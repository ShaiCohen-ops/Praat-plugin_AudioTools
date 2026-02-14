# ============================================================
# Praat AudioTools - Stereo_Micro_Macro_Time_Collapser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - Enhanced with Visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Micro ↔ Macro Time Collapser - Creative electroacoustic
#   composition tool that inverts temporal scales: micro-bursts are
#   stretched into sustained textures while slow passages are compressed
#   into transient gestures. Stereo decorrelation via parallel granular
#   processing with per-channel jitter and pitch shift.
#
#   Pipeline:
#   1. Intensity analysis to detect micro-bursts and slow textures
#   2. Time-stretch micro-bursts (OLA resynthesis)
#   3. Time-compress slow textures
#   4. Stereo decorrelation with per-channel jitter & pitch shift
#   5. Interleave and crossfade assembly
#   6. Multi-panel visualization
#
# ============================================================

form Stereo Micro ↔ Macro Time Collapser
    comment === Preset Selection ===
    optionmenu Preset: 1
        option Custom
        option Gentle Bloom (subtle expansion)
        option Extreme Inversion (dramatic scale swap)
        option Micro Detail Focus (emphasize bursts)
        option Macro Drone (emphasize slow textures)
        option Granular Chaos (high fragmentation)
        option Smooth Morph (minimal disruption)
    comment === Analysis Parameters ===
    positive Micro_window_ms 15
    positive Micro_burst_min_ms 25
    positive Micro_burst_max_ms 180
    positive Burst_threshold_dB_above_median 8
    positive Slow_min_ms 600
    real Slow_variance_threshold 0.15
    positive Slow_slope_threshold_dB_per_s 6
    comment === Transformation Parameters ===
    positive Stretch_factor 12
    positive Compress_factor 0.15
    positive Crossfade_ms 15
    comment === Stereo Parameters ===
    positive Stereo_width_percent 20
    comment === Assembly Parameters ===
    optionmenu Interleave_mode: 1
        option Alternate (micro/slow when available)
        option Probabilistic (50/50)
        option Timeline order (swapped roles)
    comment === Output ===
    positive Target_output_duration_s 60
    positive Max_output_duration_s 120
    boolean Allow_fallback_if_insufficient_segments 1
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ============================================================
# Apply Presets
# ============================================================

if preset = 2
    micro_window_ms = 12
    micro_burst_min_ms = 20
    micro_burst_max_ms = 150
    burst_threshold_dB_above_median = 6
    slow_min_ms = 800
    slow_variance_threshold = 0.12
    slow_slope_threshold_dB_per_s = 5
    stretch_factor = 8
    compress_factor = 0.25
    crossfade_ms = 20
    interleave_mode = 1
    presetName$ = "GentleBloom"
elsif preset = 3
    micro_window_ms = 10
    micro_burst_min_ms = 15
    micro_burst_max_ms = 100
    burst_threshold_dB_above_median = 10
    slow_min_ms = 500
    slow_variance_threshold = 0.2
    slow_slope_threshold_dB_per_s = 8
    stretch_factor = 20
    compress_factor = 0.08
    crossfade_ms = 8
    interleave_mode = 2
    presetName$ = "ExtremeInversion"
elsif preset = 4
    micro_window_ms = 8
    micro_burst_min_ms = 15
    micro_burst_max_ms = 80
    burst_threshold_dB_above_median = 12
    slow_min_ms = 1000
    slow_variance_threshold = 0.1
    slow_slope_threshold_dB_per_s = 4
    stretch_factor = 15
    compress_factor = 0.3
    crossfade_ms = 5
    interleave_mode = 1
    presetName$ = "MicroDetailFocus"
elsif preset = 5
    micro_window_ms = 20
    micro_burst_min_ms = 40
    micro_burst_max_ms = 200
    burst_threshold_dB_above_median = 5
    slow_min_ms = 400
    slow_variance_threshold = 0.25
    slow_slope_threshold_dB_per_s = 10
    stretch_factor = 6
    compress_factor = 0.05
    crossfade_ms = 25
    interleave_mode = 3
    presetName$ = "MacroDrone"
