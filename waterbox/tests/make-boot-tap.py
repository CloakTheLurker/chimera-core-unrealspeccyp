#!/usr/bin/env python3
"""Build boot.tap: a minimal TAP that boots to BASIC with `10 REM`.

Two blocks: a header block (flag 0x00) naming the program "boot", and a data
block (flag 0xFF) holding the 7-byte program `00 0A 03 00 EA 20 0D`
(line 10, length 3, REM + space + ENTER). Fully hand-made (no copyrighted
bytes); loading it exercises the guest tape path end to end.
"""
import struct


def block(flag, body):
    chk = flag
    for b in body:
        chk ^= b
    n = len(body) + 2  # flag + checksum
    return struct.pack('<H', n) + bytes([flag]) + body + bytes([chk])


header = bytes([0x00]) + b'boot      ' + struct.pack('<HHH', 7, 10, 7)
prog = bytes([0x00, 0x0A, 0x03, 0x00, 0xEA, 0x20, 0x0D])
tap = block(0x00, header) + block(0xFF, prog)
with open('boot.tap', 'wb') as f:
    f.write(tap)
print('boot.tap:', len(tap), 'bytes')
