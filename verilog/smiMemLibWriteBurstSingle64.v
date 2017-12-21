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
// Memory access library single burst write transfer component. This carries out
// a single write burst transfer, with data being copied from a 64-bit wide SELF
// data input. Bursts must not be greater than 512 64-bit words long and must
// not cross address boundaries at integer multiples of 4096.
//

`timescale 1ns/1ps

module smiMemLibWriteBurstSingle64
  (paramsValid, paramBurstAddr, paramBurstLen, paramBurstOpts, paramsStop,
  writeValid, writeData, writeStop, doneValid, doneStatusOk, doneStop,
  smiReqValid, smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc,
  smiRespData, smiRespStop, clk, srst);

// Specify burst parameter inputs.
input        paramsValid;
input [63:0] paramBurstAddr;
input [15:0] paramBurstLen;
input [7:0]  paramBurstOpts;
output       paramsStop;

// Specify write data inputs.
input        writeValid;
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

// Forked parameter input control signals.
wire headerValid;
wire copyReqValid;
wire headerStop;
reg  copyReqStop;

// Data copying state machine signals.
reg [12:0] flitCopyCount_d;
reg        flitCopyActive_d;

reg [12:0] flitCopyCount_q;
reg        flitCopyActive_q;

reg       copyValid;
reg [7:0] copyEofc;
wire      copyStop;

// Local parameter signals.
wire        paramBufValid;
wire [63:0] paramBufBurstAddr;
wire [15:0] paramBufBurstLen;
wire [7:0]  paramBufBurstOpts;
wire        paramBufStop;

wire [63:0] paramAlignedBurstAddr;
wire [15:0] paramByteBurstLen;

// Buffered write data inputs.
wire        writeBufValid;
wire [63:0] writeBufData;
reg         writeBufStop;

// Internal done buffer signals.
wire doneBufValid;
wire doneBufStatusOk;
wire doneBufStop;

// Add a toggle buffer to the parameter input.
smiSelfLinkToggleBuffer #(88) paramsBuffer
  (paramsValid, { paramBurstAddr, paramBurstLen, paramBurstOpts }, paramsStop,
  paramBufValid, { paramBufBurstAddr, paramBufBurstLen, paramBufBurstOpts },
  paramBufStop, clk, srst);

// Add a double buffer to the write data input.
smiSelfLinkDoubleBuffer #(64) writeBuffer
  (writeValid, writeData, writeStop, writeBufValid, writeBufData, writeBufStop,
  clk, srst);

// Fork the parameter inputs to the payload copying logic and header injection.
smiSelfFlowForkControl #(2) parameterFork
  (paramBufValid, paramBufStop, {headerValid, copyReqValid},
  {headerStop, copyReqStop}, clk, srst);

// Combinatorial logic for data copying operation.
always @(flitCopyCount_q, flitCopyActive_q, copyReqValid, paramBufBurstLen,
  writeBufValid, copyStop)
begin

  // Hold current state by default.
  flitCopyCount_d = flitCopyCount_q;
  flitCopyActive_d = flitCopyActive_q;
  copyValid = 1'b0;
  copyReqStop = 1'b1;
  writeBufStop = 1'b1;

  // Derive the EOFC value from the flit copy count.
  if (flitCopyCount_q == 13'd1)
    copyEofc = 8'd8;
  else
    copyEofc = 8'd0;

  // In the idle state, wait to begin copying the input.
  if (~flitCopyActive_q)
  begin
    copyReqStop = 1'b0;
    flitCopyCount_d = paramBufBurstLen [12:0];
    if (copyReqValid)
      flitCopyActive_d = 1'b1;
  end

  // In the copying state, hook up the SELF handshake signals and count down
  // the number of transactions observed.
  else
  begin
    copyValid = writeBufValid;
    writeBufStop = copyStop;
    if (writeBufValid & ~copyStop)
    begin
      flitCopyCount_d = flitCopyCount_q - 13'd1;

      // Final flit detected - revert to the idle state.
      if (flitCopyCount_q == 13'd1)
        flitCopyActive_d = 1'b0;
    end
  end
end

// Resettable sequential logic for data copying operation.
always @(posedge clk)
begin
  if (srst)
    flitCopyActive_q <= 1'b0;
  else
    flitCopyActive_q <= flitCopyActive_d;
end

// Non-resettable sequential logic for data copying operation.
always @(posedge clk)
begin
  flitCopyCount_q <= flitCopyCount_d;
end

// Instantiate the single data transfer core logic.
assign paramAlignedBurstAddr = { paramBufBurstAddr[63:3], 3'd0 };
assign paramByteBurstLen = { paramBufBurstLen[12:0], 3'd0 };

smiMemLibWriteBurstCore #(16) writeBurstCore
  (headerValid, paramAlignedBurstAddr, paramByteBurstLen, paramBufBurstOpts,
  headerStop, copyValid, copyEofc, writeBufData, copyStop, doneBufValid,
  doneBufStatusOk, doneBufStop, smiReqValid, smiReqEofc, smiReqData,
  smiReqStop, smiRespValid, smiRespEofc, smiRespData, smiRespStop,
  clk, srst);

// Add a toggle buffer to the done status output.
smiSelfLinkToggleBuffer #(1) doneStatusBuffer
  (doneBufValid, doneBufStatusOk, doneBufStop, doneValid, doneStatusOk,
  doneStop, clk, srst);

endmodule
