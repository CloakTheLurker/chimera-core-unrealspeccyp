#!/usr/bin/env python3
"""Build boot48.sna: a 48K snapshot that boots straight to the BASIC prompt.

48K SNA = 27-byte header (big-endian words) + 49152 bytes of RAM. The loader
pops PC off the stack, so the stack word is 0x0000 (ROM start) with SP=0xFF00.
All RAM zeroed, border white. Fully hand-made (no copyrighted bytes); the
machine ROMs it boots are the declared firmware, mounted separately.
"""
import struct

hdr = bytearray()
hdr.append(0x00)                       # I
hdr += struct.pack('>HHHH', 0, 0, 0, 0)   # alt HL DE BC AF
hdr += struct.pack('>HHHHH', 0, 0, 0, 0, 0)  # HL DE BC IY IX
hdr.append(0x00)                       # IFF1 (DI)
hdr.append(0x00)                       # R
hdr += struct.pack('>HH', 0x0000, 0xFF00)  # AF, SP
hdr.append(0x01)                       # IM 1
hdr.append(0x07)                       # border white, speaker off
assert len(hdr) == 27, len(hdr)

ram = bytearray(49152)                # all zero: empty BASIC area
ram[0xFF00 - 0x4000] = 0x00           # stacked return address 0x0000
ram[0xFF00 - 0x4000 + 1] = 0x00

with open('boot48.sna', 'wb') as f:
    f.write(hdr + ram)
print('boot48.sna:', 27 + len(ram), 'bytes')
