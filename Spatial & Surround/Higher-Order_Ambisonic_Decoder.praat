# ============================================================
# Praat AudioTools - Higher-Order Ambisonic Decoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Purpose
#   Decode Full-3D ambiX B-format (ACN/SN3D), orders 1..5, to a selected
#   loudspeaker array. Combined multichannel input is auto-detected by channel
#   count (4/9/16/25/36). Legacy separate ACN channels are also supported.
#
# Built-in layouts include horizontal arrays plus 7.1.4 and 22.2. LFE slots
# are output as SILENCE because HOA carries no directional LFE channel.
#
# The script calculates the actual rank of the real spherical-harmonic
# sampling matrix at the selected speaker directions. A layout can have more
# loudspeakers than HOA components and still be rank-deficient (for example a
# horizontal array cannot reconstruct all Full-3D vertical modes).
# ============================================================

form Ambisonic Decoder
    comment Input = Full-3D ambiX (ACN / SN3D)
    optionmenu Input_mode: 1
        option "Combined ambiX Sound (one multichannel object)"
        option "Separate mono ACN channels (legacy, selected in ACN order)"
    optionmenu Ambisonic_order: 1
        option "1st order (4 channels)"
        option "2nd order (9 channels)"
        option "3rd order (16 channels)"
        option "4th order (25 channels)"
        option "5th order (36 channels)"
    comment ─────────────────────────────────────────
    optionmenu Speaker_preset: 1
        option "Auto full-rank if available"
        option "2.0 stereo (+/-30 deg)"
        option "Triangle (3 horizontal speakers)"
        option "4.0 quad"
        option "Pentagon (5 horizontal speakers)"
        option "Hexagon (6 horizontal speakers)"
        option "5.0"
        option "5.1 (silent LFE)"
        option "7.0"
        option "7.1 (silent LFE)"
        option "8-channel horizontal ring"
        option "12-channel horizontal ring"
        option "16-channel horizontal ring"
        option "7.1.4 (11 directional + silent LFE)"
        option "22.2 (22 directional + 2 silent LFE)"
    optionmenu Decode_method: 1
        option "Basic sampling / projection"
        option "Max-rE order weighting"
        option "In-phase order weighting"
    boolean Peak_protect_only 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

clearinfo

# ============================================================
# INPUT ACQUISITION
# ============================================================
if input_mode = 1
    if numberOfSelected ("Sound") <> 1
        exitScript: "Combined mode: select exactly one multichannel ambiX Sound."
    endif
    combinedInput = selected ("Sound")
    inputName$ = selected$ ("Sound")
    selectObject: combinedInput
    inCh = Get number of channels
    if inCh = 4
        order = 1
    elsif inCh = 9
        order = 2
    elsif inCh = 16
        order = 3
    elsif inCh = 25
        order = 4
    elsif inCh = 36
        order = 5
    else
        exitScript: "Combined ambiX input must contain 4, 9, 16, 25 or 36 channels; got " + string$ (inCh) + "."
    endif
    expectedChannels = inCh
    duration = Get total duration
    sr = Get sampling frequency
    numSamples = Get number of samples
    for ch from 1 to expectedChannels
        selectObject: combinedInput
        ambiChannel[ch] = Extract one channel: ch
        channelName$[ch] = "ACN" + string$ (ch - 1)
    endfor
    fromCombined = 1
else
    order = ambisonic_order
    expectedChannels = (order + 1) ^ 2
    if numberOfSelected ("Sound") <> expectedChannels
        exitScript: "Separate-channel mode requires exactly " + string$ (expectedChannels) + " mono Sounds selected in ACN order."
    endif
    inputName$ = "separate_ACN_channels"
    for ch from 1 to expectedChannels
        ambiChannel[ch] = selected ("Sound", ch)
        selectObject: ambiChannel[ch]
        if Get number of channels <> 1
            exitScript: "Selected ACN channel " + string$ (ch - 1) + " is not mono."
        endif
        channelName$[ch] = selected$ ("Sound")
    endfor
    selectObject: ambiChannel[1]
    duration = Get total duration
    sr = Get sampling frequency
    numSamples = Get number of samples
    for ch from 2 to expectedChannels
        selectObject: ambiChannel[ch]
        if Get sampling frequency <> sr
            exitScript: "Sample-rate mismatch among selected ACN channels."
        endif
        if Get number of samples <> numSamples
            exitScript: "Sample-count mismatch among selected ACN channels."
        endif
    endfor
    fromCombined = 0
endif

if order = 1
    orderName$ = "1st"
elsif order = 2
    orderName$ = "2nd"
