# ============================================================
# Praat AudioTools - Ray_Tracing_Room_Acoustics.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ray Tracing Room Acoustics - physically accurate 3D room
#   simulation using ray tracing. Implements inverse square
#   law, air absorption, wall absorption, and Sabine RT60.
#   Uses Fibonacci sphere for even ray distribution. Creates
#   impulse response and convolves with input.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection syntax
#   - Fixed undefined preset$ variable
#   - Added wet/dry mix control
#   - Removed goto (replaced with flag)
#   - Professional multi-panel visualization
# ============================================================

form Ray Tracing Room Acoustics
    comment Select a Sound object first
    
    comment === PRESETS ===
    optionmenu Preset: 4
        option Custom (use parameters below)
        option Small Living Room
        option Large Concert Hall
        option Bathroom (Bright)
        option Recording Studio (Dead)
        option Cathedral (Very Long)
        option Small Club
        option Outdoor (Minimal)
        option Bright Chamber
    
    comment === Room dimensions (meters) ===
    positive Room_width_m 8
    positive Room_height_m 6
    positive Room_depth_m 5
    
    comment === Ray Tracing Parameters ===
    positive Number_of_rays 200
    positive Max_reflections 15
    positive Listener_radius_m 0.5
    
    comment === Acoustic parameters ===
    positive Wall_absorption 0.15
    positive Air_absorption 0.001
    positive Speed_of_sound 343
    
    comment === Reverb parameters ===
    positive Reverb_tail_s 1.5
    positive Diffuse_level 0.15
    
    comment === Positions (meters) ===
    positive Source_x 2
    positive Source_y 3
    positive Source_z 1.5
    positive Listener_x 6
    positive Listener_y 3
    positive Listener_z 1.5
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Small Living Room
    room_width_m = 5
    room_height_m = 3
    room_depth_m = 4
    number_of_rays = 150
    max_reflections = 10
    wall_absorption = 0.4
    air_absorption = 0.001
    reverb_tail_s = 0.6
    diffuse_level = 0.10
    listener_radius_m = 0.4
    source_x = 1.5
    source_y = 1.5
    source_z = 1.2
    listener_x = 3.5
    listener_y = 1.5
    listener_z = 1.2
    presetName$ = "Living Room"
elsif preset = 3
    # Large Concert Hall
    room_width_m = 40
    room_height_m = 15
    room_depth_m = 20
    number_of_rays = 300
    max_reflections = 25
    wall_absorption = 0.15
    air_absorption = 0.002
    reverb_tail_s = 3.0
    diffuse_level = 0.20
    listener_radius_m = 1.0
    source_x = 20
    source_y = 7
    source_z = 1.5
    listener_x = 10
    listener_y = 7
    listener_z = 1.5
    presetName$ = "Concert Hall"
elsif preset = 4
    # Bathroom (Bright)
    room_width_m = 2.5
    room_height_m = 2.2
    room_depth_m = 2.0
    number_of_rays = 250
    max_reflections = 20
    wall_absorption = 0.05
    air_absorption = 0.0005
    reverb_tail_s = 1.0
    diffuse_level = 0.25
    listener_radius_m = 0.3
    source_x = 0.8
    source_y = 1.1
    source_z = 1.0
    listener_x = 1.7
    listener_y = 1.1
    listener_z = 1.0
    presetName$ = "Bathroom"
elsif preset = 5
    # Recording Studio (Dead)
    room_width_m = 6
    room_height_m = 4
    room_depth_m = 5
    number_of_rays = 100
    max_reflections = 5
    wall_absorption = 0.70
    air_absorption = 0.0005
    reverb_tail_s = 0.3
    diffuse_level = 0.05
    listener_radius_m = 0.4
    source_x = 2
    source_y = 2
    source_z = 1.5
    listener_x = 4
    listener_y = 2
    listener_z = 1.5
    presetName$ = "Studio"
elsif preset = 6
    # Cathedral (Very Long)
    room_width_m = 60
    room_height_m = 25
    room_depth_m = 40
    number_of_rays = 400
    max_reflections = 30
    wall_absorption = 0.08
    air_absorption = 0.003
    reverb_tail_s = 5.0
    diffuse_level = 0.25
    listener_radius_m = 1.5
    source_x = 30
    source_y = 12
    source_z = 2.0
    listener_x = 15
    listener_y = 12
    listener_z = 2.0
    presetName$ = "Cathedral"
