# ============================================================
# Praat AudioTools - Adaptive_Wave_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Voice-Calibrated Wave Shaper. Despite the filename and the
#   "Adaptive" branding inherited from earlier versions, this is
#   NOT a time-varying adaptive process. It performs a single
#   analysis pass over the input, measures global jitter (pitch
#   period variation) and global shimmer (amplitude variation),
#   and uses those two values to set fixed drive and fold-count
#   parameters that are then applied uniformly to every sample.
#
#   The "adaptive" framing is honest at the file level: a rough,
#   jittery source produces a more aggressive shaping setup than
#   a stable, clean source. Within a single source, the
#   processing is constant — there is no per-frame modulation.
#
#   Wave shaping pipeline:
#     1. Multiply by drive (raw level boost)
#     2. Apply N rounds of symmetric folding through ±threshold
#     3. Optional saturation (sin / tanh / none)
#     4. Final peak normalization
#
#   Folding behavior note: at high drive (>2x threshold) and
#   multiple folds, the operation chains reflections that move
#   samples chaotically within [-1, +1]. This is a wavefolder's
#   characteristic harmonic-rich sound, not a bug.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5:
#   - Removed the LTAS comparison panel (and its associated
#     Convert to mono / To Spectrum / To Ltas pipeline that ran
#     twice on every script invocation). The spectral diagnostic
#     was nice to have but added significant per-run latency on
#     a script users tweak iteratively. Speed now matches v0.2.
#   - Visualization simplified: Panel A = transfer function
#     (headline), Panel B = parameter report, Panel C = output
#     waveform, Panel D = summary bar. Standard suite layout
#     minus the spectral panel.
# Changelog v0.4:
#   - (REVERTED in v0.5): LTAS comparison panel.
# Changelog v0.4:
#   - Reverted v0.3's time-varying mode (was too slow to be
#     practical). Static analysis only.
#   - Fix (BUG): undefined pitch fallback. v0.2 substituted 0.5
#     (50% jitter, extreme!) when pitch detection failed —
#     causing noise/percussive sources to silently get the most
#     aggressive shaping. v0.4+ falls back to 0 (assume clean)
#     and emits a warning.
#   - Speed: combined the two fold formulas into one if/else
#     branch. v0.2 ran 2 * fold_count formula passes; v0.4+ runs
#     fold_count passes. ~2x speedup on the fold step.
#   - NEW: Saturation_type form parameter. Sin (v0.2) / Tanh
#     (cleaner) / None (pure folding only). Tanh produces
#     monotonic saturation without v0.2's amplitude-dependent
#     non-monotonicity.
#   - NEW: Fold_threshold exposed as form parameter
#     (was hardcoded to 0.6 in v0.2).
#   - Form syntax modernized: optionmenu uses colon.
#   - Visualization rewritten to suite 8x8 standard.
# Changelog v0.2:
#   - Actually analyzes jitter/shimmer from audio
#   - Fixed input check and selection syntax
#   - Added visualization
#   - Added transfer function display
# ============================================================

form Adaptive Wave Shaper v0.5
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Default
        option Gentle Saturation
        option Aggressive Drive
        option Fold Emphasis
        option Maximum Destruction
    
    comment === Base Parameters ===
    positive Base_drive 2.0
    positive Jitter_sensitivity 1.5
    comment (how much jitter affects drive)
    positive Shimmer_sensitivity 1.2
    comment (how much shimmer affects folding)
    
    comment === Wave Shaping ===
    optionmenu Saturation_type: 1
        option Sin blend (v0.2)
        option Tanh (cleaner)
        option None (folding only)
    positive Fold_threshold 0.6
    
    comment === Analysis ===
    positive Min_pitch_Hz 75
    positive Max_pitch_Hz 600
    
    comment === Output ===
    boolean Normalize 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
input_n_channels = Get number of channels

# === Apply Presets ===
if preset = 1
    presetName$ = "Default"
    base_drive = 2.0
    jitter_sensitivity = 1.5
    shimmer_sensitivity = 1.2
elsif preset = 2
    presetName$ = "Gentle"
    base_drive = 1.2
    jitter_sensitivity = 1.0
    shimmer_sensitivity = 0.8
elsif preset = 3
    presetName$ = "Aggressive"
    base_drive = 4.0
    jitter_sensitivity = 2.0
    shimmer_sensitivity = 1.8
elsif preset = 4
    presetName$ = "FoldEmphasis"
    base_drive = 2.5
    jitter_sensitivity = 1.2
    shimmer_sensitivity = 2.5
elsif preset = 5
    presetName$ = "Maximum"
    base_drive = 5.0
    jitter_sensitivity = 3.0
    shimmer_sensitivity = 3.0
