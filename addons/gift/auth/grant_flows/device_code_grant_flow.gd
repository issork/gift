class_name DeviceCodeGrantFlow
extends TwitchOAuthFlow

signal http_connected
signal response_received

var http_client : HTTPClient = HTTPClient.new()
var chunks : PackedByteArray = PackedByteArray()
var p_signal : Signal

func _init(poll_signal : Signal = Engine.get_main_loop().process_frame) -> void:
	poll_signal.connect(poll)
	p_signal = poll_signal

# https://dev.twitch.tv/docs/authentication/getting-tokens-oauth/#starting-the-dcf-flow-for-your-user
func request_login(client_id : String, scopes : PackedStringArray) -> Dictionary:
	http_client.connect_to_host("https://id.twitch.tv", -1, TLSOptions.client())
	await(http_connected)
	http_client.request(HTTPClient.METHOD_POST, "/oauth2/device", ["Content-Type: application/x-www-form-urlencoded"], "client_id=%s&scopes=%s" % [client_id, " ".join(scopes).uri_encode()])
	return await(response_received)

func poll() -> void:
	if (http_client != null):
		http_client.poll()
		if (http_client.get_status() == HTTPClient.STATUS_CONNECTED):
			http_connected.emit()
			if (!chunks.is_empty()):
				var response = chunks.get_string_from_utf8()
				response_received.emit(JSON.parse_string(response))
				chunks.clear()
		elif (http_client.get_status() == HTTPClient.STATUS_BODY):
			chunks += http_client.read_response_body_chunk()

func login(client_id : String, scopes : PackedStringArray, device_code : String) -> UserAccessToken:
	var response : Dictionary = {}
	while (response.is_empty() || (response.has("status") && response["status"] == 400)):
		http_client.request(HTTPClient.METHOD_POST, "/oauth2/token", ["Content-Type: application/x-www-form-urlencoded"], "location=%s&client_id=%s&scopes=%s&device_code=%s&grant_type=%s" % ["https://id.twitch.tv/oauth2/token", client_id, " ".join(scopes).uri_encode(), device_code, "urn:ietf:params:oauth:grant-type:device_code".uri_encode()])
		response = await(response_received)
		if (!response.is_empty() && response.has("message") && response["message"] != "authorization_pending"):
			print("Could not login using the device code: " + response["message"])
			return null
		await(p_signal)
	var token := RefreshableUserAccessToken.new(response, client_id)
	token.fresh = true
	return token
