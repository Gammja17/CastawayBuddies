extends Node
## 게임 데이터 창고: 블록 · 아이템 · 구조물 · 조합법 · 전리품 표.
## 숫자는 전부 여기서 고친다.

const DEFAULT_STACK := 50

# 블록 종류. GridMap 아이템 번호 = 배열 순서.
# hard: 부수는 데 필요한 힘(-1 = 못 부숨). tool: 이 도구면 빨리 부서짐. need: 이 도구가 없으면 못 부숨.
var BLOCKS: Array = [
	{"id": "sand", "name": "모래 블록", "color": Color("ecd592"), "hard": 3, "tool": "shovel", "drop": "sand"},
	{"id": "dirt", "name": "흙 블록", "color": Color("8a5c34"), "hard": 4, "tool": "shovel", "drop": "dirt"},
	{"id": "grass", "name": "잔디 블록", "color": Color("5fb84a"), "hard": 4, "tool": "shovel", "drop": "dirt"},
	{"id": "stone", "name": "바위", "color": Color("8d8d93"), "hard": 8, "tool": "pick", "need": "pick", "drop": "stone", "drop_n": 2},
	{"id": "clay", "name": "점토", "color": Color("b9876e"), "hard": 5, "tool": "shovel", "drop": "clay", "drop_n": 3},
	{"id": "iron_ore", "name": "철광석", "color": Color("9a7e6e"), "hard": 12, "tool": "pick", "need": "pick", "drop": "iron_ore"},
	{"id": "plank_block", "name": "판자 블록", "color": Color("c89b5e"), "hard": 4, "tool": "axe", "drop": "plank_block"},
	{"id": "stone_block", "name": "돌 블록", "color": Color("a3a3a8"), "hard": 8, "tool": "pick", "need": "pick", "drop": "stone_block"},
	{"id": "brick_block", "name": "벽돌 블록", "color": Color("b5553c"), "hard": 10, "tool": "pick", "need": "pick", "drop": "brick_block"},
	{"id": "glass_block", "name": "유리 블록", "color": Color(0.75, 0.93, 1.0, 0.35), "hard": 2, "tool": "", "drop": "glass_block"},
	{"id": "thatch_block", "name": "초가 블록", "color": Color("c9b458"), "hard": 2, "tool": "", "drop": "thatch_block"},
	{"id": "ancient", "name": "고대 벽돌", "color": Color("6f8f7a"), "hard": -1, "tool": "", "drop": ""},
	{"id": "leaf_block", "name": "잎 블록", "color": Color("3f9a3a"), "hard": 1, "tool": "", "drop": "leaf_block"},
	# ↓ 새 블록은 항상 뒤에 붙인다 (저장 파일의 번호가 바뀌지 않게)
	{"id": "log_block", "name": "통나무 블록", "color": Color("8a5a2b"), "hard": 5, "tool": "axe", "drop": "log_block"},
	{"id": "sandstone", "name": "사암 블록", "color": Color("dcc288"), "hard": 6, "tool": "pick", "need": "pick", "drop": "sandstone"},
]
var block_index := {}   # "sand" -> 0

