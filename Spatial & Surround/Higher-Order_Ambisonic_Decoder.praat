# ============================================================
# Praat AudioTools - Higher-Order Ambisonic Decoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - SN3D-correct decode normalization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Higher-Order Ambisonic (HOA) Decoder
#   Decodes B-format ambisonic channels to speaker feeds
#   Supports 1st, 2nd, and 3rd order ambisonics
#
# Usage:
#   Select ambisonic channel sounds (W, Y, Z, X, ...) in correct order
#   then run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   SN3D-aware decode normalization (the panning was too broad; HOA
#   directivity had collapsed toward first order).
#   - Each ambisonic order n is now scaled by (2n+1) in the decode matrix.
#     For SN3D input this turns the raw projection sum_n P_n(cos g) into the
#     correct basic panning function sum_n (2n+1) P_n(cos g). Verified: the
#     octagon gain curve now matches 1 + 3cos + 5P2 + 7P3 exactly.
#   - In-phase weights replaced with the 3-D spherical form
#     a_n = N!(N+1)! / ((N+n+1)!(N-n)!) (order 3: 1, 3/5, 1/5, 1/35);
#     the previous values were the 2-D cardioid weights. Max-rE (Legendre)
#     is now applied IN ADDITION to (2n+1), not instead of it.
#   - Normalization now divides by the number of DIRECTIONAL speakers
#     (LFE excluded), so 5.1/7.1 output is no longer needlessly quiet; the
#     minimum-speaker check counts directional speakers too.
#   - RGB values in the speaker/bar colours are clamped to [0,1] (the old
#     formula could go negative and break Praat drawing).
#   - Combined mode auto-detects order from the channel count (4/9/16).
#   - 5.1/7.1 flagged as approximate sampling decode for a non-uniform
#     layout; minor label fixes (row-norm chart, LFE in angle list).
#
# Changelog v0.3:
#   Correctness pass; now matches the corrected ambiX encoder.
#   - FIX (critical): speaker layouts were mirrored (left content came out
#     right). All presets now use the ambiX convention (azimuth CCW from
#     front, +Y = LEFT); stereo is a +/-30 deg pair, not +/-90.
#   - FIX (math): 3rd-order SN3D coefficients for ACN 9/11/13/15 corrected
#     from sqrt5/4, sqrt3/4 to sqrt(5/8), sqrt(3/8). Verified by an
#     encode->decode round trip (loudest speaker = nearest to the source).
#   - Combined-input mode: accepts one multichannel ambiX Sound (the
#     encoder's output) and extracts ACN0..N-1 automatically.
#   - Full input validation: channel count, mono, matching sample rate and
#     length across all channels.
#   - Decode weights: Max-rE now uses Legendre P_m(rE) and In-phase uses
#     (L!)^2/((L+m)!(L-m)!), applied per ORDER (W no longer lumped with
#     order 1). The old Max-rE wrongly BOOSTED higher orders.
#   - Peak protection is attenuate-only (a quiet decode is no longer boosted
#     to 0.99, which had hidden the true level).
#   - LFE (5.1/7.1) is no longer fed a full-band ambisonic decode; it is left
#     silent. Undersized layouts (< ~2N+1 speakers) are warned about.
#   - Honest labelling: this is a HORIZONTAL decoder (height not
#     reconstructed). Visualization mirrored to match (+Y left); the flat
#     "W coefficient" chart replaced with per-speaker decoder row norm.
#
# Changelog v0.2:
#   - Efficient channel summing using Formula (not Combine to stereo)
#   - Modern selectObject: syntax throughout
#   - Added speaker layout visualization
#   - Added play_result toggle
#   - Proper array storage for object IDs
#   - Robust formula string building
#   - Cleaner coefficient calculation
# ============================================================

# ============================================================
# FORM
# ============================================================

