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

func _handle_empty_response() -> void:
	super._handle_empty_response()
	auth_code_received.emit("")

func _handle_success(data : Dictionary) -> void:
	super._handle_success(data)
	auth_code_received.emit(data["code"])

func _handle_error(data : Dictionary) -> void:
	super._handle_error(data)
	auth_code_received.emit("")
