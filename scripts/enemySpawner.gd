# enemySpawner.gd
extends Node3D

signal wave_updated(enemies_remaining: int)

@export_group("References")
@export var player: CharacterBody3D
@export var tanky_fish: PackedScene
@export var normal_fish: PackedScene
@export var ranged_fish: PackedScene
@export var spawn_points_container: Node3D

@export_group("Population")
@export var base_population: int = 20
@export var population_growth_rate: float = 1.4
@export var max_capacity: int = 70
@export var hard_population_cap: int = 300

@export_group("Spawn Timing")
@export var spawn_interval: float = 0.6
@export var spawn_burst_limit: int = 2

@export_group("Debug")
@export var dbg: bool = false

const _WEIGHTS: PackedInt32Array = [40, 50, 10]
const _TOTAL_WEIGHT: int         = 100
const SPAWN_DISTANCE: float      = 50.0
const POOL_SIZE: int             = 80

# free-list; O(1) acquire and release instead of linear scan
# _free_list is a stack of indices into _pool
var _pool: Array[Node3D]      = []
var _free_list: Array[int]    = []
var _scenes: Array[PackedScene]

var _day_count: int            = 0
var _next_elite_day: int       = 0
var _is_night: bool            = false
var _population_remaining: int = 0
var current_capacity: int      = 0
var _spawn_timer: float        = 0.0
var _dns: Node                 = null

func _ready() -> void:
	add_to_group(&"enemy_spawner")
	set_process(false)  # off by default; enabled only during night
	_scenes = [
		tanky_fish,
		normal_fish,
		ranged_fish if ranged_fish != null else normal_fish,
	]
	_build_pool()
	var dns: Node = get_tree().get_first_node_in_group(&"day_night")
	if dns == null:
		push_warning("[spawner] no day_night node found in group 'day_night'")
		return
	_dns = dns
	dns.day_night_changed.connect(_on_night_changed)
	_pick_next_elite_day()
	
	
func _build_pool() -> void:
	# distribute pool slots proportionally to weights; no RNG, no per-slot roll
	# tanky=35% normal=50% ranged=15% of POOL_SIZE
	var counts: PackedInt32Array = [
		POOL_SIZE * _WEIGHTS[0] / _TOTAL_WEIGHT,  # tanky
		POOL_SIZE * _WEIGHTS[1] / _TOTAL_WEIGHT,  # normal
		POOL_SIZE * _WEIGHTS[2] / _TOTAL_WEIGHT,  # ranged
	]
	
	var idx: int = 0
	for type in counts.size():
		var scene: PackedScene = _scenes[type]
		for j in counts[type]:
			var instance: Node3D = scene.instantiate() as Node3D
			instance.set_process(false)
			instance.set_physics_process(false)
			instance.visible = false
			add_child(instance)
			instance.global_position = Vector3(0.0, -9999.0, 0.0)
			instance.set_meta(&"pool_idx", idx)  # stamp index; O(1) lookup on death
			_pool.append(instance)
			_free_list.append(idx)
			idx += 1
	_free_list.shuffle()  # distribute all types evenly; without this tanky fish stay at stack bottom and never spawn
	if dbg: print("[spawner] pool built; size; ", _pool.size())
		
		
# O(1) acquire; pop from free-list stack
func _acquire_enemy() -> Node3D:
	if _free_list.is_empty():
		push_warning("[spawner] pool exhausted; raise POOL_SIZE")
		return null
	return _pool[_free_list.pop_back()]
	
	
# O(1) release; push index back onto free-list stack
func _release_to_pool(enemy: Node3D) -> void:
	enemy.visible = false
	enemy.set_process(false)
	enemy.set_physics_process(false)
	enemy.remove_from_group(&"active_enemy")
	enemy.global_position = Vector3(0.0, -9999.0, 0.0)
	_free_list.push_back(_pool.find(enemy))  # find() is O(n) but only on death; dala nanag smile
	current_capacity -= 1
	wave_updated.emit(_population_remaining + current_capacity)
	if dbg: _log_count("death")
	_check_wave_complete()
	
	
