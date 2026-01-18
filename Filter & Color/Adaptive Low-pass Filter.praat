# ============================================================
# Praat AudioTools - Adaptive_Low-pass_Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2025) 
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-varying low-pass filter using overlap-add spectral processing.
#   The cutoff frequency sweeps linearly from start to end over the
#   sound's duration, creating a dynamic filtering effect.
#
# ============================================================

# ============================================================
# Praat AudioTools - Adaptive_Low-pass_Filter_VISUAL.praat
# Version: 1.7 (Visual) - Graphics + Speed
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Adaptive Low-Pass Filter v1.7
    optionmenu Preset: 1
        option Manual
        option Gentle Sweep
        option Sharp Transition
        option Opening Filter
        option Closing Filter
        option Resonant Sweep
        option Acid Bass
        option Underwater
    comment === Filter sweep ===
    positive Start_cutoff_frequency 200
    positive End_cutoff_frequency 2000
    choice Sweep_type: 2
        option Linear
        option Logarithmic (Musical)
    comment === Filter character ===
    real Resonance 0.0
    positive Resonance_bandwidth 100
    comment === Performance ===
    optionmenu Performance_Mode: 2
        option Draft (Fastest - 80ms steps)
        option Standard (Balanced - 40ms steps)
        option High Quality (Slow - 20ms steps)
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 2
    start_cutoff_frequency = 300
    end_cutoff_frequency = 1500
    resonance = 0.2
    resonance_bandwidth = 120
    presetName$ = "GentleSweep"
elsif preset = 3
    start_cutoff_frequency = 100
    end_cutoff_frequency = 3000
    resonance = 0.3
    resonance_bandwidth = 80
    presetName$ = "SharpTransition"
elsif preset = 4
    start_cutoff_frequency = 150
    end_cutoff_frequency = 8000
    resonance = 0.4
    resonance_bandwidth = 100
    presetName$ = "Opening"
elsif preset = 5
    start_cutoff_frequency = 8000
    end_cutoff_frequency = 150
    resonance = 0.4
    resonance_bandwidth = 100
    presetName$ = "Closing"
elsif preset = 6
    start_cutoff_frequency = 200
    end_cutoff_frequency = 4000
    resonance = 0.8
    resonance_bandwidth = 60
    presetName$ = "ResonantSweep"
elsif preset = 7
    start_cutoff_frequency = 150
    end_cutoff_frequency = 3000
    resonance = 1.2
    resonance_bandwidth = 40
    presetName$ = "AcidBass"
elsif preset = 8
    start_cutoff_frequency = 800
    end_cutoff_frequency = 300
    resonance = 0.3
    resonance_bandwidth = 150
    presetName$ = "Underwater"
else
    presetName$ = "Manual"
endif

# Set window size
if performance_Mode = 1
    window_size_s = 0.08
    quality$ = "Draft"
elsif performance_Mode = 2
    window_size_s = 0.04
    quality$ = "Standard"
else
    window_size_s = 0.02
    quality$ = "High"
endif

# ============================================================
# Setup
# ============================================================
clearinfo
writeInfoLine: "=== Adaptive Low-Pass Filter v1.7 ==="
appendInfoLine: "Preset: ", presetName$, " (", quality$, ")"
appendInfoLine: "Sweep: ", start_cutoff_frequency, " -> ", end_cutoff_frequency, " Hz"

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

if start_cutoff_frequency >= nyquist
    start_cutoff_frequency = nyquist - 50
endif
if end_cutoff_frequency >= nyquist
    end_cutoff_frequency = nyquist - 50
endif

# ============================================================
# Visualization (Updated for Smooth Sweep)
# ============================================================
if draw_visualization
    Erase all
    
    # Viewport setup
    Select outer viewport: 0, 8, 0, 3.5
    Select inner viewport: 0.8, 7.5, 0.6, 3.0
    
    minFreq = 20
    maxFreq = min(nyquist, 12000)
    
    Axes: 0, duration, minFreq, maxFreq
    
    # Draw Background (Shaded Passband)
    # We use 50 points to draw the curve smoothly
    nPts = 50
    for i from 1 to nPts
        t1 = (i - 1) * duration / nPts
        t2 = i * duration / nPts
        p1 = (i - 1) / nPts
        
        # Calculate curve based on Sweep Type
        if sweep_type = 1
            # Linear
            c1 = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * p1
        else
            # Logarithmic
            c1 = start_cutoff_frequency * (end_cutoff_frequency / start_cutoff_frequency) ^ p1
        endif
        
        Paint rectangle: "{0.85, 0.92, 1.0}", t1, t2, minFreq, c1
    endfor
    
    # Draw Cutoff Line (Red)
    Colour: "Red"
    Line width: 2
    for i from 1 to nPts - 1
        t1 = (i - 1) * duration / nPts
        t2 = i * duration / nPts
        p1 = (i - 1) / nPts
        p2 = i / nPts
        
        if sweep_type = 1
            c1 = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * p1
            c2 = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * p2
        else
            c1 = start_cutoff_frequency * (end_cutoff_frequency / start_cutoff_frequency) ^ p1
            c2 = start_cutoff_frequency * (end_cutoff_frequency / start_cutoff_frequency) ^ p2
        endif
        
        Draw line: t1, c1, t2, c2
    endfor
    
    # Labels
    Line width: 1
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Cutoff Trajectory: " + originalName$
    
    Font size: 10
    Colour: "{0.2, 0.2, 0.8}"
    Text: 0.02, "left", start_cutoff_frequency, "half", string$(round(start_cutoff_frequency)) + " Hz"
    Text: duration * 0.98, "right", end_cutoff_frequency, "half", string$(round(end_cutoff_frequency)) + " Hz"
