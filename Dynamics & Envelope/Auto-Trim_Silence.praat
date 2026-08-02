# ============================================================
# Praat AudioTools - Auto-Trim Silence.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auto-Trim Silence (Start and End)
#   Finds the first-to-last "sounding" span of a Sound and extracts it,
#   with safe padding, outward-only quiet-point alignment, and short
#   edge fades.
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

form Auto-Trim Silence
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
writeInfoLine: "=== Auto-Trim Silence Report ==="
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
# Keep the new trimmed sound selected; play only if requested
# ------------------------------------------------------------
selectObject: trimmedSound
if play_result = 1
    Play
endif
