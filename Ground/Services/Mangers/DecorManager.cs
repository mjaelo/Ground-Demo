using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using GroundDemo.General.Services;
using GroundDemo.Ground.GroundDatas.ThreadGenerationData;
using GroundDemo.Ground.GroundInfos;

namespace GroundDemo.Ground.Services.Mangers;

public record MultimeshData(bool CanMultimesh, Mesh? MeshRes, Transform3D MeshLocalTransform);

public class DecorManager
{
    public Dictionary<string, PackedScene> DecorScenes { get; } = new();
    public List<DecorInfo> DecorInfos { get; }
    private readonly Dictionary<string, MultimeshData> _multimeshCache = new();
    private readonly GroundManager _parent;

    public DecorManager(GroundManager parent)
    {
        _parent = parent;
        // Load DecorInfos and decor scenes
        using DirAccess? dir = DirAccess.Open(GroundConstants.DecorPath);
        if (dir == null) { GD.PushError($"Cannot open decor directory: {GroundConstants.DecorPath}"); }
        else
        {
            dir.ListDirBegin();
            for (string f = dir.GetNext(); f != ""; f = dir.GetNext())
                if (!dir.CurrentIsDir() && f.GetExtension().ToLower() == "tscn")
                    if (ResourceLoader.Load<PackedScene>(GroundConstants.DecorPath + f) is { } scene)
                        DecorScenes[f.GetBaseName().ToLower()] = scene;
            dir.ListDirEnd();
        }
        DecorInfos = SerializationService.LoadArray(GroundConstants.DecorValuesFile, "decors", DecorInfo.FromFile);
        DecorInfos = SerializationService.LoadArray(GroundConstants.DecorValuesFile, "decors", DecorInfo.FromFile);
        DecorInfos.Sort((a, b) => a.Priority != b.Priority ? b.Priority.CompareTo(a.Priority) : string.Compare(a.DecorName, b.DecorName, StringComparison.OrdinalIgnoreCase));
        foreach (string sceneName in DecorScenes.Keys) _multimeshCache[sceneName] = GetDecorMultimeshData(DecorScenes[sceneName]);
    }
    
    public DecorThreadResult GetDecorThreadResult(Vector3 regionOriginM, HashSet<Vector2I> blocked, DecorInfo decorD, int decorIdx, Vector2I loc)
    {
        int step = Math.Max(1, GroundConstants.DecorStep);
        Vector3 origin = regionOriginM + new Vector3(-GroundConstants.ChunkSize * 0.5f, 0, -GroundConstants.ChunkSize * 0.5f);
        RandomNumberGenerator rng = new() { Seed = (ulong)(loc.X * 73856093 ^ loc.Y * 19349663 ^ decorIdx * 83492791 ^ GroundConstants.NoiseSeed) };
        List<Transform3D> transforms = [];
        for (int x = 0; x < GroundConstants.ChunkSize; x += step)
        {
            for (int z = 0; z < GroundConstants.ChunkSize; z += step)
            {
                int gx = x / step, gz = z / step;
                float r1 = rng.Randf(), r2 = rng.Randf();
                if (blocked.Contains(new Vector2I(gx, gz)) || r1 < GroundConstants.DecorEmptyChance || r2 >= decorD.SpawnChance)
                    continue;
                float posX = x + origin.X, posZ = z + origin.Z;
                List<float> biomeScores = _parent.BiomeManager.ComputeBiomeScores(posX, posZ);
                if (IsDecorAllowedInBiome(decorD, biomeScores) && CanPlaceDecor(posX, posZ, decorD))
                    FillDecorTransforms(decorD, transforms, posX, posZ, blocked, gx, gz, step, (rng.Randi() % 4) * MathF.PI * 0.5f);
            }
        }
        return new DecorThreadResult(loc, transforms, blocked, decorIdx);
    }

    private bool IsDecorAllowedInBiome(DecorInfo decor, List<float> biomeScores)
    {
        int bestI = 0;
        for (int i = 1; i < biomeScores.Count; i++) if (biomeScores[i] > biomeScores[bestI]) bestI = i;
        return _parent.BiomeManager.Biomes[bestI].AllowedDecorIds.Contains(decor.DecorName);
    }

    private bool CanPlaceDecor(float posX, float posZ, DecorInfo decor)
    {
        if (SlopeDegAt(posX, posZ) > decor.MaxSlope) return false;
        if (decor.MeshSize is { X: <= 0, Y: <= 0 }) return true;
        float hx = decor.MeshSize.X * 0.5f, hz = decor.MeshSize.Y * 0.5f;
        foreach (Vector2 off in new[] { new Vector2(-hx, -hz), new Vector2(hx, -hz), new Vector2(-hx, hz), new Vector2(hx, hz) })
            if (SlopeDegAt(posX + off.X, posZ + off.Y) > decor.MaxSlope) return false;
        return true;
    }

