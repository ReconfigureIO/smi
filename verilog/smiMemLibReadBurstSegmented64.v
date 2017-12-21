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
// Memory access library segmented burst read transfer component. This carries
// out a segmented read burst transfer, with data being copied to a 64-bit
// wide SELF data output. Bursts are automatically segmented so that they do not
// cross address boundaries at integer multiples of 4096.
//

`timescale 1ns/1ps

module smiMemLibReadBurstSegmented64
  (paramsValid, paramBurstAddr, paramBurstLen, paramBurstOpts, paramsStop,
  readValid, readData, readStop, doneValid, doneStatusOk, doneStop, smiReqValid,
  smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc, smiRespData,
  smiRespStop, clk, srst);

// Specify the burst segment size as an integer power of two number of 64-bit
// words.
parameter SegmentSize = 32;

// Determine the mask for the burst length register.
parameter BurstLenMask = SegmentSize - 1;

// Specify burst parameter inputs.
input        paramsValid;
input [63:0] paramBurstAddr;
input [31:0] paramBurstLen;
input [7:0]  paramBurstOpts;
output       paramsStop;

// Specify read data outputs.
output        readValid;
output [63:0] readData;
input         readStop;

// Specify transaction done outputs.
output doneValid;
output doneStatusOk;
input  doneStop;

// Specify SMI request outputs.
output        smiReqValid;
output [7:0]  smiReqEofc;
output [63:0] smiReqData;
input         smiReqStop;

// Specify SMI response inputs.
input        smiRespValid;
input [7:0]  smiRespEofc;
input [63:0] smiRespData;
output       smiRespStop;

// Clock and reset.
input clk;
input srst;

// Define the state space for the data transfer state machine.
parameter [1:0]
  ReadIdle = 0,
  ReadInitSetup = 1,
  ReadSetParams = 2,
  ReadSegmentSetup = 3;

// Define the control tokens passed from the data transfer state machine to
// the read response state machine.
parameter [1:0]
  RespCtrlReset = 0,
  RespCtrlCheck = 1,
  RespCtrlDone = 2;

// Specify the state space for the status monitoring state machine.
parameter [1:0]
  RespStatusIdle = 0,
  RespStatusWait = 1,
  RespStatusCheck = 2,
  RespStatusComplete = 3;

// Buffered parameter signals.
wire        paramBufValid;
wire [63:0] paramBufBurstAddr;
wire [31:0] paramBufBurstLen;
wire [7:0]  paramBufBurstOpts;
reg         paramBufStop;

// Core parameter handshake signals.
reg  paramsCoreValid;
wire paramsCoreStop;

// Specify the state signals for the data transfer state machine.
reg [1:0]  readState_d;
reg [60:0] burstWordAddr_d;
reg [31:0] burstLenCount_d;
reg [7:0]  burstOpts_d;
reg [12:0] initBurstLenA_d;
reg [12:0] initBurstLenB_d;
reg [12:0] nextBurstLen_d;

reg [1:0]  readState_q;
reg [60:0] burstWordAddr_q;
reg [31:0] burstLenCount_q;
reg [7:0]  burstOpts_q;
reg [12:0] initBurstLenA_q;
reg [12:0] initBurstLenB_q;
reg [12:0] nextBurstLen_q;

// Specify the response control signals.
reg       respCtrlFifoInValid;
reg [1:0] respCtrlFifoInCmd;
wire      respCtrlFifoInStop;

wire       respCtrlFifoOutValid;
wire [1:0] respCtrlFifoOutCmd;
reg        respCtrlFifoOutStop;

// Read data buffer signals.
wire        readBufValid;
wire [7:0]  readBufEofc;
wire [63:0] readBufData;
wire        readBufStop;

// Specify read status state signals.
reg [1:0] responseState_d;
reg       readStatusOk_d;

reg [1:0] responseState_q;
reg       readStatusOk_q;

// Specify the per-segment status signals.
wire segmentDoneValid;
wire segmentDoneStatusOk;
reg  segmentDoneStop;

reg  doneBufValid;
wire doneBufStop;

// Add a toggle buffer to the parameter input.
smiSelfLinkToggleBuffer #(104) inputParamBuffer
  (paramsValid, { paramBurstAddr, paramBurstLen, paramBurstOpts }, paramsStop,
  paramBufValid, { paramBufBurstAddr, paramBufBurstLen, paramBufBurstOpts },
  paramBufStop, clk, srst);

// Implement combinatorial logic for data transfer state machine.
always @(readState_q, burstWordAddr_q, burstLenCount_q, burstOpts_q,
  initBurstLenA_q, initBurstLenB_q, nextBurstLen_q, paramBufValid,
  paramBufBurstAddr, paramBufBurstLen, paramBufBurstOpts, paramsCoreStop,
  respCtrlFifoInStop)
begin

  // Hold current state by default.
  readState_d = readState_q;
  burstWordAddr_d = burstWordAddr_q;
  burstLenCount_d = burstLenCount_q;
  burstOpts_d = burstOpts_q;
  initBurstLenA_d = initBurstLenA_q;
  initBurstLenB_d = initBurstLenB_q;
  nextBurstLen_d = nextBurstLen_q;
  paramBufStop = 1'b1;
  paramsCoreValid = 1'b0;
  respCtrlFifoInValid = 1'b0;
  respCtrlFifoInCmd = RespCtrlDone;

  // Implement the state machine.
  case (readState_q)

    // Perform initial read transaction setup.
    ReadInitSetup :
    begin
      respCtrlFifoInValid = 1'b1;
      respCtrlFifoInCmd = RespCtrlReset;
      if (~respCtrlFifoInStop)
      begin
        readState_d = ReadSetParams;
        if (initBurstLenA_q < initBurstLenB_q)
        begin
          burstLenCount_d = burstLenCount_q - initBurstLenA_q;
          nextBurstLen_d = initBurstLenA_q;
        end
        else
        begin
          burstLenCount_d = burstLenCount_q - initBurstLenB_q;
          nextBurstLen_d = initBurstLenB_q;
        end
      end
    end

    // Check for end of read transaction before setting the core transfer
    // parameters.
    ReadSetParams :
    begin
      if (nextBurstLen_q == 13'd0)
      begin
        respCtrlFifoInValid = 1'b1;
        if (~respCtrlFifoInStop)
          readState_d = ReadIdle;
      end
      else
      begin
        paramsCoreValid = 1'b1;
        if (~paramsCoreStop)
          readState_d = ReadSegmentSetup;
      end
    end

    // Perform subsequent segment read transaction setup.
    ReadSegmentSetup :
    begin
      respCtrlFifoInValid = 1'b1;
      respCtrlFifoInCmd = RespCtrlCheck;
      if (~respCtrlFifoInStop)
      begin
        readState_d = ReadSetParams;
        burstWordAddr_d = burstWordAddr_q + nextBurstLen_q;
        if (burstLenCount_q >= SegmentSize [31:0])
        begin
          burstLenCount_d = burstLenCount_q - SegmentSize [31:0];
          nextBurstLen_d = SegmentSize [12:0];
        end
        else
        begin
          burstLenCount_d = 32'd0;
          nextBurstLen_d = burstLenCount_q [12:0];
        end
      end
    end

    // From the idle state, wait for new transfer parameters.
    default :
    begin
      burstWordAddr_d = paramBufBurstAddr [63:3];
      burstLenCount_d = paramBufBurstLen;
      burstOpts_d = paramBufBurstOpts;
      initBurstLenA_d = SegmentSize [12:0] -
        (paramBufBurstAddr [15:3] & BurstLenMask [12:0]);
      initBurstLenB_d = (paramBufBurstLen > SegmentSize [31:0]) ?
        SegmentSize [12:0] : paramBufBurstLen [12:0];
      paramBufStop = 1'b0;
      if (paramBufValid)
        readState_d = ReadInitSetup;
    end
  endcase

end

// Implement resettable state registers for data transfer state machine.
always @(posedge clk)
begin
  if (srst)
    readState_q <= ReadIdle;
  else
    readState_q <= readState_d;
end

// Implement non-resettable data transfer datapath registers.
always @(posedge clk)
begin
  burstWordAddr_q <= burstWordAddr_d;
  burstLenCount_q <= burstLenCount_d;
  burstOpts_q <= burstOpts_d;
  initBurstLenA_q <= initBurstLenA_d;
  initBurstLenB_q <= initBurstLenB_d;
  nextBurstLen_q <= nextBurstLen_d;
end

// Instantiiate the single data transfer core logic.
smiMemLibReadBurstCore #(16) readBurstCore
  (paramsCoreValid, { burstWordAddr_q, 3'd0 }, { nextBurstLen_q, 3'd0 },
  burstOpts_q, paramsCoreStop, readBufValid, readBufEofc, readBufData,
  readBufStop, segmentDoneValid, segmentDoneStatusOk, segmentDoneStop,
  smiReqValid, smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc,
  smiRespData, smiRespStop, clk, srst);

// Instantiate the response control FIFO.
smiSelfLinkBufferFifoS #(2, 16, 4) respCtrlFifo
  (respCtrlFifoInValid, respCtrlFifoInCmd, respCtrlFifoInStop,
  respCtrlFifoOutValid, respCtrlFifoOutCmd, respCtrlFifoOutStop, clk, srst);

// Implement combinatorial logic for read status tracking state machine.
always @(responseState_q, readStatusOk_q, respCtrlFifoOutValid,
  respCtrlFifoOutCmd, segmentDoneValid, segmentDoneStatusOk, doneBufStop)
begin

  // Hold current state by default.
  responseState_d = responseState_q;
  readStatusOk_d = readStatusOk_q;
  respCtrlFifoOutStop = 1'b1;
  segmentDoneStop = 1'b1;
  doneBufValid = 1'b0;

  // Implement the state machine.
  case (responseState_q)

    // Wait for the next respose update command.
    RespStatusWait :
    begin
      respCtrlFifoOutStop = 1'b0;
      if (respCtrlFifoOutValid)
      begin
        if (respCtrlFifoOutCmd == RespCtrlCheck)
          responseState_d = RespStatusCheck;
        else if (respCtrlFifoOutCmd == RespCtrlDone)
          responseState_d = RespStatusComplete;
        else
          responseState_d = RespStatusIdle;
      end
    end

    // In the response check state, wait for the next segment status input.
    RespStatusCheck :
    begin
      segmentDoneStop = 1'b0;
      if (segmentDoneValid)
      begin
        responseState_d = RespStatusWait;
        readStatusOk_d = readStatusOk_q & segmentDoneStatusOk;
      end
    end

    // Signal completion of the overall transfer.
    RespStatusComplete :
    begin
      doneBufValid = 1'b1;
      if (~doneBufStop)
        responseState_d = RespStatusIdle;
    end

    // In the idle state, wait for the reset command.
    default :
    begin
      readStatusOk_d = 1'b1;
      respCtrlFifoOutStop = 1'b0;
      if (respCtrlFifoOutValid & (respCtrlFifoOutCmd == RespCtrlReset))
        responseState_d = RespStatusWait;
    end
  endcase

end

// Implement resettable state registers for read status tracking.
always @(posedge clk)
begin
  if (srst)
    responseState_q <= RespStatusIdle;
  else
    responseState_q <= responseState_d;
end

// Implement non-resettable datapath registers for read status tracking.
always @(posedge clk)
begin
  readStatusOk_q <= readStatusOk_d;
end

// Add a toggle buffer to the done status output.
smiSelfLinkToggleBuffer #(1) doneStatusBuffer
  (doneBufValid, readStatusOk_q, doneBufStop, doneValid, doneStatusOk,
  doneStop, clk, srst);

// Buffer the read data. Note that since the transferred data is all 64-bit,
// we can just directly copy over the SMI frame contents and ignore the EOFC
// signal.
smiSelfLinkDoubleBuffer #(64) dataBuffer
  (readBufValid, readBufData, readBufStop, readValid, readData, readStop,
  clk, srst);

endmodule
