`timescale 1ns / 1ps
`default_nettype wire

/*
 apple2_floppy.v

 One drive of the Disk II: the track buffer of disk_ii.vhd (6656 bytes of nibbles, the .NIB
 track) filled from the SD card through img_sdc. karabas: floppy_track.sv of NanoApple2 (the .NIB
 images, kept as it was: 13 sectors of 512 bytes per track, written back when the track is
 dirty) plus the 140K sector images (.dsk / .do / .po, 143360 bytes): their tracks are made into
 nibbles here, as dsk2nib.c of NanoApple2 makes a .NIB, while the sectors come in.

 Sector images (dsk = 1), read only (the top write protects them): per physical sector p of the
 track the 256 bytes of its logical sector go into a page buffer (one SD read of 512 bytes,
 the half of the sector), then the sector is written into the track buffer as dsk2nib.c has it:
   38 x FF, D5 AA 96, volume (254) / track / sector / sum as 4-and-4, DE AA EB, 8 x FF,
   D5 AA AD, 342 + 1 nibbles of 6-and-2, DE AA EB    (409 bytes; FF to 6656 after sector 15)
 The 86 nibbles of the low bits: encode62 of dsk2nib takes the bytes 255 .. 0 into the nibbles
 2, 3, .. 85, 0, 1, .. in turn, 2 bits each, and keeps the last 6 bits, so
   aux[j] = { sw(p[(257 - j) & 255]), sw(p[171 - j]), sw(p[85 - j]) }   (sw: the 2 bits swapped)
 Sector order: DOS 3.3 (.dsk / .do) or ProDOS (.po), found at the mount from block 2 of the
 image (the volume directory of ProDOS: 00 00 03 00, storage type F in byte 4).

 Ports as floppy_track.sv; dsk is the kind of the image (from its size, apple2_top).
*/

module apple2_floppy (
	input wire clk,                  // the Apple (clk_core)
	input wire clk2,                 // the SD side (clk_sys)
	input wire reset,

	output wire [31:0] sd_lba,
	output reg sd_rd = 1'b0,
	output reg sd_wr = 1'b0,
	input wire sd_ack,

	input wire [8:0] sd_buff_addr,
	input wire [7:0] sd_buff_dout,
	output wire [7:0] sd_buff_din,
	input wire sd_buff_wr,

	input wire change,
	input wire mount,
	input wire dsk,                  // a 140K sector image
	input wire [5:0] track,          // Apple
	output wire ready,               // Apple
	input wire active,               // Apple

	input wire [12:0] ram_addr,      // Apple
	output wire [7:0] ram_do,        // Apple
	input wire [7:0] ram_di,         // Apple
	input wire ram_we,               // Apple
	output wire busy                 // Apple
);

// ------------------------------------------------------------------ synchronisers (as floppy_track)

reg ram_weD = 1'b0, ram_weD2 = 1'b0;
reg [5:0] trackD = 6'd0, trackD2 = 6'd0;
reg activeD = 1'b0, activeD2 = 1'b0;
always @(posedge clk2) begin
	{ ram_weD, ram_weD2 } <= { ram_we, ram_weD };
	{ trackD, trackD2 } <= { track, trackD };
	{ activeD, activeD2 } <= { active, activeD };
end

reg readyi = 1'b0, busyi = 1'b0;
reg readyD = 1'b0, readyD2 = 1'b0, busyD = 1'b0, busyD2 = 1'b0;
always @(posedge clk) begin
	{ readyD, readyD2 } <= { readyi, readyD };
	{ busyD, busyD2 } <= { busyi, busyD };
end
assign ready = readyD2;
assign busy = busyD2;

// ------------------------------------------------------------------ the GCR tables

