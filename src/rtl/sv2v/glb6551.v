module glb6551 (
	RESET_N,
	CLK,
	RX_CLK,
	RX_CLK_IN,
	XTAL_CLK_IN,
	PH_2,
	DI,
	DO,
	IRQ,
	CS,
	RW_N,
	RS,
	TXDATA_OUT,
	RXDATA_IN,
	RTS,
	CTS,
	DCD,
	DTR,
	DSR,
	clk_sys,
	serial_data_out_available,
	serial_data_in_free,
	serial_strobe_out,
	serial_data_out,
	serial_status_out,
	serial_strobe_in,
	serial_data_in
);
	input RESET_N;
	input CLK;
	output wire RX_CLK;
	input RX_CLK_IN;
	input XTAL_CLK_IN;
	input PH_2;
	input [7:0] DI;
	output wire [7:0] DO;
	output wire IRQ;
	input [1:0] CS;
	input RW_N;
	input [1:0] RS;
	output wire TXDATA_OUT;
	input RXDATA_IN;
	output wire RTS;
	input CTS;
	input DCD;
	output wire DTR;
	input DSR;
	input clk_sys;
	output wire [7:0] serial_data_out_available;
	output wire [7:0] serial_data_in_free;
	input serial_strobe_out;
	output wire [7:0] serial_data_out;
	output wire [31:0] serial_status_out;
	input serial_strobe_in;
	input [7:0] serial_data_in;
	wire [7:0] STATUS_REG;
	reg [7:0] CTL_REG = 8'd0;
	reg [7:0] CMD_REG = 8'd0;
	reg OVERRUN = 1'b0;
	reg FRAME = 1'b0;
	reg PARITY = 1'b0;
	reg TDRE;
	reg RDRF;
	wire [1:0] WORD_SELECT;
	wire PAR_DIS;
	wire [3:0] serial_data_in_space;
	assign serial_data_in_free = {4'h0, serial_data_in_space};
	wire serial_data_out_fifo_full;
	wire write = ((PH_2 && (CS == 2'b01)) && !RW_N) && (RS == 2'b00);
	wire read = ((PH_2 && (CS == 2'b01)) && RW_N) && (RS == 2'b00);
	assign serial_data_out_available[7:4] = 4'h0;
	assign RX_CLK = 1'b0;
	io_fifo uart_out_fifo(
		.reset(~RESET_N),
		.in_clk(CLK),
		.in(DI),
		.in_strobe(write),
		.in_enable(1'b0),
		.out_clk(clk_sys),
		.out(serial_data_out),
		.out_strobe(serial_strobe_out),
		.out_enable(1'b0),
		.space(),
		.used(serial_data_out_available[3:0]),
		.empty(),
		.full(serial_data_out_fifo_full)
	);
	reg serial_cpu_data_read;
	wire [7:0] serial_data_in_cpu;
	wire serial_data_in_empty;
	wire uart_rx_busy;
	reg uart_rx_busyD;
	always @(posedge CLK) uart_rx_busyD <= uart_rx_busy;
	wire uart_rx_busy_ends = !uart_rx_busy && uart_rx_busyD;
	reg out_enableD;
	reg out_enable;
	always @(posedge CLK) begin
		out_enableD <= !serial_data_in_empty && uart_rx_busy_ends;
		out_enable <= out_enableD;
	end
	io_fifo uart_in_fifo(
		.reset(~RESET_N),
		.in_clk(clk_sys),
		.in(serial_data_in),
		.in_strobe(serial_strobe_in),
		.in_enable(1'b0),
		.out_clk(CLK),
		.out(serial_data_in_cpu),
		.out_strobe(1'b0),
		.out_enable(out_enable),
		.space(serial_data_in_space),
		.used(),
		.empty(serial_data_in_empty),
		.full()
	);
	always @(posedge clk_sys) begin : sv2v_autoblock_1
		reg readD;
		reg readD1;
		readD <= read;
		readD1 <= readD;
		serial_cpu_data_read <= 1'b0;
		if (!readD1 && readD)
			serial_cpu_data_read <= 1'b1;
	end
	wire [23:0] bitrate = (CTL_REG[3:0] == 4'hf ? 24'd38400 : (CTL_REG[3:0] == 4'he ? 24'd19200 : (CTL_REG[3:0] == 4'hd ? 24'd9600 : (CTL_REG[3:0] == 4'hc ? 24'd7200 : (CTL_REG[3:0] == 4'hb ? 24'd4800 : (CTL_REG[3:0] == 4'ha ? 24'd3600 : (CTL_REG[3:0] == 4'h9 ? 24'd2400 : (CTL_REG[3:0] == 4'h8 ? 24'd1800 : (CTL_REG[3:0] == 4'h7 ? 24'd1200 : (CTL_REG[3:0] == 4'h6 ? 24'd600 : (CTL_REG[3:0] == 4'h5 ? 24'd300 : (CTL_REG[3:0] == 4'h4 ? 24'd150 : (CTL_REG[3:0] == 4'h3 ? 24'd134 : (CTL_REG[3:0] == 4'h2 ? 24'd109 : (CTL_REG[3:0] == 4'h1 ? 24'd75 : 24'd230400)))))))))))))));
	wire [3:0] databits = 4'd8;
	wire [1:0] parity = 2'h0;
	wire [1:0] stopbits = 2'h0;
	assign serial_status_out = {bitrate[7:0], bitrate[15:8], bitrate[23:16], databits, parity, stopbits};
	wire [7:0] timerd_set_data = (CTL_REG[3:0] == 4'hf ? 8'h01 : (CTL_REG[3:0] == 4'he ? 8'h02 : (CTL_REG[3:0] == 4'hd ? 8'h04 : (CTL_REG[3:0] == 4'hc ? 8'h05 : (CTL_REG[3:0] == 4'hb ? 8'h08 : (CTL_REG[3:0] == 4'ha ? 8'h0a : (CTL_REG[3:0] == 4'h9 ? 8'h10 : (CTL_REG[3:0] == 4'h8 ? 8'h16 : (CTL_REG[3:0] == 4'h7 ? 8'h20 : (CTL_REG[3:0] == 4'h6 ? 8'h40 : (CTL_REG[3:0] == 4'h5 ? 8'h80 : (CTL_REG[3:0] == 4'h4 ? 8'h40 : (CTL_REG[3:0] == 4'h3 ? 8'h48 : (CTL_REG[3:0] == 4'h2 ? 8'h50 : (CTL_REG[3:0] == 4'h1 ? 8'hbe : 8'h01)))))))))))))));
	wire [10:0] uart_prediv = (CTL_REG[3:0] == 4'hf ? 11'd30 : (CTL_REG[3:0] == 4'he ? 11'd30 : (CTL_REG[3:0] == 4'hd ? 11'd30 : (CTL_REG[3:0] == 4'hc ? 11'd30 : (CTL_REG[3:0] == 4'hb ? 11'd30 : (CTL_REG[3:0] == 4'ha ? 11'd30 : (CTL_REG[3:0] == 4'h9 ? 11'd30 : (CTL_REG[3:0] == 4'h8 ? 11'd30 : (CTL_REG[3:0] == 4'h7 ? 11'd30 : (CTL_REG[3:0] == 4'h6 ? 11'd30 : (CTL_REG[3:0] == 4'h5 ? 11'd30 : (CTL_REG[3:0] == 4'h4 ? 11'd120 : (CTL_REG[3:0] == 4'h3 ? 11'd120 : (CTL_REG[3:0] == 4'h2 ? 11'd120 : (CTL_REG[3:0] == 4'h1 ? 11'd120 : 11'd30)))))))))))))));
	reg [15:0] uart_rx_prediv_cnt;
	reg [15:0] uart_tx_prediv_cnt;
	reg [7:0] uart_tx_delay_cnt;
	wire uart_tx_busy = uart_tx_delay_cnt != 8'd0;
	reg [7:0] uart_rx_delay_cnt;
	assign uart_rx_busy = uart_rx_delay_cnt != 8'd0;
	wire serial_data_in_available = (!serial_data_in_empty && !uart_rx_busy) && !uart_rx_busyD;
	always @(posedge clk_sys) begin : sv2v_autoblock_2
		reg writeD;
		reg writeD1;
		writeD <= write;
		writeD1 <= writeD;
		if (XTAL_CLK_IN) begin
			if (uart_rx_prediv_cnt != 16'd0)
				uart_rx_prediv_cnt <= uart_rx_prediv_cnt - 16'd1;
			else begin
				uart_rx_prediv_cnt <= {uart_prediv - 11'd1, 5'b00000};
				if (uart_rx_delay_cnt != 8'd0)
					uart_rx_delay_cnt <= uart_rx_delay_cnt - 8'd1;
			end
			if (uart_tx_prediv_cnt != 16'd0)
				uart_tx_prediv_cnt <= uart_tx_prediv_cnt - 16'd1;
			else begin
				uart_tx_prediv_cnt <= {uart_prediv - 11'd1, 5'b00000};
				if (uart_tx_delay_cnt != 8'd0)
					uart_tx_delay_cnt <= uart_tx_delay_cnt - 8'd1;
			end
		end
		if (serial_cpu_data_read && serial_data_in_available) begin
			uart_rx_delay_cnt <= timerd_set_data;
			uart_rx_prediv_cnt <= {uart_prediv - 11'd1, 5'b00000};
		end
		if (!writeD1 && writeD) begin
			uart_tx_delay_cnt <= timerd_set_data;
			uart_tx_prediv_cnt <= {uart_prediv - 11'd1, 5'b00000};
		end
	end
	wire uart_rx_irq = serial_data_in_available;
	wire uart_tx_irq = !serial_data_out_fifo_full && !serial_strobe_out;
	assign TXDATA_OUT = 1'b1;
	wire [1:1] sv2v_tmp_12F25;
	assign sv2v_tmp_12F25 = !serial_data_out_fifo_full && !uart_tx_busy;
	always @(*) TDRE = sv2v_tmp_12F25;
	wire [1:1] sv2v_tmp_93296;
	assign sv2v_tmp_93296 = (CMD_REG[1] ? serial_data_in_available : serial_data_in_available && ~RTS);
	always @(*) RDRF = sv2v_tmp_93296;
	assign STATUS_REG = {!IRQ, DSR, DCD, TDRE, RDRF, OVERRUN, FRAME, PARITY};
	assign DO = (RS == 2'b00 ? serial_data_in_cpu : (RS == 2'b01 ? STATUS_REG : (RS == 2'b10 ? CMD_REG : CTL_REG)));
	assign IRQ = ({CMD_REG[1:0], RDRF} == 3'b011 ? 1'b0 : ({CMD_REG[3:2], CMD_REG[0], TDRE} == 4'b0111 ? 1'b0 : 1'b1));
	assign RTS = CMD_REG[3:2] == 2'b00;
	assign DTR = ~CMD_REG[0];
	assign PAR_DIS = ~CMD_REG[5];
	assign WORD_SELECT = CTL_REG[6:5];
	reg ph2_d = 1'b0;
	reg [4:0] acc_q = 5'b11111;
	reg [7:0] di_q = 8'h00;
	always @(posedge CLK) begin
		ph2_d <= PH_2;
		if (PH_2) begin
			acc_q <= {RW_N, CS, RS};
			di_q <= DI;
		end
		if (!RESET_N || ((ph2_d && !PH_2) && (acc_q == 5'b00101))) begin
			CTL_REG <= 8'h00;
			CMD_REG <= 8'h00;
			OVERRUN <= 1'b0;
			FRAME <= 1'b0;
			PARITY <= 1'b0;
		end
		else if (ph2_d && !PH_2) begin
			if (acc_q == 5'b00110)
				CMD_REG <= di_q;
			if (acc_q == 5'b00111)
				CTL_REG <= di_q;
		end
	end
endmodule
