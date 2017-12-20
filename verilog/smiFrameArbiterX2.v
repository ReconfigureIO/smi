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
// Implements zero wait state alternating arbitration between two SMI inputs
// onto one SMI output.
//

`timescale 1ns/1ps

module smiFrameArbiterX2
  (smiInAReady, smiInAEofc, smiInAData, smiInAStop, smiInBReady, smiInBEofc,
  smiInBData, smiInBStop, smiOutReady, smiOutEofc, smiOutData, smiOutStop,
  clk, srst);

// Specifies the flit width of the SMI interfaces.
parameter FlitWidth = 2;

// Derives the mask for unused end of frame control bits.
parameter EofcMask = 2 * FlitWidth - 1;

// Specifies the state space for the data transfer state machine.
parameter [1:0]
  TransferIdle = 0,
  TransferInA = 1,
  TransferInB = 2;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the input arbitrated interface ports.
input                   smiInAReady;
input [7:0]             smiInAEofc;
input [FlitWidth*8-1:0] smiInAData;
output                  smiInAStop;

input                   smiInBReady;
input [7:0]             smiInBEofc;
input [FlitWidth*8-1:0] smiInBData;
output                  smiInBStop;

// Specifies the output arbitrated interface ports.
output                   smiOutReady;
output [7:0]             smiOutEofc;
output [FlitWidth*8-1:0] smiOutData;
input                    smiOutStop;

// Specifies the SMI input port registers.
reg                   smiInAReady_q;
reg [7:0]             smiInAEofc_q;
reg [FlitWidth*8-1:0] smiInAData_q;
reg                   smiInALast_q;
reg                   smiInAHalt;

reg                   smiInBReady_q;
reg [7:0]             smiInBEofc_q;
reg [FlitWidth*8-1:0] smiInBData_q;
reg                   smiInBLast_q;
reg                   smiInBHalt;

// Specifies the arbitration state machine signals.
reg [1:0] transferState_d;
reg [1:0] transferState_q;

reg                    smiBufReady;
reg [7:0]              smiBufEofc;
reg [FlitWidth*8-1:0]  smiBufData;
wire                   smiBufStop;
wire [FlitWidth*8+7:0] smiOutVec;

// Implements the SMI input port resettable control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    smiInAReady_q <= 1'b0;
    smiInBReady_q <= 1'b0;
  end
  else
  begin
    if (~(smiInAReady_q & smiInAHalt))
      smiInAReady_q <= smiInAReady;
    if (~(smiInBReady_q & smiInBHalt))
      smiInBReady_q <= smiInBReady;
  end
end

assign smiInAStop = smiInAReady_q & smiInAHalt;
assign smiInBStop = smiInBReady_q & smiInBHalt;

// Implements the SMI input port non-resettable datapath registers.
always @(posedge clk)
begin
  if (~(smiInAReady_q & smiInAHalt))
  begin
    smiInAEofc_q <= smiInAEofc & EofcMask[7:0];
    smiInAData_q <= smiInAData;
    smiInALast_q <= (smiInAEofc == 8'b0) ? 1'b0 : 1'b1;
  end
  if (~(smiInBReady_q & smiInBHalt))
  begin
    smiInBEofc_q <= smiInBEofc & EofcMask[7:0];
    smiInBData_q <= smiInBData;
    smiInBLast_q <= (smiInBEofc == 8'b0) ? 1'b0 : 1'b1;
  end
end

// Implements combinatorial logic for arbitration state machine.
always @(transferState_q, smiInAReady_q, smiInAEofc_q, smiInAData_q,
  smiInALast_q, smiInBReady_q, smiInBEofc_q, smiInBData_q, smiInBLast_q,
  smiBufStop)
begin

  // Hold the current state by default.
  transferState_d = transferState_q;
  smiInAHalt = 1'b1;
  smiInBHalt = 1'b1;
  smiBufReady = 1'b0;
  smiBufEofc = smiInAEofc_q;
  smiBufData = smiInAData_q;

  // Implement state machine.
  case (transferState_q)

    // For the transfer A state, pass through the port A signals.
    TransferInA :
    begin
      smiBufReady = smiInAReady_q;
      smiInAHalt = smiBufStop;

      // Switch directly to port B transfer is there is a request waiting.
      if (smiInAReady_q & smiInALast_q & ~smiBufStop)
      begin
        if (smiInBReady_q)
          transferState_d = TransferInB;
        else
          transferState_d = TransferIdle;
      end
    end

    // For the transfer B state, pass through the port B signals.
    TransferInB :
    begin
      smiBufReady = smiInBReady_q;
      smiBufEofc = smiInBEofc_q;
      smiBufData = smiInBData_q;
      smiInBHalt = smiBufStop;

      // Switch directly to port A transfer is there is a request waiting.
      if (smiInBReady_q & smiInBLast_q & ~smiBufStop)
      begin
        if (smiInAReady_q)
          transferState_d = TransferInA;
        else
          transferState_d = TransferIdle;
      end
    end

    // From the idle state, wait for one of the inputs to become ready.
    default :
    begin
      if (smiInAReady_q)
        transferState_d = TransferInA;
      else if (smiInBReady_q)
        transferState_d = TransferInB;
    end
  endcase
end

// Implement sequential logic for arbitration state machine.
always @(posedge clk)
begin
  if (srst)
    transferState_q <= TransferIdle;
  else
    transferState_q <= transferState_d;
end

// Implement FIFO buffer on the output flits.
smiSelfLinkDoubleBuffer #((FlitWidth+1)*8) smiOutBuf
  (smiBufReady, { smiBufEofc, smiBufData }, smiBufStop, smiOutReady, smiOutVec,
  smiOutStop, clk, srst);

assign smiOutEofc = smiOutVec [FlitWidth*8+7:FlitWidth*8];
assign smiOutData = smiOutVec [FlitWidth*8-1:0];

endmodule
