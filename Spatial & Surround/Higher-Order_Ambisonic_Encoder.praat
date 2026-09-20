# ============================================================
# Praat AudioTools - Higher-Order Ambisonic Encoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Purpose
#   Encode either:
#     (1) one point source, or
#     (2) an existing multichannel loudspeaker bed
#   to Full-3D ambiX B-format (ACN / SN3D), orders 1..5.
#
# Speaker-bed mode is a RE-ENCODING of loudspeaker feeds as fixed point
# sources at the selected speaker directions. It is not an inverse decoder
# and does not claim to reconstruct a B-format master that may have existed
# before a previous loudspeaker decode.
#
# LFE policy
#   Ambisonics has no directional LFE component. LFE feeds can either be
#   ignored (default) or added to ACN0/W only as an omnidirectional LF bed.
#
# Coordinate convention
#   ambiX: azimuth CCW from front (+X), +Y = left, +Z = up.
#   0 front, +90 left, +/-180 back, -90/right = 270 degrees.
#
# Generic SN3D engine
#   Real spherical harmonics are generated recursively up to order 5.
#   ACN index n = l(l+1)+m, file order ACN0..ACN35.
# ============================================================

form Ambisonic Encoder
    comment Input interpretation
    optionmenu Input_mode: 1
        option "Point source (mono position; multichannel input is summed)"
        option "Multichannel speaker bed (each channel has a speaker direction)"
    comment ─────────────────────────────────────────
    comment Point-source position (ignored in Speaker-bed mode)
    optionmenu Position_preset: 1
        option "Custom"
        option "Front center (0 deg, 0 deg)"
        option "Front left (+45 deg, 0 deg)"
        option "Left (+90 deg, 0 deg)"
        option "Rear left (+135 deg, 0 deg)"
        option "Rear center (180 deg, 0 deg)"
        option "Rear right (-135 deg, 0 deg)"
        option "Right (-90 deg, 0 deg)"
        option "Front right (-45 deg, 0 deg)"
        option "Above front (0 deg, +45 deg)"
        option "Above (0 deg, +90 deg)"
        option "Below (0 deg, -45 deg)"
    real Azimuth_degrees 0
    real Elevation_degrees 0
    real Distance_meters 1.0
    real Reference_distance_meters 1.0
    comment ─────────────────────────────────────────
    comment Speaker-bed layout (ignored in Point-source mode)
    optionmenu Speaker_layout: 1
        option "Auto from channel count (ring-first for 8 / 12 / 16 ch)"
        option "2.0 stereo (L,R)"
        option "4.0 quad (FL,FR,RL,RR)"
        option "5.0 (L,R,C,Ls,Rs)"
        option "5.1 (L,R,C,LFE,Ls,Rs)"
        option "7.0 (L,R,C,Ls,Rs,Lb,Rb)"
        option "7.1 (L,R,C,LFE,Ls,Rs,Lb,Rb)"
        option "8-channel horizontal ring (ch1 = front, CCW)"
        option "7.1.4 (L,R,C,LFE,Ls,Rs,Lb,Rb,TpFL,TpFR,TpBL,TpBR)"
        option "12-channel horizontal ring (ch1 = front, CCW)"
        option "16-channel horizontal ring (ch1 = front, CCW)"
        option "22.2 (NHK / Spat channel order)"
        option "Even horizontal ring (use all input channels)"
    optionmenu Lfe_handling: 1
        option "Ignore LFE (recommended)"
        option "Add LFE to ACN0 / W only"
    comment ─────────────────────────────────────────
    optionmenu Ambisonic_order: 1
        option "1st order (4 channels)"
        option "2nd order (9 channels)"
        option "3rd order (16 channels)"
        option "4th order (25 channels)"
        option "5th order (36 channels)"
    optionmenu Output_format: 2
        option "Individual ACN channels"
        option "Combined multichannel B-format"
        option "Both"
    optionmenu Mode: 1
        option "General encoder"
        option "Fixed-media submission (3rd-order ambiX, combined WAV)"
    boolean Peak_protect_only 1
    boolean Verify_encoding 1
    boolean Save_wav 0
    text Wav_folder
    boolean Draw_visualization 1
    boolean Play_result 0
endform

clearinfo

