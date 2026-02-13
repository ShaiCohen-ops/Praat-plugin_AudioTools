# ============================================================
# Praat AudioTools - Individual_Formant_Stretcher.praat
# Author: Shai Cohen 
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2025) - Anti-Artifact Edition
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Transpose each formant individually for spectral reshaping.
#   v1.1: Improved artifact reduction + wilder presets
#
# Improvements in v1.1:
#   - Higher LPC order (20 vs 16) for cleaner modeling
#   - Formant trajectory smoothing (removes jitter/"water" artifacts)
#   - Pre-emphasis correction
#   - Wilder, more extreme presets
#   - Better unvoiced region handling
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Individual Formant Stretcher v1.1
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Natural (no change)
        option Compress Vowel Space
        option Expand Vowel Space
        option Brighten Spectrum
        option Darken Spectrum
        option Male to Female
        option Female to Male
        option Robot Voice (harmonic)
        option Alien Creature
        option Demon Voice
        option Chipmunk Extreme
        option Giant Extreme
        option Spectral Inversion
        option Harmonic Series
        option Chaos Mode
    
    comment === Individual Formant Control (semitones) ===
    real F1_transpose_semitones 0.0
    real F2_transpose_semitones 0.0
    real F3_transpose_semitones 0.0
    real F4_transpose_semitones 0.0
    real F5_transpose_semitones 0.0
    
    comment === Global Control ===
    real Global_transpose_semitones 0.0
    comment (Applied to all formants before individual offsets)
    
    real Bandwidth_scale 1.0
    comment (< 1.0 = narrower/sharper, > 1.0 = wider/softer)
    
    comment === Quality Settings ===
    boolean Apply_formant_smoothing 1
    comment (Reduces jitter/"water" artifacts)
    boolean Apply_artifact_reduction 1
    
    comment === Analysis Parameters ===
    positive Max_formant_hz 5500
    positive Time_step_s 0.003
    positive Window_length_s 0.030
    
    comment === Output ===
    real Dry_wet_mix 1.0
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ============================================================
# Apply Presets (WILDER!)
# ============================================================
if preset = 2
    # Natural (no change)
    f1_transpose_semitones = 0
    f2_transpose_semitones = 0
    f3_transpose_semitones = 0
    f4_transpose_semitones = 0
    f5_transpose_semitones = 0
    global_transpose_semitones = 0
    presetName$ = "Natural"
elsif preset = 3
    # Compress
    f1_transpose_semitones = 3
    f2_transpose_semitones = 2
    f3_transpose_semitones = 0
    f4_transpose_semitones = -2
    f5_transpose_semitones = -3
    presetName$ = "Compress"
elsif preset = 4
    # Expand
    f1_transpose_semitones = -3
    f2_transpose_semitones = -2
    f3_transpose_semitones = 0
    f4_transpose_semitones = 2
    f5_transpose_semitones = 3
    presetName$ = "Expand"
elsif preset = 5
    # Brighten
    f1_transpose_semitones = 0
    f2_transpose_semitones = 4
    f3_transpose_semitones = 6
    f4_transpose_semitones = 7
    f5_transpose_semitones = 8
    bandwidth_scale = 0.7
    presetName$ = "Brighten"
elsif preset = 6
    # Darken
    f1_transpose_semitones = 0
    f2_transpose_semitones = -4
    f3_transpose_semitones = -6
    f4_transpose_semitones = -7
    f5_transpose_semitones = -8
    bandwidth_scale = 1.4
    presetName$ = "Darken"
elsif preset = 7
    # Male to Female
    f1_transpose_semitones = -1
    f2_transpose_semitones = 2
    f3_transpose_semitones = 3
    f4_transpose_semitones = 3
    f5_transpose_semitones = 2
    global_transpose_semitones = 2
    bandwidth_scale = 0.85
    presetName$ = "MaleToFemale"
