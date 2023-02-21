extends CanvasLayer

signal operation_started(text: String)
signal message_logged(text: String)

class Package:
	var name := ""
	var version := ""
	
	var is_indirect := false
	
	func unscoped_name() -> String:
		return name.get_file()

class Net:
	const CONNECTING_STATUS := [
		HTTPClient.STATUS_CONNECTING,
		HTTPClient.STATUS_RESOLVING
	]
	const SUCCESS_STATUS := [
		HTTPClient.STATUS_BODY,
		HTTPClient.STATUS_CONNECTED,
	]

	const HEADERS := [
		"User-Agent: GodotPackageManager/1.0 (godot-package-manager on GitHub)",
		"Accept: */*"
	]

	static func _create_client(host: String) -> HTTPClient:
		var client := HTTPClient.new()
		
		var err := client.connect_to_host(host, 443, TLSOptions.client())
		if err != OK:
			printerr("Unable to connect to host %s" % host)
			return null
		
		while client.get_status() in CONNECTING_STATUS:
			client.poll()
			await Engine.get_main_loop().process_frame
		
		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			printerr("Bad status while connecting to host %s" % host)
			return null
		
		return client

	static func _wait_for_response(client: HTTPClient, valid_response_codes: Array[int]) -> int:
		while client.get_status() == HTTPClient.STATUS_REQUESTING:
			client.poll()
			await Engine.get_main_loop().process_frame
		
		if not client.get_status() in SUCCESS_STATUS:
			return ERR_BUG
		
		if not client.get_response_code() in valid_response_codes:
			return ERR_BUG
		
		return OK

	static func _read_response_body(client: HTTPClient) -> PackedByteArray:
		var body := PackedByteArray()
		
		while client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			
			var chunk := client.read_response_body_chunk()
			if chunk.is_empty():
				await Engine.get_main_loop().process_frame
			else:
				body.append_array(chunk)
		
		return body

	static func _response_body_to_dict(body: PackedByteArray) -> Dictionary:
		var text := body.get_string_from_utf8()
		
		var response: Variant = JSON.parse_string(text)
		if response == null:
			printerr("Failed to parse response")
			return {}
		if typeof(response) != TYPE_DICTIONARY:
			printerr("Unexpected response %s" % str(response))
			return {}
		
		return response
	
	static func get_request(
		host: String,
		path: String,
		valid_response_codes: Array[int]
	) -> PackedByteArray:
		var client: HTTPClient = await _create_client(host)
		if client == null:
			printerr("Unable to create client for get request")
			return PackedByteArray()
		
		var err := client.request(HTTPClient.METHOD_GET, "/%s" % path, HEADERS)
		if err != OK:
			printerr("Unable to send GET request to %s/%s" % [host, path])
			return PackedByteArray()
		
		err = await _wait_for_response(client, valid_response_codes)
		if err != OK:
			printerr("Bad response for GET request to %s/%s" % [host, path])
			return PackedByteArray()
		
		var body: PackedByteArray = await _read_response_body(client)
		
		return body

	static func get_request_json(host: String, path: String, valid_response_codes: Array[int]) -> Dictionary:
		var body: PackedByteArray = await get_request(host, path, valid_response_codes)
		
		return _response_body_to_dict(body)

class Npm:
	const PackageJson := {
		"PACKAGES": "packages",
	}

	const NPM := "https://registry.npmjs.org"
	const GET_FORMAT := "/%s"
	const GET_WITH_VERSION_FORMAT := "/%s/%s"
	const SEARCH_FORMAT := "/-/v1/search?text=%s"
	
	static func get_manifest(package_name: String, version: String) -> Dictionary:
		var response: Dictionary = await Net.get_request_json(
			NPM, GET_WITH_VERSION_FORMAT % [package_name, version], [200])
		
		return response
	
	static func get_tarball_url(package_name: String, version: String) -> String:
		var response := await get_manifest(package_name, version)
		if response.is_empty():
			printerr("get_tarball_url response was empty")
			return ""
		
		return response.get("dist", {}).get("tarball", "")

var hostname_regex := RegEx.create_from_string(
	"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?")

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _ready() -> void:
	operation_started.connect(func(text: String) -> void:
		print(text)
	)
	message_logged.connect(func(text: String) -> void:
		print(text)
	)
	
	var err := await test()
	
	print(err)

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

func _get_host_path_pair(url: String) -> Dictionary:
	var r := hostname_regex.search(url)
	
	return {
		"host": "%s%s" % [r.get_string(1), r.get_string(3)],
		"path": "%s%s%s" % [r.get_string(5), r.get_string(6), r.get_string(8)]
	}

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

func test() -> int:
	operation_started.emit("Starting %s@%s" % ["some text", "1.0.0"])
	
	const ADDONS_DIR_FORMAT := "res://addons/%s"
	const DEPENDENCIES_DIR_FORMAT := "res://addons/__gpm_deps/%s/%s"
	
	var package := Package.new()
	package.name = "@sometimes_youwin/verbal-expressions"
	package.version = "1.0.1"
	
	var response := await Npm.get_tarball_url(package.name, package.version)
	if response.is_empty():
		message_logged.emit("Could not get tarball url for %s@%S" % [
			package.name, package.version
		])
		return ERR_DOES_NOT_EXIST
	
	var host_path_pair := _get_host_path_pair(response)
	
	var bytes := await Net.get_request(host_path_pair.host, host_path_pair.path, [200])
	
	var package_dir := ADDONS_DIR_FORMAT % package.unscoped_name() if not package.is_indirect else \
		DEPENDENCIES_DIR_FORMAT % [package.version, package.unscoped_name()]
	
	var tar_path := "%s/%s.tar.gz" % [package_dir, package.unscoped_name()]
	
	print(package_dir)
	print(tar_path)
	
	print("Success!")
	
	return OK
