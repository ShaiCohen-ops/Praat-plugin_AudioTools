# ============================================================
# Praat AudioTools - IRCAM_Partial_Stretch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SPEAR-style partial manipulation for electroacoustic composition.
#   The selected Sound is analysed with IRCAM PM2 into partial tracks;
#   one track operation is applied; the tracks are resynthesised as a
#   sum of sinusoids.
#
#   Modes (what they actually do):
#     Spectral stretch  tracks above the split frequency are time-stretched
#                       and receive an AUTOMATIC gain (x1..x8) so they stay
#                       audible; lower tracks are untouched
#     Band stretch      three bands, each with its own time-stretch factor
#                       and AUTOMATIC per-band gain (x1..x8)
#     Freeze            the partials at one instant held as a drone
#     Partial thin      above a threshold, keep every N-th track
#     Spectral blur     amplitude-envelope smoothing of every track;
#                       frequencies unchanged (not a frequency blur)
#
#   After synthesis, automatic LEVEL BALANCING evens out 0.5 s blocks
#   (switchable), then the result is peak-normalised to 0.9 and Output
#   gain is applied (capped at 2, hard clipping reported).
#
# Pipeline:
#   Praat  : Sound -> WAV + key=value parameter file
#   Python : PM2 (-Apar) at the file's own sample rate -> partial tracks
#            (stratified selection over 7 frequency bands) -> mode ->
#            additive resynthesis -> level balancing -> WAV + manifest +
#            track data for the figure
#   Praat  : result, Info report, figure, cleanup, play
#
# Changelog v1.4:
#   - Sample rate: PM2 analysis geometry and resynthesis now use the
#     input file's rate (was fixed at 44.1 kHz: wrong window/hop and a
#     44.1 kHz output for any other input). 44.1 kHz results unchanged,
#     verified sample-identical to v1.3 in all five modes.
#   - Short form (mode, output, PM2 folder); each mode's parameters in a
#     second dialog; analysis settings behind "Advanced".
#   - Figure rebuilt around the process: input partial tracks coloured by
#     the groups the mode treats differently (with split / band /
#     threshold / freeze marks), output partial tracks, the gain applied
#     after synthesis (level balancing + normalisation), waveforms, and a
#     summary with the automatic boosts and group counts.
#   - Info report: tracks per band, groups, automatic boosts, PM2
#     window/hop in samples and ms, level-balancing range, clipping.
#   - Level balancing can be switched off (default on = v1.3 sound).
#   - Parameters passed in a file (robust on Windows); session-tagged
#     temporary files, all removed; Praat 7 trust request; clear errors
#     instead of silent fixes (Thin every N < 2).
#   - Spectral blur documented as amplitude-envelope smoothing.
#   - Version unified at 1.4 with partial_stretch.py.
#
# Requires:
#   Praat 6.3+; Python 3 with numpy and soundfile; IRCAM PM2 executable.
# ============================================================

version$ = "1.4"

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- FORM (short: details follow in a mode dialog) ----
form: "Partial Stretch v1.4"
    comment: "Folder containing pm2 / pm2.exe"
    sentence: "Pm2 bin directory", "C:\Users\User\Pm2\bin"
    optionmenu: "Mode", 1
        option: "Spectral stretch"
        option: "Band stretch"
        option: "Freeze"
        option: "Partial thin"
        option: "Spectral blur (amplitude smoothing)"
    real: "Output gain", "1.0"
    boolean: "Level balancing", 1
    comment: "Level balancing evens out loudness in 0.5 s blocks after synthesis"
    boolean: "Advanced analysis settings", 0
    boolean: "Draw visualisation", 1
    boolean: "Play result", 1
endform

# ---- MODE PARAMETERS (second dialog, only the chosen mode) ----
split_freq = 1000
upper_factor = 3
band_low = 500
band_mid = 2000
band_low_stretch = 1
band_mid_stretch = 2
band_high_stretch = 4
freeze_pos = 0.5
freeze_dur = 5
thin_above = 1000
thin_every = 2
blur_ms = 100
max_partials = 200
window_ms = 46.44
hop_ms = 5

