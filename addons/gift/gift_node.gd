extends Node
class_name Gift

# The underlying websocket sucessfully connected to twitch.
signal twitch_connected
# The connection has been closed. Not emitted if twitch announced a reconnect.
signal twitch_disconnected
# The connection to twitch failed.
signal twitch_unavailable
# Twitch requested the client to reconnect. (Will be unavailable until next connect)
signal twitch_reconnect
# The client tried to login. Returns true if successful, else false.
signal login_attempt(success)
# User sent a message in chat.
signal chat_message(sender_data, message, channel)
# User sent a whisper message.
signal whisper_message(sender_data, message, channel)
# Unhandled data passed through
signal unhandled_message(message, tags)
# A command has been called with invalid arg count
signal cmd_invalid_argcount(cmd_name, sender_data, cmd_data, arg_ary)
# A command has been called with insufficient permissions
signal cmd_no_permission(cmd_name, sender_data, cmd_data, arg_ary)
# Twitch's ping is about to be answered with a pong.
signal pong
# Emote has been downloaded
signal emote_downloaded(emote_id)
# Badge has been downloaded
signal badge_downloaded(badge_name)

# Messages starting with one of these symbols are handled. '/' will be ignored, reserved by Twitch.
export(Array, String) var command_prefixes : Array = ["!"]
# Time to wait after each sent chat message. Values below ~0.31 might lead to a disconnect after 100 messages.
export(float) var chat_timeout = 0.32
export(bool) var get_images : bool = false
# If true, caches emotes/badges to disk, so that they don't have to be redownloaded on every restart.
# This however means that they might not be updated if they change until you clear the cache.
export(bool) var disk_cache : bool = false
# Disk Cache has to be enbaled for this to work
export(String, FILE) var disk_cache_path = "user://gift/cache"

var websocket : WebSocketClient = WebSocketClient.new()
var user_regex = RegEx.new()
var twitch_restarting
# Twitch disconnects connected clients if too many chat messages are being sent. (At about 100 messages/30s)
var chat_queue = []
onready var chat_accu = chat_timeout
# Mapping of channels to their channel info, like available badges.
var channels : Dictionary = {}
var commands : Dictionary = {}
var image_cache : ImageCache

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
	websocket.verify_ssl = true
	user_regex.compile("(?<=!)[\\w]*(?=@)")

func _ready() -> void:
	websocket.connect("data_received", self, "data_received")
	websocket.connect("connection_established", self, "connection_established")
	websocket.connect("connection_closed", self, "connection_closed")
	websocket.connect("server_close_request", self, "sever_close_request")
	websocket.connect("connection_error", self, "connection_error")
	if(get_images):
		image_cache = ImageCache.new(disk_cache, disk_cache_path)
		add_child(image_cache)

func connect_to_twitch() -> void:
	if(websocket.connect_to_url("wss://irc-ws.chat.twitch.tv:443") != OK):
		print_debug("Could not connect to Twitch.")
		emit_signal("twitch_unavailable")

func _process(delta : float) -> void:
	if(websocket.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED):
		websocket.poll()
		if(!chat_queue.empty() && chat_accu >= chat_timeout):
			send(chat_queue.pop_front())
			chat_accu = 0
		else:
			chat_accu += delta

# Login using a oauth token.
# You will have to either get a oauth token yourself or use
# https://twitchapps.com/tokengen/
# to generate a token with custom scopes.
func authenticate_oauth(nick : String, token : String) -> void:
	websocket.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	send("PASS " + ("" if token.begins_with("oauth:") else "oauth:") + token, true)
	send("NICK " + nick.to_lower())
	request_caps()

func request_caps(caps : String = "twitch.tv/commands twitch.tv/tags twitch.tv/membership") -> void:
	send("CAP REQ :" + caps)

# Sends a String to Twitch.
func send(text : String, token : bool = false) -> void:
	websocket.get_peer(1).put_packet(text.to_utf8())
	if(OS.is_debug_build()):
		if(!token):
			print("< " + text.strip_edges(false))
		else:
			print("< PASS oauth:******************************")

# Sends a chat message to a channel. Defaults to the only connected channel.
func chat(message : String, channel : String = ""):
	var keys : Array = channels.keys()
	if(channel != ""):
		chat_queue.append("PRIVMSG " + ("" if channel.begins_with("#") else "#") + channel + " :" + message + "\r\n")
	elif(keys.size() == 1):
		chat_queue.append("PRIVMSG #" + channels.keys()[0] + " :" + message + "\r\n")
	else:
		print_debug("No channel specified.")

func whisper(message : String, target : String):
	chat("/w " + target + " " + message)

func data_received() -> void:
	var messages : PoolStringArray = websocket.get_peer(1).get_packet().get_string_from_utf8().strip_edges(false).split("\r\n")
	var tags = {}
	for message in messages:
		if(message.begins_with("@")):
			var msg : PoolStringArray = message.split(" ", false, 1)
			message = msg[1]
			for tag in msg[0].split(";"):
				var pair = tag.split("=")
				tags[pair[0]] = pair[1]
		if(OS.is_debug_build()):
			print("> " + message)
		handle_message(message, tags)