form Ambisonic Decoder (horizontal)
    comment Input: a combined ambiX Sound (from the encoder) OR legacy separate
    comment ACN channels selected in order. This is a HORIZONTAL decoder
    comment (speakers in the horizontal plane; height is not reconstructed).
    comment ─────────────────────────────────────────
    optionmenu Input_mode: 1
        option Combined ambiX Sound (one multichannel object)
        option Separate ACN channels (legacy, select in ACN order)
    comment ─────────────────────────────────────────
    optionmenu Ambisonic_order: 1
        option 1st order (4 channels)
        option 2nd order (9 channels)
        option 3rd order (16 channels)
    comment ─────────────────────────────────────────
    optionmenu Speaker_preset: 1
        option Stereo pair (+/-30 deg, 2 speakers)
        option Triangle (3 speakers)
        option Quad (4 speakers)
        option Pentagon (5 speakers)
        option Hexagon (6 speakers)
        option Surround 5.1 (6 incl. silent LFE)
        option Surround 7.1 (8 incl. silent LFE)
        option Octagon (8 speakers)
    comment ─────────────────────────────────────────
    optionmenu Decode_method: 1
        option Basic (projection)
        option Max-rE (energy vector)
        option In-phase (no side lobes)
    comment ─────────────────────────────────────────
    boolean Peak_protect_only 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

clearinfo

# ============================================================
# VALIDATION
# ============================================================

# Determine expected channels based on order
if ambisonic_order = 1
    expectedChannels = 4
    orderName$ = "1st"
elsif ambisonic_order = 2
    expectedChannels = 9
    orderName$ = "2nd"
else
    expectedChannels = 16
    orderName$ = "3rd"
endif

# ── Acquire the 16/9/4 ACN channels as mono objects in ambiChannel[] ──
if input_mode = 1
    # Combined: one multichannel Sound (e.g. the encoder's output).
    numSelected = numberOfSelected("Sound")
    if numSelected <> 1
        exitScript: "Combined mode: select exactly ONE multichannel Sound. Selected: " + string$(numSelected)
    endif
    combinedInput = selected("Sound")
    selectObject: combinedInput
    inCh = Get number of channels
    # Auto-detect order from the channel count; the form's order is ignored here.
    if inCh = 4
        ambisonic_order = 1
        expectedChannels = 4
        orderName$ = "1st"
    elsif inCh = 9
        ambisonic_order = 2
        expectedChannels = 9
        orderName$ = "2nd"
    elsif inCh = 16
        ambisonic_order = 3
        expectedChannels = 16
        orderName$ = "3rd"
    else
        exitScript: "Combined Sound must have 4, 9, or 16 channels (ACN/SN3D); got " + string$(inCh) + "."
    endif
    duration = Get total duration
    sr = Get sampling frequency
    numSamples = Get number of samples
    # Channel k of the file = ACN(k-1). Extract each to a mono working object.
    for i from 1 to expectedChannels
        selectObject: combinedInput
        ambiChannel[i] = Extract one channel: i
        channelName$[i] = "ACN" + string$(i - 1)
    endfor
    fromCombined = 1
else
    # Legacy: separate mono ACN channels selected in order.
    numSelected = numberOfSelected("Sound")
    if numSelected <> expectedChannels
        exitScript: "Legacy mode: select exactly " + string$(expectedChannels) + " mono Sound objects in ACN order." + newline$ + "Currently selected: " + string$(numSelected)
    endif
    for i from 1 to expectedChannels
        ambiChannel[i] = selected("Sound", i)
    endfor
    # Reference properties from channel 1, then validate every channel matches.
    selectObject: ambiChannel[1]
    duration = Get total duration
    sr = Get sampling frequency
    numSamples = Get number of samples
    for i from 1 to expectedChannels
        selectObject: ambiChannel[i]
        channelName$[i] = selected$("Sound")
        chN = Get number of channels
        chSr = Get sampling frequency
        chSamp = Get number of samples
        if chN <> 1
            exitScript: "Channel " + string$(i) + " (" + channelName$[i] + ") is not mono."
        endif
        if chSr <> sr
            exitScript: "Channel " + string$(i) + " sample-rate mismatch (" + string$(chSr) + " vs " + string$(sr) + ")."
        endif
        if chSamp <> numSamples
            exitScript: "Channel " + string$(i) + " length mismatch (" + string$(chSamp) + " vs " + string$(numSamples) + " samples)."
        endif
    endfor
    fromCombined = 0
endif

# ============================================================
# SPEAKER CONFIGURATION
# ============================================================