beginPause: "Partial Stretch — " + mode$
if mode = 1
    comment: "Tracks above the split are time-stretched and get an automatic gain"
    positive: "Split frequency (Hz)", string$(split_freq)
    positive: "Upper stretch factor", string$(upper_factor)
elsif mode = 2
    comment: "Three bands, own stretch factor each (plus automatic per-band gain)"
    positive: "Band low edge (Hz)", string$(band_low)
    positive: "Band mid edge (Hz)", string$(band_mid)
    positive: "Low stretch", string$(band_low_stretch)
    positive: "Mid stretch", string$(band_mid_stretch)
    positive: "High stretch", string$(band_high_stretch)
elsif mode = 3
    comment: "Freeze position is normalised: 0 = start, 1 = end of the Sound"
    real: "Freeze position (0-1)", string$(freeze_pos)
    positive: "Freeze duration (s)", string$(freeze_dur)
elsif mode = 4
    comment: "Above the threshold keep every N-th track (by mean frequency)"
    positive: "Thin above (Hz)", string$(thin_above)
    integer: "Keep every N", string$(thin_every)
else
    comment: "Moving average of each track amplitude envelope (frequencies unchanged)"
    positive: "Blur window (ms)", string$(blur_ms)
endif
endPause: "Continue", 1
if mode = 1
    split_freq = split_frequency
    upper_factor = upper_stretch_factor
elsif mode = 2
    band_low = band_low_edge
    band_mid = band_mid_edge
    band_low_stretch = low_stretch
    band_mid_stretch = mid_stretch
    band_high_stretch = high_stretch
elsif mode = 3
    freeze_pos = freeze_position
    freeze_dur = freeze_duration
elsif mode = 4
    thin_above = thin_above
    thin_every = keep_every_N
else
    blur_ms = blur_window
endif

if advanced_analysis_settings
    beginPause: "Partial Stretch — PM2 analysis"
        natural: "Max partials", string$(max_partials)
        positive: "Analysis window (ms)", string$(window_ms)
        positive: "Hop (ms)", string$(hop_ms)
        comment: "Window is rounded to the nearest power of two in samples"
    endPause: "Continue", 1
    max_partials = max_partials
    window_ms = analysis_window
    hop_ms = hop
endif

# ---- VALIDATION ----
if mode = 2 and band_low >= band_mid
    exitScript: "Band low edge must be below the band mid edge."
endif
if mode = 3 and (freeze_pos < 0 or freeze_pos > 1)
    exitScript: "Freeze position must be between 0 and 1."
endif
if mode = 4 and thin_every < 2
    exitScript: "Keep every N must be 2 or more (1 would keep every track)."
endif
if output_gain <= 0
    exitScript: "Output gain must be > 0."
endif

# ---- PRAAT 7 TRUST ----
if praatVersion >= 7000
    trustOK = askForTrust()
    if not trustOK
        exitScript: "Partial Stretch needs permission to write temporary files and run Python/PM2."
    endif
endif

