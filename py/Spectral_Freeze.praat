# ============================================================
# Praat AudioTools - Spectral_Freeze.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral freeze — captures the spectrum at one or more moments
#   and sustains it via overlap-add synthesis with random or coherent phase.
#
#   v3: Multi-Freeze mode — captures spectra at N points and
#   crossfades between them, creating an evolving frozen texture.
#   Each freeze point is a "waypoint" in spectral space.
#
#   Modes:
#     Single  — freeze one moment (v2 behaviour)
#     Multi   — freeze N moments, crossfade between them
#
#   Parameters:
#   - Freeze time:   moment to capture (single mode)
#   - Freeze points: how many spectral waypoints (multi mode)
#   - Dwell:         how long to hold each waypoint
#   - Crossfade:     transition time between waypoints
#   - Loop:          cycle back to the first waypoint
#   - Duration:      total output length
#   - Window:        analysis window size (larger = smoother)
#   - Shimmer:       0 = static, 0.1-0.3 = breathing
#   - Fade in/out:   smooth the start and end
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v3.6 (visualisation redesign; no DSP or selection changes):
#   - One 8-inch page that follows the process: A source spectrogram with
#     the exact capture regions + F0 contour with the captured pitches,
#     B capture -> hold routing (source time to output time), C output
#     form as the engine's equal-power state gains (+ fades), D result
#     spectrogram, E the frozen frame spectrum of every waypoint, summary.
#   - Waypoint colours (Okabe-Ito) link all panels; note names escaped for
#     the Picture window (G# no longer turns into bold G); narrow-band
#     spectrograms with a range scaled to the voice so harmonics are legible.
#   - Tick marks on every axis; nothing is drawn outside its panel.
#
# Changelog v3.5.1 (Praat syntax hotfix):
#   - Rename reserved constant pi used as a loop iterator to pitchFrameIndex
#     throughout all pitch analysis and visualization loops. No DSP changes.
#
# Changelog v3.5 (visualisation only):
#   - The Picture display now follows the musical process: source F0 contour
#     and actual capture windows, a time-accurate output state/overlap map,
#     measured output F0, and source/output spectrograms.
#   - Waypoints are annotated with their selected note and source time.
#     Capture bands match the actual two-frame window; output holds,
#     crossfades, end-hold and loop cycles match the Python timeline.
#   - No changes to pitch-aware selection, the command line, or synthesis.
#
# Changelog v3.4:
#   - Freeze point selection (multi mode): "Equally spaced" (v3.3, default)
#     or "Pitch-aware". Pitch-aware analyses the sound in Praat (Pitch,
#     Harmonicity, Intensity, Spectrogram flux) and picks the most stable
#     voiced/tonal moments: steady F0, high HNR, no onset or syllable
#     transition inside the capture region, distinct pitches preferred.
#     Waypoints keep their original chronological order.
#   - Synthesis engine (spectral_freeze.py) is untouched; only the list of
#     freeze times changes, so the two modes can be compared directly.
#   - Fewer stable moments than requested -> uses what it found (>=2) and
#     reports it; fewer than 2 -> falls back to equal spacing.
#   - Waypoint markers are labelled with the detected note; spectral slice
#     panel shows the real first waypoint.
#
# Changelog v3.3:
#   AUDIO:
#   - Multi-freeze crossfades are energy-stable; dissimilar spectra no longer
#     collapse toward silence in the middle of a transition.
#   - Coherent multi-freeze gives every waypoint its own phase/frequency
#     trajectory and crossfades coherent streams with equal-power weights.
#   - Freeze times are true frame centres with safe edge padding; sounds shorter
#     than the FFT window are supported.
#   - Preserves mono/stereo/multichannel layouts; peak safety is global.
#   - Python writes FLOAT WAV.
#   PRAAT/QA:
#   - Unique temp/log paths, captured Python errors, effective FFT-window report.
#   - Multichannel visualisation uses strongest-RMS channels and Nyquist-safe Hz.
#
# Changelog v3.2:
#   - Phase mode: Coherent locks partials to their true frequencies for
#     a steady tonal freeze; Random keeps the diffuse texture
#   - Loop no longer holds the first waypoint twice at the seam
#   - Notes when Duration is shorter than one full waypoint pass
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- PATHS ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/spectral_freeze.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/spectral_freeze.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: spectral_freeze.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

runTag$       = string$(sound)
tempInput$    = tempDir$ + "freeze_" + runTag$ + "_input.wav"
tempOutput$   = tempDir$ + "freeze_" + runTag$ + "_output.wav"
tempLog$      = tempDir$ + "freeze_" + runTag$ + "_python.log"
probePy$      = tempDir$ + "freeze_" + runTag$ + "_probe.py"
probeMarker$  = tempDir$ + "freeze_" + runTag$ + "_probe.ok"

tempInputJ$   = replace_regex$(tempInput$,   "\\", "/", 0)
tempOutputJ$  = replace_regex$(tempOutput$,  "\\", "/", 0)
tempLogJ$     = replace_regex$(tempLog$,     "\\", "/", 0)
probePyJ$     = replace_regex$(probePy$,     "\\", "/", 0)
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

# ---- NOTE NAME (Hz -> "A4") ----
procedure noteName: .hz
    if .hz <= 0
        .name$ = "-"
    else
        .midi = round (69 + 12 * log2 (.hz / 440))
        .pc = .midi mod 12
        .oct = floor (.midi / 12) - 1
        .name$ = replace$ (mid$ ("C C#D D#E F F#G G#A A#B ", .pc * 2 + 1, 2), " ", "", 0)
        ... + string$ (.oct)
    endif
endproc

# ---- VISUALIZATION HELPERS ----
# Strongest-RMS channel as a mono copy (display only)
procedure sfStrongestChannel: .src, .nCh
    if .nCh > 1
        .best = -1
        .id = 0
        for .ch to .nCh
            selectObject: .src
            .cand = Extract one channel: .ch
            .r = Get root-mean-square: 0, 0
            if .r > .best
                if .id <> 0
                    removeObject: .id
                endif
                .id = .cand
                .best = .r
            else
                removeObject: .cand
            endif
        endfor
    else
        selectObject: .src
        .id = Copy: "freeze_viz"
    endif