elsif preset = 7
    # Small Club
    room_width_m = 12
    room_height_m = 4
    room_depth_m = 10
    number_of_rays = 200
    max_reflections = 12
    wall_absorption = 0.25
    air_absorption = 0.001
    reverb_tail_s = 1.0
    diffuse_level = 0.12
    listener_radius_m = 0.6
    source_x = 3
    source_y = 2
    source_z = 1.5
    listener_x = 9
    listener_y = 2
    listener_z = 1.5
    presetName$ = "Club"
elsif preset = 8
    # Outdoor (Minimal)
    room_width_m = 100
    room_height_m = 50
    room_depth_m = 100
    number_of_rays = 80
    max_reflections = 3
    wall_absorption = 0.95
    air_absorption = 0.005
    reverb_tail_s = 0.2
    diffuse_level = 0.02
    listener_radius_m = 1.0
    source_x = 20
    source_y = 25
    source_z = 1.5
    listener_x = 25
    listener_y = 25
    listener_z = 1.5
    presetName$ = "Outdoor"
elsif preset = 9
    # Bright Chamber
    room_width_m = 8
    room_height_m = 6
    room_depth_m = 7
    number_of_rays = 250
    max_reflections = 15
    wall_absorption = 0.12
    air_absorption = 0.001
    reverb_tail_s = 1.5
    diffuse_level = 0.18
    listener_radius_m = 0.5
    source_x = 2
    source_y = 3
    source_z = 1.5
    listener_x = 6
    listener_y = 3
    listener_z = 1.5
    presetName$ = "Chamber"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# === Info ===
writeInfoLine: "=== Ray Tracing Room Acoustics ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Room: ", room_width_m, " × ", room_depth_m, " × ", room_height_m, " m (W×D×H)"
appendInfoLine: "Source: (", fixed$(source_x, 1), ", ", fixed$(source_y, 1), ", ", fixed$(source_z, 1), ")"
appendInfoLine: "Listener: (", fixed$(listener_x, 1), ", ", fixed$(listener_y, 1), ", ", fixed$(listener_z, 1), ")"
appendInfoLine: "Rays: ", number_of_rays, " × ", max_reflections, " reflections"
appendInfoLine: "Wall absorption: ", wall_absorption
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# === Calculate RT60 (Sabine's Formula) ===
volume = room_width_m * room_height_m * room_depth_m
surface_area = 2 * (room_width_m * room_height_m + room_width_m * room_depth_m + room_height_m * room_depth_m)
rt60 = 0.161 * volume / (wall_absorption * surface_area + 0.001)

if rt60 > 5.0
    rt60 = 5.0
elsif rt60 < 0.05
    rt60 = 0.05
endif

appendInfoLine: "RT60 (Sabine): ", fixed$(rt60, 2), " s"
appendInfoLine: "Volume: ", fixed$(volume, 1), " m³"
appendInfoLine: ""

# === Create Impulse Response ===
ir_duration = rt60 + reverb_tail_s
Create Sound from formula: "room_ir", 1, 0, ir_duration, sr, "0"
irSound = selected("Sound")

# === Direct Sound (Inverse Square Law) ===
direct_distance = sqrt((listener_x - source_x)^2 + (listener_y - source_y)^2 + (listener_z - source_z)^2)
direct_delay = direct_distance / speed_of_sound
direct_amplitude = 1.0 / (1.0 + direct_distance) * exp(-air_absorption * direct_distance)

direct_sample = round(direct_delay * sr)
if direct_sample < 1
    direct_sample = 1
endif

selectObject: irSound
Set value at sample number: 1, direct_sample, direct_amplitude

appendInfoLine: "Direct sound: ", fixed$(direct_delay * 1000, 1), " ms, amp=", fixed$(direct_amplitude, 3)
appendInfoLine: ""
appendInfoLine: "Ray tracing..."

# === 3D RAY TRACING ===
reflection_count = 0
total_reflection_energy = 0

