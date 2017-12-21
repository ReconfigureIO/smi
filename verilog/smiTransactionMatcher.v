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
// Implements tag based transaction matching between an SMI request channel and
// a corresponding SMI response channel. The 16-bit matched tags consist of an
// upper fixed six bits which apply to all tags associated with this transaction
// matcher and a lower ten bits which may used to index up to 1024 in-flight
// transactions.
//

`timescale 1ns/1ps

module smiTransactionMatcher
  (smiReqInReady, smiReqInEofc, smiReqInData, smiReqInStop, smiReqOutReady,
  smiReqOutEofc, smiReqOutData, smiReqOutStop, smiRespInReady, smiRespInEofc,
  smiRespInData, smiRespInStop, smiRespOutReady, smiRespOutEofc, smiRespOutData,
  smiRespOutStop, clk, srst);

// Specifes the width of the data input and output ports. Must be at least 4.
parameter FlitWidth = 4;

// Specifies the value of the fixed portion of the tag, in the range 0 to 63.
parameter TagFixedField = 0;

// Specifies the width of the ID part of the tag. This also determines the
// number of transactions which may be 'in flight' through the adaptor at any
// given time. Maximum value of 10.
parameter TagIdWidth = 2;

// Derives the width of the data input and output ports.
parameter DataWidth = FlitWidth * 8;

// Derives the maximum number of 'in flight' transactions.
parameter MaxTagIds = (1 << TagIdWidth);

// Derives the mask for unused end of frame control bits.
parameter EofcMask = 2 * FlitWidth - 1;

// Specifies the state space for the request dispatch state machine.
parameter [1:0]
  RequestIdle = 0,
  RequestDispatch = 1,
  RequestTransfer = 2;

// Specifies the state space for the response handler state machine.
parameter [1:0]
  ResponseReset = 0,
  ResponseIdle = 1,
  ResponseDispatch = 2,
  ResponseTransfer = 3;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the input transaction request and response ports.
input                 smiReqInReady;
input [7:0]           smiReqInEofc;
input [DataWidth-1:0] smiReqInData;
output                smiReqInStop;

input                 smiRespInReady;
input [7:0]           smiRespInEofc;
input [DataWidth-1:0] smiRespInData;
output                smiRespInStop;

// Specifies the output transaction request and response ports.
output                 smiReqOutReady;
output [7:0]           smiReqOutEofc;
output [DataWidth-1:0] smiReqOutData;
input                  smiReqOutStop;

output                 smiRespOutReady;
output [7:0]           smiRespOutEofc;
output [DataWidth-1:0] smiRespOutData;
input                  smiRespOutStop;

// Specifies SMI input register signals.
reg                 smiReqInReady_q;
reg [7:0]           smiReqInEofc_q;
reg [DataWidth-1:0] smiReqInData_q;
reg                 smiReqInHalt;

reg                 smiRespInReady_q;
reg [7:0]           smiRespInEofc_q;
reg [DataWidth-1:0] smiRespInData_q;
reg                 smiRespInHalt;

// Specifies the signals used for transaction ID tracking FIFO.
reg                  tagIdFifoPop;
reg [TagIdWidth-1:0] tagIdFifoOutput;
reg [TagIdWidth-1:0] tagIdFifoData [MaxTagIds-1:0];

reg                  tagIdFifoPush_d;
reg [TagIdWidth-1:0] tagIdFifoInput_d;
reg                  tagIdFifoEmpty_d;
reg [TagIdWidth-1:0] tagIdFifoIndex_d;

reg                  tagIdFifoPush_q;
reg [TagIdWidth-1:0] tagIdFifoInput_q;
reg                  tagIdFifoEmpty_q;
reg [TagIdWidth-1:0] tagIdFifoIndex_q;

// Specifies the signals used for the parameter cache RAMs.
reg        pCacheWrite;
reg        pCacheRead;
reg [15:0] pCacheSmiTags [MaxTagIds-1:0];
reg [15:0] paramSmiTag;

// Specifies the signals used for the request dispatch state machine.
reg [1:0] requestState_d;
reg [1:0] requestState_q;

// Specifies the signals used for the read response processing state machine.
reg [1:0]            responseState_d;
reg [TagIdWidth-1:0] tagIdInit_d;
reg [1:0]            responseState_q;
reg [TagIdWidth-1:0] tagIdInit_q;

// Specifies the buffered output signals.
reg                  smiReqBufReady;
reg [7:0]            smiReqBufEofc;
reg [DataWidth-1:0]  smiReqBufData;
wire                 smiReqBufStop;
wire [DataWidth+7:0] smiReqBufVec;

reg                  smiRespBufReady;
reg [7:0]            smiRespBufEofc;
reg [DataWidth-1:0]  smiRespBufData;
wire                 smiRespBufStop;
wire [DataWidth+7:0] smiRespBufVec;

// Miscellaneous signals.
integer i;

// Implement resettable input control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    smiReqInReady_q <= 1'b0;
    smiRespInReady_q <= 1'b0;
  end
  else
  begin
    if (~(smiReqInReady_q & smiReqInHalt))
      smiReqInReady_q <= smiReqInReady;
    if (~(smiRespInReady_q & smiRespInHalt))
      smiRespInReady_q <= smiRespInReady;
  end
end

// Implement non-resettable input data registers.
always @(posedge clk)
begin
  if (~(smiReqInReady_q & smiReqInHalt))
  begin
    smiReqInEofc_q <= smiReqInEofc & EofcMask[7:0];
    smiReqInData_q <= smiReqInData;
  end
  if (~(smiRespInReady_q & smiRespInHalt))
  begin
    smiRespInEofc_q <= smiRespInEofc & EofcMask[7:0];
    smiRespInData_q <= smiRespInData;
  end
end

assign smiReqInStop = smiReqInReady_q & smiReqInHalt;
assign smiRespInStop = smiRespInReady_q & smiRespInHalt;

// Implement combinatorial logic for tag ID tracking FIFO.
always @(tagIdFifoEmpty_q, tagIdFifoIndex_q, tagIdFifoPush_q, tagIdFifoPop)
begin

  // Hold current state by default.
  tagIdFifoEmpty_d = tagIdFifoEmpty_q;
  tagIdFifoIndex_d = tagIdFifoIndex_q;

  // Update the FIFO empty and index state on push only.
  if (tagIdFifoPush_q & ~tagIdFifoPop)
  begin
    if (tagIdFifoEmpty_q)
      tagIdFifoEmpty_d = 1'b0;
    else
      tagIdFifoIndex_d = tagIdFifoIndex_q + 1;
  end

  // Update the FIFO empty and index state on pop only.
  if (tagIdFifoPop & ~tagIdFifoPush_q)
  begin
    if (tagIdFifoIndex_q == 0)
      tagIdFifoEmpty_d = 1'b1;
    else
      tagIdFifoIndex_d = tagIdFifoIndex_q - 1;
  end
end

// Implement resettable control logic for read ID tracking FIFO.
always @(posedge clk)
begin
  if (srst)
  begin
    tagIdFifoEmpty_q <= 1'b1;
    for (i = 0; i < TagIdWidth; i = i + 1)
      tagIdFifoIndex_q [i] <= 1'b0;
  end
  else
  begin
    tagIdFifoEmpty_q <= tagIdFifoEmpty_d;
    tagIdFifoIndex_q <= tagIdFifoIndex_d;
  end
end

// Implement non-resettable datapath registers for read ID tracking FIFO.
always @(posedge clk)
begin
  if (tagIdFifoPush_q)
  begin
    tagIdFifoData [0] <= tagIdFifoInput_q;
    for (i = 1; i < MaxTagIds; i = i + 1)
      tagIdFifoData [i] <= tagIdFifoData [i-1];
  end
  if (tagIdFifoPop)
  begin
    tagIdFifoOutput <= tagIdFifoData [tagIdFifoIndex_q];
  end
end

// Implement parameter cache RAMs.
always @(posedge clk)
begin
  if (pCacheWrite)
  begin
    pCacheSmiTags [tagIdFifoOutput] <= smiReqInData_q [31:16];
  end
  if (pCacheRead)
  begin
    paramSmiTag <= pCacheSmiTags [smiRespInData_q [TagIdWidth+15:16]];
  end
end

// Combinatorial logic for write request dispatch state machine.
always @(requestState_q, smiReqInReady_q, smiReqInEofc_q, smiReqInData_q,
  tagIdFifoEmpty_q, tagIdFifoOutput, smiReqBufStop)
begin

  // Hold current state by default.
  requestState_d = requestState_q;
  tagIdFifoPop = 1'b0;
  smiReqBufReady = 1'b0;
  smiReqBufEofc = smiReqInEofc_q;
  smiReqBufData = smiReqInData_q;
  smiReqInHalt = 1'b1;
  pCacheWrite = 1'b0;

  // Implement state machine.
  case (requestState_q)

    // Dispatch the first flit, overwriting the tag value.
    RequestDispatch :
    begin
      smiReqBufReady = 1'b1;
      smiReqBufData [31:16] = { TagFixedField[5:0], 10'd0 };
      smiReqBufData [TagIdWidth+15:16] = tagIdFifoOutput;
      smiReqInHalt = smiReqBufStop;
      pCacheWrite = 1'b1;
      if (~smiReqBufStop)
      begin
        if (smiReqInEofc_q == 8'd0)
          requestState_d = RequestTransfer;
        else
          requestState_d = RequestIdle;
      end
    end

    // Transfer residual flits.
    RequestTransfer :
    begin
      smiReqBufReady = smiReqInReady_q;
      smiReqInHalt = smiReqBufStop;
      if (smiReqInReady_q & ~smiReqBufStop)
      begin
        if (smiReqInEofc_q != 8'd0)
          requestState_d = RequestIdle;
      end
    end

    // From the idle state, wait for a valid transaction request.
    default :
    begin
      if (smiReqInReady_q & ~tagIdFifoEmpty_q)
      begin
        requestState_d = RequestDispatch;
        tagIdFifoPop = 1'b1;
      end
    end
  endcase

end

// Sequential logic for write request dispatch state machine.
always @(posedge clk)
begin
  if (srst)
    requestState_q <= RequestIdle;
  else
    requestState_q <= requestState_d;
end

// Combinatorial logic for read response processing state machine.
always @(responseState_q, tagIdInit_q, smiRespInReady_q, smiRespInEofc_q,
  smiRespInData_q, paramSmiTag, smiRespBufStop)
begin

  // Hold current state by default.
  responseState_d = responseState_q;
  tagIdInit_d = tagIdInit_q;
  tagIdFifoPush_d = 1'b0;
  tagIdFifoInput_d = smiRespInData_q [TagIdWidth+15:16];
  smiRespBufReady = 1'b0;
  smiRespBufEofc = smiRespInEofc_q;
  smiRespBufData = smiRespInData_q;
  pCacheRead = 1'b0;
  smiRespInHalt = 1'b1;

  // Implement state machine.
  case (responseState_q)

    // In the reset state, push the initial AXI transaction ID values into the
    // read ID tracking FIFO.
    ResponseReset :
    begin
      tagIdFifoPush_d = 1'b1;
      tagIdFifoInput_d = tagIdInit_q;
      tagIdInit_d = tagIdInit_q + 1;
      if ({1'b0, tagIdInit_q} == MaxTagIds [TagIdWidth:0] - 1)
        responseState_d = ResponseIdle;
    end

    // Dispatch the first flit, overwriting the tag value.
    ResponseDispatch :
    begin
      smiRespBufReady = 1'b1;
      smiRespBufData [31:16] = paramSmiTag;
      smiRespInHalt = smiRespBufStop;
      if (~smiRespBufStop)
      begin
        if (smiRespInEofc_q == 8'd0)
          responseState_d = ResponseTransfer;
        else
          responseState_d = ResponseIdle;
      end
    end

    // Transfer residual flits.
    ResponseTransfer :
    begin
      smiRespBufReady = smiRespInReady_q;
      smiRespInHalt = smiRespBufStop;
      if (smiRespInReady_q & ~smiRespBufStop)
      begin
        if (smiRespInEofc_q != 8'd0)
          responseState_d = ResponseIdle;
      end
    end

    // From the idle state, wait for a valid read response.
    default :
    begin
      pCacheRead = 1'b1;
      if (smiRespInReady_q)
      begin
        responseState_d = ResponseDispatch;
        tagIdFifoPush_d = 1'b1;
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
    tagIdFifoPush_q <= 1'b0;
    for (i = 0; i < TagIdWidth; i = i + 1)
      tagIdInit_q[i] <= 1'b0;
  end
  else
  begin
    responseState_q <= responseState_d;
    tagIdFifoPush_q <= tagIdFifoPush_d;
    tagIdInit_q <= tagIdInit_d;
  end
end

// Non-resettable datapath registers for read response state machine.
always @(posedge clk)
begin
  tagIdFifoInput_q <= tagIdFifoInput_d;
end

// Implement FIFO buffer on the output flits.
smiSelfLinkDoubleBuffer #(DataWidth+8) smiReqOutBuf
  (smiReqBufReady, { smiReqBufEofc, smiReqBufData }, smiReqBufStop,
  smiReqOutReady, smiReqBufVec, smiReqOutStop, clk, srst);

assign smiReqOutEofc = smiReqBufVec [DataWidth+7:DataWidth];
assign smiReqOutData = smiReqBufVec [DataWidth-1:0];

smiSelfLinkDoubleBuffer #(DataWidth+8) smiRespOutBuf
  (smiRespBufReady, { smiRespBufEofc, smiRespBufData }, smiRespBufStop,
  smiRespOutReady, smiRespBufVec, smiRespOutStop, clk, srst);

assign smiRespOutEofc = smiRespBufVec [DataWidth+7:DataWidth];
assign smiRespOutData = smiRespBufVec [DataWidth-1:0];

endmodule
