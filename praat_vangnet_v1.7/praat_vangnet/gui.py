"""Praat_Vangnet - simple desktop GUI (tkinter, standard library only).

Run with:  python -m praat_vangnet.gui
or double-click Praat_Vangnet.pyw (Windows).
"""

from __future__ import annotations

import logging
import queue
import sys
import threading
import time
from pathlib import Path

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, simpledialog
from tkinter.scrolledtext import ScrolledText

from . import config, rotation, safety
from .autosave import AutosaveManager, make_logger
from .praat_link import MIN_SEND_VERSION, PraatLink, praat_version
from .project import Project
from .launcher import open_folder


# ------------------------------------------------------------ log -> GUI

class QueueLogHandler(logging.Handler):
    def __init__(self, q: queue.Queue):
        super().__init__()
        self.q = q
        self.setFormatter(logging.Formatter("%(asctime)s  %(message)s",
                                            "%H:%M:%S"))

    def emit(self, record):
        try:
            self.q.put_nowait(self.format(record))
        except queue.Full:
            pass


# ------------------------------------------------------------ helpers

def pick_from_list(parent, title: str, items: list):
    """Modal list picker; returns the selected index or None."""
    result = {"i": None}
    win = tk.Toplevel(parent)
    win.title(title)
    win.transient(parent)
    win.grab_set()
    win.geometry("560x320")
    lb = tk.Listbox(win, activestyle="dotbox")
    for it in items:
        lb.insert("end", it)
    lb.pack(fill="both", expand=True, padx=10, pady=10)
    if items:
        lb.selection_set(0)

    def ok(_=None):
        sel = lb.curselection()
        if sel:
            result["i"] = sel[0]
        win.destroy()

    lb.bind("<Double-Button-1>", ok)
    fr = ttk.Frame(win); fr.pack(pady=(0, 10))
    ttk.Button(fr, text="OK", command=ok).pack(side="left", padx=5)
    ttk.Button(fr, text="Cancel", command=win.destroy).pack(side="left")
    parent.wait_window(win)
    return result["i"]


# ------------------------------------------------------------ app

