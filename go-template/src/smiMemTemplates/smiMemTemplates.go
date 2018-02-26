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

//
// Package smiMemTemplates provides a set of functions for generating Verilog
// source code files for the SMI memory infrastructure using parameterised
// templates.
//
package smiMemTemplates

import (
	"errors"
	"fmt"
	"os"
)

//
// CreateArbitrationTree generates an SMI memory arbitration tree module for the
// number of SMI client endpoints specified by the 'numClients' parameter. The
// generated code incorporates bus width scaling such that the client side flits
// are 64 bits wide and the server side flit widths are scaled up as specified
// by the 'scalingFactor' parameter. Scaling factors of 1, 2, 4 and 8 are
// supported, giving server side flit widths of 64, 128, 256 and 512 bits.
// This writes the module source code to the Verilog source file specified by
// the 'fileName' parameter and using the Verilog module name specified by the
// 'moduleName' parameter. Returns an error item which will be set to 'nil' on
// successful completion.
//
func CreateArbitrationTree(fileName string, moduleName string, numClients uint,
	scalingFactor uint) error {

	var outFile *os.File
	var config arbitrationTreeConfig
	var err error

	// Check for valid scaling factor.
	if (scalingFactor != 1) && (scalingFactor != 2) &&
		(scalingFactor != 4) && (scalingFactor != 8) {
		err = errors.New(fmt.Sprintf(
			"Invalid bus scaling (%d) for arbitration tree", scalingFactor))
		return err
	}

	// Attempt to open the specified file for output.
	outFile, err = os.Create(fileName)
	if err != nil {
		return err
	}
	defer outFile.Close()

	// Set up the template configuration.
	config, err = configureArbitrationTree(moduleName, numClients, scalingFactor)
	if err != nil {
		return err
	}

	// Generate the Verilog file.
	return executeArbitrationTreeTemplate(outFile, config)
}

//
// CreateSmiSdaKernelAdaptor generates a configurable SMI kernel adaptor for the
// standard SDAccel build process. Writes the module source code to the Verilog
// source file specified by the 'fileName' parameter using the Verilog module
// name specified by the 'moduleName' parameter. The wrapper supports the number
// of independent SMI memory access ports specified by the 'numClients'
// parameter and the internal bus scaling specfied by the 'scalingFactor'
// parameter. Scaling factors of 1, 2, 4 and 8 are supported, giving AXI data
// widths of 64, 128, 256 and 512 bits. Returns an error item which will be set
// to 'nil' on successful completion.
//
func CreateSmiSdaKernelAdaptor(fileName string, moduleName string,
	numClients uint, scalingFactor uint) error {

	var outFile *os.File
	var config smiSdaKernelAdaptorConfig
	var err error

	// Check for valid scaling factor.
	if (scalingFactor != 1) && (scalingFactor != 2) &&
		(scalingFactor != 4) && (scalingFactor != 8) {
		err = errors.New(fmt.Sprintf(
			"Invalid bus scaling (%d) for kernel adaptor", scalingFactor))
		return err
	}

	// Attempt to open the specified file for output.
	outFile, err = os.Create(fileName)
	if err != nil {
		return err
	}
	defer outFile.Close()

	// Set up the template configuration.
	config, err = configureSmiSdaKernelAdaptor(moduleName, numClients, scalingFactor)
	if err != nil {
		return err
	}

	// Generate the Verilog file.
	return executeSmiSdaKernelAdaptorTemplate(outFile, config)
}
