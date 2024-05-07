class_name TwitchAPIConnection
extends RefCounted

signal received_response(response)

var id_conn : TwitchIDConnection

var client : HTTPClient = HTTPClient.new()
var client_response : PackedByteArray = []

func _init(id_connection : TwitchIDConnection) -> void:
	client.blocking_mode_enabled = true
	id_conn = id_connection
	id_conn.polled.connect(poll)
	client.connect_to_host("https://api.twitch.tv", -1, TLSOptions.client())

func poll() -> void:
	client.poll()
	if (client.get_status() == HTTPClient.STATUS_BODY):
		client_response += client.read_response_body_chunk()
	elif (!client_response.is_empty()):
		received_response.emit(client_response.get_string_from_utf8())
		client_response.clear()

func request(method : int, url : String, headers : PackedStringArray, body : String = "") -> Dictionary:
	client.request(method, url, headers, body)
	var response = await(received_response)
	match (client.get_response_code()):
		401:
			id_conn.token_invalid.emit()
			return {}
	return JSON.parse_string(response)

func get_channel_chat_badges(broadcaster_id : String) -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id
	]
	return await(request(HTTPClient.METHOD_GET,"/helix/chat/badges?broadcaster_id=%s" % broadcaster_id, headers))

func get_global_chat_badges() -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id
	]
	return await(request(HTTPClient.METHOD_GET,"/helix/chat/badges/global", headers))

# Create a eventsub subscription. For the data required, refer to https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/
func create_eventsub_subscription(subscription_data : Dictionary) -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id,
		"Content-Type: application/json"
	]
	var response = await(request(HTTPClient.METHOD_POST, "/helix/eventsub/subscriptions", headers, JSON.stringify(subscription_data)))
	match (client.get_response_code()):
		400:
			print("Bad Request! Check the data you specified.")
			return {}
		403:
			print("Forbidden! The access token is missing the required scopes.")
			return {}
		409:
			print("Conflict! A subscription already exists for the specified event type and condition combination.")
			return {}
		429:
			print("Too Many Requests! The request exceeds the number of subscriptions that you may create with the same combination of type and condition values.")
			return {}
	return response

func get_users_by_id(ids : Array[String]) -> Dictionary:
	return await(get_users([], ids))

func get_users_by_name(names : Array[String]) -> Dictionary:
	return await(get_users(names, []))

func get_users(names : Array[String], ids : Array[String]) -> Dictionary:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id
	]
	if (names.is_empty() && ids.is_empty()):
		return {}
	var params = "?"
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
	var response = await(request(HTTPClient.METHOD_GET,"/helix/users/%s" % params, headers))
	match (client.get_response_code()):
		400:
			id_conn.token_invalid.emit()
			return {}
	return response

# Send a whisper from user_id to target_id with the specified message.
# Returns true on success or if the message was silently dropped, false on failure.
func send_whisper(from_user_id : String, to_user_id : String, message : String) -> bool:
	var headers : PackedStringArray = [
		"Authorization: Bearer %s" % id_conn.last_token.token,
		"Client-Id: %s" % id_conn.last_token.last_client_id,
		"Content-Type: application/json"
	]
	var params: String = "?"
	params += "from_user_id=%s" % from_user_id
	params += "&to_user_id=%s" % to_user_id
	var response: Dictionary = await(
		request(
			HTTPClient.METHOD_POST,
			"/helix/whispers" + params,
			headers,
			JSON.stringify({"message": message})
		)
	)
	var response_code: int = client.get_response_code()
	match (response_code):
		# 200 is returned even if Twitch documentation says only 204
		200, 204:
			print("Success! The whisper was sent.")
			return true
		# Complete list of error codes according to Twitch documentation
		400, 401, 403, 404, 429:
			print("[Error (send_whisper)] %s - %s" % [response["status"], response["message"]])
			return false
		# Fallback for unknown response codes
		_:
			print("[Default (send_whisper)] %s " % response_code)
			return false
