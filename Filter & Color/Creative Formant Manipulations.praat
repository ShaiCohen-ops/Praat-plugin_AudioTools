# ============================================================
# Praat AudioTools - Creative_Formant_Manipulations.praat
# Author: Shai Cohen 
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2025) - Anti-Artifact + Fixed Reversal/Scrambling
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formant manipulation using LPC source-filter decomposition.
#   v1.1: Higher LPC order (20), fixed Reversal/Scrambling energy loss
#
# Improvements in v1.1:
#   - LPC order 20 (was 16) for cleaner modeling
#   - Pre-emphasis 35 Hz (was 50) for less noise
#   - Partial reversal (F1↔F3, F2↔F4) instead of full reversal
#   - Constrained scrambling (preserves energy distribution)
#   - Adaptive gain compensation for Reversal/Scrambling
#   - Wider bandwidths for extreme manipulations
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Creative Formant Manipulations v1.1
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
    boolean Apply_artifact_reduction 1
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Presets
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
    # Alien (partial reversal)
    manipulation_type = 2
    dry_wet_mix = 0.8
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
# Optimized parameters for QUALITY (v1.1)
# ============================================================
time_step = 0.003
max_formants = 5
window_length = 0.030
lpc_order = 20
preEmphasis = 35
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
writeInfoLine: "=== Creative Formant Manipulations v1.1 (ANTI-ARTIFACT) ==="
writeInfoLine: "Preset: ", presetName$
writeInfoLine: "Effect: ", manipName$
writeInfoLine: "LPC Order: ", lpc_order, " (enhanced from 10 to 20)"
writeInfoLine: "Pre-emphasis: ", preEmphasis, " Hz (reduced for less noise)"
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
lpc = To LPC (burg): lpc_order, window_length, time_step, preEmphasis

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

# Cache formant data
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

# --- REVERSAL (IMPROVED - Partial swap with compensation) ---
elsif manipulation_type = 2
    appendInfoLine: "  Using partial reversal (F1↔F3, F2↔F4) for better energy..."
    
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
        
        # PARTIAL REVERSAL (less extreme, preserves energy)
        # F1 ↔ F3 (skip extreme ends)
        # F2 ↔ F4
        # F5 stays or modified slightly
        if nf >= 4
            formantFreq_'i'_1 = tempFreq_3
            formantBand_'i'_1 = tempBand_3 * 2.5
            
            formantFreq_'i'_2 = tempFreq_4
            formantBand_'i'_2 = tempBand_4 * 2.5
            
            formantFreq_'i'_3 = tempFreq_1
            formantBand_'i'_3 = tempBand_1 * 2.0
            
            formantFreq_'i'_4 = tempFreq_2
            formantBand_'i'_4 = tempBand_2 * 2.0
            
            # F5 unchanged or slightly modified
            if nf >= 5
                formantFreq_'i'_5 = tempFreq_5
                formantBand_'i'_5 = tempBand_5 * 2.0
            endif
        elsif nf >= 2
            # Fallback for fewer formants
            formantFreq_'i'_1 = tempFreq_2
            formantBand_'i'_1 = tempBand_2 * 2.5
            
            formantFreq_'i'_2 = tempFreq_1
            formantBand_'i'_2 = tempBand_1 * 2.5
        endif
        
        # Apply to grid with WIDER bandwidths
        for f from 1 to nf
            newHz = formantFreq_'i'_'f'
            newBw = formantBand_'i'_'f'
            if newHz <> undefined
                Remove formant points between: f, ft - 0.0001, ft + 0.0001
                Add formant point: f, ft, newHz
                Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
                Add bandwidth point: f, ft, newBw
            endif
        endfor
    endfor