elsif preset = 6
    micro_window_ms = 8
    micro_burst_min_ms = 10
    micro_burst_max_ms = 60
    burst_threshold_dB_above_median = 15
    slow_min_ms = 300
    slow_variance_threshold = 0.3
    slow_slope_threshold_dB_per_s = 15
    stretch_factor = 25
    compress_factor = 0.05
    crossfade_ms = 3
    interleave_mode = 2
    presetName$ = "GranularChaos"
elsif preset = 7
    micro_window_ms = 25
    micro_burst_min_ms = 50
    micro_burst_max_ms = 250
    burst_threshold_dB_above_median = 4
    slow_min_ms = 1000
    slow_variance_threshold = 0.08
    slow_slope_threshold_dB_per_s = 3
    stretch_factor = 5
    compress_factor = 0.4
    crossfade_ms = 30
    interleave_mode = 1
    presetName$ = "SmoothMorph"
else
    presetName$ = "Custom"
endif

# ============================================================
# Input validation
# ============================================================

nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

inputSound = selected("Sound")
selectObject: inputSound
inputName$ = selected$("Sound")
inputDuration = Get total duration
inputChannels = Get number of channels
sampleRate = Get sampling frequency

if inputDuration < 0.1
    exitScript: "Sound too short (< 0.1 s). Cannot analyze."
endif

writeInfoLine: "Micro <-> Macro STEREO Collapser"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", inputName$
appendInfoLine: "Duration: ", fixed$(inputDuration, 3), " s"
appendInfoLine: "Target output: ", fixed$(target_output_duration_s, 1), " s (cap: ", fixed$(max_output_duration_s, 0), " s)"

# ============================================================
# Convert to mono for analysis (Common Analysis)
# ============================================================
selectObject: inputSound
if inputChannels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: "analysis_mono"
endif

# ============================================================
# Extract intensity contour
# ============================================================
appendInfoLine: "[1/6] Analyzing intensity (Mono)..."

selectObject: analysisMono
To Intensity: 70, micro_window_ms / 1000, "yes"
intensityObj = selected("Intensity")

selectObject: intensityObj
medianIntensity = Get quantile: 0, 0, 0.5

microWindow_s = micro_window_ms / 1000
microBurstMin_s = micro_burst_min_ms / 1000
microBurstMax_s = micro_burst_max_ms / 1000
slowMin_s = slow_min_ms / 1000
crossfade_s = crossfade_ms / 1000

# ============================================================
# Detect micro-bursts
# ============================================================
appendInfoLine: "[2/6] Detecting micro-bursts..."

numBursts = 0
t = 0
burstThreshold = medianIntensity + burst_threshold_dB_above_median

while t < inputDuration - microBurstMin_s
    selectObject: intensityObj
    intVal = Get value at time: t, "Cubic"
    
    if intVal <> undefined and intVal > burstThreshold
        tStart = t
        tEnd = t + microWindow_s
        peakInt = intVal
        
        while tEnd < inputDuration and tEnd - tStart < microBurstMax_s
            selectObject: intensityObj
            nextInt = Get value at time: tEnd, "Cubic"
            if nextInt = undefined or nextInt < burstThreshold - 3
                goto endBurst
            endif
            if nextInt > peakInt
                peakInt = nextInt
            endif
            tEnd = tEnd + microWindow_s
        endwhile
        
        label endBurst
        burstDur = tEnd - tStart
        
        if burstDur >= microBurstMin_s and burstDur <= microBurstMax_s
            numBursts = numBursts + 1
            burstStart_'numBursts' = tStart
            burstEnd_'numBursts' = tEnd
            burstPeak_'numBursts' = peakInt
        endif
        
        t = tEnd + microWindow_s
    else
        t = t + microWindow_s
    endif
endwhile

appendInfoLine: "  Found ", numBursts, " micro-bursts"

