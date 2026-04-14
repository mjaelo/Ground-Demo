extends Resource
class_name TextureData

@export var texture_name: String = ""
@export var texture_path: String = ""
@export var image: Image = null

static func from_dict(entry: Dictionary) -> TextureData:
	var t := TextureData.new()
	t.texture_name = str(entry.get("name", ""))
	t.texture_path = str(entry.get("path", ""))
	t.image = Image.load_from_file(t.texture_path)
	if not t.image:
		push_warning("TextureData: Could not load image at %s" % t.texture_path)
	return t
