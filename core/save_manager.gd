extends Node

const SAVE_PATH := "user://demonblade_save.json"
const AUTOSAVE_INTERVAL_SECONDS := 300.0

var autosave_timer: Timer

func _ready() -> void:
	autosave_timer = Timer.new()
	autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	autosave_timer.one_shot = false
	autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(autosave_timer)
	autosave_timer.start()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func create_new_save() -> bool:
	GameManager.new_game()
	return save_game()

func save_game() -> bool:
	if GameManager.save_data == null:
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open save file for writing: %s" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(GameManager.save_data.to_dictionary()))
	file.close()
	return true

func save_checkpoint() -> bool:
	return save_game()

func load_save() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	var parse_result := json.parse(file.get_as_text())
	file.close()
	if parse_result != OK or not json.data is Dictionary:
		push_warning("Save data was invalid; starting a new session.")
		GameManager.new_game()
		return false
	GameManager.apply_save_data(SaveData.from_dictionary(json.data))
	return true

func request_autosave() -> bool:
	if GameManager.can_autosave():
		return save_game()
	return false

func _on_autosave_timeout() -> void:
	request_autosave()
