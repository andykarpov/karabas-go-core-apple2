#!/bin/bash
# The VHDL of the machine (apple2_top and below, and vga_controller of apple2_fb) as one Verilog netlist for verilator: ghdl --synth,
# the Verilog modules it instantiates left as black boxes (bb_comp.py). Run from anywhere.
#   sim/vhdl2v.sh <out dir>   -> <out dir>/apple2_top_ghdl.v
set -eu
OUT=$(mkdir -p "${1:?output dir}" && cd "$1" && pwd)
SRC=$(cd "$(dirname "$0")/.." && pwd)
SV2V=${SV2V:-/opt/sv2v/sv2v}
cd "$SRC"
mkdir -p "$OUT/vhd" "$OUT/vnorm"
# the Verilog modules the VHDL instantiates, normalised (one port per declaration)
declare -A VM=(
  [Gowin_pROM_apple2]=rtl/karabas/gowin_mem.v [Gowin_pROM_key]=rtl/karabas/gowin_mem.v
  [Gowin_SDPB_8k]=rtl/karabas/gowin_mem.v [Gowin_SDPB_palette]=rtl/karabas/gowin_mem.v
  [Gowin_DPB_track_buffer_b]=rtl/karabas/gowin_mem.v
  [floppy_track]=rtl/sv2v/floppy_track.v [glb6551]=rtl/sv2v/glb6551.v
  [jt49_bus]=rtl/mockingboard/jt49/jt49_bus.v [jtframe_6805mcu]=rtl/mouse/jt6805/jtframe_6805mcu.v
  [gen_uart_mos_6551]=rtl/apple2/gen_uart.v )
ARGS=()
for m in "${!VM[@]}"; do
  f=${VM[$m]}
  n="$OUT/vnorm/$m.v"
  [ -f "$n" ] || $SV2V -I rtl/mouse/jt6805 --top=$m $f $( [ $m = jtframe_6805mcu ] && echo rtl/mouse/jt6805/jt6805*.v rtl/karabas/gowin_mem.v ../modules/rtl/mem/kg_s*.v ) > "$n" 2>/dev/null || $SV2V $f > "$n"
  ARGS+=("$m=$n")
done
VHD=$(sed -n 's/^vhdl work "\(.*\)"/\1/p' apple2.prj)
python3 sim/bb_comp.py "$OUT/vhd" "${ARGS[@]}" -- $VHD
cd "$OUT/vhd"
# VHDL-2008 finds "0000" & "001100" & x ambiguous in the opcode table of R65Cx2: qualified elements
# (the same bits) in the copy; the VHDL-2008 rules let the rest (expressions on ports, out ports to
# buffer ports) through
sed -i -E "s/^(\s*)\"([01]{4})\" & \"([01]{6})\" & ([^,-]*[^,[:space:]-])(\s*)(,?)/\1decodedBitsDef'(\"\2\3\" \& \4)\5\6/" R65Cx2.vhd
G="--std=08 -fsynopsys -frelaxed"
rm -f work-obj08.cf
ghdl -a $G sim_bb.vhd
for f in $VHD; do ghdl -a $G "$(basename "$f")"; done
ghdl --synth $G --out=verilog apple2_top > ../apple2_top_ghdl.v
# the colouring of the frame buffer (apple2_fb instantiates it from Verilog)
ghdl --synth $G --out=verilog vga_controller >> ../apple2_top_ghdl.v
wc -l ../apple2_top_ghdl.v
