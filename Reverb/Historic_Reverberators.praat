# ============================================================
# Praat AudioTools - Historic_Reverberators.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# v0.4 (2026): Historical-reference revision. Moorer Classic now uses the
#   published six-comb delays and per-comb one-pole coefficients from Table 2,
#   the published 19-tap early response from Table 3, and a 6 ms / 0.7 allpass.
#   The early FIR now feeds the recirculating late network as in Moorer Figure 12.
#   Gardner Small/Medium/Large now use the three distinct published structures
#   from Figure 4.11 instead of one scaled generic network. Gardner's published
#   RT-to-feedback mapping was empirical but its numerical table was not given;
#   feedback gain is therefore solved against this implementation's rendered IR.
#   Schroeder remains architecture-faithful; its canonical 29.7-43.7 ms realization
#   is identified as a later conventional choice, not a four-number table in 1962.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Three landmark artificial-reverberation designs, built natively
#   in Praat with no Python and no external impulse responses:
#
#     Schroeder 1962 - parallel feedback comb filters on mutually
#       prime delays, summed, then a chain of series allpass
#       sections. The original recirculating reverberator.
#
#     Moorer 1979 - a bank of comb filters each carrying a one-pole
#       lowpass inside its feedback loop, so high frequencies decay
#       faster than low ones, preceded by an FIR bank of discrete
#       early reflections and followed by a single allpass.
#
#     Gardner 1992 - three distinct diffuse-reverberator structures for
#       small, medium and large rooms, using cascaded and NESTED allpass
#       sections inside a lowpass-filtered feedback loop with weighted
#       output taps. The published Figure 4.11 values are used.
#
#   Every recursion is evaluated in place with Praat's Formula,
#   which writes columns in ascending order, so self[1, col-D]
#   reads a sample the same pass has already produced.
#
#     comb:        y[n] = x[n] + g*y[n-D]
#     lowpass comb (Moorer, one-pole in the loop, state eliminated):
#                  y[n] = x[n] - d*x[n-1] + d*y[n-1] + g(1-d)*y[n-D]
#     allpass:     y[n] = -g*x[n] + x[n-D] + g*y[n-D]
#     nested allpass (Gardner, inner allpass D1, outer delay D2):
#                  y[n] = -g2*x[n] + g1*g2*x[n-D1] - g1*x[n-D2]
#                         + x[n-D1-D2] + g1*y[n-D1] - g1*g2*y[n-D2]
#                         + g2*y[n-D1-D2]
#
#   The Gardner loop encloses its whole chain, so it cannot be run
#   one stage at a time over the whole buffer. It is processed in
#   blocks the length of the loop delay, which keeps the code in the
#   shape of the published block diagram instead of collapsing it
#   into one expanded difference equation.
#
#   Wet level is set by MEASUREMENT, not by formula. The network's
#   impulse response is rendered first; its summed square is the
#   filter's energy gain, and the wet path is scaled by the inverse
#   square root of that. This holds for all three topologies, any
#   damping and any sample rate, which is why they can share a file.
#
#   The figure's impulse response and decay curve come from running
#   the SAME network code on a unit impulse, so what is drawn is
#   what was rendered. Reported RT60 is a least-squares T30 fit over
#   the -5 to -35 dB span of that decay curve, as in ISO 3382, with
#   a T20 fit and a two-point crossing as fallbacks.
#
# HISTORICAL SCOPE:
#   Reference presets use published numerical parameters where the source gives
#   them explicitly. Moorer Classic follows Tables 2 and 3 and Figure 12. Gardner
#   Small/Medium/Large follow Figure 4.11. Schroeder's 1962 paper specifies a
#   30-45 ms comb-delay range (about 1:1.5), not one mandatory four-delay table;
#   Classic therefore keeps the widely used later 29.7/37.1/41.1/43.7 ms set.
#   Stereo delay offsets, arbitrary user RT60 values, and non-reference presets
#   are AudioTools extensions and are reported as such.
#
# Notes:
#   - Damping defaults to a true one-pole lowpass in the feedback
#     loop. The two-tap FIR of v0.2 is kept as a legacy option so
#     earlier renders reproduce; it notches at Nyquist and is
#     limited to 0.49, where the one-pole is not.
#   - A comb bank passes the source through undelayed, so at 100 %
#     wet the output still contains the direct sound. That is the
#     historical network and stays the default; the advanced dialog
#     can remove it. Not applicable to Gardner.
#   - The final Scale is an attenuate-only ceiling: quiet material
#     is never boosted, and the wet/dry setting is never divided
#     back out.
#
# ============================================================

form Historic Reverberators
    comment Select a Sound object first

    comment === Design ===
    optionmenu Topology 1
        option Schroeder 1962
        option Moorer 1979
        option Gardner 1992
    optionmenu Preset 2
        option Custom (use settings below)
        option Classic
        option Small
        option Medium
        option Large

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

selectObject: original
workSource = Copy: "reverb_work"
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif
nSrc = Get number of samples

if topology = 1
    topologyName$ = "Schroeder"
    topologyLong$ = "Schroeder 1962"
elsif topology = 2
    topologyName$ = "Moorer"
    topologyLong$ = "Moorer 1979"
else
    topologyName$ = "Gardner"
    topologyLong$ = "Gardner 1992"
endif

# ============================================================
# PRESETS
# ============================================================
# Preset 1 (Custom) keeps the two form fields live. The others set
# a full parameter table, all of which is shown pre-filled and
# editable in the Advanced settings dialog, so a preset stays
# inspectable rather than being a black box.

# --- defaults common to every topology ---
damping = 0.30
predelay_ms = 12
stereo_spread_ms = 0.8
tail_s = 0
output_ceiling = 0.95
output_channels = 1
wet_contains_direct = 1
damping_mode = 1

# --- comb-bank defaults (Schroeder, Moorer) ---
comb_count = 4
shortest_comb_ms = 29.7
longest_comb_ms = 43.7
allpass_count = 2
allpass_gain = 0.7

# --- early reflection defaults (Moorer) ---
moor_reference = 0
er_count = 18
er_first_ms = 8
er_span_ms = 80
er_level = 0.7
late_level = 1.0

# --- Gardner reference-network defaults ---
gardner_room = 2
gardner_lpf_hz = 2500
gardner_reference = 1

if topology = 1
    # ---------------- Schroeder 1962 ----------------
    if preset = 2
        presetName$ = "Classic"
        reverb_time_RT60_s = 1.9
        wet_dry_percent = 40
        comb_count = 4
        shortest_comb_ms = 29.7
        longest_comb_ms = 43.7
        allpass_count = 2
        allpass_gain = 0.7
        damping = 0
        predelay_ms = 0
    elsif preset = 3
        presetName$ = "Small"
        reverb_time_RT60_s = 0.55
        wet_dry_percent = 22
        comb_count = 4
        shortest_comb_ms = 13.5
        longest_comb_ms = 22.0
        allpass_count = 2
        allpass_gain = 0.7
        damping = 0.42
        predelay_ms = 6
        stereo_spread_ms = 0.5
    elsif preset = 4
        presetName$ = "Medium"
        reverb_time_RT60_s = 2.1
        wet_dry_percent = 38
        comb_count = 6
        shortest_comb_ms = 32.0
        longest_comb_ms = 58.0
        allpass_count = 3
        allpass_gain = 0.7
        damping = 0.34
        predelay_ms = 22
        stereo_spread_ms = 1.1
    elsif preset = 5
        presetName$ = "Large"
        reverb_time_RT60_s = 5.5
        wet_dry_percent = 52
        comb_count = 8
        shortest_comb_ms = 45.0
        longest_comb_ms = 92.0
        allpass_count = 3
        allpass_gain = 0.75
        damping = 0.20
        predelay_ms = 45
        stereo_spread_ms = 1.8
    else
        presetName$ = "Custom"
    endif
