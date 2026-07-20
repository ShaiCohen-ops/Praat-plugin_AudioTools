# ============================================================
# Praat AudioTools - Higher-Order Ambisonic Encoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - ambiX submission hardening
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Higher-Order Ambisonic (HOA) Encoder
#   Encodes a mono source into B-format ambisonic channels
#   Supports 1st, 2nd, and 3rd order ambisonics (ACN/SN3D)
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   Submission-mode hardening (so an invalid file truly cannot be produced):
#   - Submission mode now also forces Peak_protect_only (a close source can
#     no longer clip on save).
#   - A failed encoding self-test now ABORTS (before any channels/WAV are
#     created), instead of warning and continuing.
#   - WAV validation now compares the exact sample count; on any failure the
#     non-conformant file is deleted, and submission mode aborts. The report
#     states conformance is by construction (no ambisonic metadata is read
#     back from the WAV).
#   - Output folder: empty default resolves to the home directory (Windows-
#     safe, unlike /tmp); the folder is created if missing and an existing
#     file is never overwritten (auto _1, _2, ... suffix).
#   - Direct playback now warns it is not ambisonic decoding and auditions
#     only the omni (ACN0) channel.
#
# Changelog v0.3:
#   Ambisonic correctness + ambiX submission support.
#   - FIX (math): 3rd-order SN3D coefficients for ACN 9/11/13/15 were
#     low by 1/sqrt(2) (used sqrt5/4, sqrt3/4). Corrected to sqrt(5/8),
#     sqrt(3/8). Verified against the SN3D identity (per-order sum of
#     squares = 1 in every direction).
#   - FIX (convention): presets/labels/visualization now use the ambiX
#     azimuth convention (CCW from front, +Y = left): Left = 90 deg,
#     Right = 270 deg. The encoding formula (Y = sin az cos el) was
#     already correct; the presets were mirrored.
#   - Channels named explicitly ACN0..ACN15 (file order is exactly ACN
#     0..N-1); Furse-Malham letters kept as secondary labels.
#   - Submission mode: hard-locks 3rd-order / 16 ch / ACN / SN3D /
#     Full 3D / combined multichannel / WAV save, so an invalid file
#     cannot be produced.
#   - WAV export + validation: writes the combined file and re-reads it
#     to confirm channel count, sample rate, and duration.
#   - Self-test: checks reference directions and the SN3D identity every
#     run (toggle), sharing the coefficient math with the encoder.
#   - Distance vs level: replaced normalize-to-0.99 (which cancelled the
#     distance gain) with attenuate-only peak protection (shared factor,
#     reported headroom), preserving SN3D ratios and distance level.
#   - Prominent warning when a multichannel input is downmixed to a point.
#   Not yet included (future): multi-source bed accumulation, moving
#   sources / trajectories, 5th order (36 ch), 24-bit/float WAV export.
#
# Changelog v0.2:
#   - Modern selectObject: syntax throughout
#   - Added output format option (individual or combined multichannel)
#   - Array storage for channel objects and coefficients
#   - Robust formula string building
#   - Improved visualization with elevation indicator
#   - Added play_result toggle
#   - Better preset organization
#   - Proper cleanup of temporary objects
# ============================================================

# ============================================================
# FORM
# ============================================================

form Ambisonic Encoder
    comment Source Position
    comment ─────────────────────────────────────────
    optionmenu Position_preset: 1
        option Custom
        option Front center (0°, 0°)
        option Front left (45°, 0°)
        option Left (90°, 0°)
        option Rear left (135°, 0°)
        option Rear center (180°, 0°)
        option Rear right (225°, 0°)
        option Right (270°, 0°)
        option Front right (315°, 0°)
        option Above front (0°, 45°)
        option Above (0°, 90°)
        option Below (0°, -45°)
    comment ─────────────────────────────────────────
    real Azimuth_(degrees_0-360) 0
    real Elevation_(degrees_-90_to_90) 0
    real Distance_(meters) 1.0
    real Reference_distance_(meters) 1.0
    comment ─────────────────────────────────────────
    optionmenu Ambisonic_order: 1
        option 1st order (4 channels)
        option 2nd order (9 channels)
        option 3rd order (16 channels)
    comment ─────────────────────────────────────────
    optionmenu Output_format: 1
        option Individual channels (W, Y, Z, X, ...)
        option Combined multichannel B-format
        option Both
    comment ─────────────────────────────────────────
    optionmenu Mode: 1
        option General encoder
        option Fixed-media submission (3rd-order ambiX, 16ch)
    comment ─────────────────────────────────────────
    boolean Peak_protect_only 1
    boolean Verify_encoding 1
    boolean Save_wav 0
    text Wav_folder
    boolean Draw_visualization 1
    boolean Play_result 0
