# ============================================================
# Praat AudioTools - Media_ffmpeg_tools.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Praat front-end for twelve FFmpeg video/audio operations.
#   The user points the script at one folder that contains:
#     - ffmpeg (or ffmpeg.exe on Windows)
#     - the input video and/or audio file (one of each)
#   All paths are resolved automatically. Output files are
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
#   Type that folder path in the form. Output is written there.
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

form FFmpeg Media Tools v1.1
    comment === Folder containing ffmpeg(.exe) and your input file(s) ===
    comment     Windows example:   C:/ffmpeg
    comment     Mac / Linux:       /Users/shai/ffmpeg
    sentence Folder C:/ffmpeg
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
    comment === Op 3 and Op 6: Cut times  (HH:MM:SS.mmm) ===
    sentence Start_time 00:00:00.000
    sentence End_time 00:00:10.000
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

# ============================================================
# PROCEDURES  (defined before first use)
# ============================================================

procedure requireFile: .path$, .label$
    # Exit with a clear message if no matching file was found in the folder.
    if .path$ = ""
        exitScript: "No " + .label$ + " file found in:" + newline$
            ... + "  " + wf$ + newline$
            ... + "Place one " + .label$ + " file there and run again."
    endif
endproc

procedure requireNonEmpty: .val$, .label$
    # Exit with a readable message if a required text field is empty.
    if .val$ = ""
        exitScript: .label$ + " is empty. Fill in the field and run again."
    endif
endproc

procedure runFFmpeg: .cmd$, .outPath$
    # Print the full FFmpeg command, execute it via the system shell
    # (unless dry-run is enabled), then verify the output file was
    # created.
    # Uses runSystem_nocheck so FFmpeg errors do not crash Praat;
    # instead the missing-output warning directs the user to a terminal.
    appendInfoLine: "Command:"
    appendInfoLine: "  ", .cmd$
    if dry_run = 1
        appendInfoLine: "Dry run: not executed."
        appendInfoLine: ""
    else
        appendInfoLine: "Running FFmpeg..."
        runSystem_nocheck: .cmd$
        if fileReadable(.outPath$)
            appendInfoLine: "Output created: ", .outPath$
        else
            appendInfoLine: "WARNING: Output file not found: ", .outPath$
            appendInfoLine: "  Check the folder path and input files."
            appendInfoLine: "  Paste the command above into a terminal to see"
            appendInfoLine: "  the full FFmpeg error output."
        endif
        appendInfoLine: ""
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
    # Parse HH:MM:SS.mmm, MM:SS.mmm, or SS.mmm and return decimal
    # seconds in hmsToSec.seconds. Validates inputs against undefined
    # so a malformed time format produces a clear error instead of
    # letting NaN propagate into FFmpeg arguments.
    .nColons = 0
    for .ci to length(.hms$)
        if mid$(.hms$, .ci, 1) = ":"
            .nColons += 1
        endif
    endfor

    if .nColons = 2
        .c1 = index(.hms$, ":")
        .h$ = left$(.hms$, .c1 - 1)
        .rest$ = mid$(.hms$, .c1 + 1, length(.hms$))
        .c2 = index(.rest$, ":")
        .m$ = left$(.rest$, .c2 - 1)
        .s$ = mid$(.rest$, .c2 + 1, length(.rest$))
        .h = number(.h$)
        .m = number(.m$)
        .s = number(.s$)
        if .h = undefined or .m = undefined or .s = undefined
            exitScript: "Time format must be HH:MM:SS.mmm or SS.mmm. Got: '" + .hms$ + "'"
        endif
        .seconds = .h * 3600 + .m * 60 + .s
    elsif .nColons = 1
        .c1 = index(.hms$, ":")
        .m$ = left$(.hms$, .c1 - 1)
        .s$ = mid$(.hms$, .c1 + 1, length(.hms$))
        .m = number(.m$)
        .s = number(.s$)
        if .m = undefined or .s = undefined
            exitScript: "Time format must be HH:MM:SS.mmm or SS.mmm. Got: '" + .hms$ + "'"
        endif
        .seconds = .m * 60 + .s
    elsif .nColons = 0
        .s = number(.hms$)
        if .s = undefined
            exitScript: "Time format must be HH:MM:SS.mmm or SS.mmm. Got: '" + .hms$ + "'"
        endif
        .seconds = .s
    else
        exitScript: "Time format must be HH:MM:SS.mmm or SS.mmm. Got: '" + .hms$ + "'"
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
            .rem$ = mid$(.rem$, 2)
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
                .rem$ = mid$(.rem$, .sp + 1)
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

