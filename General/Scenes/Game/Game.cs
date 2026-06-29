using Godot;
using GroundDemo.Ground;
using GroundDemo.Mob;
using GroundDemo.UI;

namespace GroundDemo.General.Scenes.Game;

public partial class Game : Node3D
{
	private GroundManager _ground = null!;
	private UiManager _ui = null!;
	private MobManager _mob = null!;
	private Environment.EnvironmentManager _env = null!;
	private bool _isStartupDone;
	
	public override async void _Ready()
	{
		if (Engine.IsEditorHint())
		{
			return;
		}
		_ground = GetNode<GroundManager>("Ground");
		_ui = GetNode<UiManager>("UI");
		_mob = GetNode<MobManager>("Mob");
		_env = GetNode<Environment.EnvironmentManager>("Environment");

		_ui.Init(_mob.Player, _ground);
		_mob.Init(_ground);
		_ground.Init(_mob.Player, _mob.Npc);
		_env.Init(_mob.Player);

		// wait one frame
		await ToSignal(GetTree(), "process_frame");
	}
	
	public override void _Process(double delta)
	{
		if (Engine.IsEditorHint())
		{
			return;
		}

		Vector2I playerChunkLoc = _mob.PlayerChunkLoc;
		if (_isStartupDone)
		{
			LoadedTick(playerChunkLoc, (float)delta);
		}
		else
		{
			UnloadedTick(playerChunkLoc, (float)delta);
		}
	}

	private void LoadedTick(Vector2I playerChunkLoc, float delta)
	{
		_ground.LoadedTick(playerChunkLoc, delta);
		_ui.LoadedTick(playerChunkLoc);
		_env.LoadedTick();
	}

	private void UnloadedTick(Vector2I playerChunkLoc, float delta)
	{
		_ground.UnloadedTick(playerChunkLoc, delta);
		var loadStatus = $"{_ground.GetLoadStatus}\n{_mob.LoadStatus}";
		_ui.UnloadedTick(loadStatus);
		CheckStartup(playerChunkLoc);
	}

	private void CheckStartup(Vector2I playerChunkLoc)
	{
		if (!_ground.IsGroundReady(playerChunkLoc)) return;
		_ui.Activate();
		_ground.Activate();
		_mob.Activate();
		_isStartupDone = true;
	}
}
