# ============================================================
# Praat AudioTools - Universal_Audio_IO.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Universal Audio I/O
#
#   A unified audio input, batch conversion, and export utility for Praat.
#   The tool combines recursive audio-folder loading with non-destructive
#   export of selected Sound objects and memory-efficient folder conversion.
#
#   Three operation modes are available:
#     1. Open audio folder into Praat
#        Recursively discovers supported audio files and loads all files or
#        a limited alphabetical/random subset into the Objects window.
#
#     2. Export selected Sound objects
#        Exports one or more selected Sounds while preserving the originals.
#
#     3. Convert audio folder
#        Recursively discovers audio files, reads each file one at a time,
#        optionally resamples and dithers it, exports it, and removes the
#        temporary Sound before continuing. This allows large corpora to be
#        converted without filling the Praat Objects window or system memory.
#
#   Supported folder input extensions:
#     WAV, AIFF/AIF, AIFC, FLAC, MP3, AU/SND, NIST
#
#   Supported export formats:
#     WAV 16-bit, WAV 24-bit, WAV 32-bit, AIFF 16-bit, AIFC 16-bit,
#     FLAC 16-bit, NeXT/Sun AU 16-bit, NIST 16-bit, and Praat-native
#     highest-quality VBR MP3.
#
#   Optional sample-rate conversion uses Praat sinc resampling (precision 50).
#   TPDF dithering is applied after resampling and before integer quantization.
#   Auto mode applies dither to 16-bit export; 24-bit WAV can be dithered
#   explicitly when required. Dither is not applied to MP3 or 32-bit WAV.
#
# Usage:
#   Run from the Praat Objects window. Choose an operation mode.
#   Folder modes prompt for a source directory after the main form.
#   Export selected Sounds requires one or more selected Sound objects.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

clearinfo

form: "Universal Audio I/O v1.0.1"
    comment: "=== Operation ==="
    optionmenu: "Operation", 2
        option: "Open audio folder into Praat"
        option: "Export selected Sound objects"
        option: "Convert audio folder"

    comment: "=== Folder input (used by Open / Convert) ==="
    optionmenu: "Input format", 1
        option: "All supported audio"
        option: "WAV"
        option: "AIFF / AIFC"
        option: "FLAC"
        option: "MP3"
        option: "AU / SND"
        option: "NIST"
    natural: "Max files", "10"
    boolean: "Use all matching files", 0
    boolean: "Randomize selection", 1
    boolean: "Include subfolders", 1
    boolean: "Create report", 1

    comment: "=== Output / conversion (used by Export / Convert) ==="
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
# Decode output settings
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

if operation <> 1 and format = 9 and targetRate <> 0
    mp3RateOK = targetRate = 16000 or targetRate = 22050 or targetRate = 24000 or targetRate = 32000 or targetRate = 44100 or targetRate = 48000
    if not mp3RateOK
        exitScript: "MP3 export does not support the selected sample rate (", targetRate, " Hz).", newline$,
        ... "Choose 16, 22.05, 24, 32, 44.1 or 48 kHz, or Keep original."
    endif
endif

# -----------------------------------------------------------------------------
# Shared counters and last-result values
# -----------------------------------------------------------------------------
exported = 0
resampled = 0
dithered = 0
lastOutputPath$ = ""
lastEffectiveRate = 0
lastDither$ = "None"

