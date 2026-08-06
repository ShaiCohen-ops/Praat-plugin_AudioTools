# ============================================================
# Praat AudioTools - GRM-Style_Resonator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   GRM-STYLE (not the GRM algorithm): evokes the tuned resonant-bank
#   textures of GRM Tools, implemented offline as a bank of Hann
#   band-passes each driven through a delay-line resonator.
#   "GRM-style" = aesthetic lineage, not a reimplementation.
#
#   Delay tuning: the delays are FREQUENCY-TUNED INTEGER DELAY LINES,
#   not pitch tracking. Nothing analyses the input's pitch. The delay
#   is round(sampleRate / fc), so tuning is quantised to whole samples
#   and drifts at high frequencies - at 44.1 kHz a 3770 Hz band tunes
#   to 3675 Hz (44 cents flat); at 16 kHz it lands on 4000 Hz (103
#   cents sharp). The per-band tuning error is reported. Exact tuning
#   would need fractional-delay interpolation.
#
# Changelog v1.3 - reviewed by running the script under Parselmouth,
# so the figures below are measurements.
#   - THE RESONATOR WAS AN UNBOUNDED CASCADE. v1.2 applied a RECURSIVE
#     comb Formula once per iteration, each on the previous result, so
#     the transfer function was a product of 1/(1 - a^i z^-iD) rather
#     than a set of echoes. At a shared resonance the gains multiply:
#     for decay 0.95 over 40 iterations that is 6.1e11, about 235.7 dB.
#     Measured natural wet peak from a 0.2-peak noise input: Formant-ish
#     0.161, Inharmonic metallic 0.868, Harmonic Organ 56.6, Sparse
#     Bells 2.7 BILLION. Scale peak hid it; it did not make the filter
#     stable. Resonator_mode now offers two bounded models, and both
#     were checked before shipping on the same noise: finite echoes
#     gives 0.89 / 1.22 / 1.64 / 2.65 and the single feedback comb
#     0.91 / 1.21 / 1.64 / 2.69 for those four presets.
#   - THE WET NORMALIZATION CANCELLED gainDB. Scale peak: 0.9 on the
#     wet bus, then Scale peak: finalPeak at the end, meant gainDB of
#     -30, 0, +6 and +30 all produced sample-identical output, and a
#     0.2-peak and a 0.02-peak sine both came out at 0.99. Both are
#     replaced by attenuate-only ceilings, so a quiet input stays quiet
#     and gainDB does what it says.
#   - That also fixes the spectral-residue problem: a 440 Hz sine with
#     a single 3000 Hz resonator had a natural peak of 0.000665 and was
#     amplified to 0.99, turning filter residue and edge transients
#     into a loud ring at 3.09 kHz. Nothing is lifted now.
#   - Multichannel: the wet bus is a two-channel panner by design, so
#     more than two channels is refused with an explanation instead of
#     being silently mangled - v1.2 put the wet only in channels 1-2
#     and left 3 and up with dry alone. The band source is the loudest
#     channel, not a mono fold, so anti-phase stereo no longer
#     cancels to silence at 100% wet.
#   - xmin survives at every mix setting. The wet bus was created over
#     0..duration, so at 100% wet a Sound at 5.137-6.137 s came back at
#     0-1 s, while partial mixes kept the domain from the dry copy.
#   - Spectral tilt follows FREQUENCY, not list order. v1.2 tilted by
#     index, so an unsorted list could damp a low band and boost a high
#     one - the opposite of the setting's name.
#   - Band-edge smoothing follows the bandwidth. It was fixed at
#     100 Hz, so the Bells preset's 35 Hz bands had transition regions
#     nearly three times wider than the band itself.
#   - Optional Tail_ms so a resonance at the end of the file is not
#     cut off with it.
#   - Random panning takes a seed.
#   - Validation on band count, frequencies against Nyquist, decay,
#     iterations, mix and peak. ringIterations = 0 used to fail because
#     delSamples was printed before it existed, and an empty frequency
#     list crashed on bandIDs[1].
#   - Visualization: a single band no longer collapses the axes ("Top
#     and bottom should not be equal"), band centres draw as visible
#     markers, transition regions are shown, input and output share a
#     scale, and "All Center" is described as dual-mono.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form GRM-Style Resonator v1.3
    optionmenu Preset: 1
        option Custom
        option Harmonic (organ-like)
        option Inharmonic metallic
        option Formant-ish (voice coloring)
        option Sparse bells
    integer numBands 6
    optionmenu tuningMode: 1
        option Manual list
        option Harmonic series
        option Inharmonic ratios
    sentence manualFrequencies 300 520 890 1440 2330 3770
    real baseFreqHz 110
    sentence ratioList 1 1.41 1.89 2.37 2.98 3.56
    real bandwidthHz 80
    optionmenu Resonator_mode: 1
        option Finite echoes (N taps, bounded)
        option Single feedback comb (decay only)
    integer ringIterations 3
    real ringDecay 0.6
    real gainDB 6
    optionmenu Gain_Profile: 2
        option Flat (Equal)
        option Dampen Highs (Tilt Down)
        option Boost Highs (Tilt Up)
    optionmenu Stereo_Panning: 3
        option All Center (dual mono)
        option Stereo Spread (Alternate)
        option Wide Spread (Hard L/R)
        option Left Heavy
        option Right Heavy
        option V Shape (Outside In)
        option Random
    real dryWet 0.6
    optionmenu Output_level_mode: 2
        option Natural level
        option Safety ceiling (attenuate only)
        option Peak normalize
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED SETTINGS - edit here, not in the form
# ============================================================
# Praat forms do not scroll, so the settings you would fix once for a
# rig rather than change per file live here. The names are the same
# ones the body uses, so moving any line back into the form needs no
# other edit.

