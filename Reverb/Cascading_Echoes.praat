# ============================================================
# Praat AudioTools - Cascading_Echoes.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cascading Echoes - multi-tap delay effect with random delay
#   times per iteration. Creates dense, diffuse echo patterns.
#   Stereo mode uses different delay ranges for L/R channels
#   to create width. Exponential amplitude decay per tap.
#
# Algorithmic note (despite the name "Cascading"):
#   This is a multi-tap FIR delay, NOT cascading IIR feedback.
#   Each iteration k adds an independently-delayed copy of the
#   DRY signal to the wet accumulator, attenuated by decay^k:
#       wet = dry + sum_{k=1..N} (decay^k) * dry[col - delay[k]]
#   The taps don't feed back into each other; they're parallel
#   delayed-and-attenuated copies of the original.
#
# Stereo width note:
#   In stereo mode, each channel is independently Scale peak'd
#   to 0.95 BEFORE recombination. This maximizes per-channel
#   headroom but distorts the original L/R balance. By design
#   for the "Wide Stereo Delay" character; flagged in Panel B
#   so users see what's happening.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - Public form and output naming are unchanged.
#   - Private zero-based work copy fixes non-zero source xmin.
#   - Full multichannel support: odd channels use L taps, even use R taps.
#   - Silent tail now matches the source channel count.
#   - Custom delay ranges are ordered; all delays are >= 1 sample.
#   - Decay values are capped at 1.0; iterations at 256 internally.
#   - Safe normalization skips digital silence.
#   - Visualization uses the zero-based copy and reports multichannel mode.
#   - Warns if tail duration is shorter than the longest generated delay.
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters AND same Praat RNG state.
#     Same multi-tap FIR algorithm, same exponential decay
#     schedule (decay^k), same independent random delay
#     generation (unseeded), same mono/stereo processing
#     branches, same independent per-channel Scale peak before
#     stereo recombination, same wet/dry mix, same tail
#     extension. Same 4 presets (+ Custom) with same values.
#   - Form syntax modernized: `optionmenu Preset:` with colon.
#   - Dropped 9 decorative form lines (7 `comment === ... ===`
#     section dividers, 1 instructional, 1 inline parenthetical
#     hint). Form went from ~17 effective rows to 8 functional
#     rows.
#   - Visualization rewritten to suite 8x8 standard (v0.2 was
#     8x4.7 with 4 unconsolidated panels):
#       Title bar + metadata subtitle (preset, iterations,
#         decay L/R, delay ranges, wet/dry %)
#       Panel A (left, headline): echo tap diagram —
#         PRESERVED v0.2 design (L green stems + dots, R blue
#         stems + dots, dry gray dot at origin), now positioned
#         at suite-standard headline location
#       Panel B (right, headline): parameter report + tap list
#         showing individual tap times for both channels
#       Panel C: zoom overlay (first 500 ms, gray = original,
#         blue = processed) — shows the early echo cascade
#       Panel D: full waveform comparison (gray = original,
#         blue = processed, overlaid with SHARED y-axis) —
#         fixes v0.2's independent auto-scaling that made dry
#         vs wet hard to compare visually
#       Panel E: light-grey summary stats bar (suite standard)
# Changelog v0.2:
#   - Fixed echo formula
#   - Added bounds checking
#   - Fixed selection syntax
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Cascading Echoes v0.5.1
    optionmenu Preset: 1
        option Default (balanced)
        option Short and Tight
        option Long Ambient Tail
        option Wide Stereo Delay
        option Custom (use settings below)
    positive Tail_duration_s 1.0
    natural Iterations 5
    positive Delay_min_ms 10
    positive Delay_max_ms 100
    positive Stereo_delay_min_ms 12
    positive Stereo_delay_max_ms 120
    positive Decay_left 0.8
    positive Decay_right 0.75
    real Wet_dry_percent 60
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# Private zero-based work copy; original Sound is never shifted.
selectObject: original
workSource = Copy: "cascading_echoes_work"
selectObject: workSource
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    tail_duration_s = 1.0
    iterations = 5
    delay_min_ms = 10
    delay_max_ms = 100
    stereo_delay_min_ms = 12
    stereo_delay_max_ms = 120
    decay_left = 0.8
    decay_right = 0.75
    presetName$ = "Default"
elsif preset = 2
    # Short & Tight
    tail_duration_s = 0.5
    iterations = 3
    delay_min_ms = 5
    delay_max_ms = 40
    stereo_delay_min_ms = 7
    stereo_delay_max_ms = 50
    decay_left = 0.9
    decay_right = 0.88
    presetName$ = "ShortTight"
