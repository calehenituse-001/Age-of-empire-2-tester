# Import activation stability patch — 30 October 2026

This branch makes on-device converted-data activation reversible.

A headless CI regression caught and fixed a pre-existing cleanup defect: Godot's
DirAccess excludes hidden files by default, leaving `.complete` / `.revision`
inside old data folders and preventing deletion/rollback. The shared importer
cleanup now explicitly includes hidden files and does not recurse through
symbolic links. It is not a
graphics/texture replacement and does not change gameplay rules.

## Fixed integration risks

- Conversion output must contain a completion marker, manifest and rules table
  before replacing the current imported directory.
- The previous imported data is retained until `Rules.reload()` and
  `Assets.load_all()` both initialize successfully.
- If that initialization fails, the new directory is removed and the prior
  directory is restored, with a visible error rather than silently continuing.
- If Android kills the app while the previous directory has been moved aside
  but before a new one appears, startup attempts to recover the previous copy.
- Assets reload now clears stale manifest, terrain and cache references before
  reading a different data set.

## Tests and scope

`godot --headless --path godot_game res://tests/import_activation.tscn`
exercises rejection of incomplete staging, successful promotion, rollback,
commit and interrupted-activation recovery with synthetic files. It is added
to `tools/validate_godot.py` for the next CI run.

These checks do **not** establish whether a complete HD 2013 import or actual
rendering works on a Xiaomi 11T. Full import and 15-minute real-device gameplay
remain acceptance gates. Preserve game files and export saves before testing.
No APK needs to be built for this source-only change.
