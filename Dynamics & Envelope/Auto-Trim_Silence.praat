# ============================================================
# Praat AudioTools - Auto-Trim Silence.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auto-Trim Silence (Start and End)
#   Finds the first-to-last "sounding" span of a Sound and extracts it,
#   with safe padding, outward-only quiet-point alignment, and short
#   edge fades.
#
# Changelog v0.6 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
# Changelog vs 0.4:
#   - Boundary alignment no longer uses "nearest zero crossing" (which
#     could move a cut point INWARD and clip already-detected audio).
#     It now searches strictly OUTWARD from each padded boundary, for
#     the quietest point across all channels, bounded by a configurable
#     maximum search distance (Zero_crossing_search_ms). If nothing
#     quieter is found, the padded boundary is kept as-is and the edge
#     fade provides the click protection. This is also multichannel-safe
#     (it looks at the loudest of all channels at each candidate time,
#     not just channel 1).
#   - Full-band RMS detection now measures each window's level relative
#     to the loudest ANALYSIS WINDOW (max window RMS), not the single
#     loudest sample in the file. This makes its threshold reference
#     much closer in meaning to the Speech-band mode's "dB below maximum
#     intensity", so a single sharp transient elsewhere in the file no
#     longer drags a quiet drone below threshold.
#   - Sounding/silence run durations now account for the fact that
#     analysis windows overlap (20 ms window, 5 ms hop): duration of N
#     consecutive windows is windowLen + (N-1)*stepLen, not N*stepLen.
#   - Processing order in Full-band mode now matches Praat's own
#     algorithm: short sounding bursts are removed FIRST, and short
#     silent gaps are bridged AFTER, not the other way around.
#   - Added input validation: negative threshold, padding, fade, or
#     zero-crossing search values are rejected with a clear message
#     instead of silently producing wrong results.
#   - The report now shows the fade actually applied (0 if skipped
#     because the output was too short, or because Edge_fade_ms was 0),
#     not just the requested value.
#   - Window count uses ceiling (not floor) so a short tail of the file
#     (less than one hop) is no longer left unanalyzed.
#
# Changelog vs 0.3: see v0.4 header history in the project repository.
# ============================================================

form Auto-Trim Silence v0.6
    optionmenu Detection_mode: 2
        option Speech-band (Praat built-in)
        option Full-band RMS (music-safe)
    comment Pitch floor is used only in Speech-band mode.
    positive Pitch_floor_Hz 100
    real Threshold_dB_below_peak 35
    positive Min_silence_duration_sec 0.1
    positive Min_sounding_duration_sec 0.02
    real Leading_padding_ms 30
    real Trailing_padding_ms 100
    real Edge_fade_ms 5
    real Zero_crossing_search_ms 10
    boolean Draw_visualization 1
    boolean Play_result 0
endform

# ------------------------------------------------------------
# Validate input
# ------------------------------------------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object from the list."
endif

if threshold_dB_below_peak < 0
    exitScript: "Threshold must be zero or greater (it represents dB below the analysis peak)."
endif

if leading_padding_ms < 0 or trailing_padding_ms < 0
    exitScript: "Padding values cannot be negative."
endif

if edge_fade_ms < 0
    exitScript: "Edge fade cannot be negative."
endif

if zero_crossing_search_ms < 0
    exitScript: "Zero-crossing search distance cannot be negative."
endif

originalSound = selected("Sound")
soundName$ = selected$("Sound")

selectObject: originalSound
soundXmin = Get start time
soundXmax = Get end time
originalDuration = soundXmax - soundXmin

startTime = -1
endTime = -1

# ------------------------------------------------------------
# Mode 1: Speech-band detection (Praat's built-in silences algorithm)
# ------------------------------------------------------------
if detection_mode = 1
    selectObject: originalSound
    tg = To TextGrid (silences): pitch_floor_Hz, 0, -threshold_dB_below_peak,
        ... min_silence_duration_sec, min_sounding_duration_sec, "silent", "sounding"

    numIntervals = Get number of intervals: 1
    for i from 1 to numIntervals
        label$ = Get label of interval: 1, i
        if label$ == "sounding"
            if startTime == -1
                startTime = Get start time of interval: 1, i
            endif
            endTime = Get end time of interval: 1, i
        endif
    endfor
    removeObject: tg

