# ============================================================
# Praat AudioTools - Entropy Smart De-Esser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Intelligent de-esser using high-frequency energy detection.
#   Detects sibilants (s, sh, ch) by comparing high-frequency
#   energy to full-band energy, then applies smooth gain reduction.
#
# Technical approach:
#   - Extracts high-frequency band (4-8 kHz) where sibilants live
#   - Compares HF intensity to full-band intensity
#   - High ratio = sibilant, low ratio = voiced sound
#   - Applies gain reduction only when ratio exceeds threshold
#   - True stereo processing preserves spatial image
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit
#   for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Smart De-Esser
    comment High-frequency energy-based sibilance detection.
    optionmenu Preset: 1
        option Custom
        option Light De-Essing
        option Medium De-Essing
        option Heavy De-Essing
        option Aggressive
        option Gentle Touch
    positive hf_low 4000
    positive hf_high 8000
    comment (sibilance detection band in Hz)
    real threshold 0.4
    comment (0-1: HF/total ratio above this = sibilant)
    positive max_reduction_db 12.0
    positive attack_ms 5
    positive release_ms 50
    real dry_wet_mix 1.0
    positive scale_peak 0.95
    boolean listen_to_removed 0
    boolean play_after_processing 1
    boolean draw_visualization 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Light De-Essing"
    threshold = 0.5
    max_reduction_db = 6
    attack_ms = 5
    release_ms = 60
elif preset$ = "Medium De-Essing"
    threshold = 0.4
    max_reduction_db = 10
    attack_ms = 5
    release_ms = 50
elif preset$ = "Heavy De-Essing"
    threshold = 0.3
    max_reduction_db = 15
    attack_ms = 3
    release_ms = 40
elif preset$ = "Aggressive"
    threshold = 0.25
    max_reduction_db = 18
    attack_ms = 2
    release_ms = 30
elif preset$ = "Gentle Touch"
    threshold = 0.55
    max_reduction_db = 4
    attack_ms = 8
    release_ms = 80
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Clamp HF band to Nyquist
if hf_high > nyquist * 0.95
    hf_high = nyquist * 0.95
endif
if hf_low > hf_high - 500
    hf_low = hf_high - 500
endif

minGainLinear = 10 ^ (-max_reduction_db / 20)
attackTime = attack_ms / 1000
releaseTime = release_ms / 1000

uniqueID$ = string$(randomInteger(10000, 99999))

# ============================================================
# Analysis
# ============================================================
writeInfoLine: "Smart De-Esser"
appendInfoLine: "=============="
appendInfoLine: "Input: ", originalName$
appendInfoLine: ""
appendInfoLine: "[1/4] Analyzing sibilance..."

# Convert to mono for analysis
if numChannels > 1
    selectObject: sound
    soundMono = Convert to mono
else
    selectObject: sound
    soundMono = Copy: "mono_" + uniqueID$
endif

# Get full-band intensity
selectObject: soundMono
fullIntensity = To Intensity: 100, 0, "yes"
Rename: "full_" + uniqueID$

# Get high-frequency band intensity
selectObject: soundMono
hfFiltered = Filter (pass Hann band): hf_low, hf_high, 100
hfIntensity = To Intensity: 100, 0, "yes"
Rename: "hf_" + uniqueID$

removeObject: hfFiltered

# ============================================================
# Compute sibilance ratio and gain curve
# ============================================================
appendInfoLine: "[2/4] Computing gain curve..."

# Sample at regular intervals
timeStep = 0.005
numFrames = floor(duration / timeStep)
if numFrames < 2
    numFrames = 2
endif

