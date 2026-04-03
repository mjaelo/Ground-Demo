extends Resource
class_name BiomeData

var biome_name: String = "" # Human-readable biome name
var steepness_level: float = 2.0 # Controls terrain steepness. >0 -> hills above y=0, 0 -> flat, <0 -> inverted hills (holes) below y=0
var offset: float = 0.0
var flat_texture_id: int = 1    # Texture ID for flat ground (default Grass)
var steep_texture_id: int = 0   # Texture ID for steep slopes (default Rock)
var lod_texture_id: int = -1    # LOD texture (-1 => use flat_texture_id)
var biome_rarity: float = 1.0
var allowed_decor_ids: Array = [] # List of string IDs/names of allowed DecorData for this biome
var biome_size: float = 1.0
var has_water: bool = false # Whether this biome contains water at y=0

static func from_dict(entry: Dictionary) -> BiomeData:
	var b := BiomeData.new()
	b.biome_name = str(entry.get("name", ""))
	b.steepness_level = float(entry.get("steepness_level", 2.0))
	b.offset = float(entry.get("offset", 0.0))
	b.flat_texture_id = int(entry.get("flat_texture_id", 1))
	b.steep_texture_id = int(entry.get("steep_texture_id", 0))
	b.lod_texture_id = int(entry.get("lod_texture_id", -1))
	b.biome_rarity = float(entry.get("biome_rarity", 1.0))
	b.allowed_decor_ids = entry.get("allowed_decor_ids", [])
	b.biome_size = float(entry.get("biome_size", 1.0))
	b.has_water = bool(entry.get("has_water", false))
	return b
