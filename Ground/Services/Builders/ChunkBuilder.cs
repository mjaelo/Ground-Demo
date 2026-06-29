using System;
using System.Collections.Generic;
using Godot;
using Godot.Collections;
using GroundDemo.General.Services;
using GroundDemo.Ground.GroundDatas;
using GroundDemo.Ground.Scenes;
using Array = Godot.Collections.Array;

namespace GroundDemo.Ground.Services.Builders;

public static class ChunkBuilder
{
    // Cached Materials
    private static readonly PackedScene ChunkScene = GD.Load<PackedScene>("res://Ground/Scenes/GroundChunk.tscn");
    private static readonly ShaderMaterial GroundShaderMaterial = BuildShaderMaterial();
    private static readonly QuadMesh WaterMesh = new() { Size = new Vector2(GroundConstants.ChunkSize, GroundConstants.ChunkSize) };
    private static readonly StandardMaterial3D WaterMaterial = new()
    {
        AlbedoColor = new Color(0.0f, 0.35f, 0.65f, 0.25f),
        Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
        Roughness = 0.2f,
        Metallic = 0.0f
    };
    
    // CHUNK BUILDING
    public static GroundChunk BuildChunk(ChunkData chunkData, GroundEnums.LodLevels lodTier)
    {
        // Create material with splatmap textures
        var idxTex = ImageTexture.CreateFromImage(chunkData.SplatIndices);
        var wgtTex = ImageTexture.CreateFromImage(chunkData.SplatWeights);
        var shaderMaterial = (ShaderMaterial)GroundShaderMaterial.Duplicate();
        shaderMaterial.SetShaderParameter("splat_indices", idxTex);
        shaderMaterial.SetShaderParameter("splat_weights", wgtTex);

        // Instance GroundChunk scene and assign mesh/collision/water into it
        if (ChunkScene.Instantiate() is not GroundChunk chunkNode) throw new Exception("Failed to instance GroundChunk scene.");
        MeshInstance3D mi = chunkNode.GetNode<MeshInstance3D>("MeshInstance3D");
        mi.Mesh = BuildChunkMeshFromHeightMap(chunkData.Heightmap);
        mi.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
        float offsetX = chunkData.MapXy.X * GroundConstants.ChunkSize;
        float offsetZ = chunkData.MapXy.Y * GroundConstants.ChunkSize;
        mi.Position = new Vector3(offsetX, 0, offsetZ);
        mi.MaterialOverride = shaderMaterial;

        // GPU-level distance cull for FAR-LOD tiles
        if (lodTier == GroundEnums.LodLevels.Far)
        {
            mi.VisibilityRangeEnd = GroundConstants.FarLodVisibilityRange;
            mi.VisibilityRangeEndMargin = GroundConstants.ChunkSize * 2.0f;
        }

        // add children water and collision
        if (chunkData.HasWater)
        {
            var wmi = new MeshInstance3D
            {
                Mesh = WaterMesh,
                MaterialOverride = WaterMaterial,
                RotationDegrees = new Vector3(-90.0f, 0.0f, 0.0f),
                Position = new Vector3(
                    offsetX + GroundConstants.ChunkSize * 0.5f, 
                    GroundConstants.WaterSurfaceLevel,
                    offsetZ + GroundConstants.ChunkSize * 0.5f
                ),
                CastShadow = GeometryInstance3D.ShadowCastingSetting.Off
            };
            chunkNode.AddChild(wmi);
            chunkNode.Water = wmi;
        }

        StaticBody3D? body = null;
        if (lodTier == GroundEnums.LodLevels.Close)
        {
            body = GetCollision(chunkData.Heightmap);
            body.Position = new Vector3(offsetX, 0, offsetZ);
            chunkNode.AddChild(body);
        }

        // populate and return the instantiated GroundChunk
        chunkNode.Data = chunkData;
        chunkNode.MeshInstance = mi;
        chunkNode.CollisionBody = body;
        chunkNode.LodTier = lodTier;
        chunkNode.AreDecorsSpawned = false;
        return chunkNode;
    }

    private static StaticBody3D GetCollision(Image heightmap)
    {
        int res = heightmap.GetWidth();
        float cellSize = (float)GroundConstants.ChunkSize / (res - 1);
        var colShape = new CollisionShape3D
        {
            Shape = BuildHeightmapShape(heightmap, res),
            Scale = new Vector3(cellSize, 1.0f, cellSize),
            Position = new Vector3(GroundConstants.ChunkSize * 0.5f, 0.0f, GroundConstants.ChunkSize * 0.5f)
        };
        var body = new StaticBody3D
        {
            CollisionLayer = 1,
            CollisionMask = 0
        };
        body.AddChild(colShape);
        return body;
    }

