extends Node3D
class_name EnvironmentManager

# --- Underwater visual signifier (simple) -----------------------------------
const WATER_TINT: Color = Color(0.0, 0.18, 0.33,.5)
const WATER_FOG_COLOR: Color = Color(0.011764706, 0.30588236, 0.5529412, 0.101960786)
const WATER_FOG_DEPTH_END: float = 100.0

var _env: Environment = null
var _orig_bg_color: Color = Color(0,0,0,1)
var _orig_fog_enabled: bool = false
var _orig_fog_color: Color = Color(0,0,0)
var _orig_fog_depth_end: float = 0.0
var is_under_water: bool = false


func init():
	var we: WorldEnvironment = $"WorldEnvironment"
	_env = we.environment
	if _env:
		_orig_bg_color = _env.background_color
		_orig_fog_enabled = _env.fog_enabled
		_orig_fog_color = _env.fog_light_color
		_orig_fog_depth_end = _env.fog_depth_end

func loaded_tick(player_pos:Vector3):
	if player_pos.y < GroundConstants.WATER_SURFACE_LEVEL-1.0:
		if !is_under_water && player_pos.y < GroundConstants.WATER_SURFACE_LEVEL-2.0:
			submerge()
	elif is_under_water:
		surface()

func submerge() -> void:
	_env.fog_enabled = true
	_env.fog_light_color = WATER_FOG_COLOR
	_env.fog_density = 0.001
	is_under_water = true

func surface() -> void:
	_env.fog_enabled = _orig_fog_enabled
	_env.fog_depth_end = _orig_fog_depth_end
	_env.fog_light_color = _orig_fog_color
	get_parent().get_node("Mob/Player").velocity.y = 0
	is_under_water = false
