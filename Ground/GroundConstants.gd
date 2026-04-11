extends Resource
class_name GroundConstants

enum LOD_LEVELS {CLOSE, FAR}

# GENERAL
const HEIGHT_MIN: float = 0.0
const HEIGHT_MAX: float = 800.0
const CHUNK_SIZE: int = 256
const TEXTURES_FILE_PATH := "res://assets/textures/texture_values.json"
const WATER_SURFACE_LEVEL: float = -1.0
const NOISE_SEED: int = 7891

# BIOMES
const BIOME_VALUES_PATH := "res://assets/biomes/biome_values.json"
const STEEP_THRESHOLD: float = 30.0
const STEEP_BLEND_RANGE: float = 10.0 # Degrees on each side of STEEP_THRESHOLD over which flat/steep textures blend.
const TEXTURE_BLEND_SHARPNESS: float = 50.0
const HEIGHT_BLEND_SHARPNESS: float = 5.0
const SIZE_BASE_FREQ := 0.00015
const HEIGHT_BASE_FREQ := 0.0015
const BIOME_HEIGHT_THRESHOLD := 0.001

# DECORS
const DECOR_PATH: String = "res://assets/decors/"
const DECOR_VALUES_FILE: String = DECOR_PATH + "decor_values.json"
const DECOR_STEP: int = 2 # Distance between placed mesh instances; lower = denser.
const DECOR_EMPTY_CHANCE: float = 0.3

# CHUNKS
const BIOME_WEIGHT_THRESHOLD: float = 0.01 # treshold to be counted into splatmap
const BIOME_PROMINENCE_TRESHOLD: float = 0.1 # biome must cover at least 10% of pixels
const STARTUP_RADIUS: int = 1
const CLOSE_RADIUS: int = 3
const FAR_RADIUS: int = 30
const CLOSE_RESOLUTION: int = 48
const FAR_RESOLUTION: int = 6
const REMOVE_CHUNKS_MARGIN: int = 3

# THREADING
const STARTUP_DECOR_THREADS: int = 16
const STARTUP_CHUNK_THREADS: int = 4
const STARTUP_CHUNKS_PER_FRAME: int = 16
const STARTUP_LOD_PER_FRAME: int = 100

const STEADY_CHUNK_THREADS: int = 4
const STEADY_DECOR_THREADS: int = 2
const STEADY_CHUNKS_PER_FRAME: int = 4
const STEADY_LOD_PER_FRAME: int = 4  # Keep low: each FAR apply builds a mesh + uploads a texture on the main thread.

const CHUNK_CLEAN_INTERVAL: float = 0.5  # Only scan for chunk removal twice per second.
# VISIBILITY
## Maximum render distance for FAR-LOD chunks (GPU-level cull).  Set to 0 to disable.
const FAR_LOD_VISIBILITY_RANGE: float = float(FAR_RADIUS) * float(CHUNK_SIZE) * 1.05
## Interval (seconds) between full chunk-request scans when the player hasn't moved chunks.
const CHUNK_SCAN_INTERVAL: float = 0.25

# TEXTURE
const TERRAIN_SHADER_PATH := "res://assets/terrain_blend.gdshader"
const TEXTURE_SCALE: float = 16.0

#  NAVIGATION 
const NAV_BAKE_RADIUS: float = 1024.0 ## XZ half-extent of the nav mesh bake area around the player.

const NAV_BAKE_HEIGHT: float = 300.0 ## Full height window baked around the player's Y position.
const NAV_CELL_SIZE: float = 1.0
const NAV_CELL_HEIGHT: float = 0.5
const MIN_REBASE_DIST: float = 128.0 ## How far (XZ) the player must move before a rebake is triggered.
const BAKE_COOLDOWN: float = 1.5
