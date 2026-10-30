# Selecting groups: the lasso (2026-10-22)

Test: `tests/lasso.tscn` (touch events fed to the camera). Code: `RtsCamera` (gesture), `LassoOverlay` (the line on the HUD), `Controller.select_in_lasso`
and `Controller._move_later`, wiring in `Main`.

- **Gesture:** double tap with one finger, **keep the second touch down and draw** a loop round the units, then lift. The map is frozen while you draw
  (no scrolling or zoom). The second touch must come within 300 ms and 90 px of the first tap's release. A second finger cancels the lasso. A double tap
  where the second touch does not move (more than 14 px) is simply two taps.
- **Selection:** every unit of yours (villagers, soldiers, monks, ships) whose body lies inside the loop, which is closed from where you lift to where you
  began. Enemies, animals, garrisoned units and buildings are not selected. "No units there" when the loop is empty.
- **Diagonal drag:** a nearly straight stroke (the loop encloses less than 18 percent of its bounding box) selects the rectangle with the first and last
  point as corners, as dragging a box with the mouse does on a PC.
- **First tap of the double tap:** it acts like any tap. Taps on units, buildings or resources act at once. A tap on empty ground with units selected (a
  move order) waits 0.33 s (`MOVE_DELAY`) and is cancelled when the second touch of a double tap arrives, so starting a lasso does not send the earlier
  selection away. Start the loop on open ground.
- Not while a building or wall is being placed (`RtsCamera.lasso_ok`). The mouse works the same on a desktop (touch is emulated from it).
