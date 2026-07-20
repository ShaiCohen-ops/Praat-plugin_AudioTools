# ============================================================
# Praat AudioTools - Spatial Trajectory Painter
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spatial Trajectory Painter
#   Convert a Sound to mono, then draw a curve directly on the
#   waveform (a PitchTier opened together with the sound). The
#   mono signal is panned across N output channels (4/6/8/12/16)
#   by equal-power gains (cos/sin crossfade) that follow that curve,
#   using one of two mapping modes:
#
#   RELATIVE (default) - the min and max of whatever you drew are
#     stretched to fill the whole channel array (channel 1 ... last
#     channel). Convenient: draw anything, it always uses the full
#     array. A flat curve sits in the middle of the array.
#
#   ABSOLUTE - a fixed scale: channel_position =
#     (drawn_value - Base_value) / Step_value + 1, e.g. with
#     Base=100, Step=100: 100 Hz -> ch.1, 200 Hz -> ch.2, ...
#     Useful when you want precise, repeatable control over which
#     channels are addressed, or motion confined to a few channels.
#     A flat curve stays exactly where you drew it.
#
# Topology:
#   Line (default) - position is clamped to [channel 1 ... channel N].
#   Ring - position wraps around a full loop: going past the last
#          channel brings you back toward channel 1.
#
# Usage:
#   PHASE 1 - Select 1 Sound -> Run -> a mono copy is made and an
#             editor opens showing the waveform with an empty
#             PitchTier curve ("movement") on top.
#             Click at the desired time/height inside the CURVE
#             panel (not the waveform panel) to move the cursor
#             there, then press Ctrl-T (Cmd-T on Mac) to drop a
#             point. Repeat to draw the movement. One point is
#             enough for a fixed, static pan position.
#   PHASE 2 - Back in the Objects window, select the MONO sound
#             (name ends in "_mono") AND the "movement" PitchTier
#             -> Run again -> the N-channel panned Sound is created.
#             The mono sound and the movement PitchTier are removed
#             at the end of Phase 2 along with the other temporary
#             objects, leaving only the final multichannel result.
#             If you want to redraw and try again, re-run Phase 1
#             from the original source Sound.
#
# Note: Phase 1 (mono conversion + editor opening) and Phase 2 (including
# the Copy + Formula channel-gain application via object(id, x), which
# replaced "Multiply" in v0.4 to avoid its silent 0.9-peak rescaling) have
# been run and confirmed working end-to-end, including the visualization.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
###############################################################################
# Spatial Trajectory Painter (Form-Based, Two-Phase)
#
# A. SETUP: Select 1 Sound -> Run -> mono copy + editor open for drawing.
# B. CREATE: Select mono Sound + PitchTier "movement" -> Run -> panned output.
###############################################################################

form Spatial Trajectory Painter Settings
    comment Output channel configuration:
    optionmenu Number_of_channels: 3
        option 4
        option 6
        option 8
        option 12
        option 16
    optionmenu Topology 1
        option Line (clamp at ends)
        option Ring (wrap around)

    comment Mapping mode (how the drawn height becomes a channel position):
    optionmenu Mapping_mode 1
        option Relative (fit drawn curve to full array)
        option Absolute (fixed height-to-channel mapping)

    comment Absolute mode settings (ignored in Relative mode):
    comment (value = Base_value means channel 1, value = Base_value + Step_value means channel 2, etc.)
    positive Base_value 100
    positive Step_value 100

    comment Control resolution for reading the drawn curve:
    positive Control_rate_(Hz) 100

    comment Output:
    word Output_name movement_panner_output
    boolean Draw_visualization 1
endform