endform

clearinfo

# ============================================================
# SUBMISSION MODE — hard-lock a valid HOA3 ambiX configuration
# ============================================================
# In submission mode the format is forced so an invalid file cannot be produced:
# 3rd order (16 ch), ACN 0..15, SN3D, Full 3D, combined multichannel, WAV saved.
if mode = 2
    ambisonic_order = 3
    output_format = 2
    save_wav = 1
    verify_encoding = 1
    peak_protect_only = 1
endif

# ============================================================
# PRESET SYSTEM
# ============================================================

if position_preset = 2
    # Front center
    azimuth = 0
    elevation = 0
    presetName$ = "front"
elsif position_preset = 3
    # Front left
    azimuth = 45
    elevation = 0
    presetName$ = "front_left"
elsif position_preset = 4
    # Left
    azimuth = 90
    elevation = 0
    presetName$ = "left"
elsif position_preset = 5
    # Rear left
    azimuth = 135
    elevation = 0
    presetName$ = "rear_left"
elsif position_preset = 6
    # Rear center
    azimuth = 180
    elevation = 0
    presetName$ = "rear"
elsif position_preset = 7
    # Rear right
    azimuth = 225
    elevation = 0
    presetName$ = "rear_right"
elsif position_preset = 8
    # Right
    azimuth = 270
    elevation = 0
    presetName$ = "right"
elsif position_preset = 9
    # Front right
    azimuth = 315
    elevation = 0
    presetName$ = "front_right"
elsif position_preset = 10
    # Above front
    azimuth = 0
    elevation = 45
    presetName$ = "above_front"
elsif position_preset = 11
    # Above
    azimuth = 0
    elevation = 90
    presetName$ = "above"
elsif position_preset = 12
    # Below
    azimuth = 0
    elevation = -45
    presetName$ = "below"
else
    # Custom
    presetName$ = "custom"
endif

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
nChannelsOrig = Get number of channels
duration = Get total duration
sr = Get sampling frequency

# Convert to mono if needed. This is a POINT-SOURCE encoder: a stereo/multichannel
# input is downmixed to one mono signal and placed at a single direction, so the
# original stereo image is collapsed. This is warned about prominently below.
if nChannelsOrig > 1
    selectObject: original
    workSound = Convert to mono
    wasStereo = 1
else
    selectObject: original
    workSound = Copy: "work_temp"
    wasStereo = 0
endif

# Validate distance
if distance <= 0
    distance = 0.001
endif
if reference_distance <= 0
    reference_distance = 1.0
endif

# Normalize azimuth to 0-360
while azimuth < 0
    azimuth = azimuth + 360
endwhile
while azimuth >= 360
    azimuth = azimuth - 360
endwhile

# Clamp elevation
if elevation > 90
    elevation = 90
elsif elevation < -90
    elevation = -90
endif

# Determine number of channels
if ambisonic_order = 1
    numChannels = 4
    orderName$ = "1st"
elsif ambisonic_order = 2
    numChannels = 9
    orderName$ = "2nd"
else
    numChannels = 16
    orderName$ = "3rd"
endif

# Channel names: explicit ACN indices (unambiguous for object selection,
# combining, file inspection, and interop with other ambisonic tools). The
# file channel order is exactly ACN 0..(numChannels-1). Historical Furse-Malham
# letters (W,Y,Z,X,...) are kept only as a secondary label for readability.
channelLabel$[1]  = "ACN0"
channelLabel$[2]  = "ACN1"
channelLabel$[3]  = "ACN2"
channelLabel$[4]  = "ACN3"
channelLabel$[5]  = "ACN4"
channelLabel$[6]  = "ACN5"
channelLabel$[7]  = "ACN6"
channelLabel$[8]  = "ACN7"
channelLabel$[9]  = "ACN8"
channelLabel$[10] = "ACN9"
channelLabel$[11] = "ACN10"
channelLabel$[12] = "ACN11"
channelLabel$[13] = "ACN12"
channelLabel$[14] = "ACN13"
channelLabel$[15] = "ACN14"
channelLabel$[16] = "ACN15"
traditional$[1]  = "W"
traditional$[2]  = "Y"
traditional$[3]  = "Z"
traditional$[4]  = "X"
traditional$[5]  = "V"
traditional$[6]  = "T"
traditional$[7]  = "R"
traditional$[8]  = "S"
traditional$[9]  = "U"
traditional$[10] = "Q"
traditional$[11] = "O"
traditional$[12] = "M"
traditional$[13] = "K"
traditional$[14] = "L"
traditional$[15] = "N"
traditional$[16] = "P"

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Higher-Order Ambisonic Encoder v0.4"
writeInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
if wasStereo
    appendInfoLine: "  WARNING: multichannel input downmixed to mono and placed"
    appendInfoLine: "           at ONE direction -- the original image is collapsed."
