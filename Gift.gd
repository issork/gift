extends Gift

func _ready() -> void:
	# I use a file in the working directory to store auth data
	# so that I don't accidentally push it to the repository.
	# Replace this or create a auth file with 3 lines in your
	# project directory:
	# <bot username>
	# <oauth token>
	# <initial channel>
	var authfile := File.new()
	authfile.open("./auth", File.READ)
	var botname := authfile.get_line()
	var token := authfile.get_line()
	var initial_channel = authfile.get_line()

	connect_to_twitch()
	yield(self, "twitch_connected")

	# Login using your username and an oauth token.
	# You will have to either get a oauth token yourself or use
	# https://twitchapps.com/tokengen/
	# to generate a token with custom scopes.
	authenticate_oauth(botname, token)
	if(yield(self, "login_attempt") == false):
	  print("Invalid username or token.")
	  return
	join_channel(initial_channel)

	connect("cmd_no_permission", get_parent(), "no_permission")
	connect("chat_message", get_parent(), "chat_message")

	# Adds a command with a specified permission flag.
	# All implementations must take at least one arg for the command info.
	# Implementations that recieve args requrires two args,
	# the second arg will contain all params in a PoolStringArray
	# This command can only be executed by VIPS/MODS/SUBS/STREAMER
	add_command("test", get_parent(), "command_test", 0, 0, PermissionFlag.NON_REGULAR)

	# These two commands can be executed by everyone
	add_command("helloworld", get_parent(), "hello_world")
	add_command("greetme", get_parent(), "greet_me")

	# This command can only be executed by the streamer
	add_command("streamer_only", get_parent(), "streamer_only", 0, 0, PermissionFlag.STREAMER)

	# Command that requires exactly 1 arg.
	add_command("greet", get_parent(), "greet", 1, 1)

	# Command that prints every arg seperated by a comma (infinite args allowed), at least 2 required
	add_command("list", get_parent(), "list", -1, 2)

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
