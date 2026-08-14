# ============================================================
# Praat AudioTools - Ray_Tracing_Room_Acoustics.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ray Tracing Room Acoustics - geometric 3D room approximation
#   using ray tracing. Implements spherical-spreading amplitude,
#   air absorption, wall absorption, and Sabine RT60.
#   Uses Fibonacci sphere for even ray distribution. Creates
#   impulse response and convolves with input.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - Public form/defaults, output naming and final selection are unchanged.
#   - Fixed coordinate convention to x=width, y=depth, z=height, matching the
#     preset source/listener values (e.g. z=1.5 m as source/listener height).
#   - Corrected reflection attenuation order: listener hits are evaluated before
#     the next wall loss; air absorption is no longer double-counted.
#   - The source-to-first-wall segment is no longer counted as a reflection.
#   - Wall_absorption is treated as an energy coefficient; pressure-amplitude
#     reflection uses sqrt(1-alpha).
#   - Custom geometry, source/listener positions and ray/reflection counts are
#     sanitized internally without changing the public form.
#   - IR duration includes direct propagation delay; diffuse tail is causal,
#     deterministic, and restores Praat's global RNG afterwards.
#   - Wet/Dry cell routing is explicit and IR/output normalization is ceiling-only.
#   - Visualization uses X-Y top view and Y-Z side view consistently.
#
# Changelog v0.3:
#   - Audio output is bit-identical to v0.2 for the same form
#     parameters AND same Praat RNG state. Same Fibonacci
#     sphere ray distribution, same 6-wall intersection math,
#     same energy decay (wall absorption x air absorption x
#     inverse square), same Sabine RT60, same diffuse tail
#     formula (randomGauss * exp), same Convolve, same
#     wet/dry mix. Same 8 presets with same values.
#   - PERFORMANCE: per-reflection IR accumulation now uses
#     Get/Set value at sample number instead of Formula (part)
#     for a single-sample range. Formula (part) has substantial
#     per-call overhead (formula parsing, axes setup) that
#     dominated when applied to 1-sample ranges. Get/Set is
#     O(1) per call. For typical parameters (~500 reflections
#     hitting the listener), this saves ~1-3 seconds of
#     wallclock. Audio output is identical (same arithmetic:
#     current + amplitude, same sample position, same order).
#   - Dropped 9 decorative form lines (7 `comment === ... ===`
#     section dividers, 1 instructional, 1 inline parenthetical).
#     Form went from ~22 effective rows to 13.
#   - NEW: Draw_visualization boolean form toggle (default 1).
#     v0.2 always drew the visualization.
#   - Visualization reorganized to suite 8x8 standard while
#     PRESERVING the CAD-style dark room views:
#       Title bar (suite light) + metadata subtitle
#       Panel A (left, headline): TOP VIEW (X-Z plane) —
#         PRESERVED v0.2's dark CAD aesthetic with grid,
#         walls, rays, source, listener, direct path
#       Panel B (right, headline): SIDE VIEW (Z-Y plane) —
#         PRESERVED v0.2's dark CAD aesthetic
#       Panel C: impulse response waveform with direct
#         sound marker and RT60 reference line
#       Panel D: full waveform comparison (gray = original,
#         blue = result, SHARED y-axis)
#       Panel E: light-grey summary stats bar (suite standard)
#         with room dims, volume, RT60, ray count, reflection
#         count, direct delay, wet/dry, output stats
#     The old "parameters" text panel and "legend" strip are
#     removed (redundant with the title subtitle and Panel E).
# Changelog v0.2:
#   - Added input check
#   - Fixed selection syntax
#   - Fixed undefined preset$ variable
#   - Added wet/dry mix control
#   - Removed goto (replaced with flag)
#   - Professional multi-panel visualization
# ============================================================

