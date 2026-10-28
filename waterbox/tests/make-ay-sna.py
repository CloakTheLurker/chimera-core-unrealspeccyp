#!/usr/bin/env python3
"""Build ay.sna: a distributable 128K snapshot that programs the AY chip.

No copyrighted bytes: the snapshot's RAM is zeros plus the ~60-byte routine
below, and the core supplies the ROMs. The routine selects AY register 7
(mixer), enables tone A, sets a ~430 Hz period and maximum volume, then loops
forever. Running it must make the AY source audible, and the mixed audio must
differ between the AY and YM volume tables.

It is a 128K SNA (the format the core already loads): 27-byte header, the
three mapped 16K pages (5, 2, 0), then pc/p7FFD/trdos and six more pages.
PC is 0x8000 and the machine is in 128K mode, so this is the 128K machine.
"""
import os
import struct

# LD BC,port ; LD A,val ; OUT (C),A, as (register, value) pairs.
def ayreg(reg, val):
    return bytes([
        0x01, 0xFD, 0xFF,        # LD BC,0xFFFD   (register select)
        0x3E, reg,               # LD A,reg
        0xED, 0x79,              # OUT (C),A
        0x01, 0xFD, 0xBF,        # LD BC,0xBFFD   (data write)
        0x3E, val,               # LD A,val
        0xED, 0x79,              # OUT (C),A
    ])

code = (
    bytes([0x3E, 0x02,              # LD A,2
           0xD3, 0xFE])             # OUT (0xFE),A: border red proves it ran
    + ayreg(0, 0x00) +              # tone A fine
    ayreg(1, 0x01) +                # tone A coarse: ~430 Hz
    ayreg(7, 0x3E) +                # mixer: tone A on, B/C and noise off
    ayreg(8, 0x0E) +                # channel A volume: loud, fixed (not max:
                                    # both tables agree at 15, so 14 shows them)
    bytes([0x18, 0xFE])             # JR $ (loop forever)
)

PAGE = 0x4000
HEADER = 27
assert len(code) < PAGE

# 48K part: page 5 at 0x4000, page 2 at 0x8000, page 0 at 0xC000.
page5 = bytearray(PAGE)
page2 = bytearray(PAGE)
page0 = bytearray(PAGE)
page2[0:len(code)] = code       # 0x8000

# 128K extension: pc, p7FFD, trdos, then the six non-mapped pages.
pc = 0x8000
p7ffd = 0x00                    # RAM page 0 at 0xC000; ROM selection irrelevant
trdos = 0x00
pages = bytearray(6 * PAGE)

sna = bytearray()
sna += bytes([0x00])                          # I
sna += struct.pack('<HHHH', 0, 0, 0, 0)       # alt HL, DE, BC, AF
sna += struct.pack('<HHHHH', 0, 0, 0, 0, 0)   # HL, DE, BC, IY, IX
sna += bytes([0x00, 0x00])                    # IFF1 (DI), R
sna += struct.pack('<H', 0)                   # AF
sna += struct.pack('<H', 0x7FFE)              # SP (top of page 5)
sna += bytes([0x01, 0x00])                    # IM 1, border black
sna += page5 + page2 + page0
sna += struct.pack('<H', pc) + bytes([p7ffd, trdos])
sna += pages

assert len(sna) == 147487, len(sna)
HERE = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(HERE, '..', '..', 'test-content', 'ay.sna')
with open(out, 'wb') as f:
    f.write(sna)
print(out + ':', len(sna), 'bytes,', len(code), 'bytes of AY code')
