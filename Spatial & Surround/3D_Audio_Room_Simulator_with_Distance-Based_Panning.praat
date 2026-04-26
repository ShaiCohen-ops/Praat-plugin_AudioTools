# ============================================================
# Praat AudioTools - 3D Audio Room Simulator with Distance-Based Panning.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   3D Audio Room Simulator with Distance-Based Panning.
#   Moves a source through a 3D room around the listener,
#   convolving with a synthesized room IR per position and
#   panning via DBAP or equal-power stereo.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Changelog v0.3 (2026):
#   - FIX (critical): Two Formula sites used "Object_<id>(t)"
#     with numeric IDs substituted via backtick interpolation.
#     This crashes — Praat resolves Object_<n> by name at parse
#     time, not by numeric ID. The bug affected the per-position
#     mixing into the L/R output buffers, i.e. the entire audio
#     output of the script. Replaced with sample-indexed reads
#     and explicit linear interpolation.
#   - FIX: Converted seven Formula strings from backtick 'var'
#     interpolation to string$() concatenation. The backtick
#     form is fragile across Praat versions and ambiguous when
#     mixed with Formula's intrinsic variables; string$() is
#     the portable idiom used elsewhere in AudioTools.
#   - FIX: Random walk movement now uses a deterministic
#     wandering pattern instead of uncorrelated random teleports
#     per position. v0.2's audio loop teleported to fully random
#     points (no continuity) while the visualization drew a
#     smooth sin/cos path — the two paths didn't match. Both
#     now use the same deterministic pattern, so what you see
#     is what you hear.
#   - FIX: Added input duration validation. v0.2 silently
#     produced corrupted output for inputs shorter than the
#     required segment_duration. Now exits with a clear error.
#   - FORM: Migrated from three sequential beginPause/endPause
#     dialogs to a single form...endform block. Custom-room
#     dimension fields are always present in the form and
#     ignored unless preset=Custom.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Spatial Room Convolution with Movement - STEREO with DBAP
# Creates artificial room reverb and moves sound source around listener
# Listener is at center of room

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Get selected sound
sound = selected("Sound")
sound_name$ = selected$("Sound")
sound_dur = Get total duration
sound_sr = Get sampling frequency

# Convert to mono if needed
numberOfChannels = Get number of channels
if numberOfChannels > 1
    sound_mono = Convert to mono
    sound = sound_mono
    wasStereo = 1
else
    sound_mono = sound
    wasStereo = 0
endif

# === Single form for all parameters ===
form 3D Audio Room Simulator v0.3
    comment === Room Preset ===
    optionmenu Preset 1
        option Custom
        option Small Studio (3x4x2.5m, dry)
        option Living Room (5x6x3m, medium)
        option Concert Hall (20x15x8m, live)
        option Cathedral (40x25x15m, very live)
        option Bathroom (2x2.5x2.5m, very live)
        option Anechoic Chamber (5x5x3m, dead)
        option Club/Bar (15x10x3.5m, medium)
    comment === Custom dimensions (used only if preset=Custom) ===
    positive Custom_length 8.0
    positive Custom_width 6.0
    positive Custom_height 3.0
    real Custom_absorption 0.3
    comment === Movement ===
    optionmenu Movement 1
        option Circular (horizontal)
        option Front to Back
        option Left to Right
        option Spiral (horizontal)
        option Up and Down
        option Random walk (deterministic wander)
        option Figure-8 (horizontal)
        option Diagonal sweep
    positive Movement_radius 2.5
    natural Num_positions 16
    positive Reverb_tail 1.5
    positive Crossfade_time 0.1
    boolean Use_dbap 1
endform

# Apply preset values
if preset = 1
    # Custom — use form fields
    room_length = custom_length
    room_width = custom_width
    room_height = custom_height
    absorption = custom_absorption
elsif preset = 2
    # Small Studio
    room_length = 4.0
    room_width = 3.0
    room_height = 2.5
    absorption = 0.6
elsif preset = 3
    # Living Room
    room_length = 6.0
    room_width = 5.0
    room_height = 3.0
    absorption = 0.4
elsif preset = 4
    # Concert Hall
    room_length = 20.0
    room_width = 15.0
    room_height = 8.0
    absorption = 0.15