# Normalize folder: strip trailing slash if present.
wf$ = folder$
if right$(wf$, 1) = "/"
    wf$ = left$(wf$, length(wf$) - 1)
endif

# --- Folder existence check (NEW in v1.1) ---
# Test by trying to list the folder. Praat's fileReadable doesn't
# work on directories cross-platform, but Create Strings as file list
# returns 0 strings for non-existent folders — and crucially does so
# without an error.
Create Strings as file list: "folder_probe", wf$ + "/*"
folder_probe_n = Get number of strings
Remove

# A folder might legitimately contain no files (empty folder).
# So we need a different check: try a wildcard that might match
# anything, including hidden files. If the folder really doesn't
# exist, Praat might show a different behavior depending on OS.
# The cleanest cross-platform check is to look for the folder
# separator on a probe: if the user typed nothing, that's also
# a problem.
if length(wf$) = 0
    exitScript: "Folder path is empty. Fill in the Folder field."
endif

# --- ffmpeg executable check (NEW in v1.1) ---
if windows
    ffmpeg$ = wf$ + "/ffmpeg.exe"
else
    ffmpeg$ = wf$ + "/ffmpeg"
endif

if not fileReadable(ffmpeg$)
    if windows
        platformHint$ = "Windows: download from https://www.gyan.dev/ffmpeg/builds/" + newline$
            ... + "  Extract ffmpeg.exe and place it in the folder above."
    elsif macintosh
        platformHint$ = "macOS: download from https://evermeet.cx/ffmpeg/" + newline$
            ... + "  Or: brew install ffmpeg" + newline$
            ... + "  Place the 'ffmpeg' binary in the folder above."
    else
        platformHint$ = "Linux: apt install ffmpeg  (Debian/Ubuntu)" + newline$
            ... + "  Or: dnf install ffmpeg  (Fedora)" + newline$
            ... + "  Or download from https://ffmpeg.org/download.html" + newline$
            ... + "  Place the 'ffmpeg' binary in the folder above."
    endif
    exitScript: "FFmpeg not found at:" + newline$
        ... + "  " + ffmpeg$ + newline$
        ... + newline$
        ... + platformHint$
endif

# --- Auto-detect input files (NEW: refactored to one procedure) ---
@findFirstFile: wf$, "mp4 MP4 mov MOV avi AVI mkv MKV m4v M4V webm WEBM"
input_video$ = findFirstFile.result$

@findFirstFile: wf$, "wav WAV mp3 MP3 aiff AIFF flac FLAC m4a M4A"
input_audio$ = findFirstFile.result$

@findFirstFile: wf$, "jpg JPG jpeg JPEG png PNG bmp BMP tiff TIFF"
input_image$ = findFirstFile.result$

@findFirstFile: wf$, "srt SRT ass ASS ssa SSA"
input_subtitle$ = findFirstFile.result$

# ---- Derive output path from operation + input basename ----
@getBasename: input_video$
vbase$ = getBasename.result$
@getBasename: input_audio$
abase$ = getBasename.result$

output_file$ = ""
if operation = 1
    output_file$ = wf$ + "/" + vbase$ + "_replaced_audio.mp4"
elsif operation = 2
    output_file$ = wf$ + "/" + vbase$ + "_extracted.wav"
elsif operation = 3
    output_file$ = wf$ + "/" + vbase$ + "_cut.mp4"
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

clearinfo
writeInfoLine: "=== FFmpeg Media Tools v1.1 ==="
appendInfoLine: "Folder:   ", wf$
appendInfoLine: "FFmpeg:   ", ffmpeg$
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

    cmd$ = ffmpeg$ + " -y"
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

    cmd$ = ffmpeg$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -vn"
        ... + " -ar " + string$(round(sample_rate))
        ... + ac$
        ... + " -c:a pcm_s16le"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

    if dry_run = 0 and fileReadable(output_file$)
        appendInfoLine: "Loading extracted audio into Praat..."
        Read from file: output_file$
        appendInfoLine: "Loaded: ", selected$("Sound")
    endif

