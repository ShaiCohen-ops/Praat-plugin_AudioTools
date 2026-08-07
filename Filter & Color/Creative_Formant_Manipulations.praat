# ============================================================
# Praat AudioTools - Creative Formant Manipulations v2.2
# Spectral-envelope landmark processor
#
# No LPC resynthesis. No FormantGrid filtering.
# FormantPath is used ONLY to estimate spectral landmarks.
# The original complex STFT spectrum is multiplied by a smooth,
# real-valued gain curve, so phase is preserved bin by bin.
# Static whole-file spectral filtering: one FFT per channel.
# Formant medians use Praat's native quantile query (no O(N^2) sorting).
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
original_name$ = selected$("Sound")

form Creative Formant Manipulations v2.2
    optionmenu preset 1
        option Manual
        option Vocal Lift
        option Giant Dark
        option F2 Laser
        option Wide Alien
        option Compact Vowel
    optionmenu manipulation_type 1
        option Global formant shift
        option F2 focus
        option Formant spacing
    positive max_formant_hz 5500
    comment Manual parameters:
    positive global_ratio 1.30
    positive f2_ratio 1.45
    positive spacing_factor 1.30
    positive strength_db 15
    positive dry_wet_mix 1.0
    optionmenu output_level_mode 1
        option Natural level
        option Safety ceiling
        option Peak normalize
    positive ceiling_peak 0.95
    boolean draw_visualization 1
    boolean play_result 1
endform

# ------------------------------------------------------------
# Presets
# ------------------------------------------------------------
if preset = 2
    manipulation_type = 1
    global_ratio = 1.22
    strength_db = 12
    dry_wet_mix = 1.0
    preset_name$ = "VocalLift"
elsif preset = 3
    manipulation_type = 1
    global_ratio = 0.72
    strength_db = 18
    dry_wet_mix = 1.0
    preset_name$ = "GiantDark"
elsif preset = 4
    manipulation_type = 2
    f2_ratio = 1.75
    strength_db = 24
    dry_wet_mix = 1.0
    preset_name$ = "F2Laser"
elsif preset = 5
    manipulation_type = 3
    spacing_factor = 1.65
    strength_db = 20
    dry_wet_mix = 1.0
    preset_name$ = "WideAlien"
elsif preset = 6
    manipulation_type = 3
    spacing_factor = 0.62
    strength_db = 18
    dry_wet_mix = 1.0
    preset_name$ = "CompactVowel"
else
    preset_name$ = "Manual"
endif

if manipulation_type = 1
    manipulation_name$ = "Global formant shift"
elsif manipulation_type = 2
    manipulation_name$ = "F2 focus"
else
    manipulation_name$ = "Formant spacing"
endif

# ------------------------------------------------------------
# Fixed engine settings
# ------------------------------------------------------------
time_step_s = 0.005
window_length = 0.030
max_formants = 5
pre_emphasis = 35
grain_ms = 50
hop_divisor = 4

# These are ENVELOPE region widths, not LPC resonator Q values.
region_floor_1 = 180
region_floor_2 = 260
region_floor_3 = 360
region_floor_4 = 450
region_floor_5 = 550
region_fraction = 0.24

# ------------------------------------------------------------
# Input / validation
# ------------------------------------------------------------
selectObject: sound
duration = Get total duration
sample_rate = Get sampling frequency
num_channels = Get number of channels
original_xmin = Get start time
nyquist = sample_rate / 2
input_peak = Get absolute extremum: 0, 0, "None"

if duration < 0.20
    exitScript: "Sound must be at least 200 ms for stable formant analysis."
endif
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "dry_wet_mix must be between 0 and 1."
endif
if strength_db <= 0 or strength_db > 36
    exitScript: "strength_db must be greater than 0 and at most 36 dB."
endif
if global_ratio <= 0 or f2_ratio <= 0 or spacing_factor <= 0
    exitScript: "All frequency ratios must be greater than zero."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "ceiling_peak must be greater than 0 and at most 1."
