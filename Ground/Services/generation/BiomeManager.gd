extends RefCounted
class_name BiomeManager

var biomes: Array[BiomeData] = []
var size_noises: Array[FastNoiseLite] = []
var height_noises: Array[FastNoiseLite] = []

# INITIALIZATION 
func _init() -> void:
	_load_biomes_from_json()
	_build_noises()

func _load_biomes_from_json() -> void:
	biomes.append_array(GameUtils.load_from_json(GroundConstants.BIOME_VALUES_PATH, BiomeData, "biomes"))
	if biomes.is_empty():
		push_warning("BiomeManager: parsed 0 valid biomes from %s" % GroundConstants.BIOME_VALUES_PATH)

func _build_noises() -> void:
	size_noises.clear()
	height_noises.clear()
	for i in range(biomes.size()):
		var sn := FastNoiseLite.new()
		sn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		sn.frequency = GroundConstants.SIZE_BASE_FREQ / maxf(biomes[i].biome_size, 0.0001)
		sn.seed = GroundConstants.NOISE_SEED + i * 5137
		size_noises.append(sn)

		var hn := FastNoiseLite.new()
		hn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		hn.frequency = GroundConstants.HEIGHT_BASE_FREQ / maxf(biomes[i].steepness_level, 0.0001)
		hn.seed = GroundConstants.NOISE_SEED + i * 5137 + 99991
		height_noises.append(hn)

#  Core API 
# Compute terrain height at a world position.
func get_height_at(world_x: float, world_z: float, precomputed_scores: Array[float] = []) -> float:
	var biome_scores: Array[float] = precomputed_scores if precomputed_scores.size() == biomes.size() else _compute_biome_scores(world_x, world_z)
	var biome_count := biome_scores.size()
	var minimal_offset: float = -INF
	for i in range(biome_count):
		if biomes[i].offset > minimal_offset && biome_scores[i] >= GroundConstants.BIOME_HEIGHT_THRESHOLD:
			minimal_offset = biomes[i].offset
	
	#  Step 1: terrain height ignoring biomes with offset < minimal_offset
	var height_biome_weights_full: Array[float] = _weights_with_sharpness(biome_scores, GroundConstants.HEIGHT_BLEND_SHARPNESS)
	var high_biome_weights: Array[float] = []
	high_biome_weights.resize(biome_count)
	for i in range(biome_count):
		high_biome_weights[i] = height_biome_weights_full[i]
		if biomes[i].offset < minimal_offset:
			high_biome_weights[i] = 0.0

	# with elevated-only normalized height weights, compute high_biomes_y
	var high_biomes_y: float = 0.0
	for i in range(biome_count):
		var high_biome_weight := high_biome_weights[i]
		if high_biome_weight < GroundConstants.BIOME_HEIGHT_THRESHOLD:
			continue
		var high_biome_y := get_biome_y(world_x, world_z, i)
		high_biomes_y += high_biome_weight * high_biome_y

	#  Step 2: downward pull 
	# Determine dominant high biome weight using the elevated-only weights
	var dominant_high_biome_weight: float = 0.0
	for i in range(biome_count):
		if biomes[i].offset >= minimal_offset and high_biome_weights[i] > dominant_high_biome_weight:
			dominant_high_biome_weight = high_biome_weights[i]

	# only pull downward if a low-offset biome dominates locally
	var final_height: float = high_biomes_y
	for i in range(biome_count):
		if biomes[i].offset >= minimal_offset:
			continue
		# use the full height weights (not the elevated-only copy) so low biomes can exert pull
		var low_biome_height_weight: float = height_biome_weights_full[i]
		if low_biome_height_weight <= dominant_high_biome_weight:
			continue  # ignore non dominant low biomes
		# calculate pull_power (0,1) without dividing by 0
		var downwards_pull_power: float = (low_biome_height_weight - dominant_high_biome_weight) / maxf((1.0 - dominant_high_biome_weight), 0.001)
		downwards_pull_power = clampf(downwards_pull_power, 0.0, 1.0)
		downwards_pull_power = downwards_pull_power * downwards_pull_power * (3.0 - 2.0 * downwards_pull_power)  # smoothstep
		# Depression's own height.
		var low_biome_y: float = get_biome_y(world_x, world_z, i)
		# lower final height by pull power (0,1) toward low_biome_y
		final_height = lerpf(final_height, low_biome_y, downwards_pull_power)

	return final_height

func get_biome_y(world_x, world_z, i) -> float:
	var biome_d := biomes[i]
	var positive_noise_value: float = (height_noises[i].get_noise_2d(world_x, world_z) + 1.0) * 0.5
	return biome_d.offset + positive_noise_value * biome_d.max_hill_y

# Returns the dominant BiomeData at a world position.
func get_dominant_biome_at(world_x: float, world_z: float) -> BiomeData:
	var bw := _biome_weights(world_x, world_z)
	var best_i := 0
	for i in range(1, bw.size()):
		if bw[i] > bw[best_i]:
			best_i = i
	return biomes[best_i]

# Internal helpers-

# Compute raw per-biome scores (before sharpening/normalisation).
func _compute_biome_scores(world_x: float, world_z: float) -> Array[float]:
	var count: int = biomes.size()
	var scores: Array[float] = []
	scores.resize(count)
	for i in range(count):
		var raw: float = (size_noises[i].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		scores[i] = get_biome_score_with_size(raw, (biomes[i] as BiomeData).biome_rarity, (biomes[i] as BiomeData).biome_size)
	return scores

# Returns per-biome weights that sum to 1.0.
# Uses power-normalised scoring; higher blend_sharpness -> steeper transitions.
func _weights_with_sharpness(scores: Array[float], sharpness: float) -> Array[float]:
	# Normalise scores into weights using a power curve controlled by sharpness.
	var count := scores.size()
	var weights: Array[float] = []
	weights.resize(count)
	var total: float = 0.0
	for i in range(count):
		var w: float = pow(maxf(scores[i], 0.0001), sharpness)
		weights[i] = w
		total += w
	if total <= 0.0:
		for i in range(count):
			weights[i] = 1.0 / float(count)
	else:
		var inv: float = 1.0 / total
		for i in range(count):
			weights[i] *= inv
	return weights

func _biome_weights(world_x: float, world_z: float) -> Array[float]:
	return _weights_with_sharpness(_compute_biome_scores(world_x, world_z), GroundConstants.TEXTURE_BLEND_SHARPNESS)

func get_biome_score_with_size(raw01: float, biome_rarity: float, biome_size: float) -> float:
	var r: float = maxf(biome_rarity, 0.0001)
	var exponent: float = clampf(r, 0.25, 8.0)
	var rarity_score: float = pow(clampf(raw01, 0.0, 1.0), exponent)
	var size_bias: float = 1.0
	if biome_size > 1.0:
		size_bias = minf(1.0 + log(biome_size) * 0.2, 3.0)
	elif biome_size < 1.0:
		size_bias = maxf(1.0 - log(1.0 / biome_size) * 0.2, 0.3)
	return rarity_score * size_bias
