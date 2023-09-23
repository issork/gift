extends HBoxContainer

func set_msg(stamp : String, data : SenderData, msg : String, badges : String) -> void:
	$RichTextLabel.text = stamp + " " + badges + "[b][color="+ data.tags["color"] + "]" + data.tags["display-name"] +"[/color][/b]: " + msg
	queue_sort()
