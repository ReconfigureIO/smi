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
// Provides support for extracting a header from an SMI frame. This is the
// 'partial single flit header' variant, which should be used when the header
// size is less than the flit data width.
//

`timescale 1ns/1ps

module smiHeaderExtractPf1
  (smiInReady, smiInEofc, smiInData, smiInStop, headerReady, headerData,
  headerStop, smiOutReady, smiOutEofc, smiOutData, smiOutStop, clk, srst);

// Specifies the width of the flit data input and output ports as an integer
// power of two number of bytes.
parameter FlitWidth = 16;

// Specifies the width of the header input as an integer number of bytes. Must
// be less than the flit data width.
parameter HeadWidth = 4;

// Specifies the internal FIFO depths (between 3 and 128 entries).
parameter FifoSize = 16;

// Specifies the internal FIFO index size, which should be capable of holding
// the binary representation of FifoSize-2.
parameter FifoIndexSize = (FifoSize <= 2) ? -1 : (FifoSize <= 3) ? 1 :
  (FifoSize <= 5) ? 2 : (FifoSize <= 9) ? 3 : (FifoSize <= 17) ? 4 :
  (FifoSize <= 33) ? 5 : (FifoSize <= 65) ? 6 : (FifoSize <= 129) ? 7 : -1;

// Derives the output flit split point from the flit and head widths.
parameter FlitSplit = FlitWidth - HeadWidth;

// Derives the mask for unused end of frame control bits.
parameter EofcMask = 2 * FlitWidth - 1;

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;

// Specifies the SMI flit input signals.
input                   smiInReady;
input [7:0]             smiInEofc;
input [FlitWidth*8-1:0] smiInData;
output                  smiInStop;

// Specifies the header output signals.
output                   headerReady;
output [HeadWidth*8-1:0] headerData;
input                    headerStop;

// Specifies the SMI flit output signals.
output                   smiOutReady;
output [7:0]             smiOutEofc;
output [FlitWidth*8-1:0] smiOutData;
input                    smiOutStop;

// Specifies the SMI flit input register signals.
reg                   smiInReady_q;
reg [7:0]             smiInEofc_q;
reg [FlitWidth*8-1:0] smiInData_q;
reg                   smiInHalt;

// Specifies the state space for the header extraction state machine.
parameter [1:0]
  ExtractIdle = 0,
  ExtractCopyFrame = 1,
  ExtractAddTail = 2;

// Specifies the header extraction state machine signals.
reg [1:0]             extractState_d;
reg [FlitSplit*8-1:0] lastFlitData_d;
reg [7:0]             lastFlitEofc_d;

reg [1:0]             extractState_q;
reg [FlitSplit*8-1:0] lastFlitData_q;
reg [7:0]             lastFlitEofc_q;

// Specifies the output buffer signals.
reg                        headerBufReady;
reg [HeadWidth*8-1:0]      headerBufData;
wire                       headerBufStop;

reg                        smiOutBufReady;
reg [7:0]                  smiOutBufEofc;
reg [FlitWidth*8-1:0]      smiOutBufData;
wire                       smiOutBufStop;
wire [(FlitWidth+1)*8-1:0] smiOutVec;

// Implement resettable input control registers.
always @(posedge clk)
begin
  if (srst)
    smiInReady_q <= 1'b0;
  else
    if (~(smiInReady_q & smiInHalt))
      smiInReady_q <= smiInReady;
end

// Implement non-resettable input data registers.
always @(posedge clk)
begin
  if (~(smiInReady_q & smiInHalt))
  begin
    smiInEofc_q <= smiInEofc & EofcMask[7:0];
    smiInData_q <= smiInData;
  end
end

assign smiInStop = smiInReady_q & smiInHalt;

// Implement combinatorial logic for header extraction.
always @(extractState_q, lastFlitData_q, lastFlitEofc_q, smiInReady_q,
  smiInEofc_q, smiInData_q, headerBufStop, smiOutBufStop)
begin

  // Hold current state by default.
  extractState_d = extractState_q;
  lastFlitData_d = lastFlitData_q;
  lastFlitEofc_d = lastFlitEofc_q;
  smiInHalt = 1'b1;
  headerBufReady = 1'b0;
  headerBufData = smiInData_q [HeadWidth*8-1:0];
  smiOutBufReady = 1'b0;
  smiOutBufData = { smiInData_q [HeadWidth*8-1:0], lastFlitData_q };
  smiOutBufEofc = 8'b0;

  // Implement state machine.
  case (extractState_q)

    // Copy over the body of the frame, carrying the upper set of bytes over to
    // the next flit if required.
    ExtractCopyFrame :
    begin
      smiOutBufReady = smiInReady_q;
      smiInHalt = smiOutBufStop;
      if (smiInReady_q & ~smiOutBufStop)
      begin
        lastFlitData_d = smiInData_q [FlitWidth*8-1:HeadWidth*8];
        lastFlitEofc_d = smiInEofc_q;

        // At end of input frame we need to add an extra flit for overflow.
        if (smiInEofc_q > HeadWidth [7:0])
        begin
          extractState_d = ExtractAddTail;
        end

        // Alternatively, terminate the frame if the last flit fits.
        else if (smiInEofc_q != 8'd0)
        begin
          extractState_d = ExtractIdle;
          smiOutBufEofc = smiInEofc_q + FlitSplit [7:0];
        end
      end
    end

    // Add an extra flit to the end of the frame.
    ExtractAddTail :
    begin
      smiOutBufReady = 1'b1;
      smiOutBufEofc = lastFlitEofc_q - HeadWidth [7:0];
      if (~smiOutBufStop)
        extractState_d = ExtractIdle;
    end

    // From the idle state, wait for the first flit to become available.
    default :
    begin
      lastFlitData_d = smiInData_q [FlitWidth*8-1:HeadWidth*8];
      lastFlitEofc_d = smiInEofc_q;
      headerBufReady = smiInReady_q;
      smiInHalt = headerBufStop;

      // Either copy the frame contents or just transfer the residual contents
      // of the initial flit if it is the only one in the frame.
      if (smiInReady_q & ~headerBufStop)
      begin
        if (smiInEofc_q == 8'd0)
          extractState_d = ExtractCopyFrame;
        else
          extractState_d = ExtractAddTail;
      end
    end
  endcase

end

// Implement resettable sequential logic for state machine control signals.
always @(posedge clk)
begin
  if (srst)
    extractState_q <= ExtractIdle;
  else
    extractState_q <= extractState_d;
end

// Implement non-resettable sequential logic for state machine data signals.
always @(posedge clk)
begin
  lastFlitData_q <= lastFlitData_d;
  lastFlitEofc_q <= lastFlitEofc_d;
end

// Implement toggle buffer on the header output.
smiSelfLinkToggleBuffer #(HeadWidth*8) headerOutBuf
  (headerBufReady, headerBufData, headerBufStop, headerReady, headerData,
  headerStop, clk, srst);

// Implement FIFO buffer on the output flits.
smiSelfLinkBufferFifoS #((FlitWidth+1)*8, FifoSize, FifoIndexSize) smiOutBuf
  (smiOutBufReady, { smiOutBufEofc, smiOutBufData }, smiOutBufStop,
  smiOutReady, smiOutVec, smiOutStop, clk, srst);

assign smiOutEofc = smiOutVec [(FlitWidth+1)*8-1:FlitWidth*8];
assign smiOutData = smiOutVec [FlitWidth*8-1:0];

endmodule
