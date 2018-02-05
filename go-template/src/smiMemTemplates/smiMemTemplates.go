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
	"os"
)

//
// CreateArbitrationTree generates an SMI memory arbitration tree module for the
// number of SMI client endpoints specified by the 'numClients' parameter. The
// generated code incorporates bus width scaling such that the client side flits
// are 64 bits wide and the server side flits are 512 bits wide. Writes the
// module source code to the Verilog source file specified by the 'fileName'
// parameter and using the Verilog module name specified by the 'moduleName'
// parameter. Returns an error item which will be set to 'nil' on successful
// completion.
//
func CreateArbitrationTree(fileName string, moduleName string, numClients uint) error {
	var outFile *os.File
	var config arbitrationTreeConfig
	var err error

	// Attempt to open the specified file for output.
	outFile, err = os.Create(fileName)
	if err != nil {
		return err
	}
	defer outFile.Close()

	// Set up the template configuration.
	config, err = configureArbitrationTree(moduleName, numClients)
	if err != nil {
		return err
	}

	// Generate the Verilog file.
	return executeArbitrationTreeTemplate(outFile, config)
}
