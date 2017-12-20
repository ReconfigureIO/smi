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
// Provides support for injecting a header into an SMI frame. This is the
// 'partial two flit header' variant, which should be used when the header size
// is between 1 and 2 flit data widths.
//

`timescale 1ns/1ps

module smiHeaderInjectPf2
  (headerReady, headerData, headerStop, smiInReady, smiInEofc, smiInData,
  smiInStop, smiOutReady, smiOutEofc, smiOutData, smiOutStop, clk, srst);

// Specifies the width of the flit data input and output ports as an integer
// power of two number of bytes.
parameter FlitWidth = 8;

// Specifies the width of the header input as an integer number of bytes. Must
// be between one and two times the flit data width.
parameter HeadWidth = 14;

// Specifies the internal FIFO depths (more than 3 entries).
parameter FifoSize = 16;

// Specifies the internal FIFO index size, which should be capable of holding
// the binary representation of FifoSize-1.
parameter FifoIndexSize = 4;

// Derives the header with for flit 2.
parameter Head2Width = HeadWidth - FlitWidth;

// Derives the input flit split point from the flit and head widths.
parameter FlitSplit = FlitWidth - Head2Width;

// Derives the mask for unused end of frame control bits.
parameter EofcMask = 2 * FlitWidth - 1;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the header input signals.
input                   headerReady;
input [HeadWidth*8-1:0] headerData;
output                  headerStop;

// Specifies the SMI flit input signals.
input                   smiInReady;
input [7:0]             smiInEofc;
input [FlitWidth*8-1:0] smiInData;
output                  smiInStop;

// Specifies the SMI flit output signals.
output                   smiOutReady;
output [7:0]             smiOutEofc;
output [FlitWidth*8-1:0] smiOutData;
input                    smiOutStop;

// Specifies the header and SMI flit input register signals.
reg                   headerReady_q;
reg [HeadWidth*8-1:0] headerData_q;
reg                   headerHalt;

reg                   smiInReady_q;
reg [7:0]             smiInEofc_q;
reg [FlitWidth*8-1:0] smiInData_q;
reg                   smiInHalt;

// Specifies the state space for the header injection state machine.
parameter [1:0]
  InjectIdle = 0,
  InjectFirstFlit = 1,
  InjectCopyFrame = 2,
  InjectAddTail = 3;

// Specifies the header injection state machine signals.
reg [1:0]              injectState_d;
reg [FlitWidth*8-1:0]  firstFlitData_d;
reg [Head2Width*8-1:0] lastFlitData_d;
reg [7:0]              lastFlitEofc_d;

reg [1:0]              injectState_q;
reg [FlitWidth*8-1:0]  firstFlitData_q;
reg [Head2Width*8-1:0] lastFlitData_q;
reg [7:0]              lastFlitEofc_q;

// Specifies the output buffer signals.
reg                        smiOutBufReady;
reg [7:0]                  smiOutBufEofc;
reg [FlitWidth*8-1:0]      smiOutBufData;
wire                       smiOutBufStop;
wire [(FlitWidth+1)*8-1:0] smiOutVec;

// Implement resettable input control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    headerReady_q <= 1'b0;
    smiInReady_q <= 1'b0;
  end
  else
  begin
    if (~(headerReady_q & headerHalt))
      headerReady_q <= headerReady;
    if (~(smiInReady_q & smiInHalt))
      smiInReady_q <= smiInReady;
  end
end

// Implement non-resettable input data registers.
always @(posedge clk)
begin
  if (~(headerReady_q & headerHalt))
  begin
    headerData_q <= headerData;
  end
  if (~(smiInReady_q & smiInHalt))
  begin
    smiInEofc_q <= smiInEofc & EofcMask[7:0];
    smiInData_q <= smiInData;
  end
end

assign headerStop = headerReady_q & headerHalt;
assign smiInStop = smiInReady_q & smiInHalt;

// Implement combinatorial logic for header injection.
always @(injectState_q, firstFlitData_q, lastFlitData_q, lastFlitEofc_q,
  headerReady_q, headerData_q, smiInReady_q, smiInEofc_q, smiInData_q,
  smiOutBufStop)
begin

  // Hold current state by default.
  injectState_d = injectState_q;
  firstFlitData_d = firstFlitData_q;
  lastFlitData_d = lastFlitData_q;
  lastFlitEofc_d = lastFlitEofc_q;
  headerHalt = 1'b1;
  smiInHalt = 1'b1;
  smiOutBufReady = 1'b0;
  smiOutBufData = { smiInData_q [FlitSplit*8-1:0], lastFlitData_q };
  smiOutBufEofc = 8'b0;

  // Implement state machine.
  case (injectState_q)

    // Insert the first header flit.
    InjectFirstFlit :
    begin
      smiOutBufReady = 1'b1;
      smiOutBufData = firstFlitData_q;
      if (~smiOutBufStop)
        injectState_d = InjectCopyFrame;
    end

    // Copy over the body of the frame, carrying the upper set of bytes over to
    // the next flit if required.
    InjectCopyFrame :
    begin
      smiOutBufReady = smiInReady_q;
      smiInHalt = smiOutBufStop;
      if (smiInReady_q & ~smiOutBufStop)
      begin
        lastFlitData_d = smiInData_q [FlitWidth*8-1:FlitSplit*8];
        lastFlitEofc_d = smiInEofc_q;

        // At end of input frame we need to add an extra flit for overflow.
        if (smiInEofc_q > FlitSplit [7:0])
        begin
          injectState_d = InjectAddTail;
        end

        // Alternatively, terminate the frame if the last flit fits.
        else if (smiInEofc_q != 0)
        begin
          injectState_d = InjectIdle;
          smiOutBufEofc = smiInEofc_q + Head2Width [7:0];
        end
      end
    end

    // Add an extra flit to the end of the frame.
    InjectAddTail :
    begin
      smiOutBufReady = 1'b1;
      smiOutBufEofc = lastFlitEofc_q - FlitSplit [7:0];
      if (~smiOutBufStop)
        injectState_d = InjectIdle;
    end

    // From the idle state, wait for the header to become available.
    default :
    begin
      headerHalt = 1'b0;
      firstFlitData_d = headerData_q [FlitWidth*8-1:0];
      lastFlitData_d = headerData_q [HeadWidth*8-1:FlitWidth*8];
      lastFlitEofc_d = 8'd0;
      if (headerReady_q)
        injectState_d = InjectFirstFlit;
    end
  endcase

end

// Implement resettable sequential logic for state machine control signals.
always @(posedge clk)
begin
  if (srst)
    injectState_q <= InjectIdle;
  else
    injectState_q <= injectState_d;
end

// Implement non-resettable sequential logic for state machine data signals.
always @(posedge clk)
begin
  firstFlitData_q <= firstFlitData_d;
  lastFlitData_q <= lastFlitData_d;
  lastFlitEofc_q <= lastFlitEofc_d;
end

// Implement FIFO buffer on the output flits.
smiSelfLinkBufferFifoS #((FlitWidth+1)*8, FifoSize, FifoIndexSize) smiOutBuf
  (smiOutBufReady, { smiOutBufEofc, smiOutBufData }, smiOutBufStop,
  smiOutReady, smiOutVec, smiOutStop, clk, srst);

assign smiOutEofc = smiOutVec [(FlitWidth+1)*8-1:FlitWidth*8];
assign smiOutData = smiOutVec [FlitWidth*8-1:0];

endmodule
