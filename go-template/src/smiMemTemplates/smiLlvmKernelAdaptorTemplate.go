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
// Defines the template configuration options for a common SMI LLVM kernel
// adaptor module.
//
type smiLlvmKernelAdaptorConfig struct {
	ModuleName            string                      // Name of the kernel adaptor module.
	ArbitrationModuleName string                      // Name of the arbitration tree module.
	KernelModuleName      string                      // Name of the SMI kernel module.
	AxiByteIndexSize      uint                        // Size of AXI data byte index values.
	AxiBusDataWidth       uint                        // Width of AXI data bus in bytes.
	AxiBusIdWidth         uint                        // Width of AXI ID signal.
	KernelArgsWidth       uint                        // Number of 32-bit kernel arguments.
	SmiMemBusClientConns  []smiMemBusConnectionConfig // List of client side connections.
	SmiMemBusServerConn   []smiMemBusConnectionConfig // Single server side connection.
	SmiMemBusWireConns    []smiMemBusConnectionConfig // Internal wire connections.
}

//
// Defines the template for instantiating a common SMI LLVM kernel adaptor
// module.
//
var smiLlvmKernelAdaptorTemplate = `
{{define "smiLlvmKernelAdaptor"}}{{template "smiMemBusFileHeaderTemplate" . }}
module {{.ModuleName}} (

  // Kernel control signals.
  input          argsReady,
  input  {{makeBitSliceFromScaledWidth .KernelArgsWidth 32}} argsData,
  output         argsStop,
  output         retValReady,
  input          retValStop,

  // Specifies the AXI master write address signals.
  output [ 63:0] m_axi_gmem_awaddr,
  output [  7:0] m_axi_gmem_awlen,
  output [  2:0] m_axi_gmem_awsize,
  output [  1:0] m_axi_gmem_awburst,
  output         m_axi_gmem_awlock,
  output [  3:0] m_axi_gmem_awcache,
  output [  2:0] m_axi_gmem_awprot,
  output [  3:0] m_axi_gmem_awqos,
  output [  3:0] m_axi_gmem_awregion,
  output [  0:0] m_axi_gmem_awuser,
  output {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_awid,
  output         m_axi_gmem_awvalid,
  input          m_axi_gmem_awready,

  // Specifies the AXI master write data signals.
  output {{makeBitSliceFromScaledWidth .AxiBusDataWidth 8}} m_axi_gmem_wdata,
  output {{makeBitSliceFromScaledWidth .AxiBusDataWidth 1}} m_axi_gmem_wstrb,
  output {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_wid,
  output         m_axi_gmem_wlast,
  output [  0:0] m_axi_gmem_wuser,
  output         m_axi_gmem_wvalid,
  input          m_axi_gmem_wready,

  // Specifies the AXI master write response signals.
  input  [  1:0] m_axi_gmem_bresp,
  input  [  0:0] m_axi_gmem_buser,
  input  {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_bid,
  input          m_axi_gmem_bvalid,
  output         m_axi_gmem_bready,

  // Specifies the AXI master read address signals.
  output [ 63:0] m_axi_gmem_araddr,
  output [  7:0] m_axi_gmem_arlen,
  output [  2:0] m_axi_gmem_arsize,
  output [  1:0] m_axi_gmem_arburst,
  output         m_axi_gmem_arlock,
  output [  3:0] m_axi_gmem_arcache,
  output [  2:0] m_axi_gmem_arprot,
  output [  3:0] m_axi_gmem_arqos,
  output [  3:0] m_axi_gmem_arregion,
  output [  0:0] m_axi_gmem_aruser,
  output {{makeBitSliceFromScaledWidth .AxiBusIdWidth 1}} m_axi_gmem_arid,
  output         m_axi_gmem_arvalid,
  input          m_axi_gmem_arready,

  // Specifies the AXI master read data signals.
  input  {{makeBitSliceFromScaledWidth .AxiBusDataWidth 8}} m_axi_gmem_rdata,
  input  [  1:0] m_axi_gmem_rresp,
  input          m_axi_gmem_rlast,
  input  [  0:0] m_axi_gmem_ruser,
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
// Tie off static AXI signals.
//
assign m_axi_gmem_arburst  = 2'b01;
assign m_axi_gmem_arlock   = 1'b0;
assign m_axi_gmem_arprot   = 3'b000;
assign m_axi_gmem_arqos    = 4'b0000;
assign m_axi_gmem_arregion = 4'b0000;
assign m_axi_gmem_aruser   = 1'b0;

assign m_axi_gmem_awburst  = 2'b01;
assign m_axi_gmem_awlock   = 1'b0;
assign m_axi_gmem_awprot   = 3'b000;
assign m_axi_gmem_awqos    = 4'b0000;
assign m_axi_gmem_awregion = 4'b0000;
assign m_axi_gmem_awuser   = 1'b0;
assign m_axi_gmem_wuser    = 1'b0;

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
// Instantiate the SMI kernel logic.
//
{{.KernelModuleName}} smiKernel (

  // Connect kernel control signals.
  .args0_0Ready   (argsReady),
` + "`ifdef KERNEL_ARGS_DATA" + `
  .args0_0Data    (argsData),
` + "`endif" + `
  .args0_0Stop    (argsStop),
  .retVal1_0Ready (retValReady),
  .retVal1_0Stop  (retValStop),
{{range $index, $element := .SmiMemBusClientConns}}
  // Connect SMI for {{$element.SmiNetReqName}}/{{$element.SmiNetRespName}}.
  {{makePortIdIndexName ".request%d_0Ready " $index 2 2}} ({{$element.SmiNetReqName}}Ready),
  {{makePortIdIndexName ".request%d_0Data  " $index 2 2}} ({{$element.SmiNetReqName}}Flit),
  {{makePortIdIndexName ".request%d_0Stop  " $index 2 2}} ({{$element.SmiNetReqName}}Stop),
  {{makePortIdIndexName ".response%d_0Ready" $index 3 2}} ({{$element.SmiNetRespName}}Ready),
  {{makePortIdIndexName ".response%d_0Data " $index 3 2}} ({{$element.SmiNetRespName}}Flit),
  {{makePortIdIndexName ".response%d_0Stop " $index 3 2}} ({{$element.SmiNetRespName}}Stop),
{{end}}
  // Connect system level signals.
  .clk   (clk),
  .reset (reset)
);

endmodule
{{end}}`

