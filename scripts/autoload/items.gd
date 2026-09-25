extends Node
## 게임 데이터 창고: 아이템 · 구조물 · 조합법 · 전리품 표.
## 숫자는 전부 여기서 고친다.

const DEFAULT_STACK := 50

# v2 번거로운 생존
const SPOIL := {"raw_fish": 300.0, "big_fish": 300.0, "crab_meat": 240.0, "cooked_fish": 900.0, "cooked_big_fish": 900.0,
	"cooked_crab": 900.0, "baked_potato": 1200.0, "fish_soup": 600.0, "berries": 900.0}   # 가방에서 썩기까지 (초)
const RAW := ["raw_fish", "big_fish", "crab_meat"]    # 날로 먹으면 배탈 날 수 있다
const GRILL := {"raw_fish": "cooked_fish", "big_fish": "cooked_big_fish", "crab_meat": "cooked_crab", "potato": "baked_potato"}
const COOK_T := 20.0      # 석쇠에서 익는 시간
const BURN_T := 50.0      # 이만큼 두면 탄다
const FUEL := {"wood": 120.0, "plank": 60.0, "stick": 40.0, "palm_leaf": 25.0, "fiber": 10.0}   # 모닥불 장작 (초)
const FUEL_MAX := 600.0

# v2 도구 직접 조립: 모양 + 날(재료) + 묶는 것 + 자루. 조립한 도구 id 는 "tool:모양:재료:묶기:자루"
const TOOL_SHAPES := {"axe": "도끼", "pick": "곡괭이", "shovel": "삽", "spear": "창"}
const TOOL_MATS := {
	# 재료: [이름, 도끼 힘, 곡괭이 힘, 삽 힘, 창 공격, 내구도, 날에 드는 개수]
	"flint": ["부싯돌", 3, 2, 1, 6, 50, 1],
	"stone": ["돌", 2, 3, 2, 3, 70, 2],
	"iron": ["쇠", 7, 7, 5, 9, 220, 2],
	"scrap": ["고철", 4, 4, 3, 6, 110, 2],
	"shark_tooth": ["상어이빨", 3, 1, 1, 13, 90, 2],
	"shell": ["조개껍데기", 2, 1, 3, 4, 45, 2],
	"coconut_shell": ["코코넛", 1, 1, 3, 1, 35, 1],
	"plank": ["나무판", 1, 1, 3, 2, 60, 1],
	"golden_shell": ["황금 조개", 2, 2, 4, 5, 500, 1],
}
const BINDINGS := {"fiber": ["허술한 ", 0.6, 2], "rope": ["", 1.0, 1], "cloth": ["튼튼한 ", 1.3, 1]}   # [앞말, 내구 배수, 개수]
const HANDLES := {"stick": ["", 1.0, 0], "plank": ["묵직한 ", 1.25, 1]}   # [앞말, 내구 배수, 힘 보너스]

var _dyn := {}   # 조립 도구 정의 캐시


