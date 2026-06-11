# ============================================================
# Praat AudioTools - Batch_Channel_Format_Exporter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - folder-selection dialog option; native MP3 export
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Batch-exports the Sound objects currently SELECTED in the
#   Praat Objects window. No files are read from disk: load your
#   sounds into Praat, select them in the object list (click +
#   shift-click or ctrl-click), then run this script.
#
#   For each selected Sound the script:
#     1. Applies the chosen channel mode
#        (mono mixdown / stereo / keep / split channels)
#     2. Saves the result to the chosen output folder
#     3. Optionally renames files sequentially (01, 02, 03...)
#        with enough leading zeros for the whole batch
#
#   Original objects in the list are never modified or removed.
#
# MP3 NOTE:
#   Since the Praat 6.4 series (late 2023), Praat CAN save MP3
#   directly via "Save as highest quality MP3 file:". This
#   script uses that command. If you run it on an older Praat
#   that lacks the command, the affected file is saved as WAV
#   instead (lossless fallback), the report says so per file,
#   and an ffmpeg conversion hint is printed at the end.
#
# ERROR HANDLING:
#   - Missing / unwritable output folder -> clear error, abort
#   - Existing files are NEVER overwritten unless the
#     "Overwrite existing files" box is ticked
#   - A failure while saving one file is reported and the
#     script continues with the next file
#   - A summary (saved / skipped / failed) is printed at the end
# ============================================================

form Batch Channel and Format Exporter
    comment Exports all Sound objects currently selected in the object list.
    boolean Choose_output_folder_in_dialog 1
    sentence Output_folder
    comment If the dialog box is ticked (or the field left empty),
    comment a folder-selection dialog opens after you press OK.
    boolean Rename_sequentially 0
    comment If renaming is on, files are named 01, 02, 03... (zero-padded).
    optionmenu Channel_mode: 3
        option Mono (mix down to one channel)
        option Stereo (two channels when possible)
        option Keep multichannel (preserve channel count)
        option Split multichannel into separate mono files
    optionmenu Output_format: 1
        option WAV
        option AIFF
        option MP3 (highest quality; needs Praat 6.4+)
    boolean Overwrite_existing_files 0
endform

# ============================================================
# Collect the current selection BEFORE anything changes it
# ============================================================

numSounds = numberOfSelected ("Sound")
if numSounds = 0
    exitScript: "No Sound objects are selected. Select one or more Sounds in the Praat object list, then run the script again."
endif

for i to numSounds
    soundID_'i' = selected ("Sound", i)
    soundName_'i'$ = selected$ ("Sound", i)
endfor

# ============================================================
# Resolve and verify the output folder
# ============================================================

outFolder$ = output_folder$

if choose_output_folder_in_dialog or outFolder$ = ""
    outFolder$ = chooseDirectory$ ("Choose the output folder for the exported files")
    if outFolder$ = ""
        exitScript: "No output folder was chosen. Nothing was exported."
    endif
endif

# Strip a trailing slash or backslash so we can append "/" safely
if right$ (outFolder$, 1) = "/" or right$ (outFolder$, 1) = "\"
    outFolder$ = left$ (outFolder$, length (outFolder$) - 1)
endif

# Praat has no direct "folder exists" query, so we test by
# writing (and deleting) a tiny probe file. This catches both
# non-existent folders and folders without write permission.
probeFile$ = outFolder$ + "/__praat_write_probe__.tmp"
nocheck writeFile: probeFile$, "probe"
if not fileReadable (probeFile$)
    exitScript: "The output folder does not exist or is not writable:", newline$, outFolder$, newline$, "Create the folder (or check its permissions) and run the script again."
endif
deleteFile: probeFile$

# ============================================================
# Output format and file extension
# ============================================================

saveFormat = output_format
if saveFormat = 1
    ext$ = ".wav"
elsif saveFormat = 2
    ext$ = ".aiff"
else
    ext$ = ".mp3"
endif

# Zero-padding width: enough digits for the whole batch, minimum 2
padDigits = length (string$ (numSounds))
if padDigits < 2
    padDigits = 2
endif

# ============================================================
# Saving procedure (shared by all channel modes)
#   .obj      : Sound object to save
#   .outBase$ : file name without extension
# Updates the global counters numSaved / numSkipped / numFailed.
# ============================================================

