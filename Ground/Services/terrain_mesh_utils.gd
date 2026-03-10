extends RefCounted
class_name TerrainMeshUtils

# Shared static functions for terrain heightmap, mesh, and material generation

static func generate_heightmap(loc: Vector2i, region_size: int, resolution: int, noise, biome_manager, world_offset: Vector3, height_min: float, height_max: float) -> Image:
	var img: Image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RF)
	var import_scale: float = height_max - height_min
	for x in resolution:
		for y in resolution:
			var nx: float = (x / float(resolution)) * region_size + loc.x * region_size + world_offset.x
			var ny: float = (y / float(resolution)) * region_size + loc.y * region_size + world_offset.z
			var h: float = noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			var curve_exp: float = biome_manager.get_height_curve(nx, ny)
			h = pow(h, curve_exp)
			var world_h: float = height_min + h * import_scale
			img.set_pixel(x, y, Color(world_h, 0., 0., 1.))
	return img

static func calculate_slope_from_heightmap(img: Image, px: int, py: int, region_size: int, res: int) -> float:
	var h_c: float = img.get_pixel(px, py).r
	var h_r: float = h_c if px + 1 >= res else img.get_pixel(px + 1, py).r
	var h_d: float = h_c if py + 1 >= res else img.get_pixel(px, py + 1).r
	var cell_size: float = float(region_size) / float(res - 1)
	var dx: float = (h_r - h_c) / cell_size
	var dz: float = (h_d - h_c) / cell_size
	var n := Vector3(-dx, 1.0, -dz).normalized()
	return rad_to_deg(acos(clamp(n.dot(Vector3.UP), -1.0, 1.0)))

static func build_heightmap_mesh(img: Image, res: int, region_size: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array = []
	verts.resize(res * res)
	for y in res:
		for x in res:
			var u: float = float(x) / float(res - 1)
			var v: float = float(y) / float(res - 1)
			var px: float = u * region_size
			var pz: float = v * region_size
			var h: float = img.get_pixel(x, y).r
			verts[y * res + x] = Vector3(px, h, pz)
	for y in range(res - 1):
		for x in range(res - 1):
			var i00: int = y * res + x
			var i10: int = y * res + x + 1
			var i01: int = (y + 1) * res + x
			var i11: int = (y + 1) * res + x + 1
			var n1: Vector3 = (verts[i10] - verts[i00]).cross(verts[i01] - verts[i00]).normalized()
			var n2: Vector3 = (verts[i01] - verts[i11]).cross(verts[i10] - verts[i11]).normalized()
			st.set_normal(n1)
			st.set_uv(Vector2(float(x) / float(res - 1), float(y) / float(res - 1)))
			st.add_vertex(verts[i00])
			st.set_normal(n1)
			st.set_uv(Vector2(float(x + 1) / float(res - 1), float(y) / float(res - 1)))
			st.add_vertex(verts[i10])
			st.set_normal(n1)
			st.set_uv(Vector2(float(x) / float(res - 1), float(y + 1) / float(res - 1)))
			st.add_vertex(verts[i01])
			st.set_normal(n2)
			st.set_uv(Vector2(float(x + 1) / float(res - 1), float(y + 1) / float(res - 1)))
			st.add_vertex(verts[i11])
			st.set_normal(n2)
			st.set_uv(Vector2(float(x) / float(res - 1), float(y + 1) / float(res - 1)))
			st.add_vertex(verts[i01])
			st.set_normal(n2)
			st.set_uv(Vector2(float(x + 1) / float(res - 1), float(y) / float(res - 1)))
			st.add_vertex(verts[i10])
	return st.commit()
