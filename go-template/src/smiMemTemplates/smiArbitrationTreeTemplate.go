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
	"errors"
	"fmt"
	"math"
	"os"
	"text/template"
)

//
// Defines the template configuration options for an SMI memory bus arbitration
// tree module.
//
type arbitrationTreeConfig struct {
	ModuleName            string                       // Name of the arbitration tree module.
	SmiMemBusClientConns  []smiMemBusConnectionConfig  // List of client side connections.
	SmiMemBusServerConn   []smiMemBusConnectionConfig  // Single server side connection.
	SmiMemBusWireConns    []smiMemBusConnectionConfig  // Internal wire connections.
	SmiMemBusAssignments  []smiMemBusAssignmentConfig  // List of direct bus assignments.
	SmiMemBusWidthScalers []smiMemBusWidthScalerConfig // List of bus scaler components.
	SmiMemBusArbiters     []smiMemBusArbiterConfig     // List of bus arbiter components.
}

//
// Defines the template for instantiating an arbitration tree.
//
var smiMemBusArbitrationTreeTemplate = `
{{define "smiMemBusArbitrationTree"}}{{template "smiMemBusFileHeaderTemplate" . }}
module {{.ModuleName}} (
  {{template "smiMemBusConnectionClientPort" .SmiMemBusClientConns}}
  {{template "smiMemBusConnectionServerPort" .SmiMemBusServerConn}}

  // Specify system level signals.
  input clk,
  input srst
);
  {{template "smiMemBusConnectionWireList" .SmiMemBusWireConns}}
  {{range .SmiMemBusAssignments}}{{template "smiMemBusAssignment" .}}{{end}}
  {{range .SmiMemBusWidthScalers}}{{template "smiMemBusWidthScaler" .}}{{end}}
  {{range .SmiMemBusArbiters}}{{template "smiMemBusArbiter" .}}{{end}}
endmodule
{{end}}`

//
// Cache the parsed arbitration tree template.
//
var smiMemBusArbitrationTreeCache *template.Template = nil

//
// Implement lazy construction of the arbitration tree template.
//
func getArbitrationTreeTemplate() *template.Template {
	if smiMemBusArbitrationTreeCache == nil {
		templGroup := template.New("").Funcs(smiTemplateFunctions)
		templGroup = template.Must(templGroup.Parse(smiMemBusFileHeaderTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionClientPortTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionServerPortTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionWireListTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusAssignmentTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusArbiterTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusWidthScalerTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusArbitrationTreeTemplate))
		smiMemBusArbitrationTreeCache = templGroup
	}
	return smiMemBusArbitrationTreeCache
}

