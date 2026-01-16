# ============================================================
# Praat AudioTools - 8-Channel_Canon.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Canon Generator - creates a musical canon effect
#   with 8 pitch-shifted voices on separate channels.
#
# Changelog v0.2:
#   - Added time delays for true canon effect
#   - Changed from Hz to semitones (more musical)
#   - Fixed cleanup
#   - Added visualization
#   - Refactored with loops
# ============================================================

form 8-Channel Canon Settings
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Classic Canon (unison, staggered)"
        option: "Cluster (1-3 semitones)"
        option: "Wide Spread (4-10 semitones)"
        option: "Microtonal (quarter-tones)"
        option: "Symmetrical (mirror intervals)"
        option: "Octave Stack"
        option: "Major Scale"
        option: "Chromatic"
        option: "Fifths Tower"
    
    comment === Pitch shifts (semitones) ===
    real Semitones_1 0
    real Semitones_2 2
    real Semitones_3 4
    real Semitones_4 5
    real Semitones_5 7
    real Semitones_6 9
    real Semitones_7 11
    real Semitones_8 12
    
    comment === Canon delays (seconds) ===
    real Delay_1 0.0
    real Delay_2 0.2
    real Delay_3 0.4
    real Delay_4 0.6
    real Delay_5 0.8
    real Delay_6 1.0
    real Delay_7 1.2
    real Delay_8 1.4
    
    comment === Settings ===
    positive Resample_frequency 44100
    real Fade_time 0.01
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Classic Canon (unison, staggered)
    semitones_1 = 0
    semitones_2 = 0
    semitones_3 = 0
    semitones_4 = 0
    semitones_5 = 0
    semitones_6 = 0
    semitones_7 = 0
    semitones_8 = 0
    delay_1 = 0.0
    delay_2 = 0.3
    delay_3 = 0.6
    delay_4 = 0.9
    delay_5 = 1.2
    delay_6 = 1.5
    delay_7 = 1.8
    delay_8 = 2.1
    presetName$ = "Classic"
elsif preset = 3
    # Cluster (1-3 semitones)
    semitones_1 = 0
    semitones_2 = 1
    semitones_3 = 2
    semitones_4 = 3
    semitones_5 = -1
    semitones_6 = -2
    semitones_7 = -3
    semitones_8 = -4
    delay_1 = 0.0
    delay_2 = 0.15
    delay_3 = 0.3
    delay_4 = 0.45
    delay_5 = 0.6
    delay_6 = 0.75
    delay_7 = 0.9
    delay_8 = 1.05
    presetName$ = "Cluster"
elsif preset = 4
    # Wide Spread
    semitones_1 = 0
    semitones_2 = 4
    semitones_3 = 7
    semitones_4 = 10
    semitones_5 = -3
    semitones_6 = -7
    semitones_7 = -10
    semitones_8 = -14
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    delay_5 = 1.0
    delay_6 = 1.25
    delay_7 = 1.5
    delay_8 = 1.75
    presetName$ = "Wide"
elsif preset = 5
    # Microtonal (quarter-tones = 0.5 semitones)
    semitones_1 = 0
    semitones_2 = 0.5
    semitones_3 = 1.0
    semitones_4 = 1.5
    semitones_5 = 2.0
    semitones_6 = -0.5
    semitones_7 = -1.0
    semitones_8 = -1.5
    delay_1 = 0.0
    delay_2 = 0.1
    delay_3 = 0.2
    delay_4 = 0.3
    delay_5 = 0.4
    delay_6 = 0.5
    delay_7 = 0.6
    delay_8 = 0.7
    presetName$ = "Microtonal"
elsif preset = 6
    # Symmetrical (mirror intervals)
    semitones_1 = 6
    semitones_2 = 4
    semitones_3 = 2
    semitones_4 = 0
    semitones_5 = 0
    semitones_6 = -2
    semitones_7 = -4
    semitones_8 = -6
    delay_1 = 0.0
    delay_2 = 0.2
    delay_3 = 0.4
    delay_4 = 0.6
    delay_5 = 0.6
    delay_6 = 0.8
    delay_7 = 1.0
    delay_8 = 1.2
    presetName$ = "Symmetrical"
