extends Control

const ARROW_COLOR  := Color(1.0, 0.85, 0.0, 0.9)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)
const MARGIN       := 44.0  # px from screen edge where arrows sit

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var enemies := get_tree().get_nodes_in_group(&"active_enemy")
	if enemies.is_empty(): return
	var vp     := get_viewport_rect().size
	var center := vp * 0.5
	for enemy: Node3D in enemies:
		if camera.is_position_in_frustum(enemy.global_position): continue
		var dir := _screen_dir(camera, enemy.global_position, center, vp)
		_draw_arrow(_edge_pos(center, dir, vp), dir)


func _screen_dir(camera: Camera3D, world_pos: Vector3, center: Vector2, vp: Vector2) -> Vector2:
	var screen := camera.unproject_position(world_pos)
	if camera.is_position_behind(world_pos):
		screen = vp - screen  # mirror so behind-camera enemies point away correctly
	var d := screen - center
	return d.normalized() if d.length_squared() > 0.001 else Vector2.DOWN


func _edge_pos(center: Vector2, dir: Vector2, vp: Vector2) -> Vector2:
	var lo := Vector2(MARGIN, MARGIN)
	var hi := Vector2(vp.x - MARGIN, vp.y - MARGIN)
	var t  := INF
	if   dir.x >  1e-4: t = min(t, (hi.x - center.x) / dir.x)
	elif dir.x < -1e-4: t = min(t, (lo.x - center.x) / dir.x)
	if   dir.y >  1e-4: t = min(t, (hi.y - center.y) / dir.y)
	elif dir.y < -1e-4: t = min(t, (lo.y - center.y) / dir.y)
	return center + dir * t


func _draw_arrow(pos: Vector2, dir: Vector2) -> void:
	var perp  := Vector2(-dir.y, dir.x)
	var tip   := pos + dir  * 11.0
	var left  := pos - dir  *  7.0 - perp * 10.0
	var right := pos - dir  *  7.0 + perp * 10.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), ARROW_COLOR)
	draw_polyline(PackedVector2Array([tip, left, right, tip]), OUTLINE_COLOR, 2.0)
