extends Resource
class_name ImageCache

enum RequestType {
	EMOTE,
	BADGE,
	BADGE_MAPPING
}

var caches := {
	RequestType.EMOTE: {},
	RequestType.BADGE: {},
	RequestType.BADGE_MAPPING: {}
}

var queue := []
var thread := Thread.new()
var mutex := Mutex.new()
var active = true
var http_client := HTTPClient.new()
var host : String

var file : File = File.new()
var dir : Directory = Directory.new()
var cache_path : String
var disk_cache : bool

const HEADERS : PoolStringArray = PoolStringArray([
	"User-Agent: GIFT/1.0 (Godot Engine)",
	"Accept: */*"
])

func _init(do_disk_cache : bool, cache_path : String) -> void:
	self.disk_cache = do_disk_cache
	self.cache_path = cache_path
	thread.start(self, "start")

func start(params) -> void:
	var f : File = File.new()
	var d : Directory = Directory.new()
	if (disk_cache):
		for type in caches.keys():
			var cache_dir = RequestType.keys()[type]
			caches[cache_dir] = {}
			var error := d.make_dir_recursive(cache_path + "/" + cache_dir)
	while active:
		if (!queue.empty()):
			mutex.lock()
			var entry : Entry = queue.pop_front()
			mutex.unlock()
			var buffer : PoolByteArray = http_request(entry.path, entry.type)
			if (disk_cache):
				if !d.dir_exists(entry.filename.get_base_dir()):
					d.make_dir(entry.filename.get_base_dir())
				f.open(entry.filename, File.WRITE)
				f.store_buffer(buffer)
				f.close()
			var texture = ImageTexture.new()
			var img : Image = Image.new()
			img.load_png_from_buffer(buffer)
			if entry.type == RequestType.BADGE:
				caches[RequestType.BADGE][entry.data[0]][entry.data[1]].create_from_image(img, 0)
			elif entry.type == RequestType.EMOTE:
				caches[RequestType.EMOTE][entry.data[0]].create_from_image(img, 0)
		yield(Engine.get_main_loop(), "idle_frame")

# Gets badge mappings for the specified channel. Default: _global (global mappings)
func get_badge_mapping(channel_id : String = "_global") -> Dictionary:
	if !caches[RequestType.BADGE_MAPPING].has(channel_id):
		var filename : String = cache_path + "/" + RequestType.keys()[RequestType.BADGE_MAPPING] + "/" + channel_id + ".json"
		if !disk_cache && file.file_exists(filename):
			file.open(filename, File.READ)
			caches[RequestType.BADGE_MAPPING][channel_id] = parse_json(file.get_as_text())["badge_sets"]
			file.close()
		var buffer : PoolByteArray = http_request(channel_id, RequestType.BADGE_MAPPING)
		if !buffer.empty():
			caches[RequestType.BADGE_MAPPING][channel_id] = parse_json(buffer.get_string_from_utf8())["badge_sets"]
			if (disk_cache):
				file.open(filename, File.WRITE)
				file.store_buffer(buffer)
				file.close()
		else:
			return {}
	return caches[RequestType.BADGE_MAPPING][channel_id]

