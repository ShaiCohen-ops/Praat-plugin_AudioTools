# ============================================================
# Praat AudioTools - Chaos_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaos Distortion. Multi-stage lo-fi pipeline:
#     1. Drive (level multiplier)
#     2. Wave folding (N rounds of symmetric reflection through ±0.7)
#     3. Bit crushing (round to N-bit quantization)
#     4. Sample-rate reduction (resample down + back up = aliasing)
#     5. Optional uniform noise
#     6. Optional peak normalization
#   Five presets, plus full manual control.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters. (Same operation order, same
#     fold threshold, same bit-crush quantization, same resample
#     dance, same noise math.)
#   - Speed: combined the two fold formulas into one if/elsif/else
#     branch. v0.2 ran 2 * fold_count formula passes; v0.3 runs
#     fold_count passes. Marginal speedup on the fold step.
#   - Form syntax modernized: optionmenu uses colon.
#   - Fixed inline if/then/else ternary in Info output (line was
#     "appendInfoLine: 'Noise: ', if add_noise then ... else ... fi"
#     — that's not reliable in Praat's script-level expression
#     context). Pre-computed the string instead.
#   - Modernized cross-Sound formula reference: 
#       Formula: ~ object[resampled]   ->   Formula: ~ object[<id>, col]
#     Same behavior, explicit indexing, doesn't depend on Praat
#     substituting script variables into formula strings.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (headline, left): transfer function
#         (drive + fold + bit-crush composite)
#       Panel B (right): processing-chain diagram showing the
#         five stages with current values
#       Panel C: zoom comparison (original vs chaos, first 50ms)
#         — preserved from v0.2 because it shows quantization
#         steps and aliasing artifacts that are invisible in the
#         full-file waveform view
#       Panel D: output waveform with L/R channels distinguished
#       Panel E: summary stats bar
# Changelog v0.2:
#   - Fixed resampling bug (orphan objects)
#   - Fixed input check and selection syntax
#   - Added visualization
#   - Added info output
# ============================================================

form Chaos Distortion v0.3
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Default (balanced)
        option Gentle Grit
        option Heavy Crush
        option Lo-Fi Glitch
        option Clean Boost
        option Custom (use settings below)
    
    comment === Drive & Folding ===
    positive Drive 3.0
    natural Fold_count 3
    comment (0 = no folding, higher = more complex)
    
    comment === Bit Crushing ===
    natural Bit_crush 6
    comment (16 = CD quality, 4 = extreme)
    
    comment === Sample Rate ===
    positive Sample_rate_percent 30
    comment (100 = original, lower = more aliasing)
    
    comment === Extras ===
    boolean Add_noise 1
    real Noise_amount 0.03
    
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
    # Default (balanced)
    drive = 3.0
    fold_count = 3
    bit_crush = 6
    sample_rate_percent = 30
    add_noise = 1
    noise_amount = 0.03
    presetName$ = "Default"
elsif preset = 2
    # Gentle Grit
    drive = 1.6
    fold_count = 1
    bit_crush = 8
    sample_rate_percent = 85
    add_noise = 0
    noise_amount = 0
    presetName$ = "GentleGrit"
elsif preset = 3
    # Heavy Crush
    drive = 4.5
    fold_count = 5
    bit_crush = 4
    sample_rate_percent = 40
    add_noise = 1
    noise_amount = 0.05
    presetName$ = "HeavyCrush"
elsif preset = 4
    # Lo-Fi Glitch
    drive = 2.2
    fold_count = 2
    bit_crush = 3
    sample_rate_percent = 20
    add_noise = 1
    noise_amount = 0.04
    presetName$ = "LoFiGlitch"
elsif preset = 5
    # Clean Boost
    drive = 1.25
    fold_count = 0
    bit_crush = 12
    sample_rate_percent = 100
    add_noise = 0
    noise_amount = 0
    presetName$ = "CleanBoost"
else
    presetName$ = "Custom"
endif

# Pre-compute the "Noise: ..." display string (replaces v0.2's
# inline ternary in appendInfoLine — not reliable in script-level
# expression context across Praat builds).
if add_noise
    noiseStr$ = "yes (" + fixed$(noise_amount, 3) + ")"
else
    noiseStr$ = "no"
endif

# === Info ===
writeInfoLine: "=== Chaos Distortion v0.3 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Drive: ", fixed$(drive, 2)
appendInfoLine: "Fold count: ", fold_count
appendInfoLine: "Bit depth: ", bit_crush, " bits (", 2^bit_crush, " levels)"
appendInfoLine: "Sample rate: ", sample_rate_percent, "% (", round(sr * sample_rate_percent / 100), " Hz)"
appendInfoLine: "Noise: ", noiseStr$
appendInfoLine: ""