elsif preset = 3
    # Long Ambient Tail
    tail_duration_s = 2.5
    iterations = 7
    delay_min_ms = 25
    delay_max_ms = 250
    stereo_delay_min_ms = 30
    stereo_delay_max_ms = 300
    decay_left = 0.85
    decay_right = 0.82
    presetName$ = "LongAmbient"
elsif preset = 4
    # Wide Stereo Delay
    tail_duration_s = 1.5
    iterations = 6
    delay_min_ms = 15
    delay_max_ms = 120
    stereo_delay_min_ms = 40
    stereo_delay_max_ms = 350
    decay_left = 0.78
    decay_right = 0.72
    presetName$ = "WideStereo"
else
    presetName$ = "Custom"
endif

# Internal safety guards; built-in presets are already within these limits.
if iterations > 256
    iterations = 256
endif
if delay_min_ms > delay_max_ms
    tmpDelay = delay_min_ms
    delay_min_ms = delay_max_ms
    delay_max_ms = tmpDelay
endif
if stereo_delay_min_ms > stereo_delay_max_ms
    tmpDelay = stereo_delay_min_ms
    stereo_delay_min_ms = stereo_delay_max_ms
    stereo_delay_max_ms = tmpDelay
endif
if decay_left > 1
    decay_left = 1
endif
if decay_right > 1
    decay_right = 1
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Convert ms to samples
delay_min_samp = max(1, round(delay_min_ms / 1000 * sr))
delay_max_samp = max(delay_min_samp, round(delay_max_ms / 1000 * sr))
stereo_min_samp = max(1, round(stereo_delay_min_ms / 1000 * sr))
stereo_max_samp = max(stereo_min_samp, round(stereo_delay_max_ms / 1000 * sr))

# Store delay values for visualization
maxGeneratedDelay = 0
for k from 1 to iterations
    delayL[k] = round(randomUniform(delay_min_samp, delay_max_samp))
    delayR[k] = round(randomUniform(stereo_min_samp, stereo_max_samp))
    ampL[k] = decay_left ^ k
    ampR[k] = decay_right ^ k
    if delayL[k] > maxGeneratedDelay
        maxGeneratedDelay = delayL[k]
    endif
    if delayR[k] > maxGeneratedDelay
        maxGeneratedDelay = delayR[k]
    endif
endfor

# === Info ===
writeInfoLine: "=== Cascading Echoes v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Iterations: ", iterations
appendInfoLine: "Delay range (L): ", delay_min_ms, "-", delay_max_ms, " ms"
appendInfoLine: "Delay range (R): ", stereo_delay_min_ms, "-", stereo_delay_max_ms, " ms"
appendInfoLine: "Decay (L/R): ", decay_left, " / ", decay_right
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
if tail_duration_s * sr < maxGeneratedDelay
    appendInfoLine: "WARNING: tail shorter than longest generated delay; late echo content will be truncated."
endif
appendInfoLine: ""
appendInfoLine: "Echo taps:"
for k from 1 to iterations
    appendInfoLine: "  ", k, ": L=", round(delayL[k] * 1000 / sr), "ms (", fixed$(ampL[k], 2), ") | R=", round(delayR[k] * 1000 / sr), "ms (", fixed$(ampR[k], 2), ")"
endfor
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Create extended sound with tail
selectObject: workSource
totalDur = originalDur + tail_duration_s

Create Sound from formula: "silent_tail", numChannels, 0, tail_duration_s, sr, "0"
silentTail = selected("Sound")

# workSource was created before silentTail, so Object-list order is dry then tail.
selectObject: workSource, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

nSamples = Get number of samples