# Delay tuning. 1 = derive the delay from the band frequency,
# 0 = use Manual_Ring_Delay_Ms for every band.
tune_Delay_To_Pitch = 1
manual_Ring_Delay_Ms = 8

# Silence added before processing so a resonance at the end of the file
# is not cut off with it. The output is longer by this amount.
tail_ms = 0

# 0 = unseeded; any other value makes Random panning reproducible.
random_seed = 0

# Ceiling used by Output_level_mode 2 and 3.
finalPeak = 0.99

# Keep the per-band Sounds in the object list after mixing.
keep_individual_bands = 0

# --- 1. PRESETS ---
if preset = 2
    tuningMode = 2
    baseFreqHz = 110
    numBands = 8
    bandwidthHz = 100
    tune_Delay_To_Pitch = 1
    ringIterations = 20
    ringDecay = 0.85
    gain_Profile = 2
    stereo_Panning = 2
    presetName$ = "HarmonicOrgan"
elsif preset = 3
    tuningMode = 3
    baseFreqHz = 200
    ratioList$ = "1 1.59 2.14 2.76 3.41 4.07"
    numBands = 6
    bandwidthHz = 40
    tune_Delay_To_Pitch = 1
    ringIterations = 10
    ringDecay = 0.7
    gain_Profile = 1
    stereo_Panning = 3
    presetName$ = "Metallic"
elsif preset = 4
    tuningMode = 1
    manualFrequencies$ = "500 1500 2500 3500 4500"
    numBands = 5
    bandwidthHz = 200
    tune_Delay_To_Pitch = 0
    manual_Ring_Delay_Ms = 6
    ringIterations = 2
    ringDecay = 0.4
    gain_Profile = 2
    stereo_Panning = 6
    presetName$ = "Formant"
elsif preset = 5
    tuningMode = 1
    manualFrequencies$ = "287 645 1203 2156"
    numBands = 4
    bandwidthHz = 35
    tune_Delay_To_Pitch = 1
    ringIterations = 40
    ringDecay = 0.95
    gain_Profile = 2
    gainDB = 12
    stereo_Panning = 7
    presetName$ = "Bells"
else
    presetName$ = "Custom"
endif