elsif preset = 7
    # Octave Stack
    semitones_1 = 0
    semitones_2 = 12
    semitones_3 = -12
    semitones_4 = 24
    semitones_5 = -24
    semitones_6 = 12
    semitones_7 = -12
    semitones_8 = 0
    delay_1 = 0.0
    delay_2 = 0.2
    delay_3 = 0.4
    delay_4 = 0.6
    delay_5 = 0.8
    delay_6 = 1.0
    delay_7 = 1.2
    delay_8 = 1.4
    presetName$ = "Octaves"
elsif preset = 8
    # Major Scale
    semitones_1 = 0
    semitones_2 = 2
    semitones_3 = 4
    semitones_4 = 5
    semitones_5 = 7
    semitones_6 = 9
    semitones_7 = 11
    semitones_8 = 12
    delay_1 = 0.0
    delay_2 = 0.15
    delay_3 = 0.3
    delay_4 = 0.45
    delay_5 = 0.6
    delay_6 = 0.75
    delay_7 = 0.9
    delay_8 = 1.05
    presetName$ = "MajorScale"
elsif preset = 9
    # Chromatic
    semitones_1 = 0
    semitones_2 = 1
    semitones_3 = 2
    semitones_4 = 3
    semitones_5 = 4
    semitones_6 = 5
    semitones_7 = 6
    semitones_8 = 7
    delay_1 = 0.0
    delay_2 = 0.1
    delay_3 = 0.2
    delay_4 = 0.3
    delay_5 = 0.4
    delay_6 = 0.5
    delay_7 = 0.6
    delay_8 = 0.7
    presetName$ = "Chromatic"
elsif preset = 10
    # Fifths Tower (stacked perfect fifths)
    semitones_1 = 0
    semitones_2 = 7
    semitones_3 = 14
    semitones_4 = 21
    semitones_5 = -7
    semitones_6 = -14
    semitones_7 = -21
    semitones_8 = -28
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    delay_5 = 1.0
    delay_6 = 1.25
    delay_7 = 1.5
    delay_8 = 1.75
    presetName$ = "Fifths"
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

# === Create Base Mono ===
selectObject: originalID
Copy: "base_work"
baseWorkID = selected("Sound")
Convert to mono
monoID = selected("Sound")
Resample: resample_frequency, 50
Rename: "base_resampled"
baseDur = Get total duration

removeObject: baseWorkID, monoID

# === Store parameters in arrays ===
semi[1] = semitones_1
semi[2] = semitones_2
semi[3] = semitones_3
semi[4] = semitones_4
semi[5] = semitones_5
semi[6] = semitones_6
semi[7] = semitones_7
semi[8] = semitones_8

delay[1] = delay_1
delay[2] = delay_2
delay[3] = delay_3
delay[4] = delay_4
delay[5] = delay_5
delay[6] = delay_6
delay[7] = delay_7
delay[8] = delay_8

# === Create 8 pitched versions ===
for i from 1 to 8
    select Sound base_resampled
    Copy: "v" + string$(i) + "_work"
    vWork = selected("Sound")
    
    # Calculate shift rate from semitones
    ratio = 2 ^ (semi[i] / 12)
    shiftRate = resample_frequency * ratio
    
    Override sampling frequency: shiftRate
    Resample: resample_frequency, 50
    Rename: "voice_" + string$(i)
    voice[i] = selected("Sound")
    dur[i] = Get total duration
    
    if fade_time > 0
        Fade in: 0, 0, fade_time, "yes"
        Fade out: 0, dur[i], -fade_time, "yes"
    endif
    
    removeObject: vWork
endfor

