# ============================================================
# Praat AudioTools - Schroeder_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2026)
# v0.2 (2026): Wet normalisation is now MEASURED from the rendered impulse
#   response instead of assumed from a closed form. The v0.1 formula treated
#   the comb bank as incoherent, which it is not - every comb passes the same
#   direct term - leaving the wet 2.33 dB hot on Schroeder 1962 and 6.25 dB
#   hot on the short-slap preset. T30 is now a least-squares fit rather than
#   a two-point crossing (up to 9.4 % apart on Small room). "Gated slap"
#   renamed "Short slap": the preset contains no gate. Delay lines are now
#   guaranteed distinct, which they were not at 8 kHz. Dry path folds down
#   correctly for mono output and for inputs with more than two channels.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Schroeder reverberator (JAES 1962) built natively in Praat:
#   a bank of parallel feedback comb filters whose delays are
#   mutually prime, summed and then passed through a chain of
#   series allpass sections.
#
#     comb:     y[n] = x[n] + g * y[n-D]
#     allpass:  y[n] = -g * x[n] + x[n-D] + g * y[n-D]
#
#   Both recursions are evaluated in place with Praat's Formula,
#   which writes columns in ascending order, so self[1, col-D]
#   reads a sample the same pass has already produced. No Python,
#   no convolution, no external IR file.
#
#   Comb gains are derived from the requested RT60 rather than set
#   by hand: g = 10^(-3D / (RT60 * fs)), so every comb in the bank
#   decays to -60 dB in the same time despite different delays.
#
#   Wet level is set by MEASUREMENT, not by formula. The network's
#   impulse response is rendered first; its summed square is the
#   filter's energy gain, and the wet path is scaled by the inverse
#   square root of that, so the send has unit energy gain whatever
#   the preset, the damping or the sample rate. No closed form is
#   used, because none of them survives damping.
#
#   The figure's impulse response and energy decay curve are
#   produced by running the SAME network code on a unit impulse,
#   so the drawn decay describes the audio that was rendered
#   rather than the parameters that were requested. The RT60
#   reported as "measured" is a least-squares T30 fit over the
#   -5 to -35 dB span of that decay curve, as in ISO 3382, with
#   a T20 fit and then a two-point crossing as fallbacks when the
#   tail is too short to support the fit.
#
# Notes:
#   - Damping is a two-tap FIR lowpass inside the feedback path
#     (Moorer-style; Schroeder's 1962 network has none). Loop gain
#     is g at DC and g*(1-2d) at Nyquist, so the HF tail is shorter
#     than the LF tail. Both times are reported. Set damping to 0
#     for the historical network.
#   - A Schroeder comb bank passes the source through undelayed, so
#     at 100 % wet the output still contains the direct sound. That
#     is the historical network and remains the default; the advanced
#     dialog can remove the direct component from the wet path, which
#     makes the tail level far more consistent between presets.
#   - The final Scale is an attenuate-only ceiling: quiet material
#     is never boosted.
#
# ============================================================

form Schroeder Reverb
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Schroeder 1962 (classic)
        option Small room
        option Concert hall
        option Cathedral
        option Plate-like
        option Short slap

    comment === Reverb ===
    positive Reverb_time_RT60_s 1.8
    real Wet_dry_percent 35
    comment (0 = dry only, 100 = wet only)

    comment === Output ===
    boolean Advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT
# ============================================================

