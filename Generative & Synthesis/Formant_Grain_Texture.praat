# ============================================================
# Praat AudioTools - Formant Grain Texture v1.0
# Source-filter grain synthesis
#
# Formants in this script are SYNTHESIS formants, not measurements
# from an input Sound. Each grain creates an excitation source; grains
# assigned to the same vowel are accumulated into one source bus, and
# that bus is filtered once through a static FormantGrid.
#
# This replaces the old v0.3 approximation that added sine oscillators
# directly at F1/F2/F3. A formant is now a resonance of a source, not
# an oscillator frequency.
# ============================================================

form Formant Grain Texture v1.0
    comment === Preset ===
    optionmenu preset 1
        option Custom (use settings below)
        option Vowel Cloud
        option Whisper Choir
        option Robotic Speech
        option Alien Language
        option Gregorian Chant
        option Baby Babble
        option Ghost Voices
        option Formant Storm

    comment === Basic Settings ===
    positive duration_s 5.0
    integer sample_rate_hz 44100
    real base_frequency_hz 100

    comment === Grain Settings ===
    positive grain_density 25
    positive min_grain_ms 40
    positive max_grain_ms 120

    comment === Synthesis Formants ===
    positive formant_bandwidth_scale 1.0
    integer source_harmonics 12

    comment === Output ===
    optionmenu spatial_mode 1
        option Mono
        option Stereo Choir
        option Rotating Voices
        option Wide Cloud
    boolean normalize_output 1
    boolean draw_visualization 1
    boolean play_result 1
endform

# ------------------------------------------------------------
# Presets
# ------------------------------------------------------------
preset_name$ = "Custom"
breath_mix = 0.03

if preset = 2
    grain_density = 20
    base_frequency_hz = 120
    min_grain_ms = 50
    max_grain_ms = 120
    formant_bandwidth_scale = 1.0
    breath_mix = 0.04
    preset_name$ = "VowelCloud"
elsif preset = 3
    grain_density = 15
    base_frequency_hz = 0
    min_grain_ms = 80
    max_grain_ms = 180
    formant_bandwidth_scale = 1.35
    breath_mix = 1.0
    preset_name$ = "WhisperChoir"
elsif preset = 4
    grain_density = 35
    base_frequency_hz = 80
    min_grain_ms = 30
    max_grain_ms = 60
    formant_bandwidth_scale = 0.65
    breath_mix = 0.01
    preset_name$ = "RoboticSpeech"
elsif preset = 5
    grain_density = 30
    base_frequency_hz = 140
    min_grain_ms = 40
    max_grain_ms = 100
    formant_bandwidth_scale = 0.8
    breath_mix = 0.06
    preset_name$ = "AlienLanguage"
elsif preset = 6
    duration_s = 8.0
    grain_density = 12
    base_frequency_hz = 90
    min_grain_ms = 120
    max_grain_ms = 300
    formant_bandwidth_scale = 0.9
    breath_mix = 0.02
    preset_name$ = "GregorianChant"
elsif preset = 7
    grain_density = 45
    base_frequency_hz = 280
    min_grain_ms = 25
    max_grain_ms = 60
    formant_bandwidth_scale = 0.8
    breath_mix = 0.04
    preset_name$ = "BabyBabble"
elsif preset = 8
    grain_density = 8
    base_frequency_hz = 160
    min_grain_ms = 150
    max_grain_ms = 350
    spatial_mode = 3
    formant_bandwidth_scale = 1.25
    breath_mix = 0.18
    preset_name$ = "GhostVoices"
elsif preset = 9
    grain_density = 60
    base_frequency_hz = 110
    min_grain_ms = 15
    max_grain_ms = 40
    spatial_mode = 4
    formant_bandwidth_scale = 0.65
    breath_mix = 0.08
    preset_name$ = "FormantStorm"
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
if base_frequency_hz < 0
    exitScript: "Base frequency must be zero (whisper) or positive."
endif
if grain_density <= 0
    exitScript: "Grain density must be positive."
endif
if min_grain_ms <= 0 or max_grain_ms <= 0 or min_grain_ms > max_grain_ms
    exitScript: "Grain durations must be positive and min <= max."
