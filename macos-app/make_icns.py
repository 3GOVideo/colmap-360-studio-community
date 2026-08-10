#!/usr/bin/env python3
"""Create a modern ICNS container from PNG iconset files without Xcode."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


CHUNKS = (
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_128x128@2x.png"),
    ("ic09", "icon_256x256@2x.png"),
    ("ic10", "icon_512x512@2x.png"),
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("iconset", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    elements: list[bytes] = []
    for kind, filename in CHUNKS:
        data = (args.iconset / filename).read_bytes()
        elements.append(kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data)
    payload = b"".join(elements)
    args.output.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
