class_name RefreshableUserAccessToken
extends UserAccessToken

var refresh_token : String
var last_client_secret : String

func _init(data : Dictionary, client_id : String, client_secret : String) -> void:
	super._init(data, client_id)
	refresh_token = data["refresh_token"]
	last_client_secret = client_secret
