import bpy
import json
import sys
from pathlib import Path

source = Path(__file__).resolve().parent / "sources" / "city-zombie"
bpy.ops.import_scene.fbx(filepath=str(source / "InfectedCityMan.fbx"))
print("ASSET INSPECTION", json.dumps({
    "objects": [{"name": o.name, "type": o.type, "dimensions": list(o.dimensions), "bones": [b.name for b in o.data.bones] if o.type == "ARMATURE" else None, "polygons": len(o.data.polygons) if o.type == "MESH" else None} for o in bpy.context.scene.objects],
    "materials": [{"name": m.name, "nodes": [{"type": n.type, "image": n.image.filepath if n.type == "TEX_IMAGE" and n.image else None} for n in m.node_tree.nodes] if m.use_nodes else []} for m in bpy.data.materials],
    "actions": [a.name for a in bpy.data.actions],
}, ensure_ascii=False))
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=str(source / "Zombie Walk.fbx"))
print("ANIMATION INSPECTION", json.dumps({"new_objects": [{"name": o.name, "type": o.type, "action": o.animation_data.action.name if o.animation_data and o.animation_data.action else None} for o in bpy.data.objects if o not in before], "actions": [{"name": a.name, "range": list(a.frame_range), "paths": list({f.data_path for f in a.fcurves})[:6]} for a in bpy.data.actions]}))
print("EXPORT PARAMETERS", [p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties])
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.fbx(filepath=str(source.parent / "horror-monster" / "Walk.fbx"))
print("MONSTER INSPECTION", json.dumps({"objects": [{"name": o.name, "type": o.type, "dimensions": list(o.dimensions), "scale": list(o.scale), "bones": [b.name for b in o.data.bones][:12] if o.type == "ARMATURE" else None, "polygons": len(o.data.polygons) if o.type == "MESH" else None, "action": o.animation_data.action.name if o.animation_data and o.animation_data.action else None} for o in bpy.data.objects], "materials": [m.name for m in bpy.data.materials]}))
