# ============================================================
# Praat AudioTools - Media_ffmpeg_tools.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Praat front-end for twelve FFmpeg video/audio operations.
#   The user points the script at one folder that contains:
#     - ffmpeg (or ffmpeg.exe on Windows)
#     - the input media files
#   Inputs can be named explicitly or resolved automatically (AUTO).
#   Output files are
#   written to the same folder with descriptive suffixes.
#   The full FFmpeg command is printed to the Info window.
#
#   Supported workflows:
#     A) video -> extract audio -> Praat processing ->
#        replace audio in video  (ops 2, 1)
#     B) Praat audio -> waveform/spectrogram video ->
#        presentation  (ops 4, 5, 7, 12)
#     C) video segment -> Praat-selected audio replacement ->
#        new video segment  (op 6)
#
# Operations:
#    1.  Replace audio in video
#    2.  Extract audio from video -> open in Praat
#    3.  Cut video without re-encoding
#    4.  Waveform video from audio
#    5.  Spectrogram video from audio
#    6.  Export Praat selection as video segment
#    7.  Still image + audio -> video
#    8.  Add soft subtitles (mov_text, MP4)
#    9.  Burn subtitles into video (hardcode)
#   10.  Convert video to HAP (Max/MSP / Jitter)
#   11.  Change video frame rate
#   12.  Analysis contact video
#
# Usage:
#   Place ffmpeg(.exe) and your input file(s) in one folder.
#   Type that folder path in the form. With multiple video/audio files,
#   set Video_file / Audio_file explicitly instead of AUTO.
#   Output is written to the same folder.
#   Use forward slashes in the path (works on all platforms).
#   For operation 6, select exactly one Sound object first.
#
#   FFmpeg downloads:
#     macOS:    https://evermeet.cx/ffmpeg/
#     Windows:  https://www.gyan.dev/ffmpeg/builds/
#     Linux:    apt install ffmpeg  /  brew install ffmpeg
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.4:
#   - Praat 7: requests Full Trust before external FFmpeg/file operations.
#   - Windows: fixes cmd.exe /c parsing for FFmpeg paths while preserving
#     quoted media filenames that contain spaces.
#   - Operation 2 again opens the extracted WAV automatically in Praat.
#   - Keeps the v1.3 timing, container, subtitle, H.264 and input-selection fixes.
#
# Changelog v1.3:
#   - FIX: stale/zero-byte outputs cannot be mistaken for success; an
#     existing target is removed first and a shell marker is written only
#     when FFmpeg exits with status 0.
#   - FIX: ops 3/6 parse and validate the time fields in Praat, then pass
#     a numeric -t duration to FFmpeg. Malformed/negative ranges no longer
#     reach the shell or create -ss/-to ambiguity.
#   - FIX: op 6 uses an accurate re-encoded video cut before Praat-audio
#     replacement. Stream-copy keyframe preroll can no longer misalign an
#     exact Praat Sound range with the replacement video.
#   - FIX: op 6 interprets its Sound range relative to that Sound's own
#     start time; clipping is reported and video duration follows the
#     achieved Praat range when replacement audio is enabled.
#   - FIX: op 3 stream-copy output keeps the input container extension.
#   - FIX: soft-subtitle audio mapping is optional; MP4 operations that
#     already re-encode video use AAC audio for broader compatibility.
#   - FEATURE: optional Video_file / Audio_file fields make repeated runs
#     deterministic; AUTO preserves v1.2 folder scanning.
#   - FIX: the extension scanner now advances through the full extension
#     list; v1.2 used two-argument mid$ as if it meant substring-to-end,
#     so formats later in a list (e.g. PNG after JPG) could be missed.
#   - FEATURE: op 12 now stacks a waveform and scrolling logarithmic
#     spectrum instead of duplicating the waveform-only operation.
#   - QUALITY: H.264 outputs use yuv420p and even dimensions; generated
#     visualizers quantize requested dimensions, while arbitrary source
#     video/image paths trim at most one edge pixel when needed.
#   - AUTOMATION: FFmpeg runs with -nostdin -hide_banner -loglevel error.
# Changelog v1.2:
#   - Praat 7 audit: preserves the Sound selected for operation 6
#     before temporary Strings file-list objects change the selection.
#   - Quotes the ffmpeg executable path, so folders containing spaces
#     work correctly on Windows, macOS and Linux.
#   - Operation 6 now honours Use_duration_not_end for both the FFmpeg
#     cut and the Praat Sound extraction.
#   - Removed the ineffective folder-probe logic; missing folders now
#     produce a clearer ffmpeg/folder diagnostic.
#   - Praat 7 note: executing FFmpeg and writing files requires the
#     script to be allowed Full Trust.
# Changelog v1.1:
#   - Fix: op 9 (burn subtitles) now auto-escapes the Windows
#     drive-letter colon for FFmpeg's subtitles= filter
#     (C:/path -> C\:/path). v1.0 documented this requirement
#     in a comment but never applied it; Windows users would
#     hit a cryptic FFmpeg parse error. The escape happens in
#     the command builder so it's also visible in dry-run output
#     for users pasting commands into a shell.
#   - Added folder-exists pre-check. Previously a non-existent
#     folder path produced "no video file found" which is
#     misleading — now produces "Folder not found: ..." with
#     the path that was tried.
#   - Added ffmpeg-not-found check with platform-appropriate
#     download / install hints. Previously the file-list scan
#     ran and then operations failed at runSystem with no clear
#     message about ffmpeg.
#   - Added Dry_run toggle. Prints the command and exits
#     without executing FFmpeg. Useful for previewing or
#     copy-paste-to-shell workflows.
#   - Refactored: 4 near-duplicate file-extension iteration
#     loops (videos, audio, images, subtitles, ~80 lines)
#     collapsed into one findFirstFile procedure that takes
#     a space-separated extension list. Pure cosmetic; no
#     behavior change.
#   - Moved procedures to the top of the file (after the
#     form). Praat allows forward references but convention
#     and readability prefer top-of-file definitions.
#   - hmsToSec parser now validates against undefined and
#     reports a clear "Time format must be HH:MM:SS.mmm or
#     SS.mmm" error instead of letting NaN seconds propagate
#     into FFmpeg arguments.
# Changelog v1.0:
#   - Initial release: 12 operations, auto-detection,
#     workflow A/B/C support.
# ============================================================

