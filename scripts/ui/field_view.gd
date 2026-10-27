class_name FieldView
extends Control
## The field editor: draws the field, shapes and marchers, and handles
## selecting, dragging, drawing shapes, panning and zooming.

const MARCHER_RADIUS_YD := 0.28  # about half the shoulder width
const MIN_SPRITE_SCALE := 9.0  # px per yard; below this sprites stop shrinking
const HANDLE_PX := 5.0
const SHAPE_HIT_PX := 7.0
const SLOW_FACTOR := 0.2
const DRAG_THRESHOLD_PX := 3.0

const COL_BG := Color("#0f2a1c")
const COL_GRASS := Color("#2f6b3f")
const COL_STRIPE := Color("#2b633a")
const COL_ENDZONE := Color("#285a35")
const COL_LINE := Color(1, 1, 1, 0.85)
const COL_GRID := Color(1, 1, 1, 0.07)
const COL_SHAPE := Color("#7fd1c0")
const COL_SHAPE_SEL := Color("#ffb347")
const COL_SHAPE_HOVER := Color("#ffffff")
const COL_SELECT := Color("#ffe066")
const COL_PREVIEW := Color("#ffe066")
const COL_COLLIDE := Color(1.0, 0.12, 0.08, 0.8)
const COL_CLOSE := Color(1.0, 0.85, 0.1, 0.7)

## Spacing warnings, in yards (1 step = 0.625 yd).
const CLOSE_GAP := 0.15  # yards (~5 in) between outlines counts as "very close"
const SPACING_CELL := 3.5  # yards; bigger than any two marchers' combined reach

enum Drag { NONE, PAN, MARCHERS, SHAPE, HANDLE, BOX, CREATE, FREEFORM }

var ed: DrillEditor
var zoom := 8.0  # pixels per yard
var origin := Vector2.ZERO  # screen position of the world origin (50, midfield)

var _has_view := false
var _user_view := false  # set once the user pans or zooms; until then the field auto-fits
var _last_size := Vector2.ZERO
var _drag := Drag.NONE
var _press_pos := Vector2.ZERO
var _moved := false
var _resume_sloppy := false  # inaccurate preview was paused for this drag
var _virt := Vector2.ZERO  # drag cursor in world space (moves slower with Shift)
var _virt_start := Vector2.ZERO
var _orig := {}  # marcher id -> Vector2 at drag start
var _orig_points := PackedVector2Array()
var _primary := -1
var _handle := -1
var _drag_shape: DrillShape = null
var _hover_shape := -1
var _box_a := Vector2.ZERO
var _box_b := Vector2.ZERO
var _box_base: Array[int] = []
var _create := PackedVector2Array()
var _poly := PackedVector2Array()
var _mouse := Vector2.ZERO  # world
var _mouse_screen := Vector2.ZERO
var _disp := {}  # marcher id -> world position as currently shown
var _glow: GradientTexture2D
var _contacts := []  # [world point, level] for each close call


func setup(editor: DrillEditor) -> void:
	ed = editor
	focus_mode = FOCUS_ALL
	clip_contents = true
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	for sig in [ed.positions_changed, ed.structure_changed, ed.selection_changed, ed.time_changed, ed.view_changed]:
		sig.connect(queue_redraw)
	ed.tool_changed.connect(_on_tool_changed)


# ---------------------------------------------------------------- view

func w2s(p: Vector2) -> Vector2:
	return origin + p * zoom


func s2w(p: Vector2) -> Vector2:
	return (p - origin) / zoom


func fit_view() -> void:
	if size.x < 10 or size.y < 10:
		return
	zoom = minf(size.x / 128.0, size.y / 62.0)
	origin = size * 0.5
	_user_view = false
	queue_redraw()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var w := s2w(screen_pos)
	zoom = clampf(zoom * factor, 2.0, 250.0)
	origin = screen_pos - w * zoom
	_user_view = true
	queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			if (not _has_view or not _user_view) and size.x > 10 and size.y > 10:
				_has_view = true
				fit_view()
			elif _has_view:
				origin += (size - _last_size) * 0.5
			_last_size = size
		NOTIFICATION_DRAG_END:
			_hover_shape = -1
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			queue_redraw()


