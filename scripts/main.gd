extends Control
## Builds the window layout and handles menus, files and keyboard shortcuts.
##
## ┌──────── Tools ────────┐┌── Sets/Marchers/Shapes ──┐
## │        Editor         ││                          │
## │                       │├──────── Set Info ────────┤
## ├─────── Preview ───────┤│                          │
## └───────────────────────┘└──────────────────────────┘

const TOOLS := [
	["select", "Select", "V"],
	["line", "Line", "L"],
	["rect", "Rectangle", "R"],
	["ellipse", "Ellipse", "E"],
	["polygon", "Polygon", "P"],
	["curve", "Curve", "C"],
	["freeform", "Freeform", "F"],
]
const TOOL_KEYS := {KEY_V: "select", KEY_L: "line", KEY_R: "rect", KEY_E: "ellipse", KEY_P: "polygon", KEY_C: "curve", KEY_F: "freeform"}

enum FileId { NEW, OPEN, SAVE, SAVE_AS, EXPORT_CSV }
enum EditId { UNDO, REDO, SELECT_ALL, DESELECT, DELETE_SHAPE }
enum ViewId { SNAP, GRID, GHOST, PATHS, LABELS, SPACING, STEPS, HASH_HS, HASH_NCAA, HASH_NFL, FIT, SCALE_AUTO, SCALE_100, SCALE_125, SCALE_150, SCALE_200 }

var ed: DrillEditor
var field: FieldView
var preview: PreviewPanel
var info: InfoPanel
var tabs: TabContainer

var _tool_buttons := {}
var _view_popup: PopupMenu
var _edit_popup: PopupMenu
var _snap_check: CheckBox
var _undo_btn: Button
var _redo_btn: Button
var _file_dialog: FileDialog
var _dialog_mode := ""
var _confirm: ConfirmationDialog
var _pending: Callable
var _error: AcceptDialog
var _ui_scale := 0.0  # 0 = automatic
var _toolbar: HBoxContainer
var _toolbar_full_w := 0.0
var _compact := false
var _rsplit: VSplitContainer

const RIGHT_MIN_W := 340


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	set_anchors_preset(PRESET_FULL_RECT)
	_apply_ui_scale(0.0)
	if not OS.has_feature("headless"):
		get_window().mode = Window.MODE_MAXIMIZED
	theme = _make_theme()

	ed = DrillEditor.new()
	ed.name = "Editor"
	add_child(ed)
	_build_ui()
	_build_dialogs()

	ed.file_changed.connect(_update_title)
	ed.tool_changed.connect(_sync_tools)
	ed.view_changed.connect(_sync_view_menu)
	for sig in [ed.structure_changed, ed.positions_changed, ed.file_changed]:
		sig.connect(_sync_undo_buttons)
	ed.set_drill(DrillShow.make_demo())
	_sync_tools()
	_sync_view_menu()
	_toolbar_full_w = _toolbar.get_combined_minimum_size().x
	resized.connect(_update_compact)
	_update_compact()


## On narrow windows the tool buttons drop their text (icons + tooltips
## remain) so the right-hand column always has room.
func _update_compact() -> void:
	var available := size.x - RIGHT_MIN_W - 40.0
	var compact := available < _toolbar_full_w
	if compact == _compact:
		return
	_compact = compact
	for t in TOOLS:
		_tool_buttons[t[0]].text = "" if compact else t[1]
	_snap_check.text = "Snap" if compact else "Snap to steps"


