using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using GroundDemo.Ground.GroundDatas;
using GroundDemo.Ground.GroundDatas.ThreadGenerationData;
using GroundDemo.Ground.GroundInfos;
using GroundDemo.Ground.Scenes;

namespace GroundDemo.Ground.Services.Mangers;

public partial class ChunkManager(GroundManager parent) : RefCounted
{
    public readonly Dictionary<Vector2I, GroundChunk> Chunks = new();
    public readonly Dictionary<Vector2I, ChunkData> SavedChunkData = new();
    private readonly List<GroundChunk> _tempChunkList = [];

    // GENERATION
    public ChunkThreadResult GetChunkThreadResult(Vector2I loc, GroundEnums.LodLevels lodTier)
    {
        int resolution = lodTier == GroundEnums.LodLevels.Close ? GroundConstants.CloseResolution : GroundConstants.FarResolution;
        float baseX = loc.X * GroundConstants.ChunkSize;
        float baseZ = loc.Y * GroundConstants.ChunkSize;
        float invRes = 1.0f / (resolution - 1);

        (Image heightmap, float[] biomeWeightTotals, List<float>[] cachedBiomeWeights) = GetHeightmapAndBiomeWeights(resolution, invRes, baseX, baseZ);
        List<int> prominentBiomeIds = GetProminentBiomesIds(biomeWeightTotals);
        (Image splatIndices, Image splatWeights) = lodTier == GroundEnums.LodLevels.Far
            ? GetFarSplatmaps(cachedBiomeWeights, resolution)
            : GetCloseSplatmaps(cachedBiomeWeights, resolution, heightmap, invRes, baseX, baseZ);
        bool hasWater = false;
        foreach (int id in prominentBiomeIds) { if (parent.BiomeManager.Biomes[id].HasWater) { hasWater = true; break; } }
        ChunkData chunkData = new(loc, heightmap, splatIndices, splatWeights, hasWater, prominentBiomeIds,  new Dictionary<int, IReadOnlyList<Transform3D>>());
        return new ChunkThreadResult(lodTier, chunkData);
    }

    private List<int> GetProminentBiomesIds(float[] biomeWeightTotals)
    {
        float totalWeight = biomeWeightTotals.Sum();
        List<int> result = [];
        for (int i = 0; i < parent.BiomeManager.Biomes.Count; i++)
            if (biomeWeightTotals[i] >= totalWeight * GroundConstants.BiomeProminenceTreshold) result.Add(i);
        return result;
    }

    private (Image heightmap, float[] biomeWeightTotals, List<float>[] cachedBiomeWeights) GetHeightmapAndBiomeWeights(int resolution, float invRes, float baseX, float baseZ)
    {
        int biomeCount = parent.BiomeManager.Biomes.Count;
        float[] biomeWeightTotals = new float[biomeCount];
        var cachedBiomeWeights = new List<float>[resolution * resolution];
        Image heightmap = Image.CreateEmpty(resolution, resolution, false, Image.Format.Rf);
        for (int x = 0; x < resolution; x++)
        {
            float worldX = x * invRes * GroundConstants.ChunkSize + baseX;
            for (int y = 0; y < resolution; y++)
            {
                float worldZ = y * invRes * GroundConstants.ChunkSize + baseZ;
                List<float> biomeScores = parent.BiomeManager.ComputeBiomeScores(worldX, worldZ);
                List<float> biomeWeights = parent.BiomeManager.WeightsWithSharpness(biomeScores, GroundConstants.TextureBlendSharpness);
                cachedBiomeWeights[x * resolution + y] = biomeWeights;
                for (int i = 0; i < biomeCount; i++) biomeWeightTotals[i] += biomeWeights[i];
                heightmap.SetPixel(x, y, new Color(parent.BiomeManager.GetHeightAt(worldX, worldZ, biomeScores), 0, 0));
            }
        }
        return (heightmap, biomeWeightTotals, cachedBiomeWeights);
    }

