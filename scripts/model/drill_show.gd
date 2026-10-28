class_name DrillShow
extends RefCounted
## The whole show: marchers, sets (in order), and preview settings.

const EPS := 0.0005

## Step-size limits in yards per count at 120 bpm (scaled for other tempos).
const STEP_LARGE := 5.0 / 6.0  # 6-to-5: big but doable
const STEP_LIMIT := 1.0  # 5-to-5: unrealistic

var title := "Untitled Show"
var marchers: Array[DrillMarcher] = []
var sets: Array[DrillSet] = []
var shapes: Array[DrillShape] = []  ## shared by every set
var audio_path := ""
var audio_offset := 0.0
var hash_style := "HS"
var next_marcher_id := 1
var next_shape_id := 1


func find_marcher(id: int) -> DrillMarcher:
	for m in marchers:
		if m.id == id:
			return m
	return null


# ---------------------------------------------------------------- timing

## Seconds spent moving into set i (the first set takes no time).
func set_duration(i: int) -> float:
	if i <= 0 or i >= sets.size():
		return 0.0
	var s := sets[i]
	return float(maxi(s.counts, 1)) * 60.0 / maxf(s.tempo, 1.0)


## Time (seconds) at which each set is reached.
func set_times() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var t := 0.0
	for i in sets.size():
		t += set_duration(i)
		out.append(t)
	return out


func duration() -> float:
	var ts := set_times()
	return ts[ts.size() - 1] if ts.size() > 0 else 0.0


## Total counts before reaching set i.
func counts_before(i: int) -> int:
	var c := 0
	for k in range(1, mini(i, sets.size() - 1) + 1):
		c += maxi(sets[k].counts, 1)
	return c


func _at(i: int) -> Dictionary:
	return {"at_set": true, "set": i, "from": i, "frac": 0.0, "count": 0.0}


## Where in the show time `t` falls. "set" is the set being shown (or moved
## into, when "at_set" is false), "from" the set being left.
func locate(t: float) -> Dictionary:
	var ts := set_times()
	var n := ts.size()
	if n == 0 or t <= ts[0] + EPS:
		return _at(0)
	for i in range(1, n):
		if t < ts[i] - EPS:
			var d := ts[i] - ts[i - 1]
			var f := clampf((t - ts[i - 1]) / d, 0.0, 1.0) if d > 0.0 else 1.0
			return {
				"at_set": false,
				"set": i,
				"from": i - 1,
				"frac": f,
				"count": f * float(maxi(sets[i].counts, 1)),
			}
		if t <= ts[i] + EPS:
			return _at(i)
	return _at(n - 1)


func positions_at(loc: Dictionary) -> Dictionary:
	if sets.is_empty():
		return {}
	var to: DrillSet = sets[int(loc["set"])]
	if bool(loc["at_set"]):
		return to.positions
	var from: DrillSet = sets[int(loc["from"])]
	var f: float = loc["frac"]
	var out := {}
	for m in marchers:
		out[m.id] = from.get_pos(m.id).lerp(to.get_pos(m.id), f)
	return out


func facing_at(loc: Dictionary, id: int) -> float:
	var to: DrillSet = sets[int(loc["set"])]
	if bool(loc["at_set"]):
		return to.get_facing(id)
	var from: DrillSet = sets[int(loc["from"])]
	var a := deg_to_rad(from.get_facing(id))
	var b := deg_to_rad(to.get_facing(id))
	return rad_to_deg(lerp_angle(a, b, float(loc["frac"])))


# ---------------------------------------------------------------- step size

## Yards per count marcher `id` covers moving into set i.
func move_step(i: int, id: int) -> float:
	if i <= 0 or i >= sets.size():
		return 0.0
	var d := sets[i - 1].get_pos(id).distance_to(sets[i].get_pos(id))
	return d / float(maxi(sets[i].counts, 1))


## Faster tempos make big steps harder; slower ones allow a bit more.
static func tempo_factor(tempo: float) -> float:
	return clampf(sqrt(120.0 / maxf(tempo, 1.0)), 0.7, 1.3)


## 0 = fine, 1 = large step, 2 = unrealistic.
func step_level(i: int, id: int) -> int:
	if i <= 0 or i >= sets.size():
		return 0
	var st := move_step(i, id)
	var f := tempo_factor(sets[i].tempo)
	if st > STEP_LIMIT * f:
		return 2
	if st > STEP_LARGE * f:
		return 1
	return 0


## e.g. "6.4-to-5" (steps per 5 yards), or "hold" when not moving.
static func step_name(yards_per_count: float) -> String:
	if yards_per_count < 0.01:
		return "hold"
	return "%s-to-5" % String.num(snappedf(5.0 / yards_per_count, 0.1))


# ---------------------------------------------------------------- inaccurate preview

