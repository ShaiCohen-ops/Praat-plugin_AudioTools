# ============================================================
# Praat AudioTools - Spatial Trajectory Painter (Demo window)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - interactive HOA1-5 trajectory authoring
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Draw a spatial trajectory for a Sound directly in the Demo window, in
#   real units, hear a stereo monitor of it, and commit the multichannel
#   result - one session instead of v0.7.5's two phases (RealTier editors
#   with Ctrl-T points, Set range..., reselect the mono Sound + tiers, run
#   again).
#
#   Lanes (time runs left to right, aligned with the source waveform):
#     SPEAKER ARRAY   Position lane in channel numbers (1..N; Ring: 1..N+1,
#                     where N+1 is channel 1 again)
#     AMBISONIC       Azimuth lane in degrees, ambiX convention:
#                     0 = front, +90 = LEFT, -90 = right, +-180 = back
#                     Elevation lane in degrees (-90..+90); no points =
#                     0 deg for the whole sound (v0.7.5 "Fixed elevation")
#   Between points the path is linear; azimuth (and Ring position) take the
#   SHORTER way round: 170 -> -170 crosses behind the listener (20 deg), not
#   through the front (340 deg). A full turn therefore needs points less
#   than 180 deg (Ring: N/2 channels) apart. The map shows the path taken.
#
#   The DSP uses frame sampling, equal-power speaker gains or full-3D
#   ACN/SN3D gain tiers, Formula multiply, shared peak protection, stacking,
#   and a general real-spherical-harmonic encoder supporting HOA orders 1-5.
#   It is fed RealTiers built from the drawn points in its
#   Absolute mode (speaker: Base 1, Step 1; ambisonic: degrees). A commit
#   here equals v0.7.5 Phase 2 on the same tiers.
#
# DEMO WINDOW CONTROLS
#   Click a lane          add a point; clicking at the time of an existing
#                         point of that lane moves it instead
#   U undo   P preview (render + stereo monitor)   Enter commit   Esc cancel
#   Click the Demo window once so it has keyboard focus.
#
# STEREO MONITOR (preview and after commit) - an approximation for
#   checking motion and timing, NOT the multichannel image:
#     ambisonic   virtual cardioids at +-90 deg from W and Y (ACN0, ACN1)
#     speaker     Line: channels panned 1 = left ... N = right
#                 Ring: channel 1 at the front, increasing clockwise
#                 (an assumption - the array's real layout is yours)
#
# OUTPUT (Enter): the multichannel Sound (Output_name), the Info report,
#   and the Picture-window figure if requested. The temporary control
#   RealTier(s) are always removed after rendering.
#
# Changelog v1.1:
#   - Ambisonic trajectory mode extended from HOA1-3 to HOA1-5: 4/9/16/25/36
#     channel ambiX ACN/SN3D output.
#   - Replaced the hard-coded ACN0-15 formulas with the same general SN3D
#     real-spherical-harmonic engine used by the upgraded HOA Encoder.
#   - Visualization density adjusted for 25/36-channel Ambisonic fields.
#
# Changelog v1.0:
#   - Demo-window front end for v0.7.5: lanes in real units, shortest-way
#     wrap for azimuth / ring position, live top-down map, source waveform
#     timeline, undo, stereo-monitor preview, commit.
#   - Relative mapping and Base/Step are not needed (you draw in the
#     output's own units); Distance, Rotation and Control rate stay on the
#     optional details page.
# ============================================================

form Spatial Trajectory Painter (Demo window) v1.1
    comment Draw the trajectory in the Demo window; these fix the output format.
    optionmenu Output_representation: 1
        option Speaker array
        option Ambisonic trajectory (ambiX ACN/SN3D)
    optionmenu Number_of_channels: 3
        option 4
        option 6
        option 8
        option 12
        option 16
    optionmenu Topology 1
        option Line (clamp at ends)
        option Ring (wrap around)
    optionmenu Ambisonic_order: 1
        option First order (4 ch)
        option Second order (9 ch)
        option Third order (16 ch)
        option Fourth order (25 ch)
        option Fifth order (36 ch)
    word Output_name movement_output
    boolean Edit_details 0
    boolean Draw_visualization 1
endform

# ---- technical defaults (compatible with the previous Painter controls) ----
distance = 1.0
trajectory_rotation = 0
control_rate = 100
if edit_details
    beginPause: "Spatial Trajectory Painter - details"
        comment: "Ambisonic trajectory"
        positive: "Distance (meters)", distance
        real: "Trajectory rotation (degrees)", trajectory_rotation
        comment: "Rendering"
        positive: "Control rate (Hz)", control_rate
        comment: "Distance is inverse-distance amplitude only; no near-field compensation."
    detailsClicked = endPause: "Use defaults", "Apply", 2, 1
endif
# Absolute mapping in the drawn units
mapping_mode = 2
elevation_mapping = 2
base_value = 1
step_value = 1
fixed_elevation = 0
minimum_elevation = -45
maximum_elevation = 45

if output_representation = 1
    n_ch = number (number_of_channels$)
    orderName$ = ""
else
    if ambisonic_order = 1
        n_ch = 4
        orderName$ = "1st"
    elsif ambisonic_order = 2
        n_ch = 9
        orderName$ = "2nd"
    elsif ambisonic_order = 3
        n_ch = 16
        orderName$ = "3rd"
    elsif ambisonic_order = 4
        n_ch = 25
        orderName$ = "4th"
    else
        n_ch = 36
        orderName$ = "5th"
    endif
endif
for c to n_ch
    if output_representation = 1
        chLabel$[c] = "Ch" + string$(c)
    else
        chLabel$[c] = "ACN" + string$(c - 1)
    endif
endfor

# ---- input ----
if numberOfSelected ("Sound") <> 1
    exitScript: "Select exactly one Sound."
