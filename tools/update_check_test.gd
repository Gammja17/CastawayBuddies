extends Node
## 자동 업데이트 확인: 진짜 GitHub 최신 릴리스 읽기 + 받기 주소 따라가기 (앞부분만): godot --headless --path . tools/update_check_test.tscn

const Updater := preload("res://scripts/ui/updater.gd")


func _ready() -> void:
	for c in [["v2.1.0", "2.0.0"], ["v2.0.0", "2.0.0"], ["v10.0.0", "9.9.9"], ["v2.0.1", "2.0.10"], ["2.1", "2.0.9"]]:
		print("새 버전? %s > %s : %s" % [c[0], c[1], Updater.is_newer(c[0], c[1])])
	var http := HTTPRequest.new()
	add_child(http)
	http.request(Updater.API, ["Accept: application/vnd.github+json", "User-Agent: CastawayBuddies"])
	var r: Array = await http.request_completed
	var data = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	print("GitHub 응답 %d/%d 최신 %s" % [r[0], r[1], data.get("tag_name", "?") if data is Dictionary else "?"])
	var url := ""
	for a in data.get("assets", []):
		if a.name == Updater.ASSET:
			url = a.browser_download_url
	var dl := HTTPRequest.new()
	dl.body_size_limit = 4096   # 앞부분만
	add_child(dl)
	dl.request(url, ["User-Agent: CastawayBuddies"])
	var r2: Array = await dl.request_completed
	print("받기 주소 따라가기: 결과 %d (%d = 크기 제한에 걸림 = 받기 시작함) 코드 %d" % [r2[0], HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, r2[1]])
	get_tree().quit()
