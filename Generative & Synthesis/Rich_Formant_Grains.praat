# ============================================================
# Praat AudioTools - Rich Formant Grains v1.1
# Multi-bank source-filter granular synthesis
#
# Formants here are SYNTHESIS resonances. Grains create harmonic-rich
# or noise excitation; several resonance variants per vowel preserve
# the rich between-grain colour of the original instrument without
# using F1/F2/F3 as oscillator frequencies.
# ============================================================

form Rich Formant Grains v1.1
    comment === Musical controls ===
    optionmenu preset 1
        option Custom
        option Vowel Cloud
        option Whisper Choir
        option Robotic Speech
        option Alien Language
        option Gregorian Chant
        option Baby Babble
        option Synthetic Singing
        option Ghost Voices

    positive duration_s 5.0
    positive grain_density 35.0
    real base_frequency_hz 120
    real breath_noise_mix 0.05

    optionmenu spatial_mode 1
        option Mono
        option Stereo Spectral Split
        option Rotating Field
        option Dual-Band Whisper

    boolean edit_details 0
    boolean draw_visualization 1
    boolean play_result 1
endform

# ------------------------------------------------------------
# Defaults / presets
# ------------------------------------------------------------
sample_rate_hz = 44100
source_harmonics = 16
formant_bandwidth_scale = 1.0
min_grain_s = 0.04
max_grain_s = 0.12
output_level_mode = 2
ceiling_peak = 0.90
random_seed = 0
amp_shape = 1.0
preset_name$ = "Custom"

if preset = 2
    grain_density = 25
    base_frequency_hz = 110
    source_harmonics = 16
    breath_noise_mix = 0.05
    formant_bandwidth_scale = 1.0
    min_grain_s = 0.045
    max_grain_s = 0.13
    preset_name$ = "VowelCloud"
elsif preset = 3
    grain_density = 15
    base_frequency_hz = 180
    source_harmonics = 12
    breath_noise_mix = 1.0
    formant_bandwidth_scale = 1.35
    min_grain_s = 0.08
    max_grain_s = 0.23
    amp_shape = 0.8
    preset_name$ = "WhisperChoir"
elsif preset = 4
    grain_density = 40
    base_frequency_hz = 80
    source_harmonics = 20
    breath_noise_mix = 0.01
    formant_bandwidth_scale = 0.60
    min_grain_s = 0.03
    max_grain_s = 0.08
    amp_shape = 1.2
    preset_name$ = "RoboticSpeech"
elsif preset = 5
    grain_density = 30
    base_frequency_hz = 140
    source_harmonics = 18
    breath_noise_mix = 0.08
    formant_bandwidth_scale = 0.78
    min_grain_s = 0.04
    max_grain_s = 0.12
    preset_name$ = "AlienLanguage"
elsif preset = 6
    grain_density = 20
    base_frequency_hz = 90
    source_harmonics = 20
    breath_noise_mix = 0.025
    formant_bandwidth_scale = 0.92
    min_grain_s = 0.10
    max_grain_s = 0.30
    preset_name$ = "GregorianChant"
elsif preset = 7
    grain_density = 45
    base_frequency_hz = 250
    source_harmonics = 12
    breath_noise_mix = 0.04
    formant_bandwidth_scale = 0.78
    min_grain_s = 0.02
    max_grain_s = 0.06
    preset_name$ = "BabyBabble"
elsif preset = 8
    grain_density = 28
    base_frequency_hz = 130
    source_harmonics = 24
    breath_noise_mix = 0.015
    formant_bandwidth_scale = 0.82
    min_grain_s = 0.07
    max_grain_s = 0.18
    preset_name$ = "SyntheticSinging"
elsif preset = 9
    grain_density = 12
    base_frequency_hz = 160
    source_harmonics = 14
    breath_noise_mix = 0.18
    formant_bandwidth_scale = 1.20
    min_grain_s = 0.12
    max_grain_s = 0.37
    amp_shape = 0.7
    preset_name$ = "GhostVoices"
endif

if edit_details
    beginPause: "Rich Formant Grains v1.1 - Details"
        integer: "Sample rate (Hz)", sample_rate_hz
        integer: "Source harmonics", source_harmonics
        real: "Formant bandwidth scale", formant_bandwidth_scale
        positive: "Minimum grain duration (s)", min_grain_s
        positive: "Maximum grain duration (s)", max_grain_s
        integer: "Output mode (1 natural, 2 ceiling, 3 normalize)", output_level_mode
        real: "Output peak / ceiling", ceiling_peak
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# ------------------------------------------------------------
# Validation / setup
# ------------------------------------------------------------
if duration_s <= 0
    exitScript: "Duration must be positive."
endif
if sample_rate_hz < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
endif
if duration_s * sample_rate_hz < 8
    exitScript: "Duration is too short for the selected sample rate (need at least 8 samples)."
