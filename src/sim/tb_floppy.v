`timescale 1ns / 1ps

/*
 tb_floppy.v (iverilog, sim/run_floppy.sh)

 apple2_floppy alone with a sector image: img_sdc is modelled (busy when a request is taken,
 512 byte strobes, not busy), the head goes to the tracks of TRACKS one after the other, and after
 each load the 6656 bytes of the track buffer (port B, the Apple side) are compared with the
 reference .nib (dsk2nib.c of NanoApple2). +img= the image, +ref= the reference, +dsk=1.
*/

module tb_floppy;

reg clk = 0, clk2 = 0;
always #35 clk = ~clk;          // 14.286 MHz
always #17.5 clk2 = ~clk2;      // 28.571 MHz

reg [7:0] img [0:232959];
reg [7:0] ref [0:232959];
reg [8*256-1:0] img_name, ref_name;
integer img_size;
reg dsk;

wire [31:0] sd_lba;
wire sd_rd, sd_wr;
reg sd_ack = 0;
reg [8:0] sd_buff_addr = 0;
reg [7:0] sd_buff_dout = 0;
reg sd_buff_wr = 0;
wire [7:0] sd_buff_din;
reg change = 0, mount = 0;
reg [5:0] track = 0;
wire ready, busy;
reg [12:0] ram_addr = 0;
wire [7:0] ram_do;

apple2_floppy dut (
	.clk(clk), .clk2(clk2), .reset(1'b0),
	.sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
	.change(change), .mount(mount), .dsk(dsk), .track(track), .ready(ready), .active(1'b1),
	.ram_addr(ram_addr), .ram_do(ram_do), .ram_di(8'h00), .ram_we(1'b0), .busy(busy)
);

// img_sdc: one request at a time
integer i, reqs = 0;
always @(posedge clk2) begin
	if ((sd_rd || sd_wr) && !sd_ack) begin
		reqs = reqs + 1;
		repeat (3) @(posedge clk2);
		sd_ack <= 1;
		repeat (20) @(posedge clk2);
		for (i = 0; i < 512; i = i + 1) begin
			sd_buff_addr <= i;
			sd_buff_dout <= img[sd_lba * 512 + i];
			sd_buff_wr <= 1;
			@(posedge clk2);
			sd_buff_wr <= 0;
			@(posedge clk2);
		end
		repeat (10) @(posedge clk2);
		sd_ack <= 0;
	end
end

integer t, k, errors = 0, bad;
integer tracks [0:2];
initial begin
	if (!$value$plusargs("img=%s", img_name)) img_name = "sim/dos33master.dsk";
	if (!$value$plusargs("ref=%s", ref_name)) ref_name = "sim/build/fl/ref.nib";
	if (!$value$plusargs("dsk=%d", k)) k = 1;
	dsk = k;
	$readmemh(img_name, img);
	$readmemh(ref_name, ref);
	tracks[0] = 0; tracks[1] = 17; tracks[2] = 34;
	repeat (10) @(posedge clk2);
	mount <= 1;
	change <= 1;
	@(posedge clk2);
	change <= 0;
	for (t = 0; t < 3; t = t + 1) begin
		track <= tracks[t];
		repeat (100) @(posedge clk);
		// the probe of the mount and the load: done when busy stays low
		k = 0;
		while (k < 3000) begin
			@(posedge clk);
			k = busy ? 0 : k + 1;
		end
		bad = 0;
		for (k = 0; k < 6656; k = k + 1) begin
			ram_addr <= k;
			@(posedge clk); @(posedge clk);
			if (ram_do !== ref[tracks[t] * 6656 + k]) begin
				if (bad < 5) $display("track %0d byte %0d: %02x, want %02x", tracks[t], k, ram_do, ref[tracks[t] * 6656 + k]);
				bad = bad + 1;
			end
		end
		$display("track %0d: %0d bytes differ (%0d SD requests so far)", tracks[t], bad, reqs);
		errors = errors + bad;
	end
	if (errors == 0) $display("PASS"); else $display("FAIL");
	$finish;
end

endmodule
