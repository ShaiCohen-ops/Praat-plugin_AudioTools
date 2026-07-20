# ============================================================
# Praat AudioTools - Spatial Trajectory Painter
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Ambisonic trajectory output
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spatial Trajectory Painter
#   Convert a Sound to mono, then draw a curve directly on the
#   waveform (a PitchTier opened together with the sound). The mono
#   signal follows that curve over time and is rendered to one of
#   two output representations (Output_representation):
#
#   SPEAKER ARRAY (original mode) - the mono signal is panned across
#     N output channels (4/6/8/12/16) by equal-power gains (cos/sin
#     crossfade) that follow the drawn curve.
#
#   AMBISONIC TRAJECTORY (new in v0.5) - the drawn curve is converted
#     to a time-varying azimuth instead of a channel position, and the
#     mono signal is encoded directly into a moving ambiX (ACN/SN3D)
#     B-format signal of 4 / 9 / 16 channels (1st / 2nd / 3rd order).
#     No intermediate speaker-channel stage is used: the same drawn
#     trajectory is mapped straight to spherical-harmonic gains at
#     every control frame, so the drawn motion is encoded directly
#     into the ambisonic domain at the selected control rate (gains
#     are linearly interpolated between control frames, so encoding
#     is exact at each frame and an approximation in between -- raise
#     Control_rate for fast movement). Elevation and distance are
#     held constant; only azimuth moves.
#
#   Both representations share the same drawing interface, the same
#   two-phase workflow, and the same Relative/Absolute mapping choice:
#
#   RELATIVE (default) - the min and max of whatever you drew are
#     stretched to fill the whole output range: the full channel array
#     for Speaker array, or one full 360 degree turn for Ambisonic
#     trajectory. Convenient: draw anything, it always uses the full
#     range. A flat curve sits in the middle (array centre, or a fixed
#     azimuth) of that range.
#
#   ABSOLUTE - a fixed scale, meaning depends on the representation:
#     Speaker array: channel_position =
#       (drawn_value - Base_value) / Step_value + 1, e.g. with
#       Base=100, Step=100: 100 Hz -> ch.1, 200 Hz -> ch.2, ...
#     Ambisonic trajectory: the drawn value IS the azimuth in degrees
#       directly (e.g. 90 -> 90 deg), wrapped to 0-360.
#     Useful when you want precise, repeatable control, or motion
#     confined to a small region. A flat curve stays exactly where
#     you drew it.
#
# Topology (Speaker array only):
#   Line (default) - position is clamped to [channel 1 ... channel N].
#   Ring - position wraps around a full loop: going past the last
#          channel brings you back toward channel 1.
#   (Ambisonic trajectory is inherently circular: azimuth always wraps
#   at 360 degrees, regardless of this setting.)
#
# Usage:
#   PHASE 1 - Select 1 Sound -> Run -> a mono copy is made and an
#             editor opens showing the waveform with an empty
#             PitchTier curve ("movement") on top.
#             Click at the desired time/height inside the CURVE
#             panel (not the waveform panel) to move the cursor
#             there, then press Ctrl-T (Cmd-T on Mac) to drop a
#             point. Repeat to draw the movement. One point is
#             enough for a fixed, static pan position / direction.
#   PHASE 2 - Back in the Objects window, select the MONO sound
#             (name ends in "_mono") AND the "movement" PitchTier
#             -> Run again -> the multichannel result is created
#             (N speaker channels, or 4/9/16 ambiX channels,
#             depending on Output_representation).
#             The mono sound and the movement PitchTier are removed
#             at the end of Phase 2 along with the other temporary
#             objects, leaving only the final multichannel result.
#             If you want to redraw and try again, re-run Phase 1
#             from the original source Sound.
#
# Relationship to the Higher-Order Ambisonic Encoder script:
#   That script remains a separate, dedicated STATIC point encoder
#   (mono source, one fixed azimuth/elevation/distance). This script
#   covers the moving case: a drawn trajectory rendered either as a
#   speaker pan or directly as a moving ambiX signal. Do not chain
#   this script's speaker-array output into the Ambisonic Encoder --
#   that would collapse the motion back down to a static direction.
#   The ACN/SN3D coefficient math used here in Ambisonic trajectory
#   mode is the same shared convention as that script (azimuth CCW
#   from front, +Y = left, +Z = up).
#
# Note: Phase 1 (mono conversion + editor opening) and Phase 2 (including
# the Copy + Formula channel-gain application via object(id, x), which
# replaced "Multiply" in v0.4 to avoid its silent 0.9-peak rescaling) have
# been run and confirmed working end-to-end for the Speaker array mode,
# including the visualization. The Ambisonic trajectory mode added in
# v0.5 reuses the exact same sampling / gain-tier / multiply / stack
# pipeline, substituting ACN/SN3D coefficients for speaker crossfade
# gains at each control frame.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
###############################################################################
# Spatial Trajectory Painter (Form-Based, Two-Phase)
#
# A. SETUP: Select 1 Sound -> Run -> mono copy + editor open for drawing.
# B. CREATE: Select mono Sound + PitchTier "movement" -> Run -> panned
#            or ambisonic output, per Output_representation.
###############################################################################

