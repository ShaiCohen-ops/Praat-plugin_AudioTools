# ==============================================================================
# Praat AudioTools - Doppler_Effect_Simulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
#
# Description:
#   Simulates a physical Doppler effect (moving source, stationary listener).
#   Includes Presets and Visualization.
#
# Changelog v1.3:
#   - Preserves the original channel count. Doppler pitch is analysed once
#     from a mono reference, then the same target PitchTier is resynthesized
#     independently on every source channel and recombined in channel order.
#   - Fixes non-zero Sound start times. Time_at_closest_s is interpreted as
#     seconds from the beginning of the selected Sound; presets use its true
#     midpoint (startTime + duration/2).
#   - Adds physical/technical validation: non-negative subsonic speed,
#     positive closest distance, closest-time inside the Sound, valid pitch
#     analysis range, and analysis ceiling below Nyquist.
#   - PitchTier sampling now always includes the exact endTime.
#   - Extreme target pitches are limited to a sampling-safe 20 Hz..0.45*SR
#     range, with the number of limited control points reported.
#   - Amplitude cue uses the corrected absolute closest-time coordinate.
#   - Normalization checks for a non-silent result before scaling.
#   - Visualization title and info box now set explicit normalized axes.
# Changelog v1.2:
#   - Fixed Praat syntax (elsif, =, #)
#   - Fixed viewport widths
#   - Added info output
# ==============================================================================

# ==============================================================================
#  1. INPUT VALIDATION
# ==============================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

# Get global constraints
selectObject: originalSound
totalDuration = Get total duration
startTime = Get start time
endTime = Get end time
sr = Get sampling frequency
nChannels = Get number of channels

# ==============================================================================
#  2. USER FORM & PRESETS
# ==============================================================================

form Doppler Effect Simulator v1.3
    comment Select a Preset or use Custom settings
    optionmenu Preset 1
        option Custom
        option Fast Car (City Street)
        option Jet Flyover (High Altitude)
        option Ambulance Passing (Close)
        option Slow Bicycle
        option Sci-Fi Warp (Extreme)
    
    comment Custom Parameters (ignored if Preset is not Custom)
    real Speed_m_s 25.0
    real Closest_distance_m 5.0
    real Time_at_closest_s 0.5
    comment (seconds from the beginning of the selected Sound)
    
    comment Effect Settings
    boolean Apply_amplitude_cue 1
    boolean Normalize_output 1
    
    comment Visualization & Playback
    boolean Visualize 1
    boolean Play 1
    
    comment Technical (Pitch Analysis)
    positive Min_pitch_Hz 75
    positive Max_pitch_Hz 600
endform

# --- Apply Presets ---
# Variables: v (speed), d (distance), t_c (time closest)

# Default to form values.
# Time_at_closest_s is a RELATIVE offset from the Sound's start time.
v = speed_m_s
d = closest_distance_m
t_c_offset = time_at_closest_s

if preset = 2
    # Fast Car (City Street) ~50 km/h, close lane
    v = 15.0
    d = 4.0
    t_c_offset = totalDuration / 2
    presetName$ = "Fast Car"
elsif preset = 3
    # Jet Flyover (High Altitude) subsonic jet, high altitude
    v = 250.0
    d = 100.0
    t_c_offset = totalDuration / 2
    presetName$ = "Jet Flyover"
elsif preset = 4
    # Ambulance Passing (Close)
    v = 20.0
    d = 2.0
    t_c_offset = totalDuration / 2
    presetName$ = "Ambulance"
elsif preset = 5
    # Slow Bicycle
    v = 5.0
    d = 1.0
    t_c_offset = totalDuration / 2
    presetName$ = "Bicycle"
elsif preset = 6
    # Sci-Fi Warp (Extreme) Mach 1, extremely close
    v = 340.0
    d = 0.5
    t_c_offset = totalDuration / 2
    presetName$ = "Sci-Fi Warp"
else
    presetName$ = "Custom"
endif

# Speed of sound in air (m/s)
c_sound = 343.0

# === Validate Physics / Analysis Parameters ===
if v < 0
    exitScript: "Speed_m_s must be non-negative."
endif
if v >= c_sound
    exitScript: "This simulator uses the classical subsonic moving-source model." + newline$
        ... + "Speed_m_s must be lower than the speed of sound (" + string$(c_sound) + " m/s)."
endif
if d <= 0
    exitScript: "Closest_distance_m must be greater than zero."
