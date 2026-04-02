extends RefCounted
class_name GroundChunk

## Scene-node wrapper for a terrain chunk. Holds the MeshInstance3D, optional collision body, and a reference to the underlying ChunkData.
# TODO is this script needed for each instance?
# ── Per-chunk references ──────────────────────────────────────────────
var data: ChunkData = null # TODO i dont think Chunk needs to store ChunkData, its only needed for initialization.
var mesh_instance: MeshInstance3D = null
var collision_body: StaticBody3D = null
var lod_tier: int = GroundConstants.LOD_LEVELS.FAR
var are_decors_spawned: bool = false

# ── Convenience accessors (delegate to data) ──────────────────────────
var loc: Vector2i:
	get: return data.loc if data else Vector2i.ZERO
var heightmap: Image:
	get: return data.heightmap if data else null

## Build the chunk node hierarchy from a ChunkData.
## Call on the main thread after generating data on a worker.
static func build_chunk(chunk_d: ChunkData, shader_material: ShaderMaterial) -> GroundChunk:
	var add_collision := chunk_d.lod_tier == GroundConstants.LOD_LEVELS.CLOSE
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

	chunk.mesh_instance = mi

	if add_collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col_shape := CollisionShape3D.new()
		col_shape.shape = _build_heightmap_shape(chunk_d.heightmap, res)
		# HeightMapShape3D is centered at origin with 1-unit cell spacing.
		# Scale by cell size and offset by half-chunk so it aligns with the visual mesh
		# (which spans [0, CHUNK_SIZE] in X/Z relative to the MeshInstance3D position).
		var cell_size: float = float(GroundConstants.CHUNK_SIZE) / float(res - 1)
		col_shape.scale = Vector3(cell_size, 1.0, cell_size)
		col_shape.position = Vector3(GroundConstants.CHUNK_SIZE * 0.5, 0.0, GroundConstants.CHUNK_SIZE * 0.5)
		body.add_child(col_shape)
		mi.add_child(body)
		chunk.collision_body = body

	return chunk

## Free the visual and collision nodes.
func destroy() -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	mesh_instance = null
	collision_body = null

## Build a HeightMapShape3D from a heightmap image.
## HeightMapShape3D is far more nav-friendly than a trimesh — Godot's nav parser
## handles it without flooding the rasterizer with thousands of tiny edges.
static func _build_heightmap_shape(img: Image, res: int) -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = res
	shape.map_depth = res
	var heights := PackedFloat32Array()
	heights.resize(res * res)
	for z in res:
		for x in res:
			heights[z * res + x] = img.get_pixel(x, z).r
	shape.map_data = heights
	return shape

# ── Mesh construction ─────────────────────────────────────────────────
## Builds an indexed mesh with smooth normals via generate_normals().
static func _build_mesh(img: Image, res: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var inv := 1.0 / float(res - 1)
	# Add all vertices with UVs (normals will be generated later)
	for y in res:
		for x in res:
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
