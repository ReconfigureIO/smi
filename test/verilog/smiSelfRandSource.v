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
// Implements a compact 64-bit pseudo-random number source which generates a
// new pseudo-random value on each clock cycle when the SELF 'stop' line is low.
// This uses the fast xorshift+ algorithm proposed by Sebastiano Vigna which
// has a period of 2^128-1 and which has been demonstrated to pass the Big
// Crush test suite.
//

`timescale 1ns/1ps

module smiSelfRandSource
  (resultReady, resultData, resultStop, clk, srst);

// Specify output datapath width. Must be no more than 64 bits wide.
parameter DataWidth = 32;

// Specify random number generator seed. Must be a non-zero positive value.
parameter RandSeed = 64'h373E7B7D27C69FA4;

// Specify the random number output port.
output                 resultReady;
output [DataWidth-1:0] resultData;
input                  resultStop;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specify the random number generator state signals.
reg [63:0] xorS0_d;
reg [63:0] xorS1_d;

reg [63:0] xorS0_q;
reg [63:0] xorS1_q;

// Specify the output pipeline stages.
reg                 resultReady_q;
reg [DataWidth-1:0] resultData_q;

// Pipeline resets for large number of resettable registers.
reg localReset;

// Pipeline the reset.
always @(posedge clk)
begin
  if (srst)
    localReset <= 1'b1;
  else
    localReset <= 1'b0;
end

// Implement combinatorial logic for the XOR shift operation.
always @(xorS0_q, xorS1_q)
begin
  xorS0_d = xorS1_q;
  xorS1_d = xorS0_q;
  xorS1_d = xorS1_d ^ {xorS1_d [40:0], 23'd0};
  xorS1_d = xorS1_d ^ {18'd0, xorS1_d [63:18]};
  xorS1_d = xorS1_d ^ xorS0_d ^ {5'd0, xorS0_d [63:5]};
end

// Implement sequential logic for the XOR shift operation.
always @(posedge clk)
begin
  if (localReset)
  begin
    xorS0_q <= RandSeed [63:0];
    xorS1_q <= 64'd0;
  end
  else if (~(resultReady_q & resultStop))
  begin
    xorS0_q <= xorS0_d;
    xorS1_q <= xorS1_d;
  end
end

// Implement resettable output control registers.
always @(posedge clk)
begin
  if (localReset)
    resultReady_q <= 1'b0;
  else if (~(resultReady_q & resultStop))
    resultReady_q <= 1'b1;
end

// Implement non-resettable output data register with term summation.
always @(posedge clk)
begin
  if (~(resultReady_q & resultStop))
    resultData_q <= xorS0_q [63:64-DataWidth] + xorS1_q [63:64-DataWidth];
end

assign resultReady = resultReady_q;
assign resultData = resultData_q;

endmodule