endif

# FormantPath searches ceilings above the requested value.
max_formant_hz = min(max_formant_hz, (nyquist - 50) / 1.22)
if max_formant_hz < 1000
    exitScript: "Sample rate is too low for useful formant analysis."
endif

# True bypass before any analysis/FFT.
neutral = 0
if manipulation_type = 1 and abs(global_ratio - 1) < 0.000001
    neutral = 1
elsif manipulation_type = 2 and abs(f2_ratio - 1) < 0.000001
    neutral = 1
elsif manipulation_type = 3 and abs(spacing_factor - 1) < 0.000001
    neutral = 1
endif
if dry_wet_mix = 0 or neutral = 1
    selectObject: sound
    out = Copy: original_name$ + "_CFM_Bypass"
    selectObject: out
    if output_level_mode = 2
        p = Get absolute extremum: 0, 0, "None"
        if p > ceiling_peak
            Scale peak: ceiling_peak
        endif
    elsif output_level_mode = 3
        p = Get absolute extremum: 0, 0, "None"
        if p > 0
            Scale peak: ceiling_peak
        endif
    endif
    if play_result
        Play
    endif
    selectObject: out
    exitScript: ""
endif

clearinfo
writeInfoLine: "=== Creative Formant Manipulations v2.2 ==="
appendInfoLine: "Method: spectral-envelope landmarks, magnitude only, original phase."
appendInfoLine: "No LPC resynthesis and no FormantGrid filtering."
appendInfoLine: "Optimized static engine: native formant medians + one FFT per channel."
appendInfoLine: "Input: ", original_name$, " | ", fixed$(duration, 3), " s | ", num_channels,
    ... " ch | ", sample_rate, " Hz"
appendInfoLine: "Preset: ", preset_name$

# ------------------------------------------------------------
# Work copy at time zero
# ------------------------------------------------------------
selectObject: sound
work_sound = Copy: "cfm_work"
Shift times to: "start time", 0

# Analysis channel: mono fold unless it cancels, then loudest real channel.
if num_channels > 1
    selectObject: work_sound
    analysis_sound = Convert to mono
    fold_rms = Get root-mean-square: 0, 0
    if fold_rms = undefined or fold_rms < 0.0000001
        removeObject: analysis_sound
        best_rms = -1
        pick_ch = 1
        for ch from 1 to num_channels
            selectObject: work_sound
            probe = Extract one channel: ch
            r = Get root-mean-square: 0, 0
            removeObject: probe
            if r > best_rms
                best_rms = r
                pick_ch = ch
            endif
        endfor
        selectObject: work_sound
        analysis_sound = Extract one channel: pick_ch
        appendInfoLine: "Analysis: mono fold cancelled; using channel ", pick_ch
    else
        appendInfoLine: "Analysis: mono fold"
    endif
else
    selectObject: work_sound
    analysis_sound = Copy: "cfm_analysis"
endif

selectObject: analysis_sound
analysis_rms = Get root-mean-square: 0, 0
if analysis_rms = undefined or analysis_rms < 0.0000001
    removeObject: analysis_sound, work_sound
    exitScript: "The analysis signal is silent."
endif

# ------------------------------------------------------------
# Formant landmarks - analysis only
# ------------------------------------------------------------
appendInfoLine: "Analyzing formant landmarks..."
selectObject: analysis_sound
formant_path = To FormantPath (burg): time_step_s, max_formants, max_formant_hz,
    ... window_length, pre_emphasis, 0.05, 4
formant_obj = Extract Formant
selectObject: formant_obj
num_frames = Get number of frames

# Fast robust static landmarks: use Praat's native median query.
# v2.1 copied every frame into script variables and insertion-sorted them,
# which made runtime grow quadratically with file duration.
for fn from 1 to max_formants
    selectObject: formant_obj
    formant_'fn' = Get quantile: fn, 0, 0, "Hertz", 0.5