# 아이템. stack 기본 50, 도구는 1.
# food: hunger/thirst/hp 회복, ret = 먹고 돌려받는 아이템
# tool: kind(axe/pick/shovel/spear/rod/hook/torch), power(채집력), dmg(공격력), dur(내구도)
# fill: 땅에 우클릭으로 부을 수 있음 / struct: 설치하면 되는 구조물 id
# vis: 3D 모양. "m:킷/모델" 이면 Kenney GLB, 아니면 Vis 가 도형으로 만든다.
var ITEMS := {
	# ── 재료 ──
	"wood": {"name": "통나무", "desc": "나무를 패면 나온다. 거의 모든 것의 시작. 물을 보고 우클릭하면 띄운다 (4개 이상 나란히 띄워 밧줄로 묶으면 뗏목).", "vis": "m:survival/resource-wood"},
	"plank": {"name": "판자", "desc": "통나무를 쪼갠 것. 건축과 조합에 쓴다.", "vis": "m:survival/resource-planks"},
	"stick": {"name": "막대기", "desc": "평범한 막대기. 친구를 찌르지 말 것.", "vis": {"s": "cyl", "c": "9b6a3a", "sz": [0.05, 0.7, 0.05], "rot": [0, 0, 60]}},
	"palm_leaf": {"name": "야자잎", "desc": "야자수에서 떨어진 큰 잎. 지붕, 침대, 횃불 재료. 손에 들면 비를 가려 준다 (우산).", "vis": {"s": "box", "c": "4caf3f", "sz": [0.5, 0.04, 0.22]}},
	"fiber": {"name": "섬유", "desc": "덤불에서 뜯은 질긴 풀. 꼬면 밧줄이 된다.", "vis": {"s": "box", "c": "9ccc4a", "sz": [0.12, 0.35, 0.12]}},
	"rope": {"name": "밧줄", "desc": "섬유를 꼬아 만든 밧줄. 무인도의 접착제.", "vis": {"s": "torus", "c": "c7a86b", "sz": [0.35, 0.35, 0.35]}},
	"stone": {"name": "돌멩이", "desc": "바닥에 굴러다니거나 바위를 캐면 나온다.", "vis": "m:survival/resource-stone"},
	"flint": {"name": "부싯돌", "desc": "날카로운 돌. 창끝과 갈고리에 쓴다.", "vis": {"s": "prism", "c": "3d3f46", "sz": [0.22, 0.14, 0.18]}},
	"sand": {"name": "모래 한 줌", "desc": "물가를 보고 우클릭하면 부어서 땅을 만든다. 화덕에 녹이면 유리.", "fill": true, "vis": {"s": "sphere", "c": "e3cf94", "sz": [0.34, 0.18, 0.34]}},
	"dirt": {"name": "흙 한 줌", "desc": "땅에 우클릭으로 부어 높이거나 물을 메운다. 밭 만들 때도 쓴다.", "fill": true, "vis": {"s": "sphere", "c": "7d5b3a", "sz": [0.34, 0.18, 0.34]}},
	"clay": {"name": "점토", "desc": "물가의 붉은 흙. 화덕에서 구우면 벽돌.", "vis": {"s": "sphere", "c": "b9876e", "sz": [0.3, 0.2, 0.3]}},
	"iron_ore": {"name": "철광석", "desc": "돌섬 동굴에서 캔다. 화덕에서 녹이면 철.", "vis": {"s": "sphere", "c": "8b6f60", "sz": [0.3, 0.25, 0.3]}},
	"glass": {"name": "유리", "desc": "모래를 녹인 것. 병을 만든다.", "vis": {"s": "box", "c": "bfe9ff", "sz": [0.3, 0.05, 0.3]}},
	"iron": {"name": "철 주괴", "desc": "반짝반짝. 철 도구의 재료.", "vis": {"s": "box", "c": "c9ced6", "sz": [0.3, 0.12, 0.16]}},
	"scrap": {"name": "고철", "desc": "난파선이나 떠다니는 잔해에서 나온다. 녹이면 철.", "vis": {"s": "box", "c": "7a6a60", "sz": [0.3, 0.06, 0.25], "rot": [0, 20, 10]}},
	"plastic": {"name": "플라스틱", "desc": "바다에 떠다니는 쓰레기. 2개를 녹여 붙이면 빈 병이 된다.", "vis": {"s": "box", "c": "5ec8e5", "sz": [0.28, 0.05, 0.2]}},
	"cloth": {"name": "천", "desc": "찢어진 돛 조각. 돛, 붕대, 토템에 쓴다.", "vis": {"s": "box", "c": "efe8d8", "sz": [0.35, 0.04, 0.3]}},
	"brick": {"name": "벽돌", "desc": "점토를 구운 것. 마을 토템 재료.", "vis": {"s": "box", "c": "b5553c", "sz": [0.3, 0.12, 0.15]}},
	"shell": {"name": "조개껍데기", "desc": "해변에서 줍는 예쁜 조개. 장식과 토템에 쓴다.", "vis": {"s": "cone", "c": "f4c9b8", "sz": [0.22, 0.12, 0.22]}},
	"golden_shell": {"name": "황금 조개", "desc": "눈부시게 빛나는 조개. 어딘가에서 이걸 원하는 존재가 있다는데...", "vis": {"s": "cone", "c": "ffd23f", "sz": [0.3, 0.16, 0.3], "glow": true}},
	"shark_tooth": {"name": "상어 이빨", "desc": "상어한테서 뽑았다(?). 무시무시한 창을 만들 수 있다.", "vis": {"s": "prism", "c": "f5f1e6", "sz": [0.12, 0.2, 0.06]}},
	"bottle": {"name": "빈 병", "desc": "바다를 보며 우클릭하면 바닷물을 담는다.", "vis": "m:survival/bottle"},
	"compass": {"name": "선장의 나침반", "desc": "탈출선에 꼭 필요한 나침반. 바늘이 계속 북쪽... 아니 거북이 쪽을 가리킨다?", "stack": 1, "vis": {"s": "cyl", "c": "d4a93a", "sz": [0.26, 0.06, 0.26]}},
	"clockwork": {"name": "태엽 뭉치", "desc": "난파선 선장실에서 나온 톱니바퀴 덩어리.", "vis": {"s": "torus", "c": "b08d57", "sz": [0.25, 0.25, 0.25]}},
	# ── 음식 ──
	"coconut": {"name": "코코넛", "desc": "우클릭으로 먹고 마신다. 배고픔 +8, 목마름 +22. 껍데기는 컵이 된다.", "food": {"hunger": 8, "thirst": 22, "ret": "coconut_shell"}, "vis": {"s": "sphere", "c": "6b4423", "sz": [0.28, 0.28, 0.28]}},
	"berries": {"name": "산딸기", "desc": "덤불에서 딴 열매. 밭에 심을 수도 있다.", "food": {"hunger": 6, "thirst": 4}, "vis": {"s": "sphere", "c": "d8324a", "sz": [0.2, 0.2, 0.2]}},
	"raw_fish": {"name": "생선", "desc": "비리다. 날로 먹으면 배탈 날 수 있다. 불붙은 모닥불에 들고 E 로 석쇠에 올려 굽자.", "food": {"hunger": 8, "hp": -4}, "vis": "m:survival/fish"},
	"cooked_fish": {"name": "구운 생선", "desc": "노릇노릇. 배고픔 +30", "food": {"hunger": 30, "hp": 5}, "vis": {"s": "box", "c": "c77b36", "sz": [0.4, 0.12, 0.14]}},
	"big_fish": {"name": "대왕 생선", "desc": "팔뚝만 하다. 구우면 잔치다.", "food": {"hunger": 12, "hp": -6}, "vis": "m:survival/fish-large"},
	"cooked_big_fish": {"name": "대왕 생선구이", "desc": "배고픔 +55, 체력 +15", "food": {"hunger": 55, "hp": 15}, "vis": {"s": "box", "c": "b5652a", "sz": [0.6, 0.16, 0.2]}},
	"crab_meat": {"name": "게살", "desc": "날것. 구워 먹자.", "food": {"hunger": 6, "hp": -3}, "vis": {"s": "box", "c": "f08a7a", "sz": [0.2, 0.12, 0.12]}},
	"cooked_crab": {"name": "게살 구이", "desc": "배고픔 +25. 복수의 맛.", "food": {"hunger": 25, "hp": 5}, "vis": {"s": "box", "c": "e0552f", "sz": [0.22, 0.14, 0.14]}},
	"potato": {"name": "감자", "desc": "난파선에서 건진 씨감자. 밭에 심으면 불어난다.", "food": {"hunger": 5}, "vis": {"s": "sphere", "c": "c9a35e", "sz": [0.22, 0.17, 0.2]}},
	"baked_potato": {"name": "군감자", "desc": "호호 불어 먹는 맛. 배고픔 +28", "food": {"hunger": 28, "thirst": -3}, "vis": {"s": "sphere", "c": "8f6431", "sz": [0.23, 0.18, 0.21]}},
	"seaweed": {"name": "해초", "desc": "얕은 바다에서 뜯는다. 짭짤하다.", "food": {"hunger": 4, "thirst": 2}, "vis": {"s": "box", "c": "2f7d4f", "sz": [0.1, 0.4, 0.05]}},
	"salt_water": {"name": "바닷물", "desc": "마시면 더 목마르다. 모닥불에 끓이면 깨끗한 물.", "food": {"thirst": -15, "ret": "bottle"}, "vis": {"s": "cyl", "c": "3a8fd1", "sz": [0.14, 0.3, 0.14]}},
	"fresh_water": {"name": "깨끗한 물", "desc": "살 것 같다. 목마름 +45", "food": {"thirst": 45, "ret": "bottle"}, "vis": {"s": "cyl", "c": "a8e4ff", "sz": [0.14, 0.3, 0.14]}},
	"fish_soup": {"name": "생선 수프", "desc": "든든한 한 그릇. 배고픔 +45, 목마름 +25, 체력 +10", "food": {"hunger": 45, "thirst": 25, "hp": 10}, "vis": {"s": "cyl", "c": "e8c38a", "sz": [0.3, 0.14, 0.3]}},
	"bandage": {"name": "붕대", "desc": "우클릭으로 감는다. 피를 멈추고 체력 +30", "food": {"hp": 30}, "vis": {"s": "cyl", "c": "ffffff", "sz": [0.16, 0.16, 0.16], "rot": [90, 0, 0]}},
	"coconut_shell": {"name": "코코넛 껍데기", "desc": "코코넛을 먹고 남은 껍데기. 물가를 보고 우클릭하면 바닷물을 뜬다. 빗물받이에서도 쓴다.", "vis": {"s": "sphere", "c": "5a3a1e", "sz": [0.26, 0.13, 0.26]}},
	"shell_salt": {"name": "껍데기 바닷물", "desc": "코코넛 껍데기에 뜬 바닷물. 모닥불에 끓이자.", "food": {"thirst": -10, "ret": "coconut_shell"}, "vis": {"s": "sphere", "c": "3a8fd1", "sz": [0.26, 0.13, 0.26]}},
	"shell_water": {"name": "껍데기 물", "desc": "끓인 물 한 껍데기. 목마름 +22", "food": {"thirst": 22, "ret": "coconut_shell"}, "vis": {"s": "sphere", "c": "a8e4ff", "sz": [0.26, 0.13, 0.26]}},
	"rotten_food": {"name": "썩은 음식", "desc": "으... 먹으면 반드시 배탈. 자라는 밭에 들고 E 하면 거름이 된다.", "food": {"hunger": 3}, "vis": {"s": "box", "c": "5d6b3a", "sz": [0.3, 0.12, 0.2]}},
	"burnt_food": {"name": "탄 음식", "desc": "새까맣게 탔다. 배는 조금 찬다.", "food": {"hunger": 6, "thirst": -3}, "vis": {"s": "box", "c": "2a2420", "sz": [0.3, 0.12, 0.2]}},
	"seaweed_feast": {"name": "해초 잔치상", "desc": "해초와 생선과 코코넛으로 차린 거한 한 상. 먹는 용도가 아닌 것 같다.", "stack": 1, "vis": {"s": "cyl", "c": "3f8f5a", "sz": [0.6, 0.12, 0.6]}},
	# ── 도구 ──
	"stone_axe": {"name": "돌도끼", "desc": "나무를 빨리 벤다.", "tool": {"kind": "axe", "power": 3, "dmg": 3, "dur": 90}, "stack": 1, "vis": "m:survival/tool-axe"},
	"stone_pick": {"name": "돌곡괭이", "desc": "바위를 캐고, 바위 땅도 판다.", "tool": {"kind": "pick", "power": 3, "dmg": 3, "dur": 90}, "stack": 1, "vis": "m:survival/tool-pickaxe"},
	"shovel": {"name": "삽", "desc": "모래, 흙, 점토를 빨리 판다. 보물도 판다.", "tool": {"kind": "shovel", "power": 3, "dmg": 2, "dur": 120}, "stack": 1, "vis": "m:survival/tool-shovel"},
	"spear": {"name": "나무창", "desc": "게와 상어를 혼내준다.", "tool": {"kind": "spear", "power": 1, "dmg": 5, "dur": 70}, "stack": 1, "vis": {"s": "spear", "c": "9b6a3a", "tip": "3d3f46"}},
	"fishing_rod": {"name": "낚싯대", "desc": "바다를 보고 좌클릭으로 던지고, ! 가 뜨면 다시 좌클릭.", "tool": {"kind": "rod", "power": 1, "dmg": 1, "dur": 60}, "stack": 1, "vis": {"s": "rod", "c": "8b5a2b"}},
	"hook": {"name": "갈고리", "desc": "떠다니는 잔해를 멀리서 좌클릭으로 낚아챈다.", "tool": {"kind": "hook", "power": 1, "dmg": 2, "dur": 80}, "stack": 1, "vis": {"s": "hook", "c": "c7a86b"}},
	"iron_axe": {"name": "철도끼", "desc": "나무가 두 방.", "tool": {"kind": "axe", "power": 7, "dmg": 6, "dur": 300}, "stack": 1, "vis": "m:survival/tool-axe-upgraded"},
	"iron_pick": {"name": "철곡괭이", "desc": "돌이 두 방.", "tool": {"kind": "pick", "power": 7, "dmg": 6, "dur": 300}, "stack": 1, "vis": "m:survival/tool-pickaxe-upgraded"},
	"iron_spear": {"name": "철창", "desc": "든든한 무기.", "tool": {"kind": "spear", "power": 1, "dmg": 9, "dur": 220}, "stack": 1, "vis": {"s": "spear", "c": "6d4a2a", "tip": "c9ced6"}},
	"shark_spear": {"name": "상어이빨 창", "desc": "상어 이빨을 박은 무시무시한 창. 게 왕도 무섭지 않다.", "tool": {"kind": "spear", "power": 1, "dmg": 13, "dur": 180}, "stack": 1, "vis": {"s": "spear", "c": "6d4a2a", "tip": "f5f1e6"}},
	"bow_drill": {"name": "활비비", "desc": "막대를 활로 비벼 불씨를 만든다. 장작 넣은 모닥불을 보고 좌클릭을 꾹. 비 맞으면 안 붙는다.", "tool": {"kind": "firestarter", "power": 1, "dmg": 1, "dur": 25}, "stack": 1, "vis": {"s": "rod", "c": "8b5a2b"}},
	"crowbar": {"name": "쇠지렛대", "desc": "잠긴 상자를 비틀어 연다.", "tool": {"kind": "crowbar", "power": 2, "dmg": 4, "dur": 999}, "stack": 1, "vis": {"s": "hook", "c": "b53a2a"}},
	"torch": {"name": "횃불", "desc": "들고 있으면 주변이 밝고 밤게가 다가오지 못한다. 우클릭으로 꽂을 수도 있다.", "tool": {"kind": "torch", "power": 1, "dmg": 1, "dur": 999}, "struct": "torch", "vis": {"s": "torch"}},
	"raft": {"name": "뗏목", "desc": "통나무를 물에 나란히 띄우고 밧줄로 묶어 만든 뗏목. 바다를 보고 우클릭으로 띄운다. E 로 타고, 같이 탄 사람이 많을수록 빨리 간다.", "stack": 1, "vis": {"s": "raft"}},
	"sapling": {"name": "야자 묘목", "desc": "모래나 흙 위에 우클릭으로 심으면 야자수가 자란다.", "struct": "sapling", "vis": {"s": "sapling"}},
	# ── 설치 구조물 ──
	"workbench": {"name": "작업대", "desc": "설치하면 근처에서 더 많은 걸 만들 수 있다.", "struct": "workbench", "vis": "m:survival/workbench"},
	"door": {"name": "나무 문", "desc": "집에는 문이 있어야 집이지. 문틀 벽을 보고 놓으면 쏙 들어간다. E 로 여닫는다.", "struct": "door", "vis": {"s": "door"}},
	# ── 건축 부품 (2m 격자, 서로 붙는다) ──
	"foundation": {"name": "나무 기초", "desc": "2m x 2m 바닥 기초. 땅이나 얕은 물에 다리를 박아 세운다. 물 위에 깔면 땅을 넓힌 걸로 친다.", "struct": "foundation", "stack": 20, "vis": {"s": "part", "k": "foundation"}},
	"floor": {"name": "나무 바닥", "desc": "기초 옆에 이어 깔거나, 벽이나 기둥 위에 올려 2층을 만든다.", "struct": "floor", "stack": 20, "vis": {"s": "part", "k": "floor"}},
	"wall": {"name": "나무 벽", "desc": "기초나 바닥 가장자리에 붙는다. 벽 위에 벽도 쌓인다.", "struct": "wall", "stack": 20, "vis": {"s": "part", "k": "wall"}},
	"window_wall": {"name": "창문 벽", "desc": "유리 창문이 달린 벽. 밖이 보인다.", "struct": "window_wall", "stack": 20, "vis": {"s": "part", "k": "window_wall"}},
	"doorway": {"name": "문틀 벽", "desc": "문을 달 수 있는 벽. 문 없이 두면 그냥 구멍.", "struct": "doorway", "stack": 20, "vis": {"s": "part", "k": "doorway"}},
	"stairs": {"name": "나무 계단", "desc": "바닥 위나 땅에 놓는다. 보는 쪽으로 올라간다.", "struct": "stairs", "stack": 20, "vis": {"s": "part", "k": "stairs"}},
	"roof": {"name": "야자잎 지붕", "desc": "벽 위에 얹는다. 마주 보게 두 장 얹으면 뾰족 지붕.", "struct": "roof", "stack": 20, "vis": {"s": "part", "k": "roof", "rot": [0, 180, 0]}},
	"pillar": {"name": "나무 기둥", "desc": "칸 꼭짓점에 세운다. 벽 없이 바닥이나 지붕을 받친다.", "struct": "pillar", "stack": 20, "vis": {"s": "part", "k": "pillar"}},
	"campfire": {"name": "모닥불", "desc": "요리하고, 물을 끓이고, 밤을 밝힌다.", "struct": "campfire", "vis": "m:survival/campfire-pit"},
	"furnace": {"name": "화덕", "desc": "고철과 광석을 녹이고 벽돌과 유리를 굽는다.", "struct": "furnace", "vis": {"s": "furnace"}},
	"chest": {"name": "상자", "desc": "모두가 같이 쓰는 보관함 (18칸).", "struct": "chest", "vis": "m:survival/chest"},
	"bed": {"name": "잎사귀 침대", "desc": "다시 태어나는 곳. 밤에 모두 누우면 아침이 된다.", "struct": "bed", "vis": "m:survival/bedroll"},
	"rain_collector": {"name": "빗물받이", "desc": "천천히 깨끗한 물이 고인다. 비 오면 빨리. 빈 병을 들고 E.", "struct": "rain_collector", "vis": "m:survival/barrel-open"},
	"farm_plot": {"name": "밭", "desc": "감자나 산딸기를 심는다.", "struct": "farm_plot", "vis": {"s": "box", "c": "5a3a1e", "sz": [0.6, 0.15, 0.6]}},
	"trap": {"name": "통발", "desc": "물가에 두면 생선이나 게가 잡힌다.", "struct": "trap", "vis": {"s": "trap"}},
	"sand_trap": {"name": "모래 포집기", "desc": "얕은 물가에 두면 파도가 모래를 쌓아 준다. 섬 넓히기의 핵심!", "struct": "sand_trap", "vis": {"s": "box", "c": "b08850", "sz": [0.6, 0.3, 0.6]}},
	"shipyard": {"name": "조선소", "desc": "탈출선을 만드는 곳. 물가에 설치해야 한다.", "struct": "shipyard", "vis": "m:pirate/structure-platform-dock-small"},
	"totem": {"name": "마을 토템", "desc": "섬에 뿌리내리기로 한 사람들의 상징. 섬 한가운데 세우자.", "struct": "totem", "vis": {"s": "totem"}},
	"bell_ringer": {"name": "태엽 종치기", "desc": "종 옆에 두면, 다른 종이 울릴 때 같이 울려 준다. 친구가 없을 때.", "struct": "bell_ringer", "vis": {"s": "torus", "c": "b08d57", "sz": [0.4, 0.4, 0.4]}},
}

