# ============================================================
# Praat AudioTools - Gravitational_Lens_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
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
# Changelog v1.0:
#   - Fixed amplitude lensing: rays near mass now AMPLIFY (like real lensing)
#   - Added exponential decay for natural reverb tail
#   - Added early reflections cluster for improved density
#   - Refactored with procedures (reduced code repetition)
#   - Enhanced visualization with time dilation field
#   - Added ray statistics to info output
# ============================================================

form Gravitational Lens Reverb v1.0
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Lensing
        option Medium Lensing
        option Heavy Lensing
        option Extreme Lensing
        option Black Hole (experimental)
    
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
    
    comment === Decay & Early Reflections ===
    positive Decay_rate 1.5
    natural Early_reflections 8
    positive Early_reflection_density 0.008
    
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
    decay_rate = 1.8
    early_reflections = 6
    early_reflection_density = 0.01
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
    decay_rate = 1.5
    early_reflections = 8
    early_reflection_density = 0.008
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
    decay_rate = 1.2
    early_reflections = 10
    early_reflection_density = 0.006
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
    decay_rate = 1.0
    early_reflections = 12
    early_reflection_density = 0.005
    fadeout_duration_s = 1.8
    presetName$ = "Extreme"
elsif preset = 6
    # Black Hole (experimental - event horizon effects)
    tail_duration_s = 10.0
    mass_points = 8
    rays_per_mass = 20
    space_curvature = 2.5
    mass_strength_mean = 3.0
    mass_strength_stddev = 0.5
    ray_delay_start_s = 0.02
    ray_delay_increment_s = 0.03
    lensing_amplitude = 0.3
    time_dilation_factor = 0.35
    decay_rate = 0.6
    early_reflections = 15
    early_reflection_density = 0.004
    fadeout_duration_s = 2.5
    presetName$ = "BlackHole"
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

# Pre-generate mass positions (shared between channels for consistency)
for m from 1 to mass_points
    massPos[m] = randomUniform(0.03, 0.9)
    massStr[m] = randomGauss(mass_strength_mean, mass_strength_stddev)
    if massStr[m] < 0.1
        massStr[m] = 0.1
    endif
endfor

totalRays = mass_points * rays_per_mass

# === Info ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  GRAVITATIONAL LENS REVERB v1.0"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""
writeInfoLine: "=== Spacetime Configuration ==="
writeInfoLine: "  Mass points: ", mass_points
writeInfoLine: "  Rays per mass: ", rays_per_mass
writeInfoLine: "  Total rays: ", totalRays
writeInfoLine: "  Space curvature: ", fixed$(space_curvature, 2)
writeInfoLine: "  Time dilation factor: ", fixed$(time_dilation_factor, 2)
writeInfoLine: "  Decay rate: ", fixed$(decay_rate, 2)
writeInfoLine: "  Early reflections: ", early_reflections
writeInfoLine: ""
writeInfoLine: "=== Mass Distribution ==="
for m from 1 to min(5, mass_points)
    writeInfoLine: "  Mass ", m, ": pos=", fixed$(massPos[m], 3), "s strength=", fixed$(massStr[m], 2)
endfor
if mass_points > 5
    writeInfoLine: "  ... (", mass_points - 5, " more)"
endif
writeInfoLine: ""
writeInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
writeInfoLine: ""

# ============================================================
# PROCEDURES
# ============================================================

procedure applyEarlyReflections: .sound
    # Adds tight early reflections for initial density
    # These simulate the first wave of reflections before diffuse tail
    
    appendInfoLine: "  Adding ", early_reflections, " early reflections..."
    
    for .er from 1 to early_reflections
        .er_delay = 0.008 + .er * early_reflection_density
        # Amplitude decreases with reflection number (1/sqrt for natural decay)
        .er_amp = 0.12 / sqrt(.er)
        # Slight randomization for organic feel
        .er_delay = .er_delay * randomUniform(0.9, 1.1)
        
        selectObject: .sound
        Formula: ~ self + .er_amp * self(x - .er_delay)
    endfor
endproc


