# OpenGoFootball — Milestone 1

Independent Godot 4 football engine. This milestone only renders **Neftyanik Stadium** (`st009`) from a GLB. No gameplay.

PES 2021 files are an external asset format. This repo does not include Fox Engine code.

## Run

1. Open `game/project.godot` in Godot 4.3+.
2. Drop `Neftyanik.glb` into `stadiums/neftyanik/` if it is not already there.
3. Press Play. Right-drag to orbit, scroll to zoom.

## Pipeline

PES FPK/FPKD → extract FMDL/FTEX → Blender (headless) → `Neftyanik.glb` → this project.

Axis conversion is a **single import-time matrix** applied when baking the GLB. Ground truth: pitch length 115 m along X, width 76 m along Z, goal width. Do not sprinkle Y-up fixes in engine code.

## Layout

- `scenes/Main.tscn` — camera, sun, environment
- `stadiums/neftyanik/` — GLB lives here
