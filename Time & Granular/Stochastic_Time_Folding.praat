# ============================================================
# Praat AudioTools - Stochastic_Time_Folding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stochastic Time Folding - creates blurry, smeared textures
#   through probabilistic time-domain averaging. Each iteration
#   randomly decides whether to fold (average past/present/future)
#   or apply a uniform amplitude variation, creating evolving
#   diffuse sounds.
#
# Changelog v0.5:
#   - API COMPATIBILITY: public form is byte-for-byte unchanged from v0.4.
#     Output naming remains <input>_folded_<preset>.
#   - FIX: Amplitude_min / Amplitude_max now have audible effect. v0.4
#     applied a uniform gain per AMP pass, then unconditionally normalized
#     the final peak. Because every fold pass is linear, all uniform AMP
#     gains reduce to one global scalar and were cancelled exactly by final
#     peak normalization. v0.5 treats Scale_peak as a maximum output peak:
#     it scales DOWN only when needed and never boosts a quieter result.
#   - HARDENING: all user min/max pairs are canonicalized internally, so
#     reversed Custom ranges do not break randomUniform calls.
#   - HARDENING: probability thresholds are clamped to [0,1], matching the
#     randomUniform(0,1) decision mask. Presets are unchanged.
#   - FIX: foldDistance and backwardDistance are clamped to at least one
#     sample; extreme Custom divisors can no longer collapse to a zero-delay
#     pseudo-fold.
#   - SAFE NORMALIZATION: digital silence is left untouched.
#
# Changelog v0.4 (musical fixes -- output is intentionally cleaner
# than v0.2/v0.3 on the Aggressive and Micro Glitch presets):
#
#   The folding Formula's in-place feedback cascade is PRESERVED
#   exactly (it is load-bearing -- it keeps the texture coherent).
#   Two separate gain/noise problems that made the output distorted
#   and noisy are fixed:
#
#   FIX 1 -- gain blowup eliminated (avgDiv clamped to >= 3).
#     The FOLD branch sums three terms and divides by avgDiv. With
#     the feedback it is a single-pole IIR whose DC gain per
#     iteration is 2/(avgDiv-1):
#         avgDiv = 2  ->  2.0x per iteration  (2^9 = 512x over the
#                         Aggressive preset's 9 iterations; 2^12 =
#                         4096x over Micro Glitch's 12) -> massive
#                         low-frequency buildup that survived the
#                         final Scale peak as distortion.
#         avgDiv = 3  ->  1.0x  (unity, stable, clean)
#         avgDiv > 3  ->  < 1.0x (attenuates)
#     v0.4 clamps avgDiv = max(3, fold_average_divisor) so DC gain is
#     always <= 1. The Aggressive and Micro Glitch presets are
#     updated to avgDiv = 3 (they keep their aggression through
#     iteration count, threshold range, and short fold distances --
#     not through over-unity gain). Default and Gentle already used
#     3 and are unchanged.
#
#   FIX 2 -- per-sample noise eliminated.
#     v0.2's non-fold branch was `self * randomUniform(ampMin, ampMax)`,
#     which re-evaluated randomUniform PER SAMPLE -> broadband
#     multiplicative noise (harsh, glitchy). v0.4 computes ONE random
#     gain per iteration (iterAmpGain) and applies it uniformly, so
#     the amplitude-variation gesture remains but the per-sample noise
#     is gone.
#
#   Net: Default/Gentle are essentially unchanged; Aggressive and
#   Micro Glitch are now musical -- diffuse and evolving rather than
#   distorted and noisy.
#
#   Also retained from the v0.3 polish pass (all non-audio):
#     - Form: 8 comment rows dropped; colon on optionmenu Preset:.
#     - presetName$ "Micro Glitch" -> "MicroGlitch"; output filename
#       <input>_folded_<preset>.
#     - Visualization rewritten to suite 8x8 with the legend
#       positioning bug fixed (explicit Axes: 0,1,0,1).
#     - Optional Debug_output toggle: per-iteration peak/RMS and gain
#       reporting in the info window (default ON; turn off once you've
#       confirmed the gains sit near 1.0x).
#
#   Changelog v0.2:
#     - Modern syntax
#     - Added bounds checking
#     - Fixed Formula interpolation
#     - Added visualization
# ============================================================

