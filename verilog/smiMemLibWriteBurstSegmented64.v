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
// Memory access library segmented burst write transfer component. This carries
// out a segmented write burst transfer, with data being copied from a 64-bit
// wide SELF data input. Bursts are automatically segmented so that they do not
// cross address boundaries at integer multiples of 4096.
//

`timescale 1ns/1ps

module smiMemLibWriteBurstSegmented64
  (paramsValid, paramBurstAddr, paramBurstLen, paramBurstOpts, paramsStop,
  writeValid, writeData, writeStop, doneValid, doneStatusOk, doneStop,
  smiReqValid, smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc,
  smiRespData, smiRespStop, clk, srst);

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

// Specify write data inputs.
input        writeValid;
input [63:0] writeData;
output       writeStop;

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
parameter [2:0]
  WriteIdle = 0,
  WriteInitSetup = 1,
  WriteSetParams = 2,
  WriteCopyData = 3,
  WriteSegmentSetup = 4;

// Define the control tokens passed from the data transfer state machine to
// the write response state machine.
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

// Buffered write data inputs.
wire        writeBufValid;
wire [63:0] writeBufData;
reg         writeBufStop;

// Core parameter handshake signals.
reg  paramsCoreValid;
wire paramsCoreStop;

// Data copy signals.
reg       copyValid;
reg [7:0] copyEofc;
wire      copyStop;

// Specify the state signals for the data transfer state machine.
reg [2:0]  writeState_d;
reg [60:0] burstWordAddr_d;
reg [31:0] burstLenCount_d;
reg [7:0]  burstOpts_d;
reg [12:0] initBurstLenA_d;
reg [12:0] initBurstLenB_d;
reg [12:0] nextBurstLen_d;
reg [12:0] flitCopyCount_d;

reg [2:0]  writeState_q;
reg [60:0] burstWordAddr_q;
reg [31:0] burstLenCount_q;
reg [7:0]  burstOpts_q;
reg [12:0] initBurstLenA_q;
reg [12:0] initBurstLenB_q;
reg [12:0] nextBurstLen_q;
reg [12:0] flitCopyCount_q;

// Specify the response control signals.
reg       respCtrlFifoInValid;
reg [1:0] respCtrlFifoInCmd;
wire      respCtrlFifoInStop;

wire       respCtrlFifoOutValid;
wire [1:0] respCtrlFifoOutCmd;
reg        respCtrlFifoOutStop;

// Specify write status state signals.
reg [1:0] responseState_d;
reg       writeStatusOk_d;

reg [1:0] responseState_q;
reg       writeStatusOk_q;

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

// Add a double buffer to the write data input.
smiSelfLinkDoubleBuffer #(64) writeDataBuffer
  (writeValid, writeData, writeStop, writeBufValid, writeBufData, writeBufStop,
  clk, srst);

// Implement combinatorial logic for data transfer state machine.
always @(writeState_q, burstWordAddr_q, burstLenCount_q, burstOpts_q,
  initBurstLenA_q, initBurstLenB_q, nextBurstLen_q, flitCopyCount_q,
  paramBufValid, paramBufBurstAddr, paramBufBurstLen, paramBufBurstOpts,
  paramsCoreStop, writeBufValid, copyStop, respCtrlFifoInStop)
begin

  // Hold current state by default.
  writeState_d = writeState_q;
  burstWordAddr_d = burstWordAddr_q;
  burstLenCount_d = burstLenCount_q;
  burstOpts_d = burstOpts_q;
  initBurstLenA_d = initBurstLenA_q;
  initBurstLenB_d = initBurstLenB_q;
  nextBurstLen_d = nextBurstLen_q;
  flitCopyCount_d = flitCopyCount_q;
  paramBufStop = 1'b1;
  paramsCoreValid = 1'b0;
  copyValid = 1'b0;
  writeBufStop = 1'b1;
  respCtrlFifoInValid = 1'b0;
  respCtrlFifoInCmd = RespCtrlDone;

  // Derive the EOFC value from the flit copy count.
  if (flitCopyCount_q == 13'd1)
    copyEofc = 8'd8;
  else
    copyEofc = 8'd0;

  // Implement the state machine.
  case (writeState_q)

    // Perform initial write transaction setup.
    WriteInitSetup :
    begin
      respCtrlFifoInValid = 1'b1;
      respCtrlFifoInCmd = RespCtrlReset;
      if (~respCtrlFifoInStop)
      begin
        writeState_d = WriteSetParams;
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

    // Check for end of write transaction before setting the core transfer
    // parameters.
    WriteSetParams :
    begin
      flitCopyCount_d = nextBurstLen_q;
      if (nextBurstLen_q == 13'd0)
      begin
        respCtrlFifoInValid = 1'b1;
        if (~respCtrlFifoInStop)
          writeState_d = WriteIdle;
      end
      else
      begin
        paramsCoreValid = 1'b1;
        if (~paramsCoreStop)
          writeState_d = WriteCopyData;
      end
    end

    // Perform data copying by hooking up the write data handshake signals.
    WriteCopyData :
    begin
      copyValid = writeBufValid;
      writeBufStop = copyStop;
      if (writeBufValid & ~copyStop)
      begin
        flitCopyCount_d = flitCopyCount_q - 13'd1;

        // Final flit detected - prepare next segment.
        if (flitCopyCount_q == 13'd1)
          writeState_d = WriteSegmentSetup;
      end
    end

    // Perform subsequent segment write transaction setup.
    WriteSegmentSetup :
    begin
      respCtrlFifoInValid = 1'b1;
      respCtrlFifoInCmd = RespCtrlCheck;
      if (~respCtrlFifoInStop)
      begin
        writeState_d = WriteSetParams;
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
        writeState_d = WriteInitSetup;
    end
  endcase

end

// Implement resettable state registers for data transfer state machine.
always @(posedge clk)
begin
  if (srst)
    writeState_q <= WriteIdle;
  else
    writeState_q <= writeState_d;
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
  flitCopyCount_q <= flitCopyCount_d;
end

// Instantiate the core write burst logic.
smiMemLibWriteBurstCore #(16) writeBurstCore
  (paramsCoreValid, { burstWordAddr_q, 3'd0 }, { nextBurstLen_q, 3'd0 },
  burstOpts_q, paramsCoreStop, copyValid, copyEofc, writeBufData, copyStop,
  segmentDoneValid, segmentDoneStatusOk, segmentDoneStop, smiReqValid,
  smiReqEofc, smiReqData, smiReqStop, smiRespValid, smiRespEofc, smiRespData,
  smiRespStop, clk, srst);

// Instantiate the response control FIFO.
smiSelfLinkBufferFifoS #(2, 16, 4) respCtrlFifo
  (respCtrlFifoInValid, respCtrlFifoInCmd, respCtrlFifoInStop,
  respCtrlFifoOutValid, respCtrlFifoOutCmd, respCtrlFifoOutStop, clk, srst);

// Implement combinatorial logic for write status tracking state machine.
always @(responseState_q, writeStatusOk_q, respCtrlFifoOutValid,
  respCtrlFifoOutCmd, segmentDoneValid, segmentDoneStatusOk, doneBufStop)
begin

  // Hold current state by default.
  responseState_d = responseState_q;
  writeStatusOk_d = writeStatusOk_q;
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
        writeStatusOk_d = writeStatusOk_q & segmentDoneStatusOk;
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
      writeStatusOk_d = 1'b1;
      respCtrlFifoOutStop = 1'b0;
      if (respCtrlFifoOutValid & (respCtrlFifoOutCmd == RespCtrlReset))
        responseState_d = RespStatusWait;
    end
  endcase

end

// Implement resettable state registers for write status tracking.
always @(posedge clk)
begin
  if (srst)
    responseState_q <= RespStatusIdle;
  else
    responseState_q <= responseState_d;
end

// Implement non-resettable datapath registers for write status tracking.
always @(posedge clk)
begin
  writeStatusOk_q <= writeStatusOk_d;
end

// Add a toggle buffer to the done status output.
smiSelfLinkToggleBuffer #(1) doneStatusBuffer
  (doneBufValid, writeStatusOk_q, doneBufStop, doneValid, doneStatusOk,
  doneStop, clk, srst);

endmodule