# --- 2. SETUP ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")
selectObject: original
samplingRate = Get sampling frequency
inputDuration = Get total duration
originalXmin = Get start time
nyquist = samplingRate / 2
numChannels = Get number of channels
inputPeak = Get absolute extremum: 0, 0, "None"

# The wet bus pans bands across TWO channels; there is no defined
# placement for a third. v1.2 mixed the wet into channels 1-2 only and
# left channels 3 and up carrying dry alone.
if numChannels > 2
    exitScript: "This Sound has " + string$(numChannels) + " channels. The resonator bank " +
    ... "pans its bands across a stereo field, so the wet signal is inherently two-channel " +
    ... "and there is no defined placement for further channels. Use a mono or stereo " +
    ... "Sound, or process the channel pairs separately."
endif

# --- Validation ---
if ringDecay < 0 or ringDecay >= 1
    exitScript: "ringDecay must be at least 0 and below 1 (got " + fixed$(ringDecay, 3) +
    ... "). At 1 or above the resonator does not decay and the output grows without bound."
endif
if ringIterations < 0
    exitScript: "ringIterations cannot be negative."
endif
if ringIterations > 200
    exitScript: "ringIterations above 200 is beyond any useful decay length."
endif
if dryWet < 0 or dryWet > 1
    exitScript: "dryWet must be between 0 and 1 (got " + fixed$(dryWet, 3) + ")."
endif
if finalPeak <= 0 or finalPeak > 1
    exitScript: "finalPeak must be greater than 0 and at most 1."
endif
if bandwidthHz <= 0
    exitScript: "bandwidthHz must be greater than 0."
endif
if tail_ms < 0
    tail_ms = 0
endif

if random_seed <> 0
    random_initializeWithSeedUnsafelyButPredictably: random_seed
endif

# --- 3. PARSE FREQUENCIES ---
if tuningMode = 1
    str$ = manualFrequencies$
    count = 0
    repeat
        space = index(str$, " ")
        if space > 0
            token$ = left$(str$, space - 1)
            str$ = mid$(str$, space + 1, 10000)
        else
            token$ = str$
            str$ = ""
        endif
        token$ = replace$(token$, " ", "", 0)
        if token$ <> ""
            count = count + 1
            freqs[count] = number(token$)
        endif
    until str$ = ""
    actualNumBands = count
    tuningStr$ = "Manual List"
elsif tuningMode = 2
    actualNumBands = numBands
    for i from 1 to actualNumBands
        freqs[i] = baseFreqHz * i
    endfor
    tuningStr$ = "Harmonic (" + string$(baseFreqHz) + " Hz)"
else
    str$ = ratioList$
    count = 0
    repeat
        space = index(str$, " ")
        if space > 0
            token$ = left$(str$, space - 1)
            str$ = mid$(str$, space + 1, 10000)
        else
            token$ = str$
            str$ = ""
        endif
        token$ = replace$(token$, " ", "", 0)
        if token$ <> ""
            count = count + 1
            freqs[count] = baseFreqHz * number(token$)
        endif
    until str$ = ""
    actualNumBands = count
    tuningStr$ = "Inharmonic (" + string$(baseFreqHz) + " Hz)"
endif

if actualNumBands > numBands
    actualNumBands = numBands
endif
# v1.2 went straight on to bandIDs[1] with no bands at all.
if actualNumBands < 1
    exitScript: "No usable band frequencies were found. Check the frequency list, the " +
    ... "ratio list, or numBands."
endif

# Every centre must be inside the usable spectrum
minFreqSeen = freqs[1]
maxFreqSeen = freqs[1]
for i from 1 to actualNumBands
    if freqs[i] <= 20 or freqs[i] >= nyquist - 20
        exitScript: "Band " + string$(i) + " is at " + fixed$(freqs[i], 1) + " Hz, outside " +
        ... "the usable range 20 to " + fixed$(nyquist - 20, 1) + " Hz for this sample rate."
    endif
    if freqs[i] < minFreqSeen
        minFreqSeen = freqs[i]
    endif
    if freqs[i] > maxFreqSeen
        maxFreqSeen = freqs[i]
    endif