# ------------------------------------------------------------
# Mode 2: Full-band RMS detection (no filtering)
# ------------------------------------------------------------
else
    selectObject: originalSound
    windowLen = 0.02
    stepLen = 0.005
    nWindows = ceiling((originalDuration - windowLen) / stepLen) + 1
    if nWindows < 1
        nWindows = 1
    endif

    # --- Pass 1: measure RMS of every window, track the loudest window ---
    rms# = zero#(nWindows)
    maxWindowRMS = 0
    for w from 1 to nWindows
        t1 = soundXmin + (w - 1) * stepLen
        if t1 > soundXmax
            t1 = soundXmax
        endif
        t2 = t1 + windowLen
        if t2 > soundXmax
            t2 = soundXmax
        endif
        if t2 > t1
            selectObject: originalSound
            windowRMS = Get root-mean-square: t1, t2
        else
            windowRMS = 0
        endif
        rms#[w] = windowRMS
        if windowRMS > maxWindowRMS
            maxWindowRMS = windowRMS
        endif
    endfor

    if maxWindowRMS <= 0
        exitScript: "No audio detected above the threshold. The file might be entirely silent."
    endif

    # --- Pass 2: classify each window relative to the loudest window ---
    sounding# = zero#(nWindows)
    for w from 1 to nWindows
        if rms#[w] > 0
            windowDB = 20 * log10(rms#[w] / maxWindowRMS)
        else
            windowDB = -300
        endif
        if windowDB >= -threshold_dB_below_peak
            sounding#[w] = 1
        endif
    endfor

    # --- Step A: remove sounding runs shorter than the minimum sounding
    #     duration FIRST (matches Praat's own processing order) ---
    i = 1
    while i <= nWindows
        if sounding#[i] = 1
            j = i
            while j <= nWindows and sounding#[j] = 1
                j = j + 1
            endwhile
            runCount = j - i
            runDuration = windowLen + (runCount - 1) * stepLen
            if runDuration < min_sounding_duration_sec
                for k from i to j - 1
                    sounding#[k] = 0
                endfor
            endif
            i = j
        else
            i = i + 1
        endif
    endwhile

    # --- Step B: bridge silent gaps shorter than the minimum silence
    #     duration (only interior gaps; never extend past either end) ---
    i = 1
    while i <= nWindows
        if sounding#[i] = 0
            j = i
            while j <= nWindows and sounding#[j] = 0
                j = j + 1
            endwhile
            gapCount = j - i
            gapDuration = windowLen + (gapCount - 1) * stepLen
            if gapDuration < min_silence_duration_sec and i > 1 and j <= nWindows
                for k from i to j - 1
                    sounding#[k] = 1
                endfor
            endif
            i = j
        else
            i = i + 1
        endif
    endwhile

    for w from 1 to nWindows
        if sounding#[w] = 1
            if startTime == -1
                startTime = soundXmin + (w - 1) * stepLen
            endif
            windowEnd = soundXmin + (w - 1) * stepLen + windowLen
            if windowEnd > soundXmax
                windowEnd = soundXmax
            endif
            endTime = windowEnd
        endif
    endfor
endif

# ------------------------------------------------------------
# Check if the file was entirely silent
# ------------------------------------------------------------
if startTime == -1
    exitScript: "No audio detected above the threshold. The file might be entirely silent."
endif

# ------------------------------------------------------------
# Apply padding
# ------------------------------------------------------------
leadingPad = leading_padding_ms / 1000
trailingPad = trailing_padding_ms / 1000

trimStart = startTime - leadingPad
if trimStart < soundXmin
    trimStart = soundXmin
endif
trimEnd = endTime + trailingPad
if trimEnd > soundXmax
    trimEnd = soundXmax
endif

# ------------------------------------------------------------
# Outward-only quiet-point search (replaces "nearest zero crossing")
#
# Searches strictly AWAY from the detected sounding region, so the
# boundary can only move further out (more padding) and can never
# move inward into audio that was already classified as sounding.
# Looks at the loudest of ALL channels at each candidate time, so it
# is safe for stereo/multichannel material even when one channel does
# not cross zero at the same instant as another.
# ------------------------------------------------------------
procedure findQuietPoint: .startT, .direction, .maxShift
    .sr = Get sampling frequency
    .dt = 1 / .sr
    .maxSteps = round(.maxShift / .dt)
    .nch = Get number of channels
    .bestVal = 1e30
    .bestTime = .startT
    .s = 0
    while .s <= .maxSteps
        .t2 = .startT + .direction * .s * .dt
        if .t2 >= soundXmin and .t2 <= soundXmax
            .maxAbs = 0
            for .c from 1 to .nch
                .v = Get value at time: .c, .t2, "Cubic"
                .av = abs(.v)
                if .av > .maxAbs
                    .maxAbs = .av
                endif
            endfor
            if .maxAbs < .bestVal
                .bestVal = .maxAbs
                .bestTime = .t2
            endif
        endif
        .s = .s + 1
    endwhile
endproc

zeroCrossSearchSec = zero_crossing_search_ms / 1000
if zeroCrossSearchSec > 0
    selectObject: originalSound
    @findQuietPoint: trimStart, -1, zeroCrossSearchSec
    trimStart = findQuietPoint.bestTime

    selectObject: originalSound
    @findQuietPoint: trimEnd, 1, zeroCrossSearchSec
    trimEnd = findQuietPoint.bestTime
endif

if trimEnd <= trimStart
    exitScript: "Computed trim boundaries are invalid; try lowering the threshold or padding."
endif

# ------------------------------------------------------------
# Extract the trimmed audio
# ------------------------------------------------------------
selectObject: originalSound
trimmedSound = Extract part: trimStart, trimEnd, "rectangular", 1, "no"
Rename: soundName$ + "_trimmed"

selectObject: trimmedSound
outDur = Get total duration

# ------------------------------------------------------------
# Apply short local edge fades (does not affect the rest of the file)
# Tracks whether the fade was actually applied, and at what length,
# for accurate reporting.
# ------------------------------------------------------------
edgeFadeSec = edge_fade_ms / 1000
fadeApplied = 0
effectiveFadeSec = 0

if edgeFadeSec > 0
    maxFade = outDur / 2
    if edgeFadeSec < maxFade
        effectiveFadeSec = edgeFadeSec
    else
        effectiveFadeSec = maxFade
    endif
    if effectiveFadeSec > 0
        selectObject: trimmedSound
        Formula: "if x < xmin + 'effectiveFadeSec:6' then self * (x - xmin) / 'effectiveFadeSec:6' else if x > xmax - 'effectiveFadeSec:6' then self * (xmax - x) / 'effectiveFadeSec:6' else self endif endif"
        fadeApplied = 1
    endif
endif

# ------------------------------------------------------------
# Report
# ------------------------------------------------------------
writeInfoLine: "=== Auto-Trim Silence v0.6 Report ==="
appendInfoLine: "Detection mode: ", detection_mode$
appendInfoLine: "Threshold: ", threshold_dB_below_peak, " dB below analysis peak"
appendInfoLine: "Original duration: ", fixed$(originalDuration, 3), " s"
appendInfoLine: "Detected first sounding time: ", fixed$(startTime, 3), " s"
appendInfoLine: "Detected last sounding time: ", fixed$(endTime, 3), " s"
appendInfoLine: "Padding requested (lead/trail): ", leading_padding_ms, " / ", trailing_padding_ms, " ms"
appendInfoLine: "Zero-crossing search distance: ", zero_crossing_search_ms, " ms (outward only)"
appendInfoLine: "Final trim points (after padding + quiet-point search): ", fixed$(trimStart, 4), " s -> ", fixed$(trimEnd, 4), " s"
appendInfoLine: "Leading duration removed: ", fixed$(trimStart - soundXmin, 3), " s"
appendInfoLine: "Trailing duration removed: ", fixed$(soundXmax - trimEnd, 3), " s"
if fadeApplied = 1
    appendInfoLine: "Edge fade applied: ", fixed$(effectiveFadeSec * 1000, 2), " ms"
else
    appendInfoLine: "Edge fade applied: none (requested ", edge_fade_ms, " ms was 0, or longer than half the output)"
endif
appendInfoLine: "Output duration: ", fixed$(outDur, 3), " s"
appendInfoLine: "Output object: ", soundName$, "_trimmed"

# ------------------------------------------------------------
# Visualization
# ------------------------------------------------------------
if draw_visualization = 1
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    vizName$ = replace$(soundName$, "_", "\_ ", 0)

    selectObject: originalSound
    srcPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: trimmedSound
    outPeakViz = Get absolute extremum: 0, 0, "None"
    ampViz = srcPeakViz
    if outPeakViz > ampViz
        ampViz = outPeakViz
    endif
    if ampViz < 0.001
        ampViz = 0.001
    endif
    ampViz = ampViz * 1.15

    pageHeight = 5.85
    Erase all
    Line width: 1
    Colour: "Black"
    Solid line
    Select outer viewport: 0, 8, 0, pageHeight

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Auto-Trim Silence v0.6##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + detection_mode$ + " | threshold " + fixed$(threshold_dB_below_peak, 1) + " dB below analysis peak"

    # === Detection and final trim boundaries ===
    Select outer viewport: 0, 8, 0.72, 2.72
    Select inner viewport: 0.60, 7.70, 1.00, 2.48
    Axes: soundXmin, soundXmax, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", soundXmin, soundXmax, -ampViz, ampViz

    # Removed material.
    if trimStart > soundXmin
        Paint rectangle: "{0.94, 0.86, 0.86}", soundXmin, trimStart, -ampViz, ampViz
    endif
    if trimEnd < soundXmax
        Paint rectangle: "{0.94, 0.86, 0.86}", trimEnd, soundXmax, -ampViz, ampViz
    endif

    # Detected sounding span: dashed blue.
    Colour: "{0.25, 0.45, 0.75}"
    Dashed line
    Draw line: startTime, -ampViz, startTime, ampViz
    Draw line: endTime, -ampViz, endTime, ampViz
    Solid line

    # Final outward-safe trim points: solid amber.
    Colour: "{0.80, 0.55, 0.20}"
    Line width: 2
    Draw line: trimStart, -ampViz, trimStart, ampViz
    Draw line: trimEnd, -ampViz, trimEnd, ampViz
    Line width: 1

    selectObject: originalSound
    Colour: "{0.50, 0.50, 0.50}"
    Draw: soundXmin, soundXmax, -ampViz, ampViz, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Trim Decision | red = removed | blue dashed = detected sounding | amber = final safe cut"

    # === Trimmed result ===
    Select outer viewport: 0, 8, 2.94, 4.08
    Select inner viewport: 0.60, 7.70, 3.16, 3.84
    Axes: 0, outDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, -ampViz, ampViz
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, outDur, 0
    selectObject: trimmedSound
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, outDur, -ampViz, ampViz, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Trimmed Result | edge fade " + fixed$(effectiveFadeSec * 1000, 2) + " ms"

    # === Summary strip ===
    Select outer viewport: 0, 8, 4.30, 5.80
    Select inner viewport: 0.60, 7.70, 4.40, 5.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half", "##Detection##  first sounding " + fixed$(startTime, 3) + " s | last sounding " + fixed$(endTime, 3) + " s | minimum silence " + fixed$(min_silence_duration_sec, 3) + " s | minimum sounding " + fixed$(min_sounding_duration_sec, 3) + " s"
    Text: 0.02, "left", 0.50, "half", "##Boundary rule##  padding " + fixed$(leading_padding_ms, 1) + "/" + fixed$(trailing_padding_ms, 1) + " ms | outward quiet-point search <= " + fixed$(zero_crossing_search_ms, 1) + " ms | final " + fixed$(trimStart, 4) + " -> " + fixed$(trimEnd, 4) + " s"
    Text: 0.02, "left", 0.22, "half", "##Output##  " + fixed$(originalDuration, 3) + " s -> " + fixed$(outDur, 3) + " s | removed lead " + fixed$(trimStart - soundXmin, 3) + " s | removed tail " + fixed$(soundXmax - trimEnd, 3) + " s | peak " + fixed$(outPeakViz, 3)
    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ------------------------------------------------------------
# Keep the new trimmed sound selected; play only if requested
# ------------------------------------------------------------
selectObject: trimmedSound
if play_result = 1
    Play
endif
