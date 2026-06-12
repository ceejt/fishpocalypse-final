# scripts/fishSystem/fishing_system.gd
class_name FishingSystem
extends Node

# Weights indexed by rarity order in RarityConfig.tiers (common=0 … ???=5)
const BASE_RARITY_WEIGHTS: Array[float] = [100.0, 60.0, 30.0, 10.0, 3.0, 1.0]

@export var items_db: ItemsDB
@export var rarity_config: RarityConfig
@export var minigame: FishingMinigame
@export var item_spawner: ItemSpawner

## World-space center of the island. Used to compute which direction faces water.
## Set this once in the Inspector to match your island's center position.
@export var island_center: Vector3 = Vector3.ZERO

var _can_fish: bool = false
var _in_shore_zone: bool = false
var _zones_entered: int = 0  # counts overlapping zones the player is inside
var _player: Node3D = null
var _locked_player: Node3D = null
var _game_state: Node = null

func _ready() -> void:
	if minigame == null:
		minigame = get_node_or_null("../UI/FishingMinigame")
	if minigame == null:
		push_error("FishingSystem: FishingMinigame not found at ../UI/FishingMinigame — assign via Inspector.")
		return
	if items_db == null:
		push_error("FishingSystem: 'items_db' export not assigned in Inspector.")
		return
	_game_state = get_node_or_null("/root/GameState")
	if _game_state != null:
		if _game_state.has_signal("day_started"):
			_game_state.day_started.connect(_on_day_started)
		if _game_state.has_signal("night_started"):
			_game_state.night_started.connect(_on_day_ended)
		if _game_state.has_signal("transition_started"):
			_game_state.transition_started.connect(_on_day_ended)
	else:
		push_warning("FishingSystem: GameState autoload not found — fishing enabled for all times (debug mode).")
		_can_fish = true
	if item_spawner == null:
		var spawners := get_tree().get_nodes_in_group("item_spawners")
		if not spawners.is_empty():
			item_spawner = spawners[0] as ItemSpawner
	minigame.caught.connect(_on_caught)
	minigame.failed.connect(_on_failed)
	call_deferred("_connect_shore_zones")

func _on_day_started() -> void:
	_can_fish = true

func _on_day_ended() -> void:
	_can_fish = false
	_zones_entered = 0
	if minigame.is_active():
		minigame.cancel()
		_unfreeze_player()

func _unhandled_input(event: InputEvent) -> void:
	if not _can_fish or not _in_shore_zone or minigame.is_active():
		return
	if not InputMap.has_action("INTERACT"):
		return
	if event.is_action_pressed("INTERACT"):
		_start_fishing()

func _start_fishing() -> void:
	var pole := _get_equipped_pole()
	if pole == null:
		return
	var item := _roll_item(pole)
	if item == null:
		push_warning("FishingSystem: catch pool empty (all weapons locked by spawn_day?)")
		return
	# Pick the fishing animation based on water direction (no rotation — camera is a child of player)
	var water_dir := _get_water_direction()
	var anim_name := _pick_fishing_anim(water_dir)
	if _player != null and _player.has_method("play_fishing_anim"):
		_player.play_fishing_anim(anim_name)
	minigame.start_wait(item, pole)
	_freeze_player()

## Detects which cardinal direction has water by casting a short downward ray
## in each of the 4 directions from the player. The direction where the ray
## finds no ground (or ground below water level) is the water direction.
## Falls back to island_center math if all raycasts hit solid ground.
func _get_water_direction() -> Vector3:
	if _player == null:
		return Vector3.FORWARD

	var space := _player.get_world_3d().direct_space_state
	var probe_dist := 4.0   # how far to probe outward from player
	var water_y    := -1.0  # ground hits below this y are treated as water

	var dirs: Array[Vector3] = [
		Vector3(0.0, 0.0,  1.0),  # +Z  south / toward camera
		Vector3(0.0, 0.0, -1.0),  # -Z  north / away from camera
		Vector3( 1.0, 0.0, 0.0),  # +X  east  / screen-right
		Vector3(-1.0, 0.0, 0.0),  # -X  west  / screen-left
	]

	var water_dirs: Array[Vector3] = []
	for d: Vector3 in dirs:
		var probe := _player.global_position + d * probe_dist
		var params := PhysicsRayQueryParameters3D.create(
			probe + Vector3(0.0, 2.0, 0.0),
			probe + Vector3(0.0, -6.0, 0.0)
		)
		params.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(params)
		# No terrain hit, or hit is at/below water level → water is this way
		if hit.is_empty() or (hit["position"] as Vector3).y < water_y:
			water_dirs.append(d)

	if not water_dirs.is_empty():
		var combined := Vector3.ZERO
		for d: Vector3 in water_dirs:
			combined += d
		if combined.length_squared() > 0.001:
			return combined.normalized()

	# Fallback: use island_center offset when all probes hit solid ground
	var fallback := _player.global_position - island_center
	fallback.y = 0.0
	if fallback.length_squared() > 0.001:
		return fallback.normalized()
	return Vector3.FORWARD