form Stochastic Time Folding v0.4
    optionmenu Preset: 1
        option Default (balanced)
        option Gentle Folds
        option Aggressive Folds
        option Micro Glitch
        option Custom
    natural Fold_iterations 6
    positive Initial_threshold 0.5
    positive Threshold_var_min 0.2
    positive Threshold_var_max 0.2
    positive Threshold_limit_min 0.1
    positive Threshold_limit_max 0.9
    positive Fold_distance_min 3
    positive Fold_distance_max 12
    positive Amplitude_min 0.7
    positive Amplitude_max 1.2
    positive Fold_average_divisor 3
    positive Fold_backward_divisor 2
    positive Scale_peak 0.96
    boolean Debug_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    fold_iterations = 6
    initial_threshold = 0.5
    threshold_var_min = 0.2
    threshold_var_max = 0.2
    threshold_limit_min = 0.1
    threshold_limit_max = 0.9
    fold_distance_min = 3
    fold_distance_max = 12
    amplitude_min = 0.7
    amplitude_max = 1.2
    fold_average_divisor = 3
    fold_backward_divisor = 2
elsif preset = 2
    # Gentle Folds
    fold_iterations = 4
    initial_threshold = 0.4
    threshold_var_min = 0.10
    threshold_var_max = 0.15
    threshold_limit_min = 0.15
    threshold_limit_max = 0.85
    fold_distance_min = 5
    fold_distance_max = 15
    amplitude_min = 0.9
    amplitude_max = 1.1
    fold_average_divisor = 3
    fold_backward_divisor = 2
elsif preset = 3
    # Aggressive Folds
    fold_iterations = 9
    initial_threshold = 0.6
    threshold_var_min = 0.25
    threshold_var_max = 0.35
    threshold_limit_min = 0.05
    threshold_limit_max = 0.95
    fold_distance_min = 2
    fold_distance_max = 10
    amplitude_min = 0.5
    amplitude_max = 1.5
    fold_average_divisor = 3
    fold_backward_divisor = 2
elsif preset = 4
    # Micro Glitch
    fold_iterations = 12
    initial_threshold = 0.55
    threshold_var_min = 0.15
    threshold_var_max = 0.25
    threshold_limit_min = 0.10
    threshold_limit_max = 0.90
    fold_distance_min = 2
    fold_distance_max = 6
    amplitude_min = 0.6
    amplitude_max = 1.4
    fold_average_divisor = 3
    fold_backward_divisor = 3
endif

# === Internal Parameter Canonicalization (public form unchanged) ===
thresholdVarLow = min(threshold_var_min, threshold_var_max)
thresholdVarHigh = max(threshold_var_min, threshold_var_max)
thresholdLimitLow = max(0, min(1, min(threshold_limit_min, threshold_limit_max)))
thresholdLimitHigh = max(0, min(1, max(threshold_limit_min, threshold_limit_max)))
foldDivisorLow = min(fold_distance_min, fold_distance_max)
foldDivisorHigh = max(fold_distance_min, fold_distance_max)
ampLow = min(amplitude_min, amplitude_max)
ampHigh = max(amplitude_min, amplitude_max)

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
totalSamples = Get number of samples
if totalSamples < 3
    exitScript: "Sound must contain at least 3 samples for time folding."
endif

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Gentle"
elsif preset = 3
    presetName$ = "Aggressive"
elsif preset = 4
    presetName$ = "MicroGlitch"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Stochastic Time Folding v0.4 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Iterations: ", fold_iterations
appendInfoLine: "Initial threshold: ", initial_threshold
appendInfoLine: "Fold distance range: ", fold_distance_min, "-", fold_distance_max
appendInfoLine: ""

# === Copy for Processing ===
selectObject: original
Copy: original_name$ + "_folded_" + presetName$
result = selected("Sound")

# === Store Threshold Evolution for Visualization ===
thresholds# = zero#(fold_iterations)
foldDistances# = zero#(fold_iterations)

# === Initialize Adaptive Threshold ===
adaptiveThreshold = max(thresholdLimitLow, min(thresholdLimitHigh, initial_threshold))

# === Main Folding Processing Loop ===
appendInfoLine: "Processing folds..."