# -----------------------------------------------------------------------------
# Procedure: export currently selected Sound
# .preserveSource = 1 for selected-object export, 0 for folder conversion.
# -----------------------------------------------------------------------------
procedure exportCurrentSound: .sourceName$, .preserveSource, .index
    .sourceRate = Get sampling frequency

    if format = 9 and targetRate = 0
        .mp3RateOK = abs (.sourceRate - 16000) < 0.5 or abs (.sourceRate - 22050) < 0.5 or abs (.sourceRate - 24000) < 0.5 or abs (.sourceRate - 32000) < 0.5 or abs (.sourceRate - 44100) < 0.5 or abs (.sourceRate - 48000) < 0.5
        if not .mp3RateOK
            exitScript: "Sound ", .sourceName$, " has a sample rate of ", .sourceRate, " Hz, which is not a standard MP3 sample rate.", newline$,
            ... "Choose an MP3-compatible sample rate explicitly."
        endif
    endif

    if .preserveSource
        .work = Copy: "__UAIO_" + string$ (.index)
    else
        .work = selected ("Sound")
    endif

    .effectiveRate = .sourceRate
    if targetRate <> 0 and abs (.sourceRate - targetRate) >= 0.5
        .oldWork = .work
        .work = Resample: targetRate, 50
        removeObject: .oldWork
        .effectiveRate = targetRate
        resampled += 1
    elsif targetRate <> 0
        .effectiveRate = targetRate
    endif

    .applyDither = 0
    if dither = 1
        if targetBits = 16
            .applyDither = 1
        endif
    elsif dither = 3
        if targetBits = 16 or targetBits = 24
            .applyDither = 1
        endif
    endif

    .ditherLabel$ = "None"
    if .applyDither
        if targetBits = 16
            .ditherLsb = 1 / 32768
        else
            .ditherLsb = 1 / 8388608
        endif
        Formula: ~ self + (randomUniform (-0.5, 0.5) + randomUniform (-0.5, 0.5)) * .ditherLsb
        dithered += 1
        .ditherLabel$ = "TPDF"
    endif

    .baseName$ = .sourceName$ + filename_suffix$
    .outputPath$ = output_folder$ + "/" + .baseName$ + extension$

    if not overwrite_existing_files
        .counter = 1
        while fileReadable (.outputPath$)
            .outputPath$ = output_folder$ + "/" + .baseName$ + "_" + string$ (.counter) + extension$
            .counter += 1
        endwhile
    endif

    selectObject: .work
    if format = 1
        Save as 24-bit WAV file: .outputPath$
    elsif format = 2
        Save as WAV file: .outputPath$
    elsif format = 3
        Save as 32-bit WAV file: .outputPath$
    elsif format = 4
        Save as AIFF file: .outputPath$
    elsif format = 5
        Save as AIFC file: .outputPath$
    elsif format = 6
        Save as FLAC file: .outputPath$
    elsif format = 7
        Save as NeXT/Sun file: .outputPath$
    elsif format = 8
        Save as NIST file: .outputPath$
    elsif format = 9
        Save as highest quality MP3 file: .outputPath$
    endif

    removeObject: .work
    exported += 1

    lastOutputPath$ = .outputPath$
    lastEffectiveRate = .effectiveRate
    lastDither$ = .ditherLabel$
endproc

