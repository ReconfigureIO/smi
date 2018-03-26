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
// limitations under the License.//
//

package smiMemTemplates

import (
	"fmt"
	"os"
	"text/template"
)

//
// Defines the template configuration options for a Huwawei FP1 SMI kernel
// adaptor module.
//
type smiFp1KernelAdaptorConfig struct {
	ModuleName            string                      // Name of the kernel adaptor module.
	ArbitrationModuleName string                      // Name of the arbitration tree module.
	KernelModuleName      string                      // Name of the SMI kernel module.
	AxiByteIndexSize      uint                        // Size of AXI data byte index values.
	AxiBusDataWidth       uint                        // Width of AXI data bus in bytes.
	AxiBusIdWidth         uint                        // Width of AXI ID signal.
	SmiMemBusClientConns  []smiMemBusConnectionConfig // List of client side connections.
	SmiMemBusServerConn   []smiMemBusConnectionConfig // Single server side connection.
	SmiMemBusWireConns    []smiMemBusConnectionConfig // Internal wire connections.
}

//
// Defines the template for instantiating an SMI SDAccel kernel adaptor module.
//
var smiFp1KernelAdaptorTemplate = `
{{define "smiFp1KernelAdaptor"}}{{template "smiMemBusFileHeaderTemplate" . }}
module {{.ModuleName}} (

  // Action control signals.
  input          go_ready,
  output         go_stop,
  output         done_ready,
  input          done_stop,

  // Configuration register file access signals.
  output         config_req_valid,
  output [ 31:0] config_req_data,
  input          config_req_stop,
  input          config_resp_valid,
  input  [ 31:0] config_resp_data,
  output         config_resp_stop,

  // Kernel internal register access signals.
  input          control_req_valid,
  input  [ 64:0] control_req_data,
  output         control_req_stop,
  output         control_resp_valid,
  output [ 33:0] control_resp_data,
  input          control_resp_stop,

  // Kernel interrupt queue signals.
  output         interrupt_valid,
  output [ 31:0] interrupt_data,
  input          interrupt_stop,

  // Specifies the AXI master write address signals.
  output [ 63:0] m_axi_gmem_awaddr,
  output [  7:0] m_axi_gmem_awlen,
  output [  2:0] m_axi_gmem_awsize,
  output {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_awid,
  output         m_axi_gmem_awvalid,
  input          m_axi_gmem_awready,

  // Specifies the AXI master write data signals.
  output {{makeBitSliceFromScaledWidth .AxiBusDataWidth 8}} m_axi_gmem_wdata,
  output {{makeBitSliceFromScaledWidth .AxiBusDataWidth 1}} m_axi_gmem_wstrb,
  output         m_axi_gmem_wlast,
  output {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_wid,
  output         m_axi_gmem_wvalid,
  input          m_axi_gmem_wready,

  // Specifies the AXI master write response signals.
  input  [  1:0] m_axi_gmem_bresp,
  input  {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_bid,
  input          m_axi_gmem_bvalid,
  output         m_axi_gmem_bready,

  // Specifies the AXI master read address signals.
  output [ 63:0] m_axi_gmem_araddr,
  output [  7:0] m_axi_gmem_arlen,
  output [  2:0] m_axi_gmem_arsize,
  output {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_arid,
  output         m_axi_gmem_arvalid,
  input          m_axi_gmem_arready,

  // Specifies the AXI master read data signals.
  input  {{makeBitSliceFromScaledWidth .AxiBusDataWidth 8}} m_axi_gmem_rdata,
  input  [  1:0] m_axi_gmem_rresp,
  input          m_axi_gmem_rlast,
  input  {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_rid,
  input          m_axi_gmem_rvalid,
  output         m_axi_gmem_rready,

  // Specify system level signals.
  input          clk,
  input          reset
);
{{template "smiMemBusConnectionWireList" .SmiMemBusWireConns}}
// Concatenated SMI flit vectors. {{range .SmiMemBusClientConns}}
wire [ 71:0] {{.SmiNetReqName}}Flit;
wire [ 71:0] {{.SmiNetRespName}}Flit;{{end}}

// Unused AXI interface signals.
wire [  3:0] m_axi_gmem_arcache;
wire [  3:0] m_axi_gmem_awcache;

//
// Instantiate the SMI/AXI memory controller adaptor.
//
smiAxiMemBusAdaptor #({{.AxiByteIndexSize}}, {{.AxiBusIdWidth}}, 33) axiBusAdaptor (
  {{with $wire := index .SmiMemBusServerConn 0}}
  // Connect SMI main memory bus.
  .smiReqReady  ({{$wire.SmiNetReqName}}Ready),
  .smiReqEofc   ({{$wire.SmiNetReqName}}Eofc),
  .smiReqData   ({{$wire.SmiNetReqName}}Data),
  .smiReqStop   ({{$wire.SmiNetReqName}}Stop),
  .smiRespReady ({{$wire.SmiNetRespName}}Ready),
  .smiRespEofc  ({{$wire.SmiNetRespName}}Eofc),
  .smiRespData  ({{$wire.SmiNetRespName}}Data),
  .smiRespStop  ({{$wire.SmiNetRespName}}Stop),
  {{end}}
  // Connect active AXI read data bus signals.
  .axiARValid   (m_axi_gmem_arvalid),
  .axiARReady   (m_axi_gmem_arready),
  .axiARId      (m_axi_gmem_arid),
  .axiARAddr    (m_axi_gmem_araddr),
  .axiARLen     (m_axi_gmem_arlen),
  .axiARSize    (m_axi_gmem_arsize),
  .axiARCache   (m_axi_gmem_arcache),

  .axiRValid    (m_axi_gmem_rvalid),
  .axiRReady    (m_axi_gmem_rready),
  .axiRId       (m_axi_gmem_rid),
  .axiRData     (m_axi_gmem_rdata),
  .axiRResp     (m_axi_gmem_rresp),
  .axiRLast     (m_axi_gmem_rlast),

  // Connect active AXI write data bus signals.
  .axiAWValid   (m_axi_gmem_awvalid),
  .axiAWReady   (m_axi_gmem_awready),
  .axiAWId      (m_axi_gmem_awid),
  .axiAWAddr    (m_axi_gmem_awaddr),
  .axiAWLen     (m_axi_gmem_awlen),
  .axiAWSize    (m_axi_gmem_awsize),
  .axiAWCache   (m_axi_gmem_awcache),

  .axiWValid    (m_axi_gmem_wvalid),
  .axiWReady    (m_axi_gmem_wready),
  .axiWId       (m_axi_gmem_wid),
  .axiWData     (m_axi_gmem_wdata),
  .axiWStrb     (m_axi_gmem_wstrb),
  .axiWLast     (m_axi_gmem_wlast),

  .axiBValid    (m_axi_gmem_bvalid),
  .axiBReady    (m_axi_gmem_bready),
  .axiBId       (m_axi_gmem_bid),
  .axiBResp     (m_axi_gmem_bresp),

  // Connect system level signals.
  .axiReset     (reset),  // TODO: This should be passed in.
  .clk          (clk),
  .srst         (reset)
);

//
// Instantiate the memory access arbitration logic.
//
{{.ArbitrationModuleName}} memArbitrationTree (
{{template "smiMemBusConnectionPortLink" .SmiMemBusClientConns}}
{{template "smiMemBusConnectionPortLink" .SmiMemBusServerConn}}

  // Connect system level signals.
  .clk  (clk),
  .srst (reset)
);

//
// Map SMI flit vector signals.
// {{range .SmiMemBusClientConns}}
assign {{.SmiNetReqName}}Data  = {{.SmiNetReqName}}Flit [63:0];
assign {{.SmiNetReqName}}Eofc  = {{.SmiNetReqName}}Flit [71:64];
assign {{.SmiNetRespName}}Flit = { {{.SmiNetRespName}}Eofc, {{.SmiNetRespName}}Data };
{{end}}
//
// Instantiate the SMI kernel logic. Uses positional signal assignment since
// the Go kernel parameter names may vary.
//
{{.KernelModuleName}} smiKernel (

  // Connect action control signals.
  go_ready,
  go_stop,
  done_ready,
  done_stop,

  // Connect configuration register file access signals.
  config_req_valid,
  config_req_data,
  config_req_stop,
  config_resp_valid,
  config_resp_data,
  config_resp_stop,

  // Kernel internal register access signals.
  control_req_valid,
  control_req_data,
  control_req_stop,
  control_resp_valid,
  control_resp_data,
  control_resp_stop,

  // Kernel interrupt queue signals.
  interrupt_valid,
  interrupt_data,
  interrupt_stop,
{{range $index, $element := .SmiMemBusClientConns}}
  // Connect SMI for {{$element.SmiNetReqName}}/{{$element.SmiNetRespName}}.
  {{$element.SmiNetReqName}}Ready,
  {{$element.SmiNetReqName}}Flit,
  {{$element.SmiNetReqName}}Stop,
  {{$element.SmiNetRespName}}Ready,
  {{$element.SmiNetRespName}}Flit,
  {{$element.SmiNetRespName}}Stop,
{{end}}
  // Connect system level signals.
  clk,
  reset
);

endmodule
{{end}}`

