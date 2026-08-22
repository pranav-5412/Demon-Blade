extends Node

const REQUIRED_ACTIONS: PackedStringArray = ["move_forward", "move_backward", "move_left", "move_right", "sprint", "jump", "interact", "attack", "heavy_attack", "dodge", "block", "lock_on", "ability_1", "ability_2", "ability_3", "ability_4", "ability_5", "ability_6", "ability_7", "switch_character", "pause"]

func has_required_actions() -> bool:
	for action in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			return false
	return true
