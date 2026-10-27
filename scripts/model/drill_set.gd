class_name DrillSet
extends RefCounted
## A snapshot of every marcher's spot. `counts` is the number of counts it
## takes to move from the previous set into this one, at `tempo` bpm.
##
## Shapes live on the show; a set records how it uses them: who is attached
## (in order), how far they're rotated around, which are hidden, and its own
## points for any shape that's been moved or reshaped in this set.

var name := "Set 1"
var counts := 8
var tempo := 120.0
var notes := ""
var positions := {}  # marcher id (int) -> Vector2, in yards
var facings := {}  # marcher id (int) -> float, degrees (0 = facing the front sideline)
var attached := {}  # shape id (int) -> Array[int] of marcher ids, in order along the shape
var offsets := {}  # shape id (int) -> float, rotation around a closed shape (0..1)
var hidden := {}  # shape id (int) -> true, for shapes hidden in this set
var forms := {}  # shape id (int) -> PackedVector2Array, this set's own points


func get_pos(id: int) -> Vector2:
	return positions.get(id, Vector2.ZERO)


func get_facing(id: int) -> float:
	return float(facings.get(id, 0.0))


## The marchers on a shape in this set. The array is live: changes stick.
func on_shape(shape_id: int) -> Array[int]:
	if not attached.has(shape_id):
		var empty: Array[int] = []
		attached[shape_id] = empty
	return attached[shape_id]


func count_on(shape_id: int) -> int:
	return (attached[shape_id] as Array).size() if attached.has(shape_id) else 0


## The id of the shape a marcher is attached to here, or -1.
func shape_id_of(marcher_id: int) -> int:
	for sid in attached:
		if (attached[sid] as Array).has(marcher_id):
			return sid
	return -1


func offset_of(shape_id: int) -> float:
	return float(offsets.get(shape_id, 0.0))


func is_shown(shape_id: int) -> bool:
	return not hidden.has(shape_id)


func set_shown(shape_id: int, on: bool) -> void:
	if on:
		hidden.erase(shape_id)
	else:
		hidden[shape_id] = true


## Drops everything this set knows about a shape.
func forget_shape(shape_id: int) -> void:
	attached.erase(shape_id)
	offsets.erase(shape_id)
	hidden.erase(shape_id)
	forms.erase(shape_id)


func copy() -> DrillSet:
	var s := DrillSet.new()
	s.name = name
	s.counts = counts
	s.tempo = tempo
	s.notes = notes
	s.positions = positions.duplicate()
	s.facings = facings.duplicate()
	for sid in attached:
		var ids: Array[int] = []
		ids.assign(attached[sid])
		s.attached[sid] = ids
	s.offsets = offsets.duplicate()
	s.hidden = hidden.duplicate()
	for sid in forms:
		s.forms[sid] = (forms[sid] as PackedVector2Array).duplicate()
	return s


func to_dict() -> Dictionary:
	var pos := {}
	for id in positions:
		var p: Vector2 = positions[id]
		pos[str(id)] = [p.x, p.y]
	var fac := {}
	for id in facings:
		fac[str(id)] = facings[id]
	var att := {}
	for sid in attached:
		if not (attached[sid] as Array).is_empty():
			att[str(sid)] = (attached[sid] as Array).duplicate()
	var off := {}
	for sid in offsets:
		off[str(sid)] = offsets[sid]
	var frm := {}
	for sid in forms:
		var pts := []
		for p in forms[sid]:
			pts.append([p.x, p.y])
		frm[str(sid)] = pts
	return {
		"name": name,
		"counts": counts,
		"tempo": tempo,
		"notes": notes,
		"positions": pos,
		"facings": fac,
		"attached": att,
		"offsets": off,
		"hidden": hidden.keys(),
		"forms": frm,
	}


## Old files (version 1) kept whole shapes in each set; DrillShow.from_dict
## converts those, so this only reads the current layout.
static func from_dict(d: Dictionary) -> DrillSet:
	var s := DrillSet.new()
	s.name = str(d.get("name", "Set"))
	s.counts = int(d.get("counts", 8))
	s.tempo = float(d.get("tempo", 120.0))
	s.notes = str(d.get("notes", ""))
	var pos: Dictionary = d.get("positions", {})
	for k in pos:
		var p: Array = pos[k]
		s.positions[int(k)] = Vector2(float(p[0]), float(p[1]))
	var fac: Dictionary = d.get("facings", {})
	for k in fac:
		s.facings[int(k)] = float(fac[k])
	var att: Dictionary = d.get("attached", {})
	for k in att:
		var ids: Array[int] = []
		for m in att[k]:
			ids.append(int(m))
		s.attached[int(k)] = ids
	var off: Dictionary = d.get("offsets", {})
	for k in off:
		s.offsets[int(k)] = float(off[k])
	for k in d.get("hidden", []):
		s.hidden[int(k)] = true
	var frm: Dictionary = d.get("forms", {})
	for k in frm:
		var pts := PackedVector2Array()
		for p in frm[k]:
			pts.append(Vector2(float(p[0]), float(p[1])))
		s.forms[int(k)] = pts
	return s