endif
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Source position:"
appendInfoLine: "  Azimuth: ", fixed$(azimuth, 1), "°"
appendInfoLine: "  Elevation: ", fixed$(elevation, 1), "°"
appendInfoLine: "  Distance: ", fixed$(distance, 2), " m"
appendInfoLine: "  Reference: ", fixed$(reference_distance, 2), " m"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Ambisonic order: ", orderName$, " (", numChannels, " channels)"
appendInfoLine: "Output format: ", if output_format = 1 then "Individual" else if output_format = 2 then "Combined" else "Both" fi fi
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# CALCULATE ENCODING COEFFICIENTS
# ============================================================

appendInfoLine: "Calculating encoding coefficients..."

# Distance attenuation (inverse distance law)
distanceGain = reference_distance / distance
distanceGain_dB = 20 * log10(distanceGain)

appendInfoLine: "  Distance gain: ", fixed$(distanceGain, 4), " (", fixed$(distanceGain_dB, 1), " dB)"

# Convert to radians (kept for the visualization further down)
azRad = azimuth * pi / 180
elRad = elevation * pi / 180

# Compute the 16 ACN/SN3D coefficients via the shared procedure (defined at the
# end of the script and also exercised by the self-test).
@computeACN: azimuth, elevation
for ch from 1 to 16
    coeff[ch] = acn[ch]
endfor

# Display coefficients
appendInfoLine: ""
appendInfoLine: "Encoding coefficients:"
for ch from 1 to numChannels
    appendInfoLine: "  ", channelLabel$[ch], ": ", fixed$(coeff[ch], 6)
endfor
appendInfoLine: ""

# ============================================================
# SELF-TEST (SN3D reference directions + normalization identity)
# ============================================================
if verify_encoding
    appendInfoLine: "Self-test (SN3D reference directions)..."
    stFail = 0
    @computeACN: 0, 0
    @stCheck: "Front  ACN0 (W)", acn[1], 1.0
    @stCheck: "Front  ACN3 (X)", acn[4], 1.0
    @stCheck: "Front  ACN1 (Y)", acn[2], 0.0
    @stCheck: "Front  ACN2 (Z)", acn[3], 0.0
    @computeACN: 90, 0
    @stCheck: "Left   ACN1 (Y)", acn[2], 1.0
    @stCheck: "Left   ACN3 (X)", acn[4], 0.0
    @computeACN: 270, 0
    @stCheck: "Right  ACN1 (Y)", acn[2], -1.0
    @computeACN: 0, 90
    @stCheck: "Above  ACN2 (Z)", acn[3], 1.0
    # SN3D identity: per-order sum of squares = 1 in every direction
    @computeACN: 37, 24
    @stSumSq: "order 1 sum-sq", 2, 4
    @stSumSq: "order 2 sum-sq", 5, 9
    @stSumSq: "order 3 sum-sq", 10, 16
    if stFail = 0
        appendInfoLine: "  Self-test: PASS"
    else
        appendInfoLine: "  Self-test: ", stFail, " FAILURE(S)"
        exitScript: "Encoding self-test failed (", stFail, " check(s)). No channels or WAV were created."
    endif
    appendInfoLine: ""
endif

# ============================================================
# ENCODE: CREATE AMBISONIC CHANNELS
# ============================================================

appendInfoLine: "Encoding ambisonic channels..."

