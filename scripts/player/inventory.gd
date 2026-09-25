class_name Inventory
extends RefCounted
## 가방 36칸 (0~8 = 단축바). 칸 = null 또는 {"id", "n", "d"(내구도, 도구만), "a"(상한 정도(초), 썩는 음식만)}

signal changed

const SIZE := 36
const HOTBAR := 9

var slots: Array = []


func _init() -> void:
	slots.resize(SIZE)


static func add_to_slots(arr: Array, id: String, n: int, d: int = -1) -> int:
	## 칸 배열에 넣고 남은 개수를 돌려준다
	var stack := Items.max_stack(id)
	if stack > 1:
		for i in arr.size():
			var s = arr[i]
			if s != null and s.id == id and s.n < stack:
				var put := mini(n, stack - s.n)
				if s.has("a"):
					s.a = s.a * s.n / float(s.n + put)   # 새것과 섞이면 평균만큼 싱싱해진다
				s.n += put
				n -= put
				if n <= 0:
					return 0
	for i in arr.size():
		if arr[i] == null:
			var put := mini(n, stack)
			var s := {"id": id, "n": put}
			var tool := Items.tool_of(id)
			if stack == 1 and not tool.is_empty():
				s.d = d if d > 0 else tool.get("dur", 100)
			if Items.SPOIL.has(id):
				s.a = 0.0
			arr[i] = s
			n -= put
			if n <= 0:
				return 0
	return n


func add(id: String, n: int, d: int = -1) -> int:
	var left := add_to_slots(slots, id, n, d)
	changed.emit()
	return left


func count(id: String) -> int:
	var c := 0
	for s in slots:
		if s != null and s.id == id:
			c += s.n
	return c


func has_all(req: Dictionary) -> bool:
	for id in req:
		if count(id) < req[id]:
			return false
	return true


func remove(id: String, n: int) -> int:
	## 뺀 개수. 단축바 뒤쪽 칸부터 뺀다 (손에 든 걸 덜 건드리게)
	var removed := 0
	for i in range(SIZE - 1, -1, -1):
		var s = slots[i]
		if s != null and s.id == id:
			var take := mini(n - removed, s.n)
			s.n -= take
			removed += take
			if s.n <= 0:
				slots[i] = null
			if removed >= n:
				break
	changed.emit()
	return removed


func remove_all(req: Dictionary) -> void:
	for id in req:
		remove(id, req[id])


func take_slot(i: int, n: int = -1) -> Dictionary:
	var s = slots[i]
	if s == null:
		return {}
	var out: Dictionary = s.duplicate()
	if n < 0 or n >= s.n:
		slots[i] = null
	else:
		s.n -= n
		out.n = n
	changed.emit()
	return out


func swap(a: int, b: int) -> void:
	var t = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	changed.emit()


func merge_or_swap(from: int, to: int) -> void:
	if from == to:
		return
	var a = slots[from]
	var b = slots[to]
	if a != null and b != null and a.id == b.id and Items.max_stack(a.id) > 1:
		var stack := Items.max_stack(a.id)
		var put := mini(a.n, stack - b.n)
		if b.has("a"):
			b.a = (b.a * b.n + a.get("a", 0.0) * put) / float(b.n + put)
		b.n += put
		a.n -= put
		if a.n <= 0:
			slots[from] = null
		changed.emit()
		return
	swap(from, to)


func use_durability(i: int, amount: int = 1) -> bool:
	## 도구 내구도 깎기. 부서지면 true
	var s = slots[i]
	if s == null or not s.has("d"):
		return false
	s.d -= amount
	if s.d <= 0:
		slots[i] = null
		changed.emit()
		return true
	changed.emit()
	return false


func age_food(sec: float) -> int:
	## 음식이 sec 초만큼 상한다. 썩어 버린 칸 수를 돌려준다
	var rotted := 0
	var any := false
	for i in SIZE:
		var s = slots[i]
		if s == null or not Items.SPOIL.has(s.id):
			continue
		any = true
		s.a = s.get("a", 0.0) + sec
		if s.a >= Items.SPOIL[s.id]:
			slots[i] = {"id": "rotten_food", "n": s.n}
			rotted += 1
	if any:
		changed.emit()
	return rotted


func free_space_for(id: String) -> int:
	var stack := Items.max_stack(id)
	var room := 0
	for s in slots:
		if s == null:
			room += stack
		elif s.id == id:
			room += stack - s.n
	return room


func to_array() -> Array:
	return slots.duplicate(true)


func from_array(arr: Array) -> void:
	slots = []
	slots.resize(SIZE)
	for i in mini(arr.size(), SIZE):
		if arr[i] != null and arr[i] is Dictionary and not Items.item(arr[i].get("id", "")).is_empty():
			slots[i] = arr[i].duplicate()
	changed.emit()
