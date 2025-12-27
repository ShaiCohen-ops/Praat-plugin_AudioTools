# ============================================================
# Praat AudioTools - Creative Formant Manipulations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formant manipulation using LPC source-filter decomposition.
#   Separates the excitation signal (source) from the vocal tract
#   resonances (filter), manipulates the formants, then resynthesizes.
#
# Technical approach:
#   - LPC inverse filtering extracts excitation signal
#   - FormantPath analysis tracks formant trajectories
#   - FormantGrid manipulation applies creative effects
#   - Source-filter resynthesis creates modified audio
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

form Creative Formant Manipulations
    optionmenu Preset: 1
        option Custom
        option Robot Voice
        option Chipmunk
        option Giant
        option Alien
        option Wobble
        option Vowel Morph
    optionmenu Manipulation_type: 1
        option Rotation (vowel morphing)
        option Reversal (spectral flip)
        option Scrambling (randomize)
        option Scaling (gender shift)
        option LFO Modulation
        option Crossfade (temporal blend)
        option Freezing (hold vowels)
    positive max_formant_hz 5500
    real rotation_semitones 3.0
    real scale_frequency 0.8
    real scale_bandwidth 1.2
    positive lfo_rate 2.0
    positive lfo_depth 6.0
    positive freeze_interval 0.3
    positive freeze_duration 0.15
    real dry_wet_mix 1.0
    boolean play_after_processing 1
    boolean draw_visualization 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Robot Voice"
    manipulation_type = 7
    freeze_interval = 0.08
    freeze_duration = 0.08
elif preset$ = "Chipmunk"
    manipulation_type = 4
    scale_frequency = 1.4
    scale_bandwidth = 0.8
elif preset$ = "Giant"
    manipulation_type = 4
    scale_frequency = 0.7
    scale_bandwidth = 1.3
elif preset$ = "Alien"
    manipulation_type = 2
elif preset$ = "Wobble"
    manipulation_type = 5
    lfo_rate = 4.0
    lfo_depth = 8.0
elif preset$ = "Vowel Morph"
    manipulation_type = 6
endif

# ============================================================
# Fixed parameters
# ============================================================
time_step = 0.005
max_formants = 5
window_length = 0.025
preEmphasis = 50
crossfade_cycles = 3
scale_peak = 0.95

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

# Generate unique ID
uniqueID$ = string$(randomInteger(10000, 99999))

# ============================================================
# Get manipulation type name
# ============================================================
if manipulation_type = 1
    manipName$ = "Rotation"
elif manipulation_type = 2
    manipName$ = "Reversal"
elif manipulation_type = 3
    manipName$ = "Scrambling"
elif manipulation_type = 4
    manipName$ = "Scaling"
elif manipulation_type = 5
    manipName$ = "LFO"
elif manipulation_type = 6
    manipName$ = "Crossfade"
else
    manipName$ = "Freeze"
endif

# ============================================================
# Convert to mono for analysis
# ============================================================
if numChannels > 1
    selectObject: sound
    soundMono = Convert to mono
else
    selectObject: sound
    soundMono = Copy: "mono_" + uniqueID$
endif

# ============================================================
# STEP 1: Extract source excitation
# ============================================================
writeInfoLine: "Creative Formant Manipulations"
appendInfoLine: "=============================="
appendInfoLine: "Effect: ", manipName$
appendInfoLine: ""
appendInfoLine: "[1/4] Extracting source excitation..."

selectObject: soundMono
lpc = To LPC (burg): max_formants * 2, window_length, time_step, preEmphasis

selectObject: soundMono, lpc
sourceExcitation = Filter (inverse)
Rename: "source_" + uniqueID$

# ============================================================
# STEP 2: Analyze formants
# ============================================================
appendInfoLine: "[2/4] Analyzing formants..."

selectObject: soundMono
formantPath = To FormantPath (burg): time_step, max_formants, max_formant_hz, window_length, preEmphasis, 0.05, 4
formantObj = Extract Formant

selectObject: formantObj
numFrames = Get number of frames

