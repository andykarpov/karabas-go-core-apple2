#!/bin/bash
# Builds the verilator model of the machine (the ghdl netlist of the VHDL of apple2.prj, its
# Verilog files, tb_apple2.v) and runs sim_apple2 with the given arguments (see sim_apple2.cpp).
# The build goes to src/sim/build.
#   sim/run_boot.sh --ms 1500 --disk1 sim/dos33master.nib --ppm sim/build/frame
set -e
cd "$(dirname "$0")"
SIM=$(pwd)
SRC=..
mkdir -p build
VHD=$(sed -n 's/^vhdl work "\(.*\)"/\1/p' $SRC/apple2.prj | sed "s#^#$SRC/#")
VLOG=$(sed -n 's/^verilog work "\(.*\)"/\1/p' $SRC/apple2.prj)
NET=build/apple2_top_ghdl.v
if [ ! -f $NET ] || [ -n "$(find $VHD vhdl2v.sh bb_comp.py -newer $NET 2>/dev/null)" ]; then
	./vhdl2v.sh build > build/ghdl.log 2>&1 || { grep -v warning build/ghdl.log | tail -30; exit 1; }
fi
BIN=build/obj/Vtb_apple2
if [ ! -x $BIN ] || [ -n "$(find $NET $(echo "$VLOG" | sed "s#^#$SRC/#") tb_apple2.v sim_apple2.cpp run_boot.sh $SRC/rtl/karabas/apple2_sram.v $SRC/rtl/karabas/apple2_fb.v -newer $BIN 2>/dev/null)" ]; then
	# the ROM paths of the sources are relative to src/, where XST runs
	(cd $SRC && verilator -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-BLKANDNBLK -Wno-MULTIDRIVEN \
		-Wno-COMBDLY -Wno-UNOPTFLAT --no-timing +1364-2005ext+v -Irtl/mouse/jt6805 --top-module tb_apple2 \
		-Mdir sim/build/obj --cc $VLOG sim/build/apple2_top_ghdl.v rtl/karabas/apple2_sram.v rtl/karabas/apple2_fb.v sim/tb_apple2.v \
		--exe $SIM/sim_apple2.cpp -o Vtb_apple2 > sim/build/verilator.log 2>&1) || { tail -30 build/verilator.log; exit 1; }
	make -s -j8 -C build/obj -f Vtb_apple2.mk > build/make.log 2>&1 || { tail -30 build/make.log; exit 1; }
fi
# run from src/ so that the $readmem paths (roms/...) resolve
cd $SRC
exec sim/build/obj/Vtb_apple2 "$@"