    private void FillDecorTransforms(DecorInfo decor, List<Transform3D> transforms, float posX, float posZ, HashSet<Vector2I> blocked, int gx, int gz, int step, float rotY)
    {
        float bestH = _parent.BiomeManager.GetHeightAt(posX, posZ);
        if (decor.MeshSize.X > 0 || decor.MeshSize.Y > 0)
        {
            float hx = decor.MeshSize.X * 0.5f, hz = decor.MeshSize.Y * 0.5f;
            foreach (Vector2 off in new[] { new Vector2(-hx, -hz), new Vector2(hx, -hz), new Vector2(-hx, hz), new Vector2(hx, hz) })
            { float h = _parent.BiomeManager.GetHeightAt(posX + off.X, posZ + off.Y); if (h > bestH) bestH = h; }
        }
        transforms.Add(new Transform3D(new Basis(Vector3.Up, rotY), new Vector3(posX, bestH, posZ)));
        if (decor.MeshSize.X > 0 || decor.MeshSize.Y > 0)
        {
            int rx = (int)MathF.Ceiling(decor.MeshSize.X / (2.0f * step));
            int rz = (int)MathF.Ceiling(decor.MeshSize.Y / (2.0f * step));
            for (int dx = -rx; dx <= rx; dx++)
                for (int dz = -rz; dz <= rz; dz++)
                    blocked.Add(new Vector2I(gx + dx, gz + dz));
        }
    }

    private float SlopeDegAt(float wx, float wz)
    {
        Vector3 n = _parent.ChunkManager.SampleNormal(wx, wz);
        float ny = Math.Clamp(n.Dot(Vector3.Up), -1.0f, 1.0f);
        return Mathf.RadToDeg(MathF.Atan2(MathF.Sqrt(Math.Max(0.0f, 1.0f - ny * ny)), ny));
    }

    public Node3D[] GetDecorMeshes(DecorInfo decor, IReadOnlyList<Transform3D> transforms)
    {
        string key = decor.DecorName.ToLower();
        if (!DecorScenes.TryGetValue(key, out PackedScene? scene) || transforms.Count == 0) return [];
        MultimeshData md = _multimeshCache.GetValueOrDefault(key, new MultimeshData(false, null, Transform3D.Identity));

        return md.CanMultimesh
            ? [AddMeshesMultimesh([.. transforms], md.MeshRes!, md.MeshLocalTransform, decor.VisibilityRange)]
            : AddMeshesSimple([.. transforms], decor.VisibilityRange, scene, decor.GeneratorAction);
    }

    private MultimeshData GetDecorMultimeshData(PackedScene scene)
    {
        bool canMultimesh = true;
        Mesh? meshRes = null;
        Transform3D meshLocalTransform = Transform3D.Identity;
        Node tempInst = scene.Instantiate();
        // check if can multimesh based on node types
        List<MeshInstance3D> meshInstances = new();
        foreach (Node n in tempInst.GetChildren())
        {
            if (n is MeshInstance3D mi) meshInstances.Add(mi);
            else if (n is CollisionObject3D or Area3D) canMultimesh = false;
        }
        if (tempInst is MeshInstance3D rootMi) meshInstances.Add(rootMi);
        if (tempInst.GetScript().Obj != null) canMultimesh = false;
        
        // check if can multimesh based on mesh properties
        if (meshInstances.Count == 1 && canMultimesh)
        {
            meshRes = meshInstances[0].Mesh;
            meshLocalTransform = meshInstances[0].Transform;
            Vector3 s = meshLocalTransform.Basis.Scale;
            if (Math.Abs(s.X - 1.0f) > 0.001f || Math.Abs(s.Y - 1.0f) > 0.001f || Math.Abs(s.Z - 1.0f) > 0.001f) canMultimesh = false;
            if (meshLocalTransform.Origin.Length() > 0.001f) canMultimesh = false;
        }
        else { canMultimesh = false; }

        if (GodotObject.IsInstanceValid(tempInst)) tempInst.Free();
        return new MultimeshData(canMultimesh, meshRes, meshLocalTransform);
    }

    private MultiMeshInstance3D AddMeshesMultimesh(Transform3D[] transforms, Mesh meshRes, Transform3D meshLocalTransform, float visRange)
    {
        MultiMesh mm = new() { TransformFormat = MultiMesh.TransformFormatEnum.Transform3D, InstanceCount = transforms.Length, Mesh = meshRes };
        for (int i = 0; i < transforms.Length; i++) mm.SetInstanceTransform(i, transforms[i] * meshLocalTransform);
        MultiMeshInstance3D mmInst = new() { Multimesh = mm };
        if (visRange > 0.0f) ApplyVisibilityRangeRecursive(mmInst, visRange);
        return mmInst;
    }

    private Node3D[] AddMeshesSimple(Transform3D[] transforms, float visRange, PackedScene scene, Action<Node3D>? generator)
    {
        List<Node3D> nodes = new();
        foreach (Transform3D t in transforms)
        {
            Node3D node = (Node3D)scene.Instantiate();
            node.Transform = t;
            generator?.Invoke(node);
            if (visRange > 0.0f) ApplyVisibilityRangeRecursive(node, visRange);
            nodes.Add(node);
        }
        return [.. nodes];
    }

    private void ApplyVisibilityRangeRecursive(Node node, float rangeEnd)
    {
        if (node is GeometryInstance3D gi)
        {
            gi.VisibilityRangeEnd = rangeEnd;
            gi.VisibilityRangeEndMargin = rangeEnd * 0.1f;
            gi.VisibilityRangeFadeMode = GeometryInstance3D.VisibilityRangeFadeModeEnum.Disabled;
        }
        foreach (Node child in node.GetChildren()) ApplyVisibilityRangeRecursive(child, rangeEnd);
    }

    public void ClearDecors(Vector2I loc, Node3D[] decorNodes)
    {
        foreach (Node3D node in decorNodes)
            if (GodotObject.IsInstanceValid(node)) node.QueueFree();
        _parent.GroundThreadManager.DecorThreads.Remove(loc);
    }
}
