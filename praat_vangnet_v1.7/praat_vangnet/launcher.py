"""Praat_Vangnet launcher (CLI).

Run with:  python -m praat_vangnet.launcher
"""

from __future__ import annotations

import os
import subprocess
import sys
import webbrowser
from pathlib import Path

from . import config, rotation, safety
from .autosave import AutosaveManager, make_logger
from .praat_link import MIN_SEND_VERSION, PraatLink, praat_version
from .project import Project


# ---------------------------------------------------------------- helpers

def ask(prompt: str, default: str = "") -> str:
    s = input(f"{prompt}{f' [{default}]' if default else ''}: ").strip()
    return s or default


def pick(title: str, options: list) -> int:
    """Numbered menu; returns index into options, or -1 for cancel."""
    print(f"\n{title}")
    for i, opt in enumerate(options, 1):
        print(f"  {i}. {opt}")
    print("  0. Back/Cancel")
    while True:
        s = input("> ").strip()
        if s == "0":
            return -1
        if s.isdigit() and 1 <= int(s) <= len(options):
            return int(s) - 1
        print("Please enter a number from the list.")


def ensure_praat_path(cfg: dict) -> str:
    p = cfg.get("praat_path", "")
    if p and Path(p).expanduser().exists():
        return p
    for cand in config.default_praat_candidates():
        if Path(cand).exists():
            print(f"Found Praat at: {cand}")
            cfg["praat_path"] = cand
            config.save_config(cfg)
            return cand
    while True:
        p = ask("Path to the Praat executable (.exe / binary / .app)")
        if p and Path(p).expanduser().exists():
            cfg["praat_path"] = str(Path(p).expanduser())
            config.save_config(cfg)
            return cfg["praat_path"]
        print("Not found, try again.")


def open_folder(path: Path):
    try:
        if sys.platform.startswith("win"):
            os.startfile(str(path))                      # type: ignore
        elif sys.platform == "darwin":
            subprocess.Popen(["open", str(path)])
        else:
            subprocess.Popen(["xdg-open", str(path)])
    except OSError:
        print(f"(could not open file manager; folder is: {path})")


# ---------------------------------------------------------------- flows

def start_session(project: Project, cfg: dict, load_pairs=None):
    """Launch Praat, optionally load WAVs, run autosave until user exits."""
    logger = make_logger(project)
    project.clean_tmp(logger)                    # stale-temp scan on startup

    # Verify the transport BEFORE launching anything: praat --send needs 6.2+
    if not cfg.get("sendpraat_path", "").strip():
        ver = praat_version(cfg["praat_path"])
        if ver is None:
            print("Could not determine the Praat version (ran "
                  "'Praat.exe --version').")
            print("If autosave fails below, your Praat is probably too old.")
        elif ver < MIN_SEND_VERSION:
            print(f"Your Praat is version {ver[0]}.{ver[1]}, but the "
                  f"autosave transport (praat --send) needs "
                  f"{MIN_SEND_VERSION[0]}.{MIN_SEND_VERSION[1]} or newer.")
            print("Fix: download the current Praat from praat.org and set "
                  "its path in Settings,")
            print("     or configure a sendpraat executable in Settings.")
            logger.error("Praat %d.%d too old for --send; session aborted",
                         *ver)
            return
        else:
            logger.info("Praat %d.%d detected; --send transport OK", *ver)

    link = PraatLink(cfg["praat_path"], cfg.get("sendpraat_path", ""),
                     cfg["job_timeout_seconds"], logger)

    print("Starting or attaching to Praat...")
    if not link.launch_and_attach(project.tmp, total=90):
        print("Praat did not become responsive; aborting session.")
        print("(Autosave did NOT start. Nothing was saved or deleted, "
              "and no Praat window was closed.)")
        logger.error("Praat never answered the startup ping")
        return
    print("Connected to Praat." if link.process is None
          else "Praat launched.")

    if load_pairs:
        print(f"Loading {len(load_pairs)} sound(s) into Praat...")
        if link.load_files(load_pairs, project.tmp):
            logger.info("restored %d sound(s) into Praat", len(load_pairs))
        else:
            logger.error("restore job failed or timed out")
            print("Warning: the restore job did not confirm completion.")

    config.remember_project(project.root)
    mgr = AutosaveManager(project, link, cfg)
    mgr.start()
    session_menu(project, mgr, link, cfg)


