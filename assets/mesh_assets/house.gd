@tool
extends StaticBody3D

enum HouseType {
	COTTAGE   = 0,  ## simple single-storey cottage
	L_SHAPED  = 1,  ## L-shaped with a side annex
	TOWER     = 2,  ## main body + round tower
	TWO_STOREY = 3, ## two-storey with jetty overhang
}

## Every time you toggle this ON the house is regenerated with a new random
## variant.  The counter is used as an extra seed so each click differs.
@export var generate_in_editor: bool = false:
	set(value):
		generate_in_editor = false
		if value and Engine.is_editor_hint():
			_build_count += 1
			_build_house()

## Internal rebuild counter — changing it also changes the seed.
@export var _build_count: int = 0
@export var ground_normal: Vector3 = Vector3.UP

# ───────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	call_deferred("_build_house")

# ───────────────────────────────────────────────────────────────────────────
func _build_house() -> void:
	# ---- clear children ----------------------------------------------------
	for c in get_children():
		c.queue_free()
	if is_inside_tree():
		await get_tree().process_frame

	# ---- RNG ---------------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	var p := position
	rng.seed = hash(str(int(p.x * 10.0), "_", int(p.y * 10.0), "_", int(p.z * 10.0), "_", _build_count))

	# ---- colour palettes (medieval stone / plaster / wood) -----------------
	var wall_cols = [
		Color(0.72, 0.65, 0.55), 
#		Color(0.62, 0.58, 0.50),
		Color(0.59, 0.499, 0.425, 1.0), 
#		Color(0.55, 0.50, 0.44),
		Color(0.678, 0.62, 0.486, 1.0),
	]
	var timber_cols = [
		Color(0.30, 0.18, 0.10), 
		Color(0.25, 0.15, 0.08),
	]
	var roof_cols = [
		Color(0.28, 0.18, 0.12),
		Color(0.42, 0.28, 0.18),
		Color(0.42, 0.262, 0.227, 1.0), 
		Color(0.35, 0.32, 0.28),
	]
	var trim_cols = [
		Color(0.18, 0.18, 0.18), 
		Color(0.40, 0.30, 0.20),
	]

	var wall_mat := _mat(_vary(wall_cols[rng.randi() % wall_cols.size()], rng), 0.85, 0.02)
	var timber_mat := _mat(_vary(timber_cols[rng.randi() % timber_cols.size()], rng), 0.75, 0.0)
	var roof_mat := _mat(_vary(roof_cols[rng.randi() % roof_cols.size()], rng), 0.90, 0.02)
	var trim_mat := _mat(_vary(trim_cols[rng.randi() % trim_cols.size()], rng), 0.60, 0.08)
	var stone_mat := _mat(Color(0.401, 0.374, 0.337, 1.0), 0.95, 0.0)

	# ---- pick a house type -------------------------------------------------
	var house_type: HouseType = rng.randi() % HouseType.size() as HouseType
	var has_chimney: bool = rng.randf() < 0.7
	var has_columns: bool = rng.randf() < 0.4
	var has_half_timber: bool = rng.randf() < 0.6
	var has_arch_door: bool = rng.randf() < 0.5

	# ---- main body dims (all values in metres, no scale factor) -------------
	var bw: float = rng.randf_range(16.0, 28.0)   # width
	var bd: float = rng.randf_range(14.0, 24.0)   # depth
	var bh: float = rng.randf_range(10.0, 16.0)   # wall height
	var rh: float = rng.randf_range(7.0, 13.0)    # roof height

	# ==== STONE FOUNDATION ==================================================
	var fh: float = rng.randf_range(1.2, 2.4)
	_add_box("Foundation", Vector3(bw + 1.0, fh, bd + 1.0), Vector3(0, fh * 0.5, 0), stone_mat, rng)

	# ==== MAIN WALLS ========================================================
	_add_box("MainWalls", Vector3(bw, bh, bd), Vector3(0, fh + bh * 0.5, 0), wall_mat, rng)

	# ==== DOOR — compute dimensions first so other elements can avoid it ====
	# door_half_w: half-width of door + frame, used to keep beams and windows clear
	var door_half_w: float
	var door_h: float
	if has_arch_door:
		var dw: float = rng.randf_range(3.5, 5.0)
		door_h = min(rng.randf_range(5.5, 7.5), bh * 0.75)
		door_half_w = dw * 0.5 + 0.6 + 0.8  # half door + pillar offset + pillar half-width
		_add_arched_door_dims(bd, bh, fh, trim_mat, stone_mat, rng, dw, door_h)
	else:
		var dw: float = rng.randf_range(3.0, 4.5)
		door_h = min(rng.randf_range(5.0, 7.0), bh * 0.75)
		door_half_w = dw * 0.5 + 0.5 + 0.25  # half door + frame_w * 1.5
		_add_simple_door_dims(bd, fh, trim_mat, rng, dw, door_h)

	# ==== HALF-TIMBER FRAMING — gaps at door and windows ====================
	if has_half_timber:
		_add_half_timber(bw, bd, bh, fh, timber_mat, rng, door_half_w, door_h)

	# ==== ROOF ==============================================================
	var roof_style: int = rng.randi() % 3
	_add_roof(roof_style, bw, bd, bh, fh, rh, roof_mat, rng)

	# ==== WINDOWS — centred between door edge and wall edge =================
	_add_windows(bw, bd, bh, fh, trim_mat, rng, door_half_w)

	# ==== COLUMNS / PORCH ==================================================
	if has_columns:
		_add_columns(bw, bd, bh, fh, stone_mat, timber_mat, rng)

	# ==== CHIMNEY ===========================================================
	if has_chimney:
		_add_chimney(bw, bd, bh, fh, rh, stone_mat, rng)

	# ==== ANNEX (L-shape / tower / second storey) ===========================
	match house_type:
		HouseType.L_SHAPED:
			_add_l_annex(bw, bd, bh, fh, wall_mat, roof_mat, timber_mat, has_half_timber, rng)
		HouseType.TOWER:
			_add_tower(bw, bd, bh, fh, stone_mat, roof_mat, rng)
		HouseType.TWO_STOREY:
			_add_second_storey(bw, bd, bh, fh, rh, wall_mat, timber_mat, roof_mat, rng)

	# ==== COLLISION =========================================================
	var total_h: float = fh + bh + rh
	var cs := BoxShape3D.new()
	cs.size = Vector3(bw + 4.0, total_h, bd + 4.0)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = cs
	col.position = Vector3(0, total_h * 0.5, 0)
	_own(col)

	# --- Align to ground slope if needed ---
	var up = ground_normal.normalized()
	var align_ok = up.length() > 0.9 and abs(up.dot(Vector3.UP)) < 0.999
	if align_ok:
		var ref = abs(up.dot(Vector3.FORWARD)) < 0.99 and Vector3.FORWARD or Vector3.RIGHT
		var x_axis = up.cross(ref).normalized()
		if x_axis.length() < 0.1:
			x_axis = up.cross(Vector3.RIGHT).normalized()
		var z_axis = x_axis.cross(up).normalized()
		if x_axis.length() < 0.1 or z_axis.length() < 0.1:
			self.transform.basis = Basis.IDENTITY
		else:
			var rot_basis = Basis(x_axis, up, z_axis).orthonormalized()
			if abs(rot_basis.determinant()) < 0.01:
				self.transform.basis = Basis.IDENTITY
			else:
				self.transform.basis = rot_basis
	else:
		self.transform.basis = Basis.IDENTITY

	# --- Lower house so foundation sits at/below Y=0 ---
	var min_y := 0.0
	for c in get_children():
		if c is MeshInstance3D:
			var aabb = c.get_aabb()
			var y = c.position.y + aabb.position.y
			if min_y == 0.0 or y < min_y:
				min_y = y
	self.position.y -= min_y

	print("[House] Built type=", HouseType.keys()[house_type], "  children=", get_child_count())


