//
// Copyright 2017 ReconfigureIO
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Implementation of the scalable memory interface (SMI) to ARM AXI read bus
// adaptor. This assumes that the SMI request frames have already been filtered
// on the frame type identifier field and are known to be read requests.
//
// The following signals are not included on the AXI-4 interfaces. If connecting
// to a fabric or component that supports these signals, these constant values
// should be used:
//      Signal          Value
//      AxBURST[1:0]    0b01 (Incremental Bursts Only)
//      AxLOCK[1:0]     0b00
//      AxPROT[2:0]     0b000
//      AxQOS[3:0]      0b0000
//      AxREGION[3:0]   0b0000
//

`timescale 1ns/1ps

// Frame type identifiers - should probably move to a common package.
`define READ_RESP_ID_BYTE  8'hFD

module smiAxiMemReadAdaptor
  (smiReqReady, smiReqEofc, smiReqData, smiReqStop, smiRespReady, smiRespEofc,
  smiRespData, smiRespStop, axiARValid, axiARReady, axiARId, axiARAddr,
  axiARLen, axiARSize, axiARCache, axiRValid, axiRReady, axiRId, axiRData,
  axiRResp, axiRLast, axiReset, clk, srst);

// Specifies the number of bits required to address individual bytes within the
// AXI data signal. This also determines the width of the data signal.
parameter DataIndexSize = 4;

// Specifies the width of the AXI ID signal. This also determines the number
// of transactions which may be 'in flight' through the adaptor at any given
// time.
parameter AxiIdWidth = 4;

// Specifies the internal FIFO depths (between 3 and 128 entries).
parameter FifoSize = 16;

// Derives the width of the data input and output ports. Minimum of 128 bits.
parameter DataWidth = (1 << DataIndexSize) * 8;

// Derives the maximum number of 'in flight' read transactions.
parameter MaxReadIds = (1 << AxiIdWidth);

// Specifies the state space for the read request dispatch state machine.
parameter [1:0]
  RequestIdle = 0,
  RequestDispatch = 1,
  RequestDrain = 2;

// Specifies the state space for the read response handler state machine.
parameter [2:0]
  ResponseReset = 0,
  ResponseIdle = 1,
  ResponseSetPacking = 2,
  ResponseSetHeader = 3,
  ResponseDrain = 4;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;
input axiReset;

// Specifies the 'upstream' scalable memory interface ports.
input                 smiReqReady;
input [7:0]           smiReqEofc;
input [DataWidth-1:0] smiReqData;
output                smiReqStop;

output                 smiRespReady;
output [7:0]           smiRespEofc;
output [DataWidth-1:0] smiRespData;
input                  smiRespStop;

// Specifies the 'downstream' AXI read address ports.
output                  axiARValid;
input                   axiARReady;
output [AxiIdWidth-1:0] axiARId;
output [63:0]           axiARAddr;
output [7:0]            axiARLen;
output [2:0]            axiARSize;
output [3:0]            axiARCache;

// Specifies the 'downstream' AXI read data ports.
input                  axiRValid;
output                 axiRReady;
input [AxiIdWidth-1:0] axiRId;
input [DataWidth-1:0]  axiRData;
input [1:0]            axiRResp;
input                  axiRLast;

// Specifies the SMI request and AXI read data response input registers.
reg                 smiReqReady_q;
reg [7:0]           smiReqEofc_q;
reg [DataWidth-1:0] smiReqData_q;
reg                 smiReqHalt;

wire                  axiRBufValid;
wire [AxiIdWidth-1:0] axiRBufId;
wire [DataWidth-1:0]  axiRBufData;
wire [1:0]            axiRBufResp;
wire                  axiRBufLast;
wire                  axiRBufStop;

// Forked control line signals for read data response input.
wire       axiRCtrlValid;
reg        axiRCtrlHalt;
wire       axiRDataValid;
wire       axiRDataHalt;

// Specifies the buffered AXI address signals.
reg         axiARBufValid;
wire        axiARBufStop;

// verilator lint_off UNUSED
wire [15:0] axiARLenBuf;
// verilator lint_on UNUSED

reg                  axiARValid_q;
reg [AxiIdWidth-1:0] axiARId_q;
reg [63:0]           axiARAddr_q;
reg [7:0]            axiARLen_q;
reg                  axiARCacheBuf_q;

