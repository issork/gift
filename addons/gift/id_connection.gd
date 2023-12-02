class_name TwitchIDConnection
extends RefCounted


signal polled
signal token_invalid
signal token_refreshed(success)

const ONE_HOUR_MS = 3600000

var last_token : TwitchToken

var id_client : HTTPClient = HTTPClient.new()
var id_client_response : PackedByteArray = []

var next_check : int = 0

func _init(token : TwitchToken) -> void:
	last_token = token
	if (last_token.fresh):
		next_check += ONE_HOUR_MS
	id_client.connect_to_host("https://id.twitch.tv", -1, TLSOptions.client())

func poll() -> void:
	if (id_client != null):
		id_client.poll()
		if (id_client.get_status() == HTTPClient.STATUS_CONNECTED):
			if (!id_client_response.is_empty()):
				var response = JSON.parse_string(id_client_response.get_string_from_utf8())
				if (response.has("status") && (response["status"] == 401 || response["status"] == 400)):
					print("Token is invalid. Aborting.")
					token_invalid.emit()
					token_refreshed.emit(false)
				else:
					last_token.token = response.get("access_token", last_token.token)
					last_token.expires_in = response.get("expires_in", last_token.expires_in)
					if last_token is RefreshableUserAccessToken:
						last_token.refresh_token = response.get("refresh_token", last_token.refresh_token)
						token_refreshed.emit(true)
					if last_token is AppAccessToken:
						token_refreshed.emit(true)
				id_client_response.clear()
			if (next_check <= Time.get_ticks_msec()):
				check_token()
				next_check += ONE_HOUR_MS
		elif (id_client.get_status() == HTTPClient.STATUS_BODY):
			id_client_response += id_client.read_response_body_chunk()
	polled.emit()

func check_token() -> void:
	id_client.request(HTTPClient.METHOD_GET, "/oauth2/validate", ["Authorization: OAuth %s" % last_token.token])
	print("Validating token...")

func refresh_token() -> void:
	if (last_token is RefreshableUserAccessToken):
		id_client.request(HTTPClient.METHOD_GET, "/oauth2/token", ["Content-Type: application/x-www-form-urlencoded"], "grant_type=refresh_token&refresh_token=%s&client_id=%s&client_secret=%s" % [last_token.refresh_token, last_token.last_client_id, last_token.last_client_secret])
	elif (last_token is UserAccessToken):
		var auth : ImplicitGrantFlow = ImplicitGrantFlow.new()
		polled.connect(auth.poll)
		var last_token = await(auth.login(last_token.last_client_id, last_token.scopes))
		token_refreshed.emit(true)
	else:
		id_client.request(HTTPClient.METHOD_POST, "/oauth2/token", ["Content-Type: application/x-www-form-urlencoded"], "client_id=%s&client_secret=%s&grant_type=client_credentials" % [last_token.client_id, last_token.client_secret])
	if (last_token == null):
		print("Please check if you have all required scopes.")
		token_refreshed.emit(false)
