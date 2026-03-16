extends Object
class_name GroundUtils

# ── Ground Utility ───────────────────────────────────────────────────────────
static func world_pos_to_chunk_loc(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / float(GroundConstants.CHUNK_SIZE)), floori(pos.z / float(GroundConstants.CHUNK_SIZE)))

static func height_from_heightmap(img: Image, world_pos: Vector3, loc: Vector2i) -> float:
	var res: int = img.get_width()
	var lx: float = world_pos.x - loc.x * GroundConstants.CHUNK_SIZE
	var lz: float = world_pos.z - loc.y * GroundConstants.CHUNK_SIZE
	var px: int = clampi(int(lx / float(GroundConstants.CHUNK_SIZE) * (res - 1)), 0, res - 1)
	var py: int = clampi(int(lz / float(GroundConstants.CHUNK_SIZE) * (res - 1)), 0, res - 1)
	return img.get_pixel(px, py).r
