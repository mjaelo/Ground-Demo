namespace GroundDemo.Ground;


public static class GroundConstants
{
    // GENERAL
    public const float HeightMin = 0.0f;
    public const float HeightMax = 800.0f;
    public const int ChunkSize = 256;
    public const string TexturesFilePath = "res://Assets/Ground/textures/texture_values.json";
    public const float WaterSurfaceLevel = -1.0f;
    public const int NoiseSeed = 7891;

    // BIOMES
    public const string BiomeValuesPath = "res://Assets/Ground/biomes/biome_values.json";
    public const float SteepThreshold = 30.0f;
    public const float SteepBlendRange = 10.0f; // Degrees on each side of SteepThreshold over which flat/steep textures blend.
    public const float TextureBlendSharpness = 50.0f;
    public const float HeightBlendSharpness = 5.0f;
    public const float SizeBaseFreq = 0.00015f;
    public const float HeightBaseFreq = 0.0015f;
    public const float BiomeHeightThreshold = 0.001f;

    // DECORS
    public const string DecorPath = "res://Assets/Ground/decors/";
    public const string DecorValuesFile = DecorPath + "decor_values.json";
    public const int DecorStep = 2; // Distance between placed mesh instances; lower = denser.
    public const float DecorEmptyChance = 0.3f;

    // CHUNKS
    public const float BiomeWeightThreshold = 0.01f; // threshold to be counted into splatmap
    public const float BiomeProminenceTreshold = 0.1f; // biome must cover at least 10% of pixels
    public const int StartupRadius = 1;
    public const int CloseRadius = 3;
    public const int FarRadius = 30;
    public const int CloseResolution = 48;
    public const int FarResolution = 6;
    public const int RemoveChunksMargin = 3;

    // THREADING
    public const int StartupDecorThreads = 16;
    public const int StartupChunkThreads = 4;
    public const int StartupChunksPerFrame = 16;
    public const int StartupLodPerFrame = 100;

    public const int SteadyChunkThreads = 4;
    public const int SteadyDecorThreads = 2;
    public const int SteadyChunksPerFrame = 4;
    public const int SteadyLodPerFrame = 4;

    public const float ChunkCleanInterval = 0.5f; // Only scan for chunk removal twice per second.

    // VISIBILITY
    // Maximum render distance for FAR-LOD chunks (GPU-level cull). Set to 0 to disable.
    public static readonly float FarLodVisibilityRange = FarRadius * ChunkSize * 1.05f;
    // Interval (seconds) between full chunk-request scans when the player hasn't moved chunks.
    public const float ChunkScanInterval = 0.25f;

    // TEXTURE
    public const string TerrainShaderPath = "res://Assets/Ground/terrain_blend.gdshader";
    public const float TextureScale = 16.0f;

    // NAVIGATION
    public const float NavBakeRadius = 1024.0f; // XZ half-extent of the nav mesh bake area around the player.
    public const float NavBakeHeight = 300.0f; // Full height window baked around the player's Y position.
    public const float NavCellSize = 1.0f;
    public const float NavCellHeight = 0.5f;
    public const float MinRebaseDist = 128.0f; // How far (XZ) the player must move before a rebake is triggered.
    public const float BakeCooldown = 1.5f;
}