extends Gift

func _ready() -> void:
	connect("cmd_no_permission", self, "no_permission")
	connect_to_twitch()
	yield(self, "twitch_connected")
	authenticate_oauth(<username>, <oauth_token>)
	join_channel(<channel_name>)
	
	# Adds a command with a specified permission flag. Defaults to PermissionFlag.EVERYONE
	# All implementation must take at least one arg for the command data.
	# This command can only be executed by VIPS/MODS/SUBS/STREAMER
	add_command("test", self, "command_test", PermissionFlag.NON_REGULAR)
	# This command can be executed by everyone
	add_command("helloworld", self, "hello_world", PermissionFlag.EVERYONE)
	# This command can only be executed by the streamer
	add_command("streamer_only", self, "streamer_only", PermissionFlag.STREAMER)
	# Command that requires exactly 1 arg.
	add_command("greet", self, "greet", PermissionFlag.EVERYONE, 1, 1)
	# Command that prints every arg seperated by a comma (infinite args allowed), at least 2 required
	add_command("list", self, "list", PermissionFlag.EVERYONE, -1, 2)
	
	# Adds a command alias
	add_alias("test","test1")
	add_alias("test","test2")
	add_alias("test","test3")
	
	# Remove a single command
	remove_command("test2")
	# Now only knows commands "test", "test1" and "test3"
	remove_command("test")
	# Now only knows commands "test1" and "test3"
	
	# Remove all commands that call the same function as the specified command
	purge_command("test1")
	# Now no "test" command is known
	
	# Send a chat message to the only connected channel ("mennomax")
	# Fails, if connected to more than one channel.
	chat("TEST")
	# Send a chat message to channel "mennomax"
	chat("TEST", "mennomax")
	# Send a whisper to user "mennomax"
	whisper("TEST", "mennomax")

# The cmd_data array contains [<sender_data (Array)>, <command_string (String)>, <whisper (bool)>
func command_test(cmd_data):
	print("A")

# The cmd_data array contains [<sender_data (Array)>, <command_string (String)>, <whisper (bool)>
func hello_world(cmd_data):
	chat("HELLO WORLD!")

func streamer_only(cmd_data):
	chat("Streamer command executed")

func no_permission(cmd_data):
	chat("NO PERMISSION!")

func greet(cmd_data, arg_ary):
	chat("Greetings, " + arg_ary[0])

func list(cmd_data, arg_ary):
	chat(arg_ary.join(", "))