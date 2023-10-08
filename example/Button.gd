extends Button

func _pressed():
	%Gift.chat(%LineEdit.text)
	var channel : String = %Gift.channels.keys()[0]
	%Gift.handle_command(SenderData.new(%Gift.username, channel, %Gift.last_state[channel]), (":" + %LineEdit.text).split(" ", true, 1))
	%LineEdit.text = ""
