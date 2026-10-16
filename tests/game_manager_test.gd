extends Node

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	await get_tree().process_frame
	await _run()
	if failures.is_empty():
		print("GAME_MANAGER_TEST: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST FAILURE: %s" % failure)
		print("GAME_MANAGER_TEST: FAIL (%d failures / %d checks)" % [failures.size(), checks])
		get_tree().quit(1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func _run() -> void:
	# GameManager is loaded as an autoload singleton, so we can access it globally.
	# Same with SaveData class.

	# Initial State test
	_check(GameManager.save_data != null, "GameManager.save_data should be initialized")
	_check(GameManager.current_state == GameManager.GameState.BOOT, "GameManager.current_state should be BOOT initially")
	_check(GameManager.is_paused == false, "GameManager.is_paused should be false initially")

	# Test apply_save_data
	var new_save = SaveData.new()
	new_save.episode = 5
	new_save.chapter = 3
	new_save.player_health = 150.0

	GameManager.apply_save_data(new_save)

	_check(GameManager.save_data == new_save, "GameManager.save_data should match the applied SaveData")
	_check(GameManager.current_episode == 5, "GameManager.current_episode should be set to 5")
	_check(GameManager.current_chapter == 3, "GameManager.current_chapter should be set to 3")

	# Test set_game_state PAUSED
	GameManager.set_game_state(GameManager.GameState.PAUSED)
	_check(GameManager.current_state == GameManager.GameState.PAUSED, "GameManager.current_state should be PAUSED")
	_check(GameManager.is_paused == true, "GameManager.is_paused should be true")
	_check(get_tree().paused == true, "get_tree().paused should be true")
	_check(GameManager.can_autosave() == false, "Cannot autosave when paused")

	# Test set_game_state GAMEPLAY
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_check(GameManager.current_state == GameManager.GameState.GAMEPLAY, "GameManager.current_state should be GAMEPLAY")
	_check(GameManager.is_paused == false, "GameManager.is_paused should be false")
	_check(get_tree().paused == false, "get_tree().paused should be false")
	_check(GameManager.can_autosave() == true, "Can autosave in GAMEPLAY when not paused")

	# Test new_game
	GameManager.new_game()
	_check(GameManager.save_data != null, "GameManager.save_data should be initialized after new_game")
	_check(GameManager.save_data != new_save, "GameManager.save_data should be a new instance after new_game")
	_check(GameManager.current_state == GameManager.GameState.BOOT, "GameManager.current_state should be BOOT after new_game")
	_check(GameManager.current_episode == 1, "GameManager.current_episode should be 1 after new_game")
	_check(GameManager.current_chapter == 0, "GameManager.current_chapter should be 0 after new_game")