elsif preset = 5
    # Cathedral
    room_length = 40.0
    room_width = 25.0
    room_height = 15.0
    absorption = 0.08
elsif preset = 6
    # Bathroom
    room_length = 2.5
    room_width = 2.0
    room_height = 2.5
    absorption = 0.05
elsif preset = 7
    # Anechoic Chamber
    room_length = 5.0
    room_width = 5.0
    room_height = 3.0
    absorption = 0.99
else
    # Club/Bar
    room_length = 15.0
    room_width = 10.0
    room_height = 3.5
    absorption = 0.25
endif

if room_length <= 0 or room_width <= 0 or room_height <= 0
    exitScript: "Invalid room dimensions!"
endif

if num_positions < 2
    num_positions = 2
endif

# Build movement$ string for display (was set by old endPause dialog)
if movement = 1
    movement$ = "Circular"
elsif movement = 2
    movement$ = "Front to Back"
elsif movement = 3
    movement$ = "Left to Right"
elsif movement = 4
    movement$ = "Spiral"
elsif movement = 5
    movement$ = "Up and Down"
elsif movement = 6
    movement$ = "Random walk"
elsif movement = 7
    movement$ = "Figure-8"
else
    movement$ = "Diagonal"
endif

# Speed of sound
c = 343

# Calculate room volume and RT60 (simplified Sabine equation)
volume = room_length * room_width * room_height
area_xy = room_length * room_width
area_xz = room_length * room_height
area_yz = room_width * room_height
surface_area = 2 * (area_xy + area_xz + area_yz)
rt60 = 0.161 * volume / (absorption * surface_area + 0.001)

# Limit RT60 to reasonable values
if rt60 > 5.0
    rt60 = 5.0
endif
if rt60 < 0.05
    rt60 = 0.05
endif

writeInfoLine: "Spatial Room Convolution - STEREO"
if preset = 2
    appendInfoLine: "Preset: Small Studio"
elsif preset = 3
    appendInfoLine: "Preset: Living Room"
elsif preset = 4
    appendInfoLine: "Preset: Concert Hall"
elsif preset = 5
    appendInfoLine: "Preset: Cathedral"
elsif preset = 6
    appendInfoLine: "Preset: Bathroom"
elsif preset = 7
    appendInfoLine: "Preset: Anechoic Chamber"
elsif preset = 8
    appendInfoLine: "Preset: Club/Bar"
else
    appendInfoLine: "Preset: Custom"
endif
appendInfoLine: "Room: ", fixed$(room_length, 1), " x ", fixed$(room_width, 1), " x ", fixed$(room_height, 1), " m"
appendInfoLine: "RT60: ", fixed$(rt60, 2), " seconds"
appendInfoLine: "Movement: ", movement$
if use_dbap
    appendInfoLine: "Panning: DBAP (Distance-Based Amplitude Panning)"
else
    appendInfoLine: "Panning: Equal-power stereo"
endif
appendInfoLine: "Processing ", num_positions, " positions..."

# Create impulse response for the room
ir_duration = rt60 + reverb_tail

# Generate room impulse response (simplified model)
Create Sound from formula: "room_ir", 1, 0, ir_duration, sound_sr, "0"

# Add direct sound impulse at start
Formula (part): 0, 0.0001, 1, 1, "1"

# Add early reflections (simplified - 6 walls)
wall_distance_x = room_length / 2
wall_distance_y = room_width / 2
wall_distance_z = room_height / 2

# Calculate reflection times and amplitudes
rt60_str$ = fixed$(rt60, 8)
for reflection from 1 to 6
    if reflection = 1 or reflection = 2
        dist = wall_distance_x
    elsif reflection = 3 or reflection = 4
        dist = wall_distance_y
    else
        dist = wall_distance_z
    endif
    
    delay = dist / c
    amp = (1 - absorption) * 0.7
    amp_str$ = fixed$(amp, 8)
    
    if delay < ir_duration
        # v0.3: backtick 'amp' / 'rt60' replaced with string$()
        Formula (part): delay, delay + 0.0001, 1, 1,
            ... "self + " + amp_str$ + " * exp(-3 * x / " + rt60_str$ + ")"
    endif
    
    # Second order reflections
    delay2 = 2 * delay
    amp2 = amp * (1 - absorption) * 0.5
    amp2_str$ = fixed$(amp2, 8)
    if delay2 < ir_duration
        Formula (part): delay2, delay2 + 0.0001, 1, 1,
            ... "self + " + amp2_str$ + " * exp(-3 * x / " + rt60_str$ + ")"
    endif
