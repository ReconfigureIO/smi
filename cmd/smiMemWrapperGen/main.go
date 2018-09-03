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
	"errors"
	"flag"
	"fmt"
	"github.com/ReconfigureIO/smi/go-template/src/smiMemTemplates"
)

func main() {

	// We pass two parameters. One is the number of SMI endpoints to
	// generate code for, the other is the output AXI data bus width.
	numMemPortsPtr := flag.Uint("numMemPorts", 1,
		"the number of SMI memory ports")
	axiBusWidthPtr := flag.Uint("axiBusWidth", 64,
		"the width of the AXI data bus (64, 128, 256 or 512)")
	axiBusIdWidthPtr := flag.Uint("axiBusIdWidth", 1,
		"the width of the AXI ID bus")
	kernelArgsWidthPtr := flag.Uint("kernelArgsWidth", 1,
		"the number of 32-bit kernel argument words")
	targetPlatformPtr := flag.String("targetPlatform", "sdaccel",
		"the target platform ('sdaccel', 'llvm' or 'huawei-fp1')")
	flag.Parse()

	// Convert the AXI bus width the bus width scaling factor.
	scalingFactor := uint(0)
	switch *axiBusWidthPtr {
	case 64:
		scalingFactor = 1
	case 128:
		scalingFactor = 2
	case 256:
		scalingFactor = 4
	case 512:
		scalingFactor = 8
	default:
		panic(errors.New(fmt.Sprintf(
			"Invalid AXI bus width (%d) for kernel adaptor", *axiBusWidthPtr)))
	}

	// Build the arbitration component with the specified number of ports.
	moduleName := fmt.Sprintf("smiMemArbitrationTreeX%dS%d", *numMemPortsPtr, scalingFactor)
	fileName := fmt.Sprintf("%s.v", moduleName)
	err := smiMemTemplates.CreateArbitrationTree(
		fileName, moduleName, *numMemPortsPtr, scalingFactor)
	if err != nil {
		panic(err)
	}

	// Build the wrapper component with the specified number of ports.
	switch *targetPlatformPtr {
	case "sdaccel":
		kernelName := fmt.Sprintf("teak__action__top__smi__x%d", *numMemPortsPtr)
		moduleName = "teak__action__top__gmem"
		fileName = fmt.Sprintf("%s.v", moduleName)
		err = smiMemTemplates.CreateSmiSdaKernelAdaptor(
			fileName, moduleName, kernelName, *numMemPortsPtr, scalingFactor)
	case "llvm":
		kernelName := "teak___x24_main_x2e_Top_x3a_public"
		moduleName := "llvm_kernel_smi_adaptor"
		fileName = fmt.Sprintf("%s.v", moduleName)
		err = smiMemTemplates.CreateSmiLlvmKernelAdaptor(
			fileName, moduleName, kernelName, *numMemPortsPtr,
			scalingFactor, *axiBusIdWidthPtr, *kernelArgsWidthPtr)
	case "huawei-fp1":
		kernelName := "teak__main_x2e_Top"
		moduleName = "fp1_teak_action_top_gmem"
		fileName = fmt.Sprintf("%s.v", moduleName)
		err = smiMemTemplates.CreateSmiFp1KernelAdaptor(
			fileName, moduleName, kernelName, *numMemPortsPtr, scalingFactor)
	default:
		err = errors.New(fmt.Sprintf(
			"Invalid target platform (%s) for kernel adaptor", *targetPlatformPtr))
	}
	if err != nil {
		panic(err)
	}
}