# ═══════════════════════════════════════════════════════════════════════════
# BUILDING BLOCKS
# ═══════════════════════════════════════════════════════════════════════════

func _add_box(n: String, sz: Vector3, pos: Vector3, mat: StandardMaterial3D, _r) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = sz
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_own(mi)
	return mi

func _add_cylinder(n: String, radius: float, height: float, pos: Vector3, mat: StandardMaterial3D, sides: int = 12) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = sides
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_own(mi)
	return mi

func _add_prism(n: String, sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = sz
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_own(mi)
	return mi

# ── half-timber decorative beams ──────────────────────────────────────────
# door_clear_hw: X-radius around X=0 that must stay clear (door + frame)
# door_clear_h:  height of door — beams below this on the front face are skipped
func _add_half_timber(bw: float, bd: float, bh: float, fh: float, mat: StandardMaterial3D, rng: RandomNumberGenerator, door_clear_hw: float = 0.0, door_clear_h: float = 0.0) -> void:
	var beam := 0.45  # thick timber beams
	var y_base: float = fh

	# horizontal beams at 1/3 and 2/3 height on front & back
	# On the front face (side_z == +1) split the beam around the door opening
	for frac in [0.33, 0.66]:
		var y: float = y_base + bh * frac
		for side_z in [-1.0, 1.0]:
			if side_z > 0.0 and door_clear_hw > 0.0 and y < fh + door_clear_h:
				# This beam height is inside the door zone — split into left and right segments
				var seg_w: float = bw * 0.5 - door_clear_hw
				if seg_w > 0.5:
					var cx_left: float  = -(door_clear_hw + seg_w * 0.5)
					var cx_right: float =  door_clear_hw + seg_w * 0.5
					_add_box("HBeamL", Vector3(seg_w, beam, beam), Vector3(cx_left,  y, side_z * bd * 0.5), mat, rng)
					_add_box("HBeamR", Vector3(seg_w, beam, beam), Vector3(cx_right, y, side_z * bd * 0.5), mat, rng)
			else:
				_add_box("HBeam", Vector3(bw + 0.1, beam, beam), Vector3(0, y, side_z * bd * 0.5), mat, rng)

	# vertical beams at edges and a few intermediate on front & back
	var num_v: int = rng.randi_range(2, 4)
	for i in range(num_v):
		var t: float = float(i) / float(num_v - 1) if num_v > 1 else 0.5
		var x: float = lerp(-bw * 0.45, bw * 0.45, t)
		for side_z in [-1.0, 1.0]:
			# On front face skip any vertical beam that would cross through the door
			if side_z > 0.0 and door_clear_hw > 0.0 and abs(x) < door_clear_hw:
				continue
			_add_box("VBeam", Vector3(beam, bh, beam), Vector3(x, y_base + bh * 0.5, side_z * bd * 0.5), mat, rng)

	# diagonal cross beams (X pattern) on front face — only outside the door zone
	if rng.randf() < 0.5:
		for side_z in [-1.0, 1.0]:
			for dx in [-1.0, 1.0]:
				# Only draw if the beam's centre X is outside the door clear zone
				var cx: float = dx * bw * 0.22
				if side_z > 0.0 and door_clear_hw > 0.0 and abs(cx) < door_clear_hw + 1.0:
					continue
				var xb := BoxMesh.new()
				var diag_len: float = sqrt(bw * bw * 0.16 + bh * bh * 0.09)
				xb.size = Vector3(diag_len, beam, beam)
				xb.material = mat
				var mi := MeshInstance3D.new()
				mi.name = "XBeam"
				mi.mesh = xb
				mi.position = Vector3(cx, y_base + bh * 0.5, side_z * bd * 0.5)
				var angle: float = atan2(bh * 0.33, bw * 0.4) * dx * side_z
				mi.rotation.z = angle
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				_own(mi)

# ── roof styles ───────────────────────────────────────────────────────────
func _add_roof(style: int, bw: float, bd: float, bh: float, fh: float, rh: float, mat: StandardMaterial3D, _r) -> void:
	var y_top: float = fh + bh
	if style == 0:
		# steep gable
		_add_prism("Roof", Vector3(bw + 2.0, rh, bd + 2.5), Vector3(0, y_top + rh * 0.5, 0), mat)
	elif style == 1:
		# hip roof – two overlapping prisms rotated 90°
		_add_prism("RoofA", Vector3(bw + 2.0, rh * 0.9, bd + 2.5), Vector3(0, y_top + rh * 0.45, 0), mat)
		var mi := _add_prism("RoofB", Vector3(bd + 2.0, rh * 0.7, bw + 2.5), Vector3(0, y_top + rh * 0.35, 0), mat)
		mi.rotation.y = PI * 0.5
	else:
		# mansard-ish – lower steep prism + small flat top box
		_add_prism("RoofLow", Vector3(bw + 2.0, rh * 0.6, bd + 2.5), Vector3(0, y_top + rh * 0.3, 0), mat)
		_add_box("RoofFlat", Vector3(bw * 0.5, 0.6, bd * 0.6), Vector3(0, y_top + rh * 0.6 + 0.3, 0), mat, _r)

# ── doors — internal helpers that take pre-computed dw/dh ─────────────────
func _add_simple_door_dims(bd: float, fh: float, mat: StandardMaterial3D, rng: RandomNumberGenerator, dw: float, dh: float) -> void:
	var z_pos: float = bd * 0.5 + 0.15
	_add_box("Door", Vector3(dw, dh, 0.3), Vector3(0, fh + dh * 0.5, z_pos), mat, rng)
	var frame_w: float = 0.5
	_add_box("DoorFrameL", Vector3(frame_w, dh + 0.5, 0.5), Vector3(-dw * 0.5 - frame_w * 0.5, fh + dh * 0.5, z_pos), mat, rng)
	_add_box("DoorFrameR", Vector3(frame_w, dh + 0.5, 0.5), Vector3( dw * 0.5 + frame_w * 0.5, fh + dh * 0.5, z_pos), mat, rng)
	_add_box("DoorFrameT", Vector3(dw + frame_w * 2.0 + 0.3, 0.5, 0.5), Vector3(0, fh + dh + 0.25, z_pos), mat, rng)

func _add_arched_door_dims(bd: float, _bh: float, fh: float, trim_mat: StandardMaterial3D, stone_mat: StandardMaterial3D, rng: RandomNumberGenerator, dw: float, dh: float) -> void:
	var z_pos: float = bd * 0.5 + 0.15
	_add_box("Door", Vector3(dw, dh, 0.3), Vector3(0, fh + dh * 0.5, z_pos), trim_mat, rng)
	var arch := CylinderMesh.new()
	arch.top_radius = dw * 0.5 + 0.4
	arch.bottom_radius = dw * 0.5 + 0.4
	arch.height = 0.6
	arch.radial_segments = 16
	arch.material = stone_mat
	var ami := MeshInstance3D.new()
	ami.name = "DoorArch"
	ami.mesh = arch
	ami.position = Vector3(0, fh + dh + 0.3, z_pos)
	ami.rotation.x = PI * 0.5
	ami.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_own(ami)
	for sx in [-1.0, 1.0]:
		_add_box("DoorPillar", Vector3(0.8, dh + 0.8, 0.8), Vector3(sx * (dw * 0.5 + 0.6), fh + (dh + 0.8) * 0.5, z_pos), stone_mat, rng)

# ── windows ───────────────────────────────────────────────────────────────
# door_clear_hw: X-half-width of door area that must stay clear on the front face.
# Front windows are placed one per side, centred in the gap between
# door edge (door_clear_hw) and wall edge (bw * 0.5).
func _add_windows(bw: float, bd: float, bh: float, fh: float, mat: StandardMaterial3D, rng: RandomNumberGenerator, door_clear_hw: float = 0.0) -> void:
	var wy: float = fh + bh * 0.55
	var ww: float = rng.randf_range(2.0, 3.0)
	var wh: float = min(rng.randf_range(2.5, 3.5), bh * 0.5)
	var idx := 0

	# Front face: one window on each side of the door, centred in the available gap.
	# Available gap on each side: from door_clear_hw to bw*0.5 (wall edge).
	var wall_half: float = bw * 0.5
	var gap: float = wall_half - door_clear_hw   # space on each side
	if gap >= ww + 1.0:   # only place if there is comfortable room
		for side in [-1.0, 1.0]:
			# Centre of the gap on this side
			var cx: float = side * (door_clear_hw + gap * 0.5)
			# Make sure window doesn't poke outside the wall
			cx = clampf(cx, -(wall_half - ww * 0.5 - 0.2), wall_half - ww * 0.5 - 0.2)
			_add_box("Win" + str(idx), Vector3(ww, wh, 0.3), Vector3(cx, wy, bd * 0.5 + 0.15), mat, rng)
			_add_box("Sill" + str(idx), Vector3(ww + 0.6, 0.3, 0.5), Vector3(cx, wy - wh * 0.5 - 0.15, bd * 0.5 + 0.25), mat, rng)
			idx += 1

	# Side windows
	for side_x in [-1.0, 1.0]:
		var n_side: int = rng.randi_range(1, 2)
		for i in range(n_side):
			var t2: float = float(i) / float(n_side) if n_side > 1 else 0.5
			var z: float = lerp(-bd * 0.3, bd * 0.3, t2)
			_add_box("Win" + str(idx), Vector3(0.3, wh, ww), Vector3(side_x * (bw * 0.5 + 0.15), wy, z), mat, rng)
			_add_box("SideSill" + str(idx), Vector3(0.5, 0.3, ww + 0.6), Vector3(side_x * (bw * 0.5 + 0.25), wy - wh * 0.5 - 0.15, z), mat, rng)
			idx += 1

# ── columns / porch ──────────────────────────────────────────────────────
func _add_columns(bw: float, bd: float, bh: float, fh: float, stone_mat: StandardMaterial3D, wood_mat: StandardMaterial3D, rng: RandomNumberGenerator) -> void:
	var col_h: float = bh * 0.8
	var porch_depth: float = rng.randf_range(3.5, 5.5)
	var z_front: float = bd * 0.5 + porch_depth
	var n_cols: int = rng.randi_range(2, 4)
	for i in range(n_cols):
		var t: float = float(i) / float(n_cols - 1) if n_cols > 1 else 0.5
		var x: float = lerp(-bw * 0.45, bw * 0.45, t)
		_add_cylinder("Col" + str(i), 0.5, col_h, Vector3(x, fh + col_h * 0.5, z_front), stone_mat, 8)
		_add_cylinder("Cap" + str(i), 0.8, 0.5, Vector3(x, fh + col_h + 0.25, z_front), stone_mat, 8)
		_add_box("ColBase" + str(i), Vector3(1.2, 0.5, 1.2), Vector3(x, fh + 0.25, z_front), stone_mat, rng)
	_add_box("PorchBeam", Vector3(bw + 1.0, 0.6, porch_depth + 0.5), Vector3(0, fh + col_h + 0.6, bd * 0.5 + porch_depth * 0.5), wood_mat, rng)

# ── chimney ───────────────────────────────────────────────────────────────
func _add_chimney(bw: float, _bd: float, bh: float, fh: float, rh: float, mat: StandardMaterial3D, rng: RandomNumberGenerator) -> void:
	var cw: float = rng.randf_range(1.5, 2.5)
	var ch: float = bh + rh + rng.randf_range(2.0, 5.0)
	var cx: float = rng.randf_range(-bw * 0.3, bw * 0.3)
	_add_box("Chimney", Vector3(cw, ch, cw), Vector3(cx, fh + ch * 0.5, 0), mat, rng)
	_add_box("ChimneyCap", Vector3(cw + 0.8, 0.5, cw + 0.8), Vector3(cx, fh + ch + 0.25, 0), mat, rng)

# ── L-shaped annex ────────────────────────────────────────────────────────
func _add_l_annex(bw: float, bd: float, bh: float, fh: float, wall_mat: StandardMaterial3D, roof_mat: StandardMaterial3D, timber_mat: StandardMaterial3D, half_timber: bool, rng: RandomNumberGenerator) -> void:
	var aw: float = rng.randf_range(8.0, bw * 0.55)
	var ad: float = rng.randf_range(8.0, 14.0)
	var ah: float = bh * rng.randf_range(0.7, 1.0)
	var arh: float = rng.randf_range(4.0, 8.0)
	var side: float = [-1.0, 1.0][rng.randi() % 2]
	var ox: float = side * (bw * 0.5 + aw * 0.5)
	_add_box("AnnexWalls", Vector3(aw, ah, ad), Vector3(ox, fh + ah * 0.5, -bd * 0.5 + ad * 0.5 - 1.0), wall_mat, rng)
	_add_prism("AnnexRoof", Vector3(aw + 1.0, arh, ad + 1.5), Vector3(ox, fh + ah + arh * 0.5, -bd * 0.5 + ad * 0.5 - 1.0), roof_mat)
	if half_timber:
		for frac in [0.33, 0.66]:
			_add_box("AnnBeam", Vector3(aw, 0.4, 0.4), Vector3(ox, fh + ah * frac, -bd * 0.5 - 1.0 + ad), timber_mat, rng)

# ── tower annex ───────────────────────────────────────────────────────────
func _add_tower(bw: float, bd: float, bh: float, fh: float, stone_mat: StandardMaterial3D, roof_mat: StandardMaterial3D, rng: RandomNumberGenerator) -> void:
	var tower_r: float = rng.randf_range(3.5, 6.0)
	var th: float = bh * rng.randf_range(1.3, 2.0)
	var side: float = [-1.0, 1.0][rng.randi() % 2]
	var tx: float = side * (bw * 0.5 + tower_r * 0.6)
	var tz: float = rng.randf_range(-bd * 0.3, bd * 0.3)
	_add_cylinder("Tower", tower_r, th, Vector3(tx, fh + th * 0.5, tz), stone_mat, 16)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = tower_r + 1.0
	cone.height = rng.randf_range(5.0, 10.0)
	cone.radial_segments = 16
	cone.material = roof_mat
	var cmi := MeshInstance3D.new()
	cmi.name = "TowerRoof"
	cmi.mesh = cone
	cmi.position = Vector3(tx, fh + th + cone.height * 0.5, tz)
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_own(cmi)
	for ay in [0.3, 0.6]:
		var wy: float = fh + th * ay
		_add_box("ArrowSlit", Vector3(0.4, 2.0, tower_r + 1.0), Vector3(tx, wy, tz), stone_mat, rng)

# ── second storey ─────────────────────────────────────────────────────────
func _add_second_storey(bw: float, bd: float, bh: float, fh: float, rh: float, wall_mat: StandardMaterial3D, timber_mat: StandardMaterial3D, roof_mat: StandardMaterial3D, rng: RandomNumberGenerator) -> void:
	var s2h: float = bh * rng.randf_range(0.6, 0.8)
	var overhang: float = rng.randf_range(0.8, 2.0)
	var s2w: float = bw + overhang * 2.0
	var s2d: float = bd + overhang * 2.0
	var y2: float = fh + bh
	_add_box("Floor2", Vector3(s2w, s2h, s2d), Vector3(0, y2 + s2h * 0.5, 0), wall_mat, rng)
	for frac in [0.5]:
		for sz in [-1.0, 1.0]:
			_add_box("F2Beam", Vector3(s2w + 0.1, 0.4, 0.4), Vector3(0, y2 + s2h * frac, sz * s2d * 0.5), timber_mat, rng)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box("Bracket", Vector3(0.5, overhang, 0.5), Vector3(sx * bw * 0.4, y2 - overhang * 0.3, sz * bd * 0.5), timber_mat, rng)
	var r2h: float = rh * rng.randf_range(0.8, 1.2)
	_add_prism("Roof2", Vector3(s2w + 1.5, r2h, s2d + 2.0), Vector3(0, y2 + s2h + r2h * 0.5, 0), roof_mat)
	var wy2: float = y2 + s2h * 0.5
	for sx in [-1.0, 1.0]:
		_add_box("F2Win", Vector3(2.2, 2.5, 0.3), Vector3(sx * s2w * 0.25, wy2, s2d * 0.5 + 0.15), timber_mat, rng)


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _own(node: Node) -> void:
	add_child(node)
	if Engine.is_editor_hint() and get_tree() != null:
		var root = get_tree().edited_scene_root
		if root:
			node.owner = root

func _mat(col: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = roughness
	m.metallic = metallic
	return m

func _vary(c: Color, rng: RandomNumberGenerator) -> Color:
	var v := 0.01
	return Color(
		clampf(c.r + rng.randf_range(-v, v), 0.0, 1.0),
		clampf(c.g + rng.randf_range(-v, v), 0.0, 1.0),
		clampf(c.b + rng.randf_range(-v, v), 0.0, 1.0),
		1.0)
