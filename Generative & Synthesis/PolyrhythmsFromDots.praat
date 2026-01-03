# ============================================================
# Praat AudioTools - Polyrhythms_From_Dots.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
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
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Changelog v0.2:
#   - Fixed output deletion bug
#   - Fixed division by zero
#   - Added proper visualization
#   - Added envelope to prevent clicks
#   - Modern syntax
# ============================================================

form Polyrhythms From Dots
    comment === Preset ===
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
    
    comment === Rhythm ===
    integer Dots_line_1 5 (= top line, left-panned)
    integer Dots_line_2 7 (= bottom line, right-panned)
    
    comment === Timing ===
    positive Bar_duration_s 2.0
    positive Dot_duration_s 0.05
    
    comment === Sound ===
    positive Base_frequency_Hz 220
    integer Sample_rate_Hz 44100
    positive Amplitude 0.5
    
    comment === Output ===
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

# Calculate spacing
spacing1 = bar_duration_s / dots_line_1
spacing2 = bar_duration_s / dots_line_2

# Second line frequency (perfect fifth above)
freq2 = base_frequency_Hz * 1.5

# === Info ===
writeInfoLine: "=== Polyrhythms From Dots ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Rhythm: ", dots_line_1, " vs ", dots_line_2
appendInfoLine: "Bar duration: ", bar_duration_s, " s"
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

# === Create Stereo Sound ===
appendInfoLine: "Synthesizing polyrhythm..."

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
Rename: "polyrhythm_" + string$(dots_line_1) + "vs" + string$(dots_line_2)

removeObject: leftSound, rightSound

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

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

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.8
    Select inner viewport: 0, 7, 0.2, 0.8
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Polyrhythm: " + string$(dots_line_1) + " vs " + string$(dots_line_2)
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", preset_name$ + " | Bar: " + fixed$(bar_duration_s, 1) + " s"
    
    # === Dot Diagram ===
    Select outer viewport: 0, 7, 1.0, 3.0
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 1.1, 2.9
    Axes: -0.1 * bar_duration_s, bar_duration_s * 1.1, -0.2, 1.2
    
    # Draw time axis
    Colour: "{0.7, 0.7, 0.7}"
    Draw line: 0, 0.5, bar_duration_s, 0.5
    
    # Draw line 1 dots (top, blue)
    for .i to dots_line_1
        .t = dotTime1[.i]
        Paint circle (mm): "{0.2, 0.4, 0.8}", .t, 0.85, 4
    endfor
    
    # Draw line 2 dots (bottom, orange)
    for .i to dots_line_2
        .t = dotTime2[.i]
        Paint circle (mm): "{0.8, 0.5, 0.2}", .t, 0.15, 4
    endfor
    
    # Draw vertical lines showing coincidences
    Colour: "{0.5, 0.5, 0.5}"
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
    
    # Labels
    Colour: "Black"
    Draw inner box
    Font size: 9
    Colour: "{0.2, 0.4, 0.8}"
    Text: -0.05 * bar_duration_s, "right", 0.85, "half", string$(dots_line_1)
    Colour: "{0.8, 0.5, 0.2}"
    Text: -0.05 * bar_duration_s, "right", 0.15, "half", string$(dots_line_2)
    Colour: "Black"
    Font size: 8
    Marks bottom every: 1, bar_duration_s / 4, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Waveform ===
    Select outer viewport: 0, 7, 3.2, 4.5
    selectObject: outputSound
    Draw: 0, 0, 0, 0, "yes", "curve"
    Draw inner box
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 4.7, 6.2
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 4.8, 6.1
    
    selectObject: outputSound
    Extract one channel: 1
    .monoSpec = selected("Sound")
    
    .maxFreq = freq2 * 2
    selectObject: .monoSpec
    To Spectrogram: 0.01, .maxFreq, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    # Mark frequencies
    Select inner viewport: 0.5, 6.5, 4.8, 6.1
    Axes: 0, bar_duration_s, 0, .maxFreq
    
    Colour: "{0.5, 0.7, 1}"
    Dotted line
    Draw line: 0, base_frequency_Hz, bar_duration_s, base_frequency_Hz
    Colour: "{1, 0.7, 0.5}"
    Draw line: 0, freq2, bar_duration_s, freq2
    Solid line
    
    Colour: "White"
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc