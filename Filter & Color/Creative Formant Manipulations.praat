# ============================================================
# Praat AudioTools - Creative_Formant_Manipulations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formant manipulation using LPC source-filter decomposition.
#
# Changelog v0.3:
#   - Fixed stray "Convert to stereo" command
#   - Fixed preset comparison (number not string)
#   - Fixed all array syntax for Praat
#   - Fixed Formula variable interpolation
#   - Added preset name to output
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Creative Formant Manipulations v0.3
    optionmenu Preset: 1
        option Manual
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
    positive Max_formant_hz 5500
    real Rotation_semitones 3.0
    real Scale_frequency 0.8
    real Scale_bandwidth 1.2
    positive Lfo_rate 2.0
    positive Lfo_depth 6.0
    positive Freeze_interval 0.3
    positive Freeze_duration 0.15
    real Dry_wet_mix 1.0
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Presets (fixed: use number not string)
# ============================================================
if preset = 2
    # Robot Voice
    manipulation_type = 7
    freeze_interval = 0.08
    freeze_duration = 0.08
    presetName$ = "Robot"
elsif preset = 3
    # Chipmunk
    manipulation_type = 4
    scale_frequency = 1.4
    scale_bandwidth = 0.8
    presetName$ = "Chipmunk"
elsif preset = 4
    # Giant
    manipulation_type = 4
    scale_frequency = 0.7
    scale_bandwidth = 1.3
    presetName$ = "Giant"
elsif preset = 5
    # Alien
    manipulation_type = 2
    presetName$ = "Alien"
elsif preset = 6
    # Wobble
    manipulation_type = 5
    lfo_rate = 4.0
    lfo_depth = 8.0
    presetName$ = "Wobble"
elsif preset = 7
    # Vowel Morph
    manipulation_type = 6
    presetName$ = "VowelMorph"
else
    presetName$ = "Manual"
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
# Setup
# ============================================================
selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# Get manipulation type name
if manipulation_type = 1
    manipName$ = "Rotation"
elsif manipulation_type = 2
    manipName$ = "Reversal"
elsif manipulation_type = 3
    manipName$ = "Scrambling"
elsif manipulation_type = 4
    manipName$ = "Scaling"
elsif manipulation_type = 5
    manipName$ = "LFO"
elsif manipulation_type = 6
    manipName$ = "Crossfade"
else
    manipName$ = "Freeze"
endif

clearinfo
writeInfoLine: "=== Creative Formant Manipulations v0.3 ==="
writeInfoLine: "Preset: ", presetName$
writeInfoLine: "Effect: ", manipName$
appendInfoLine: ""

# ============================================================
# Convert to mono for analysis
# ============================================================
if numChannels > 1
    selectObject: sound
    soundMono = Convert to mono
else
    selectObject: sound
    soundMono = Copy: "mono_work"
endif

# ============================================================
# STEP 1: Extract source excitation
# ============================================================
appendInfoLine: "[1/4] Extracting source excitation..."

selectObject: soundMono
lpc = To LPC (burg): max_formants * 2, window_length, time_step, preEmphasis

selectObject: soundMono
plusObject: lpc
sourceExcitation = Filter (inverse)

# ============================================================
# STEP 2: Analyze formants
# ============================================================
appendInfoLine: "[2/4] Analyzing formants..."

selectObject: soundMono
formantPath = To FormantPath (burg): time_step, max_formants, max_formant_hz, window_length, preEmphasis, 0.05, 4
formantObj = Extract Formant

selectObject: formantObj
numFrames = Get number of frames

appendInfoLine: "  Frames: ", numFrames

# Cache formant data (using Praat array syntax)
for i from 1 to numFrames
    selectObject: formantObj
    frameTime_'i' = Get time from frame number: i
    numFormantsInFrame_'i' = Get number of formants: i
    
    for f from 1 to max_formants
        formantFreq_'i'_'f' = undefined
        formantBand_'i'_'f' = undefined
        origFormantFreq_'i'_'f' = undefined
    endfor
    
    nf = numFormantsInFrame_'i'
    for f from 1 to nf
        ft = frameTime_'i'
        formantFreq_'i'_'f' = Get value at time: f, ft, "hertz", "Linear"
        formantBand_'i'_'f' = Get bandwidth at time: f, ft, "hertz", "Linear"
        origFormantFreq_'i'_'f' = formantFreq_'i'_'f'
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
        nf = numFormantsInFrame_'i'
        ft = frameTime_'i'
        for f from 1 to nf
            hz = formantFreq_'i'_'f'
            if hz <> undefined
                newHz = hz * factor
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    formantFreq_'i'_'f' = newHz
                endif
            endif
        endfor
    endfor