if numChannels = 2
    # === STEREO PROCESSING ===
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Create wet signal containers (start as copies)
    selectObject: leftChannel
    Copy: "left_wet"
    leftWet = selected("Sound")
    
    selectObject: rightChannel
    Copy: "right_wet"
    rightWet = selected("Sound")
    
    # Process left channel - add each echo tap
    for k from 1 to iterations
        delay = delayL[k]
        amp = ampL[k]
        amp_str$ = string$(amp)
        delay_str$ = string$(delay)
        
        # Add delayed version of original
        left_str$ = string$(leftChannel)
        selectObject: leftWet
        Formula: "self + " + amp_str$ + " * (if col > " + delay_str$ + " then object[" + left_str$ + ", col - " + delay_str$ + "] else 0 fi)"
    endfor
    
    # Process right channel
    for k from 1 to iterations
        delay = delayR[k]
        amp = ampR[k]
        amp_str$ = string$(amp)
        delay_str$ = string$(delay)
        
        right_str$ = string$(rightChannel)
        selectObject: rightWet
        Formula: "self + " + amp_str$ + " * (if col > " + delay_str$ + " then object[" + right_str$ + ", col - " + delay_str$ + "] else 0 fi)"
    endfor
    
    # Apply wet/dry mix
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: leftWet
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: rightWet
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Normalize (per-channel — preserves "Wide Stereo Delay" character)
    selectObject: leftWet
    leftPeak = Get absolute extremum: 0, 0, "None"
    if leftPeak > 0
        Scale peak: 0.95
    endif

    selectObject: rightWet
    rightPeak = Get absolute extremum: 0, 0, "None"
    if rightPeak > 0
        Scale peak: 0.95
    endif
    
    # Combine to stereo
    selectObject: leftWet, rightWet
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_echo_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, leftWet, rightWet, extendedSound
    
elsif numChannels = 1
    # === MONO PROCESSING ===
    
    # Create wet signal (start as copy)
    selectObject: extendedSound
    Copy: "mono_wet"
    monoWet = selected("Sound")
    
    # Add each echo tap
    for k from 1 to iterations
        delay = delayL[k]
        amp = ampL[k]
        amp_str$ = string$(amp)
        delay_str$ = string$(delay)
        
        ext_str$ = string$(extendedSound)
        selectObject: monoWet
        Formula: "self + " + amp_str$ + " * (if col > " + delay_str$ + " then object[" + ext_str$ + ", col - " + delay_str$ + "] else 0 fi)"
    endfor
    
    # Apply wet/dry mix
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: monoWet
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    # Normalize
    selectObject: monoWet
    monoPeak = Get absolute extremum: 0, 0, "None"
    if monoPeak > 0
        Scale peak: 0.95
    endif
    Rename: originalName$ + "_echo_" + presetName$
    result = monoWet

    # Cleanup
    removeObject: extendedSound

else
    # === MULTICHANNEL PROCESSING (3+ channels) ===
    # Odd channels use L taps; even channels use R taps.
    selectObject: extendedSound
    Copy: "multi_wet"
    multiWet = selected("Sound")
    ext_str$ = string$(extendedSound)

    for k from 1 to iterations
        delayL_str$ = string$(delayL[k])
        delayR_str$ = string$(delayR[k])
        ampL_str$ = string$(ampL[k])
        ampR_str$ = string$(ampR[k])

        selectObject: multiWet
        Formula: "self + if row mod 2 = 1 then "
            ... + ampL_str$ + " * (if col > " + delayL_str$
            ... + " then object[" + ext_str$ + ", row, col - " + delayL_str$ + "] else 0 fi)"
            ... + " else "
            ... + ampR_str$ + " * (if col > " + delayR_str$
            ... + " then object[" + ext_str$ + ", row, col - " + delayR_str$ + "] else 0 fi)"
            ... + " fi"
    endfor

    if dry_level > 0
        selectObject: multiWet
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + ext_str$ + ", row, col] * " + string$(dry_level)
    endif

    # One common normalization preserves inter-channel balance.
    selectObject: multiWet
    multiPeak = Get absolute extremum: 0, 0, "None"
    if multiPeak > 0
        Scale peak: 0.95
    endif
    Rename: originalName$ + "_echo_" + presetName$
    result = multiWet
    removeObject: extendedSound
endif

