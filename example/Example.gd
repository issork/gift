extends Control

# Your client id. You can share this publicly. Default is my own client_id.
# Please do not ship your project with my client_id, but feel free to test with it.
# Visit https://dev.twitch.tv/console/apps/create to create a new application.
# You can then find your client id at the bottom of the application console.
# DO NOT SHARE THE CLIENT SECRET. If you do, regenerate it.
@export var client_id : String = "9x951o0nd03na7moohwetpjjtds0or"
# The name of the channel we want to connect to.
@export var channel : String
# The username of the bot account.
@export var username : String

var id : TwitchIDConnection
var api : TwitchAPIConnection
var irc : TwitchIRCConnection
var eventsub : TwitchEventSubConnection

var cmd_handler : GIFTCommandHandler = GIFTCommandHandler.new()

var iconloader : TwitchIconDownloader

func _ready() -> void:
	# We will login using the Implicit Grant Flow, which only requires a client_id.
	# Alternatively, you can use the Authorization Code Grant Flow or the Client Credentials Grant Flow.
	# Note that the Client Credentials Grant Flow will only return an AppAccessToken, which can not be used
	# for the majority of the Twitch API or to join a chat room.
	var auth : ImplicitGrantFlow = ImplicitGrantFlow.new()
	# For the auth to work, we need to poll it regularly.
	get_tree().process_frame.connect(auth.poll) # You can also use a timer if you don't want to poll on every frame.

	# Next, we actually get our token to authenticate. We want to be able to read and write messages,
	# so we request the required scopes. See https://dev.twitch.tv/docs/authentication/scopes/#twitch-access-token-scopes
	var token : UserAccessToken = await(auth.login(client_id, ["chat:read", "chat:edit"]))
	if (token == null):
		# Authentication failed. Abort.
		return

	# Store the token in the ID connection, create all other connections.
	id = TwitchIDConnection.new(token)
	irc = TwitchIRCConnection.new(id)
	api = TwitchAPIConnection.new(id)
	iconloader = TwitchIconDownloader.new(api)
	# For everything to work, the id connection has to be polled regularly.
	get_tree().process_frame.connect(id.poll)

	# Connect to the Twitch chat.
	if(!await(irc.connect_to_irc(username))):
		# Authentication failed. Abort.
		return
	# Request the capabilities. By default only twitch.tv/commands and twitch.tv/tags are used.
	# Refer to https://dev.twitch.tv/docs/irc/capabilities/ for all available capapbilities.
	irc.request_capabilities()
	# Join the channel specified in the exported 'channel' variable.
	irc.join_channel(channel)

	# Add a helloworld command.
	cmd_handler.add_command("helloworld", hello)
	# The helloworld command can now also be executed with "hello"!
	cmd_handler.add_alias("helloworld", "hello")
	# Add a list command that accepts between 1 and infinite args.
	cmd_handler.add_command("list", list, -1, 1)

	# For the chat example to work, we forward the messages received to the put_chat function.
	irc.chat_message.connect(put_chat)

	# We also have to forward the messages to the command handler to handle them.
	irc.chat_message.connect(cmd_handler.handle_command)
	# If you also want to accept whispers, connect the signal and bind true as the last arg.
	irc.whisper_message.connect(cmd_handler.handle_command.bind(true))

	# When we press enter on the chat bar or press the send button, we want to execute the send_message
	# function.
	%LineEdit.text_submitted.connect(send_message.unbind(1))
	%Button.pressed.connect(send_message)

	# This part of the example only works if GIFT is logged in to your broadcaster account.
	# If you are, you can uncomment this to also try receiving follow events.
	# Don't forget to also add the 'moderator:read:followers' scope to your token.
#	eventsub = TwitchEventSubConnection.new(api)
#	await(eventsub.connect_to_eventsub())
#	eventsub.event.connect(on_event)
#	var user_ids : Dictionary = await(api.get_users_by_name([username]))
#	if (user_ids.has("data") && user_ids["data"].size() > 0):
#		var user_id : String = user_ids["data"][0]["id"]
#		eventsub.subscribe_event("channel.follow", "2", {"broadcaster_user_id": user_id, "moderator_user_id": user_id})

func hello(cmd_info : CommandInfo) -> void:
	irc.chat("Hello World!")

func list(cmd_info : CommandInfo, arg_ary : PackedStringArray) -> void:
	irc.chat(", ".join(arg_ary))

func on_event(type : String, data : Dictionary) -> void:
	match(type):
		"channel.follow":
			print("%s followed your channel!" % data["user_name"])

func send_message() -> void:
	irc.chat(%LineEdit.text)
	%LineEdit.text = ""

func put_chat(senderdata : SenderData, msg : String):
	var bottom : bool = %ChatScrollContainer.scroll_vertical == %ChatScrollContainer.get_v_scroll_bar().max_value - %ChatScrollContainer.get_v_scroll_bar().get_rect().size.y
	var label : RichTextLabel = RichTextLabel.new()
	var time = Time.get_time_dict_from_system()
	label.fit_content = true
	label.selection_enabled = true
	label.push_font_size(12)
	label.push_color(Color.WEB_GRAY)
	label.add_text("%02d:%02d " % [time["hour"], time["minute"]])
	label.pop()
	label.push_font_size(14)
	var badges : Array[Texture2D]
	for badge in senderdata.tags["badges"].split(",", false):
		label.add_image(await(iconloader.get_badge(badge, senderdata.tags["room-id"])), 0, 0, Color.WHITE, INLINE_ALIGNMENT_CENTER)
	label.push_bold()
	if (senderdata.tags["color"] != ""):
		label.push_color(Color(senderdata.tags["color"]))
	label.add_text(" %s" % senderdata.tags["display-name"])
	label.push_color(Color.WHITE)
	label.push_normal()
	label.add_text(": ")
	var locations : Array[EmoteLocation] = []
	if (senderdata.tags.has("emotes")):
		for emote in senderdata.tags["emotes"].split("/", false):
			var data : PackedStringArray = emote.split(":")
			for d in data[1].split(","):
				var start_end = d.split("-")
				locations.append(EmoteLocation.new(data[0], int(start_end[0]), int(start_end[1])))
	locations.sort_custom(Callable(EmoteLocation, "smaller"))
	if (locations.is_empty()):
		label.add_text(msg)
	else:
		var offset = 0
		for loc in locations:
			label.add_text(msg.substr(offset, loc.start - offset))
			label.add_image(await(iconloader.get_emote(loc.id)), 0, 0, Color.WHITE, INLINE_ALIGNMENT_CENTER)
			offset = loc.end + 1
	%Messages.add_child(label)
	await(get_tree().process_frame)
	if (bottom):
		%ChatScrollContainer.scroll_vertical = %ChatScrollContainer.get_v_scroll_bar().max_value

class EmoteLocation extends RefCounted:
	var id : String
	var start : int
	var end : int

	func _init(emote_id, start_idx, end_idx):
		self.id = emote_id
		self.start = start_idx
		self.end = end_idx

	static func smaller(a : EmoteLocation, b : EmoteLocation):
		return a.start < b.start
