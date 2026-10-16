extends Node

const ObjectiveTracker = preload("res://systems/objective_tracker.gd")

var failures: Array[String] = []
var checks := 0

var current_text_received: String = ""
var current_step_received: int = -1
var signal_emitted_count: int = 0

func _ready() -> void:
	await get_tree().process_frame
	await _run()
	if failures.is_empty():
		print("OBJECTIVE_TRACKER_TEST: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST FAILURE: %s" % failure)
		print("OBJECTIVE_TRACKER_TEST: FAIL (%d failures / %d checks)" % [failures.size(), checks])
		get_tree().quit(1)

func _on_objective_changed(text: String, step: int) -> void:
	current_text_received = text
	current_step_received = step
	signal_emitted_count += 1

func _run() -> void:
	var tracker = ObjectiveTracker.new()
	add_child(tracker)
	tracker.objective_changed.connect(_on_objective_changed)

	_check(tracker.current_step == 0, "Initial step is 0")
	_check(tracker.current_text == "", "Initial text is empty")

	tracker.set_objective(1, "Find the demon")

	_check(tracker.current_step == 1, "current_step updated correctly")
	_check(tracker.current_text == "Find the demon", "current_text updated correctly")
	_check(signal_emitted_count == 1, "Signal emitted exactly once")
	_check(current_step_received == 1, "Signal parameter step correct")
	_check(current_text_received == "Find the demon", "Signal parameter text correct")

	tracker.queue_free()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