# ============================================================
# GLOBAL FORMAT RULES
# ============================================================
if mode = 2
    if input_mode <> 1
        exitScript: "Fixed-media submission mode is defined for a point source. Use General encoder for a speaker bed."
    endif
    ambisonic_order = 3
    output_format = 2
    save_wav = 1
    verify_encoding = 1
    peak_protect_only = 1
endif

# ============================================================
# INPUT
# ============================================================
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
original = selected ("Sound")
originalName$ = selected$ ("Sound")
selectObject: original
nChannelsOrig = Get number of channels
duration = Get total duration
sr = Get sampling frequency
numSamples = Get number of samples
if numSamples <= 0
    exitScript: "The selected Sound contains no samples."
endif

# Order -> number of ACN channels
order = ambisonic_order
numChannels = (order + 1) ^ 2
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

for ch from 1 to 36
    channelLabel$[ch] = "ACN" + string$ (ch - 1)
endfor

# ============================================================
# POINT-SOURCE PRESET
# ============================================================
if position_preset = 2
    azimuth_degrees = 0
    elevation_degrees = 0
    presetName$ = "front"
elsif position_preset = 3
    azimuth_degrees = 45
    elevation_degrees = 0
    presetName$ = "front_left"
elsif position_preset = 4
    azimuth_degrees = 90
    elevation_degrees = 0
    presetName$ = "left"
elsif position_preset = 5
    azimuth_degrees = 135
    elevation_degrees = 0
    presetName$ = "rear_left"
elsif position_preset = 6
    azimuth_degrees = 180
    elevation_degrees = 0
    presetName$ = "rear"
elsif position_preset = 7
    azimuth_degrees = -135
    elevation_degrees = 0
    presetName$ = "rear_right"
elsif position_preset = 8
    azimuth_degrees = -90
    elevation_degrees = 0
    presetName$ = "right"
elsif position_preset = 9
    azimuth_degrees = -45
    elevation_degrees = 0
    presetName$ = "front_right"
elsif position_preset = 10
    azimuth_degrees = 0
    elevation_degrees = 45
    presetName$ = "above_front"
elsif position_preset = 11
    azimuth_degrees = 0
    elevation_degrees = 90
    presetName$ = "above"
elsif position_preset = 12
    azimuth_degrees = 0
    elevation_degrees = -45
    presetName$ = "below"
else
    presetName$ = "custom"
endif
while azimuth_degrees < -180
    azimuth_degrees += 360
endwhile
while azimuth_degrees > 180
    azimuth_degrees -= 360
endwhile
elevation_degrees = max (-90, min (90, elevation_degrees))
if distance_meters <= 0
    distance_meters = 0.001
endif
if reference_distance_meters <= 0
    reference_distance_meters = 1.0
endif

# ============================================================
# SPEAKER-BED LAYOUT
# ============================================================
numBedSpeakers = 0
numLFE = 0
layoutName$ = ""
for i from 1 to max (64, nChannelsOrig)
    bedAz[i] = 0
    bedEl[i] = 0
    bedIsLFE[i] = 0
endfor

