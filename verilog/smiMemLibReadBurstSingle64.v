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
// Memory access library single burst read transfer component. This carries out
// a single read burst transfer, with data being copied to a 64-bit wide SELF
// data output. Bursts must not be greater than 512 64-bit words long and must
// not cross address boundaries at integer multiples of 4096.
//

`timescale 1ns/1ps

module smiMemLibReadBurstSingle64
  (paramsValid, paramBurstAddr, paramBurstLen, paramBurstOpts, paramsStop,
  readValid, readData, readStop, doneValid, doneStatusOk, doneStop, smiReqValid,
  smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc, smiRespData,
  smiRespStop, clk, srst);

// Specify burst parameter inputs.
input        paramsValid;
input [63:0] paramBurstAddr;
input [15:0] paramBurstLen;
input [7:0]  paramBurstOpts;
output       paramsStop;

// Specify read data outputs.
output        readValid;
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

// Local parameter signals.
wire        paramBufValid;
wire [63:0] paramBufBurstAddr;
wire [15:0] paramBufBurstLen;
wire [7:0]  paramBufBurstOpts;
wire        paramBufStop;

wire [63:0] paramAlignedBurstAddr;
wire [15:0] paramByteBurstLen;

// Read data buffer signals.
wire        readBufValid;
wire [7:0]  readBufEofc;
wire [63:0] readBufData;
wire        readBufStop;

// Internal done buffer signals.
wire doneBufValid;
wire doneBufStatusOk;
wire doneBufStop;

// Add a toggle buffer to the parameter input.
smiSelfLinkToggleBuffer #(88) paramsBuffer
  (paramsValid, { paramBurstAddr, paramBurstLen, paramBurstOpts }, paramsStop,
  paramBufValid, { paramBufBurstAddr, paramBufBurstLen, paramBufBurstOpts },
  paramBufStop, clk, srst);

// Instantiiate the single data transfer core logic.
assign paramAlignedBurstAddr = { paramBufBurstAddr[63:3], 3'd0 };
assign paramByteBurstLen = { paramBufBurstLen[12:0], 3'd0 };

smiMemLibReadBurstCore #(16) readBurstCore
  (paramBufValid, paramAlignedBurstAddr, paramByteBurstLen, paramBufBurstOpts,
  paramBufStop, readBufValid, readBufEofc, readBufData, readBufStop, doneBufValid,
  doneBufStatusOk, doneBufStop, smiReqValid, smiReqEofc, smiReqData, smiReqStop,
  smiRespValid, smiRespEofc, smiRespData, smiRespStop, clk, srst);

// Buffer the read data. Note that since the transferred data is all 64-bit,
// we can just directly copy over the SMI frame contents and ignore the EOFC
// signal.
smiSelfLinkDoubleBuffer #(64) dataBuffer
  (readBufValid, readBufData, readBufStop, readValid, readData, readStop,
  clk, srst);

// Add a toggle buffer to the done status output.
smiSelfLinkToggleBuffer #(1) doneStatusBuffer
  (doneBufValid, doneBufStatusOk, doneBufStop, doneValid, doneStatusOk,
  doneStop, clk, srst);

endmodule
