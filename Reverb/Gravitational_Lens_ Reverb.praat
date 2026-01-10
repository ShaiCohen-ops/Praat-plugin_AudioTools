# ============================================================
# Praat AudioTools - Gravitational_Lens_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Gravitational Lens Reverb - physics-inspired reverb that
#   simulates relativistic spacetime effects. Sound "rays"
#   (echoes) are bent by gravitational "mass points", creating
#   warped delay times, amplitude lensing, and time dilation.
#   Based loosely on Schwarzschild metric concepts. Creates
#   organic, evolving diffusion patterns.
#
# Changelog v0.2:
#   - Fixed selection and formula syntax
#   - Fixed sqrt domain error (clamping)
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Gravitational Lens Reverb
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Lensing
        option Medium Lensing
        option Heavy Lensing
        option Extreme Lensing
    
    comment === Spacetime Parameters ===
    positive Tail_duration_s 4.0
    natural Mass_points 12
    natural Rays_per_mass 8
    positive Space_curvature 0.8
    
    comment === Mass Properties ===
    positive Mass_strength_mean 1.2
    positive Mass_strength_stddev 0.5
    
    comment === Ray Properties ===
    positive Ray_delay_start_s 0.05
    positive Ray_delay_increment_s 0.06
    positive Lensing_amplitude 0.16
    positive Time_dilation_factor 0.15
    
    comment === Fadeout ===
    positive Fadeout_duration_s 1.0
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
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
    # Subtle Lensing
    tail_duration_s = 2.5
    mass_points = 6
    rays_per_mass = 5
    space_curvature = 0.5
    mass_strength_mean = 0.8
    mass_strength_stddev = 0.3
    ray_delay_start_s = 0.06
    ray_delay_increment_s = 0.08
    lensing_amplitude = 0.12
    time_dilation_factor = 0.1
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Lensing
    tail_duration_s = 4.0
    mass_points = 12
    rays_per_mass = 8
    space_curvature = 0.8
    mass_strength_mean = 1.2
    mass_strength_stddev = 0.5
    ray_delay_start_s = 0.05
    ray_delay_increment_s = 0.06
    lensing_amplitude = 0.16
    time_dilation_factor = 0.15
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Lensing
    tail_duration_s = 5.5
    mass_points = 18
    rays_per_mass = 12
    space_curvature = 1.1
    mass_strength_mean = 1.6
    mass_strength_stddev = 0.7
    ray_delay_start_s = 0.04
    ray_delay_increment_s = 0.05
    lensing_amplitude = 0.2
    time_dilation_factor = 0.2
    fadeout_duration_s = 1.4
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Lensing
    tail_duration_s = 7.5
    mass_points = 25
    rays_per_mass = 16
    space_curvature = 1.5
    mass_strength_mean = 2.0
    mass_strength_stddev = 0.9
    ray_delay_start_s = 0.03
    ray_delay_increment_s = 0.04
    lensing_amplitude = 0.24
    time_dilation_factor = 0.25
    fadeout_duration_s = 1.8
    presetName$ = "Extreme"
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

# Pre-generate mass positions for visualization
for m from 1 to mass_points
    massPos[m] = randomUniform(0.03, 0.9)
    massStr[m] = randomGauss(mass_strength_mean, mass_strength_stddev)
    if massStr[m] < 0.1
        massStr[m] = 0.1
    endif
endfor

totalRays = mass_points * rays_per_mass

# === Info ===
writeInfoLine: "=== Gravitational Lens Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Mass points: ", mass_points
appendInfoLine: "Rays per mass: ", rays_per_mass
appendInfoLine: "Total rays: ", totalRays
appendInfoLine: "Space curvature: ", space_curvature
appendInfoLine: "Time dilation factor: ", time_dilation_factor
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Mass positions (first 5):"
for m from 1 to min(5, mass_points)
    appendInfoLine: "  Mass ", m, ": pos=", fixed$(massPos[m], 3), " strength=", fixed$(massStr[m], 2)
endfor
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Create silent tail
if numChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sr, "0"
endif
silentTail = selected("Sound")

# Concatenate
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

totalDur = originalDur + tail_duration_s

