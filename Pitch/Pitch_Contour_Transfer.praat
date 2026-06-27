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
#   Pitch Contour Transfer - imposes the pitch CONTOUR (the melodic
#   shape) of Sound A onto Sound B. A's contour is time-warped to B's
#   duration, expressed as semitone deviations from A's mean, then
#   applied to B. Register choice keeps B's own pitch level or moves it
#   to A's; Blend strength interpolates between B's own contour and A's.
#
# Changelog v0.4:
#   - TRUE contour transfer (was a mean-level match): A's time-warped
#     contour shape is now transferred, not just its average pitch
#   - Register option (keep B's / match A's); blend now shape-amount
#   - Synthesis-range clamp (no longer truncates at the analysis range)
#   - Visualization shows A's shape, B original and result; fixed legend
#   - Standard header
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
xmin_a = Get start time

selectObject: sound_b
name_b$ = selected$("Sound")
dur_b = Get total duration
xmin_b = Get start time

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
    optionmenu Register 1
        option Keep B's register (B's voice, A's tune)
        option Match A's register (move B to A's level)
    real Blend_strength 1.0
    comment (0 = keep B's own contour, 1 = full A contour)
    
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

# === Transfer Setup ===
if register = 2
    anchor = mean_a
    regName$ = "match A"
else
    anchor = mean_b
    regName$ = "keep B"
endif

# Generous synthesis clamp (covers both ranges, not just B's analysis
# range) so a transferred contour is never truncated at resynthesis.
synthFloor = min(pitch_floor_A, pitch_floor_B)
synthCeil  = max(pitch_ceiling_A, pitch_ceiling_B)

appendInfoLine: "Transfer: ", regName$, " register, blend ", fixed$(blend_strength, 2)
appendInfoLine: "Synthesis range: ", round(synthFloor), "-", round(synthCeil), " Hz"
appendInfoLine: ""

# === Create Manipulation ===
selectObject: sound_b
manipulation = To Manipulation: analysis_time_step, pitch_floor_B, pitch_ceiling_B

selectObject: manipulation
pitch_tier = Extract pitch tier

selectObject: pitch_tier
Remove points between: 0, 10000

# === Build Pitch Tier from A's time-warped contour ===
appendInfoLine: "Transferring contour..."
n_points = 0

maxVizPoints  = min(n_frames_b, 500)
vizTimes#     = zero#(maxVizPoints)
vizOrigPitch# = zero#(maxVizPoints)
vizNewPitch#  = zero#(maxVizPoints)
vizAShape#    = zero#(maxVizPoints)
vizFilled#    = zero#(maxVizPoints)
vizStep = ceiling(n_frames_b / maxVizPoints)

# Carry A's deviation across its unvoiced gaps (start at 0 = A's mean)
prev_dev_a = 0

for i from 1 to n_frames_b
    selectObject: pitch_b
    t = Get time from frame number: i
    f0_b = Get value at time: t, "Hertz", "Linear"

    if f0_b <> undefined and f0_b > 0
        # B's own contour as a semitone deviation from B's mean
        dev_b = 12 * log2(f0_b / mean_b)

        # Map B's time to the same PHASE in A, read A's contour there
        phase = (t - xmin_b) / dur_b
        t_a = xmin_a + phase * dur_a
        selectObject: pitch_a
        f0_a = Get value at time: t_a, "Hertz", "Linear"
        if f0_a <> undefined and f0_a > 0
            dev_a = 12 * log2(f0_a / mean_a)
            prev_dev_a = dev_a
        else
            dev_a = prev_dev_a
        endif

        # Blend A's shape with B's own, anchored to the chosen register
        final_dev = blend_strength * dev_a + (1 - blend_strength) * dev_b
        target_f0 = anchor * 2 ^ (final_dev / 12)

        if target_f0 < synthFloor
            target_f0 = synthFloor
        elsif target_f0 > synthCeil
            target_f0 = synthCeil
        endif

        selectObject: pitch_tier
        Add point: t, target_f0
        n_points = n_points + 1

        # Store B original, A's shape on the register, and the result
        vizIdx = ceiling(i / vizStep)
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            if vizFilled#[vizIdx] = 0
                vizTimes#[vizIdx]     = t
                vizOrigPitch#[vizIdx] = f0_b
                vizAShape#[vizIdx]    = anchor * 2 ^ (dev_a / 12)
                vizNewPitch#[vizIdx]  = target_f0
                vizFilled#[vizIdx]    = 1
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

appendInfoLine: "Result mean: ", fixed$(mean_b, 1), " Hz → ", fixed$(mean_result, 1), " Hz"
if register = 2
    appendInfoLine: "Register target (A): ", fixed$(mean_a, 1), " Hz"
else
    appendInfoLine: "Register kept (B): ", fixed$(mean_b, 1), " Hz"
endif
appendInfoLine: ""

# === Visualization ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Pitch Contour Transfer##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", name_a$ + " → " + name_b$ + " | " + regName$ + " | blend " + fixed$(blend_strength, 2)
    
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
    
    # Find pitch range across B original, A's shape, and result
    minP = mean_b
    maxP = mean_b
    for vp from 1 to maxVizPoints
        if vizFilled#[vp] = 1
            if vizOrigPitch#[vp] < minP
                minP = vizOrigPitch#[vp]
            endif
            if vizOrigPitch#[vp] > maxP
                maxP = vizOrigPitch#[vp]
            endif
            if vizAShape#[vp] < minP
                minP = vizAShape#[vp]
            endif
            if vizAShape#[vp] > maxP
                maxP = vizAShape#[vp]
            endif
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
    
    # B's mean reference line
    Colour: "{0.6, 0.6, 0.6}"
    Dotted line
    Draw line: 0, mean_b, dur_b, mean_b
    Solid line
    
    # Draw original B pitch (grey)
    Colour: "{0.7, 0.7, 0.7}"
    for vp from 2 to maxVizPoints
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
            Draw line: vizTimes#[vp - 1], vizOrigPitch#[vp - 1], vizTimes#[vp], vizOrigPitch#[vp]
        endif
    endfor
    
    # Draw A's contour shape on the register (green dashed = target shape)
    Colour: "{0.4, 0.65, 0.45}"
    Dotted line
    for vp from 2 to maxVizPoints
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
            Draw line: vizTimes#[vp - 1], vizAShape#[vp - 1], vizTimes#[vp], vizAShape#[vp]
        endif
    endfor
    Solid line
    
    # Draw result (blue, bold)
    Colour: "{0.3, 0.45, 0.75}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
            Draw line: vizTimes#[vp - 1], vizNewPitch#[vp - 1], vizTimes#[vp], vizNewPitch#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Legend (in the panel's own Hz/time coordinates, near the top)
    legY = maxP + pMargin * 0.5
    legX = dur_b * 0.03
    Font size: 6
    Colour: "{0.7, 0.7, 0.7}"
    Text: legX, "left", legY, "half", "B original"
    Colour: "{0.4, 0.65, 0.45}"
    Text: legX + dur_b * 0.18, "left", legY, "half", "A contour"
    Colour: "{0.3, 0.45, 0.75}"
    Text: legX + dur_b * 0.36, "left", legY, "half", "result"
    
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
    Text: 0.5, "centre", 0.5, "half", "Contour: " + name_a$ + " → " + name_b$ + " | Register: " + regName$ + " | Blend: " + fixed$(blend_strength, 2)
    
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