def session_menu(project: Project, mgr: AutosaveManager,
                 link: PraatLink, cfg: dict):
    while True:
        if mgr.praat_crashed or not link.praat_alive():
            print("\n*** Praat has exited or crashed. ***")
            print("Your last successful autosave is preserved in latest/.")
            print("Reopen the launcher and choose 'Open last project'.")
            mgr.stop(wait=False)
            return
        choice = pick(f"Project '{project.name}' - session menu", [
            "Save now",
            "Set autosave interval",
            "Open project folder",
            "Clean temporary files",
            "Stop autosave safely and exit session",
            "Save, close Praat and exit",
            "Clean up old backups",
        ])
        if choice == 0:
            mgr.save_now()
        elif choice == 1:
            try:
                m = float(ask("Interval in minutes",
                              str(mgr.interval_s / 60)))
                mgr.set_interval_minutes(m)
            except ValueError:
                print("Not a number.")
        elif choice == 2:
            open_folder(project.root)
        elif choice == 3:
            if mgr.is_busy_saving():
                print("An autosave is running; try again in a moment.")
            else:
                n = project.clean_tmp(mgr.logger)
                print(f"Removed {n} temp file(s).")
        elif choice in (4, -1):
            print("Stopping autosave (waiting for any running cycle)...")
            mgr.stop(wait=True)
            print("Autosave stopped. Praat stays open; closing the "
                  "launcher will NOT close Praat.")
            return
        elif choice == 5:
            print("Final save (latest/ only)...")
            mgr.stop(wait=True)
            before = project.read_session().get("last_autosave_time", "")
            mgr.run_cycle(manual=True, history=False)
            after = project.read_session().get("last_autosave_time", "")
            if not (after and after != before):
                print("Final save did NOT complete; Praat was NOT closed.")
                print("Check Praat (running script / open dialog), then "
                      "retry. Restarting autosave loop.")
                mgr = AutosaveManager(project, link, cfg)
                mgr.start()
                continue
            print("Final save confirmed. Closing Praat...")
            if not link.quit_praat(project.tmp):
                print("Praat did not acknowledge the quit request; your "
                      "work is safe in latest/ - close Praat manually.")
            return
        elif choice == 6:
            n_files, size = rotation.backup_usage(project)
            stamps = project.list_backup_timestamps()
            print(f"{len(stamps)} cycle(s), {n_files} file(s), "
                  f"{size / 1e6:.1f} MB in autosaved_wav/")
            sub = pick("Clean up backups (latest/ is never touched)", [
                "Apply retention policy now",
                "Keep only the newest N cycles",
                "Delete ALL timestamped backups",
            ])
            if sub == 0:
                d = rotation.rotate(project, cfg["retention"], mgr.logger)
                print(f"Removed {d} file(s).")
            elif sub in (1, 2):
                n = 0
                if sub == 1:
                    try:
                        n = max(1, int(ask("Cycles to keep", "5")))
                    except ValueError:
                        print("Not a number."); continue
                if ask(f"Type YES to delete all but the newest {n} "
                       f"cycle(s)") == "YES":
                    d, freed = rotation.prune_keep_n(project, n, mgr.logger)
                    print(f"Removed {d} file(s), freed {freed/1e6:.1f} MB.")
                else:
                    print("Cancelled.")


def flow_new_project(cfg: dict):
    projects_dir = Path(cfg["projects_dir"]).expanduser()
    projects_dir.mkdir(parents=True, exist_ok=True)
    name = ask("New project name")
    if not name:
        return
    root = projects_dir / name
    if root.exists():
        print("A folder with that name already exists.")
        return
    project = Project.create(root)
    print(f"Created: {project.root}")
    print("Tip: copy your source WAVs into originals/ - they are never "
          "touched by autosave or rotation.")
    start_session(project, cfg)


def _open_project_at(path_str: str, cfg: dict, restore_from: str = ""):
    project = Project(Path(path_str))
    if not project.is_valid():
        print(f"Not a valid project (missing project_state/): {path_str}")
        return
    Project.create(project.root)                # re-create missing subdirs
    if restore_from:
        pairs = [(p, base) for p, base in
                 project.files_for_timestamp(restore_from)]
        label = f"backup {restore_from}"
    else:
        pairs = project.latest_files()
        # prefer original (pre-sanitization) object names when recorded
        session = project.read_session()
        latest, names = session.get("latest_files", []), \
            session.get("object_names", [])
        if latest and names and len(latest) == len(names):
            mapping = {fn: nm for fn, nm in zip(latest, names)}
            pairs = [(p, mapping.get(p.name, base)) for p, base in pairs]
        label = "latest/"
    if not pairs:
        print(f"No saved sounds found in {label}; opening Praat empty.")
    else:
        print(f"Will restore {len(pairs)} sound(s) from {label}.")
    start_session(project, cfg, load_pairs=pairs or None)


def flow_open_last(cfg: dict):
    rec = config.load_recents()
    last = rec.get("last_opened_project", "")
    if not last:
        print("No last project recorded yet.")
        return
    _open_project_at(last, cfg)


