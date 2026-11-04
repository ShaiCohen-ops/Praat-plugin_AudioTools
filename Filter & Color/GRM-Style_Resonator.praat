# ============================================================
# Praat AudioTools - GRM-Style_Resonator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   GRM-STYLE (not the GRM algorithm): an independently developed bank
#   of up to 64 parallel ringing resonators, inspired by the classic
#   INA-GRM Reson. "GRM-style" = aesthetic lineage, not a
#   reimplementation of proprietary software.
#
#   Each resonator is a complex one-pole resonator
#       z[n] = r e^(j w[n]) z[n-1] + x[n],      y[n] = g Re(z[n])
#   whose real output is exactly the two-pole/one-zero system
#       H(z) = (1 - r cos(w) z^-1) / (1 - 2 r cos(w) z^-1 + r^2 z^-2)
#   i.e. poles at r e^(+-jw). Its impulse response is g r^n cos(w n):
#   a decaying sinusoid at exactly the requested frequency, which
#   keeps ringing after the excitation ends.
#
#   It is computed by heterodyning: v[n] = r v[n-1] + x[n] e^(-j th[n])
#   with th[n] the running phase, then y = g Re(v e^(j th)). Each
#   recursion holds ONE real state, so Praat can run it as a single
#   compiled in-place Formula pass instead of an interpreted sample loop.
#   The envelope |v| decays by exactly r per sample whatever w[n] does,
#   so frequency modulation can never destabilise the bank or change
#   its decay, and the state is continuous through every retuning.
#
#   Relationships (fs = sample rate, f = frequency, T60 in seconds):
#     r   = 10^(-3 / (T60 fs))           60 dB amplitude decay in T60
#     B   = ln(1000) / (pi T60)          -3 dB bandwidth = 2.199 / T60 Hz
#     Q   = f / B = f T60 / 2.199
#   Decay is set in seconds and is independent of frequency. For a
#   single second-order resonator bandwidth and decay are the same
#   physical quantity: Q is reported, not set separately.
#
# Changelog v2.0 (2026):
#   - NEW RESONANT ARCHITECTURE. The Hann band-pass + integer-delay comb
#     bank is gone. Its decay was a tap/feedback coefficient, so a short
#     impulse produced at most a short comb buzz and no sustained tone.
#     v2.0 uses the parallel second-order resonators described above.
#   - Decay in seconds (Resonance_decay_s), frequency-independent, with
#     a per-bank Decay_tilt and an optional per-resonator decay list.
#   - Exact tuning: continuous pole angle, no sample rounding. v1.5
#     tuned 3770 Hz to 3675 Hz at 44.1 kHz (-44 cents); v2.0 rings at
#     the requested frequency to within measurement precision.
#   - Up to 64 resonators; layouts Manual, Harmonic, Inharmonic ratios,
#     Equal logarithmic; static dispersion; spread and shift in the
#     advanced block.
#   - Excitation scaling chooses what is held constant per resonator
#     (noise power / steady-state peak / impulse amplitude); the bank is
#     divided by sqrt(N), which keeps relative balance between resonators.
#   - Transient_focus: 0 = whole input excites, 1 = attacks only.
#   - Automatic resonant tail from the longest T60; fixed tail option;
#     a 20 ms fade only when a tail has to be cut short.
#   - Frequency modulation of the bank itself: Sine LFO, Smooth random
#     drift, Sample-and-hold - phase- and state-continuous.
#   - New presets built on distinct resonant behaviour.
#   - Visualization redrawn for the new bank: output with tail, output
#     spectrogram with the actual coefficient trajectories overlaid,
#     measured spectrum against intended frequencies, configured against
#     measured decay, configured gain against measured output level.
#   - Removed: ringIterations, ringDecay, bandwidthHz, Resonator_mode,
#     delay tuning. Dry/Wet, Output_level_mode, panning, xmin
#     preservation, the >2-channel refusal and the 8-inch page convention
#     are kept from v1.5.1.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form GRM-Style Resonator v2.0
    optionmenu Preset: 1
        option Custom
        option Harmonic Organ
        option Metallic Resonance
        option Resonant Cloud
        option Moving Resonance
        option Percussive Resonance
        option Deep Resonance
    integer Number_of_resonators 8
    optionmenu Frequency_layout: 2
        option Manual list (Hz)
        option Harmonic series
        option Inharmonic ratios
        option Equal logarithmic
    real Base_frequency_Hz 110
    real Top_frequency_Hz 1760
    sentence Frequencies_or_ratios 1 1.41 1.89 2.37 2.98 3.56
    real Dispersion_cents 0
    real Resonance_decay_s 3.0
    real Decay_tilt 0.7
    optionmenu Excitation_scaling: 1
        option Balanced (constant noise power)
        option Unity peak (filter-like)
        option Unity impulse (strike)
    real Transient_focus 0
    real Resonance_gain_dB 0
    optionmenu Stereo_panning: 2
        option All Center (dual mono)
        option Stereo Spread (Alternate)
        option Wide Spread (Hard L/R)
        option Left Heavy
        option Right Heavy
        option V Shape (Outside In)
        option Random
    optionmenu Modulation: 1
        option None
        option Sine LFO
        option Smooth random drift
        option Sample-and-hold
    real Modulation_depth_cents 50
    real Modulation_rate_Hz 0.2
    real Dry_wet 1.0
    optionmenu Tail_mode: 1
        option Automatic (longest T60)
        option Fixed (tail_s below)
        option None (truncate)
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
# Praat forms do not scroll, so rig-level settings live here. The names
# are the ones the body uses, so moving a line into the form needs no
# other edit.

# Gain profile across the bank, by frequency: 1 Flat, 2 Dampen highs,
# 3 Boost highs.
gain_Profile = 2

# Per-resonator decay times in seconds, lowest-listed resonator first.
# Empty = use Resonance_decay_s with Decay_tilt. Fewer values than
# resonators: the last value repeats.
decay_list$ = ""

# Static spread and shift of the whole bank. Spread scales every
# interval above the lowest resonator (1 = unchanged, 2 = intervals
# doubled); shift transposes the bank.
freq_spread = 1
freq_shift_cents = 0

