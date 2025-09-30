# ============================================
# setup.praat — plugin_AudioTools
# Builds: Objects → Praat → AudioTools - <Folder> → (commands)
# One cascade per first-level subfolder.
# ============================================

# ---- Enumerate first-level subfolders (relative to plugin_AudioTools) ----
Create Strings as folder list: "AT_folders", "*"
selectObject: "Strings AT_folders"
nf = Get number of strings

added = 0

# ---- For each subfolder, make a cascade and add its scripts ----
for i to nf
    selectObject: "Strings AT_folders"
    folder$ = Get string: i

    # Skip hidden/system folders like .git
    if left$(folder$, 1) = "."
        next
    endif

    # Cascade name for this folder (appears as a separate menu under Praat)
    cascade$ = "AudioTools - " + folder$

    # Create the cascade (depth 0 under Praat)
    Add menu command: "Objects", "Praat", cascade$, "", 0, ""

    # ---------- Add *.praat scripts ----------
    Create Strings as file list: "AT_files1", folder$ + "/*.praat"
    selectObject: "Strings AT_files1"
    n1 = Get number of strings

    if n1 > 0
        for j to n1
            selectObject: "Strings AT_files1"
            filename$ = Get string: j
            rel$ = folder$ + "/" + filename$

            # Title without extension
            dot = rindex(filename$, ".")
            if dot = 0
                title$ = filename$
            else
                title$ = left$(filename$, dot - 1)
            endif

            # Add the command into this folder's cascade (depth 1)
            Add menu command: "Objects", "Praat", title$ + "...", cascade$, 1, rel$
            added = added + 1
        endfor
    endif
    selectObject: "Strings AT_files1"
    Remove

    # ---------- Add *.praatscript scripts (alternate extension) ----------
    Create Strings as file list: "AT_files2", folder$ + "/*.praatscript"
    selectObject: "Strings AT_files2"
    n2 = Get number of strings

    if n2 > 0
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
    endif
    selectObject: "Strings AT_files2"
    Remove
endfor

# ---- Optional: include scripts in the plugin root (no subfolder) ----
# Put these into a general cascade.
Create Strings as file list: "AT_root1", "*.praat"
selectObject: "Strings AT_root1"
nr1 = Get number of strings

if nr1 > 0
    cascadeRoot$ = "AudioTools - Root"
    Add menu command: "Objects", "Praat", cascadeRoot$, "", 0, ""
    for k to nr1
        selectObject: "Strings AT_root1"
        rfile$ = Get string: k
        rrel$ = rfile$

        rdot = rindex(rfile$, ".")
        if rdot = 0
            rtitle$ = rfile$
        else
            rtitle$ = left$(rfile$, rdot - 1)
        endif

        Add menu command: "Objects", "Praat", rtitle$ + "...", cascadeRoot$, 1, rrel$
        added = added + 1
    endfor
endif
selectObject: "Strings AT_root1"
Remove

Create Strings as file list: "AT_root2", "*.praatscript"
selectObject: "Strings AT_root2"
nr2 = Get number of strings

if nr2 > 0
    if nr1 = 0
        cascadeRoot$ = "AudioTools - Root"
        Add menu command: "Objects", "Praat", cascadeRoot$, "", 0, ""
    endif
    for k2 to nr2
        selectObject: "Strings AT_root2"
        rfile2$ = Get string: k2
        rrel2$ = rfile2$

        rdot2 = rindex(rfile2$, ".")
        if rdot2 = 0
            rtitle2$ = rfile2$
        else
            rtitle2$ = left$(rfile2$, rdot2 - 1)
        endif

        Add menu command: "Objects", "Praat", rtitle2$ + "...", cascadeRoot$, 1, rrel2$
        added = added + 1
    endfor
endif
selectObject: "Strings AT_root2"
Remove

# ---- If nothing was added at all, show a placeholder cascade ----
if added = 0
    Add menu command: "Objects", "Praat", "AudioTools - No scripts found", "", 0, ""
    Add menu command: "Objects", "Praat", "Put *.praat in subfolders", "AudioTools - No scripts found", 1, ""
endif

# ---- Cleanup ----
selectObject: "Strings AT_folders"
Remove
