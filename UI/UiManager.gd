extends Control
class_name UiManager

var player: Player
var ground: GroundManager
@onready var info_node := $Label
@onready var loading_node := $Loading
@onready var loading_label := $Loading/VBoxContainer/LoadingLabel
@onready var data_label := $Loading/VBoxContainer/DataLabel

var loading_ticks: int = 0

func init(_player:Player, _ground:GroundManager) -> void:
	player = _player
	ground = _ground
	RenderingServer.set_debug_generate_wireframes(true)
	NavigationServer3D.set_debug_enabled(true)
	
	loading_node.visible = true
	info_node.visible = false

func loaded_tick(player_chunk_loc: Vector2i) -> void:
	var loaded_text := """FPS: %d
			Move Speed: %.1f
			Position: %.1v
			""" % [Engine.get_frames_per_second(), player.MOVE_SPEED, player.global_position]
	loaded_text += """
			Player
			Move: WASDEQ,Space,Mouse
			Move speed: Wheel,+/-,Shift
			Camera View: V
			Gravity toggle: G
			Collision toggle: C

			Window
			Quit: F8
			Render mode: F10
			Full screen: F11
			Mouse toggle: Escape / F12
			"""
	var biome_name := ground.biome_manager.get_dominant_biome_at(player.position.x, player.position.z).biome_name
	var decor_spawned:bool = ground.chunk_manager.chunks.get(player_chunk_loc).are_decors_spawned
	loaded_text += """
			Chunk
			Biome: %s
			Loc: %s
			Decor Spawned: %s
			""" % [biome_name, player_chunk_loc, decor_spawned]
	info_node.text = loaded_text

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

#  Input 
func _unhandled_key_input(p_event: InputEvent) -> void:
	if p_event is InputEventKey and p_event.pressed:
		match p_event.keycode:
			KEY_F8:
				get_tree().quit()
			KEY_F10:
				var vp := get_viewport()
				vp.debug_draw = (vp.debug_draw + 1 ) % 6 as Viewport.DebugDraw
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
