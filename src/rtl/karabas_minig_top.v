`timescale 1ns / 1ps
`default_nettype wire

/*
 Apple //e core for Karabas Mini rev.G (HDMI, PCM5102): the NanoApple2 machine (apple2_top) with
 the board glue of core-rk (mcu, OSD, HDMI) and core-atarist (img_sdc).

 All file work goes through the firmware: the disk images of the F items of core.json through
 img_sdc (slot 0 / 1 the drives of the Disk II in slot 6, .nib; slot 2 the HDD in slot 7, .hdv).
 The ROMs are in the bitstream.

 Clocks: one PLL, VCO 1000 MHz (50 * 20): clk_sys 28.571 MHz (/35: the mcu, img_sdc, the SD side
 of the machine, audio), clk_core 14.286 MHz (/70: the machine, 0.2 % under the 14.318 of NTSC),
 clk_pix 25.0 MHz (/40: 640 x 480 at 60 Hz out of the frame buffer apple2_fb, the OSD, HDMI) and
 clk_8 8.0 MHz (/125: FT_CLK_OUT); a DCM makes the 125 MHz of the HDMI serialiser from clk_pix.

 Memory: the 64K main + 64K aux RAM in the SRAM (apple2_sram: main the low lane, aux the high one).

 Soft switches (the index of the item in the osd of core.json, file items included):
   0 Disk 1 (F 0)   1 Disk 2 (F 1)   2 Hard disk (F 2)   3 CPU (65C02 / 6502)
   4 Monitor (Color / B&W / Green / Amber)   5 Palette   6 Mockingboard   7 Mouse
   8 Reset   9 Serial (Off / USB UART / ESP Wi-Fi)   10 ESP bit 7 (Clear / Keep)
 (the menu shows Serial before Reset: core.json pins "index" on both)
 Reset (F12) is a power on reset of the //e (the boot from the disk); Ctrl + Pause is Ctrl+Reset.

 Serial: the Super Serial Card (slot 2) on the uart of the firmware (kg_mcu CMD_UART, apple2_ser:
 the USB CDC port, the speed of the Apple goes to the firmware) or on the ESP module of the board
 (UART_RX / UART_TX / UART_CTS, 115200; Mini G: ESP32-S3 without the reset / boot lines).
*/

module karabas_minig_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,

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

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

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

assign ESP32_SPI_CS_N = 1'b1;
assign MIDI_TX = 1'b1;
assign UART_RX = 1'bz;
assign TAPE_OUT = 1'b0;

// Mini G2: T3 (FLASH_CS_N) is the ~CS of the SDRAM; 0 on both revisions (CLAUDE.md)
assign FLASH_CS_N = 1'b0;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;

assign MRD_N = 2'b00;  // SRAM /OE: always on, apple2_sram drives MD only with /WE

// ------------------------------------------------------------------ clocks

wire clk_sys, clk_core, clk_pix, clk_8;
wire locked, lockedx5, areset;
wire clk_hdmi, clk_hdmi_n;

wire [5:0] pll_clk;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(20),     // VCO 1000 MHz
	.CLKOUT0_DIVIDE(35),    // 28.571 MHz
	.CLKOUT1_DIVIDE(70),    // 14.286 MHz
	.CLKOUT2_DIVIDE(40),    // 25.0 MHz
	.CLKOUT3_DIVIDE(125),   // 8.0 MHz
	.BUFG_MASK(6'b001111)
) pll (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_out(pll_clk),
	.locked(locked)
);
assign clk_sys = pll_clk[0];
assign clk_core = pll_clk[1];
assign clk_pix = pll_clk[2];
assign clk_8 = pll_clk[3];
assign areset = ~locked;

kg_dcm #(
	.CLKIN_PERIOD(40.0),
	.CLKFX_MULTIPLY(5),
	.CLKFX_DIVIDE(1)
) pllx5 (
	.clk_in(clk_pix),
	.rst(areset),
	.clk_fx(clk_hdmi),
	.clk_fx180(clk_hdmi_n),
	.clk_0(),
	.locked(lockedx5)
);

// the clock of the FT812
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

// MCU_SCK on a global buffer (as tsconf and the menu: on local routing the flip-flops of the SPI
// receiver had several ns of clock skew); the FT812 and SD2 get the IBUFG output (a BUFG drives no pad)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));

wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire [7:0] kb_status, kb_dat0, kb_dat1, kb_dat2, kb_dat3, kb_dat4, kb_dat5;
wire [7:0] uart_rx_data, uart_rx_idx, uart_tx_data, uart_dll, uart_dlm;
wire uart_tx_wr, uart_dll_wr, uart_dlm_wr;
wire [12:0] joy_l, joy_r;
wire [7:0] ms_x, ms_y;
wire [3:0] ms_z;
wire [2:0] ms_b;
wire ms_upd;
wire rom_active, rom_wr;
wire [31:0] rom_addr;
wire [7:0] rom_data;
wire file_active, file_wr;
wire [7:0] file_slot, file_data;
wire [31:0] file_addr;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] img_mounted, img_data, img_result, img_wp;
wire [63:0] img_size;
wire img_data_wr, img_result_wr, img_q_wr, img_q_ack;
wire [8:0] img_data_addr;
wire [15:0] img_sum;
wire [23:0] img_q_di;
wire [7:0] rtc_a, rtc_do;