func _marcher_r() -> float:
	return MARCHER_RADIUS_YD * _sprite_scale()


func _one(id: int) -> Array[int]:
	var a: Array[int] = [id]
	return a


func _snap_pt(p: Vector2) -> Vector2:
	if ed.snap:
		return (p / FieldCoords.STEP).round() * FieldCoords.STEP
	return p


# ---------------------------------------------------------------- hit testing

func _refresh_disp() -> void:
	if ed.sloppy:
		_disp = ed.drill.sloppy_positions_at(ed.loc, ed.sloppy_amount, ed.sloppy_seed)
	else:
		_disp = ed.drill.positions_at(ed.loc)


func _marcher_at(sp: Vector2) -> int:
	var best := -1
	var best_d := maxf(_marcher_r() * 1.2, 7.0)
	for id in _disp:
		var p: Vector2 = _disp[id]
		var d := w2s(p).distance_to(sp)
		if d <= best_d:
			best_d = d
			best = id
	return best


func _shape_at(wp: Vector2) -> DrillShape:
	var s := ed.edit_set()
	if s == null:
		return null
	var tol := SHAPE_HIT_PX / zoom
	var best: DrillShape = null
	for sh in ed.drill.shapes_shown(s):
		var d := ShapeGeom.distance_to(ed.drill.form(s, sh), wp)
		if d <= tol:
			tol = d
			best = sh
	return best


func _handles(sh: DrillShape) -> PackedVector2Array:
	if sh.type == "freeform":
		return PackedVector2Array()
	return sh.points


func _handle_at(sh: DrillShape, sp: Vector2) -> int:
	var hs := _handles(sh)
	for i in range(hs.size() - 1, -1, -1):
		if w2s(hs[i]).distance_to(sp) <= HANDLE_PX + 3.0:
			return i
	return -1


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		origin -= event.delta * 20.0
		_user_view = true
		queue_redraw()
		accept_event()
	elif event is InputEventKey and event.pressed:
		if _key(event):
			accept_event()


func _mouse_button(e: InputEventMouseButton) -> void:
	_mouse_screen = e.position
	_mouse = s2w(e.position)
	if e.pressed:
		grab_focus()
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, 1.1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.0 / 1.1)
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			if e.pressed:
				if e.button_index == MOUSE_BUTTON_RIGHT and not _poly.is_empty():
					_finish_poly(ed.tool == "polygon")
				elif _drag == Drag.NONE:
					_drag = Drag.PAN
			elif _drag == Drag.PAN:
				_drag = Drag.NONE
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_left_press(e)
			else:
				_left_release(e)
	accept_event()
	queue_redraw()


func _left_press(e: InputEventMouseButton) -> void:
	var wp := s2w(e.position)
	_press_pos = e.position
	_moved = false
	_virt = wp
	_virt_start = wp
	var s := ed.edit_set()
	var cmd := e.is_command_or_control_pressed()
	match ed.tool:
		"select":
			if s == null:
				return
			var sel_shape := ed.drill.find_shape(ed.selected_shape)
			if sel_shape != null and s.is_shown(sel_shape.id):
				var h := _handle_at(ed.drill.form(s, sel_shape), e.position)
				if h >= 0:
					_drag = Drag.HANDLE
					_drag_shape = sel_shape
					_handle = h
					_orig_points = ed.drill.form(s, sel_shape).points.duplicate()
					return
			var mid := _marcher_at(e.position)
			if mid != -1:
				if cmd:
					ed.toggle_marcher(mid)
					if not ed.selected_marchers.has(mid):
						return
				elif not ed.selected_marchers.has(mid):
					ed.select_marchers(_one(mid))
				_primary = mid
				_orig.clear()
				for id in ed.selected_marchers:
					_orig[id] = s.get_pos(id)
				_drag = Drag.MARCHERS
				return
			var sh := _shape_at(wp)
			if sh != null:
				ed.select_shape(sh.id)
				_drag = Drag.SHAPE
				_drag_shape = sh
				_orig_points = ed.drill.form(s, sh).points.duplicate()
				return
			_drag = Drag.BOX
			_box_a = e.position
			_box_b = e.position
			_box_base.clear()
			if cmd:
				_box_base.assign(ed.selected_marchers)
			else:
				ed.clear_selection()
		"line", "rect", "ellipse":
			if s == null:
				return
			var p := _snap_pt(wp)
			_create = PackedVector2Array([p, p])
			_drag = Drag.CREATE
		"freeform":
			if s == null:
				return
			_create = PackedVector2Array([wp])
			_drag = Drag.FREEFORM
		"polygon", "curve":
			if s == null:
				return
			if e.double_click:
				_finish_poly(ed.tool == "polygon")
				return
			if _poly.size() >= 3 and w2s(_poly[0]).distance_to(e.position) < 9.0:
				_finish_poly(true)
				return
			_poly.append(_snap_pt(wp))


