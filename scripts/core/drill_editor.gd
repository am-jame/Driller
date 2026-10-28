class_name DrillEditor
extends Node
## Shared editor state. Every panel reads from and edits through this, and
## listens to its signals to stay in sync.

signal structure_changed  ## marchers / sets / shapes added, removed, renamed or reassigned
signal positions_changed  ## something moved
signal selection_changed
signal time_changed
signal tool_changed
signal view_changed
signal file_changed  ## path or unsaved state changed
signal show_replaced  ## a different show was loaded

const UNDO_LIMIT := 200

var drill: DrillShow
var time := 0.0
var loc := {"at_set": true, "set": 0, "from": 0, "frac": 0.0, "count": 0.0}
var selected_marchers: Array[int] = []
var selected_shape := -1
var tool := "select"
var file_path := ""
var dirty := false

# View options
var snap := false
var show_grid := true
var show_ghost := true
var show_paths := true
var show_labels := true
var show_spacing := true
var show_step_warnings := true
## Inaccurate preview: draw everyone slightly off their dots (display only).
var sloppy := false
var sloppy_amount := 0.6  # yards, at most
var sloppy_seed := 1

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _ck_key := ""
var _ck_msec := 0


func set_drill(d: DrillShow, path := "") -> void:
	drill = d
	file_path = path
	dirty = false
	_undo.clear()
	_redo.clear()
	_ck_key = ""
	selected_marchers.clear()
	selected_shape = -1
	time = 0.0
	loc = drill.locate(0.0)
	show_replaced.emit()
	structure_changed.emit()
	positions_changed.emit()
	selection_changed.emit()
	time_changed.emit()
	file_changed.emit()


# ---------------------------------------------------------------- sets & time

func current_set_index() -> int:
	return int(loc["set"])


func is_at_set() -> bool:
	return bool(loc["at_set"])


func current_set() -> DrillSet:
	return drill.sets[current_set_index()]


## The set that can be edited right now, or null while between sets.
func edit_set() -> DrillSet:
	return current_set() if is_at_set() else null


func go_to_set(i: int) -> void:
	i = clampi(i, 0, drill.sets.size() - 1)
	time = drill.set_times()[i]
	_set_loc({"at_set": true, "set": i, "from": i, "frac": 0.0, "count": 0.0})


func set_time(t: float) -> void:
	time = clampf(t, 0.0, drill.duration())
	_set_loc(drill.locate(time))


## Call after counts or tempo change so the time stays consistent.
func refresh_time() -> void:
	if is_at_set():
		go_to_set(current_set_index())
	else:
		set_time(time)


func _set_loc(l: Dictionary) -> void:
	var changed := int(l["set"]) != int(loc["set"]) or bool(l["at_set"]) != bool(loc["at_set"])
	loc = l
	if changed:
		_validate_selection()
	time_changed.emit()


# ---------------------------------------------------------------- selection

## "set", "marcher" or "shape": what the info panel should describe.
func focus() -> String:
	if not selected_marchers.is_empty():
		return "marcher"
	if selected_shape != -1:
		return "shape"
	return "set"


func select_marchers(ids: Array[int]) -> void:
	selected_marchers.assign(ids)
	selected_shape = -1
	selection_changed.emit()


func toggle_marcher(id: int) -> void:
	if selected_marchers.has(id):
		selected_marchers.erase(id)
	else:
		selected_marchers.append(id)
	selected_shape = -1
	selection_changed.emit()


func select_all() -> void:
	var ids: Array[int] = []
	for m in drill.marchers:
		ids.append(m.id)
	select_marchers(ids)


func select_shape(id: int) -> void:
	selected_marchers.clear()
	selected_shape = id
	selection_changed.emit()


func clear_selection() -> void:
	selected_marchers.clear()
	selected_shape = -1
	selection_changed.emit()


func _validate_selection(emit := true) -> void:
	var changed := false
	var keep: Array[int] = []
	for id in selected_marchers:
		if drill.find_marcher(id) != null:
			keep.append(id)
	if keep.size() != selected_marchers.size():
		selected_marchers = keep
		changed = true
	if selected_shape != -1:
		if drill.find_shape(selected_shape) == null:
			selected_shape = -1
			changed = true
	if changed and emit:
		selection_changed.emit()


# ---------------------------------------------------------------- undo

## Saves an undo point before a change. Repeated calls with the same key
## within a moment (e.g. typing in a field) merge into one undo step.
func checkpoint(key := "") -> void:
	var now := Time.get_ticks_msec()
	if key != "" and key == _ck_key and now - _ck_msec < 1500:
		_ck_msec = now
		return
	_ck_key = key
	_ck_msec = now
	_undo.append(drill.to_dict())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()
	if not dirty:
		dirty = true
		file_changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(drill.to_dict())
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(drill.to_dict())
	_restore(_redo.pop_back())


