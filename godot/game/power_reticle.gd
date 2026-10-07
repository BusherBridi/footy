class_name PowerReticle
extends Control
## Centre-screen crosshair with a ring that fills clockwise as throw power builds.

var power := 0.0
var angle_deg := 0.0
var show_hint := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color.WHITE.lerp(Color(1.0, 0.25, 0.2), power)
	draw_arc(c, 26.0, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
	if power > 0.0:
		draw_arc(c, 26.0, -PI * 0.5, -PI * 0.5 + TAU * power, 48, col, 5.0)
	draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), col, 2.0)
	draw_line(c + Vector2(0, -8), c + Vector2(0, 8), col, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-60, 52), "angle %d°   power %d%%" % [int(angle_deg), int(power * 100.0)], HORIZONTAL_ALIGNMENT_CENTER, 120, 14, col)
	if show_hint:
		draw_string(font, c + Vector2(-90, 70), "release aim to cancel", HORIZONTAL_ALIGNMENT_CENTER, 180, 12, Color(1, 1, 1, 0.7))
