extends Area3D

var direction: Vector3  = Vector3.ZERO
var damage: int         = 6
var speed: float        = 2.9
var turn_speed: float   = 2.0
var target_scale: float = 1.0
var grow_duration: float = 0.4

const GRACE_END: float      = 0.3
const LIFETIME: float       = 8.0
const _SCALE_EPSILON: float = 0.001
const _INV_GROW_DUR: float  = 0.25

var _timer: float = 0.0
var _grew: bool   = false
var _target: CharacterBody3D = null

func _ready() -> void:
	monitoring  = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_target = get_tree().get_first_node_in_group(&"player") as CharacterBody3D
	scale   = Vector3.ONE * _SCALE_EPSILON

func init(dir: Vector3, dmg: int) -> void:
	# reset all state so pooled projectile is clean on reuse
	direction = dir
	damage    = dmg
	_timer    = 0.0
	_grew     = false
	scale     = Vector3.ONE * _SCALE_EPSILON

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= LIFETIME:
		_retire()
		return

	if not _grew:
		if _timer < grow_duration:
			scale = Vector3.ONE * (_timer * _INV_GROW_DUR * target_scale)
		else:
			scale = Vector3.ONE * target_scale
			_grew = true

	if _timer > GRACE_END and _target != null:
		var desired: Vector3 = (_target.global_position - global_position).normalized()
		direction = direction.lerp(desired, turn_speed * delta).normalized()

	global_position += direction * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if _timer <= GRACE_END: return
	$AudioStreamPlayer3D.play()
	if body.is_in_group(&"player"):
		_target._take_damage(damage)
	_retire()

func hit() -> void:
	_retire()

func _retire() -> void:
	ProjectilePool.release(self)
