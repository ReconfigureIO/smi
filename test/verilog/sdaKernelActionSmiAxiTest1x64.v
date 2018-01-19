//
// (c) 2018 ReconfigureIO
//
// <COPYRIGHT TERMS>
//

//
// Provides the kernel action logic for a single 64-bit wide SMI/AXI test.
//

`timescale 1ns/1ps

// Can be redefined on the synthesis command line.
`define AXI_MASTER_ADDR_WIDTH 64

// Can be redefined on the synthesis command line.
`define AXI_MASTER_DATA_WIDTH 64

// Can be redefined on the synthesis command line.
`define AXI_MASTER_ID_WIDTH 1

// Can be redefined on the synthesis command line.
`define AXI_MASTER_USER_WIDTH 1

// Specify the control register offsets.
`define AXI_CONTROL_OFFSET_MEM_BASE_ADDR_L      32'h40
`define AXI_CONTROL_OFFSET_MEM_BASE_ADDR_H      32'h44
`define AXI_CONTROL_OFFSET_MEM_BLOCK_SIZE       32'h48
`define AXI_CONTROL_OFFSET_TEST_COUNT           32'h4C
`define AXI_CONTROL_OFFSET_ERR_RESULT_ADDR_L    32'h50
`define AXI_CONTROL_OFFSET_ERR_RESULT_ADDR_H    32'h54
`define AXI_CONTROL_OFFSET_DCOUNT_RESULT_ADDR_L 32'h58
`define AXI_CONTROL_OFFSET_DCOUNT_RESULT_ADDR_H 32'h5C

// The module name is common for different kernel action toplevel entities.
module teak__action__top__gmem
  (go_0Ready, go_0Stop, done_0Ready, done_0Stop, s_axi_araddr, s_axi_arcache, s_axi_arprot,
  s_axi_arvalid, s_axi_arready, s_axi_rdata, s_axi_rresp, s_axi_rvalid,
  s_axi_rready, s_axi_awaddr, s_axi_awcache, s_axi_awprot, s_axi_awvalid,
  s_axi_awready, s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
  s_axi_bresp, s_axi_bvalid, s_axi_bready, m_axi_gmem_awaddr, m_axi_gmem_awlen,
  m_axi_gmem_awsize, m_axi_gmem_awburst, m_axi_gmem_awlock, m_axi_gmem_awcache,
  m_axi_gmem_awprot, m_axi_gmem_awqos, m_axi_gmem_awregion, m_axi_gmem_awuser,
  m_axi_gmem_awid, m_axi_gmem_awvalid, m_axi_gmem_awready, m_axi_gmem_wdata,
  m_axi_gmem_wstrb, m_axi_gmem_wlast, m_axi_gmem_wuser,
  m_axi_gmem_wvalid, m_axi_gmem_wready, m_axi_gmem_bresp, m_axi_gmem_buser,
  m_axi_gmem_bid, m_axi_gmem_bvalid, m_axi_gmem_bready, m_axi_gmem_araddr,
  m_axi_gmem_arlen, m_axi_gmem_arsize, m_axi_gmem_arburst, m_axi_gmem_arlock,
  m_axi_gmem_arcache, m_axi_gmem_arprot, m_axi_gmem_arqos, m_axi_gmem_arregion,
  m_axi_gmem_aruser, m_axi_gmem_arid, m_axi_gmem_arvalid, m_axi_gmem_arready,
  m_axi_gmem_rdata, m_axi_gmem_rresp, m_axi_gmem_rlast, m_axi_gmem_ruser,
  m_axi_gmem_rid, m_axi_gmem_rvalid, m_axi_gmem_rready, paramaddr_0Ready,
  paramaddr_0Data, paramaddr_0Stop, paramdata_0Ready, paramdata_0Data, paramdata_0Stop,
  clk, reset);

// Action control signals.
input  go_0Ready;
output go_0Stop;
output done_0Ready;
input  done_0Stop;

// Parameter data access signals. Provides a SELF channel output for address
// values and a SELF channel input for the corresponding data items read from
// the parameter register file.
output        paramaddr_0Ready;
output [31:0] paramaddr_0Data;
input         paramaddr_0Stop;

input         paramdata_0Ready;
input [31:0]  paramdata_0Data;
output        paramdata_0Stop;

// Specifies the AXI slave bus signals.
input [31:0]  s_axi_araddr;
input [3:0]   s_axi_arcache;
input [2:0]   s_axi_arprot;
input         s_axi_arvalid;
output        s_axi_arready;
output [31:0] s_axi_rdata;
output [1:0]  s_axi_rresp;
output        s_axi_rvalid;
input         s_axi_rready;
input [31:0]  s_axi_awaddr;
input [3:0]   s_axi_awcache;
input [2:0]   s_axi_awprot;
input         s_axi_awvalid;
output        s_axi_awready;
input [31:0]  s_axi_wdata;
input [3:0]   s_axi_wstrb;
input         s_axi_wvalid;
output        s_axi_wready;
output [1:0]  s_axi_bresp;
output        s_axi_bvalid;
input         s_axi_bready;

// Specifies the AXI master write address signals.
output [`AXI_MASTER_ADDR_WIDTH-1:0] m_axi_gmem_awaddr;
output [7:0]                        m_axi_gmem_awlen;
output [2:0]                        m_axi_gmem_awsize;
output [1:0]                        m_axi_gmem_awburst;
output                              m_axi_gmem_awlock;
output [3:0]                        m_axi_gmem_awcache;
output [2:0]                        m_axi_gmem_awprot;
output [3:0]                        m_axi_gmem_awqos;
output [3:0]                        m_axi_gmem_awregion;
output [`AXI_MASTER_USER_WIDTH-1:0] m_axi_gmem_awuser;
output [`AXI_MASTER_ID_WIDTH-1:0]   m_axi_gmem_awid;
output                              m_axi_gmem_awvalid;
input                               m_axi_gmem_awready;

