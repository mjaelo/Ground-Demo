extends Object

## Called by DecorManager after the House scene is instantiated and added to the tree.
## Clears the scene's default placeholder content and builds a procedural house in its place.
static func call_generator(root: Node3D) -> void:
	# Remove all existing children (placeholder mesh etc.)
	for c in root.get_children():
		c.queue_free()
	await root.get_tree().process_frame

	var rng := RandomNumberGenerator.new()
	var p := root.position
	rng.seed = hash(str(int(p.x * 10), "_", int(p.z * 10)))

	# Materials
	var wall_cols := [Color(0.72, 0.65, 0.55), Color(0.59, 0.50, 0.43), Color(0.68, 0.62, 0.49)]
	var roof_cols := [Color(0.28, 0.18, 0.12), Color(0.42, 0.28, 0.18), Color(0.35, 0.32, 0.28)]
	var wall_mat  := _mat(wall_cols[rng.randi() % wall_cols.size()], 0.85, 0.02)
	var roof_mat  := _mat(roof_cols[rng.randi() % roof_cols.size()], 0.90, 0.02)
	var stone_mat := _mat(Color(0.40, 0.37, 0.34), 0.95, 0.0)
	var door_mat  := _mat(Color(0.12, 0.06, 0.03), 0.9, 0.0)

	# Dimensions
	var bw: float = rng.randf_range(8.0, 16.0)
	var bd: float = rng.randf_range(7.0, 13.0)
	var bh: float = rng.randf_range(5.0, 9.0)
	var rh: float = rng.randf_range(4.0, 7.0)
	var fh: float = rng.randf_range(0.5, 1.2)

	_add_box(root, "Foundation", Vector3(bw + 0.6, fh, bd + 0.6),          Vector3(0, fh * 0.5, 0), stone_mat)
	_add_box(root, "Walls",      Vector3(bw, bh, bd),                       Vector3(0, fh + bh * 0.5, 0), wall_mat)
	_add_prism(root, "Roof",     Vector3(bw + 1.0, rh, bd + 1.2),           Vector3(0, fh + bh + rh * 0.5, 0), roof_mat)

	# Simple front door so rotation can be verified visually
	var dw: float = clamp(rng.randf_range(1.8, 3.0), 1.2, bw * 0.6)
	var dh: float = min(bh * 0.75, rng.randf_range(2.2, 3.2))
	var door_z: float = bd * 0.5 + 0.125
	# Door leaf (thin box)
	_add_box(root, "Door", Vector3(dw, dh, 0.25), Vector3(0, fh + dh * 0.5, door_z), door_mat)
	# Door frame pillars and lintel
	var frame_w: float = 0.25
	_add_box(root, "DoorFrameL", Vector3(frame_w, dh + 0.4, 0.35), Vector3(-dw * 0.5 - frame_w * 0.5, fh + dh * 0.5, door_z), stone_mat)
	_add_box(root, "DoorFrameR", Vector3(frame_w, dh + 0.4, 0.35), Vector3( dw * 0.5 + frame_w * 0.5, fh + dh * 0.5, door_z), stone_mat)
	_add_box(root, "DoorFrameT", Vector3(dw + frame_w * 2.0 + 0.2, 0.35, 0.35), Vector3(0, fh + dh + 0.2, door_z), stone_mat)

	# Optional chimney
	if rng.randf() < 0.6:
		var cw: float = rng.randf_range(0.8, 1.4)
		var ch: float = bh + rh + rng.randf_range(1.0, 2.5)
		var cx: float = rng.randf_range(-bw * 0.25, bw * 0.25)
		_add_box(root, "Chimney",    Vector3(cw, ch, cw),              Vector3(cx, fh + ch * 0.5, 0), stone_mat)
		_add_box(root, "ChimneyCap", Vector3(cw + 0.4, 0.3, cw + 0.4), Vector3(cx, fh + ch + 0.15, 0), stone_mat)

	# Single box collision covering the whole house
	var total_h: float = fh + bh + rh
	var cs := BoxShape3D.new()
	cs.size = Vector3(bw + 1.0, total_h, bd + 1.0)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = cs
	col.position = Vector3(0, total_h * 0.5, 0)
	root.add_child(col)

# ---------------------------------------------------------------------------
# Static helpers
# ---------------------------------------------------------------------------

static func _add_box(parent: Node3D, n: String, sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var m := BoxMesh.new()
	m.size = sz
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)

static func _add_prism(parent: Node3D, n: String, sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var m := PrismMesh.new()
	m.size = sz
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)

static func _mat(col: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = roughness
	m.metallic = metallic
	return m