# Fixed tail used by Tail_mode 2, and the cap for the automatic tail.
tail_s = 5
max_auto_tail_s = 30

# 0 = unseeded; any other value makes dispersion, random drift,
# sample-and-hold and Random panning reproducible.
random_seed = 0

# Ceiling used by Output_level_mode 2 and 3.
finalPeak = 0.99

# Transient detector time constants (Transient_focus > 0).
transient_attack_s = 0.05
transient_release_s = 0.15

# --- 1. PRESETS ---
if preset = 2
    number_of_resonators = 12
    frequency_layout = 2
    base_frequency_Hz = 110
    dispersion_cents = 0
    resonance_decay_s = 4.0
    decay_tilt = 0.5
    excitation_scaling = 1
    transient_focus = 0
    resonance_gain_dB = 0
    gain_Profile = 2
    stereo_panning = 2
    modulation = 1
    presetName$ = "HarmonicOrgan"
elsif preset = 3
    number_of_resonators = 6
    frequency_layout = 3
    base_frequency_Hz = 220
    frequencies_or_ratios$ = "1 2.756 5.404 8.933 13.344 18.64"
    dispersion_cents = 0
    resonance_decay_s = 6.0
    decay_tilt = 0.4
    excitation_scaling = 3
    transient_focus = 0.5
    resonance_gain_dB = -6
    gain_Profile = 1
    stereo_panning = 3
    modulation = 1
    presetName$ = "MetallicResonance"
elsif preset = 4
    number_of_resonators = 32
    frequency_layout = 4
    base_frequency_Hz = 300
    top_frequency_Hz = 2400
    dispersion_cents = 40
    resonance_decay_s = 2.5
    decay_tilt = 1
    excitation_scaling = 1
    transient_focus = 0
    resonance_gain_dB = 0
    gain_Profile = 2
    stereo_panning = 7
    modulation = 3
    modulation_depth_cents = 8
    modulation_rate_Hz = 0.3
    presetName$ = "ResonantCloud"
elsif preset = 5
    number_of_resonators = 10
    frequency_layout = 3
    base_frequency_Hz = 180
    frequencies_or_ratios$ = "1 1.41 1.89 2.37 2.98 3.56 4.21 4.87 5.62 6.30"
    dispersion_cents = 0
    resonance_decay_s = 3.0
    decay_tilt = 0.8
    excitation_scaling = 1
    transient_focus = 0
    resonance_gain_dB = 0
    gain_Profile = 2
    stereo_panning = 6
    modulation = 3
    modulation_depth_cents = 300
    modulation_rate_Hz = 0.15
    presetName$ = "MovingResonance"
elsif preset = 6
    number_of_resonators = 8
    frequency_layout = 3
    base_frequency_Hz = 330
    frequencies_or_ratios$ = "1 1.594 2.136 2.296 2.653 2.918 3.156 3.501"
    dispersion_cents = 0
    resonance_decay_s = 1.2
    decay_tilt = 0.6
    excitation_scaling = 3
    transient_focus = 1
    resonance_gain_dB = -6
    gain_Profile = 1
    stereo_panning = 3
    modulation = 1
    presetName$ = "PercussiveResonance"
elsif preset = 7
    number_of_resonators = 8
    frequency_layout = 4
    base_frequency_Hz = 40
    top_frequency_Hz = 320
    dispersion_cents = 0
    resonance_decay_s = 12
    decay_tilt = 0.5
    excitation_scaling = 1
    transient_focus = 0.3
    resonance_gain_dB = 0
    gain_Profile = 1
    stereo_panning = 2
    modulation = 2
    modulation_depth_cents = 15
    modulation_rate_Hz = 0.07
    presetName$ = "DeepResonance"
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
srcSamples = Get number of samples
nyquist = samplingRate / 2
numChannels = Get number of channels
inputPeak = Get absolute extremum: 0, 0, "None"

if numChannels > 2
    exitScript: "This Sound has " + string$(numChannels) + " channels. The resonator bank " +
    ... "pans its resonators across a stereo field, so the wet signal is two-channel and " +
    ... "there is no defined placement for further channels. Use a mono or stereo Sound, " +
    ... "or process the channel pairs separately."
endif

# --- Validation ---
if number_of_resonators < 1 or number_of_resonators > 64
    exitScript: "Number_of_resonators must be between 1 and 64."
endif
if resonance_decay_s < 0.01 or resonance_decay_s > 60
    exitScript: "Resonance_decay_s must be between 0.01 and 60 s."
endif
if decay_tilt <= 0
    exitScript: "Decay_tilt must be greater than 0 (1 = every resonator has the same decay)."
endif
if base_frequency_Hz <= 0
    exitScript: "Base_frequency_Hz must be greater than 0."
endif
if frequency_layout = 4 and top_frequency_Hz <= base_frequency_Hz and number_of_resonators > 1
    exitScript: "Equal logarithmic spacing needs Top_frequency_Hz above Base_frequency_Hz."
endif
if transient_focus < 0 or transient_focus > 1
    exitScript: "Transient_focus must be between 0 and 1."
endif
if dry_wet < 0 or dry_wet > 1
    exitScript: "Dry_wet must be between 0 and 1 (got " + fixed$(dry_wet, 3) + ")."
endif
if modulation > 1
    if modulation_rate_Hz <= 0 or modulation_rate_Hz > 20
        exitScript: "Modulation_rate_Hz must be above 0 and at most 20 Hz."
    endif
    if modulation_depth_cents < 0 or modulation_depth_cents > 2400
        exitScript: "Modulation_depth_cents must be between 0 and 2400."
    endif
endif
if dispersion_cents < 0
    dispersion_cents = 0
endif
if finalPeak <= 0 or finalPeak > 1
    exitScript: "finalPeak must be greater than 0 and at most 1."
endif
if freq_spread <= 0
    exitScript: "freq_spread must be greater than 0."
endif
if tail_s < 0
    tail_s = 0
endif

if random_seed <> 0
    random_initializeWithSeedUnsafelyButPredictably: random_seed
endif