endif
if grain_density <= 0
    exitScript: "Grain density must be positive."
endif
if base_frequency_hz < 0
    exitScript: "Base frequency must be zero or positive."
endif
if source_harmonics < 1 or source_harmonics > 40
    exitScript: "Source harmonics must be between 1 and 40."
endif
if breath_noise_mix < 0 or breath_noise_mix > 1
    exitScript: "Breath noise mix must be between 0 and 1."
endif
if formant_bandwidth_scale <= 0
    exitScript: "Formant bandwidth scale must be positive."
endif
if min_grain_s <= 0 or max_grain_s <= 0 or max_grain_s < min_grain_s
    exitScript: "Grain durations must be positive and max >= min."
endif
if min_grain_s * sample_rate_hz < 8
    exitScript: "Minimum grain duration is too short for the selected sample rate (need at least 8 samples)."
endif
if output_level_mode < 1 or output_level_mode > 3
    exitScript: "Output mode must be 1 (natural), 2 (ceiling), or 3 (normalize)."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Output peak / ceiling must be in (0,1]."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (random) or a positive integer."
endif

nyquist = sample_rate_hz / 2
if base_frequency_hz > 0 and base_frequency_hz * 1.10 >= nyquist - 100
    exitScript: "Base frequency is too high: the +10 percent grain-F0 spread must remain below Nyquist minus 100 Hz."
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
else
    random_initializeSafelyAndUnpredictably ()
endif

two_pi = 2 * pi
uid$ = string$(randomInteger(10000, 99999))
variants = 3
n_vowels = 5
n_buses = n_vowels * variants

if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "StereoSpectralSplit"
elsif spatial_mode = 3
    spatial_name$ = "RotatingField"
else
    spatial_name$ = "DualBandWhisper"
endif

if output_level_mode = 1
    level_name$ = "Natural"
elsif output_level_mode = 2
    level_name$ = "Ceiling"
else
    level_name$ = "PeakNormalize"
endif

# ------------------------------------------------------------
# Base vowel resonances
# ------------------------------------------------------------
base_f1[1] = 730
base_f2[1] = 1090
base_f3[1] = 2440
vowel_name$[1] = "a"

base_f1[2] = 270
base_f2[2] = 2290
base_f3[2] = 3010
vowel_name$[2] = "i"

base_f1[3] = 300
base_f2[3] = 870
base_f3[3] = 2240
vowel_name$[3] = "u"

base_f1[4] = 530
base_f2[4] = 1840
base_f3[4] = 2480
vowel_name$[4] = "e"

base_f1[5] = 570
base_f2[5] = 840
base_f3[5] = 2410
vowel_name$[5] = "o"

bw1 = 90 * formant_bandwidth_scale
bw2 = 130 * formant_bandwidth_scale
bw3 = 180 * formant_bandwidth_scale

# Three resonance variants for each vowel. The normal presets use a
# small spread; Alien uses a much wider synthetic-vocal-tract spread.
for v from 1 to n_vowels
    for q from 1 to variants
        b = (v - 1) * variants + q
        if preset = 5
            var_f1[b] = base_f1[v] * randomUniform(0.58, 1.48)
            var_f2[b] = base_f2[v] * randomUniform(0.68, 1.42)
            var_f3[b] = base_f3[v] * randomUniform(0.78, 1.28)
        else
            if q = 1
                m1 = 0.970
                m2 = 0.985
                m3 = 0.990
            elsif q = 2
                m1 = 1.000
                m2 = 1.000
                m3 = 1.000
            else
                m1 = 1.030
                m2 = 1.015
                m3 = 1.010
            endif
            var_f1[b] = base_f1[v] * m1
            var_f2[b] = base_f2[v] * m2
            var_f3[b] = base_f3[v] * m3
        endif

        # Keep resonances ordered and inside Nyquist.
        var_f1[b] = max(80, min(var_f1[b], nyquist - 500))
        var_f2[b] = max(var_f1[b] + 80, min(var_f2[b], nyquist - 250))
        var_f3[b] = max(var_f2[b] + 100, min(var_f3[b], nyquist - 50))
        if var_f3[b] > nyquist - 40
            var_f3[b] = nyquist - 40
        endif
    endfor
endfor

# ------------------------------------------------------------
# Grain plan: fixed count, random duration/onset, vowel and resonance variant.
# Duration is drawn before onset so every grain fits completely inside the
# output and the requested duration distribution is not shortened near T.
# ------------------------------------------------------------
total_grains = round(duration_s * grain_density)
if total_grains < 1
    total_grains = 1
endif
realized_density = total_grains / duration_s
sum_f1 = 0
sum_f2 = 0
sum_f3 = 0
sum_f0 = 0
sum_dur = 0
min_real_dur = duration_s
max_real_dur = 0
for v from 1 to n_vowels
    vowel_count[v] = 0
