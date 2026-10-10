"""Optimize the downloaded CC0 soldier in an isolated Blender process.

blender --background --factory-startup --python tools/convert_survivor.py
"""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parent.parent
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / "tools/sources/survivor-soldier.glb"))
rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
print("SURVIVOR BONES", [bone.name for bone in rig.data.bones])
for index, image in enumerate(list(bpy.data.images)):
    if image.size[0] and max(image.size) > 2048:
        factor = 2048 / max(image.size)
        image.scale(round(image.size[0] * factor), round(image.size[1] * factor))
    if image.size[0]:
        # Blender 3.1's GLB exporter cannot copy resized packed JPEG images.
        # Reload from a real PNG before packing the optimized textures.
        image.filepath_raw = str(ROOT / f"tools/sources/survivor-texture-{index}.png")
        formats = [item.identifier for item in image.bl_rna.properties["file_format"].enum_items]
        image.file_format = next(value for value in formats if value == "PNG")
        image.save()
        replacement = bpy.data.images.load(image.filepath_raw, check_existing=False)
        replacement.colorspace_settings.name = image.colorspace_settings.name
        replacement.pack()
        for material in bpy.data.materials:
            if material.use_nodes:
                for node in material.node_tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image == image:
                        node.image = replacement
for mesh in meshes:
    bpy.context.view_layer.objects.active = mesh
    types = [item.identifier for item in bpy.types.Modifier.bl_rna.properties["type"].enum_items]
    modifier = mesh.modifiers.new("Game-ready survivor", next(value for value in types if value == "DECIMATE"))
    modifier.ratio = 0.10
    while mesh.modifiers[0] != modifier:
        bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    print("SURVIVOR POLYGONS", len(mesh.data.polygons))

# Author a standing idle from the walk cycle's relaxed standing pose.
# Walk and run are preserved from the download; physics owns root movement.
rig.animation_data.action = None
walk = next(track.strips[0].action for track in rig.animation_data.nla_tracks if track.name.lower() == "walk")
idle = walk.copy()
idle.name = "idle"
for curve in idle.fcurves:
    value = curve.evaluate(walk.frame_range[0])
    while curve.keyframe_points:
        curve.keyframe_points.remove(curve.keyframe_points[-1], fast=True)
    curve.keyframe_points.insert(1, value)
    curve.keyframe_points.insert(61, value)
idle.use_fake_user = True
track = rig.animation_data.nla_tracks.new()
track.name = "idle"
track.strips.new("idle", 1, idle)
for track in rig.animation_data.nla_tracks:
    track.mute = False
bpy.context.scene.frame_set(1)
formats = [item.identifier for item in bpy.ops.export_scene.gltf.get_rna_type().properties["export_format"].enum_items]
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / "assets/models/survivor_soldier.glb"),
    export_format=next(value for value in formats if value == "GLB"),
    export_animations=True,
    export_nla_strips=True,
    export_force_sampling=True,
    export_frame_range=False,
    export_cameras=False,
    export_lights=False,
)
print("EXPORTED survivor_soldier.glb")
