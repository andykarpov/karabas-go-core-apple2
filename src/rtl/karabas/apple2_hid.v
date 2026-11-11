`timescale 1ns / 1ps
`default_nettype wire

/*
 apple2_hid.v

 The USB devices of the mcu link (kg_mcu) as the inputs of the NanoApple2 machine (apple2_top).

 Keyboard: kg_mcu gives the USB report (KB_STATUS = modifier bits, KB_DAT0..5 = up to six usage
 codes). keyboard.vhd of NanoApple2 wants the key events of the MiSTeryNano HID: usb_key =
 { released, code[6:0] } with a level change of kbd_strobe per event, the modifiers as the codes
 68 + n (n = the bit of KB_STATUS: 68 left Ctrl, 69 left Shift, 6A left Alt, 6B left GUI, 6C..6F
 the right ones). A report that differs from the last one is compared with it: the codes that
 went are releases, the new ones presses, then the modifier bits. One event per GAP clocks
 (keyboard.vhd takes an event in a few clocks of 14 MHz and synchronises kbd_strobe itself).
 Ctrl + Pause (usage 48) is Ctrl+Reset of the //e (reset_key, held while pressed; AppleWin has
 Ctrl+Break for it).

 Joysticks (JOY_L | JOY_R, kg_mcu: [1] up, [2] down, [3] left, [4] right, [6] A, [7] B): the
 paddles 0 / 1 at -127 / 0 / +127 (apple2_top: signed, 0 = centre), the buttons 0 / 1 = A / B.

 Mouse: each report (ms_upd toggles) gives its deltas (x 2, y negated) and the left button to
 the AppleMouse card, which adds them to the steps still to go; mouse_tog changes with them (the
 top makes the strobe of the card on clk_core from it).
*/

module apple2_hid #(
	parameter GAP = 1024
) (
	input wire clk,                // clk_sys

	input wire [7:0] kb_status,
	input wire [7:0] kb_dat0,
	input wire [7:0] kb_dat1,
	input wire [7:0] kb_dat2,
	input wire [7:0] kb_dat3,
	input wire [7:0] kb_dat4,
	input wire [7:0] kb_dat5,

	input wire [12:0] joy_l,
	input wire [12:0] joy_r,

	input wire [7:0] ms_x,
	input wire [7:0] ms_y,
	input wire [2:0] ms_b,
	input wire ms_upd,

	output reg [7:0] usb_key = 8'h80,
	output reg kbd_strobe = 1'b0,
	output reg reset_key = 1'b0,

	output wire [7:0] paddle_x,
	output wire [7:0] paddle_y,
	output wire [1:0] joy_btn,

	output reg [8:0] mouse_x = 9'd0,
	output reg [8:0] mouse_y = 9'd0,
	output reg mouse_btn = 1'b0,
	output reg mouse_tog = 1'b0
);

// ------------------------------------------------------------------ keyboard

wire [55:0] now = { kb_status, kb_dat5, kb_dat4, kb_dat3, kb_dat2, kb_dat1, kb_dat0 };
reg [55:0] cur = 56'd0;    // the report being compared
reg [55:0] old = 56'd0;    // the report before it
reg busy = 1'b0;
reg [4:0] item = 5'd0;     // 0..5 the old codes, 6..11 the new codes, 12..19 the modifier bits
reg [15:0] gap = 16'd0;

function in_report;
	input [7:0] code;
	input [55:0] rep;
	in_report = code != 8'd0 && (code == rep[7:0] || code == rep[15:8] || code == rep[23:16] ||
		code == rep[31:24] || code == rep[39:32] || code == rep[47:40]);
endfunction

wire [7:0] old_code = old[item[2:0] * 8 +: 8];
wire [7:0] new_code = cur[(item - 5'd6) * 8 +: 8];
wire [2:0] mod_bit = item - 5'd12;
wire mod_old = old[48 + mod_bit];
wire mod_new = cur[48 + mod_bit];

// an event of the item: send (usb_key, released) or nothing
reg ev = 1'b0;
reg ev_rel = 1'b0;
reg [6:0] ev_code = 7'd0;
always @* begin
	ev = 1'b0;
	ev_rel = 1'b0;
	ev_code = 7'd0;
	if (item < 5'd6) begin
		// a code that went (codes over 7F are not keys of keyboard.vhd)
		ev = old_code != 8'd0 && !old_code[7] && !in_report(old_code, cur);
		ev_rel = 1'b1;
		ev_code = old_code[6:0];
	end
	else if (item < 5'd12) begin
		ev = new_code != 8'd0 && !new_code[7] && !in_report(new_code, old);
		ev_code = new_code[6:0];
	end
	else begin
		ev = mod_old != mod_new;
		ev_rel = !mod_new;
		ev_code = 7'h68 + mod_bit;
	end
end

always @(posedge clk) begin
	if (gap != 16'd0)
		gap <= gap - 16'd1;
	if (!busy) begin
		if (now != old) begin
			cur <= now;
			item <= 5'd0;
			busy <= 1'b1;
		end
	end
	else if (gap == 16'd0) begin
		if (ev) begin
			usb_key <= { ev_rel, ev_code };
			kbd_strobe <= ~kbd_strobe;
			gap <= GAP;
		end
		if (item == 5'd19) begin
			old <= cur;
			busy <= 1'b0;
		end
		else
			item <= item + 5'd1;
	end
	// Ctrl (left or right) + Pause
	reset_key <= (kb_status[0] || kb_status[4]) && in_report(8'h48, now);
end

// ------------------------------------------------------------------ joystick

wire [12:0] joy = joy_l | joy_r;
assign paddle_x = joy[3] ? 8'h81 : joy[4] ? 8'h7F : 8'h00;
assign paddle_y = joy[1] ? 8'h81 : joy[2] ? 8'h7F : 8'h00;
assign joy_btn = { joy[7], joy[6] };

// ------------------------------------------------------------------ mouse

reg ms_upd_d = 1'b0;
always @(posedge clk) begin
	ms_upd_d <= ms_upd;
	if (ms_upd != ms_upd_d) begin
		// x 2: the card counts one step of the Apple per two encoder steps; y: up is + for the card
		// (the PS/2 sign), down for USB
		mouse_x <= { ms_x, 1'b0 };
		mouse_y <= ms_y == 8'h80 ? 9'h0FE : 9'd0 - { ms_y, 1'b0 };
		mouse_btn <= ms_b[0];
		mouse_tog <= ~mouse_tog;
	end
end

endmodule
