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
// Provides support for SMI flit width scaling. This variant supports reduction
// of the input flit data width by a factor of 8.
//

`timescale 1ns/1ps

module smiFlitScaleD8
  (smiInReady, smiInEofc, smiInData, smiInStop, smiOutReady, smiOutEofc,
  smiOutData, smiOutStop, clk, srst);

// Specifies the width of the flit data input port as an integer power of two
// number of bytes.
parameter FlitWidth = 8;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the SMI input signals.
input                   smiInReady;
input [7:0]             smiInEofc;
input [FlitWidth*8-1:0] smiInData;
output                  smiInStop;

// Specifies the SMI output signals.
output                 smiOutReady;
output [7:0]           smiOutEofc;
output [FlitWidth-1:0] smiOutData;
input                  smiOutStop;

// Specifies the SMI buffered input signals.
wire                   smiInBufReady;
wire [7:0]             smiInBufEofc;
wire [FlitWidth*8-1:0] smiInBufData;
wire                   smiInBufStop;
wire [FlitWidth*8+7:0] smiInBufVec;

// Specifies the internal connections.
wire                   smiSc1Ready;
wire [7:0]             smiSc1Eofc;
wire [FlitWidth*4-1:0] smiSc1Data;
wire                   smiSc1Stop;

wire                   smiSc2Ready;
wire [7:0]             smiSc2Eofc;
wire [FlitWidth*2-1:0] smiSc2Data;
wire                   smiSc2Stop;

// Specifies the SMI bus width reduction signals.
wire                 smiSc3Ready;
wire [7:0]           smiSc3Eofc;
wire [FlitWidth-1:0] smiSc3Data;
wire                 smiSc3Halt;
wire [FlitWidth+7:0] smiOutVec;

// Instantiate the data input buffer.
smiSelfLinkToggleBuffer #(FlitWidth*8+8) smiBufIn
  (smiInReady, {smiInEofc, smiInData}, smiInStop, smiInBufReady, smiInBufVec,
  smiInBufStop, clk, srst);

assign smiInBufEofc = smiInBufVec [FlitWidth*8+7:FlitWidth*8];
assign smiInBufData = smiInBufVec [FlitWidth*8-1:0];

// Instantiate the first stage scaling.
smiFlitScaleStageD2 #(FlitWidth) scaleStage1
  (smiInBufReady, smiInBufEofc, smiInBufData, smiInBufStop, smiSc1Ready,
  smiSc1Eofc, smiSc1Data, smiSc1Stop, clk, srst);

// Instantiate the second stage scaling.
smiFlitScaleStageD2 #(FlitWidth/2) scaleStage2
  (smiSc1Ready, smiSc1Eofc, smiSc1Data, smiSc1Stop, smiSc2Ready, smiSc2Eofc,
  smiSc2Data, smiSc2Stop, clk, srst);

// Instantiate the third stage scaling.
smiFlitScaleStageD2 #(FlitWidth/4) scaleStage3
  (smiSc2Ready, smiSc2Eofc, smiSc2Data, smiSc2Stop, smiSc3Ready, smiSc3Eofc,
  smiSc3Data, smiSc3Halt, clk, srst);

// Instantiate the data output FIFO.
smiSelfLinkDoubleBuffer #(FlitWidth+8) smiBufOut
  (smiSc3Ready, {smiSc3Eofc, smiSc3Data}, smiSc3Halt, smiOutReady,
  smiOutVec, smiOutStop, clk, srst);

assign smiOutEofc = smiOutVec[FlitWidth+7:FlitWidth];
assign smiOutData = smiOutVec[FlitWidth-1:0];

endmodule