form FFmpeg Media Tools v1.4
    comment === Folder containing ffmpeg(.exe) and your input file(s) ===
    comment     Windows example:   C:/ffmpeg
    comment     Mac / Linux:       /Users/shai/ffmpeg
    sentence Folder C:/ffmpeg
    comment === Optional explicit inputs (AUTO = scan folder) ===
    sentence Video_file AUTO
    sentence Audio_file AUTO
    comment === Select operation ===
    optionmenu Operation: 1
        option  1  Replace audio in video
        option  2  Extract audio from video -> open in Praat
        option  3  Cut video without re-encoding
        option  4  Waveform video from audio
        option  5  Spectrogram video from audio
        option  6  Export Praat selection as video segment
        option  7  Still image + audio -> video
        option  8  Add soft subtitles (mov_text, MP4)
        option  9  Burn subtitles into video (hardcode)
        option 10  Convert video to HAP (Max/MSP / Jitter)
        option 11  Change video frame rate
        option 12  Analysis contact video
    comment === Op 1: Replace Audio ===
    boolean Shortest_stream 0
    comment === Op 2: Extract Audio ===
    positive Sample_rate 48000
    optionmenu Channels: 2
        option Mono
        option Stereo
    comment === Op 3 and Op 6: time range  (HH:MM:SS.mmm) ===
    sentence Start_time 00:00:00.000
    sentence End_time_or_duration 00:00:10.000
    boolean Use_duration_not_end 0
    comment === Op 4, 5, 12: Visualization dimensions ===
    positive Width 1920
    positive Height 1080
    positive Frame_rate 30
    comment === Op 6: Also replace cut video audio with Praat WAV? ===
    boolean Replace_audio_in_cut 1
    comment === Op 10: HAP mode ===
    optionmenu Hap_mode: 1
        option hap
        option hap_alpha
        option hap_q
    comment === Op 11: Target frame rate ===
    positive Target_fps 25
    comment === General ===
    boolean Dry_run 0
endform

# Praat 7 requires explicit trust for scripts that write files or run commands.
if praatVersion >= 7000
    trustRequest = askForTrust()
endif

# Preserve the Sound selected for operation 6 BEFORE any file-list helper
# creates temporary Strings objects and changes the Praat selection.
op6_sound = 0
if operation = 6
    if numberOfSelected("Sound") <> 1
        exitScript: "Operation 6 requires exactly one Sound object selected before running the script."
    endif
    op6_sound = selected("Sound")
endif

