class_name CombatHurtbox
extends Area3D

@export var combatant_path: NodePath

@onready var combatant: Combatant = get_node(combatant_path)

func receive_hit(hitbox: CombatHitbox) -> bool:
	return combatant.receive_damage(hitbox.damage, hitbox.can_stagger)