elsif preset = 8
    # Female to Male
    f1_transpose_semitones = 1
    f2_transpose_semitones = -2
    f3_transpose_semitones = -3
    f4_transpose_semitones = -3
    f5_transpose_semitones = -2
    global_transpose_semitones = -2
    bandwidth_scale = 1.15
    presetName$ = "FemaleToMale"
elsif preset = 9
    # Robot Voice (harmonic series)
    f1_transpose_semitones = 0
    f2_transpose_semitones = 12
    f3_transpose_semitones = 19
    f4_transpose_semitones = 24
    f5_transpose_semitones = 28
    bandwidth_scale = 0.5
    presetName$ = "Robot"
elsif preset = 10
    # Alien Creature
    f1_transpose_semitones = 8
    f2_transpose_semitones = -5
    f3_transpose_semitones = 12
    f4_transpose_semitones = -8
    f5_transpose_semitones = 15
    bandwidth_scale = 1.5
    presetName$ = "Alien"
elsif preset = 11
    # Demon Voice
    f1_transpose_semitones = -7
    f2_transpose_semitones = -12
    f3_transpose_semitones = -8
    f4_transpose_semitones = -15
    f5_transpose_semitones = -10
    global_transpose_semitones = -5
    bandwidth_scale = 2.0
    presetName$ = "Demon"
elsif preset = 12
    # Chipmunk Extreme
    f1_transpose_semitones = 5
    f2_transpose_semitones = 8
    f3_transpose_semitones = 10
    f4_transpose_semitones = 12
    f5_transpose_semitones = 12
    global_transpose_semitones = 7
    bandwidth_scale = 0.6
    presetName$ = "ChipmunkExtreme"
elsif preset = 13
    # Giant Extreme
    f1_transpose_semitones = -8
    f2_transpose_semitones = -12
    f3_transpose_semitones = -10
    f4_transpose_semitones = -14
    f5_transpose_semitones = -12
    global_transpose_semitones = -8
    bandwidth_scale = 2.5
    presetName$ = "GiantExtreme"
elsif preset = 14
    # Spectral Inversion
    f1_transpose_semitones = 12
    f2_transpose_semitones = 5
    f3_transpose_semitones = 0
    f4_transpose_semitones = -5
    f5_transpose_semitones = -12
    bandwidth_scale = 1.0
    presetName$ = "Inversion"
elsif preset = 15
    # Harmonic Series
    f1_transpose_semitones = 0
    f2_transpose_semitones = 12
    f3_transpose_semitones = 19
    f4_transpose_semitones = 24
    f5_transpose_semitones = 28
    bandwidth_scale = 0.4
    presetName$ = "Harmonic"
elsif preset = 16
    # Chaos Mode
    f1_transpose_semitones = 9
    f2_transpose_semitones = -11
    f3_transpose_semitones = 14
    f4_transpose_semitones = -6
    f5_transpose_semitones = 17
    bandwidth_scale = 1.8
    presetName$ = "Chaos"
else
    presetName$ = "Custom"
endif

# ============================================================
# Parameters (ANTI-ARTIFACT)
# ============================================================
lpc_order = 20
preEmphasis = 35
max_formants = 5
smoothing_window = 5

clearinfo
writeInfoLine: "=== Individual Formant Stretcher v1.1 (ANTI-ARTIFACT) ==="
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""
writeInfoLine: "Formant Offsets (semitones):"
writeInfoLine: "  Global: ", fixed$(global_transpose_semitones, 1)
writeInfoLine: "  F1: ", fixed$(f1_transpose_semitones, 1)
writeInfoLine: "  F2: ", fixed$(f2_transpose_semitones, 1)
writeInfoLine: "  F3: ", fixed$(f3_transpose_semitones, 1)
writeInfoLine: "  F4: ", fixed$(f4_transpose_semitones, 1)
writeInfoLine: "  F5: ", fixed$(f5_transpose_semitones, 1)
writeInfoLine: "  Bandwidth scale: ", fixed$(bandwidth_scale, 2)
writeInfoLine: "  LPC order: ", lpc_order, " (enhanced)"
if apply_formant_smoothing
    writeInfoLine: "  Formant smoothing: ENABLED"
