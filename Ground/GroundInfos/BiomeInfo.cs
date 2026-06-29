using System.Collections.Generic;
using GroundDemo.General.Services;

namespace GroundDemo.Ground.GroundInfos;

/// Information about a biome loaded once at the start of the program.
public record BiomeInfo
{
    public string BiomeName { get; init; } = "";
    public float SteepnessLevel { get; init; } = 0.0f; /// Controls terrain steepness percent.
    public float Offset { get; init; } = 0.0f; /// Elevation offset from HeightMin.
    public int FlatTextureId { get; init; } = 1;   /// Texture ID for flat ground (default Grass).
    public int SteepTextureId { get; init; } = 0;  /// Texture ID for steep slopes (default Rock).
    public int LodTextureId { get; init; } = -1;   /// LOD texture (-1 => use FlatTextureId).
    public float BiomeRarity { get; init; } = 1.0f;
    public IReadOnlyList<string> AllowedDecorIds { get; init; } = []; /// String IDs/names of allowed decors.
    public float BiomeSize { get; set; } = 1.0f;
    public bool HasWater { get; init; } = false; /// Whether this biome contains water at y=0.
    public float MaxHillY => SteepnessLevel * SteepnessLevel * (GroundConstants.HeightMax - GroundConstants.HeightMin) * 0.6f;

    public static BiomeInfo FromFile(string json)
    {
        return SerializationService.Deserialize<BiomeInfo>(json) ?? new BiomeInfo();
    }
}

