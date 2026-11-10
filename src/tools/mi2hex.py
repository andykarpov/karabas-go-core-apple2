#!/usr/bin/env python3
"""Gowin .mi (one hex word per line after the '#' header) -> $readmemh file.

usage: mi2hex.py in.mi out.hex
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
words = []
with open(src) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#'):
            words.append(line.upper())
with open(dst, 'w') as f:
    f.write('\n'.join(words) + '\n')
print(f'{dst}: {len(words)} words')
