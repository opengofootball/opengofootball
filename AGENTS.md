# AGENTS.md — OpenGoFootball

Guidance for AI coding agents working in this repository.

## Project overview

OpenGoFootball is an independent football game built on the **Godot Engine**. The first
technical objective (Milestone 1) is a **vertical slice**: load, convert, and render a
PES 2021 community stadium (Neftyanik, `st009`) inside Godot. No gameplay yet.

PES 2021 files are treated as **external asset formats** that are investigated and
converted. The repository does **not** include or depend on proprietary Fox Engine
source code. The PES Stadium Exporter and its `StadiumLibs/` are a reverse-engineering
reference only.

```
PES FPK/FPKD -> extract FMDL/FTEX -> Blender (headless) -> Neftyanik.glb -> Godot
```

## Engine / toolchain versions

- **Godot**: `4.6.3` stable, **Windows** build
  (`Godot_v4.6.3-stable_win64.exe`). Project targets the **Mobile** renderer
  (`project.godot` declares `config/features=PackedStringArray("4.6", "Mobile")`) so it
  runs on all platforms (desktop, Android, iOS).
- **Blender**: `5.1.1` (used headless for the FMDL -> GLB bake).
- Target platform is **Windows** initially.

> Note: the Linux dev box here has **no Blender installed**. Godot, Blender,
> `FtexTools.exe`, `GzsTool.exe`, and `texconv.exe` are Windows binaries. Rendering,
> texture re-import, and GLB baking must be executed/validated on the Windows machine;
> this box is used to author and refine scripts, scenes, and config. A Linux headless
> Godot (`Godot_v4.6.3-stable_linux.x86_64`) IS available for **parse/instantiation
> sanity checks** via `--headless --path game --script` (e.g. validate script loads);
> it does not render.

## Repository layout

```
OpenGoFootball/
├── AGENTS.md                  <- this file
├── Godot_v4.6.3-stable_win64.exe
├── PESBUL_2021_Server_Connector.bat   (separate integration target, not a dependency)
├── Assets/                    <- raw PES 2021 stadium source assets (FTEX/FPK, read-only input)
│   └── Stadium/Neftyanik Stadium/...
├── PES Exporter/              <- PES Stadium Exporter reference implementation
│   └── StadiumLibs/           <- FmdlFile.py, Ftex.py, IO.py, PesFox*.py (reference parsers)
├── work/
│   ├── m1-extract/            <- FPK/FPKD extraction output (st009_fpk, st009_fpkd, pitch_st009_*)
│   └── stadiums/neftyanik/    <- baked stadium assets, KEPT OUT of the Godot project
│       ├── Neftyanik.glb      <- baked stadium visual shell (stands/roof)
│       ├── pitch.gdshader     <- source for game/field/football_field.gdshader
│       ├── pitch/             <- turf_alp, turf_green, detail, grain, normal, srm PNGs
│       └── README.md          <- (plus baked GLB textures)
└── game/                      <- the Godot 4 project (open game/project.godot)
    ├── project.godot
    ├── scenes/
    │   ├── Main.tscn          <- camera, sun, environment, Stadium + Player + Ball (run scene)
    │   ├── default_stadium.tscn <- shared Stadium: FootballField + StadiumVisual slot
    │   ├── orbit_camera.gd    <- right-drag orbit, scroll zoom
    │   ├── player.gd/.tscn    <- Ch38 Mixamo player + Stage 3.1 foot IK + Stage 4 hooks
    │   ├── foot_ik.gd         <- TwoBoneIK3D foot-ground + ball IK mode
    │   ├── football_interaction.gd <- Stage 4 state machine (APPROACH/CONTROL/DRIBBLE/PASS/SHOOT)
    ├── ball/                  <- football simulation + visual (Stage 4)
    │   ├── ball.gd            <- CharacterBody3D custom physics (gravity/friction/bounce)
    │   ├── ball.tscn          <- ball scene (mesh + collision + BallDetector)
    │   └── visual/            <- Loafbrr CC0 football assets (Balls.glb + textures)
    ├── field/                 <- karl-grass pitch ground (pure Godot, no GLB)
    │   ├── football_field.gd  <- static collision + MownGrass grid + FarImpostor
    │   ├── football_field.tscn
    │   ├── football_field.gdshader <- (unused now; flat turf shader kept on disk)
    │   ├── grass/             <- mown-blade grass, port of karl/godot-grass (Unlicense)
    │   │   ├── grass_multimesh_detailed.tres/_simple.tres <- shared baked MultiMeshes
    │   │   ├── grass_grid.gd/.tscn     <- rectangular chunk grid across the field
    │   │   ├── grass_chunk.gd/.tscn    <- per-cell shared .tres LOD + impostor fade
    │   │   ├── grass.gd/.gdshader      <- blade helper + mown blade shader
    │   │   ├── impostor_grass.gdshader <- distance impostor plane
    │   │   └── grass-stalk(+-simple).obj, grass_normals.png, LICENSE.unlicense
    │   └── turf/              <- 6 PNG copies shared down from work/stadiums/neftyanik/pitch
    ├── characters/            <- Ch38_nonPBR.fbx (default player), mixamo/ FBX pack, .tres clips
    └── tools/                 <- conversion / retarget scripts
        ├── convert_neftyanik.py      <- headless FMDL -> GLB bake (output to work/stadiums/)
        ├── prep_pitch_textures.py    <- DDS -> PNG for the pitch
        ├── retarget_mixamo.gd        <- Mixamo FBX -> Ch38 mixamorig5_* .tres
        └── verify_retarget.gd / verify_foot_ik.gd
```

