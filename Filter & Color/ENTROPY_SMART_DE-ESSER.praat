# ============================================================
# Praat AudioTools - ENTROPY_SMART_DE-ESSER.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8 (2026) - HF-ratio detector with spectral-entropy confidence
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Hybrid split-band de-esser. Candidate sibilance is detected from
#   high-frequency intensity relative to full-band intensity, with an
#   absolute HF level gate. Spectral entropy INSIDE the selected HF band
#   then acts as a confidence modifier: noise-like HF receives the full
#   requested reduction, while peaky/tonal HF receives less.
#
#       residual  = signal - HF band
#       output    = residual + HF band x gain
#
#   Reduction is applied ONLY to the selected HF band, so the
#   fundamental, low formants and body of the voice keep their level.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.8 (2026):
#   - Added spectral entropy as a real secondary detector. The existing
#     HF/full-band ratio and absolute HF gate remain primary; normalized
#     Shannon entropy is measured only inside the selected HF band and
#     smoothly scales the requested reduction.
#   - Low-entropy (tonal/peaky) HF can receive substantially less
#     attenuation; high-entropy (noise-like) HF receives the full
#     ratio-derived attenuation.
#   - Entropy uses a 20 ms Gaussian spectrogram and a soft confidence
#     transition rather than a binary entropy gate.
#   - Audio remains split-band, multichannel, and phase/image preserving
#     in the same sense as v0.7: one shared gain curve is applied only to
#     each channel's HF band.
#
# Changelog v0.7 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v0.6 - Parselmouth-verified again. The v0.5 architecture
# passed: split-band confirmed (a 200 Hz tone measured 0.1000000 /
# 0.1000001 / 0.1000000 before, during and after a sibilant, and the
# removed-only signal held just 2.7e-7 of it), identity with no
# sibilance (0 frames, max difference 0), the HF gate (1e-6 noise:
# 243/243 frames gated, max error 0), edge handling (-10.79 dB on a
# 10 ms burst at the file start against -11.85 mid-file), xmin, four
# channels and all presets. Four things remained:
#   - THE HF GATE OVERRODE ATTACK AND RELEASE. v0.5 smoothed the ratio
#     and THEN forced gain = 1 whenever HF sat below the gate, so the
#     gate cut straight through the envelope: a decaying HF tone
#     crossing the gate jumped from 0.2512 to 1.0000 inside one 4 ms
#     frame despite a 100 ms release, and a rising one snapped to
#     0.252 despite a 100 ms attack. The gate is applied to the
#     detector target BEFORE anything is smoothed, and attack/release
#     now act on the GAIN itself, so gate transitions obey the times.
#   - DETECTION PICKED THE WRONG CHANNEL. Choosing the loudest channel
#     by FULL-band RMS is not where sibilance lives: a stereo file with
#     a loud low tone in channel 1 and the only sibilant burst in a
#     quieter channel 2 reduced 0 frames and left channel 2 untouched.
#     The default is now the strongest HF evidence per frame across all
#     channels, with one shared gain curve preserving the image.
#   - THE SOFT KNEE STILL HAD A SLOPE STEP. v0.5 clamped the reduction
#     to 0 through the lower half of the knee, so the slope still
#     jumped at the threshold - a smoothed onset, not a symmetric knee.
#     It is now the standard quadratic knee, C1 at both edges.
#   - The plots folded to mono, so anti-phase stereo drew as silence
#     even with correct audio. They use a real channel now, named in
#     the zoom caption.
#   - Added a Telephony band preset (2.5-3.7 kHz) for narrowband
#     material, where the default 4-8 kHz band is at or above Nyquist.
#
# Changelog v0.5 - reviewed by running the script under Parselmouth,
# so the figures below are measurements.
#   - SPLIT-BAND. v0.4 multiplied the WHOLE signal by the gain curve,
#     so everything ducked when an "s" arrived: with a steady 200 Hz
#     tone under a mid-file sibilant, the 200 Hz component fell from
#     0.100 to 0.0457 - 6.8 dB of ducking on content that is nowhere
#     near the sibilant band. That is wideband de-essing, not
#     de-essing. Reduction now applies to the HF band alone, via
#     output = signal - HF x (1 - gain), which is exactly
#     residual + HF x gain and is bit-identical to the input wherever
#     gain is 1.
#   - "Listen to removed" is now only the removed HF, HF x (1 - gain).
#     v0.4's version audibly contained the 200 Hz tone it had ducked.
#   - PEAK NORMALIZATION REMOVED FROM THE DEFAULT PATH. v0.4 always ran
#     Scale peak: 0.95, so a quiet tone with ZERO frames reduced came
#     out 33.5 dB louder (0.020 -> 0.950), Dry/Wet = 0 returned a
#     maximum difference of 0.93 from the input, and white noise
#     peaking at 4e-6 was lifted to 0.95. Output_level_mode now offers
#     natural level (default), match input RMS, safety ceiling or
#     explicit peak normalization.
#   - xmin handled. The gain tier was built over 0..duration while the
#     Sound sat elsewhere: the same file at 5 s reduced 0 frames
#     against 47 at 0 s, output identical to input, and the plot died
#     with "Argument left Bottom and top has the value undefined".
#     All work happens on a copy shifted to 0 now.
#   - The frame grid comes from the Intensity object. v0.4 sampled
#     every 5 ms from t = 0, but Praat's first frame centre sits about
#     half a physical window in, so early samples were undefined,
#     became -80 dB and gave ratio 0. Measured on a sibilant burst at
#     the very start: 0.0 dB reduction at 10 and 20 ms, -1.37 dB at
#     50 ms and -3.81 dB at 100 ms, against 11.6-11.8 dB for the same
#     burst mid-file. The tier is now built on the real frame times
#     with the first and last gains held out to the file edges.
#   - Absolute HF gate. Detection was ratio-only, so white noise at
#     about 1e-6 had 177 of 200 frames "reduced" purely because its
#     spectral tilt was high. A frame now also needs real HF level
#     above Hf_gate_dBFS.
#   - Analysis no longer folds to mono. Anti-phase stereo cancelled
#     and gave 0 frames reduced with the output untouched; the loudest
#     channel is used instead. Every channel is processed and kept -
#     v0.4 turned 4-channel input into 2 channels without a word.
#   - Real soft knee. v0.4's "soft knee" was gain = 1 below threshold
#     and a straight line above it: continuous in value, discontinuous
#     in slope, i.e. a hard knee. Knee_width now gives a smooth
#     transition centred on the threshold.
#   - Short files exit with a message. Below the Intensity window
#     length the run aborted with Praat's "Sound shorter than window
#     length"; 5, 20, 50 and 64 ms all failed, 80 ms worked.
#   - Validation on the HF band, threshold, mix, ceiling and duration.
#   - Attack and Release are labelled as what they are: smoothing on a
#     detector envelope that the Intensity window has already smeared
#     over tens of milliseconds. A 2 ms attack does not make a 2 ms
#     detector.
# ============================================================

