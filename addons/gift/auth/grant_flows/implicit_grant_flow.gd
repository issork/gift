class_name ImplicitGrantFlow
extends RedirectingFlow

# Get an OAuth token from Twitch. Returns null if authentication failed.
func login(client_id : String, scopes : PackedStringArray, force_verify : bool = false) -> UserAccessToken:
	start_tcp_server()
	OS.shell_open("https://id.twitch.tv/oauth2/authorize?response_type=token&client_id=%s&force_verify=%s&redirect_uri=%s&scope=%s" % [client_id, "true" if force_verify else "false", redirect_url, " ".join(scopes)].map(func (a : String): return a.uri_encode()))
	print("Waiting for user to login.")
	var token_data : Dictionary = await(token_received)
	server.stop()
	if (!token_data.is_empty()):
		var token : UserAccessToken = UserAccessToken.new(token_data, client_id)
		token.fresh = true
		return token
	return null

func poll() -> void:
	if (!peer):
		peer = _create_peer()
		if (peer && peer.get_status() == StreamPeerTCP.STATUS_CONNECTED):
			_poll_peer()
	elif (peer.get_status() == StreamPeerTCP.STATUS_CONNECTED):
		_poll_peer()

func _handle_empty_response() -> void:
	send_response("200 OK", "<html><script>window.location = window.location.toString().replace('#','?');</script><head><title>Twitch Login</title></head></html>".to_utf8_buffer())

func _handle_success(data : Dictionary) -> void:
	super._handle_success(data)
	token_received.emit(data)

func _handle_error(data : Dictionary) -> void:
	super._handle_error(data)
	token_received.emit({})