// Specifies the signals used for read transaction ID tracking FIFO.
reg                  readIdFifoPop;
reg [AxiIdWidth-1:0] readIdFifoOutput;
reg [AxiIdWidth-1:0] readIdFifoData [MaxReadIds-1:0];

reg                  readIdFifoPush_d;
reg [AxiIdWidth-1:0] readIdFifoInput_d;
reg                  readIdFifoEmpty_d;
reg [AxiIdWidth-1:0] readIdFifoIndex_d;

reg                  readIdFifoPush_q;
reg [AxiIdWidth-1:0] readIdFifoInput_q;
reg                  readIdFifoEmpty_q;
reg [AxiIdWidth-1:0] readIdFifoIndex_q;

// Specifies the signals used for the parameter cache RAMs.
reg        pCacheWrite;
reg        pCacheRead;
reg [15:0] pCacheSmiTags [MaxReadIds-1:0];
reg [7:0]  pCacheAddrOffsets [MaxReadIds-1:0];
reg [7:0]  pCacheDataLengths [MaxReadIds-1:0];

reg [15:0] paramSmiTag;
reg [7:0]  paramAddrOffset;
reg [7:0]  paramDataLength;

// Specifies the signals used for the read request dispatch state machine.
reg [1:0] dispatchState_d;
reg [1:0] dispatchState_q;

// Specifies the signals used for the read response processing state machine.
reg [2:0]            responseState_d;
reg [1:0]            responseStatus_d;
reg [AxiIdWidth-1:0] axiIdInit_d;
reg [2:0]            responseState_q;
reg [1:0]            responseStatus_q;
reg [AxiIdWidth-1:0] axiIdInit_q;

// Specifies the signals used for the packed frame datapath.
wire                 dataFrameReady;
wire [7:0]           dataFrameEofc;
wire [DataWidth-1:0] dataFrameData;
wire                 dataFrameStop;

// Specifies the signals used for the frame control inputs.
reg         packSetupValid;
wire        packSetupStop;
reg         headerValid;
wire [31:0] headerData;
wire        headerStop;

// Miscellaneous signals.
integer i;

// Implement resettable SMI request registers.
always @(posedge clk)
begin
  if (srst)
  begin
    smiReqReady_q <= 1'b0;
  end
  else if (~(smiReqReady_q & smiReqHalt))
    smiReqReady_q <= smiReqReady;
end

// Implement non-resettable SMI request registers.
always @(posedge clk)
begin
  if (~(smiReqReady_q & smiReqHalt))
  begin
    smiReqEofc_q <= smiReqEofc;
    smiReqData_q <= smiReqData;
  end
end

assign smiReqStop = smiReqReady_q & smiReqHalt;

// Instantiate AXI read data input buffer.
smiAxiInputBuffer #(DataWidth+AxiIdWidth+3) axiReadBuffer
  (axiRValid, {axiRId, axiRLast, axiRResp, axiRData}, axiRReady, axiRBufValid,
  {axiRBufId, axiRBufLast, axiRBufResp, axiRBufData}, axiRBufStop, clk, axiReset);

// Fork the AXI read data response signals.
smiSelfFlowForkControl #(2) readDataFork
  (axiRBufValid, axiRBufStop, {axiRCtrlValid, axiRDataValid},
  {axiRCtrlHalt, axiRDataHalt}, clk, srst);

// Implement combinatorial logic for read ID tracking FIFO.
always @(readIdFifoEmpty_q, readIdFifoIndex_q, readIdFifoPush_q, readIdFifoPop)
begin

  // Hold current state by default.
  readIdFifoEmpty_d = readIdFifoEmpty_q;
  readIdFifoIndex_d = readIdFifoIndex_q;

  // Update the FIFO empty and index state on push only.
  if (readIdFifoPush_q & ~readIdFifoPop)
  begin
    if (readIdFifoEmpty_q)
      readIdFifoEmpty_d = 1'b0;
    else
      readIdFifoIndex_d = readIdFifoIndex_q + 1;
  end

  // Update the FIFO empty and index state on pop only.
  if (readIdFifoPop & ~readIdFifoPush_q)
  begin
    if (readIdFifoIndex_q == 0)
      readIdFifoEmpty_d = 1'b1;
    else
      readIdFifoIndex_d = readIdFifoIndex_q - 1;
  end
