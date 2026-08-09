# ============================================================
# Praat AudioTools - Pitch_Stylization_and_Shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Stylization and Shift - combines pitch smoothing,
#   transposition, quantization (auto-tune), and monotone
#   (robot voice) effects. Quick tool for common pitch edits.
#   Note: the Robot preset flattens to the mean AND drops it by
#   2 semitones for a lower, machine-like timbre.
#
# Changelog v0.5:
#   - Added Formant_follow_percent (0..100) to couple pitch-register change
#     with timbral/formant change.
#   - Formant ratio is derived from the measured mean pitch change between
#     the original and processed PitchTiers, so all modes drive timbre.
#   - 0% follow preserves the v0.4 timbre path; 0 st measured change also
#     bypasses formant processing.
#   - Formant processing uses Praat Change speaker with pitch, pitch-range,
#     and duration multipliers fixed at 1, applied per channel.
#   - Extreme formant ratios are safety-limited to 0.5..2.0 and reported.
#   - Final peak safety runs after optional formant processing.
#   - Visualization layout/style is unchanged; the stats line reports the
#     measured pitch change, formant follow amount, and formant ratio.
#
# Changelog v0.4:
#   - True identity path for Manual 0 Hz stylize / 0 st shift.
#   - Full xmin/xmax-safe pitch processing and visualization.
#   - Robust no-pitch handling; identity mode still returns an exact copy.
#   - Validates stylization, pitch-analysis range, and shift amount.
#   - Preserves the source channel count by applying one shared PitchTier
#     independently to every channel.
#   - Robot mean is computed directly from PitchTier points and then shifted
#     by the documented -2 semitones.
#   - Quantize and shift targets use synthesis-safe frequency limits.
#   - Peak protection is attenuation-only.
#   - Visualization layout/style preserved; only coordinate/robustness fixes.
#
# Changelog v0.3:
#   - Fixed off-screen pitch-panel legend (now in Hz/time coords)
#   - Standard header
#   - Documented Robot preset's -2 st drop
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
orig_name$ = selected$("Sound")

selectObject: original
source_xmin = Get start time
source_xmax = Get end time
dur = source_xmax - source_xmin
fs = Get sampling frequency
n_channels = Get number of channels

# === Form ===
form Pitch Stylization and Shift v0.5
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (use settings below)
        option Gentle Smoothing
        option Stepwise Quantize (Auto-tune)
        option Robot Voice (Monotone)
        option Pitch Down (-1 Octave)
        option Pitch Up (+1 Octave)
        option Strong Stylize
    
    comment === Manual Parameters ===
    real Stylize_Hz 2
    real Shift_semitones 0
    
    real Formant_follow_percent 0
    comment (0 = preserve formants, 100 = follow measured pitch-register change)
    comment === Analysis ===
    positive Time_step 0.005
    positive Min_pitch 75
    positive Max_pitch 600
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
op_stylize = stylize_Hz
op_shift = shift_semitones
mode = 0
# mode: 0=Normal, 1=Quantize, 2=Robot

if preset = 2
    # Gentle Smoothing
    op_stylize = 3.0
    op_shift = 0
    mode = 0
    presetName$ = "Gentle"
elsif preset = 3
    # Stepwise Quantize
    op_stylize = 0
    op_shift = 0
    mode = 1
    presetName$ = "Quantize"
elsif preset = 4
    # Robot Voice
    op_stylize = 0
    op_shift = -2
    mode = 2
    presetName$ = "Robot"
elsif preset = 5
    # Pitch Down
    op_stylize = 0
    op_shift = -12
    mode = 0
    presetName$ = "Octave-"
elsif preset = 6
    # Pitch Up
    op_stylize = 0
    op_shift = 12
    mode = 0
    presetName$ = "Octave+"
elsif preset = 7
    # Strong Stylize
    op_stylize = 10.0
    op_shift = -5
    mode = 0
    presetName$ = "Strong"
else
    presetName$ = "Manual"
endif

# Get mode name
if mode = 0
    modeName$ = "Normal"
elsif mode = 1
    modeName$ = "Quantize"
