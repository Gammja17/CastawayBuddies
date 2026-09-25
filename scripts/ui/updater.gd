extends PanelContainer
## 타이틀 오른쪽 위: GitHub 최신 릴리스를 확인해서, 새 버전이면 exe 를 받아 바꿔 끼우고 다시 켠다 (Windows PC판만).
## 새 버전 올리는 법: project.godot 의 버전을 올리고, 같은 번호의 태그(v2.1.0)로 CastawayBuddies.exe 를 릴리스에 올린다.
## 개발용: -- --update-url=<주소> (최신 릴리스 JSON 을 다른 데서 받기), -- --update-now (묻지 않고 바로 받기)

const API := "https://api.github.com/repos/Gammja17/CastawayBuddies/releases/latest"
const RELEASES := "https://github.com/Gammja17/CastawayBuddies/releases/latest"
const ASSET := "CastawayBuddies.exe"

@onready var info: Label = %UpdateInfo
@onready var bar: ProgressBar = %UpdateBar
@onready var go_btn: Button = %UpdateGo
@onready var later_btn: Button = %UpdateLater

var _http: HTTPRequest
var _asset := {}      # {"tag", "url", "size", "digest"}
var _target := ""     # 받는 중인 새 exe


func _ready() -> void:
	visible = false
	set_process(false)
	if not can_update():
		return
	_cleanup()
	go_btn.pressed.connect(_download)
	later_btn.pressed.connect(hide)
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_checked)
	_http.request(_arg("--update-url=", API), ["Accept: application/vnd.github+json", "User-Agent: CastawayBuddies"])


static func can_update() -> bool:
	## 내보낸 Windows exe 에서만 (에디터·웹판은 안 한다)
	return OS.has_feature("windows") and OS.has_feature("template") and OS.get_executable_path().get_extension().to_lower() == "exe"


static func is_newer(tag: String, current: String) -> bool:
	## "v2.1.0" 이 "2.0.0" 보다 새 버전인가
	var a := tag.trim_prefix("v").split(".")
	var b := current.trim_prefix("v").split(".")
	for i in maxi(a.size(), b.size()):
		var x := a[i].to_int() if i < a.size() else 0
		var y := b[i].to_int() if i < b.size() else 0
		if x != y:
			return x > y
	return false


func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return fallback


func _cleanup() -> void:
	## 지난번 업데이트에서 남은 파일 치우기 (옛 exe 는 이제 안 돌고 있다)
	var exe := OS.get_executable_path()
	for f in [_old_path(exe), exe.get_base_dir().path_join("CastawayBuddies.update.exe")]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func _old_path(exe: String) -> String:
	return exe.get_basename() + ".old.exe"


func _on_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return   # 인터넷이 없거나 GitHub 이 바쁘다. 조용히 넘어간다
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	var tag: String = str(data.get("tag_name", ""))
	var current: String = ProjectSettings.get_setting("application/config/version", "0")
	if not is_newer(tag, current):
		return
	for a in data.get("assets", []):
		if a is Dictionary and a.get("name", "") == ASSET:
			_asset = {"tag": tag, "url": a.get("browser_download_url", ""), "size": int(a.get("size", 0)), "digest": str(a.get("digest", ""))}
	if _asset.is_empty():
		return
	info.text = "새 버전 %s 나왔다! (지금 v%s)\n받으면 알아서 다시 켜진다. 친구도 같이 업데이트!" % [tag, current]
	visible = true
	Audio.play("quest", -6.0)
	if "--update-now" in OS.get_cmdline_user_args():
		_download()


func _download() -> void:
	if _asset.is_empty() or _target != "":
		return
	_target = OS.get_executable_path().get_base_dir().path_join("CastawayBuddies.update.exe")
	var probe := FileAccess.open(_target, FileAccess.WRITE)
	if probe == null:
		_fail("이 폴더에는 쓸 수 없어서 못 바꾼다. 릴리스 페이지에서 직접 받아 줘")
		return
	probe.close()
	go_btn.disabled = true
	later_btn.disabled = true
	bar.visible = true
	bar.value = 0.0
	info.text = "%s 받는 중..." % _asset.tag
	var dl := HTTPRequest.new()
	dl.download_file = _target
	dl.use_threads = true
	add_child(dl)
	dl.request_completed.connect(_on_downloaded.bind(dl))
	if dl.request(_asset.url, ["User-Agent: CastawayBuddies"]) != OK:
		_fail("받기를 시작하지 못했다")
		return
	_http = dl
	set_process(true)


func _process(_delta: float) -> void:
	if _http and _asset.get("size", 0) > 0:
		bar.value = 100.0 * _http.get_downloaded_bytes() / float(_asset.size)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, dl: HTTPRequest) -> void:
	set_process(false)
	dl.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("받다가 끊겼다 (%d/%d). 나중에 다시 해 보자" % [result, code])
		return
	# 제대로 받았나: 크기, 그리고 GitHub 이 알려 준 SHA-256 지문
	var f := FileAccess.open(_target, FileAccess.READ)
	var size := f.get_length() if f else -1
	if f:
		f.close()
	if size != _asset.size:
		_fail("받은 파일 크기가 이상하다 (%d / %d)" % [size, _asset.size])
		return
	if _asset.digest.begins_with("sha256:") and FileAccess.get_sha256(_target) != _asset.digest.trim_prefix("sha256:"):
		_fail("받은 파일 지문이 안 맞는다. 다시 받아 보자")
		return
	# 돌고 있는 exe 는 지울 순 없어도 이름은 바꿀 수 있다 → 옛것은 .old 로, 새것을 제자리에
	var exe := OS.get_executable_path()
	var old := _old_path(exe)
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(exe, old) != OK:
		_fail("exe 를 바꿔 끼우지 못했다. 릴리스 페이지에서 직접 받아 줘")
		return
	if DirAccess.rename_absolute(_target, exe) != OK:
		DirAccess.rename_absolute(old, exe)   # 되돌리기
		_fail("exe 를 바꿔 끼우지 못했다. 릴리스 페이지에서 직접 받아 줘")
		return
	info.text = "%s 로 바꿨다! 다시 켜는 중..." % _asset.tag
	OS.create_process(exe, OS.get_cmdline_args())   # 켤 때 준 설정(창 크기 등) 그대로
	get_tree().quit()


func _fail(text: String) -> void:
	set_process(false)
	if _target != "" and FileAccess.file_exists(_target):
		DirAccess.remove_absolute(_target)
	_target = ""
	bar.visible = false
	info.text = text
	go_btn.text = "릴리스 페이지 열기"
	go_btn.disabled = false
	later_btn.disabled = false
	if go_btn.pressed.is_connected(_download):
		go_btn.pressed.disconnect(_download)
		go_btn.pressed.connect(func(): OS.shell_open(RELEASES))
	visible = true
