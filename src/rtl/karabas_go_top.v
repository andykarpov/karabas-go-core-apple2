`timescale 1ns / 1ps
`default_nettype wire

/*
 Apple //e core for Karabas Go (VGA, PCM5102). The same as karabas_minig_top.v except the pins, the
 MCU link (MCU_SCK not on a clock pin) and the video: 24 bit RGB to the VGA DAC, the pixel clock on
 V_CLK, the FT812 off that bus (FT_OE_N = 1). The floppy connector is not used (its outputs 0: the
 Disk II is not a Shugart drive). The NanoApple2 machine (apple2_top) with the board glue of core-rk,
 MCU link v2 (kg_mcu2) and core-atarist (img_sdc).

 All file work goes through the firmware: the disk images of the F items of core.json through
 the mounter of kg_mcu2 (slot 0 / 1 the drives of the Disk II in slot 6, .nib; slot 2 the HDD in slot 7, .hdv).
 The ROMs are in the bitstream.

 Clocks: one PLL, VCO 1000 MHz (50 * 20): clk_sys 28.571 MHz (/35: the mcu, img_sdc, the SD side
 of the machine, audio), clk_core 14.286 MHz (/70: the machine, 0.2 % under the 14.318 of NTSC),
 clk_pix 25.0 MHz (/40: 640 x 480 at 60 Hz out of the frame buffer apple2_fb, the OSD, V_CLK).

 Memory: the 64K main + 64K aux RAM in the SRAM (apple2_sram: main the low lane, aux the high one).

 Soft switches (the index of the item in the osd of core.json, file items included):
   0 Disk 1 (F 0)   1 Disk 2 (F 1)   2 Hard disk (F 2)   3 CPU (65C02 / 6502)
   4 Monitor (Color / B&W / Green / Amber)   5 Palette   6 Mockingboard   7 Mouse
   8 Reset   9 Serial (Off / USB UART / ESP Wi-Fi)   10 ESP bit 7 (Clear / Keep)
 (the menu shows Serial before Reset: core.json pins "index" on both)
 Reset (F12) is a power on reset of the //e (the boot from the disk); Ctrl + Pause is Ctrl+Reset.

 Serial: the Super Serial Card (slot 2) on the uart of the firmware (kg_mcu2 port 0, apple2_ser:
 the USB CDC port, the speed of the Apple goes to the firmware) or on the ESP module of the board
 (UART_RX / UART_TX / UART_CTS, 115200; ESP_RESET_N / ESP_BOOT_N left to the module: Z).
*/

module karabas_go_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	output wire [7:0] VGA_R,
	output wire [7:0] VGA_G,
	output wire [7:0] VGA_B,
	output wire VGA_HS,
	output wire VGA_VS,
	output wire V_CLK,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,

	output wire DAC_LRCK,
	output wire DAC_DAT,
	output wire DAC_BCK,
	output wire DAC_MUTE,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,
	inout wire [1:0] MCU_SPI_IO, // [0] INT of link v2 (firmware IO1, GPIO2), [1] unused (IO0, GPIO14)

	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign SDR_BA = 2'b11;
assign SDR_A = 13'h1FFF;
assign SDR_CLK = 1'b1;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign MIDI_TX = 1'b1;
assign MIDI_CLK = 1'b1;
assign MIDI_RESET_N = 1'b1;
assign FT_OE_N = 1'b1;     // the FT812 does not drive the video DAC
assign BEEPER = 1'b0;

// the floppy connector is not used: its outputs 0 (the board inverts them: high = active)
assign FDC_DRIVE = 2'b00;
assign FDC_MOTOR = 1'b0;
assign FDC_DIR = 1'b0;
assign FDC_STEP = 1'b0;
assign FDC_WDATA = 1'b0;
assign FDC_WGATE = 1'b0;
assign FDC_SIDE_N = 1'b0;
assign UART_RX = 1'bz;
assign TAPE_OUT = 1'b0;

