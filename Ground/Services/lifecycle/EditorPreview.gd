@tool
extends Node

@onready var parent: GroundManager = get_parent()

func _ready():
	parent = get_parent()
	parent.init(null,null)
	await parent.ready

@export_group("Editor Preview")
@export_range(1, 10) var editor_preview_radius: int = 1
@export_enum("None", "Plains", "Mountain", "Village", "Lake") var editor_biome: int = 0
@export var generate_in_editor: bool = false:
	set(value):
		generate_in_editor = value
		if Engine.is_editor_hint() and is_inside_tree():
			if value:
				_editor_generate()
			else:
				_editor_clear()

func _editor_generate() -> void:
	_editor_clear()
	
	if editor_biome > 0:
		for i in parent.biome_manager.biomes.size():
			var biome_d:BiomeData = parent.biome_manager.biomes[i]
			if i != editor_biome -1:
				biome_d.biome_size = 0
	
	# Load textures and build shader material inline (avoids @tool dependency on GroundManager)
	var loaded_textures: Array = GameUtils.load_from_json(GroundConstants.TEXTURES_FILE_PATH, TextureData, "textures")
	for tex_data in loaded_textures:
		if tex_data.texture_path.is_empty():
			continue
		var tex = load(tex_data.texture_path)
		if tex:
			tex_data.texture = tex

	var generator := parent.chunk_manager
	var mat: ShaderMaterial = parent.texture_manager.shader_material

	var r: int = editor_preview_radius
	var total: int = (2 * r + 1) * (2 * r + 1)

	for rx in range(-r, r + 1):
		for ry in range(-r, r + 1):
			var loc := Vector2i(rx, ry)
			var thread_res := generator.get_chunk_thread_result(loc, GroundConstants.LOD_LEVELS.CLOSE)
			var chunk := GroundUtils.build_chunk(thread_res.chunk_data, mat, thread_res.lod_tier)
			chunk.mesh_instance.name = "EditorChunk_%d_%d" % [rx, ry]
			$"../Chunks".add_child(chunk.mesh_instance)
			chunk.mesh_instance.owner = get_tree().edited_scene_root

			if parent.decor_manager:
				var chunk_center := Vector3(loc.x * GroundConstants.CHUNK_SIZE + GroundConstants.CHUNK_SIZE * 0.5, 0, loc.y * GroundConstants.CHUNK_SIZE + GroundConstants.CHUNK_SIZE * 0.5)
				var blocked := {}
				for decor_d in parent.decor_manager.decor_datas:
					var transforms := parent.decor_manager.generate_transforms_for_decor(chunk_center, blocked, decor_d)
					if transforms.size() > 0:
						var decor_nodes: Array[Node3D] = parent.decor_manager.get_decor_meshes(decor_d, transforms)
						for node in decor_nodes:
							chunk.get_parent().add_child(node)
						chunk.decor_nodes = decor_nodes
	print("[EditorGen] Done! %d chunks." % total)

func _editor_clear() -> void:
	var to_remove: Array[Node] = []
	for child in $"../Chunks".get_children():
		child.queue_free()
	parent.init(null,null)
	print("[EditorGen] Cleared %d preview chunks." % to_remove.size())
