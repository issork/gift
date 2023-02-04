extends Node
class_name Gift

# The underlying websocket sucessfully connected to Twitch.
signal twitch_connected
# The connection has been closed. Not emitted if twitch announced a reconnect.
signal twitch_disconnected
# The connection to Twitch failed.
signal twitch_unavailable
# Twitch requested the client to reconnect. (Will be unavailable until next connect)
signal twitch_reconnect
# The client tried to login. Returns true if successful, else false.
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
# Twitch's ping is about to be answered with a pong.
signal pong

## Messages starting with one of these symbols are handled as commands. '/' will be ignored, reserved by Twitch.
@export
var command_prefixes : Array[String] = ["!"]

## Time to wait in msec after each sent chat message. Values below ~310 might lead to a disconnect after 100 messages.
@export
var chat_timeout_ms : int = 320

## If true, caches emotes/badges to disk, so that they don't have to be redownloaded on every restart.
## This however means that they might not be updated if they change until you clear the cache.
@export
var disk_cache : bool = false

## Disk Cache has to be enbaled for this to work
@export_file
var disk_cache_path : String = "user://gift/cache"

# Twitch disconnects connected clients if too many chat messages are being sent. (At about 100 messages/30s).
# This queue makes sure messages aren't sent too quickly.
var chat_queue : Array[String] = []
var last_msg : int = Time.get_ticks_msec()
# Mapping of channels to their channel info, like available badges.
var channels : Dictionary = {}
# Last Userstate of the bot for channels. Contains <channel_name> -> <userstate_dictionary> entries.
var last_userstate : Dictionary = {}
# Dictionary of commands, contains <command key> -> <Callable> entries.
var commands : Dictionary = {}

var websocket : WebSocketPeer = WebSocketPeer.new()
var connected : bool = false
var user_regex : RegEx = RegEx.new()
var twitch_restarting : bool = false

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

#var image_cache : ImageCache

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

func _ready() -> void:
	if (disk_cache):
		for key in RequestType.keys():
			if (!DirAccess.dir_exists_absolute(disk_cache_path + "/" + key)):
				DirAccess.make_dir_recursive_absolute(disk_cache_path + "/" + key)

func connect_to_twitch() -> void:
	websocket.connect_to_url("wss://irc-ws.chat.twitch.tv:443")
	set_process(true)

func _process(delta : float) -> void:
	websocket.poll()
	var state := websocket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if (!connected):
				twitch_connected.emit()
				connected = true
				print_debug("Connected to Twitch.")
			while (websocket.get_available_packet_count()):
				data_received(websocket.get_packet())
			if (!chat_queue.is_empty() && (last_msg + chat_timeout_ms) <= Time.get_ticks_msec()):
				send(chat_queue.pop_front())
				last_msg = Time.get_ticks_msec()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if (!connected):
				twitch_unavailable.emit()
				print_debug("Could not connect to Twitch.")
			connected = false
			if(twitch_restarting):
				print_debug("Reconnecting to Twitch")
				twitch_reconnect.emit()
				connect_to_twitch()
				await twitch_connected
				for channel in channels.keys():
					join_channel(channel)
				twitch_restarting = false
			else:
				set_process(false)
				print_debug("Disconnected from Twitch.")
				twitch_disconnected.emit()
			print_debug("Connection closed! [%s]: %s"%[websocket.get_close_code(), websocket.get_close_reason()])

# Login using a oauth token.
# You will have to either get a oauth token yourself or use
# https://twitchapps.com/tokengen/
# to generate a token with custom scopes.
func authenticate_oauth(nick : String, token : String) -> void:
	send("PASS " + ("" if token.begins_with("oauth:") else "oauth:") + token, true)
	send("NICK " + nick.to_lower())

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
		chat_message.emit(SenderData.new(last_userstate[channels.keys()[0]]["display-name"], channel, last_userstate[channels.keys()[0]]), message)
	elif(keys.size() == 1):
		chat_queue.append("PRIVMSG #" + channels.keys()[0] + " :" + message + "\r\n")
		chat_message.emit(SenderData.new(last_userstate[channels.keys()[0]]["display-name"], channels.keys()[0], last_userstate[channels.keys()[0]]), message)
	else:
		print_debug("No channel specified.")

func whisper(message : String, target : String) -> void:
	chat("/w " + target + " " + message)

func get_emote(emote_id : String, scale : String = "1.0") -> Texture:
	var texture : Texture
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
			request.request("https://static-cdn.jtvnw.net/emoticons/v1/" + emote_id + "/" + scale, ["User-Agent: GIFT/2.0.0 (Godot Engine)","Accept: */*"])
			var data = await(request.request_completed)
			request.queue_free()
			var img : Image = Image.new()
			img.load_png_from_buffer(data[3])
			texture = ImageTexture.create_from_image(img)
			texture.take_over_path(filename)
		caches[RequestType.EMOTE][cachename] = texture
	return caches[RequestType.EMOTE][cachename]

func get_badge(badge_name : String, channel_id : String = "_global", scale : String = "1") -> Texture:
	var badge_data : PackedStringArray = badge_name.split("/", true, 1)
	var texture : Texture
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
					request.request(map[badge_data[0]]["versions"][badge_data[1]]["image_url_" + scale + "x"], ["User-Agent: GIFT/2.0.0 (Godot Engine)","Accept: */*"])
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
			request.request("https://badges.twitch.tv/v1/badges/" + ("global" if channel_id == "_global" else "channels/" + channel_id) + "/display", ["User-Agent: GIFT/2.0.0 (Godot Engine)","Accept: */*"])
			var data = await(request.request_completed)
			request.queue_free()
			var buffer : PackedByteArray = data[3]
			if !buffer.is_empty():
				caches[RequestType.BADGE_MAPPING][channel_id] = JSON.parse_string(buffer.get_string_from_utf8())["badge_sets"]
				if (disk_cache):
					var file : FileAccess = FileAccess.open(filename, FileAccess.WRITE)
					file.store_buffer(buffer)
			else:
				return {}
	return caches[RequestType.BADGE_MAPPING][channel_id]

func data_received(data) -> void:
	var messages : PackedStringArray = data.get_string_from_utf8().strip_edges(false).split("\r\n")
	var tags = {}
	for message in messages:
		if(message.begins_with("@")):
			var msg : PackedStringArray = message.split(" ", false, 1)
			message = msg[1]
			for tag in msg[0].split(";"):
				var pair = tag.split("=")
				tags[pair[0]] = pair[1]
		if(OS.is_debug_build()):
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
	if(message == ":tmi.twitch.tv NOTICE * :Login authentication failed" || message == ":tmi.twitch.tv NOTICE * :Login unsuccessful"):
		print_debug("Authentication failed.")
		login_attempt.emit(false)
		return
	if(message == "PING :tmi.twitch.tv"):
		send("PONG :tmi.twitch.tv")
		pong.emit()
		return
	var msg : PackedStringArray = message.split(" ", true, 3)
	match msg[1]:
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
		"USERSTATE":
			last_userstate[msg[2].right(-1)] = tags
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
