class_name DrillShape
extends RefCounted
## A drawn form (line, arc, block...) that marchers can be attached to.
## Shapes belong to the whole show. Each set keeps its own list of attached
## marchers (spaced evenly along it, in order), its own rotation, and whether
## the shape is hidden there.

const TYPE_NAMES := {
	"line": "Line",
	"rect": "Rectangle",
	"ellipse": "Ellipse",
	"polygon": "Polygon",
	"curve": "Curve",
	"freeform": "Freeform",
}

var id := 0
var name := ""
var type := "line"
## Control points in field yards. For "rect" these are the 4 corners,
## for "ellipse" the two corners of its bounding box.
var points := PackedVector2Array()
## Only used by polygon / curve / freeform (rect and ellipse are always closed).
var closed := false


func type_name() -> String:
	return str(TYPE_NAMES.get(type, type))


## True if both shapes have the same form (used when loading old files).
func same_form(o: DrillShape) -> bool:
	return type == o.type and closed == o.closed and points == o.points


func copy() -> DrillShape:
	var s := DrillShape.new()
	s.id = id
	s.name = name
	s.type = type
	s.points = points.duplicate()
	s.closed = closed
	return s


func to_dict() -> Dictionary:
	var pts := []
	for p in points:
		pts.append([p.x, p.y])
	return {
		"id": id,
		"name": name,
		"type": type,
		"points": pts,
		"closed": closed,
	}


static func from_dict(d: Dictionary) -> DrillShape:
	var s := DrillShape.new()
	s.id = int(d.get("id", 0))
	s.name = str(d.get("name", ""))
	s.type = str(d.get("type", "line"))
	s.closed = bool(d.get("closed", false))
	for p in d.get("points", []):
		s.points.append(Vector2(float(p[0]), float(p[1])))
	return s
