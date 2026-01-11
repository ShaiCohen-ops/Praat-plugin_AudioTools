# ============================================================
# Praat AudioTools - 8-channel_speed_deviations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Speed Deviations via PSOLA
#   Creates 8 channels with different playback speeds.
#   Preserves pitch while changing duration.
#
# Changelog v0.2:
#   - Fixed cleanup (removed dangerous select all)
#   - Added visualization
#   - Added play toggle
#   - Added presets
# ============================================================

form 8-Channel Speed Deviations
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use mode below)"
        option: "Subtle (±5%)"
        option: "Moderate (±15%)"
        option: "Wide (±30%)"
        option: "Extreme (±50%)"
        option: "Accelerando (0.7 to 1.3)"
        option: "Decelerando (1.3 to 0.7)"
    
    comment === MODE ===
    optionmenu Mode: 1
        option: "Automatic (using factor)"
        option: "Manual (input all values)"
        option: "Random deviation"
    
    comment === Automatic mode settings ===
    positive Speed_deviation_factor 0.15
    
    comment === Manual mode settings ===
    positive Channel_1_speed 0.85
    positive Channel_2_speed 0.88
    positive Channel_3_speed 0.91
    positive Channel_4_speed 0.94
    positive Channel_5_speed 1.06
    positive Channel_6_speed 1.09
    positive Channel_7_speed 1.12
    positive Channel_8_speed 1.15
    
    comment === Random mode settings ===
    positive Random_min_speed 0.80
    positive Random_max_speed 1.20
    integer Random_seed 42
    
    comment === Audio settings ===
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
    mode = 1
    speed_deviation_factor = 0.05
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate
    mode = 1
    speed_deviation_factor = 0.15
    presetName$ = "Moderate"
elsif preset = 4
    # Wide
    mode = 1
    speed_deviation_factor = 0.30
    presetName$ = "Wide"
elsif preset = 5
    # Extreme
    mode = 1
    speed_deviation_factor = 0.50
    presetName$ = "Extreme"
elsif preset = 6
    # Accelerando
    mode = 2
    channel_1_speed = 0.70
    channel_2_speed = 0.80
    channel_3_speed = 0.90
    channel_4_speed = 1.00
    channel_5_speed = 1.10
    channel_6_speed = 1.20
    channel_7_speed = 1.25
    channel_8_speed = 1.30
    presetName$ = "Accelerando"
elsif preset = 7
    # Decelerando
    mode = 2
    channel_1_speed = 1.30
    channel_2_speed = 1.25
    channel_3_speed = 1.20
    channel_4_speed = 1.10
    channel_5_speed = 1.00
    channel_6_speed = 0.90
    channel_7_speed = 0.80
    channel_8_speed = 0.70
    presetName$ = "Decelerando"
else
    if mode = 1
        presetName$ = "Auto"
    elsif mode = 2
        presetName$ = "Manual"
    else
        presetName$ = "Random"
    endif
endif

# === Calculate speed factors ===
if mode = 1
    # Automatic mode - calculate from factor
    for i from 1 to 8
        speedFactor[i] = 1 - speed_deviation_factor + ((i-1) * (2 * speed_deviation_factor) / 7)
    endfor
elsif mode = 2
    # Manual mode - use provided values
    speedFactor[1] = channel_1_speed
    speedFactor[2] = channel_2_speed
    speedFactor[3] = channel_3_speed
    speedFactor[4] = channel_4_speed
    speedFactor[5] = channel_5_speed
    speedFactor[6] = channel_6_speed
    speedFactor[7] = channel_7_speed
    speedFactor[8] = channel_8_speed
else
    # Random mode
    for i from 1 to 8
        pseudoRand = ((random_seed * i * 137 + 97) mod 1000) / 1000
        speedFactor[i] = random_min_speed + (random_max_speed - random_min_speed) * pseudoRand
    endfor
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
original_sr = Get sampling frequency
original_dur = Get total duration

# === Info ===
writeInfoLine: "=== 8-Channel Speed Deviations ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Original duration: ", fixed$(original_dur, 2), "s"
appendInfoLine: ""

# === Convert to mono if needed ===
numberOfChannels = Get number of channels
if numberOfChannels > 1
    Convert to mono
    monoID = selected("Sound")
else
    selectObject: originalID
    Copy: "mono_work"
    monoID = selected("Sound")
endif

