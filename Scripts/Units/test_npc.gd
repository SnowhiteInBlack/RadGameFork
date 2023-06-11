extends CharacterBody3D

var stats_base: Dictionary
@export var stats_curr: Dictionary
var spells_base: Dictionary
@export var spells_curr: Dictionary

func _ready():
	# load stats and spells
	var file = "res://Data/db_stats.json"
	var json_dict = JSON.parse_string(FileAccess.get_file_as_string(file))
	stats_base = json_dict["2"]
	stats_curr = stats_base
	file = "res://Data/db_spells.json"
	json_dict = JSON.parse_string(FileAccess.get_file_as_string(file))
	spells_base["2"] = json_dict["2"]
	spells_curr = spells_base

func _process(_delta):
	if stats_curr["health_current"] < stats_curr["health_max"]/2:
		Combat.combat_event(spells_curr["2"],self,self)
