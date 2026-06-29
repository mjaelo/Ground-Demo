using System;
using System.Text.Json;
using System.Text.Json.Serialization;
using Godot;
using GroundDemo.General.Services;
using GroundDemo.Ground.Services;

namespace GroundDemo.Ground.GroundInfos;

/// Information about a decor asset loaded once at the start of the program.
public record DecorInfo
{
    public string DecorName { get; init; } = "";
    public float SpawnChance { get; init; } = 1.0f; // Probability (0–1) of being used at a given XZ point.
    public float MaxSlope { get; init; } = 90.0f; // Maximum degrees of ground at which this decor may appear.
    public float VisibilityRange { get; init; } = 0.0f; // Maximum distance from the camera at which this asset is rendered. Set to 0 to use the default.
    public int Priority { get; init; } = 0; // Priority for spawning: higher values spawn earlier. (houses high, grass low)
    public Vector2I MeshSize { get; init; } = Vector2I.Zero;
    [JsonIgnore] public Action<Node3D>? GeneratorAction { get; private set; }

    public static DecorInfo FromFile(string json)
    {
        var decorInfo = SerializationService.Deserialize<DecorInfo>(json) ?? new DecorInfo();
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("GeneratorScript", out var pathElem)) return decorInfo;
        decorInfo.GeneratorAction = GeneratorScriptResolver.Resolve(pathElem.GetString());
        return decorInfo;
    }
}