endfor
for b from 1 to n_buses
    bus_count[b] = 0
endfor

effective_min_grain_s = min(min_grain_s, duration_s)
effective_max_grain_s = min(max_grain_s, duration_s)
if effective_max_grain_s < effective_min_grain_s
    effective_min_grain_s = effective_max_grain_s
endif

for g from 1 to total_grains
    if effective_max_grain_s > effective_min_grain_s
        grain_dur[g] = randomUniform(effective_min_grain_s, effective_max_grain_s)
    else
        grain_dur[g] = effective_min_grain_s
    endif
    grain_time[g] = randomUniform(0, max(0, duration_s - grain_dur[g]))

    # Preserve the original preset vowel populations.
    if preset = 3 or preset = 6
        r = randomUniform(0, 1)
        if r < 0.4
            v = 1
        elsif r < 0.7
            v = 3
        else
            v = 5
        endif
    elsif preset = 9
        if randomUniform(0, 1) < 0.5
            v = 2
        else
            v = 3
        endif
    else
        v = randomInteger(1, 5)
    endif

    q = randomInteger(1, variants)
    b = (v - 1) * variants + q
    grain_vowel[g] = v
    grain_variant[g] = q
    grain_bus[g] = b
    vowel_count[v] = vowel_count[v] + 1
    bus_count[b] = bus_count[b] + 1
    grain_f1[g] = var_f1[b]
    grain_f2[g] = var_f2[b]
    grain_f3[g] = var_f3[b]
    sum_f1 = sum_f1 + grain_f1[g]
    sum_f2 = sum_f2 + grain_f2[g]
    sum_f3 = sum_f3 + grain_f3[g]

    grain_f0[g] = base_frequency_hz * randomUniform(0.90, 1.10)
    grain_amp[g] = amp_shape * 0.40 / sqrt(max(12, grain_density)) * randomUniform(0.85, 1.15)
    sum_f0 = sum_f0 + grain_f0[g]
    sum_dur = sum_dur + grain_dur[g]
    min_real_dur = min(min_real_dur, grain_dur[g])
    max_real_dur = max(max_real_dur, grain_dur[g])
endfor

mean_f1 = sum_f1 / total_grains
mean_f2 = sum_f2 / total_grains
mean_f3 = sum_f3 / total_grains
mean_f0 = sum_f0 / total_grains
mean_dur = sum_dur / total_grains
rep_g = 1
rep_bus = grain_bus[rep_g]
rep_f0 = grain_f0[rep_g]
rep_dur = grain_dur[rep_g]
rep_f1 = grain_f1[rep_g]
rep_f2 = grain_f2[rep_g]
rep_f3 = grain_f3[rep_g]

clearinfo
writeInfoLine: "=== Rich Formant Grains v1.1 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s, 2), " s | target/realized density: ", fixed$(grain_density, 1), "/", fixed$(realized_density, 1), " grains/s"
appendInfoLine: "Total grains: ", total_grains, " | F0: ", fixed$(base_frequency_hz, 1), " Hz"
appendInfoLine: "Engine: fixed-count grain plan -> excitation -> 15 F1-F3 resonance buses -> spatial map"
appendInfoLine: "Mean synthesis resonances: ", fixed$(mean_f1, 0), " / ", fixed$(mean_f2, 0), " / ", fixed$(mean_f3, 0), " Hz"
appendInfoLine: ""

# ------------------------------------------------------------
# Create excitation buses
# ------------------------------------------------------------
for b from 1 to n_buses
    source_bus[b] = Create Sound from formula: "rfg_src_" + string$(b) + "_" + uid$, 1, 0, duration_s, sample_rate_hz, "0"
endfor

appendInfoLine: "[1/3] Building rich excitation cloud..."
# Each grain writes only into its own time interval. This keeps synthesis
# cost proportional to the amount of grain audio rather than evaluating
# every grain expression across the full output duration.
for g from 1 to total_grains
    b = grain_bus[g]
    gt = grain_time[g]
    gd = grain_dur[g]
    ge = min(duration_s, gt + gd)
    ga = grain_amp[g]
    gf0 = grain_f0[g]
    gt$ = fixed$(gt, 7)
    gd$ = fixed$(gd, 7)
    env$ = "sin(pi*(x-" + gt$ + ")/" + gd$ + ")"

    src$ = "0"
    if gf0 > 0 and breath_noise_mix < 0.999999
        max_h = min(source_harmonics, floor((nyquist - 100) / gf0))
        if max_h < 1
            max_h = 1
        endif
        for h from 1 to max_h
            coeff = 1 / (h ^ 0.85)
            src$ = src$ + "+" + fixed$(coeff, 7) + "*sin(2*pi*" + fixed$(h * gf0, 5) + "*(x-" + gt$ + "))"
        endfor
        src$ = "((1-" + fixed$(breath_noise_mix, 6) + ")*(" + src$ + ") + " + fixed$(breath_noise_mix, 6) + "*randomGauss(0,1))"
    else
        src$ = "randomGauss(0,1)"
    endif

    grain_formula$ = "self + " + fixed$(ga, 8) + "*(" + src$ + ")*" + env$
    selectObject: source_bus[b]
    Formula (part): gt, ge, 1, 1, grain_formula$