# ---- PATHS ----
pluginDir$ = replace$(preferencesDirectory$, "\", "/", 0) + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/partial_stretch.py"
if not fileReadable(pythonScript$)
    pythonScript$ = replace$(defaultDirectory$, "\", "/", 0) + "/partial_stretch.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find partial_stretch.py (expected in " + pluginDir$ + "py/ or next to this script)."
endif

pm2Dir$ = replace$(pm2_bin_directory$, "\", "/", 0)
if right$(pm2Dir$, 1) <> "/"
    pm2Dir$ = pm2Dir$ + "/"
endif
if windows
    pm2Exe$ = pm2Dir$ + "pm2.exe"
else
    pm2Exe$ = pm2Dir$ + "pm2"
endif
if not fileReadable(pm2Exe$)
    exitScript: "PM2 binary not found: " + pm2Exe$ + newline$ + "Set the PM2 folder in the form."
endif

tmpDir$ = replace$(temporaryDirectory$, "\", "/", 0) + "/"
sessionTag$ = replace_regex$(date$(), "[^0-9]", "", 0) + "_" + string$(randomInteger(100000, 999999))
tmp$ = tmpDir$ + "ps_" + sessionTag$ + "_"
inputWav$ = tmp$ + "input.wav"
resultWav$ = tmp$ + "result.wav"
doneFile$ = tmp$ + "done.txt"
logFile$ = tmp$ + "log.txt"
manifestFile$ = tmp$ + "manifest.txt"
paramFile$ = tmp$ + "params.txt"
tracksIn$ = tmp$ + "tracks_in.txt"
tracksOut$ = tmp$ + "tracks_out.txt"
gainFile$ = tmp$ + "gain.txt"

procedure cleanUp
    for .k from 1 to 9
        if .k = 1
            .f$ = inputWav$
        elsif .k = 2
            .f$ = resultWav$
        elsif .k = 3
            .f$ = doneFile$
        elsif .k = 4
            .f$ = logFile$
        elsif .k = 5
            .f$ = manifestFile$
        elsif .k = 6
            .f$ = paramFile$
        elsif .k = 7
            .f$ = tracksIn$
        elsif .k = 8
            .f$ = tracksOut$
        else
            .f$ = gainFile$
        endif
        if fileReadable(.f$)
            deleteFile: .f$
        endif
    endfor
endproc

# ---- PYTHON ----
probePy$ = tmp$ + "probe.py"
probeOK$ = tmp$ + "probe.ok"
writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "import numpy, soundfile"
appendFileLine: probePy$, "open(sys.argv[1], ""w"").write(""ok"")"
if windows
    nCand = 3
    cand1$ = "python"
    cand2$ = "py"
    cand3$ = "python3"
else
    nCand = 2
    cand1$ = "python3"
    cand2$ = "python"
endif
pythonCmd$ = ""
iCand = 1
while iCand <= nCand and pythonCmd$ = ""
    tryCmd$ = cand'iCand'$
    runSystem_nocheck: tryCmd$ + " """ + probePy$ + """ """ + probeOK$ + """"
    if fileReadable(probeOK$)
        pythonCmd$ = tryCmd$
        deleteFile: probeOK$
    endif
    iCand = iCand + 1
endwhile
deleteFile: probePy$
if pythonCmd$ = ""
    exitScript: "No Python 3 with numpy + soundfile found (pip install numpy soundfile)."
endif

# ---- MODE NAME ----
if mode = 1
    modeTok$ = "spectral_stretch"
elsif mode = 2
    modeTok$ = "band_stretch"
elsif mode = 3
    modeTok$ = "freeze"
elsif mode = 4
    modeTok$ = "partial_thin"
else
    modeTok$ = "spectral_blur"
endif
resultName$ = soundName$ + "_ps_" + modeTok$

# ---- RUN ----
selectObject: sound
dur_in = Get total duration
sr_in = Get sampling frequency
Save as WAV file: inputWav$

writeFileLine: paramFile$, "input_wav=" + inputWav$
appendFileLine: paramFile$, "done_file=" + doneFile$
appendFileLine: paramFile$, "pm2_dir=" + pm2Dir$
appendFileLine: paramFile$, "result_wav=" + resultWav$
appendFileLine: paramFile$, "log_path=" + logFile$
appendFileLine: paramFile$, "tmp_prefix=" + tmp$
appendFileLine: paramFile$, "manifest=" + manifestFile$
appendFileLine: paramFile$, "mode=" + modeTok$
appendFileLine: paramFile$, "max_partials=" + string$(max_partials)
appendFileLine: paramFile$, "analysis_window_ms=" + string$(window_ms)
appendFileLine: paramFile$, "hop_ms=" + string$(hop_ms)
appendFileLine: paramFile$, "output_gain=" + string$(output_gain)
appendFileLine: paramFile$, "level_balance=" + string$(level_balancing)
appendFileLine: paramFile$, "split_freq_hz=" + string$(split_freq)
appendFileLine: paramFile$, "upper_stretch_factor=" + string$(upper_factor)
appendFileLine: paramFile$, "band_lo_hz=" + string$(band_low)
appendFileLine: paramFile$, "band_mid_hz=" + string$(band_mid)
appendFileLine: paramFile$, "band_lo_stretch=" + string$(band_low_stretch)
appendFileLine: paramFile$, "band_mid_stretch=" + string$(band_mid_stretch)
appendFileLine: paramFile$, "band_hi_stretch=" + string$(band_high_stretch)
appendFileLine: paramFile$, "freeze_time=" + string$(freeze_pos)
appendFileLine: paramFile$, "freeze_duration=" + string$(freeze_dur)
appendFileLine: paramFile$, "thin_above_hz=" + string$(thin_above)
appendFileLine: paramFile$, "thin_every_n=" + string$(thin_every)
appendFileLine: paramFile$, "blur_window_ms=" + string$(blur_ms)

writeInfoLine: "=== Partial Stretch v", version$, " ==="
appendInfoLine: "Source:  ", soundName$, "  (", fixed$(dur_in, 2), " s, ", sr_in, " Hz)"
appendInfoLine: "Mode:    ", modeTok$
appendInfoLine: "Running PM2 analysis + resynthesis..."
runSubprocess: pythonCmd$, pythonScript$, paramFile$

# ---- RESULT ----
status$ = ""
if fileReadable(doneFile$)
    status$ = readFile$(doneFile$)
endif
man$ = ""
if fileReadable(manifestFile$)
    man$ = newline$ + readFile$(manifestFile$)
endif
procedure man: .key$
    .s$ = extractLine$(man$, newline$ + .key$ + "=")
endproc

if left$(status$, 2) <> "ok" or not fileReadable(resultWav$)
    @man: "error"
    appendInfoLine: ""
    appendInfoLine: "ERROR: ", man.s$
    if fileReadable(logFile$)
        appendInfoLine: ""
        appendInfoLine: "=== backend log ==="
        appendInfoLine: readFile$(logFile$)
    endif
    @cleanUp
    exitScript: "Partial Stretch failed — see the Info window."
endif

resultObj = Read from file: resultWav$
Rename: resultName$
dur_out = Get total duration
sr_out = Get sampling frequency

@man: "groups"
groups$ = man.s$
@man: "selected_per_band"
perBand$ = man.s$
@man: "tracks_selected"
nSel$ = man.s$
@man: "tracks_found"
nFound$ = man.s$
@man: "pm2_window"
pmWin$ = man.s$
@man: "pm2_hop"
pmHop$ = man.s$
@man: "balance_gain_range"
balRange$ = man.s$
@man: "normalise_factor"
normF$ = man.s$
@man: "clipped_samples"
clipped$ = man.s$
@man: "freeze_time_s"
freezeT$ = man.s$
@man: "output_peak"
outPeak$ = man.s$

appendInfoLine: ""
appendInfoLine: "--- PM2 analysis ---"
appendInfoLine: "  window ", pmWin$, ", hop ", pmHop$
appendInfoLine: "  tracks: ", nSel$, " selected of ", nFound$, " found"
appendInfoLine: "  per band (Hz): ", perBand$
appendInfoLine: "--- Operation ---"
appendInfoLine: "  ", groups$
appendInfoLine: "--- Level ---"
if level_balancing
    appendInfoLine: "  level balancing ON: block gains ", balRange$, " (0.5 s blocks toward the median peak)"
else
    appendInfoLine: "  level balancing OFF"
endif
appendInfoLine: "  peak normalisation x", normF$, " to 0.9, output gain x", fixed$(min(output_gain, 2), 2)
if clipped$ <> "0"
    appendInfoLine: "  WARNING: ", clipped$, " samples clipped (output gain above ~1.1)"
endif
appendInfoLine: ""
appendInfoLine: "Result: ", resultName$, "  ", fixed$(dur_out, 3), " s at ", sr_out, " Hz, peak ", outPeak$

if draw_visualisation
    @drawFigure
endif
@cleanUp
selectObject: resultObj
if play_result
    Play
endif

# ============================================================
# FIGURE
# ============================================================
procedure sanitize: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    .out$ = .s$
endproc

procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        .step = .p
    elsif .m < 3.5
        .step = 2 * .p
    elsif .m < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure groupColour: .g
    # .r .gg .b : full-strength colour of a track group
    if .g = 1
        .r = 0.85
        .gg = 0.35
        .b = 0.15
    elsif .g = 2
        if modeTok$ = "partial_thin"
            .r = 0.62
            .gg = 0.62
            .b = 0.62
        else
            .r = 0.15
            .gg = 0.60
            .b = 0.35
        endif
    else
        .r = 0.20
        .gg = 0.40
        .b = 0.80
    endif
endproc

procedure drawTracks: .file$, .y0, .y1, .tMax, .fMax
    # rows: track id, group, time, frequency, amplitude
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, .tMax, 0, .fMax
    Paint rectangle: "{0.99, 0.99, 1.00}", 0, .tMax, 0, .fMax
    if fileReadable(.file$)
        .mx = Read Matrix from raw text file: .file$
        .n = Get number of rows
        .aMax = 1e-12
        for .r to .n
            .a = Get value in cell: .r, 5
            .aMax = max(.aMax, .a)
        endfor
        Line width: 1.2
        .pid = Get value in cell: 1, 1
        .pt = Get value in cell: 1, 3
        .pf = Get value in cell: 1, 4
        .pa = Get value in cell: 1, 5
        for .r from 2 to .n
            .id = Get value in cell: .r, 1
            .tt = Get value in cell: .r, 3
            .ff = Get value in cell: .r, 4
            .aa = Get value in cell: .r, 5
            if .id = .pid and .pa > 1e-7 and .aa > 1e-7 and .pf > 0 and .ff > 0
                .g = Get value in cell: .r, 2
                @groupColour: .g
                .lev = max(0, min(1, (20 * log10(max(.aa, 1e-12) / .aMax) + 60) / 60))
                .w = 0.25 + 0.75 * .lev
                Colour: "{" + fixed$(1 - .w * (1 - groupColour.r), 3) + ", " + fixed$(1 - .w * (1 - groupColour.gg), 3) + ", " + fixed$(1 - .w * (1 - groupColour.b), 3) + "}"
                Draw line: .pt, min(.pf, .fMax), .tt, min(.ff, .fMax)
            endif
            .pid = .id
            .pt = .tt
            .pf = .ff
            .pa = .aa
        endfor
        Line width: 1
        removeObject: .mx
    endif
endproc

procedure modeMarks: .y0, .y1, .tMax, .fMax, .isInput
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, .tMax, 0, .fMax
    Colour: "{0.30, 0.30, 0.30}"
    Dotted line
    if modeTok$ = "spectral_stretch" and split_freq < .fMax
        Draw line: 0, split_freq, .tMax, split_freq
    elsif modeTok$ = "band_stretch"
        if band_low < .fMax
            Draw line: 0, band_low, .tMax, band_low
        endif
        if band_mid < .fMax
            Draw line: 0, band_mid, .tMax, band_mid
        endif
    elsif modeTok$ = "partial_thin" and thin_above < .fMax
        Draw line: 0, thin_above, .tMax, thin_above
    elsif modeTok$ = "freeze" and .isInput and freezeT$ <> ""
        Solid line
        Colour: "{0.85, 0.20, 0.20}"
        Draw line: number(freezeT$), 0, number(freezeT$), .fMax
    endif
    Solid line
endproc

procedure drawFigure
    Erase all
    Line width: 1
    Solid line
    t0 = 0.10
    t1 = 0.60
    a0 = 0.90
    a1 = 2.95
    b0 = 3.35
    b1 = 5.40
    c0 = 5.95
    c1 = 6.80
    d0 = 7.10
    d1 = 7.95
    s0 = 8.50
    s1 = 9.75
    canvasH = 9.85

    # display range: highest partial in the input data, capped at Nyquist
    fMaxD = 5000
    if fileReadable(tracksIn$)
        .mx = Read Matrix from raw text file: tracksIn$
        .n = Get number of rows
        .hi = 0
        for .r to .n
            .a = Get value in cell: .r, 5
            if .a > 1e-7
                .f = Get value in cell: .r, 4
                .hi = max(.hi, .f)
            endif
        endfor
        removeObject: .mx
        if .hi > 0
            fMaxD = min(sr_in / 2, .hi * 1.08)
        endif
    endif

    # title
    Font size: 13
    Select inner viewport: 0.6, 7.7, t0, t1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    @sanitize: modeTok$
    Text: 0.5, "centre", 0.72, "half", "##Partial Stretch — " + sanitize.out$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, t0, t1
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.42}"
    @sanitize: soundName$
    Text: 0.5, "centre", 0.18, "half", sanitize.out$ + "   |   " + nSel$ + " partial tracks   |   PM2 window " + pmWin$

    # legend text per mode
    if modeTok$ = "spectral_stretch"
        legA$ = "blue: below split (unchanged)   orange: above split (stretched, automatic gain)"
    elsif modeTok$ = "band_stretch"
        legA$ = "blue: low band   orange: mid band   green: high band"
    elsif modeTok$ = "partial_thin"
        legA$ = "blue: below threshold   orange: kept above   grey: removed"
    elsif modeTok$ = "freeze"
        legA$ = "red line: freeze instant"
    else
        legA$ = "amplitude envelopes are smoothed; frequencies stay"
    endif

    # A: input partials
    Font size: 7
    @drawTracks: tracksIn$, a0, a1, dur_in, fMaxD
    @modeMarks: a0, a1, dur_in, fMaxD, 1
    Select inner viewport: 0.6, 7.7, a0, a1
    Axes: 0, dur_in, 0, fMaxD
    Colour: "Black"
    Text top: "no", "##Input partials (PM2)## — " + legA$ + "; darker = louder"
    Select inner viewport: 0.6, 7.7, a0, a1
    Axes: 0, dur_in, 0, fMaxD
    Draw inner box
    @niceStep: dur_in, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: fMaxD, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: a0, a1, "Freq (Hz)"

    # B: output partials
    @drawTracks: tracksOut$, b0, b1, dur_out, fMaxD
    @modeMarks: b0, b1, dur_out, fMaxD, 0
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, dur_out, 0, fMaxD
    Colour: "Black"
    Text top: "no", "##Output partials## — after the operation, as resynthesised (" + fixed$(dur_out, 2) + " s)"
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, dur_out, 0, fMaxD
    Draw inner box
    @niceStep: dur_out, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: fMaxD, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @railLabel: b0, b1, "Freq (Hz)"

    # C: gain applied after synthesis (dB)
    if fileReadable(gainFile$)
        .gm = Read Matrix from raw text file: gainFile$
        .n = Get number of rows
        .lo = 1e9
        .hi = -1e9
        for .r to .n
            .g = Get value in cell: .r, 2
            .db = 20 * log10(max(.g, 1e-6))
            .lo = min(.lo, .db)
            .hi = max(.hi, .db)
        endfor
        if .hi - .lo < 6
            .mid = (.hi + .lo) / 2
            .lo = .mid - 3
            .hi = .mid + 3
        endif
        .pad = (.hi - .lo) * 0.1
        Select inner viewport: 0.6, 7.7, c0, c1
        Axes: 0, dur_out, .lo - .pad, .hi + .pad
        Paint rectangle: "{0.98, 0.98, 0.99}", 0, dur_out, .lo - .pad, .hi + .pad
        Colour: "{0.85, 0.35, 0.15}"
        Line width: 1.5
        .xa = Get value in cell: 1, 1
        .ga = Get value in cell: 1, 2
        .ya = 20 * log10(max(.ga, 1e-6))
        for .r from 2 to .n
            .xb = Get value in cell: .r, 1
            .gb = Get value in cell: .r, 2
            .yb = 20 * log10(max(.gb, 1e-6))
            Draw line: .xa, .ya, .xb, .yb
            .xa = .xb
            .ya = .yb
        endfor
        Line width: 1
        removeObject: .gm
        Select inner viewport: 0.6, 7.7, c0, c1
        Axes: 0, dur_out, .lo - .pad, .hi + .pad
        Colour: "Black"
        if level_balancing
            Text top: "no", "##Gain after synthesis## — automatic level balancing x normalisation x output gain (dB)"
        else
            Text top: "no", "##Gain after synthesis## — level balancing off: normalisation x output gain (dB)"
        endif
        Select inner viewport: 0.6, 7.7, c0, c1
        Axes: 0, dur_out, .lo - .pad, .hi + .pad
        Draw inner box
        @niceStep: dur_out, 8
        Marks bottom every: 1, niceStep.step, "no", "yes", "no"
        @niceStep: .hi - .lo + 2 * .pad, 3
        Marks left every: 1, niceStep.step, "yes", "yes", "no"
        @railLabel: c0, c1, "Gain (dB)"
    endif

    # D: waveforms on a shared axis
    .tSpan = max(dur_in, dur_out)
    selectObject: sound
    .m1 = Get absolute extremum: 0, 0, "None"
    selectObject: resultObj
    .m2 = Get absolute extremum: 0, 0, "None"
    .wR = max(.m1, .m2, 1e-6) * 1.05
    Select inner viewport: 0.6, 7.7, d0, d1
    Axes: 0, .tSpan, -.wR, .wR
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, .tSpan, -.wR, .wR
    selectObject: sound
    .mono1 = Convert to mono
    Shift times to: "start time", 0
    Select inner viewport: 0.6, 7.7, d0, d1
    Colour: "{0.72, 0.72, 0.76}"
    Draw: 0, .tSpan, -.wR, .wR, "no", "Curve"
    removeObject: .mono1
    selectObject: resultObj
    .mono2 = Convert to mono
    Select inner viewport: 0.6, 7.7, d0, d1
    Colour: "{0.20, 0.40, 0.80}"
    Draw: 0, .tSpan, -.wR, .wR, "no", "Curve"
    removeObject: .mono2
    Select inner viewport: 0.6, 7.7, d0, d1
    Axes: 0, .tSpan, -.wR, .wR
    Colour: "Black"
    Text top: "no", "##Waveforms## — grey input, blue result"
    Select inner viewport: 0.6, 7.7, d0, d1
    Axes: 0, .tSpan, -.wR, .wR
    Draw inner box
    @niceStep: .tSpan, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @railLabel: d0, d1, "Wave"

    # summary
    Font size: 7
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    @sanitize: "Operation: " + groups$
    Text: 0.012, "left", 0.70, "half", sanitize.out$
    @sanitize: "Tracks per band (Hz): " + perBand$ + "   (" + nSel$ + " of " + nFound$ + ")"
    Text: 0.012, "left", 0.54, "half", sanitize.out$
    if level_balancing
        .lv$ = "Level balancing on (block gains " + balRange$ + ")"
    else
        .lv$ = "Level balancing off"
    endif
    .lv$ = .lv$ + "  |  peak normalisation x" + normF$ + "  |  output gain x" + fixed$(min(output_gain, 2), 2) + "  |  clipped samples " + clipped$
    @sanitize: .lv$
    Text: 0.012, "left", 0.38, "half", sanitize.out$
    @sanitize: "PM2: window " + pmWin$ + ", hop " + pmHop$ + "  |  input " + fixed$(dur_in, 2) + " s → output " + fixed$(dur_out, 2) + " s at " + string$(sr_out) + " Hz"
    Text: 0.012, "left", 0.22, "half", sanitize.out$
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Select outer viewport: 0, 8, 0, canvasH
endproc
