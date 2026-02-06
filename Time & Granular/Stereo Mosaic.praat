# ============================================================
# Praat AudioTools - Stereo_Mosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Creative Expansion (Fixed)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Mosaic - creates stereo composites from multiple
#   selected Sound objects by partitioning each file into
#   regions and distributing them to L/R channels with
#   extensive creative control over extraction, timing,
#   spectral content, and spatial positioning.
#
# Changelog v0.3:
#   - Added region overlap and gap control
#   - Added random time offset per file
#   - Added pitch shift range per region
#   - Added per-channel highpass/lowpass filters
#   - Added pan jitter for soft L/R positioning
#   - Added stereo width control
#   - Added cross-channel bleed
#   - Added region duration variation
#   - Added tempo scaling per region
#   - Added controllable reverse probability
#   - Added controllable amplitude variation range
#   - Fixed hardcoded sample rate (auto-detection)
#   - Compact form with presets
# ============================================================

form Stereo Mosaic v0.3
    comment Select 2+ Sound objects first
    
    comment === PRESET ===
    optionmenu Preset 1
        option Custom
        option Classic Ping Pong
        option Glitchy Scatter
        option Spectral Dance
        option Wide Stereo Field
        option Dense Overlap
        option Minimal Sparse
    
    comment === BASIC ===
    positive Regions_per_file 4
    optionmenu Channel_strategy 1
        option Alternating regions
        option Left first / Right second
        option Random split
        option Reverse order
        option Inside out
        option Spiral pattern
    
    comment === CREATIVE (0 to disable) ===
    real Overlap_percent 0
    real Gap_ms 0
    real Pitch_shift_semitones 0
    real Reverse_percent 0
    real Stereo_width_percent 100
    
    comment === OUTPUT ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Classic Ping Pong
    regions_per_file = 4
    channel_strategy = 1
    overlap_percent = 0
    gap_ms = 0
    pitch_shift_semitones = 0
    reverse_percent = 0
    stereo_width_percent = 100
    fade_time_s = 0.05
    attenuation_divisor = 1.1
    random_time_offset_percent = 0
    duration_variation_percent = 0
    tempo_scale_min = 100
    tempo_scale_max = 100
    pitch_shift_min_semitones = 0
    pitch_shift_max_semitones = 0
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 0
    cross_channel_bleed_percent = 0
    amplitude_variation_min = 100
    amplitude_variation_max = 100
elsif preset = 3
    # Glitchy Scatter
    regions_per_file = 8
    channel_strategy = 3
    overlap_percent = 0
    gap_ms = 50
    pitch_shift_semitones = 6
    reverse_percent = 40
    stereo_width_percent = 150
    fade_time_s = 0.02
    attenuation_divisor = 1.3
    random_time_offset_percent = 20
    duration_variation_percent = 30
    tempo_scale_min = 70
    tempo_scale_max = 150
    pitch_shift_min_semitones = -5
    pitch_shift_max_semitones = 7
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 30
    cross_channel_bleed_percent = 10
    amplitude_variation_min = 60
    amplitude_variation_max = 140
elsif preset = 4
    # Spectral Dance
    regions_per_file = 6
    channel_strategy = 6
    overlap_percent = 15
    gap_ms = 0
    pitch_shift_semitones = 5
    reverse_percent = 0
    stereo_width_percent = 130
    fade_time_s = 0.04
    attenuation_divisor = 1.1
    random_time_offset_percent = 10
    duration_variation_percent = 0
    tempo_scale_min = 90
    tempo_scale_max = 110
    pitch_shift_min_semitones = -7
    pitch_shift_max_semitones = 5
    left_highpass_Hz = 300
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 4000
    pan_jitter_percent = 20
    cross_channel_bleed_percent = 5
    amplitude_variation_min = 80
    amplitude_variation_max = 120
elsif preset = 5
    # Wide Stereo Field
    regions_per_file = 5
    channel_strategy = 1
    overlap_percent = 10
    gap_ms = 0
    pitch_shift_semitones = 0
    reverse_percent = 0
    stereo_width_percent = 180
    fade_time_s = 0.06
    attenuation_divisor = 1.0
    random_time_offset_percent = 0
    duration_variation_percent = 0
    tempo_scale_min = 100
    tempo_scale_max = 100
    pitch_shift_min_semitones = 0
    pitch_shift_max_semitones = 0
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 50
    cross_channel_bleed_percent = 0
    amplitude_variation_min = 100
    amplitude_variation_max = 100
