extends Node


var PORT = 4242

func _ready():
	Autoload.main_reference = self
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(remove_player)
	multiplayer.connected_to_server.connect(load_map_on_spawn)
	var mainmenu = preload("res://Scenes/UI/mainmenu.tscn")
	mainmenu = mainmenu.instantiate()
	add_child(mainmenu)
	

func start_hosting():
	# delete any multiplayer peer that might exist:
	multiplayer.multiplayer_peer = null
	# create new peer and set its host, then tell our multiplayer API to use it:
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	# get our multiplayer UID (as server this should always be "1" in Godot 4)
	var player_uid = multiplayer.get_unique_id()
	spawn_player(player_uid)
	Autoload.current_map_path = "hub.tscn"
	var new_map_load = load("res://Scenes/Maps/"+Autoload.current_map_path)
	var map_instance = new_map_load.instantiate()
	Autoload.current_map_reference = map_instance
	add_child(map_instance)

func start_joining(server):
	multiplayer.multiplayer_peer = null
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(server, PORT)
	multiplayer.multiplayer_peer = peer

func spawn_player(peer_id: int):
	if not multiplayer.is_server():
		return
	var new_player = preload("res://Scenes/Units/player.tscn").instantiate()
	new_player.name = str(peer_id)
	$players.add_child(new_player,true)
	

func remove_player(peer_id):
	print("remove_player triggered")
	var player = get_node_or_null("players/"+str(peer_id))
	if multiplayer.is_server() and player:
		player.queue_free()
	

##############################################################################################################################
# Map loading and unloading
# when spawning, join map that host is on
func load_map_on_spawn():
	rpc_id(1,"current_map_query",multiplayer.get_unique_id())
@rpc("any_peer")
func current_map_query(peer_id):
	rpc_id(peer_id,"current_map_reply",Autoload.current_map_path)
	return Autoload.current_map_path
@rpc("authority")
func current_map_reply(reply):
	var new_map_load = load("res://Scenes/Maps/"+reply)
	var map_instance = new_map_load.instantiate()
	Autoload.current_map_reference = map_instance
	add_child(map_instance)
	Autoload.current_map_path = "hub.tscn"

func swap_map_init(new_map):
	# if only one player, load map
	if get_tree().get_nodes_in_group("playergroup").size() == 1:
		swap_map(new_map)
	# show popup to all players to accept map change
	# change map if all players agree
	swap_map(new_map)
	

@rpc("call_local")
func swap_map(new_map):
	if Autoload.current_map_reference != null:
		Autoload.current_map_reference.queue_free()
	var new_map_load = load(new_map)
	var map_instance = new_map_load.instantiate()
	Autoload.current_map_reference = map_instance
	add_child(map_instance)
	# get spawn location on loaded map
	var spawnlocation = Autoload.current_map_reference.get_node("spawnlocation").position
	Autoload.player_reference.set_position(spawnlocation)
	

##############################################################################################################################
# exit game (in minecraft)
func exit_game():
	get_tree().quit()
