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
// Memory access library single burst read transfer common core logic. This
// carries out a single read burst transfer, with data being copied to a 64-bit
// wide SMI data output.
//

`timescale 1ns/1ps

// Frame type identifiers - should probably move to a common package.
`define READ_REQ_ID_BYTE   8'h02
`define READ_RESP_ID_BYTE  8'hFD

// Constants specifying the supported SMI memory read options.
`define SMI_MEM_READ_OPT_DEFAULT 8'h00 // Use default buffered read options.
`define SMI_MEM_READ_OPT_DIRECT  8'h01 // Perform direct unbuffered read.

module smiMemLibReadBurstCore
  (paramsValid, paramBurstAddr, paramBurstLen, paramBurstOpts, paramsStop,
  readValid, readEofc, readData, readStop, doneValid, doneStatusOk, doneStop,
  smiReqValid, smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc,
  smiRespData, smiRespStop, clk, srst);

// Specifies the internal FIFO depths (between 3 and 128 entries).
parameter FifoSize = 16;

// Specify burst parameter inputs.
input        paramsValid;
input [63:0] paramBurstAddr;
input [15:0] paramBurstLen;
input [7:0]  paramBurstOpts;
output       paramsStop;

// Specify read data outputs.
output        readValid;
output [7:0]  readEofc;
output [63:0] readData;
input         readStop;

// Specify transaction done outputs.
output doneValid;
output doneStatusOk;
input  doneStop;

// Specify SMI request outputs.
output        smiReqValid;
output [7:0]  smiReqEofc;
output [63:0] smiReqData;
input         smiReqStop;

// Specify SMI response inputs.
input        smiRespValid;
input [7:0]  smiRespEofc;
input [63:0] smiRespData;
output       smiRespStop;

// Clock and reset.
input clk;
input srst;

// Specifies the state space for the request transmit state machine.
parameter [1:0]
  RequestReset = 0,
  RequestIdle = 1,
  RequestTx1 = 2,
  RequestTx2 = 3;

// Parameter input registers.
reg [63:0] paramBurstAddr_q;
reg [15:0] paramBurstLen_q;
reg [7:0]  paramBurstOpts_q;

// SMI request state machine signals.
reg [1:0]  smiReqState_d;
reg [1:0]  smiReqState_q;

// SMI request buffered output signals.
reg        smiReqBufValid;
reg [7:0]  smiReqBufEofc;
reg [63:0] smiReqBufData;
wire       smiReqBufStop;

wire [31:0] headerData;

// Implement parameter input registers.
always @(posedge clk)
begin
  if (smiReqState_q == RequestIdle)
  begin
    paramBurstAddr_q <= paramBurstAddr;
    paramBurstLen_q <= paramBurstLen;
    paramBurstOpts_q <= paramBurstOpts;
  end
end

assign paramsStop = (smiReqState_q == RequestIdle) ? 1'b0 : 1'b1;

// Implement combinatorial logic for burst request state machine.
always @(smiReqState_q, paramsValid, paramBurstAddr_q, paramBurstLen_q,
  paramBurstOpts_q, smiReqBufStop)
begin

  // Hold current state by default.
  smiReqState_d = smiReqState_q;
  smiReqBufValid = 1'b0;
  smiReqBufEofc = 8'd0;
  smiReqBufData = 64'd0;

  // Implement state machine.
  case (smiReqState_q)

    // Transmit request flit 1.
    RequestTx1 :
    begin
      smiReqBufValid = 1'b1;
      smiReqBufData [7:0] = `READ_REQ_ID_BYTE;
      smiReqBufData [15:8] = paramBurstOpts_q;
      smiReqBufData [63:32] = paramBurstAddr_q [31:0];
      if (~smiReqBufStop)
        smiReqState_d = RequestTx2;
    end

    // Transmit request flit 2.
    RequestTx2 :
    begin
      smiReqBufValid = 1'b1;
      smiReqBufEofc = 8'd6;
      smiReqBufData [31:0] = paramBurstAddr_q [63:32];
      smiReqBufData [47:32] = paramBurstLen_q;
      if (~smiReqBufStop)
        smiReqState_d = RequestIdle;
    end

    // From the idle state, wait until the transfer parameters are valid.
    RequestIdle :
    begin
      if (paramsValid)
        smiReqState_d = RequestTx1;
    end

    // From the reset state, transition to the idle state.
    default :
    begin
      smiReqState_d = RequestIdle;
    end
  endcase

end

// Implement sequential logic for burst request state machine.
always @(posedge clk)
begin
  if (srst)
    smiReqState_q <= RequestReset;
  else
    smiReqState_q <= smiReqState_d;
end

// Insert double buffer on SMI request output.
smiSelfLinkDoubleBuffer #(72) smiReqBuffer
  (smiReqBufValid, { smiReqBufEofc, smiReqBufData }, smiReqBufStop, smiReqValid,
  { smiReqEofc, smiReqData }, smiReqStop, clk, srst);

// Implement header extraction on read responses.
smiHeaderExtractPf1 #(8, 4, FifoSize) smiHeaderExtraction
  (smiRespValid, smiRespEofc, smiRespData, smiRespStop, doneValid, headerData,
  doneStop, readValid, readEofc, readData, readStop, clk, srst);

// Map Header signals to done status output. The status bits at headerData[9:8]
// correspond to the standard AXI response encoding and the command byte is
// also checked to ensure it is a valid response frame.
assign doneStatusOk =
  (headerData[7:0] == `READ_RESP_ID_BYTE) ? ~headerData [9] : 1'b0;

endmodule
