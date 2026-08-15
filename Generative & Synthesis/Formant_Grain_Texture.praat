# ============================================================
# Praat AudioTools - Formant Grain Texture
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# FORMANT-GRAIN SOURCE/FILTER SYNTHESIS
#
#   Each stochastic event creates a Hann-windowed excitation grain.
#   The grain is assigned to one of five SYNTHESIS vowel banks:
#
#       a : F1 730, F2 1090, F3 2440 Hz
#       i : F1 270, F2 2290, F3 3010 Hz
#       u : F1 300, F2  870, F3 2240 Hz
#       e : F1 530, F2 1840, F3 2480 Hz
#       o : F1 570, F2  840, F3 2410 Hz
#
#   Grains assigned to the same vowel are accumulated into one source bus,
#   then that bus is filtered by one static three-resonance FormantGrid.
#   Because the filter is linear and time invariant inside each vowel bus,
#   filtering the sum is mathematically equivalent to filtering those grains
#   individually and summing them afterward.
#
#   These formants are SYNTHESIS targets, not measurements from an input Sound.
#
# EVENT PROCESS
#   Grain onsets are a homogeneous Poisson process:
#
#       inter-onset interval ~ Exponential(rate = Grain_density)
#
#   Therefore Grain_density is an expected event rate, not a fixed grain count.
#
# EXCITATION
#   Voiced grains use a normalized harmonic source:
#
#       s(t) = sqrt(2)/sqrt(sum_h 1/h^2) * sum_h sin(h*w0*t+phi)/h
#
#   Breath_mix is interpreted as an approximate POWER fraction:
#
#       source = sqrt(1-breath)*harmonic + sqrt(breath)*noise
#
#   Whisper mode (F0 = 0) uses noise only.
#
# v1.1 reviewed:
#   - Preserved the correct source/filter FormantGrid architecture.
#   - Replaced fixed N + uniform onset placement with a genuine homogeneous
#     Poisson event process; actual grain count is stochastic.
#   - Event schedule is chronological; no sorting is needed.
#   - Added reproducible Random_seed, random grain phase and F0 jitter control.
#   - Harmonic excitation is RMS-normalized before harmonic/noise mixing.
#   - Breath_mix now has a clear power-fraction interpretation.
#   - Grain level is compensated by expected overlap, so density primarily
#     controls texture occupancy rather than hidden loudness.
#   - Replaced repeated whole-Sound chunk Formula passes with Formula (part)
#     restricted to the current chunk. Boundary-crossing grains retain the
#     same age, phase and Hann envelope on both sides.
#   - Kept five vowel buses, but spatialization now occurs on FILTERED vowel
#     buses with equal-power gains; removed left/right Hann-band coloration.
#   - Stereo Vowel Spread gives five fixed positions.
#   - Rotating Vowel Buses uses equal-power moving positions with phase offsets.
#   - Wide Vowel Field gives a wider fixed distribution.
#   - Presets renamed to describe actual spectral/statistical behavior rather
#     than claiming speech styles, age groups, chant or supernatural voices.
#   - Compact laptop-safe main form + one optional Source/Filter detail page.
#   - One combined edge fade and one optional final/common peak normalization.
#   - Visualization rebuilt:
#       A actual Poisson onset/vowel schedule
#       B actual grain F1/F2/F3 map
#       C measured spectrogram + sampled actual formant guides
#       D measured representative-channel waveform
#       vowel occupancy / source-filter / level QC
# ============================================================

form Formant Grain Texture v1.1
    optionmenu Preset 1
        option Custom (baseline values)
        option Balanced Vowel Cloud
        option Whispered Back-Vowel Cloud
        option Alternating Front Vowels
        option Distorted Vowel Bank
        option Sparse Low Open Vowels
        option High Dense Vowel Scatter
        option Sparse Breathy Back Vowels
        option Dense Narrow Vowel Storm

    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    real Base_frequency_Hz 100
    positive Grain_density 25

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Vowel Spread
        option Rotating Vowel Buses
        option Wide Vowel Field

    boolean Edit_source_filter_details 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
