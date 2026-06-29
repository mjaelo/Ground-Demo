using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Godot;

namespace GroundDemo.Ground.Services;

/// Resolves a generator script path to an <see cref="Action{Node3D}"/> by finding the static Build method via reflection.
/// The reflection scan is performed once at startup and cached for all subsequent calls.
public static class GeneratorScriptResolver
{
    private const string TargetNamespace = "GroundDemo.Ground";

    // Pre-built lookup: type simple name -> bound Action<Node3D> delegate
    private static readonly Dictionary<string, Action<Node3D>> BuildActions = BuildActionMap();

    private static Dictionary<string, Action<Node3D>> BuildActionMap()
    {
        const BindingFlags flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static;
        return AppDomain.CurrentDomain.GetAssemblies()
            .SelectMany(a => a.GetTypes())
            .Where(t => (t.Namespace ?? string.Empty).StartsWith(TargetNamespace, StringComparison.Ordinal))
            .Select(t => (Type: t, Method: t.GetMethod("Build", flags)))
            .Where(x => x.Method != null)
            .ToDictionary(
                x => x.Type.Name,
                x => (Action<Node3D>)(n => x.Method!.Invoke(null, [n]))
            );
    }

    public static Action<Node3D>? Resolve(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        string baseName = System.IO.Path.GetFileNameWithoutExtension(path);
        return BuildActions.GetValueOrDefault(baseName);
    }
}