n_ch = number(number_of_channels$)

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
    appendInfoLine: "   With Mapping_mode = Relative (default): whatever range you"
    appendInfoLine: "   draw is stretched to cover the whole channel array."
    appendInfoLine: "   With Mapping_mode = Absolute: 'base_value' = channel 1,"
    appendInfoLine: "   " + string$(base_value + step_value) + " = channel 2, etc. (fixed scale)."
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

    writeInfoLine: "=== PHASE 2: GENERATING MOVEMENT PAN ==="
    appendInfoLine: "Channels: 'n_ch'"
    appendInfoLine: "Points drawn: 'n_points'"
    if mapping_mode = 1
        appendInfoLine: "Mapping: Relative (fit to full array)"
    else
        appendInfoLine: "Mapping: Absolute (Base='base_value', Step='step_value')"
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

# --- Sample the drawn curve at a fixed control rate, map to channel position ---
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
        # Relative: stretch the drawn range to fill the whole array
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
        if topology = 1
            chanPos_frame[f] = 1 + posNorm * (n_ch - 1)
        else
            chanPos_frame[f] = 1 + posNorm * n_ch
        endif
    else
        # Absolute: fixed scale
        chanPos_frame[f] = (v - base_value) / step_value + 1
    endif
endfor

# --- Build one equal-power gain AmplitudeTier per output channel ---
for c to n_ch
    gainTier = Create AmplitudeTier: "gain" + string$(c), xmin, xmax
    for f from 0 to n_frames
        t = t_frame[f]
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

        gainArr[c,f] = gain
        Add point: t, gain
    endfor
    gain_id[c] = gainTier
endfor

# --- Multiply the mono signal by each channel's gain envelope ---
# NOTE: we deliberately do NOT use the "Multiply" command here.
# Sound & AmplitudeTier: Multiply rescales its result to a peak of
# 0.9, independently for every channel -- which would destroy the
# equal-power balance between channels we just computed. Instead we
# copy the mono sound and apply the gain with Formula, which edits
# samples in place with no rescaling.
for c to n_ch
    selectObject: mono
    Copy: "ch" + string$(c)
    ch_id[c] = selected("Sound")
    gid = gain_id[c]
    Formula: "self * object('gid', x)"