form Entropy Smart De-Esser v0.8
    optionmenu Preset: 1
        option Custom
        option Light De-Essing
        option Medium De-Essing
        option Heavy De-Essing
        option Aggressive
        option Gentle Touch
        option Telephony band (2.5-3.7 kHz)
    positive Hf_low_hz 4000
    positive Hf_high_hz 8000
    real Threshold 0.4
    positive Max_reduction_db 12.0
    positive Attack_ms 5
    positive Release_ms 50
    real Dry_wet_mix 1.0
    optionmenu Output_level_mode: 1
        option Natural level
        option Match input RMS
        option Safety ceiling (attenuate only)
        option Peak normalize
    positive Ceiling_peak 0.95
    boolean Listen_to_removed 0
    boolean Show_spectrogram 1
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ============================================================
# ADVANCED SETTINGS - edit here, not in the form
# ============================================================
# Praat forms do not scroll, so the rarely-changed controls live here.

# Width of the soft knee, in ratio units, centred on Threshold.
# 0 gives the old hard knee.
knee_width = 0.12

# A frame counts as sibilant only if the HF band is at least this
# loud in absolute terms, as well as high in ratio. Without it,
# near-silent noise reads as pure sibilance (1e-6 noise had 177 of
# 200 frames "reduced").
hf_gate_dBFS = -55

# Spectral-entropy confidence, measured ONLY inside the selected HF band.
# entropy_low..entropy_high maps entropy to a 0..1 confidence with a
# smoothstep curve. entropy_weight says how strongly that confidence can
# reduce the ratio-derived attenuation. At the default 0.70, low-entropy
# HF keeps 30% of the ratio-derived reduction rather than being hard-gated.
entropy_window_ms = 20
entropy_freq_step_Hz = 20
entropy_low = 0.55
entropy_high = 0.90
entropy_weight = 0.70

# Minimum pitch for To Intensity. The physical analysis window is
# 6.4 / this, so 200 Hz gives about 32 ms - short enough to see a
# sibilant, long enough to be stable. v0.4 used 100 Hz, i.e. a 64 ms
# window, which is why brief sibilants smeared.
detector_min_pitch_Hz = 200

