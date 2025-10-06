# ============================================================
# Praat AudioTools - Recursive WAV opener.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analytical measurement or feature-extraction script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Recursive WAV opener — corrected (Praat script)

writeInfoLine: "Recursive WAV loader starting..."

directory$ = chooseDirectory$: "Select folder containing .wav files"
if directory$ = ""
    exitScript: "No folder selected."
endif

# make sure path ends with a forward slash (works cross-platform)
if right$(directory$, 1) <> "/"
    directory$ = directory$ + "/"
endif

appendInfoLine: "Start folder: ", directory$
appendInfoLine: "Praat version: ", praatVersion$

procedure openWavFiles: .dir$
    # get wav files (case-insensitive)
    files$# = fileNames_caseInsensitive$# (.dir$ + "*.wav")
    for i from 1 to size (files$#)
        f$ = files$# [i]
        appendInfoLine: "Opening: ", .dir$ + f$
        Read from file: .dir$ + f$
    endfor

    # get subfolders and recurse
    folders$# = folderNames$# (.dir$ + "*")
    for j from 1 to size (folders$#)
        sub$ = folders$# [j]
        if sub$ <> "." and sub$ <> ".."
            appendInfoLine: "Descending into: ", .dir$ + sub$ + "/"
            @openWavFiles: .dir$ + sub$ + "/"
        endif
    endfor
endproc

@openWavFiles: directory$
appendInfoLine: "Done."
