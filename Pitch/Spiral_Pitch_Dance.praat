# ============================================================
# Praat AudioTools - Spiral_Pitch_Dance.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spiral Pitch Dance - creates accelerating sinusoidal pitch
#   movement. The spiral speeds up over time, creating a Doppler-
#   like flyby effect. Great for transitions and buildups.
#
# Changelog v0.4:
#   - Spiral modulation is now source-relative: the original pitch contour
#     is multiplied by the spiral ratio instead of being replaced by a
#     contour around one median F0.
#   - Semitone_range may be 0; zero range is a true identity path that
#     bypasses PSOLA and returns an exact copy.
#   - Mono is used for analysis only; the original channel count is preserved
#     by applying one shared PitchTier independently to every channel.
#   - Removed the fabricated 200 Hz fallback; processing stops cleanly when
#     no usable voiced pitch is detected.
#   - Analysis range is separated from synthesis safety (20 Hz .. 0.45*SR).
#   - Added parameter/sample-rate validation; Acceleration must be >= 1.
#   - Peak protection is attenuation-only.
#   - Visualization layout/style preserved; zero-range axes and spiral-frequency
#     fallback are corrected.
#
# Changelog v0.3:
#   - Stereo-safe: fold multichannel input to mono before To Manipulation
#     (output is mono for stereo input; mono input unchanged / bit-identical)
#   - Viz: set world axes explicitly before title & stats text (was
#     inheriting stale axes from the frequency panel -> mis-placed text)
#   - Viz: track filled buckets so the first curve point (t=0) is drawn
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
orig$ = selected$("Sound")

selectObject: original
xmin = Get start time
xmax = Get end time
dur = xmax - xmin
sampling = Get sampling frequency
n_channels = Get number of channels

# === Form ===
form Spiral Pitch Dance v0.4
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Spiral
        option Moderate Spiral
        option Aggressive Spiral
        option Extreme Spiral
        option Fast Rotation
        option Slow Evolution
        option Psychedelic Swirl
    
    comment === Spiral Parameters ===
    positive Spirals 2
    real Semitone_range 24
    positive Acceleration 1.5
    
    comment === Analysis ===
    positive Time_step 0.005
    positive Floor_pitch 50
    positive Ceiling_pitch 1200
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Spiral
    spirals = 1.5
    semitone_range = 12
    acceleration = 1.3
    presetName$ = "Gentle"
elsif preset = 3
    # Moderate Spiral
    spirals = 2
    semitone_range = 24
    acceleration = 1.5
    presetName$ = "Moderate"
elsif preset = 4
    # Aggressive Spiral
    spirals = 3
    semitone_range = 36
    acceleration = 1.8
    presetName$ = "Aggressive"
elsif preset = 5
    # Extreme Spiral
    spirals = 5
    semitone_range = 48
    acceleration = 2.2
    presetName$ = "Extreme"
elsif preset = 6
    # Fast Rotation
    spirals = 4
    semitone_range = 30
    acceleration = 2.5
    presetName$ = "Fast"
elsif preset = 7
    # Slow Evolution
    spirals = 1
    semitone_range = 18
    acceleration = 1.2
    presetName$ = "Slow"
elsif preset = 8
    # Psychedelic Swirl
    spirals = 8
    semitone_range = 60
    acceleration = 3.0
    presetName$ = "Psychedelic"
else
    presetName$ = "Manual"
endif

# === Validation ===
if dur <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if spirals <= 0 or spirals > 64
    exitScript: "Spirals must be greater than 0 and no more than 64."
endif
if semitone_range < 0 or semitone_range > 72
    exitScript: "Semitone_range must be between 0 and 72 semitones."
endif
if acceleration < 1 or acceleration > 10
    exitScript: "Acceleration must be between 1 and 10."
endif
if time_step <= 0
    exitScript: "Time_step must be greater than zero."
endif
if floor_pitch <= 0 or ceiling_pitch <= floor_pitch
    exitScript: "Floor_pitch / Ceiling_pitch are invalid."
endif
if ceiling_pitch >= 0.45 * sampling
    exitScript: "Ceiling_pitch must be below 45% of the source sampling frequency."
endif

