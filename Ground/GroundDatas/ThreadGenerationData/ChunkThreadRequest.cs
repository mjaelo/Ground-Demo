using Godot;

namespace GroundDemo.Ground.GroundDatas.ThreadGenerationData;

public record ChunkThreadRequest(
    Vector2I Loc,
    GroundEnums.LodLevels LodTier,
    float Dist
);

