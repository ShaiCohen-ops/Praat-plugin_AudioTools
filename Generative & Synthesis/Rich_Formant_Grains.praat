# ============================================================
# Praat AudioTools - Rich Formant Grains v1.0
# Multi-bank source-filter granular synthesis
#
# Formants here are SYNTHESIS resonances. Grains create harmonic-rich
# or noise excitation; several resonance variants per vowel preserve
# the rich between-grain colour of the original instrument without
# using F1/F2/F3 as oscillator frequencies.
# ============================================================

form Rich Formant Grains v1.0
    comment === Preset ===
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

    comment === Timing ===
    positive duration_s 5.0
    integer sample_rate_hz 44100
    positive grain_density 35.0

    comment === Source ===
    real base_frequency_hz 120
    integer source_harmonics 16
    real breath_noise_mix 0.05

    comment === Synthesis Formants ===
    positive formant_bandwidth_scale 1.0

    comment === Spatialization ===
    optionmenu spatial_mode 1
        option Mono
        option Stereo Choir
        option Rotating Voices
        option Binaural Whisper

    comment === Output ===
    optionmenu output_level_mode 2
        option Natural level
        option Safety ceiling
        option Peak normalize
    positive ceiling_peak 0.90
    integer random_seed 0
    boolean draw_visualization 1
    boolean play_result 1
endform

# ------------------------------------------------------------
# Presets
# ------------------------------------------------------------
preset_name$ = "Custom"
min_grain_s = 0.04
max_grain_s = 0.12
amp_shape = 1.0

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

# ------------------------------------------------------------
# Validation / setup
# ------------------------------------------------------------
if duration_s <= 0
    exitScript: "Duration must be positive."
endif
if sample_rate_hz < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
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
if breath_noise_mix < 0
    breath_noise_mix = 0
elsif breath_noise_mix > 1
    breath_noise_mix = 1
endif
if formant_bandwidth_scale <= 0
    exitScript: "Formant bandwidth scale must be positive."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling peak must be in (0,1]."
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
else
    random_initializeSafelyAndUnpredictably ()
endif

nyquist = sample_rate_hz / 2
two_pi = 2 * pi
uid$ = string$(randomInteger(10000, 99999))
variants = 3
n_vowels = 5
n_buses = n_vowels * variants

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
# Grain plan
# ------------------------------------------------------------
total_grains = round(duration_s * grain_density)
if total_grains < 1
    total_grains = 1
endif
sum_f1 = 0
sum_f2 = 0
sum_f3 = 0

for g from 1 to total_grains
    grain_time[g] = randomUniform(0, max(0, duration_s - min_grain_s))
    grain_dur[g] = randomUniform(min_grain_s, max_grain_s)
    if grain_time[g] + grain_dur[g] > duration_s
        grain_dur[g] = duration_s - grain_time[g]
    endif
    if grain_dur[g] < 0.005
        grain_dur[g] = 0.005
    endif

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
    grain_bus[g] = b
    grain_f1[g] = var_f1[b]
    grain_f2[g] = var_f2[b]
    grain_f3[g] = var_f3[b]
    sum_f1 = sum_f1 + grain_f1[g]
    sum_f2 = sum_f2 + grain_f2[g]
    sum_f3 = sum_f3 + grain_f3[g]

    grain_f0[g] = base_frequency_hz * randomUniform(0.90, 1.10)
    grain_amp[g] = amp_shape * 0.40 / sqrt(max(12, grain_density)) * randomUniform(0.85, 1.15)
endfor

mean_f1 = sum_f1 / total_grains
mean_f2 = sum_f2 / total_grains
mean_f3 = sum_f3 / total_grains

clearinfo
writeInfoLine: "=== Rich Formant Grains v1.0 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s, 2), " s | density: ", fixed$(grain_density, 1), " grains/s"
appendInfoLine: "Total grains: ", total_grains, " | F0: ", fixed$(base_frequency_hz, 1), " Hz"
appendInfoLine: "Engine: grain excitation -> 15 synthetic resonance buses"
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

# Cleanup synthesis objects.
for b from 1 to n_buses
    removeObject: source_bus[b], fg[b], filtered_bus[b]
endfor

# ------------------------------------------------------------
# Visualization
# ------------------------------------------------------------
if draw_visualization
    Erase all

    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Rich Formant Grains v1.0: " + preset_name$

    # Grain/vowel timeline.
    Select outer viewport: 0, 8, 0.65, 2.15
    Select inner viewport: 0.6, 7.6, 0.75, 2.05
    Axes: 0, duration_s, 0.5, 5.5
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration_s, 0.5, 5.5
    for g from 1 to total_grains
        v = grain_vowel[g]
        Colour: "{0.25,0.45,0.75}"
        if v = 1
            Colour: "{0.80,0.35,0.35}"
        elsif v = 2
            Colour: "{0.35,0.55,0.85}"
        elsif v = 3
            Colour: "{0.35,0.75,0.55}"
        elsif v = 4
            Colour: "{0.80,0.60,0.25}"
        elsif v = 5
            Colour: "{0.65,0.40,0.75}"
        endif
        Draw line: grain_time[g], v, min(duration_s, grain_time[g] + grain_dur[g]), v
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 5, "yes", "no", "no"
    Text left: "yes", "Vowel bank"
    Text bottom: "yes", "Time (s)"

    selectObject: output_sound
    out_ch = Get number of channels
    if out_ch > 1
        disp = Extract one channel: 1
    else
        disp = Copy: "rfg_disp_" + uid$
    endif

    Select outer viewport: 0, 8, 2.35, 4.65
    Select inner viewport: 0.6, 7.6, 2.45, 4.55
    selectObject: disp
    spec_ceil = min(5000, nyquist)
    spec = To Spectrogram: 0.025, spec_ceil, 0.004, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: spec, disp

    Select inner viewport: 0.6, 7.6, 2.45, 4.55
    Axes: 0, duration_s, 0, spec_ceil
    Colour: "{1.0,0.50,0.50}"
    Draw line: 0, min(mean_f1, spec_ceil), duration_s, min(mean_f1, spec_ceil)
    Colour: "{0.50,1.0,0.50}"
    Draw line: 0, min(mean_f2, spec_ceil), duration_s, min(mean_f2, spec_ceil)
    Colour: "{0.50,0.50,1.0}"
    Draw line: 0, min(mean_f3, spec_ceil), duration_s, min(mean_f3, spec_ceil)
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 4.8, 5.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "15 source-filter buses: harmonic/noise excitation -> synthetic F1-F3 resonances"
    Font size: 6
    Colour: "{0.30,0.30,0.30}"
    Text: 0.02, "left", 0.42, "half", "Mean F1/F2/F3: " + fixed$(mean_f1,0) + "/" + fixed$(mean_f2,0) + "/" + fixed$(mean_f3,0) + " Hz | BW x" + fixed$(formant_bandwidth_scale,2) + " | harmonics " + string$(source_harmonics)
    Text: 0.02, "left", 0.16, "half", "Peak " + fixed$(pre_peak,3) + " -> " + fixed$(out_peak,3) + " | RMS " + fixed$(pre_rms,4) + " -> " + fixed$(out_rms,4)
    Font size: 10
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Formants are synthesis resonances, not oscillator frequencies."
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
