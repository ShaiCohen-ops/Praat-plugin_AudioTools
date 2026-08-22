# ============================================================
# Praat AudioTools - Spatial Trajectory Painter
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7.3 (2026) - Ambisonic trajectory output, optional drawn elevation
# v0.7.3 (2026): VISUALIZATION LAYOUT FIX - inset trajectory endpoint labels away from the adjacent panel rail; DSP unchanged.
# v0.7.2 (2026): VISUALIZATION LAYOUT FIX - keep trajectory endpoint labels inside their panel; DSP unchanged.
# v0.7.1 (2026): VISUALIZATION LAYOUT FIX - separate title/subtitle bands; DSP unchanged.
# v0.7 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
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
#     Control_rate for fast movement). Distance is held constant.
#
#     ELEVATION (new in v0.7) - elevation may be either a single FIXED
#       value for the whole sound (the original v0.5 behaviour), or a
#       second, INDEPENDENT drawn curve giving time-varying elevation.
#       When Elevation_control = "Drawn elevation curve", Phase 1 opens
#       TWO editors -- one for the azimuth curve (movement_azimuth) and
#       one for the elevation curve (movement_elevation) -- and Phase 2
#       encodes a genuine time-varying full-3D direction at every frame:
#         azimuth(t)   from movement_azimuth
#         elevation(t) from movement_elevation
#         distance     = fixed form value
#       The drawn elevation curve has its own Relative / Absolute mapping
#       (Elevation_mapping), separate from the azimuth Mapping_mode.
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
# Changelog:
#   v0.7 - Optional DRAWN ELEVATION for Ambisonic trajectory mode. A
#          second, independent PitchTier (movement_elevation) can now
#          drive elevation over time, in parallel with the azimuth curve
#          (movement_azimuth), producing genuine full-3D movement instead
#          of horizontal motion at a fixed height. The only change to the
#          encoding core is that @computeACN is now called with a
#          per-frame elevation_frame[f] instead of a single fixed
#          elevation; with Elevation_control = "Fixed elevation" that
#          per-frame value is constant, so v0.7 reproduces v0.5 output
#          numerically for the same input, settings, and azimuth curve.
#          Elevation has its own Relative / Absolute mapping and is always
#          clamped to [-90, +90] (never wrapped). Distance stays fixed.
#          The Ambisonic visualization gained an elevation-vs-time panel
#          and an elevation-aware summary/report. Speaker-array mode,
#          ACN/SN3D math, gain handling, and peak protection are unchanged.
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
    comment Elevation: use one fixed value, or draw a 2nd curve (Phase 1 then opens a 2nd editor).
    optionmenu Elevation_control: 1
        option Fixed elevation
        option Drawn elevation curve
    real Fixed_elevation_(degrees) 0
    comment Drawn-elevation mapping (used only when Elevation_control = Drawn elevation curve):
    optionmenu Elevation_mapping: 1
        option Relative
        option Absolute degrees
    real Minimum_elevation_(degrees) -45
    real Maximum_elevation_(degrees) 45
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

# drawnElevation is true only for Ambisonic mode with a drawn elevation curve.
# In Speaker-array mode the elevation controls are ignored entirely, and in
# Ambisonic fixed-elevation mode only Fixed_elevation is used.
drawnElevation = 0
if output_representation = 2 and elevation_control = 2
    drawnElevation = 1
