# ============================================================
# Praat AudioTools - No_Input_Mixer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   No-input mixer simulation - feedback synthesis inspired by
#   experimental music techniques where a mixing console's output
#   is routed back to its input, creating self-oscillation.
#
# Changelog v0.3:
#   - Fixed Binaural: the in-place self[col-30] ITD delay cascaded zeros and
#     silenced the right channel. Now a feedforward delay from the unmodified
#     channel by ID.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, filter-drift plot + spectrogram, grey summary, larger fonts).
#   - Replaced non-ASCII characters (em-dash, plus-minus).
# ============================================================

form No-Input Mixer
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Edge of Oscillation
        option Deep Throbbing Drone
        option High Frequency Whistle
        option Degraded Cassette Loop
        option Unstable Resonance
    
    comment === Basic Settings ===
    positive Duration_s 10.0
    integer Sample_rate_Hz 44100
    positive Iterations 60
    
    comment === Circuit Physics ===
    positive Feedback_gain 1.05 (= 0.9-1.5)
    positive Damping_factor 0.94 (= 0.8-0.99)
    
    comment === Filter Drift ===
    positive Resonance_center_Hz 220
    positive Resonance_width_Hz 100
    positive Analog_instability 0.05 (= 0-0.3)
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Edge of Oscillation - subtle, barely oscillating
    feedback_gain = 1.01
    damping_factor = 0.92
    resonance_center_Hz = 440
    resonance_width_Hz = 300
    analog_instability = 0.02
    preset_name$ = "EdgeOfOscillation"
    
elsif preset = 3
    # Deep Throbbing Drone
    feedback_gain = 1.4
    damping_factor = 0.85
    resonance_center_Hz = 60
    resonance_width_Hz = 40
    analog_instability = 0.1
    preset_name$ = "DeepDrone"
    
elsif preset = 4
    # High Frequency Whistle
    feedback_gain = 1.1
    damping_factor = 0.98
    resonance_center_Hz = 2500
    resonance_width_Hz = 50
    analog_instability = 0.01
    preset_name$ = "HighWhistle"
    
elsif preset = 5
    # Degraded Cassette Loop
    feedback_gain = 0.98
    damping_factor = 0.99
    resonance_center_Hz = 800
    resonance_width_Hz = 1000
    analog_instability = 0.2
    preset_name$ = "CassetteLoop"
    
elsif preset = 6
    # Unstable Resonance
    feedback_gain = 1.2
    damping_factor = 0.90
    resonance_center_Hz = 350
    resonance_width_Hz = 150
    analog_instability = 0.15
    preset_name$ = "UnstableResonance"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Info ===
writeInfoLine: "=== No-Input Mixer ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Iterations: ", iterations
appendInfoLine: "Feedback gain: ", feedback_gain
appendInfoLine: "Damping: ", damping_factor
appendInfoLine: "Resonance: ", resonance_center_Hz, " +/- ", resonance_width_Hz / 2, " Hz"
appendInfoLine: "Instability: ", analog_instability
appendInfoLine: ""

# === Track filter frequencies for visualization ===
for iter to iterations
    filterFreq[iter] = resonance_center_Hz
endfor

# === Seed Injection (tiny noise to start oscillation) ===
appendInfoLine: "Initializing circuit..."

noiseL = Create Sound from formula: "noise_L_" + uid$, 1, 0, duration_s, sample_rate_Hz, "randomGauss(0, 0.0001)"
noiseR = Create Sound from formula: "noise_R_" + uid$, 1, 0, duration_s, sample_rate_Hz, "randomGauss(0, 0.0001)"

selectObject: noiseL
plusObject: noiseR
loopSound = Combine to stereo
Rename: "loop_" + uid$

removeObject: noiseL, noiseR

# === The Feedback Loop ===
appendInfoLine: "Running feedback simulation..."

for iter to iterations
    selectObject: loopSound
    Copy: "feedback_" + uid$
    feedbackPath = selected("Sound")
    
    # Calculate dynamic filter drift (analog instability)
    driftHz = resonance_center_Hz * analog_instability
    currentFreq = resonance_center_Hz + randomGauss(0, driftHz)
    widthDrift = resonance_width_Hz * analog_instability
    currentWidth = resonance_width_Hz + randomGauss(0, widthDrift)
    
    # Clamp values
    if currentWidth < 10
        currentWidth = 10
    endif
    if currentFreq < 20
        currentFreq = 20
    endif
    if currentFreq > sample_rate_Hz / 2 - currentWidth
        currentFreq = sample_rate_Hz / 2 - currentWidth
    endif
    
    # Store for visualization
    filterFreq[iter] = currentFreq
    
    # Bandpass filter (simulates resonant EQ)
    lowFreq = max(1, currentFreq - currentWidth / 2)
    highFreq = min(sample_rate_Hz / 2 - 1, currentFreq + currentWidth / 2)
    
    selectObject: feedbackPath
    Filter (pass Hann band): lowFreq, highFreq, 20
    filteredSound = selected("Sound")
    removeObject: feedbackPath
    
    # --- FIXED SECTION START ---
    
    # 1. Rename the filtered sound immediately so we can reference it
    selectObject: filteredSound
    Rename: "filt_" + uid$
    
    # 2. Select the loop sound to apply the mix formula
    selectObject: loopSound
    
    # Mix with soft clipping (arctan saturation)
    # Formula references the renamed "Sound_filt_..." directly
    Formula: "(2/pi) * arctan(damping_factor * self + feedback_gain * Sound_filt_" + uid$ + "[])"
    
    removeObject: filteredSound
    
    # --- FIXED SECTION END ---
    
    # Progress
    if iter mod 10 = 0
        appendInfoLine: "  Iteration ", iter, "/", iterations, " - freq: ", fixed$(currentFreq, 1), " Hz"
    endif
