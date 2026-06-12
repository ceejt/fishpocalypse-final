extends CharacterBody3D

@onready var inventory: InventorySystem = $COMPONENTS/InventorySystem
@onready var health: HealthComponents = $COMPONENTS/HealthComponent
@onready var combat: CombatSystem = $COMPONENTS/CombatSystem

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var weapon_holder: Marker3D = $Kamot

@onready var fist_sprite: AnimatedSprite3D = $PunchHitbox/FistSprite
@onready var punch_hitbox: Area3D = $PunchHitbox 
var _punch_timer: float = 0.0
const PUNCH_COOLDOWN := 0.2
const PUNCH_DAMAGE := 5
const PUNCH_RANGE := 3
var _punch_active := false
const PUNCH_SP_COST := 14.0

var _facing_dir := Vector3.FORWARD

@export var HP := 100
@export var CP := 100
@export var SP := 100
@export var RR_CP := 20
@export var RR_SP := 20

var cp_recharge_blocked := false
var cp_recharge_timer := 0.0

@export var walk_speed := 5.0
@export var run_speed := 9.0
@export var dodge_speed := 25.0
@export var dodge_time := 0.15
@export var gravity := 20.0

@onready var anim: AnimatedSprite3D = $Sprite3D
@onready var spotlight: SpotLight3D = $SpotLight3D
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var _fishing_prompt: Label3D = $FishingPrompt

var last_valid_position := Vector3.ZERO
var previous_valid_position := Vector3.ZERO
var has_valid_position := false

const WATER_Y_LEVEL := -1.5
const SAVE_INTERVAL := 0.5
var save_timer := 0.0

var invincibility_timer := 0.0
const INVINCIBILITY_TIME := 0.5

var is_dodging := false
var dodge_timer := 0.0
var dodge_dir := Vector3.ZERO
var current_anim := ""

var ghost_interval := 0.01
var ghost_timer := 0.0
var was_moving_before_dodge := false

const _SFX_WALK  = preload("res://assets/audio/player_walk.mp3")
const _SFX_DODGE = preload("res://assets/audio/player_dodge.mp3")
const _SFX_HURT  = preload("res://assets/audio/player_hurt.mp3")
const _SFX_SPLASH = preload("res://assets/audio/water_splash.mp3")

func _ready() -> void:
	fist_sprite.visible = false
	add_to_group("player")
	if audio_player:
		audio_player.volume_db = 5.0
		audio_player.pitch_scale = 1.0
	inventory.slot_changed.connect(func(_slot): _log_inventory())
	# FIX: connect equipped_weapon_changed so swapping slots calls equip_weapon
	inventory.equipped_weapon_changed.connect(_on_equipped_weapon_changed)
	if spotlight: spotlight.visible = false
	var day_night_system = get_tree().get_first_node_in_group("day_night")
	if day_night_system:
		day_night_system.day_night_changed.connect(_on_night_changed)
	if health:
		health.initialize(HP)
		health.died.connect(_on_player_died)
		health.health_changed.connect(_on_health_changed)
	combat.dodged.connect(func(): pass)
	inventory.set_health_component(health)


func _physics_process(delta: float) -> void:
	save_timer += delta
	if _punch_timer > 0.0: _punch_timer -= delta
	if cp_recharge_blocked:
		cp_recharge_timer -= delta
		if cp_recharge_timer <= 0.0:
			cp_recharge_blocked = false
	if not is_on_floor(): velocity.y -= gravity * delta
	else: velocity.y = 0
	if invincibility_timer > 0.0:
		invincibility_timer -= delta

	if is_dodging:
		dodge_timer -= delta
		ghost_timer -= delta
		
		velocity.x = dodge_dir.x * dodge_speed
		velocity.z = dodge_dir.z * dodge_speed
		_play_anim("dodge")
		if ghost_timer <= 0.0:
			ghost_timer = ghost_interval
			_spawn_dodge_ghost()
		
		if dodge_timer <= 0:
			is_dodging = false
			ghost_timer = 0.0
			if was_moving_before_dodge:
				_play_walk_sound()
		
		move_and_slide()
		_check_ocean_boundary()
		return

	var input_dir := Vector3.ZERO
	if Input.is_action_pressed("D"): input_dir.x += 1
	if Input.is_action_pressed("A"): input_dir.x -= 1
	if Input.is_action_pressed("S"): input_dir.z += 1
	if Input.is_action_pressed("W"): input_dir.z -= 1

	input_dir = input_dir.normalized()
	var speed := run_speed if Input.is_action_pressed("RUN") else walk_speed
	velocity.x = input_dir.x * speed
	velocity.z = input_dir.z * speed

	_play_move_anim()
	move_and_slide()
	_check_ocean_boundary()
	_update_aim()