# Speaker preset names for output
if speaker_preset = 1
    presetName$ = "stereo"
    numSpeakers = 2
elsif speaker_preset = 2
    presetName$ = "triangle"
    numSpeakers = 3
elsif speaker_preset = 3
    presetName$ = "quad"
    numSpeakers = 4
elsif speaker_preset = 4
    presetName$ = "pentagon"
    numSpeakers = 5
elsif speaker_preset = 5
    presetName$ = "hexagon"
    numSpeakers = 6
elsif speaker_preset = 6
    presetName$ = "surround51"
    numSpeakers = 6
elsif speaker_preset = 7
    presetName$ = "surround71"
    numSpeakers = 8
else
    presetName$ = "octagon"
    numSpeakers = 8
endif

# Decode method name
if decode_method = 1
    methodName$ = "basic"
elsif decode_method = 2
    methodName$ = "maxrE"
else
    methodName$ = "inphase"
endif

# Define speaker positions (azimuth in radians).
# Convention MATCHES the encoder: azimuth CCW from front (+X), +Y = LEFT, so a
# left speaker has POSITIVE azimuth and a right speaker negative (= 360-x). The
# old layouts were mirrored, which sent left-encoded content to the right.
for i from 1 to 8
    speakerEl[i] = 0
    speakerIsLFE[i] = 0
endfor

if speaker_preset = 1
    # Stereo loudspeaker pair at +/-30 deg (standard, not +/-90).
    speakerAz[1] = 30 * pi / 180
    speakerAz[2] = 330 * pi / 180

elsif speaker_preset = 2
    # Triangle: front + rear-left + rear-right (CCW)
    speakerAz[1] = 0
    speakerAz[2] = 120 * pi / 180
    speakerAz[3] = 240 * pi / 180

elsif speaker_preset = 3
    # Quad: FL, FR, RL, RR (left = positive az)
    speakerAz[1] = 45 * pi / 180
    speakerAz[2] = 315 * pi / 180
    speakerAz[3] = 135 * pi / 180
    speakerAz[4] = 225 * pi / 180

elsif speaker_preset = 4
    # Pentagon: 5 evenly spaced, CCW (already correct)
    for i from 1 to 5
        speakerAz[i] = (i - 1) * 2 * pi / 5
    endfor

elsif speaker_preset = 5
    # Hexagon: 6 evenly spaced, CCW
    for i from 1 to 6
        speakerAz[i] = (i - 1) * 2 * pi / 6
    endfor

elsif speaker_preset = 6
    # 5.1: L, R, C, LFE, Ls, Rs (ITU-ish; left = positive az). LFE is NOT decoded.
    speakerAz[1] = 30 * pi / 180
    speakerAz[2] = 330 * pi / 180
    speakerAz[3] = 0
    speakerAz[4] = 0
    speakerAz[5] = 110 * pi / 180
    speakerAz[6] = 250 * pi / 180
    speakerIsLFE[4] = 1

elsif speaker_preset = 7
    # 7.1: L, R, C, LFE, Ls, Rs, Lb, Rb (left = positive az). LFE is NOT decoded.
    speakerAz[1] = 30 * pi / 180
    speakerAz[2] = 330 * pi / 180
    speakerAz[3] = 0
    speakerAz[4] = 0
    speakerAz[5] = 90 * pi / 180
    speakerAz[6] = 270 * pi / 180
    speakerAz[7] = 135 * pi / 180
    speakerAz[8] = 225 * pi / 180
    speakerIsLFE[4] = 1

else
    # Octagon: 8 evenly spaced, CCW
    for i from 1 to 8
        speakerAz[i] = (i - 1) * 2 * pi / 8
    endfor
endif

# Count directional (non-LFE) speakers: LFE is not part of the decode, so it
# must not dilute the normalization or the minimum-speaker requirement.
numLFE = 0
for i from 1 to numSpeakers
    if speakerIsLFE[i]
        numLFE = numLFE + 1
    endif
endfor
numDirectionalSpeakers = numSpeakers - numLFE

# Minimum-speaker sanity: a horizontal order-N decode needs about 2N+1
# DIRECTIONAL speakers.
minSpeakers = 2 * ambisonic_order + 1
undersized = 0
if numDirectionalSpeakers < minSpeakers
    undersized = 1
