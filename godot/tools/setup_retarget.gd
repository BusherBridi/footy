extends SceneTree
## One-off: give the mannequin (UAL) and the CMU mocap clips humanoid bone maps in their
## import settings, so Godot retargets both onto its standard humanoid skeleton and the mocap
## clips play on our mannequin. Run, then reimport:
##   godot --headless --path godot -s tools/setup_retarget.gd
##   godot --headless --path godot --import

const UAL := {
	"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
	"Neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftUpperArm": "upperarm_l", "LeftLowerArm": "lowerarm_l", "LeftHand": "hand_l",
	"LeftThumbMetacarpal": "thumb_01_l", "LeftThumbProximal": "thumb_02_l", "LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "index_01_l", "LeftIndexIntermediate": "index_02_l", "LeftIndexDistal": "index_03_l",
	"LeftMiddleProximal": "middle_01_l", "LeftMiddleIntermediate": "middle_02_l", "LeftMiddleDistal": "middle_03_l",
	"LeftRingProximal": "ring_01_l", "LeftRingIntermediate": "ring_02_l", "LeftRingDistal": "ring_03_l",
	"LeftLittleProximal": "pinky_01_l", "LeftLittleIntermediate": "pinky_02_l", "LeftLittleDistal": "pinky_03_l",
	"RightShoulder": "clavicle_r", "RightUpperArm": "upperarm_r", "RightLowerArm": "lowerarm_r", "RightHand": "hand_r",
	"RightThumbMetacarpal": "thumb_01_r", "RightThumbProximal": "thumb_02_r", "RightThumbDistal": "thumb_03_r",
	"RightIndexProximal": "index_01_r", "RightIndexIntermediate": "index_02_r", "RightIndexDistal": "index_03_r",
	"RightMiddleProximal": "middle_01_r", "RightMiddleIntermediate": "middle_02_r", "RightMiddleDistal": "middle_03_r",
	"RightRingProximal": "ring_01_r", "RightRingIntermediate": "ring_02_r", "RightRingDistal": "ring_03_r",
	"RightLittleProximal": "pinky_01_r", "RightLittleIntermediate": "pinky_02_r", "RightLittleDistal": "pinky_03_r",
	"LeftUpperLeg": "thigh_l", "LeftLowerLeg": "calf_l", "LeftFoot": "foot_l", "LeftToes": "ball_l",
	"RightUpperLeg": "thigh_r", "RightLowerLeg": "calf_r", "RightFoot": "foot_r", "RightToes": "ball_r",
}

const MOCAP := {
	"Root": "Root", "Hips": "Hips", "Spine": "Abdomen", "Chest": "Torso", "UpperChest": "Chest",
	"Neck": "Neck", "Head": "Head",
	"LeftShoulder": "Shoulder.L", "LeftUpperArm": "UpperArm.L", "LeftLowerArm": "LowerArm.L", "LeftHand": "Hand.L",
	"LeftThumbProximal": "Thumb2.L", "LeftThumbDistal": "Thumb3.L",
	"LeftIndexProximal": "Index2.L", "LeftIndexIntermediate": "Index3.L", "LeftIndexDistal": "Index4.L",
	"LeftMiddleProximal": "Middle2.L", "LeftMiddleIntermediate": "Middle3.L", "LeftMiddleDistal": "Middle4.L",
	"LeftRingProximal": "Ring2.L", "LeftRingIntermediate": "Ring3.L", "LeftRingDistal": "Ring4.L",
	"LeftLittleProximal": "Pinky2.L", "LeftLittleIntermediate": "Pinky3.L", "LeftLittleDistal": "Pinky4.L",
	"RightShoulder": "Shoulder.R", "RightUpperArm": "UpperArm.R", "RightLowerArm": "LowerArm.R", "RightHand": "Hand.R",
	"RightThumbProximal": "Thumb2.R", "RightThumbDistal": "Thumb3.R",
	"RightIndexProximal": "Index2.R", "RightIndexIntermediate": "Index3.R", "RightIndexDistal": "Index4.R",
	"RightMiddleProximal": "Middle2.R", "RightMiddleIntermediate": "Middle3.R", "RightMiddleDistal": "Middle4.R",
	"RightRingProximal": "Ring2.R", "RightRingIntermediate": "Ring3.R", "RightRingDistal": "Ring4.R",
	"RightLittleProximal": "Pinky2.R", "RightLittleIntermediate": "Pinky3.R", "RightLittleDistal": "Pinky4.R",
	"LeftUpperLeg": "UpperLeg.L", "LeftLowerLeg": "LowerLeg.L", "LeftFoot": "Foot.L",
	"RightUpperLeg": "UpperLeg.R", "RightLowerLeg": "LowerLeg.R", "RightFoot": "Foot.R",
}


func _init() -> void:
	for f in ["res://assets/quaternius/UAL1_Standard.glb", "res://assets/quaternius/UAL2_Standard.glb"]:
		_set_map(f, "Armature/Skeleton3D", UAL)
	var dir := DirAccess.open("res://assets/mocap_clips")
	for f in dir.get_files():
		if f.ends_with(".fbx"):
			_set_map("res://assets/mocap_clips/" + f, "CharacterArmature/Skeleton3D", MOCAP)
	quit()


func _set_map(file: String, skeleton_path: String, names: Dictionary) -> void:
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	for k in names:
		bm.set_skeleton_bone_name(StringName(k), StringName(names[k]))
	var cfg := ConfigFile.new()
	if cfg.load(file + ".import") != OK:
		push_error("no import file for " + file)
		return
	var subs: Dictionary = cfg.get_value("params", "_subresources", {})
	var nodes: Dictionary = subs.get("nodes", {})
	var opts: Dictionary = nodes.get("PATH:" + skeleton_path, {})
	opts["retarget/bone_map"] = bm
	nodes["PATH:" + skeleton_path] = opts
	subs["nodes"] = nodes
	cfg.set_value("params", "_subresources", subs)
	cfg.save(file + ".import")
	print("bone map set: ", file)