endfor

removeObject: formant_path, formant_obj, analysis_sound

valid_formants = 0
for fn from 1 to max_formants
    if formant_'fn' <> undefined and formant_'fn' > 0
        valid_formants = valid_formants + 1
        appendInfoLine: "  F", fn, " = ", fixed$(formant_'fn', 1), " Hz"
    endif
endfor
if valid_formants < 2
    removeObject: work_sound
    exitScript: "Fewer than two reliable formant landmarks were found."
endif

# ------------------------------------------------------------
# Target landmarks
# ------------------------------------------------------------
# F2 is the pivot for spacing mode. If unavailable, use F1.
if formant_2 <> undefined
    pivot_hz = formant_2
else
    pivot_hz = formant_1
endif

for fn from 1 to max_formants
    old_'fn' = formant_'fn'
    target_'fn' = formant_'fn'
    active_'fn' = 0
    if formant_'fn' <> undefined and formant_'fn' > 0
        if manipulation_type = 1
            target_'fn' = formant_'fn' * global_ratio
            active_'fn' = 1
        elsif manipulation_type = 2
            if fn = 2
                target_'fn' = formant_'fn' * f2_ratio
                active_'fn' = 1
            endif
        else
            target_'fn' = pivot_hz + (formant_'fn' - pivot_hz) * spacing_factor
            active_'fn' = 1
        endif

        if target_'fn' < 80
            target_'fn' = 80
        endif
        if target_'fn' > nyquist - 80
            target_'fn' = nyquist - 80
        endif
    endif
endfor

appendInfoLine: "Targets:"
for fn from 1 to max_formants
    if active_'fn' = 1
        appendInfoLine: "  F", fn, ": ", fixed$(old_'fn', 1), " -> ", fixed$(target_'fn', 1), " Hz"
    endif
endfor

# ------------------------------------------------------------
# Build ONE static spectral gain expression.
# This is deliberate: nothing in the spectral curve changes with time,
# so the engine cannot create tremolo from moving poles or trajectories.
# ------------------------------------------------------------
expr$ = ""
terms = 0
for fn from 1 to max_formants
    if active_'fn' = 1 and old_'fn' <> undefined and abs(target_'fn' - old_'fn') > 0.5
        if fn = 1
            floor_w = region_floor_1
        elsif fn = 2
            floor_w = region_floor_2
        elsif fn = 3
            floor_w = region_floor_3
        elsif fn = 4
            floor_w = region_floor_4
        else
            floor_w = region_floor_5
        endif
        width = max(floor_w, old_'fn' * region_fraction)
        if width > 900
            width = 900
        endif

        # Strong but smooth redistribution: a broad dip at the original
        # landmark and a broad lift at its destination.
        if terms > 0
            expr$ = expr$ + " + "
        endif
        expr$ = expr$ + fixed$(strength_db, 4) + " * (exp(-0.5*((x-" +
            ... fixed$(target_'fn', 3) + ")/" + fixed$(width, 3) + ")^2) - exp(-0.5*((x-" +
            ... fixed$(old_'fn', 3) + ")/" + fixed$(width, 3) + ")^2))"
        terms = terms + 1
    endif
endfor

if terms = 0
    removeObject: work_sound
    selectObject: sound
    out = Copy: original_name$ + "_CFM_Bypass"
    selectObject: out
    exitScript: ""
endif

# Clamp the SUM, not each formant separately.
shape_limit$ = fixed$(strength_db, 4)