elsif preset = 6
    # Dense Overlap
    regions_per_file = 12
    channel_strategy = 3
    overlap_percent = 40
    gap_ms = 0
    pitch_shift_semitones = 3
    reverse_percent = 25
    stereo_width_percent = 120
    fade_time_s = 0.03
    attenuation_divisor = 1.4
    random_time_offset_percent = 15
    duration_variation_percent = 20
    tempo_scale_min = 85
    tempo_scale_max = 115
    pitch_shift_min_semitones = -3
    pitch_shift_max_semitones = 3
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 40
    cross_channel_bleed_percent = 15
    amplitude_variation_min = 70
    amplitude_variation_max = 130
elsif preset = 7
    # Minimal Sparse
    regions_per_file = 3
    channel_strategy = 2
    overlap_percent = 0
    gap_ms = 300
    pitch_shift_semitones = 0
    reverse_percent = 10
    stereo_width_percent = 100
    fade_time_s = 0.08
    attenuation_divisor = 1.0
    random_time_offset_percent = 5
    duration_variation_percent = 10
    tempo_scale_min = 95
    tempo_scale_max = 105
    pitch_shift_min_semitones = 0
    pitch_shift_max_semitones = 0
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 10
    cross_channel_bleed_percent = 0
    amplitude_variation_min = 90
    amplitude_variation_max = 110
else
    # Custom - use form values, set hidden params to defaults
    fade_time_s = 0.05
    attenuation_divisor = 1.1
    random_time_offset_percent = 0
    duration_variation_percent = 0
    tempo_scale_min = 100
    tempo_scale_max = 100
    
    # Expand simple pitch_shift_semitones to min/max range
    if pitch_shift_semitones > 0
        pitch_shift_min_semitones = -pitch_shift_semitones
        pitch_shift_max_semitones = pitch_shift_semitones
    else
        pitch_shift_min_semitones = 0
        pitch_shift_max_semitones = 0
    endif
    
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 0
    cross_channel_bleed_percent = 0
    amplitude_variation_min = 100
    amplitude_variation_max = 100
endif

# Clamp overlap to valid range
region_overlap_percent = overlap_percent
if region_overlap_percent < 0
    region_overlap_percent = 0
endif
if region_overlap_percent > 50
    region_overlap_percent = 50
endif

gap_between_regions_ms = gap_ms

# === Input Validation ===
numberOfSelectedSounds = numberOfSelected("Sound")

if numberOfSelectedSounds = 0
    exitScript: "Please select some Sound objects first."
endif
if numberOfSelectedSounds < 2
    exitScript: "Please select at least two Sound objects."
endif
if fade_time_s < 0
    exitScript: "Fade time cannot be negative."
endif
if regions_per_file < 1
    exitScript: "Regions per file must be at least 1."
endif

# === Get Strategy Name ===
if channel_strategy = 1
    strategyName$ = "Alternating"
elsif channel_strategy = 2
    strategyName$ = "Split"
elsif channel_strategy = 3
    strategyName$ = "Random"
elsif channel_strategy = 4
    strategyName$ = "Reverse"
elsif channel_strategy = 5
    strategyName$ = "Inside-out"
else
    strategyName$ = "Spiral"
endif

# === Info ===
writeInfoLine: "=== Stereo Mosaic v0.3 ==="
appendInfoLine: "Files: ", numberOfSelectedSounds
appendInfoLine: "Regions per file: ", regions_per_file
appendInfoLine: "Strategy: ", strategyName$
appendInfoLine: ""

# === Store Original Selection and Detect Sample Rate ===
originalSounds# = selected#("Sound")
maxSR = 0

for i to numberOfSelectedSounds
    selectObject: originalSounds#[i]
    thisSR = Get sampling frequency
    if thisSR > maxSR
        maxSR = thisSR
    endif
endfor

appendInfoLine: "Sample rate: ", maxSR, " Hz"
appendInfoLine: ""

# === Convert All to Mono and Resample ===
monoSounds# = zero#(numberOfSelectedSounds)

for i to numberOfSelectedSounds
    selectObject: originalSounds#[i]
    thisSR = Get sampling frequency
    numChannels = Get number of channels
    
    Copy: "mono_work_" + string$(i)
    workID = selected("Sound")
    
    # Resample if needed
    if thisSR <> maxSR
        Resample: maxSR, 50
        removeObject: workID
        workID = selected("Sound")
    endif
    
    # Convert to mono
    if numChannels > 1
        Convert to mono
        monoID = selected("Sound")
        removeObject: workID
        monoSounds#[i] = monoID
    else
        monoSounds#[i] = workID
    endif