    private (Image indices, Image weights) GetCloseSplatmaps(List<float>[] cachedBiomeWeights, int resolution, Image heightmap, float invRes, float baseX, float baseZ)
    {
        Image splatIdx = Image.CreateEmpty(resolution, resolution, false, Image.Format.Rgb8);
        Image splatWgt = Image.CreateEmpty(resolution, resolution, false, Image.Format.Rgb8);
        float cellSize = (float)GroundConstants.ChunkSize / (resolution - 1);
        float slopeLo = GroundConstants.SteepThreshold - GroundConstants.SteepBlendRange;
        float slopeHi = GroundConstants.SteepThreshold + GroundConstants.SteepBlendRange;

        // Reusable per-pixel dictionary: textureId -> accumulated weight
        Dictionary<int, float> texWeights = new();

        for (int x = 0; x < resolution; x++)
        {
            for (int y = 0; y < resolution; y++)
            {
                float hCenter = heightmap.GetPixel(x, y).R;
                float hRight = x + 1 < resolution ? heightmap.GetPixel(x + 1, y).R : parent.BiomeManager.GetHeightAt((x + 1) * invRes * GroundConstants.ChunkSize + baseX, y * invRes * GroundConstants.ChunkSize + baseZ);
                float hDown  = y + 1 < resolution ? heightmap.GetPixel(x, y + 1).R : parent.BiomeManager.GetHeightAt(x * invRes * GroundConstants.ChunkSize + baseX, (y + 1) * invRes * GroundConstants.ChunkSize + baseZ);
                float slope = Mathf.RadToDeg(MathF.Acos(Math.Clamp(new Vector3(-(hRight - hCenter) / cellSize, 1.0f, -(hDown - hCenter) / cellSize).Normalized().Dot(Vector3.Up), -1.0f, 1.0f)));
                float steepFactor = Math.Clamp((slope - slopeLo) / (slopeHi - slopeLo), 0.0f, 1.0f);
                steepFactor = steepFactor * steepFactor * (3.0f - 2.0f * steepFactor);

                texWeights.Clear();
                List<float> biomeWeights = cachedBiomeWeights[x * resolution + y];
                for (int i = 0; i < parent.BiomeManager.Biomes.Count; i++)
                {
                    if (biomeWeights[i] < GroundConstants.BiomeWeightThreshold) continue;
                    BiomeInfo biome = parent.BiomeManager.Biomes[i];
                    float flatW = biomeWeights[i] * (1.0f - steepFactor);
                    float steepW = biomeWeights[i] * steepFactor;
                    if (flatW > 0.001f && biome.FlatTextureId >= 0)
                    {
                        texWeights.TryGetValue(biome.FlatTextureId, out float cur);
                        texWeights[biome.FlatTextureId] = cur + flatW;
                    }
                    if (steepW > 0.001f && biome.SteepTextureId >= 0)
                    {
                        texWeights.TryGetValue(biome.SteepTextureId, out float cur);
                        texWeights[biome.SteepTextureId] = cur + steepW;
                    }
                }
                WriteTop3(texWeights, splatIdx, splatWgt, x, y);
            }
        }
        return (splatIdx, splatWgt);
    }

    private (Image indices, Image weights) GetFarSplatmaps(List<float>[] cachedBiomeWeights, int resolution)
    {
        Image splatIdx = Image.CreateEmpty(resolution, resolution, false, Image.Format.Rgb8);
        Image splatWgt = Image.CreateEmpty(resolution, resolution, false, Image.Format.Rgb8);
        Dictionary<int, float> texWeights = new();

        for (int x = 0; x < resolution; x++)
        {
            for (int y = 0; y < resolution; y++)
            {
                texWeights.Clear();
                List<float> biomeWeights = cachedBiomeWeights[x * resolution + y];
                for (int i = 0; i < parent.BiomeManager.Biomes.Count; i++)
                {
                    if (biomeWeights[i] < GroundConstants.BiomeWeightThreshold) continue;
                    int texId = parent.BiomeManager.Biomes[i].LodTextureId;
                    if (texId < 0) texId = parent.BiomeManager.Biomes[i].FlatTextureId;
                    if (texId >= 0)
                    {
                        texWeights.TryGetValue(texId, out float cur);
                        texWeights[texId] = cur + biomeWeights[i];
                    }
                }
                WriteTop3(texWeights, splatIdx, splatWgt, x, y);
            }
        }
        return (splatIdx, splatWgt);
    }

