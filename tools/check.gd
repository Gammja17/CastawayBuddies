extends Node
## 모든 스크립트·씬을 불러 보며 문법 오류를 찾는다: godot --headless --path . tools/check.tscn


func _ready() -> void:
	var bad := 0
	for dir in ["res://scripts", "res://scenes"]:
		for f in _files(dir):
			if f.ends_with(".gd") or f.ends_with(".tscn"):
				var r = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
				if r == null:
					print("로드 실패: ", f)
					bad += 1
				elif r is GDScript and not (r as GDScript).can_instantiate():
					print("컴파일 실패: ", f)
					bad += 1
	print("검사 끝. 문제 %d 개" % bad)
	get_tree().quit()


func _files(path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(path)
	if d == null:
		return out
	for f in d.get_files():
		out.append(path + "/" + f)
	for sub in d.get_directories():
		out.append_array(_files(path + "/" + sub))
	return out