## The game (Godot) project

- Open `game/project.godot` in Godot 4.3+ (4.6.3 used).
- `run/main_scene="res://scenes/Main.tscn"`.
- M1 renders the parametric field; Neftyanik stands/roof attach later as a visual shell.

### The shared Stadium (`default_stadium.tscn`)

```
Stadium (Main.tscn)
└── Stadium (instance of res://scenes/default_stadium.tscn)
    ├── FootballField         standardized, parametric, pure Godot (game/field/)
    └── StadiumVisual         empty Node3D placeholder for community stands/roof/buildings
    └── Player                grounds to field surface Y=0
```

- `Main.tscn` instances `default_stadium.tscn` as the `Stadium` node.
- `FootballField` is the karl-grass pitch ground (`field/football_field.gd`): a static
  collision box plus a grid of mown-grass chunks with LOD impostors — pure Godot.
  **No Blender, no GLB.**
- `StadiumVisual` is the (currently empty) slot where a community stadium's baked
  visual shell (e.g. Neftyanik stands/roof) is attached later.

### The pitch ground (`game/field/`)

- Recreated from zero on the karl/godot-grass stack. `football_field.gd` exports
  `field_length` (115) and `field_width` (76); it builds only:
  - a single `StaticBody3D` ground box (`Collision/Ground`) so the player stands,
  - a `Grass/MownGrass` karl chunk grid (`field/grass/grass_grid.tscn`), and
  - a field-sized `FarImpostor` base plane (`Grass/FarImpostor`, 119×80).
- **No surface/Lines/Goals/no turf shader carpet** anymore — the ground is pure grass
  (karl chunk LOD + impostors). `get_center_spot()` and `get_field_rect()` remain for the
  player/camera; `get_goal_position(team)` returns `Vector3.ZERO` (no goals mid-M1).
- Coordinates (locked): center=(0,0,0), +X=length, +Z=width, surface top at Y=`surface_y`
  (default 0). Y-up.

### Player collision (PES/UFL model) — no per-body-part shapes

- The player is a single kinematic **`CharacterBody3D` + one `CapsuleShape3D`**
  (locomotion + body-vs-body/ground). This mirrors PES/UFL: animated players do **not**
  carry per-bone collision. Per-part rigid bodies only appear later as an on-demand
  **ragdoll** on fouls (a deferred milestone, not this M1 movement slice).
- Ball/foot interaction is a dedicated **`BallContact` `Area3D`** child of `Player`
  (sphere r≈0.12, `collision_layer=4` / bit 3, `collision_mask=1`, `monitoring=true`)
  plus a short **`FootRay`** `RayCast3D` for "ball in reach ahead". This is the seed of
  the pass/kick/possession system — **no** extra colliders on the body.
- `player.gd` helpers: `get_ball_contact()`, `ball_in_reach()`, and `get_foot_pos(side)`
  which resolves the animatev `Left Foot` / `Right Foot` skeleton bone (fallen back to
  the `BallContact` origin) — the PES-style "which foot" read driven by animation, not a
  per-foot collider. `debug_physics := false` gates a `_debug_dump()` print called from
  `_physics_process`.
- Ragdoll-for-fouls (later): swap the kinematic body for a skeletal `RigidBody3D` +
  `Generic6DOFJoint3D` set on a tackle impulse. Not implemented mid-M1.

