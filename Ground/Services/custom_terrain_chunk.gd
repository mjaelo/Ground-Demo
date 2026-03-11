extends RefCounted
class_name CustomTerrainChunk

## Represents a single terrain chunk as a MeshInstance3D with optional
## collision, using a custom shader for multi-texture blending.
## Replaces Terrain3D's region system entirely.

# ── LOD tiers (must match CustomTerrainManager constants) ─────────────
const TIER_CLOSE := 0
const TIER_MEDIUM := 1
const TIER_FAR := 2

# ── Per-chunk data ────────────────────────────────────────────────────
var loc: Vector2i = Vector2i.ZERO
var tier: int = TIER_FAR
var mesh_instance: MeshInstance3D = null
var collision_body: StaticBody3D = null
var heightmap: Image = null          # kept for world-shift reuse
var splatmap: Image = null           # R=weight0, G=weight1, B=weight2
var mesh_assets_spawned: bool = false

## Build the chunk node hierarchy and return the root MeshInstance3D.
## Call on the main thread after generating data on a worker.
static func build_chunk(
	p_loc: Vector2i,
	p_tier: int,
	region_size: int,
	p_heightmap: Image,
	p_splatmap: Image,
	shader_material: ShaderMaterial,
	add_collision: bool,
) -> CustomTerrainChunk:
	var chunk := CustomTerrainChunk.new()
	chunk.loc = p_loc
	chunk.tier = p_tier
	chunk.heightmap = p_heightmap
	chunk.splatmap = p_splatmap

	var res: int = p_heightmap.get_width()
	var mesh := _build_mesh(p_heightmap, res, region_size)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Create per-instance material with splatmap texture
	var mat: ShaderMaterial = shader_material.duplicate() as ShaderMaterial
	var splat_tex := ImageTexture.create_from_image(p_splatmap)
	mat.set_shader_parameter("splatmap", splat_tex)
	mat.set_shader_parameter("region_size", float(region_size))
	mi.material_override = mat

	mi.position = Vector3(p_loc.x * region_size, 0, p_loc.y * region_size)
	chunk.mesh_instance = mi

	if add_collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col_shape := CollisionShape3D.new()
		col_shape.shape = mesh.create_trimesh_shape()
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

## Shift the chunk's world position (for world-origin shifting).
func shift(offset: Vector3) -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.position += offset

# ── Mesh construction ─────────────────────────────────────────────────
## Builds an indexed mesh with smooth normals via generate_normals().
static func _build_mesh(img: Image, res: int, region_size: int) -> ArrayMesh:
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
			st.add_vertex(Vector3(u * region_size, h, v * region_size))

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
