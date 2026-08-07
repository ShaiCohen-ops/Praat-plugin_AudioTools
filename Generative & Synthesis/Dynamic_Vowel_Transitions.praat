# ============================================================
# Praat AudioTools - Dynamic Vowel Transitions v1.0
# True dynamic source-filter vowel synthesis
#
# F1/F2/F3 are SYNTHESIS RESONANCES in a time-varying FormantGrid.
# They are not oscillator frequencies. A harmonic or noise excitation
# is created first, then filtered through the moving vocal-tract model.
# ============================================================

form Dynamic Vowel Transitions v1.0
    comment === Preset ===
    optionmenu preset 1
        option Custom (use settings below)
        option A to I
        option I to U
        option U to A
        option A to E to I
        option Vowel Cycle
        option Formant Glissando
        option Whisper Morph
        option Singing Vowels
        option Robot Speech
        option Alien Vowels

    comment === Basic Settings ===
    positive duration_s 3.0
    integer sample_rate_hz 44100
    real fundamental_hz 120

    comment === Start Vowel Resonances (Hz) ===
    positive start_f1 730
    positive start_f2 1090
    positive start_f3 2440

    comment === End Vowel Resonances (Hz) ===
    positive end_f1 270
    positive end_f2 2290
    positive end_f3 3010

    comment === Source-Filter Synthesis ===
    positive formant_bandwidth_scale 1.0
    integer source_harmonics 18
    real breathiness 0.04

    comment === Output ===
    optionmenu spatial_mode 1
        option Mono
        option Stereo Voice
        option Rotating Formants
        option Wide Transition
    optionmenu output_level_mode 1
        option Natural level
        option Safety ceiling
        option Peak normalize
    positive ceiling_peak 0.90
    boolean draw_visualization 1
    boolean play_result 1
endform

# ------------------------------------------------------------
# Presets
# ------------------------------------------------------------
preset_name$ = "Custom"
multi_vowel = 0

if preset = 2
    start_f1 = 730
    start_f2 = 1090
    start_f3 = 2440
    end_f1 = 270
    end_f2 = 2290
    end_f3 = 3010
    fundamental_hz = 120
    formant_bandwidth_scale = 1.0
    source_harmonics = 18
    breathiness = 0.04
    preset_name$ = "A_to_I"
elsif preset = 3
    start_f1 = 270
    start_f2 = 2290
    start_f3 = 3010
    end_f1 = 300
    end_f2 = 870
    end_f3 = 2240
    fundamental_hz = 120
    formant_bandwidth_scale = 1.0
    source_harmonics = 18
    breathiness = 0.04
    preset_name$ = "I_to_U"
elsif preset = 4
    start_f1 = 300
    start_f2 = 870
    start_f3 = 2240
    end_f1 = 730
    end_f2 = 1090
    end_f3 = 2440
    fundamental_hz = 120
    formant_bandwidth_scale = 1.0
    source_harmonics = 18
    breathiness = 0.04
    preset_name$ = "U_to_A"
elsif preset = 5
    multi_vowel = 1
    num_vowels = 3
    vowel_f1[1] = 730
    vowel_f2[1] = 1090
    vowel_f3[1] = 2440
    vowel_f1[2] = 530
    vowel_f2[2] = 1840
    vowel_f3[2] = 2480
    vowel_f1[3] = 270
    vowel_f2[3] = 2290
    vowel_f3[3] = 3010
    fundamental_hz = 120
    formant_bandwidth_scale = 1.0
    source_harmonics = 18
    breathiness = 0.04
    preset_name$ = "A_E_I"
elsif preset = 6
    multi_vowel = 1
    num_vowels = 4
    vowel_f1[1] = 730
    vowel_f2[1] = 1090
    vowel_f3[1] = 2440
    vowel_f1[2] = 270
    vowel_f2[2] = 2290
    vowel_f3[2] = 3010
    vowel_f1[3] = 300
    vowel_f2[3] = 870
    vowel_f3[3] = 2240
    vowel_f1[4] = 730
    vowel_f2[4] = 1090
    vowel_f3[4] = 2440
    fundamental_hz = 120
    formant_bandwidth_scale = 1.0
    source_harmonics = 18
    breathiness = 0.04
    preset_name$ = "VowelCycle"