# --- 3. FREQUENCIES ---
# Tokenise the list field (Hz for Manual, ratios for Inharmonic).
# Three-argument mid$ only: two-argument mid$ returns ONE character.
nTok = 0
str$ = frequencies_or_ratios$ + " "
while length(str$) > 0
    sp = index(str$, " ")
    tok$ = left$(str$, sp - 1)
    str$ = mid$(str$, sp + 1, length(str$) - sp)
    if tok$ <> ""
        val = number(tok$)
        if val <> undefined and val > 0
            nTok = nTok + 1
            tokVal[nTok] = val
        endif
    endif
endwhile

if frequency_layout = 1 or frequency_layout = 3
    nReq = min(nTok, number_of_resonators)
    if nReq < 1
        exitScript: "No usable values in Frequencies_or_ratios."
    endif
else
    nReq = number_of_resonators
endif

for k from 1 to nReq
    if frequency_layout = 1
        fRaw[k] = tokVal[k]
    elsif frequency_layout = 2
        fRaw[k] = base_frequency_Hz * k
    elsif frequency_layout = 3
        fRaw[k] = base_frequency_Hz * tokVal[k]
    else
        if nReq > 1
            fRaw[k] = base_frequency_Hz * (top_frequency_Hz / base_frequency_Hz) ^ ((k - 1) / (nReq - 1))
        else
            fRaw[k] = base_frequency_Hz
        endif
    endif
endfor
if frequency_layout = 1
    layoutStr$ = "Manual list"
elsif frequency_layout = 2
    layoutStr$ = "Harmonic, " + fixed$(base_frequency_Hz, 1) + " Hz"
elsif frequency_layout = 3
    layoutStr$ = "Inharmonic, " + fixed$(base_frequency_Hz, 1) + " Hz"
else
    layoutStr$ = "Equal log " + fixed$(base_frequency_Hz, 0) + "-" + fixed$(top_frequency_Hz, 0) + " Hz"
endif

# Spread (around the lowest), shift, dispersion
fLowRaw = fRaw[1]
for k from 1 to nReq
    if fRaw[k] < fLowRaw
        fLowRaw = fRaw[k]
    endif
endfor
for k from 1 to nReq
    ff = fLowRaw * (fRaw[k] / fLowRaw) ^ freq_spread
    ff = ff * 2 ^ (freq_shift_cents / 1200)
    if dispersion_cents > 0
        dispC[k] = randomUniform(-dispersion_cents, dispersion_cents)
    else
        dispC[k] = 0
    endif
    fRaw[k] = ff * 2 ^ (dispC[k] / 1200)
endfor

# Keep only resonators inside 20 Hz .. Nyquist - 20 Hz
nRes = 0
nDropped = 0
for k from 1 to nReq
    if fRaw[k] > 20 and fRaw[k] < nyquist - 20
        nRes = nRes + 1
        freq[nRes] = fRaw[k]
    else
        nDropped = nDropped + 1
    endif
endfor
if nRes < 1
    exitScript: "Every resonator frequency falls outside 20 Hz to " + fixed$(nyquist - 20, 0) +
    ... " Hz at this sample rate."
endif

minF = freq[1]
maxF = freq[1]
for k from 1 to nRes
    minF = min(minF, freq[k])
    maxF = max(maxF, freq[k])
endfor
logMin = ln(minF)
logMax = ln(maxF)

# --- 4. PER-RESONATOR DECAY, GAIN, COEFFICIENTS ---
# Optional decay list
nDec = 0
if decay_list$ <> ""
    str$ = decay_list$ + " "
    while length(str$) > 0
        sp = index(str$, " ")
        tok$ = left$(str$, sp - 1)
        str$ = mid$(str$, sp + 1, length(str$) - sp)
        if tok$ <> ""
            val = number(tok$)
            if val <> undefined and val > 0
                nDec = nDec + 1
                decVal[nDec] = val
            endif
        endif
    endwhile
endif

baseGainLin = 10 ^ (resonance_gain_dB / 20)
bankNorm = 1 / sqrt(nRes)
maxT60 = 0
for k from 1 to nRes
    if logMax > logMin
        fpos[k] = (ln(freq[k]) - logMin) / (logMax - logMin)
    else
        fpos[k] = 0
    endif

    if nDec > 0
        t60[k] = decVal[min(k, nDec)]
    else
        t60[k] = resonance_decay_s * decay_tilt ^ fpos[k]
    endif
    t60[k] = max(0.01, min(60, t60[k]))
    maxT60 = max(maxT60, t60[k])

    # Pole radius: amplitude falls 60 dB (factor 1000) in t60 seconds
    rad[k] = 10 ^ (-3 / (t60[k] * samplingRate))
    bwHz[k] = ln(1000) / (pi * t60[k])
    qFac[k] = freq[k] / bwHz[k]

    # Excitation scaling of one resonator (real output y = g Re(z))
    if excitation_scaling = 1
        # unit white-noise power gain: E|z|^2 = 1/(1-r^2), Re carries half
        gNorm[k] = sqrt(2 * (1 - rad[k] ^ 2))
    elsif excitation_scaling = 2
        # unit steady-state gain at the resonance: |H| = 1/(2(1-r)) there
        gNorm[k] = 2 * (1 - rad[k])
    else
        # impulse rings at amplitude 1
        gNorm[k] = 1
    endif

    if gain_Profile = 1
        prof[k] = 1
        gainProfileStr$ = "Flat"
    elsif gain_Profile = 2
        prof[k] = 1 - 0.8 * fpos[k]
        gainProfileStr$ = "Dampen highs"
    else
        prof[k] = 0.2 + 0.8 * fpos[k]
        gainProfileStr$ = "Boost highs"
    endif

    gTot[k] = gNorm[k] * prof[k] * baseGainLin * bankNorm
endfor

# Magnitude-response peak of each resonator. The RINGING frequency is the
# pole angle and is exact; the steady-state |H| peak sits slightly off it
# for very broad resonances (the image pole). Reported, not hidden.
for k from 1 to nRes
    w0 = 2 * pi * freq[k] / samplingRate
    rr = rad[k]
    rc = rr * cos(w0)
    bRad = -ln(rr)
    lo = max(0.000001, w0 - 8 * bRad)
    hi = min(pi - 0.000001, w0 + 8 * bRad)
    # coarse grid, then a fine grid around the best cell, then a
    # parabolic fit in log magnitude
    for ipass from 1 to 2
        bestW = w0
        bestM = -1
        for it from 0 to 400
            om = lo + (hi - lo) * it / 400
            @resMag2: rr, rc, om
            if resMag2.m > bestM
                bestM = resMag2.m
                bestW = om
            endif
        endfor
        stepW = (hi - lo) / 400
        lo = max(0.000001, bestW - 2 * stepW)
        hi = min(pi - 0.000001, bestW + 2 * stepW)
    endfor
    stepW = (hi - lo) / 400
    @resMag2: rr, rc, bestW - stepW
    ma = ln(resMag2.m)
    @resMag2: rr, rc, bestW
    mb = ln(resMag2.m)
    @resMag2: rr, rc, bestW + stepW
    mc = ln(resMag2.m)
    den = ma - 2 * mb + mc
    if den < 0
        bestW = bestW + stepW * 0.5 * (ma - mc) / den
    endif
    peakHz[k] = bestW * samplingRate / (2 * pi)
    peakCents[k] = 1200 * log2(peakHz[k] / freq[k])
endfor

# --- 5. PANS ---
for k from 1 to nRes
    if stereo_panning = 1
        pL[k] = 1.0
        pR[k] = 1.0
        if numChannels = 1
            panningStr$ = "Dual mono"
        else
            panningStr$ = "Stereo preserved"
        endif
    elsif stereo_panning = 2
        if (k mod 2) = 1
            pL[k] = 1.0
            pR[k] = 0.3
        else
            pL[k] = 0.3
            pR[k] = 1.0
        endif
        panningStr$ = "Stereo Alternate"
    elsif stereo_panning = 3
        if (k mod 2) = 1
            pL[k] = 1.0
            pR[k] = 0.0
        else
            pL[k] = 0.0
            pR[k] = 1.0
        endif
        panningStr$ = "Hard L/R"
    elsif stereo_panning = 4
        pL[k] = 1.0
        pR[k] = 0.3
        panningStr$ = "Left Heavy"
    elsif stereo_panning = 5
        pL[k] = 0.3
        pR[k] = 1.0
        panningStr$ = "Right Heavy"
    elsif stereo_panning = 6
        midK = (nRes + 1) / 2
        if k <= midK
            if midK > 1
                prog = (k - 1) / (midK - 1)
            else
                prog = 0
            endif
            pL[k] = 1.0 - prog * 0.7
            pR[k] = 0.3 + prog * 0.7
        else
            remK = nRes - midK
            if remK > 0
                prog = (k - midK) / remK
            else
                prog = 0
            endif
            pL[k] = 0.3 + prog * 0.7
            pR[k] = 1.0 - prog * 0.7
        endif
        panningStr$ = "V-Shape"
    else
        rp = randomUniform(0, 1)
        pL[k] = 1.0 - rp
        pR[k] = rp
        if random_seed <> 0
            panningStr$ = "Random (seed " + string$(random_seed) + ")"
        else
            panningStr$ = "Random (unseeded)"
        endif
    endif
endfor

# --- 6. TAIL ---
if tail_mode = 1
    tailLen = min(maxT60, max_auto_tail_s)
    tailStr$ = "Automatic"
elsif tail_mode = 2
    tailLen = tail_s
    tailStr$ = "Fixed"
else
    tailLen = 0
    tailStr$ = "None"
endif
tailSamples = round(tailLen * samplingRate)
tailLen = tailSamples / samplingRate
# Cut short = the longest resonance is still above -60 dB at the end
tailTruncated = tailLen < maxT60 - 0.0005

if modulation = 1
    modStr$ = "None"
elsif modulation = 2
    modStr$ = "Sine LFO"
elsif modulation = 3
    modStr$ = "Smooth drift"
else
    modStr$ = "Sample-and-hold"
endif
if excitation_scaling = 1
    scaleStr$ = "Balanced"
elsif excitation_scaling = 2
    scaleStr$ = "Unity peak"
else
    scaleStr$ = "Unity impulse"
endif

clearinfo
writeInfoLine: "=== GRM-Style Resonator v2.0 ==="
appendInfoLine: "Input: ", originalName$, " (", fixed$(inputDuration, 3), " s, ",
    ... numChannels, " ch, ", samplingRate, " Hz)"
appendInfoLine: "Preset: ", presetName$, " | ", nRes, " resonators | ", layoutStr$
if nDropped > 0
    appendInfoLine: "  NOTE: ", nDropped, " resonator(s) outside 20 Hz..Nyquist-20 Hz were dropped"
endif
appendInfoLine: "Excitation scaling: ", scaleStr$, " | Transient focus: ", fixed$(transient_focus, 2),
    ... " | Bank norm 1/sqrt(", nRes, ")"
appendInfoLine: "Modulation: ", modStr$
if modulation > 1
    appendInfoLine: "  depth ", fixed$(modulation_depth_cents, 1), " cents, rate ",
        ... fixed$(modulation_rate_Hz, 3), " Hz"
endif
appendInfoLine: "Tail: ", tailStr$, " ", fixed$(tailLen, 3), " s (longest T60 ", fixed$(maxT60, 3), " s)"
if tailTruncated
    appendInfoLine: "  Tail shorter than the longest T60: 20 ms fade applied to the wet end"
endif
appendInfoLine: ""

# ============================================================
# Work copy at time 0, padded with the tail
# ============================================================
selectObject: original
workSound = Copy: "grm_work"
Shift times to: "start time", 0
if tailSamples > 0
    Create Sound from formula: "grm_tail", numChannels, 0, tailLen, samplingRate, "0"
    tailPad = selected("Sound")
    selectObject: workSound
    plusObject: tailPad
    Concatenate
    extended = selected("Sound")
    removeObject: workSound, tailPad
    workSound = extended
endif
selectObject: workSound
duration = Get total duration
totalSamples = Get number of samples
work$ = string$(workSound)
fs$ = string$(samplingRate)