endfor

# Add diffuse reverb tail
# v0.3: backtick 'rt60' replaced with string$()
Formula: "self + 0.1 * randomGauss(0, 1) * exp(-6.9 * x / " + rt60_str$ + ")"

# Normalize IR
Scale peak: 0.99
room_ir = selected("Sound")

# Calculate segment duration with overlap
segment_duration = sound_dur / num_positions + crossfade_time

# v0.3: Input duration validation. Below this length the segment
# extraction would silently truncate and produce corrupted output.
min_required_dur = segment_duration * 1.2
if sound_dur < min_required_dur
    removeObject: room_ir
    if wasStereo = 1
        selectObject: sound_mono
        Remove
    endif
    exitScript: "Input too short. Need at least ",
        ... fixed$(min_required_dur, 2),
        ... " s for ", num_positions, " positions with ",
        ... fixed$(crossfade_time, 2), " s crossfade. Input is ",
        ... fixed$(sound_dur, 2), " s. Reduce num_positions or crossfade_time, or use a longer source."
endif

# Calculate output duration
output_duration = sound_dur + ir_duration + 1.0

# Create empty stereo output
Create Sound from formula: "output_L", 1, 0, output_duration, sound_sr, "0"
output_L = selected("Sound")
Create Sound from formula: "output_R", 1, 0, output_duration, sound_sr, "0"
output_R = selected("Sound")

# Define speaker positions for DBAP (stereo setup)
# Left speaker at (-1, 0, 0) and Right speaker at (+1, 0, 0)
speaker_L_x = -1.0
speaker_L_y = 0.0
speaker_L_z = 0.0
speaker_R_x = 1.0
speaker_R_y = 0.0
speaker_R_z = 0.0

# DBAP rolloff exponent (typically 6 for 3D, but we can use 2-4 for 2D)
dbap_exponent = 2.0