elsif topology = 2
    # ---------------- Moorer 1979 ----------------
    # Six lowpass combs, one allpass, early reflections in front.
    if preset = 2
        presetName$ = "Classic"
        reverb_time_RT60_s = 2.0
        wet_dry_percent = 40
        comb_count = 6
        shortest_comb_ms = 50.0
        longest_comb_ms = 78.0
        allpass_count = 1
        allpass_gain = 0.7
        # Published Moorer reference: Table 2 + preferred 19-tap Table 3.
        moor_reference = 1
        damping = 0.50
        predelay_ms = 0
        er_count = 19
        er_first_ms = 0
        er_span_ms = 79.7
        er_level = 1.0
    elsif preset = 3
        presetName$ = "Small"
        reverb_time_RT60_s = 0.7
        wet_dry_percent = 25
        comb_count = 6
        shortest_comb_ms = 22.0
        longest_comb_ms = 38.0
        allpass_count = 1
        allpass_gain = 0.7
        damping = 0.50
        predelay_ms = 4
        er_count = 12
        er_first_ms = 4
        er_span_ms = 34
        er_level = 0.8
        stereo_spread_ms = 0.5
    elsif preset = 4
        presetName$ = "Medium"
        reverb_time_RT60_s = 2.2
        wet_dry_percent = 38
        comb_count = 6
        shortest_comb_ms = 50.0
        longest_comb_ms = 78.0
        allpass_count = 1
        allpass_gain = 0.7
        damping = 0.40
        predelay_ms = 15
        er_count = 18
        er_first_ms = 8
        er_span_ms = 80
        er_level = 0.7
        stereo_spread_ms = 1.1
    elsif preset = 5
        presetName$ = "Large"
        reverb_time_RT60_s = 4.5
        wet_dry_percent = 50
        comb_count = 6
        shortest_comb_ms = 68.0
        longest_comb_ms = 104.0
        allpass_count = 2
        allpass_gain = 0.72
        damping = 0.26
        predelay_ms = 32
        er_count = 22
        er_first_ms = 12
        er_span_ms = 130
        er_level = 0.6
        stereo_spread_ms = 1.6
    else
        presetName$ = "Custom"
        comb_count = 6
        shortest_comb_ms = 50.0
        longest_comb_ms = 78.0
        allpass_count = 1
        damping = 0.36
    endif
else
    # ---------------- Gardner 1992 ----------------
    # Figure 4.11 contains three DIFFERENT structures, not one scalable network.
    # Classic is retained as a convenient alias for the published Medium structure.
    if preset = 2
        presetName$ = "Classic"
        gardner_room = 2
        reverb_time_RT60_s = 1.00
        wet_dry_percent = 35
        gardner_lpf_hz = 2500
        predelay_ms = 0
        stereo_spread_ms = 0.8
    elsif preset = 3
        presetName$ = "Small"
        gardner_room = 1
        reverb_time_RT60_s = 0.48
        wet_dry_percent = 25
        gardner_lpf_hz = 4200
        predelay_ms = 0
        stereo_spread_ms = 0.5
    elsif preset = 4
        presetName$ = "Medium"
        gardner_room = 2
        reverb_time_RT60_s = 0.95
        wet_dry_percent = 35
        gardner_lpf_hz = 2500
        predelay_ms = 0
        stereo_spread_ms = 0.8
    elsif preset = 5
        presetName$ = "Large"
        gardner_room = 3
        reverb_time_RT60_s = 2.60
        wet_dry_percent = 45
        gardner_lpf_hz = 2600
        predelay_ms = 0
        stereo_spread_ms = 1.2
    else
        presetName$ = "Custom"
        # Custom Gardner chooses the published structure by requested RT range.
        if reverb_time_RT60_s <= 0.57
            gardner_room = 1
            gardner_lpf_hz = 4200
        elsif reverb_time_RT60_s <= 1.29
            gardner_room = 2
            gardner_lpf_hz = 2500
        else
            gardner_room = 3
            gardner_lpf_hz = 2600
        endif
    endif
endif

# ============================================================
# ADVANCED SETTINGS
# ============================================================
# Kept out of the main form so the form stays short. Under
# praat --run this block auto-continues with the values below.

if advanced_settings
    beginPause: "Historic Reverberators - advanced (" + topologyName$ + " / " + presetName$ + ")"
        comment: "Decay"
        positive: "Reverb time RT60 s", string$ (reverb_time_RT60_s)
        if topology < 3
            if topology = 2 and moor_reference = 1
                comment: "Moorer Classic uses the published per-comb one-pole coefficients from Table 2."
            else
                real: "Damping", string$ (damping)
                choice: "Damping mode", damping_mode
                    option: "One-pole lowpass in the loop"
                    option: "Two-tap FIR (legacy v0.2)"
            endif
        else
            comment: "Gardner uses the published feedback lowpass cutoff for the selected room structure."
        endif
        real: "Predelay ms", string$ (predelay_ms)
        real: "Stereo spread ms", string$ (stereo_spread_ms)
        if topology < 3
            comment: "Comb bank and allpass chain"
            natural: "Comb count", string$ (comb_count)
            positive: "Shortest comb ms", string$ (shortest_comb_ms)
            positive: "Longest comb ms", string$ (longest_comb_ms)
            integer: "Allpass count", string$ (allpass_count)
            positive: "Allpass gain", string$ (allpass_gain)
            boolean: "Wet contains direct sound", wet_contains_direct
        endif
        if topology = 2
            comment: "Early reflections"
            if moor_reference = 1
                comment: "Classic uses Moorer Table 2/3 values; controls below are informational."
            endif
            natural: "Er count", string$ (er_count)
            real: "Er first ms", string$ (er_first_ms)
            positive: "Er span ms", string$ (er_span_ms)
            positive: "Er level", string$ (er_level)
            positive: "Late level", string$ (late_level)
        endif
        if topology = 3
            comment: "Gardner Figure 4.11"
            if gardner_room = 1
                comment: "Published Small structure; recommended RT 0.38 - 0.57 s; LPF 4.2 kHz"
            elsif gardner_room = 2
                comment: "Published Medium structure; recommended RT 0.58 - 1.29 s; LPF 2.5 kHz"
            else
                comment: "Published Large structure; recommended RT >= 1.30 s; LPF 2.6 kHz"
            endif
            comment: "RT feedback gain is calibrated from the rendered impulse response."
        endif
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
if allpass_gain >= 0.95
    allpass_gain = 0.95
endif
if allpass_gain <= 0
    allpass_gain = 0.1
endif
if predelay_ms < 0
    predelay_ms = 0
endif
if stereo_spread_ms < 0
    stereo_spread_ms = 0
endif
if er_count < 2
    er_count = 2
endif
if er_first_ms < 0
    er_first_ms = 0
endif
if er_span_ms <= er_first_ms
    er_span_ms = er_first_ms + 20
endif

dampClamped = 0
if damping < 0
    damping = 0
    dampClamped = 1
endif
if damping_mode = 2
    if damping > 0.49
        damping = 0.49
        dampClamped = 1
    endif
else
    if damping > 0.95
        damping = 0.95
        dampClamped = 1
    endif
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

# Moorer sends the late field in behind the early reflection cluster.
lateOffset = 0
if topology = 2
    lateOffset = round (er_span_ms * sr / 1000)
endif

gardner_lpf_effective = gardner_lpf_hz
if topology = 3 and gardner_lpf_effective > 0.45 * sr
    gardner_lpf_effective = 0.45 * sr
endif

irN = preD + lateOffset + round (tail_s * sr) + 8
audN = round (originalDur * sr) + preD + lateOffset + round (tail_s * sr)

# ============================================================
# DELAY LINES
# ============================================================
# Delays are snapped to a PRIME number of samples so the recirculating
# paths share as few common echo instants as possible, and no two of
# them are allowed to land on the same length.

nEdc = 400

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

procedure nearestPrime: .n
    .offset = 0
    .found = 0
    while .found = 0
        .cand = .n - .offset
        if .cand >= 2
            .isPrime = 1
            .d = 2
            while .d * .d <= .cand
                if .isPrime = 1
                    if .cand mod .d = 0
                        .isPrime = 0
                    endif
                endif
                .d = .d + 1
            endwhile
            if .isPrime = 1
                .found = 1
                nearestPrime.result = .cand
            endif
        endif
        if .found = 0 and .offset > 0
            .cand = .n + .offset
            .isPrime = 1
            .d = 2
            while .d * .d <= .cand
                if .isPrime = 1
                    if .cand mod .d = 0
                        .isPrime = 0
                    endif
                endif
                .d = .d + 1
            endwhile
            if .isPrime = 1
                .found = 1
                nearestPrime.result = .cand
            endif
        endif
        .offset = .offset + 1
    endwhile
