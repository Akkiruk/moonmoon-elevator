"""Remove the car's two door-piston extension poles from Moon-Moon's elevator schematic.

The poles stick out of the car into the shaft's east wall (where the floor contacts are) for the
whole height of the shaft, which jams the car. Run:  python fix-schematic.py <in.nbt> <out.nbt>
"""
import sys

import nbtlib


def main(src, dst):
    nbt = nbtlib.load(src)
    car = None
    for sub in nbt["sub_levels"]:
        names = {str(p["Name"]) for p in sub["palette"]}
        if "computercraft:computer_advanced" in names:
            car = sub
    if car is None:
        sys.exit("no car sub-level (the one with the computer) found")
    pole = {i for i, p in enumerate(car["palette"]) if str(p["Name"]) == "create:piston_extension_pole"}
    before = len(car["blocks"])
    kept = [b for b in car["blocks"] if int(b["state"]) not in pole]
    car["blocks"] = nbtlib.List[nbtlib.Compound](kept)
    print(f"car blocks {before} -> {len(kept)} (removed {before - len(kept)} extension poles)")
    nbt.save(dst)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