if input_mode = 2
    resolvedLayout = speaker_layout
    if speaker_layout = 1
        if nChannelsOrig = 2
            resolvedLayout = 2
        elsif nChannelsOrig = 4
            resolvedLayout = 3
        elsif nChannelsOrig = 5
            resolvedLayout = 4
        elsif nChannelsOrig = 6
            resolvedLayout = 5
        elsif nChannelsOrig = 7
            resolvedLayout = 6
        elsif nChannelsOrig = 8
            # Ambiguous with 7.1. Auto deliberately uses the all-directional
            # 8-speaker ring; choose 7.1 explicitly when channel 4 is LFE.
            resolvedLayout = 8
        elsif nChannelsOrig = 12
            # Ambiguous with 7.1.4. Auto deliberately uses the all-directional
            # 12-speaker ring; choose 7.1.4 explicitly when channel 4 is LFE.
            resolvedLayout = 10
        elsif nChannelsOrig = 16
            resolvedLayout = 11
        elsif nChannelsOrig = 24
            resolvedLayout = 12
        else
            exitScript: "No built-in Auto layout for " + string$ (nChannelsOrig) + " channels. Choose Even horizontal ring or a named layout explicitly."
        endif
    endif

    if speaker_layout = 1 and (nChannelsOrig = 8 or nChannelsOrig = 12)
        appendInfoLine: "Auto layout policy: ", nChannelsOrig, " channels -> ", if nChannelsOrig = 8 then "8-ring" else "12-ring" fi, ". Choose the cinema layout explicitly if the file contains LFE."
    endif

    if resolvedLayout = 2
        layoutName$ = "2.0"
        expectedBedChannels = 2
        bedAz[1] = 30
        bedAz[2] = -30
    elsif resolvedLayout = 3
        layoutName$ = "4.0 quad"
        expectedBedChannels = 4
        bedAz[1] = 45
        bedAz[2] = -45
        bedAz[3] = 135
        bedAz[4] = -135
    elsif resolvedLayout = 4
        layoutName$ = "5.0"
        expectedBedChannels = 5
        bedAz[1] = 30
        bedAz[2] = -30
        bedAz[3] = 0
        bedAz[4] = 110
        bedAz[5] = -110
    elsif resolvedLayout = 5
        layoutName$ = "5.1"
        expectedBedChannels = 6
        bedAz[1] = 30
        bedAz[2] = -30
        bedAz[3] = 0
        bedIsLFE[4] = 1
        bedAz[5] = 110
        bedAz[6] = -110
    elsif resolvedLayout = 6
        layoutName$ = "7.0"
        expectedBedChannels = 7
        bedAz[1] = 30
        bedAz[2] = -30
        bedAz[3] = 0
        bedAz[4] = 90
        bedAz[5] = -90
        bedAz[6] = 150
        bedAz[7] = -150
    elsif resolvedLayout = 7
        layoutName$ = "7.1"
        expectedBedChannels = 8
        bedAz[1] = 30
        bedAz[2] = -30
        bedAz[3] = 0
        bedIsLFE[4] = 1
        bedAz[5] = 90
        bedAz[6] = -90
        bedAz[7] = 150
        bedAz[8] = -150
    elsif resolvedLayout = 8
        layoutName$ = "8-ring"
        expectedBedChannels = 8
        for i from 1 to 8
            bedAz[i] = (i - 1) * 360 / 8
        endfor
    elsif resolvedLayout = 9
        layoutName$ = "7.1.4"
        expectedBedChannels = 12
        bedAz[1] = 30
        bedAz[2] = -30
        bedAz[3] = 0
        bedIsLFE[4] = 1
        bedAz[5] = 90
        bedAz[6] = -90
        bedAz[7] = 150
        bedAz[8] = -150
        bedAz[9] = 45
        bedAz[10] = -45
        bedAz[11] = 135
        bedAz[12] = -135
        for i from 9 to 12
            bedEl[i] = 45
        endfor
    elsif resolvedLayout = 10
        layoutName$ = "12-ring"
        expectedBedChannels = 12
        for i from 1 to 12
            bedAz[i] = (i - 1) * 360 / 12
        endfor
    elsif resolvedLayout = 11
        layoutName$ = "16-ring"
        expectedBedChannels = 16
        for i from 1 to 16
            bedAz[i] = (i - 1) * 360 / 16
        endfor
    elsif resolvedLayout = 12
        layoutName$ = "22.2"
        expectedBedChannels = 24
        # NHK / Spat channel order. ambiX sign convention: +azimuth = left.
        bedAz[1] = 45
        bedAz[2] = -45
        bedAz[3] = 0
        bedIsLFE[4] = 1
        bedAz[5] = 135
        bedAz[6] = -135
        bedAz[7] = 30
        bedAz[8] = -30
        bedAz[9] = 180
        bedIsLFE[10] = 1
        bedAz[11] = 90
        bedAz[12] = -90
        bedAz[13] = 45
        bedAz[14] = -45
        bedAz[15] = 0
        bedAz[16] = 0
        bedAz[17] = 135
        bedAz[18] = -135
        bedAz[19] = 90
        bedAz[20] = -90
        bedAz[21] = 180
        bedAz[22] = 0
        bedAz[23] = 45
        bedAz[24] = -45
        for i from 13 to 21
            bedEl[i] = 45
        endfor
        bedEl[16] = 90
        bedEl[22] = -30
        bedEl[23] = -30
        bedEl[24] = -30
    else
        layoutName$ = "even_" + string$ (nChannelsOrig) + "_ring"
        expectedBedChannels = nChannelsOrig
        if nChannelsOrig < 2 or nChannelsOrig > 64
            exitScript: "Even horizontal ring supports 2..64 input channels."
        endif
        for i from 1 to nChannelsOrig
            bedAz[i] = (i - 1) * 360 / nChannelsOrig
        endfor
    endif

    if nChannelsOrig <> expectedBedChannels
        exitScript: "Speaker-bed layout " + layoutName$ + " expects " + string$ (expectedBedChannels) + " channels, but the selected Sound has " + string$ (nChannelsOrig) + "."
    endif
    numBedSpeakers = nChannelsOrig
    for i from 1 to numBedSpeakers
        if bedIsLFE[i]
            numLFE += 1
        endif
    endfor
