"""Headless FMDL -> GLB bake for OpenGoFootball M1. Run with Blender 5.1 --background."""
import os
import sys
import traceback
import subprocess

import bpy
import addon_utils

EXTRACT = r"C:\Users\csantz\Documents\OpenGoFootball\work\m1-extract"
TEX_DIR = r"C:\Users\csantz\Documents\OpenGoFootball\Assets\Stadium\Neftyanik Stadium\Asset\model\bg\st009\sourceimages\tga\#windx11"
FTEX_TOOLS = r"C:\Users\csantz\Documents\OpenGoFootball\PES Exporter\StadiumLibs\Gzs\FtexTools.exe"
OUT_GLB = r"C:\Users\csantz\Documents\OpenGoFootball\game\stadiums\neftyanik\Neftyanik.glb"

FMDLS = [
    (os.path.join(EXTRACT, r"st009_fpk\Assets\pes16\model\bg\st009\scenes\center1.fmdl"), "center1"),
    (os.path.join(EXTRACT, r"st009_fpk\Assets\pes16\model\bg\st009\scenes\center2.fmdl"), "center2"),
    (os.path.join(EXTRACT, r"st009_fpk\Assets\pes16\model\bg\st009\scenes\center3.fmdl"), "center3"),
    (os.path.join(EXTRACT, r"pitch_st009_fpk\Assets\pes16\model\bg\st009\scenes\st009_pitch.fmdl"), "pitch"),
]


def log(msg):
    print(msg, flush=True)


def enable_addon():
    for mod in ("PES_Stadium_Exporter",):
        try:
            addon_utils.enable(mod, default_set=True, persistent=True)
            log("enabled addon %s" % mod)
            return
        except Exception as e:
            log("enable %s failed: %s" % (mod, e))
    raise RuntimeError("Could not enable PES_Stadium_Exporter")


def convert_ftex():
    from StadiumLibs import Ftex
    n = 0
    ok_py = 0
    ok_exe = 0
    for name in os.listdir(TEX_DIR):
        if not name.lower().endswith(".ftex"):
            continue
        ftex = os.path.join(TEX_DIR, name)
        dds = ftex[:-5] + ".dds"
        if os.path.isfile(dds) and os.path.getsize(dds) > 0:
            continue
        try:
            Ftex.ftexToDds(ftex, dds)
            n += 1
            ok_py += 1
        except Exception as e:
            log("Ftex.ftexToDds failed %s: %s — trying FtexTools.exe" % (name, e))
            try:
                r = subprocess.run(
                    [FTEX_TOOLS, name],
                    cwd=TEX_DIR,
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
                log(
                    "FtexTools %s exit=%s stdout=%s stderr=%s"
                    % (
                        name,
                        r.returncode,
                        (r.stdout or "").strip()[:300],
                        (r.stderr or "").strip()[:300],
                    )
                )
            except Exception as e2:
                log("FtexTools spawn failed %s: %s" % (name, e2))
            n += 1
            if os.path.isfile(dds) and os.path.getsize(dds) > 0:
                ok_exe += 1
    dds_count = len([x for x in os.listdir(TEX_DIR) if x.lower().endswith(".dds")])
    log("converted/attempted %d ftex (python=%d ftextools=%d) dds_now=%d" % (n, ok_py, ok_exe, dds_count))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)


def import_fmdls():
    from PES_Stadium_Exporter import importFmdlfile, node_group

    scn = bpy.context.scene
    for attr, val in (
        ("fmdl_import_extensions_enabled", True),
        ("fmdl_import_loop_preservation", True),
        ("fmdl_import_mesh_splitting", True),
        ("fmdl_import_load_textures", True),
        ("fmdl_import_all_bounding_boxes", False),
        ("fixmeshesmooth", True),
    ):
        if hasattr(scn, attr):
            setattr(scn, attr, val)

    try:
        node_group()
    except Exception as e:
        log("node_group skipped: %s" % e)

    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
    root = bpy.context.active_object
    root.name = "Neftyanik"

    ok = 0
    for path, name in FMDLS:
        if not os.path.isfile(path):
            log("MISSING %s" % path)
            continue
        log("IMPORT %s (%d bytes)" % (name, os.path.getsize(path)))
        try:
            importFmdlfile(path, "Skeleton_%s" % name, name, name, TEX_DIR, "Neftyanik")
            ok += 1
        except Exception:
            log("FAIL %s\n%s" % (name, traceback.format_exc()))
    log("imported %d / %d fmdl" % (ok, len(FMDLS)))
    log("meshes=%d objects=%d images=%d" % (
        len(bpy.data.meshes), len(bpy.data.objects), len(bpy.data.images)))
    with_pixels = 0
    for im in bpy.data.images:
        w = im.size[0] if im.size else 0
        h = im.size[1] if im.size else 0
        has = w > 0 and h > 0
        if has:
            with_pixels += 1
        log("  img %s %dx%d packed=%s file=%s" % (
            im.name, w, h, bool(im.packed_file), im.filepath))
    log("images with pixels: %d / %d" % (with_pixels, len(bpy.data.images)))
    return ok


def export_glb():
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    kwargs = dict(
        filepath=OUT_GLB,
        export_format="GLB",
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
    )
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_extras", None)
        try:
            bpy.ops.export_scene.gltf(**kwargs)
        except TypeError:
            bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB")
    size = os.path.getsize(OUT_GLB) if os.path.isfile(OUT_GLB) else 0
    log("WROTE %s (%d bytes)" % (OUT_GLB, size))
    if size < 1000:
        raise RuntimeError("GLB too small")


def main():
    log("Blender %s" % bpy.app.version_string)
    enable_addon()
    convert_ftex()
    clear_scene()
    ok = import_fmdls()
    if ok == 0:
        raise RuntimeError("no FMDLs imported")
    export_glb()
    log("DONE")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