# ============================================================
# PROCEDURES  (defined before first use)
# ============================================================

procedure requireFile: .path$, .label$
    # Exit clearly for both auto-detection misses and invalid explicit names.
    if .path$ = ""
        exitScript: "No " + .label$ + " file found in:" + newline$
            ... + "  " + wf$ + newline$
            ... + "Place one " + .label$ + " file there, or use an explicit filename."
    endif
    if not fileReadable(.path$)
        exitScript: "Required " + .label$ + " file is not readable:" + newline$ + "  " + .path$
    endif
endproc

procedure requireNonEmpty: .val$, .label$
    # Exit with a readable message if a required text field is empty.
    if .val$ = ""
        exitScript: .label$ + " is empty. Fill in the field and run again."
    endif
endproc

procedure runFFmpeg: .cmd$, .outPath$
    appendInfoLine: "Command:"
    appendInfoLine: "  ", .cmd$
    if dry_run = 1
        appendInfoLine: "Dry run: not executed."
        appendInfoLine: ""
        .ok = 0
    else
        if fileReadable(.outPath$)
            deleteFile: .outPath$
        endif
        appendInfoLine: "Running FFmpeg..."
        .launchCmd$ = .cmd$
        if windows and ffmpegNeedsOuterQuote
            .launchCmd$ = q$ + .cmd$ + q$
        endif
        runSystem_nocheck: .launchCmd$
        .ok = 0
        if fileReadable(.outPath$)
            .ok = 1
            appendInfoLine: "Output created: ", .outPath$
        else
            appendInfoLine: "WARNING: Output file not found: ", .outPath$
            appendInfoLine: "  Paste the command above into a terminal to see the FFmpeg diagnostic."
        endif
        appendInfoLine: ""
    endif
endproc

procedure makeEvenDimensions: .w, .h
    .w2 = floor(.w)
    .h2 = floor(.h)
    if .w2 mod 2 <> 0
        .w2 = .w2 - 1
    endif
    if .h2 mod 2 <> 0
        .h2 = .h2 - 1
    endif
    if .w2 < 2 or .h2 < 2
        exitScript: "Width and Height must be at least 2 pixels."
    endif
endproc

procedure getBasename: .path$
    # Returns the filename without extension from a full path.
    # Result is in getBasename.result$
    .result$ = ""
    if .path$ <> ""
        .ls = rindex(.path$, "/")
        .ld = rindex(.path$, ".")
        if .ld > .ls
            .result$ = mid$(.path$, .ls + 1, .ld - .ls - 1)
        else
            .result$ = mid$(.path$, .ls + 1, length(.path$) - .ls)
        endif
    endif
endproc

procedure hmsToSec: .hms$
    # Strict parser for HH:MM:SS.mmm, MM:SS.mmm, or SS.mmm.
    # Reject shell/meta characters before number(), which can accept a
    # numeric prefix and otherwise hide malformed trailing text.
    if length(.hms$) = 0
        exitScript: "Time field is empty."
    endif
    for .ci to length(.hms$)
        .ch$ = mid$(.hms$, .ci, 1)
        if index("0123456789.:", .ch$) = 0
            exitScript: "Time contains an invalid character: '" + .hms$ + "'"
        endif
    endfor

    .nColons = 0
    for .ci to length(.hms$)
        if mid$(.hms$, .ci, 1) = ":"
            .nColons = .nColons + 1
        endif
    endfor

    if .nColons = 2
        .c1 = index(.hms$, ":")
        .h$ = left$(.hms$, .c1 - 1)
        .rest$ = mid$(.hms$, .c1 + 1, length(.hms$) - .c1)
        .c2 = index(.rest$, ":")
        .m$ = left$(.rest$, .c2 - 1)
        .s$ = mid$(.rest$, .c2 + 1, length(.rest$) - .c2)
        .h = number(.h$)
        .m = number(.m$)
        .s = number(.s$)
        if .h = undefined or .m = undefined or .s = undefined
            exitScript: "Invalid time: '" + .hms$ + "'"
        endif
        if .m < 0 or .m >= 60 or .s < 0 or .s >= 60
            exitScript: "For HH:MM:SS, minutes and seconds must be below 60: '" + .hms$ + "'"
        endif
        .seconds = .h * 3600 + .m * 60 + .s
    elsif .nColons = 1
        .c1 = index(.hms$, ":")
        .m$ = left$(.hms$, .c1 - 1)
        .s$ = mid$(.hms$, .c1 + 1, length(.hms$) - .c1)
        .m = number(.m$)
        .s = number(.s$)
        if .m = undefined or .s = undefined
            exitScript: "Invalid time: '" + .hms$ + "'"
        endif
        if .m < 0 or .s < 0 or .s >= 60
            exitScript: "For MM:SS, seconds must be below 60: '" + .hms$ + "'"
        endif
        .seconds = .m * 60 + .s
    elsif .nColons = 0
        .s = number(.hms$)
        if .s = undefined
            exitScript: "Invalid time: '" + .hms$ + "'"
        endif
        .seconds = .s
    else
        exitScript: "Time format must be HH:MM:SS.mmm, MM:SS.mmm, or SS.mmm. Got: '" + .hms$ + "'"
    endif
    if .seconds < 0
        exitScript: "Time values must be non-negative. Got: '" + .hms$ + "'"
    endif