# ============================================================
# Detect slow textures
# ============================================================
appendInfoLine: "[3/6] Detecting slow textures..."

numSlowRegions = 0
t = 0
scanWindow = slowMin_s / 4

while t < inputDuration - slowMin_s
    tStart = t
    tEnd = t + slowMin_s
    
    selectObject: intensityObj
    meanInt = Get mean: tStart, tEnd, "energy"
    stdInt = Get standard deviation: tStart, tEnd
    
    if meanInt <> undefined and meanInt > 0
        variance = stdInt / max(1, meanInt)
        
        startInt = Get value at time: tStart, "Cubic"
        endInt = Get value at time: tEnd, "Cubic"
        if startInt <> undefined and endInt <> undefined
            slope = abs((endInt - startInt) / (tEnd - tStart))
        else
            slope = 999
        endif
        
        if variance < slow_variance_threshold and slope < slow_slope_threshold_dB_per_s
            numSlowRegions = numSlowRegions + 1
            slowStart_'numSlowRegions' = tStart
            slowEnd_'numSlowRegions' = tEnd
            slowVar_'numSlowRegions' = variance
            t = tEnd
        else
            t = t + scanWindow
        endif
    else
        t = t + scanWindow
    endif
endwhile

appendInfoLine: "  Found ", numSlowRegions, " slow textures"

# ============================================================
# Fallback
# ============================================================
if (numBursts < 2 or numSlowRegions < 2) and allow_fallback_if_insufficient_segments
    appendInfoLine: "⚠ Using fallback analysis..."
    selectObject: intensityObj
    q25 = Get quantile: 0, 0, 0.25
    q75 = Get quantile: 0, 0, 0.75
    numBursts = 0
    numSlowRegions = 0
    t = 0
    while t < inputDuration - 0.05
        selectObject: intensityObj
        intVal = Get value at time: t, "Cubic"
        if intVal <> undefined
            if intVal > q75
                dur = randomUniform(microBurstMin_s, microBurstMax_s)
                if t + dur < inputDuration
                    numBursts = numBursts + 1
                    burstStart_'numBursts' = t
                    burstEnd_'numBursts' = t + dur
                    burstPeak_'numBursts' = intVal
                    t = t + dur
                else
                    t = inputDuration
                endif
            elsif intVal < q25
                dur = randomUniform(slowMin_s, slowMin_s * 2)
                if t + dur < inputDuration
                    numSlowRegions = numSlowRegions + 1
                    slowStart_'numSlowRegions' = t
                    slowEnd_'numSlowRegions' = t + dur
                    t = t + dur
                else
                    t = inputDuration
                endif
            else
                t = t + 0.05
            endif
        else
            t = t + 0.05
        endif
    endwhile
endif

if numBursts = 0 and numSlowRegions = 0
    exitScript: "No segments detected. Cannot proceed."
endif

# ============================================================
# STEREO GENERATION LOOP
# ============================================================
appendInfoLine: ""
appendInfoLine: "[4/6] Generating Stereo Channels..."

