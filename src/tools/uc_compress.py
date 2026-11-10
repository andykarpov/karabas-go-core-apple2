#!/usr/bin/env python3
"""jt6805 microcode (rtl/mouse/jt6805/6805.uc, 4096 x 39 bits, $readmemb) -> an index ROM
(roms/6805_uc_idx.hex, 4096 x 8) and a table of the distinct words (roms/6805_uc_tab.hex,
256 x 40): 145 words only, so the table fits in LUTs and the index in 2 block RAMs instead of 10.
Run from src/."""
words = [int(l.strip(), 2) for l in open('rtl/mouse/jt6805/6805.uc') if l.strip()]
assert len(words) == 4096
tab = [0] + sorted(set(words) - {0})
assert len(tab) <= 256
pos = {w: i for i, w in enumerate(tab)}
with open('roms/6805_uc_idx.hex', 'w') as f:
    f.write('\n'.join('%02X' % pos[w] for w in words) + '\n')
with open('roms/6805_uc_tab.hex', 'w') as f:
    f.write('\n'.join('%010X' % w for w in tab + [0] * (256 - len(tab))) + '\n')
print('words', len(tab))
