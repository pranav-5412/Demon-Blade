class_name RotatingRoomController
extends Node3D

signal rotation_started(target_state: int)
signal rotation_finished(current_state: int)
signal drum_hook_requested(hook_name: StringName)

@export var rotation_duration := 0.85

var orientation_state := 0
var rotation_active := false
var visual_root: Node3D
var state_geometry: Node3D
var safe_anchor: Marker3D
var exit_bridge: MeshInstance3D
var exit_collision: CollisionShape3D
var route_open := false

func _ready() -> void:
	_build_room()
	_apply_state_geometry()

func rotate_room(quarter_turns: int) -> bool:
	if rotation_active:
		return false
	rotation_active = true
	var target_state := wrapi(orientation_state + quarter_turns, 0, 4)
	rotation_started.emit(target_state)
	drum_hook_requested.emit(&"drum_room_rotate")
	var target_angle := float(target_state * 90)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visual_root, "rotation_degrees:z", target_angle, rotation_duration)
	await tween.finished
	orientation_state = target_state
	_apply_state_geometry()
	rotation_active = false
	rotation_finished.emit(orientation_state)
	return true

func restore_state(saved_state: int, puzzle_complete: bool) -> void:
	orientation_state = clampi(saved_state, 0, 3)
	visual_root.rotation_degrees.z = float(orientation_state * 90)
	set_route_open(puzzle_complete)
	_apply_state_geometry()

func stabilize() -> void:
	rotation_active = false
	orientation_state = 0
	visual_root.rotation_degrees.z = 0.0
	_apply_state_geometry()

func set_route_open(value: bool) -> void:
	route_open = value
	if is_instance_valid(exit_bridge):
		exit_bridge.visible = value
	if is_instance_valid(exit_collision):
		exit_collision.disabled = not value

func get_safe_position() -> Vector3:
	return safe_anchor.global_position

func _apply_state_geometry() -> void:
	if not is_instance_valid(state_geometry):
		return
	var state_platforms := state_geometry.get_children()
	for index in state_platforms.size():
		var child := state_platforms[index] as Node3D
		child.visible = index == orientation_state
		var body := child.get_node_or_null("Body") as StaticBody3D
		if body != null:
			var collision := body.get_node("Collision") as CollisionShape3D
			collision.disabled = index != orientation_state

func _build_room() -> void:
	visual_root = Node3D.new()
	visual_root.name = "RotatingVisualRoot"
	add_child(visual_root)
	_add_visual_box(visual_root, "FloorPanel", Vector3(14, 0.5, 14), Vector3(0, -0.25, 0), Color(0.28, 0.2, 0.16))
	_add_visual_box(visual_root, "CeilingPanel", Vector3(14, 0.5, 14), Vector3(0, 7.75, 0), Color(0.16, 0.11, 0.1))
	_add_visual_box(visual_root, "WallLeft", Vector3(0.5, 8, 14), Vector3(-7, 3.75, 0), Color(0.22, 0.14, 0.11))
	_add_visual_box(visual_root, "WallRight", Vector3(0.5, 8, 14), Vector3(7, 3.75, 0), Color(0.22, 0.14, 0.11))
	_add_visual_box(visual_root, "WallMark", Vector3(3.0, 0.22, 0.8), Vector3(0, 0.08, -4.5), Color(0.75, 0.18, 0.08))
	state_geometry = Node3D.new()
	state_geometry.name = "WalkableStates"
	add_child(state_geometry)
	for state in 4:
		var root := Node3D.new()
		root.name = "State%d" % state
		state_geometry.add_child(root)
		var offset: Vector3 = [Vector3(0, 0, 0), Vector3(2.4, 0.35, 0), Vector3(0, 0.7, -1.8), Vector3(-2.4, 0.35, 0)][state]
		_add_walkable_box(root, "StateFloor", Vector3(12, 0.7, 12), offset + Vector3(0, -0.35, 0), Color(0.3 + state * 0.025, 0.22, 0.17))
	safe_anchor = Marker3D.new()
	safe_anchor.name = "SafeAnchor"
	safe_anchor.position = Vector3(0, 1.1, 1.5)
	add_child(safe_anchor)
	var bridge_root := Node3D.new()
	bridge_root.name = "PuzzleExitBridge"
	bridge_root.position = Vector3(0, 0, -8.5)
	add_child(bridge_root)
	exit_bridge = _add_visual_box(bridge_root, "Bridge", Vector3(4, 0.7, 8), Vector3.ZERO, Color(0.35, 0.25, 0.17))
	var body := StaticBody3D.new()
	body.name = "Body"
	bridge_root.add_child(body)
	exit_collision = CollisionShape3D.new()
	exit_collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 0.7, 8)
	exit_collision.shape = shape
	body.add_child(exit_collision)
	set_route_open(false)

func _add_visual_box(parent: Node, label: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	parent.add_child(visual)
	return visual

func _add_walkable_box(parent: Node, label: String, size: Vector3, position: Vector3, color: Color) -> void:
	_add_visual_box(parent, label, size, position, color)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.position = position
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
