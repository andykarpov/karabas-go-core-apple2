// sim_apple2.cpp: the verilator harness of tb_apple2 (the machine + RAM).
//
//   clk_sys 28.636 MHz, clk_core 14.318 MHz (every second edge of clk_sys)
//   SD card: the sector interface of img_sdc / sd_card, images 0 / 1 (floppies, .nib) and 2 (.hdv)
//   keyboard: usb_key = {released, code[6:0]} with a level change of kbd_strobe per event, the codes
//             of the MiSTeryNano HID (USB usage, modifiers 0x68 + n)
//   frames: the colour picture of vga_controller (vga_r / g / b, 14 MHz pixels) as PPM
//
// options:
//   --ms N            run N ms of machine time (default 1000)
//   --disk1 F         .nib image in drive 1 (image 0), --disk2 F (image 1), --hdd F (image 2)
//   --type-at MS TEXT type TEXT (\n = Return) from MS on, 60 ms per key
//   --ppm PREFIX      write the last frame to PREFIX.ppm (and PREFIX_<ms>.ppm every --every ms)
//   --every MS        frame interval for --ppm
//   --trace-sd        print the SD requests
#include "Vtb_apple2.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static Vtb_apple2 *top;
static uint64_t sys_cycles = 0;            // clk_sys rising edges
static const double SYS_HZ = 28636363.0;
static uint64_t ms_to_cycles(double ms) { return (uint64_t)(ms * SYS_HZ / 1000.0); }

// ---------------------------------------------------------------- SD card
struct Image { FILE *f = nullptr; long size = 0; std::string name; };
static Image img[3];
static bool trace_sd = false;

enum SdState { SD_IDLE, SD_ACK, SD_READ, SD_WRITE, SD_DONE };
static SdState sd_state = SD_IDLE;
static int sd_img = 0, sd_pos = 0, sd_wait = 0;
static uint8_t sd_buf[512];
static uint32_t sd_lba_cur = 0;

static void sd_step() {
	// called once per clk_sys cycle, after the rising edge
	top->sd_rd_byte_strobe = 0;
	switch (sd_state) {
	case SD_IDLE:
		for (int i = 2; i >= 0; i--) {
			bool rd = (top->sd_rd >> i) & 1, wr = (top->sd_wr >> i) & 1;
			if (rd || wr) {
				sd_img = i;
				sd_lba_cur = top->sd_lba;
				if (trace_sd)
					printf("[%8.3f ms] SD %s img %d lba %u\n", sys_cycles * 1000.0 / SYS_HZ, rd ? "rd" : "wr", i, sd_lba_cur);
				memset(sd_buf, 0, sizeof sd_buf);
				if (rd && img[i].f) {
					fseek(img[i].f, (long)sd_lba_cur * 512, SEEK_SET);
					size_t n = fread(sd_buf, 1, 512, img[i].f);
					(void)n;
				}
				top->sd_busy = 1;
				sd_state = rd ? SD_READ : SD_WRITE;
				sd_pos = 0;
				sd_wait = 4;
				break;
			}
		}
		break;
	case SD_READ:
		if (sd_wait) { sd_wait--; break; }
		top->sd_byte_index = sd_pos;
		top->sd_rd_data = sd_buf[sd_pos];
		top->sd_rd_byte_strobe = 1;
		sd_wait = 1;
		if (++sd_pos == 512) { sd_state = SD_DONE; sd_wait = 4; }
		break;
	case SD_WRITE:
		// index n, then its byte two clocks later (buffer latency + the mux of apple2_top)
		if (sd_wait) {
			if (sd_wait == 1 && sd_pos > 0) sd_buf[sd_pos - 1] = top->sd_wr_data;
			sd_wait--;
			break;
		}
		if (sd_pos == 512) {
			if (img[sd_img].f) {
				fseek(img[sd_img].f, (long)sd_lba_cur * 512, SEEK_SET);
				fwrite(sd_buf, 1, 512, img[sd_img].f);
				fflush(img[sd_img].f);
			}
			sd_state = SD_DONE;
			sd_wait = 4;
			break;
		}
		top->sd_byte_index = sd_pos++;
		sd_wait = 2;
		break;
	case SD_DONE:
		if (sd_wait) { sd_wait--; break; }
		top->sd_busy = 0;
		sd_state = SD_IDLE;
		break;
	default:
		break;
	}
}

