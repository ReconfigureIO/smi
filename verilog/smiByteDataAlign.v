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
// Provides support for aligning flit data transfers to their corresponding
// byte lanes, as required by AXI write data transactions. The output consists
// of the newly aliged data words, together with their associated write data
// strobe lines.
//

`timescale 1ns/1ps

module smiByteDataAlign
  (setupReady, byteOffset, setupStop, smiInReady, smiInEofc, smiInData,
  smiInStop, alignedOutReady, alignedOutData, alignedOutStrobes, alignedOutLast,
  alignedOutStop, clk, srst);

// Specifies the width of the flit data input and output ports as an integer
// power of two number of bytes.
parameter FlitWidth = 16;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the address offet input signals.
input       setupReady;
input [7:0] byteOffset;
output      setupStop;

// Specifies the SMI flit input signals.
input                   smiInReady;
input [7:0]             smiInEofc;
input [FlitWidth*8-1:0] smiInData;
output                  smiInStop;

// Specifies the byte aligned output data signals.
output                   alignedOutReady;
output [FlitWidth*8-1:0] alignedOutData;
output [FlitWidth-1:0]   alignedOutStrobes;
output                   alignedOutLast;
input                    alignedOutStop;

// Specifies the address offset and SMI flit input register signals.
reg       setupReady_q;
reg [7:0] byteOffset_q;
reg       setupHalt;

reg                   smiInReady_q;
reg [7:0]             smiInEofc_q;
reg [FlitWidth*8-1:0] smiInData_q;
reg                   smiInHalt;

// Specifies the state space for the byte alignment state machine.
parameter [1:0]
  AlignIdle = 0,
  AlignCopyFrame = 1,
  AlignAddTail = 2;

// Specifies the header injection state machine signals.
reg [1:0]                   alignState_d;
reg [(FlitWidth-1)*8-1:0]   lastFlitData_d;
reg [FlitWidth-2:0]         lastFlitStrobes_d;
reg [7:0]                   shiftOffset_d;

reg [1:0]                   alignState_q;
reg [(FlitWidth-1)*8-1:0]   lastFlitData_q;
reg [FlitWidth-2:0]         lastFlitStrobes_q;
reg [7:0]                   shiftOffset_q;

// Specifies the barrel shifter input signals.
reg                 shiftInValid_d;
reg                 shiftInLast_d;
reg [FlitWidth-1:0] shiftInStrobes_d;
wire                barrelShiftStop;

reg                         shiftInValid_q;
reg                         shiftInLast_q;
reg [(2*FlitWidth-1)*8-1:0] shiftInData_q;
reg [2*FlitWidth-2:0]       shiftInStrobes_q;
reg [7:0]                   shiftInAmount_q;

// Specifies the barrel shifter pipeline signals.
reg [(2*FlitWidth-1)*8-1:0] shiftP1Data_d;
reg [2*FlitWidth-2:0]       shiftP1Strobes_d;

reg                         shiftP1Valid_q;
reg                         shiftP1Last_q;
reg [(2*FlitWidth-1)*8-1:0] shiftP1Data_q;
reg [2*FlitWidth-2:0]       shiftP1Strobes_q;
reg [7:0]                   shiftP1Amount_q;

reg [(2*FlitWidth-1)*8-1:0] shiftP2Data_d;
reg [2*FlitWidth-2:0]       shiftP2Strobes_d;

reg                         shiftP2Valid_q;
reg                         shiftP2Last_q;
reg [(2*FlitWidth-1)*8-1:0] shiftP2Data_q;
reg [2*FlitWidth-2:0]       shiftP2Strobes_q;
reg [7:0]                   shiftP2Amount_q;

reg [(2*FlitWidth-1)*8-1:0] shiftP3Data_d;
reg [2*FlitWidth-2:0]       shiftP3Strobes_d;

reg                   shiftP3Valid_q;
reg                   shiftP3Last_q;
reg [FlitWidth*8-1:0] shiftP3Data_q;
reg [FlitWidth-1:0]   shiftP3Strobes_q;

// Combined output vector.
wire [FlitWidth*9:0] alignedOutVec;

// Miscellaneous signals.
integer i;

// Implement resettable input control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    setupReady_q <= 1'b0;
    smiInReady_q  <= 1'b0;
  end
  else
  begin
    if (~(setupReady_q & setupHalt))
      setupReady_q <= setupReady;
    if (~(smiInReady_q & smiInHalt))
      smiInReady_q <= smiInReady;
  end
end

// Implement non-resettable input data registers.
always @(posedge clk)
begin
  if (~(setupReady_q & setupHalt))
  begin
    byteOffset_q <= byteOffset & (FlitWidth [7:0] - 8'b1);
  end
  if (~(smiInReady_q & smiInHalt))
  begin
    smiInEofc_q <= smiInEofc;
    smiInData_q <= smiInData;
  end
end

assign setupStop = setupReady_q & setupHalt;
assign smiInStop = smiInReady_q & smiInHalt;

// Implement combinatorial logic for byte alignment.
always @(alignState_q, lastFlitData_q, lastFlitStrobes_q, shiftOffset_q,
  setupReady_q, byteOffset_q, smiInReady_q, smiInEofc_q, smiInData_q,
  barrelShiftStop)
begin

  // Hold current state by default.
  alignState_d = alignState_q;
  lastFlitData_d = lastFlitData_q;
  lastFlitStrobes_d = lastFlitStrobes_q;
  shiftOffset_d = shiftOffset_q;
  shiftInValid_d = 1'b0;
  shiftInLast_d = 1'b0;

  setupHalt = 1'b1;
  smiInHalt = 1'b1;

  // Derive the current strobes from the shift offset and end of frame control.
  if (smiInEofc_q == 8'd0)
    for (i = 0; i < FlitWidth; i = i + 1)
      shiftInStrobes_d [i] = 1'b1;
  else
    for (i = 0; i < FlitWidth; i = i + 1)
      shiftInStrobes_d [i] = (i[7:0] < smiInEofc_q) ? 1'b1 : 1'b0;

  // Implement state machine.
  case (alignState_q)

    // Copy over the body of the frame, carrying the upper set of bytes over to
    // the next flit if required.
    AlignCopyFrame :
    begin
      shiftInValid_d = smiInReady_q;
      smiInHalt = barrelShiftStop;
      if (smiInReady_q & ~barrelShiftStop)
      begin
        lastFlitData_d = smiInData_q [FlitWidth*8-1:8];
        lastFlitStrobes_d = shiftInStrobes_d [FlitWidth-1:1];

        // At end of input frame we need to add an extra flit for overflow.
        if ({1'b0, smiInEofc_q} + {1'b0, shiftOffset_q} > FlitWidth [8:0])
        begin
          alignState_d = AlignAddTail;
        end

        // Alternatively, terminate the frame if the last flit fits.
        else if (smiInEofc_q != 0)
        begin
          alignState_d = AlignIdle;
          shiftInLast_d = 1'b1;
        end
      end
    end

    // Add an extra flit to the end of the frame.
    AlignAddTail :
    begin
      shiftInValid_d = 1'b1;
      shiftInLast_d = 1'b1;
      for (i = 0; i < FlitWidth; i = i + 1)
        shiftInStrobes_d [i] = 1'b0;
      if (~barrelShiftStop)
        alignState_d = AlignIdle;
    end

    // From the idle state, wait for the offset to become available.
    default :
    begin
      for (i = 0; i < (FlitWidth-1)*8; i = i + 1)
        lastFlitData_d [i] = 1'b0;
      for (i = 0; i < FlitWidth-1; i = i + 1)
        lastFlitStrobes_d [i] = 1'b0;
      shiftOffset_d = byteOffset_q;
      setupHalt = 1'b0;
      if (setupReady_q)
        alignState_d = AlignCopyFrame;
    end
  endcase

end

// Implement resettable sequential logic for state machine control signals.
always @(posedge clk)
begin
  if (srst)
    alignState_q <= AlignIdle;
  else
    alignState_q <= alignState_d;
end

// Implement non-resettable sequential logic for state machine data signals.
always @(posedge clk)
begin
  lastFlitData_q    <= lastFlitData_d;
  lastFlitStrobes_q <= lastFlitStrobes_d;
  shiftOffset_q     <= shiftOffset_d;
end

// Implement resettable barrel shifter input control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    shiftInValid_q <= 1'b0;
    shiftP1Valid_q <= 1'b0;
    shiftP2Valid_q <= 1'b0;
    shiftP3Valid_q <= 1'b0;
  end
  else if (~barrelShiftStop)
  begin
    shiftInValid_q <= shiftInValid_d;
    shiftP1Valid_q <= shiftInValid_q;
    shiftP2Valid_q <= shiftP1Valid_q;
    shiftP3Valid_q <= shiftP2Valid_q;
  end
end

// Implement non-resettable barrel shifter input data registers.
always @(posedge clk)
begin
  if (~barrelShiftStop)
  begin
    shiftInLast_q    <= shiftInLast_d;
    shiftInAmount_q  <= shiftOffset_q;
    shiftInData_q    <= { smiInData_q, lastFlitData_q };
    shiftInStrobes_q <= { shiftInStrobes_d, lastFlitStrobes_q };
  end
end

// Implement first barrel shifter stage logic.
always @(shiftInData_q, shiftInStrobes_q, shiftInAmount_q)
begin
  shiftP1Data_d    = shiftInData_q;
  shiftP1Strobes_d = shiftInStrobes_q;

  // Shift on bit 0.
  if ((shiftInAmount_q & 8'd1) != 8'd0)
  begin
    for (i = (2*FlitWidth-1)*8-1; i >= 8; i = i - 1)
      shiftP1Data_d [i] = shiftP1Data_d [i-8];
    for (i = 2*FlitWidth-2; i >= 1; i = i - 1)
      shiftP1Strobes_d [i] = shiftP1Strobes_d [i-1];
  end

  // Shift on bit 3.
  if ((shiftInAmount_q & 8'd8) != 8'd0)
  begin
    for (i = (2*FlitWidth-1)*8-1; i >= 64; i = i - 1)
      shiftP1Data_d [i] = shiftP1Data_d [i-64];
    for (i = 2*FlitWidth-2; i >= 8; i = i - 1)
      shiftP1Strobes_d [i] = shiftP1Strobes_d [i-8];
  end

end

// Implement first barrel shifter stage registers.
always @(posedge clk)
begin
  if (~barrelShiftStop)
  begin
    shiftP1Last_q    <= shiftInLast_q;
    shiftP1Amount_q  <= shiftInAmount_q;
    shiftP1Data_q    <= shiftP1Data_d;
    shiftP1Strobes_q <= shiftP1Strobes_d;
  end
end

// Implement second barrel shifter stage logic.
always @(shiftP1Data_q, shiftP1Strobes_q, shiftP1Amount_q)
begin
  shiftP2Data_d    = shiftP1Data_q;
  shiftP2Strobes_d = shiftP1Strobes_q;

  // Shift on bit 1.
  if ((shiftP1Amount_q & 8'd2) != 8'd0)
  begin
    for (i = (2*FlitWidth-1)*8-1; i >= 16; i = i - 1)
      shiftP2Data_d [i] = shiftP2Data_d [i-16];
    for (i = 2*FlitWidth-2; i >= 2; i = i - 1)
      shiftP2Strobes_d [i] = shiftP2Strobes_d [i-2];
  end

  // Shift on bit 4.
  if ((shiftP1Amount_q & 8'd16) != 8'd0)
  begin
    for (i = (2*FlitWidth-1)*8-1; i >= 128; i = i - 1)
      shiftP2Data_d [i] = shiftP2Data_d [i-128];
    for (i = 2*FlitWidth-2; i >= 16; i = i - 1)
      shiftP2Strobes_d [i] = shiftP2Strobes_d [i-16];
  end

end

// Implement second barrel shifter stage registers.
always @(posedge clk)
begin
  if (~barrelShiftStop)
  begin
    shiftP2Last_q    <= shiftP1Last_q;
    shiftP2Amount_q  <= shiftP1Amount_q;
    shiftP2Data_q    <= shiftP2Data_d;
    shiftP2Strobes_q <= shiftP2Strobes_d;
  end
end

// Implement third barrel shifter stage logic.
always @(shiftP2Data_q, shiftP2Strobes_q, shiftP2Amount_q)
begin
  shiftP3Data_d    = shiftP2Data_q;
  shiftP3Strobes_d = shiftP2Strobes_q;

  // Shift on bit 2.
  if ((shiftP2Amount_q & 8'd4) != 8'd0)
  begin
    for (i = (2*FlitWidth-1)*8-1; i >= 32; i = i - 1)
      shiftP3Data_d [i] = shiftP3Data_d [i-32];
    for (i = 2*FlitWidth-2; i >= 4; i = i - 1)
      shiftP3Strobes_d [i] = shiftP3Strobes_d [i-4];
  end

  // Shift on bit 5.
  if ((shiftP2Amount_q & 8'd32) != 8'd0)
  begin
    for (i = (2*FlitWidth-1)*8-1; i >= 256; i = i - 1)
      shiftP3Data_d [i] = shiftP3Data_d [i-256];
    for (i = 2*FlitWidth-2; i >= 32; i = i - 1)
      shiftP3Strobes_d [i] = shiftP3Strobes_d [i-32];
  end

  // Shift on bit 6.
  if ((shiftP2Amount_q & 8'd64) != 8'd0)
  begin
    for (i = (2*FlitWidth-1)*8-1; i >= 512; i = i - 1)
      shiftP3Data_d [i] = shiftP3Data_d [i-512];
    for (i = 2*FlitWidth-2; i >= 64; i = i - 1)
      shiftP3Strobes_d [i] = shiftP3Strobes_d [i-64];
  end

end

// Implement third barrel shifter stage registers.
always @(posedge clk)
begin
  if (~barrelShiftStop)
  begin
    shiftP3Last_q    <= shiftP2Last_q;
    shiftP3Data_q    <= shiftP3Data_d [(2*FlitWidth-1)*8-1:(FlitWidth-1)*8];
    shiftP3Strobes_q <= shiftP3Strobes_d [2*FlitWidth-2:FlitWidth-1];
  end
end

// Implement double buffering on the output flits.
smiSelfLinkDoubleBuffer #(FlitWidth*9+1) smiOutBuf
  (shiftP3Valid_q, { shiftP3Last_q, shiftP3Strobes_q, shiftP3Data_q  },
  barrelShiftStop, alignedOutReady, alignedOutVec, alignedOutStop, clk, srst);

assign alignedOutLast = alignedOutVec [FlitWidth*9];
assign alignedOutStrobes = alignedOutVec [FlitWidth*9-1:FlitWidth*8];
assign alignedOutData = alignedOutVec [FlitWidth*8-1:0];

endmodule