# 설치 구조물. model 은 Kenney GLB, 없으면 Vis 가 도형으로.
# station: 조합대 역할. light: 빛 반경. solid: 충돌 여부. water: 물가에만 설치.
var STRUCTS := {
	"workbench": {"name": "작업대", "model": "survival/workbench", "station": "workbench", "solid": true},
	"door": {"name": "나무 문", "vis": {"s": "door"}, "solid": true},
	"campfire": {"name": "모닥불", "model": "survival/campfire-pit", "station": "campfire", "light": 9.0, "solid": false},
	"furnace": {"name": "화덕", "vis": {"s": "furnace"}, "station": "furnace", "light": 4.0, "solid": true},
	"chest": {"name": "상자", "model": "survival/chest", "solid": true, "slots": 18},
	"bed": {"name": "잎사귀 침대", "model": "survival/bedroll", "solid": false},
	"torch": {"name": "횃불", "vis": {"s": "torch"}, "light": 8.0, "solid": false, "item": "torch"},
	"sapling": {"name": "야자 묘목", "vis": {"s": "sapling"}, "solid": false, "item": "sapling", "on": ["sand", "dirt", "grass"]},
	"rain_collector": {"name": "빗물받이", "model": "survival/barrel-open", "solid": true, "cap": 3},
	"farm_plot": {"name": "밭", "vis": {"s": "box", "c": "5a3a1e", "sz": [0.95, 0.15, 0.95]}, "solid": false, "on": ["dirt", "grass"]},
	"trap": {"name": "통발", "vis": {"s": "trap"}, "solid": false, "water": true, "cap": 3},
	"sand_trap": {"name": "모래 포집기", "vis": {"s": "box", "c": "b08850", "sz": [0.9, 0.35, 0.9]}, "solid": false, "water": true, "cap": 8},
	"shipyard": {"name": "조선소", "model": "pirate/structure-platform-dock-small", "solid": false, "water": true},
	"totem": {"name": "마을 토템", "vis": {"s": "totem"}, "solid": true},
	"bell_ringer": {"name": "태엽 종치기", "vis": {"s": "torus", "c": "b08d57", "sz": [0.5, 0.5, 0.5]}, "solid": false},
	"float_log": {"name": "떠 있는 통나무", "vis": {"s": "log"}, "solid": true, "item": "wood"},
	# 건축 부품 (모양·충돌은 Build 가 만든다)
	"foundation": {"name": "나무 기초", "solid": true, "build": true},
	"floor": {"name": "나무 바닥", "solid": true, "build": true},
	"wall": {"name": "나무 벽", "solid": true, "build": true},
	"window_wall": {"name": "창문 벽", "solid": true, "build": true},
	"doorway": {"name": "문틀 벽", "solid": true, "build": true},
	"stairs": {"name": "나무 계단", "solid": true, "build": true},
	"roof": {"name": "야자잎 지붕", "solid": true, "build": true},
	"pillar": {"name": "나무 기둥", "solid": true, "build": true},
	# 월드에만 있는 것 (조합 불가)
	"loot_crate": {"name": "떠밀려온 상자", "model": "pirate/crate", "solid": true, "world": true},
	"loot_barrel": {"name": "낡은 통", "model": "survival/barrel", "solid": true, "world": true},
	"captain_chest": {"name": "선장의 금고", "model": "pirate/chest", "solid": true, "world": true},
	"tablet": {"name": "고대 석판", "model": "nature/statue_block", "solid": true, "world": true},
	"bell": {"name": "고대의 종", "vis": {"s": "bell"}, "solid": true, "world": true},
	"altar": {"name": "거북 제단", "model": "nature/statue_ring", "solid": true, "world": true},
	"plate": {"name": "압력판", "vis": {"s": "box", "c": "8fa89a", "sz": [0.9, 0.08, 0.9]}, "solid": false, "world": true},
	"dig_spot": {"name": "수상한 모래", "vis": {"s": "xmark"}, "solid": false, "world": true},
	"note_sign": {"name": "팻말", "model": "survival/signpost", "solid": true, "world": true},
	"big_rock": {"name": "커다란 바위", "model": "survival/rock-b", "solid": true, "world": true},
	"temple": {"name": "고대 신전", "solid": true, "world": true},      # 모양은 Structs 가 따로 만든다
	"cave_roof": {"name": "동굴 천장", "solid": true, "world": true},
}

