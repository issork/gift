class_name TwitchToken
extends RefCounted

var last_client_id : String = ""
var token : String
var expires_in : int
var fresh : bool = false

func _init(data : Dictionary, client_id : String, expires_in : int = 0) -> void:
	token = data["access_token"]
	last_client_id = client_id