    /// Picks the 3 highest-weight texture IDs, normalises their weights, and writes to both images.
    private static void WriteTop3(Dictionary<int, float> texWeights, Image splatIdx, Image splatWgt, int x, int y)
    {
        // Find top 3 by weight
        int id0 = 0, id1 = 0, id2 = 0;
        float w0 = 0f, w1 = 0f, w2 = 0f;
        foreach (var kv in texWeights)
        {
            if (kv.Value > w0)      { id2 = id1; w2 = w1; id1 = id0; w1 = w0; id0 = kv.Key; w0 = kv.Value; }
            else if (kv.Value > w1) { id2 = id1; w2 = w1; id1 = kv.Key; w1 = kv.Value; }
            else if (kv.Value > w2) { id2 = kv.Key; w2 = kv.Value; }
        }

        float total = w0 + w1 + w2;
        if (total > 0f) { float inv = 1f / total; w0 *= inv; w1 *= inv; w2 *= inv; }
        else { w0 = 1f; } // fallback

        splatIdx.SetPixel(x, y, new Color(id0 / 255f, id1 / 255f, id2 / 255f));
        splatWgt.SetPixel(x, y, new Color(w0, w1, w2));
    }

    // MANAGEMENT
    public void UpdateDistantChunks(Vector2I playerLoc)
    {
        float removeR = GroundConstants.FarRadius + GroundConstants.RemoveChunksMargin;
        _tempChunkList.Clear();
        _tempChunkList.AddRange(Chunks.Values);
        foreach (GroundChunk chunk in _tempChunkList)
        {
            float dist = chunk.Data.MapXy.DistanceTo(playerLoc);
            if (dist > removeR) { RemoveChunk(chunk.Data.MapXy); }
            else if (chunk.LodTier == GroundEnums.LodLevels.Close && dist > GroundConstants.CloseRadius + 1 && chunk.AreDecorsSpawned)
            {
                parent.DecorManager.ClearDecors(chunk.Data.MapXy, chunk.DecorNodes.ToArray());
                chunk.DecorNodes = [];
                chunk.AreDecorsSpawned = false;
            }
        }
    }

    public void RemoveChunk(Vector2I loc)
    {
        if (!Chunks.Remove(loc, out GroundChunk? chunk)) return;
        if (IsInstanceValid(chunk)) chunk.QueueFree();
        parent.DecorManager.ClearDecors(loc, chunk.DecorNodes.ToArray());
        chunk.DecorNodes = [];
    }

    // SAMPLING
    public Vector3 SampleNormal(float worldX, float worldZ)
    {
        Vector2I loc = GroundUtils.WorldPosToChunkLoc(new Vector3(worldX, 0, worldZ));
        if (Chunks.TryGetValue(loc, out GroundChunk? chunk) && chunk.Data?.Heightmap != null)
        {
            float bh = GroundUtils.HeightFromHeightmap(chunk.Data.Heightmap, worldX, worldZ, loc);
            return new Vector3(-(GroundUtils.HeightFromHeightmap(chunk.Data.Heightmap, worldX + 1.0f, worldZ, loc) - bh), 1.0f, -(GroundUtils.HeightFromHeightmap(chunk.Data.Heightmap, worldX, worldZ + 1.0f, loc) - bh)).Normalized();
        }
        float bh2 = parent.BiomeManager.GetHeightAt(worldX, worldZ);
        return new Vector3(-(parent.BiomeManager.GetHeightAt(worldX + 1.0f, worldZ) - bh2), 1.0f, -(parent.BiomeManager.GetHeightAt(worldX, worldZ + 1.0f) - bh2)).Normalized();
    }

    public float GetHeightAt(Vector3 worldPos)
    {
        Vector2I loc = GroundUtils.WorldPosToChunkLoc(worldPos);
        if (Chunks.TryGetValue(loc, out GroundChunk? chunk) && chunk.Data?.Heightmap != null)
            return GroundUtils.HeightFromHeightmap(chunk.Data.Heightmap, worldPos.X, worldPos.Z, loc);
        return parent.BiomeManager.GetHeightAt(worldPos.X, worldPos.Z);
    }
}
