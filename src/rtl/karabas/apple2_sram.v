`timescale 1ns / 1ps
`default_nettype wire

/*
 apple2_sram.v

 The 64K main + 64K aux RAM of the Apple //e in the SRAM of the board (two byte lanes of 2M x 8,
 10 ns, asynchronous): main RAM is the low lane (MD[7:0], MWR_N[0]), aux RAM the high lane of the
 same word, so one read gives both, as apple2.vhd wants them (ram_do = aux & main). MA = ram_addr,
 the upper address bits 0. /OE (MRD_N) is tied low by the top: an SRAM chip with /WE low does not
 drive its lane.

 The machine needs a registered read on its 14 MHz clock (sim/tb_apple2.v, docs/PLAN.md Ф1):
 the CPU takes ram_do on the clock after PHASE_ZERO falls, when ram_addr is the video address
 already. Here MA is ram_addr registered and dout is MD registered: dout at an edge is the SRAM at
 ram_addr two edges before. ram_addr is stable for the 7 clocks of each half of a CPU cycle (the
 CPU in PHASE_ZERO high, the video in low), so at the edge where PHASE_ZERO falls dout is the CPU
 byte and the video latch later in the low half gets the video byte. One clock (70 ns) covers the
 address out, the 10 ns of the SRAM and the data in.

 Write: ram_we is high (with ram_addr, ram_aux, ram_din) for the clocks of PHASE_ZERO high. /WE of
 the lane goes low at the falling edge after the registered address has the write address, and
 high again at the falling edge after ram_we has gone (the address register changes half a clock
 later); MD is driven while /WE is low.
*/

module apple2_sram (
	input wire clk,                // clk_core, 14 MHz

	input wire [15:0] ram_addr,
	input wire ram_aux,
	input wire ram_we,
	input wire [7:0] ram_din,
	output reg [15:0] ram_dout = 16'd0,

	output reg [20:0] MA = 21'd0,
	input wire [15:0] md_in,       // MD of the pads (the top has the tristate buffers)
	output wire [15:0] md_out,
	output wire [1:0] md_oe,       // drive the lane: MD[7:0] / MD[15:8]
	output wire [1:0] MWR_N
);

reg we_q = 1'b0;
reg aux_q = 1'b0;
reg [7:0] din_q = 8'd0;

always @(posedge clk) begin
	MA <= { 5'd0, ram_addr };
	we_q <= ram_we;
	aux_q <= ram_aux;
	din_q <= ram_din;
	ram_dout <= md_in;
end

// the write strobe on the falling edges: on while the registered and the current request agree
reg we_act = 1'b0;
always @(negedge clk)
	we_act <= we_q & ram_we;

assign MWR_N = { ~(we_act & aux_q), ~(we_act & ~aux_q) };
assign md_out = { din_q, din_q };
assign md_oe = { we_act & aux_q, we_act & ~aux_q };

endmodule
