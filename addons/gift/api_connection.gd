class_name TwitchAPIConnection
extends RefCounted

signal received_response(response : String)
signal requested(request : GiftRequest)

var id_conn : TwitchIDConnection

var client : HTTPClient = HTTPClient.new()
var client_response : PackedByteArray = []
var mock : bool = false

var queue : Array = []
var current_request : GiftRequest

func _init(id_connection : TwitchIDConnection, twitch_cli_url : String = "") -> void:
	id_conn = id_connection
	id_conn.polled.connect(poll)
	client.connect_to_host("https://api.twitch.tv", -1, TLSOptions.client())

func poll() -> void:
	client.poll()
	if (!queue.is_empty() && client.get_status() == HTTPClient.STATUS_CONNECTED && current_request == null):
		current_request = queue.pop_front()
		requested.emit(current_request)
		client.request(current_request.method, "/mock" if mock else "/helix" + current_request.url, current_request.headers, current_request.body)
	if (client.get_status() == HTTPClient.STATUS_BODY):
		client_response += client.read_response_body_chunk()
	elif (!client_response.is_empty()):
		received_response.emit(client_response.get_string_from_utf8())
		client_response.clear()
		current_request = null

func request(method : int, url : String, headers : PackedStringArray, body : String = "") -> Dictionary:
	var request : GiftRequest = GiftRequest.new(method, url, headers, body)
	queue.append(request)
	var req : GiftRequest = await(requested)
	while (req != request):
		req = await(requested)
	var str_response : String = await(received_response)
	var response = JSON.parse_string(str_response) if !str_response.is_empty() else {}
	var response_code: int = client.get_response_code()
	match (response_code):
		200, 201, 202, 203, 204:
			return response
		_:
			if (response_code == 401):
				id_conn.token_invalid.emit()
				print("Token invalid. Attempting to fetch a new token.")
				if(await(id_conn.token_refreshed)):
					for i in headers.size():
						if (headers[i].begins_with("Authorization: Bearer")):
							headers[i] = "Authorization: Bearer %s" % id_conn.last_token.token
						elif (headers[i].begins_with("Client-Id:")):
							headers[i] = "Client-Id: %s" % id_conn.last_token.last_client_id
					return await(request(method, url, headers, body))
			var msg : String = "Error %s: %s while calling (%s). Please check the Twitch API documnetation." % [str(response_code), response.get("message", "without message"), url]
			return {}

func get_channel_chat_badges(broadcaster_id : String) -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id
	]
	return await(request(HTTPClient.METHOD_GET, "/chat/badges?broadcaster_id=%s" % broadcaster_id, headers))

func get_global_chat_badges() -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id
	]
	return await(request(HTTPClient.METHOD_GET, "/chat/badges/global", headers))

# Create a eventsub subscription. For the data required, refer to https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/
func create_eventsub_subscription(subscription_data : Dictionary) -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id,
		"Content-Type: application/json"
	]
	return await(request(HTTPClient.METHOD_POST, "/eventsub/subscriptions", headers, JSON.stringify(subscription_data)))

func get_users_by_id(ids : Array[String]) -> Dictionary:
	return await(get_users([], ids))

func get_users_by_name(names : Array[String]) -> Dictionary:
	return await(get_users(names, []))

func get_users(names : Array[String], ids : Array[String]) -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id
	]
	var response
	var params : String = ""
	if (!names.is_empty() || !ids.is_empty()):
		params = "?"
		if (names.size() > 0):
			params += "login=%s" % names.pop_back()
			while(names.size() > 0):
				params += "&login=%s" % names.pop_back()
		if (params.length() > 1):
			params += "&"
		if (ids.size() > 0):
			params += "id=%s" % ids.pop_back()
			while(ids.size() > 0):
				params += "&id=%s" % ids.pop_back()
	return await(request(HTTPClient.METHOD_GET, "/users/%s" % params, headers))

# Send a whisper from user_id to target_id with the specified message.
# Returns true on success or if the message was silently dropped, false on failure.
func send_whisper(from_user_id : String, to_user_id : String, message : String) -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id,
		"Content-Type: application/json"
	]
	var params: String = "?"
	params += "from_user_id=%s" % from_user_id
	params += "&to_user_id=%s" % to_user_id
	return await(request(HTTPClient.METHOD_POST, "/whispers" + params, headers, JSON.stringify({"message": message})))
