# ============================================================
# Praat AudioTools - 8_Channels_Time_Polyphony.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time Polyphony - 8 Channels
#   Creates 8 time-stretched copies using PSOLA and combines
#   them into an 8-channel output. Each voice drifts at a
#   different rate, creating rich polyphonic textures.
#
# Changelog v0.2:
#   - Refactored to use loop (removed 150+ lines of repetition)
#   - Removed unnecessary stereo/mono conversion
#   - Added visualization
#   - Added Custom preset option
# ============================================================

form Time Polyphony - 8 Channels
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Classic Polyphony"
        option: "Slow Motion"
        option: "Fast Chaos"
        option: "Rhythmic Pulse"
        option: "Subtle Variation"
        option: "Extreme Stretch"
        option: "Glitch Matrix"
        option: "Converging"
        option: "Diverging"
    
    comment === Time scales (1.0 = normal, >1 = slower, <1 = faster) ===
    real Time_scale_1 1.0
    real Time_scale_2 1.15
    real Time_scale_3 0.85
    real Time_scale_4 1.3
    real Time_scale_5 0.7
    real Time_scale_6 1.1
    real Time_scale_7 0.9
    real Time_scale_8 1.2
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Classic Polyphony
    time_scale_1 = 1.0
    time_scale_2 = 1.15
    time_scale_3 = 0.85
    time_scale_4 = 1.3
    time_scale_5 = 0.7
    time_scale_6 = 1.1
    time_scale_7 = 0.9
    time_scale_8 = 1.2
    presetName$ = "Classic"
elsif preset = 3
    # Slow Motion
    time_scale_1 = 1.5
    time_scale_2 = 1.7
    time_scale_3 = 1.3
    time_scale_4 = 1.6
    time_scale_5 = 1.4
    time_scale_6 = 1.8
    time_scale_7 = 1.2
    time_scale_8 = 1.9
    presetName$ = "SlowMo"
elsif preset = 4
    # Fast Chaos
    time_scale_1 = 0.5
    time_scale_2 = 0.6
    time_scale_3 = 0.4
    time_scale_4 = 0.7
    time_scale_5 = 0.3
    time_scale_6 = 0.8
    time_scale_7 = 0.25
    time_scale_8 = 0.9
    presetName$ = "FastChaos"
elsif preset = 5
    # Rhythmic Pulse
    time_scale_1 = 1.0
    time_scale_2 = 0.5
    time_scale_3 = 1.0
    time_scale_4 = 0.5
    time_scale_5 = 1.0
    time_scale_6 = 0.5
    time_scale_7 = 1.0
    time_scale_8 = 0.5
    presetName$ = "Rhythmic"
elsif preset = 6
    # Subtle Variation
    time_scale_1 = 1.0
    time_scale_2 = 1.05
    time_scale_3 = 0.98
    time_scale_4 = 1.02
    time_scale_5 = 0.95
    time_scale_6 = 1.03
    time_scale_7 = 0.97
    time_scale_8 = 1.01
    presetName$ = "Subtle"
elsif preset = 7
    # Extreme Stretch
    time_scale_1 = 3.0
    time_scale_2 = 2.5
    time_scale_3 = 3.5
    time_scale_4 = 2.0
    time_scale_5 = 4.0
    time_scale_6 = 2.2
    time_scale_7 = 3.8
    time_scale_8 = 2.7
    presetName$ = "Extreme"
elsif preset = 8
    # Glitch Matrix
    time_scale_1 = 0.15
    time_scale_2 = 0.8
    time_scale_3 = 0.3
    time_scale_4 = 1.5
    time_scale_5 = 0.2
    time_scale_6 = 1.2
    time_scale_7 = 0.4
    time_scale_8 = 2.0
    presetName$ = "Glitch"
elsif preset = 9
    # Converging (start spread, end together)
    time_scale_1 = 0.7
    time_scale_2 = 0.8
    time_scale_3 = 0.9
    time_scale_4 = 0.95
    time_scale_5 = 1.05
    time_scale_6 = 1.1
    time_scale_7 = 1.2
    time_scale_8 = 1.3
    presetName$ = "Converge"
elsif preset = 10
    # Diverging (start together, spread out)
    time_scale_1 = 1.0
    time_scale_2 = 1.0
    time_scale_3 = 1.0
    time_scale_4 = 1.0
    time_scale_5 = 1.0
    time_scale_6 = 1.0
    time_scale_7 = 1.0
    time_scale_8 = 1.0
    # Note: For true diverging, would need varying stretch over time
    presetName$ = "Diverge"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
originalDur = Get total duration
sr = Get sampling frequency

# === Store time scales in array ===
scale[1] = time_scale_1
scale[2] = time_scale_2
scale[3] = time_scale_3
scale[4] = time_scale_4
scale[5] = time_scale_5
scale[6] = time_scale_6
scale[7] = time_scale_7
scale[8] = time_scale_8

