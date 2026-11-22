class_name UiKit
extends RefCounted


static func button(text: String, cb: Callable, color := Color(0.17, 0.21, 0.31), min_size := Vector2(300, 64), font := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		if st == "hover":
			s.bg_color = color.lightened(0.18)
		elif st == "pressed":
			s.bg_color = color.darkened(0.2)
		else:
			s.bg_color = color
		s.set_corner_radius_all(12)
		s.border_color = Color(1, 1, 1, 0.55) if st == "focus" else Color(1, 1, 1, 0.12)
		s.set_border_width_all(2)
		b.add_theme_stylebox_override(st, s)
	b.pressed.connect(cb)
	return b


static func label(text: String, size := 24, color := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(size / 8, 2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
