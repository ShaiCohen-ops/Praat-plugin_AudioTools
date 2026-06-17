#!/usr/bin/env python3
"""
audiotools_installer.py
Installer / updater for the Praat AudioTools plugin.

Author: Shai Cohen, Department of Music, Bar-Ilan University
License: MIT
Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools

WHAT IT DOES
    1. Auto-detects the Praat preferences folder for your OS.
    2. Shows you the target plugin folder and asks for confirmation
       (you can type a different path if the guess is wrong).
    3. Downloads the latest 'main' branch from GitHub.
    4. Backs up any existing plugin folder.
    5. Installs the new version.

REQUIREMENTS
    - Python 3.6+  (standard library only - no pip installs needed)
    - Internet access

USAGE
    Double-click (if .py is associated with Python) or run:
        python audiotools_installer.py
    Optional flags:
        python audiotools_installer.py --dir "C:\\Users\\User\\Praat"
        python audiotools_installer.py --yes        (skip confirmation)
        python audiotools_installer.py --no-backup
        python audiotools_installer.py --branch main
"""

import argparse
import os
import shutil
import sys
import tempfile
import time
import urllib.request
import zipfile

REPO_OWNER = "ShaiCohen-ops"
REPO_NAME = "Praat-plugin_AudioTools"
PLUGIN_FOLDER_NAME = "plugin_AudioTools"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def log(msg=""):
    print(msg, flush=True)


def hr():
    log("-" * 60)


def praat_pref_dir():
    """Return Praat's preferences directory for the current OS.

    Mirrors Praat's own logic:
      Windows : %USERPROFILE%\\Praat
      macOS   : ~/Library/Preferences/Praat Prefs
      Linux   : ~/.praat-dir
    """
    home = os.path.expanduser("~")
    if sys.platform.startswith("win"):
        base = os.environ.get("USERPROFILE", home)
        return os.path.join(base, "Praat")
    elif sys.platform == "darwin":
        return os.path.join(home, "Library", "Preferences", "Praat Prefs")
    else:
        return os.path.join(home, ".praat-dir")


def confirm(prompt, default_yes=True):
    suffix = " [Y/n] " if default_yes else " [y/N] "
    try:
        ans = input(prompt + suffix).strip().lower()
    except EOFError:
        return default_yes
    if ans == "":
        return default_yes
    return ans in ("y", "yes")


