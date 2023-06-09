extends Node
class_name Gift

# The underlying websocket sucessfully connected to Twitch IRC.
signal twitch_connected
# The connection has been closed. Not emitted if Twitch IRC announced a reconnect.
signal twitch_disconnected
# The connection to Twitch IRC failed.
signal twitch_unavailable
# Twitch IRC requested the client to reconnect. (Will be unavailable until next connect)
signal twitch_reconnect
# User token from Twitch has been fetched.
signal user_token_received(token_data)
# User token is valid.
signal user_token_valid
# User token is no longer valid.
signal user_token_invalid
# The client tried to login to Twitch IRC. Returns true if successful, else false.
signal login_attempt(success)
# User sent a message in chat.
signal chat_message(sender_data, message)
# User sent a whisper message.
signal whisper_message(sender_data, message)
# Unhandled data passed through
signal unhandled_message(message, tags)
# A command has been called with invalid arg count
signal cmd_invalid_argcount(cmd_name, sender_data, cmd_data, arg_ary)
# A command has been called with insufficient permissions
signal cmd_no_permission(cmd_name, sender_data, cmd_data, arg_ary)
# Twitch IRC ping is about to be answered with a pong.
signal pong


# The underlying websocket sucessfully connected to Twitch EventSub.
signal events_connected
# The connection to Twitch EventSub failed.
signal events_unavailable
# The underlying websocket disconnected from Twitch EventSub.
signal events_disconnected
# The id has been received from the welcome message.
signal events_id(id)
# Twitch directed the bot to reconnect to a different URL
signal events_reconnect
# Twitch revoked a event subscription
signal events_revoked(event, reason)

# Refer to https://dev.twitch.tv/docs/eventsub/eventsub-reference/ data contained in the data dictionary.
signal event(type, data)

@export_category("IRC")

## Messages starting with one of these symbols are handled as commands. '/' will be ignored, reserved by Twitch.
@export var command_prefixes : Array[String] = ["!"]

## Time to wait in msec after each sent chat message. Values below ~310 might lead to a disconnect after 100 messages.
@export var chat_timeout_ms : int = 320

## Scopes to request for the token. Look at https://dev.twitch.tv/docs/authentication/scopes/ for a list of all available scopes.
@export var scopes : Array[String] = ["chat:edit", "chat:read"]

@export_category("Emotes/Badges")

## If true, caches emotes/badges to disk, so that they don't have to be redownloaded on every restart.
## This however means that they might not be updated if they change until you clear the cache.
@export var disk_cache : bool = false

## Disk Cache has to be enbaled for this to work
@export_file var disk_cache_path : String = "user://gift/cache"

var client_id : String = ""
var client_secret : String = ""
var username : String = ""
var user_id : String = ""
var token : Dictionary = {}

# Twitch disconnects connected clients if too many chat messages are being sent. (At about 100 messages/30s).
# This queue makes sure messages aren't sent too quickly.
var chat_queue : Array[String] = []
var last_msg : int = Time.get_ticks_msec()
# Mapping of channels to their channel info, like available badges.
var channels : Dictionary = {}
# Last Userstate of the bot for channels. Contains <channel_name> -> <userstate_dictionary> entries.
var last_state : Dictionary = {}
# Dictionary of commands, contains <command key> -> <Callable> entries.
var commands : Dictionary = {}

var eventsub : WebSocketPeer
var eventsub_messages : Dictionary = {}
var eventsub_connected : bool = false
var eventsub_restarting : bool = false
var eventsub_reconnect_url : String = ""
var session_id : String = ""
var keepalive_timeout : int = 0
var last_keepalive : int = 0

var websocket : WebSocketPeer
var server : TCPServer = TCPServer.new()
var peer : StreamPeerTCP
var connected : bool = false
var user_regex : RegEx = RegEx.new()
var twitch_restarting : bool = false

const USER_AGENT : String = "User-Agent: GIFT/4.1.4 (Godot Engine)"

enum RequestType {
	EMOTE,
	BADGE,
	BADGE_MAPPING
}

var caches := {
	RequestType.EMOTE: {},
	RequestType.BADGE: {},
	RequestType.BADGE_MAPPING: {}
}

# Required permission to execute the command
enum PermissionFlag {
	EVERYONE = 0,
	VIP = 1,
	SUB = 2,
	MOD = 4,
	STREAMER = 8,
	# Mods and the streamer
	MOD_STREAMER = 12,
	# Everyone but regular viewers
	NON_REGULAR = 15
}

# Where the command should be accepted
enum WhereFlag {
	CHAT = 1,
	WHISPER = 2
}

func _init():
	user_regex.compile("(?<=!)[\\w]*(?=@)")
	if (disk_cache):
		for key in RequestType.keys():
			if (!DirAccess.dir_exists_absolute(disk_cache_path + "/" + key)):
				DirAccess.make_dir_recursive_absolute(disk_cache_path + "/" + key)

# Authenticate to authorize GIFT to use your account to process events and messages.
func authenticate(client_id, client_secret) -> void:
	self.client_id = client_id
	self.client_secret = client_secret
	print("Checking token...")
	if (FileAccess.file_exists("user://gift/auth/user_token")):
		var file : FileAccess = FileAccess.open_encrypted_with_pass("user://gift/auth/user_token", FileAccess.READ, client_secret)
		token = JSON.parse_string(file.get_as_text())
		if (token.has("scope") && scopes.size() != 0):
			if (scopes.size() != token["scope"].size()):
				get_token()
				token = await(user_token_received)
			else:
				for scope in scopes:
					if (!token["scope"].has(scope)):
						get_token()
						token = await(user_token_received)
		else:
			get_token()
			token = await(user_token_received)
	else:
		get_token()
		token = await(user_token_received)
	username = await(is_token_valid(token["access_token"]))
	while (username == ""):
		print("Token invalid.")
		get_token()
		token = await(user_token_received)
		username = await(is_token_valid(token["access_token"]))
	print("Token verified.")
	user_token_valid.emit()
	refresh_token()