endfor

# ------------------------------------------------------------
# Filter each sub-bus through its synthetic resonance bank.
# One scalar RMS compensation per bus prevents all-pole filter gain
# from masquerading as musical dynamics.
# ------------------------------------------------------------
appendInfoLine: "[2/3] Applying synthetic F1-F3 resonance banks..."
for b from 1 to n_buses
    selectObject: source_bus[b]
    source_rms[b] = Get root-mean-square: 0, 0

    fg[b] = Create FormantGrid: "rfg_fg_" + string$(b) + "_" + uid$, 0, duration_s, 3, var_f1[b], 1000, bw1, 50
    selectObject: fg[b]
    for f from 1 to 3
        Remove formant points between: f, 0, duration_s
        Remove bandwidth points between: f, 0, duration_s
    endfor

    Add formant point: 1, 0, var_f1[b]
    Add formant point: 1, duration_s, var_f1[b]
    Add bandwidth point: 1, 0, bw1
    Add bandwidth point: 1, duration_s, bw1

    Add formant point: 2, 0, var_f2[b]
    Add formant point: 2, duration_s, var_f2[b]
    Add bandwidth point: 2, 0, bw2
    Add bandwidth point: 2, duration_s, bw2

    Add formant point: 3, 0, var_f3[b]
    Add formant point: 3, duration_s, var_f3[b]
    Add bandwidth point: 3, 0, bw3
    Add bandwidth point: 3, duration_s, bw3

    selectObject: source_bus[b]
    plusObject: fg[b]
    filtered_bus[b] = Filter (no scale)

    selectObject: filtered_bus[b]
    filtered_rms = Get root-mean-square: 0, 0
    if source_rms[b] > 0.000000000001 and filtered_rms > 0.000000000001
        bus_gain = source_rms[b] / filtered_rms
        Formula: "self * " + string$(bus_gain)
    endif
endfor

# ------------------------------------------------------------
# Sum buses
# ------------------------------------------------------------
mono_sound = Create Sound from formula: "RichFormant_" + preset_name$ + "_mono", 1, 0, duration_s, sample_rate_hz, "0"
for b from 1 to n_buses
    selectObject: mono_sound
    Formula: "self + object(" + string$(filtered_bus[b]) + ", x)"
endfor

selectObject: mono_sound
fade_in = min(0.03, duration_s / 4)
fade_out = min(0.05, duration_s / 4)
if fade_in > 0
    Formula: "if x < " + string$(fade_in) + " then self*(x/" + string$(fade_in) + ") else self fi"
endif
if fade_out > 0
    Formula: "if x > " + string$(duration_s - fade_out) + " then self*((" + string$(duration_s) + "-x)/" + string$(fade_out) + ") else self fi"
endif

# ------------------------------------------------------------
# Spatial processing
# ------------------------------------------------------------
appendInfoLine: "[3/3] Spatial/output stage..."
if spatial_mode = 1
    output_sound = mono_sound

elsif spatial_mode = 2
    selectObject: mono_sound
    left_sound = Copy: "rfg_left_" + uid$
    left_filtered = Filter (pass Hann band): 0, min(2500, nyquist - 100), 120
    removeObject: left_sound
    left_sound = left_filtered

    selectObject: mono_sound
    right_sound = Copy: "rfg_right_" + uid$
    right_filtered = Filter (pass Hann band): 150, min(4000, nyquist - 100), 120
    removeObject: right_sound
    right_sound = right_filtered

    selectObject: left_sound
    plusObject: right_sound
    output_sound = Combine to stereo
    removeObject: mono_sound, left_sound, right_sound

elsif spatial_mode = 3
    selectObject: mono_sound
    left_sound = Copy: "rfg_left_" + uid$
    Formula: "self * sqrt(max(0,0.5 + 0.5*cos(2*pi*0.12*x)))"

    selectObject: mono_sound
    right_sound = Copy: "rfg_right_" + uid$
    Formula: "self * sqrt(max(0,0.5 - 0.5*cos(2*pi*0.12*x)))"

    selectObject: left_sound
    plusObject: right_sound
    output_sound = Combine to stereo
    removeObject: mono_sound, left_sound, right_sound