# What drives detection:
#   1 = channel 1
#   2 = loudest channel by full-band RMS
#   3 = strongest HF evidence per frame, across all channels (default)
# Mode 2 picks by FULL-band RMS, which is not where sibilance lives: a
# stereo file with a loud low tone in channel 1 and the only sibilant
# burst in a quieter channel 2 reduced 0 frames.
analysis_channel_mode = 3

# ============================================================
# Presets
# ============================================================
if preset$ = "Light De-Essing"
    threshold = 0.5
    max_reduction_db = 6
    attack_ms = 5
    release_ms = 60
    presetName$ = "Light"
elsif preset$ = "Medium De-Essing"
    threshold = 0.4
    max_reduction_db = 10
    attack_ms = 5
    release_ms = 50
    presetName$ = "Medium"
elsif preset$ = "Heavy De-Essing"
    threshold = 0.3
    max_reduction_db = 15
    attack_ms = 3
    release_ms = 40
    presetName$ = "Heavy"
elsif preset$ = "Aggressive"
    threshold = 0.25
    max_reduction_db = 18
    attack_ms = 2
    release_ms = 30
    presetName$ = "Aggressive"
elsif preset$ = "Gentle Touch"
    threshold = 0.55
    max_reduction_db = 4
    attack_ms = 8
    release_ms = 80
    presetName$ = "GentleTouch"
elsif preset$ = "Telephony band (2.5-3.7 kHz)"
    # For narrowband material, where 4-8 kHz does not exist: at an
    # 8 kHz sample rate the default band sits at or above Nyquist and
    # the script (correctly) refuses to run.
    hf_low_hz = 2500
    hf_high_hz = 3700
    threshold = 0.4
    max_reduction_db = 10
    attack_ms = 5
    release_ms = 50
    presetName$ = "Telephony"
else
    presetName$ = "Custom"
endif

# ============================================================
# Input and validation
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
originalXmin = Get start time
nyquist = sampleRate / 2
inputPeak = Get absolute extremum: 0, 0, "None"
inputRMS = Get root-mean-square: 0, 0

if hf_high_hz > nyquist * 0.95
    hf_high_hz = nyquist * 0.95
endif
if hf_low_hz >= hf_high_hz - 200
    exitScript: "Hf_low_hz (" + fixed$(hf_low_hz, 0) + ") must be at least 200 Hz below " +
    ... "Hf_high_hz (" + fixed$(hf_high_hz, 0) + " after clamping to Nyquist)."
endif
if threshold <= 0 or threshold >= 1
    exitScript: "Threshold must be between 0 and 1 (got " + fixed$(threshold, 3) +
    ... "). It is a ratio of HF amplitude to full-band amplitude."
endif
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry_wet_mix must be between 0 and 1 (got " + fixed$(dry_wet_mix, 3) + ")."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1."
endif
if entropy_low < 0 or entropy_high > 1 or entropy_low >= entropy_high
    exitScript: "Entropy confidence limits must satisfy 0 <= low < high <= 1."
endif
if entropy_weight < 0 or entropy_weight > 1
    exitScript: "Entropy_weight must be between 0 and 1."
endif
if entropy_window_ms <= 0 or entropy_freq_step_Hz <= 0
    exitScript: "Entropy window and frequency step must be greater than zero."
endif

# To Intensity needs at least one physical window of audio.
physWindow = 6.4 / detector_min_pitch_Hz
if duration < physWindow * 1.5
    exitScript: "Sound is too short: " + fixed$(duration * 1000, 1) + " ms. The detector " +
    ... "window is " + fixed$(physWindow * 1000, 1) + " ms, so at least " +
    ... fixed$(physWindow * 1500, 0) + " ms is needed."
endif

minGainLinear = 10 ^ (-max_reduction_db / 20)
attackTime = attack_ms / 1000
releaseTime = release_ms / 1000
# Praat Intensity dB is referenced to 2e-5 Pa, so amplitude 1 is about
# 94 dB; convert the dBFS gate into those units.
hfGateDb = hf_gate_dBFS + 93.98

if listen_to_removed = 0
    suffix$ = "_deessed"
else
    suffix$ = "_sibilants"
endif

writeInfoLine: "Entropy Smart De-Esser v0.8"
appendInfoLine: "===================="
appendInfoLine: "Input: ", originalName$, " (", fixed$(duration, 2), " s, ", numChannels,
    ... " ch, ", sampleRate, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "HF band: ", fixed$(hf_low_hz, 0), "-", fixed$(hf_high_hz, 0), " Hz"
appendInfoLine: "Detector window: ", fixed$(physWindow * 1000, 1),
    ... " ms - Attack/Release smooth an envelope already smeared by this."