func _mouse_motion(e: InputEventMouseMotion) -> void:
	_mouse_screen = e.position
	_mouse = s2w(e.position)
	var factor := SLOW_FACTOR if e.shift_pressed else 1.0
	match _drag:
		Drag.PAN:
			origin += e.relative
			_user_view = true
		Drag.MARCHERS, Drag.SHAPE, Drag.HANDLE:
			_virt += e.relative / zoom * factor
			if not _moved and e.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
				_moved = true
				ed.checkpoint()
				if ed.sloppy:
					_resume_sloppy = true
					ed.set_view("sloppy", false)  # edit against the exact dots
			if _moved:
				_apply_drag()
		Drag.BOX:
			_box_b = e.position
			_apply_box()
		Drag.CREATE:
			_create[1] = _constrain(_create[0], _snap_pt(_mouse), e.shift_pressed)
		Drag.FREEFORM:
			if _create[_create.size() - 1].distance_to(_mouse) > 0.35:
				_create.append(_mouse)
	queue_redraw()


func _left_release(e: InputEventMouseButton) -> void:
	match _drag:
		Drag.MARCHERS:
			if _moved:
				var ids: Array[int] = []
				for id in _orig:
					ids.append(id)
				var target := _shape_at(_virt)
				if target != null:
					ed.assign_to_shape(target.id, ids, {}, false)
				else:
					ed.detach_marchers(ids, false)
			elif not e.is_command_or_control_pressed() and ed.selected_marchers.size() > 1:
				ed.select_marchers(_one(_primary))
		Drag.CREATE:
			_finish_create()
		Drag.FREEFORM:
			_finish_freeform()
	if _drag != Drag.PAN:
		_drag = Drag.NONE
	if _resume_sloppy:
		_resume_sloppy = false
		ed.set_view("sloppy", true)
	_hover_shape = -1
	_drag_shape = null
	queue_redraw()


func _apply_drag() -> void:
	var s := ed.edit_set()
	if s == null:
		return
	var delta := _virt - _virt_start
	match _drag:
		Drag.MARCHERS:
			if ed.snap and _orig.has(_primary):
				var o: Vector2 = _orig[_primary]
				delta = _snap_pt(o + delta) - o
			for id in _orig:
				s.positions[id] = _orig[id] + delta
			var hover := _shape_at(_virt)
			_hover_shape = hover.id if hover != null else -1
			ed.notify_positions()
		Drag.SHAPE:
			if ed.snap and not _orig_points.is_empty():
				delta = _snap_pt(_orig_points[0] + delta) - _orig_points[0]
			var pts := PackedVector2Array()
			for p in _orig_points:
				pts.append(p + delta)
			ed.set_shape_points(_drag_shape, pts)
		Drag.HANDLE:
			var pts := _orig_points.duplicate()
			var np := _snap_pt(_orig_points[_handle] + delta)
			pts[_handle] = np
			if _drag_shape.type == "rect" and pts.size() == 4:
				# Keep the rectangle square-cornered: neighbours share an x or y.
				var prev := (_handle + 3) % 4
				var next := (_handle + 1) % 4
				if _handle % 2 == 0:
					pts[next].y = np.y
					pts[prev].x = np.x
				else:
					pts[prev].y = np.y
					pts[next].x = np.x
			ed.set_shape_points(_drag_shape, pts)


func _apply_box() -> void:
	var r := Rect2(_box_a, Vector2.ZERO).expand(_box_b)
	var ids: Array[int] = []
	ids.assign(_box_base)
	for id in _disp:
		var p: Vector2 = _disp[id]
		if r.has_point(w2s(p)) and not ids.has(id):
			ids.append(id)
	ed.select_marchers(ids)