endif
if t_c_offset < 0 or t_c_offset > totalDuration
    exitScript: "Time_at_closest_s must lie between 0 and the Sound duration (" + fixed$(totalDuration, 3) + " s)."
endif
if min_pitch_Hz >= max_pitch_Hz
    exitScript: "Min_pitch_Hz must be lower than Max_pitch_Hz."
endif
if max_pitch_Hz >= sr / 2
    exitScript: "Max_pitch_Hz must be below the Nyquist frequency (" + fixed$(sr / 2, 1) + " Hz)."
endif

# Convert relative closest-time offset to the Sound's absolute time domain.
t_c = startTime + t_c_offset

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  DOPPLER EFFECT SIMULATOR v1.3"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", originalName$, " (", fixed$(totalDuration, 2), "s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""
writeInfoLine: "=== Physics Parameters ==="
writeInfoLine: "  Source speed: ", fixed$(v, 1), " m/s (", fixed$(v * 3.6, 1), " km/h)"
writeInfoLine: "  Closest distance: ", fixed$(d, 1), " m"
writeInfoLine: "  Time at closest: ", fixed$(t_c_offset, 2), " s after Sound start"
writeInfoLine: "  Absolute closest time: ", fixed$(t_c, 3), " s"
writeInfoLine: "  Channels preserved: ", nChannels
writeInfoLine: "  Speed of sound: ", fixed$(c_sound, 0), " m/s"
writeInfoLine: ""

# Calculate max pitch shift
max_shift_approach = c_sound / (c_sound - v)
max_shift_recede = c_sound / (c_sound + v)
appendInfoLine: "=== Expected Pitch Shift ==="
appendInfoLine: "  Approaching: ", fixed$((max_shift_approach - 1) * 100, 1), "% higher"
appendInfoLine: "  Receding: ", fixed$((1 - max_shift_recede) * 100, 1), "% lower"
appendInfoLine: ""

# ==============================================================================
#  3. PROCESSING (PHYSICS ENGINE)
# ==============================================================================

appendInfoLine: "Processing..."

# Prepare Data Storage for Visualization (Table)
steps_vis = 100
Create TableOfReal: "DopplerVisData", steps_vis, 4
visTableID = selected("TableOfReal")

# --- Step 3a: Pitch Analysis and Multichannel Resynthesis ---

# Analyse pitch once from a mono reference.
selectObject: originalSound
if nChannels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: originalName$ + "_Doppler_analysis"
endif

selectObject: analysisMono
pitchID = To Pitch: 0.0, min_pitch_Hz, max_pitch_Hz

# Reject material for which this PSOLA-based implementation has no usable
# voiced pitch contour.
selectObject: pitchID
medianPitch = Get quantile: 0, 0, 0.5, "Hertz"
if medianPitch = undefined
    removeObject: pitchID, analysisMono, visTableID
    exitScript: "No usable pitch was detected." + newline$
        ... + "This PSOLA-based Doppler simulator requires voiced / periodic material."
endif

Create PitchTier: "DopplerShift", startTime, endTime
pitchTierID = selected("PitchTier")

# Sample the physical factor at a fixed 10-ms control interval, always adding
# the exact Sound end time.
timeStep = 0.01
numSteps = ceiling(totalDuration / timeStep)
targetMinHz = 20
targetMaxHz = 0.45 * sr
limitedPitchPoints = 0
voicedPitchPoints = 0

for i from 0 to numSteps
    if i = numSteps
        t = endTime
    else
        t = min(endTime, startTime + i * timeStep)
    endif

    # Moving source, stationary listener.
    t_rel = t - t_c
    x_dist = v * t_rel
    hyp_dist = sqrt(d^2 + x_dist^2)

    v_radial = v * (x_dist / hyp_dist)
    factor = c_sound / (c_sound + v_radial)

    selectObject: pitchID
    val = Get value at time: t, "Hertz", "Linear"
    if val <> undefined and val > 0
        newVal = val * factor

        # Sampling-safe target range for extreme settings (notably Warp).
        if newVal < targetMinHz
            newVal = targetMinHz
            limitedPitchPoints += 1
        elsif newVal > targetMaxHz
            newVal = targetMaxHz
            limitedPitchPoints += 1
        endif

        selectObject: pitchTierID
        Add point: t, newVal
        voicedPitchPoints += 1
    endif
endfor

if voicedPitchPoints = 0
    removeObject: pitchTierID, pitchID, analysisMono, visTableID
    exitScript: "Pitch analysis produced no usable Doppler control points."
endif

