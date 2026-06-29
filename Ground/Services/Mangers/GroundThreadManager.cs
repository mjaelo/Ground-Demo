using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Godot;
using GroundDemo.Ground.GroundDatas;
using GroundDemo.Ground.GroundDatas.ThreadGenerationData;
using GroundDemo.Ground.GroundInfos;
using GroundDemo.Ground.Scenes;
using GroundDemo.Ground.Services.Builders;

namespace GroundDemo.Ground.Services.Mangers;

public partial class GroundThreadManager(GroundManager parent) : RefCounted
{
    public readonly Dictionary<Vector2I, Task<DecorThreadResult>> DecorThreads = new();
    private readonly Dictionary<Vector2I, Task<ChunkThreadResult>> _chunkThreads = new();
    private readonly List<ChunkThreadResult> _pendingChunkResults = [];
    private readonly List<DecorThreadResult> _pendingDecorResults = [];
    private readonly List<ChunkThreadRequest> _chunkRequests = [];
    private readonly List<DecorThreadRequest> _decorRequests = [];

    private int _maxChunkThreads = GroundConstants.StartupChunkThreads;
    private int _maxDecorThreads = GroundConstants.StartupDecorThreads;
    private int _maxChunksPerFrame = GroundConstants.StartupChunksPerFrame;
    private int _maxLodPerFrame = GroundConstants.StartupLodPerFrame;

    private Vector2I _lastPlayerLoc = Vector2I.Zero;
    private readonly HashSet<Vector2I> _visibleChunksCache = [];
    private Vector2I _lastScanLoc = new(-9999, -9999);
    private float _scanTimer;
    private bool _chunkRequestsDirty = true;
    private bool _decorRequestsDirty = true;
    private readonly List<Vector2I> _doneKeys = [];

    public void HandleThreads(Vector2I playerLoc, float delta = 0.016f)
    {
        _lastPlayerLoc = playerLoc;
        _visibleChunksCache.Clear();
        Plane[] frustum = parent.Camera.GetFrustum().ToArray(); // cached in local for frame

        // Mark scan as dirty when the player crosses a chunk boundary
        if (playerLoc != _lastScanLoc)
        {
            _lastScanLoc = playerLoc;
            _chunkRequestsDirty = true;
            _decorRequestsDirty = true;
            _scanTimer = 0.0f;
        }
        else
        {
            _scanTimer += delta;
            if (_scanTimer >= GroundConstants.ChunkScanInterval)
            {
                _scanTimer = 0.0f;
                _chunkRequestsDirty = true;
                _decorRequestsDirty = true;
            }
        }

        // Collect pending thread results
        CollectPendingThreadResults(_chunkThreads, _pendingChunkResults);
        CollectPendingThreadResults(DecorThreads, _pendingDecorResults);

        // Process pending chunk results
        if (_pendingChunkResults.Count > 0)
        {
            SortPendingChunkResults(playerLoc, frustum);
            ApplyChunkResults(frustum);
        }

        if (_pendingDecorResults.Count > 0)
        {
            SortPendingDecorResults(playerLoc, frustum);
            ApplyDecorResults(frustum);
        }

        // Start new chunk threads
        if (_chunkThreads.Count < _maxChunkThreads)
        {
            if (_chunkRequestsDirty) UpdateChunkRequests(playerLoc, frustum);
            StartChunkThreads();
        }

        if (DecorThreads.Count < _maxDecorThreads)
        {
            if (_decorRequestsDirty) UpdateDecorRequests(playerLoc, frustum);
            StartDecorThreads(frustum);
        }
    }

    // CHUNKS
    private void UpdateChunkRequests(Vector2I playerLoc, Plane[] frustum)
    {
        bool areRequestsDirty = false;
        int farR = GroundConstants.FarRadius, closeR = GroundConstants.CloseRadius;
        float farRSq = farR * farR, closeRSq = closeR * closeR;
        HashSet<Vector2I> requestLocs = new();
        foreach (var r in _chunkRequests) requestLocs.Add(r.Loc);
        for (int x = playerLoc.X - farR; x <= playerLoc.X + farR; x++)
        {
            for (int y = playerLoc.Y - farR; y <= playerLoc.Y + farR; y++)
            {
                Vector2I loc = new(x, y);
                float dx = x - playerLoc.X, dy = y - playerLoc.Y, distSq = dx * dx + dy * dy;
                if (distSq > farRSq || _chunkThreads.ContainsKey(loc) || requestLocs.Contains(loc)) continue;
                parent.ChunkManager.Chunks.TryGetValue(loc, out GroundChunk? chunk);
                GroundEnums.LodLevels desiredLod =
                    distSq <= closeRSq ? GroundEnums.LodLevels.Close : GroundEnums.LodLevels.Far;
                if (chunk != null && chunk.LodTier <= desiredLod) continue;
                if (!IsChunkVisible(loc, frustum) && (desiredLod != GroundEnums.LodLevels.Close ||
                                                      (distSq > 1.0f && !IsStartupChunk(loc)))) continue;
                if (desiredLod == GroundEnums.LodLevels.Close &&
                    parent.ChunkManager.SavedChunkData.TryGetValue(loc, out ChunkData? savedData))
                {
                    _pendingChunkResults.Add(new ChunkThreadResult((int)GroundEnums.LodLevels.Close, savedData));
                    continue;
                }

                _chunkRequests.Add(new ChunkThreadRequest(loc, desiredLod, MathF.Sqrt(distSq)));
                areRequestsDirty = true;
            }
        }

        if (areRequestsDirty) SortChunkRequests(frustum);
        _chunkRequestsDirty = false;
    }

