import json
import struct
import sys
from pathlib import Path

paths = [Path(arg) for arg in sys.argv[1:]] if len(sys.argv) > 1 else (Path(__file__).resolve().parent.parent / "assets" / "models").glob("*.glb")
for path in paths:
    with path.open("rb") as file:
        file.read(12)
        size, _kind = struct.unpack("<II", file.read(8))
        data = json.loads(file.read(size))
    print(path.name)
    print("animations", [(a["name"], len(a.get("channels", []))) for a in data.get("animations", [])])
    print("materials", [(m.get("name"), "baseColorTexture" in m.get("pbrMetallicRoughness", {}), "normalTexture" in m) for m in data.get("materials", [])])
    print("skins", len(data.get("skins", [])), "mesh primitives", sum(len(m["primitives"]) for m in data.get("meshes", [])))
    print("triangles", sum(data["accessors"][p["indices"]]["count"] // 3 for m in data.get("meshes", []) for p in m["primitives"] if "indices" in p))
    print("position bounds", [(a.get("min"), a.get("max")) for a in data["accessors"] if a.get("type") == "VEC3" and "min" in a])