endif
sound_in = selected ("Sound")
sound_name$ = selected$ ("Sound")
selectObject: sound_in
xmin = Get start time
xmax = Get end time
dur = xmax - xmin
duration = dur
Convert to mono
mono = selected ("Sound")
Rename: sound_name$ + "_mono"
mono_name$ = sound_name$ + "_mono"
wavePeak = Get absolute extremum: 0, 0, "None"
if wavePeak <= 0
    wavePeak = 1
endif

# ---- lanes ----
amb = output_representation = 2
ring = output_representation = 1 and topology = 2
nLanes = if amb then 2 else 1 fi
if amb
    laneLo[1] = -180
    laneHi[1] = 180
    laneLo[2] = -90
    laneHi[2] = 90
    period = 360
elsif ring
    laneLo[1] = 1
    laneHi[1] = n_ch + 1
    period = n_ch
else
    laneLo[1] = 1
    laneHi[1] = n_ch
    period = 0
endif
nP[1] = 0
nP[2] = 0
nHist = 0
status$ = "Click the " + if amb then "azimuth" else "position" fi + " lane to draw the trajectory."
finalView = 0

# ---- Demo layout (window units 0..100, y upward; sx/sy/flipH for tests) ----
sx = 1
sy = 1
flipH = 0
ttlB = 92
ttlT = 99
mapL = 7.5
mapR = 36
mapB = 47
mapT = 75.5
lnL = 44
lnR = 96.25
if amb
    l1B = 64
    l1T = 84
    l2B = 38
    l2T = 57
else
    l1B = 38
    l1T = 84
endif
wvB = 17
wvT = 29
sumB = 1.5
sumT = 11

cPrim$  = "{0.20, 0.48, 0.75}"
cSec$   = "{0.85, 0.38, 0.18}"
cGrey$  = "{0.55, 0.55, 0.60}"
cPanel$ = "{0.97, 0.97, 0.97}"
cGrid$  = "{0.80, 0.80, 0.80}"
cSub$   = "{0.35, 0.35, 0.50}"
cSumTx$ = "{0.25, 0.25, 0.35}"
cSum$   = "{0.94, 0.94, 0.94}"


###############################################################################
# POINT EDITING (sorted arrays per lane; shared undo stack)
###############################################################################
procedure addOrMove: .lane, .x, .y
    .tol = dur * 0.004
    .hit = 0
    for .i to nP[.lane]
        if .hit = 0 and abs (pT[.lane, .i] - .x) <= .tol
            .hit = .i
        endif
    endfor
    nHist += 1
    hLane[nHist] = .lane
    if .hit > 0
        hKind[nHist] = 2
        hT[nHist] = pT[.lane, .hit]
        hV[nHist] = pV[.lane, .hit]
        pV[.lane, .hit] = .y
        .verb$ = "Moved"
    else
        .n = nP[.lane]
        .pos = .n + 1
        for .i to .n
            if .pos = .n + 1 and pT[.lane, .i] > .x
                .pos = .i
            endif
        endfor
        for .m to .n - .pos + 1
            .j = .n - .m + 1
            .jn = .j + 1
            pT[.lane, .jn] = pT[.lane, .j]
            pV[.lane, .jn] = pV[.lane, .j]
        endfor
        pT[.lane, .pos] = .x
        pV[.lane, .pos] = .y
        nP[.lane] = .n + 1
        hKind[nHist] = 1
        hT[nHist] = .x
        hV[nHist] = .y
        .verb$ = "Added"
    endif
    .u$ = if amb then (if .lane = 1 then " deg azimuth" else " deg elevation" fi) else "" fi
    .v$ = if amb then fixed$ (round (.y), 0) else "channel " + fixed$ (.y, 2) fi
    status$ = .verb$ + " point at " + fixed$ (.x, 2) + " s: " + .v$ + .u$ + "."
endproc

procedure undoLast
    if nHist = 0
        status$ = "Nothing to undo."
    else
        .lane = hLane[nHist]
        .idx = 0
        for .i to nP[.lane]
            if pT[.lane, .i] = hT[nHist]
                .idx = .i
            endif
        endfor
        if hKind[nHist] = 2 and .idx > 0
            pV[.lane, .idx] = hV[nHist]
            status$ = "Undid move."
        elsif .idx > 0
            for .i from .idx to nP[.lane] - 1
                .j = .i + 1
                pT[.lane, .i] = pT[.lane, .j]
                pV[.lane, .i] = pV[.lane, .j]
            endfor
            nP[.lane] -= 1
            status$ = "Undid add."
        endif
        nHist -= 1
    endif
endproc

procedure routeClick: .x, .y
    .u = (.x - lnL) / (lnR - lnL)
    if .u < 0 or .u > 1
        status$ = "Click inside a lane (right-hand panels)."
    elsif .y >= l1B and .y <= l1T
        .v = laneLo[1] + (.y - l1B) / (l1T - l1B) * (laneHi[1] - laneLo[1])
        if amb
            .v = round (.v)
        endif
        @addOrMove: 1, xmin + .u * dur, .v
    elsif amb and .y >= l2B and .y <= l2T
        .v = round (laneLo[2] + (.y - l2B) / (l2T - l2B) * (laneHi[2] - laneLo[2]))
        @addOrMove: 2, xmin + .u * dur, .v
    else
        status$ = "Click inside a lane (right-hand panels)."
    endif
endproc

###############################################################################
# DRAWN POINTS -> UNWRAPPED VALUES (shorter way round) -> path sampling
###############################################################################
# unwrapped values of lane 1 into uV[i] (azimuth / ring position)
procedure unwrapLane1
    for .i to nP[1]
        if .i = 1 or period = 0
            uV[.i] = pV[1, .i]
        else
            .d = pV[1, .i] - pV[1, .i - 1]
            .d = .d - period * round (.d / period)
            .ip = .i - 1
            uV[.i] = uV[.ip] + .d
        endif
    endfor
endproc