# Calculate ratio and gain for each frame
for i from 1 to numFrames
    t = (i - 1) * timeStep
    if t > duration
        t = duration
    endif
    
    timeVal[i] = t
    
    selectObject: fullIntensity
    fullDb = Get value at time: t, "Cubic"
    
    selectObject: hfIntensity
    hfDb = Get value at time: t, "Cubic"
    
    # Handle undefined values
    if fullDb = undefined
        fullDb = -80
    endif
    if hfDb = undefined
        hfDb = -80
    endif
    
    # Convert to linear and compute ratio
    fullLin = 10 ^ (fullDb / 20)
    hfLin = 10 ^ (hfDb / 20)
    
    if fullLin > 0.0001
        ratioVal[i] = hfLin / fullLin
    else
        ratioVal[i] = 0
    endif
    
    # Clamp ratio
    if ratioVal[i] > 1
        ratioVal[i] = 1
    endif
endfor

# ============================================================
# Apply attack/release smoothing
# ============================================================
appendInfoLine: "[3/4] Smoothing..."

attackCoef = 1 - exp(-2.2 / (attackTime / timeStep + 1))
releaseCoef = 1 - exp(-2.2 / (releaseTime / timeStep + 1))

smoothedRatio[1] = ratioVal[1]
for i from 2 to numFrames
    if ratioVal[i] > smoothedRatio[i-1]
        # Attack (rising)
        smoothedRatio[i] = smoothedRatio[i-1] + attackCoef * (ratioVal[i] - smoothedRatio[i-1])
    else
        # Release (falling)
        smoothedRatio[i] = smoothedRatio[i-1] + releaseCoef * (ratioVal[i] - smoothedRatio[i-1])
    endif
endfor

# Calculate gain from smoothed ratio
maxRatio = 0
minRatio = 1
framesReduced = 0

for i from 1 to numFrames
    r = smoothedRatio[i]
    
    if r > maxRatio
        maxRatio = r
    endif
    if r < minRatio
        minRatio = r
    endif
    
    if r < threshold
        gainVal[i] = 1
    else
        # Linear reduction above threshold
        reduction = (r - threshold) / (1 - threshold)
        gainVal[i] = 1 - reduction * (1 - minGainLinear)
        if gainVal[i] < minGainLinear
            gainVal[i] = minGainLinear
        endif
        framesReduced += 1
    endif
endfor

# ============================================================
# Create gain tier
# ============================================================
Create IntensityTier: "gain_" + uniqueID$, 0, duration
gainTier = selected("IntensityTier")

for i from 1 to numFrames
    Add point: timeVal[i], gainVal[i]
endfor

# ============================================================
# Apply gain
# ============================================================
appendInfoLine: "[4/4] Applying de-essing..."

if numChannels = 1
    selectObject: soundMono
    processed = Copy: "processed_" + uniqueID$
    
    if listen_to_removed = 0
        Formula: "self * IntensityTier_gain_'uniqueID$'(x)"
    else
        Formula: "self * (1 - IntensityTier_gain_'uniqueID$'(x))"
    endif
    
    if dry_wet_mix < 1 and listen_to_removed = 0
        selectObject: soundMono
        Rename: "dry_" + uniqueID$
        selectObject: processed
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dry_'uniqueID$'(x)"
        removeObject: "Sound dry_" + uniqueID$
    endif
    
    selectObject: processed
    finalOutput = selected("Sound")
else
    selectObject: sound
    Extract one channel: 1
    left = selected("Sound")
    
    selectObject: sound
    Extract one channel: 2
    right = selected("Sound")
    
    if listen_to_removed = 0
        selectObject: left
        Formula: "self * IntensityTier_gain_'uniqueID$'(x)"
        selectObject: right
        Formula: "self * IntensityTier_gain_'uniqueID$'(x)"
    else
        selectObject: left
        Formula: "self * (1 - IntensityTier_gain_'uniqueID$'(x))"
        selectObject: right
        Formula: "self * (1 - IntensityTier_gain_'uniqueID$'(x))"
    endif
    
    if dry_wet_mix < 1 and listen_to_removed = 0
        selectObject: sound
        Extract one channel: 1
        dryL = selected("Sound")
        Rename: "dryL_" + uniqueID$
        
        selectObject: sound
        Extract one channel: 2
        dryR = selected("Sound")
        Rename: "dryR_" + uniqueID$
        
        selectObject: left
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dryL_'uniqueID$'(x)"
        selectObject: right
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dryR_'uniqueID$'(x)"
        
        removeObject: dryL, dryR
    endif
    
    selectObject: left, right
    Combine to stereo
    finalOutput = selected("Sound")
    
    removeObject: left, right
