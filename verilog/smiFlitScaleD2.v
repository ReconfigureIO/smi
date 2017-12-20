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
// limitations under the License.//
//

//
// Provides support for SMI flit width scaling. This variant supports halving
// of the input flit data width.
//

`timescale 1ns/1ps

module smiFlitScaleD2
  (smiInReady, smiInEofc, smiInData, smiInStop, smiOutReady, smiOutEofc,
  smiOutData, smiOutStop, clk, srst);

// Specifies the width of the flit data input port as an integer power of two
// number of bytes.
parameter FlitWidth = 4;

// Derives the mask for unused end of frame control bits.
parameter EofcMask = 2 * FlitWidth - 1;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the SMI input signals.
input                   smiInReady;
input [7:0]             smiInEofc;
input [FlitWidth*8-1:0] smiInData;
output                  smiInStop;

// Specifies the SMI output signals.
output                   smiOutReady;
output [7:0]             smiOutEofc;
output [FlitWidth*4-1:0] smiOutData;
input                    smiOutStop;

// Specifies the SMI buffered input signals.
wire                   smiInBufReady;
wire [7:0]             smiInBufEofc;
wire [FlitWidth*8-1:0] smiInBufData;
wire                   smiInBufStop;
wire [FlitWidth*8+7:0] smiInBufVec;

// Specifies the SMI bus width reduction signals.
wire                   smiScReady;
wire [7:0]             smiScEofc;
wire [FlitWidth*4-1:0] smiScData;
wire                   smiScHalt;
wire [FlitWidth*4+7:0] smiOutVec;

// Instantiate the data input buffer.
smiSelfLinkToggleBuffer #(FlitWidth*8+8) smiBufIn
  (smiInReady, {smiInEofc, smiInData}, smiInStop, smiInBufReady, smiInBufVec,
  smiInBufStop, clk, srst);

assign smiInBufEofc = smiInBufVec [FlitWidth*8+7:FlitWidth*8];
assign smiInBufData = smiInBufVec [FlitWidth*8-1:0];

// Instantiate the flit width scaling stage.
smiFlitScaleStageD2 #(FlitWidth) scaleStage
  (smiInBufReady, smiInBufEofc, smiInBufData, smiInBufStop, smiScReady,
  smiScEofc, smiScData, smiScHalt, clk, srst);

// Instantiate the data output buffer.
smiSelfLinkDoubleBuffer #(FlitWidth*4+8) smiBufOut
  (smiScReady, {smiScEofc, smiScData}, smiScHalt, smiOutReady,
  smiOutVec, smiOutStop, clk, srst);

assign smiOutEofc = smiOutVec[FlitWidth*4+7:FlitWidth*4];
assign smiOutData = smiOutVec[FlitWidth*4-1:0];

endmodule