# ------------------------------------------------------------
# FAST STATIC SPECTRAL ENGINE
# ------------------------------------------------------------
# The landmark mapping above is deliberately static for the whole Sound.
# Therefore the spectral gain curve is also time-invariant: thousands of
# 50-ms STFT grains are unnecessary. One complex FFT per channel applies
# the same smooth magnitude curve while preserving the original phase.
# The Gaussian regions are broad, so the resulting impulse response is short.
procedure process_channel: .input_sound
    selectObject: .input_sound
    .in_dur = Get total duration

    selectObject: .input_sound
    .spec = To Spectrum: "yes"
    selectObject: .spec
    Formula: "self * 10^(min(" + shape_limit$ + ",max(-" + shape_limit$ + "," + expr$ + "))/20)"

    selectObject: .spec
    .back_full = To Sound
    removeObject: .spec

    # To Spectrum can zero-pad to an FFT-friendly size. Restore the exact
    # original channel duration after inverse transformation.
    selectObject: .back_full
    .out = Extract part: 0, .in_dur, "rectangular", 1, "no"
    removeObject: .back_full
    selectObject: .out
endproc

# ------------------------------------------------------------
# Process every channel with the same landmark mapping
# ------------------------------------------------------------
for ch from 1 to num_channels
    if num_channels = 1
        selectObject: work_sound
        dry_ch[ch] = Copy: "cfm_dry"
    else
        selectObject: work_sound
        dry_ch[ch] = Extract one channel: ch
    endif

    @process_channel: dry_ch[ch]
    wet_ch[ch] = selected("Sound")

    if dry_wet_mix < 1
        selectObject: wet_ch[ch]
        Formula: "self*" + string$(dry_wet_mix) + " + object[" + string$(dry_ch[ch]) +
            ... ",1,col]*" + string$(1-dry_wet_mix)
    endif
endfor

if num_channels = 1
    selectObject: wet_ch[1]
    output = Copy: "cfm_output"
    removeObject: wet_ch[1]
else
    selectObject: wet_ch[1]
    out_dur = Get total duration
    Create Sound from formula: "cfm_output", num_channels, 0, out_dur, sample_rate, "0"
    output = selected("Sound")
    for ch from 1 to num_channels
        selectObject: output
        Formula (part): 0, out_dur, ch, ch,
            ... "object[" + string$(wet_ch[ch]) + ",1,col]"
    endfor
    for ch from 1 to num_channels
        removeObject: wet_ch[ch]
    endfor
endif

for ch from 1 to num_channels
    removeObject: dry_ch[ch]
endfor

# ------------------------------------------------------------
# Output level
# ------------------------------------------------------------
selectObject: output
pre_peak = Get absolute extremum: 0, 0, "None"
if output_level_mode = 2
    if pre_peak > ceiling_peak
        Scale peak: ceiling_peak
    endif
elsif output_level_mode = 3
    if pre_peak > 0
        Scale peak: ceiling_peak
    endif
endif

selectObject: output
out_peak = Get absolute extremum: 0, 0, "None"
out_dur = Get total duration
out_sr = Get sampling frequency
out_ch = Get number of channels