min_grain_ms = 40
max_grain_ms = 120
formant_bandwidth_scale = 1.0
source_harmonics = 12
breath_mix = 0.03
f0_jitter_percent = 10
random_seed = 0
edge_fade_s = 0.02

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    grain_density = 20
    base_frequency_Hz = 120
    min_grain_ms = 50
    max_grain_ms = 120
    formant_bandwidth_scale = 1.0
    source_harmonics = 12
    breath_mix = 0.04
    f0_jitter_percent = 8
    preset_name$ = "Balanced Vowel Cloud"

elsif preset = 3
    grain_density = 15
    base_frequency_Hz = 0
    min_grain_ms = 80
    max_grain_ms = 180
    formant_bandwidth_scale = 1.35
    source_harmonics = 12
    breath_mix = 1.0
    f0_jitter_percent = 0
    preset_name$ = "Whispered Back-Vowel Cloud"

elsif preset = 4
    grain_density = 35
    base_frequency_Hz = 80
    min_grain_ms = 30
    max_grain_ms = 60
    formant_bandwidth_scale = 0.65
    source_harmonics = 16
    breath_mix = 0.01
    f0_jitter_percent = 3
    preset_name$ = "Alternating Front Vowels"

elsif preset = 5
    grain_density = 30
    base_frequency_Hz = 140
    min_grain_ms = 40
    max_grain_ms = 100
    formant_bandwidth_scale = 0.80
    source_harmonics = 15
    breath_mix = 0.06
    f0_jitter_percent = 14
    preset_name$ = "Distorted Vowel Bank"

elsif preset = 6
    duration_s = 8.0
    grain_density = 12
    base_frequency_Hz = 90
    min_grain_ms = 120
    max_grain_ms = 300
    formant_bandwidth_scale = 0.90
    source_harmonics = 12
    breath_mix = 0.02
    f0_jitter_percent = 5
    preset_name$ = "Sparse Low Open Vowels"

elsif preset = 7
    grain_density = 45
    base_frequency_Hz = 280
    min_grain_ms = 25
    max_grain_ms = 60
    formant_bandwidth_scale = 0.80
    source_harmonics = 18
    breath_mix = 0.04
    f0_jitter_percent = 12
    preset_name$ = "High Dense Vowel Scatter"

elsif preset = 8
    grain_density = 8
    base_frequency_Hz = 160
    min_grain_ms = 150
    max_grain_ms = 350
    formant_bandwidth_scale = 1.25
    source_harmonics = 10
    breath_mix = 0.18
    f0_jitter_percent = 10
    spatial_mode = 3
    preset_name$ = "Sparse Breathy Back Vowels"

elsif preset = 9
    grain_density = 60
    base_frequency_Hz = 110
    min_grain_ms = 15
    max_grain_ms = 40
    formant_bandwidth_scale = 0.65
    source_harmonics = 20
    breath_mix = 0.08
    f0_jitter_percent = 18
    spatial_mode = 4
    preset_name$ = "Dense Narrow Vowel Storm"
endif

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_source_filter_details
    beginPause: "Formant Grain Texture - Source / Filter Details"
        positive: "Min grain duration (ms)", min_grain_ms
        positive: "Max grain duration (ms)", max_grain_ms
        positive: "Formant bandwidth scale", formant_bandwidth_scale
        integer: "Source harmonics", source_harmonics
        real: "Breath mix (0..1 power fraction)", breath_mix
        real: "F0 jitter (percent)", f0_jitter_percent
        integer: "Random seed (0 = unpredictable)", random_seed
        real: "Edge fade (s)", edge_fade_s
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# 1. VALIDATION / LABELS
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if base_frequency_Hz < 0
    exitScript: "Base frequency must be zero (whisper) or positive."
endif
if grain_density <= 0 or grain_density > 250
    exitScript: "Grain density must be > 0 and <= 250 grains/s."
endif
if min_grain_ms <= 0 or max_grain_ms <= 0 or min_grain_ms > max_grain_ms
    exitScript: "Grain durations must be positive and min <= max."
