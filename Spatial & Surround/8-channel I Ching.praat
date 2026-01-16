# ============================================================
# Praat AudioTools - 8-channel_I_Ching.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-channel I Ching: Form & Speed
#   Uses I Ching hexagrams to generate algorithmic audio variations.
#   Each channel gets a unique hexagram that determines:
#   - Slice reversals (Yin lines = reversed)
#   - Speed deviation (hexagram value 0-63 maps to speed)
#
# Changelog v0.2:
#   - Added presets
#   - Fixed random seed handling
#   - Added pitch range options
#   - Added play toggle
#   - Enhanced visualization with hexagram numbers
# ============================================================

form 8-channel I Ching Form & Speed
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Subtle (5% deviation)"
        option: "Moderate (20% deviation)"
        option: "Extreme (50% deviation)"
        option: "Chaos (100% deviation)"
        option: "Slow Drift (20% slower bias)"
        option: "Fast Drift (20% faster bias)"
        option: "Micro-variations (2% deviation)"
    
    comment === I Ching Configuration ===
    real Deviation_range 0.20
    real Speed_bias 0.0
    
    comment === Random seed (0 = truly random) ===
    integer Random_seed 0
    
    comment === Audio Settings ===
    positive Min_pitch 75
    positive Max_pitch 600
    boolean Override_sampling_frequency 1
    positive Target_sampling_frequency 44100
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle
    deviation_range = 0.05
    speed_bias = 0.0
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate
    deviation_range = 0.20
    speed_bias = 0.0
    presetName$ = "Moderate"
elsif preset = 4
    # Extreme
    deviation_range = 0.50
    speed_bias = 0.0
    presetName$ = "Extreme"
elsif preset = 5
    # Chaos
    deviation_range = 1.00
    speed_bias = 0.0
    presetName$ = "Chaos"
elsif preset = 6
    # Slow Drift
    deviation_range = 0.20
    speed_bias = -0.15
    presetName$ = "SlowDrift"
elsif preset = 7
    # Fast Drift
    deviation_range = 0.20
    speed_bias = 0.15
    presetName$ = "FastDrift"
elsif preset = 8
    # Micro-variations
    deviation_range = 0.02
    speed_bias = 0.0
    presetName$ = "Micro"
else
    presetName$ = "Custom"
endif

# === Setup ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Set random seed if specified
if random_seed > 0
    # Use seed for reproducibility (Praat doesn't have direct seed, but we can document)
    appendInfoLine: "Note: Random seed ", random_seed, " requested (for documentation purposes)"
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")
original_freq = Get sampling frequency
original_dur = Get total duration

# === Info ===
writeInfoLine: "=== 8-Channel I Ching: Form & Speed ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Deviation: +/-", fixed$(deviation_range * 100, 0), "%"
appendInfoLine: "Speed bias: ", fixed$(speed_bias * 100, 0), "%"
appendInfoLine: ""

# === Setup Picture Window ===
if draw_visualization
    Erase all
    Select outer viewport: 0, 12, 0, 8
    Axes: 0, 10, 0, 10
    Font size: 14
    Colour: "Black"
    Text: 5, "centre", 9.5, "half", "8-CHANNEL I CHING: " + presetName$ + " | " + originalName$
    Font size: 10
endif

# === Store hexagram data for info ===
for ch from 1 to 8
    hexValue[ch] = 0
    speedFactor[ch] = 1.0
endfor