appendInfoLine: "Entropy confidence: HF-band Shannon entropy, ",
    ... fixed$(entropy_low, 2), "-", fixed$(entropy_high, 2),
    ... " soft range, weight ", fixed$(entropy_weight, 2)
appendInfoLine: ""

# ============================================================
# Work copy at time 0
# ============================================================
# v0.4 built the gain tier over 0..duration whatever the Sound's own
# start time was: the same file at 5 s reduced 0 frames against 47 at
# 0 s and came back untouched.
selectObject: sound
workSound = Copy: "deess_work"
Shift times to: "start time", 0

# ============================================================
# [1/4] Detection
# ============================================================
appendInfoLine: "[1/4] Analyzing sibilance..."

# A real channel, never a fold: anti-phase stereo cancelled in v0.4 and
# produced 0 frames reduced with the output unchanged.
if numChannels = 1
    nDetect = 1
    selectObject: workSound
    detCh[1] = Copy: "deess_analysis"
    analysisSource$ = "the single channel"
elsif analysis_channel_mode = 3
    # Every channel measured; the frame loop below takes the strongest
    # HF evidence at each instant.
    nDetect = numChannels
    for ch from 1 to numChannels
        selectObject: workSound
        detCh[ch] = Extract one channel: ch
    endfor
    analysisSource$ = "strongest HF evidence across " + string$(numChannels) + " channels"
else
    pickCh = 1
    if analysis_channel_mode = 2
        bestRms = -1
        for ch from 1 to numChannels
            selectObject: workSound
            probeCh = Extract one channel: ch
            probeRms = Get root-mean-square: 0, 0
            removeObject: probeCh
            if probeRms > bestRms
                bestRms = probeRms
                pickCh = ch
            endif
        endfor
    endif
    nDetect = 1
    selectObject: workSound
    detCh[1] = Extract one channel: pickCh
    analysisSource$ = "channel " + string$(pickCh)
endif
appendInfoLine: "  Detection reads ", analysisSource$

for d from 1 to nDetect
    selectObject: detCh[d]
    fullInt[d] = To Intensity: detector_min_pitch_Hz, 0, "yes"
    selectObject: detCh[d]
    hfTmp = Filter (pass Hann band): hf_low_hz, hf_high_hz, 100
    hfInt[d] = To Intensity: detector_min_pitch_Hz, 0, "yes"
    removeObject: hfTmp
endfor

# ============================================================
# [2/4] Ratio, gate, gain, then attack/release ON THE GAIN
# ============================================================
appendInfoLine: "[2/4] Computing gain curve..."

# v0.4 sampled every 5 ms from t = 0. Praat centres its first frame
# about half a physical window in, so those early samples were
# undefined, became -80 dB and gave ratio 0 - which is why a sibilant
# in the first 20 ms received exactly 0.0 dB of reduction.
selectObject: fullInt[1]
numFrames = Get number of frames
frameDx = Get time step
frameX1 = Get time from frame number: 1

if numFrames < 2
    exitScript: "The detector produced only " + string$(numFrames) + " frame(s)."
endif

appendInfoLine: "  Frames: ", numFrames, " at ", fixed$(frameDx * 1000, 2),
    ... " ms, first at ", fixed$(frameX1 * 1000, 1), " ms"

# Spectral entropy matrices. These are used only as a confidence measure
# after the HF-ratio/absolute-level detector has found a candidate frame.
# The distribution is normalized within Hf_low_hz..Hf_high_hz, so the
# entropy value describes spectral shape in the de-essing band, not the
# amount of HF energy (the Intensity gate already handles amount).
entropyTop = min(nyquist, hf_high_hz + 200)
for d from 1 to nDetect
    selectObject: detCh[d]
    entSpec = To Spectrogram: entropy_window_ms / 1000, entropyTop, frameDx, entropy_freq_step_Hz, "Gaussian"
    entMat[d] = To Matrix
    removeObject: entSpec

    selectObject: entMat[d]
    entNrow[d] = Get number of rows
    entNcol[d] = Get number of columns
    entX1[d] = Get x of column: 1
    if entNcol[d] > 1
        .x2 = Get x of column: 2
        entDx[d] = .x2 - entX1[d]
    else
        entDx[d] = frameDx
    endif
    entY1[d] = Get y of row: 1
    if entNrow[d] > 1
        .y2 = Get y of row: 2
        entDy[d] = .y2 - entY1[d]
    else
        entDy[d] = 1
    endif
    entRowLo[d] = ceiling((hf_low_hz - entY1[d]) / entDy[d]) + 1
    entRowHi[d] = floor((hf_high_hz - entY1[d]) / entDy[d]) + 1
    if entRowLo[d] < 1
        entRowLo[d] = 1
    endif
    if entRowHi[d] > entNrow[d]
        entRowHi[d] = entNrow[d]
    endif