endif
if max_grain_ms > 2000
    exitScript: "Maximum grain duration is limited to 2000 ms."
endif
if formant_bandwidth_scale <= 0 or formant_bandwidth_scale > 5
    exitScript: "Formant bandwidth scale must be > 0 and <= 5."
endif
if source_harmonics < 1 or source_harmonics > 40
    exitScript: "Source harmonics must be between 1 and 40."
endif
if breath_mix < 0 or breath_mix > 1
    exitScript: "Breath mix must be between 0 and 1."
endif
if f0_jitter_percent < 0 or f0_jitter_percent > 100
    exitScript: "F0 jitter must be between 0 and 100 percent."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

if spatial_mode = 1
    spatial$ = "Mono"
elsif spatial_mode = 2
    spatial$ = "Stereo Vowel Spread"
elsif spatial_mode = 3
    spatial$ = "Rotating Vowel Buses"
else
    spatial$ = "Wide Vowel Field"
endif

nyquist = sample_rate_Hz/2
safeTop = 0.45*sample_rate_Hz
uid$ = string$(randomInteger(10000,99999))

# ---------------------------------------------------------------------------
# 2. VOWEL SYNTHESIS BANKS
# ---------------------------------------------------------------------------
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

base_bw1 = 90*formant_bandwidth_scale
base_bw2 = 130*formant_bandwidth_scale
base_bw3 = 180*formant_bandwidth_scale

# Seed the ENTIRE stochastic synthesis path, including bank distortion,
# grain schedule, phases, F0 jitter and rendered noise.
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

# Distorted Vowel Bank deliberately perturbs synthesis targets once per run.
if preset = 5
    for v from 1 to 5
        bank_f1[v] = bank_f1[v]*randomUniform(0.68,1.32)
        bank_f2[v] = bank_f2[v]*randomUniform(0.78,1.48)
        bank_f3[v] = bank_f3[v]*randomUniform(0.82,1.25)
    endfor
endif

# Preserve ordering and sampling headroom.
for v from 1 to 5
    bank_f1[v] = min(bank_f1[v],safeTop-500)
    bank_f2[v] = min(bank_f2[v],safeTop-300)
    bank_f3[v] = min(bank_f3[v],safeTop-120)

    bank_f1[v] = max(80,bank_f1[v])
    bank_f2[v] = max(bank_f1[v]+80,bank_f2[v])
    bank_f3[v] = max(bank_f2[v]+100,bank_f3[v])

    if bank_f3[v] > safeTop
        bank_f3[v] = safeTop
    endif
endfor

# ---------------------------------------------------------------------------
# 3. GENUINE POISSON GRAIN SCHEDULE
# ---------------------------------------------------------------------------
expectedGrains = grain_density*duration_s
if expectedGrains > 10000
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "Expected grain count exceeds 10,000. Reduce density or duration."
endif

meanGrainDur = 0.0005*(min_grain_ms+max_grain_ms)
expectedOverlap = max(1,grain_density*meanGrainDur)
baseGrainAmp = 0.42/sqrt(expectedOverlap)

total_grains = 0
grainClock = 0

count_vowel# = zero#(5)
sum_f1 = 0
sum_f2 = 0
sum_f3 = 0
sum_dur = 0
minF0Realized = 1e9
maxF0Realized = 0