func _process(_delta: float) -> void:
	if _fishing_prompt != null and _fishing_prompt.visible:
		var t := Time.get_ticks_msec() / 1000.0
		_fishing_prompt.modulate.a = 0.6 + 0.4 * sin(t * 3.0)

func _try_punch() -> void:
	if _punch_timer > 0.0: return
	if SP < PUNCH_SP_COST: return
	_punch_timer = PUNCH_COOLDOWN
	deduct_sp(PUNCH_SP_COST)
	_play_anim("attack")
	_swing_weapon(PUNCH_COOLDOWN)
	_execute_punch()

func _execute_punch() -> void:
	var move_dir: Vector3 = _facing_dir

	# spawn a temporary fist sprite for this punch
	var fist: AnimatedSprite3D = fist_sprite.duplicate()
	get_parent().add_child(fist)

	var angle_y: float = atan2(-move_dir.x, -move_dir.z)
	fist.rotation.y = angle_y
	fist.rotation.x = 0.0

	# dot products for direction
	var dot_right: float = move_dir.dot(Vector3(1, 0, 0))   # +X = right
	var dot_down: float = move_dir.dot(Vector3(0, 0, 1))    # +Z = screen down (toward player)
	var abs_right: float = abs(dot_right)
	var abs_down: float = abs(dot_down)

	# diagonal threshold — if both axes contribute roughly equally it's diagonal
	var diag: float = 0.6

	if abs_right < diag and abs_down >= diag:
		# mostly vertical
		if dot_down >= 0.0:
			fist.frame = 0  # below player
		else:
			fist.frame = 1  # above player
	elif abs_right >= diag and abs_down < diag:
		# mostly horizontal
		if dot_right >= 0.0:
			fist.frame = 2  # right
		else:
			fist.frame = 3  # left
	else:
		# diagonal
		if dot_right >= 0.0 and dot_down < 0.0:
			fist.frame = 4  # upper right
		elif dot_right >= 0.0 and dot_down >= 0.0:
			fist.frame = 5  # lower right
		elif dot_right < 0.0 and dot_down < 0.0:
			fist.frame = 6  # upper left
		else:
			fist.frame = 7  # lower left

	var start_offset: float = 0.5
	fist.visible = true
	fist.global_position = global_position + move_dir * start_offset

	var hit_bodies: Array = []
	var steps: int = 10
	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		punch_hitbox.global_position = global_position + move_dir * (start_offset + PUNCH_RANGE * t)
		fist.global_position = global_position + move_dir * (start_offset + PUNCH_RANGE * t)
		punch_hitbox.monitoring = true

		await get_tree().create_timer(0.03).timeout
		await get_tree().physics_frame

		for body in punch_hitbox.get_overlapping_bodies():
			if body == self: continue
			if body in hit_bodies: continue
			if body.has_method("take_damage"):
				hit_bodies.append(body)
				body.take_damage(PUNCH_DAMAGE)
				print("[Punch] hit %s for %.1f" % [body.name, PUNCH_DAMAGE])
				var knockback_dir: Vector3 = (body.global_position - global_position).normalized()
				knockback_dir.y = 0.0
				body.velocity += knockback_dir * 8.0

		punch_hitbox.monitoring = true

	if hit_bodies.is_empty():
		print("[Punch] missed")

	fist.queue_free()
	punch_hitbox.global_position = global_position
	
func _swing_weapon(duration: float) -> void:
	_play_anim("attack")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		weapon_holder, "rotation_degrees",
		weapon_holder.rotation_degrees + Vector3(0, 45, 0),
		duration * 0.35
	)
	tween.tween_property(
		weapon_holder, "rotation_degrees",
		weapon_holder.rotation_degrees,
		duration * 0.65
	)

