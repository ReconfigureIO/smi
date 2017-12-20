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
// Implementation of a buffered SELF link with short FIFO. This component
// should typically be used for SELF links with a buffering capacity of
// between 3 and 128 entries to make efficient use of SRL primitives.
//

`timescale 1ns/1ps

module smiSelfLinkBufferFifoS
  (dataInValid, dataIn, dataInStop, dataOutValid, dataOut, dataOutStop,
  clk, srst);

// Specifes the width of the data channel.
parameter DataWidth = 8;

// Specifies the link buffer FIFO size.
parameter FifoSize = 16;

// Specifies the link buffer FIFO index size, which should be capable of holding
// the binary representation of FifoSize-2.
parameter FifoIndexSize = 4;

// Specifies the 'upstream' data input ports.
// verilator lint_off UNUSED
input  [DataWidth-1:0] dataIn;
// verilator lint_on UNUSED
input                  dataInValid;
output                 dataInStop;

// Specifies the 'downstream' data output ports.
output [DataWidth-1:0] dataOut;
output                 dataOutValid;
input                  dataOutStop;

// Specify system level signals.
input clk;
input srst;

// Specify the FIFO state machine signals.
reg                     fifoStop_d;
reg                     fifoReadValid_d;
reg [FifoIndexSize-1:0] fifoIndex_d;

reg                     fifoStop_q;
reg                     fifoReadValid_q;
reg [FifoIndexSize-1:0] fifoIndex_q;

// Specifies the FIFO shift register elements. Note that the size of the FIFO
// array is reduced by one to account for the additional storage element in
// the data output register.
// verilator lint_off UNDRIVEN
reg [DataWidth-1:0] fifoArray [FifoSize-2:0];
// verilator lint_on UNDRIVEN
reg [DataWidth-1:0] dataOut_q;
reg                 dataOutValid_q;

// Combinatorial status signals.
wire fifoWritePush;
wire fifoReadStop;

// Miscellaneous signals.
integer i;

// Implement combinatorial logic for the FIFO state machine.
always @(fifoStop_q, fifoReadValid_q, fifoIndex_q, fifoReadStop, fifoWritePush)
begin

  // Hold current state by default.
  fifoStop_d = fifoStop_q;
  fifoReadValid_d = fifoReadValid_q;
  fifoIndex_d = fifoIndex_q;

  // Clear input stop line after reset.
  if (fifoStop_q & ~fifoReadValid_q)
  begin
    fifoStop_d = 1'b0;
  end

  // Implement first push into an empty FIFO.
  else if (~fifoReadValid_q)
  begin
    fifoReadValid_d = fifoWritePush;
  end

  // Update the FIFO index on a push without concurrent pop.
  else if (fifoWritePush & fifoReadStop)
  begin
    fifoIndex_d = fifoIndex_q + 1;
    if ({1'b0, fifoIndex_q} == FifoSize [FifoIndexSize:0] - 3)
      fifoStop_d = 1'b1;
  end

  // Update the FIFO index on a pop without concurrent push.
  else if (~fifoWritePush & ~fifoReadStop)
  begin
    if (fifoIndex_q == 0)
      fifoReadValid_d = 1'b0;
    else
      fifoIndex_d = fifoIndex_q - 1;
    fifoStop_d = 1'b0;
  end
end

// Implement sequential logic for FIFO state machine.
always @(posedge clk)
begin
  if (srst)
  begin
    fifoStop_q <= 1'b1;
    fifoReadValid_q <= 1'b0;
    for (i = 0; i < FifoIndexSize; i = i + 1)
      fifoIndex_q [i] <= 1'b0;
  end
  else
  begin
    fifoStop_q <= fifoStop_d;
    fifoReadValid_q <= fifoReadValid_d;
    fifoIndex_q <= fifoIndex_d;
  end
end

assign fifoWritePush = dataInValid & ~fifoStop_q;
assign dataInStop = fifoStop_q;

// Implement the FIFO shift register.
// Disabled for linting, since this construct is not supported by Verilator.
`ifndef verilator
always @(posedge clk)
begin
  if (fifoWritePush)
  begin
    fifoArray [0] <= dataIn;
    for (i = 0; i < FifoSize - 2; i = i + 1)
      fifoArray [i+1] <= fifoArray[i];
  end
end
`endif

// Implement resettable control registers for output pipeline stage.
always @(posedge clk)
begin
  if (srst)
    dataOutValid_q <= 1'b0;
  else if (~fifoReadStop)
    dataOutValid_q <= fifoReadValid_q;
end

// Implement non-resettable data register for output pipeline stage.
always @(posedge clk)
begin
  if (~fifoReadStop)
    dataOut_q <= fifoArray [fifoIndex_q];
end

assign fifoReadStop = dataOutValid_q & dataOutStop;
assign dataOutValid = dataOutValid_q;
assign dataOut = dataOut_q;

endmodule
