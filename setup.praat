# ============================================================
# Praat AudioTools - setup.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Praat AudioTools processing script (plugin_audiotools)
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================
# setup.praat — plugin_AudioTools
# Builds: Objects → Praat → AudioTools - <Folder> → (commands)
# One cascade per first-level subfolder.
# ============================================

toolMenuRoot$ = "AudioTools"

# ---- Enumerate first-level subfolders (relative to plugin_AudioTools) ----
Create Strings as folder list: "AT_folders", "*"
# If your Praat doesn’t support "folder list", use:
# Create Strings as directory list: "AT_folders", "."

selectObject: "Strings AT_folders"
nFolders = Get number of strings
if nFolders > 1
    Sort
endif

added = 0

# ---- For each subfolder, make a cascade and add its scripts ----
for i to nFolders
    selectObject: "Strings AT_folders"
    folder$ = Get string: i

    # Skip hidden/system folders like .git
    if left$(folder$, 1) = "."
        next
    endif

    cascade$ = toolMenuRoot$ + " - " + folder$
    Add menu command: "Objects", "Praat", cascade$, "", 0, ""

    # ---------- Add *.praat scripts ----------
    Create Strings as file list: "AT_files1", folder$ + "/*.praat"
    selectObject: "Strings AT_files1"
    n1 = Get number of strings
    if n1 > 1
        Sort
    endif

    for j to n1
        selectObject: "Strings AT_files1"
        filename$ = Get string: j
        rel$ = folder$ + "/" + filename$

        dot = rindex(filename$, ".")
        if dot = 0
            title$ = filename$
        else
            title$ = left$(filename$, dot - 1)
        endif

        Add menu command: "Objects", "Praat", title$ + "...", cascade$, 1, rel$
        added = added + 1
    endfor
    selectObject: "Strings AT_files1"
    Remove

    # ---------- Add *.praatscript scripts ----------
    Create Strings as file list: "AT_files2", folder$ + "/*.praatscript"
    selectObject: "Strings AT_files2"
    n2 = Get number of strings
    if n2 > 1
        Sort
    endif

    for j2 to n2
        selectObject: "Strings AT_files2"
        filename2$ = Get string: j2
        rel2$ = folder$ + "/" + filename2$

        dot2 = rindex(filename2$, ".")
        if dot2 = 0
            title2$ = filename2$
        else
            title2$ = left$(filename2$, dot2 - 1)
        endif

        Add menu command: "Objects", "Praat", title2$ + "...", cascade$, 1, rel2$
        added = added + 1
    endfor
    selectObject: "Strings AT_files2"
    Remove
endfor

# ---- If nothing was added at all, show a placeholder cascade ----
if added = 0
    Add menu command: "Objects", "Praat", toolMenuRoot$ + " - No scripts found", "", 0, ""
    Add menu command: "Objects", "Praat", "Put *.praat in subfolders", toolMenuRoot$ + " - No scripts found", 1, ""
endif

# ---- Cleanup ----
selectObject: "Strings AT_folders"
Remove