endfor

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
# Draws an 8x8-canvas Picture-window overview of the movement pan, using
# the suite's standard outer-viewport-title / inner-viewport-data pattern
# (the small gap between each panel's outer and inner viewport is the
# title strip). Uses gainArr[c,f], captured above while the AmplitudeTiers
# were built, instead of re-querying the AmplitudeTier objects via
# object(id,x) -- that lookup pattern has been a recurring source of bugs
# elsewhere in this suite, so it's avoided here entirely.
#
# Phase 2 and the Picture-window visualization have been tested
# end-to-end in Praat. For 12/16-channel output, watch for label crowding
# in the Speaker array and Channel utilization panels; channelFontSize
# and maxSpeakerDiameter below scale down automatically above 8 channels,
# but very dense arrays may still benefit from a manual check.
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

    # --- scale labels / speaker dots down for denser 12- and 16-channel arrays ---
    if n_ch > 8
        channelFontSize = 4
        maxSpeakerDiameter = 3.2
    else
        channelFontSize = 5
        maxSpeakerDiameter = 4.5
    endif

    # --- topology / mapping strings for the subtitle and summary ---
    if topology = 1
        topology$ = "Line"
    else
        topology$ = "Ring"
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

    # --- per-channel active-time percentage (gain > 0.001) ---
    totalFrames = n_frames + 1
    for c to n_ch
        activeCount = 0
        for f from 0 to n_frames
            if gainArr[c,f] > 0.001
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
                activeList$ = string$(c)
            else
                activeList$ = activeList$ + ", " + string$(c)
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

    # --- equal-power diagnostic: sum of squared gains at each control frame,
    # ---   plus the midpoint of every consecutive frame pair. AmplitudeTiers
    # ---   interpolate linearly between points, so the midpoint gain is just
    # ---   the average of the two frame gains; checking it catches most
    # ---   real power dips that a fast movement could cause between frames,
    # ---   without needing to resample the full audio-rate signal.
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

    # --- plotted channel position per frame (clamped for Line, wrapped for Ring) ---
    for f from 0 to n_frames
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
    Text: 0.5, "Centre", 0.80, "Half", "##MOVEMENT PANNER##"
    Font size: 7
    Colour: {0.35, 0.35, 0.52}
    escapedName$ = replace$(mono_name$, "_", "\_ ", 0)
    subtitle$ = escapedName$ + "  |  " + string$(n_ch) + " channels  |  " + topology$ + "  |  " + mapping$ + "  |  " + fixed$(duration, 2) + " s  |  " + string$(control_rate) + " Hz control"
    Text: 0.5, "Centre", 0.15, "Half", subtitle$
    Colour: "Black"

    # ============================================================
    # PANEL A -- Movement trajectory (large left panel)
    # ============================================================
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "Centre", 0.97, "Half", "Movement trajectory  (vertical position = output channel)"

    Select inner viewport: 0.50, 4.00, 0.85, 4.50
    Axes: xmin, xmax, 0, n_ch + 1
    Colour: {0.96, 0.96, 0.96}
    Paint rectangle: {0.96, 0.96, 0.96}, xmin, xmax, 0.5, n_ch + 0.5

    # horizontal channel-centre guides
    Colour: {0.88, 0.88, 0.88}
    Line width: 1
    for ch from 1 to n_ch
        Draw line: xmin, ch, xmax, ch
    endfor
    # vertical time guides
    nTicks = 5
    for i from 0 to nTicks
        tx = xmin + i * (xmax - xmin) / nTicks
        Draw line: tx, 0.5, tx, n_ch + 0.5
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box

    # trajectory itself, broken at Ring wrap points
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
            Font size: 4
            Text: t_frame[f], "Centre", plotPos[f], "Half", "wrap"
            Font size: 7
            Colour: {0.25, 0.50, 0.82}
        endif
    endfor
    Line width: 1

    # start / end markers
    Colour: {0.30, 0.68, 0.40}
    Paint circle (mm): {0.30, 0.68, 0.40}, t_frame[0], plotPos[0], 2.0
    Colour: "Black"
    Font size: 5
    Text: t_frame[0], "Centre", plotPos[0] - 0.4, "Half", "start"

    Colour: {0.85, 0.38, 0.22}
    Paint circle (mm): {0.85, 0.38, 0.22}, t_frame[n_frames], plotPos[n_frames], 2.0
    Colour: "Black"
    Text: t_frame[n_frames], "Centre", plotPos[n_frames] + 0.4, "Half", "end"

    # axis label
    Font size: 6
    Colour: {0.35, 0.35, 0.52}
    Text: (xmin + xmax) / 2, "Centre", 0.15, "Half", "Time (s)"
    Colour: "Black"

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

    # ============================================================
    # PANEL C -- Channel utilization (lower right)
    # ============================================================
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "Centre", 0.97, "Half", "Channel utilization  (% of time active)"

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
        Text: -3, "Right", yCentre, "Half", "Ch" + string$(c)
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box

    # ============================================================
    # PANEL D -- Per-channel gain heatmap (full width)
    # ============================================================
    Select outer viewport: 0, 8, 4.68, 5.95
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "Centre", 0.97, "Half", "Per-channel gain map  (colour intensity = gain)"

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
            sumG = 0
            cnt = 0
            for f from startF to endF
                sumG = sumG + gainArr[c,f]
                cnt = cnt + 1
            endfor
            binGain[c,b] = sumG / cnt
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
        Text: -3, "Right", c, "Half", string$(c)
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
    line1$ = mapping$ + " | " + topology$ + " | " + string$(n_ch) + " channels | Range " + fixed$(drawnMin, 1) + "-" + fixed$(drawnMax, 1) + " | " + fixed$(duration, 2) + " s"
    line2$ = "Active channels: " + activeChannels$ + " | Control-frame power gain -- mean: " + fixed$(meanPower, 3) + ", min: " + fixed$(minPower, 3) + ", max: " + fixed$(maxPower, 3)
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

selectObject: result
appendInfoLine: "Done! Created: 'output_name$' ('n_ch' channels)."
Play
