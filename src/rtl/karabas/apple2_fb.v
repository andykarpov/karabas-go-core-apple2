`timescale 1ns / 1ps
`default_nettype wire

/*
 apple2_fb.v

 The frame buffer of the Apple video (docs/PLAN.md decision 4): the picture of the machine at its
 own rate goes into block RAM, the board shows it as a standard 640 x 480 at 60 Hz (VGA timing of
 a 25 MHz pixel clock: 800 x 525, syncs negative at the pads, here high active).

 In (clk_core, 14 MHz): the bit stream VIDEO of apple2.vhd (one point per clock, 560 per line in
 the window HBL / VBL low, 192 lines), one bit per point: 560 x 192 = 107520 bits in 8 RAMB16,
 and COLOR_LINE once per line (192 bits). The colours of the Apple are made from the bit stream
 (NTSC artifacts: a point's colour depends on its neighbours and on its position modulo 4), so
 the bits are enough.

 Out (clk_pix, 25 MHz): 640 x 480, the Apple window 560 x 384 in its middle (x 40, y 48), each
 line twice. The bits of a line go out one per pixel clock into vga_controller of NanoApple2
 (the same colouring, palettes and monochrome modes as upstream), with HBL / VBL of the window so
 that its point counter starts where the line starts, as in the machine. Its picture comes
 LAT clocks after the bit; the syncs and the enable are delayed to match.

 One buffer, written while it is read: the two frame rates differ (59.92 / 59.52 Hz), so a
 moving picture tears at one line that walks through the screen every 2.5 s (decided to try
 first; two buffers would need 8 more RAMB16).
*/

module apple2_fb #(
	parameter LAT = 5               // clocks from VIDEO to the RGB of vga_controller (the sim checks)
) (
	// the machine
	input wire clk_core,
	input wire video,
	input wire color_line,
	input wire hbl,
	input wire vbl,

	// options (quasi static)
	input wire [1:0] screen_mode,   // 00 colour, 01 B&W, 10 green, 11 amber
	input wire [1:0] palette,

	// 640 x 480
	input wire clk_pix,
	output reg [23:0] rgb = 24'd0,
	output reg hs = 1'b0,
	output reg vs = 1'b0,
	output reg de = 1'b0
);

// ------------------------------------------------------------------ in

// the points of a line come X_SKIP clocks after the falling edge of HBL (and run on into HBL):
// 13..572 in the sim (video_generator); vga_controller counts the colour phase from that edge too
localparam X_SKIP = 13;

reg [9:0] hx = 10'd0;         // clocks since the falling edge of HBL
reg [7:0] wy = 8'd0;
reg [16:0] waddr = 17'd0, wline = 17'd0;
reg old_hbl = 1'b1, old_vbl = 1'b1;
reg line_on = 1'b0;           // the line has points (not in VBL)
reg [191:0] colors = 192'd0;
wire first = !hbl && old_hbl;
wire wr = line_on && !first && hx >= X_SKIP - 1 && hx < X_SKIP + 559;

