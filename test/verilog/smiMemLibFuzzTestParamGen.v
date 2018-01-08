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
// Memory access library fuzz test parameter generator. This component uses a
// PRNG to select SMI burst addresses and lengths, where the bursts fall within
// a given address window (starting at configMemAddrBase and of length
// configMemBlockSize). These address range values are assumed to have been
// sanitised in advance. It also generates pseudo-random data count base and
// increment values for use by the write data generation and read data checker
// components.
//

`timescale 1ns/1ps

module smiMemLibFuzzTestParamGen
  (configValid, configMemAddrBase, configMemBlockSize, configNumTests,
  configStop, paramsValid, paramBaseAddr, paramByteLength, paramDataInit,
  paramDataIncr, paramsStop, clk, srst);

// Specifies the minimum supported burst length (in bytes).
parameter MinBurstLength = 64;

// Specifies the maximum supported burst length (in bytes).
parameter MaxBurstLength = 8192;

// Specifies the pseudo-random number generator seed.
parameter RandSeed = 64'h373E7B7D27C69FA4;

// Specifies the fuzz test configuration input signals.
input        configValid;
input [63:0] configMemAddrBase;
input [31:0] configMemBlockSize;
input [31:0] configNumTests;
output       configStop;

// Specifies the fuzz test parameter output signals.
output        paramsValid;
output [63:0] paramBaseAddr;
output [31:0] paramByteLength;
output [63:0] paramDataInit;
output [63:0] paramDataIncr;
input         paramsStop;

// Specifies system level signals.
input clk;
input srst;

// Define the state space for the configuration setup state machine.
parameter [1:0]
  ConfigSetupReset = 0,
  ConfigSetupIdle = 1,
  ConfigSetupWindowMask = 2,
  ConfigSetupWait = 3;

// Define the state space for the parameter generation state machine.
parameter [3:0]
  ParamGenIdle = 0,
  ParamGenTestCount = 1,
  ParamGenSetByteOffset = 2,
  ParamGenCheckByteOffset = 3,
  ParamGenSetByteLength = 4,
  ParamGenCheckByteLength1 = 5,
  ParamGenCheckByteLength2 = 6,
  ParamGenSetDataInit = 7,
  ParamGenSetDataIncr = 8,
  ParamGenWait = 9;

// Specify the PRNG source signals.
wire        randReady;
wire [63:0] randData;
reg         randStop;

// Specify the configuration setup state machine signals.
reg [1:0]  configSetupState_d;
reg        configSetupDone_d;
reg [63:0] configMemAddrBase_d;
reg [31:0] configMemBlockSize_d;
reg [31:0] configNumTests_d;
reg [31:0] configWindowMask_d;

reg [1:0]  configSetupState_q;
reg        configSetupDone_q;
reg [63:0] configMemAddrBase_q;
reg [31:0] configMemBlockSize_q;
reg [31:0] configNumTests_q;
reg [31:0] configWindowMask_q;

// Specify the parameter generation state machine signals.
reg [3:0]  paramGenState_d;
reg        paramGenDone_d;
reg [31:0] testCount_d;
reg [31:0] burstByteOffset_d;
reg [31:0] burstByteLength_d;
reg [63:0] paramBaseAddr_d;
reg [31:0] paramByteLength_d;
reg [63:0] paramDataInit_d;
reg [63:0] paramDataIncr_d;

reg [3:0]  paramGenState_q;
reg        paramGenDone_q;
reg [31:0] testCount_q;
reg [31:0] burstByteOffset_q;
reg [31:0] burstByteLength_q;
reg [63:0] paramBaseAddr_q;
reg [31:0] paramByteLength_q;
reg [63:0] paramDataInit_q;
reg [63:0] paramDataIncr_q;

// Specify the parameter output buffer handshake signals.
reg  paramsBufReady;
wire paramsBufStop;

// Instantiate the PRNG module.
smiSelfRandSource #(64, RandSeed) randSource
  (randReady, randData, randStop, clk, srst);

// Implement combinatorial logic for configuration setup state machine.
always @(configSetupState_q, configMemAddrBase_q, configMemBlockSize_q,
  configNumTests_q, configWindowMask_q, configValid, configMemAddrBase,
  configMemBlockSize, configNumTests, paramGenDone_q)
begin

  // Hold current state by default.
  configSetupState_d = configSetupState_q;
  configSetupDone_d = 1'b0;
  configMemAddrBase_d = configMemAddrBase_q;
  configMemBlockSize_d = configMemBlockSize_q;
  configNumTests_d = configNumTests_q;
  configWindowMask_d = configWindowMask_q;

  // Implement state machine.
  case (configSetupState_q)

    // From the idle state, wait for new configuration parameters.
    ConfigSetupIdle :
    begin
      if (configValid)
        configSetupState_d = ConfigSetupWindowMask;
      configMemAddrBase_d = configMemAddrBase;
      configMemBlockSize_d = configMemBlockSize;
      configNumTests_d = configNumTests;
      configWindowMask_d = 32'd1;
    end

    // Generate address window mask to use.
    ConfigSetupWindowMask :
    begin
      if (configWindowMask_q >= configMemBlockSize_q)
      begin
        configSetupState_d = ConfigSetupWait;
        configSetupDone_d = 1'b1;
      end
      else
      begin
        configWindowMask_d = { configWindowMask_q [30:0], 1'b1 };
      end
    end

    // After configuration setup, wait for the parameter generation state
    // machine to run to completion.
    ConfigSetupWait :
    begin
      if (paramGenDone_q)
        configSetupState_d = ConfigSetupIdle;
    end

    // From the reset state, transition directly to the idle state.
    default :
    begin
      configSetupState_d = ConfigSetupIdle;
    end
  endcase

end

assign configStop = (configSetupState_q == ConfigSetupIdle) ? 1'b0 : 1'b1;

// Implement resettable state registers for configuration setup.
always @(posedge clk)
begin
  if (srst)
  begin
    configSetupState_q <= ConfigSetupReset;
    configSetupDone_q <= 1'b0;
  end
  else
  begin
    configSetupState_q <= configSetupState_d;
    configSetupDone_q <= configSetupDone_d;
  end
end

// Implement non-resettable data registers for configuration setup.
always @(posedge clk)
begin
  configMemAddrBase_q <= configMemAddrBase_d;
  configMemBlockSize_q <= configMemBlockSize_d;
  configNumTests_q <= configNumTests_d;
  configWindowMask_q <= configWindowMask_d;
end

// Implement combinatorial logic for parameter generation state machine.
always @(paramGenState_q, testCount_q, burstByteOffset_q, burstByteLength_q,
  paramBaseAddr_q, paramByteLength_q, paramDataInit_q, paramDataIncr_q,
  configSetupDone_q, configMemAddrBase_q, configMemBlockSize_q, configNumTests_q,
  configWindowMask_q, randReady, randData, paramsBufStop)
begin

  // Hold current state by default.
  paramGenState_d = paramGenState_q;
  paramGenDone_d = 1'b0;
  testCount_d = testCount_q;
  burstByteOffset_d = burstByteOffset_q;
  burstByteLength_d = burstByteLength_q;
  paramBaseAddr_d = paramBaseAddr_q;
  paramByteLength_d = paramByteLength_q;
  paramDataInit_d = paramDataInit_q;
  paramDataIncr_d = paramDataIncr_q;
  randStop = 1'b1;
  paramsBufReady = 1'b0;

  // Implement state machine.
  case (paramGenState_q)

    // Check for end of test.
    ParamGenTestCount :
    begin
      if (testCount_q == 32'd0)
      begin
        paramGenState_d = ParamGenIdle;
        paramGenDone_d = 1'b1;
      end
      else
      begin
        paramGenState_d = ParamGenSetByteOffset;
        testCount_d = testCount_q - 32'd1;
      end
    end

    // Set burst offset to a random value in the lower half of the test range.
    ParamGenSetByteOffset :
    begin
      burstByteOffset_d = randData [63:32] & { 1'b0, configWindowMask_q [31:1] };
      randStop = 1'b0;
      if (randReady)
        paramGenState_d = ParamGenCheckByteOffset;
    end

    // Check that the byte offset falls in the lower half of the test range and
    // generate a new burst offset value if not.
    ParamGenCheckByteOffset :
    begin
      paramBaseAddr_d = configMemAddrBase_q + {32'd0, burstByteOffset_q };
      if (burstByteOffset_q > { 1'b0, configMemBlockSize_q [31:1] })
        paramGenState_d = ParamGenSetByteOffset;
      else
        paramGenState_d = ParamGenSetByteLength;
    end

    // Set the transfer length to a random value in the test range.
    ParamGenSetByteLength :
    begin
      burstByteLength_d = randData [63:32] & configWindowMask_q;
      randStop = 1'b0;
      if (randReady)
        paramGenState_d = ParamGenCheckByteLength1;
    end

    // Check that the burst transfer falls within the fixed minimum and maximum
    // sizes and generate a new burst length if not.
    ParamGenCheckByteLength1 :
    begin
      paramByteLength_d = burstByteLength_q;
      if ((burstByteLength_q > MaxBurstLength [31:0]) ||
          (burstByteLength_q < MinBurstLength [31:0]))
        paramGenState_d = ParamGenSetByteLength;
      else
        paramGenState_d = ParamGenCheckByteLength2;
    end

    // Check that the burst transfer falls within the test range and generate
    // a new burst length if not.
    ParamGenCheckByteLength2 :
    begin
      paramByteLength_d = burstByteLength_q;
      if ({ 1'b0, burstByteOffset_q } + { 1'b0, burstByteLength_q } >
          { 1'b0, configMemBlockSize_q })
        paramGenState_d = ParamGenSetByteLength;
      else
        paramGenState_d = ParamGenSetDataInit;
    end

    // Set the data initialisation parameter value.
    ParamGenSetDataInit :
    begin
      paramDataInit_d = randData;
      randStop = 1'b0;
      if (randReady)
        paramGenState_d = ParamGenSetDataIncr;
    end

    // Set the data increment parameter value.
    ParamGenSetDataIncr :
    begin
      paramDataIncr_d = randData;
      randStop = 1'b0;
      if (randReady)
        paramGenState_d = ParamGenWait;
    end

    // In the wait state, attempt to push the new parameter values to the
    // output buffer.
    ParamGenWait :
    begin
      paramsBufReady = 1'b1;
      if (~paramsBufStop)
        paramGenState_d = ParamGenTestCount;
    end

    // From the idle state, wait for the new configuration to become available.
    default :
    begin
      if (configSetupDone_q)
        paramGenState_d = ParamGenTestCount;
      testCount_d = configNumTests_q;
    end
  endcase

end

// Implement resettable state registers for parameter generation.
always @(posedge clk)
begin
  if (srst)
  begin
    paramGenState_q <= ParamGenIdle;
    paramGenDone_q <= 1'b0;
  end
  else
  begin
    paramGenState_q <= paramGenState_d;
    paramGenDone_q <= paramGenDone_d;
  end
end

// Implement non-resettable data registers for parameter generation.
always @(posedge clk)
begin
  testCount_q <= testCount_d;
  burstByteOffset_q <= burstByteOffset_d;
  burstByteLength_q <= burstByteLength_d;
  paramBaseAddr_q <= paramBaseAddr_d;
  paramByteLength_q <= paramByteLength_d;
  paramDataInit_q <= paramDataInit_d;
  paramDataIncr_q <= paramDataIncr_d;
end

// Instantiate output parameter buffer.
smiSelfLinkToggleBuffer #(224) paramBuffer
  (paramsBufReady, { paramBaseAddr_q, paramByteLength_q, paramDataInit_q,
  paramDataIncr_q }, paramsBufStop, paramsValid, { paramBaseAddr,
  paramByteLength, paramDataInit, paramDataIncr }, paramsStop, clk, srst);

endmodule