# value of a lane at time .t (held before the first / after the last point),
# lane 1 from the unwrapped values; result for display is wrapped back
procedure laneAt: .lane, .t
    .n = nP[.lane]
    if .n = 0
        .result = 0
    else
        .j = 0
        for .i to .n
            if pT[.lane, .i] <= .t
                .j = .i
            endif
        endfor
        if .lane = 1
            if .j = 0
                .result = uV[1]
            elsif .j = .n
                .result = uV[.n]
            else
                .k = .j + 1
                .result = uV[.j] + (uV[.k] - uV[.j]) * (.t - pT[1, .j]) / max (1e-12, pT[1, .k] - pT[1, .j])
            endif
        else
            if .j = 0
                .result = pV[2, 1]
            elsif .j = .n
                .result = pV[2, .n]
            else
                .k = .j + 1
                .result = pV[2, .j] + (pV[2, .k] - pV[2, .j]) * (.t - pT[2, .j]) / max (1e-12, pT[2, .k] - pT[2, .j])
            endif
        endif
    endif
endproc

###############################################################################
# RENDER (shared AudioTools spatial DSP on tiers built from the drawing)
###############################################################################
procedure buildTiers
    @unwrapLane1
    if amb and nP[2] > 0
        drawnElevation = 1
        movement = Create RealTier: "movement_azimuth", xmin, xmax
        for .i to nP[1]
            Add point: pT[1, .i], uV[.i]
        endfor
        selectObject: mono
        minusObject: mono
        movement_el = Create RealTier: "movement_elevation", xmin, xmax
        for .i to nP[2]
            Add point: pT[2, .i], pV[2, .i]
        endfor
        n_el_points = nP[2]
    else
        drawnElevation = 0
        movement = Create RealTier: "movement", xmin, xmax
        for .i to nP[1]
            Add point: pT[1, .i], uV[.i]
        endfor
        movement_el = 0
    endif
    n_points = nP[1]
endproc

procedure renderDSP
# --- Relative mode: find the value range of the drawn azimuth points ---
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

# --- Relative ELEVATION mapping: find the value range of the drawn
# --- elevation points, so it can be stretched to [Min_el, Max_el].
# --- A flat curve (elRangeDrawn = 0) is later placed at the midpoint;
# --- guarding against division by zero here.
if drawnElevation = 1 and elevation_mapping = 1
    selectObject: movement_el
    elMinDrawn = Get value at index: 1
    elMaxDrawn = elMinDrawn
    for i to n_el_points
        v = Get value at index: i
        if v < elMinDrawn
            elMinDrawn = v
        endif
        if v > elMaxDrawn
            elMaxDrawn = v
        endif
    endfor
    elRangeDrawn = elMaxDrawn - elMinDrawn
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

    # --- Ambisonic elevation (degrees, clamped to [-90, +90], never wrapped) ---
    if output_representation = 2
        if drawnElevation = 0
            # Fixed elevation: identical value at every frame (v0.5 behaviour).
            elevation_frame[f] = fixed_elevation
        else
            selectObject: movement_el
            vEl = Get value at time: t
            if elevation_mapping = 1
                # Relative: stretch the drawn elevation range to [Min_el, Max_el].
                if elRangeDrawn <> 0
                    elNorm = (vEl - elMinDrawn) / elRangeDrawn
                else
                    # Flat curve -> midpoint of the requested range (no div by zero).
                    elNorm = 0.5
                endif
                if elNorm < 0
                    elNorm = 0
                elsif elNorm > 1
                    elNorm = 1
                endif
                elDeg = minimum_elevation + elNorm * (maximum_elevation - minimum_elevation)
            else
                # Absolute: the drawn value IS the elevation in degrees.
                elDeg = vEl
            endif
            # Clamp (do NOT wrap) elevation to the valid pole-to-pole range.
            if elDeg > 90
                elDeg = 90
            elsif elDeg < -90
                elDeg = -90
            endif
            elevation_frame[f] = elDeg
        endif
    endif
endfor

# --- Actual azimuth / elevation extents (for the info report + visualization) ---
if output_representation = 2
    azMinActual = azimuth_frame[0]
    azMaxActual = azimuth_frame[0]
    elevMinActual = elevation_frame[0]
    elevMaxActual = elevation_frame[0]
    for f from 0 to n_frames
        if azimuth_frame[f] < azMinActual
            azMinActual = azimuth_frame[f]
        endif
        if azimuth_frame[f] > azMaxActual
            azMaxActual = azimuth_frame[f]
        endif
        if elevation_frame[f] < elevMinActual
            elevMinActual = elevation_frame[f]
        endif
        if elevation_frame[f] > elevMaxActual
            elevMaxActual = elevation_frame[f]
        endif
    endfor

    # Human-readable elevation-mode strings, reused by the report + panels.
    if drawnElevation = 0
        elevModeShort$ = "Fixed"
        elevModeDesc$ = "fixed " + fixed$(fixed_elevation, 1) + " deg"
    else
        if elevation_mapping = 1
            elevModeShort$ = "Drawn/Relative"
            elevModeDesc$ = "drawn, relative -> [" + fixed$(minimum_elevation, 1) + ", " + fixed$(maximum_elevation, 1) + "] deg"
        else
            elevModeShort$ = "Drawn/Absolute"
            elevModeDesc$ = "drawn, absolute degrees"
        endif
    endif
endif

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
        # Full-3D direction per frame: azimuth AND elevation both vary in time
        # (elevation_frame[f] is constant in Fixed mode, so this reduces exactly
        # to the v0.5 fixed-elevation call there).
        @computeACN: azimuth_frame[f], elevation_frame[f], ambisonic_order
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
        # gainArr drives the heatmap and power diagnostic. It must describe the
        # FINAL effective channel gains after the same shared protection factor.
        for c to n_ch
            for f from 0 to n_frames
                gainArr[c,f] = gainArr[c,f] * scaleFactor
            endfor
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

endproc

