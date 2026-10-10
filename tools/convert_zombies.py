"""Convert downloaded CC0 FBX assets to textured, animated game-ready GLBs.

Run with an isolated Blender --background --factory-startup process.
"""
import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "tools" / "sources"
OUTPUT = ROOT / "assets" / "models"


def reset():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def image(path, non_color=False, max_size=2048):
    texture = bpy.data.images.load(str(path), check_existing=True)
    if max(texture.size) > max_size:
        factor = max_size / max(texture.size)
        texture.scale(int(texture.size[0] * factor), int(texture.size[1] * factor))
    if non_color:
        valid = [i.identifier for i in texture.colorspace_settings.bl_rna.properties["name"].enum_items]
        if "Non-Color" in valid:
            texture.colorspace_settings.name = "Non-Color"
    texture.pack()
    return texture


def textured_material(material, albedo, normal):
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    output = nodes.new("ShaderNodeOutputMaterial")
    shader.inputs["Roughness"].default_value = 0.82
    material.node_tree.links.new(shader.outputs[0], output.inputs[0])
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image(albedo)
    material.node_tree.links.new(texture.outputs[0], shader.inputs["Base Color"])
    if normal.exists():
        normal_texture = nodes.new("ShaderNodeTexImage")
        normal_texture.image = image(normal, True)
        normal_map = nodes.new("ShaderNodeNormalMap")
        normal_map.inputs["Strength"].default_value = 0.7
        material.node_tree.links.new(normal_texture.outputs[0], normal_map.inputs["Color"])
        material.node_tree.links.new(normal_map.outputs[0], shader.inputs["Normal"])


def transfer_action(rig, source_rig, name, prefix=None):
    source_action = source_rig.animation_data.action
    if prefix:
        # FBX animation-only files have different rest-bone orientations. Merely
        # renaming curves leaves arms in a T-pose; bake world-space FK retargeting.
        rig.animation_data_create()
        for track in rig.animation_data.nla_tracks:
            track.mute = True
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        source_names = {bone.name.split(":")[-1]: bone.name for bone in source_rig.data.bones}
        constraint_types = [i.identifier for i in bpy.types.Constraint.bl_rna.properties["type"].enum_items]
        for bone in rig.pose.bones:
            suffix = bone.name.split(":")[-1]
            if suffix not in source_names:
                continue
            constraint = bone.constraints.new(next(v for v in constraint_types if v == "COPY_ROTATION"))
            constraint.target = source_rig
            constraint.subtarget = source_names[suffix]
            for property_name in ["target_space", "owner_space"]:
                valid = [i.identifier for i in constraint.bl_rna.properties[property_name].enum_items]
                setattr(constraint, property_name, next(v for v in valid if v == "WORLD"))
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bake_types = [i.identifier for i in bpy.ops.nla.bake.get_rna_type().properties["bake_types"].enum_items]
        bpy.ops.nla.bake(frame_start=int(source_action.frame_range[0]), frame_end=int(source_action.frame_range[1]), step=1, only_selected=False, visual_keying=True, clear_constraints=True, use_current_action=True, bake_types={next(v for v in bake_types if v == "POSE")})
    else:
        action = source_action.copy()
        action.name = name
    # Eliminate planar root motion: movement and collision are controlled by Rust/Godot.
    for curve in list(action.fcurves):
        if not curve.data_path.startswith("pose.bones"):
            action.fcurves.remove(curve)
            continue
        if curve.data_path.endswith(".location") and any(token in curve.data_path for token in ["Hips", '"root"', '"joint1"']):
            keys = curve.keyframe_points
            if len(keys) > 1:
                first, last = keys[0].co.copy(), keys[-1].co.copy()
                for key in keys:
                    progress = (key.co.x - first.x) / max(last.x - first.x, 1)
                    key.co.y -= (last.y - first.y) * progress
    action.use_fake_user = True
    rig.animation_data_create()
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.mute = bool(prefix)
    strip = track.strips.new(name, 1, action)
    strip.name = name
    # All clips start at frame 1 and are exported as individual NLA tracks.
    return action