for fold from 1 to fold_iterations
    selectObject: result
    
    # Evolve threshold (except first iteration)
    if fold > 1
        thresholdChange = randomUniform(thresholdVarLow, thresholdVarHigh)
        # Randomly add or subtract
        if randomUniform(0, 1) > 0.5
            adaptiveThreshold = adaptiveThreshold + thresholdChange
        else
            adaptiveThreshold = adaptiveThreshold - thresholdChange
        endif
        # Clamp to limits
        adaptiveThreshold = max(thresholdLimitLow, min(thresholdLimitHigh, adaptiveThreshold))
    endif
    
    thresholds#[fold] = adaptiveThreshold
    
    # Random fold distance for this iteration
    foldDivisor = randomUniform(foldDivisorLow, foldDivisorHigh)
    foldDistance = max(1, round(totalSamples / foldDivisor))
    backwardDistance = max(1, round(foldDistance / fold_backward_divisor))
    
    foldDistances#[fold] = foldDistance / sampleRate * 1000
    
    # Random probability for this iteration
    probMask = randomUniform(0, 1)
    
    # Amplitude variation range
    ampMin = ampLow
    ampMax = ampHigh
    
    # v0.4 MUSICAL FIX 1 (gain): clamp avgDiv to >= 3. The FOLD branch
    # is a feedback IIR with DC gain 2/(avgDiv-1) per iteration:
    #   avgDiv=2 -> 2.0x  (compounds to 512x over 9 iters -> distortion)
    #   avgDiv=3 -> 1.0x  (unity, stable, clean)
    #   avgDiv>3 -> <1.0x (attenuates)
    # avgDiv < 3 caused the low-frequency buildup that survived the
    # final Scale peak as distortion. Clamping to 3 guarantees DC gain
    # <= 1, so no spectral blowup. Default/Gentle already use 3.
    avgDiv = max(3, fold_average_divisor)
    
    # v0.4 MUSICAL FIX 2 (noise): one amplitude gain per iteration,
    # applied uniformly. v0.2's else branch used
    # `self * randomUniform(ampMin, ampMax)` which re-randomized EVERY
    # sample -> broadband multiplicative noise (the harsh glitch). A
    # single per-iteration gain keeps the amplitude-variation gesture
    # without the per-sample noise.
    iterAmpGain = randomUniform(ampMin, ampMax)
    
    appendInfoLine: "  Fold ", fold, ": thresh=", fixed$(adaptiveThreshold, 2), " dist=", foldDistance, " prob=", fixed$(probMask, 2)
    
    # Which branch will this iteration take? (probMask and
    # adaptiveThreshold are per-iteration scalars, so the whole
    # buffer takes the same branch.)
    if probMask < adaptiveThreshold
        branchTaken$ = "FOLD (avg 3 samples / " + string$(avgDiv) + ")"
    else
        branchTaken$ = "AMP (uniform x" + fixed$(iterAmpGain, 3) + ")"
    endif
    
    # DEBUG: measure level BEFORE this iteration's Formula
    if debug_output
        selectObject: result
        peakBefore = Get absolute extremum: 0, 0, "None"
        rmsBefore = Get root-mean-square: 0, 0
    endif
    
    # NOTE: the backward reference self[col - backwardDistance] reads the
    # ALREADY-FOLDED value, not the original, because Praat evaluates a
    # Sound Formula left-to-right (gotcha #19). This is a recursive
    # within-pass cascade and it is LOAD-BEARING -- it is what keeps the
    # texture coherent and smooth. An earlier v0.3 build "corrected" this
    # to average original samples via a pre-fold snapshot, which produced
    # harsh comb filtering and noise. The cascade is preserved exactly.
    # The forward reference self[col + foldDistance] correctly reads the
    # original (not-yet-processed) sample. Do NOT "fix" this.
    # (v0.4: avgDiv is clamped >= 3 above, and the else branch now uses a
    # per-iteration uniform gain instead of per-sample random noise.)
    selectObject: result
    Formula: ~ if probMask < adaptiveThreshold 
        ... then (if col + foldDistance <= ncol and col - backwardDistance >= 1 
            ... then (self + self[col + foldDistance] + self[col - backwardDistance]) / avgDiv 
            ... else self fi) 
        ... else self * iterAmpGain fi
    
    # DEBUG: measure level AFTER, report per-iteration gain
    if debug_output
        selectObject: result
        peakAfter = Get absolute extremum: 0, 0, "None"
        rmsAfter = Get root-mean-square: 0, 0
        if peakBefore > 0
            peakGain = peakAfter / peakBefore
        else
            peakGain = 0
        endif
        if rmsBefore > 0
            rmsGain = rmsAfter / rmsBefore
        else
            rmsGain = 0
        endif
        appendInfoLine: "    [DEBUG] ", branchTaken$
        appendInfoLine: "    [DEBUG]   peak ", fixed$(peakBefore, 4), " -> ", fixed$(peakAfter, 4), "  (", fixed$(peakGain, 3), "x)"
        appendInfoLine: "    [DEBUG]   rms  ", fixed$(rmsBefore, 4), " -> ", fixed$(rmsAfter, 4), "  (", fixed$(rmsGain, 3), "x)"
        if peakAfter > 1.0
            appendInfoLine: "    [DEBUG]   *** peak exceeds 1.0 (", fixed$(peakAfter, 2), ") -- gain buildup ***"
        endif
    endif
endfor