elsif preset = 7
    start_f1 = 200
    start_f2 = 600
    start_f3 = 1800
    end_f1 = 900
    end_f2 = 2800
    end_f3 = 4000
    fundamental_hz = 110
    formant_bandwidth_scale = 0.75
    source_harmonics = 24
    breathiness = 0.03
    preset_name$ = "FormantGlissando"
elsif preset = 8
    start_f1 = 600
    start_f2 = 1200
    start_f3 = 2400
    end_f1 = 400
    end_f2 = 1800
    end_f3 = 2800
    fundamental_hz = 0
    formant_bandwidth_scale = 1.35
    source_harmonics = 1
    breathiness = 1.0
    preset_name$ = "WhisperMorph"
elsif preset = 9
    duration_s = 5.0
    fundamental_hz = 220
    start_f1 = 550
    start_f2 = 1100
    start_f3 = 2350
    end_f1 = 350
    end_f2 = 2000
    end_f3 = 3000
    formant_bandwidth_scale = 0.85
    source_harmonics = 26
    breathiness = 0.025
    preset_name$ = "SingingVowels"
elsif preset = 10
    start_f1 = 400
    start_f2 = 1200
    start_f3 = 2400
    end_f1 = 500
    end_f2 = 1500
    end_f3 = 2600
    fundamental_hz = 100
    formant_bandwidth_scale = 0.60
    source_harmonics = 20
    breathiness = 0.005
    preset_name$ = "RobotSpeech"
elsif preset = 11
    start_f1 = 150
    start_f2 = 3000
    start_f3 = 4500
    end_f1 = 800
    end_f2 = 1200
    end_f3 = 3500
    fundamental_hz = 180
    formant_bandwidth_scale = 0.55
    source_harmonics = 28
    breathiness = 0.06
    preset_name$ = "AlienVowels"
endif

# ------------------------------------------------------------
# Validation / setup
# ------------------------------------------------------------
if duration_s <= 0
    exitScript: "Duration_s must be greater than 0."
endif
if sample_rate_hz < 4000
    exitScript: "Sample_rate_hz must be at least 4000 Hz."
endif
if fundamental_hz < 0
    fundamental_hz = 0
endif
if fundamental_hz > 0 and fundamental_hz >= sample_rate_hz / 2 - 100
    exitScript: "Fundamental_hz is too high for this sample rate."
endif
if source_harmonics < 1
    source_harmonics = 1
endif
if source_harmonics > 64
    source_harmonics = 64
endif
if formant_bandwidth_scale <= 0
    formant_bandwidth_scale = 1
endif
if breathiness < 0
    breathiness = 0
elsif breathiness > 1
    breathiness = 1
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    ceiling_peak = 0.90
endif

nyquist = sample_rate_hz / 2
max_resonance_hz = nyquist - 80
if max_resonance_hz < 900
    exitScript: "Sample rate is too low for a three-resonance vowel model."
endif

uid$ = string$(randomInteger(10000, 99999))
two_pi = 2 * pi

# Bandwidths are synthesis parameters, not measured LPC bandwidths.
bw1 = 70 * formant_bandwidth_scale
bw2 = 100 * formant_bandwidth_scale
bw3 = 150 * formant_bandwidth_scale

# Use enough trajectory points for smooth motion while capping dispatch cost.
trajectory_step = max(0.01, duration_s / 800)
n_traj = ceiling(duration_s / trajectory_step) + 1

clearinfo
writeInfoLine: "=== Dynamic Vowel Transitions v1.0 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Engine: excitation -> dynamic synthetic FormantGrid"
appendInfoLine: "Duration: ", fixed$(duration_s, 3), " s | SR: ", sample_rate_hz, " Hz"
if fundamental_hz > 0
    appendInfoLine: "Source: harmonic, F0=", fixed$(fundamental_hz, 2), " Hz, harmonics=", source_harmonics
