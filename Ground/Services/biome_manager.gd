extends RefCounted
class_name BiomeManager

## Manages biome assignment using per-biome noise competition.
##
## Each biome has its own noise layer (same frequency, different seed).
## The noise value is scaled by the biome's weight. At every world point
## the biome with the highest score wins. Where two scores are close,
## they blend smoothly. This produces organic blob-shaped regions with
## no contour-line or grid artifacts.
##
## To add a new biome: add an entry to biome_definitions.json — that's it.

const BIOME_VALUES_PATH := "res://assets/biomes/biome_values.json"

# TODO add to Constants
const  STEEP_THRESHOLD: float = 30.0
# ── Biome registry ───────────────────────────────────────────────────
var biomes: Array[BiomeData] = []

# ── One noise source per biome (built automatically) ─────────────────
var _noises: Array[FastNoiseLite] = []

## Base seed; each biome offsets from this.
var noise_seed: int = 7891

## Score difference at which blending starts (world-noise units).
## Bigger = wider transition zones.
var blend_margin: float = 0.12

func _init() -> void:
	_load_biomes_from_json()
	_build_noises()

# ── JSON loading ──────────────────────────────────────────────────────
func _load_biomes_from_json() -> void:
	if not FileAccess.file_exists(BIOME_VALUES_PATH):
		push_warning("BiomeManager: biome file not found: %s — using defaults" % BIOME_VALUES_PATH)
		_register_default_biomes()
		return
	var file := FileAccess.open(BIOME_VALUES_PATH, FileAccess.READ)
	if file == null:
		push_warning("BiomeManager: failed to open: %s — using defaults" % BIOME_VALUES_PATH)
		_register_default_biomes()
		return
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("BiomeManager: JSON parse error in %s at line %d: %s" % [BIOME_VALUES_PATH, json.get_error_line(), json.get_error_message()])
		_register_default_biomes()
		return
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("BiomeManager: expected JSON object in %s" % BIOME_VALUES_PATH)
		_register_default_biomes()
		return

	var biome_array: Variant = data.get("biomes", [])
	if typeof(biome_array) != TYPE_ARRAY or biome_array.size() == 0:
		push_warning("BiomeManager: no biomes array in %s — using defaults" % BIOME_VALUES_PATH)
		_register_default_biomes()
		return

	biomes.clear()
	for entry in biome_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var b := BiomeData.from_dict(entry)
		biomes.push_back(b)

	if biomes.is_empty():
		push_warning("BiomeManager: parsed 0 valid biomes from %s — using defaults" % BIOME_VALUES_PATH)
		_register_default_biomes()

# ── Fallback default biome definitions ────────────────────────────────
func _register_default_biomes() -> void:
	var plains := BiomeData.new()
	plains.biome_name = "Plains"
	plains.height_curve = 4.0
	plains.weight = 5.0

	var swamp := BiomeData.new()
	swamp.biome_name = "Swamp"
	swamp.height_curve = 5.0
	swamp.flat_texture_id = 2
	swamp.steep_texture_id = 2
	swamp.weight = 3.0

	var mountain := BiomeData.new()
	mountain.biome_name = "Mountain"
	mountain.height_curve = 0.4
	mountain.weight = 2.0

	biomes = [plains, swamp, mountain]

## Call after modifying `biomes` at runtime.
func _build_noises() -> void:
	_noises.clear()
	for i in biomes.size():
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = biomes[i].biome_frequency # Use per-biome frequency for patch size
		n.seed = noise_seed + i * 5137   # different seed per biome
		_noises.append(n)

# ── Core API ──────────────────────────────────────────────────────────

## Returns the blended height-curve exponent for a world position.
func get_height_curve(world_x: float, world_z: float) -> float:
	var bw := _biome_weights(world_x, world_z)
	var curve := 0.0
	for i in bw.size():
		curve += biomes[i].height_curve * bw[i]
	return curve

## Returns the dominant BiomeData at a world position.
func get_biome_at(world_x: float, world_z: float) -> BiomeData:
	var bw := _biome_weights(world_x, world_z)
	var best_i := 0
	for i in range(1, bw.size()):
		if bw[i] > bw[best_i]:
			best_i = i
	return biomes[best_i]