endif

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
    # Clamp the FIXED elevation value to a valid range, same convention as the
    # Ambisonic Encoder. Used only when Elevation_control = Fixed elevation.
    if fixed_elevation > 90
        fixed_elevation = 90
    elsif fixed_elevation < -90
        fixed_elevation = -90
    endif
    # Validate / clamp the drawn-elevation TARGET range (Relative mapping).
    # Reverse ranges are an error rather than silently swapped.
    if elevation_control = 2
        if minimum_elevation > maximum_elevation
            exitScript: "Error: Minimum_elevation (" + fixed$(minimum_elevation, 1) + " deg) is greater than Maximum_elevation (" + fixed$(maximum_elevation, 1) + " deg). Set Minimum_elevation <= Maximum_elevation; the values are not reversed automatically."
        endif
        if minimum_elevation > 90
            minimum_elevation = 90
        elsif minimum_elevation < -90
            minimum_elevation = -90
        endif
        if maximum_elevation > 90
            maximum_elevation = 90
        elsif maximum_elevation < -90
            maximum_elevation = -90
        endif
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

    if drawnElevation = 1
        # --- Two independent curves: azimuth + elevation ---
        # Both PitchTiers share the mono Sound's time domain. Each opens in
        # its own editor so azimuth and elevation can be drawn separately.
        movement_az = Create PitchTier: "movement_azimuth", xmin, xmax
        movement_el = Create PitchTier: "movement_elevation", xmin, xmax

        selectObject: mono
        plusObject: movement_az
        View & Edit

        selectObject: mono
        plusObject: movement_el
        View & Edit

        writeInfoLine: "=== PHASE 1: TWO EDITORS OPENED (Ambisonic, drawn elevation) ==="
        appendInfoLine: "Two editors were opened on the same mono Sound:"
        appendInfoLine: "  * Editor with 'movement_azimuth'   -> draws AZIMUTH over time."
        appendInfoLine: "  * Editor with 'movement_elevation' -> draws ELEVATION over time."
        appendInfoLine: "In EACH editor:"
        appendInfoLine: "1. Click at the desired time/height INSIDE THE CURVE PANEL"
        appendInfoLine: "   (not the waveform panel) to position the cursor there."
        appendInfoLine: "2. Press Ctrl-T (Windows/Linux) or Cmd-T (Mac) to drop a point."
        appendInfoLine: "   Repeat to draw the curve. Drag existing points to reshape."
        appendInfoLine: "   Draw at least one point in BOTH editors."
        appendInfoLine: "   Output: Ambisonic trajectory (" + orderName$ + " order, 'n_ch' ambiX channels)."
        appendInfoLine: "   Azimuth mapping (Mapping_mode):"
        appendInfoLine: "     Relative -> drawn range maps to one full 360-degree turn (+Rotation)."
        appendInfoLine: "     Absolute -> drawn value IS azimuth in degrees (+Rotation), wrapped 0-360."
        if elevation_mapping = 1
            appendInfoLine: "   Elevation mapping: Relative -> drawn range maps to [" + fixed$(minimum_elevation, 1) + ", " + fixed$(maximum_elevation, 1) + "] deg."
        else
            appendInfoLine: "   Elevation mapping: Absolute -> drawn value IS elevation in degrees, clamped to [-90, +90]."
        endif
        appendInfoLine: "   Distance stays fixed at 'distance:2' m."
        appendInfoLine: "3. Go back to the Objects window."
        appendInfoLine: "4. Select the mono Sound '" + sound_name$ + "_mono' AND BOTH"
        appendInfoLine: "   'movement_azimuth' AND 'movement_elevation'."
        appendInfoLine: "5. Run this script again."

        exitScript: "Phase 1 complete. Draw both curves, select the mono Sound + both tiers, and run again."
    else
        # --- Single curve: azimuth / channel position only ---
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
            appendInfoLine: "   Elevation and distance stay fixed at 'fixed_elevation:1' deg / 'distance:2' m."
        endif
        appendInfoLine: "3. Go back to the Objects window."
        appendInfoLine: "4. Select BOTH '" + sound_name$ + "_mono' AND 'movement'."
        appendInfoLine: "5. Run this script again."

        exitScript: "Phase 1 complete. Draw the curve, select both objects, and run again."
    endif