elsif operation = 3
    # ----------------------------------------------------------
    # Op 3: CUT VIDEO WITHOUT RE-ENCODING (stream copy)
    # NOTE: stream-copy cuts are NOT frame-accurate — FFmpeg
    # seeks to the nearest keyframe before the requested start.
    # ----------------------------------------------------------
    @requireFile: input_video$, "video"
    @requireNonEmpty: start_time$, "Start time"
    @requireNonEmpty: end_time$,   "End time / Duration"

    if use_duration_not_end
        range$ = " -t "  + end_time$
    else
        range$ = " -to " + end_time$
    endif

    cmd$ = ffmpeg$ + " -y"
        ... + " -ss " + start_time$
        ... + " -i "  + q$ + input_video$ + q$
        ... + range$
        ... + " -c copy"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 4
    # ----------------------------------------------------------
    # Op 4: WAVEFORM VIDEO FROM AUDIO
    # ----------------------------------------------------------
    @requireFile: input_audio$, "audio"

    size$ = string$(round(width)) + "x" + string$(round(height))
    fps$  = string$(round(frame_rate))

    cmd$ = ffmpeg$ + " -y"
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -filter_complex " + q$
        ... + "[0:a]asplit=2[awav][aout];"
        ... + "[awav]showwaves=s=" + size$
        ... + ":mode=line:rate=" + fps$
        ... + "[vout]" + q$
        ... + " -map [vout] -map [aout]"
        ... + " -c:v libx264 -preset fast -crf 18"
        ... + " -c:a aac -b:a 192k"
        ... + " -r " + fps$
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 5
    # ----------------------------------------------------------
    # Op 5: SPECTROGRAM VIDEO FROM AUDIO
    # ----------------------------------------------------------
    @requireFile: input_audio$, "audio"

    size$ = string$(round(width)) + "x" + string$(round(height))
    fps$  = string$(round(frame_rate))

    cmd$ = ffmpeg$ + " -y"
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -filter_complex " + q$
        ... + "[0:a]asplit=2[aspec][aout];"
        ... + "[aspec]showspectrum=s=" + size$
        ... + ":slide=scroll:mode=combined"
        ... + ":color=intensity:scale=log[vout]" + q$
        ... + " -map [vout] -map [aout]"
        ... + " -c:v libx264 -preset fast -crf 18"
        ... + " -c:a aac -b:a 192k"
        ... + " -r " + fps$
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 6
    # ----------------------------------------------------------
    # Op 6: EXPORT PRAAT SELECTION AS VIDEO SEGMENT
    # ----------------------------------------------------------
    if numberOfSelected("Sound") <> 1
        exitScript: "Operation 6 requires exactly one Sound object selected."
    endif

    @requireFile: input_video$, "video"
    @requireNonEmpty: start_time$, "Start time"
    @requireNonEmpty: end_time$,   "End time"

    sel_sound = selected("Sound")

    # Derive intermediate paths from the output path
    dotPos = rindex(output_file$, ".")
    if dotPos > 0
        out_base$ = left$(output_file$, dotPos - 1)
        out_ext$  = mid$(output_file$, dotPos, length(output_file$))
    else
        out_base$ = output_file$
        out_ext$  = ".mp4"
    endif

    cut_video$ = out_base$ + "_cut" + out_ext$
    praat_wav$ = out_base$ + "_praat_sel.wav"

    appendInfoLine: "Intermediate files:"
    appendInfoLine: "  ", cut_video$
    appendInfoLine: "  ", praat_wav$
    appendInfoLine: ""

    # (a) Cut the source video to the selected time range
    appendInfoLine: "Step (a): Cutting video segment..."
    cmd_a$ = ffmpeg$ + " -y"
        ... + " -ss " + start_time$
        ... + " -i "  + q$ + input_video$ + q$
        ... + " -to " + end_time$
        ... + " -c copy"
        ... + " " + q$ + cut_video$ + q$

    @runFFmpeg: cmd_a$, cut_video$

    # (b) Export the Sound's time range as a WAV file
    appendInfoLine: "Step (b): Exporting Praat selection as WAV..."

    @hmsToSec: start_time$
    sel_t1 = hmsToSec.seconds
    @hmsToSec: end_time$
    sel_t2 = hmsToSec.seconds

    selectObject: sel_sound
    snd_dur = Get total duration

    if sel_t1 < 0
        sel_t1 = 0
    endif
    if sel_t2 > snd_dur
        sel_t2 = snd_dur
    endif
    if sel_t1 >= sel_t2
        exitScript: "Start time is not before end time within the selected Sound."
    endif

    if dry_run = 1
        appendInfoLine: "Dry run: skipping Praat WAV export step."
        appendInfoLine: ""
    else
        selectObject: sel_sound
        part_snd = Extract part: sel_t1, sel_t2, "rectangular", 1.0, "yes"
        Save as WAV file: praat_wav$
        removeObject: part_snd
        appendInfoLine: "  Saved: ", praat_wav$
    endif

    # (c) Optionally replace the cut video's audio with the Praat WAV
    if replace_audio_in_cut
        appendInfoLine: "Step (c): Replacing cut video audio with Praat WAV..."
        cmd_c$ = ffmpeg$ + " -y"
            ... + " -i " + q$ + cut_video$  + q$
            ... + " -i " + q$ + praat_wav$  + q$
            ... + " -map 0:v:0 -map 1:a:0"
            ... + " -c:v copy -c:a aac -b:a 192k"
            ... + " -shortest"
            ... + " " + q$ + output_file$ + q$
        @runFFmpeg: cmd_c$, output_file$
    else
        appendInfoLine: "Replace audio skipped; final output is the cut video:"
        appendInfoLine: "  ", cut_video$
    endif