# === Process each channel ===
appendInfoLine: "Processing channels:"
for i from 1 to 8
    sf = speedFactor[i]
    
    selectObject: monoID
    Copy: "temp_ch" + string$(i)
    tempID = selected("Sound")
    
    # Calculate target duration
    targetDur = original_dur / sf
    durationRatio = targetDur / original_dur
    
    # Apply PSOLA
    Lengthen (overlap-add): min_pitch, max_pitch, durationRatio
    processedID = selected("Sound")
    
    # Resample
    if override_sampling_frequency
        Resample: target_sampling_frequency, 50
        removeObject: processedID
        processedID = selected("Sound")
    endif
    
    # Store
    channel[i] = processedID
    
    selectObject: channel[i]
    dur[i] = Get total duration
    
    # Cleanup temp
    removeObject: tempID
    
    # Calculate percentage
    pct = (sf - 1) * 100
    if pct >= 0
        appendInfoLine: "  Ch", i, ": ", fixed$(sf, 3), "x (+", fixed$(pct, 1), "%) -> ", fixed$(dur[i], 2), "s"
    else
        appendInfoLine: "  Ch", i, ": ", fixed$(sf, 3), "x (", fixed$(pct, 1), "%) -> ", fixed$(dur[i], 2), "s"
    endif
endfor

# === Combine all 8 channels ===
selectObject: channel[1], channel[2]
Combine to stereo
pair12 = selected("Sound")

selectObject: channel[3], channel[4]
Combine to stereo
pair34 = selected("Sound")

selectObject: channel[5], channel[6]
Combine to stereo
pair56 = selected("Sound")

selectObject: channel[7], channel[8]
Combine to stereo
pair78 = selected("Sound")

selectObject: pair12, pair34
Combine to stereo
quad1234 = selected("Sound")

selectObject: pair56, pair78
Combine to stereo
quad5678 = selected("Sound")

selectObject: quad1234, quad5678
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
Rename: originalName$ + "_8chSpeed_" + presetName$

# === Get final duration ===
selectObject: result
finalDur = Get total duration

# === Cleanup ===
removeObject: monoID
for i from 1 to 8
    removeObject: channel[i]
endfor
removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "8-Channel Speed Deviations: " + presetName$ + " | " + originalName$
    
    # Duration bars
    Select outer viewport: 0.5, 9.5, 0.8, 4.0
    Select inner viewport: 1.0, 9.0, 1.2, 3.7
    
    # Find max duration for scaling
    maxDur = dur[1]
    for i from 2 to 8
        if dur[i] > maxDur
            maxDur = dur[i]
        endif
    endfor
    
    Axes: 0, maxDur * 1.1, 0, 9
    
    # Background
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxDur * 1.1, 0, 9
    
    # Draw bars for each channel
    for i from 1 to 8
        yPos = 9 - i
        sf = speedFactor[i]
        
        # Color based on speed (blue=slow, red=fast)
        if sf < 1.0
            # Slower = blue tones
            intensity = (1.0 - sf) / 0.5
            if intensity > 1
                intensity = 1
            endif
            r = 0.3
            g = 0.4 + intensity * 0.2
            b = 0.7 + intensity * 0.2
        else
            # Faster = red/orange tones
            intensity = (sf - 1.0) / 0.5
            if intensity > 1
                intensity = 1
            endif
            r = 0.7 + intensity * 0.2
            g = 0.4 - intensity * 0.1
            b = 0.3
        endif
        
        Paint rectangle: "{" + fixed$(r, 2) + "," + fixed$(g, 2) + "," + fixed$(b, 2) + "}", 0, dur[i], yPos + 0.15, yPos + 0.75
        
        Colour: "Black"
        Draw rectangle: 0, dur[i], yPos + 0.15, yPos + 0.75
        
        Font size: 7
        Text: 0.1, "left", yPos + 0.45, "half", "Ch" + string$(i) + ": " + fixed$(sf, 2) + "x"
        Text: dur[i] + 0.1, "left", yPos + 0.45, "half", fixed$(dur[i], 1) + "s"
    endfor
    
    # Original duration marker
    Colour: "{0.5, 0.5, 0.5}"
    Dotted line
    Draw line: original_dur, 0.5, original_dur, 8.5
    Solid line
    Font size: 6
    Text: original_dur, "centre", 0.3, "half", "original"
    
    # Axes
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Duration (s)"
    
    # Legend
    Font size: 6
    Paint rectangle: "{0.4, 0.5, 0.8}", maxDur * 0.85, maxDur * 0.9, 8.3, 8.6
    Text: maxDur * 0.91, "left", 8.45, "half", "Slower"
    Paint rectangle: "{0.8, 0.4, 0.3}", maxDur * 0.85, maxDur * 0.9, 7.8, 8.1
    Text: maxDur * 0.91, "left", 7.95, "half", "Faster"
    
    # Output waveform
    Select outer viewport: 0.5, 9.5, 4.2, 6.0
    Select inner viewport: 1.0, 9.0, 4.4, 5.8
    selectObject: result
    Colour: "{0.4, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output (8ch)"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: 8-channel, ", fixed$(finalDur, 2), "s (longest channel)"

if play_result
    selectObject: result
    Play
endif

selectObject: result