endproc

procedure findFirstFile: .folder$, .extensions$
    # Look in .folder$ for the first file matching any extension in
    # .extensions$ (space-separated, case-sensitive — pass both
    # cases if needed: "wav WAV mp3 MP3"). Returns the full path
    # in findFirstFile.result$ or "" if no match.
    #
    # Replaces four near-identical 30-line iteration blocks in v1.0.
    .result$ = ""
    .rem$ = .extensions$ + " "
    while length(.rem$) > 0 and .result$ = ""
        # Strip leading whitespace
        while length(.rem$) > 0 and left$(.rem$, 1) = " "
            .rem$ = mid$(.rem$, 2, length(.rem$) - 1)
        endwhile
        if length(.rem$) = 0
            # done
        else
            .sp = index(.rem$, " ")
            if .sp = 0
                .ext$ = .rem$
                .rem$ = ""
            else
                .ext$ = left$(.rem$, .sp - 1)
                .rem$ = mid$(.rem$, .sp + 1, length(.rem$) - .sp)
            endif
            if length(.ext$) > 0
                Create Strings as file list: "ff_list", .folder$ + "/*." + .ext$
                .nMatched = Get number of strings
                if .nMatched > 0
                    .firstName$ = Get string: 1
                    .result$ = .folder$ + "/" + .firstName$
                endif
                Remove
            endif
        endif
    endwhile
endproc

procedure escapeSubtitlesPath: .path$
    # FFmpeg's subtitles= filter uses ":" as a key/value separator
    # within the filter argument. On Windows, paths begin with
    # "C:/" which the filter parser misinterprets. The fix is to
    # escape the drive-letter colon as "\:". macOS and Linux paths
    # don't have this issue.
    # Result in escapeSubtitlesPath.result$
    .result$ = .path$
    if windows
        # Escape any ":" in the path (covers drive letter and any
        # other colons that might appear, though those are rare).
        .out$ = ""
        for .i to length(.path$)
            .ch$ = mid$(.path$, .i, 1)
            if .ch$ = ":"
                .out$ = .out$ + "\:"
            else
                .out$ = .out$ + .ch$
            endif
        endfor
        .result$ = .out$
    endif
endproc

# ============================================================
# GLOBAL CONSTANTS
# ============================================================