elsif n_sounds = 1 and (n_tiers = 1 or n_tiers = 2)
    # === PHASE 2: PROCESSING ===

    mono = selected("Sound")
    mono_name$ = selected$("Sound")

    # Capture the selected PitchTier id(s) and name(s) NOW, before any
    # selectObject narrows the selection (which would drop the tiers).
    for i to n_tiers
        selTierId[i] = selected("PitchTier", i)
        selTierName$[i] = selected$("PitchTier", i)
    endfor

    # --- Sound safety checks (shared by both phases) ---
    selectObject: mono
    n_channels_check = Get number of channels
    if n_channels_check <> 1
        exitScript: "Error: the selected Sound must be mono (it has 'n_channels_check' channels). Run Phase 1 first."
    endif
    mono_xmin = Get start time
    mono_xmax = Get end time

    if drawnElevation = 1
        # --- Drawn-elevation mode expects EXACTLY two named tiers ---
        if n_tiers <> 2
            # Self-diagnosing message: the cause is almost always either
            # (a) Elevation_control was 'Fixed' during Phase 1 (so only a single
            #     'movement' tier exists) but 'Drawn' now, or
            # (b) only one of the two drawn tiers was selected.
            diag$ = ""
            for i to n_tiers
                diag$ = diag$ + "'" + selTierName$[i] + "'"
                if i < n_tiers
                    diag$ = diag$ + ", "
                endif
            endfor
            if n_tiers = 1 and selTierName$[1] = "movement"
                exitScript: "Error: Elevation_control mismatch. The selected tier 'movement' was created by a Phase 1 run with Elevation_control = Fixed elevation (azimuth only), but this run has Elevation_control = Drawn elevation curve, which needs TWO curves. Fix by EITHER (1) re-running Phase 1 with Elevation_control = Drawn elevation curve to create 'movement_azimuth' + 'movement_elevation', OR (2) setting Elevation_control = Fixed elevation to process this 'movement' tier as-is. Elevation_control must be the SAME in Phase 1 and Phase 2."
            elsif n_tiers = 1 and selTierName$[1] = "movement_azimuth"
                exitScript: "Error: only 'movement_azimuth' is selected; the elevation curve 'movement_elevation' is missing from the selection. In the Objects window select the mono Sound PLUS BOTH 'movement_azimuth' and 'movement_elevation', then run again. (If 'movement_elevation' is not in the list, re-run Phase 1 with Elevation_control = Drawn elevation curve.)"
            elsif n_tiers = 1 and selTierName$[1] = "movement_elevation"
                exitScript: "Error: only 'movement_elevation' is selected; the azimuth curve 'movement_azimuth' is missing from the selection. Select the mono Sound PLUS BOTH tiers and run again."
            elsif n_tiers = 1
                exitScript: "Error: 'Drawn elevation curve' needs TWO PitchTiers named 'movement_azimuth' and 'movement_elevation', but only 1 is selected (" + diag$ + "). Select the mono Sound plus BOTH tiers, or re-run Phase 1 in drawn-elevation mode. Elevation_control must match between Phase 1 and Phase 2."
            else
                exitScript: "Error: 'Drawn elevation curve' needs EXACTLY two PitchTiers ('movement_azimuth' and 'movement_elevation'), but 'n_tiers' are selected (" + diag$ + "). Deselect any extra PitchTiers and select only the mono Sound + those two."
            endif
        endif

        # Identify tiers by exact name -- order-independent.
        movement_az = 0
        movement_el = 0
        for i to n_tiers
            tid = selTierId[i]
            tname$ = selTierName$[i]
            if tname$ = "movement_azimuth"
                movement_az = tid
            elsif tname$ = "movement_elevation"
                movement_el = tid
            endif
        endfor
        if movement_az = 0
            exitScript: "Error: no PitchTier named 'movement_azimuth' is selected. Select the mono Sound plus 'movement_azimuth' and 'movement_elevation' created in Phase 1."
        endif
        if movement_el = 0
            exitScript: "Error: no PitchTier named 'movement_elevation' is selected. Select the mono Sound plus 'movement_azimuth' and 'movement_elevation' created in Phase 1."
        endif

        # movement drives azimuth for the shared sampling / range code below.
        movement = movement_az

        # Time-domain checks for BOTH tiers.
        selectObject: movement_az
        az_xmin = Get start time
        az_xmax = Get end time
        if abs(az_xmin - mono_xmin) > 0.001 or abs(az_xmax - mono_xmax) > 0.001
            exitScript: "Error: 'movement_azimuth' time domain does not match the Sound's. Use the tiers created together with this Sound in Phase 1."
        endif
        n_points = Get number of points
        if n_points < 1
            exitScript: "Error: draw at least 1 point on 'movement_azimuth' before running Phase 2."
        endif

        selectObject: movement_el
        el_xmin = Get start time
        el_xmax = Get end time
        if abs(el_xmin - mono_xmin) > 0.001 or abs(el_xmax - mono_xmax) > 0.001
            exitScript: "Error: 'movement_elevation' time domain does not match the Sound's. Use the tiers created together with this Sound in Phase 1."
        endif
        n_el_points = Get number of points
        if n_el_points < 1
            exitScript: "Error: draw at least 1 point on 'movement_elevation' before running Phase 2."
        endif
    else
        # --- Fixed-elevation / Speaker mode expects EXACTLY one tier ---
        if n_tiers <> 1
            hasAz = 0
            hasEl = 0
            for i to n_tiers
                if selTierName$[i] = "movement_azimuth"
                    hasAz = 1
                elsif selTierName$[i] = "movement_elevation"
                    hasEl = 1
                endif
            endfor
            if n_tiers = 2 and hasAz = 1 and hasEl = 1
                exitScript: "Error: Elevation_control mismatch. You selected the two drawn curves 'movement_azimuth' + 'movement_elevation', but this run has Elevation_control = Fixed elevation, which expects ONE 'movement' tier. Set Elevation_control = Drawn elevation curve to use both curves."
            else
                exitScript: "Error: this mode needs ONE PitchTier ('movement'), but 'n_tiers' are selected. To draw a moving elevation, set Elevation_control = Drawn elevation curve and re-run Phase 1."
            endif
        endif

        movement = selTierId[1]
        movement_el = 0

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
    endif

    if output_representation = 1
        repName$ = "SPEAKER-ARRAY PAN"
    else
        repName$ = "AMBISONIC TRAJECTORY (" + orderName$ + " order)"
    endif

    writeInfoLine: "=== PHASE 2: GENERATING ", repName$, " ==="
    appendInfoLine: "Channels: 'n_ch'"
    appendInfoLine: "Points drawn (azimuth): 'n_points'"
    if drawnElevation = 1
        appendInfoLine: "Points drawn (elevation): 'n_el_points'"
    endif
    if mapping_mode = 1
        appendInfoLine: "Azimuth mapping: Relative (fit to full range)"
    else
        if output_representation = 1
            appendInfoLine: "Mapping: Absolute (Base='base_value', Step='step_value')"
        else
            appendInfoLine: "Azimuth mapping: Absolute (drawn value = azimuth in degrees)"
        endif
    endif
    if output_representation = 2
        if drawnElevation = 0
            appendInfoLine: "Elevation: Fixed 'fixed_elevation:1' deg, Distance: 'distance:2' m, Rotation: 'trajectory_rotation:1' deg"
        else
            if elevation_mapping = 1
                appendInfoLine: "Elevation: Drawn (Relative -> [" + fixed$(minimum_elevation, 1) + ", " + fixed$(maximum_elevation, 1) + "] deg), Distance: 'distance:2' m, Rotation: 'trajectory_rotation:1' deg"
            else
                appendInfoLine: "Elevation: Drawn (Absolute degrees), Distance: 'distance:2' m, Rotation: 'trajectory_rotation:1' deg"
            endif
        endif
    endif