for ch from 1 to numChannels
    # Calculate final gain (coefficient * distance attenuation)
    finalGain = coeff[ch] * distanceGain
    gainStr$ = fixed$(finalGain, 10)
    
    # Create channel
    selectObject: workSound
    ambiChannel[ch] = Copy: originalName$ + "_" + channelLabel$[ch]
    
    selectObject: ambiChannel[ch]
    Formula: "self * " + gainStr$
    
    appendInfoLine: "  Channel ", ch, " (", channelLabel$[ch], "): gain = ", fixed$(finalGain, 6)
endfor

appendInfoLine: ""

# ============================================================
# NORMALIZE (if requested)
# ============================================================

if peak_protect_only
    appendInfoLine: "Peak protection (attenuate-only)..."
    
    # Find global peak across all channels
    globalPeak = 0
    for ch from 1 to numChannels
        selectObject: ambiChannel[ch]
        peak = Get absolute extremum: 0, 0, "None"
        if peak > globalPeak
            globalPeak = peak
        endif
    endfor
    
    # Only attenuate if we would clip. A shared factor across ALL channels
    # preserves the SN3D inter-channel ratios AND the distance relationship
    # (normalizing weak output up to 0.99 would erase the distance gain, since
    # distanceGain is a single scalar applied to every channel).
    if globalPeak > 0.99
        scaleFactor = 0.99 / globalPeak
        headroom_dB = 20 * log10(scaleFactor)
        scaleStr$ = fixed$(scaleFactor, 10)
        for ch from 1 to numChannels
            selectObject: ambiChannel[ch]
            Formula: "self * " + scaleStr$
        endfor
        appendInfoLine: "  Global peak: ", fixed$(globalPeak, 4)
        appendInfoLine: "  Headroom adjustment: ", fixed$(headroom_dB, 1), " dB (shared across all channels)"
    else
        appendInfoLine: "  Global peak: ", fixed$(globalPeak, 4), " (no attenuation needed)"
    endif
    
    appendInfoLine: ""
endif

# ============================================================
# CREATE COMBINED OUTPUT (if requested)
# ============================================================

if output_format >= 2
    appendInfoLine: "Creating combined multichannel B-format..."
    
    selectObject: ambiChannel[1]
    for ch from 2 to numChannels
        plusObject: ambiChannel[ch]
    endfor
    
    combinedResult = Combine to stereo
    selectObject: combinedResult
    Rename: originalName$ + "_Bformat_" + orderName$ + "_" + presetName$
    
    appendInfoLine: "  Created: ", selected$("Sound")
    appendInfoLine: ""
endif

# ============================================================
# CLEANUP INDIVIDUAL CHANNELS (if only combined output)
# ============================================================

if output_format = 2
    # Remove individual channels, keep only combined
    for ch from 1 to numChannels
        removeObject: ambiChannel[ch]
    endfor
endif

# Clean up work sound
removeObject: workSound