def download(url, dest):
    """Download url -> dest with a simple progress indicator."""
    req = urllib.request.Request(url, headers={"User-Agent": "AudioToolsInstaller"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        total = resp.getheader("Content-Length")
        total = int(total) if total else 0
        got = 0
        chunk = 1024 * 64
        with open(dest, "wb") as f:
            while True:
                data = resp.read(chunk)
                if not data:
                    break
                f.write(data)
                got += len(data)
                if total:
                    pct = 100.0 * got / total
                    sys.stdout.write("\r    Downloading... %5.1f%% (%d KB)" %
                                     (pct, got // 1024))
                else:
                    sys.stdout.write("\r    Downloading... %d KB" % (got // 1024))
                sys.stdout.flush()
    sys.stdout.write("\n")
    sys.stdout.flush()


def find_extracted_root(extract_dir):
    """Return the single top-level folder produced by extraction.

    GitHub zips expand to '<repo>-<branch>/'. We locate it by LISTING
    rather than assuming the name, then verify it is non-empty.
    """
    entries = [os.path.join(extract_dir, e) for e in os.listdir(extract_dir)]
    dirs = [e for e in entries if os.path.isdir(e)]
    if not dirs:
        return None
    # Prefer one starting with the repo name; else take the first dir.
    for d in dirs:
        if os.path.basename(d).startswith(REPO_NAME):
            return d
    return dirs[0]


def copy_tree_over(src, dst):
    """Copy the CONTENTS of src into dst, merging/overwriting files."""
    os.makedirs(dst, exist_ok=True)
    for name in os.listdir(src):
        s = os.path.join(src, name)
        d = os.path.join(dst, name)
        if os.path.isdir(s):
            shutil.copytree(s, d, dirs_exist_ok=True)
        else:
            shutil.copy2(s, d)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(
        description="Install/update the Praat AudioTools plugin.")
    ap.add_argument("--dir", default=None,
                    help="Praat preferences folder (where plugin_AudioTools "
                         "lives). Auto-detected if omitted.")
    ap.add_argument("--branch", default="main", help="Branch to install.")
    ap.add_argument("--yes", action="store_true",
                    help="Skip the confirmation prompt.")
    ap.add_argument("--no-backup", action="store_true",
                    help="Do not back up the existing folder.")
    args = ap.parse_args()

    log("=" * 60)
    log("  Praat AudioTools - Installer / Updater")
    log("=" * 60)
    log()

    # --- 1. Determine target folder ---------------------------------------
    pref_dir = args.dir if args.dir else praat_pref_dir()
    pref_dir = os.path.abspath(os.path.expanduser(pref_dir))
    plugin_dir = os.path.join(pref_dir, PLUGIN_FOLDER_NAME)

    log("Operating system : %s" % sys.platform)
    log("Praat prefs guess: %s" % pref_dir)
    log("Plugin folder    : %s" % plugin_dir)
    if os.path.isdir(plugin_dir):
        log("                   (exists - will be updated)")
    else:
        log("                   (not present - will be created)")
    log()

    if not os.path.isdir(pref_dir):
        log("NOTE: the Praat preferences folder above does not exist yet.")
        log("If that path looks wrong, re-run with:  --dir \"<your path>\"")
        log("(Run praatPrefDir.praat inside Praat to find the exact folder.)")
        log()

    # --- 2. Confirm --------------------------------------------------------
    if not args.yes:
        if not confirm("Install AudioTools into the folder above?"):
            # Offer a manual override before giving up.
            try:
                custom = input(
                    "Enter a different Praat prefs path (or blank to cancel): "
                ).strip()
            except EOFError:
                custom = ""
            if not custom:
                log("Cancelled.")
                return 1
            pref_dir = os.path.abspath(os.path.expanduser(custom))
            plugin_dir = os.path.join(pref_dir, PLUGIN_FOLDER_NAME)
            log("Using: %s" % plugin_dir)

    branch = args.branch
    zip_url = ("https://codeload.github.com/%s/%s/zip/refs/heads/%s"
               % (REPO_OWNER, REPO_NAME, branch))

    # --- 3. Work in a temp dir --------------------------------------------
    tmp = tempfile.mkdtemp(prefix="audiotools_")
    zip_path = os.path.join(tmp, "audiotools.zip")
    extract_dir = os.path.join(tmp, "extract")
    os.makedirs(extract_dir, exist_ok=True)

    try:
        hr()
        log("[1/4] Downloading %s (%s branch)..." % (REPO_NAME, branch))
        try:
            download(zip_url, zip_path)
        except Exception as e:
            log("    ERROR: download failed: %s" % e)
            log("    Check your internet connection and that the repo exists:")
            log("      https://github.com/%s/%s" % (REPO_OWNER, REPO_NAME))
            return 1

        if not os.path.isfile(zip_path) or os.path.getsize(zip_path) < 1000:
            log("    ERROR: the downloaded file is missing or too small.")
            log("    (GitHub may have returned an error page instead of a zip.)")
            return 1
        log("    OK (%d KB)" % (os.path.getsize(zip_path) // 1024))

        hr()
        log("[2/4] Extracting...")
        try:
            with zipfile.ZipFile(zip_path) as z:
                z.extractall(extract_dir)
        except zipfile.BadZipFile:
            log("    ERROR: the downloaded file is not a valid zip archive.")
            return 1

        src_root = find_extracted_root(extract_dir)
        if src_root is None:
            log("    ERROR: extraction produced no folder. Aborting.")
            return 1
        n_items = len(os.listdir(src_root))
        if n_items == 0:
            log("    ERROR: the extracted folder is empty. Aborting.")
            return 1
        log("    OK -> %s (%d items)" % (os.path.basename(src_root), n_items))

        # --- 4. Backup existing, then install -----------------------------
        hr()
        if os.path.isdir(plugin_dir) and not args.no_backup:
            stamp = time.strftime("%Y%m%d_%H%M%S")
            backup = plugin_dir + "_backup_" + stamp
            log("[3/4] Backing up existing folder...")
            shutil.copytree(plugin_dir, backup)
            log("    Backup: %s" % backup)
        else:
            log("[3/4] No existing folder to back up (or backup disabled).")

        hr()
        log("[4/4] Installing...")
        os.makedirs(plugin_dir, exist_ok=True)
        copy_tree_over(src_root, plugin_dir)
        log("    Installed into: %s" % plugin_dir)

        hr()
        log()
        log("SUCCESS - AudioTools is installed.")
        log("IMPORTANT: restart Praat so the new menu and scripts load.")
        log()
        return 0

    finally:
        # Always clean the temp dir.
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    try:
        rc = main()
    except KeyboardInterrupt:
        log("\nCancelled.")
        rc = 1
    # Keep the window open if double-clicked on Windows.
    if sys.platform.startswith("win") and sys.stdin and sys.stdin.isatty():
        try:
            input("\nPress Enter to close...")
        except EOFError:
            pass
    sys.exit(rc)
