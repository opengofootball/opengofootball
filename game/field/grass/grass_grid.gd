@tool
extends Node3D

## Lays a grid of pitch-grass chunks across a rectangular area
## (field_length along X × field_width along Z). Each chunk is a `cell_size` square.
## Ported from karl/godot-grass (Unlicense) for a fixed field. Chunks reference the
## shared baked MultiMesh .tres (no runtime blade scatter).

@export var field_width := 76.0
@export var field_length := 115.0
@export var cell_size := 5.0

@export var player: Node3D = null

# Texture-only test mode: when false, every chunk hides its blades and shows
# only the flat impostor plane (solid green fill).
@export var blades_enabled := true

const CHUNK := "res://field/grass/grass_chunk.tscn"


func _ready() -> void:
	reload()


func _process(_delta: float) -> void:
	# The player may not exist yet when we build (it is instanced later in the
	# scene). Resolve it lazily once it appears and propagate to the chunks.
	if player == null:
		var found := _find_player()
		if found != null:
			player = found
			_propagate_player()


func _find_player() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	var found := root.find_child("Player", true, false)
	if found is Node3D:
		return found
	return null


func _propagate_player() -> void:
	for chunk in get_children():
		var g: Node3D = chunk.get_node_or_null("Grass")
		if g != null and g is MultiMeshInstance3D:
			var mmi := g as MultiMeshInstance3D
			mmi.set("player", player)


func reload() -> void:
	for child in get_children():
		child.queue_free()

	var cols := int(ceil(field_length / cell_size))
	var rows := int(ceil(field_width / cell_size))

	for r in rows:
		for c in cols:
			var chunk: Node3D = load(CHUNK).instantiate()
			chunk.position = Vector3(
				(c - (cols - 1) * 0.5) * cell_size,
				0.0,
				(r - (rows - 1) * 0.5) * cell_size
			)
			chunk.blades_enabled = blades_enabled
			add_child(chunk)