endproc

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

# Schroeder Classic uses a conventional later realization of the 30-45 ms
# range recommended in the 1962 paper. The paper itself does not prescribe
# one mandatory four-number table.
classicPos [1] = 0
classicPos [2] = 0.528571
classicPos [3] = 0.814286
classicPos [4] = 1

# Moorer Table 2: published six-comb delays and one-pole g1 values.
moorDelayMs [1] = 50
moorDelayMs [2] = 56
moorDelayMs [3] = 61
moorDelayMs [4] = 68
moorDelayMs [5] = 72
moorDelayMs [6] = 78
moorG1_25 [1] = 0.24
moorG1_25 [2] = 0.26
moorG1_25 [3] = 0.28
moorG1_25 [4] = 0.29
moorG1_25 [5] = 0.30
moorG1_25 [6] = 0.32
moorG1_50 [1] = 0.46
moorG1_50 [2] = 0.48
moorG1_50 [3] = 0.50
moorG1_50 [4] = 0.52
moorG1_50 [5] = 0.53
moorG1_50 [6] = 0.55

# Moorer explicitly recommends interpolation for intermediate sampling rates.
moorInterp = (sr - 25000) / 25000
if moorInterp < 0
    moorInterp = 0
endif
if moorInterp > 1
    moorInterp = 1
endif

spreadOffset = round (stereo_spread_ms * sr / 1000)

for ch from 1 to nWetCh
    nUsedDelays = 0
    if topology < 3
        for ci from 1 to comb_count
            if topology = 2 and moor_reference = 1 and ci <= 6
                delayMs = moorDelayMs [ci]
            elsif comb_count = 4
                pos = classicPos [ci]
                delayMs = shortest_comb_ms + (longest_comb_ms - shortest_comb_ms) * pos
            else
                pos = (ci - 1) / (comb_count - 1)
                delayMs = shortest_comb_ms + (longest_comb_ms - shortest_comb_ms) * pos
            endif
            rawD = round (delayMs * sr / 1000)
            if ch = 2
                rawD = rawD + spreadOffset
            endif
            if rawD < 8
                rawD = 8
            endif
            if topology = 2 and moor_reference = 1
                @nearestPrime: rawD
                combDelay [ch, ci] = nearestPrime.result
            else
                @freePrime: rawD
                combDelay [ch, ci] = freePrime.result
            endif
            if topology = 2 and moor_reference = 1
                # Moorer's reference design uses one common DC loop gain g for all
                # combs. The paper gives g ~= 1 - 0.366/T as a practical inverse
                # relation (about g=.83 for T=2 s with this delay set).
                g = 1 - 0.366 / reverb_time_RT60_s
                if g < 0.05
                    g = 0.05
                endif
                if g > 0.985
                    g = 0.985
                endif
                combGain [ch, ci] = g
                moorDamp [ci] = moorG1_25 [ci] + moorInterp * (moorG1_50 [ci] - moorG1_25 [ci])
            else
                # Creative variants retain the previous per-delay RT mapping so
                # changing their delay span does not invalidate the requested RT.
                g = 10 ^ (-3 * combDelay [ch, ci] / (reverb_time_RT60_s * sr))
                if g > 0.985
                    g = 0.985
                endif
                combGain [ch, ci] = g
                if topology = 2
                    moorDamp [ci] = damping
                endif
            endif
        endfor

        for ai from 1 to allpass_count
            if topology = 2
                apMs = 6.0 / (2.94 ^ (ai - 1))
            else
                apMs = 5.0 / (2.94 ^ (ai - 1))
            endif
            rawD = round (apMs * sr / 1000)
            if ch = 2
                rawD = rawD + round (spreadOffset / 2)
            endif
            if rawD < 4
                rawD = 4
            endif
            if topology = 2 and moor_reference = 1
                @nearestPrime: rawD
                apDelay [ch, ai] = nearestPrime.result
            else
                @freePrime: rawD
                apDelay [ch, ai] = freePrime.result
            endif
        endfor
    endif
endfor

# ============================================================
# EARLY REFLECTION PATTERN (Moorer)
# ============================================================
# Classic uses Moorer's preferred 19-tap Table 3 exactly (before sample
# quantisation). Other presets retain the deterministic parametric AudioTools
# pattern as creative variants. Table 3 is from an idealized geometric
# simulation of Boston Symphony Hall; it is not a measured hall IR.

if topology = 2
    if moor_reference = 1
        erTimeMs [1] = 0
        erTimeMs [2] = 4.3
        erTimeMs [3] = 21.5
        erTimeMs [4] = 22.5
        erTimeMs [5] = 26.8
        erTimeMs [6] = 27.0
        erTimeMs [7] = 29.8
        erTimeMs [8] = 45.8
        erTimeMs [9] = 48.5
        erTimeMs [10] = 57.2
        erTimeMs [11] = 58.7
        erTimeMs [12] = 59.5
        erTimeMs [13] = 61.2
        erTimeMs [14] = 70.7
        erTimeMs [15] = 70.8
        erTimeMs [16] = 72.6
        erTimeMs [17] = 74.1
        erTimeMs [18] = 75.3
        erTimeMs [19] = 79.7
        erGain [1] = 1.000
        erGain [2] = 0.841
        erGain [3] = 0.504
        erGain [4] = 0.491
        erGain [5] = 0.379
        erGain [6] = 0.380
        erGain [7] = 0.346
        erGain [8] = 0.289
        erGain [9] = 0.272
        erGain [10] = 0.192
        erGain [11] = 0.193
        erGain [12] = 0.217
        erGain [13] = 0.181
        erGain [14] = 0.180
        erGain [15] = 0.181
        erGain [16] = 0.176
        erGain [17] = 0.142
        erGain [18] = 0.167
        erGain [19] = 0.134
        er_count = 19
        er_span_ms = 79.7
        for k from 1 to er_count
            erDelay [k] = round (erTimeMs [k] * sr / 1000)
        endfor
    else
        erMaxGain = 0
        for k from 1 to er_count
            frac = (k - 1) / (er_count - 1)
            hashA = 0.5 * (1 + sin (k * 12.9898 + 4.1414))
            hashB = 0.5 * (1 + sin (k * 78.233 + 1.7231))
            tMs = er_first_ms + (er_span_ms - er_first_ms) * (frac ^ 1.35)
            tMs = tMs + 0.05 * (er_span_ms - er_first_ms) * (hashA - 0.5)
            if tMs < er_first_ms * 0.5
                tMs = er_first_ms * 0.5
            endif
            erTimeMs [k] = tMs
            gk = (0.95 - 0.72 * frac) * (0.55 + 0.75 * hashB)
            erGain [k] = gk
            if gk > erMaxGain
                erMaxGain = gk
            endif
        endfor
        for k from 1 to er_count
            erGain [k] = erGain [k] / erMaxGain
            erDelay [k] = round (erTimeMs [k] * sr / 1000)
            if erDelay [k] < 1
                erDelay [k] = 1
            endif
        endfor
    endif
endif

# ============================================================
# FORMULA TEMPLATES
# ============================================================
# One static string each; the globals they read are set immediately
# before every call. Avoids building formula strings in loops.

combFirF$ = "if col > combD then self + combG * ((1 - combDamp) * self [1, col - combD] + combDamp * self [1, col - combD + 1]) else self fi"

combOnePoleF$ = "self + (if col > 1 then combDamp * (self [1, col - 1] - object [combSrc, 1, col - 1]) else 0 fi) + (if col > combD then combG * (1 - combDamp) * self [1, col - combD] else 0 fi)"

allpassF$ = "if col > apD then -apG * self + object [apIn, 1, col - apD] + apG * self [1, col - apD] else -apG * self fi"

