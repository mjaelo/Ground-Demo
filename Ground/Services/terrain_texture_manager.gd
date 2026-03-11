extends RefCounted
class_name TerrainTextureManager

const DEFAULT_TEXTURES_FILE := "res://assets/textures/texture_values.json"

var loaded_textures: Dictionary = {}

## Load textures from JSON. No Terrain3D dependency.
func load_textures(textures_file: String = DEFAULT_TEXTURES_FILE) -> void:
	loaded_textures.clear()
	var texture_defs := _load_texture_defs(textures_file)
	for tex_info in texture_defs:
		_load_texture(tex_info)

static func _load_texture_defs(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("TerrainTextureManager: textures file not found: %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TerrainTextureManager: failed to open: %s" % path)
		return []
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("TerrainTextureManager: JSON parse error in %s at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return []
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("TerrainTextureManager: expected JSON object in %s" % path)
		return []
	var textures: Variant = data.get("textures", [])
	if typeof(textures) != TYPE_ARRAY:
		push_error("TerrainTextureManager: expected 'textures' array in %s" % path)
		return []
	return textures

func _load_texture(tex_info: Dictionary) -> void:
	var tex_name: String = str(tex_info.get("name", ""))
	var tex_path: String = str(tex_info.get("path", ""))
	if tex_name.is_empty() or tex_path.is_empty():
		push_warning("TerrainTextureManager: texture entry missing name or path")
		return
	var tex: Texture2D = load(tex_path)
	if tex:
		loaded_textures[tex_name.to_lower()] = tex
	else:
		push_warning("TerrainTextureManager: Could not load texture at %s" % tex_path)