else
    appendInfoLine: "Source: noise (whisper)"
endif
appendInfoLine: "Bandwidth scale: ", fixed$(formant_bandwidth_scale, 2), " | Breathiness: ", fixed$(breathiness, 2)
appendInfoLine: ""

# ------------------------------------------------------------
# Build source excitation.
# ------------------------------------------------------------
appendInfoLine: "[1/4] Building excitation..."

if fundamental_hz > 0
    source_formula$ = "0"
    valid_harmonics = 0
    for h from 1 to source_harmonics
        hf = h * fundamental_hz
        if hf < nyquist - 80
            amp = 1 / (h ^ 1.15)
            source_formula$ = source_formula$ + " + " + fixed$(amp, 8) + "*sin(two_pi*" + string$(hf) + "*x)"
            valid_harmonics = valid_harmonics + 1
        endif
    endfor
    if valid_harmonics < 1
        exitScript: "No valid source harmonics below Nyquist."
    endif
    source = Create Sound from formula: "dvt_source_" + uid$, 1, 0, duration_s, sample_rate_hz, source_formula$
    selectObject: source
    src_peak = Get absolute extremum: 0, 0, "None"
    if src_peak > 0
        Formula: "self * " + string$(0.30 / src_peak)
    endif
    if breathiness > 0
        Formula: "self*(1-" + string$(breathiness) + ") + randomGauss(0,0.12)*" + string$(breathiness)
    endif
else
    source = Create Sound from formula: "dvt_source_" + uid$, 1, 0, duration_s, sample_rate_hz, "randomGauss(0,0.18)"
endif

selectObject: source
source_rms = Get root-mean-square: 0, 0

# ------------------------------------------------------------
# Build a true time-varying synthesis FormantGrid.
# ------------------------------------------------------------
appendInfoLine: "[2/4] Building dynamic F1/F2/F3 resonance trajectories..."

fg = Create FormantGrid: "dvt_filter_" + uid$, 0, duration_s, 3, 500, 1000, 100, 50
selectObject: fg
for f from 1 to 3
    Remove formant points between: f, 0, duration_s
    Remove bandwidth points between: f, 0, duration_s
endfor

# Bandwidths are static here; only resonance frequencies morph.
Add bandwidth point: 1, 0, bw1
Add bandwidth point: 1, duration_s, bw1
Add bandwidth point: 2, 0, bw2
Add bandwidth point: 2, duration_s, bw2
Add bandwidth point: 3, 0, bw3
Add bandwidth point: 3, duration_s, bw3

for p from 1 to n_traj
    t = (p - 1) * trajectory_step
    if t > duration_s
        t = duration_s
    endif
    norm_t = t / duration_s

    if multi_vowel = 1
        segment_dur = 1 / (num_vowels - 1)
        segment = floor(norm_t / segment_dur) + 1
        if segment >= num_vowels
            segment = num_vowels - 1
        endif
        local_t = (norm_t - (segment - 1) * segment_dur) / segment_dur
        if local_t < 0
            local_t = 0
        elsif local_t > 1
            local_t = 1
        endif
        smooth_t = 0.5 * (1 - cos(pi * local_t))
        f1_here = vowel_f1[segment] + (vowel_f1[segment + 1] - vowel_f1[segment]) * smooth_t
        f2_here = vowel_f2[segment] + (vowel_f2[segment + 1] - vowel_f2[segment]) * smooth_t
        f3_here = vowel_f3[segment] + (vowel_f3[segment + 1] - vowel_f3[segment]) * smooth_t
    else
        smooth_t = 0.5 * (1 - cos(pi * norm_t))
        f1_here = start_f1 + (end_f1 - start_f1) * smooth_t
        f2_here = start_f2 + (end_f2 - start_f2) * smooth_t
        f3_here = start_f3 + (end_f3 - start_f3) * smooth_t
    endif

    # Keep all three resonances valid and ordered at low sample rates too.
    f1_here = max(80, min(f1_here, max_resonance_hz - 220))
    f2_here = max(f1_here + 80, min(f2_here, max_resonance_hz - 120))
    f3_here = max(f2_here + 100, min(f3_here, max_resonance_hz))
    if f3_here > max_resonance_hz
        f3_here = max_resonance_hz
        f2_here = min(f2_here, f3_here - 100)
        f1_here = min(f1_here, f2_here - 80)
    endif

    trajectory_t[p] = t
    trajectory_f1[p] = f1_here
    trajectory_f2[p] = f2_here
    trajectory_f3[p] = f3_here

    selectObject: fg
    Add formant point: 1, t, f1_here
    Add formant point: 2, t, f2_here
    Add formant point: 3, t, f3_here