endif

# Saturation display name
if saturation_type = 1
    satName$ = "Sin"
elsif saturation_type = 2
    satName$ = "Tanh"
else
    satName$ = "None"
endif

# === Info ===
writeInfoLine: "=== Adaptive Wave Shaper v0.5 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Saturation: ", satName$
appendInfoLine: "Fold threshold: ", fixed$(fold_threshold, 3)
appendInfoLine: ""

# ============================================================
# ANALYZE JITTER AND SHIMMER  (single global pass)
# ============================================================

appendInfoLine: "Analyzing voice quality metrics..."

selectObject: original

# Convert to mono for analysis (regardless of input channels)
mono = Convert to mono

# Pitch + PointProcess
selectObject: mono
To Pitch: 0.0, min_pitch_Hz, max_pitch_Hz
pitch = selected("Pitch")

selectObject: mono
plusObject: pitch
To PointProcess (cc)
pp = selected("PointProcess")

# Check whether pitch detection found enough pulses
pitch_detected = 1
selectObject: pp
nPulses = Get number of points
if nPulses < 4
    pitch_detected = 0
endif

if pitch_detected = 1
    selectObject: pp
    jitter_local = Get jitter (local): 0, 0, 0.0001, 0.02, 1.3
    if jitter_local = undefined
        jitter_local = 0
        pitch_detected = 0
    endif
    
    selectObject: mono
    plusObject: pp
    shimmer_local = Get shimmer (local): 0, 0, 0.0001, 0.02, 1.3, 1.6
    if shimmer_local = undefined
        shimmer_local = 0
    endif
else
    # FIX v0.4+: undefined pitch falls back to 0 (clean), not 0.5.
    # v0.2 silently treated unpitched audio (noise, percussion) as
    # 50% jitter, triggering maximum aggression on these sources.
    jitter_local = 0
    shimmer_local = 0
    appendInfoLine: "  No detectable pitch — falling back to clean shaping (drive only)"
endif

jitter_percent = jitter_local * 100
shimmer_percent = shimmer_local * 100

appendInfoLine: "Jitter (local): ", fixed$(jitter_percent, 2), "%"
appendInfoLine: "Shimmer (local): ", fixed$(shimmer_percent, 2), "%"
appendInfoLine: ""

# Cleanup analysis objects
removeObject: mono, pitch, pp

# ============================================================
# CALCULATE CALIBRATED PARAMETERS
# ============================================================

# Drive increases with jitter (pitch instability -> more drive)
adaptive_drive = base_drive * (1 + (jitter_percent * jitter_sensitivity / 100))

# Fold count increases with shimmer (amplitude instability -> more folds)
adaptive_fold = 1 + round(shimmer_percent * shimmer_sensitivity / 20)

# Limit parameters to safe ranges
if adaptive_drive < 0.5
    adaptive_drive = 0.5
endif
if adaptive_drive > 8.0
    adaptive_drive = 8.0
endif
if adaptive_fold < 1
    adaptive_fold = 1
endif
if adaptive_fold > 8
    adaptive_fold = 8
endif

appendInfoLine: "Calibrated drive: ", fixed$(adaptive_drive, 2)
appendInfoLine: "Calibrated folds: ", adaptive_fold
appendInfoLine: ""

# ============================================================
# APPLY WAVE SHAPING
# ============================================================

appendInfoLine: "Applying wave shaping..."

selectObject: original
result = Copy: original_name$ + "_shaped_" + presetName$

# 1. Drive
selectObject: result
Formula: ~ self * adaptive_drive

# 2. Wave folding (combined one-formula version, ~2x faster than v0.2)
for i from 1 to adaptive_fold
    selectObject: result
    Formula: ~ if self > fold_threshold then fold_threshold - (self - fold_threshold)
        ... else if self < -fold_threshold then -fold_threshold - (self + fold_threshold)
        ... else self fi fi
endfor

# 3. Saturation
if saturation_type = 1
    # Sin blend (v0.2 behavior — non-monotonic at low levels)
    selectObject: result
    Formula: ~ sin(self * 2) * 0.3 + self * 0.7
elsif saturation_type = 2
    # Tanh — clean monotonic saturation
    selectObject: result
    Formula: ~ tanh(self * 1.5)
endif
# Type 3 = None: folding only

# 4. Normalize
if normalize
    selectObject: result
    Scale peak: 0.9
