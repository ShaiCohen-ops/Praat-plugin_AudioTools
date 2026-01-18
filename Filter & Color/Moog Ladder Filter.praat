# ============================================================
# Praat AudioTools - Moog_Ladder_Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed syntax, added visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Moog Ladder Filter using TPT (Topology-Preserving Transform)
#   4-pole (24dB/oct) lowpass with resonance and automation
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

form Moog Ladder Filter v0.2
    optionmenu Preset: 1
        option Custom
        option Bass Filter (300 Hz, res 0.3)
        option Warm Pad (800 Hz, res 0.5)
        option Vocal Formant (1500 Hz, res 0.65)
        option Bright Sweep (2500 Hz, res 0.55)
        option Resonant Peak (1200 Hz, res 0.75)
        option Telephone (2800 Hz, res 0.35)
        option Sub Bass (150 Hz, res 0.2)
        option Acid Bass (500 Hz, res 0.75)
        option Cutoff Sweep Up (200-3000 Hz)
        option Cutoff Sweep Down (3000-200 Hz)
        option Resonance Sweep (res 0.1-0.85)
    comment === Static Parameters ===
    positive Cutoff_frequency 1000
    real Resonance 0.7
    comment (Resonance 0-1, higher = more peak)
    comment === Automation Parameters ===
    positive Start_cutoff 200
    positive End_cutoff 3000
    real Start_resonance 0.2
    real End_resonance 0.8
    comment === Output ===
    boolean DC_blocker 1
    optionmenu Limiter_type: 1
        option Soft (x/(1+|x|))
        option Analog-style (tanh)
    real Output_trim_dB 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

use_automation = 0

if preset = 2
    # Bass Filter
    cutoff_frequency = 300
    resonance = 0.3
    presetName$ = "BassFilter"
elsif preset = 3
    # Warm Pad
    cutoff_frequency = 800
    resonance = 0.5
    presetName$ = "WarmPad"
elsif preset = 4
    # Vocal Formant
    cutoff_frequency = 1500
    resonance = 0.65
    presetName$ = "VocalFormant"
elsif preset = 5
    # Bright Sweep
    cutoff_frequency = 2500
    resonance = 0.55
    presetName$ = "BrightSweep"
elsif preset = 6
    # Resonant Peak
    cutoff_frequency = 1200
    resonance = 0.75
    presetName$ = "ResonantPeak"
elsif preset = 7
    # Telephone
    cutoff_frequency = 2800
    resonance = 0.35
    presetName$ = "Telephone"
elsif preset = 8
    # Sub Bass
    cutoff_frequency = 150
    resonance = 0.2
    presetName$ = "SubBass"
elsif preset = 9
    # Acid Bass
    cutoff_frequency = 500
    resonance = 0.75
    presetName$ = "AcidBass"
elsif preset = 10
    # Cutoff Sweep Up
    start_cutoff = 200
    end_cutoff = 3000
    start_resonance = 0.5
    end_resonance = 0.5
    use_automation = 1
    presetName$ = "SweepUp"
elsif preset = 11
    # Cutoff Sweep Down
    start_cutoff = 3000
    end_cutoff = 200
    start_resonance = 0.5
    end_resonance = 0.5
    use_automation = 1
    presetName$ = "SweepDown"
elsif preset = 12
    # Resonance Sweep
    start_cutoff = 800
    end_cutoff = 800
    start_resonance = 0.1
    end_resonance = 0.85
    use_automation = 1
    presetName$ = "ResSweep"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: soundID
samplingFrequency = Get sampling frequency
duration = Get total duration
numberOfChannels = Get number of channels
nyquist = samplingFrequency / 2

# Output trim
trimGain = 10 ^ (output_trim_dB / 20)

# Clamp resonance
if resonance > 0.99
    resonance = 0.99
endif
if resonance < 0
    resonance = 0
endif

