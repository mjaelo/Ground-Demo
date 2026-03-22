@tool
extends Node

@onready var ground: Ground = get_parent()

func _ready():
	await ground.ready
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

	# Set up noise
	var noise := FastNoiseLite.new()
	noise.frequency = GroundConstants.NOISE_FREQUENCY

	# Set up biome manager
	var biome_mgr := BiomeManager.new()

	# Load textures and build shader material inline (avoids @tool dependency on GroundManager)
	var loaded_textures: Array = GameUtils.load_from_json(
		GroundConstants.TEXTURES_FILE_PATH, TextureData, "textures")
	for tex_data in loaded_textures:
		if tex_data.texture_path.is_empty():
			continue
		var tex = load(tex_data.texture_path)
		if tex:
			tex_data.texture = tex

	biome_mgr.set_texture_count(loaded_textures.size())

	var mat := _build_editor_shader_material(loaded_textures)
	var generator := ChunkGenerator.new()
	generator.initialize(noise, biome_mgr)

	var r: int = editor_preview_radius
	var total: int = (2 * r + 1) * (2 * r + 1)

	for rx in range(-r, r + 1):
		for ry in range(-r, r + 1):
			var loc := Vector2i(rx, ry)
			var chunk_d := generator.generate_chunk_data(loc, GroundConstants.LOD_LEVELS.CLOSE)
			var chunk := GroundChunk.build_chunk(chunk_d, mat, false)
			chunk.mesh_instance.name = "EditorChunk_%d_%d" % [rx, ry]
			$"../Chunks".add_child(chunk.mesh_instance)
			chunk.mesh_instance.owner = get_tree().edited_scene_root

	print("[EditorGen] Done! %d chunks." % total)

func _build_editor_shader_material(loaded_textures: Array) -> ShaderMaterial:
	var shader: Shader = load(GroundConstants.TERRAIN_SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = shader

	# Build Texture2DArray from raw source PNGs
	var images: Array[Image] = []
	var common_size := Vector2i.ZERO
	for tex_data in loaded_textures:
		var img := Image.new()
		var path: String = tex_data.texture_path
		var err := img.load(ProjectSettings.globalize_path(path))
		if err != OK:
			var sz := common_size if common_size != Vector2i.ZERO else Vector2i(256, 256)
			img = Image.create_empty(sz.x, sz.y, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)
		if common_size == Vector2i.ZERO:
			common_size = Vector2i(img.get_width(), img.get_height())
		if Vector2i(img.get_width(), img.get_height()) != common_size:
			img.resize(common_size.x, common_size.y)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		images.append(img)

	if not images.is_empty():
		var tex_arr := Texture2DArray.new()
		if tex_arr.create_from_images(images) == OK:
			mat.set_shader_parameter("terrain_textures", tex_arr)
		else:
			push_warning("[EditorGen] Texture2DArray creation failed")

	mat.set_shader_parameter("texture_scale", GroundConstants.TEXTURE_SCALE)
	mat.set_shader_parameter("region_size", float(GroundConstants.CHUNK_SIZE))
	return mat

func _editor_clear() -> void:
	var to_remove: Array[Node] = []
	for child in $"../Chunks".get_children():
		if child.name.begins_with("EditorChunk_"):
			to_remove.push_back(child)
	for child in to_remove:
		child.queue_free()
	print("[EditorGen] Cleared %d preview chunks." % to_remove.size())