## Shift while drawing: lines snap to 45 degrees, rectangles/ellipses become square.
func _constrain(a: Vector2, b: Vector2, on: bool) -> Vector2:
	if not on:
		return b
	var d := b - a
	if ed.tool == "line":
		var ang := snappedf(d.angle(), PI / 4.0)
		return a + Vector2.from_angle(ang) * d.length()
	var m := maxf(absf(d.x), absf(d.y))
	return a + Vector2(m if d.x >= 0.0 else -m, m if d.y >= 0.0 else -m)


func _key(e: InputEventKey) -> bool:
	match e.keycode:
		KEY_ESCAPE:
			if not _poly.is_empty():
				_poly.clear()
			elif ed.tool != "select":
				ed.set_tool("select")
			else:
				ed.clear_selection()
			queue_redraw()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if not _poly.is_empty():
				_finish_poly(ed.tool == "polygon")
				return true
		KEY_DELETE, KEY_BACKSPACE:
			if ed.selected_shape != -1:
				ed.delete_shape(ed.selected_shape)
				return true
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			return _nudge(e)
	return false


## Arrow keys move selected marchers one step (Shift: a quarter step).
func _nudge(e: InputEventKey) -> bool:
	var s := ed.edit_set()
	if s == null or ed.selected_marchers.is_empty():
		return false
	var dir := Vector2.ZERO
	match e.keycode:
		KEY_LEFT:
			dir = Vector2.LEFT
		KEY_RIGHT:
			dir = Vector2.RIGHT
		KEY_UP:
			dir = Vector2.UP
		KEY_DOWN:
			dir = Vector2.DOWN
	var amount := FieldCoords.STEP * (0.25 if e.shift_pressed else 1.0)
	ed.checkpoint("nudge")
	var ids: Array[int] = []
	ids.assign(ed.selected_marchers)
	ed.detach_marchers(ids, false)
	for id in ids:
		s.positions[id] = s.get_pos(id) + dir * amount
	ed.notify_positions()
	return true


# ---------------------------------------------------------------- shape creation

func _on_tool_changed() -> void:
	_poly.clear()
	_create.clear()
	if _drag == Drag.CREATE or _drag == Drag.FREEFORM:
		_drag = Drag.NONE
	queue_redraw()


func _finish_create() -> void:
	if _create.size() < 2:
		return
	var a := _create[0]
	var b := _create[1]
	_create.clear()
	if a.distance_to(b) < 0.5:
		return
	var sh := DrillShape.new()
	sh.type = ed.tool
	match ed.tool:
		"line":
			sh.points = PackedVector2Array([a, b])
		"rect":
			sh.points = ShapeGeom.rect_corners(a, b)
		"ellipse":
			sh.points = PackedVector2Array([a.min(b), a.max(b)])
	_add_shape(sh)


func _finish_freeform() -> void:
	var pts := _create.duplicate()
	_create.clear()
	if pts.size() < 3:
		return
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	if total < 1.0:
		return
	var sh := DrillShape.new()
	sh.type = "freeform"
	# Ending near the start closes the loop.
	if pts.size() > 4 and pts[0].distance_to(pts[pts.size() - 1]) < 1.5:
		pts.remove_at(pts.size() - 1)
		sh.closed = true
	sh.points = pts
	_add_shape(sh)


func _finish_poly(closed: bool) -> void:
	var pts := _poly.duplicate()
	_poly.clear()
	# A double-click lands twice on the same spot.
	if pts.size() >= 2 and pts[pts.size() - 1].distance_to(pts[pts.size() - 2]) < 0.05:
		pts.remove_at(pts.size() - 1)
	var need := 3 if ed.tool == "polygon" else 2
	if pts.size() < need:
		queue_redraw()
		return
	var sh := DrillShape.new()
	sh.type = ed.tool
	sh.points = pts
	sh.closed = closed and pts.size() >= 3
	_add_shape(sh)


func _add_shape(sh: DrillShape) -> void:
	ed.add_shape(sh)
	ed.set_tool("select")
	queue_redraw()