//
// Cache the parsed SMI SDAccel kernel adaptor template.
//
var smiFp1KernelAdaptorCache *template.Template = nil

//
// Implement lazy construction of the SMI SDAccel kernel adaptor template.
//
func getSmiFp1KernelAdaptorTemplate() *template.Template {
	if smiFp1KernelAdaptorCache == nil {
		templGroup := template.New("").Funcs(smiTemplateFunctions)
		templGroup = template.Must(templGroup.Parse(smiMemBusFileHeaderTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionPortLinkTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionWireListTemplate))
		templGroup = template.Must(templGroup.Parse(smiFp1KernelAdaptorTemplate))
		smiFp1KernelAdaptorCache = templGroup
	}
	return smiFp1KernelAdaptorCache
}

//
// Generates an SMI SDaccel kernel adaptor configuration given the supplied
// parameters.
//
func configureSmiFp1KernelAdaptor(moduleName string, kernelName string,
	numPorts uint, scalingFactor uint) (smiFp1KernelAdaptorConfig, error) {

	var smiFp1KernelAdaptor = smiFp1KernelAdaptorConfig{}
	smiFp1KernelAdaptor.ModuleName = moduleName
	smiFp1KernelAdaptor.KernelModuleName = kernelName
	smiFp1KernelAdaptor.ArbitrationModuleName =
		fmt.Sprintf("smiMemArbitrationTreeX%dS%d", numPorts, scalingFactor)
	smiFp1KernelAdaptor.AxiBusDataWidth = scalingFactor * 8
	smiFp1KernelAdaptor.AxiBusIdWidth = 1

	smiFp1KernelAdaptor.AxiByteIndexSize = 2
	for i := scalingFactor; i != 0; i = i >> 1 {
		smiFp1KernelAdaptor.AxiByteIndexSize += 1
	}

	// Add the common connection signals.
	smiFp1KernelAdaptor.SmiMemBusClientConns = make([]smiMemBusConnectionConfig, 0)
	smiFp1KernelAdaptor.SmiMemBusServerConn = make([]smiMemBusConnectionConfig, 1)
	smiFp1KernelAdaptor.SmiMemBusWireConns = make([]smiMemBusConnectionConfig, 1)
	serverConn := smiMemBusConnectionConfig{
		"smiMemServerReq", "smiMemServerResp", scalingFactor * 8}
	smiFp1KernelAdaptor.SmiMemBusServerConn[0] = serverConn
	smiFp1KernelAdaptor.SmiMemBusWireConns[0] = serverConn

	// Add the variable number of internal SMI port connections.
	for i := uint(0); i < numPorts; i++ {
		clientConn := smiMemBusConnectionConfig{
			fmt.Sprintf("smiMemClientReq%d", i),
			fmt.Sprintf("smiMemClientResp%d", i), 8}
		smiFp1KernelAdaptor.SmiMemBusClientConns = append(
			smiFp1KernelAdaptor.SmiMemBusClientConns, clientConn)
		smiFp1KernelAdaptor.SmiMemBusWireConns = append(
			smiFp1KernelAdaptor.SmiMemBusWireConns, clientConn)
	}

	return smiFp1KernelAdaptor, nil
}

//
// Execute the template using the supplied output file handle and configuration.
//
func executeSmiFp1KernelAdaptorTemplate(outFile *os.File, config smiFp1KernelAdaptorConfig) error {
	return getSmiFp1KernelAdaptorTemplate().ExecuteTemplate(
		outFile, "smiFp1KernelAdaptor", config)
}
