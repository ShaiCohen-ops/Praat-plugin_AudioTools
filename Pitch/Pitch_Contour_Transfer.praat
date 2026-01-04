# ============================================================
# Praat AudioTools - Pitch_Contour_Transfer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Contour Transfer - matches the mean pitch of Sound B
#   to Sound A by calculating the pitch difference and applying
#   a global shift. Blend strength controls partial matching.
#
# Changelog v0.3:
#   - Modern syntax throughout
#   - Added visualization
#   - Better description
# ============================================================

# === Check Input ===
numSelected = numberOfSelected("Sound")
if numSelected <> 2
    exitScript: "Please select exactly 2 Sound objects (A=source, B=target)"
endif

sound_a = selected("Sound", 1)
sound_b = selected("Sound", 2)

selectObject: sound_a
name_a$ = selected$("Sound")
dur_a = Get total duration

selectObject: sound_b
name_b$ = selected$("Sound")
dur_b = Get total duration

# === Form ===
form Pitch Contour Transfer
    comment Select 2 Sounds: A (source style), B (target to shift)
    
    comment === Analysis ===
    real Analysis_time_step 0.01
    
    comment === Pitch Range (Sound A) ===
    real Pitch_floor_A 75
    real Pitch_ceiling_A 300
    
    comment === Pitch Range (Sound B) ===
    real Pitch_floor_B 50
    real Pitch_ceiling_B 300
    
    comment === Transfer ===
    real Blend_strength 1.0
    comment (0 = no change, 1 = full match)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Info ===
writeInfoLine: "=== Pitch Contour Transfer ==="
appendInfoLine: "Source (A): ", name_a$, " (", fixed$(dur_a, 2), " s)"
appendInfoLine: "Target (B): ", name_b$, " (", fixed$(dur_b, 2), " s)"
appendInfoLine: "Blend: ", blend_strength
appendInfoLine: ""

# === Analyze Sound A ===
appendInfoLine: "Analyzing Sound A..."
selectObject: sound_a
pitch_a = To Pitch: analysis_time_step, pitch_floor_A, pitch_ceiling_A

selectObject: pitch_a
mean_a = Get mean: 0, 0, "Hertz"
n_frames_a = Get number of frames

appendInfoLine: "  Mean pitch: ", fixed$(mean_a, 1), " Hz"

# === Analyze Sound B ===
appendInfoLine: "Analyzing Sound B..."
selectObject: sound_b
pitch_b = To Pitch: analysis_time_step, pitch_floor_B, pitch_ceiling_B

selectObject: pitch_b
n_frames_b = Get number of frames
mean_b = Get mean: 0, 0, "Hertz"
n_voiced_b = Count voiced frames
voiced_percent = (n_voiced_b / n_frames_b) * 100

appendInfoLine: "  Mean pitch: ", fixed$(mean_b, 1), " Hz"
appendInfoLine: "  Voiced: ", fixed$(voiced_percent, 1), "%"
appendInfoLine: ""

# === Calculate Shift ===
mean_shift = (mean_a - mean_b) * blend_strength
if mean_b > 0
    semitones = 12 * log2((mean_b + mean_shift) / mean_b)
else
    semitones = 0
endif

appendInfoLine: "Shift: ", fixed$(mean_shift, 1), " Hz (", fixed$(semitones, 2), " semitones)"
appendInfoLine: ""

# === Create Manipulation ===
selectObject: sound_b
manipulation = To Manipulation: analysis_time_step, pitch_floor_B, pitch_ceiling_B

selectObject: manipulation
pitch_tier = Extract pitch tier

selectObject: pitch_tier
Remove points between: 0, 10000

# === Build New Pitch Tier ===
appendInfoLine: "Building shifted pitch tier..."
n_points = 0

# Store original and shifted for visualization
maxVizPoints = min(n_frames_b, 500)
vizTimes# = zero#(maxVizPoints)
vizOrigPitch# = zero#(maxVizPoints)
vizNewPitch# = zero#(maxVizPoints)
vizStep = ceiling(n_frames_b / maxVizPoints)

for i from 1 to n_frames_b
    selectObject: pitch_b
    t = Get time from frame number: i
    f0_b = Get value at time: t, "Hertz", "Linear"
    
    if f0_b <> undefined
        target_f0 = f0_b + mean_shift
        
        # Clamp to range
        if target_f0 < pitch_floor_B
            target_f0 = pitch_floor_B
        elsif target_f0 > pitch_ceiling_B
            target_f0 = pitch_ceiling_B
        endif
        
        selectObject: pitch_tier
        Add point: t, target_f0
        n_points = n_points + 1
        
        # Store for visualization
        vizIdx = ceiling(i / vizStep)
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            if vizTimes#[vizIdx] = 0
                vizTimes#[vizIdx] = t
                vizOrigPitch#[vizIdx] = f0_b
                vizNewPitch#[vizIdx] = target_f0
            endif
        endif
    endif
endfor

appendInfoLine: "Points: ", n_points, " / ", n_frames_b
appendInfoLine: ""

# === Resynthesize ===
appendInfoLine: "Resynthesizing..."
selectObject: manipulation, pitch_tier
Replace pitch tier

selectObject: manipulation
sound_result = Get resynthesis (overlap-add)
Rename: name_b$ + "_matched"

