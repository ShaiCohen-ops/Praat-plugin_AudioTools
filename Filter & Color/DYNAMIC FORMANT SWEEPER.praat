# ============================================================
# Praat AudioTools - Dynamic_Formant_Sweeper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed Formula syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LFO-controlled formant filter that sweeps a resonant bandpass
#   through the audio. Creates vowel morphing, robot voices,
#   talking synth effects, and other spectral animations.
#
# Changelog v0.3:
#   - Fixed Formula variable interpolation
#   - Fixed object reference in dry/wet mix
# ============================================================

# === Check for Sound selection ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

inputSound = selected("Sound")
originalName$ = selected$("Sound")

form Dynamic Formant Sweeper v0.3
    optionmenu Preset: 1
        option Manual
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
    optionmenu Lfo_shape: 1
        option Sine
        option Triangle
        option Square (Chopper)
        option Sawtooth
        option Reverse Sawtooth
    comment === Processing ===
    positive Frame_duration_ms 25
    real Dry_wet_mix 1.0
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    rate_Hz = 0.3
    min_freq_Hz = 700
    max_freq_Hz = 1200
    bandwidth_Hz = 80
    lfo_shape = 1
    frame_duration_ms = 40
    dry_wet_mix = 0.6
    presetName$ = "GentleVowelMorph"
elsif preset = 3
    rate_Hz = 2.0
    min_freq_Hz = 400
    max_freq_Hz = 2000
    bandwidth_Hz = 150
    lfo_shape = 3
    frame_duration_ms = 15
    dry_wet_mix = 0.85
    presetName$ = "RobotVoice"
elsif preset = 4
    rate_Hz = 0.5
    min_freq_Hz = 600
    max_freq_Hz = 1800
    bandwidth_Hz = 120
    lfo_shape = 2
    frame_duration_ms = 30
    dry_wet_mix = 0.75
    presetName$ = "TalkingSynth"
elsif preset = 5
    rate_Hz = 0.2
    min_freq_Hz = 300
    max_freq_Hz = 800
    bandwidth_Hz = 200
    lfo_shape = 1
    frame_duration_ms = 50
    dry_wet_mix = 0.9
    presetName$ = "Underwater"
elsif preset = 6
    rate_Hz = 1.5
    min_freq_Hz = 800
    max_freq_Hz = 3000
    bandwidth_Hz = 90
    lfo_shape = 4
    frame_duration_ms = 20
    dry_wet_mix = 0.8
    presetName$ = "AlienSpeech"
elsif preset = 7
    rate_Hz = 4.0
    min_freq_Hz = 500
    max_freq_Hz = 2500
    bandwidth_Hz = 100
    lfo_shape = 1
    frame_duration_ms = 10
    dry_wet_mix = 0.7
    presetName$ = "FastWobble"
elsif preset = 8
    rate_Hz = 0.1
    min_freq_Hz = 400
    max_freq_Hz = 3500
    bandwidth_Hz = 100
    lfo_shape = 4
    frame_duration_ms = 35
    dry_wet_mix = 1.0
    presetName$ = "SlowSweep"
else
    presetName$ = "Manual"
endif

# === Get Input Sound Info ===
twoPi = 2 * pi

selectObject: inputSound
duration = Get total duration
sampleRate = Get sampling frequency
nChannels = Get number of channels

nPoles = round(sampleRate / 1000) + 2
frameDurSec = frame_duration_ms / 1000

# === Info ===
clearinfo
writeInfoLine: "=== Dynamic Formant Sweeper v0.3 ==="
appendInfoLine: "Preset: ", presetName$
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

# === Step 2: Create LFO-Modulated Formant Filter ===
appendInfoLine: "[2/4] Creating LFO-modulated filter..."

selectObject: processingSound
filterObject = To Formant (burg): frameDurSec, 5, 5500, 0.025, 50

freqRange = max_freq_Hz - min_freq_Hz
freqMid = min_freq_Hz + freqRange / 2

# Generate F1 frequency formula based on LFO shape
minF$ = string$(min_freq_Hz)
maxF$ = string$(max_freq_Hz)
range$ = string$(freqRange)
mid$ = string$(freqMid)
rate$ = string$(rate_Hz)
halfRange$ = string$(freqRange / 2)

if lfo_shape = 1
    # Sine
    freqFormula$ = minF$ + " + " + range$ + " * 0.5 * (1 + sin(2*pi*" + rate$ + "*x))"
elsif lfo_shape = 2
    # Triangle
    freqFormula$ = mid$ + " + " + halfRange$ + " * (2/pi) * arcsin(sin(2*pi*" + rate$ + "*x))"
elsif lfo_shape = 3
    # Square (Chopper)
    freqFormula$ = "if sin(2*pi*" + rate$ + "*x) > 0 then " + maxF$ + " else " + minF$ + " endif"
elsif lfo_shape = 4
    # Sawtooth
    freqFormula$ = minF$ + " + " + range$ + " * ((" + rate$ + "*x) mod 1)"
elsif lfo_shape = 5
    # Reverse Sawtooth
    freqFormula$ = maxF$ + " - " + range$ + " * ((" + rate$ + "*x) mod 1)"
endif

