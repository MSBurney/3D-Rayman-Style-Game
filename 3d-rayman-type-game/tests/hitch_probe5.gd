extends Node

## THROWAWAY probe #5 — the real reproduction.
##
## Theory: shockwave.gd builds a `StandardMaterial3D` per ring. Godot keeps one
## compiled shader per distinct material configuration and FREES it when the
## last material using it is destroyed. A ring frees itself after `duration`
## (0.38s), so if no other ring is alive at that moment the shader goes with it
## and the next ring has to compile all over again.
##
## That explains why the earlier probes looked clean: they spun every ~12 frames
## with vsync off, so rings overlapped and something always held the shader. A
## player spins maybe twice a second, with gaps longer than the ring's life.
##
## So: spawn 8 rings ONE SECOND apart, by real time, and see if each one stalls.
## Prediction: every single one hitches. The puff is the control — its material
## is a sub-resource of its scene, so it is never freed, so it should be clean.

const MAIN := preload("res://scenes/main.tscn")
const BURST := preload("res://scenes/fx/jump_burst.tscn")
const RING := preload("res://scenes/fx/shockwave.tscn")

var player: Player
var _last_usec: int = 0
var _intervals: Array[float] = []
var _report: Array[String] = []
var _baseline: float = 0.0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	player = main.get_node("Player") as Player
	if player == null:
		print("PROBE5 no player")
		get_tree().quit(1)
		return
	await _run()
	print("\n==== HITCH PROBE 5 (one second between effects) ====")
	for line in _report:
		print(line)
	get_tree().quit(0)


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_intervals.append(float(now - _last_usec) / 1000.0)
	_last_usec = now


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _measure(label: String, action: Callable) -> void:
	# A full second of real time, so anything the previous effect was keeping
	# alive has definitely been freed. This is the bit the other probes missed.
	await get_tree().create_timer(1.0).timeout
	var t0 := Time.get_ticks_usec()
	action.call()
	var call_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var mark := _intervals.size()
	await _frames(20)
	var worst := 0.0
	for i in range(mark, _intervals.size()):
		worst = maxf(worst, _intervals[i])
	var flag := ""
	if worst > _baseline * 3.0 and worst > 4.0:
		flag = "  *** HITCH ***"
	_report.append("  %-30s call %6.2fms   worst frame %6.2fms%s"
		% [label, call_ms, worst, flag])


func _run() -> void:
	await _frames(150)
	_intervals.clear()
	await _frames(120)
	var total := 0.0
	var worst := 0.0
	for ms in _intervals:
		total += ms
		worst = maxf(worst, ms)
	_baseline = total / maxf(float(_intervals.size()), 1.0)
	_report.append("  idle baseline: mean %.2fms, worst %.2fms" % [_baseline, worst])
	_report.append("")
	_report.append("  PREDICTION: every ring hitches, no puff does.")
	_report.append("")

	for i in 6:
		await _measure("ring, 1s apart #%d" % (i + 1), _spawn_ring)
	_report.append("")
	for i in 6:
		await _measure("puff, 1s apart #%d" % (i + 1), _spawn_burst)
	_report.append("")
	for i in 6:
		await _measure("real spin, 1s apart #%d" % (i + 1),
			func() -> void: _force_spin((i % 3) + 1))


func _spawn_burst() -> void:
	var puff := BURST.instantiate() as Node3D
	get_tree().current_scene.add_child(puff)
	puff.global_position = player.global_position + Vector3.UP * 0.25
	puff.call(&"play", Color(1, 0.9, 0.5), 14, 5.0, Vector3.DOWN)


func _spawn_ring() -> void:
	var ring := RING.instantiate() as Node3D
	get_tree().current_scene.add_child(ring)
	ring.global_position = player.global_position
	ring.call(&"play", 3.0, false)


func _force_spin(step: int) -> void:
	var a := player.abilities
	a._cooldown = 0.0
	a._combo_left = 999.0
	a.spin_step = step - 1
	a._spin()