    private void StartChunkThreads()
    {
        int i = 0;
        while (i < _chunkRequests.Count)
        {
            if (_chunkThreads.Count >= _maxChunkThreads) break;
            ChunkThreadRequest req = _chunkRequests[i];
            if (_chunkThreads.ContainsKey(req.Loc))
            {
                i++;
                continue;
            }

            _chunkRequests.RemoveAt(i);
            _chunkThreads[req.Loc] = Task.Run(() =>
                parent.ChunkManager.GetChunkThreadResult(req.Loc, req.LodTier));
        }
    }

    private void ApplyChunkResults(Plane[] frustum)
    {
        int closeApplied = 0, lodApplied = 0, i = 0;
        while (i < _pendingChunkResults.Count)
        {
            if (closeApplied >= _maxChunksPerFrame && lodApplied >= _maxLodPerFrame) break;
            ChunkThreadResult result = _pendingChunkResults[i];
            bool isClose = result.LodTier == (int)GroundEnums.LodLevels.Close;
            if ((isClose && closeApplied >= _maxChunksPerFrame) || (!isClose && lodApplied >= _maxLodPerFrame))
            {
                i++;
                continue;
            }

            _pendingChunkResults.RemoveAt(i);
            ChunkData chunkD = result.ChunkData;
            if (parent.ChunkManager.Chunks.TryGetValue(chunkD.MapXy, out GroundChunk? existing) &&
                existing.LodTier <= result.LodTier) continue;
            if (parent.ChunkManager.Chunks.ContainsKey(chunkD.MapXy)) parent.ChunkManager.RemoveChunk(chunkD.MapXy);

            GroundChunk chunk = ChunkBuilder.BuildChunk(chunkD, result.LodTier);
            AddChunkToTree(chunk);
            parent.ChunkManager.Chunks[chunkD.MapXy] = chunk;

            if (isClose)
            {
                closeApplied++;
                if (IsChunkVisible(chunkD.MapXy, frustum) || IsStartupChunk(chunkD.MapXy))
                {
                    if (chunkD.DecorTransforms.Count == 0)
                    {
                        int idx = GetNextAllowedDecorInChunk(0, chunkD.ProminentBiomeIds);
                        if (idx >= 0)
                            _decorRequests.Add(new DecorThreadRequest(chunkD.MapXy, idx, new HashSet<Vector2I>()));
                        else
                        {
                            chunk.AreDecorsSpawned = true;
                            parent.ChunkManager.SavedChunkData[chunkD.MapXy] = chunkD;
                        }
                    }
                }
            }
            else
            {
                lodApplied++;
            }
        }
    }


    // DECORS
    private void UpdateDecorRequests(Vector2I playerLoc, Plane[] frustum)
    {
        bool dirty = false;
        int savedApplied = 0;
        HashSet<Vector2I> reqLocs = new();
        foreach (var r in _decorRequests) reqLocs.Add(r.Loc);
        foreach (GroundChunk chunk in parent.ChunkManager.Chunks.Values)
        {
            if (chunk.LodTier != GroundEnums.LodLevels.Close || chunk.AreDecorsSpawned ||
                DecorThreads.ContainsKey(chunk.Data!.MapXy) || reqLocs.Contains(chunk.Data.MapXy)) continue;
            if (!IsChunkVisible(chunk.Data.MapXy, frustum) && !IsStartupChunk(chunk.Data.MapXy)) continue;
            if (chunk.Data.DecorTransforms.Count > 0)
            {
                if (savedApplied >= _maxChunksPerFrame) continue;
                foreach (var kv in chunk.Data.DecorTransforms)
                {
                    Node3D[] nodes =
                        parent.DecorManager.GetDecorMeshes(parent.DecorManager.DecorInfos[kv.Key], kv.Value);
                    foreach (Node3D node in nodes) AddDecorToTree(node, chunk);
                    chunk.DecorNodes.AddRange(nodes);
                }

                chunk.AreDecorsSpawned = true;
                savedApplied++;
                continue;
            }

            int idx = GetNextAllowedDecorInChunk(0, chunk.Data.ProminentBiomeIds);
            if (idx >= 0)
            {
                _decorRequests.Add(new DecorThreadRequest(chunk.Data.MapXy, idx, new HashSet<Vector2I>()));
                dirty = true;
            }
            else
            {
                chunk.AreDecorsSpawned = true;
                parent.ChunkManager.SavedChunkData[chunk.Data.MapXy] = chunk.Data;
            }
        }

        if (dirty) SortDecorRequests(playerLoc, frustum);
        _decorRequestsDirty = false;
    }

