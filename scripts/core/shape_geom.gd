class_name ShapeGeom
extends RefCounted
## Geometry helpers: turn shapes into polylines, measure along them, and
## space marchers evenly.

const ELLIPSE_SEGMENTS := 96
const CURVE_STEPS := 16


static func is_closed(sh: DrillShape) -> bool:
	match sh.type:
		"rect", "ellipse":
			return true
		"line":
			return false
	return sh.closed and sh.points.size() >= 3


static func sample(sh: DrillShape) -> PackedVector2Array:
	return sample_points(sh.type, sh.points, is_closed(sh))


## Polyline approximation. Closed shapes repeat their first point at the end.
static func sample_points(type: String, pts: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.is_empty():
		return out
	match type:
		"ellipse":
			if pts.size() < 2:
				return pts.duplicate()
			var c := (pts[0] + pts[1]) * 0.5
			var rad := (pts[1] - pts[0]).abs() * 0.5
			# Starts at the top (back) and goes clockwise.
			for i in ELLIPSE_SEGMENTS + 1:
				var a := -PI * 0.5 + TAU * float(i) / ELLIPSE_SEGMENTS
				out.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
			return out
		"curve":
			return _catmull(pts, closed and pts.size() >= 3)
	out = pts.duplicate()
	if closed and pts.size() >= 3:
		out.append(pts[0])
	return out


static func _catmull(pts: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var n := pts.size()
	if n < 2:
		return pts.duplicate()
	var out := PackedVector2Array()
	var seg_count := n if closed else n - 1
	for i in seg_count:
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var p0: Vector2
		var p3: Vector2
		if closed:
			p0 = pts[(i - 1 + n) % n]
			p3 = pts[(i + 2) % n]
		else:
			p0 = pts[i - 1] if i > 0 else p1 * 2.0 - p2
			p3 = pts[i + 2] if i + 2 < n else p2 * 2.0 - p1
		for s in CURVE_STEPS:
			var t := float(s) / CURVE_STEPS
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (
				2.0 * p1
				+ (p2 - p0) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(pts[0] if closed else pts[n - 1])
	return out


static func cumulative(poly: PackedVector2Array) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	if poly.is_empty():
		return c
	c.append(0.0)
	for i in range(1, poly.size()):
		c.append(c[i - 1] + poly[i - 1].distance_to(poly[i]))
	return c


static func length(sh: DrillShape) -> float:
	var c := cumulative(sample(sh))
	return c[c.size() - 1] if c.size() > 0 else 0.0


static func point_at(poly: PackedVector2Array, cum: PackedFloat64Array, s: float) -> Vector2:
	var n := poly.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1 or s <= 0.0:
		return poly[0]
	if s >= cum[n - 1]:
		return poly[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := cum[hi] - cum[lo]
	var f := (s - cum[lo]) / seg if seg > 0.0 else 0.0
	return poly[lo].lerp(poly[hi], f)


## Closest spot on the polyline: {"s": distance along it, "dist": distance away}.
static func project(poly: PackedVector2Array, cum: PackedFloat64Array, p: Vector2) -> Dictionary:
	if poly.size() == 1:
		return {"s": 0.0, "dist": p.distance_to(poly[0])}
	var best_d := INF
	var best_s := 0.0
	for i in range(poly.size() - 1):
		var a := poly[i]
		var ab := poly[i + 1] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 == 0.0 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d := (a + ab * t).distance_to(p)
		if d < best_d:
			best_d = d
			best_s = cum[i] + sqrt(l2) * t
	return {"s": best_s, "dist": best_d}


static func distance_to(sh: DrillShape, p: Vector2) -> float:
	var poly := sample(sh)
	if poly.is_empty():
		return INF
	return float(project(poly, cumulative(poly), p)["dist"])


## Distances along the shape for n evenly spaced marchers. Open shapes put
## marchers on both ends; closed shapes space them all the way around.
static func params(n: int, total: float, closed: bool, offset: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in n:
		if closed:
			out.append(fposmod((float(k) / n + offset) * total, total) if total > 0.0 else 0.0)
		elif n == 1:
			out.append(total * 0.5)
		else:
			out.append(total * float(k) / float(n - 1))
	return out


## True if the shape has sharp corners that marchers can be pinned to.
static func has_corners(sh: DrillShape) -> bool:
	return sh.type in ["rect", "polygon"] and sh.points.size() >= 3


## Number of corners a "marchers on corners" shape needs filled.
static func corner_count(sh: DrillShape) -> int:
	return sh.points.size() if has_corners(sh) else 0


## True if marchers are really being pinned to corners (the option is on and
## there are enough marchers to cover every corner).
static func pins_corners(sh: DrillShape, n: int) -> bool:
	return sh.corners and has_corners(sh) and n >= corner_count(sh)


## Distances along the shape for n marchers with one on every corner and the
## rest spread over the sides, each side's gaps as even as possible.
## `cum` is the cumulative length of sample(sh) (whose points are the corners).
static func corner_params(sh: DrillShape, cum: PackedFloat64Array, n: int, offset: float) -> PackedFloat64Array:
	var closed := is_closed(sh)
	var m := sh.points.size()
	var total := cum[cum.size() - 1]
	var sides := m if closed else m - 1
	var starts := PackedFloat64Array()
	var lens := PackedFloat64Array()
	var extra := PackedInt32Array()
	for j in sides:
		starts.append(cum[j])
		lens.append((total if closed and j == m - 1 else cum[j + 1]) - cum[j])
		extra.append(0)
	# Hand the spare marchers out one at a time to whichever side has the
	# widest gaps, which keeps the largest interval as small as possible.
	for _r in n - m:
		var best := 0
		var best_gap := -1.0
		for j in sides:
			var g := lens[j] / (extra[j] + 1)
			if g > best_gap + 1e-9:
				best_gap = g
				best = j
		extra[best] += 1
	var slots := PackedFloat64Array()
	for j in sides:
		slots.append(starts[j])
		for t in extra[j]:
			slots.append(starts[j] + lens[j] * float(t + 1) / (extra[j] + 1))
	if not closed:
		slots.append(total)
		return slots
	# Rotating a pinned shape moves marchers a whole spot at a time.
	var shift := posmod(roundi(offset * n), n)
	var out := PackedFloat64Array()
	for k in n:
		out.append(slots[(k + shift) % n])
	return out


## Distances along the shape for its n marchers, in order.
static func slot_params(sh: DrillShape, cum: PackedFloat64Array, n: int, offset: float) -> PackedFloat64Array:
	if pins_corners(sh, n):
		return corner_params(sh, cum, n, offset)
	return params(n, cum[cum.size() - 1], is_closed(sh), offset)


## Spots for the shape's n marchers: evenly spaced, or pinned to corners.
static func distribute(sh: DrillShape, n: int, offset := 0.0) -> PackedVector2Array:
	var poly := sample(sh)
	var cum := cumulative(poly)
	var out := PackedVector2Array()
	if poly.is_empty():
		for k in n:
			out.append(Vector2.ZERO)
		return out
	for s in slot_params(sh, cum, n, offset):
		out.append(point_at(poly, cum, s))
	return out


## Gap between n marchers spaced along the shape, in yards.
static func spacing(sh: DrillShape, n: int) -> float:
	var total := length(sh)
	if is_closed(sh):
		return total / n if n > 0 else 0.0
	return total / (n - 1) if n > 1 else 0.0


## Smallest and largest gap (along the shape) between neighbouring marchers.
static func gap_range(sh: DrillShape, n: int) -> Vector2:
	if n < 2:
		return Vector2.ZERO
	var cum := cumulative(sample(sh))
	if cum.is_empty():
		return Vector2.ZERO
	var total := cum[cum.size() - 1]
	var ps := slot_params(sh, cum, n, 0.0)
	ps.sort()
	var lo := INF
	var hi := 0.0
	var count := ps.size() if is_closed(sh) else ps.size() - 1
	for k in count:
		var g := (ps[k + 1] if k + 1 < ps.size() else ps[0] + total) - ps[k]
		lo = minf(lo, g)
		hi = maxf(hi, g)
	return Vector2(lo, hi)


static func rect_corners(a: Vector2, b: Vector2) -> PackedVector2Array:
	var lo := a.min(b)
	var hi := a.max(b)
	return PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