clearinfo
writeInfoLine: "=== Moog Ladder Filter v0.2 ==="
writeInfoLine: "Input: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Sample rate: ", samplingFrequency, " Hz"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$

if use_automation
    appendInfoLine: "Mode: Automation"
    appendInfoLine: "Cutoff: ", start_cutoff, " -> ", end_cutoff, " Hz"
    appendInfoLine: "Resonance: ", fixed$(start_resonance, 2), " -> ", fixed$(end_resonance, 2)
else
    appendInfoLine: "Mode: Static"
    appendInfoLine: "Cutoff: ", cutoff_frequency, " Hz"
    appendInfoLine: "Resonance: ", fixed$(resonance, 2)
endif
appendInfoLine: "Limiter: ", if limiter_type = 1 then "Soft" else "Tanh" fi
appendInfoLine: ""

# ============================================================
# AUTOMATION MODE
# ============================================================

if use_automation
    appendInfoLine: "Processing with automation..."
    
    # Chunk size for parameter updates (10ms)
    chunkDuration = 0.01
    numberOfChunks = ceiling(duration / chunkDuration)
    
    appendInfoLine: "Chunks: ", numberOfChunks
    
    # Process each chunk and store IDs
    for chunkIndex from 1 to numberOfChunks
        # Calculate time range
        t_start = (chunkIndex - 1) * chunkDuration
        t_end = chunkIndex * chunkDuration
        if t_end > duration
            t_end = duration
        endif
        
        # Interpolate parameters at chunk midpoint
        t_mid = (t_start + t_end) / 2
        progress = t_mid / duration
        
        # Exponential interpolation for cutoff (musical)
        cutoff_frequency = start_cutoff * exp(ln(end_cutoff / start_cutoff) * progress)
        
        # Linear interpolation for resonance
        resonance = start_resonance + (end_resonance - start_resonance) * progress
        
        # Extract chunk
        selectObject: soundID
        chunkID = Extract part: t_start, t_end, "rectangular", 1, "no"
        
        # Calculate TPT coefficients
        fc = cutoff_frequency / samplingFrequency
        wc = 2 * pi * fc
        g = tan(wc / 2)
        gg = g / (1 + g)
        gg_comp = 1 - gg
        
        # Resonance with power curve
        k = 4 * (resonance ^ 1.5)
        
        # Adaptive k cap for stability
        k_max = 3.9
        if g > 0.6
            k_max = 3.9 - (g - 0.6) * 3.0
            if k_max < 3.0
                k_max = 3.0
            endif
        endif
        if k > k_max
            k = k_max
        endif
        
        # Adaptive iterations
        iterations = 2
        if k > 3.0 or g > 0.5
            iterations = 3
        endif
        if k > 3.4 and g > 0.5
            iterations = 4
        endif
        
        # Create filter stages
        selectObject: chunkID
        stage1 = Copy: "stage1"
        stage2 = Copy: "stage2"
        stage3 = Copy: "stage3"
        stage4 = Copy: "stage4"
        feedback = Copy: "feedback"
        chunkResult = Copy: "chunk_result"
        
        selectObject: feedback
        Formula: "0"
        
        # Build coefficient strings
        k$ = string$(k)
        gg$ = string$(gg)
        ggc$ = string$(gg_comp)
        chunkId$ = string$(chunkID)
        
        for iteration from 1 to iterations
            selectObject: stage1
            Formula: "Object_" + chunkId$ + "(x) - " + k$ + " * self[col-1]"
            Formula: "self[col] * " + gg$ + " + self[col-1] * " + ggc$
            
            stage1Id$ = string$(stage1)
            selectObject: stage2
            Formula: "Object_" + stage1Id$ + "(x)"
            Formula: "self[col] * " + gg$ + " + self[col-1] * " + ggc$
            
            stage2Id$ = string$(stage2)
            selectObject: stage3
            Formula: "Object_" + stage2Id$ + "(x)"
            Formula: "self[col] * " + gg$ + " + self[col-1] * " + ggc$
            
            stage3Id$ = string$(stage3)
            selectObject: stage4
            Formula: "Object_" + stage3Id$ + "(x)"
            Formula: "self[col] * " + gg$ + " + self[col-1] * " + ggc$
            
            selectObject: feedback
            stage4Id$ = string$(stage4)
            Formula: "Object_" + stage4Id$ + "[col-1]"
        endfor
        
        # Copy result and apply gain
        trim$ = string$(trimGain)
        selectObject: chunkResult
        Formula: "Object_" + stage4Id$ + "(x) * " + trim$
        
        # Apply limiting
        if limiter_type = 1
            Formula: "self / (1 + abs(self))"
        else
            Formula: "tanh(0.8 * self)"
        endif
        
        # Store chunk result ID
        chunkResult_'chunkIndex' = chunkResult
        
        # Cleanup (keep chunkResult)
        removeObject: stage1, stage2, stage3, stage4, feedback, chunkID
    endfor
    
    # Concatenate all chunks
    selectObject: chunkResult_1
    for chunkIndex from 2 to numberOfChunks
        cid = chunkResult_'chunkIndex'
        plusObject: cid
    endfor
    resultID = Concatenate
    Rename: soundName$ + "_moog_" + presetName$
    
    # Cleanup chunk results
    for chunkIndex from 1 to numberOfChunks
        cid = chunkResult_'chunkIndex'
        removeObject: cid
    endfor
    
    # DC blocker
    if dC_blocker
        selectObject: resultID
        dcInput = Copy: "dc_input"
        dcOutput = Copy: "dc_output"
        
        alpha_dc = exp(-2 * pi * 20 / samplingFrequency)
        alpha_dc$ = string$(alpha_dc)
        resultId$ = string$(resultID)
        dcInId$ = string$(dcInput)
        
        selectObject: dcInput
        Formula: "Object_" + resultId$ + "(x)"
        
        selectObject: dcOutput
        Formula: "Object_" + dcInId$ + "[col] - Object_" + dcInId$ + "[col-1] + " + alpha_dc$ + " * self[col-1]"
        
        dcOutId$ = string$(dcOutput)
        selectObject: resultID
        Formula: "Object_" + dcOutId$ + "(x)"
        
        removeObject: dcInput, dcOutput
    endif

