class_name ChapterInteractable
extends Area3D

signal activated(interactable_id: String)

@export var interactable_id: String
@export var prompt_text: String = "Press E to interact."

func is_player_nearby(player: Node3D) -> bool:
	return has_overlapping_bodies() and get_overlapping_bodies().has(player)

func activate() -> void:
	activated.emit(interactable_id)
