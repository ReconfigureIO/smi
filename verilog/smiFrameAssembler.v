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
// The SMI frame assembler is a frame aware FIFO which allows SMI frames to be
// 'assembled' by slowly presenting frame data at the input, with the output
// only becoming ready once an entire frame has been committed in this manner.
// Using SMI frame assemblers ensures that a complete frame is available before
// requesting routing or arbitration slots that would otherwise block on
// incomplete frames. This instantiates the SRL based 'small' SELF FIFO
// component for FIFOs of less than 128 flits in length and the circular buffer
// variant for larger FIFOs. In the event that a single frame exceeds the FIFO
// length the data output will be enabled before the entire frame has been
// received at the input in order to prevent it from blocking.
//

`timescale 1ns/1ps

module smiFrameAssembler
  (dataInValid, dataInEofc, dataIn, dataInStop, dataOutValid, dataOutEofc,
  dataOut, dataOutStop, clk, srst);

// Specifes the flit width of the data channel, expressed as an integer power
// of two number of bytes.
parameter FlitWidth = 8;

// Specifies the link buffer FIFO size (maximum 1024).
parameter FifoSize = 64;

// Specifies the maximum number of frames which may be queued by the frame
// assembler component (maximum 63).
parameter MaxFrameCount = 2;

// Specifies the link buffer FIFO index size, which should be capable of holding
// the binary representation of FifoSize-1.
parameter FifoIndexSize = (FifoSize <= 2) ? 1 : (FifoSize <= 4) ? 2 :
  (FifoSize <= 8) ? 3 : (FifoSize <= 16) ? 4 : (FifoSize <= 32) ? 5 :
  (FifoSize <= 64) ? 6 : (FifoSize <= 128) ? 7 : (FifoSize <= 256) ? 8 :
  (FifoSize <= 512) ? 9 : (FifoSize <= 1024) ? 10 : (FifoSize <= 2048) ? 11 :
  (FifoSize <= 4096) ? 12 : (FifoSize <= 8192) ? 13 : (FifoSize <= 16384) ? 14 :
  (FifoSize <= 32768) ? 15 : (FifoSize <= 65536) ? 16 : -1;

// Specifies the maximum frame counter size, which should be capable of holding
// the binary representation of MaxFrameCount.
parameter MaxFrameCountSize = (MaxFrameCount < 2) ? 1 : (MaxFrameCount < 4) ? 2 :
  (MaxFrameCount < 8) ? 3 : (MaxFrameCount < 16) ? 4 : (MaxFrameCount < 32) ? 5 :
  (MaxFrameCount < 64) ? 6 : -1;

// Specifies the 'upstream' data input ports.
input                   dataInValid;
input [7:0]             dataInEofc;
input [FlitWidth*8-1:0] dataIn;
output                  dataInStop;

// Specifies the 'downstream' data output ports.
output                   dataOutValid;
output [7:0]             dataOutEofc;
output [FlitWidth*8-1:0] dataOut;
input                    dataOutStop;

// Specify system level signals.
input clk;
input srst;

// Specify the data input registers.
reg                   dataInValid_q;
reg                   dataInEof_q;
reg [7:0]             dataInEofc_q;
reg [FlitWidth*8-1:0] dataIn_q;
wire                  dataInHalt;

// Specify the data output registers.
reg                   dataOutValid_q;
reg                   dataOutEof_q;
reg [7:0]             dataOutEofc_q;
reg [FlitWidth*8-1:0] dataOut_q;

// Specify the frame counter and output gating signals.
reg [MaxFrameCountSize-1:0] frameCount_d;

reg [MaxFrameCountSize-1:0] frameCount_q;
reg                         frameReady_q;
reg                         inputHalt_q;
wire                        outputBlocked;

// Specified the FIFO buffered output signals.
wire                   fifoInValid;
wire                   fifoInStop;
wire                   fifoOutValid;
wire [7:0]             fifoOutEofc;
wire [FlitWidth*8-1:0] fifoOutData;
wire                   fifoOutStop;

// Miscellaneous signals.
integer i;

// Implement resettable input control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    dataInValid_q <= 1'b0;
    dataInEof_q <= 1'b0;
  end
  else if (~(dataInValid_q & dataInHalt))
  begin
    dataInValid_q <= dataInValid;
    dataInEof_q <= (dataInEofc == 8'd0) ? 1'b0 : 1'b1;
  end
end

// Implement non-resettable input datapath registers.
always @(posedge clk)
begin
  if (~(dataInValid_q & dataInHalt))
  begin
    dataInEofc_q <= dataInEofc;
    dataIn_q <= dataIn;
  end
end

assign dataInStop = dataInValid_q & dataInHalt;

// Implement combinatorial logic for frame counter.
always @(frameCount_q, frameReady_q, fifoInValid, fifoInStop, dataInEof_q,
  dataOutValid_q, fifoOutStop, dataOutEof_q)
begin

  // Hold current state by default.
  frameCount_d = frameCount_q;

  // Process end of input frame.
  if (fifoInValid & ~fifoInStop)
  begin
    if (dataInEof_q)
      frameCount_d = frameCount_d + 1;
  end

  // Process end of output frame.
  if (dataOutValid_q & ~fifoOutStop)
  begin
    if (dataOutEof_q)
      frameCount_d = frameCount_d - 1;
  end
end

// Implement sequential logic for frame counter.
always @(posedge clk)
begin
  if (srst)
  begin
    for (i = 0; i < MaxFrameCountSize; i = i + 1)
      frameCount_q [i] <= 1'b0;
    frameReady_q <= 1'b0;
    inputHalt_q <= 1'b1;
  end
  else
  begin
    frameCount_q <= frameCount_d;
    frameReady_q <= (frameCount_d == 0) ? 1'b0 : 1'b1;
    inputHalt_q <= (frameCount_d == MaxFrameCount [MaxFrameCountSize-1:0]) ? 1'b1 : 1'b0;
  end
end

// Instantiate the buffer FIFO.
generate
  if (FifoSize < 128)
    smiSelfLinkBufferFifoS #(FlitWidth*8+8, FifoSize+1, FifoIndexSize) flitFifoS
      (fifoInValid, { dataInEofc_q, dataIn_q }, fifoInStop, fifoOutValid,
      { fifoOutEofc, fifoOutData }, fifoOutStop, clk, srst);
  else
    smiSelfLinkBufferFifoL #(FlitWidth*8+8, FifoSize, FifoIndexSize) flitFifoL
      (fifoInValid, { dataInEofc_q, dataIn_q }, fifoInStop, fifoOutValid,
      { fifoOutEofc, fifoOutData }, fifoOutStop, clk, srst);
endgenerate

// Implement resettable output control registers.
always @(posedge clk)
begin
  if (srst)
  begin
    dataOutValid_q <= 1'b0;
    dataOutEof_q <= 1'b0;
  end
  else if (~fifoOutStop)
  begin
    dataOutValid_q <= fifoOutValid;
    dataOutEof_q <= (fifoOutEofc == 8'd0) ? 1'b0 : 1'b1;
  end
end

// Implement non-resettable output data registers.
always @(posedge clk)
begin
  if (~fifoOutStop)
  begin
    dataOutEofc_q <= fifoOutEofc;
    dataOut_q <= fifoOutData;
  end
end

assign outputBlocked = ~(frameReady_q | fifoInStop);
assign fifoInValid = dataInValid_q & ~inputHalt_q;
assign dataInHalt = fifoInStop | inputHalt_q;
assign dataOutValid = dataOutValid_q & ~outputBlocked;
assign dataOutEofc = dataOutEofc_q;
assign dataOut = dataOut_q;
assign fifoOutStop = dataOutValid_q & (dataOutStop | outputBlocked);

endmodule
