"""Convert PES pitch DDS to PNG inside the Godot project."""
import os
import subprocess
import sys

TEXCONV = r"C:\Users\csantz\Documents\OpenGoFootball\PES Exporter\StadiumLibs\Gzs\texconv.exe"
SRC = r"C:\Users\csantz\Documents\OpenGoFootball\Assets\Stadium\Neftyanik Stadium\Asset\model\bg\st009\sourceimages\tga\#windx11"
DST = r"C:\Users\csantz\Documents\OpenGoFootball\game\stadiums\neftyanik\pitch"

ALBEDO = [
    "turf_green.dds",
    "pitch_alp.dds",
    "pitch_detail_alp.dds",
    "pitch_grain.dds",
]
LINEAR = [
    "turf_nrm.dds",
    "turf_green_srm.dds",
]


def convert(name, srgb):
    src = os.path.join(SRC, name)
    if not os.path.isfile(src):
        print("MISSING", src)
        return False
    cmd = [TEXCONV, "-ft", "png", "-y", "-o", DST]
    if srgb:
        cmd.append("-srgb")
    cmd.append(src)
    print(" ".join(cmd))
    r = subprocess.run(cmd, cwd=DST)
    return r.returncode == 0


def main():
    os.makedirs(DST, exist_ok=True)
    ok = 0
    for n in ALBEDO:
        if convert(n, True):
            ok += 1
    for n in LINEAR:
        if convert(n, False):
            ok += 1
    print("converted", ok, "files into", DST)
    print("out", os.listdir(DST))
    if ok < 4:
        sys.exit(1)


if __name__ == "__main__":
    main()