# Process each position
for pos from 1 to num_positions
    # Calculate position based on movement preset
    angle = (pos - 1) / num_positions * 2 * pi
    progress = (pos - 1) / (num_positions - 1)
    
    if movement = 1
        # Circular (horizontal)
        x_pos = movement_radius * cos(angle)
        y_pos = movement_radius * sin(angle)
        z_pos = 0
    elsif movement = 2
        # Front to Back
        x_pos = movement_radius * (2 * progress - 1)
        y_pos = 0
        z_pos = 0
    elsif movement = 3
        # Left to Right
        x_pos = 0
        y_pos = movement_radius * (2 * progress - 1)
        z_pos = 0
    elsif movement = 4
        # Spiral (horizontal)
        radius_spiral = movement_radius * progress
        x_pos = radius_spiral * cos(angle * 3)
        y_pos = radius_spiral * sin(angle * 3)
        z_pos = 0
    elsif movement = 5
        # Up and Down
        x_pos = 0
        y_pos = 0
        z_pos = movement_radius * sin(angle) * 0.5
    elsif movement = 6
        # v0.3: Deterministic wandering pattern (was uncorrelated
        # randomUniform teleports per position, which didn't match
        # the visualization's smooth path). Now uses the same
        # sin*cos formula as the viz so what you see is what you hear.
        x_pos = movement_radius * sin(pos * 0.7) * cos(pos * 0.3)
        y_pos = movement_radius * cos(pos * 0.5) * sin(pos * 0.4)
        z_pos = 0
    elsif movement = 7
        # Figure-8 (horizontal)
        x_pos = movement_radius * sin(angle * 2) * cos(angle)
        y_pos = movement_radius * sin(angle * 2) * sin(angle)
        z_pos = 0
    else
        # Diagonal sweep
        x_pos = movement_radius * (2 * progress - 1)
        y_pos = movement_radius * (2 * progress - 1)
        z_pos = 0
    endif
    
    # Calculate distance from listener (at origin)
    distance = sqrt(x_pos^2 + y_pos^2 + z_pos^2)
    if distance < 0.1
        distance = 0.1
    endif
    
    # Distance attenuation (inverse square law, but limited)
    atten = 1 / (1 + distance)
    
    # Calculate panning gains
    if use_dbap
        # DBAP: Distance-Based Amplitude Panning
        # Calculate distance from source to each speaker
        dist_L = sqrt((x_pos - speaker_L_x)^2 + (y_pos - speaker_L_y)^2 + (z_pos - speaker_L_z)^2)
        dist_R = sqrt((x_pos - speaker_R_x)^2 + (y_pos - speaker_R_y)^2 + (z_pos - speaker_R_z)^2)
        
        # Prevent division by zero
        if dist_L < 0.01
            dist_L = 0.01
        endif
        if dist_R < 0.01
            dist_R = 0.01
        endif
        
        # Calculate weights (inverse distance with exponent)
        weight_L = 1 / (dist_L ^ dbap_exponent)
        weight_R = 1 / (dist_R ^ dbap_exponent)
        
        # Normalize weights
        total_weight = weight_L + weight_R
        gain_L = sqrt(weight_L / total_weight)
        gain_R = sqrt(weight_R / total_weight)
        
        pan = (gain_R - gain_L)
    else
        # Standard equal-power panning based on y_pos (left-right)
        max_y = room_width / 2
        if max_y > 0
            pan = y_pos / max_y
            if pan < -1
                pan = -1
            endif
            if pan > 1
                pan = 1
            endif
        else
            pan = 0
        endif
        
        # Convert pan to left/right gains (equal power panning)
        pan_angle = (pan + 1) * pi / 4
        gain_L = cos(pan_angle)
        gain_R = sin(pan_angle)
    endif
    
    # Calculate time position in output
    time_offset = (pos - 1) * (sound_dur / num_positions)
    
    # Extract segment from source with overlap
    selectObject: sound
    start_time = time_offset
    end_time = time_offset + segment_duration
    if start_time < 0
        start_time = 0
    endif
    if end_time > sound_dur
        end_time = sound_dur
    endif
    
    segment = Extract part: start_time, end_time, "rectangular", 1, "no"
    seg_dur = Get total duration

    # v0.3: backtick interpolation replaced with string$() for
    # portability. The fade arithmetic is unchanged.
    cf_str$ = fixed$(crossfade_time, 8)
    seg_str$ = fixed$(seg_dur, 8)

    # Apply crossfade envelope to segment
    if pos > 1 and pos < num_positions
        # Fade in and out
        Formula: "self * (if x < " + cf_str$
            ... + " then x / " + cf_str$
            ... + " else (if x > " + seg_str$ + " - " + cf_str$
            ... + " then (" + seg_str$ + " - x) / " + cf_str$
            ... + " else 1 fi) fi)"
    elsif pos = 1
        # Only fade out at end
        Formula: "self * (if x > " + seg_str$ + " - " + cf_str$
            ... + " then (" + seg_str$ + " - x) / " + cf_str$
            ... + " else 1 fi)"
    else
        # Only fade in at start
        Formula: "self * (if x < " + cf_str$
            ... + " then x / " + cf_str$
            ... + " else 1 fi)"
    endif

    # Apply distance attenuation
    atten_str$ = fixed$(atten, 8)
    Formula: "self * " + atten_str$
    
    # Convolve with room IR
    plusObject: room_ir
    conv = Convolve: "sum", "zero"
    Rename: "conv_" + string$(pos)
    conv_dur = Get total duration

    # v0.3 FIX (critical): previous version used
    #   "self + Object_'conv'(x - 'time_offset') * 'gain_L'"
    # which is name-resolved at parse time and crashes with
    # numeric IDs. Replaced with sample-indexed reads + manual
    # linear interpolation. The conv has xmin=0 (Convolve output),
    # sample rate = sound_sr, so column index for read time
    # tRead = (x - time_offset) is colF = tRead * sr + 1.
    convStr$ = string$(conv)
    srStr$ = fixed$(sound_sr, 6)
    toStr$ = fixed$(time_offset, 8)
    gLStr$ = fixed$(gain_L, 8)
    gRStr$ = fixed$(gain_R, 8)

    # colF expression — repeated four times in the formula
    # (Praat Formula has no let-bindings).
    colF$ = "((x - " + toStr$ + ") * " + srStr$ + " + 1)"

    selectObject: output_L
    Formula (part): time_offset, time_offset + conv_dur, 1, 1,
        ... "self + ((1 - (" + colF$ + " - floor(" + colF$ + "))) * "
        ... + "object[" + convStr$ + ", 1, floor(" + colF$ + ")] + "
        ... + "(" + colF$ + " - floor(" + colF$ + ")) * "
        ... + "object[" + convStr$ + ", 1, floor(" + colF$ + ") + 1]"
        ... + ") * " + gLStr$

    selectObject: output_R
    Formula (part): time_offset, time_offset + conv_dur, 1, 1,
        ... "self + ((1 - (" + colF$ + " - floor(" + colF$ + "))) * "
        ... + "object[" + convStr$ + ", 1, floor(" + colF$ + ")] + "
        ... + "(" + colF$ + " - floor(" + colF$ + ")) * "
        ... + "object[" + convStr$ + ", 1, floor(" + colF$ + ") + 1]"
        ... + ") * " + gRStr$

    # Clean up
    removeObject: segment, conv
    
    appendInfoLine: "Position ", pos, "/", num_positions, " - Distance: ", fixed$(distance, 2), "m, Pan: ", fixed$(pan, 2), " (L:", fixed$(gain_L, 2), " R:", fixed$(gain_R, 2), ")"
