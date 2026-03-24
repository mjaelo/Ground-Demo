extends RefCounted
class_name BiomeManager

var biomes: Array[BiomeData] = []
var _noises: Array[FastNoiseLite] = []

# TODO move Constants to GroundConstants
# Base seed; each biome offsets from this.
var noise_seed: int = 7891
# Controls how sharply biomes separate for texture blending. Higher = sharper.
var blend_sharpness: float = 50.0
var height_blend_sharpness: float = 10.0

const SIZE_BASE_FREQ: float = 0.00015
const SIZE_EXPONENT: float = 0.5

# ─ Initialization ─────────────────────────────────────────────────────
func _init() -> void:
	_load_biomes_from_json()
	_build_noises()

func _load_biomes_from_json() -> void:
	biomes.append_array(GameUtils.load_from_json(GroundConstants.BIOME_VALUES_PATH, BiomeData, "biomes"))
	if biomes.is_empty():
		push_warning("BiomeManager: parsed 0 valid biomes from %s" % GroundConstants.BIOME_VALUES_PATH)

func _build_noises() -> void:
	_noises.clear()
	for i in range(biomes.size()):
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		var freq := get_biome_frequency((biomes[i] as BiomeData).biome_size)
		n.frequency = freq
		# Different seed per biome
		n.seed = noise_seed + i * 5137
		_noises.append(n)

# ── Core API ──────────────────────────────────────────────────────────
# Compute terrain height (0..1 fraction) at a world position.
func sample_height(noise: FastNoiseLite, world_x: float, world_z: float) -> float:
	var bw := _height_biome_weights(world_x, world_z)
	var raw01: float = (noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var amplitude: float = 0.0
	for i in range(bw.size()):
		var w := bw[i]
		if w < 0.001:
			continue
		var height_aplitute := clampf((biomes[i] as BiomeData).steepness_level  * 0.01, 0.0, 1.0)
		amplitude += height_aplitute * w
	return clampf(raw01 * amplitude, 0.0, 1.0)

# Returns the dominant BiomeData at a world position.
func get_biome_at(world_x: float, world_z: float) -> BiomeData:
	var bw := _biome_weights(world_x, world_z)
	var best_i := 0
	for i in range(1, bw.size()):
		if bw[i] > bw[best_i]:
			best_i = i
	return biomes[best_i]

# --- Internal helpers -------------------------------------------------

# Compute raw per-biome scores (before sharpening/normalisation).
func _compute_biome_scores(world_x: float, world_z: float) -> Array[float]:
	var count: int = biomes.size()
	var scores: Array[float] = []
	scores.resize(count)
	for i in range(count):
		var raw: float = (_noises[i].get_noise_2d(world_x, world_z) + 1.0) * 0.5
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
	return _weights_with_sharpness(_compute_biome_scores(world_x, world_z), blend_sharpness)

# Like _biome_weights but uses height_blend_sharpness.
func _height_biome_weights(world_x: float, world_z: float) -> Array[float]:
	return _weights_with_sharpness(_compute_biome_scores(world_x, world_z), height_blend_sharpness)

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

func get_biome_frequency(biome_size) -> float:
	if biome_size <= 0.0:
		return SIZE_BASE_FREQ
	var s: float = pow(float(biome_size), SIZE_EXPONENT)
	return SIZE_BASE_FREQ / maxf(s, 0.0001)
