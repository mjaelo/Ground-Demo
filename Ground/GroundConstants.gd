extends Resource
class_name GroundConstants

enum LOD_LEVELS {CLOSE, MEDIUM, FAR}

# ── GENERAL GROUND ────────────────────────────────────────────────────
const height_min: float = 0.0
const height_max: float = 800.0
const CHUNK_SIZE: int = 256
const TEXTURES_FILE_PATH := "res://assets/textures/texture_values.json"

# ── BIOMES ────────────────────────────────────────────────────────────
const BIOME_VALUES_PATH := "res://assets/biomes/biome_values.json"
const STEEP_THRESHOLD: float = 30.0
## Degrees on each side of STEEP_THRESHOLD over which flat/steep textures blend.
const STEEP_BLEND_RANGE: float = 10.0

# ── MESH ASSETS ───────────────────────────────────────────────────────
const MESH_ASSETS_PATH: String = "res://assets/mesh_assets/"
const DECOR_VALUES_FILE: String = MESH_ASSETS_PATH + "decor_values.json"
const DECOR_STEP: int = 2 # Distance between placed mesh instances; lower = denser.
const DECOR_EMPTY_CHANCE: float = 0.3

# ── CHUNK RADII & RESOLUTION ─────────────────────────────────────────
const close_radius: int = 4
const medium_radius: int = 10
const far_radius: int = 22
const close_resolution: int = 48
const medium_resolution: int = 16
const far_resolution: int = 6
const UNLOAD_MARGIN: int = 3
const STREAM_CHECK_INTERVAL: float = 0.08
const MAX_DECOR_THREADS: int = 4

const STARTUP_CHUNKS_PER_FRAME: int = 16
const STARTUP_THREADS: int = 16
const STARTUP_FAR_PER_FRAME: int = 200
const STARTUP_FAR_THREADS: int = 12

const STEADY_CHUNKS_PER_FRAME: int = 4
const STEADY_THREADS: int = 6
const STEADY_FAR_PER_FRAME: int = 30
const STEADY_FAR_THREADS: int = 4

# ── TERRAIN SHADER ────────────────────────────────────────────────────
const TERRAIN_SHADER_PATH := "res://Ground/Services/terrain_blend.gdshader"
const TEXTURE_SCALE: float = 16.0

# ── NOISE ─────────────────────────────────────────────────────────────
const NOISE_FREQUENCY: float = 0.0009