    private void StartDecorThreads(Plane[] frustum)
    {
        int i = 0;
        while (i < _decorRequests.Count)
        {
            if (DecorThreads.Count >= _maxDecorThreads) break;
            DecorThreadRequest req = _decorRequests[i];
            if (DecorThreads.ContainsKey(req.Loc))
            {
                i++;
                continue;
            }

            if (!IsChunkVisible(req.Loc, frustum) && !IsStartupChunk(req.Loc))
            {
                i++;
                continue;
            }

            _decorRequests.RemoveAt(i);
            StartDecorThread(req);
        }
    }

    private void StartDecorThread(DecorThreadRequest req)
    {
        if (DecorThreads.ContainsKey(req.Loc)) return;
        DecorInfo decorD = parent.DecorManager.DecorInfos[req.DecorIdx];
        if (string.IsNullOrEmpty(decorD.DecorName) ||
            !parent.DecorManager.DecorScenes.ContainsKey(decorD.DecorName.ToLower())) return;
        Vector3 chunkCenter = new(req.Loc.X * GroundConstants.ChunkSize + GroundConstants.ChunkSize * 0.5f, 0,
            req.Loc.Y * GroundConstants.ChunkSize + GroundConstants.ChunkSize * 0.5f);
        DecorThreads[req.Loc] = Task.Run(() =>
            parent.DecorManager.GetDecorThreadResult(chunkCenter, [..req.Blocked], decorD, req.DecorIdx, req.Loc));
    }

    private void ApplyDecorResults(Plane[] frustum)
    {
        int applied = 0;
        while (_pendingDecorResults.Count > 0 && applied < _maxChunksPerFrame)
        {
            DecorThreadResult result = _pendingDecorResults[0];
            _pendingDecorResults.RemoveAt(0);
            if (!parent.ChunkManager.Chunks.TryGetValue(result.Loc, out GroundChunk? chunk) ||
                chunk.LodTier != GroundEnums.LodLevels.Close || chunk.AreDecorsSpawned) continue;
            chunk.Blocked = []; // store blocked state on chunk if needed
            applied++;
            Node3D[] nodes = parent.DecorManager.GetDecorMeshes(parent.DecorManager.DecorInfos[result.DecorIdx],
                result.DecorTransforms);
            foreach (Node3D node in nodes) AddDecorToTree(node, chunk);
            chunk.DecorNodes.AddRange(nodes);
            chunk.Data!.DecorTransforms[result.DecorIdx] = result.DecorTransforms;

            // Start next decor for this chunk
            int idx = GetNextAllowedDecorInChunk(result.DecorIdx + 1, chunk.Data.ProminentBiomeIds);
            if (idx != -1 && !chunk.Data.DecorTransforms.ContainsKey(idx))
            {
                DecorThreadRequest req = new(result.Loc, idx, result.Blocked);
                if (IsChunkVisible(result.Loc, frustum) || IsStartupChunk(result.Loc))
                {
                    if (!DecorThreads.ContainsKey(result.Loc) && DecorThreads.Count < _maxDecorThreads)
                        StartDecorThread(req);
                    else _decorRequests.Add(req);
                }
                else
                {
                    _decorRequests.Add(req);
                }
            }
            else
            {
                chunk.AreDecorsSpawned = true;
                parent.ChunkManager.SavedChunkData[chunk.Data.MapXy] = chunk.Data;
            }
        }
    }

    // HELPERS
    private void CollectPendingThreadResults<T>(Dictionary<Vector2I, Task<T>> dict, List<T> results)
    {
        _doneKeys.Clear();
        foreach (var kv in dict)
            if (kv.Value.IsCompleted)
                _doneKeys.Add(kv.Key);
        foreach (Vector2I key in _doneKeys)
        {
            results.Add(dict[key].Result);
            dict.Remove(key);
        }
    }

    public void SetSteadyValues()
    {
        _maxChunkThreads = GroundConstants.SteadyChunkThreads;
        _maxDecorThreads = GroundConstants.SteadyDecorThreads;
        _maxChunksPerFrame = GroundConstants.SteadyChunksPerFrame;
        _maxLodPerFrame = GroundConstants.SteadyLodPerFrame;
    }