identity_mode = 0
if semitone_range = 0
    identity_mode = 1
endif

# === Info ===
writeInfoLine: "=== Spiral Pitch Dance v0.4 ==="
appendInfoLine: "Source: ", orig$, " (", fixed$(dur, 2), " s, ", n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Spirals: ", spirals
appendInfoLine: "Semitone range: +/-", semitone_range
appendInfoLine: "Acceleration: ", acceleration
appendInfoLine: ""

# === Visualization curve storage ===
npoints = round(dur / 0.01)
if npoints < 200
    npoints = 200
endif
if npoints > 2000
    npoints = 2000
endif

maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizPhases# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    pos = i / (npoints - 1)

    phase = spirals * 2 * pi * (pos ^ acceleration)
    spiral_value = sin(phase)
    pitch_shift_st = semitone_range * spiral_value

    vizIdx = floor(i / vizStep) + 1
    if vizIdx < 1
        vizIdx = 1
    elsif vizIdx > maxVizPoints
        vizIdx = maxVizPoints
    endif

    if vizFilled#[vizIdx] = 0
        vizFilled#[vizIdx] = 1
        vizTimes#[vizIdx] = t
        vizShifts#[vizIdx] = pitch_shift_st
        vizPhases#[vizIdx] = phase
    endif
endfor

safetyApplied = 0
limited_points = 0
analysisMono = 0
analysisManip = 0
originalPitchTier = 0
pitchTier = 0

# === True identity path ===
if identity_mode
    selectObject: original
    result = Copy: orig$ + "_spiral_" + presetName$
    appendInfoLine: "Zero semitone range: exact audio copy (PSOLA bypassed)."

else
    # === Mono analysis reference ===
    selectObject: original
    if n_channels > 1
        analysisMono = Convert to mono
    else
        analysisMono = Copy: "SPD_analysis"
    endif

    selectObject: analysisMono
    analysisManip = To Manipulation: time_step, floor_pitch, ceiling_pitch

    selectObject: analysisManip
    originalPitchTier = Extract pitch tier

    selectObject: originalPitchTier
    nPitchPoints = Get number of points

    if nPitchPoints < 1
        removeObject: analysisManip, originalPitchTier, analysisMono
        exitScript: "No usable voiced pitch was detected in the selected analysis range."
    endif

    # Robust reference pitch for reporting only.
    log_sum = 0
    pitch_count = 0
    for pp from 1 to nPitchPoints
        selectObject: originalPitchTier
        pf = Get value at index: pp
        if pf <> undefined and pf > 0
            log_sum += log2(pf)
            pitch_count += 1
        endif
    endfor
    if pitch_count > 0
        reference_f0 = 2 ^ (log_sum / pitch_count)
        appendInfoLine: "Reference pitch (geometric mean): ", fixed$(reference_f0, 1), " Hz"
    endif

    # === Build source-relative processed PitchTier ===
    appendInfoLine: ""
    appendInfoLine: "Building source-relative spiral pitch curve..."

    Create PitchTier: "spiral_pitch", xmin, xmax
    pitchTier = selected("PitchTier")

    synth_floor = 20
    synth_ceil = 0.45 * sampling

    for pp from 1 to nPitchPoints
        selectObject: originalPitchTier
        t = Get time from index: pp
        source_f0 = Get value at index: pp

        pos = (t - xmin) / dur
        if pos < 0
            pos = 0
        elsif pos > 1
            pos = 1
        endif

        phase = spirals * 2 * pi * (pos ^ acceleration)
        pitch_shift_st = semitone_range * sin(phase)
        ratio = 2 ^ (pitch_shift_st / 12)

        new_f0 = source_f0 * ratio

        if new_f0 < synth_floor
            new_f0 = synth_floor
            limited_points += 1
        elsif new_f0 > synth_ceil
            new_f0 = synth_ceil
            limited_points += 1
        endif

        selectObject: pitchTier
        Add point: t, new_f0
    endfor

    if limited_points > 0
        appendInfoLine: "Sampling-safe pitch limits applied: ", limited_points, " point(s)"
    endif

    # === Resynthesize every original channel with shared PitchTier ===
    appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."
    channelResults# = zero#(n_channels)

    for ch from 1 to n_channels
        selectObject: original
        if n_channels = 1
            channelWork = Copy: "SPD_ch1"
        else
            channelWork = Extract one channel: ch
            Rename: "SPD_ch" + string$(ch)
        endif

        selectObject: channelWork
        manipulation = To Manipulation: time_step, floor_pitch, ceiling_pitch

        selectObject: manipulation
        plusObject: pitchTier
        Replace pitch tier

        selectObject: manipulation
        channelResult = Get resynthesis (overlap-add)
        Rename: "SPD_result_ch" + string$(ch)
        channelResults#[ch] = channelResult

        removeObject: manipulation, channelWork
    endfor

    Create Sound from formula: "SPD_result_build", n_channels,
        ... xmin, xmax, sampling, "0"
    result = selected("Sound")

    for ch from 1 to n_channels
        selectObject: result
        Formula (part): xmin, xmax, ch, ch,
            ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
        removeObject: channelResults#[ch]
    endfor

    selectObject: result
    Rename: orig$ + "_spiral_" + presetName$