func _restore(d: Dictionary) -> void:
	# Audio settings aren't part of undo history.
	var keep_audio := drill.audio_path
	var keep_offset := drill.audio_offset
	drill = DrillShow.from_dict(d)
	drill.audio_path = keep_audio
	drill.audio_offset = keep_offset
	_ck_key = ""
	dirty = true
	var i := mini(current_set_index(), drill.sets.size() - 1)
	if is_at_set():
		time = drill.set_times()[i]
		loc = drill._at(i)
	else:
		time = clampf(time, 0.0, drill.duration())
		loc = drill.locate(time)
	_validate_selection(false)
	structure_changed.emit()
	positions_changed.emit()
	selection_changed.emit()
	time_changed.emit()
	file_changed.emit()


func mark_saved(path: String) -> void:
	file_path = path
	dirty = false
	file_changed.emit()


# ---------------------------------------------------------------- notifications

func notify_positions() -> void:
	positions_changed.emit()


func notify_structure() -> void:
	structure_changed.emit()
	positions_changed.emit()


func set_tool(t: String) -> void:
	if tool == t:
		return
	tool = t
	tool_changed.emit()


func set_view(option: String, value: Variant) -> void:
	set(option, value)
	view_changed.emit()


func set_hash_style(style: String) -> void:
	checkpoint()
	drill.hash_style = style
	view_changed.emit()
	notify_structure()


# ---------------------------------------------------------------- set commands

func add_set_after(i: int) -> void:
	checkpoint()
	var src := drill.sets[i]
	var ns := src.copy()
	ns.counts = maxi(src.counts, 1)
	ns.notes = ""
	ns.name = "Set %d" % (i + 2)
	drill.sets.insert(i + 1, ns)
	_renumber()
	structure_changed.emit()
	go_to_set(i + 1)
	positions_changed.emit()


func delete_set(i: int) -> void:
	if drill.sets.size() <= 1:
		return
	checkpoint()
	drill.sets.remove_at(i)
	_renumber()
	# Move to a set that still exists before anything redraws, or panels
	# would look up the deleted (possibly now out-of-range) set.
	var j := mini(i, drill.sets.size() - 1)
	time = drill.set_times()[j]
	loc = {"at_set": true, "set": j, "from": j, "frac": 0.0, "count": 0.0}
	_validate_selection(false)
	structure_changed.emit()
	selection_changed.emit()
	time_changed.emit()
	positions_changed.emit()


func move_set(i: int, dir: int) -> void:
	var j := i + dir
	if j < 0 or j >= drill.sets.size():
		return
	checkpoint()
	var tmp := drill.sets[i]
	drill.sets[i] = drill.sets[j]
	drill.sets[j] = tmp
	_renumber()
	structure_changed.emit()
	go_to_set(j)
	_validate_selection()
	positions_changed.emit()


## Auto-named sets ("Set 3") keep their numbers in order.
func _renumber() -> void:
	var re := RegEx.create_from_string("^Set \\d+$")
	for i in drill.sets.size():
		var s := drill.sets[i]
		if s.name.strip_edges() == "" or re.search(s.name) != null:
			s.name = "Set %d" % (i + 1)


# ---------------------------------------------------------------- marcher commands

func add_marchers(section: String, count: int) -> void:
	if count <= 0:
		return
	checkpoint()
	var spots := _free_spots(current_set(), count)
	var ids: Array[int] = []
	for k in count:
		ids.append(drill.add_marcher(section, spots[k]).id)
	notify_structure()
	select_marchers(ids)


func _free_spots(s: DrillSet, count: int) -> Array[Vector2]:
	const SP := 2.5
	var occupied := {}
	for id in s.positions:
		var p: Vector2 = s.positions[id]
		occupied[Vector2i((p / SP).round())] = true
	var cands: Array[Vector2i] = []
	for gx in range(-18, 19):
		for gy in range(-9, 10):
			cands.append(Vector2i(gx, gy))
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var la := a.length_squared()
		var lb := b.length_squared()
		if la != lb:
			return la < lb
		return a.y < b.y if a.y != b.y else a.x < b.x)
	var out: Array[Vector2] = []
	for c in cands:
		if out.size() >= count:
			break
		if not occupied.has(c):
			out.append(Vector2(c) * SP)
	while out.size() < count:
		out.append(Vector2.ZERO)
	return out


func remove_marchers(ids: Array[int]) -> void:
	if ids.is_empty():
		return
	checkpoint()
	for id in ids.duplicate():
		drill.remove_marcher(id)
	selected_marchers.clear()
	notify_structure()
	selection_changed.emit()


