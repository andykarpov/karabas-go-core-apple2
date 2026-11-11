# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

An Apple //e (enhanced) core (65C02 / 6502, 64 KB + 64 KB aux, 80 columns, double hi-res, Disk II, ProDOS HDD, Mockingboard, AppleMouse, SSC) for the Karabas Go, Mini and Mini G boards (Xilinx Spartan-6 XC6SLX25, ISE 14.7, XST): a port of the MiST machine of [apple2efpga](https://github.com/gyurco/apple2efpga) as extended by [NanoApple2](https://github.com/MiSTle-Dev/NanoApple2); parts of [Apple-II_MiSTer](https://github.com/MiSTer-devel/Apple-II_MiSTer) later.

Status: phase 0 done (2026-11-11: import, XST fit of the machine with all cards, 32 % LUT, 30 RAMB16), phase 1 done (verilator model: sim/run_boot.sh), next phase 2 (Mini G). Docs, in Russian: `docs/PLAN.md` (research, decisions, phases). Follow the phases; record a changed decision in PLAN.md. Decisions still open are listed at its end: ask the user, do not assume.

All file work goes through the firmware (OSD, `FL` / `F` items, `img_sdc`): no loader or soft CPU in the core.

Templates: `../karabas-go-core-atarist` (MiSTeryNano port: sd_card interface on `img_sdc`, sv2v flow, Makefile, sim harness), `../karabas-go-core-archie` (latest Makefile / sim / HID layout), `../karabas-go-core-orion128` / `../karabas-go-core-rk` (SRAM as machine RAM).

## Layout (planned, phase 0 creates it)

- `upstream/`: NanoApple2 as imported (reference, not built).
- `src/rtl/`: the machine and cards, changes marked `-- karabas:` / `// karabas:`; `src/rtl/karabas/`: our parts (`apple2_hid.v`, `apple2_sram.v`, ...).
- `src/Makefile`: the ISE flow as in core-atarist / core-archie (`make minig`, `make minig-xst`, `make apple2-xst` = the machine alone).
- `src/core.json`: kgo2 description (`apple2.kg`). `src/make_core.py`: symlink to `../../karabas-go-tools/make_core/make_core.py`.
- `modules/`: the git submodule [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules). Clone with `--recursive`. A change to a module is made there (branch + PR) and taken here by moving the submodule commit.

## Rules of the core

The rules of core-atarist / core-archie apply: standard-ish video timing with syncs always present (check the user's monitor), `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 (the Go floppy port is Shugart, not Disk II), OSD switch index = item position unless `"index"`, an OSD value shows 10 characters at most, FL slots 0..7 only (one array with the F slots), Verilog-2001 for XST (`sv2v` for SV), imported code marked `karabas:`.

- Mini / Mini G tops drive T3 (`FLASH_CS_N`) = 0: on Mini G2 it is the SDRAM ~CS.
- XST: instantiate VHDL entities with `entity work.x` (Quartus accepts `x : work.x`); declare Verilog nets before use; no declarations in unnamed blocks; no aggregates on ports of Verilog modules.
- XST silently removes a register with neither reset nor initial value whose way out of idle depends on itself (see atarist `fdc1772`): when imported logic works in sim and not on the board, read Xst:1710 / 2404 in the `.syr` first.
- **Ask the user before every check on the board** (and the HDMI capture), even inside a phase; bench only through `hwq`. Ask before a firmware flash.
- One branch per phase of `docs/PLAN.md`, one PR at its end.
- Heavy builds: Mini G only while working on one feature, all boards for a release. Long sims via `job run` + Monitor on `job watch`, minutes-long runs only after asking.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
