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

	// We pass a single parameter which is the number of SMI endpoints to
	// generate code for.
	numMemPortsPtr := flag.Uint("numMemPorts", 1, "the number of SMI memory ports")
	flag.Parse()

	// Build the arbitration component with the specified number of ports.
	moduleName := fmt.Sprintf("smiMemArbitrationTreeX%d", *numMemPortsPtr)
	fileName := "smi_mem_arbitration_tree.v"
	err := smiMemTemplates.CreateArbitrationTree(fileName, moduleName, *numMemPortsPtr)
	if err != nil {
		panic(err)
	}

	// Build the wrapper component with the specified number of ports.
	moduleName = "teak__action__top__gmem"
	fileName = "teak_action_wrapper.v"
	err = smiMemTemplates.CreateSmiSdaKernelAdaptor(fileName, moduleName, *numMemPortsPtr)
	if err != nil {
		panic(err)
	}
}