# --- REVERSAL ---
elsif manipulation_type = 2
    for i from 1 to numFrames
        ft = frameTime_'i'
        
        # Store temp values
        for f from 1 to max_formants
            nf = numFormantsInFrame_'i'
            if f <= nf
                tempFreq_'f' = formantFreq_'i'_'f'
                tempBand_'f' = formantBand_'i'_'f'
            else
                tempFreq_'f' = undefined
                tempBand_'f' = undefined
            endif
        endfor
        
        # Reverse assignment
        for f from 1 to max_formants
            srcF = max_formants - f + 1
            srcFreq = tempFreq_'srcF'
            srcBand = tempBand_'srcF'
            if srcFreq <> undefined
                Remove formant points between: f, ft - 0.0001, ft + 0.0001
                Add formant point: f, ft, srcFreq
                Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
                Add bandwidth point: f, ft, srcBand
                formantFreq_'i'_'f' = srcFreq
            endif
        endfor
    endfor

# --- SCRAMBLING ---
elsif manipulation_type = 3
    for i from 1 to numFrames
        ft = frameTime_'i'
        nf = numFormantsInFrame_'i'
        
        # Store temp values
        for f from 1 to max_formants
            if f <= nf
                tempFreq_'f' = formantFreq_'i'_'f'
                tempBand_'f' = formantBand_'i'_'f'
            else
                tempFreq_'f' = undefined
                tempBand_'f' = undefined
            endif
        endfor
        
        # Create permutation
        for k from 1 to max_formants
            perm_'k' = k
        endfor
        
        for k from max_formants to 2
            r = randomInteger(1, k)
            swapK = perm_'k'
            swapR = perm_'r'
            perm_'k' = swapR
            perm_'r' = swapK
        endfor
        
        # Apply permutation
        for f from 1 to max_formants
            srcF = perm_'f'
            srcFreq = tempFreq_'srcF'
            srcBand = tempBand_'srcF'
            if srcFreq <> undefined
                Remove formant points between: f, ft - 0.0001, ft + 0.0001
                Add formant point: f, ft, srcFreq
                Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
                Add bandwidth point: f, ft, srcBand
                formantFreq_'i'_'f' = srcFreq
            endif
        endfor
    endfor

# --- SCALING ---
elsif manipulation_type = 4
    for i from 1 to numFrames
        nf = numFormantsInFrame_'i'
        ft = frameTime_'i'
        for f from 1 to nf
            hz = formantFreq_'i'_'f'
            bw = formantBand_'i'_'f'
            if hz <> undefined
                newHz = hz * scale_frequency
                newBw = bw * scale_bandwidth
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
                    Add bandwidth point: f, ft, newBw
                    formantFreq_'i'_'f' = newHz
                endif
            endif
        endfor
    endfor

# --- LFO ---
elsif manipulation_type = 5
    for i from 1 to numFrames
        ft = frameTime_'i'
        lfoVal = sin(2 * pi * lfo_rate * ft)
        modFactor = 2 ^ ((lfoVal * lfo_depth) / 12)
        
        nf = numFormantsInFrame_'i'
        for f from 1 to nf
            hz = formantFreq_'i'_'f'
            if hz <> undefined
                newHz = hz * modFactor
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    formantFreq_'i'_'f' = newHz
                endif
            endif
        endfor
    endfor

# --- CROSSFADE ---
elsif manipulation_type = 6
    for i from 1 to numFrames
        ft = frameTime_'i'
        pos = (ft / duration) * crossfade_cycles
        fade = (sin(pos * 2 * pi) + 1) / 2
        
        nfFirst = numFormantsInFrame_1
        nfLast = numFormantsInFrame_'numFrames'
        
        for f from 1 to max_formants
            if f <= nfFirst and f <= nfLast
                hzStart = origFormantFreq_1_'f'
                hzEnd = origFormantFreq_'numFrames'_'f'
                
                if hzStart <> undefined and hzEnd <> undefined
                    newHz = hzStart * (1 - fade) + hzEnd * fade
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    formantFreq_'i'_'f' = newHz
                endif
            endif
        endfor
    endfor

# --- FREEZING ---
elsif manipulation_type = 7
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
        
        nfFreeze = numFormantsInFrame_'freezeIdx'
        
        for k from startFrame to endFrame
            ft = frameTime_'k'
            for f from 1 to max_formants
                if f <= nfFreeze
                    hzFreeze = origFormantFreq_'freezeIdx'_'f'
                    if hzFreeze <> undefined
                        Remove formant points between: f, ft - 0.0001, ft + 0.0001
                        Add formant point: f, ft, hzFreeze
                        formantFreq_'k'_'f' = hzFreeze
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