### Player locomotion clips — Mixamo on Ch38 (no Blender)

- Default mesh is **Ch38** (`res://characters/Ch38_nonPBR.fbx`, `mixamorig5_*` bones).
  Superhero / UAL stay on disk unused. Input: **W** = `Jog_Fwd`, **S** = `Jog_Back`,
  **E+W** = `Dribble`, idle = `Soccer_Idle`. Extra Mixamo soccer clips load into the
  AnimationPlayer library but are not input-mapped yet.
- **Source**: Mixamo soccer pack in `game/characters/mixamo/` (FBX for Unity, Without
  Skin, ~30 fps, In Place, exported on Ch38 except `Dribble.fbx` which is short-name).
- **Retarget (world-space)**: `game/tools/retarget_mixamo.gd` (headless) maps source
  rotations onto Ch38 `mixamorig5_*`. Same-rig Mixamo clips identity-map `mixamorig5_*`;
  X Bot uses `mixamorig_*` → `mixamorig5_*`; Dribble uses the short-name table. Root/hips
  **position** tracks are dropped (locomotion is code-driven). Track paths are
  `Skeleton3D:mixamorig5_<bone>`. Run:
  `--headless --path game --script res://tools/retarget_mixamo.gd`
- **Retarget validation**: `--headless --path game --script res://tools/verify_retarget.gd`
- **Wiring** (`player.gd`): `MIXAMO_CLIPS` loads every `.tres` via
  `AnimationLibrary.add_animation()`.

### Stage 3.1 foot → ground IK (presentation only)

- `foot_ik.gd` on `Player/IK` does **not** drive simulation. After Ch38 instantiates it
  parents two `TwoBoneIK3D` nodes under the model's `Skeleton3D` (Godot requires
  `SkeletonModifier3D` as a skeleton child — do not create a second skeleton).
- Chains: `mixamorig5_LeftUpLeg → LeftLeg → LeftFoot` and the Right* pair. Targets/poles
  live under `Player/IK`; `GroundDetection` Left/RightFootRay exclude the player capsule
  (rays start inside it). Each physics frame: lerp the target to
  `hit + UP * 0.03`, clamp foot tilt to ~15°, `influence = 0.5`.
- Foot plant/swing and pelvis offset are **not** in 3.1 — walking may look glued.
- Headless check: `--headless --path game --script res://tools/verify_foot_ik.gd`

### Stage 4 — Football interaction (ball approach / control / dribble / pass / shoot)

- **Architecture**: `FootballInteraction` is a child `Node3D` of `Player`, separate from
  `player.gd` (movement) and `foot_ik.gd` (IK). The ball (`ball.gd` / `ball.tscn`) is
  an independent `CharacterBody3D` on collision layer 2. It is **never** reparented.
- **State machine** (`football_interaction.gd`): `NONE → APPROACH → CONTROL → DRIBBLE`.
  `PASS` and `SHOOT` are transient states that fire an impulse then return to `APPROACH`.
- **Ball detection**: `FootballInteraction` reads the ball reference directly (no
  `BallDetector` area; detection is fully parametric). Tunables for the "in reach" gate:
  `detection_distance` (2.0 m), `detection_angle_deg` (90° — frontal cone in player-local
  space), `max_ball_height` (0.5 m), `control_distance` (1.0 m). The player-local cone
  filter (`_ball_within_angle()`) prevents acting on balls behind the player, relaxed
  within 0.8 m.
- **Dynamic foot selection**: `to_local(ball.global_position).x < 0 → left foot`, else
  right. Selection happens on entering `CONTROL`. Exposed via `get_active_foot()`.
- **Ball IK** (`foot_ik.gd`): `set_ball_ik(active, foot, target, influence)` switches the
  active foot's `TwoBoneIK3D` target from ground raycast to ball contact point. The other
  foot keeps ground IK. Influence is `0.5` (same as ground). Ball IK is active during
  `CONTROL` and `DRIBBLE`, off otherwise.
- **Reach weighting**: `max_foot_reach` (1.3 m) + `reach_fade` (0.25 m) drive a smooth
  curve so BallIK influence → 0 beyond leg reach (prevents leg overextension). The active
  foot's `TwoBoneIK3D.influence` = `influence × reach_weight`.
- **Smooth IK blend**: `foot_ik.gd` ramps `_ball_ik_influence` with `move_toward`
  (`_ball_ik_blend_speed`), so BallIK eases in/out instead of snapping. Ground foot
  influence is restored on deactivation.