endif
if formant_bandwidth_scale <= 0
    exitScript: "Formant bandwidth scale must be positive."
endif
if source_harmonics < 1 or source_harmonics > 40
    exitScript: "Source harmonics must be between 1 and 40."
endif

nyquist = sample_rate_hz / 2
two_pi = 2 * pi
uid$ = string$(randomInteger(10000, 99999))
chunk_size = 0.5

# ------------------------------------------------------------
# Vowel synthesis banks
# Frequencies are synthesis targets; bandwidths are deliberately
# broad and robust rather than LPC measurements.
# ------------------------------------------------------------
# /a/
bank_f1[1] = 730
bank_f2[1] = 1090
bank_f3[1] = 2440
# /i/
bank_f1[2] = 270
bank_f2[2] = 2290
bank_f3[2] = 3010
# /u/
bank_f1[3] = 300
bank_f2[3] = 870
bank_f3[3] = 2240
# /e/
bank_f1[4] = 530
bank_f2[4] = 1840
bank_f3[4] = 2480
# /o/
bank_f1[5] = 570
bank_f2[5] = 840
bank_f3[5] = 2410

vowel_name$[1] = "a"
vowel_name$[2] = "i"
vowel_name$[3] = "u"
vowel_name$[4] = "e"
vowel_name$[5] = "o"

# Synthesis bandwidths. These are filter design parameters.
base_bw1 = 90 * formant_bandwidth_scale
base_bw2 = 130 * formant_bandwidth_scale
base_bw3 = 180 * formant_bandwidth_scale

# Alien Language deliberately distorts the SYNTHESIS vowel banks once
# per run. It does not pretend these are measured vocal-tract values.
if preset = 5
    for v from 1 to 5
        bank_f1[v] = bank_f1[v] * randomUniform(0.68, 1.32)
        bank_f2[v] = bank_f2[v] * randomUniform(0.78, 1.48)
        bank_f3[v] = bank_f3[v] * randomUniform(0.82, 1.25)
    endfor
endif

# Keep every resonance inside a useful spectrum.
for v from 1 to 5
    bank_f1[v] = min(bank_f1[v], nyquist - 500)
    bank_f2[v] = min(bank_f2[v], nyquist - 300)
    bank_f3[v] = min(bank_f3[v], nyquist - 120)
    if bank_f1[v] < 80
        bank_f1[v] = 80
    endif
    if bank_f2[v] <= bank_f1[v] + 80
        bank_f2[v] = bank_f1[v] + 80
    endif
    if bank_f3[v] <= bank_f2[v] + 100
        bank_f3[v] = bank_f2[v] + 100
    endif
    if bank_f3[v] >= nyquist - 40
        bank_f3[v] = nyquist - 40
    endif
endfor

# ------------------------------------------------------------
# Grain parameters. No O(N^2) sorting is needed; grains are binned
# into time chunks during synthesis.
# ------------------------------------------------------------
total_grains = round(duration_s * grain_density)
if total_grains < 1
    total_grains = 1
endif

sum_f1 = 0
sum_f2 = 0
sum_f3 = 0

for g from 1 to total_grains
    max_start = max(0, duration_s - min_grain_ms / 1000)
    grain_time[g] = randomUniform(0, max_start)
    grain_dur[g] = randomUniform(min_grain_ms, max_grain_ms) / 1000
    if grain_time[g] + grain_dur[g] > duration_s
        grain_dur[g] = duration_s - grain_time[g]
    endif
    if grain_dur[g] < 0.005
        grain_dur[g] = 0.005
    endif

    if preset = 3 or preset = 6
        r = randomUniform(0, 1)
        if r < 0.4
            grain_vowel[g] = 1
        elsif r < 0.7
            grain_vowel[g] = 3
        else
            grain_vowel[g] = 5
        endif
    elsif preset = 4
        if randomUniform(0, 1) < 0.5
            grain_vowel[g] = 2
        else
            grain_vowel[g] = 4
        endif
    elsif preset = 8
        if randomUniform(0, 1) < 0.6
            grain_vowel[g] = 5
        else
            grain_vowel[g] = 2
        endif
    else
        grain_vowel[g] = randomInteger(1, 5)
    endif

    v = grain_vowel[g]
    grain_f1[g] = bank_f1[v]
    grain_f2[g] = bank_f2[v]
    grain_f3[g] = bank_f3[v]
    sum_f1 = sum_f1 + grain_f1[g]
    sum_f2 = sum_f2 + grain_f2[g]
    sum_f3 = sum_f3 + grain_f3[g]

    grain_amp[g] = 0.32 / sqrt(max(10, grain_density))
    if base_frequency_hz > 0
        grain_f0[g] = base_frequency_hz * randomUniform(0.90, 1.10)
    else
        grain_f0[g] = 0
    endif