endfor

appendInfoLine: "  F1: ", fixed$(trajectory_f1[1], 0), " -> ", fixed$(trajectory_f1[n_traj], 0), " Hz"
appendInfoLine: "  F2: ", fixed$(trajectory_f2[1], 0), " -> ", fixed$(trajectory_f2[n_traj], 0), " Hz"
appendInfoLine: "  F3: ", fixed$(trajectory_f3[1], 0), " -> ", fixed$(trajectory_f3[n_traj], 0), " Hz"

# ------------------------------------------------------------
# Dynamic source-filter synthesis.
# ------------------------------------------------------------
appendInfoLine: "[3/4] Filtering source through moving vocal tract..."
selectObject: source
plusObject: fg
filtered = Filter (no scale)

# FormantGrid all-pole gain can be very large. Match one GLOBAL RMS scalar
# back to the excitation. This preserves the time-varying colour and its
# natural harmonic/formant interaction without per-frame normalization.
selectObject: filtered
filtered_rms = Get root-mean-square: 0, 0
if source_rms > 0.000000000001 and filtered_rms > 0.000000000001
    global_comp = source_rms / filtered_rms
    Formula: "self * " + string$(global_comp)
endif

# Gentle edges only.
fade_s = min(0.02, duration_s / 4)
if fade_s > 0
    Formula: "if x < " + string$(fade_s) + " then self*(x/" + string$(fade_s) + ") else self fi"
    Formula: "if x > " + string$(duration_s - fade_s) + " then self*((" + string$(duration_s) + "-x)/" + string$(fade_s) + ") else self fi"
endif

# ------------------------------------------------------------
# Spatial processing.
# ------------------------------------------------------------
appendInfoLine: "[4/4] Spatial/output stage..."
output_sound = filtered

if spatial_mode = 2
    # Stereo Voice: complementary broad bands.
    selectObject: output_sound
    left_copy = Copy: "dvt_left_" + uid$
    left_filtered = Filter (pass Hann band): 0, min(2200, nyquist - 100), 120
    removeObject: left_copy

    selectObject: output_sound
    right_copy = Copy: "dvt_right_" + uid$
    right_filtered = Filter (pass Hann band): min(120, nyquist - 300), min(5000, nyquist - 80), 120
    removeObject: right_copy

    selectObject: left_filtered
    plusObject: right_filtered
    stereo = Combine to stereo
    removeObject: output_sound, left_filtered, right_filtered
    output_sound = stereo

elsif spatial_mode = 3
    # Rotating Formants: same vowel signal, equal-power-ish slow rotation.
    selectObject: output_sound
    left_sound = Copy: "dvt_left_" + uid$
    Formula: "self * sqrt(max(0,0.5 + 0.5*cos(two_pi*0.15*x)))"

    selectObject: output_sound
    right_sound = Copy: "dvt_right_" + uid$
    Formula: "self * sqrt(max(0,0.5 + 0.5*sin(two_pi*0.15*x)))"

    selectObject: left_sound
    plusObject: right_sound
    stereo = Combine to stereo
    removeObject: output_sound, left_sound, right_sound
    output_sound = stereo