procedure processGravitationalRays: .sound, .channelOffset
    # Main ray processing with gravitational lensing
    # .channelOffset provides slight variation for stereo decorrelation
    
    .totalProcessed = 0
    .minDelay = 999
    .maxDelay = 0
    .totalAmp = 0
    
    for .mass from 1 to mass_points
        # Apply channel offset for stereo decorrelation
        .mass_position = massPos[.mass] + .channelOffset * randomUniform(-0.03, 0.03)
        if .mass_position < 0.02
            .mass_position = 0.02
        elsif .mass_position > 0.95
            .mass_position = 0.95
        endif
        
        .mass_strength = massStr[.mass] * (1 + .channelOffset * randomUniform(-0.1, 0.1))
        
        for .ray from 1 to rays_per_mass
            # Base delay (straight-line propagation)
            .straight_delay = ray_delay_start_s + .ray * ray_delay_increment_s
            
            # === GRAVITATIONAL BENDING ===
            # Rays passing closer to mass are bent more
            .distance_to_mass = abs(.straight_delay - .mass_position)
            .bending = .mass_strength / (.distance_to_mass + 0.005)
            
            # Curved delay = straight + bending effect
            .curved_delay = .straight_delay + .bending * space_curvature
            
            # === GRAVITATIONAL LENSING AMPLITUDE ===
            # In real lensing, rays near mass are AMPLIFIED (not attenuated)
            # This is the key fix from v0.2
            .lensing_amp = lensing_amplitude * (1 + .bending * 0.15)
            
            # Clamp to prevent excessive amplification
            if .lensing_amp > 0.35
                .lensing_amp = 0.35
            endif
            
            # === EXPONENTIAL DECAY ===
            # Natural reverb decay based on delay time
            .decay = exp(-.curved_delay * decay_rate)
            .lensing_amp = .lensing_amp * .decay
            
            # === TIME DILATION ===
            # Schwarzschild-inspired: time slows near mass
            # sqrt(1 - rs/r) where rs is Schwarzschild radius analog
            .dilation_arg = 1 - .mass_strength * time_dilation_factor
            if .dilation_arg < 0.01
                .dilation_arg = 0.01
            endif
            .time_dilation = sqrt(.dilation_arg)
            
            # Final delay with time dilation applied
            .final_delay = .curved_delay * .time_dilation
            
            # Apply to sound
            if .lensing_amp > 0.001 and .final_delay > 0.001
                selectObject: .sound
                Formula: ~ self + .lensing_amp * self(x - .final_delay)
                
                .totalProcessed += 1
                .totalAmp += .lensing_amp
                if .final_delay < .minDelay
                    .minDelay = .final_delay
                endif
                if .final_delay > .maxDelay
                    .maxDelay = .final_delay
                endif
            endif
        endfor
    endfor
    
    # Store statistics for info output
    processGravitationalRays.processed = .totalProcessed
    processGravitationalRays.minDelay = .minDelay
    processGravitationalRays.maxDelay = .maxDelay
    processGravitationalRays.avgAmp = .totalAmp / (.totalProcessed + 0.001)
endproc


procedure applyWetDryMix: .wetSound, .drySound
    # Applies wet/dry mix
    
    if dry_level > 0.001
        selectObject: .wetSound
        Formula: ~ self * wet_level + object[.drySound] * dry_level
    endif
endproc


procedure applyFadeout: .sound, .totalDur
    # Applies smooth cosine fadeout
    
    .fade_start = .totalDur - fadeout_duration_s
    
    selectObject: .sound
    Formula: ~ if x > .fade_start then self * (0.5 + 0.5 * cos(pi * (x - .fade_start) / fadeout_duration_s)) else self fi
endproc


# ============================================================
# MAIN PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Create silent tail
if numChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sr, "0"
endif
silentTail = selected("Sound")

# Concatenate original with tail
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

totalDur = originalDur + tail_duration_s