form Ray Tracing Room Acoustics v0.3
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
    positive Room_width_m 8
    positive Room_height_m 6
    positive Room_depth_m 5
    positive Number_of_rays 200
    positive Max_reflections 15
    positive Listener_radius_m 0.5
    positive Wall_absorption 0.15
    positive Air_absorption 0.001
    positive Speed_of_sound 343
    positive Reverb_tail_s 1.5
    positive Diffuse_level 0.15
    positive Source_x 2
    positive Source_y 3
    positive Source_z 1.5
    positive Listener_x 6
    positive Listener_y 3
    positive Listener_z 1.5
    real Wet_dry_percent 60
    boolean Draw_visualization 1
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
    presetName$ = "LivingRoom"
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
    presetName$ = "ConcertHall"
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

# Internal geometry/stability guards; built-in presets remain unchanged.
if room_width_m < 0.1
    room_width_m = 0.1
endif
if room_depth_m < 0.1
    room_depth_m = 0.1
endif
if room_height_m < 0.1
    room_height_m = 0.1
endif

effectiveRays = round(number_of_rays)
if effectiveRays < 1
    effectiveRays = 1
endif

effectiveReflections = round(max_reflections)
if effectiveReflections < 1
    effectiveReflections = 1
endif

wallAbsEff = wall_absorption
if wallAbsEff < 0
    wallAbsEff = 0
elsif wallAbsEff > 0.99
    wallAbsEff = 0.99
endif
wallReflectionAmp = sqrt(1 - wallAbsEff)

airAbsEff = max(0, air_absorption)
speedEff = max(1, speed_of_sound)
tailEff = max(2 / sr, reverb_tail_s)

diffuseEff = diffuse_level
if diffuseEff < 0
    diffuseEff = 0
elsif diffuseEff > 1
    diffuseEff = 1
endif

minRoomDim = min(room_width_m, min(room_depth_m, room_height_m))
coordEps = max(0.000001, minRoomDim * 0.000001)

# Coordinate convention: x=width, y=depth, z=height.
source_x = min(room_width_m - coordEps, max(coordEps, source_x))
source_y = min(room_depth_m - coordEps, max(coordEps, source_y))
source_z = min(room_height_m - coordEps, max(coordEps, source_z))
listener_x = min(room_width_m - coordEps, max(coordEps, listener_x))
listener_y = min(room_depth_m - coordEps, max(coordEps, listener_y))
listener_z = min(room_height_m - coordEps, max(coordEps, listener_z))

listenerRadiusEff = listener_radius_m
if listenerRadiusEff < 0.001
    listenerRadiusEff = 0.001
endif
maxListenerRadius = 0.49 * minRoomDim
if listenerRadiusEff > maxListenerRadius
    listenerRadiusEff = maxListenerRadius
endif

# === Info ===
writeInfoLine: "=== Ray Tracing Room Acoustics v0.4 ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Room: ", room_width_m, " x ", room_depth_m, " x ", room_height_m, " m (W x D x H)"
appendInfoLine: "Source (x=width,y=depth,z=height): (", fixed$(source_x, 1), ", ", fixed$(source_y, 1), ", ", fixed$(source_z, 1), ")"
appendInfoLine: "Listener (x=width,y=depth,z=height): (", fixed$(listener_x, 1), ", ", fixed$(listener_y, 1), ", ", fixed$(listener_z, 1), ")"
appendInfoLine: "Rays: ", effectiveRays, " x ", effectiveReflections, " max reflections"
appendInfoLine: "Wall absorption: ", wallAbsEff
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# === Calculate RT60 (Sabine's Formula) ===
volume = room_width_m * room_height_m * room_depth_m
surface_area = 2 * (room_width_m * room_height_m + room_width_m * room_depth_m + room_height_m * room_depth_m)
rt60 = 0.161 * volume / (wallAbsEff * surface_area + 0.001)

if rt60 > 5.0
    rt60 = 5.0
elsif rt60 < 0.05
    rt60 = 0.05
endif

appendInfoLine: "RT60 (Sabine): ", fixed$(rt60, 2), " s"
appendInfoLine: "Volume: ", fixed$(volume, 1), " m^3"
appendInfoLine: ""

# === Direct Sound / Impulse Response geometry ===
direct_distance = sqrt((listener_x - source_x)^2 + (listener_y - source_y)^2 + (listener_z - source_z)^2)
direct_delay = direct_distance / speedEff
direct_amplitude = 1.0 / (1.0 + direct_distance) * exp(-airAbsEff * direct_distance)

