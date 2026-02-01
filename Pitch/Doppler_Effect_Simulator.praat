# ==============================================================================
# Praat AudioTools - Doppler_Effect_Simulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 
# License: MIT License
#
# Description:
#   Simulates a physical Doppler effect (moving source, stationary listener).
#   Includes Presets and Visualization.
#
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

# ==============================================================================
#  2. USER FORM & PRESETS
# ==============================================================================

form Doppler Effect Simulator
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

# Default to form values
v = speed_m_s
d = closest_distance_m
t_c = time_at_closest_s

if preset = 2
    # Fast Car (City Street) ~50 km/h, close lane
    v = 15.0
    d = 4.0
    t_c = totalDuration / 2
    presetName$ = "Fast Car"
elsif preset = 3
    # Jet Flyover (High Altitude) subsonic jet, high altitude
    v = 250.0
    d = 100.0
    t_c = totalDuration / 2
    presetName$ = "Jet Flyover"
elsif preset = 4
    # Ambulance Passing (Close)
    v = 20.0
    d = 2.0
    t_c = totalDuration / 2
    presetName$ = "Ambulance"
elsif preset = 5
    # Slow Bicycle
    v = 5.0
    d = 1.0
    t_c = totalDuration / 2
    presetName$ = "Bicycle"
elsif preset = 6
    # Sci-Fi Warp (Extreme) Mach 1, extremely close
    v = 340.0
    d = 0.5
    t_c = totalDuration / 2
    presetName$ = "Sci-Fi Warp"
else
    presetName$ = "Custom"
endif

# Speed of sound in air (m/s)
c_sound = 343.0

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  DOPPLER EFFECT SIMULATOR v1.2"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", originalName$, " (", fixed$(totalDuration, 2), "s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""
writeInfoLine: "=== Physics Parameters ==="
writeInfoLine: "  Source speed: ", fixed$(v, 1), " m/s (", fixed$(v * 3.6, 1), " km/h)"
writeInfoLine: "  Closest distance: ", fixed$(d, 1), " m"
writeInfoLine: "  Time at closest: ", fixed$(t_c, 2), " s"
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

# --- Step 3a: Pitch Manipulation ---

selectObject: originalSound
To Manipulation: 0.01, min_pitch_Hz, max_pitch_Hz
manipulationID = selected("Manipulation")

selectObject: originalSound
To Pitch: 0.0, min_pitch_Hz, max_pitch_Hz
pitchID = selected("Pitch")

Create PitchTier: "DopplerShift", startTime, endTime
pitchTierID = selected("PitchTier")

# PSOLA Calculation Loop
timeStep = 0.01
numSteps = floor(totalDuration / timeStep)

for i from 0 to numSteps
    t = startTime + (i * timeStep)
    
    # Physics Math
    t_rel = t - t_c
    x_dist = v * t_rel
    hyp_dist = sqrt(d^2 + x_dist^2)
    
    if hyp_dist > 0.0001
        v_radial = v * (x_dist / hyp_dist)
    else
        v_radial = 0
    endif
    
    factor = c_sound / (c_sound + v_radial)
    
    # Apply to PitchTier
    selectObject: pitchID
    val = Get value at time: t, "Hertz", "Linear"
    if val <> undefined
        newVal = val * factor
        selectObject: pitchTierID
        Add point: t, newVal
    endif
endfor

# Apply PitchTier
selectObject: pitchTierID
plusObject: manipulationID
Replace pitch tier

selectObject: manipulationID
Get resynthesis (overlap-add)
dopplerSoundID = selected("Sound")
Rename: originalName$ + "_Doppler"

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
    Scale peak: 0.99
    appendInfoLine: "  Normalized output"
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

# Remove temp objects
removeObject: manipulationID
removeObject: pitchID
removeObject: pitchTierID
removeObject: visTableID

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", originalName$, "_Doppler"
appendInfoLine: "=============================================="

# Playback
if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: dopplerSoundID