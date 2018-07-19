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
// limitations under the License.//
//

//
// Implementation of an Ethernet interface AXI Stream output adapter. This
// module converts SMI Ethernet frames to Ethernet frames for processing by the
// transmit side MAC using the AXI Stream protocol. It also performs retiming
// from the local SMI system clock to the output Ethernet line clock.
//

`timescale 1ns/1ps

module smiEthAxisOutputAdaptor
  (smiInValid, smiInData, smiInEofc, smiInStop, axisOutValid, axisOutData,
  axisOutKeep, axisOutLast, axisOutReady, ethClk, ethRst, sysClk, sysRst);

// Specifies the number of bits required to address individual bytes within the
// AXI data signal. This also determines the width of the data signal.
parameter DataIndexSize = 3;

// Specifies the input FIFO size.
parameter FifoSize = 1024;

// Specifies the maximum number of frames which may be queued by the input FIFO.
parameter FifoMaxFrames = 32;

// Derives the width of the data input and output ports.
parameter DataWidth = (1 << DataIndexSize) * 8;

// Derives the width of the AXI Slave keep port.
parameter KeepWidth = (1 << DataIndexSize);

// Derives the flit width for SMI components.
parameter FlitWidth = (1 << DataIndexSize);

// Specifies the SMI Frame input signals.
input                 smiInValid;
input [DataWidth-1:0] smiInData;
input [7:0]           smiInEofc;
output                smiInStop;

// Specifies the AXI Stream input signals.
output                 axisOutValid;
output [DataWidth-1:0] axisOutData;
output [KeepWidth-1:0] axisOutKeep;
output                 axisOutLast;
input                  axisOutReady;

// Specifies the clock and synchronous reset input signals.
input ethClk;
input ethRst;
input sysClk;
input sysRst;

// SMI header signals.
wire        headerReady;
wire [15:0] headerData;
wire        headerStop;

// SMI system clock domain output.
wire                 smiSysOutValid;
wire [DataWidth-1:0] smiSysOutData;
wire [7:0]           smiSysOutEofc;
wire                 smiSysOutStop;

// SMI output signals to frame assembly FIFO.
wire                 smiEthFifoValid;
wire [DataWidth-1:0] smiEthFifoData;
wire [7:0]           smiEthFifoEofc;
wire                 smiEthFifoStop;

// SMI output signals in Ethernet clock domain.
wire                 smiEthOutValid;
wire [DataWidth-1:0] smiEthOutData;
wire [7:0]           smiEthOutEofc;
wire                 smiEthOutStatus;
wire                 smiEthOutStop;
wire                 axisOutUser;

// Tie off unused signals.
assign headerStop = 1'b0;
assign smiEthOutStatus = 1'b0;

// Remove the SMI frame header. This is currently just discarded on transmit.
smiHeaderExtractPf1 #(FlitWidth, 2, 32) smiHeaderExtraction
  (smiInValid, smiInEofc, smiInData, smiInStop, headerReady, headerData,
  headerStop, smiSysOutValid, smiSysOutEofc, smiSysOutData, smiSysOutStop,
  sysClk, sysRst);

// Implement clock domain boundary.
smiSelfLinkAsyncFifo #(DataWidth+8, 512, 9) smiClockBoundary
  (smiSysOutValid, {smiSysOutEofc, smiSysOutData}, smiSysOutStop,
  smiEthFifoValid, {smiEthFifoEofc, smiEthFifoData}, smiEthFifoStop,
  sysClk, sysRst, ethClk, ethRst);

// Implement frame assembly component. This ensures that a full frame is ready
// for transmission before forwarding it to the Ethernet MAC.
smiFrameAssembler #(FlitWidth, FifoSize, FifoMaxFrames) outputFifo
  (smiEthFifoValid, smiEthFifoEofc, smiEthFifoData, smiEthFifoStop, smiEthOutValid,
  smiEthOutEofc, smiEthOutData, smiEthOutStop, ethClk, ethRst);

// Implement SMI to AXIS conversion. Note that the out of band user/status
// signals are not supported.
smiAxisOutputAdaptor #(DataIndexSize, 1) axisOutputAdaptor
  (smiEthOutValid, smiEthOutData, smiEthOutEofc, smiEthOutStatus, smiEthOutStop,
  axisOutValid, axisOutData, axisOutKeep, axisOutUser, axisOutLast, axisOutReady,
  ethClk, ethRst);

endmodule