function [7:0] gcr;
	input [5:0] v;
	case (v)
		6'h00: gcr = 8'h96; 6'h01: gcr = 8'h97; 6'h02: gcr = 8'h9A; 6'h03: gcr = 8'h9B;
		6'h04: gcr = 8'h9D; 6'h05: gcr = 8'h9E; 6'h06: gcr = 8'h9F; 6'h07: gcr = 8'hA6;
		6'h08: gcr = 8'hA7; 6'h09: gcr = 8'hAB; 6'h0A: gcr = 8'hAC; 6'h0B: gcr = 8'hAD;
		6'h0C: gcr = 8'hAE; 6'h0D: gcr = 8'hAF; 6'h0E: gcr = 8'hB2; 6'h0F: gcr = 8'hB3;
		6'h10: gcr = 8'hB4; 6'h11: gcr = 8'hB5; 6'h12: gcr = 8'hB6; 6'h13: gcr = 8'hB7;
		6'h14: gcr = 8'hB9; 6'h15: gcr = 8'hBA; 6'h16: gcr = 8'hBB; 6'h17: gcr = 8'hBC;
		6'h18: gcr = 8'hBD; 6'h19: gcr = 8'hBE; 6'h1A: gcr = 8'hBF; 6'h1B: gcr = 8'hCB;
		6'h1C: gcr = 8'hCD; 6'h1D: gcr = 8'hCE; 6'h1E: gcr = 8'hCF; 6'h1F: gcr = 8'hD3;
		6'h20: gcr = 8'hD6; 6'h21: gcr = 8'hD7; 6'h22: gcr = 8'hD9; 6'h23: gcr = 8'hDA;
		6'h24: gcr = 8'hDB; 6'h25: gcr = 8'hDC; 6'h26: gcr = 8'hDD; 6'h27: gcr = 8'hDE;
		6'h28: gcr = 8'hDF; 6'h29: gcr = 8'hE5; 6'h2A: gcr = 8'hE6; 6'h2B: gcr = 8'hE7;
		6'h2C: gcr = 8'hE9; 6'h2D: gcr = 8'hEA; 6'h2E: gcr = 8'hEB; 6'h2F: gcr = 8'hEC;
		6'h30: gcr = 8'hED; 6'h31: gcr = 8'hEE; 6'h32: gcr = 8'hEF; 6'h33: gcr = 8'hF2;
		6'h34: gcr = 8'hF3; 6'h35: gcr = 8'hF4; 6'h36: gcr = 8'hF5; 6'h37: gcr = 8'hF6;
		6'h38: gcr = 8'hF7; 6'h39: gcr = 8'hF9; 6'h3A: gcr = 8'hFA; 6'h3B: gcr = 8'hFB;
		6'h3C: gcr = 8'hFC; 6'h3D: gcr = 8'hFD; 6'h3E: gcr = 8'hFE; default: gcr = 8'hFF;
	endcase
endfunction

// physical sector -> logical sector of the image: DOS 3.3 order, ProDOS order
function [3:0] dos_sec;
	input [3:0] p;
	case (p)
		4'h0: dos_sec = 4'h0; 4'h1: dos_sec = 4'h7; 4'h2: dos_sec = 4'hE; 4'h3: dos_sec = 4'h6;
		4'h4: dos_sec = 4'hD; 4'h5: dos_sec = 4'h5; 4'h6: dos_sec = 4'hC; 4'h7: dos_sec = 4'h4;
		4'h8: dos_sec = 4'hB; 4'h9: dos_sec = 4'h3; 4'hA: dos_sec = 4'hA; 4'hB: dos_sec = 4'h2;
		4'hC: dos_sec = 4'h9; 4'hD: dos_sec = 4'h1; 4'hE: dos_sec = 4'h8; default: dos_sec = 4'hF;
	endcase
endfunction

function [3:0] po_sec;
	input [3:0] p;
	po_sec = p[0] ? { 1'b1, p[3:1] } : { 1'b0, p[3:1] };   // 0 8 1 9 2 A 3 B ...
endfunction

function [1:0] sw2;
	input [1:0] b;
	sw2 = { b[0], b[1] };
endfunction

// ------------------------------------------------------------------ the page buffer (sector images)

reg [7:0] page [0:255];
reg [7:0] pa_i = 8'd0;           // the byte of the data field
reg [6:0] pa_j = 7'd0;           // the nibble of the low bits
wire [7:0] a_idx = 8'd1 - { 1'b0, pa_j };      // (257 - j) & 255
wire [7:0] b_idx = 8'd171 - { 1'b0, pa_j };
wire [7:0] c_idx = 8'd85 - { 1'b0, pa_j };
wire [7:0] pg_a = page[a_idx];
wire [7:0] pg_b = page[b_idx];
wire [7:0] pg_c = page[c_idx];
wire [7:0] pg_i = page[pa_i];
wire [5:0] aux_j = { sw2(pg_a[1:0]), sw2(pg_b[1:0]), sw2(pg_c[1:0]) };

// ------------------------------------------------------------------ the SD side

reg [31:0] lba = 32'd0;
reg [3:0] rel_lba = 4'd0;
assign sd_lba = lba;

reg old_ack = 1'b0, old_change = 1'b0;
reg [5:0] cur_track = 6'b111111;
reg saving = 1'b0, dirty = 1'b0;
reg po = 1'b0;                   // ProDOS order

// the sector image: states
localparam S_IDLE = 4'd0, S_PROBE = 4'd1, S_SEC = 4'd2, S_EMIT = 4'd3, S_PAD = 4'd4, S_NIB = 4'd5;
reg [3:0] st = S_IDLE;
reg [3:0] psec = 4'd0;           // physical sector
reg [3:0] lsec = 4'd0;           // its logical sector in the image
reg [12:0] wa = 13'd0;           // the write address of the track buffer
reg [9:0] ep = 10'd0;            // the byte of the sector being written (0..408)
reg [5:0] last = 6'd0;           // the 6-and-2 chain
reg [7:0] eb;                    // the byte at ep
reg [4:0] probe_ok = 5'd0;

