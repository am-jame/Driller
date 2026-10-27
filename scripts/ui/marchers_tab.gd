class_name MarchersTab
extends VBoxContainer
## Roster of marchers. Rows can be dragged onto a shape in the editor.

var ed: DrillEditor
var tree: Tree
var section_pick: OptionButton
var count_spin: SpinBox
var _sync := false
var _push_queued := false


func setup(editor: DrillEditor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)
	tree = Tree.new()
	tree.columns = 3
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = SIZE_EXPAND_FILL
	tree.set_column_title(0, "Label")
	tree.set_column_title(1, "Section")
	tree.set_column_title(2, "Shape (this set)")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 70)
	tree.multi_selected.connect(func(_it: TreeItem, _c: int, _s: bool) -> void: _queue_push())
	tree.set_drag_forwarding(_get_drag, Callable(), Callable())
	add_child(tree)

	var hint := Ui.label("Tip: drag rows onto a shape in the editor to attach them.", 12, Ui.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	section_pick = OptionButton.new()
	section_pick.focus_mode = FOCUS_NONE
	for n in Sections.names():
		section_pick.add_item(n)
	section_pick.select(Sections.names().find("Trumpet"))
	section_pick.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(section_pick)
	count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 200
	count_spin.value = 4
	count_spin.tooltip_text = "How many to add"
	row.add_child(count_spin)
	var add := Ui.icon_button("plus", "Add marchers of this section", "Add")
	add.pressed.connect(func() -> void:
		ed.add_marchers(section_pick.get_item_text(section_pick.selected), int(count_spin.value)))
	row.add_child(add)
	var del := Ui.icon_button("trash", "Remove the selected marchers from the show")
	del.pressed.connect(func() -> void:
		var ids: Array[int] = []
		ids.assign(ed.selected_marchers)
		ed.remove_marchers(ids))
	row.add_child(del)
	add_child(row)

	ed.structure_changed.connect(_rebuild)
	ed.selection_changed.connect(_sync_selection)
	ed.time_changed.connect(_on_time)


var _last_set := -1


func _on_time() -> void:
	var key := ed.current_set_index() if ed.is_at_set() else -1
	if key != _last_set:
		_rebuild()


func _rebuild() -> void:
	_last_set = ed.current_set_index() if ed.is_at_set() else -1
	_sync = true
	tree.clear()
	var root := tree.create_item()
	var s := ed.edit_set()
	for m in ed.drill.marchers:
		var it := tree.create_item(root)
		it.set_text(0, m.label)
		it.set_text(1, m.section)
		it.set_custom_color(1, Sections.color(m.section))
		var sh := ed.drill.shape_of(s, m.id) if s != null else null
		it.set_text(2, sh.name if sh != null else "—")
		it.set_metadata(0, m.id)
	_sync = false
	_sync_selection()


func _sync_selection() -> void:
	_sync = true
	var root := tree.get_root()
	if root != null:
		var it := root.get_first_child()
		while it != null:
			var want := ed.selected_marchers.has(int(it.get_metadata(0)))
			for c in tree.columns:
				if want != it.is_selected(c):
					if want:
						it.select(c)
					else:
						it.deselect(c)
			it = it.get_next()
	_sync = false


func _queue_push() -> void:
	if _sync or _push_queued:
		return
	_push_queued = true
	_push_selection.call_deferred()


func _push_selection() -> void:
	_push_queued = false
	var ids := _selected_ids()
	if ids != ed.selected_marchers:
		ed.select_marchers(ids)


func _selected_ids() -> Array[int]:
	var ids: Array[int] = []
	var it := tree.get_next_selected(null)
	while it != null:
		ids.append(int(it.get_metadata(0)))
		it = tree.get_next_selected(it)
	return ids


func _get_drag(at_position: Vector2) -> Variant:
	var ids := _selected_ids()
	var under := tree.get_item_at_position(at_position)
	if under != null and not ids.has(int(under.get_metadata(0))):
		ids.clear()
		ids.append(int(under.get_metadata(0)))
	if ids.is_empty():
		return null
	var lbl := Label.new()
	var names := PackedStringArray()
	for id in ids.slice(0, 6):
		var m := ed.drill.find_marcher(id)
		if m != null:
			names.append(m.label)
	lbl.text = ", ".join(names) + ("…" if ids.size() > 6 else "") + "  → drop on a shape"
	tree.set_drag_preview(lbl)
	return {"type": "marchers", "ids": ids}