// Specifies the AXI master write data signals.
output [`AXI_MASTER_DATA_WIDTH-1:0]   m_axi_gmem_wdata;
output [`AXI_MASTER_DATA_WIDTH/8-1:0] m_axi_gmem_wstrb;
output                                m_axi_gmem_wlast;
output [`AXI_MASTER_USER_WIDTH-1:0]   m_axi_gmem_wuser;
output                                m_axi_gmem_wvalid;
input                                 m_axi_gmem_wready;

// Specifies the AXI master write response signals.
input [1:0]                        m_axi_gmem_bresp;
input [`AXI_MASTER_USER_WIDTH-1:0] m_axi_gmem_buser;
input [`AXI_MASTER_ID_WIDTH-1:0]   m_axi_gmem_bid;
input                              m_axi_gmem_bvalid;
output                             m_axi_gmem_bready;

// Specifies the AXI master read address signals.
output [`AXI_MASTER_ADDR_WIDTH-1:0] m_axi_gmem_araddr;
output [7:0]                        m_axi_gmem_arlen;
output [2:0]                        m_axi_gmem_arsize;
output [1:0]                        m_axi_gmem_arburst;
output                              m_axi_gmem_arlock;
output [3:0]                        m_axi_gmem_arcache;
output [2:0]                        m_axi_gmem_arprot;
output [3:0]                        m_axi_gmem_arqos;
output [3:0]                        m_axi_gmem_arregion;
output [`AXI_MASTER_USER_WIDTH-1:0] m_axi_gmem_aruser;
output [`AXI_MASTER_ID_WIDTH-1:0]   m_axi_gmem_arid;
output                              m_axi_gmem_arvalid;
input                               m_axi_gmem_arready;