elsif order = 3
    orderName$ = "3rd"
elsif order = 4
    orderName$ = "4th"
else
    orderName$ = "5th"
endif

# ============================================================
# LAYOUT RESOLUTION
# ============================================================
resolvedPreset = speaker_preset
if speaker_preset = 1
    if order = 1
        resolvedPreset = 14
    elsif order = 2 or order = 3
        resolvedPreset = 15
    else
        if fromCombined
            for ch from 1 to expectedChannels
                removeObject: ambiChannel[ch]
            endfor
        endif
        exitScript: "Auto: no built-in full-rank array is available for order " + string$ (order) + ". Choose 22.2 manually to make an explicitly rank-deficient decode, or use a denser external decoder."
    endif
endif

for i from 1 to 24
    speakerAz[i] = 0
    speakerEl[i] = 0
    speakerIsLFE[i] = 0
endfor

if resolvedPreset = 2
    presetName$ = "2.0"
    numSpeakers = 2
    speakerAz[1] = 30
    speakerAz[2] = -30
elsif resolvedPreset = 3
    presetName$ = "triangle"
    numSpeakers = 3
    speakerAz[1] = 0
    speakerAz[2] = 120
    speakerAz[3] = -120
elsif resolvedPreset = 4
    presetName$ = "4.0_quad"
    numSpeakers = 4
    speakerAz[1] = 45
    speakerAz[2] = -45
    speakerAz[3] = 135
    speakerAz[4] = -135
elsif resolvedPreset = 5
    presetName$ = "pentagon"
    numSpeakers = 5
    for i from 1 to 5
        speakerAz[i] = (i - 1) * 360 / 5
    endfor
elsif resolvedPreset = 6
    presetName$ = "hexagon"
    numSpeakers = 6
    for i from 1 to 6
        speakerAz[i] = (i - 1) * 360 / 6
    endfor
elsif resolvedPreset = 7
    presetName$ = "5.0"
    numSpeakers = 5
    speakerAz[1] = 30
    speakerAz[2] = -30
    speakerAz[3] = 0
    speakerAz[4] = 110
    speakerAz[5] = -110
elsif resolvedPreset = 8
    presetName$ = "5.1"
    numSpeakers = 6
    speakerAz[1] = 30
    speakerAz[2] = -30
    speakerAz[3] = 0
    speakerIsLFE[4] = 1
    speakerAz[5] = 110
    speakerAz[6] = -110
elsif resolvedPreset = 9
    presetName$ = "7.0"
    numSpeakers = 7
    speakerAz[1] = 30
    speakerAz[2] = -30
    speakerAz[3] = 0
    speakerAz[4] = 90
    speakerAz[5] = -90
    speakerAz[6] = 150
    speakerAz[7] = -150
elsif resolvedPreset = 10
    presetName$ = "7.1"
    numSpeakers = 8
    speakerAz[1] = 30
    speakerAz[2] = -30
    speakerAz[3] = 0
    speakerIsLFE[4] = 1
    speakerAz[5] = 90
    speakerAz[6] = -90
    speakerAz[7] = 150
    speakerAz[8] = -150
elsif resolvedPreset = 11
    presetName$ = "8_ring"
    numSpeakers = 8
    for i from 1 to 8
        speakerAz[i] = (i - 1) * 360 / 8
    endfor
elsif resolvedPreset = 12
    presetName$ = "12_ring"
    numSpeakers = 12
    for i from 1 to 12
        speakerAz[i] = (i - 1) * 360 / 12
    endfor
elsif resolvedPreset = 13
    presetName$ = "16_ring"
    numSpeakers = 16
    for i from 1 to 16
        speakerAz[i] = (i - 1) * 360 / 16
    endfor
elsif resolvedPreset = 14
    presetName$ = "7.1.4"
    numSpeakers = 12
    speakerAz[1] = 30
    speakerAz[2] = -30
    speakerAz[3] = 0
    speakerIsLFE[4] = 1
    speakerAz[5] = 90
    speakerAz[6] = -90
    speakerAz[7] = 150
    speakerAz[8] = -150
    speakerAz[9] = 45
    speakerAz[10] = -45
    speakerAz[11] = 135
    speakerAz[12] = -135
    for i from 9 to 12
        speakerEl[i] = 45
    endfor