nestedF$ = "-napGB * object [napSrc, 1, col] + (if col > napDA then napGA * napGB * object [napSrc, 1, col - napDA] + napGA * self [1, col - napDA] else 0 fi) + (if col > napDB then -napGA * object [napSrc, 1, col - napDB] - napGA * napGB * self [1, col - napDB] else 0 fi) + (if col > napDA + napDB then object [napSrc, 1, col - napDA - napDB] + napGB * self [1, col - napDA - napDB] else 0 fi)"

lowpassF$ = "(if col > loopD then (1 - combDamp) * object [napA2, 1, col - loopD] else 0 fi) + (if col > 1 then combDamp * self [1, col - 1] else 0 fi)"

# Double-nested allpass. dnD0 is the residual outer delay; dnD1/dnD2 are
# the two inner allpass delays. dnG0 is outer gain, dnG1/dnG2 inner gains.
doubleNestedF$ = "-dnG0 * object [dnSrc, 1, col] + (if col > dnD1 then dnG0*dnG1*object [dnSrc,1,col-dnD1] + dnG1*self [1,col-dnD1] else 0 fi) + (if col > dnD2 then dnG0*dnG2*object [dnSrc,1,col-dnD2] + dnG2*self [1,col-dnD2] else 0 fi) + (if col > dnD1+dnD2 then -dnG0*dnG1*dnG2*object [dnSrc,1,col-dnD1-dnD2] - dnG1*dnG2*self [1,col-dnD1-dnD2] else 0 fi) + (if col > dnD0 then dnG1*dnG2*object [dnSrc,1,col-dnD0] + dnG0*dnG1*dnG2*self [1,col-dnD0] else 0 fi) + (if col > dnD0+dnD1 then -dnG2*object [dnSrc,1,col-dnD0-dnD1] - dnG0*dnG2*self [1,col-dnD0-dnD1] else 0 fi) + (if col > dnD0+dnD2 then -dnG1*object [dnSrc,1,col-dnD0-dnD2] - dnG0*dnG1*self [1,col-dnD0-dnD2] else 0 fi) + (if col > dnD0+dnD1+dnD2 then object [dnSrc,1,col-dnD0-dnD1-dnD2] + dnG0*self [1,col-dnD0-dnD1-dnD2] else 0 fi)"

# ============================================================
# GARDNER NETWORK - published Figure 4.11 structures
# ============================================================
# The published diagrams specify the allpass structures and lowpass cutoffs but
# not a numerical RT-to-feedback table. We therefore preserve those structures
# and solve only the outer feedback gain against the rendered impulse response.
# A pure delay that already exists in each published loop is used as the block
# boundary, so no extra loop delay is invented.