// ---------------------------------------------------------------- keyboard
struct KeyEv { uint64_t at; uint8_t code; bool release; };
static std::vector<KeyEv> keys;
static size_t key_next = 0;

static void ascii_key(char c, int &code, bool &shift) {
	shift = false;
	code = -1;
	static const char *sh_digits = ")!@#$%^&*(";
	if (c >= 'a' && c <= 'z') code = 0x04 + c - 'a';
	else if (c >= 'A' && c <= 'Z') { code = 0x04 + c - 'A'; shift = true; }
	else if (c >= '1' && c <= '9') code = 0x1E + c - '1';
	else if (c == '0') code = 0x27;
	else if (c == '\n') code = 0x28;
	else if (c == ' ') code = 0x2C;
	else if (c == '-') code = 0x2D;
	else if (c == '=') code = 0x2E;
	else if (c == ',') code = 0x36;
	else if (c == '.') code = 0x37;
	else if (c == '/') code = 0x38;
	else if (c == ';') code = 0x33;
	else if (c == '"') { code = 0x34; shift = true; }
	else if (c == ':') { code = 0x33; shift = true; }
	else if (c == '$') { code = 0x21; shift = true; }
	else if (const char *p = strchr(sh_digits, c)) { code = p == sh_digits ? 0x27 : 0x1E + (int)(p - sh_digits) - 1; shift = true; }
}

static void type_text(double at_ms, const char *text) {
	uint64_t t = ms_to_cycles(at_ms);
	const uint64_t step = ms_to_cycles(30);
	for (const char *p = text; *p; p++) {
		char c = *p;
		if (c == '\\' && p[1] == 'n') { c = '\n'; p++; }
		int code; bool shift;
		ascii_key(c, code, shift);
		if (code < 0) continue;
		if (shift) { keys.push_back({t, 0x69, false}); t += step / 4; }
		keys.push_back({t, (uint8_t)code, false}); t += step;
		keys.push_back({t, (uint8_t)code, true}); t += step / 4;
		if (shift) { keys.push_back({t, 0x69, true}); t += step / 4; }
		t += step / 2;
	}
}

static void key_step() {
	if (key_next < keys.size() && sys_cycles >= keys[key_next].at) {
		const KeyEv &k = keys[key_next++];
		top->usb_key = (k.release ? 0x80 : 0) | (k.code & 0x7f);
		top->kbd_strobe = !top->kbd_strobe;
	}
}

// ---------------------------------------------------------------- frames
static const int FW = 910, FH = 262;
static std::vector<uint8_t> frame(FW * FH * 3), last(FW * FH * 3);
static int fx = 0, fy = 0, frames = 0;
static bool old_hbl = false, old_vbl = false;

static int trace_we = 0;
static uint64_t st_we = 0, st_video = 0, st_vga = 0;
static void pixel_step() {
	if (top->ram_we) {
		st_we++;
		if (trace_we > 0 && !top->reset_cold) { trace_we--; printf("[%8.3f ms] we %c %04x = %02x\n", sys_cycles * 1000.0 / SYS_HZ, top->ram_aux ? 'A' : 'M', top->ram_addr, top->ram_din); }
	}
	if (top->video) st_video++;
	if (top->vga_r | top->vga_g | top->vga_b) st_vga++;
	// on each clk_core rising edge
	bool hb = top->vga_hblank, vb = top->vga_vblank;
	if (!hb && !vb && fx < FW && fy < FH) {
		uint8_t *p = &frame[(fy * FW + fx) * 3];
		p[0] = top->vga_r; p[1] = top->vga_g; p[2] = top->vga_b;
	}
	if (!hb) fx++;
	if (hb && !old_hbl) { if (fx > 0 && !vb) fy++; fx = 0; }
	if (vb && !old_vbl) {
		last = frame;
		std::fill(frame.begin(), frame.end(), 0);
		fy = 0;
		frames++;
	}
	old_hbl = hb; old_vbl = vb;
}