endif

# ============================================================
# SELF-TEST OF GENERIC SN3D ENGINE
# ============================================================
if verify_encoding
    stFail = 0
    @computeACN: 0, 0, 5
    @stCheck: "Front ACN0", acn[1], 1
    @stCheck: "Front ACN3 (X)", acn[4], 1
    @stCheck: "Front ACN1 (Y)", acn[2], 0
    @stCheck: "Front ACN2 (Z)", acn[3], 0
    @computeACN: 90, 0, 5
    @stCheck: "Left ACN1 (Y)", acn[2], 1
    @computeACN: -90, 0, 5
    @stCheck: "Right ACN1 (Y)", acn[2], -1
    @computeACN: 0, 90, 5
    @stCheck: "Above ACN2 (Z)", acn[3], 1
    @computeACN: 37, 24, 5
    @stSumSq: "order 1 sum-sq", 2, 4
    @stSumSq: "order 2 sum-sq", 5, 9
    @stSumSq: "order 3 sum-sq", 10, 16
    @stSumSq: "order 4 sum-sq", 17, 25
    @stSumSq: "order 5 sum-sq", 26, 36
    if stFail > 0
        exitScript: "Encoding self-test failed (" + string$ (stFail) + " check(s))."
    endif
endif

# ============================================================
# INFO HEADER
# ============================================================
writeInfoLine: "=== Higher-Order Ambisonic Encoder ==="
appendInfoLine: "Input:      ", originalName$, "  (", nChannelsOrig, " ch, ", fixed$ (duration, 3), " s @ ", sr, " Hz)"
appendInfoLine: "Output:     ambiX ACN/SN3D, ", orderName$, " order, ", numChannels, " channels"
if input_mode = 1
    appendInfoLine: "Mode:       point source"
    appendInfoLine: "Position:   az ", fixed$ (azimuth_degrees, 1), " deg, el ", fixed$ (elevation_degrees, 1), " deg"
    appendInfoLine: "Distance:   ", fixed$ (distance_meters, 3), " m (reference ", fixed$ (reference_distance_meters, 3), " m)"
    if nChannelsOrig > 1
        appendInfoLine: "WARNING:    input is summed to mono before point-source encoding."
    endif
else
    appendInfoLine: "Mode:       multichannel speaker-bed re-encoding"
    appendInfoLine: "Layout:     ", layoutName$, "  (", numBedSpeakers, " input feeds, ", numLFE, " LFE)"
    if lfe_handling = 1
        lfeInfo$ = "ignored"
    else
        lfeInfo$ = "added to ACN0/W only"
    endif
    appendInfoLine: "LFE:        ", lfeInfo$
    appendInfoLine: "Note:       this represents the loudspeaker feeds as fixed sources; it is not an inverse decoder."
endif
appendInfoLine: ""

# ============================================================
# CREATE AMBISONIC CHANNELS
# ============================================================
for ch from 1 to numChannels
    selectObject: original
    ambiChannel[ch] = Extract one channel: 1
    selectObject: ambiChannel[ch]
    Rename: originalName$ + "_" + channelLabel$[ch]
    Formula: "0"
endfor

if input_mode = 1
    selectObject: original
    if nChannelsOrig > 1
        workSound = Convert to mono
    else
        workSound = Copy: "__hoa_point_source"
    endif
    distanceGain = reference_distance_meters / distance_meters
    @computeACN: azimuth_degrees, elevation_degrees, order
    for ch from 1 to numChannels
        g = acn[ch] * distanceGain
        if abs (g) > 1e-15
            selectObject: ambiChannel[ch]
            Formula: "self + " + fixed$ (g, 12) + " * object[" + string$ (workSound) + ", 1, col]"
        endif
    endfor
    removeObject: workSound