appendInfoLine: "  Pitch control points: ", voicedPitchPoints
if limitedPitchPoints > 0
    appendInfoLine: "  Extreme target points limited for sampling safety: ", limitedPitchPoints
endif

# Resynthesize each original channel independently with the same target tier.
channelResultIDs# = zero#(nChannels)

for ch from 1 to nChannels
    selectObject: originalSound
    if nChannels = 1
        channelWork = Copy: originalName$ + "_Doppler_ch1"
    else
        channelWork = Extract one channel: ch
        Rename: originalName$ + "_Doppler_ch" + string$(ch)
    endif

    selectObject: channelWork
    channelManip = To Manipulation: 0.01, min_pitch_Hz, max_pitch_Hz

    selectObject: pitchTierID
    plusObject: channelManip
    Replace pitch tier

    selectObject: channelManip
    channelResult = Get resynthesis (overlap-add)
    Rename: originalName$ + "_Doppler_tmp" + string$(ch)

    channelResultIDs#[ch] = channelResult
    removeObject: channelManip, channelWork
endfor

# Combine to stereo can combine any number of mono Sounds; with sequentially
# created channel results, object creation order equals source channel order.
if nChannels = 1
    dopplerSoundID = channelResultIDs#[1]
    selectObject: dopplerSoundID
else
    selectObject: channelResultIDs#[1]
    for ch from 2 to nChannels
        plusObject: channelResultIDs#[ch]
    endfor
    dopplerSoundID = Combine to stereo
endif

selectObject: dopplerSoundID
Rename: originalName$ + "_Doppler"

# Remove temporary per-channel resyntheses after the combined output exists.
if nChannels > 1
    for ch from 1 to nChannels
        removeObject: channelResultIDs#[ch]
    endfor
endif

# Analysis objects are no longer needed.
removeObject: pitchID, pitchTierID, analysisMono

# --- Step 3b: Amplitude Manipulation ---

if apply_amplitude_cue
    selectObject: dopplerSoundID
    
    # Pre-calculate formula constants
    d_sq = d^2
    v_sq = v^2
    
    # Formula string: self * ( d / sqrt(d^2 + v^2 * (x - t_c)^2) )
    fs_1$ = string$(d) + " / sqrt(" + string$(d_sq) + " + " + string$(v_sq)
    fs_2$ = " * (x - " + string$(t_c) + ")^2)"
    formula$ = "self * (" + fs_1$ + fs_2$ + ")"
    
    Formula: formula$
    
    appendInfoLine: "  Applied amplitude distance cue"
endif

if normalize_output
    selectObject: dopplerSoundID
    outputPeak = Get absolute extremum: 0, 0, "None"
    if outputPeak > 1e-15
        Scale peak: 0.99
        appendInfoLine: "  Normalized output to 0.99 peak"
    else
        appendInfoLine: "  Output is silent; normalization skipped"
    endif
endif

# --- Step 3c: Fill Visualization Table & Calculate Bounds ---

# Initialize bounds to extreme values
vis_max_factor = -1000
vis_min_factor = 1000
vis_max_gain = -1000

selectObject: visTableID
for i from 1 to steps_vis
    t = startTime + (i-1) * (totalDuration / (steps_vis - 1))
    
    t_rel = t - t_c
    x_dist = v * t_rel
    hyp_dist = sqrt(d^2 + x_dist^2)
    
    if hyp_dist > 0.0001
        v_radial = v * (x_dist / hyp_dist)
    else
        v_radial = 0
    endif
    
    factor = c_sound / (c_sound + v_radial)
    gain = d / hyp_dist
    
    # Store in table
    Set value: i, 1, t
    Set value: i, 2, factor
    Set value: i, 3, gain
    Set value: i, 4, hyp_dist
    
    # Update Max/Min
    if factor > vis_max_factor
        vis_max_factor = factor
    endif
    if factor < vis_min_factor
        vis_min_factor = factor
    endif
    if gain > vis_max_gain
        vis_max_gain = gain
    endif
endfor

