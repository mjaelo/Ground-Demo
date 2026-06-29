using System.Collections.Generic;
using Godot;

namespace GroundDemo.Ground.GroundDatas;

/// <summary>
/// Data holder for a single Ground Chunk
/// </summary>
/// <param name="MapXy">chunk's map coordinates (in chunks, not world units)</param>
/// <param name="Heightmap">height of each vertex in the chunk</param>
/// <param name="SplatIndices">RGB channels store the top-3 texture array indices for each pixel, encoded as idx/255</param>
/// <param name="SplatWeights">RGB channels store the normalised blend weights for those 3 textures </param>
/// <param name="HasWater">whether this chunk should render water at y=0</param>
/// <param name="ProminentBiomeIds">ids of prominent biomes in the chunk. used for is_decor_allowed_in_chunk</param>
/// <param name="DecorTransforms">decor_id -> Array[Transforms3D]</param>
public record ChunkData(
    Vector2I MapXy,
    Image Heightmap,
    Image SplatIndices,
    Image SplatWeights,
    bool HasWater,
    IReadOnlyList<int> ProminentBiomeIds,
    IDictionary<int, IReadOnlyList<Transform3D>> DecorTransforms
);