else
    for spk from 1 to numBedSpeakers
        if bedIsLFE[spk]
            if lfe_handling = 2
                selectObject: ambiChannel[1]
                Formula: "self + object[" + string$ (original) + ", " + string$ (spk) + ", col]"
            endif
        else
            @computeACN: bedAz[spk], bedEl[spk], order
            for ch from 1 to numChannels
                g = acn[ch]
                if abs (g) > 1e-15
                    selectObject: ambiChannel[ch]
                    Formula: "self + " + fixed$ (g, 12) + " * object[" + string$ (original) + ", " + string$ (spk) + ", col]"
                endif
            endfor
        endif
    endfor
endif

# ============================================================
# SHARED PEAK PROTECTION
# ============================================================
globalPeak = 0
for ch from 1 to numChannels
    selectObject: ambiChannel[ch]
    pk = Get absolute extremum: 0, 0, "None"
    globalPeak = max (globalPeak, pk)
endfor
protectDb = 0
if peak_protect_only and globalPeak > 0.99
    scaleFactor = 0.99 / globalPeak
    protectDb = 20 * log10 (scaleFactor)
    for ch from 1 to numChannels
        selectObject: ambiChannel[ch]
        Formula: "self * " + fixed$ (scaleFactor, 12)
    endfor
endif
if protectDb < 0
    peakInfo$ = "  -> shared protection " + fixed$ (protectDb, 2) + " dB"
else
    peakInfo$ = "  (no shared attenuation needed)"
endif
appendInfoLine: "Peak:       ", fixed$ (globalPeak, 6), peakInfo$

# ============================================================
# COMBINED OUTPUT
# ============================================================
combinedResult = 0
if output_format >= 2
    selectObject: ambiChannel[1]
    for ch from 2 to numChannels
        plusObject: ambiChannel[ch]
    endfor
    combinedResult = Combine to stereo
    selectObject: combinedResult
    if input_mode = 1
        Rename: originalName$ + "_ambiX_HOA" + string$ (order) + "_" + presetName$
    else
        Rename: originalName$ + "_ambiX_HOA" + string$ (order) + "_from_" + layoutName$
    endif
endif

# ============================================================
# WAV EXPORT (combined output only)
# ============================================================
if save_wav
    if combinedResult = 0
        appendInfoLine: "WAV:        not saved (Combined multichannel output is required)."
    else
        outFolder$ = wav_folder$
        if outFolder$ = ""
            outFolder$ = homeDirectory$
        endif
        createFolder: outFolder$
        wavBase$ = originalName$ + "_HOA" + string$ (order) + "_ambiX_ACN_SN3D"
        wavPath$ = outFolder$ + "/" + wavBase$ + ".wav"
        dupN = 0
        while fileReadable (wavPath$)
            dupN += 1
            wavPath$ = outFolder$ + "/" + wavBase$ + "_" + string$ (dupN) + ".wav"
        endwhile
        selectObject: combinedResult
        Save as 24-bit WAV file: wavPath$
        savedSamples = Get number of samples
        savedSr = Get sampling frequency
        check = Read from file: wavPath$
        chkCh = Get number of channels
        chkSr = Get sampling frequency
        chkSamples = Get number of samples
        removeObject: check
        if chkCh <> numChannels or chkSr <> savedSr or chkSamples <> savedSamples
            deleteFile: wavPath$
            if mode = 2
                exitScript: "WAV validation failed; the non-conformant file was deleted."
            else
                appendInfoLine: "WAV:        validation FAILED; file deleted."
            endif
        else
            appendInfoLine: "WAV:        ", wavPath$
            appendInfoLine: "            validated ", chkCh, " ch @ ", chkSr, " Hz, ", chkSamples, " samples (24-bit PCM)"
        endif
    endif