procedure freeRender: .keepResult
    for .c to n_ch
        removeObject: gain_id[.c], ch_id[.c]
    endfor
    if .keepResult = 0
        removeObject: result
    endif
endproc

procedure freeTiers
    removeObject: movement
    if movement_el > 0
        removeObject: movement_el
    endif
endproc

# stereo monitor of the current multichannel result
procedure monitorMix
    selectObject: result
    .mon = Create Sound from formula: "monitor", 2, xmin, xmax, sampleRateMono, "0"
    for .c to n_ch
        if amb
            if .c = 1
                .gl = 0.5
                .gr = 0.5
            elsif .c = 2
                .gl = 0.5
                .gr = -0.5
            else
                .gl = 0
                .gr = 0
            endif
        elsif ring
            .a = (.c - 1) / n_ch * 2 * pi
            .gl = 0.5 * (1 - sin (.a))
            .gr = 0.5 * (1 + sin (.a))
        else
            .xx = if n_ch > 1 then (.c - 1) / (n_ch - 1) else 0.5 fi
            .gl = cos (.xx * pi / 2)
            .gr = sin (.xx * pi / 2)
        endif
        if .gl <> 0 or .gr <> 0
            selectObject: .mon
            Formula: "self + object[" + string$ (result) + ", " + string$ (.c) + ", col] * (if row = 1 then " + string$ (.gl) + " else " + string$ (.gr) + " fi)"
        endif
    endfor
    selectObject: .mon
    .pk = Get absolute extremum: 0, 0, "None"
    if .pk > 0
        Scale peak: 0.9
    endif
    .result = .mon
endproc

procedure preview
    if nP[1] = 0
        status$ = "Draw at least one " + if amb then "azimuth" else "position" fi + " point first."
    else
        status$ = "Rendering the preview..."
        @drawAll
        @buildTiers
        @renderDSP
        @monitorMix
        Play
        removeObject: monitorMix.result
        @freeRender: 0
        @freeTiers
        status$ = "Preview played (stereo monitor - an approximation, not the multichannel image)."
    endif
endproc

###############################################################################
# DRAWING
###############################################################################
procedure vp: .x1, .x2, .y1, .y2
    if flipH > 0
        demo Select inner viewport: .x1 * sx, .x2 * sx, flipH - .y2 * sy, flipH - .y1 * sy
    else
        demo Select inner viewport: .x1 * sx, .x2 * sx, .y1 * sy, .y2 * sy
    endif
endproc

procedure caption: .x1, .x2, .yT, .text$
    demo Font size: 8
    @vp: .x1, .x2, .yT, .yT + 3
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Text: 0, "left", 0.2, "half", .text$
endproc

procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor (log10 (.raw))
    .result = 10 * .mag
    if 5 * .mag >= .raw
        .result = 5 * .mag
    endif
    if 2 * .mag >= .raw
        .result = 2 * .mag
    endif
    if .mag >= .raw
        .result = .mag
    endif
endproc

procedure drawTitle
    demo Font size: 12
    @vp: 7.5, 96.25, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Text: 0.5, "centre", 0.72, "half", "##SPATIAL TRAJECTORY PAINTER" + if finalView then " \-- RESULT" else "" fi + "##"
    .nm$ = replace$ (sound_name$, "_", "\_ ", 0)
    demo Font size: 7
    @vp: 7.5, 96.25, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: cSub$
    demo Text: 0.5, "centre", 0.12, "half", .nm$ + "   |   " + fixed$ (dur, 2) + " s   |   "
        ... + if amb then orderName$ + " order ambiX (" + string$ (n_ch) + " ch)" else string$ (n_ch) + "-channel " + if ring then "ring" else "line" fi fi
endproc

# ---- lanes -----------------------------------------------------------------
procedure drawLane: .lane, .yB, .yT
    .lo = laneLo[.lane]
    .hi = laneHi[.lane]
    demo Font size: 7
    @vp: lnL, lnR, .yB, .yT
    demo Axes: xmin, xmax, .lo, .hi
    demo Paint rectangle: cPanel$, xmin, xmax, .lo, .hi
    demo Colour: cGrid$
    demo Dotted line
    if amb and .lane = 1
        for .g from -1 to 1
            demo Draw line: xmin, .g * 90, xmax, .g * 90
        endfor
    elsif amb
        demo Draw line: xmin, 0, xmax, 0
        demo Draw line: xmin, 45, xmax, 45
        demo Draw line: xmin, -45, xmax, -45
    else
        for .g from 1 to n_ch + ring
            demo Draw line: xmin, .g, xmax, .g
        endfor
    endif
    demo Solid line
    # the path actually rendered, sampled (lane 1 wrapped back for display)
    if nP[.lane] > 0
        demo Colour: if .lane = 1 then cPrim$ else cSec$ fi
        demo Line width: 2
        .ns = 300
        for .s from 0 to .ns
            .t = xmin + .s / .ns * dur
            @laneAt: .lane, .t
            .v = laneAt.result
            if .lane = 1 and period > 0
                .v = laneLo[1] + (.v - laneLo[1]) - period * floor ((.v - laneLo[1]) / period)
            endif
            if .s > 0
                if abs (.v - .pv) < period / 2 or period = 0 or .lane = 2
                    demo Draw line: .pt, .pv, .t, .v
                endif
            endif
            .pt = .t
            .pv = .v
        endfor
        demo Line width: 1
        for .i to nP[.lane]
            demo Paint circle (mm): if .lane = 1 then cPrim$ else cSec$ fi, pT[.lane, .i], pV[.lane, .i], 1.6
        endfor
    elsif .lane = 2
        demo Colour: cSec$
        demo Line width: 2
        demo Draw line: xmin, 0, xmax, 0
        demo Line width: 1
    endif
    demo Font size: 6
    @vp: lnL, lnR, .yB, .yT
    demo Axes: xmin, xmax, .lo, .hi
    if .lane = 2 and nP[2] = 0
        demo Colour: cSub$
        demo Text: xmax, "right", 80, "top", "no points: 0 deg throughout "
    endif
    demo Font size: 7
    @vp: lnL, lnR, .yB, .yT
    demo Axes: xmin, xmax, .lo, .hi
    demo Colour: "Black"
    demo Draw inner box
    if amb and .lane = 1
        demo One mark left: 180, "no", "yes", "no", "back"
        demo One mark left: 90, "no", "yes", "no", "L 90"
        demo One mark left: 0, "no", "yes", "no", "front"
        demo One mark left: -90, "no", "yes", "no", "R -90"
        demo One mark left: -180, "no", "yes", "no", "back"
        @caption: lnL, lnR, .yT + 1, "##Azimuth (ambiX, +90 = left)##   shorter way round between points"
    elsif amb
        demo Marks left every: 1, 45, "yes", "yes", "no"
        @caption: lnL, lnR, .yT + 1, "##Elevation (deg)##"
    else
        for .g from 1 to n_ch
            demo One mark left: .g, "no", "yes", "no", string$ (.g)
        endfor
        if ring
            demo One mark left: n_ch + 1, "no", "yes", "no", "1"
        endif
        @caption: lnL, lnR, .yT + 1, "##Position (channel)##   " + if ring then "ring: top row = channel 1 again; shorter way round" else "line: clamped at 1 and " + string$ (n_ch) fi
    endif
