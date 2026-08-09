# ============================================================
# Praat AudioTools - Pitch_Contour_Transfer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
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
# Changelog v0.5:
#   - Separates pitch-analysis limits from synthesis safety limits.
#     Transferred contours are no longer clipped to the A/B analysis ceilings.
#   - Validates time step, pitch ranges, blend range, and voiced-pitch presence.
#   - Analysis uses zero-based mono references for both A and B, so arbitrary
#     source xmin/xmax values are handled consistently.
#   - Preserves B's original channel count: one shared transferred PitchTier is
#     applied independently to every channel, then channels are rebuilt.
#   - Result verification uses a wider pitch-analysis range.
#   - Peak protection is attenuation-only; quiet outputs are not normalized up.
#   - Keeps the established AudioTools visualization design; only coordinate
#     bugs are corrected (relative B times and centred info text).
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
xmin_a = Get start time
xmax_a = Get end time
dur_a = xmax_a - xmin_a
sr_a = Get sampling frequency
channels_a = Get number of channels

selectObject: sound_b
name_b$ = selected$("Sound")
xmin_b = Get start time
xmax_b = Get end time
dur_b = xmax_b - xmin_b
sr_b = Get sampling frequency
channels_b = Get number of channels

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

# === Validation ===
if analysis_time_step <= 0
    exitScript: "Analysis_time_step must be greater than zero."
endif
if pitch_floor_A <= 0 or pitch_ceiling_A <= pitch_floor_A
    exitScript: "Sound A pitch range is invalid."
endif
if pitch_floor_B <= 0 or pitch_ceiling_B <= pitch_floor_B
    exitScript: "Sound B pitch range is invalid."
endif
if pitch_ceiling_A >= 0.45 * sr_a
    exitScript: "Pitch_ceiling_A must be below 45% of Sound A's sampling frequency."
endif
if pitch_ceiling_B >= 0.45 * sr_b
    exitScript: "Pitch_ceiling_B must be below 45% of Sound B's sampling frequency."
endif
if blend_strength < 0 or blend_strength > 1
    exitScript: "Blend_strength must be between 0 and 1."
endif
if dur_a <= 0 or dur_b <= 0
    exitScript: "Both Sounds must have positive duration."
endif

# === Prepare zero-based mono analysis references ===
selectObject: sound_a
if channels_a > 1
    a_mono_tmp = Convert to mono
    selectObject: a_mono_tmp
    a_mono = Extract part: xmin_a, xmax_a, "rectangular", 1, "no"
    Rename: "PCT_A_analysis"
    removeObject: a_mono_tmp
else
    a_mono = Extract part: xmin_a, xmax_a, "rectangular", 1, "no"
    Rename: "PCT_A_analysis"
endif

selectObject: sound_b
if channels_b > 1
    b_mono_tmp = Convert to mono
    selectObject: b_mono_tmp
    b_mono = Extract part: xmin_b, xmax_b, "rectangular", 1, "no"
    Rename: "PCT_B_analysis"
    removeObject: b_mono_tmp
else
    b_mono = Extract part: xmin_b, xmax_b, "rectangular", 1, "no"
    Rename: "PCT_B_analysis"
endif

# === Info ===
writeInfoLine: "=== Pitch Contour Transfer v0.5 ==="
appendInfoLine: "Source (A): ", name_a$, " (", fixed$(dur_a, 2), " s)"
appendInfoLine: "Target (B): ", name_b$, " (", fixed$(dur_b, 2), " s; ", channels_b, " ch)"
appendInfoLine: "Blend: ", blend_strength
appendInfoLine: ""

# === Analyze Sound A ===
appendInfoLine: "Analyzing Sound A..."
selectObject: a_mono
pitch_a = To Pitch: analysis_time_step, pitch_floor_A, pitch_ceiling_A

selectObject: pitch_a
mean_a = Get mean: 0, 0, "Hertz"
n_frames_a = Get number of frames
n_voiced_a = Count voiced frames

