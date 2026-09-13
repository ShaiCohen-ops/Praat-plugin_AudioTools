# ============================================================
# Praat AudioTools - Universal_Audio_Export.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Universal Audio Export
#
#   A batch-aware audio export and format-conversion utility for
#   one or more selected Sound objects in Praat.
#
#   Supports native export to WAV (16-, 24-, and 32-bit), AIFF,
#   AIFC, FLAC, NeXT/Sun AU, NIST, and highest-quality VBR MP3.
#   Optional sample-rate conversion provides standard rates from
#   16 kHz to 192 kHz using Praat's sinc resampling.
#
#   TPDF dithering can be applied before integer quantization.
#   Auto mode applies dither to 16-bit export, while 24-bit WAV
#   can be dithered explicitly when required.
#
#   Batch export preserves the original Sound objects, processes
#   temporary copies, retains object names, and can automatically
#   generate unique filenames to avoid overwriting existing files.
#
# Usage:
#   Select one or more Sound objects in the Praat Objects window,
#   run the script, choose the target format, sample rate, dither
#   mode, filename suffix, and destination folder.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

form: "Universal Audio Export"
    comment: "Export one or more selected Sound objects"
    optionmenu: "Format", 1
        option: "WAV 24-bit"
        option: "WAV 16-bit"
        option: "WAV 32-bit"
        option: "AIFF 16-bit"
        option: "AIFC 16-bit"
        option: "FLAC 16-bit"
        option: "NeXT/Sun AU 16-bit"
        option: "NIST 16-bit"
        option: "MP3 highest-quality VBR"
    optionmenu: "Sample rate", 1
        option: "Keep original"
        option: "16000 Hz"
        option: "22050 Hz"
        option: "24000 Hz"
        option: "32000 Hz"
        option: "44100 Hz"
        option: "48000 Hz"
        option: "88200 Hz"
        option: "96000 Hz"
        option: "176400 Hz"
        option: "192000 Hz"
    optionmenu: "Dither", 1
        option: "Auto (recommended)"
        option: "None"
        option: "TPDF"
    sentence: "Filename suffix", ""
    folder: "Output folder", "."
    boolean: "Overwrite existing files", 0
endform

