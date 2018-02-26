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

//
// Defines the template configuration options for a single SMI memory bus
// connection, consisting of an SMI request and SMI response connection.
//
type smiMemBusConnectionConfig struct {
	SmiNetReqName      string // Name of SMI request connections between entities.
	SmiNetRespName     string // Name of SMI request connections between entities.
	SmiMemBusFlitWidth uint   // Number of bytes in each SMI flit.
}

//
// Defines the template configuration options for a direct assignment between
// SMI memory bus signals.
//
type smiMemBusAssignmentConfig struct {
	SmiMemBusClientConn smiMemBusConnectionConfig // Single client side connections.
	SmiMemBusServerConn smiMemBusConnectionConfig // Single server side connection.
}

//
// Defines the template configuration options for an SMI memory bus scaler
// assembly.
//
type smiMemBusWidthScalerConfig struct {
	InstanceName         string                    // Base name of the bus width scaler instances.
	SmiMemBusScaleFactor uint                      // Bus width scaling factor.
	SmiMemBusFlitWidth   uint                      // Number of bytes in each 'client side' SMI flit.
	SmiMemBusClientConn  smiMemBusConnectionConfig // Single client side connections.
	SmiMemBusServerConn  smiMemBusConnectionConfig // Single server side connection.
}

//
// Defines the template configuration options for an SMI memory bus arbitration
// component.
//
type smiMemBusArbiterConfig struct {
	InstanceName         string                      // Name of the arbitration instance.
	SmiFifoFlitDepth     uint                        // Depth of internal flit FIFOs.
	SmiFifoFrameDepth    uint                        // Maximum number of frames per FIFO.
	SmiMemBusFlitWidth   uint                        // Number of bytes in each 'client side' SMI flit.
	SmiMemBusTagIdWidth  uint                        // Number of bits used for ID tagging.
	SmiMemBusScaleWidth  bool                        // Indicates whether bus width scaling is to be used.
	SmiMemBusClientConns []smiMemBusConnectionConfig // List of client side connections.
	SmiMemBusServerConn  smiMemBusConnectionConfig   // Single server side connection.
}

//
// Defines the file header template to be used on generated files.
//
var smiMemBusFileHeaderTemplate = `
{{define "smiMemBusFileHeaderTemplate"}}//
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
// Machine generated file - DO NOT EDIT
//

` + "`timescale 1ns/1ps" + `
{{end}}`

//
// Defines the template for an array of external SMI memory upstream 'client'
// ports using the Verilog 2001 inline port syntax.
//
var smiMemBusConnectionClientPortTemplate = `
{{define "smiMemBusConnectionClientPort"}}{{if .}}{{range .}}
  // SMI ports for {{.SmiNetReqName}}/{{.SmiNetRespName}}
  input          {{.SmiNetReqName -}}Ready,
  input  [  7:0] {{.SmiNetReqName -}}Eofc,
  input  {{makeBitSliceFromScaledWidth .SmiMemBusFlitWidth 8}} {{.SmiNetReqName -}}Data,
  output         {{.SmiNetReqName -}}Stop,
  output         {{.SmiNetRespName -}}Ready,
  output [  7:0] {{.SmiNetRespName -}}Eofc,
  output {{makeBitSliceFromScaledWidth .SmiMemBusFlitWidth 8}} {{.SmiNetRespName -}}Data,
  input          {{.SmiNetRespName -}}Stop,
{{end}}{{end}}{{end}}`

//
// Defines the template for an array of external SMI memory downstream 'server'
// ports using the Verilog 2001 inline port syntax.
//
var smiMemBusConnectionServerPortTemplate = `
{{define "smiMemBusConnectionServerPort"}}{{if .}}{{range .}}
  // SMI ports for {{.SmiNetReqName}}/{{.SmiNetRespName}}
  output         {{.SmiNetReqName -}}Ready,
  output [  7:0] {{.SmiNetReqName -}}Eofc,
  output {{makeBitSliceFromScaledWidth .SmiMemBusFlitWidth 8}} {{.SmiNetReqName -}}Data,
  input          {{.SmiNetReqName -}}Stop,
  input          {{.SmiNetRespName -}}Ready,
  input  [  7:0] {{.SmiNetRespName -}}Eofc,
  input  {{makeBitSliceFromScaledWidth .SmiMemBusFlitWidth 8}} {{.SmiNetRespName -}}Data,
  output         {{.SmiNetRespName -}}Stop,
{{end}}{{end}}{{end}}`