# ============================================================
# STATIC MODE
# ============================================================

else
    appendInfoLine: "Processing (static mode)..."
    
    # Calculate TPT coefficients
    fc = cutoff_frequency / samplingFrequency
    wc = 2 * pi * fc
    g = tan(wc / 2)
    gg = g / (1 + g)
    gg_comp = 1 - gg
    
    # Resonance with power curve
    k = 4 * (resonance ^ 1.5)
    
    # Adaptive k cap
    k_max = 3.9
    if g > 0.6
        k_max = 3.9 - (g - 0.6) * 3.0
        if k_max < 3.0
            k_max = 3.0
        endif
    endif
    if k > k_max
        k = k_max
    endif
    
    appendInfoLine: "TPT coefficients: g=", fixed$(g, 4), " k=", fixed$(k, 2)
    
    # Adaptive iterations
    iterations = 2
    if k > 3.0 or g > 0.5
        iterations = 3
    endif
    if k > 3.4 and g > 0.5
        iterations = 4
    endif
    
    appendInfoLine: "Iterations: ", iterations
    
    # Create working copies
    selectObject: soundID
    stage1 = Copy: "stage1"
    stage2 = Copy: "stage2"
    stage3 = Copy: "stage3"
    stage4 = Copy: "stage4"
    feedback = Copy: "feedback"
    resultID = Copy: soundName$ + "_moog_" + presetName$
    
    selectObject: feedback
    Formula: "0"
    
    # Build coefficient strings
    k$ = string$(k)
    gg$ = string$(gg)
    ggc$ = string$(gg_comp)
    soundId$ = string$(soundID)
    
    for iteration from 1 to iterations
        # Stage 1: input - k*feedback, then lowpass
        fbId$ = string$(feedback)
        selectObject: stage1
        Formula: "Object_" + soundId$ + "(x) - " + k$ + " * Object_" + fbId$ + "(x)"
        Formula: "self[col] * " + gg$ + " + self[col-1] * " + ggc$
        
        # Stage 2
        stage1Id$ = string$(stage1)
        selectObject: stage2
        Formula: "Object_" + stage1Id$ + "(x)"
        Formula: "self[col] * " + gg$ + " + self[col-1] * " + ggc$
        
        # Stage 3
        stage2Id$ = string$(stage2)
        selectObject: stage3
        Formula: "Object_" + stage2Id$ + "(x)"
        Formula: "self[col] * " + gg$ + " + self[col-1] * " + ggc$
        
        # Stage 4
        stage3Id$ = string$(stage3)
        selectObject: stage4
        Formula: "Object_" + stage3Id$ + "(x)"
        Formula: "self[col] * " + gg$ + " + self[col-1] * " + ggc$
        
        # Update feedback
        stage4Id$ = string$(stage4)
        selectObject: feedback
        Formula: "Object_" + stage4Id$ + "[col-1]"
    endfor
    
    # Copy result with trim
    trim$ = string$(trimGain)
    selectObject: resultID
    Formula: "Object_" + stage4Id$ + "(x) * " + trim$
    
    # Apply limiting
    if limiter_type = 1
        Formula: "self / (1 + abs(self))"
    else
        Formula: "tanh(0.8 * self)"
    endif
    
    # DC blocker
    if dC_blocker
        selectObject: resultID
        dcInput = Copy: "dc_input"
        dcOutput = Copy: "dc_output"
        
        alpha_dc = exp(-2 * pi * 20 / samplingFrequency)
        alpha_dc$ = string$(alpha_dc)
        resultId$ = string$(resultID)
        dcInId$ = string$(dcInput)
        
        selectObject: dcInput
        Formula: "Object_" + resultId$ + "(x)"
        
        selectObject: dcOutput
        Formula: "Object_" + dcInId$ + "[col] - Object_" + dcInId$ + "[col-1] + " + alpha_dc$ + " * self[col-1]"
        
        dcOutId$ = string$(dcOutput)
        selectObject: resultID
        Formula: "Object_" + dcOutId$ + "(x)"
        
        removeObject: dcInput, dcOutput
    endif
    
    # Cleanup
    removeObject: stage1, stage2, stage3, stage4, feedback
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    # Create spectra for comparison
    selectObject: soundID
    origSpecID = To Spectrum: "yes"
    
    selectObject: resultID
    resSpecID = To Spectrum: "yes"
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Moog Ladder Filter: " + soundName$ + " [" + presetName$ + "]"
    
    # Waveform comparison
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.75, 1.85
    
    selectObject: soundID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Waveform (gray=original, blue=filtered)"
    Text left: "yes", "Amp"
    
    # Spectrum comparison
    Select outer viewport: 0, 8, 2.2, 4.2
    Select inner viewport: 0.6, 7.6, 2.4, 4.0
    
    selectObject: origSpecID
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 1
    Draw: 0, 8000, 0, 80, "no"
    
    selectObject: resSpecID
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    Draw: 0, 8000, 0, 80, "no"
    
    # Mark cutoff frequency
    if use_automation = 0
        Colour: "{0.9, 0.3, 0.3}"
        Line width: 1
        Axes: 0, 8000, 0, 80
        Dotted line
        Draw line: cutoff_frequency, 0, cutoff_frequency, 80
        Solid line
    endif
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Text top: "no", "Spectrum (gray=original, blue=filtered)"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Filter response curve (theoretical)
    Select outer viewport: 0, 4, 4.4, 6.0
    Select inner viewport: 0.6, 3.6, 4.6, 5.8
    
    if use_automation = 0
        # Draw idealized 24dB/oct slope
        Axes: 1, 4, -60, 10
        
        Colour: "{0.9, 0.5, 0.2}"
        Line width: 2
        
        # Passband
        logCutoff = log10(cutoff_frequency)
        Draw line: 1, 0, logCutoff, 0
        
        # Resonance peak
        if resonance > 0.3
            peakHeight = resonance * 15
            Draw line: logCutoff, 0, logCutoff, peakHeight
            Draw line: logCutoff, peakHeight, logCutoff + 0.1, 0
        endif
        
        # Slope (-24dB/octave = -24dB per factor of 2 in frequency)
        # In log10 terms: -24 / log10(2) per unit = -80dB/decade approximately
        for i from 1 to 20
            f1 = cutoff_frequency * (1.1 ^ (i - 1))
            f2 = cutoff_frequency * (1.1 ^ i)
            if f2 < 10000
                log1 = log10(f1)
                log2 = log10(f2)
                db1 = -24 * log2(f1 / cutoff_frequency)
                db2 = -24 * log2(f2 / cutoff_frequency)
                if db1 > -60 and db2 > -60
                    Draw line: log1, db1, log2, db2
                endif
            endif
        endfor
        
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text top: "no", "Filter Response (24dB/oct)"
        Text left: "yes", "dB"
        Text bottom: "yes", "log Freq"
        
        # Mark cutoff
        Colour: "{0.9, 0.3, 0.3}"
        Dotted line
        Draw line: logCutoff, -60, logCutoff, 10
        Solid line
        Font size: 7
        Text: logCutoff, "centre", -55, "half", string$(cutoff_frequency) + " Hz"
    else
        # Draw automation envelope
        Axes: 0, 1, 0, max(end_cutoff, start_cutoff) * 1.1
        
        Colour: "{0.9, 0.5, 0.2}"
        Line width: 2
        
        # Draw cutoff sweep
        for i from 0 to 50
            p1 = i / 50
            p2 = (i + 1) / 50
            c1 = start_cutoff * exp(ln(end_cutoff / start_cutoff) * p1)
            c2 = start_cutoff * exp(ln(end_cutoff / start_cutoff) * p2)
            Draw line: p1, c1, p2, c2
        endfor
        
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text top: "no", "Cutoff Automation"
        Text left: "yes", "Hz"
        Text bottom: "yes", "Time (normalized)"
    endif
    
    # Info panel
    Select outer viewport: 4, 8, 4.4, 6.0
    Select inner viewport: 4.5, 7.7, 4.6, 5.85
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    
    if use_automation
        Text: 0.05, "left", 0.85, "half", "Mode: Automation"
        Text: 0.05, "left", 0.65, "half", "Cutoff: " + string$(start_cutoff) + " -> " + string$(end_cutoff) + " Hz"
        Text: 0.05, "left", 0.45, "half", "Resonance: " + fixed$(start_resonance, 2) + " -> " + fixed$(end_resonance, 2)
    else
        Text: 0.05, "left", 0.85, "half", "Mode: Static"
        Text: 0.05, "left", 0.65, "half", "Cutoff: " + string$(cutoff_frequency) + " Hz"
        Text: 0.05, "left", 0.45, "half", "Resonance: " + fixed$(resonance, 2) + " (k=" + fixed$(k, 2) + ")"
    endif
    
    Text: 0.05, "left", 0.25, "half", "Limiter: " + if limiter_type = 1 then "Soft" else "Tanh" fi
    Text: 0.05, "left", 0.08, "half", "DC Block: " + if dC_blocker then "On" else "Off" fi
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    
    removeObject: origSpecID, resSpecID
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", soundName$, "_moog_", presetName$

if play_result
    selectObject: resultID
    Play
endif

selectObject: soundID