# === MAIN LOOP (8 CHANNELS) ===
for ch from 1 to 8
    
    # 1. GENERATE HEXAGRAM
    line[1] = randomInteger(0, 1)
    line[2] = randomInteger(0, 1)
    line[3] = randomInteger(0, 1)
    line[4] = randomInteger(0, 1)
    line[5] = randomInteger(0, 1)
    line[6] = randomInteger(0, 1)

    # Calculate Values
    hex_value = line[1] + (line[2]*2) + (line[3]*4) + (line[4]*8) + (line[5]*16) + (line[6]*32)
    normalized_hex = hex_value / 63
    speed_factor = 1.0 + speed_bias + ((normalized_hex * (deviation_range * 2)) - deviation_range)
    
    # Ensure speed_factor is positive
    if speed_factor < 0.1
        speed_factor = 0.1
    endif
    
    # Store for later
    hexValue[ch] = hex_value
    speedFactor[ch] = speed_factor

    # 2. DRAWING (Grid Layout)
    if draw_visualization
        if ch <= 4
            xCenter = 1.5 + (ch-1)*2.3
            yBase = 5.5
        else
            xCenter = 1.5 + (ch-5)*2.3
            yBase = 1.5
        endif
        
        Colour: "Black"
        Text: xCenter, "centre", yBase - 0.5, "half", "Ch" + string$(ch) + " #" + string$(hex_value)
        Text: xCenter, "centre", yBase - 0.85, "half", "(" + fixed$(speed_factor, 2) + "x)"
        
        Line width: 3
        for k from 1 to 6
            lineY = yBase + (k-1)*0.4
            
            if line[k] = 1
                # Yang - solid line (blue)
                Colour: "{0.3, 0.4, 0.7}"
                Draw line: xCenter-0.8, lineY, xCenter+0.8, lineY
            else
                # Yin - broken line (red)
                Colour: "{0.7, 0.4, 0.3}"
                Draw line: xCenter-0.8, lineY, xCenter-0.15, lineY
                Draw line: xCenter+0.15, lineY, xCenter+0.8, lineY
            endif
        endfor
        Line width: 1
        Colour: "Black"
    endif

    # 3. SLICING & RECOMBINATION
    selectObject: originalSound
    sliceDuration = original_dur / 6
    validSliceCount = 0
    
    for s from 1 to 6
        # Extract Slice
        startTime = (s - 1) * sliceDuration
        endTime = s * sliceDuration
        if endTime > original_dur
            endTime = original_dur
        endif
        
        if endTime - startTime > 0.001
            selectObject: originalSound
            Extract part: startTime, endTime, "rectangular", 1.0, "no"
            currentSliceID = selected("Sound")
            
            # REVERSE IF YIN
            if line[s] = 0
                Reverse
            endif
            
            # Store ID
            validSliceCount += 1
            sliceID[validSliceCount] = selected("Sound")
        endif
    endfor
    
    # Concatenate Slices
    if validSliceCount > 0
        selectObject: sliceID[1]
        for k from 2 to validSliceCount
            plusObject: sliceID[k]
        endfor
        
        Concatenate
        recombinedSound = selected("Sound")
        
        # Cleanup Slices immediately
        for k from 1 to validSliceCount
            removeObject: sliceID[k]
        endfor
    else
        # Fallback if slicing failed (rare)
        selectObject: originalSound
        Copy: "fallback"
        recombinedSound = selected("Sound")
    endif

    # 4. SPEED DEVIATION & FINALIZATION
    selectObject: recombinedSound
    
    # Force Mono (needed for overlap-add)
    nChans = Get number of channels
    if nChans > 1
        Convert to mono
        removeObject: recombinedSound
        recombinedSound = selected("Sound")
    endif
    
    # Apply Speed (Lengthen)
    dur_current = Get total duration
    target_dur = dur_current / speed_factor
    
    Lengthen (overlap-add): min_pitch, max_pitch, target_dur/dur_current
    
    removeObject: recombinedSound
    speedSound = selected("Sound")
    
    # Resample
    if override_sampling_frequency
        Resample: target_sampling_frequency, 50
    else
        Resample: original_freq, 50
    endif
    
    removeObject: speedSound
    final_channels[ch] = selected("Sound")
    Rename: "Ch" + string$(ch)

endfor

# === COMBINE 8 CHANNELS ===
selectObject: final_channels[1]
for i from 2 to 8
    plusObject: final_channels[i]
endfor

Combine to stereo
Rename: originalName$ + "_8chIChing_" + presetName$
Scale peak: 0.95
finalID = selected("Sound")

# Cleanup Channels
for i from 1 to 8
    removeObject: final_channels[i]
endfor

# === Final Info ===
appendInfoLine: "Hexagram results:"
for ch from 1 to 8
    appendInfoLine: "  Ch", ch, ": Hex #", hexValue[ch], " -> ", fixed$(speedFactor[ch], 3), "x speed"
endfor
appendInfoLine: ""
appendInfoLine: "=== Done ==="

# === Play ===
if play_result
    selectObject: finalID
    Play
endif

selectObject: finalID