endfor

mean_f1 = sum_f1 / total_grains
mean_f2 = sum_f2 / total_grains
mean_f3 = sum_f3 / total_grains

clearinfo
writeInfoLine: "=== Formant Grain Texture v1.0 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s, 2), " s | density: ", fixed$(grain_density, 1), " grains/s"
appendInfoLine: "Total grains: ", total_grains, " | source F0: ", fixed$(base_frequency_hz, 1), " Hz"
appendInfoLine: "Engine: excitation buses -> synthetic FormantGrid filters"
appendInfoLine: "Mean synthesis formants: ", fixed$(mean_f1, 0), " / ", fixed$(mean_f2, 0), " / ", fixed$(mean_f3, 0), " Hz"
appendInfoLine: ""

# ------------------------------------------------------------
# Create five excitation buses.
# ------------------------------------------------------------
for v from 1 to 5
    source_bus[v] = Create Sound from formula: "fgt_src_" + vowel_name$[v] + "_" + uid$, 1, 0, duration_s, sample_rate_hz, "0"
endfor

# ------------------------------------------------------------
# Fill buses chunk by chunk. Voiced grains contain a harmonic-rich
# excitation; whisper grains contain noise. Neither source contains
# sine oscillators at the formant frequencies.
# ------------------------------------------------------------
appendInfoLine: "[1/3] Building grain excitation buses..."
chunk_start = 0
while chunk_start < duration_s
    chunk_end = min(duration_s, chunk_start + chunk_size)
    for v from 1 to 5
        formula$[v] = "0"
        count_chunk[v] = 0
    endfor

    for g from 1 to total_grains
        if grain_time[g] >= chunk_start and grain_time[g] < chunk_end
            v = grain_vowel[g]
            gt = grain_time[g]
            gd = grain_dur[g]
            ga = grain_amp[g]
            gf0 = grain_f0[g]

            gt$ = fixed$(gt, 7)
            ge$ = fixed$(gt + gd, 7)
            gd$ = fixed$(gd, 7)
            ga$ = fixed$(ga, 8)

            # Hann grain envelope.
            env$ = "(0.5 - 0.5*cos(2*pi*(x-" + gt$ + ")/" + gd$ + "))"

            if gf0 > 0
                src$ = "0"
                max_h = min(source_harmonics, floor((nyquist - 100) / gf0))
                if max_h < 1
                    max_h = 1
                endif
                for h from 1 to max_h
                    coeff = 1 / h
                    term$ = fixed$(coeff, 7) + "*sin(2*pi*" + fixed$(h * gf0, 5) + "*(x-" + gt$ + "))"
                    src$ = src$ + "+" + term$
                endfor
                # A little aspiration keeps dense voiced clouds from sounding
                # like perfectly periodic additive synthesis.
                if breath_mix > 0
                    src$ = "((1-" + fixed$(breath_mix, 5) + ")*(" + src$ + ") + " + fixed$(breath_mix, 5) + "*randomGauss(0,1))"
                endif
            else
                src$ = "randomGauss(0,1)"
            endif

            grain_term$ = " + if x >= " + gt$ + " and x < " + ge$ + " then " + ga$ + "*(" + src$ + ")*" + env$ + " else 0 fi"
            formula$[v] = formula$[v] + grain_term$
            count_chunk[v] = count_chunk[v] + 1
        endif
    endfor

    for v from 1 to 5
        if count_chunk[v] > 0
            selectObject: source_bus[v]
            Formula: "self + (" + formula$[v] + ")"
        endif
    endfor

    chunk_start = chunk_end