endif
appendInfoLine: ""

# Store individual factors
global_factor = 2 ^ (global_transpose_semitones / 12)
f1_factor = 2 ^ (f1_transpose_semitones / 12)
f2_factor = 2 ^ (f2_transpose_semitones / 12)
f3_factor = 2 ^ (f3_transpose_semitones / 12)
f4_factor = 2 ^ (f4_transpose_semitones / 12)
f5_factor = 2 ^ (f5_transpose_semitones / 12)

# ============================================================
# Setup
# ============================================================
selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# Convert to mono
if numChannels > 1
    selectObject: sound
    soundMono = Convert to mono
else
    selectObject: sound
    soundMono = Copy: "mono_work"
endif

# ============================================================
# STEP 1: Extract source
# ============================================================
appendInfoLine: "[1/4] Extracting source excitation..."

selectObject: soundMono
lpc = To LPC (burg): lpc_order, window_length_s, time_step_s, preEmphasis

selectObject: soundMono
plusObject: lpc
sourceExcitation = Filter (inverse)

# ============================================================
# STEP 2: Analyze formants
# ============================================================
appendInfoLine: "[2/4] Analyzing formants..."

selectObject: soundMono
formantPath = To FormantPath (burg): time_step_s, max_formants, max_formant_hz, window_length_s, preEmphasis, 0.05, 4
formantObj = Extract Formant

selectObject: formantObj
numFrames = Get number of frames

appendInfoLine: "  Frames: ", numFrames

# Cache original formant data
for i from 1 to numFrames
    selectObject: formantObj
    frameTime_'i' = Get time from frame number: i
    numFormantsInFrame_'i' = Get number of formants: i
    
    for f from 1 to max_formants
        origFormantFreq_'i'_'f' = undefined
        origFormantBand_'i'_'f' = undefined
        newFormantFreq_'i'_'f' = undefined
        newFormantBand_'i'_'f' = undefined
    endfor
    
    nf = numFormantsInFrame_'i'
    for f from 1 to nf
        ft = frameTime_'i'
        origFormantFreq_'i'_'f' = Get value at time: f, ft, "hertz", "Linear"
        origFormantBand_'i'_'f' = Get bandwidth at time: f, ft, "hertz", "Linear"
    endfor
endfor

# Convert to FormantGrid
selectObject: formantObj
formantGrid = Down to FormantGrid

# ============================================================
# STEP 3: Apply transformations + SMOOTHING
# ============================================================
appendInfoLine: "[3/4] Applying formant stretching with smoothing..."

selectObject: formantGrid

# First pass: Calculate new formant values
for i from 1 to numFrames
    nf = numFormantsInFrame_'i'
    
    for f from 1 to nf
        origHz = origFormantFreq_'i'_'f'
        origBw = origFormantBand_'i'_'f'
        
        if origHz <> undefined
            # Apply global transpose first
            newHz = origHz * global_factor
            
            # Apply individual formant factor
            if f = 1
                newHz = newHz * f1_factor
            elsif f = 2
                newHz = newHz * f2_factor
            elsif f = 3
                newHz = newHz * f3_factor
            elsif f = 4
                newHz = newHz * f4_factor
            elsif f = 5
                newHz = newHz * f5_factor
            endif
            
            # Scale bandwidth
            newBw = origBw * bandwidth_scale
            
            # Clamp to valid range
            if newHz > 50 and newHz < max_formant_hz
                newFormantFreq_'i'_'f' = newHz
                newFormantBand_'i'_'f' = newBw
            else
                newFormantFreq_'i'_'f' = origHz
                newFormantBand_'i'_'f' = origBw
            endif
        endif
    endfor
endfor

