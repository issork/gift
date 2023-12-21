class_name TwitchIconDownloader
extends RefCounted

signal fetched(texture)

var api : TwitchAPIConnection

const JTVNW_URL : String = "https://static-cdn.jtvnw.net"

var jtvnw_client : HTTPClient = HTTPClient.new()
var jtvnw_response : PackedByteArray = []
var jtvnw_queue : Array[String] = []

var cached_badges : Dictionary = {}

var disk_cache : bool

func _init(twitch_api : TwitchAPIConnection, disk_cache_enabled : bool = false) -> void:
	api = twitch_api
	api.id_conn.polled.connect(poll)
	disk_cache = disk_cache_enabled
	jtvnw_client.connect_to_host(JTVNW_URL)

func poll() -> void:
	jtvnw_client.poll()
	var conn_status : HTTPClient.Status = jtvnw_client.get_status()
	if (conn_status == HTTPClient.STATUS_BODY):
		jtvnw_response += jtvnw_client.read_response_body_chunk()
	elif (!jtvnw_response.is_empty()):
		var img := Image.new()
		img.load_png_from_buffer(jtvnw_response)
		jtvnw_response.clear()
		var path = jtvnw_queue.pop_front()
		var texture : ImageTexture = ImageTexture.new()
		texture.set_image(img)
		texture.take_over_path(path)
		fetched.emit(texture)
	elif (!jtvnw_queue.is_empty()):
		if (conn_status == HTTPClient.STATUS_CONNECTED):
			jtvnw_client.request(HTTPClient.METHOD_GET, jtvnw_queue.front(), ["Accept: image/png"])
		elif (conn_status == HTTPClient.STATUS_DISCONNECTED || conn_status == HTTPClient.STATUS_CONNECTION_ERROR):
			jtvnw_client.connect_to_host(JTVNW_URL)

func get_badge(badge_id : String, channel_id : String = "_global", scale : String = "1x") -> Texture2D:
	var badge_data : PackedStringArray = badge_id.split("/", true, 1)
	if (!cached_badges.has(channel_id)):
		if (channel_id == "_global"):
			cache_badges(await(api.get_global_chat_badges()), channel_id)
		else:
			cache_badges(await(api.get_channel_chat_badges(channel_id)), channel_id)
	if (channel_id != "_global" && !cached_badges[channel_id].has(badge_data[0])):
		return await(get_badge(badge_id, "_global", scale))
	var path : String = cached_badges[channel_id][badge_data[0]]["versions"][badge_data[1]]["image_url_%s" % scale].substr(JTVNW_URL.length())
	if ResourceLoader.has_cached(path):
		return load(path)
	else:
		jtvnw_queue.append(path)
		var filepath : String = "user://badges/%s/%s_%s_%s.png" % [channel_id, badge_data[0], badge_data[1], scale]
		return await(wait_for_fetched(path, filepath))

func get_emote(emote_id : String, dark : bool = true, scale : String = "1.0") -> Texture2D:
	var path : String = "/emoticons/v2/%s/static/%s/%s" % [emote_id, "dark" if dark else "light", scale]
	if ResourceLoader.has_cached(path):
		return load(path)
	else:
		var filepath : String = "user://emotes/%s.png" % emote_id
		jtvnw_queue.append(path)
		return await(wait_for_fetched(path, filepath))

func cache_badges(result, channel_id) -> void:
	cached_badges[channel_id] = result
	var mappings : Dictionary = {}
	var badges : Array = cached_badges[channel_id]["data"]
	for entry in badges:
		if (!mappings.has(entry["set_id"])):
			mappings[entry["set_id"]] = {"versions" : {}}
		for version in entry["versions"]:
			mappings[entry["set_id"]]["versions"][version["id"]] = version
	cached_badges[channel_id] = mappings

func wait_for_fetched(path : String, filepath : String) -> ImageTexture:
		var last_fetched : ImageTexture = null
		while (last_fetched == null || last_fetched.resource_path != path):
			last_fetched = await(fetched)
		last_fetched.take_over_path(path)
		return load(path)
