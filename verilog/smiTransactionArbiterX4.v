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
// Implements four way transaction arbitration on SMI based accesses.
//

`timescale 1ns/1ps

module smiTransactionArbiterX4
  (smiReqAInReady, smiReqAInEofc, smiReqAInData, smiReqAInStop, smiRespAOutReady,
  smiRespAOutEofc, smiRespAOutData, smiRespAOutStop, smiReqBInReady,
  smiReqBInEofc, smiReqBInData, smiReqBInStop, smiRespBOutReady, smiRespBOutEofc,
  smiRespBOutData, smiRespBOutStop, smiReqCInReady, smiReqCInEofc, smiReqCInData,
  smiReqCInStop, smiRespCOutReady, smiRespCOutEofc, smiRespCOutData,
  smiRespCOutStop, smiReqDInReady, smiReqDInEofc, smiReqDInData, smiReqDInStop,
  smiRespDOutReady, smiRespDOutEofc, smiRespDOutData, smiRespDOutStop,
  smiReqOutReady, smiReqOutEofc, smiReqOutData, smiReqOutStop, smiRespInReady,
  smiRespInEofc, smiRespInData, smiRespInStop, clk, srst);

// Specifes the width of the data input and output ports. Must be at least 4.
parameter FlitWidth = 4;

// Specifies the width of the ID part of the tag. This also determines the
// number of transactions which may be 'in flight' through each upstream
// interface at any given time. Maximum value of 10.
parameter TagIdWidth = 2;

// Specifies the internal FIFO depths (more than 3 entries).
parameter FifoSize = 16;

// Specifies the maximum number of frames which may be queued by the frame
// assembler component (maximum 63).
parameter MaxFrameCount = 7;

// Derives the width of the data input and output ports.
parameter DataWidth = FlitWidth * 8;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the input transaction request and response ports.
input                 smiReqAInReady;
input [7:0]           smiReqAInEofc;
input [DataWidth-1:0] smiReqAInData;
output                smiReqAInStop;

input                 smiReqBInReady;
input [7:0]           smiReqBInEofc;
input [DataWidth-1:0] smiReqBInData;
output                smiReqBInStop;

input                 smiReqCInReady;
input [7:0]           smiReqCInEofc;
input [DataWidth-1:0] smiReqCInData;
output                smiReqCInStop;

input                 smiReqDInReady;
input [7:0]           smiReqDInEofc;
input [DataWidth-1:0] smiReqDInData;
output                smiReqDInStop;

input                 smiRespInReady;
input [7:0]           smiRespInEofc;
input [DataWidth-1:0] smiRespInData;
output                smiRespInStop;

// Specifies the output transaction request and response ports.
output                 smiReqOutReady;
output [7:0]           smiReqOutEofc;
output [DataWidth-1:0] smiReqOutData;
input                  smiReqOutStop;

output                 smiRespAOutReady;
output [7:0]           smiRespAOutEofc;
output [DataWidth-1:0] smiRespAOutData;
input                  smiRespAOutStop;

output                 smiRespBOutReady;
output [7:0]           smiRespBOutEofc;
output [DataWidth-1:0] smiRespBOutData;
input                  smiRespBOutStop;

output                 smiRespCOutReady;
output [7:0]           smiRespCOutEofc;
output [DataWidth-1:0] smiRespCOutData;
input                  smiRespCOutStop;

output                 smiRespDOutReady;
output [7:0]           smiRespDOutEofc;
output [DataWidth-1:0] smiRespDOutData;
input                  smiRespDOutStop;

// Specifies the internal bus A signals.
wire                 smiReqAIntReady;
wire [7:0]           smiReqAIntEofc;
wire [DataWidth-1:0] smiReqAIntData;
wire                 smiReqAIntStop;

wire                 smiReqABufReady;
wire [7:0]           smiReqABufEofc;
wire [DataWidth-1:0] smiReqABufData;
wire                 smiReqABufStop;

wire                 smiRespAIntReady;
wire [7:0]           smiRespAIntEofc;
wire [DataWidth-1:0] smiRespAIntData;
wire                 smiRespAIntStop;

wire                 smiRespABufReady;
wire [7:0]           smiRespABufEofc;
wire [DataWidth-1:0] smiRespABufData;
wire                 smiRespABufStop;

// Specifies the internal bus B signals.
wire                 smiReqBIntReady;
wire [7:0]           smiReqBIntEofc;
wire [DataWidth-1:0] smiReqBIntData;
wire                 smiReqBIntStop;

wire                 smiReqBBufReady;
wire [7:0]           smiReqBBufEofc;
wire [DataWidth-1:0] smiReqBBufData;
wire                 smiReqBBufStop;

wire                 smiRespBIntReady;
wire [7:0]           smiRespBIntEofc;
wire [DataWidth-1:0] smiRespBIntData;
wire                 smiRespBIntStop;

wire                 smiRespBBufReady;
wire [7:0]           smiRespBBufEofc;
wire [DataWidth-1:0] smiRespBBufData;
wire                 smiRespBBufStop;

// Specifies the internal bus C signals.
wire                 smiReqCIntReady;
wire [7:0]           smiReqCIntEofc;
wire [DataWidth-1:0] smiReqCIntData;
wire                 smiReqCIntStop;

wire                 smiReqCBufReady;
wire [7:0]           smiReqCBufEofc;
wire [DataWidth-1:0] smiReqCBufData;
wire                 smiReqCBufStop;

wire                 smiRespCIntReady;
wire [7:0]           smiRespCIntEofc;
wire [DataWidth-1:0] smiRespCIntData;
wire                 smiRespCIntStop;

wire                 smiRespCBufReady;
wire [7:0]           smiRespCBufEofc;
wire [DataWidth-1:0] smiRespCBufData;
wire                 smiRespCBufStop;

// Specifies the internal bus B signals.
wire                 smiReqDIntReady;
wire [7:0]           smiReqDIntEofc;
wire [DataWidth-1:0] smiReqDIntData;
wire                 smiReqDIntStop;

wire                 smiReqDBufReady;
wire [7:0]           smiReqDBufEofc;
wire [DataWidth-1:0] smiReqDBufData;
wire                 smiReqDBufStop;

wire                 smiRespDIntReady;
wire [7:0]           smiRespDIntEofc;
wire [DataWidth-1:0] smiRespDIntData;
wire                 smiRespDIntStop;

wire                 smiRespDBufReady;
wire [7:0]           smiRespDBufEofc;
wire [DataWidth-1:0] smiRespDBufData;
wire                 smiRespDBufStop;

// Instantiate transaction matcher on upstream bus A.
smiTransactionMatcher #(FlitWidth, 0, TagIdWidth) busAMatcher
  (smiReqAInReady, smiReqAInEofc, smiReqAInData, smiReqAInStop, smiReqAIntReady,
  smiReqAIntEofc, smiReqAIntData, smiReqAIntStop, smiRespAIntReady, smiRespAIntEofc,
  smiRespAIntData, smiRespAIntStop, smiRespAOutReady, smiRespAOutEofc, smiRespAOutData,
  smiRespAOutStop, clk, srst);

// Instantiate FIFO buffers on upstream bus A.
smiFrameAssembler #(FlitWidth, FifoSize, MaxFrameCount) busAReqBuffer
  (smiReqAIntReady, smiReqAIntEofc, smiReqAIntData, smiReqAIntStop,
  smiReqABufReady, smiReqABufEofc, smiReqABufData, smiReqABufStop, clk, srst);

smiFrameBuffer #(FlitWidth, FifoSize) busARespBuffer
  (smiRespABufReady, smiRespABufEofc, smiRespABufData, smiRespABufStop,
  smiRespAIntReady, smiRespAIntEofc, smiRespAIntData, smiRespAIntStop, clk, srst);

// Instantiate transaction matcher on upstream bus B.
smiTransactionMatcher #(FlitWidth, 1, TagIdWidth) busBMatcher
  (smiReqBInReady, smiReqBInEofc, smiReqBInData, smiReqBInStop, smiReqBIntReady,
  smiReqBIntEofc, smiReqBIntData, smiReqBIntStop, smiRespBIntReady, smiRespBIntEofc,
  smiRespBIntData, smiRespBIntStop, smiRespBOutReady, smiRespBOutEofc, smiRespBOutData,
  smiRespBOutStop, clk, srst);

// Instantiate FIFO buffers on upstream bus B.
smiFrameAssembler #(FlitWidth, FifoSize, MaxFrameCount) busBReqBuffer
  (smiReqBIntReady, smiReqBIntEofc, smiReqBIntData, smiReqBIntStop, smiReqBBufReady,
  smiReqBBufEofc, smiReqBBufData, smiReqBBufStop, clk, srst);

smiFrameBuffer #(FlitWidth, FifoSize) busBRespBuffer
  (smiRespBBufReady, smiRespBBufEofc, smiRespBBufData, smiRespBBufStop,
  smiRespBIntReady, smiRespBIntEofc, smiRespBIntData, smiRespBIntStop, clk, srst);

// Instantiate transaction matcher on upstream bus C.
smiTransactionMatcher #(FlitWidth, 2, TagIdWidth) busCMatcher
  (smiReqCInReady, smiReqCInEofc, smiReqCInData, smiReqCInStop, smiReqCIntReady,
  smiReqCIntEofc, smiReqCIntData, smiReqCIntStop, smiRespCIntReady, smiRespCIntEofc,
  smiRespCIntData, smiRespCIntStop, smiRespCOutReady, smiRespCOutEofc, smiRespCOutData,
  smiRespCOutStop, clk, srst);

// Instantiate FIFO buffers on upstream bus C.
smiFrameAssembler #(FlitWidth, FifoSize, MaxFrameCount) busCReqBuffer
  (smiReqCIntReady, smiReqCIntEofc, smiReqCIntData, smiReqCIntStop,
  smiReqCBufReady, smiReqCBufEofc, smiReqCBufData, smiReqCBufStop, clk, srst);

smiFrameBuffer #(FlitWidth, FifoSize) busCRespBuffer
  (smiRespCBufReady, smiRespCBufEofc, smiRespCBufData, smiRespCBufStop,
  smiRespCIntReady, smiRespCIntEofc, smiRespCIntData, smiRespCIntStop, clk, srst);

// Instantiate transaction matcher on upstream bus D.
smiTransactionMatcher #(FlitWidth, 3, TagIdWidth) busDMatcher
  (smiReqDInReady, smiReqDInEofc, smiReqDInData, smiReqDInStop, smiReqDIntReady,
  smiReqDIntEofc, smiReqDIntData, smiReqDIntStop, smiRespDIntReady, smiRespDIntEofc,
  smiRespDIntData, smiRespDIntStop, smiRespDOutReady, smiRespDOutEofc, smiRespDOutData,
  smiRespDOutStop, clk, srst);

// Instantiate FIFO buffers on upstream bus D.
smiFrameAssembler #(FlitWidth, FifoSize, MaxFrameCount) busDReqBuffer
  (smiReqDIntReady, smiReqDIntEofc, smiReqDIntData, smiReqDIntStop, smiReqDBufReady,
  smiReqDBufEofc, smiReqDBufData, smiReqDBufStop, clk, srst);

smiFrameBuffer #(FlitWidth, FifoSize) busDRespBuffer
  (smiRespDBufReady, smiRespDBufEofc, smiRespDBufData, smiRespDBufStop,
  smiRespDIntReady, smiRespDIntEofc, smiRespDIntData, smiRespDIntStop, clk, srst);

// Instantiate frame arbitration between upstream requests.
smiFrameArbiterX4 #(FlitWidth) reqArbiter
  (smiReqABufReady, smiReqABufEofc, smiReqABufData, smiReqABufStop,
  smiReqBBufReady, smiReqBBufEofc, smiReqBBufData, smiReqBBufStop,
  smiReqCBufReady, smiReqCBufEofc, smiReqCBufData, smiReqCBufStop,
  smiReqDBufReady, smiReqDBufEofc, smiReqDBufData, smiReqDBufStop,
  smiReqOutReady, smiReqOutEofc, smiReqOutData, smiReqOutStop, clk, srst);

// Instantiate frame steering to upstream responses.
smiFrameSteerX4 #(FlitWidth, 0, (1 << 26), (2 << 26), (3 << 26), (63 << 26)) respSteer
  (smiRespInReady, smiRespInEofc, smiRespInData, smiRespInStop, smiRespABufReady,
  smiRespABufEofc, smiRespABufData, smiRespABufStop, smiRespBBufReady,
  smiRespBBufEofc, smiRespBBufData, smiRespBBufStop, smiRespCBufReady,
  smiRespCBufEofc, smiRespCBufData, smiRespCBufStop, smiRespDBufReady,
  smiRespDBufEofc, smiRespDBufData, smiRespDBufStop, clk, srst);

endmodule
