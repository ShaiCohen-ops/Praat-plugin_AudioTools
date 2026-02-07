# ============================================================
# Praat AudioTools - Onset-Based Oscillator Bank v2.0
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - OPTIMIZED + VISUALIZATION
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Onset-triggered resonator bank. Detects onsets via intensity 
#   derivative, extracts pitch, and synthesizes harmonic bursts with 
#   ADSR envelopes. Each onset triggers a multi-partial oscillator 
#   with detuning, brightness control, and waveshaping.
#
# Features:
#   - Intensity-based onset detection with configurable threshold
#   - Pitch extraction with multiple fallback methods
#   - Harmonic oscillator bank (1-32 partials) with detuning
#   - ADSR envelopes with randomization
#   - Waveshaping (sin³) for brightness
#   - Velocity sensitivity (onset strength → burst amplitude)
#   - Speed modes for faster processing
#   - Comprehensive visualization: onsets, pitches, bursts, spectrum
#   - 6 presets from gentle to dense
#
# Categories: Resynthesis, Pitch-Based Effects, Creative Effects
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis 
#   Toolkit for Experimental Composition.
# ============================================================

form Onset-Based Oscillator Bank v2.0
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Gentle Resonance
        option Percussive Bells
        option Ethereal Pad
        option Metallic Shimmer
        option Natural Pluck
        option Dense Cluster
    
    comment === Onset Detection ===
    positive Onset_threshold_(dB) 1.5
    positive Min_intensity_(dB) 35.0
    positive Min_interval_(s) 0.1
    boolean Velocity_sensitive 1
    
    comment === Oscillators (Custom only) ===
    integer Num_partials 12
    positive Partial_spread 0.5
    positive Decay_(s) 1.5
    real Brightness 0.7
    
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 16 kHz)
    
    comment === Output ===
    positive Tail_duration_(s) 2.0
    positive Fadeout_duration_(s) 0.5
    real Dry_wet_mix 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET DEFINITIONS
# ============================================================
attackBase = 0.005
attackRandom = 0.01
decayRandom = 0.5
ampRandom = 0.3
waveshapeAmt = 0.2
decayTime = decay

if preset = 2
    # Gentle Resonance
    onset_threshold = 2.0
    min_intensity = 35.0
    min_interval = 0.15
    num_partials = 8
    partial_spread = 0.3
    decayTime = 2.0
    brightness = 0.5
    dry_wet_mix = 0.7
    attackBase = 0.01
    waveshapeAmt = 0.1
    presetName$ = "GentleResonance"
elsif preset = 3
    # Percussive Bells
    onset_threshold = 1.5
    min_intensity = 40.0
    min_interval = 0.08
    num_partials = 15
    partial_spread = 0.8
    decayTime = 1.0
    brightness = 0.9
    dry_wet_mix = 1.0
    attackBase = 0.002
    waveshapeAmt = 0.3
    presetName$ = "PercussiveBells"
elsif preset = 4
    # Ethereal Pad
    onset_threshold = 2.5
    min_intensity = 30.0
    min_interval = 0.2
    num_partials = 20
    partial_spread = 0.2
    decayTime = 3.5
    brightness = 0.6
    dry_wet_mix = 0.8
    attackBase = 0.05
    waveshapeAmt = 0.15
    presetName$ = "EtherealPad"
elsif preset = 5
    # Metallic Shimmer
    onset_threshold = 1.2
    min_intensity = 35.0
    min_interval = 0.1
    num_partials = 18
    partial_spread = 1.0
    decayTime = 1.2
    brightness = 1.0
    dry_wet_mix = 1.0
    attackBase = 0.003
    waveshapeAmt = 0.4
    presetName$ = "MetallicShimmer"
elsif preset = 6
    # Natural Pluck
    onset_threshold = 1.5
    min_intensity = 35.0
    min_interval = 0.12
    num_partials = 6
    partial_spread = 0.4
    decayTime = 0.8
    brightness = 0.7
    dry_wet_mix = 0.9
    attackBase = 0.001
    waveshapeAmt = 0.15
    presetName$ = "NaturalPluck"
elsif preset = 7
    # Dense Cluster
    onset_threshold = 1.0
    min_intensity = 32.0
    min_interval = 0.05
    num_partials = 25
    partial_spread = 1.2
    decayTime = 1.8
    brightness = 0.8
    dry_wet_mix = 1.0
    attackBase = 0.008
    waveshapeAmt = 0.25
    presetName$ = "DenseCluster"