endfor

halfKnee = knee_width / 2
kneeSlope = (1 - minGainLinear) / (1 - threshold)
framesGated = 0

for i from 1 to numFrames
    timeVal[i] = frameX1 + (i - 1) * frameDx

    # Strongest HF evidence at this instant, over the detection
    # channels. v0.5 chose ONE channel for the whole file by full-band
    # RMS, which is not where sibilance lives.
    bestR = 0
    bestHf = -1000
    bestD = 1
    for d from 1 to nDetect
        selectObject: fullInt[d]
        fullDb = Get value in frame: i
        selectObject: hfInt[d]
        hfDb = Get value in frame: i
        if fullDb = undefined
            fullDb = 0
        endif
        if hfDb = undefined
            hfDb = 0
        endif
        fullLin = 10 ^ (fullDb / 20)
        hfLin = 10 ^ (hfDb / 20)
        if fullLin > 0
            rHere = hfLin / fullLin
        else
            rHere = 0
        endif
        if rHere > 1
            rHere = 1
        endif
        # Only a channel whose HF is genuinely loud can set the target
        if hfDb >= hfGateDb and rHere > bestR
            bestR = rHere
            bestHf = hfDb
            bestD = d
        endif
        if hfDb > bestHf and bestR = 0
            bestHf = hfDb
        endif
    endfor

    hfDbVal[i] = bestHf

    # The gate is applied to the DETECTOR TARGET, before smoothing.
    # v0.5 forced gain = 1 after smoothing, which let the gate override
    # attack and release entirely: a decaying HF tone crossing the gate
    # jumped from 0.2512 to 1.0000 inside a single 4 ms frame despite a
    # 100 ms release, and a rising one snapped to 0.252 despite a 100 ms
    # attack.
    if bestHf < hfGateDb
        ratioVal[i] = 0
        framesGated = framesGated + 1
    else
        ratioVal[i] = bestR
    endif

    # --- HF-band spectral entropy confidence ---
    entropyVal[i] = 0
    entropyConfidence[i] = 0
    if ratioVal[i] > 0
        cc = round((timeVal[i] - entX1[bestD]) / entDx[bestD]) + 1
        if cc < 1
            cc = 1
        endif
        if cc > entNcol[bestD]
            cc = entNcol[bestD]
        endif
        rlo = entRowLo[bestD]
        rhi = entRowHi[bestD]
        nb = rhi - rlo + 1
        sumP = 0
        if nb > 1
            for rr from rlo to rhi
                pwr = object[entMat[bestD], rr, cc]
                if pwr > 0
                    sumP += pwr
                endif
            endfor
            if sumP > 1e-30
                hent = 0
                for rr from rlo to rhi
                    pwr = object[entMat[bestD], rr, cc]
                    if pwr > 0
                        pp = pwr / sumP
                        hent -= pp * ln(pp)
                    endif
                endfor
                entropyVal[i] = hent / ln(nb)
            endif
        endif
        ec = (entropyVal[i] - entropy_low) / (entropy_high - entropy_low)
        if ec < 0
            ec = 0
        elsif ec > 1
            ec = 1
        endif
        # Smoothstep: continuous value and slope at both confidence edges.
        entropyConfidence[i] = ec * ec * (3 - 2 * ec)
    endif

    # --- Target gain: ratio threshold/knee, then entropy confidence ---
    # A real C1 knee. v0.5 clamped the reduction to 0 through the whole
    # lower half of the knee, so the slope still jumped at the
    # threshold - smoothed onset, not a symmetric knee.
    r = ratioVal[i]
    if knee_width > 0 and r > threshold - halfKnee and r < threshold + halfKnee
        over = r - threshold + halfKnee
        red = (over * over) / (2 * knee_width) * kneeSlope
    elsif r <= threshold - halfKnee
        red = 0
    else
        red = (r - threshold) * kneeSlope
    endif

    # Entropy is a confidence MODIFIER, not a second hard gate. At low
    # entropy the ratio detector retains (1 - entropy_weight) of its
    # requested reduction; at high entropy it retains 100%.
    entropyScale = (1 - entropy_weight) + entropy_weight * entropyConfidence[i]
    red = red * entropyScale
    rawGain[i] = 1 - red
    if rawGain[i] < minGainLinear
        rawGain[i] = minGainLinear
    endif
    if rawGain[i] > 1
        rawGain[i] = 1
    endif
endfor

# --- Attack / release applied to the GAIN, after the gate ---
# Gain falling = more reduction = attack; gain rising = release.
attackCoef = 1 - exp(-2.2 / (attackTime / frameDx + 1))
releaseCoef = 1 - exp(-2.2 / (releaseTime / frameDx + 1))

