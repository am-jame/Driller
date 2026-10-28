class_name InfoPanel
extends VBoxContainer
## Details for whatever is selected: the current set, marcher(s), or a shape.

const FACINGS := [["Front", 0.0], ["Side 1", 90.0], ["Back", 180.0], ["Side 2", 270.0]]

var ed: DrillEditor
var _title: Label
var _subtitle: Label
var _body: VBoxContainer
var _built_key := ""
var _self_edit := false
var _refreshing := false
var _refreshers: Array[Callable] = []


func setup(editor: DrillEditor) -> void:
	ed = editor
	add_theme_constant_override("separation", 4)
	_title = Ui.label("", 18)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_title)
	_subtitle = Ui.label("", 12, Ui.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_subtitle)
	add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)

	ed.selection_changed.connect(_maybe_rebuild)
	ed.structure_changed.connect(func() -> void:
		if _self_edit:
			_refresh()
		else:
			_rebuild())
	ed.positions_changed.connect(_refresh)
	ed.time_changed.connect(_maybe_rebuild)


func _key() -> String:
	return "%s|%s|%d|%s|%d" % [ed.focus(), str(ed.selected_marchers), ed.selected_shape, ed.is_at_set(), ed.current_set_index()]


func _maybe_rebuild() -> void:
	if _key() != _built_key:
		_rebuild()
	else:
		_refresh()


func _rebuild() -> void:
	if ed.drill == null:
		return
	_built_key = _key()
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_refreshers.clear()
	match ed.focus():
		"marcher":
			if ed.selected_marchers.size() == 1:
				_build_marcher(ed.selected_marchers[0])
			else:
				_build_multi()
		"shape":
			_build_shape()
		_:
			_build_set()
	_refresh()


func _refresh() -> void:
	if ed.drill == null:
		return
	_refreshing = true
	for r in _refreshers:
		r.call()
	_refreshing = false


## Runs an edit made from this panel: records undo, applies it, notifies.
func _edit(key: String, fn: Callable, structure := true) -> void:
	if _refreshing:
		return
	_self_edit = true
	ed.checkpoint(key)
	fn.call()
	if structure:
		ed.notify_structure()
	else:
		ed.notify_positions()
	_self_edit = false


# ---------------------------------------------------------------- widgets

func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	_body.add_child(g)
	return g


func _row(g: GridContainer, text: String, control: Control) -> Control:
	var l := Ui.label(text, 0, Ui.TEXT_DIM)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	g.add_child(l)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	g.add_child(control)
	return control


func _value_label(g: GridContainer, text: String) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row(g, text, l)
	return l