## Maps a water direction to a fishing animation.
## +Z (south / sea below on screen) -> fish_front
## -Z (north / sea above on screen) -> walk_back  (no fish_back sprite exists)
## +X (east  / screen-right)        -> fish_right
## -X (west  / screen-left)         -> fish_left
func _pick_fishing_anim(water_dir: Vector3) -> String:
	var ax := absf(water_dir.x)
	var az := absf(water_dir.z)
	if az >= ax:
		return "fish_front" if water_dir.z > 0.0 else "walk_back"
	return "fish_right" if water_dir.x > 0.0 else "fish_left"

func _roll_item(pole: FishingPoleData) -> Resource:
	var pool: Array[Resource] = []
	var weights: Array[float] = []
	var raw = _game_state.get("day_count") if _game_state != null else 1
	if raw == null:
		push_warning("FishingSystem: GameState.day_count not found — defaulting to 1")
	var day: int = raw if raw != null else 1

	for w: FishWeaponData in items_db.fish_weapons:
		if w.spawn_day <= day:
			var idx := _rarity_index(w.rarity)
			pool.append(w)
			weights.append(BASE_RARITY_WEIGHTS[idx] * (1.0 + pole.base_lure_chance * (w.rarity.lure_multiplier if w.rarity != null else 1.0)))

	for h: HealingItemData in items_db.healing_items:
		pool.append(h)
		weights.append(BASE_RARITY_WEIGHTS[0] * (1.0 + pole.base_lure_chance))

	for p: FishingPoleData in items_db.fishing_poles:
		var idx := _rarity_index(p.rarity)
		pool.append(p)
		weights.append(BASE_RARITY_WEIGHTS[idx] * (1.0 + pole.base_lure_chance * (p.rarity.lure_multiplier if p.rarity != null else 1.0)))

	if pool.is_empty():
		return null
	return _weighted_pick(pool, weights)

func _weighted_pick(pool: Array[Resource], weights: Array[float]) -> Resource:
	var total := 0.0
	for w: float in weights:
		total += w
	var roll := randf() * total
	var acc := 0.0
	for i: int in pool.size():
		acc += weights[i]
		if roll <= acc:
			return pool[i]
	return pool[-1]

func _rarity_index(rarity: RarityTier) -> int:
	if rarity_config == null or rarity == null:
		return 0
	for i: int in rarity_config.tiers.size():
		if rarity_config.tiers[i] == rarity:
			return i
	return 0

func _get_equipped_pole() -> FishingPoleData:
	if _player != null and _player.has_node("InventorySystem"):
		var inv := _player.get_node("InventorySystem")
		if inv.has_method("get_equipped_pole"):
			var p: FishingPoleData = inv.get_equipped_pole()
			if p != null:
				return p
	if not items_db.fishing_poles.is_empty():
		return items_db.fishing_poles[0]
	push_error("FishingSystem: no fishing poles in ItemsDB")
	return null

func _on_shore_entered(player: Node3D) -> void:
	_zones_entered += 1
	_in_shore_zone = true
	_player = player
	if _player.has_method("show_fishing_prompt"):
		_player.show_fishing_prompt()

func _on_shore_exited() -> void:
	_zones_entered = maxi(_zones_entered - 1, 0)
	if _zones_entered > 0:
		return  # still inside at least one other zone — keep prompt active
	_in_shore_zone = false
	if _player != null and _player.has_method("hide_fishing_prompt"):
		_player.hide_fishing_prompt()
	_player = null

func _on_caught(item: Resource) -> void:
	_unfreeze_player()
	if item_spawner == null:
		push_error("FishingSystem: 'item_spawner' export not assigned — caught item lost")
		return
	if _player != null:
		item_spawner.spawn_marker.global_position = _player.global_position
	var rarity: RarityTier = _get_item_rarity(item)
	if item is FishWeaponData:
		item_spawner.spawn_weapon(item as FishWeaponData, rarity)
	elif item is HealingItemData:
		var common: RarityTier = rarity_config.tiers[0] if rarity_config and not rarity_config.tiers.is_empty() else null
		item_spawner.spawn_healing_item(item as HealingItemData, common)
	elif item is FishingPoleData:
		item_spawner.spawn_pole(item as FishingPoleData, rarity)

func _on_failed() -> void:
	_unfreeze_player()

func _freeze_player() -> void:
	if _player == null:
		return
	_locked_player = _player
	_locked_player.set_physics_process(false)
	if _locked_player is CharacterBody3D:
		(_locked_player as CharacterBody3D).velocity = Vector3.ZERO

func _unfreeze_player() -> void:
	if _locked_player == null:
		return
	_locked_player.set_physics_process(true)
	_locked_player = null

func _connect_shore_zones() -> void:
	for node in get_tree().get_nodes_in_group("shore_zones"):
		if node is ShoreZone:
			node.player_entered_shore.connect(_on_shore_entered)
			node.player_exited_shore.connect(_on_shore_exited)

func _get_item_rarity(item: Resource) -> RarityTier:
	var r: RarityTier = item.get("rarity") as RarityTier
	if r != null:
		return r
	if rarity_config and not rarity_config.tiers.is_empty():
		return rarity_config.tiers[0]
	return null