static void write_ppm(const std::string &name) {
	// the used area only
	int w = 0, h = 0;
	for (int y = 0; y < FH; y++)
		for (int x = 0; x < FW; x++) {
			const uint8_t *p = &last[(y * FW + x) * 3];
			if (p[0] | p[1] | p[2]) { if (x + 1 > w) w = x + 1; if (y + 1 > h) h = y + 1; }
		}
	if (w < 560) w = 560;
	if (h < 192) h = 192;
	FILE *f = fopen(name.c_str(), "wb");
	if (!f) return;
	fprintf(f, "P6\n%d %d\n255\n", w, h);
	for (int y = 0; y < h; y++) fwrite(&last[y * FW * 3], 3, w, f);
	fclose(f);
}

// ---------------------------------------------------------------- main
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	double run_ms = 1000, every_ms = 0;
	std::string ppm;
	const char *disk[3] = {nullptr, nullptr, nullptr};
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		if (a == "--ms" && i + 1 < argc) run_ms = atof(argv[++i]);
		else if (a == "--disk1" && i + 1 < argc) disk[0] = argv[++i];
		else if (a == "--disk2" && i + 1 < argc) disk[1] = argv[++i];
		else if (a == "--hdd" && i + 1 < argc) disk[2] = argv[++i];
		else if (a == "--ppm" && i + 1 < argc) ppm = argv[++i];
		else if (a == "--every" && i + 1 < argc) every_ms = atof(argv[++i]);
		else if (a == "--type-at" && i + 2 < argc) { double t = atof(argv[++i]); type_text(t, argv[++i]); }
		else if (a == "--trace-sd") trace_sd = true;
		else if (a == "--trace-we" && i + 1 < argc) trace_we = atoi(argv[++i]);
	}
	top = new Vtb_apple2;
	for (int i = 0; i < 3; i++)
		if (disk[i]) {
			img[i].f = fopen(disk[i], "r+b");
			if (!img[i].f) { fprintf(stderr, "can't open %s\n", disk[i]); return 1; }
			fseek(img[i].f, 0, SEEK_END);
			img[i].size = ftell(img[i].f);
		}

	top->reset_cold = 1;
	top->reset_warm = 0;
	top->clk_sys = 0;
	top->clk_core = 0;
	top->eval();

	const uint64_t end = ms_to_cycles(run_ms);
	const uint64_t every = every_ms > 0 ? ms_to_cycles(every_ms) : 0;
	const uint64_t mount_at = ms_to_cycles(20);
	int mounted = 0;
	bool core_phase = false;
	while (sys_cycles < end && !Verilated::gotFinish()) {
		// rising edge of clk_sys; clk_core (half the frequency) changes with it
		top->clk_sys = 1;
		core_phase = !core_phase;
		top->clk_core = core_phase;
		top->eval();
		if (core_phase) pixel_step();
		sys_cycles++;

		if (sys_cycles == ms_to_cycles(1)) top->reset_cold = 0;
		// mount the images one after the other (img_mounted is one pulse per image)
		top->img_mounted = 0;
		if (sys_cycles >= mount_at && mounted < 3 && (sys_cycles & 63) == 0) {
			if (disk[mounted]) {
				top->img_mounted = 1 << mounted;
				top->img_size = img[mounted].size;
			}
			mounted++;
		}
		sd_step();
		key_step();

		top->clk_sys = 0;
		top->eval();

		if (every && sys_cycles % every == 0 && !ppm.empty()) {
			char n[64];
			snprintf(n, sizeof n, "_%05d.ppm", (int)(sys_cycles * 1000.0 / SYS_HZ + 0.5));
			write_ppm(ppm + n);
		}
	}
	printf("%.1f ms, %d frames, disk active %d; ram writes %llu, video 1s %llu, vga lit %llu, addr %04x\n", sys_cycles * 1000.0 / SYS_HZ, frames, top->disk_active,
		(unsigned long long)st_we, (unsigned long long)st_video, (unsigned long long)st_vga, top->ram_addr);
	if (!ppm.empty()) write_ppm(ppm + ".ppm");
	for (auto &i : img) if (i.f) fclose(i.f);
	top->final();
	delete top;
	return 0;
}
