class_name PreviewPanel
extends VBoxContainer
## Play the show back with its music. Audio time = show time + offset.

var ed: DrillEditor
var playing := false

var _player: AudioStreamPlayer
var _click: AudioStreamPlayer
var _click_accent: AudioStreamPlayer
var _timeline: Timeline
var _play_btn: Button
var _time_label: Label
var _where_label: Label
var _audio_label: Label
var _offset_spin: SpinBox
var _volume: HSlider
var _metronome: CheckBox
var _sloppy: CheckBox
var _sloppy_spin: SpinBox
var _sloppy_dice: Button
var _audio_dialog: FileDialog
var _clock := 0.0
var _internal := false
var _last_count := -1


func setup(editor: DrillEditor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)

	_player = AudioStreamPlayer.new()
	add_child(_player)
	_click = AudioStreamPlayer.new()
	_click.stream = _make_click(1400.0)
	_click.volume_db = -6.0
	add_child(_click)
	_click_accent = AudioStreamPlayer.new()
	_click_accent.stream = _make_click(2200.0)
	_click_accent.volume_db = -4.0
	add_child(_click_accent)

	# Header
	var head := HBoxContainer.new()
	head.add_child(Ui.label("Preview", 15))
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(sp)
	_where_label = Ui.label("", 13, Ui.TEXT_DIM)
	head.add_child(_where_label)
	add_child(head)

	# Transport
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 4)
	var b_start := Ui.icon_button("start", "Go to the start (Home)")
	b_start.pressed.connect(func() -> void: seek_to_set(0))
	tr.add_child(b_start)
	var b_prev := Ui.icon_button("prev", "Previous set ( [ )")
	b_prev.pressed.connect(step_set.bind(-1))
	tr.add_child(b_prev)
	_play_btn = Ui.icon_button("play", "Play / pause (Space)")
	_play_btn.custom_minimum_size.x = 44
	_play_btn.pressed.connect(toggle_play)
	tr.add_child(_play_btn)
	var b_next := Ui.icon_button("next", "Next set ( ] )")
	b_next.pressed.connect(step_set.bind(1))
	tr.add_child(b_next)
	var b_end := Ui.icon_button("end", "Go to the last set")
	b_end.pressed.connect(func() -> void: seek_to_set(ed.drill.sets.size() - 1))
	tr.add_child(b_end)
	_time_label = Ui.label("0:00.00 / 0:00.00", 15)
	_time_label.custom_minimum_size.x = 170
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tr.add_child(_time_label)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = SIZE_EXPAND_FILL
	tr.add_child(sp2)
	_metronome = CheckBox.new()
	_metronome.text = "Metronome"
	_metronome.focus_mode = FOCUS_NONE
	_metronome.tooltip_text = "Click on every count while playing (accent on each new move)."
	tr.add_child(_metronome)
	tr.add_child(VSeparator.new())
	_sloppy = CheckBox.new()
	_sloppy.text = "Inaccurate"
	_sloppy.focus_mode = FOCUS_NONE
	_sloppy.tooltip_text = "Show everyone slightly off their dots at each set, like a real rehearsal.\nOnly changes the preview, not the drill."
	_sloppy.toggled.connect(func(on: bool) -> void:
		ed.set_view("sloppy", on)
		_sync_sloppy())
	tr.add_child(_sloppy)
	_sloppy_spin = SpinBox.new()
	_sloppy_spin.min_value = 0.1
	_sloppy_spin.max_value = 4.0
	_sloppy_spin.step = 0.1
	_sloppy_spin.value = ed.sloppy_amount / FieldCoords.STEP
	_sloppy_spin.suffix = "steps"
	_sloppy_spin.custom_minimum_size.x = 100
	_sloppy_spin.select_all_on_focus = true
	_sloppy_spin.tooltip_text = "The furthest anyone can be off their dot (8-to-5 steps)."
	_sloppy_spin.value_changed.connect(func(v: float) -> void:
		ed.set_view("sloppy_amount", v * FieldCoords.STEP))
	tr.add_child(_sloppy_spin)
	_sloppy_dice = Ui.icon_button("dice", "Re-roll who misses and by how much")
	_sloppy_dice.pressed.connect(func() -> void:
		ed.set_view("sloppy_seed", ed.sloppy_seed + 1))
	tr.add_child(_sloppy_dice)
	_sync_sloppy()
	add_child(tr)

	_timeline = Timeline.new()
	_timeline.setup(ed)
	_timeline.size_flags_vertical = SIZE_EXPAND_FILL
	_timeline.seek_requested.connect(_on_seek)
	add_child(_timeline)

	# Audio
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 6)
	var load_btn := Ui.icon_button("music", "Load an .ogg, .mp3 or .wav file", "Load Audio…")
	load_btn.pressed.connect(func() -> void: _audio_dialog.popup_centered_ratio(0.6))
	ar.add_child(load_btn)
	_audio_label = Ui.label("No audio", 13, Ui.TEXT_DIM)
	_audio_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_audio_label.clip_text = true
	_audio_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ar.add_child(_audio_label)
	ar.add_child(Ui.label("Offset", 13, Ui.TEXT_DIM))
	_offset_spin = SpinBox.new()
	_offset_spin.min_value = -600
	_offset_spin.max_value = 600
	_offset_spin.step = 0.01
	_offset_spin.suffix = "s"
	_offset_spin.custom_minimum_size.x = 110
	_offset_spin.select_all_on_focus = true
	_offset_spin.tooltip_text = "Where in the audio the show starts.\nPositive: the show starts this many seconds into the track.\nNegative: the show starts before the music does."
	_offset_spin.value_changed.connect(_on_offset_changed)
	ar.add_child(_offset_spin)
	ar.add_child(Ui.label("Vol", 13, Ui.TEXT_DIM))
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01
	_volume.value = 0.8
	_volume.custom_minimum_size.x = 90
	_volume.size_flags_vertical = SIZE_SHRINK_CENTER
	_volume.focus_mode = FOCUS_NONE
	_volume.value_changed.connect(func(v: float) -> void: _player.volume_db = linear_to_db(maxf(v, 0.0001)))
	_player.volume_db = linear_to_db(0.8)
	ar.add_child(_volume)
	var clear := Ui.icon_button("trash", "Remove the audio")
	clear.pressed.connect(func() -> void:
		ed.drill.audio_path = ""
		_load_audio(""))
	ar.add_child(clear)
	add_child(ar)

	_audio_dialog = FileDialog.new()
	_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_audio_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_audio_dialog.use_native_dialog = true
	_audio_dialog.title = "Load Audio"
	_audio_dialog.filters = PackedStringArray(["*.ogg, *.mp3, *.wav ; Audio files"])
	_audio_dialog.file_selected.connect(func(path: String) -> void:
		ed.drill.audio_path = path
		ed.dirty = true
		ed.file_changed.emit()
		_load_audio(path))
	add_child(_audio_dialog)

	ed.view_changed.connect(_sync_sloppy)
	ed.time_changed.connect(_on_time_changed)
	ed.structure_changed.connect(_update_labels)
	ed.show_replaced.connect(func() -> void:
		pause()
		_offset_spin.set_value_no_signal(ed.drill.audio_offset)
		_offset_spin.get_line_edit().text = str(ed.drill.audio_offset)
		_load_audio(ed.drill.audio_path))


