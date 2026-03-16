extends Resource
class_name BiomeData

## Human-readable biome name.
var biome_name: String = ""
## Height curve exponent applied to the base noise.
## Higher values = flatter/lower terrain; lower values = taller peaks.
var height_curve: float = 2.0
## Texture ID used on flat ground (slope below steep_slope_threshold).
var flat_texture_id: int = 1  # Grass
## Texture ID used on steep slopes (slope above steep_slope_threshold).
var steep_texture_id: int = 0  # Rock
## Texture ID shown on distant LOD chunks. -1 means use flat_texture_id.
var lod_texture_id: int = -1
## Relative weight for biome selection. Higher = more common.
var weight: float = 1.0
## List of string IDs/names of allowed DecorData for this biome
var allowed_decor_ids: Array = []
# Controls patch size for this biome (lower = bigger patches)
var biome_frequency: float = 0.00015

## Returns the texture ID to use for LOD chunks.
func get_lod_texture_id() -> int:
	if lod_texture_id >= 0:
		return lod_texture_id
	return flat_texture_id

static func from_dict(entry: Dictionary) -> BiomeData:
	var b := BiomeData.new()
	b.biome_name = str(entry.get("name", ""))
	b.height_curve = float(entry.get("height_curve", 2.0))
	b.flat_texture_id = int(entry.get("flat_texture_id", 1))
	b.steep_texture_id = int(entry.get("steep_texture_id", 0))
	b.lod_texture_id = int(entry.get("lod_texture_id", -1))
	b.weight = float(entry.get("weight", 1.0))
	b.allowed_decor_ids = entry.get("allowed_decor_ids", [])
	b.biome_frequency = float(entry.get("biome_frequency",  0.00015))
	return b