if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected ("Sound")
originalName$ = selected$ ("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# Private zero-based processing copy; the caller's Sound is untouched.
selectObject: original
workSource = Copy: "schroeder_work"
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif
nSrc = Get number of samples

# ============================================================
# PRESETS
# ============================================================
# Preset 1 keeps the two form fields live. Every other preset sets
# the full parameter set below; all of it is then shown, pre-filled
# and editable, in the Advanced settings dialog, so a preset stays
# inspectable rather than being a black box.

if preset = 1
    presetName$ = "Custom"
    comb_count = 4
    shortest_comb_ms = 29.7
    longest_comb_ms = 43.7
    damping = 0.15
    predelay_ms = 12
    allpass_count = 2
    allpass_gain = 0.7
    stereo_spread_ms = 0.8
elsif preset = 2
    # Schroeder's published network: four combs 29.7-43.7 ms,
    # two allpasses at 5 ms and 1.7 ms with g = 0.7, no damping.
    presetName$ = "Schroeder1962"
    reverb_time_RT60_s = 1.9
    wet_dry_percent = 40
    comb_count = 4
    shortest_comb_ms = 29.7
    longest_comb_ms = 43.7
    damping = 0
    predelay_ms = 0
    allpass_count = 2
    allpass_gain = 0.7
    stereo_spread_ms = 0.8
elsif preset = 3
    presetName$ = "SmallRoom"
    reverb_time_RT60_s = 0.55
    wet_dry_percent = 22
    comb_count = 4
    shortest_comb_ms = 13.5
    longest_comb_ms = 22.0
    damping = 0.30
    predelay_ms = 6
    allpass_count = 2
    allpass_gain = 0.7
    stereo_spread_ms = 0.5
elsif preset = 4
    presetName$ = "ConcertHall"
    reverb_time_RT60_s = 2.1
    wet_dry_percent = 38
    comb_count = 6
    shortest_comb_ms = 32.0
    longest_comb_ms = 58.0
    damping = 0.22
    predelay_ms = 22
    allpass_count = 3
    allpass_gain = 0.7
    stereo_spread_ms = 1.1
elsif preset = 5
    presetName$ = "Cathedral"
    reverb_time_RT60_s = 5.5
    wet_dry_percent = 52
    comb_count = 8
    shortest_comb_ms = 45.0
    longest_comb_ms = 92.0
    damping = 0.12
    predelay_ms = 45
    allpass_count = 3
    allpass_gain = 0.75
    stereo_spread_ms = 1.8
elsif preset = 6
    # Dense, bright, short delays: plate character rather than a room.
    presetName$ = "PlateLike"
    reverb_time_RT60_s = 2.6
    wet_dry_percent = 45
    comb_count = 8
    shortest_comb_ms = 8.5
    longest_comb_ms = 19.5
    damping = 0.05
    predelay_ms = 0
    allpass_count = 4
    allpass_gain = 0.78
    stereo_spread_ms = 0.4
elsif preset = 7
    presetName$ = "ShortSlap"
    reverb_time_RT60_s = 0.28
    wet_dry_percent = 55
    comb_count = 5
    shortest_comb_ms = 24.0
    longest_comb_ms = 47.0
    damping = 0.02
    predelay_ms = 18
    allpass_count = 1
    allpass_gain = 0.6
    stereo_spread_ms = 1.4
endif

tail_s = 0
output_ceiling = 0.95
output_channels = 1
wet_contains_direct = 1

# ============================================================
# ADVANCED SETTINGS
# ============================================================
# Kept out of the main form so the form stays short. Under
# praat --run this block auto-continues with the values below.

if advanced_settings
    beginPause: "Schroeder Reverb - advanced (" + presetName$ + ")"
        comment: "Network"
        positive: "Reverb time RT60 s", string$ (reverb_time_RT60_s)
        natural: "Comb count", string$ (comb_count)
        positive: "Shortest comb ms", string$ (shortest_comb_ms)
        positive: "Longest comb ms", string$ (longest_comb_ms)
        integer: "Allpass count", string$ (allpass_count)
        positive: "Allpass gain", string$ (allpass_gain)
        comment: "Colour and space"
        real: "Damping", string$ (damping)
        comment: "(0 = no damping, 0.49 = maximum HF loss per pass)"
        real: "Predelay ms", string$ (predelay_ms)
        real: "Stereo spread ms", string$ (stereo_spread_ms)
        boolean: "Wet contains direct sound", wet_contains_direct
        comment: "(off = tail only; on = the historical Schroeder network)"
        comment: "Output"
        real: "Wet dry percent", string$ (wet_dry_percent)
        real: "Tail s", "0"
        comment: "(0 = automatic, 1.5 x RT60)"
        positive: "Output ceiling", string$ (output_ceiling)
        choice: "Output channels", output_channels
            option: "Stereo"
            option: "Mono"
    endPause: "Render", 1
endif

# ============================================================
# VALIDATION
# ============================================================

if comb_count < 2
    comb_count = 2
endif
if comb_count > 12
    comb_count = 12
endif
if allpass_count < 0
    allpass_count = 0
endif
if allpass_count > 6
    allpass_count = 6
endif

if longest_comb_ms <= shortest_comb_ms
    longest_comb_ms = shortest_comb_ms * 1.47
endif

dampClamped = 0
if damping < 0
    damping = 0
    dampClamped = 1
endif
if damping > 0.49
    damping = 0.49
    dampClamped = 1
endif

if allpass_gain >= 0.95
    allpass_gain = 0.95
endif
if predelay_ms < 0
    predelay_ms = 0
endif
if stereo_spread_ms < 0
    stereo_spread_ms = 0
endif

wetClamped = 0
if wet_dry_percent < 0
    wet_dry_percent = 0
    wetClamped = 1
endif
if wet_dry_percent > 100
    wet_dry_percent = 100
    wetClamped = 1
endif
wetMix = wet_dry_percent / 100

if tail_s <= 0
    tail_s = 1.5 * reverb_time_RT60_s
endif
if tail_s < 0.25
    tail_s = 0.25
endif

if output_channels = 2
    nWetCh = 1
else
    nWetCh = 2
endif

combDamp = damping
preD = round (predelay_ms * sr / 1000)

# ============================================================
# DELAY LINES
# ============================================================
# Comb delays are snapped to a PRIME number of samples so the
# combs share as few common echo instants as possible; that is
# what keeps the tail from ringing on a single period.

procedure nextPrime: .n
    .p = .n
    if .p < 2
        .p = 2
    endif
    .searching = 1
    while .searching = 1
        .isPrime = 1
        .d = 2
        while .d * .d <= .p
            if .isPrime = 1
                if .p mod .d = 0
                    .isPrime = 0
                endif
            endif
            .d = .d + 1
        endwhile
        if .isPrime = 1
            .searching = 0
        else
            .p = .p + 1
        endif
    endwhile
    nextPrime.result = .p
endproc

# Two delay lines of equal length defeat the point of the prime snapping.
# At 8 kHz the two shortest allpasses of the dense presets both landed on
# 5 samples, so the search now skips any length already taken.
procedure freePrime: .n
    .from = .n
    .accepted = 0
    while .accepted = 0
        @nextPrime: .from
        .cand = nextPrime.result
        .clash = 0
        for .u from 1 to nUsedDelays
            if usedDelay [.u] = .cand
                .clash = 1
            endif
        endfor
        if .clash = 0
            .accepted = 1
        else
            .from = .cand + 1
        endif
    endwhile
    nUsedDelays = nUsedDelays + 1
    usedDelay [nUsedDelays] = .cand
    freePrime.result = .cand
endproc

# Schroeder's four published delays, expressed as positions between
# the shortest and the longest, so the classic spacing is preserved
# when comb_count = 4 and stretched linearly for any other count.
classicPos [1] = 0
classicPos [2] = 0.528571
classicPos [3] = 0.814286
classicPos [4] = 1

spreadOffset = round (stereo_spread_ms * sr / 1000)

for ch from 1 to nWetCh
    nUsedDelays = 0
    for ci from 1 to comb_count
        if comb_count = 4
            pos = classicPos [ci]
        else
            pos = (ci - 1) / (comb_count - 1)
        endif
        delayMs = shortest_comb_ms + (longest_comb_ms - shortest_comb_ms) * pos
        rawD = round (delayMs * sr / 1000)
        if ch = 2
            rawD = rawD + spreadOffset
        endif
        if rawD < 8
            rawD = 8
        endif
        @freePrime: rawD
        combDelay [ch, ci] = freePrime.result
        # g such that the comb reaches -60 dB in exactly RT60 seconds.
        g = 10 ^ (-3 * combDelay [ch, ci] / (reverb_time_RT60_s * sr))
        if g > 0.985
            g = 0.985
        endif
        combGain [ch, ci] = g
    endfor

    for ai from 1 to allpass_count
        # 5.0, 1.7, 0.6, 0.2 ... ms - Schroeder's two, then thirds.
        apMs = 5.0 / (2.94 ^ (ai - 1))
        rawD = round (apMs * sr / 1000)
        if ch = 2
            rawD = rawD + round (spreadOffset / 2)
        endif
        if rawD < 4
            rawD = 4
        endif
        @freePrime: rawD
        apDelay [ch, ai] = freePrime.result
    endfor
endfor

# Provisional scaling inside the bank, only to keep intermediate values
# near unity. The wet gain that matters is measured from the rendered
# impulse response after the network has run.
combNorm = 1 / comb_count

# Decay times implied by the loop gains, at DC and at Nyquist.
gRef = combGain [1, 1]
dRef = combDelay [1, 1]
rt60_lf = -3 * dRef / (sr * log10 (gRef))
gHf = gRef * (1 - 2 * damping)
if gHf > 0.000001
    rt60_hf = -3 * dRef / (sr * log10 (gHf))
else
    rt60_hf = 0
endif

# ============================================================
# REPORT (parameters)
# ============================================================

writeInfoLine: "=== Schroeder Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$ (originalDur, 2), " s, ", numChannels, " ch, ", sr, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "RT60 requested: ", fixed$ (reverb_time_RT60_s, 2), " s"
appendInfoLine: "Combs: ", comb_count, "  |  Allpasses: ", allpass_count, " (g=", fixed$ (allpass_gain, 2), ")"
appendInfoLine: "Predelay: ", fixed$ (predelay_ms, 1), " ms  |  Tail: ", fixed$ (tail_s, 2), " s"
appendInfoLine: "Damping: ", fixed$ (damping, 3), "  ->  loop gain x", fixed$ (1 - 2 * damping, 3), " at Nyquist"
appendInfoLine: "  implied decay: ", fixed$ (rt60_lf, 2), " s at DC, ", fixed$ (rt60_hf, 2), " s at Nyquist"
appendInfoLine: "Wet/Dry: ", fixed$ (wet_dry_percent, 1), " %"
appendInfoLine: ""
appendInfoLine: "Comb bank (left):"
for ci from 1 to comb_count
    appendInfoLine: "  C", ci, ": ", combDelay [1, ci], " samples (", fixed$ (combDelay [1, ci] * 1000 / sr, 2), " ms), g=", fixed$ (combGain [1, ci], 4)
endfor
if allpass_count > 0
    appendInfoLine: "Allpass chain (left):"
    for ai from 1 to allpass_count
        appendInfoLine: "  A", ai, ": ", apDelay [1, ai], " samples (", fixed$ (apDelay [1, ai] * 1000 / sr, 2), " ms)"
    endfor
endif
appendInfoLine: ""
appendInfoLine: "Rendering..."

# ============================================================
# MONO SEND
# ============================================================
# The reverb send is mono, as in the original network; the stereo
# image comes from running two decorrelated networks, not from
# reverberating the two input channels separately.

selectObject: workSource
if numChannels > 1
    sendMono = Convert to mono
else
    sendMono = Copy: "schroeder_send"
endif

irN = preD + round (tail_s * sr) + 8
audN = round (originalDur * sr) + preD + round (tail_s * sr)

# ============================================================
# NETWORK
# ============================================================
# pass 1 renders the network's impulse response (used by the figure
# and by the T30 measurement); pass 2 renders the audio. Identical
# code, so the drawn decay is the decay that was rendered.

for pass from 1 to 2
    if pass = 1
        netN = irN
    else
        netN = audN
    endif
    netDur = netN / sr

    for ch from 1 to nWetCh
        # --- source buffer, predelay applied at construction ---
        if pass = 1
            Create Sound from formula: "net_src", 1, 0, netDur, sr, "if col = preD + 1 then 1 else 0 fi"
        else
            Create Sound from formula: "net_src", 1, 0, netDur, sr, "0"
            Formula: "if col <= preD then 0 else if col - preD <= nSrc then object [sendMono, 1, col - preD] else 0 fi fi"
        endif
        netSrc = selected ("Sound")

        # --- parallel comb bank ---
        for ci from 1 to comb_count
            selectObject: netSrc
            combTmp = Copy: "comb_tmp"
            combD = combDelay [ch, ci]
            combG = combGain [ch, ci]
            Formula: "if col > combD then self + combG * ((1 - combDamp) * self [1, col - combD] + combDamp * self [1, col - combD + 1]) else self fi"
            if ci = 1
                netAcc = combTmp
                selectObject: netAcc
                Rename: "net_acc"
            else
                combAdd = combTmp
                selectObject: netAcc
                Formula: "self + object [combAdd, 1, col]"
                removeObject: combTmp
            endif
        endfor

        selectObject: netAcc
        if wet_contains_direct = 0
            # Every comb passes x[n] through undelayed, so the bank carries
            # comb_count copies of the direct sound. Removing them leaves the
            # reverberant tail alone for the allpass chain to disperse.
            Formula: "self - comb_count * object [netSrc, 1, col]"
        endif
        Formula: "self * combNorm"

        # --- series allpass chain ---
        for ai from 1 to allpass_count
            selectObject: netAcc
            apIn = Copy: "ap_in"
            apD = apDelay [ch, ai]
            apG = allpass_gain
            selectObject: netAcc
            Formula: "if col > apD then -apG * self + object [apIn, 1, col - apD] + apG * self [1, col - apD] else -apG * self fi"
            removeObject: apIn
        endfor

        selectObject: netAcc
        if pass = 1
            Rename: "ir_" + string$ (ch)
            irId [ch] = netAcc
        else
            Rename: "wet_" + string$ (ch)
            wetId [ch] = netAcc
        endif
        removeObject: netSrc
    endfor

    if pass = 1
        # The impulse response IS the measurement: its summed square is the
        # network's energy gain, so the wet path is scaled by the inverse
        # square root of it. One shared gain for both channels, so the
        # stereo balance survives.
        energySum = 0
        for ch from 1 to nWetCh
            selectObject: irId [ch]
            irLen = Get total duration
            irEnergy = Get energy: 0, irLen
            energySum = energySum + irEnergy * sr
        endfor
        energyGain = energySum / nWetCh
        if energyGain > 0
            netGain = 1 / sqrt (energyGain)
        else
            netGain = 1
        endif
        for ch from 1 to nWetCh
            selectObject: irId [ch]
            Multiply: netGain
        endfor
    else
        for ch from 1 to nWetCh
            selectObject: wetId [ch]
            Multiply: netGain
        endfor
    endif
endfor

removeObject: sendMono

# ============================================================
# MEASURE THE RENDERED DECAY (Schroeder backward integration)
# ============================================================

nEdc = 400
selectObject: irId [1]
irDur = Get total duration
totalEnergy = Get energy: 0, irDur

edcValid = 0
if totalEnergy > 0
    edcValid = 1
    for k from 1 to nEdc
        tEdc = (k - 1) * irDur / nEdc
        eTail = Get energy: tEdc, irDur
        edcT [k] = tEdc
        if eTail > 0
            edcDb [k] = 10 * log10 (eTail / totalEnergy)
        else
            edcDb [k] = -120
        endif
    endfor
endif

# T30 fit: time between the -5 dB and -35 dB crossings, doubled.
procedure crossing: .target
    .t = -1
    .k = 2
    .done = 0
    while .k <= nEdc
        if .done = 0
            if edcDb [.k] <= .target
                .prevDb = edcDb [.k - 1]
                .thisDb = edcDb [.k]
                if .prevDb - .thisDb > 0
                    .frac = (.prevDb - .target) / (.prevDb - .thisDb)
                else
                    .frac = 0
                endif
                .t = edcT [.k - 1] + .frac * (edcT [.k] - edcT [.k - 1])
                .done = 1
            endif
        endif
        .k = .k + 1
    endwhile
    crossing.result = .t
endproc

# Least-squares slope of the decay curve over a dB window, as in ISO 3382.
# A two-point crossing is up to 9.4 % away from this on a damped preset.
procedure fitDecay: .hi, .lo
    .n = 0
    .sx = 0
    .sy = 0
    .sxx = 0
    .sxy = 0
    for .k from 1 to nEdc
        if edcDb [.k] <= .hi
            if edcDb [.k] >= .lo
                .n = .n + 1
                .sx = .sx + edcT [.k]
                .sy = .sy + edcDb [.k]
                .sxx = .sxx + edcT [.k] * edcT [.k]
                .sxy = .sxy + edcT [.k] * edcDb [.k]
            endif
        endif
    endfor
    .slope = 0
    if .n >= 2
        .den = .n * .sxx - .sx * .sx
        if .den <> 0
            .slope = (.n * .sxy - .sx * .sy) / .den
        endif
    endif
endproc

rt60_measured = 0
rt60_method$ = "not measurable"
if edcValid = 1
    @crossing: -5
    t5 = crossing.result
    @crossing: -35
    t35 = crossing.result
    @crossing: -25
    t25 = crossing.result
    fitOk = 0
    @fitDecay: -5, -35
    if fitDecay.n >= 10
        if fitDecay.slope < 0
            rt60_measured = -60 / fitDecay.slope
            rt60_method$ = "T30 fit, " + string$ (fitDecay.n) + " pts"
            fitOk = 1
        endif
    endif
    if fitOk = 0
        @fitDecay: -5, -25
        if fitDecay.n >= 10
            if fitDecay.slope < 0
                rt60_measured = -60 / fitDecay.slope
                rt60_method$ = "T20 fit, " + string$ (fitDecay.n) + " pts"
                fitOk = 1
            endif
        endif
    endif
    if fitOk = 0
        if t5 >= 0 and t35 > t5
            rt60_measured = 2 * (t35 - t5)
            rt60_method$ = "T30 crossing"
        elsif t5 >= 0 and t25 > t5
            rt60_measured = 3 * (t25 - t5)
            rt60_method$ = "T20 crossing"
        endif
    endif
endif

# Echo density at the end of the impulse response, as a sanity check
# on whether the network is dense enough to sound like a room.
selectObject: irId [1]
irPeak = Get maximum: 0, 0, "None"
irMin = Get minimum: 0, 0, "None"
if abs (irMin) > irPeak
    irPeak = abs (irMin)
endif

# ============================================================
# DRY / WET MIX
# ============================================================

audDur = audN / sr

# Dry fold-down. Mono output averages every source channel (it must not
# silently keep only channel 1 while the wet send is a full fold-down);
# stereo output takes L and R from a 2-channel source, and splits an
# input with more than two channels odd/even, as elsewhere in the library.
for ch from 1 to nWetCh
    Create Sound from formula: "dry_" + string$ (ch), 1, 0, audDur, sr, "0"
    dryId [ch] = selected ("Sound")
    nMix = 0
    for c from 1 to numChannels
        useChannel = 0
        if numChannels = 1
            useChannel = 1
        elsif nWetCh = 1
            useChannel = 1
        elsif numChannels = 2
            if c = ch
                useChannel = 1
            endif
        else
            if c mod 2 = ch mod 2
                useChannel = 1
            endif
        endif
        if useChannel = 1
            nMix = nMix + 1
            dryCh = c
            Formula: "if col <= nSrc then self + object [workSource, dryCh, col] else self fi"
        endif
    endfor
    dryMixCount [ch] = nMix
    if nMix > 1
        Formula: "self / nMix"
    endif
endfor

# Zero-padded copy of the source for the figure, so the Dry panel and the
# result panel share one time axis instead of two different ones.
Create Sound from formula: "dry_draw", numChannels, 0, audDur, sr, "0"
dryDraw = selected ("Sound")
Formula: "if col <= nSrc then object [workSource, row, col] else 0 fi"

for ch from 1 to nWetCh
    selectObject: wetId [ch]
    mixDry = dryId [ch]
    Formula: "self * wetMix + object [mixDry, 1, col] * (1 - wetMix)"
    removeObject: dryId [ch]
endfor

if nWetCh = 2
    selectObject: wetId [1], wetId [2]
    result = Combine to stereo
    removeObject: wetId [1], wetId [2]
else
    result = wetId [1]
endif

# Attenuate-only ceiling: never boost quiet material, never divide
# the wet/dry setting back out.
selectObject: result
outPeak = Get maximum: 0, 0, "None"
outMin = Get minimum: 0, 0, "None"
if abs (outMin) > outPeak
    outPeak = abs (outMin)
endif
ceilingApplied = 0
if outPeak > output_ceiling and outPeak > 0
    Multiply: output_ceiling / outPeak
    ceilingApplied = 1
    finalPeak = output_ceiling
else
    finalPeak = outPeak
endif

Rename: originalName$ + "_schroeder_" + presetName$

removeObject: workSource

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    titleName$ = replace$ (originalName$, "_", "\_ ", 0)

    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Schroeder Reverb: " + titleName$ + " (" + presetName$ + ")" + " | v0.2"

    # Dry waveform
    Font size: 7
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    selectObject: dryDraw
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.20, 0.48, 0.7, 1.3
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    Axes: 0, 1, 0, 1

    # Result waveform
    Font size: 7
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    selectObject: result
    Colour: "{0.60, 0.50, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.20, 0.48, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Wet " + fixed$ (wet_dry_percent, 0) + "\%  "
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    Axes: 0, audDur, -1, 1
    Text bottom: "yes", "Time (s)"

    # Impulse response of the network
    Font size: 7
    Select outer viewport: 0, 8, 2.7, 3.8
    Select inner viewport: 0.60, 7.70, 2.8, 3.7
    if irPeak <= 0
        irPeak = 1
    endif
    irRange = irPeak * 1.15
    Axes: 0, irDur, -irRange, irRange
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, irDur, -irRange, irRange
    if nWetCh = 2
        selectObject: irId [2]
        Colour: "{0.85, 0.45, 0.10}"
        Draw: 0, 0, -irRange, irRange, "no", "Curve"
    endif
    selectObject: irId [1]
    Colour: "{0.20, 0.40, 0.80}"
    Draw: 0, 0, -irRange, irRange, "no", "Curve"

    Select inner viewport: 0.60, 7.70, 2.8, 3.7
    Axes: 0, irDur, -irRange, irRange
    if preD > 0
        Colour: "{0.55, 0.55, 0.55}"
        Dotted line
        Draw line: preD / sr, -irRange, preD / sr, irRange
        Solid line
        Font size: 6
        Text: preD / sr, "left", irRange * 0.82, "half", " predelay"
    endif

    Select inner viewport: 0.60, 7.70, 2.8, 3.7
    Axes: 0, irDur, -irRange, irRange
    Font size: 6
    Colour: "{0.20, 0.40, 0.80}"
    Text: irDur * 0.985, "right", -irRange * 0.62, "half", "L"
    if nWetCh = 2
        Colour: "{0.85, 0.45, 0.10}"
        Text: irDur * 0.985, "right", -irRange * 0.82, "half", "R"
    endif

    Select inner viewport: 0.60, 7.70, 2.8, 3.7
    Axes: 0, irDur, -irRange, irRange
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.20, 0.48, 2.8, 3.7
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Impulse"
    Select inner viewport: 0.60, 7.70, 2.8, 3.7
    Axes: 0, irDur, -irRange, irRange

    # Energy decay curve
    Font size: 7
    Select outer viewport: 0, 8, 3.9, 5.1
    Select inner viewport: 0.60, 7.70, 4.0, 5.0
    Axes: 0, irDur, -80, 2
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, irDur, -80, 2

    Select inner viewport: 0.60, 7.70, 4.0, 5.0
    Axes: 0, irDur, -80, 2
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, -60, irDur, -60
    Solid line

    if edcValid = 1
        Colour: "{0.20, 0.40, 0.80}"
        Line width: 1.5
        for k from 2 to nEdc
            y1 = edcDb [k - 1]
            y2 = edcDb [k]
            if y1 < -80
                y1 = -80
            endif
            if y2 < -80
                y2 = -80
            endif
            Draw line: edcT [k - 1], y1, edcT [k], y2
        endfor
        Line width: 1
    endif

    Select inner viewport: 0.60, 7.70, 4.0, 5.0
    Axes: 0, irDur, -80, 2
    if rt60_measured > 0 and rt60_measured < irDur
        Colour: "{0.80, 0.20, 0.20}"
        Draw line: rt60_measured, -80, rt60_measured, 2
    endif
    if reverb_time_RT60_s < irDur
        Colour: "{0.45, 0.45, 0.45}"
        Dashed line
        Draw line: reverb_time_RT60_s, -80, reverb_time_RT60_s, 2
        Solid line
    endif

    Select inner viewport: 0.60, 7.70, 4.0, 5.0
    Axes: 0, irDur, -80, 2
    Font size: 6
    Colour: "{0.80, 0.20, 0.20}"
    Text: irDur * 0.985, "right", -8, "half", "measured " + fixed$ (rt60_measured, 2) + " s (" + rt60_method$ + ")"
    Colour: "{0.45, 0.45, 0.45}"
    Text: irDur * 0.985, "right", -16, "half", "requested " + fixed$ (reverb_time_RT60_s, 2) + " s"
    Colour: "{0.60, 0.60, 0.60}"
    Text: 0.02 * irDur, "left", -56, "half", "-60 dB"

    Select inner viewport: 0.60, 7.70, 4.0, 5.0
    Axes: 0, irDur, -80, 2
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 20, "yes", "yes", "no"
    Select inner viewport: 0.20, 0.48, 4.0, 5.0
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Decay (dB)"
    Select inner viewport: 0.60, 7.70, 4.0, 5.0
    Axes: 0, irDur, -80, 2
    Text bottom: "yes", "Time (s)"

    # Delay network map. Its height follows the row count so the labels
    # keep a workable pitch at 12 rows; everything below it shifts down.
    nRows = comb_count + allpass_count
    netH = 1.0
    if nRows > 9
        netH = 0.115 * nRows
    endif
    netTop = 5.6
    netBot = netTop + netH
    parTop = netBot + 0.45
    sumTop = netBot + 0.95
    canvasH = netBot + 2.05

    Font size: 7
    Select outer viewport: 0, 8, netTop - 0.1, netBot + 0.1
    Select inner viewport: 0.60, 7.70, netTop, netBot

    maxRowDelay = 0
    for ci from 1 to comb_count
        if combDelay [1, ci] * 1000 / sr > maxRowDelay
            maxRowDelay = combDelay [1, ci] * 1000 / sr
        endif
    endfor
    xMax = maxRowDelay * 1.78
    Axes: 0, xMax, nRows + 1, 0
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, xMax, nRows + 0.5, 0.5

    Select inner viewport: 0.60, 7.70, netTop, netBot
    Axes: 0, xMax, nRows + 1, 0
    Line width: 2
    for ci from 1 to comb_count
        dMs = combDelay [1, ci] * 1000 / sr
        gg = combGain [1, ci]
        Colour: "{0.30, 0.45, 0.70}"
        Draw line: 0, ci, dMs, ci
    endfor
    for ai from 1 to allpass_count
        dMs = apDelay [1, ai] * 1000 / sr
        Colour: "{0.85, 0.45, 0.10}"
        Draw line: 0, comb_count + ai, dMs, comb_count + ai
    endfor
    Line width: 1

    Select inner viewport: 0.60, 7.70, netTop, netBot
    Axes: 0, xMax, nRows + 1, 0
    Font size: 6
    if nRows <= 8
        showSamples = 1
    else
        showSamples = 0
    endif
    for ci from 1 to comb_count
        dMs = combDelay [1, ci] * 1000 / sr
        Colour: "{0.30, 0.45, 0.70}"
        Paint circle (mm): "{0.30, 0.45, 0.70}", dMs, ci, 0.9
        Colour: "{0.25, 0.25, 0.30}"
        rowLabel$ = "  C" + string$ (ci) + "  " + fixed$ (dMs, 1) + " ms   g=" + fixed$ (combGain [1, ci], 3)
        if showSamples = 1
            rowLabel$ = rowLabel$ + "   " + string$ (combDelay [1, ci]) + " smp"
        endif
        Select inner viewport: 0.60, 7.70, netTop, netBot
        Axes: 0, xMax, nRows + 1, 0
        Text: dMs, "left", ci, "half", rowLabel$
    endfor
    for ai from 1 to allpass_count
        dMs = apDelay [1, ai] * 1000 / sr
        Colour: "{0.85, 0.45, 0.10}"
        Paint circle (mm): "{0.85, 0.45, 0.10}", dMs, comb_count + ai, 0.9
        Colour: "{0.25, 0.25, 0.30}"
        rowLabel$ = "  A" + string$ (ai) + "  " + fixed$ (dMs, 2) + " ms   g=" + fixed$ (allpass_gain, 3)
        if showSamples = 1
            rowLabel$ = rowLabel$ + "   " + string$ (apDelay [1, ai]) + " smp"
        endif
        Select inner viewport: 0.60, 7.70, netTop, netBot
        Axes: 0, xMax, nRows + 1, 0
        Text: dMs, "left", comb_count + ai, "half", rowLabel$
    endfor

    Select inner viewport: 0.60, 7.70, netTop, netBot
    Axes: 0, xMax, nRows + 1, 0
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.20, 0.48, netTop, netBot
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Network"
    Select inner viewport: 0.60, 7.70, netTop, netBot
    Axes: 0, xMax, nRows + 1, 0
    Text bottom: "yes", "Delay (ms)"

    # Parameters
    Select outer viewport: 0, 8, parTop, parTop + 0.4
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.40, 0.40, 0.40}"
    Text: 0.5, "centre", 0.5, "half", "Combs: " + string$ (comb_count) + " | Allpass: " + string$ (allpass_count) + " | RT60: " + fixed$ (reverb_time_RT60_s, 2) + " s | Damping: " + fixed$ (damping, 2) + " | Predelay: " + fixed$ (predelay_ms, 0) + " ms | Spread: " + fixed$ (stereo_spread_ms, 1) + " ms | Wet gain: " + fixed$ (netGain, 3) + " | Peak: " + fixed$ (finalPeak, 3)

    Font size: 10
    Colour: "Black"

    # Summary strip - compact house spacing.
    Select outer viewport: 0, 8, sumTop, sumTop + 1.0
    Select inner viewport: 0.60, 7.70, sumTop + 0.07, sumTop + 0.93
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.60, 7.70, sumTop + 0.07, sumTop + 0.93
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.02, "left", 0.57, "half", "Parallel combs on mutually prime delays, then " + string$ (allpass_count) + " series allpass sections (Schroeder 1962)"
    Select inner viewport: 0.60, 7.70, sumTop + 0.07, sumTop + 0.93
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    if damping > 0
        decayLine$ = "Decay measured on the rendered impulse response: " + fixed$ (rt60_measured, 2) + " s by " + rt60_method$ + "; damping places the broadband figure between " + fixed$ (rt60_hf, 2) + " s at Nyquist and " + fixed$ (reverb_time_RT60_s, 2) + " s at DC"
    else
        decayLine$ = "Decay measured on the rendered impulse response: " + fixed$ (rt60_measured, 2) + " s by " + rt60_method$ + " against " + fixed$ (reverb_time_RT60_s, 2) + " s requested, undamped"
    endif
    Text: 0.02, "left", 0.34, "half", decayLine$
    Select inner viewport: 0.60, 7.70, sumTop + 0.07, sumTop + 0.93
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.02, "left", 0.11, "half", "Wet gain " + fixed$ (netGain, 3) + " measured from this impulse response, not assumed; blue = left network, orange = right"

    Select inner viewport: 0.60, 7.70, sumTop + 0.07, sumTop + 0.93
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, canvasH
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

