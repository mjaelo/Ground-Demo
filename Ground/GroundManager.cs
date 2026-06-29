using Godot;
using GroundDemo.Ground.Scenes;
using GroundDemo.Ground.Services.Mangers;
using GroundDemo.Ground.Services.Lifecycle;
using GroundDemo.Mob.Scenes.Mobs.Npc;
using GroundDemo.Mob.Scenes.Mobs.Player;

namespace GroundDemo.Ground;

[Tool]
public partial class GroundManager : Node
{
	// Node references
	private Player _player = null!;
	private Npc _npc = null!;
	public Camera3D Camera = null!;

	// Managers
	public DecorManager DecorManager = null!;
	public BiomeManager BiomeManager = null!;
	public ChunkManager ChunkManager = null!;
	public GroundThreadManager GroundThreadManager = null!;
	private BoundaryDetector _boundaryDetector = null!;

	// State counters
	private int _spawnedChunksNr;
	private int _decorChunksNr;
	private int _totalChunkNr;
	private bool _isGroundStartupDone;
	public bool IsGroundStartupDone => _isGroundStartupDone;
	private float _chunkCleanTimer;
	
	public string GetLoadStatus => $"Chunks: {_spawnedChunksNr,2} / {_totalChunkNr,2}\nDecor:  {_decorChunksNr,2} / {_totalChunkNr,2}";

	public void Init(Player? player, Npc? enemy)
	{
		BiomeManager = new BiomeManager();
		DecorManager = new DecorManager(this);
		GroundThreadManager = new GroundThreadManager(this);
		ChunkManager = new ChunkManager(this);

		if (player == null || enemy == null) return;
		_boundaryDetector = new BoundaryDetector(player);
		_player = player;
		_npc = enemy;
		Camera = player.GetNode<Camera3D>("%Camera3D");
	}

	public void UnloadedTick(Vector2I playerChunkLoc, float delta = 0.016f)
	{
		GroundThreadManager.HandleThreads(playerChunkLoc, delta);
		_chunkCleanTimer += delta;
		if (!(_chunkCleanTimer >= GroundConstants.ChunkCleanInterval)) return;
		_chunkCleanTimer = 0.0f;
		ChunkManager.UpdateDistantChunks(playerChunkLoc);
	}

	public void LoadedTick(Vector2I playerChunkLoc, float delta = 0.016f)
	{
		// Call ground thread handling and chunk cleaning
		GroundThreadManager.HandleThreads(playerChunkLoc, delta);
		_chunkCleanTimer += delta;
		if (!ChunkManager.Chunks.TryGetValue(playerChunkLoc, out GroundChunk? chunk)) return;
		_boundaryDetector.Update(chunk);
		if (!(_chunkCleanTimer >= GroundConstants.ChunkCleanInterval)) return;
		_chunkCleanTimer = 0.0f;
		ChunkManager.UpdateDistantChunks(playerChunkLoc);
	}

	public bool IsGroundReady(Vector2I playerLoc)
	{
		const int cr = GroundConstants.StartupRadius;
		_decorChunksNr = 0;
		_spawnedChunksNr = 0;
		_totalChunkNr = 0;
		bool isReady = true;
		for (int x = playerLoc.X - cr; x <= playerLoc.X + cr; x++)
		{
			for (int y = playerLoc.Y - cr; y <= playerLoc.Y + cr; y++)
			{
				var loc = new Vector2I(x, y);
				_totalChunkNr += 1;
				if (!ChunkManager.Chunks.TryGetValue(loc, out GroundChunk? chunk))
				{
					isReady = false;
					continue;
				}
				_spawnedChunksNr += 1;
				if (chunk.LodTier > GroundEnums.LodLevels.Close || !chunk.AreDecorsSpawned)
				{
					isReady = false;
					continue;
				}
				_decorChunksNr += 1;
			}
		}
		return isReady;
	}

	public void Activate()
	{
		GroundThreadManager.SetSteadyValues();
		_isGroundStartupDone = true;
	}

}