procedure saveOne: .obj, .outBase$
    .path$ = outFolder$ + "/" + .outBase$ + ext$
    if fileReadable (.path$) and not overwrite_existing_files
        appendInfoLine: "  SKIPPED (file exists): ", .path$
        numSkipped = numSkipped + 1
    else
        # When overwriting, delete first so that a failed save
        # cannot leave the old file masquerading as a success.
        if fileReadable (.path$)
            deleteFile: .path$
        endif
        selectObject: .obj
        if saveFormat = 1
            nocheck Save as WAV file: .path$
        elsif saveFormat = 2
            nocheck Save as AIFF file: .path$
        else
            # Native MP3 export (Praat 6.4+). On older Praat this
            # command does not exist; nocheck swallows the error
            # and we fall back to a lossless WAV for this file.
            nocheck Save as highest quality MP3 file: .path$
        endif
        if fileReadable (.path$)
            appendInfoLine: "  saved: ", .path$
            numSaved = numSaved + 1
        elsif saveFormat = 3
            .fallback$ = outFolder$ + "/" + .outBase$ + ".wav"
            if fileReadable (.fallback$) and not overwrite_existing_files
                appendInfoLine: "  FAILED (MP3 unavailable; WAV fallback exists, not overwritten): ", .fallback$
                numFailed = numFailed + 1
            else
                if fileReadable (.fallback$)
                    deleteFile: .fallback$
                endif
                selectObject: .obj
                nocheck Save as WAV file: .fallback$
                if fileReadable (.fallback$)
                    appendInfoLine: "  saved as WAV (MP3 export unavailable in this Praat): ", .fallback$
                    numSaved = numSaved + 1
                    numMp3Fallback = numMp3Fallback + 1
                else
                    appendInfoLine: "  FAILED to save: ", .path$
                    numFailed = numFailed + 1
                endif
            endif
        else
            appendInfoLine: "  FAILED to save: ", .path$
            numFailed = numFailed + 1
        endif
    endif
endproc

# ============================================================
# Main loop
# ============================================================

writeInfoLine: "Batch Channel and Format Exporter"
appendInfoLine: "Sounds selected: ", numSounds
appendInfoLine: "Output folder:   ", outFolder$
if saveFormat = 1
    appendInfoLine: "Format: WAV"
elsif saveFormat = 2
    appendInfoLine: "Format: AIFF"
else
    appendInfoLine: "Format: MP3 (highest quality)"
endif
appendInfoLine: ""

numSaved = 0
numSkipped = 0
numFailed = 0
numMp3Fallback = 0

for i to numSounds
    sndID = soundID_'i'
    baseName$ = soundName_'i'$

    # Base output name: sequential number or original object name.
    # Note: without renaming, two objects with the same name will
    # collide; the second is then skipped (or overwrites, if enabled).
    if rename_sequentially
        baseOut$ = right$ ("0000000000" + string$ (i), padDigits)
    else
        baseOut$ = baseName$
    endif

    selectObject: sndID
    nCh = Get number of channels
    appendInfoLine: "[", i, "/", numSounds, "] ", baseName$, " (", nCh, " ch)"

    if channel_mode = 1
        # --- MONO: mix down to one channel ---
        if nCh > 1
            selectObject: sndID
            work = Convert to mono
            @saveOne: work, baseOut$
            removeObject: work
        else
            @saveOne: sndID, baseOut$
        endif

    elsif channel_mode = 2
        # --- STEREO: two channels when possible ---
        if nCh = 2
            @saveOne: sndID, baseOut$
        elsif nCh = 1
            selectObject: sndID
            work = Convert to stereo
            @saveOne: work, baseOut$
            removeObject: work
        else
            # More than 2 channels: keep channels 1 and 2,
            # drop the rest (documented limitation).
            selectObject: sndID
            chL = Extract one channel: 1
            selectObject: sndID
            chR = Extract one channel: 2
            selectObject: chL, chR
            work = Combine to stereo
            @saveOne: work, baseOut$
            removeObject: chL, chR, work
            appendInfoLine: "  note: ", nCh, " channels reduced to stereo (channels 3+ dropped)"
        endif

    elsif channel_mode = 3
        # --- KEEP MULTICHANNEL: save as-is ---
        @saveOne: sndID, baseOut$

    else
        # --- SPLIT: one mono file per channel ---
        for ch to nCh
            selectObject: sndID
            chanSound = Extract one channel: ch
            @saveOne: chanSound, baseOut$ + "_ch" + string$ (ch)
            removeObject: chanSound
        endfor
    endif
endfor

# ============================================================
# Summary
# ============================================================

appendInfoLine: ""
appendInfoLine: "DONE"
appendInfoLine: "Files saved:   ", numSaved
appendInfoLine: "Files skipped: ", numSkipped, " (already existed; enable overwrite to replace)"
appendInfoLine: "Files failed:  ", numFailed

if numMp3Fallback > 0
    appendInfoLine: ""
    appendInfoLine: "MP3 FALLBACK NOTE"
    appendInfoLine: string$ (numMp3Fallback), " file(s) were saved as WAV because this Praat version"
    appendInfoLine: "lacks MP3 export (added in the 6.4 series). Update Praat, or"
    appendInfoLine: "convert the WAVs to MP3 with ffmpeg in a terminal:"
    appendInfoLine: ""
    appendInfoLine: "  cd """, outFolder$, """"
    appendInfoLine: "  for f in *.wav; do ffmpeg -i ""$f"" -b:a 320k ""${f%.wav}.mp3""; done"
    appendInfoLine: ""
    appendInfoLine: "(Windows PowerShell equivalent:)"
    appendInfoLine: "  Get-ChildItem *.wav | ForEach-Object { ffmpeg -i $_.Name -b:a 320k ($_.BaseName + '.mp3') }"
endif

# Restore the original selection so the user can keep working
selectObject: soundID_1
for i from 2 to numSounds
    plusObject: soundID_'i'
endfor
