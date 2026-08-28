#!/usr/bin/env python3
"""Fail the build if a Mach-O lacks an LC_CODE_SIGNATURE load command.

AltStore and Sideloadly re-sign an app by replacing its existing signature.
They cannot add the signature slot themselves, so an app built with
CODE_SIGNING_ALLOWED=NO is rejected at install time with a generic
"Invalid parameters" error. Catching it here turns that into a loud
build failure instead of a mystery on the device.
"""
import os
import struct
import sys

LC_CODE_SIGNATURE = 0x1D


def has_signature_slot(path: str) -> bool:
    with open(path, "rb") as f:
        magic = struct.unpack("<I", f.read(4))[0]
        if magic not in (0xFEEDFACF, 0xCFFAEDFE):
            raise SystemExit(f"::error::{path} is not a 64-bit Mach-O (magic {magic:#x})")
        f.seek(16)
        ncmds = struct.unpack("<I", f.read(4))[0]
        offset = 32
        for _ in range(ncmds):
            f.seek(offset)
            cmd, cmdsize = struct.unpack("<II", f.read(8))
            if cmd == LC_CODE_SIGNATURE:
                return True
            offset += cmdsize
    return False


def main() -> int:
    app = sys.argv[1]
    binaries = [
        os.path.join(app, "EasynewsPlayer"),
        os.path.join(app, "Frameworks/VLCKit.framework/VLCKit"),
    ]
    unsigned = [b for b in binaries if os.path.exists(b) and not has_signature_slot(b)]
    for b in unsigned:
        print(f"::error::No LC_CODE_SIGNATURE in {b} - AltStore will reject this IPA")
    if unsigned:
        return 1
    print(f"Signature slot present in all {len(binaries)} binaries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
