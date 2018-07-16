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
// The SMI frame dropper is a frame aware FIFO which allows entire SMI frames
// to be 'dropped' if an overflow condition occurs, with the output only
// becoming ready once an entire frame has been committed. This uses an internal
// circular buffer which supports write pointer resets in the case of input
// overflow conditions. Note that in the event that a single frame exceeds the
// FIFO length the frame will always be dropped. There is an additional status
// output which indicates an overflow condition which will be asserted for the
// entire duration of each frame that follows a previously dropped frame. There
// is also an out of band user status signal which may be used to transfer
// frame status information.
//

`timescale 1ns/1ps

module smiFrameDropper
  (dataInValid, dataInEofc, dataIn, dataInStatus, dataInStop, dataOutValid,
  dataOutEofc, dataOut, dataOutStatus, dataOutStop, frameDropped, dropCountReset,
  dropCount, clk, srst);

// Specifes the flit width of the data channel, expressed as an integer power
// of two number of bytes.
parameter FlitWidth = 8;

// Specifies the frame status signal width.
parameter StatusWidth = 4;

// Specifies the link buffer FIFO size (maximum 65536).
parameter FifoSize = 64;

// Specifies the maximum number of frames which may be queued by the frame
// assembler component (maximum 63).
parameter MaxFrameCount = 16;

// Specifies the link buffer FIFO index size, which should be capable of holding
// the binary representation of FifoSize-1.
parameter FifoIndexSize = (FifoSize <= 2) ? 1 : (FifoSize <= 4) ? 2 :
  (FifoSize <= 8) ? 3 : (FifoSize <= 16) ? 4 : (FifoSize <= 32) ? 5 :
  (FifoSize <= 64) ? 6 : (FifoSize <= 128) ? 7 : (FifoSize <= 256) ? 8 :
  (FifoSize <= 512) ? 9 : (FifoSize <= 1024) ? 10 : (FifoSize <= 2048) ? 11 :
  (FifoSize <= 4096) ? 12 : (FifoSize <= 8192) ? 13 : (FifoSize <= 16384) ? 14 :
  (FifoSize <= 32768) ? 15 : (FifoSize <= 65536) ? 16 : -1;

// Specifies the maximum frame counter size, which should be capable of holding
// the binary representation of MaxFrameCount-1.
parameter MaxFrameCountSize = (MaxFrameCount <= 2) ? 1 : (MaxFrameCount <= 4) ? 2 :
  (MaxFrameCount <= 8) ? 3 : (MaxFrameCount <= 16) ? 4 : (MaxFrameCount <= 32) ? 5 :
  (MaxFrameCount <= 64) ? 6 : -1;

// Specifies the 'upstream' data input ports.
input                   dataInValid;
input [7:0]             dataInEofc;
input [FlitWidth*8-1:0] dataIn;
input [StatusWidth-1:0] dataInStatus;
output                  dataInStop;

// Specifies the 'downstream' data output ports.
output                   dataOutValid;
output [7:0]             dataOutEofc;
output [FlitWidth*8-1:0] dataOut;
output [StatusWidth-1:0] dataOutStatus;
input                    dataOutStop;

// Dropped frame notification signals. the frame dropped signal indicates that
// one or more frames that precede the current received frame have been dropped
// and the counter output provides a running total of the number of dropped
// frames.
output        frameDropped;
input         dropCountReset;
output [31:0] dropCount;

// Specify system level signals.
input clk;
input srst;

// Specify the data input registers.
reg                   dataInValid_q;
reg                   dataInEof_q;
reg [7:0]             dataInEofc_q;
reg [StatusWidth-1:0] dataInStatus_q;
reg [FlitWidth*8-1:0] dataIn_q;

// Specify the input state machine registers.
reg                     discardFrame_d;
reg                     overflowFlag_d;
reg [FifoIndexSize-1:0] entryCount_d;
reg [FifoIndexSize-1:0] frameCount_d;
reg [FifoIndexSize-1:0] writeAddr_d;
reg [FifoIndexSize-1:0] writeBaseAddr_d;
reg                     writePipeEn_d;
reg [31:0]              dropCount_d;

reg                     discardFrame_q;
reg                     overflowFlag_q;
reg [FifoIndexSize-1:0] entryCount_q;
reg [FifoIndexSize-1:0] frameCount_q;
reg [FifoIndexSize-1:0] writeAddr_q;
reg [FifoIndexSize-1:0] writeBaseAddr_q;
reg                     writePipeEn_q;
reg [31:0]              dropCount_q;

reg [FifoIndexSize-1:0] writePipeAddr_q;
reg [FlitWidth*8-1:0]   writePipeData_q;

// Specify the output state machine registers.
reg                     outputActive_d;
reg [FifoIndexSize-1:0] outputCount_d;
reg [StatusWidth+8:0]   outputFrameInfo_d;
reg [FifoIndexSize-1:0] readAddr_d;
reg                     readPipeValidP1_d;
reg [FifoIndexSize-1:0] readPipeAddr_d;
reg [7:0]               readPipeEofcP1_d;
reg                     readPipeOverflowP1_d;
reg [StatusWidth-1:0]   readPipeStatusP1_d;

reg                     outputActive_q;
reg [FifoIndexSize-1:0] outputCount_q;
reg [StatusWidth+8:0]   outputFrameInfo_q;
reg [FifoIndexSize-1:0] readAddr_q;
reg                     readPipeValidP1_q;
reg [FifoIndexSize-1:0] readPipeAddr_q;
reg [7:0]               readPipeEofcP1_q;
reg                     readPipeOverflowP1_q;
reg [StatusWidth-1:0]   readPipeStatusP1_q;

// Intermediate FIFO signals.
wire entryCountDecr;
reg  inputFrameInfoPush;
wire inputFrameInfoStop;
wire outputFrameInfoValid;
wire outputFrameInfoStop;

wire                     frameInfoOverflow;
wire [7:0]               frameInfoEofc;
wire [StatusWidth-1:0]   frameInfoStatus;
wire [FifoIndexSize-1:0] frameInfoSize;

// RAM array signals.
reg [FlitWidth*8-1:0] ramArray [(1 << FifoIndexSize)-1:0];
reg [FlitWidth*8-1:0] ramReadData_q;

// Output read pipeline signals.
reg                   readPipeValidP2_q;
reg [7:0]             readPipeEofcP2_q;
reg                   readPipeOverflowP2_q;
reg [StatusWidth-1:0] readPipeStatusP2_q;
reg                   outputValid_q;
reg [FlitWidth*8-1:0] outputData_q;
reg [7:0]             outputEofc_q;
reg                   outputOverflow_q;
reg [StatusWidth-1:0] outputStatus_q;
wire                  readPipeStop;

// Miscellaneous signals.
wire [31:0] zeros = 32'd0;

// Implement resettable input control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    dataInValid_q <= 1'b0;
    dataInEof_q <= 1'b0;
  end
  else
  begin
    dataInValid_q <= dataInValid;
    dataInEof_q <= (dataInEofc == 8'd0) ? 1'b0 : 1'b1;
  end
end

// Implement non-resettable input datapath registers.
always @(posedge clk)
begin
  dataInEofc_q <= dataInEofc;
  dataIn_q <= dataIn;
  dataInStatus_q <= dataInStatus;
end

// Note that the input never blocks because we discard frames instead of
// applying backpressure.
assign dataInStop = 1'b0;

// Implement combinatorial logic for input frame processing state machine.
// Note that this must never block the data input, so all processing must
// complete in a single cycle.
always @(discardFrame_q, overflowFlag_q, entryCount_q, frameCount_q, writeAddr_q,
  writeBaseAddr_q, dropCount_q, dataInValid_q, dataInEof_q, inputFrameInfoStop,
  entryCountDecr, dropCountReset, zeros)
begin

  // Hold current state by default.
  discardFrame_d = discardFrame_q;
  overflowFlag_d = overflowFlag_q;
  entryCount_d = entryCount_q;
  frameCount_d = frameCount_q;
  writeAddr_d = writeAddr_q;
  writeBaseAddr_d = writeBaseAddr_q;
  dropCount_d = dropCount_q;
  writePipeEn_d = 1'b0;
  inputFrameInfoPush = 1'b0;

  // Perform updates on data input valid strobe.
  if (dataInValid_q)
  begin

    // Implement normal data push if the frame isn't being discarded.
    if (~dataInEof_q)
    begin
      if (~discardFrame_q)
      begin
        if ({1'b0, entryCount_q} == FifoSize [FifoIndexSize:0] - 1)
        begin
          discardFrame_d = 1'b1;
        end
        else
        begin
          entryCount_d = entryCount_q + 1;
          frameCount_d = frameCount_q + 1;
          writeAddr_d = writeAddr_q + 1;
          writePipeEn_d = 1'b1;
        end
      end
    end

    // Process end of discarded frame.
    else if (discardFrame_q | inputFrameInfoStop)
    begin
      discardFrame_d = 1'b0;
      overflowFlag_d = 1'b1;
      entryCount_d = entryCount_q - frameCount_q;
      frameCount_d = zeros [FifoIndexSize-1:0];
      writeAddr_d = writeBaseAddr_q;
      dropCount_d = dropCount_q + 32'd1;
    end

    // Process end of good frame.
    else
    begin
      discardFrame_d = 1'b0;
      overflowFlag_d = 1'b0;
      entryCount_d = entryCount_q + 1;
      frameCount_d = 0;
      writeAddr_d = writeAddr_q + 1;
      writeBaseAddr_d = writeAddr_d;
      writePipeEn_d = 1'b1;
      inputFrameInfoPush = 1'b1;
    end
  end

  // Decrement entry count on output data pop.
  if (entryCountDecr)
  begin
    entryCount_d = entryCount_d - 1;
  end

  // Reset the dropped frame counter if required.
  if (dropCountReset)
  begin
    dropCount_d = 32'd0;
  end
end

// Implement resettable input state machine control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    discardFrame_q <= 1'b0;
    overflowFlag_q <= 1'b0;
    entryCount_q <= zeros [FifoIndexSize-1:0];
    frameCount_q <= zeros [FifoIndexSize-1:0];
    writeAddr_q <= zeros [FifoIndexSize-1:0];
    writeBaseAddr_q <= zeros [FifoIndexSize-1:0];
    writePipeEn_q <= 1'b0;
    dropCount_q <= 32'd0;
  end
  else
  begin
    discardFrame_q <= discardFrame_d;
    overflowFlag_q <= overflowFlag_d;
    entryCount_q <= entryCount_d;
    frameCount_q <= frameCount_d;
    writeAddr_q <= writeAddr_d;
    writeBaseAddr_q <= writeBaseAddr_d;
    writePipeEn_q <= writePipeEn_d;
    dropCount_q <= dropCount_d;
  end
end

// Implement non-resettable input status machine datapath registers.
always @(posedge clk)
begin
  writePipeAddr_q <= writeAddr_q;
  writePipeData_q <= dataIn_q;
end

// Instantiate the frame information FIFO.
smiSelfLinkBufferFifoS #(FifoIndexSize+StatusWidth+9, MaxFrameCount, MaxFrameCountSize) frameInfoFifo
  (inputFrameInfoPush, {overflowFlag_q, dataInEofc_q, dataInStatus_q, frameCount_q},
  inputFrameInfoStop, outputFrameInfoValid, {frameInfoOverflow, frameInfoEofc,
  frameInfoStatus, frameInfoSize}, outputFrameInfoStop, clk, srst);

// Implement combinatorial logic for output frame processing state machine.
always @(outputActive_q, outputCount_q, outputFrameInfo_q, readAddr_q,
  readPipeValidP1_q, readPipeAddr_q, readPipeEofcP1_q, readPipeOverflowP1_q,
  readPipeStatusP1_q, outputFrameInfoValid, frameInfoOverflow, frameInfoEofc,
  frameInfoStatus, frameInfoSize, readPipeStop, zeros)
begin

  // Hold current state by default.
  outputActive_d = outputActive_q;
  outputCount_d = outputCount_q;
  outputFrameInfo_d = outputFrameInfo_q;
  readAddr_d = readAddr_q;
  readPipeValidP1_d = readPipeValidP1_q;
  readPipeAddr_d = readPipeAddr_q;
  readPipeEofcP1_d = readPipeEofcP1_q;
  readPipeOverflowP1_d = readPipeOverflowP1_q;
  readPipeStatusP1_d = readPipeStatusP1_q;

  // Wait for a new frame to become available.
  if (~outputActive_q)
  begin
    readPipeValidP1_d = 1'b0;
    if (outputFrameInfoValid)
    begin
      outputActive_d = 1'b1;
      outputCount_d = frameInfoSize;
      outputFrameInfo_d = {frameInfoStatus, frameInfoOverflow, frameInfoEofc};
    end
  end

  // Process active frame when the read output is not stopped.
  else
  begin
    outputCount_d = outputCount_q - 1;
    readAddr_d = readAddr_q + 1;
    readPipeValidP1_d = 1'b1;
    readPipeAddr_d = readAddr_q;
    readPipeOverflowP1_d = outputFrameInfo_q [8];
    readPipeStatusP1_d = outputFrameInfo_q [StatusWidth+8:9];

    // Terminate on end of frame.
    if (outputCount_q == zeros [FifoIndexSize-1:0])
    begin
      outputActive_d = 1'b0;
      readPipeEofcP1_d = outputFrameInfo_q [7:0];
    end

    // Continue for remaining frame body.
    else
    begin
      readPipeEofcP1_d = 8'd0;
    end
  end
end

// Implement resettable registers for read state machine control logic.
always @(posedge clk)
begin
  if (srst)
  begin
    outputActive_q <= 1'b0;
    readAddr_q <= zeros [FifoIndexSize-1:0];
    readPipeValidP1_q <= 1'b0;
    readPipeOverflowP1_q <= 1'b0;
    readPipeStatusP1_q <= zeros [StatusWidth-1:0];
  end
  else if (~readPipeStop)
  begin
    outputActive_q <= outputActive_d;
    readAddr_q <= readAddr_d;
    readPipeValidP1_q <= readPipeValidP1_d;
    readPipeOverflowP1_q <= readPipeOverflowP1_d;
    readPipeStatusP1_q <= readPipeStatusP1_d;
  end
end

assign entryCountDecr = readPipeValidP1_q & ~readPipeStop;
assign outputFrameInfoStop = outputActive_q | readPipeStop;

// Implement non-resettable registers for read state machine datapath logic.
always @(posedge clk)
begin
  if (~readPipeStop)
  begin
    outputCount_q <= outputCount_d;
    outputFrameInfo_q <= outputFrameInfo_d;
    readPipeAddr_q <= readPipeAddr_d;
    readPipeEofcP1_q <= readPipeEofcP1_d;
  end
end

// Implement FIFO RAM.
always @(posedge clk)
begin
  if (writePipeEn_q)
    ramArray [writePipeAddr_q] <= writePipeData_q;
  if (~readPipeStop)
    ramReadData_q <= ramArray [readPipeAddr_q];
end

// Implement resettable control registers for read pipeline delay matching and
// data output.
always @(posedge clk)
begin
  if (srst)
  begin
    readPipeValidP2_q <= 1'b0;
    outputValid_q <= 1'b0;
  end
  else if (~readPipeStop)
  begin
    readPipeValidP2_q <= readPipeValidP1_q;
    outputValid_q <= readPipeValidP2_q;
  end
end

// Implement non-resettable datapath registers for read pipeline delay matching
// and data output.
always @(posedge clk)
begin
  if (~readPipeStop)
  begin
    readPipeEofcP2_q <= readPipeEofcP1_q;
    readPipeOverflowP2_q <= readPipeOverflowP1_q;
    readPipeStatusP2_q <= readPipeStatusP1_q;
    outputData_q <= ramReadData_q;
    outputEofc_q <= readPipeEofcP2_q;
    outputOverflow_q <= readPipeOverflowP2_q;
    outputStatus_q <= readPipeStatusP2_q;
  end
end

assign readPipeStop = dataOutStop & outputValid_q;
assign dataOutValid = outputValid_q;
assign dataOutEofc = outputEofc_q;
assign dataOut = outputData_q;
assign dataOutStatus = outputStatus_q;
assign frameDropped = outputOverflow_q;
assign dropCount = dropCount_q;

endmodule