else
    exitScript: "SELECTION ERROR: To start, select 1 Sound. To finish, select the mono Sound AND the 'movement' PitchTier (or, for drawn elevation, 'movement_azimuth' AND 'movement_elevation')."
endif

###############################################################################
# MAIN LOGIC (Runs only in Phase 2)
###############################################################################

selectObject: mono
xmin = Get start time
xmax = Get end time
duration = xmax - xmin

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
        @computeACN: azimuth_frame[f], elevation_frame[f]
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
    Select outer viewport: 0, 8, 0, 0.30
    Select inner viewport: 0.60, 7.70, 0.02, 0.28
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 12
    Text: 0.5, "Centre", 0.5, "Half", "##SPATIAL TRAJECTORY PAINTER v0.7.3##"
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
# In drawn-elevation mode, 'movement' is the azimuth tier (movement_azimuth);
# the elevation tier (movement_elevation) is removed separately when present.
removeObject: movement
if drawnElevation = 1
    removeObject: movement_el
endif

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
    appendInfoLine: ""
    appendInfoLine: "--- Ambisonic trajectory report ---"
    appendInfoLine: "Representation: Ambisonic trajectory"
    appendInfoLine: "Order: " + orderName$
    appendInfoLine: "Channels: " + string$(n_ch)
    appendInfoLine: "Azimuth control: drawn"
    if mapping_mode = 1
        appendInfoLine: "Azimuth mapping: Relative"
    else
        appendInfoLine: "Azimuth mapping: Absolute"
    endif
    if drawnElevation = 0
        appendInfoLine: "Elevation control: Fixed (" + fixed$(fixed_elevation, 1) + " deg)"
    else
        appendInfoLine: "Elevation control: Drawn"
        if elevation_mapping = 1
            appendInfoLine: "Elevation mapping: Relative -> [" + fixed$(minimum_elevation, 1) + ", " + fixed$(maximum_elevation, 1) + "] deg"
        else
            appendInfoLine: "Elevation mapping: Absolute degrees"
        endif
    endif
    appendInfoLine: "Elevation range: " + fixed$(elevMinActual, 1) + " to " + fixed$(elevMaxActual, 1) + " deg"
    appendInfoLine: "Distance: " + fixed$(distance, 2) + " m (fixed)"
    appendInfoLine: "Control rate: " + string$(control_rate) + " Hz"
    appendInfoLine: "Output convention: ambiX ACN/SN3D Full 3D"
    appendInfoLine: ""
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
