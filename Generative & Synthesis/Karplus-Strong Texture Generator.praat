# ============================================================
# Praat AudioTools - Karplus_Strong_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Karplus-Strong plucked string synthesis.
#   Physical modeling algorithm: noise burst → filtered delay line.
#
#   Algorithm: y[n] = g × 0.5 × (y[n-N] + y[n-N-1])
#   where N = sample_rate / frequency, g = damping factor
#
# Usage:
#   Run this script (no input sound required).
#
# Changelog v0.2:
#   - Fixed KS algorithm (was subtraction, now correct averaging)
#   - Added visualization
#   - Added spatial modes
# ============================================================

form Karplus-Strong Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Plucked String
        option Guitar Strum
        option Harp Glissando
        option Metallic Pluck
        option Sitar Drone
        option Steel Drum
        option Banjo Bright
        option Dulcimer Shimmer
        option Prepared Piano
        option Frozen Resonance
    
    comment === Basic Settings ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    positive Pitch_Hz 220
    
    comment === KS Parameters ===
    real Damping 0.995 (= 0.9-0.9999)
    real Brightness 0.5 (= 0-1, lowpass mix)
    positive Excitation_ms 5
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo (detuned)
        option Stereo (delayed)
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    pitch_Hz = 220
    damping = 0.996
    brightness = 0.5
    excitation_ms = 5
    preset_name$ = "PluckedString"
    
elsif preset = 3
    pitch_Hz = 110
    damping = 0.995
    brightness = 0.6
    excitation_ms = 8
    preset_name$ = "GuitarStrum"
    
elsif preset = 4
    pitch_Hz = 440
    damping = 0.998
    brightness = 0.4
    excitation_ms = 3
    preset_name$ = "HarpGlissando"
    
elsif preset = 5
    pitch_Hz = 330
    damping = 0.9995
    brightness = 0.8
    excitation_ms = 2
    preset_name$ = "MetallicPluck"
    
elsif preset = 6
    pitch_Hz = 130
    damping = 0.997
    brightness = 0.5
    excitation_ms = 15
    preset_name$ = "SitarDrone"
    
elsif preset = 7
    pitch_Hz = 523
    damping = 0.994
    brightness = 0.7
    excitation_ms = 4
    preset_name$ = "SteelDrum"
    
elsif preset = 8
    pitch_Hz = 294
    damping = 0.990
    brightness = 0.9
    excitation_ms = 3
    preset_name$ = "BanjoBright"
    
elsif preset = 9
    pitch_Hz = 392
    damping = 0.9985
    brightness = 0.4
    excitation_ms = 6
    preset_name$ = "DulcimerShimmer"
    
elsif preset = 10
    pitch_Hz = 185
    damping = 0.993
    brightness = 0.6
    excitation_ms = 10
    preset_name$ = "PreparedPiano"
    
elsif preset = 11
    pitch_Hz = 261
    damping = 0.9999
    brightness = 0.3
    excitation_ms = 20
    preset_name$ = "FrozenResonance"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# Calculate delay line length
delaySamples = round(sample_rate_Hz / pitch_Hz)
excitationSamples = round(excitation_ms * sample_rate_Hz / 1000)

# Ensure excitation doesn't exceed delay
if excitationSamples > delaySamples
    excitationSamples = delaySamples
endif

# === Info ===
writeInfoLine: "=== Karplus-Strong Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Pitch: ", pitch_Hz, " Hz"
appendInfoLine: "Delay: ", delaySamples, " samples"
appendInfoLine: "Damping: ", damping
appendInfoLine: "Brightness: ", brightness
appendInfoLine: "Excitation: ", excitation_ms, " ms (", excitationSamples, " samples)"
appendInfoLine: ""

# === Synthesize using proper Karplus-Strong algorithm ===
appendInfoLine: "Synthesizing..."

