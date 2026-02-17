extends Node

# Width/height of the terrain region in meters.
@export var region_size: int = 256
# Resolution of the generated heightmap image; higher = smoother but slower.
@export var heightmap_resolution: int = 256

# Lowest and highest terrain elevation (meters) used when importing the heightmap.
@export var height_min: float = 0.0
@export var height_max: float = 100.0
# Noise frequency that shapes the terrain slopes/hills.
@export var noise_frequency: float = 0.0009
# Resolution of generated texture assets; higher = sharper textures.
@export var texture_resolution: int = 1024
# Auto shader slope angle for texture blending (steeper gets brown). Raise to push brown onto steeper faces.
@export var auto_slope: float = 1.0
# Max slope (degrees) to still consider ground "green"; steeper is brown.
@export var ground_max_slope_deg: float = 28.0
# How sharp the blend is between materials; higher makes brown vs green separation clearer.
@export var blend_sharpness: float = 0.1
# How far to scatter grass/foliage; 0 uses the full terrain size.
@export var foliage_extent: int = 0
# Distance between placed foliage instances; lower = denser.
@export var foliage_step: int = 2
# Max slope (degrees) where grass/foliage is allowed; steeper spots stay bare/brown.
@export var foliage_max_slope_deg: float = 18.0
# Chance (0-1) to keep a foliage instance after slope check; lower = more sporadic.
@export var foliage_density: float = 0.25

var terrain: Terrain3D


func _ready() -> void:
	$UI.player = $Player
		
	if has_node("RunThisSceneLabel3D"):
		$RunThisSceneLabel3D.queue_free()

	terrain = await create_terrain()

	# Enable runtime navigation baking using the terrain
	# Enable `Debug/Visible Navigation` if you wish to see it
	$RuntimeNavigationBaker.terrain = terrain
	$RuntimeNavigationBaker.enabled = true


func create_terrain() -> Terrain3D:
	# Create textures
	var green_gr := Gradient.new()
	green_gr.set_color(0, Color.from_hsv(100./360., .35, .3))
	green_gr.set_color(1, Color.from_hsv(120./360., .4, .37))
	var green_ta: Terrain3DTextureAsset = await create_texture_asset("Grass", green_gr, texture_resolution)
	green_ta.uv_scale = 0.1
	green_ta.detiling_rotation = 0.1

	var brown_gr := Gradient.new()
	brown_gr.set_color(0, Color(.32,.34,.3))
	brown_gr.set_color(1, Color(.4,.4,.4))
	var brown_ta: Terrain3DTextureAsset = await create_texture_asset("Dirt", brown_gr, texture_resolution)
	brown_ta.uv_scale = 0.03
	green_ta.detiling_rotation = 0.1
	
	var grass_ma: Terrain3DMeshAsset = create_mesh_asset("Grass", Color.from_hsv(120./360., .4, .37)) 

	# Create a terrain
	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	add_child(terrain, true)

	# Set material and assets
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", auto_slope)
	terrain.material.set_shader_param("blend_sharpness", blend_sharpness)
	terrain.assets = Terrain3DAssets.new()
	# Texture 0 will now be the steep/slope (brown) and texture 1 the flatter base (green)
	terrain.assets.set_texture(0, brown_ta)
	terrain.assets.set_texture(1, green_ta)
	terrain.assets.set_mesh_asset(0, grass_ma)

	# Generate height map w/ 32-bit noise and import it with scale
	var noise := FastNoiseLite.new()
	noise.frequency = noise_frequency
	var img: Image = Image.create_empty(heightmap_resolution, heightmap_resolution, false, Image.FORMAT_RF)
	var world_size: float = region_size * 2.0
	for x in img.get_width():
		for y in img.get_height():
			var nx := (x / float(heightmap_resolution)) * world_size
			var ny := (y / float(heightmap_resolution)) * world_size
			img.set_pixel(x, y, Color(noise.get_noise_2d(nx, ny), 0., 0., 1.))
	terrain.region_size = region_size
	terrain.data.import_images([img, null, null], Vector3(-region_size, 0, -region_size), height_min, height_max)

	# Instance foliage (only on reasonably flat/green surfaces)
	var xforms: Array[Transform3D]
	var width: int = foliage_extent if foliage_extent > 0 else region_size * 2
	var step: int = max(1, foliage_step)
	var origin: Vector3 = Vector3(-region_size, 0, -region_size)
	for x in range(0, width, step):
		for z in range(0, width, step):
			var pos := Vector3(x, 0, z) + origin
			pos.y = terrain.data.get_height(pos)
			if is_nan(pos.y):
				continue
			var normal: Vector3 = terrain.data.get_normal(pos)
			var slope_deg := rad_to_deg(acos(clamp(normal.dot(Vector3.UP), -1.0, 1.0)))
			if slope_deg > foliage_max_slope_deg:
				continue
			if randf() > foliage_density:
				continue
			xforms.push_back(Transform3D(Basis(), pos))
	terrain.instancer.add_transforms(0, xforms)

	# Enable the next line and `Debug/Visible Collision Shapes` to see collision
	#terrain.collision.mode = Terrain3DCollision.DYNAMIC_EDITOR

	return terrain


func create_texture_asset(asset_name: String, gradient: Gradient, texture_size: int = 512) -> Terrain3DTextureAsset:
	# Create noise map
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.004
	
	# Create albedo noise texture
	var alb_noise_tex := NoiseTexture2D.new()
	alb_noise_tex.width = texture_size
	alb_noise_tex.height = texture_size
	alb_noise_tex.seamless = true
	alb_noise_tex.noise = fnl
	alb_noise_tex.color_ramp = gradient
	await alb_noise_tex.changed
	var alb_noise_img: Image = alb_noise_tex.get_image()

	# Create albedo + height texture
	for x in alb_noise_img.get_width():
		for y in alb_noise_img.get_height():
			var clr: Color = alb_noise_img.get_pixel(x, y)
			clr.a = clr.v # Noise as height
			alb_noise_img.set_pixel(x, y, clr)
	alb_noise_img.generate_mipmaps()
	var albedo := ImageTexture.create_from_image(alb_noise_img)

	# Create normal + rough texture
	var nrm_noise_tex := NoiseTexture2D.new()
	nrm_noise_tex.width = texture_size
	nrm_noise_tex.height = texture_size
	nrm_noise_tex.as_normal_map = true
	nrm_noise_tex.seamless = true
	nrm_noise_tex.noise = fnl
	await nrm_noise_tex.changed
	var nrm_noise_img = nrm_noise_tex.get_image()
	for x in nrm_noise_img.get_width():
		for y in nrm_noise_img.get_height():
			var normal_rgh: Color = nrm_noise_img.get_pixel(x, y)
			normal_rgh.a = 0.8 # Roughness
			nrm_noise_img.set_pixel(x, y, normal_rgh)
	nrm_noise_img.generate_mipmaps()
	var normal := ImageTexture.create_from_image(nrm_noise_img)

	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = albedo
	ta.normal_texture = normal
	return ta


func create_mesh_asset(asset_name: String, color: Color) -> Terrain3DMeshAsset:
	var ma := Terrain3DMeshAsset.new()
	ma.name = asset_name
	ma.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
	ma.material_override.albedo_color = color
	return ma