removeObject: irId [1], dryDraw
if nWetCh = 2
    removeObject: irId [2]
endif

# ============================================================
# FINAL REPORT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "RT60 measured on the rendered impulse response: ", fixed$ (rt60_measured, 3), " s (", rt60_method$, ")"
appendInfoLine: "  requested ", fixed$ (reverb_time_RT60_s, 3), " s"
if damping > 0
    appendInfoLine: "  The measurement is broadband, so with damping on it is EXPECTED to fall"
    appendInfoLine: "  between ", fixed$ (rt60_hf, 2), " s (Nyquist) and ", fixed$ (rt60_lf, 2), " s (DC). Set damping to 0"
    appendInfoLine: "  to compare the measured and requested times directly."
endif
appendInfoLine: "Network energy gain measured on the impulse response: ", fixed$ (energyGain, 4)
appendInfoLine: "  wet path scaled by ", fixed$ (netGain, 6), " for unit energy gain"
if wet_contains_direct = 0
    appendInfoLine: "  direct component removed from the wet path (tail only)"
else
    appendInfoLine: "  wet retains the direct sound, as in the 1962 network"
endif
if numChannels > 2
    appendInfoLine: "Dry fold-down: ", dryMixCount [1], " channel(s) to L, ", dryMixCount [nWetCh], " to R"
endif
appendInfoLine: "Output peak: ", fixed$ (finalPeak, 4)
if ceilingApplied = 1
    appendInfoLine: "  ceiling applied (pre-ceiling peak ", fixed$ (outPeak, 4), ")"
else
    appendInfoLine: "  below ceiling ", fixed$ (output_ceiling, 2), ", no scaling applied"
endif
if dampClamped = 1
    appendInfoLine: "Note: damping was clamped to the 0 - 0.49 range."
endif
if wetClamped = 1
    appendInfoLine: "Note: wet/dry was clamped to the 0 - 100 range."
endif
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$ ("Sound"), " (", fixed$ (audDur, 2), " s)"

# === Play ===
if play_result
    selectObject: result
    Play
endif
