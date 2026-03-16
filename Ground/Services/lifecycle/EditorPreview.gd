@tool
extends Node

@onready var ground: Ground = get_parent()

func _ready():
	pass

# ── Editor Preview ──────────────────────────────────────────────────────
@export_group("Editor Preview")
@export_range(1, 10) var editor_preview_radius: int = 3
@export var generate_in_editor: bool = false:
	set(value):
		generate_in_editor = value
		if Engine.is_editor_hint() and is_inside_tree():
			if value:
				_editor_generate()
			else:
				_editor_clear()

# ── Editor preview generation — delegates to ChunkGenerator ──────────
func _editor_generate() -> void:
	_editor_clear()
	ground._create_managers()

	var r: int = editor_preview_radius
	var total: int = (2 * r + 1) * (2 * r + 1)

	var mat := ground._terrain_manager._build_shader_material()
	var generator := ChunkGenerator.new()
	generator.initialize(ground._noise, ground._biome_manager)

	for rx in range(-r, r + 1):
		for ry in range(-r, r + 1):
			var loc := Vector2i(rx, ry)
			var chunk_d := generator.generate_chunk_data(loc, GroundConstants.LOD_LEVELS.CLOSE)
			var chunk := GroundChunk.build_chunk(chunk_d, mat, false)
			chunk.mesh_instance.name = "EditorChunk_%d_%d" % [rx, ry]
			$"../Chunks".add_child(chunk.mesh_instance)
			chunk.mesh_instance.owner = get_tree().edited_scene_root

	print("[EditorGen] Done! %d chunks." % total)

func _editor_clear() -> void:
	var to_remove: Array[Node] = []
	for child in $"../Chunks".get_children():
		if child.name.begins_with("EditorChunk_"):
			to_remove.push_back(child)
	for child in to_remove:
		child.queue_free()
	print("[EditorGen] Cleared %d preview chunks." % to_remove.size())
