extends Node
## Looks for a newer build when the game starts and offers an update.
##
## CI writes res://config/build.json ({sha, branch, repo}) into every build. On start:
## - Web (also the installed web app): asks the service worker to look for a new version (Godot's
##   built-in PWA update support) and compares our sha with version.json published next to the game.
## - Android: compares our sha with the commit of the latest APK release for this branch on GitHub.
## Without build.json (running from the editor or tests) nothing is checked.

signal update_available

const BUILD_PATH := "res://config/build.json"

var available := false
var build: Dictionary = {}
var _release_url := ""
var _http: HTTPRequest


func _ready() -> void:
	if FileAccess.file_exists(BUILD_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(BUILD_PATH))
		if typeof(d) == TYPE_DICTIONARY:
			build = d
	if build.is_empty():
		return
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_response)
	if OS.has_feature("web"):
		_check_web()
	elif OS.has_feature("android"):
		var url := "https://api.github.com/repos/%s/releases/tags/build-%s" % [build.get("repo", ""), build.get("branch", "")]
		_http.request(url, ["Accept: application/vnd.github+json", "User-Agent: RogueCards-updater"])


func _check_web() -> void:
	# A new service worker waiting means the installed app has a newer version ready.
	JavaScriptBridge.pwa_update_available.connect(_mark_available)
	if JavaScriptBridge.pwa_needs_update():
		_mark_available()
	JavaScriptBridge.eval("if (navigator.serviceWorker) navigator.serviceWorker.getRegistration().then(function (r) { if (r) r.update(); });", true)
	# Also ask the server directly (works even without a service worker), bypassing caches.
	var base: String = str(JavaScriptBridge.eval("location.href.split('?')[0].split('#')[0].replace(/[^/]*$/, '')", true))
	if base.begins_with("http"):
		_http.request(base + "version.json?t=%d" % Time.get_unix_time_from_system(), ["Cache-Control: no-cache"])


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY:
		return
	var remote_sha := ""
	if OS.has_feature("android"):
		remote_sha = str(d.get("target_commitish", ""))
		_release_url = str(d.get("html_url", ""))
	else:
		remote_sha = str(d.get("sha", ""))
	if remote_sha != "" and remote_sha != str(build.get("sha", "")):
		_mark_available()


func _mark_available() -> void:
	if available:
		return
	available = true
	update_available.emit()


## Installs the update: the web app swaps in the new version and reloads; Android opens the APK release.
func apply() -> void:
	if OS.has_feature("web"):
		if not JavaScriptBridge.pwa_needs_update():
			# The new version may not be downloaded yet: ask for it and give it a few seconds.
			JavaScriptBridge.eval("if (navigator.serviceWorker) navigator.serviceWorker.getRegistration().then(function (r) { if (r) r.update(); });", true)
			for i in 30:
				await get_tree().create_timer(0.2).timeout
				if JavaScriptBridge.pwa_needs_update():
					break
		if JavaScriptBridge.pwa_needs_update():
			JavaScriptBridge.pwa_update()  # activates the new version and reloads
		else:
			JavaScriptBridge.eval("location.reload()", true)
	elif _release_url != "":
		OS.shell_open(_release_url)
