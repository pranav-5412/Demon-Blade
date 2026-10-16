class_name TrainingDummy
extends Node3D

signal dummy_damaged(dummy: TrainingDummy, amount: float)
signal dummy_defeated(dummy: TrainingDummy)

@onready var combatant: Combatant = $Combatant
@onready var visual: MeshInstance3D = $Visual
@onready var hurtbox: Area3D = $Hurtbox

func _ready() -> void:
	combatant.damaged.connect(_on_damaged)
	combatant.defeated.connect(_on_defeated)

func reset_dummy(health: float = 100.0) -> void:
	combatant.max_health = health
	combatant.restore_full_health()
	visible = true
	hurtbox.set_deferred("monitorable", true)
	visual.scale = Vector3.ONE

func _on_damaged(amount: float, _guarded: bool) -> void:
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3(1.18, 0.82, 1.18), 0.08)
	tween.tween_property(visual, "scale", Vector3.ONE, 0.12)
	dummy_damaged.emit(self, amount)

func _on_defeated() -> void:
	hurtbox.set_deferred("monitorable", false)
	visual.scale = Vector3(1.0, 0.25, 1.0)
	dummy_defeated.emit(self)
