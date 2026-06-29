using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Godot;

namespace GroundDemo.General.Services;

public static class SerializationService
{
	// Options for serialization (with reference handling for circular references)
	private static readonly JsonSerializerOptions SerializeOptions = new()
	{
		DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
		IncludeFields = true,
		Converters = { new JsonStringEnumConverter(), new Vector2IConverter() }
	};

	private class Vector2IConverter : JsonConverter<Vector2I>
	{
		public override Vector2I Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
		{
			using var doc = JsonDocument.ParseValue(ref reader);
			var array = doc.RootElement.EnumerateArray().Select(x => x.GetInt32()).ToList();
			return new Vector2I(array[0], array[1]);
		}

		public override void Write(Utf8JsonWriter writer, Vector2I value, JsonSerializerOptions options)
		{
			writer.WriteStartArray();
			writer.WriteNumberValue(value.X);
			writer.WriteNumberValue(value.Y);
			writer.WriteEndArray();
		}
	}

	public static string Serialize<T>(T obj) =>
		JsonSerializer.Serialize(obj, SerializeOptions);

	public static T? Deserialize<T>(string json) =>
		JsonSerializer.Deserialize<T>(json, SerializeOptions);

	// Opens a Godot res:// JSON file and deserializes the named array using a per-element factory.
	public static List<T> LoadArray<T>(string resPath, string arrayKey, Func<string, T> factory)
	{
		using var file = FileAccess.Open(resPath, FileAccess.ModeFlags.Read);
		if (file == null) return [];
		using var doc = JsonDocument.Parse(file.GetAsText());
		if (!doc.RootElement.TryGetProperty(arrayKey, out var arr) || arr.ValueKind != JsonValueKind.Array) return [];
		return arr.EnumerateArray().Select(el => factory(el.GetRawText())).ToList();
	}
}