endif

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Higher-Order Ambisonic Decoder v0.4"
writeInfoLine: "============================================"
appendInfoLine: "Ambisonic order: ", orderName$, " (", expectedChannels, " channels)"
appendInfoLine: "Speaker layout: ", presetName$, " (", numSpeakers, " output channels, ", numDirectionalSpeakers, " directional)"
appendInfoLine: "Decode method: ", methodName$
if speaker_preset = 6 or speaker_preset = 7
    appendInfoLine: "  Note: non-uniform layout -- approximate horizontal sampling decode"
    appendInfoLine: "        (AllRAD/EPAD would be better for irregular arrays)."
endif
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Input channels:"
for i from 1 to expectedChannels
    appendInfoLine: "  ", i, ": ", channelName$[i]
endfor
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Speaker positions:"
for spk from 1 to numSpeakers
    azDeg = speakerAz[spk] * 180 / pi
    elDeg = speakerEl[spk] * 180 / pi
    if speakerIsLFE[spk]
        appendInfoLine: "  Spk ", spk, ": LFE (not decoded, silent)"
    else
        appendInfoLine: "  Spk ", spk, ": az=", fixed$(azDeg, 1), "°, el=", fixed$(elDeg, 1), "°"
    endif
endfor
if undersized
    appendInfoLine: ""
    appendInfoLine: "  WARNING: ", numSpeakers, " speakers is fewer than the ~", minSpeakers,
        ... " needed for a stable horizontal order-", ambisonic_order, " decode."
    appendInfoLine: "           Directions and levels will not be well reconstructed."
endif
appendInfoLine: ""

# ============================================================
# CONSTANTS
# ============================================================

sqrt2 = sqrt(2)
sqrt3 = sqrt(3)
sqrt5 = sqrt(5)
sqrt15 = sqrt(15)

# ============================================================
# CALCULATE DECODER MATRIX
# ============================================================

appendInfoLine: "Calculating decoder coefficients..."