endif

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard, minus LTAS panel)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##VOICE-CALIBRATED WAVE SHAPER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(adaptive_drive, 2)
        ... + "  |  Folds: " + string$(adaptive_fold)
        ... + "  |  Sat: " + satName$
        ... + "  |  Jitter: " + fixed$(jitter_percent, 2) + "%"
        ... + "  |  Shimmer: " + fixed$(shimmer_percent, 2) + "%"
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # The defining diagnostic for a wave shaper.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.5, 1.5, -1.5, 1.5
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5
    
    # y=x reference (no shaping)
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    
    # Fold threshold lines
    Colour: "{0.55, 0.78, 0.55}"
    Dotted line
    Draw line: -1.5, fold_threshold, 1.5, fold_threshold
    Draw line: -1.5, -fold_threshold, 1.5, -fold_threshold
    Solid line
    Font size: 5
    Text: -1.4, "left", fold_threshold, "bottom", " thresh"
    Text: -1.4, "left", -fold_threshold, "top", " -thresh"
    
    # Draw transfer function with current calibrated params
    Colour: "{0.80, 0.40, 0.40}"
    Line width: 2
    nPoints = 200
    prevX = -1.2
    prevY = -1.2 * adaptive_drive
    for f from 1 to adaptive_fold
        if prevY > fold_threshold
            prevY = fold_threshold - (prevY - fold_threshold)
        endif
        if prevY < -fold_threshold
            prevY = -fold_threshold - (prevY + fold_threshold)
        endif
    endfor
    if saturation_type = 1
        prevY = sin(prevY * 2) * 0.3 + prevY * 0.7
    elsif saturation_type = 2
        prevY = tanh(prevY * 1.5)
    endif
    if prevY > 1.4
        prevY = 1.4
    endif
    if prevY < -1.4
        prevY = -1.4
    endif
    
    for p from 2 to nPoints
        x = -1.2 + (p - 1) / (nPoints - 1) * 2.4
        y = x * adaptive_drive
        for f from 1 to adaptive_fold
            if y > fold_threshold
                y = fold_threshold - (y - fold_threshold)
            endif
            if y < -fold_threshold
                y = -fold_threshold - (y + fold_threshold)
            endif
        endfor
        if saturation_type = 1
            y = sin(y * 2) * 0.3 + y * 0.7
        elsif saturation_type = 2
            y = tanh(y * 1.5)
        endif
        if y > 1.4
            y = 1.4
        endif
        if y < -1.4
            y = -1.4
        endif
        Draw line: prevX, prevY, x, y
        prevX = x
        prevY = y
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # Compact text panel showing the analysis-derived parameters.
    # Replaces the LTAS panel (which was too slow on every run).
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    # Section: Voice quality
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.92, "half", "Voice quality (analyzed):"
    
    Font size: 11
    Colour: "{0.30, 0.45, 0.78}"
    Text: 0.10, "left", 0.83, "half", "Jitter:  " + fixed$(jitter_percent, 2) + " %"
    Text: 0.10, "left", 0.75, "half", "Shimmer: " + fixed$(shimmer_percent, 2) + " %"
    
    if pitch_detected = 0
        Font size: 7
        Colour: "{0.78, 0.45, 0.30}"
        Text: 0.10, "left", 0.68, "half", "(no pitch detected — clean fallback)"
    endif
    
    # Section: Calibrated parameters
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.58, "half", "Calibrated parameters:"
    
    Font size: 11
    Colour: "{0.80, 0.40, 0.40}"
    Text: 0.10, "left", 0.49, "half", "Drive:   " + fixed$(adaptive_drive, 2) + " x"
    Colour: "{0.40, 0.65, 0.40}"
    Text: 0.10, "left", 0.41, "half", "Folds:   " + string$(adaptive_fold)
    
    # Section: Sensitivities
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.27, "half", "Sensitivities:"
    
    Font size: 8
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.18, "half", "Jitter sens:  " + fixed$(jitter_sensitivity, 2)
    Text: 0.10, "left", 0.10, "half", "Shimmer sens: " + fixed$(shimmer_sensitivity, 2)
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Transfer function (input -> output)"
    Text: 6.10, "centre", 7.30, "half", "Analysis report"
    
    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: result
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: result
    if nResultCh = 1
        Colour: "{0.20, 0.55, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if nResultCh >= 2
            selectObject: result
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        Text top: "no", "Output  (blue=L  orange=R)"
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + original_name$
        ... + "  |  Jitter: " + fixed$(jitter_percent, 2) + "%"
        ... + "  |  Shimmer: " + fixed$(shimmer_percent, 2) + "%"
        ... + "  |  Drive: " + fixed$(adaptive_drive, 2)
        ... + "  |  Folds: " + string$(adaptive_fold)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Saturation: " + satName$
        ... + "  |  Threshold: " + fixed$(fold_threshold, 2)
        ... + "  |  J-sens: " + fixed$(jitter_sensitivity, 1)
        ... + "  |  S-sens: " + fixed$(shimmer_sensitivity, 1)
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