endproc

# ---- source waveform: the timeline the lanes share ---------------------------
procedure drawWave
    demo Font size: 7
    @vp: lnL, lnR, wvB, wvT
    demo Axes: xmin, xmax, -wavePeak, wavePeak
    demo Paint rectangle: cPanel$, xmin, xmax, -wavePeak, wavePeak
    selectObject: mono
    demo Colour: cGrey$
    demo Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    @vp: lnL, lnR, wvB, wvT
    demo Axes: xmin, xmax, -wavePeak, wavePeak
    demo Colour: "Black"
    demo Draw inner box
    @niceStep: dur, 8
    demo Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    demo Text bottom: "yes", "Time (s)"
    @caption: lnL, lnR, wvT + 1, "##Source (mono)##"
endproc

# ---- top-down map --------------------------------------------------------------
procedure drawMap
    demo Font size: 7
    @vp: mapL, mapR, mapB, mapT
    demo Axes: -1.35, 1.35, -1.35, 1.35
    demo Paint rectangle: cPanel$, -1.35, 1.35, -1.35, 1.35
    demo Colour: cGrid$
    # reference circles as polylines, mapped exactly like the path, so both
    # deform together if the Demo window is not square
    if amb or ring
        @ring: 1
        demo Dotted line
        if amb
            @ring: cos (45 * pi / 180)
        endif
        demo Solid line
    endif
    # speakers (array modes)
    if amb = 0
        for .c to n_ch
            if ring
                .a = (.c - 1) / n_ch * 2 * pi
                .sxp = sin (.a)
                .syp = cos (.a)
            else
                .sxp = -1 + 2 * (.c - 1) / max (1, n_ch - 1)
                .syp = 0.6
            endif
            demo Paint circle (mm): cGrey$, .sxp, .syp, 2.2
        endfor
    endif
    # path
    if nP[1] > 0
        @unwrapLane1
        demo Colour: cPrim$
        demo Line width: 2
        .ns = 200
        for .s from 0 to .ns
            .t = xmin + .s / .ns * dur
            @laneAt: 1, .t
            .v = laneAt.result
            if amb
                @laneAt: 2, .t
                .el = laneAt.result
                .r = cos (.el * pi / 180)
                .px = -.r * sin (.v * pi / 180)
                .py = .r * cos (.v * pi / 180)
            elsif ring
                .a = (.v - 1) / n_ch * 2 * pi
                .px = sin (.a)
                .py = cos (.a)
            else
                .vv = max (1, min (n_ch, .v))
                .px = -1 + 2 * (.vv - 1) / max (1, n_ch - 1)
                .py = 0.6
            endif
            if .s > 0
                demo Draw line: .ppx, .ppy, .px, .py
            endif
            if .s = 0
                .sx0 = .px
                .sy0 = .py
            endif
            .ppx = .px
            .ppy = .py
        endfor
        demo Line width: 1
        demo Paint circle (mm): cSec$, .sx0, .sy0, 2.2
        demo Paint circle (mm): cPrim$, .px, .py, 2.2
    endif
    demo Paint circle (mm): "{0.25, 0.25, 0.35}", 0, if amb or ring then 0 else -0.4 fi, 2.4
    demo Font size: 6
    @vp: mapL, mapR, mapB, mapT
    demo Axes: -1.35, 1.35, -1.35, 1.35
    demo Colour: cSub$
    if amb or ring
        demo Text: 0, "centre", 1.22, "half", "front"
        demo Text: -1.25, "centre", 0, "half", "L"
        demo Text: 1.25, "centre", 0, "half", "R"
    else
        demo Text: -1, "centre", 0.85, "half", "1"
        demo Text: 1, "centre", 0.85, "half", string$ (n_ch)
    endif
    demo Colour: cSec$
    demo Text: -1.3, "left", -1.25, "bottom", "orange = start"
    demo Font size: 7
    @vp: mapL, mapR, mapB, mapT
    demo Axes: -1.35, 1.35, -1.35, 1.35
    demo Colour: "Black"
    demo Draw inner box
    @caption: mapL, mapR, mapT + 1, "##Map (top-down)##"
    demo Font size: 6
    @vp: mapL, mapR, mapB - 9, mapB - 1
    demo Axes: 0, 1, 0, 1
    demo Colour: cSub$
    if amb
        demo Text: 0, "left", 0.75, "half", "radius = cos (elevation): elevated"
        demo Text: 0, "left", 0.35, "half", "positions sit inside the circle"
    elsif ring
        demo Text: 0, "left", 0.75, "half", "assumed layout: channel 1 front,"
        demo Text: 0, "left", 0.35, "half", "increasing clockwise"
    else
        demo Text: 0, "left", 0.75, "half", "line array: channel 1 ... " + string$ (n_ch)
        demo Text: 0, "left", 0.35, "half", "left to right"
    endif
