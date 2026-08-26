class_name SaveData
extends RefCounted

const CURRENT_VERSION := 1

var version: int = CURRENT_VERSION
var episode: int = 1
var chapter: int = 0
var current_scene: String = ""
var player_position: Vector3 = Vector3.ZERO
var player_health: float = 200.0
var player_stamina: float = 100.0
var wan_currency: int = 0
var current_playable_character: String = ""
var unlocked_abilities: Array[String] = []
var story_flags: Dictionary = {}
var completed_objectives: Array[String] = []
var sword_material_selected: bool = false
var sword_material: String = ""
var upgrade_levels: Dictionary = {}

func to_dictionary() -> Dictionary:
	return {"version": version, "episode": episode, "chapter": chapter, "current_scene": current_scene, "player_position": {"x": player_position.x, "y": player_position.y, "z": player_position.z}, "player_health": player_health, "player_stamina": player_stamina, "wan_currency": wan_currency, "current_playable_character": current_playable_character, "unlocked_abilities": unlocked_abilities, "story_flags": story_flags, "completed_objectives": completed_objectives, "sword_material_selected": sword_material_selected, "sword_material": sword_material, "upgrade_levels": upgrade_levels}

static func from_dictionary(value: Dictionary) -> SaveData:
	var data := SaveData.new()
	data.version = int(value.get("version", CURRENT_VERSION))
	data.episode = int(value.get("episode", 1))
	data.chapter = int(value.get("chapter", 0))
	data.current_scene = str(value.get("current_scene", ""))
	var position: Variant = value.get("player_position", {})
	if position is Dictionary:
		data.player_position = Vector3(float(position.get("x", 0.0)), float(position.get("y", 0.0)), float(position.get("z", 0.0)))
	data.player_health = float(value.get("player_health", 200.0))
	data.player_stamina = float(value.get("player_stamina", 100.0))
	data.wan_currency = int(value.get("wan_currency", 0))
	data.current_playable_character = str(value.get("current_playable_character", ""))
	data.unlocked_abilities.assign(value.get("unlocked_abilities", []))
	data.story_flags = value.get("story_flags", {})
	data.completed_objectives.assign(value.get("completed_objectives", []))
	data.sword_material = str(value.get("sword_material", ""))
	data.sword_material_selected = bool(value.get("sword_material_selected", not data.sword_material.is_empty()))
	data.upgrade_levels = value.get("upgrade_levels", {})
	return data
