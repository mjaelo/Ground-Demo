using System;
using Godot;

namespace GroundDemo.Ground;

/// Ground Utils
public static class GroundUtils
{
    public static Vector2I WorldPosToChunkLoc(Vector3 pos)
    {
        var chunkX = (int)MathF.Floor(pos.X / GroundConstants.ChunkSize);
        var chunkZ = (int)MathF.Floor(pos.Z / GroundConstants.ChunkSize);
        return new Vector2I(chunkX, chunkZ);
    }

    public static float HeightFromHeightmap(Image img, float worldX, float worldZ, Vector2I loc)
    {
        var maxRes = img.GetWidth() - 1; // ChunkSize maps to index 0..maxRes; prevents out-of-range at boundary
        var localX = worldX - loc.X * GroundConstants.ChunkSize;
        var localZ = worldZ - loc.Y * GroundConstants.ChunkSize;
        var px = Math.Clamp((int)(localX / GroundConstants.ChunkSize * maxRes), 0, maxRes);
        var py = Math.Clamp((int)(localZ / GroundConstants.ChunkSize * maxRes), 0, maxRes);
        var color = img.GetPixel(px, py);
        return color.R;
    }
}