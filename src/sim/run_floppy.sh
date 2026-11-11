#!/bin/bash
# apple2_floppy with the 140K sector images (iverilog, tb_floppy.v): the tracks 0, 17, 34 of
# dos33master.dsk (DOS order) and of a ProDOS order copy of it (block 2 with the ProDOS volume
# directory mark) against dsk2nib.c of NanoApple2. Seconds.
set -e
cd "$(dirname "$0")/.."
B=sim/build/fl
mkdir -p $B
U=${NANOAPPLE2:-}
[ -x $B/dsk2nib ] || gcc -O -o $B/dsk2nib sim/dsk2nib.c
python3 - <<'PY'
d = bytearray(open('sim/dos33master.dsk', 'rb').read())
dos = [0x0,0x7,0xE,0x6,0xD,0x5,0xC,0x4,0xB,0x3,0xA,0x2,0x9,0x1,0x8,0xF]
po = [0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15]
# the ProDOS order copy: physical sector p is DOS sector dos[p] and ProDOS sector po[p]
p = bytearray(len(d))
for t in range(35):
    for s in range(16):
        p[t*4096 + po[s]*256 : t*4096 + po[s]*256 + 256] = d[t*4096 + dos[s]*256 : t*4096 + dos[s]*256 + 256]
p[0x400:0x405] = bytes([0, 0, 3, 0, 0xF5])
# its DOS order twin for the reference
q = bytearray(len(d))
for t in range(35):
    for s in range(16):
        q[t*4096 + dos[s]*256 : t*4096 + dos[s]*256 + 256] = p[t*4096 + po[s]*256 : t*4096 + po[s]*256 + 256]
open('sim/build/fl/test.po', 'wb').write(p)
open('sim/build/fl/test_do.dsk', 'wb').write(q)
# the write tests: logical sector 5 of track 0 changed (DOS order image) and ProDOS sector 9 (.po)
d2 = bytearray(d); d2[5*256:6*256] = bytes((i * 7 + 3) & 255 for i in range(256))
open('sim/build/fl/w.dsk', 'wb').write(d2)
p2 = bytearray(p); p2[9*256:10*256] = bytes((i * 13 + 1) & 255 for i in range(256))
open('sim/build/fl/w.po', 'wb').write(p2)
q2 = bytearray(len(d))
for t in range(35):
    for s in range(16):
        q2[t*4096 + dos[s]*256 : t*4096 + dos[s]*256 + 256] = p2[t*4096 + po[s]*256 : t*4096 + po[s]*256 + 256]
open('sim/build/fl/w_po_do.dsk', 'wb').write(q2)
PY
$B/dsk2nib sim/dos33master.dsk $B/ref.nib > /dev/null
$B/dsk2nib $B/test_do.dsk $B/ref_po.nib > /dev/null
$B/dsk2nib $B/w.dsk $B/w.nib > /dev/null
$B/dsk2nib $B/w_po_do.dsk $B/w_po.nib > /dev/null
for f in sim/dos33master.dsk $B/ref.nib $B/test.po $B/ref_po.nib $B/w.dsk $B/w.nib $B/w.po $B/w_po.nib; do
	python3 -c "import sys; open(sys.argv[2],'w').write('\n'.join('%02x' % b for b in open(sys.argv[1],'rb').read()))" $f $B/$(basename $f).hex
done
iverilog -g2005 -o $B/tb_floppy sim/tb_floppy.v rtl/karabas/apple2_floppy.v rtl/karabas/gowin_mem.v \
	../modules/rtl/mem/kg_tdpram.v ../modules/rtl/mem/kg_sprom.v ../modules/rtl/mem/kg_sdpram.v ../modules/rtl/mem/kg_spram.v
echo "== DOS order"
vvp -n $B/tb_floppy +img=$B/dos33master.dsk.hex +ref=$B/ref.nib.hex | grep -v "^VCD\|readmem"
echo "== ProDOS order"
vvp -n $B/tb_floppy +img=$B/test.po.hex +ref=$B/ref_po.nib.hex | grep -v "^VCD\|readmem"
echo "== .nib (floppy_track as upstream)"
python3 -c "import sys; open(sys.argv[2],'w').write('\n'.join('%02x' % b for b in open(sys.argv[1],'rb').read()))" sim/dos33master.nib $B/nib.hex
vvp -n $B/tb_floppy +img=$B/nib.hex +ref=$B/nib.hex +dsk=0 | grep -v "^VCD\|readmem"
echo "== write, DOS order"
vvp -n $B/tb_floppy +wr=1 +img=$B/dos33master.dsk.hex +ref=$B/w.nib.hex +exp=$B/w.dsk.hex | grep -v "^VCD\|readmem\|finish"
echo "== write, ProDOS order"
vvp -n $B/tb_floppy +wr=1 +img=$B/test.po.hex +ref=$B/w_po.nib.hex +exp=$B/w.po.hex | grep -v "^VCD\|readmem\|finish"