# ---------------------------------------------------------------- layout

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_stylebox("panel", "PanelContainer", Ui.panel_style())
	var tab_panel := Ui.panel_style(Ui.PANEL, 8)
	tab_panel.corner_radius_top_left = 0
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_constant("separation", "HSplitContainer", 6)
	t.set_constant("separation", "VSplitContainer", 6)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(Ui.ACCENT, 0.35)
	t.set_stylebox("selected", "Tree", sel)
	t.set_stylebox("selected_focus", "Tree", sel)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	return t


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Ui.BG
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	var hsplit := HSplitContainer.new()
	margin.add_child(hsplit)

	# Left column: tools, editor, preview
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	hsplit.add_child(left)
	left.add_child(_build_toolbar())

	var lsplit := VSplitContainer.new()
	lsplit.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(lsplit)

	var field_panel := PanelContainer.new()
	field_panel.add_theme_stylebox_override("panel", Ui.panel_style(Ui.PANEL, 2))
	field_panel.size_flags_vertical = SIZE_EXPAND_FILL
	field = FieldView.new()
	field.setup(ed)
	field_panel.add_child(field)
	lsplit.add_child(field_panel)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size.y = 190
	preview = PreviewPanel.new()
	preview.setup(ed)
	preview_panel.add_child(preview)
	lsplit.add_child(preview_panel)

	# Right column: tabs over info
	var rsplit := VSplitContainer.new()
	rsplit.custom_minimum_size.x = RIGHT_MIN_W
	_rsplit = rsplit
	hsplit.add_child(rsplit)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.size_flags_stretch_ratio = 1.4
	var sets_tab := SetsTab.new()
	sets_tab.name = "Sets"
	sets_tab.setup(ed)
	tabs.add_child(sets_tab)
	var marchers_tab := MarchersTab.new()
	marchers_tab.name = "Marchers"
	marchers_tab.setup(ed)
	tabs.add_child(marchers_tab)
	var shapes_tab := ShapesTab.new()
	shapes_tab.name = "Shapes"
	shapes_tab.setup(ed)
	tabs.add_child(shapes_tab)
	rsplit.add_child(tabs)

	var info_panel := PanelContainer.new()
	info_panel.size_flags_vertical = SIZE_EXPAND_FILL
	info = InfoPanel.new()
	info.setup(ed)
	info_panel.add_child(info)
	rsplit.add_child(info_panel)


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.panel_style(Ui.PANEL, 5))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	panel.add_child(hb)
	_toolbar = hb

	var cmd := Ui.cmd_name()
	var file_menu := MenuButton.new()
	file_menu.text = "File"
	file_menu.flat = false
	var fp := file_menu.get_popup()
	fp.add_item("New Show  (%s+N)" % cmd, FileId.NEW)
	fp.add_item("Open…  (%s+O)" % cmd, FileId.OPEN)
	fp.add_separator()
	fp.add_item("Save  (%s+S)" % cmd, FileId.SAVE)
	fp.add_item("Save As…  (%s+Shift+S)" % cmd, FileId.SAVE_AS)
	fp.add_separator()
	fp.add_item("Export Coordinates (CSV)…", FileId.EXPORT_CSV)
	fp.id_pressed.connect(_on_file_menu)
	hb.add_child(file_menu)

	var edit_menu := MenuButton.new()
	edit_menu.text = "Edit"
	edit_menu.flat = false
	_edit_popup = edit_menu.get_popup()
	_edit_popup.add_item("Undo  (%s+Z)" % cmd, EditId.UNDO)
	_edit_popup.add_item("Redo  (%s+Shift+Z)" % cmd, EditId.REDO)
	_edit_popup.add_separator()
	_edit_popup.add_item("Select All Marchers  (%s+A)" % cmd, EditId.SELECT_ALL)
	_edit_popup.add_item("Deselect  (Esc)", EditId.DESELECT)
	_edit_popup.add_item("Delete Selected Shape  (Delete)", EditId.DELETE_SHAPE)
	_edit_popup.id_pressed.connect(_on_edit_menu)
	hb.add_child(edit_menu)

	var view_menu := MenuButton.new()
	view_menu.text = "View"
	view_menu.flat = false
	_view_popup = view_menu.get_popup()
	_view_popup.hide_on_checkable_item_selection = false
	_view_popup.add_check_item("Snap to Steps", ViewId.SNAP)
	_view_popup.add_check_item("4-Step Grid", ViewId.GRID)
	_view_popup.add_check_item("Previous Set Ghosts", ViewId.GHOST)
	_view_popup.add_check_item("Movement Paths", ViewId.PATHS)
	_view_popup.add_check_item("Marcher Labels", ViewId.LABELS)
	_view_popup.add_check_item("Spacing Warnings", ViewId.SPACING)
	_view_popup.add_check_item("Step Size Warnings", ViewId.STEPS)
	_view_popup.add_separator("Hash Marks")
	_view_popup.add_radio_check_item("High School", ViewId.HASH_HS)
	_view_popup.add_radio_check_item("College", ViewId.HASH_NCAA)
	_view_popup.add_radio_check_item("NFL", ViewId.HASH_NFL)
	_view_popup.add_separator()
	_view_popup.add_item("Zoom to Fit  (%s+0)" % cmd, ViewId.FIT)
	_view_popup.add_separator("Interface Size")
	_view_popup.add_radio_check_item("Automatic", ViewId.SCALE_AUTO)
	_view_popup.add_radio_check_item("100%", ViewId.SCALE_100)
	_view_popup.add_radio_check_item("125%", ViewId.SCALE_125)
	_view_popup.add_radio_check_item("150%", ViewId.SCALE_150)
	_view_popup.add_radio_check_item("200%", ViewId.SCALE_200)
	_view_popup.id_pressed.connect(_on_view_menu)
	hb.add_child(view_menu)

	hb.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for t in TOOLS:
		var b := Ui.icon_button(t[0], "%s (%s)" % [t[1], t[2]], t[1])
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(ed.set_tool.bind(t[0]))
		_tool_buttons[t[0]] = b
		hb.add_child(b)

	hb.add_child(VSeparator.new())
	_undo_btn = Ui.icon_button("undo", "Undo (%s+Z)" % cmd)
	_undo_btn.pressed.connect(ed.undo)
	hb.add_child(_undo_btn)
	_redo_btn = Ui.icon_button("redo", "Redo (%s+Shift+Z)" % cmd)
	_redo_btn.pressed.connect(ed.redo)
	hb.add_child(_redo_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	hb.add_child(spacer)
	_snap_check = CheckBox.new()
	_snap_check.text = "Snap to steps"
	_snap_check.focus_mode = FOCUS_NONE
	_snap_check.tooltip_text = "Snap positions to the 8-to-5 step grid."
	_snap_check.toggled.connect(func(on: bool) -> void: ed.set_view("snap", on))
	hb.add_child(_snap_check)
	var fit := Ui.icon_button("fit", "Zoom to fit the field (%s+0)" % cmd)
	fit.pressed.connect(func() -> void: field.fit_view())
	hb.add_child(fit)
	return panel


func _build_dialogs() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(_on_file_chosen)
	add_child(_file_dialog)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Unsaved Changes"
	_confirm.dialog_text = "This show has unsaved changes. Discard them?"
	_confirm.ok_button_text = "Discard"
	_confirm.confirmed.connect(func() -> void:
		if _pending.is_valid():
			_pending.call())
	add_child(_confirm)

	_error = AcceptDialog.new()
	_error.title = "Driller"
	add_child(_error)


# ---------------------------------------------------------------- syncing

func _update_title() -> void:
	var file_name := ed.file_path.get_file() if ed.file_path != "" else "Untitled"
	get_window().title = "%s%s — Driller" % [file_name, " *" if ed.dirty else ""]


func _sync_tools() -> void:
	for t in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == ed.tool)


