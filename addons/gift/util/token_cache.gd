class_name TokenCache
extends RefCounted

# Loads a token from file located at token_path. Returns null if the token was invalid.
static func load_token(token_path : String, scopes : Array[String] = []) -> TwitchToken:
	var token : TwitchToken = null
	if (FileAccess.file_exists(token_path)):
		var file : FileAccess = FileAccess.open(token_path, FileAccess.READ)
		var data : Dictionary = JSON.parse_string(file.get_as_text())
		if (data.has("scope")):
			var old_scopes = data["scope"]
			for scope in old_scopes:
				if (!scopes.has(scope)):
					return token
			if (data.has("refresh_token")):
				return RefreshableUserAccessToken.new(data, data["client_id"])
			else:
				return UserAccessToken.new(data, data["client_id"])
		else:
			return AppAccessToken.new(data, data["client_id"])
	return token

# Stores a token in a file located at token_path. The files contents will be overwritten.
static func save_token(token_path : String, token : TwitchToken) -> void:
	DirAccess.make_dir_recursive_absolute(token_path.get_base_dir())
	var file : FileAccess = FileAccess.open(token_path, FileAccess.WRITE)
	var data : Dictionary = {}
	data["client_id"] = token.last_client_id
	data["access_token"] = token.token
	if (token is UserAccessToken):
		data["scope"] = token.scopes
	if (token is RefreshableUserAccessToken):
		data["refresh_token"] = token.refresh_token
		if (token.last_client_secret != ""):
			data["client_secret"] = token.last_client_secret
	file.store_string(JSON.stringify(data))
