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
// Implements message steering to four SMI outputs from one SMI input based on
// message type field matching. Matching message types are steered to outputs
// A, B, C or D and non-matching message types are discarded.
//

`timescale 1ns/1ps

module smiFrameSteerX4
  (smiInReady, smiInEofc, smiInData, smiInStop, smiOutAReady, smiOutAEofc,
  smiOutAData, smiOutAStop, smiOutBReady, smiOutBEofc, smiOutBData, smiOutBStop,
  smiOutCReady, smiOutCEofc, smiOutCData, smiOutCStop, smiOutDReady, smiOutDEofc,
  smiOutDData, smiOutDStop, clk, srst);

// Specifies the flit width of the SMI interfaces. Must be at least 4.
parameter FlitWidth = 16;

// Specifies the message type matching word value for output A.
parameter TypeMatchA = 0;

// Specifies the message type matching word value for output B.
parameter TypeMatchB = 1;

// Specifies the message type matching word value for output B.
parameter TypeMatchC = 2;

// Specifies the message type matching word value for output B.
parameter TypeMatchD = 3;

// Specifies the message type matching mask. Mask bits which are set to zero
// denote don't care bits.
parameter TypeMask = 3;

// Derives the mask for unused end of frame control bits.
parameter EofcMask = 2 * FlitWidth - 1;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the input combined interface ports.
input                   smiInReady;
input [7:0]             smiInEofc;
input [FlitWidth*8-1:0] smiInData;
output                  smiInStop;

// Specifies the output steered data interface ports.
output                   smiOutAReady;
output [7:0]             smiOutAEofc;
output [FlitWidth*8-1:0] smiOutAData;
input                    smiOutAStop;

output                   smiOutBReady;
output [7:0]             smiOutBEofc;
output [FlitWidth*8-1:0] smiOutBData;
input                    smiOutBStop;

output                   smiOutCReady;
output [7:0]             smiOutCEofc;
output [FlitWidth*8-1:0] smiOutCData;
input                    smiOutCStop;

output                   smiOutDReady;
output [7:0]             smiOutDEofc;
output [FlitWidth*8-1:0] smiOutDData;
input                    smiOutDStop;

// Specifies the SMI input port registers.
reg                   smiInReady_q;
reg [7:0]             smiInEofc_q;
reg [FlitWidth*8-1:0] smiInData_q;
reg                   smiInLast_q;
reg                   smiInSteerA_q;
reg                   smiInSteerB_q;
reg                   smiInSteerC_q;
reg                   smiInSteerD_q;
wire                  smiInHalt;

// Specifies the SMI output buffer signals.
wire                   smiBufAReady;
wire                   smiBufAStop;
wire [FlitWidth*8+7:0] smiOutAVec;

wire                   smiBufBReady;
wire                   smiBufBStop;
wire [FlitWidth*8+7:0] smiOutBVec;

wire                   smiBufCReady;
wire                   smiBufCStop;
wire [FlitWidth*8+7:0] smiOutCVec;

wire                   smiBufDReady;
wire                   smiBufDStop;
wire [FlitWidth*8+7:0] smiOutDVec;

// Implement resettable SMI input control registers with integrated end of
// frame detection logic.
always @(posedge clk)
begin
  if (srst)
  begin
    smiInReady_q <= 1'b0;
    smiInLast_q <= 1'b1;
  end
  else if (~(smiInReady_q & smiInHalt))
  begin
    smiInReady_q <= smiInReady;
    if (smiInReady)
      smiInLast_q <= (smiInEofc == 8'd0) ? 1'b0 : 1'b1;
  end
end

assign smiInStop = smiInReady_q & smiInHalt;

// Implement non-resettable SMI input data registers with integrated steer
// selection logic.
always @(posedge clk)
begin
  if (~(smiInReady_q & smiInHalt))
  begin
    smiInEofc_q <= smiInEofc & EofcMask[7:0];
    smiInData_q <= smiInData;
    if (smiInLast_q)
    begin
      smiInSteerA_q <=
        ((TypeMask[31:0] & (TypeMatchA[31:0] ^ smiInData[31:0])) == 32'd0) ? 1'b1 : 1'b0;
      smiInSteerB_q <=
        ((TypeMask[31:0] & (TypeMatchB[31:0] ^ smiInData[31:0])) == 32'd0) ? 1'b1 : 1'b0;
      smiInSteerC_q <=
        ((TypeMask[31:0] & (TypeMatchC[31:0] ^ smiInData[31:0])) == 32'd0) ? 1'b1 : 1'b0;
      smiInSteerD_q <=
        ((TypeMask[31:0] & (TypeMatchD[31:0] ^ smiInData[31:0])) == 32'd0) ? 1'b1 : 1'b0;
    end
  end
end

// Implement SMI signal mux into output buffers.
assign smiBufAReady = smiInReady_q & smiInSteerA_q;
assign smiBufBReady = smiInReady_q & smiInSteerB_q;
assign smiBufCReady = smiInReady_q & smiInSteerC_q;
assign smiBufDReady = smiInReady_q & smiInSteerD_q;

assign smiInHalt = (smiInSteerA_q & smiBufAStop) |
                   (smiInSteerB_q & smiBufBStop) |
                   (smiInSteerC_q & smiBufCStop) |
                   (smiInSteerD_q & smiBufDStop);

// Instantiate output buffers.
smiSelfLinkDoubleBuffer #((FlitWidth+1)*8) smiBufA
  (smiBufAReady, {smiInEofc_q, smiInData_q}, smiBufAStop,
  smiOutAReady, smiOutAVec, smiOutAStop, clk, srst);

assign smiOutAEofc = smiOutAVec [FlitWidth*8+7:FlitWidth*8];
assign smiOutAData = smiOutAVec [FlitWidth*8-1:0];

smiSelfLinkDoubleBuffer #((FlitWidth+1)*8) smiBufB
  (smiBufBReady, {smiInEofc_q, smiInData_q}, smiBufBStop,
  smiOutBReady, smiOutBVec, smiOutBStop, clk, srst);

assign smiOutBEofc = smiOutBVec [FlitWidth*8+7:FlitWidth*8];
assign smiOutBData = smiOutBVec [FlitWidth*8-1:0];

smiSelfLinkDoubleBuffer #((FlitWidth+1)*8) smiBufC
  (smiBufCReady, {smiInEofc_q, smiInData_q}, smiBufCStop,
  smiOutCReady, smiOutCVec, smiOutCStop, clk, srst);

assign smiOutCEofc = smiOutCVec [FlitWidth*8+7:FlitWidth*8];
assign smiOutCData = smiOutCVec [FlitWidth*8-1:0];

smiSelfLinkDoubleBuffer #((FlitWidth+1)*8) smiBufD
  (smiBufDReady, {smiInEofc_q, smiInData_q}, smiBufDStop,
  smiOutDReady, smiOutDVec, smiOutDStop, clk, srst);

assign smiOutDEofc = smiOutDVec [FlitWidth*8+7:FlitWidth*8];
assign smiOutDData = smiOutDVec [FlitWidth*8-1:0];

endmodule
