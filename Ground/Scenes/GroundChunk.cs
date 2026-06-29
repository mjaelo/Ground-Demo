using System.Collections.Generic;
using Godot;
using GroundDemo.Ground.GroundDatas;

namespace GroundDemo.Ground.Scenes;

/// Scene script for a terrain chunk.
[GlobalClass]
[Tool]
public partial class GroundChunk : Node3D
{
	public required ChunkData Data { get; set; }
	public required MeshInstance3D MeshInstance { get; set; }
	public StaticBody3D? CollisionBody { get; set; }
	public List<Node3D> DecorNodes { get; set; } = []; // Node Array of decors in the chunks
	public bool AreDecorsSpawned { get; set; }
	public GroundEnums.LodLevels LodTier { get; set; } = GroundEnums.LodLevels.Far; // LOD tier used to generate this chunk.
	public HashSet<Vector2I> Blocked { get; set; } = []; // chunk x,z points blocked by placed decors
	public MeshInstance3D? Water { get; set; }
}