endfor

# === Create Initial Buffers ===
Create Sound from formula: "temp_left", 1, 0, 0.01, maxSR, "0"
leftID = selected("Sound")

Create Sound from formula: "temp_right", 1, 0, 0.01, maxSR, "0"
rightID = selected("Sound")

# === Store Region Assignments for Visualization ===
totalRegions = numberOfSelectedSounds * regions_per_file
regionFile# = zero#(totalRegions)
regionIndex# = zero#(totalRegions)
regionChannel# = zero#(totalRegions)
regionReversed# = zero#(totalRegions)
regionPitchShift# = zero#(totalRegions)
regionIdx = 0

leftCount = 0
rightCount = 0

# === Main Processing Loop ===
appendInfoLine: "Processing files..."

for i to numberOfSelectedSounds
    selectObject: monoSounds#[i]
    soundName$ = selected$("Sound")
    total_duration = Get total duration
    
    # Random time offset
    if random_time_offset_percent > 0
        maxOffset = total_duration * random_time_offset_percent / 100
        timeOffset = randomUniform(0, maxOffset)
    else
        timeOffset = 0
    endif
    
    # Calculate overlap
    overlapFactor = 1 - (region_overlap_percent / 100)
    if overlapFactor < 0.5
        overlapFactor = 0.5
    endif
    
    # Effective step size with overlap
    step_duration = (total_duration - timeOffset) / (regions_per_file * overlapFactor - (1 - overlapFactor))
    region_duration = step_duration
    
    appendInfoLine: "  File ", i, ": ", regions_per_file, " regions × ", fixed$(region_duration * 1000, 0), "ms"
    if timeOffset > 0
        appendInfoLine: "    Offset: +", fixed$(timeOffset * 1000, 0), "ms"
    endif
    
    for region to regions_per_file
        # Calculate region boundaries with overlap
        regionStart = timeOffset + (region - 1) * step_duration * overlapFactor
        regionEnd = regionStart + region_duration
        
        # Duration variation
        if duration_variation_percent > 0
            durationMult = 1 + randomUniform(-duration_variation_percent/100, duration_variation_percent/100)
            regionDurVaried = region_duration * durationMult
            regionEnd = regionStart + regionDurVaried
        endif
        
        # Clip to file boundaries
        if regionStart < 0
            regionStart = 0
        endif
        if regionEnd > total_duration
            regionEnd = total_duration
        endif
        
        if regionEnd <= regionStart
            continue
        endif
        
        selectObject: monoSounds#[i]
        Extract part: regionStart, regionEnd, "rectangular", 1, "no"
        regionSeg = selected("Sound")
        
        # === TEMPORAL PROCESSING ===
        
        # Tempo scaling
        if tempo_scale_min <> 100 or tempo_scale_max <> 100
            tempoScale = randomUniform(tempo_scale_min, tempo_scale_max) / 100
            if abs(tempoScale - 1.0) > 0.01
                selectObject: regionSeg
                Lengthen (overlap-add): 75, 600, tempoScale
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
        endif
        
        # Determine channel based on strategy
        if channel_strategy = 1
            # Alternating
            if region mod 2 = 1
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 2
            # Left first half, Right second half
            if region <= regions_per_file / 2
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 3
            # Random
            if randomUniform(0, 1) < 0.5
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 4
            # Reverse order right
            if region mod 2 = 1
                isLeftChannel = 0
            else
                isLeftChannel = 1
            endif
        elsif channel_strategy = 5
            # Inside out
            midpoint = (regions_per_file + 1) / 2
            distanceFromMid = abs(region - midpoint)
            if floor(distanceFromMid) mod 2 = 0
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        else
            # Spiral (golden ratio)
            spiralValue = (i * 1.618 + region) mod 2
            if spiralValue < 1
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        endif
        
        # Pan jitter (soft L/R)
        if pan_jitter_percent > 0
            jitterAmount = pan_jitter_percent / 100
            panShift = randomUniform(-jitterAmount, jitterAmount)
            
            if isLeftChannel = 1
                # Left channel with jitter
                if panShift > 0
                    # Shift toward center/right
                    if randomUniform(0, 1) < panShift
                        isLeftChannel = 0
                    endif
                endif
            else
                # Right channel with jitter
                if panShift < 0
                    # Shift toward center/left
                    if randomUniform(0, 1) < abs(panShift)
                        isLeftChannel = 1
                    endif
                endif
            endif
        endif
        
        # Store for visualization
        regionIdx += 1
        regionFile#[regionIdx] = i
        regionIndex#[regionIdx] = region
        regionChannel#[regionIdx] = isLeftChannel
        
        # === SPECTRAL PROCESSING ===
        
        # Pitch shifting
        pitchShift = 0
        if pitch_shift_min_semitones <> 0 or pitch_shift_max_semitones <> 0
            pitchShift = randomUniform(pitch_shift_min_semitones, pitch_shift_max_semitones)
            if abs(pitchShift) > 0.1
                selectObject: regionSeg
                pitchManip = To Manipulation: 0.01, 75, 600
                pitchTier = Extract pitch tier
                
                selectObject: pitchTier
                pitchFactor = 2^(pitchShift/12)
                pitchFactorStr$ = string$(pitchFactor)
                Formula: "self * " + pitchFactorStr$
                
                selectObject: pitchManip
                plusObject: pitchTier
                Replace pitch tier
                
                selectObject: pitchManip
                Get resynthesis (overlap-add)
                newSeg = selected("Sound")
                
                removeObject: regionSeg, pitchManip, pitchTier
                regionSeg = newSeg
            endif
        endif
        regionPitchShift#[regionIdx] = pitchShift
        
        # Channel-specific filtering
        selectObject: regionSeg
        if isLeftChannel = 1
            if left_highpass_Hz > 0
                Filter (pass Hann band): 0, left_highpass_Hz, 100
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
            if left_lowpass_Hz > 0
                selectObject: regionSeg
                Filter (pass Hann band): left_lowpass_Hz, 0, 100
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
        else
            if right_highpass_Hz > 0
                Filter (pass Hann band): 0, right_highpass_Hz, 100
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
            if right_lowpass_Hz > 0
                selectObject: regionSeg
                Filter (pass Hann band): right_lowpass_Hz, 0, 100
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
        endif
        
        # Optional reverse
        selectObject: regionSeg
        wasReversed = 0
        if reverse_percent > 0
            if randomUniform(0, 100) < reverse_percent
                Reverse
                wasReversed = 1
            endif
        endif
        regionReversed#[regionIdx] = wasReversed
        
        # === AMPLITUDE PROCESSING ===
        
        # Amplitude variation
        if amplitude_variation_min <> 100 or amplitude_variation_max <> 100
            ampMult = randomUniform(amplitude_variation_min, amplitude_variation_max) / 100
            Scale peak: ampMult * 0.95
        endif
        
        # Apply fades and attenuation
        segDur = Get total duration
        if segDur > 2 * fade_time_s
            attStr$ = string$(attenuation_divisor)
            Formula: "self / " + attStr$
            fadeStr$ = string$(fade_time_s)
            Formula: "self * min(1, x / " + fadeStr$ + ")"
            Formula: "self * min(1, (xmax - x) / " + fadeStr$ + ")"
        else
            attStr$ = string$(attenuation_divisor)
            Formula: "self / " + attStr$
        endif
        
        # Add to appropriate channel
        if isLeftChannel = 1
            selectObject: leftID, regionSeg
            Concatenate
            newLeft = selected("Sound")
            removeObject: leftID
            leftID = newLeft
            Rename: "temp_left"
            leftCount += 1
        else
            selectObject: rightID, regionSeg
            Concatenate
            newRight = selected("Sound")
            removeObject: rightID
            rightID = newRight
            Rename: "temp_right"
            rightCount += 1
        endif
        
        removeObject: regionSeg
        
        # Add gap if specified
        if gap_between_regions_ms > 0
            gapDur = gap_between_regions_ms / 1000
            gap = Create Sound from formula: "gap", 1, 0, gapDur, maxSR, "0"
            
            if isLeftChannel = 1
                selectObject: leftID, gap
                Concatenate
                newLeft = selected("Sound")
                removeObject: leftID
                leftID = newLeft
                Rename: "temp_left"
            else
                selectObject: rightID, gap
                Concatenate
                newRight = selected("Sound")
                removeObject: rightID
                rightID = newRight
                Rename: "temp_right"
            endif
            
            removeObject: gap
        endif
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Left channel: ", leftCount, " regions"
appendInfoLine: "Right channel: ", rightCount, " regions"

