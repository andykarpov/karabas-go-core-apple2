`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_apple2.v

 The machine (apple2_top, the ghdl netlist of the VHDL plus the Verilog modules) with a model of the
 RAM: 64K main + 64K aux, ram_dout = aux & main at ram_addr, REGISTERED on the 14 MHz clock and
 written on it. The machine needs the register: the CPU takes its data (CPU_DL = ram_do) on the
 clock after PHASE_ZERO falls, when ram_addr is the video address already; the SDRAM of MiST /
 NanoApple2 held the data the same way. The clocks, the keyboard, the SD card and the
 frame capture are in sim_apple2.cpp.
*/

module tb_apple2 (
	input wire clk_core,
	input wire clk_sys,
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
	input wire [8:0] sd_byte_index,
	input wire [7:0] sd_rd_data,
	input wire sd_rd_byte_strobe,
	output wire [7:0] sd_wr_data,

	output wire video,
	output wire hbl,
	output wire vbl,
	output wire [7:0] vga_r,
	output wire [7:0] vga_g,
	output wire [7:0] vga_b,
	output wire vga_hs,
	output wire vga_vs,
	output wire vga_hblank,
	output wire vga_vblank,
	output wire speaker,
	output wire [1:0] disk_active,

	// the RAM, for the harness (dumps, checks)
	output wire [15:0] ram_addr,
	output wire ram_we,
	output wire ram_aux,
	output wire [7:0] ram_din
);

	reg [7:0] main_mem [0:65535];
	reg [7:0] aux_mem [0:65535];
	integer i;
	initial
		for (i = 0; i < 65536; i = i + 1) begin
			main_mem[i] = 8'h00;
			aux_mem[i] = 8'h00;
		end

	reg [15:0] ram_dout = 16'd0;
	always @(posedge clk_core) begin
		ram_dout <= {aux_mem[ram_addr], main_mem[ram_addr]};
		if (ram_we) begin
			if (ram_aux)
				aux_mem[ram_addr] <= ram_din;
			else
				main_mem[ram_addr] <= ram_din;
		end
	end

	apple2_top machine (
		.clk_core(clk_core),
		.clk_sys(clk_sys),
		.reset_cold(reset_cold),
		.reset_warm(reset_warm),
		.cpu_type(1'b1),
		.romswitch(1'b0),
		.screen_mode(2'b00),
		.palette(2'b00),
		.lores_text(1'b0),
		.mb_en(1'b1),
		.mouse_en(1'b1),
		.ssc_en(1'b1),
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
		.color_line(),
		.hbl(hbl),
		.vbl(vbl),
		.vga_r(vga_r),
		.vga_g(vga_g),
		.vga_b(vga_b),
		.vga_hs(vga_hs),
		.vga_vs(vga_vs),
		.vga_hblank(vga_hblank),
		.vga_vblank(vga_vblank),
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
		.sd_byte_index(sd_byte_index),
		.sd_rd_data(sd_rd_data),
		.sd_rd_byte_strobe(sd_rd_byte_strobe),
		.sd_wr_data(sd_wr_data),
		.uart_rx(1'b1),
		.uart_tx(),
		.disk_active(disk_active)
	);

endmodule