## A repeatable random miss for marcher `id` at set i: up to `amount` yards
## off their spot (biased toward small misses) and a few degrees off facing.
static func sloppy_miss(i: int, id: int, amount: float, seed: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, i, id])
	var ang := rng.randf() * TAU
	var r := amount * sqrt(rng.randf()) * rng.randf()
	var face := rng.randf_range(-1.0, 1.0) * clampf(amount * 8.0, 0.0, 10.0)
	return Vector3(cos(ang) * r, sin(ang) * r, face)


## Like positions_at, but everyone misses their dots a little at every set.
func sloppy_positions_at(loc: Dictionary, amount: float, seed: int) -> Dictionary:
	var out := {}
	if sets.is_empty():
		return out
	var i := int(loc["set"])
	var at_set := bool(loc["at_set"])
	var from := int(loc["from"])
	var f: float = loc["frac"]
	for m in marchers:
		var b := sets[i].get_pos(m.id) + _xy(sloppy_miss(i, m.id, amount, seed))
		if at_set:
			out[m.id] = b
		else:
			var a := sets[from].get_pos(m.id) + _xy(sloppy_miss(from, m.id, amount, seed))
			out[m.id] = a.lerp(b, f)
	return out


func sloppy_facing_at(loc: Dictionary, id: int, amount: float, seed: int) -> float:
	var i := int(loc["set"])
	var off := sloppy_miss(i, id, amount, seed).z
	if not bool(loc["at_set"]):
		off = lerpf(sloppy_miss(int(loc["from"]), id, amount, seed).z, off, float(loc["frac"]))
	return facing_at(loc, id) + off


static func _xy(v: Vector3) -> Vector2:
	return Vector2(v.x, v.y)


# ---------------------------------------------------------------- marchers

func unique_label(prefix: String) -> String:
	var used := {}
	for m in marchers:
		used[m.label] = true
	var n := 1
	while used.has(prefix + str(n)):
		n += 1
	return prefix + str(n)


func add_marcher(section: String, pos: Vector2) -> DrillMarcher:
	var m := DrillMarcher.new()
	m.id = next_marcher_id
	next_marcher_id += 1
	m.section = section
	m.label = unique_label(Sections.prefix(section))
	marchers.append(m)
	for s in sets:
		s.positions[m.id] = pos
	return m


func remove_marcher(id: int) -> void:
	for i in marchers.size():
		if marchers[i].id == id:
			marchers.remove_at(i)
			break
	for s in sets:
		s.positions.erase(id)
		s.facings.erase(id)
		var sid := s.shape_id_of(id)
		if sid != -1:
			s.on_shape(sid).erase(id)
			var sh := find_shape(sid)
			if sh != null:
				relayout(s, sh)


# ---------------------------------------------------------------- shapes

func find_shape(id: int) -> DrillShape:
	for sh in shapes:
		if sh.id == id:
			return sh
	return null


## The shape marcher `mid` is attached to in set `s`, or null.
func shape_of(s: DrillSet, mid: int) -> DrillShape:
	var sid := s.shape_id_of(mid)
	return find_shape(sid) if sid != -1 else null


## The shape as it is in set `s`: its own points there, or the shared ones.
func form(s: DrillSet, sh: DrillShape) -> DrillShape:
	if s == null or not s.forms.has(sh.id):
		return sh
	var f := sh.copy()
	f.points = (s.forms[sh.id] as PackedVector2Array).duplicate()
	return f


func has_own_form(s: DrillSet, sh: DrillShape) -> bool:
	return s.forms.has(sh.id)


## Shapes drawn (and usable) in set `s`.
func shapes_shown(s: DrillSet) -> Array[DrillShape]:
	var out: Array[DrillShape] = []
	for sh in shapes:
		if s.is_shown(sh.id):
			out.append(sh)
	return out


func add_shape(sh: DrillShape) -> void:
	sh.id = next_shape_id
	next_shape_id += 1
	if sh.name == "":
		sh.name = "%s %d" % [sh.type_name(), sh.id]
	shapes.append(sh)


## Deletes a shape from the show. Marchers on it stay where they are.
func remove_shape(id: int) -> void:
	var sh := find_shape(id)
	if sh != null:
		shapes.erase(sh)
	for s in sets:
		s.forget_shape(id)


## Puts every marcher attached to `sh` in set `s` at its evenly spaced spot.
func relayout(s: DrillSet, sh: DrillShape) -> void:
	var ids := s.on_shape(sh.id)
	var pts := ShapeGeom.distribute(form(s, sh), ids.size(), s.offset_of(sh.id))
	for k in ids.size():
		s.positions[ids[k]] = pts[k]


## After a shape changes everywhere (e.g. open/closed): re-space its marchers in every set.
func relayout_everywhere(sh: DrillShape) -> void:
	for s in sets:
		if s.count_on(sh.id) > 0:
			relayout(s, sh)