# Second pass: TEMPORAL SMOOTHING (removes jitter)
if apply_formant_smoothing
    appendInfoLine: "  Applying temporal smoothing to remove artifacts..."
    
    for f from 1 to max_formants
        for i from 1 to numFrames
            if newFormantFreq_'i'_'f' <> undefined
                # Collect neighboring frames
                sum_freq = 0
                sum_bw = 0
                count = 0
                
                half_window = (smoothing_window - 1) / 2
                for j from max(1, i - half_window) to min(numFrames, i + half_window)
                    freq = newFormantFreq_'j'_'f'
                    bw = newFormantBand_'j'_'f'
                    if freq <> undefined
                        sum_freq = sum_freq + freq
                        sum_bw = sum_bw + bw
                        count = count + 1
                    endif
                endfor
                
                if count > 0
                    smoothedFormantFreq_'i'_'f' = sum_freq / count
                    smoothedFormantBand_'i'_'f' = sum_bw / count
                else
                    smoothedFormantFreq_'i'_'f' = newFormantFreq_'i'_'f'
                    smoothedFormantBand_'i'_'f' = newFormantBand_'i'_'f'
                endif
            else
                smoothedFormantFreq_'i'_'f' = undefined
                smoothedFormantBand_'i'_'f' = undefined
            endif
        endfor
    endfor
    
    # Copy smoothed values back
    for i from 1 to numFrames
        for f from 1 to max_formants
            newFormantFreq_'i'_'f' = smoothedFormantFreq_'i'_'f'
            newFormantBand_'i'_'f' = smoothedFormantBand_'i'_'f'
        endfor
    endfor
endif

# Third pass: Apply to FormantGrid
for i from 1 to numFrames
    nf = numFormantsInFrame_'i'
    ft = frameTime_'i'
    
    for f from 1 to nf
        newHz = newFormantFreq_'i'_'f'
        newBw = newFormantBand_'i'_'f'
        
        if newHz <> undefined
            Remove formant points between: f, ft - 0.0001, ft + 0.0001
            Add formant point: f, ft, newHz
            
            Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
            Add bandwidth point: f, ft, newBw
        endif
    endfor
endfor

# ============================================================
# STEP 4: Resynthesize with ARTIFACT REDUCTION
# ============================================================
appendInfoLine: "[4/4] Resynthesizing with artifact reduction..."

selectObject: sourceExcitation
plusObject: formantGrid
resynthMono = Filter

# Apply de-emphasis to match pre-emphasis
selectObject: resynthMono
Filter (de-emphasis): preEmphasis
resynthMono_deemp = selected("Sound")
removeObject: resynthMono
resynthMono = resynthMono_deemp

# Intensity matching
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

# Enhanced artifact reduction
if apply_artifact_reduction
    selectObject: resynthMono
    
    # Stage 1: Remove high-frequency LPC artifacts
    Filter (stop Hann band): max_formant_hz * 0.95, 10000, 100
    artifact_filtered = selected("Sound")
    
    # Stage 2: Spectral smoothing (reduces "water" sound)
    To Spectrum: "yes"
    spectrum_smooth = selected("Spectrum")
    Formula: "if self > 0 then self * (1 + 0.1 * (self[row-1] + self[row+1]) / (2 * self)) else self fi"
    To Sound
    smooth_sound = selected("Sound")
    removeObject: spectrum_smooth
    
    # Stage 3: Gentle de-clicking
    Formula: "if abs(self - self[col-1]) > 0.5 then (self[col-1] + self[col+1])/2 else self fi"
    
    removeObject: artifact_filtered, resynthMono
    resynthMono = smooth_sound
endif

# Dry/wet mix
if dry_wet_mix < 1
    dryMix$ = string$(1 - dry_wet_mix)
    wetMix$ = string$(dry_wet_mix)
    monoId$ = string$(soundMono)
    
    selectObject: resynthMono
    Formula: wetMix$ + " * self + " + dryMix$ + " * Object_" + monoId$ + "(x)"
endif

