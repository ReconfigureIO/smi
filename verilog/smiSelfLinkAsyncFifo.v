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
// Implementation of an asynchronous SELF link with dual port RAM based FIFO.
// This component should be used for SELF links which cross clock boundaries.
//

`timescale 1ns/1ps

module smiSelfLinkAsyncFifo
  (dataInValid, dataIn, dataInStop, dataOutValid, dataOut, dataOutStop,
  inClk, inRst, outClk, outRst);

// Specifes the width of the data channel.
parameter DataWidth = 16;

// Specifies the link buffer FIFO size.
parameter FifoSize = 32;

// Specifies the link buffer FIFO index size, which should be capable of holding
// the binary representation of FifoSize-1.
parameter FifoIndexSize = 5;

// Specifies the 'upstream' data input ports.
input  [DataWidth-1:0] dataIn;
input                  dataInValid;
output                 dataInStop;

// Specifies the 'downstream' data output ports.
output [DataWidth-1:0] dataOut;
output                 dataOutValid;
input                  dataOutStop;

// Specify system level signals.
input inClk;
input inRst;
input outClk;
input outRst;

// Specifies data input registers.
reg [DataWidth-1:0] dataIn_q;
reg                 dataInValid_q;

// Specify the FIFO input state machine signals.
reg [FifoIndexSize-1:0] inputTotalCount_d;
reg [FifoIndexSize-1:0] inputNewCount_d;
reg [FifoIndexSize-1:0] ramWriteIndex_d;
reg                     fifoFull_d;
reg                     inputIncrToggle_d;
reg [FifoIndexSize-1:0] inputIncrValue_d;

reg [FifoIndexSize-1:0] inputTotalCount_q;
reg [FifoIndexSize-1:0] inputNewCount_q;
reg [FifoIndexSize-1:0] ramWriteIndex_q;
reg                     fifoFull_q;
reg                     inputIncrToggle_q;
reg [FifoIndexSize-1:0] inputIncrValue_q;

// Specify the FIFO output state machine signals.
reg [FifoIndexSize-1:0] outputTotalCount_d;
reg [FifoIndexSize-1:0] outputOldCount_d;
reg [FifoIndexSize-1:0] ramReadIndex_d;
reg                     fifoReady_d;
reg                     outputDecrToggle_d;
reg [FifoIndexSize-1:0] outputDecrValue_d;

reg [FifoIndexSize-1:0] outputTotalCount_q;
reg [FifoIndexSize-1:0] outputOldCount_q;
reg [FifoIndexSize-1:0] ramReadIndex_q;
reg                     fifoReady_q;
reg                     outputDecrToggle_q;
reg [FifoIndexSize-1:0] outputDecrValue_q;

// Specify the entry count decrement retiming pipeline signals.
reg [3:0]               inputDecrToggle_q;
reg [FifoIndexSize-1:0] inputDecrValueP1_q;
reg [FifoIndexSize-1:0] inputDecrValueP2_q;
wire                    inputDecrStrobe;

// Specify the entry count increment async signals.
reg [3:0]               outputIncrToggle_q;
reg [FifoIndexSize-1:0] outputIncrValueP1_q;
reg [FifoIndexSize-1:0] outputIncrValueP2_q;
wire                    outputIncrStrobe;

// Specify RAM access signals.
reg                 ramWriteStrobe;
reg                 ramReadStrobe;
reg [DataWidth-1:0] ramArray [(1 << FifoIndexSize)-1:0];
reg [DataWidth-1:0] ramReadData_q;
reg                 ramReadDataValid_q;
wire                ramReadHalt;

// Miscellaneous signals.
integer i;

// Implement data input register for resettable control signals.
always @(posedge inClk)
begin
  if (inRst)
    dataInValid_q <= 1'b0;
  else if (~(dataInValid_q & fifoFull_q))
    dataInValid_q <= dataInValid;
end

// Implement data input register for non-resettable datapath signals.
always @(posedge inClk)
begin
  if (~(dataInValid_q & fifoFull_q))
    dataIn_q <= dataIn;
end

// Implement combinatorial logic for FIFO input state machine.
always @(inputTotalCount_q, inputNewCount_q, ramWriteIndex_q, fifoFull_q,
  inputIncrToggle_q, inputIncrValue_q, dataInValid_q, dataIn_q, inputDecrStrobe,
  inputDecrValueP2_q)
begin

  // Hold current state by default.
  inputTotalCount_d = inputTotalCount_q;
  inputNewCount_d = inputNewCount_q;
  ramWriteIndex_d = ramWriteIndex_q;
  fifoFull_d = fifoFull_q;
  inputIncrToggle_d = inputIncrToggle_q;
  inputIncrValue_d = inputIncrValue_q;
  ramWriteStrobe = 1'b0;

  // Increment the entry count and derive the FIFO full signal, writing the new
  // data into RAM at the same time.
  if (dataInValid_q & ~fifoFull_q)
  begin
    inputTotalCount_d = inputTotalCount_q + 1;
    inputNewCount_d = inputNewCount_q + 1;
    ramWriteIndex_d = ramWriteIndex_q + 1;
    ramWriteStrobe = 1'b1;
    if ({1'b0, inputTotalCount_q} == FifoSize [FifoIndexSize:0] - 1)
      fifoFull_d = 1'b1;
  end

  // Decrement the input entry count after the specified number of entries
  // has been transferred from the read side. Also updates the input increment
  // value for handing off to the read side.
  if (inputDecrStrobe)
  begin
    if (inputDecrValueP2_q != 0)
    begin
      inputTotalCount_d = inputTotalCount_d - inputDecrValueP2_q;
      fifoFull_d = 1'b0;
    end
    inputIncrToggle_d = ~inputIncrToggle_q;
    inputIncrValue_d = inputNewCount_d;
    for (i = 0; i < FifoIndexSize; i = i + 1)
      inputNewCount_d [i] = 1'b0;
  end
end

// Implement sequential logic for FIFO input state machine.
always @(posedge inClk)
begin
  if (inRst)
  begin
    for (i = 0; i < FifoIndexSize; i = i + 1)
    begin
      inputTotalCount_q [i] <= 1'b0;
      inputNewCount_q [i] <= 1'b0;
      ramWriteIndex_q [i] <= 1'b0;
      inputIncrValue_q [i] <= 1'b0;
    end
    fifoFull_q <= 1'b0;
    inputIncrToggle_q <= 1'b0;
  end
  else
  begin
    inputTotalCount_q <= inputTotalCount_d;
    inputNewCount_q <= inputNewCount_d;
    ramWriteIndex_q <= ramWriteIndex_d;
    inputIncrValue_q <= inputIncrValue_d;
    fifoFull_q <= fifoFull_d;
    inputIncrToggle_q <= inputIncrToggle_d;
  end
end

// Implement combinatorial logic for FIFO output state machine.
always @(outputTotalCount_q, outputOldCount_q, ramReadIndex_q, fifoReady_q,
  outputDecrToggle_q, outputDecrValue_q, ramReadHalt, outputIncrStrobe,
  outputIncrValueP2_q)
begin

  // Hold current state by default.
  outputTotalCount_d = outputTotalCount_q;
  outputOldCount_d = outputOldCount_q;
  ramReadIndex_d = ramReadIndex_q;
  fifoReady_d = fifoReady_q;
  outputDecrToggle_d = outputDecrToggle_q;
  outputDecrValue_d = outputDecrValue_q;
  ramReadStrobe = 1'b0;

  // Decrement the entry count and derive the FIFO ready signal, reading the new
  // data from RAM at the same time.
  if (~ramReadHalt & fifoReady_q)
  begin
    outputTotalCount_d = outputTotalCount_q - 1;
    outputOldCount_d = outputOldCount_q + 1;
    ramReadIndex_d = ramReadIndex_q + 1;
    ramReadStrobe = 1'b1;
    if (outputTotalCount_q == 1)
      fifoReady_d = 1'b0;
  end

  // Increment the output entry count after the specified number of entries
  // has been transferred from the write side. Also updates the output decrement
  // value for handing off to the write side.
  if (outputIncrStrobe)
  begin
    if (outputIncrValueP2_q != 0)
    begin
      outputTotalCount_d = outputTotalCount_d + outputIncrValueP2_q;
      fifoReady_d = 1'b1;
    end
    outputDecrToggle_d = ~outputDecrToggle_q;
    outputDecrValue_d = outputOldCount_d;
    for (i = 0; i < FifoIndexSize; i = i + 1)
      outputOldCount_d [i] = 1'b0;
  end
end

// Implement sequential logic for FIFO output state machine.
always @(posedge outClk)
begin
  if (outRst)
  begin
    for (i = 0; i < FifoIndexSize; i = i + 1)
    begin
      outputTotalCount_q [i] <= 1'b0;
      outputOldCount_q [i] <= 1'b0;
      ramReadIndex_q [i] <= 1'b0;
      outputDecrValue_q [i] <= 1'b0;
    end
    fifoReady_q <= 1'b0;
    outputDecrToggle_q <= 1'b1;
  end
  else
  begin
    outputTotalCount_q <= outputTotalCount_d;
    outputOldCount_q <= outputOldCount_d;
    ramReadIndex_q <= ramReadIndex_d;
    outputDecrValue_q <= outputDecrValue_d;
    fifoReady_q <= fifoReady_d;
    outputDecrToggle_q <= outputDecrToggle_d;
  end
end

// Implement retiming registers for input clock domain.
always @(posedge inClk)
begin
  if (inRst)
  begin
    inputDecrToggle_q <= 4'd0;
    for (i = 0; i < FifoIndexSize; i = i + 1)
    begin
      inputDecrValueP1_q [i] <= 1'b0;
      inputDecrValueP2_q [i] <= 1'b0;
    end
  end
  else
  begin
    inputDecrToggle_q <= {outputDecrToggle_q, inputDecrToggle_q [3:1]};
    inputDecrValueP1_q <= outputDecrValue_q;
    inputDecrValueP2_q <= inputDecrValueP1_q;
  end
end

assign inputDecrStrobe = inputDecrToggle_q [0] ^ inputDecrToggle_q [1];

// Implement retiming registers for output clock domain.
always @(posedge outClk)
begin
  if (outRst)
  begin
    outputIncrToggle_q <= 4'd0;
    for (i = 0; i < FifoIndexSize; i = i + 1)
    begin
      outputIncrValueP1_q [i] <= 1'b0;
      outputIncrValueP2_q [i] <= 1'b0;
    end
  end
  else
  begin
    outputIncrToggle_q <= {inputIncrToggle_q, outputIncrToggle_q [3:1]};
    outputIncrValueP1_q <= inputIncrValue_q;
    outputIncrValueP2_q <= outputIncrValueP1_q;
  end
end

assign outputIncrStrobe = outputIncrToggle_q [0] ^ outputIncrToggle_q [1];

// Implement the FIFO RAM write port.
always @(posedge inClk)
begin
  if (ramWriteStrobe)
    ramArray [ramWriteIndex_q] <= dataIn_q;
end

// Implement the FIFO RAM read valid output line.
always @(posedge outClk)
begin
  if (outRst)
    ramReadDataValid_q <= 1'b0;
  else if (~ramReadHalt)
    ramReadDataValid_q <= ramReadStrobe;
end

// Implement the FIFO RAM read port.
always @(posedge outClk)
begin
  if (~ramReadHalt)
    ramReadData_q <= ramArray [ramReadIndex_q];
end

assign ramReadHalt = ramReadDataValid_q & dataOutStop;
assign dataInStop = dataInValid_q & fifoFull_q;
assign dataOutValid = ramReadDataValid_q;
assign dataOut = ramReadData_q;

endmodule
