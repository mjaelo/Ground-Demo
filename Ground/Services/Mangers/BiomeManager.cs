using System;
using System.Collections.Generic;
using Godot;
using GroundDemo.General.Services;
using GroundDemo.Ground.GroundInfos;

namespace GroundDemo.Ground.Services.Mangers;

public class BiomeManager
{
    public readonly List<BiomeInfo> Biomes = SerializationService.LoadArray(GroundConstants.BiomeValuesPath, "biomes", BiomeInfo.FromFile);
    private readonly List<FastNoiseLite> _sizeNoises;
    private readonly List<FastNoiseLite> _heightNoises;

    // INITIALIZATION
    public BiomeManager()
    {
        _sizeNoises = [];
        _heightNoises = [];
        for (int i = 0; i < Biomes.Count; i++)
        {
            _sizeNoises.Add(new FastNoiseLite()
            {
                NoiseType = FastNoiseLite.NoiseTypeEnum.SimplexSmooth,
                Frequency = GroundConstants.SizeBaseFreq / MathF.Max(Biomes[i].BiomeSize, 0.0001f),
                Seed = GroundConstants.NoiseSeed + i * 5137
            });
            _heightNoises.Add(new FastNoiseLite()
            {
                NoiseType = FastNoiseLite.NoiseTypeEnum.SimplexSmooth,
                Frequency = GroundConstants.HeightBaseFreq / MathF.Max(Biomes[i].SteepnessLevel, 0.0001f),
                Seed = GroundConstants.NoiseSeed + i * 5137 + 99991
            });
        }
    }

    // CORE API
    public float GetHeightAt(float worldX, float worldZ, IList<float>? precomputedScores = null)
    {
        int biomeCount = Biomes.Count;
        Span<float> biomeScores = stackalloc float[biomeCount];
        if (precomputedScores != null && precomputedScores.Count == biomeCount)
            for (int i = 0; i < biomeCount; i++) biomeScores[i] = precomputedScores[i];
        else
        {
            for (int i = 0; i < Biomes.Count; i++)
                biomeScores[i] = GetBiomeScoreWithSize((_sizeNoises[i].GetNoise2D(worldX, worldZ) + 1.0f) * 0.5f, Biomes[i].BiomeRarity, Biomes[i].BiomeSize);
        }

        float dominantOffset = float.NegativeInfinity;
        for (int i = 0; i < biomeCount; i++)
            if (Biomes[i].Offset > dominantOffset && biomeScores[i] >= GroundConstants.BiomeHeightThreshold)
                dominantOffset = Biomes[i].Offset;

        // Step 1: terrain height ignoring biomes with offset < minimal_offset
        Span<float> heightBiomeWeightsFull = stackalloc float[biomeCount];
        WeightsWithSharpnessSpan(biomeScores, GroundConstants.HeightBlendSharpness, heightBiomeWeightsFull);
        Span<float> highBiomeWeights = stackalloc float[biomeCount];
        for (int i = 0; i < biomeCount; i++)
            highBiomeWeights[i] = Biomes[i].Offset < dominantOffset ? 0.0f : heightBiomeWeightsFull[i];

        // with elevated-only normalized height weights, compute high_biomes_y
        float highBiomesY = 0.0f;
        for (int i = 0; i < biomeCount; i++)
        {
            if (highBiomeWeights[i] < GroundConstants.BiomeHeightThreshold) continue;
            highBiomesY += highBiomeWeights[i] * GetBiomeY(worldX, worldZ, i);
        }

        // Step 2: downward pull from low-offset biomes
        float dominantHighBiomeWeight = 0.0f;
        for (int i = 0; i < biomeCount; i++)
            if (Biomes[i].Offset >= dominantOffset && highBiomeWeights[i] > dominantHighBiomeWeight)
                dominantHighBiomeWeight = highBiomeWeights[i];

        // only pull downward if a low-offset biome dominates locally
        float finalHeight = highBiomesY;
        for (int i = 0; i < biomeCount; i++)
        {
            if (Biomes[i].Offset >= dominantOffset) continue;
            float lowW = heightBiomeWeightsFull[i];
            if (lowW <= dominantHighBiomeWeight) continue;
            float pullPower = MathF.Min(MathF.Max((lowW - dominantHighBiomeWeight) / MathF.Max(1.0f - dominantHighBiomeWeight, 0.001f), 0.0f), 1.0f);
            pullPower = pullPower * pullPower * (3.0f - 2.0f * pullPower); // smoothstep
            finalHeight += (GetBiomeY(worldX, worldZ, i) - finalHeight) * pullPower;
        }
        return finalHeight;
    }

