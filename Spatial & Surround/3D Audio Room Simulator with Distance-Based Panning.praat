# ============================================================
# Praat AudioTools - 3D Audio Room Simulator with Distance-Based Panning.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   3D Audio Room Simulator with Distance-Based Panning
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
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

# Room preset selection
beginPause: "Room Preset"
    comment: "Select a room preset or customize"
    optionMenu: "Preset", 1
        option: "Custom"
        option: "Small Studio (3x4x2.5m, dry)"
        option: "Living Room (5x6x3m, medium)"
        option: "Concert Hall (20x15x8m, live)"
        option: "Cathedral (40x25x15m, very live)"
        option: "Bathroom (2x2.5x2.5m, very live)"
        option: "Anechoic Chamber (5x5x3m, dead)"
        option: "Club/Bar (15x10x3.5m, medium)"
endPause: "Cancel", "OK", 2

# Apply preset values
if preset = 1
    # Custom - get from user
    room_length = 8.0
    room_width = 6.0
    room_height = 3.0
    absorption = 0.3
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

# Get room dimensions from user (allow override if Custom)
if preset = 1
    beginPause: "Custom Room Dimensions"
        comment: "Define the room (listener at center)"
        positive: "room_length", room_length
        comment: "Length (meters, front-back)"
        positive: "room_width", room_width
        comment: "Width (meters, left-right)"
        positive: "room_height", room_height
        comment: "Height (meters)"
        positive: "absorption", absorption
        comment: "Wall absorption (0-1, higher = more damping)"
    endPause: "Cancel", "OK", 2
endif

if room_length <= 0 or room_width <= 0 or room_height <= 0
    exitScript: "Invalid room dimensions!"
endif

# Movement preset selection
beginPause: "Movement Preset"
    comment: "Select how the sound moves around the listener"
    optionMenu: "Movement", 1
        option: "Circular (horizontal)"
        option: "Front to Back"
        option: "Left to Right"
        option: "Spiral (horizontal)"
        option: "Up and Down"
        option: "Random walk"
        option: "Figure-8 (horizontal)"
        option: "Diagonal sweep"
    positive: "movement_radius", 2.5
    comment: "Movement radius/distance (meters)"
    positive: "num_positions", 16
    comment: "Number of position samples (more = smoother)"
    positive: "reverb_tail", 1.5
    comment: "Reverb tail duration (seconds)"
    positive: "crossfade_time", 0.1
    comment: "Crossfade between positions (seconds)"
    boolean: "use_dbap", 1
    comment: "Use DBAP (Distance-Based Amplitude Panning)"
endPause: "Cancel", "OK", 2

if num_positions < 2
    num_positions = 2
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
    
    if delay < ir_duration
        Formula (part): delay, delay + 0.0001, 1, 1, "self + 'amp' * exp(-3 * x / 'rt60')"
    endif
    
    # Second order reflections
    delay2 = 2 * delay
    amp2 = amp * (1 - absorption) * 0.5
    if delay2 < ir_duration
        Formula (part): delay2, delay2 + 0.0001, 1, 1, "self + 'amp2' * exp(-3 * x / 'rt60')"
    endif
endfor

# Add diffuse reverb tail
Formula: "self + 0.1 * randomGauss(0, 1) * exp(-6.9 * x / 'rt60')"

# Normalize IR
Scale peak: 0.99
room_ir = selected("Sound")

# Calculate segment duration with overlap
segment_duration = sound_dur / num_positions + crossfade_time

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
        # Random walk
        x_pos = movement_radius * (randomUniform(0, 1) - 0.5) * 2
        y_pos = movement_radius * (randomUniform(0, 1) - 0.5) * 2
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
    
    # Apply crossfade envelope to segment
    if pos > 1 and pos < num_positions
        # Fade in and out
        Formula: "self * (if x < 'crossfade_time' then x / 'crossfade_time' else (if x > 'seg_dur' - 'crossfade_time' then ('seg_dur' - x) / 'crossfade_time' else 1 fi) fi)"
    elsif pos = 1
        # Only fade out at end
        Formula: "self * (if x > 'seg_dur' - 'crossfade_time' then ('seg_dur' - x) / 'crossfade_time' else 1 fi)"
    else
        # Only fade in at start
        Formula: "self * (if x < 'crossfade_time' then x / 'crossfade_time' else 1 fi)"
    endif
    
    # Apply distance attenuation
    Formula: "self * 'atten'"
    
    # Convolve with room IR
    plusObject: room_ir
    conv = Convolve: "sum", "zero"
    Rename: "conv_'pos'"
    conv_dur = Get total duration
    
    # Mix into output buffers with spatial positioning
    selectObject: output_L
    Formula (part): time_offset, time_offset + conv_dur, 1, 1, 
        ... "self + Object_'conv' (x - 'time_offset') * 'gain_L'"
    
    selectObject: output_R
    Formula (part): time_offset, time_offset + conv_dur, 1, 1, 
        ... "self + Object_'conv' (x - 'time_offset') * 'gain_R'"
    
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
# VISUALIZATION - Movement Path in Room
# ============================================================

Erase all