end

// Implement resettable control logic for read ID tracking FIFO.
always @(posedge clk)
begin
  if (srst)
  begin
    readIdFifoEmpty_q <= 1'b1;
    for (i = 0; i < AxiIdWidth; i = i + 1)
      readIdFifoIndex_q [i] <= 1'b0;
  end
  else
  begin
    readIdFifoEmpty_q <= readIdFifoEmpty_d;
    readIdFifoIndex_q <= readIdFifoIndex_d;
  end
end

// Implement non-resettable datapath registers for read ID tracking FIFO.
always @(posedge clk)
begin
  if (readIdFifoPush_q)
  begin
    readIdFifoData [0] <= readIdFifoInput_q;
    for (i = 1; i < MaxReadIds; i = i + 1)
      readIdFifoData [i] <= readIdFifoData [i-1];
  end
  if (readIdFifoPop)
  begin
    readIdFifoOutput <= readIdFifoData [readIdFifoIndex_q];
  end
end

// Implement parameter cache RAMs.
always @(posedge clk)
begin
  if (pCacheWrite)
  begin
    pCacheSmiTags [readIdFifoOutput] <= smiReqData_q [31:16];
    pCacheAddrOffsets [readIdFifoOutput] <= smiReqData_q [39:32];
    pCacheDataLengths [readIdFifoOutput] <= smiReqData_q [103:96];
  end
  if (pCacheRead)
  begin
    paramSmiTag <= pCacheSmiTags [axiRBufId];
    paramAddrOffset <= pCacheAddrOffsets [axiRBufId];
    paramDataLength <= pCacheDataLengths [axiRBufId];
  end
end

// Combinatorial logic for read request dispatch state machine.
always @(dispatchState_q, smiReqReady_q, smiReqData_q, smiReqEofc_q,
  readIdFifoEmpty_q, axiARBufStop)
