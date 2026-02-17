extends Node3D

var chunk_x: int
var chunk_z: int
var chunk_size: int
var height_min: float
var height_max: float
var heightmap_resolution: int
var noise_frequency: float
var texture_resolution: int
var auto_slope: float
var blend_sharpness: float
var foliage_step: int
var foliage_max_slope_deg: float
var foliage_density: float

var terrain: Terrain3D

func setup(cx, cz, size, hmin, hmax, hres, nfreq, tres, slope, sharp, fstep, fmaxslope, fdensity):
	chunk_x = cx
	chunk_z = cz
	chunk_size = size
	height_min = hmin
	height_max = hmax
	heightmap_resolution = hres
	noise_frequency = nfreq
	texture_resolution = tres
	auto_slope = slope
	blend_sharpness = sharp
	foliage_step = fstep
	foliage_max_slope_deg = fmaxslope
	foliage_density = fdensity
	_generate_terrain()

func _generate_terrain():
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	add_child(terrain)
	terrain.transform.origin = Vector3(chunk_x * chunk_size, 0, chunk_z * chunk_size)
	terrain.region_size = chunk_size / 2
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", auto_slope)
	terrain.material.set_shader_param("blend_sharpness", blend_sharpness)
	# Use simple green and brown for demo
	var green_gr := Gradient.new()
	green_gr.set_color(0, Color.from_hsv(100./360., .35, .3))
	green_gr.set_color(1, Color.from_hsv(120./360., .4, .37))
	var green_ta: Terrain3DTextureAsset = Terrain3DTextureAsset.new()
	green_ta.name = "Grass"
	green_ta.albedo_texture = ImageTexture.create_from_image(Image.create(chunk_size, chunk_size, false, Image.FORMAT_RGB8))
	var brown_gr := Gradient.new()
	brown_gr.set_color(0, Color(.32,.34,.3))
	brown_gr.set_color(1, Color(.4,.4,.4))
	var brown_ta: Terrain3DTextureAsset = Terrain3DTextureAsset.new()
	brown_ta.name = "Dirt"
	brown_ta.albedo_texture = ImageTexture.create_from_image(Image.create(chunk_size, chunk_size, false, Image.FORMAT_RGB8))
	terrain.assets = Terrain3DAssets.new()
	terrain.assets.set_texture(0, brown_ta)
	terrain.assets.set_texture(1, green_ta)
	# Heightmap
	var noise := FastNoiseLite.new()
	noise.frequency = noise_frequency
	var img: Image = Image.create_empty(heightmap_resolution, heightmap_resolution, false, Image.FORMAT_RF)
	for x in img.get_width():
		for y in img.get_height():
			var wx := chunk_x * chunk_size + (x / float(heightmap_resolution)) * chunk_size
			var wz := chunk_z * chunk_size + (y / float(heightmap_resolution)) * chunk_size
			img.set_pixel(x, y, Color(noise.get_noise_2d(wx, wz), 0., 0., 1.))
	terrain.data.import_images([img, null, null], Vector3(-chunk_size/2, 0, -chunk_size/2), height_min, height_max)
	# Foliage (optional, can be added similarly)