gainVal[1] = rawGain[1]
for i from 2 to numFrames
    if rawGain[i] < gainVal[i-1]
        gainVal[i] = gainVal[i-1] + attackCoef * (rawGain[i] - gainVal[i-1])
    else
        gainVal[i] = gainVal[i-1] + releaseCoef * (rawGain[i] - gainVal[i-1])
    endif
endfor

maxRatio = 0
minRatio = 1
maxEntropy = 0
minEntropy = 1
sumEntropy = 0
entropyFrames = 0
framesReduced = 0
for i from 1 to numFrames
    if ratioVal[i] > maxRatio
        maxRatio = ratioVal[i]
    endif
    if ratioVal[i] < minRatio
        minRatio = ratioVal[i]
    endif
    if ratioVal[i] > 0
        entropyFrames += 1
        sumEntropy += entropyVal[i]
        if entropyVal[i] > maxEntropy
            maxEntropy = entropyVal[i]
        endif
        if entropyVal[i] < minEntropy
            minEntropy = entropyVal[i]
        endif
    endif
    if gainVal[i] < 0.999
        framesReduced = framesReduced + 1
    endif
endfor
if entropyFrames > 0
    meanEntropy = sumEntropy / entropyFrames
else
    minEntropy = 0
    meanEntropy = 0
endif

# --- Gain tier on the real frame times, held out to the edges ---
Create IntensityTier: "deess_gain", 0, duration
gainTier = selected("IntensityTier")
if timeVal[1] > 0
    Add point: 0, gainVal[1]
endif
for i from 1 to numFrames
    Add point: timeVal[i], gainVal[i]
endfor
if timeVal[numFrames] < duration
    Add point: duration, gainVal[numFrames]
endif
tier$ = string$(gainTier)

# ============================================================
# [3/4] Split-band processing, every channel
# ============================================================
appendInfoLine: "[3/4] Applying split-band de-essing..."

for ch from 1 to numChannels
    if numChannels = 1
        selectObject: workSound
        chDry[ch] = Copy: "deess_dry"
    else
        selectObject: workSound
        chDry[ch] = Extract one channel: ch
    endif

    selectObject: chDry[ch]
    hfBand = Filter (pass Hann band): hf_low_hz, hf_high_hz, 100
    hf$ = string$(hfBand)

    if listen_to_removed = 0
        # output = signal - HF x (1 - gain), i.e. residual + HF x gain.
        # Only the high band is touched; at gain 1 this is the input.
        selectObject: chDry[ch]
        chWet[ch] = Copy: "deess_wet"
        Formula: "self - object[" + hf$ + ", 1, col] * (1 - object(" + tier$ + ", x))"
    else
        # Only what was taken out of the high band.
        selectObject: hfBand
        chWet[ch] = Copy: "deess_removed"
        Formula: "self * (1 - object(" + tier$ + ", x))"
    endif
    removeObject: hfBand

    if dry_wet_mix < 1 and listen_to_removed = 0
        selectObject: chWet[ch]
        Formula: "self * " + string$(dry_wet_mix) + " + object[" + string$(chDry[ch]) +
            ... ", 1, col] * " + string$(1 - dry_wet_mix)
    endif
    appendInfo: "."
endfor
appendInfoLine: ""

if numChannels = 1
    selectObject: chWet[1]
    finalOutput = Copy: "deess_out"
    removeObject: chWet[1]
else
    selectObject: chWet[1]
    outDurCh = Get total duration
    Create Sound from formula: "deess_out", numChannels, 0, outDurCh, sampleRate, "0"
    finalOutput = selected("Sound")
    for ch from 1 to numChannels
        selectObject: finalOutput
        Formula (part): 0, outDurCh, ch, ch,
            ... "object[" + string$(chWet[ch]) + ", 1, col]"
    endfor
    for ch from 1 to numChannels
        removeObject: chWet[ch]
    endfor
endif

# ============================================================
# [4/4] Output level
# ============================================================
appendInfoLine: "[4/4] Output level..."

selectObject: finalOutput
pre_level_peak = Get absolute extremum: 0, 0, "None"
pre_level_rms = Get root-mean-square: 0, 0
level_gain = 1
level_action$ = "natural level"

if output_level_mode = 2
    if pre_level_rms > 0 and inputRMS > 0
        level_gain = inputRMS / pre_level_rms
        selectObject: finalOutput
        Formula: "self * " + string$(level_gain)
        level_action$ = "matched to input RMS"
    endif
elsif output_level_mode = 3
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 4
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