procedure gardnerNet
    # Right-channel timing variation is an AudioTools spatial extension. The
    # left channel is the published timing; R offsets only the pure boundary
    # and simple delay sections by the requested small spread.
    if ch = 2
        gSpread = round (stereo_spread_ms * sr / 1000)
    else
        gSpread = 0
    endif

    # Shared buffers.
    Create Sound from formula: "g_state", 1, 0, netDur, sr, "0"
    gState = selected ("Sound")
    Create Sound from formula: "g_fb", 1, 0, netDur, sr, "0"
    gFb = selected ("Sound")
    Create Sound from formula: "g_mix", 1, 0, netDur, sr, "0"
    gMix = selected ("Sound")
    Create Sound from formula: "g_out", 1, 0, netDur, sr, "0"
    gOut = selected ("Sound")

    # Exact one-pole coefficient whose magnitude is -3 dB at the published
    # Gardner lowpass cutoff (clamped below Nyquist for low-rate material).
    .fc = gardner_lpf_effective
    .omega = 2 * pi * .fc / sr
    .u = 2 - cos (.omega)
    gardnerAlpha = .u - sqrt (.u * .u - 1)

    if gardner_room = 1
        # SMALL, Figure 4.11:
        # 24 ms -> double nested AP 35(.3){22(.4),8.3(.6)}
        #       -> single nested AP 66(.1){30(.4)}; taps .5/.5; LPF 4.2 kHz.
        bD = round (24.0 * sr / 1000) + gSpread
        if bD < 1
            bD = 1
        endif
        Create Sound from formula: "g_dn1", 1, 0, netDur, sr, "0"
        gDN1 = selected ("Sound")
        Create Sound from formula: "g_sn2", 1, 0, netDur, sr, "0"
        gSN2 = selected ("Sound")

        # A block no longer than the smallest residual delay (4.7 ms).
        blockD = max (1, floor (4.5 * sr / 1000))
        .nBlocks = ceiling (netN / blockD)
        for .b from 0 to .nBlocks - 1
            bt1 = .b * blockD / sr
            bt2 = (.b + 1) * blockD / sr
            if bt2 > netDur
                bt2 = netDur
            endif

            # Published double-nested 35 ms outer: residual 35-22-8.3 = 4.7 ms.
            selectObject: gDN1
            dnSrc = gState
            dnD0 = round (4.7 * sr / 1000)
            dnD1 = round (22.0 * sr / 1000)
            dnD2 = round (8.3 * sr / 1000)
            dnG0 = 0.3
            dnG1 = 0.4
            dnG2 = 0.6
            Formula (part): bt1, bt2, 1, 1, doubleNestedF$

            # Published single-nested 66 ms outer containing 30 ms inner.
            selectObject: gSN2
            napSrc = gDN1
            napDA = round (30.0 * sr / 1000)
            napDB = round (36.0 * sr / 1000)
            napGA = 0.4
            napGB = 0.1
            Formula (part): bt1, bt2, 1, 1, nestedF$

            # Feedback lowpass from the end of the published network.
            selectObject: gFb
            fbSrc = gSN2
            Formula (part): bt1, bt2, 1, 1, "(1-gardnerAlpha)*object [fbSrc,1,col] + (if col > 1 then gardnerAlpha*self [1,col-1] else 0 fi)"

            # Input summing node; write through the published 24 ms delay into
            # the future state buffer (this is the block boundary).
            selectObject: gMix
            Formula (part): bt1, bt2, 1, 1, "object [netSrc,1,col] + gK*object [gFb,1,col]"
            ft1 = bt1 + bD / sr
            ft2 = bt2 + bD / sr
            if ft1 < netDur
                if ft2 > netDur
                    ft2 = netDur
                endif
                selectObject: gState
                Formula (part): ft1, ft2, 1, 1, "object [gMix,1,col-bD]"
            endif

            selectObject: gOut
            Formula (part): bt1, bt2, 1, 1, "0.5*object [gDN1,1,col] + 0.5*object [gSN2,1,col]"
        endfor
        gnResult = gOut
        removeObject: gState, gFb, gMix, gDN1, gSN2

    elsif gardner_room = 2
        # MEDIUM, Figure 4.11:
        # DNAP 35(.3){8.3(.7),22(.5)} -> 5 -> AP30(.5) -> 67 [tap]
        # -> 15 + input -> NAP39(.3){9.8(.6)} -> 108 -> LPF 2.5 kHz.
        bD = round (5.0 * sr / 1000) + gSpread
        if bD < 1
            bD = 1
        endif
        Create Sound from formula: "g_dn1", 1, 0, netDur, sr, "0"
        gDN1 = selected ("Sound")
        Create Sound from formula: "g_ap30", 1, 0, netDur, sr, "0"
        gAP30 = selected ("Sound")
        Create Sound from formula: "g_d67", 1, 0, netDur, sr, "0"
        gD67 = selected ("Sound")
        Create Sound from formula: "g_d15", 1, 0, netDur, sr, "0"
        gD15 = selected ("Sound")
        Create Sound from formula: "g_mix2", 1, 0, netDur, sr, "0"
        gMix2 = selected ("Sound")
        Create Sound from formula: "g_sn", 1, 0, netDur, sr, "0"
        gSN = selected ("Sound")
        Create Sound from formula: "g_d108", 1, 0, netDur, sr, "0"
        gD108 = selected ("Sound")

        d67 = round (67.0 * sr / 1000) + gSpread
        d15 = round (15.0 * sr / 1000) + gSpread
        d108 = round (108.0 * sr / 1000) + gSpread
        blockD = max (1, floor (4.5 * sr / 1000))
        .nBlocks = ceiling (netN / blockD)
        for .b from 0 to .nBlocks - 1
            bt1 = .b * blockD / sr
            bt2 = (.b + 1) * blockD / sr
            if bt2 > netDur
                bt2 = netDur
            endif

            # Downstream path is known from the previously-filled 5 ms state.
            selectObject: gAP30
            apIn = gState
            apD = round (30.0 * sr / 1000)
            apG = 0.5
            Formula (part): bt1, bt2, 1, 1, allpassF$
            selectObject: gD67
            Formula (part): bt1, bt2, 1, 1, "if col > d67 then object [gAP30,1,col-d67] else 0 fi"
            selectObject: gD15
            Formula (part): bt1, bt2, 1, 1, "if col > d15 then object [gD67,1,col-d15] else 0 fi"
            selectObject: gMix2
            Formula (part): bt1, bt2, 1, 1, "object [netSrc,1,col] + object [gD15,1,col]"
            selectObject: gSN
            napSrc = gMix2
            napDA = round (9.8 * sr / 1000)
            napDB = round (29.2 * sr / 1000)
            napGA = 0.6
            napGB = 0.3
            Formula (part): bt1, bt2, 1, 1, nestedF$
            selectObject: gD108
            Formula (part): bt1, bt2, 1, 1, "if col > d108 then object [gSN,1,col-d108] else 0 fi"
            selectObject: gFb
            fbSrc = gD108
            Formula (part): bt1, bt2, 1, 1, "(1-gardnerAlpha)*object [fbSrc,1,col] + (if col > 1 then gardnerAlpha*self [1,col-1] else 0 fi)"

            # First published section receives input + outer feedback.
            selectObject: gMix
            Formula (part): bt1, bt2, 1, 1, "object [netSrc,1,col] + gK*object [gFb,1,col]"
            selectObject: gDN1
            dnSrc = gMix
            dnD0 = round (4.7 * sr / 1000)
            dnD1 = round (8.3 * sr / 1000)
            dnD2 = round (22.0 * sr / 1000)
            dnG0 = 0.3
            dnG1 = 0.7
            dnG2 = 0.5
            Formula (part): bt1, bt2, 1, 1, doubleNestedF$
            ft1 = bt1 + bD / sr
            ft2 = bt2 + bD / sr
            if ft1 < netDur
                if ft2 > netDur
                    ft2 = netDur
                endif
                selectObject: gState
                Formula (part): ft1, ft2, 1, 1, "object [gDN1,1,col-bD]"
            endif

            selectObject: gOut
            Formula (part): bt1, bt2, 1, 1, "0.5*object [gDN1,1,col] + 0.5*object [gD67,1,col] + 0.5*object [gSN,1,col]"
        endfor
        gnResult = gOut
        removeObject: gState, gFb, gMix, gDN1, gAP30, gD67, gD15, gMix2, gSN, gD108

    else
        # LARGE, Figure 4.11:
        # AP8(.3)->AP12(.3) [tap .34] ->4->17 -> NAP87(.5){62(.25)}
        # ->31 [tap .14] ->3 -> DNAP120(.5){76(.25),30(.25)} [tap .14]
        # -> LPF 2.6 kHz.
        bD = round (4.0 * sr / 1000) + gSpread
        if bD < 1
            bD = 1
        endif
        Create Sound from formula: "g_ap8", 1, 0, netDur, sr, "0"
        gAP8 = selected ("Sound")
        Create Sound from formula: "g_ap12", 1, 0, netDur, sr, "0"
        gAP12 = selected ("Sound")
        Create Sound from formula: "g_d17", 1, 0, netDur, sr, "0"
        gD17 = selected ("Sound")
        Create Sound from formula: "g_sn87", 1, 0, netDur, sr, "0"
        gSN87 = selected ("Sound")
        Create Sound from formula: "g_d31", 1, 0, netDur, sr, "0"
        gD31 = selected ("Sound")
        Create Sound from formula: "g_d3", 1, 0, netDur, sr, "0"
        gD3 = selected ("Sound")
        Create Sound from formula: "g_dn120", 1, 0, netDur, sr, "0"
        gDN120 = selected ("Sound")

        d17 = round (17.0 * sr / 1000) + gSpread
        d31 = round (31.0 * sr / 1000) + gSpread
        d3 = round (3.0 * sr / 1000) + gSpread
        blockD = max (1, floor (3.5 * sr / 1000))
        .nBlocks = ceiling (netN / blockD)
        for .b from 0 to .nBlocks - 1
            bt1 = .b * blockD / sr
            bt2 = (.b + 1) * blockD / sr
            if bt2 > netDur
                bt2 = netDur
            endif

            # Downstream from the published 4 ms boundary.
            selectObject: gD17
            Formula (part): bt1, bt2, 1, 1, "if col > d17 then object [gState,1,col-d17] else 0 fi"
            selectObject: gSN87
            napSrc = gD17
            napDA = round (62.0 * sr / 1000)
            napDB = round (25.0 * sr / 1000)
            napGA = 0.25
            napGB = 0.5
            Formula (part): bt1, bt2, 1, 1, nestedF$
            selectObject: gD31
            Formula (part): bt1, bt2, 1, 1, "if col > d31 then object [gSN87,1,col-d31] else 0 fi"
            selectObject: gD3
            Formula (part): bt1, bt2, 1, 1, "if col > d3 then object [gD31,1,col-d3] else 0 fi"
            selectObject: gDN120
            dnSrc = gD3
            dnD0 = round (14.0 * sr / 1000)
            dnD1 = round (76.0 * sr / 1000)
            dnD2 = round (30.0 * sr / 1000)
            dnG0 = 0.5
            dnG1 = 0.25
            dnG2 = 0.25
            Formula (part): bt1, bt2, 1, 1, doubleNestedF$
            selectObject: gFb
            fbSrc = gDN120
            Formula (part): bt1, bt2, 1, 1, "(1-gardnerAlpha)*object [fbSrc,1,col] + (if col > 1 then gardnerAlpha*self [1,col-1] else 0 fi)"

            # Input + feedback through the two published allpasses.
            selectObject: gMix
            Formula (part): bt1, bt2, 1, 1, "object [netSrc,1,col] + gK*object [gFb,1,col]"
            selectObject: gAP8
            apIn = gMix
            apD = round (8.0 * sr / 1000)
            apG = 0.3
            Formula (part): bt1, bt2, 1, 1, allpassF$
            selectObject: gAP12
            apIn = gAP8
            apD = round (12.0 * sr / 1000)
            apG = 0.3
            Formula (part): bt1, bt2, 1, 1, allpassF$
            ft1 = bt1 + bD / sr
            ft2 = bt2 + bD / sr
            if ft1 < netDur
                if ft2 > netDur
                    ft2 = netDur
                endif
                selectObject: gState
                Formula (part): ft1, ft2, 1, 1, "object [gAP12,1,col-bD]"
            endif

            selectObject: gOut
            Formula (part): bt1, bt2, 1, 1, "0.34*object [gAP12,1,col] + 0.14*object [gD31,1,col] + 0.14*object [gDN120,1,col]"
        endfor
        gnResult = gOut
        removeObject: gState, gFb, gMix, gAP8, gAP12, gD17, gSN87, gD31, gD3, gDN120
    endif
endproc

# ============================================================
# DECAY MEASUREMENT (Schroeder backward integration + ISO 3382 fit)
# ============================================================

procedure measureDecay: .sid
    selectObject: .sid
    irDur = Get total duration
    totalEnergy = Get energy: 0, irDur
    edcValid = 0
    if totalEnergy > 0
        edcValid = 1
        for .k from 1 to nEdc
            tEdc = (.k - 1) * irDur / nEdc
            eTail = Get energy: tEdc, irDur
            edcT [.k] = tEdc
            if eTail > 0
                edcDb [.k] = 10 * log10 (eTail / totalEnergy)
            else
                edcDb [.k] = -120
            endif
        endfor
    endif

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
endproc