selectObject: sound_result
Scale peak: 0.95

# === Verify Result ===
selectObject: sound_result
pitch_result = To Pitch: analysis_time_step, pitch_floor_B, pitch_ceiling_B
mean_result = Get mean: 0, 0, "Hertz"

appendInfoLine: "Result: ", fixed$(mean_b, 1), " Hz → ", fixed$(mean_result, 1), " Hz"
appendInfoLine: "Target was: ", fixed$(mean_a, 1), " Hz"
appendInfoLine: ""

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Pitch Contour Transfer: " + name_a$ + " → " + name_b$
    
    # Sound A waveform
    Select outer viewport: 0, 4, 0.6, 1.5
    Select inner viewport: 0.6, 3.8, 0.7, 1.4
    selectObject: sound_a
    Colour: "{0.5, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "A (src)"
    
    # Sound B waveform (original)
    Select outer viewport: 4, 8, 0.6, 1.5
    Select inner viewport: 4.4, 7.6, 0.7, 1.4
    selectObject: sound_b
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "B (orig)"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: sound_result
    Colour: "{0.5, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Pitch comparison
    Select outer viewport: 0, 8, 2.7, 4.3
    Select inner viewport: 0.6, 7.6, 2.9, 4.2
    
    # Find pitch range
    minP = mean_a
    maxP = mean_a
    for vp from 1 to maxVizPoints
        if vizOrigPitch#[vp] > 0
            if vizOrigPitch#[vp] < minP
                minP = vizOrigPitch#[vp]
            endif
            if vizOrigPitch#[vp] > maxP
                maxP = vizOrigPitch#[vp]
            endif
        endif
        if vizNewPitch#[vp] > 0
            if vizNewPitch#[vp] < minP
                minP = vizNewPitch#[vp]
            endif
            if vizNewPitch#[vp] > maxP
                maxP = vizNewPitch#[vp]
            endif
        endif
    endfor
    
    pMargin = (maxP - minP) * 0.15
    if pMargin < 10
        pMargin = 10
    endif
    
    Axes: 0, dur_b, minP - pMargin, maxP + pMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, dur_b, minP - pMargin, maxP + pMargin
    
    # Draw mean lines
    Colour: "{0.5, 0.7, 0.5}"
    Dotted line
    Draw line: 0, mean_a, dur_b, mean_a
    Font size: 6
    Text: dur_b * 0.02, "left", mean_a + pMargin * 0.3, "half", "A mean"
    
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: 0, mean_b, dur_b, mean_b
    Text: dur_b * 0.02, "left", mean_b - pMargin * 0.3, "half", "B orig"
    
    Solid line
    
    # Draw original B pitch
    Colour: "{0.7, 0.7, 0.7}"
    for vp from 2 to maxVizPoints
        if vizOrigPitch#[vp] > 0 and vizOrigPitch#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizOrigPitch#[vp - 1], vizTimes#[vp], vizOrigPitch#[vp]
        endif
    endfor
    
    # Draw shifted pitch
    Colour: "{0.4, 0.5, 0.7}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizNewPitch#[vp] > 0 and vizNewPitch#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizNewPitch#[vp - 1], vizTimes#[vp], vizNewPitch#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    Colour: "{0.7, 0.7, 0.7}"
    Text: 0.85, "left", 1.05, "half", "B original"
    Colour: "{0.4, 0.5, 0.7}"
    Text: 0.92, "left", 1.05, "half", "B shifted"
    
    # Stats bar
    Select outer viewport: 0, 8, 4.5, 5.2
    Select inner viewport: 0.6, 7.6, 4.6, 5.1
    
    Axes: 0, 3, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 3, 0, 1
    
    # Mean A
    Paint rectangle: "{0.5, 0.7, 0.5}", 0.1, 0.9, 0.1, 0.9
    Colour: "Black"
    Font size: 6
    Text: 0.5, "centre", 0.5, "half", fixed$(mean_a, 0) + " Hz"
    Text: 0.5, "centre", -0.3, "half", "A mean"
    
    # Mean B original
    Paint rectangle: "{0.6, 0.6, 0.6}", 1.1, 1.9, 0.1, 0.9
    Text: 1.5, "centre", 0.5, "half", fixed$(mean_b, 0) + " Hz"
    Text: 1.5, "centre", -0.3, "half", "B orig"
    
    # Mean result
    Paint rectangle: "{0.5, 0.6, 0.8}", 2.1, 2.9, 0.1, 0.9
    Text: 2.5, "centre", 0.5, "half", fixed$(mean_result, 0) + " Hz"
    Text: 2.5, "centre", -0.3, "half", "Result"
    
    # Arrow showing shift
    Colour: "{0.4, 0.4, 0.4}"
    Draw arrow: 1.5, 1.1, 2.5, 1.1
    
    Colour: "Black"
    Draw inner box
    
    # Info
    Select outer viewport: 0, 8, 5.3, 5.6
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Shift: " + fixed$(mean_shift, 1) + " Hz (" + fixed$(semitones, 2) + " st) | Blend: " + fixed$(blend_strength, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: manipulation, pitch_tier, pitch_a, pitch_b, pitch_result

# === Final Info ===
selectObject: sound_result

appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: sound_result
    Play
endif

selectObject: sound_result