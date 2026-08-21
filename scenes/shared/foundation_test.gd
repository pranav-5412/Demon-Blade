extends Control

@onready var status_label: Label = %StatusLabel

func _ready() -> void:
	var save_created := true
	if not SaveManager.has_save():
		save_created = SaveManager.create_new_save()
	var save_loaded := SaveManager.load_save()
	GameManager.save_data.current_scene = get_tree().current_scene.scene_file_path
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	var autosave_callback_saved := SaveManager.request_autosave()
	GameManager.set_game_state(GameManager.GameState.BOOT)
	var checks := [
		["GameManager initialized", GameManager.save_data != null],
		["SaveManager initialized", SaveManager.autosave_timer != null],
		["Save created", save_created],
		["Save loaded", save_loaded],
		["Autosave interval: 300 seconds", is_equal_approx(SaveManager.autosave_timer.wait_time, 300.0)],
		["Autosave callback", autosave_callback_saved],
		["Input actions configured", InputActions.has_required_actions()],
	]
	var lines: PackedStringArray = []
	for check in checks:
		lines.append("%s  %s" % ["PASS" if check[1] else "FAIL", check[0]])
	status_label.text = "\n".join(lines)