## Removes the given marchers from any shapes in set `s`. Returns true if any were attached.
func detach(s: DrillSet, ids: Array[int]) -> bool:
	var changed := false
	for sid in s.attached.keys():
		var on := s.on_shape(sid)
		var hit := false
		for id in ids:
			if on.has(id):
				on.erase(id)
				hit = true
		if hit:
			changed = true
			var sh := find_shape(sid)
			if sh != null:
				relayout(s, sh)
	return changed


## Attaches marchers to a shape in set `s`. Each one is slotted in by where it
## sits along the shape (its current spot, or `hints[id]` if given), so
## dropping a marcher near one end puts it at that end.
func assign(s: DrillSet, sh: DrillShape, ids: Array[int], hints := {}) -> void:
	for sid in s.attached.keys():
		if sid == sh.id:
			continue
		var on := s.on_shape(sid)
		var hit := false
		for id in ids:
			if on.has(id):
				on.erase(id)
				hit = true
		if hit:
			var other := find_shape(sid)
			if other != null:
				relayout(s, other)

	var poly := ShapeGeom.sample(form(s, sh))
	var cum := ShapeGeom.cumulative(poly)
	var length := cum[cum.size() - 1] if cum.size() > 0 else 0.0
	var mine := s.on_shape(sh.id)
	var remaining: Array[int] = []
	for id in mine:
		if not ids.has(id):
			remaining.append(id)
	var params := ShapeGeom.params(remaining.size(), length, ShapeGeom.is_closed(sh), s.offset_of(sh.id))
	var entries := []
	for k in remaining.size():
		entries.append([params[k], 0, remaining[k]])
	for j in ids.size():
		var id := ids[j]
		var p: Vector2 = hints.get(id, s.get_pos(id))
		var proj := ShapeGeom.project(poly, cum, p)
		entries.append([float(proj["s"]), j + 1, id])
	entries.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	mine.clear()
	for e in entries:
		mine.append(int(e[2]))
	relayout(s, sh)


## Reorders the marchers on `sh` in set i so the total (and so average)
## distance from their spots in the previous set is as small as possible.
## Closed shapes also try rotating everyone around the loop. Returns false
## if there's nothing to do (first set, or fewer than two marchers).
func order_by_moves(i: int, sh: DrillShape) -> bool:
	if i <= 0 or i >= sets.size():
		return false
	var s := sets[i]
	var prev := sets[i - 1]
	var ids := s.on_shape(sh.id)
	var n := ids.size()
	if n < 2:
		return false
	var f := form(s, sh)
	var poly := ShapeGeom.sample(f)
	var cum := ShapeGeom.cumulative(poly)
	if cum.is_empty():
		return false
	var closed := ShapeGeom.is_closed(f)
	var from := PackedVector2Array()
	for id in ids:
		from.append(prev.get_pos(id))

	# Spots repeat every 1/n of the way round, so only offsets in [0, 1/n) matter.
	var offsets := PackedFloat64Array([s.offset_of(sh.id)])
	# Pinned-corner spots don't move with small rotations, so one try is enough.
	if closed and not ShapeGeom.pins_corners(f, n):
		var tries := clampi(4000 / (n * n) + 8, 8, 48)
		for k in tries:
			offsets.append((float(k) / tries) / n)

	var best_cost := INF
	var best_off := s.offset_of(sh.id)
	var best_match := PackedInt32Array()
	var cost := PackedFloat64Array()
	cost.resize(n * n)
	for off in offsets:
		var spots := PackedVector2Array()
		for d in ShapeGeom.slot_params(f, cum, n, off):
			spots.append(ShapeGeom.point_at(poly, cum, d))
		for r in n:
			for c in n:
				cost[r * n + c] = spots[r].distance_to(from[c])
		var pairing := Assignment.solve(cost, n)
		var sum := 0.0
		for r in n:
			sum += cost[r * n + pairing[r]]
		if sum < best_cost - 1e-6:
			best_cost = sum
			best_off = off
			best_match = pairing

	var order: Array[int] = []
	for r in n:
		order.append(ids[best_match[r]])
	ids.assign(order)
	if closed:
		s.offsets[sh.id] = best_off
	relayout(s, sh)
	return true


## Average and longest distance (yards) the given marchers travel into set i.
func move_stats(i: int, ids: Array[int]) -> Vector2:
	if i <= 0 or i >= sets.size() or ids.is_empty():
		return Vector2.ZERO
	var sum := 0.0
	var longest := 0.0
	for id in ids:
		var d := sets[i - 1].get_pos(id).distance_to(sets[i].get_pos(id))
		sum += d
		longest = maxf(longest, d)
	return Vector2(sum / ids.size(), longest)


# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	var ms := []
	for m in marchers:
		ms.append(m.to_dict())
	var shs := []
	for sh in shapes:
		shs.append(sh.to_dict())
	var ss := []
	for s in sets:
		ss.append(s.to_dict())
	return {
		"format": "driller",
		"version": 2,
		"title": title,
		"audio_path": audio_path,
		"audio_offset": audio_offset,
		"hash_style": hash_style,
		"next_marcher_id": next_marcher_id,
		"next_shape_id": next_shape_id,
		"marchers": ms,
		"shapes": shs,
		"sets": ss,
	}


static func from_dict(d: Dictionary) -> DrillShow:
	var show := DrillShow.new()
	show.title = str(d.get("title", "Untitled Show"))
	show.audio_path = str(d.get("audio_path", ""))
	show.audio_offset = float(d.get("audio_offset", 0.0))
	show.hash_style = str(d.get("hash_style", "HS"))
	show.next_marcher_id = int(d.get("next_marcher_id", 1))
	show.next_shape_id = int(d.get("next_shape_id", 1))
	for m in d.get("marchers", []):
		show.marchers.append(DrillMarcher.from_dict(m))
	for sh in d.get("shapes", []):
		show.shapes.append(DrillShape.from_dict(sh))
	for sd in d.get("sets", []):
		show.sets.append(DrillSet.from_dict(sd))
	if show.sets.is_empty():
		show.sets.append(DrillSet.new())
	# Keep id counters ahead of anything in the file.
	for m in show.marchers:
		show.next_marcher_id = maxi(show.next_marcher_id, m.id + 1)
	for sh in show.shapes:
		show.next_shape_id = maxi(show.next_shape_id, sh.id + 1)
	if int(d.get("version", 1)) < 2:
		show._convert_v1(d.get("sets", []))
	return show


## Version 1 files kept a separate copy of each shape in every set. Copies
## become one shared shape (with this set's own points where they differ);
## each shape starts out hidden
## in the sets that didn't have it, so old shows look the same as before.
func _convert_v1(raw_sets: Array) -> void:
	for sd in raw_sets:
		for shd in sd.get("shapes", []):
			next_shape_id = maxi(next_shape_id, int(shd.get("id", 0)) + 1)
	var used_in := {}  # shape id -> {set index: true}
	for i in mini(raw_sets.size(), sets.size()):
		var s := sets[i]
		for shd in raw_sets[i].get("shapes", []):
			var fd := DrillShape.from_dict(shd)
			var sh := find_shape(fd.id)
			if sh != null and sh.type == fd.type and sh.closed == fd.closed:
				if sh.points != fd.points:
					s.forms[sh.id] = fd.points.duplicate()
			elif sh != null:
				sh = null
				for other in shapes:
					if other.name == fd.name and other.same_form(fd):
						sh = other
						break
			if sh == null:
				if find_shape(fd.id) != null:
					fd.id = next_shape_id
					next_shape_id += 1
				shapes.append(fd)
				sh = fd
			var ids: Array[int] = []
			for m in shd.get("marchers", []):
				ids.append(int(m))
			s.attached[sh.id] = ids
			if float(shd.get("start_offset", 0.0)) != 0.0:
				s.offsets[sh.id] = float(shd.get("start_offset", 0.0))
			if not used_in.has(sh.id):
				used_in[sh.id] = {}
			used_in[sh.id][i] = true
	for sh in shapes:
		for i in sets.size():
			if not used_in.get(sh.id, {}).has(i):
				sets[i].set_shown(sh.id, false)


## A small starter show: a block of 24 that opens into an ellipse.
static func make_demo() -> DrillShow:
	var show := DrillShow.new()
	show.title = "Demo Show"
	var s1 := DrillSet.new()
	s1.name = "Set 1"
	s1.counts = 8
	show.sets.append(s1)
	var rows := ["Flute", "Clarinet", "Trumpet", "Mellophone", "Baritone", "Tuba"]
	var hash_y := FieldCoords.hash_y(show.hash_style)
	for r in rows.size():
		for c in 4:
			var pos := Vector2((float(c) - 1.5) * 2.5, hash_y - 2.5 - float(r) * 2.5)
			show.add_marcher(rows[r], pos)
	var s2 := s1.copy()
	s2.name = "Set 2"
	s2.counts = 16
	show.sets.append(s2)
	var ring := DrillShape.new()
	ring.type = "ellipse"
	ring.name = "Ellipse 1"
	ring.points = PackedVector2Array([Vector2(-16, -8), Vector2(16, 8)])
	show.add_shape(ring)
	s1.set_shown(ring.id, false)
	var ids: Array[int] = []
	for m in show.marchers:
		ids.append(m.id)
	show.assign(s2, ring, ids)
	return show
