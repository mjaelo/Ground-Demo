extends Resource
class_name BiomeData

## Human-readable biome name.
@export var biome_name: String = ""

## Height curve exponent applied to the base noise.
## Higher values = flatter/lower terrain; lower values = taller peaks.
@export var height_curve: float = 2.0

## Texture ID used on flat ground (slope below steep_slope_threshold).
@export var flat_texture_id: int = 1  # e.g. Grass

## Texture ID used on steep slopes (slope above steep_slope_threshold).
@export var steep_texture_id: int = 0  # e.g. Rock

## If true, a single texture covers the whole biome regardless of slope.
@export var uniform_texture: bool = false

## The slope angle (degrees) above which the steep texture is used.
@export var steep_slope_threshold: float = 30.0

## Relative weight for biome selection. Higher = more common.
@export var weight: float = 1.0

## Returns the texture ID for a given slope angle in degrees.
func get_texture_id(slope_deg: float) -> int:
	if uniform_texture:
		return flat_texture_id
	if slope_deg > steep_slope_threshold:
		return steep_texture_id
	return flat_texture_id
