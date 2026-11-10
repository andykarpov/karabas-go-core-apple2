module io_fifo (
	reset,
	in,
	in_clk,
	in_strobe,
	in_enable,
	out_clk,
	out,
	out_strobe,
	out_enable,
	space,
	empty,
	used,
	full
);
	parameter DATA_WIDTH = 8;
	parameter DEPTH = 4;
	input reset;
	input [DATA_WIDTH - 1:0] in;
	input in_clk;
	input in_strobe;
	input in_enable;
	input out_clk;
	output wire [DATA_WIDTH - 1:0] out;
	input out_strobe;
	input out_enable;
	output wire [DEPTH - 1:0] space;
	output wire empty;
	output wire [DEPTH - 1:0] used;
	output wire full;
	localparam FIFO_ADDR_BITS = DEPTH;
	localparam FIFO_DEPTH = 1 << FIFO_ADDR_BITS;
	reg [DATA_WIDTH - 1:0] fifo [FIFO_DEPTH - 1:0];
	reg [FIFO_ADDR_BITS - 1:0] writeP;
	reg [FIFO_ADDR_BITS - 1:0] readP;
	assign full = readP == (writeP + 1);
	assign empty = readP == writeP;
	assign used = writeP - readP;
	assign space = (readP - writeP) - 1'd1;
	reg in_strobeD;
	reg in_strobeD2;
	reg out_strobeD;
	reg out_strobeD2;
	assign out = (!empty ? fifo[readP] : fifo[readP - 1'd1]);
	always @(posedge out_clk) begin
		out_strobeD <= out_strobe;
		out_strobeD2 <= out_strobeD;
		if (reset)
			readP <= 0;
		else if ((out_strobeD && !out_strobeD2) || out_enable)
			readP <= readP + 1'd1;
	end
	always @(posedge in_clk) begin
		in_strobeD <= in_strobe;
		in_strobeD2 <= in_strobeD;
		if (reset)
			writeP <= 0;
		else if ((in_strobeD && !in_strobeD2) || in_enable) begin
			fifo[writeP] <= in;
			writeP <= writeP + 1'd1;
		end
	end
endmodule
