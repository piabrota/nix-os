"""Checks of the files of the favicon build: the three files and nothing else, the ICO (a header,
a 16-byte entry for each of the 16, 32 and 48 px images, then PNGs that fill the file to its last
byte) and the 180 px touch icon. `python3 favicon/files_test.py <favicon output>`; favicon/check.nix
runs it. Prints "N checks, M failed"; exits 1 on a failure.
"""

import struct
import sys
from pathlib import Path

PNG = b"\x89PNG\r\n\x1a\n"


def main(out):
    results = []

    def check(desc, got, want):
        results.append((desc, got, want))

    files = ["apple-touch-icon.png", "favicon.ico", "favicon.svg"]
    for f in files:
        check(f"{f} is not empty", (out / f).is_file() and (out / f).stat().st_size > 0, True)
    check("the output holds the three files only", sorted(p.name for p in out.iterdir()), files)

    ico = (out / "favicon.ico").read_bytes()
    reserved, kind, n = struct.unpack_from("<HHH", ico, 0)
    check("ico reserved", reserved, 0)
    check("ico type", kind, 1)
    check("ico count", n, 3)
    end = 6 + 16 * 3
    for i, px in enumerate((16, 32, 48)):
        w, h, _, _, _, bits, size, offset = struct.unpack_from("<BBBBHHII", ico, 6 + 16 * i)
        check(f"ico entry {i} width", w, px)
        check(f"ico entry {i} height", h, px)
        check(f"ico entry {i} bits", bits, 32)
        check(f"ico entry {i} starts where the last ended", offset, end)
        check(f"ico entry {i} is a PNG", ico[offset : offset + 8], PNG)
        check(f"ico entry {i} PNG is as wide as its entry", struct.unpack_from(">I", ico, offset + 16)[0], w)
        end = offset + size
    check("ico ends with its last image", len(ico), end)

    png = (out / "apple-touch-icon.png").read_bytes()
    check("touch icon is a PNG", png[:8], PNG)
    check("touch icon is 180 by 180 px", struct.unpack_from(">II", png, 16), (180, 180))

    failed = [r for r in results if r[1] != r[2]]
    for desc, got, want in failed:
        print(f"FAIL {desc}: got [{got!r}], want [{want!r}]")
    print(f"{len(results)} checks of the files, {len(failed)} failed")
    return int(bool(failed))


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