# 아이템. stack 기본 50, 도구는 1.
# food: hunger/thirst/hp 회복, ret = 먹고 돌려받는 아이템
# tool: kind(axe/pick/shovel/spear/rod/hook/torch), power(채집력), dmg(공격력), dur(내구도)
# block: 설치하면 되는 블록 id / struct: 설치하면 되는 구조물 id
# vis: 3D 모양. "m:킷/모델" 이면 Kenney GLB, 아니면 Vis 가 도형으로 만든다.
var ITEMS := {
	# ── 재료 ──
	"wood": {"name": "통나무", "desc": "나무를 패면 나온다. 거의 모든 것의 시작.", "vis": "m:survival/resource-wood"},
	"plank": {"name": "판자", "desc": "통나무를 쪼갠 것. 건축과 조합에 쓴다.", "vis": "m:survival/resource-planks"},
	"stick": {"name": "막대기", "desc": "평범한 막대기. 친구를 찌르지 말 것.", "vis": {"s": "cyl", "c": "9b6a3a", "sz": [0.05, 0.7, 0.05], "rot": [0, 0, 60]}},
	"palm_leaf": {"name": "야자잎", "desc": "야자수에서 떨어진 큰 잎. 지붕, 침대, 횃불 재료.", "vis": {"s": "box", "c": "4caf3f", "sz": [0.5, 0.04, 0.22]}},
	"fiber": {"name": "섬유", "desc": "덤불에서 뜯은 질긴 풀. 꼬면 밧줄이 된다.", "vis": {"s": "box", "c": "9ccc4a", "sz": [0.12, 0.35, 0.12]}},
	"rope": {"name": "밧줄", "desc": "섬유를 꼬아 만든 밧줄. 무인도의 접착제.", "vis": {"s": "torus", "c": "c7a86b", "sz": [0.35, 0.35, 0.35]}},
	"stone": {"name": "돌멩이", "desc": "바닥에 굴러다니거나 바위를 캐면 나온다.", "vis": "m:survival/resource-stone"},
	"flint": {"name": "부싯돌", "desc": "날카로운 돌. 창끝과 갈고리에 쓴다.", "vis": {"s": "prism", "c": "3d3f46", "sz": [0.22, 0.14, 0.18]}},
	"sand": {"name": "모래 블록", "desc": "설치해서 섬을 넓힐 수 있다. 화덕에 녹이면 유리.", "block": "sand", "vis": {"s": "block", "b": "sand"}},
	"dirt": {"name": "흙 블록", "desc": "설치하면 섬이 넓어진다. 밭에도 쓴다.", "block": "dirt", "vis": {"s": "block", "b": "dirt"}},
	"clay": {"name": "점토", "desc": "물가의 붉은 흙. 화덕에서 구우면 벽돌.", "vis": {"s": "sphere", "c": "b9876e", "sz": [0.3, 0.2, 0.3]}},
	"iron_ore": {"name": "철광석", "desc": "돌섬 동굴에서 캔다. 화덕에서 녹이면 철.", "vis": {"s": "sphere", "c": "8b6f60", "sz": [0.3, 0.25, 0.3]}},
	"iron": {"name": "철 주괴", "desc": "반짝반짝. 철 도구의 재료.", "vis": {"s": "box", "c": "c9ced6", "sz": [0.3, 0.12, 0.16]}},
	"scrap": {"name": "고철", "desc": "난파선이나 떠다니는 잔해에서 나온다. 녹이면 철.", "vis": {"s": "box", "c": "7a6a60", "sz": [0.3, 0.06, 0.25], "rot": [0, 20, 10]}},
	"plastic": {"name": "플라스틱", "desc": "바다에 떠다니는 쓰레기. 2개를 녹여 붙이면 빈 병이 된다.", "vis": {"s": "box", "c": "5ec8e5", "sz": [0.28, 0.05, 0.2]}},
	"cloth": {"name": "천", "desc": "찢어진 돛 조각. 돛, 붕대, 토템에 쓴다.", "vis": {"s": "box", "c": "efe8d8", "sz": [0.35, 0.04, 0.3]}},
	"brick": {"name": "벽돌", "desc": "점토를 구운 것. 4개로 벽돌 블록.", "vis": {"s": "box", "c": "b5553c", "sz": [0.3, 0.12, 0.15]}},
	"shell": {"name": "조개껍데기", "desc": "해변에서 줍는 예쁜 조개. 장식과 토템에 쓴다.", "vis": {"s": "cone", "c": "f4c9b8", "sz": [0.22, 0.12, 0.22]}},
	"golden_shell": {"name": "황금 조개", "desc": "눈부시게 빛나는 조개. 어딘가에서 이걸 원하는 존재가 있다는데...", "vis": {"s": "cone", "c": "ffd23f", "sz": [0.3, 0.16, 0.3], "glow": true}},
	"shark_tooth": {"name": "상어 이빨", "desc": "상어한테서 뽑았다(?). 무시무시한 창을 만들 수 있다.", "vis": {"s": "prism", "c": "f5f1e6", "sz": [0.12, 0.2, 0.06]}},
	"bottle": {"name": "빈 병", "desc": "바다를 보며 우클릭하면 바닷물을 담는다.", "vis": "m:survival/bottle"},
	"compass": {"name": "선장의 나침반", "desc": "탈출선에 꼭 필요한 나침반. 바늘이 계속 북쪽... 아니 거북이 쪽을 가리킨다?", "stack": 1, "vis": {"s": "cyl", "c": "d4a93a", "sz": [0.26, 0.06, 0.26]}},
	"clockwork": {"name": "태엽 뭉치", "desc": "난파선 선장실에서 나온 톱니바퀴 덩어리.", "vis": {"s": "torus", "c": "b08d57", "sz": [0.25, 0.25, 0.25]}},
	# ── 음식 ──
	"coconut": {"name": "코코넛", "desc": "우클릭으로 먹고 마신다. 배고픔 +8, 목마름 +22", "food": {"hunger": 8, "thirst": 22}, "vis": {"s": "sphere", "c": "6b4423", "sz": [0.28, 0.28, 0.28]}},
	"berries": {"name": "산딸기", "desc": "덤불에서 딴 열매. 밭에 심을 수도 있다.", "food": {"hunger": 6, "thirst": 4}, "vis": {"s": "sphere", "c": "d8324a", "sz": [0.2, 0.2, 0.2]}},
	"raw_fish": {"name": "생선", "desc": "비리다. 날로 먹으면 체력이 조금 깎인다. 모닥불에 굽자.", "food": {"hunger": 8, "hp": -4}, "vis": "m:survival/fish"},
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
	"bandage": {"name": "붕대", "desc": "우클릭으로 감는다. 체력 +30", "food": {"hp": 30}, "vis": {"s": "cyl", "c": "ffffff", "sz": [0.16, 0.16, 0.16], "rot": [90, 0, 0]}},
	"seaweed_feast": {"name": "해초 잔치상", "desc": "해초와 생선과 코코넛으로 차린 거한 한 상. 먹는 용도가 아닌 것 같다.", "stack": 1, "vis": {"s": "cyl", "c": "3f8f5a", "sz": [0.6, 0.12, 0.6]}},
	# ── 도구 ──
	"stone_axe": {"name": "돌도끼", "desc": "나무를 빨리 벤다.", "tool": {"kind": "axe", "power": 3, "dmg": 3, "dur": 90}, "stack": 1, "vis": "m:survival/tool-axe"},
	"stone_pick": {"name": "돌곡괭이", "desc": "바위와 돌 블록을 캔다.", "tool": {"kind": "pick", "power": 3, "dmg": 3, "dur": 90}, "stack": 1, "vis": "m:survival/tool-pickaxe"},
	"shovel": {"name": "삽", "desc": "모래, 흙, 점토를 빨리 판다. 보물도 판다.", "tool": {"kind": "shovel", "power": 3, "dmg": 2, "dur": 120}, "stack": 1, "vis": "m:survival/tool-shovel"},
	"spear": {"name": "나무창", "desc": "게와 상어를 혼내준다.", "tool": {"kind": "spear", "power": 1, "dmg": 5, "dur": 70}, "stack": 1, "vis": {"s": "spear", "c": "9b6a3a", "tip": "3d3f46"}},
	"fishing_rod": {"name": "낚싯대", "desc": "바다를 보고 좌클릭으로 던지고, ! 가 뜨면 다시 좌클릭.", "tool": {"kind": "rod", "power": 1, "dmg": 1, "dur": 60}, "stack": 1, "vis": {"s": "rod", "c": "8b5a2b"}},
	"hook": {"name": "갈고리", "desc": "떠다니는 잔해를 멀리서 좌클릭으로 낚아챈다.", "tool": {"kind": "hook", "power": 1, "dmg": 2, "dur": 80}, "stack": 1, "vis": {"s": "hook", "c": "c7a86b"}},
	"iron_axe": {"name": "철도끼", "desc": "나무가 두 방.", "tool": {"kind": "axe", "power": 7, "dmg": 6, "dur": 300}, "stack": 1, "vis": "m:survival/tool-axe-upgraded"},
	"iron_pick": {"name": "철곡괭이", "desc": "돌이 두 방.", "tool": {"kind": "pick", "power": 7, "dmg": 6, "dur": 300}, "stack": 1, "vis": "m:survival/tool-pickaxe-upgraded"},
	"iron_spear": {"name": "철창", "desc": "든든한 무기.", "tool": {"kind": "spear", "power": 1, "dmg": 9, "dur": 220}, "stack": 1, "vis": {"s": "spear", "c": "6d4a2a", "tip": "c9ced6"}},
	"shark_spear": {"name": "상어이빨 창", "desc": "상어 이빨을 박은 무시무시한 창. 게 왕도 무섭지 않다.", "tool": {"kind": "spear", "power": 1, "dmg": 13, "dur": 180}, "stack": 1, "vis": {"s": "spear", "c": "6d4a2a", "tip": "f5f1e6"}},
	"crowbar": {"name": "쇠지렛대", "desc": "잠긴 상자를 비틀어 연다.", "tool": {"kind": "crowbar", "power": 2, "dmg": 4, "dur": 999}, "stack": 1, "vis": {"s": "hook", "c": "b53a2a"}},
	"torch": {"name": "횃불", "desc": "들고 있으면 주변이 밝고 밤게가 다가오지 못한다. 우클릭으로 꽂을 수도 있다.", "tool": {"kind": "torch", "power": 1, "dmg": 1, "dur": 999}, "struct": "torch", "vis": {"s": "torch"}},
	"raft": {"name": "뗏목", "desc": "바다를 보고 우클릭으로 띄운다. E 로 타고, 같이 탄 사람이 많을수록 빨리 간다. 상어도 못 건드린다.", "stack": 1, "vis": {"s": "raft"}},
	"sapling": {"name": "야자 묘목", "desc": "모래나 흙 위에 우클릭으로 심으면 야자수가 자란다.", "struct": "sapling", "vis": {"s": "sapling"}},
	# ── 설치 블록 ──
	"plank_block": {"name": "판자 블록", "desc": "바다 위에도 놓을 수 있다. 다리를 놓자!", "block": "plank_block", "vis": {"s": "block", "b": "plank_block"}},
	"stone_block": {"name": "돌 블록", "desc": "튼튼한 건축 블록.", "block": "stone_block", "vis": {"s": "block", "b": "stone_block"}},
	"brick_block": {"name": "벽돌 블록", "desc": "제일 튼튼한 건축 블록.", "block": "brick_block", "vis": {"s": "block", "b": "brick_block"}},
	"glass_block": {"name": "유리 블록", "desc": "창문! 문명의 증거.", "block": "glass_block", "vis": {"s": "block", "b": "glass_block"}},
	"thatch_block": {"name": "초가 블록", "desc": "야자잎을 엮은 지붕 블록.", "block": "thatch_block", "vis": {"s": "block", "b": "thatch_block"}},
	"log_block": {"name": "통나무 블록", "desc": "통나무 오두막의 기본.", "block": "log_block", "vis": {"s": "block", "b": "log_block"}},
	"sandstone": {"name": "사암 블록", "desc": "모래를 꾹꾹 눌러 만든 돌. 해변 성벽에 딱.", "block": "sandstone", "vis": {"s": "block", "b": "sandstone"}},
	"leaf_block": {"name": "잎 블록", "desc": "야자잎 뭉치. 울타리나 숨바꼭질용.", "block": "leaf_block", "vis": {"s": "block", "b": "leaf_block"}},
	# ── 설치 구조물 ──
	"workbench": {"name": "작업대", "desc": "설치하면 근처에서 더 많은 걸 만들 수 있다.", "struct": "workbench", "vis": "m:survival/workbench"},
	"door": {"name": "나무 문", "desc": "집에는 문이 있어야 집이지. E 로 여닫는다.", "struct": "door", "vis": {"s": "door"}},
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
}