# DEBUG: report the cumulative peak just before final Scale peak
if debug_output
    selectObject: result
    finalPeakRaw = Get absolute extremum: 0, 0, "None"
    finalRmsRaw = Get root-mean-square: 0, 0
    appendInfoLine: ""
    appendInfoLine: "[DEBUG] Before Scale peak: peak=", fixed$(finalPeakRaw, 3), "  rms=", fixed$(finalRmsRaw, 4)
    appendInfoLine: "[DEBUG] (peak > 1 can also result from intentional AMP gains; final stage only limits peaks above Scale_peak)"
    appendInfoLine: ""
endif

# === Peak Ceiling ===
# Uniform AMP gains must survive to the output; unconditional normalization
# would cancel them exactly because all processing above is linear.
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "None"
if resultPeak > scale_peak
    Scale peak: scale_peak
endif

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Original waveform           (left half, headline)
# Panel B: Folded waveform             (right half, headline)
# Panel C: Threshold evolution         (left half, signature)
# Panel D: Fold distances              (right half)
# Panel E: Light-grey 3-line summary   (suite standard)
###############################################################################
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##STOCHASTIC TIME FOLDING##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(fold_iterations) + " iterations"
        ... + "  |  threshold " + fixed$(thresholdLimitLow, 2) + "-" + fixed$(thresholdLimitHigh, 2)
        ... + "  |  avg divisor " + string$(fold_average_divisor)

    # ----------------------------------------------------------
    # PANEL A (left): ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18
    selectObject: original
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original  (" + fixed$(duration, 2) + " s)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL B (right): FOLDED WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18
    selectObject: result
    Colour: "{0.55, 0.45, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Folded  (" + string$(fold_iterations) + " passes)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL C (left): THRESHOLD EVOLUTION
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 2.40, 4.40
    Select inner viewport: 0.55, 4.00, 2.60, 4.28
    Axes: 0, fold_iterations + 1, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fold_iterations + 1, 0, 1.1

    # Threshold limit band (dotted)
    Colour: "{0.78, 0.78, 0.82}"
    Dotted line
    Draw line: 0, threshold_limit_min, fold_iterations + 1, threshold_limit_min
    Draw line: 0, threshold_limit_max, fold_iterations + 1, threshold_limit_max
    Solid line

    # Threshold evolution
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 2
    for f from 1 to fold_iterations
        if f > 1
            Draw line: f - 1, thresholds#[f - 1], f, thresholds#[f]
        endif
    endfor
    Line width: 1
    for f from 1 to fold_iterations
        Paint circle (mm): "{0.30, 0.50, 0.78}", f, thresholds#[f], 1.4
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Threshold evolution  (dotted = limits)"
    Font size: 6
    Text left: "yes", "Threshold"
    Text bottom: "yes", "Iteration"

    # ----------------------------------------------------------
    # PANEL D (right): FOLD DISTANCES
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.40, 4.40
    Select inner viewport: 4.55, 7.75, 2.60, 4.28
    maxDist = foldDistances#[1]
    for f from 2 to fold_iterations
        if foldDistances#[f] > maxDist
            maxDist = foldDistances#[f]
        endif
    endfor
    if maxDist < 0.001
        maxDist = 0.001
    endif
    Axes: 0, fold_iterations + 1, 0, maxDist * 1.2
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fold_iterations + 1, 0, maxDist * 1.2

    for f from 1 to fold_iterations
        Paint rectangle: "{0.70, 0.50, 0.50}", f - 0.35, f + 0.35, 0, foldDistances#[f]
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Fold distance per iteration"
    Font size: 6
    Text left: "yes", "Dist (ms)"
    Text bottom: "yes", "Iteration"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # v0.3 fix: explicit Axes 0,1,0,1 before Text(). v0.2's legend
    # inherited axes from the fold-distance panel.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.50, 5.20
    Select inner viewport: 0.55, 7.75, 4.57, 5.14
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + original_name$
        ... + "  |  " + string$(fold_iterations) + " iterations"
        ... + "  |  init threshold " + fixed$(initial_threshold, 2)
        ... + "  |  threshold limits " + fixed$(thresholdLimitLow, 2) + "-" + fixed$(thresholdLimitHigh, 2)
        ... + "  |  avg div " + string$(fold_average_divisor)

    Text: 0.02, "left", 0.28, "half",
        ... "Fold divisor range: " + fixed$(foldDivisorLow, 1) + "-" + fixed$(foldDivisorHigh, 1)
        ... + "  |  Backward div: " + string$(fold_backward_divisor)
        ... + "  |  Amp var: " + fixed$(ampLow, 2) + "-" + fixed$(ampHigh, 2)
        ... + "  |  Out: " + original_name$ + "_folded_" + presetName$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result