# -----------------------------------------------------------------------------
# Validate selection
# -----------------------------------------------------------------------------
sounds# = selected# ("Sound")
numberOfSounds = size (sounds#)
if numberOfSounds = 0
    exitScript: "Select one or more Sound objects before running Universal Audio Export."
endif

if not folderExists (output_folder$)
    exitScript: "The output folder does not exist:", newline$, output_folder$
endif

# -----------------------------------------------------------------------------
# Decode output-format settings
# -----------------------------------------------------------------------------
targetBits = 0
extension$ = ""
formatLabel$ = ""

if format = 1
    targetBits = 24
    extension$ = ".wav"
    formatLabel$ = "WAV 24-bit"
elsif format = 2
    targetBits = 16
    extension$ = ".wav"
    formatLabel$ = "WAV 16-bit"
elsif format = 3
    targetBits = 32
    extension$ = ".wav"
    formatLabel$ = "WAV 32-bit"
elsif format = 4
    targetBits = 16
    extension$ = ".aiff"
    formatLabel$ = "AIFF 16-bit"
elsif format = 5
    targetBits = 16
    extension$ = ".aifc"
    formatLabel$ = "AIFC 16-bit"
elsif format = 6
    targetBits = 16
    extension$ = ".flac"
    formatLabel$ = "FLAC 16-bit"
elsif format = 7
    targetBits = 16
    extension$ = ".au"
    formatLabel$ = "NeXT/Sun AU 16-bit"
elsif format = 8
    targetBits = 16
    extension$ = ".nist"
    formatLabel$ = "NIST 16-bit"
elsif format = 9
    targetBits = 0
    extension$ = ".mp3"
    formatLabel$ = "MP3 highest-quality VBR"
endif

# -----------------------------------------------------------------------------
# Decode sample-rate setting. targetRate = 0 means keep original.
# -----------------------------------------------------------------------------
targetRate = 0
if sample_rate = 2
    targetRate = 16000
elsif sample_rate = 3
    targetRate = 22050
elsif sample_rate = 4
    targetRate = 24000
elsif sample_rate = 5
    targetRate = 32000
elsif sample_rate = 6
    targetRate = 44100
elsif sample_rate = 7
    targetRate = 48000
elsif sample_rate = 8
    targetRate = 88200
elsif sample_rate = 9
    targetRate = 96000
elsif sample_rate = 10
    targetRate = 176400
elsif sample_rate = 11
    targetRate = 192000
endif

# MP3 uses MPEG-supported sample rates only.
if format = 9 and targetRate <> 0
    mp3RateOK = targetRate = 16000 or targetRate = 22050 or targetRate = 24000 or targetRate = 32000 or targetRate = 44100 or targetRate = 48000
    if not mp3RateOK
        exitScript: "MP3 export does not support the selected sample rate (", targetRate, " Hz).", newline$,
        ... "Choose 16, 22.05, 24, 32, 44.1 or 48 kHz, or Keep original if the source already uses one of these rates."
    endif
endif

# -----------------------------------------------------------------------------
# Export loop
# -----------------------------------------------------------------------------
exported = 0
resampled = 0
dithered = 0

for i to numberOfSounds
    selectObject: sounds# [i]
    sourceName$ = selected$ ("Sound")
    sourceRate = Get sampling frequency

    # MP3 validation when keeping the original sample rate.
    if format = 9 and targetRate = 0
        mp3RateOK = abs (sourceRate - 16000) < 0.5 or abs (sourceRate - 22050) < 0.5 or abs (sourceRate - 24000) < 0.5 or abs (sourceRate - 32000) < 0.5 or abs (sourceRate - 44100) < 0.5 or abs (sourceRate - 48000) < 0.5
        if not mp3RateOK
            selectObject: sounds#
            exitScript: "Sound ", sourceName$, " has a sample rate of ", sourceRate, " Hz, which is not a standard MP3 sample rate.", newline$,
            ... "Choose an MP3-compatible sample rate explicitly (16, 22.05, 24, 32, 44.1 or 48 kHz)."
        endif
    endif

    # Work on a private copy so that the selected source object is never changed.
    work = Copy: "__UAE_" + string$ (i)

    # Resample only when requested and actually needed.
    effectiveRate = sourceRate
    if targetRate <> 0 and abs (sourceRate - targetRate) >= 0.5
        oldWork = work
        work = Resample: targetRate, 50
        removeObject: oldWork
        effectiveRate = targetRate
        resampled += 1
    elsif targetRate <> 0
        effectiveRate = targetRate
    endif

    # Determine whether to apply TPDF dither.
    applyDither = 0
    if dither = 1
        # Auto: dither only when writing a 16-bit integer/lossless file.
        if targetBits = 16
            applyDither = 1
        endif
    elsif dither = 3
        # Forced TPDF: meaningful here for 16- and 24-bit integer PCM.
        if targetBits = 16 or targetBits = 24
            applyDither = 1
        endif
    endif

    if applyDither
        if targetBits = 16
            ditherLsb = 1 / 32768
        else
            ditherLsb = 1 / 8388608
        endif
        Formula: ~ self + (randomUniform (-0.5, 0.5) + randomUniform (-0.5, 0.5)) * ditherLsb
        dithered += 1
    endif

    # Create the destination path. If overwrite is disabled, generate a unique name.
    baseName$ = sourceName$ + filename_suffix$
    outputPath$ = output_folder$ + "/" + baseName$ + extension$

    if not overwrite_existing_files
        counter = 1
        while fileReadable (outputPath$)
            outputPath$ = output_folder$ + "/" + baseName$ + "_" + string$ (counter) + extension$
            counter += 1
        endwhile
    endif

    # Native Praat writers.
    selectObject: work
    if format = 1
        Save as 24-bit WAV file: outputPath$
    elsif format = 2
        Save as WAV file: outputPath$
    elsif format = 3
        Save as 32-bit WAV file: outputPath$
    elsif format = 4
        Save as AIFF file: outputPath$
    elsif format = 5
        Save as AIFC file: outputPath$
    elsif format = 6
        Save as FLAC file: outputPath$
    elsif format = 7
        Save as NeXT/Sun file: outputPath$
    elsif format = 8
        Save as NIST file: outputPath$
    elsif format = 9
        Save as highest quality MP3 file: outputPath$
    endif

    removeObject: work
    exported += 1
endfor

# Restore the user's original selection.
selectObject: sounds#

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------
writeInfoLine: "Universal Audio Export"
appendInfoLine: "----------------------"
appendInfoLine: "Exported:     ", exported, " Sound object(s)"
appendInfoLine: "Format:       ", formatLabel$
if targetRate = 0
    appendInfoLine: "Sample rate:  Keep original"
else
    appendInfoLine: "Sample rate:  ", targetRate, " Hz"
endif
if dither = 1
    appendInfoLine: "Dither:       Auto"
elsif dither = 2
    appendInfoLine: "Dither:       None"
else
    appendInfoLine: "Dither:       TPDF"
endif
appendInfoLine: "Resampled:    ", resampled, " file(s)"
appendInfoLine: "Dithered:     ", dithered, " file(s)"
appendInfoLine: "Destination:  ", output_folder$
appendInfoLine: "Done."