# ============================================================
# REPORT (parameters)
# ============================================================

writeInfoLine: "=== Historic Reverberators: ", topologyLong$, " ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$ (originalDur, 2), " s, ", numChannels, " ch, ", sr, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "RT60 requested: ", fixed$ (reverb_time_RT60_s, 2), " s"
if topology = 3
    appendInfoLine: "Feedback lowpass: ", fixed$ (gardner_lpf_effective, 0), " Hz"
    if gardner_lpf_effective = gardner_lpf_hz
        appendInfoLine: "  published Figure 4.11 cutoff"
    else
        appendInfoLine: "  published cutoff ", fixed$ (gardner_lpf_hz, 0), " Hz clamped below Nyquist for this sample rate"
    endif
elsif topology = 2 and moor_reference = 1
    if sr < 25000
        appendInfoLine: "Damping: Moorer Table 2 per-comb coefficients (25 kHz endpoint; source table begins at 25 kHz)"
    elsif sr > 50000
        appendInfoLine: "Damping: Moorer Table 2 per-comb coefficients (50 kHz endpoint)"
    else
        appendInfoLine: "Damping: Moorer Table 2 per-comb coefficients (linear 25/50 kHz interpolation)"
    endif
elsif damping_mode = 1
    appendInfoLine: "Damping: ", fixed$ (damping, 3), " (one-pole in the feedback loop)"
else
    appendInfoLine: "Damping: ", fixed$ (damping, 3), " (two-tap FIR, legacy v0.2)"
endif
appendInfoLine: "Predelay: ", fixed$ (predelay_ms, 1), " ms  |  Tail: ", fixed$ (tail_s, 2), " s"
appendInfoLine: "Wet/Dry: ", fixed$ (wet_dry_percent, 1), " %"
appendInfoLine: ""

if topology < 3
    appendInfoLine: "Comb bank (left):"
    for ci from 1 to comb_count
        if topology = 2
            appendInfoLine: "  C", ci, ": ", combDelay [1, ci], " samples (", fixed$ (combDelay [1, ci] * 1000 / sr, 2), " ms), g=", fixed$ (combGain [1, ci], 4), ", g1=", fixed$ (moorDamp [ci], 3)
        else
            appendInfoLine: "  C", ci, ": ", combDelay [1, ci], " samples (", fixed$ (combDelay [1, ci] * 1000 / sr, 2), " ms), g=", fixed$ (combGain [1, ci], 4)
        endif
    endfor
    if allpass_count > 0
        appendInfoLine: "Allpass chain (left):"
        for ai from 1 to allpass_count
            appendInfoLine: "  A", ai, ": ", apDelay [1, ai], " samples (", fixed$ (apDelay [1, ai] * 1000 / sr, 2), " ms), g=", fixed$ (allpass_gain, 3)
        endfor
    endif
else
    appendInfoLine: "Gardner Figure 4.11 reference network (left):"
    if gardner_room = 1
        appendInfoLine: "  Small: 24 -> DNAP 35(.3){22(.4),8.3(.6)} -> NAP 66(.1){30(.4)} ms"
        appendInfoLine: "  output taps 0.5 / 0.5; feedback LPF 4.2 kHz"
    elsif gardner_room = 2
        appendInfoLine: "  Medium: DNAP 35(.3){8.3(.7),22(.5)} -> 5 -> AP30(.5) -> 67 -> 15 + input"
        appendInfoLine: "          -> NAP39(.3){9.8(.6)} -> 108 ms; taps 0.5 / 0.5 / 0.5; LPF 2.5 kHz"
    else
        appendInfoLine: "  Large: AP8(.3) -> AP12(.3) -> 4 -> 17 -> NAP87(.5){62(.25)} -> 31 -> 3"
        appendInfoLine: "         -> DNAP120(.5){76(.25),30(.25)} ms; taps .34 / .14 / .14; LPF 2.6 kHz"
    endif
endif

if topology = 2
    appendInfoLine: "Early reflections: ", er_count, " taps over ", fixed$ (er_first_ms, 1), " - ", fixed$ (er_span_ms, 1), " ms, level ", fixed$ (er_level, 2)
    if moor_reference = 1
        appendInfoLine: "  published 19-tap Table 3 reference; idealized Boston Symphony Hall geometry"
    else
        appendInfoLine: "  AudioTools parametric creative pattern"
    endif
endif
appendInfoLine: ""

# ============================================================
# LOOP GAIN CALIBRATION (Gardner)
# ============================================================
# Gardner states that RT->feedback gain was obtained by interpolation between
# measured data, but the thesis does not publish that numerical mapping. We do
# not invent it: the published network is held fixed and only g is solved by
# bisection against the network's own rendered T30/T20 decay.

calibIters = 0
calibError = 0
gardnerGain = 0
if topology = 3
    appendInfoLine: "Calibrating Gardner feedback gain against the rendered reference network..."
    loG = 0
    hiG = 0.995
    bestG = 0.5
    bestErr = 1e9
    ch = 1
    netN = irN
    netDur = netN / sr
    for iter from 1 to 8
        testG = 0.5 * (loG + hiG)
        gK = testG
        Create Sound from formula: "cal_src", 1, 0, netDur, sr, "if col = preD + 1 then 1 else 0 fi"
        netSrc = selected ("Sound")
        @gardnerNet
        @measureDecay: gnResult
        removeObject: gnResult, netSrc
        calibIters = iter
        if rt60_measured > 0
            calibError = 100 * (rt60_measured - reverb_time_RT60_s) / reverb_time_RT60_s
            appendInfoLine: "  pass ", iter, ": g=", fixed$ (testG, 5), " -> ", fixed$ (rt60_measured, 3), " s (", fixed$ (calibError, 1), " percent)"
            if abs (calibError) < abs (bestErr)
                bestErr = calibError
                bestG = testG
            endif
            if rt60_measured < reverb_time_RT60_s
                loG = testG
            else
                hiG = testG
            endif
        else
            loG = testG
        endif
    endfor
    gardnerGain = bestG
    calibError = bestErr
    appendInfoLine: "  calibrated feedback gain: ", fixed$ (gardnerGain, 5)
    appendInfoLine: "  (network values are published; only RT-to-g is numerically solved here)"
    appendInfoLine: ""
endif

appendInfoLine: "Rendering..."

# ============================================================
# MONO SEND
# ============================================================

selectObject: workSource
if numChannels > 1
    sendMono = Convert to mono
else
    sendMono = Copy: "reverb_send"
endif

# ============================================================
# NETWORK
# ============================================================
# pass 1 renders the impulse response (figure, decay measurement and
# the wet gain); pass 2 renders the audio. Identical code.

