# Praat_Vangnet

A Python launcher and autosave/project system for Praat. It launches
Praat, periodically exports every **Sound** object in the Objects window
to WAV, keeps timestamped backups plus a `latest/` copy, and can reload
the last session after a crash.

Only Sound objects are protected. TextGrids, Pitch, Formant, Intensity,
Manipulation objects, selections, undo history, editor windows, and
script variables are **not** saved (see Limitations).

## Requirements

- Python 3.8+ (standard library only, no pip installs)
- Praat 6.2 or newer (the `--send` mechanism; older versions can use a
  `sendpraat` binary instead, configurable in Settings)

## Setup

1. Unzip anywhere, e.g. `~/tools/praat_vangnet/`.
2. Run: `python -m praat_vangnet.launcher` from the folder that
   contains the `praat_vangnet/` package directory.
3. On first run the launcher auto-detects Praat or asks for its path.
   Global settings and the recent-projects registry live in
   `~/Praat_Vangnet/` (or your existing `~/PraatAutosave/`, kept for compatibility) (config.json, recent_projects.json).

## Usage

**GUI (recommended):** double-click `Praat_Vangnet.pyw` (Windows), or run
`python -m praat_vangnet.gui`. Buttons mirror the menus below; during a
session you get a live activity log, last-autosave time, a green/red
Praat status, and one-click **Save now**. Closing the window stops
autosave safely; Praat itself stays open.

**Command line:** `python -m praat_vangnet.launcher`.

**Desktop shortcut with the AudioTools icon (Windows):** right-click
`Praat_Vangnet.pyw` > Send to > Desktop (create shortcut). Then
right-click the new shortcut > Properties > Change Icon... > Browse to
`praat_vangnet\assets\icon.ico`. The running window and taskbar use
this icon automatically.

Main menu: Create new project / Open last project / Open recent project /
Restore from backup timestamp / Delete-clean a project / Settings.

A project session launches Praat, (optionally) reloads sounds, then
starts the background autosave loop. The session menu offers: Save now,
Set autosave interval, Open project folder, Clean temporary files, and
Stop autosave safely.

Project structure:

    ProjectName/
      originals/        your source files - NEVER touched by the system
      autosaved_wav/    2026-06-11_14-05-00_name.wav  (timestamped cycles)
      latest/           name_latest.wav               (newest good copy)
      project_state/    last_session.json, backup_index.json
      logs/             autosave_log.txt
      tmp/              all temporary files (cleaned automatically)

Typical crash recovery: reopen the launcher, choose **Open last
project** - Praat starts and the WAVs from `latest/` are loaded with
their original object names. **Restore from backup timestamp** loads a
chosen older cycle from `autosaved_wav/` instead.

## How a save cycle works (atomicity)

1. Python cleans `tmp/`, writes a generated Praat job script there, and
   sends it to the running Praat (`praat --send`, or `sendpraat`).
2. Praat exports each Sound to a numbered temp WAV in `tmp/`, writes a
   manifest (index, status, object name), restores your selection, and
   writes a `done` marker **as its last action**.
3. Python waits for the marker (timeout = freeze detection). On
   timeout/crash, nothing outside `tmp/` is touched and the previous
   backup survives.
4. Python validates each WAV (RIFF header, non-empty), moves it to a
   timestamped name in `autosaved_wav/`, then updates `latest/` via a
   temp file + atomic `os.replace`.
5. State files are updated; old cycles are pruned per the retention
   policy (keep last N cycles, optionally hourly-today and daily
   keepers). `originals/` and `latest/` are never pruned.

## Error-handling strategy

- **Praat crash**: the watcher sees the process exit; the loop stops,
  a crash entry is logged, `latest/` is preserved. The launcher offers
  "Open last project" on the next start.
- **Praat frozen/busy**: no done-marker within the timeout (default
  90 s, configurable) - the cycle is abandoned, logged as UNRESPONSIVE,
  partial temp files are removed, and the loop retries next interval.
- **Partial/corrupt WAVs**: header+size validation per file; invalid
  files are logged as failures and never reach `autosaved_wav/` or
  `latest/`.
- **Name collisions**: object names are sanitized for Windows/macOS/
  Linux and deduplicated with numeric suffixes; timestamped files are
  additionally uniquified rather than overwritten.
- **Deletion safety**: path is resolved and must look like a project;
  home/Desktop/Documents/system roots are refused; symlinked roots are
  refused; default mode keeps `originals/`; a deletion summary is left
  next to the folder; the recents registry is updated.

## Limitations (important)

- Only Sound objects existing **at autosave time** are protected.
  Changes made after the last autosave are lost on a crash, and nothing
  can be recovered for the period before the first autosave.
- WAV stores audio only: object metadata beyond the name (e.g. a
  Sound's original time origin) is not preserved.
- LongSound objects are not exported (they are file-backed already).
- A modal dialog open in Praat (e.g. a form waiting for input) blocks
  sent scripts; those cycles will log as UNRESPONSIVE until the dialog
  is closed. This is a Praat constraint, not a failure.
- If you open Praat yourself (not via the launcher), crash detection by
  process handle is unavailable; freeze detection via ping still works.

## Extending to other object types

`praat_scripts/autosave_job.template.praat` is the only place that
knows the type "Sound". To snapshot TextGrids etc., duplicate the
enumeration block with the new type and a suitable `Save as ...`
command, add an extension column to the manifest, and teach
`autosave.py` the extension -> folder mapping. The Python side is
type-agnostic apart from the `.wav` validation function.

## Testing checklist

- [ ] New project: folder tree created; session menu reachable.
- [ ] Autosave with 0 / 1 / many Sounds (incl. duplicate names, names
      with spaces, Hebrew/Unicode, very long names, name "CON").
- [ ] `Save now` produces a new cycle immediately.
- [ ] User's selection in Praat is identical before/after a cycle.
- [ ] Kill Praat mid-session: crash logged, `latest/` intact, "Open
      last project" restores all sounds with original names.
- [ ] Freeze simulation (open a Praat form, wait a cycle): UNRESPONSIVE
      logged, no changes to `latest/`, recovery on next cycle.
- [ ] Restore from older timestamp loads that cycle's files.
- [ ] Rotation: with keep_last=2, older cycles pruned except hourly/
      daily keepers; `originals/` and `latest/` untouched.
- [ ] Delete option A removes generated dirs, keeps `originals/`,
      marks project inactive; option B removes everything; both refuse
      a symlinked root and protected paths.
- [ ] Stale `tmp/` files from a previous crash are removed on startup.
- [ ] Windows: paths with backslashes and drive letters work end-to-end.