# ---------------------------------------------------------------- drag & drop from the marcher list

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("type", "") != "marchers":
		return false
	var sh := _shape_at(s2w(at_position))
	var hid := sh.id if sh != null else -1
	if hid != _hover_shape:
		_hover_shape = hid
		queue_redraw()
	return sh != null


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var wp := s2w(at_position)
	var sh := _shape_at(wp)
	_hover_shape = -1
	if sh == null:
		return
	var ids: Array[int] = []
	var hints := {}
	for id in data["ids"]:
		ids.append(int(id))
		hints[int(id)] = wp
	ed.assign_to_shape(sh.id, ids, hints)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if ed == null or ed.drill == null:
		return
	_refresh_disp()
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	_draw_field()
	_draw_ghosts(ed.current_set_index())
	var s := ed.edit_set()
	if s != null:
		_draw_shapes(s)
	_draw_creation()
	_draw_marchers()
	if _drag == Drag.BOX:
		var r := Rect2(_box_a, Vector2.ZERO).expand(_box_b)
		draw_rect(r, Color(1, 0.88, 0.4, 0.12))
		draw_rect(r, Color(1, 0.88, 0.4, 0.8), false, 1.0)
	_draw_overlay()


func _draw_field() -> void:
	var hw := FieldCoords.HALF_WIDTH
	var tl := w2s(Vector2(-60, -hw))
	var br := w2s(Vector2(60, hw))
	draw_rect(Rect2(tl, br - tl), COL_GRASS)
	for i in 20:
		if i % 2 == 1:
			var a := w2s(Vector2(-50.0 + i * 5.0, -hw))
			var b := w2s(Vector2(-45.0 + i * 5.0, hw))
			draw_rect(Rect2(a, b - a), COL_STRIPE)
	for sgn in [-1.0, 1.0]:
		var a := w2s(Vector2(sgn * 50.0, -hw))
		var b := w2s(Vector2(sgn * 60.0, hw))
		draw_rect(Rect2(a, b - a).abs(), COL_ENDZONE)

	# 4-step grid
	if ed.show_grid and FieldCoords.STEP * 4.0 * zoom >= 8.0:
		var g := FieldCoords.STEP * 4.0
		var x := -50.0
		while x <= 50.0:
			draw_line(w2s(Vector2(x, -hw)), w2s(Vector2(x, hw)), COL_GRID)
			x += g
		var y := hw
		while y >= -hw:
			draw_line(w2s(Vector2(-50, y)), w2s(Vector2(50, y)), COL_GRID)
			y -= g

	var lw := maxf(1.0, 0.12 * zoom)
	for i in 21:
		var x := -50.0 + i * 5.0
		draw_line(w2s(Vector2(x, -hw)), w2s(Vector2(x, hw)), COL_LINE, lw)
	draw_rect(Rect2(tl, br - tl), COL_LINE, false, lw * 1.6)

	# Yard ticks along the sidelines and hashes.
	var hy := FieldCoords.hash_y(ed.drill.hash_style)
	var tw := maxf(1.0, 0.08 * zoom)
	if zoom >= 3.0:
		for xi in range(-49, 50):
			var x := float(xi)
			if xi % 5 == 0:
				for y in [hy, -hy]:
					draw_line(w2s(Vector2(x - 0.6, y)), w2s(Vector2(x + 0.6, y)), COL_LINE, lw)
				continue
			draw_line(w2s(Vector2(x, hw)), w2s(Vector2(x, hw - 0.7)), COL_LINE, tw)
			draw_line(w2s(Vector2(x, -hw)), w2s(Vector2(x, -hw + 0.7)), COL_LINE, tw)
			for y in [hy, -hy]:
				draw_line(w2s(Vector2(x, y - 0.33)), w2s(Vector2(x, y + 0.33)), COL_LINE, tw)

	# Yard numbers: 2 yards tall, 7 yards in from each sideline.
	var font := get_theme_default_font()
	var fs := int(clampf(2.7 * zoom, 6.0, 600.0))
	var num_col := Color(1, 1, 1, 0.75)
	for k in range(1, 10):
		var x := -50.0 + k * 10.0
		var txt := str(50 - int(absf(x)))
		for back in [false, true]:
			var anchor := w2s(Vector2(x, -hw + 7.0 if back else hw - 7.0))
			draw_set_transform(anchor, PI if back else 0.0, Vector2.ONE)
			var gap := 0.35 * zoom
			draw_string(font, Vector2(-gap - 400.0, 0), txt.substr(0, 1), HORIZONTAL_ALIGNMENT_RIGHT, 400.0, fs, num_col)
			draw_string(font, Vector2(gap, 0), txt.substr(1, 1), HORIZONTAL_ALIGNMENT_LEFT, 400.0, fs, num_col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Orientation labels.
	var lbl_col := Color(1, 1, 1, 0.45)
	var small := 12
	draw_string(font, w2s(Vector2(0, hw)) + Vector2(-100, 18), "FRONT  ·  AUDIENCE", HORIZONTAL_ALIGNMENT_CENTER, 200, small, lbl_col)
	draw_string(font, w2s(Vector2(0, -hw)) + Vector2(-100, -8), "BACK", HORIZONTAL_ALIGNMENT_CENTER, 200, small, lbl_col)
	draw_set_transform(w2s(Vector2(-60, 0)) + Vector2(-8, 0), -PI / 2.0, Vector2.ONE)
	draw_string(font, Vector2(-100, 0), "SIDE 1", HORIZONTAL_ALIGNMENT_CENTER, 200, small, lbl_col)
	draw_set_transform(w2s(Vector2(60, 0)) + Vector2(8, 0), PI / 2.0, Vector2.ONE)
	draw_string(font, Vector2(-100, 0), "SIDE 2", HORIZONTAL_ALIGNMENT_CENTER, 200, small, lbl_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Previous-set ghosts and the paths into set i. Paths whose step size is too
## big for the tempo glow yellow (large) or red (unrealistic).
func _draw_ghosts(i: int) -> void:
	if i == 0 or not (ed.show_ghost or ed.show_paths or ed.show_step_warnings):
		return
	var prev := ed.drill.sets[i - 1]
	var s := ed.drill.sets[i]
	var r := _marcher_r()
	var glow_w := maxf(1.1 * zoom, 8.0)
	for m in ed.drill.marchers:
		var a := w2s(prev.get_pos(m.id))
		var b := w2s(s.get_pos(m.id))
		var level := ed.drill.step_level(i, m.id) if ed.show_step_warnings else 0
		if level > 0:
			var col := COL_COLLIDE if level == 2 else COL_CLOSE
			for k in 3:
				var w := glow_w * (1.0 - k * 0.3)
				var c := Color(col, col.a * (0.25 + k * 0.2))
				draw_line(a, b, c, w, true)
				draw_circle(a, w * 0.5, c, true, -1.0, true)
				draw_circle(b, w * 0.5, c, true, -1.0, true)
		if (ed.show_paths or level > 0) and a.distance_to(b) > 2.0:
			var line_col := Color(1, 1, 1, 0.35) if level == 0 else Color(1, 1, 1, 0.8)
			draw_dashed_line(a, b, line_col, 1.0, 4.0)
		if ed.show_ghost and ed.is_at_set():
			draw_circle(a, r * 0.7, Color(1, 1, 1, 0.16))


func _poly_to_screen(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = w2s(poly[i])
	return out


func _draw_shapes(s: DrillSet) -> void:
	var font := get_theme_default_font()
	for base in ed.drill.shapes:
		var sh := ed.drill.form(s, base)
		var spoly := _poly_to_screen(ShapeGeom.sample(sh))
		if spoly.size() < 2:
			continue
		var sel := sh.id == ed.selected_shape
		if not s.is_shown(sh.id):
			# Hidden here: only a faint outline when picked from the Shapes list.
			if sel:
				for k in spoly.size() - 1:
					draw_dashed_line(spoly[k], spoly[k + 1], Color(COL_SHAPE_SEL, 0.45), 1.5, 6.0)
				var hl := "%s  (hidden in this set)" % sh.name
				draw_string_outline(font, spoly[0] + Vector2(6, -8), hl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.7))
				draw_string(font, spoly[0] + Vector2(6, -8), hl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(COL_SHAPE_SEL, 0.7))
			continue
		var hov := sh.id == _hover_shape
		var col := COL_SHAPE_HOVER if hov else (COL_SHAPE_SEL if sel else COL_SHAPE)
		var w := 4.0 if hov else (2.5 if sel else 1.8)
		if hov:
			draw_polyline(spoly, Color(1, 1, 1, 0.25), 10.0, true)
		draw_polyline(spoly, col, w, true)
		if sel:
			for p in _handles(sh):
				var hp := w2s(p)
				var r := Rect2(hp - Vector2.ONE * HANDLE_PX, Vector2.ONE * HANDLE_PX * 2.0)
				draw_rect(r, Color.WHITE)
				draw_rect(r, Color("#202020"), false, 1.0)
		if sel or hov:
			var label := "%s  (%d)" % [sh.name, s.count_on(sh.id)]
			draw_string_outline(font, spoly[0] + Vector2(6, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.7))
			draw_string(font, spoly[0] + Vector2(6, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_creation() -> void:
	var pts := PackedVector2Array()
	var type := ed.tool
	var closed := false
	if _drag == Drag.CREATE and _create.size() == 2:
		match type:
			"line":
				pts = _create
			"rect":
				pts = ShapeGeom.rect_corners(_create[0], _create[1])
				closed = true
			"ellipse":
				pts = PackedVector2Array([_create[0].min(_create[1]), _create[0].max(_create[1])])
				closed = true
	elif _drag == Drag.FREEFORM:
		pts = _create
		type = "freeform"
	elif not _poly.is_empty():
		pts = _poly.duplicate()
		pts.append(_snap_pt(_mouse))
		closed = type == "polygon"
	if pts.size() < 2:
		return
	var poly := _poly_to_screen(ShapeGeom.sample_points(type, pts, closed))
	draw_polyline(poly, COL_PREVIEW, 2.0, true)
	for p in _poly:
		draw_circle(w2s(p), 3.5, COL_PREVIEW)
	if _poly.size() >= 3 and w2s(_poly[0]).distance_to(_mouse_screen) < 9.0:
		draw_circle(w2s(_poly[0]), 7.0, COL_PREVIEW, false, 2.0, true)


## Finds marchers that are too close, using their real outlines (bodies and
## instruments): 2 = touching, 1 = within CLOSE_GAP, or a trombone slide
## would hit at full extension. Also records where the closest calls are.
func spacing_levels() -> Dictionary:
	var levels := {}
	_contacts.clear()
	var feet := {}
	var reach := {}
	var cells := {}
	for m in ed.drill.marchers:
		if not _disp.has(m.id):
			continue
		var kind := Sections.kind(m.section)
		var p: Vector2 = _disp[m.id]
		feet[m.id] = Footprint.placed(kind, p, _facing(m.id))
		reach[m.id] = Footprint.reach(kind)
		var c := Vector2i((p / SPACING_CELL).floor())
		if not cells.has(c):
			cells[c] = []
		cells[c].append(m.id)
	for c in cells:
		for id in cells[c]:
			var p: Vector2 = _disp[id]
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var nc: Vector2i = c + Vector2i(dx, dy)
					if not cells.has(nc):
						continue
					for other in cells[nc]:
						if other <= id:
							continue
						if p.distance_to(_disp[other]) > float(reach[id]) + float(reach[other]) + CLOSE_GAP:
							continue
						var g := Footprint.gap(feet[id], feet[other], false)
						var lv := 0
						if float(g["gap"]) < 0.0:
							lv = 2
						elif float(g["gap"]) < CLOSE_GAP:
							lv = 1
						else:
							var ge := Footprint.gap(feet[id], feet[other], true)
							if float(ge["gap"]) < 0.0:
								lv = 1
								g = ge
						if lv > 0:
							levels[id] = maxi(int(levels.get(id, 0)), lv)
							levels[other] = maxi(int(levels.get(other, 0)), lv)
							_contacts.append([g["at"], lv])
	return levels


## Soft red/yellow glows under marchers that are colliding or very close,
## plus a smaller one where they meet.
func _draw_spacing_warnings(r: float, view: Rect2) -> void:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.75))
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 64
		_glow.height = 64
	var levels := spacing_levels()
	var gr := maxf(0.75 * _sprite_scale(), 10.0)
	var cr := maxf(0.35 * _sprite_scale(), 7.0)
	# Yellow first so red sits on top where they overlap.
	for want in [1, 2]:
		var col := COL_CLOSE if want == 1 else COL_COLLIDE
		for id in levels:
			if levels[id] != want:
				continue
			var sp := w2s(_disp[id])
			if view.has_point(sp):
				draw_texture_rect(_glow, Rect2(sp - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, col)
		for ct in _contacts:
			if int(ct[1]) != want:
				continue
			var cp := w2s(ct[0])
			if view.has_point(cp):
				draw_texture_rect(_glow, Rect2(cp - Vector2(cr, cr), Vector2(cr, cr) * 2.0), false, col)


func _facing(id: int) -> float:
	if ed.sloppy:
		return ed.drill.sloppy_facing_at(ed.loc, id, ed.sloppy_amount, ed.sloppy_seed)
	return ed.drill.facing_at(ed.loc, id)


## Pixels per yard for sprites: true scale, but never so small they vanish.
func _sprite_scale() -> float:
	return maxf(zoom, MIN_SPRITE_SCALE)


func _draw_marchers() -> void:
	var r := _marcher_r()
	var font := get_theme_default_font()
	var view := Rect2(Vector2.ZERO, size).grow(1.7 * _sprite_scale())
	var label_size := int(clampf(r * 2.1, 9.0, 16.0))
	var dragging_ids := _orig if _drag == Drag.MARCHERS and _moved else {}
	if ed.show_spacing:
		_draw_spacing_warnings(r, view)
	for m in ed.drill.marchers:
		var p: Vector2 = _disp.get(m.id, Vector2.ZERO)
		var sp := w2s(p)
		if not view.has_point(sp):
			continue
		var angle := deg_to_rad(_facing(m.id))
		var alpha := 0.85 if dragging_ids.has(m.id) else 1.0
		MarcherSprite.draw(self, sp, _sprite_scale(), angle, Sections.color(m.section), Sections.kind(m.section), alpha)
		if ed.selected_marchers.has(m.id):
			draw_arc(sp, maxf(r * 1.7, 6.0), 0.0, TAU, 24, COL_SELECT, 2.0, true)
		if ed.show_labels and r >= 3.4:
			var lp := sp + Vector2(-40, -r * 1.7)
			draw_string_outline(font, lp, m.label, HORIZONTAL_ALIGNMENT_CENTER, 80, label_size, 3, Color(0, 0, 0, 0.75))
			draw_string(font, lp, m.label, HORIZONTAL_ALIGNMENT_CENTER, 80, label_size, Color.WHITE)


func _draw_overlay() -> void:
	var font := get_theme_default_font()
	var s := ed.current_set()
	var text: String
	if ed.is_at_set():
		text = "%s" % s.name
		if ed.current_set_index() > 0:
			text += "   ·   %d counts @ %d bpm" % [s.counts, int(s.tempo)]
	else:
		text = "Moving into %s   ·   count %.1f of %d   ·   go to a set to edit" % [s.name, float(ed.loc["count"]), s.counts]
	if ed.sloppy:
		text += "   ·   inaccurate preview"
	_draw_badge(font, Vector2(10, 10), text)

	var hint := ""
	match ed.tool:
		"select":
			if _drag == Drag.MARCHERS and _moved:
				hint = "Drop on a shape to attach  ·  hold Shift to move slowly"
			else:
				hint = "Drag marchers (Shift = slow)  ·  drag onto a shape to attach  ·  %s-click to add to selection  ·  right/middle-drag to pan" % Ui.cmd_name()
		"line", "rect", "ellipse":
			hint = "Drag to draw  ·  Shift constrains"
		"polygon":
			hint = "Click to add corners  ·  click the first point, double-click or Enter to finish  ·  Esc cancels"
		"curve":
			hint = "Click to add points  ·  double-click, Enter or right-click to finish  ·  Esc cancels"
		"freeform":
			hint = "Drag to draw  ·  end near the start to close the loop"
	_draw_badge(font, Vector2(10, size.y - 30), hint, 12)


func _draw_badge(font: Font, pos: Vector2, text: String, fs := 13) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_rect(Rect2(pos, Vector2(w + 16, fs + 10)), Color(0, 0, 0, 0.55))
	draw_string(font, pos + Vector2(8, fs + 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