always @(posedge clk_core) begin
	old_hbl <= hbl;
	old_vbl <= vbl;
	if (vbl && !old_vbl) begin
		wy <= 8'd0;
		wline <= 17'd0;
		line_on <= 1'b0;
	end
	if (first) begin
		hx <= 10'd0;
		waddr <= wline;
		line_on <= !vbl;
		// the line before had points: the next line of the buffer
		if (line_on && !(vbl && !old_vbl) && wy != 8'd191) begin
			wy <= wy + 8'd1;
			wline <= wline + 17'd560;
			waddr <= wline + 17'd560;
		end
	end
	else if (hx != 10'h3FF)
		hx <= hx + 10'd1;
	if (wr)
		waddr <= waddr + 17'd1;
	if (line_on && hx == 10'd100)
		colors[wy] <= color_line;
end

wire [16:0] wa = waddr;
wire rbit;
reg [16:0] raddr = 17'd0;

kg_sdpram #(.DW(1), .AW(17)) buffer (
	.clka(clk_core),
	.wea(wr),
	.addra(wa),
	.dina(video),
	.clkb(clk_pix),
	.enb(1'b1),
	.addrb(raddr),
	.doutb(rbit)
);

// ------------------------------------------------------------------ out

localparam H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_TOTAL = 800;
localparam V_ACTIVE = 480, V_FP = 10, V_SYNC = 2, V_TOTAL = 525;
localparam X0 = 40, Y0 = 48;  // the Apple window

reg [9:0] hc = 10'd0, vc = 10'd0;
always @(posedge clk_pix) begin
	if (hc == H_TOTAL - 1) begin
		hc <= 10'd0;
		vc <= (vc == V_TOTAL - 1) ? 10'd0 : vc + 10'd1;
	end
	else
		hc <= hc + 10'd1;
end

wire [9:0] ax = hc - X0;
wire [9:0] ay = vc - Y0;
wire in_x = hc >= X0 && hc < X0 + 560;
wire in_h = hc >= X0 - X_SKIP && hc < X0 + 560;  // HBL of vga_controller: falls X_SKIP before the points
wire in_y = vc >= Y0 && vc < Y0 + 384;
wire [7:0] line = ay[8:1];

// stage 1: the address of the point (a line of the Apple: 560 bits)
reg [16:0] rline = 17'd0;
reg s1_x = 1'b0, s1_y = 1'b0, s1_h = 1'b0;
reg s1_color = 1'b0;
always @(posedge clk_pix) begin
	if (hc == H_TOTAL - 1)
		rline <= (vc + 10'd1 == Y0) ? 17'd0 : (in_y && ay[0]) ? rline + 17'd560 : rline;
	raddr <= rline + ax;
	s1_x <= in_x;
	s1_h <= in_h;
	s1_y <= in_y;
	s1_color <= colors[line];
end

// stage 2: the bit (block RAM) into vga_controller
reg s2_x = 1'b0, s2_y = 1'b0, s2_h = 1'b0, s2_color = 1'b0;
always @(posedge clk_pix) begin
	s2_x <= s1_x;
	s2_h <= s1_h;
	s2_y <= s1_y;
	s2_color <= s1_color;
end

wire [7:0] vr, vg, vb;
vga_controller colour (
	.CLK_14M(clk_pix),
	.VIDEO(rbit & s2_x & s2_y),
	.COLOR_LINE(s2_color),
	.SCREEN_MODE(screen_mode),
	.COLOR_PALETTE(palette),
	.HBL(~s2_h),
	.VBL(~s2_y),
	.VGA_HS(),
	.VGA_VS(),
	.VGA_HBL(),
	.VGA_VBL(),
	.VGA_R(vr),
	.VGA_G(vg),
	.VGA_B(vb),
	.ioctl_addr(25'd0),
	.ioctl_data(8'd0),
	.ioctl_index(8'd0),
	.ioctl_download(1'b0),
	.ioctl_wr(1'b0),
	.ioctl_wait(),
	.ioctl_clk(clk_pix)
);

// the timing of the counters, delayed by the two stages and LAT
localparam D = 2 + LAT;
reg [D-1:0] d_hs = 0, d_vs = 0, d_de = 0, d_win = 0;
always @(posedge clk_pix) begin
	d_hs <= { d_hs[D-2:0], hc >= H_ACTIVE + H_FP && hc < H_ACTIVE + H_FP + H_SYNC };
	d_vs <= { d_vs[D-2:0], vc >= V_ACTIVE + V_FP && vc < V_ACTIVE + V_FP + V_SYNC };
	d_de <= { d_de[D-2:0], hc < H_ACTIVE && vc < V_ACTIVE };
	d_win <= { d_win[D-2:0], in_x && in_y };
	hs <= d_hs[D-1];
	vs <= d_vs[D-1];
	de <= d_de[D-1];
	rgb <= d_win[D-1] ? { vr, vg, vb } : 24'd0;
end

endmodule
