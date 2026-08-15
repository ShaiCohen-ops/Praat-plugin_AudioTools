# ============================================================
# Praat AudioTools - Polyrhythms_From_Dots.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Polyrhythm generator and visualizer. Creates two rhythmic
#   lines with different numbers of evenly-spaced beats over
#   a common duration, demonstrating metric relationships like
#   3:4, 5:7, etc.
#
#   Visual representation shows dots on two lines; audio uses
#   different pitches for each line with stereo separation.
#
#   v0.4 adds a Repeat_count form field that concatenates the
#   single-bar pattern N times for an N-bar output.
#
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5:
#   - Visualization redesigned around the actual algorithm:
#       A common LCM lattice and exact dot placement
#       B dot kernel and stereo routing
#       C bar assembly and repetition
#       D measured stereo output as final confirmation only
#   - Coincidences are now detected exactly with integer arithmetic,
#     not with an arbitrary 10 ms tolerance.
#   - Main form shortened; dot duration, sample rate and output peak moved
#     to an optional Edit details page.
#   - Removed the old global Amplitude control: it was mathematically
#     cancelled by fixed peak normalization and therefore had no effect.
#   - Added sample-rate/Nyquist and minimum-kernel validation.
#   - Added reduced-ratio, exact-grid and output QC reporting.
#   - Spectrogram removed from the visualization because it described
#     the result rather than the polyrhythmic construction process.
# Changelog v0.4:
#   - NEW: Repeat_count form field (default 1). Concatenates the
#     single-bar pattern N times to produce an N-bar output.
#     Implementation uses a single `Concatenate` call on a
#     selection of N copies — O(N) work, not O(N^2) iterative.
#     Output filename gets `_xN` suffix when N > 1.
#   - Audio output is bit-identical to v0.3 when Repeat_count = 1.
#     For N > 1, the output is N copies of the same v0.3 single-
#     bar audio end-to-end (no crossfade, no time-warp). The
#     Scale peak is applied to the single bar BEFORE concatenation,
#     so the repeated output has the same peak as the single bar.
#   - Visualization: Panel A (dot diagram) keeps showing ONE bar
#     because that IS the pattern. Panel C (stereo waveform) and
#     Panel D (spectrogram) show the full repeated output. Title
#     bar and Panel E summary mention the repeat count.
# Changelog v0.3:
#   - Suite 8x8 visualization, Show_spectrogram opt-in,
#     parameter report with GCD/LCM/coincidences,
#     `optionmenu Preset:` colon syntax, dropped decorative
#     comment lines, computeGcd procedure.
# Changelog v0.2:
#   - Fixed output deletion bug, fixed division by zero,
#     added envelope, added visualization
# ============================================================

form Polyrhythms From Dots v0.5
    optionmenu Preset 1
        option Custom
        option 3 vs 4 (Waltz)
        option 5 vs 7 (Complex)
        option 2 vs 3 (Simple)
        option 4 vs 5 (Jazz)
        option 3 vs 5 (African)
        option 7 vs 8 (Dense)
        option 4 vs 7 (Progressive)
        option 5 vs 9 (Math Rock)
    integer Dots_line_1 5 (= top line, left-panned)
    integer Dots_line_2 7 (= bottom line, right-panned)
    positive Bar_duration_s 2.0
    natural Repeat_count 1
    positive Base_frequency_Hz 220
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
dot_duration_s = 0.05
sample_rate_Hz = 44100
amplitude = 1.0
output_peak = 0.9

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    dots_line_1 = 3
    dots_line_2 = 4
    bar_duration_s = 3.0
    base_frequency_Hz = 196
    preset_name$ = "3vs4_Waltz"
elsif preset = 3
    dots_line_1 = 5
    dots_line_2 = 7
    bar_duration_s = 3.5
    base_frequency_Hz = 220
    preset_name$ = "5vs7_Complex"
elsif preset = 4
    dots_line_1 = 2
    dots_line_2 = 3
    bar_duration_s = 2.0
    base_frequency_Hz = 165
    preset_name$ = "2vs3_Simple"
elsif preset = 5
    dots_line_1 = 4
    dots_line_2 = 5
    bar_duration_s = 4.0
    base_frequency_Hz = 262
    preset_name$ = "4vs5_Jazz"
