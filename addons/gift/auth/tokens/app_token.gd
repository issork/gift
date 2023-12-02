class_name AppAccessToken
extends TwitchToken

func _init(data : Dictionary, client_id) -> void:
	super._init(data, client_id, data["expires_in"])
