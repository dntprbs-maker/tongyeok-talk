"""Compile existing approved artwork into the Xcode-generated icon catalog."""
import json
import subprocess
import sys
from pathlib import Path

source, catalog = map(Path, sys.argv[1:])
manifest = json.loads((catalog / "Contents.json").read_text())
assert source.is_file() and len(manifest["images"]) >= 10
for item in manifest["images"]:
    filename = item.get("filename")
    if not filename:
        continue
    assert Path(filename).name == filename
    width, height = map(float, item["size"].split("x"))
    assert width == height
    pixels = int(width * float(item["scale"].removesuffix("x")))
    subprocess.run([
        "sips", "-s", "format", "png", "-z", str(pixels), str(pixels),
        str(source), "--out", str(catalog / filename),
    ], check=True, stdout=subprocess.DEVNULL)
print("Compiled approved Tongyeok icon catalog")
