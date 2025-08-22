extends Control

#region variables and constants
var times_refreshed: int
var timer: float
var content_path: String

const DB_URL: String = "https://github.com/Gapva/sscdb/archive/refs/heads/main.zip"
#endregion

#region types and enums
var OutColor: Dictionary = {
	REGULAR = "#ffffff",
	ERROR = "#ffaaaa",
	WARNING = "#ffffaa",
	NOTICE = "#aaaaff",
	GOOD = "#aaffaa",
}

enum ResultType {
	FAIL,
	SUCCESS,
	UNKNOWN,
}
#endregion

#region console methods
func append_reg(text: String = "") -> void:
	print(text)
	%log.append_text("[color=%s]%s\n" % [OutColor.REGULAR, text])

func append_err(text: String = "") -> void:
	print(text)
	%log.append_text("[color=%s]%s\n" % [OutColor.ERROR, text])

func append_warning(text: String = "") -> void:
	print(text)
	%log.append_text("[color=%s]%s\n" % [OutColor.WARNING, text])

func append_notice(text: String = "") -> void:
	print(text)
	%log.append_text("[color=%s]%s\n" % [OutColor.NOTICE, text])

func append_success(text: String = "") -> void:
	print(text)
	%log.append_text("[color=%s]%s\n" % [OutColor.GOOD, text])

func br() -> void:
	print()
	%log.append_text("\n")

func inline_wait(text: String = "") -> void:
	print("%s..." % text)
	%log.append_text("[color=%s]%s..." % [OutColor.REGULAR, text])

func inline_result(type: ResultType) -> void:
	match type:
		ResultType.FAIL:
			print("failed\n")
			%log.append_text("[color=%s] failed\n" % OutColor.ERROR)
		ResultType.SUCCESS:
			print("OK\n")
			%log.append_text("[color=%s] OK\n" % OutColor.GOOD)
		_: # assume ResultType.UNKNOWN
			print("couldn't establish\n")
			%log.append_text("[color=%s] couldn't establish\n" % OutColor.WARNING)

func fatal_stop() -> void:
	append_err("\nSSCHelper encountered a dead end and cannot progress further")
	append_notice("press esc to exit")

func process_complete() -> void:
	append_success("\nprocess finished successfully in %ss" % snappedf(timer, 0.01))
	append_notice("press esc to exit")
#endregion

#region program methods
func fetch_latest_db(to: String) -> bool:
	if DirAccess.dir_exists_absolute("user://sscdb"):
		remove_item("%s/sscdb" % ProjectSettings.globalize_path("user://"))
	var req: HTTPRequest = HTTPRequest.new()
	self.add_child(req)
	req.download_file = to
	req.request(DB_URL)
	await req.request_completed
	return FileAccess.file_exists(to) and FileAccess.open(to, FileAccess.READ).get_length() > 0

func extract_fetched_db(to: String) -> void:
	var reader: ZIPReader = ZIPReader.new()
	reader.open("user://sscdb.zip")
	var root_dir: DirAccess = DirAccess.open(to)
	var files: PackedStringArray = reader.get_files()
	for file_path: String in files:
		if file_path.ends_with("/"):
			root_dir.make_dir_recursive(file_path)
			continue
		root_dir.make_dir_recursive(root_dir.get_current_dir().path_join(file_path).get_base_dir())
		var file: FileAccess = FileAccess.open(root_dir.get_current_dir().path_join(file_path), FileAccess.WRITE)
		var buffer: PackedByteArray = reader.read_file(file_path)
		file.store_buffer(buffer)
	reader.close()
	remove_item("%s/sscdb.zip" % ProjectSettings.globalize_path("user://"))
	DirAccess.rename_absolute("user://sscdb-main", "user://sscdb")

func remove_item(path: String) -> void: # because godot's builtin one has privelage issues
	match OS.get_name().to_lower():
		"linux":
			OS.execute("rm", ["-rf", path])
		"windows":
			var fixed_path: String = path.replace("/", "\\")
			OS.execute("del", ["/F", "/Q", fixed_path])

func make_dir(path: String) -> void:
	match OS.get_name().to_lower():
		"linux":
			OS.execute("mkdir", ["-p", path])
		"windows":
			var fixed_path: String = path.replace("/", "\\")
			OS.execute("powershell", [
				"-WindowStyle", "Hidden",
				"-Command", "New-Item -ItemType Directory -Path '%s' -Force" % fixed_path
			])
#endregion

#region builtin methods
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("bg_toggle"):
		$particles.visible = not $particles.visible
	elif event.is_action_pressed("music_toggle"):
		$music.playing = not $music.playing
	elif event.is_action_pressed("refresh"):
		%log.clear()
		times_refreshed += 1
		timer = 0.0
		append_warning("helper refreshed (%s)" % str(times_refreshed))
		br()
		_ready()
	elif event.is_action_pressed("exit"):
		get_tree().quit()

