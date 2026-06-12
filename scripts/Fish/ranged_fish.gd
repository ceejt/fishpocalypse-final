extends "res://scripts/enemy.gd"

@export var projectile_scene: PackedScene
@export var shoot_audio: AudioStreamPlayer3D

const ATTACK_RANGE: float         = 18.0
const PREFERRED_INNER: float      = 10.0
const PREFERRED_OUTER: float      = 14.0
const ATTACK_COOLDOWN: float      = 2.5
const SHOOT_FRAME_DURATION: float = 0.4

const _HURT_COLOR: Color   = Color(1.0, 0.2, 0.2, 1.0)
const _HURT_SCALE: float   = 1.35
const _FLASH_TIME: float   = 0.08
const _RECOVER_TIME: float = 0.18

@onready var _sprite: AnimatedSprite3D      = $AnimatedSprite3D
@onready var _hurt_sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D_2

var _attack_timer: float      = 0.0
var _shoot_frame_timer: float = 0.0

func _ready() -> void:
	max_health = 20
	speed      = 2.0
	damage     = 6
	super._ready()
	_sprite.animation = &"default"
	_sprite.frame     = 0
	_sprite.pause()
	if projectile_scene != null:
		ProjectilePool.init_pool(projectile_scene)

func take_damage(amount: float) -> void:
	_hurt_flash()
	super.take_damage(amount)
	
func _hurt_flash() -> void:
	var tw: Tween = create_tween().set_parallel(true)
	
	# snap to hurt state instantly; no easing on onset
	_sprite.modulate = _HURT_COLOR
	_sprite.scale    = Vector3.ONE * _HURT_SCALE
	
	# hold, then ease back to normal
	tw.tween_property(_sprite, "modulate", Color.WHITE, _RECOVER_TIME).set_delay(_FLASH_TIME)
	tw.tween_property(_sprite, "scale",    Vector3.ONE, _RECOVER_TIME).set_delay(_FLASH_TIME)
	if _hurt_sfx: _hurt_sfx.play()
	
func _physics_process(delta: float) -> void:
	if player_reference == null: return

	jump_timer    -= delta
	_attack_timer += delta

	if _shoot_frame_timer > 0.0:
		_shoot_frame_timer -= delta
		if _shoot_frame_timer <= 0.0:
			_sprite.frame = 0

	# water escape — stronger jump to clear island edges
	if global_position.y < -0.5 and jump_timer <= 0.0:
		velocity.y = jump_force * 2.0
		jump_timer = jump_cooldown

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var player_pos: Vector3 = player_reference.global_position
	var dist: float         = global_position.distance_to(player_pos)
	var dir: Vector3        = (player_pos - global_position).normalized()

	if dist > PREFERRED_OUTER:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	elif dist < PREFERRED_INNER:
		velocity.x = -dir.x * speed
		velocity.z = -dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
	
	for i: int in get_slide_collision_count():
		var collider: Object = get_slide_collision(i).get_collider()
		if collider.is_in_group(&"player"):
			_deal_damage_to_player(collider)
			
	if dist <= ATTACK_RANGE and _attack_timer >= ATTACK_COOLDOWN and ProjectilePool.can_shoot():
		_attack_timer = 0.0
		_shoot(dir)
		
func _shoot(dir: Vector3) -> void:
	var proj: Node = ProjectilePool.acquire()
	if proj == null: return
	proj.global_position = global_position + Vector3(dir.x * 1.5, 0.5, dir.z * 1.5)
	proj.init(dir, damage)
	proj.visible = true
	proj.set_process(true)
	if shoot_audio: shoot_audio.play()
	_sprite.frame      = 1
	_shoot_frame_timer = SHOOT_FRAME_DURATION
