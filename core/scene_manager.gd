extends Node

var is_transitioning: bool = false

func transition_to(scene_path: String) -> Error:
	if is_transitioning or not ResourceLoader.exists(scene_path):
		return ERR_BUSY if is_transitioning else ERR_FILE_NOT_FOUND
	is_transitioning = true
	GameManager.set_game_state(GameManager.GameState.LOADING)
	var result := get_tree().change_scene_to_file(scene_path)
	is_transitioning = false
	if result != OK:
		GameManager.set_game_state(GameManager.GameState.BOOT)
	return result
