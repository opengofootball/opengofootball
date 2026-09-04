"""
Blender diagnostic — list every MeshInstance3D (object) name and its material
in the baked Neftyanik GLB.

Run on Windows:
    blender --background --python game/tools/list_mesh_names.py
"""
import bpy
import sys

GLB_PATH = "game/stadiums/neftyanik/Neftyanik.glb"

# ── load ────────────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB_PATH)

print("\n" + "=" * 80)
print("MESH LIST — Neftyanik.glb")
print("=" * 80)
print(f"{'Object name':<40} {'Material':<30} {'Faces':>8}")
print("-" * 80)

for obj in bpy.data.objects:
    if obj.type != 'MESH':
        continue
    mesh = obj.data
    mat_name = "(none)"
    if obj.data.materials and obj.data.materials[0]:
        mat_name = obj.data.materials[0].name
    print(f"{obj.name:<40} {mat_name:<30} {len(mesh.polygons):>8}")

print("-" * 80)
total = sum(1 for o in bpy.data.objects if o.type == 'MESH')
print(f"Total mesh objects: {total}")
print("=" * 80)

bpy.ops.wm.quit_blender()
