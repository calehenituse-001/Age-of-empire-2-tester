class_name ImportActivation
extends RefCounted
## Promotes converted game data without deleting the preceding usable import.
## Directory operations remain in the app-private GameData folder.

static func staged_ready(stage: String) -> bool:
	return DirAccess.dir_exists_absolute(stage) \
		and FileAccess.file_exists(stage.path_join(".complete")) \
		and FileAccess.file_exists(stage.path_join("manifest.json")) \
		and FileAccess.file_exists(stage.path_join("data/rules.json"))


## After a process crash during promotion, only restore the backup if no live
## directory exists. Do not override a potentially good completed activation.
static func recover_missing(live: String) -> bool:
	if DirAccess.dir_exists_absolute(live):
		return false
	var previous := live + ".previous"
	return DirAccess.dir_exists_absolute(previous) \
		and DirAccess.rename_absolute(previous, live) == OK


## Empty result means promotion succeeded. A failure preserves/restores the
## previous import and never advertises the incomplete candidate as active.
static func promote(stage: String, live: String) -> String:
	if not staged_ready(stage):
		return "Converted files are incomplete (manifest/rules/completion marker missing)."
	var previous := live + ".previous"
	if DirAccess.dir_exists_absolute(previous):
		if not DirAccess.dir_exists_absolute(live):
			if DirAccess.rename_absolute(previous, live) != OK:
				return "Cannot recover the previous data before activation."
		else:
			Importer._rmdir(previous)
			if DirAccess.dir_exists_absolute(previous):
				return "Cannot remove a stale previous-import folder."
	var had_live := DirAccess.dir_exists_absolute(live)
	if had_live and DirAccess.rename_absolute(live, previous) != OK:
		return "Cannot preserve the current imported data."
	if DirAccess.rename_absolute(stage, live) != OK:
		if had_live:
			DirAccess.rename_absolute(previous, live)
		return "Cannot activate converted data; check free storage."
	return ""


## Called if Rules or Assets fail to initialize from the promoted data.
## Removes only the failed new import, then restores the previous one.
static func rollback(live: String) -> bool:
	var previous := live + ".previous"
	Importer._rmdir(live)
	if DirAccess.dir_exists_absolute(live):
		return false
	if not DirAccess.dir_exists_absolute(previous):
		return true
	return DirAccess.rename_absolute(previous, live) == OK


## Drop the backup only after the promoted data passes runtime initialization.
static func commit(live: String) -> void:
	Importer._rmdir(live + ".previous")
