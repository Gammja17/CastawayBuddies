class_name Condition
extends RefCounted
## v2 번거로운 몸 상태: 젖음 · 추위 · 배탈 · 피 흘림. 내 캐릭터만 계산한다.

const BLEED_TIME := 45.0     # 붕대 안 감으면 이만큼 피를 흘리다 멎는다 (그리고 곪을 수도)
const SICK_RAW := 60.0
const SICK_ROTTEN := 90.0

var wet := 0.0        # 0~1
var cold := 0.0       # 0~1 (0.5 넘으면 덜덜, 체력이 깎인다)
var sick := 0.0       # 남은 배탈 시간(초)
var bleed := 0.0      # 남은 출혈 시간(초)
var sheltered := false
var warm := false     # 불 옆
var _vomit_t := 20.0


func tick(p: Player, delta: float) -> void:
	var g := Game.I
	var clock := g.clock
	sheltered = _roof_over(p)
	warm = g.near_fire(p.global_position, 3.5)
	# 젖기 / 마르기
	if p.swimming or p.global_position.y < Terrain.WATER_Y - 0.3:
		wet = 1.0
	elif clock.raining and not sheltered and p.held_id != "palm_leaf":
		wet = minf(1.0, wet + delta / 40.0)
	else:
		var dry := 1.0 / 90.0
		if warm:
			dry = 1.0 / 15.0
		elif clock.is_night():
			dry = 1.0 / 240.0
		wet = maxf(0.0, wet - delta * dry)
	# 추위: 밤·폭풍·젖음이면 추워지고, 지붕 밑이나 불 옆이면 덜하다
	var chill := 0.0
	if clock.is_night():
		chill += 0.45
	if clock.storm:
		chill += 0.3
	chill += wet * 0.6
	if sheltered:
		chill -= 0.25
	var target := clampf(chill - 0.4, 0.0, 1.0)
	if warm:
		target = 0.0
	cold = move_toward(cold, target, delta / (20.0 if target < cold else 45.0))
	# 배탈 / 출혈 시간 줄이기
	if sick > 0.0:
		sick = maxf(0.0, sick - delta)
		_vomit_t -= delta
		if _vomit_t <= 0.0:
			_vomit_t = randf_range(20.0, 35.0)
			p.hunger = maxf(0.0, p.hunger - 8.0)
			p.thirst = maxf(0.0, p.thirst - 8.0)
			g.hud.toast("우웨엑!! 배탈이다...", Color("b8e07a"))
			Audio.play_at("hurt", p.global_position, -2.0, 0.6)
			g.shake_camera(0.15, Vector3.INF)
	if bleed > 0.0:
		bleed = maxf(0.0, bleed - delta)
		if bleed <= 0.0 and randf() < 0.5:
			sick = maxf(sick, SICK_RAW)
			g.hud.toast("피는 멎었는데 상처가 곪았다... (배탈)", Color("ffb07a"))


func drain_mult() -> float:
	## 배고픔·목마름 줄어드는 배수
	return (1.5 if sick > 0.0 else 1.0) * (1.3 if cold > 0.5 else 1.0)


func hp_loss() -> float:
	## 초당 체력 손해
	var n := 0.0
	if bleed > 0.0:
		n += 0.35
	if cold > 0.5:
		n += 0.3 * cold
	return n


func blocks_regen() -> bool:
	return sick > 0.0 or bleed > 0.0 or cold > 0.5


func start_bleed() -> void:
	bleed = BLEED_TIME


func status_bbcode() -> String:
	var parts: Array = []
	if bleed > 0.0:
		parts.append("[color=#ff6a5a]피 흘림 (붕대!)[/color]")
	if sick > 0.0:
		parts.append("[color=#b8e07a]배탈[/color]")
	if cold > 0.5:
		parts.append("[color=#a8d8ff]덜덜 추움[/color]")
	elif cold > 0.2:
		parts.append("[color=#c8e4ff]쌀쌀[/color]")
	if wet > 0.3:
		parts.append("[color=#7ac8ff]젖음[/color]")
	if warm:
		parts.append("[color=#ffcf7a]따뜻[/color]")
	return "  ".join(parts)


func to_dict() -> Dictionary:
	return {"wet": wet, "cold": cold, "sick": sick, "bleed": bleed}


func from_dict(d: Dictionary) -> void:
	wet = d.get("wet", 0.0)
	cold = d.get("cold", 0.0)
	sick = d.get("sick", 0.0)
	bleed = d.get("bleed", 0.0)


func _roof_over(p: Player) -> bool:
	## 머리 위에 지붕·바닥·동굴 천장이 있나
	var from := p.global_position + Vector3.UP * 1.9
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8.0, 1 | 2)
	q.exclude = [p.get_rid()]
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