// Specifies the AXI master read data signals.
input [`AXI_MASTER_DATA_WIDTH-1:0] m_axi_gmem_rdata;
input [1:0]                        m_axi_gmem_rresp;
input                              m_axi_gmem_rlast;
input [`AXI_MASTER_USER_WIDTH-1:0] m_axi_gmem_ruser;
input [`AXI_MASTER_ID_WIDTH-1:0]   m_axi_gmem_rid;
input                              m_axi_gmem_rvalid;
output                             m_axi_gmem_rready;

// System level signals.
input clk;
input reset;

// Specify state space for test runner state machine.
parameter [4:0]
  TestStateReset = 0,
  TestStateIdle = 1,
  TestStateGetParam1l = 2,
  TestStateGetParam1h = 3,
  TestStateGetParam2 = 4,
  TestStateGetParam3 = 5,
  TestStateGetParam4l = 6,
  TestStateGetParam4h = 7,
  TestStateGetParam5l = 8,
  TestStateGetParam5h = 9,
  TestStateSetConfig = 10,
  TestStateGetStatus = 11,
  TestStateWriteErrCountReq = 12,
  TestStateWriteErrCountDone = 13,
  TestStateWriteDataCountReq = 14,
  TestStateWriteDataCountDone = 15,
  TestStateReportResult = 16;

// Parameter request state machine signals.
reg [3:0] paramReqCount_d;
reg [3:0] paramReqCount_q;

// Action execution state machine signals.
reg [4:0]  testState_d;
reg [63:0] memBaseAddr_d;
reg [31:0] memBlockLength_d;
reg [31:0] fuzzTestCount_d;
reg [63:0] errResultAddr_d;
reg [63:0] dcountResultAddr_d;
reg [31:0] errorCount_d;
reg [63:0] dataCount_d;

reg [4:0]  testState_q;
reg [63:0] memBaseAddr_q;
reg [31:0] memBlockLength_q;
reg [31:0] fuzzTestCount_q;
reg [63:0] errResultAddr_q;
reg [63:0] dcountResultAddr_q;
reg [31:0] errorCount_q;
reg [63:0] dataCount_q;

reg        paramReq;
reg        goHalt;
reg        doneReady;
reg        paramAddrReady;
reg [31:0] paramAddrData;
reg        paramReadHalt;

// Specifies internal SMI memory bus signals.
wire        smiStatReqReady;
wire [7:0]  smiStatReqEofc;
wire [63:0] smiStatReqData;
wire        smiStatReqStop;
wire        smiStatRespReady;
wire [7:0]  smiStatRespEofc;
wire [63:0] smiStatRespData;
wire        smiStatRespStop;

wire        smiTestReqReady;
wire [7:0]  smiTestReqEofc;
wire [63:0] smiTestReqData;
wire        smiTestReqStop;
wire        smiTestRespReady;
wire [7:0]  smiTestRespEofc;
wire [63:0] smiTestRespData;
wire        smiTestRespStop;

wire        smiReqReady;
wire [7:0]  smiReqEofc;
wire [63:0] smiReqData;
wire        smiReqStop;
wire        smiRespReady;
wire [7:0]  smiRespEofc;
wire [63:0] smiRespData;
wire        smiRespStop;

// Specifies fuzz tester configuration and status signals.
wire configValid;
wire configStop;

reg        statusWriteValid;
reg [63:0] statusWriteData;
reg [63:0] statusWriteAddr;
wire       statusWriteStop;
wire       statusWriteDoneValid;
wire       statusWriteDoneStatusOk;
reg        statusWriteDoneStop;

wire        statusValid;
wire [31:0] statusErrorCount;
wire [63:0] statusDataCount;
reg         statusStop;

// AXI slave loopback signals. Initialised to zero to avoid locking the slave
// AXI bus on reset.
reg s_axi_read_ready_q = 1'b0;
reg s_axi_read_complete_q = 1'b0;
reg s_axi_write_ready_q = 1'b0;
reg s_axi_write_complete_q = 1'b0;

// Implement combinatorial logic for parameter request state machine.
always @(paramReqCount_q, paramReq, paramaddr_0Stop)
begin

  // Hold current state by default.
  paramReqCount_d = paramReqCount_q;
  paramAddrReady = 1'b0;
  paramAddrData = 32'd0;

  // From the idle state, wait for parameter request to be initiated.
  if (paramReqCount_q == 4'd0)
  begin
    if (paramReq)
      paramReqCount_d = 4'd1;
  end

  // Issue parameter requests.
  else if (paramReqCount_q <= 4'd8)
  begin
    paramAddrReady = 1'b1;
    case (paramReqCount_q)
      4'd1 : paramAddrData = `AXI_CONTROL_OFFSET_MEM_BASE_ADDR_L;
      4'd2 : paramAddrData = `AXI_CONTROL_OFFSET_MEM_BASE_ADDR_H;
      4'd3 : paramAddrData = `AXI_CONTROL_OFFSET_MEM_BLOCK_SIZE;
      4'd4 : paramAddrData = `AXI_CONTROL_OFFSET_TEST_COUNT;
      4'd5 : paramAddrData = `AXI_CONTROL_OFFSET_ERR_RESULT_ADDR_L;
      4'd6 : paramAddrData = `AXI_CONTROL_OFFSET_ERR_RESULT_ADDR_H;
      4'd7 : paramAddrData = `AXI_CONTROL_OFFSET_DCOUNT_RESULT_ADDR_L;
      4'd8 : paramAddrData = `AXI_CONTROL_OFFSET_DCOUNT_RESULT_ADDR_H;
      default : paramAddrData = 32'd0;
    endcase
    if (~paramaddr_0Stop)
      paramReqCount_d = paramReqCount_q + 4'd1;
  end

  // Revert to idle state.
  else
  begin
    paramReqCount_d = 4'd0;
  end

end

// Implement combinatorial logic for action execution state machine.
always @(testState_q, memBaseAddr_q, memBlockLength_q, fuzzTestCount_q,
  errResultAddr_q, dcountResultAddr_q, errorCount_q, dataCount_q, go_0Ready,
  done_0Stop, paramdata_0Ready, paramdata_0Data, configStop, statusValid,
  statusErrorCount, statusDataCount, statusWriteStop, statusWriteDoneValid)
begin

  // Hold current state by default.
  testState_d = testState_q;
  memBaseAddr_d = memBaseAddr_q;
  memBlockLength_d = memBlockLength_q;
  fuzzTestCount_d = fuzzTestCount_q;
  errResultAddr_d = errResultAddr_q;
  dcountResultAddr_d = dcountResultAddr_q;
  errorCount_d = errorCount_q;
  dataCount_d = dataCount_q;

  goHalt = 1'b1;
  doneReady = 1'b0;
  paramReq = 1'b0;
  paramReadHalt = 1'b1;
  statusWriteValid = 1'b0;
  statusWriteData = 64'd0;
  statusWriteAddr = 64'd0;
  statusWriteDoneStop = 1'b1;
  statusStop = 1'b1;

  // Implement state machine.
  case (testState_q)

    // In the idle state, wait for the 'go' request.
    TestStateIdle :
    begin
      goHalt = 1'b0;
      if (go_0Ready)
      begin
        testState_d = TestStateGetParam1l;
        errorCount_d = 32'd0;
        paramReq = 1'b1;
      end
    end

    // Get parameter 1 (64-bit test memory block base address).
    TestStateGetParam1l :
    begin
      paramReadHalt = 1'b0;
      memBaseAddr_d [31:0] = paramdata_0Data;
      if (paramdata_0Ready)
        testState_d = TestStateGetParam1h;
    end

    TestStateGetParam1h :
    begin
      paramReadHalt = 1'b0;
      memBaseAddr_d [63:32] = paramdata_0Data;
      if (paramdata_0Ready)
        testState_d = TestStateGetParam2;
    end

    // Get parameter 2 (32-bit test memory block length).
    TestStateGetParam2 :
    begin
      paramReadHalt = 1'b0;
      memBlockLength_d = paramdata_0Data;
      if (paramdata_0Ready)
        testState_d = TestStateGetParam3;
    end

    // Get parameter 3 (32-bit test count).
    TestStateGetParam3 :
    begin
      paramReadHalt = 1'b0;
      fuzzTestCount_d = paramdata_0Data;
      if (paramdata_0Ready)
        testState_d = TestStateGetParam4l;
    end

    // Get parameter 4 (64-bit error count result base address).
    TestStateGetParam4l :
    begin
      paramReadHalt = 1'b0;
      errResultAddr_d [31:0] = paramdata_0Data;
      if (paramdata_0Ready)
        testState_d = TestStateGetParam4h;
    end

    TestStateGetParam4h :
    begin
      paramReadHalt = 1'b0;
      errResultAddr_d [63:32] = paramdata_0Data;
      if (paramdata_0Ready)
        testState_d = TestStateGetParam5l;
    end

    // Get parameter 5 (64-bit data count result base address).
    TestStateGetParam5l :
    begin
      paramReadHalt = 1'b0;
      dcountResultAddr_d [31:0] = paramdata_0Data;
      if (paramdata_0Ready)
        testState_d = TestStateGetParam5h;
    end

    TestStateGetParam5h :
    begin
      paramReadHalt = 1'b0;
      dcountResultAddr_d [63:32] = paramdata_0Data;
      if (paramdata_0Ready)
        testState_d = TestStateSetConfig;
    end

    // Set the configuration parameters, initiating the fuzz testing.
    TestStateSetConfig :
    begin
      if (~configStop)
        testState_d = TestStateGetStatus;
    end

    // Get the fuzz testing status value.
    TestStateGetStatus :
    begin
      statusStop = 1'b0;
      errorCount_d = statusErrorCount;
      dataCount_d = statusDataCount;
      if (statusValid)
        testState_d = TestStateWriteErrCountReq;
    end

    // Write the status error count value to the return location in shared memory.
    TestStateWriteErrCountReq :
    begin
      statusWriteValid = 1'b1;
      statusWriteAddr = errResultAddr_q;
      statusWriteData = { 32'd0, errorCount_q };
      if (~statusWriteStop)
        testState_d = TestStateWriteErrCountDone;
    end

    TestStateWriteErrCountDone :
    begin
      statusWriteDoneStop = 1'b0;
      if (statusWriteDoneValid)
        testState_d = TestStateWriteDataCountReq;
    end

    // Write the status data count value to the return location in shared memory.
    TestStateWriteDataCountReq :
    begin
      statusWriteValid = 1'b1;
      statusWriteAddr = dcountResultAddr_q;
      statusWriteData = dataCount_q;
      if (~statusWriteStop)
        testState_d = TestStateWriteDataCountDone;
    end

    TestStateWriteDataCountDone :
    begin
      statusWriteDoneStop = 1'b0;
      if (statusWriteDoneValid)
        testState_d = TestStateReportResult;
    end

    // Indicate completion to the SDAccel framework.
    TestStateReportResult :
    begin
      doneReady = 1'b1;
      if (~done_0Stop)
        testState_d = TestStateIdle;
    end

    // From the reset state, transition to the idle state.
    default :
    begin
      testState_d = TestStateIdle;
    end
  endcase

end

// Implement resettable state registers for test control state machine.
always @(posedge clk)
begin
  if (reset)
  begin
    testState_q <= TestStateReset;
    paramReqCount_q <= 4'd0;
  end
  else
  begin
    testState_q <= testState_d;
    paramReqCount_q <= paramReqCount_d;
  end
end

// Implement non-resettable data registers for test control state machine.
always @(posedge clk)
begin
  memBaseAddr_q <= memBaseAddr_d;
  memBlockLength_q <= memBlockLength_d;
  fuzzTestCount_q <= fuzzTestCount_d;
  errResultAddr_q <= errResultAddr_d;
  dcountResultAddr_q <= dcountResultAddr_d;
  errorCount_q <= errorCount_d;
  dataCount_q <= dataCount_d;
end

// Connect external handshake signals.
assign go_0Stop = goHalt;
assign done_0Ready = doneReady;

assign paramaddr_0Ready = paramAddrReady;
assign paramaddr_0Data = paramAddrData;
assign paramdata_0Stop = paramReadHalt;

assign configValid = (testState_q == TestStateSetConfig) ? 1'b1 : 1'b0;

// Implement AXI read control loopback.
always @(posedge clk)
begin
  if (s_axi_read_complete_q)
  begin
    s_axi_read_complete_q <= ~s_axi_rready;
  end
  else if (s_axi_read_ready_q)
  begin
    s_axi_read_ready_q <= 1'b0;
    s_axi_read_complete_q <= 1'b1;
  end
  else
  begin
    s_axi_read_ready_q <= s_axi_arvalid;
  end
end

assign s_axi_arready = s_axi_read_ready_q;
assign s_axi_rdata = errorCount_q;
assign s_axi_rresp = 2'b0;
assign s_axi_rvalid = s_axi_read_complete_q;

// Implement AXI write control loopback.
always @(posedge clk)
begin
  if (s_axi_write_complete_q)
  begin
    s_axi_write_complete_q <= ~s_axi_bready;
  end
  else if (s_axi_write_ready_q)
  begin
    s_axi_write_ready_q <= 1'b0;
    s_axi_write_complete_q <= 1'b1;
  end
  else
  begin
    s_axi_write_ready_q <= s_axi_awvalid & s_axi_wvalid;
  end
end

assign s_axi_awready = s_axi_write_ready_q;
assign s_axi_wready = s_axi_write_ready_q;
assign s_axi_bresp = 2'b0;
assign s_axi_bvalid = s_axi_write_complete_q;

// Instantiate the SMI memory fuzz test module.
smiMemLibFuzzTestBurst64 smiMemLibFuzzTestBurst64
  (configValid, memBaseAddr_q, memBlockLength_q, fuzzTestCount_q, configStop,
  statusValid, statusErrorCount, statusDataCount, statusStop, smiTestReqReady,
  smiTestReqEofc, smiTestReqData, smiTestReqStop, smiTestRespReady,
  smiTestRespEofc, smiTestRespData, smiTestRespStop, clk, reset);

// Instantiate the status memory write module.
smiMemLibWriteWord64 statusWriter
  (statusWriteValid, statusWriteAddr, 8'h01, statusWriteData, statusWriteStop,
  statusWriteDoneValid, statusWriteDoneStatusOk, statusWriteDoneStop,
  smiStatReqReady, smiStatReqEofc, smiStatReqData, smiStatReqStop,
  smiStatRespReady, smiStatRespEofc, smiStatRespData, smiStatRespStop,
  clk, reset);

// Instantiate two-way SMI transaction arbiter.
smiTransactionArbiterX2 #(8, 2, 64, 4) transactionArbiter
  (smiTestReqReady, smiTestReqEofc, smiTestReqData, smiTestReqStop,
  smiTestRespReady, smiTestRespEofc, smiTestRespData, smiTestRespStop,
  smiStatReqReady, smiStatReqEofc, smiStatReqData, smiStatReqStop,
  smiStatRespReady, smiStatRespEofc, smiStatRespData, smiStatRespStop,
  smiReqReady, smiReqEofc, smiReqData, smiReqStop, smiRespReady, smiRespEofc,
  smiRespData, smiRespStop, clk, reset);

// Instantiate the SMI/AXI bus adapter.
smiAxiMemBusAdaptor #(3, `AXI_MASTER_ID_WIDTH) smiAxiMemBusAdaptor
  (smiReqReady, smiReqEofc, smiReqData, smiReqStop, smiRespReady, smiRespEofc,
  smiRespData, smiRespStop, m_axi_gmem_arvalid, m_axi_gmem_arready,
  m_axi_gmem_arid, m_axi_gmem_araddr, m_axi_gmem_arlen, m_axi_gmem_arsize,
  m_axi_gmem_arcache, m_axi_gmem_rvalid, m_axi_gmem_rready, m_axi_gmem_rid,
  m_axi_gmem_rdata, m_axi_gmem_rresp, m_axi_gmem_rlast, m_axi_gmem_awvalid,
  m_axi_gmem_awready, m_axi_gmem_awid, m_axi_gmem_awaddr, m_axi_gmem_awlen,
  m_axi_gmem_awsize, m_axi_gmem_awcache, m_axi_gmem_wvalid, m_axi_gmem_wready,
  m_axi_gmem_wdata, m_axi_gmem_wstrb, m_axi_gmem_wlast, m_axi_gmem_bvalid,
  m_axi_gmem_bready, m_axi_gmem_bid, m_axi_gmem_bresp, reset, clk, reset);

// Tie off unused AXI memory access signals.
assign m_axi_gmem_awburst = 2'b1;
assign m_axi_gmem_awlock = 1'b0;
assign m_axi_gmem_awprot = 3'b0;
assign m_axi_gmem_awqos = 4'b0;
assign m_axi_gmem_awregion = 4'b0;
assign m_axi_gmem_awuser = `AXI_MASTER_USER_WIDTH'b0;
assign m_axi_gmem_wuser = `AXI_MASTER_USER_WIDTH'b0;

assign m_axi_gmem_arburst = 2'b1;
assign m_axi_gmem_arlock = 1'b0;
assign m_axi_gmem_arprot = 3'b0;
assign m_axi_gmem_arqos = 4'b0;
assign m_axi_gmem_arregion = 4'b0;
assign m_axi_gmem_aruser = `AXI_MASTER_USER_WIDTH'b0;

endmodule
