class_name Sections
extends RefCounted
## Instrument sections: label prefix, colour and which sprite to draw.

const LIST := [
	{"name": "Flute", "prefix": "F", "kind": "flute", "color": "#8ad7ff"},
	{"name": "Clarinet", "prefix": "C", "kind": "clarinet", "color": "#6b8cff"},
	{"name": "Saxophone", "prefix": "X", "kind": "sax", "color": "#a77bff"},
	{"name": "Trumpet", "prefix": "T", "kind": "brass", "color": "#ffd34d"},
	{"name": "Mellophone", "prefix": "M", "kind": "mello", "color": "#ffa14d"},
	{"name": "Trombone", "prefix": "B", "kind": "trombone", "color": "#ff6b5b"},
	{"name": "Baritone", "prefix": "E", "kind": "bari", "color": "#e65c9c"},
	{"name": "Tuba", "prefix": "U", "kind": "tuba", "color": "#c97a45"},
	{"name": "Snare", "prefix": "S", "kind": "snare", "color": "#e8e8e8"},
	{"name": "Tenors", "prefix": "Q", "kind": "tenor", "color": "#bdbdbd"},
	{"name": "Bass Drum", "prefix": "D", "kind": "bass", "color": "#9e9e9e"},
	{"name": "Cymbals", "prefix": "Y", "kind": "cymbal", "color": "#d9c27a"},
	{"name": "Color Guard", "prefix": "G", "kind": "guard", "color": "#5be3a0"},
	{"name": "Drum Major", "prefix": "DM", "kind": "major", "color": "#ffffff"},
]

static var _by_name := {}


static func _info(section: String) -> Dictionary:
	if _by_name.is_empty():
		for s in LIST:
			var d: Dictionary = s.duplicate()
			d["color"] = Color(str(s["color"]))
			_by_name[s["name"]] = d
	return _by_name.get(section, _by_name["Trumpet"])


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for s in LIST:
		out.append(str(s["name"]))
	return out


static func color(section: String) -> Color:
	return _info(section)["color"]


static func kind(section: String) -> String:
	return str(_info(section)["kind"])


static func prefix(section: String) -> String:
	return str(_info(section)["prefix"])