selectObject: filterObject
Formula (frequencies): "if row = 1 then " + freqFormula$ + " else self endif"
Formula (bandwidths): "if row = 1 then " + string$(bandwidth_Hz) + " else self endif"

# === Step 3: Resynthesis ===
appendInfoLine: "[3/4] Resynthesizing..."

selectObject: sourceSignal
plusObject: filterObject
outputRaw = Filter

# Apply gentle lowpass to smooth artifacts
selectObject: outputRaw
outputFiltered = Filter (pass Hann band): 0, 8000, 100

removeObject: outputRaw

# === Step 4: Dry/Wet Mix ===
if dry_wet_mix < 1.0
    appendInfoLine: "Mixing: ", fixed$(dry_wet_mix * 100, 0), "% wet / ", fixed$((1 - dry_wet_mix) * 100, 0), "% dry"
    
    wetAmount$ = string$(dry_wet_mix)
    dryAmount$ = string$(1 - dry_wet_mix)
    
    # Make a copy of dry signal
    selectObject: processingSound
    drySound = Copy: "dry_signal"
    dryId$ = string$(drySound)
    
    # Mix: output = wet * filtered + dry * original
    selectObject: outputFiltered
    Formula: "self * " + wetAmount$ + " + Object_" + dryId$ + "(x) * " + dryAmount$
    
    removeObject: drySound
endif

selectObject: outputFiltered
Rename: originalName$ + "_swept_" + presetName$
outputSound = selected("Sound")

# === Fade In/Out (fixed Formula syntax) ===
dur$ = string$(duration)
fadeOut$ = string$(duration - 0.02)

selectObject: outputSound
Formula: "if x < 0.01 then self * (x / 0.01) else self endif"
Formula: "if x > " + fadeOut$ + " then self * ((" + dur$ + " - x) / 0.02) else self endif"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.95

# === Convert Back to Stereo if Needed ===
if isStereo = 1
    appendInfoLine: "Converting back to stereo..."
    selectObject: outputSound
    stereoOutput = Convert to stereo
    Rename: originalName$ + "_swept_" + presetName$
    removeObject: outputSound
    outputSound = stereoOutput
endif

# === Cleanup ===
removeObject: lpcObject, sourceSignal, filterObject
if isStereo = 1
    removeObject: monoSound
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.7
    Select inner viewport: 0, 7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Dynamic Formant Sweeper - " + presetName$
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
    nPoints = 200
    for i from 2 to nPoints
        t1 = (i - 2) / (nPoints - 1) * duration
        t2 = (i - 1) / (nPoints - 1) * duration
        
        # Calculate LFO value
        if lfo_shape = 1
            y1 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t1))
            y2 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 2
            y1 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t1))
            y2 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 3
            if sin(twoPi * rate_Hz * t1) > 0
                y1 = max_freq_Hz
            else
                y1 = min_freq_Hz
            endif
            if sin(twoPi * rate_Hz * t2) > 0
                y2 = max_freq_Hz
            else
                y2 = min_freq_Hz
            endif
        elsif lfo_shape = 4
            y1 = min_freq_Hz + freqRange * ((rate_Hz * t1) mod 1)
            y2 = min_freq_Hz + freqRange * ((rate_Hz * t2) mod 1)
        elsif lfo_shape = 5
            y1 = max_freq_Hz - freqRange * ((rate_Hz * t1) mod 1)
            y2 = max_freq_Hz - freqRange * ((rate_Hz * t2) mod 1)
        endif
        
        Draw line: t1, y1, t2, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "F1 (Hz)"
    Text bottom: "yes", "Time (s) - LFO Trajectory"
    
    # === Spectrogram with F1 Overlay ===
    Select outer viewport: 0, 7, 2.2, 5.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 2.3, 4.9
    
    # Get mono for spectrogram
    if isStereo = 1
        selectObject: outputSound
        Extract one channel: 1
        specSound = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        specSound = selected("Sound")
    endif
    
    selectObject: specSound
    spec = To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: specSound, spec
    
    # Overlay F1 trajectory on spectrogram
    Select inner viewport: 0.5, 6.5, 2.3, 4.9
    Axes: 0, duration, 0, 5000
    
    Colour: "Yellow"
    Line width: 3
    for i from 2 to nPoints
        t1 = (i - 2) / (nPoints - 1) * duration
        t2 = (i - 1) / (nPoints - 1) * duration
        
        if lfo_shape = 1
            y1 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t1))
            y2 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 2
            y1 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t1))
            y2 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 3
            if sin(twoPi * rate_Hz * t1) > 0
                y1 = max_freq_Hz
            else
                y1 = min_freq_Hz
            endif
            if sin(twoPi * rate_Hz * t2) > 0
                y2 = max_freq_Hz
            else
                y2 = min_freq_Hz
            endif
        elsif lfo_shape = 4
            y1 = min_freq_Hz + freqRange * ((rate_Hz * t1) mod 1)
            y2 = min_freq_Hz + freqRange * ((rate_Hz * t2) mod 1)
        elsif lfo_shape = 5
            y1 = max_freq_Hz - freqRange * ((rate_Hz * t1) mod 1)
            y2 = max_freq_Hz - freqRange * ((rate_Hz * t2) mod 1)
        endif
        
        Draw line: t1, y1, t2, y2
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
endif

# === Output ===
selectObject: inputSound
plusObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound