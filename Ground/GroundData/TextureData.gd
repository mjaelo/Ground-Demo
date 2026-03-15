extends Resource
class_name TextureData

## Human-readable texture name.
@export var texture_name: String = ""
## Path to the texture resource.
@export var texture_path: String = ""
## The loaded Texture2D resource (optional, can be null if not loaded).
@export var texture: Texture2D = null

static func from_dict(entry: Dictionary) -> TextureData:
	var t := TextureData.new()
	t.texture_name = str(entry.get("name", ""))
	t.texture_path = str(entry.get("path", ""))
	return t