func _update_aim() -> void:
	if camera == null: return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001: return
	var t := (global_position.y - ray_origin.y) / ray_dir.y
	var world_mouse := ray_origin + ray_dir * t
	var aim := world_mouse - global_position
	aim.y = 0.0
	if aim.length_squared() < 0.001: return
	_facing_dir = aim.normalized()
	weapon_holder.look_at(global_position + _facing_dir, Vector3.UP)
	weapon_holder.rotate_y(PI)


func get_facing_dir() -> Vector3:
	return _facing_dir


func _on_night_changed(active: bool) -> void:
	if spotlight: spotlight.visible = active
func _on_health_changed(current: int, _maximum: int) -> void:
	HP = current
func _on_player_died() -> void:
	set_physics_process(false)


func _on_equipped_weapon_changed(weapon_node: Weapon) -> void:
	# Collect nodes that still belong to an inventory slot — never free these.
	var keeper_nodes: Array = []
	if inventory.main_slot_node != null: keeper_nodes.append(inventory.main_slot_node)
	if inventory.secondary_slot_node != null: keeper_nodes.append(inventory.secondary_slot_node)

	# Free orphaned weapon nodes (swapped out / dropped).
	for child in weapon_holder.get_children():
		if child is Weapon and child not in keeper_nodes:
			child.queue_free()

	# Hide all slot weapons; only the active one will be shown below.
	for node in keeper_nodes:
		if is_instance_valid(node) and node.get_parent() == weapon_holder:
			node.visible = false

	if weapon_node == null:
		combat.equip_weapon_node(null)
		return

	if weapon_node.get_parent() != weapon_holder:
		weapon_holder.add_child(weapon_node)
		weapon_node.position = Vector3.ZERO
		weapon_node.rotation = Vector3.ZERO
		var pickup_area := weapon_node.get_node_or_null("PickupArea")
		if pickup_area:
			pickup_area.set_deferred("monitoring", false)
			pickup_area.set_deferred("monitorable", false)
	weapon_node.visible = true
	combat.equip_weapon_node(weapon_node)

func _check_ocean_boundary() -> void:
	if global_position.y <= WATER_Y_LEVEL:
		_push_back_to_land()
		_play_splash_sound()
	else:
		if is_on_floor() and save_timer >= SAVE_INTERVAL:
			save_timer = 0.0
			previous_valid_position = last_valid_position
			last_valid_position = global_position
			has_valid_position = true


func _push_back_to_land() -> void:
	if not has_valid_position: return
	global_position = previous_valid_position
	velocity = Vector3.ZERO

func take_damage(amount: float) -> void:
	_take_damage(amount)
func _take_damage(amount: float) -> void:
	if invincibility_timer > 0.0: return
	_play_hurt_sound()
	_play_anim(&"hurt")
	health.take_damage(amount)
	invincibility_timer = INVINCIBILITY_TIME
	_hurt_camera_punch()
	_hurt_screen_flash()
	print("[Player] took %.1f damage" % amount)
	
func _hurt_camera_punch() -> void:
	var cam = $Camera3D
	var original_fov = cam.fov
	var original_rotation = cam.rotation_degrees
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# FOV Punch
	tween.tween_property(cam, "fov", original_fov + 7.0, 0.07)
	tween.tween_property(cam, "fov", original_fov, 0.28)
	
	# Camera Shake
	tween.tween_method(_apply_shake.bind(cam, original_rotation), 2.2, 0.0, 0.35)
	# Reset rotation at the end
	tween.tween_callback(_reset_camera_rotation.bind(cam, original_rotation))
func _hurt_screen_flash() -> void:
	var flash = get_node_or_null("UI_HUD/ColorRect")
	if flash == null: return
	flash.modulate = Color(1.0, 0.25, 0.2, 0.65)
	flash.visible = true
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "modulate:a", 0.0, 0.32)
	tween.tween_callback(func(): flash.visible = false)