for pass from 1 to 2
    if pass = 1
        netN = irN
    else
        netN = audN
    endif
    netDur = netN / sr

    for ch from 1 to nWetCh

        # ---- dry send into the network, predelay applied here ----
        if pass = 1
            Create Sound from formula: "net_src", 1, 0, netDur, sr, "if col = preD + 1 then 1 else 0 fi"
        else
            Create Sound from formula: "net_src", 1, 0, netDur, sr, "0"
            Formula: "if col <= preD then 0 else if col - preD <= nSrc then object [sendMono, 1, col - preD] else 0 fi fi"
        endif
        netSrc = selected ("Sound")

        if topology < 3
            # ================= comb bank + allpass chain =================

            # Moorer Figure 12: build the complete early FIR response first.
            if topology = 2
                Create Sound from formula: "early_src", 1, 0, netDur, sr, "0"
                earlySrc = selected ("Sound")
                for k from 1 to er_count
                    erD = erDelay [k]
                    erG = erGain [k]
                    selectObject: earlySrc
                    Formula: "self + (if col > erD then erG*object [netSrc,1,col-erD] else if erD = 0 then erG*object [netSrc,1,col] else 0 fi fi)"
                endfor
                # D1/D2 alignment: delay the recirculating branch so its first
                # contribution reaches the end of the early-reflection cluster.
                Create Sound from formula: "late_src", 1, 0, netDur, sr, "0"
                lateSrc = selected ("Sound")
                Formula: "if col > lateOffset then object [earlySrc,1,col-lateOffset] else 0 fi"
            else
                earlySrc = 0
                lateSrc = netSrc
            endif

            for ci from 1 to comb_count
                selectObject: lateSrc
                combTmp = Copy: "comb_tmp"
                combD = combDelay [ch, ci]
                combG = combGain [ch, ci]
                combSrc = lateSrc
                if topology = 2
                    combDamp = moorDamp [ci]
                else
                    combDamp = damping
                endif
                if topology = 2 and moor_reference = 1
                    Formula: combOnePoleF$
                elsif damping_mode = 1
                    Formula: combOnePoleF$
                else
                    Formula: combFirF$
                endif
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
                # Every comb passes x[n] through undelayed, so the bank
                # carries comb_count copies of the direct sound.
                Formula: "self - comb_count * object [lateSrc, 1, col]"
            endif
            Formula: "self / comb_count"

            for ai from 1 to allpass_count
                selectObject: netAcc
                apIn = Copy: "ap_in"
                apD = apDelay [ch, ai]
                apG = allpass_gain
                selectObject: netAcc
                Formula: allpassF$
                removeObject: apIn
            endfor

            if topology = 2
                selectObject: netAcc
                Formula: "self * late_level + er_level*object [earlySrc,1,col]"
                removeObject: lateSrc, earlySrc
            endif

        else
            # ================= Gardner Figure 4.11 network =================
            gK = gardnerGain
            @gardnerNet
            netAcc = gnResult
        endif

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
        # The impulse response IS the measurement: its summed square is
        # the network's energy gain, so the wet path is scaled by the
        # inverse square root of it. One shared gain for both channels,
        # so the stereo balance survives.
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

@measureDecay: irId [1]

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

Create Sound from formula: "dry_draw", numChannels, 0, audDur, sr, "0"
dryDraw = selected ("Sound")
Formula: "if col <= nSrc then object [workSource, row, col] else 0 fi"

# Mono output averages every source channel; stereo output takes L and R
# from a 2-channel source and splits a wider input odd/even.
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

Rename: originalName$ + "_" + topologyName$ + "_" + presetName$

