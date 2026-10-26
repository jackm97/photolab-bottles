"""Dump the Binary table streams of an MSI.

Usage: python -I scripts/re/msi_streams.py <msi> <output-dir>

Writes one file per OLE stream whose decoded name starts with "Binary.", named
after the decoded name without that prefix. The output directory must be new
or empty. The input is untrusted data; it is only read, never executed.
"""
import os
import sys

import olefile


# Copied from tools/msipatch.py lines 3-16 (that script runs a patch at import
# time, so it cannot be imported).
def _c(x):
    if x<10: return chr(48+x)
    if x<36: return chr(55+x)
    if x<62: return chr(61+x)
    return "._"[x-62]
def dec(n):
    out=""
    for ch in n:
        c=ord(ch)
        if 0x3800<=c<0x4800: c-=0x3800; out+=_c(c&0x3f)+_c(c>>6)
        elif 0x4800<=c<0x4840: out+=_c(c-0x4800)
        elif c==0x4840: out+="!"
        else: out+=ch
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    if os.listdir(dst):
        sys.exit(f"output directory {dst} is not empty")
    prefix = "Binary."
    ole = olefile.OleFileIO(src)
    count = 0
    for entry in ole.listdir(streams=True):
        if len(entry) != 1:
            continue
        name = dec(entry[0])
        if not name.startswith(prefix):
            continue
        out_name = name[len(prefix):]
        # The name is attacker-controlled: refuse anything that is not a plain file name.
        if not out_name or "/" in out_name or "\\" in out_name or out_name in (".", ".."):
            print(f"skipping stream with unsafe name: {out_name!r}", file=sys.stderr)
            continue
        data = ole.openstream(entry).read()
        with open(os.path.join(dst, out_name), "wb") as f:
            f.write(data)
        print(f"{out_name}\t{len(data)}")
        count += 1
    ole.close()
    print(f"{count} binary streams written to {dst}")


if __name__ == "__main__":
    main()