def export(rig, meshes, filename):
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks:
        track.mute = False
    bpy.context.scene.frame_set(1)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
        for polygon in mesh.data.polygons:
            polygon.use_smooth = True
    bpy.context.view_layer.objects.active = rig
    formats = [item.identifier for item in bpy.ops.export_scene.gltf.get_rna_type().properties["export_format"].enum_items]
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT / filename),
        export_format=next(value for value in formats if value == "GLB"),
        use_selection=True,
        export_animations=True,
        export_nla_strips=True,
        export_force_sampling=True,
        export_frame_range=False,
        export_cameras=False,
        export_lights=False,
    )
    print("EXPORTED", filename)


reset()
city = SOURCES / "city-zombie"
bpy.ops.import_scene.fbx(filepath=str(city / "InfectedCityMan.fbx"))
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
rig.animation_data.action = None
for mesh in meshes:
    for material in mesh.data.materials:
        if "Body1" in material.name or "Outfit1" in material.name:
            base = city / ("InfectedCityMan_" + material.name)
            textured_material(material, Path(str(base) + "_BaseColor.png"), Path(str(base) + "_Normal.png"))
    if len(mesh.data.polygons) > 12000:
        bpy.context.view_layer.objects.active = mesh
        valid = [i.identifier for i in bpy.types.Modifier.bl_rna.properties["type"].enum_items]
        mod = mesh.modifiers.new("Game detail", next(v for v in valid if v == "DECIMATE"))
        mod.ratio = 0.42
        bpy.ops.object.modifier_apply(modifier=mod.name)
clips = {"walk": "Zombie Walk.fbx", "walk_alt": "Walking.fbx", "run": "Zombie Running.fbx", "attack": "Zombie Attack.fbx", "attack_alt": "Zombie Attack2.fbx", "death": "Zombie Dying.fbx", "hurt": "Zombie Reaction Hit.fbx", "idle": "Zombie Idle.fbx", "roar": "Zombie Scream.fbx"}
for name, file in clips.items():
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(city / file))
    source_rig = next(o for o in bpy.data.objects if o not in existing and o.type == "ARMATURE")
    transfer_action(rig, source_rig, name, "CityDeadOutfit:")
    for obj in list(bpy.data.objects):
        if obj not in existing:
            bpy.data.objects.remove(obj, do_unlink=True)
export(rig, meshes, "city_zombie.glb")

reset()
monster = SOURCES / "horror-monster"
bpy.ops.import_scene.fbx(filepath=str(monster / "Walk.fbx"))
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
rig = next(m.object for m in mesh.modifiers if m.type == "ARMATURE")
walk = transfer_action(rig, rig, "walk")
rig.animation_data.action = None
for material in mesh.data.materials:
    textured_material(material, monster / "test_StingrayPBS1SG_AlbedoTransparency.png", monster / "test_StingrayPBS1SG_Normal.png")
# Preserve mesh world transform but discard authoring controls and unrelated rigs.
matrix = mesh.matrix_world.copy()
mesh.parent = rig
mesh.matrix_world = matrix
for obj in list(bpy.data.objects):
    if obj not in [rig, mesh]:
        bpy.data.objects.remove(obj, do_unlink=True)
existing = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=str(monster / "Run.fbx"))
source_mesh = next(o for o in bpy.data.objects if o not in existing and o.type == "MESH")
source_rig = next(m.object for m in source_mesh.modifiers if m.type == "ARMATURE")
transfer_action(rig, source_rig, "run")
for obj in list(bpy.data.objects):
    if obj not in existing:
        bpy.data.objects.remove(obj, do_unlink=True)
# The walk source's skeletal pose includes a menacing forward lunge; use a shorter
# selected segment for melee if the pack has no dedicated attack clip.
attack = walk.copy()
attack.name = "attack"
track = rig.animation_data.nla_tracks.new()
track.name = "attack"
strip = track.strips.new("attack", 1, attack)
strip.action_frame_start = attack.frame_range[0]
strip.action_frame_end = min(attack.frame_range[0] + 18, attack.frame_range[1])
export(rig, [mesh], "horror_mutant.glb")