endproc

procedure ring: .r
    for .s from 1 to 96
        .a0 = (.s - 1) / 96 * 2 * pi
        .a1 = .s / 96 * 2 * pi
        demo Draw line: .r * sin (.a0), .r * cos (.a0), .r * sin (.a1), .r * cos (.a1)
    endfor
endproc

procedure drawSummary
    demo Font size: 7
    @vp: 7.5, 96.25, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Paint rectangle: cSum$, 0, 1, 0, 1
    demo Colour: cSumTx$
    if finalView
        demo Text: 0.01, "left", 0.78, "half", "##Done.## The multichannel Sound is in the Objects window; the report is in the Info window."
    else
        demo Text: 0.01, "left", 0.78, "half", "##Click## a lane: add / move point   ##U## undo   ##P## preview (stereo monitor)   ##Enter## commit   ##Esc## cancel"
    endif
    demo Text: 0.01, "left", 0.46, "half", "##" + string$ (nP[1]) + "## " + if amb then "azimuth" else "position" fi + " point(s)" + if amb then ", ##" + string$ (nP[2]) + "## elevation point(s)" else "" fi
        ... + "   control rate " + string$ (control_rate) + " Hz" + if amb then ", distance " + fixed$ (distance, 2) + " m, rotation " + fixed$ (trajectory_rotation, 0) + " deg" else "" fi
    demo Text: 0.01, "left", 0.16, "half", "##Status:## " + replace$ (status$, "_", "\_ ", 0)
    @vp: 7.5, 96.25, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Draw inner box
endproc

procedure drawAll
    demo Erase all
    @drawTitle
    @drawMap
    @drawLane: 1, l1B, l1T
    if amb
        @drawLane: 2, l2B, l2T
    endif
    @drawWave
    @drawSummary
    demo Font size: 7
    @vp: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
endproc

###############################################################################
# SESSION
###############################################################################
selectObject: mono
sampleRateMono = Get sampling frequency
@drawAll

# >>> INPUT LOOP
action$ = ""
while action$ = ""
    demoWaitForInput ()
    if demoClicked ()
        @routeClick: demoX (), demoY ()
        @drawAll
    elsif demoKeyPressed ()
        key$ = demoKey$ ()
        if key$ = newline$ or key$ = unicode$ (13) or key$ = unicode$ (65293)
            if nP[1] = 0
                status$ = "Draw at least one " + if amb then "azimuth" else "position" fi + " point before committing."
                @drawAll
            else
                action$ = "commit"
            endif
        elsif key$ = unicode$ (27) or key$ = unicode$ (65307)
            action$ = "cancel"
        elsif key$ = "u" or key$ = "U"
            @undoLast
            @drawAll
        elsif key$ = "p" or key$ = "P"
            @preview
            @drawAll
        endif
    endif
endwhile
# <<< INPUT LOOP

if action$ = "cancel"
    removeObject: mono
    status$ = "Cancelled - nothing was created."
    @drawAll
    exitScript: "Spatial Trajectory Painter cancelled."
endif

###############################################################################
# COMMIT
###############################################################################
writeInfoLine: "=== Spatial Trajectory Painter (Demo) v1.1 ==="
status$ = "Rendering..."
@drawAll
@buildTiers
@renderDSP
appendInfoLine: "Representation: ", if amb then orderName$ + " order ambiX ACN/SN3D (" + string$ (n_ch) + " ch)" else string$ (n_ch) + "-channel speaker array, " + if ring then "ring" else "line" fi fi
appendInfoLine: "Points: ", nP[1], if amb then " azimuth, " + string$ (nP[2]) + " elevation" else " position" fi
appendInfoLine: "Mapping: Absolute in drawn units (" + if amb then "degrees" else "channel numbers: Base 1, Step 1" fi + "), unwrapped the shorter way round"
if amb
    appendInfoLine: "Azimuth range: " + fixed$ (azMinActual, 1) + " to " + fixed$ (azMaxActual, 1) + " deg (0-360, ambiX)"
    appendInfoLine: "Elevation: " + elevModeDesc$ + ", range " + fixed$ (elevMinActual, 1) + " to " + fixed$ (elevMaxActual, 1) + " deg"
    appendInfoLine: "Distance: " + fixed$ (distance, 2) + " m (fixed), rotation " + fixed$ (trajectory_rotation, 1) + " deg"
endif
appendInfoLine: "Control rate: ", control_rate, " Hz"

