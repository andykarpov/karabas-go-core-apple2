`timescale 1ns / 1ps
`default_nettype wire

/*
 apple2_ser.v

 The Super Serial Card on the uart of the firmware (kg_mcu CMD_UART: the USB CDC port of the
 board, or a USB-UART adapter in its USB host): the byte 6551 of the upstream (glb6551 in ssc.vhd,
 wifimodem = 1) has a fifo each way on clk_sys.

 - Apple -> mcu: one byte per byte time of the speed the Apple set (10 bits), so the mcu queue
   does not overflow: the first byte of the fifo goes as uart_tx_data / uart_tx_wr (tx_mode 1:
   the mcu sends it at the dll / dlm speed), then the fifo is told it was taken.
 - mcu -> Apple: a byte is new when uart_rx_idx changes; it goes into the fifo (the firmware has
   no flow control: 15 bytes of room).
 - the speed: glb6551 gives its bitrate (serial_status_out[31:8], bytes swapped, one code off);
   the divisor of 115200 (as the 16550 of the ZX Evo RS232 that the firmware knows) goes out as dll, dlm when it
   changes and once after the start.
*/

module apple2_ser #(
	parameter CLK_HZ = 28571429
) (
	input wire clk,                // clk_sys
	input wire en,                 // the mode is on

	// glb6551 (apple2_top ser_*)
	input wire [7:0] out_avail,
	input wire [7:0] out_data,
	output reg out_strobe = 1'b0,
	input wire [31:0] status,
	output reg in_strobe = 1'b0,
	output reg [7:0] in_data = 8'd0,

	// kg_mcu
	input wire [7:0] uart_rx_data,
	input wire [7:0] uart_rx_idx,
	output reg [7:0] uart_tx_data = 8'd0,
	output reg uart_tx_wr = 1'b0,
	output reg [7:0] uart_dll = 8'd0,
	output reg uart_dll_wr = 1'b0,
	output reg [7:0] uart_dlm = 8'd0,
	output reg uart_dlm_wr = 1'b0
);

localparam BIT_115200 = CLK_HZ / 115200;   // clocks of one bit at 115200

wire [23:0] bitrate = { status[15:8], status[23:16], status[31:24] };

// glb6551 reports the speed of the code one above (its 0001 is 75, the 6551 has 50 there): the
// divisor is that of the real speed of the code, as gen_uart_mos_6551 (the ESP mode) runs it
reg [11:0] div;
always @* begin
	case (bitrate)
	24'd38400: div = 12'd6;      // code F: 19200
	24'd19200: div = 12'd12;     // E: 9600
	24'd9600:  div = 12'd16;     // D: 7200
	24'd7200:  div = 12'd24;     // C: 4800
	24'd4800:  div = 12'd32;     // B: 3600
	24'd3600:  div = 12'd48;     // A: 2400
	24'd2400:  div = 12'd64;     // 9: 1800
	24'd1800:  div = 12'd96;     // 8: 1200
	24'd1200:  div = 12'd192;    // 7: 600
	24'd600:   div = 12'd384;    // 6: 300
	24'd300:   div = 12'd768;    // 5: 150
	24'd150:   div = 12'd856;    // 4: 134.58
	24'd134:   div = 12'd1048;   // 3: 109.92
	24'd109:   div = 12'd1536;   // 2: 75
	24'd75:    div = 12'd2304;   // 1: 50
	default:   div = 12'd1;      // 0: 16 x the external clock, 115200 here
	endcase
end

// ---------------------------------------------------------------- the speed
reg [11:0] div_sent = 12'd0;
reg [1:0] spd = 2'd0;
always @(posedge clk) begin
	uart_dll_wr <= 1'b0;
	uart_dlm_wr <= 1'b0;
	case (spd)
	2'd0: if (en && div != div_sent) begin
		div_sent <= div;
		uart_dll <= div[7:0];
		uart_dll_wr <= 1'b1;
		spd <= 2'd1;
	end
	2'd1: spd <= 2'd2;                 // the dll and the dlm on different clocks
	2'd2: begin
		uart_dlm <= { 4'd0, div_sent[11:8] };
		uart_dlm_wr <= 1'b1;
		spd <= 2'd0;
	end
	default: spd <= 2'd0;
	endcase
end

// ---------------------------------------------------------------- Apple -> mcu
reg [11:0] bit_cnt = 12'd0;        // clocks of one bit at 115200
reg [15:0] bits = 16'd0;           // bits at 115200 still to wait
always @(posedge clk) begin
	uart_tx_wr <= 1'b0;
	out_strobe <= 1'b0;
	if (bits != 16'd0) begin
		if (bit_cnt == BIT_115200 - 1) begin
			bit_cnt <= 12'd0;
			bits <= bits - 16'd1;
		end
		else
			bit_cnt <= bit_cnt + 12'd1;
	end
	else if (en && out_avail != 8'd0 && spd == 2'd0) begin
		uart_tx_data <= out_data;
		uart_tx_wr <= 1'b1;
		out_strobe <= 1'b1;            // io_fifo steps on the rising edge, two clocks later
		bits <= div_sent * 4'd10;
		bit_cnt <= 12'd0;
	end
end

// ---------------------------------------------------------------- mcu -> Apple
reg [7:0] rx_idx_d = 8'd0;
always @(posedge clk) begin
	rx_idx_d <= uart_rx_idx;
	in_strobe <= 1'b0;
	if (uart_rx_idx != rx_idx_d && en) begin
		in_data <= uart_rx_data;
		in_strobe <= 1'b1;
	end
end

endmodule
