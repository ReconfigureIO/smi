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
// limitations under the License.
//

//
// Memory access library 64 bit wide burst fuzz tester. This component initiates
// 64-bit wide write bursts followed by corresponding read check bursts which
// use common randomised base addresses and lengths. The bursts fall within a
// given address window (configAddrBase to configAddrTop-1 inclusive) and the
// write/read cycle is repeated a configurable number of times.
//

`timescale 1ns/1ps

module smiMemLibFuzzTestBurst64
  (configValid, configMemAddrBase, configMemBlockSize, configNumTests,
  configStop, statusValid, statusErrorCount, statusDataCount, statusStop,
  smiReqValid, smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc,
  smiRespData, smiRespStop, clk, srst);

// Specifies the minimum supported burst length (in bytes).
parameter MinBurstLength = 8;

// Specifies the maximum supported burst length (in bytes).
parameter MaxBurstLength = (1024 * 1024 * 1024);

// Specifies the internal FIFO depths (between 3 and 128 entries).
parameter FifoSize = 16;

// Specifies the pseudo-random number generator seed.
parameter RandSeed = 64'h373E7B7D27C69FA4;

// Specify the burst segment size as an integer power of two number of 64-bit
// words.
parameter BurstSegmentSize = 32;

// Specifies the configuration input signals.
input        configValid;
input [63:0] configMemAddrBase;
input [31:0] configMemBlockSize;
input [31:0] configNumTests;
output       configStop;

// Specifies the test status output signals.
output        statusValid;
output [31:0] statusErrorCount;
output [63:0] statusDataCount;
input         statusStop;

// Specifies the SMI request and response channel signals.
output        smiReqValid;
output [7:0]  smiReqEofc;
output [63:0] smiReqData;
input         smiReqStop;

input        smiRespValid;
input [7:0]  smiRespEofc;
input [63:0] smiRespData;
output       smiRespStop;

// Specifies the system level signals.
input clk;
input srst;

// Specify state space for test state machine.
parameter [2:0]
  TestStateReset = 0,
  TestStateIdle = 1,
  TestStateBurstCount = 2,
  TestStateStartWrite = 3,
  TestStateCheckWrite = 4,
  TestStateStartRead = 5,
  TestStateCheckRead = 6,
  TestStateReportResult = 7;

// Specify the forked configuration handshake signals.
wire configParamsValid;
wire configParamsStop;
wire configTestValid;
wire configTestStop;

// Specify the burst parameter signals.
wire        testParamsValid;
wire [63:0] testParamBurstAddr;
wire [31:0] testParamByteLength;
wire [63:0] testParamDataInit;
wire [63:0] testParamDataIncr;
reg         testParamsStop;
wire [31:0] testParamBurstLen;
wire [7:0]  testParamBurstOpts;

// Specify the test state machine signals.
reg [2:0]  testState_d;
reg [31:0] testCount_d;
reg [31:0] errorCount_d;
reg [63:0] dataCount_d;

reg [2:0]  testState_q;
reg [31:0] testCount_q;
reg [31:0] errorCount_q;
reg [63:0] dataCount_q;

// Specify the burst stimulus control signals.
reg  writeTestParamsValid;
wire writeTestParamsStop;
wire writeTestDoneValid;
wire writeTestDoneStatusOk;
reg  writeTestDoneStop;

reg  readTestParamsValid;
wire readTestParamsStop;
wire readTestDoneValid;
wire readTestDoneStatusOk;
reg  readTestDoneStop;

// Specify the write stimulus to burst write controller connections.
wire        writeParamsValid;
wire [63:0] writeParamBurstAddr;
wire [31:0] writeParamBurstLen;
wire [7:0]  writeParamBurstOpts;
wire        writeParamsStop;
wire        writeDataValid;
wire [63:0] writeDataValue;
wire        writeDataStop;
wire        writeDoneValid;
wire        writeDoneStatusOk;
wire        writeDoneStop;

// Specify the read checker to burst read controller connections.
wire        readParamsValid;
wire [63:0] readParamBurstAddr;
wire [31:0] readParamBurstLen;
wire [7:0]  readParamBurstOpts;
wire        readParamsStop;
wire        readDataValid;
wire [63:0] readDataValue;
wire        readDataStop;
wire        readDoneValid;
wire        readDoneStatusOk;
wire        readDoneStop;

// Specify the internal SMI connection signals.
wire        smiWriteReqValid;
wire [7:0]  smiWriteReqEofc;
wire [63:0] smiWriteReqData;
wire        smiWriteReqStop;
wire        smiWriteRespValid;
wire [7:0]  smiWriteRespEofc;
wire [63:0] smiWriteRespData;
wire        smiWriteRespStop;

wire        smiReadReqValid;
wire [7:0]  smiReadReqEofc;
wire [63:0] smiReadReqData;
wire        smiReadReqStop;
wire        smiReadRespValid;
wire [7:0]  smiReadRespEofc;
wire [63:0] smiReadRespData;
wire        smiReadRespStop;

// Status output buffer handshake signals.
reg  statusBufValid;
wire statusBufStop;

// Fork the configuration request to the parameter generation logic and
// test state machine.
smiSelfFlowForkControl #(2) configFork
  (configValid, configStop, { configParamsValid, configTestValid },
  { configParamsStop, configTestStop }, clk, srst);

assign configTestStop = (testState_q == TestStateIdle) ? 1'b0 : 1'b1;

// Instantiate the test parameter generation logic.
smiMemLibFuzzTestParamGen #(MinBurstLength, MaxBurstLength, RandSeed) paramGen
  (configParamsValid, configMemAddrBase, configMemBlockSize, configNumTests,
  configParamsStop, testParamsValid, testParamBurstAddr, testParamByteLength,
  testParamDataInit, testParamDataIncr, testParamsStop, clk, srst);

assign testParamBurstLen = { 3'd0, testParamByteLength [31:3] };
assign testParamBurstOpts = 8'd0;

// Implement combinatorial logic for driving test process state machine.
always @(testState_q, testCount_q, errorCount_q, dataCount_q, configTestValid,
  configNumTests, testParamsValid, testParamByteLength, writeTestParamsStop,
  writeTestDoneValid, writeTestDoneStatusOk, readTestParamsStop, readTestDoneValid,
  readTestDoneStatusOk, statusBufStop)
begin

  // Hold current state by default.
  testState_d = testState_q;
  testCount_d = testCount_q;
  errorCount_d = errorCount_q;
  dataCount_d = dataCount_q;
  testParamsStop = 1'b1;
  writeTestParamsValid = 1'b0;
  writeTestDoneStop = 1'b1;
  readTestParamsValid = 1'b0;
  readTestDoneStop = 1'b1;
  statusBufValid = 1'b0;

  // Implement state machine.
  case (testState_q)

    // In the idle state, wait for new test configuration input.
    TestStateIdle :
    begin
      testCount_d = configNumTests;
      errorCount_d = 32'd0;
      dataCount_d = 64'd0;
      if (configTestValid)
        testState_d = TestStateBurstCount;
    end

    // Implement individual test counter.
    TestStateBurstCount :
    begin
      if (testCount_q == 32'd0)
      begin
        testState_d = TestStateReportResult;
      end
      else if (testParamsValid)
      begin
        testState_d = TestStateStartWrite;
        testCount_d = testCount_q - 32'd1;
        dataCount_d = dataCount_q + { 32'd0, testParamByteLength [31:3], 3'd0 };
      end
    end

    // Initiate write once the new test parameters to be available.
    TestStateStartWrite :
    begin
      writeTestParamsValid = 1'b1;
      if (~writeTestParamsStop)
        testState_d = TestStateCheckWrite;
    end

    // Check write completion status.
    TestStateCheckWrite :
    begin
      writeTestDoneStop = 1'b0;
      if (writeTestDoneValid)
      begin
        if (writeTestDoneStatusOk)
        begin
          testState_d = TestStateStartRead;
        end
        else
        begin
          testState_d = TestStateBurstCount;
          errorCount_d = errorCount_q + 32'b1;
        end
      end
    end

    // Initiate read once successful write has occurred.
    TestStateStartRead :
    begin
      readTestParamsValid = 1'b1;
      if (~readTestParamsStop)
        testState_d = TestStateCheckRead;
    end

    // Check read completion status.
    TestStateCheckRead :
    begin
      readTestDoneStop = 1'b0;
      if (readTestDoneValid)
      begin
        testState_d = TestStateBurstCount;
        testParamsStop = 1'b0;
        if (~readTestDoneStatusOk)
          errorCount_d = errorCount_q + 32'b1;
      end
    end

    // On completion of all tests, report result.
    TestStateReportResult :
    begin
      statusBufValid = 1'b1;
      if (~statusBufStop)
        testState_d = TestStateIdle;
    end

    // From the reset state, transition to idle.
    default :
    begin
      testState_d = TestStateIdle;
    end
  endcase

end

// Implement resettable registers for state machine.
always @(posedge clk)
begin
  if (srst)
    testState_q <= TestStateReset;
  else
    testState_q <= testState_d;
end

// Implement non-resettable datapath registers for state machine.
always @(posedge clk)
begin
  testCount_q <= testCount_d;
  errorCount_q <= errorCount_d;
  dataCount_q <= dataCount_d;
end

// Instantiate burst write stimulus generator.
smiMemLibWriteBurstTestSource64 writeTestDataSource
  (writeTestParamsValid, testParamBurstAddr, testParamBurstLen, testParamBurstOpts,
  testParamDataInit, testParamDataIncr, writeTestParamsStop, writeTestDoneValid,
  writeTestDoneStatusOk, writeTestDoneStop, writeParamsValid, writeParamBurstAddr,
  writeParamBurstLen, writeParamBurstOpts, writeParamsStop, writeDataValid,
  writeDataValue, writeDataStop, writeDoneValid, writeDoneStatusOk, writeDoneStop,
  clk, srst);

// Instantiate the burst write controller.
smiMemLibWriteBurstSegmented64 #(BurstSegmentSize) writeBurstController
  (writeParamsValid, writeParamBurstAddr, writeParamBurstLen, writeParamBurstOpts,
  writeParamsStop, writeDataValid, writeDataValue, writeDataStop, writeDoneValid,
  writeDoneStatusOk, writeDoneStop, smiWriteReqValid, smiWriteReqEofc,
  smiWriteReqData, smiWriteReqStop, smiWriteRespValid, smiWriteRespEofc,
  smiWriteRespData, smiWriteRespStop, clk, srst);

// Instantiate burst read data checker.
smiMemLibReadBurstTestCheck64 readTestDataChecker
  (readTestParamsValid, testParamBurstAddr, testParamBurstLen, testParamBurstOpts,
  testParamDataInit, testParamDataIncr, readTestParamsStop, readTestDoneValid,
  readTestDoneStatusOk, readTestDoneStop, readParamsValid, readParamBurstAddr,
  readParamBurstLen, readParamBurstOpts, readParamsStop, readDataValid,
  readDataValue, readDataStop, readDoneValid, readDoneStatusOk, readDoneStop,
  clk, srst);

// Instantiate the burst read controller.
smiMemLibReadBurstSegmented64 #(BurstSegmentSize) readBurstController
  (readParamsValid, readParamBurstAddr, readParamBurstLen, readParamBurstOpts,
  readParamsStop, readDataValid, readDataValue, readDataStop, readDoneValid,
  readDoneStatusOk, readDoneStop, smiReadReqValid, smiReadReqEofc, smiReadReqData,
  smiReadReqStop, smiReadRespValid, smiReadRespEofc, smiReadRespData,
  smiReadRespStop, clk, srst);

// Implement SMI transaction arbitration between read and write controllers.
smiTransactionArbiterX2 #(8, 2, 3*BurstSegmentSize, 3) transactionArbiter
  (smiWriteReqValid, smiWriteReqEofc, smiWriteReqData, smiWriteReqStop,
  smiWriteRespValid, smiWriteRespEofc, smiWriteRespData, smiWriteRespStop,
  smiReadReqValid, smiReadReqEofc, smiReadReqData, smiReadReqStop,
  smiReadRespValid, smiReadRespEofc, smiReadRespData, smiReadRespStop,
  smiReqValid, smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc,
  smiRespData, smiRespStop, clk, srst);

// Implement toggle buffer on status output.
smiSelfLinkToggleBuffer #(96) statusBuffer
  (statusBufValid, { errorCount_q, dataCount_q }, statusBufStop, statusValid,
  { statusErrorCount, statusDataCount }, statusStop, clk, srst);

endmodule