elsif preset = 6
    dots_line_1 = 3
    dots_line_2 = 5
    bar_duration_s = 2.5
    base_frequency_Hz = 147
    preset_name$ = "3vs5_African"
elsif preset = 7
    dots_line_1 = 7
    dots_line_2 = 8
    bar_duration_s = 4.0
    base_frequency_Hz = 330
    dot_duration_s = 0.03
    preset_name$ = "7vs8_Dense"
elsif preset = 8
    dots_line_1 = 4
    dots_line_2 = 7
    bar_duration_s = 3.0
    base_frequency_Hz = 196
    preset_name$ = "4vs7_Progressive"
elsif preset = 9
    dots_line_1 = 5
    dots_line_2 = 9
    bar_duration_s = 5.0
    base_frequency_Hz = 220
    dot_duration_s = 0.04
    preset_name$ = "5vs9_MathRock"
endif

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT DETAILS PAGE
# ---------------------------------------------------------------------------
if edit_details
    beginPause: "Polyrhythms From Dots v0.5 - Dot / Audio Details"
        positive: "Dot duration (s)", dot_duration_s
        integer: "Sample rate (Hz)", sample_rate_Hz
        real: "Output peak (0..1)", output_peak
    endPause: "Run", 1
endif

# === Validate Parameters ===
if dots_line_1 < 1 or dots_line_2 < 1
    exitScript: "Dots per line must be at least 1."
endif
if repeat_count < 1
    exitScript: "Repeat count must be at least 1."
endif
if repeat_count > 64
    exitScript: "Repeat count must not exceed 64."
endif
if sample_rate_Hz < 1000
    exitScript: "Sample rate must be at least 1000 Hz."
endif
if dot_duration_s * sample_rate_Hz < 4
    exitScript: "Dot duration must span at least 4 samples at the selected sample rate."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be greater than 0 and no more than 1."
endif

nyquist_Hz = sample_rate_Hz / 2
freq2 = base_frequency_Hz * 1.5
if freq2 >= 0.95 * nyquist_Hz
    exitScript: "Highest oscillator frequency (", fixed$(freq2, 1), " Hz) must stay below 95% of Nyquist (", fixed$(0.95 * nyquist_Hz, 1), " Hz). Lower Base frequency or raise Sample rate."
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# Calculate spacing
spacing1 = bar_duration_s / dots_line_1
spacing2 = bar_duration_s / dots_line_2
smallestSpacing_s = min(spacing1, spacing2)
if smallestSpacing_s * sample_rate_Hz < 1
    exitScript: "The densest dot spacing is shorter than one sample. Reduce Dots per line, increase Bar duration, or raise Sample rate."
endif

# Compute GCD and LCM of the two dot counts (for the parameter report)
@computeGcd: dots_line_1, dots_line_2
gcdDots = computeGcd.result
lcmDots = (dots_line_1 * dots_line_2) / gcdDots

# === Info ===
writeInfoLine: "=== Polyrhythms From Dots v0.5 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Rhythm: ", dots_line_1, " vs ", dots_line_2
appendInfoLine: "GCD: ", gcdDots, "  |  LCM: ", lcmDots
appendInfoLine: "Bar duration: ", bar_duration_s, " s  |  Repeats: ", repeat_count
appendInfoLine: "Line 1: ", base_frequency_Hz, " Hz, spacing ", fixed$(spacing1, 3), " s"
appendInfoLine: "Line 2: ", freq2, " Hz, spacing ", fixed$(spacing2, 3), " s"
appendInfoLine: ""

# === Store dot times ===
for i to dots_line_1
    dotTime1[i] = (i - 1) * spacing1
endfor

for i to dots_line_2
    dotTime2[i] = (i - 1) * spacing2
endfor

# === Create Stereo Sound (one bar) ===
appendInfoLine: "Synthesizing polyrhythm (one bar)..."

leftSound = Create Sound from formula: "left_" + uid$, 1, 0, bar_duration_s, sample_rate_Hz, "0"
rightSound = Create Sound from formula: "right_" + uid$, 1, 0, bar_duration_s, sample_rate_Hz, "0"