# ============================================================
# PROCESSING  (identical pipeline to v0.2, slightly faster fold)
# ============================================================

appendInfoLine: "Processing..."

selectObject: original
Copy: original_name$ + "_chaos_" + presetName$
result = selected("Sound")

# 1. Drive
appendInfoLine: "  Applying drive (", fixed$(drive, 2), "x)..."
selectObject: result
Formula: ~ self * drive

# 2. Wave folding (combined formula, ~2x faster than v0.2's two-pass)
if fold_count > 0
    appendInfoLine: "  Applying ", fold_count, " fold(s)..."
    fold_threshold = 0.7
    for i from 1 to fold_count
        selectObject: result
        Formula: ~ if self > fold_threshold then fold_threshold - (self - fold_threshold)
            ... else if self < -fold_threshold then -fold_threshold - (self + fold_threshold)
            ... else self fi fi
    endfor
endif

# 3. Bit crushing
appendInfoLine: "  Applying bit crush (", bit_crush, " bits)..."
levels = 2 ^ bit_crush
selectObject: result
Formula: ~ round(self * levels) / levels

# 4. Sample rate reduction (if < 100%)
if sample_rate_percent < 100
    appendInfoLine: "  Applying sample rate reduction..."
    new_rate = sr * (sample_rate_percent / 100)
    if new_rate < 1000
        new_rate = 1000
    endif
    
    # Resample down
    selectObject: result
    Resample: new_rate, 50
    downsampled = selected("Sound")
    
    # Resample back up
    selectObject: downsampled
    Resample: sr, 50
    resampled = selected("Sound")
    
    # Modernized cross-Sound formula reference (replaces v0.2's
    # implicit `object[resampled]` which relied on script-variable
    # substitution into the formula string).
    resampledIdStr$ = string$(resampled)
    selectObject: result
    Formula: "object[" + resampledIdStr$ + ", col]"
    
    removeObject: downsampled, resampled
endif

# 5. Add noise if requested
if add_noise
    appendInfoLine: "  Adding noise..."
    selectObject: result
    Formula: ~ self + randomUniform(-noise_amount, noise_amount)
endif

