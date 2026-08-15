# ============================================================
# Praat AudioTools - Dynamic Vowel Transitions v1.1 reviewed
# True dynamic source-filter vowel synthesis
#
# F1/F2/F3 are SYNTHESIS RESONANCES in a time-varying FormantGrid.
# They are not oscillator frequencies. A harmonic or noise excitation
# is created first, then filtered through the moving vocal-tract model.
#
# v1.1 reviewed:
#   - Preserved the genuine time-varying FormantGrid source-filter engine.
#   - Compact laptop-safe launcher + optional advanced vowel/source page.
#   - Added reproducible Random_seed for breath/noise excitation.
#   - Source is RMS-normalized after harmonic/noise mixing so Breathiness
#     changes spectral character rather than silently changing source level.
#   - Output level mode 1 renamed Reference RMS: the global FormantGrid gain
#     compensation explicitly matches filtered RMS to source RMS once.
#   - Replaced post-filter spectral-split stereo with signal-preserving spatial
#     modes: short-delay stereo, exact equal-power rotation, transition pan.
#   - Combined edge fades into one Formula.
#   - Added practical 0.45*Fs formant headroom; if needed, all formants and
#     bandwidths are scaled together, preserving ratios better than per-formant
#     clipping/reordering.
#   - Preset names made mechanism-faithful for synthetic/extreme cases.
#   - Visualization rebuilt around actual formant paths, actual excitation,
#     measured spectrogram + model overlay, measured output, and QC.
# ============================================================

form Dynamic Vowel Transitions v1.1
    optionmenu Preset 1
        option Custom (baseline values)
        option A to I
        option I to U
        option U to A
        option A to E to I
        option Vowel Cycle
        option Formant Glissando
        option Whisper Morph
        option High-F0 Singing Morph
        option Narrow-Band Robot Morph
        option Extreme Formant Morph

    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    real Fundamental_hz 120

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Voice
        option Rotating Voice
        option Transition Pan

    optionmenu Output_level_mode 1
        option Reference RMS
        option Safety ceiling
        option Peak normalize

    boolean Edit_vowel_source_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ------------------------------------------------------------
# Detailed defaults (optional advanced page)
# ------------------------------------------------------------
start_f1 = 730
start_f2 = 1090
start_f3 = 2440
end_f1 = 270
end_f2 = 2290
end_f3 = 3010
formant_bandwidth_scale = 1.0
source_harmonics = 18
breathiness = 0.04
random_seed = 0
edge_fade_s = 0.02
ceiling_peak = 0.90

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
    preset_name$ = "A to I"
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
    preset_name$ = "I to U"
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
    preset_name$ = "U to A"
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
    preset_name$ = "A to E to I"
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
    preset_name$ = "Vowel Cycle"
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
    preset_name$ = "Formant Glissando"
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
    preset_name$ = "Whisper Morph"
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
    preset_name$ = "High-F0 Singing Morph"
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
    preset_name$ = "Narrow-Band Robot Morph"
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
    preset_name$ = "Extreme Formant Morph"
endif

# ------------------------------------------------------------
# Optional advanced vowel/source page
# Preset values are already applied, so this page fine-tunes the preset.
# ------------------------------------------------------------
if edit_vowel_source_details
    beginPause: "Dynamic Vowel Transitions - Vowel & Source Details"
        comment: "For A-E-I and Vowel Cycle presets, start/end fields are not used; source settings still apply."
        positive: "Start f1 (Hz)", start_f1
        positive: "Start f2 (Hz)", start_f2
        positive: "Start f3 (Hz)", start_f3
        positive: "End f1 (Hz)", end_f1
        positive: "End f2 (Hz)", end_f2
        positive: "End f3 (Hz)", end_f3
        positive: "Formant bandwidth scale", formant_bandwidth_scale
        integer: "Source harmonics", source_harmonics
        real: "Breathiness (0..1)", breathiness
        integer: "Random seed (0 = unpredictable)", random_seed
        real: "Edge fade s", edge_fade_s
        positive: "Ceiling peak", ceiling_peak
    endPause: "Run", 1
endif

# ------------------------------------------------------------
# Validation / setup
# ------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz for this three-formant model."
endif
if fundamental_hz < 0
    exitScript: "Fundamental frequency cannot be negative; use 0 for whisper/noise."
