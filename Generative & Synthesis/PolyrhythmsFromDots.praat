# ============================================================
# Praat AudioTools - Polyrhythms_From_Dots.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
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

form Polyrhythms From Dots v0.4
    optionmenu Preset: 1
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
    positive Dot_duration_s 0.05
    natural Repeat_count 1
    positive Base_frequency_Hz 220
    integer Sample_rate_Hz 44100
    positive Amplitude 0.5
    boolean Show_spectrogram 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

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

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# Ensure at least 1 dot per line
if dots_line_1 < 1
    dots_line_1 = 1
endif
if dots_line_2 < 1
    dots_line_2 = 1
endif

# Clamp repeat count to a sane range
if repeat_count < 1
    repeat_count = 1
endif
if repeat_count > 64
    repeat_count = 64
endif

# Calculate spacing
spacing1 = bar_duration_s / dots_line_1
spacing2 = bar_duration_s / dots_line_2

# Second line frequency (perfect fifth above)
freq2 = base_frequency_Hz * 1.5

# Compute GCD and LCM of the two dot counts (for the parameter report)
@computeGcd: dots_line_1, dots_line_2
gcdDots = computeGcd.result
lcmDots = (dots_line_1 * dots_line_2) / gcdDots

# === Info ===
writeInfoLine: "=== Polyrhythms From Dots v0.4 ==="
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
    
    if d > 0.005
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
    
    if d > 0.005
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
Scale peak: 0.9

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

# Count coincidences between the two dot patterns (within 10 ms tolerance)
# This is the per-bar count, not multiplied by repeats.
coincidenceCount = 0
for i to dots_line_1
    for j to dots_line_2
        coDiff = abs(dotTime1[i] - dotTime2[j])
        if coDiff < 0.01
            coincidenceCount = coincidenceCount + 1
        endif
    endfor