# Shell-safe double-quote character. Wrapping paths in double
# quotes handles spaces on both Windows (cmd.exe) and Unix.
q$ = """"

# ============================================================
# FOLDER SETUP  -  validation, ffmpeg discovery, file detection
# ============================================================

# One working folder contains ffmpeg(.exe) and the media files.
wf$ = folder$
if length(wf$) > 1
    lastChar$ = right$(wf$, 1)
    if lastChar$ = "/" or lastChar$ = "\"
        wf$ = left$(wf$, length(wf$) - 1)
    endif
endif
if length(wf$) = 0
    exitScript: "Folder path is empty. Fill in the Folder field."
endif

if windows
    ffmpeg$ = wf$ + "/ffmpeg.exe"
else
    ffmpeg$ = wf$ + "/ffmpeg"
endif
if not fileReadable(ffmpeg$)
    exitScript: "FFmpeg not found at:" + newline$ + "  " + ffmpeg$ + newline$
        ... + "Check that the Folder exists and contains the FFmpeg executable."
endif

# Praat 7 on Windows launches runSystem through cmd.exe /c. If the executable
# path has no whitespace, leave the first token unquoted; media paths remain quoted.
# If the executable path itself needs quotes, runFFmpeg adds an outer quote pair.
ffmpegNeedsOuterQuote = 0
if windows
    if index(ffmpeg$, " ") = 0 and index(ffmpeg$, tab$) = 0
        ffmpeg_cmd$ = ffmpeg$ + " -nostdin -hide_banner -loglevel error"
    else
        ffmpeg_cmd$ = q$ + ffmpeg$ + q$ + " -nostdin -hide_banner -loglevel error"
        ffmpegNeedsOuterQuote = 1
    endif
else
    ffmpeg_cmd$ = q$ + ffmpeg$ + q$ + " -nostdin -hide_banner -loglevel error"
endif

# --- Auto-detect input files (NEW: refactored to one procedure) ---
if video_file$ = "AUTO" or video_file$ = "auto" or video_file$ = ""
    @findFirstFile: wf$, "mp4 MP4 mov MOV avi AVI mkv MKV m4v M4V webm WEBM"
    input_video$ = findFirstFile.result$
else
    input_video$ = wf$ + "/" + video_file$
endif

if audio_file$ = "AUTO" or audio_file$ = "auto" or audio_file$ = ""
    @findFirstFile: wf$, "wav WAV mp3 MP3 aiff AIFF flac FLAC m4a M4A"
    input_audio$ = findFirstFile.result$
else
    input_audio$ = wf$ + "/" + audio_file$
endif

@findFirstFile: wf$, "jpg JPG jpeg JPEG png PNG bmp BMP tiff TIFF"
input_image$ = findFirstFile.result$

@findFirstFile: wf$, "srt SRT ass ASS ssa SSA"
input_subtitle$ = findFirstFile.result$

# ---- Derive output path from operation + input basename ----
@getBasename: input_video$
vbase$ = getBasename.result$
@getBasename: input_audio$
abase$ = getBasename.result$

vext$ = ".mp4"
if input_video$ <> ""
    vdot = rindex(input_video$, ".")
    vslash = rindex(input_video$, "/")
    if vdot > vslash
        vext$ = mid$(input_video$, vdot, length(input_video$))
    endif
endif

output_file$ = ""
if operation = 1
    output_file$ = wf$ + "/" + vbase$ + "_replaced_audio.mp4"
elsif operation = 2
    output_file$ = wf$ + "/" + vbase$ + "_extracted.wav"
elsif operation = 3
    output_file$ = wf$ + "/" + vbase$ + "_cut" + vext$
elsif operation = 4
    output_file$ = wf$ + "/" + abase$ + "_waveform.mp4"
elsif operation = 5
    output_file$ = wf$ + "/" + abase$ + "_spectrogram.mp4"
elsif operation = 6
    output_file$ = wf$ + "/" + vbase$ + "_export.mp4"
elsif operation = 7
    output_file$ = wf$ + "/" + abase$ + "_image_video.mp4"
elsif operation = 8
    output_file$ = wf$ + "/" + vbase$ + "_subtitled.mp4"
elsif operation = 9
    output_file$ = wf$ + "/" + vbase$ + "_hardcoded.mp4"
elsif operation = 10
    output_file$ = wf$ + "/" + vbase$ + "_hap.mov"
elsif operation = 11
    output_file$ = wf$ + "/" + vbase$ + "_fps" + string$(round(target_fps)) + ".mp4"
elsif operation = 12
    output_file$ = wf$ + "/" + abase$ + "_contact.mp4"
endif

final_output$ = output_file$

clearinfo
writeInfoLine: "=== FFmpeg Media Tools v1.4 ==="
appendInfoLine: "Folder:   ", wf$
appendInfoLine: "Video:    ", input_video$
appendInfoLine: "Audio:    ", input_audio$
appendInfoLine: "Output:   ", output_file$
if dry_run = 1
    appendInfoLine: "Dry run:  ON  (commands printed, FFmpeg not executed)"
endif
appendInfoLine: ""

# ============================================================
# OPERATION DISPATCH
# ============================================================

if operation = 1
    # ----------------------------------------------------------
    # Op 1: REPLACE AUDIO IN VIDEO
    # Copies the original video stream and replaces the audio
    # stream with the supplied WAV, encoded as AAC (192 kbps).
    # ----------------------------------------------------------
    @requireFile: input_video$, "video"
    @requireFile: input_audio$, "audio"

    shortest$ = ""
    if shortest_stream
        shortest$ = " -shortest"
    endif

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -map 0:v:0 -map 1:a:0"
        ... + " -c:v copy"
        ... + " -c:a aac -b:a 192k"
        ... + shortest$
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 2
    # ----------------------------------------------------------
    # Op 2: EXTRACT AUDIO FROM VIDEO -> OPEN IN PRAAT
    # ----------------------------------------------------------
    @requireFile: input_video$, "video"

    if channels = 1
        ac$ = " -ac 1"
    else
        ac$ = " -ac 2"
    endif

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -vn"
        ... + " -ar " + string$(round(sample_rate))
        ... + ac$
        ... + " -c:a pcm_s16le"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$
    if dry_run = 0 and runFFmpeg.ok
        appendInfoLine: "Loading extracted audio into Praat..."
        Read from file: output_file$
        appendInfoLine: "Loaded: ", selected$("Sound")
        appendInfoLine: ""
    endif

elsif operation = 3
    # ----------------------------------------------------------
    # Op 3: CUT VIDEO WITHOUT RE-ENCODING (stream copy)
    # The start can land at an earlier keyframe; use op 6 when exact
    # A/V alignment matters.
    # ----------------------------------------------------------
    @requireFile: input_video$, "video"
    @requireNonEmpty: start_time$, "Start time"
    @requireNonEmpty: end_time_or_duration$, "End time / Duration"

    @hmsToSec: start_time$
    cutStart = hmsToSec.seconds
    @hmsToSec: end_time_or_duration$
    cutEndOrDur = hmsToSec.seconds
    if use_duration_not_end
        cutDur = cutEndOrDur
    else
        cutDur = cutEndOrDur - cutStart
    endif
    if cutDur <= 0
        exitScript: "Cut duration must be greater than zero."
    endif
    cutStart$ = fixed$(cutStart, 6)
    cutDur$ = fixed$(cutDur, 6)
    appendInfoLine: "Requested stream-copy range: start ", cutStart$, " s | duration ", cutDur$, " s"
    appendInfoLine: "Note: stream copy can preserve preroll from an earlier keyframe."

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -ss " + cutStart$
        ... + " -i " + q$ + input_video$ + q$
        ... + " -t " + cutDur$
        ... + " -map 0"
        ... + " -c copy"
        ... + " " + q$ + output_file$ + q$
    @runFFmpeg: cmd$, output_file$

elsif operation = 4
    # ----------------------------------------------------------
    # Op 4: WAVEFORM VIDEO FROM AUDIO
    # ----------------------------------------------------------
    @requireFile: input_audio$, "audio"

    @makeEvenDimensions: width, height
    vidW = makeEvenDimensions.w2
    vidH = makeEvenDimensions.h2
    if vidW <> round(width) or vidH <> round(height)
        appendInfoLine: "Video dimensions adjusted to even values: ", vidW, "x", vidH
    endif
    size$ = string$(vidW) + "x" + string$(vidH)
    fps$  = string$(round(frame_rate))

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -filter_complex " + q$
        ... + "[0:a]asplit=2[awav][aout];"
        ... + "[awav]showwaves=s=" + size$
        ... + ":mode=line:rate=" + fps$
        ... + "[vout]" + q$
        ... + " -map [vout] -map [aout]"
        ... + " -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p"
        ... + " -c:a aac -b:a 192k"
        ... + " -r " + fps$
        ... + " -shortest"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 5
    # ----------------------------------------------------------
    # Op 5: SPECTROGRAM VIDEO FROM AUDIO
    # ----------------------------------------------------------
    @requireFile: input_audio$, "audio"

    @makeEvenDimensions: width, height
    vidW = makeEvenDimensions.w2
    vidH = makeEvenDimensions.h2
    if vidW <> round(width) or vidH <> round(height)
        appendInfoLine: "Video dimensions adjusted to even values: ", vidW, "x", vidH
    endif
    size$ = string$(vidW) + "x" + string$(vidH)
    fps$  = string$(round(frame_rate))

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -filter_complex " + q$
        ... + "[0:a]asplit=2[aspec][aout];"
        ... + "[aspec]showspectrum=s=" + size$
        ... + ":slide=scroll:mode=combined"
        ... + ":color=intensity:scale=log,fps=" + fps$ + "[vout]" + q$
        ... + " -map [vout] -map [aout]"
        ... + " -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p"
        ... + " -c:a aac -b:a 192k"
        ... + " -r " + fps$
        ... + " -shortest"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 6
    # ----------------------------------------------------------
    # Op 6: EXPORT PRAAT SOUND RANGE AS VIDEO SEGMENT
    # Re-encodes the cut video for accurate timing, then optionally
    # replaces its audio with the matching Praat Sound range.
    # ----------------------------------------------------------
    selectObject: op6_sound
    @requireFile: input_video$, "video"
    @requireNonEmpty: start_time$, "Start time"
    @requireNonEmpty: end_time_or_duration$, "End time / Duration"
    sel_sound = selected("Sound")

    @hmsToSec: start_time$
    reqStart = hmsToSec.seconds
    @hmsToSec: end_time_or_duration$
    reqEndOrDur = hmsToSec.seconds
    if use_duration_not_end
        reqDur = reqEndOrDur
    else
        reqDur = reqEndOrDur - reqStart
    endif
    if reqDur <= 0
        exitScript: "Operation 6 duration must be greater than zero."
    endif

    selectObject: sel_sound
    sndXmin = Get start time
    sndXmax = Get end time
    sndFs = Get sampling frequency
    sndDur = sndXmax - sndXmin
    relT1 = reqStart
    relT2 = reqStart + reqDur
    if relT2 > sndDur
        relT2 = sndDur
    endif
    if relT1 >= relT2
        exitScript: "Requested range does not overlap the selected Sound."
    endif
    soundT1 = sndXmin + relT1
    soundT2 = sndXmin + relT2
    actualDur = relT2 - relT1
    if abs(actualDur - reqDur) > 0.5 / sndFs
        appendInfoLine: "Praat range clipped to Sound end: actual duration ", fixed$(actualDur, 6), " s"
    endif

    videoDur = reqDur
    if replace_audio_in_cut
        videoDur = actualDur
    endif

    dotPos = rindex(output_file$, ".")
    out_base$ = left$(output_file$, dotPos - 1)
    if replace_audio_in_cut
        cut_video$ = out_base$ + "_cut.mp4"
    else
        cut_video$ = output_file$
    endif
    praat_wav$ = out_base$ + "_praat_sel.wav"

    appendInfoLine: "Range: video start ", fixed$(reqStart, 6), " s | duration ", fixed$(videoDur, 6), " s"
    appendInfoLine: "Praat Sound relative range: ", fixed$(relT1, 6), "-", fixed$(relT2, 6), " s | object xmin ", fixed$(sndXmin, 6), " s"

    appendInfoLine: "Step (a): Creating accurate video segment..."
    cmd_a$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -ss " + fixed$(reqStart, 6)
        ... + " -t " + fixed$(videoDur, 6)
        ... + " -map 0:v:0 -map 0:a?"
        ... + " -vf " + q$ + "scale=trunc(iw/2)*2:trunc(ih/2)*2" + q$
        ... + " -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p"
        ... + " -c:a aac -b:a 192k"
        ... + " " + q$ + cut_video$ + q$
    @runFFmpeg: cmd_a$, cut_video$

    if replace_audio_in_cut
        appendInfoLine: "Step (b): Exporting Praat Sound range as WAV..."
        if dry_run = 1
            appendInfoLine: "Dry run: skipping Praat WAV export step."
            appendInfoLine: ""
        else
            selectObject: sel_sound
            part_snd = Extract part: soundT1, soundT2, "rectangular", 1.0, "yes"
            Save as WAV file: praat_wav$
            removeObject: part_snd
            appendInfoLine: "  Saved: ", praat_wav$
        endif

        appendInfoLine: "Step (c): Replacing segment audio with Praat WAV..."
        cmd_c$ = ffmpeg_cmd$ + " -y"
            ... + " -i " + q$ + cut_video$ + q$
            ... + " -i " + q$ + praat_wav$ + q$
            ... + " -map 0:v:0 -map 1:a:0"
            ... + " -c:v copy -c:a aac -b:a 192k -shortest"
            ... + " " + q$ + output_file$ + q$
        @runFFmpeg: cmd_c$, output_file$
        final_output$ = output_file$
    else
        final_output$ = cut_video$
        appendInfoLine: "Audio replacement disabled; final output is the accurate cut."
    endif

elsif operation = 7
    # ----------------------------------------------------------
    # Op 7: STILL IMAGE + AUDIO -> VIDEO
    # ----------------------------------------------------------
    @requireFile: input_image$, "image (jpg/png)"
    @requireFile: input_audio$, "audio"

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -loop 1"
        ... + " -i " + q$ + input_image$ + q$
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -map 0:v -map 1:a"
        ... + " -vf " + q$ + "scale=trunc(iw/2)*2:trunc(ih/2)*2" + q$
        ... + " -c:v libx264 -preset fast -crf 18"
        ... + " -tune stillimage"
        ... + " -pix_fmt yuv420p"
        ... + " -c:a aac -b:a 192k"
        ... + " -shortest"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 8
    # ----------------------------------------------------------
    # Op 8: ADD SOFT SUBTITLES (mov_text, MP4)
    # ----------------------------------------------------------
    @requireFile: input_video$,    "video"
    @requireFile: input_subtitle$, "subtitle (srt/ass)"

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_video$    + q$
        ... + " -i " + q$ + input_subtitle$ + q$
        ... + " -map 0:v:0 -map 0:a? -map 1:s:0"
        ... + " -c:v copy -c:a aac -b:a 192k"
        ... + " -c:s mov_text"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 9
    # ----------------------------------------------------------
    # Op 9: BURN SUBTITLES INTO VIDEO (hardcode)
    # FIX (v1.1): the path inside subtitles= filter must escape
    # ":" on Windows. The escapeSubtitlesPath procedure handles
    # this automatically so the dry-run output is also correct.
    # macOS and Linux paths pass through unchanged.
    # ----------------------------------------------------------
    @requireFile: input_video$,    "video"
    @requireFile: input_subtitle$, "subtitle (srt/ass)"

    @escapeSubtitlesPath: input_subtitle$
    sub_path_filter$ = escapeSubtitlesPath.result$

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -vf " + q$ + "subtitles=" + sub_path_filter$ + ",scale=trunc(iw/2)*2:trunc(ih/2)*2" + q$
        ... + " -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p"
        ... + " -c:a aac -b:a 192k"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 10
    # ----------------------------------------------------------
    # Op 10: CONVERT VIDEO TO HAP (Max/MSP / Jitter)
    # ----------------------------------------------------------
    @requireFile: input_video$, "video"

    if hap_mode = 1
        hap_fmt$ = ""
    elsif hap_mode = 2
        hap_fmt$ = " -format hap_alpha"
    else
        hap_fmt$ = " -format hap_q"
    endif

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -c:v hap"
        ... + hap_fmt$
        ... + " -c:a aac -b:a 192k"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 11
    # ----------------------------------------------------------
    # Op 11: CHANGE VIDEO FRAME RATE
    # ----------------------------------------------------------
    @requireFile: input_video$, "video"

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -vf " + q$ + "fps=" + string$(target_fps) + ",scale=trunc(iw/2)*2:trunc(ih/2)*2" + q$
        ... + " -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p"
        ... + " -c:a aac -b:a 192k"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 12
    # ----------------------------------------------------------
    # Op 12: ANALYSIS CONTACT VIDEO
    # Top = waveform; bottom = scrolling logarithmic spectrum.
    # ----------------------------------------------------------
    @requireFile: input_audio$, "audio"

    @makeEvenDimensions: width, height
    vidW = makeEvenDimensions.w2
    vidH = makeEvenDimensions.h2
    halfH = floor(vidH / 2)
    if halfH < 2
        exitScript: "Height is too small for a two-panel analysis video."
    endif
    vidH = 2 * halfH
    if vidW <> round(width) or vidH <> round(height)
        appendInfoLine: "Video dimensions adjusted for encoder/stack: ", vidW, "x", vidH
    endif
    panelSize$ = string$(vidW) + "x" + string$(halfH)
    fps$ = string$(round(frame_rate))

    cmd$ = ffmpeg_cmd$ + " -y"
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -filter_complex " + q$
        ... + "[0:a]asplit=3[awav][aspec][aout];"
        ... + "[awav]showwaves=s=" + panelSize$ + ":mode=p2p:rate=" + fps$ + ":colors=0x00cccc[wv];"
        ... + "[aspec]showspectrum=s=" + panelSize$ + ":slide=scroll:mode=combined:color=intensity:scale=log,fps=" + fps$ + "[sp];"
        ... + "[wv][sp]vstack=inputs=2[vout]" + q$
        ... + " -map [vout] -map [aout]"
        ... + " -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p"
        ... + " -c:a aac -b:a 192k -r " + fps$
        ... + " -shortest"
        ... + " " + q$ + output_file$ + q$
    @runFFmpeg: cmd$, output_file$

endif

appendInfoLine: ""
if operation = 6
    appendInfoLine: "Final output: ", final_output$
endif
appendInfoLine: "=== DONE ==="