if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left
    selectObject: leftChannel
    Copy: "reverb_left"
    reverbLeft = selected("Sound")
    
    for mass from 1 to mass_points
        mass_position = massPos[mass]
        mass_strength = massStr[mass]
        
        for ray from 1 to rays_per_mass
            straight_delay = ray_delay_start_s + ray * ray_delay_increment_s
            distance_to_mass = abs(straight_delay - mass_position)
            bending = mass_strength / (distance_to_mass + 0.005)
            curved_delay = straight_delay + bending * space_curvature
            lensing_amp = lensing_amplitude / (1 + bending)
            
            # Time dilation - clamp to avoid sqrt of negative
            dilation_arg = 1 - mass_strength * time_dilation_factor
            if dilation_arg < 0.01
                dilation_arg = 0.01
            endif
            time_dilation = sqrt(dilation_arg)
            
            final_delay = curved_delay * time_dilation
            
            amp_str$ = string$(lensing_amp)
            delay_str$ = string$(final_delay)
            
            selectObject: reverbLeft
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        endfor
    endfor
    
    # Process right (slightly different for decorrelation)
    selectObject: rightChannel
    Copy: "reverb_right"
    reverbRight = selected("Sound")
    
    for mass from 1 to mass_points
        # Offset mass positions for right channel
        mass_position = massPos[mass] + randomUniform(-0.05, 0.05)
        if mass_position < 0.03
            mass_position = 0.03
        elsif mass_position > 0.9
            mass_position = 0.9
        endif
        mass_strength = massStr[mass] * randomUniform(0.9, 1.1)
        
        for ray from 1 to rays_per_mass
            straight_delay = (ray_delay_start_s + 0.01) + ray * (ray_delay_increment_s - 0.005)
            distance_to_mass = abs(straight_delay - mass_position)
            bending = mass_strength / (distance_to_mass + 0.006)
            curved_delay = straight_delay + bending * (space_curvature * 0.95)
            lensing_amp = (lensing_amplitude * 0.9) / (1 + bending)
            
            dilation_arg = 1 - mass_strength * (time_dilation_factor * 1.1)
            if dilation_arg < 0.01
                dilation_arg = 0.01
            endif
            time_dilation = sqrt(dilation_arg)
            
            final_delay = curved_delay * time_dilation
            
            amp_str$ = string$(lensing_amp)
            delay_str$ = string$(final_delay)
            
            selectObject: reverbRight
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        endfor
    endfor
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: reverbLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: reverbRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: reverbLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.95
    
    selectObject: reverbRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.95
    
    # Combine
    selectObject: reverbLeft, reverbRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_gravitational_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, reverbLeft, reverbRight, extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "reverb_mono"
    reverbMono = selected("Sound")
    
    for mass from 1 to mass_points
        mass_position = massPos[mass]
        mass_strength = massStr[mass]
        
        for ray from 1 to rays_per_mass
            straight_delay = ray_delay_start_s + ray * ray_delay_increment_s
            distance_to_mass = abs(straight_delay - mass_position)
            bending = mass_strength / (distance_to_mass + 0.005)
            curved_delay = straight_delay + bending * space_curvature
            lensing_amp = lensing_amplitude / (1 + bending)
            
            dilation_arg = 1 - mass_strength * time_dilation_factor
            if dilation_arg < 0.01
                dilation_arg = 0.01
            endif
            time_dilation = sqrt(dilation_arg)
            
            final_delay = curved_delay * time_dilation
            
            amp_str$ = string$(lensing_amp)
            delay_str$ = string$(final_delay)
            
            selectObject: reverbMono
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        endfor
    endfor
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: reverbMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: reverbMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    Scale peak: 0.95
    Rename: originalName$ + "_gravitational_" + presetName$
    result = reverbMono
    
    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Gravitational Lens Reverb: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.5, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Lensed " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Mass point diagram (spacetime visualization)
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9
    
    maxDelay = ray_delay_start_s + rays_per_mass * ray_delay_increment_s * 2
    
    Axes: 0, maxDelay, 0, mass_points + 1
    Paint rectangle: "{0.1, 0.1, 0.15}", 0, maxDelay, 0, mass_points + 1
    
    # Draw rays and mass points
    for mass from 1 to min(mass_points, 15)
        y = mass
        mass_position = massPos[mass]
        mass_strength = massStr[mass]
        
        # Draw mass point (gravitational source)
        massSize = 0.02 + mass_strength * 0.015
        Colour: "{0.9, 0.7, 0.3}"
        Paint circle: "{0.9, 0.7, 0.3}", mass_position, y, massSize * maxDelay
        
        # Draw rays bending around mass
        Colour: "{0.4, 0.6, 0.9}"
        Line width: 1
        
        for ray from 1 to min(rays_per_mass, 6)
            straight_delay = ray_delay_start_s + ray * ray_delay_increment_s
            distance_to_mass = abs(straight_delay - mass_position)
            bending = mass_strength / (distance_to_mass + 0.005)
            curved_delay = straight_delay + bending * space_curvature
            
            # Draw bent ray path
            if curved_delay < maxDelay
                Draw line: 0, y + (ray - 3) * 0.1, curved_delay, y + (ray - 3) * 0.1
                # Arrow head
                Draw line: curved_delay - 0.01, y + (ray - 3) * 0.1 + 0.05, curved_delay, y + (ray - 3) * 0.1
                Draw line: curved_delay - 0.01, y + (ray - 3) * 0.1 - 0.05, curved_delay, y + (ray - 3) * 0.1
            endif
        endfor
    endfor
    
    Line width: 1
    Colour: "White"
    Draw inner box
    Font size: 6
    Colour: "White"
    Text left: "yes", "Mass #"
    Text bottom: "yes", "Delay (s)"
    
    # Legend
    Font size: 5
    Colour: "{0.9, 0.7, 0.3}"
    Text: maxDelay * 0.85, "centre", mass_points + 0.7, "half", "● Mass points"
    Colour: "{0.4, 0.6, 0.9}"
    Text: maxDelay * 0.85, "centre", mass_points + 0.3, "half", "→ Bent rays"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Masses: " + string$(mass_points) + " | Rays: " + string$(rays_per_mass) + "/mass | Curvature: " + fixed$(space_curvature, 2) + " | Dilation: " + fixed$(time_dilation_factor, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result