endif

# Final attenuation-only peak safety.
selectObject: result
result_peak = Get absolute extremum: 0, 0, "None"
if result_peak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
endif

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spiral Pitch Dance: " + orig$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Spiral"
    Text bottom: "yes", "Time (s)"
    
    # Pitch shift curve (spiral)
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.7, 3.9
    
    sMargin = semitone_range * 0.15
    
    if sMargin < 2
        sMargin = 2
    endif
    Axes: xmin, xmax, -semitone_range - sMargin, semitone_range + sMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, -semitone_range - sMargin, semitone_range + sMargin
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, 0, xmax, 0
    Solid line
    
    # Range lines
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: xmin, semitone_range, xmax, semitone_range
    Draw line: xmin, -semitone_range, xmax, -semitone_range
    Solid line
    
    # Draw spiral curve
    Colour: "{0.5, 0.4, 0.7}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizFilled#[vp] and vizFilled#[vp - 1]
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Shift (st)"
    Text bottom: "yes", "Time (s)"
    
    # Phase/frequency indicator
    Select outer viewport: 0, 8, 4.2, 5.0
    Select inner viewport: 0.6, 7.6, 4.3, 4.9
    
    # Calculate instantaneous frequency at each point
    maxFreqViz = 0
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > vizTimes#[vp - 1]
            instFreq = (vizPhases#[vp] - vizPhases#[vp - 1]) / (2 * pi * (vizTimes#[vp] - vizTimes#[vp - 1]))
            if instFreq > maxFreqViz
                maxFreqViz = instFreq
            endif
        endif
    endfor
    
    if maxFreqViz < 1
        maxFreqViz = spirals * acceleration / dur
    endif
    if maxFreqViz < 0.1
        maxFreqViz = 0.1
    endif
    
    Axes: xmin, xmax, 0, maxFreqViz * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, 0, maxFreqViz * 1.2
    
    # Draw frequency curve
    Colour: "{0.7, 0.5, 0.5}"
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > vizTimes#[vp - 1]
            instFreq = (vizPhases#[vp] - vizPhases#[vp - 1]) / (2 * pi * (vizTimes#[vp] - vizTimes#[vp - 1]))
            prevFreq = 0
            if vp > 2 and vizTimes#[vp - 1] > vizTimes#[vp - 2]
                prevFreq = (vizPhases#[vp - 1] - vizPhases#[vp - 2]) / (2 * pi * (vizTimes#[vp - 1] - vizTimes#[vp - 2]))
            else
                prevFreq = instFreq
            endif
            Draw line: vizTimes#[vp - 1], prevFreq, vizTimes#[vp], instFreq
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Spiral freq"
    Text bottom: "yes", "Time (s)"
    
    # Stats
    Select outer viewport: 0, 8, 5.1, 5.4
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Spirals: " + fixed$(spirals, 1) + " | Range: +/-" + string$(semitone_range) + " st | Acceleration: " + fixed$(acceleration, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
if identity_mode = 0
    removeObject: analysisManip, originalPitchTier, pitchTier, analysisMono
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
