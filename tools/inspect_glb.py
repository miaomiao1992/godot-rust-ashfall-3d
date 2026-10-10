import json
import struct
from pathlib import Path

for path in (Path(__file__).resolve().parent.parent / "assets" / "models").glob("*.glb"):
    with path.open("rb") as file:
        file.read(12)
        size, _kind = struct.unpack("<II", file.read(8))
        data = json.loads(file.read(size))
    print(path.name)
    print("animations", [(a["name"], len(a.get("channels", []))) for a in data.get("animations", [])])
    print("materials", [(m.get("name"), "baseColorTexture" in m.get("pbrMetallicRoughness", {}), "normalTexture" in m) for m in data.get("materials", [])])
    print("skins", len(data.get("skins", [])), "mesh primitives", sum(len(m["primitives"]) for m in data.get("meshes", [])))
