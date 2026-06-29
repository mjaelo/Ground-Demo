using Godot;
using GroundDemo.Ground;
using GroundDemo.Ground.Scenes;
using GroundDemo.Mob.Scenes.Mobs.Player;

namespace GroundDemo.UI;

public partial class UiManager : Control
{
	private Player _player = null!;
	private GroundManager _ground = null!;
	private Label _infoNode = null!;
	private Control _loadingNode = null!;
	private Label _loadingLabel = null!;
	private Label _dataLabel = null!;

	private int _loadingTicks;
	
	public override void _Ready()
	{
		_infoNode = GetNode<Label>("Label");
		_loadingNode = GetNode<Control>("Loading");
		_loadingLabel = GetNode<Label>("Loading/VBoxContainer/LoadingLabel");
		_dataLabel = GetNode<Label>("Loading/VBoxContainer/DataLabel");
	}
	public void Init(Player player, GroundManager ground)
	{
		_player = player;
		_ground = ground;
		_infoNode.Visible = false;
		_loadingNode.Visible = true;

		RenderingServer.SetDebugGenerateWireframes(true);
		NavigationServer3D.SetDebugEnabled(true);
	}

	public void Activate()
	{
		_loadingNode.Visible = false;
		_infoNode.Visible = true;
	}

	public void UnloadedTick(string status)
	{
		_loadingTicks++;
		var dotsNr = (int)(_loadingTicks / 10.0) % 6;
		var dots = new string('*', dotsNr + 1);
		_loadingLabel.Text = $"Loading\n{dots}";
		_dataLabel.Text = $"FPS: {Engine.GetFramesPerSecond()}\n{status}";
	}

	public void LoadedTick(Vector2I playerChunkLoc)
	{
		// Build the same informational text as in the GDScript implementation
		var loadedText = $"FPS: {Engine.GetFramesPerSecond()}\n" +
						 $"Move Speed: {_player.MoveSpeed:F1}\n" +
						 $"Position: ({(int)_player.GlobalPosition.X}, {(int)_player.GlobalPosition.Y}, {(int)_player.GlobalPosition.Z})\n";

		loadedText +=
			"Player\n" +
			"Move: WASDEQ,Space,Mouse\n" +
			"Move speed: Wheel,+/-,Shift\n" +
			"Camera View: V\n" +
			"Gravity toggle: G\n" +
			"Collision toggle: C\n\n" +
			"Window\n" +
			"Quit: F8\n" +
			"Render mode: F10\n" +
			"Full screen: F11\n" +
			"Mouse toggle: Escape / F12\n";

		// Biome name from ground.biome_manager.get_dominant_biome_at(player.position.x, player.position.z)
		var biome = _ground.BiomeManager.GetDominantBiomeAt(_player.GlobalPosition.X, _player.GlobalPosition.Z);

		// decor spawned - check chunk dictionary
		bool decorSpawned = false;
		if (_ground.ChunkManager.Chunks.TryGetValue(playerChunkLoc, out GroundChunk? chunk))
		{
			decorSpawned = chunk.AreDecorsSpawned;
		}

		loadedText += $"Chunk\nBiome: {biome.BiomeName}\nLoc: {playerChunkLoc}\nDecor Spawned: {decorSpawned}\n";

		_infoNode.Text = loadedText;
	}

	public override void _UnhandledKeyInput(InputEvent pEvent)
	{
		if (pEvent is not InputEventKey { Pressed: true } key) return;

		switch (key.Keycode)
		{
			case Key.F8:
				GetTree().Quit();
				break;
			case Key.F10:
				var vp = GetViewport();
				vp.DebugDraw = (Viewport.DebugDrawEnum)(((int)vp.DebugDraw + 1) % 6);
				GetViewport().SetInputAsHandled();
				break;
			case Key.F11:
				ToggleFullscreen();
				GetViewport().SetInputAsHandled();
				break;
			case Key.Escape or Key.F12:
				Input.MouseMode = Input.MouseMode == Input.MouseModeEnum.Visible
					? Input.MouseModeEnum.Captured
					: Input.MouseModeEnum.Visible;
				GetViewport().SetInputAsHandled();
				break;
		}
	}

	private static void ToggleFullscreen()
	{
		var mode = DisplayServer.WindowGetMode();
		if (mode is DisplayServer.WindowMode.ExclusiveFullscreen or DisplayServer.WindowMode.Fullscreen)
		{
			DisplayServer.WindowSetMode(DisplayServer.WindowMode.Windowed);
			DisplayServer.WindowSetSize(new Vector2I(1280, 720));
		}
		else
		{
			DisplayServer.WindowSetMode(DisplayServer.WindowMode.ExclusiveFullscreen);
		}
	}
}