# Registers a command on an object with a func to call, similar to connect(signal, instance, func).
func add_command(cmd_name : String, instance : Object, instance_func : String, max_args : int = 0, min_args : int = 0, permission_level : int = PermissionFlag.EVERYONE, where : int = WhereFlag.CHAT) -> void:
	var func_ref = FuncRef.new()
	func_ref.set_instance(instance)
	func_ref.set_function(instance_func)
	commands[cmd_name] = CommandData.new(func_ref, permission_level, max_args, min_args, where)

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

func add_aliases(cmd_name : String, aliases : PoolStringArray) -> void:
	for alias in aliases:
		add_alias(cmd_name, alias)

func handle_message(message : String, tags : Dictionary) -> void:
	if(message == ":tmi.twitch.tv NOTICE * :Login authentication failed"):
		print_debug("Authentication failed.")
		emit_signal("login_attempt", false)
		return
	if(message == "PING :tmi.twitch.tv"):
		send("PONG :tmi.twitch.tv")
		emit_signal("pong")
		return
	var msg : PoolStringArray = message.split(" ", true, 4)
	match msg[1]:
		"001":
			print_debug("Authentication successful.")
			emit_signal("login_attempt", true)
		"PRIVMSG":
			var sender_data : SenderData = SenderData.new(user_regex.search(msg[0]).get_string(), msg[2], tags)
			handle_command(sender_data, msg)
			emit_signal("chat_message", sender_data, msg[3].right(1))
			if(get_images):
				if(!image_cache.badge_map.has(tags["room-id"])):
					image_cache.get_badge_mappings(tags["room-id"])
				for emote in tags["emotes"].split("/", false):
					image_cache.get_emote(emote.split(":")[0])
				for badge in tags["badges"].split(",", false):
					image_cache.get_badge(badge, tags["room-id"])
		"WHISPER":
			var sender_data : SenderData = SenderData.new(user_regex.search(msg[0]).get_string(), msg[2], tags)
			handle_command(sender_data, msg, true)
			emit_signal("whisper_message", sender_data, msg[3].right(1))
		"RECONNECT":
			twitch_restarting = true
		_:
			emit_signal("unhandled_message", message, tags)

func handle_command(sender_data : SenderData, msg : PoolStringArray, whisper : bool = false) -> void:
	if(command_prefixes.has(msg[3].substr(1, 1))):
		var command : String  = msg[3].right(2)
		var cmd_data : CommandData = commands.get(command)
		if(cmd_data):
			if(whisper == true && cmd_data.where & WhereFlag.WHISPER != WhereFlag.WHISPER):
				return
			elif(whisper == false && cmd_data.where & WhereFlag.CHAT != WhereFlag.CHAT):
				return 
			var args = "" if msg.size() < 5 else msg[4]
			var arg_ary : PoolStringArray = PoolStringArray() if args == "" else args.split(" ")
			if(arg_ary.size() > cmd_data.max_args && cmd_data.max_args != -1 || arg_ary.size() < cmd_data.min_args):
				emit_signal("cmd_invalid_argcount", command, sender_data, cmd_data, arg_ary)
				print_debug("Invalid argcount!")
				return
			if(cmd_data.permission_level != 0):
				var user_perm_flags = get_perm_flag_from_tags(sender_data.tags)
				if(user_perm_flags & cmd_data.permission_level != cmd_data.permission_level):
					emit_signal("cmd_no_permission", command, sender_data, cmd_data, arg_ary)
					print_debug("No Permission for command!")
					return
			if(arg_ary.size() == 0):
				cmd_data.func_ref.call_func(CommandInfo.new(sender_data, command, whisper))
			else:
				cmd_data.func_ref.call_func(CommandInfo.new(sender_data, command, whisper), arg_ary)

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
	send("JOIN #" + lower_channel)
	channels[lower_channel] = {}

func leave_channel(channel : String) -> void:
	var lower_channel : String = channel.to_lower()
	send("PART #" + lower_channel)
	channels.erase(lower_channel)

func connection_established(protocol : String) -> void:
	print_debug("Connected to Twitch.")
	emit_signal("twitch_connected")

func connection_closed(was_clean_close : bool) -> void:
	if(twitch_restarting):
		print_debug("Reconnecting to Twitch")
		emit_signal("twitch_reconnect")
		connect_to_twitch()
		yield(self, "twitch_connected")
		for channel in channels.keys():
			join_channel(channel)
		twitch_restarting = false
	else:
		print_debug("Disconnected from Twitch.")
		emit_signal("twitch_disconnected")

func connection_error() -> void:
	print_debug("Twitch is unavailable.")
	emit_signal("twitch_unavailable")

func server_close_request(code : int, reason : String) -> void:
	pass
