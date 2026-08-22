class_name CombatHitbox
extends Area3D

@export var damage: float = 10.0
@export var can_stagger: bool = true

var source_combatant: Combatant
var already_hit: Array[CombatHurtbox] = []

func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)

func activate(active_damage: float, duration: float, stagger: bool = true) -> void:
	damage = active_damage
	can_stagger = stagger
	already_hit.clear()
	monitoring = true
	await get_tree().create_timer(duration).timeout
	monitoring = false

func _on_area_entered(area: Area3D) -> void:
	if not area is CombatHurtbox:
		return
	var hurtbox := area as CombatHurtbox
	if hurtbox in already_hit or hurtbox.combatant == source_combatant:
		return
	already_hit.append(hurtbox)
	hurtbox.receive_hit(self)