endfor

# --- 4. GAIN PROFILE (BY FREQUENCY, NOT BY INDEX) ---
# v1.2 tilted by list position, so an unsorted list could damp a low
# band and boost a high one - the reverse of what the setting says.
baseGainLin = 10 ^ (gainDB / 20)
logMin = ln(minFreqSeen)
logMax = ln(maxFreqSeen)
for i from 1 to actualNumBands
    if logMax > logMin
        fpos = (ln(freqs[i]) - logMin) / (logMax - logMin)
    else
        fpos = 0
    endif
    if gain_Profile = 1
        bandGain[i] = baseGainLin
        gainProfileStr$ = "Flat"
    elsif gain_Profile = 2
        bandGain[i] = baseGainLin * (1.0 - 0.8 * fpos)
        gainProfileStr$ = "Dampen Highs"
    else
        bandGain[i] = baseGainLin * (0.2 + 0.8 * fpos)
        gainProfileStr$ = "Boost Highs"
    endif
endfor

if resonator_mode = 1
    resStr$ = "Finite echoes (" + string$(ringIterations) + " taps)"
else
    resStr$ = "Single feedback comb"
endif

clearinfo
writeInfoLine: "=== GRM-Style Resonator v1.3 ==="
appendInfoLine: "Input: ", originalName$, " (", fixed$(inputDuration, 3), " s, ",
    ... numChannels, " ch, ", samplingRate, " Hz)"
appendInfoLine: "Preset: ", presetName$, " | Bands: ", actualNumBands, " | ", resStr$
if resonator_mode = 1
    appendInfoLine: "  Peak resonance gain <= ",
        ... fixed$((1 - ringDecay ^ (ringIterations + 1)) / (1 - ringDecay), 2), "x"
else
    appendInfoLine: "  Peak resonance gain <= ", fixed$(1 / (1 - ringDecay), 2),
        ... "x (ringIterations is not used by this mode)"
endif
appendInfoLine: ""

# ============================================================
# Work copy at time 0, plus optional tail
# ============================================================
# The wet bus is created over 0..duration, so at 100% wet a Sound
# living at 5.137-6.137 s came back at 0-1 s in v1.2.
selectObject: original
workSound = Copy: "grm_work"
Shift times to: "start time", 0

if tail_ms > 0
    tailSec = tail_ms / 1000
    Create Sound from formula: "grm_tail", numChannels, 0, tailSec, samplingRate, "0"
    tailPad = selected("Sound")
    selectObject: workSound
    plusObject: tailPad
    Concatenate
    extended = selected("Sound")
    removeObject: workSound, tailPad
    workSound = extended
    appendInfoLine: "Tail: ", fixed$(tail_ms, 0), " ms added so the resonance can decay"
endif

selectObject: workSound
duration = Get total duration
totalSamples = Get number of samples

# Band source: a real channel, never a fold. An anti-phase stereo pair
# cancelled to silence in v1.2 and produced a silent wet bus.
if numChannels = 1
    selectObject: workSound
    bandSource = Copy: "grm_bandsrc"
    srcStr$ = "mono"
else
    bestRms = -1
    pickCh = 1
    for ch from 1 to numChannels
        selectObject: workSound
        probe = Extract one channel: ch
        probeRms = Get root-mean-square: 0, 0
        removeObject: probe
        if probeRms > bestRms
            bestRms = probeRms
            pickCh = ch
        endif
    endfor
    selectObject: workSound
    bandSource = Extract one channel: pickCh
    srcStr$ = "channel " + string$(pickCh)
endif
appendInfoLine: "Band source: ", srcStr$

# --- 5. GENERATION LOOP ---
appendInfoLine: "Generating ", actualNumBands, " bands..."

