class_name WaterFormData
extends Resource

@export var form_number: int = 1
@export var ability_name: String = "Water Form"
@export var input_action: StringName = &"ability_1"
@export var gameplay_role: String = "strike"
@export var stamina_cost: float = 10.0
@export var breath_cost: float = 15.0
@export var cooldown: float = 1.0
@export var damage: float = 20.0
@export var movement_distance: float = 0.0
@export var hitbox_scale: Vector3 = Vector3.ONE
@export var active_time: float = 0.2
@export var vfx_hook: StringName = &"water_arc"
@export var sfx_hook: StringName = &"water_form"
@export var animation_hook: StringName = &"procedural_slash"
@export var camera_feedback_hook: StringName = &"light_impulse"
