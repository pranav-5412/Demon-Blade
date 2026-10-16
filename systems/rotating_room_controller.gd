class_name RotatingRoomController
extends Node3D

signal rotation_started(target_state: int)
signal rotation_finished(current_state: int)
signal drum_hook_requested(hook_name: StringName)

@export var rotation_duration := 0.85
@export var room_visual_name := "RotatingRoomA"
@export var room_variant := 0

var orientation_state := 0
var rotation_active := false
var visual_root: Node3D
var state_geometry: Node3D
var safe_anchor: Marker3D
var exit_bridge: MeshInstance3D
var exit_collision: CollisionShape3D
var route_open := false
var dust_root: Node3D

func _ready() -> void:
	_build_room()
	_apply_state_geometry()

func rotate_room(quarter_turns: int) -> bool:
	if rotation_active:
		return false
	rotation_active = true
	if is_instance_valid(dust_root):
		dust_root.visible = true
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
	if is_instance_valid(dust_root):
		dust_root.visible = false
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
		var active := index == orientation_state
		child.visible = active
		for collision_node in child.find_children("*", "CollisionShape3D", true, false):
			(collision_node as CollisionShape3D).disabled = not active

func _build_room() -> void:
	visual_root = Node3D.new()
	visual_root.name = room_visual_name
	add_child(visual_root)
	visual_root.set_meta("furnished_rotating_room", true)
	visual_root.set_meta("dimensions", Vector3(10, 4.5, 10))
	_build_architecture(visual_root)
	_build_props(visual_root)
	_build_state_geometry()
	_build_exit_bridge()

func _build_architecture(parent: Node) -> void:
	_add_visual_box(parent, "WoodenFloor", Vector3(10, 0.38, 10), Vector3(0, -0.19, 0), Color(0.38, 0.27, 0.17))
	_add_visual_box(parent, "PaperCeiling", Vector3(10, 0.28, 10), Vector3(0, 4.45, 0), Color(0.35, 0.3, 0.24))
	_add_visual_box(parent, "PanelWallLeft", Vector3(0.32, 4.5, 10), Vector3(-5, 2.25, 0), Color(0.5, 0.42, 0.31))
	_add_visual_box(parent, "PanelWallRight", Vector3(0.32, 4.5, 10), Vector3(5, 2.25, 0), Color(0.5, 0.42, 0.31))
	_add_door_wall(parent, "EntranceWall", 5.0)
	_add_door_wall(parent, "ExitWall", -5.0)
	for x_position in [-4.75, 4.75]:
		for z_position in [-4.75, 4.75]:
			_add_visual_box(parent, "CornerTimber", Vector3(0.38, 4.5, 0.38), Vector3(x_position, 2.25, z_position), Color(0.2, 0.075, 0.035))
	for beam_z in [-3.2, 0.0, 3.2]:
		_add_visual_box(parent, "CeilingBeam", Vector3(9.8, 0.32, 0.34), Vector3(0, 4.2, beam_z), Color(0.21, 0.075, 0.035))

func _build_props(parent: Node) -> void:
	if room_variant == 0:
		for mat_position in [Vector3(-2.2, 0.03, -1.4), Vector3(0.4, 0.03, -1.4), Vector3(-2.2, 0.03, 1.0), Vector3(0.4, 0.03, 1.0)]:
			_add_visual_box(parent, "TatamiMat", Vector3(2.25, 0.08, 1.85), mat_position, Color(0.52, 0.5, 0.29))
		_add_visual_box(parent, "WallShelf", Vector3(2.8, 0.2, 0.65), Vector3(-3.9, 2.2, 0), Color(0.28, 0.12, 0.055))
		_add_visual_box(parent, "BrokenCabinet", Vector3(1.1, 1.7, 0.7), Vector3(3.8, 0.85, 2.5), Color(0.3, 0.14, 0.06), Vector3(0.08, 0.18, 0.12))
	else:
		_add_visual_box(parent, "TiltedBookcase", Vector3(1.3, 3.2, 0.65), Vector3(-3.6, 1.6, 1.8), Color(0.28, 0.11, 0.05), Vector3(0.0, 0.0, 0.24))
		_add_visual_box(parent, "FallenScreen", Vector3(3.4, 1.65, 0.12), Vector3(1.4, 0.82, -2.1), Color(0.53, 0.43, 0.3), Vector3(0.0, 0.0, -0.38))
		_add_visual_box(parent, "RaisedPlatform", Vector3(3.0, 0.42, 2.4), Vector3(1.8, 0.21, 1.8), Color(0.36, 0.19, 0.09))
		_add_visual_box(parent, "TrapDrumRack", Vector3(2.0, 1.1, 0.55), Vector3(-1.8, 0.55, -2.6), Color(0.36, 0.08, 0.035))
	_add_drum_motif(parent, Vector3(0, 2.3, -4.78))
	_add_lantern(parent, Vector3(0, 3.65, 0))
	_build_dust_motes()