if mean_a = undefined or mean_a <= 0 or n_voiced_a < 1
    removeObject: pitch_a, a_mono, b_mono
    exitScript: "Sound A has no usable voiced pitch in the selected analysis range."
endif

appendInfoLine: "  Mean pitch: ", fixed$(mean_a, 1), " Hz"
appendInfoLine: "  Voiced frames: ", n_voiced_a, " / ", n_frames_a

# === Analyze Sound B ===
appendInfoLine: "Analyzing Sound B..."
selectObject: b_mono
pitch_b = To Pitch: analysis_time_step, pitch_floor_B, pitch_ceiling_B

selectObject: pitch_b
n_frames_b = Get number of frames
mean_b = Get mean: 0, 0, "Hertz"
n_voiced_b = Count voiced frames

if mean_b = undefined or mean_b <= 0 or n_voiced_b < 1
    removeObject: pitch_a, pitch_b, a_mono, b_mono
    exitScript: "Sound B has no usable voiced pitch in the selected analysis range."
endif

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

# Analysis limits determine what can be DETECTED; synthesis safety limits
# determine what may be GENERATED. Do not truncate the transferred contour
# at the analysis ceilings.
synthFloor = 20
synthCeil = 0.45 * sr_b

appendInfoLine: "Transfer: ", regName$, " register, blend ", fixed$(blend_strength, 2)
appendInfoLine: "Target safety range: ", round(synthFloor), "-", round(synthCeil), " Hz"
appendInfoLine: ""

# === Build transferred PitchTier ===
Create PitchTier: "PCT_target", xmin_b, xmax_b
pitch_tier = selected("PitchTier")

appendInfoLine: "Transferring contour..."
n_points = 0
limited_points = 0

maxVizPoints  = min(n_frames_b, 500)
if maxVizPoints < 1
    maxVizPoints = 1
endif
vizTimes#     = zero#(maxVizPoints)
vizOrigPitch# = zero#(maxVizPoints)
vizNewPitch#  = zero#(maxVizPoints)
vizAShape#    = zero#(maxVizPoints)
vizFilled#    = zero#(maxVizPoints)
vizStep = ceiling(n_frames_b / maxVizPoints)
if vizStep < 1
    vizStep = 1
endif

# Carry A's last valid deviation across A's unvoiced gaps.
prev_dev_a = 0

for i from 1 to n_frames_b
    selectObject: pitch_b
    t_rel = Get time from frame number: i
    f0_b = Get value at time: t_rel, "Hertz", "Linear"

    if f0_b <> undefined and f0_b > 0
        dev_b = 12 * log2(f0_b / mean_b)

        # Map B's relative phase into zero-based A analysis time.
        phase = t_rel / dur_b
        if phase < 0
            phase = 0
        elsif phase > 1
            phase = 1
        endif
        t_a_rel = phase * dur_a

        selectObject: pitch_a
        f0_a = Get value at time: t_a_rel, "Hertz", "Linear"
        if f0_a <> undefined and f0_a > 0
            dev_a = 12 * log2(f0_a / mean_a)
            prev_dev_a = dev_a
        else
            dev_a = prev_dev_a
        endif

        final_dev = blend_strength * dev_a + (1 - blend_strength) * dev_b
        target_f0 = anchor * 2 ^ (final_dev / 12)

        if target_f0 < synthFloor
            target_f0 = synthFloor
            limited_points += 1
        elsif target_f0 > synthCeil
            target_f0 = synthCeil
            limited_points += 1
        endif

        # PitchTier for B must use B's ABSOLUTE time domain.
        t_abs_b = xmin_b + t_rel
        if t_abs_b < xmin_b
            t_abs_b = xmin_b
        elsif t_abs_b > xmax_b
            t_abs_b = xmax_b
        endif

        selectObject: pitch_tier
        Add point: t_abs_b, target_f0
        n_points += 1

        # Visualization stays zero-based, matching its established 0..dur_b axes.
        vizIdx = ceiling(i / vizStep)
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            if vizFilled#[vizIdx] = 0
                vizTimes#[vizIdx]     = t_rel
                vizOrigPitch#[vizIdx] = f0_b
                vizAShape#[vizIdx]    = anchor * 2 ^ (dev_a / 12)
                vizNewPitch#[vizIdx]  = target_f0
                vizFilled#[vizIdx]    = 1
            endif
        endif
    endif