assign FLASH_CS_N = 1'b1;   // the flash chip; the SDRAM /CS is hard wired on Go
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign MRD_N = 2'b00;  // SRAM /OE: always on, apple2_sram drives MD only with /WE

// ------------------------------------------------------------------ clocks

wire clk_sys, clk_core, clk_pix;
wire locked, areset;

wire [5:0] pll_clk;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(20),     // VCO 1000 MHz
	.CLKOUT0_DIVIDE(35),    // 28.571 MHz
	.CLKOUT1_DIVIDE(70),    // 14.286 MHz
	.CLKOUT2_DIVIDE(40),    // 25.0 MHz
	.BUFG_MASK(6'b000111)
) pll (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_out(pll_clk),
	.locked(locked)
);
assign clk_sys = pll_clk[0];
assign clk_core = pll_clk[1];
assign clk_pix = pll_clk[2];
assign areset = ~locked;

// the pixel clock of the VGA DAC: clk_pix inverted, the DAC takes a pixel half a period after the
// OSD changed it (as the menu core)
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_pix), .C1(~clk_pix), .CE(1'b1), .D0(1'b0), .D1(1'b1), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

// MCU_SCK is not on a clock pin before rev.G (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)
wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;

// karabas: MCU link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on MCU_SPI_IO[0] (N9, IO1 of the firmware)
wire mcu_int;
assign MCU_SPI_IO[0] = mcu_int;
assign MCU_SPI_IO[1] = 1'bz;

wire [7:0] kb_status, kb_dat0, kb_dat1, kb_dat2, kb_dat3, kb_dat4, kb_dat5;
wire [7:0] uart_rx_data, uart_rx_idx, uart_tx_data, uart_dll, uart_dlm;
wire uart_tx_wr, uart_dll_wr, uart_dlm_wr;
wire [15:0] joy_l16, joy_r16;
wire [12:0] joy_l = joy_l16[12:0], joy_r = joy_r16[12:0];
wire [7:0] ms_x, ms_y, ms_z8, ms_b8;
wire [3:0] ms_z = ms_z8[3:0];
wire [2:0] ms_b = ms_b8[2:0];
wire ms_wr;
wire [11*8-1:0] sw;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] img_wp;
wire [31:0] port_out_data;
wire [3:0] port_out_wr;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;

// the disks: the file mounter of kg_mcu2 (kg_l2_img) has the sd card interface of img_sdc
wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
wire [31:0] sd_lba;
wire [2:0] sd_rd, sd_wr;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, sd_wr_data;
wire img_active;