//
// Defines the template for generating a list of internal connection wires for
// a given memory bus array.
//
var smiMemBusConnectionWireListTemplate = `
{{define "smiMemBusConnectionWireList"}}{{if .}}{{range .}}
// SMI connections for {{.SmiNetReqName}}/{{.SmiNetRespName}}
wire         {{.SmiNetReqName -}}Ready;
wire [  7:0] {{.SmiNetReqName -}}Eofc;
wire {{makeBitSliceFromScaledWidth .SmiMemBusFlitWidth 8}} {{.SmiNetReqName -}}Data;
wire         {{.SmiNetReqName -}}Stop;
wire         {{.SmiNetRespName -}}Ready;
wire [  7:0] {{.SmiNetRespName -}}Eofc;
wire {{makeBitSliceFromScaledWidth .SmiMemBusFlitWidth 8}} {{.SmiNetRespName -}}Data;
wire         {{.SmiNetRespName -}}Stop;
{{end}}{{end}}{{end}}`

//
// Defines the template for generating named port mappings for a given memory
// bus module connection array.
//
var smiMemBusConnectionPortLinkTemplate = `` +
	`{{define "smiReqBusConnectionPortLink"}}` +
	`.{{.SmiNetReqName -}}Ready ({{.SmiNetReqName -}}Ready),
  .{{.SmiNetReqName -}}Eofc  ({{.SmiNetReqName -}}Eofc),
  .{{.SmiNetReqName -}}Data  ({{.SmiNetReqName -}}Data),
  .{{.SmiNetReqName -}}Stop  ({{.SmiNetReqName -}}Stop),{{end}}` +
	`{{define "smiRespBusConnectionPortLink"}}` +
	`.{{.SmiNetRespName -}}Ready ({{.SmiNetRespName -}}Ready),
  .{{.SmiNetRespName -}}Eofc  ({{.SmiNetRespName -}}Eofc),
  .{{.SmiNetRespName -}}Data  ({{.SmiNetRespName -}}Data),
  .{{.SmiNetRespName -}}Stop  ({{.SmiNetRespName -}}Stop),{{end}}` +
	`{{define "smiMemBusConnectionPortLink"}}{{if .}}{{range .}}
  // SMI ports for {{.SmiNetReqName}}/{{.SmiNetRespName}}
  {{template "smiReqBusConnectionPortLink" .}}
  {{template "smiRespBusConnectionPortLink" .}}
{{end}}{{end}}{{end}}`

//
// Defines the template for implementing direct SMI memory bus assignments.
//
var smiMemBusAssignmentTemplate = `
{{define "smiMemBusAssignment"}}
// Directly map {{.SmiMemBusClientConn.SmiNetReqName}} -> {{.SmiMemBusServerConn.SmiNetReqName}}
assign {{.SmiMemBusServerConn.SmiNetReqName}}Ready = {{.SmiMemBusClientConn.SmiNetReqName}}Ready;
assign {{.SmiMemBusServerConn.SmiNetReqName}}Eofc = {{.SmiMemBusClientConn.SmiNetReqName}}Eofc;
assign {{.SmiMemBusServerConn.SmiNetReqName}}Data = {{.SmiMemBusClientConn.SmiNetReqName}}Data;
assign {{.SmiMemBusClientConn.SmiNetReqName}}Stop = {{.SmiMemBusServerConn.SmiNetReqName}}Stop;

// Directly map {{.SmiMemBusServerConn.SmiNetRespName}} -> {{.SmiMemBusClientConn.SmiNetRespName}}
assign {{.SmiMemBusClientConn.SmiNetRespName}}Ready = {{.SmiMemBusServerConn.SmiNetRespName}}Ready;
assign {{.SmiMemBusClientConn.SmiNetRespName}}Eofc = {{.SmiMemBusServerConn.SmiNetRespName}}Eofc;
assign {{.SmiMemBusClientConn.SmiNetRespName}}Data = {{.SmiMemBusServerConn.SmiNetRespName}}Data;
assign {{.SmiMemBusServerConn.SmiNetRespName}}Stop = {{.SmiMemBusClientConn.SmiNetRespName}}Stop;
{{end}}`

