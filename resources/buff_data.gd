class_name BuffData extends Resource

enum StatTarget { MOVE_SPEED, DAMAGE, SHOT_DELAY, HEAL_AMOUNT, MAX_HP, MAX_CP }

@export var buff_name: String = ""
@export var stat_target: StatTarget = StatTarget.MOVE_SPEED
@export var multiplier: float = 1.0
@export var addend: float = 0.0
@export var duration: float = 10.0   # seconds; -1 = permanent
@export var icon: Texture2D