# --- SCRAMBLING (IMPROVED - Constrained randomization) ---
elsif manipulation_type = 3
    appendInfoLine: "  Using constrained scrambling for better energy..."
    
    for i from 1 to numFrames
        nf = numFormantsInFrame_'i'
        ft = frameTime_'i'
        
        # Store originals
        for f from 1 to max_formants
            tempFreq_'f' = undefined
            tempBand_'f' = undefined
        endfor
        
        for f from 1 to nf
            tempFreq_'f' = formantFreq_'i'_'f'
            tempBand_'f' = formantBand_'i'_'f'
        endfor
        
        # CONSTRAINED SCRAMBLING: Keep F1 in lower range, F5 in upper range
        if nf >= 3
            # F1: Pick from F1-F2 (keep low energy present)
            rIdx1 = randomInteger(1, 2)
            formantFreq_'i'_1 = tempFreq_'rIdx1'
            formantBand_'i'_1 = tempBand_'rIdx1' * 2.0
            
            # F2-F4: Randomize from middle formants
            for f from 2 to min(nf - 1, 4)
                rIdx = randomInteger(2, min(nf, 4))
                formantFreq_'i'_'f' = tempFreq_'rIdx'
                formantBand_'i'_'f' = tempBand_'rIdx' * 2.0
            endfor
            
            # F5: Pick from F4-F5 (keep high range)
            if nf >= 5
                rIdx5 = randomInteger(max(4, nf - 1), nf)
                formantFreq_'i'_5 = tempFreq_'rIdx5'
                formantBand_'i'_5 = tempBand_'rIdx5' * 2.0
            endif
        else
            # Fallback for fewer formants
            for f from 1 to nf
                rIdx = randomInteger(1, nf)
                formantFreq_'i'_'f' = tempFreq_'rIdx'
                formantBand_'i'_'f' = tempBand_'rIdx' * 2.5
            endfor
        endif
        
        # Apply to grid
        for f from 1 to nf
            newHz = formantFreq_'i'_'f'
            newBw = formantBand_'i'_'f'
            if newHz <> undefined
                Remove formant points between: f, ft - 0.0001, ft + 0.0001
                Add formant point: f, ft, newHz
                Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
                Add bandwidth point: f, ft, newBw
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
                    formantBand_'i'_'f' = newBw
                endif
            endif
        endfor
    endfor

# --- LFO MODULATION ---
elsif manipulation_type = 5
    for i from 1 to numFrames
        nf = numFormantsInFrame_'i'
        ft = frameTime_'i'
        modFactor = 1 + (lfo_depth / 100) * sin(2 * pi * lfo_rate * ft)
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
    numCycles = crossfade_cycles
    cycleDur = duration / numCycles
    
    for cycle from 1 to numCycles
        tStart = (cycle - 1) * cycleDur
        tEnd = cycle * cycleDur
        
        for i from 1 to numFrames
            ft = frameTime_'i'
            if ft >= tStart and ft <= tEnd
                progress = (ft - tStart) / cycleDur
                
                nf = numFormantsInFrame_'i'
                for f from 1 to nf
                    origHz = origFormantFreq_'i'_'f'
                    
                    if f < max_formants
                        targetF = f + 1
                        if targetF <= nf
                            targetHz = origFormantFreq_'i'_'targetF'
                        else
                            targetHz = origHz
                        endif
                    else
                        targetHz = origHz
                    endif
                    
                    if origHz <> undefined and targetHz <> undefined
                        newHz = origHz + progress * (targetHz - origHz)
                        if newHz > 0 and newHz < max_formant_hz
                            Remove formant points between: f, ft - 0.0001, ft + 0.0001
                            Add formant point: f, ft, newHz
                            formantFreq_'i'_'f' = newHz
                        endif
                    endif
                endfor
            endif
        endfor
    endfor

# --- FREEZING ---
elsif manipulation_type = 7
    currTime = 0
    
    while currTime < duration
        freezeTime = currTime + freeze_duration / 2
        
        freezeIdx = 0
        minDist = 99999
        for i from 1 to numFrames
            ft = frameTime_'i'
            dist = abs(ft - freezeTime)
            if dist < minDist
                minDist = dist
                freezeIdx = i
            endif
        endfor
        
        if freezeIdx > 0
            nfFreeze = numFormantsInFrame_'freezeIdx'
            
            for k from 1 to numFrames
                ft = frameTime_'k'
                if ft >= currTime and ft < currTime + freeze_duration
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
                endif
            endfor
        endif
        
        currTime = currTime + freeze_interval
    endwhile
endif

# ============================================================
# STEP 4: Resynthesize
# ============================================================
appendInfoLine: "[4/4] Resynthesizing with quality enhancement..."

selectObject: sourceExcitation
plusObject: formantGrid
resynthMono = Filter

# ============================================================
# QUALITY ENHANCEMENT: Intensity matching
# ============================================================
selectObject: soundMono
To Intensity: 75, 0.001, "yes"
intensityObj = selected("Intensity")
meanIntensity = Get mean: 0, 0, "energy"

selectObject: resynthMono
To Intensity: 75, 0.001, "yes"
resynthIntensityObj = selected("Intensity")
resynthMeanIntensity = Get mean: 0, 0, "energy"

selectObject: resynthMono
intensityDiff = meanIntensity - resynthMeanIntensity
Formula: "self * 10^(intensityDiff/20)"
Scale peak: 0.99

removeObject: intensityObj, resynthIntensityObj