# === Equalize Channel Lengths ===
selectObject: leftID
leftDur = Get total duration

selectObject: rightID
rightDur = Get total duration

# Pad shorter channel with silence
if leftDur > rightDur
    silenceDur = leftDur - rightDur
    silence = Create Sound from formula: "pad", 1, 0, silenceDur, maxSR, "0"
    selectObject: rightID, silence
    Concatenate
    newRight = selected("Sound")
    removeObject: rightID, silence
    rightID = newRight
    Rename: "temp_right"
elsif rightDur > leftDur
    silenceDur = rightDur - leftDur
    silence = Create Sound from formula: "pad", 1, 0, silenceDur, maxSR, "0"
    selectObject: leftID, silence
    Concatenate
    newLeft = selected("Sound")
    removeObject: leftID, silence
    leftID = newLeft
    Rename: "temp_left"
endif

# === Stereo Width Processing ===
if stereo_width_percent <> 100
    widthFactor = stereo_width_percent / 100
    
    selectObject: leftID
    leftCopy = Copy: "left_width"
    
    selectObject: rightID
    rightCopy = Copy: "right_width"
    
    # M/S processing
    selectObject: leftID
    rightStr$ = string$(rightCopy)
    Formula: "(self + object[" + rightStr$ + "]) / 2 + ((self - object[" + rightStr$ + "]) / 2) * " + string$(widthFactor)
    
    selectObject: rightID
    leftStr$ = string$(leftCopy)
    Formula: "(self + object[" + leftStr$ + "]) / 2 - ((object[" + leftStr$ + "] - self) / 2) * " + string$(widthFactor)
    
    removeObject: leftCopy, rightCopy