while grainClock < duration_s
    u = max(1e-12,randomUniform(0,1))
    grainClock = grainClock-ln(u)/grain_density

    if grainClock < duration_s
        total_grains = total_grains+1
        if total_grains > 12000
            if seedWasFixed
                random_initializeSafelyAndUnpredictably ()
            endif
            exitScript: "Stochastic realization exceeded 12,000 grains."
        endif

        grain_time[total_grains] = grainClock

        gd = randomUniform(min_grain_ms,max_grain_ms)/1000
        gd = min(gd,duration_s-grainClock)
        grain_dur[total_grains] = max(1/sample_rate_Hz,gd)

        # Preset-specific vowel probability, but no false claims of speech.
        if preset = 3 or preset = 6
            r = randomUniform(0,1)
            if r < 0.4
                vv = 1
            elsif r < 0.7
                vv = 3
            else
                vv = 5
            endif

        elsif preset = 4
            if randomUniform(0,1) < 0.5
                vv = 2
            else
                vv = 4
            endif

        elsif preset = 8
            if randomUniform(0,1) < 0.6
                vv = 5
            else
                vv = 2
            endif

        else
            vv = randomInteger(1,5)
        endif

        grain_vowel[total_grains] = vv
        count_vowel#[vv] = count_vowel#[vv]+1

        grain_f1[total_grains] = bank_f1[vv]
        grain_f2[total_grains] = bank_f2[vv]
        grain_f3[total_grains] = bank_f3[vv]

        sum_f1 = sum_f1+grain_f1[total_grains]
        sum_f2 = sum_f2+grain_f2[total_grains]
        sum_f3 = sum_f3+grain_f3[total_grains]
        sum_dur = sum_dur+grain_dur[total_grains]

        grain_amp[total_grains] =
            ... baseGrainAmp*(0.88+0.12*randomUniform(0,1))
        grain_phase[total_grains] = 2*pi*randomUniform(0,1)

        if base_frequency_Hz > 0
            jitterFrac = f0_jitter_percent/100
            f0 = base_frequency_Hz*(1+randomUniform(-jitterFrac,jitterFrac))
            f0 = max(20,f0)

            # Guarantee at least the fundamental is below practical Nyquist.
            f0 = min(f0,safeTop)
            grain_f0[total_grains] = f0

            minF0Realized = min(minF0Realized,f0)
            maxF0Realized = max(maxF0Realized,f0)
        else
            grain_f0[total_grains] = 0
        endif
    endif
endwhile

if total_grains < 1
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "This stochastic realization produced zero grains. Increase duration/density or change seed."
endif

mean_f1 = sum_f1/total_grains
mean_f2 = sum_f2/total_grains
mean_f3 = sum_f3/total_grains
meanDurRealized = sum_dur/total_grains
realizedDensity = total_grains/duration_s

if base_frequency_Hz = 0
    minF0Realized = 0
    maxF0Realized = 0
endif

# ---------------------------------------------------------------------------
# 4. DENSITY BINS FOR QC / VISUALIZATION
# ---------------------------------------------------------------------------
densityBins = min(32,max(10,round(duration_s*3)))
densityBinWidth = duration_s/densityBins
densityCount# = zero#(densityBins)
densityRate# = zero#(densityBins)
densityMax = grain_density

for g from 1 to total_grains
    b = floor(grain_time[g]/densityBinWidth)+1
    b = max(1,min(densityBins,b))
    densityCount#[b] = densityCount#[b]+1
endfor