else
    modeName$ = "Robot"
endif

# === Validation ===
if dur <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if op_stylize < 0
    exitScript: "Stylize_Hz must be zero or greater."
endif
if op_shift < -48 or op_shift > 48
    exitScript: "Shift_semitones must be between -48 and +48."
endif
if formant_follow_percent < 0 or formant_follow_percent > 100
    exitScript: "Formant_follow_percent must be between 0 and 100."
endif
if time_step <= 0
    exitScript: "Time_step must be greater than zero."
endif
if min_pitch <= 0 or max_pitch <= min_pitch
    exitScript: "Min_pitch / Max_pitch are invalid."
endif
if max_pitch >= 0.45 * fs
    exitScript: "Max_pitch must be below 45% of the source sampling frequency."
endif

identity_mode = 0
if mode = 0 and op_stylize = 0 and op_shift = 0
    identity_mode = 1
endif

# === Info ===
writeInfoLine: "=== Pitch Stylization and Shift v0.5 ==="
appendInfoLine: "Source: ", orig_name$, " (", fixed$(dur, 2), " s, ", n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
if op_stylize > 0
    appendInfoLine: "Stylize: ", op_stylize, " Hz"
endif
if op_shift <> 0
    appendInfoLine: "Shift: ", op_shift, " semitones"
endif
appendInfoLine: "Formant follow: ", formant_follow_percent, "%"
appendInfoLine: ""

safetyApplied = 0
pitch_available = 0
mean_shift_st = 0
formant_ratio = 1
formant_ratio_raw = 1
formantLimited = 0
formantApplied = 0

# === Exact identity audio path ===
if identity_mode
    selectObject: original
    result = Copy: orig_name$ + "_" + presetName$
    appendInfoLine: "Identity settings: exact audio copy (PSOLA bypassed)."
endif

# === Mono analysis reference ===
selectObject: original
if n_channels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: "PSSS_analysis"
endif

appendInfoLine: "Analyzing pitch..."
selectObject: analysisMono
analysisManip = To Manipulation: time_step, min_pitch, max_pitch

selectObject: analysisManip
origPitchTier = Extract pitch tier

selectObject: origPitchTier
nPts = Get number of points

if nPts > 0
    pitch_available = 1
endif

if pitch_available = 0 and identity_mode = 0
    removeObject: analysisManip, origPitchTier, analysisMono
    exitScript: "No usable voiced pitch was detected in the selected analysis range."
endif