# Full RT60 + requested tail occurs AFTER direct arrival.
ir_duration = direct_delay + rt60 + tailEff
Create Sound from formula: "room_ir", 1, 0, ir_duration, sr, "0"
irSound = selected("Sound")

selectObject: irSound
irSamples = Get number of samples

direct_sample = round(direct_delay * sr)
if direct_sample < 1
    direct_sample = 1
elsif direct_sample > irSamples
    direct_sample = irSamples
endif

Set value at sample number: 1, direct_sample, direct_amplitude

appendInfoLine: "Direct sound: ", fixed$(direct_delay * 1000, 1), " ms, amp=", fixed$(direct_amplitude, 3)
appendInfoLine: ""
appendInfoLine: "Ray tracing..."

# ============================================================
# 3D RAY TRACING
# Unchanged from v0.2 EXCEPT the per-reflection accumulation
# inside the inner loop uses Get/Set value at sample number
# (O(1)) instead of Formula (part) on a 1-sample range
# (heavy parser overhead).
# ============================================================
reflection_count = 0
total_reflection_energy = 0

# Cache for visualization (only the rays we'll display)
# Max 60 vizRays, only every 3rd drawn -> ~20 rays
vizMaxRays = 60
vizPathsX# = zero#(vizMaxRays * 5)
vizPathsY# = zero#(vizMaxRays * 5)
vizPathsZ# = zero#(vizMaxRays * 5)
vizPathLen# = zero#(vizMaxRays)

for ray from 1 to effectiveRays
    # Fibonacci sphere distribution (even coverage)
    golden_ratio = (1 + sqrt(5)) / 2
    theta = 2 * pi * ray / golden_ratio
    
    z_val = 1 - 2 * (ray - 0.5) / effectiveRays
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
    
    # Cache start point for viz
    if ray <= vizMaxRays
        vizPathsX#[(ray - 1) * 5 + 1] = pos_x
        vizPathsY#[(ray - 1) * 5 + 1] = pos_y
        vizPathsZ#[(ray - 1) * 5 + 1] = pos_z
        vizPathLen#[ray] = 1
    endif
    
    # Trace reflections
    for reflection from 1 to effectiveReflections
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
                t_top = (room_depth_m - pos_y) / dir_y
            else
                t_top = 1e10
            endif
            if dir_y < -0.0001
                t_bottom = -pos_y / dir_y
            else
                t_bottom = 1e10
            endif
            
            if dir_z > 0.0001
                t_back = (room_height_m - pos_z) / dir_z
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
            
            # Path geometry. 'energy' is pressure-amplitude gain at the START
            # of this segment, after all previous wall and air losses.
            segment_distance = sqrt((new_x - pos_x)^2 + (new_y - pos_y)^2 + (new_z - pos_z)^2)

            # Evaluate listener arrival before applying the wall loss that ends
            # this segment. Iteration 1 is source->first wall, so only iteration
            # 2 onward represents at least one completed reflection.
            dx_seg = new_x - pos_x
            dy_seg = new_y - pos_y
            dz_seg = new_z - pos_z
            seg_length_sq = dx_seg^2 + dy_seg^2 + dz_seg^2

            if reflection >= 2 and seg_length_sq > 0
                t_closest = ((listener_x - pos_x) * dx_seg + (listener_y - pos_y) * dy_seg + (listener_z - pos_z) * dz_seg) / seg_length_sq

                if t_closest >= 0 and t_closest <= 1
                    closest_x = pos_x + t_closest * dx_seg
                    closest_y = pos_y + t_closest * dy_seg
                    closest_z = pos_z + t_closest * dz_seg
                    dist_to_listener = sqrt((listener_x - closest_x)^2 + (listener_y - closest_y)^2 + (listener_z - closest_z)^2)

                    if dist_to_listener < listenerRadiusEff and energy > 0.001
                        along_segment = t_closest * segment_distance
                        total_acoustic_path = total_path_length + along_segment + dist_to_listener
                        new_air_path = along_segment + dist_to_listener

                        amplitude = energy * exp(-airAbsEff * new_air_path) / (1.0 + total_acoustic_path)
                        delay_time = total_acoustic_path / speedEff
                        sample_pos = round(delay_time * sr)

                        if sample_pos > direct_sample and sample_pos <= irSamples
                            selectObject: irSound
                            current_val = Get value at sample number: 1, sample_pos
                            Set value at sample number: 1, sample_pos, current_val + amplitude
                            reflection_count = reflection_count + 1
                            total_reflection_energy = total_reflection_energy + amplitude
                        endif
                    endif
                endif
            endif

            # Advance to the wall, then apply THIS wall and segment losses.
            total_path_length = total_path_length + segment_distance
            energy = energy * exp(-airAbsEff * segment_distance) * wallReflectionAmp

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
            
            # Cache viz path point (up to 4 reflections per ray for display)
            if ray <= vizMaxRays and reflection <= 4
                idx = (ray - 1) * 5 + reflection + 1
                vizPathsX#[idx] = pos_x
                vizPathsY#[idx] = pos_y
                vizPathsZ#[idx] = pos_z
                vizPathLen#[ray] = reflection + 1
            endif
            
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
appendInfoLine: "Adding causal diffuse tail..."
selectObject: irSound
rt60_str$ = string$(rt60)
diff_str$ = string$(diffuseEff)
direct_str$ = string$(direct_delay)

