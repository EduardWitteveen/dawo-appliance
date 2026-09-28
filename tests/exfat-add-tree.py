#!/usr/bin/env python3
"""Copy a host directory tree into the root of an existing exFAT filesystem
inside an image file, without mounting it (tests only; no root needed).

    python3 tests/exfat-add-tree.py IMAGE PARTITION-OFFSET-BYTES SRCDIR

Used by tests/test-live-stick-tool.sh to put a dawo-appliance/ folder on a
DAWO_LOGS partition made by mkfs.exfat, so the read action of
scripts/windows/dawo-stick.ps1 can be tested offline. Directories are stored
contiguously (NoFatChain); every second file is stored as a fragmented FAT
chain (a free cluster left between its clusters), so both read paths are
exercised. The result passes `fsck.exfat -n`.

SPDX-License-Identifier: EUPL-1.2
"""
import os
import struct
import sys

img_path, part_off, src = sys.argv[1], int(sys.argv[2]), sys.argv[3]
f = open(img_path, "r+b")


def rd(off, n):
    f.seek(part_off + off)
    return f.read(n)


def wr(off, data):
    f.seek(part_off + off)
    f.write(data)


bs = rd(0, 512)
assert bs[3:11] == b"EXFAT   ", "no exFAT boot sector"
fat_off = struct.unpack_from("<I", bs, 80)[0]
heap, count, root = struct.unpack_from("<III", bs, 88)
bps = 1 << bs[108]
cs = bps << bs[109]


def cl_off(c):
    return heap * bps + (c - 2) * cs


root_raw = bytearray(rd(cl_off(root), cs))
bitmap_cluster = bitmap_len = None
free_slot = None
for i in range(0, cs, 32):
    t = root_raw[i]
    if t == 0x81:
        bitmap_cluster, bitmap_len = struct.unpack_from("<IQ", root_raw, i + 20)
    if t == 0 and free_slot is None:
        free_slot = i
assert bitmap_cluster is not None and free_slot is not None
bitmap = bytearray(rd(cl_off(bitmap_cluster), bitmap_len))


def used(c):
    return bitmap[(c - 2) // 8] >> ((c - 2) % 8) & 1


def mark(c):
    bitmap[(c - 2) // 8] |= 1 << ((c - 2) % 8)


def set_fat(c, v):
    wr(fat_off * bps + 4 * c, struct.pack("<I", v))


def alloc_contig(n):
    c = 2
    while True:
        if c + n - 2 > count:
            sys.exit("exfat-add-tree: no room")
        if all(not used(c + k) for k in range(n)):
            for k in range(n):
                mark(c + k)
            return c
        c += 1


def alloc_fragmented(n):
    out, c = [], 2
    while len(out) < n:
        if c - 2 >= count:
            sys.exit("exfat-add-tree: no room")
        if not used(c):
            mark(c)
            out.append(c)
            c += 1  # leave the next cluster free: a gap
        c += 1
    for a, b in zip(out, out[1:] + [0xFFFFFFFF]):
        set_fat(a, b)
    return out


def chk16(data, skip=()):
    s = 0
    for i, b in enumerate(data):
        if i in skip:
            continue
        s = (((s << 15) | (s >> 1)) + b) & 0xFFFF
    return s


def entry_set(name, is_dir, first, length, contig):
    u = name.encode("utf-16-le")
    nlen = len(name)
    upper = name.upper().encode("utf-16-le")
    name_hash = chk16(upper)
    secs = 1 + (nlen + 14) // 15
    stamp = ((2026 - 1980) << 25) | (9 << 21) | (28 << 16) | (12 << 11)
    fe = bytearray(32)
    fe[0], fe[1] = 0x85, secs
    struct.pack_into("<HHIII", fe, 4, 0x10 if is_dir else 0x20, 0, stamp, stamp, stamp)
    se = bytearray(32)
    se[0], se[1], se[3] = 0xC0, 0x01 | (0x02 if contig else 0), nlen
    struct.pack_into("<H", se, 4, name_hash)
    struct.pack_into("<Q", se, 8, length)
    struct.pack_into("<IQ", se, 20, first, length)
    out = fe + se
    for k in range(0, nlen, 15):
        ne = bytearray(32)
        ne[0] = 0xC1
        part = u[2 * k:2 * (k + 15)]
        ne[2:2 + len(part)] = part
        out += ne
    struct.pack_into("<H", out, 2, chk16(out, skip=(2, 3)))
    return out


state = {"files": 0}


def add_children(path):
    """Write the children of host dir `path`; return their entry sets."""
    sets = bytearray()
    for name in sorted(os.listdir(path)):
        p = os.path.join(path, name)
        if os.path.isdir(p):
            content = add_children(p)
            n = max(1, (len(content) + cs - 1) // cs)
            c = alloc_contig(n)
            wr(cl_off(c), bytes(content) + bytes(n * cs - len(content)))
            sets += entry_set(name, True, c, n * cs, True)
        else:
            data = open(p, "rb").read()
            assert data, "empty files are not supported here"
            n = (len(data) + cs - 1) // cs
            state["files"] += 1
            if state["files"] % 2 == 0 and n > 1:
                chain = alloc_fragmented(n)
                for k, c in enumerate(chain):
                    wr(cl_off(c), data[k * cs:(k + 1) * cs])
                sets += entry_set(name, False, chain[0], len(data), False)
            else:
                c = alloc_contig(n)
                wr(cl_off(c), data)
                sets += entry_set(name, False, c, len(data), True)
    return sets


new = add_children(src)
assert free_slot + len(new) <= cs, "root directory cluster full"
root_raw[free_slot:free_slot + len(new)] = new
wr(cl_off(root), bytes(root_raw))
wr(cl_off(bitmap_cluster), bytes(bitmap))
f.close()
print("exfat-add-tree: added %d files from %s" % (state["files"], src))