# Initialize all array values to undefined first
for i from 1 to numFrames
    for f from 1 to max_formants
        formantFreq[i, f] = undefined
        formantBand[i, f] = undefined
        origFormantFreq[i, f] = undefined
    endfor
endfor

# Cache formant data
for i from 1 to numFrames
    frameTime[i] = Get time from frame number: i
    numFormantsInFrame[i] = Get number of formants: i
    for f from 1 to numFormantsInFrame[i]
        formantFreq[i, f] = Get value at time: f, frameTime[i], "hertz", "Linear"
        formantBand[i, f] = Get bandwidth at time: f, frameTime[i], "hertz", "Linear"
        origFormantFreq[i, f] = formantFreq[i, f]
    endfor
endfor

# Convert to FormantGrid
selectObject: formantObj
formantGrid = Down to FormantGrid

# ============================================================
# STEP 3: Apply manipulation
# ============================================================
appendInfoLine: "[3/4] Applying ", manipName$, "..."

selectObject: formantGrid

# --- ROTATION ---
if manipulation_type = 1
    factor = 2 ^ (rotation_semitones / 12)
    for i from 1 to numFrames
        for f from 1 to numFormantsInFrame[i]
            hz = formantFreq[i, f]
            if hz <> undefined
                newHz = hz * factor
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                    Add formant point: f, frameTime[i], newHz
                    formantFreq[i, f] = newHz
                endif
            endif
        endfor
    endfor

# --- REVERSAL ---
elif manipulation_type = 2
    for i from 1 to numFrames
        for f from 1 to max_formants
            if f <= numFormantsInFrame[i]
                tempFreq[f] = formantFreq[i, f]
                tempBand[f] = formantBand[i, f]
            else
                tempFreq[f] = undefined
                tempBand[f] = undefined
            endif
        endfor
        
        for f from 1 to max_formants
            srcF = max_formants - f + 1
            if tempFreq[srcF] <> undefined
                Remove formant points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                Add formant point: f, frameTime[i], tempFreq[srcF]
                Remove bandwidth points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                Add bandwidth point: f, frameTime[i], tempBand[srcF]
                formantFreq[i, f] = tempFreq[srcF]
            endif
        endfor
    endfor

# --- SCRAMBLING ---
elif manipulation_type = 3
    for i from 1 to numFrames
        for f from 1 to max_formants
            if f <= numFormantsInFrame[i]
                tempFreq[f] = formantFreq[i, f]
                tempBand[f] = formantBand[i, f]
            else
                tempFreq[f] = undefined
                tempBand[f] = undefined
            endif
        endfor
        
        for k from 1 to max_formants
            perm[k] = k
        endfor
        
        for k from max_formants to 2
            r = randomInteger(1, k)
            swap = perm[k]
            perm[k] = perm[r]
            perm[r] = swap
        endfor
        
        for f from 1 to max_formants
            srcF = perm[f]
            if tempFreq[srcF] <> undefined
                Remove formant points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                Add formant point: f, frameTime[i], tempFreq[srcF]
                Remove bandwidth points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                Add bandwidth point: f, frameTime[i], tempBand[srcF]
                formantFreq[i, f] = tempFreq[srcF]
            endif
        endfor
    endfor

# --- SCALING ---
elif manipulation_type = 4
    for i from 1 to numFrames
        for f from 1 to numFormantsInFrame[i]
            hz = formantFreq[i, f]
            bw = formantBand[i, f]
            if hz <> undefined
                newHz = hz * scale_frequency
                newBw = bw * scale_bandwidth
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                    Add formant point: f, frameTime[i], newHz
                    Remove bandwidth points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                    Add bandwidth point: f, frameTime[i], newBw
                    formantFreq[i, f] = newHz
                endif
            endif
        endfor
    endfor

# --- LFO ---
elif manipulation_type = 5
    for i from 1 to numFrames
        lfoVal = sin(2 * pi * lfo_rate * frameTime[i])
        modFactor = 2 ^ ((lfoVal * lfo_depth) / 12)
        
        for f from 1 to numFormantsInFrame[i]
            hz = formantFreq[i, f]
            if hz <> undefined
                newHz = hz * modFactor
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                    Add formant point: f, frameTime[i], newHz
                    formantFreq[i, f] = newHz
                endif
            endif
        endfor
    endfor

