class_name TwitchIRCConnection
extends RefCounted

signal connection_state_changed(state)
signal chat_message(sender_data, message)
signal whisper_message(sender_data, message)
signal channel_data_received(room)
signal login_attempt(success)

signal unhandled_message(message, tags)

enum ConnectionState {
	DISCONNECTED,
	CONNECTED,
	CONNECTION_FAILED,
	RECONNECTING
}

var connection_state : ConnectionState = ConnectionState.DISCONNECTED:
	set(new_state):
		connection_state = new_state
		connection_state_changed.emit(new_state)

var websocket : WebSocketPeer
# Timestamp of the last message sent.
var last_msg : int = Time.get_ticks_msec()
# Time to wait in msec after each sent chat message. Values below ~310 might lead to a disconnect after 100 messages.
var chat_timeout_ms : int = 320
# Twitch disconnects connected clients if too many chat messages are being sent. (At about 100 messages/30s).
# This queue makes sure messages aren't sent too quickly.
var chat_queue : Array[String] = []
# Mapping of channels to their channel info, like available badges.
var channels : Dictionary = {}
# Last Userstate of the bot for channels. Contains <channel_name> -> <userstate_dictionary> entries.
var last_state : Dictionary = {}
var user_regex : RegEx = RegEx.create_from_string("(?<=!)[\\w]*(?=@)")

var id : TwitchIDConnection

var last_username : String
var last_token : UserAccessToken
var last_caps : PackedStringArray

func _init(twitch_id_connection : TwitchIDConnection) -> void:
	id = twitch_id_connection
	id.polled.connect(poll)

# Connect to Twitch IRC. Returns true on success, false if connection fails.
func connect_to_irc(username : String) -> bool:
	last_username = username
	websocket = WebSocketPeer.new()
	websocket.connect_to_url("wss://irc-ws.chat.twitch.tv:443")
	print("Connecting to Twitch IRC.")
	if (await(connection_state_changed) != ConnectionState.CONNECTED):
		return false
	send("PASS oauth:%s" % id.last_token.token, true)
	send("NICK " + username.to_lower())
	if (await(login_attempt)):
		print("Connected.")
		return true
	return false

func poll() -> void:
	if (websocket != null && connection_state != ConnectionState.CONNECTION_FAILED && connection_state != ConnectionState.RECONNECTING):
		websocket.poll()
		var state := websocket.get_ready_state()
		match state:
			WebSocketPeer.STATE_OPEN:
				if (connection_state == ConnectionState.DISCONNECTED):
					connection_state = ConnectionState.CONNECTED
					print("Connected to Twitch.")
				else:
					while (websocket.get_available_packet_count()):
						data_received(websocket.get_packet())
					if (!chat_queue.is_empty() && (last_msg + chat_timeout_ms) <= Time.get_ticks_msec()):
						send(chat_queue.pop_front())
						last_msg = Time.get_ticks_msec()
			WebSocketPeer.STATE_CLOSED:
				if (connection_state == ConnectionState.DISCONNECTED):
					print("Could not connect to Twitch.")
					connection_state = ConnectionState.CONNECTION_FAILED
				elif(connection_state == ConnectionState.RECONNECTING):
					print("Reconnecting to Twitch...")
					await(reconnect())
				else:
					connection_state = ConnectionState.DISCONNECTED
					print("Disconnected from Twitch. [%s]: %s"%[websocket.get_close_code(), websocket.get_close_reason()])

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

# Sends a String to Twitch.
func send(text : String, token : bool = false) -> void:
	websocket.send_text(text)
	if(OS.is_debug_build()):
		if(!token):
			print("< " + text.strip_edges(false))
		else:
			print("< PASS oauth:******************************")

# Request capabilities from twitch.
func request_capabilities(caps : PackedStringArray = ["twitch.tv/commands", "twitch.tv/tags"]) -> void:
	last_caps = caps
	send("CAP REQ :" + " ".join(caps))

# Sends a chat message to a channel. Defaults to the only connected channel.
func chat(message : String, channel : String = ""):
	var keys : Array = channels.keys()
	if(channel != ""):
		if (channel.begins_with("#")):
			channel = channel.right(-1)
		chat_queue.append("PRIVMSG #" + channel + " :" + message + "\r\n")
		if (last_state.has(channel)):
			chat_message.emit(SenderData.new(last_state[channel]["display-name"], channel, last_state[channels.keys()[0]]), message)
	elif(keys.size() == 1):
		chat_queue.append("PRIVMSG #" + channels.keys()[0] + " :" + message + "\r\n")
		if (last_state.has(channels.keys()[0])):
			chat_message.emit(SenderData.new(last_state[channels.keys()[0]]["display-name"], channels.keys()[0], last_state[channels.keys()[0]]), message)
	else:
		print("No channel specified.")

func handle_message(message : String, tags : Dictionary) -> void:
	if(message == "PING :tmi.twitch.tv"):
		send("PONG :tmi.twitch.tv")
		return
	var msg : PackedStringArray = message.split(" ", true, 3)
	match msg[1]:
		"NOTICE":
			var info : String = msg[3].right(-1)
			if (info == "Login authentication failed" || info == "Login unsuccessful"):
				print("Authentication failed.")
				login_attempt.emit(false)
			elif (info == "You don't have permission to perform that action"):
				print("No permission. Attempting to obtain new token.")
				id.refresh_token()
				var success : bool = await(id.token_refreshed)
				if (!success):
					print("Please check if you have all required scopes.")
					websocket.close(1000, "Token became invalid.")
					return
				connection_state = ConnectionState.RECONNECTING
			else:
				unhandled_message.emit(message, tags)
		"001":
			print("Authentication successful.")
			login_attempt.emit(true)
		"PRIVMSG":
			var sender_data : SenderData = SenderData.new(user_regex.search(msg[0]).get_string(), msg[2], tags)
			chat_message.emit(sender_data, msg[3].right(-1))
		"WHISPER":
			var sender_data : SenderData = SenderData.new(user_regex.search(msg[0]).get_string(), msg[2], tags)
			whisper_message.emit(sender_data, msg[3].right(-1))
		"RECONNECT":
			connection_state = ConnectionState.RECONNECTING
		"USERSTATE", "ROOMSTATE":
			var room = msg[2].right(-1)
			if (!last_state.has(room)):
				last_state[room] = tags
				channel_data_received.emit(room)
			else:
				for key in tags:
					last_state[room][key] = tags[key]
		_:
			unhandled_message.emit(message, tags)

func join_channel(channel : String) -> void:
	var lower_channel : String = channel.to_lower()
	channels[lower_channel] = {}
	send("JOIN #" + lower_channel)

func leave_channel(channel : String) -> void:
	var lower_channel : String = channel.to_lower()
	send("PART #" + lower_channel)
	channels.erase(lower_channel)

func reconnect() -> void:
	if(await(connect_to_irc(last_username))):
		request_capabilities(last_caps)
		for channel in channels.keys():
			join_channel(channel)
		connection_state = ConnectionState.CONNECTED