# ============================================================
# Excitation
# ============================================================
# Transient_focus mixes the input with a transient-gated copy. The
# detector compares an instant-attack peak follower with a slow-rising
# copy of that same envelope: equal on steady material, far apart at an
# onset. gate = clamp(fast / slow - 1, 0, 1).
# The gate is linked across channels so the stereo image is not skewed.
selectObject: workSound
excitation = Copy: "grm_exc"
exc$ = string$(excitation)
if transient_focus > 0
    if numChannels = 2
        Create Sound from formula: "grm_abs", 1, 0, duration, samplingRate,
            ... "max(abs(object[" + work$ + ", 1, col]), abs(object[" + work$ + ", 2, col]))"
    else
        Create Sound from formula: "grm_abs", 1, 0, duration, samplingRate,
            ... "abs(object[" + work$ + ", 1, col])"
    endif
    envAbs = selected("Sound")
    kRelF = exp(-1 / (transient_release_s * samplingRate))
    kAtt = 1 - exp(-1 / (transient_attack_s * samplingRate))
    envFast = Copy: "grm_envf"
    Formula: "if self > self[col-1] * " + string$(kRelF) + " then self else self[col-1] * " +
        ... string$(kRelF) + " fi"
    # Slow envelope follows the FAST PEAK envelope, rising with a slow
    # attack and falling with it instantly: on any steady signal the two
    # converge (measured gate 0.004 on a steady sine), at an onset the
    # fast one leads by up to ~transient_attack_s.
    selectObject: envFast
    envSlow = Copy: "grm_envs"
    Formula: "if self > self[col-1] then self[col-1] + " + string$(kAtt) +
        ... " * (self - self[col-1]) else self fi"
    selectObject: excitation
    gateExpr$ = "min(1, max(0, object[" + string$(envFast) + ", 1, col] / (object[" +
        ... string$(envSlow) + ", 1, col] + 1e-12) - 1))"
    Formula: "self * (" + string$(1 - transient_focus) + " + " + string$(transient_focus) +
        ... " * " + gateExpr$ + ")"
    removeObject: envAbs, envFast, envSlow
endif

# ============================================================
# Modulation control (one row per resonator)
# ============================================================
if modulation = 3 or modulation = 4
    ctlDur = duration + 4 / modulation_rate_Hz
    Create Sound from formula: "grm_ctl", nRes, 0, ctlDur, modulation_rate_Hz,
        ... "randomUniform(-1, 1)"
    ctl = selected("Sound")
    ctl$ = string$(ctl)
endif
rate$ = string$(modulation_rate_Hz)
depth$ = string$(modulation_depth_cents)
nyqLim$ = string$(nyquist - 20)

# ============================================================
# 7. RESONATOR BANK
# ============================================================
appendInfoLine: "Running ", nRes, " resonators..."
Create Sound from formula: "Wet_Mix", 2, 0, duration, samplingRate, "0"
wetSum = selected("Sound")

nTraj = 160
if numChannels = 2
    srcRow$ = "row"
else
    srcRow$ = "1"
endif
measN1 = srcSamples + round(0.02 * samplingRate)

for k from 1 to nRes
    fk$ = string$(freq[k])
    # --- running phase th[n] (the coefficient trajectory) ---
    if modulation = 1
        Create Sound from formula: "grm_ph", 1, 0, duration, samplingRate,
            ... "2 * pi * " + fk$ + " * (col - 1) / " + fs$
    else
        if modulation = 2
            phiK = 2 * pi * (k - 1) / nRes
            modX$ = "sin(2 * pi * " + rate$ + " * x + " + string$(phiK) + ")"
        elsif modulation = 3
            pp$ = "(x * " + rate$ + " + 1.5)"
            modX$ = "(object[" + ctl$ + ", " + string$(k) + ", floor(" + pp$ + ")] + " +
                ... "(object[" + ctl$ + ", " + string$(k) + ", floor(" + pp$ + ") + 1] - " +
                ... "object[" + ctl$ + ", " + string$(k) + ", floor(" + pp$ + ")]) * " +
                ... "(1 - cos(pi * (" + pp$ + " - floor(" + pp$ + ")))) / 2)"
        else
            modX$ = "object[" + ctl$ + ", " + string$(k) + ", floor(x * " + rate$ + " + 1.5)]"
        endif
        fexpr$ = "min(max(" + fk$ + " * 2 ^ (" + depth$ + " * " + modX$ + " / 1200), 20), " +
            ... nyqLim$ + ")"
        Create Sound from formula: "grm_ph", 1, 0, duration, samplingRate, "0"
        Formula: "self[col-1] + 2 * pi * " + fexpr$ + " / " + fs$
    endif
    ph = selected("Sound")
    ph$ = string$(ph)

    # --- recursion: one real state per row (re/im per channel) ---
    Create Sound from formula: "grm_state", 2 * numChannels, 0, duration, samplingRate, "0"
    st = selected("Sound")
    st$ = string$(st)
    Formula: "object[" + exc$ + ", (row + 1) div 2, col] * (if row mod 2 = 1 then cos(object[" +
        ... ph$ + ", 1, col]) else -sin(object[" + ph$ + ", 1, col]) fi) + " +
        ... string$(rad[k]) + " * self[col-1]"

    # --- decay measured on the actual state envelope |v| after the source ---
    t60Meas[k] = undefined
    measN2 = measN1 + round(min(0.5 * t60[k], tailLen - 0.04) * samplingRate)
    if measN2 - measN1 >= round(0.05 * samplingRate) and measN2 <= totalSamples
        bestA1 = 0
        bestA2 = 0
        for c from 1 to numChannels
            re1 = Get value at sample number: 2 * c - 1, measN1
            im1 = Get value at sample number: 2 * c, measN1
            re2 = Get value at sample number: 2 * c - 1, measN2
            im2 = Get value at sample number: 2 * c, measN2
            a1 = sqrt(re1 ^ 2 + im1 ^ 2)
            if a1 > bestA1
                bestA1 = a1
                bestA2 = sqrt(re2 ^ 2 + im2 ^ 2)
            endif
        endfor
        if bestA1 > 1e-12 and bestA2 > 0 and bestA2 < bestA1
            t60Meas[k] = 3 * ((measN2 - measN1) / samplingRate) / log10(bestA1 / bestA2)
        endif
    endif

    # --- real output of this resonator ---
    Create Sound from formula: "grm_y", numChannels, 0, duration, samplingRate,
        ... string$(gTot[k]) + " * (object[" + st$ + ", 2 * row - 1, col] * cos(object[" + ph$ +
        ... ", 1, col]) - object[" + st$ + ", 2 * row, col] * sin(object[" + ph$ + ", 1, col]))"
    yk = selected("Sound")
    rmsOut[k] = Get root-mean-square: 0, 0
    if rmsOut[k] > 0
        rmsDB[k] = 20 * log10(rmsOut[k])
    else
        rmsDB[k] = -300
    endif

    # --- coefficient trajectory, read back from the phase actually used ---
    selectObject: ph
    for j from 1 to nTraj
        nj = 1 + round((j - 1) / (nTraj - 1) * (totalSamples - 2))
        th1 = Get value at sample number: 1, nj
        th2 = Get value at sample number: 1, nj + 1
        trajT[j] = (nj - 0.5) / samplingRate
        traj[k, j] = (th2 - th1) * samplingRate / (2 * pi)
    endfor

    # --- pan into the stereo wet bus ---
    selectObject: wetSum
    Formula: "self + (if row = 1 then " + string$(pL[k]) + " else " + string$(pR[k]) +
        ... " fi) * object[" + string$(yk) + ", " + srcRow$ + ", col]"
    removeObject: ph, st, yk