endif

# === Cross-Channel Bleed ===
if cross_channel_bleed_percent > 0
    bleedAmount = cross_channel_bleed_percent / 100
    
    selectObject: leftID
    Copy: "left_for_bleed"
    leftCopy = selected("Sound")
    
    selectObject: rightID
    Copy: "right_for_bleed"
    rightCopy = selected("Sound")
    
    # Add bleed from right to left
    selectObject: leftID
    rightStr$ = string$(rightCopy)
    bleedStr$ = string$(bleedAmount)
    Formula: "self + " + bleedStr$ + " * object[" + rightStr$ + "]"
    
    # Add bleed from left to right
    selectObject: rightID
    leftStr$ = string$(leftCopy)
    Formula: "self + " + bleedStr$ + " * object[" + leftStr$ + "]"
    
    removeObject: leftCopy, rightCopy
endif

# === Finalize ===
selectObject: leftID
Scale peak: 0.99

selectObject: rightID
Scale peak: 0.99

selectObject: leftID, rightID
Combine to stereo
result = selected("Sound")

compositeName$ = "mosaic_" + string$(numberOfSelectedSounds) + "f_" + string$(regions_per_file) + "r"
Rename: compositeName$

selectObject: result
outputDuration = Get total duration

# === Cleanup ===
removeObject: leftID, rightID

for i to numberOfSelectedSounds
    if monoSounds#[i] > 0
        removeObject: monoSounds#[i]
    endif