func _ready() -> void:
	append_reg("SSCHelper version %s" % ProjectSettings.get("application/config/version"))
	br()
	append_notice("press m to toggle music")
	append_notice("press p to toggle background blobs")
	append_notice("press ctrl + r to re-run the helper")
	br()
	var system: String = OS.get_name().to_lower()
	append_reg("system is running %s" % system)
	match system:
		"linux":
			inline_wait("locating sober content directory")
			if DirAccess.dir_exists_absolute("%s/.var/app/org.vinegarhq.Sober/data/sober/assets/content" % OS.get_environment("HOME")):
				content_path = "%s/.var/app/org.vinegarhq.Sober/data/sober/assets/content" % OS.get_environment("HOME")
				inline_result(ResultType.SUCCESS)
			else:
				inline_result(ResultType.FAIL)
				append_err("could not find Sober content directory; is Sober installed?")
				append_notice("try running 'flatpak install org.vinegarhq.Sober' in your terminal emulator")
				fatal_stop()
				return
		"windows":
			inline_wait("locating latest player content directory")
			var version_dir: String = "C:/Users/%s/AppData/Local/Roblox/Versions" % OS.get_environment("USERNAME")
			var sorted_versions: Array[Dictionary]
			var version_errors: int = 0
			if DirAccess.dir_exists_absolute(version_dir):
				for version in DirAccess.get_directories_at(version_dir):
					var version_is_player: bool = true
					for file in DirAccess.get_files_at(version_dir + version):
						if file.contains("Studio"): version_is_player = false
					if version_is_player:
						sorted_versions.append({
							"name": version,
							"modified": FileAccess.get_modified_time(version_dir + version)
						})
				sorted_versions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return b.modified < a.modified)
				content_path = "%s/%s/content" % [version_dir, sorted_versions[0].name]
				inline_result(ResultType.SUCCESS)
			else:
				inline_result(ResultType.FAIL)
				append_err("could not find regular player")
			inline_wait("checking for alternative bootstrappers")
			version_dir = "C:/Users/%s/AppData/Local/Fishstrap/Modifications" % OS.get_environment("USERNAME")
			if DirAccess.dir_exists_absolute(version_dir):
				make_dir("%s/content" % version_dir)
				content_path = "%s/content" % version_dir
			else:
				version_errors += 1
				version_dir = "C:/Users/%s/AppData/Local/Bloxstrap/Modifications" % OS.get_environment("USERNAME")
				if DirAccess.dir_exists_absolute(version_dir):
					make_dir("%s/content" % version_dir)
					content_path = "%s/content" % version_dir
				else:
					version_errors += 1
			if version_errors >= 2:
				inline_result(ResultType.FAIL)
				append_err("could not find alternative bootstrapper")
				fatal_stop()
			else:
				inline_result(ResultType.SUCCESS)
				var client_name: String
				match version_errors:
					0: client_name = "fishstrap"
					1: client_name = "bloxstrap"
					_: client_name = "alternative bootstrapper"
				append_reg("found %s" % client_name)
			return
		_:
			append_err("unsupported operating system")
			fatal_stop()
			return
	inline_wait("fetching latest SSCDatabase")
	if await fetch_latest_db("user:///sscdb.zip"):
		inline_result(ResultType.SUCCESS)
	else:
		inline_result(ResultType.FAIL)
		append_err("unable to fetch database; are you connected to the internet?")
		fatal_stop()
		return
	inline_wait("extracting fetched database")
	extract_fetched_db("user://")
	inline_result(ResultType.SUCCESS)
	if DirAccess.dir_exists_absolute("%s/ssc" % content_path):
		append_reg("found existing fetched database, queued to replace")
		print("%s/ssc" % content_path)
		remove_item("%s/ssc" % content_path)
	inline_wait("cleaning up")
	DirAccess.rename_absolute("user://sscdb", "%s/ssc" % content_path)
	inline_result(ResultType.SUCCESS)
	if DirAccess.dir_exists_absolute("user://custom"):
		append_reg("found custom chart data")
		inline_wait("syncing customs with local database")
		if len(DirAccess.get_directories_at("user://custom")) == 2:
			DirAccess.make_dir_absolute("%s/ssc/custom" % content_path)
			DirAccess.make_dir_absolute("%s/ssc/custom/aud" % content_path)
			DirAccess.make_dir_absolute("%s/ssc/custom/img" % content_path)
			for img: String in DirAccess.get_files_at("user://custom/img"):
				DirAccess.copy_absolute("user://custom/img/%s" % img, "%s/ssc/custom/img/%s" % [content_path, img])
			for aud: String in DirAccess.get_files_at("user://custom/aud"):
				DirAccess.copy_absolute("user://custom/aud/%s" % aud, "%s/ssc/custom/aud/%s" % [content_path, aud])
			inline_result(ResultType.SUCCESS)
		else:
			inline_result(ResultType.FAIL)
			append_err("invalid custom folder structure, skipping")
	process_complete()
	return

func _process(delta: float) -> void:
	timer += delta
#endregion
