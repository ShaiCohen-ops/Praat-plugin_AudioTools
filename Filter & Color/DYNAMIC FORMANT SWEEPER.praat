# ============================================================
# Praat AudioTools - Dynamic_Formant_Sweeper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LFO-controlled formant filter that sweeps a resonant bandpass
#   through the audio. Creates vowel morphing, robot voices,
#   talking synth effects, and other spectral animations.
#
#   Pipeline:
#   1. Extract source signal via inverse LPC filtering
#   2. Create formant filter with F1 modulated by LFO
#   3. Apply filter to source (resynthesis)
#   4. Mix with original (dry/wet)
#
# Usage:
#   Select a Sound object in Praat, then run this script.
#
# Changelog v0.2:
#   - Fixed dry/wet mixing (was halving output)
#   - Modern syntax throughout
#   - Added fade in/out
#   - Improved visualization
# ============================================================

form Dynamic Formant Sweeper
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Vowel Morph
        option Robot Voice
        option Talking Synth
        option Underwater
        option Alien Speech
        option Fast Wobble
        option Slow Sweep
    
    comment === LFO Parameters ===
    real Rate_Hz 1.0
    positive Min_freq_Hz 500
    positive Max_freq_Hz 3500
    
    comment === Filter Shape ===
    positive Bandwidth_Hz 100
    optionmenu Lfo_shape 1
        option Sine
        option Triangle
        option Square (Chopper)
        option Sawtooth
        option Reverse Sawtooth
    
    comment === Processing ===
    positive Frame_duration_ms 25
    real Dry_wet_mix 1.0 (= 0=dry, 1=wet)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check for Sound selection ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    rate_Hz = 0.3
    min_freq_Hz = 700
    max_freq_Hz = 1200
    bandwidth_Hz = 80
    lfo_shape = 1
    frame_duration_ms = 40
    dry_wet_mix = 0.6
    preset_name$ = "GentleVowelMorph"
elsif preset = 3
    rate_Hz = 2.0
    min_freq_Hz = 400
    max_freq_Hz = 2000
    bandwidth_Hz = 150
    lfo_shape = 3
    frame_duration_ms = 15
    dry_wet_mix = 0.85
    preset_name$ = "RobotVoice"
elsif preset = 4
    rate_Hz = 0.5
    min_freq_Hz = 600
    max_freq_Hz = 1800
    bandwidth_Hz = 120
    lfo_shape = 2
    frame_duration_ms = 30
    dry_wet_mix = 0.75
    preset_name$ = "TalkingSynth"
elsif preset = 5
    rate_Hz = 0.2
    min_freq_Hz = 300
    max_freq_Hz = 800
    bandwidth_Hz = 200
    lfo_shape = 1
    frame_duration_ms = 50
    dry_wet_mix = 0.9
    preset_name$ = "Underwater"
elsif preset = 6
    rate_Hz = 1.5
    min_freq_Hz = 800
    max_freq_Hz = 3000
    bandwidth_Hz = 90
    lfo_shape = 4
    frame_duration_ms = 20
    dry_wet_mix = 0.8
    preset_name$ = "AlienSpeech"
elsif preset = 7
    rate_Hz = 4.0
    min_freq_Hz = 500
    max_freq_Hz = 2500
    bandwidth_Hz = 100
    lfo_shape = 1
    frame_duration_ms = 10
    dry_wet_mix = 0.7
    preset_name$ = "FastWobble"
elsif preset = 8
    rate_Hz = 0.1
    min_freq_Hz = 400
    max_freq_Hz = 3500
    bandwidth_Hz = 100
    lfo_shape = 4
    frame_duration_ms = 35
    dry_wet_mix = 1.0
    preset_name$ = "SlowSweep"
endif

# === Get Input Sound Info ===
inputSound = selected("Sound")
originalName$ = selected$("Sound")
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

selectObject: inputSound
duration = Get total duration
sampleRate = Get sampling frequency
nChannels = Get number of channels

nPoles = round(sampleRate / 1000) + 2
frameDurSec = frame_duration_ms / 1000

# === Info ===
writeInfoLine: "=== Dynamic Formant Sweeper ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "LFO: ", rate_Hz, " Hz | Range: ", min_freq_Hz, "-", max_freq_Hz, " Hz"
appendInfoLine: "Frame: ", frame_duration_ms, " ms | Mix: ", fixed$(dry_wet_mix * 100, 0), "%"
appendInfoLine: ""