form Spatial Trajectory Painter Settings
    comment Output representation:
    optionmenu Output_representation: 1
        option Speaker array
        option Ambisonic trajectory (ambiX ACN/SN3D)

    comment Speaker array settings (used only when Output_representation = Speaker array):
    optionmenu Number_of_channels: 3
        option 4
        option 6
        option 8
        option 12
        option 16
    optionmenu Topology 1
        option Line (clamp at ends)
        option Ring (wrap around)

    comment Ambisonic settings (used only when Output_representation = Ambisonic trajectory):
    optionmenu Ambisonic_order: 1
        option First order (4 ch)
        option Second order (9 ch)
        option Third order (16 ch)
    real Elevation_(degrees) 0
    comment Distance controls inverse-distance amplitude attenuation only (no near-field compensation).
    positive Distance_(meters) 1.0
    real Trajectory_rotation_(degrees) 0

    comment Mapping mode (how the drawn height becomes a position):
    optionmenu Mapping_mode 1
        option Relative (fit drawn curve to full range)
        option Absolute (fixed height-to-position mapping)

    comment Absolute mode, Speaker array: value = Base_value means channel 1, +Step_value means channel 2, etc.
    comment Absolute mode, Ambisonic: the drawn value IS the azimuth in degrees directly (wrapped to 0-360).
    comment (Base_value / Step_value below apply to Speaker array only.)
    positive Base_value 100
    positive Step_value 100

    comment Control resolution for reading the drawn curve:
    positive Control_rate_(Hz) 100

    comment Output:
    word Output_name movement_output
    boolean Draw_visualization 1
endform

if output_representation = 1
    n_ch = number(number_of_channels$)
    orderName$ = ""
else
    if ambisonic_order = 1
        n_ch = 4
        orderName$ = "1st"
    elsif ambisonic_order = 2
        n_ch = 9
        orderName$ = "2nd"
    else
        n_ch = 16
        orderName$ = "3rd"
    endif
    # Clamp elevation to a valid range, same convention as the Ambisonic Encoder.
    if elevation > 90
        elevation = 90
    elsif elevation < -90
        elevation = -90
    endif
endif

# Channel / component labels, used for object names, legends, and info text.
for c to n_ch
    if output_representation = 1
        chLabel$[c] = "Ch" + string$(c)
    else
        chLabel$[c] = "ACN" + string$(c - 1)
    endif
endfor

###############################################################################
# WORKFLOW DETECTOR
###############################################################################

n_sounds = numberOfSelected("Sound")
n_tiers = numberOfSelected("PitchTier")

if n_sounds = 1 and n_tiers = 0
    # === PHASE 1: SETUP ===

    sound_in = selected("Sound")
    sound_name$ = selected$("Sound")
    xmin = Get start time
    xmax = Get end time

    selectObject: sound_in
    Convert to mono
    mono = selected("Sound")
    Rename: sound_name$ + "_mono"

    movement = Create PitchTier: "movement", xmin, xmax

    selectObject: mono
    plusObject: movement
    View & Edit

    writeInfoLine: "=== PHASE 1: EDITOR OPENED ==="
    appendInfoLine: "1. Click at the desired time/height INSIDE THE CURVE PANEL"
    appendInfoLine: "   (not the waveform panel) to position the cursor there."
    appendInfoLine: "2. Press Ctrl-T (Windows/Linux) or Cmd-T (Mac) to drop a point."
    appendInfoLine: "   Repeat to draw the movement. Drag existing points to reshape."
    if output_representation = 1
        appendInfoLine: "   Output: Speaker array ('n_ch' channels)."
        appendInfoLine: "   With Mapping_mode = Relative (default): whatever range you"
        appendInfoLine: "   draw is stretched to cover the whole channel array."
        appendInfoLine: "   With Mapping_mode = Absolute: 'base_value' = channel 1,"
        appendInfoLine: "   " + string$(base_value + step_value) + " = channel 2, etc. (fixed scale)."
    else
        appendInfoLine: "   Output: Ambisonic trajectory (" + orderName$ + " order, 'n_ch' ambiX channels)."
        appendInfoLine: "   With Mapping_mode = Relative (default): the drawn range maps to"
        appendInfoLine: "   one full 360-degree turn (plus Trajectory_rotation)."
        appendInfoLine: "   With Mapping_mode = Absolute: the drawn value IS the azimuth in"
        appendInfoLine: "   degrees directly (plus Trajectory_rotation), wrapped to 0-360 --"
        appendInfoLine: "   e.g. 360 wraps to the same as 0 (front), so there is no need to"
        appendInfoLine: "   draw all the way down to a height of 0 to reach front."
        appendInfoLine: "   Elevation and distance stay fixed at 'elevation:1' deg / 'distance:2' m."
    endif
    appendInfoLine: "3. Go back to the Objects window."
    appendInfoLine: "4. Select BOTH '" + sound_name$ + "_mono' AND 'movement'."
    appendInfoLine: "5. Run this script again."

    exitScript: "Phase 1 complete. Draw the curve, select both objects, and run again."