# ============================================================
# ADAPTIVE GAIN for Reversal/Scrambling
# ============================================================
if manipulation_type = 2 or manipulation_type = 3
    selectObject: resynthMono
    Formula: "self * 3.5"
    Scale peak: 0.95
    appendInfoLine: "  Applied energy compensation for ", manipName$
endif

# ============================================================
# QUALITY ENHANCEMENT: Artifact reduction
# ============================================================
if apply_artifact_reduction
    appendInfoLine: "  Applying artifact reduction..."
    
    selectObject: resynthMono
    
    # Remove high-frequency artifacts
    Filter (stop Hann band): max_formant_hz * 0.95, 10000, 100
    artifact_filtered = selected("Sound")
    
    # Gentle de-clicking
    Formula: "if abs(self - self[col-1]) > 0.5 then (self[col-1] + self[col+1])/2 else self fi"
    
    removeObject: resynthMono
    resynthMono = artifact_filtered
endif

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
    appendInfoLine: "  Processing stereo channels..."
    
    selectObject: sound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: sound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left
    selectObject: leftChannel
    lpcL = To LPC (burg): lpc_order, window_length, time_step, preEmphasis
    selectObject: leftChannel
    plusObject: lpcL
    sourceL = Filter (inverse)
    
    selectObject: sourceL
    plusObject: formantGrid
    resynthL = Filter
    
    # Process right
    selectObject: rightChannel
    lpcR = To LPC (burg): lpc_order, window_length, time_step, preEmphasis
    selectObject: rightChannel
    plusObject: lpcR
    sourceR = Filter (inverse)
    
    selectObject: sourceR
    plusObject: formantGrid
    resynthR = Filter
    
    # Intensity matching for stereo
    selectObject: leftChannel
    To Intensity: 75, 0.001, "yes"
    intensityL = selected("Intensity")
    meanIntL = Get mean: 0, 0, "energy"
    
    selectObject: rightChannel
    To Intensity: 75, 0.001, "yes"
    intensityR = selected("Intensity")
    meanIntR = Get mean: 0, 0, "energy"
    
    selectObject: resynthL
    To Intensity: 75, 0.001, "yes"
    resynthIntL = selected("Intensity")
    resynthMeanIntL = Get mean: 0, 0, "energy"
    
    selectObject: resynthR
    To Intensity: 75, 0.001, "yes"
    resynthIntR = selected("Intensity")
    resynthMeanIntR = Get mean: 0, 0, "energy"
    
    selectObject: resynthL
    diffL = meanIntL - resynthMeanIntL
    Formula: "self * 10^(diffL/20)"
    
    selectObject: resynthR
    diffR = meanIntR - resynthMeanIntR
    Formula: "self * 10^(diffR/20)"
    
    removeObject: intensityL, intensityR, resynthIntL, resynthIntR
    
    # ADAPTIVE GAIN for stereo Reversal/Scrambling
    if manipulation_type = 2 or manipulation_type = 3
        selectObject: resynthL
        Formula: "self * 3.5"
        
        selectObject: resynthR
        Formula: "self * 3.5"
        
        appendInfoLine: "  Applied energy compensation for stereo"
    endif
    
    # Artifact reduction for stereo
    if apply_artifact_reduction
        selectObject: resynthL
        Filter (stop Hann band): max_formant_hz * 0.95, 10000, 100
        resynthL_filtered = selected("Sound")
        Formula: "if abs(self - self[col-1]) > 0.5 then (self[col-1] + self[col+1])/2 else self fi"
        removeObject: resynthL
        resynthL = resynthL_filtered
        
        selectObject: resynthR
        Filter (stop Hann band): max_formant_hz * 0.95, 10000, 100
        resynthR_filtered = selected("Sound")
        Formula: "if abs(self - self[col-1]) > 0.5 then (self[col-1] + self[col+1])/2 else self fi"
        removeObject: resynthR
        resynthR = resynthR_filtered
    endif
    
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