endfor

if modulation = 3 or modulation = 4
    removeObject: ctl
endif
removeObject: excitation

# Safety fade only where a still-audible tail is cut short
if tailTruncated
    fadeLen = min(0.02, duration / 4)
    selectObject: wetSum
    Formula (part): duration - fadeLen, duration, 1, 2,
        ... "self * (0.5 + 0.5 * cos(pi * (x - " + string$(duration - fadeLen) + ") / " +
        ... string$(fadeLen) + "))"
endif

selectObject: wetSum
wetNaturalPeak = Get absolute extremum: 0, 0, "None"
wetSrcRMS = Get root-mean-square: 0, inputDuration
if tailSamples > round(0.5 * samplingRate)
    wetTailRMS = Get root-mean-square: inputDuration, inputDuration + 0.5
else
    wetTailRMS = undefined
endif
appendInfoLine: "  Natural wet peak: ", fixed$(wetNaturalPeak, 6)

# --- Measured spectrum of the wet bus (for the figure) ---
if draw_visualization
    selectObject: wetSum
    wetMono = Convert to mono
    wetSpec = To Spectrum: "yes"
    specLo = max(10, minF / 2)
    specHi = min(nyquist * 0.98, maxF * 2)
    if specHi <= specLo * 1.5
        specHi = specLo * 1.5
    endif
    nSpecB = 180
    specRes = 2 / duration
    specMax = -1000
    for b from 1 to nSpecB
        fa = specLo * (specHi / specLo) ^ ((b - 1) / nSpecB)
        fb = specLo * (specHi / specLo) ^ (b / nSpecB)
        if fb - fa < specRes
            fcen = sqrt(fa * fb)
            fa = max(0, fcen - specRes / 2)
            fb = fcen + specRes / 2
        endif
        dens = Get band density: fa, fb
        specF[b] = sqrt(fa * fb)
        if dens > 0
            specDB[b] = 10 * log10(dens)
        else
            specDB[b] = -300
        endif
        specMax = max(specMax, specDB[b])
    endfor
    removeObject: wetSpec
endif

# --- 8. DRY/WET ---
# Dry_wet = 0 is a true bypass: the original samples, domain and channel
# count, no tail.
if dry_wet = 0
    selectObject: original
    output = Copy: "grm_bypass"
    Shift times to: "start time", 0
    bypassed = 1
else
    bypassed = 0
    selectObject: workSound
    dry = Copy: "dry_temp"
    if numChannels = 1
        selectObject: dry
        Convert to stereo
        stereoDry = selected("Sound")
        removeObject: dry
        dry = stereoDry
    endif
    selectObject: dry
    Formula: "self * " + string$(1 - dry_wet) + " + object[" + string$(wetSum) +
        ... ", row, col] * " + string$(dry_wet)
    output = dry
endif

# --- 9. OUTPUT LEVEL ---
selectObject: output
preLevelPeak = Get absolute extremum: 0, 0, "None"
levelAction$ = "natural level"
if bypassed
    levelAction$ = "skipped (Dry/Wet 0 = bypass)"
else
    if output_level_mode = 2
        if preLevelPeak > finalPeak
            Scale peak: finalPeak
            levelAction$ = "ceiling applied (" + fixed$(20 * log10(finalPeak / preLevelPeak), 1) + " dB)"
        else
            levelAction$ = "ceiling not needed"
        endif
    elsif output_level_mode = 3
        if preLevelPeak > 0
            Scale peak: finalPeak
            levelAction$ = "peak normalized"
        endif
    endif
endif
selectObject: output
outPeak = Get absolute extremum: 0, 0, "None"
outDuration = Get total duration

# --- Per-resonator report ---
appendInfoLine: ""
appendInfoLine: "  #     f (Hz)   T60 set  T60 meas   r              Q      BW (Hz)  |H| peak (cents)  out RMS (dB)"
for k from 1 to nRes
    if t60Meas[k] = undefined
        tm$ = "   --   "
    else
        tm$ = fixed$(t60Meas[k], 3)
    endif
    appendInfoLine: "  ", k, "   ", fixed$(freq[k], 2), "   ", fixed$(t60[k], 3), "   ", tm$, "   ",
        ... fixed$(rad[k], 9), "   ", fixed$(qFac[k], 0), "   ", fixed$(bwHz[k], 3), "   ",
        ... fixed$(round(peakCents[k] * 1000) / 1000, 3), "   ", fixed$(rmsDB[k], 1)
endfor
appendInfoLine: "  Ringing frequency = pole angle, exact by construction. 'T60 meas' is read from"
appendInfoLine: "  the resonator state envelope after the source ends (needs a tail)."