for i from 1 to actualNumBands
    fc = freqs[i]
    low = fc - bandwidthHz / 2
    high = fc + bandwidthHz / 2
    if low < 20
        low = 20
    endif
    if high > nyquist - 20
        high = nyquist - 20
    endif
    if low >= high
        low = max(20, fc - 10)
        high = min(nyquist - 20, fc + 10)
    endif
    bandLow[i] = low
    bandHigh[i] = high

    # Edge smoothing follows the band. Fixed at 100 Hz it made the
    # Bells preset's 35 Hz bands into transitions three times wider
    # than the band itself.
    smoothHz = max(10, min(100, (high - low) / 2))
    bandSmooth[i] = smoothHz

    selectObject: bandSource
    bandSound = Filter (pass Hann band): low, high, smoothHz

    selectObject: bandSound
    Formula: "self * " + string$(bandGain[i])

    # --- Delay ---
    if tune_Delay_To_Pitch
        delSamples = round(samplingRate / fc)
    else
        if manual_Ring_Delay_Ms > 0
            delSamples = round(manual_Ring_Delay_Ms * samplingRate / 1000.0)
        else
            delSamples = 1
        endif
    endif
    if delSamples < 1
        delSamples = 1
    endif
    bandDelay[i] = delSamples
    tunedTo[i] = samplingRate / delSamples
    if tune_Delay_To_Pitch
        centsErr[i] = 1200 * log2(tunedTo[i] / fc)
    else
        centsErr[i] = 0
    endif

    # --- Resonator ---
    if ringIterations > 0 and ringDecay > 0
        if resonator_mode = 1
            # Finite echoes: every tap reads the ORIGINAL band, so the
            # result is x + a x[n-D] + a^2 x[n-2D] + ... and the gain is
            # bounded by (1 - a^(N+1)) / (1 - a). v1.2 applied a
            # recursive comb once per iteration ON THE PREVIOUS RESULT,
            # cascading them: 6.1e11 at decay 0.95 over 40 iterations.
            selectObject: bandSound
            dryBand = Copy: "band_dry"
            dryBand$ = string$(dryBand)
            for it from 1 to ringIterations
                a = ringDecay ^ it
                d = delSamples * it
                if d < totalSamples - 1
                    selectObject: bandSound
                    Formula (part): (d + 0.25) / samplingRate, duration, 1, 1,
                        ... "self + " + string$(a) + " * object[" + dryBand$ +
                        ... ", 1, col - " + string$(d) + "]"
                endif
            endfor
            removeObject: dryBand
        else
            # Single feedback comb: y[n] = x[n] + a y[n-D]. Bounded by
            # 1 / (1 - a) at resonance.
            selectObject: bandSound
            Formula: "if col > " + string$(delSamples) + " then self + " + string$(ringDecay) +
                ... " * self[col-" + string$(delSamples) + "] else self fi"
        endif
    endif

    selectObject: bandSound
    Rename: "band" + string$(i)
    bandIDs[i] = selected("Sound")

    if tune_Delay_To_Pitch
        appendInfoLine: "  Band ", i, ": ", fixed$(fc, 1), " Hz -> delay ", delSamples,
            ... " spl = ", fixed$(tunedTo[i], 1), " Hz (", fixed$(centsErr[i], 1), " cents)"
    else
        appendInfoLine: "  Band ", i, ": ", fixed$(fc, 1), " Hz, delay ", delSamples, " spl"
    endif
endfor