else
    presetName$ = "22.2"
    numSpeakers = 24
    # NHK / Spat channel order, ambiX convention (+azimuth = left).
    speakerAz[1] = 45
    speakerAz[2] = -45
    speakerAz[3] = 0
    speakerIsLFE[4] = 1
    speakerAz[5] = 135
    speakerAz[6] = -135
    speakerAz[7] = 30
    speakerAz[8] = -30
    speakerAz[9] = 180
    speakerIsLFE[10] = 1
    speakerAz[11] = 90
    speakerAz[12] = -90
    speakerAz[13] = 45
    speakerAz[14] = -45
    speakerAz[15] = 0
    speakerAz[16] = 0
    speakerAz[17] = 135
    speakerAz[18] = -135
    speakerAz[19] = 90
    speakerAz[20] = -90
    speakerAz[21] = 180
    speakerAz[22] = 0
    speakerAz[23] = 45
    speakerAz[24] = -45
    for i from 13 to 21
        speakerEl[i] = 45
    endfor
    speakerEl[16] = 90
    speakerEl[22] = -30
    speakerEl[23] = -30
    speakerEl[24] = -30
endif

# Directional speaker bookkeeping
numDirectional = 0
numLFE = 0
horizontal = 1
for spk from 1 to numSpeakers
    if speakerIsLFE[spk]
        numLFE += 1
    else
        numDirectional += 1
        dirSpk[numDirectional] = spk
        if abs (speakerEl[spk]) > 1e-9
            horizontal = 0
        endif
    endif
endfor

# ============================================================
# REAL SH MATRIX + ACTUAL MATRIX RANK
# ============================================================
for r from 1 to numDirectional
    spk = dirSpk[r]
    @computeACN: speakerAz[spk], speakerEl[spk], order
    for ch from 1 to expectedChannels
        rawSH[spk, ch] = acn[ch]
        rankM[r, ch] = acn[ch]
    endfor
endfor

rankTol = 1e-9
matrixRank = 0
pivotRow = 1
for rankCol from 1 to expectedChannels
    bestRow = 0
    bestAbs = 0
    for r from pivotRow to numDirectional
        av = abs (rankM[r, rankCol])
        if av > bestAbs
            bestAbs = av
            bestRow = r
        endif
    endfor
    if bestRow > 0 and bestAbs > rankTol
        if bestRow <> pivotRow
            for c from 1 to expectedChannels
                tmp = rankM[pivotRow, c]
                rankM[pivotRow, c] = rankM[bestRow, c]
                rankM[bestRow, c] = tmp
            endfor
        endif
        piv = rankM[pivotRow, rankCol]
        for c from rankCol to expectedChannels
            rankM[pivotRow, c] = rankM[pivotRow, c] / piv
        endfor
        for r from 1 to numDirectional
            if r <> pivotRow
                fac = rankM[r, rankCol]
                if abs (fac) > rankTol
                    for c from rankCol to expectedChannels
                        rankM[r, c] = rankM[r, c] - fac * rankM[pivotRow, c]
                    endfor
                endif
            endif
        endfor
        matrixRank += 1
        pivotRow += 1
    endif
endfor
fullRank = matrixRank = expectedChannels
lostComponents = expectedChannels - matrixRank

# ============================================================
# DECODE METHOD ORDER WEIGHTS
# ============================================================
for n from 0 to order
    orderWeight[n + 1] = 1
endfor
if decode_method = 2
    rE = cos (137.9 / (order + 1.51) * pi / 180)
    legP[1] = 1
    if order >= 1
        legP[2] = rE
    endif
    for n from 2 to order
        legP[n + 1] = ((2 * n - 1) * rE * legP[n] - (n - 1) * legP[n - 1]) / n
    endfor
    for n from 0 to order
        orderWeight[n + 1] = legP[n + 1]
    endfor
elsif decode_method = 3
    @factorial: order
    fN = factorialResult
    @factorial: order + 1
    fNp1 = factorialResult
    for n from 0 to order
        @factorial: order + n + 1
        fA = factorialResult
        @factorial: order - n
        fB = factorialResult
        orderWeight[n + 1] = fN * fNp1 / (fA * fB)
    endfor
endif

if decode_method = 1
    methodName$ = "basic"
elsif decode_method = 2
    methodName$ = "maxrE"
else
    methodName$ = "inphase"
endif

# Projection/sampling decoder. For irregular layouts this is an approximation;
# rank tells whether the geometry can span the Full-3D component space at all.
for spk from 1 to numSpeakers
    for ch from 1 to expectedChannels
        coeff[spk, ch] = 0
    endfor
    if not speakerIsLFE[spk]
        for ch from 1 to expectedChannels
            n = ch - 1
            componentOrder = floor (sqrt (n))
            coeff[spk, ch] = rawSH[spk, ch] * (2 * componentOrder + 1) * orderWeight[componentOrder + 1] / numDirectional
        endfor
    endif