# 조합법. at: "" 맨손, 아니면 근처(5m)에 있어야 할 조합대.
var RECIPES: Array = [
	# 맨손
	{"out": "plank", "n": 3, "in": {"wood": 1}, "at": ""},
	{"out": "stick", "n": 2, "in": {"plank": 1}, "at": ""},
	{"out": "rope", "n": 1, "in": {"fiber": 2}, "at": ""},
	{"out": "bottle", "n": 1, "in": {"plastic": 2}, "at": ""},
	{"out": "bow_drill", "n": 1, "in": {"stick": 2, "rope": 1}, "at": ""},
	{"out": "workbench", "n": 1, "in": {"wood": 4, "stone": 2}, "at": ""},
	{"out": "campfire", "n": 1, "in": {"stick": 4, "stone": 3, "palm_leaf": 2}, "at": ""},
	{"out": "sapling", "n": 1, "in": {"coconut": 1}, "at": ""},
	{"out": "bandage", "n": 1, "in": {"cloth": 1, "fiber": 2}, "at": ""},
	# 작업대
	{"out": "fishing_rod", "n": 1, "in": {"stick": 3, "rope": 2}, "at": "workbench"},
	{"out": "hook", "n": 1, "in": {"stick": 2, "rope": 2, "flint": 1}, "at": "workbench"},
	{"out": "chest", "n": 1, "in": {"plank": 8, "rope": 1}, "at": "workbench"},
	{"out": "door", "n": 1, "in": {"plank": 6}, "at": "workbench"},
	{"out": "bed", "n": 1, "in": {"plank": 4, "palm_leaf": 8}, "at": "workbench"},
	{"out": "rain_collector", "n": 1, "in": {"plank": 4, "palm_leaf": 4, "rope": 1}, "at": "workbench"},
	{"out": "farm_plot", "n": 1, "in": {"plank": 2, "dirt": 2}, "at": "workbench"},
	{"out": "trap", "n": 1, "in": {"stick": 6, "rope": 3}, "at": "workbench"},
	{"out": "sand_trap", "n": 1, "in": {"plank": 6, "rope": 2, "stone": 4}, "at": "workbench"},
	{"out": "furnace", "n": 1, "in": {"stone": 12, "clay": 6}, "at": "workbench"},
	{"out": "crowbar", "n": 1, "in": {"iron": 3}, "at": "workbench"},
	{"out": "shipyard", "n": 1, "in": {"plank": 20, "wood": 10, "rope": 8, "iron": 4}, "at": "workbench"},
	{"out": "totem", "n": 1, "in": {"plank": 20, "brick": 10, "shell": 8, "cloth": 3}, "at": "workbench"},
	{"out": "bell_ringer", "n": 1, "in": {"clockwork": 1, "iron": 4, "rope": 3}, "at": "workbench"},
	{"out": "foundation", "n": 1, "in": {"plank": 4, "wood": 2, "rope": 1}, "at": "workbench"},
	{"out": "floor", "n": 1, "in": {"plank": 4}, "at": "workbench"},
	{"out": "wall", "n": 1, "in": {"plank": 4, "stick": 2}, "at": "workbench"},
	{"out": "window_wall", "n": 1, "in": {"plank": 3, "stick": 2, "glass": 1}, "at": "workbench"},
	{"out": "doorway", "n": 1, "in": {"plank": 3, "stick": 2}, "at": "workbench"},
	{"out": "stairs", "n": 1, "in": {"plank": 5}, "at": "workbench"},
	{"out": "roof", "n": 1, "in": {"palm_leaf": 6, "stick": 3}, "at": "workbench"},
	{"out": "pillar", "n": 1, "in": {"wood": 2}, "at": "workbench"},
	# 모닥불
	{"out": "torch", "n": 2, "in": {"stick": 1, "palm_leaf": 1}, "at": "campfire"},
	{"out": "fresh_water", "n": 1, "in": {"salt_water": 1}, "at": "campfire"},
	{"out": "shell_water", "n": 1, "in": {"shell_salt": 1}, "at": "campfire"},
	{"out": "fish_soup", "n": 1, "in": {"raw_fish": 2, "fresh_water": 1, "seaweed": 2}, "at": "campfire"},
	{"out": "seaweed_feast", "n": 1, "in": {"seaweed": 20, "cooked_fish": 5, "coconut": 5}, "at": "campfire"},
	# 화덕
	{"out": "iron", "n": 1, "in": {"scrap": 2}, "at": "furnace"},
	{"out": "iron", "n": 1, "in": {"iron_ore": 1}, "at": "furnace"},
	{"out": "glass", "n": 1, "in": {"sand": 2}, "at": "furnace"},
	{"out": "brick", "n": 1, "in": {"clay": 1}, "at": "furnace"},
	{"out": "bottle", "n": 2, "in": {"glass": 1}, "at": "furnace"},
]