# --- CROSSFADE ---
elif manipulation_type = 6
    for i from 1 to numFrames
        pos = (frameTime[i] / duration) * crossfade_cycles
        fade = (sin(pos * 2 * pi) + 1) / 2
        
        for f from 1 to max_formants
            if f <= numFormantsInFrame[1] and f <= numFormantsInFrame[numFrames]
                hzStart = origFormantFreq[1, f]
                hzEnd = origFormantFreq[numFrames, f]
                
                if hzStart <> undefined and hzEnd <> undefined
                    newHz = hzStart * (1 - fade) + hzEnd * fade
                    Remove formant points between: f, frameTime[i] - 0.0001, frameTime[i] + 0.0001
                    Add formant point: f, frameTime[i], newHz
                    formantFreq[i, f] = newHz
                endif
            endif
        endfor
    endfor

# --- FREEZING ---
elif manipulation_type = 7
    currTime = 0
    while currTime < duration
        freezeIdx = round((currTime / duration) * numFrames)
        if freezeIdx < 1
            freezeIdx = 1
        endif
        if freezeIdx > numFrames
            freezeIdx = numFrames
        endif
        
        startTime = currTime
        endTime = min(currTime + freeze_duration, duration)
        
        startFrame = round((startTime / duration) * numFrames)
        endFrame = round((endTime / duration) * numFrames)
        
        if startFrame < 1
            startFrame = 1
        endif
        if endFrame > numFrames
            endFrame = numFrames
        endif
        
        for k from startFrame to endFrame
            for f from 1 to max_formants
                if f <= numFormantsInFrame[freezeIdx]
                    hzFreeze = origFormantFreq[freezeIdx, f]
                    if hzFreeze <> undefined
                        Remove formant points between: f, frameTime[k] - 0.0001, frameTime[k] + 0.0001
                        Add formant point: f, frameTime[k], hzFreeze
                        formantFreq[k, f] = hzFreeze
                    endif
                endif
            endfor
        endfor
        
        currTime = currTime + freeze_interval
    endwhile
endif

# ============================================================
# STEP 4: Resynthesize
# ============================================================
appendInfoLine: "[4/4] Resynthesizing..."

selectObject: sourceExcitation, formantGrid
resynthMono = Filter
Rename: "resynth_" + uniqueID$

selectObject: soundMono
origIntensity = Get intensity (dB)

selectObject: resynthMono
Scale intensity: origIntensity

# ============================================================
# Apply dry/wet mix
# ============================================================
if dry_wet_mix < 1
    selectObject: soundMono
    Rename: "dry_" + uniqueID$
    
    selectObject: resynthMono
    Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dry_'uniqueID$'(x)"
    
    selectObject: "Sound dry_" + uniqueID$
    Rename: "mono_" + uniqueID$
endif

# ============================================================
# Handle stereo
# ============================================================
if numChannels > 1
    selectObject: sound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: sound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    selectObject: leftChannel
    lpcL = To LPC (burg): max_formants * 2, window_length, time_step, preEmphasis
    selectObject: leftChannel, lpcL
    sourceL = Filter (inverse)
    
    selectObject: sourceL, formantGrid
    resynthL = Filter
    
    selectObject: rightChannel
    lpcR = To LPC (burg): max_formants * 2, window_length, time_step, preEmphasis
    selectObject: rightChannel, lpcR
    sourceR = Filter (inverse)
    
    selectObject: sourceR, formantGrid
    resynthR = Filter
    
    if dry_wet_mix < 1
        selectObject: leftChannel
        Rename: "dryL_" + uniqueID$
        selectObject: resynthL
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dryL_'uniqueID$'(x)"
        removeObject: "Sound dryL_" + uniqueID$
        
        selectObject: rightChannel
        Rename: "dryR_" + uniqueID$
        selectObject: resynthR
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dryR_'uniqueID$'(x)"
        removeObject: "Sound dryR_" + uniqueID$
    endif
    
    selectObject: resynthL, resynthR
    Combine to stereo
    finalOutput = selected("Sound")
    
    Scale peak: scale_peak
    Rename: originalName$ + "_" + manipName$
    
    removeObject: leftChannel, rightChannel, lpcL, lpcR, sourceL, sourceR, resynthL, resynthR