for ray from 1 to number_of_rays
    # Fibonacci sphere distribution (even coverage)
    golden_ratio = (1 + sqrt(5)) / 2
    theta = 2 * pi * ray / golden_ratio
    
    z_val = 1 - 2 * (ray - 0.5) / number_of_rays
    if z_val > 1
        z_val = 1
    elsif z_val < -1
        z_val = -1
    endif
    
    phi = arccos(z_val)
    
    # Starting position and direction
    pos_x = source_x
    pos_y = source_y
    pos_z = source_z
    
    dir_x = sin(phi) * cos(theta)
    dir_y = sin(phi) * sin(theta)
    dir_z = cos(phi)
    
    energy = 1.0
    total_path_length = 0
    exitRay = 0
    
    # Trace reflections
    for reflection from 1 to max_reflections
        if exitRay = 0
            # Find intersection with 6 walls
            if dir_x > 0.0001
                t_right = (room_width_m - pos_x) / dir_x
            else
                t_right = 1e10
            endif
            if dir_x < -0.0001
                t_left = -pos_x / dir_x
            else
                t_left = 1e10
            endif
            
            if dir_y > 0.0001
                t_top = (room_height_m - pos_y) / dir_y
            else
                t_top = 1e10
            endif
            if dir_y < -0.0001
                t_bottom = -pos_y / dir_y
            else
                t_bottom = 1e10
            endif
            
            if dir_z > 0.0001
                t_back = (room_depth_m - pos_z) / dir_z
            else
                t_back = 1e10
            endif
            if dir_z < -0.0001
                t_front = -pos_z / dir_z
            else
                t_front = 1e10
            endif
            
            # Find nearest wall
            t_wall = min(t_right, min(t_left, min(t_top, min(t_bottom, min(t_back, t_front)))))
            
            # New position
            new_x = pos_x + dir_x * t_wall
            new_y = pos_y + dir_y * t_wall
            new_z = pos_z + dir_z * t_wall
            
            # Path length and energy
            segment_distance = sqrt((new_x - pos_x)^2 + (new_y - pos_y)^2 + (new_z - pos_z)^2)
            total_path_length = total_path_length + segment_distance
            energy = energy * (1 - wall_absorption) * exp(-air_absorption * segment_distance)
            
            # Check if ray passes near listener
            dx_seg = new_x - pos_x
            dy_seg = new_y - pos_y
            dz_seg = new_z - pos_z
            seg_length_sq = dx_seg^2 + dy_seg^2 + dz_seg^2
            
            if seg_length_sq > 0
                t_closest = ((listener_x - pos_x) * dx_seg + (listener_y - pos_y) * dy_seg + (listener_z - pos_z) * dz_seg) / seg_length_sq
            else
                t_closest = 0
            endif
            
            if t_closest >= 0 and t_closest <= 1
                closest_x = pos_x + t_closest * dx_seg
                closest_y = pos_y + t_closest * dy_seg
                closest_z = pos_z + t_closest * dz_seg
                dist_to_listener = sqrt((listener_x - closest_x)^2 + (listener_y - closest_y)^2 + (listener_z - closest_z)^2)
                
                if dist_to_listener < listener_radius_m and energy > 0.001
                    path_to_reflection = total_path_length - (1 - t_closest) * segment_distance
                    total_acoustic_path = path_to_reflection + dist_to_listener
                    
                    amplitude = energy / (1.0 + total_acoustic_path) * exp(-air_absorption * total_acoustic_path)
                    delay_time = total_acoustic_path / speed_of_sound
                    sample_pos = round(delay_time * sr)
                    
                    if sample_pos > direct_sample and sample_pos < ir_duration * sr
                        amp_str$ = string$(amplitude)
                        t1 = sample_pos / sr
                        t2 = (sample_pos + 1) / sr
                        
                        selectObject: irSound
                        Formula (part): t1, t2, 1, 1, "self + " + amp_str$
                        reflection_count = reflection_count + 1
                        total_reflection_energy = total_reflection_energy + amplitude
                    endif
                endif
            endif
            
            # Reflect direction
            if t_wall = t_right or t_wall = t_left
                dir_x = -dir_x
            endif
            if t_wall = t_top or t_wall = t_bottom
                dir_y = -dir_y
            endif
            if t_wall = t_back or t_wall = t_front
                dir_z = -dir_z
            endif
            
            # Update position
            pos_x = new_x
            pos_y = new_y
            pos_z = new_z
            
            # Exit if energy too low
            if energy < 0.001
                exitRay = 1
            endif
        endif
    endfor
endfor

appendInfoLine: "Traced reflections: ", reflection_count
appendInfoLine: "Reflection energy: ", fixed$(total_reflection_energy, 3)
appendInfoLine: "Direct/Reverb ratio: ", fixed$(direct_amplitude / (total_reflection_energy + 0.001), 2)
appendInfoLine: ""