# ============================================================
# VISUALIZATION (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    Erase all
    pageHeight = 8.20
    Select outer viewport: 0, 8, 0, pageHeight

    # Output panel uses the output's own scale: an impulse input would
    # otherwise set the range and hide a quiet resonant tail.
    vizAmp = max(outPeak, 0.000001) * 1.1
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)

    # --- TITLE ---
    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##GRM-Style Resonator v2.0##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$ + " | " +
        ... string$(nRes) + " resonators | " + modStr$

    # --- 1. OUTPUT WITH TAIL ---
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.75, 1.85
    Axes: 0, duration, -vizAmp, vizAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -vizAmp, vizAmp
    if tailLen > 0
        Paint rectangle: "{0.93, 0.95, 0.98}", inputDuration, duration, -vizAmp, vizAmp
    endif
    selectObject: output
    Colour: "{0.20, 0.60, 0.50}"
    Draw: 0, duration, -vizAmp, vizAmp, "no", "Curve"
    Select inner viewport: 0.60, 7.70, 0.75, 1.85
    Axes: 0, duration, -vizAmp, vizAmp
    Colour: "{0.80, 0.30, 0.30}"
    Dotted line
    Draw line: inputDuration, -vizAmp, inputDuration, vizAmp
    Solid line
    Colour: "Black"
    Draw inner box
    @niceStep: duration / 6
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Text top: "no", "Output L/R, peak " + fixed$(outPeak, 4) + "; pale area = resonant tail after the source ends (dotted line)"
    Text left: "yes", "Amplitude"

    # --- 2. SPECTROGRAM + COEFFICIENT TRAJECTORIES ---
    trajMax = maxF
    for k from 1 to nRes
        for j from 1 to nTraj
            trajMax = max(trajMax, traj[k, j])
        endfor
    endfor
    sgTop = min(nyquist, trajMax * 1.25)
    minSpacing = sgTop
    for k from 1 to nRes - 1
        for m from k + 1 to nRes
            minSpacing = min(minSpacing, abs(freq[k] - freq[m]))
        endfor
    endfor
    sgWin = max(0.02, min(0.12, 2.5 / max(minSpacing, 1)))
    selectObject: output
    outMono = Convert to mono
    sgTimeStep = max(0.002, duration / 800)
    sg = To Spectrogram: sgWin, sgTop, sgTimeStep, sgTop / 400, "Gaussian"
    Select inner viewport: 0.60, 7.70, 2.45, 4.05
    Paint: 0, duration, 0, sgTop, 100, "yes", 60, 6, 0, "no"
    Select inner viewport: 0.60, 7.70, 2.45, 4.05
    Axes: 0, duration, 0, sgTop
    Colour: "{0.85, 0.25, 0.20}"
    Line width: 1
    for k from 1 to nRes
        for j from 1 to nTraj - 1
            Draw line: trajT[j], traj[k, j], trajT[j + 1], traj[k, j + 1]
        endfor
    endfor
    Colour: "{0.30, 0.40, 0.80}"
    Dotted line
    Draw line: inputDuration, 0, inputDuration, sgTop
    Solid line
    Colour: "Black"
    Select inner viewport: 0.60, 7.70, 2.45, 4.05
    Axes: 0, duration, 0, sgTop
    Draw inner box
    @niceStep: duration / 6
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: sgTop / 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    Text top: "no", "Measured output spectrogram (grey) with the resonator frequencies actually used (red)"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    removeObject: sg, outMono

    # --- 3a. MEASURED SPECTRUM vs INTENDED FREQUENCIES ---
    specFloor = specMax - 70
    Select inner viewport: 0.60, 3.75, 4.65, 5.85
    Axes: log10(specLo), log10(specHi), specFloor, specMax + 5
    Paint rectangle: "{0.97, 0.97, 0.97}", log10(specLo), log10(specHi), specFloor, specMax + 5
    Colour: "{0.85, 0.55, 0.55}"
    Dotted line
    for k from 1 to nRes
        Draw line: log10(freq[k]), specFloor, log10(freq[k]), specMax + 5
    endfor
    Solid line
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 1.5
    for b from 1 to nSpecB - 1
        y1 = max(specFloor, specDB[b])
        y2 = max(specFloor, specDB[b + 1])
        Draw line: log10(specF[b]), y1, log10(specF[b + 1]), y2
    endfor
    Line width: 1
    Colour: "Black"
    Select inner viewport: 0.60, 3.75, 4.65, 5.85
    Axes: log10(specLo), log10(specHi), specFloor, specMax + 5
    Draw inner box
    tickList$ = "20 50 100 200 500 1000 2000 5000 10000 20000"
    str$ = tickList$ + " "
    while length(str$) > 0
        sp = index(str$, " ")
        tv = number(left$(str$, sp - 1))
        str$ = mid$(str$, sp + 1, length(str$) - sp)
        if tv >= specLo and tv <= specHi
            if tv >= 1000
                tl$ = fixed$(tv / 1000, 0) + "k"
            else
                tl$ = fixed$(tv, 0)
            endif
            One mark bottom: log10(tv), "no", "yes", "no", tl$
        endif
    endwhile
    Marks left every: 1, 20, "yes", "yes", "no"
    Text top: "no", "Wet spectrum, measured (blue) vs intended frequencies (red)"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz, log)"

    # --- 3b. DECAY: CONFIGURED vs MEASURED ---
    decTop = maxT60 * 1.2
    Select inner viewport: 4.55, 7.70, 4.65, 5.85
    Axes: 0, nRes + 1, 0, decTop
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nRes + 1, 0, decTop
    bw = min(0.35, 0.4)
    for k from 1 to nRes
        Paint rectangle: "{0.70, 0.78, 0.90}", k - bw, k + bw, 0, t60[k]
    endfor
    Select inner viewport: 4.55, 7.70, 4.65, 5.85
    Axes: 0, nRes + 1, 0, decTop
    nMeasured = 0
    for k from 1 to nRes
        if t60Meas[k] <> undefined
            nMeasured = nMeasured + 1
            Paint circle (mm): "{0.80, 0.30, 0.30}", k, min(t60Meas[k], decTop), 0.8
        endif
    endfor
    Colour: "Black"
    Select inner viewport: 4.55, 7.70, 4.65, 5.85
    Axes: 0, nRes + 1, 0, decTop
    Draw inner box
    @niceStep: decTop / 3
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    if nMeasured > 0
        Text top: "no", "T60: set (bars) vs measured on the state (dots)"
    else
        Text top: "no", "T60 set (bars); not measurable here: no tail"
    endif
    Text left: "yes", "T60 (s)"
    Text bottom: "yes", "Resonator"

    # --- 4a. LEVEL: CONFIGURED GAIN vs MEASURED OUTPUT ---
    # Both relative to their own maximum, so the profile shape and the
    # measured balance can be compared directly.
    gMaxDB = -1000
    mMaxDB = -1000
    for k from 1 to nRes
        cfgDB[k] = 20 * log10(max(gTot[k], 1e-15))
        gMaxDB = max(gMaxDB, cfgDB[k])
        mMaxDB = max(mMaxDB, rmsDB[k])
    endfor
    lvlFloor = -48
    Select inner viewport: 0.60, 3.75, 6.45, 7.65
    Axes: 0, nRes + 1, lvlFloor, 3
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nRes + 1, lvlFloor, 3
    for k from 1 to nRes
        mv = max(lvlFloor, rmsDB[k] - mMaxDB)
        Paint rectangle: "{0.55, 0.75, 0.65}", k - 0.35, k + 0.35, lvlFloor, mv
    endfor
    Select inner viewport: 0.60, 3.75, 6.45, 7.65
    Axes: 0, nRes + 1, lvlFloor, 3
    Colour: "{0.50, 0.20, 0.50}"
    Line width: 2
    for k from 1 to nRes - 1
        Draw line: k, max(lvlFloor, cfgDB[k] - gMaxDB), k + 1, max(lvlFloor, cfgDB[k + 1] - gMaxDB)
    endfor
    Line width: 1
    for k from 1 to nRes
        Paint circle (mm): "{0.50, 0.20, 0.50}", k, max(lvlFloor, cfgDB[k] - gMaxDB), 0.6
    endfor
    Colour: "Black"
    Select inner viewport: 0.60, 3.75, 6.45, 7.65
    Axes: 0, nRes + 1, lvlFloor, 3
    Draw inner box
    Marks left every: 1, 12, "yes", "yes", "no"
    Text top: "no", "Level re max: configured gain (line) vs measured output RMS (bars)"
    Text left: "yes", "dB"
    Text bottom: "yes", "Resonator"

    # --- 4b. SUMMARY STRIP ---
    Font size: 7
    Select inner viewport: 4.55, 7.70, 6.45, 7.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.04, "left", 0.91, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 4.55, 7.70, 6.45, 7.65
    Axes: 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.04, "left", 0.77, "half", "Resonators: " + string$(nRes) + " | " + layoutStr$
    Text: 0.04, "left", 0.65, "half", "Freq: " + fixed$(minF, 1) + "-" + fixed$(maxF, 1) + " Hz"
    Text: 0.04, "left", 0.53, "half", "T60: " + fixed$(t60[1], 2) + " s (res 1), max " + fixed$(maxT60, 2) + " s"
    Text: 0.04, "left", 0.41, "half", "Scaling: " + scaleStr$ + ", focus " + fixed$(transient_focus, 2)
    Text: 0.04, "left", 0.29, "half", "Gain: " + fixed$(resonance_gain_dB, 1) + " dB, " + gainProfileStr$
    Text: 0.04, "left", 0.17, "half", "Mod: " + modStr$ + " | Pan: " + panningStr$
    Text: 0.54, "left", 0.77, "half", "Dry/Wet: " + fixed$(dry_wet * 100, 0) + "\%  wet"
    Text: 0.54, "left", 0.65, "half", "Wet peak: " + fixed$(wetNaturalPeak, 4)
    Text: 0.54, "left", 0.53, "half", "Out peak: " + fixed$(outPeak, 4)
    Text: 0.54, "left", 0.41, "half", "Level: " + levelAction$
    Text: 0.54, "left", 0.29, "half", "Tail: " + tailStr$ + " " + fixed$(tailLen, 2) + " s"
    Text: 0.54, "left", 0.17, "half", "Duration: " + fixed$(outDuration, 2) + " s | seed " + string$(random_seed)
    Select inner viewport: 4.55, 7.70, 6.45, 7.65
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: wetMono
    # Restore complete page for Picture export / clipboard.
    Font size: 10
    Select outer viewport: 0, 8, 0, pageHeight
    Colour: "Black"
    Line width: 1
    Solid line
