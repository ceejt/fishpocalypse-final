class_name FishingMinigame
extends Control

signal caught(item: Resource)
signal failed()

enum State { IDLE, WAITING, BITE, ACTIVE, RESULT_SUCCESS, RESULT_FAIL }

const RISE_ACCEL := 6.5
const FALL_GRAVITY := 3.2
const FILL_RATE := 0.35
const DRAIN_RATE := 0.22
const RESULT_DISPLAY_TIME := 0.8

# Lihok sa isda
const DIR_CHANGE_MIN := 0.15
const DIR_CHANGE_MAX := 0.25

# Minimum mo howat og Max
const WAIT_MIN := 2.0
const WAIT_MAX := 2.0
const BITE_WINDOW_MIN := 0.7
const BITE_WINDOW_MAX := 100.0

@onready var _fish_bar: FishingBar = $CenterBox/ContentVBox/BarsHBox/FishBar
@onready var _catch_progress: ProgressBar = $CenterBox/ContentVBox/BarsHBox/CatchStatus/CatchProgress
@onready var _wait_label: Label = $WaitLabel
@onready var _bite_label: Label = $BiteLabel
@onready var _white_bg: Panel = $Panel
@onready var _reel_audio: AudioStreamPlayer = $ReelAudio
@onready var _caught_audio: AudioStreamPlayer = $CaughtAudio

var _state: State = State.IDLE
var _fish_pos: float = 0.5
var _fish_vel: float = 0.0
var _fish_dir_timer: float = 0.0
var _zone_pos: float = 0.35
var _zone_vel: float = 0.0
var _zone_size: float = 0.25
var _fish_speed: float = 1.5
var _catch_val: float = 0.0
var _result_timer: float = 0.0

var _pending_item: Resource = null
var _pending_pole: FishingPoleData = null
var _wait_timer: float = 0.0
var _bite_window: float = 0.0

func _ready() -> void:
	_set_state(State.IDLE)

func start_wait(item: Resource, pole: FishingPoleData) -> void:
	_pending_item = item
	_pending_pole = pole
	_wait_timer = randf_range(WAIT_MIN, WAIT_MAX)
	_set_state(State.WAITING)

func cancel() -> void:
	_set_state(State.IDLE)

func is_active() -> bool:
	return _state != State.IDLE

func _set_state(s: State) -> void:
	_state = s
	visible = false
	_wait_label.visible = false
	_bite_label.visible = false
	$CenterBox.visible = false
	_white_bg. visible = false
	_reel_audio.stop()

	match s:
		State.IDLE:
			pass
		State.WAITING:
			visible = true
			_wait_label.visible = true
			_wait_label.text = "Waiting for a bite..."
		State.BITE:
			visible = true
			_bite_label.visible = true
		State.ACTIVE:
			visible = true
			$CenterBox.visible = true
			_white_bg.visible = true
			_fish_pos = 0.5
			_fish_vel = 0.0
			_zone_pos = 0.35
			_zone_vel = 0.0
			_catch_val = 0.25
			_fish_dir_timer = 0.0
			_zone_size = _pending_pole.base_bar_size
			_fish_speed = _pending_pole.base_lure_speed
			_reel_audio.play()
		State.RESULT_SUCCESS:
			visible = true
			$CenterBox.visible = true
			_white_bg.visible = true
			_result_timer = RESULT_DISPLAY_TIME
			_caught_audio.play()
		State.RESULT_FAIL:
			visible = true
			$CenterBox.visible = true
			_white_bg.visible = true
			_result_timer = RESULT_DISPLAY_TIME

func _process(delta: float) -> void:
	match _state:
		State.WAITING:
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_bite_window = randf_range(BITE_WINDOW_MIN, BITE_WINDOW_MAX)
				_set_state(State.BITE)
		State.BITE:
			_bite_window -= delta
			if _bite_window <= 0.0:
				_set_state(State.IDLE)
				failed.emit()
		State.ACTIVE:
			_update_fish(delta)
			_update_zone(delta)
			_update_progress(delta)
			_fish_bar.fish_pos = _fish_pos
			_fish_bar.zone_pos = _zone_pos
			_fish_bar.zone_size = _zone_size
			_fish_bar.queue_redraw()
			_catch_progress.value = _catch_val
		State.RESULT_SUCCESS, State.RESULT_FAIL:
			_result_timer -= delta
			if _result_timer <= 0.0:
				var succeeded := (_state == State.RESULT_SUCCESS)
				_set_state(State.IDLE)
				if succeeded:
					caught.emit(_pending_item)
				else:
					failed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("INTERACT"):
		return
	match _state:
		State.WAITING:
			# Early press — cancel cast; consume event so FishingSystem doesn't re-cast on same keypress
			get_viewport().set_input_as_handled()
			_set_state(State.IDLE)
			failed.emit()
		State.BITE:
			_set_state(State.ACTIVE)

func _update_fish(delta: float) -> void:
	_fish_dir_timer -= delta
	if _fish_dir_timer <= 0.0:
		_fish_vel = randf_range(-_fish_speed, _fish_speed)
		_fish_dir_timer = randf_range(DIR_CHANGE_MIN, DIR_CHANGE_MAX)
	_fish_pos += _fish_vel * delta
	if _fish_pos <= 0.0:
		_fish_pos = 0.0
		_fish_vel = absf(_fish_vel)
	elif _fish_pos >= 1.0:
		_fish_pos = 1.0
		_fish_vel = -absf(_fish_vel)

func _update_zone(delta: float) -> void:
	if InputMap.has_action("INTERACT") and Input.is_action_pressed("INTERACT"):
		_zone_vel -= RISE_ACCEL * delta
	_zone_vel += FALL_GRAVITY * delta
	_zone_vel = clampf(_zone_vel, -10.0, 10.0)
	_zone_pos += _zone_vel * delta
	_zone_pos = clampf(_zone_pos, 0.0, 1.0 - _zone_size)

func _update_progress(delta: float) -> void:
	if _is_fish_in_zone():
		_catch_val += FILL_RATE * delta
	else:
		_catch_val -= DRAIN_RATE * delta
	_catch_val = clampf(_catch_val, 0.0, 1.0)
	if _catch_val >= 1.0:
		_set_state(State.RESULT_SUCCESS)
	elif _catch_val <= 0.0:
		_set_state(State.RESULT_FAIL)

func _is_fish_in_zone() -> bool:
	return _fish_pos >= _zone_pos and _fish_pos <= (_zone_pos + _zone_size)
