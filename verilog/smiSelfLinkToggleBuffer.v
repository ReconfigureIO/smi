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
// Implementation of a SELF based single stage elastic buffer, using the
// 'W1R1' buffer form with toggle based flow control. The toggle operation
// ensures that flow control signals have a low fanout, but will restrict
// throughput to one token every two clock cycles. This is a fully synchronous
// implementation which is suitable for use in FPGA designs.
//

`timescale 1ns/1ps

module smiSelfLinkToggleBuffer
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

// Define the flow control state registers.
reg inputCycle_d;
reg outputCycle_d;
reg inputCycle_q;
reg outputCycle_q;

// Define the data register.
reg [DataWidth-1:0] dataReg_q;

// Implement combinatorial logic for input/output toggle. Accepts incoming data
// if the buffer is empty, otherwise waits for the data out stop line to be
// taken low.
always @(inputCycle_q, outputCycle_q, dataInValid, dataOutStop)
begin

  // Hold current state by default.
  inputCycle_d = inputCycle_q;
  outputCycle_d = outputCycle_q;

  // Wait for new data during input cycle.
  if (inputCycle_q)
  begin
    if (dataInValid)
    begin
      inputCycle_d = 1'b0;
      outputCycle_d = 1'b1;
    end
  end

  // Wait for data output stop signal to clear on output cycle.
  else if (outputCycle_q)
  begin
    if (~dataOutStop)
    begin
      inputCycle_d = 1'b1;
      outputCycle_d = 1'b0;
    end
  end

  // Start a new input cycle after reset.
  else
  begin
    inputCycle_d = 1'b1;
    outputCycle_d = 1'b0;
  end
end

// Implement sequential logic for resettable control signals.
always @(posedge clk)
begin
  if (srst)
  begin
    inputCycle_q <= 1'b0;
    outputCycle_q <= 1'b0;
  end
  else
  begin
    inputCycle_q <= inputCycle_d;
    outputCycle_q <= outputCycle_d;
  end
end

// Implement sequential logic for non-resettable datapath signals.
always @(posedge clk)
begin
  if (inputCycle_q)
  begin
    dataReg_q <= dataIn;
  end
end

// Derive the data output and control signals.
assign dataOut = dataReg_q;
assign dataOutValid = outputCycle_q;
assign dataInStop = ~inputCycle_q;

endmodule