kg_mcu #(
	.BURST_MAX_MHZ(32),  // Rev.G has MCU_SCK on a global clock pin
	.CS_FILTER(3),
	.ENABLE_RTC(0),
	.ENABLE_UART(1),     // the SSC on the firmware uart
	.ENABLE_MATRIX(0),
	.ENABLE_DEBUG(0),
	.ENABLE_IMG(1),      // the disks: slots 0, 1 (Disk II), 2 (HDD)
	.ENABLE_IMG_WP(1),   // read only images: write protected disks
	.ENABLE_FILE(0),
	.FILE_CMDS(0),
	.FILE_WR_EACH(1),
	.FILE_TO_ROM(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(mcu_sck),
	.MCU_SS(MCU_CS_N),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(MCU_IO[0]),
	.MCU_BURST_READY(mcu_burst_ready),

	.KB_STATUS(kb_status),
	.KB_DAT0(kb_dat0),
	.KB_DAT1(kb_dat1),
	.KB_DAT2(kb_dat2),
	.KB_DAT3(kb_dat3),
	.KB_DAT4(kb_dat4),
	.KB_DAT5(kb_dat5),
	.KB_SCANCODE(),
	.KB_SCANCODE_UPD(),
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	.MS_X(ms_x),
	.MS_Y(ms_y),
	.MS_Z(ms_z),
	.MS_B(ms_b),
	.MS_UPD(ms_upd),

	.ROMLOADER_ACTIVE(rom_active),
	.ROMLOAD_ADDR(rom_addr),
	.ROMLOAD_DATA(rom_data),
	.ROMLOAD_WR(rom_wr),

	.FILELOAD_ACTIVE(file_active),
	.FILELOAD_ADDR(file_addr),
	.FILELOAD_DATA(file_data),
	.FILELOAD_WR(file_wr),
	.FILELOAD_SLOT(file_slot),

	.SOFTSW_COMMAND(softsw_command),
	.OSD_COMMAND(osd_command),
	.BUSY(mcu_busy),

	.FT_SPI_ON(ft_spi_on),
	.FT_CS_N(ft_cs_n),
	.FT_MOSI(ft_mosi),
	.FT_MISO(FT_SPI_MISO),
	.FT_SCK(),
	.SD2_CS_N(sd2_cs_n),
	.SD2_MOSI(sd2_mosi),
	.SD2_MISO(SD_DO),
	.SD2_SCK(),

	.DVI_ONLY(dvi_only),

	// not used by this core
	.PS2_COMMAND(16'h0000),
	.PS2_COMMAND_WR(1'b0),
	.RTC_A(rtc_a),
	.RTC_DI(8'd0),
	.RTC_DO(rtc_do),
	.RTC_CS(1'b0),
	.RTC_WR_N(1'b1),
	.UART_RX_DATA(uart_rx_data),
	.UART_RX_IDX(uart_rx_idx),
	.UART_TX_DATA(uart_tx_data),
	.UART_TX_WR(uart_tx_wr),
	.UART_TX_MODE(1'b1),   // at the dll / dlm speed
	.UART_DLM(uart_dlm),
	.UART_DLL(uart_dll),
	.UART_DLM_WR(uart_dlm_wr),
	.UART_DLL_WR(uart_dll_wr),
	.MATRIX_CMD(24'h000000),
	.MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(16'h0000),
	.DEBUG_DATA(16'h0000),
	.IMG_MOUNTED(img_mounted),
	.IMG_SIZE(img_size),
	.IMG_WP(img_wp),
	.IMG_DATA_WR(img_data_wr),
	.IMG_DATA_ADDR(img_data_addr),
	.IMG_DATA(img_data),
	.IMG_RESULT_WR(img_result_wr),
	.IMG_RESULT(img_result),
	.IMG_SUM(img_sum),
	.IMG_Q_WR(img_q_wr),
	.IMG_Q_DI(img_q_di),
	.IMG_Q_ACK(img_q_ack),
	.ESP_UART_RX_DATA(8'h00),
	.ESP_UART_RX_WR(1'b0),
	.FLASHBOOT_START(1'b0),
	.FLASHBOOT_COREID(5'd0)
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

wire [11*8-1:0] sw;
kg_soft_switches #(.N(11)) soft_switches (
	.clk(clk_sys),
	.command(softsw_command),
	.regs(sw),
	.upd()
);
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

// ------------------------------------------------------------------ img_sdc

wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
wire [31:0] sd_lba;
wire [2:0] sd_rd, sd_wr;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, sd_wr_data;
wire img_active;

img_sdc #(.OUT_LATENCY(2)) img_sdc (
	.clk(clk_sys),
	.reset(areset),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_data_wr(img_data_wr),
	.img_data_addr(img_data_addr),
	.img_data(img_data),
	.img_result_wr(img_result_wr),
	.img_result(img_result),
	.img_sum(img_sum),
	.img_q_wr(img_q_wr),
	.img_q_di(img_q_di),
	.img_q_ack(img_q_ack),

	.sdc_img_mounted(sdc_img_mounted),
	.sdc_img_size(sdc_img_size),
	.sdc_rd({ 5'd0, sd_rd }),
	.sdc_wr({ 5'd0, sd_wr }),
	.sdc_sector(sd_lba),
	.sdc_busy(sdc_busy),
	.sdc_done(sdc_done),
	.sdc_error(sdc_error),
	.sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(sd_wr_data),

	.active(img_active)
);

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

// the OSD commands of kg_mcu (clk_sys) into clk_pix: a word that changes is a command, it crosses
// through a fifo and comes out as a change again (as core-rk)
reg [15:0] osd_cmd_d = 16'd0;
always @(posedge clk_sys)
	osd_cmd_d <= osd_command;
wire osd_fifo_empty;
wire [15:0] osd_cmd_pix;
kg_async_fifo #(.DW(16), .AW(4)) osd_fifo (
	.wclk(clk_sys), .wreset(areset), .wr(osd_command != osd_cmd_d), .din(osd_command), .full(),
	.rclk(clk_pix), .rreset(areset), .rd(!osd_fifo_empty), .dout(osd_cmd_pix), .empty(osd_fifo_empty),
	.rcount()
);

// 640 x 480: the counters start at the leading edge of the syncs, a step is two pixels / lines;
// the picture starts 144 pixels and 35 lines after them, the OSD (512 x 416) 64 pixels and 32 lines
// into it
wire [23:0] osd_rgb;
kg_osd_overlay #(.H_OFFSET(104), .V_OFFSET(33), .H_DIV4_WIDTH(1100)) osd (
	.clk(clk_pix),
	.rgb_i(video_rgb),
	.rgb_o(osd_rgb),
	.hsync_i(video_hs),
	.vsync_i(video_vs),
	.v_offset(11'd0),
	.h_offset(11'd0),
	.osd_command(osd_cmd_pix)
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
	.lrck(DAC_WS)
);

// ------------------------------------------------------------------ HDMI

// the audio sample into clk_pix: held on clk_sys at 48 kHz (a toggle tells), taken on clk_pix at the
// change of the synchronised toggle, as core-rk. 48 kHz of 28.571 MHz (200 / 7): + 21 modulo 12500
reg [31:0] smp = 32'd0;
reg smp_tog = 1'b0;
reg [13:0] smp_acc = 14'd0;
always @(posedge clk_sys) begin
	if (smp_acc >= 14'd12500 - 14'd21) begin
		smp_acc <= smp_acc + 14'd21 - 14'd12500;
		smp <= { aud_l, aud_r };
		smp_tog <= ~smp_tog;
	end
	else
		smp_acc <= smp_acc + 14'd21;
end
wire smp_tog_pix;
kg_sync smp_sync (.clk(clk_pix), .d(smp_tog), .q(smp_tog_pix));
reg smp_tog_pix_d = 1'b0;
reg [23:0] hdmi_l = 24'd0, hdmi_r = 24'd0;
always @(posedge clk_pix) begin
	smp_tog_pix_d <= smp_tog_pix;
	if (smp_tog_pix != smp_tog_pix_d) begin
		hdmi_l <= { smp[31:16], 8'd0 };
		hdmi_r <= { smp[15:0], 8'd0 };
	end
end

// the audio sample clock of hdmi_tx: 48 kHz of 25 MHz, + 6 modulo 3125
reg [11:0] aud_acc = 12'd0;
reg aud_stb = 1'b0;
always @(posedge clk_pix) begin
	aud_stb <= 1'b0;
	if (aud_acc >= 12'd3125 - 12'd6) begin
		aud_acc <= aud_acc + 12'd6 - 12'd3125;
		aud_stb <= 1'b1;
	end
	else
		aud_acc <= aud_acc + 12'd6;
end
wire dvi_only_pix;
kg_sync dvi_sync (.clk(clk_pix), .d(dvi_only), .q(dvi_only_pix));

// 640 x 480: negative syncs
hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_pix),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(~lockedx5),
	.rgb(osd_rgb),
	.vsync(~video_vs),
	.hsync(~video_hs),
	.de(video_de),
	.audio_en(~dvi_only_pix),
	.audio_l(hdmi_l),
	.audio_r(hdmi_r),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

endmodule