selectObject: finalOutput
finalPeak = Get absolute extremum: 0, 0, "None"
finalDur = Get total duration
reducedPct = framesReduced / numFrames * 100
gatedPct = framesGated / numFrames * 100

# ============================================================
# VISUALIZATION  (8 x 8 canvas - suite standard, drawn at t = 0)
# ============================================================
if draw_visualization

    # Which channel the plots show. Folding to mono would cancel
    # anti-phase stereo on screen even though the audio is fine.
    vizCh = 1
    if numChannels > 1
        bestVizRms = -1
        for ch from 1 to numChannels
            selectObject: workSound
            vp = Extract one channel: ch
            vpr = Get root-mean-square: 0, 0
            removeObject: vp
            if vpr > bestVizRms
                bestVizRms = vpr
                vizCh = ch
            endif
        endfor
    endif

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line

    if show_spectrogram
        selectObject: finalOutput
        if numChannels > 1
            specSource = Extract one channel: vizCh
        else
            specSource = Copy: "deess_spec_src"
        endif
        selectObject: specSource
        specTop = min(8000, nyquist)
        resultSpec = To Spectrogram: 0.005, specTop, 0.002, 20, "Gaussian"
    endif

    # ---- TITLE ----
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Entropy Smart De-Esser v0.8##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    # A real channel, not a fold: anti-phase stereo would draw as
    # silence even though the output is correct.
    selectObject: workSound
    if numChannels > 1
        origMono = Extract one channel: vizCh
    else
        origMono = Copy: "deess_orig_viz"
    endif

    selectObject: origMono
    src_peak = Get absolute extremum: 0, 0, "None"
    if src_peak < 0.001
        src_peak = 0.001
    endif
    src_amp = src_peak * 1.15

    Axes: 0, duration, -src_amp, src_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -src_amp, src_amp

    selectObject: origMono
    Colour: "{0.62, 0.62, 0.62}"
    Line width: 1
    Draw: 0, duration, -src_amp, src_amp, "no", "Curve"

    Axes: 0, duration, -src_amp, src_amp
    Colour: "{0.88, 0.28, 0.28}"
    Line width: 2
    redMax = src_amp * 0.9
    for i from 1 to numFrames - 1
        g1_norm = (1 - gainVal[i]) * redMax
        g2_norm = (1 - gainVal[i + 1]) * redMax
        Draw line: timeVal[i], g1_norm, timeVal[i + 1], g2_norm
    endfor
    Line width: 1

    removeObject: origMono

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp / Red."
    Text bottom: "yes", "Time (s)"

    # ---- PANEL B: HF ratio + threshold + gate ----
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, duration, 0, 1

    Colour: "{0.88, 0.88, 0.92}"
    Dotted line
    Draw line: 0, 0.25, duration, 0.25
    Draw line: 0, 0.50, duration, 0.50
    Draw line: 0, 0.75, duration, 0.75
    Solid line

    # Knee band around the threshold
    if knee_width > 0
        Paint rectangle: "{1.00, 0.92, 0.92}", 0, duration,
            ... max(0, threshold - halfKnee), min(1, threshold + halfKnee)
    endif

    Colour: "{0.85, 0.25, 0.25}"
    Line width: 1.5
    Dotted line
    Draw line: 0, threshold, duration, threshold
    Solid line

    # Frames the absolute HF gate held at unity
    Colour: "{0.55, 0.75, 0.55}"
    Line width: 1
    for i from 1 to numFrames
        if hfDbVal[i] < hfGateDb
            Draw line: timeVal[i], 0, timeVal[i], 0.03
        endif
    endfor

    Colour: "{0.20, 0.50, 0.80}"
    Line width: 1.8
    for i from 1 to numFrames - 1
        Draw line: timeVal[i], ratioVal[i], timeVal[i + 1], ratioVal[i + 1]
    endfor

    # Entropy in the selected HF band. Zero on frames held out by the
    # absolute HF gate, because entropy is not consulted there.
    Colour: "{0.90, 0.55, 0.15}"
    Line width: 1.4
    for i from 1 to numFrames - 1
        Draw line: timeVal[i], entropyVal[i], timeVal[i + 1], entropyVal[i + 1]
    endfor
    Line width: 1

    Font size: 6
    Colour: "{0.85, 0.25, 0.25}"
    Text: duration * 0.02, "left", threshold + 0.04, "half", "thresh " + fixed$(threshold, 2)

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Ratio / entropy"
    Text bottom: "yes", "Time (s)"

    # ---- ALIGNED PANEL TITLES ----
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Waveform (grey) + Gain reduction (red)"
    Text: 6.10, "centre", 7.30, "half",
        ... "HF/full ratio (blue), HF entropy (orange), knee (pink), gate (green)"

    # ---- PANEL C: zoom overlay ----
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    zoomDur = min(2.0, min(duration, finalDur))

    selectObject: workSound
    if numChannels > 1
        zoomOrig = Extract one channel: vizCh
    else
        zoomOrig = Copy: "deess_zoom_orig"
    endif
    selectObject: finalOutput
    if numChannels > 1
        zoomOut = Extract one channel: vizCh
    else
        zoomOut = Copy: "deess_zoom_out"
    endif

    selectObject: zoomOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: zoomOut
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = max(z_peak1, z_peak2)
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15

    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0

    selectObject: zoomOrig
    Colour: "{0.65, 0.65, 0.65}"
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    selectObject: zoomOut
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"

    removeObject: zoomOrig, zoomOut

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur, 1) + " s, channel " + string$(vizCh) + "  (grey = original, blue = output)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ---- PANEL D: result spectrogram ----
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    if show_spectrogram
        selectObject: resultSpec
        Paint: 0, 0, 0, specTop, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Result spectrogram (0-" + fixed$(specTop, 0) + " Hz)"
        Text left: "yes", "Freq (Hz)"
        Text bottom: "yes", "Time (s)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.5, "centre", 0.5, "half", "Result spectrogram disabled (Show_spectrogram = OFF)"
        Colour: "Black"
        Draw inner box
    endif

    # ---- PANEL E: summary ----
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if listen_to_removed = 0
        modeStr$ = "de-essed (split band)"
    else
        modeStr$ = "removed HF only"
    endif
    if show_spectrogram
        specStr$ = "shown"
    else
        specStr$ = "off"
    endif

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$ + suffix$
        ... + "  |  HF " + fixed$(hf_low_hz, 0) + "-" + fixed$(hf_high_hz, 0) + " Hz"
        ... + "  |  Threshold: " + fixed$(threshold, 2) + " (knee " + fixed$(knee_width, 2) + ")"
        ... + "  |  Entropy: " + fixed$(entropy_low, 2) + "-" + fixed$(entropy_high, 2)
        ... + "  |  Max red: -" + fixed$(max_reduction_db, 1) + " dB"
        ... + "  |  Atk/Rel: " + fixed$(attack_ms, 0) + "/" + fixed$(release_ms, 0) + " ms"

    Text: 0.02, "left", 0.28, "half",
        ... "Mode: " + modeStr$
        ... + "  |  Reduced " + string$(framesReduced) + "/" + string$(numFrames)
        ... + " (" + fixed$(reducedPct, 1) + "%)"
        ... + "  |  HF-gated " + fixed$(gatedPct, 1) + "%"
        ... + "  |  Mix: " + fixed$(dry_wet_mix, 2)
        ... + "  |  Peak " + fixed$(inputPeak, 3) + " -> " + fixed$(finalPeak, 3)
        ... + "  |  Level: " + level_action$
        ... + "  |  Spec: " + specStr$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1

    if show_spectrogram
        removeObject: resultSpec, specSource
    endif
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# Restore the source time domain and finish
# ============================================================
selectObject: finalOutput
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + suffix$
finalName$ = selected$("Sound")

