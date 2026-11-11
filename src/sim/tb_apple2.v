`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_apple2.v

 The machine as the board has it: apple2_top (the ghdl netlist of the VHDL plus the Verilog
 modules), apple2_sram with a model of the SRAM at its pins (two lanes of 64K here: main the low,
 aux the high one; asynchronous read, written while /WE is low) and the frame buffer apple2_fb
 (640 x 480). The machine needs the registered read of apple2_sram: the CPU takes its data on the
 clock after PHASE_ZERO falls, when ram_addr is the video address already (docs/PLAN.md Ф1).

 The clocks (clk_sys 28.571, clk_core 14.286, clk_pix 25 MHz), the keyboard, the SD card as
 img_sdc serves it and the frame capture are in sim_apple2.cpp.
*/

module tb_apple2 (
	input wire clk_core,
	input wire clk_sys,
	input wire clk_pix,
	input wire reset_cold,
	input wire reset_warm,

	input wire [7:0] usb_key,
	input wire kbd_strobe,

	input wire [2:0] img_mounted,
	input wire [31:0] img_size,
	output wire [31:0] sd_lba,
	output wire [2:0] sd_rd,
	output wire [2:0] sd_wr,
	input wire sd_busy,
	input wire [2:0] sd_slot,
	input wire [8:0] sd_byte_index,
	input wire [7:0] sd_rd_data,
	input wire sd_rd_byte_strobe,
	output wire [7:0] sd_wr_data,

	input wire [1:0] screen_mode,
	output wire [23:0] rgb,
	output wire hs,
	output wire vs,
	output wire de,
	output wire speaker,
	output wire [1:0] disk_active,

	// for the harness (dumps, checks)
	output wire [15:0] ram_addr,
	output wire ram_we,
	output wire ram_aux,
	output wire [7:0] ram_din,
	output wire video,
	output wire hbl,
	output wire vbl
);

	// the SRAM chips
	reg [7:0] main_mem [0:65535];
	reg [7:0] aux_mem [0:65535];
	integer i;
	initial
		for (i = 0; i < 65536; i = i + 1) begin
			main_mem[i] = 8'h00;
			aux_mem[i] = 8'h00;
		end

	wire [20:0] MA;
	wire [1:0] MWR_N;
	wire [15:0] md_out;      // apple2_sram drives its lane while /WE is low
	wire [1:0] md_oe;
	wire [15:0] ram_dout;
	wire [15:0] MD = { md_oe[1] ? md_out[15:8] : aux_mem[MA[15:0]], md_oe[0] ? md_out[7:0] : main_mem[MA[15:0]] };
	always @(posedge MWR_N[0]) main_mem[MA[15:0]] <= md_out[7:0];
	always @(posedge MWR_N[1]) aux_mem[MA[15:0]] <= md_out[15:8];

	apple2_sram sram (
		.clk(clk_core),
		.ram_addr(ram_addr),
		.ram_aux(ram_aux),
		.ram_we(ram_we),
		.ram_din(ram_din),
		.ram_dout(ram_dout),
		.MA(MA),
		.md_in(MD),
		.md_out(md_out),
		.md_oe(md_oe),
		.MWR_N(MWR_N)
	);

	wire color_line;

	apple2_top machine (
		.clk_core(clk_core),
		.clk_sys(clk_sys),
		.reset_cold(reset_cold),
		.reset_warm(reset_warm),
		.cpu_type(1'b1),
		.romswitch(1'b1),
		.color_text(1'b0),
		.mono(screen_mode != 2'b00),
		.mb_en(1'b1),
		.mouse_en(1'b1),
		.ssc_en(1'b0),
		.ssc_irq_en(1'b0),
		.hdd_en(1'b1),
		.floppy_wp(2'b00),
		.hdd_wp(1'b0),
		.ram_addr(ram_addr),
		.ram_aux(ram_aux),
		.ram_we(ram_we),
		.ram_din(ram_din),
		.ram_dout(ram_dout),
		.video(video),
		.color_line(color_line),
		.hbl(hbl),
		.vbl(vbl),
		.speaker(speaker),
		.psg_l(),
		.psg_r(),
		.usb_key(usb_key),
		.kbd_strobe(kbd_strobe),
		.soft_reset(),
		.paddle_x(8'h00),
		.paddle_y(8'h00),
		.joy_btn(2'b00),
		.mouse_strobe(1'b0),
		.mouse_x(9'd0),
		.mouse_y(9'd0),
		.mouse_btn(1'b0),
		.img_mounted(img_mounted),
		.img_size(img_size),
		.sd_lba(sd_lba),
		.sd_rd(sd_rd),
		.sd_wr(sd_wr),
		.sd_busy(sd_busy),
		.sd_slot(sd_slot),
		.sd_byte_index(sd_byte_index),
		.sd_rd_data(sd_rd_data),
		.sd_rd_byte_strobe(sd_rd_byte_strobe),
		.sd_wr_data(sd_wr_data),
		.uart_rx(1'b1),
		.uart_tx(),
		.disk_active(disk_active)
	);

	apple2_fb fb (
		.clk_core(clk_core),
		.video(video),
		.color_line(color_line),
		.hbl(hbl),
		.vbl(vbl),
		.screen_mode(screen_mode),
		.palette(2'b00),
		.clk_pix(clk_pix),
		.rgb(rgb),
		.hs(hs),
		.vs(vs),
		.de(de)
	);

endmodule
