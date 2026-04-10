extends RefCounted
class_name TextureManager ## Handles shader material and texture array setup for terrain rendering.

var loaded_textures:Array[TextureData]
var shader_material: ShaderMaterial = null

func _init() -> void:
	loaded_textures.append_array(GameUtils.load_from_json(GroundConstants.TEXTURES_FILE_PATH, TextureData, "textures"))
	build_shader_material()

func build_shader_material() -> void:
	var shader: Shader = load(GroundConstants.TERRAIN_SHADER_PATH)
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader

	# Build a Texture2DArray from all loaded textures so the shader can index any texture dynamically without a fixed number of uniforms.
	var tex_array := build_texture_array()
	if tex_array:
		shader_material.set_shader_parameter("terrain_textures", tex_array)
	else:
		push_warning("GroundMaterialManager: Failed to build terrain texture array!")

	shader_material.set_shader_parameter("texture_scale", GroundConstants.TEXTURE_SCALE)
	shader_material.set_shader_parameter("region_size", float(GroundConstants.CHUNK_SIZE))
	shader_material.set_shader_parameter("texture_count", loaded_textures.size())

## Packs every loaded terrain texture into a single Texture2DArray.
func build_texture_array() -> Texture2DArray:
	if loaded_textures.is_empty():
		push_warning("GroundMaterialManager: No textures loaded, cannot build texture array.")
		return null

	# Load raw images from the original source files
	var images: Array[Image] = load_images()
	if images.is_empty():
		push_warning("GroundMaterialManager: No images loaded for texture array.")
		return null

	var tex_arr := Texture2DArray.new()
	var create_err := tex_arr.create_from_images(images)
	if create_err != OK:
		push_error("GroundMaterialManager: Texture2DArray creation failed with error %d" % create_err)
		return null
	return tex_arr

func load_images() -> Array[Image]:
	var images: Array[Image] = []
	var common_size := Vector2i.ZERO
	for tex_data in loaded_textures:
		var img := Image.new()
		# Convert res:// path to the project file system path for raw loading
		var path: String = tex_data.texture_path
		var load_err := img.load(ProjectSettings.globalize_path(path))
		if load_err != OK:
			push_warning("GroundMaterialManager: Could not load raw image '%s' (error %d), using placeholder." % [path, load_err])
			var sz := common_size if common_size != Vector2i.ZERO else Vector2i(256, 256)
			img = Image.create_empty(sz.x, sz.y, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)

		if common_size == Vector2i.ZERO:
			common_size = Vector2i(img.get_width(), img.get_height())

		# Ensure uniform size
		if Vector2i(img.get_width(), img.get_height()) != common_size:
			img.resize(common_size.x, common_size.y)
		# Ensure consistent uncompressed format
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		images.append(img)
	return images