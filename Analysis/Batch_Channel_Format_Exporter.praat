# ============================================================
# Praat AudioTools - Batch_Channel_Format_Exporter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - user control over sample rate and bit depth
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
#     2. Optionally resamples to the chosen sampling rate
#     3. Saves the result to the chosen output folder, at the
#        chosen bit depth, in the chosen format
#     4. Optionally renames files sequentially (01, 02, 03...)
#        with enough leading zeros for the whole batch
#
#   Original objects in the list are never modified or removed.
#
# SAMPLE RATE NOTE:
#   Resampling uses Praat's own "Resample:" command (precision 50),
#   which is a genuine, native operation. If "Keep original
#   sampling rate" is chosen, no resampling occurs.
#
# BIT DEPTH NOTE:
#   Praat's own file-writing commands (Save as WAV/AIFF/FLAC file)
#   are hard-wired to 16-bit; Praat itself has no scripting option
#   to write 24-bit or 32-bit float files. To offer real control,
#   this script first saves natively (16-bit), then, if 24-bit or
#   32-bit float was requested, re-encodes that file in place using
#   ffmpeg (pcm_s24le/be or pcm_f32le/be), if ffmpeg is installed
#   and on the system PATH. If ffmpeg is missing or fails, the file
#   is left at native 16-bit and this is reported per file and in
#   the summary. Bit depth has no effect on MP3 (a lossy format).
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
    optionmenu Sample_rate: 1
        option Keep original sampling rate
        option 16000 Hz
        option 22050 Hz
        option 44100 Hz
        option 48000 Hz
        option 96000 Hz
        option 192000 Hz
        option Custom (set below)
    positive Custom_sample_rate_Hz 44100
    comment Custom rate is used only when "Custom" is selected above.
    optionmenu Bit_depth: 1
        option 16-bit (Praat native; no extra software needed)
        option 24-bit (WAV/AIFF; re-encoded with ffmpeg)
        option 32-bit float (WAV/AIFF; re-encoded with ffmpeg)
    comment Praat itself can only write 16-bit WAV/AIFF/FLAC files.
    comment 24-bit / 32-bit float re-encodes the saved file with
    comment ffmpeg (if installed on the system PATH). No effect on MP3.
    boolean Overwrite_existing_files 0
endform

# ============================================================
# Resolve sample-rate and bit-depth choices
# ============================================================

if sample_rate = 1
    targetRate = 0
elsif sample_rate = 2
    targetRate = 16000
elsif sample_rate = 3
    targetRate = 22050
elsif sample_rate = 4
    targetRate = 44100
elsif sample_rate = 5
    targetRate = 48000
elsif sample_rate = 6
    targetRate = 96000
elsif sample_rate = 7
    targetRate = 192000
else
    targetRate = custom_sample_rate_hz
endif

bitDepth = bit_depth

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
# Bit-depth conversion (post-process, via ffmpeg)
#   .path$ : path of the just-saved (native 16-bit) file
#   .fmt   : 1 = WAV, 2 = AIFF  (never called for MP3)
# Praat cannot itself write anything but 16-bit, so 24-bit and
# 32-bit-float requests are realized by re-encoding the file in
# place with ffmpeg. If ffmpeg is missing or fails, the file is
# simply left at native 16-bit and that is reported.
# Updates the global counters numBitDepthDone / numBitDepthFailed.
# ============================================================