else
    presetName$ = "Custom"
endif

# Speed mode
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 16000
    speedStr$ = "Fast"
endif

startTime = stopwatch

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
name$ = selected$("Sound")
totalDur = Get total duration
origSR = Get sampling frequency
numChan = Get number of channels

if totalDur < 0.1
    exitScript: "Sound too short (min 0.1s)."
endif

writeInfoLine: "=== Onset-Based Oscillator Bank v2.0 ==="
appendInfoLine: "Input: ", name$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: ""

# Optional downsampling
workingSound = sound
if targetSR > 0 and origSR > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz"
    selectObject: sound
    Resample: targetSR, 50
    workingSound = selected("Sound")
    workingSR = targetSR
else
    workingSR = origSR
endif

selectObject: workingSound
sampleRate = Get sampling frequency
nyquistFreq = sampleRate / 2

# ============================================================
# ONSET DETECTION
# ============================================================
appendInfo: "Stage 1: Detecting onsets... "

selectObject: workingSound
intensityObj = To Intensity: 50, 0, "yes"

selectObject: intensityObj
numFrames = Get number of frames

# Allocate arrays
onset_times# = zero#(500)
onset_velocities# = zero#(500)
numOnsets = 0
lastOnset = -1

for iFrame from 3 to numFrames - 1
    frameTime = Get time from frame number: iFrame
    currInt = Get value in frame: iFrame
    prev2Int = Get value in frame: iFrame - 2
    
    if currInt <> undefined and prev2Int <> undefined
        intDiff = (currInt - prev2Int) / 2
        if intDiff > onset_threshold and currInt > min_intensity
            if frameTime - lastOnset > min_interval
                numOnsets += 1
                onset_times#[numOnsets] = frameTime
                
                # Store velocity (normalized intensity jump)
                velocity = (intDiff - onset_threshold) / 10
                velocity = min(1, max(0.3, velocity))
                onset_velocities#[numOnsets] = velocity
                
                lastOnset = frameTime
            endif
        endif
    endif
endfor

removeObject: intensityObj

if numOnsets = 0
    if workingSound <> sound
        removeObject: workingSound
    endif
    exitScript: "No onsets found. Try lowering threshold."
endif

appendInfoLine: numOnsets, " onsets"

# ============================================================
# PITCH EXTRACTION
# ============================================================
appendInfo: "Stage 2: Extracting pitches... "

onset_pitches# = zero#(numOnsets)

for onsetIdx from 1 to numOnsets
    onsetTime = onset_times#[onsetIdx]
    
    selectObject: workingSound
    segStart = max(0, onsetTime - 0.02)
    segEnd = min(onsetTime + 0.12, totalDur)
    
    if segEnd - segStart > 0.03
        Extract part: segStart, segEnd, "rectangular", 1, "no"
        segment = selected("Sound")
        
        To Pitch (ac): 0, 50, 15, "no", 0.01, 0.5, 0.01, 0.2, 0.1, 2500
        pitchObj = selected("Pitch")
        
        relTime = onsetTime - segStart
        detectedPitch = Get value at time: relTime, "Hertz", "Linear"
        
        if detectedPitch = undefined or detectedPitch <= 0
            detectedPitch = Get mean: 0, 0, "Hertz"
        endif
        if detectedPitch = undefined or detectedPitch <= 0
            detectedPitch = Get quantile: 0, 0, 0.5, "Hertz"
        endif
        
        removeObject: segment, pitchObj
        
        # Store valid pitch
        if detectedPitch <> undefined and detectedPitch >= 50 and detectedPitch < 4000
            onset_pitches#[onsetIdx] = detectedPitch
        else
            onset_pitches#[onsetIdx] = 0
        endif
    else
        onset_pitches#[onsetIdx] = 0
    endif
endfor

appendInfoLine: "done"

# ============================================================
# SYNTHESIZE OSCILLATOR BANK (OPTIMIZED)
# ============================================================
# ============================================================
# CREATE OUTPUT WITH TAIL
# ============================================================
appendInfo: "Stage 3: Synthesizing bursts... "

# Add tail space for burst decay
totalDurWithTail = totalDur + tail_duration

wetSignal = Create Sound from formula: "wet", numChan, 0, totalDurWithTail, sampleRate, "0"