# === Build processed PitchTier ===
if pitch_available
    # Start from the original tier; keep it intact for visualization.
    selectObject: origPitchTier
    workPitchTier = Copy: "PSSS_work_pitch"

    # Stylization is only part of Normal mode.
    if mode = 0 and op_stylize > 0
        selectObject: workPitchTier
        Stylize: op_stylize, "Hz"
    endif

    # Robot central pitch: geometric mean of original voiced tier points.
    robot_base = 0
    if mode = 2
        robot_log_sum = 0
        robot_count = 0
        for rp from 1 to nPts
            selectObject: origPitchTier
            rv = Get value at index: rp
            if rv <> undefined and rv > 0
                robot_log_sum += log2(rv)
                robot_count += 1
            endif
        endfor

        if robot_count < 1
            removeObject: analysisManip, origPitchTier, workPitchTier, analysisMono
            exitScript: "Robot mode could not determine a valid source pitch."
        endif

        robot_base = 2 ^ (robot_log_sum / robot_count)
        appendInfoLine: "Robot centre: ", fixed$(robot_base, 1), " Hz before -2 st shift"
    endif

    # Build final tier explicitly so quantize/shift can be safely clamped.
    Create PitchTier: "processed_pitch", source_xmin, source_xmax
    pitchTier = selected("PitchTier")

    synth_floor = 20
    synth_ceil = 0.45 * fs
    limited_points = 0

    selectObject: workPitchTier
    workPts = Get number of points

    for pt from 1 to workPts
        selectObject: workPitchTier
        t = Get time from index: pt
        f = Get value at index: pt

        if mode = 2
            target_f = robot_base
        elsif mode = 1
            target_f = 440 * 2 ^ (round(12 * log2(f / 440)) / 12)
        else
            target_f = f
        endif

        if op_shift <> 0
            target_f *= 2 ^ (op_shift / 12)
        endif

        if target_f < synth_floor
            target_f = synth_floor
            limited_points += 1
        elsif target_f > synth_ceil
            target_f = synth_ceil
            limited_points += 1
        endif

        selectObject: pitchTier
        Add point: t, target_f
    endfor

    if limited_points > 0
        appendInfoLine: "Sampling-safe pitch limits applied: ", limited_points, " point(s)"
    endif

    # Measure average register change at the original tier's time points.
    shift_sum_st = 0
    shift_count = 0
    for mp from 1 to nPts
        selectObject: origPitchTier
        orig_f = Get value at index: mp
        mt = Get time from index: mp

        selectObject: pitchTier
        proc_f = Get value at time: mt

        if orig_f <> undefined and proc_f <> undefined and orig_f > 0 and proc_f > 0
            shift_sum_st += 12 * log2(proc_f / orig_f)
            shift_count += 1
        endif
    endfor

    if shift_count > 0
        mean_shift_st = shift_sum_st / shift_count
    else
        mean_shift_st = 0
    endif

    formant_ratio_raw = 2 ^ ((mean_shift_st * formant_follow_percent / 100) / 12)
    formant_ratio = formant_ratio_raw

    if formant_ratio < 0.5
        formant_ratio = 0.5
        formantLimited = 1
    elsif formant_ratio > 2.0
        formant_ratio = 2.0
        formantLimited = 1
    endif

    appendInfoLine: "Measured mean pitch change: ", fixed$(mean_shift_st, 2), " st"
    appendInfoLine: "Formant ratio: ", fixed$(formant_ratio, 4)
    if formantLimited
        appendInfoLine: "Formant ratio safety limit applied (raw: ", fixed$(formant_ratio_raw, 4), ")"
    endif
else
    # Identity + no detected pitch: visualization will show an empty pitch panel.
    workPitchTier = 0
    pitchTier = 0
endif

# === Resynthesize only when audio processing is required ===
if identity_mode = 0
    appendInfoLine: ""
    appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."

    channelResults# = zero#(n_channels)

    for ch from 1 to n_channels
        selectObject: original
        if n_channels = 1
            channelWork = Copy: "PSSS_ch1"
        else
            channelWork = Extract one channel: ch
            Rename: "PSSS_ch" + string$(ch)
        endif

        selectObject: channelWork
        manipulation = To Manipulation: time_step, min_pitch, max_pitch

        selectObject: manipulation
        plusObject: pitchTier
        Replace pitch tier

        selectObject: manipulation
        channelResult = Get resynthesis (overlap-add)
        Rename: "PSSS_result_ch" + string$(ch)
        channelResults#[ch] = channelResult

        removeObject: manipulation, channelWork
    endfor

    # Rebuild exact original channel count and time domain.
    Create Sound from formula: "PSSS_result_build", n_channels,
        ... source_xmin, source_xmax, fs, "0"
    result = selected("Sound")

    for ch from 1 to n_channels
        selectObject: result
        Formula (part): source_xmin, source_xmax, ch, ch,
            ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
        removeObject: channelResults#[ch]
    endfor

    selectObject: result
    Rename: orig_name$ + "_" + presetName$
endif