class App:
    def __init__(self):
        self.cfg = config.load_config()
        self.root = tk.Tk()
        self.root.title("Praat_Vangnet")
        self._set_icon()
        self.root.geometry("680x520")
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        self.project: Project | None = None
        self.link: PraatLink | None = None
        self.mgr: AutosaveManager | None = None
        self.log_q: queue.Queue = queue.Queue(maxsize=1000)
        self._crash_announced = False

        self.menu_frame = self._build_menu_frame()
        self.session_frame = self._build_session_frame()
        self.show_menu()
        self.root.after(400, self._tick)

    def _set_icon(self):
        """Window/taskbar icon from the bundled AudioTools logo."""
        assets = Path(__file__).parent / "assets"
        try:
            if sys.platform.startswith("win") and (assets / "icon.ico").exists():
                self.root.iconbitmap(default=str(assets / "icon.ico"))
            elif (assets / "icon.png").exists():
                self._icon_img = tk.PhotoImage(file=str(assets / "icon.png"))
                self.root.iconphoto(True, self._icon_img)
        except tk.TclError:
            pass    # icon is cosmetic; never block startup over it

    # -------------------------------------------------- frames
    def _build_menu_frame(self):
        f = ttk.Frame(self.root, padding=24)
        ttk.Label(f, text="Praat_Vangnet",
                  font=("Segoe UI", 18, "bold")).pack(pady=(0, 4))
        ttk.Label(f, text="Safety net for Praat: autosave & restore "
                          "(Sound objects only)").pack(pady=(0, 18))
        for text, cmd in [
            ("Create new project", self.act_new),
            ("Open last project", self.act_open_last),
            ("Open recent project...", self.act_open_recent),
            ("Restore from backup timestamp...", self.act_restore),
            ("Clean up old backups...", self.act_cleanup_menu),
            ("Delete / clean a project...", self.act_delete),
            ("Settings...", self.act_settings),
        ]:
            ttk.Button(f, text=text, width=36, command=cmd).pack(pady=4)
        self.menu_status = ttk.Label(f, text="", foreground="gray")
        self.menu_status.pack(pady=(16, 0))
        return f

    def _build_session_frame(self):
        f = ttk.Frame(self.root, padding=14)
        top = ttk.Frame(f); top.pack(fill="x")
        self.lbl_project = ttk.Label(top, text="", font=("Segoe UI", 13, "bold"))
        self.lbl_project.pack(side="left")
        self.lbl_status = ttk.Label(top, text="", font=("Segoe UI", 11))
        self.lbl_status.pack(side="right")

        info = ttk.Frame(f); info.pack(fill="x", pady=(6, 8))
        self.lbl_lastsave = ttk.Label(info, text="Last autosave: -")
        self.lbl_lastsave.pack(side="left")
        self.lbl_interval = ttk.Label(info, text="")
        self.lbl_interval.pack(side="right")

        btns = ttk.Frame(f); btns.pack(fill="x", pady=(0, 8))
        self.btn_save = ttk.Button(btns, text="Save now",
                                   command=self.act_save_now)
        self.btn_save.pack(side="left", padx=(0, 6))
        ttk.Button(btns, text="Set interval...",
                   command=self.act_interval).pack(side="left", padx=6)
        ttk.Button(btns, text="Open project folder",
                   command=lambda: open_folder(self.project.root)
                   ).pack(side="left", padx=6)
        ttk.Button(btns, text="Clean temp files",
                   command=self.act_clean_tmp).pack(side="left", padx=6)
        ttk.Button(btns, text="Clean up backups...",
                   command=lambda: self.cleanup_backups(self.project)
                   ).pack(side="left", padx=6)
        ttk.Button(btns, text="Stop && back to menu",
                   command=self.act_stop_session).pack(side="right")
        self.btn_exit = ttk.Button(btns, text="Save, close Praat && exit",
                                   command=self.act_save_close_exit)
        self.btn_exit.pack(side="right", padx=6)

        ttk.Label(f, text="Activity log:").pack(anchor="w")
        self.log_view = ScrolledText(f, height=16, state="disabled",
                                     font=("Consolas", 9))
        self.log_view.pack(fill="both", expand=True)
        return f

    def show_menu(self):
        self.session_frame.pack_forget()
        self.menu_frame.pack(fill="both", expand=True)

    def show_session(self):
        self.menu_frame.pack_forget()
        self.session_frame.pack(fill="both", expand=True)

    # -------------------------------------------------- periodic update
    def _tick(self):
        # drain log queue into the text view
        drained = False
        while True:
            try:
                line = self.log_q.get_nowait()
            except queue.Empty:
                break
            drained = True
            self.log_view.configure(state="normal")
            self.log_view.insert("end", line + "\n")
            self.log_view.configure(state="disabled")
        if drained:
            self.log_view.see("end")

        if self.mgr and self.project:
            sess = self.project.read_session()
            self.lbl_lastsave.config(
                text=f"Last autosave: {sess.get('last_autosave_time') or '-'}")
            self.lbl_interval.config(
                text=f"Interval: {self.mgr.interval_s / 60:g} min")
            crashed = self.mgr.praat_crashed or not self.link.praat_alive()
            if crashed:
                self.lbl_status.config(text="PRAAT CLOSED / CRASHED",
                                       foreground="red")
                self.btn_save.state(["disabled"])
                if not self._crash_announced:
                    self._crash_announced = True
                    messagebox.showwarning(
                        "Praat closed",
                        "Praat has exited or crashed.\n\nYour last "
                        "successful autosave is preserved in latest/.\n"
                        "Use 'Open last project' to restore it.")
            else:
                self.lbl_status.config(text="Praat running, autosave active",
                                       foreground="green")
        self.root.after(400, self._tick)

    # -------------------------------------------------- session start
    def _ensure_praat_path(self) -> bool:
        p = self.cfg.get("praat_path", "")
        if p and Path(p).expanduser().exists():
            return True
        for cand in config.default_praat_candidates():
            if Path(cand).exists():
                self.cfg["praat_path"] = cand
                config.save_config(self.cfg)
                return True
        messagebox.showinfo("Praat location",
                            "Please locate your Praat executable.")
        p = filedialog.askopenfilename(title="Select Praat executable")
        if p:
            self.cfg["praat_path"] = p
            config.save_config(self.cfg)
            return True
        return False

    def start_session(self, project: Project, load_pairs=None):
        if not self._ensure_praat_path():
            return
        # version gate (unless sendpraat is configured)
        if not self.cfg.get("sendpraat_path", "").strip():
            ver = praat_version(self.cfg["praat_path"])
            if ver and ver < MIN_SEND_VERSION:
                messagebox.showerror(
                    "Praat too old",
                    f"Your Praat is {ver[0]}.{ver[1]}; autosave needs "
                    f"{MIN_SEND_VERSION[0]}.{MIN_SEND_VERSION[1]}+ "
                    f"(praat --send).\nDownload the current Praat from "
                    f"praat.org, or set a sendpraat path in Settings.")
                return

        self.project = project
        logger = make_logger(project)
        # attach GUI log handler once per logger
        if not any(isinstance(h, QueueLogHandler) for h in logger.handlers):
            logger.addHandler(QueueLogHandler(self.log_q))
        project.clean_tmp(logger)
        self.link = PraatLink(self.cfg["praat_path"],
                              self.cfg.get("sendpraat_path", ""),
                              self.cfg["job_timeout_seconds"], logger)
        self._crash_announced = False
        self.lbl_project.config(text=project.name)
        self.lbl_status.config(text="Starting Praat...", foreground="black")
        self.show_session()

        def worker():
            ok = self.link.launch_and_attach(project.tmp, total=90)
            if not ok:
                self.root.after(0, lambda: (
                    messagebox.showerror(
                        "Praat not responding",
                        "Praat did not become responsive.\nAutosave did "
                        "NOT start; nothing was saved or deleted, and no "
                        "Praat window was closed."),
                    self.show_menu()))
                return
            if load_pairs:
                if not self.link.load_files(load_pairs, project.tmp):
                    logger.error("restore job failed or timed out")
            config.remember_project(project.root)
            self.mgr = AutosaveManager(project, self.link, self.cfg)
            self.mgr.start()

        threading.Thread(target=worker, daemon=True).start()

    # -------------------------------------------------- menu actions
    def act_new(self):
        name = simpledialog.askstring("New project", "Project name:",
                                      parent=self.root)
        if not name:
            return
        projects_dir = Path(self.cfg["projects_dir"]).expanduser()
        projects_dir.mkdir(parents=True, exist_ok=True)
        root = projects_dir / name
        if root.exists():
            messagebox.showerror("Exists",
                                 "A folder with that name already exists.")
            return
        self.start_session(Project.create(root))

    def _recents(self) -> list:
        rec = config.load_recents()
        return [p for p in rec.get("recent_projects", [])
                if Path(p).exists()]

    def _resolve_pairs(self, project: Project, restore_from: str = ""):
        if restore_from:
            return project.files_for_timestamp(restore_from)
        pairs = project.latest_files()
        sess = project.read_session()
        latest, names = sess.get("latest_files", []), \
            sess.get("object_names", [])
        if latest and names and len(latest) == len(names):
            mapping = {fn: nm for fn, nm in zip(latest, names)}
            pairs = [(p, mapping.get(p.name, base)) for p, base in pairs]
        return pairs

    def _open_at(self, path_str: str, restore_from: str = ""):
        project = Project(Path(path_str))
        if not project.is_valid():
            messagebox.showerror("Invalid project",
                                 f"Missing project_state/ in:\n{path_str}")
            return
        Project.create(project.root)
        pairs = self._resolve_pairs(project, restore_from)
        if not pairs:
            messagebox.showinfo("Nothing to restore",
                                "No saved sounds found; opening Praat empty.")
        self.start_session(project, load_pairs=pairs or None)

    def act_open_last(self):
        last = config.load_recents().get("last_opened_project", "")
        if not last:
            messagebox.showinfo("No last project",
                                "No last project recorded yet.")
            return
        self._open_at(last)

    def act_open_recent(self):
        recents = self._recents()
        if not recents:
            messagebox.showinfo("Empty", "No recent projects.")
            return
        i = pick_from_list(self.root, "Open recent project", recents)
        if i is not None:
            self._open_at(recents[i])

    def act_restore(self):
        recents = self._recents()
        if not recents:
            messagebox.showinfo("Empty", "No recent projects.")
            return
        i = pick_from_list(self.root, "Restore - choose project", recents)
        if i is None:
            return
        project = Project(Path(recents[i]))
        stamps = project.list_backup_timestamps()
        if not stamps:
            messagebox.showinfo("No backups",
                                "No timestamped backups in autosaved_wav/.")
            return
        j = pick_from_list(self.root, "Choose backup (newest first)",
                           stamps[:60])
        if j is not None:
            self._open_at(recents[i], restore_from=stamps[j])

    def act_delete(self):
        recents = self._recents()
        if not recents:
            messagebox.showinfo("Empty", "No projects in the recent list.")
            return
        i = pick_from_list(self.root, "Delete / clean project", recents)
        if i is None:
            return
        project = Project(Path(recents[i]))
        mode = pick_from_list(self.root, f"Options for: {project.name}", [
            "Delete generated data, KEEP originals/  (recommended)",
            "Delete ENTIRE project folder including originals/",
            "Remove from recent list only (delete nothing)",
        ])
        if mode is None:
            return
        if mode == 2:
            config.forget_project(project.root)
            messagebox.showinfo("Done", "Removed from list; nothing deleted.")
            return
        entire = (mode == 1)
        detail = ("EVERYTHING, including originals/." if entire else
                  "autosaved_wav/, latest/, project_state/, logs/, tmp/\n"
                  "(originals/ is kept)")
        confirm = simpledialog.askstring(
            "Confirm deletion",
            f"Will delete from:\n{project.root}\n\n{detail}\n\n"
            f"Type the project name ({project.name}) to confirm:",
            parent=self.root)
        if confirm != project.name:
            messagebox.showinfo("Cancelled", "Name mismatch; nothing deleted.")
            return
        errors = safety.delete_project(project, entire=entire)
        if errors:
            messagebox.showwarning("Completed with issues", "\n".join(errors))
        else:
            messagebox.showinfo("Deleted", "Deleted successfully.")

    def act_cleanup_menu(self):
        recents = self._recents()
        if not recents:
            messagebox.showinfo("Empty", "No recent projects.")
            return
        i = pick_from_list(self.root, "Clean up backups - choose project",
                           recents)
        if i is not None:
            self.cleanup_backups(Project(Path(recents[i])))

    def cleanup_backups(self, project: Project):
        if project is None:
            return
        if self.mgr and self.project and \
                self.project.root == project.root and \
                self.mgr.is_busy_saving():
            messagebox.showinfo("Busy", "An autosave is running; "
                                        "try again in a moment.")
            return
        n_files, size = rotation.backup_usage(project)
        stamps = project.list_backup_timestamps()
        if not n_files:
            messagebox.showinfo(
                "Nothing to clean",
                "autosaved_wav/ is empty.\nlatest/ and originals/ are "
                "never touched by cleanup anyway.")
            return
        info = (f"{project.name}: {len(stamps)} backup cycle(s), "
                f"{n_files} file(s), {size / 1e6:.1f} MB")
        mode = pick_from_list(self.root, f"Clean up backups - {info}", [
            "Apply the retention policy now (from Settings)",
            "Keep only the newest N cycles...",
            "Delete ALL timestamped backups (latest/ is kept)",
        ])
        if mode is None:
            return
        logger = make_logger(project)
        if mode == 0:
            deleted = rotation.rotate(project, self.cfg["retention"], logger)
            messagebox.showinfo("Done",
                                f"Retention policy applied: removed "
                                f"{deleted} file(s).")
            return
        if mode == 1:
            n = simpledialog.askinteger(
                "Keep newest N", "How many cycles to keep:",
                initialvalue=5, minvalue=1, parent=self.root)
            if n is None:
                return
        else:
            n = 0
        doomed = max(0, len(stamps) - n)
        what = ("ALL timestamped backups" if n == 0 else
                f"everything except the newest {n} cycle(s)")
        if not messagebox.askyesno(
                "Confirm cleanup",
                f"Delete {what} from autosaved_wav/?\n"
                f"({doomed} cycle(s) will be removed.)\n\n"
                f"latest/ and originals/ are NOT touched."):
            return
        deleted, freed = rotation.prune_keep_n(project, n, logger)
        messagebox.showinfo(
            "Done", f"Removed {deleted} file(s), freed {freed / 1e6:.1f} MB."
                    f"\nlatest/ and originals/ untouched.")

    def act_settings(self):
        win = tk.Toplevel(self.root)
        win.title("Settings")
        win.transient(self.root); win.grab_set()
        rows = ttk.Frame(win, padding=14); rows.pack(fill="both", expand=True)
        entries = {}

        def add_row(r, label, key, value, browse=None):
            ttk.Label(rows, text=label).grid(row=r, column=0, sticky="w",
                                             pady=3)
            e = ttk.Entry(rows, width=48)
            e.insert(0, str(value))
            e.grid(row=r, column=1, padx=6)
            entries[key] = e
            if browse:
                ttk.Button(rows, text="...", width=3,
                           command=lambda: self._browse_into(e, browse)
                           ).grid(row=r, column=2)

        add_row(0, "Praat executable", "praat_path",
                self.cfg["praat_path"], browse="file")
        add_row(1, "sendpraat (optional)", "sendpraat_path",
                self.cfg["sendpraat_path"], browse="file")
        add_row(2, "Projects folder", "projects_dir",
                self.cfg["projects_dir"], browse="dir")
        add_row(3, "Autosave interval (min)", "autosave_interval_minutes",
                self.cfg["autosave_interval_minutes"])
        add_row(4, "Keep last N cycles", "keep_last_cycles",
                self.cfg["retention"]["keep_last_cycles"])

        hv = tk.BooleanVar(value=self.cfg["retention"]["keep_hourly_today"])
        dv = tk.BooleanVar(value=self.cfg["retention"]["keep_daily"])
        ttk.Checkbutton(rows, text="Keep hourly backups for today",
                        variable=hv).grid(row=5, column=0, columnspan=2,
                                          sticky="w")
        ttk.Checkbutton(rows, text="Keep daily backups",
                        variable=dv).grid(row=6, column=0, columnspan=2,
                                          sticky="w")

        def save():
            try:
                self.cfg["praat_path"] = entries["praat_path"].get().strip()
                self.cfg["sendpraat_path"] = \
                    entries["sendpraat_path"].get().strip()
                self.cfg["projects_dir"] = \
                    entries["projects_dir"].get().strip()
                self.cfg["autosave_interval_minutes"] = float(
                    entries["autosave_interval_minutes"].get())
                self.cfg["retention"]["keep_last_cycles"] = int(
                    entries["keep_last_cycles"].get())
                self.cfg["retention"]["keep_hourly_today"] = hv.get()
                self.cfg["retention"]["keep_daily"] = dv.get()
                config.save_config(self.cfg)
                win.destroy()
            except ValueError:
                messagebox.showerror("Invalid", "Check the numeric fields.",
                                     parent=win)

        ttk.Button(rows, text="Save", command=save).grid(row=7, column=1,
                                                         pady=(12, 0))

    def _browse_into(self, entry: ttk.Entry, kind: str):
        p = (filedialog.askopenfilename() if kind == "file"
             else filedialog.askdirectory())
        if p:
            entry.delete(0, "end")
            entry.insert(0, p)

    # -------------------------------------------------- session actions
    def act_save_now(self):
        if self.mgr:
            self.mgr.save_now()

    def act_interval(self):
        if not self.mgr:
            return
        m = simpledialog.askfloat("Autosave interval", "Minutes:",
                                  initialvalue=self.mgr.interval_s / 60,
                                  minvalue=0.5, parent=self.root)
        if m:
            self.mgr.set_interval_minutes(m)

    def act_clean_tmp(self):
        if self.mgr and self.mgr.is_busy_saving():
            messagebox.showinfo("Busy", "An autosave is running; "
                                        "try again in a moment.")
            return
        if self.project:
            n = self.project.clean_tmp(self.mgr.logger if self.mgr else None)
            messagebox.showinfo("Cleaned", f"Removed {n} temp file(s).")

    def act_stop_session(self):
        def worker():
            if self.mgr:
                self.mgr.stop(wait=True)
                self.mgr = None
            self.root.after(0, self.show_menu)
        threading.Thread(target=worker, daemon=True).start()
        self.lbl_status.config(text="Stopping autosave...",
                               foreground="black")

    def act_save_close_exit(self):
        if not self.mgr or not self.project:
            return
        if self.mgr.praat_crashed or not self.link.praat_alive():
            messagebox.showinfo("Praat already closed",
                                "Praat is not running; just exiting.")
            self.root.destroy()
            return
        if not messagebox.askyesno(
                "Save, close Praat and exit",
                "This will:\n  1. run a final autosave of all Sounds\n"
                "  2. close Praat\n  3. close this window\n\nProceed?"):
            return
        self.btn_exit.state(["disabled"])
        self.btn_save.state(["disabled"])
        self.lbl_status.config(text="Final save, then closing...",
                               foreground="black")

        def worker():
            mgr, link, project = self.mgr, self.link, self.project
            mgr.stop(wait=True)              # waits out any running cycle
            before = project.read_session().get("last_autosave_time", "")
            mgr.run_cycle(manual=True, history=False)   # final: latest/ only
            after = project.read_session().get("last_autosave_time", "")
            landed = after and after != before

            def finish():
                if not landed:
                    messagebox.showerror(
                        "Final save did not complete",
                        "Praat did not confirm the final save, so Praat "
                        "was NOT closed.\nCheck Praat (a running script "
                        "or open dialog blocks saving), then try again "
                        "or close Praat manually.")
                    self.btn_exit.state(["!disabled"])
                    self.btn_save.state(["!disabled"])
                    # resume the autosave loop so work stays protected
                    self.mgr = AutosaveManager(project, link, self.cfg)
                    self.mgr.start()
                    return
                quit_ok = link.quit_praat(project.tmp)
                if not quit_ok:
                    messagebox.showwarning(
                        "Praat did not confirm closing",
                        "The final save SUCCEEDED, but Praat did not "
                        "acknowledge the quit request.\nYour work is "
                        "safe in latest/; close Praat manually.")
                self.root.destroy()

            self.root.after(0, finish)

        threading.Thread(target=worker, daemon=True).start()

    def on_close(self):
        if self.mgr and not self.mgr.praat_crashed:
            if not messagebox.askyesno(
                    "Quit", "Stop autosave and quit?\n(Praat itself "
                            "stays open.)"):
                return
            self.mgr.stop(wait=False)
        self.root.destroy()

    def run(self):
        self.root.mainloop()


def main():
    App().run()


if __name__ == "__main__":
    main()
