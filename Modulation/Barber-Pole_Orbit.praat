# ============================================================
# Praat AudioTools - Barber_Pole_Orbit.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Barber-Pole Orbit - creates a Shepard-tone-like perpetual
#   rising/falling pitch illusion using modulated delays.
#   Multiple "turns" with opposing drift directions combine
#   to create endless spiral motion in stereo.
#
# Changelog v0.2:
#   - Modern syntax, input check, mono tracking, visualization
#
# Changelog v0.3:
#   - FIXED the core effect, which was broken three ways:
#       * It addressed L/R via "col mod 2", assuming interleaved stereo - but
#         Praat stores channels as ROWS, so this selected odd/even SAMPLES
#         within each channel instead of channels. Result: both output channels
#         came out identical (dual-mono - no stereo spiral at all), and the
#         odd/even decimation injected aliasing/high-frequency junk.
#       * The base term read self[...] in place (the recursive-delay trap).
#     Now each turn reads a DRY copy (feedforward) per channel (row), with the
#     stereo phase applied to the right channel via (row-1)*stereo_phase, so the
#     two channels genuinely differ and the spiral is stereo. No decimation.
#   - Visualization polished to house style; ASCII legend.
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
dur = Get total duration
numberOfChannels = Get number of channels

# === Form ===
form Barber-Pole Orbit Effect
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Ascending Illusion
        option Classic Barber Pole
        option Intense Spiral
        option Subtle Shimmer
        option Deep Space Rotation
        option Extreme Perpetual Motion
    
    comment === Orbit Parameters ===
    natural Number_of_turns 5
    positive Base_delay_ms 7.0
    positive Modulation_depth 0.10
    
    comment === Modulation Rates ===
    positive Base_rate_hz 3.8
    positive Drift_rate_hz 0.12
    positive Phase_offset 1.2
    
    comment === Stereo ===
    positive Stereo_phase_offset 0.5
    
    comment === Mix ===
    positive Turn_attenuation 1.0
    positive Temporal_shift 0.3
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Ascending Illusion
    number_of_turns = 3
    base_delay_ms = 5.0
    modulation_depth = 0.08
    base_rate_hz = 3.0
    drift_rate_hz = 0.08
    phase_offset = 1.57
    stereo_phase_offset = 0.25
    turn_attenuation = 1.5
    temporal_shift = 0.2
    presetName$ = "Gentle"
elsif preset = 3
    # Classic Barber Pole
    number_of_turns = 5
    base_delay_ms = 7.0
    modulation_depth = 0.12
    base_rate_hz = 4.0
    drift_rate_hz = 0.15
    phase_offset = 1.2
    stereo_phase_offset = 0.5
    turn_attenuation = 1.0
    temporal_shift = 0.3
    presetName$ = "Classic"
elsif preset = 4
    # Intense Spiral
    number_of_turns = 7
    base_delay_ms = 9.0
    modulation_depth = 0.18
    base_rate_hz = 5.5
    drift_rate_hz = 0.22
    phase_offset = 0.9
    stereo_phase_offset = 0.75
    turn_attenuation = 0.7
    temporal_shift = 0.45
    presetName$ = "Intense"
elsif preset = 5
    # Subtle Shimmer
    number_of_turns = 4
    base_delay_ms = 4.0
    modulation_depth = 0.06
    base_rate_hz = 2.5
    drift_rate_hz = 0.05
    phase_offset = 1.8
    stereo_phase_offset = 0.3
    turn_attenuation = 2.0
    temporal_shift = 0.15
    presetName$ = "Shimmer"
elsif preset = 6
    # Deep Space Rotation
    number_of_turns = 6
    base_delay_ms = 12.0
    modulation_depth = 0.15
    base_rate_hz = 2.0
    drift_rate_hz = 0.10
    phase_offset = 1.0
    stereo_phase_offset = 0.66
    turn_attenuation = 0.8
    temporal_shift = 0.5
    presetName$ = "Space"
elsif preset = 7
    # Extreme Perpetual Motion
    number_of_turns = 10
    base_delay_ms = 10.0
    modulation_depth = 0.25
    base_rate_hz = 6.5
    drift_rate_hz = 0.30
    phase_offset = 0.8
    stereo_phase_offset = 0.9
    turn_attenuation = 0.5
    temporal_shift = 0.6
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Barber-Pole Orbit ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Turns: ", number_of_turns
appendInfoLine: "Base delay: ", base_delay_ms, " ms"
appendInfoLine: "Modulation depth: ", modulation_depth
appendInfoLine: "Base rate: ", base_rate_hz, " Hz"
appendInfoLine: "Drift rate: ", drift_rate_hz, " Hz"
appendInfoLine: "Stereo phase: ", stereo_phase_offset
appendInfoLine: ""

# === Prepare Sound ===
selectObject: original
monoConverted = 0

if numberOfChannels = 1
    appendInfoLine: "Converting mono to stereo..."
    Convert to stereo
    stereoTemp = selected("Sound")
    monoConverted = 1
else
    selectObject: original
    stereoTemp = original
endif