# ==============================================================================
#  4. VISUALIZATION
# ==============================================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    Font size: 10
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Doppler Effect## | " + presetName$ + " | " + fixed$(v, 0) + " m/s @ " + fixed$(d, 1) + "m"
    Font size: 10
    
    # --- A. Spatial Schematic (Top) ---
    Select outer viewport: 0, 8, 0.6, 2.4
    Select inner viewport: 0.8, 7.6, 0.8, 2.2
    
    Axes: startTime, endTime, -3, 4
    
    # Background
    Paint rectangle: "{0.95, 0.97, 1}", startTime, endTime, -3, 4
    
    # Draw Listener
    Colour: "Black"
    Paint circle (mm): "Black", t_c, 0, 3.0
    Font size: 7
    Text: t_c, "centre", -1.2, "half", "Listener"
    
    # Draw Path
    Colour: "{0.5, 0.5, 0.5}"
    Line width: 2
    Draw line: startTime, 2, endTime, 2
    Line width: 1
    
    # Draw Source moving
    # Start position
    Colour: "{0.3, 0.7, 0.3}"
    Paint circle (mm): "{0.3, 0.7, 0.3}", startTime + 0.05, 2, 2.5
    
    # Closest position
    Colour: "{0.9, 0.3, 0.3}"
    Paint circle (mm): "{0.9, 0.3, 0.3}", t_c, 2, 4.0
    
    # End position
    Colour: "{0.3, 0.7, 0.3}"
    Paint circle (mm): "{0.3, 0.7, 0.3}", endTime - 0.05, 2, 2.5
    
    # Arrow showing direction
    Colour: "{0.4, 0.4, 0.4}"
    Draw arrow: startTime + 0.1, 2.8, endTime - 0.1, 2.8
    
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: startTime + 0.05, "left", 3.2, "half", "Start"
    Text: t_c, "centre", 3.2, "half", "Closest (" + fixed$(d, 1) + "m)"
    Text: endTime - 0.05, "right", 3.2, "half", "End"
    
    # Distance line
    Colour: "{0.6, 0.6, 0.6}"
    Dashed line
    Draw line: t_c, 0, t_c, 2
    Solid line
    
    Colour: "Black"
    Draw inner box
    
    # --- B. Frequency Shift Curve (Middle) ---
    Select outer viewport: 0, 8, 2.5, 4.3
    Select inner viewport: 0.8, 7.6, 2.7, 4.1
    
    # Calculate axis bounds
    margin = (vis_max_factor - vis_min_factor) * 0.1
    if margin = 0
        margin = 0.05
    endif
    
    Axes: startTime, endTime, vis_min_factor - margin, vis_max_factor + margin
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", startTime, endTime, vis_min_factor - margin, vis_max_factor + margin
    
    # Unity line
    Colour: "{0.7, 0.7, 0.7}"
    Dashed line
    Draw line: startTime, 1.0, endTime, 1.0
    Solid line
    
    # Pitch curve
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 2
    
    selectObject: visTableID
    for i from 1 to steps_vis - 1
        t1 = Get value: i, 1
        v1 = Get value: i, 2
        t2 = Get value: i + 1, 1
        v2 = Get value: i + 1, 2
        Draw line: t1, v1, t2, v2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 2.5, 4.3
    Text left: "yes", "Pitch Factor"
    
    # --- C. Amplitude/Gain Curve (Bottom-Middle) ---
    Select outer viewport: 0, 8, 4.4, 6.2
    Select inner viewport: 0.8, 7.6, 4.6, 6.0
    
    # Set max gain axis
    if vis_max_gain < 1.0
        vis_max_gain = 1.0
    endif
    
    Axes: startTime, endTime, 0, vis_max_gain * 1.1
    
    # Background
    Paint rectangle: "{1, 0.97, 0.97}", startTime, endTime, 0, vis_max_gain * 1.1
    
    # Gain curve
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    
    selectObject: visTableID
    for i from 1 to steps_vis - 1
        t1 = Get value: i, 1
        v1 = Get value: i, 3
        t2 = Get value: i + 1, 1
        v2 = Get value: i + 1, 3
        Draw line: t1, v1, t2, v2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 4.4, 6.2
    Text left: "yes", "Gain"
    Text bottom: "yes", "Time (s)"
    
    # --- D. Info Box ---
    Select outer viewport: 0, 8, 6.3, 6.8
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Approaching: +" + fixed$((max_shift_approach - 1) * 100, 1) + "% | Receding: -" + fixed$((1 - max_shift_recede) * 100, 1) + "% | Speed of sound: " + fixed$(c_sound, 0) + " m/s"
    
    Font size: 10
    Colour: "Black"
endif


# ==============================================================================
#  5. CLEANUP & EXIT
# ==============================================================================

# Select final object
selectObject: dopplerSoundID

# Remove visualization data.
removeObject: visTableID

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", originalName$, "_Doppler"
appendInfoLine: "  Output channels: ", nChannels
appendInfoLine: "=============================================="

# Playback
if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: dopplerSoundID