removeObject: workSource

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    labelX = -0.035
    labelFont = 7
    titleName$ = replace$ (originalName$, "_", "\_ ", 0)

    # ---- geometry: the panel stack grows with what there is to show ----
    if topology = 2
        erTop = 5.6
        erBot = 6.3
        netTop = 6.9
    else
        erTop = 0
        erBot = 0
        netTop = 5.6
    endif
    if topology = 3
        netH = 1.45
    else
        nRows = comb_count + allpass_count
        netH = 1.0
        if nRows > 9
            netH = 0.115 * nRows
        endif
    endif
    netBot = netTop + netH
    parTop = netBot + 0.45
    sumTop = netBot + 0.95
    canvasH = netBot + 2.05

    # ---- title ----
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##" + topologyLong$ + "##  " + titleName$ + " (" + presetName$ + ")" + " | v0.4"

    # ---- dry ----
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

    # ---- result ----
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

    # ---- impulse response ----
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
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    if preD > 0
        Draw line: preD / sr, -irRange, preD / sr, irRange
    endif
    if lateOffset > 0
        Draw line: (preD + lateOffset) / sr, -irRange, (preD + lateOffset) / sr, irRange
    endif
    Solid line

    Select inner viewport: 0.60, 7.70, 2.8, 3.7
    Axes: 0, irDur, -irRange, irRange
    Font size: 6
    if preD > 0
        Colour: "{0.45, 0.45, 0.45}"
        Text: preD / sr, "left", irRange * 0.84, "half", " predelay"
    endif
    Select inner viewport: 0.60, 7.70, 2.8, 3.7
    Axes: 0, irDur, -irRange, irRange
    if lateOffset > 0
        Colour: "{0.45, 0.45, 0.45}"
        Text: (preD + lateOffset) / sr, "left", irRange * 0.62, "half", " late field enters"
    endif

    Select inner viewport: 0.60, 7.70, 2.8, 3.7
    Axes: 0, irDur, -irRange, irRange
    Colour: "{0.20, 0.40, 0.80}"
    Text: irDur * 0.985, "right", -irRange * 0.62, "half", "L"
    if nWetCh = 2
        Select inner viewport: 0.60, 7.70, 2.8, 3.7
        Axes: 0, irDur, -irRange, irRange
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

    # ---- energy decay curve ----
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
    Select inner viewport: 0.60, 7.70, 4.0, 5.0
    Axes: 0, irDur, -80, 2
    Colour: "{0.45, 0.45, 0.45}"
    Text: irDur * 0.985, "right", -16, "half", "requested " + fixed$ (reverb_time_RT60_s, 2) + " s"
    Select inner viewport: 0.60, 7.70, 4.0, 5.0
    Axes: 0, irDur, -80, 2
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

    # ---- early reflection tap bank (Moorer only) ----
    if topology = 2
        Font size: 7
        Select outer viewport: 0, 8, erTop - 0.1, erBot + 0.1
        Select inner viewport: 0.60, 7.70, erTop, erBot
        erXmax = er_span_ms * 1.08
        Axes: 0, erXmax, 0, 1.15
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, erXmax, 0, 1.15

        Select inner viewport: 0.60, 7.70, erTop, erBot
        Axes: 0, erXmax, 0, 1.15
        Line width: 1.5
        for k from 1 to er_count
            tk = erDelay [k] * 1000 / sr
            gk = erGain [k]
            shade = 0.25 + 0.45 * (1 - gk)
            Colour: "{" + fixed$ (shade, 2) + ", " + fixed$ (shade * 0.9 + 0.15, 2) + ", " + fixed$ (0.70, 2) + "}"
            Draw line: tk, 0, tk, gk
        endfor
        Line width: 1
        for k from 1 to er_count
            tk = erDelay [k] * 1000 / sr
            gk = erGain [k]
            Select inner viewport: 0.60, 7.70, erTop, erBot
            Axes: 0, erXmax, 0, 1.15
            Paint circle (mm): "{0.30, 0.35, 0.70}", tk, gk, 0.8
        endfor

        Select inner viewport: 0.60, 7.70, erTop, erBot
        Axes: 0, erXmax, 0, 1.15
        Font size: 6
        Colour: "{0.35, 0.35, 0.50}"
        if moor_reference = 1
            erCaption$ = string$ (er_count) + " published Table 3 taps"
        else
            erCaption$ = string$ (er_count) + " AudioTools parametric taps"
        endif
        Text: erXmax * 0.985, "right", 1.05, "half", erCaption$

        Select inner viewport: 0.60, 7.70, erTop, erBot
        Axes: 0, erXmax, 0, 1.15
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.20, 0.48, erTop, erBot
        Axes: 0, 1, 0, 1
        Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Early refl."
        Select inner viewport: 0.60, 7.70, erTop, erBot
        Axes: 0, erXmax, 0, 1.15
        Text bottom: "yes", "Reflection time (ms)"
    endif

    # ---- topology panel ----
    Font size: 7
    Select outer viewport: 0, 8, netTop - 0.1, netBot + 0.1
    Select inner viewport: 0.60, 7.70, netTop, netBot

    if topology < 3
        # delay map of the comb bank and the allpass chain
        maxRowDelay = 0
        for ci from 1 to comb_count
            if combDelay [1, ci] * 1000 / sr > maxRowDelay
                maxRowDelay = combDelay [1, ci] * 1000 / sr
            endif
        endfor
        xMax = maxRowDelay * 1.78
        Axes: 0, xMax, nRows + 1, 0
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, xMax, nRows + 1, 0

        Select inner viewport: 0.60, 7.70, netTop, netBot
        Axes: 0, xMax, nRows + 1, 0
        Line width: 2
        for ci from 1 to comb_count
            dMs = combDelay [1, ci] * 1000 / sr
            Colour: "{0.30, 0.45, 0.70}"
            Draw line: 0, ci, dMs, ci
        endfor
        for ai from 1 to allpass_count
            dMs = apDelay [1, ai] * 1000 / sr
            Colour: "{0.85, 0.45, 0.10}"
            Draw line: 0, comb_count + ai, dMs, comb_count + ai
        endfor
        Line width: 1

        Font size: 6
        if nRows <= 8
            showSamples = 1
        else
            showSamples = 0
        endif
        for ci from 1 to comb_count
            dMs = combDelay [1, ci] * 1000 / sr
            Select inner viewport: 0.60, 7.70, netTop, netBot
            Axes: 0, xMax, nRows + 1, 0
            Paint circle (mm): "{0.30, 0.45, 0.70}", dMs, ci, 0.9
            rowLabel$ = "  C" + string$ (ci) + "  " + fixed$ (dMs, 1) + " ms   g=" + fixed$ (combGain [1, ci], 3)
            if showSamples = 1
                rowLabel$ = rowLabel$ + "   " + string$ (combDelay [1, ci]) + " smp"
            endif
            Select inner viewport: 0.60, 7.70, netTop, netBot
            Axes: 0, xMax, nRows + 1, 0
            Colour: "{0.25, 0.25, 0.30}"
            Text: dMs, "left", ci, "half", rowLabel$
        endfor
        for ai from 1 to allpass_count
            dMs = apDelay [1, ai] * 1000 / sr
            Select inner viewport: 0.60, 7.70, netTop, netBot
            Axes: 0, xMax, nRows + 1, 0
            Paint circle (mm): "{0.85, 0.45, 0.10}", dMs, comb_count + ai, 0.9
            rowLabel$ = "  A" + string$ (ai) + "  " + fixed$ (dMs, 2) + " ms   g=" + fixed$ (allpass_gain, 3)
            if showSamples = 1
                rowLabel$ = rowLabel$ + "   " + string$ (apDelay [1, ai]) + " smp"
            endif
            Select inner viewport: 0.60, 7.70, netTop, netBot
            Axes: 0, xMax, nRows + 1, 0
            Colour: "{0.25, 0.25, 0.30}"
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
    else
        Axes: 0, 100, 0, 100
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 100, 0, 100
        Font size: 7
        Colour: "{0.20, 0.25, 0.35}"
        if gardner_room = 1
            Text: 50, "centre", 72, "half", "##Gardner Small - Figure 4.11##"
            Font size: 6
            Text: 50, "centre", 54, "half", "24 -> DNAP 35(.3){22(.4), 8.3(.6)} -> NAP 66(.1){30(.4)} ms"
            Text: 50, "centre", 36, "half", "output taps 0.5 / 0.5   |   feedback LPF 4.2 kHz"
            Text: 50, "centre", 19, "half", "published RT range 0.38-0.57 s   |   calibrated g=" + fixed$ (gardnerGain, 4)
        elsif gardner_room = 2
            Text: 50, "centre", 72, "half", "##Gardner Medium - Figure 4.11##"
            Font size: 6
            Text: 50, "centre", 54, "half", "DNAP35 -> 5 -> AP30 -> 67 -> 15 + input -> NAP39 -> 108 ms"
            Text: 50, "centre", 36, "half", "taps 0.5 / 0.5 / 0.5   |   feedback LPF 2.5 kHz"
            Text: 50, "centre", 19, "half", "published RT range 0.58-1.29 s   |   calibrated g=" + fixed$ (gardnerGain, 4)
        else
            Text: 50, "centre", 72, "half", "##Gardner Large - Figure 4.11##"
            Font size: 6
            Text: 50, "centre", 54, "half", "AP8 -> AP12 -> 4 -> 17 -> NAP87 -> 31 -> 3 -> DNAP120 ms"
            Text: 50, "centre", 36, "half", "taps 0.34 / 0.14 / 0.14   |   feedback LPF 2.6 kHz"
            Text: 50, "centre", 19, "half", "published RT range >=1.30 s   |   calibrated g=" + fixed$ (gardnerGain, 4)
        endif
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.20, 0.48, netTop, netBot
        Axes: 0, 1, 0, 1
        Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Topology"
        Select inner viewport: 0.60, 7.70, netTop, netBot
        Axes: 0, 100, 0, 100
    endif

    # ---- parameter strip ----
    Select outer viewport: 0, 8, parTop, parTop + 0.4
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.40, 0.40, 0.40}"
    if topology < 3
        parLine$ = "Combs: " + string$ (comb_count) + " | Allpass: " + string$ (allpass_count)
    else
        parLine$ = "Gardner Figure 4.11 room " + string$ (gardner_room) + " | Feedback gain: " + fixed$ (gardnerGain, 3)
    endif
    if topology = 3
        parLine$ = parLine$ + " | RT60: " + fixed$ (reverb_time_RT60_s, 2) + " s | LPF: " + fixed$ (gardner_lpf_hz, 0) + " Hz | Wet gain: " + fixed$ (netGain, 3) + " | Peak: " + fixed$ (finalPeak, 3)
    else
        if damping_mode = 1
            dampName$ = "one-pole"
        else
            dampName$ = "FIR"
        endif
        if topology = 2 and moor_reference = 1
            dampText$ = "Table 2 per-comb"
        else
            dampText$ = fixed$ (damping, 2) + " " + dampName$
        endif
        parLine$ = parLine$ + " | RT60: " + fixed$ (reverb_time_RT60_s, 2) + " s | Damping: " + dampText$ + " | Predelay: " + fixed$ (predelay_ms, 0) + " ms | Wet gain: " + fixed$ (netGain, 3) + " | Peak: " + fixed$ (finalPeak, 3)
    endif
    Text: 0.5, "centre", 0.5, "half", parLine$

    Font size: 10
    Colour: "Black"

    # ---- summary ----
    Select outer viewport: 0, 8, sumTop, sumTop + 1.0
    Select inner viewport: 0.60, 7.70, sumTop + 0.07, sumTop + 0.93
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"

    if topology = 1
        sumLine$ = "Parallel feedback combs on mutually prime delays, then " + string$ (allpass_count) + " series allpass sections"
    elsif topology = 2
        sumLine$ = "FIR early reflections in front of " + string$ (comb_count) + " lowpass combs and " + string$ (allpass_count) + " allpass; the late field enters behind the cluster"
    else
        sumLine$ = "Published Gardner Figure 4.11 structure for this room class; RT feedback gain solved from the rendered network"
    endif

    if topology = 3
        decayLine$ = "Decay measured on the rendered reference network: " + fixed$ (rt60_measured, 2) + " s by " + rt60_method$ + "; feedback gain calibrated to the requested RT"
    elsif topology = 2 and moor_reference = 1
        decayLine$ = "Decay measured on Moorer's published Table 2/3 network: " + fixed$ (rt60_measured, 2) + " s by " + rt60_method$
    elsif damping > 0
        decayLine$ = "Decay measured on the rendered impulse response: " + fixed$ (rt60_measured, 2) + " s by " + rt60_method$ + "; damping shortens the tail above DC"
    else
        decayLine$ = "Decay measured on the rendered impulse response: " + fixed$ (rt60_measured, 2) + " s by " + rt60_method$ + " against " + fixed$ (reverb_time_RT60_s, 2) + " s requested, undamped"
    endif

    Font size: 6
    Select inner viewport: 0.60, 7.70, sumTop + 0.07, sumTop + 0.93
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.02, "left", 0.57, "half", sumLine$
    Select inner viewport: 0.60, 7.70, sumTop + 0.07, sumTop + 0.93
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
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
if topology = 3
    appendInfoLine: "  Gardner feedback gain was calibrated on the rendered network with its published LPF."
elsif damping > 0
    appendInfoLine: "  The measurement is broadband, so frequency-dependent damping can shorten"
    appendInfoLine: "  the measured broadband decay relative to the low-frequency loop decay."
endif
appendInfoLine: "Network energy gain measured on the impulse response: ", fixed$ (energyGain, 4)
appendInfoLine: "  wet path scaled by ", fixed$ (netGain, 6), " for unit energy gain"
if topology < 3
    if wet_contains_direct = 0
        appendInfoLine: "  direct component removed from the wet path (tail only)"
    else
        appendInfoLine: "  wet retains the direct sound, as in the original network"
    endif
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
    appendInfoLine: "Note: damping was clamped to its legal range."
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
