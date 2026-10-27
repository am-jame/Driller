class_name FieldCoords
extends RefCounted
## Football field measurements and drill-chart style coordinate readouts.
## World space is in yards: origin at the 50 yard line midfield, +x toward
## Side 2, +y toward the front sideline (the audience).

const STEP := 0.625  # one 8-to-5 step, in yards
const HALF_LENGTH := 60.0  # back of the end zone
const GOAL := 50.0
const HALF_WIDTH := 160.0 / 6.0  # 53 1/3 yards wide

const HASH_STYLES := {
	"HS": {"name": "High School", "from_sideline": 160.0 / 9.0},
	"NCAA": {"name": "College", "from_sideline": 20.0},
	"NFL": {"name": "NFL", "from_sideline": 70.75 / 3.0},
}


## y of the front hash (back hash is the negative).
static func hash_y(style: String) -> float:
	var info: Dictionary = HASH_STYLES.get(style, HASH_STYLES["HS"])
	return HALF_WIDTH - float(info["from_sideline"])


static func fmt_steps(v: float) -> String:
	return String.num(snappedf(v, 0.01))


## e.g. "S1: 2.5 steps outside 35 yd ln"
static func describe_x(x: float) -> String:
	var ax := absf(x)
	var line := clampf(roundf(ax / 5.0) * 5.0, 0.0, GOAL)
	var yard := int(GOAL - line)
	var steps := (ax - line) / STEP
	var side := "S1" if x < 0.0 else "S2"
	var line_name := "goal line" if yard == 0 else "%d yd ln" % yard
	if absf(steps) < 0.01:
		if yard == 50:
			return "On 50 yd ln"
		return "%s: On %s" % [side, line_name]
	var dir := "outside" if steps > 0.0 else "inside"
	return "%s: %s steps %s %s" % [side, fmt_steps(absf(steps)), dir, line_name]


## e.g. "4 steps behind front hash"
static func describe_y(y: float, style: String) -> String:
	var hy := hash_y(style)
	var refs := [
		["front sideline", HALF_WIDTH],
		["front hash", hy],
		["back hash", -hy],
		["back sideline", -HALF_WIDTH],
	]
	var best: Array = refs[0]
	for r in refs:
		if absf(y - float(r[1])) < absf(y - float(best[1])):
			best = r
	var steps := (y - float(best[1])) / STEP
	if absf(steps) < 0.01:
		return "On %s" % best[0]
	var dir := "in front of" if steps > 0.0 else "behind"
	return "%s steps %s %s" % [fmt_steps(absf(steps)), dir, best[0]]
