class_name MarcherSprite
extends RefCounted
## Draws a top-down marcher to scale: shoulders, shako and instrument.
## Sizes come from Footprint (in yards); `scale` is pixels per yard.
## Local +y is the direction the marcher faces, -x their right hand.
## Points are placed in screen pixels here (rather than with a scaled
## canvas transform) so circles and smoothed lines draw cleanly at any zoom.

const OUTLINE := Color(0.05, 0.07, 0.08, 0.9)
const GOLD := Color("#e9c46a")
const SILVER := Color("#d9dee3")
const BLACK := Color("#1b1b1b")
const HAT := Color("#1d232b")
const HEAD_SKIN := Color("#f1f1f1")

static var _ci: CanvasItem
static var _pos := Vector2.ZERO
static var _scale := 1.0
static var _ang := 0.0
static var _alpha := 1.0


## Local yards -> screen pixels.
static func _p(v: Vector2) -> Vector2:
	return _pos + (v * _scale).rotated(_ang)


static func _poly_ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var n := clampi(int(maxf(rx, ry) * _scale * 1.2), 10, 40)
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var a := TAU * i / n
		out[i] = _p(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func _disc(c: Vector2, r: float, col: Color) -> void:
	if r * _scale < 1.2:
		_ci.draw_circle(_p(c), maxf(r * _scale, 0.6), _a(col))
		return
	_ci.draw_colored_polygon(_poly_ellipse(c, r, r), _a(col))


static func _ring(c: Vector2, r: float, col: Color, w_px := 1.0) -> void:
	var pts := _poly_ellipse(c, r, r)
	pts.append(pts[0])
	_ci.draw_polyline(pts, _a(col), w_px, true)


## A tube `w` yards thick (never thinner than a pixel).
static func _line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	_ci.draw_line(_p(a), _p(b), _a(col), maxf(w * _scale, 1.0), true)


static func draw(ci: CanvasItem, pos: Vector2, scale: float, angle: float, color: Color, kind: String, alpha := 1.0) -> void:
	_ci = ci
	_pos = pos
	_scale = scale
	_ang = angle
	_alpha = alpha
	var ow := clampf(scale * 0.02, 1.0, 2.0)  # outline width, px

	# Things worn around the body go underneath it.
	if kind == "tuba":
		_ring(Vector2.ZERO, 0.36, GOLD, maxf(0.1 * scale, 1.0))

	var body := _poly_ellipse(Vector2.ZERO, Footprint.BODY_HALF + Footprint.BODY_R, Footprint.BODY_R)
	ci.draw_colored_polygon(body, _a(color.darkened(0.12)))
	body.append(body[0])
	ci.draw_polyline(body, _a(OUTLINE), ow, true)

	var m := Footprint.MOUTH
	match kind:
		"brass":
			_horn(m, Vector2(0, 0.6), 0.035, Vector2(0, 0.62), 0.07)
		"mello":
			_horn(m, Vector2(0, 0.62), 0.05, Vector2(0, 0.66), 0.15)
		"bari":
			_horn(m, Vector2(0.03, 0.66), 0.07, Vector2(0.03, 0.74), 0.155)
		"trombone":
			var x := Footprint.SLIDE_X
			var gap := Footprint.SLIDE_R * 0.7
			# Where the slide reaches at 7th position, faint.
			_line(Vector2(x, Footprint.SLIDE_CLOSED), Vector2(x, Footprint.SLIDE_OPEN), Footprint.SLIDE_R * 2.0, Color(SILVER, 0.28))
			# Tuning slide over the left shoulder.
			_line(Vector2(0.1, 0.1), Vector2(0.1, -0.22), 0.05, GOLD)
			# The slide in 1st position: two tubes and the crook.
			for sx in [-gap, gap]:
				_line(Vector2(x + sx, 0.12), Vector2(x + sx, Footprint.SLIDE_CLOSED), 0.025, SILVER)
			_line(Vector2(x - gap, Footprint.SLIDE_CLOSED), Vector2(x + gap, Footprint.SLIDE_CLOSED), 0.035, SILVER)
			_disc(Vector2(0.09, 0.6), 0.12, GOLD)
			_disc(Vector2(0.09, 0.6), 0.07, GOLD.darkened(0.35))
		"tuba":
			_disc(Vector2(0.04, 0.44), 0.36, Color(GOLD, 0.92))
			_disc(Vector2(0.04, 0.44), 0.24, Color(GOLD.darkened(0.4), 0.92))
		"flute":
			_line(Vector2(0.08, 0.15), Vector2(-0.62, 0.2), 0.04, SILVER)
		"clarinet":
			_line(m, Vector2(0, 0.46), 0.06, BLACK)
			_disc(Vector2(0, 0.48), 0.045, BLACK)
		"sax":
			_line(Vector2(-0.02, 0.12), Vector2(-0.12, 0.36), 0.08, GOLD)
			_disc(Vector2(-0.14, 0.4), 0.07, GOLD)
		"snare":
			_drum(Vector2(0, 0.34), 0.195, ow)
		"tenor":
			for d in Footprint.tenor_drums():
				_drum(d[0], d[1], ow)
		"bass":
			# Heads face the sides, so from above you see the shell.
			var shell := PackedVector2Array([_p(Vector2(-0.2, 0.16)), _p(Vector2(0.2, 0.16)), _p(Vector2(0.2, 0.88)), _p(Vector2(-0.2, 0.88))])
			ci.draw_colored_polygon(shell, _a(HEAD_SKIN))
			shell.append(shell[0])
			ci.draw_polyline(shell, _a(OUTLINE), ow, true)
		"cymbal":
			for sx in [-1.0, 1.0]:
				_disc(Vector2(sx * 0.3, 0.3), 0.25, GOLD)
				_disc(Vector2(sx * 0.3, 0.3), 0.05, GOLD.darkened(0.35))
		"guard":
			var top := Vector2(-0.3, 0.62)
			_line(Vector2(-0.12, 0.15), top, 0.04, SILVER)
			var flag := PackedVector2Array([_p(top), _p(top + Vector2(0.06, -0.3)), _p(top + Vector2(0.4, -0.22)), _p(top + Vector2(0.34, 0.06))])
			ci.draw_colored_polygon(flag, _a(Color(color.lightened(0.2), 0.9)))
		"major":
			_line(Vector2(-0.2, 0.1), Vector2(-0.28, 0.45), 0.04, SILVER)

	# Shako with a plume.
	_disc(Footprint.HEAD, Footprint.HEAD_R, HAT)
	_ring(Footprint.HEAD, Footprint.HEAD_R, color.lightened(0.35), ow)
	_disc(Footprint.HEAD, 0.035, Color.WHITE)


static func _horn(a: Vector2, b: Vector2, tube_r: float, bell: Vector2, bell_r: float) -> void:
	_line(a, b, tube_r * 2.0, GOLD)
	_disc(bell, bell_r, GOLD)
	_disc(bell, bell_r * 0.55, GOLD.darkened(0.35))


static func _drum(c: Vector2, r: float, ow: float) -> void:
	_disc(c, r, HEAD_SKIN)
	_ring(c, r, OUTLINE, ow)


static func _a(c: Color) -> Color:
	c.a *= _alpha
	return c