endfor

if n_points < 1
    removeObject: pitch_tier, pitch_a, pitch_b, a_mono, b_mono
    exitScript: "No transferable voiced pitch points were found."
endif

appendInfoLine: "Points: ", n_points, " / ", n_frames_b
if limited_points > 0
    appendInfoLine: "Sampling-safe target limits applied: ", limited_points, " point(s)"
endif
appendInfoLine: ""

# === Resynthesize every channel of B with the same transferred PitchTier ===
appendInfoLine: "Resynthesizing ", channels_b, " channel(s)..."
channel_result_ids# = zero#(channels_b)

for ch from 1 to channels_b
    selectObject: sound_b
    if channels_b = 1
        channel_work = Copy: "PCT_B_ch1"
    else
        channel_work = Extract one channel: ch
        Rename: "PCT_B_ch" + string$(ch)
    endif

    selectObject: channel_work
    channel_manip = To Manipulation: analysis_time_step, pitch_floor_B, pitch_ceiling_B

    selectObject: channel_manip
    plusObject: pitch_tier
    Replace pitch tier

    selectObject: channel_manip
    channel_result = Get resynthesis (overlap-add)
    Rename: "PCT_result_ch" + string$(ch)
    channel_result_ids#[ch] = channel_result

    removeObject: channel_manip, channel_work
endfor

# Rebuild B's original channel layout without quoted object-name references.
Create Sound from formula: name_b$ + "_matched", channels_b,
    ... xmin_b, xmax_b, sr_b, "0"
sound_result = selected("Sound")

for ch from 1 to channels_b
    selectObject: sound_result
    Formula (part): xmin_b, xmax_b, ch, ch,
        ... "object[" + string$(channel_result_ids#[ch]) + ", 1, col]"
    removeObject: channel_result_ids#[ch]
endfor

# Attenuation-only peak safety.
selectObject: sound_result
result_peak = Get absolute extremum: 0, 0, "None"
if result_peak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
else
    safetyApplied = 0
endif

# === Verify Result ===
selectObject: sound_result
if channels_b > 1
    result_mono = Convert to mono
else
    result_mono = Copy: "PCT_result_analysis"
endif

verifyFloor = max(20, min(pitch_floor_A, pitch_floor_B) * 0.5)
verifyCeil = min(1200, 0.45 * sr_b)
if verifyCeil <= verifyFloor
    verifyFloor = pitch_floor_B
    verifyCeil = pitch_ceiling_B
endif

selectObject: result_mono
pitch_result = To Pitch: analysis_time_step, verifyFloor, verifyCeil
mean_result = Get mean: 0, 0, "Hertz"
if mean_result = undefined
    mean_result = 0
endif

appendInfoLine: "Result mean: ", fixed$(mean_b, 1), " Hz -> ", fixed$(mean_result, 1), " Hz"
if register = 2
    appendInfoLine: "Register target (A): ", fixed$(mean_a, 1), " Hz"
else
    appendInfoLine: "Register kept (B): ", fixed$(mean_b, 1), " Hz"
endif
appendInfoLine: "Output channels: ", channels_b
appendInfoLine: "Peak safety applied: ", safetyApplied
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
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Contour: " + name_a$ + " → " + name_b$ + " | Register: " + regName$ + " | Blend: " + fixed$(blend_strength, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: pitch_tier, pitch_a, pitch_b, pitch_result, a_mono, b_mono, result_mono

# === Final Info ===
selectObject: sound_result

appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Channels preserved: ", channels_b
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: sound_result
    Play
endif

selectObject: sound_result