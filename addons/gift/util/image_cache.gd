extends Node
class_name ImageCache

signal badge_mapping_available

var cached_images : Dictionary = {"emotes": {}, "badges": {}}
var cache_mutex = Mutex.new()
var badge_map : Dictionary = {}
var badge_mutex = Mutex.new()
var dl_queue : PoolStringArray = []
var disk_cache : bool
var disk_cache_path : String

var file : File = File.new()
var dir : Directory = Directory.new()

func _init(do_disk_cache : bool, cache_path : String) -> void:
	disk_cache = do_disk_cache
	disk_cache_path = cache_path

func _ready() -> void:
	if(disk_cache):
		for cache_dir in cached_images.keys():
			cached_images[cache_dir] = {}
			dir.make_dir_recursive(disk_cache_path + "/" + cache_dir)
			dir.open(disk_cache_path + "/" + cache_dir)
			dir.list_dir_begin(true)
			var current = dir.get_next()
			while current != "":
				if(!dir.current_is_dir()):
					file.open(dir.get_current_dir() + "/" + current, File.READ)
					var img : Image = Image.new()
					img.load_png_from_buffer(file.get_buffer(file.get_len()))
					file.close()
					var img_texture : ImageTexture = ImageTexture.new()
					img_texture.create_from_image(img, 0)
					cache_mutex.lock()
					cached_images[cache_dir][current.get_basename()] = img_texture
					cache_mutex.unlock()
				current = dir.get_next()
		dir.open(disk_cache_path)
		dir.list_dir_begin(true)
		var current = dir.get_next()
		while current != "":
			if(!dir.current_is_dir()):
				file.open(disk_cache_path + "/" + current, File.READ)
				badge_map[current.get_basename()] = parse_json(file.get_as_text())["badge_sets"]
				file.close()
			current = dir.get_next()
	get_badge_mappings()
	yield(self, "badge_mapping_available")

func create_request(url : String, resource : String, res_type : String) -> void:
	var http_request = HTTPRequest.new()
	http_request.connect("request_completed", self, "downloaded", [http_request, resource, res_type], CONNECT_ONESHOT)
	add_child(http_request)
	http_request.download_file = disk_cache_path + "/" + res_type + "/" + resource + ".png"
	http_request.request(url, [], false, HTTPClient.METHOD_GET)

# Gets badge mappings for the specified channel. Empty String will get the mappings for global badges instead.
func get_badge_mappings(channel_id : String = "") -> void:
	var url : String
	if(channel_id == ""):
		channel_id = "_global"
		url = "https://badges.twitch.tv/v1/badges/global/display"
	else:
		url = "https://badges.twitch.tv/v1/badges/channels/" + channel_id + "/display"
	if(!badge_map.has(channel_id)):
		var http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.request(url, [], false, HTTPClient.METHOD_GET)
		http_request.connect("request_completed", self, "badge_mapping_received", [http_request, channel_id], CONNECT_ONESHOT)
	else:
		emit_signal("badge_mapping_available")

func get_emote(id : String) -> ImageTexture:
	cache_mutex.lock()
	if(cached_images["emotes"].has(id)):
		return cached_images["emotes"][id]
	else:
		create_request("http://static-cdn.jtvnw.net/emoticons/v1/" + id + "/1.0", id, "emotes")
	cache_mutex.unlock()
	return null

func get_badge(badge_name : String, channel_id : String = "") -> ImageTexture:
	cache_mutex.lock()
	var badge_data : PoolStringArray = badge_name.split("/")
	if(cached_images["badges"].has(badge_data[0])):
		return cached_images["badges"][badge_data[0]]
	var channel : String
	if(!badge_map[channel_id].has(badge_data[0])):
		channel_id = "_global"
	create_request(badge_map[channel_id][badge_data[0]]["versions"][badge_data[1]]["image_url_1x"], badge_data[0], "badges")
	cache_mutex.unlock()
	return null

func downloaded(result : int, response_code : int, headers : PoolStringArray, body : PoolByteArray, request : HTTPRequest, id : String, type : String) -> void:
	if(type == "emotes"):
		get_parent().emit_signal("emote_downloaded", id)
	elif(type == "badges"):
		get_parent().emit_signal("badge_downloaded", id)
	request.queue_free()

func badge_mapping_received(result : int, response_copde : int, headers : PoolStringArray, body : PoolByteArray, request : HTTPRequest, id : String) -> void:
	badge_map[id] = parse_json(body.get_string_from_utf8())["badge_sets"]
	if(disk_cache):
		file.open(disk_cache_path + "/" + id + ".json", File.WRITE)
		file.store_buffer(body)
		file.close()
	emit_signal("badge_mapping_available")
	request.queue_free()
