class_name Ui
extends RefCounted
## Small UI helpers: colours, styleboxes, icons and formatting.

const BG := Color("#14181b")
const PANEL := Color("#1e2428")
const PANEL_BORDER := Color("#2c363c")
const ACCENT := Color("#6fb3a2")
const TEXT_DIM := Color("#9aa7ad")

const ICON_SVG := {
	"select": '<path d="M6 3 L6 19 L10 15 L13 21 L15.5 20 L12.5 14 L18 14 Z" fill="#e8ecef" stroke="none"/>',
	"line": '<path d="M5 19 L19 5"/><circle cx="5" cy="19" r="2" fill="#e8ecef"/><circle cx="19" cy="5" r="2" fill="#e8ecef"/>',
	"rect": '<rect x="4" y="6" width="16" height="12" rx="1"/>',
	"ellipse": '<ellipse cx="12" cy="12" rx="9" ry="6.5"/>',
	"polygon": '<path d="M12 3 L21 10 L17.5 20.5 L6.5 20.5 L3 10 Z"/>',
	"curve": '<path d="M3 18 C 8 1, 15 23, 21 6"/>',
	"freeform": '<path d="M3 15 C5 7 8 7 9 12 S12 19 14 12 S18 4 21 10"/>',
	"undo": '<path d="M9 14 L4 9 L9 4"/><path d="M4 9 H14.5 a5.5 5.5 0 0 1 0 11 H11"/>',
	"redo": '<path d="M15 14 L20 9 L15 4"/><path d="M20 9 H9.5 a5.5 5.5 0 0 0 0 11 H13"/>',
	"play": '<path d="M7 4 L20 12 L7 20 Z" fill="#e8ecef"/>',
	"pause": '<rect x="6" y="4" width="4" height="16" fill="#e8ecef" stroke="none"/><rect x="14" y="4" width="4" height="16" fill="#e8ecef" stroke="none"/>',
	"start": '<path d="M5 4 V20"/><path d="M19 4 L9 12 L19 20 Z" fill="#e8ecef"/>',
	"prev": '<path d="M12 5 L5 12 L12 19 Z" fill="#e8ecef"/><path d="M20 5 L13 12 L20 19 Z" fill="#e8ecef"/>',
	"next": '<path d="M4 5 L11 12 L4 19 Z" fill="#e8ecef"/><path d="M12 5 L19 12 L12 19 Z" fill="#e8ecef"/>',
	"end": '<path d="M19 4 V20"/><path d="M5 4 L15 12 L5 20 Z" fill="#e8ecef"/>',
	"music": '<path d="M9 18 V5 L20 3 V16"/><circle cx="6.5" cy="18" r="2.5" fill="#e8ecef"/><circle cx="17.5" cy="16" r="2.5" fill="#e8ecef"/>',
	"fit": '<path d="M4 9 V4 H9 M15 4 H20 V9 M20 15 V20 H15 M9 20 H4 V15"/>',
	"dice": '<rect x="4" y="4" width="16" height="16" rx="3"/><circle cx="9" cy="9" r="1.3" fill="#e8ecef"/><circle cx="15" cy="15" r="1.3" fill="#e8ecef"/><circle cx="15" cy="9" r="1.3" fill="#e8ecef"/><circle cx="9" cy="15" r="1.3" fill="#e8ecef"/>',
	"plus": '<path d="M12 5 V19 M5 12 H19"/>',
	"trash": '<path d="M4 7 H20 M9 7 V4 H15 V7 M6 7 L7 20 H17 L18 7"/>',
	"up": '<path d="M6 15 L12 9 L18 15"/>',
	"down": '<path d="M6 9 L12 15 L18 9"/>',
}

static var _icons := {}


## Icons are rendered at 3x and drawn smaller so they stay crisp on HiDPI.
static func icon(icon_name: String) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#e8ecef" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % ICON_SVG.get(icon_name, "")
	var img := Image.new()
	img.load_svg_from_string(svg, 3.0)
	var tex := ImageTexture.create_from_image(img)
	_icons[icon_name] = tex
	return tex


static func panel_style(color := PANEL, margin := 8.0, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func icon_button(icon_name: String, tooltip: String, text := "") -> Button:
	var b := Button.new()
	b.icon = icon(icon_name)
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("icon_max_width", 18)
	return b


static func label(text: String, font_size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


static func fmt_time(t: float) -> String:
	var neg := t < 0.0
	t = absf(t)
	var m := int(t) / 60
	var s := t - m * 60.0
	return "%s%d:%05.2f" % ["-" if neg else "", m, s]


static func cmd_name() -> String:
	return "Cmd" if OS.get_name() == "macOS" else "Ctrl"
