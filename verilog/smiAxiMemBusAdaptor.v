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
// Implementation of the scalable memory interface (SMI) to ARM AXI read/write
// bus adaptor.
//
// The following signals are not included on the AXI-4 interfaces. If connecting
// to a fabric or component that supports these signals, these constant values
// should be used:
//      Signal          Value
//      AxBURST[1:0]    0b01 (Incremental Bursts Only)
//      AxLOCK[1:0]     0b00
//      AxPROT[2:0]     0b000
//      AxQOS[3:0]      0b0000
//      AxREGION[3:0]   0b0000
//

`timescale 1ns/1ps

// Frame type identifiers - should probably move to a common package.
`define WRITE_REQ_ID_BYTE  32'h00000001
`define READ_REQ_ID_BYTE   32'h00000002
`define ID_BYTE_MASK       32'h000000FF

module smiAxiMemBusAdaptor
  (smiReqReady, smiReqEofc, smiReqData, smiReqStop, smiRespReady, smiRespEofc,
  smiRespData, smiRespStop, axiARValid, axiARReady, axiARId, axiARAddr,
  axiARLen, axiARSize, axiARCache, axiRValid, axiRReady, axiRId, axiRData,
  axiRResp, axiRLast, axiAWValid, axiAWReady, axiAWId, axiAWAddr, axiAWLen,
  axiAWSize, axiAWCache, axiWValid, axiWReady, axiWData, axiWStrb, axiWLast,
  axiBValid, axiBReady, axiBId, axiBResp, axiReset, clk, srst);

// Specifies the number of bits required to address individual bytes within the
// AXI data signal. This also determines the width of the data signal. Minimum
// value of 4 for a 16 byte / 128 bit AXI data bus.
parameter DataIndexSize = 4;

// Specifies the width of the AXI ID signal. This also determines the number
// of transactions which may be 'in flight' through the adaptor at any given
// time.
parameter AxiIdWidth = 4;

// Specifies the internal FIFO depths (between 3 and 128 entries).
parameter FifoSize = 16;

// Derives the flit width of the data input and output ports. Minimum 16 bytes.
parameter FlitWidth = (1 << DataIndexSize);

// Derives the maximum number of 'in flight' read transactions.
parameter MaxReadIds = (1 << AxiIdWidth);

// Specifies the clock and active high synchronous reset signals.
input clk;
input srst;
input axiReset;

// Specifies the 'upstream' combined read and write ports.
input                   smiReqReady;
input [7:0]             smiReqEofc;
input [FlitWidth*8-1:0] smiReqData;
output                  smiReqStop;

output                   smiRespReady;
output [7:0]             smiRespEofc;
output [FlitWidth*8-1:0] smiRespData;
input                    smiRespStop;

// Specifies the 'downstream' AXI read address ports.
output                  axiARValid;
input                   axiARReady;
output [AxiIdWidth-1:0] axiARId;
output [63:0]           axiARAddr;
output [7:0]            axiARLen;
output [2:0]            axiARSize;
output [3:0]            axiARCache;

// Specifies the 'downstream' AXI read data ports.
input                   axiRValid;
output                  axiRReady;
input [AxiIdWidth-1:0]  axiRId;
input [FlitWidth*8-1:0] axiRData;
input [1:0]             axiRResp;
input                   axiRLast;

// Specifies the 'downstream' AXI write address ports.
output                  axiAWValid;
input                   axiAWReady;
output [AxiIdWidth-1:0] axiAWId;
output [63:0]           axiAWAddr;
output [7:0]            axiAWLen;
output [2:0]            axiAWSize;
output [3:0]            axiAWCache;

// Specifies the 'downstream' AXI write data ports.
output                   axiWValid;
input                    axiWReady;
output [FlitWidth*8-1:0] axiWData;
output [FlitWidth-1:0]   axiWStrb;
output                   axiWLast;

// Specifies the 'downstream' AXI write response ports.
input                  axiBValid;
output                 axiBReady;
input [AxiIdWidth-1:0] axiBId;
input [1:0]            axiBResp;

// Specify the SMI read bus signals.
wire                   readReqReady;
wire [7:0]             readReqEofc;
wire [FlitWidth*8-1:0] readReqData;
wire                   readReqStop;

wire                   writeReqReady;
wire [7:0]             writeReqEofc;
wire [FlitWidth*8-1:0] writeReqData;
wire                   writeReqStop;

wire                   readRespReady;
wire [7:0]             readRespEofc;
wire [FlitWidth*8-1:0] readRespData;
wire                   readRespStop;

wire                   writeRespReady;
wire [7:0]             writeRespEofc;
wire [FlitWidth*8-1:0] writeRespData;
wire                   writeRespStop;

// Steer the read and write requests to the appropriate AXI handler.
smiFrameSteerX2 #(FlitWidth, `READ_REQ_ID_BYTE, `WRITE_REQ_ID_BYTE,
    `ID_BYTE_MASK) requestSteer
  (smiReqReady, smiReqEofc, smiReqData, smiReqStop, readReqReady, readReqEofc,
  readReqData, readReqStop, writeReqReady, writeReqEofc, writeReqData,
  writeReqStop, clk, srst);

// Arbitrate the read and write responses onto the same SMI response.
smiFrameArbiterX2 #(FlitWidth) responseArbiter
  (writeRespReady, writeRespEofc, writeRespData, writeRespStop, readRespReady,
  readRespEofc, readRespData, readRespStop, smiRespReady, smiRespEofc,
  smiRespData, smiRespStop, clk, srst);

// Instantiate the AXI read adaptor.
smiAxiMemReadAdaptor #(DataIndexSize, AxiIdWidth, FifoSize) readAdaptor
  (readReqReady, readReqEofc, readReqData, readReqStop, readRespReady,
  readRespEofc, readRespData, readRespStop, axiARValid, axiARReady, axiARId,
  axiARAddr, axiARLen, axiARSize, axiARCache, axiRValid, axiRReady, axiRId,
  axiRData, axiRResp, axiRLast, axiReset, clk, srst);

// Instantiate the AXI write adaptor.
smiAxiMemWriteAdaptor #(DataIndexSize, AxiIdWidth, FifoSize) writeAdaptor
  (writeReqReady, writeReqEofc, writeReqData, writeReqStop, writeRespReady,
  writeRespEofc, writeRespData, writeRespStop, axiAWValid, axiAWReady, axiAWId,
  axiAWAddr, axiAWLen, axiAWSize, axiAWCache, axiWValid, axiWReady, axiWData,
  axiWStrb, axiWLast, axiBValid, axiBReady, axiBId, axiBResp, axiReset, clk, srst);

endmodule