# === Add Diffuse Reverb Tail ===
appendInfoLine: "Adding diffuse tail..."
selectObject: irSound
rt60_str$ = string$(rt60)
diff_str$ = string$(diffuse_level)
Formula: "self + " + diff_str$ + " * randomGauss(0, 1) * exp(-6.9 * x / " + rt60_str$ + ")"

Scale peak: 0.99
appendInfoLine: "IR duration: ", fixed$(ir_duration, 2), " s"
appendInfoLine: ""

# === Convolve ===
appendInfoLine: "Convolving..."
selectObject: original, irSound
Convolve: "sum", "zero"
wetSound = selected("Sound")

# === Apply Wet/Dry Mix ===
if dry_level > 0
    # Extend dry to match wet length
    selectObject: wetSound
    wetDur = Get total duration
    
    selectObject: original
    Copy: "dry_extended"
    dryExt = selected("Sound")
    
    dryDur = Get total duration
    if dryDur < wetDur
        # Create silence pad with SAME channel count as original
        Create Sound from formula: "sil_pad", numChannels, 0, wetDur - dryDur, sr, "0"
        silPad = selected("Sound")
        selectObject: dryExt, silPad
        Concatenate
        temp = selected("Sound")
        removeObject: silPad, dryExt
        dryExt = temp
    endif
    
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dryExt)
    
    selectObject: wetSound
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
    
    removeObject: dryExt
endif

selectObject: wetSound
Scale peak: 0.95
Rename: originalName$ + "_raytraced_" + presetName$
result = selected("Sound")

# ============================================================
# PROFESSIONAL VISUALIZATION
# ============================================================

Erase all

# === COLOR DEFINITIONS ===
wallColor$ = "{0.2, 0.2, 0.25}"
floorColor$ = "{0.25, 0.25, 0.3}"
sourceColor$ = "{0.9, 0.3, 0.2}"
listenerColor$ = "{0.2, 0.5, 0.9}"
gridColor$ = "{0.35, 0.35, 0.4}"
textColor$ = "{0.9, 0.9, 0.9}"
accentColor$ = "{0.9, 0.7, 0.2}"

# ============================================================
# PANEL 1: TOP VIEW (Bird's Eye)
# ============================================================
Select outer viewport: 0, 4, 0.6, 3.4
Select inner viewport: 0.5, 3.7, 0.9, 3.2

# Background
Axes: -room_width_m * 0.05, room_width_m * 1.05, -room_depth_m * 0.05, room_depth_m * 1.05
Paint rectangle: "{0.12, 0.12, 0.15}", -room_width_m * 0.05, room_width_m * 1.05, -room_depth_m * 0.05, room_depth_m * 1.05

# Room floor
Paint rectangle: floorColor$, 0, room_width_m, 0, room_depth_m

# Grid lines
Colour: gridColor$
Line width: 1
Dotted line
gridStep = 1
if room_width_m > 20
    gridStep = 5
elsif room_width_m > 10
    gridStep = 2
endif

gx = gridStep
while gx < room_width_m
    Draw line: gx, 0, gx, room_depth_m
    gx = gx + gridStep
endwhile

gz = gridStep
while gz < room_depth_m
    Draw line: 0, gz, room_width_m, gz
    gz = gz + gridStep
endwhile
Solid line

# Room walls
Line width: 3
Colour: "{0.4, 0.4, 0.45}"
Draw line: 0, 0, room_width_m, 0
Draw line: room_width_m, 0, room_width_m, room_depth_m
Draw line: room_width_m, room_depth_m, 0, room_depth_m
Draw line: 0, room_depth_m, 0, 0

# Draw rays (re-trace for visualization)
Line width: 1
for vizRay from 1 to min(number_of_rays, 60)
    if vizRay mod 3 = 0
        golden_ratio = (1 + sqrt(5)) / 2
        theta = 2 * pi * vizRay / golden_ratio
        z_val = 1 - 2 * (vizRay - 0.5) / number_of_rays
        if z_val > 1
            z_val = 1
        elsif z_val < -1
            z_val = -1
        endif
        phi = arccos(z_val)
        
        vpos_x = source_x
        vpos_z = source_z
        vdir_x = sin(phi) * cos(theta)
        vdir_z = cos(phi)
        
        for refl from 1 to min(4, max_reflections)
            if vdir_x > 0.0001
                vt_right = (room_width_m - vpos_x) / vdir_x
            else
                vt_right = 1e10
            endif
            if vdir_x < -0.0001
                vt_left = -vpos_x / vdir_x
            else
                vt_left = 1e10
            endif
            if vdir_z > 0.0001
                vt_back = (room_depth_m - vpos_z) / vdir_z
            else
                vt_back = 1e10
            endif
            if vdir_z < -0.0001
                vt_front = -vpos_z / vdir_z
            else
                vt_front = 1e10
            endif
            
            vt_wall = min(vt_right, min(vt_left, min(vt_back, vt_front)))
            if vt_wall < 1000
                vnew_x = vpos_x + vdir_x * vt_wall
                vnew_z = vpos_z + vdir_z * vt_wall
                
                intensity = 0.8 - refl * 0.15
                if intensity < 0.2
                    intensity = 0.2
                endif
                Colour: "{" + fixed$(0.3 + intensity * 0.3, 2) + ", " + fixed$(0.5 + intensity * 0.3, 2) + ", " + fixed$(0.3 + intensity * 0.2, 2) + "}"
                Draw line: vpos_x, vpos_z, vnew_x, vnew_z
                
                if vt_wall = vt_right or vt_wall = vt_left
                    vdir_x = -vdir_x
                endif
                if vt_wall = vt_back or vt_wall = vt_front
                    vdir_z = -vdir_z
                endif
                
                vpos_x = vnew_x
                vpos_z = vnew_z
            endif
        endfor
    endif
endfor

# Direct sound path
Line width: 2
Colour: accentColor$
Dashed line
Draw line: source_x, source_z, listener_x, listener_z
Solid line

# Source marker
Colour: sourceColor$
Paint circle (mm): sourceColor$, source_x, source_z, 3.5
Line width: 1.5
Colour: "{1, 0.5, 0.4}"
Draw circle (mm): source_x, source_z, 5

# Listener marker  
Colour: listenerColor$
Paint circle (mm): listenerColor$, listener_x, listener_z, 3.5
Line width: 1.5
Colour: "{0.4, 0.7, 1}"
Draw circle (mm): listener_x, listener_z, 5

Line width: 1

# Title
Font size: 9
Colour: "Black"
Select outer viewport: 0, 4, 0.4, 0.65
Text: 0.5, "centre", 0.5, "half", "TOP VIEW (X-Z)"

# ============================================================
# PANEL 2: SIDE VIEW (Elevation)
# ============================================================
Select outer viewport: 4, 8, 0.6, 3.4
Select inner viewport: 4.5, 7.7, 0.9, 3.2

# Background
Axes: -room_depth_m * 0.05, room_depth_m * 1.05, -room_height_m * 0.05, room_height_m * 1.05
Paint rectangle: "{0.12, 0.12, 0.15}", -room_depth_m * 0.05, room_depth_m * 1.05, -room_height_m * 0.05, room_height_m * 1.05

# Room cross-section
Paint rectangle: "{0.18, 0.18, 0.22}", 0, room_depth_m, 0, room_height_m

# Grid
Colour: gridColor$
Dotted line
gridStepH = 1
if room_height_m > 10
    gridStepH = 2
endif

gz = gridStep
while gz < room_depth_m
    Draw line: gz, 0, gz, room_height_m
    gz = gz + gridStep
endwhile

gy = gridStepH
while gy < room_height_m
    Draw line: 0, gy, room_depth_m, gy
    gy = gy + gridStepH
endwhile
Solid line

# Walls
Line width: 3
Colour: "{0.4, 0.4, 0.45}"
Draw rectangle: 0, room_depth_m, 0, room_height_m

# Floor
Line width: 4
Colour: "{0.45, 0.4, 0.35}"
Draw line: 0, 0, room_depth_m, 0

# Ceiling
Line width: 2
Colour: "{0.35, 0.35, 0.4}"
Draw line: 0, room_height_m, room_depth_m, room_height_m

# Source (Z-Y plane)
Colour: sourceColor$
Paint circle (mm): sourceColor$, source_z, source_y, 3.5
Line width: 1.5
Colour: "{1, 0.5, 0.4}"
Draw circle (mm): source_z, source_y, 5

# Listener
Colour: listenerColor$
Paint circle (mm): listenerColor$, listener_z, listener_y, 3.5
Line width: 1.5
Colour: "{0.4, 0.7, 1}"
Draw circle (mm): listener_z, listener_y, 5

