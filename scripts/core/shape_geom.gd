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


## Spots for n marchers spaced evenly along the shape.
static func distribute(sh: DrillShape, n: int, offset := 0.0) -> PackedVector2Array:
	var poly := sample(sh)
	var cum := cumulative(poly)
	var out := PackedVector2Array()
	if poly.is_empty():
		for k in n:
			out.append(Vector2.ZERO)
		return out
	var total := cum[cum.size() - 1]
	for s in params(n, total, is_closed(sh), offset):
		out.append(point_at(poly, cum, s))
	return out


## Gap between n marchers spaced along the shape, in yards.
static func spacing(sh: DrillShape, n: int) -> float:
	var total := length(sh)
	if is_closed(sh):
		return total / n if n > 0 else 0.0
	return total / (n - 1) if n > 1 else 0.0


static func rect_corners(a: Vector2, b: Vector2) -> PackedVector2Array:
	var lo := a.min(b)
	var hi := a.max(b)
	return PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