endif
if source_harmonics < 1 or source_harmonics > 128
    exitScript: "Source harmonics must be between 1 and 128."
endif
if formant_bandwidth_scale <= 0 or formant_bandwidth_scale > 5
    exitScript: "Formant bandwidth scale must be > 0 and <= 5."
endif
if breathiness < 0 or breathiness > 1
    exitScript: "Breathiness must be between 0 and 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling peak must be > 0 and <= 1."
endif

# Custom endpoints must describe ordered positive resonance triplets.
if multi_vowel = 0
    if start_f1 <= 0 or start_f2 <= start_f1 or start_f3 <= start_f2
        exitScript: "Start formants must satisfy 0 < F1 < F2 < F3."
    endif
    if end_f1 <= 0 or end_f2 <= end_f1 or end_f3 <= end_f2
        exitScript: "End formants must satisfy 0 < F1 < F2 < F3."
    endif
endif

two_pi = 2*pi
nyquist = sample_rate_Hz/2
safeTop = 0.45*sample_rate_Hz
uid$ = string$(randomInteger(10000,99999))

if fundamental_hz > 0 and fundamental_hz >= safeTop
    exitScript: "Fundamental frequency is too high for the requested sample rate."
endif

# If the requested F3 exceeds practical headroom, scale ALL formants together.
# This preserves the vowel-space ratios better than independent clipping.
maxRequestedF3 = max(start_f3,end_f3)
if multi_vowel = 1
    maxRequestedF3 = 0
    for vv to num_vowels
        if vowel_f1[vv] <= 0 or vowel_f2[vv] <= vowel_f1[vv] or vowel_f3[vv] <= vowel_f2[vv]
            exitScript: "Internal multi-vowel preset has invalid F1/F2/F3 ordering."
        endif
        maxRequestedF3 = max(maxRequestedF3,vowel_f3[vv])
    endfor
endif

formantFrequencyScale = min(1,safeTop/maxRequestedF3)
formantsAdjusted = formantFrequencyScale < 0.999999

# Bandwidths are synthesis parameters, not measured LPC bandwidths.
# Scale them with frequency only when sample-rate headroom forces a formant scale.
bw1 = 70*formant_bandwidth_scale*formantFrequencyScale
bw2 = 100*formant_bandwidth_scale*formantFrequencyScale
bw3 = 150*formant_bandwidth_scale*formantFrequencyScale

# Smooth trajectory: dense enough for filtering and figure overlay, capped for dispatch cost.
trajectory_step = max(0.005,duration_s/700)
n_traj = ceiling(duration_s/trajectory_step)+1

if spatial_mode = 1
    spatialLabel$ = "Mono"
elsif spatial_mode = 2
    spatialLabel$ = "Stereo Voice"
elsif spatial_mode = 3
    spatialLabel$ = "Rotating Voice"
else
    spatialLabel$ = "Transition Pan"
endif

if output_level_mode = 1
    levelLabel$ = "Reference RMS"
elsif output_level_mode = 2
    levelLabel$ = "Safety ceiling"
else
    levelLabel$ = "Peak normalize"
endif

if random_seed > 0
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

clearinfo
writeInfoLine: "=== Dynamic Vowel Transitions v1.1 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Engine: excitation -> time-varying synthetic FormantGrid"
appendInfoLine: "Duration: ", fixed$(duration_s,3), " s | SR: ", sample_rate_Hz, " Hz"
if fundamental_hz > 0
    appendInfoLine: "Source: harmonic, F0=", fixed$(fundamental_hz,2), " Hz, requested harmonics=", source_harmonics
else
    appendInfoLine: "Source: noise / whisper"
endif
appendInfoLine: "Bandwidth scale: ", fixed$(formant_bandwidth_scale,2), " | Breathiness: ", fixed$(breathiness,2)
appendInfoLine: "Spatial: ", spatialLabel$, " | Output level: ", levelLabel$
appendInfoLine: "Randomness: ", seedLabel$
if formantsAdjusted
    appendInfoLine: "All formant frequencies/bandwidths scaled by ", fixed$(formantFrequencyScale,4), " for 0.45*Fs headroom."
endif
appendInfoLine: ""

# ------------------------------------------------------------
# Build source excitation.
# ------------------------------------------------------------
appendInfoLine: "[1/4] Building excitation..."

seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
endif

if fundamental_hz > 0
    source_formula$ = "0"
    valid_harmonics = 0
    for h from 1 to source_harmonics
        hf = h*fundamental_hz
        if hf < safeTop
            amp = 1/(h^1.15)
            source_formula$ = source_formula$ + " + " + fixed$(amp,8) + "*sin(two_pi*" + string$(hf) + "*x)"
            valid_harmonics = valid_harmonics + 1
        endif
    endfor
    if valid_harmonics < 1
        exitScript: "No valid source harmonics below practical Nyquist headroom."
    endif

    source = Create Sound from formula: "dvt_source_" + uid$, 1, 0, duration_s, sample_rate_Hz, source_formula$
    selectObject: source

    # Add breath noise without turning Breathiness into a gain control.
    if breathiness > 0
        Formula: "self*(1-breathiness) + randomGauss(0,1)*breathiness"
    endif
else
    valid_harmonics = 0
    source = Create Sound from formula: "dvt_source_" + uid$, 1, 0, duration_s, sample_rate_Hz, "randomGauss(0,1)"
endif

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# Common excitation reference level AFTER harmonic/noise mixing.
selectObject: source
sourceRmsRaw = Get root-mean-square: 0,0
sourceTargetRMS = 0.12
if sourceRmsRaw <= 0
    exitScript: "Excitation has zero RMS."
endif
Formula: "self * (sourceTargetRMS/sourceRmsRaw)"
source_rms = Get root-mean-square: 0,0
source_peak = Get absolute extremum: 0,0,"None"

if fundamental_hz > 0
    appendInfoLine: "  Valid harmonics: ", valid_harmonics, " | source RMS: ", fixed$(source_rms,4)
else
    appendInfoLine: "  Whisper source RMS: ", fixed$(source_rms,4)
endif

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

    # Apply one common headroom scale; preserve formant ordering/ratios.
    f1_here = f1_here*formantFrequencyScale
    f2_here = f2_here*formantFrequencyScale
    f3_here = f3_here*formantFrequencyScale

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

# FormantGrid all-pole gain can be large. Apply ONE global reference scalar.
# This preserves the transition's internal spectral/intensity evolution.
selectObject: filtered
filtered_rms_raw = Get root-mean-square: 0,0
if source_rms > 1e-12 and filtered_rms_raw > 1e-12
    global_comp = source_rms/filtered_rms_raw
    Formula: "self*global_comp"
else
    global_comp = 1
endif
referenceRMS = Get root-mean-square: 0,0

# Short edge protection only; no musical envelope.
actualFade = min(edge_fade_s,0.20*duration_s)
if actualFade > 0
    fadeOutStart = duration_s-actualFade
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

# ------------------------------------------------------------
# Signal-preserving spatial processing.
# ------------------------------------------------------------
appendInfoLine: "[4/4] Spatial/output stage..."
output_sound = filtered
sqrtTwo = sqrt(2)

if spatial_mode = 2
    # Stereo Voice: subtle interaural decorrelation without spectral filtering.
    monoID = output_sound
    stereoDelay = min(0.004,0.02*duration_s)

    selectObject: monoID
    left_sound = Copy: "dvt_left_" + uid$
    Formula: "self/sqrtTwo"

    selectObject: monoID
    right_sound = Copy: "dvt_right_" + uid$
    Formula: "object(monoID,x-stereoDelay,1)/sqrtTwo"

    selectObject: left_sound
    plusObject: right_sound
    Combine to stereo
    stereo = selected("Sound")
    removeObject: monoID,left_sound,right_sound
    output_sound = stereo

elsif spatial_mode = 3
    # Exact equal-power rotation of the complete vowel signal.
    monoID = output_sound
    rotationRate = 0.15

    selectObject: monoID
    left_sound = Copy: "dvt_left_" + uid$
    Formula: "self*sqrt(0.5*(1-sin(two_pi*rotationRate*x)))"

    selectObject: monoID
    right_sound = Copy: "dvt_right_" + uid$
    Formula: "self*sqrt(0.5*(1+sin(two_pi*rotationRate*x)))"

    selectObject: left_sound
    plusObject: right_sound
    Combine to stereo
    stereo = selected("Sound")
    removeObject: monoID,left_sound,right_sound
    output_sound = stereo