# Picture-window diagnostic
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

    # --- scale labels / dots down for dense higher-order fields ---
    if n_ch > 16
        channelFontSize = 3
        maxSpeakerDiameter = 2.7
    elsif n_ch > 8
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
    # ---   reflects the FINAL SN3D per-order energy after distanceGain and,
    # ---   when triggered, the shared peak-protection scale factor.
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
    Select outer viewport: 0, 8, 0, 0.30
    Select inner viewport: 0.60, 7.70, 0.02, 0.28
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 12
    Text: 0.5, "Centre", 0.5, "Half", "##SPATIAL TRAJECTORY PAINTER##"
    Select outer viewport: 0, 8, 0.30, 0.55
    Select inner viewport: 0.60, 7.70, 0.31, 0.54
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: {0.35, 0.35, 0.52}
    escapedName$ = replace$(mono_name$, "_", "\_ ", 0)
    subtitle$ = escapedName$ + "  |  " + repDesc$ + "  |  " + mapping$ + "  |  " + fixed$(duration, 2) + " s  |  " + string$(control_rate) + " Hz control"
    Text: 0.5, "Centre", 0.5, "Half", subtitle$
    Colour: "Black"

    # ============================================================
    # PANEL A -- Movement trajectory (large left panel)
    #   Speaker array: one panel, channel position vs time (unchanged).
    #   Ambisonic:     TWO stacked panels -- azimuth vs time (top) and
    #                  elevation vs time (bottom) -- so both dimensions of
    #                  motion are visible. The top-view azimuth circle is
    #                  still shown separately in Panel B.
    # ============================================================
    if output_representation = 1
        Select outer viewport: 0, 4.2, 0.75, 4.60
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.5, "Centre", 0.97, "Half", "Movement trajectory  (vertical position = output channel)"

        Select inner viewport: 0.50, 4.00, 0.85, 4.50

        axisLow = 0
        axisHigh = n_ch + 1
        rectLow = 0.5
        rectHigh = n_ch + 0.5

        Axes: xmin, xmax, axisLow, axisHigh
        Colour: {0.96, 0.96, 0.96}
        Paint rectangle: {0.96, 0.96, 0.96}, xmin, xmax, rectLow, rectHigh

        # horizontal position guides
        Colour: {0.88, 0.88, 0.88}
        Line width: 1
        for ch from 1 to n_ch
            Draw line: xmin, ch, xmax, ch
        endfor
        # vertical time guides
        nTicks = 5
        for i from 0 to nTicks
            tx = xmin + i * (xmax - xmin) / nTicks
            Draw line: tx, rectLow, tx, rectHigh
        endfor

        Colour: "Black"
        Line width: 1
        Draw inner box

        # trajectory itself, broken at wrap points (Ring topology)
        Colour: {0.25, 0.50, 0.82}
        Line width: 2
        for f from 1 to n_frames
            wrapBreak = 0
            if topology = 2 and abs(plotPos[f] - plotPos[f-1]) > n_ch / 2
                wrapBreak = 1
            endif
            if wrapBreak = 0
                Draw line: t_frame[f-1], plotPos[f-1], t_frame[f], plotPos[f]
            else
                Colour: {0.55, 0.35, 0.65}
                Font size: 6
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
        Font size: 6
        Text: t_frame[0] + 0.015 * duration, "left", plotPos[0] - markerOffset, "Half", "Centre"

        Colour: {0.85, 0.38, 0.22}
        Paint circle (mm): {0.85, 0.38, 0.22}, t_frame[n_frames], plotPos[n_frames], 2.0
        Colour: "Black"
        Text: t_frame[n_frames] - 0.025 * duration, "right", plotPos[n_frames] + markerOffset, "Half", "end"

        # axis label
        Font size: 6
        Colour: {0.35, 0.35, 0.52}
        Text: (xmin + xmax) / 2, "Centre", axisLow + (axisHigh - axisLow) * 0.03, "Half", "Time (s)"
        Colour: "Black"
    else
        # --------------------------------------------------------
        # PANEL A-top -- Azimuth vs time (Ambisonic)
        # --------------------------------------------------------
        Select outer viewport: 0, 4.2, 0.75, 2.62
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.5, "Centre", 0.93, "Half", "Azimuth vs time  (degrees, 0-360)"

        Select inner viewport: 0.50, 4.00, 0.92, 2.54
        Axes: xmin, xmax, -10, 370
        Colour: {0.96, 0.96, 0.96}
        Paint rectangle: {0.96, 0.96, 0.96}, xmin, xmax, 0, 360

        Colour: {0.88, 0.88, 0.88}
        Line width: 1
        for gi to 5
            gVal = (gi - 1) * 90
            Draw line: xmin, gVal, xmax, gVal
        endfor
        Font size: 6
        Colour: {0.55, 0.55, 0.55}
        for gi to 5
            gVal = (gi - 1) * 90
            Text: xmin, "Left", gVal, "Half", fixed$(gVal, 0) + "°"
        endfor
        Colour: {0.88, 0.88, 0.88}
        for i from 0 to 5
            tx = xmin + i * (xmax - xmin) / 5
            Draw line: tx, 0, tx, 360
        endfor
        Colour: "Black"
        Line width: 1
        Draw inner box

        # azimuth path, broken at 0/360 wrap points
        Colour: {0.25, 0.50, 0.82}
        Line width: 2
        for f from 1 to n_frames
            if abs(azimuth_frame[f] - azimuth_frame[f-1]) > 180
                Colour: {0.55, 0.35, 0.65}
                Font size: 6
                Text: t_frame[f], "Centre", azimuth_frame[f], "Half", "wrap"
                Font size: 7
                Colour: {0.25, 0.50, 0.82}
            else
                Draw line: t_frame[f-1], azimuth_frame[f-1], t_frame[f], azimuth_frame[f]
            endif
        endfor
        Line width: 1

        Colour: {0.30, 0.68, 0.40}
        Paint circle (mm): {0.30, 0.68, 0.40}, t_frame[0], azimuth_frame[0], 2.0
        Colour: {0.85, 0.38, 0.22}
        Paint circle (mm): {0.85, 0.38, 0.22}, t_frame[n_frames], azimuth_frame[n_frames], 2.0
        Colour: "Black"
        Font size: 6
        Colour: {0.35, 0.35, 0.52}
        Text: (xmin + xmax) / 2, "Centre", 12, "Half", "Time (s)"
        Colour: "Black"

        # --------------------------------------------------------
        # PANEL A-bottom -- Elevation vs time (Ambisonic)
        # --------------------------------------------------------
        Select outer viewport: 0, 4.2, 2.68, 4.60
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.5, "Centre", 0.95, "Half", "Elevation vs time  (" + elevModeShort$ + ")"

        # axis range: fit the actual elevation extent, padded, clamped to +-90.
        elAxisLow = elevMinActual
        elAxisHigh = elevMaxActual
        if elAxisHigh - elAxisLow < 1
            elAxisLow = elAxisLow - 5
            elAxisHigh = elAxisHigh + 5
        endif
        elPad = (elAxisHigh - elAxisLow) * 0.12
        elAxisLow = elAxisLow - elPad
        elAxisHigh = elAxisHigh + elPad
        if elAxisLow < -90
            elAxisLow = -90
        endif
        if elAxisHigh > 90
            elAxisHigh = 90
        endif

        Select inner viewport: 0.50, 4.00, 2.86, 4.50
        Axes: xmin, xmax, elAxisLow, elAxisHigh
        Colour: {0.96, 0.96, 0.96}
        Paint rectangle: {0.96, 0.96, 0.96}, xmin, xmax, elAxisLow, elAxisHigh

        # horizontal elevation guides at -90/-45/0/45/90 where in range
        Line width: 1
        for gi to 5
            gv = -90 + (gi - 1) * 45
            if gv >= elAxisLow and gv <= elAxisHigh
                if gv = 0
                    Colour: {0.72, 0.72, 0.78}
                else
                    Colour: {0.88, 0.88, 0.88}
                endif
                Draw line: xmin, gv, xmax, gv
                Font size: 6
                Colour: {0.55, 0.55, 0.55}
                Text: xmin, "Left", gv, "Half", fixed$(gv, 0) + "°"
            endif
        endfor
        # vertical time guides
        Colour: {0.88, 0.88, 0.88}
        for i from 0 to 5
            tx = xmin + i * (xmax - xmin) / 5
            Draw line: tx, elAxisLow, tx, elAxisHigh
        endfor
        Colour: "Black"
        Line width: 1
        Draw inner box

        # elevation path (continuous -- clamped, never wrapped)
        Colour: {0.80, 0.45, 0.20}
        Line width: 2
        for f from 1 to n_frames
            Draw line: t_frame[f-1], elevation_frame[f-1], t_frame[f], elevation_frame[f]
        endfor
        Line width: 1

        Colour: {0.30, 0.68, 0.40}
        Paint circle (mm): {0.30, 0.68, 0.40}, t_frame[0], elevation_frame[0], 2.0
        Colour: {0.85, 0.38, 0.22}
        Paint circle (mm): {0.85, 0.38, 0.22}, t_frame[n_frames], elevation_frame[n_frames], 2.0
        Colour: "Black"
        Font size: 6
        Colour: {0.35, 0.35, 0.52}
        Text: (xmin + xmax) / 2, "Centre", elAxisLow + (elAxisHigh - elAxisLow) * 0.05, "Half", "Time (s)"
        Colour: "Black"
    endif

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
            Font size: 6
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
        if drawnElevation = 0
            elBTitle$ = "el=" + fixed$(fixed_elevation, 0) + "°"
        else
            elBTitle$ = "el " + fixed$(elevMinActual, 0) + ".." + fixed$(elevMaxActual, 0) + "°"
        endif
        Text: 0.5, "Centre", 0.97, "Half", "Top view (azimuth path, " + elBTitle$ + ")"

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
        Font size: 6
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
        line1$ = orderName$ + " order ambiX (" + string$(n_ch) + " ch) | Az " + fixed$(azMinActual, 1) + "-" + fixed$(azMaxActual, 1) + "° | El " + fixed$(elevMinActual, 1) + "-" + fixed$(elevMaxActual, 1) + "° | Dist " + fixed$(distance, 2) + " m | Rot " + fixed$(trajectory_rotation, 1) + "° | " + string$(control_rate) + " Hz"
        line2$ = "Elevation: " + elevModeDesc$ + " | Az " + mapping$ + " | Active: " + activeChannels$ + " | Encoded power -- mean (frames): " + fixed$(meanPower, 3) + ", min/max (frames+midpoints): " + fixed$(minPower, 3) + "/" + fixed$(maxPower, 3)
    endif
    Text: 0.5, "Centre", 0.68, "Half", line1$
    Text: 0.5, "Centre", 0.28, "Half", line2$

    # ============================================================
    # RESET
    # ============================================================
    Select outer viewport: 0, 8, 0, 6.88
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