# --- 6. PANS ---
for i from 1 to actualNumBands
    if stereo_Panning = 1
        pL[i] = 1.0
        pR[i] = 1.0
        panningStr$ = "Dual mono"
    elsif stereo_Panning = 2
        if (i mod 2) = 1
            pL[i] = 1.0
            pR[i] = 0.3
        else
            pL[i] = 0.3
            pR[i] = 1.0
        endif
        panningStr$ = "Stereo Alternate"
    elsif stereo_Panning = 3
        if (i mod 2) = 1
            pL[i] = 1.0
            pR[i] = 0.0
        else
            pL[i] = 0.0
            pR[i] = 1.0
        endif
        panningStr$ = "Hard L/R"
    elsif stereo_Panning = 4
        pL[i] = 1.0
        pR[i] = 0.3
        panningStr$ = "Left Heavy"
    elsif stereo_Panning = 5
        pL[i] = 0.3
        pR[i] = 1.0
        panningStr$ = "Right Heavy"
    elsif stereo_Panning = 6
        mid = (actualNumBands + 1) / 2
        if i <= mid
            if mid > 1
                prog = (i - 1) / (mid - 1)
            else
                prog = 0
            endif
            pL[i] = 1.0 - prog * 0.7
            pR[i] = 0.3 + prog * 0.7
        else
            rem = actualNumBands - mid
            if rem > 0
                prog = (i - mid) / rem
            else
                prog = 0
            endif
            pL[i] = 0.3 + prog * 0.7
            pR[i] = 1.0 - prog * 0.7
        endif
        panningStr$ = "V-Shape"
    else
        rr = randomUniform(0, 1)
        pL[i] = 1.0 - rr
        pR[i] = rr
        if random_seed <> 0
            panningStr$ = "Random (seed " + string$(random_seed) + ")"
        else
            panningStr$ = "Random (unseeded)"
        endif
    endif
endfor

# --- 7. STEREO MIX ---
appendInfoLine: ""
appendInfoLine: "Mixing..."

Create Sound from formula: "Wet_Mix", 2, 0, duration, samplingRate, "0"
wetSum = selected("Sound")

for i from 1 to actualNumBands
    theBand = bandIDs[i]
    selectObject: wetSum
    Formula (part): 0, duration, 1, 1,
        ... "self + object[" + string$(theBand) + ", 1, col] * " + string$(pL[i])
    Formula (part): 0, duration, 2, 2,
        ... "self + object[" + string$(theBand) + ", 1, col] * " + string$(pR[i])
endfor

selectObject: wetSum
wetNaturalPeak = Get absolute extremum: 0, 0, "None"
appendInfoLine: "  Natural wet peak: ", fixed$(wetNaturalPeak, 6)

# Attenuate only. v1.2's Scale peak: 0.9 here meant gainDB had no
# effect at all - -30, 0, +6 and +30 dB all gave identical output - and
# a 0.000665-peak residue was amplified to full scale.
wetGuard = 1
if wetNaturalPeak > 4
    wetGuard = 4 / wetNaturalPeak
    selectObject: wetSum
    Formula: "self * " + string$(wetGuard)
    appendInfoLine: "  Wet bus attenuated x", fixed$(wetGuard, 5),
        ... " to keep the summing stage bounded"
endif

# --- 8. DRY/WET ---
selectObject: workSound
dry = Copy: "dry_temp"
selectObject: dry
dryCh = Get number of channels
if dryCh = 1
    Convert to stereo
    stereoDry = selected("Sound")
    removeObject: dry
    dry = stereoDry
endif

selectObject: dry
Formula: "self * " + string$(1 - dryWet) + " + object[" + string$(wetSum) +
    ... ", row, col] * " + string$(dryWet)
output = dry
selectObject: wetSum
Remove

# --- 9. OUTPUT LEVEL ---
selectObject: output
preLevelPeak = Get absolute extremum: 0, 0, "None"
levelGain = 1
levelAction$ = "natural level"

if output_level_mode = 2
    if preLevelPeak > finalPeak and preLevelPeak > 0
        Scale peak: finalPeak
        levelGain = finalPeak / preLevelPeak
        levelAction$ = "ceiling applied"
    else
        levelAction$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if preLevelPeak > 0
        Scale peak: finalPeak
        levelGain = finalPeak / preLevelPeak
        levelAction$ = "peak normalized"
    endif
endif

selectObject: output
outPeak = Get absolute extremum: 0, 0, "None"
outDuration = Get total duration