# ============================================================
# VISUALIZATION WITH FORMANT TRAJECTORIES
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "Creative Formant Manipulations v1.1"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.2, "half", presetName$ + " | " + manipName$ + " | Anti-Artifact Enhanced"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.6, 3.7, 0.7, 1.95
    
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Waveform"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.4, 7.7, 0.7, 1.95
    
    selectObject: finalOutput
    Colour: "{0.3, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Processed"
    Text bottom: "yes", "Time (s)"
    
    # FORMANT TRAJECTORIES
    Select outer viewport: 0, 8, 2.1, 4.0
    Select inner viewport: 0.6, 7.7, 2.2, 3.95
    
    Axes: 0, duration, 0, 3500
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 3500
    
    # Draw original formants (grey)
    formant_colors$# = {"{0.7, 0.7, 0.7}", "{0.7, 0.7, 0.7}", "{0.7, 0.7, 0.7}"}
    
    for f from 1 to 3
        Colour: formant_colors$#[f]
        Dotted line
        for i from 1 to numFrames - 1
            i_next = i + 1
            t1 = frameTime_'i'
            t2 = frameTime_'i_next'
            freq1 = origFormantFreq_'i'_'f'
            freq2 = origFormantFreq_'i_next'_'f'
            if freq1 <> undefined and freq2 <> undefined
                Draw line: t1, freq1, t2, freq2
            endif
        endfor
        Solid line
    endfor
    
    # Draw modified formants (colored)
    formant_colors$#[1] = "{0.3, 0.6, 0.9}"
    formant_colors$#[2] = "{0.9, 0.5, 0.3}"
    formant_colors$#[3] = "{0.3, 0.8, 0.5}"
    
    for f from 1 to 3
        Colour: formant_colors$#[f]
        Line width: 2
        for i from 1 to numFrames - 1
            i_next = i + 1
            t1 = frameTime_'i'
            t2 = frameTime_'i_next'
            freq1 = formantFreq_'i'_'f'
            freq2 = formantFreq_'i_next'_'f'
            if freq1 <> undefined and freq2 <> undefined
                Draw line: t1, freq1, t2, freq2
            endif
        endfor
        Line width: 1
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Formant Trajectories (grey=original, colored=modified)"
    Text bottom: "yes", "Time (s)"
    
    Font size: 5
    Colour: "{0.3, 0.6, 0.9}"
    Text: duration * 0.95, "right", 500, "half", "F1"
    Colour: "{0.9, 0.5, 0.3}"
    Text: duration * 0.95, "right", 1500, "half", "F2"
    Colour: "{0.3, 0.8, 0.5}"
    Text: duration * 0.95, "right", 2500, "half", "F3"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 4.1, 6.0
    Select inner viewport: 0.6, 3.7, 4.2, 5.95
    
    selectObject: sound
    if numChannels > 1
        Extract one channel: 1
        spec_source = selected("Sound")
    else
        Copy: "spec_source"
        spec_source = selected("Sound")
    endif
    
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    orig_spec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original Spectrogram"
    
    removeObject: orig_spec, spec_source
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 4.1, 6.0
    Select inner viewport: 4.4, 7.7, 4.2, 5.95
    
    selectObject: finalOutput
    if numChannels > 1
        Extract one channel: 1
        spec_proc = selected("Sound")
    else
        Copy: "spec_proc"
        spec_proc = selected("Sound")
    endif
    
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    proc_spec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Processed Spectrogram"
    
    removeObject: proc_spec, spec_proc
    
    # Info panel
    Select outer viewport: 0, 8, 6.1, 7.0
    Select inner viewport: 0.6, 7.7, 6.2, 6.95
    
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.9, "half", "Processing Details"
    
    Font size: 6
    Colour: "{0.5, 0.5, 0.5}"
    
    Text: 0.05, "left", 0.65, "half", "Effect: " + manipName$
    Text: 0.05, "left", 0.5, "half", "Frames: " + string$(numFrames)
    Text: 0.05, "left", 0.35, "half", "Dry/Wet: " + fixed$(dry_wet_mix, 2)
    Text: 0.05, "left", 0.2, "half", "Duration: " + fixed$(duration, 2) + " s"
    
    Text: 0.55, "left", 0.65, "half", "LPC Order: " + string$(lpc_order)
    if apply_artifact_reduction
        Text: 0.55, "left", 0.5, "half", "✓ Artifact Reduction"
    endif
    Text: 0.55, "left", 0.35, "half", "Pre-emphasis: " + string$(preEmphasis) + " Hz"
    if manipulation_type = 2 or manipulation_type = 3
        Text: 0.55, "left", 0.2, "half", "✓ Energy Compensation"
    endif
    
    Font size: 10
endif

# ============================================================
# Final output
# ============================================================
selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Quality enhancements:"
appendInfoLine: "  • LPC order: ", lpc_order
appendInfoLine: "  • Pre-emphasis: ", preEmphasis, " Hz"
if apply_artifact_reduction
    appendInfoLine: "  • Artifact reduction enabled"
endif
if manipulation_type = 2
    appendInfoLine: "  • Partial reversal (F1↔F3, F2↔F4) + gain boost"
elsif manipulation_type = 3
    appendInfoLine: "  • Constrained scrambling + gain boost"
endif

if play_after_processing
    appendInfoLine: "Playing result..."
    Play
endif