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
// Implementation of an SMI Frame to AXI Stream converter which conforms to the
// AXI Stream requirements. Acts as an output adaptor from SMI to the external
// AXI Stream protocol. Note that support for AXI 'user' signals is included
// which is not part of the standard SMI protocol. If unused, the user signal
// width should be set to 1 and the associated input port tied low.
//

`timescale 1ns/1ps

module smiAxisOutputAdaptor
  (smiInValid, smiInData, smiInEofc, smiInUser, smiInStop, axisOutValid,
  axisOutData, axisOutKeep, axisOutUser, axisOutLast, axisOutReady,
  clk, srst);

// Specifies the number of bits required to address individual bytes within the
// AXI data signal. This also determines the width of the data signal.
parameter DataIndexSize = 3;

// Specifies the width of the AXI User signal for out of band control.
parameter UserWidth = 1;

// Derives the width of the data input and output ports.
parameter DataWidth = (1 << DataIndexSize) * 8;

// Derives the width of the AXI Slave keep port.
parameter KeepWidth = (1 << DataIndexSize);

// Specifies the SMI Frame input signals.
input                 smiInValid;
input [DataWidth-1:0] smiInData;
input [7:0]           smiInEofc;
input [UserWidth-1:0] smiInUser;
output                smiInStop;

// Specifies the AXI Stream output signals.
output                 axisOutValid;
output [DataWidth-1:0] axisOutData;
output [KeepWidth-1:0] axisOutKeep;
output [UserWidth-1:0] axisOutUser;
output                 axisOutLast;
input                  axisOutReady;

// Specifies the clock and synchronous reset input signals.
input clk;
input srst;

// Specify the internal AXI Stream signals.
reg [KeepWidth-1:0] axisKeep;
reg                 axisLast;

// Miscellaneous signals.
integer i;

// Implement AXI output buffer registers.
smiAxiOutputBuffer #(DataWidth+KeepWidth+UserWidth+1) axiOutputBuffer
  (smiInValid, {smiInData, axisKeep, smiInUser, axisLast}, smiInStop,
  axisOutValid, {axisOutData, axisOutKeep, axisOutUser, axisOutLast},
  axisOutReady, clk, srst);

// Map SMI EOFC to AXI Stream control signals.
always @ (smiInEofc)
begin
  if (smiInEofc == 8'h00)
  begin
    axisLast = 1'b0;
    for (i = 0; i < KeepWidth; i = i + 1)
      axisKeep [i] = 1'b1;
  end
  else
  begin
    axisLast = 1'b1;
    for (i = 0; i < KeepWidth; i = i + 1)
      axisKeep [i] = (i [7:0] < smiInEofc) ? 1'b1 : 1'b0;
  end
end

endmodule
