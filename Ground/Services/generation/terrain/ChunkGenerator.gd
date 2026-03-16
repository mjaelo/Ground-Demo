extends RefCounted
class_name ChunkGenerator

## Generates heightmap and splatmap data for terrain chunks on worker threads.

var _noise: FastNoiseLite = null
var _biome_manager: BiomeManager = null

func initialize(noise: FastNoiseLite, biome_manager: BiomeManager) -> void:
	_noise = noise
	_biome_manager = biome_manager

func generate_chunk_data(loc: Vector2i, tier: int) -> Dictionary:
	var res: int
	match tier:
		GroundConstants.LOD_LEVELS.CLOSE:
			res = GroundConstants.close_resolution
		GroundConstants.LOD_LEVELS.MEDIUM:
			res = GroundConstants.medium_resolution
		_:
			res = GroundConstants.far_resolution
	var result := _generate_heightmap_and_splatmap(loc, res, tier)
	return {"loc": loc, "tier": tier, "heightmap": result["heightmap"], "splatmap": result["splatmap"]}

func _generate_heightmap_and_splatmap(loc: Vector2i, res: int, tier: int) -> Dictionary:
	var chunk_size := GroundConstants.CHUNK_SIZE
	var bx: float = loc.x * chunk_size
	var bz: float = loc.y * chunk_size
	var inv := 1.0 / float(res - 1)
	var scale: float = GroundConstants.height_max - GroundConstants.height_min

	var hm := Image.create_empty(res, res, false, Image.FORMAT_RF)
	var sm := Image.create_empty(res, res, false, Image.FORMAT_RGBA8)

	var cached_weights: Array = []
	cached_weights.resize(res * res)
	for x in res:
		var nx: float = float(x) * inv * chunk_size + bx
		for y in res:
			var ny: float = float(y) * inv * chunk_size + bz
			var bw := _biome_manager._biome_weights(nx, ny)
			cached_weights[x * res + y] = bw
			var curve := 0.0
			for i in bw.size():
				curve += _biome_manager.biomes[i].height_curve * bw[i]
			var h: float = _noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			h = pow(h, curve)
			hm.set_pixel(x, y, Color(GroundConstants.height_min + h * scale, 0, 0, 1))

	if tier == GroundConstants.LOD_LEVELS.FAR:
		for x in res:
			for y in res:
				var bw: Array[float] = cached_weights[x * res + y]
				var r := 0.0; var g := 0.0; var b := 0.0
				for i in bw.size():
					if bw[i] < 0.01: continue
					var bt: int = _biome_manager.biomes[i].get_lod_texture_id()
					if bt == 0: r += bw[i]
					elif bt == 1: g += bw[i]
					elif bt == 2: b += bw[i]
				sm.set_pixel(x, y, Color(r, g, b, 1.0))
	else:
		var cs: float = float(chunk_size) / float(res - 1)
		for x in res:
			for y in res:
				var hc: float = hm.get_pixel(x, y).r
				var hr: float = hc if x + 1 >= res else hm.get_pixel(x + 1, y).r
				var hd: float = hc if y + 1 >= res else hm.get_pixel(x, y + 1).r
				var slope: float = rad_to_deg(acos(clampf(Vector3(-(hr - hc) / cs, 1.0, -(hd - hc) / cs).normalized().dot(Vector3.UP), -1.0, 1.0)))
				var bw: Array[float] = cached_weights[x * res + y]
				var r := 0.0; var g := 0.0; var b := 0.0
				for i in bw.size():
					if bw[i] < 0.01: continue
					var bd: BiomeData = _biome_manager.biomes[i]
					var bt: int = bd.steep_texture_id if slope > GroundConstants.STEEP_THRESHOLD else bd.flat_texture_id
					if bt == 0: r += bw[i]
					elif bt == 1: g += bw[i]
					elif bt == 2: b += bw[i]
				sm.set_pixel(x, y, Color(r, g, b, 1.0))

	return {"heightmap": hm, "splatmap": sm}
