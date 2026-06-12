extends MeshInstance3D

@onready var splash_sprite: AnimatedSprite3D = $splash

func _ready():
	$Area3D.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	if body.is_in_group("player") or body.is_in_group("active_enemy"):
		trigger_splash(body.global_position)

func trigger_splash(player_pos: Vector3):
	splash_sprite.global_position = Vector3(player_pos.x, global_position.y + 1.0, player_pos.z)
	splash_sprite.visible = true
	splash_sprite.play("splash")
	
	await splash_sprite.animation_finished
	splash_sprite.visible = false