else
    selectObject: resynthMono
    Scale peak: scale_peak
    Rename: originalName$ + "_" + manipName$
    finalOutput = selected("Sound")
endif

# ============================================================
# Cleanup
# ============================================================
removeObject: soundMono, lpc, sourceExcitation, formantPath, formantObj, formantGrid, resynthMono

# ============================================================
# Visualization
# ============================================================
procedure drawVisualization
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
    
    maxFreqDisplay = 4000
    for i from 1 to numFrames
        for f from 1 to max_formants
            if origFormantFreq[i, f] <> undefined
                if origFormantFreq[i, f] > maxFreqDisplay * 0.8
                    maxFreqDisplay = origFormantFreq[i, f] * 1.2
                endif
            endif
            if formantFreq[i, f] <> undefined
                if formantFreq[i, f] > maxFreqDisplay * 0.8
                    maxFreqDisplay = formantFreq[i, f] * 1.2
                endif
            endif
        endfor
    endfor
    if maxFreqDisplay > max_formant_hz
        maxFreqDisplay = max_formant_hz
    endif
    
    # ========================================================
    # PANEL 1: Original formants
    # ========================================================
    Select outer viewport: 0, 6, 0, 3
    Select inner viewport: 0.7, 5.8, 0.5, 2.6
    
    Axes: 0, duration, 0, maxFreqDisplay
    
    for f from 1 to max_formants
        if f = 1
            Colour: "{0.8, 0.2, 0.2}"
        elsif f = 2
            Colour: "{0.2, 0.6, 0.2}"
        elsif f = 3
            Colour: "{0.2, 0.2, 0.8}"
        elsif f = 4
            Colour: "{0.7, 0.5, 0.2}"
        else
            Colour: "{0.5, 0.2, 0.7}"
        endif
        
        Line width: 2
        
        for i from 1 to numFrames - 1
            val1 = origFormantFreq[i, f]
            val2 = origFormantFreq[i + 1, f]
            if val1 <> undefined and val2 <> undefined
                Draw line: frameTime[i], val1, frameTime[i + 1], val2
            endif
        endfor
    endfor
    
    Line width: 1
    Black
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "##Original Formants## - " + originalName$
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    # ========================================================
    # PANEL 2: Modified formants
    # ========================================================
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.7, 5.8, 3.5, 5.6
    
    Axes: 0, duration, 0, maxFreqDisplay
    
    for f from 1 to max_formants
        if f = 1
            Colour: "{0.8, 0.2, 0.2}"
        elsif f = 2
            Colour: "{0.2, 0.6, 0.2}"
        elsif f = 3
            Colour: "{0.2, 0.2, 0.8}"
        elsif f = 4
            Colour: "{0.7, 0.5, 0.2}"
        else
            Colour: "{0.5, 0.2, 0.7}"
        endif
        
        Line width: 2
        
        for i from 1 to numFrames - 1
            val1 = formantFreq[i, f]
            val2 = formantFreq[i + 1, f]
            if val1 <> undefined and val2 <> undefined
                Draw line: frameTime[i], val1, frameTime[i + 1], val2
            endif
        endfor
    endfor
    
    Line width: 1
    Black
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "##Modified Formants## (" + manipName$ + ") F1-red F2-green F3-blue"
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
endproc

if draw_visualization
    @drawVisualization
endif

# ============================================================
# Select final output
# ============================================================
selectObject: finalOutput

# ============================================================
# Play if requested
# ============================================================
if play_after_processing
    Play
endif

# ============================================================
# Report
# ============================================================
appendInfoLine: ""
appendInfoLine: "=============================="
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", originalName$, "_", manipName$
appendInfoLine: "Channels: ", numChannels
appendInfoLine: "Frames: ", numFrames
if draw_visualization
    appendInfoLine: "Visualization in Picture window."
endif