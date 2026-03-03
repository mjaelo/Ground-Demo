extends Node
class_name TerrainTextureManager

const TEXTURE_PATHS := [
	{"name": "Rock", "id": 0, "path": "res://assets/textures/rock_tex.png"},
	{"name": "Grass", "id": 1, "path": "res://assets/textures/grass_tex.png"},
	{"name": "Mud", "id": 2, "path": "res://assets/textures/mud_tex.png"} # Added mud texture
]

var loaded_textures: Dictionary = {}

func initialize(terrain: Terrain3D) -> void:
	loaded_textures.clear()
	for tex_info in TEXTURE_PATHS:
		_load_texture(tex_info)
		_register_terrain_texture(terrain, tex_info)

func _load_texture(tex_info:Dictionary) -> void:
	var tex: Texture2D = load(tex_info["path"])
	if tex:
		loaded_textures[tex_info["name"].to_lower()] = tex
	else:
		push_warning("TerrainTextureManager: Could not load texture at %s" % tex_info["path"])

func _register_terrain_texture(terrain: Terrain3D, tex_info: Dictionary) -> void:
	var assets = terrain.assets
	if assets == null:
		push_error("TerrainTextureManager: Terrain3D has no assets resource")
		return
	var key = tex_info["name"].to_lower()
	if loaded_textures.has(key):
		var ta = Terrain3DTextureAsset.new()
		ta.name = tex_info["name"]
		ta.id = tex_info["id"]
		ta.set_albedo_texture(loaded_textures[key])
		assets.set_texture(tex_info["id"], ta)