endfor

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
# Procedure: drawVisualization  (8 x 8 canvas — suite standard)
# ==============================================================================
procedure drawVisualization
    
    Erase all
    Black
    Plain line
    
    # ----------------------------------------------------------
    # Compute spectrogram ONLY if user opted in
    # ----------------------------------------------------------
    if show_spectrogram
        selectObject: outputSound
        Extract one channel: 1
        specMono = selected("Sound")
        maxSpecFreq = freq2 * 2
        To Spectrogram: 0.01, maxSpecFreq, 0.005, 20, "Gaussian"
        polySpec = selected("Spectrogram")
    endif
    
    # Repeat-count label used in several places
    if repeat_count > 1
        repeatStr$ = "x" + string$(repeat_count) + " bars"
        barPlural$ = "s"
    else
        repeatStr$ = "single bar"
        barPlural$ = ""
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##POLYRHYTHMS FROM DOTS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... preset_name$
        ... + "  |  " + string$(dots_line_1) + " vs " + string$(dots_line_2)
        ... + "  |  bar " + fixed$(bar_duration_s, 2) + " s"
        ... + "  |  " + repeatStr$
        ... + "  |  line 1 = " + fixed$(base_frequency_Hz, 0) + " Hz"
        ... + "  |  line 2 = " + fixed$(freq2, 0) + " Hz"
        ... + "  |  dot " + fixed$(dot_duration_s * 1000, 0) + " ms"

    # ----------------------------------------------------------
    # PANEL A: POLYRHYTHM DOT DIAGRAM  (left, headline)
    # Shows ONE bar — the pattern. The repeat count is reflected
    # in the panel title but the dot positions are per-bar.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: -0.06 * bar_duration_s, bar_duration_s * 1.04, -0.2, 1.2
    Paint rectangle: "{0.97, 0.97, 0.99}", -0.06 * bar_duration_s, bar_duration_s * 1.04, -0.2, 1.2
    
    # Time axis line
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 1
    Draw line: 0, 0.5, bar_duration_s, 0.5
    
    # Dotted vertical lines at coincidences (drawn BEFORE the dots so
    # the dots sit on top)
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1
    Dotted line
    for .i to dots_line_1
        for .j to dots_line_2
            .diff = abs(dotTime1[.i] - dotTime2[.j])
            if .diff < 0.01
                Draw line: dotTime1[.i], 0.15, dotTime1[.i], 0.85
            endif
        endfor
    endfor
    Solid line
    Line width: 1
    
    # Line 1 dots (top, blue)
    for .i to dots_line_1
        .t = dotTime1[.i]
        Paint circle (mm): "{0.20, 0.50, 0.82}", .t, 0.85, 3.5
    endfor
    
    # Line 2 dots (bottom, orange)
    for .i to dots_line_2
        .t = dotTime2[.i]
        Paint circle (mm): "{0.82, 0.50, 0.20}", .t, 0.15, 3.5
    endfor
    
    # Line-count labels at left edge
    Colour: "{0.20, 0.50, 0.82}"
    Font size: 9
    Text: -0.03 * bar_duration_s, "right", 0.85, "half", string$(dots_line_1)
    Colour: "{0.82, 0.50, 0.20}"
    Text: -0.03 * bar_duration_s, "right", 0.15, "half", string$(dots_line_2)
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Marks bottom every: 1, bar_duration_s / 4, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Ratio:"
    
    Font size: 13
    Colour: "{0.55, 0.35, 0.78}"
    Text: 0.10, "left", 0.84, "half", "##" + string$(dots_line_1) + " : " + string$(dots_line_2) + "##"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.74, "half", "Math:"
    
    Font size: 10
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.10, "left", 0.67, "half", "GCD:           " + string$(gcdDots)
    Text: 0.10, "left", 0.60, "half", "LCM:           " + string$(lcmDots) + " subdivisions"
    Text: 0.10, "left", 0.53, "half", "Coincidences:  " + string$(coincidenceCount) + " / bar"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.45, "half", "Timing:"
    
    Font size: 10
    Colour: "{0.20, 0.50, 0.82}"
    Text: 0.10, "left", 0.38, "half", "Spacing 1:  " + fixed$(spacing1 * 1000, 1) + " ms"
    Colour: "{0.82, 0.50, 0.20}"
    Text: 0.10, "left", 0.32, "half", "Spacing 2:  " + fixed$(spacing2 * 1000, 1) + " ms"
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.26, "half", "Bar:        " + fixed$(bar_duration_s, 2) + " s"
    Text: 0.10, "left", 0.20, "half", "Dot:        " + fixed$(dot_duration_s * 1000, 1) + " ms"
    Text: 0.10, "left", 0.14, "half", "Total:      " + fixed$(finalDur, 2) + " s (" + string$(repeat_count) + " bar" + barPlural$ + ")"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.06, "half", "Pitches:"
    
    Font size: 9
    Colour: "{0.20, 0.50, 0.82}"
    Text: 0.10, "left", 0.01, "half", "L1 = " + fixed$(base_frequency_Hz, 1) + " Hz"
    Colour: "{0.82, 0.50, 0.20}"
    Text: 0.55, "left", 0.01, "half", "L2 = " + fixed$(freq2, 1) + " Hz"
    
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
    Text: 2.10, "centre", 7.30, "half",
        ... "Dot diagram — one bar  (blue = line 1, orange = line 2, purple = coincidences)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: STEREO L/R WAVEFORM  (full repeated output)
    # L blue, R orange.  Bar boundaries marked as light vertical lines
    # when repeated.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    selectObject: outputSound
    Extract one channel: 1
    leftDisp = selected("Sound")
    selectObject: outputSound
    Extract one channel: 2
    rightDisp = selected("Sound")
    
    selectObject: leftDisp
    wp_L = Get absolute extremum: 0, 0, "None"
    selectObject: rightDisp
    wp_R = Get absolute extremum: 0, 0, "None"
    wp_max = wp_L
    if wp_R > wp_max
        wp_max = wp_R
    endif
    if wp_max < 0.001
        wp_max = 0.001
    endif
    wp_amp = wp_max * 1.15
    
    Axes: 0, finalDur, -wp_amp, wp_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -wp_amp, wp_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    # Bar-boundary markers (light vertical dotted lines) when repeated
    if repeat_count > 1
        Colour: "{0.78, 0.78, 0.85}"
        Line width: 1
        Dotted line
        for br from 1 to repeat_count - 1
            barLineX = br * bar_duration_s
            Draw line: barLineX, -wp_amp, barLineX, wp_amp
        endfor
        Solid line
    endif
    
    # L channel
    selectObject: leftDisp
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, finalDur, -wp_amp, wp_amp, "no", "Curve"
    
    # R channel
    selectObject: rightDisp
    Colour: "{0.82, 0.50, 0.25}"
    Line width: 1
    Draw: 0, finalDur, -wp_amp, wp_amp, "no", "Curve"
    
    removeObject: leftDisp, rightDisp
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if repeat_count > 1
        Text top: "no", "Stereo waveform — " + string$(repeat_count) + " bars  (blue = L, orange = R; dotted = bar boundaries)"
    else
        Text top: "no", "Stereo waveform  (blue = L, orange = R)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: SPECTROGRAM (opt-in) or placeholder
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    if show_spectrogram
        selectObject: polySpec
        Paint: 0, 0, 0, maxSpecFreq, 100, "yes", 50, 6, 0, "no"
        
        # Mark the two pitch lines
        Axes: 0, finalDur, 0, maxSpecFreq
        Colour: "{0.50, 0.75, 1.00}"
        Line width: 1
        Dotted line
        Draw line: 0, base_frequency_Hz, finalDur, base_frequency_Hz
        Colour: "{1.00, 0.70, 0.40}"
        Draw line: 0, freq2, finalDur, freq2
        Solid line
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Spectrogram (dotted lines mark L1 = " + fixed$(base_frequency_Hz, 0) + " Hz, L2 = " + fixed$(freq2, 0) + " Hz)"
        Text left: "yes", "Freq (Hz)"
        Text bottom: "yes", "Time (s)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
        Font size: 8
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.5, "centre", 0.5, "half", "Spectrogram disabled (Show_spectrogram = OFF)"
        Colour: "Black"
        Draw inner box
    endif
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if show_spectrogram
        specStr$ = "shown"
    else
        specStr$ = "off"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + preset_name$ + "##"
        ... + "  Ratio: " + string$(dots_line_1) + " : " + string$(dots_line_2)
        ... + "  |  GCD: " + string$(gcdDots)
        ... + "  |  LCM: " + string$(lcmDots) + " subdivisions"
        ... + "  |  Coincidences/bar: " + string$(coincidenceCount)
        ... + "  |  Bar: " + fixed$(bar_duration_s, 2) + " s"
        ... + "  |  Repeats: " + string$(repeat_count)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Line 1: " + fixed$(base_frequency_Hz, 0) + " Hz / " + fixed$(spacing1 * 1000, 1) + " ms"
        ... + "  |  Line 2: " + fixed$(freq2, 0) + " Hz / " + fixed$(spacing2 * 1000, 1) + " ms"
        ... + "  |  Dot: " + fixed$(dot_duration_s * 1000, 1) + " ms"
        ... + "  |  Total: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  Spec: " + specStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup spectrogram objects if computed
    if show_spectrogram
        removeObject: polySpec, specMono
    endif
endproc