// the SSC on port 0 (the uart of the firmware): its divisor in the config of the port, always
// (tx_mode 1 of v1: the mcu sends at the speed the Apple set)
wire [127:0] port_cfg = { 112'd0, uart_dlm, uart_dll };

kg_mcu2 #(
	.CAPS(16'h0004),     // write protected images
	.SW_N(11),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // the disks: slots 0, 1 (Disk II), 2 (HDD)
	.IMG_OUT_LATENCY(2),
	.ENABLE_PORTS(4'b0001),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(mcu_busy), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD({ kb_dat5, kb_dat4, kb_dat3, kb_dat2, kb_dat1, kb_dat0, kb_status }), .KBD_WR(),
	.PS2_CODE(), .PS2_KIND(), .PS2_WR(),
	.MS_X(ms_x), .MS_Y(ms_y), .MS_Z(ms_z8), .MS_B(ms_b8), .MS_WR(ms_wr),
	.JOY_L(joy_l16), .JOY_R(joy_r16), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(), .LD_SLOT(), .LD_SIZE(), .LD_START(), .LD_ACTIVE(), .LD_END(),
	.LD_ADDR(), .LD_DATA(), .LD_WR(), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
	.SDC_RD({ 5'd0, sd_rd }), .SDC_WR({ 5'd0, sd_wr }), .SDC_SECTOR(sd_lba),
	.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_byte_in_data), .SDC_BYTE_OUT_DATA(sd_wr_data),
	.IMG_WP(img_wp), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(img_active),

	.PORT_OUT_DATA(port_out_data), .PORT_OUT_WR(port_out_wr), .PORT_OUT_READY(4'b1111),
	.PORT_IN_DATA({ 24'd0, uart_tx_data }), .PORT_IN_WR({ 3'b000, uart_tx_wr }),
	.PORT_CFG(port_cfg), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(8'd0), .RTC_DI(8'd0), .RTC_CS(1'b0), .RTC_WR_N(1'b1), .MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0), .RTC_DO(),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(sd2_mosi), .SD2_MISO(SD_DO), .SD2_CS_N(sd2_cs_n)
);

// the toggles of v1 out of the pulses of v2: the mouse report (apple2_hid takes a change of
// ms_upd) and the serial byte with a counter that changes with it (apple2_ser)
reg ms_upd = 1'b0;
reg [7:0] uart_rx_data_r = 8'd0, uart_rx_idx_r = 8'd0;
always @(posedge clk_sys) begin
	if (ms_wr)
		ms_upd <= ~ms_upd;
	if (port_out_wr[0]) begin
		uart_rx_data_r <= port_out_data[7:0];
		uart_rx_idx_r <= uart_rx_idx_r + 1'b1;
	end
end
assign uart_rx_data = uart_rx_data_r;
assign uart_rx_idx = uart_rx_idx_r;

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

// the switches: the SW registers of kg_mcu2
wire sw_6502 = sw[3*8];
wire [1:0] sw_monitor = sw[4*8 +: 2];
wire [1:0] sw_palette = sw[5*8 +: 2];
wire sw_no_mb = sw[6*8];
wire sw_no_mouse = sw[7*8];
wire sw_reset = sw[8*8];
wire [1:0] sw_serial = sw[9*8 +: 2];   // 0 off, 1 the firmware uart, 2 the ESP module
wire sw_esp_bit7 = sw[10*8];            // 0 the ESP gets bit 7 cleared, 1 kept

// ------------------------------------------------------------------ HID

wire [7:0] usb_key, paddle_x, paddle_y;
wire kbd_strobe, reset_key, mouse_btn, mouse_tog;
wire [1:0] joy_btn;
wire [8:0] mouse_x, mouse_y;

apple2_hid hid (
	.clk(clk_sys),
	.kb_status(kb_status),
	.kb_dat0(kb_dat0),
	.kb_dat1(kb_dat1),
	.kb_dat2(kb_dat2),
	.kb_dat3(kb_dat3),
	.kb_dat4(kb_dat4),
	.kb_dat5(kb_dat5),
	.joy_l(joy_l),
	.joy_r(joy_r),
	.ms_x(ms_x),
	.ms_y(ms_y),
	.ms_b(ms_b),
	.ms_upd(ms_upd),
	.usb_key(usb_key),
	.kbd_strobe(kbd_strobe),
	.reset_key(reset_key),
	.paddle_x(paddle_x),
	.paddle_y(paddle_y),
	.joy_btn(joy_btn),
	.mouse_x(mouse_x),
	.mouse_y(mouse_y),
	.mouse_btn(mouse_btn),
	.mouse_tog(mouse_tog)
);

// the mouse report into clk_core: a strobe of one clock at the change of the synchronised toggle
// (the deltas are stable long before)
wire mouse_tog_core;
kg_sync mouse_sync (.clk(clk_core), .d(mouse_tog), .q(mouse_tog_core));
reg mouse_tog_core_d = 1'b0;
always @(posedge clk_core)
	mouse_tog_core_d <= mouse_tog_core;
wire mouse_strobe = mouse_tog_core != mouse_tog_core_d;

// ------------------------------------------------------------------ the machine

// reset: the PLL, Reset of the OSD (a power on: the boot ROM starts the disk); Ctrl+Reset
reg [3:0] rst_sync = 4'hF;
always @(posedge clk_core)
	rst_sync <= { rst_sync[2:0], areset | sw_reset };
wire reset_cold = rst_sync[3];
wire reset_warm;
kg_sync rk_sync (.clk(clk_core), .d(reset_key), .q(reset_warm));

wire [15:0] ram_addr, ram_dout;
wire [7:0] ram_din;
wire ram_aux, ram_we;
wire a2_video, a2_color_line, a2_hbl, a2_vbl;
wire speaker;
wire [9:0] psg_l, psg_r;
wire [1:0] disk_active;

// ------------------------------------------------------------------ serial (SSC)

wire ssc_on = sw_serial != 2'd0;
wire ssc_esp = sw_serial == 2'd2;
wire ssc_bytes = !ssc_esp;
wire ssc_tx, ssc_rts_n, ser_out_strobe, ser_in_strobe;
wire [7:0] ser_out_avail, ser_out_data, ser_in_data;
wire [31:0] ser_status;

apple2_top machine (
	.clk_core(clk_core),
	.clk_sys(clk_sys),
	.reset_cold(reset_cold),
	.reset_warm(reset_warm),
	.cpu_type(~sw_6502),
	.romswitch(1'b1),        // the US character set (upstream default)
	.color_text(1'b0),
	.mono(sw_monitor != 2'b00),
	.mb_en(~sw_no_mb),
	.mouse_en(~sw_no_mouse),
	.ssc_en(sw_serial != 2'd0),
	.ssc_irq_en(sw_serial == 2'd2),   // the byte 6551 has no interrupt
	.ssc_bytes(ssc_bytes),
	.ssc_tx_7bit(!sw_esp_bit7),
	.hdd_en(1'b1),
	.floppy_wp(img_wp[1:0]),
	.hdd_wp(img_wp[2]),
	.ram_addr(ram_addr),
	.ram_aux(ram_aux),
	.ram_we(ram_we),
	.ram_din(ram_din),
	.ram_dout(ram_dout),
	.video(a2_video),
	.color_line(a2_color_line),
	.hbl(a2_hbl),
	.vbl(a2_vbl),
	.speaker(speaker),
	.psg_l(psg_l),
	.psg_r(psg_r),
	.usb_key(usb_key),
	.kbd_strobe(kbd_strobe),
	.soft_reset(),
	.paddle_x(paddle_x),
	.paddle_y(paddle_y),
	.joy_btn(joy_btn),
	.mouse_strobe(mouse_strobe),
	.mouse_x(mouse_x),
	.mouse_y(mouse_y),
	.mouse_btn(mouse_btn),
	.img_mounted(sdc_img_mounted[2:0]),
	.img_size(sdc_img_size[31:0]),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_busy(sdc_busy),
	.sd_slot(sdc_slot),
	.sd_byte_index(sdc_byte_addr),
	.sd_rd_data(sdc_byte_in_data),
	.sd_rd_byte_strobe(sdc_byte_in_strobe),
	.sd_wr_data(sd_wr_data),
	.uart_rx(ssc_esp ? UART_RX : 1'b1),
	.uart_tx(ssc_tx),
	.uart_rts_n(ssc_rts_n),
	.ser_out_avail(ser_out_avail),
	.ser_out_data(ser_out_data),
	.ser_out_strobe(ser_out_strobe),
	.ser_status(ser_status),
	.ser_in_strobe(ser_in_strobe),
	.ser_in_data(ser_in_data),
	.disk_active(disk_active)
);

// the ESP module: driven only in its mode (UART_CTS low = the module may send)
assign UART_TX = ssc_esp ? ssc_tx : 1'bz;
assign UART_CTS = ssc_esp ? ssc_rts_n : 1'bz;

apple2_ser ser (
	.clk(clk_sys),
	.en(ssc_bytes && ssc_on),
	.out_avail(ser_out_avail),
	.out_data(ser_out_data),
	.out_strobe(ser_out_strobe),
	.status(ser_status),
	.in_strobe(ser_in_strobe),
	.in_data(ser_in_data),
	.uart_rx_data(uart_rx_data),
	.uart_rx_idx(uart_rx_idx),
	.uart_tx_data(uart_tx_data),
	.uart_tx_wr(uart_tx_wr),
	.uart_dll(uart_dll),
	.uart_dll_wr(uart_dll_wr),
	.uart_dlm(uart_dlm),
	.uart_dlm_wr(uart_dlm_wr)
);

wire [15:0] md_out;
wire [1:0] md_oe;
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
assign MD[7:0] = md_oe[0] ? md_out[7:0] : 8'bzzzzzzzz;
assign MD[15:8] = md_oe[1] ? md_out[15:8] : 8'bzzzzzzzz;

// ------------------------------------------------------------------ video

wire [23:0] video_rgb;
wire video_hs, video_vs, video_de;

apple2_fb fb (
	.clk_core(clk_core),
	.video(a2_video),
	.color_line(a2_color_line),
	.hbl(a2_hbl),
	.vbl(a2_vbl),
	.screen_mode(sw_monitor),
	.palette(sw_palette),
	.clk_pix(clk_pix),
	.rgb(video_rgb),
	.hs(video_hs),
	.vs(video_vs),
	.de(video_de)
);

// the bitmap OSD of link v2 (kg_l2_osd_overlay): written on clk_sys, shown on clk_pix, centred in
// de, 2 clocks of latency with its syncs and de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk_sys),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_pix),
	.rgb_i(video_rgb), .hs_i(video_hs), .vs_i(video_vs), .de_i(video_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

// ------------------------------------------------------------------ audio

// the speaker (a square wave) and the two PSG channels of the Mockingboard on clk_sys. mockingboard.vhd
// gives the sum of its three channels (0..765) minus 512 as 10 bits: adding 512 back gives the sum,
// 0 in silence (as a signed number the silence was -512, a large DC step when the card starts)
reg [2:0] spk_s = 3'd0;
reg [9:0] psg_l_s = 10'd0, psg_r_s = 10'd0, psg_l_q = 10'd0, psg_r_q = 10'd0;
always @(posedge clk_sys) begin
	spk_s <= { spk_s[1:0], speaker };
	psg_l_q <= psg_l;
	psg_r_q <= psg_r;
	psg_l_s <= psg_l_q;
	psg_r_s <= psg_r_q;
end
wire signed [15:0] spk16 = spk_s[2] ? 16'sd6000 : -16'sd6000;
wire [9:0] psg_l_u = psg_l_s + 10'h200;
wire [9:0] psg_r_u = psg_r_s + 10'h200;
wire signed [15:0] mb_l = sw_no_mb ? 16'sd0 : { 2'b00, psg_l_u, 4'd0 };
wire signed [15:0] mb_r = sw_no_mb ? 16'sd0 : { 2'b00, psg_r_u, 4'd0 };
wire signed [16:0] mix_l = spk16 + mb_l;
wire signed [16:0] mix_r = spk16 + mb_r;
wire [15:0] aud_l = (mix_l[16] != mix_l[15]) ? { mix_l[16], { 15{ !mix_l[16] } } } : mix_l[15:0];
wire [15:0] aud_r = (mix_r[16] != mix_r[15]) ? { mix_r[16], { 15{ !mix_r[16] } } } : mix_r[15:0];

kg_pcm5102 #(.DIV_BITS(2)) dac (  // bck 3.6 MHz, 111 kHz
	.clk(clk_sys),
	.reset(areset),
	.left(aud_l),
	.right(aud_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_LRCK)
);
assign DAC_MUTE = 1'b1;  // soft mute of the PCM5102: 1 = sound on

// ------------------------------------------------------------------ VGA

// 640 x 480: negative syncs. The output of the OSD is a logic path (11 levels): the pixels and the
// syncs are registered on clk_pix (one pixel later, all together) for the half period to the DAC
reg [23:0] vga_rgb = 24'd0;
reg vga_hs = 1'b1, vga_vs = 1'b1;
always @(posedge clk_pix) begin
	vga_rgb <= osd_rgb;
	vga_hs <= ~osd_hs;   // the syncs of the overlay: in step with osd_rgb
	vga_vs <= ~osd_vs;
end
assign VGA_R = vga_rgb[23:16];
assign VGA_G = vga_rgb[15:8];
assign VGA_B = vga_rgb[7:0];
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;

endmodule