endfor

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 10, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Mosaic v0.3: " + string$(numberOfSelectedSounds) + " files × " + string$(regions_per_file) + " regions (" + strategyName$ + ")"
    
    # Result waveform
    Select outer viewport: 0, 10, 0.6, 1.8
    Select inner viewport: 0.6, 9.6, 0.7, 1.7
    selectObject: result
    Colour: "{0.3, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Region distribution - Left channel
    Select outer viewport: 0, 10, 2.0, 3.0
    Select inner viewport: 0.6, 9.6, 2.1, 2.9
    
    maxRegionsPerChannel = max(leftCount, rightCount)
    Axes: 0, maxRegionsPerChannel, 0, numberOfSelectedSounds + 1
    Paint rectangle: "{0.9, 0.95, 1.0}", 0, maxRegionsPerChannel, 0, numberOfSelectedSounds + 1
    
    # Draw left channel regions
    leftPos = 0
    for r to regionIdx
        if regionChannel#[r] = 1
            leftPos += 1
            fileIdx = regionFile#[r]
            
            # Color by file
            hue = (fileIdx - 1) / max(1, numberOfSelectedSounds - 1)
            red = 0.3 + 0.5 * sin(hue * 2 * pi)
            grn = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            blu = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(red, 2) + ", " + fixed$(grn, 2) + ", " + fixed$(blu, 2) + "}"
            
            Paint rectangle: barColor$, leftPos - 0.9, leftPos - 0.1, fileIdx - 0.4, fileIdx + 0.4
            
            # Mark if reversed or pitch-shifted
            if regionReversed#[r] = 1
                Colour: "White"
                Font size: 5
                Text: leftPos - 0.5, "centre", fileIdx, "half", "R"
            elsif abs(regionPitchShift#[r]) > 0.5
                Colour: "White"
                Font size: 5
                Text: leftPos - 0.5, "centre", fileIdx, "half", fixed$(regionPitchShift#[r], 0)
            endif
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "File #"
    Text: 0.5, "centre", 1.08, "bottom", "LEFT CHANNEL"
    
    # Region distribution - Right channel
    Select outer viewport: 0, 10, 3.1, 4.1
    Select inner viewport: 0.6, 9.6, 3.2, 4.0
    
    Axes: 0, maxRegionsPerChannel, 0, numberOfSelectedSounds + 1
    Paint rectangle: "{1.0, 0.95, 0.9}", 0, maxRegionsPerChannel, 0, numberOfSelectedSounds + 1
    
    # Draw right channel regions
    rightPos = 0
    for r to regionIdx
        if regionChannel#[r] = 0
            rightPos += 1
            fileIdx = regionFile#[r]
            
            # Color by file
            hue = (fileIdx - 1) / max(1, numberOfSelectedSounds - 1)
            red = 0.3 + 0.5 * sin(hue * 2 * pi)
            grn = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            blu = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(red, 2) + ", " + fixed$(grn, 2) + ", " + fixed$(blu, 2) + "}"
            
            Paint rectangle: barColor$, rightPos - 0.9, rightPos - 0.1, fileIdx - 0.4, fileIdx + 0.4
            
            # Mark if reversed or pitch-shifted
            if regionReversed#[r] = 1
                Colour: "White"
                Font size: 5
                Text: rightPos - 0.5, "centre", fileIdx, "half", "R"
            elsif abs(regionPitchShift#[r]) > 0.5
                Colour: "White"
                Font size: 5
                Text: rightPos - 0.5, "centre", fileIdx, "half", fixed$(regionPitchShift#[r], 0)
            endif
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "File #"
    Text: 0.5, "centre", 1.08, "bottom", "RIGHT CHANNEL"
    
    # Parameter summary
    Select outer viewport: 0, 10, 4.3, 4.9
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    
    paramText$ = "Overlap: " + fixed$(region_overlap_percent, 0) + "% | Gap: " + fixed$(gap_between_regions_ms, 0) + "ms | "
    paramText$ = paramText$ + "Pitch: ±" + fixed$((abs(pitch_shift_min_semitones) + abs(pitch_shift_max_semitones))/2, 1) + "st | "
    paramText$ = paramText$ + "Reverse: " + fixed$(reverse_percent, 0) + "% | Width: " + fixed$(stereo_width_percent, 0) + "%"
    Text: 0.5, "centre", 0.3, "half", paramText$
    
    # Stats
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.5, "centre", 0.7, "half", "Regions: " + string$(regionIdx) + " (L:" + string$(leftCount) + " R:" + string$(rightCount) + ") | Duration: " + fixed$(outputDuration, 2) + "s | SR: " + string$(maxSR) + "Hz"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", compositeName$
appendInfoLine: "Duration: ", fixed$(outputDuration, 2), " s"
appendInfoLine: "Regions: ", regionIdx, " (L:", leftCount, " R:", rightCount, ")"
appendInfoLine: ""
appendInfoLine: "Processing applied:"
if region_overlap_percent > 0
    appendInfoLine: "  • Region overlap: ", region_overlap_percent, "%"
endif
if gap_between_regions_ms > 0
    appendInfoLine: "  • Gaps: ", gap_between_regions_ms, " ms"
endif
if pitch_shift_min_semitones <> 0 or pitch_shift_max_semitones <> 0
    appendInfoLine: "  • Pitch shift: ", pitch_shift_min_semitones, " to +", pitch_shift_max_semitones, " semitones"
endif
if reverse_percent > 0
    appendInfoLine: "  • Reverse probability: ", reverse_percent, "%"
endif
if stereo_width_percent <> 100
    appendInfoLine: "  • Stereo width: ", stereo_width_percent, "%"
endif
if cross_channel_bleed_percent > 0
    appendInfoLine: "  • Cross-channel bleed: ", cross_channel_bleed_percent, "%"
endif

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