# === Synthesize Line 1 (left-panned, lower pitch) ===
for i to dots_line_1
    t = dotTime1[i]
    d = dot_duration_s
    if t + d > bar_duration_s
        d = bar_duration_s - t
    endif
    
    if d > 0
        t$ = fixed$(t, 6)
        d$ = fixed$(d, 6)
        f$ = fixed$(base_frequency_Hz, 1)
        a$ = fixed$(amplitude, 3)
        
        # Envelope: raised cosine (no clicks)
        # Sound: sine wave
        formula$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + a$ + " * sin(twoPi * " + f$ + " * (x - " + t$ + ")) * (1 - cos(twoPi * (x - " + t$ + ") / " + d$ + ")) / 2 else 0 fi"
        
        # Line 1 goes mostly to left
        selectObject: leftSound
        Formula: "self + 0.9 * (" + formula$ + ")"
        
        selectObject: rightSound
        Formula: "self + 0.3 * (" + formula$ + ")"
    endif
endfor

# === Synthesize Line 2 (right-panned, higher pitch) ===
for i to dots_line_2
    t = dotTime2[i]
    d = dot_duration_s
    if t + d > bar_duration_s
        d = bar_duration_s - t
    endif
    
    if d > 0
        t$ = fixed$(t, 6)
        d$ = fixed$(d, 6)
        f$ = fixed$(freq2, 1)
        a$ = fixed$(amplitude, 3)
        
        formula$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + a$ + " * sin(twoPi * " + f$ + " * (x - " + t$ + ")) * (1 - cos(twoPi * (x - " + t$ + ") / " + d$ + ")) / 2 else 0 fi"
        
        # Line 2 goes mostly to right
        selectObject: leftSound
        Formula: "self + 0.3 * (" + formula$ + ")"
        
        selectObject: rightSound
        Formula: "self + 0.9 * (" + formula$ + ")"
    endif
endfor

# === Combine to Stereo ===
selectObject: leftSound
plusObject: rightSound
outputSound = Combine to stereo

# Single-bar name; will be re-renamed below if repeated
baseName$ = "polyrhythm_" + string$(dots_line_1) + "vs" + string$(dots_line_2)
Rename: baseName$

removeObject: leftSound, rightSound

# === Normalize the SINGLE BAR (before any repetition) ===
# Scaling here means each repeated bar has identical peak.
# Scaling after concatenation would equalize the whole repeated
# block, which has the same peak as the single bar anyway since
# the bars are bit-identical copies.
selectObject: outputSound
Scale peak: output_peak

# === Repeat the pattern N times (if requested) ===
if repeat_count > 1
    appendInfoLine: "Repeating pattern ", repeat_count, " times..."
    
    # Create N-1 copies of the single bar
    for r from 2 to repeat_count
        selectObject: outputSound
        Copy: "bar_copy_" + string$(r) + "_" + uid$
        barCopies[r] = selected("Sound")
    endfor
    
    # Build a multi-object selection: outputSound + all copies, in order
    selectObject: outputSound
    for r from 2 to repeat_count
        plusObject: barCopies[r]
    endfor
    
    # Concatenate in one call — O(N) work, not iterative O(N^2)
    Concatenate
    newOutput = selected("Sound")
    
    # Remove the original single-bar outputSound and all copies
    removeObject: outputSound
    for r from 2 to repeat_count
        removeObject: barCopies[r]
    endfor
    
    outputSound = newOutput
    selectObject: outputSound
    Rename: baseName$ + "_x" + string$(repeat_count)
endif

# Capture stats for visualization
selectObject: outputSound
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# Exact coincidences of two equal-division grids occur GCD(n1,n2) times
# over the half-open bar [0,T).  Use the number-theoretic result directly
# rather than an O(n1*n2) pairwise scan.
coincidenceCount = gcdDots

reduced1 = dots_line_1 / gcdDots
reduced2 = dots_line_2 / gcdDots
latticeStep_s = bar_duration_s / lcmDots
selectObject: outputSound
finalRms = Get root-mean-square: 0, 0

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Total duration: ", fixed$(finalDur, 2), " s (", repeat_count, " x ", fixed$(bar_duration_s, 2), " s)"

