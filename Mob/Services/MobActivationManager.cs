using Godot;
using GroundDemo.Ground;
using GroundDemo.Mob.Scenes.Mobs.Player;

namespace GroundDemo.Mob.Services;

public partial class MobActivationManager : RefCounted
{
    Scenes.Mobs.Npc.Npc _npc = null!;
    Player _player = null!;
    private GroundManager _parent = null!;
    public bool IsNpcActivated;
    public bool IsPlayerActivated;
    private const float SpawnGroundDist = 5.0f;

    public MobActivationManager(Scenes.Mobs.Npc.Npc npc, Player player, GroundManager parentManager)
    {
        _parent = parentManager;
        _npc = npc;
        _player = player;
        
        _npc.SetProcess(false);
        _npc.SetPhysicsProcess(false);
        _player.SetPhysicsProcess(false);
    }
    
    
    public void ActivatePlayer()
    {
        if (IsPlayerActivated) return;
        
        _player.GlobalTransform = GetSpawnTransform(_player.GlobalTransform);
        _player.SetGravityEnabled(true);
        _player.SetCollisionEnabled(true);
        _player.SetPhysicsProcess(true);
        IsPlayerActivated = true;
    }

    public void ActivateNpc()
    {
        if (IsNpcActivated) return;

        _npc.GlobalTransform = GetSpawnTransform(_npc.GlobalTransform);
        _npc.Target = _player;
        _npc.SetProcess(true);
        _npc.SetPhysicsProcess(true);
        IsNpcActivated = true;
    }
    
    private Transform3D GetSpawnTransform(Transform3D plTransform)
    {
        float heightAtPlayer = _parent.ChunkManager.GetHeightAt(plTransform.Origin);
        plTransform.Origin.Y = heightAtPlayer + SpawnGroundDist;
        return plTransform;
    }

    public void OnNavBakeFinished()
    {
        _npc.NavigationReady = true;
    }
}

