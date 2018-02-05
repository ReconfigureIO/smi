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
	SmiMemBusWidthScalers []smiMemBusWidthScalerConfig // List of bus scaler components.
	SmiMemBusArbiters     []smiMemBusArbiterConfig     // List of bus scaler components.
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
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionPortLinkTemplate))
		templGroup = template.Must(templGroup.Parse(smiMemBusConnectionWireListTemplate))
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
func configureArbitrationTree(moduleName string, numClients uint) (arbitrationTreeConfig, error) {
	var arbitrationTree = arbitrationTreeConfig{}
	arbitrationTree.ModuleName = moduleName

	if numClients < 1 {
		// Zero client arbitration trees are not supported!
		return arbitrationTree, errors.New(fmt.Sprintf(
			"Invalid number of SMI clients (%d) for arbitration tree", numClients))

	} else if numClients == 1 {
		// For a single client, just implement scaling from the inputs to outputs.
		clientConn := smiMemBusConnectionConfig{"smiMemClientReq", "smiMemClientResp", 8}
		serverConn := smiMemBusConnectionConfig{"smiMemServerReq", "smiMemServerResp", 64}
		arbitrationTree.SmiMemBusClientConns = []smiMemBusConnectionConfig{clientConn}
		arbitrationTree.SmiMemBusServerConn = []smiMemBusConnectionConfig{serverConn}
		arbitrationTree.SmiMemBusWidthScalers = []smiMemBusWidthScalerConfig{
			{"busWidthScaler", 8, 8, clientConn, serverConn}}

	} else if numClients <= 3 {
		// For two to three clients, implement single scaling arbiter with
		// additional scaling on the client side. Start by building the
		// client side connections and bus width scalers.
		arbitrationTree.SmiMemBusClientConns = make([]smiMemBusConnectionConfig, numClients)
		arbitrationTree.SmiMemBusWireConns = make([]smiMemBusConnectionConfig, numClients)
		arbitrationTree.SmiMemBusWidthScalers = make([]smiMemBusWidthScalerConfig, numClients)
		for i := uint(0); i < numClients; i++ {
			clientConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiMemClientReq%02d", i),
				fmt.Sprintf("smiMemClientResp%02d", i), 8}
			wireConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiMemScaledReq%02d", i),
				fmt.Sprintf("smiMemScaledResp%02d", i), 32}
			arbitrationTree.SmiMemBusClientConns[i] = clientConn
			arbitrationTree.SmiMemBusWireConns[i] = wireConn
			arbitrationTree.SmiMemBusWidthScalers[i] = smiMemBusWidthScalerConfig{
				fmt.Sprintf("busWidthScaler%02d", i), 4, 8,
				clientConn, wireConn}
		}

		// Add the server side connection and arbiter component.
		serverConn := smiMemBusConnectionConfig{
			"smiMemServerReq", "smiMemServerResp", 64}
		arbitrationTree.SmiMemBusArbiters = []smiMemBusArbiterConfig{
			{"busArbiter", 32, 4, 32, 4, true, arbitrationTree.SmiMemBusWireConns, serverConn}}
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

		// Add the main arbitration component.
		serverConn := smiMemBusConnectionConfig{
			"smiMemServerReq", "smiMemServerResp", 64}
		busWireConns := make([]smiMemBusConnectionConfig, fanInLayer0)
		arbitrationTree.SmiMemBusWireConns = make([]smiMemBusConnectionConfig, fanInLayer0)
		for i := uint(0); i < fanInLayer0; i++ {
			busWireConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiWireReqL0I%d", i), fmt.Sprintf("smiWireRespL0I%d", i), 32}
			busWireConns[i] = busWireConn
			arbitrationTree.SmiMemBusWireConns[i] = busWireConn
		}
		arbitrationTree.SmiMemBusArbiters = make([]smiMemBusArbiterConfig, 1)
		arbitrationTree.SmiMemBusArbiters[0] = smiMemBusArbiterConfig{
			"busArbiterL0I0", 32, 4, 32, 4, true, busWireConns, serverConn}
		arbitrationTree.SmiMemBusServerConn = []smiMemBusConnectionConfig{serverConn}

		// Add the second layer of arbiters.
		for i := uint(0); i < fanInLayer0; i++ {
			busWireConns := make([]smiMemBusConnectionConfig, fanInLayer1)
			for j := uint(0); j < fanInLayer1; j++ {
				busWireConns[j] = smiMemBusConnectionConfig{
					fmt.Sprintf("smiWireReqL1I%d", i*fanInLayer1+j),
					fmt.Sprintf("smiWireRespL1I%d", i*fanInLayer1+j), 16}
			}
			serverSideConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiWireReqL0I%d", i),
				fmt.Sprintf("smiWireRespL0I%d", i), 32}
			busArbiter := smiMemBusArbiterConfig{
				fmt.Sprintf("busArbiterL1I%d", i), 32, 4, 16, 4,
				true, busWireConns, serverSideConn}
			arbitrationTree.SmiMemBusArbiters = append(
				arbitrationTree.SmiMemBusArbiters, busArbiter)
			arbitrationTree.SmiMemBusWireConns = append(
				arbitrationTree.SmiMemBusWireConns, busWireConns...)
		}

		// Add the third layer of arbiters or bus width scalers.
		clientIndex := uint(0)
		arbitrationTree.SmiMemBusClientConns = make([]smiMemBusConnectionConfig, 0)
		arbitrationTree.SmiMemBusWidthScalers = make([]smiMemBusWidthScalerConfig, 0)
		for i := uint(0); i < numServers; i++ {
			serverSideConn := smiMemBusConnectionConfig{
				fmt.Sprintf("smiWireReqL1I%d", i),
				fmt.Sprintf("smiWireRespL1I%d", i), 16}
			if fanInsLayer2[i] == 1 {
				clientSideConn := smiMemBusConnectionConfig{
					fmt.Sprintf("smiMemClientReq%02d", clientIndex),
					fmt.Sprintf("smiMemClientResp%02d", clientIndex), 8}
				busWidthScaler := smiMemBusWidthScalerConfig{
					fmt.Sprintf("busWidthScalerL2I%d", i), 2, 8,
					clientSideConn, serverSideConn}
				arbitrationTree.SmiMemBusWidthScalers = append(
					arbitrationTree.SmiMemBusWidthScalers, busWidthScaler)
				arbitrationTree.SmiMemBusClientConns = append(
					arbitrationTree.SmiMemBusClientConns, clientSideConn)
			} else {
				clientSideConns := make([]smiMemBusConnectionConfig, fanInsLayer2[i])
				for j := uint(0); j < fanInsLayer2[i]; j++ {
					clientSideConns[j] = smiMemBusConnectionConfig{
						fmt.Sprintf("smiMemClientReq%02d", clientIndex+j),
						fmt.Sprintf("smiMemClientResp%02d", clientIndex+j), 8}
				}
				busArbiter := smiMemBusArbiterConfig{
					fmt.Sprintf("busArbiterL2I%d", i), 32, 4, 8, 4,
					true, clientSideConns, serverSideConn}
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
