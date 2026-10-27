class_name SetsTab
extends VBoxContainer
## List of sets. Selecting one jumps the editor and preview to it.

var ed: DrillEditor
var tree: Tree
var _sync := false
var _last_key := ""


func setup(editor: DrillEditor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)
	tree = Tree.new()
	tree.columns = 4
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.size_flags_vertical = SIZE_EXPAND_FILL
	var cols := [["#", 40, false], ["Name", 0, true], ["Counts", 64, false], ["Time", 72, false]]
	for i in cols.size():
		tree.set_column_title(i, cols[i][0])
		tree.set_column_expand(i, cols[i][2])
		if cols[i][1] > 0:
			tree.set_column_custom_minimum_width(i, cols[i][1])
	tree.item_selected.connect(_on_selected)
	tree.item_mouse_selected.connect(func(_p: Vector2, _b: int) -> void: _on_selected(true))
	add_child(tree)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var add := Ui.icon_button("plus", "Add a set after the current one (copies its positions and shape use)", "Add Set")
	add.pressed.connect(func() -> void: ed.add_set_after(ed.current_set_index()))
	row.add_child(add)
	var del := Ui.icon_button("trash", "Delete the current set", "Delete")
	del.pressed.connect(func() -> void: ed.delete_set(ed.current_set_index()))
	row.add_child(del)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)
	var up := Ui.icon_button("up", "Move set earlier")
	up.pressed.connect(func() -> void: ed.move_set(ed.current_set_index(), -1))
	row.add_child(up)
	var down := Ui.icon_button("down", "Move set later")
	down.pressed.connect(func() -> void: ed.move_set(ed.current_set_index(), 1))
	row.add_child(down)
	add_child(row)

	ed.structure_changed.connect(_rebuild)
	ed.time_changed.connect(_sync_selection)


func _rebuild() -> void:
	_sync = true
	tree.clear()
	var root := tree.create_item()
	var ts := ed.drill.set_times()
	for i in ed.drill.sets.size():
		var s := ed.drill.sets[i]
		var it := tree.create_item(root)
		it.set_text(0, str(i + 1))
		it.set_text(1, s.name)
		it.set_text(2, "—" if i == 0 else str(s.counts))
		it.set_text(3, Ui.fmt_time(ts[i]))
		it.set_metadata(0, i)
		for c in [0, 2, 3]:
			it.set_text_alignment(c, HORIZONTAL_ALIGNMENT_RIGHT)
	_sync = false
	_last_key = ""
	_sync_selection()


func _sync_selection() -> void:
	var key := "%d:%s" % [ed.current_set_index(), ed.is_at_set()]
	if key == _last_key:
		return
	_last_key = key
	_sync = true
	tree.deselect_all()
	var root := tree.get_root()
	if root != null:
		var it := root.get_first_child()
		while it != null:
			if int(it.get_metadata(0)) == ed.current_set_index():
				if ed.is_at_set():
					it.select(0)
				tree.scroll_to_item(it)
			it = it.get_next()
	_sync = false


func _on_selected(clicked := false) -> void:
	if _sync:
		return
	var it := tree.get_selected()
	if it == null:
		return
	ed.go_to_set(int(it.get_metadata(0)))
	if clicked or ed.focus() != "set":
		ed.clear_selection()