func _sync_sloppy() -> void:
	_sloppy.set_pressed_no_signal(ed.sloppy)
	_sloppy_spin.editable = ed.sloppy
	_sloppy_dice.disabled = not ed.sloppy


# ---------------------------------------------------------------- transport

func toggle_play() -> void:
	if playing:
		pause()
	else:
		play()


func play() -> void:
	if ed.drill.duration() <= 0.0:
		return
	if ed.time >= ed.drill.duration() - 0.001:
		_set_time(0.0)
	playing = true
	_clock = ed.time
	_last_count = -1
	_sync_audio(true)
	_play_btn.icon = Ui.icon("pause")


func pause() -> void:
	playing = false
	_player.stop()
	_play_btn.icon = Ui.icon("play")


func step_set(dir: int) -> void:
	var i := ed.current_set_index()
	if ed.is_at_set():
		i += dir
	elif dir < 0:
		i -= 1  # between sets: "previous" is the set just left
	seek_to_set(i)


func seek_to_set(i: int) -> void:
	_internal = true
	ed.go_to_set(i)
	_internal = false
	_after_seek()


func _on_seek(t: float, set_index: int) -> void:
	if set_index >= 0:
		seek_to_set(set_index)
	else:
		_set_time(t)
		_after_seek()


func _set_time(t: float) -> void:
	_internal = true
	ed.set_time(t)
	_internal = false