endfor

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== Higher-Order Ambisonic Decoder ==="
appendInfoLine: "Input:      ", inputName$
appendInfoLine: "Format:     ", orderName$, " order, ", expectedChannels, " ch ACN/SN3D"
appendInfoLine: "Layout:     ", presetName$, "  (", numSpeakers, " output ch; ", numDirectional, " directional; ", numLFE, " LFE)"
if fullRank
    rankInfo$ = "  (full rank)"
else
    rankInfo$ = "  -- " + string$ (lostComponents) + " component dimension(s) not reproducible"
endif
appendInfoLine: "Rank:       ", matrixRank, " / ", expectedChannels, rankInfo$
if horizontal
    appendInfoLine: "Geometry:   horizontal; Full-3D vertical modes cannot all be reconstructed."
endif
appendInfoLine: "Method:     ", methodName$, " sampling/projection"
if resolvedPreset = 14 or resolvedPreset = 15
    appendInfoLine: "Note:       irregular 3D array; projection is approximate even when the geometry is full rank."
endif
appendInfoLine: ""

# ============================================================
# DECODE TO SPEAKER FEEDS
# ============================================================
for spk from 1 to numSpeakers
    selectObject: ambiChannel[1]
    speakerSound[spk] = Copy: "Speaker_" + string$ (spk)
    selectObject: speakerSound[spk]
    Formula: "0"
    if not speakerIsLFE[spk]
        for ch from 1 to expectedChannels
            c = coeff[spk, ch]
            if abs (c) > 1e-15
                Formula: "self + " + fixed$ (c, 12) + " * object[" + string$ (ambiChannel[ch]) + ", 1, col]"
            endif
        endfor
    endif
endfor

# ============================================================
# SHARED PEAK PROTECTION
# ============================================================
globalPeak = 0
for spk from 1 to numSpeakers
    selectObject: speakerSound[spk]
    pk = Get absolute extremum: 0, 0, "None"
    globalPeak = max (globalPeak, pk)
endfor
protectDb = 0
if peak_protect_only and globalPeak > 0.99
    sf = 0.99 / globalPeak
    protectDb = 20 * log10 (sf)
    for spk from 1 to numSpeakers
        selectObject: speakerSound[spk]
        Formula: "self * " + fixed$ (sf, 12)
    endfor
endif
if protectDb < 0
    peakInfo$ = " -> shared protection " + fixed$ (protectDb, 2) + " dB"
else
    peakInfo$ = " (no attenuation needed)"
endif
appendInfoLine: "Peak:       ", fixed$ (globalPeak, 6), peakInfo$

# ============================================================
# COMBINE OUTPUT
# ============================================================
selectObject: speakerSound[1]
for spk from 2 to numSpeakers
    plusObject: speakerSound[spk]
endfor
result = Combine to stereo
selectObject: result
Rename: "AmbiDecode_HOA" + string$ (order) + "_" + presetName$ + "_" + methodName$
finalDur = Get total duration
finalChannels = Get number of channels
for spk from 1 to numSpeakers
    removeObject: speakerSound[spk]
