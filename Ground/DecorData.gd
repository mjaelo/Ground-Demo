extends Resource
class_name DecorData 
# TODO should it be DecorInfo instead, as it holds info about decor types and not about a specific decor?

## Human-readable label matching the Terrain3DMeshAsset name or scene file stem.
@export var asset_name: String = ""
## Relative selection weight when competing against other eligible layers (0–100).
@export_range(0.0, 100.0) var weight: float = 1.0
## Probability (0–1) that this layer is even considered at a given grid point,
## evaluated before weight-based competition. Use low values for rare structures.
@export_range(0.0, 1.0) var spawn_chance: float = 1.0
## Maximum terrain slope (degrees) at which this decor may appear.
@export var max_slope: float = 90.0
## Minimum world-space Y height at which this decor may appear.
@export var min_height: float = -1e6
## Maximum world-space Y height at which this decor may appear.
@export var max_height: float = 1e6
## World-space XZ size of the asset in meters (e.g. Vector2i(20, 20)).
## Neighbouring grid points within this area will not have other assets placed on them.
## (0, 0) means single-point with no blocking.
@export var mesh_size: Vector2i = Vector2i.ZERO
## Maximum distance (metres) from the camera at which this asset is rendered.
## Smaller values hide the mesh sooner as the camera moves away, saving performance.
## Set to 0 to use the default (no override — the asset keeps its existing lod range).
@export var visibility_range: float = 0.0

static func from_dict(d: Dictionary) -> DecorData:
	var r := DecorData.new()
	r.asset_name  = str(d.get("name",         ""))
	r.weight      = float(d.get("weight",       1.0))
	r.spawn_chance = float(d.get("spawn_chance", 1.0))
	r.max_slope   = float(d.get("max_slope",    90.0))
	if d.has("min_height"):
		r.min_height = float(d["min_height"])
	if d.has("max_height"):
		r.max_height = float(d["max_height"])
	if d.has("mesh_size"):
		var ms: Variant = d["mesh_size"]
		if typeof(ms) == TYPE_ARRAY and ms.size() >= 2:
			r.mesh_size = Vector2i(int(ms[0]), int(ms[1]))
	if d.has("visibility_range"):
		r.visibility_range = float(d["visibility_range"])
	return r