# ============================================================
# WAV EXPORT + VALIDATION (re-reads the file actually written)
# ============================================================
if save_wav and output_format >= 2
    # Resolve a writable output folder. Empty -> home directory (exists and is
    # writable on every OS, unlike a hard-coded /tmp on Windows). createFolder
    # is idempotent, so this also guarantees the folder exists.
    outFolder$ = wav_folder$
    if outFolder$ = ""
        outFolder$ = homeDirectory$
    endif
    createFolder: outFolder$

    wavName$ = originalName$ + "_HOA" + string$(ambisonic_order) + "_ambiX_ACN_SN3D"
    wavPath$ = outFolder$ + "/" + wavName$ + ".wav"
    # Avoid clobbering an existing file: append _1, _2, ... if needed.
    dupN = 0
    while fileReadable(wavPath$)
        dupN = dupN + 1
        wavPath$ = outFolder$ + "/" + wavName$ + "_" + string$(dupN) + ".wav"
    endwhile

    # Samples-per-channel we are about to write (exact reference for validation).
    selectObject: combinedResult
    savedSamples = Get number of samples

    Save as WAV file: wavPath$
    appendInfoLine: "Saved WAV: ", wavPath$

    # Re-read and validate the bytes actually on disk, not just the Praat object.
    reread = Read from file: wavPath$
    selectObject: reread
    vCh = Get number of channels
    vSr = Get sampling frequency
    vDur = Get total duration
    vSamp = Get number of samples

    appendInfoLine: ""
    appendInfoLine: "Validation report:"
    appendInfoLine: "  File: ", wavPath$
    appendInfoLine: "  Channels: ", vCh, "  (expected ", numChannels, ")"
    appendInfoLine: "  Sample rate: ", vSr, " Hz"
    appendInfoLine: "  Duration: ", fixed$(vDur, 4), " s"
    appendInfoLine: "  Samples/channel: ", vSamp, "  (expected ", savedSamples, ")"
    appendInfoLine: "  Channel order: ACN 0..", numChannels - 1
    appendInfoLine: "  Encoding convention: generated as ACN/SN3D"
    appendInfoLine: "    (the WAV carries no ambisonic metadata; conformance is by construction,"
    appendInfoLine: "     confirmed by the self-test above, not read back from the file)"
    if ambisonic_order = 3
        appendInfoLine: "  Target: ambiX (3rd order, Full 3D, 16 ch)"
    endif
    appendInfoLine: "  Format: 16-bit linear WAV (Praat). Use Python/soundfile if 24-bit or float is required."

    vPass = 1
    if vCh <> numChannels
        vPass = 0
    endif
    if vSr <> sr
        vPass = 0
    endif
    if vSamp <> savedSamples
        vPass = 0
    endif
    removeObject: reread

    if vPass = 1
        appendInfoLine: "  Validation: PASS"
        appendInfoLine: ""
    else
        appendInfoLine: "  Validation: FAIL (channel/rate/sample-count mismatch)"
        # A file that failed validation must not masquerade as a submission.
        deleteFile: wavPath$
        appendInfoLine: "  Deleted the non-conformant file."
        if mode = 2
            exitScript: "Submission WAV validation failed; the file was deleted."
        endif
        appendInfoLine: ""
    endif
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Ambisonic Encoder##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... originalName$ + "  |  " + orderName$ + " order (" + string$(numChannels) + " ch)"
        ... + "  |  az=" + fixed$(azimuth, 0) + "°  el=" + fixed$(elevation, 0) + "°"
        ... + "  |  d=" + fixed$(distance, 2) + "m"

    # ----------------------------------------------------------
    # Top-down view — azimuth (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.52, 3.52
    Select inner viewport: 0.45, 3.95, 0.62, 3.40

    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.5, 1.5, -1.5, 1.5

    # Distance circles
    Colour: "{0.86, 0.86, 0.86}"
    Line width: 1
    maxDist = max(distance, 1) * 1.2
    for r from 1 to 4
        radius = r / 4 * maxDist
        if radius <= 1.3
            Draw circle: 0, 0, radius
        endif
    endfor

    # Crosshairs
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 0, -1.4, 0, 1.4
    Draw line: -1.4, 0, 1.4, 0
    Dotted line
    Draw line: -1, -1, 1, 1
    Draw line: -1, 1, 1, -1
    Solid line

    # Direction labels
    Font size: 6
    Colour: "{0.50, 0.50, 0.50}"
    Text: 0.08, "left", 1.38, "half", "0° Front"
    Text: 0.08, "left", -1.38, "half", "180° Rear"
    Text: -1.42, "right", -0.12, "half", "90° Left"
    Text: 1.42, "left", -0.12, "half", "270° Right"

    # Listener
    Paint circle (mm): "{0.35, 0.35, 0.35}", 0, 0, 2.5

    # Source arrow + marker
    displayDist = min(distance, maxDist) / maxDist * 1.2
    # ambiX: +Y = left. Screen X increases to the right, so negate sin(az) to
    # put a left source (az=90) on the left of the plot.
    srcX = -displayDist * sin(azRad)
    srcY = displayDist * cos(azRad)
    Colour: "{0.82, 0.28, 0.28}"
    Line width: 2
    Draw arrow: 0, 0, srcX, srcY

    markerSize = 2.5 + abs(elevation) / 90 * 1.5
    if elevation >= 0
        Paint circle (mm): "{0.90, 0.30, 0.30}", srcX, srcY, markerSize
    else
        Colour: "{0.90, 0.30, 0.30}"
        Draw circle (mm): srcX, srcY, markerSize
    endif

    Font size: 5
    Colour: "{0.60, 0.22, 0.22}"
    if srcY >= 0
        Text: srcX, "centre", srcY + 0.16, "half", "Src"
    else
        Text: srcX, "centre", srcY - 0.16, "half", "Src"
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Top view (azimuth)  •=filled above horizon  ○=below"

    # ----------------------------------------------------------
    # Side view — elevation (right, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.52, 2.22
    Select inner viewport: 4.50, 7.65, 0.62, 2.10

    Axes: -0.2, 1.5, -1.2, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -0.2, 1.5, -1.2, 1.2

    # Horizon
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 0, 0, 1.4, 0

    # Elevation arc
    Colour: "{0.86, 0.86, 0.86}"
    Dotted line
    for a from -90 to 90
        aRad = a * pi / 180
        x1 = cos(aRad)
        y1 = sin(aRad)
        if a > -90
            Draw line: prevArcX, prevArcY, x1, y1
        endif
        prevArcX = x1
        prevArcY = y1
    endfor
    Solid line

    Font size: 6
    Colour: "{0.50, 0.50, 0.50}"
    Text: -0.08, "right", 1.05, "half", "+90°"
    Text: -0.08, "right", -1.05, "half", "-90°"
    Text: 1.25, "centre", 0.12, "half", "0°"

    # Listener
    Paint circle (mm): "{0.35, 0.35, 0.35}", 0, 0, 2

    # Source in side view
    sideX = displayDist * cos(elRad)
    sideY = displayDist * sin(elRad)
    Colour: "{0.82, 0.28, 0.28}"
    Line width: 2
    Draw arrow: 0, 0, sideX, sideY
    Paint circle (mm): "{0.90, 0.30, 0.30}", sideX, sideY, 2.5
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Side view (elevation)"

    # ----------------------------------------------------------
    # Coefficient bar chart (right, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.30, 3.52
    Select inner viewport: 4.50, 7.65, 2.40, 3.40

    maxCoeff = 0
    for ch from 1 to numChannels
        if abs(coeff[ch]) > maxCoeff
            maxCoeff = abs(coeff[ch])
        endif
    endfor
    if maxCoeff < 0.01
        maxCoeff = 1
    endif
    cTop = maxCoeff * 1.2

    Axes: 0.3, numChannels + 0.7, -cTop, cTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.3, numChannels + 0.7, -cTop, cTop

    # Zero line
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0.3, 0, numChannels + 0.7, 0

    for ch from 1 to numChannels
        c = coeff[ch]
        if c >= 0
            barCol$ = "{0.35, 0.58, 0.78}"
        else
            barCol$ = "{0.78, 0.48, 0.35}"
        endif
        Paint rectangle: barCol$, ch - 0.30, ch + 0.30, 0, c
        Font size: 5
        Colour: "{0.35, 0.35, 0.35}"
        Text: ch, "centre", -cTop * 0.92, "half", channelLabel$[ch]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Coeff"
    Text top: "no", "Encoding coefficients (ACN/SN3D)"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.62, 4.42
    Select inner viewport: 0.45, 7.65, 3.68, 4.36
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    # Build coefficient list
    coeffList$ = ""
    for ch from 1 to numChannels
        if ch > 1
            coeffList$ = coeffList$ + "  "
        endif
        coeffList$ = coeffList$ + channelLabel$[ch] + "=" + fixed$(coeff[ch], 3)
    endfor

    Text: 0.02, "left", 0.55, "half",
        ... "Order: " + orderName$ + "  (" + string$(numChannels) + " ch)"
        ... + "  |  Az: " + fixed$(azimuth, 1) + "°"
        ... + "  |  El: " + fixed$(elevation, 1) + "°"
        ... + "  |  Dist: " + fixed$(distance, 2) + "m"
        ... + "  |  Gain: " + fixed$(distanceGain_dB, 1) + " dB"
    Text: 0.02, "left", 0.22, "half",
        ... "Coefficients:  " + coeffList$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