//
// Cache the parsed SMI LLVM kernel adaptor template.
//
var smiLlvmKernelAdaptorCache *template.Template = nil

//
// Implement lazy construction of the SMI LLVM kernel adaptor template.
//
func getSmiLlvmKernelAdaptorTemplate() *template.Template {
	if smiLlvmKernelAdaptorCache == nil {
		templGroup := template.New("").Funcs(smiTemplateFunctions)
		templGroup = template.Must(templGroup.Parse(smiMemBusFileHeaderTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionPortLinkTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionWireListTemplate))
		templGroup = template.Must(templGroup.Parse(smiLlvmKernelAdaptorTemplate))
		smiLlvmKernelAdaptorCache = templGroup
	}
	return smiLlvmKernelAdaptorCache
}

//
// Generates a common SMI LLVM kernel adaptor configuration given the supplied
// parameters.
//
func configureSmiLlvmKernelAdaptor(moduleName string, kernelName string,
	numPorts uint, scalingFactor uint, axiBusIdWidth uint,
	kernelArgsWidth uint) (smiLlvmKernelAdaptorConfig, error) {

	var smiLlvmKernelAdaptor = smiLlvmKernelAdaptorConfig{}
	smiLlvmKernelAdaptor.ModuleName = moduleName
	smiLlvmKernelAdaptor.KernelModuleName = kernelName
	smiLlvmKernelAdaptor.ArbitrationModuleName =
		fmt.Sprintf("smiMemArbitrationTreeX%dS%d", numPorts, scalingFactor)
	smiLlvmKernelAdaptor.AxiBusDataWidth = scalingFactor * 8
	smiLlvmKernelAdaptor.AxiBusIdWidth = axiBusIdWidth
	smiLlvmKernelAdaptor.KernelArgsWidth = kernelArgsWidth

	smiLlvmKernelAdaptor.AxiByteIndexSize = 2
	for i := scalingFactor; i != 0; i = i >> 1 {
		smiLlvmKernelAdaptor.AxiByteIndexSize += 1
	}

	// Add the common connection signals.
	smiLlvmKernelAdaptor.SmiMemBusClientConns = make([]smiMemBusConnectionConfig, 0)
	smiLlvmKernelAdaptor.SmiMemBusServerConn = make([]smiMemBusConnectionConfig, 1)
	smiLlvmKernelAdaptor.SmiMemBusWireConns = make([]smiMemBusConnectionConfig, 1)
	serverConn := smiMemBusConnectionConfig{
		"smiMemServerReq", "smiMemServerResp", scalingFactor * 8}
	smiLlvmKernelAdaptor.SmiMemBusServerConn[0] = serverConn
	smiLlvmKernelAdaptor.SmiMemBusWireConns[0] = serverConn

	// Add the variable number of internal SMI port connections.
	for i := uint(0); i < numPorts; i++ {
		clientConn := smiMemBusConnectionConfig{
			fmt.Sprintf("smiMemClientReq%d", i),
			fmt.Sprintf("smiMemClientResp%d", i), 8}
		smiLlvmKernelAdaptor.SmiMemBusClientConns = append(
			smiLlvmKernelAdaptor.SmiMemBusClientConns, clientConn)
		smiLlvmKernelAdaptor.SmiMemBusWireConns = append(
			smiLlvmKernelAdaptor.SmiMemBusWireConns, clientConn)
	}

	return smiLlvmKernelAdaptor, nil
}

//
// Execute the template using the supplied output file handle and configuration.
//
func executeSmiLlvmKernelAdaptorTemplate(outFile *os.File,
	config smiLlvmKernelAdaptorConfig) error {

	return getSmiLlvmKernelAdaptorTemplate().ExecuteTemplate(
		outFile, "smiLlvmKernelAdaptor", config)
}