# Capture stats for visualization
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
resultNumCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Black
    Plain line
    
    # Find max delay (for tap diagram axis)
    maxDelay = 0
    for k from 1 to iterations
        if delayL[k] > maxDelay
            maxDelay = delayL[k]
        endif
        if delayR[k] > maxDelay
            maxDelay = delayR[k]
        endif
    endfor
    maxDelayMs = maxDelay * 1000 / sr * 1.1
    if maxDelayMs < 10
        maxDelayMs = 10
    endif
    
    # Mono copies of original and result for waveform display
    selectObject: workSource
    if numChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz_orig"
    endif
    
    selectObject: result
    if resultNumCh > 1
        vizProc = Convert to mono
    else
        vizProc = Copy: "viz_proc"
    endif
    
    # Compute SHARED y-axis from BOTH dry and wet (fixes v0.2's
    # independent auto-scaling that made comparison difficult)
    selectObject: vizOrig
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizProc
    pPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = oPeak
    if pPeak > sharedPeak
        sharedPeak = pPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.15
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##CASCADING ECHOES##" + " | v0.5.1"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(iterations) + " iter"
        ... + "  |  decay L/R " + fixed$(decay_left, 2) + "/" + fixed$(decay_right, 2)
        ... + "  |  L " + fixed$(delay_min_ms, 0) + "-" + fixed$(delay_max_ms, 0) + " ms"
        ... + "  |  R " + fixed$(stereo_delay_min_ms, 0) + "-" + fixed$(stereo_delay_max_ms, 0) + " ms"
        ... + "  |  " + fixed$(wet_dry_percent, 0) + "% wet"
    
    # ----------------------------------------------------------
    # PANEL A: ECHO TAP DIAGRAM  (left, headline)
    # PRESERVED v0.2 design: L green stems + dots, R blue stems
    # + dots, dry gray dot at origin.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    Axes: 0, maxDelayMs, 0, 1.15
    Paint rectangle: "{0.96, 0.96, 0.97}", 0, maxDelayMs, 0, 1.15
    
    # Reference grid
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    Draw line: 0, 0.25, maxDelayMs, 0.25
    Draw line: 0, 0.50, maxDelayMs, 0.50
    Draw line: 0, 0.75, maxDelayMs, 0.75
    Draw line: 0, 1.00, maxDelayMs, 1.00
    Solid line
    
    # Dry signal marker at origin (gray)
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 2
    Draw line: 0, 0, 0, 1
    Paint circle (mm): "{0.55, 0.55, 0.55}", 0, 1, 1.0
    
    # Echo taps
    Line width: 2
    for k from 1 to iterations
        # Left tap (green)
        delayMs_L = delayL[k] * 1000 / sr
        Colour: "{0.30, 0.65, 0.35}"
        Draw line: delayMs_L, 0, delayMs_L, ampL[k]
        Paint circle (mm): "{0.30, 0.65, 0.35}", delayMs_L, ampL[k], 0.9
        
        # Right tap (blue)
        delayMs_R = delayR[k] * 1000 / sr
        Colour: "{0.30, 0.45, 0.78}"
        Draw line: delayMs_R, 0, delayMs_R, ampR[k]
        Paint circle (mm): "{0.30, 0.45, 0.78}", delayMs_R, ampR[k], 0.9
    endfor
    Line width: 1
    
    # Inline legend
    Font size: 6
    Colour: "{0.55, 0.55, 0.55}"
    Text: maxDelayMs * 0.02, "left", 1.10, "half", "dry"
    Colour: "{0.30, 0.65, 0.35}"
    Text: maxDelayMs * 0.10, "left", 1.10, "half", "L taps"
    Colour: "{0.30, 0.45, 0.78}"
    Text: maxDelayMs * 0.22, "left", 1.10, "half", "R taps"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 0.95, 4.40
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amplitude (decay^k)"
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    Axes: 0, maxDelayMs, 0, 1.15
    Text bottom: "yes", "Delay (ms)"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT + TAP LIST  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.95, "half", "Algorithm:"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.89, "half", "Multi-tap FIR delay (parallel, not cascading)"
    Text: 0.10, "left", 0.84, "half", "wet = dry + sum_k (decay^k) \\.c dry[col - delay_k]"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.77, "half", "Settings:"
    
    Font size: 7
    Colour: "{0.30, 0.65, 0.35}"
    Text: 0.10, "left", 0.71, "half", "Decay L: " + fixed$(decay_left, 3) + "  |  Range: " + fixed$(delay_min_ms, 0) + "-" + fixed$(delay_max_ms, 0) + " ms"
    Colour: "{0.30, 0.45, 0.78}"
    Text: 0.10, "left", 0.65, "half", "Decay R: " + fixed$(decay_right, 3) + "  |  Range: " + fixed$(stereo_delay_min_ms, 0) + "-" + fixed$(stereo_delay_max_ms, 0) + " ms"
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.59, "half", "Iterations: " + string$(iterations) + "  |  Tail: " + fixed$(tail_duration_s, 2) + " s"
    Text: 0.10, "left", 0.53, "half", "Wet/Dry:    " + fixed$(wet_dry_percent, 0) + "% wet"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.46, "half", "Taps:"
    
    # Tap list (up to 7 taps shown; if more, show first 5 + last 1)
    Font size: 6
    if iterations <= 7
        nShow = iterations
        truncate = 0
    else
        nShow = 5
        truncate = 1
    endif
    
    tapY = 0.40
    for k from 1 to nShow
        Colour: "{0.30, 0.65, 0.35}"
        Text: 0.10, "left", tapY, "half", "L" + string$(k) + ": " + fixed$(delayL[k] * 1000 / sr, 1) + " ms (" + fixed$(ampL[k], 2) + ")"
        Colour: "{0.30, 0.45, 0.78}"
        Text: 0.52, "left", tapY, "half", "R" + string$(k) + ": " + fixed$(delayR[k] * 1000 / sr, 1) + " ms (" + fixed$(ampR[k], 2) + ")"
        tapY = tapY - 0.045
    endfor
    
    if truncate
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", tapY, "half", "..."
        tapY = tapY - 0.045
        Colour: "{0.30, 0.65, 0.35}"
        Text: 0.10, "left", tapY, "half", "L" + string$(iterations) + ": " + fixed$(delayL[iterations] * 1000 / sr, 1) + " ms (" + fixed$(ampL[iterations], 2) + ")"
        Colour: "{0.30, 0.45, 0.78}"
        Text: 0.52, "left", tapY, "half", "R" + string$(iterations) + ": " + fixed$(delayR[iterations] * 1000 / sr, 1) + " ms (" + fixed$(ampR[iterations], 2) + ")"
    endif
    
    # Stereo width disclaimer if relevant
    if numChannels = 2
        Font size: 6
        Colour: "{0.55, 0.30, 0.20}"
        Text: 0.05, "left", 0.03, "half", "Note: per-channel Scale peak (Wide Stereo character)"
    elsif numChannels > 2
        Font size: 6
        Colour: "{0.55, 0.30, 0.20}"
        Text: 0.05, "left", 0.03, "half", "Note: odd channels use L taps; even channels use R taps"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0.60, 7.70, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Echo tap diagram  (L green, R blue, dry gray)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report + tap list"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 500 ms)
    # Gray = original, blue = processed.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    
    zoomDur = 0.5
    if zoomDur > originalDur
        zoomDur = originalDur
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif
    
    selectObject: vizOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: vizProc
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original behind
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Processed on top
    selectObject: vizProc
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, blue = processed)"
    Select inner viewport: 0.20, 0.48, 4.75, 5.48
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amp"
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    Axes: 0, zoomDur, -z_amp, z_amp
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: FULL WAVEFORM COMPARISON  (overlaid, SHARED y-axis)
    # Fixes v0.2's independent auto-scaling.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    
    Axes: 0, finalDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    # Mark the dry-vs-tail boundary
    if originalDur < finalDur
        Colour: "{0.85, 0.50, 0.20}"
        Line width: 1
        Dotted line
        Draw line: originalDur, -sharedAmp, originalDur, sharedAmp
        Solid line
        Font size: 6
        Text: originalDur, "left", sharedAmp * 0.85, "half", "  tail"
    endif
    
    # Original behind
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, finalDur, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Processed on top
    selectObject: vizProc
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, finalDur, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Full output  (gray = original, blue = processed, shared y-axis)"
    Select inner viewport: 0.20, 0.48, 5.69, 6.48
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amp"
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    Axes: 0, finalDur, -sharedAmp, sharedAmp
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.70, 7.70
    Select inner viewport: 0.60, 7.70, 6.77, 7.63
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if numChannels = 2
        stereoStr$ = "stereo (per-ch peak)"
    elsif numChannels = 1
        stereoStr$ = "mono"
    else
        stereoStr$ = string$(numChannels) + "ch (odd=L taps, even=R taps)"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", 
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + string$(iterations) + " iterations"
        ... + "  |  Decay L: " + fixed$(decay_left, 3)
        ... + "  |  Decay R: " + fixed$(decay_right, 3)
        ... + "  |  L range: " + fixed$(delay_min_ms, 0) + "-" + fixed$(delay_max_ms, 0) + " ms"
        ... + "  |  R range: " + fixed$(stereo_delay_min_ms, 0) + "-" + fixed$(stereo_delay_max_ms, 0) + " ms"
    
    Font size: 6
    Text: 0.02, "left", 0.24, "half", 
        ... "Wet/Dry: " + fixed$(wet_dry_percent, 0) + "\%  "
        ... + "  |  Tail: " + fixed$(tail_duration_s, 2) + " s"
        ... + "  |  Mode: " + stereoStr$
        ... + "  |  In: " + fixed$(originalDur, 2) + " s"
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    
    Select inner viewport: 0.60, 7.70, 6.77, 7.63
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: vizOrig, vizProc

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 7.80
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

removeObject: workSource

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