endwhile

# ------------------------------------------------------------
# Filter each source bus through its own synthetic vowel resonances.
# Use Filter (no scale): relative levels are normalized only once, if
# the user requests normalization at the end.
# ------------------------------------------------------------
appendInfoLine: "[2/3] Applying synthetic vowel filters..."

for v from 1 to 5
    selectObject: source_bus[v]
    source_rms[v] = Get root-mean-square: 0, 0

    fg[v] = Create FormantGrid: "fgt_filter_" + vowel_name$[v] + "_" + uid$, 0, duration_s, 3, bank_f1[v], 1000, base_bw1, 50

    selectObject: fg[v]
    for f from 1 to 3
        Remove formant points between: f, 0, duration_s
        Remove bandwidth points between: f, 0, duration_s
    endfor

    Add formant point: 1, 0, bank_f1[v]
    Add formant point: 1, duration_s, bank_f1[v]
    Add bandwidth point: 1, 0, base_bw1
    Add bandwidth point: 1, duration_s, base_bw1

    Add formant point: 2, 0, bank_f2[v]
    Add formant point: 2, duration_s, bank_f2[v]
    Add bandwidth point: 2, 0, base_bw2
    Add bandwidth point: 2, duration_s, base_bw2

    Add formant point: 3, 0, bank_f3[v]
    Add formant point: 3, duration_s, bank_f3[v]
    Add bandwidth point: 3, 0, base_bw3
    Add bandwidth point: 3, duration_s, base_bw3

    selectObject: source_bus[v]
    plusObject: fg[v]
    filtered_bus[v] = Filter (no scale)

    # A FormantGrid is an all-pole resonator and can have very large
    # absolute gain. Compensate each whole vowel bus back to the RMS
    # of its excitation. This is one constant per bus, so grain dynamics
    # remain intact and Normalize_output is still the only peak normalizer.
    selectObject: filtered_bus[v]
    filtered_rms = Get root-mean-square: 0, 0
    if source_rms[v] > 0.000000000001 and filtered_rms > 0.000000000001
        bus_gain = source_rms[v] / filtered_rms
        Formula: "self * " + string$(bus_gain)
    endif
endfor

# ------------------------------------------------------------
# Sum vowel buses.
# ------------------------------------------------------------
output_sound = Create Sound from formula: "formant_" + preset_name$ + "_mono", 1, 0, duration_s, sample_rate_hz, "0"
for v from 1 to 5
    selectObject: output_sound
    Formula: "self + object(" + string$(filtered_bus[v]) + ", x)"
endfor

# Gentle global edge fade only, not per-grain replacement.
selectObject: output_sound
fade_s = min(0.02, duration_s / 4)
if fade_s > 0
    Formula: "if x < " + string$(fade_s) + " then self*(x/" + string$(fade_s) + ") else self fi"
    Formula: "if x > " + string$(duration_s - fade_s) + " then self*((" + string$(duration_s) + "-x)/" + string$(fade_s) + ") else self fi"
endif

# ------------------------------------------------------------
# Spatial processing. Kept compatible with the original modes.
# ------------------------------------------------------------
appendInfoLine: "[3/3] Spatial/output stage..."
if spatial_mode = 2
    selectObject: output_sound
    left_sound = Copy: "fgt_left_" + uid$
    left_filtered = Filter (pass Hann band): 0, min(2500, nyquist - 100), 120
    removeObject: left_sound
    left_sound = left_filtered

    selectObject: output_sound
    right_sound = Copy: "fgt_right_" + uid$
    right_filtered = Filter (pass Hann band): 150, min(4000, nyquist - 100), 120
    removeObject: right_sound
    right_sound = right_filtered

    selectObject: left_sound
    plusObject: right_sound
    stereo_sound = Combine to stereo
    removeObject: output_sound, left_sound, right_sound
    output_sound = stereo_sound

