# ============================================================
# Praat AudioTools - Clean_Ableton_Bridge.praat
# Version: 1.1 (2026)
#
# Deletes WAV files created by Send_to_Ableton.praat, together
# with the Ableton Live analysis sidecars (.asd) that Live writes
# next to them.
#
# Changelog 1.0 -> 1.1
#   - .asd sidecars are now deleted (1.0 globbed "*.wav" only,
#     which never matches "MyClip.wav.asd").
#   - Single directory listing, classification by suffix, so no
#     glob edge case can hide a file.
#   - Post-delete verification: anything left over is listed.
#
# IMPORTANT:
# Ableton Live clips can continue to reference these WAV files.
# Clean only after Collect All and Save, or when the clips/files
# are no longer needed. Close the Live Set first: Live rewrites
# .asd files as soon as it re-scans or replays a clip.
# ============================================================

form Clean Ableton Bridge v1.1
    comment WARNING: Live may still reference these bridge WAV files.
    comment Use this only after Collect All and Save, or when they are no longer needed.
    boolean I_understand_and_want_to_delete_all_bridge_WAV_files 0
    boolean List_folder_contents_before_deleting 0
endform

if i_understand_and_want_to_delete_all_bridge_WAV_files = 0
    exitScript: "Nothing deleted."
endif

if praatVersion >= 7000
    trustRequest = askForTrust()
endif

rootFolder$ = homeDirectory$ + "/Praat_AudioTools"
bridgeFolder$ = rootFolder$ + "/Ableton_Bridge"
createFolder: rootFolder$
createFolder: bridgeFolder$

allFiles$# = fileNames$# (bridgeFolder$ + "/*")
total = size (allFiles$#)

writeInfoLine: "Clean Ableton Bridge v1.1"
appendInfoLine: "  Folder: ", bridgeFolder$
appendInfoLine: "  Files found: ", total
appendInfoLine: ""

if list_folder_contents_before_deleting
    appendInfoLine: "Folder contents before deleting:"
    for i to total
        appendInfoLine: "    ", allFiles$# [i]
    endfor
    appendInfoLine: ""
endif

if total = 0
    appendInfoLine: "Ableton bridge is already clean."
    exitScript ()
endif

wavDeleted = 0
asdDeleted = 0
skipped = 0

for i to total
    name$ = allFiles$# [i]
    ext$ = right$ (name$, 4)
    fullPath$ = bridgeFolder$ + "/" + name$

    if ext$ = ".wav" or ext$ = ".WAV"
        deleteFile: fullPath$
        wavDeleted = wavDeleted + 1
    elsif ext$ = ".asd" or ext$ = ".ASD"
        deleteFile: fullPath$
        asdDeleted = asdDeleted + 1
    else
        skipped = skipped + 1
    endif
endfor

appendInfoLine: "Deleted WAV files: ", wavDeleted
appendInfoLine: "Deleted ASD files: ", asdDeleted
appendInfoLine: "Left untouched (other extensions): ", skipped
appendInfoLine: ""

# --- verification pass -------------------------------------
remaining$# = fileNames$# (bridgeFolder$ + "/*")
remaining = size (remaining$#)

if remaining = 0
    appendInfoLine: "Verified: folder is empty."
else
    appendInfoLine: "Still present after cleaning (", remaining, "):"
    for i to remaining
        appendInfoLine: "    ", remaining$# [i]
    endfor
    appendInfoLine: ""
    appendInfoLine: "If a .wav or .asd appears above, the delete was refused"
    appendInfoLine: "by the OS - the file is locked, read-only, or still open"
    appendInfoLine: "in Live. Close the Live Set and run again."
endif