elsif n_sounds = 1 and n_tiers = 1
    # === PHASE 2: PROCESSING ===

    mono = selected("Sound")
    movement = selected("PitchTier")
    mono_name$ = selected$("Sound")

    # --- Safety checks ---
    selectObject: mono
    n_channels_check = Get number of channels
    if n_channels_check <> 1
        exitScript: "Error: the selected Sound must be mono (it has 'n_channels_check' channels). Run Phase 1 first."
    endif
    mono_xmin = Get start time
    mono_xmax = Get end time

    selectObject: movement
    tier_xmin = Get start time
    tier_xmax = Get end time
    if abs(tier_xmin - mono_xmin) > 0.001 or abs(tier_xmax - mono_xmax) > 0.001
        exitScript: "Error: the 'movement' tier's time domain does not match the Sound's. Use the tier created together with this Sound in Phase 1."
    endif

    n_points = Get number of points
    if n_points < 1
        exitScript: "Error: draw at least 1 point on the curve before running Phase 2."
    endif

    if output_representation = 1
        repName$ = "SPEAKER-ARRAY PAN"
    else
        repName$ = "AMBISONIC TRAJECTORY (" + orderName$ + " order)"
    endif

    writeInfoLine: "=== PHASE 2: GENERATING ", repName$, " ==="
    appendInfoLine: "Channels: 'n_ch'"
    appendInfoLine: "Points drawn: 'n_points'"
    if mapping_mode = 1
        appendInfoLine: "Mapping: Relative (fit to full range)"
    else
        if output_representation = 1
            appendInfoLine: "Mapping: Absolute (Base='base_value', Step='step_value')"
        else
            appendInfoLine: "Mapping: Absolute (drawn value = azimuth in degrees)"
        endif
    endif
    if output_representation = 2
        appendInfoLine: "Elevation: 'elevation:1' deg, Distance: 'distance:2' m, Rotation: 'trajectory_rotation:1' deg"
    endif

else
    exitScript: "SELECTION ERROR: To start, select 1 Sound. To finish, select the mono Sound AND the 'movement' PitchTier."
endif

###############################################################################
# MAIN LOGIC (Runs only in Phase 2)
###############################################################################

selectObject: mono
xmin = Get start time
xmax = Get end time
duration = xmax - xmin

# --- Relative mode: find the value range of the drawn points ---
if mapping_mode = 1
    selectObject: movement
    minVal = Get value at index: 1
    maxVal = minVal
    for i to n_points
        v = Get value at index: i
        if v < minVal
            minVal = v
        endif
        if v > maxVal
            maxVal = v
        endif
    endfor
    range = maxVal - minVal
endif

# --- Sample the drawn curve at a fixed control rate, map to a position ---
# Speaker array -> chanPos_frame[f] (channel position, 1..n_ch)
# Ambisonic trajectory -> azimuth_frame[f] (degrees, wrapped to 0-360)
n_frames = ceiling(duration * control_rate)
for f from 0 to n_frames
    t = xmin + f / control_rate
    if t > xmax
        t = xmax
    endif
    t_frame[f] = t

    selectObject: movement
    v = Get value at time: t

    if mapping_mode = 1
        # Relative: stretch the drawn range to fill the whole output range
        if range <> 0
            posNorm = (v - minVal) / range
        else
            posNorm = 0.5
        endif
        if posNorm < 0
            posNorm = 0
        elsif posNorm > 1
            posNorm = 1
        endif
    endif

    if output_representation = 1
        # --- Speaker array position ---
        if mapping_mode = 1
            if topology = 1
                chanPos_frame[f] = 1 + posNorm * (n_ch - 1)
            else
                chanPos_frame[f] = 1 + posNorm * n_ch
            endif
        else
            # Absolute: fixed scale
            chanPos_frame[f] = (v - base_value) / step_value + 1
        endif
    else
        # --- Ambisonic azimuth (degrees, always circular) ---
        if mapping_mode = 1
            az = posNorm * 360 + trajectory_rotation
        else
            az = v + trajectory_rotation
        endif
        az = az - 360 * floor(az / 360)
        azimuth_frame[f] = az
    endif
endfor

# --- Ambisonic trajectory: pre-compute ACN/SN3D coefficients at every frame ---
# distanceGain is inverse-distance AMPLITUDE attenuation only (matching the
# Higher-Order Ambisonic Encoder's convention with reference_distance = 1 m).
# It does not perform near-field compensation or encode any other physical
# distance cue.
if output_representation = 2
    if distance <= 0
        distance = 0.001
    endif
    distanceGain = 1 / distance
    for f from 0 to n_frames
        @computeACN: azimuth_frame[f], elevation
        for c to n_ch
            acnFrame[c,f] = acn[c] * distanceGain
        endfor
    endfor
endif