# Direct path
Line width: 2
Colour: accentColor$
Dashed line
Draw line: source_z, source_y, listener_z, listener_y
Solid line
Line width: 1

# Title
Font size: 9
Colour: "Black"
Select outer viewport: 4, 8, 0.4, 0.65
Text: 0.5, "centre", 0.5, "half", "SIDE VIEW (Z-Y)"

# ============================================================
# PANEL 3: IMPULSE RESPONSE
# ============================================================
Select outer viewport: 0, 5, 3.5, 5.0
Select inner viewport: 0.5, 4.8, 3.7, 4.85

selectObject: irSound
Colour: "{0.4, 0.6, 0.8}"
Draw: 0, 0, 0, 0, "no", "Curve"

# Mark direct sound
Colour: accentColor$
Line width: 2
Draw line: direct_delay, -0.8, direct_delay, 0.8
Line width: 1

Colour: "Black"
Draw inner box

Font size: 7
Colour: "{0.3, 0.3, 0.3}"
Text left: "yes", "Amplitude"
Text bottom: "yes", "Time (s)"

# Direct label
Font size: 6
Colour: accentColor$
Text: direct_delay + ir_duration * 0.02, "left", 0.6, "half", "Direct"

# Title
Font size: 9
Colour: "Black"
Select outer viewport: 0, 5, 3.35, 3.55
Text: 0.5, "centre", 0.5, "half", "IMPULSE RESPONSE"

# ============================================================
# PANEL 4: PARAMETERS
# ============================================================
Select outer viewport: 5, 8, 3.5, 5.0

Font size: 9
Colour: "Black"
Text: 0.05, "left", 1.95, "half", "PARAMETERS"

Font size: 7
Colour: "{0.25, 0.25, 0.25}"

# Column 1: Room
Text: 0.05, "left", 0.78, "half", "Room: " + fixed$(room_width_m, 1) + "×" + fixed$(room_depth_m, 1) + "×" + fixed$(room_height_m, 1) + "m"
Text: 0.05, "left", 0.52, "half", "Volume: " + fixed$(volume, 0) + " m³"
Text: 0.05, "left", 0.36, "half", "RT60: " + fixed$(rt60, 2) + " s"
Text: 0.05, "left", 0.20, "half", "Wall abs: " + fixed$(wall_absorption, 2)
Text: 0.05, "left", 0.04, "half", "Air abs: " + fixed$(air_absorption, 4)

# Column 2: Ray tracing
Text: 0.95, "left", 0.78, "half", "Rays: " + string$(number_of_rays)
Text: 0.95, "left", 0.52, "half", "Reflections: " + string$(max_reflections)
Text: 0.95, "left", 0.36, "half", "Hits: " + string$(reflection_count)
Text: 0.95, "left", 0.20, "half", "Direct: " + fixed$(direct_delay * 1000, 1) + " ms"
Text: 0.95, "left", 0.04, "half", "Wet: " + fixed$(wet_dry_percent, 0) + "%"

# ============================================================
# MAIN TITLE
# ============================================================
Select outer viewport: 0, 8, 0, 0.4
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.5, "half", "Ray Tracing Room Acoustics: " + originalName$ + " [" + presetName$ + "]"

# ============================================================
# LEGEND
# ============================================================
Select outer viewport: 0, 8, 5.0, 5.3
Font size: 7

Colour: sourceColor$
Paint circle (mm): sourceColor$, 0.12, 0.5, 1.5
Colour: "Black"
Text: 0.14, "left", 0.5, "half", "Source"

Colour: listenerColor$
Paint circle (mm): listenerColor$, 0.32, 0.5, 1.5
Colour: "Black"
Text: 0.34, "left", 0.5, "half", "Listener"

Colour: "{0.5, 0.7, 0.5}"
Text: 0.52, "left", 0.5, "half", "— Rays"

Colour: accentColor$
Text: 0.68, "left", 0.5, "half", "-- Direct"

Font size: 10
Colour: "Black"

# ============================================================
# CLEANUP
# ============================================================

removeObject: irSound

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", originalName$, "_raytraced_", presetName$
appendInfoLine: ""
appendInfoLine: "Physics implemented:"
appendInfoLine: "  - TRUE 3D ray tracing (all 6 walls)"
appendInfoLine: "  - Inverse square law (1/r)"
appendInfoLine: "  - Air absorption"
appendInfoLine: "  - Wall absorption"
appendInfoLine: "  - Sabine RT60"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result