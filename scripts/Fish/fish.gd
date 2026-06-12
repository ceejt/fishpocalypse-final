extends "res://scripts/enemy.gd"

@onready var _sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var _hurt_sfx: AudioStreamPlayer3D  = $AudioStreamPlayer3D

# hurt flash constants; tweak in one place
const _HURT_COLOR: Color   = Color(1.0, 0.2, 0.2, 1.0)  # red tint; precomputed
const _HURT_SCALE: float   = 1.5                         # scale pop on hit
const _FLASH_TIME: float   = 0.08                         # seconds at peak
const _RECOVER_TIME: float = 0.10                         # seconds back to normal

func _ready() -> void:
	max_health = 30
	speed      = 3.5
	damage     = 5
	super._ready()
	if _sprite:
		_sprite.modulate = Color.WHITE
		_sprite.scale    = Vector3.ONE
		
# override take_damage; call super so hp/die logic still runs in enemy.gd
func take_damage(amount: float) -> void:
	_hurt_flash()
	super.take_damage(amount)
	
func _hurt_flash() -> void:
	if _sprite == null: return
	# kill any in-progress tween; prevents stacking on rapid hits
	var tw: Tween = create_tween().set_parallel(true)
	# snap to hurt state immediately; no easing on the onset
	_sprite.modulate    = _HURT_COLOR
	_sprite.scale       = Vector3.ONE * _HURT_SCALE
	# hold for _FLASH_TIME, then ease back to normal
	tw.tween_property(_sprite, "modulate", Color.WHITE,   _RECOVER_TIME).set_delay(_FLASH_TIME)
	tw.tween_property(_sprite, "scale",    Vector3.ONE,   _RECOVER_TIME).set_delay(_FLASH_TIME)
	if _hurt_sfx: _hurt_sfx.play()
