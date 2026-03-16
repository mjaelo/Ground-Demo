@tool
extends Node

@onready var ground: Ground = get_parent()

func _ready():
	pass

# ── Editor Preview ──────────────────────────────────────────────────────
@export_group("Editor Preview")
@export_range(1, 10) var editor_preview_radius: int = 3
@export var generate_in_editor: bool = false:
	set(value):
		generate_in_editor = value
		if Engine.is_editor_hint() and is_inside_tree():
			if value:
				_editor_generate()
			else:
				_editor_clear()

# ── Editor preview generation TODO move/extract common logic to TerrainManager. should not be trated as base logc
func _editor_generate() -> void:
	_editor_clear()
	ground._create_managers()

	var chunk_size := float(GroundConstants.CHUNK_SIZE)
	var scale: float = GroundConstants.height_max - GroundConstants.height_min
	var r: int = editor_preview_radius
	var total: int = (2 * r + 1) * (2 * r + 1)

	# Build shader material for preview chunks
	var mat := ground._terrain_manager._build_shader_material() # TODO is it needed both here and in TerrainManager?

	for rx in range(-r, r + 1):
		for ry in range(-r, r + 1):
			var loc := Vector2i(rx, ry)
			var res: int = GroundConstants.close_resolution
			var inv := 1.0 / float(res - 1)
			var bx: float = loc.x * chunk_size
			var bz: float = loc.y * chunk_size

			# Heightmap
			var height_map := Image.create_empty(res, res, false, Image.FORMAT_RF)
			for x in res:
				var nx: float = float(x) * inv * chunk_size + bx
				for y in res:
					var ny: float = float(y) * inv * chunk_size + bz
					var h: float = ground._noise.get_noise_2d(nx, ny)
					h = (h + 1.0) * 0.5
					h = pow(h, ground._biome_manager.get_height_curve(nx, ny))
					height_map.set_pixel(x, y, Color(GroundConstants.height_min + h * scale, 0, 0, 1))

			# Splatmap
			var splat_map := Image.create_empty(res, res, false, Image.FORMAT_RGBA8)
			var cs: float = float(chunk_size) / float(res - 1)
			for x in res:
				var nx: float = float(x) * inv * chunk_size + bx
				for y in res:
					var ny: float = float(y) * inv * chunk_size + bz
					var hc: float = height_map.get_pixel(x, y).r
					var hr: float = hc if x + 1 >= res else height_map.get_pixel(x + 1, y).r
					var hd: float = hc if y + 1 >= res else height_map.get_pixel(x, y + 1).r
					var slope: float = rad_to_deg(acos(clampf(
						Vector3(-(hr - hc) / cs, 1.0, -(hd - hc) / cs).normalized().dot(Vector3.UP), -1.0, 1.0)))
					var bw := ground._biome_manager._biome_weights(nx, ny)
					var wr := 0.0; var wg := 0.0; var wb := 0.0
					for i in bw.size():
						if bw[i] < 0.01: continue
						var bd: BiomeData = ground._biome_manager.biomes[i]
						var bt: int = bd.steep_texture_id if slope > GroundConstants.STEEP_THRESHOLD else bd.flat_texture_id
						if bt == 0:   wr += bw[i]
						elif bt == 1: wg += bw[i]
						elif bt == 2: wb += bw[i]
					splat_map.set_pixel(x, y, Color(wr, wg, wb, 1.0))

			var chunk := GroundChunk.build_chunk(loc, GroundConstants.LOD_LEVELS.CLOSE, height_map, splat_map, mat, false)
			chunk.mesh_instance.name = "EditorChunk_%d_%d" % [rx, ry]
			print($"../Chunks")
			$"../Chunks".add_child(chunk.mesh_instance)
			chunk.mesh_instance.owner = get_tree().edited_scene_root

	print("[EditorGen] Done! %d chunks." % total)

func _editor_clear() -> void:
	var to_remove: Array[Node] = []
	for child in $"../Chunks".get_children():
		if child.name.begins_with("EditorChunk_"):
			to_remove.push_back(child)
	for child in to_remove:
		child.queue_free()
	print("[EditorGen] Cleared %d preview chunks." % to_remove.size())