selectObject: sourceExcitation
plusObject: formantGrid
resynthMono = Filter

selectObject: soundMono
origIntensity = Get intensity (dB)

selectObject: resynthMono
Scale intensity: origIntensity

# ============================================================
# Apply dry/wet mix
# ============================================================
if dry_wet_mix < 1
    dryMix$ = string$(1 - dry_wet_mix)
    wetMix$ = string$(dry_wet_mix)
    monoId$ = string$(soundMono)
    
    selectObject: resynthMono
    Formula: wetMix$ + " * self + " + dryMix$ + " * Object_" + monoId$ + "(x)"
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
    
    # Process left
    selectObject: leftChannel
    lpcL = To LPC (burg): max_formants * 2, window_length, time_step, preEmphasis
    selectObject: leftChannel
    plusObject: lpcL
    sourceL = Filter (inverse)
    
    selectObject: sourceL
    plusObject: formantGrid
    resynthL = Filter
    
    # Process right
    selectObject: rightChannel
    lpcR = To LPC (burg): max_formants * 2, window_length, time_step, preEmphasis
    selectObject: rightChannel
    plusObject: lpcR
    sourceR = Filter (inverse)
    
    selectObject: sourceR
    plusObject: formantGrid
    resynthR = Filter
    
    # Apply dry/wet if needed
    if dry_wet_mix < 1
        leftId$ = string$(leftChannel)
        rightId$ = string$(rightChannel)
        
        selectObject: resynthL
        Formula: wetMix$ + " * self + " + dryMix$ + " * Object_" + leftId$ + "(x)"
        
        selectObject: resynthR
        Formula: wetMix$ + " * self + " + dryMix$ + " * Object_" + rightId$ + "(x)"
    endif
    
    selectObject: resynthL
    plusObject: resynthR
    Combine to stereo
    finalOutput = selected("Sound")
    
    Scale peak: scale_peak
    Rename: originalName$ + "_" + manipName$ + "_" + presetName$
    
    removeObject: leftChannel, rightChannel, lpcL, lpcR, sourceL, sourceR, resynthL, resynthR
else
    selectObject: resynthMono
    Scale peak: scale_peak
    Rename: originalName$ + "_" + manipName$ + "_" + presetName$
    finalOutput = selected("Sound")
endif

# ============================================================
# Cleanup
# ============================================================
removeObject: soundMono, lpc, sourceExcitation, formantPath, formantObj, formantGrid
if numChannels = 1
    # resynthMono was renamed to finalOutput, don't remove
else
    removeObject: resynthMono
endif

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
    
    maxFreqDisplay = 4000
    for i from 1 to numFrames
        for f from 1 to max_formants
            origF = origFormantFreq_'i'_'f'
            modF = formantFreq_'i'_'f'
            if origF <> undefined
                if origF > maxFreqDisplay * 0.8
                    maxFreqDisplay = origF * 1.2
                endif
            endif
            if modF <> undefined
                if modF > maxFreqDisplay * 0.8
                    maxFreqDisplay = modF * 1.2
                endif
            endif
        endfor
    endfor
    if maxFreqDisplay > max_formant_hz
        maxFreqDisplay = max_formant_hz
    endif
    
    # PANEL 1: Original formants
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
            i1 = i + 1
            val1 = origFormantFreq_'i'_'f'
            val2 = origFormantFreq_'i1'_'f'
            ft1 = frameTime_'i'
            ft2 = frameTime_'i1'
            if val1 <> undefined and val2 <> undefined
                Draw line: ft1, val1, ft2, val2
            endif
        endfor
    endfor
    
    Line width: 1
    Colour: "Black"
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Original Formants - " + originalName$
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    # PANEL 2: Modified formants
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
            i1 = i + 1
            val1 = formantFreq_'i'_'f'
            val2 = formantFreq_'i1'_'f'
            ft1 = frameTime_'i'
            ft2 = frameTime_'i1'
            if val1 <> undefined and val2 <> undefined
                Draw line: ft1, val1, ft2, val2
            endif
        endfor
    endfor
    
    Line width: 1
    Colour: "Black"
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Modified Formants (" + manipName$ + ") [" + presetName$ + "]"
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
endif

# ============================================================
# Output
# ============================================================
selectObject: sound
plusObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Frames: ", numFrames

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput