using Godot;
using GroundDemo.Ground;
using GroundDemo.Mob.Scenes.Mobs.Player;

namespace GroundDemo.General.Scenes.Environment;

public partial class EnvironmentManager : Node3D
{
	private static readonly Color WaterFogColor = new Color(0.011764706f, 0.30588236f, 0.5529412f, 0.101960786f);

	private Godot.Environment _env = null!;
	private Player _player = null!;
	private Color _origBgColor = new Color(0f, 0f, 0f);
	private bool _origFogEnabled;
	private Color _origFogColor = new Color(0f, 0f, 0f);
	private float _origFogDepthEnd;
	private bool _isUnderWater;

	private const float SurfaceLevel = GroundConstants.WaterSurfaceLevel - 1.0f;
	private const float SubmergeLevel = GroundConstants.WaterSurfaceLevel - 2.0f;

	public void Init(Player player)
	{
		_player = player;
		WorldEnvironment we = GetNodeOrNull<WorldEnvironment>("WorldEnvironment");
		if (we?.Environment == null)
		{
			return;
		}

		_env = we.Environment;
		_origBgColor = _env.BackgroundColor;
		_origFogEnabled = _env.FogEnabled;
		_origFogColor = _env.FogLightColor;
		_origFogDepthEnd = _env.FogDepthEnd;
	}

	public void LoadedTick()
	{
		var playerY = _player.GlobalPosition.Y;
		if (_isUnderWater)
		{
			if (playerY >= SurfaceLevel)
				Surface();
		}
		else if (playerY < SubmergeLevel) {
			Submerge();
		}
	}

	private void Submerge()
	{
		_env.FogEnabled = true;
		_env.FogLightColor = WaterFogColor;
		_env.FogDensity = 0.001f;
		_isUnderWater = true;
	}

	private void Surface()
	{
		_env.FogEnabled = _origFogEnabled;
		_env.FogDepthEnd = _origFogDepthEnd;
		_env.FogLightColor = _origFogColor;
		_player.Velocity = _player.Velocity with { Y = 0f };
		_isUnderWater = false;
	}
}