# ------------------------------------------------------------
# VISUALIZATION — adapted from the original CFM suite layout
# ------------------------------------------------------------
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    # Use channel 1 for a stable before/after display. On long Sounds, draw
    # only a representative central excerpt so visualization time and memory
    # do not scale with the full recording length. Processing is unaffected.
    viz_max_seconds = 8
    viz_start = 0
    viz_end = duration
    viz_excerpt = 0
    if duration > viz_max_seconds
        viz_start = (duration - viz_max_seconds) / 2
        viz_end = viz_start + viz_max_seconds
        viz_excerpt = 1
    endif

    selectObject: work_sound
    if num_channels > 1
        viz_orig_full = Extract one channel: 1
    else
        viz_orig_full = Copy: "cfm_viz_orig_full"
    endif
    selectObject: viz_orig_full
    if viz_excerpt
        viz_orig = Extract part: viz_start, viz_end, "rectangular", 1, "no"
        removeObject: viz_orig_full
    else
        viz_orig = viz_orig_full
    endif

    selectObject: output
    if out_ch > 1
        viz_proc_full = Extract one channel: 1
    else
        viz_proc_full = Copy: "cfm_viz_proc_full"
    endif
    selectObject: viz_proc_full
    if viz_excerpt
        viz_proc = Extract part: viz_start, viz_end, "rectangular", 1, "no"
        removeObject: viz_proc_full
    else
        viz_proc = viz_proc_full
    endif

    selectObject: viz_orig
    orig_peak_viz = Get absolute extremum: 0, 0, "None"
    selectObject: viz_proc
    proc_peak_viz = Get absolute extremum: 0, 0, "None"
    viz_max = max(orig_peak_viz, proc_peak_viz)
    if viz_max < 0.001
        viz_max = 0.001
    endif
    viz_amp = viz_max * 1.15

    draw_max_freq = 3500
    for fn from 1 to max_formants
        if old_'fn' <> undefined and old_'fn' > draw_max_freq
            draw_max_freq = old_'fn'
        endif
        if target_'fn' <> undefined and target_'fn' > draw_max_freq
            draw_max_freq = target_'fn'
        endif
    endfor
    draw_max_freq = min(max_formant_hz, draw_max_freq * 1.08)
    if draw_max_freq < 1200
        draw_max_freq = min(max_formant_hz, 1200)
    endif
    spec_ceil = min(nyquist, max(5000, max_formant_hz))

    # Spectrograms first, then paint them below.
    selectObject: viz_orig
    To Spectrogram: 0.005, spec_ceil, 0.002, 20, "Gaussian"
    orig_spec = selected("Spectrogram")
    selectObject: viz_proc
    To Spectrogram: 0.005, spec_ceil, 0.002, 20, "Gaussian"
    proc_spec = selected("Spectrogram")

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # TITLE
    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Creative Formant Manipulations##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.06, "half",
        ... original_name$ + "  |  " + preset_name$ + "  |  " + manipulation_name$
        ... + "  |  strength " + fixed$(strength_db, 1) + " dB"
        ... + "  |  mix " + fixed$(dry_wet_mix, 2)
        ... + "  |  " + string$(num_channels) + " ch"
    if viz_excerpt
        Font size: 6
        Colour: "{0.45, 0.45, 0.55}"
        Text: 0.5, "centre", -0.25, "half",
            ... "Visualization: central " + fixed$(viz_max_seconds, 1) + " s excerpt (processing used the full Sound)"
    endif

    # A — ORIGINAL WAVEFORM
    Select outer viewport: 0, 4, 0.65, 1.95
    Select inner viewport: 0.55, 3.75, 0.78, 1.88
    selectObject: viz_orig
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, 0, -viz_amp, viz_amp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "A  Original waveform (shared scale)"
    Text left: "yes", "Amplitude"

    # B — PROCESSED WAVEFORM
    Select outer viewport: 4, 8, 0.65, 1.95
    Select inner viewport: 4.35, 7.75, 0.78, 1.88
    selectObject: viz_proc
    Colour: "{0.22, 0.64, 0.40}"
    Draw: 0, 0, -viz_amp, viz_amp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "B  Processed waveform (shared scale)"
    Text bottom: "yes", "Time (s)"

    # C — LANDMARK MAP: measured landmarks vs spectral-envelope targets
    Select outer viewport: 0, 8, 2.08, 3.75
    Select inner viewport: 0.65, 7.72, 2.25, 3.67
    Axes: 0.5, 5.5, 0, draw_max_freq
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, 5.5, 0, draw_max_freq

    Colour: "{0.86, 0.86, 0.89}"
    Dotted line
    grid_hz = 500
    gh = grid_hz
    while gh < draw_max_freq
        Draw line: 0.5, gh, 5.5, gh
        gh = gh + grid_hz
    endwhile
    Solid line

    formant_colours$# = {"{0.25, 0.55, 0.88}", "{0.90, 0.48, 0.24}", "{0.22, 0.70, 0.43}", "{0.58, 0.38, 0.78}", "{0.78, 0.30, 0.48}"}
    for fn from 1 to max_formants
        if old_'fn' <> undefined and old_'fn' > 0
            # Connector shows how far this envelope landmark is moved.
            Colour: "{0.68, 0.68, 0.72}"
            Line width: 1
            Draw line: fn, old_'fn', fn, target_'fn'
            Paint circle: "{0.68, 0.68, 0.72}", fn, old_'fn', 0.07

            Colour: formant_colours$#[fn]
            Paint circle: formant_colours$#[fn], fn, target_'fn', 0.10
            Font size: 6
            Text: fn + 0.10, "left", target_'fn', "half",
                ... "F" + string$(fn) + "  " + fixed$(old_'fn', 0) + " -> " + fixed$(target_'fn', 0)
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "C  Spectral-envelope landmark mapping (grey = measured, colour = target)"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Formant landmark index"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left every: 1, 500, "yes", "yes", "no"

    # D — ORIGINAL SPECTROGRAM
    Select outer viewport: 0, 4, 3.90, 5.90
    Select inner viewport: 0.55, 3.75, 4.08, 5.82
    selectObject: orig_spec
    Paint: 0, 0, 0, spec_ceil, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "D  Original spectrogram"
    Text left: "yes", "Frequency (Hz)"

    # E — PROCESSED SPECTROGRAM
    Select outer viewport: 4, 8, 3.90, 5.90
    Select inner viewport: 4.35, 7.75, 4.08, 5.82
    selectObject: proc_spec
    Paint: 0, 0, 0, spec_ceil, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "E  Processed spectrogram"
    Text bottom: "yes", "Time (s)"

    # RESULT / ENGINE STRIP
    Select outer viewport: 0, 8, 6.10, 7.45
    Select inner viewport: 0.55, 7.72, 6.20, 7.35
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Colour: "{0.80, 0.80, 0.82}"
    Draw line: 0.50, 0.08, 0.50, 0.92

    Font size: 7
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.02, "left", 0.82, "half", "PROCESS"
    Font size: 6
    Colour: "{0.22, 0.22, 0.22}"
    Text: 0.02, "left", 0.55, "half",
        ... "Static spectral-envelope FFT  |  original phase preserved"
    Text: 0.02, "left", 0.28, "half",
        ... "one FFT per channel  |  " + string$(valid_formants) + " landmarks"

    Font size: 7
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.53, "left", 0.82, "half", "RESULT"
    Font size: 6
    Colour: "{0.22, 0.22, 0.22}"
    Text: 0.53, "left", 0.55, "half",
        ... "peak " + fixed$(input_peak, 3) + " -> " + fixed$(out_peak, 3)
    Text: 0.53, "left", 0.28, "half",
        ... fixed$(duration, 3) + " s  |  " + string$(out_ch) + " ch  |  " + fixed$(out_sr, 0) + " Hz"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"

    removeObject: orig_spec, proc_spec, viz_orig, viz_proc
endif

# Restore the source time domain only after the picture has been drawn at t=0.
selectObject: output
if original_xmin <> 0
    Shift times to: "start time", original_xmin
endif
Rename: original_name$ + "_CFM2_" + preset_name$
out_name$ = selected$("Sound")

removeObject: work_sound

appendInfoLine: ""
appendInfoLine: "Output: ", out_name$
appendInfoLine: "Duration: ", fixed$(duration, 6), " -> ", fixed$(out_dur, 6), " s"
appendInfoLine: "Channels: ", num_channels, " -> ", out_ch
appendInfoLine: "Sample rate: ", sample_rate, " -> ", out_sr, " Hz"
appendInfoLine: "Peak: ", fixed$(input_peak, 5), " -> ", fixed$(out_peak, 5)

if play_result
    selectObject: output
    if out_peak > 1
        play_copy = Copy: "cfm_play_safe"
        Scale peak: 0.95
        Play
        removeObject: play_copy
    else
        Play
    endif
endif

selectObject: output