# === Info ===
writeInfoLine: "=== 8-Channel Time Polyphony ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Original duration: ", fixed$(originalDur, 2), "s"
appendInfoLine: ""
appendInfoLine: "Processing 8 voices with PSOLA..."

# === Create 8 time-stretched voices ===
for i from 1 to 8
    selectObject: originalID
    
    # Create manipulation object
    manip = To Manipulation: 0.01, 75, 600
    
    # Create duration tier
    durTier = Create DurationTier: "dur", 0, originalDur
    Add point: 0, scale[i]
    Add point: originalDur, scale[i]
    
    # Apply duration change
    selectObject: manip, durTier
    Replace duration tier
    
    # Resynthesize
    selectObject: manip
    voice[i] = Get resynthesis (overlap-add)
    
    # Cleanup manipulation objects
    removeObject: durTier, manip
    
    # Get resulting duration
    selectObject: voice[i]
    dur[i] = Get total duration
    
    appendInfoLine: "  Ch", i, ": ×", fixed$(scale[i], 2), " → ", fixed$(dur[i], 2), "s"
endfor

# === Combine all 8 voices into 8-channel output ===
# Combine in pairs, then combine pairs
selectObject: voice[1], voice[2]
Combine to stereo
pair12 = selected("Sound")

selectObject: voice[3], voice[4]
Combine to stereo
pair34 = selected("Sound")

selectObject: voice[5], voice[6]
Combine to stereo
pair56 = selected("Sound")

selectObject: voice[7], voice[8]
Combine to stereo
pair78 = selected("Sound")

# Combine stereo pairs into 4-channel, then 8-channel
selectObject: pair12, pair34
Combine to stereo
quad1234 = selected("Sound")

selectObject: pair56, pair78
Combine to stereo
quad5678 = selected("Sound")

selectObject: quad1234, quad5678
Combine to stereo
result = selected("Sound")
Scale peak: 0.99
Rename: originalName$ + "_timePoly_" + presetName$

# === Cleanup ===
for i from 1 to 8
    removeObject: voice[i]
endfor
removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

# === Get final duration ===
selectObject: result
finalDur = Get total duration

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "8-Channel Time Polyphony: " + presetName$ + " | " + originalName$
    
    # Channel duration diagram
    Select outer viewport: 0.5, 9.5, 0.8, 4.5
    Select inner viewport: 1.0, 9.0, 1.2, 4.2
    
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
    
    # Draw each channel as bar
    for i from 1 to 8
        yPos = 9 - i
        
        # Color based on speed (blue=slow, red=fast)
        if scale[i] >= 1.0
            # Slower = blue tones
            intensity = (scale[i] - 1.0) / 3.0
            if intensity > 1
                intensity = 1
            endif
            r = 0.4 - intensity * 0.2
            g = 0.5 - intensity * 0.2
            b = 0.7 + intensity * 0.2
        else
            # Faster = red/orange tones
            intensity = (1.0 - scale[i]) / 0.8
            if intensity > 1
                intensity = 1
            endif
            r = 0.7 + intensity * 0.2
            g = 0.5 - intensity * 0.2
            b = 0.4 - intensity * 0.2
        endif
        
        Paint rectangle: "{" + fixed$(r, 2) + "," + fixed$(g, 2) + "," + fixed$(b, 2) + "}", 0, dur[i], yPos + 0.15, yPos + 0.75
        
        Colour: "Black"
        Line width: 1
        Draw rectangle: 0, dur[i], yPos + 0.15, yPos + 0.75
        
        Font size: 7
        Text: 0.1, "left", yPos + 0.45, "half", "Ch" + string$(i) + ": ×" + fixed$(scale[i], 2)
        Text: dur[i] + 0.1, "left", yPos + 0.45, "half", fixed$(dur[i], 1) + "s"
    endfor
    
    # Original duration marker
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    Dotted line
    Draw line: originalDur, 0.5, originalDur, 8.5
    Solid line
    Line width: 1
    Font size: 6
    Text: originalDur, "centre", 0.3, "half", "original"
    
    # Axes
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Duration (s)"
    
    # Legend
    Font size: 6
    Paint rectangle: "{0.5, 0.6, 0.8}", 7.5, 7.8, 8.5, 8.7
    Text: 7.9, "left", 8.6, "half", "= Slower"
    Paint rectangle: "{0.8, 0.5, 0.4}", 7.5, 7.8, 8.0, 8.2
    Text: 7.9, "left", 8.1, "half", "= Faster"
    
    # Output waveform
    Select outer viewport: 0.5, 9.5, 4.7, 6.5
    Select inner viewport: 1.0, 9.0, 4.9, 6.3
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
appendInfoLine: "Output: 8-channel, ", fixed$(finalDur, 2), "s"

if play_result
    selectObject: result
    Play
endif

selectObject: result