func _after_seek() -> void:
	_clock = ed.time
	_last_count = -1
	if playing:
		_sync_audio(true)


func _on_time_changed() -> void:
	_update_labels()
	# Time moved from elsewhere (e.g. picking a set in the list) while playing.
	if not _internal and playing:
		_after_seek()


func _process(delta: float) -> void:
	if not playing:
		return
	var t := _clock + delta
	if _player.playing:
		# The music is the master clock while it's playing.
		var at := _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		t = maxf(at - ed.drill.audio_offset, _clock)
	else:
		_sync_audio(false, t)
	_clock = t
	var dur := ed.drill.duration()
	if t >= dur:
		_set_time(dur)
		pause()
		return
	_set_time(t)
	_tick_metronome()


## Starts (or restarts) the music at the right spot for the show clock.
func _sync_audio(force: bool, t := -1.0) -> void:
	if _player.stream == null:
		return
	if t < 0.0:
		t = _clock
	var at := t + ed.drill.audio_offset
	var length := _player.stream.get_length()
	if at < 0.0 or (length > 0.0 and at >= length):
		_player.stop()
		return
	if force or not _player.playing:
		_player.play(at)


func _tick_metronome() -> void:
	var loc := ed.loc
	var i := int(loc["set"])
	var abs_count := float(ed.drill.counts_before(i))
	if not bool(loc["at_set"]):
		abs_count = float(ed.drill.counts_before(i - 1)) + float(loc["count"])
	var c := int(floorf(abs_count + 0.0001))
	if c == _last_count:
		return
	var first := _last_count == -1
	_last_count = c
	if not _metronome.button_pressed or first:
		return
	var boundary := bool(loc["at_set"]) or floorf(float(loc["count"]) + 0.0001) == 0.0
	(_click_accent if boundary else _click).play()


# ---------------------------------------------------------------- audio

func _load_audio(path: String) -> void:
	pause()
	_player.stream = null
	_timeline.audio_length = 0.0
	if path == "":
		_audio_label.text = "No audio"
		_timeline.queue_redraw()
		return
	var stream: AudioStream = null
	if FileAccess.file_exists(path):
		match path.get_extension().to_lower():
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(path)
			"mp3":
				stream = AudioStreamMP3.load_from_file(path)
			"wav":
				stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		_audio_label.text = "Couldn't load %s" % path.get_file()
		_timeline.queue_redraw()
		return
	_player.stream = stream
	_timeline.audio_length = stream.get_length()
	_audio_label.text = "%s  (%s)" % [path.get_file(), Ui.fmt_time(stream.get_length())]
	_timeline.queue_redraw()


func _on_offset_changed(v: float) -> void:
	ed.drill.audio_offset = v
	if not ed.dirty:
		ed.dirty = true
		ed.file_changed.emit()
	_timeline.queue_redraw()
	if playing:
		_sync_audio(true)


func _update_labels() -> void:
	if ed.drill == null:
		return
	_time_label.text = "%s / %s" % [Ui.fmt_time(ed.time), Ui.fmt_time(ed.drill.duration())]
	var s := ed.current_set()
	if ed.is_at_set():
		_where_label.text = "%s  (%d of %d)" % [s.name, ed.current_set_index() + 1, ed.drill.sets.size()]
	else:
		_where_label.text = "→ %s   count %.1f of %d" % [s.name, float(ed.loc["count"]), s.counts]


static func _make_click(freq: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.04)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * freq * t) * exp(-t * 80.0) * 0.7
		data.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