func detach_marchers(ids: Array[int], record := true) -> void:
	var s := edit_set()
	if s == null:
		return
	if record:
		checkpoint()
	if drill.detach(s, ids):
		notify_structure()


func set_facing(ids: Array[int], degrees: float) -> void:
	var s := edit_set()
	if s == null:
		return
	checkpoint()
	for id in ids:
		s.facings[id] = degrees
	notify_positions()


func set_section(ids: Array[int], section: String) -> void:
	checkpoint()
	for id in ids:
		var m := drill.find_marcher(id)
		if m != null:
			m.section = section
	notify_structure()


## mode: "row" (same front-to-back), "column" (same side-to-side) or "spread"
## (evenly between the two marchers farthest apart).
func align_marchers(ids: Array[int], mode: String) -> void:
	var s := edit_set()
	if s == null or ids.size() < 2:
		return
	checkpoint()
	drill.detach(s, ids)
	var avg := Vector2.ZERO
	for id in ids:
		avg += s.get_pos(id)
	avg /= ids.size()
	match mode:
		"row":
			for id in ids:
				s.positions[id] = Vector2(s.get_pos(id).x, avg.y)
		"column":
			for id in ids:
				s.positions[id] = Vector2(avg.x, s.get_pos(id).y)
		"spread":
			var a := s.get_pos(ids[0])
			var b := a
			var best := -1.0
			for i in ids.size():
				for j in range(i + 1, ids.size()):
					var d := s.get_pos(ids[i]).distance_squared_to(s.get_pos(ids[j]))
					if d > best:
						best = d
						a = s.get_pos(ids[i])
						b = s.get_pos(ids[j])
			var dir := b - a
			var order := ids.duplicate()
			order.sort_custom(func(x: int, y: int) -> bool:
				return (s.get_pos(x) - a).dot(dir) < (s.get_pos(y) - a).dot(dir))
			for k in order.size():
				s.positions[order[k]] = a.lerp(b, float(k) / float(order.size() - 1))
	notify_structure()


# ---------------------------------------------------------------- shape commands

func add_shape(sh: DrillShape) -> void:
	if edit_set() == null:
		return
	checkpoint()
	drill.add_shape(sh)
	notify_structure()
	select_shape(sh.id)


## Deletes a shape from every set. Marchers on it stay where they are.
func delete_shape(id: int) -> void:
	if drill.find_shape(id) == null:
		return
	checkpoint()
	drill.remove_shape(id)
	if selected_shape == id:
		selected_shape = -1
	notify_structure()
	selection_changed.emit()


func assign_to_shape(shape_id: int, ids: Array[int], hints := {}, record := true) -> void:
	var s := edit_set()
	if s == null:
		return
	var sh := drill.find_shape(shape_id)
	if sh == null:
		return
	if record:
		checkpoint()
	s.set_shown(shape_id, true)
	drill.assign(s, sh, ids, hints)
	notify_structure()


## Moves or reshapes a shape in the current set only (other sets keep
## their own points). Call checkpoint() first.
func set_shape_points(sh: DrillShape, pts: PackedVector2Array) -> void:
	var s := edit_set()
	if s == null:
		return
	s.forms[sh.id] = pts
	drill.relayout(s, sh)
	positions_changed.emit()


## Reorders a shape's marchers in this set for the shortest moves from the previous set.
func order_shape_by_moves(id: int) -> void:
	var sh := drill.find_shape(id)
	if sh == null or edit_set() == null:
		return
	checkpoint()
	if drill.order_by_moves(current_set_index(), sh):
		notify_structure()


## Makes this set's points for a shape the shared outline for every set.
func share_shape_points(id: int) -> void:
	var s := edit_set()
	var sh := drill.find_shape(id)
	if s == null or sh == null:
		return
	checkpoint()
	sh.points = drill.form(s, sh).points.duplicate()
	for other in drill.sets:
		other.forms.erase(id)
	drill.relayout_everywhere(sh)
	notify_structure()


## Drops this set's own points for a shape, going back to the shared outline.
func reset_shape_points(id: int) -> void:
	var s := edit_set()
	var sh := drill.find_shape(id)
	if s == null or sh == null or not s.forms.has(id):
		return
	checkpoint()
	s.forms.erase(id)
	drill.relayout(s, sh)
	notify_structure()


## Shows or hides a shape in set i (-1 = every set). Marchers stay attached.
func set_shape_shown(id: int, on: bool, i := -2) -> void:
	if i == -2:
		i = current_set_index()
	checkpoint()
	if i == -1:
		for s in drill.sets:
			s.set_shown(id, on)
	else:
		drill.sets[i].set_shown(id, on)
	notify_structure()