selectObject: stereoTemp
Copy: originalName$ + "_barber_pole"
result = selected("Sound")

# Get sampling frequency
selectObject: result
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Calculate stereo phase in radians
stereo_phase = stereo_phase_offset * 2 * pi

# === Apply Barber-Pole Effect ===
appendInfoLine: "Applying barber-pole effect..."

# Keep a clean (dry) copy of the stereo source; every turn reads from it
# (feedforward) so taps are never recursive.
selectObject: result
Copy: originalName$ + "_dry"
dry = selected("Sound")

for t from 1 to number_of_turns
    appendInfoLine: "  Turn ", t, "/", number_of_turns

    # Weight for this turn
    w = 1 / (t + turn_attenuation)

    # One pass per turn, applied to BOTH channels. Channels are rows in Praat,
    # so the right channel (row 2) gets the stereo phase via (row - 1).
    # Two opposing modulated-delay taps (up-drift and down-drift) of the dry
    # signal are added, each read from the dry copy at the same channel (row).
    selectObject: result
    Formula: ~ self + w * object[dry, row, max(1, min(ncol, col + round(base + base * modulation_depth * sin(2 * pi * base_rate_hz * x + 2 * pi * drift_rate_hz * x + t * temporal_shift + (row - 1) * stereo_phase))))] + w * object[dry, row, max(1, min(ncol, col + round(base + base * modulation_depth * sin(2 * pi * base_rate_hz * x - 2 * pi * drift_rate_hz * x + phase_offset - t * temporal_shift + (row - 1) * stereo_phase))))]
endfor

removeObject: dry

# Scale to peak
selectObject: result
Scale peak: scale_peak
Rename: originalName$ + "_barber_" + presetName$

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Barber-Pole Orbit: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.50, 0.60, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Barber-Pole"
    Text bottom: "yes", "Time (s)"
    
    # Modulation pattern visualization
    Select outer viewport: 0, 8, 2.7, 4.2
    Select inner viewport: 0.6, 7.6, 2.9, 4.1
    
    Axes: 0, dur, -1.2, 1.2
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, dur, -1.2, 1.2
    
    # Zero line
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, 0, dur, 0
    Solid line
    
    # Draw modulation curves for first few turns
    numVizTurns = min(number_of_turns, 4)
    
    for t from 1 to numVizTurns
        # Color gradient
        colorVal = 0.3 + (t - 1) * 0.15
        
        # Upward drift (solid)
        Colour: "{" + fixed$(colorVal, 2) + ", " + fixed$(0.5, 2) + ", " + fixed$(0.7, 2) + "}"
        for samp from 1 to 100
            x1 = (samp - 1) / 100 * dur
            x2 = samp / 100 * dur
            y1 = sin(2 * pi * base_rate_hz * x1 + 2 * pi * drift_rate_hz * x1 + t * temporal_shift)
            y2 = sin(2 * pi * base_rate_hz * x2 + 2 * pi * drift_rate_hz * x2 + t * temporal_shift)
            Draw line: x1, y1, x2, y2
        endfor
        
        # Downward drift (dashed)
        Colour: "{" + fixed$(0.7, 2) + ", " + fixed$(colorVal, 2) + ", " + fixed$(0.5, 2) + "}"
        Dotted line
        for samp from 1 to 100
            x1 = (samp - 1) / 100 * dur
            x2 = samp / 100 * dur
            y1 = sin(2 * pi * base_rate_hz * x1 - 2 * pi * drift_rate_hz * x1 + phase_offset - t * temporal_shift)
            y2 = sin(2 * pi * base_rate_hz * x2 - 2 * pi * drift_rate_hz * x2 + phase_offset - t * temporal_shift)
            Draw line: x1, y1, x2, y2
        endfor
        Solid line
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Modulation"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 5
    Colour: "{0.40, 0.50, 0.70}"
    Text: 0.02, "left", 1.1, "half", "- Up drift"
    Colour: "{0.70, 0.40, 0.50}"
    Text: 0.12, "left", 1.1, "half", "... Down drift"
    
    # Turn weights
    Select outer viewport: 0, 8, 4.4, 5.0
    Select inner viewport: 0.6, 7.6, 4.5, 4.9
    
    maxW = 1 / (1 + turn_attenuation)
    Axes: 0, number_of_turns + 1, 0, maxW * 1.2
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, number_of_turns + 1, 0, maxW * 1.2
    
    for t from 1 to number_of_turns
        w = 1 / (t + turn_attenuation)
        Colour: "{0.50, 0.60, 0.70}"
        Paint rectangle: "{0.50, 0.60, 0.70}", t - 0.3, t + 0.3, 0, w
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Weight"
    Text bottom: "yes", "Turn"
    
    # Summary panel (grey)
    Select outer viewport: 0, 8, 5.1, 5.6
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "Turns: " + string$(number_of_turns) + "  |  rate " + fixed$(base_rate_hz, 1) + " Hz  |  drift " + fixed$(drift_rate_hz, 2) + " Hz  |  stereo phase " + fixed$(stereo_phase_offset, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
if monoConverted = 1
    removeObject: stereoTemp
endif

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