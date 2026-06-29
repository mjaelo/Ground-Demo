using System;
using Godot;
using GroundDemo.Ground;
using GroundDemo.Mob.Scenes.Mobs.Player;

namespace GroundDemo.Mob.Services;

public partial class RuntimeNavigationBaker : Node
{
	private const float AgentHeight = 2.0f;
	private const float AgentMaxSlopeDegrees = 45.0f;
	private const float MergeRasterizerCellScale = 0.0625f;

	private Player _player = null!;
	private MobActivationManager _activationManager = null!;
	private Vector3 _currentCenter = new(float.PositiveInfinity, float.PositiveInfinity, float.PositiveInfinity);
	private bool _bakeInFlight;
	private float _bakeCooldownTimer;

	private readonly NavigationMesh _template = new()
	{
		GeometryParsedGeometryType = NavigationMesh.ParsedGeometryType.StaticColliders,
		GeometrySourceGeometryMode = NavigationMesh.SourceGeometryMode.RootNodeChildren,
		CellSize = GroundConstants.NavCellSize,
		CellHeight = GroundConstants.NavCellHeight,
		AgentHeight = AgentHeight,
		AgentRadius = GroundConstants.NavCellSize,
		AgentMaxClimb = GroundConstants.NavCellHeight,
		AgentMaxSlope = AgentMaxSlopeDegrees
	};

	private readonly NavigationRegion3D _navRegion = new()
	{
		NavigationLayers = 1,
		EnterCost = 0.0f,
		TravelCost = 1.0f,
		UseEdgeConnections = false
	};

	public override void _Ready()
	{
		AddChild(_navRegion);
		Rid map = GetViewport().FindWorld3D().NavigationMap;
		NavigationServer3D.MapSetCellSize(map, _template.CellSize);
		NavigationServer3D.MapSetCellHeight(map, _template.CellHeight);
		NavigationServer3D.MapSetMergeRasterizerCellScale(map, MergeRasterizerCellScale);
	}

	public void Init(Player player, MobActivationManager activationManager)
	{
		_player = player;
		_activationManager = activationManager;
	}

	public override void _Process(double delta)
	{
		if (_bakeInFlight) return;
		if (_bakeCooldownTimer > 0.0f)
		{
			_bakeCooldownTimer -= (float)delta;
			return;
		}

		var trackPos = _player.GlobalPosition;
		const float snap = GroundConstants.ChunkSize * 0.5f;
		Vector3 snappedCenter = new(
			MathF.Round(trackPos.X / snap) * snap,
			trackPos.Y,
			MathF.Round(trackPos.Z / snap) * snap
		);

		var dx = snappedCenter.X - _currentCenter.X;
		var dz = snappedCenter.Z - _currentCenter.Z;
		if (dx * dx + dz * dz >= GroundConstants.MinRebaseDist * GroundConstants.MinRebaseDist)
		{
			_currentCenter = snappedCenter;
			_rebake(_currentCenter);
		}
	}

	private void _rebake(Vector3 center)
	{
		var sourceGeometry = new NavigationMeshSourceGeometryData3D();
		NavigationServer3D.ParseSourceGeometryData(_template, sourceGeometry, GetParent() ?? this);

		_bakeInFlight = true;
		_bakeCooldownTimer = GroundConstants.BakeCooldown;

		if (!sourceGeometry.HasData())
		{
			_finish_bake(null);
			return;
		}

		const float r = GroundConstants.NavBakeRadius;
		const float h = GroundConstants.NavBakeHeight;
		_template.FilterBakingAabb = new Aabb(new Vector3(-r, -h * 0.5f, -r), new Vector3(r * 2.0f, h, r * 2.0f));
		_template.FilterBakingAabbOffset = center;

		var navMesh = _template;
		NavigationServer3D.BakeFromSourceGeometryDataAsync(
			navMesh,
			sourceGeometry,
			Callable.From(() => CallDeferred(nameof(_finish_bake), navMesh))
		);
	}

	public void _finish_bake(NavigationMesh? navMesh)
	{
		_bakeInFlight = false;
		if (navMesh != null) _navRegion.NavigationMesh = navMesh;
		_activationManager.OnNavBakeFinished();
	}
}
