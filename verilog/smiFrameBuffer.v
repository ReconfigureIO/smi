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
// The SMI frame buffer is a wrapper for the SELF FIFO components which
// instantiates the SRL based 'small' SELF FIFO component for FIFOs of less
// than 128 flits in length and the circular buffer variant for larger FIFOs.
//

`timescale 1ns/1ps

module smiFrameBuffer
  (dataInValid, dataInEofc, dataIn, dataInStop, dataOutValid, dataOutEofc,
  dataOut, dataOutStop, clk, srst);

// Specifes the flit width of the data channel, expressed as an integer power
// of two number of bytes.
parameter FlitWidth = 8;

// Specifies the link buffer FIFO size (maximum 1024).
parameter FifoSize = 64;

// Specifies the link buffer FIFO index size, which should be capable of holding
// the binary representation of FifoSize-1.
parameter FifoIndexSize = (FifoSize <= 2) ? 1 : (FifoSize <= 4) ? 2 :
  (FifoSize <= 8) ? 3 : (FifoSize <= 16) ? 4 : (FifoSize <= 32) ? 5 :
  (FifoSize <= 64) ? 6 : (FifoSize <= 128) ? 7 : (FifoSize <= 256) ? 8 :
  (FifoSize <= 512) ? 9 : (FifoSize <= 1024) ? 10 : (FifoSize <= 2048) ? 11 :
  (FifoSize <= 4096) ? 12 : (FifoSize <= 8192) ? 13 : (FifoSize <= 16384) ? 14 :
  (FifoSize <= 32768) ? 15 : (FifoSize <= 65536) ? 16 : -1;

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

// Instantiate the buffer FIFO.
generate
  if (FifoSize < 128)
    smiSelfLinkBufferFifoS #(FlitWidth*8+8, FifoSize+1, FifoIndexSize) flitFifoS
      (dataInValid, { dataInEofc, dataIn }, dataInStop, dataOutValid,
      { dataOutEofc, dataOut }, dataOutStop, clk, srst);
  else
    smiSelfLinkBufferFifoL #(FlitWidth*8+8, FifoSize, FifoIndexSize) flitFifoL
      (dataInValid, { dataInEofc, dataIn }, dataInStop, dataOutValid,
      { dataOutEofc, dataOut }, dataOutStop, clk, srst);
endgenerate

endmodule
