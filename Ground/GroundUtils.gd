extends Object
class_name GroundUtils

# materials
static var WATER_MESH: QuadMesh = (func ()->QuadMesh: 
	var water_mesh := QuadMesh.new() 
	water_mesh.size = Vector2(GroundConstants.CHUNK_SIZE, GroundConstants.CHUNK_SIZE) 
	return water_mesh).call()
static var WATER_MATERIAL: StandardMaterial3D = (func () -> StandardMaterial3D:
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.0, 0.35, 0.65, 0.25)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.2
	water_material.metallic = 0.0
	return water_material).call()

# GENERAL GROUND UTILS
static func world_pos_to_chunk_loc(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / float(GroundConstants.CHUNK_SIZE)), floori(pos.z / float(GroundConstants.CHUNK_SIZE)))

static func height_from_heightmap(img: Image, world_x:float, world_z:float, loc: Vector2i) -> float:
	var res: int = img.get_width()
	var lx: float = world_x - loc.x * GroundConstants.CHUNK_SIZE
	var lz: float = world_z - loc.y * GroundConstants.CHUNK_SIZE
	var px: int = clampi(int(lx / float(GroundConstants.CHUNK_SIZE) * (res - 1)), 0, res - 1)
	var py: int = clampi(int(lz / float(GroundConstants.CHUNK_SIZE) * (res - 1)), 0, res - 1)
	return img.get_pixel(px, py).r

# CHUNK UTILS
static func build_chunk(chunk_d: ChunkData, shader_material: ShaderMaterial, lod_tier: int) -> GroundChunk:
	## Build GroundChunk from a ChunkData.
	var chunk := GroundChunk.new()
	chunk.data = chunk_d

	var res: int = chunk_d.heightmap.get_width()
	var mesh := _build_mesh(chunk_d.heightmap, res)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Create per-instance material with splatmap texture
	var mat: ShaderMaterial = shader_material.duplicate() as ShaderMaterial
	var splat_tex := ImageTexture.create_from_image(chunk_d.splatmap)
	mat.set_shader_parameter("splatmap", splat_tex)
	mat.set_shader_parameter("region_size", float(GroundConstants.CHUNK_SIZE))
	mi.material_override = mat
	mi.position = Vector3(chunk_d.loc.x * GroundConstants.CHUNK_SIZE, 0, chunk_d.loc.y * GroundConstants.CHUNK_SIZE)

	# GPU-level distance cull for FAR-LOD tiles so they are not rendered beyond the streamed radius.
	if lod_tier == GroundConstants.LOD_LEVELS.FAR and GroundConstants.FAR_LOD_VISIBILITY_RANGE > 0.0:
		mi.visibility_range_end = GroundConstants.FAR_LOD_VISIBILITY_RANGE
		mi.visibility_range_end_margin = GroundConstants.CHUNK_SIZE * 2.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	chunk.mesh_instance = mi

	if chunk_d.has_water:
		var wmi := get_water_mi()
		mi.add_child(wmi)

	if lod_tier == GroundConstants.LOD_LEVELS.CLOSE:
		var body := get_collision(chunk_d, res)
		mi.add_child(body)
		chunk.collision_body = body

	return chunk

static func get_collision(chunk_d:ChunkData, res: int ) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col_shape := CollisionShape3D.new()
	col_shape.shape = _build_heightmap_shape(chunk_d.heightmap, res)
	var cell_size: float = float(GroundConstants.CHUNK_SIZE) / float(res - 1)
	col_shape.scale = Vector3(cell_size, 1.0, cell_size)
	col_shape.position = Vector3(GroundConstants.CHUNK_SIZE * 0.5, 0.0, GroundConstants.CHUNK_SIZE * 0.5)
	body.add_child(col_shape)
	return body

static func get_water_mi() ->MeshInstance3D:
	var wmi := MeshInstance3D.new()
	wmi.mesh = WATER_MESH
	wmi.material_override = WATER_MATERIAL
	wmi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	wmi.position = Vector3(GroundConstants.CHUNK_SIZE * 0.5, GroundConstants.WATER_SURFACE_LEVEL, GroundConstants.CHUNK_SIZE * 0.5)
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return wmi

static func _build_heightmap_shape(img: Image, res: int) -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = res
	shape.map_depth = res
	var heights := PackedFloat32Array()
	heights.resize(res * res)
	for z in range(res):
		for x in range(res):
			heights[z * res + x] = img.get_pixel(x, z).r
	shape.map_data = heights
	return shape

## Builds an indexed mesh with smooth normals via generate_normals().
static func _build_mesh(img: Image, res: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var inv := 1.0 / float(res - 1)
	# Add all vertices with UVs (normals will be generated later)
	for y in range(res):
		for x in range(res):
			var u: float = float(x) * inv
			var v: float = float(y) * inv
			var h: float = img.get_pixel(x, y).r
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(u * GroundConstants.CHUNK_SIZE, h, v * GroundConstants.CHUNK_SIZE))

	# Add triangle indices
	for y in range(res - 1):
		for x in range(res - 1):
			var i00: int = y * res + x
			var i10: int = i00 + 1
			var i01: int = i00 + res
			var i11: int = i01 + 1
			# Tri 1
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i01)
			# Tri 2
			st.add_index(i11)
			st.add_index(i01)
			st.add_index(i10)

	# Let SurfaceTool compute smooth vertex normals from the triangle geometry
	st.generate_normals()
	return st.commit()