for b from 1 to densityBins
    densityRate#[b] = densityCount#[b]/densityBinWidth
    densityMax = max(densityMax,densityRate#[b])
endfor

# ---------------------------------------------------------------------------
# 5. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  FORMANT GRAIN TEXTURE v1.1"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s,2), " s"
appendInfoLine: "Target / realized density: ",
    ... fixed$(grain_density,2), " / ", fixed$(realizedDensity,2), " grains/s"
appendInfoLine: "Expected / actual grains: ",
    ... fixed$(expectedGrains,1), " / ", total_grains
appendInfoLine: "Source F0: ", fixed$(base_frequency_Hz,1), " Hz"
appendInfoLine: "Breath power fraction: ", fixed$(breath_mix,3)
appendInfoLine: "Mean synthesis F1/F2/F3: ",
    ... fixed$(mean_f1,0), " / ", fixed$(mean_f2,0), " / ", fixed$(mean_f3,0), " Hz"
appendInfoLine: "Spatial: ", spatial$
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 6. CREATE FIVE EXCITATION BUSES
# ---------------------------------------------------------------------------
for v from 1 to 5
    source_bus[v] = Create Sound from formula:
        ... "fgt_src_" + vowel_name$[v] + "_" + uid$,
        ... 1,0,duration_s,sample_rate_Hz,"0"
endfor

# ---------------------------------------------------------------------------
# 7. BUILD EXCITATION BUSES WITH CHUNK-LOCAL FORMULA PASSES
# ---------------------------------------------------------------------------
appendInfoLine: "[1/3] Building Poisson excitation buses..."

chunk_size = min(0.5,duration_s)
numChunks = ceiling(duration_s/chunk_size)
candidateStart = 1
maxTermsPerBusChunk = 0

for chunk from 1 to numChunks
    chunk_start = (chunk-1)*chunk_size
    chunk_end = min(duration_s,chunk*chunk_size)

    # Because grain times are chronological, skip grains that cannot overlap.
    while candidateStart <= total_grains and
        ... grain_time[candidateStart]+max_grain_ms/1000 <= chunk_start
        candidateStart = candidateStart+1
    endwhile

    for v from 1 to 5
        formula$[v] = "0"
        count_chunk[v] = 0
    endfor

    g = candidateStart
    while g <= total_grains and grain_time[g] < chunk_end
        grainEnd = grain_time[g]+grain_dur[g]

        if grainEnd > chunk_start
            v = grain_vowel[g]
            gt = grain_time[g]
            gd = grain_dur[g]
            ga = grain_amp[g]
            gf0 = grain_f0[g]
            gp = grain_phase[g]

            clip_start = max(chunk_start,gt)
            clip_end = min(chunk_end,grainEnd)

            gt$ = fixed$(gt,9)
            gd$ = fixed$(gd,9)
            ga$ = fixed$(ga,9)
            gp$ = fixed$(gp,9)

            age$ = "(x-" + gt$ + ")"
            env$ = "(0.5-0.5*cos(2*pi*" + age$ + "/" + gd$ + "))"

            if gf0 > 0
                max_h = min(source_harmonics,floor(safeTop/gf0))
                max_h = max(1,max_h)

                harmonicPower = 0
                for h from 1 to max_h
                    harmonicPower = harmonicPower+1/(h*h)
                endfor
                harmonicNorm = sqrt(2)/sqrt(harmonicPower)

                src$ = "0"
                for h from 1 to max_h
                    coeff = harmonicNorm/h
                    term$ = fixed$(coeff,8) + "*sin(2*pi*"
                        ... + fixed$(h*gf0,6) + "*" + age$ + "+" + gp$ + ")"
                    src$ = src$+"+"+term$
                endfor

                if breath_mix > 0
                    toneGain = sqrt(max(0,1-breath_mix))
                    noiseGain = sqrt(breath_mix)
                    src$ = "(" + fixed$(toneGain,8) + "*(" + src$ + ")+"
                        ... + fixed$(noiseGain,8) + "*randomGauss(0,1))"
                endif

            else
                src$ = "randomGauss(0,1)"
            endif

            grain_term$ = "+if x>=" + fixed$(clip_start,9)
                ... + " and x<" + fixed$(clip_end,9)
                ... + " then " + ga$ + "*(" + src$ + ")*" + env$
                ... + " else 0 fi"

            formula$[v] = formula$[v]+grain_term$
            count_chunk[v] = count_chunk[v]+1
            maxTermsPerBusChunk = max(maxTermsPerBusChunk,count_chunk[v])
        endif

        g = g+1
    endwhile

    for v from 1 to 5
        if count_chunk[v] > 0
            selectObject: source_bus[v]
            Formula (part): chunk_start,chunk_end,1,1,
                ... "self+(" + formula$[v] + ")"
        endif
    endfor
endfor

# ---------------------------------------------------------------------------
# 8. FILTER FIVE VOWEL BUSES
# ---------------------------------------------------------------------------
appendInfoLine: "[2/3] Applying five synthetic FormantGrid filters..."

for v from 1 to 5
    selectObject: source_bus[v]
    source_rms[v] = Get root-mean-square: 0,0

    fg[v] = Create FormantGrid:
        ... "fgt_filter_" + vowel_name$[v] + "_" + uid$,
        ... 0,duration_s,3,bank_f1[v],1000,base_bw1,50

    selectObject: fg[v]
    for f from 1 to 3
        Remove formant points between: f,0,duration_s
        Remove bandwidth points between: f,0,duration_s
    endfor

    Add formant point: 1,0,bank_f1[v]
    Add formant point: 1,duration_s,bank_f1[v]
    Add bandwidth point: 1,0,base_bw1
    Add bandwidth point: 1,duration_s,base_bw1

    Add formant point: 2,0,bank_f2[v]
    Add formant point: 2,duration_s,bank_f2[v]
    Add bandwidth point: 2,0,base_bw2
    Add bandwidth point: 2,duration_s,base_bw2

    Add formant point: 3,0,bank_f3[v]
    Add formant point: 3,duration_s,bank_f3[v]
    Add bandwidth point: 3,0,base_bw3
    Add bandwidth point: 3,duration_s,base_bw3

    selectObject: source_bus[v]
    plusObject: fg[v]
    Filter (no scale)
    filtered_bus[v] = selected("Sound")

    # All-pole filters can have large absolute gain. Match each filtered bus
    # back to its excitation-bus RMS with ONE scalar, preserving spectral shape.
    selectObject: filtered_bus[v]
    filtered_rms = Get root-mean-square: 0,0

    if source_rms[v] > 1e-12 and filtered_rms > 1e-12
        bus_gain = source_rms[v]/filtered_rms
        Formula: "self*bus_gain"
    endif
endfor

# ---------------------------------------------------------------------------
# 9. VOWEL-BUS SPATIAL MIX
# ---------------------------------------------------------------------------
appendInfoLine: "[3/3] Spatial/output stage..."

if spatial_mode = 1
    output_sound = Create Sound from formula:
        ... "fgt_mono_" + uid$,1,0,duration_s,sample_rate_Hz,
        ... "object[" + string$(filtered_bus[1]) + ",1,col]"
        ... + "+object[" + string$(filtered_bus[2]) + ",1,col]"
        ... + "+object[" + string$(filtered_bus[3]) + ",1,col]"
        ... + "+object[" + string$(filtered_bus[4]) + ",1,col]"
        ... + "+object[" + string$(filtered_bus[5]) + ",1,col]"

else
    # Fixed pan values are only used in the two static spatial modes.
    if spatial_mode = 2
        pan_bus# = {0.08,0.29,0.50,0.71,0.92}
    elsif spatial_mode = 4
        pan_bus# = {0.03,0.97,0.14,0.86,0.50}
    endif

    leftFormula$ = "0"
    rightFormula$ = "0"

    for v from 1 to 5
        bid$ = string$(filtered_bus[v])

        if spatial_mode = 3
            phase0 = 2*pi*(v-1)/5
            phase0$ = fixed$(phase0,9)

            # Equal-power moving pan:
            # p = 0.5 + 0.46*sin(angle)
            # gL = sqrt(1-p), gR = sqrt(p)
            panExpr$ = "(0.5+0.46*sin(2*pi*0.10*x+" + phase0$ + "))"
            leftGain$ = "sqrt(1-" + panExpr$ + ")"
            rightGain$ = "sqrt(" + panExpr$ + ")"

        else
            leftGain$ = fixed$(sqrt(1-pan_bus#[v]),9)
            rightGain$ = fixed$(sqrt(pan_bus#[v]),9)
        endif

        leftFormula$ = leftFormula$ + "+" + leftGain$
            ... + "*object[" + bid$ + ",1,col]"
        rightFormula$ = rightFormula$ + "+" + rightGain$
            ... + "*object[" + bid$ + ",1,col]"
    endfor

    left_sound = Create Sound from formula:
        ... "fgt_left_" + uid$,1,0,duration_s,sample_rate_Hz,leftFormula$
    right_sound = Create Sound from formula:
        ... "fgt_right_" + uid$,1,0,duration_s,sample_rate_Hz,rightFormula$

    selectObject: left_sound
    plusObject: right_sound
    Combine to stereo
    output_sound = selected("Sound")

    removeObject: left_sound,right_sound
endif

# ---------------------------------------------------------------------------
# 10. EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.20*duration_s)

if actualFade > 0
    fadeOutStart = duration_s-actualFade
    selectObject: output_sound
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

selectObject: output_sound
pre_peak = Get absolute extremum: 0,0,"None"
pre_rms = Get root-mean-square: 0,0

if normalize_output and pre_peak > 0
    Scale peak: 0.90
endif

safePreset$ = replace$(preset_name$," ","_",0)
Rename: "FormantGrain_" + safePreset$

out_peak = Get absolute extremum: 0,0,"None"
out_rms = Get root-mean-square: 0,0
out_channels = Get number of channels

# Restore unpredictable RNG only AFTER all rendered noise has been generated.
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# Source buses are no longer needed. Keep filtered buses until visualization,
# because their true vowel-bank spatial/spectral contribution is part of QC.
for v from 1 to 5
    removeObject: source_bus[v],fg[v]
endfor

# ---------------------------------------------------------------------------
# 11. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

for v from 1 to 5
    removeObject: filtered_bus[v]
endfor

# ---------------------------------------------------------------------------
# 12. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: output_sound
appendInfoLine: ""
appendInfoLine: "Vowel counts a/i/u/e/o: ",
    ... count_vowel#[1], " / ", count_vowel#[2], " / ",
    ... count_vowel#[3], " / ", count_vowel#[4], " / ", count_vowel#[5]
appendInfoLine: "Mean grain duration: ", fixed$(meanDurRealized*1000,1), " ms"
appendInfoLine: "Max terms in a vowel bus / 0.5-s chunk: ", maxTermsPerBusChunk
appendInfoLine: "Pre-normalization peak/RMS: ",
    ... fixed$(pre_peak,4), " / ", fixed$(pre_rms,5)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(out_peak,4), " / ", fixed$(out_rms,5)
appendInfoLine: "Formants are synthesis resonances, not oscillator frequencies."
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: output_sound


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .a$ = "{0.76,0.38,0.18}"
    .i$ = "{0.18,0.43,0.72}"
    .u$ = "{0.25,0.58,0.38}"
    .e$ = "{0.52,0.30,0.62}"
    .o$ = "{0.55,0.35,0.20}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "FORMANT GRAIN TEXTURE | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... "Poisson " + fixed$(grain_density,1) + "/s | actual "
        ... + string$(total_grains) + " grains | " + spatial$
    Text: 0.5,"centre",0.20,"half",
        ... "harmonic/noise grain -> vowel bus -> static 3-resonance FormantGrid -> equal-power spatial mix"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL EVENT / VOWEL SCHEDULE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.76,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  STOCHASTIC EVENT FIELD | actual onset + duration; row = assigned vowel"

    Select inner viewport: .left,.right,1.05,2.00
    Axes: 0,duration_s,0.5,5.5
    Paint rectangle: .bg$,0,duration_s,0.5,5.5

    Colour: .grid$
    Dotted line
    for .v from 1 to 5
        Draw line: 0,.v,duration_s,.v
    endfor
    Plain line

    .grainStep = max(1,ceiling(total_grains/1800))

    for .g from 1 to total_grains
        if ((.g-1) mod .grainStep)=0
            .v = grain_vowel[.g]

            if .v=1
                Colour: .a$
            elsif .v=2
                Colour: .i$
            elsif .v=3
                Colour: .u$
            elsif .v=4
                Colour: .e$
            else
                Colour: .o$
            endif

            Draw line: grain_time[.g],.v,
                ... min(duration_s,grain_time[.g]+grain_dur[.g]),.v
        endif
    endfor

    Colour: "Black"
    Font size: 5
    Text: 0.005*duration_s,"left",1,"half","a"
    Text: 0.005*duration_s,"left",2,"half","i"
    Text: 0.005*duration_s,"left",3,"half","u"
    Text: 0.005*duration_s,"left",4,"half","e"
    Text: 0.005*duration_s,"left",5,"half","o"

    Draw inner box
    Marks bottom: 5,"yes","yes","no"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL FORMANT GRAIN MAP
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.16,2.38
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  SYNTHESIS FORMANTS | actual F1 / F2 / F3 assigned to every rendered grain"

    .formantMax = min(safeTop,max(3500,1.12*max(mean_f3,bank_f3[1],bank_f3[2],bank_f3[3],bank_f3[4],bank_f3[5])))

    Select inner viewport: .left,.right,2.45,3.49
    Axes: 0,duration_s,0,.formantMax
    Paint rectangle: .bg$,0,duration_s,0,.formantMax

    Colour: .grid$
    Dotted line
    Draw line: 0,1000,duration_s,1000
    Draw line: 0,2000,duration_s,2000
    Draw line: 0,3000,duration_s,3000
    Plain line

    .mapStep = max(1,ceiling(total_grains/700))

    for .g from 1 to total_grains
        if ((.g-1) mod .mapStep)=0
            .v = grain_vowel[.g]

            if .v=1
                Colour: .a$
            elsif .v=2
                Colour: .i$
            elsif .v=3
                Colour: .u$
            elsif .v=4
                Colour: .e$
            else
                Colour: .o$
            endif

            .x0 = grain_time[.g]
            .x1 = min(duration_s,.x0+grain_dur[.g])

            Draw line: .x0,grain_f1[.g],.x1,grain_f1[.g]
            Draw line: .x0,grain_f2[.g],.x1,grain_f2[.g]
            Draw line: .x0,grain_f3[.g],.x1,grain_f3[.g]
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if out_channels = 1
        selectObject: output_sound
        Copy: "fgt_display_" + uid$
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
    Select inner viewport: 0.35,7.65,3.65,3.87
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + sampled actual formant guides"

    .specMax = .formantMax
    .specStep = max(0.002,duration_s/1100)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,3.94,5.04
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    .guideStep = max(1,ceiling(total_grains/180))

    for .g from 1 to total_grains
        if ((.g-1) mod .guideStep)=0
            .v = grain_vowel[.g]

            if .v=1
                Colour: .a$
            elsif .v=2
                Colour: .i$
            elsif .v=3
                Colour: .u$
            elsif .v=4
                Colour: .e$
            else
                Colour: .o$
            endif

            .x0 = grain_time[.g]
            .x1 = min(duration_s,.x0+grain_dur[.g])

            Draw line: .x0,grain_f1[.g],.x1,grain_f1[.g]
            Draw line: .x0,grain_f2[.g],.x1,grain_f2[.g]
            Draw line: .x0,grain_f3[.g],.x1,grain_f3[.g]
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.20,5.42
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MEASURED OUTPUT | representative channel after vowel-bus spatial mix"

    selectObject: .disp
    .wavePeak = Get absolute extremum: 0,0,"None"
    if .wavePeak < 0.001
        .wavePeak = 0.001
    endif
    .waveY = 1.05*.wavePeak

    Select inner viewport: .left,.right,5.49,6.24
    Axes: 0,duration_s,-.waveY,.waveY
    Paint rectangle: .bg$,0,duration_s,-.waveY,.waveY
    selectObject: .disp
    Colour: "{0.20,0.45,0.65}"
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
    Select inner viewport: 0.50,7.50,6.48,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.81,"half",
        ... "PROCESS  |  Poisson grains -> harmonic/noise source -> 5 vowel FormantGrids -> spatial bus mix"

    Text: 0.02,"left",0.60,"half",
        ... "EVENTS  |  expected " + fixed$(expectedGrains,1)
        ... + "  |  actual " + string$(total_grains)
        ... + "  |  realized " + fixed$(realizedDensity,2) + "/s"
        ... + "  |  " + seedLabel$

    Text: 0.02,"left",0.39,"half",
        ... "VOWELS a/i/u/e/o  |  " + string$(count_vowel#[1]) + "/"
        ... + string$(count_vowel#[2]) + "/" + string$(count_vowel#[3]) + "/"
        ... + string$(count_vowel#[4]) + "/" + string$(count_vowel#[5])
        ... + "  |  BW scale " + fixed$(formant_bandwidth_scale,2)

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02,"left",0.18,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(pre_peak,3)
        ... + "  |  pre-RMS " + fixed$(pre_rms,4)
        ... + "  |  final peak " + fixed$(out_peak,3)
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
