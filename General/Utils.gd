extends Object
class_name Utils

# ── JSON Handling ─────────────────────────────────────────────────────────
## Loads a JSON file and returns its root dictionary, or null on error.
static func load_json_dict(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_warning("Utils: File not found: %s" % file_path)
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("Utils: Failed to open file: %s" % file_path)
		return {}
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("Utils: JSON parse error in %s at line %d: %s" % [file_path, json.get_error_line(), json.get_error_message()])
		return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Utils: Expected JSON object in %s" % file_path)
		return {}
	return data

## Converts an array of dictionaries to an array of Data objects using the class's from_dict method.
static func array_from_json(data_array: Array, data_class: Object) -> Array:
	var result: Array = []
	for entry in data_array:
		if typeof(entry) == TYPE_DICTIONARY:
			var obj = data_class.from_dict(entry)
			if obj:
				result.append(obj)
	return result

## Loads a JSON file, extracts the array at array_key, converts it to data_class objects, and returns the array.
static func load_from_json(json_path: String, data_class: Object, array_key: String) -> Array:
	var data := load_json_dict(json_path)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Utils: Expected dictionary in %s" % json_path)
		return []
	var arr: Array = data.get(array_key, [])
	if typeof(arr) != TYPE_ARRAY:
		push_error("Utils: Expected array for key '%s' in %s" % [array_key, json_path])
		return []
	return array_from_json(arr, data_class)