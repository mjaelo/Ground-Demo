extends Resource
class_name BiomeData

## Human-readable biome name.
var biome_name: String = ""
## Controls terrain steepness. Higher = more steep/mountainous peaks.
## Lower = gentler rolling hills. 0 = completely flat ground.
var steepness_level: float = 2.0
## Texture ID used on flat ground (slope below steep_slope_threshold).
var flat_texture_id: int = 1  # Grass
## Texture ID used on steep slopes (slope above steep_slope_threshold).
var steep_texture_id: int = 0  # Rock
## Texture ID shown on distant LOD chunks. -1 means use flat_texture_id.
var lod_texture_id: int = -1
## How rare this biome is. Higher = rarer (less likely to appear).
## 1.0 is the most common baseline; larger values make it increasingly rare.
var biome_rarity: float = 1.0
## List of string IDs/names of allowed DecorData for this biome
var allowed_decor_ids: Array = []
## Controls the spatial size of biome patches. Higher = bigger patches, lower = smaller.
## 1.0 is the default baseline size.
var biome_size: float = 1.0

## Conversion constants – these ensure the internal values fed to the
## blending / scoring / pow() math stay identical to the original system.
const _STEEPNESS_BASE: float = 10.0
const _RARITY_BASE: float = 5.0
const _SIZE_BASE_FREQ: float = 0.00015

## Returns the pow() exponent used for height generation (same as old height_curve).
func get_height_exponent() -> float:
	if steepness_level <= 0.0:
		return 100.0  # effectively flat
	return _STEEPNESS_BASE / steepness_level

## Returns the internal weight for biome competition scoring (same as old weight).
func get_biome_weight() -> float:
	if biome_rarity <= 0.0:
		return _RARITY_BASE
	return _RARITY_BASE / biome_rarity

## Returns the internal noise frequency for patch size (same as old biome_frequency).
func get_biome_frequency() -> float:
	if biome_size <= 0.0:
		return _SIZE_BASE_FREQ
	return _SIZE_BASE_FREQ / biome_size

## Returns the texture ID to use for LOD chunks.
func get_lod_texture_id() -> int:
	if lod_texture_id >= 0:
		return lod_texture_id
	return flat_texture_id

static func from_dict(entry: Dictionary) -> BiomeData:
	var b := BiomeData.new()
	b.biome_name = str(entry.get("name", ""))
	b.steepness_level = float(entry.get("steepness_level", 2.0))
	b.flat_texture_id = int(entry.get("flat_texture_id", 1))
	b.steep_texture_id = int(entry.get("steep_texture_id", 0))
	b.lod_texture_id = int(entry.get("lod_texture_id", -1))
	b.biome_rarity = float(entry.get("biome_rarity", 1.0))
	b.allowed_decor_ids = entry.get("allowed_decor_ids", [])
	b.biome_size = float(entry.get("biome_size", 1.0))
	return b
