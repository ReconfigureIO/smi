//
// (c) 2017 ReconfigureIO
//
// <COPYRIGHT TERMS>
//

//
// Package smi/protocol provides low level primitives and data types for working
// with the SMI protocol.
//
package smi

//
// Import the SMI specific Verilog code.
// #include verilog/smi_axi_bus_adaptor.v
// #include verilog/smi_axi_read_adaptor.v
// #include verilog/smi_axi_write_adaptor.v
// #include verilog/smi_byte_data_align.v
// #include verilog/smi_flit_data_pack.v
// #include verilog/smi_flit_scale_d2.v
// #include verilog/smi_flit_scale_d4.v
// #include verilog/smi_flit_scale_d8.v
// #include verilog/smi_flit_scale_stage_d2.v
// #include verilog/smi_flit_scale_stage_x2.v
// #include verilog/smi_flit_scale_x2.v
// #include verilog/smi_flit_scale_x4.v
// #include verilog/smi_flit_scale_x8.v
// #include verilog/smi_frame_arbiter_x2.v
// #include verilog/smi_frame_arbiter_x4.v
// #include verilog/smi_frame_steer_x2.v
// #include verilog/smi_frame_steer_x4.v
// #include verilog/smi_header_extract_sf.v
// #include verilog/smi_header_inject_sf.v
// #include verilog/smi_scaling_arbiter_x2.v
// #include verilog/smi_scaling_arbiter_x4.v
// #include verilog/smi_transaction_matcher.v
// #include verilog/sda_kernel_wrapper_gmem.v
//

//
// Constants specifying the supported SMI frame type bytes.
//
const (
	SmiMemWriteReq  = 0x01 // SMI memory write request.
	SmiMemWriteResp = 0xFE // SMI memory write response.
	SmiMemReadReq   = 0x02 // SMI memory read request.
	SmiMemReadResp  = 0xFD // SMI memory read response.
)

//
// Constants specifying the supported SMI memory write options.
//
const (
	SmiMemWriteOptDefault = uint8(0x00) // Use default buffered write options.
	SmiMemWriteOptDirect  = uint8(0x01) // Perform direct unbuffered write.
)

//
// Constants specifying the supported SMI memory read options.
//
const (
	SmiMemReadOptDefault = uint8(0x00) // Use default buffered read options.
	SmiMemReadOptDirect  = uint8(0x01) // Perform direct unbuffered read.
)

//
// Specify the standard burst fragment size as an integer number of bytes.
//
const SmiMemBurstSize = 256

//
// The maximum frame size is derived from the SmiMemBurstSize parameter
// and can contain the specified amount of data plus up to 16 bytes of
// header information.
//
const SmiMemFrame64Size = 2 + SmiMemBurstSize/8

//
// Specify the number of in-flight transactions supported by each
// arbitrated SMI port.
//
const SmiMemInFlightLimit = 4

//
// Type Flit64 specifies an SMI flit format with a 64-bit datapath.
//
type Flit64 struct {
	Data [8]uint8
	Eofc uint8
}

//
// Forwards a single Flit64 based SMI frame from an input channel to an output
// channel with intermediate buffering. The buffer has capacity to store a
// complete frame, with data being available at the output as soon as it has
// been received on the input.
// TODO: Update once there is a fix for the channel size compiler limitation.
//
func ForwardFrame64(
	smiInput <-chan Flit64,
	smiOutput chan<- Flit64) {
	smiBuffer := make(chan Flit64, 34 /* SmiMemFrame64Size */)

	go func() {
		hasNextInputFlit := true
		for hasNextInputFlit {
			inputFlitData := <-smiInput
			smiBuffer <- inputFlitData
			hasNextInputFlit = inputFlitData.Eofc == uint8(0)
		}
	}()

	hasNextOutputFlit := true
	for hasNextOutputFlit {
		outputFlitData := <-smiBuffer
		smiOutput <- outputFlitData
		hasNextOutputFlit = outputFlitData.Eofc == uint8(0)
	}
}

//
// Assembles a single Flit64 based SMI frame from an input channel, copying the
// frame to the output channel once the entire frame has been received. The
// maximum frame size is derived from the SmiMemBurstSize parameter and can
// contain the specified amount of payload data plus up to 16 bytes of header
// information.
// TODO: Update once there is a fix for the channel size compiler limitation.
//
func AssembleFrame64(
	smiInput <-chan Flit64,
	smiOutput chan<- Flit64) {
	smiBuffer := make(chan Flit64, 34 /* SmiMemFrame64Size */)

	hasNextInputFlit := true
	for hasNextInputFlit {
		inputFlitData := <-smiInput
		smiBuffer <- inputFlitData
		hasNextInputFlit = inputFlitData.Eofc == uint8(0)
	}

	hasNextOutputFlit := true
	for hasNextOutputFlit {
		outputFlitData := <-smiBuffer
		smiOutput <- outputFlitData
		hasNextOutputFlit = outputFlitData.Eofc == uint8(0)
	}
}