extends Resource
class_name GroundConstants

enum LOD_LEVELS {CLOSE, MEDIUM, FAR}

# GENERAL GROUND CONSTANTS
const height_min: float = 0.0
const height_max: float = 800.0
const CHUNK_SIZE: int = 256
const TEXTURES_FILE_PATH := "res://assets/textures/texture_values.json"

# BIOMES
const BIOME_VALUES_PATH := "res://assets/biomes/biome_values.json"
const STEEP_THRESHOLD: float = 30.0

# MESH ASSETS
const MESH_ASSETS_PATH: String = "res://assets/mesh_assets/"
const DECOR_VALUES_FILE: String = MESH_ASSETS_PATH + "decor_values.json"

# WORLD SHIFTING
const shift_threshold: float = 4096.0 * 0.5

# CHUNK MANAGER
const close_radius: int = 4
const medium_radius: int = 10
const far_radius: int = 22
const close_resolution: int = 64
const medium_resolution: int = 24
const far_resolution: int = 8