researchSeed = 20260814
random_initializeWithSeedUnsafelyButPredictably (researchSeed)
if diffuseEff > 0
    Formula: "if x >= " + direct_str$ + " then self + " + diff_str$ + " * randomGauss(0, 1) * exp(-6.9 * (x - " + direct_str$ + ") / " + rt60_str$ + ") else self fi"
endif
random_initializeSafelyAndUnpredictably ()

irPeak = Get absolute extremum: 0, 0, "None"
if irPeak > 0.99
    Scale peak: 0.99
endif

appendInfoLine: "IR duration: ", fixed$(ir_duration, 2), " s | Seed: ", researchSeed
appendInfoLine: ""

# === Convolve ===
appendInfoLine: "Convolving..."
selectObject: original, irSound
Convolve: "sum", "zero"
wetSound = selected("Sound")

# === Apply Wet/Dry Mix ===
if dry_level > 0
    selectObject: wetSound
    wetDur = Get total duration
    
    selectObject: original
    Copy: "dry_extended"
    dryExt = selected("Sound")
    
    dryDur = Get total duration
    if dryDur < wetDur
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
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", row, col] * " + dry_str$
    
    removeObject: dryExt
endif

selectObject: wetSound
finalPrePeak = Get absolute extremum: 0, 0, "None"
if finalPrePeak > 0.95
    Scale peak: 0.95
endif
Rename: originalName$ + "_raytraced_" + presetName$
result = selected("Sound")