endfor

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 6.3
    Select inner viewport: 0.5, 7.5, 0.05, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Higher-Order Ambisonic Decoder##"
    Font size: 7
    Colour: "{0.35,0.35,0.52}"
    Text: 0.5, "centre", 0.18, "half", "HOA " + string$ (order) + " ACN/SN3D -> " + presetName$ + "   |   rank " + string$ (matrixRank) + "/" + string$ (expectedChannels)

    # speaker map: radius = cos(elevation), so top/bottom project inward
    Select inner viewport: 0.6, 3.8, 0.95, 4.15
    Axes: -1.35, 1.35, -1.35, 1.35
    Paint rectangle: "{0.97,0.97,0.97}", -1.35, 1.35, -1.35, 1.35
    Colour: "{0.82,0.82,0.82}"
    Draw circle: 0, 0, 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    for spk from 1 to numSpeakers
        if speakerIsLFE[spk]
            Colour: "{0.55,0.55,0.60}"
            Text: 0, "centre", 0, "half", "LFE"
        else
            rr = cos (speakerEl[spk] * pi / 180)
            px = -rr * sin (speakerAz[spk] * pi / 180)
            py = rr * cos (speakerAz[spk] * pi / 180)
            if abs (speakerEl[spk]) < 1e-9
                Paint circle (mm): "{0.20,0.48,0.75}", px, py, 2.5
            else
                Colour: "{0.85,0.38,0.18}"
                Draw circle (mm): px, py, 2.5
            endif
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "##Speaker geometry##   filled = horizontal, outline = elevated/lower"

    # decoder row norms
    maxNorm = 1e-12
    for spk from 1 to numSpeakers
        ss = 0
        for ch from 1 to expectedChannels
            ss += coeff[spk, ch] * coeff[spk, ch]
        endfor
        rowNorm[spk] = sqrt (ss)
        maxNorm = max (maxNorm, rowNorm[spk])
    endfor
    Select inner viewport: 4.35, 7.55, 0.95, 4.15
    Axes: 0.5, numSpeakers + 0.5, 0, maxNorm * 1.2
    Paint rectangle: "{0.97,0.97,0.97}", 0.5, numSpeakers + 0.5, 0, maxNorm * 1.2
    for spk from 1 to numSpeakers
        Paint rectangle: "{0.35,0.50,0.68}", spk - 0.35, spk + 0.35, 0, rowNorm[spk]
    endfor
    Colour: "Black"
    Draw inner box
    Text bottom: "yes", "Output channel"
    Text left: "yes", "Decoder row norm"
    Font size: 8
    Text top: "no", "##Decoder weights##"

    Select inner viewport: 0.6, 7.55, 4.7, 5.8
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "{0.25,0.25,0.35}"
    Font size: 7
    Text: 0.02, "left", 0.76, "half", "##Input:## HOA " + string$ (order) + " (" + string$ (expectedChannels) + " components)   |   ##Method:## " + methodName$
    Text: 0.02, "left", 0.46, "half", "##Layout:## " + presetName$ + "   |   directional " + string$ (numDirectional) + "   |   LFE " + string$ (numLFE)
    if horizontal
        geomInfo$ = "   |   horizontal geometry"
    else
        geomInfo$ = "   |   3D geometry"
    endif
    Text: 0.02, "left", 0.16, "half", "##Matrix rank:## " + string$ (matrixRank) + "/" + string$ (expectedChannels) + geomInfo$
    Colour: "Black"
    Draw inner box
endif

# ============================================================
# PLAY / CLEANUP
# ============================================================
if play_result
    selectObject: result
    Play
endif

if fromCombined
    for ch from 1 to expectedChannels
        removeObject: ambiChannel[ch]
    endfor
endif
selectObject: result
appendInfoLine: ""
appendInfoLine: "Decoding complete: ", selected$ ("Sound"), " (", finalChannels, " ch, ", fixed$ (finalDur, 3), " s)."
if not fullRank
    appendInfoLine: "WARNING: the chosen geometry is rank-deficient for this Full-3D order; output is an approximation with unreproducible component dimensions."
endif

# ============================================================
# PROCEDURES
# ============================================================
procedure computeACN: .azDeg, .elDeg, .maxOrder
    .az = .azDeg * pi / 180
    .x = sin (.elDeg * pi / 180)
    .ce = cos (.elDeg * pi / 180)
    for .i from 1 to 36
        acn[.i] = 0
    endfor
    for .l from 0 to .maxOrder
        for .m from 0 to .maxOrder
            assocP[.l + 1, .m + 1] = 0
        endfor
    endfor
    assocP[1, 1] = 1
    for .m from 1 to .maxOrder
        assocP[.m + 1, .m + 1] = (2 * .m - 1) * .ce * assocP[.m, .m]
    endfor
    for .m from 0 to .maxOrder - 1
        assocP[.m + 2, .m + 1] = (2 * .m + 1) * .x * assocP[.m + 1, .m + 1]
    endfor
    for .m from 0 to .maxOrder
        for .l from .m + 2 to .maxOrder
            assocP[.l + 1, .m + 1] = ((2 * .l - 1) * .x * assocP[.l, .m + 1] - (.l + .m - 1) * assocP[.l - 1, .m + 1]) / (.l - .m)
        endfor
    endfor
    for .l from 0 to .maxOrder
        .idx0 = .l * .l + .l + 1
        acn[.idx0] = assocP[.l + 1, 1]
        for .m from 1 to .l
            .ratio = 1
            for .k from .l - .m + 1 to .l + .m
                .ratio = .ratio / .k
            endfor
            .norm = sqrt (2 * .ratio)
            .base = .norm * assocP[.l + 1, .m + 1]
            .idxPos = .l * .l + .l + .m + 1
            .idxNeg = .l * .l + .l - .m + 1
            acn[.idxPos] = .base * cos (.m * .az)
            acn[.idxNeg] = .base * sin (.m * .az)
        endfor
    endfor
endproc

procedure factorial: .n
    factorialResult = 1
    if .n >= 2
        for .k from 2 to .n
            factorialResult *= .k
        endfor
    endif
endproc