# Gets a new auth token from Twitch.
func get_token() -> void:
	print("Fetching new token.")
	var scope = ""
	for i in scopes.size() - 1:
		scope += scopes[i]
		scope += " "
	if (scopes.size() > 0):
		scope += scopes[scopes.size() - 1]
	scope = scope.uri_encode()
	OS.shell_open("https://id.twitch.tv/oauth2/authorize
	?response_type=code
	&client_id=" + client_id +
	"&redirect_uri=http://localhost:18297
	&scope=" + scope)
	server.listen(18297)
	print("Waiting for user to login.")
	while(!peer):
		peer = server.take_connection()
		OS.delay_msec(100)
	while(peer.get_status() == peer.STATUS_CONNECTED):
		peer.poll()
		if (peer.get_available_bytes() > 0):
			var response = peer.get_utf8_string(peer.get_available_bytes())
			if (response == ""):
				print("Empty response. Check if your redirect URL is set to http://localhost:18297.")
				return
			var start : int = response.find("?")
			response = response.substr(start + 1, response.find(" ", start) - start)
			var data : Dictionary = {}
			for entry in response.split("&"):
				var pair = entry.split("=")
				data[pair[0]] = pair[1] if pair.size() > 0 else ""
			if (data.has("error")):
				var msg = "Error %s: %s" % [data["error"], data["error_description"]]
				print(msg)
				send_response(peer, "400 BAD REQUEST",  msg.to_utf8_buffer())
				peer.disconnect_from_host()
				break
			else:
				print("Success.")
				send_response(peer, "200 OK", "Success!".to_utf8_buffer())
				peer.disconnect_from_host()
				var request : HTTPRequest = HTTPRequest.new()
				add_child(request)
				request.request("https://id.twitch.tv/oauth2/token", [USER_AGENT, "Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST, "client_id=" + client_id + "&client_secret=" + client_secret + "&code=" + data["code"] + "&grant_type=authorization_code&redirect_uri=http://localhost:18297")
				var answer = await(request.request_completed)
				if (!DirAccess.dir_exists_absolute("user://gift/auth")):
					DirAccess.make_dir_recursive_absolute("user://gift/auth")
				var file : FileAccess = FileAccess.open_encrypted_with_pass("user://gift/auth/user_token", FileAccess.WRITE, client_secret)
				var token_data = answer[3].get_string_from_utf8()
				file.store_string(token_data)
				request.queue_free()
				user_token_received.emit(JSON.parse_string(token_data))
				break
		OS.delay_msec(100)

func send_response(peer : StreamPeer, response : String, body : PackedByteArray) -> void:
	peer.put_data(("HTTP/1.1 %s\r\n" % response).to_utf8_buffer())
	peer.put_data("Server: GIFT (Godot Engine)\r\n".to_utf8_buffer())
	peer.put_data(("Content-Length: %d\r\n"% body.size()).to_utf8_buffer())
	peer.put_data("Connection: close\r\n".to_utf8_buffer())
	peer.put_data("Content-Type: text/plain; charset=UTF-8\r\n".to_utf8_buffer())
	peer.put_data("\r\n".to_utf8_buffer())
	peer.put_data(body)

# If the token is valid, returns the username of the token bearer.
func is_token_valid(token : String) -> String:
	var request : HTTPRequest = HTTPRequest.new()
	add_child(request)
	request.request("https://id.twitch.tv/oauth2/validate", [USER_AGENT, "Authorization: OAuth " + token])
	var data = await(request.request_completed)
	request.queue_free()
	if (data[1] == 200):
		var payload : Dictionary = JSON.parse_string(data[3].get_string_from_utf8())
		user_id = payload["user_id"]
		return payload["login"]
	return ""

func refresh_token() -> void:
	await(get_tree().create_timer(3600).timeout)
	if (await(is_token_valid(token["access_token"])) == ""):
		user_token_invalid.emit()
		return
	else:
		refresh_token()
	var to_remove : Array[String] = []
	for entry in eventsub_messages.keys():
		if (Time.get_ticks_msec() - eventsub_messages[entry] > 600000):
			to_remove.append(entry)
	for n in to_remove:
		eventsub_messages.erase(n)

func _process(delta : float) -> void:
	if (websocket):
		websocket.poll()
		var state := websocket.get_ready_state()
		match state:
			WebSocketPeer.STATE_OPEN:
				if (!connected):
					twitch_connected.emit()
					connected = true
					print_debug("Connected to Twitch.")
				else:
					while (websocket.get_available_packet_count()):
						data_received(websocket.get_packet())
					if (!chat_queue.is_empty() && (last_msg + chat_timeout_ms) <= Time.get_ticks_msec()):
						send(chat_queue.pop_front())
						last_msg = Time.get_ticks_msec()
			WebSocketPeer.STATE_CLOSED:
				if (!connected):
					twitch_unavailable.emit()
					print_debug("Could not connect to Twitch.")
					websocket = null
				elif(twitch_restarting):
					print_debug("Reconnecting to Twitch...")
					twitch_reconnect.emit()
					connect_to_irc()
					await(twitch_connected)
					for channel in channels.keys():
						join_channel(channel)
					twitch_restarting = false
				else:
					print_debug("Disconnected from Twitch.")
					twitch_disconnected.emit()
					connected = false
					print_debug("Connection closed! [%s]: %s"%[websocket.get_close_code(), websocket.get_close_reason()])
	if (eventsub):
		eventsub.poll()
		var state := eventsub.get_ready_state()
		match state:
			WebSocketPeer.STATE_OPEN:
				if (!eventsub_connected):
					events_connected.emit()
					eventsub_connected = true
					print_debug("Connected to EventSub.")
				else:
					while (eventsub.get_available_packet_count()):
						process_event(eventsub.get_packet())
			WebSocketPeer.STATE_CLOSED:
				if(!eventsub_connected):
					print_debug("Could not connect to EventSub.")
					events_unavailable.emit()
					eventsub = null
				elif(eventsub_restarting):
					print_debug("Reconnecting to EventSub")
					eventsub.close()
					connect_to_eventsub(eventsub_reconnect_url)
					await(eventsub_connected)
					eventsub_restarting = false
				else:
					print_debug("Disconnected from EventSub.")
					events_disconnected.emit()
					eventsub_connected = false
					print_debug("Connection closed! [%s]: %s"%[websocket.get_close_code(), websocket.get_close_reason()])

func process_event(data : PackedByteArray) -> void:
	var msg : Dictionary = JSON.parse_string(data.get_string_from_utf8())
	if (eventsub_messages.has(msg["metadata"]["message_id"])):
		return
	eventsub_messages[msg["metadata"]["message_id"]] = Time.get_ticks_msec()
	var payload : Dictionary = msg["payload"]
	last_keepalive = Time.get_ticks_msec()
	match msg["metadata"]["message_type"]:
		"session_welcome":
			session_id = payload["session"]["id"]
			keepalive_timeout = payload["session"]["keepalive_timeout_seconds"]
			events_id.emit(session_id)
		"session_keepalive":
			if (payload.has("session")):
				keepalive_timeout = payload["session"]["keepalive_timeout_seconds"]
		"session_reconnect":
			eventsub_restarting = true
			eventsub_reconnect_url = payload["session"]["reconnect_url"]
			events_reconnect.emit()
		"revocation":
			events_revoked.emit(payload["subscription"]["type"], payload["subscription"]["status"])
		"notification":
			var event_data : Dictionary = payload["event"]
			event.emit(payload["subscription"]["type"], event_data)

# Connect to Twitch IRC. Make sure to authenticate first.
func connect_to_irc() -> bool:
	websocket = WebSocketPeer.new()
	websocket.connect_to_url("wss://irc-ws.chat.twitch.tv:443")
	print("Connecting to Twitch IRC.")
	await(twitch_connected)
	send("PASS oauth:%s" % [token["access_token"]], true)
	send("NICK " + username.to_lower())
	var success = await(login_attempt)
	if (success):
		connected = true
	return success

# Connect to Twitch EventSub. Make sure to authenticate first.
func connect_to_eventsub(url : String = "wss://eventsub.wss.twitch.tv/ws") -> void:
	eventsub = WebSocketPeer.new()
	eventsub.connect_to_url(url)
	print("Connecting to Twitch EventSub.")
	await(events_id)
	events_connected.emit()

# Refer to https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/ for details on
# which API versions are available and which conditions are required.
func subscribe_event(event_name : String, version : int, conditions : Dictionary) -> void:
	var data : Dictionary = {}
	data["type"] = event_name
	data["version"] = str(version)
	data["condition"] = conditions
	data["transport"] = {
		"method":"websocket",
		"session_id":session_id
	}
	var request : HTTPRequest = HTTPRequest.new()
	add_child(request)
	request.request("https://api.twitch.tv/helix/eventsub/subscriptions", [USER_AGENT, "Authorization: Bearer " + token["access_token"], "Client-Id:" + client_id, "Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(data))
	var reply : Array = await(request.request_completed)
	request.queue_free()
	var response : Dictionary = JSON.parse_string(reply[3].get_string_from_utf8())
	if (response.has("error")):
		print("Subscription failed for event '%s'. Error %s (%s): %s" % [event_name, response["status"], response["error"], response["message"]])
		return
	print("Now listening to '%s' events." % event_name)

# Request capabilities from twitch.
func request_caps(caps : String = "twitch.tv/commands twitch.tv/tags twitch.tv/membership") -> void:
	send("CAP REQ :" + caps)

# Sends a String to Twitch.
func send(text : String, token : bool = false) -> void:
	websocket.send_text(text)
	if(OS.is_debug_build()):
		if(!token):
			print("< " + text.strip_edges(false))
		else:
			print("< PASS oauth:******************************")

# Sends a chat message to a channel. Defaults to the only connected channel.
func chat(message : String, channel : String = ""):
	var keys : Array = channels.keys()
	if(channel != ""):
		if (channel.begins_with("#")):
			channel = channel.right(-1)
		chat_queue.append("PRIVMSG #" + channel + " :" + message + "\r\n")
		chat_message.emit(SenderData.new(last_state[channels.keys()[0]]["display-name"], channel, last_state[channels.keys()[0]]), message)
	elif(keys.size() == 1):
		chat_queue.append("PRIVMSG #" + channels.keys()[0] + " :" + message + "\r\n")
		chat_message.emit(SenderData.new(last_state[channels.keys()[0]]["display-name"], channels.keys()[0], last_state[channels.keys()[0]]), message)
	else:
		print_debug("No channel specified.")

# Send a whisper message to a user by username. Returns a empty dictionary on success. If it failed, "status" will be present in the Dictionary.
func whisper(message : String, target : String) -> Dictionary:
	var user_data : Dictionary = await(user_data_by_name(target))
	if (user_data.has("status")):
		return user_data
	var response : int = await(whisper_by_uid(message, user_data["id"]))
	if (response != HTTPClient.RESPONSE_NO_CONTENT):
		return {"status": response}
	return {}

# Send a whisper message to a user by UID. Returns the response code.
func whisper_by_uid(message : String, target_id : String) -> int:
	var request : HTTPRequest = HTTPRequest.new()
	add_child(request)
	request.request("https://api.twitch.tv/helix/whispers", [USER_AGENT, "Authorization: Bearer " + token["access_token"], "Client-Id:" + client_id, "Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"from_user_id": user_id, "to_user_id": target_id, "message": message}))
	var reply : Array = await(request.request_completed)
	request.queue_free()
	if (reply[1] != HTTPClient.RESPONSE_NO_CONTENT):
		print("Error sending the whisper: " + reply[3].get_string_from_utf8())
	return reply[0]

# Returns the response as Dictionary. If it failed, "error" will be present in the Dictionary.
func user_data_by_name(username : String) -> Dictionary:
	var request : HTTPRequest = HTTPRequest.new()
	add_child(request)
	request.request("https://api.twitch.tv/helix/users?login=" + username, [USER_AGENT, "Authorization: Bearer " + token["access_token"], "Client-Id:" + client_id, "Content-Type: application/json"], HTTPClient.METHOD_GET)
	var reply : Array = await(request.request_completed)
	var response : Dictionary = JSON.parse_string(reply[3].get_string_from_utf8())
	request.queue_free()
	if (response.has("error")):
		print("Error fetching user data: " + reply[3].get_string_from_utf8())
		return response
	else:
		return response["data"][0]

func get_emote(emote_id : String, scale : String = "1.0") -> Texture2D:
	var texture : Texture2D
	var cachename : String = emote_id + "_" + scale
	var filename : String = disk_cache_path + "/" + RequestType.keys()[RequestType.EMOTE] + "/" + cachename + ".png"
	if !caches[RequestType.EMOTE].has(cachename):
		if (disk_cache && FileAccess.file_exists(filename)):
			texture = ImageTexture.new()
			var img : Image = Image.new()
			img.load_png_from_buffer(FileAccess.get_file_as_bytes(filename))
			texture.create_from_image(img)
		else:
			var request : HTTPRequest = HTTPRequest.new()
			add_child(request)
			request.request("https://static-cdn.jtvnw.net/emoticons/v1/" + emote_id + "/" + scale, [USER_AGENT,"Accept: */*"])
			var data = await(request.request_completed)
			request.queue_free()
			var img : Image = Image.new()
			img.load_png_from_buffer(data[3])
			texture = ImageTexture.create_from_image(img)
			texture.take_over_path(filename)
			if (disk_cache):
				DirAccess.make_dir_recursive_absolute(filename.get_base_dir())
				texture.get_image().save_png(filename)
		caches[RequestType.EMOTE][cachename] = texture
	return caches[RequestType.EMOTE][cachename]

func get_badge(badge_name : String, channel_id : String = "_global", scale : String = "1") -> Texture2D:
	var badge_data : PackedStringArray = badge_name.split("/", true, 1)
	var texture : Texture2D
	var cachename = badge_data[0] + "_" + badge_data[1] + "_" + scale
	var filename : String = disk_cache_path + "/" + RequestType.keys()[RequestType.BADGE] + "/" + channel_id + "/" + cachename + ".png"
	if (!caches[RequestType.BADGE].has(channel_id)):
		caches[RequestType.BADGE][channel_id] = {}
	if (!caches[RequestType.BADGE][channel_id].has(cachename)):
		if (disk_cache && FileAccess.file_exists(filename)):
			var img : Image = Image.new()
			img.load_png_from_buffer(FileAccess.get_file_as_bytes(filename))
			texture = ImageTexture.create_from_image(img)
			texture.take_over_path(filename)
		else:
			var map : Dictionary = caches[RequestType.BADGE_MAPPING].get(channel_id, await(get_badge_mapping(channel_id)))
			if (!map.is_empty()):
				if(map.has(badge_data[0])):
					var request : HTTPRequest = HTTPRequest.new()
					add_child(request)
					request.request(map[badge_data[0]]["versions"][badge_data[1]]["image_url_" + scale + "x"], [USER_AGENT,"Accept: */*"])
					var data = await(request.request_completed)
					var img : Image = Image.new()
					img.load_png_from_buffer(data[3])
					texture = ImageTexture.create_from_image(img)
					texture.take_over_path(filename)
					request.queue_free()
				elif channel_id != "_global":
					return await(get_badge(badge_name, "_global", scale))
			elif (channel_id != "_global"):
				return await(get_badge(badge_name, "_global", scale))
			if (disk_cache):
				DirAccess.make_dir_recursive_absolute(filename.get_base_dir())
				texture.get_image().save_png(filename)
		texture.take_over_path(filename)
		caches[RequestType.BADGE][channel_id][cachename] = texture
	return caches[RequestType.BADGE][channel_id][cachename]

func get_badge_mapping(channel_id : String = "_global") -> Dictionary:
	if !caches[RequestType.BADGE_MAPPING].has(channel_id):
		var filename : String = disk_cache_path + "/" + RequestType.keys()[RequestType.BADGE_MAPPING] + "/" + channel_id + ".json"
		if (disk_cache && FileAccess.file_exists(filename)):
			caches[RequestType.BADGE_MAPPING][channel_id] = JSON.parse_string(FileAccess.get_file_as_string(filename))["badge_sets"]
		else:
			var request : HTTPRequest = HTTPRequest.new()
			add_child(request)
			request.request("https://api.twitch.tv/helix/chat/badges" + ("/global" if channel_id == "_global" else "?broadcaster_id=" + channel_id), [USER_AGENT, "Authorization: Bearer " + token["access_token"], "Client-Id:" + client_id, "Content-Type: application/json"], HTTPClient.METHOD_GET)
			var reply : Array = await(request.request_completed)
			var response : Dictionary = JSON.parse_string(reply[3].get_string_from_utf8())
			var mappings : Dictionary = {}
			for entry in response["data"]:
				if (!mappings.has(entry["set_id"])):
					mappings[entry["set_id"]] = {"versions": {}}
				for version in entry["versions"]:
					mappings[entry["set_id"]]["versions"][version["id"]] = version
			request.queue_free()
			if (reply[1] == HTTPClient.RESPONSE_OK):
				caches[RequestType.BADGE_MAPPING][channel_id] = mappings
				if (disk_cache):
					DirAccess.make_dir_recursive_absolute(filename.get_base_dir())
					var file : FileAccess = FileAccess.open(filename, FileAccess.WRITE)
					file.store_string(JSON.stringify(mappings))
			else:
				print("Could not retrieve badge mapping for channel_id " + channel_id + ".")
				return {}
	return caches[RequestType.BADGE_MAPPING][channel_id]

func data_received(data : PackedByteArray) -> void:
	var messages : PackedStringArray = data.get_string_from_utf8().strip_edges(false).split("\r\n")
	var tags = {}
	for message in messages:
		if(message.begins_with("@")):
			var msg : PackedStringArray = message.split(" ", false, 1)
			message = msg[1]
			for tag in msg[0].split(";"):
				var pair = tag.split("=")
				tags[pair[0]] = pair[1]
		if (OS.is_debug_build()):
			print("> " + message)
		handle_message(message, tags)

# Registers a command on an object with a func to call, similar to connect(signal, instance, func).
func add_command(cmd_name : String, callable : Callable, max_args : int = 0, min_args : int = 0, permission_level : int = PermissionFlag.EVERYONE, where : int = WhereFlag.CHAT) -> void:
	commands[cmd_name] = CommandData.new(callable, permission_level, max_args, min_args, where)

# Removes a single command or alias.
func remove_command(cmd_name : String) -> void:
	commands.erase(cmd_name)

# Removes a command and all associated aliases.
func purge_command(cmd_name : String) -> void:
	var to_remove = commands.get(cmd_name)
	if(to_remove):
		var remove_queue = []
		for command in commands.keys():
			if(commands[command].func_ref == to_remove.func_ref):
				remove_queue.append(command)
		for queued in remove_queue:
			commands.erase(queued)

func add_alias(cmd_name : String, alias : String) -> void:
	if(commands.has(cmd_name)):
		commands[alias] = commands.get(cmd_name)

func add_aliases(cmd_name : String, aliases : PackedStringArray) -> void:
	for alias in aliases:
		add_alias(cmd_name, alias)

func handle_message(message : String, tags : Dictionary) -> void:
	if(message == "PING :tmi.twitch.tv"):
		send("PONG :tmi.twitch.tv")
		pong.emit()
		return
	var msg : PackedStringArray = message.split(" ", true, 3)
	match msg[1]:
		"NOTICE":
			var info : String = msg[3].right(-1)
			if (info == "Login authentication failed" || info == "Login unsuccessful"):
				print_debug("Authentication failed.")
				login_attempt.emit(false)
			elif (info == "You don't have permission to perform that action"):
				print_debug("No permission. Check if access token is still valid. Aborting.")
				user_token_invalid.emit()
				set_process(false)
			else:
				unhandled_message.emit(message, tags)
		"001":
			print_debug("Authentication successful.")
			login_attempt.emit(true)
		"PRIVMSG":
			var sender_data : SenderData = SenderData.new(user_regex.search(msg[0]).get_string(), msg[2], tags)
			handle_command(sender_data, msg[3].split(" ", true, 1))
			chat_message.emit(sender_data, msg[3].right(-1))
		"WHISPER":
			var sender_data : SenderData = SenderData.new(user_regex.search(msg[0]).get_string(), msg[2], tags)
			handle_command(sender_data, msg[3].split(" ", true, 1), true)
			whisper_message.emit(sender_data, msg[3].right(-1))
		"RECONNECT":
			twitch_restarting = true
		"USERSTATE", "ROOMSTATE":
			var room = msg[2].right(-1)
			if (!last_state.has(room)):
				last_state[room] = tags
			else:
				for key in tags:
					last_state[room][key] = tags[key]
		_:
			unhandled_message.emit(message, tags)

func handle_command(sender_data : SenderData, msg : PackedStringArray, whisper : bool = false) -> void:
	if(command_prefixes.has(msg[0].substr(1, 1))):
		var command : String  = msg[0].right(-2)
		var cmd_data : CommandData = commands.get(command)
		if(cmd_data):
			if(whisper == true && cmd_data.where & WhereFlag.WHISPER != WhereFlag.WHISPER):
				return
			elif(whisper == false && cmd_data.where & WhereFlag.CHAT != WhereFlag.CHAT):
				return
			var args = "" if msg.size() == 1 else msg[1]
			var arg_ary : PackedStringArray = PackedStringArray() if args == "" else args.split(" ")
			if(arg_ary.size() > cmd_data.max_args && cmd_data.max_args != -1 || arg_ary.size() < cmd_data.min_args):
				cmd_invalid_argcount.emit(command, sender_data, cmd_data, arg_ary)
				print_debug("Invalid argcount!")
				return
			if(cmd_data.permission_level != 0):
				var user_perm_flags = get_perm_flag_from_tags(sender_data.tags)
				if(user_perm_flags & cmd_data.permission_level == 0):
					cmd_no_permission.emit(command, sender_data, cmd_data, arg_ary)
					print_debug("No Permission for command!")
					return
			if(arg_ary.size() == 0):
				cmd_data.func_ref.call(CommandInfo.new(sender_data, command, whisper))
			else:
				cmd_data.func_ref.call(CommandInfo.new(sender_data, command, whisper), arg_ary)

func get_perm_flag_from_tags(tags : Dictionary) -> int:
	var flag = 0
	var entry = tags.get("badges")
	if(entry):
		for badge in entry.split(","):
			if(badge.begins_with("vip")):
				flag += PermissionFlag.VIP
			if(badge.begins_with("broadcaster")):
				flag += PermissionFlag.STREAMER
	entry = tags.get("mod")
	if(entry):
		if(entry == "1"):
			flag += PermissionFlag.MOD
	entry = tags.get("subscriber")
	if(entry):
		if(entry == "1"):
			flag += PermissionFlag.SUB
	return flag

func join_channel(channel : String) -> void:
	var lower_channel : String = channel.to_lower()
	channels[lower_channel] = {}
	send("JOIN #" + lower_channel)

func leave_channel(channel : String) -> void:
	var lower_channel : String = channel.to_lower()
	send("PART #" + lower_channel)
	channels.erase(lower_channel)
