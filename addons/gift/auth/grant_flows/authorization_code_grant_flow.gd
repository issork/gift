class_name AuthorizationCodeGrantFlow
extends RedirectingFlow

signal auth_code_received(token)
signal http_connected

var http_client : HTTPClient
var chunks : PackedByteArray = PackedByteArray()

func get_authorization_code(client_id : String, scopes : PackedStringArray, force_verify : bool = false) -> String:
	start_tcp_server()
	OS.shell_open("https://id.twitch.tv/oauth2/authorize?response_type=code&client_id=%s&scope=%s&redirect_uri=%s&force_verify=%s" % [client_id, " ".join(scopes).uri_encode(), redirect_url, "true" if force_verify else "false"].map(func (a : String): return a.uri_encode()))
	print("Waiting for user to login.")
	var code : String = await(auth_code_received)
	server.stop()
	return code

func login(client_id : String, client_secret : String, auth_code : String = "", scopes : PackedStringArray = [], force_verify : bool = false) -> RefreshableUserAccessToken:
	if (auth_code == ""):
		auth_code = await(get_authorization_code(client_id, scopes, force_verify))
	if (http_client == null):
		http_client = HTTPClient.new()
		http_client.connect_to_host("https://id.twitch.tv", -1, TLSOptions.client())
	await(http_connected)
	http_client.request(HTTPClient.METHOD_POST, "/oauth2/token", ["Content-Type: application/x-www-form-urlencoded"], "client_id=%s&client_secret=%s&code=%s&grant_type=authorization_code&redirect_uri=%s" % [client_id, client_secret, auth_code, redirect_url])
	print("Using auth token to login.")
	var token : RefreshableUserAccessToken = RefreshableUserAccessToken.new(await(token_received), client_id, client_secret)
	token.fresh = true
	return token

func poll() -> void:
	if (server != null):
		super.poll()

func _process_response(response : String) -> void:
	if (response == ""):
		print("Empty response. Check if your redirect URL is set to %s." % redirect_url)
		return
	var start : int = response.find("?")
	if (start == -1):
		print ("Response from Twitch does not contain the required data.")
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
			print("Success.")
			send_response("200 OK", "<html><head><title>Twitch Login</title></head><body>Success!</body></html>".to_utf8_buffer())
			auth_code_received.emit(data["code"])
	peer.disconnect_from_host()
	peer = null