elsif spatial_mode = 3
    selectObject: output_sound
    left_sound = Copy: "fgt_left_" + uid$
    Formula: "self * sqrt(0.5 + 0.5*cos(2*pi*0.12*x))"

    selectObject: output_sound
    right_sound = Copy: "fgt_right_" + uid$
    Formula: "self * sqrt(0.5 - 0.5*cos(2*pi*0.12*x))"

    selectObject: left_sound
    plusObject: right_sound
    stereo_sound = Combine to stereo
    removeObject: output_sound, left_sound, right_sound
    output_sound = stereo_sound

elsif spatial_mode = 4
    selectObject: output_sound
    left_sound = Copy: "fgt_left_" + uid$
    left_filtered = Filter (pass Hann band): 0, min(2000, nyquist - 100), 150
    removeObject: left_sound
    left_sound = left_filtered

    selectObject: output_sound
    right_sound = Copy: "fgt_right_" + uid$
    right_filtered = Filter (pass Hann band): 300, min(6000, nyquist - 100), 150
    removeObject: right_sound
    right_sound = right_filtered

    selectObject: left_sound
    plusObject: right_sound
    stereo_sound = Combine to stereo
    removeObject: output_sound, left_sound, right_sound
    output_sound = stereo_sound
endif

selectObject: output_sound
Rename: "FormantGrain_" + preset_name$
pre_peak = Get absolute extremum: 0, 0, "None"
pre_rms = Get root-mean-square: 0, 0
if normalize_output and pre_peak > 0
    Scale peak: 0.9
endif
out_peak = Get absolute extremum: 0, 0, "None"
out_rms = Get root-mean-square: 0, 0

# Cleanup synthesis objects.
for v from 1 to 5
    removeObject: source_bus[v], fg[v], filtered_bus[v]
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
    Text: 0.5, "centre", 0.5, "half", "Formant Grain Texture v1.0: " + preset_name$

    selectObject: output_sound
    out_ch = Get number of channels
    if out_ch > 1
        disp = Extract one channel: 1
    else
        disp = Copy: "fgt_disp_" + uid$
    endif

    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: disp
    Colour: "{0.20, 0.45, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    Select outer viewport: 0, 8, 2.0, 4.6
    Select inner viewport: 0.6, 7.6, 2.1, 4.5
    selectObject: disp
    spec_ceil = min(4000, nyquist)
    spec = To Spectrogram: 0.03, spec_ceil, 0.005, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: spec, disp

    Select inner viewport: 0.6, 7.6, 2.1, 4.5
    Axes: 0, duration_s, 0, spec_ceil
    Line width: 2
    Colour: "{1.0, 0.50, 0.50}"
    Draw line: 0, min(mean_f1, spec_ceil), duration_s, min(mean_f1, spec_ceil)
    Colour: "{0.50, 1.0, 0.50}"
    Draw line: 0, min(mean_f2, spec_ceil), duration_s, min(mean_f2, spec_ceil)
    Colour: "{0.50, 0.50, 1.0}"
    Draw line: 0, min(mean_f3, spec_ceil), duration_s, min(mean_f3, spec_ceil)
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 4.75, 5.75
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02, "left", 0.78, "half", "Source-filter synthesis: harmonic/noise grains -> 5 synthetic vowel FormantGrids"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.46, "half", "Mean F1/F2/F3: " + fixed$(mean_f1, 0) + "/" + fixed$(mean_f2, 0) + "/" + fixed$(mean_f3, 0) + " Hz | BW scale: " + fixed$(formant_bandwidth_scale, 2) + " | harmonics: " + string$(source_harmonics)
    Text: 0.02, "left", 0.14, "half", "Peak: " + fixed$(pre_peak, 3) + " -> " + fixed$(out_peak, 3) + " | RMS: " + fixed$(pre_rms, 4) + " -> " + fixed$(out_rms, 4) + " | lines = mean synthesis resonances"
    Font size: 10
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: output_sound
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Peak: ", fixed$(pre_peak, 4), " -> ", fixed$(out_peak, 4)
appendInfoLine: "RMS:  ", fixed$(pre_rms, 5), " -> ", fixed$(out_rms, 5)
appendInfoLine: "Formants are synthesis resonances, not sinusoidal oscillators."

if play_result
    selectObject: output_sound
    Play
endif

selectObject: output_sound
