extends Node

# Resolution of generated texture assets; higher = sharper textures.
@export var texture_resolution: int = 256

# TODO save to files
func get_terrain_assets() -> Terrain3DAssets:
	# Create assets and its textures
	var green_gr := Gradient.new()
	green_gr.set_color(0, Color.from_hsv(100./360., .35, .3))
	green_gr.set_color(1, Color.from_hsv(120./360., .4, .37))
	var green_ta: Terrain3DTextureAsset = create_texture_asset("Grass", green_gr, texture_resolution)
	green_ta.uv_scale = 0.1
	green_ta.detiling_rotation = 0.1

	var brown_gr := Gradient.new()
	brown_gr.set_color(0, Color(.32,.34,.3))
	brown_gr.set_color(1, Color(.4,.4,.4))
	var brown_ta: Terrain3DTextureAsset = create_texture_asset("Dirt", brown_gr, texture_resolution)
	brown_ta.uv_scale = 0.03
	green_ta.detiling_rotation = 0.1
	
	var grass_ma: Terrain3DMeshAsset = create_mesh_asset("Grass", Color.from_hsv(120./360., .4, .37))
	
	var assets:=Terrain3DAssets.new()
	# Texture 0 will now be the steep/slope (brown) and texture 1 the flatter base (green)
	assets.set_texture(0, brown_ta)
	assets.set_texture(1, green_ta)
	assets.set_mesh_asset(0, grass_ma)

	return assets

func create_texture_asset(asset_name: String, gradient: Gradient, texture_size: int = 512) -> Terrain3DTextureAsset:
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.004
	var img := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	for x in range(texture_size):
		for y in range(texture_size):
			var n := fnl.get_noise_2d(x, y)
			n = (n + 1.0) * 0.5
			var c := gradient.sample(n)
			c.a = c.v
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var albedo := ImageTexture.create_from_image(img)

	var nrm_img := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	for x in range(texture_size):
		for y in range(texture_size):
			var n := fnl.get_noise_2d(x + 123.0, y + 456.0)
			n = (n + 1.0) * 0.5
			var normal := Color(0.5, 0.5, 1.0, 0.8)
			var bump := (n - 0.5) * 0.1
			normal.r = clamp(0.5 + bump, 0.0, 1.0)
			normal.g = clamp(0.5 - bump, 0.0, 1.0)
			nrm_img.set_pixel(x, y, normal)
	nrm_img.generate_mipmaps()
	var normal_tex := ImageTexture.create_from_image(nrm_img)

	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = albedo
	ta.normal_texture = normal_tex
	return ta

func create_mesh_asset(asset_name: String, color: Color) -> Terrain3DMeshAsset:
	var ma := Terrain3DMeshAsset.new()
	ma.name = asset_name
	ma.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
	ma.material_override.albedo_color = color
	return ma
