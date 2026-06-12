extends Node3D
signal day_night_changed(is_night_active: bool)

@export var day_length_sec: int = 10
@export var speed_factor: float = 1.0
@onready var light: DirectionalLight3D = $DirectionalLight3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var music_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var wind: AudioStreamPlayer = $Wind
@onready var bird: AudioStreamPlayer = $Bird

var time_accumulated: float = 0.0
var is_night: bool = false
var sky_material: ProceduralSkyMaterial
var _env: Environment

var _day_sky_top: Color
var _day_sky_horizon: Color
var _day_ground_bottom: Color
var _day_ground_horizon: Color

var MORNING_MUSIC = preload("res://assets/audio/morning_audio.mp3")
# ADDED: night tracks pool — picked randomly on each night transition
var NIGHT_MUSIC: Array = [
	preload("res://assets/audio/night_01.mp3"),
	preload("res://assets/audio/night_02.mp3"),
]

func _ready() -> void:
	MORNING_MUSIC.loop = true
	# ADDED: set loop on all night tracks
	for track in NIGHT_MUSIC:
		track.loop = true
	music_player.volume_db = -16.0
	add_to_group("day_night")
	_env = world_env.environment
	if _env and _env.sky and _env.sky.sky_material:
		sky_material = _env.sky.sky_material as ProceduralSkyMaterial
	if sky_material:
		_day_sky_top = sky_material.sky_top_color
		_day_sky_horizon = sky_material.sky_horizon_color
		_day_ground_bottom = sky_material.ground_bottom_color
		_day_ground_horizon = sky_material.ground_horizon_color
	_set_day_state()
	
func _process(delta: float) -> void:
	time_accumulated += delta * speed_factor
	if time_accumulated >= day_length_sec and not is_night:
		time_accumulated = 0.0
		_set_night_state()
		
func _set_day_state() -> void:
	is_night = false
	light.light_energy = 1.5
	light.light_color = Color("ffff9aff")
	if sky_material:
		sky_material.sky_top_color = _day_sky_top
		sky_material.sky_horizon_color = _day_sky_horizon
		sky_material.ground_bottom_color = _day_ground_bottom
		sky_material.ground_horizon_color = _day_ground_horizon
	if _env:
		_env.background_mode = Environment.BG_SKY
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_sky_contribution = 1.0
		_env.fog_enabled = true
		_env.fog_mode = Environment.FOG_MODE_DEPTH
		_env.fog_light_color = Color(0.568, 0.996, 0.922, 1.0)
		_env.fog_density = 0.90
		_env.fog_sky_affect = 1.0
	music_player.stream = MORNING_MUSIC
	music_player.play() # e comment lng ni kung saba kaau
	day_night_changed.emit(false)
	
func _set_night_state() -> void:
	is_night = true
	light.light_energy = 0.0
	
	# Remove chill music
	wind.stop()
	bird.stop()
	
	if _env:
		_env.background_mode = Environment.BG_SKY
		if sky_material:
			sky_material.sky_top_color        = Color(0.95, 0.15, 0.15)
			sky_material.sky_horizon_color     = Color(0.0,  0.0,  0.0, 1.0)
			sky_material.ground_bottom_color   = Color(0.05, 0.0,  0.0)
			sky_material.ground_horizon_color  = Color(0.12, 0.02, 0.02)
		_env.ambient_light_source          = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_color           = Color(0.12, 0.03, 0.03)
		_env.ambient_light_energy          = 0.5
		_env.ambient_light_sky_contribution = 0.0
		_env.fog_enabled     = true
		_env.fog_mode        = Environment.FOG_MODE_DEPTH
		_env.fog_light_color = Color(1.0, 0.204, 0.204, 1.0)
		_env.fog_density     = 0.9
		_env.fog_sky_affect  = 1.0
		
	# ADDED: pick a random night track from the pool
	music_player.stream = NIGHT_MUSIC[randi() % NIGHT_MUSIC.size()]
	music_player.play()
	day_night_changed.emit(true)
	
# CALL ONCE ENEMIES ARE DEAD
func return_to_day() -> void:
	if is_night:
		time_accumulated = 0.0
		_set_day_state()
