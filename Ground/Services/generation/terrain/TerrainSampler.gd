extends RefCounted
class_name TerrainSampler

## Noise-based height and normal sampling for terrain generation.

var _noise: FastNoiseLite = null
var _biome_manager: BiomeManager = null

func initialize(noise: FastNoiseLite, biome_manager: BiomeManager) -> void:
	_noise = noise
	_biome_manager = biome_manager

func sample_height(world_x: float, world_z: float) -> float:
	var h := _noise.get_noise_2d(world_x, world_z)
	h = (h + 1.0) * 0.5
	h = pow(h, _biome_manager.get_height_curve(world_x, world_z))
	return GroundConstants.height_min + h * (GroundConstants.height_max - GroundConstants.height_min)

func sample_normal(world_x: float, world_z: float) -> Vector3:
	var bh := sample_height(world_x, world_z)
	var dx := sample_height(world_x + 1.0, world_z) - bh
	var dz := sample_height(world_x, world_z + 1.0) - bh
	return Vector3(-dx, 1.0, -dz).normalized()