for spk from 1 to numSpeakers
    az = speakerAz[spk]
    el = speakerEl[spk]
    
    cos_az = cos(az)
    sin_az = sin(az)
    cos_el = cos(el)
    sin_el = sin(el)
    cos_el_sq = cos_el * cos_el
    sin_el_sq = sin_el * sin_el
    
    # 1st order coefficients (ACN ordering: W, Y, Z, X)
    # W = 1 (omni)
    # Y = sin(az)*cos(el)
    # Z = sin(el)
    # X = cos(az)*cos(el)
    
    coeff[spk, 1] = 1.0
    coeff[spk, 2] = sin_az * cos_el
    coeff[spk, 3] = sin_el
    coeff[spk, 4] = cos_az * cos_el
    
    # 2nd order (V, T, R, S, U)
    if ambisonic_order >= 2
        cos_2az = cos(2 * az)
        sin_2az = sin(2 * az)
        
        coeff[spk, 5] = sqrt3 * sin_2az * cos_el_sq * 0.5
        coeff[spk, 6] = sqrt3 * sin_az * sin_el * cos_el
        coeff[spk, 7] = 0.5 * (3 * sin_el_sq - 1)
        coeff[spk, 8] = sqrt3 * cos_az * sin_el * cos_el
        coeff[spk, 9] = sqrt3 * cos_2az * cos_el_sq * 0.5
    endif
    
    # 3rd order (Q, O, M, K, L, N, P)
    if ambisonic_order >= 3
        cos_3az = cos(3 * az)
        sin_3az = sin(3 * az)
        cos_2az = cos(2 * az)
        sin_2az = sin(2 * az)
        
        # SN3D-correct 3rd-order (matches the encoder): ACN 9/11/13/15 use
        # sqrt(5/8) and sqrt(3/8), not sqrt5/4 and sqrt3/4.
        coeff[spk, 10] = sqrt(5/8) * sin_3az * cos_el * cos_el_sq
        coeff[spk, 11] = sqrt15 * sin_2az * sin_el * cos_el_sq * 0.5
        coeff[spk, 12] = sqrt(3/8) * sin_az * cos_el * (5 * sin_el_sq - 1)
        coeff[spk, 13] = 0.5 * sin_el * (5 * sin_el_sq - 3)
        coeff[spk, 14] = sqrt(3/8) * cos_az * cos_el * (5 * sin_el_sq - 1)
        coeff[spk, 15] = sqrt15 * cos_2az * sin_el * cos_el_sq * 0.5
        coeff[spk, 16] = sqrt(5/8) * cos_3az * cos_el * cos_el_sq
    endif
    
    # Per-order SIDE weights a_n (method-dependent). Basic = all 1.
    a0 = 1
    a1 = 1
    a2 = 1
    a3 = 1
    if decode_method = 2
        # Max-rE: a_n = Legendre P_n(rE), rE = cos(137.9 / (order+1.51) deg).
        rE = cos(137.9 / (ambisonic_order + 1.51) * pi / 180)
        a1 = rE
        a2 = 0.5 * (3 * rE * rE - 1)
        a3 = 0.5 * (5 * rE * rE * rE - 3 * rE)
    elsif decode_method = 3
        # In-phase (3-D spherical): a_n = N!(N+1)! / ((N+n+1)!(N-n)!).
        # (The 2-D cardioid weights used before were wrong for a 3-D basis.)
        if ambisonic_order = 1
            a1 = 1/3
        elsif ambisonic_order = 2
            a1 = 1/2
            a2 = 1/10
        else
            a1 = 3/5
            a2 = 1/5
            a3 = 1/35
        endif
    endif

    # Normalize by the number of DIRECTIONAL speakers (LFE excluded).
    normFactor = 1 / numDirectionalSpeakers

    # Decode weight per channel = (2n+1) * a_n * normFactor.
    # The (2n+1) factor is essential for SN3D input: it is what turns the raw
    # projection sum_n P_n(cos g) into the proper basic panning function
    # sum_n (2n+1) P_n(cos g). Without it, higher orders are suppressed and the
    # HOA directivity collapses toward first order.
    for ch from 1 to expectedChannels
        if ch = 1
            n2p1 = 1
            aw = a0
        elsif ch <= 4
            n2p1 = 3
            aw = a1
        elsif ch <= 9
            n2p1 = 5
            aw = a2
        else
            n2p1 = 7
            aw = a3
        endif
        coeff[spk, ch] = coeff[spk, ch] * n2p1 * aw * normFactor
    endfor
endfor

appendInfoLine: "Decoder matrix calculated"
appendInfoLine: ""

# ============================================================
# DECODE: CREATE SPEAKER FEEDS
# ============================================================

appendInfoLine: "Decoding to speaker feeds..."

for spk from 1 to numSpeakers
    appendInfoLine: "  Processing speaker ", spk, "/", numSpeakers
    
    # Create silent output channel
    Create Sound from formula: "Speaker_" + string$(spk), 1, 0, duration, sr, "0"
    speakerSound[spk] = selected("Sound")
    
    # Sum weighted ambisonic channels using Formula.
    # LFE speakers are NOT part of the ambisonic decode (an LFE is not a
    # directional loudspeaker); leave them silent.
    if not speakerIsLFE[spk]
        for ch from 1 to expectedChannels
            c = coeff[spk, ch]
            if c <> 0
                coeffStr$ = fixed$(c, 8)
                inputIdStr$ = string$(ambiChannel[ch])
                selectObject: speakerSound[spk]
                Formula: "self + " + coeffStr$ + " * Object_" + inputIdStr$ + "[col]"
            endif
        endfor
    endif
endfor

appendInfoLine: ""

# ============================================================
# PEAK PROTECTION (attenuate only)
# ============================================================