def flow_open_recent(cfg: dict):
    rec = config.load_recents()
    recents = [p for p in rec.get("recent_projects", []) if Path(p).exists()]
    if not recents:
        print("No recent projects.")
        return
    i = pick("Open recent project", recents)
    if i >= 0:
        _open_project_at(recents[i], cfg)


def flow_restore_timestamp(cfg: dict):
    rec = config.load_recents()
    recents = [p for p in rec.get("recent_projects", []) if Path(p).exists()]
    if not recents:
        print("No recent projects.")
        return
    i = pick("Restore from backup - choose project", recents)
    if i < 0:
        return
    project = Project(Path(recents[i]))
    stamps = project.list_backup_timestamps()
    if not stamps:
        print("No timestamped backups found in autosaved_wav/.")
        return
    j = pick("Choose backup timestamp (newest first)", stamps[:40])
    if j >= 0:
        _open_project_at(recents[i], cfg, restore_from=stamps[j])


def flow_delete(cfg: dict):
    rec = config.load_recents()
    recents = [p for p in rec.get("recent_projects", []) if Path(p).exists()]
    if not recents:
        print("No projects in the recent list.")
        return
    i = pick("Delete/clean project", recents)
    if i < 0:
        return
    project = Project(Path(recents[i]))
    mode = pick(f"Delete options for: {project.root}", [
        "Delete generated data, KEEP originals/  (recommended default)",
        "Delete ENTIRE project folder including originals/",
        "Remove from recent list only (delete nothing)",
    ])
    if mode == -1:
        return
    if mode == 2:
        config.forget_project(project.root)
        print("Removed from recent list. No files deleted.")
        return
    entire = (mode == 1)
    print("\nThis will permanently delete from:")
    print(f"  {project.root}")
    if entire:
        print("  EVERYTHING, including originals/.")
    else:
        print("  autosaved_wav/, latest/, project_state/, logs/, tmp/")
        print("  (originals/ is kept)")
    if ask("Type the project name to confirm") != project.name:
        print("Name mismatch - nothing deleted.")
        return
    logger = make_logger(project) if not entire else None
    errors = safety.delete_project(project, entire=entire, logger=logger)
    if errors:
        print("Completed with issues:")
        for e in errors:
            print("  -", e)
    else:
        print("Deleted successfully.")


def flow_settings(cfg: dict):
    while True:
        i = pick("Settings", [
            f"Praat executable [{cfg['praat_path'] or 'auto'}]",
            f"sendpraat executable (optional) [{cfg['sendpraat_path'] or 'not used'}]",
            f"Default projects folder [{cfg['projects_dir']}]",
            f"Default autosave interval [{cfg['autosave_interval_minutes']} min]",
            f"Retention: keep last cycles [{cfg['retention']['keep_last_cycles']}]",
            f"Retention: keep hourly today [{cfg['retention']['keep_hourly_today']}]",
            f"Retention: keep daily [{cfg['retention']['keep_daily']}]",
        ])
        if i == -1:
            return
        try:
            if i == 0:
                cfg["praat_path"] = ask("Praat path", cfg["praat_path"])
            elif i == 1:
                cfg["sendpraat_path"] = ask("sendpraat path (empty = use "
                                            "praat --send)",
                                            cfg["sendpraat_path"])
            elif i == 2:
                cfg["projects_dir"] = ask("Projects folder",
                                          cfg["projects_dir"])
            elif i == 3:
                cfg["autosave_interval_minutes"] = float(
                    ask("Minutes", str(cfg["autosave_interval_minutes"])))
            elif i == 4:
                cfg["retention"]["keep_last_cycles"] = int(
                    ask("Keep last N cycles",
                        str(cfg["retention"]["keep_last_cycles"])))
            elif i == 5:
                cfg["retention"]["keep_hourly_today"] = \
                    ask("Keep hourly today (y/n)", "y").lower().startswith("y")
            elif i == 6:
                cfg["retention"]["keep_daily"] = \
                    ask("Keep daily (y/n)", "y").lower().startswith("y")
            config.save_config(cfg)
        except ValueError:
            print("Invalid value, not saved.")


def main():
    print("=" * 56)
    print(" Praat_Vangnet - safety net (autosave & restore) for Praat")
    print("=" * 56)
    cfg = config.load_config()
    ensure_praat_path(cfg)
    while True:
        i = pick("Main menu", [
            "Create new project",
            "Open last project",
            "Open recent project",
            "Restore from backup timestamp",
            "Delete / clean a project",
            "Settings",
        ])
        if i == -1:
            print("Bye. (Praat, if open, stays open.)")
            return
        [flow_new_project, flow_open_last, flow_open_recent,
         flow_restore_timestamp, flow_delete, flow_settings][i](cfg)


if __name__ == "__main__":
    main()
