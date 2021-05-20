extends Control

func chat_message(data : SenderData, msg : String) -> void:
	$ChatContainer.put_chat(data, msg)

# Check the CommandInfo class for the available info of the cmd_info.
func command_test(cmd_info : CommandInfo) -> void:
	print("A")

func hello_world(cmd_info : CommandInfo) -> void:
	$Gift.chat("HELLO WORLD!")

func streamer_only(cmd_info : CommandInfo) -> void:
	$Gift.chat("Streamer command executed")

func no_permission(cmd_info : CommandInfo) -> void:
	$Gift.chat("NO PERMISSION!")

func greet(cmd_info : CommandInfo, arg_ary : PoolStringArray) -> void:
	$Gift.chat("Greetings, " + arg_ary[0])

func greet_me(cmd_info : CommandInfo) -> void:
	$Gift.chat("Greetings, " + cmd_info.sender_data.tags["display-name"] + "!")

func list(cmd_info : CommandInfo, arg_ary : PoolStringArray) -> void:
	$Gift.chat(arg_ary.join(", "))