# === Convert Stereo to Mono for Processing ===
isStereo = 0
if nChannels = 2
    appendInfoLine: "Converting stereo to mono for processing..."
    selectObject: inputSound
    monoSound = Convert to mono
    Rename: "mono_" + uid$
    processingSound = monoSound
    isStereo = 1
else
    processingSound = inputSound
endif

# === Step 1: Source Extraction (Inverse LPC) ===
appendInfoLine: "[1/4] Extracting source signal..."

selectObject: processingSound
lpcObject = To LPC (burg): nPoles, 0.025, 0.005, 50

selectObject: lpcObject
plusObject: processingSound
sourceSignal = Filter (inverse)
Rename: "source_" + uid$

# === Step 2: Create LFO-Modulated Formant Filter ===
appendInfoLine: "[2/4] Creating LFO-modulated filter..."

selectObject: processingSound
filterObject = To Formant (burg): frameDurSec, 5, 5500, 0.025, 50
Rename: "filter_" + uid$

freqRange = max_freq_Hz - min_freq_Hz
freqMid = min_freq_Hz + freqRange / 2

# Generate F1 frequency formula based on LFO shape
if lfo_shape = 1
    # Sine
    freqFormula$ = string$(min_freq_Hz) + " + " + string$(freqRange) + " * 0.5 * (1 + sin(2*pi*" + string$(rate_Hz) + "*x))"
elsif lfo_shape = 2
    # Triangle
    freqFormula$ = string$(freqMid) + " + " + string$(freqRange/2) + " * (2/pi) * arcsin(sin(2*pi*" + string$(rate_Hz) + "*x))"
elsif lfo_shape = 3
    # Square (Chopper)
    freqFormula$ = "if sin(2*pi*" + string$(rate_Hz) + "*x) > 0 then " + string$(max_freq_Hz) + " else " + string$(min_freq_Hz) + " endif"
elsif lfo_shape = 4
    # Sawtooth
    freqFormula$ = string$(min_freq_Hz) + " + " + string$(freqRange) + " * ((" + string$(rate_Hz) + "*x) mod 1)"
elsif lfo_shape = 5
    # Reverse Sawtooth
    freqFormula$ = string$(max_freq_Hz) + " - " + string$(freqRange) + " * ((" + string$(rate_Hz) + "*x) mod 1)"
endif

selectObject: filterObject
Formula (frequencies): "if row = 1 then " + freqFormula$ + " else self endif"
Formula (bandwidths): "if row = 1 then " + string$(bandwidth_Hz) + " else self endif"

# === Step 3: Resynthesis ===
appendInfoLine: "[3/4] Resynthesizing..."

selectObject: sourceSignal
plusObject: filterObject
outputRaw = Filter
Rename: "output_raw_" + uid$

# Apply gentle lowpass to smooth artifacts
selectObject: outputRaw
outputFiltered = Filter (pass Hann band): 0, 8000, 100
Rename: "output_filtered_" + uid$

removeObject: outputRaw

# === Step 4: Dry/Wet Mix ===
if dry_wet_mix < 1.0
    appendInfoLine: "Mixing: ", fixed$(dry_wet_mix * 100, 0), "% wet / ", fixed$((1 - dry_wet_mix) * 100, 0), "% dry"
    
    wetAmount = dry_wet_mix
    dryAmount = 1 - dry_wet_mix
    
    # Make a copy of dry signal
    selectObject: processingSound
    Copy: "dry_" + uid$
    drySound = selected("Sound")
    
    # Mix: output = wet * filtered + dry * original
    selectObject: outputFiltered
    dryName$ = "Sound_dry_" + uid$
    Formula: "self * " + string$(wetAmount) + " + " + dryName$ + "[] * " + string$(dryAmount)
    
    removeObject: drySound
endif

selectObject: outputFiltered
Rename: "swept_" + preset_name$
outputSound = selected("Sound")

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.01 then self * (x / 0.01) else self fi"
Formula: "if x > duration - 0.02 then self * ((duration - x) / 0.02) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.95

