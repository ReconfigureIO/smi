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
// Implementation of a buffered SELF link with large FIFO. This component
// should typically be used for SELF links with a buffering capacity of
// over 128 entries to make efficient use of RAM based circular buffers.
//

`timescale 1ns/1ps

module smiSelfLinkBufferFifoL
  (dataInValid, dataIn, dataInStop, dataOutValid, dataOut, dataOutStop,
  clk, srst);

// Specifes the width of the data channel.
parameter DataWidth = 8;

// Specifies the link buffer FIFO size.
parameter FifoSize = 128;

// Specifies the link buffer FIFO index size, which should be capable of holding
// the binary representation of FifoSize-1.
parameter FifoIndexSize = 7;

// Specifies the 'upstream' data input ports.
input  [DataWidth-1:0] dataIn;
input                  dataInValid;
output                 dataInStop;

// Specifies the 'downstream' data output ports.
output [DataWidth-1:0] dataOut;
output                 dataOutValid;
input                  dataOutStop;

// Specify system level signals.
input clk;
input srst;

// Specifies data input registers.
reg [DataWidth-1:0] dataIn_q;
reg                 dataInValid_q;

// Specifies the FIFO state machine signals.
reg [FifoIndexSize-1:0] entryCount_d;
reg [FifoIndexSize-1:0] writeIndex_d;
reg [FifoIndexSize-1:0] readIndex_d;
reg                     fifoFull_d;
reg                     ramReadValid_d;

reg [FifoIndexSize-1:0] entryCount_q;
reg [FifoIndexSize-1:0] writeIndex_q;
reg [FifoIndexSize-1:0] readIndex_q;
reg                     fifoFull_q;
reg                     ramReadValid_q;

// Specifies the FIFO RAM block.
reg                 ramWriteStrobe;
reg                 ramReadStrobe;
reg [DataWidth-1:0] ramArray [(1 << FifoIndexSize)-1:0];
reg [DataWidth-1:0] ramReadData_q;

// Specifies the FIFO RAM output pipeline signals.
reg                 ramPipeValid_q;
reg [DataWidth-1:0] ramPipeData_q;
wire                ramPipeStop;

// Miscellaneous signals.
integer i;

// Implement data input register for resettable control signals.
always @(posedge clk)
begin
  if (srst)
    dataInValid_q <= 1'b0;
  else if (~(dataInValid_q & fifoFull_q))
    dataInValid_q <= dataInValid;
end

// Implement data input register for non-resettable datapath signals.
always @(posedge clk)
begin
  if (~(dataInValid_q & fifoFull_q))
    dataIn_q <= dataIn;
end

assign dataInStop = dataInValid_q & fifoFull_q;

// Implement the FIFO combinatorial logic.
always @(entryCount_q, writeIndex_q, readIndex_q, fifoFull_q, dataIn_q,
  dataInValid_q, ramReadValid_q, ramPipeValid_q, ramPipeStop, dataOutStop)
begin

  // Hold current state by default.
  entryCount_d = entryCount_q;
  writeIndex_d = writeIndex_q;
  readIndex_d = readIndex_q;
  fifoFull_d = fifoFull_q;
  ramReadValid_d = ramReadValid_q;
  ramWriteStrobe = 1'b0;
  ramReadStrobe = 1'b0;

  // Increment the entry count and derive the FIFO full signal. Note that the
  // entry count limit takes into account the additional storage element in the
  // data input register.
  if ((dataInValid_q & ~fifoFull_q) & ~(ramPipeValid_q & ~dataOutStop))
  begin
    if ({1'b0, entryCount_q} == FifoSize [FifoIndexSize:0] - 2)
      fifoFull_d = 1'b1;
    else
      entryCount_d = entryCount_q + 1;
  end

  // Decrement the entry count and derive the FIFO full signal.
  else if (~(dataInValid_q & ~fifoFull_q) & (ramPipeValid_q & ~dataOutStop))
  begin
    if (fifoFull_q)
      fifoFull_d = 1'b0;
    else
      entryCount_d = entryCount_q - 1;
  end

  // Transfer FIFO data to the output register.
  if (~(ramReadValid_q & ramPipeStop))
  begin
    if (writeIndex_q == readIndex_q)
    begin
      ramReadValid_d = 1'b0;
    end
    else
    begin
      ramReadStrobe = 1'b1;
      readIndex_d = readIndex_q + 1;
      ramReadValid_d = 1'b1;
    end
  end

  // Transfer valid input data into the FIFO.
  if (dataInValid_q & ~fifoFull_q)
  begin
    ramWriteStrobe = 1'b1;
    writeIndex_d = writeIndex_q + 1;
  end
end

// Implement the FIFO sequential logic.
always @(posedge clk)
begin
  if (srst)
  begin
    for (i = 0; i < FifoIndexSize; i = i + 1)
    begin
      entryCount_q [i] <= 1'b0;
      writeIndex_q [i] <= 1'b0;
      readIndex_q [i] <= 1'b0;
    end
    fifoFull_q <= 1'b0;
    ramReadValid_q <= 1'b0;
  end
  else
  begin
    entryCount_q <= entryCount_d;
    writeIndex_q <= writeIndex_d;
    readIndex_q <= readIndex_d;
    fifoFull_q <= fifoFull_d;
    ramReadValid_q <= ramReadValid_d;
  end
end

// Implement the FIFO RAM.
always @(posedge clk)
begin
  if (ramWriteStrobe)
    ramArray [writeIndex_q] <= dataIn_q;
  if (ramReadStrobe)
    ramReadData_q <= ramArray [readIndex_q];
end

// Implement data output register for resettable control signals.
always @(posedge clk)
begin
  if (srst)
    ramPipeValid_q <= 1'b0;
  else if (~ramPipeStop)
    ramPipeValid_q <= ramReadValid_q;
end

// Implement data input register for non-resettable datapath signals.
always @(posedge clk)
begin
  if (~ramPipeStop)
    ramPipeData_q <= ramReadData_q;
end

assign ramPipeStop = ramPipeValid_q & dataOutStop;
assign dataOutValid = ramPipeValid_q;
assign dataOut = ramPipeData_q;

endmodule