# We loop twice: channel 1 (Left), channel 2 (Right)
for channel to 2
    appendInfoLine: "  Processing Channel ", channel, "..."
    
    # 1. TRANSFORM SEGMENTS (with unique jitter per channel)
    for i to numBursts
        tStart = burstStart_'i'
        tEnd = burstEnd_'i'
        
        selectObject: inputSound
        burstSeg = Extract part: tStart, tEnd, "rectangular", 1, "no"
        segDur = Get total duration
        
        requiredFloor = 3.0 / segDur
        safePitchFloor = requiredFloor + 5.0
        
        if safePitchFloor < 590
            selectObject: burstSeg
            To Manipulation: 0.01, safePitchFloor, 600
            manip = selected("Manipulation")
            
            selectObject: manip
            Extract duration tier
            durationTier = selected("DurationTier")
            
            # --- STEREO JITTER ---
            jitter = randomUniform(-stereo_width_percent/200, stereo_width_percent/200)
            current_stretch = stretch_factor * (1 + jitter)
            
            selectObject: durationTier
            Add point: 0, current_stretch
            
            selectObject: manip
            plusObject: durationTier
            Replace duration tier
            
            selectObject: manip
            Get resynthesis (overlap-add)
            tempSound = selected("Sound")
            removeObject: manip, durationTier

            # --- STEREO PITCH SHIFT (FIXED) ---
            if stereo_width_percent > 0
                selectObject: tempSound
                currSR = Get sampling frequency
                pitch_shift_factor = randomUniform(0.98, 1.02)
                Override sampling frequency: currSR * pitch_shift_factor
                Resample: currSR, 50
                shiftedSound = selected("Sound")
                
                removeObject: tempSound
                burstTransformed_'i' = shiftedSound
            else
                burstTransformed_'i' = tempSound
            endif
        else
            selectObject: burstSeg
            burstTransformed_'i' = Copy: "burst_skipped"
        endif
        
        selectObject: burstTransformed_'i'
        Scale peak: 0.95
        removeObject: burstSeg
    endfor

    for i to numSlowRegions
        tStart = slowStart_'i'
        tEnd = slowEnd_'i'
        
        selectObject: inputSound
        slowSeg = Extract part: tStart, tEnd, "rectangular", 1, "no"
        segDur = Get total duration
        
        requiredFloor = 3.0 / segDur
        safePitchFloor = requiredFloor + 5.0
        
        if safePitchFloor < 590
            selectObject: slowSeg
            To Manipulation: 0.01, safePitchFloor, 600
            manip = selected("Manipulation")
            
            selectObject: manip
            Extract duration tier
            durationTier = selected("DurationTier")
            
            # --- STEREO JITTER ---
            jitter = randomUniform(-stereo_width_percent/200, stereo_width_percent/200)
            current_compress = compress_factor * (1 + jitter)
            
            selectObject: durationTier
            Add point: 0, current_compress
            
            selectObject: manip
            plusObject: durationTier
            Replace duration tier
            
            selectObject: manip
            Get resynthesis (overlap-add)
            tempSound = selected("Sound")
            removeObject: manip, durationTier

            # --- STEREO PITCH SHIFT (FIXED) ---
            if stereo_width_percent > 0
                selectObject: tempSound
                currSR = Get sampling frequency
                pitch_shift_factor = randomUniform(0.99, 1.01)
                Override sampling frequency: currSR * pitch_shift_factor
                Resample: currSR, 50
                shiftedSound = selected("Sound")
                
                removeObject: tempSound
                slowTransformed_'i' = shiftedSound
            else
                slowTransformed_'i' = tempSound
            endif
        else
            selectObject: slowSeg
            slowTransformed_'i' = Copy: "slow_skipped"
        endif
        
        selectObject: slowTransformed_'i'
        Scale peak: 0.95
        removeObject: slowSeg
    endfor

    # 2. INTERLEAVE & ASSEMBLE
    totalSegments = numBursts + numSlowRegions
    segmentOrder# = zero# (totalSegments)
    segmentType# = zero# (totalSegments)
    segIdx = 0

    if interleave_mode = 1
        burstIdx = 1
        slowIdx = 1
        while burstIdx <= numBursts or slowIdx <= numSlowRegions
            if burstIdx <= numBursts
                segIdx = segIdx + 1
                segmentOrder#[segIdx] = burstIdx
                segmentType#[segIdx] = 1
                burstIdx = burstIdx + 1
            endif
            if slowIdx <= numSlowRegions
                segIdx = segIdx + 1
                segmentOrder#[segIdx] = slowIdx
                segmentType#[segIdx] = 2
                slowIdx = slowIdx + 1
            endif
        endwhile
    elsif interleave_mode = 2
        burstIdx = 1
        slowIdx = 1
        for i to totalSegments
            if randomUniform(0, 1) < 0.5 and burstIdx <= numBursts
                segIdx = segIdx + 1
                segmentOrder#[segIdx] = burstIdx
                segmentType#[segIdx] = 1
                burstIdx = burstIdx + 1
            elsif slowIdx <= numSlowRegions
                segIdx = segIdx + 1
                segmentOrder#[segIdx] = slowIdx
                segmentType#[segIdx] = 2
                slowIdx = slowIdx + 1
            elsif burstIdx <= numBursts
                segIdx = segIdx + 1
                segmentOrder#[segIdx] = burstIdx
                segmentType#[segIdx] = 1
                burstIdx = burstIdx + 1
            endif
        endfor
    else
        allEvents# = zero# (totalSegments)
        allTypes# = zero# (totalSegments)
        allIdx# = zero# (totalSegments)
        for i to numBursts
            allEvents#[i] = burstStart_'i'
            allTypes#[i] = 1
            allIdx#[i] = i
        endfor
        for i to numSlowRegions
            allEvents#[numBursts + i] = slowStart_'i'
            allTypes#[numBursts + i] = 2
            allIdx#[numBursts + i] = i
        endfor
        for i to totalSegments - 1
            for j to totalSegments - i
                if allEvents#[j] > allEvents#[j + 1]
                    temp = allEvents#[j]
                    allEvents#[j] = allEvents#[j + 1]
                    allEvents#[j + 1] = temp
                    temp = allTypes#[j]
                    allTypes#[j] = allTypes#[j + 1]
                    allTypes#[j + 1] = temp
                    temp = allIdx#[j]
                    allIdx#[j] = allIdx#[j + 1]
                    allIdx#[j + 1] = temp
                endif
            endfor
        endfor
        for i to totalSegments
            segIdx = i
            segmentOrder#[i] = allIdx#[i]
            segmentType#[i] = allTypes#[i]
        endfor
    endif

    # 3. CONCATENATE (loop through segment pool until target duration)
    effectiveCap = min(target_output_duration_s, max_output_duration_s)
    
    if segIdx > 0
        firstType = segmentType#[1]
        firstIdx = segmentOrder#[1]
        if firstType = 1
            selectObject: burstTransformed_'firstIdx'
        else
            selectObject: slowTransformed_'firstIdx'
        endif
        outputSound = Copy: "temp_output"
        
        poolPos = 2
        
        while poolPos > 0
            # Wrap around: cycle through segment pool
            cycleIdx = ((poolPos - 1) mod segIdx) + 1
            
            segType = segmentType#[cycleIdx]
            segOrder = segmentOrder#[cycleIdx]
            if segType = 1
                selectObject: burstTransformed_'segOrder'
            else
                selectObject: slowTransformed_'segOrder'
            endif
            nextSeg = Copy: "next_seg"
            
            selectObject: outputSound
            currentDur = Get total duration
            selectObject: nextSeg
            nextDur = Get total duration
            
            minDur = min(currentDur, nextDur)
            safeCrossfade = min(crossfade_s, minDur * 0.3)
            
            if safeCrossfade > 0.002 and currentDur > safeCrossfade * 2 and nextDur > safeCrossfade * 2
                selectObject: outputSound, nextSeg
                Concatenate with overlap: safeCrossfade
                temp = selected("Sound")
                removeObject: outputSound
                outputSound = temp
            else
                selectObject: outputSound, nextSeg
                Concatenate
                temp = selected("Sound")
                removeObject: outputSound
                outputSound = temp
            endif
            removeObject: nextSeg
            
            selectObject: outputSound
            totalDur = Get total duration
            
            # Stop if we've reached the target or hit the hard cap
            if totalDur >= effectiveCap
                goto stopAssemblyStereo
            endif
            
            poolPos = poolPos + 1
        endwhile
        label stopAssemblyStereo
        
        # Trim to exact target duration
        selectObject: outputSound
        totalDur = Get total duration
        if totalDur > effectiveCap
            Extract part: 0, effectiveCap, "rectangular", 1, "no"
            trimmed = selected("Sound")
            removeObject: outputSound
            outputSound = trimmed
        endif
    endif

    selectObject: outputSound
    Rename: "Channel_" + string$(channel)
    finalChannel_'channel' = selected("Sound")

    # Cleanup grains for this channel to free memory
    for i to numBursts
        removeObject: burstTransformed_'i'
    endfor
    for i to numSlowRegions
        removeObject: slowTransformed_'i'
    endfor
