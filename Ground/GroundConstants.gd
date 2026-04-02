extends Resource
class_name GroundConstants

enum LOD_LEVELS {CLOSE, FAR}

# ── GENERAL GROUND ────────────────────────────────────────────────────
const HEIGHT_MIN: float = 0.0
const HEIGHT_MAX: float = 800.0
const CHUNK_SIZE: int = 256
const TEXTURES_FILE_PATH := "res://assets/textures/texture_values.json"

# ── BIOMES ────────────────────────────────────────────────────────────
const BIOME_VALUES_PATH := "res://assets/biomes/biome_values.json"
const STEEP_THRESHOLD: float = 30.0
const STEEP_BLEND_RANGE: float = 10.0 # Degrees on each side of STEEP_THRESHOLD over which flat/steep textures blend.

# ── DECORS ───────────────────────────────────────────────────────
const DECOR_PATH: String = "res://assets/decors/"
const DECOR_VALUES_FILE: String = DECOR_PATH + "decor_values.json"
const DECOR_STEP: int = 2 # Distance between placed mesh instances; lower = denser.
const DECOR_EMPTY_CHANCE: float = 0.3

# ── CHUNKS ─────────────────────────────────────────

const initial_chunk_radius: int = 1
const close_radius: int = 2
const far_radius: int = 22
const close_resolution: int = 48
const far_resolution: int = 6
const REMOVE_CHUNKS_MARGIN: int = 3

const STARTUP_DECOR_THREADS: int = 16
const STARTUP_CHUNK_THREADS: int = 4
const STARTUP_CHUNKS_PER_FRAME: int = 16
const STARTUP_LOD_PER_FRAME: int = 100

const STEADY_CHUNK_THREADS: int = 4
const STEADY_DECOR_THREADS: int = 4
const STEADY_CHUNKS_PER_FRAME: int = 4
const STEADY_LOD_PER_FRAME: int = 30

# ── TERRAIN SHADER ────────────────────────────────────────────────────
const TERRAIN_SHADER_PATH := "res://assets/terrain_blend.gdshader"
const TEXTURE_SCALE: float = 16.0

# ── NOISE ─────────────────────────────────────────────────────────────
const NOISE_FREQUENCY: float = 0.0009
# ── NAVIGATION ─────────────────────────────────────────────────────────────
## XZ half-extent of the nav mesh bake area around the player.
const NAV_BAKE_RADIUS: float = 1024.0
## Full height window baked around the player's Y position.
const NAV_BAKE_HEIGHT: float = 300.0
const NAV_CELL_SIZE: float = 1.0
const NAV_CELL_HEIGHT: float = 0.5
## How far (XZ) the player must move before a rebake is triggered.
const MIN_REBASE_DIST: float = 128.0
const BAKE_COOLDOWN: float = 1.5