begin

  // Hold current state by default.
  dispatchState_d = dispatchState_q;
  readIdFifoPop = 1'b0;
  axiARBufValid = 1'b0;
  smiReqHalt = 1'b1;
  pCacheWrite = 1'b0;

  // Implement state machine.
  case (dispatchState_q)

    // Transfer the read request to the AXI read address output.
    RequestDispatch :
    begin
      axiARBufValid = 1'b1;
      pCacheWrite = 1'b1;
      if (~axiARBufStop)
        dispatchState_d = RequestDrain;
    end

    // Drain the SMI request input frame.
    RequestDrain :
    begin
      smiReqHalt = 1'b0;
      if (smiReqEofc_q != 8'd0)
        dispatchState_d = RequestIdle;
    end

    // From the idle state, wait for a valid read request.
    default :
    begin
      if (smiReqReady_q & ~readIdFifoEmpty_q)
      begin
        dispatchState_d = RequestDispatch;
        readIdFifoPop = 1'b1;
      end
    end
  endcase

end

// Sequential logic for read request dispatch state machine.
always @(posedge clk)
begin
  if (srst)
    dispatchState_q <= RequestIdle;
  else
    dispatchState_q <= dispatchState_d;
end

// To calculate the AXI burst length we need to take into account the number
// of bytes in the burst and the address offset within the first word. This
// yields a 16-bit value which we slice down to 8 bits later.
assign axiARLenBuf = (smiReqData_q [111:96] - 16'd1 +
  (smiReqData_q [47:32] & ((16'd1 << DataIndexSize) - 16'd1))) >> DataIndexSize;

// Buffer the AXI read address output using a toggle buffer.
always @(posedge clk)
begin
  if (axiReset)
  begin
    axiARValid_q <= 1'b0;
    axiARLen_q <= 8'd0;
    axiARAddr_q <= 64'd0;
    for (i = 0; i < AxiIdWidth; i = i + 1)
      axiARId_q [i] <= 1'b0;
    axiARCacheBuf_q <= 1'b0;
  end
  else if (axiARValid_q)
  begin
    axiARValid_q <= ~axiARReady;
  end
  else if (axiARBufValid)
  begin
    axiARValid_q <= 1'b1;
    axiARLen_q <= axiARLenBuf[7:0];
    axiARAddr_q <= smiReqData_q [95:32];
    axiARId_q <= readIdFifoOutput;
    axiARCacheBuf_q <= ~smiReqData_q [8];
  end
end

assign axiARBufStop = axiARValid_q;
assign axiARValid = axiARValid_q;
assign axiARId = axiARId_q;
assign axiARLen = axiARLen_q;
assign axiARAddr = axiARAddr_q;
assign axiARSize = DataIndexSize [2:0];
assign axiARCache = { 3'b001, axiARCacheBuf_q };

// Combinatorial logic for read response processing state machine.
always @(responseState_q, responseStatus_q, axiIdInit_q, readIdFifoInput_q,
  axiRCtrlValid, axiRBufId, axiRBufResp, axiRBufLast, packSetupStop, headerStop)
begin

  // Hold current state by default.
  responseState_d = responseState_q;
  responseStatus_d = responseStatus_q;
  axiIdInit_d = axiIdInit_q;
  readIdFifoPush_d = 1'b0;
  readIdFifoInput_d = readIdFifoInput_q;
  pCacheRead = 1'b0;
  axiRCtrlHalt = 1'b1;
  packSetupValid = 1'b0;
  headerValid = 1'b0;

  // Implement state machine.
  case (responseState_q)

    // In the reset state, push the initial AXI transaction ID values into the
    // read ID tracking FIFO.
    ResponseReset :
    begin
      readIdFifoPush_d = 1'b1;
      readIdFifoInput_d = axiIdInit_q;
      axiIdInit_d = axiIdInit_q + 1;
      if ({1'b0, axiIdInit_q} == MaxReadIds [AxiIdWidth:0] - 1)
        responseState_d = ResponseIdle;
    end

    // Set the data packing parameters.
    ResponseSetPacking :
    begin
      axiRCtrlHalt = axiRBufLast;
      packSetupValid = 1'b1;
      if (~packSetupStop)
        responseState_d = ResponseSetHeader;
    end

    // Set the header parameters.
    ResponseSetHeader :
    begin
      axiRCtrlHalt = axiRBufLast;
      headerValid = 1'b1;
      if (~headerStop)
        responseState_d = ResponseDrain;
    end

    // Drain the control input FIFO.
    ResponseDrain :
    begin
      axiRCtrlHalt = 1'b0;
      if (axiRCtrlValid & axiRBufLast)
        responseState_d = ResponseIdle;
    end

    // From the idle state, wait for a valid read response.
    default :
    begin
      pCacheRead = 1'b1;
      axiRCtrlHalt = axiRBufLast;
      responseStatus_d = axiRBufResp;
      readIdFifoInput_d = axiRBufId;
      if (axiRCtrlValid)
      begin
        responseState_d = ResponseSetPacking;
        readIdFifoPush_d = 1'b1;
      end
    end
  endcase
end

// Resettable control registers for read response state machine.
always @(posedge clk)
begin
  if (srst)
  begin
    responseState_q <= ResponseReset;
    readIdFifoPush_q <= 1'b0;
    for (i = 0; i < AxiIdWidth; i = i + 1)
      axiIdInit_q[i] <= 1'b0;
  end
  else
  begin
    responseState_q <= responseState_d;
    readIdFifoPush_q <= readIdFifoPush_d;
    axiIdInit_q <= axiIdInit_d;
  end
end

// Non-resettable datapath registers for read response state machine.
always @(posedge clk)
begin
  responseStatus_q <= responseStatus_d;
  readIdFifoInput_q <= readIdFifoInput_d;
end

// Assemble the frame header.
assign headerData = { paramSmiTag, 6'd0, responseStatus_q, `READ_RESP_ID_BYTE };

// Implement flit byte packing on the read data bus.
smiFlitDataPack #(DataWidth/8) flitDataPack
  (packSetupValid, paramAddrOffset, paramDataLength, packSetupStop,
  axiRDataValid, axiRBufData, axiRBufLast, axiRDataHalt, dataFrameReady,
  dataFrameEofc, dataFrameData, dataFrameStop, clk, srst);

// Implement read frame header injection.
smiHeaderInjectPf1 #(DataWidth/8, 4, FifoSize) headerInjection
  (headerValid, headerData, headerStop, dataFrameReady, dataFrameEofc,
  dataFrameData, dataFrameStop, smiRespReady, smiRespEofc, smiRespData,
  smiRespStop, clk, srst);

endmodule
