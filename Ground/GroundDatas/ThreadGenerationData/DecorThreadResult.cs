using System.Collections.Generic;
using Godot;

namespace GroundDemo.Ground.GroundDatas.ThreadGenerationData;

public record DecorThreadResult(
    Vector2I Loc,
    IReadOnlyList<Transform3D> DecorTransforms,
    IReadOnlySet<Vector2I> Blocked, // x,z -> true
    int DecorIdx
);