//
// Defines the template for instantiating SMI memory bus width scaling modules.
//
var smiMemBusWidthScalerTemplate = `
{{define "smiMemBusWidthScaler"}}
// Instantiate SMI request scaler {{.InstanceName}}Req
{{printf "smiFlitScaleX%d" .SmiMemBusScaleFactor}} #(` +
	`{{.SmiMemBusFlitWidth}}) {{.InstanceName}}Req (

  .smiInReady  ({{.SmiMemBusClientConn.SmiNetReqName}}Ready),
  .smiInEofc   ({{.SmiMemBusClientConn.SmiNetReqName}}Eofc),
  .smiInData   ({{.SmiMemBusClientConn.SmiNetReqName}}Data),
  .smiInStop   ({{.SmiMemBusClientConn.SmiNetReqName}}Stop),

  .smiOutReady ({{.SmiMemBusServerConn.SmiNetReqName}}Ready),
  .smiOutEofc  ({{.SmiMemBusServerConn.SmiNetReqName}}Eofc),
  .smiOutData  ({{.SmiMemBusServerConn.SmiNetReqName}}Data),
  .smiOutStop  ({{.SmiMemBusServerConn.SmiNetReqName}}Stop),

  .clk  (clk),
  .srst (srst)
);

// Instantiate SMI response scaler {{.InstanceName}}Resp
{{printf "smiFlitScaleD%d" .SmiMemBusScaleFactor}} #(` +
	`{{.SmiMemBusFlitWidth}}*{{.SmiMemBusScaleFactor}}) {{.InstanceName}}Resp (

  .smiInReady  ({{.SmiMemBusServerConn.SmiNetRespName}}Ready),
  .smiInEofc   ({{.SmiMemBusServerConn.SmiNetRespName}}Eofc),
  .smiInData   ({{.SmiMemBusServerConn.SmiNetRespName}}Data),
  .smiInStop   ({{.SmiMemBusServerConn.SmiNetRespName}}Stop),

  .smiOutReady ({{.SmiMemBusClientConn.SmiNetRespName}}Ready),
  .smiOutEofc  ({{.SmiMemBusClientConn.SmiNetRespName}}Eofc),
  .smiOutData  ({{.SmiMemBusClientConn.SmiNetRespName}}Data),
  .smiOutStop  ({{.SmiMemBusClientConn.SmiNetRespName}}Stop),

  .clk  (clk),
  .srst (srst)
);
{{end}}`

//
// Defines the template for instantiating a single SMI memory bus arbitration
// module.
//
var smiMemBusArbiterTemplate = `
{{define "smiMemBusArbiter"}}
// Instantiate transaction arbiter {{.InstanceName}}
{{if .SmiMemBusScaleWidth}}` +
	`{{len .SmiMemBusClientConns | printf "smiTransactionScaledArbiterX%d"}}` +
	`{{else}}` +
	`{{len .SmiMemBusClientConns | printf "smiTransactionArbiterX%d"}}` +
	`{{end}} #({{.SmiMemBusFlitWidth}}, {{.SmiMemBusTagIdWidth}}, ` +
	`{{.SmiFifoFlitDepth}}, {{.SmiFifoFrameDepth}}) {{.InstanceName}} (
  {{range $index, $element := .SmiMemBusClientConns}}
  {{makePortIdCharName ".smiReq%cInReady" $index}}   ({{$element.SmiNetReqName}}Ready),
  {{makePortIdCharName ".smiReq%cInEofc" $index}}    ({{$element.SmiNetReqName}}Eofc),
  {{makePortIdCharName ".smiReq%cInData" $index}}    ({{$element.SmiNetReqName}}Data),
  {{makePortIdCharName ".smiReq%cInStop" $index}}    ({{$element.SmiNetReqName}}Stop),
  {{makePortIdCharName ".smiResp%cOutReady" $index}} ({{$element.SmiNetRespName}}Ready),
  {{makePortIdCharName ".smiResp%cOutEofc" $index}}  ({{$element.SmiNetRespName}}Eofc),
  {{makePortIdCharName ".smiResp%cOutData" $index}}  ({{$element.SmiNetRespName}}Data),
  {{makePortIdCharName ".smiResp%cOutStop" $index}}  ({{$element.SmiNetRespName}}Stop),
  {{end}}
  .smiReqOutReady ({{.SmiMemBusServerConn.SmiNetReqName}}Ready),
  .smiReqOutEofc  ({{.SmiMemBusServerConn.SmiNetReqName}}Eofc),
  .smiReqOutData  ({{.SmiMemBusServerConn.SmiNetReqName}}Data),
  .smiReqOutStop  ({{.SmiMemBusServerConn.SmiNetReqName}}Stop),
  .smiRespInReady ({{.SmiMemBusServerConn.SmiNetRespName}}Ready),
  .smiRespInEofc  ({{.SmiMemBusServerConn.SmiNetRespName}}Eofc),
  .smiRespInData  ({{.SmiMemBusServerConn.SmiNetRespName}}Data),
  .smiRespInStop  ({{.SmiMemBusServerConn.SmiNetRespName}}Stop),

  .clk  (clk),
  .srst (srst)
);
{{end}}`