# --- Build one gain AmplitudeTier per output channel ---
# Speaker array: equal-power crossfade gain based on distance to chanPos.
# Ambisonic trajectory: pre-computed ACN/SN3D coefficient (can be negative).
for c to n_ch
    gainTier = Create AmplitudeTier: "gain" + string$(c), xmin, xmax
    for f from 0 to n_frames
        t = t_frame[f]

        if output_representation = 1
            chanPos = chanPos_frame[f]

            if topology = 1
                # Line: clamp at the ends
                if chanPos < 1
                    chanPos = 1
                elsif chanPos > n_ch
                    chanPos = n_ch
                endif
                dist = abs(chanPos - c)
            else
                # Ring: wrap around a full loop of n_ch channels
                chanWrapped = chanPos - n_ch * floor((chanPos - 1) / n_ch)
                rawdist = abs(chanWrapped - c)
                if rawdist > n_ch / 2
                    dist = n_ch - rawdist
                else
                    dist = rawdist
                endif
            endif

            if dist < 1
                gain = cos(dist * pi / 2)
            else
                gain = 0
            endif
        else
            gain = acnFrame[c,f]
        endif

        gainArr[c,f] = gain
        Add point: t, gain
    endfor
    gain_id[c] = gainTier
endfor

# --- Multiply the mono signal by each channel's gain envelope ---
# NOTE: we deliberately do NOT use the "Multiply" command here.
# Sound & AmplitudeTier: Multiply rescales its result to a peak of
# 0.9, independently for every channel -- which would destroy the
# equal-power balance (Speaker array) or the ACN/SN3D ratios
# (Ambisonic trajectory) we just computed. Instead we copy the mono
# sound and apply the gain with Formula, which edits samples in place
# with no rescaling.
for c to n_ch
    selectObject: mono
    Copy: chLabel$[c]
    ch_id[c] = selected("Sound")
    gid = gain_id[c]
    Formula: "self * object('gid', x)"
endfor

# --- Ambisonic trajectory: shared (attenuate-only) peak protection ---
# ACN/SN3D coefficients can add up to values above 1 (e.g. two components
# both near their peak at once), and small Distance values amplify that
# further via distanceGain. A single shared scale factor, found from the
# loudest sample across ALL HOA channels and applied equally to every
# channel, prevents clipping without touching the inter-channel ACN/SN3D
# ratios or the drawn direction -- the same approach the Higher-Order
# Ambisonic Encoder uses. (Not needed for Speaker array: each equal-power
# crossfade gain is already <= 1 there.)
if output_representation = 2
    globalPeak = 0
    for c to n_ch
        selectObject: ch_id[c]
        peak = Get absolute extremum: 0, 0, "None"
        if peak > globalPeak
            globalPeak = peak
        endif
    endfor
    if globalPeak > 0.99
        scaleFactor = 0.99 / globalPeak
        headroom_dB = 20 * log10(scaleFactor)
        scaleStr$ = fixed$(scaleFactor, 10)
        for c to n_ch
            selectObject: ch_id[c]
            Formula: "self * " + scaleStr$
        endfor
        appendInfoLine: "Peak protection: global peak was ", fixed$(globalPeak, 4), " -- applied ", fixed$(headroom_dB, 1), " dB (shared across all ", n_ch, " channels)."
    else
        appendInfoLine: "Peak protection: global peak ", fixed$(globalPeak, 4), " (no attenuation needed)."
    endif
endif

# --- Stack the channels into one multichannel Sound ---
for c to n_ch
    if c = 1
        selectObject: ch_id[c]
    else
        plusObject: ch_id[c]
    endif
endfor
result = Combine to stereo
Rename: output_name$

###############################################################################
# VISUALIZATION (optional)
#
# Draws an 8x8-canvas Picture-window overview of the movement, using the
# suite's standard outer-viewport-title / inner-viewport-data pattern (the
# small gap between each panel's outer and inner viewport is the title
# strip). Uses gainArr[c,f], captured above while the gain AmplitudeTiers
# were built, instead of re-querying the AmplitudeTier objects via
# object(id,x) -- that lookup pattern has been a recurring source of bugs
# elsewhere in this suite, so it's avoided here entirely.
#
# Speaker array: Panel B shows a speaker map (Line row / Ring circle).
# Ambisonic trajectory: Panel B shows a top-view (azimuth) path instead,
# since there is no physical speaker layout to draw.
#
# Phase 2 and the Picture-window visualization have been tested
# end-to-end in Praat for Speaker array output. For 12/16-channel output,
# watch for label crowding in Panels B/C; channelFontSize and
# maxSpeakerDiameter below scale down automatically above 8 channels, but
# very dense arrays may still benefit from a manual check.
###############################################################################