func _build_state_geometry() -> void:
	state_geometry = Node3D.new()
	state_geometry.name = "WalkableStates"
	add_child(state_geometry)
	for state in 4:
		var root := Node3D.new()
		root.name = "State%d" % state
		state_geometry.add_child(root)
		var offset: Vector3 = [Vector3(0, 0, 0), Vector3(1.4, 0.2, 0), Vector3(0, 0.45, -1.0), Vector3(-1.4, 0.2, 0)][state]
		_add_walkable_box(root, "StateFloor", Vector3(9.4, 0.45, 9.4), offset + Vector3(0, -0.225, 0), Color(0.34 + state * 0.025, 0.24, 0.16))
		_add_walkable_box(root, "StateLeftBoundary", Vector3(0.3, 4.3, 9.4), offset + Vector3(-4.7, 2.15, 0), Color(0.45, 0.36, 0.25))
		_add_walkable_box(root, "StateRightBoundary", Vector3(0.3, 4.3, 9.4), offset + Vector3(4.7, 2.15, 0), Color(0.45, 0.36, 0.25))
		if state > 0:
			_add_walkable_box(root, "OrientationStep", Vector3(3.2, 0.35, 2.0), offset + Vector3(0, 0.18, -3.1), Color(0.42, 0.25, 0.13))
	safe_anchor = Marker3D.new()
	safe_anchor.name = "SafeAnchor"
	safe_anchor.position = Vector3(0, 1.1, 1.5)
	add_child(safe_anchor)

func _build_exit_bridge() -> void:
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

func _add_door_wall(parent: Node, label: String, z_position: float) -> void:
	var panel_color := Color(0.52, 0.44, 0.33)
	var timber_color := Color(0.2, 0.075, 0.035)
	_add_visual_box(parent, "%sLeft" % label, Vector3(3.65, 4.5, 0.3), Vector3(-3.18, 2.25, z_position), panel_color)
	_add_visual_box(parent, "%sRight" % label, Vector3(3.65, 4.5, 0.3), Vector3(3.18, 2.25, z_position), panel_color)
	_add_visual_box(parent, "%sLintel" % label, Vector3(2.9, 0.35, 0.42), Vector3(0, 3.35, z_position), timber_color)
	_add_visual_box(parent, "%sPost" % label, Vector3(0.28, 3.4, 0.42), Vector3(-1.35, 1.7, z_position), timber_color)
	_add_visual_box(parent, "%sPost" % label, Vector3(0.28, 3.4, 0.42), Vector3(1.35, 1.7, z_position), timber_color)

func _add_drum_motif(parent: Node, position: Vector3) -> void:
	var motif := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.72
	mesh.bottom_radius = 0.72
	mesh.height = 0.16
	mesh.material = _make_material(Color(0.55, 0.07, 0.025), 0.85)
	motif.name = "OrientationDrumMark"
	motif.mesh = mesh
	motif.position = position
	motif.rotation_degrees.x = 90.0
	parent.add_child(motif)

func _add_lantern(parent: Node, position: Vector3) -> void:
	_add_visual_box(parent, "LanternGlow", Vector3(0.34, 0.5, 0.34), position, Color(1.0, 0.6, 0.23))
	var frame_color := Color(0.27, 0.08, 0.03)
	_add_visual_box(parent, "LanternTop", Vector3(0.58, 0.08, 0.58), position + Vector3(0, 0.34, 0), frame_color)
	_add_visual_box(parent, "LanternBottom", Vector3(0.58, 0.08, 0.58), position + Vector3(0, -0.34, 0), frame_color)
	for corner in [Vector3(-0.25, 0, -0.25), Vector3(0.25, 0, -0.25), Vector3(-0.25, 0, 0.25), Vector3(0.25, 0, 0.25)]:
		_add_visual_box(parent, "LanternPost", Vector3(0.06, 0.68, 0.06), position + corner, frame_color)
	var light := OmniLight3D.new()
	light.name = "WarmLanternLight"
	light.position = position
	light.light_color = Color(1.0, 0.48, 0.18)
	light.light_energy = 2.1
	light.omni_range = 7.0
	light.shadow_enabled = false
	parent.add_child(light)

func _build_dust_motes() -> void:
	dust_root = Node3D.new()
	dust_root.name = "RotationDust"
	dust_root.visible = false
	visual_root.add_child(dust_root)
	for index in 18:
		var mote := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.025 + float(index % 3) * 0.012
		mesh.height = mesh.radius * 2.0
		mesh.material = _make_material(Color(0.75, 0.58, 0.36), 0.55)
		mote.mesh = mesh
		mote.position = Vector3(-4.0 + float((index * 17) % 80) * 0.1, 0.35 + float((index * 29) % 34) * 0.1, -4.0 + float((index * 37) % 80) * 0.1)
		dust_root.add_child(mote)

func _add_visual_box(parent: Node, label: String, size: Vector3, position: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _make_material(color, 0.18)
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	visual.rotation = rotation
	parent.add_child(visual, true)
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

func _make_material(color: Color, emission_strength: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color * emission_strength
	return material