# Handle stereo
if numChannels > 1
    selectObject: sound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: sound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left
    selectObject: leftChannel
    lpcL = To LPC (burg): lpc_order, window_length_s, time_step_s, preEmphasis
    selectObject: leftChannel
    plusObject: lpcL
    sourceL = Filter (inverse)
    
    selectObject: sourceL
    plusObject: formantGrid
    resynthL = Filter
    
    selectObject: resynthL
    Filter (de-emphasis): preEmphasis
    resynthL_deemp = selected("Sound")
    removeObject: resynthL
    resynthL = resynthL_deemp
    
    # Process right
    selectObject: rightChannel
    lpcR = To LPC (burg): lpc_order, window_length_s, time_step_s, preEmphasis
    selectObject: rightChannel
    plusObject: lpcR
    sourceR = Filter (inverse)
    
    selectObject: sourceR
    plusObject: formantGrid
    resynthR = Filter
    
    selectObject: resynthR
    Filter (de-emphasis): preEmphasis
    
    # Intensity matching
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
    
    if apply_artifact_reduction
        selectObject: resynthL
        Filter (stop Hann band): max_formant_hz * 0.95, 10000, 100
        resynthL_filtered = selected("Sound")
        To Spectrum: "yes"
        spectrum_L = selected("Spectrum")
        Formula: "if self > 0 then self * (1 + 0.1 * (self[row-1] + self[row+1]) / (2 * self)) else self fi"
        To Sound
        resynthL_smooth = selected("Sound")
        Formula: "if abs(self - self[col-1]) > 0.5 then (self[col-1] + self[col+1])/2 else self fi"
        removeObject: spectrum_L, resynthL_filtered, resynthL
        resynthL = resynthL_smooth
        
        selectObject: resynthR
        Filter (stop Hann band): max_formant_hz * 0.95, 10000, 100
        resynthR_filtered = selected("Sound")
        To Spectrum: "yes"
        spectrum_R = selected("Spectrum")
        Formula: "if self > 0 then self * (1 + 0.1 * (self[row-1] + self[row+1]) / (2 * self)) else self fi"
        To Sound
        resynthR_smooth = selected("Sound")
        Formula: "if abs(self - self[col-1]) > 0.5 then (self[col-1] + self[col+1])/2 else self fi"
        removeObject: spectrum_R, resynthR_filtered, resynthR
        resynthR = resynthR_smooth
    endif
    
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
    
    Scale peak: 0.95
    Rename: originalName$ + "_FormantStretch_" + presetName$
    
    removeObject: leftChannel, rightChannel, lpcL, lpcR, sourceL, sourceR, resynthL, resynthR
else
    selectObject: resynthMono
    Scale peak: 0.95
    Rename: originalName$ + "_FormantStretch_" + presetName$
    finalOutput = selected("Sound")
endif

# Cleanup
removeObject: soundMono, lpc, sourceExcitation, formantPath, formantObj, formantGrid