const STATION_NAMES := {"": "맨손", "workbench": "작업대", "campfire": "모닥불", "furnace": "화덕"}

# 전리품: [아이템, 최소, 최대, 가중치]
var LOOT := {
	"flotsam": [["plank", 2, 4, 30], ["wood", 1, 2, 18], ["plastic", 1, 2, 16], ["rope", 1, 1, 10],
			["scrap", 1, 2, 12], ["cloth", 1, 1, 8], ["bottle", 1, 1, 6], ["coconut", 1, 2, 8], ["palm_leaf", 2, 3, 6]],
	"barrel": [["plank", 2, 5, 20], ["rope", 1, 2, 15], ["scrap", 1, 3, 15], ["cloth", 1, 2, 12],
			["bottle", 1, 2, 10], ["fresh_water", 1, 1, 8], ["potato", 1, 3, 8], ["flint", 1, 2, 8]],
	"fish": [["raw_fish", 1, 1, 70], ["big_fish", 1, 1, 14], ["seaweed", 1, 2, 8], ["bottle", 1, 1, 4],
			["plastic", 1, 1, 3], ["golden_shell", 1, 1, 1]],
	"trap": [["raw_fish", 1, 1, 55], ["crab_meat", 1, 1, 35], ["shell", 1, 2, 10]],
}