maxBurstDur = attackBase + attackRandom + (decayTime + decayRandom) * 4
maxBurstDur = min(maxBurstDur, 5)

validOnsets = 0

for onsetIdx from 1 to numOnsets
    detectedPitch = onset_pitches#[onsetIdx]
    
    if detectedPitch > 0
        validOnsets += 1
        onsetTime = onset_times#[onsetIdx]
        velocity = onset_velocities#[onsetIdx]
        
        # Apply velocity sensitivity
        if velocity_sensitive
            ampScale = velocity
        else
            ampScale = 1.0
        endif
        
        # Allow bursts to extend into tail
        burstEnd = min(onsetTime + maxBurstDur, totalDurWithTail)
        burstDur = burstEnd - onsetTime
        
        if burstDur > 0.01
            maxPartial = min(num_partials, floor(nyquistFreq * 0.9 / detectedPitch))
            
            # BUILD ALL PARTIALS IN ONE FORMULA (FAST!)
            formula$ = "0"
            
            for partialNum from 1 to maxPartial
                partialFreq = detectedPitch * partialNum * (1 + randomUniform(-0.01, 0.01) * partial_spread)
                
                if partialFreq < nyquistFreq * 0.95
                    attackTime = attackBase + randomUniform(0, attackRandom)
                    decayVal = decayTime + randomUniform(-decayRandom, decayRandom)
                    decayVal = max(decayVal, 0.05)
                    
                    ampVal = (0.1 / sqrt(partialNum)) * (brightness ^ (partialNum - 1)) * ampScale
                    ampVal = ampVal * (1 + randomUniform(-ampRandom, ampRandom))
                    
                    wsBlend = waveshapeAmt * brightness
                    ampClean = ampVal * (1 - wsBlend)
                    ampWS = ampVal * wsBlend
                    
                    attStr$ = fixed$(attackTime, 6)
                    decStr$ = fixed$(decayVal, 6)
                    freqStr$ = fixed$(partialFreq, 3)
                    
                    # Envelope
                    env$ = "(if x<" + attStr$ + " then x/" + attStr$ + " else exp(-(x-" + attStr$ + ")/" + decStr$ + ") fi)"
                    
                    # Clean sine
                    if ampClean > 0.001
                        ampStr$ = fixed$(ampClean, 6)
                        formula$ = formula$ + "+" + ampStr$ + "*sin(2*pi*" + freqStr$ + "*x)*" + env$
                    endif
                    
                    # Waveshaped
                    if ampWS > 0.001
                        ampWSStr$ = fixed$(ampWS, 6)
                        formula$ = formula$ + "+" + ampWSStr$ + "*(sin(2*pi*" + freqStr$ + "*x)^3)*" + env$
                    endif
                endif
            endfor
            
            # Create burst with all partials at once
            burstSound = Create Sound from formula: "burst", 1, 0, burstDur, sampleRate, formula$
            
            # Add to wet signal
            onsetStr$ = fixed$(onsetTime, 8)
            selectObject: wetSignal
            Formula (part): onsetTime, burstEnd, 1, numChan, "self + Sound_burst(x - " + onsetStr$ + ")"
            
            removeObject: burstSound
        endif
    endif
    
    if onsetIdx mod 10 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: " ", validOnsets, " bursts"

# ============================================================
# MIX AND FINALIZE
# ============================================================
appendInfo: "Stage 4: Mixing... "

# Apply fadeout to wet signal
if fadeout_duration > 0
    selectObject: wetSignal
    fadeStart = totalDurWithTail - fadeout_duration
    Formula (part): fadeStart, totalDurWithTail, 1, numChan, 
    ... "self * (1 - (x - " + fixed$(fadeStart, 6) + ") / " + fixed$(fadeout_duration, 6) + ")"
endif

# Upsample if needed
if targetSR > 0 and origSR > targetSR
    selectObject: wetSignal
    Resample: origSR, 50
    wetUpsampled = selected("Sound")
    removeObject: wetSignal
    wetSignal = wetUpsampled
    finalSR = origSR
else
    finalSR = sampleRate
endif

# Get wet signal name
selectObject: wetSignal
wetName$ = selected$("Sound")

# Get original sound name for formula
selectObject: sound
origName$ = selected$("Sound")

# Create extended output (original + tail)
selectObject: sound
numChannels = Get number of channels

