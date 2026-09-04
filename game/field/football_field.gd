extends Node3D

# Standardized pitch ground built on the karl/godot-grass stack
# (game/field/grass/): a grid of grass chunks (shared baked MultiMesh .tres,
# detailed<->simple LOD + impostor fade) over a field-sized base impostor plane,
# plus a single StaticBody3D so the player has something to stand on.
#
# No surface/lines/goals anymore — the ground is pure grass.

# Field dimensions. Length along +X, width along +Z.
@export var field_length := 115.0
@export var field_width := 76.0
@export var surface_y := 0.0

# Places to drop generated geometry/colliders.
@export var collisions_parent_path := "Collision"
@export var grass_parent_path := "Grass"

# Short 3D mown grass (karl/godot-grass LOD). Texture-only test: set to
# false to hide the blades and show only the flat impostor green fill.
@export var blades_enabled := false

const GRASS_GRID := "res://field/grass/grass_grid.tscn"
const IMPOSTOR_SHADER := "res://field/grass/impostor_grass.gdshader"
const IMPOSTOR_NOISE := "res://field/grass/grass_normals.png"

var _collisions_parent: Node3D
var _grass_parent: Node3D


func _ready() -> void:
	_resolve_parents()
	_build_all()


func _resolve_parents() -> void:
	_collisions_parent = _ensure_node(collisions_parent_path)
	_grass_parent = _ensure_node(grass_parent_path)


func _ensure_node(path: String) -> Node3D:
	var existing := get_node_or_null(path)
	if existing != null and existing is Node3D:
		return existing
	var n := Node3D.new()
	n.name = path.get_file()
	add_child(n)
	return n


func _build_all() -> void:
	_build_collision()
	_build_grass()


# ── coordinates (kept for the player / camera) ─────────────────────────────

func half_length() -> float:
	return field_length * 0.5


func half_width() -> float:
	return field_width * 0.5


func get_center_spot() -> Vector3:
	return Vector3(0.0, surface_y, 0.0)


func get_goal_position(_team: String) -> Vector3:
	return Vector3.ZERO


func get_field_rect() -> AABB:
	return AABB(Vector3(-half_length(), surface_y, -half_width()), Vector3(field_length, 0.0, field_width))


# ── collision (static ground plane) ────────────────────────────────────────

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	_collisions_parent.add_child(body)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(field_length, 2.0, field_width)
	cs.shape = shape
	cs.position = Vector3(0.0, surface_y - 1.0, 0.0)
	body.add_child(cs)


# ── 3D mown grass (karl/godot-grass LOD) ──────────────────────────────────

func _build_grass() -> void:
	var grid: Node3D = load(GRASS_GRID).instantiate()
	grid.name = "MownGrass"
	grid.field_width = field_width
	grid.field_length = field_length
	grid.blades_enabled = blades_enabled
	_grass_parent.add_child(grid)

	# The field-size base impostor plane is only needed when real blades are
	# on; in texture-only mode the per-chunk impostors already cover the field.
	if blades_enabled:
		var far := MeshInstance3D.new()
		far.name = "FarImpostor"
		far.position = Vector3(0.0, surface_y - 0.01, 0.0)
		var plane := PlaneMesh.new()
		plane.size = Vector2(field_length + 4.0, field_width + 4.0)
		far.mesh = plane
		far.material_override = _make_impostor_material()
		_grass_parent.add_child(far)


func _make_impostor_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(IMPOSTOR_SHADER) as Shader
	var nrm := load(IMPOSTOR_NOISE) as Texture2D
	if nrm != null:
		mat.set_shader_parameter("baked_normals", nrm)
	var patch := FastNoiseLite.new()
	patch.seed = 1337
	patch.frequency = 0.05
	var patch_tex := NoiseTexture2D.new()
	patch_tex.seamless = true
	patch_tex.noise = patch
	mat.set_shader_parameter("patch_noise", patch_tex)
	mat.set_shader_parameter("patch_scale", 4.0)
	mat.set_shader_parameter("color_small", Color(0.24, 0.42, 0.16, 1.0))
	mat.set_shader_parameter("color_large", Color(0.36, 0.52, 0.18, 1.0))
	mat.set_shader_parameter("ground_color", Color(0.0, 0.0, 0.0, 1.0))
	return mat