extends Node
## 모델 크기 재기: godot --headless --path . tools/measure.tscn

const LIST := ["pirate/palm-straight", "pirate/palm-bend", "pirate/palm-detailed-straight", "nature/tree_palmTall", "nature/tree_palm",
	"survival/tree", "survival/tree-tall", "nature/tree_default", "nature/tree_oak", "nature/tree_detailed", "nature/plant_bush", "nature/plant_bushLarge",
	"survival/rock-a", "survival/rock-b", "nature/rock_largeA", "nature/stone_largeA", "nature/stone_tallA", "survival/workbench", "survival/campfire-pit",
	"survival/chest", "survival/bedroll", "survival/barrel-open", "survival/barrel", "pirate/crate", "pirate/chest", "pirate/ship-wreck", "pirate/ship-small",
	"pirate/ship-medium", "pirate/structure-platform-dock-small", "nature/statue_block", "nature/statue_ring", "nature/statue_column", "nature/statue_head",
	"nature/statue_obelisk", "survival/signpost", "survival/tool-axe", "survival/fish", "survival/resource-wood", "pirate/boat-row-small", "nature/stump_round",
	"nature/grass_large", "nature/flower_redA", "nature/mushroom_redGroup", "nature/crops_leafsStageA", "nature/crop_pumpkin", "survival/tent", "pirate/flag-pirate", "nature/lily_large"]


func _ready() -> void:
	for p in LIST:
		var n := Vis.model(p)
		var ab := Vis.aabb_of(n)
		print("%-40s size=(%.2f, %.2f, %.2f) pos=(%.2f, %.2f, %.2f)" % [p, ab.size.x, ab.size.y, ab.size.z, ab.position.x, ab.position.y, ab.position.z])
		n.free()
	get_tree().quit()
