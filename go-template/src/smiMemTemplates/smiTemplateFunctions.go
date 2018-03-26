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
	"text/template"
	"time"
)

//
// Create Verilog bit slice of specified width.
//
func makeBitSliceFromScaledWidth(width uint, scaling uint) string {
	return fmt.Sprintf("[%3d:0]", width*scaling-1)
}

//
// Create Verilog bit slice with specified data index size.
//
func makeBitSliceFromIndexSize(indexSize uint, scaling uint) string {
	width := uint(1 << uint(indexSize))
	return fmt.Sprintf("[%3d:0]", width*scaling-1)
}

//
// Creates a port identifier name where ports are distinguished using the
// sequence of alphabetic characters A, B, C etc.
//
func makePortIdCharName(portNamePattern string, index int) string {
	return fmt.Sprintf(portNamePattern, index+int('A'))
}

//
// Creates a time and date string which can be used for timestamping generated
// files.
//
func makeFileTimestamp() string {
	return time.Now().Format(time.RFC1123)
}

//
// Build the template function map.
//
var smiTemplateFunctions = template.FuncMap{
	"makeBitSliceFromScaledWidth": makeBitSliceFromScaledWidth,
	"makeBitSliceFromIndexSize":   makeBitSliceFromIndexSize,
	"makePortIdCharName":          makePortIdCharName,
	"makeFileTimestamp":           makeFileTimestamp}
