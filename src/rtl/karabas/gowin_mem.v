`timescale 1ns / 1ps
`default_nettype wire

/*
 gowin_mem.v

 karabas: the Gowin memory wrappers that the NanoApple2 machine instantiates (upstream/gowin),
 with the same module and port names, on the inferred block RAMs of modules/rtl/mem. Gowin
 READ_MODE 0 (bypass) = one clock of read latency, as kg_*; oce only matters in pipeline mode
 and is ignored; the resets are tied to 0 upstream and ignored too. The ROM contents come from
 the .hex files of src/roms (tools/mi2hex.py of the upstream .mi files), paths relative to src/.
*/

// system ROM: 16K x 8 (27128.mi = $C000-$FFFF of the //e enhanced)
module Gowin_pROM_apple2 (
	output wire [7:0] dout,
	input wire clk,
	input wire oce,
	input wire ce,
	input wire reset,
	input wire [13:0] ad
);
	kg_sprom #(.DW(8), .AW(14), .INIT_FILE("roms/27128.hex")) rom (
		.clk(clk), .en(ce), .addr(ad), .dout(dout));
endmodule

// keyboard ROM: 2K x 8
module Gowin_pROM_key (
	output wire [7:0] dout,
	input wire clk,
	input wire oce,
	input wire ce,
	input wire reset,
	input wire [10:0] ad
);
	kg_sprom #(.DW(8), .AW(11), .INIT_FILE("roms/key.hex")) rom (
		.clk(clk), .en(ce), .addr(ad), .dout(dout));
endmodule

// video (character) ROM: 8K x 8, port A writes (loading), port B reads
module Gowin_SDPB_8k (
	output wire [7:0] dout,
	input wire clka,
	input wire cea,
	input wire reseta,
	input wire clkb,
	input wire ceb,
	input wire resetb,
	input wire oce,
	input wire [12:0] ada,
	input wire [7:0] din,
	input wire [12:0] adb
);
	kg_sdpram #(.DW(8), .AW(13), .INIT_FILE("roms/video8k.hex")) ram (
		.clka(clka), .wea(cea), .addra(ada), .dina(din),
		.clkb(clkb), .enb(ceb), .addrb(adb), .doutb(dout));
endmodule

// palette: written as 64 bytes, read as 16 words of 32 bits, byte ada[1:0] = bits 8*ada[1:0] +: 8
module Gowin_SDPB_palette (
	output reg [31:0] dout,
	input wire clka,
	input wire cea,
	input wire reseta,
	input wire clkb,
	input wire ceb,
	input wire resetb,
	input wire oce,
	input wire [5:0] ada,
	input wire [7:0] din,
	input wire [3:0] adb
);
	reg [7:0] lane0 [0:15];
	reg [7:0] lane1 [0:15];
	reg [7:0] lane2 [0:15];
	reg [7:0] lane3 [0:15];

	integer i;
	initial begin
		dout = 32'd0;
		for (i = 0; i < 16; i = i + 1) begin
			lane0[i] = 8'd0;
			lane1[i] = 8'd0;
			lane2[i] = 8'd0;
			lane3[i] = 8'd0;
		end
	end

	always @(posedge clka)
		if (cea)
			case (ada[1:0])
				2'd0: lane0[ada[5:2]] <= din;
				2'd1: lane1[ada[5:2]] <= din;
				2'd2: lane2[ada[5:2]] <= din;
				2'd3: lane3[ada[5:2]] <= din;
			endcase

	always @(posedge clkb)
		if (ceb)
			dout <= {lane3[adb], lane2[adb], lane1[adb], lane0[adb]};
endmodule

// HDD sector buffer: 512 x 8, true dual port
module Gowin_DPB_track_buffer_b (
	output wire [7:0] douta,
	output wire [7:0] doutb,
	input wire clka,
	input wire ocea,
	input wire cea,
	input wire reseta,
	input wire wrea,
	input wire clkb,
	input wire oceb,
	input wire ceb,
	input wire resetb,
	input wire wreb,
	input wire [8:0] ada,
	input wire [7:0] dina,
	input wire [8:0] adb,
	input wire [7:0] dinb
);
	kg_tdpram #(.DW(8), .AW(9), .WRITE_FIRST(0)) ram (
		.clka(clka), .ena(cea), .wea(wrea), .addra(ada), .dina(dina), .douta(douta),
		.clkb(clkb), .enb(ceb), .web(wreb), .addrb(adb), .dinb(dinb), .doutb(doutb));
endmodule

// floppy track buffer: 8K x 8 (a .NIB track is 6656 bytes), true dual port
module Gowin_DPB_trkbuf (
	output wire [7:0] douta,
	output wire [7:0] doutb,
	input wire clka,
	input wire ocea,
	input wire cea,
	input wire reseta,
	input wire wrea,
	input wire clkb,
	input wire oceb,
	input wire ceb,
	input wire resetb,
	input wire wreb,
	input wire [12:0] ada,
	input wire [7:0] dina,
	input wire [12:0] adb,
	input wire [7:0] dinb
);
	kg_tdpram #(.DW(8), .AW(13), .WRITE_FIRST(0)) ram (
		.clka(clka), .ena(cea), .wea(wrea), .addra(ada), .dina(dina), .douta(douta),
		.clkb(clkb), .enb(ceb), .web(wreb), .addrb(adb), .dinb(dinb), .doutb(doutb));
endmodule

// AppleMouse 6805 RAM: 128 x 8
module Gowin_SP_128b (
	output wire [7:0] dout,
	input wire clk,
	input wire oce,
	input wire ce,
	input wire reset,
	input wire wre,
	input wire [6:0] ad,
	input wire [7:0] din
);
	kg_spram #(.DW(8), .AW(7), .WRITE_FIRST(0)) ram (
		.clk(clk), .en(ce), .we(wre), .addr(ad), .din(din), .dout(dout));
endmodule

// jt6805 microcode: 4096 x 40 (39 used) = rtl/mouse/jt6805/6805.uc (the upstream Gowin ROM holds
// the same words). 145 distinct words: an index ROM in block RAM (one clock, as the Gowin ROM) and
// the words in a LUT table read asynchronously behind it (tools/uc_compress.py makes both).
module Gowin_pROM_uc (
	output wire [39:0] dout,
	input wire clk,
	input wire oce,
	input wire ce,
	input wire reset,
	input wire [11:0] ad
);
	wire [7:0] idx;
	kg_sprom #(.DW(8), .AW(12), .INIT_FILE("roms/6805_uc_idx.hex")) rom (
		.clk(clk), .en(ce), .addr(ad), .dout(idx));

	(* rom_style = "distributed" *) reg [39:0] tab [0:255];
	initial $readmemh("roms/6805_uc_tab.hex", tab);
	assign dout = tab[idx];
endmodule