//
// Generates an arbitration tree configuration given the supplied parameters.
//
func configureArbitrationTree(moduleName string, numClients uint,
	scalingFactor uint) (arbitrationTreeConfig, error) {

	var arbitrationTree = arbitrationTreeConfig{}
	arbitrationTree.ModuleName = moduleName

	if numClients < 1 {
		// Zero client arbitration trees are not supported!
		return arbitrationTree, errors.New(fmt.Sprintf(
			"Invalid number of SMI clients (%d) for arbitration tree", numClients))

	} else if numClients == 1 {
		// For a single client, just implement scaling from the inputs to outputs.
		clientConn := smiMemBusConnectionConfig{"smiMemClientReq0", "smiMemClientResp0", 8}
		serverConn := smiMemBusConnectionConfig{"smiMemServerReq", "smiMemServerResp", scalingFactor * 8}
		arbitrationTree.SmiMemBusClientConns = []smiMemBusConnectionConfig{clientConn}
		arbitrationTree.SmiMemBusServerConn = []smiMemBusConnectionConfig{serverConn}
		if scalingFactor > 1 {
			arbitrationTree.SmiMemBusWidthScalers = []smiMemBusWidthScalerConfig{
				{"busWidthScaler", scalingFactor, 8, clientConn, serverConn}}
		} else {
			arbitrationTree.SmiMemBusAssignments = []smiMemBusAssignmentConfig{
				{clientConn, serverConn}}
		}

	} else if numClients <= 3 {
		// For two to three clients, implement single arbiter with scaling on the
		// client side. Start by building the client side connections and bus width scalers.
		arbitrationTree.SmiMemBusClientConns = make([]smiMemBusConnectionConfig, numClients)
		arbitrationTree.SmiMemBusWireConns = make([]smiMemBusConnectionConfig, numClients)
		if scalingFactor > 1 {
			arbitrationTree.SmiMemBusWidthScalers = make([]smiMemBusWidthScalerConfig, numClients)
		} else {
			arbitrationTree.SmiMemBusAssignments = make([]smiMemBusAssignmentConfig, numClients)
		}
		for i := uint(0); i < numClients; i++ {
			clientConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiMemClientReq%d", i),
				fmt.Sprintf("smiMemClientResp%d", i), 8}
			wireConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiMemScaledReq%d", i),
				fmt.Sprintf("smiMemScaledResp%d", i), scalingFactor * 8}
			arbitrationTree.SmiMemBusClientConns[i] = clientConn
			arbitrationTree.SmiMemBusWireConns[i] = wireConn
			if scalingFactor > 1 {
				arbitrationTree.SmiMemBusWidthScalers[i] = smiMemBusWidthScalerConfig{
					fmt.Sprintf("busWidthScaler%d", i), scalingFactor, 8, clientConn, wireConn}
			} else {
				arbitrationTree.SmiMemBusAssignments[i] = smiMemBusAssignmentConfig{
					clientConn, wireConn}
			}
		}

		// Add the server side connection and arbiter component.
		serverConn := smiMemBusConnectionConfig{
			"smiMemServerReq", "smiMemServerResp", scalingFactor * 8}
		arbitrationTree.SmiMemBusArbiters = []smiMemBusArbiterConfig{
			{"busArbiter", 32, 4, scalingFactor * 8, 4, false,
				arbitrationTree.SmiMemBusWireConns, serverConn}}
		arbitrationTree.SmiMemBusServerConn = []smiMemBusConnectionConfig{serverConn}

	} else if numClients <= 64 {
		// For up to 64 clients, use a three layer tree with scaling arbiters
		// on all layers. Start by determining the various arbitration fan ins.
		averageFanIn := math.Cbrt(float64(numClients))
		fanInLayer0 := uint(math.Ceil(averageFanIn))
		fmt.Printf("  fanInLayer0 = %d (avg %f)\n", fanInLayer0, averageFanIn)

		averageFanIn = math.Sqrt(float64(numClients) / float64(fanInLayer0))
		fanInLayer1 := uint(math.Ceil(averageFanIn))
		fmt.Printf("  fanInLayer1 = %d (avg %f)\n", fanInLayer1, averageFanIn)

		numServers := fanInLayer0 * fanInLayer1
		averageFanIn = float64(numClients) / float64(numServers)
		fanInLayer2 := uint(math.Ceil(averageFanIn))
		fmt.Printf("  fanInLayer2 = %d (avg %f)\n", fanInLayer2, averageFanIn)

		fanInsLayer2 := make([]uint, numServers)
		fmt.Printf("  fanInsLayer2 = [")
		remainingClients := numClients
		for i := uint(0); i < numServers; i++ {
			fanInsLayer2[i] = fanInLayer2
			fmt.Printf(" %d", fanInLayer2)
			remainingClients -= fanInLayer2
			if remainingClients <= (numServers-i-1)*(fanInLayer2-1) {
				fanInLayer2--
			}
		}
		fmt.Printf(" ]\n")

		// Determine bus scaling parameters.
		flitWidthLayer0 := uint(32)
		doScalingLayer0 := true
		if scalingFactor < 8 {
			flitWidthLayer0 = scalingFactor * 8
			doScalingLayer0 = false
		}
		flitWidthLayer1 := uint(16)
		doScalingLayer1 := true
		if scalingFactor < 4 {
			flitWidthLayer1 = scalingFactor * 8
			doScalingLayer1 = false
		}
		doScalingLayer2 := true
		if scalingFactor < 2 {
			doScalingLayer2 = false
		}

		// Add the main arbitration component.
		serverConn := smiMemBusConnectionConfig{
			"smiMemServerReq", "smiMemServerResp", scalingFactor * 8}
		busWireConns := make([]smiMemBusConnectionConfig, fanInLayer0)
		arbitrationTree.SmiMemBusWireConns = make([]smiMemBusConnectionConfig, fanInLayer0)
		for i := uint(0); i < fanInLayer0; i++ {
			busWireConn := smiMemBusConnectionConfig{fmt.Sprintf("smiWireReqL0I%d", i),
				fmt.Sprintf("smiWireRespL0I%d", i), flitWidthLayer0}
			busWireConns[i] = busWireConn
			arbitrationTree.SmiMemBusWireConns[i] = busWireConn
		}
		arbitrationTree.SmiMemBusArbiters = make([]smiMemBusArbiterConfig, 1)
		arbitrationTree.SmiMemBusArbiters[0] = smiMemBusArbiterConfig{
			"busArbiterL0I0", 32, 4, flitWidthLayer0, 4, doScalingLayer0,
			busWireConns, serverConn}
		arbitrationTree.SmiMemBusServerConn = []smiMemBusConnectionConfig{serverConn}

		// Add the second layer of arbiters.
		for i := uint(0); i < fanInLayer0; i++ {
			busWireConns := make([]smiMemBusConnectionConfig, fanInLayer1)
			for j := uint(0); j < fanInLayer1; j++ {
				busWireConns[j] = smiMemBusConnectionConfig{
					fmt.Sprintf("smiWireReqL1I%d", i*fanInLayer1+j),
					fmt.Sprintf("smiWireRespL1I%d", i*fanInLayer1+j), flitWidthLayer1}
			}
			serverSideConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiWireReqL0I%d", i),
				fmt.Sprintf("smiWireRespL0I%d", i), flitWidthLayer0}
			busArbiter := smiMemBusArbiterConfig{
				fmt.Sprintf("busArbiterL1I%d", i), 32, 4, flitWidthLayer1, 4,
				doScalingLayer1, busWireConns, serverSideConn}
			arbitrationTree.SmiMemBusArbiters = append(
				arbitrationTree.SmiMemBusArbiters, busArbiter)
			arbitrationTree.SmiMemBusWireConns = append(
				arbitrationTree.SmiMemBusWireConns, busWireConns...)
		}

		// Add the third layer of arbiters or bus width scalers.
		clientIndex := uint(0)
		arbitrationTree.SmiMemBusClientConns = make([]smiMemBusConnectionConfig, 0)
		arbitrationTree.SmiMemBusWidthScalers = make([]smiMemBusWidthScalerConfig, 0)
		arbitrationTree.SmiMemBusAssignments = make([]smiMemBusAssignmentConfig, 0)
		for i := uint(0); i < numServers; i++ {
			serverSideConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiWireReqL1I%d", i),
				fmt.Sprintf("smiWireRespL1I%d", i), flitWidthLayer1}
			if fanInsLayer2[i] == 1 {
				clientSideConn := smiMemBusConnectionConfig{
					fmt.Sprintf("smiMemClientReq%d", clientIndex),
					fmt.Sprintf("smiMemClientResp%d", clientIndex), 8}
				if doScalingLayer2 {
					busWidthScaler := smiMemBusWidthScalerConfig{
						fmt.Sprintf("busWidthScalerL2I%d", i), 2, 8,
						clientSideConn, serverSideConn}
					arbitrationTree.SmiMemBusWidthScalers = append(
						arbitrationTree.SmiMemBusWidthScalers, busWidthScaler)
				} else {
					busAssignment := smiMemBusAssignmentConfig{
						clientSideConn, serverSideConn}
					arbitrationTree.SmiMemBusAssignments = append(
						arbitrationTree.SmiMemBusAssignments, busAssignment)
				}
				arbitrationTree.SmiMemBusClientConns = append(
					arbitrationTree.SmiMemBusClientConns, clientSideConn)
			} else {
				clientSideConns := make([]smiMemBusConnectionConfig, fanInsLayer2[i])
				for j := uint(0); j < fanInsLayer2[i]; j++ {
					clientSideConns[j] = smiMemBusConnectionConfig{
						fmt.Sprintf("smiMemClientReq%d", clientIndex+j),
						fmt.Sprintf("smiMemClientResp%d", clientIndex+j), 8}
				}
				busArbiter := smiMemBusArbiterConfig{
					fmt.Sprintf("busArbiterL2I%d", i), 32, 4, 8, 4,
					doScalingLayer2, clientSideConns, serverSideConn}
				arbitrationTree.SmiMemBusArbiters = append(
					arbitrationTree.SmiMemBusArbiters, busArbiter)
				arbitrationTree.SmiMemBusClientConns = append(
					arbitrationTree.SmiMemBusClientConns, clientSideConns...)
			}
			clientIndex += fanInsLayer2[i]
		}
	} else {
		// Currently unsupported number of SMI memory clients.
		return arbitrationTree, errors.New(fmt.Sprintf(
			"Unsupported number of SMI clients (%d) for arbitration tree", numClients))
	}
	return arbitrationTree, nil
}

//
// Execute the template using the supplied output file handle and configuration.
//
func executeArbitrationTreeTemplate(outFile *os.File, config arbitrationTreeConfig) error {
	return getArbitrationTreeTemplate().ExecuteTemplate(
		outFile, "smiMemBusArbitrationTree", config)
}
