class_name HudBar
extends Control
## A flat meter for the HUD: a background, a lag band (the white "damage just
## taken" band under HP) and the fill. Fills from the left, or from the right
## when reversed (the right-hand fighter's bars).

@export var value: float = 1.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var lag: float = 0.0:
	set(v):
		lag = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var reversed: bool = false
@export var fill_color: Color = Color(0.85, 0.2, 0.16)
@export var lag_color: Color = Color(1.0, 0.95, 0.85, 0.85)
@export var back_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var edge_color: Color = Color(1.0, 1.0, 1.0, 0.25)


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, back_color)
	if lag > value:
		draw_rect(_part(lag), lag_color)
	draw_rect(_part(value), fill_color)
	draw_rect(r, edge_color, false, 1.0)


func _part(frac: float) -> Rect2:
	var w: float = size.x * frac
	if reversed:
		return Rect2(Vector2(size.x - w, 0.0), Vector2(w, size.y))
	return Rect2(Vector2.ZERO, Vector2(w, size.y))