func _sync_undo_buttons() -> void:
	_undo_btn.disabled = not ed.can_undo()
	_redo_btn.disabled = not ed.can_redo()


func _sync_view_menu() -> void:
	var p := _view_popup
	p.set_item_checked(p.get_item_index(ViewId.SNAP), ed.snap)
	p.set_item_checked(p.get_item_index(ViewId.GRID), ed.show_grid)
	p.set_item_checked(p.get_item_index(ViewId.GHOST), ed.show_ghost)
	p.set_item_checked(p.get_item_index(ViewId.PATHS), ed.show_paths)
	p.set_item_checked(p.get_item_index(ViewId.LABELS), ed.show_labels)
	p.set_item_checked(p.get_item_index(ViewId.SPACING), ed.show_spacing)
	p.set_item_checked(p.get_item_index(ViewId.STEPS), ed.show_step_warnings)
	var hs := ed.drill.hash_style if ed.drill != null else "HS"
	p.set_item_checked(p.get_item_index(ViewId.HASH_HS), hs == "HS")
	p.set_item_checked(p.get_item_index(ViewId.HASH_NCAA), hs == "NCAA")
	p.set_item_checked(p.get_item_index(ViewId.HASH_NFL), hs == "NFL")
	var scales := {ViewId.SCALE_AUTO: 0.0, ViewId.SCALE_100: 1.0, ViewId.SCALE_125: 1.25, ViewId.SCALE_150: 1.5, ViewId.SCALE_200: 2.0}
	for id in scales:
		p.set_item_checked(p.get_item_index(id), is_equal_approx(scales[id], _ui_scale))
	_snap_check.set_pressed_no_signal(ed.snap)


