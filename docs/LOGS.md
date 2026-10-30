# Debug logs

- One text file per game session in `user://logs/session_YYYY-MM-DD_HH-MM-SS.txt`.
- Written only when the tablet is NOT attached to a computer (USB debugging on and USB plugged). Menu -> Debug logs -> "Always log" overrides that.
- Menu -> Debug logs: list (date, length, size, errors, how the run ended), open, save to Download/AoE2HDBeta/logs, share / write a mail, delete one or all.
- The app's previous exit reason (crash, killed, normal) is read from Android and added to the previous session's log and to `exits.txt`.
- Keeps 30 sessions, 3 MB per file, 40 MB total.