var _recipe_cache := {}


static func josa(word: String, with_final: String, without_final: String) -> String:
	## 받침에 맞는 조사: josa("곡괭이", "이", "가") -> "곡괭이가"
	if word.is_empty():
		return word
	var c := word.unicode_at(word.length() - 1)
	if c >= 0xAC00 and c <= 0xD7A3:
		return word + (with_final if (c - 0xAC00) % 28 != 0 else without_final)
	return word + with_final + "(" + without_final + ")"


func _def(id: String) -> Dictionary:
	if ITEMS.has(id):
		return ITEMS[id]
	if id.begins_with("tool:"):
		if not _dyn.has(id):
			_dyn[id] = _make_tool_def(id)
		return _dyn[id]
	return {}


func item(id: String) -> Dictionary:
	return _def(id)


func name_of(id: String) -> String:
	return _def(id).get("name", id)


func max_stack(id: String) -> int:
	var d: Dictionary = _def(id)
	if d.has("stack"):
		return d.stack
	if d.has("tool") and not d.has("struct"):
		return 1
	return DEFAULT_STACK


func tool_of(id: String) -> Dictionary:
	return _def(id).get("tool", {})


func food_of(id: String) -> Dictionary:
	return _def(id).get("food", {})


func repair_cost(item_id: String) -> Dictionary:
	## 작업대에서 도구 고치는 재료 (내구도 절반 회복)
	var mat := item_id.split(":")[2] if item_id.begins_with("tool:") else ""
	if item_id.begins_with("iron_") or item_id == "crowbar" or mat in ["iron", "scrap"]:
		return {"iron": 1}
	if item_id.begins_with("stone_") or mat == "stone":
		return {"stone": 2, "rope": 1}
	return {"stick": 1, "rope": 1}


