using Godot;

namespace GroundDemo.UI.Menu;

public partial class Menu : Control
{
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		// Connect button signals
		GetNode<Button>("VBoxContainer/Start").Pressed += OnStartPressed;
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	private void OnStartPressed()
	{
		// Load Creator scene
		var gameScene = GD.Load<PackedScene>("res://General/Scenes/Game/game.tscn");
		var gameInstance = gameScene.Instantiate();

		// Add to parent
		GetParent().AddChild(gameInstance);
		
		// Remove Menu scene from memory
		QueueFree();
	}
}
