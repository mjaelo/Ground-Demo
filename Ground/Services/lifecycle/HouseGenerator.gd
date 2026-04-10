@tool
extends Node3D

@export var generate :bool = false: 
	set(value):
		generate = value
		if Engine.is_editor_hint() and is_inside_tree():
			call_generator(self)

const max_house_width := 10.0
const max_house_height := 10.0
const max_house_depth := 10.0
const foundation_height := 5.0

const wall_cols := [Color(0.72, 0.65, 0.55), Color(0.59, 0.50, 0.43), Color(0.68, 0.62, 0.49)]
const roof_cols := [Color(0.28, 0.18, 0.12), Color(0.42, 0.28, 0.18), Color(0.35, 0.32, 0.28)]
static var stone_mat := get_material(Color(0.40, 0.37, 0.34), 0.95, 0.0)
static var door_mat  := get_material(Color(0.12, 0.06, 0.03), 0.9, 0.0)

## builds a procedural house in root node.
static func call_generator(root: Node3D) -> void:
	# Remove all existing children (placeholder mesh etc.)
	for c in root.get_children():
		root.remove_child(c)
		if is_instance_valid(c):
			c.free()

	var rng := RandomNumberGenerator.new()
	var p := root.position
	rng.seed = hash(str(int(p.x * 10), "_", int(p.z * 10)))

	# Materials
	var wall_mat  := get_material(wall_cols[rng.randi() % wall_cols.size()], 0.85, 0.02)
	var roof_mat  := get_material(roof_cols[rng.randi() % roof_cols.size()], 0.90, 0.02)

	# Dimensions (increased ranges so houses are larger)
	var bw: float = rng.randf_range(max_house_width/2, max_house_width) # base width (X)
	var bd: float = rng.randf_range(max_house_height/2, max_house_height) # base depth (Z)
	var bh: float = rng.randf_range(max_house_depth/2, max_house_depth)  # wall height (Y)
	var rh: float = rng.randf_range(max_house_height/4, max_house_height/2)  # roof height
	var fh: float = foundation_height
	
	_add_box(root, "Foundation", Vector3(bw + 0.6, fh, bd + 0.6), Vector3(0, -fh * 0.5, 0), stone_mat)
	_add_box(root, "Walls", Vector3(bw, bh, bd), Vector3(0, bh * 0.5, 0), wall_mat)
	_add_prism(root, "Roof", Vector3(bw + 1.0, rh, bd + 1.2), Vector3(0, bh + rh * 0.5, 0), roof_mat)
	
	add_door(rng, bw, bh, bd, root)
	if rng.randf() < 0.6:
		add_chimney(rng, bw, bh, rh, bd, root)
	
	# Collision covering the whole house (including foundation below ground)
	var total_h_full: float = fh + bh + rh # from foundation bottom (-fh) up to roof top (bh + rh)
	var cs := BoxShape3D.new()
	cs.size = Vector3(bw + 1.0, total_h_full, bd + 1.0)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	# Collision center = midpoint between foundation bottom (-fh) and roof top (bh + rh)
	col.position = Vector3(0, (bh + rh - fh) * 0.5, 0)
	col.shape = cs
	root.add_child(col)

static func add_door(rng, bw, bh, bd, root):
	# Simple front door so rotation can be verified visually
	var dw: float = 1.5
	var dh: float = 3
	var door_z: float = bd * 0.5 + 0.125
	# Door leaf (thin box). Door bottom at y=0, center at dh * 0.5
	_add_box(root, "Door", Vector3(dw, dh, 0.25), Vector3(0, dh * 0.5, door_z), door_mat)
	# Door frame pillars and lintel
	var frame_w: float = 0.25
	_add_box(root, "DoorFrameL", Vector3(frame_w, dh + 0.4, 0.35), Vector3(-dw * 0.5 - frame_w * 0.5, dh * 0.5, door_z), stone_mat)
	_add_box(root, "DoorFrameR", Vector3(frame_w, dh + 0.4, 0.35), Vector3( dw * 0.5 + frame_w * 0.5, dh * 0.5, door_z), stone_mat)
	_add_box(root, "DoorFrameT", Vector3(dw + frame_w * 2.0 + 0.2, 0.35, 0.35), Vector3(0, dh + 0.2, door_z), stone_mat)

static func add_chimney(rng, bw, bh, rh, bd, root):
	# Chimney should start at roof top (y = bh + rh) and extend upward
	var cw: float = rng.randf_range(0.4, .8)
	var shaft_h: float = rng.randf_range(.5, 1.0) # height above roof
	var ch_total: float = shaft_h
	var cx: float = rng.randf_range(-bw * 0.25, bw * 0.25)
	# Place chimney so its bottom sits at roof top (bh + rh), center at bh + rh + ch_total*0.5
	_add_box(root, "Chimney", Vector3(cw, ch_total, cw), Vector3(cx, bh + rh + ch_total * 0.5, 0), stone_mat)
	_add_box(root, "ChimneyCap", Vector3(cw + 0.4, 0.3, cw + 0.4), Vector3(cx, bh + rh + ch_total + 0.15, 0), stone_mat)

# Static helpers
static func _add_box(parent: Node3D, n: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var m := BoxMesh.new()
	m.size = size
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

static func get_material(col: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = roughness
	m.metallic = metallic
	return m