endfor

# Combine to stereo
selectObject: output_L
plusObject: output_R
output_stereo = Combine to stereo
Rename: sound_name$ + "_spatial_stereo"

# Normalize
Scale peak: 0.99

# Clean up
removeObject: room_ir, output_L, output_R
if wasStereo = 1
    selectObject: sound_mono
    Remove
endif

# ============================================================
# VISUALIZATION
# ============================================================

# Build preset name string for display
if preset = 2
    presetDisp$ = "Small Studio"
elsif preset = 3
    presetDisp$ = "Living Room"
elsif preset = 4
    presetDisp$ = "Concert Hall"
elsif preset = 5
    presetDisp$ = "Cathedral"
elsif preset = 6
    presetDisp$ = "Bathroom"
elsif preset = 7
    presetDisp$ = "Anechoic"
elsif preset = 8
    presetDisp$ = "Club/Bar"
else
    presetDisp$ = "Custom"
endif

dbapStr$ = "EP stereo"
if use_dbap
    dbapStr$ = "DBAP"
endif

Erase all
Select outer viewport: 0, 8, 0, 8

# ----------------------------------------------------------
# Title
# ----------------------------------------------------------
Select outer viewport: 0, 8, 0, 0.65
Axes: 0, 1, 0, 1
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.65, "half", "##3D Audio Room Simulator v0.3##"
Font size: 7
Colour: "{0.35, 0.35, 0.52}"
Text: 0.5, "centre", -0.25, "half",
    ... sound_name$ + "  |  " + presetDisp$
    ... + "  |  " + fixed$(room_length, 1) + "×" + fixed$(room_width, 1)
    ... + "×" + fixed$(room_height, 1) + "m"
    ... + "  |  RT60=" + fixed$(rt60, 2) + "s"
    ... + "  |  " + movement$

# ----------------------------------------------------------
# Room top-view with movement path
# ----------------------------------------------------------
Select outer viewport: 0, 8, 0.55, 4.55
Select inner viewport: 0.55, 7.65, 0.75, 4.45

margin = max(room_length, room_width) * 0.18
Axes: -room_length/2 - margin, room_length/2 + margin,
    ... -room_width/2 - margin, room_width/2 + margin

# Room floor
Paint rectangle: "{0.94, 0.94, 0.90}", -room_length/2, room_length/2,
    ... -room_width/2, room_width/2

# Room walls
Colour: "{0.30, 0.30, 0.30}"
Line width: 3
Draw rectangle: -room_length/2, room_length/2,
    ... -room_width/2, room_width/2
Line width: 1