if numChannels = 2
    # ============================================================
    # STEREO PROCESSING
    # ============================================================
    
    appendInfoLine: "  Processing stereo channels..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # === LEFT CHANNEL ===
    selectObject: leftChannel
    Copy: "reverb_left"
    reverbLeft = selected("Sound")
    
    appendInfoLine: "  Left channel:"
    @applyEarlyReflections: reverbLeft
    @processGravitationalRays: reverbLeft, 0
    appendInfoLine: "    Rays processed: ", processGravitationalRays.processed
    appendInfoLine: "    Delay range: ", fixed$(processGravitationalRays.minDelay, 3), " - ", fixed$(processGravitationalRays.maxDelay, 3), " s"
    
    # === RIGHT CHANNEL ===
    selectObject: rightChannel
    Copy: "reverb_right"
    reverbRight = selected("Sound")
    
    appendInfoLine: "  Right channel:"
    @applyEarlyReflections: reverbRight
    @processGravitationalRays: reverbRight, 1
    appendInfoLine: "    Rays processed: ", processGravitationalRays.processed
    appendInfoLine: "    Delay range: ", fixed$(processGravitationalRays.minDelay, 3), " - ", fixed$(processGravitationalRays.maxDelay, 3), " s"
    
    # Apply wet/dry mix
    @applyWetDryMix: reverbLeft, leftChannel
    @applyWetDryMix: reverbRight, rightChannel
    
    # Apply fadeout
    @applyFadeout: reverbLeft, totalDur
    @applyFadeout: reverbRight, totalDur
    
    # Normalize
    selectObject: reverbLeft
    Scale peak: 0.95
    
    selectObject: reverbRight
    Scale peak: 0.95
    
    # Combine to stereo
    selectObject: reverbLeft, reverbRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_gravitational_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, reverbLeft, reverbRight, extendedSound