for ch from 1 to numChannels
    removeObject: chDry[ch]
endfor
for d from 1 to nDetect
    removeObject: fullInt[d], hfInt[d], entMat[d], detCh[d]
endfor
removeObject: gainTier, workSound

appendInfoLine: ""
appendInfoLine: "===================="
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", finalName$
appendInfoLine: "Channels: ", numChannels, " (all processed)"
appendInfoLine: ""
appendInfoLine: "HF ratio range: ", fixed$(minRatio, 2), " - ", fixed$(maxRatio, 2)
appendInfoLine: "HF-band entropy (gated-in frames): ", fixed$(minEntropy, 3), " - ",
    ... fixed$(maxEntropy, 3), " | mean ", fixed$(meanEntropy, 3)
appendInfoLine: "Frames reduced: ", framesReduced, " / ", numFrames, " (",
    ... fixed$(reducedPct, 1), "%)"
appendInfoLine: "Frames held at unity by the HF gate: ", framesGated, " (",
    ... fixed$(gatedPct, 1), "%)"
appendInfoLine: "Peak: ", fixed$(inputPeak, 4), " -> ", fixed$(finalPeak, 4),
    ... " (", level_action$, ")"
if output_level_mode <> 4 and finalPeak > 1
    appendInfoLine: "WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

selectObject: finalOutput
if play_after_processing
    if finalPeak > 1
        appendInfoLine: "Playing a scaled copy (peak exceeds 1.0)..."
        playCopy = Copy: "play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        Play
    endif
endif

selectObject: finalOutput