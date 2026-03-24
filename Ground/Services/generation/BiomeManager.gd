extends RefCounted
class_name BiomeManager

var biomes := [] # ── Biome registry ───────────────────────────────────────────────────
var _noises: Array[FastNoiseLite] = [] # ── One noise source per biome (built automatically) ─────────────────

# TODO move Constants to GroundConstants
## Base seed; each biome offsets from this.
var noise_seed: int = 7891
## Controls how sharply biomes separate from each other for texture blending. Higher = sharper transitions. Lower = softer transitions.
var blend_sharpness: float = 50.0
var height_blend_sharpness: float = 10.0
## Conversion constants – these ensure the internal values fed to the
const _STEEPNESS_BASE: float = 10.0
const _RARITY_BASE: float = 5.0
const _SIZE_BASE_FREQ: float = 0.00015
const _SIZE_EXPONENT: float = 0.5
const _MAX_HEIGHT_AMPLITUDE: float = 1.0

#─ Initialization ─────────────────────────────────────────────────────
func _init() -> void:
	_load_biomes_from_json()
	_build_noises()

func _load_biomes_from_json() -> void:
	biomes = GameUtils.load_from_json(GroundConstants.BIOME_VALUES_PATH, BiomeData, "biomes") as Array[BiomeData]
	if biomes.is_empty():
		push_warning("BiomeManager: parsed 0 valid biomes from %s" % GroundConstants.BIOME_VALUES_PATH)

func _build_noises() -> void:
	_noises.clear()
	for i in biomes.size():
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		var freq := get_biome_frequency((biomes[i] as BiomeData).biome_size)
		n.frequency = freq
		print("[BiomeManager] %s biome_size=%.2f -> frequency=%.6f" % [(biomes[i] as BiomeData).biome_name, (biomes[i] as BiomeData).biome_size, freq])
		n.seed = noise_seed + i * 5137   # different seed per biome
		_noises.append(n)

# ── Core API ──────────────────────────────────────────────────────────

