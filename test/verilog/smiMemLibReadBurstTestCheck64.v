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
// Memory access library read burst test checker. This component initiates read
// bursts from a specified address and of a specified length and checks the
// memory contents against generated counting sequence data.
//

`timescale 1ns/1ps

module smiMemLibReadBurstTestCheck64
  (testParamsValid, testParamBurstAddr, testParamBurstLen, testParamBurstOpts,
  testParamDataInit, testParamDataIncr, testParamsStop, testDoneValid,
  testDoneStatusOk, testDoneStop, readParamsValid, readParamBurstAddr,
  readParamBurstLen, readParamBurstOpts, readParamsStop, readDataValid,
  readDataValue, readDataStop, readDoneValid, readDoneStatusOk,
  readDoneStop, clk, srst);

// Specify test parameter inputs, used to initiate a data read test.
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

// Specify the read burst controller parameters.
output        readParamsValid;
output [63:0] readParamBurstAddr;
output [31:0] readParamBurstLen;
output [7:0]  readParamBurstOpts;
input         readParamsStop;

// Specify the read data input signals.
input        readDataValid;
input [63:0] readDataValue;
output       readDataStop;

// Specify the read done status signals.
input  readDoneValid;
input  readDoneStatusOk;
output readDoneStop;

// System level signals.
input clk;
input srst;

// Define the state space for the test state machine.
parameter [1:0]
  TestIdle = 0,
  TestSetParams = 1,
  TestCheckData = 2,
  TestGetStatus = 3;

// Specify test state machine signals.
reg [1:0]  testState_d;
reg        testPassed_d;
reg [63:0] burstAddr_d;
reg [31:0] burstLen_d;
reg [7:0]  burstOpts_d;
reg [63:0] dataCounterVal_d;
reg [63:0] dataCounterIncr_d;
reg [31:0] readDataCounter_d;

reg [1:0]  testState_q;
reg        testPassed_q;
reg [63:0] burstAddr_q;
reg [31:0] burstLen_q;
reg [7:0]  burstOpts_q;
reg [63:0] dataCounterVal_q;
reg [63:0] dataCounterIncr_q;
reg [31:0] readDataCounter_q;

reg testParamsHalt;
reg readParamsReady;
reg readDataHalt;

// Implement combinatorial logic for read burst test state machine.
always @(testState_q, testPassed_q, burstAddr_q, burstLen_q, burstOpts_q,
  dataCounterVal_q, dataCounterIncr_q, readDataCounter_q, testParamsValid,
  testParamBurstAddr, testParamBurstLen, testParamBurstOpts, testParamDataInit,
  testParamDataIncr, readParamsStop, readDataValid, readDataValue, readDoneValid,
  testDoneStop)
begin

  // Hold current state by default.
  testState_d = testState_q;
  testPassed_d = testPassed_q;
  burstAddr_d = burstAddr_q;
  burstLen_d = burstLen_q;
  burstOpts_d = burstOpts_q;
  dataCounterVal_d = dataCounterVal_q;
  dataCounterIncr_d = dataCounterIncr_q;
  readDataCounter_d = readDataCounter_q;

  testParamsHalt = 1'b1;
  readParamsReady = 1'b0;
  readDataHalt = 1'b1;

  // Implement state machine.
  case (testState_q)

    // Set the memory transfer parameters.
    TestSetParams :
    begin
      readParamsReady = 1'b1;
      if (~readParamsStop)
        testState_d = TestCheckData;
    end

    // Check counting sequence on read data port.
    TestCheckData :
    begin
      readDataHalt = 1'b0;
      if (readDataValid)
      begin
        dataCounterVal_d = dataCounterVal_q + dataCounterIncr_q;
        readDataCounter_d = readDataCounter_q - 32'd1;
        if (readDataCounter_q == 32'd1)
          testState_d = TestGetStatus;
        if (dataCounterVal_q != readDataValue)
          testPassed_d = 1'b0;
      end
    end

    // Forward the status signals.
    TestGetStatus :
    begin
      if (readDoneValid & ~testDoneStop)
        testState_d = TestIdle;
    end

    // From the default idle state, wait for a new set of test parameters.
    default :
    begin
      testParamsHalt = 1'b0;
      testPassed_d = 1'b1;
      burstAddr_d = testParamBurstAddr;
      burstLen_d = testParamBurstLen;
      burstOpts_d = testParamBurstOpts;
      dataCounterVal_d = testParamDataInit;
      dataCounterIncr_d = testParamDataIncr;
      readDataCounter_d = testParamBurstLen;
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
  testPassed_q <= testPassed_d;
  burstAddr_q <= burstAddr_d;
  burstLen_q <= burstLen_d;
  burstOpts_q <= burstOpts_d;
  dataCounterVal_q <= dataCounterVal_d;
  dataCounterIncr_q <= dataCounterIncr_d;
  readDataCounter_q <= readDataCounter_d;
end

assign testParamsStop = testParamsHalt;
assign readParamsValid = readParamsReady;
assign readParamBurstAddr = burstAddr_q;
assign readParamBurstLen = burstLen_q;
assign readParamBurstOpts = burstOpts_q;
assign readDataStop = readDataHalt;
assign testDoneValid = (testState_q == TestGetStatus) ? readDoneValid : 1'b0;
assign testDoneStatusOk = readDoneStatusOk & testPassed_q;
assign readDoneStop = (testState_q == TestGetStatus) ? testDoneStop : 1'b1;

endmodule