# KS needs two passes because Formula can't do proper feedback
# Pass 1: Create excitation noise
outputSound = Create Sound from formula: "ks_" + uid$, 1, 0, duration_s, sample_rate_Hz,
    ... "if col <= excitationSamples then randomGauss(0, 0.5) else 0 fi"

# Pass 2: Apply KS feedback loop iteratively
# We need to do this sample-by-sample for proper feedback
selectObject: outputSound
for samp from delaySamples + 2 to round(duration_s * sample_rate_Hz)
    # Get delayed samples
    val1 = Get value at sample number: 1, samp - delaySamples
    val2 = Get value at sample number: 1, samp - delaySamples - 1
    
    # KS formula: damping * (brightness * delayed + (1-brightness) * average)
    newVal = damping * (brightness * val1 + (1 - brightness) * 0.5 * (val1 + val2))
    
    Set value at sample number: 1, samp, newVal
    
    # Progress
    if samp mod 10000 = 0
        appendInfoLine: "  Sample ", samp, " / ", round(duration_s * sample_rate_Hz)
    endif
endfor

# === Fade out ===
selectObject: outputSound
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo (detuned) - create second string with slight pitch difference
    appendInfoLine: ""
    appendInfoLine: "Creating detuned stereo..."
    
    delaySamplesR = round(sample_rate_Hz / (pitch_Hz * 1.005))
    
    rightSound = Create Sound from formula: "ks_right_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "if col <= excitationSamples then randomGauss(0, 0.5) else 0 fi"
    
    for samp from delaySamplesR + 2 to round(duration_s * sample_rate_Hz)
        val1 = Get value at sample number: 1, samp - delaySamplesR
        val2 = Get value at sample number: 1, samp - delaySamplesR - 1
        newVal = damping * (brightness * val1 + (1 - brightness) * 0.5 * (val1 + val2))
        Set value at sample number: 1, samp, newVal
    endfor
    
    Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"
    
    selectObject: outputSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "ks_" + preset_name$
    
    removeObject: outputSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Stereo (delayed) - Haas effect
    appendInfoLine: ""
    appendInfoLine: "Creating delayed stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    delaySamplesHaas = round(0.015 * sample_rate_Hz)
    Formula: "if col > delaySamplesHaas then self[col - delaySamplesHaas] else 0 fi"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "ks_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "ks_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

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
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0.3, 0.9
    Select inner viewport: 0, 7, 0.3, 0.9
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Karplus-Strong Synthesis — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "Pitch: " + fixed$(pitch_Hz, 1) + " Hz | Damping: " + fixed$(damping, 4) + " | Brightness: " + fixed$(brightness, 2)
    
    # === Waveform (first 50ms to show attack) ===
    Select outer viewport: 0, 7, 1.0, 2.5
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: .leftMargin, .rightMargin, 1.1, 2.4
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoWave = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_wave"
        .monoWave = selected("Sound")
    endif
    
    selectObject: .monoWave
    .showTime = min(0.05, duration_s)
    Draw: 0, .showTime, 0, 0, "yes", "curve"
    
    removeObject: .monoWave
    
    Select inner viewport: .leftMargin, .rightMargin, 1.1, 2.4
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 0.01, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s) — Attack detail"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 2.7, 5.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 2.8, 4.9
    
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
    .maxFreqSpec = min(8000, pitch_Hz * 12)
    
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    # Draw harmonics
    Select inner viewport: .leftMargin, .rightMargin, 2.8, 4.9
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "{1, 1, 0.3}"
    Line width: 1
    for .h to 8
        .hFreq = pitch_Hz * .h
        if .hFreq < .maxFreqSpec
            Draw line: 0, .hFreq, duration_s, .hFreq
        endif
    endfor
    
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 5.1, 5.5
    Select inner viewport: 0, 7, 5.1, 5.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Delay: " + string$(delaySamples) + " samples | Excitation: " + fixed$(excitation_ms, 1) + " ms | Yellow lines = harmonics"
    Text: 0.5, "centre", 0.5, "half", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
