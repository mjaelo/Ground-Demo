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
var biome_rarity: float = 1.0
## List of string IDs/names of allowed DecorData for this biome
var allowed_decor_ids: Array = []
## Controls the spatial size of biome patches. Higher = bigger patches, lower = smaller.
var biome_size: float = 1.0

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
