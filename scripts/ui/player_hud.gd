extends Control
class_name PlayerHUD

const INVENTORY_SLOTS = preload("res://scenes/ui/InventorySlots.tscn")

@export var hp_fill_texture: Texture2D
@export var cp_fill_texture: Texture2D
@export var sp_fill_texture: Texture2D

@onready var _hp_bar: ProgressBar = $Panel/VBoxContainer/HPRow/Control/HPBar
@onready var _cp_bar: ProgressBar = $Panel/VBoxContainer/CPRow/Control/CPBar
@onready var _sp_bar: ProgressBar = $Panel/VBoxContainer/SPRow/Control/SPBar
@onready var _wave_label: Label   = $"../EnemyCounter"

var _player = null
var _inventory: InventorySystem = null


func _ready() -> void:
	_apply_textures()
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("PlayerHUD: no node in group 'player'")
		return
	var health = _player.get_node_or_null("COMPONENTS/HealthComponent")
	if health:
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current_hp, health.max_hp)
	_inventory = _player.get_node_or_null("COMPONENTS/InventorySystem")
	if _inventory:
		var slots: InventorySlots = INVENTORY_SLOTS.instantiate()
		get_parent().add_child(slots)
		slots.setup(_inventory)
	var spawner := get_tree().get_first_node_in_group(&"enemy_spawner")
	if spawner:
		spawner.wave_updated.connect(_on_wave_updated)


func _apply_textures() -> void:
	_apply_bar_texture(_hp_bar, hp_fill_texture)
	_apply_bar_texture(_cp_bar, cp_fill_texture)
	_apply_bar_texture(_sp_bar, sp_fill_texture)


func _apply_bar_texture(bar: ProgressBar, tex: Texture2D) -> void:
	if tex == null: return
	var style := StyleBoxTexture.new()
	style.texture = tex
	bar.add_theme_stylebox_override("fill", style)


func _on_health_changed(current: int, maximum: int) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current


func _on_wave_updated(remaining: int) -> void:
	if _wave_label:
		_wave_label.text = "Enemies: %d" % remaining


func _process(_delta: float) -> void:
	if _player == null: return
	_cp_bar.value = _player.CP
	_sp_bar.value = _player.SP
