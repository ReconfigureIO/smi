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
// Implementation of a SELF based elastic buffer, using the 'W2R1' FIFO form
// given in the paper by Cortadella et al. This configuration effectively
// implements 'double buffering' to ensure maximum datapath throughput without
// introducing combinatorial paths on the SELF control signals. Because of the
// double buffering, up to two SELF control tokens may be held by the buffer
// at any given time. Therefore it may also be viewed as a two entry SELF link
// FIFO component.
//

`timescale 1ns/1ps

module smiSelfLinkDoubleBuffer
  (dataInValid, dataIn, dataInStop, dataOutValid, dataOut, dataOutStop,
  clk, srst);

// Specifes the width of the dataIn and dataOut ports.
parameter DataWidth = 16;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the 'upstream' data input ports.
input  [DataWidth-1:0] dataIn;
input                  dataInValid;
output                 dataInStop;

// Specifies the 'downstream' data output ports.
output [DataWidth-1:0] dataOut;
output                 dataOutValid;
input                  dataOutStop;

// Define the FIFO state registers.
reg fifoReady_d;
reg fifoReady_q;
reg fifoFull_d;
reg fifoFull_q;

// Define the A and B data registers. Register B is the output register and
// register A is the input buffer register.
reg [DataWidth-1:0] dataRegA_d;
reg [DataWidth-1:0] dataRegA_q;
reg [DataWidth-1:0] dataRegB_d;
reg [DataWidth-1:0] dataRegB_q;

// Specifies the common clock enable.
reg clockEnable;

// Implement combinatorial FIFO block.
always @(dataIn, dataInValid, dataOutStop, dataRegA_q, dataRegB_q,
  fifoReady_q, fifoFull_q)
begin

  // Hold current state by default. The default behaviour for register A is
  // to load directly from the input and the default behaviour for register
  // B is to load the contents of register A.
  clockEnable = 1'b0;
  fifoReady_d = fifoReady_q;
  fifoFull_d = fifoFull_q;
  dataRegA_d = dataIn;
  dataRegB_d = dataRegA_q;

  // Clear stop on reset or push into empty FIFO.
  if (~fifoReady_q)
  begin
    if (fifoFull_q)
    begin
      clockEnable = 1'b1;
      fifoFull_d = 1'b0;
    end
    else if (dataInValid)
    begin
      clockEnable = 1'b1;
      fifoReady_d = 1'b1;
      dataRegB_d = dataIn;
    end
  end

  // Push, pop or push through single entry FIFO.
  else if (~fifoFull_q)
  begin
    if ((dataInValid) && (dataOutStop))
    begin
      clockEnable = 1'b1;
      fifoFull_d = 1'b1;
      dataRegB_d = dataRegB_q;
    end
    else if ((~dataInValid) && (~dataOutStop))
    begin
      clockEnable = 1'b1;
      fifoReady_d = 1'b0;
    end
    else if ((dataInValid) && (~dataOutStop))
    begin
      clockEnable = 1'b1;
      dataRegB_d = dataIn;
    end
  end

  // Pop from full FIFO, moving buffer register contents to output.
  else
  begin
    if (~dataOutStop)
    begin
      clockEnable = 1'b1;
      fifoFull_d = 1'b0;
    end
  end
end

// Implement sequential logic for resettable control signals.
always @(posedge clk)
begin
  if (srst)
  begin
    fifoReady_q <= 1'b0;
    fifoFull_q <= 1'b1;
  end
  else if (clockEnable)
  begin
    fifoReady_q <= fifoReady_d;
    fifoFull_q <= fifoFull_d;
  end
end

// Implement sequential logic for non-resettable datapath signals.
always @(posedge clk)
begin
  if (clockEnable)
  begin
    dataRegA_q <= dataRegA_d;
    dataRegB_q <= dataRegB_d;
  end
end

// Derive the data output and control signals.
assign dataOut = dataRegB_q;
assign dataOutValid = fifoReady_q;
assign dataInStop = fifoFull_q;

endmodule