# === Optional formant follow ===
# Change speaker multiplies formants while the following three factors
# keep pitch, pitch range, and duration unchanged: 1, 1, 1.
if formant_follow_percent > 0 and abs(formant_ratio - 1) > 0.000001
    appendInfoLine: "Applying formant follow..."

    # Adapt Change speaker's pitch-analysis range to the processed register.
    register_ratio = 2 ^ (mean_shift_st / 12)
    speakerMin = max(20, min_pitch * register_ratio * 0.75)
    speakerMax = max_pitch * register_ratio * 1.5
    if speakerMax > 0.45 * fs
        speakerMax = 0.45 * fs
    endif
    if speakerMax <= speakerMin
        speakerMin = max(20, min_pitch * 0.5)
        speakerMax = min(0.45 * fs, max_pitch * 2)
    endif

    formantChannelResults# = zero#(n_channels)

    for ch from 1 to n_channels
        selectObject: result
        if n_channels = 1
            formantSource = Copy: "PSSS_formant_ch1"
        else
            formantSource = Extract one channel: ch
            Rename: "PSSS_formant_ch" + string$(ch)
        endif

        selectObject: formantSource
        formantChannel = Change speaker: speakerMin, speakerMax, formant_ratio, 1, 1, 1
        Rename: "PSSS_formant_result_ch" + string$(ch)
        formantChannelResults#[ch] = formantChannel

        removeObject: formantSource
    endfor

    Create Sound from formula: "PSSS_formant_build", n_channels,
        ... source_xmin, source_xmax, fs, "0"
    formantResult = selected("Sound")

    for ch from 1 to n_channels
        selectObject: formantResult
        Formula (part): source_xmin, source_xmax, ch, ch,
            ... "object[" + string$(formantChannelResults#[ch]) + ", 1, col]"
        removeObject: formantChannelResults#[ch]
    endfor

    removeObject: result
    selectObject: formantResult
    Rename: orig_name$ + "_" + presetName$
    result = selected("Sound")
    formantApplied = 1
endif

# Final attenuation-only peak safety, after optional formant processing.
selectObject: result
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
endif

# === Visualization ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Pitch Stylization & Shift##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", orig_name$ + " | " + presetName$ + " | " + modeName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    if mode = 2
        Colour: "{0.7, 0.5, 0.6}"
    elsif mode = 1
        Colour: "{0.5, 0.6, 0.7}"
    else
        Colour: "{0.5, 0.7, 0.6}"
    endif
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", presetName$
    Text bottom: "yes", "Time (s)"
    
    # Pitch comparison
    Select outer viewport: 0, 8, 2.7, 4.5
    Select inner viewport: 0.6, 7.6, 2.9, 4.4

    if pitch_available
        # Find pitch range across original and processed tiers.
        minP = 1000000
        maxP = 0

        selectObject: origPitchTier
        nPts = Get number of points
        for pt from 1 to nPts
            f = Get value at index: pt
            if f > 0
                if f < minP
                    minP = f
                endif
                if f > maxP
                    maxP = f
                endif
            endif
        endfor

        selectObject: pitchTier
        nPts2 = Get number of points
        for pt from 1 to nPts2
            f = Get value at index: pt
            if f > 0
                if f < minP
                    minP = f
                endif
                if f > maxP
                    maxP = f
                endif
            endif
        endfor

        if minP >= maxP
            minP = min_pitch
            maxP = max_pitch
        endif

        pMargin = (maxP - minP) * 0.15
        if pMargin < 20
            pMargin = 20
        endif

        Axes: 0, dur, minP - pMargin, maxP + pMargin
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, dur, minP - pMargin, maxP + pMargin

        # Draw original pitch using relative time.
        Colour: "{0.7, 0.7, 0.7}"
        selectObject: origPitchTier
        for pt from 2 to nPts
            t1 = Get time from index: pt - 1
            t2 = Get time from index: pt
            f1 = Get value at index: pt - 1
            f2 = Get value at index: pt
            if f1 > 0 and f2 > 0
                Draw line: t1 - source_xmin, f1, t2 - source_xmin, f2
            endif
        endfor

        # Draw processed pitch.
        if mode = 2
            Colour: "{0.7, 0.4, 0.5}"
        elsif mode = 1
            Colour: "{0.4, 0.5, 0.7}"
        else
            Colour: "{0.4, 0.7, 0.5}"
        endif
        Line width: 1.5
        selectObject: pitchTier
        for pt from 2 to nPts2
            t1 = Get time from index: pt - 1
            t2 = Get time from index: pt
            f1 = Get value at index: pt - 1
            f2 = Get value at index: pt
            if f1 > 0 and f2 > 0
                Draw line: t1 - source_xmin, f1, t2 - source_xmin, f2
            endif
        endfor
        Line width: 1

        # Draw semitone grid for quantize mode.
        if mode = 1
            Colour: "{0.85, 0.85, 0.95}"
            minMidi = floor(69 + 12 * log2(minP / 440))
            maxMidi = ceiling(69 + 12 * log2(maxP / 440))
            for midi from minMidi to maxMidi
                freq = 440 * (2 ^ ((midi - 69) / 12))
                Dotted line
                Draw line: 0, freq, dur, freq
                Solid line
            endfor
        endif

        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Pitch (Hz)"
        Text bottom: "yes", "Time (s)"

        # Legend in panel coordinates.
        legY = maxP + pMargin * 0.5
        legX = dur * 0.03
        Font size: 6
        Colour: "{0.7, 0.7, 0.7}"
        Text: legX, "left", legY, "half", "Original"
        if mode = 2
            Colour: "{0.7, 0.4, 0.5}"
        elsif mode = 1
            Colour: "{0.4, 0.5, 0.7}"
        else
            Colour: "{0.4, 0.7, 0.5}"
        endif
        Text: legX + dur * 0.14, "left", legY, "half", "Processed"
    else
        # Identity mode can still succeed for unvoiced material.
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text: 0.5, "centre", 0.5, "half", "No voiced pitch detected - audio copied unchanged"
        Text left: "yes", "Pitch"
    endif

    # Mode indicator
    Select outer viewport: 0, 8, 4.7, 5.3
    Select inner viewport: 0.6, 7.6, 4.8, 5.2
    
    Axes: 0, 3, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 3, 0, 1
    
    # Normal
    if mode = 0
        Paint rectangle: "{0.5, 0.7, 0.5}", 0.1, 0.9, 0.1, 0.9
    else
        Paint rectangle: "{0.8, 0.8, 0.8}", 0.1, 0.9, 0.1, 0.9
    endif
    
    # Quantize
    if mode = 1
        Paint rectangle: "{0.5, 0.6, 0.8}", 1.1, 1.9, 0.1, 0.9
    else
        Paint rectangle: "{0.8, 0.8, 0.8}", 1.1, 1.9, 0.1, 0.9
    endif
    
    # Robot
    if mode = 2
        Paint rectangle: "{0.7, 0.5, 0.6}", 2.1, 2.9, 0.1, 0.9
    else
        Paint rectangle: "{0.8, 0.8, 0.8}", 2.1, 2.9, 0.1, 0.9
    endif
    
    Colour: "Black"
    Font size: 6
    Text: 0.5, "centre", 0.5, "half", "Normal"
    Text: 1.5, "centre", 0.5, "half", "Quantize"
    Text: 2.5, "centre", 0.5, "half", "Robot"
    
    Draw inner box
    Font size: 6
    Text left: "yes", "Mode"
    
    # Stats
    Select outer viewport: 0, 8, 5.4, 5.7
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    statsText$ = "Mode: " + modeName$
    if op_stylize > 0
        statsText$ = statsText$ + " | Stylize: " + fixed$(op_stylize, 1) + " Hz"
    endif
    if op_shift <> 0
        statsText$ = statsText$ + " | Shift: " + string$(op_shift) + " st"
    endif
    statsText$ = statsText$ + " | dF0: " + fixed$(mean_shift_st, 2) + " st"
    statsText$ = statsText$ + " | Formant: " + fixed$(formant_follow_percent, 0) + "%"
    statsText$ = statsText$ + " x" + fixed$(formant_ratio, 3)
    Text: 0.5, "centre", 0.5, "half", statsText$
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
if pitch_available
    removeObject: analysisManip, origPitchTier, workPitchTier, pitchTier, analysisMono
else
    removeObject: analysisManip, origPitchTier, analysisMono
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Measured mean pitch change: ", fixed$(mean_shift_st, 2), " st"
appendInfoLine: "Formant follow: ", fixed$(formant_follow_percent, 0), "%"
appendInfoLine: "Formant ratio: ", fixed$(formant_ratio, 4)
appendInfoLine: "Formant processing applied: ", formantApplied
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result