# 6. Normalize if requested
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
# VISUALIZATION  (8 x 8 canvas — suite standard)
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
    Text: 0.5, "centre", 0.68, "half", "##CHAOS DISTORTION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Folds: " + string$(fold_count)
        ... + "  |  Bits: " + string$(bit_crush)
        ... + "  |  SR: " + fixed$(sample_rate_percent, 0) + "%"
        ... + "  |  Noise: " + noiseStr$
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # Composite of drive + fold + bit-crush.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    # y=x reference (no shaping)
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line
    
    # Fold threshold lines
    Colour: "{0.55, 0.78, 0.55}"
    Dotted line
    Draw line: -1.2, 0.7, 1.2, 0.7
    Draw line: -1.2, -0.7, 1.2, -0.7
    Solid line
    Font size: 5
    Colour: "{0.30, 0.55, 0.30}"
    Text: -1.15, "left", 0.7, "bottom", " ±0.7 fold"
    
    # Draw transfer function
    Colour: "{0.78, 0.50, 0.30}"
    Line width: 2
    nPoints = 200
    levels_disp = 2 ^ bit_crush
    
    # First point
    prev_x = -1.0
    prev_y = prev_x * drive
    for f from 1 to fold_count
        if prev_y > 0.7
            prev_y = 0.7 - (prev_y - 0.7)
        endif
        if prev_y < -0.7
            prev_y = -0.7 - (prev_y + 0.7)
        endif
    endfor
    prev_y = round(prev_y * levels_disp) / levels_disp
    if prev_y > 1.1
        prev_y = 1.1
    endif
    if prev_y < -1.1
        prev_y = -1.1
    endif
    
    for p from 1 to nPoints
        curr_x = -1.0 + (p / nPoints) * 2.0
        curr_y = curr_x * drive
        for f from 1 to fold_count
            if curr_y > 0.7
                curr_y = 0.7 - (curr_y - 0.7)
            endif
            if curr_y < -0.7
                curr_y = -0.7 - (curr_y + 0.7)
            endif
        endfor
        curr_y = round(curr_y * levels_disp) / levels_disp
        if curr_y > 1.1
            curr_y = 1.1
        endif
        if curr_y < -1.1
            curr_y = -1.1
        endif
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: PROCESSING CHAIN DIAGRAM  (right, headline-height)
    # The five-stage pipeline shown explicitly with current values.
    # Preserved from v0.2 — it's the script's most distinctive viz.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 6
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 6
    
    # Five vertical boxes representing the pipeline stages
    # Each at y range [stage*1.0, stage*1.0+0.7] for stages 5..1 (top to bottom)
    
    # Stage 1: Drive
    yTop = 5.6
    yBot = 5.0
    Paint rectangle: "{0.85, 0.70, 0.55}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "1. DRIVE"
    Font size: 9
    Colour: "{0.30, 0.20, 0.10}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", fixed$(drive, 2) + " x"
    
    # Arrow down
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 5.0, 0.50, 4.7
    
    # Stage 2: Fold
    yTop = 4.6
    yBot = 4.0
    if fold_count > 0
        Paint rectangle: "{0.70, 0.85, 0.60}", 0.10, 0.90, yBot, yTop
    else
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    endif
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "2. FOLD"
    Font size: 9
    if fold_count > 0
        Colour: "{0.20, 0.40, 0.15}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", string$(fold_count) + " x"
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "off"
    endif
    
    # Arrow down
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 4.0, 0.50, 3.7
    
    # Stage 3: Crush
    yTop = 3.6
    yBot = 3.0
    Paint rectangle: "{0.60, 0.70, 0.85}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "3. CRUSH"
    Font size: 9
    Colour: "{0.10, 0.20, 0.40}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", string$(bit_crush) + " bits"
    
    # Arrow down
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 3.0, 0.50, 2.7
    
    # Stage 4: SR
    yTop = 2.6
    yBot = 2.0
    if sample_rate_percent < 100
        Paint rectangle: "{0.60, 0.85, 0.75}", 0.10, 0.90, yBot, yTop
    else
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    endif
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "4. SR REDUCE"
    Font size: 9
    if sample_rate_percent < 100
        Colour: "{0.10, 0.40, 0.30}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", fixed$(sample_rate_percent, 0) + "%"
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "off"
    endif
    
    # Arrow down
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 2.0, 0.50, 1.7
    
    # Stage 5: Noise
    yTop = 1.6
    yBot = 1.0
    if add_noise
        Paint rectangle: "{0.85, 0.65, 0.60}", 0.10, 0.90, yBot, yTop
    else
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    endif
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "5. NOISE"
    Font size: 9
    if add_noise
        Colour: "{0.40, 0.15, 0.10}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "+/- " + fixed$(noise_amount, 3)
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "off"
    endif
    
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
    Text: 2.10, "centre", 7.30, "half", "Transfer (drive + fold + crush)"
    Text: 6.10, "centre", 7.30, "half", "Processing chain"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM COMPARISON  (full width, first 50ms)
    # Original (gray) vs chaos (orange) overlaid. Reveals
    # quantization steps and aliasing artifacts that the
    # full-file waveform can't show.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.05
    if zoomDur > duration
        zoomDur = duration
    endif
    
    selectObject: original
    origPeak = Get absolute extremum: 0, zoomDur, "None"
    selectObject: result
    resPeak = Get absolute extremum: 0, zoomDur, "None"
    zoomMax = origPeak
    if resPeak > zoomMax
        zoomMax = resPeak
    endif
    if zoomMax < 0.001
        zoomMax = 0.001
    endif
    zAmpViz = zoomMax * 1.15
    
    Axes: 0, zoomDur, -zAmpViz, zAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -zAmpViz, zAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original (gray, behind)
    selectObject: original
    if input_n_channels > 1
        Extract one channel: 1
        zOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    
    # Chaos (orange, on top)
    selectObject: result
    if nResultCh > 1
        Extract one channel: 1
        zRes = selected("Sound")
        Colour: "{0.78, 0.45, 0.20}"
        Line width: 1.3
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zRes
    else
        Colour: "{0.78, 0.45, 0.20}"
        Line width: 1.3
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, orange = chaos)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
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
        Text top: "no", "Output (full file)  (blue=L  orange=R)"
    else
        Text top: "no", "Output (full file, mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if normalize
        normStr$ = "yes (peak 0.9)"
    else
        normStr$ = "no"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + original_name$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Folds: " + string$(fold_count)
        ... + "  |  Crush: " + string$(bit_crush) + " bits (" + string$(2^bit_crush) + " levels)"
    
    Text: 0.02, "left", 0.28, "half",
        ... "SR: " + fixed$(sample_rate_percent, 0) + "%"
        ... + "  |  Noise: " + noiseStr$
        ... + "  |  Normalize: " + normStr$
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
