class_name UserAccessToken
extends TwitchToken

var scopes : PackedStringArray

func _init(data : Dictionary, client_id : String) -> void:
	super._init(data, client_id)
	scopes = data["scope"]
