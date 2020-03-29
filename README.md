# GIFT
Godot IRC For Twitch addon

- [Examples](https://github.com/MennoMax/gift#Examples)
- [API](https://github.com/MennoMax/gift#API)
    - [Exported Variables](https://github.com/MennoMax/gift#Exported-Variables)
    - [Signals](https://github.com/MennoMax/gift#Signals)
    - [Functions](https://github.com/MennoMax/gift#Functions)
    - [Utility Classes](https://github.com/MennoMax/gift#Utility-Classes)

***

**The badge/emote downloading functionality is experimental, but should work. Please report issues you find here.**

### Examples

The following code is also [included](https://github.com/MennoMax/gift/blob/master/Gift.gd) in this repository.
```gdscript
extends Gift

func _ready() -> void:
  connect("cmd_no_permission", self, "no_permission")
  connect_to_twitch()
  yield(self, "twitch_connected")
  
  # Login using your username and an oauth token.
  # You will have to either get a oauth token yourself or use
  # https://twitchapps.com/tokengen/
  # to generate a token with custom scopes.
  authenticate_oauth(<account_name>, <oauth_token>)
  if(yield(self, "login_attempt") == false):
    print("Invalid username or token.")
    return
  join_channel(<channel_name>)
  
  # Adds a command with a specified permission flag.
  # All implementations must take at least one arg for the command info.
  # Implementations that recieve args requrires two args,
  # the second arg will contain all params in a PoolStringArray
  # This command can only be executed by VIPS/MODS/SUBS/STREAMER
  add_command("test", self, "command_test", 0, 0, PermissionFlag.NON_REGULAR)
  
  # These two commands can be executed by everyone
  add_command("helloworld", self, "hello_world")
  add_command("greetme", self, "greet_me")
  
  # This command can only be executed by the streamer
  add_command("streamer_only", self, "streamer_only", 0, 0, PermissionFlag.STREAMER)
  
  # Command that requires exactly 1 arg.
  add_command("greet", self, "greet", 1, 1)
  
  # Command that prints every arg seperated by a comma (infinite args allowed), at least 2 required
  add_command("list", self, "list", -1, 2)

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
  chat("TEST")
  
  # Send a chat message to channel <channel_name>
  chat("TEST", <channel_name>)
  
  # Send a whisper to target user
  whisper("TEST", <target_name>)

# Check the CommandInfo class for the available info of the cmd_info.
func command_test(cmd_info : CommandInfo) -> void:
  print("A")

func hello_world(cmd_info : CommandInfo) -> void:
  chat("HELLO WORLD!")

func streamer_only(cmd_info : CommandInfo) -> void:
  chat("Streamer command executed")

func no_permission(cmd_info : CommandInfo) -> void:
  chat("NO PERMISSION!")

func greet(cmd_info : CommandInfo, arg_ary : PoolStringArray) -> void:
  chat("Greetings, " + arg_ary[0])

func greet_me(cmd_info : CommandInfo) -> void:
  chat("Greetings, " + cmd_info.sender_data.tags["display-name"] + "!")

func list(cmd_info : CommandInfo, arg_ary : PoolStringArray) -> void:
  chat(arg_ary.join(", "))
  
```

***

## API

### Exported Variables
- **command_prefix**: PoolStringArray - Prefixes for commands. Every message that starts with one of these will be interpreted as one.
- **chat_timeout** : float - Time to wait before sending the next chat message. Values below ~0.31 will lead to a disconnect at 100 messages in the queue.
- **get_badges** : bool - Wether or not badges should be downloaded and cached in RAM.
- **get_emotes** : bool - Wether or not emotes should be downloaded and cached in RAM.
- **disk_cache** : bool - If true, badges and emotes will be cached on the disk instead.
- **disk_cache_path** : String - Path to the cache folder on the hard drive.

***

### Signals:
|Signal|Params|Description|
|-|-|-|
|twitch_connected|-|The underlying websocket successfully connected to Twitch.|
|twitch_disconnected|-|The connection has been closed. Not emitted if Twitch announced a reconnect.|
|twitch_unavailbale|-|Could not establish a connection to Twitch.|
|twitch_reconnect|-|Twitch requested the client to reconnect. (Will be unavailable until next connect)|
|login_attempt|success(bool) - wether or not the login attempt was successful|The client tried to login.|
|chat_message|sender_data(SenderData), message(String), channel(String)|User sent a message in chat.|
|whisper_message|sender_data(SenderData), message(String), channel(String)|User sent a whisper message.|
|unhandled message|message(String), tags(Dictionary)|Unhandled message from Twitch.|
|cmd_invalid_argcount|cmd_name(String), sender_data(SenderData), cmd_data(CommandData), arg_ary(PoolStringArray)|A command has been called by a chatter with an invalid amount of args.|
|cmd_no_permission|cmd_name(String), sender_data(SenderData), cmd_data(CommandData), arg_ary(PoolStringArray)|A command has been called by a chater without having the required permissions.|
|pong|-|A ping from Twitch has been answered with a pong.|

***

### Functions:
|Function|Params|Description|
|-|-|-|
|authenticate_oauth|nick(String) - the accoutns username, token(String) - your oauth token|Authenticate yourself to use the Twitch API. Check out https://twitchapps.com/tokengen/ to generate a token.|
|send|text(string) - the UTF8-String that should be sent to Twitch|Sends a UTF8-String to Twitch over the websocket.|
|chat|message(String), channel(String) - DEFAULT: Only connected channel|Sends a chat message to a channel.|
|whisper|message(String), target(String)| Sends a whisper message to the specified user.|
|add_command|cmd_name(String), instance(Object), instance_func(String), max_args(int), min_args(int), permission_level(int), where(int)| Registers a command with a function to call on a specified object. You can also set min/max args allowed and where (whisper or chat) the command execution should be allowed to be requested.|
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
- **func_ref** : FuncRef - Function that is called by the command.
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