# ── 도구 직접 조립 ──

func tool_id(shape: String, mat: String, bind: String, handle: String) -> String:
	return "tool:%s:%s:%s:%s" % [shape, mat, bind, handle]


func assembly_cost(shape: String, mat: String, bind: String, handle: String) -> Dictionary:
	## 조립에 드는 재료 (창은 긴 자루라 막대기가 둘)
	var need := {}
	need[mat] = TOOL_MATS[mat][6]
	need[bind] = need.get(bind, 0) + BINDINGS[bind][2]
	need[handle] = need.get(handle, 0) + (2 if shape == "spear" and handle == "stick" else 1)
	return need


func assembly_station(mat: String) -> String:
	## 쇠붙이는 작업대에서 두드려야 한다
	return "workbench" if mat in ["iron", "scrap", "golden_shell"] else ""


func _make_tool_def(id: String) -> Dictionary:
	var p := id.split(":")
	if p.size() != 5 or not TOOL_SHAPES.has(p[1]) or not TOOL_MATS.has(p[2]) or not BINDINGS.has(p[3]) or not HANDLES.has(p[4]):
		return {}
	var shape: String = p[1]
	var m: Array = TOOL_MATS[p[2]]
	var b: Array = BINDINGS[p[3]]
	var h: Array = HANDLES[p[4]]
	var col: int = {"axe": 1, "pick": 2, "shovel": 3, "spear": 4}[shape]
	var power: int = 1 if shape == "spear" else m[col] + h[2]
	var dmg: int = m[4] if shape == "spear" else (2 if shape == "shovel" else maxi(2, power - 1))
	var dur := int(m[5] * b[1] * h[1])
	var base := _tool_base(shape, p[2])
	return {"name": "%s%s%s %s" % [h[0], b[0], m[0], TOOL_SHAPES[shape]],
		"desc": "직접 조립한 도구. 힘 %d / 공격 %d / 내구 %d%s" % [power, dmg, dur, " / 무거워서 느리다" if h[2] > 0 else ""],
		"tool": {"kind": shape, "power": power, "dmg": dmg, "dur": dur, "slow": h[2] > 0},
		"stack": 1, "vis": ITEMS[base].vis, "icon": base}