endif

# ============================================================
# Processing
# ============================================================
overlap = 0.5
hopDur = window_size_s * overlap
nSegs = floor((duration - window_size_s) / hopDur) + 1
if nSegs < 1
    window_size_s = duration
    hopDur = duration
    nSegs = 1
endif

appendInfoLine: "Processing ", nSegs, " segments..."

procedure processChannel: .inputSound
    selectObject: .inputSound
    .dur = Get total duration
    .sr = Get sampling frequency
    
    Create Sound from formula: "output_buffer", 1, 0, .dur, .sr, "0"
    .output = selected("Sound")
    .outputId$ = string$(.output)
    
    pi_val = 3.14159265
    
    for seg from 1 to nSegs
        # Time & Progress
        segStart = (seg - 1) * hopDur
        segEnd = segStart + window_size_s
        segMid = (segStart + segEnd) / 2
        progress = segMid / .dur
        if progress > 1
            progress = 1
        endif
        
        # Calculate Cutoff (Matching the Visual)
        if sweep_type = 1
            cutoff = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * progress
        else
            cutoff = start_cutoff_frequency * (end_cutoff_frequency / start_cutoff_frequency) ^ progress
        endif

        smoothing = max(50, cutoff * 0.15)
        lowBound = cutoff - smoothing
        highBound = cutoff + smoothing
        
        # Safety
        if lowBound < 0
            lowBound = 0
        endif
        if highBound > nyquist
            highBound = nyquist
        endif
        
        # Extract & FFT
        selectObject: .inputSound
        .seg = Extract part: segStart, segEnd, "Hanning", 1, "no"
        .spec = To Spectrum: "yes"
        
        # Filter
        low$ = string$(lowBound)
        high$ = string$(highBound)
        
        selectObject: .spec
        if resonance <= 0
            Formula: "if x < " + low$ + " then self else if x > " + high$ + " then 0 else self * 0.5 * (1 + cos(pi * (x - " + low$ + ") / (" + high$ + " - " + low$ + "))) endif endif"
        else
            cut$ = string$(cutoff)
            res$ = string$(resonance)
            bw$ = string$(resonance_bandwidth)
            Formula: "if x > " + high$ + " then 0 else if x < " + low$ + " then self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) else self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) * 0.5 * (1 + cos(pi * (x - " + low$ + ") / (" + high$ + " - " + low$ + "))) endif endif"
        endif
        
        To Sound
        .segFilt = selected("Sound")
        .segFiltId$ = string$(.segFilt)
        removeObject: .seg, .spec
        
        # Mix
        selectObject: .output
        startStr$ = string$(segStart)
        endStr$ = string$(segEnd)
        Formula: "if x >= " + startStr$ + " and x < " + endStr$ + " then self + Object_" + .segFiltId$ + "(x - " + startStr$ + ") else self endif"
        
        removeObject: .segFilt
        
        if seg mod 50 = 0
            appendInfo: "."
        endif
    endfor
    selectObject: .output
endproc

if numChannels = 1
    selectObject: sound
    inputMono = Copy: "input_mono"
    @processChannel: inputMono
    finalOutput = selected("Sound")
    removeObject: inputMono
else
    selectObject: sound
    Extract one channel: 1
    inputL = selected("Sound")
    selectObject: sound
    Extract one channel: 2
    inputR = selected("Sound")
    
    appendInfo: "L"
    @processChannel: inputL
    outputL = selected("Sound")
    appendInfoLine: ""
    appendInfo: "R"
    @processChannel: inputR
    outputR = selected("Sound")
    
    removeObject: inputL, inputR
    selectObject: outputL
    plusObject: outputR
    Combine to stereo
    finalOutput = selected("Sound")
    removeObject: outputL, outputR
endif

appendInfoLine: " Done."

selectObject: finalOutput
Scale peak: scale_peak
Rename: originalName$ + "_LPF_" + quality$

selectObject: sound
plusObject: finalOutput

if play_after_processing
    selectObject: finalOutput
    Play
endif