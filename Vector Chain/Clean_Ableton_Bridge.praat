# ============================================================
# Praat AudioTools - Clean_Ableton_Bridge.praat
# Version: 1.0 (2026)
#
# Deletes WAV files created by Send_to_Ableton.praat.
#
# IMPORTANT:
# Ableton Live clips can continue to reference these WAV files.
# Clean only after Collect All and Save, or when the clips/files
# are no longer needed.
# ============================================================

form Clean Ableton Bridge v1.0
    comment WARNING: Live may still reference these bridge WAV files.
    comment Use this only after Collect All and Save, or when they are no longer needed.
    boolean I_understand_and_want_to_delete_all_bridge_WAV_files 0
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

wavFiles$# = fileNames$# (bridgeFolder$ + "/*.wav")
n = size(wavFiles$#)

if n = 0
    writeInfoLine: "Ableton bridge is already clean."
    appendInfoLine: "  Folder: ", bridgeFolder$
else
    for i to n
        deleteFile: bridgeFolder$ + "/" + wavFiles$#[i]
    endfor


    writeInfoLine: "Ableton bridge cleaned."
    appendInfoLine: "  Deleted WAV files: ", n
    appendInfoLine: "  Folder: ", bridgeFolder$
endif