## Computes the terrain height (0..1 fraction of height range) at a world position.
## Evaluates pow(noise, exponent) per biome individually, then linearly blends
## the resulting heights. Uses proportional scoring (all biomes contribute based
## on their score) to avoid sharp lines where second-place biomes change.
func sample_height(noise: FastNoiseLite, world_x: float, world_z: float) -> float:
	var bw := _height_biome_weights(world_x, world_z)
	var raw01: float = (noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var amplitude: float = 0.0
	for i in bw.size():
		var w := bw[i]
		if w < 0.001:
			continue
		amplitude += get_height_amplitude((biomes[i] as BiomeData).steepness_level) * w
	return clampf(raw01 * amplitude, 0.0, 1.0)

func get_height_amplitude(steepness_level: float) -> float:
	if steepness_level <= 0.0:
		return 0.0
	var t: float = clampf(steepness_level / 100.0, 0.0, 1.0)
	return lerpf(0.0, _MAX_HEIGHT_AMPLITUDE, t)

## Returns the dominant BiomeData at a world position.
func get_biome_at(world_x: float, world_z: float) -> BiomeData:
	var bw := _biome_weights(world_x, world_z)
	var best_i := 0
	for i in range(1, bw.size()):
		if bw[i] > bw[best_i]:
			best_i = i
	return biomes[best_i]

# ── Internal: per-biome noise competition ────────────────────────────

## Returns per-biome weights that sum to 1.0.
## Uses power-normalized scoring: each biome's score is raised to
## blend_sharpness, then all are normalised. This naturally produces
## ~100% weight deep inside a biome and gradual transitions at boundaries.
func _biome_weights(world_x: float, world_z: float) -> Array[float]:
	var count: int = biomes.size()

	# Score each biome: noise * weight
	var scores: Array[float] = []
	scores.resize(count)
	for i in count:
		var raw: float = (_noises[i].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		scores[i] = get_biome_score_with_size(raw, (biomes[i] as BiomeData).biome_rarity, (biomes[i] as BiomeData).biome_size)

	# Raise to sharpening power and normalise.
	# Higher blend_sharpness → steeper transitions, more distinct biomes.
	# Lower → wider, softer blending zones.
	var weights: Array[float] = []
	weights.resize(count)
	var total: float = 0.0
	for i in count:
		# Clamp to small positive to avoid pow(0, n) = 0 discontinuities
		var w: float = pow(maxf(scores[i], 0.0001), blend_sharpness)
		weights[i] = w
		total += w

	if total <= 0.0:
		for i in count:
			weights[i] = 1.0 / float(count)
	else:
		var inv: float = 1.0 / total
		for i in count:
			weights[i] *= inv

	return weights

func _height_biome_weights(world_x: float, world_z: float) -> Array[float]:
	var count: int = biomes.size()
	var scores: Array[float] = []
	scores.resize(count)
	for i in count:
		var raw: float = (_noises[i].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		scores[i] = get_biome_score_with_size(raw, (biomes[i] as BiomeData).biome_rarity, (biomes[i] as BiomeData).biome_size)

	var weights: Array[float] = []
	weights.resize(count)
	var total: float = 0.0
	for i in count:
		var w: float = pow(maxf(scores[i], 0.0001), height_blend_sharpness)
		weights[i] = w
		total += w

	if total <= 0.0:
		for i in count:
			weights[i] = 1.0 / float(count)
	else:
		var inv: float = 1.0 / total
		for i in count:
			weights[i] *= inv

	return weights

## Returns per-biome weights proportional to each biome's score.
## Every biome contributes: weight_i = score_i / sum(scores).
## Weights change continuously everywhere — no top-2 selection means
## no sharp lines where the second-place biome changes.
func _all_biome_weights(world_x: float, world_z: float) -> Array[float]:
	var count: int = biomes.size()
	var scores: Array[float] = []
	scores.resize(count)
	var total: float = 0.0
	for i in count:
		var raw: float = (_noises[i].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		var s: float = get_biome_score_with_size(raw, (biomes[i] as BiomeData).biome_rarity, (biomes[i] as BiomeData).biome_size)
		scores[i] = s
		total += s

	var weights: Array[float] = []
	weights.resize(count)
	if total <= 0.0:
		for i in count:
			weights[i] = 1.0 / float(count)
	else:
		for i in count:
			weights[i] = scores[i] / total
	return weights

## Returns the pow() exponent used for height generation (same as old height_curve).
func get_height_exponent(steepness_level) -> float:
	if steepness_level <= 0.0:
		return 100.0  # effectively flat
	return _STEEPNESS_BASE / steepness_level

## Returns the internal weight for biome competition scoring (same as old weight).
func get_biome_weight(biome_rarity) -> float:
	if biome_rarity <= 0.0:
		return _RARITY_BASE
	return _RARITY_BASE / biome_rarity

func get_biome_score(raw01: float, biome_rarity: float) -> float:
	var r: float = maxf(biome_rarity, 0.0001)
	# Higher biome_rarity => rarer biome. We implement this by biasing the
	# raw noise toward 0 so that only its highest peaks can dominate.
	# r = 1.0 means "normal" distribution.
	# r > 1.0 makes the biome rarer.
	# r < 1.0 makes the biome more common.
	var exp: float = clampf(r, 0.25, 8.0)
	return pow(clampf(raw01, 0.0, 1.0), exp)

func get_biome_score_with_size(raw01: float, biome_rarity: float, biome_size: float) -> float:
	var r: float = maxf(biome_rarity, 0.0001)
	var exp: float = clampf(r, 0.25, 8.0)
	var rarity_score: float = pow(clampf(raw01, 0.0, 1.0), exp)
	# Size bias: larger biome_size (lower frequency) gets a boost so it wins
	# more often when its noise is high, making big biomes appear more often.
	var size_bias: float = 1.0
	if biome_size > 1.0:
		size_bias = minf(1.0 + log(biome_size) * 0.2, 3.0)
	elif biome_size < 1.0:
		size_bias = maxf(1.0 - log(1.0 / biome_size) * 0.2, 0.3)
	return rarity_score * size_bias

## Returns the internal noise frequency for patch size (same as old biome_frequency).
func get_biome_frequency(biome_size) -> float:
	if biome_size <= 0.0:
		return _SIZE_BASE_FREQ
	var s: float = pow(float(biome_size), _SIZE_EXPONENT)
	return _SIZE_BASE_FREQ / maxf(s, 0.0001)

func debug_print_scores_at(world_x: float, world_z: float) -> void:
	print("=== Biome scores at (%.1f, %.1f) ===" % [world_x, world_z])
	for i in biomes.size():
		var raw: float = (_noises[i].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		var rarity_score: float = get_biome_score(raw, (biomes[i] as BiomeData).biome_rarity)
		var final_score: float = get_biome_score_with_size(raw, (biomes[i] as BiomeData).biome_rarity, (biomes[i] as BiomeData).biome_size)
		print("%s: raw=%.4f, rarity=%.2f, rarity_score=%.6f, size=%.2f, final_score=%.6f" % [(biomes[i] as BiomeData).biome_name, raw, (biomes[i] as BiomeData).biome_rarity, rarity_score, (biomes[i] as BiomeData).biome_size, final_score])