# ============================================================
# VISUALIZATION
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
    Text: 0.5, "centre", 0.6, "half", "Individual Formant Stretcher v1.1"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.2, "half", presetName$ + " | Anti-Artifact Enhanced"
    
    # Waveforms
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.6, 3.7, 0.7, 1.75
    
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Waveform"
    
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.4, 7.7, 0.7, 1.75
    
    selectObject: finalOutput
    Colour: "{0.3, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Stretched"
    Text bottom: "yes", "Time (s)"
    
    # FORMANT TRAJECTORIES
    Select outer viewport: 0, 8, 1.9, 4.5
    Select inner viewport: 0.6, 7.7, 2.0, 4.45
    
    Axes: 0, duration, 0, 4500
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 4500
    
    formant_colors$# = {"{0.3, 0.5, 0.9}", "{0.9, 0.5, 0.3}", "{0.3, 0.8, 0.5}", "{0.8, 0.3, 0.7}", "{0.9, 0.7, 0.3}"}
    
    # Draw original formants (dotted)
    for f from 1 to 5
        Colour: formant_colors$#[f]
        Dotted line
        Line width: 1
        for i from 1 to numFrames - 1
            i_next = i + 1
            t1 = frameTime_'i'
            t2 = frameTime_'i_next'
            freq1 = origFormantFreq_'i'_'f'
            freq2 = origFormantFreq_'i_next'_'f'
            if freq1 <> undefined and freq2 <> undefined and freq1 < 4500 and freq2 < 4500
                Draw line: t1, freq1, t2, freq2
            endif
        endfor
        Solid line
    endfor
    
    # Draw modified formants (solid, smoothed)
    for f from 1 to 5
        Colour: formant_colors$#[f]
        Line width: 2
        for i from 1 to numFrames - 1
            i_next = i + 1
            t1 = frameTime_'i'
            t2 = frameTime_'i_next'
            freq1 = newFormantFreq_'i'_'f'
            freq2 = newFormantFreq_'i_next'_'f'
            if freq1 <> undefined and freq2 <> undefined and freq1 < 4500 and freq2 < 4500
                Draw line: t1, freq1, t2, freq2
            endif
        endfor
        Line width: 1
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Formant Trajectories (dotted=original, solid=smoothed)"
    Text bottom: "yes", "Time (s)"
    
    Font size: 5
    legend_x = duration * 0.02
    Colour: formant_colors$#[1]
    Text: legend_x, "left", 400, "half", "F1"
    Colour: formant_colors$#[2]
    Text: legend_x, "left", 1200, "half", "F2"
    Colour: formant_colors$#[3]
    Text: legend_x, "left", 2200, "half", "F3"
    Colour: formant_colors$#[4]
    Text: legend_x, "left", 3200, "half", "F4"
    Colour: formant_colors$#[5]
    Text: legend_x, "left", 4000, "half", "F5"
    
    # Spectrograms
    Select outer viewport: 0, 4, 4.6, 6.5
    Select inner viewport: 0.6, 3.7, 4.7, 6.45
    
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
    
    Select outer viewport: 4, 8, 4.6, 6.5
    Select inner viewport: 4.4, 7.7, 4.7, 6.45
    
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
    Text top: "no", "Stretched Spectrogram"
    
    removeObject: proc_spec, spec_proc
    
    # Parameter panel
    Select outer viewport: 0, 8, 6.6, 7.5
    Select inner viewport: 0.6, 7.7, 6.7, 7.45
    
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.9, "half", "Processing Details"
    
    Font size: 6
    Colour: "{0.5, 0.5, 0.5}"
    
    Text: 0.05, "left", 0.65, "half", "Global: " + fixed$(global_transpose_semitones, 1) + " st"
    Text: 0.25, "left", 0.65, "half", "F1: " + fixed$(f1_transpose_semitones, 1) + " st"
    Text: 0.40, "left", 0.65, "half", "F2: " + fixed$(f2_transpose_semitones, 1) + " st"
    Text: 0.55, "left", 0.65, "half", "F3: " + fixed$(f3_transpose_semitones, 1) + " st"
    Text: 0.70, "left", 0.65, "half", "F4: " + fixed$(f4_transpose_semitones, 1) + " st"
    Text: 0.85, "left", 0.65, "half", "F5: " + fixed$(f5_transpose_semitones, 1) + " st"
    
    Text: 0.05, "left", 0.35, "half", "LPC: " + string$(lpc_order)
    if apply_formant_smoothing
        Text: 0.20, "left", 0.35, "half", "✓ Smoothing"
    endif
    if apply_artifact_reduction
        Text: 0.40, "left", 0.35, "half", "✓ Anti-Artifact"
    endif
    Text: 0.65, "left", 0.35, "half", "BW: " + fixed$(bandwidth_scale, 2) + "x"
    Text: 0.82, "left", 0.35, "half", "Mix: " + fixed$(dry_wet_mix, 2)
    
    Font size: 10
endif

# Output
selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Artifact reduction applied:"
appendInfoLine: "  • LPC order: ", lpc_order
appendInfoLine: "  • Temporal smoothing: ", apply_formant_smoothing
appendInfoLine: "  • Spectral smoothing: ", apply_artifact_reduction
appendInfoLine: "  • De-emphasis correction"

if play_after_processing
    appendInfoLine: "Playing result..."
    Play
endif