endif

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 6.2
    Font size: 12
    Select inner viewport: 0.5, 7.5, 0.05, 0.5
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Higher-Order Ambisonic Encoder##"
    Font size: 7
    Colour: "{0.35,0.35,0.52}"
    if input_mode = 1
        vizMode$ = "Point source -> "
    else
        vizMode$ = layoutName$ + " speaker bed -> "
    endif
    Text: 0.5, "centre", 0.18, "half", vizMode$ + "HOA " + string$ (order) + " ambiX ACN/SN3D"

    # spatial map
    Select inner viewport: 0.6, 3.8, 0.9, 4.1
    Axes: -1.35, 1.35, -1.35, 1.35
    Paint rectangle: "{0.97,0.97,0.97}", -1.35, 1.35, -1.35, 1.35
    Colour: "{0.82,0.82,0.82}"
    Draw circle: 0, 0, 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    if input_mode = 1
        rr = cos (elevation_degrees * pi / 180)
        px = -rr * sin (azimuth_degrees * pi / 180)
        py = rr * cos (azimuth_degrees * pi / 180)
        Paint circle (mm): "{0.20,0.48,0.75}", px, py, 3
    else
        for spk from 1 to numBedSpeakers
            if not bedIsLFE[spk]
                rr = cos (bedEl[spk] * pi / 180)
                px = -rr * sin (bedAz[spk] * pi / 180)
                py = rr * cos (bedAz[spk] * pi / 180)
                Paint circle (mm): "{0.20,0.48,0.75}", px, py, 2.2
            endif
        endfor
    endif
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "##Input geometry##"

    # output component peaks
    peakMax = 1e-12
    for ch from 1 to numChannels
        selectObject: ambiChannel[ch]
        outPk[ch] = Get absolute extremum: 0, 0, "None"
        peakMax = max (peakMax, outPk[ch])
    endfor
    Select inner viewport: 4.35, 7.55, 0.9, 4.1
    Axes: 0.5, numChannels + 0.5, 0, peakMax * 1.15
    Paint rectangle: "{0.97,0.97,0.97}", 0.5, numChannels + 0.5, 0, peakMax * 1.15
    for ch from 1 to numChannels
        Paint rectangle: "{0.35,0.50,0.68}", ch - 0.35, ch + 0.35, 0, outPk[ch]
    endfor
    Colour: "Black"
    Draw inner box
    Text bottom: "yes", "ACN channel"
    Text left: "yes", "Peak"
    Font size: 8
    Text top: "no", "##Encoded component peaks##"

    # summary
    Select inner viewport: 0.6, 7.55, 4.65, 5.75
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "{0.25,0.25,0.35}"
    Font size: 7
    Text: 0.02, "left", 0.76, "half", "##Output:## " + string$ (numChannels) + " ch ACN/SN3D   |   order " + string$ (order)
    if input_mode = 1
        vizInput$ = "point source at az " + fixed$ (azimuth_degrees, 1) + ", el " + fixed$ (elevation_degrees, 1)
    else
        vizInput$ = layoutName$ + " (" + string$ (numBedSpeakers) + " feeds)"
    endif
    Text: 0.02, "left", 0.46, "half", "##Input:## " + vizInput$
    if protectDb < 0
        vizProtect$ = fixed$ (protectDb, 2) + " dB shared attenuation"
    else
        vizProtect$ = "none"
    endif
    Text: 0.02, "left", 0.16, "half", "##Peak protection:## " + vizProtect$
    Colour: "Black"
    Draw inner box
endif

# ============================================================
# PLAY / CLEANUP / FINAL SELECTION
# ============================================================
if play_result
    if combinedResult <> 0
        selectObject: combinedResult
        audition = Extract one channel: 1
        Play
        removeObject: audition
    else
        selectObject: ambiChannel[1]
        Play
    endif
endif

if output_format = 2
    for ch from 1 to numChannels
        removeObject: ambiChannel[ch]
    endfor
    selectObject: combinedResult
elsif output_format = 3
    selectObject: combinedResult
else
    selectObject: ambiChannel[1]
    for ch from 2 to numChannels
        plusObject: ambiChannel[ch]
    endfor
endif

appendInfoLine: ""
appendInfoLine: "Encoding complete."
appendInfoLine: "Convention: ACN channel order, SN3D normalization, Full 3D."
if input_mode = 2
    appendInfoLine: "Speaker-bed result is a re-encoding of the loudspeaker feeds, not an inverse-decode reconstruction."
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

procedure stCheck: .label$, .got, .expect
    if abs (.got - .expect) > 1e-7
        stFail += 1
        appendInfoLine: "SELF-TEST FAIL: ", .label$, " got ", fixed$ (.got, 9), " expected ", fixed$ (.expect, 9)
    endif
endproc

procedure stSumSq: .label$, .from, .to
    .ss = 0
    for .j from .from to .to
        .ss += acn[.j] * acn[.j]
    endfor
    @stCheck: .label$, .ss, 1
endproc