endproc

# Round tick step (1 / 2 / 5 x 10^k), about 4-10 ticks
procedure sfNiceStep: .range
    .step = 10 ^ floor (log10 (max (.range, 1e-6) / 4))
    if .range / .step > 15
        .step = .step * 5
    elsif .range / .step > 7
        .step = .step * 2
    endif
endproc

# Text for the Picture window: neutralise Praat's style characters
procedure sfEsc: .s$
    .s$ = replace$ (.s$, "\", "\bs", 0)
    .s$ = replace$ (.s$, "_", "\_ ", 0)
    .s$ = replace$ (.s$, "%", "\% ", 0)
    .s$ = replace$ (.s$, "^", "\^ ", 0)
    .s$ = replace$ (.s$, "#", "\# ", 0)
endproc

# Waypoint colour (Okabe-Ito, cycling) and a light tint of it
procedure sfColour: .w
    .k = ((.w - 1) mod 8) + 1
    .c$ = "{" + fixed$ (vColR# [.k], 2) + ", " + fixed$ (vColG# [.k], 2) + ", " + fixed$ (vColB# [.k], 2) + "}"
endproc

procedure sfTint: .w, .amount
    .k = ((.w - 1) mod 8) + 1
    .r = vColR# [.k] + (1 - vColR# [.k]) * .amount
    .g = vColG# [.k] + (1 - vColG# [.k]) * .amount
    .b = vColB# [.k] + (1 - vColB# [.k]) * .amount
    .c$ = "{" + fixed$ (.r, 2) + ", " + fixed$ (.g, 2) + ", " + fixed$ (.b, 2) + "}"
endproc

# Note name safe for the Picture window ("#" is a style character there)
procedure sfNote: .hz
    @noteName: .hz
    .pic$ = replace$ (noteName.name$, "#", "\# ", 0)
    if .hz <= 0
        .pic$ = "-"
    endif
endproc

# Which waypoint(s) sound at output time t, as spectral_freeze.py decides:
# .a = current state, .b = next state, .blend = 0..1 crossfade position
procedure sfStateAt: .t
    if freeze_mode = 1
        .a = 1
        .b = 1
        .blend = 0
    else
        if loop
            .tl = .t - floor (.t / vOnePass) * vOnePass
        else
            .tl = min (.t, vOnePass)
        endif
        .cursor = 0
        .found = 0
        .a = vizN
        .b = vizN
        .blend = 0
        .w = 1
        while .found = 0 and .w <= vizN
            if .tl < .cursor + dwell_s
                .a = .w
                .b = .w
                .blend = 0
                .found = 1
            else
                .cursor += dwell_s
                if .w < vizN or loop
                    if .tl < .cursor + vEffX
                        .a = .w
                        .b = (.w mod vizN) + 1
                        .u = (.tl - .cursor) / max (vEffX, 1e-9)
                        .blend = 0.5 - 0.5 * cos (pi * .u)
                        .found = 1
                    else
                        .cursor += vEffX
                    endif
                endif
            endif
            .w += 1
        endwhile
    endif
endproc

# ---- PITCH-AWARE FREEZE POINT SELECTION (v3.4) ----
# Scores every 10-ms frame whose capture region (the FFT frame centred on t
# plus the second frame one hop later, i.e. t - W/2 .. t + 3W/4) is:
#   voiced throughout, steady in F0, harmonic (HNR), free of onsets
#   (positive log-spectral flux), and not near the noise floor.
# Picks the best-scoring moments greedily, keeping them apart in time and,
# when possible, at least 1 semitone apart in pitch; returns them sorted
# in original chronological order.
procedure selectTonalFreezePoints: .nWanted, .winS
    .nFound = 0
    .msg$ = ""
    .time# = zero# (1)
    .hz# = zero# (1)
    .score# = zero# (1)
    .pitchFloor = 75
    .pitchCeiling = 800
    .step = 0.01
    .minScore = 0.05

    selectObject: sound
    if nChannels > 1
        .ana = Convert to mono
    else
        .ana = Copy: "freeze_ana"
    endif

    selectObject: .ana
    .pitch = To Pitch: .step, .pitchFloor, .pitchCeiling
    selectObject: .ana
    .harm = To Harmonicity (cc): .step, .pitchFloor, 0.1, 1.0
    selectObject: .ana
    .int = To Intensity: .pitchFloor, .step, "yes"
    .intMax = Get maximum: 0, 0, "Parabolic"

    # Spectral flux from a coarse log spectrogram (floor 70 dB below peak)
    selectObject: .ana
    .spec = To Spectrogram: 0.025, 5000, .step, 50, "Gaussian"
    .mat = To Matrix
    .pmax = Get maximum
    .pfloor = .pmax * 1e-7
    if .pfloor <= 0
        .pfloor = 1e-20
    endif
    Formula: "10 * log10 (max (self, " + string$ (.pfloor) + "))"
    .lp## = Get all values
    .mx1 = Get x of column: 1
    .mdx = Get column distance
    .nCols = Get number of columns
    .nRows = Get number of rows
    removeObject: .spec, .mat

    .colFlux# = zero# (.nCols)
    for .ic from 2 to .nCols
        .s = 0
        for .ir to .nRows
            .d = .lp## [.ir, .ic] - .lp## [.ir, .ic - 1]
            if .d > 0
                .s += .d
            endif
        endfor
        .colFlux# [.ic] = .s / .nRows
    endfor

    # Per-frame descriptors on the pitch grid
    selectObject: .pitch
    .nF = Get number of frames
    .t# = zero# (.nF)
    .st# = zero# (.nF)
    .voiced# = zero# (.nF)
    .hnr# = zero# (.nF)
    .db# = zero# (.nF)
    .flux# = zero# (.nF)
    .nVoiced = 0
    for .i to .nF
        selectObject: .pitch
        .t = Get time from frame number: .i
        .t# [.i] = .t
        .f = Get value in frame: .i, "Hertz"
        if .f <> undefined
            .voiced# [.i] = 1
            .st# [.i] = 12 * log2 (.f / 100)
            .nVoiced += 1
        endif
        selectObject: .harm
        .h = Get value at time: .t, "linear"
        if .h = undefined
            .h = 0
        endif
        .hnr# [.i] = max (.h, 0)
        selectObject: .int
        .v = Get value at time: .t, "linear"
        if .v = undefined
            .v = .intMax - 100
        endif
        .db# [.i] = .v
        .col = round ((.t - .mx1) / .mdx) + 1
        .col = max (1, min (.nCols, .col))
        .flux# [.i] = .colFlux# [.col]
    endfor

    if .nVoiced < 3
        removeObject: .ana, .pitch, .harm, .int
        .msg$ = "almost no voiced frames found"
    else
        # Flux reference = median flux over voiced frames
        .vf# = zero# (.nVoiced)
        .k = 0
        for .i to .nF
            if .voiced# [.i]
                .k += 1
                .vf# [.k] = .flux# [.i]
            endif
        endfor
        .vf# = sort# (.vf#)
        .fluxRef = .vf# [round ((.nVoiced + 1) / 2)]
        if .fluxRef <= 0
            .fluxRef = mean (.vf#) + 1e-9
        endif

        # Score every frame
        .left = max (1, round (.winS * 0.5 / .step))
        .right = max (1, round (.winS * 0.75 / .step))
        .cScore# = zero# (.nF)
        .cSt# = zero# (.nF)
        for .i from 1 + .left to .nF - .right
            .nv = 0
            .stMin = 1e9
            .stMax = -1e9
            .stSum = 0
            .hSum = 0
            .fMax = 0
            .dbMin = 1e9
            for .j from .i - .left to .i + .right
                if .voiced# [.j]
                    .nv += 1
                    .stMin = min (.stMin, .st# [.j])
                    .stMax = max (.stMax, .st# [.j])
                    .stSum += .st# [.j]
                endif
                .hSum += .hnr# [.j]
                .fMax = max (.fMax, .flux# [.j])
                .dbMin = min (.dbMin, .db# [.j])
            endfor
            .nTot = .left + .right + 1
            if .nv >= 0.9 * .nTot
                .sStab = exp (- (.stMax - .stMin) / 0.6)
                .sHnr = max (0, min (1, (.hSum / .nTot) / 20))
                .sFlux = 1 / (1 + (.fMax / .fluxRef) ^ 2)
                .sLev = max (0, min (1, (.dbMin - (.intMax - 35)) / 20))
                .cScore# [.i] = .sStab * .sHnr * .sFlux * .sLev
                .cSt# [.i] = .stSum / .nv
            endif
        endfor

        # Greedy pick with relaxation passes
        .minSep = max (0.15, .winS)
        .pickIdx# = zero# (.nWanted)
        for .pass to 4
            if .pass = 1
                .pitchSep = 1.0
                .sep = .minSep
            elsif .pass = 2
                .pitchSep = 0.5
                .sep = .minSep
            elsif .pass = 3
                .pitchSep = 0
                .sep = .minSep
            else
                .pitchSep = 0
                .sep = .winS * 0.5
            endif
            .searching = 1
            while .searching and .nFound < .nWanted
                .best = 0
                .bestScore = .minScore
                for .i to .nF
                    if .cScore# [.i] > .bestScore
                        .ok = 1
                        for .p to .nFound
                            .q = .pickIdx# [.p]
                            if abs (.t# [.i] - .t# [.q]) < .sep
                                .ok = 0
                            elsif abs (.cSt# [.i] - .cSt# [.q]) < .pitchSep
                                .ok = 0
                            endif
                        endfor
                        if .ok
                            .best = .i
                            .bestScore = .cScore# [.i]
                        endif
                    endif
                endfor
                if .best > 0
                    .nFound += 1
                    .pickIdx# [.nFound] = .best
                else
                    .searching = 0
                endif
            endwhile
        endfor

        if .nFound > 0
            # Restore chronological order (insertion sort on frame index)
            for .a from 2 to .nFound
                .key = .pickIdx# [.a]
                .b = .a - 1
                while .b >= 1 and .pickIdx# [.b] > .key
                    .pickIdx# [.b + 1] = .pickIdx# [.b]
                    .b -= 1
                endwhile
                .pickIdx# [.b + 1] = .key
            endfor
            .time# = zero# (.nFound)
            .hz# = zero# (.nFound)
            .score# = zero# (.nFound)
            for .p to .nFound
                .q = .pickIdx# [.p]
                .time# [.p] = .t# [.q]
                .hz# [.p] = 100 * 2 ^ (.cSt# [.q] / 12)
                .score# [.p] = .cScore# [.q]
            endfor
        endif

        removeObject: .ana, .pitch, .harm, .int
    endif
endproc

@cleanUpTempFiles

# ---- GET INPUT STATS ----
selectObject: sound
totalDuration = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# ===========================================================================
# STAGE 0 — Python Probe (file-based, runs before form)
# ===========================================================================

if windows
    nCandidates = 4
    candidate1$ = "python"
    candidate2$ = "py"
    candidate3$ = "py -3"
    candidate4$ = "python3"
else
    nCandidates = 3
    candidate1$ = "python3"
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = ""
endif

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

pythonCmd$ = ""
for iCand from 1 to nCandidates
    if iCand = 1
        tryCmd$ = candidate1$
    elsif iCand = 2
        tryCmd$ = candidate2$
    elsif iCand = 3
        tryCmd$ = candidate3$
    else
        tryCmd$ = candidate4$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python with numpy and soundfile." + newline$
        ... + "Install Python 3 and run:  pip install numpy soundfile"
endif

# ---- FORM ----
form Spectral Freeze v3.6
    optionmenu Preset: 1
        option Custom
        option Drone (static, pure)
        option Pad (soft breathing)
        option Shimmer (lively, unstable)
        option Long fade (cinematic)
        option Evolving Landscape (multi-freeze)
        option Vowel Drift (multi-freeze)
        option Frozen Spectral Loop (multi-freeze)
    optionmenu Freeze_mode: 1
        option Single freeze point
        option Multi-freeze (evolving texture)
    real Freeze_time_s 0.5
    integer Number_of_freeze_points 4
    optionmenu Freeze_point_selection: 1
        option Equally spaced (original)
        option Pitch-aware (stable tonal moments)
    real Crossfade_s 2.0
    real Dwell_s 1.5
    boolean Loop 0
    positive Duration_s 8.0
    positive Window_ms 80.0
    real Shimmer 0.15
    optionmenu Phase: 1
        option Random (diffuse)
        option Coherent (tonal)
    real Fade_in_s 0.5
    real Fade_out_s 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
presetName$ = "Custom"
if preset = 2
    window_ms  = 120
    shimmer    = 0.0
    fade_in_s  = 0.1
    fade_out_s = 0.5
    freeze_mode = 1
    phase = 2
    presetName$ = "Drone"
elsif preset = 3
    window_ms  = 80
    shimmer    = 0.15
    fade_in_s  = 0.5
    fade_out_s = 1.0
    freeze_mode = 1
    phase = 1
    presetName$ = "Pad"
elsif preset = 4
    window_ms  = 40
    shimmer    = 0.4
    fade_in_s  = 0.1
    fade_out_s = 0.5
    freeze_mode = 1
    phase = 1
    presetName$ = "Shimmer"
elsif preset = 5
    window_ms  = 100
    shimmer    = 0.1
    fade_in_s  = 2.0
    fade_out_s = 3.0
    freeze_mode = 1
    phase = 2
    presetName$ = "LongFade"
elsif preset = 6
    window_ms  = 100
    shimmer    = 0.12
    fade_in_s  = 1.0
    fade_out_s = 2.0
    freeze_mode = 2
    number_of_freeze_points = 5
    crossfade_s = 3.0
    dwell_s = 2.0
    loop = 0
    duration_s = 20.0
    phase = 1
    presetName$ = "EvolvingLandscape"
elsif preset = 7
    window_ms  = 60
    shimmer    = 0.18
    fade_in_s  = 0.5
    fade_out_s = 1.0
    freeze_mode = 2
    number_of_freeze_points = 6
    crossfade_s = 1.5
    dwell_s = 0.8
    loop = 0
    duration_s = 12.0
    phase = 1
    presetName$ = "VowelDrift"
elsif preset = 8
    window_ms  = 80
    shimmer    = 0.08
    fade_in_s  = 0.3
    fade_out_s = 0.3
    freeze_mode = 2
    number_of_freeze_points = 3
    crossfade_s = 2.5
    dwell_s = 1.0
    loop = 1
    duration_s = 15.0
    phase = 1
    presetName$ = "FrozenSpectralLoop"
endif

# ---- CLAMP PARAMETERS ----
if freeze_time_s < 0
    freeze_time_s = 0
endif
if freeze_time_s > totalDuration
    freeze_time_s = totalDuration
endif
if number_of_freeze_points < 2
    number_of_freeze_points = 2
endif
if number_of_freeze_points > 20
    number_of_freeze_points = 20
endif
if crossfade_s < 0.1
    crossfade_s = 0.1
endif
if dwell_s < 0
    dwell_s = 0
endif
if shimmer < 0
    shimmer = 0
endif
if shimmer > 1
    shimmer = 1
endif
if fade_in_s < 0
    fade_in_s = 0
endif
if fade_out_s < 0
    fade_out_s = 0
endif

# Python rounds the requested analysis window up to a power of two.
requestedWindowSamples = round(window_ms / 1000 * sr)
if requestedWindowSamples < 1
    requestedWindowSamples = 1
endif
fftSamples = 64
while fftSamples < requestedWindowSamples
    fftSamples = fftSamples * 2
endwhile
effectiveWindowMs = 1000 * fftSamples / sr

# ---- BUILD FREEZE TIMES STRING (multi mode) ----
freezeTimesStr$ = ""
nFP = number_of_freeze_points
selectionLabel$ = "Single point"

if freeze_mode = 2
    margin = totalDuration * 0.05
    if margin > 0.5
        margin = 0.5
    endif
    rangeStart = margin
    rangeEnd   = totalDuration - margin
    if rangeEnd <= rangeStart
        rangeStart = 0
        rangeEnd   = totalDuration
    endif
    span = rangeEnd - rangeStart

    # Equally spaced (v3.3) — always computed; also the pitch-aware fallback
    fpTime# = zero# (nFP)
    fpHz# = zero# (nFP)
    for fp from 1 to nFP
        fpTime# [fp] = rangeStart + (fp - 1) * span / (nFP - 1)
    endfor

    selectionLabel$ = "Equally spaced"
    if freeze_point_selection = 2
        @selectTonalFreezePoints: nFP, effectiveWindowMs / 1000
        if selectTonalFreezePoints.nFound >= 2
            nFP = selectTonalFreezePoints.nFound
            fpTime# = selectTonalFreezePoints.time#
            fpHz# = selectTonalFreezePoints.hz#
            selectionLabel$ = "Pitch-aware"
        else
            selectionLabel$ = "Pitch-aware -> fallback (equal)"
        endif
    endif

    for fp from 1 to nFP
        if fp > 1
            freezeTimesStr$ = freezeTimesStr$ + ","
        endif
        freezeTimesStr$ = freezeTimesStr$ + fixed$(fpTime# [fp], 4)
    endfor
endif

# ---- MODE LABEL ----
if freeze_mode = 1
    modeLabel$ = "Single"
else
    modeLabel$ = "Multi (" + string$(nFP) + " points)"
endif

# ---- PHASE MODE ----
if phase = 2
    phaseMode$ = "coherent"
else
    phaseMode$ = "random"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Freeze v3.6 ==="
appendInfoLine: "Input: ", soundName$, "  (", fixed$(totalDuration, 3), "s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode:   ", modeLabel$
appendInfoLine: ""
if freeze_mode = 1
    appendInfoLine: "Freeze at:   ", fixed$(freeze_time_s, 3), " s"
else
    appendInfoLine: "Selection:   ", selectionLabel$
    if freeze_point_selection = 2
        if selectTonalFreezePoints.msg$ <> ""
            appendInfoLine: "  NOTE: ", selectTonalFreezePoints.msg$
        endif
        if selectTonalFreezePoints.nFound >= 2
            if nFP < number_of_freeze_points
                appendInfoLine: "  NOTE: only ", nFP, " stable tonal moments found (", number_of_freeze_points, " requested)."
            endif
            for fp from 1 to nFP
                @noteName: fpHz# [fp]
                appendInfoLine: "  ", fp, ":  ", fixed$ (fpTime# [fp], 3), " s   ", fixed$ (fpHz# [fp], 1), " Hz  (", noteName.name$, ")   score ", fixed$ (selectTonalFreezePoints.score# [fp], 3)
            endfor
        else
            appendInfoLine: "  NOTE: fewer than 2 stable tonal moments; using equal spacing."
        endif
    endif
    appendInfoLine: "Freeze pts:  ", freezeTimesStr$
    appendInfoLine: "Crossfade:   ", fixed$(crossfade_s, 2), " s"
    appendInfoLine: "Dwell:       ", fixed$(dwell_s, 2), " s"
    appendInfoLine: "Loop:        ", string$(loop)
    if loop = 0
        onePassDur = nFP * dwell_s + (nFP - 1) * crossfade_s
        if duration_s < onePassDur - 0.01
            appendInfoLine: "  NOTE: Duration (", fixed$(duration_s, 1), "s) < one pass (", fixed$(onePassDur, 1), "s); later waypoints not reached."
        endif
    endif
endif
appendInfoLine: "Duration:    ", fixed$(duration_s, 2), " s"
appendInfoLine: "Window:      requested ", fixed$(window_ms, 1), " ms  |  FFT ", fftSamples, " samples = ", fixed$(effectiveWindowMs, 1), " ms"
appendInfoLine: "Shimmer:     ", fixed$(shimmer, 2)
appendInfoLine: "Phase:       ", phaseMode$
appendInfoLine: "Fades:       in ", fixed$(fade_in_s, 2), " s  out ", fixed$(fade_out_s, 2), " s"
appendInfoLine: "Python:      ", pythonCmd$
appendInfoLine: ""

# ===========================================================================
# STAGE 1 — Export WAV
# ===========================================================================
appendInfoLine: "[1/4] Exporting WAV..."
selectObject: sound
Save as WAV file: tempInput$

# ===========================================================================
# STAGE 2 — Call Python
# ===========================================================================
appendInfoLine: "[2/4] Running spectral freeze engine..."

if freeze_mode = 1
    runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """"
        ... + " """ + tempInputJ$ + """"
        ... + " """ + tempOutputJ$ + """"
        ... + " " + fixed$(freeze_time_s, 6)
        ... + " " + fixed$(duration_s, 4)
        ... + " " + fixed$(window_ms, 2)
        ... + " " + fixed$(shimmer, 4)
        ... + " " + fixed$(fade_in_s, 4)
        ... + " " + fixed$(fade_out_s, 4)
        ... + " single"
        ... + " " + phaseMode$
        ... + " > """ + tempLogJ$ + """ 2>&1"
else
    runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """"
        ... + " """ + tempInputJ$ + """"
        ... + " """ + tempOutputJ$ + """"
        ... + " " + freezeTimesStr$
        ... + " " + fixed$(duration_s, 4)
        ... + " " + fixed$(window_ms, 2)
        ... + " " + fixed$(shimmer, 4)
        ... + " " + fixed$(fade_in_s, 4)
        ... + " " + fixed$(fade_out_s, 4)
        ... + " multi"
        ... + " " + fixed$(crossfade_s, 4)
        ... + " " + fixed$(dwell_s, 4)
        ... + " " + string$(loop)
        ... + " " + phaseMode$
        ... + " > """ + tempLogJ$ + """ 2>&1"
endif

# ===========================================================================
# STAGE 3 — Verify & Import
# ===========================================================================
if not fileReadable(tempOutput$)
    pyErr$ = ""
    if fileReadable(tempLog$)
        pyErr$ = readFile$(tempLog$)
    endif
    if pyErr$ = ""
        pyErr$ = "(no Python output captured)"
    endif
    @cleanUpTempFiles
    exitScript: "Python spectral freeze failed." + newline$ + newline$ + pyErr$
endif

appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
if freeze_mode = 1
    Rename: soundName$ + "_freeze"
else
    Rename: soundName$ + "_multiFreeze"
endif
resultSound = selected("Sound")

# ---- RESULT STATS ----
selectObject: resultSound
durOut = Get total duration
nChannelsOut = Get number of channels
rms_out = Get root-mean-square: 0, 0

selectObject: sound
rms_orig = Get root-mean-square: 0, 0

###############################################################################
# VISUALIZATION — the freeze process on one 8-inch page
#   A  Source       spectrogram + F0 contour; the captured moments
#   B  Capture -> hold   each moment is routed to its place in the output
#   C  Output form  state gains over output time (as the engine computes them)
#   D  Result       output spectrogram on the same output time axis
#   E  Frozen spectra   the exact frame captured at each waypoint
#   + summary strip
# Waypoint colours link every panel. Source panels use source time;
# C and D use output time.
###############################################################################

if draw_visualization
    appendInfoLine: "[4/4] Creating visualization..."

    # ---- display channels (strongest RMS; processing keeps all channels) ----
    @sfStrongestChannel: sound, nChannels
    monoInViz = sfStrongestChannel.id
    @sfStrongestChannel: resultSound, nChannelsOut
    monoOutViz = sfStrongestChannel.id

    # ---- waypoints shown ----
    if freeze_mode = 1
        vizN = 1
        vizTime# = zero# (1)
        vizHz# = zero# (1)
        vizTime# [1] = freeze_time_s
    else
        vizN = nFP
        vizTime# = fpTime#
        vizHz# = fpHz#
    endif

    # ---- source pitch (same search range as the selection) ----
    selectObject: monoInViz
    vPitch = To Pitch: 0.01, 75, 800
    vNPF = Get number of frames
    vPT# = zero# (vNPF)
    vPM# = zero# (vNPF)
    vMidiLo = 200
    vMidiHi = -100
    for vI to vNPF
        vPT# [vI] = Get time from frame number: vI
        vF = Get value in frame: vI, "Hertz"
        if vF <> undefined
            vPM# [vI] = 69 + 12 * log2 (vF / 440)
            vMidiLo = min (vMidiLo, vPM# [vI])
            vMidiHi = max (vMidiHi, vPM# [vI])
        endif
    endfor
    vMedF0 = Get quantile: 0, 0, 0.5, "Hertz"

    # Equal spacing / single: read the pitch at the marker (nearest voiced
    # frame within 40 ms) so every waypoint can be named when it is voiced.
    for vW to vizN
        if vizHz# [vW] <= 0
            vBest = 0.04
            for vI to vNPF
                if vPM# [vI] > 0 and abs (vPT# [vI] - vizTime# [vW]) < vBest
                    vBest = abs (vPT# [vI] - vizTime# [vW])
                    vizHz# [vW] = 440 * 2 ^ ((vPM# [vI] - 69) / 12)
                endif
            endfor
        endif
        if vizHz# [vW] > 0
            vM = 69 + 12 * log2 (vizHz# [vW] / 440)
            vMidiLo = min (vMidiLo, vM)
            vMidiHi = max (vMidiHi, vM)
        endif
    endfor
    if vMidiHi < vMidiLo
        vMidiLo = 48
        vMidiHi = 72
    endif
    vMidiLo = floor (vMidiLo) - 2
    vMidiHi = ceiling (vMidiHi) + 5
    if vMidiHi - vMidiLo < 12
        vMid = (vMidiLo + vMidiHi) / 2
        vMidiLo = round (vMid - 6)
        vMidiHi = round (vMid + 6)
    endif

    # Frequency range: enough harmonics of the voice to read them
    vNyq = sr / 2
    if vMedF0 = undefined
        vFmax = 5000
    else
        vFmax = max (1500, min (5000, 12 * vMedF0))
    endif
    vFmax = min (vFmax, vNyq)
    vFmax = 500 * ceiling (vFmax / 500)
    vFmax = min (vFmax, vNyq)

    # ---- waypoint colours (Okabe-Ito, cycling) ----
    vColR# = {0.00, 0.84, 0.00, 0.80, 0.90, 0.34, 0.55, 0.35}
    vColG# = {0.45, 0.37, 0.62, 0.47, 0.62, 0.71, 0.40, 0.35}
    vColB# = {0.70, 0.00, 0.45, 0.65, 0.00, 0.91, 0.20, 0.35}

    # ---- output timeline (mirrors spectral_freeze.py) ----
    vEffX = crossfade_s
    if freeze_mode = 1
        vOnePass = durOut
    else
        if loop
            vOnePass = vizN * dwell_s + vizN * vEffX
        else
            vOnePass = vizN * dwell_s + (vizN - 1) * vEffX
        endif
        if vOnePass <= 0
            vOnePass = duration_s
        endif
    endif

    # ---- time ticks ----
    @sfNiceStep: totalDuration
    vSrcStep = sfNiceStep.step
    @sfNiceStep: durOut
    vOutStep = sfNiceStep.step

    @sfEsc: soundName$
    vName$ = sfEsc.s$

    Erase all
    Line width: 1
    Colour: "Black"
    Solid line

    # ======================= TITLE =========================================
    Select inner viewport: 0.6, 7.7, 0.10, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Text: 0.5, "centre", 0.75, "half", "##Spectral Freeze##   " + vName$
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if freeze_mode = 1
        vSub$ = "Single freeze at " + fixed$ (freeze_time_s, 3) + " s"
    else
        vSub$ = "Multi-freeze  |  " + string$ (vizN) + " waypoints  |  " + selectionLabel$
    endif
    vSub$ = vSub$ + "  |  " + phaseMode$ + " phase  |  FFT " + fixed$ (effectiveWindowMs, 1) + " ms  |  " + presetName$
    Text: 0.5, "centre", 0.15, "half", vSub$
    Colour: "Black"

    # ======================= A1 SOURCE SPECTROGRAM =========================
    vY1 = 0.85
    vY2 = 1.90
    selectObject: monoInViz
    vSpec = To Spectrogram: 0.03, vFmax, max (0.002, totalDuration / 1500), 20, "Gaussian"
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Paint: 0, totalDuration, 0, vFmax, 100, "yes", 50, 6, 0, "no"
    removeObject: vSpec
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, totalDuration, 0, vFmax
    # capture region = FFT frame centred on t plus the second frame one hop later
    Line width: 2
    for vW to vizN
        @sfColour: vW
        Colour: sfColour.c$
        vA = max (0, vizTime# [vW] - effectiveWindowMs / 2000)
        vB = min (totalDuration, vizTime# [vW] + 3 * effectiveWindowMs / 4000)
        Draw rectangle: vA, vB, 0, vFmax
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left every: 1, 1000, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "##A  Source##   spectrogram; coloured frames = the exact regions captured (FFT frame + one hop)"

    # ======================= A2 SOURCE PITCH ===============================
    vY1 = 2.18
    vY2 = 2.98
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, totalDuration, vMidiLo, vMidiHi
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, totalDuration, vMidiLo, vMidiHi
    for vW to vizN
        @sfColour: vW
        @sfTint: vW, 0.80
        vA = max (0, vizTime# [vW] - effectiveWindowMs / 2000)
        vB = min (totalDuration, vizTime# [vW] + 3 * effectiveWindowMs / 4000)
        Paint rectangle: sfTint.c$, vA, vB, vMidiLo, vMidiHi
    endfor
    # octave / fifth grid
    Colour: "{0.88, 0.88, 0.88}"
    for vM from ceiling (vMidiLo) to floor (vMidiHi)
        if vM mod 12 = 0 or vM mod 12 = 7
            Draw line: 0, vM, totalDuration, vM
        endif
    endfor
    # F0 contour (voiced runs only)
    Colour: "{0.30, 0.30, 0.30}"
    Line width: 1.5
    for vI from 2 to vNPF
        if vPM# [vI] > 0 and vPM# [vI - 1] > 0
            Draw line: vPT# [vI - 1], vPM# [vI - 1], vPT# [vI], vPM# [vI]
        endif
    endfor
    Line width: 1
    # captured pitches
    for vW to vizN
        @sfColour: vW
        @sfNote: vizHz# [vW]
        if vizHz# [vW] > 0
            vM = 69 + 12 * log2 (vizHz# [vW] / 440)
            Paint circle: sfColour.c$, vizTime# [vW], vM, totalDuration * 0.006
            Colour: sfColour.c$
            Font size: 7
            Text: vizTime# [vW], "centre", vMidiHi - 0.10 * (vMidiHi - vMidiLo), "half", "##" + string$ (vW) + "## " + sfNote.pic$
        else
            Colour: sfColour.c$
            Font size: 7
            Text: vizTime# [vW], "centre", vMidiHi - 0.10 * (vMidiHi - vMidiLo), "half", "##" + string$ (vW) + "## unvoiced"
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    for vM from ceiling (vMidiLo + 0.5) to floor (vMidiHi - 0.5)
        if vM mod 12 = 0 or vM mod 12 = 7
            @sfNote: 440 * 2 ^ ((vM - 69) / 12)
            One mark left: vM, "no", "yes", "no", sfNote.pic$
        endif
    endfor
    Marks bottom every: 1, vSrcStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Pitch"
    Text bottom: "yes", "Source time (s)"
    if freeze_mode = 2 and selectionLabel$ = "Pitch-aware"
        Text top: "no", "F0 contour (grey) and the pitch of each captured moment: chosen where F0 is steady, harmonic and free of onsets"
    else
        Text top: "no", "F0 contour (grey) and the pitch found at each captured moment"
    endif

    # ======================= B CAPTURE -> HOLD MAPPING =====================
    vY1 = 3.60
    vY2 = 4.05
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, 1, 0, 1
    Colour: "{0.75, 0.75, 0.75}"
    Line width: 3
    Draw line: 0, 1, 1, 1
    Draw line: 0, 0, 1, 0
    Line width: 1.5
    vNotReached = 0
    for vW to vizN
        @sfColour: vW
        Colour: sfColour.c$
        if freeze_mode = 1
            vCentre = durOut / 2
        else
            vCentre = (vW - 1) * (dwell_s + vEffX) + dwell_s / 2
        endif
        vXs = vizTime# [vW] / totalDuration
        if vCentre <= durOut
            vXo = vCentre / durOut
            Draw line: vXs, 1, vXo, 0
            Paint circle: sfColour.c$, vXo, 0, 0.004
        else
            vNotReached += 1
            Dotted line
            Draw line: vXs, 1, 1, 0.35
            Solid line
        endif
        Paint circle: sfColour.c$, vXs, 1, 0.004
    endfor
    Line width: 1
    Colour: "{0.40, 0.40, 0.40}"
    Font size: 6
    Text: -0.005, "right", 1, "half", "source"
    Text: -0.005, "right", 0, "half", "output"
    Colour: "Black"
    Font size: 7
    vCap$ = "##B  Capture → hold##   each captured moment becomes a sustained state in the output"
    if vNotReached > 0
        vCap$ = vCap$ + "  (" + string$ (vNotReached) + " not reached: Duration too short)"
    endif
    Text top: "no", vCap$

    # ======================= C OUTPUT FORM (state gains) ===================
    vY1 = 4.40
    vY2 = 5.15
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, durOut, 0, 1.25
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, durOut, 0, 1.25
    Colour: "{0.88, 0.88, 0.88}"
    Draw line: 0, 1, durOut, 1
    vNS = 600
    vPrevW# = zero# (vizN)
    Line width: 2
    for vK from 0 to vNS
        vT = vK * durOut / vNS
        @sfStateAt: vT
        for vW to vizN
            vG = 0
            if vW = sfStateAt.a
                vG = sqrt (1 - sfStateAt.blend)
            endif
            if vW = sfStateAt.b and sfStateAt.b <> sfStateAt.a
                vG = sqrt (sfStateAt.blend)
            endif
            if vK > 0 and (vG > 0 or vPrevW# [vW] > 0)
                @sfColour: vW
                Colour: sfColour.c$
                Draw line: vPrevT, vPrevW# [vW], vT, vG
            endif
            vPrevW# [vW] = vG
        endfor
        vPrevT = vT
    endfor
    Line width: 1
    # overall fades
    Colour: "{0.25, 0.25, 0.25}"
    Dashed line
    vFi = min (fade_in_s, durOut)
    vFo = min (fade_out_s, durOut)
    Draw line: 0, 0, vFi, 1
    Draw line: vFi, 1, durOut - vFo, 1
    Draw line: durOut - vFo, 1, durOut, 0
    Solid line
    # state labels over each hold
    Font size: 6
    if freeze_mode = 1
        @sfNote: vizHz# [1]
        @sfColour: 1
        Colour: sfColour.c$
        Text: durOut / 2, "centre", 1.12, "half", "##1## " + sfNote.pic$
    else
        vCyc = 0
        vStart = 0
        while vStart < durOut and vCyc < 50
            for vW to vizN
                vT0 = vStart + (vW - 1) * (dwell_s + vEffX)
                if vT0 < durOut and (vW < vizN or loop)
                    vT1 = vT0 + dwell_s
                else
                    vT1 = durOut
                endif
                vT1 = min (vT1, durOut)
                if vT0 < durOut and vT1 - vT0 > 0.035 * durOut
                    @sfNote: vizHz# [vW]
                    @sfColour: vW
                    Colour: sfColour.c$
                    Text: (vT0 + vT1) / 2, "centre", 1.12, "half", "##" + string$ (vW) + "## " + sfNote.pic$
                endif
            endfor
            vCyc += 1
            if loop
                vStart += vOnePass
            else
                vStart = durOut
            endif
        endwhile
    endif
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Gain"
    if freeze_mode = 1
        Text top: "no", "##C  Output form##   one sustained state; dashed = fade in / out"
    else
        vLoop$ = ""
        if loop
            vLoop$ = ", looping"
        endif
        Text top: "no", "##C  Output form##   hold " + fixed$ (dwell_s, 2) + " s, equal-power crossfade " + fixed$ (crossfade_s, 2) + " s" + vLoop$ + "; dashed = fade in / out"
    endif

    # ======================= D RESULT SPECTROGRAM ==========================
    vY1 = 5.55
    vY2 = 6.50
    selectObject: monoOutViz
    vSpec = To Spectrogram: 0.03, vFmax, max (0.002, durOut / 1500), 20, "Gaussian"
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Paint: 0, durOut, 0, vFmax, 100, "yes", 50, 6, 0, "no"
    removeObject: vSpec
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, durOut, 0, vFmax
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left every: 1, 1000, "yes", "yes", "no"
    Marks bottom every: 1, vOutStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Output time (s)"
    Text top: "no", "##D  Result##   spectrogram of the frozen output (same frequency range as A)"

    # ======================= E FROZEN SPECTRA ==============================
    vNE = min (vizN, 6)
    vGap = 0.18
    vPW = (7.1 - (vNE - 1) * vGap) / vNE
    vY1 = 7.10
    vY2 = 7.80
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, 1, 0, 1
    Font size: 7
    vECap$ = "##E  Frozen spectra##   the frame captured at each waypoint (dB, common scale)"
    if vizN > 6
        vECap$ = vECap$ + "  |  first 6 of " + string$ (vizN)
    endif
    Text top: "no", vECap$
    vHalf = effectiveWindowMs / 2000
    vLtasMax = -1e9
    for vW to vNE
        selectObject: monoInViz
        vT0 = max (0, vizTime# [vW] - vHalf)
        vT1 = min (totalDuration, vizTime# [vW] + vHalf)
        vPart = Extract part: vT0, vT1, "Hanning", 1, "no"
        vSpc = To Spectrum: "yes"
        vLtas [vW] = To Ltas (1-to-1)
        vMx = Get maximum: 0, vFmax, "None"
        vLtasMax = max (vLtasMax, vMx)
        removeObject: vPart, vSpc
    endfor
    for vW to vNE
        vX1 = 0.6 + (vW - 1) * (vPW + vGap)
        Select inner viewport: vX1, vX1 + vPW, vY1, vY2
        Axes: 0, vFmax, vLtasMax - 60, vLtasMax + 3
        Paint rectangle: "{0.985, 0.985, 0.985}", 0, vFmax, vLtasMax - 60, vLtasMax + 3
        selectObject: vLtas [vW]
        @sfColour: vW
        Colour: sfColour.c$
        Draw: 0, vFmax, vLtasMax - 60, vLtasMax + 3, "no", "Curve"
        Colour: "Black"
        Select inner viewport: vX1, vX1 + vPW, vY1, vY2
        Axes: 0, vFmax, vLtasMax - 60, vLtasMax + 3
        Draw inner box
        Font size: 6
        for vKHz to floor (vFmax / 1000 - 0.25)
            One mark bottom: 1000 * vKHz, "no", "yes", "no", string$ (vKHz) + "k"
        endfor
        @sfNote: vizHz# [vW]
        Colour: sfColour.c$
        Font size: 7
        Text: 0.97 * vFmax, "right", vLtasMax - 2, "top", "##" + string$ (vW) + "## " + sfNote.pic$ + "  " + fixed$ (vizTime# [vW], 2) + " s"
        Colour: "Black"
        removeObject: vLtas [vW]
    endfor
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, 1, 0, 1
    Font size: 7
    Text bottom: "yes", "Frequency (Hz)"

    # ======================= SUMMARY =======================================
    vY1 = 8.30
    vY2 = 8.80
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    if freeze_mode = 1
        vLine1$ = "##Result##  " + fixed$ (durOut, 2) + " s from one moment (" + fixed$ (freeze_time_s, 3) + " s)"
    else
        vLine1$ = "##Result##  " + fixed$ (durOut, 2) + " s from " + string$ (vizN) + " moments  |  selection: " + selectionLabel$
        if loop = 0 and durOut > vOnePass + 0.01
            vLine1$ = vLine1$ + "  |  last state held " + fixed$ (durOut - vOnePass, 2) + " s"
        endif
    endif
    vLine1$ = vLine1$ + "  |  " + phaseMode$ + " phase  |  shimmer " + fixed$ (shimmer, 2)
    Text: 0.015, "left", 0.70, "half", vLine1$
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    vLine2$ = "FFT " + string$ (fftSamples) + " samples (" + fixed$ (effectiveWindowMs, 1) + " ms)  |  fades " + fixed$ (fade_in_s, 2) + " / " + fixed$ (fade_out_s, 2) + " s"
    vLine2$ = vLine2$ + "  |  RMS " + fixed$ (rms_orig, 4) + " → " + fixed$ (rms_out, 4)
    vLine2$ = vLine2$ + "  |  channels " + string$ (nChannels) + " → " + string$ (nChannelsOut) + "  |  " + string$ (sr) + " Hz"
    Text: 0.015, "left", 0.27, "half", vLine2$
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, vY1, vY2
    Axes: 0, 1, 0, 1
    Draw inner box

    removeObject: vPitch, monoInViz, monoOutViz
    Font size: 10
    Colour: "Black"
    Line width: 1
    Select outer viewport: 0, 8, 0, 8.9
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ===========================================================================
# CLEANUP & SUMMARY
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
if freeze_mode = 1
    appendInfoLine: "Output: ", soundName$, "_freeze  (", fixed$(durOut, 2), "s)"
    appendInfoLine: "Frozen at: ", fixed$(freeze_time_s, 3), "s"
else
    appendInfoLine: "Output: ", soundName$, "_multiFreeze  (", fixed$(durOut, 2), "s)"
    appendInfoLine: "Waypoints: ", freezeTimesStr$, "  (", selectionLabel$, ")"
    appendInfoLine: "Crossfade: ", fixed$(crossfade_s, 2), "s  Dwell: ", fixed$(dwell_s, 2), "s  Loop: ", string$(loop)
endif
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "RMS original: ", fixed$(rms_orig, 6)
appendInfoLine: "RMS frozen:   ", fixed$(rms_out, 6)

selectObject: resultSound

if play_result
    Play
endif
