extends Resource
class_name TextureData

@export var texture_name: String = ""
@export var texture_path: String = ""
@export var texture: Texture2D = null

static func from_dict(entry: Dictionary) -> TextureData:
	var t := TextureData.new()
	t.texture_name = str(entry.get("name", ""))
	t.texture_path = str(entry.get("path", ""))
	var tex = load(t.texture_path)
	if tex:
		t.texture = tex
	else:
		push_warning("TextureData: Could not load texture at %s" % t.texture_path)
	return t
