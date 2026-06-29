using System.Collections.Generic;
using Godot;

namespace GroundDemo.Ground.GroundDatas.ThreadGenerationData;

/// Thread Request to generate decors with a DecorIdx in Loc chunk, avoiding Blocked locs
public record DecorThreadRequest(
    Vector2I Loc,
    int DecorIdx,
    IReadOnlySet<Vector2I> Blocked // locs blocked by other decor
);