# Grid lines (1m spacing)
Colour: "{0.85, 0.85, 0.82}"
for gridX from -floor(room_length/2) to floor(room_length/2)
    Draw line: gridX, -room_width/2, gridX, room_width/2
endfor
for gridY from -floor(room_width/2) to floor(room_width/2)
    Draw line: -room_length/2, gridY, room_length/2, gridY
endfor

# Movement path (blue→red gradient)
Line width: 2.5
prev_x = 0
prev_y = 0
numDrawPoints = 100

for drawPos from 1 to numDrawPoints
    angle = (drawPos - 1) / numDrawPoints * 2 * pi
    progress = (drawPos - 1) / (numDrawPoints - 1)

    if movement = 1
        x_pos = movement_radius * cos(angle)
        y_pos = movement_radius * sin(angle)
    elsif movement = 2
        x_pos = movement_radius * (2 * progress - 1)
        y_pos = 0
    elsif movement = 3
        x_pos = 0
        y_pos = movement_radius * (2 * progress - 1)
    elsif movement = 4
        radius_spiral = movement_radius * progress
        x_pos = radius_spiral * cos(angle * 3)
        y_pos = radius_spiral * sin(angle * 3)
    elsif movement = 5
        x_pos = movement_radius * 0.3 * sin(angle)
        y_pos = 0
    elsif movement = 6
        x_pos = movement_radius * sin(drawPos * 0.7) * cos(drawPos * 0.3)
        y_pos = movement_radius * cos(drawPos * 0.5) * sin(drawPos * 0.4)
    elsif movement = 7
        x_pos = movement_radius * sin(angle * 2) * cos(angle)
        y_pos = movement_radius * sin(angle * 2) * sin(angle)
    else
        x_pos = movement_radius * (2 * progress - 1)
        y_pos = movement_radius * (2 * progress - 1)
    endif

    cR = progress
    cG = 0.20
    cB = 1 - progress

    if drawPos > 1
        Colour: "{" + fixed$(cR, 2) + ", " + fixed$(cG, 2) + ", " + fixed$(cB, 2) + "}"
        Draw line: prev_x, prev_y, x_pos, y_pos
    endif
    prev_x = x_pos
    prev_y = y_pos
endfor

# Position markers
for pos from 1 to num_positions
    angle = (pos - 1) / num_positions * 2 * pi
    progress = (pos - 1) / (num_positions - 1)

    if movement = 1
        x_pos = movement_radius * cos(angle)
        y_pos = movement_radius * sin(angle)
    elsif movement = 2
        x_pos = movement_radius * (2 * progress - 1)
        y_pos = 0
    elsif movement = 3
        x_pos = 0
        y_pos = movement_radius * (2 * progress - 1)
    elsif movement = 4
        radius_spiral = movement_radius * progress
        x_pos = radius_spiral * cos(angle * 3)
        y_pos = radius_spiral * sin(angle * 3)
    elsif movement = 5
        x_pos = movement_radius * 0.3 * sin(angle)
        y_pos = 0
    elsif movement = 6
        x_pos = movement_radius * sin(pos * 0.7) * cos(pos * 0.3)
        y_pos = movement_radius * cos(pos * 0.5) * sin(pos * 0.4)
    elsif movement = 7
        x_pos = movement_radius * sin(angle * 2) * cos(angle)
        y_pos = movement_radius * sin(angle * 2) * sin(angle)
    else
        x_pos = movement_radius * (2 * progress - 1)
        y_pos = movement_radius * (2 * progress - 1)
    endif

    cR = progress
    cB = 1 - progress
    Paint circle (mm): "{" + fixed$(cR, 2) + ", 0.30, " + fixed$(cB, 2) + "}",
        ... x_pos, y_pos, 2.2
endfor

# Listener at centre
Paint circle (mm): "White", 0, 0, 4.5
Paint circle (mm): "{0.20, 0.68, 0.22}", 0, 0, 3.8

# Speaker positions
Paint circle (mm): "{0.58, 0.38, 0.18}", speaker_L_x, speaker_L_y, 3
Paint circle (mm): "{0.58, 0.38, 0.18}", speaker_R_x, speaker_R_y, 3

