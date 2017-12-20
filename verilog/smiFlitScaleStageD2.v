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
// Provides support for SMI flit width scaling. This is a single scaling stage
// which reduces the flit width by a factor of 2.
//

`timescale 1ns/1ps

module smiFlitScaleStageD2
  (smiInReady, smiInEofc, smiInData, smiInStop, smiOutReady, smiOutEofc,
  smiOutData, smiOutStop, clk, srst);

// Specifies the width of the flit data input port as an integer power of two
// number of bytes.
parameter FlitWidth = 4;

// Derives the mask for unused end of frame control bits.
parameter EofcMask = 2 * FlitWidth - 1;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the SMI input signals.
input                   smiInReady;
input [7:0]             smiInEofc;
input [FlitWidth*8-1:0] smiInData;
output                  smiInStop;

// Specifies the SMI output signals.
output                   smiOutReady;
output [7:0]             smiOutEofc;
output [FlitWidth*4-1:0] smiOutData;
input                    smiOutStop;

// Specifies the SMI input register signals.
reg                   smiInReady_q;
reg [7:0]             smiInEofc_q;
reg [FlitWidth*8-1:0] smiInData_q;
reg                   smiInLastLow_q;
reg                   smiInLastHigh_q;
reg                   smiInHalt;

// Specifies the SMI bus width reduction signals.
reg                   rdcDataReady_d;
reg                   rdcDataPhase_d;
reg [FlitWidth*4-1:0] rdcDataMux_d;
reg [7:0]             rdcDataEofc_d;

reg                   rdcDataReady_q;
reg                   rdcDataPhase_q;
reg [FlitWidth*4-1:0] rdcDataMux_q;
reg [7:0]             rdcDataEofc_q;
wire                  rdcDataHalt;

// Implement the resettable input control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    smiInReady_q <= 1'd0;
    smiInLastLow_q <= 1'd0;
    smiInLastHigh_q <= 1'd0;
  end
  else if (~(smiInReady_q & smiInHalt))
  begin
    smiInReady_q <= smiInReady;
    if (smiInReady)
      if (smiInEofc == 8'd0)
      begin
        smiInLastLow_q <= 1'b0;
        smiInLastHigh_q <= 1'b0;
      end
      else if (smiInEofc <= FlitWidth[8:1])
      begin
        smiInLastLow_q <= 1'b1;
        smiInLastHigh_q <= 1'b0;
      end
      else
      begin
        smiInLastLow_q <= 1'b0;
        smiInLastHigh_q <= 1'b1;
      end
  end
end

// Implement the non-resettable input datapath registers.
always @(posedge clk)
begin
  if (~(smiInReady_q & smiInHalt))
  begin
    smiInEofc_q <= smiInEofc & EofcMask[7:0];
    smiInData_q <= smiInData;
  end
end

assign smiInStop = smiInReady_q & smiInHalt;

// Combinatorial logic for carrying out bus width reduction.
always @(rdcDataReady_q, rdcDataPhase_q, rdcDataMux_q, rdcDataEofc_q, smiInReady_q,
  smiInEofc_q, smiInData_q, smiInLastLow_q, smiInLastHigh_q, rdcDataHalt)
begin

  // Hold current state by default.
  rdcDataReady_d = 1'b0;
  rdcDataPhase_d = rdcDataPhase_q;
  rdcDataMux_d = rdcDataMux_q;
  rdcDataEofc_d = rdcDataEofc_q;
  smiInHalt = 1'b1;

  // Update on new input.
  if (smiInReady_q)
  begin
    rdcDataPhase_d = ~rdcDataPhase_q;
    rdcDataEofc_d = 8'd0;

    // Process 'low' data phase.
    if (~rdcDataPhase_q)
    begin
      rdcDataReady_d = 1'b1;
      rdcDataMux_d = smiInData_q[FlitWidth*4-1:0];
      if (smiInLastLow_q)
      begin
        rdcDataPhase_d = 1'b0;
        rdcDataEofc_d = smiInEofc_q;
        smiInHalt = rdcDataReady_q & rdcDataHalt;
      end
    end

    // Process 'high' data phase.
    else
    begin
      rdcDataReady_d = 1'b1;
      rdcDataMux_d = smiInData_q[FlitWidth*8-1:FlitWidth*4];
      smiInHalt = rdcDataReady_q & rdcDataHalt;
      if (smiInLastHigh_q)
      begin
        rdcDataEofc_d = smiInEofc_q - FlitWidth[8:1];
      end
    end
  end
end

// Resettable control logic for carrying out bus width reduction.
always @(posedge clk)
begin
  if (srst)
  begin
    rdcDataReady_q <= 1'b0;
    rdcDataPhase_q <= 1'b0;
  end
  else if (~(rdcDataReady_q & rdcDataHalt))
  begin
    rdcDataReady_q <= rdcDataReady_d;
    rdcDataPhase_q <= rdcDataPhase_d;
  end
end

// Non-resettable datapath logic for carrying out bus width expansion.
always @(posedge clk)
begin
  if (~(rdcDataReady_q & rdcDataHalt))
  begin
    rdcDataMux_q <= rdcDataMux_d;
    rdcDataEofc_q <= rdcDataEofc_d;
  end
end

// Map the output port signals.
assign smiOutReady = rdcDataReady_q;
assign smiOutEofc = rdcDataEofc_q;
assign smiOutData = rdcDataMux_q;
assign rdcDataHalt = smiOutStop;

endmodule
