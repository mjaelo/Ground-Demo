using System.Collections.Generic;
using Godot;
using GroundDemo.Ground.Services.Builders;
using GroundDemo.Ground.Services.Mangers;

namespace GroundDemo.Ground.Services.Lifecycle;

[Tool]
public partial class EditorPreview : Node
{
	private GroundManager _parent = null!;

	[ExportGroup("Editor Preview")]
	[Export(PropertyHint.Range, "1,10")]
	public int EditorPreviewRadius { get; set; } = 1;
	[Export] public int EditorBiome { get; set; } // 0=None, 1=Plains, 2=Mountain, 3=Village, 4=Lake
	[Export] public bool GenerateInEditor
	{
		get => _generateInEditor;
		set
		{
			_generateInEditor = value;
			if (Engine.IsEditorHint() && IsInsideTree())
			{
				if (value) EditorGenerate();
				else EditorClear();
			}
		}
	}
	private bool _generateInEditor;

	public override void _Ready()
	{
		_parent = GetParent<GroundManager>();
		_parent.Init(null!, null!);
	}

	private void EditorGenerate()
	{
		_Ready();
		EditorClear();

		GD.Print("Starting Editor Generate...");

		// Force a specific biome by zeroing the others' size
		if (EditorBiome > 0)
		{
			for (int i = 0; i < _parent.BiomeManager.Biomes.Count; i++)
				if (i != EditorBiome - 1)
					_parent.BiomeManager.Biomes[i].BiomeSize = 0;
		}

		ChunkManager generator = _parent.ChunkManager;
		int r = EditorPreviewRadius;
		int total = (2 * r + 1) * (2 * r + 1);

		for (int rx = -r; rx <= r; rx++)
		{
			for (int ry = -r; ry <= r; ry++)
			{
				var loc = new Vector2I(rx, ry);
				var threadRes = generator.GetChunkThreadResult(loc, GroundEnums.LodLevels.Close);
				var chunk = ChunkBuilder.BuildChunk(threadRes.ChunkData, GroundEnums.LodLevels.Close);
				chunk.Name = $"EditorChunk_{rx}_{ry}";
				GetNode("../Chunks").AddChild(chunk);
				chunk.Owner = GetTree().EditedSceneRoot;

				if (_parent.DecorManager != null)
				{
					GD.Print("starting decors ",_parent.DecorManager.DecorInfos.Count);
					float cs = GroundConstants.ChunkSize;
					var chunkCenter = new Vector3(loc.X * cs + cs * 0.5f, 0, loc.Y * cs + cs * 0.5f);
					for (int i = 0; i < _parent.DecorManager.DecorInfos.Count; i++)
					{
						var decorD = _parent.DecorManager.DecorInfos[i];
						var decRes = _parent.DecorManager.GetDecorThreadResult(chunkCenter, [], decorD, i, loc);
						GD.Print("decor results colleted: ", decRes.DecorTransforms.Count);
						if (decRes.DecorTransforms.Count > 0)
						{
							Node3D[] nodes = _parent.DecorManager.GetDecorMeshes(decorD, decRes.DecorTransforms);
							GD.Print("decors count: ", nodes.Length);
							foreach (Node3D node in nodes)
								chunk.GetNode<Node3D>("Decors").AddChild(node);
							chunk.DecorNodes.AddRange(nodes);
						}
					}
				}
			}
		}
		GD.Print($"[EditorGen] Done! {total} chunks.");
	}

	private void EditorClear()
	{
		Node chunksNode = GetNode("../Chunks");
		foreach (Node child in chunksNode.GetChildren())
			child.QueueFree();
		_parent.Init(null!, null!);
		GD.Print("[EditorGen] Cleared preview chunks.");
	}
}