if numChannels = 1
    output = Create Sound from formula: name$ + "_resonated_" + presetName$, 1, 0, totalDurWithTail, finalSR,
    ... "if x < totalDur then Sound_'origName$'(x) else 0 fi"
else
    output = Create Sound from formula: name$ + "_resonated_" + presetName$, 2, 0, totalDurWithTail, finalSR,
    ... "if x < totalDur then Sound_'origName$'(x, col) else 0 fi"
endif

# Apply mix
selectObject: output

if dry_wet_mix >= 0.99
    Formula: "Sound_'wetName$'[]"
elsif dry_wet_mix <= 0.01
    # Keep original (with tail silence)
else
    wetStr$ = fixed$(dry_wet_mix, 4)
    dryStr$ = fixed$(1 - dry_wet_mix, 4)
    Formula: "self * " + dryStr$ + " + Sound_'wetName$'[] * " + wetStr$
endif

Scale peak: 0.95

processingTime = stopwatch - startTime

appendInfoLine: "done"
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Valid onsets: ", validOnsets, " / ", numOnsets
appendInfoLine: "Tail duration: ", fixed$(tail_duration, 2), " seconds"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Onset-Based Oscillator Bank: " + name$ + " [" + presetName$ + "]"
    
    # Waveform with onset markers
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.5, 7.7, 0.7, 1.9
    selectObject: sound
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark onsets
    maxAmp = Get maximum: 0, 0, "None"
    minAmp = Get minimum: 0, 0, "None"
    
    for i to numOnsets
        if onset_pitches#[i] > 0
            Colour: "{0.9, 0.3, 0.3}"
        else
            Colour: "{0.5, 0.5, 0.5}"
        endif
        Draw line: onset_times#[i], minAmp, onset_times#[i], maxAmp
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original Waveform + Onsets (red = valid pitch)"
    Text left: "yes", "Amp"
    
    # Processed waveform
    Select outer viewport: 0, 8, 2.2, 3.2
    Select inner viewport: 0.5, 7.7, 2.3, 3.1
    selectObject: output
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Processed"
    Text left: "yes", "Amp"
    
    # Pitch track
    Select outer viewport: 0, 4, 3.4, 4.6
    Select inner viewport: 0.5, 3.7, 3.5, 4.5
    
    minPitch = 5000
    maxPitch = 0
    for i to numOnsets
        if onset_pitches#[i] > 0
            if onset_pitches#[i] < minPitch
                minPitch = onset_pitches#[i]
            endif
            if onset_pitches#[i] > maxPitch
                maxPitch = onset_pitches#[i]
            endif
        endif
    endfor
    
    if maxPitch > minPitch
        Axes: 0, totalDur, minPitch * 0.9, maxPitch * 1.1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalDur, minPitch * 0.9, maxPitch * 1.1
        
        Colour: "{0.3, 0.6, 0.3}"
        Line width: 3
        
        for i to numOnsets
            if onset_pitches#[i] > 0
                Draw circle: onset_times#[i], onset_pitches#[i], 0.02
            endif
        endfor
        
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Detected Pitches"
        Text left: "yes", "Hz"
        Text bottom: "yes", "Time (s)"
    endif
    
    # Velocity profile
    Select outer viewport: 4, 8, 3.4, 4.6
    Select inner viewport: 4.5, 7.7, 3.5, 4.5
    
    Axes: 0, totalDur, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalDur, 0, 1.1
    
    Colour: "{0.7, 0.4, 0.2}"
    Line width: 2
    
    for i to numOnsets
        if onset_pitches#[i] > 0
            vel = onset_velocities#[i]
            Draw line: onset_times#[i], 0, onset_times#[i], vel
        endif
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Onset Velocities"
    Text left: "yes", "Level"
    Text bottom: "yes", "Time (s)"
    
    # Info panel
    Select outer viewport: 0, 8, 4.8, 5.3
    Select inner viewport: 0.5, 7.7, 4.85, 5.25
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.5, "half", speedStr$ + " | Time: " + fixed$(processingTime, 2) + "s | Onsets: " + string$(validOnsets) + "/" + string$(numOnsets) + " | Partials: " + string$(num_partials)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: wetSignal

if workingSound <> sound
    removeObject: workingSound
endif

selectObject: output

if play_result
    Play
endif

selectObject: sound
