extends Node

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	await get_tree().process_frame
	await _run()
	if failures.is_empty():
		print("SCENE_MANAGER_TEST: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST FAILURE: %s" % failure)
		print("SCENE_MANAGER_TEST: FAIL (%d failures / %d checks)" % [failures.size(), checks])
		get_tree().quit(1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)

func _run() -> void:
	# Test 1: File not found
	SceneManager.is_transitioning = false
	var result = SceneManager.transition_to("res://non_existent_scene.tscn")
	_check(result == ERR_FILE_NOT_FOUND, "Returns ERR_FILE_NOT_FOUND for invalid path")
	_check(SceneManager.is_transitioning == false, "is_transitioning remains false after failed invalid path")

	# Test 2: Busy
	SceneManager.is_transitioning = true
	result = SceneManager.transition_to("res://tests/dummy_scene.tscn")
	_check(result == ERR_BUSY, "Returns ERR_BUSY when already transitioning")
	_check(SceneManager.is_transitioning == true, "is_transitioning remains true when busy")

	# Test 3: Valid file but invalid scene
	SceneManager.is_transitioning = false
	result = SceneManager.transition_to("res://icon.svg")
	_check(result != OK, "Returns error for non-scene file")
	_check(SceneManager.is_transitioning == false, "is_transitioning resets to false after failed load")
	_check(GameManager.current_state == GameManager.GameState.BOOT, "Game state set to BOOT on failed load")

	# Test 4: Successful transition
	SceneManager.is_transitioning = false
	var dummy_path = "res://tests/dummy_scene.tscn"
	result = SceneManager.transition_to(dummy_path)
	_check(result == OK, "Returns OK for valid scene path")
	_check(SceneManager.is_transitioning == false, "is_transitioning resets to false after successful transition")
	_check(GameManager.current_state == GameManager.GameState.LOADING, "Game state set to LOADING on successful transition")
