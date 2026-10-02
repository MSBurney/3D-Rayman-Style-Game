extends SceneTree

## Prints fresh resource UIDs, one per line.
##
## Every .tscn needs a `uid://...` in its [gd_scene] header. The editor adds one
## automatically; a scene written as text by hand does not have one, and then
## references to it fall back to matching by file path, which logs
## `invalid UID ... using text path instead` in every scene that points at it.
##
## Safe to run with --script because it touches no game code and so needs no
## autoloads. See the note on --script in CLAUDE.md before writing any other
## throwaway check this way.
func _init() -> void:
	for i in 6:
		print(ResourceUID.id_to_text(ResourceUID.create_id()))
	quit()