elsif spatial_mode = 4
    # Equal-power left-to-right pan tied to overall transition progress.
    monoID = output_sound

    selectObject: monoID
    left_sound = Copy: "dvt_left_" + uid$
    Formula: "self*sqrt(1-(0.05+0.90*0.5*(1-cos(pi*x/duration_s))))"

    selectObject: monoID
    right_sound = Copy: "dvt_right_" + uid$
    Formula: "self*sqrt(0.05+0.90*0.5*(1-cos(pi*x/duration_s)))"

    selectObject: left_sound
    plusObject: right_sound
    Combine to stereo
    stereo = selected("Sound")
    removeObject: monoID,left_sound,right_sound
    output_sound = stereo
endif

# Output level policy is applied AFTER spatialization.
selectObject: output_sound
pre_peak = Get absolute extremum: 0,0,"None"
pre_rms = Get root-mean-square: 0,0

if output_level_mode = 2
    if pre_peak > ceiling_peak and pre_peak > 0
        Formula: "self*(ceiling_peak/pre_peak)"
    endif
elsif output_level_mode = 3
    if pre_peak > 0
        Scale peak: ceiling_peak
    endif
endif

post_peak = Get absolute extremum: 0,0,"None"
post_rms = Get root-mean-square: 0,0
finalChannels = Get number of channels

safePreset$ = replace$(preset_name$," ","_",0)
Rename: "vowel_" + safePreset$

appendInfoLine: "Output: ", selected$("Sound"), " | peak ", fixed$(pre_peak,4), " -> ", fixed$(post_peak,4)
appendInfoLine: "Reference RMS scalar: ", fixed$(global_comp,6), " | final RMS: ", fixed$(post_rms,4)