elsif operation = 7
    # ----------------------------------------------------------
    # Op 7: STILL IMAGE + AUDIO -> VIDEO
    # ----------------------------------------------------------
    @requireFile: input_image$, "image (jpg/png)"
    @requireFile: input_audio$, "audio"

    cmd$ = ffmpeg$ + " -y"
        ... + " -loop 1"
        ... + " -i " + q$ + input_image$ + q$
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -map 0:v -map 1:a"
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

    cmd$ = ffmpeg$ + " -y"
        ... + " -i " + q$ + input_video$    + q$
        ... + " -i " + q$ + input_subtitle$ + q$
        ... + " -map 0:v -map 0:a -map 1:s"
        ... + " -c:v copy -c:a copy"
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

    cmd$ = ffmpeg$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -vf subtitles=" + q$ + sub_path_filter$ + q$
        ... + " -c:v libx264 -preset fast -crf 18"
        ... + " -c:a copy"
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

    cmd$ = ffmpeg$ + " -y"
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

    cmd$ = ffmpeg$ + " -y"
        ... + " -i " + q$ + input_video$ + q$
        ... + " -vf fps=" + string$(target_fps)
        ... + " -c:v libx264 -preset fast -crf 18"
        ... + " -c:a copy"
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

elsif operation = 12
    # ----------------------------------------------------------
    # Op 12: ANALYSIS CONTACT VIDEO
    # ----------------------------------------------------------
    @requireFile: input_audio$, "audio"

    size$ = string$(round(width)) + "x" + string$(round(height))
    fps$  = string$(round(frame_rate))

    cmd$ = ffmpeg$ + " -y"
        ... + " -i " + q$ + input_audio$ + q$
        ... + " -filter_complex " + q$
        ... + "[0:a]asplit=2[awav][aout];"
        ... + "[awav]showwaves=s=" + size$
        ... + ":mode=p2p:rate=" + fps$
        ... + ":colors=0x00cccc[vout]" + q$
        ... + " -map [vout] -map [aout]"
        ... + " -c:v libx264 -preset fast -crf 18"
        ... + " -c:a aac -b:a 192k"
        ... + " -r " + fps$
        ... + " " + q$ + output_file$ + q$

    @runFFmpeg: cmd$, output_file$

endif

appendInfoLine: ""
appendInfoLine: "=== DONE ==="