endfor

# === Spatial Processing ===
appendInfoLine: ""
appendInfoLine: "Applying spatial processing..."

selectObject: loopSound

if spatial_mode = 1
    # Mono
    Convert to mono
    outputSound = selected("Sound")
    Rename: "noinput_" + preset_name$
    removeObject: loopSound
    
elsif spatial_mode = 2
    # Stereo Wide (frequency split)
    Extract one channel: 1
    ch1 = selected("Sound")
    
    selectObject: loopSound
    Extract one channel: 2
    ch2 = selected("Sound")
    
    selectObject: ch1
    Filter (pass Hann band): 0, 4000, 100
    ch1Filt = selected("Sound")
    removeObject: ch1
    
    selectObject: ch2
    Filter (pass Hann band): 200, sample_rate_Hz / 2, 100
    ch2Filt = selected("Sound")
    removeObject: ch2
    
    selectObject: ch1Filt
    plusObject: ch2Filt
    outputSound = Combine to stereo
    Rename: "noinput_" + preset_name$
    
    removeObject: loopSound, ch1Filt, ch2Filt

elsif spatial_mode = 3
    # Rotating
    rotationRate = 0.2
    
    Extract one channel: 1
    ch1 = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * rotationRate * x))"
    
    selectObject: loopSound
    Extract one channel: 2
    ch2 = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * rotationRate * x))"
    
    selectObject: ch1
    plusObject: ch2
    outputSound = Combine to stereo
    Rename: "noinput_" + preset_name$
    
    removeObject: loopSound, ch1, ch2

elsif spatial_mode = 4
    # Binaural
    Extract one channel: 1
    ch1 = selected("Sound")
    Filter (pass Hann band): 50, 3000, 80
    ch1Filt = selected("Sound")
    removeObject: ch1
    
    selectObject: loopSound
    Extract one channel: 2
    ch2 = selected("Sound")
    # ITD delay (feedforward: read the unmodified channel by ID, not in-place;
    # in-place self[col-30] with else 0 cascades zeros and silences the channel)
    Copy: "ch2src_" + uid$
    ch2src = selected("Sound")
    selectObject: ch2
    Formula: "if col > 30 then object[" + string$(ch2src) + ", 1, col - 30] else 0 fi"
    removeObject: ch2src
    Filter (pass Hann band): 200, 6000, 80
    ch2Filt = selected("Sound")
    removeObject: ch2
    
    selectObject: ch1Filt
    plusObject: ch2Filt
    outputSound = Combine to stereo
    Rename: "noinput_" + preset_name$
    
    removeObject: loopSound, ch1Filt, ch2Filt
endif

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.05 then self * (x / 0.05) else self fi"
Formula: "if x > duration_s - 0.1 then self * ((duration_s - x) / 0.1) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.95

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

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "No-Input Mixer: " + preset_name$

    # --- Panel 1: Filter frequency drift ---
    Select outer viewport: 0, 8, 0.9, 2.7
    Select inner viewport: 0.75, 7.6, 1.05, 2.6
    .minFreq = filterFreq[1]
    .maxFreq = filterFreq[1]
    for .i to iterations
        if filterFreq[.i] < .minFreq
            .minFreq = filterFreq[.i]
        endif
        if filterFreq[.i] > .maxFreq
            .maxFreq = filterFreq[.i]
        endif
    endfor
    .freqRange = .maxFreq - .minFreq
    if .freqRange < 10
        .freqRange = 10
    endif
    .minFreq = .minFreq - .freqRange * 0.1
    .maxFreq = .maxFreq + .freqRange * 0.1
    Axes: 0, iterations, .minFreq, .maxFreq
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, iterations, .minFreq, .maxFreq

    Colour: "{0.70, 0.70, 0.70}"
    Dotted line
    Draw line: 0, resonance_center_Hz, iterations, resonance_center_Hz
    Solid line

    Colour: "{0.80, 0.30, 0.20}"
    Line width: 2
    for .i from 2 to iterations
        Draw line: .i - 1, filterFreq[.i - 1], .i, filterFreq[.i]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 10, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Iteration"
    Text left: "yes", "Filter freq (Hz)"

    # --- Panel 2: Spectrogram ---
    Select outer viewport: 0, 8, 2.9, 4.9
    Select inner viewport: 0.75, 7.6, 3.05, 4.8
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        .monoSpec = selected("Sound")
    endif
    selectObject: .monoSpec
    .maxFreqSpec = min(8000, resonance_center_Hz * 8)
    .maxFreqSpec = max(2000, .maxFreqSpec)
    To Spectrogram: 0.05, .maxFreqSpec, 0.01, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .monoSpec, .spec

    Select inner viewport: 0.75, 7.6, 3.05, 4.8
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "{1.0, 0.80, 0.20}"
    Line width: 1
    Dotted line
    Draw line: 0, resonance_center_Hz, duration_s, resonance_center_Hz
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # --- Summary panel (grey) ---
    Select outer viewport: 0, 8, 5.0, 5.4
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "Gain: " + fixed$(feedback_gain, 2) + " | Damp: " + fixed$(damping_factor, 2) + " | Instability: " + fixed$(analog_instability, 2) + " | Resonance: " + fixed$(resonance_center_Hz, 0) + " Hz | Yellow line = resonance center"
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc