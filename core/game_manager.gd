extends Node

enum GameState { BOOT, GAMEPLAY, PAUSED, LOADING }

var current_state: GameState = GameState.BOOT
var current_episode: int = 1
var current_chapter: int = 0
var is_paused: bool = false
var save_data: SaveData

func _ready() -> void:
	new_game()

func new_game() -> void:
	save_data = SaveData.new()
	current_episode = save_data.episode
	current_chapter = save_data.chapter
	set_game_state(GameState.BOOT)

func apply_save_data(data: SaveData) -> void:
	save_data = data
	current_episode = data.episode
	current_chapter = data.chapter

func set_game_state(next_state: GameState) -> void:
	current_state = next_state
	is_paused = next_state == GameState.PAUSED
	get_tree().paused = is_paused

func can_autosave() -> bool:
	return current_state == GameState.GAMEPLAY and not is_paused
