using Godot;

namespace GroundDemo.Ground.Services.Builders;

[Tool]
public partial class HouseBuilder : Node3D
{
	[Export]
	public bool Generate
	{
		get => _generate;
		set
		{
			_generate = value;
			if (Engine.IsEditorHint() && IsInsideTree())
				Build(this);
		}
	}
	private bool _generate;
	
	// Material constants
	private const float WallRoughness = 0.85f;
	private const float WallMetallic = 0.02f;
	private const float RoofRoughness = 0.90f;
	private const float RoofMetallic = 0.02f;
	private const float StoneRoughness = 0.95f;
	private const float DoorRoughness = 0.90f;

	// Probability constants
	private const float ChimneyChance = 0.6f;
	
	// Dimension constants
	private const float MaxHouseX = 10.0f;
	private const float MaxHouseY = 10.0f;
	private const float MaxHouseZ = 10.0f;
	private const float FoundationY = 5.0f;
	private const float FoundationXz = 0.6f;
	private const float RoofX = 1.0f;
	private const float RoofZ = 1.2f;
	private const float CollisionXz = 1.0f;
	
	private const float DoorX = 1.5f;
	private const float DoorY = 3.0f;
	private const float DoorFrameX = 0.25f;
	private const float DoorZ = 0.25f;
	private const float DoorFrameZ = 0.35f;
	private const float DoorFrameTopY = 0.35f;
	private const float DoorFrameExtraY = 0.4f;
	private const float DoorTopGapY = 0.2f;
	
	private const float ChimneyXz = 0.6f;
	private const float ChimneyCapY = 0.3f;
	private const float ChimneyCapXz = 1.0f;

	private static readonly Color[] WallCols =
	[
		new(0.72f, 0.65f, 0.55f),
		new(0.59f, 0.50f, 0.43f),
		new(0.68f, 0.62f, 0.49f)
	];

	private static readonly Color[] RoofCols =
	[
		new(0.28f, 0.18f, 0.12f),
		new(0.42f, 0.28f, 0.18f),
		new Color(0.35f, 0.32f, 0.28f)
	];

	private static readonly StandardMaterial3D StoneMat = GetMaterial(new Color(0.40f, 0.37f, 0.34f), StoneRoughness, 0.0f);
	private static readonly StandardMaterial3D DoorMat = GetMaterial(new Color(0.12f, 0.06f, 0.03f), DoorRoughness, 0.0f);

	/// Builds a procedural house
	public static void Build(Node3D root)
	{
		// Remove all existing children
		foreach (Node c in root.GetChildren())
		{
			root.RemoveChild(c);
			if (IsInstanceValid(c)) c.Free();
		}

		var rng = new RandomNumberGenerator();
		Vector3 p = root.Position;
		rng.Seed = (ulong)GD.Hash($"{(int)(p.X * 10)}_{(int)(p.Z * 10)}");

		StandardMaterial3D wallMat = GetMaterial(WallCols[rng.RandiRange(0, WallCols.Length - 1)], WallRoughness, WallMetallic);
		StandardMaterial3D roofMat = GetMaterial(RoofCols[rng.RandiRange(0, RoofCols.Length - 1)], RoofRoughness, RoofMetallic);

		float baseX = rng.RandfRange(MaxHouseX * 0.5f, MaxHouseX); // base X dimension
		float baseZ = rng.RandfRange(MaxHouseZ * 0.5f, MaxHouseZ); // base Z dimension
		float wallY = rng.RandfRange(MaxHouseY * 0.5f, MaxHouseY);
		float roofY = rng.RandfRange(MaxHouseY * 0.25f, MaxHouseY * 0.5f);

		AddBox(root,
			"Foundation",
			new Vector3(baseX + FoundationXz, FoundationY, baseZ + FoundationXz),
			new Vector3(0, -FoundationY * 0.5f, 0),
			StoneMat);
		AddBox(root,
			"Walls",
			new Vector3(baseX, wallY, baseZ),
			new Vector3(0, wallY * 0.5f, 0),
			wallMat);
		AddPrism(root,
			"Roof",
			new Vector3(baseX + RoofX, roofY, baseZ + RoofZ),
			new Vector3(0, wallY + roofY * 0.5f, 0),
			roofMat);
		AddDoor(baseZ, root);
		if (rng.Randf() < ChimneyChance)
			AddChimney(rng, baseX, wallY, roofY, root);

		// Collision covering the whole house (including foundation below ground)
		float totalY = FoundationY + wallY + roofY;
		var collisionShape = new BoxShape3D { Size = new Vector3(baseX + CollisionXz, totalY, baseZ + CollisionXz) };
		var collisionNode = new CollisionShape3D
		{
			Name = "Collision",
			Position = new Vector3(0, (wallY + roofY - FoundationY) * 0.5f, 0),
			Shape = collisionShape
		};
		root.AddChild(collisionNode);
	}

	private static void AddDoor(float baseZ, Node3D root)
	{
		float doorZ = baseZ * 0.5f + 0.125f;
		AddBox(root, "Door", new Vector3(DoorX, DoorY, DoorZ), new Vector3(0, DoorY * 0.5f, doorZ), DoorMat);
		// Door frame
		AddBox(root, "DoorFrameL", new Vector3(DoorFrameX, DoorY + DoorFrameExtraY, DoorFrameZ),
			new Vector3(-DoorX * 0.5f - DoorFrameX * 0.5f, DoorY * 0.5f, doorZ), StoneMat);
		AddBox(root, "DoorFrameR", new Vector3(DoorFrameX, DoorY + DoorFrameExtraY, DoorFrameZ),
			new Vector3(DoorX * 0.5f + DoorFrameX * 0.5f, DoorY * 0.5f, doorZ), StoneMat);
		AddBox(root, "DoorFrameT", new Vector3(DoorX + DoorFrameX * 2.0f + DoorTopGapY, DoorFrameTopY, DoorFrameZ), new Vector3(0, DoorY + DoorTopGapY, doorZ),
			StoneMat);
	}

	private static void AddChimney(RandomNumberGenerator rng, float baseX, float wallY, float roofY, Node3D root)
	{
		float chimneyX = rng.RandfRange(-baseX * 0.25f, baseX * 0.25f);
		float chimneyY = wallY + roofY * 0.5f;
		float chimneyCapY = wallY + roofY + ChimneyCapY * 0.5f;

		AddBox(root, "Chimney",
			new Vector3(ChimneyXz, roofY, ChimneyXz),
			new Vector3(chimneyX, chimneyY, 0), StoneMat);
		AddBox(root, "ChimneyCap",
			new Vector3(ChimneyCapXz, ChimneyCapY, ChimneyCapXz),
			new Vector3(chimneyX, chimneyCapY, 0), StoneMat);
	}

	private static void AddBox(Node3D parent, string name, Vector3 size, Vector3 pos, StandardMaterial3D mat)
	{
		var mesh = new BoxMesh { Size = size, Material = mat };
		parent.AddChild(new MeshInstance3D
		{
			Name = name,
			Mesh = mesh,
			Position = pos,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.On
		});
	}

	private static void AddPrism(Node3D parent, string name, Vector3 size, Vector3 pos, StandardMaterial3D mat)
	{
		var mesh = new PrismMesh { Size = size, Material = mat };
		parent.AddChild(new MeshInstance3D
		{
			Name = name,
			Mesh = mesh,
			Position = pos,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.On
		});
	}

	private static StandardMaterial3D GetMaterial(Color col, float roughness, float metallic) =>
		new() { AlbedoColor = col, Roughness = roughness, Metallic = metallic };
}
