class_name PartyCompanionFollow
extends Node3D

@export var player_path: NodePath
@export var party_path: NodePath
@export var follow_distance := 2.2
@export var side_spacing := 1.55
@export var catch_up_distance := 14.0

@onready var player: ThirdPersonPlayer = get_node(player_path)
@onready var party: PartyCharacterController = get_node(party_path)

var slots: Array[Node3D] = []
var companion_ids: Array[String] = []
var active_character_id := "tanjiro"
var follow_enabled := true

func _ready() -> void:
	for index in 2:
		var slot := _build_companion_slot(index)
		add_child(slot)
		slots.append(slot)
	active_character_id = party.current_character
	party.character_changed.connect(_on_character_changed)
	_refresh_companions()
	force_catch_up()

func _process(delta: float) -> void:
	if not follow_enabled:
		return
	var catch_up_distance_squared := catch_up_distance * catch_up_distance
	for index in slots.size():
		var slot := slots[index]
		var target := _target_position(index)
		if slot.global_position.distance_squared_to(target) > catch_up_distance_squared:
			slot.global_position = target
		else:
			slot.global_position = slot.global_position.lerp(target, minf(delta * 5.5, 1.0))
		var facing := player.global_position
		facing.y = slot.global_position.y
		if slot.global_position.distance_squared_to(facing) > 0.05:
			slot.look_at(facing, Vector3.UP)

func set_follow_enabled(value: bool) -> void:
	follow_enabled = value

func force_catch_up() -> void:
	for index in slots.size():
		slots[index].global_position = _target_position(index)

func get_companion_ids() -> Array[String]:
	return companion_ids.duplicate()

func _on_character_changed(character_id: String, _display_name: String) -> void:
	var previous := active_character_id
	active_character_id = character_id
	_refresh_companions(previous)
	force_catch_up()

func _refresh_companions(previous_character: String = "") -> void:
	var inactive: Array[String] = []
	if not previous_character.is_empty() and previous_character != active_character_id:
		inactive.append(previous_character)
	for character_id in ["tanjiro", "zenitsu", "inosuke"]:
		if character_id != active_character_id and character_id not in inactive:
			inactive.append(character_id)
	companion_ids = inactive
	for index in slots.size():
		_configure_slot(slots[index], inactive[index])

func _target_position(index: int) -> Vector3:
	var side := -side_spacing if index == 0 else side_spacing
	var stagger := follow_distance + index * 0.75
	var target := player.global_position + player.global_basis.x * side + player.global_basis.z * stagger
	target.y = _ground_height_at(target)
	return target

func _ground_height_at(position: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(position + Vector3(0, 22, 0), position + Vector3(0, -45, 0))
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit.get("position", position).y) if not hit.is_empty() else player.global_position.y - 1.0

func _build_companion_slot(index: int) -> Node3D:
	var slot := Node3D.new()
	slot.name = "CompanionSlot%d" % (index + 1)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.35
	body_mesh.height = 1.25
	body.mesh = body_mesh
	body.position = Vector3(0, 0.72, 0)
	slot.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.3
	head_mesh.height = 0.6
	head.mesh = head_mesh
	head.position = Vector3(0, 1.55, 0)
	slot.add_child(head)
	for blade_data in [["BladeLeft", -0.43, 18.0], ["BladeRight", 0.43, -18.0]]:
		var blade := MeshInstance3D.new()
		blade.name = str(blade_data[0])
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(0.07, 1.35, 0.1)
		blade.mesh = blade_mesh
		blade.position = Vector3(float(blade_data[1]), 0.92, 0)
		blade.rotation_degrees.z = float(blade_data[2])
		slot.add_child(blade)
	var label := Label3D.new()
	label.name = "Nameplate"
	label.position = Vector3(0, 2.2, 0)
	label.font_size = 32
	label.outline_size = 4
	slot.add_child(label)
	return slot

func _configure_slot(slot: Node3D, character_id: String) -> void:
	var profile: Dictionary = PartyCharacterController.PROFILES[character_id]
	_set_color(slot.get_node("Body") as MeshInstance3D, profile.color)
	_set_color(slot.get_node("Head") as MeshInstance3D, profile.head_color)
	var left := slot.get_node("BladeLeft") as MeshInstance3D
	var right := slot.get_node("BladeRight") as MeshInstance3D
	left.visible = true
	right.visible = character_id == "inosuke"
	_set_color(left, _blade_color(character_id))
	_set_color(right, _blade_color(character_id))
	(slot.get_node("Nameplate") as Label3D).text = str(profile.name)
	slot.set_meta("character_id", character_id)

func _set_color(mesh: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	mesh.material_override = material

func _blade_color(character_id: String) -> Color:
	match character_id:
		"zenitsu": return Color(1.0, 0.78, 0.16)
		"inosuke": return Color(0.68, 0.72, 0.74)
		_: return Color(0.72, 0.76, 0.82)