elsif spatial_mode = 4
    # Wide Transition: stronger spectral contrast between channels.
    selectObject: output_sound
    left_copy = Copy: "dvt_left_" + uid$
    left_filtered = Filter (pass Hann band): 0, min(1700, nyquist - 100), 120
    removeObject: left_copy

    selectObject: output_sound
    right_copy = Copy: "dvt_right_" + uid$
    right_filtered = Filter (pass Hann band): min(180, nyquist - 300), min(6000, nyquist - 80), 120
    removeObject: right_copy

    selectObject: left_filtered
    plusObject: right_filtered
    stereo = Combine to stereo
    removeObject: output_sound, left_filtered, right_filtered
    output_sound = stereo
endif

selectObject: output_sound
Rename: "vowel_" + preset_name$

# Output level policy.
pre_peak = Get absolute extremum: 0, 0, "None"
if output_level_mode = 2
    if pre_peak > ceiling_peak and pre_peak > 0
        Formula: "self * " + string$(ceiling_peak / pre_peak)
    endif
elsif output_level_mode = 3
    if pre_peak > 0
        Scale peak: ceiling_peak
    endif
endif
post_peak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "Output: ", selected$("Sound"), " | peak ", fixed$(pre_peak, 4), " -> ", fixed$(post_peak, 4)

# Cleanup engine objects.
removeObject: source, fg

# ------------------------------------------------------------
# Visualization
# ------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

if play_result
    selectObject: output_sound
    Play
endif

selectObject: output_sound
appendInfoLine: ""
appendInfoLine: "=== Done ==="

# ==============================================================================
# Visualization
# ==============================================================================
procedure drawVisualization
    Erase all

    Select outer viewport: 0, 8, 0.1, 0.65
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Dynamic Vowel Transitions v1.0: " + preset_name$

    selectObject: output_sound
    .nch = Get number of channels
    if .nch > 1
        .disp = Extract one channel: 1
    else
        .disp = Copy: "dvt_display_" + uid$
    endif

    # Waveform
    Select outer viewport: 0, 8, 0.75, 1.9
    Select inner viewport: 0.65, 7.6, 0.85, 1.8
    selectObject: .disp
    Colour: "{0.20, 0.45, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"

    # Spectrogram
    .max_spec = min(5000, nyquist - 80)
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.65, 7.6, 2.15, 4.45
    selectObject: .disp
    .spec = To Spectrogram: 0.03, .max_spec, 0.005, 20, "Gaussian"
    Paint: 0, 0, 0, .max_spec, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec

    # Overlay the actual synthesis-resonance trajectories used by FormantGrid.
    Select inner viewport: 0.65, 7.6, 2.15, 4.45
    Axes: 0, duration_s, 0, .max_spec
    Line width: 1.5
    for .p from 1 to n_traj - 1
        if trajectory_t[.p + 1] > trajectory_t[.p]
            Colour: "{1.0, 0.35, 0.35}"
            Draw line: trajectory_t[.p], trajectory_f1[.p], trajectory_t[.p + 1], trajectory_f1[.p + 1]
            Colour: "{0.35, 0.85, 0.35}"
            Draw line: trajectory_t[.p], trajectory_f2[.p], trajectory_t[.p + 1], trajectory_f2[.p + 1]
            Colour: "{0.35, 0.45, 1.0}"
            Draw line: trajectory_t[.p], trajectory_f3[.p], trajectory_t[.p + 1], trajectory_f3[.p + 1]
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # Summary
    Select outer viewport: 0, 8, 4.7, 5.25
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    if fundamental_hz > 0
        .source_label$ = "harmonic F0=" + fixed$(fundamental_hz, 0) + " Hz"
    else
        .source_label$ = "noise / whisper"
    endif
    Text: 0.5, "centre", 0.62, "half", "Source-filter engine | " + .source_label$ + " | BW x" + fixed$(formant_bandwidth_scale, 2)
    Text: 0.5, "centre", 0.28, "half", "Red/green/blue = actual synthesis F1/F2/F3 trajectories"

    removeObject: .disp
    Font size: 10
    Colour: "Black"
endproc