- **Ball orientation**: `_orient_foot_basis()` turns the active foot target toward the
  ball so the foot naturally faces its approach direction.
- **Debug visuals**: `foot_ik.gd` `debug_visuals := false` draws unshaded spheres at the
  foot target (orange) and ball (cyan) for tuning; `football_interaction.gd`
  `debug_interactions` prints state/foot/distance/height/reach/detected.
- **Possession**: Logical flag only — `has_ball()` returns `true` in `CONTROL` or
  `DRIBBLE`. The ball remains a free-simulating `CharacterBody3D`.
- **Dribble**: Continuous velocity steering in `_update_dribble()`. Each physics frame
  sets `ball.velocity = player.velocity + spring_correction` toward a target at
  `dribble_forward_offset` (0.6) + `dribble_side_offset` (0.15) from the player, so the
  ball rides in front during `DRIBBLE`.
- **Pass** (`Q`): Impulse in player forward direction at `pass_power` (8.0).
- **Shoot** (`F`): Impulse at `shoot_power` (18.0) with `shoot_elevation` (0.8 m/s).
- **Ball physics** (`ball.gd`): Manual gravity, ground friction, air drag, bounce
  (coefficient 0.5). `apply_touch(impulse)` and `apply_shot(direction, power, elevation)`
  are the gameplay API. Ball mass 0.43 kg (FIFA size 5).
- **Kick animation**: `pass`/`shoot` gate on `_ball_in_control_range()` and call
  `player.play_kick("Kick_Soccerball")` (0.5 s `_kick_anim_timer`).
- **Input**: `Q` = pass, `F` = shoot. Player turn speed reduced during ball control
  (`control_turn_speed`).
- **Ball asset**: Loafbrr CC0 football — `game/ball/visual/Balls.glb` mesh +
  `Football_Ball.tres` (text StandardMaterial3D referencing local 1k textures).
- **Collision layers**: Player = 1, Ball = 2, Ground = 1. Player↔Ball collision
  exceptions are set so the capsule and ball don't physically block each other.
- Headless verify: `--headless --path game --script res/tools/verify_foot_ik.gd` (still
  validates Stage 3 IK + bones).

### Short 3D mown grass (`field/grass/` — port of karl/godot-grass)

- The pitch grass is a port of **`git.hexaquo.at/karl/godot-grass`** (geometry grass
  MultiMesh shader + chunk/LOD system from the "Grass Rendering Series" at hexaquo.at),
  **public domain (Unlicense)** — `field/grass/LICENSE.unlicense`. It fully **replaces**
  the old SimpleGrassTextured plugin integration (plugin, `plugin_grass.gd`, `%SimpleGrass`
  autoload, `[editor_plugins]`, and `[shader_globals] sgt_*` block are all gone from
  `project.godot`).
- **Architecture** (`game/field/grass/`) — faithful to karl, but using **shared baked
  `.tres` MultiMeshes** instead of runtime scatter:
  - `grass_multimesh_detailed.tres` / `_simple.tres` — the original karl baked
    MultiMeshes (10000 instances per 5×5 cell, meshes `grass-stalk.obj` /
    `grass-stalk-simple.obj`), copied verbatim and paths retargeted to
    `res://field/grass/`. Shared by every chunk (karl repeats the patch per cell).
  - `grass_grid.gd/.tscn` — lays a rectangular grid of chunks across `field_length × field_width`
    (default 115×76 along X×Z, `cell_size` 5 → 368 chunks). Lazily resolves and propagates the **Player**
    to every chunk's `Grass` node in `_process` (player is instanced after the field in `Main.tscn`).
  - `grass_chunk.gd/.tscn` — one `cell_size` cell with karl's node structure
    `Ground` (black base plane) + `Grass` (MultiMeshInstance3D = detailed `.tres`) +
    `Impostor` (5×5 plane). `_process` swaps in the **simple** `.tres` past `lod_switch`,
    and fades the `Impostor` in (`impostor_grass.gdshader`) as the grass fades out.
  - `grass.gd` — `MultiMeshInstance3D` helper that pushes `object_position`/`object_radius`
    (the **player**) to its material every frame so blades bend around the character.
  - `grass.gdshader` — real blade shader: UV `bottom_to_top`, `blade_bend`, **patch/mottle**
    (`size_small/large`, `color_small/large` via `patch_noise`), base AO, `BACKLIGHT`,
    dithered `ALPHA_HASH` soft edges, **`mow_height`** clipping (mows to a flat short blade), and
    an enabled **player `object_bend`** block. **Wind is removed** (static mown turf; the only
    motion is player interaction). `NORMAL` flattening is left off so 3D blade normals stay.
  - `impostor_grass.gdshader` — distance impostor (uses `grass_normals.png`), wind removed.
