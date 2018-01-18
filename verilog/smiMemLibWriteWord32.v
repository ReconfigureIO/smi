//
// Copyright 2018 ReconfigureIO
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
// Memory access library write access module for single 32-bit data words.
//

`timescale 1ns/1ps

// Frame type identifiers - should probably move to a common package.
`define WRITE_REQ_ID_BYTE   8'h01
`define WRITE_RESP_ID_BYTE  8'hFE

module smiMemLibWriteWord32
  (paramsValid, paramWriteAddr, paramWriteOpts, paramWriteData, paramsStop,
  doneValid, doneStatusOk, doneStop, smiReqValid, smiReqEofc, smiReqData,
  smiReqStop, smiRespValid, smiRespEofc, smiRespData, smiRespStop, clk, srst);

// Specify data transfer parameter inputs.
input        paramsValid;
input [63:0] paramWriteAddr;
input [7:0]  paramWriteOpts;
input [31:0] paramWriteData;
output       paramsStop;

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

// Define the state space for the write transaction state machine.
parameter [2:0]
  WriteIdle = 0,
  WriteReqFlit1 = 1,
  WriteReqFlit2 = 2,
  WriteReqFlit3 = 3,
  WriteRespWait = 4,
  WriteRespDrain = 5,
  WriteGetStatus = 6;

// Buffered parameter signals.
wire        paramBufValid;
wire [63:0] paramBufWriteAddr;
wire [7:0]  paramBufWriteOpts;
wire [31:0] paramBufWriteData;
reg         paramBufStop;

// Buffered SMI response inputs.
wire        smiRespBufValid;
wire [7:0]  smiRespBufEofc;
wire [63:0] smiRespBufData;
reg         smiRespBufStop;

// Specify state machine signals.
reg [2:0]  writeState_d;
reg        doneStatusOk_d;

reg [2:0]  writeState_q;
reg        doneStatusOk_q;

// Buffered SMI request outputs.
reg        smiReqBufValid;
reg [7:0]  smiReqBufEofc;
reg [63:0] smiReqBufData;
wire       smiReqBufStop;

// Buffered SMI status outputs.
reg  doneBufValid;
wire doneBufStop;

// Add a toggle buffer to the parameter input.
smiSelfLinkToggleBuffer #(104) paramsBuffer
  (paramsValid, { paramWriteAddr, paramWriteOpts, paramWriteData }, paramsStop,
  paramBufValid, { paramBufWriteAddr, paramBufWriteOpts, paramBufWriteData },
  paramBufStop, clk, srst);

// Add a toggle buffer to the SMI response input.
smiSelfLinkToggleBuffer #(72) smiRespBuffer
  (smiRespValid, { smiRespEofc, smiRespData }, smiRespStop, smiRespBufValid,
  { smiRespBufEofc, smiRespBufData }, smiRespBufStop, clk, srst);

// Implement combinatorial logic for transaction state machine.
always @(writeState_q, doneStatusOk_q, paramBufValid, paramBufWriteAddr,
  paramBufWriteOpts, paramBufWriteData, smiReqBufStop, smiRespBufValid,
  smiRespBufEofc, smiRespBufData, doneBufStop)
begin

  // Hold current state by default.
  writeState_d = writeState_q;
  doneStatusOk_d = doneStatusOk_q;
  paramBufStop = 1'b1;
  doneBufValid = 1'b0;
  smiReqBufValid = 1'b0;
  smiReqBufEofc = 8'd0;
  smiReqBufData = 64'd0;
  smiRespBufStop = 1'b1;

  // Implement state machine.
  case (writeState_q)

    // Write out the first request flit.
    WriteReqFlit1 :
    begin
      smiReqBufValid = 1'b1;
      smiReqBufData [7:0] = `WRITE_REQ_ID_BYTE;
      smiReqBufData [15:8] = paramBufWriteOpts;
      smiReqBufData [63:34] = paramBufWriteAddr [31:2];
      if (~smiReqBufStop)
        writeState_d = WriteReqFlit2;
    end

    // Write out the second request flit.
    WriteReqFlit2 :
    begin
      smiReqBufValid = 1'b1;
      smiReqBufData [31:0] = paramBufWriteAddr [63:32];
      smiReqBufData [47:32] = 16'd4;
      smiReqBufData [63:48] = paramBufWriteData [15:0];
      if (~smiReqBufStop)
        writeState_d = WriteReqFlit3;
    end

    // Write out the third request flit.
    WriteReqFlit3 :
    begin
      paramBufStop = smiReqBufStop;
      smiReqBufValid = 1'b1;
      smiReqBufEofc = 8'd2;
      smiReqBufData [15:0] = paramBufWriteData [31:16];
      if (~smiReqBufStop)
        writeState_d = WriteRespWait;
    end

    // Wait for the response message.
    WriteRespWait :
    begin
      if (smiRespBufData [7:0] == `WRITE_RESP_ID_BYTE)
        doneStatusOk_d = ~smiRespBufData [9];
      else
        doneStatusOk_d = 1'b0;
      if (smiRespBufValid)
        writeState_d = WriteRespDrain;
    end

    // Drain the response frame.
    WriteRespDrain :
    begin
      smiRespBufStop = 1'b0;
      if (smiRespBufValid & (smiRespBufEofc != 8'd0))
        writeState_d = WriteGetStatus;
    end

    // Set the output status.
    WriteGetStatus :
    begin
      doneBufValid = 1'b1;
      if (~doneBufStop)
        writeState_d = WriteIdle;
    end

    // From the idle state, wait for the input parameters to become available.
    default :
    begin
      if (paramBufValid)
        writeState_d = WriteReqFlit1;
    end
  endcase

end

// Implement resettable registers for write access state machine.
always @(posedge clk)
begin
  if (srst)
    writeState_q <= WriteIdle;
  else
    writeState_q <= writeState_d;
end

// Implement non-resettable datapath registers.
always @(posedge clk)
begin
  doneStatusOk_q <= doneStatusOk_d;
end

// Add a toggle buffer to the SMI request output.
smiSelfLinkToggleBuffer #(72) smiReqBuffer
  (smiReqBufValid, { smiReqBufEofc, smiReqBufData }, smiReqBufStop, smiReqValid,
  { smiReqEofc, smiReqData }, smiReqStop, clk, srst);

// Add a toggle buffer to the status output.
smiSelfLinkToggleBuffer #(1) doneStatusBuffer
  (doneBufValid, doneStatusOk_q, doneBufStop, doneValid, doneStatusOk,
  doneStop, clk, srst);

endmodule