## The layout is sized as window size / scale, so the UI stays the same
## physical size whatever the window size (and is sharp on HiDPI screens).
func _apply_ui_scale(s: float) -> void:
	_ui_scale = s
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_factor = 1.0
	if not win.size_changed.is_connected(_update_scale):
		win.size_changed.connect(_update_scale)
	_update_scale()


func _update_scale() -> void:
	var f := _ui_scale if _ui_scale > 0.0 else maxf(DisplayServer.screen_get_scale(), 1.0)
	var win := get_window()
	win.content_scale_size = Vector2i((Vector2(win.size) / f).round())


# ---------------------------------------------------------------- menus

func _on_file_menu(id: int) -> void:
	match id:
		FileId.NEW:
			_confirm_discard(func() -> void:
				var d := DrillShow.new()
				d.sets.append(DrillSet.new())
				ed.set_drill(d)
				field.fit_view())
		FileId.OPEN:
			_confirm_discard(func() -> void: _open_dialog("open"))
		FileId.SAVE:
			save()
		FileId.SAVE_AS:
			_open_dialog("save")
		FileId.EXPORT_CSV:
			_open_dialog("export")


func _on_edit_menu(id: int) -> void:
	match id:
		EditId.UNDO:
			ed.undo()
		EditId.REDO:
			ed.redo()
		EditId.SELECT_ALL:
			ed.select_all()
		EditId.DESELECT:
			ed.clear_selection()
		EditId.DELETE_SHAPE:
			if ed.selected_shape != -1:
				ed.delete_shape(ed.selected_shape)


func _on_view_menu(id: int) -> void:
	match id:
		ViewId.SNAP:
			ed.set_view("snap", not ed.snap)
		ViewId.GRID:
			ed.set_view("show_grid", not ed.show_grid)
		ViewId.GHOST:
			ed.set_view("show_ghost", not ed.show_ghost)
		ViewId.PATHS:
			ed.set_view("show_paths", not ed.show_paths)
		ViewId.LABELS:
			ed.set_view("show_labels", not ed.show_labels)
		ViewId.SPACING:
			ed.set_view("show_spacing", not ed.show_spacing)
		ViewId.STEPS:
			ed.set_view("show_step_warnings", not ed.show_step_warnings)
		ViewId.HASH_HS:
			ed.set_hash_style("HS")
		ViewId.HASH_NCAA:
			ed.set_hash_style("NCAA")
		ViewId.HASH_NFL:
			ed.set_hash_style("NFL")
		ViewId.FIT:
			field.fit_view()
		ViewId.SCALE_AUTO:
			_apply_ui_scale(0.0)
		ViewId.SCALE_100:
			_apply_ui_scale(1.0)
		ViewId.SCALE_125:
			_apply_ui_scale(1.25)
		ViewId.SCALE_150:
			_apply_ui_scale(1.5)
		ViewId.SCALE_200:
			_apply_ui_scale(2.0)
	_sync_view_menu()