// one sector of the track buffer (dsk2nib.c): what byte ep is
wire [7:0] vol = 8'd254;
wire [7:0] trk8 = { 2'b00, cur_track };
wire [7:0] sec8 = { 4'h0, psec };
wire [7:0] sum8 = vol ^ trk8 ^ sec8;
always @* begin
	eb = 8'hFF;
	if (ep < 10'd38) eb = 8'hFF;
	else case (ep)
		10'd38: eb = 8'hD5; 10'd39: eb = 8'hAA; 10'd40: eb = 8'h96;
		10'd41: eb = { 1'b1, vol[7], 1'b1, vol[5], 1'b1, vol[3], 1'b1, vol[1] };
		10'd42: eb = { 1'b1, vol[6], 1'b1, vol[4], 1'b1, vol[2], 1'b1, vol[0] };
		10'd43: eb = { 1'b1, trk8[7], 1'b1, trk8[5], 1'b1, trk8[3], 1'b1, trk8[1] };
		10'd44: eb = { 1'b1, trk8[6], 1'b1, trk8[4], 1'b1, trk8[2], 1'b1, trk8[0] };
		10'd45: eb = { 1'b1, sec8[7], 1'b1, sec8[5], 1'b1, sec8[3], 1'b1, sec8[1] };
		10'd46: eb = { 1'b1, sec8[6], 1'b1, sec8[4], 1'b1, sec8[2], 1'b1, sec8[0] };
		10'd47: eb = { 1'b1, sum8[7], 1'b1, sum8[5], 1'b1, sum8[3], 1'b1, sum8[1] };
		10'd48: eb = { 1'b1, sum8[6], 1'b1, sum8[4], 1'b1, sum8[2], 1'b1, sum8[0] };
		10'd49: eb = 8'hDE; 10'd50: eb = 8'hAA; 10'd51: eb = 8'hEB;
		// 52..59: 8 x FF
		10'd60: eb = 8'hD5; 10'd61: eb = 8'hAA; 10'd62: eb = 8'hAD;
		// 63..148: the 86 nibbles of the low bits (aux 85 .. 0), 149..404: the 256 high parts
		10'd405: eb = gcr(last);
		10'd406: eb = 8'hDE; 10'd407: eb = 8'hAA; 10'd408: eb = 8'hEB;
		default:
			if (ep >= 10'd63 && ep < 10'd149) eb = gcr(aux_j ^ last);
			else if (ep >= 10'd149 && ep < 10'd405) eb = gcr(pg_i[7:2] ^ last);
			else eb = 8'hFF;
	endcase
end

// the track buffer port A: the SD bytes of a .NIB, or the nibbles made here
reg pa_we = 1'b0;
reg [12:0] pa_addr = 13'd0;
reg [7:0] pa_din = 8'd0;

always @(posedge clk2) begin
	old_change <= change;
	old_ack <= sd_ack;
	pa_we <= 1'b0;

	if (sd_ack) { sd_rd, sd_wr } <= 2'b00;

	if (readyi && ram_weD2 && !dsk) dirty <= 1'b1;

	// the page of a sector image: the half of the SD sector that holds the logical sector
	if (sd_buff_wr && sd_ack && st == S_SEC && sd_buff_addr[8] == lsec[0])
		page[sd_buff_addr[7:0]] <= sd_buff_dout;
	// the probe of the order: block 2 = SD sector 2
	if (sd_buff_wr && sd_ack && st == S_PROBE) begin
		if (sd_buff_addr == 9'd0) probe_ok[0] <= sd_buff_dout == 8'h00;
		if (sd_buff_addr == 9'd1) probe_ok[1] <= sd_buff_dout == 8'h00;
		if (sd_buff_addr == 9'd2) probe_ok[2] <= sd_buff_dout == 8'h03;
		if (sd_buff_addr == 9'd3) probe_ok[3] <= sd_buff_dout == 8'h00;
		if (sd_buff_addr == 9'd4) probe_ok[4] <= sd_buff_dout[7:4] == 4'hF;
	end

	if (!old_change && change) begin
		readyi <= mount;
		cur_track <= 6'b111111;
		busyi <= 1'b0;
		sd_rd <= 1'b0;
		sd_wr <= 1'b0;
		saving <= 1'b0;
		dirty <= 1'b0;
		po <= 1'b0;
		st <= (mount && dsk) ? S_PROBE : S_IDLE;
		if (mount && dsk) begin
			// block 2 of the image (the volume directory of ProDOS)
			lba <= 32'd2;
			sd_rd <= 1'b1;
			busyi <= 1'b1;
		end
	end
	else if (reset && st != S_PROBE) begin
		// (the probe of a mount goes on: its request may be taken already)
		cur_track <= 6'b111111;
		busyi <= 1'b0;
		sd_rd <= 1'b0;
		sd_wr <= 1'b0;
		saving <= 1'b0;
		dirty <= 1'b0;
		st <= S_IDLE;
	end
	else case (st)
	S_PROBE:
		if (old_ack && !sd_ack) begin
			po <= &probe_ok;
			busyi <= 1'b0;
			st <= S_IDLE;
		end

	S_SEC:
		// the SD sector of the logical sector is in: write the physical sector
		if (old_ack && !sd_ack) begin
			ep <= 10'd0;
			last <= 6'd0;
			pa_j <= 7'd85;
			pa_i <= 8'd0;
			st <= S_EMIT;
		end

	S_EMIT: begin
		pa_we <= 1'b1;
		pa_addr <= wa;
		pa_din <= eb;
		wa <= wa + 13'd1;
		ep <= ep + 10'd1;
		if (ep >= 10'd63 && ep < 10'd149) begin
			last <= aux_j;
			pa_j <= pa_j - 7'd1;
		end
		else if (ep >= 10'd149 && ep < 10'd405) begin
			last <= pg_i[7:2];
			pa_i <= pa_i + 8'd1;
		end
		if (ep == 10'd408) begin
			if (psec == 4'd15)
				st <= S_PAD;
			else begin
				psec <= psec + 4'd1;
				lsec <= po ? po_sec(psec + 4'd1) : dos_sec(psec + 4'd1);
				lba <= { 23'd0, cur_track, 3'd0 } + ((po ? po_sec(psec + 4'd1) : dos_sec(psec + 4'd1)) >> 1);
				sd_rd <= 1'b1;
				st <= S_SEC;
			end
		end
	end

	S_PAD: begin
		pa_we <= 1'b1;
		pa_addr <= wa;
		pa_din <= 8'hFF;
		wa <= wa + 13'd1;
		if (wa == 13'd6655) begin
			busyi <= 1'b0;
			st <= S_IDLE;
		end
	end

	S_NIB:
		// as floppy_track.sv
		if (old_ack && !sd_ack) begin
			if (rel_lba != 4'd12) begin
				lba <= lba + 32'd1;
				rel_lba <= rel_lba + 4'd1;
				if (saving) sd_wr <= 1'b1;
				else sd_rd <= 1'b1;
			end
			else if (saving && (cur_track != trackD2)) begin
				saving <= 1'b0;
				cur_track <= trackD2;
				rel_lba <= 4'd0;
				lba <= trackD2 * 8'd13;
				sd_rd <= 1'b1;
			end
			else begin
				busyi <= 1'b0;
				dirty <= 1'b0;
				st <= S_IDLE;
			end
		end

	default:  // S_IDLE
		if (readyi && ((cur_track != trackD2) || (old_change && !change) || (dirty && !activeD2))) begin
			if (dsk) begin
				// a sector image: the track from its physical sector 0
				cur_track <= trackD2;
				psec <= 4'd0;
				lsec <= 4'd0;
				wa <= 13'd0;
				lba <= { 23'd0, trackD2, 3'd0 };
				sd_rd <= 1'b1;
				busyi <= 1'b1;
				dirty <= 1'b0;
				st <= S_SEC;
			end
			else if (dirty && cur_track != 6'b111111) begin
				saving <= 1'b1;
				lba <= cur_track * 8'd13;
				rel_lba <= 4'd0;
				sd_wr <= 1'b1;
				busyi <= 1'b1;
				st <= S_NIB;
			end
			else begin
				saving <= 1'b0;
				cur_track <= trackD2;
				rel_lba <= 4'd0;
				lba <= trackD2 * 8'd13;
				sd_rd <= 1'b1;
				busyi <= 1'b1;
				dirty <= 1'b0;
				st <= S_NIB;
			end
		end
	endcase
end

// the track buffer: port A on clk2 (the SD bytes of a .NIB at {rel_lba, addr}, or the nibbles of a
// sector image), port B the Apple
wire nib_we = sd_buff_wr & sd_ack & (st == S_NIB);
wire [12:0] a_addr = pa_we ? pa_addr : { rel_lba, sd_buff_addr };

Gowin_DPB_trkbuf trkbuf (
	.clka(clk2),
	.dina(nib_we ? sd_buff_dout : pa_din),
	.douta(sd_buff_din),
	.ada(a_addr),
	.wrea(nib_we | pa_we),
	.ocea(1'b1),
	.cea(1'b1),
	.reseta(1'b0),
	.clkb(clk),
	.dinb(ram_di),
	.doutb(ram_do),
	.adb(ram_addr),
	.wreb(ram_we & !dsk),
	.oceb(1'b1),
	.ceb(1'b1),
	.resetb(1'b0)
);

endmodule
