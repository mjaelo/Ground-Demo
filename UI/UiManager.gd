extends Control
class_name UiManager

var player: Player
var visible_mode: int = 1
@onready var info_node := $Label
@onready var loading_node := $Loading
@onready var loading_label := $Loading/VBoxContainer/LoadingLabel
@onready var data_label := $Loading/VBoxContainer/DataLabel

var loading_ticks: int = 0

func init(_player:Player) -> void:
	player = _player
	RenderingServer.set_debug_generate_wireframes(true)
	NavigationServer3D.set_debug_enabled(true)
	
	loading_node.visible = true
	info_node.visible = false

func loaded_tick() -> void:
	info_node.text = "FPS: %d\n" % Engine.get_frames_per_second()
	if(visible_mode == 1):
		info_node.text += "Move Speed: %.1f\n" % player.MOVE_SPEED if player else ""
		if player:
			info_node.text += "Position: %.1v\n" % player.global_position
		info_node.text += """
			Player
			Move: WASDEQ,Space,Mouse
			Move speed: Wheel,+/-,Shift
			Camera View: V
			Gravity toggle: G
			Collision toggle: C

			Window
			Quit: F8
			UI toggle: F9
			Render mode: F10
			Full screen: F11
			Mouse toggle: Escape / F12
			"""

func unloaded_tick(status:String) -> void:
	loading_ticks += 1
	var dots_nr := int(loading_ticks / 10.0) % 6
	var dots := '*'
	for nr in dots_nr:
		dots+='*'
	var fps_text :=  "FPS: %d\n" % Engine.get_frames_per_second()
	loading_label.text = "Loading\n" + str(dots)
	data_label.text = fps_text+status

func activate() -> void:
	loading_node.visible = false
	info_node.visible = true

# ── Input ────────────────────────────────────────────────────────────── TODO clean up
func _unhandled_key_input(p_event: InputEvent) -> void:
	if p_event is InputEventKey and p_event.pressed:
		match p_event.keycode:
			KEY_F8:
				get_tree().quit()
			KEY_F9:
				visible_mode = (visible_mode + 1 ) % 3
				info_node.visible = (visible_mode == 1)
				visible = visible_mode > 0
			KEY_F10:
				var vp = get_viewport()
				vp.debug_draw = (vp.debug_draw + 1 ) % 6
				get_viewport().set_input_as_handled()
			KEY_F11:
				toggle_fullscreen()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE, KEY_F12:
				if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				else:
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				get_viewport().set_input_as_handled()
		
func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or \
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2(1280, 720))
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