# === Calculate output duration ===
maxEnd = 0
for i from 1 to 8
    thisEnd = delay[i] + dur[i]
    if thisEnd > maxEnd
        maxEnd = thisEnd
    endif
endfor
outputDur = maxEnd + 0.05

# === Create 8 output channel buffers ===
for i from 1 to 8
    Create Sound from formula: "ch" + string$(i), 1, 0, outputDur, resample_frequency, "0"
    ch[i] = selected("Sound")
endfor

# === Place each voice in its channel with delay ===
for i from 1 to 8
    selectObject: ch[i]
    d = delay[i]
    voiceDur = dur[i]
    
    # Build formula string with voice name
    voiceName$ = "voice_" + string$(i)
    Formula (part): d, d + voiceDur, 1, 1, "Sound_'voiceName$'(x - 'd')"
endfor

# === Combine all 8 channels ===
selectObject: ch[1], ch[2]
Combine to stereo
pair12 = selected("Sound")

selectObject: ch[3], ch[4]
Combine to stereo
pair34 = selected("Sound")

selectObject: ch[5], ch[6]
Combine to stereo
pair56 = selected("Sound")

selectObject: ch[7], ch[8]
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
Rename: originalName$ + "_canon8ch_" + presetName$

# === Info ===
writeInfoLine: "=== 8-Channel Canon ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
for i from 1 to 8
    if semi[i] >= 0
        appendInfoLine: "Ch", i, ": +", fixed$(semi[i], 1), " st, delay ", fixed$(delay[i], 2), "s"
    else
        appendInfoLine: "Ch", i, ": ", fixed$(semi[i], 1), " st, delay ", fixed$(delay[i], 2), "s"
    endif
endfor

# === Cleanup ===
select Sound base_resampled
Remove

for i from 1 to 8
    removeObject: voice[i], ch[i]
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
    Text: 0.5, "centre", 0.5, "half", "8-Channel Canon: " + presetName$ + " | " + originalName$
    
    # Canon diagram
    Select outer viewport: 0.5, 9.5, 0.8, 5.0
    Select inner viewport: 1.0, 9.0, 1.2, 4.7
    
    Axes: 0, outputDur * 1.05, 0, 9
    
    # Background
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, outputDur * 1.05, 0, 9
    
    # Draw each channel
    for i from 1 to 8
        yPos = 9 - i
        
        # Color based on pitch (blue=low, red=high)
        if semi[i] >= 0
            intensity = semi[i] / 24
            if intensity > 1
                intensity = 1
            endif
            r = 0.4 + intensity * 0.4
            g = 0.5 - intensity * 0.2
            b = 0.7 - intensity * 0.3
        else
            intensity = -semi[i] / 24
            if intensity > 1
                intensity = 1
            endif
            r = 0.4 - intensity * 0.1
            g = 0.5 + intensity * 0.2
            b = 0.7 + intensity * 0.2
        endif
        
        Paint rectangle: "{" + fixed$(r, 2) + "," + fixed$(g, 2) + "," + fixed$(b, 2) + "}", delay[i], delay[i] + dur[i], yPos + 0.1, yPos + 0.8
        
        Colour: "Black"
        Draw rectangle: delay[i], delay[i] + dur[i], yPos + 0.1, yPos + 0.8
        
        Font size: 7
        if semi[i] >= 0
            Text: delay[i] + 0.05, "left", yPos + 0.45, "half", "Ch" + string$(i) + ": +" + fixed$(semi[i], 0) + " st"
        else
            Text: delay[i] + 0.05, "left", yPos + 0.45, "half", "Ch" + string$(i) + ": " + fixed$(semi[i], 0) + " st"
        endif
    endfor
    
    # Axes
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    
    # Output waveform
    Select outer viewport: 0.5, 9.5, 5.2, 6.5
    Select inner viewport: 1.0, 9.0, 5.4, 6.3
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
appendInfoLine: "Output: 8-channel, ", fixed$(outputDur, 2), "s"

if play_result
    selectObject: result
    Play
endif

selectObject: result