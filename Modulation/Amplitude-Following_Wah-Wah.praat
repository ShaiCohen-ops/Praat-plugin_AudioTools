# ============================================================
# Praat AudioTools - Amplitude_Following_Wah_Wah.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Amplitude-Following Wah-Wah - classic envelope follower effect.
#   Louder sounds open the filter (brighter), quieter sounds close
#   it (darker). Uses FormantGrid as a time-varying resonant filter.
#
# Changelog v0.2:
#   - Fixed formant count, input check, visualization, envelope smoothing
#
# Changelog v0.3:
#   - Polished the visualization to the AudioTools house style (title band at
#     font 14, grey {0.94} summary panel, full-precision RGB, larger fonts).
#   - Replaced non-ASCII arrows in the plot legend.
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
dur = Get total duration
fs = Get sampling frequency

# === Form ===
form Amplitude Following Wah-Wah
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Style 1
        option Classic Guitar (mid-range, sharp)
        option Funky Bass (low-range, thumpy)
        option Subtle Vocal (wide, gentle)
        option Sci-Fi Zap (extreme range, very sharp)
        option Custom (use settings below)
    
    comment === Custom Settings ===
    positive Custom_min_Hz 400
    positive Custom_max_Hz 2500
    positive Custom_bandwidth_Hz 150
    
    comment === Envelope ===
    positive Envelope_smoothing_Hz 50
    comment (lower = smoother envelope response)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if style = 1
    # Classic Guitar
    min_cutoff = 400
    max_cutoff = 2500
    bw = 100
    presetName$ = "Guitar"
elsif style = 2
    # Funky Bass
    min_cutoff = 80
    max_cutoff = 800
    bw = 80
    presetName$ = "Bass"
elsif style = 3
    # Subtle Vocal
    min_cutoff = 500
    max_cutoff = 1500
    bw = 300
    presetName$ = "Vocal"
elsif style = 4
    # Sci-Fi Zap
    min_cutoff = 200
    max_cutoff = 4000
    bw = 50
    presetName$ = "SciFi"
else
    # Custom
    min_cutoff = custom_min_Hz
    max_cutoff = custom_max_Hz
    bw = custom_bandwidth_Hz
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Amplitude-Following Wah-Wah ==="
appendInfoLine: "Source: ", name$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Filter range: ", min_cutoff, " - ", max_cutoff, " Hz"
appendInfoLine: "Bandwidth: ", bw, " Hz"
appendInfoLine: "Envelope smoothing: ", envelope_smoothing_Hz, " Hz"
appendInfoLine: ""

# === Get Envelope ===
appendInfoLine: "Extracting amplitude envelope..."
selectObject: original
# Lower Hz = smoother envelope (acts as smoothing)
intensity = To Intensity: envelope_smoothing_Hz, 0, "yes"

selectObject: intensity
min_int = Get minimum: 0, 0, "Parabolic"
max_int = Get maximum: 0, 0, "Parabolic"
range_int = max_int - min_int

if range_int = 0
    range_int = 1
endif

n_frames = Get number of frames

appendInfoLine: "Intensity range: ", fixed$(min_int, 1), " - ", fixed$(max_int, 1), " dB"
appendInfoLine: "Frames: ", n_frames

# === Create FormantGrid ===
appendInfoLine: ""
appendInfoLine: "Building filter envelope..."

# Create grid with ONLY 1 formant (was 10 - bug!)
formantGrid = Create FormantGrid: name$ + "_filter", 0, dur, 1, min_cutoff, 1000, bw, 50

# Remove any initial default points
selectObject: formantGrid
Remove formant points between: 1, 0, dur
Remove bandwidth points between: 1, 0, dur

# Store for visualization
maxVizPoints = min(n_frames, 500)
vizTimes# = zero#(maxVizPoints)
vizIntensity# = zero#(maxVizPoints)
vizFreq# = zero#(maxVizPoints)
vizStep = ceiling(n_frames / maxVizPoints)

# === Map Intensity to Frequency ===
for i to n_frames
    selectObject: intensity
    t = Get time from frame number: i
    val = Get value in frame: i
    
    # Normalize to 0-1
    norm_val = (val - min_int) / range_int
    if norm_val < 0
        norm_val = 0
    elsif norm_val > 1
        norm_val = 1
    endif
    
    # Calculate filter frequency
    target_freq = min_cutoff + ((max_cutoff - min_cutoff) * norm_val)
    
    # Store for visualization
    vizIdx = ceiling(i / vizStep)
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        if vizTimes#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizIntensity#[vizIdx] = norm_val
            vizFreq#[vizIdx] = target_freq
        endif
    endif
    
    # Add to grid
    selectObject: formantGrid
    Add formant point: 1, t, target_freq
    Add bandwidth point: 1, t, bw
endfor

# === Apply Filter ===
appendInfoLine: ""
appendInfoLine: "Applying filter..."

selectObject: original, formantGrid
result = Filter

selectObject: result
Rename: name$ + "_wah_" + presetName$
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Amplitude-Following Wah-Wah: " + name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.70, 0.50, 0.50}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Wah"
    Text bottom: "yes", "Time (s)"
    
    # Envelope and filter frequency
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.7, 3.9
    
    Axes: 0, dur, 0, 1.1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, dur, 0, 1.1
    
    # Draw normalized intensity (envelope)
    Colour: "{0.50, 0.70, 0.50}"
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizIntensity#[vp - 1], vizTimes#[vp], vizIntensity#[vp]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Envelope"
    
    # Filter frequency
    Select outer viewport: 0, 8, 4.2, 5.2
    Select inner viewport: 0.6, 7.6, 4.3, 5.1
    
    freqMargin = (max_cutoff - min_cutoff) * 0.1
    Axes: 0, dur, min_cutoff - freqMargin, max_cutoff + freqMargin
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, dur, min_cutoff - freqMargin, max_cutoff + freqMargin
    
    # Draw range lines
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, min_cutoff, dur, min_cutoff
    Draw line: 0, max_cutoff, dur, max_cutoff
    Solid line
    
    # Draw filter frequency
    Colour: "{0.70, 0.50, 0.50}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizFreq#[vp - 1], vizTimes#[vp], vizFreq#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Filter (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Summary panel (grey)
    Select outer viewport: 0, 8, 5.4, 5.8
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "Loud -> high freq (bright)  |  quiet -> low freq (dark)  |  range " + string$(min_cutoff) + "-" + string$(max_cutoff) + " Hz  |  BW " + string$(bw) + " Hz"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: intensity, formantGrid

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