# ------------------------------------------------------------
# Visualization
# ------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ============================================================================== 
# Visualization
# ============================================================================== 
procedure drawVisualization
    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .f1c$ = "{0.82,0.26,0.22}"
    .f2c$ = "{0.24,0.60,0.34}"
    .f3c$ = "{0.24,0.38,0.82}"
    .outc$ = "{0.72,0.38,0.18}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half","DYNAMIC VOWEL TRANSITIONS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    if fundamental_hz > 0
        .sourceLabel$ = "harmonic F0 " + fixed$(fundamental_hz,0) + " Hz | " + string$(valid_harmonics) + " harmonics"
    else
        .sourceLabel$ = "noise / whisper excitation"
    endif
    Text: 0.5,"centre",0.68,"half",.sourceLabel$ + " | breath " + fixed$(breathiness,2) + " | " + spatialLabel$
    Text: 0.5,"centre",0.20,"half","excitation -> moving F1/F2/F3 all-pole filter -> one global RMS reference -> spatial render"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL SYNTHESIS FORMANT PATHS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.76,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half","A  SYNTHESIS RESONANCE TRAJECTORIES | exact FormantGrid paths"

    .formantMax = max(trajectory_f3[1],trajectory_f3[n_traj])
    .formantMax = max(.formantMax,maxRequestedF3*formantFrequencyScale)
    .formantTop = min(safeTop,1.08*.formantMax)
    .formantTop = max(1000,.formantTop)

    Select inner viewport: .left,.right,1.05,2.07
    Axes: 0,duration_s,0,.formantTop
    Paint rectangle: .bg$,0,duration_s,0,.formantTop

    Colour: .grid$
    Dotted line
    if multi_vowel = 1
        for .vv from 2 to num_vowels-1
            .vt = duration_s*(.vv-1)/(num_vowels-1)
            Draw line: .vt,0,.vt,.formantTop
        endfor
    endif
    Plain line

    Line width: 1.5
    for .p from 1 to n_traj-1
        if trajectory_t[.p+1] > trajectory_t[.p]
            Colour: .f1c$
            Draw line: trajectory_t[.p],trajectory_f1[.p],trajectory_t[.p+1],trajectory_f1[.p+1]
            Colour: .f2c$
            Draw line: trajectory_t[.p],trajectory_f2[.p],trajectory_t[.p+1],trajectory_f2[.p+1]
            Colour: .f3c$
            Draw line: trajectory_t[.p],trajectory_f3[.p],trajectory_t[.p+1],trajectory_f3[.p+1]
        endif
    endfor
    Line width: 1

    Axes: 0,duration_s,0,.formantTop
    Font size: 5
    Colour: .f1c$
    Text: 0.015*duration_s,"left",trajectory_f1[1],"half","F1"
    Colour: .f2c$
    Text: 0.015*duration_s,"left",trajectory_f2[1],"half","F2"
    Colour: .f3c$
    Text: 0.015*duration_s,"left",trajectory_f3[1],"half","F3"

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL EXCITATION SPECTRUM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.23,2.45
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half","B  ACTUAL EXCITATION | measured source spectrum before FormantGrid"

    .maxSpec = min(6000,safeTop)
    selectObject: source
    To Spectrum: "yes"
    .sourceSpectrum = selected("Spectrum")

    Select inner viewport: .left,.right,2.52,3.30
    selectObject: .sourceSpectrum
    Colour: "{0.28,0.45,0.68}"
    Draw: 0,.maxSpec,0,0,"yes"
    removeObject: .sourceSpectrum

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: output_sound
        Copy: "dvt_display_" + uid$
        .disp = selected("Sound")
    else
        selectObject: output_sound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0,0

        selectObject: output_sound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0,0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # -----------------------------------------------------------------------
    # PANEL C: MODEL -> MEASUREMENT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.55,3.77
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half","C  MODEL -> MEASUREMENT | measured spectrogram + exact synthesis trajectories"

    selectObject: .disp
    .specStep = max(0.002,duration_s/1100)
    To Spectrogram: 0.03,.maxSpec,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,3.84,5.02
    selectObject: .spec
    Paint: 0,0,0,.maxSpec,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.maxSpec
    Line width: 1.3
    for .p from 1 to n_traj-1
        if trajectory_t[.p+1] > trajectory_t[.p]
            if trajectory_f1[.p] <= .maxSpec and trajectory_f1[.p+1] <= .maxSpec
                Colour: .f1c$
                Draw line: trajectory_t[.p],trajectory_f1[.p],trajectory_t[.p+1],trajectory_f1[.p+1]
            endif
            if trajectory_f2[.p] <= .maxSpec and trajectory_f2[.p+1] <= .maxSpec
                Colour: .f2c$
                Draw line: trajectory_t[.p],trajectory_f2[.p],trajectory_t[.p+1],trajectory_f2[.p+1]
            endif
            if trajectory_f3[.p] <= .maxSpec and trajectory_f3[.p+1] <= .maxSpec
                Colour: .f3c$
                Draw line: trajectory_t[.p],trajectory_f3[.p],trajectory_t[.p+1],trajectory_f3[.p+1]
            endif
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.18,5.40
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half","D  MEASURED OUTPUT | representative channel"

    selectObject: .disp
    .wavePeak = Get absolute extremum: 0,0,"None"
    if .wavePeak < 0.001
        .wavePeak = 0.001
    endif
    .waveY = 1.05*.wavePeak

    Select inner viewport: .left,.right,5.47,6.20
    Axes: 0,duration_s,-.waveY,.waveY
    Paint rectangle: .bg$,0,duration_s,-.waveY,.waveY
    selectObject: .disp
    Colour: .outc$
    Draw: 0,0,-.waveY,.waveY,"no","Curve"
    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Amplitude"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.46,7.80
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1
    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.82,"half","MODEL  |  excitation -> 3 moving all-pole resonances -> one global RMS reference scalar"

    Text: 0.02,"left",0.61,"half","SOURCE  |  " + .sourceLabel$ + "  |  breath " + fixed$(breathiness,2) + "  |  " + seedLabel$

    Text: 0.02,"left",0.40,"half","FILTER  |  BW " + fixed$(bw1,0) + "/" + fixed$(bw2,0) + "/" + fixed$(bw3,0) + " Hz  |  formant scale " + fixed$(formantFrequencyScale,3)

    Text: 0.02,"left",0.19,"half","OUTPUT  |  pre-peak " + fixed$(pre_peak,3) + "  |  final peak " + fixed$(post_peak,3) + "  |  RMS " + fixed$(post_rms,4) + "  |  " + spatialLabel$ + "  |  " + levelLabel$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1
    Colour: "Black"
    Line width: 1
    Font size: 10
endproc

# Cleanup retained engine objects after optional visualization.
removeObject: source,fg

if play_result
    selectObject: output_sound
    Play
endif

selectObject: output_sound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
