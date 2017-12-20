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
// To minimise AXI bus load, the FIFO buffer uses the W1R2 form.
//

`timescale 1ns/1ps

module smiAxiInputBuffer
  (axiValid, axiDataIn, axiReady, dataOutValid, dataOut, dataOutStop,
  clk, srst);

// Specifes the width of the axiDataIn and dataOut ports.
parameter DataWidth = 16;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the 'upstream' AXI data input ports.
input  [DataWidth-1:0] axiDataIn;
input                  axiValid;
output                 axiReady;

// Specifies the 'downstream' data output ports.
output [DataWidth-1:0] dataOut;
output                 dataOutValid;
input                  dataOutStop;

// Define the FIFO state registers.
reg fifoPopReady_d;
reg fifoPopReady_q;
reg fifoPushReady_d;
reg fifoPushReady_q;

// Define the A and B data registers. Register A is the direct input register.
reg [DataWidth-1:0] dataRegA_d;
reg [DataWidth-1:0] dataRegA_q;
reg [DataWidth-1:0] dataRegB_d;
reg [DataWidth-1:0] dataRegB_q;

// Specifies the common clock enable.
reg clockEnable;

// Miscellaneous signals and variables.
wire fifoPush;
integer i;

// Implement combinatorial FIFO block.
always @(fifoPush, axiDataIn, dataOutStop, fifoPopReady_q, fifoPushReady_q,
  dataRegA_q, dataRegB_q)
begin

  // Hold current state by default.
  clockEnable = 1'b0;
  fifoPopReady_d = fifoPopReady_q;
  fifoPushReady_d = fifoPushReady_q;

  // Push register values on FIFO push strobe.
  if (fifoPush)
  begin
    dataRegA_d = axiDataIn;
    dataRegB_d = dataRegA_q;
  end
  else
  begin
    dataRegA_d = dataRegA_q;
    dataRegB_d = dataRegB_q;
  end

  // Assert AXI ready on reset or push into an empty FIFO.
  if (~fifoPopReady_q)
  begin
    if (~fifoPushReady_q)
    begin
      clockEnable = 1'b1;
      fifoPushReady_d = 1'b1;
    end
    else if (fifoPush)
    begin
      clockEnable = 1'b1;
      fifoPopReady_d = 1'b1;
    end
  end

  // Push, pop or push through single entry FIFO.
  else if (fifoPushReady_q)
  begin
    if ((fifoPush) && (dataOutStop))
    begin
      clockEnable = 1'b1;
      fifoPushReady_d = 1'b0;
    end
    else if ((~fifoPush) && (~dataOutStop))
    begin
      clockEnable = 1'b1;
      fifoPopReady_d = 1'b0;
    end
    else if ((fifoPush) && (~dataOutStop))
    begin
      clockEnable = 1'b1;
    end
  end

  // Pop from a full FIFO.
  else
  begin
    if (~dataOutStop)
    begin
      clockEnable = 1'b1;
      fifoPushReady_d = 1'b1;
    end
  end
end

// Implement sequential FIFO block.
always @(posedge clk)
begin
  if (srst)
  begin
    fifoPopReady_q <= 1'b0;
    fifoPushReady_q <= 1'b0;
    for (i = 0; i < DataWidth; i = i + 1)
    begin
      dataRegA_q[i] <= 1'b0;
      dataRegB_q[i] <= 1'b0;
    end
  end
  else if (clockEnable)
  begin
    fifoPopReady_q <= fifoPopReady_d;
    fifoPushReady_q <= fifoPushReady_d;
    dataRegA_q <= dataRegA_d;
    dataRegB_q <= dataRegB_d;
  end
end

// Derive the data output and control signals.
assign fifoPush = axiValid & fifoPushReady_q;
assign dataOut = fifoPushReady_q ? dataRegA_q : dataRegB_q;
assign dataOutValid = fifoPopReady_q;
assign axiReady = fifoPushReady_q;

endmodule
