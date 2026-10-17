#!/usr/bin/env python3
"""Copy files out of an exFAT filesystem inside an image file, read-only and
without mounting it (no root needed).

    python3 tests/exfat-read.py IMAGE PARTITION-OFFSET-BYTES OUTDIR [PREFIX]

Every file whose path starts with PREFIX (a path inside the filesystem, e.g.
dawo-appliance or dawo-appliance/x/screens; default: everything) is written
under OUTDIR with the same relative path; one line per file is printed.
Used by the KVM test test-live-launch (nix/tests/live-launch.nix) to take the
screenshots off its DAWO_LOGS stick image, and tested offline against an image
written by tests/exfat-add-tree.py (tests/test-exfat-read.sh). Both the
contiguous (NoFatChain) and the FAT-chained layout are read; deleted entries
are skipped. The image is opened read-only.

SPDX-License-Identifier: EUPL-1.2
"""
import os
import struct
import sys

if len(sys.argv) not in (4, 5):
    sys.exit(__doc__.split("\n\n")[1])
img_path, part_off, out_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
prefix = [p for p in (sys.argv[4] if len(sys.argv) == 5 else "").split("/") if p]
f = open(img_path, "rb")


def rd(off, n):
    f.seek(part_off + off)
    return f.read(n)


bs = rd(0, 512)
assert bs[3:11] == b"EXFAT   ", "no exFAT boot sector"
fat_off = struct.unpack_from("<I", bs, 80)[0]
heap, count, root = struct.unpack_from("<III", bs, 88)
bps = 1 << bs[108]
cs = bps << bs[109]
END = 0xFFFFFFF7  # bad cluster (0xFFFFFFF7) and end of chain (0xFFFFFFFF)


def cl_off(c):
    return heap * bps + (c - 2) * cs


def fat_next(c):
    return struct.unpack("<I", rd(fat_off * bps + 4 * c, 4))[0]


def clusters(first, length, contig):
    """The clusters of a chain; length None: follow the FAT to its end."""
    c, n = first, None if length is None else (length + cs - 1) // cs
    while 2 <= c < END and c - 2 < count and (n is None or n > 0):
        yield c
        c = c + 1 if contig else fat_next(c)
        if n is not None:
            n -= 1


def read_dir(first, length, contig):
    """(name, is_dir, first cluster, data length, contiguous) per entry."""
    raw = b"".join(rd(cl_off(c), cs) for c in clusters(first, length, contig))
    i = 0
    while i + 32 <= len(raw):
        t = raw[i]
        if t == 0x00:  # end of directory
            break
        if t != 0x85:  # bitmap, up-case, label, deleted or a stray secondary
            i += 32
            continue
        secs = raw[i + 1]
        attr = struct.unpack_from("<H", raw, i + 4)[0]
        se = raw[i + 32:i + 64]
        if len(se) < 32 or se[0] != 0xC0:
            i += 32
            continue
        flags, nlen = se[1], se[3]
        first_c, dlen = struct.unpack_from("<IQ", se, 20)
        name = b"".join(raw[i + 32 * k + 2:i + 32 * k + 32] for k in range(2, secs + 1))
        name = name.decode("utf-16-le", "replace")[:nlen]
        yield name, bool(attr & 0x10), first_c, dlen, bool(flags & 0x02)
        i += 32 * (secs + 1)


def copy_file(first, length, contig, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    left = length
    with open(dst, "wb") as out:
        for c in clusters(first, length, contig):
            n = min(cs, left)
            out.write(rd(cl_off(c), n))
            left -= n
    assert left == 0, "short chain for " + dst


def walk(first, length, contig, path):
    for name, is_dir, c, dlen, cont in read_dir(first, length, contig):
        if name in ("", ".", "..") or "/" in name or "\\" in name:
            continue
        p = path + [name]
        # Only into directories on the way to PREFIX, or below it.
        if p[:len(prefix)] != prefix[:len(p)]:
            continue
        if is_dir:
            walk(c, dlen, cont, p)
        elif len(p) > len(prefix) or p == prefix:
            copy_file(c, dlen, cont, os.path.join(out_dir, *p))
            print("%s %d" % ("/".join(p), dlen))


walk(root, None, False, [])  # the root directory always uses the FAT
f.close()
