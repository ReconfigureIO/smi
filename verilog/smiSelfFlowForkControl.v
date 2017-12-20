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
// Implementation of a SELF based dataflow 'fork' controller using pipelined
// eager forwarding. It manages the SELF handshakes for a configurable number
// of pass-through outputs.
//

`timescale 1ns/1ps

module smiSelfFlowForkControl
  (ctrlInReady, ctrlInStop, ctrlOutReady, ctrlOutStop, clk, srst);

// Specifies the number of fork output branches.
parameter NumPorts = 2;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the 'upstream' control input ports.
input  ctrlInReady;
output ctrlInStop;

// Specifies the 'downstream' control output ports.
output [NumPorts-1:0] ctrlOutReady;
input  [NumPorts-1:0] ctrlOutStop;

// Specifies eager fork control signal.
reg                ctrlInHalt;
reg [NumPorts-1:0] ctrlOutValid;
reg [NumPorts-1:0] eagerValid_d;
reg [NumPorts-1:0] eagerValid_q;

// Miscellaneous signals.
integer i;

// Implement combinatorial logic for eager fork handshake.
always @(ctrlInReady, ctrlOutStop, eagerValid_q)
begin

  // Stop the input on any stopped output.
  ctrlInHalt = |(eagerValid_q & ctrlOutStop);

  // Clear the eager valid flags as their respective outputs complete.
  if (ctrlInReady & ctrlInHalt)
    eagerValid_d = eagerValid_q & ctrlOutStop;
  else
    for (i = 0; i < NumPorts; i = i + 1)
      eagerValid_d [i] = 1'b1;

  // Drive the valid output lines on a valid input.
  if (ctrlInReady)
    ctrlOutValid = eagerValid_q;
  else
    for (i = 0; i < NumPorts; i = i + 1)
      ctrlOutValid [i] = 1'b0;

end

// Implement sequential logic for eager fork handshake.
always @(posedge clk)
begin
  if (srst)
    for (i = 0; i < NumPorts; i = i + 1)
      eagerValid_q [i] <= 1'b1;
  else
    eagerValid_q <= eagerValid_d;
end

// Assign outputs.
assign ctrlInStop = ctrlInHalt;
assign ctrlOutReady = ctrlOutValid;

endmodule