# Adaptive label offset (proportional to room size)
lblOff = max(room_width, room_length) * 0.06
Font size: 6
Colour: "{0.12, 0.40, 0.12}"
Text: 0, "centre", -lblOff, "half", "Listener"
Colour: "{0.40, 0.25, 0.10}"
Text: speaker_L_x, "centre", speaker_L_y - lblOff, "half", "L"
Text: speaker_R_x, "centre", speaker_R_y - lblOff, "half", "R"

# Direction labels
Font size: 7
Colour: "{0.45, 0.45, 0.45}"
Text: 0, "centre", room_width/2 + margin * 0.55, "half", "Front"
Text: 0, "centre", -room_width/2 - margin * 0.55, "half", "Back"
Text: -room_length/2 - margin * 0.50, "centre", 0, "half", "Left"
Text: room_length/2 + margin * 0.50, "centre", 0, "half", "Right"

# Legend: start/end colours
Font size: 5
Colour: "{0.00, 0.20, 1.00}"
Text: room_length/2 + margin * 0.45, "centre", -room_width/2 - margin * 0.30, "half", "Start"
Colour: "{1.00, 0.20, 0.00}"
Text: room_length/2 + margin * 0.45, "centre", -room_width/2 - margin * 0.55, "half", "End"

Line width: 1
Colour: "Black"
Draw inner box
Font size: 7
Text top: "no", "Room top view  —  " + movement$ + "  (r=" + fixed$(movement_radius, 1) + "m)"

# ----------------------------------------------------------
# Output waveform (L blue, R orange)
# ----------------------------------------------------------
Select outer viewport: 0, 8, 4.65, 5.75
Select inner viewport: 0.55, 7.65, 4.72, 5.68

selectObject: output_stereo
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak < 0.001
    outPeak = 0.001
endif
ampMax = outPeak * 1.15

selectObject: output_stereo
outDur = Get total duration
Axes: 0, outDur, -ampMax, ampMax
Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, -ampMax, ampMax
Colour: "{0.80, 0.80, 0.80}"
Draw line: 0, 0, outDur, 0

selectObject: output_stereo
Extract one channel: 1
vizL = selected("Sound")
Colour: "{0.25, 0.50, 0.82}"
Draw: 0, 0, -ampMax, ampMax, "no", "Curve"

selectObject: output_stereo
Extract one channel: 2
vizR = selected("Sound")
Colour: "{0.82, 0.45, 0.25}"
Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
removeObject: vizL, vizR

Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Output"
Text top: "no", "Stereo output  (blue=L  orange=R)"
Text bottom: "yes", "Time (s)"

# ----------------------------------------------------------
# Summary panel
# ----------------------------------------------------------
Select outer viewport: 0, 8, 5.85, 6.65
Select inner viewport: 0.55, 7.65, 5.90, 6.58
Axes: 0, 1, 0, 1
Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
Font size: 7
Colour: "Black"
Text: 0.02, "left", 0.82, "half", "##Summary##"
Font size: 6
Colour: "{0.30, 0.30, 0.30}"
Text: 0.02, "left", 0.52, "half",
    ... "Room: " + fixed$(room_length, 1) + "×" + fixed$(room_width, 1)
    ... + "×" + fixed$(room_height, 1) + "m"
    ... + "  |  Vol: " + fixed$(volume, 0) + " m³"
    ... + "  |  Absorb: " + fixed$(absorption, 2)
    ... + "  |  RT60: " + fixed$(rt60, 2) + "s"
    ... + "  |  Panning: " + dbapStr$
Text: 0.02, "left", 0.18, "half",
    ... "Movement: " + movement$
    ... + "  |  Radius: " + fixed$(movement_radius, 1) + "m"
    ... + "  |  Positions: " + string$(num_positions)
    ... + "  |  Crossfade: " + fixed$(crossfade_time, 2) + "s"
    ... + "  |  Tail: " + fixed$(reverb_tail, 1) + "s"
Colour: "Black"
Draw rectangle: 0, 1, 0, 1

Font size: 10
Colour: "Black"
Line width: 1

# Select output for user
selectObject: output_stereo
Play

appendInfoLine: ""
appendInfoLine: "Done! Spatial convolution complete."
appendInfoLine: "Output: STEREO - ", selected$("Sound")