procedure convertBitDepth: .path$, .fmt
    if .fmt = 1
        if bitDepth = 2
            .codec$ = "pcm_s24le"
            .label$ = "24-bit"
        else
            .codec$ = "pcm_f32le"
            .label$ = "32-bit float"
        endif
    else
        if bitDepth = 2
            .codec$ = "pcm_s24be"
            .label$ = "24-bit"
        else
            .codec$ = "pcm_f32be"
            .label$ = "32-bit float"
        endif
    endif

    .tmpPath$ = .path$ + ".bitdepth_tmp"
    nocheck deleteFile: .tmpPath$
    runSystem_nocheck: "ffmpeg -y -loglevel error -i ""'.path$'"" -c:a '.codec$' ""'.tmpPath$'"""

    if fileReadable (.tmpPath$)
        deleteFile: .path$
        if windows
            runSystem_nocheck: "move /Y ""'.tmpPath$'"" ""'.path$'"""
        else
            runSystem_nocheck: "mv ""'.tmpPath$'"" ""'.path$'"""
        endif
        if fileReadable (.path$)
            appendInfoLine: "    -> re-encoded to ", .label$, " (ffmpeg)"
            numBitDepthDone = numBitDepthDone + 1
        else
            appendInfoLine: "    -> WARNING: bit-depth temp file created but could not be moved into place"
            numBitDepthFailed = numBitDepthFailed + 1
        endif
    else
        appendInfoLine: "    -> kept at native 16-bit (ffmpeg not found, or conversion failed)"
        numBitDepthFailed = numBitDepthFailed + 1
    endif
endproc

# ============================================================
# Saving procedure (shared by all channel modes)
#   .obj      : Sound object to save
#   .outBase$ : file name without extension
# Updates the global counters numSaved / numSkipped / numFailed.
# Resamples a temporary copy first if a target sample rate was
# requested and differs from the object's current rate; the
# original object passed in is never modified.
# ============================================================

procedure saveOne: .obj, .outBase$
    .saveObj = .obj
    .resampled = 0
    if targetRate > 0
        selectObject: .obj
        .curRate = Get sampling frequency
        if .curRate <> targetRate
            .saveObj = Resample: targetRate, 50
            .resampled = 1
        endif
    endif

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
        selectObject: .saveObj
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
            if saveFormat <> 3 and bitDepth > 1
                @convertBitDepth: .path$, saveFormat
            endif
        elsif saveFormat = 3
            .fallback$ = outFolder$ + "/" + .outBase$ + ".wav"
            if fileReadable (.fallback$) and not overwrite_existing_files
                appendInfoLine: "  FAILED (MP3 unavailable; WAV fallback exists, not overwritten): ", .fallback$
                numFailed = numFailed + 1
            else
                if fileReadable (.fallback$)
                    deleteFile: .fallback$
                endif
                selectObject: .saveObj
                nocheck Save as WAV file: .fallback$
                if fileReadable (.fallback$)
                    appendInfoLine: "  saved as WAV (MP3 export unavailable in this Praat): ", .fallback$
                    numSaved = numSaved + 1
                    numMp3Fallback = numMp3Fallback + 1
                    if bitDepth > 1
                        @convertBitDepth: .fallback$, 1
                    endif
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

    if .resampled
        removeObject: .saveObj
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
if targetRate = 0
    appendInfoLine: "Sample rate: unchanged (original rate kept)"
else
    appendInfoLine: "Sample rate: ", targetRate, " Hz (resampled as needed)"
endif
if bitDepth = 1
    appendInfoLine: "Bit depth: 16-bit (Praat native)"
elsif saveFormat = 3
    appendInfoLine: "Bit depth: n/a (MP3 is lossy; bit-depth choice ignored)"
elsif bitDepth = 2
    appendInfoLine: "Bit depth: 24-bit (native 16-bit save, then re-encoded via ffmpeg)"
else
    appendInfoLine: "Bit depth: 32-bit float (native 16-bit save, then re-encoded via ffmpeg)"
endif
appendInfoLine: ""

numSaved = 0
numSkipped = 0
numFailed = 0
numMp3Fallback = 0
numBitDepthDone = 0
numBitDepthFailed = 0

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

if bitDepth > 1
    appendInfoLine: ""
    appendInfoLine: "BIT-DEPTH CONVERSION (via ffmpeg)"
    appendInfoLine: "Re-encoded successfully: ", numBitDepthDone
    if numBitDepthFailed > 0
        appendInfoLine: numBitDepthFailed, " file(s) stayed at native 16-bit because ffmpeg was"
        appendInfoLine: "not found (or failed). Install ffmpeg and make sure it is on"
        appendInfoLine: "the system PATH, then re-run with overwrite enabled to upgrade"
        appendInfoLine: "those files."
    endif
endif

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
