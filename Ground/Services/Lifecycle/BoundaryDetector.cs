using Godot;
using GroundDemo.Ground.Scenes;
using GroundDemo.Mob.Scenes.Mobs.Player;

namespace GroundDemo.Ground.Services.Lifecycle;

public partial class BoundaryDetector(Player player) : RefCounted
{
    public void Update(GroundChunk? chunk)
    {
        if (!IsInstanceValid(player))
        {
            return;
        }
        if (chunk is { LodTier: > GroundEnums.LodLevels.Close})
        {
            player.Velocity = Vector3.Zero;
            player.SetPhysicsProcess(false);
        }
        else
        {
            player.SetPhysicsProcess(true);
        }
    }
}

