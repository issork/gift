class_name ClientCredentialsGrantFlow
extends TwitchOAuthFlow

signal http_connected

var http_client : HTTPClient
var chunks : PackedByteArray = PackedByteArray()

func poll() -> void:
	if (http_client != null):
		http_client.poll()
		if (http_client.get_status() == HTTPClient.STATUS_CONNECTED):
			http_connected.emit()
			if (!chunks.is_empty()):
				var response = chunks.get_string_from_utf8()
				token_received.emit(JSON.parse_string(response))
				chunks.clear()
				http_client = null
		elif (http_client.get_status() == HTTPClient.STATUS_BODY):
			chunks += http_client.read_response_body_chunk()

func login(client_id : String, client_secret : String) -> AppAccessToken:
	if (http_client == null):
		http_client = HTTPClient.new()
		http_client.connect_to_host("https://id.twitch.tv", -1, TLSOptions.client())
	await(http_connected)
	http_client.request(HTTPClient.METHOD_POST, "/oauth2/token", ["Content-Type: application/x-www-form-urlencoded"], "client_id=%s&client_secret=%s&grant_type=client_credentials" % [client_id, client_secret])
	var token : AppAccessToken =  AppAccessToken.new(await(token_received), client_id)
	token.fresh = true
	return token