if draw_visualization = 1

    # --- suite channel-colour palette (cycles every 8 channels) ---
    palR[1] = 0.25
    palG[1] = 0.50
    palB[1] = 0.82
    palR[2] = 0.22
    palG[2] = 0.66
    palB[2] = 0.72
    palR[3] = 0.35
    palG[3] = 0.68
    palB[3] = 0.42
    palR[4] = 0.78
    palG[4] = 0.66
    palB[4] = 0.22
    palR[5] = 0.86
    palG[5] = 0.48
    palB[5] = 0.20
    palR[6] = 0.82
    palG[6] = 0.28
    palB[6] = 0.28
    palR[7] = 0.68
    palG[7] = 0.32
    palB[7] = 0.66
    palR[8] = 0.45
    palG[8] = 0.38
    palB[8] = 0.78

    for c to n_ch
        palIndex = ((c - 1) mod 8) + 1
        chanR[c] = palR[palIndex]
        chanG[c] = palG[palIndex]
        chanB[c] = palB[palIndex]
    endfor

    # --- scale labels / dots down for denser 9-, 12- and 16-channel arrays ---
    if n_ch > 8
        channelFontSize = 4
        maxSpeakerDiameter = 3.2
    else
        channelFontSize = 5
        maxSpeakerDiameter = 4.5
    endif

    # --- topology / mapping / representation strings for subtitle and summary ---
    if output_representation = 1
        if topology = 1
            topology$ = "Line"
        else
            topology$ = "Ring"
        endif
        repDesc$ = string$(n_ch) + " ch speaker array"
    else
        topology$ = orderName$ + " order ambiX"
        repDesc$ = orderName$ + " order ambiX (" + string$(n_ch) + " ch)"
    endif
    if mapping_mode = 1
        mapping$ = "Relative"
    else
        mapping$ = "Absolute"
    endif

    # --- drawn-value range (for the summary bar, independent of mapping mode) ---
    selectObject: movement
    drawnMin = Get value at index: 1
    drawnMax = drawnMin
    for i to n_points
        vv = Get value at index: i
        if vv < drawnMin
            drawnMin = vv
        endif
        if vv > drawnMax
            drawnMax = vv
        endif
    endfor

    # --- per-channel active-time percentage (|gain| > 0.001) ---
    # abs() is used because ambisonic ACN/SN3D coefficients can be negative,
    # unlike the always-nonnegative speaker crossfade gain.
    totalFrames = n_frames + 1
    for c to n_ch
        activeCount = 0
        for f from 0 to n_frames
            if abs(gainArr[c,f]) > 0.001
                activeCount = activeCount + 1
            endif
        endfor
        activePct[c] = activeCount / totalFrames * 100
    endfor

    activeChannelCount = 0
    activeList$ = ""
    for c to n_ch
        if activePct[c] > 0
            activeChannelCount = activeChannelCount + 1
            if activeList$ = ""
                activeList$ = chLabel$[c]
            else
                activeList$ = activeList$ + ", " + chLabel$[c]
            endif
        endif
    endfor
    if activeChannelCount = 0
        activeChannels$ = "none"
    elsif n_ch <= 8
        activeChannels$ = activeList$
    else
        activeChannels$ = string$(activeChannelCount) + " of " + string$(n_ch)
    endif

    # --- power diagnostic: sum of squared gains at each control frame,
    # ---   plus the midpoint of every consecutive frame pair. AmplitudeTiers
    # ---   interpolate linearly between points, so the midpoint gain is just
    # ---   the average of the two frame gains; checking it catches most
    # ---   real power dips (or, for ambisonic, encoded-energy dips) that a
    # ---   fast movement could cause between frames, without needing to
    # ---   resample the full audio-rate signal. For Speaker array this
    # ---   should sit near 1 (equal-power); for Ambisonic trajectory it
    # ---   reflects the SN3D per-order energy scaled by distanceGain^2.
    # ---   NOTE: meanPower is averaged over control frames only, while
    # ---   minPower/maxPower are taken over control frames AND inter-frame
    # ---   midpoints (a larger, denser set) -- the summary panel labels
    # ---   this explicitly so the three numbers are never misread as
    # ---   coming from the same sample set.
    sumPower = 0
    minPower = 1000000
    maxPower = -1000000
    for f from 0 to n_frames
        p = 0
        for c to n_ch
            p = p + gainArr[c,f] ^ 2
        endfor
        powerGain[f] = p
        sumPower = sumPower + p
        if p < minPower
            minPower = p
        endif
        if p > maxPower
            maxPower = p
        endif
    endfor
    meanPower = sumPower / totalFrames

    for f from 1 to n_frames
        pMid = 0
        for c to n_ch
            gMid = (gainArr[c,f-1] + gainArr[c,f]) / 2
            pMid = pMid + gMid ^ 2
        endfor
        if pMid < minPower
            minPower = pMid
        endif
        if pMid > maxPower
            maxPower = pMid
        endif
    endfor

    # --- plotted vertical position per frame ---
    # Speaker array: channel position (clamped for Line, wrapped for Ring).
    # Ambisonic trajectory: azimuth in degrees (already wrapped to 0-360).
    for f from 0 to n_frames
        if output_representation = 1
            if topology = 1
                p = chanPos_frame[f]
                if p < 1
                    p = 1
                elsif p > n_ch
                    p = n_ch
                endif
            else
                p = chanPos_frame[f] - n_ch * floor((chanPos_frame[f] - 1) / n_ch)
            endif
        else
            p = azimuth_frame[f]
        endif
        plotPos[f] = p
    endfor

    Erase all
    Colour: "Black"
    Line width: 1
    Font size: 10
    Solid line

    # ============================================================
    # TITLE BAR (full width)
    # ============================================================
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 12
    Text: 0.5, "Centre", 0.80, "Half", "##SPATIAL TRAJECTORY PAINTER##"
    Font size: 7
    Colour: {0.35, 0.35, 0.52}
    escapedName$ = replace$(mono_name$, "_", "\_ ", 0)
    subtitle$ = escapedName$ + "  |  " + repDesc$ + "  |  " + mapping$ + "  |  " + fixed$(duration, 2) + " s  |  " + string$(control_rate) + " Hz control"
    Text: 0.5, "Centre", 0.15, "Half", subtitle$
    Colour: "Black"

    # ============================================================
    # PANEL A -- Movement trajectory (large left panel)
    # ============================================================
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    if output_representation = 1
        Text: 0.5, "Centre", 0.97, "Half", "Movement trajectory  (vertical position = output channel)"
    else
        Text: 0.5, "Centre", 0.97, "Half", "Movement trajectory  (vertical position = azimuth, degrees)"
    endif

    Select inner viewport: 0.50, 4.00, 0.85, 4.50

    if output_representation = 1
        axisLow = 0
        axisHigh = n_ch + 1
        rectLow = 0.5
        rectHigh = n_ch + 0.5
    else
        axisLow = -10
        axisHigh = 370
        rectLow = 0
        rectHigh = 360
    endif

    Axes: xmin, xmax, axisLow, axisHigh
    Colour: {0.96, 0.96, 0.96}
    Paint rectangle: {0.96, 0.96, 0.96}, xmin, xmax, rectLow, rectHigh

    # horizontal position guides
    Colour: {0.88, 0.88, 0.88}
    Line width: 1
    if output_representation = 1
        for ch from 1 to n_ch
            Draw line: xmin, ch, xmax, ch
        endfor
    else
        for gi to 5
            gVal = (gi - 1) * 90
            Draw line: xmin, gVal, xmax, gVal
        endfor
        Font size: 5
        Colour: {0.55, 0.55, 0.55}
        for gi to 5
            gVal = (gi - 1) * 90
            Text: xmin, "Left", gVal, "Half", fixed$(gVal, 0) + "°"
        endfor
        Font size: 7
    endif
    # vertical time guides
    nTicks = 5
    for i from 0 to nTicks
        tx = xmin + i * (xmax - xmin) / nTicks
        Draw line: tx, rectLow, tx, rectHigh
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box

    # trajectory itself, broken at wrap points (Ring topology, or always for ambisonic)
    Colour: {0.25, 0.50, 0.82}
    Line width: 2
    for f from 1 to n_frames
        wrapBreak = 0
        if output_representation = 1
            if topology = 2 and abs(plotPos[f] - plotPos[f-1]) > n_ch / 2
                wrapBreak = 1
            endif
        else
            if abs(plotPos[f] - plotPos[f-1]) > 180
                wrapBreak = 1
            endif
        endif
        if wrapBreak = 0
            Draw line: t_frame[f-1], plotPos[f-1], t_frame[f], plotPos[f]
        else
            Colour: {0.55, 0.35, 0.65}
            Font size: 4
            Text: t_frame[f], "Centre", plotPos[f], "Half", "wrap"
            Font size: 7
            Colour: {0.25, 0.50, 0.82}
        endif
    endfor
    Line width: 1

    # start / end markers
    markerOffset = (axisHigh - axisLow) * 0.025
    Colour: {0.30, 0.68, 0.40}
    Paint circle (mm): {0.30, 0.68, 0.40}, t_frame[0], plotPos[0], 2.0
    Colour: "Black"
    Font size: 5
    Text: t_frame[0], "Centre", plotPos[0] - markerOffset, "Half", "Centre"

    Colour: {0.85, 0.38, 0.22}
    Paint circle (mm): {0.85, 0.38, 0.22}, t_frame[n_frames], plotPos[n_frames], 2.0
    Colour: "Black"
    Text: t_frame[n_frames], "Centre", plotPos[n_frames] + markerOffset, "Half", "end"

    # axis label
    Font size: 6
    Colour: {0.35, 0.35, 0.52}
    Text: (xmin + xmax) / 2, "Centre", axisLow + (axisHigh - axisLow) * 0.03, "Half", "Time (s)"
    Colour: "Black"

    if output_representation = 1
        # ============================================================
        # PANEL B -- Speaker-array map (upper right)
        # ============================================================
        Select outer viewport: 4.2, 8, 0.75, 3.00
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.5, "Centre", 0.97, "Half", "Speaker array  (dot size = active time)"

        Select inner viewport: 4.52, 7.75, 0.85, 2.92
        Axes: 0, 1, 0, 1
        Colour: {0.96, 0.96, 0.96}
        Paint rectangle: {0.96, 0.96, 0.96}, 0, 1, 0, 1
        Colour: "Black"
        Line width: 1
        Draw inner box

        if topology = 1
            # --- Line: speakers in a horizontal row ---
            for c to n_ch
                spkX[c] = 0.1 + (c - 1) / (n_ch - 1) * 0.8
                spkY[c] = 0.5
            endfor
            Colour: {0.7, 0.7, 0.7}
            Line width: 1
            Draw line: spkX[1], 0.5, spkX[n_ch], 0.5
        else
            # --- Ring: speakers around a circle, small "Listener" marker at centre ---
            centreX = 0.5
            centreY = 0.5
            ringR = 0.35
            for c to n_ch
                angle = 2 * pi * (c - 1) / n_ch - pi / 2
                spkX[c] = centreX + ringR * cos(angle)
                spkY[c] = centreY + ringR * sin(angle)
            endfor
            Colour: {0.5, 0.5, 0.5}
            Paint circle (mm): {0.5, 0.5, 0.5}, centreX, centreY, 1.0
            Font size: 4
            Colour: "Black"
            Text: centreX, "Centre", centreY - 0.09, "Half", "Listener"
        endif

        for c to n_ch
            diam = 1.6 + (activePct[c] / 100) * (maxSpeakerDiameter - 1.6)
            Colour: {chanR[c], chanG[c], chanB[c]}
            Paint circle (mm): {chanR[c], chanG[c], chanB[c]}, spkX[c], spkY[c], diam
            Colour: "Black"
            Font size: channelFontSize
            Text: spkX[c], "Centre", spkY[c], "Half", string$(c)
        endfor
        Colour: "Black"
    else
        # ============================================================
        # PANEL B -- Ambisonic top view: horizontal azimuth path (upper right)
        # ============================================================
        Select outer viewport: 4.2, 8, 0.75, 3.00
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.5, "Centre", 0.97, "Half", "Top view (azimuth path, el=" + fixed$(elevation, 0) + "°)"

        Select inner viewport: 4.52, 7.75, 0.85, 2.92
        Axes: -1.3, 1.3, -1.3, 1.3
        Colour: {0.96, 0.96, 0.96}
        Paint rectangle: {0.96, 0.96, 0.96}, -1.3, 1.3, -1.3, 1.3

        Colour: {0.86, 0.86, 0.86}
        Line width: 1
        Draw circle: 0, 0, 1
        Draw circle: 0, 0, 0.5
        Colour: {0.78, 0.78, 0.78}
        Draw line: 0, -1.25, 0, 1.25
        Draw line: -1.25, 0, 1.25, 0

        Font size: 6
        Colour: {0.50, 0.50, 0.50}
        Text: 0.06, "Left", 1.18, "Half", "0° Front"
        Text: 0.06, "Left", -1.18, "Half", "180° Rear"
        Text: -1.20, "Right", -0.10, "Half", "90° Left"
        Text: 1.20, "Left", -0.10, "Half", "270° Right"

        Paint circle (mm): {0.35, 0.35, 0.35}, 0, 0, 2.0
        Font size: 4
        Colour: "Black"
        Text: 0, "Centre", -0.10, "Half", "Listener"

        # trajectory path: ambiX top view, srcX = -sin(az), srcY = cos(az)
        Colour: {0.25, 0.50, 0.82}
        Line width: 2
        for f to n_frames
            azRad0 = azimuth_frame[f-1] * pi / 180
            azRad1 = azimuth_frame[f] * pi / 180
            px0 = -sin(azRad0)
            py0 = cos(azRad0)
            px1 = -sin(azRad1)
            py1 = cos(azRad1)
            Draw line: px0, py0, px1, py1
        endfor
        Line width: 1

        azStartRad = azimuth_frame[0] * pi / 180
        azEndRad = azimuth_frame[n_frames] * pi / 180
        Colour: {0.30, 0.68, 0.40}
        Paint circle (mm): {0.30, 0.68, 0.40}, -sin(azStartRad), cos(azStartRad), 2.2
        Colour: {0.85, 0.38, 0.22}
        Paint circle (mm): {0.85, 0.38, 0.22}, -sin(azEndRad), cos(azEndRad), 2.2
        Colour: "Black"

        Line width: 1
        Draw inner box
    endif

    # ============================================================
    # PANEL C -- Channel / component utilization (lower right)
    # ============================================================
    if output_representation = 1
        panelCTitle$ = "Channel utilization  (% of time active)"
    else
        panelCTitle$ = "ACN channel activity  (% of time |gain| > 0.1%)"
    endif

    Select outer viewport: 4.2, 8, 3.05, 4.60
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "Centre", 0.97, "Half", panelCTitle$

    Select inner viewport: 4.52, 7.75, 3.12, 4.52
    Axes: 0, 100, 0, n_ch + 1
    Colour: {0.96, 0.96, 0.96}
    Paint rectangle: {0.96, 0.96, 0.96}, 0, 100, 0.5, n_ch + 0.5

    barHeight = 0.76
    for c to n_ch
        yCentre = c
        Colour: {chanR[c], chanG[c], chanB[c]}
        Paint rectangle: {chanR[c], chanG[c], chanB[c]}, 0, activePct[c], yCentre - barHeight / 2, yCentre + barHeight / 2
        Font size: channelFontSize
        label$ = fixed$(activePct[c], 1) + "%"
        if activePct[c] > 18
            Colour: "White"
            Text: activePct[c] - 3, "Right", yCentre, "Half", label$
        else
            Colour: {0.30, 0.30, 0.30}
            Text: activePct[c] + 2, "Left", yCentre, "Half", label$
        endif
        Colour: "Black"
        Text: -3, "Right", yCentre, "Half", chLabel$[c]
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box

    # ============================================================
    # PANEL D -- Per-channel gain heatmap (full width)
    # ============================================================
    if output_representation = 1
        panelDTitle$ = "Per-channel gain map  (colour intensity = gain)"
    else
        panelDTitle$ = "Per-channel gain map  (colour intensity = |gain|)"
    endif

    Select outer viewport: 0, 8, 4.68, 5.95
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "Centre", 0.97, "Half", panelDTitle$

    Select inner viewport: 0.55, 7.72, 4.75, 5.88

    nBins = 250
    if totalFrames < nBins
        nBins = totalFrames
    endif
    framesPerBin = totalFrames / nBins

    for b from 0 to nBins - 1
        startF = floor(b * framesPerBin)
        endF = floor((b + 1) * framesPerBin) - 1
        if endF < startF
            endF = startF
        endif
        if endF > n_frames
            endF = n_frames
        endif
        for c to n_ch
            sumAbsG = 0
            cnt = 0
            for f from startF to endF
                # Mean of |gain|, not the (possibly cancelling) mean of the
                # signed gain: an ACN component that alternates sign within
                # a bin is still active and must show up in the map.
                sumAbsG = sumAbsG + abs(gainArr[c,f])
                cnt = cnt + 1
            endfor
            binGain[c,b] = sumAbsG / cnt
        endfor
    endfor

    Axes: 0, nBins, 0, n_ch + 1.6
    for b from 0 to nBins - 1
        for c to n_ch
            g = binGain[c,b]
            if g < 0
                g = 0
            elsif g > 1
                g = 1
            endif
            cellR = 1 + g * (chanR[c] - 1)
            cellG = 1 + g * (chanG[c] - 1)
            cellB = 1 + g * (chanB[c] - 1)
            Colour: {cellR, cellG, cellB}
            Paint rectangle: {cellR, cellG, cellB}, b, b + 1, c - 0.5, c + 0.5
        endfor
    endfor

    Colour: {0.85, 0.85, 0.85}
    Line width: 1
    for c from 1 to n_ch - 1
        Draw line: 0, c + 0.5, nBins, c + 0.5
    endfor
    Colour: "Black"
    Draw inner box

    Font size: channelFontSize
    for c to n_ch
        Text: -3, "Right", c, "Half", chLabel$[c]
    endfor
    Font size: 6
    Colour: {0.35, 0.35, 0.52}
    for i from 0 to 5
        tickBin = i * nBins / 5
        tickTime = xmin + i * duration / 5
        Text: tickBin, "Centre", 0.15, "Half", fixed$(tickTime, 1)
    endfor
    Colour: "Black"

    # ============================================================
    # PANEL E -- Power diagnostic and summary (full width)
    # ============================================================
    Select outer viewport: 0, 8, 6.02, 6.78
    Axes: 0, 1, 0, 1
    Colour: {0.94, 0.94, 0.94}
    Paint rectangle: {0.94, 0.94, 0.94}, 0, 1, 0, 1
    Colour: "Black"
    Line width: 1
    Draw inner box

    Font size: 6
    Colour: {0.28, 0.28, 0.28}
    if output_representation = 1
        line1$ = mapping$ + " | " + topology$ + " | " + string$(n_ch) + " channels | Range " + fixed$(drawnMin, 1) + "-" + fixed$(drawnMax, 1) + " | " + fixed$(duration, 2) + " s"
        line2$ = "Active channels: " + activeChannels$ + " | Power gain -- mean (at frames): " + fixed$(meanPower, 3) + ", min/max (frames+midpoints): " + fixed$(minPower, 3) + "/" + fixed$(maxPower, 3)
    else
        line1$ = mapping$ + " | " + orderName$ + " order ambiX (" + string$(n_ch) + " ch) | El " + fixed$(elevation, 1) + "° | Dist " + fixed$(distance, 2) + " m | Rot " + fixed$(trajectory_rotation, 1) + "°"
        line2$ = "Active: " + activeChannels$ + " | Range " + fixed$(drawnMin, 1) + "-" + fixed$(drawnMax, 1) + " | Encoded power -- mean (at frames): " + fixed$(meanPower, 3) + ", min/max (frames+midpoints): " + fixed$(minPower, 3) + "/" + fixed$(maxPower, 3)
    endif
    Text: 0.5, "Centre", 0.68, "Half", line1$
    Text: 0.5, "Centre", 0.28, "Half", line2$

    # ============================================================
    # RESET
    # ============================================================
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

###############################################################################
# CLEANUP -- removes all working objects, leaving only the final
# multichannel result. To draw a new movement curve after this,
# re-run Phase 1 from the original source Sound.
###############################################################################

for c to n_ch
    removeObject: gain_id[c]
    removeObject: ch_id[c]
endfor
removeObject: mono
removeObject: movement

if output_representation = 1
    doneDesc$ = "speaker array"
else
    doneDesc$ = orderName$ + " order ambiX"
endif

selectObject: result
appendInfoLine: "Done! Created: 'output_name$' ('n_ch' channels, " + doneDesc$ + ")."
if output_representation = 1
    Play
else
    appendInfoLine: "Ambisonic output created (raw ACN/SN3D field components)."
    appendInfoLine: "Playing these channels directly is not a valid spatial playback --"
    appendInfoLine: "decode through a speaker-array or binaural ambisonic decoder first."
endif

###############################################################################
# PROCEDURES
###############################################################################

# Compute the 16 ACN/SN3D encoding coefficients for a direction (degrees).
# Writes global acn[1..16] (acn[1]=ACN0 ... acn[16]=ACN15). Shared math with
# the Higher-Order Ambisonic Encoder script, so a moving trajectory here and
# a static point there stay numerically consistent.
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