if peak_protect_only
    appendInfoLine: "Peak protection (attenuate-only)..."
    
    globalPeak = 0
    for spk from 1 to numSpeakers
        selectObject: speakerSound[spk]
        peak = Get absolute extremum: 0, 0, "None"
        if peak > globalPeak
            globalPeak = peak
        endif
    endfor
    
    # Only attenuate on clipping, with a shared factor across all speakers, so
    # the true decode level and relative speaker levels are preserved (boosting
    # a quiet decode up to 0.99 would hide the actual level and defeat
    # comparisons between methods/layouts).
    if globalPeak > 0.99
        scaleFactor = 0.99 / globalPeak
        scaleStr$ = fixed$(scaleFactor, 8)
        for spk from 1 to numSpeakers
            selectObject: speakerSound[spk]
            Formula: "self * " + scaleStr$
        endfor
        appendInfoLine: "  Global peak: ", fixed$(globalPeak, 4), " -> attenuated by ", fixed$(20*log10(scaleFactor), 1), " dB"
    else
        appendInfoLine: "  Global peak: ", fixed$(globalPeak, 4), " (no attenuation needed)"
    endif
endif

# ============================================================
# COMBINE TO MULTICHANNEL OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "Combining to multichannel output..."

selectObject: speakerSound[1]
for spk from 2 to numSpeakers
    plusObject: speakerSound[spk]
endfor

result = Combine to stereo
selectObject: result
Rename: "AmbiDecode_" + orderName$ + "_" + presetName$ + "_" + methodName$

# Get final info
selectObject: result
finalChannels = Get number of channels
finalDur = Get total duration

# Clean up individual speaker sounds
for spk from 1 to numSpeakers
    removeObject: speakerSound[spk]
