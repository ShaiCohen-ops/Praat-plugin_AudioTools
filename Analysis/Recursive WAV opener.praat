# ============================================================
# Praat AudioTools - Recursive WAV opener
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2026) - reviewed
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Recursively collect WAV files from a chosen folder and load either all
#   readable files or a limited random/alphabetical subset into Praat.
#   Optionally creates a load-report Table with source paths and audio metadata.
#
# Usage:
#   Run from the Praat Objects window. No Sound selection is required.
# ============================================================

clearinfo

form Recursive WAV opener v0.2
    comment === File selection ===
    positive Max_files 10
    boolean Open_all 0
    boolean Randomize_selection 1
    boolean Include_subfolders 1
    comment === Output ===
    boolean Create_load_report 1
endform

writeInfoLine: "Recursive WAV loader v0.2"
appendInfoLine: "========================="

directory$ = chooseDirectory$: "Select folder containing WAV files"
if directory$ = ""
    exitScript: "No folder selected."
endif

# Forward slashes are accepted by Praat on all supported platforms.
if right$(directory$, 1) <> "/"
    directory$ = directory$ + "/"
endif

appendInfoLine: "Start folder: ", directory$
appendInfoLine: "Praat version: ", appVersion$ ()
appendInfoLine: "Recursive search: ", if include_subfolders then "yes" else "no" fi
appendInfoLine: ""

# Strings object used as a dynamically growable path list.
all_paths = Create Strings as tokens: ""
Rename: "AudioTools_WAV_paths"

max_recursion_depth = 64
skipped_deep_folders = 0

procedure collectWavFiles: .dir$, .depth
    if .depth <= max_recursion_depth and folderExists (.dir$)
        .files$# = fileNames_caseInsensitive$# (.dir$ + "*.wav")
        for .i from 1 to size (.files$#)
            .file$ = .files$# [.i]
            selectObject: all_paths
            Insert string: 0, .dir$ + .file$
        endfor

        if include_subfolders
            .folders$# = folderNames$# (.dir$ + "*")
            for .j from 1 to size (.folders$#)
                .sub$ = .folders$# [.j]
                if .sub$ <> "." and .sub$ <> ".."
                    @collectWavFiles: .dir$ + .sub$ + "/", .depth + 1
                endif
            endfor
        endif
    elsif .depth > max_recursion_depth
        skipped_deep_folders = skipped_deep_folders + 1
    endif
endproc

# 1. Collect WAV paths.
appendInfoLine: "Searching for WAV files..."
@collectWavFiles: directory$, 0

selectObject: all_paths
total_found = Get number of strings

if total_found = 0
    removeObject: all_paths
    exitScript: "No WAV files were found in this folder with the current recursion setting."
endif

# 2. Put the list in deterministic order before optional randomization.
selectObject: all_paths
Sort

# Preflight readability so the requested sample size counts readable files.
readable_count = 0
unreadable_count = 0
for i from 1 to total_found
    selectObject: all_paths
    path$ = Get string: i
    if fileReadable (path$)
        readable_count = readable_count + 1
    else
        unreadable_count = unreadable_count + 1
    endif
endfor

if readable_count = 0
    removeObject: all_paths
    exitScript: "WAV paths were found, but none of the files are readable."
endif

if open_all
    target_open = readable_count
    load_order$ = "alphabetical"
else
    target_open = min(readable_count, max_files)
    if randomize_selection
        selectObject: all_paths
        Randomize
        load_order$ = "random sample"
    else
        load_order$ = "alphabetical first N"
    endif
endif

appendInfoLine: "Paths found: ", total_found
appendInfoLine: "Readable WAV files: ", readable_count
if unreadable_count > 0
    appendInfoLine: "Unreadable paths skipped: ", unreadable_count
endif
if skipped_deep_folders > 0
    appendInfoLine: "Folders skipped at recursion-depth limit: ", skipped_deep_folders
endif
appendInfoLine: "Load order: ", load_order$
appendInfoLine: "Target files to open: ", target_open
appendInfoLine: ""

# 3. Optional persistent report of the files that are actually loaded.
report = 0
if create_load_report
    report = Create Table with column names: "WAV_Load_Report", target_open, "LoadIndex Path ObjectName Duration_s Channels SampleRate_Hz"
endif

# Keep IDs so every loaded Sound can be reselected at the end.
loaded_ids# = zero# (target_open)
opened_count = 0
candidate_index = 1

while candidate_index <= total_found and opened_count < target_open
    selectObject: all_paths
    current_path$ = Get string: candidate_index

    if fileReadable (current_path$)
        appendInfoLine: "Opening (", opened_count + 1, "/", target_open, "): ", current_path$
        Read from file: current_path$

        opened_count = opened_count + 1
        loaded_id = selected ("Sound")
        loaded_ids# [opened_count] = loaded_id

        selectObject: loaded_id
        object_name$ = selected$ ("Sound")
        duration = Get total duration
        channels = Get number of channels
        sample_rate = Get sampling frequency

        if create_load_report
            selectObject: report
            Set numeric value: opened_count, "LoadIndex", opened_count
            Set string value: opened_count, "Path", current_path$
            Set string value: opened_count, "ObjectName", object_name$
            Set numeric value: opened_count, "Duration_s", duration
            Set numeric value: opened_count, "Channels", channels
            Set numeric value: opened_count, "SampleRate_Hz", sample_rate
        endif
    endif

    candidate_index = candidate_index + 1
endwhile

# Remove only the helper object created by this script.
removeObject: all_paths

# 4. Select all successfully loaded Sounds for immediate follow-up processing.
if opened_count > 0
    selectObject: loaded_ids# [1]
    for i from 2 to opened_count
        plusObject: loaded_ids# [i]
    endfor
endif

appendInfoLine: ""
appendInfoLine: "=== LOAD SUMMARY ==="
appendInfoLine: "Loaded: ", opened_count, " Sound object(s)"
appendInfoLine: "Selection mode: ", load_order$
if create_load_report
    appendInfoLine: "Report: Table WAV_Load_Report"
endif
appendInfoLine: "Loaded Sounds are selected in the Objects window."
appendInfoLine: "Done."