# ---------------------------------------------------------------- files

func _confirm_discard(then: Callable) -> void:
	if not ed.dirty:
		then.call()
		return
	_pending = then
	_confirm.popup_centered()


func _open_dialog(mode: String) -> void:
	_dialog_mode = mode
	var fd := _file_dialog
	match mode:
		"open":
			fd.title = "Open Show"
			fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			fd.filters = PackedStringArray(["*.drill ; Drill Shows"])
		"save":
			fd.title = "Save Show"
			fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			fd.filters = PackedStringArray(["*.drill ; Drill Shows"])
			fd.current_file = ed.file_path.get_file() if ed.file_path != "" else "show.drill"
		"export":
			fd.title = "Export Coordinates"
			fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			fd.filters = PackedStringArray(["*.csv ; CSV"])
			fd.current_file = "coordinates.csv"
	fd.popup_centered_ratio(0.6)


func _on_file_chosen(path: String) -> void:
	match _dialog_mode:
		"open":
			_load(path)
		"save":
			if path.get_extension().to_lower() != "drill":
				path += ".drill"
			_save_to(path)
		"export":
			if path.get_extension().to_lower() != "csv":
				path += ".csv"
			_export_csv(path)


func save() -> void:
	if ed.file_path == "":
		_open_dialog("save")
	else:
		_save_to(ed.file_path)


func _save_to(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_show_error("Couldn't save to %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(ed.drill.to_dict(), "\t"))
	f.close()
	ed.mark_saved(path)


func _load(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		_show_error("%s isn't a valid show file." % path.get_file())
		return
	ed.set_drill(DrillShow.from_dict(data), path)
	field.fit_view()


func _export_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_show_error("Couldn't write %s." % path)
		return
	f.store_csv_line(PackedStringArray(["Set", "Counts", "Marcher", "Section", "Side to side", "Front to back", "X (yd)", "Y (yd)"]))
	var d := ed.drill
	for i in d.sets.size():
		var s := d.sets[i]
		for m in d.marchers:
			var p := s.get_pos(m.id)
			f.store_csv_line(PackedStringArray([
				s.name, str(s.counts) if i > 0 else "", m.label, m.section,
				FieldCoords.describe_x(p.x), FieldCoords.describe_y(p.y, d.hash_style),
				"%.3f" % p.x, "%.3f" % p.y,
			]))
	f.close()


func _show_error(msg: String) -> void:
	_error.dialog_text = msg
	_error.popup_centered()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_confirm_discard(func() -> void: get_tree().quit())


# ---------------------------------------------------------------- shortcuts

func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if k.is_command_or_control_pressed():
		match k.keycode:
			KEY_Z:
				if k.shift_pressed:
					ed.redo()
				else:
					ed.undo()
			KEY_Y:
				ed.redo()
			KEY_S:
				if k.shift_pressed:
					_open_dialog("save")
				else:
					save()
			KEY_O:
				_on_file_menu(FileId.OPEN)
			KEY_N:
				_on_file_menu(FileId.NEW)
			KEY_A:
				ed.select_all()
			KEY_0:
				field.fit_view()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if k.alt_pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			preview.toggle_play()
		KEY_BRACKETLEFT:
			preview.step_set(-1)
		KEY_BRACKETRIGHT:
			preview.step_set(1)
		KEY_HOME:
			preview.seek_to_set(0)
		_:
			if TOOL_KEYS.has(k.keycode) and not k.shift_pressed:
				ed.set_tool(TOOL_KEYS[k.keycode])
			else:
				return
	get_viewport().set_input_as_handled()