else
    selectObject: mono_sound
    left_sound = Copy: "rfg_left_" + uid$
    left_filtered = Filter (pass Hann band): 100, min(3000, nyquist - 100), 80
    removeObject: left_sound
    left_sound = left_filtered
    Formula: "self * (0.8 + 0.1*sin(2*pi*0.2*x))"

    selectObject: mono_sound
    right_sound = Copy: "rfg_right_" + uid$
    right_filtered = Filter (pass Hann band): 80, min(3500, nyquist - 100), 80
    removeObject: right_sound
    right_sound = right_filtered
    Formula: "self * (0.7 + 0.2*cos(2*pi*0.25*x))"

    selectObject: left_sound
    plusObject: right_sound
    output_sound = Combine to stereo
    removeObject: mono_sound, left_sound, right_sound
endif

selectObject: output_sound
Rename: "RichFormant_" + preset_name$
pre_peak = Get absolute extremum: 0, 0, "None"
pre_rms = Get root-mean-square: 0, 0

if output_level_mode = 2
    if pre_peak > ceiling_peak and pre_peak > 0
        Formula: "self * " + string$(ceiling_peak / pre_peak)
    endif
elsif output_level_mode = 3
    if pre_peak > 0
        Scale peak: ceiling_peak
    endif
endif

selectObject: output_sound
out_peak = Get absolute extremum: 0, 0, "None"
out_rms = Get root-mean-square: 0, 0

# ------------------------------------------------------------
# Visualization-only measurement of one actual FormantGrid bus.
# An impulse probe gives a flat input spectrum; band-averaged output energy
# therefore measures the programmed filter response without source-spectrum bias.
# ------------------------------------------------------------
response_points = 0
if draw_visualization
    probe_dur = min(duration_s, 1.0)
    if probe_dur * sample_rate_hz >= 16
        probe = Create Sound from formula: "rfg_probe_" + uid$, 1, 0, probe_dur, sample_rate_hz, "if col = 1 then 1 else 0 fi"
        selectObject: probe
        plusObject: fg[rep_bus]
        probe_filtered = Filter (no scale)
        selectObject: probe_filtered
        probe_spectrum = To Spectrum: "yes"

        response_points = 48
        response_fmin = 80
        response_fmax = min(6000, nyquist - 100)
        response_ratio = exp(ln(response_fmax / response_fmin) / (response_points - 1))
        response_half_ratio = sqrt(response_ratio)
        response_max_db = -1000000
        for k from 1 to response_points
            rf = response_fmin * exp((k - 1) * ln(response_fmax / response_fmin) / (response_points - 1))
            lo = max(0, rf / response_half_ratio)
            hi = min(nyquist, rf * response_half_ratio)
            selectObject: probe_spectrum
            band_energy = Get band energy: lo, hi
            db = 10 * ln(max(band_energy, 1e-30)) / ln(10)
            response_freq[k] = rf
            response_db[k] = db
            response_max_db = max(response_max_db, db)
        endfor
        for k from 1 to response_points
            response_db[k] = max(-60, response_db[k] - response_max_db)
        endfor
        removeObject: probe, probe_filtered, probe_spectrum
    endif
endif

# Cleanup synthesis objects after the response measurement.
for b from 1 to n_buses
    removeObject: source_bus[b], fg[b], filtered_bus[b]
endfor

