class_name BuffSystem extends Node

signal buff_applied(buff: BuffData)
signal buff_expired(buff: BuffData)
signal buff_removed(buff: BuffData)
signal stats_changed()

# Each entry: { data: BuffData, remaining: float }
var _active: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("buff_system")
	var gs = get_node_or_null("/root/GameState")
	if gs:
		if gs.has_signal("buff_applied"):
			gs.buff_applied.connect(_on_gamestate_buff_applied)
		if gs.has_signal("night_started"):
			gs.night_started.connect(_on_night_started)


func _process(delta: float) -> void:
	var expired: Array[BuffData] = []
	for entry in _active:
		if entry.data.duration < 0.0:
			continue
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			expired.append(entry.data)
	for buff in expired:
		_remove_entry(buff)
		buff_expired.emit(buff)
	if not expired.is_empty():
		stats_changed.emit()


func apply_buff(buff: BuffData) -> void:
	if buff == null: return
	for entry in _active:
		if entry.data == buff:
			entry.remaining = buff.duration
			buff_applied.emit(buff)
			stats_changed.emit()
			return
	_active.append({ "data": buff, "remaining": buff.duration })
	buff_applied.emit(buff)
	stats_changed.emit()


func remove_buff(buff: BuffData) -> void:
	_remove_entry(buff)
	buff_removed.emit(buff)
	stats_changed.emit()


func get_multiplier(stat: BuffData.StatTarget) -> float:
	var result := 1.0
	for entry in _active:
		if entry.data.stat_target == stat:
			result *= entry.data.multiplier
	return result


func get_addend(stat: BuffData.StatTarget) -> float:
	var result := 0.0
	for entry in _active:
		if entry.data.stat_target == stat:
			result += entry.data.addend
	return result


func _on_night_started() -> void:
	var to_clear: Array[BuffData] = []
	for entry in _active:
		if entry.data.duration >= 0.0:
			to_clear.append(entry.data)
	for buff in to_clear:
		_remove_entry(buff)
		buff_removed.emit(buff)
	if not to_clear.is_empty():
		stats_changed.emit()


func _remove_entry(buff: BuffData) -> void:
	for i in range(_active.size() - 1, -1, -1):
		if _active[i].data == buff:
			_active.remove_at(i)
			return


func _on_gamestate_buff_applied(buff: BuffData) -> void:
	apply_buff(buff)
