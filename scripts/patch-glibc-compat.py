#!/usr/bin/env python3
"""Drop the GLIBC_2.39 verneed (weak pidfd_* only) so the binary runs on 2.34+."""
import struct
import sys
from pathlib import Path

def patch(path: Path) -> bool:
    b = bytearray(path.read_bytes())
    needle = b"GLIBC_2.39"
    if needle not in b:
        return False
    # Known layout for this v1.0.2 ELF (verified)
    struct.pack_into("<H", b, 0x1610 + 2, 19)
    struct.pack_into("<I", b, 0x1790 + 12, 0)
    vs_off, vs_size = 0x1480, 368
    for i in range(0, vs_size, 2):
        v = struct.unpack_from("<H", b, vs_off + i)[0]
        if (v & 0x7FFF) == 17:
            struct.pack_into("<H", b, vs_off + i, 0)
    path.write_bytes(b)
    return True

if __name__ == "__main__":
    p = Path(sys.argv[1] if len(sys.argv) > 1 else "bin/cctv-server")
    if patch(p):
        print(f"patched glibc 2.39 verneed: {p}")
    else:
        print(f"no GLIBC_2.39 verneed (already compatible): {p}")