- **Mown height**: blade native is ~1m; visible height ≈ `mow_height` × the karl baked
  per-instance scale (default `mow_height` 0.5 with `size_small/large` 0.5/0.9 →
  roughly 0.2–0.5 m). Tune the shader params (`size_small/large`, `mow_height`) on Windows.
- **`football_field.gd`**: `_build_grass()` instantiates `grass_grid.tscn` under
  `FootballField/Grass` as `MownGrass`, plus a field-sized `FarImpostor` base plane
  (impostor shader). `grass_enabled` toggle unchanged.
- **Perf**: 368 chunks share two `.tres` (each 10000 instances) — every chunk renders
  the full repeat patch, so far chunks switch to the simple `.tres` via LOD. Tune
  `cell_size` / LOD distances on Windows for the Mobile budget.
- Render quality, LOD distances (`lod_switch`/fade ranges), mown height, and the player bend radius
  (`object_radius` ≈1.2) are all confirmed/tuned only on Windows (Linux can't render).

### Pitch rendering (`football_field.gdshader`)

- **Removed in the from-zero recreation** — the flat turf-shader carpet, FIFA
  marking mesh, procedural goals, and `concrete_apron.gd` are all gone. The pitch is
  pure karl grass (chunks + impostors) over a static collision box. (`football_field.gdshader`
  and `field/turf/` textures remain on disk but are unused; `football_field.gd` no longer
  references them.)
- When a community GLB shell is later attached under `StadiumVisual`, its baked field
  meshes (by name `pitch_0`, `center2_4`, or material `grass`, `pitch_ed`) should be
  hidden so the shared field shows (formerly the `stadium_loader.gd` behavior, now removed).

## Engine coordinate / scale conventions

- **Axis conversion is a single import-time matrix** applied when baking the GLB —
  do NOT sprinkle per-node Y-up/rotation "fixes" in engine scripts.
- Ground-truth references: pitch length 115 m along X, width 76 m along Z, goal width.

## Key facts / gotchas (learned)

- **Texture mipmaps**: `football_field.gdshader` (and `pitch.gdshader`, the grass
  `grass.gdshader`) samples pitch/grass textures with `filter_linear_mipmap`. Every `.PNG.import`
  in `field/turf/` (and `field/grass/grass_normals.png`) must have
  `mipmaps/generate=true`, or the grass can render **magenta** (Godot error/fallback material).
  After editing any `.import`, the textures must be **re-imported** in the Godot editor
  (regenerates the `.godot/imported/*.ctex`, incl. the large 4096x2048 ones). New grass
  textures also need one import pass before the first headless/runtime load.
- `turf_nrm.PNG` should be imported as a normal map (`compress/normal_map=1`).
- The main-stadium FMDLs are `center1/2/3` + `st009_pitch` (in `st009_fpk` /
  `pitch_st009_fpk`). The `back1/2, front1/2/3, left1/2, right1/2` MAIN FMDLs listed in
  `st009_modelset.fox2.xml` are **absent from the community pack** — not a converter bug.
- FTEX -> DDS pure-Python decoding (`StadiumLibs/Ftex.ftexToDds`) currently hits a
  "Decompression error" and falls back to `FtexTools.exe` (Windows).

## Commands

You generally run on this Linux box only for **authoring/refining** files. The heavy,
Windows-only steps are run by the user:

```text
# Bake the GLB (Windows, Blender 5.1.1 behind the scenes):
blender --background --python game/tools/convert_neftyanik.py

# Prepare pitch DDS -> PNG (Windows, texconv.exe):
python game/tools/prep_pitch_textures.py

# Open the game:
#   run game/project.godot in Godot 4.6.3 (Windows)
#   then re-import field/turf/ (and stadiums/neftyanik/pitch/) after any .import change.
```

## Naming / conventions

- Keep the Godot game independent of PES formats: conversions happen offline and get
  committed as `.glb` + textures.
- Scripts follow the existing GDScript style (tabs, snake_case, type hints).
- Do not hard-code axis fixes in engine code; keep them in the bake/import stage.