    private static HeightMapShape3D BuildHeightmapShape(Image img, int res)
    {
        var heights = new float[res * res];
        for (int z = 0; z < res; z++)
        {
            for (int x = 0; x < res; x++)
            {
                heights[z * res + x] = img.GetPixel(x, z).R;
            }
        }

        return new HeightMapShape3D
        {
            MapWidth = res,
            MapDepth = res,
            MapData = heights
        };
    }

    private static ArrayMesh BuildChunkMeshFromHeightMap(Image heightmap)
    {
        int res = heightmap.GetWidth();
        int vertCount = res * res;
        int triCount = (res - 1) * (res - 1) * 2;
        float inv = 1.0f / (res - 1);
        float cs = GroundConstants.ChunkSize;

        Vector3[] verts = new Vector3[vertCount];
        Vector2[] uvs = new Vector2[vertCount];
        Vector3[] normals = new Vector3[vertCount];
        int[] indices = new int[triCount * 3];

        // Fill vertices and UVs
        for (int y = 0; y < res; y++)
        {
            for (int x = 0; x < res; x++)
            {
                int idx = y * res + x;
                float u = x * inv;
                float v = y * inv;
                verts[idx] = new Vector3(u * cs, heightmap.GetPixel(x, y).R, v * cs);
                uvs[idx] = new Vector2(u, v);
            }
        }

        // Fill indices
        int ii = 0;
        for (int y = 0; y < res - 1; y++)
        {
            for (int x = 0; x < res - 1; x++)
            {
                int i00 = y * res + x;
                int i10 = i00 + 1;
                int i01 = i00 + res;
                int i11 = i01 + 1;
                indices[ii++] = i00; indices[ii++] = i10; indices[ii++] = i01;
                indices[ii++] = i11; indices[ii++] = i01; indices[ii++] = i10;
            }
        }

        // Compute smooth vertex normals from face normals
        for (int i = 0; i < indices.Length; i += 3)
        {
            Vector3 a = verts[indices[i]], b = verts[indices[i + 1]], c = verts[indices[i + 2]];
            Vector3 faceNormal = (c - a).Cross(b - a);
            normals[indices[i]] += faceNormal;
            normals[indices[i + 1]] += faceNormal;
            normals[indices[i + 2]] += faceNormal;
        }
        for (int i = 0; i < vertCount; i++) normals[i] = normals[i].Normalized();

        var arrays = new Array();
        arrays.Resize((int)Mesh.ArrayType.Max);
        arrays[(int)Mesh.ArrayType.Vertex] = verts;
        arrays[(int)Mesh.ArrayType.Normal] = normals;
        arrays[(int)Mesh.ArrayType.TexUV] = uvs;
        arrays[(int)Mesh.ArrayType.Index] = indices;

        ArrayMesh mesh = new ArrayMesh();
        mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
        return mesh;
    }
    
    // TEXTURE SHADER BUILDING
    private static ShaderMaterial BuildShaderMaterial()
    {
        List<Image> imagesList = LoadTextureImages();

        Texture2DArray? texArrayRes = null;
        if (imagesList.Count > 0)
        {
            Texture2DArray texArr = new Texture2DArray();
            Error err = texArr.CreateFromImages(new Array<Image>(imagesList));
            if (err == Error.Ok) texArrayRes = texArr;
            else GD.PushError($"Failed to create Texture2DArray: {err}");
        }

        Shader shader = GD.Load<Shader>(GroundConstants.TerrainShaderPath);
        ShaderMaterial shaderMat = new ShaderMaterial { Shader = shader };
        if (texArrayRes != null) shaderMat.SetShaderParameter("terrain_textures", texArrayRes);
        shaderMat.SetShaderParameter("texture_scale", GroundConstants.TextureScale);
        return shaderMat;
    }

    private static List<Image> LoadTextureImages()
    {
        // load textures table from GroundConstants.TexturesFilePath
        List<string> imagePaths = SerializationService.LoadArray<string>(
            GroundConstants.TexturesFilePath, 
            "textures", 
            s => SerializationService.Deserialize<string>(s) ?? string.Empty
        );        
        List<Image> imagesList = new();
        foreach (string path in imagePaths)
        {
            Image image = new Image();
            if (image.Load(ProjectSettings.GlobalizePath(path)) != Error.Ok) continue;
            image.GenerateMipmaps();
            imagesList.Add(image);

        }
        return imagesList;
    }

}