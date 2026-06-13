"""Safe project deletion and path-safety checks.

Rules implemented (see spec section 16):
  - never delete outside the project folder
  - resolve paths and refuse suspicious targets (home, Desktop, roots, ...)
  - never follow symlinks: a symlinked project root or subfolder is refused
  - option A (default): delete generated data, keep originals/
  - option B: delete the entire project folder
  - log before deleting; leave a deletion summary next to the folder
"""

from __future__ import annotations

import shutil
import time
from pathlib import Path

from . import config
from .project import Project

GENERATED_DIRS = ["autosaved_wav", "latest", "project_state", "logs", "tmp"]


def forbidden_paths() -> set:
    home = Path.home().resolve()
    candidates = {
        home,
        home / "Desktop", home / "Documents", home / "Downloads",
        home / "Music", home / "Pictures",
    }
    candidates.update(Path(p).resolve() for p in ("/", "/usr", "/etc",
                                                  "/var", "/home"))
    for drive in ("C:\\", "C:\\Windows", "C:\\Program Files",
                  "C:\\Users"):
        try:
            candidates.add(Path(drive).resolve())
        except OSError:
            pass
    return candidates


def check_deletable(root: Path) -> str:
    """Return '' if the path is safe to delete as a project, else a reason."""
    try:
        resolved = root.expanduser().resolve(strict=True)
    except (OSError, FileNotFoundError):
        return "path does not exist"
    if root.is_symlink() or resolved != root.expanduser().absolute().resolve():
        # resolve(strict) already followed links; refuse explicit symlink roots
        if root.is_symlink():
            return "project root is a symlink (refusing to follow)"
    if resolved in forbidden_paths():
        return f"refusing to delete protected location: {resolved}"
    if len(resolved.parts) < 3:
        return f"path too close to filesystem root: {resolved}"
    if not (resolved / "project_state").is_dir() and \
       not (resolved / "autosaved_wav").is_dir():
        return ("folder does not look like a Praat_Vangnet project "
                "(no project_state/ or autosaved_wav/)")
    return ""


def _rmtree_no_symlink_descent(path: Path, errors: list):
    """shutil.rmtree, refusing to descend into symlinked directories."""
    if path.is_symlink():
        errors.append(f"skipped symlink: {path}")
        return
    shutil.rmtree(path, onerror=lambda f, p, e: errors.append(f"{p}: {e[1]}"))


def delete_project(project: Project, entire: bool, logger=None) -> list:
    """Delete generated data (entire=False) or the whole folder (True).
    Returns a list of error strings (empty = clean)."""
    reason = check_deletable(project.root)
    if reason:
        return [reason]

    errors: list = []
    summary_lines = [
        f"Praat_Vangnet deletion summary",
        f"time: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"project: {project.name}",
        f"path: {project.root}",
        f"mode: {'ENTIRE project' if entire else 'generated data only'}",
    ]
    if logger:
        logger.info("DELETE requested (%s): %s",
                    "entire" if entire else "generated-only", project.root)

    if entire:
        _rmtree_no_symlink_descent(project.root, errors)
        config.forget_project(project.root, mark_inactive=False)
    else:
        for sub in GENERATED_DIRS:
            d = project.root / sub
            if d.exists():
                _rmtree_no_symlink_descent(d, errors)
        config.forget_project(project.root, mark_inactive=True)

    summary_lines += [f"errors: {len(errors)}"] + errors
    parent = project.root.parent
    try:
        if parent.is_dir():
            summary = parent / f"{project.name}_deletion_summary.txt"
            summary.write_text("\n".join(summary_lines) + "\n",
                               encoding="utf-8")
    except OSError:
        pass
    return errors
