extends Node3D

@export var breath_height: float = 0.06
@export var breath_speed: float = 2.2

var base_y: float

func _ready() -> void:
	base_y = position.y

func _process(_delta: float) -> void:
	position.y = base_y + sin(Time.get_ticks_msec() * 0.001 * breath_speed) * breath_height