appendInfoLine: "============================================"
appendInfoLine: "ENCODING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Position: az=", fixed$(azimuth, 1), "°, el=", fixed$(elevation, 1), "°, dist=", fixed$(distance, 2), "m"
appendInfoLine: "Order: ", orderName$, " (", numChannels, " channels)"
appendInfoLine: ""

if output_format = 1
    appendInfoLine: "Output: ", numChannels, " individual channel sounds"
    appendInfoLine: "Channels created:"
    for ch from 1 to numChannels
        selectObject: ambiChannel[ch]
        appendInfoLine: "  ", selected$("Sound")
    endfor
    # Select all channels
    selectObject: ambiChannel[1]
    for ch from 2 to numChannels
        plusObject: ambiChannel[ch]
    endfor
elsif output_format = 2
    appendInfoLine: "Output: Combined multichannel B-format"
    selectObject: combinedResult
    appendInfoLine: "  ", selected$("Sound")
else
    appendInfoLine: "Output: Both individual and combined"
    appendInfoLine: "Individual channels:"
    for ch from 1 to numChannels
        selectObject: ambiChannel[ch]
        appendInfoLine: "  ", selected$("Sound")
    endfor
    selectObject: combinedResult
    appendInfoLine: "Combined: ", selected$("Sound")
    # Select combined as primary result
    selectObject: combinedResult
