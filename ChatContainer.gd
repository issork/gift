extends VBoxContainer

func put_chat(senderdata : SenderData, msg : String):
	var msgnode : Control = preload("res://ChatMessage.tscn").instance()
	var time = OS.get_time()
	var badges : String = ""
	if ($"../Gift".image_cache):
		for badge in senderdata.tags["badges"].split(",", false):
			badges += "[img=center]" + $"../Gift".image_cache.get_badge(badge, senderdata.tags["room-id"]).resource_path + "[/img] "
		var locations : Array = []
		for emote in senderdata.tags["emotes"].split("/", false):
			var data : Array = emote.split(":")
			for d in data[1].split(","):
				var start_end = d.split("-")
				locations.append(EmoteLocation.new(data[0], int(start_end[0]), int(start_end[1])))
		locations.sort_custom(EmoteLocation, "smaller")
		var offset = 0
		for loc in locations:
			var emote_string = "[img=center]" + $"../Gift".image_cache.get_emote(loc.id).resource_path +"[/img]"
			msg = msg.substr(0, loc.start + offset) + emote_string + msg.substr(loc.end + offset + 1)
			offset += emote_string.length() + loc.start - loc.end - 1
	var bottom : bool = $Chat/ScrollContainer.scroll_vertical == $Chat/ScrollContainer.get_v_scrollbar().max_value - $Chat/ScrollContainer.get_v_scrollbar().rect_size.y
	msgnode.set_msg(str(time["hour"]) + ":" + ("0" + str(time["minute"]) if time["minute"] < 10 else str(time["minute"])), senderdata, msg, badges)
	$Chat/ScrollContainer/ChatMessagesContainer.add_child(msgnode)
	yield(get_tree(), "idle_frame")
	if (bottom):
		$Chat/ScrollContainer.scroll_vertical = $Chat/ScrollContainer.get_v_scrollbar().max_value

class EmoteLocation extends Reference:
	var id : String
	var start : int
	var end : int

	func _init(emote_id, start_idx, end_idx):
		self.id = emote_id
		self.start = start_idx
		self.end = end_idx

	static func smaller(a : EmoteLocation, b : EmoteLocation):
		return a.start < b.start