# ============================================================
# VISUALIZATION (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    Erase all

    selectObject: workSound
    vizInPeak = Get absolute extremum: 0, 0, "None"
    vizAmp = max(vizInPeak, outPeak)
    if vizAmp < 0.001
        vizAmp = 0.001
    endif
    vizAmp = vizAmp * 1.1

    if tune_Delay_To_Pitch
        tunedStr$ = "Yes"
    else
        tunedStr$ = "No"
    endif

    # --- TITLE ---
    Select outer viewport: 0, 8, 0, 0.6
    Select inner viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##GRM-Style Resonator##"
    Font size: 7
    Colour: "{0.40, 0.40, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... originalName$ + " [" + presetName$ + "]"
        ... + "  |  " + resStr$
        ... + "  |  frequency-tuned integer delays"
        ... + "  |  " + panningStr$

    # --- 1. INPUT ---
    Select outer viewport: 0, 4, 0.7, 2.0
    Select inner viewport: 0.6, 3.75, 0.8, 1.9
    selectObject: workSound
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, duration, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Input (shared scale with output)"

    # --- 2. BAND ARCHITECTURE ---
    Select outer viewport: 4, 8, 0.7, 2.0
    Select inner viewport: 4.55, 7.7, 0.8, 1.9

    plotMinFreq = bandLow[1] - bandSmooth[1]
    plotMaxFreq = bandHigh[1] + bandSmooth[1]
    for i from 1 to actualNumBands
        if bandLow[i] - bandSmooth[i] < plotMinFreq
            plotMinFreq = bandLow[i] - bandSmooth[i]
        endif
        if bandHigh[i] + bandSmooth[i] > plotMaxFreq
            plotMaxFreq = bandHigh[i] + bandSmooth[i]
        endif
    endfor
    # A single band gave identical top and bottom, and Praat refused
    # the axes with "Top and bottom should not be equal".
    freqSpan = plotMaxFreq - plotMinFreq
    if freqSpan < 1
        freqSpan = max(1, plotMaxFreq * 0.1)
    endif
    plotMinFreq = max(0, plotMinFreq - freqSpan * 0.1)
    plotMaxFreq = plotMaxFreq + freqSpan * 0.1
    if plotMaxFreq <= plotMinFreq
        plotMaxFreq = plotMinFreq + 1
    endif

    Axes: 0, actualNumBands + 1, plotMinFreq, plotMaxFreq
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actualNumBands + 1, plotMinFreq, plotMaxFreq

    for i from 1 to actualNumBands
        if gain_Profile = 1
            bandColor$ = "{0.30, 0.50, 0.80}"
        else
            shade = bandGain[i] / max(baseGainLin, 0.000001)
            bandColor$ = "{" + fixed$(0.15 + shade * 0.25, 2) + ", " +
                ... fixed$(0.30 + shade * 0.30, 2) + ", " + fixed$(0.55 + shade * 0.30, 2) + "}"
        endif
        # Transition regions, which v1.2 never drew
        Paint rectangle: "{0.88, 0.90, 0.94}", i - 0.35, i + 0.35,
            ... bandLow[i] - bandSmooth[i], bandHigh[i] + bandSmooth[i]
        Paint rectangle: bandColor$, i - 0.3, i + 0.3, bandLow[i], bandHigh[i]

        # A visible centre marker. v1.2 drew a line from a point to
        # itself, which renders as nothing.
        Colour: "{0.80, 0.30, 0.30}"
        Line width: 2
        Draw line: i - 0.3, freqs[i], i + 0.3, freqs[i]
        Line width: 1
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Bands: pass (dark) + Hann transition (pale)"
    Text bottom: "yes", "Band number"

    # --- 3. PANNING ---
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.7, 2.2, 3.4
    Axes: 0, actualNumBands + 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actualNumBands + 1, 0, 1
    for i from 1 to actualNumBands
        Paint rectangle: "{0.90, 0.70, 0.30}", i - 0.35, i, 0.5, 0.5 + pL[i] * 0.45
        Paint rectangle: "{0.30, 0.60, 0.80}", i, i + 0.35, 0.5, 0.5 - pR[i] * 0.45
    endfor
    Colour: "{0.50, 0.50, 0.50}"
    Line width: 1.5
    Draw line: 0, 0.5, actualNumBands + 1, 0.5
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan"
    Text top: "no", "Panning: " + panningStr$ + "  (up = left, down = right)"
    Text bottom: "yes", "Band number"

    # --- 4. OUTPUT ---
    Select outer viewport: 0, 8, 3.6, 4.9
    Select inner viewport: 0.6, 7.7, 3.7, 4.8
    selectObject: output
    Colour: "{0.20, 0.60, 0.50}"
    Draw: 0, duration, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Output (stereo, same scale as input)"
    Text bottom: "yes", "Time (s)"

    # --- 5. GAIN PROFILE ---
    Select outer viewport: 0, 4, 5.0, 6.2
    Select inner viewport: 0.6, 3.75, 5.1, 6.1
    gainTop = baseGainLin * 1.2
    if gainTop <= 0
        gainTop = 1
    endif
    Axes: 0, actualNumBands + 1, 0, gainTop
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actualNumBands + 1, 0, gainTop
    Colour: "{0.70, 0.30, 0.70}"
    Line width: 3
    for i from 1 to actualNumBands - 1
        Draw line: i, bandGain[i], i + 1, bandGain[i + 1]
    endfor
    Line width: 1
    for i from 1 to actualNumBands
        Paint circle: "{0.50, 0.20, 0.50}", i, bandGain[i], 0.12
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain (linear)"
    Text top: "no", "Tilt by frequency: " + gainProfileStr$
    Text bottom: "yes", "Band number"

    # --- 6. INFO ---
    Select outer viewport: 4, 8, 5.0, 6.2
    Select inner viewport: 4.55, 7.7, 5.1, 6.1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.05, "left", 0.90, "half", "##Parameters##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.05, "left", 0.76, "half", "Bands: " + string$(actualNumBands) + "  |  " + tuningStr$
    Text: 0.05, "left", 0.64, "half", "Bandwidth: " + fixed$(bandwidthHz, 0) + " Hz"
    Text: 0.05, "left", 0.52, "half", resStr$ + ", decay " + fixed$(ringDecay, 2)
    Text: 0.05, "left", 0.40, "half", "Tuned delay: " + tunedStr$
    Text: 0.05, "left", 0.28, "half", "Gain: " + fixed$(gainDB, 1) + " dB, " + gainProfileStr$
    Text: 0.05, "left", 0.16, "half", "Dry/Wet: " + fixed$(dryWet * 100, 0) + "% wet"
    Text: 0.55, "left", 0.76, "half", "Wet peak: " + fixed$(wetNaturalPeak, 4)
    Text: 0.55, "left", 0.64, "half", "Out peak: " + fixed$(outPeak, 4)
    Text: 0.55, "left", 0.52, "half", "Level: " + levelAction$
    Text: 0.55, "left", 0.40, "half", "Duration: " + fixed$(outDuration, 2) + " s"
    Text: 0.55, "left", 0.28, "half", "Source: " + srcStr$
    Text: 0.55, "left", 0.16, "half", "Seed: " + string$(random_seed)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# --- CLEANUP AND FINISH ---
if keep_individual_bands = 0
    selectObject: bandIDs[1]
    for i from 2 to actualNumBands
        plusObject: bandIDs[i]
    endfor
    Remove
endif
removeObject: bandSource, workSound

selectObject: output
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + "_GRMstyle_" + presetName$
finalName$ = selected$("Sound")

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "  Duration: ", fixed$(inputDuration, 3), " s -> ", fixed$(outDuration, 3), " s"
appendInfoLine: "  Peak: ", fixed$(inputPeak, 4), " -> ", fixed$(outPeak, 4),
    ... " (", levelAction$, ")"
if output_level_mode <> 3 and outPeak > 1
    appendInfoLine: "  WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

selectObject: output
if play_result
    if outPeak > 1
        appendInfoLine: "Playing a scaled copy (peak exceeds 1.0)..."
        playCopy = Copy: "play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        Play
    endif
endif

selectObject: output