# -----------------------------------------------------------------------------
# Procedure: add files matching a pattern to the shared path list
# -----------------------------------------------------------------------------
procedure addPattern: .dir$, .pattern$
    .files$# = fileNames_caseInsensitive$# (.dir$ + .pattern$)
    for .i from 1 to size (.files$#)
        selectObject: all_paths
        Insert string: 0, .dir$ + .files$# [.i]
    endfor
endproc

# -----------------------------------------------------------------------------
# Procedure: recursively collect supported audio files
# -----------------------------------------------------------------------------
max_recursion_depth = 64
skipped_deep_folders = 0

procedure collectAudioFiles: .dir$, .depth
    if .depth <= max_recursion_depth and folderExists (.dir$)
        if input_format = 1 or input_format = 2
            @addPattern: .dir$, "*.wav"
        endif
        if input_format = 1 or input_format = 3
            @addPattern: .dir$, "*.aif"
            @addPattern: .dir$, "*.aiff"
            @addPattern: .dir$, "*.aifc"
        endif
        if input_format = 1 or input_format = 4
            @addPattern: .dir$, "*.flac"
        endif
        if input_format = 1 or input_format = 5
            @addPattern: .dir$, "*.mp3"
        endif
        if input_format = 1 or input_format = 6
            @addPattern: .dir$, "*.au"
            @addPattern: .dir$, "*.snd"
        endif
        if input_format = 1 or input_format = 7
            @addPattern: .dir$, "*.nist"
        endif

        if include_subfolders
            .folders$# = folderNames$# (.dir$ + "*")
            for .j from 1 to size (.folders$#)
                .sub$ = .folders$# [.j]
                if .sub$ <> "." and .sub$ <> ".."
                    @collectAudioFiles: .dir$ + .sub$ + "/", .depth + 1
                endif
            endfor
        endif
    elsif .depth > max_recursion_depth
        skipped_deep_folders += 1
    endif
endproc

# -----------------------------------------------------------------------------
# Operation 2: Export selected Sound objects
# -----------------------------------------------------------------------------
if operation = 2
    sounds# = selected# ("Sound")
    numberOfSounds = size (sounds#)

    if numberOfSounds = 0
        exitScript: "Select one or more Sound objects before running Export selected Sound objects."
    endif
    if not folderExists (output_folder$)
        exitScript: "The output folder does not exist:", newline$, output_folder$
    endif

    report = 0
    if create_report
        report = Create Table with column names: "Audio_IO_Export_Report", numberOfSounds, "Index ObjectName SourceRate_Hz OutputPath TargetFormat TargetRate_Hz Dither"
    endif

    for i from 1 to numberOfSounds
        selectObject: sounds# [i]
        sourceName$ = selected$ ("Sound")
        sourceRate = Get sampling frequency

        @exportCurrentSound: sourceName$, 1, i

        if create_report
            selectObject: report
            Set numeric value: i, "Index", i
            Set string value: i, "ObjectName", sourceName$
            Set numeric value: i, "SourceRate_Hz", sourceRate
            Set string value: i, "OutputPath", lastOutputPath$
            Set string value: i, "TargetFormat", formatLabel$
            Set numeric value: i, "TargetRate_Hz", lastEffectiveRate
            Set string value: i, "Dither", lastDither$
        endif
    endfor

    selectObject: sounds#

    writeInfoLine: "Universal Audio I/O v1.0.1"
    appendInfoLine: "========================"
    appendInfoLine: "Operation:     Export selected Sound objects"
    appendInfoLine: "Exported:      ", exported, " Sound object(s)"
    appendInfoLine: "Format:        ", formatLabel$
    if targetRate = 0
        appendInfoLine: "Sample rate:   Keep original"
    else
        appendInfoLine: "Sample rate:   ", targetRate, " Hz"
    endif
    if dither = 1
        appendInfoLine: "Dither:        Auto"
    elsif dither = 2
        appendInfoLine: "Dither:        None"
    else
        appendInfoLine: "Dither:        TPDF"
    endif
    appendInfoLine: "Resampled:     ", resampled, " file(s)"
    appendInfoLine: "Dithered:      ", dithered, " file(s)"
    appendInfoLine: "Destination:   ", output_folder$
    if create_report
        appendInfoLine: "Report:        Table Audio_IO_Export_Report"
    endif
    appendInfoLine: "Done."
    goto FINISH
endif

# -----------------------------------------------------------------------------
# Operations 1 and 3: choose and scan a source folder
# -----------------------------------------------------------------------------
source_folder$ = chooseFolder$: "Select source audio folder"
if source_folder$ = ""
    exitScript: "No source folder selected."
endif
if right$ (source_folder$, 1) <> "/"
    source_folder$ = source_folder$ + "/"
endif

if operation = 3 and not folderExists (output_folder$)
    exitScript: "The output folder does not exist:", newline$, output_folder$
endif

all_paths = Create Strings as tokens: ""
Rename: "AudioTools_Audio_paths"

@collectAudioFiles: source_folder$, 0

selectObject: all_paths
total_found = Get number of strings
if total_found = 0
    removeObject: all_paths
    exitScript: "No supported audio files were found in this folder with the current input-format and recursion settings."
endif

selectObject: all_paths
Sort

readable_count = 0
unreadable_count = 0
for i from 1 to total_found
    selectObject: all_paths
    path$ = Get string: i
    if fileReadable (path$)
        readable_count += 1
    else
        unreadable_count += 1
    endif
endfor

if readable_count = 0
    removeObject: all_paths
    exitScript: "Audio paths were found, but none of the files are readable."
endif

if use_all_matching_files
    target_count = readable_count
    selectionMode$ = "alphabetical - all readable files"
else
    target_count = min (readable_count, max_files)
    if randomize_selection
        selectObject: all_paths
        Randomize
        selectionMode$ = "random sample"
    else
        selectionMode$ = "alphabetical first N"
    endif
endif

writeInfoLine: "Universal Audio I/O v1.0.1"
appendInfoLine: "========================"
if operation = 1
    appendInfoLine: "Operation:       Open audio folder into Praat"
else
    appendInfoLine: "Operation:       Convert audio folder"
endif
appendInfoLine: "Source folder:   ", source_folder$
appendInfoLine: "Paths found:     ", total_found
appendInfoLine: "Readable files:  ", readable_count
if unreadable_count > 0
    appendInfoLine: "Unreadable:      ", unreadable_count
endif
if skipped_deep_folders > 0
    appendInfoLine: "Depth-limited:   ", skipped_deep_folders, " folder(s)"
endif
appendInfoLine: "Selection:       ", selectionMode$
appendInfoLine: "Target files:    ", target_count
appendInfoLine: ""

# -----------------------------------------------------------------------------
# Operation 1: Open folder into Praat
# -----------------------------------------------------------------------------
if operation = 1
    report = 0
    if create_report
        report = Create Table with column names: "Audio_IO_Load_Report", target_count, "LoadIndex Path ObjectName Duration_s Channels SampleRate_Hz"
    endif

    loaded_ids# = zero# (target_count)
    opened_count = 0
    candidate_index = 1

    while candidate_index <= total_found and opened_count < target_count
        selectObject: all_paths
        current_path$ = Get string: candidate_index

        if fileReadable (current_path$)
            appendInfoLine: "Opening (", opened_count + 1, "/", target_count, "): ", current_path$
            Read from file: current_path$

            opened_count += 1
            loaded_id = selected ("Sound")
            loaded_ids# [opened_count] = loaded_id

            selectObject: loaded_id
            object_name$ = selected$ ("Sound")
            duration = Get total duration
            channels = Get number of channels
            source_rate = Get sampling frequency

            if create_report
                selectObject: report
                Set numeric value: opened_count, "LoadIndex", opened_count
                Set string value: opened_count, "Path", current_path$
                Set string value: opened_count, "ObjectName", object_name$
                Set numeric value: opened_count, "Duration_s", duration
                Set numeric value: opened_count, "Channels", channels
                Set numeric value: opened_count, "SampleRate_Hz", source_rate
            endif
        endif

        candidate_index += 1
    endwhile

    removeObject: all_paths

    if opened_count > 0
        selectObject: loaded_ids# [1]
        for i from 2 to opened_count
            plusObject: loaded_ids# [i]
        endfor
    endif

    appendInfoLine: ""
    appendInfoLine: "=== LOAD SUMMARY ==="
    appendInfoLine: "Loaded:          ", opened_count, " Sound object(s)"
    appendInfoLine: "Selection mode:  ", selectionMode$
    if create_report
        appendInfoLine: "Report:          Table Audio_IO_Load_Report"
    endif
    appendInfoLine: "Loaded Sounds are selected in the Objects window."
    appendInfoLine: "Done."
    goto FINISH
endif

# -----------------------------------------------------------------------------
# Operation 3: Convert folder, one file at a time
# -----------------------------------------------------------------------------
report = 0
if create_report
    report = Create Table with column names: "Audio_IO_Conversion_Report", target_count, "Index SourcePath ObjectName Duration_s Channels SourceRate_Hz OutputPath TargetFormat TargetRate_Hz Dither"
endif

converted_count = 0
candidate_index = 1

while candidate_index <= total_found and converted_count < target_count
    selectObject: all_paths
    current_path$ = Get string: candidate_index

    if fileReadable (current_path$)
        appendInfoLine: "Converting (", converted_count + 1, "/", target_count, "): ", current_path$
        Read from file: current_path$

        source_id = selected ("Sound")
        sourceName$ = selected$ ("Sound")
        duration = Get total duration
        channels = Get number of channels
        sourceRate = Get sampling frequency

        @exportCurrentSound: sourceName$, 0, converted_count + 1
        converted_count += 1

        if create_report
            selectObject: report
            Set numeric value: converted_count, "Index", converted_count
            Set string value: converted_count, "SourcePath", current_path$
            Set string value: converted_count, "ObjectName", sourceName$
            Set numeric value: converted_count, "Duration_s", duration
            Set numeric value: converted_count, "Channels", channels
            Set numeric value: converted_count, "SourceRate_Hz", sourceRate
            Set string value: converted_count, "OutputPath", lastOutputPath$
            Set string value: converted_count, "TargetFormat", formatLabel$
            Set numeric value: converted_count, "TargetRate_Hz", lastEffectiveRate
            Set string value: converted_count, "Dither", lastDither$
        endif
    endif

    candidate_index += 1
endwhile

removeObject: all_paths

appendInfoLine: ""
appendInfoLine: "=== CONVERSION SUMMARY ==="
appendInfoLine: "Converted:       ", converted_count, " file(s)"
appendInfoLine: "Format:          ", formatLabel$
if targetRate = 0
    appendInfoLine: "Sample rate:     Keep original"
else
    appendInfoLine: "Sample rate:     ", targetRate, " Hz"
endif
if dither = 1
    appendInfoLine: "Dither:          Auto"
elsif dither = 2
    appendInfoLine: "Dither:          None"
else
    appendInfoLine: "Dither:          TPDF"
endif
appendInfoLine: "Resampled:       ", resampled, " file(s)"
appendInfoLine: "Dithered:        ", dithered, " file(s)"
appendInfoLine: "Destination:     ", output_folder$
if create_report
    appendInfoLine: "Report:          Table Audio_IO_Conversion_Report"
endif
appendInfoLine: "No converted source Sounds remain in the Objects window."
appendInfoLine: "Done."


label FINISH
# End of Universal Audio I/O