func _apply_shake(intensity: float, cam: Camera3D, original_rot: Vector3) -> void:
	cam.rotation_degrees = original_rot + Vector3(
		randf_range(-intensity, intensity),
		randf_range(-intensity, intensity),
		randf_range(-intensity * 0.5, intensity * 0.5)
	)
	
	
func _reset_camera_rotation(cam: Camera3D, original_rot: Vector3) -> void:
	cam.rotation_degrees = original_rot
	
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		inventory.use_item("item_slot_1")
		_log_inventory()
	if event.is_action_pressed("ui_cancel"):
		inventory.drop_item("main_slot")
		_log_inventory()

func _log_inventory() -> void:
	print("[Inventory] main=%s | secondary=%s | item1=%s | item2=%s" % [
		inventory.main_slot.resource_path if inventory.main_slot else "empty",
		inventory.secondary_slot.resource_path if inventory.secondary_slot else "empty",
		inventory.item_slot_1.resource_path if inventory.item_slot_1 else "empty",
		inventory.item_slot_2.resource_path if inventory.item_slot_2 else "empty",
	])

func _play_move_anim() -> void:
	var is_moving := Input.is_action_pressed("W") or Input.is_action_pressed("S") \
		or Input.is_action_pressed("A") or Input.is_action_pressed("D")

	if Input.is_action_pressed("W"): _play_anim("walk_back")
	elif Input.is_action_pressed("S"): _play_anim("walk_front")
	elif Input.is_action_pressed("A"): _play_anim("walk_left")
	elif Input.is_action_pressed("D"): _play_anim("walk_right")
	else: _play_anim("idle")
	
	if audio_player:
		if is_moving and not is_dodging:
			_play_walk_sound()
		else:
			if audio_player.playing and audio_player.stream == preload("res://assets/audio/player_walk.mp3"):
				audio_player.stop()

func _play_walk_sound() -> void:
	if audio_player and not audio_player.playing:
		audio_player.stream = _SFX_WALK
		audio_player.volume_db = 1.0
		audio_player.pitch_scale = randf_range(0.95, 1.05)
		audio_player.play()
func _play_dodge_sound() -> void:
	if audio_player:
		audio_player.stop()
		audio_player.stream = _SFX_DODGE
		audio_player.volume_db = 10.0
		audio_player.pitch_scale = 1.5
		audio_player.play()
func _play_hurt_sound() -> void:
	if audio_player:
		audio_player.stream = _SFX_HURT
		audio_player.volume_db = 1.0
		audio_player.pitch_scale = 1.0
		audio_player.play()
func _play_splash_sound() -> void:
	if audio_player:
		audio_player.stream = _SFX_SPLASH
		audio_player.volume_db = 1.0
		audio_player.pitch_scale = 1.0
		audio_player.play()

func _play_anim(name: String) -> void:
	if current_anim == name: return
	if not anim.sprite_frames.has_animation(name): return
	current_anim = name
	anim.play(name)

func deduct_sp(amount: float) -> void:
	SP = max(SP - amount, 0)


func deduct_cp(amount: float) -> void:
	CP = max(CP - amount, 0)


func block_cp_recharge(duration: float) -> void:
	cp_recharge_blocked = true
	cp_recharge_timer = duration


func start_dodge(direction: Vector3) -> void:
	is_dodging = true
	dodge_timer = dodge_time
	dodge_dir = direction
	ghost_timer = 0.0
	was_moving_before_dodge = (direction != Vector3.ZERO)


func end_dodge() -> void:
	is_dodging = false
	ghost_timer = 0.0
	if was_moving_before_dodge:
		_play_walk_sound()


func show_fishing_prompt() -> void:
	if _fishing_prompt != null:
		_fishing_prompt.visible = true

func hide_fishing_prompt() -> void:
	if _fishing_prompt != null:
		_fishing_prompt.visible = false
		_fishing_prompt.modulate.a = 1.0

func play_fishing_anim(anim_name: String) -> void:
	_play_anim(anim_name)


func _spawn_dodge_ghost() -> void:
	var ghost := Node3D.new()
	ghost.set_script(load("res://scripts/player/dodge_ghost.gd"))
	get_parent().add_child(ghost)
	ghost.global_position = global_position
	ghost.global_rotation = global_rotation
	ghost.setup(anim, anim.frame)
