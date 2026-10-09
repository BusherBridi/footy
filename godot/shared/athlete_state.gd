class_name AthleteState
extends RefCounted
## Everything the movement step needs. Plain data so it can be copied for
## client prediction and replayed on the server.

enum Status { OK, STUMBLE, DOWN, DIVING, SPIN, TRUCK, HURDLE, POP, WRAPPED, HOLDING, SET, BLOCKED, BLOCKING }

var pos := Vector2.ZERO          # x, z on the field plane (metres)
var heading := Vector2(0, -1)    # unit direction of travel / facing
var speed := 0.0
var stamina := 1.0               # 0..1
var cut_timer := 0.0             # >0 while planted in a cut
var cut_cooldown := 0.0
var prev_dir := Vector2.ZERO     # last frame's stick direction, for flick detection
var status := Status.OK          # set by the referee (tackles); movement just obeys it
var status_timer := 0.0
var spin_side := 0                # -1 left, 0 straight, +1 right: where the spin will pop out
var juke_timer := 0.0
var carrying := false            # holding the ball: runs a little slower so pursuit angles work
var stance_dir := Vector2.ZERO   # stance: the locked facing (zero = not in stance)
var hip_timer := 0.0             # >0 while flipping the hips out of a stance (slow, facing turning)


func copy() -> AthleteState:
	var s := AthleteState.new()
	s.pos = pos
	s.heading = heading
	s.speed = speed
	s.stamina = stamina
	s.cut_timer = cut_timer
	s.cut_cooldown = cut_cooldown
	s.prev_dir = prev_dir
	s.status = status
	s.status_timer = status_timer
	s.juke_timer = juke_timer
	s.spin_side = spin_side
	s.carrying = carrying
	s.stance_dir = stance_dir
	s.hip_timer = hip_timer
	return s


## Where the body points: the locked stance direction, else the way you're moving.
func facing() -> Vector2:
	return stance_dir if stance_dir != Vector2.ZERO else heading


func in_stance() -> bool:
	return stance_dir != Vector2.ZERO and hip_timer <= 0.0