# === Convert Back to Stereo if Needed ===
if isStereo = 1
    appendInfoLine: "Converting back to stereo..."
    selectObject: outputSound
    stereoOutput = Convert to stereo
    Rename: "swept_" + preset_name$
    removeObject: outputSound
    outputSound = stereoOutput
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Cleanup ===
removeObject: lpcObject, sourceSignal, filterObject
if isStereo = 1
    removeObject: monoSound
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
    Select outer viewport: 0, 7, 0.2, 0.7
    Select inner viewport: 0, 7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Dynamic Formant Sweeper — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "LFO: " + fixed$(rate_Hz, 1) + " Hz | Range: " + string$(min_freq_Hz) + "-" + string$(max_freq_Hz) + " Hz | Mix: " + fixed$(dry_wet_mix * 100, 0) + "%"
    
    # === LFO Waveform ===
    Select outer viewport: 0, 7, 0.8, 2.0
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 0.9, 1.9
    Axes: 0, duration, min_freq_Hz - 100, max_freq_Hz + 100
    
    # Draw LFO curve
    Colour: "{0.8, 0.5, 0.2}"
    Line width: 2
    .nPoints = 200
    for .i from 2 to .nPoints
        .t1 = (.i - 2) / (.nPoints - 1) * duration
        .t2 = (.i - 1) / (.nPoints - 1) * duration
        
        # Calculate LFO value
        if lfo_shape = 1
            .y1 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * .t1))
            .y2 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * .t2))
        elsif lfo_shape = 2
            .y1 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * .t1))
            .y2 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * .t2))
        elsif lfo_shape = 3
            .y1 = if sin(twoPi * rate_Hz * .t1) > 0 then max_freq_Hz else min_freq_Hz fi
            .y2 = if sin(twoPi * rate_Hz * .t2) > 0 then max_freq_Hz else min_freq_Hz fi
        elsif lfo_shape = 4
            .y1 = min_freq_Hz + freqRange * ((rate_Hz * .t1) mod 1)
            .y2 = min_freq_Hz + freqRange * ((rate_Hz * .t2) mod 1)
        elsif lfo_shape = 5
            .y1 = max_freq_Hz - freqRange * ((rate_Hz * .t1) mod 1)
            .y2 = max_freq_Hz - freqRange * ((rate_Hz * .t2) mod 1)
        endif
        
        Draw line: .t1, .y1, .t2, .y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "F1 (Hz)"
    Text bottom: "yes", "Time (s) — LFO Trajectory"
    
    # === Spectrogram with F1 Overlay ===
    Select outer viewport: 0, 7, 2.2, 5.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 2.3, 4.9
    
    # Get mono for spectrogram
    if isStereo = 1
        selectObject: outputSound
        Extract one channel: 1
        .specSound = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        .specSound = selected("Sound")
    endif
    
    selectObject: .specSound
    .spec = To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .specSound, .spec
    
    # Overlay F1 trajectory on spectrogram
    Select inner viewport: 0.5, 6.5, 2.3, 4.9
    Axes: 0, duration, 0, 5000
    
    Colour: "Yellow"
    Line width: 3
    for .i from 2 to .nPoints
        .t1 = (.i - 2) / (.nPoints - 1) * duration
        .t2 = (.i - 1) / (.nPoints - 1) * duration
        
        if lfo_shape = 1
            .y1 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * .t1))
            .y2 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * .t2))
        elsif lfo_shape = 2
            .y1 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * .t1))
            .y2 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * .t2))
        elsif lfo_shape = 3
            .y1 = if sin(twoPi * rate_Hz * .t1) > 0 then max_freq_Hz else min_freq_Hz fi
            .y2 = if sin(twoPi * rate_Hz * .t2) > 0 then max_freq_Hz else min_freq_Hz fi
        elsif lfo_shape = 4
            .y1 = min_freq_Hz + freqRange * ((rate_Hz * .t1) mod 1)
            .y2 = min_freq_Hz + freqRange * ((rate_Hz * .t2) mod 1)
        elsif lfo_shape = 5
            .y1 = max_freq_Hz - freqRange * ((rate_Hz * .t1) mod 1)
            .y2 = max_freq_Hz - freqRange * ((rate_Hz * .t2) mod 1)
        endif
        
        Draw line: .t1, .y1, .t2, .y2
    endfor
    Line width: 1
    
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
    Text: 0.5, "centre", 0.5, "half", "Yellow line = F1 filter frequency | Spectrogram shows filtered output"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc