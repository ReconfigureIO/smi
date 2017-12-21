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
// Memory access library single burst write transfer common core logic. This
// carries out a single write burst transfer, with data being copied from a
// 64-bit wide SMI data input.
//

`timescale 1ns/1ps

// Frame type identifiers - should probably move to a common package.
`define WRITE_REQ_ID_BYTE   8'h01
`define WRITE_RESP_ID_BYTE  8'hFE

// Constants specifying the supported SMI memory write options.
`define SMI_MEM_WRITE_OPT_DEFAULT 8'h00 // Use default buffered write options.
`define SMI_MEM_WRITE_OPT_DIRECT  8'h01 // Perform direct unbuffered write.

module smiMemLibWriteBurstCore
  (paramsValid, paramBurstAddr, paramBurstLen, paramBurstOpts, paramsStop,
  writeValid, writeEofc, writeData, writeStop, doneValid, doneStatusOk,
  doneStop, smiReqValid, smiReqEofc, smiReqData, smiReqStop, smiRespValid,
  smiRespEofc, smiRespData, smiRespStop, clk, srst);

// Specifies the internal FIFO depths (between 3 and 128 entries).
parameter FifoSize = 16;

// Specify burst parameter inputs.
input        paramsValid;
input [63:0] paramBurstAddr;
input [15:0] paramBurstLen;
input [7:0]  paramBurstOpts;
output       paramsStop;

// Specify write data inputs.
input        writeValid;
input [7:0]  writeEofc;
input [63:0] writeData;
output       writeStop;

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

// Specifies the state space for the response receive state machine.
parameter [1:0]
  ReceiveIdle = 0,
  ReceiveStatus = 1,
  ReceiveDrain = 2;

// Respone state machine signals.
reg [1:0] receiveState_d;
reg       doneStatusOk_d;
reg       doneReady;
reg       smiRespHalt;

reg [1:0] receiveState_q;
reg       doneStatusOk_q;

// Miscellaneous signals.
wire [111:0] headerData;

// Inject the SMI header into the write data stream.
assign headerData = { paramBurstLen, paramBurstAddr, 16'd0,
  paramBurstOpts, `WRITE_REQ_ID_BYTE };

smiHeaderInjectPf2 #(8, 14, FifoSize) smiHeaderInsertion
  (paramsValid, headerData, paramsStop, writeValid, writeEofc, writeData,
  writeStop, smiReqValid, smiReqEofc, smiReqData, smiReqStop, clk, srst);

// Implement combinatorial logic for checking the response.
always @(receiveState_q, doneStatusOk_q, smiRespValid, smiRespEofc, smiRespData,
  doneStop)
begin

  // Hold current state by default.
  receiveState_d = receiveState_q;
  doneStatusOk_d = doneStatusOk_q;
  doneReady = 1'b0;
  smiRespHalt = 1'b1;

  // Implement state machine.
  case (receiveState_q)

    // Forward the status response.
    ReceiveStatus :
    begin
      doneReady = 1'b1;
      if (~doneStop)
        receiveState_d = ReceiveDrain;
    end

    // Drain the response message.
    ReceiveDrain :
    begin
      smiRespHalt = 1'b0;
      if (smiRespValid && (smiRespEofc != 8'b0))
        receiveState_d = ReceiveIdle;
    end

    // From the idle state, wait for the next status response.
    default :
    begin
      if (smiRespData [7:0] == `WRITE_RESP_ID_BYTE)
        doneStatusOk_d = ~smiRespData [9];
      else
        doneStatusOk_d = 1'b0;
      if (smiRespValid)
        receiveState_d = ReceiveStatus;
    end
  endcase

end

// Implement sequential logic for checking the response.
always @(posedge clk)
begin
  if (srst)
  begin
    receiveState_q <= ReceiveIdle;
    doneStatusOk_q <= 1'b0;
  end
  else
  begin
    receiveState_q <= receiveState_d;
    doneStatusOk_q <= doneStatusOk_d;
  end
end

assign doneValid = doneReady;
assign doneStatusOk = doneStatusOk_q;
assign smiRespStop = smiRespHalt;

endmodule
