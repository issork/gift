extends Gift

func _ready() -> void:
	connect("cmd_no_permission", self, "no_permission")
	connect_to_twitch()
	yield(self, "twitch_connected")
	
	# Login using your username and an oauth token.
	# You will have to either get a oauth token yourself or use
	# https://twitchapps.com/tokengen/
	# to generate a token with custom scopes.
	authenticate_oauth("<account_name>", "<oauth_token>")
	if(yield(self, "login_attempt") == false):
	  print("Invalid username or token.")
	  return
	join_channel("<channel_name>")
	
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
	chat("TEST", "<channel_name>")
	
	# Send a whisper to target user
	whisper("TEST", "<target_name>")

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
