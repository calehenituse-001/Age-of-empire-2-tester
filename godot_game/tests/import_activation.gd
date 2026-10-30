extends Node
## Synthetic on-disk transaction tests; no Microsoft game assets needed.
var checks := 0
var failures := 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + title)

func marker(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null)
	f.store_string(contents)

func _ready() -> void:
	var root := ProjectSettings.globalize_path("user://import_activation_test")
	Importer._rmdir(root)
	DirAccess.make_dir_recursive_absolute(root)
	var live := root.path_join("imported")
	var stage := root.path_join("importing")
	DirAccess.make_dir_recursive_absolute(live)
	marker(live.path_join("original.txt"), "keep me")
	DirAccess.make_dir_recursive_absolute(stage)
	marker(stage.path_join("manifest.json"), "{}")
	check(not ImportActivation.staged_ready(stage), "incomplete staged import refused")
	check(not ImportActivation.promote(stage, live).is_empty(), "incomplete import cannot replace previous data")
	check(FileAccess.file_exists(live.path_join("original.txt")), "previous data survives refusal")
	marker(stage.path_join(".complete"), "1")
	marker(stage.path_join("data/rules.json"), "{}")
	check(ImportActivation.staged_ready(stage), "completed staged layout detected")
	check(ImportActivation.promote(stage, live).is_empty(), "complete stage promoted")
	check(FileAccess.file_exists(live.path_join("manifest.json")), "candidate becomes live")
	check(FileAccess.file_exists(live.path_join(".previous/original.txt")), "backup preserved pending validation")
	check(ImportActivation.rollback(live), "runtime failure rolls back")
	check(FileAccess.file_exists(live.path_join("original.txt")), "original restored after failure")
	check(not FileAccess.file_exists(live.path_join("manifest.json")), "failed candidate removed")
	DirAccess.make_dir_recursive_absolute(stage)
	marker(stage.path_join("manifest.json"), "{}")
	marker(stage.path_join(".complete"), "1")
	marker(stage.path_join("data/rules.json"), "{}")
	check(ImportActivation.promote(stage, live).is_empty(), "second import promoted")
	ImportActivation.commit(live)
	check(not DirAccess.dir_exists_absolute(live + ".previous"), "validated commit releases backup")
	DirAccess.rename_absolute(live, live + ".previous")
	check(ImportActivation.recover_missing(live), "interrupted promotion recovers backup")
	check(FileAccess.file_exists(live.path_join("manifest.json")), "recovered import is intact")
	check(not ImportActivation.recover_missing(live), "recovery never overwrites live data")
	Importer._rmdir(root)
	print("IMPORT_ACTIVATION_TEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
