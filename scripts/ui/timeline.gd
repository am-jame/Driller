class_name Timeline
extends Control
## Show timeline: one segment per move, count ticks, the audio's extent and
## a playhead. Click or drag to scrub; it snaps to sets (hold Shift to not).

signal seek_requested(t: float, set_index: int)

const PAD := 10.0
const SNAP_PX := 7.0

var ed: DrillEditor
var audio_length := 0.0
var _dragging := false


func setup(editor: DrillEditor) -> void:
	ed = editor
	custom_minimum_size = Vector2(0, 64)
	size_flags_horizontal = SIZE_EXPAND_FILL
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	for sig in [ed.time_changed, ed.structure_changed]:
		sig.connect(queue_redraw)


func _total() -> float:
	return maxf(ed.drill.duration(), 0.001)


func _x(t: float) -> float:
	return PAD + t / _total() * (size.x - PAD * 2.0)


func _t(x: float) -> float:
	return clampf((x - PAD) / maxf(size.x - PAD * 2.0, 1.0) * _total(), 0.0, ed.drill.duration())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_seek(event.position.x, event.shift_pressed)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_seek(event.position.x, event.shift_pressed)
		accept_event()


func _seek(x: float, no_snap: bool) -> void:
	if ed.drill.sets.size() < 2:
		return
	var ts := ed.drill.set_times()
	if not no_snap:
		for i in ts.size():
			if absf(_x(ts[i]) - x) <= SNAP_PX:
				seek_requested.emit(ts[i], i)
				return
	seek_requested.emit(_t(x), -1)


func _draw() -> void:
	if ed == null or ed.drill == null:
		return
	var font := get_theme_default_font()
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color("#161b1e"))
	var ts := ed.drill.set_times()
	var n := ts.size()
	if n < 2:
		draw_string(font, Vector2(PAD, h * 0.5 + 5), "Add a second set to build a timeline.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.TEXT_DIM)
		return
	var top := 18.0
	var bar_h := h - top - 14.0
	for i in range(1, n):
		var x0 := _x(ts[i - 1])
		var x1 := _x(ts[i])
		var col := Color("#2a3a3d") if i % 2 == 1 else Color("#24312f")
		if i == ed.current_set_index() and not ed.is_at_set():
			col = col.lightened(0.15)
		draw_rect(Rect2(x0, top, x1 - x0, bar_h), col)
		# Count ticks
		var counts := maxi(ed.drill.sets[i].counts, 1)
		var px_per := (x1 - x0) / counts
		if px_per >= 4.0:
			for c in range(1, counts):
				var cx := x0 + px_per * c
				var big := c % 4 == 0
				draw_line(Vector2(cx, top + bar_h - (8.0 if big else 4.0)), Vector2(cx, top + bar_h), Color(1, 1, 1, 0.25 if big else 0.12))
		var label := "%d ct" % counts
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		if x1 - x0 > lw + 8:
			draw_string(font, Vector2((x0 + x1 - lw) * 0.5, top + bar_h * 0.5 + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))

	# Audio extent (where the music is, relative to the show).
	if audio_length > 0.0:
		var a0 := clampf(_x(-ed.drill.audio_offset), PAD, size.x - PAD)
		var a1 := clampf(_x(audio_length - ed.drill.audio_offset), PAD, size.x - PAD)
		if a1 > a0:
			draw_rect(Rect2(a0, h - 10, a1 - a0, 4), Color(Ui.ACCENT, 0.7))

	# Set markers
	var last_label_x := -1000.0
	for i in n:
		var x := _x(ts[i])
		var cur := i == ed.current_set_index() and ed.is_at_set()
		draw_line(Vector2(x, top - 2), Vector2(x, top + bar_h), Color(1, 1, 1, 0.9 if cur else 0.5), 2.0 if cur else 1.0)
		if x - last_label_x > 18:
			draw_string(font, Vector2(x - 20, 13), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Ui.ACCENT if cur else Color(1, 1, 1, 0.7))
			last_label_x = x

	# Playhead
	var px := _x(ed.time)
	draw_line(Vector2(px, 4), Vector2(px, h - 4), Color("#ff5c5c"), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(px - 5, 2), Vector2(px + 5, 2), Vector2(px, 9)]), Color("#ff5c5c"))
