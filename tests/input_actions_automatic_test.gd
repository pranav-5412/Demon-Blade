extends Node

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
    await get_tree().process_frame
    await _run()
    if failures.is_empty():
        print("INPUT_ACTIONS_AUTOMATIC_TEST: PASS (%d checks)" % checks)
        get_tree().quit(0)
    else:
        for failure in failures:
            push_error("TEST FAILURE: %s" % failure)
        print("INPUT_ACTIONS_AUTOMATIC_TEST: FAIL (%d failures / %d checks)" % [failures.size(), checks])
        get_tree().quit(1)

func _run() -> void:
    var input_actions = InputActions

    _check(input_actions.has_required_actions(), "has_required_actions returns true on default configuration")

    # Store existing events for the action we will remove
    var events = InputMap.action_get_events("move_forward")
    var deadzone = InputMap.action_get_deadzone("move_forward")

    # Remove it and test
    InputMap.erase_action("move_forward")
    _check(not input_actions.has_required_actions(), "has_required_actions returns false when an action is missing")

    # Restore the action
    InputMap.add_action("move_forward")
    InputMap.action_set_deadzone("move_forward", deadzone)
    for event in events:
        InputMap.action_add_event("move_forward", event)

    _check(input_actions.has_required_actions(), "has_required_actions returns true again after restoring the missing action")

func _check(condition: bool, label: String) -> void:
    checks += 1
    if condition:
        print("PASS: %s" % label)
    else:
        failures.append(label)
