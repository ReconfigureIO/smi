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
// Implementation of an AXI Stream to SMI Frame converter which conforms to the
// AXI Stream requirements. Acts as an input adaptor from the external AXI
// Stream protocol to SMI. Note that support for AXI 'user' signals is included
// which is not part of the standard SMI protocol. If unused, the user signal
// width should be set to 1 and the associated input port tied low.
//

`timescale 1ns/1ps

module smiAxisInputAdaptor
  (axisInValid, axisInData, axisInKeep, axisInUser, axisInLast, axisInReady,
  smiOutValid, smiOutData, smiOutEofc, smiOutUser, smiOutStop, clk, srst);

// Specifies the number of bits required to address individual bytes within the
// AXI data signal. This also determines the width of the data signal.
parameter DataIndexSize = 3;

// Specifies the width of the AXI User signal for out of band control.
parameter UserWidth = 1;

// Derives the width of the data input and output ports.
parameter DataWidth = (1 << DataIndexSize) * 8;

// Derives the width of the AXI Slave keep port.
parameter KeepWidth = (1 << DataIndexSize);

// Specifies the AXI Stream input signals.
input                 axisInValid;
input [DataWidth-1:0] axisInData;
input [KeepWidth-1:0] axisInKeep;
input [UserWidth-1:0] axisInUser;
input                 axisInLast;
output                axisInReady;

// Specifies the SMI Frame output signals.
output                 smiOutValid;
output [DataWidth-1:0] smiOutData;
output [7:0]           smiOutEofc;
output [UserWidth-1:0] smiOutUser;
input                  smiOutStop;

// Specifies the clock and synchronous reset input signals.
input clk;
input srst;

// Specify the internal AXI Stream signals.
wire [KeepWidth-1:0] axisKeep;
wire                 axisLast;
reg  [7:0]           smiEofc;

// Miscellaneous signals.
integer i;

// Implement AXI input buffer registers.
smiAxiInputBuffer #(DataWidth+KeepWidth+UserWidth+1) axiInputBuffer
  (axisInValid, {axisInData, axisInKeep, axisInUser, axisInLast}, axisInReady,
  smiOutValid, {smiOutData, axisKeep, smiOutUser, axisLast}, smiOutStop,
  clk, srst);

// Map AXI Stream control signals to SMI EOFC. This assumes the keep signal
// conforms to the AXI Stream spec, so that the most significant active bit
// can be used to determine the number of valid bytes in the final flit.
always @ (axisKeep, axisLast)
begin
  if (~axisLast)
  begin
    smiEofc = 8'h00;
  end
  else
  begin
    smiEofc = 8'hFF;
    for (i = 1; i <= KeepWidth; i = i + 1)
      if (axisKeep [i-1])
        smiEofc = i [7:0];
  end
end

assign smiOutEofc = smiEofc;

endmodule
