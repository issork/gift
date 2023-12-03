class_name ImplicitGrantFlow
extends RedirectingFlow

# Get an OAuth token from Twitch. Returns null if authentication failed.
func login(client_id : String, scopes : PackedStringArray, force_verify : bool = false) -> UserAccessToken:
	start_tcp_server()
	OS.shell_open("https://id.twitch.tv/oauth2/authorize?response_type=token&client_id=%s&force_verify=%s&redirect_uri=%s&scope=%s" % [client_id, "true" if force_verify else "false", redirect_url, " ".join(scopes)].map(func (a : String): return a.uri_encode()))
	print("Waiting for user to login.")
	var token_data : Dictionary = await(token_received)
	server.stop()
	if (token_data != null):
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

func _process_response(response : String) -> void:
		if (response == ""):
			print("Empty response. Check if your redirect URL is set to %s." % redirect_url)
			return
		var start : int = response.substr(0, response.find("\n")).find("?")
		if (start == -1):
			send_response("200 OK", "<html><script>window.location = window.location.toString().replace('#','?');</script><head><title>Twitch Login</title></head></html>".to_utf8_buffer())
		else:
			response = response.substr(start + 1, response.find(" ", start) - start)
			var data : Dictionary = {}
			for entry in response.split("&"):
				var pair = entry.split("=")
				data[pair[0]] = pair[1] if pair.size() > 0 else ""
			if (data.has("error")):
				var msg = "Error %s: %s" % [data["error"], data["error_description"]]
				print(msg)
				send_response("400 BAD REQUEST",  msg.to_utf8_buffer())
			else:
				data["scope"] = data["scope"].uri_decode().split(" ")
				print("Success.")
				send_response("200 OK", "<html><head><title>Twitch Login</title></head><body>Success!</body></html>".to_utf8_buffer())
			token_received.emit(data)
		peer.disconnect_from_host()
		peer = null