## Returns a fully encoded control-map float for a world position + slope.
func get_encoded_control(world_x: float, world_z: float, slope_deg: float) -> float:
	var bw := _biome_weights(world_x, world_z)

	# Find the two strongest biome contributions
	var best_i := 0
	var second_i := -1
	for i in range(1, bw.size()):
		if bw[i] > bw[best_i]:
			second_i = best_i
			best_i = i
		elif second_i < 0 or bw[i] > bw[second_i]:
			second_i = i

	var primary: BiomeData = biomes[best_i]
	var base_tex: int = get_texture_id(slope_deg, primary.steep_texture_id, primary.flat_texture_id)

	# Blend with secondary biome if it has significant influence
	if second_i >= 0 and bw[second_i] > 0.01:
		var secondary: BiomeData = biomes[second_i]
		var over_tex: int = get_texture_id(slope_deg, secondary.steep_texture_id, secondary.flat_texture_id)
		if over_tex != base_tex:
			var total: float = bw[best_i] + bw[second_i]
			var blend_t: float = bw[second_i] / total  # 0..0.5
			# blend_t is how much of the secondary shows through.
			# To avoid the "outline" artifact where Terrain3D's bilinear
			# interpolation sees flipped base/overlay at neighboring pixels,
			# always put the lower tex ID as base and higher as overlay.
			# Invert the blend when the dominant biome has the higher ID.
			var lo: int = min(base_tex, over_tex)
			var hi: int = max(base_tex, over_tex)
			var lo_amount: float
			if base_tex == lo:
				# Primary is low ID → secondary (hi) shows through at blend_t
				lo_amount = 1.0 - blend_t
			else:
				# Primary is high ID → low ID shows through at blend_t
				lo_amount = blend_t
			# blend_byte = how much of the overlay (hi) to show.
			# 0 = all base (lo), 255 = all overlay (hi).
			var blend_byte: int = int(clamp((1.0 - lo_amount) * 255.0, 0.0, 255.0))
			return encode_control(lo, hi, blend_byte)

	return encode_control(base_tex)

# ── Internal: per-biome noise competition ────────────────────────────

## Returns per-biome weights that sum to 1.0 (at most two non-zero).
func _biome_weights(world_x: float, world_z: float) -> Array[float]:
	var count: int = biomes.size()

	# Score each biome: noise * weight
	var scores: Array[float] = []
	scores.resize(count)
	for i in count:
		# noise is -1..1, shift to 0..1 then scale by weight
		var raw: float = (_noises[i].get_noise_2d(world_x, world_z) + 1.0) * 0.5
		scores[i] = raw * biomes[i].weight

	# Find best and second-best
	var best_i := 0
	var second_i := -1
	for i in range(1, count):
		if scores[i] > scores[best_i]:
			second_i = best_i
			best_i = i
		elif second_i < 0 or scores[i] > scores[second_i]:
			second_i = i

	var weights: Array[float] = []
	weights.resize(count)
	for i in count:
		weights[i] = 0.0

	if second_i < 0:
		weights[best_i] = 1.0
		return weights

	# How close are the top two scores? Blend within margin.
	var diff: float = scores[best_i] - scores[second_i]
	if diff >= blend_margin:
		# Clear winner
		weights[best_i] = 1.0
	else:
		# Smooth blend: 0 at edge (diff=0) → 1 fully inside (diff=margin)
		var t: float = diff / blend_margin  # 0..1
		t = t * t * (3.0 - 2.0 * t)         # smoothstep
		weights[best_i] = 0.5 + 0.5 * t     # 0.5..1.0
		weights[second_i] = 1.0 - weights[best_i]  # 0.5..0.0

	return weights

# ── Control-map encoding ─────────────────────────────────────────────

## Terrain3D control map bit layout (from the shader):
##   Bit  0       : autoshader flag (0 = manual texture)
##   Bit  2       : hole
##   Bits 14-21   : blend value (0-255)
##   Bits 22-26   : overlay texture ID
##   Bits 27-31   : base texture ID
static func encode_control(base_id: int, overlay_id: int = -1, blend_byte: int = 0) -> float:
	var bits: int = 0
	bits |= (base_id & 0x1F) << 27
	if overlay_id >= 0:
		bits |= (overlay_id & 0x1F) << 22
	else:
		bits |= (base_id & 0x1F) << 22
	bits |= (blend_byte & 0xFF) << 14
	# Bit 0 = 0 → autoshader OFF (manual texturing)
	var buf := PackedByteArray()
	buf.resize(4)
	buf.encode_u32(0, bits)
	return buf.decode_float(0)


## Returns the texture ID for a given slope angle in degrees.
func get_texture_id(slope_deg: float, steep_texture_id, flat_texture_id) -> int:
	if slope_deg > STEEP_THRESHOLD:
		return steep_texture_id
	return flat_texture_id