func _on_night_changed(active: bool) -> void:
	_is_night = active
	if active:
		_population_remaining = _calculate_population()
		_spawn_timer = 0.0
		wave_updated.emit(_population_remaining)
		set_process(true)  # wake up; start spawning
		if dbg:
			print("[spawner] night started; day; ", _day_count,
				"  population; ", _population_remaining,
				"  max_capacity; ", max_capacity)
	else:
		_day_count += 1
		set_process(false)  # sleep until next night; zero per-frame cost
		if dbg: print("[spawner] day ", _day_count, " ; enemies alive; ", current_capacity)
			
			
func _pick_next_elite_day() -> void:
	_next_elite_day = _day_count + randi_range(2, 3)
	
	
func _calculate_population() -> int:
	var raw: float = base_population * (1.0 + population_growth_rate * log(1.0 + _day_count))
	return mini(int(raw), hard_population_cap)
	
	
func _process(delta: float) -> void:
	# guard: sleep _process when nothing left to spawn this wave
	if _population_remaining <= 0 or current_capacity >= max_capacity:
		set_process(false)
		_check_wave_complete()
		return
	_spawn_timer += delta
	if _spawn_timer < spawn_interval: return
	_spawn_timer = 0.0
	
	# hoist loop bounds; avoids re-reading vars each iteration
	var burst_left: int = mini(spawn_burst_limit,
		mini(_population_remaining, max_capacity - current_capacity))
		
	for i in burst_left:
		var elite: bool = (_day_count >= _next_elite_day and i == 0)
		_spawn(_get_random_position(), elite)
		if elite: _pick_next_elite_day()
		
		
func _spawn(pos: Vector3, elite: bool = false) -> void:
	var enemy: Node3D = _acquire_enemy()
	if enemy == null: return

	enemy.global_position  = pos
	enemy.player_reference = player
	enemy.is_elite         = elite
	enemy.visible          = true
	enemy.set_process(true)
	enemy.set_physics_process(true)
	enemy.add_to_group(&"active_enemy")
	enemy.reset()
	enemy.apply_day_scaling(_day_count)  # apply day scaling after reset
	current_capacity      += 1
	_population_remaining -= 1
	if dbg: _log_count("spawn")
	
	
func _check_wave_complete() -> void:
	if _is_night and _population_remaining <= 0 and current_capacity <= 0:
		if _dns != null:
			_dns.return_to_day()


func _pick_random_scene() -> PackedScene:
	var roll: int = randi_range(1, _TOTAL_WEIGHT)
	var cumulative: int = 0
	for i in _WEIGHTS.size():
		cumulative += _WEIGHTS[i]
		if roll <= cumulative: return _scenes[i]
	return normal_fish
	
	
func _get_random_position() -> Vector3:
	if spawn_points_container != null and spawn_points_container.get_child_count() > 0:
		var count := spawn_points_container.get_child_count()
		# shuffle order so we don't always favour the same point on failure
		var indices := range(count)
		indices.shuffle()
		for i in indices:
			var pt := spawn_points_container.get_child(i) as Node3D
			var validated := _ground_check(pt.global_position)
			if validated != Vector3.ZERO:
				return validated
		push_warning("[spawner] all spawn points failed ground check; falling back")
	var angle: float = randf_range(0.0, TAU)
	return player.position + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_DISTANCE


func _ground_check(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query  := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 10, 0),
		pos + Vector3(0, -10, 0)
	)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return Vector3.ZERO
	var hit_y: float = result.position.y
	if hit_y < -0.5:  # below sea level — water, not land
		return Vector3.ZERO
	return result.position + Vector3(0, 0.5, 0)  # place enemy just above ground
	
	
func _log_count(event: String) -> void:
	print("[spawner] ", event,
		" ; live; ", current_capacity,
		" / ", max_capacity,
		" ; remaining; ", _population_remaining,
		" ; fps; ", Engine.get_frames_per_second(),
		" ; day; ", _day_count)
