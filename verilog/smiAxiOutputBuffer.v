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
// Implementation of an AXI to SELF input buffer which conforms to the AXI
// requirements. Note that the AXI specification usually requires asynchronous
// resets, but a synchronous reset is used here to account for the fact that
// the reset signal is derived from the Donut action interface state machine.
// To minimise AXI bus logic, the FIFO buffer uses the W2R1 form.
//

`timescale 1ns/1ps

module smiAxiOutputBuffer
  (dataInValid, dataIn, dataInStop, axiValid, axiDataOut, axiReady,
  clk, srst);

// Specifes the width of the dataIn and dataOut ports.
parameter DataWidth = 16;

// Specifies the clock and active high asynchronous reset signals.
input clk;
input srst;

// Specifies the 'upstream' data input ports.
input  [DataWidth-1:0] dataIn;
input                  dataInValid;
output                 dataInStop;

// Specifies the 'downstream' AXI output ports.
output [DataWidth-1:0] axiDataOut;
output                 axiValid;
input                  axiReady;

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

// Miscellaneous signals and variables.
integer i;
wire fifoPop;

// Implement combinatorial FIFO block.
always @(dataIn, dataInValid, fifoPop, dataRegA_q, dataRegB_q, fifoReady_q,
  fifoFull_q)
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
    if ((dataInValid) && (~fifoPop))
    begin
      clockEnable = 1'b1;
      fifoFull_d = 1'b1;
      dataRegB_d = dataRegB_q;
    end
    else if ((~dataInValid) && (fifoPop))
    begin
      clockEnable = 1'b1;
      fifoReady_d = 1'b0;
    end
    else if ((dataInValid) && (fifoPop))
    begin
      clockEnable = 1'b1;
      dataRegB_d = dataIn;
    end
  end

  // Pop from full FIFO, moving buffer register contents to output.
  else
  begin
    if (fifoPop)
    begin
      clockEnable = 1'b1;
      fifoFull_d = 1'b0;
    end
  end
end

// Implement sequential FIFO block.
always @(posedge clk)
begin
  if (srst)
  begin
    fifoReady_q <= 1'b0;
    fifoFull_q <= 1'b1;
    for (i = 0; i < DataWidth; i = i + 1)
    begin
      dataRegA_q[i] <= 1'b0;
      dataRegB_q[i] <= 1'b0;
    end
  end
  else if (clockEnable)
  begin
    fifoReady_q <= fifoReady_d;
    fifoFull_q <= fifoFull_d;
    dataRegA_q <= dataRegA_d;
    dataRegB_q <= dataRegB_d;
  end
end

// Derive the data output and control signals.
assign fifoPop = fifoReady_q & axiReady;
assign axiDataOut = dataRegB_q;
assign axiValid = fifoReady_q;
assign dataInStop = fifoFull_q;

endmodule
