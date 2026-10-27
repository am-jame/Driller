class_name DrillMarcher
extends RefCounted
## One performer. Positions live in each DrillSet, keyed by this id.

var id := 0
var label := ""
var section := "Trumpet"


func to_dict() -> Dictionary:
	return {"id": id, "label": label, "section": section}


static func from_dict(d: Dictionary) -> DrillMarcher:
	var m := DrillMarcher.new()
	m.id = int(d.get("id", 0))
	m.label = str(d.get("label", ""))
	m.section = str(d.get("section", "Trumpet"))
	return m
