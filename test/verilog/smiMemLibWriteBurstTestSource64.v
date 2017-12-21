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
// Memory access library write burst test source. This component generates write
// bursts to a specified address and of a specified length using generated
// counting sequence data.
//

`timescale 1ns/1ps

module smiMemLibWriteBurstTestSource64
  (testParamsValid, testParamBurstAddr, testParamBurstLen, testParamBurstOpts,
  testParamDataInit, testParamDataIncr, testParamsStop, testDoneValid,
  testDoneStatusOk, testDoneStop, writeParamsValid, writeParamBurstAddr,
  writeParamBurstLen, writeParamBurstOpts, writeParamsStop, writeDataValid,
  writeDataValue, writeDataStop, writeDoneValid, writeDoneStatusOk,
  writeDoneStop, clk, srst);

// Specify test parameter inputs, used to initiate a data write test.
input        testParamsValid;
input [63:0] testParamBurstAddr;
input [31:0] testParamBurstLen;
input [7:0]  testParamBurstOpts;
input [63:0] testParamDataInit;
input [63:0] testParamDataIncr;
output       testParamsStop;

// Specify test done status signals.
output testDoneValid;
output testDoneStatusOk;
input  testDoneStop;

// Specify the write burst controller parameters.
output        writeParamsValid;
output [63:0] writeParamBurstAddr;
output [31:0] writeParamBurstLen;
output [7:0]  writeParamBurstOpts;
input         writeParamsStop;

// Specify the write data output signals.
output        writeDataValid;
output [63:0] writeDataValue;
input         writeDataStop;

// Specify the write done status signals.
input  writeDoneValid;
input  writeDoneStatusOk;
output writeDoneStop;

// System level signals.
input clk;
input srst;

// Define the state space for the test state machine.
parameter [1:0]
  TestIdle = 0,
  TestSetParams = 1,
  TestWriteData = 2,
  TestGetStatus = 3;

// Specify test state machine signals.
reg [1:0]  testState_d;
reg [63:0] burstAddr_d;
reg [31:0] burstLen_d;
reg [7:0]  burstOpts_d;
reg [63:0] dataCounterVal_d;
reg [63:0] dataCounterIncr_d;
reg [31:0] writeDataCounter_d;

reg [1:0]  testState_q;
reg [63:0] burstAddr_q;
reg [31:0] burstLen_q;
reg [7:0]  burstOpts_q;
reg [63:0] dataCounterVal_q;
reg [63:0] dataCounterIncr_q;
reg [31:0] writeDataCounter_q;

reg testParamsHalt;
reg writeParamsReady;
reg writeDataReady;
reg testDoneReady;
reg writeDoneHalt;

// Implement combinatorial logic for write burst test state machine.
always @(testState_q, burstAddr_q, burstLen_q, burstOpts_q, dataCounterVal_q,
  dataCounterIncr_q, writeDataCounter_q, testParamsValid, testParamBurstAddr,
  testParamBurstLen, testParamBurstOpts, testParamDataInit, testParamDataIncr,
  writeParamsStop, writeDataStop, writeDoneValid, testDoneStop)
begin

  // Hold current state by default.
  testState_d = testState_q;
  burstAddr_d = burstAddr_q;
  burstLen_d = burstLen_q;
  burstOpts_d = burstOpts_q;
  dataCounterVal_d = dataCounterVal_q;
  dataCounterIncr_d = dataCounterIncr_q;
  writeDataCounter_d = writeDataCounter_q;

  testParamsHalt = 1'b1;
  writeParamsReady = 1'b0;
  writeDataReady = 1'b0;
  testDoneReady = 1'b0;
  writeDoneHalt = 1'b1;

  // Implement state machine.
  case (testState_q)

    // Set the memory transfer parameters.
    TestSetParams :
    begin
      writeParamsReady = 1'b1;
      if (~writeParamsStop)
        testState_d = TestWriteData;
    end

    // Copy counting sequence to write data port.
    TestWriteData :
    begin
      writeDataReady = 1'b1;
      if (~writeDataStop)
      begin
        dataCounterVal_d = dataCounterVal_q + dataCounterIncr_q;
        writeDataCounter_d = writeDataCounter_q - 32'd1;
        if (writeDataCounter_q == 32'd1)
          testState_d = TestGetStatus;
      end
    end

    // Forward the status signals.
    TestGetStatus :
    begin
      testDoneReady = writeDoneValid;
      writeDoneHalt = testDoneStop;
      if (writeDoneValid & ~testDoneStop)
        testState_d = TestIdle;
    end

    // From the default idle state, wait for a new set of test parameters.
    default :
    begin
      testParamsHalt = 1'b0;
      burstAddr_d = testParamBurstAddr;
      burstLen_d = testParamBurstLen;
      burstOpts_d = testParamBurstOpts;
      dataCounterVal_d = testParamDataInit;
      dataCounterIncr_d = testParamDataIncr;
      writeDataCounter_d = testParamBurstLen;
      if (testParamsValid)
        testState_d = TestSetParams;
    end
  endcase

end

// Implement resettable state registers.
always @(posedge clk)
begin
  if (srst)
    testState_q <= TestIdle;
  else
    testState_q <= testState_d;
end

// Implement non-resettable datapath registers.
always @(posedge clk)
begin
  burstAddr_q <= burstAddr_d;
  burstLen_q <= burstLen_d;
  burstOpts_q <= burstOpts_d;
  dataCounterVal_q <= dataCounterVal_d;
  dataCounterIncr_q <= dataCounterIncr_d;
  writeDataCounter_q <= writeDataCounter_d;
end

assign testParamsStop = testParamsHalt;
assign writeParamsValid = writeParamsReady;
assign writeParamBurstAddr = burstAddr_q;
assign writeParamBurstLen = burstLen_q;
assign writeParamBurstOpts = burstOpts_q;
assign writeDataValid = writeDataReady;
assign writeDataValue = dataCounterVal_q;
assign testDoneValid = testDoneReady;
assign testDoneStatusOk = writeDoneStatusOk;
assign writeDoneStop = writeDoneHalt;

endmodule