func get_badge(badge_name : String, channel_id : String = "_global", scale : String = "1") -> ImageTexture:
	var badge_data : PoolStringArray = badge_name.split("/", true, 1)
	var texture : ImageTexture = ImageTexture.new()
	var cachename = badge_data[0] + "_" + badge_data[1] + "_" + scale
	var filename : String = cache_path + "/" + RequestType.keys()[RequestType.BADGE] + "/" + channel_id + "/" + cachename + ".png"
	if !caches[RequestType.BADGE].has(channel_id):
		caches[RequestType.BADGE][channel_id] = {}
	if !caches[RequestType.BADGE][channel_id].has(cachename):
		if !disk_cache && file.file_exists(filename):
			file.open(filename, File.READ)
			var img : Image = Image.new()
			img.load_png_from_buffer(file.get_buffer(file.get_len()))
			texture.create_from_image(img)
			file.close()
		else:
			var map : Dictionary = caches[RequestType.BADGE_MAPPING].get(channel_id, get_badge_mapping(channel_id))
			if !map.empty():
				if map.has(badge_data[0]):
					mutex.lock()
					queue.append(Entry.new(map[badge_data[0]]["versions"][badge_data[1]]["image_url_" + scale + "x"].substr("https://static-cdn.jtvnw.net/badges/v1/".length()), RequestType.BADGE, filename, [channel_id, cachename]))
					mutex.unlock()
					var img = preload("res://addons/gift/placeholder.png")
					texture.create_from_image(img)
				elif channel_id != "_global":
					return get_badge(badge_name, "_global", scale)
			elif channel_id != "_global":
				return get_badge(badge_name, "_global", scale)
		texture.take_over_path(filename)
		caches[RequestType.BADGE][channel_id][cachename] = texture
	return caches[RequestType.BADGE][channel_id][cachename]

func get_emote(emote_id : String, scale = "1.0") -> ImageTexture:
	var texture : ImageTexture = ImageTexture.new()
	var cachename : String = emote_id + "_" + scale
	var filename : String = cache_path + "/" + RequestType.keys()[RequestType.EMOTE] + "/" + cachename + ".png"
	if !caches[RequestType.EMOTE].has(cachename):
		if !disk_cache && file.file_exists(filename):
			file.open(filename, File.READ)
			var img : Image = Image.new()
			img.load_png_from_buffer(file.get_buffer(file.get_len()))
			texture.create_from_image(img)
			file.close()
		else:
			mutex.lock()
			queue.append(Entry.new(emote_id + "/" + scale, RequestType.EMOTE, filename, [cachename]))
			mutex.unlock()
			var img = preload("res://addons/gift/placeholder.png")
			texture.create_from_image(img)
		texture.take_over_path(filename)
		caches[RequestType.EMOTE][cachename] = texture
	return caches[RequestType.EMOTE][cachename]

func http_request(path : String, type : int) -> PoolByteArray:
	var error := 0
	var buffer = PoolByteArray()
	var new_host : String
	match type:
		RequestType.BADGE_MAPPING:
			new_host = "badges.twitch.tv"
			path = "/v1/badges/" + ("global" if path == "_global" else "channels/" + path) + "/display"
		RequestType.BADGE, RequestType.EMOTE:
			new_host = "static-cdn.jtvnw.net"
			if type == RequestType.BADGE:
				path = "/badges/v1/" + path
			else:
				path = "/emoticons/v1/" + path
	if (host != new_host):
		error = http_client.connect_to_host(new_host, 443, true)
		while http_client.get_status() == HTTPClient.STATUS_CONNECTING or http_client.get_status() == HTTPClient.STATUS_RESOLVING:
			http_client.poll()
			delay(100)
		if (error != OK):
			print("Could not connect to " + new_host + ". Images disabled.")
			active = false
			return buffer
		host = new_host
	http_client.request(HTTPClient.METHOD_GET, path, HEADERS)
	while (http_client.get_status() == HTTPClient.STATUS_REQUESTING):
		http_client.poll()
		delay(50)
	if !(http_client.get_status() == HTTPClient.STATUS_BODY or http_client.get_status() == HTTPClient.STATUS_CONNECTED):
		print("Request failed. Skipped " + path + " (" + RequestType.keys()[type] + ")")
		return buffer
	while (http_client.get_status() == HTTPClient.STATUS_BODY):
		http_client.poll()
		delay(1)
		var chunk = http_client.read_response_body_chunk()
		if (chunk.size() == 0):
			delay(1)
		else:
			buffer += chunk
	return buffer

func delay(delay : int):
	if (OS.has_feature("web")):
		yield(Engine.get_main_loop(), "idle_frame")
	else:
		OS.delay_msec(delay)

class Entry extends Reference:
	var path : String
	var type : int
	var filename : String
	var data : Array

	func _init(path : String, type : int, filename : String, data : Array):
		self.path = path
		self.type = type
		self.filename = filename
		self.data = data
