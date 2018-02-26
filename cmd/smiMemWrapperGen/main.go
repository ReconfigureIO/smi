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

package main

import (
	"flag"
	"fmt"
	"github.com/ReconfigureIO/smi/go-template/src/smiMemTemplates"
)

func main() {

	// We pass two parameters. One is the number of SMI endpoints to
	// generate code for, the other is the data bus scaling factor.
	numMemPortsPtr := flag.Uint("numMemPorts", 1, "the number of SMI memory ports")
	scalingFactorPtr := flag.Uint("scalingFactor", 1, "the bus width scaling factor (1, 2, 4 or 8)")
	flag.Parse()

	// Build the arbitration component with the specified number of ports.
	moduleName := fmt.Sprintf("smiMemArbitrationTreeX%dS%d", *numMemPortsPtr, *scalingFactorPtr)
	fileName := fmt.Sprintf("%s.v", moduleName)
	err := smiMemTemplates.CreateArbitrationTree(
		fileName, moduleName, *numMemPortsPtr, *scalingFactorPtr)
	if err != nil {
		panic(err)
	}

	// Build the wrapper component with the specified number of ports.
	moduleName = "teak__action__top__gmem"
	fileName = fmt.Sprintf("%s.v", moduleName)
	err = smiMemTemplates.CreateSmiSdaKernelAdaptor(
		fileName, moduleName, *numMemPortsPtr, *scalingFactorPtr)
	if err != nil {
		panic(err)
	}
}
