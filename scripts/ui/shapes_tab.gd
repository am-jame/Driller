class_name ShapesTab
extends VBoxContainer
## Every shape in the show. The checkbox shows or hides a shape in the
## current set; the count is how many marchers are on it in this set.

var ed: DrillEditor
var tree: Tree
var empty_label: Label
var _all_btn: Button
var _none_btn: Button
var _sync := false
var _last_set := -2


func setup(editor: DrillEditor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)
	tree = Tree.new()
	tree.columns = 4
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.size_flags_vertical = SIZE_EXPAND_FILL
	tree.set_column_title(0, "Show")
	tree.set_column_title(1, "Name")
	tree.set_column_title(2, "Type")
	tree.set_column_title(3, "Marchers")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 52)
	tree.set_column_expand(3, false)
	tree.set_column_custom_minimum_width(3, 80)
	tree.item_selected.connect(_on_selected)
	tree.item_edited.connect(_on_edited)
	add_child(tree)

	empty_label = Ui.label("", 12, Ui.TEXT_DIM)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(empty_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_all_btn = Button.new()
	_all_btn.text = "Show in all sets"
	_all_btn.focus_mode = FOCUS_NONE
	_all_btn.tooltip_text = "Show the selected shape in every set."
	_all_btn.pressed.connect(func() -> void:
		if ed.selected_shape != -1:
			ed.set_shape_shown(ed.selected_shape, true, -1))
	row.add_child(_all_btn)
	_none_btn = Button.new()
	_none_btn.text = "Only this set"
	_none_btn.focus_mode = FOCUS_NONE
	_none_btn.tooltip_text = "Hide the selected shape in every other set."
	_none_btn.pressed.connect(func() -> void:
		var id := ed.selected_shape
		if id == -1 or not ed.is_at_set():
			return
		ed.checkpoint()
		for k in ed.drill.sets.size():
			ed.drill.sets[k].set_shown(id, k == ed.current_set_index())
		ed.notify_structure())
	row.add_child(_none_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)
	var del := Ui.icon_button("trash", "Delete the selected shape from every set (its marchers stay where they are)")
	del.pressed.connect(func() -> void:
		if ed.selected_shape != -1:
			ed.delete_shape(ed.selected_shape))
	row.add_child(del)
	add_child(row)

	ed.structure_changed.connect(_rebuild)
	ed.selection_changed.connect(_sync_selection)
	ed.time_changed.connect(func() -> void:
		var key := ed.current_set_index() if ed.is_at_set() else -1
		if key != _last_set:
			_rebuild())


func _rebuild() -> void:
	_last_set = ed.current_set_index() if ed.is_at_set() else -1
	_sync = true
	tree.clear()
	var root := tree.create_item()
	var s := ed.edit_set()
	for sh in ed.drill.shapes:
		var it := tree.create_item(root)
		it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		it.set_editable(0, s != null)
		it.set_checked(0, s == null or s.is_shown(sh.id))
		it.set_tooltip_text(0, "Show this shape in the current set")
		it.set_text(1, sh.name)
		it.set_text(2, sh.type_name())
		it.set_text(3, str(s.count_on(sh.id)) if s != null else "—")
		it.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)
		it.set_metadata(0, sh.id)
		if s != null and not s.is_shown(sh.id):
			for c in [1, 2, 3]:
				it.set_custom_color(c, Ui.TEXT_DIM)
	if ed.drill.shapes.is_empty():
		empty_label.text = "No shapes yet. Pick a shape tool in the toolbar and draw on the field. Shapes are shared by every set."
	elif s == null:
		empty_label.text = "Go to a set to show, hide or use shapes."
	else:
		empty_label.text = "Shapes are shared by every set. Untick to hide one in this set; drag marchers onto a shape to space them evenly along it."
	_sync = false
	_sync_selection()


func _sync_selection() -> void:
	_sync = true
	tree.deselect_all()
	var root := tree.get_root()
	if root != null:
		var it := root.get_first_child()
		while it != null:
			if int(it.get_metadata(0)) == ed.selected_shape:
				it.select(1)
			it = it.get_next()
	var has := ed.selected_shape != -1
	_all_btn.disabled = not has
	_none_btn.disabled = not has or not ed.is_at_set()
	_sync = false


func _on_selected() -> void:
	if _sync:
		return
	var it := tree.get_selected()
	if it != null:
		ed.select_shape(int(it.get_metadata(0)))


func _on_edited() -> void:
	if _sync:
		return
	var it := tree.get_edited()
	if it == null or tree.get_edited_column() != 0:
		return
	var id := int(it.get_metadata(0))
	var on := it.is_checked(0)
	(func() -> void: ed.set_shape_shown(id, on)).call_deferred()