endif

selectObject: finalOutput
Scale peak: scale_peak

if listen_to_removed = 0
    Rename: originalName$ + "_deessed"
else
    Rename: originalName$ + "_sibilants"
endif

# Cleanup
removeObject: soundMono, fullIntensity, hfIntensity, gainTier

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    Erase all
    
    if duration > 10
        timeTickInterval = 2
    elsif duration > 5
        timeTickInterval = 1
    elsif duration > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif
    
    # PANEL 1: Waveform with gain reduction
    Select outer viewport: 0, 6, 0, 2
    Select inner viewport: 0.6, 5.8, 0.3, 1.8
    
    selectObject: sound
    if numChannels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "orig_viz_" + uniqueID$
    endif
    
    selectObject: origMono
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Axes: 0, duration, 0, 1
    
    # Draw gain reduction
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 2
    for i from 1 to numFrames - 1
        g1 = 1 - gainVal[i]
        g2 = 1 - gainVal[i + 1]
        Draw line: timeVal[i], g1, timeVal[i + 1], g2
    endfor
    
    Line width: 1
    Black
    Draw inner box
    Text left: "yes", "Gain red."
    Text top: "no", "##Waveform + Reduction## (red curve)"
    
    removeObject: origMono
    
    # PANEL 2: HF ratio
    Select outer viewport: 0, 6, 2, 4
    Select inner viewport: 0.6, 5.8, 2.3, 3.8
    
    Axes: 0, duration, 0, 1
    
    # Threshold line
    Colour: "{0.8, 0.2, 0.2}"
    Dotted line
    Draw line: 0, threshold, duration, threshold
    Solid line
    
    # Ratio curve
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    for i from 1 to numFrames - 1
        Draw line: timeVal[i], smoothedRatio[i], timeVal[i + 1], smoothedRatio[i + 1]
    endfor
    
    Line width: 1
    Black
    Draw inner box
    Text left: "yes", "HF ratio"
    Text top: "no", "##Sibilance Ratio## (threshold: " + fixed$(threshold, 2) + ")"
    Marks left every: 1, 0.25, "yes", "yes", "no"
    
    # PANEL 3: Result spectrogram
    Select outer viewport: 0, 6, 4, 6
    Select inner viewport: 0.6, 5.8, 4.3, 5.8
    
    selectObject: finalOutput
    if numChannels > 1
        resultMono = Convert to mono
    else
        resultMono = Copy: "result_viz_" + uniqueID$
    endif
    
    selectObject: resultMono
    To Spectrogram: 0.005, 8000, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
    
    Black
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq"
    Text top: "no", "##Result##"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    removeObject: resultSpec, resultMono
endif

selectObject: finalOutput

if play_after_processing
    Play
endif

appendInfoLine: ""
appendInfoLine: "=============="
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", originalName$, if listen_to_removed = 0 then "_deessed" else "_sibilants" fi
appendInfoLine: "Channels: ", numChannels
appendInfoLine: ""
appendInfoLine: "HF band: ", hf_low, " - ", hf_high, " Hz"
appendInfoLine: "Threshold: ", fixed$(threshold, 2)
appendInfoLine: "Max reduction: ", max_reduction_db, " dB"
appendInfoLine: "HF ratio range: ", fixed$(minRatio, 2), " - ", fixed$(maxRatio, 2)
appendInfoLine: "Frames reduced: ", framesReduced, " / ", numFrames, " (", fixed$(framesReduced / numFrames * 100, 1), "%)"
if draw_visualization
    appendInfoLine: "Visualization in Picture window."
endif