func _spin(min_v: float, max_v: float, step: float, suffix := "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.suffix = suffix
	s.select_all_on_focus = true
	return s


func _heading(text: String) -> void:
	var l := Ui.label(text.to_upper(), 11, Ui.ACCENT)
	_body.add_child(l)


func _buttons(items: Array) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.tooltip_text = it[1]
		b.focus_mode = FOCUS_NONE
		b.pressed.connect(it[2])
		flow.add_child(b)
	_body.add_child(flow)


# ---------------------------------------------------------------- set

func _build_set() -> void:
	var i := ed.current_set_index()
	var s := ed.current_set()
	var g := _grid()

	var name_edit := LineEdit.new()
	name_edit.text = s.name
	name_edit.text_changed.connect(func(t: String) -> void:
		_edit("set_name:%d" % i, func() -> void: s.name = t))
	_row(g, "Name", name_edit)

	var counts := _spin(1, 999, 1, "counts")
	counts.editable = i > 0
	counts.tooltip_text = "Counts to move from the previous set into this one." if i > 0 else "The first set has no move into it."
	counts.value_changed.connect(func(v: float) -> void:
		_edit("set_counts:%d" % i, func() -> void:
			s.counts = int(v)
			ed.refresh_time()))
	_row(g, "Counts", counts)

	var tempo := _spin(20, 400, 1, "bpm")
	tempo.editable = i > 0
	tempo.value_changed.connect(func(v: float) -> void:
		_edit("set_tempo:%d" % i, func() -> void:
			s.tempo = v
			ed.refresh_time()))
	_row(g, "Tempo", tempo)

	var timing := _value_label(g, "Timing")
	var summary := _value_label(g, "Contents")

	_heading("Notes")
	var notes := TextEdit.new()
	notes.text = s.notes
	notes.custom_minimum_size.y = 90
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.placeholder_text = "Notes for this set (visuals, cues…)"
	notes.text_changed.connect(func() -> void:
		_edit("set_notes:%d" % i, func() -> void: s.notes = notes.text, false))
	_body.add_child(notes)

	_refreshers.append(func() -> void:
		var ts := ed.drill.set_times()
		_title.text = s.name if ed.is_at_set() else "Moving into %s" % s.name
		if ed.is_at_set():
			_subtitle.text = "Set %d of %d" % [i + 1, ed.drill.sets.size()]
		else:
			_subtitle.text = "Count %.1f of %d. Go to a set to edit positions." % [float(ed.loc["count"]), s.counts]
		if not counts.get_line_edit().has_focus():
			counts.value = s.counts
		if not tempo.get_line_edit().has_focus():
			tempo.value = s.tempo
		if i == 0:
			timing.text = "Opening set, at 0:00.00"
		else:
			timing.text = "Arrives at %s (move takes %.2f s)" % [Ui.fmt_time(ts[i]), ed.drill.set_duration(i)]
		var nm := ed.drill.marchers.size()
		var ns := ed.drill.shapes_shown(s).size()
		summary.text = "%d marcher%s · %d shape%s shown" % [nm, "" if nm == 1 else "s", ns, "" if ns == 1 else "s"])


# ---------------------------------------------------------------- one marcher

func _build_marcher(id: int) -> void:
	var m := ed.drill.find_marcher(id)
	if m == null:
		return
	var ids: Array[int] = [id]
	var g := _grid()

	var lbl := LineEdit.new()
	lbl.text = m.label
	lbl.text_changed.connect(func(t: String) -> void:
		_edit("mlabel:%d" % id, func() -> void: m.label = t))
	_row(g, "Label", lbl)

	var sec := OptionButton.new()
	for n in Sections.names():
		sec.add_item(n)
	sec.select(Sections.names().find(m.section))
	sec.item_selected.connect(func(idx: int) -> void:
		_self_edit = true
		ed.set_section(ids, sec.get_item_text(idx))
		_self_edit = false)
	_row(g, "Section", sec)

	var editable := ed.is_at_set()
	var xs := _spin(-70, 70, 0.01, "yd")
	var ys := _spin(-40, 40, 0.01, "yd")
	xs.editable = editable
	ys.editable = editable
	xs.tooltip_text = "Side to side, in yards from the 50 (negative = Side 1)."
	ys.tooltip_text = "Front to back, in yards from midfield (positive = toward the front)."
	var set_axis := func(axis: int, v: float) -> void:
		var s := ed.edit_set()
		if s == null:
			return
		_edit("mpos:%d:%d" % [id, axis], func() -> void:
			ed.drill.detach(s, ids)
			var p := s.get_pos(id)
			p[axis] = v
			s.positions[id] = p)
	xs.value_changed.connect(func(v: float) -> void: set_axis.call(0, v))
	ys.value_changed.connect(func(v: float) -> void: set_axis.call(1, v))
	_row(g, "X", xs)
	_row(g, "Y", ys)
	var ss_label := _value_label(g, "Side to side")
	var fb_label := _value_label(g, "Front to back")
	var move_label := _value_label(g, "Move in")

	var face := OptionButton.new()
	for f in FACINGS:
		face.add_item(f[0])
	face.disabled = not editable
	face.item_selected.connect(func(idx: int) -> void:
		_self_edit = true
		ed.set_facing(ids, FACINGS[idx][1])
		_self_edit = false)
	_row(g, "Facing", face)

	var shape_row := HBoxContainer.new()
	var shape_label := Label.new()
	shape_label.size_flags_horizontal = SIZE_EXPAND_FILL
	shape_row.add_child(shape_label)
	var detach := Button.new()
	detach.text = "Detach"
	detach.focus_mode = FOCUS_NONE
	detach.tooltip_text = "Free this marcher from its shape (it keeps its spot)."
	detach.pressed.connect(func() -> void: ed.detach_marchers(ids))
	shape_row.add_child(detach)
	_row(g, "Shape", shape_row)

	_heading("Coordinates in every set")
	var table := Tree.new()
	table.columns = 3
	table.hide_root = true
	table.column_titles_visible = true
	table.set_column_title(0, "Set")
	table.set_column_title(1, "Side to side")
	table.set_column_title(2, "Front to back")
	table.set_column_expand(0, false)
	table.set_column_custom_minimum_width(0, 44)
	table.custom_minimum_size.y = 170
	table.select_mode = Tree.SELECT_ROW
	table.item_activated.connect(func() -> void:
		var it := table.get_selected()
		if it != null:
			ed.go_to_set(int(it.get_metadata(0))))
	table.tooltip_text = "Double-click a row to jump to that set."
	_body.add_child(table)

	_refreshers.append(func() -> void:
		var p: Vector2 = ed.drill.positions_at(ed.loc).get(id, Vector2.ZERO)
		_title.text = m.label
		_subtitle.text = m.section + ("" if editable else "  ·  between sets (read only)")
		if not xs.get_line_edit().has_focus():
			xs.value = snappedf(p.x, 0.01)
		if not ys.get_line_edit().has_focus():
			ys.value = snappedf(p.y, 0.01)
		ss_label.text = FieldCoords.describe_x(p.x)
		fb_label.text = FieldCoords.describe_y(p.y, ed.drill.hash_style)
		var si := ed.current_set_index()
		if si == 0:
			move_label.text = "Opening set"
			move_label.remove_theme_color_override("font_color")
		else:
			var cur_set := ed.drill.sets[si]
			var st := ed.drill.move_step(si, id)
			var lv := ed.drill.step_level(si, id)
			move_label.text = "%.2f yd in %d counts · %s%s" % [st * cur_set.counts, cur_set.counts, DrillShow.step_name(st),
				["", "  (large step)", "  (too big for this tempo)"][lv]]
			if lv == 0:
				move_label.remove_theme_color_override("font_color")
			else:
				move_label.add_theme_color_override("font_color", Color("#ff6b5b") if lv == 2 else Color("#ffd34d"))
		var fdeg := fposmod(ed.drill.facing_at(ed.loc, id), 360.0)
		face.select(int(roundf(fdeg / 90.0)) % 4)
		var s := ed.edit_set()
		var sh := ed.drill.shape_of(s, id) if s != null else null
		shape_label.text = "None" if sh == null else (sh.name if s.is_shown(sh.id) else "%s (hidden)" % sh.name)
		detach.disabled = sh == null
		table.clear()
		var root := table.create_item()
		for k in ed.drill.sets.size():
			var sp := ed.drill.sets[k].get_pos(id)
			var it := table.create_item(root)
			it.set_text(0, str(k + 1))
			it.set_text(1, FieldCoords.describe_x(sp.x))
			it.set_text(2, FieldCoords.describe_y(sp.y, ed.drill.hash_style))
			it.set_metadata(0, k)
			if k == ed.current_set_index() and ed.is_at_set():
				for c in 3:
					it.set_custom_bg_color(c, Color(Ui.ACCENT, 0.25)))


# ---------------------------------------------------------------- several marchers

func _build_multi() -> void:
	var ids: Array[int] = []
	ids.assign(ed.selected_marchers)
	var names := PackedStringArray()
	var sections := {}
	for id in ids:
		var m := ed.drill.find_marcher(id)
		if m != null:
			names.append(m.label)
			sections[m.section] = true
	_title.text = "%d marchers" % ids.size()
	_subtitle.text = ", ".join(names.slice(0, 24)) + ("…" if names.size() > 24 else "")

	var g := _grid()
	var sec := OptionButton.new()
	var all_names := Sections.names()
	for n in all_names:
		sec.add_item(n)
	if sections.size() == 1:
		sec.select(all_names.find(str(sections.keys()[0])))
	else:
		sec.add_item("(mixed)")
		sec.select(all_names.size())
		sec.set_item_disabled(all_names.size(), true)
	sec.item_selected.connect(func(idx: int) -> void:
		if idx < all_names.size():
			ed.set_section(ids, all_names[idx]))
	_row(g, "Section", sec)

	var face := OptionButton.new()
	for f in FACINGS:
		face.add_item(f[0])
	face.add_item("—")
	face.select(FACINGS.size())
	face.set_item_disabled(FACINGS.size(), true)
	face.disabled = not ed.is_at_set()
	face.item_selected.connect(func(idx: int) -> void:
		if idx < FACINGS.size():
			ed.set_facing(ids, FACINGS[idx][1]))
	_row(g, "Facing", face)

	if ed.is_at_set():
		_heading("Arrange")
		_buttons([
			["Align row", "Line them up front-to-back (same distance from the front).", func() -> void: ed.align_marchers(ids, "row")],
			["Align column", "Line them up side-to-side (same yard line position).", func() -> void: ed.align_marchers(ids, "column")],
			["Spread evenly", "Space them evenly on a straight line between the two farthest apart.", func() -> void: ed.align_marchers(ids, "spread")],
			["Detach from shapes", "Free them from any shapes they're attached to.", func() -> void: ed.detach_marchers(ids)],
		])
	var tip := Ui.label("Drag the selection onto a shape to attach all of them. Arrow keys nudge by a step (Shift: quarter step).", 12, Ui.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(tip)


# ---------------------------------------------------------------- shape

func _build_shape() -> void:
	var sh := ed.drill.find_shape(ed.selected_shape)
	if sh == null:
		return
	var s := ed.edit_set()
	if s == null:
		_title.text = sh.name
		_subtitle.text = "%s · go to a set to edit it" % sh.type_name()
		return
	var g := _grid()

	var name_edit := LineEdit.new()
	name_edit.text = sh.name
	name_edit.text_changed.connect(func(t: String) -> void:
		_edit("shape_name:%d" % sh.id, func() -> void: sh.name = t))
	_row(g, "Name", name_edit)

	var shown := CheckBox.new()
	shown.text = "Show in this set"
	shown.focus_mode = FOCUS_NONE
	shown.tooltip_text = "Hidden shapes aren't drawn or usable in this set. Marchers already on it stay attached."
	shown.toggled.connect(func(on: bool) -> void:
		_self_edit = true
		ed.set_shape_shown(sh.id, on)
		_self_edit = false)
	_row(g, "Visible", shown)
	var used := _value_label(g, "Used in")
	var outline := _value_label(g, "Outline")
	var outline_btns := HBoxContainer.new()
	outline_btns.add_theme_constant_override("separation", 4)
	var share := Button.new()
	share.text = "Use in all sets"
	share.focus_mode = FOCUS_NONE
	share.tooltip_text = "Make this set's points the shape's outline in every set."
	share.pressed.connect(func() -> void: ed.share_shape_points(sh.id))
	outline_btns.add_child(share)
	var reset := Button.new()
	reset.text = "Reset to shared"
	reset.focus_mode = FOCUS_NONE
	reset.tooltip_text = "Forget this set's own points and use the shared outline."
	reset.pressed.connect(func() -> void: ed.reset_shape_points(sh.id))
	outline_btns.add_child(reset)
	_row(g, "", outline_btns)

	if sh.type in ["polygon", "curve", "freeform"]:
		var closed := CheckBox.new()
		closed.text = "Closed loop"
		closed.button_pressed = sh.closed
		closed.focus_mode = FOCUS_NONE
		closed.toggled.connect(func(on: bool) -> void:
			_edit("shape_closed:%d" % sh.id, func() -> void:
				sh.closed = on
				ed.drill.relayout_everywhere(sh)))
		_row(g, "Shape", closed)

	if sh.type in ["rect", "polygon"]:
		var pin := CheckBox.new()
		pin.text = "Marchers on corners"
		pin.button_pressed = sh.corners
		pin.focus_mode = FOCUS_NONE
		pin.tooltip_text = "Always put a marcher on every corner, spreading the rest evenly along each side (all sets)."
		pin.toggled.connect(func(on: bool) -> void:
			_edit("shape_corners:%d" % sh.id, func() -> void:
				sh.corners = on
				ed.drill.relayout_everywhere(sh)))
		_row(g, "Corners", pin)

	var rot := HSlider.new()
	rot.min_value = 0.0
	rot.max_value = 1.0
	rot.step = 0.001
	rot.value = s.offset_of(sh.id)
	rot.tooltip_text = "Slides marchers around a closed shape (this set only)."
	rot.value_changed.connect(func(v: float) -> void:
		_edit("shape_rot:%d" % sh.id, func() -> void:
			s.offsets[sh.id] = v
			ed.drill.relayout(s, sh), false))
	var rot_ctl := _row(g, "Rotate", rot)

	var length := _value_label(g, "Length")
	var spacing := _value_label(g, "Interval")
	var moves := _value_label(g, "Moves in")

	_heading("Marcher order")
	var order := ItemList.new()
	order.custom_minimum_size.y = 120
	order.max_columns = 0
	order.same_column_width = true
	order.fixed_column_width = 56
	order.select_mode = ItemList.SELECT_MULTI
	order.focus_mode = FOCUS_NONE
	_body.add_child(order)

	var ids_of := func() -> Array[int]:
		var out: Array[int] = []
		out.assign(s.on_shape(sh.id))
		return out
	if ed.current_set_index() > 0:
		_buttons([
			["Order by shortest moves", "Reorder the marchers on this shape so the average distance from where they were in the previous set is as small as possible (no crossing paths). Closed shapes are also rotated for the best fit.", func() -> void: ed.order_shape_by_moves(sh.id)],
		])
	_buttons([
		["Select marchers", "Select everyone attached to this shape.", func() -> void: ed.select_marchers(ids_of.call())],
		["Reverse order", "Flip which end each marcher is on (this set only).", func() -> void:
			_edit("", func() -> void:
				s.on_shape(sh.id).reverse()
				ed.drill.relayout(s, sh))],
		["Release all", "Detach all marchers in this set (they keep their spots).", func() -> void: ed.detach_marchers(ids_of.call())],
		["Delete shape", "Delete this shape from every set. Marchers stay where they are.", func() -> void: ed.delete_shape(sh.id)],
	])

	_refreshers.append(func() -> void:
		_title.text = sh.name
		var n := s.count_on(sh.id)
		_subtitle.text = "%s · %d marchers in this set%s" % [sh.type_name(), n, "" if s.is_shown(sh.id) else " · hidden here"]
		shown.set_pressed_no_signal(s.is_shown(sh.id))
		var shown_in := 0
		var with_marchers := 0
		for other in ed.drill.sets:
			if other.is_shown(sh.id):
				shown_in += 1
			if other.count_on(sh.id) > 0:
				with_marchers += 1
		used.text = "Shown in %d of %d sets · has marchers in %d" % [shown_in, ed.drill.sets.size(), with_marchers]
		var own := ed.drill.has_own_form(s, sh)
		var n_own := 0
		for other in ed.drill.sets:
			if other.forms.has(sh.id):
				n_own += 1
		outline.text = "Own points in this set" if own else "Shared"
		if n_own > (1 if own else 0):
			outline.text += "  (%d other set%s have their own)" % [n_own - (1 if own else 0), "" if n_own - (1 if own else 0) == 1 else "s"]
		reset.disabled = not own
		share.disabled = n_own == 0
		var shf := ed.drill.form(s, sh)
		var closed_now := ShapeGeom.is_closed(sh)
		rot_ctl.get_parent().get_child(rot_ctl.get_index() - 1).visible = closed_now
		rot.visible = closed_now
		var total := ShapeGeom.length(shf)
		length.text = "%.2f yd  (%s steps)" % [total, FieldCoords.fmt_steps(total / FieldCoords.STEP)]
		var gr := ShapeGeom.gap_range(shf, n)
		if n < 2:
			spacing.text = "—"
		elif gr.y - gr.x < 0.01:
			spacing.text = "%.2f yd  (%s-step interval)" % [gr.y, FieldCoords.fmt_steps(gr.y / FieldCoords.STEP)]
		else:
			spacing.text = "%.2f–%.2f yd  (%s–%s steps)" % [gr.x, gr.y, FieldCoords.fmt_steps(gr.x / FieldCoords.STEP), FieldCoords.fmt_steps(gr.y / FieldCoords.STEP)]
		if sh.corners and ShapeGeom.has_corners(shf) and n < ShapeGeom.corner_count(shf):
			spacing.text += "\nNeeds %d marchers to fill every corner" % ShapeGeom.corner_count(shf)
		var si := ed.current_set_index()
		if si == 0:
			moves.text = "Opening set"
		elif n == 0:
			moves.text = "—"
		else:
			var st := ed.drill.move_stats(si, ids_of.call())
			moves.text = "avg %.2f yd · longest %.2f yd" % [st.x, st.y]
		order.clear()
		for id in s.on_shape(sh.id):
			var m := ed.drill.find_marcher(id)
			if m != null:
				var idx := order.add_item(m.label)
				order.set_item_custom_fg_color(idx, Sections.color(m.section)))
