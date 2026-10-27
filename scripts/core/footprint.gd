class_name Footprint
extends RefCounted
## Real-world top-down size of a marcher and their instrument, in yards.
## Used both to draw the sprites to scale and to check for collisions.
##
## Local frame: origin between the shoulders, +y is the way they face,
## -x is their right hand, +x their left. Each part is a capsule (a line
## segment with a radius); a circle is a capsule with a == b.
##
## Rough sizes (1 yd = 36 in): shoulders ~19 in wide, chest ~10 in deep;
## trumpet ~19 in, 5 in bell; mellophone ~22 in, 11 in bell; marching
## baritone ~26 in, 11 in bell; trombone slide ~29 in closed (1st position)
## plus ~23 in more at 7th, 8.5 in bell; sousaphone 26 in bell; flute ~26 in
## to the right; snare 14 in; bass drums ~26 in across, 14 in deep.

const BODY_HALF := 0.13  # half the distance between the shoulder "ends"
const BODY_R := 0.14  # so shoulders are ~0.54 yd wide, ~0.28 yd deep
const HEAD := Vector2(0, 0.02)
const HEAD_R := 0.11
const MOUTH := Vector2(0, 0.12)

## Trombone slide (on the player's right of centre).
const SLIDE_X := -0.05
const SLIDE_R := 0.055
const SLIDE_CLOSED := 0.93  # forward reach of the slide crook, 1st position
const SLIDE_OPEN := 1.57  # ... at 7th position

## Parts marked EXTENDED only count as "might hit" (yellow), not a sure hit.
enum { SOLID, EXTENDED }

static var _cache := {}


## Array of [a: Vector2, b: Vector2, r: float, tag: int].
static func parts(kind: String) -> Array:
	if _cache.has(kind):
		return _cache[kind]
	var p := [[Vector2(-BODY_HALF, 0), Vector2(BODY_HALF, 0), BODY_R, SOLID]]
	match kind:
		"brass":
			p.append([MOUTH, Vector2(0, 0.6), 0.035, SOLID])
			p.append([Vector2(0, 0.62), Vector2(0, 0.62), 0.07, SOLID])
		"mello":
			p.append([MOUTH, Vector2(0, 0.62), 0.05, SOLID])
			p.append([Vector2(0, 0.66), Vector2(0, 0.66), 0.15, SOLID])
		"bari":
			p.append([MOUTH, Vector2(0.03, 0.66), 0.07, SOLID])
			p.append([Vector2(0.03, 0.74), Vector2(0.03, 0.74), 0.155, SOLID])
		"trombone":
			p.append([Vector2(SLIDE_X, 0.12), Vector2(SLIDE_X, SLIDE_CLOSED), SLIDE_R, SOLID])
			p.append([Vector2(0.09, 0.6), Vector2(0.09, 0.6), 0.12, SOLID])  # bell
			p.append([Vector2(0.1, 0.1), Vector2(0.1, -0.22), 0.04, SOLID])  # tuning slide over the left shoulder
			p.append([Vector2(SLIDE_X, SLIDE_CLOSED), Vector2(SLIDE_X, SLIDE_OPEN), SLIDE_R, EXTENDED])
		"tuba":
			p.append([Vector2.ZERO, Vector2.ZERO, 0.42, SOLID])  # sousaphone wrap
			p.append([Vector2(0.04, 0.44), Vector2(0.04, 0.44), 0.36, SOLID])  # bell overhead
		"flute":
			p.append([Vector2(0.08, 0.15), Vector2(-0.62, 0.2), 0.02, SOLID])
		"clarinet":
			p.append([MOUTH, Vector2(0, 0.46), 0.03, SOLID])
			p.append([Vector2(0, 0.48), Vector2(0, 0.48), 0.045, SOLID])
		"sax":
			p.append([Vector2(-0.02, 0.12), Vector2(-0.12, 0.36), 0.04, SOLID])
			p.append([Vector2(-0.14, 0.4), Vector2(-0.14, 0.4), 0.07, SOLID])
		"snare":
			p.append([Vector2(0, 0.34), Vector2(0, 0.34), 0.195, SOLID])
		"tenor":
			for d in tenor_drums():
				p.append([d[0], d[0], d[1], SOLID])
		"bass":
			p.append([Vector2(0, 0.36), Vector2(0, 0.68), 0.2, SOLID])
		"cymbal":
			p.append([Vector2(-0.3, 0.3), Vector2(-0.3, 0.3), 0.25, SOLID])
			p.append([Vector2(0.3, 0.3), Vector2(0.3, 0.3), 0.25, SOLID])
		"guard":
			p.append([Vector2(-0.12, 0.15), Vector2(-0.3, 0.62), 0.03, SOLID])
		"major":
			p.append([Vector2(-0.2, 0.1), Vector2(-0.28, 0.45), 0.025, SOLID])
	_cache[kind] = p
	return p


## Quint drum centres and radii, player's right to left, plus the shot drum.
static func tenor_drums() -> Array:
	return [
		[Vector2(-0.34, 0.27), 0.18],
		[Vector2(-0.13, 0.45), 0.14],
		[Vector2(0.13, 0.45), 0.167],
		[Vector2(0.35, 0.27), 0.194],
		[Vector2(0.0, 0.66), 0.083],
	]


## How far any part reaches from the origin.
static func reach(kind: String) -> float:
	var m := 0.0
	for c in parts(kind):
		m = maxf(m, maxf((c[0] as Vector2).length(), (c[1] as Vector2).length()) + float(c[2]))
	return m


## The parts placed on the field: [a, b, r, tag] in world yards.
static func placed(kind: String, pos: Vector2, facing_deg: float) -> Array:
	var ang := deg_to_rad(facing_deg)
	var out := []
	for c in parts(kind):
		out.append([pos + (c[0] as Vector2).rotated(ang), pos + (c[1] as Vector2).rotated(ang), c[2], c[3]])
	return out


## Gap between two placed footprints (negative = overlapping), and where
## they come closest. `with_extended` also counts EXTENDED parts.
static func gap(fa: Array, fb: Array, with_extended: bool) -> Dictionary:
	var best := INF
	var at := Vector2.ZERO
	for ca in fa:
		if int(ca[3]) == EXTENDED and not with_extended:
			continue
		for cb in fb:
			if int(cb[3]) == EXTENDED and not with_extended:
				continue
			var pts := Geometry2D.get_closest_points_between_segments(ca[0], ca[1], cb[0], cb[1])
			var d: float = pts[0].distance_to(pts[1]) - float(ca[2]) - float(cb[2])
			if d < best:
				best = d
				at = (pts[0] + pts[1]) * 0.5
	return {"gap": best, "at": at}