    private float GetBiomeY(float worldX, float worldZ, int i) =>
        Biomes[i].Offset + (_heightNoises[i].GetNoise2D(worldX, worldZ) + 1.0f) * 0.5f * Biomes[i].MaxHillY;

    public BiomeInfo GetDominantBiomeAt(float worldX, float worldZ)
    {
        List<float> bw = BiomeWeights(worldX, worldZ);
        int bestI = 0;
        for (int i = 1; i < bw.Count; i++)
            if (bw[i] > bw[bestI]) bestI = i;
        return Biomes[bestI];
    }

    // HELPERS
    private void WeightsWithSharpnessSpan(ReadOnlySpan<float> scores, float sharpness, Span<float> weights)
    {
        int count = scores.Length;
        float total = 0.0f;
        for (int i = 0; i < count; i++) { weights[i] = MathF.Pow(MathF.Max(scores[i], 0.0001f), sharpness); total += weights[i]; }
        if (total <= 0.0f) { for (int i = 0; i < count; i++) weights[i] = 1.0f / count; }
        else { float inv = 1.0f / total; for (int i = 0; i < count; i++) weights[i] *= inv; }
    }

    // Keep List-returning versions for callers that still need them (ChunkManager splatmap)
    public List<float> ComputeBiomeScores(float worldX, float worldZ)
    {
        List<float> scores = new List<float>(Biomes.Count);
        for (int i = 0; i < Biomes.Count; i++)
            scores.Add(GetBiomeScoreWithSize((_sizeNoises[i].GetNoise2D(worldX, worldZ) + 1.0f) * 0.5f, Biomes[i].BiomeRarity, Biomes[i].BiomeSize));
        return scores;
    }

    public List<float> WeightsWithSharpness(IList<float> scores, float sharpness)
    {
        int count = scores.Count;
        List<float> weights = new List<float>(new float[count]);
        float total = 0.0f;
        for (int i = 0; i < count; i++) { weights[i] = MathF.Pow(MathF.Max(scores[i], 0.0001f), sharpness); total += weights[i]; }
        if (total <= 0.0f) { for (int i = 0; i < count; i++) weights[i] = 1.0f / count; }
        else { float inv = 1.0f / total; for (int i = 0; i < count; i++) weights[i] *= inv; }
        return weights;
    }

    private List<float> BiomeWeights(float worldX, float worldZ) =>
        WeightsWithSharpness(ComputeBiomeScores(worldX, worldZ), GroundConstants.TextureBlendSharpness);

    private float GetBiomeScoreWithSize(float raw01, float biomeRarity, float biomeSize)
    {
        float rarityScore = MathF.Pow(MathF.Max(0.0f, MathF.Min(raw01, 1.0f)), MathF.Max(0.25f, MathF.Min(MathF.Max(biomeRarity, 0.0001f), 8.0f)));
        float sizeBias = biomeSize > 1.0f ? MathF.Min(1.0f + MathF.Log(biomeSize) * 0.2f, 3.0f)
                       : biomeSize < 1.0f ? MathF.Max(1.0f - MathF.Log(1.0f / biomeSize) * 0.2f, 0.3f)
                       : 1.0f;
        return rarityScore * sizeBias;
    }
}