endfor

# ============================================================
# Combine to Stereo
# ============================================================
appendInfoLine: "[5/6] Merging Stereo Field..."

selectObject: finalChannel_1
dur1 = Get total duration
selectObject: finalChannel_2
dur2 = Get total duration
maxDur = max(dur1, dur2)

# Pad shorter channel so they match exactly
if dur1 < maxDur
    selectObject: finalChannel_1
    diff = maxDur - dur1
    silence = Create Sound from formula: "silence", 1, 0, diff, sampleRate, "0"
    selectObject: finalChannel_1, silence
    Concatenate
    temp = selected("Sound")
    removeObject: finalChannel_1, silence
    finalChannel_1 = temp
endif

if dur2 < maxDur
    selectObject: finalChannel_2
    diff = maxDur - dur2
    silence = Create Sound from formula: "silence", 1, 0, diff, sampleRate, "0"
    selectObject: finalChannel_2, silence
    Concatenate
    temp = selected("Sound")
    removeObject: finalChannel_2, silence
    finalChannel_2 = temp
endif

selectObject: finalChannel_1, finalChannel_2
Combine to stereo
Rename: "Stereo_Collapser_Output"
Scale peak: 0.99
finalOutput = selected("Sound")

selectObject: finalOutput
outputDuration = Get total duration

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "[6/6] Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Stereo Micro ↔ Macro Time Collapser##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half", inputName$ + " | " + presetName$ + " | Target: " + fixed$(target_output_duration_s, 1) + " s | Stretch: ×" + fixed$(stretch_factor, 1) + " | Compress: ×" + fixed$(compress_factor, 2)
    
    # === ORIGINAL WAVEFORM ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.7, 1.35
    selectObject: analysisMono
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(inputDuration, 2) + " s (" + string$(inputChannels) + "ch, " + string$(sampleRate) + " Hz)"
    
    # === INTENSITY CONTOUR WITH SEGMENT MAP ===
    Select outer viewport: 0, 8, 1.5, 2.9
    Select inner viewport: 0.6, 7.7, 1.6, 2.8
    
    selectObject: intensityObj
    minInt = Get minimum: 0, 0, "Parabolic"
    maxInt = Get maximum: 0, 0, "Parabolic"
    if minInt = undefined
        minInt = 40
    endif
    if maxInt = undefined
        maxInt = 90
    endif
    intRange = maxInt - minInt
    if intRange < 1
        intRange = 1
    endif
    
    Axes: 0, inputDuration, minInt - intRange * 0.1, maxInt + intRange * 0.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, inputDuration, minInt - intRange * 0.1, maxInt + intRange * 0.15
    
    # Draw slow texture regions (cool blue, behind)
    for i to numSlowRegions
        Paint rectangle: "{0.75, 0.85, 0.95}", slowStart_'i', slowEnd_'i', minInt - intRange * 0.1, maxInt + intRange * 0.15
    endfor
    
    # Draw micro-burst regions (warm orange, behind)
    for i to numBursts
        Paint rectangle: "{0.95, 0.85, 0.75}", burstStart_'i', burstEnd_'i', minInt - intRange * 0.1, maxInt + intRange * 0.15
    endfor
    
    # Draw threshold line
    Colour: "{0.9, 0.4, 0.4}"
    Dotted line
    Draw line: 0, burstThreshold, inputDuration, burstThreshold
    Solid line
    
    # Draw intensity contour
    selectObject: intensityObj
    Colour: "{0.3, 0.3, 0.4}"
    Line width: 1.5
    Draw: 0, 0, 0, 0, "no"
    Line width: 1
    
    # Draw burst peak markers
    for i to numBursts
        midT = (burstStart_'i' + burstEnd_'i') / 2
        Paint circle (mm): "{0.9, 0.4, 0.3}", midT, burstPeak_'i', 0.6
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Intensity (dB)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Segment Detection: " + string$(numBursts) + " bursts, " + string$(numSlowRegions) + " slow textures"
    
    # === ORIGINAL SPECTROGRAM ===
    Select outer viewport: 0, 8, 3.0, 4.3
    Select inner viewport: 0.6, 7.7, 3.1, 4.2
    
    selectObject: analysisMono
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original Spectrogram"
    
    removeObject: origSpec
    
    # === RESULT WAVEFORMS (Stereo: L + R side by side) ===
    # Left channel
    Select outer viewport: 0, 4, 4.4, 5.1
    Select inner viewport: 0.6, 3.7, 4.5, 5.05
    selectObject: finalChannel_1
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result L"
    Text top: "no", fixed$(outputDuration, 2) + " s (target: " + fixed$(target_output_duration_s, 1) + " s)"
    Select outer viewport: 4, 8, 4.4, 5.1
    Select inner viewport: 4.4, 7.7, 4.5, 5.05
    selectObject: finalChannel_2
    Colour: "{0.8, 0.5, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result R"
    Text bottom: "yes", "Time (s)"
    
    # === RESULT SPECTROGRAM (from left channel) ===
    Select outer viewport: 0, 8, 5.2, 6.5
    Select inner viewport: 0.6, 7.7, 5.3, 6.4
    
    selectObject: finalChannel_1
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Result Spectrogram (L channel)"
    
    removeObject: resultSpec
    
    # === SEGMENT DURATION DISTRIBUTION ===
    Select outer viewport: 0, 4, 6.6, 7.8
    Select inner viewport: 0.6, 3.7, 6.7, 7.7
    
    # Calculate average durations for bar chart
    avgBurstDur = 0
    maxBurstDur = 0
    for i to numBursts
        bDur = burstEnd_'i' - burstStart_'i'
        avgBurstDur = avgBurstDur + bDur
        if bDur > maxBurstDur
            maxBurstDur = bDur
        endif
    endfor
    if numBursts > 0
        avgBurstDur = avgBurstDur / numBursts
    endif
    
    avgSlowDur = 0
    maxSlowDur = 0
    for i to numSlowRegions
        sDur = slowEnd_'i' - slowStart_'i'
        avgSlowDur = avgSlowDur + sDur
        if sDur > maxSlowDur
            maxSlowDur = sDur
        endif
    endfor
    if numSlowRegions > 0
        avgSlowDur = avgSlowDur / numSlowRegions
    endif
    
    # Compute estimated transformed durations
    estBurstOut = avgBurstDur * stretch_factor
    estSlowOut = avgSlowDur * compress_factor
    
    yMax = max(max(avgBurstDur, avgSlowDur), max(estBurstOut, estSlowOut)) * 1.2
    if yMax < 0.01
        yMax = 1
    endif
    
    Axes: 0, 5, 0, yMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 5, 0, yMax
    
    barW = 0.6
    
    # Original burst avg
    Paint rectangle: "{0.95, 0.7, 0.55}", 1 - barW/2, 1 + barW/2, 0, avgBurstDur
    # Original slow avg
    Paint rectangle: "{0.6, 0.78, 0.9}", 2 - barW/2, 2 + barW/2, 0, avgSlowDur
    # Transformed burst (stretched)
    Paint rectangle: "{0.9, 0.4, 0.3}", 3 - barW/2, 3 + barW/2, 0, estBurstOut
    # Transformed slow (compressed)
    Paint rectangle: "{0.3, 0.55, 0.8}", 4 - barW/2, 4 + barW/2, 0, estSlowOut
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Colour: "{0.3, 0.3, 0.3}"
    Text: 1, "centre", -yMax * 0.06, "half", "Burst"
    Text: 2, "centre", -yMax * 0.06, "half", "Slow"
    Text: 3, "centre", -yMax * 0.06, "half", "B×Str"
    Text: 4, "centre", -yMax * 0.06, "half", "S×Cmp"
    
    Font size: 6
    Colour: "Black"
    Text left: "yes", "Duration (s)"
    Text top: "no", "Avg Segment Durations"
    
    # === PARAMETERS & STATS ===
    Select outer viewport: 4, 8, 6.6, 7.8
    Select inner viewport: 4.4, 7.7, 6.7, 7.7
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    Text: 0.05, "left", 0.88, "half", "##Processing Summary##"
    
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    
    # Interleave mode label
    if interleave_mode = 1
        modeLabel$ = "Alternate"
    elsif interleave_mode = 2
        modeLabel$ = "Probabilistic"
    else
        modeLabel$ = "Timeline"
    endif
    
    Text: 0.05, "left", 0.72, "half", "Micro-bursts: " + string$(numBursts) + " (avg " + fixed$(avgBurstDur * 1000, 1) + " ms)"
    Text: 0.05, "left", 0.55, "half", "Slow textures: " + string$(numSlowRegions) + " (avg " + fixed$(avgSlowDur * 1000, 1) + " ms)"
    Text: 0.05, "left", 0.38, "half", "Stretch: ×" + fixed$(stretch_factor, 1) + " | Compress: ×" + fixed$(compress_factor, 2)
    Text: 0.05, "left", 0.21, "half", "Stereo: " + string$(stereo_width_percent) + "% | Xfade: " + fixed$(crossfade_ms, 0) + " ms"
    Text: 0.05, "left", 0.05, "half", "Mode: " + modeLabel$ + " | Target: " + fixed$(target_output_duration_s, 1) + " s | Actual: " + fixed$(outputDuration, 2) + " s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 7.85, 8.2
    Axes: 0, 1, 0, 1
    Font size: 6
    
    # Burst legend
    Paint rectangle: "{0.95, 0.85, 0.75}", 0.02, 0.05, 0.3, 0.7
    Colour: "Black"
    Text: 0.06, "left", 0.5, "half", "Micro-burst"
    
    # Slow legend
    Paint rectangle: "{0.75, 0.85, 0.95}", 0.18, 0.21, 0.3, 0.7
    Text: 0.22, "left", 0.5, "half", "Slow texture"
    
    # Threshold legend
    Colour: "{0.9, 0.4, 0.4}"
    Dotted line
    Draw line: 0.36, 0.5, 0.40, 0.5
    Solid line
    Colour: "Black"
    Text: 0.41, "left", 0.5, "half", "Burst threshold"
    
    # Channel legend
    Colour: "{0.3, 0.5, 0.8}"
    Draw line: 0.58, 0.5, 0.62, 0.5
    Colour: "Black"
    Text: 0.63, "left", 0.5, "half", "Left"
    
    Colour: "{0.8, 0.5, 0.3}"
    Draw line: 0.72, 0.5, 0.76, 0.5
    Colour: "Black"
    Text: 0.77, "left", 0.5, "half", "Right"
    
    # Peak marker legend
    Paint circle (mm): "{0.9, 0.4, 0.3}", 0.90, 0.5, 0.5
    Colour: "Black"
    Text: 0.92, "left", 0.5, "half", "Peak"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Cleanup & Finish
# ============================================================

removeObject: analysisMono, intensityObj, finalChannel_1, finalChannel_2

selectObject: finalOutput
dur = Get total duration

appendInfoLine: ""
appendInfoLine: "COMPLETE"
appendInfoLine: "Stereo Width: ", stereo_width_percent, "%"
appendInfoLine: "Target: ", fixed$(target_output_duration_s, 1), " s | Actual: ", fixed$(dur, 3), " s"

if play_output
    Play
endif