@freeRender: 1
selectObject: result
Rename: output_name$
# Control tiers are implementation details only; never leave them in Objects.
@freeTiers

appendInfoLine: ""
appendInfoLine: "Created: ", output_name$, " (", n_ch, " ch)"
if amb
    appendInfoLine: "Raw ACN/SN3D field components: decode through a speaker-array or binaural"
    appendInfoLine: "ambisonic decoder for real spatial playback."
endif
appendInfoLine: "The stereo monitor is an approximation for checking motion and timing only."

finalView = 1
status$ = "Committed: " + output_name$ + ". Playing the stereo monitor."
@drawAll
@monitorMix
Play
removeObject: monitorMix.result
removeObject: mono
selectObject: result

###############################################################################
# PROCEDURES
###############################################################################

# Compute real ACN/SN3D coefficients for Full-3D HOA orders 1..5.
# Writes global acn[1..(maxOrder+1)^2], where acn[1] = ACN0.
# This is the same general associated-Legendre implementation used by the
# upgraded Higher-Order Ambisonic Encoder, so static and moving encoding stay
# numerically consistent through fifth order.
# Convention: azimuth CCW from front (+X), +Y = left, +Z = up.
procedure computeACN: .azDeg, .elDeg, .maxOrder
    .az = .azDeg * pi / 180
    .x = sin (.elDeg * pi / 180)
    .ce = cos (.elDeg * pi / 180)

    # Clear the complete HOA5 range so a lower-order call cannot retain values.
    for .i from 1 to 36
        acn[.i] = 0
    endfor

    # Unnormalised associated Legendre functions without the Condon-Shortley
    # phase. The recurrence is evaluated at x = sin(elevation), which matches
    # the ambiX coordinate convention used throughout AudioTools.
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

    # ACN index n = l(l+1)+m, represented here as array index n+1.
    # SN3D normalization for m>0 is sqrt(2 (l-m)!/(l+m)!).
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
