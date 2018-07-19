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
// Implementation of an Ethernet interface AXI Stream input adapter. This
// module converts Ethernet frames emitted by the receive side MAC using the
// AXI Stream protocol into SMI Ethernet frames. It also performs retiming
// from the input Ethernet line clock to the local SMI system clock.
//

`timescale 1ns/1ps

// Frame type identifiers - should probably move to a common package.
`define ETHERNET_FRAME_ID_BYTE 8'h40

module smiEthAxisInputAdaptor
  (axisInValid, axisInData, axisInKeep, axisInUser, axisInLast, axisInReady,
  smiOutValid, smiOutData, smiOutEofc, smiOutStop, frmDropCountReset, frmDropCount,
  ethClk, ethRst, sysClk, sysRst);

// Specifies the number of bits required to address individual bytes within the
// AXI data signal. This also determines the width of the data signal.
parameter DataIndexSize = 3;

// Specifies the width of the AXI User signal for out of band control.
parameter UserWidth = 1;

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

// Specifies the AXI Stream input signals.
input                 axisInValid;
input [DataWidth-1:0] axisInData;
input [KeepWidth-1:0] axisInKeep;
input [UserWidth-1:0] axisInUser;
input                 axisInLast;
output                axisInReady;

// Specifies the SMI Frame output signals.
output                 smiOutValid;
output [DataWidth-1:0] smiOutData;
output [7:0]           smiOutEofc;
input                  smiOutStop;

// Interface to dropped frame counter.
input         frmDropCountReset;
output [31:0] frmDropCount;

// Specifies the clock and synchronous reset input signals.
input ethClk;
input ethRst;
input sysClk;
input sysRst;

// Converted SMI input signals in Ethernet clock domain.
wire                 smiEthInValid;
wire [DataWidth-1:0] smiEthInData;
wire [7:0]           smiEthInEofc;
wire [UserWidth-1:0] smiEthInStatus;
wire                 smiEthInStop;

// SMI output signals from non-blocking frame FIFO.
wire                 smiEthFifoValid;
wire [DataWidth-1:0] smiEthFifoData;
wire [7:0]           smiEthFifoEofc;
wire [UserWidth-1:0] smiEthFifoStatus;
wire                 smiEthFifoStop;
wire                 smiEthFifoOverflow;

// Converted SMI input signals in system clock domain.
wire                 smiSysInValid;
wire [DataWidth-1:0] smiSysInData;
wire [7:0]           smiSysInEofc;
wire [UserWidth:0]   smiSysInStatus;
wire                 smiSysInStop;

// Forked SELF handshake signals for status and data.
wire smiSysStatusValid;
reg  smiSysStatusStop;
wire smiSysPayloadValid;
wire smiSysPayloadStop;

// Specify header state machine signals.
reg        drainStatusInput_d;
reg        drainStatusInput_q;
reg        headerReady;
reg [15:0] headerData;
wire       headerStop;

// Map AXI input stream signals to SMI signals.
smiAxisInputAdaptor #(DataIndexSize, UserWidth) axisInputAdaptor
  (axisInValid, axisInData, axisInKeep, axisInUser, axisInLast, axisInReady,
  smiEthInValid, smiEthInData, smiEthInEofc, smiEthInStatus, smiEthInStop,
  ethClk, ethRst);

// Implement non-blocking SMI frame FIFO in Ethernet clock domain.
smiFrameDropper #(FlitWidth, UserWidth, FifoSize, FifoMaxFrames) inputFifo
  (smiEthInValid, smiEthInEofc, smiEthInData, smiEthInStatus, smiEthInStop,
  smiEthFifoValid, smiEthFifoEofc, smiEthFifoData, smiEthFifoStatus, smiEthFifoStop,
  smiEthFifoOverflow, frmDropCountReset, frmDropCount, ethClk, ethRst);

// Implement clock domain boundary. Not that this implicitly appends the overflow
// flag to the frame status signal.
smiSelfLinkAsyncFifo #(DataWidth+UserWidth+9, 512, 9) smiClockBoundary
  (smiEthFifoValid, {smiEthFifoOverflow, smiEthFifoStatus, smiEthFifoEofc,
  smiEthFifoData}, smiEthFifoStop, smiSysInValid, {smiSysInStatus, smiSysInEofc,
  smiSysInData}, smiSysInStop, ethClk, ethRst, sysClk, sysRst);

// Status information passed through the input FIFO is valid for the duration
// of a complete frame, so it can be appended to the SMI frame header at the
// start of each received Ethernet frame.
smiSelfFlowForkControl #(2) smiStatusFork
  (smiSysInValid, smiSysInStop, {smiSysStatusValid, smiSysPayloadValid},
  {smiSysStatusStop, smiSysPayloadStop}, sysClk, sysRst);

// Implement combinatorial logic for status header generation.
always @(drainStatusInput_q, smiSysStatusValid, headerStop, smiSysInEofc,
  smiSysInStatus)
begin

  // Hold current state by default.
  drainStatusInput_d = drainStatusInput_q;
  headerReady = 1'b0;
  headerData [15:0] = {8'd0, `ETHERNET_FRAME_ID_BYTE};
  headerData [8] = smiSysInStatus [UserWidth];
  headerData [UserWidth+8:9] = smiSysInStatus [UserWidth-1:0];
  smiSysStatusStop = 1'b0;

  // Wait for first flit of the frame to extract the status.
  if (~drainStatusInput_q)
  begin
    headerReady = smiSysStatusValid;
    smiSysStatusStop = headerStop;
    if ((smiSysStatusValid & ~headerStop) && (smiSysInEofc == 8'b0))
      drainStatusInput_d = 1'b1;
  end

  // Drain the remaining frame contents.
  else
  begin
    if (smiSysStatusValid && (smiSysInEofc != 8'b0))
      drainStatusInput_d = 1'b0;
  end

end

// Implement sequential logic for status header generation.
always @(posedge sysClk)
begin
  if (sysRst)
    drainStatusInput_q <= 1'b0;
  else
    drainStatusInput_q <= drainStatusInput_d;
end

// Implement SMI frame header insertion.
smiHeaderInjectPf1 #(FlitWidth, 2, 32) smiHeaderInjection
  (headerReady, headerData, headerStop, smiSysPayloadValid, smiSysInEofc,
  smiSysInData, smiSysPayloadStop, smiOutValid, smiOutEofc, smiOutData,
  smiOutStop, sysClk, sysRst);

endmodule