func _tool_base(shape: String, mat: String) -> String:
	## 모양·아이콘을 빌려 올 원래 도구
	var metal: bool = mat in ["iron", "scrap", "golden_shell"]
	match shape:
		"axe": return "iron_axe" if metal else "stone_axe"
		"pick": return "iron_pick" if metal else "stone_pick"
		"spear": return "shark_spear" if mat == "shark_tooth" else ("iron_spear" if metal else "spear")
	return "shovel"


func struct_of(item_id: String) -> String:
	return _def(item_id).get("struct", "")


func recipes_at(station: String) -> Array:
	if not _recipe_cache.has(station):
		_recipe_cache[station] = RECIPES.filter(func(r): return r.at == station)
	return _recipe_cache[station]


func roll_loot(table: String, rng: RandomNumberGenerator, rolls: int = 1) -> Array:
	## [[id, n], ...]
	var t: Array = LOOT.get(table, [])
	var total := 0
	for e in t:
		total += e[3]
	var out: Array = []
	for _r in rolls:
		var pick := rng.randi_range(1, total)
		for e in t:
			pick -= e[3]
			if pick <= 0:
				out.append([e[0], rng.randi_range(e[1], e[2])])
				break
	return out


func icon(id: String) -> Texture2D:
	var path := "res://assets/icons/%s.png" % _def(id).get("icon", id)
	if ResourceLoader.exists(path):
		return load(path)
	return null
