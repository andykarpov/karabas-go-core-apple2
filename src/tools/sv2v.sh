#!/bin/bash
# Converts the SystemVerilog of the upstream to Verilog-2001 for XST with sv2v (/opt/sv2v/sv2v):
# one file per module in rtl/sv2v/. rtl/sv2v/ is generated and in git; change the sources (with a
# "karabas:" comment), then run this.
set -e
cd "$(dirname "$0")/../rtl"
SV2V=${SV2V:-/opt/sv2v/sv2v}
SRC="apple2/floppy_track.sv uart6551/uart_6551.v uart6551/io_fifo.v"
rm -rf sv2v && mkdir sv2v
$SV2V $SRC -w sv2v 2>&1 | grep -v -E '^\s*$' || true
ls sv2v