endfor

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Ambisonic Decoder##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... orderName$ + " order → " + presetName$
        ... + " (" + string$(numSpeakers) + " spk)"
        ... + "  |  " + methodName$

    # ----------------------------------------------------------
    # Speaker layout (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.5, 0.52, 3.82
    Select inner viewport: 0.45, 4.20, 0.62, 3.70

    Axes: -1.6, 1.6, -1.6, 1.6
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -1.6, 1.6

    # Reference circle + crosshairs
    Colour: "{0.86, 0.86, 0.86}"
    Line width: 1
    Draw circle: 0, 0, 0.5
    Draw circle: 0, 0, 1.0
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, -1.45, 0, 1.45
    Draw line: -1.45, 0, 1.45, 0

    # Direction labels
    Font size: 6
    Colour: "{0.50, 0.50, 0.50}"
    Text: 0.08, "left", 1.42, "half", "Front"
    Text: 0.08, "left", -1.42, "half", "Rear"
    Text: -1.48, "right", -0.12, "half", "L"
    Text: 1.48, "left", -0.12, "half", "R"

    # Listener
    Paint circle (mm): "{0.35, 0.35, 0.35}", 0, 0, 2.2
    Font size: 5
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0, "centre", -0.16, "half", "Listener"

    # Speakers — coloured squares with radial lines
    for spk from 1 to numSpeakers
        az = speakerAz[spk]
        spkVizX = -sin(az)
        spkVizY = cos(az)

        # Colour from hue wheel
        hue = (spk - 1) / numSpeakers
        sR = 0.30 + 0.50 * sin(hue * 2 * pi)
        sG = 0.30 + 0.50 * sin(hue * 2 * pi + 2 * pi / 3)
        sB = 0.30 + 0.50 * sin(hue * 2 * pi + 4 * pi / 3)
        sR = min(1, max(0, sR))
        sG = min(1, max(0, sG))
        sB = min(1, max(0, sB))
        spkCol$ = "{" + fixed$(sR, 2) + ", " + fixed$(sG, 2) + ", " + fixed$(sB, 2) + "}"

        Paint rectangle: spkCol$,
            ... spkVizX - 0.08, spkVizX + 0.08,
            ... spkVizY - 0.08, spkVizY + 0.08

        # Radial line
        Colour: spkCol$
        Dotted line
        Draw line: 0, 0, spkVizX * 0.85, spkVizY * 0.85
        Solid line

        # Number label outside
        lblDist = 1.18
        lblX = -lblDist * sin(az)
        lblY = lblDist * cos(az)
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: lblX, "centre", lblY, "half", string$(spk)
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Speaker layout: " + presetName$

    # ----------------------------------------------------------
    # Per-speaker decoder row-norm bar chart (right, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.5, 8, 0.52, 2.22
    Select inner viewport: 4.80, 7.65, 0.62, 2.10

    # Decoder ROW NORM per speaker = sqrt(sum of that speaker's coefficients^2).
    # Unlike the W coefficient (identical for every speaker), this varies and
    # shows how strongly each speaker is driven overall.
    rowNorm# = zero#(numSpeakers)
    maxNorm = 0
    for spk from 1 to numSpeakers
        ss = 0
        for ch from 1 to expectedChannels
            ss = ss + coeff[spk, ch] * coeff[spk, ch]
        endfor
        rowNorm#[spk] = sqrt(ss)
        if rowNorm#[spk] > maxNorm
            maxNorm = rowNorm#[spk]
        endif
    endfor
    if maxNorm < 0.01
        maxNorm = 1
    endif
    wTop = maxNorm * 1.3

    Axes: 0.3, numSpeakers + 0.7, 0, wTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.3, numSpeakers + 0.7, 0, wTop

    for spk from 1 to numSpeakers
        wVal = rowNorm#[spk]
        hue = (spk - 1) / numSpeakers
        sR = 0.30 + 0.50 * sin(hue * 2 * pi)
        sG = 0.30 + 0.50 * sin(hue * 2 * pi + 2 * pi / 3)
        sB = 0.30 + 0.50 * sin(hue * 2 * pi + 4 * pi / 3)
        sR = min(1, max(0, sR))
        sG = min(1, max(0, sG))
        sB = min(1, max(0, sB))
        Paint rectangle: "{" + fixed$(sR, 2) + ", " + fixed$(sG, 2) + ", " + fixed$(sB, 2) + "}",
            ... spk - 0.32, spk + 0.32, 0, wVal
        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: spk, "centre", wVal + wTop * 0.04, "half", fixed$(wVal, 3)
        Font size: 6
        Text: spk, "centre", -wTop * 0.07, "half", string$(spk)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Row norm"
    Text bottom: "yes", "Speaker"
    Text top: "no", "Decoder row norm per speaker"

    # ----------------------------------------------------------
    # Output waveform — mono downmix (right, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.5, 8, 2.30, 3.82
    Select inner viewport: 4.80, 7.65, 2.38, 3.72

    selectObject: result
    vizDown = Convert to mono
    Colour: "{0.35, 0.50, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizDown
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mix"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Mono downmix"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.92, 4.82
    Select inner viewport: 0.45, 7.65, 3.98, 4.76
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    # Speaker angle list
    spkAngles$ = ""
    for spk from 1 to numSpeakers
        if spk > 1
            spkAngles$ = spkAngles$ + "  "
        endif
        if speakerIsLFE[spk]
            spkAngles$ = spkAngles$ + string$(spk) + ":LFE"
        else
            azDeg = speakerAz[spk] * 180 / pi
            spkAngles$ = spkAngles$ + string$(spk) + ":" + fixed$(azDeg, 0) + "°"
        endif
    endfor

    Text: 0.02, "left", 0.58, "half",
        ... "Order: " + orderName$
        ... + "  |  Method: " + methodName$
        ... + "  |  Layout: " + presetName$
        ... + " (" + string$(numSpeakers) + " spk)"
        ... + "  |  Duration: " + fixed$(finalDur, 2) + " s"
    Text: 0.02, "left", 0.22, "half",
        ... "Speakers:  " + spkAngles$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "DECODING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", finalChannels
appendInfoLine: "Duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: ""
appendInfoLine: "Ambisonic order: ", orderName$
appendInfoLine: "Speaker layout: ", presetName$
appendInfoLine: "Decode method: ", methodName$
appendInfoLine: ""
appendInfoLine: "Decoder coefficients (1st-order components per speaker):"
for spk from 1 to numSpeakers
    appendInfoLine: "  Spk ", spk, ": W=", fixed$(coeff[spk, 1], 4), ", Y=", fixed$(coeff[spk, 2], 4), ", Z=", fixed$(coeff[spk, 3], 4), ", X=", fixed$(coeff[spk, 4], 4)
endfor

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    selectObject: result
    Play
endif

# Clean up channels extracted from a combined input (the user's original
# multichannel object is left untouched). Legacy inputs are the user's own
# objects and are never removed.
if fromCombined = 1
    for i from 1 to expectedChannels
        removeObject: ambiChannel[i]
    endfor
endif

selectObject: result