extends Node3D
class_name ProjectileSpawner

var data: ProjectileData
var damage: float = 0.0
var direction: Vector3 = Vector3.FORWARD
var _tick_accum: float = 0.0

@onready var sprite: Sprite3D = $AnimatedSprite3D
@onready var lifetime_timer: Timer = $Timer          # match your actual node name
@onready var hitbox: Area3D = $Area3D                # match your actual node name


func setup(p_data: ProjectileData, p_damage: float, p_direction: Vector3) -> void:
	if p_data == null:
		push_error("ProjectileSpawner: data is null")
		queue_free()
		return

	data = p_data
	damage = p_damage
	direction = p_direction.normalized()

	if sprite and data.sprite:
		sprite.texture = data.sprite
	
	if lifetime_timer:
		lifetime_timer.wait_time = data.lifetime
		lifetime_timer.one_shot = true
		lifetime_timer.timeout.connect(queue_free)
		lifetime_timer.start()
	else:
		push_warning("ProjectileSpawner: Timer node missing")

	if hitbox:
		hitbox.body_entered.connect(_on_body_entered)
	else:
		push_warning("ProjectileSpawner: Area3D node missing")


func _physics_process(delta: float) -> void:
	if data == null: return
	match data.type:
		ProjectileData.ProjectileType.BULLET:
			global_position += direction * data.speed * delta

		ProjectileData.ProjectileType.LASER:
			_tick_accum += delta
			if _tick_accum >= data.tick_rate:
				_tick_accum = 0.0
				if hitbox:
					for body in hitbox.get_overlapping_bodies():
						_apply_damage(body)


func _on_body_entered(body: Node) -> void:
	if data == null: return
	if data.type != ProjectileData.ProjectileType.BULLET: return
	if data.owner_type == ProjectileData.OwnerType.PLAYER and not body.is_in_group("enemy"): return
	if data.owner_type == ProjectileData.OwnerType.ENEMY  and not body.is_in_group("player"): return
	_apply_damage(body)
	queue_free()


func _apply_damage(body: Node) -> void:
	if body == null: return
	if data.owner_type == ProjectileData.OwnerType.PLAYER and body.is_in_group("player"): return
	if data.owner_type == ProjectileData.OwnerType.ENEMY  and body.is_in_group("enemy"): return
	if body.has_method("take_damage"):
		body.take_damage(damage)