endif

appendInfoLine: ""
appendInfoLine: "Use with Ambisonic Decoder for speaker playback."

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    # Playing raw B-format is NOT ambisonic decoding (not binaural, not
    # loudspeaker-decoded). Only the omni ACN0 is meaningful to audition here;
    # use a proper decoder for spatial playback.
    appendInfoLine: ""
    appendInfoLine: "Note: direct playback is not ambisonic decoding. Playing ACN0 (omni) only;"
    appendInfoLine: "      use an ambisonic decoder for spatial/binaural monitoring."
    if output_format >= 2
        selectObject: combinedResult
        Extract one channel: 1
        playMono = selected("Sound")
        Play
        removeObject: playMono
    else
        selectObject: ambiChannel[1]
        Play
    endif
endif

# Final selection
if output_format >= 2
    selectObject: combinedResult
else
    selectObject: ambiChannel[1]
    for ch from 2 to numChannels
        plusObject: ambiChannel[ch]
    endfor
endif
# ============================================================
# PROCEDURES
# ============================================================

# Compute the 16 ACN/SN3D encoding coefficients for a direction (degrees).
# Writes global acn[1..16] (acn[1]=ACN0 ... acn[16]=ACN15). Shared by the main
# encode and the self-test so both exercise the same math.
# Convention: azimuth CCW from front (+X), +Y = left, +Z = up.
procedure computeACN: .azDeg, .elDeg
    .az = .azDeg * pi / 180
    .el = .elDeg * pi / 180
    .ca = cos(.az)
    .sa = sin(.az)
    .ce = cos(.el)
    .se = sin(.el)
    .ce2 = .ce * .ce
    .se2 = .se * .se
    .c2a = cos(2 * .az)
    .s2a = sin(2 * .az)
    .c3a = cos(3 * .az)
    .s3a = sin(3 * .az)
    acn[1]  = 1.0
    acn[2]  = .sa * .ce
    acn[3]  = .se
    acn[4]  = .ca * .ce
    acn[5]  = sqrt(3) * .s2a * .ce2 * 0.5
    acn[6]  = sqrt(3) * .sa * .se * .ce
    acn[7]  = 0.5 * (3 * .se2 - 1)
    acn[8]  = sqrt(3) * .ca * .se * .ce
    acn[9]  = sqrt(3) * .c2a * .ce2 * 0.5
    acn[10] = sqrt(5/8) * .s3a * .ce * .ce2
    acn[11] = sqrt(15) * .s2a * .se * .ce2 * 0.5
    acn[12] = sqrt(3/8) * .sa * .ce * (5 * .se2 - 1)
    acn[13] = 0.5 * .se * (5 * .se2 - 3)
    acn[14] = sqrt(3/8) * .ca * .ce * (5 * .se2 - 1)
    acn[15] = sqrt(15) * .c2a * .se * .ce2 * 0.5
    acn[16] = sqrt(5/8) * .c3a * .ce * .ce2
endproc

# Assert one coefficient equals an expected value (increments global stFail).
procedure stCheck: .label$, .got, .expect
    if abs(.got - .expect) < 0.0005
        appendInfoLine: "  [PASS] ", .label$, " = ", fixed$(.got, 3)
    else
        appendInfoLine: "  [FAIL] ", .label$, " = ", fixed$(.got, 3), " (expected ", fixed$(.expect, 3), ")"
        stFail = stFail + 1
    endif
endproc

# Assert the SN3D per-order sum of squares equals 1 (increments global stFail).
procedure stSumSq: .label$, .from, .to
    .ss = 0
    for .k from .from to .to
        .ss = .ss + acn[.k] * acn[.k]
    endfor
    if abs(.ss - 1.0) < 0.001
        appendInfoLine: "  [PASS] ", .label$, " = ", fixed$(.ss, 4)
    else
        appendInfoLine: "  [FAIL] ", .label$, " = ", fixed$(.ss, 4), " (expected 1.0)"
        stFail = stFail + 1
    endif
endproc