    private int GetNextAllowedDecorInChunk(int decorIdx, IReadOnlyList<int> prominentBiomes)
    {
        while (decorIdx < parent.DecorManager.DecorInfos.Count)
        {
            string name = parent.DecorManager.DecorInfos[decorIdx].DecorName;
            foreach (int id in prominentBiomes)
                if (parent.BiomeManager.Biomes[id].AllowedDecorIds.Contains(name))
                    return decorIdx;
            decorIdx++;
        }

        return -1;
    }

    private bool IsStartupChunk(Vector2I loc)
    {
        if (parent.IsGroundStartupDone) return false;
        Vector2I d = loc - _lastPlayerLoc; // Chebyshev distance
        return Math.Max(Math.Abs(d.X), Math.Abs(d.Y)) <= GroundConstants.StartupRadius;
    }

    // SORTERS
    private void SortPendingChunkResults(Vector2I playerLoc, Plane[] frustum)
    {
        if (_pendingChunkResults.Count <= 1) return;
        foreach (ChunkThreadResult r in _pendingChunkResults) IsChunkVisible(r.ChunkData.MapXy, frustum);
        _pendingChunkResults.Sort((a, b) =>
        {
            if (a.LodTier != b.LodTier) return a.LodTier.CompareTo(b.LodTier);
            var aVis = _visibleChunksCache.Contains(a.ChunkData.MapXy);
            var bVis = _visibleChunksCache.Contains(b.ChunkData.MapXy);
            if (aVis != bVis) return aVis ? -1 : 1;
            return a.ChunkData.MapXy.DistanceTo(playerLoc).CompareTo(b.ChunkData.MapXy.DistanceTo(playerLoc));
        });
    }

    private void SortPendingDecorResults(Vector2I playerLoc, Plane[] frustum)
    {
        if (_pendingDecorResults.Count <= 1) return;
        foreach (DecorThreadResult r in _pendingDecorResults) IsChunkVisible(r.Loc, frustum);
        _pendingDecorResults.Sort((a, b) =>
        {
            bool aVis = _visibleChunksCache.Contains(a.Loc), bVis = _visibleChunksCache.Contains(b.Loc);
            if (aVis != bVis) return aVis ? -1 : 1;
            return a.Loc.DistanceTo(playerLoc).CompareTo(b.Loc.DistanceTo(playerLoc));
        });
    }

    private void SortDecorRequests(Vector2I playerLoc, Plane[] frustum)
    {
        if (_decorRequests.Count <= 1) return;
        foreach (DecorThreadRequest r in _decorRequests) IsChunkVisible(r.Loc, frustum);
        _decorRequests.Sort((a, b) =>
        {
            bool aVis = _visibleChunksCache.Contains(a.Loc), bVis = _visibleChunksCache.Contains(b.Loc);
            if (aVis != bVis) return aVis ? -1 : 1;
            return a.Loc.DistanceTo(playerLoc).CompareTo(b.Loc.DistanceTo(playerLoc));
        });
    }

    private void SortChunkRequests(Plane[] frustum)
    {
        foreach (ChunkThreadRequest r in _chunkRequests) IsChunkVisible(r.Loc, frustum);
        _chunkRequests.Sort((a, b) =>
        {
            if (a.LodTier != b.LodTier) return a.LodTier.CompareTo(b.LodTier);
            bool aVis = _visibleChunksCache.Contains(a.Loc), bVis = _visibleChunksCache.Contains(b.Loc);
            if (aVis != bVis) return aVis ? -1 : 1;
            return a.Dist.CompareTo(b.Dist);
        });
    }

    private bool IsChunkVisible(Vector2I loc, Plane[] frustum)
    {
        if (_visibleChunksCache.Contains(loc)) return true;

        // test chunk visibility
        bool result = true;
        if (frustum.Length == 0) return true;
        float cs = GroundConstants.ChunkSize;
        Aabb aabb = new(new Vector3(loc.X * cs, GroundConstants.HeightMin, loc.Y * cs),
            new Vector3(cs, GroundConstants.HeightMax - GroundConstants.HeightMin, cs));
        foreach (Plane plane in frustum)
        {
            if (plane.IsPointOver(aabb.GetSupport(-plane.Normal)))
            {
                result = false;
                break;
            }
        }

        if (result) _visibleChunksCache.Add(loc);
        return result;
    }

    // ADD TO TREE
    private void AddChunkToTree(GroundChunk chunk)
    {
        parent.GetNode("Chunks").AddChild(chunk);
    }

    private void AddDecorToTree(Node3D node, GroundChunk chunk)
    {
        // Add decor under the chunk's Decors node so decors are grouped per-chunk
        Node3D decorsNode = chunk.GetNode<Node3D>("Decors");
        decorsNode.AddChild(node);
    }
}