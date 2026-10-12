"""Convert GoldSrc v30 cs_assault geometry, UVs, lighting and entities to Godot.

Coordinates: (x, y, z) -> (x, z, -y), 40 GoldSrc units per metre.
Requires Pillow. Original BSP is an input, never guessed procedural geometry.
"""
import argparse
import hashlib
import json
import math
import re
import struct
from collections import Counter
from pathlib import Path

from PIL import Image


def mip_image(data, offset=0):
    name, w, h, *mips = struct.unpack_from("<16s6I", data, offset)
    name = name.split(b"\0")[0].decode("latin1")
    if not mips[0]: return name, None
    palette_offset = offset + mips[3] + (w // 8) * (h // 8) + 2
    pixels = data[offset + mips[0]:offset + mips[0] + w * h]
    image = Image.frombytes("P", (w, h), pixels)
    image.putpalette(data[palette_offset:palette_offset + 768])
    image = image.convert("RGBA")
    if name.startswith("{"):
        image.putalpha(Image.frombytes("L", (w, h), bytes(0 if p == 255 else 255 for p in pixels)))
    return name, image


def wad_images(path):
    data = Path(path).read_bytes()
    magic, count, directory = struct.unpack_from("<4sii", data)
    assert magic == b"WAD3", f"Invalid WAD: {path}"
    result = {}
    for i in range(count):
        offset, size, _, kind, compression, _, _ = struct.unpack_from("<iiiBBH16s", data, directory + i * 32)
        if kind == 67 and compression == 0:
            name, image = mip_image(data, offset)
            result[name.lower()] = image
    return result


class Bsp:
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        assert struct.unpack_from("<i", self.data)[0] == 30, "Expected GoldSrc BSP v30"
        self.lumps = [struct.unpack_from("<ii", self.data, 4 + i * 8) for i in range(15)]
        self.entities = [dict(re.findall(r'"([^"\n]*)"\s*"([^"\n]*)"', block))
                         for block in re.findall(r"\{([^}]+)\}", self.lump(0).decode("latin1"))]

    def lump(self, index):
        start, size = self.lumps[index]
        return self.data[start:start + size]

    def records(self, index, fmt):
        return list(struct.iter_unpack("<" + fmt, self.lump(index)))

    def textures(self):
        data = self.lump(2)
        count = struct.unpack_from("<i", data)[0]
        result = []
        for offset in struct.unpack_from(f"<{count}i", data, 4):
            if offset < 0:
                result.append(("missing", 16, 16, None))
                continue
            name, w, h, *mips = struct.unpack_from("<16s6I", data, offset)
            name = name.split(b"\0")[0].decode("latin1")
            image = None
            if mips[0]:
                palette_offset = offset + mips[3] + (w // 8) * (h // 8) + 2
                pixels = data[offset + mips[0]:offset + mips[0] + w * h]
                image = Image.frombytes("P", (w, h), pixels)
                image.putpalette(data[palette_offset:palette_offset + 768])
                image = image.convert("RGBA")
                if name.startswith("{"):
                    image.putalpha(Image.frombytes("L", (w, h), bytes(0 if p == 255 else 255 for p in pixels)))
            result.append((name, w, h, image))
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bsp")
    parser.add_argument("--output")
    parser.add_argument("--wad", action="append", default=[])
    parser.add_argument("--inspect-ducts", action="store_true")
    parser.add_argument("--inspect-texture")
    args = parser.parse_args()
    bsp = Bsp(args.bsp)
    textures = bsp.textures()
    available = {}
    for path in args.wad: available.update(wad_images(path))
    textures = [(n, w, h, image if image is not None else available.get(n.lower())) for n, w, h, image in textures]
    print("SHA256", hashlib.sha256(bsp.data).hexdigest())
    print("Entities", Counter(e.get("classname") for e in bsp.entities))
    print("Textures", len(textures), "resolved", sum(image is not None for n, w, h, image in textures))
    models = bsp.records(14, "9f7i")
    for e in ([] if args.output or args.inspect_ducts or args.inspect_texture else bsp.entities):
        if e.get("classname") in ["info_player_start", "info_player_deathmatch", "func_ladder", "func_door", "func_breakable", "trigger_camera", "hostage_entity", "light_environment"]:
            print("ENTITY", e)
            if e.get("model", "").startswith("*"):
                print("MODEL", models[int(e["model"][1:])])
    if args.inspect_ducts or args.inspect_texture:
        vertices = bsp.records(3, "3f")
        edges = bsp.records(12, "2H")
        surfedges = [r[0] for r in bsp.records(13, "i")]
        texinfos = bsp.records(6, "8fii")
        for face in bsp.records(7, "Hhihh4Bi"):
            name = textures[texinfos[face[4]][8]][0]
            if args.inspect_texture:
                if args.inspect_texture not in name: continue
            elif name not in ["duct_flr01", "duct_vnt2", "{duct_vnt2"]: continue
            points = [vertices[edges[abs(se)][0 if se >= 0 else 1]] for se in surfedges[face[2]:face[2] + face[3]]]
            print("DUCT", name, [tuple(round(f, 1) for f in p) for p in points])
    if not args.output:
        return
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    vertices = bsp.records(3, "3f")
    edges = bsp.records(12, "2H")
    surfedges = [r[0] for r in bsp.records(13, "i")]
    faces = bsp.records(7, "Hhihh4Bi")
    texinfos = bsp.records(6, "8fii")
    planes = bsp.records(1, "4fi")
    lighting = bsp.lump(8)
    scale = 1 / 40

    def transform(v):
        return [round(v[0] * scale, 6), round(v[2] * scale, 6), round((1536 - v[1]) * scale, 6)]

    entities_by_model = {int(e["model"][1:]): e for e in bsp.entities if e.get("model", "").startswith("*")}
    atlas = Image.new("RGB", (1024, 1024), (190, 190, 190))
    atlas_x = atlas_y = row_height = 0
    surfaces = []
    collision = []
    for model_index, model in enumerate(models):
        entity = entities_by_model.get(model_index, {})
        classname = entity.get("classname", "worldspawn")
        if classname.startswith("trigger_") or classname in ["func_ladder", "func_buyzone", "func_hostage_rescue"]:
            continue
        groups = {}
        model_collision = []
        for face in faces[model[-2]:model[-2] + model[-1]]:
            plane, side, first, num, ti, *rest = face
            info = texinfos[ti]
            texture_id = info[8]
            name, w, h, image = textures[texture_id]
            if name.lower() in ["sky", "clip", "origin", "aaatrigger"]:
                continue
            points = [vertices[edges[abs(se)][0 if se >= 0 else 1]] for se in surfedges[first:first + num]]
            uv_pixels = [[sum(p[j] * info[j] for j in range(3)) + info[3],
                          sum(p[j] * info[j + 4] for j in range(3)) + info[7]] for p in points]
            lm_min = [math.floor(round(min(uv[k] for uv in uv_pixels) / 16, 4)) for k in range(2)]
            lm_size = [math.ceil(round(max(uv[k] for uv in uv_pixels) / 16, 4)) - lm_min[k] + 1 for k in range(2)]
            light_offset = rest[-1]
            if light_offset >= 0 and light_offset + lm_size[0] * lm_size[1] * 3 <= len(lighting):
                lw, lh = lm_size
                if atlas_x + lw + 2 > 1024:
                    atlas_x = 0
                    atlas_y += row_height
                    row_height = 0
                assert atlas_y + lh + 2 < 1024, "Lightmap atlas overflow"
                tile = Image.frombytes("RGB", (lw, lh), lighting[light_offset:light_offset + lw * lh * 3])
                atlas.paste(tile, (atlas_x + 1, atlas_y + 1))
                atlas.paste(tile.crop((0, 0, lw, 1)), (atlas_x + 1, atlas_y))
                atlas.paste(tile.crop((0, lh - 1, lw, lh)), (atlas_x + 1, atlas_y + lh + 1))
                atlas.paste(tile.crop((0, 0, 1, lh)), (atlas_x, atlas_y + 1))
                atlas.paste(tile.crop((lw - 1, 0, lw, lh)), (atlas_x + lw + 1, atlas_y + 1))
                uv2 = [[(atlas_x + 1.5 + uv[0] / 16 - lm_min[0]) / 1024,
                        (atlas_y + 1.5 + uv[1] / 16 - lm_min[1]) / 1024] for uv in uv_pixels]
                atlas_x += lw + 2
                row_height = max(row_height, lh + 2)
            else:
                uv2 = [[1023.5 / 1024, 1023.5 / 1024]] * num
            normal = planes[plane][:3]
            normal = [normal[0], normal[2], -normal[1]]
            if side: normal = [-v for v in normal]
            group = groups.setdefault(texture_id, {"texture": texture_id, "vertices": [], "normals": [], "uv": [], "uv2": []})
            # GoldSrc surfedges already wind clockwise when viewed from empty space.
            # The axis conversion is a rotation (determinant +1), so retain order.
            for j in range(1, num - 1):
                for idx in [0, j, j + 1]:
                    position = transform(points[idx])
                    group["vertices"].extend(position)
                    group["normals"].extend(normal)
                    group["uv"].extend([uv_pixels[idx][0] / w, uv_pixels[idx][1] / h])
                    group["uv2"].extend(uv2[idx])
                    if classname != "func_illusionary":
                        collision.extend(position)
                        model_collision.extend(position)
        surfaces.append({"model": model_index, "entity": entity, "surfaces": list(groups.values()), "collision": model_collision})
    for i, (name, w, h, image) in enumerate(textures):
        if image is not None:
            image.save(output / f"texture_{i}.png")
    atlas.save(output / "lightmap.png")
    data = {"source_sha256": hashlib.sha256(bsp.data).hexdigest(), "scale": scale,
            "textures": [{"name": name, "path": f"texture_{i}.png" if image is not None else ""} for i, (name, w, h, image) in enumerate(textures)],
            "models": surfaces, "collision": collision,
            "entities": bsp.entities,
            "model_bounds": [{"min": transform(m[:3]), "max": transform(m[3:6])} for m in models]}
    (output / "map.json").write_text(json.dumps(data, separators=(",", ":")))
    print("CONVERTED", len(faces), "faces;", len(collision) // 9, "collision triangles")


if __name__ == "__main__":
    main()
