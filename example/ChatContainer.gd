extends VBoxContainer

func put_chat(senderdata : SenderData, msg : String):
	var msgnode : Control = preload("res://example/ChatMessage.tscn").instantiate()
	var time = Time.get_time_dict_from_system()
	var badges : String = ""
	for badge in senderdata.tags["badges"].split(",", false):
		var result = await(%Gift.get_badge(badge, senderdata.tags["room-id"]))
		badges += "[img=center]" + result.resource_path + "[/img] "
	var locations : Array = []
	if (senderdata.tags.has("emotes")):
		for emote in senderdata.tags["emotes"].split("/", false):
			var data : Array = emote.split(":")
			for d in data[1].split(","):
				var start_end = d.split("-")
				locations.append(EmoteLocation.new(data[0], int(start_end[0]), int(start_end[1])))
	locations.sort_custom(Callable(EmoteLocation, "smaller"))
	var offset = 0
	for loc in locations:
		var result = await(%Gift.get_emote(loc.id))
		var emote_string = "[img=center]" + result.resource_path +"[/img]"
		msg = msg.substr(0, loc.start + offset) + emote_string + msg.substr(loc.end + offset + 1)
		offset += emote_string.length() + loc.start - loc.end - 1
	var bottom : bool = $Chat/ScrollContainer.scroll_vertical == $Chat/ScrollContainer.get_v_scroll_bar().max_value - $Chat/ScrollContainer.get_v_scroll_bar().get_rect().size.y
	msgnode.set_msg("%02d:%02d" % [time["hour"], time["minute"]], senderdata, msg, badges)
	$Chat/ScrollContainer/ChatMessagesContainer.add_child(msgnode)
	await(get_tree().process_frame)
	if (bottom):
		$Chat/ScrollContainer.scroll_vertical = $Chat/ScrollContainer.get_v_scroll_bar().max_value

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