endif

# --- CLEANUP AND FINISH ---
removeObject: wetSum, workSound

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
appendInfoLine: "  Peak: ", fixed$(inputPeak, 4), " -> ", fixed$(outPeak, 4), " (", levelAction$, ")"
if wetTailRMS <> undefined and wetSrcRMS > 0
    appendInfoLine: "  Wet RMS first 0.5 s after the source re source part: ",
        ... fixed$(20 * log10(max(wetTailRMS, 1e-15) / wetSrcRMS), 1), " dB"
endif
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

procedure niceStep: .raw
    .mag = 10 ^ floor(log10(.raw))
    .n = .raw / .mag
    if .n < 1.5
        .step = .mag
    elsif .n < 3.5
        .step = 2 * .mag
    elsif .n < 7.5
        .step = 5 * .mag
    else
        .step = 10 * .mag
    endif
endproc

# |H(e^jw)|^2 of the real resonator output, H = (1 - rc z^-1)/(1 - 2 rc z^-1 + r^2 z^-2)
procedure resMag2: .r, .rc, .om
    .nr = 1 - .rc * cos(.om)
    .ni = .rc * sin(.om)
    .dr = 1 - 2 * .rc * cos(.om) + .r * .r * cos(2 * .om)
    .di = 2 * .rc * sin(.om) - .r * .r * sin(2 * .om)
    .m = (.nr * .nr + .ni * .ni) / (.dr * .dr + .di * .di)
endproc
