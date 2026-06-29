using System;
using Godot;
using GroundDemo.Ground;
using GroundDemo.Mob.Scenes.Mobs.Npc;
using GroundDemo.Mob.Scenes.Mobs.Player;
using GroundDemo.Mob.Services;

namespace GroundDemo.Mob;

public partial class MobManager : Node
{
	public Player Player = null!;
	public Npc Npc = null!;
	private MobActivationManager _mobActivationManager = null!;
	private RuntimeNavigationBaker _navBaker = null!;
	
	public string LoadStatus => $"Navigation ready: {Npc.NavigationReady}";
	public Vector2I PlayerChunkLoc => new(
		(int)MathF.Floor(Player.GlobalPosition.X / GroundConstants.ChunkSize),
		(int)MathF.Floor(Player.GlobalPosition.Z / GroundConstants.ChunkSize)
	);
	
	public override void _Ready()
	{
		Player = GetNodeOrNull<Player>("Player");
		Npc = GetNodeOrNull<Npc>("Npc");
		_navBaker = GetNodeOrNull<RuntimeNavigationBaker>("NavBaker");
	}

	public void Init(GroundManager ground)
	{
		Player.Init();
		_mobActivationManager = new MobActivationManager(Npc, Player, ground);
		_navBaker.Init(Player, _mobActivationManager);
	}

	public void Activate()
	{
		// forward activation to MobActivationManager
		_mobActivationManager.ActivatePlayer();
		_mobActivationManager.ActivateNpc();
	}
}
