extends HBoxContainer
class_name InventorySlots

const _COLOR_EMPTY  := Color(0.08, 0.08, 0.08, 0.85)
const _COLOR_WEAPON :=  Color(1.0, 0.173, 0.161, 0.9)
const _COLOR_ACTIVE := Color(0.35, 0.90, 0.40, 1.0)
const _COLOR_ITEM   := Color(0.85, 0.45, 0.10, 0.9)

var _inventory: InventorySystem = null
var _active_slot: String = "main_slot"

@onready var _slot_main:      ColorRect = $SlotMain
@onready var _slot_secondary: ColorRect = $SlotSecondary
@onready var _slot_item1:     ColorRect = $SlotItem1
@onready var _slot_item2:     ColorRect = $SlotItem2


func setup(inventory: InventorySystem) -> void:
	_inventory = inventory
	_inventory.slot_changed.connect(_on_slot_changed)
	_inventory.equipped_weapon_changed.connect(_on_weapon_changed)
	_refresh_all_slots()


func _refresh_all_slots() -> void:
	if _inventory == null: return
	_update_weapon_slot(_slot_main,      _inventory.main_slot,      "main_slot")
	_update_weapon_slot(_slot_secondary, _inventory.secondary_slot, "secondary_slot")
	_update_item_slot(_slot_item1, _inventory.item_slot_1)
	_update_item_slot(_slot_item2, _inventory.item_slot_2)


func _update_weapon_slot(rect: ColorRect, data: FishWeaponData, slot_name: String) -> void:
	if rect == null: return
	var icon: TextureRect = rect.get_node_or_null("Icon")
	if data == null:
		rect.color = _COLOR_EMPTY
		if icon: icon.texture = null
	elif slot_name == _active_slot:
		rect.color = _COLOR_ACTIVE
		if icon and data.sprite_frames:
			icon.texture = data.sprite_frames.get_frame_texture("default", 0)
	else:
		rect.color = _COLOR_WEAPON
		if icon and data.sprite_frames:
			icon.texture = data.sprite_frames.get_frame_texture("default", 0)


func _update_item_slot(rect: ColorRect, data: HealingItemData) -> void:
	if rect == null: return
	var icon: TextureRect = rect.get_node_or_null("Icon")
	if data == null:
		rect.color = _COLOR_EMPTY
		if icon: icon.texture = null
	else:
		rect.color = _COLOR_ITEM
		if icon: icon.texture = data.sprite


func _on_slot_changed(slot_name: String) -> void:
	if _inventory == null: return
	match slot_name:
		"main_slot":      _update_weapon_slot(_slot_main,      _inventory.main_slot,      "main_slot")
		"secondary_slot": _update_weapon_slot(_slot_secondary, _inventory.secondary_slot, "secondary_slot")
		"item_slot_1":    _update_item_slot(_slot_item1, _inventory.item_slot_1)
		"item_slot_2":    _update_item_slot(_slot_item2, _inventory.item_slot_2)


func _on_weapon_changed(_weapon_node: Weapon) -> void:
	if _inventory == null: return
	_active_slot = _inventory._active_weapon_slot
	_update_weapon_slot(_slot_main,      _inventory.main_slot,      "main_slot")
	_update_weapon_slot(_slot_secondary, _inventory.secondary_slot, "secondary_slot")