# ------------------------------------------------------------
# Visualization
# ------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    Erase all

    # Every text strip owns an explicit inner viewport. Praat Picture keeps
    # viewport state, so plots and titles must never rely on inherited state.

    # ---------------- Title ----------------
    Select outer viewport: 0, 8, 0.04, 0.32
    Select inner viewport: 0.18, 7.82, 0.06, 0.29
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Rich Formant Grains: " + preset_name$

    # ---------------- Process strip ----------------
    Select outer viewport: 0, 8, 0.34, 0.60
    Select inner viewport: 0.22, 7.78, 0.37, 0.57
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.30,0.30,0.30}"
    Text: 0.5, "centre", 0.5, "half", "grain plan  ->  excitation x window  ->  F1-F3 banks  ->  RMS match  ->  spatial map  ->  output"

    # ---------------- Panel A title ----------------
    Select outer viewport: 0, 8, 0.66, 0.86
    Select inner viewport: 0.10, 7.90, 0.68, 0.84
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  Grain plan: onset + duration + vowel + resonance variant; line length = duration"

    # ---------------- Panel A: actual grain plan ----------------
    Select outer viewport: 0, 8, 0.88, 2.05
    Select inner viewport: 0.78, 7.62, 0.98, 1.85
    Axes: 0, duration_s, 0.55, 5.45
    Paint rectangle: "{0.96,0.96,0.96}", 0, duration_s, 0.55, 5.45
    for .g from 1 to total_grains
        .v = grain_vowel[.g]
        .q = grain_variant[.g]
        .y = .v + (.q - 2) * 0.13
        if .v = 1
            Colour: "{0.78,0.34,0.30}"
        elsif .v = 2
            Colour: "{0.28,0.48,0.76}"
        elsif .v = 3
            Colour: "{0.28,0.68,0.48}"
        elsif .v = 4
            Colour: "{0.78,0.56,0.20}"
        else
            Colour: "{0.58,0.36,0.70}"
        endif
        Draw line: grain_time[.g], .y, grain_time[.g] + grain_dur[.g], .y
        Paint circle (mm): "{0.30,0.30,0.30}", grain_time[.g], .y, 0.75
    endfor
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 7.62, 0.98, 1.85
    Axes: 0, duration_s, 0.55, 5.45
    Font size: 8
    One mark left: 1, "yes", "yes", "no", "a"
    One mark left: 2, "yes", "yes", "no", "i"
    One mark left: 3, "yes", "yes", "no", "u"
    One mark left: 4, "yes", "yes", "no", "e"
    One mark left: 5, "yes", "yes", "no", "o"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 9
    Text left: "yes", "Vowel / variant"
    Text bottom: "yes", "Time (s)"

    # ---------------- Panel B title ----------------
    Select outer viewport: 0, 8, 2.18, 2.38
    Select inner viewport: 0.10, 7.90, 2.20, 2.36
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "B  One realized grain: half-sine window + harmonic/noise excitation"

    # ---------------- Panel B-left: grain window ----------------
    Select outer viewport: 0, 4, 2.40, 3.57
    Select inner viewport: 0.78, 3.72, 2.50, 3.37
    Axes: 0, rep_dur, 0, 1.05
    Paint rectangle: "{0.96,0.96,0.96}", 0, rep_dur, 0, 1.05
    .segments = 160
    .pt = 0
    .py = 0
    Colour: "{0.18,0.48,0.76}"
    Line width: 1.5
    for .k from 1 to .segments
        .t = .k * rep_dur / .segments
        .y = sin(pi * .t / rep_dur)
        Draw line: .pt, .py, .t, .y
        .pt = .t
        .py = .y
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 3.72, 2.50, 3.37
    Axes: 0, rep_dur, 0, 1.05
    Font size: 8
    Marks bottom: 3, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Local grain time (s)"
    Text left: "yes", "Window"

    # ---------------- Panel B-right: source spectrum model ----------------
    Select outer viewport: 4, 8, 2.40, 3.57
    Select inner viewport: 4.38, 7.62, 2.50, 3.37
    .srcMaxF = min(nyquist - 100, max(1000, rep_f0 * max(1, source_harmonics)))
    Axes: 0, .srcMaxF, 0, 1.05
    Paint rectangle: "{0.96,0.96,0.96}", 0, .srcMaxF, 0, 1.05
    if rep_f0 > 0 and breath_noise_mix < 0.999999
        .maxH = min(source_harmonics, floor((nyquist - 100) / rep_f0))
        .norm = max(0.000001, 1 - breath_noise_mix)
        Colour: "{0.78,0.38,0.20}"
        for .h from 1 to .maxH
            .a = .norm / (.h ^ 0.85)
            Draw line: .h * rep_f0, 0, .h * rep_f0, .a
        endfor
    endif
    if breath_noise_mix > 0
        Colour: "{0.45,0.45,0.45}"
        .noiseY = min(1, breath_noise_mix)
        Draw line: 0, .noiseY, .srcMaxF, .noiseY
    endif
    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.38, 7.62, 2.50, 3.37
    Axes: 0, .srcMaxF, 0, 1.05
    Font size: 8
    Marks bottom: 4, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Excitation frequency (Hz)"
    Text left: "yes", "Relative source amplitude"

    # B formula strip
    Select outer viewport: 0, 8, 3.58, 3.74
    Select inner viewport: 0.20, 7.80, 3.59, 3.73
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30,0.30,0.30}"
    if rep_f0 > 0
        Text: 0.5, "centre", 0.5, "half", "s(tau) = [(1-n) sum_h h^-0.85 sin(2*pi*h*f0*tau) + n*noise] * sin(pi*tau/D)"
    else
        Text: 0.5, "centre", 0.5, "half", "f0 = 0: noise excitation * sin(pi*tau/D)"
    endif

    # ---------------- Panel C title ----------------
    Select outer viewport: 0, 8, 3.82, 4.02
    Select inner viewport: 0.10, 7.90, 3.84, 4.00
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "C  Source-filter stage: measured FormantGrid response + spatial mapping"

    # ---------------- Panel C-left: measured response on log frequency ----------------
    Select outer viewport: 0, 4.4, 4.04, 5.34
    Select inner viewport: 0.80, 4.08, 4.14, 5.12
    .logMin = log10(80)
    .logMax = log10(min(6000, nyquist - 100))
    Axes: .logMin, .logMax, -60, 3
    Paint rectangle: "{0.96,0.96,0.96}", .logMin, .logMax, -60, 3
    if response_points > 1
        Colour: "{0.18,0.48,0.76}"
        Line width: 1.5
        for .k from 2 to response_points
            Draw line: log10(response_freq[.k-1]), response_db[.k-1], log10(response_freq[.k]), response_db[.k]
        endfor
        Line width: 1
    endif
    Colour: "{0.78,0.34,0.30}"
    Draw line: log10(rep_f1), -60, log10(rep_f1), 1
    Colour: "{0.28,0.68,0.48}"
    Draw line: log10(rep_f2), -60, log10(rep_f2), 1
    Colour: "{0.58,0.36,0.70}"
    Draw line: log10(rep_f3), -60, log10(rep_f3), 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.80, 4.08, 4.14, 5.12
    Axes: .logMin, .logMax, -60, 3
    Font size: 7
    if 100 <= min(6000, nyquist - 100)
        One mark bottom: log10(100), "yes", "yes", "no", "100"
    endif
    if 200 <= min(6000, nyquist - 100)
        One mark bottom: log10(200), "yes", "yes", "no", "200"
    endif
    if 500 <= min(6000, nyquist - 100)
        One mark bottom: log10(500), "yes", "yes", "no", "500"
    endif
    if 1000 <= min(6000, nyquist - 100)
        One mark bottom: log10(1000), "yes", "yes", "no", "1k"
    endif
    if 2000 <= min(6000, nyquist - 100)
        One mark bottom: log10(2000), "yes", "yes", "no", "2k"
    endif
    if 5000 <= min(6000, nyquist - 100)
        One mark bottom: log10(5000), "yes", "yes", "no", "5k"
    endif
    Marks left every: 1, 20, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Frequency (Hz, log)"
    Text left: "yes", "Relative response (dB)"

    # ---------------- Panel C-right: actual spatial rule ----------------
    Select outer viewport: 4.4, 8, 4.04, 5.34
    Select inner viewport: 4.78, 7.62, 4.14, 5.12
    if spatial_mode = 3
        Axes: 0, duration_s, 0, 1.05
        Paint rectangle: "{0.96,0.96,0.96}", 0, duration_s, 0, 1.05
        .prevT = 0
        .prevL = 1
        .prevR = 0
        for .k from 1 to 160
            .t = .k * duration_s / 160
            .l = sqrt(max(0, 0.5 + 0.5*cos(2*pi*0.12*.t)))
            .r = sqrt(max(0, 0.5 - 0.5*cos(2*pi*0.12*.t)))
            Colour: "{0.18,0.48,0.76}"
            Draw line: .prevT, .prevL, .t, .l
            Colour: "{0.78,0.38,0.20}"
            Draw line: .prevT, .prevR, .t, .r
            .prevT = .t
            .prevL = .l
            .prevR = .r
        endfor
        Colour: "Black"
        Draw inner box
        Select inner viewport: 4.78, 7.62, 4.14, 5.12
        Axes: 0, duration_s, 0, 1.05
        Font size: 7
        Marks bottom: 4, "yes", "yes", "no"
        Marks left: 3, "yes", "yes", "no"
        Font size: 9
        Text bottom: "yes", "Time (s)"
        Text left: "yes", "L/R gain"
    elsif spatial_mode = 2 or spatial_mode = 4
        .spMax = min(4500, nyquist - 100)
        Axes: 0, .spMax, 0.4, 2.6
        Paint rectangle: "{0.96,0.96,0.96}", 0, .spMax, 0.4, 2.6
        Colour: "{0.18,0.48,0.76}"
        if spatial_mode = 2
            Draw line: 0, 2, min(2500,.spMax), 2
            Colour: "{0.78,0.38,0.20}"
            Draw line: min(150,.spMax), 1, min(4000,.spMax), 1
        else
            Draw line: min(100,.spMax), 2, min(3000,.spMax), 2
            Colour: "{0.78,0.38,0.20}"
            Draw line: min(80,.spMax), 1, min(3500,.spMax), 1
        endif
        Colour: "Black"
        Draw inner box
        Select inner viewport: 4.78, 7.62, 4.14, 5.12
        Axes: 0, .spMax, 0.4, 2.6
        Font size: 7
        One mark left: 1, "yes", "yes", "no", "R"
        One mark left: 2, "yes", "yes", "no", "L"
        Marks bottom: 4, "yes", "yes", "no"
        Font size: 9
        Text bottom: "yes", "Passband (Hz)"
        Text left: "yes", "Channel"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96,0.96,0.96}", 0, 1, 0, 1
        Font size: 10
        Colour: "{0.25,0.25,0.25}"
        Text: 0.5, "centre", 0.62, "half", "Mono routing"
        Font size: 8
        Text: 0.5, "centre", 0.38, "half", "sum 15 filtered buses -> one channel"
        Colour: "Black"
        Draw inner box
    endif

    # C annotation strip
    Select outer viewport: 0, 8, 5.35, 5.53
    Select inner viewport: 0.18, 7.82, 5.36, 5.52
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30,0.30,0.30}"
    Text: 0.02, "left", 0.5, "half", "Rep bus F1/F2/F3 " + fixed$(rep_f1,0) + "/" + fixed$(rep_f2,0) + "/" + fixed$(rep_f3,0) + " Hz | BW " + fixed$(bw1,0) + "/" + fixed$(bw2,0) + "/" + fixed$(bw3,0) + " Hz | spatial: " + spatial_name$

    # ---------------- Panel D title ----------------
    Select outer viewport: 0, 8, 5.60, 5.80
    Select inner viewport: 0.10, 7.90, 5.62, 5.78
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "D  Measured output (verification only)"

    selectObject: output_sound
    .channels = Get number of channels
    if .channels = 1
        Select outer viewport: 0, 8, 5.82, 6.82
        Select inner viewport: 0.78, 7.62, 5.91, 6.63
        Draw: 0, 0, -1, 1, "no", "Curve"
        Select inner viewport: 0.78, 7.62, 5.91, 6.63
        Axes: 0, duration_s, -1, 1
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.78, 7.62, 5.91, 6.63
        Axes: 0, duration_s, -1, 1
        Font size: 7
        Marks left: 3, "yes", "yes", "no"
        Marks bottom: 5, "yes", "yes", "no"
        Font size: 9
        Text left: "yes", "Amplitude"
        Text bottom: "yes", "Time (s)"
    else
        .leftPlot = Extract one channel: 1
        selectObject: output_sound
        .rightPlot = Extract one channel: 2

        Select outer viewport: 0, 8, 5.82, 6.36
        Select inner viewport: 0.78, 7.62, 5.88, 6.25
        selectObject: .leftPlot
        Draw: 0, 0, -1, 1, "no", "Curve"
        Select inner viewport: 0.78, 7.62, 5.88, 6.25
        Axes: 0, duration_s, -1, 1
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.78, 7.62, 5.88, 6.25
        Axes: 0, duration_s, -1, 1
        Font size: 7
        Marks left: 3, "yes", "yes", "no"
        Text left: "yes", "L"

        Select outer viewport: 0, 8, 6.38, 6.92
        Select inner viewport: 0.78, 7.62, 6.44, 6.81
        selectObject: .rightPlot
        Draw: 0, 0, -1, 1, "no", "Curve"
        Select inner viewport: 0.78, 7.62, 6.44, 6.81
        Axes: 0, duration_s, -1, 1
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.78, 7.62, 6.44, 6.81
        Axes: 0, duration_s, -1, 1
        Font size: 7
        Marks left: 3, "yes", "yes", "no"
        Marks bottom: 5, "yes", "yes", "no"
        Text left: "yes", "R"
        Font size: 9
        Text bottom: "yes", "Time (s)"
        removeObject: .leftPlot, .rightPlot
    endif

    # ---------------- QC summary ----------------
    Select outer viewport: 0, 8, 7.08, 7.88
    Select inner viewport: 0.18, 7.82, 7.12, 7.84
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.18, 7.82, 7.12, 7.84
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.28,0.28,0.28}"
    Text: 0.02, "left", 0.70, "half", "QC  grains " + string$(total_grains) + " | density " + fixed$(grain_density,1) + "/" + fixed$(realized_density,1) + " /s"
    Text: 0.35, "left", 0.70, "half", "Duration mean/range " + fixed$(mean_dur,3) + " | " + fixed$(min_real_dur,3) + ".." + fixed$(max_real_dur,3) + " s"
    Text: 0.69, "left", 0.70, "half", "Source F0 mean " + fixed$(mean_f0,1) + " Hz | noise " + fixed$(breath_noise_mix,2)
    Text: 0.02, "left", 0.26, "half", "Mean F1/F2/F3 " + fixed$(mean_f1,0) + "/" + fixed$(mean_f2,0) + "/" + fixed$(mean_f3,0) + " Hz"
    Text: 0.35, "left", 0.26, "half", spatial_name$ + " | " + level_name$ + " | Nyquist " + fixed$(nyquist,0) + " Hz"
    Text: 0.69, "left", 0.26, "half", "Peak/RMS " + fixed$(out_peak,3) + "/" + fixed$(out_rms,3) + " | prepeak " + fixed$(pre_peak,3)

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Formants are synthesis resonances, not oscillator frequencies; visualization shows one measured filter response."
appendInfoLine: "Peak: ", fixed$(pre_peak,4), " -> ", fixed$(out_peak,4)
appendInfoLine: "RMS:  ", fixed$(pre_rms,5), " -> ", fixed$(out_rms,5)

if play_result
    selectObject: output_sound
    Play
endif

if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif
selectObject: output_sound