# ==============================================================================
# Procedure: computeGcd  (Euclidean algorithm)
# Result lives in computeGcd.result
# ==============================================================================
procedure computeGcd: .a, .b
    while .b > 0
        .temp = .b
        .b = .a mod .b
        .a = .temp
    endwhile
    .result = .a
endproc

# ==============================================================================
# Procedure: drawVisualization  (8 x 8 process-oriented canvas)
# ==============================================================================
procedure drawVisualization

    Erase all
    Black
    Plain line

    if repeat_count > 1
        repeatStr$ = "x" + string$(repeat_count) + " bars"
    else
        repeatStr$ = "single bar"
    endif

    # Choose a readable thinning factor for very fine LCM lattices.
    gridStride = ceiling(lcmDots / 32)
    if gridStride < 1
        gridStride = 1
    endif

    # ------------------------------------------------------------------
    # HEADER / PROCESS FLOW
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.78
    Select inner viewport: 0.30, 7.70, 0.08, 0.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.96}", 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.74, "half", "##POLYRHYTHMS FROM DOTS##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.38}"
    Text: 0.5, "centre", 0.30, "half",
        ... "n1:n2 -> delta1=T/n1, delta2=T/n2 -> exact LCM lattice -> windowed tones -> stereo sum -> peak scale -> repeat bars -> output"

    # ------------------------------------------------------------------
    # PANEL A: COMMON TEMPORAL LATTICE + ACTUAL DOT LOCATIONS
    # ------------------------------------------------------------------
    Select outer viewport: 0, 4.20, 0.88, 3.65
    Select inner viewport: 0.60, 4.00, 1.18, 3.45
    Axes: 0, bar_duration_s, -0.20, 1.20
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, bar_duration_s, -0.20, 1.20

    # LCM grid: every event of both lines falls on this lattice.
    Colour: "{0.88, 0.88, 0.90}"
    Line width: 1
    for k from 0 to lcmDots
        if k mod gridStride = 0
            gx = k * latticeStep_s
            Draw line: gx, -0.10, gx, 1.08
        endif
    endfor

    # Exact coincidences: k*T/GCD, k = 0..GCD-1.
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1.5
    for .k from 0 to gcdDots - 1
        .tx = .k * bar_duration_s / gcdDots
        Draw line: .tx, 0.18, .tx, 0.82
    endfor

    Colour: "{0.20, 0.50, 0.82}"
    Line width: 1
    Draw line: 0, 0.85, bar_duration_s, 0.85
    for .i to dots_line_1
        Paint circle (mm): "{0.20, 0.50, 0.82}", dotTime1[.i], 0.85, 2.8
    endfor

    Colour: "{0.82, 0.50, 0.20}"
    Draw line: 0, 0.15, bar_duration_s, 0.15
    for .i to dots_line_2
        Paint circle (mm): "{0.82, 0.50, 0.20}", dotTime2[.i], 0.15, 2.8
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Lines"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 4.20, 0.80, 1.12
    Select inner viewport: 0.60, 4.00, 0.82, 1.08
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    if gridStride = 1
        gridNote$ = "all lattice lines shown"
    else
        gridNote$ = "display every " + string$(gridStride) + " lattice cells"
    endif
    Text: 0.5, "centre", 0.5, "half", "A  Common lattice: delta = T / LCM; purple = exact coincidences; " + gridNote$

    # ------------------------------------------------------------------
    # PANEL B: DOT KERNEL -> STEREO ROUTING
    # ------------------------------------------------------------------
    Select outer viewport: 4.20, 8, 0.88, 3.65
    Select inner viewport: 4.55, 7.72, 1.18, 3.45

    # Plot the actual kernel duration and actual oscillator frequencies.
    # Amplitude is normalized only for shape readability; the nominal scalar
    # amplitude is normalized only for kernel-shape readability; output level is set later by Output peak.
    .nPlot = 320
    .needed = ceiling(12 * freq2 * dot_duration_s)
    if .needed > .nPlot
        .nPlot = .needed
    endif
    if .nPlot > 1600
        .nPlot = 1600
    endif

    Axes: 0, dot_duration_s, -1.15, 1.15
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, dot_duration_s, -1.15, 1.15

    .prevX = 0
    .prevEnv = 0
    Colour: "{0.65, 0.75, 0.88}"
    Line width: 1
    for .q from 1 to .nPlot
        .tau = .q * dot_duration_s / .nPlot
        .u = .tau / dot_duration_s
        .env = (1 - cos(twoPi * .u)) / 2
        Draw line: .prevX, 0.55 + 0.38 * .prevEnv, .tau, 0.55 + 0.38 * .env
        Draw line: .prevX, 0.55 - 0.38 * .prevEnv, .tau, 0.55 - 0.38 * .env
        .prevX = .tau
        .prevEnv = .env
    endfor

    .prevX = 0
    .prevEnv = 0
    Colour: "{0.88, 0.73, 0.58}"
    for .q from 1 to .nPlot
        .tau = .q * dot_duration_s / .nPlot
        .u = .tau / dot_duration_s
        .env = (1 - cos(twoPi * .u)) / 2
        Draw line: .prevX, -0.55 + 0.38 * .prevEnv, .tau, -0.55 + 0.38 * .env
        Draw line: .prevX, -0.55 - 0.38 * .prevEnv, .tau, -0.55 - 0.38 * .env
        .prevX = .tau
        .prevEnv = .env
    endfor

    .prevX = 0
    .prevY1 = 0.55
    .prevY2 = -0.55
    Colour: "{0.20, 0.50, 0.82}"
    Line width: 1.2
    for .q from 1 to .nPlot
        .tau = .q * dot_duration_s / .nPlot
        .u = .tau / dot_duration_s
        .env = (1 - cos(twoPi * .u)) / 2
        .y1 = 0.55 + 0.34 * .env * sin(twoPi * base_frequency_Hz * .tau)
        Draw line: .prevX, .prevY1, .tau, .y1
        .prevX = .tau
        .prevY1 = .y1
    endfor

    Colour: "{0.82, 0.50, 0.20}"
    .prevX = 0
    for .q from 1 to .nPlot
        .tau = .q * dot_duration_s / .nPlot
        .u = .tau / dot_duration_s
        .env = (1 - cos(twoPi * .u)) / 2
        .y2 = -0.55 + 0.34 * .env * sin(twoPi * freq2 * .tau)
        Draw line: .prevX, .prevY2, .tau, .y2
        .prevX = .tau
        .prevY2 = .y2
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Local dot time (s)"
    Text: 0.02 * dot_duration_s, "left", 1.02, "half", "g1: " + fixed$(base_frequency_Hz, 1) + " Hz"
    Text: 0.02 * dot_duration_s, "left", -1.02, "half", "g2: " + fixed$(freq2, 1) + " Hz"
    Text: 0.98 * dot_duration_s, "right", 0.18, "half", "L = 0.9 g1 + 0.3 g2"
    Text: 0.98 * dot_duration_s, "right", -0.18, "half", "R = 0.3 g1 + 0.9 g2"
    Select outer viewport: 4.20, 8, 0.80, 1.12
    Select inner viewport: 4.55, 7.72, 0.82, 1.08
    Axes: 0, 1, 0, 1
    Font size: 7
    Text: 0.5, "centre", 0.5, "half", "B  Each dot -> raised-cosine tone -> fixed stereo routing"

    # ------------------------------------------------------------------
    # PANEL C: BAR ASSEMBLY -> REPETITION
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 3.78, 5.45
    Select inner viewport: 0.60, 7.72, 4.05, 5.25

    .barsShown = repeat_count
    if .barsShown > 8
        .barsShown = 8
    endif
    .schedDur = .barsShown * bar_duration_s
    Axes: 0, .schedDur, -0.15, 1.15
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, .schedDur, -0.15, 1.15

    # Bar boundaries represent the concatenate stage.
    Colour: "{0.78, 0.78, 0.82}"
    Dotted line
    for .r from 0 to .barsShown
        .bx = .r * bar_duration_s
        Draw line: .bx, -0.10, .bx, 1.08
    endfor
    Solid line

    for .r from 0 to .barsShown - 1
        .off = .r * bar_duration_s
        Colour: "{0.20, 0.50, 0.82}"
        for .i to dots_line_1
            .tx = .off + dotTime1[.i]
            Draw line: .tx, 0.62, .tx, 0.98
        endfor
        Colour: "{0.82, 0.50, 0.20}"
        for .i to dots_line_2
            .tx = .off + dotTime2[.i]
            Draw line: .tx, 0.02, .tx, 0.38
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Time (s)"
    if repeat_count > .barsShown
        Text: .schedDur * 0.99, "right", 1.05, "half", "first " + string$(.barsShown) + " of " + string$(repeat_count) + " identical bars shown"
    else
        Text: .schedDur * 0.99, "right", 1.05, "half", "one synthesized bar, then exact concatenation x" + string$(repeat_count)
    endif

    Select outer viewport: 0, 8, 3.68, 4.00
    Select inner viewport: 0.60, 7.72, 3.70, 3.96
    Axes: 0, 1, 0, 1
    Font size: 7
    Text: 0.5, "centre", 0.5, "half", "C  Event schedule -> one stereo bar -> normalize -> concatenate identical copies"

    # ------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT CONFIRMATION
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 5.58, 6.82
    Select inner viewport: 0.60, 7.72, 5.83, 6.62

    selectObject: outputSound
    Extract one channel: 1
    .leftDisp = selected("Sound")
    selectObject: outputSound
    Extract one channel: 2
    .rightDisp = selected("Sound")

    Axes: 0, finalDur, -1, 1
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, finalDur, -1, 1
    Colour: "{0.84, 0.84, 0.84}"
    Draw line: 0, 0, finalDur, 0

    if repeat_count > 1
        Colour: "{0.80, 0.80, 0.86}"
        Dotted line
        for .r from 1 to repeat_count - 1
            .bx = .r * bar_duration_s
            Draw line: .bx, -1, .bx, 1
        endfor
        Solid line
    endif

    selectObject: .leftDisp
    Colour: "{0.20, 0.50, 0.82}"
    Line width: 1
    Draw: 0, finalDur, -1, 1, "no", "Curve"
    selectObject: .rightDisp
    Colour: "{0.82, 0.50, 0.20}"
    Draw: 0, finalDur, -1, 1, "no", "Curve"

    removeObject: .leftDisp, .rightDisp

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 5.48, 5.80
    Select inner viewport: 0.60, 7.72, 5.50, 5.76
    Axes: 0, 1, 0, 1
    Font size: 7
    Text: 0.5, "centre", 0.5, "half", "D  Measured output confirmation (blue = L, orange = R; fixed amplitude scale)"

    # ------------------------------------------------------------------
    # PROCESS / QC SUMMARY
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 6.94, 7.82
    Select inner viewport: 0.45, 7.75, 7.02, 7.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    Font size: 6
    Text: 0.02, "left", 0.76, "half",
        ... "##Model##  " + string$(dots_line_1) + " : " + string$(dots_line_2)
        ... + " -> reduced " + string$(reduced1) + " : " + string$(reduced2)
        ... + "  |  delta1 " + fixed$(spacing1 * 1000, 2) + " ms"
        ... + "  |  delta2 " + fixed$(spacing2 * 1000, 2) + " ms"
        ... + "  |  lattice " + fixed$(latticeStep_s * 1000, 2) + " ms"
    Text: 0.02, "left", 0.48, "half",
        ... "##Exact structure##  GCD " + string$(gcdDots)
        ... + "  |  LCM " + string$(lcmDots)
        ... + "  |  coincidences/bar " + string$(coincidenceCount)
        ... + "  |  events/bar " + string$(dots_line_1 + dots_line_2)
        ... + "  |  repeats " + string$(repeat_count)
    Text: 0.02, "left", 0.20, "half",
        ... "##Synthesis QC##  dot " + fixed$(dot_duration_s * 1000, 2) + " ms (" + fixed$(dot_duration_s * sample_rate_Hz, 1) + " samples)"
        ... + "  |  min spacing " + fixed$(smallestSpacing_s * sample_rate_Hz, 1) + " samples"
        ... + "  |  f1/f2 " + fixed$(base_frequency_Hz, 1) + "/" + fixed$(freq2, 1) + " Hz"
        ... + "  |  total " + fixed$(finalDur, 2) + " s"
        ... + "  |  peak target/measured " + fixed$(output_peak, 3) + "/" + fixed$(finalPeak, 3)
        ... + "  |  RMS " + fixed$(finalRms, 3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
