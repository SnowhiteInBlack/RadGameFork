extends CharacterBody3D


@onready var player_cam = $camera_rotation/camera_arm/player_camera
@onready var synchronizer = $MultiplayerSynchronizer

var playermodel_reference = null

#const speed = 10.0
const jump_velocity = 4.5

# stats
var stats_base : Dictionary
var stats_curr : Dictionary
var aura_dict : Dictionary
var absorb_dict : Dictionary

# targeting vars
var space_state
var unit_selectedtarget = null
var unit_mouseover_target = null
var interactables_in_range = []
var current_interact_target = null

# other
var esc_level = 0

# states
var is_moving : bool = false
var is_dead : bool = false

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _enter_tree() -> void:
	# We need to set the authority before entering the tree, because by then,
	# we already have started sending data.
	if str(name).is_valid_int():
		var id := str(name).to_int()
		# Before ready, the variable `multiplayer_synchronizer` is not set yet
		$MultiplayerSynchronizer.set_multiplayer_authority(id)

func _ready():
	if not synchronizer.is_multiplayer_authority():
		return
	Autoload.player_reference = self
	player_cam.set_current(true)
	if multiplayer.is_server():
		set_model("res://Scenes/Units/knight_scene.tscn",multiplayer.get_unique_id())
	else:
		rpc_id(1,"set_model","res://Scenes/Units/knight_scene.tscn",multiplayer.get_unique_id())
	# load stats and spells
	var file = "res://Data/db_stats_player.json"
	var json_dict = JSON.parse_string(FileAccess.get_file_as_string(file))
	stats_base = json_dict["0"]
	stats_curr = stats_base.duplicate(true) # can't just assign regularly, since that only creates a new pointer to same dict
	stats_curr.erase("stats_add") # remove modifiers, as they are only needed in base
	stats_curr.erase("stats_mult")
	# load persistent ui features
	Autoload.player_ui_main_reference.load_persistent()
	Autoload.player_ui_main_reference.get_node("ui_persistent").playerframe_initialize()
	Autoload.player_ui_main_reference.get_node("ui_persistent").actionbars_initialize()
	# load spell scenes
	load_spell_scenes()
	# a bit of hackyhackfraudyfraud to test spells, assignment will implemented later
	$spells/spell_10.actionbar.append(Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_1"))
	Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_1").\
						assign_actionbar($spells.get_node("spell_10"))
	$spells/spell_12.actionbar.append(Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_2"))
	Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_2").\
						assign_actionbar($spells.get_node("spell_12"))
	$spells/spell_11.actionbar.append(Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_3"))
	Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_3").\
						assign_actionbar($spells.get_node("spell_11"))
	$spells/spell_13.actionbar.append(Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_4"))
	Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_4").\
						assign_actionbar($spells.get_node("spell_13"))
	$spells/spell_14.actionbar.append(Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_5"))
	Autoload.player_ui_main_reference.get_node("ui_persistent").get_node("actionbars").get_node("actionbar1").get_node("actionbar1_5").\
						assign_actionbar($spells.get_node("spell_14"))

func _input(event):
	if not synchronizer.is_multiplayer_authority():
		return
	if event.is_action_pressed("escape") and esc_level == 0:
		Autoload.player_ui_main_reference.esc_menu()
	if event.is_action_pressed("interact"):
		if current_interact_target != null:
			current_interact_target.interaction(self)

func _unhandled_input(event):
	#targeting
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		# targeting ray
		var result = targetray(event.position)
		targeting(result)

func _process(delta):
	# resource regen
	if stats_curr["resource_regen"] != 0:
		stats_curr["resource_current"] = max(min(stats_curr["resource_current"]+stats_curr["resource_regen"]*delta,stats_curr["resource_max"]),0)
	# interaction target sorting
	if interactables_in_range.size() > 0:
		var distance = 10000.
		var distance_new = 0.
		var old_interactable = null
		if is_instance_valid(current_interact_target):
			old_interactable = current_interact_target
		for interactable_nearby in interactables_in_range:
			distance_new = self.global_position.distance_to(interactable_nearby.global_position)
			if distance_new < distance:
				distance = distance_new
				current_interact_target = interactable_nearby
		if not old_interactable == current_interact_target:
			if is_instance_valid(old_interactable):
				old_interactable.hide_interact_popup()
		current_interact_target.show_interact_popup()

func _physics_process(delta):
	# targeting ray
	space_state = get_world_3d().direct_space_state
	if not synchronizer.is_multiplayer_authority(): 
		return
	# jumping
	if Input.is_action_just_pressed("jump") and is_on_floor():
		Autoload.playermodel_reference.get_node("AnimationPlayer").play("KayKit Animated Character|Jump")
		velocity.y = jump_velocity
	# apply gravity if in air
	if not is_on_floor():
		velocity.y -= gravity * delta
	# movement
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# unrotated direction vector
	var direction_ur = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# rotate direction vector using camera angle
	var direction = Vector3(cos(2*PI-$camera_rotation.rotation.y)*direction_ur.x - sin(2*PI-$camera_rotation.rotation.y)*direction_ur.z, 0, \
							sin(2*PI-$camera_rotation.rotation.y)*direction_ur.x + cos(2*PI-$camera_rotation.rotation.y)*direction_ur.z)
#	var speed = stats_curr["speed"]
	if direction:
		velocity.x = direction.x * stats_curr["speed"]
		velocity.z = direction.z * stats_curr["speed"]
	else:
		velocity.x = move_toward(velocity.x, 0, stats_curr["speed"])
		velocity.z = move_toward(velocity.z, 0, stats_curr["speed"])
	# turn character to match movement direction
	if direction != Vector3.ZERO:
		$pivot.look_at(position + direction, Vector3.UP)
	if velocity == Vector3.ZERO:
		is_moving = false
		# animation
		if Autoload.playermodel_reference != null:
			Autoload.playermodel_reference.get_node("AnimationPlayer").play("KayKit Animated Character|Idle")
	else:
		is_moving = true
		# animation
		if Autoload.playermodel_reference != null:
				Autoload.playermodel_reference.get_node("AnimationPlayer").play("KayKit Animated Character|Run")
	move_and_slide()

# set player model
@rpc("any_peer")
func set_model(model_name,peer_id):
	var playernode = $/root/main/players.find_child(str(peer_id),true,false)
	if playernode.get_child(0).get_child_count() > 0:
		for node in playernode.get_child(0).get_children():
			node.queue_free()
	var model = load(model_name).instantiate()
	playernode.get_child(0).add_child(model,true)
	
###################################################################################################
# target ray
func targetray(eventposition):
	var origin = player_cam
	var from = origin.project_ray_origin(eventposition)
	var to = from + origin.project_ray_normal(eventposition) * 1000
	var query = PhysicsRayQueryParameters3D.create(from,to)
	var result = space_state.intersect_ray(query)
	return result
	
func targeting(result) -> void:
	# unset target and return if no collider is hit (like when clicking the sky)
	if not result.has("collider"):
		unit_selectedtarget = null
		Autoload.player_ui_main_reference.targetframe_remove()
		return
	# set target if player, npc or hostile is hit by ray
	if result.collider.is_in_group("playergroup") or result.collider.is_in_group("npcgroup_targetable") or\
	result.collider.is_in_group("hostilegroup_targetable"):
		unit_selectedtarget = result.collider
		Autoload.player_ui_main_reference.targetframe_initialize()
	# unset target if no valid target is hit by ray
	else:
		unit_selectedtarget = null
		Autoload.player_ui_main_reference.targetframe_remove()
###################################################################################################
# set up spells, auras, absorbs
func load_spell_scenes() -> void:
	for spellid in stats_base["spell list"]:
		$spells.add_child(load("res://Scenes/Spells/spell_"+spellid+".tscn").instantiate())
func sort_absorbs():
	pass
###################################################################################################
# get spell target
func get_spell_target(spell):
	var spell_target = null
	var ray_result = null
	# set target to either mouseovered unit frame or ray collider
	if unit_mouseover_target != null:
		spell_target = unit_mouseover_target
	else:
		ray_result = targetray(get_viewport().get_mouse_position())
		# check if target ray result has a collider, and check if collider is a valid result
		if ray_result.has("collider") and (ray_result.collider.is_in_group("playergroup") or \
			ray_result.collider.is_in_group("npcgroup_targetable") or\
			ray_result.collider.is_in_group("hostilegroup_targetable")):
				spell_target = ray_result.collider
	# check legality of mouseover target
	if spell_target == null or not spell_target.is_in_group(spell["targetgroup"]):
		# illegal mouseover target, set target to selected target
		spell_target = unit_selectedtarget
		# check legality of selected target
		if spell_target == null or not spell_target.is_in_group(spell["targetgroup"]):
			# illegal selected target as well, cannot use spell, so return
			return "no_legal_target"
	# return legal target
	return spell_target

# check target and send combat event from action bar
func send_combat_event(spell) -> void:
	var spell_target = null
	var ray_result = null
	# set target to either mouseovered unit frame or ray collider
	if unit_mouseover_target != null:
		spell_target = unit_mouseover_target
	else:
		ray_result = targetray(get_viewport().get_mouse_position())
		# check if target ray result has a collider, and check if collider is a valid result
		if ray_result.has("collider") and (ray_result.collider.is_in_group("playergroup") or \
			ray_result.collider.is_in_group("npcgroup_targetable") or\
			ray_result.collider.is_in_group("hostilegroup_targetable")):
				spell_target = ray_result.collider
	# check legality of mouseover target
	if spell_target == null or not spell_target.is_in_group(spell["targetgroup"]):
		# illegal mouseover target, set target to selected target
		spell_target = unit_selectedtarget
		# check legality of selected target
		if spell_target == null or not spell_target.is_in_group(spell["targetgroup"]):
			# illegal selected target as well, cannot use spell, so return
			return
	# legal target found, either from mouseover or selected, so send combat event
	Combat.combat_event(spell,self,spell_target)