# 조합법. at: "" 맨손, 아니면 근처(5m)에 있어야 할 조합대.
var RECIPES: Array = [
	# 맨손
	{"out": "plank", "n": 3, "in": {"wood": 1}, "at": ""},
	{"out": "stick", "n": 2, "in": {"plank": 1}, "at": ""},
	{"out": "rope", "n": 1, "in": {"fiber": 2}, "at": ""},
	{"out": "bottle", "n": 1, "in": {"plastic": 2}, "at": ""},
	{"out": "stone_axe", "n": 1, "in": {"stick": 2, "stone": 3, "rope": 1}, "at": ""},
	{"out": "stone_pick", "n": 1, "in": {"stick": 2, "stone": 3, "rope": 1}, "at": ""},
	{"out": "spear", "n": 1, "in": {"stick": 3, "flint": 1, "rope": 1}, "at": ""},
	{"out": "torch", "n": 2, "in": {"stick": 1, "palm_leaf": 1}, "at": ""},
	{"out": "workbench", "n": 1, "in": {"wood": 4, "stone": 2}, "at": ""},
	{"out": "campfire", "n": 1, "in": {"stick": 4, "stone": 3, "palm_leaf": 2}, "at": ""},
	{"out": "sapling", "n": 1, "in": {"coconut": 1}, "at": ""},
	{"out": "thatch_block", "n": 2, "in": {"palm_leaf": 4}, "at": ""},
	{"out": "leaf_block", "n": 1, "in": {"palm_leaf": 3}, "at": ""},
	{"out": "bandage", "n": 1, "in": {"cloth": 1, "fiber": 2}, "at": ""},
	# 작업대
	{"out": "plank_block", "n": 1, "in": {"plank": 2}, "at": "workbench"},
	{"out": "stone_block", "n": 1, "in": {"stone": 3}, "at": "workbench"},
	{"out": "brick_block", "n": 1, "in": {"brick": 4}, "at": "workbench"},
	{"out": "log_block", "n": 1, "in": {"wood": 2}, "at": "workbench"},
	{"out": "sandstone", "n": 2, "in": {"sand": 3}, "at": "workbench"},
	{"out": "shovel", "n": 1, "in": {"stick": 2, "plank": 3}, "at": "workbench"},
	{"out": "fishing_rod", "n": 1, "in": {"stick": 3, "rope": 2}, "at": "workbench"},
	{"out": "hook", "n": 1, "in": {"stick": 2, "rope": 2, "flint": 1}, "at": "workbench"},
	{"out": "chest", "n": 1, "in": {"plank": 8, "rope": 1}, "at": "workbench"},
	{"out": "door", "n": 1, "in": {"plank": 6}, "at": "workbench"},
	{"out": "raft", "n": 1, "in": {"plank": 10, "rope": 4, "wood": 4}, "at": "workbench"},
	{"out": "bed", "n": 1, "in": {"plank": 4, "palm_leaf": 8}, "at": "workbench"},
	{"out": "rain_collector", "n": 1, "in": {"plank": 4, "palm_leaf": 4, "rope": 1}, "at": "workbench"},
	{"out": "farm_plot", "n": 1, "in": {"plank": 2, "dirt": 2}, "at": "workbench"},
	{"out": "trap", "n": 1, "in": {"stick": 6, "rope": 3}, "at": "workbench"},
	{"out": "sand_trap", "n": 1, "in": {"plank": 6, "rope": 2, "stone": 4}, "at": "workbench"},
	{"out": "furnace", "n": 1, "in": {"stone": 12, "clay": 6}, "at": "workbench"},
	{"out": "iron_axe", "n": 1, "in": {"iron": 3, "stick": 2}, "at": "workbench"},
	{"out": "iron_pick", "n": 1, "in": {"iron": 3, "stick": 2}, "at": "workbench"},
	{"out": "iron_spear", "n": 1, "in": {"iron": 2, "stick": 3}, "at": "workbench"},
	{"out": "shark_spear", "n": 1, "in": {"stick": 3, "shark_tooth": 3, "rope": 2}, "at": "workbench"},
	{"out": "crowbar", "n": 1, "in": {"iron": 3}, "at": "workbench"},
	{"out": "shipyard", "n": 1, "in": {"plank": 20, "wood": 10, "rope": 8, "iron": 4}, "at": "workbench"},
	{"out": "totem", "n": 1, "in": {"plank": 20, "brick": 10, "shell": 8, "cloth": 3}, "at": "workbench"},
	{"out": "bell_ringer", "n": 1, "in": {"clockwork": 1, "iron": 4, "rope": 3}, "at": "workbench"},
	# 모닥불
	{"out": "cooked_fish", "n": 1, "in": {"raw_fish": 1}, "at": "campfire"},
	{"out": "cooked_big_fish", "n": 1, "in": {"big_fish": 1}, "at": "campfire"},
	{"out": "cooked_crab", "n": 1, "in": {"crab_meat": 1}, "at": "campfire"},
	{"out": "baked_potato", "n": 1, "in": {"potato": 1}, "at": "campfire"},
	{"out": "fresh_water", "n": 1, "in": {"salt_water": 1}, "at": "campfire"},
	{"out": "fish_soup", "n": 1, "in": {"raw_fish": 2, "fresh_water": 1, "seaweed": 2}, "at": "campfire"},
	{"out": "seaweed_feast", "n": 1, "in": {"seaweed": 20, "cooked_fish": 5, "coconut": 5}, "at": "campfire"},
	# 화덕
	{"out": "iron", "n": 1, "in": {"scrap": 2}, "at": "furnace"},
	{"out": "iron", "n": 1, "in": {"iron_ore": 1}, "at": "furnace"},
	{"out": "brick", "n": 1, "in": {"clay": 1}, "at": "furnace"},
	{"out": "glass_block", "n": 1, "in": {"sand": 2}, "at": "furnace"},
	{"out": "bottle", "n": 2, "in": {"glass_block": 1}, "at": "furnace"},
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


func _ready() -> void:
	for i in BLOCKS.size():
		block_index[BLOCKS[i].id] = i


static func josa(word: String, with_final: String, without_final: String) -> String:
	## 받침에 맞는 조사: josa("곡괭이", "이", "가") -> "곡괭이가"
	if word.is_empty():
		return word
	var c := word.unicode_at(word.length() - 1)
	if c >= 0xAC00 and c <= 0xD7A3:
		return word + (with_final if (c - 0xAC00) % 28 != 0 else without_final)
	return word + with_final + "(" + without_final + ")"


func item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


func name_of(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id)


func max_stack(id: String) -> int:
	var d: Dictionary = ITEMS.get(id, {})
	if d.has("stack"):
		return d.stack
	if d.has("tool") and not d.has("struct"):
		return 1
	return DEFAULT_STACK


func tool_of(id: String) -> Dictionary:
	return ITEMS.get(id, {}).get("tool", {})


func food_of(id: String) -> Dictionary:
	return ITEMS.get(id, {}).get("food", {})


func block_id(item_id: String) -> int:
	var b: String = ITEMS.get(item_id, {}).get("block", "")
	return block_index.get(b, -1)


func block(idx: int) -> Dictionary:
	if idx < 0 or idx >= BLOCKS.size():
		return {}
	return BLOCKS[idx]


func struct_of(item_id: String) -> String:
	return ITEMS.get(item_id, {}).get("struct", "")


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
	var path := "res://assets/icons/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	return null