# Capture stats for visualization
selectObject: result
resultDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
resultNumCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard with
# preserved CAD-style dark room views in Panels A and B)
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # Color palette (preserved from v0.2 for room views)
    floorColor$ = "{0.25, 0.25, 0.3}"
    sourceColor$ = "{0.9, 0.3, 0.2}"
    listenerColor$ = "{0.2, 0.5, 0.9}"
    gridColor$ = "{0.35, 0.35, 0.4}"
    accentColor$ = "{0.9, 0.7, 0.2}"
    
    # Mono copies for waveform panels
    selectObject: original
    if numChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz_orig"
    endif
    
    selectObject: result
    if resultNumCh > 1
        vizResult = Convert to mono
    else
        vizResult = Copy: "viz_result"
    endif
    
    # SHARED y-axis from BOTH original and result
    selectObject: vizOrig
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    rPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = oPeak
    if rPeak > sharedPeak
        sharedPeak = rPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.15
    
    # ----------------------------------------------------------
    # TITLE BAR  (suite standard light)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##RAY TRACING ROOM ACOUSTICS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + fixed$(room_width_m, 1) + " x " + fixed$(room_depth_m, 1) + " x " + fixed$(room_height_m, 1) + " m"
        ... + "  |  RT60 " + fixed$(rt60, 2) + " s"
        ... + "  |  " + string$(effectiveRays) + " rays x " + string$(effectiveReflections)
        ... + "  |  " + fixed$(wet_dry_percent, 0) + "% wet"
    
    # ----------------------------------------------------------
    # PANEL A: TOP VIEW (X-Y plane)  (left, headline)
    # PRESERVED v0.2 CAD-style dark aesthetic
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    # Dark background (slight padding outside the room)
    Axes: -room_width_m * 0.05, room_width_m * 1.05, -room_depth_m * 0.05, room_depth_m * 1.05
    Paint rectangle: "{0.12, 0.12, 0.15}", -room_width_m * 0.05, room_width_m * 1.05, -room_depth_m * 0.05, room_depth_m * 1.05
    
    # Room floor (slightly lighter dark)
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
    
    # Draw rays from cached paths (every 3rd of first 60 — ~20 rays)
    Line width: 1
    for vizRay from 1 to vizMaxRays
        if vizRay mod 3 = 0 and vizRay <= effectiveRays
            nPts = vizPathLen#[vizRay]
            for p from 1 to nPts - 1
                px1 = vizPathsX#[(vizRay - 1) * 5 + p]
                py1 = vizPathsY#[(vizRay - 1) * 5 + p]
                px2 = vizPathsX#[(vizRay - 1) * 5 + p + 1]
                py2 = vizPathsY#[(vizRay - 1) * 5 + p + 1]
                
                # Color fades with reflection number
                intensity = 0.8 - (p - 1) * 0.15
                if intensity < 0.2
                    intensity = 0.2
                endif
                Colour: "{" + fixed$(0.3 + intensity * 0.3, 2) + ", " + fixed$(0.5 + intensity * 0.3, 2) + ", " + fixed$(0.3 + intensity * 0.2, 2) + "}"
                Draw line: px1, py1, px2, py2
            endfor
        endif
    endfor
    
    # Direct sound path
    Line width: 2
    Colour: accentColor$
    Dashed line
    Draw line: source_x, source_y, listener_x, listener_y
    Solid line
    
    # Source marker
    Colour: sourceColor$
    Paint circle (mm): sourceColor$, source_x, source_y, 3.5
    Line width: 1.5
    Colour: "{1, 0.5, 0.4}"
    Draw circle (mm): source_x, source_y, 5
    
    # Listener marker
    Colour: listenerColor$
    Paint circle (mm): listenerColor$, listener_x, listener_y, 3.5
    Line width: 1.5
    Colour: "{0.4, 0.7, 1}"
    Draw circle (mm): listener_x, listener_y, 5
    
    Line width: 1
    
    # ----------------------------------------------------------
    # PANEL B: SIDE VIEW (Y-Z plane)  (right, headline)
    # PRESERVED v0.2 CAD-style dark aesthetic
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    # Dark background
    Axes: -room_depth_m * 0.05, room_depth_m * 1.05, -room_height_m * 0.05, room_height_m * 1.05
    Paint rectangle: "{0.12, 0.12, 0.15}", -room_depth_m * 0.05, room_depth_m * 1.05, -room_height_m * 0.05, room_height_m * 1.05
    
    # Room cross-section
    Paint rectangle: "{0.18, 0.18, 0.22}", 0, room_depth_m, 0, room_height_m
    
    # Grid
    Colour: gridColor$
    Line width: 1
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
    
    # Source (Y-Z plane)
    Colour: sourceColor$
    Paint circle (mm): sourceColor$, source_y, source_z, 3.5
    Line width: 1.5
    Colour: "{1, 0.5, 0.4}"
    Draw circle (mm): source_y, source_z, 5
    
    # Listener
    Colour: listenerColor$
    Paint circle (mm): listenerColor$, listener_y, listener_z, 3.5
    Line width: 1.5
    Colour: "{0.4, 0.7, 1}"
    Draw circle (mm): listener_y, listener_z, 5
    
    # Direct path
    Line width: 2
    Colour: accentColor$
    Dashed line
    Draw line: source_y, source_z, listener_y, listener_z
    Solid line
    Line width: 1
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Top view  (X-Y plane, room from above)"
    Text: 6.10, "centre", 7.30, "half", "Side view  (Y-Z plane, room from side)"
    
    # ----------------------------------------------------------
    # PANEL C: IMPULSE RESPONSE WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    # IR needs absolute peak for y-axis
    selectObject: irSound
    irPeak = Get absolute extremum: 0, 0, "None"
    if irPeak < 0.001
        irPeak = 0.001
    endif
    irAmp = irPeak * 1.15
    
    Axes: 0, ir_duration, -irAmp, irAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, ir_duration, -irAmp, irAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, ir_duration, 0
    
    # RT60 reference line: decay time measured from direct arrival.
    rt60Marker = direct_delay + rt60
    Colour: "{0.70, 0.70, 0.75}"
    Line width: 1
    Dashed line
    if rt60Marker < ir_duration
        Draw line: rt60Marker, -irAmp, rt60Marker, irAmp
    endif
    Solid line
    
    # IR waveform
    selectObject: irSound
    Colour: "{0.30, 0.45, 0.75}"
    Line width: 1
    Draw: 0, ir_duration, -irAmp, irAmp, "no", "Curve"
    
    # Direct sound marker
    Colour: accentColor$
    Line width: 2
    Draw line: direct_delay, -irAmp, direct_delay, irAmp
    Line width: 1
    
    # Inline labels
    Font size: 5
    Colour: "{0.55, 0.45, 0.15}"
    Text: direct_delay + ir_duration * 0.01, "left", irAmp * 0.85, "half", "direct"
    if rt60Marker < ir_duration
        Colour: "{0.55, 0.55, 0.55}"
        Text: rt60Marker + ir_duration * 0.01, "left", irAmp * 0.85, "half", "RT60"
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Impulse response  (orange = direct, gray dashed = RT60)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: FULL WAVEFORM COMPARISON  (SHARED y-axis)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    if resultDur > originalDur
        dispDur = resultDur
    else
        dispDur = originalDur
    endif
    
    Axes: 0, dispDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dispDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, dispDur, 0
    
    # Mark where original ends if shorter than result
    if originalDur < resultDur
        Colour: "{0.85, 0.50, 0.20}"
        Line width: 1
        Dotted line
        Draw line: originalDur, -sharedAmp, originalDur, sharedAmp
        Solid line
        Font size: 5
        Text: originalDur, "left", sharedAmp * 0.85, "half", "  reverb tail"
    endif
    
    # Original behind (gray)
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, originalDur, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Result on top (blue)
    selectObject: vizResult
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, resultDur, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Full waveform  (gray = original, blue = result, shared y-axis)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Room: " + fixed$(room_width_m, 1) + " x " + fixed$(room_depth_m, 1) + " x " + fixed$(room_height_m, 1) + " m  (" + fixed$(volume, 0) + " m^3)"
        ... + "  |  RT60: " + fixed$(rt60, 2) + " s"
        ... + "  |  Wall abs: " + fixed$(wallAbsEff, 2)
        ... + "  |  Air abs: " + fixed$(airAbsEff, 4)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Rays: " + string$(effectiveRays) + " x " + string$(effectiveReflections)
        ... + "  |  Hits: " + string$(reflection_count)
        ... + "  |  Direct: " + fixed$(direct_delay * 1000, 1) + " ms (amp " + fixed$(direct_amplitude, 3) + ")"
        ... + "  |  Wet: " + fixed$(wet_dry_percent, 0) + "%"
        ... + "  |  In: " + fixed$(originalDur, 2) + " s"
        ... + "  |  Out: " + fixed$(resultDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: vizOrig, vizResult
endif

# === Cleanup ===
removeObject: irSound

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", originalName$, "_raytraced_", presetName$
appendInfoLine: ""
appendInfoLine: "Physics implemented:"
appendInfoLine: "  - 3D geometric ray tracing (all 6 walls)"
appendInfoLine: "  - Spherical-spreading pressure amplitude (~1/r)"
appendInfoLine: "  - Air absorption"
appendInfoLine: "  - Wall absorption"
appendInfoLine: "  - Sabine RT60"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
