module floppy_track (
	clk,
	clk2,
	reset,
	sd_lba,
	sd_rd,
	sd_wr,
	sd_ack,
	sd_buff_addr,
	sd_buff_dout,
	sd_buff_din,
	sd_buff_wr,
	change,
	mount,
	track,
	ready,
	active,
	ram_addr,
	ram_do,
	ram_di,
	ram_we,
	busy
);
	input clk;
	input clk2;
	input reset;
	output wire [31:0] sd_lba;
	output reg sd_rd;
	output reg sd_wr;
	input sd_ack;
	input [8:0] sd_buff_addr;
	input [7:0] sd_buff_dout;
	output wire [7:0] sd_buff_din;
	input sd_buff_wr;
	input change;
	input mount;
	input [5:0] track;
	output wire ready;
	input active;
	input [12:0] ram_addr;
	output wire [7:0] ram_do;
	input [7:0] ram_di;
	input ram_we;
	output wire busy;
	reg readyD2;
	assign ready = readyD2;
	reg busyD2;
	assign busy = busyD2;
	reg [31:0] lba;
	assign sd_lba = lba;
	reg [3:0] rel_lba;
	reg activeD2;
	reg busyi;
	reg ram_weD2;
	reg readyi;
	reg [5:0] trackD2;
	always @(posedge clk2) begin : sv2v_autoblock_1
		reg old_ack;
		reg [5:0] cur_track;
		reg old_change;
		reg saving;
		reg dirty;
		old_change <= change;
		old_ack <= sd_ack;
		if (sd_ack)
			{sd_rd, sd_wr} <= 0;
		if (readyi && ram_weD2)
			dirty <= 1;
		if (~old_change & change) begin
			readyi <= mount;
			cur_track <= 'b111111;
			busyi <= 0;
			sd_rd <= 0;
			sd_wr <= 0;
			saving <= 0;
			dirty <= 0;
		end
		else if (reset) begin
			cur_track <= 'b111111;
			busyi <= 0;
			sd_rd <= 0;
			sd_wr <= 0;
			saving <= 0;
			dirty <= 0;
		end
		else if (busyi) begin
			if (old_ack && ~sd_ack) begin
				if (rel_lba != 4'd12) begin
					lba <= lba + 1'd1;
					rel_lba <= rel_lba + 1'd1;
					if (saving)
						sd_wr <= 1;
					else
						sd_rd <= 1;
				end
				else if (saving && (cur_track != trackD2)) begin
					saving <= 0;
					cur_track <= trackD2;
					rel_lba <= 0;
					lba <= trackD2 * 8'd13;
					sd_rd <= 1;
				end
				else begin
					busyi <= 0;
					dirty <= 0;
				end
			end
		end
		else if (readyi && (((cur_track != trackD2) || (old_change && ~change)) || (dirty && ~activeD2))) begin
			if (dirty && (cur_track != 'b111111)) begin
				saving <= 1;
				lba <= cur_track * 8'd13;
				rel_lba <= 0;
				sd_wr <= 1;
				busyi <= 1;
			end
			else begin
				saving <= 0;
				cur_track <= trackD2;
				rel_lba <= 0;
				lba <= trackD2 * 8'd13;
				sd_rd <= 1;
				busyi <= 1;
				dirty <= 0;
			end
		end
	end
	Gowin_DPB_trkbuf trkbuf_inst(
		.clka(clk2),
		.dina(sd_buff_dout),
		.douta(sd_buff_din),
		.ada({rel_lba, sd_buff_addr}),
		.wrea(sd_buff_wr & sd_ack),
		.ocea(1'b1),
		.cea(1'b1),
		.reseta(1'b0),
		.clkb(clk),
		.dinb(ram_di),
		.doutb(ram_do),
		.adb(ram_addr),
		.wreb(ram_we),
		.oceb(1'b1),
		.ceb(1'b1),
		.resetb(1'b0)
	);
	reg ram_weD;
	reg [5:0] trackD;
	reg activeD;
	always @(posedge clk2) begin : FDD_IN
		{ram_weD, ram_weD2} <= {ram_we, ram_weD};
		{trackD, trackD2} <= {track, trackD};
		{activeD, activeD2} <= {active, activeD};
	end
	reg readyD;
	reg busyD;
	always @(posedge clk) begin : FDD_OUT
		{readyD, readyD2} <= {readyi, readyD};
		{busyD, busyD2} <= {busyi, busyD};
	end
endmodule