else
    # ============================================================
    # MONO PROCESSING
    # ============================================================
    
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "reverb_mono"
    reverbMono = selected("Sound")
    
    @applyEarlyReflections: reverbMono
    @processGravitationalRays: reverbMono, 0
    
    appendInfoLine: "  Rays processed: ", processGravitationalRays.processed
    appendInfoLine: "  Delay range: ", fixed$(processGravitationalRays.minDelay, 3), " - ", fixed$(processGravitationalRays.maxDelay, 3), " s"
    appendInfoLine: "  Avg amplitude: ", fixed$(processGravitationalRays.avgAmp, 4)
    
    # Apply wet/dry mix
    @applyWetDryMix: reverbMono, extendedSound
    
    # Apply fadeout
    @applyFadeout: reverbMono, totalDur
    
    # Normalize
    selectObject: reverbMono
    Scale peak: 0.95
    Rename: originalName$ + "_gravitational_" + presetName$
    result = reverbMono
    
    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.85, "half", "##Gravitational Lens Reverb##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  " + string$(mass_points) + " masses × "
        ... + string$(rays_per_mass) + " rays"
        ... + "  |  Wet=" + fixed$(wet_dry_percent, 0) + "%"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: result
    Colour: "{0.38, 0.50, 0.72}"
    Draw: 0, totalDur, 0, 0, "no", "Curve"

    # Mark original duration
    Colour: "{0.82, 0.30, 0.30}"
    Dotted line
    Draw line: originalDur, -1, originalDur, 1
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)  — dotted = original end"

    # ----------------------------------------------------------
    # Spacetime diagram
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.24, 4.34
    Select inner viewport: 0.55, 7.65, 2.32, 4.24

    maxDelay = ray_delay_start_s + rays_per_mass * ray_delay_increment_s * 2.5
    if maxDelay < 0.5
        maxDelay = 0.5
    endif

    Axes: 0, maxDelay, 0, mass_points + 1

    # Time dilation field (background gradient)
    numGridX = 40
    numGridY = 20

    for gx from 1 to numGridX
        for gy from 1 to numGridY
            xPos = (gx - 0.5) / numGridX * maxDelay
            yPos = (gy - 0.5) / numGridY * (mass_points + 1)

            localDilation = 1
            for m from 1 to mass_points
                dist = sqrt((xPos - massPos[m])^2 + ((yPos - m) / mass_points * maxDelay)^2)
                if dist < 0.01
                    dist = 0.01
                endif
                dilArg = 1 - massStr[m] * time_dilation_factor * 0.3 / (dist + 0.1)
                if dilArg < 0.1
                    dilArg = 0.1
                endif
                localDilation = localDilation * sqrt(dilArg)
            endfor

            grey = 0.08 + localDilation * 0.07
            if grey > 0.18
                grey = 0.18
            endif

            cellW = maxDelay / numGridX
            cellH = (mass_points + 1) / numGridY

            Paint rectangle: "{" + fixed$(grey, 2) + "," + fixed$(grey, 2) + "," + fixed$(grey + 0.02, 2) + "}",
                ... xPos - cellW/2, xPos + cellW/2,
                ... yPos - cellH/2, yPos + cellH/2
        endfor
    endfor

    # Draw rays and mass points
    for mass from 1 to min(mass_points, 15)
        y = mass
        mass_position = massPos[mass]
        mass_strength = massStr[mass]

        # Draw rays
        for ray from 1 to min(rays_per_mass, 8)
            straight_delay = ray_delay_start_s + ray * ray_delay_increment_s
            distance_to_mass = abs(straight_delay - mass_position)
            bending = mass_strength / (distance_to_mass + 0.005)
            curved_delay = straight_delay + bending * space_curvature

            lensing_amp = lensing_amplitude * (1 + bending * 0.15)
            if lensing_amp > 0.35
                lensing_amp = 0.35
            endif
            decay = exp(-curved_delay * decay_rate)
            finalAmp = lensing_amp * decay

            rayBright = 0.3 + finalAmp * 2
            if rayBright > 0.9
                rayBright = 0.9
            endif

            Colour: "{" + fixed$(rayBright * 0.5, 2) + "," + fixed$(rayBright * 0.7, 2) + "," + fixed$(rayBright, 2) + "}"
            Line width: 0.5 + finalAmp * 4

            if curved_delay < maxDelay
                rayY = y + (ray - rays_per_mass/2) * 0.08
                Draw line: 0, rayY, curved_delay, rayY
                Draw line: curved_delay - 0.015, rayY + 0.06, curved_delay, rayY
                Draw line: curved_delay - 0.015, rayY - 0.06, curved_delay, rayY
            endif
        endfor

        # Mass point — Paint circle (mm) avoids axis-scale distortion
        # and prevents overflow since size is in viewport millimeters
        massMM = 1.5 + mass_strength * 1.2
        if massMM > 5
            massMM = 5
        endif
        glowMM = massMM * 1.5

        # Glow
        Paint circle (mm): "{0.40, 0.30, 0.15}", mass_position, y, glowMM
        # Core
        Paint circle (mm): "{0.95, 0.75, 0.30}", mass_position, y, massMM
    endfor

    Line width: 1
    Colour: "{0.60, 0.60, 0.60}"
    Draw inner box

    Font size: 7
    Colour: "{0.70, 0.70, 0.70}"
    Text left: "yes", "Mass #"
    Text bottom: "yes", "Delay (s)"
    Text top: "no", "Spacetime diagram  (dilation field + bent rays + mass points)"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.42, 5.32
    Select inner viewport: 0.55, 7.65, 4.48, 5.26
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.55, "half",
        ... "Masses: " + string$(mass_points)
        ... + "  |  Rays/mass: " + string$(rays_per_mass)
        ... + "  |  Total rays: " + string$(totalRays)
        ... + "  |  Curvature: " + fixed$(space_curvature, 2)
        ... + "  |  Dilation: " + fixed$(time_dilation_factor, 2)
        ... + "  |  Decay: " + fixed$(decay_rate, 2)
    Text: 0.02, "left", 0.22, "half",
        ... "Tail: " + fixed$(tail_duration_s, 1) + " s"
        ... + "  |  Early refl: " + string$(early_reflections)
        ... + "  |  Fadeout: " + fixed$(fadeout_duration_s, 1) + " s"
        ... + "  |  Wet/Dry: " + fixed$(wet_dry_percent, 0) + "%"

    # Legend symbols inline
    Colour: "{0.95, 0.75, 0.30}"
    Paint circle (mm): "{0.95, 0.75, 0.30}", 0.72, 0.82, 1.2
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.74, "left", 0.82, "half", "= mass"
    Colour: "{0.35, 0.55, 0.85}"
    Line width: 2
    Draw line: 0.85, 0.82, 0.89, 0.82
    Line width: 1
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.90, "left", 0.82, "half", "= ray"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete"
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(totalDur, 2), " s (original: ", fixed$(originalDur, 2), " s)"
appendInfoLine: ""

if play_result
    appendInfoLine: "Playing..."
    Play
endif

appendInfoLine: "Done!"

selectObject: result