# === Title ===
Select outer viewport: 0, 10, 0, 0.8
Font size: 16
Colour: "Black"
Text: 0.5, "centre", 0.5, "half", "3D Room Simulator: " + movement$ + " | " + fixed$(room_length, 1) + "×" + fixed$(room_width, 1) + "×" + fixed$(room_height, 1) + "m | RT60: " + fixed$(rt60, 2) + "s"

# === Room Top View with Movement Path (LARGE) ===
Select outer viewport: 0.5, 9.5, 1.0, 7.5
Select inner viewport: 1.0, 9.0, 1.5, 7.0

# Set axes to show room with margin
margin = max(room_length, room_width) * 0.15
Axes: -room_length/2 - margin, room_length/2 + margin, -room_width/2 - margin, room_width/2 + margin

# Room floor
Paint rectangle: "{0.92, 0.92, 0.88}", -room_length/2, room_length/2, -room_width/2, room_width/2

# Room walls (thicker border)
Colour: "{0.3, 0.3, 0.3}"
Line width: 4
Draw rectangle: -room_length/2, room_length/2, -room_width/2, room_width/2
Line width: 1

# Grid lines
Colour: "{0.82, 0.82, 0.78}"
Line width: 1
for gridX from -floor(room_length/2) to floor(room_length/2)
    Draw line: gridX, -room_width/2, gridX, room_width/2
endfor
for gridY from -floor(room_width/2) to floor(room_width/2)
    Draw line: -room_length/2, gridY, room_length/2, gridY
endfor

# Draw movement path with color gradient (blue to red = start to end)
Line width: 3
prev_x = 0
prev_y = 0
numDrawPoints = 100

for drawPos from 1 to numDrawPoints
    angle = (drawPos - 1) / numDrawPoints * 2 * pi
    progress = (drawPos - 1) / (numDrawPoints - 1)
    
    if movement = 1
        # Circular
        x_pos = movement_radius * cos(angle)
        y_pos = movement_radius * sin(angle)
    elsif movement = 2
        # Front to Back
        x_pos = movement_radius * (2 * progress - 1)
        y_pos = 0
    elsif movement = 3
        # Left to Right
        x_pos = 0
        y_pos = movement_radius * (2 * progress - 1)
    elsif movement = 4
        # Spiral
        radius_spiral = movement_radius * progress
        x_pos = radius_spiral * cos(angle * 3)
        y_pos = radius_spiral * sin(angle * 3)
    elsif movement = 5
        # Up and Down (show as front-back for top view)
        x_pos = movement_radius * 0.3 * sin(angle)
        y_pos = 0
    elsif movement = 6
        # Random walk - use deterministic pattern for visualization
        x_pos = movement_radius * sin(drawPos * 0.7) * cos(drawPos * 0.3)
        y_pos = movement_radius * cos(drawPos * 0.5) * sin(drawPos * 0.4)
    elsif movement = 7
        # Figure-8
        x_pos = movement_radius * sin(angle * 2) * cos(angle)
        y_pos = movement_radius * sin(angle * 2) * sin(angle)
    else
        # Diagonal sweep
        x_pos = movement_radius * (2 * progress - 1)
        y_pos = movement_radius * (2 * progress - 1)
    endif
    
    # Color gradient: blue (start) to red (end)
    r = progress
    g = 0.2
    b = 1 - progress
    
    if drawPos > 1
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        Draw line: prev_x, prev_y, x_pos, y_pos
    endif
    
    prev_x = x_pos
    prev_y = y_pos
endfor

# Draw position markers
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
    
    # Color gradient for markers
    r = progress
    b = 1 - progress
    Paint circle (mm): "{" + fixed$(r, 2) + ", 0.3, " + fixed$(b, 2) + "}", x_pos, y_pos, 3
endfor

# Listener at center (large)
Paint circle (mm): "White", 0, 0, 6
Paint circle (mm): "{0.2, 0.7, 0.2}", 0, 0, 5
Font size: 10
Colour: "{0.1, 0.4, 0.1}"
Text: 0, "centre", -room_width * 0.12, "half", "LISTENER"

# Speaker positions
Paint circle (mm): "{0.6, 0.4, 0.2}", speaker_L_x, speaker_L_y, 4
Paint circle (mm): "{0.6, 0.4, 0.2}", speaker_R_x, speaker_R_y, 4
Font size: 9
Colour: "{0.4, 0.25, 0.1}"
Text: speaker_L_x, "centre", speaker_L_y - 0.5, "half", "L"
Text: speaker_R_x, "centre", speaker_R_y - 0.5, "half", "R"

# Axes labels
Colour: "{0.3, 0.3, 0.3}"
Font size: 10
Text: 0, "centre", room_width/2 + margin * 0.5, "half", "Front"
Text: 0, "centre", -room_width/2 - margin * 0.5, "half", "Back"
Text: -room_length/2 - margin * 0.4, "centre", 0, "half", "Left"
Text: room_length/2 + margin * 0.4, "centre", 0, "half", "Right"

Line width: 1
Colour: "Black"
Draw inner box

# Reset
Font size: 10
Colour: "Black"
Line width: 1

# Select output for user
selectObject: output_stereo
Play

appendInfoLine: ""
appendInfoLine: "Done! Spatial convolution complete."
appendInfoLine: "Output: STEREO - ", selected$("Sound")