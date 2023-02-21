# GIFT
Godot IRC For Twitch addon

To use this plugin, you need to create a new application on dev.twitch.tv to get a client ID and a client secret. The redirect URL of your App has to be https://localhost:18297.

If you require help, feel free to join my >[Discord Server](https://discord.gg/28DQbuwMM2)< and ask your questions <3

- [Examples](https://github.com/MennoMax/gift#Examples)
- [API](https://github.com/MennoMax/gift#API)
	- [Exported Variables](https://github.com/MennoMax/gift#Exported-Variables)
	- [Signals](https://github.com/MennoMax/gift#Signals)
	- [Functions](https://github.com/MennoMax/gift#Functions)
	- [Utility Classes](https://github.com/MennoMax/gift#Utility-Classes)

***

Below is a working example of this plugin, which is included in this project. A replication of the twitch chat.

![image](https://user-images.githubusercontent.com/12477395/119052327-b9fc9980-b9c4-11eb-8f45-a2a8f2d98977.png)

### Examples

The following code is also [included](https://github.com/MennoMax/gift/blob/master/Gift.gd) in this repository.
```gdscript
extends Gift

func _ready() -> void:
	cmd_no_permission.connect(no_permission)
	chat_message.connect(on_chat)
	channel_follow.connect(on_follow)

	# I use a file in the working directory to store auth data
	# so that I don't accidentally push it to the repository.
	# Replace this or create a auth file with 3 lines in your
	# project directory:
	# <client_id>
	# <client_secret>
	# <initial channel>
	var authfile := FileAccess.open("./auth", FileAccess.READ)
	client_id = authfile.get_line()
	client_secret = authfile.get_line()
	var initial_channel = authfile.get_line()

	# When calling this method, a browser will open.
	# Log in to the account that should be used.
	await(authenticate(client_id, client_secret))
	var success = await(connect_to_irc())
	if (success):
		request_caps()
		join_channel(initial_channel)
	events.append("channel.follow")
	await(connect_to_eventsub())

	# Adds a command with a specified permission flag.
	# All implementations must take at least one arg for the command info.
	# Implementations that recieve args requrires two args,
	# the second arg will contain all params in a PackedStringArray
	# This command can only be executed by VIPS/MODS/SUBS/STREAMER
	add_command("test", command_test, 0, 0, PermissionFlag.NON_REGULAR)

	# These two commands can be executed by everyone
	add_command("helloworld", hello_world)
	add_command("greetme", greet_me)

	# This command can only be executed by the streamer
	add_command("streamer_only", streamer_only, 0, 0, PermissionFlag.STREAMER)

	# Command that requires exactly 1 arg.
	add_command("greet", greet, 1, 1)

	# Command that prints every arg seperated by a comma (infinite args allowed), at least 2 required
	add_command("list", list, -1, 2)

	# Adds a command alias
	add_alias("test","test1")
	add_alias("test","test2")
	add_alias("test","test3")
	# Or do it in a single line
	# add_aliases("test", ["test1", "test2", "test3"])

	# Remove a single command
	remove_command("test2")

	# Now only knows commands "test", "test1" and "test3"
	remove_command("test")
	# Now only knows commands "test1" and "test3"

	# Remove all commands that call the same function as the specified command
	purge_command("test1")
	# Now no "test" command is known

	# Send a chat message to the only connected channel (<channel_name>)
	# Fails, if connected to more than one channel.
#	chat("TEST")

	# Send a chat message to channel <channel_name>
#	chat("TEST", initial_channel)

	# Send a whisper to target user
#	whisper("TEST", initial_channel)

func on_follow(data : Dictionary) -> void:
	print("%s followed your channel!" % data["user_name"])

func on_chat(data : SenderData, msg : String) -> void:
	%ChatContainer.put_chat(data, msg)

# Check the CommandInfo class for the available info of the cmd_info.
func command_test(cmd_info : CommandInfo) -> void:
	print("A")

func hello_world(cmd_info : CommandInfo) -> void:
	chat("HELLO WORLD!")

func streamer_only(cmd_info : CommandInfo) -> void:
	chat("Streamer command executed")

func no_permission(cmd_info : CommandInfo) -> void:
	chat("NO PERMISSION!")

func greet(cmd_info : CommandInfo, arg_ary : PackedStringArray) -> void:
	chat("Greetings, " + arg_ary[0])

func greet_me(cmd_info : CommandInfo) -> void:
	chat("Greetings, " + cmd_info.sender_data.tags["display-name"] + "!")

func list(cmd_info : CommandInfo, arg_ary : PackedStringArray) -> void:
	var msg = ""
	for i in arg_ary.size() - 1:
		msg += arg_ary[i]
		msg += ", "
	msg += arg_ary[arg_ary.size() - 1]
	chat(msg)

```

***

## API

### Exported Variables
- **command_prefix**: Array[String] - Prefixes for commands. Every message that starts with one of these will be interpreted as one.
- **chat_timeout** : float - Time to wait before sending the next chat message. Values below ~0.31 will lead to a disconnect at 100 messages in the queue.
- **scopes** : Array[String] - Scopes to request when creating your user token. Check https://dev.twitch.tv/docs/authentication/scopes/ for a list of all available scopes.
- **events** : Array[String] - Events to subscribe to with the EventSub. Full list available at  https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/
- **disk_cache** : bool - If true, badges and emotes will be cached on the disk instead of only in RAM.
- **disk_cache_path** : String - Path to the cache folder on the hard drive.

***

### Signals:
|Signal|Params|Description|
|-|-|-|
|twitch_connected|-|The underlying websocket successfully connected to Twitch IRC.|
|twitch_disconnected|-|The connection has been closed. Not emitted if Twitch IRC announced a reconnect.|
|twitch_unavailbale|-|Could not establish a connection to Twitch IRC.|
|twitch_reconnect|-|Twitch IRC requested the client to reconnect. (Will be unavailable until next connect)|
|-|-|-|
|user_token_received|token_data(Dictionary)|User token from Twitch has been fetched.|
|user_token_valid|-|User token has been checked and is valid.|
|user_token_invalid|-|User token has been checked and is invalid.|
|login_attempt|success(bool) - wether or not the login attempt was successful|The client tried to login to Twitch IRC. Returns true if successful, else false.|
|-|-|-|
|chat_message|sender_data(SenderData), message(String)|User sent a message in chat.|
|whisper_message|sender_data(SenderData), message(String)|User sent a whisper message.|
|unhandled message|message(String), tags(Dictionary)|Unhandled message from Twitch.|
|cmd_invalid_argcount|cmd_name(String), sender_data(SenderData), cmd_data(CommandData), arg_ary(PackedStringArray)|A command has been called by a chatter with an invalid amount of args.|
|cmd_no_permission|cmd_name(String), sender_data(SenderData), cmd_data(CommandData), arg_ary(PackedStringArray)|A command has been called by a chatter without having the required permissions.|
|pong|-|A ping from Twitch has been answered with a pong.|
|-|-|-|
|events_connected|-|The underlying websocket sucessfully connected to Twitch EventSub.|
|events_unavailable|-|The connection to Twitch EventSub failed.|
|events_disconnected|-|The underlying websocket disconnected from Twitch EventSub.|
|events_id(id)|id(String))|The id has been received from the welcome message.|
|events_reconnect|-|Twitch directed the bot to reconnect to a different URL.|
|events_revoked|event(String), reason(String)|Twitch revoked a event subscription|

Events from EventSub are named just like their subscription name, with all '.' replaced by '_'.
Example: channel.follow emits the signal channel_follow(data(Dictionary))
***

### Functions:
|Function|Params|Description|
|-|-|-|
|authenticate|client_id(String), client_secret(String)|Request a OAUTH token from Twitch with your client_id and client_secret|
|connect_to_irc|-|Connect to Twitch IRC. Make sure to authenticate first.|
|connect_to_eventsub|url(String) - only used when Twitch requests a reconnect to a specific URL|Connect to Twitch EventSub. Make sure to authenticate first.|
|request_caps|caps(String) - capabilities to request from twitch|Request capabilities from Twitch.|
|send|text(string) - the UTF8-String that should be sent to Twitch|Sends a UTF8-String to Twitch over the websocket.|
|chat|message(String), channel(String) - DEFAULT: Only connected channel|Sends a chat message to a channel.|
|whisper|message(String), target(String)| Sends a whisper message to the specified user.|
|add_command|cmd_name(String), function(Callable), max_args(int), min_args(int), permission_level(int), where(int)| Registers a command with a function to call on a specified object. You can also set min/max args allowed and where (whisper or chat) the command execution should be allowed to be requested.|
|remove_command|cmd_name(String)|Removes a single command or alias from the command registry.|
|purge_command|cmd_name(String)| Removes all commands that call the same function on the same object as the specified command.|
|add_alias|cmd_name(String), alias(String)|Registers a command alias.|
|add_aliases|cmd_name(String), aliases(PoolStringArray)|Registers all command aliases in the array.|
|join_channel|channel(String)|Joins a channel.|
|leave_channel|channel(String)|Leaves a channel.|

***

### Utility Classes

***

#### CommandData
##### Data required to store, execute and handle commands properly.
- **func_ref** : Callable - Function that is called by the command.
- **permission_level** : int - Permission level required by the command.
- **max_args** : int - Maximum number of arguments this command accepts. cmd_invalid_argcount is emitted if above this number.
- **min_args** : int - Minimum number of arguments this command accepts. cmd_invalid_argcount is emitted if below this number.
- **where** : int - Where the command should be received (0 = Chat, 1 = Whisper)

***

#### CommandInfo
##### Info about the command that was executed.
- **sender_data** : SenderData - Associated data with the sender.
- **command** : String - Name of the command that has been called.
- **whisper** : bool - true if the command was sent as a whisper message.

***

#### SenderData
##### Data of the sender
- **user** : String - The lowercase username of the sender. Use tags["display-name"] for the case sensitive name.
- **channel** : String - The channel in which the data was sent.
- **tags** : Dictionary - Refer to the Tags documentation; https://dev.twitch.tv/docs/irc/tags

