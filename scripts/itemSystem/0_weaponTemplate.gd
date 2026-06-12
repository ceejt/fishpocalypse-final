extends Node3D
class_name Weapon

@export var data: FishWeaponData
var rarity: RarityTier

@onready var sprite: AnimatedSprite3D = $Sprite3D
@onready var audio: AudioStreamPlayer3D = $WeaponAudio
@onready var fire_timer: Timer = $Timer
@onready var muzzle: Marker3D = $Muzzle

const PROJECTILE_SPAWNER = preload("res://scenes/WeaponRelated/ProjectileSpawner.tscn")

func setup(new_data: FishWeaponData, rolled_rarity: RarityTier) -> void:
	data = new_data
	rarity = rolled_rarity
	apply_data()


# FIX: activate() no longer starts the timer for auto-fire.
# CombatSystem owns the fire rate via _shot_delay_timer.
# The timer is still used inside shoot() to reset itself,
# but it must NOT be running when CombatSystem calls shoot() manually
# — that old guard (not fire_timer.is_stopped()) was blocking all shots.
func activate() -> void:
	# Intentionally empty: CombatSystem controls when to call shoot().
	pass


func deactivate() -> void:
	if fire_timer and not fire_timer.is_stopped():
		fire_timer.stop()


func apply_data() -> void:
	if sprite:
		sprite.sprite_frames = data.sprite_frames if data.sprite_frames else null
	else:
		push_warning("Weapon: AnimatedSprite3D node missing")

	if audio:
		audio.stream = data.sfx if data.sfx else null
	else:
		push_warning("Weapon: AudioStreamPlayer3D node missing")

	if fire_timer:
		fire_timer.wait_time = data.base_shot_delay * (rarity.shot_delay_multiplier if rarity else 1.0)
		fire_timer.one_shot = true   # FIX: one-shot — CombatSystem decides when to fire again
		if not fire_timer.timeout.is_connected(_on_fire_timer_timeout):
			fire_timer.timeout.connect(_on_fire_timer_timeout)
	else:
		push_warning("Weapon: Timer node missing")


func shoot(direction: Vector3 = Vector3.FORWARD) -> void:
	if data == null or rarity == null: return
	if data.projectile == null:
		push_warning("Weapon: No ProjectileData assigned in FishWeaponData")
		return
	if not is_inside_tree():
		push_warning("Weapon: shoot called before entering tree")
		return
	if not muzzle or not muzzle.is_inside_tree():
		push_warning("Weapon: muzzle not ready")
		return

	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(&"shoot"):
		sprite.play(&"shoot")

	var shoot_dir := direction
	if direction == Vector3.FORWARD and muzzle:
		shoot_dir = -muzzle.global_transform.basis.z

	var count := data.base_projectiles_per_shot
	for i in count:
		var p: ProjectileSpawner = PROJECTILE_SPAWNER.instantiate()
		var angle := 0.0
		if count > 1:
			angle = deg_to_rad(10.0 * (i - (count - 1) / 2.0))
		var dir := shoot_dir.rotated(Vector3.UP, angle)
		get_tree().current_scene.add_child(p)
		p.global_position = muzzle.global_position if muzzle else global_position
		p.setup(data.projectile, data.base_damage_per_shot * rarity.damage_multiplier, dir)

	if audio: audio.play()


func _ready() -> void:
	_setup_pickup_area()


func _setup_pickup_area() -> void:
	var area := Area3D.new()
	area.name = "PickupArea"
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	col.shape = sphere
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"): return
	var inv: InventorySystem = body.get_node_or_null("COMPONENTS/InventorySystem")
	if inv: inv.pickup(self)


func _on_picked_up() -> void:
	# FIX: do NOT call queue_free() here — Player.equip_weapon() reparents
	# this node into the weapon_holder. Freeing it here would delete it
	# before it can be equipped. Call this only after a drop/swap-out.
	pass


func _on_fire_timer_timeout() -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(&"default"):
		sprite.play(&"default")
