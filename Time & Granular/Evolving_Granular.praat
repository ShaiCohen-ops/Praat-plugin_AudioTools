# ============================================================
# Praat AudioTools - Evolving_Granular.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Stereo output (dual-pass with small differences)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Evolving Granular Synthesis - creates granular textures with
#   time-varying parameters. Three evolution modes:
#   - Density Growth: grain density increases over time
#   - Pitch Sweep: gradual pitch transposition
#   - Statistical Shift: 3 regions with different characteristics
#
# Changelog v0.4:
#   - Stereo output: each grain is placed in the left channel as-is and in
#     the right channel with small independent per-grain jitter (detune,
#     source position, timing). Same texture, decorrelated -> natural width.
#   - New Stereo_width control (0 = identical channels/mono, 1 = wide).
#   - Grain extract/pitch/mix refactored into a placeGrain procedure.
#
# Changelog v0.3:
#   - Fixed pitch shifting. The old Lengthen (overlap-add) call is a
#     pitch-PRESERVING time-stretch, so pitch never changed (and downward
#     shifts silently no-op'd via nocheck). Now uses Override sampling
#     frequency + Resample (varispeed), so Pitch Sweep and the Rising/
#     Falling presets actually shift pitch. Grain length scales by 1/factor.
#   - Visualization: title and legend set their own Axes so they center
#     correctly (legend no longer drifts/clips with input duration);
#     'Original' label aligned with 'Granular'.
#
# Changelog v0.2:
#   - Fixed object reference bugs
#   - Added input check
#   - Added evolution visualization
# ============================================================

form Evolving Granular
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Dense Cloud
        option Sparse Texture
        option Rising Pitch Sweep
        option Falling Pitch Sweep
        option Three Region Evolution
        option Gentle Growth
        option Extreme Density Build
        option Micro Grains
    
    comment === Grain Parameters (Custom only) ===
    real Initial_density 10.0
    real Final_density 25.0
    real Grain_duration_min 0.05
    real Grain_duration_max 0.15
    
    comment === Evolution ===
    optionmenu Evolution_type 1
        option Density growth
        option Pitch sweep
        option Statistical shift
    real Pitch_shift_semitones 7.0
    
    comment === Randomization ===
    real Position_randomness 0.3
    real Pitch_randomness 2.0
    real Amplitude_randomness 0.2
    
    comment === Stereo ===
    real Stereo_width 0.3
    comment (0 = mono, ~0.3 subtle, ~0.5 stereo, 1 = wide)
    
    comment === Options ===
    boolean Enable_pitch_shifting 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    initial_density = 20.0
    final_density = 40.0
    grain_duration_min = 0.04
    grain_duration_max = 0.10
    evolution_type = 1
    pitch_shift_semitones = 3.0
    position_randomness = 0.4
    pitch_randomness = 1.5
    amplitude_randomness = 0.25
    enable_pitch_shifting = 1
    preset_name$ = "DenseCloud"
elsif preset = 3
    initial_density = 5.0
    final_density = 12.0
    grain_duration_min = 0.08
    grain_duration_max = 0.20
    evolution_type = 1
    pitch_shift_semitones = 2.0
    position_randomness = 0.2
    pitch_randomness = 1.0
    amplitude_randomness = 0.15
    enable_pitch_shifting = 1
    preset_name$ = "SparseTexture"
elsif preset = 4
    initial_density = 15.0
    final_density = 30.0
    grain_duration_min = 0.05
    grain_duration_max = 0.12
    evolution_type = 2
    pitch_shift_semitones = 12.0
    position_randomness = 0.25
    pitch_randomness = 2.0
    amplitude_randomness = 0.20
    enable_pitch_shifting = 1
    preset_name$ = "RisingPitch"
elsif preset = 5
    initial_density = 15.0
    final_density = 30.0
    grain_duration_min = 0.05
    grain_duration_max = 0.12
    evolution_type = 2
    pitch_shift_semitones = -12.0
    position_randomness = 0.25
    pitch_randomness = 2.0
    amplitude_randomness = 0.20
    enable_pitch_shifting = 1
    preset_name$ = "FallingPitch"
elsif preset = 6
    initial_density = 18.0
    final_density = 35.0
    grain_duration_min = 0.03
    grain_duration_max = 0.15
    evolution_type = 3
    pitch_shift_semitones = 5.0
    position_randomness = 0.35
    pitch_randomness = 2.5
    amplitude_randomness = 0.25
    enable_pitch_shifting = 1
    preset_name$ = "ThreeRegion"
elsif preset = 7
    initial_density = 8.0
    final_density = 20.0
    grain_duration_min = 0.06
    grain_duration_max = 0.16
    evolution_type = 1
    pitch_shift_semitones = 2.0
    position_randomness = 0.15
    pitch_randomness = 1.0
    amplitude_randomness = 0.10
    enable_pitch_shifting = 1
    preset_name$ = "GentleGrowth"
elsif preset = 8
    initial_density = 10.0
    final_density = 60.0
    grain_duration_min = 0.03
    grain_duration_max = 0.08
    evolution_type = 1
    pitch_shift_semitones = 5.0
    position_randomness = 0.5
    pitch_randomness = 3.0
    amplitude_randomness = 0.30
    enable_pitch_shifting = 1
    preset_name$ = "ExtremeDensity"
elsif preset = 9
    initial_density = 30.0
    final_density = 50.0
    grain_duration_min = 0.02
    grain_duration_max = 0.05
    evolution_type = 1
    pitch_shift_semitones = 7.0
    position_randomness = 0.3
    pitch_randomness = 4.0
    amplitude_randomness = 0.25
    enable_pitch_shifting = 0
    preset_name$ = "MicroGrains"
else
    preset_name$ = "Custom"
endif

# === Get Evolution Type Name ===
if evolution_type = 1
    evolution_name$ = "Density Growth"
elsif evolution_type = 2
    evolution_name$ = "Pitch Sweep"
else
    evolution_name$ = "Statistical Shift"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

originalSound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: originalSound
duration = Get total duration
sampling_rate = Get sampling frequency
n_channels = Get number of channels

# Convert to mono if stereo (keep original for visualization)
if n_channels > 1
    selectObject: originalSound
    Convert to mono
    sourceSound = selected("Sound")
else
    sourceSound = originalSound
endif

# === Info ===
writeInfoLine: "=== Evolving Granular ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Evolution: ", evolution_name$
appendInfoLine: ""

# Calculate total number of grains
avg_density = (initial_density + final_density) / 2
total_grains = round(avg_density * duration)

# Safety limit
if total_grains > 500
    total_grains = 500
endif

appendInfoLine: "Grains: ", total_grains
appendInfoLine: "Density: ", fixed$(initial_density, 1), " -> ", fixed$(final_density, 1), " /sec"
appendInfoLine: ""

# ===================================================================
# PRE-COMPUTE GRAIN PARAMETERS
# ===================================================================

appendInfoLine: "Generating grain parameters..."

# Initialize arrays
for grain to total_grains
    grainSourcePos[grain] = 0
    grainOutputPos[grain] = 0
    grainDur[grain] = -1
    grainPitchShift[grain] = 0
    grainAmp[grain] = 0
endfor

# Generate parameters based on evolution type
for grain to total_grains
    normalized_time = (grain - 1) / total_grains
    
    if evolution_type = 1
        # Density Growth
        current_density = initial_density + (final_density - initial_density) * normalized_time
        grain_center = normalized_time * duration + position_randomness * randomGauss(0, 1)
        gDur = grain_duration_min + (grain_duration_max - grain_duration_min) * randomUniform(0, 1)
        grain_start = grain_center - gDur / 2
        
        time_probability = current_density / ((initial_density + final_density) / 2)
        
        if randomUniform(0, 1) < time_probability and grain_start >= 0 and grain_start + gDur <= duration
            source_pos = grain_start + position_randomness * randomGauss(0, 0.5)
            source_pos = max(0, min(duration - gDur, source_pos))
            pShift = pitch_randomness * randomGauss(0, 1)
            amp_factor = 1 + amplitude_randomness * randomGauss(0, 1)
            amp_factor = max(0.3, min(1.5, amp_factor))
            
            grainSourcePos[grain] = source_pos
            grainOutputPos[grain] = grain_start
            grainDur[grain] = gDur
            grainPitchShift[grain] = pShift
            grainAmp[grain] = amp_factor
        endif
        
    elsif evolution_type = 2
        # Pitch Sweep
        grain_center = randomUniform(0, duration)
        normalized_time = grain_center / duration
        gDur = grain_duration_min + (grain_duration_max - grain_duration_min) * randomUniform(0, 1)
        grain_start = grain_center - gDur / 2
        
        if grain_start >= 0 and grain_start + gDur <= duration
            current_pitch_shift = pitch_shift_semitones * normalized_time
            pShift = current_pitch_shift + pitch_randomness * randomGauss(0, 1)
            source_pos = grain_start + position_randomness * randomGauss(0, 0.3)
            source_pos = max(0, min(duration - gDur, source_pos))
            amp_factor = (1.2 - normalized_time * 0.4) + amplitude_randomness * randomGauss(0, 1)
            amp_factor = max(0.3, min(1.5, amp_factor))
            
            grainSourcePos[grain] = source_pos
            grainOutputPos[grain] = grain_start
            grainDur[grain] = gDur
            grainPitchShift[grain] = pShift
            grainAmp[grain] = amp_factor
        endif
        
    else
        # Statistical Shift (3 regions)
        grain_center = randomUniform(0, duration)
        normalized_time = grain_center / duration
        
        if normalized_time < 0.33
            gDur = 0.08 + 0.1 * randomUniform(0, 1)
            pShift = -4 + pitch_randomness * randomGauss(0, 1)
            amp_factor = 0.9 + amplitude_randomness * randomGauss(0, 1)
        elsif normalized_time < 0.66
            gDur = 0.04 + 0.06 * randomUniform(0, 1)
            pShift = 2 + pitch_randomness * 1.5 * randomGauss(0, 1)
            amp_factor = 0.7 + amplitude_randomness * randomGauss(0, 1)
        else
            gDur = 0.02 + 0.04 * randomUniform(0, 1)
            pShift = 8 + pitch_randomness * 2 * randomGauss(0, 1)
            amp_factor = 0.5 + amplitude_randomness * randomGauss(0, 1)
        endif
        
        grain_start = grain_center - gDur / 2
        
        if grain_start >= 0 and grain_start + gDur <= duration
            source_pos = grain_start + position_randomness * randomGauss(0, 0.5)
            source_pos = max(0, min(duration - gDur, source_pos))
            amp_factor = max(0.2, min(1.3, amp_factor))
            
            grainSourcePos[grain] = source_pos
            grainOutputPos[grain] = grain_start
            grainDur[grain] = gDur
            grainPitchShift[grain] = pShift
            grainAmp[grain] = amp_factor
        endif
    endif
endfor

# Per-channel stereo decorrelation amounts (small differences)
stereo_detune_st = stereo_width * 0.06
stereo_pos_jit_s = stereo_width * 0.002
stereo_time_jit_s = stereo_width * 0.0005

appendInfoLine: "Synthesizing grains..."

# ===================================================================
# GRAIN SYNTHESIS
# ===================================================================

# Stereo output: two channels from the same grain plan, with small independent
# per-grain differences (detune / source-position / timing) so the sides are the
# same texture but decorrelated. Stereo_width scales it (0 = identical = mono).
Create Sound from formula: sound_name$ + "_granular", 2, 0, duration, sampling_rate, "0"
outputSound = selected("Sound")

valid_grains = 0
progressStep = max(1, floor(total_grains / 10))

for grain to total_grains
    gDur = grainDur[grain]
    
    # Skip invalid grains (marked with negative duration)
    if gDur > 0
        source_pos = grainSourcePos[grain]
        grain_start = grainOutputPos[grain]
        pShift = grainPitchShift[grain]
        amp_factor = grainAmp[grain]
        
        # Left channel: base grain
        @placeGrain: 1, source_pos, grain_start, pShift, amp_factor, gDur
        
        # Right channel: same grain, small independent differences
        srcR = source_pos + stereo_pos_jit_s * randomGauss(0, 1)
        srcR = max(0, min(duration - gDur, srcR))
        startR = grain_start + stereo_time_jit_s * randomGauss(0, 1)
        if startR < 0
            startR = 0
        endif
        pShiftR = pShift + stereo_detune_st * randomGauss(0, 1)
        @placeGrain: 2, srcR, startR, pShiftR, amp_factor, gDur
        
        valid_grains += 1
    endif
    
    if grain mod progressStep = 0
        appendInfoLine: "  ", floor(grain / total_grains * 100), "%"
    endif
endfor

# ===================================================================
# FINALIZE
# ===================================================================

selectObject: outputSound
Scale peak: 0.95
Rename: sound_name$ + "_" + preset_name$

# ===================================================================
# VISUALIZATION WITH EVOLUTION PLOTS
# ===================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Evolving Granular: " + sound_name$ + " (" + preset_name$ + " - " + evolution_name$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: originalSound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    selectObject: outputSound
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Granular"
    Text bottom: "yes", "Time (s)"
    
    # === EVOLUTION PLOTS ===
    
    # Find min/max for pitch and duration
    minPitch = 0
    maxPitch = 0
    minDur = 1
    maxDur = 0
    for grain to total_grains
        if grainDur[grain] > 0
            if grainPitchShift[grain] < minPitch
                minPitch = grainPitchShift[grain]
            endif
            if grainPitchShift[grain] > maxPitch
                maxPitch = grainPitchShift[grain]
            endif
            if grainDur[grain] < minDur
                minDur = grainDur[grain]
            endif
            if grainDur[grain] > maxDur
                maxDur = grainDur[grain]
            endif
        endif
    endfor
    
    # Add margins
    pitchRange = maxPitch - minPitch
    if pitchRange < 1
        pitchRange = 1
    endif
    minPitch = minPitch - pitchRange * 0.1
    maxPitch = maxPitch + pitchRange * 0.1
    
    durRange = maxDur - minDur
    if durRange < 0.01
        durRange = 0.01
    endif
    minDur = max(0, minDur - durRange * 0.1)
    maxDur = maxDur + durRange * 0.1
    
    # --- Pitch Evolution Plot ---
    Select outer viewport: 0, 4, 3.3, 4.8
    Select inner viewport: 0.6, 3.8, 3.5, 4.7
    
    Axes: 0, duration, minPitch, maxPitch
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minPitch, maxPitch
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line
    
    # Draw grains as dots (color by pitch)
    for grain to total_grains
        if grainDur[grain] > 0
            gTime = grainOutputPos[grain]
            gPitch = grainPitchShift[grain]
            
            # Color: blue for negative, red for positive pitch
            if gPitch < 0
                colorVal = min(1, abs(gPitch) / 12)
                dotColor$ = "{" + fixed$(0.2, 2) + ", " + fixed$(0.3, 2) + ", " + fixed$(0.5 + colorVal * 0.5, 2) + "}"
            else
                colorVal = min(1, gPitch / 12)
                dotColor$ = "{" + fixed$(0.5 + colorVal * 0.5, 2) + ", " + fixed$(0.3, 2) + ", " + fixed$(0.2, 2) + "}"
            endif
            
            Paint circle (mm): dotColor$, gTime, gPitch, 0.4
        endif
    endfor
    
    # Trend line for pitch sweep
    if evolution_type = 2
        Colour: "{0.8, 0.2, 0.2}"
        Line width: 2
        Draw line: 0, 0, duration, pitch_shift_semitones
        Line width: 1
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (st)"
    Text bottom: "yes", "Time (s)"
    
    # --- Duration Evolution Plot ---
    Select outer viewport: 4, 8, 3.3, 4.8
    Select inner viewport: 4.4, 7.6, 3.5, 4.7
    
    Axes: 0, duration, minDur * 1000, maxDur * 1000
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minDur * 1000, maxDur * 1000
    
    # Draw grains as dots (color by duration)
    for grain to total_grains
        if grainDur[grain] > 0
            gTime = grainOutputPos[grain]
            gDurMs = grainDur[grain] * 1000
            
            # Color: short=yellow, long=purple
            normalizedDur = (grainDur[grain] - minDur) / durRange
            dotColor$ = "{" + fixed$(0.8 - normalizedDur * 0.3, 2) + ", " + fixed$(0.6 - normalizedDur * 0.3, 2) + ", " + fixed$(0.2 + normalizedDur * 0.6, 2) + "}"
            
            Paint circle (mm): dotColor$, gTime, gDurMs, 0.4
        endif
    endfor
    
    # Region markers for statistical shift
    if evolution_type = 3
        Colour: "{0.5, 0.5, 0.5}"
        Dotted line
        Draw line: duration * 0.33, minDur * 1000, duration * 0.33, maxDur * 1000
        Draw line: duration * 0.66, minDur * 1000, duration * 0.66, maxDur * 1000
        Solid line
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dur (ms)"
    Text bottom: "yes", "Time (s)"
    
    # --- Density Plot (grains per time bin) ---
    Select outer viewport: 0, 4, 5.0, 6.2
    Select inner viewport: 0.6, 3.8, 5.2, 6.1
    
    # Calculate density in time bins
    numBins = 20
    binWidth = duration / numBins
    maxBinCount = 0
    
    for bin to numBins
        binCount[bin] = 0
    endfor
    
    for grain to total_grains
        if grainDur[grain] > 0
            binIdx = floor(grainOutputPos[grain] / binWidth) + 1
            if binIdx < 1
                binIdx = 1
            endif
            if binIdx > numBins
                binIdx = numBins
            endif
            binCount[binIdx] = binCount[binIdx] + 1
        endif
    endfor
    
    for bin to numBins
        if binCount[bin] > maxBinCount
            maxBinCount = binCount[bin]
        endif
    endfor
    
    if maxBinCount < 1
        maxBinCount = 1
    endif
    
    Axes: 0, duration, 0, maxBinCount * 1.1
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, maxBinCount * 1.1
    
    # Draw density bars
    for bin to numBins
        binStart = (bin - 1) * binWidth
        binEnd = bin * binWidth - binWidth * 0.1
        
        # Color gradient based on density
        normalizedCount = binCount[bin] / maxBinCount
        barColor$ = "{" + fixed$(0.3 + normalizedCount * 0.5, 2) + ", " + fixed$(0.7 - normalizedCount * 0.2, 2) + ", " + fixed$(0.3, 2) + "}"
        
        Paint rectangle: barColor$, binStart, binEnd, 0, binCount[bin]
    endfor
    
    # Trend line for density growth
    if evolution_type = 1
        Colour: "{0.2, 0.6, 0.2}"
        Line width: 2
        startDensity = initial_density * binWidth
        endDensity = final_density * binWidth
        Draw line: 0, startDensity, duration, endDensity
        Line width: 1
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Count"
    Text bottom: "yes", "Time (s)"
    
    # --- Amplitude Plot ---
    Select outer viewport: 4, 8, 5.0, 6.2
    Select inner viewport: 4.4, 7.6, 5.2, 6.1
    
    Axes: 0, duration, 0, 1.6
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1.6
    
    # Reference line at 1.0
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 1.0, duration, 1.0
    Solid line
    
    # Draw grains as dots
    for grain to total_grains
        if grainDur[grain] > 0
            gTime = grainOutputPos[grain]
            gAmp = grainAmp[grain]
            
            # Color: darker = louder
            dotColor$ = "{" + fixed$(0.8 - gAmp * 0.3, 2) + ", " + fixed$(0.5 - gAmp * 0.2, 2) + ", " + fixed$(0.2, 2) + "}"
            
            Paint circle (mm): dotColor$, gTime, gAmp, 0.4
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 6.3, 6.6
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Grains: " + string$(valid_grains) + "/" + string$(total_grains) + " | Density: " + fixed$(initial_density, 0) + " -> " + fixed$(final_density, 0) + "/s | Pitch: " + fixed$(minPitch, 1) + " to " + fixed$(maxPitch, 1) + " st"
    
    Font size: 10
    Colour: "Black"
endif

# Clean up mono conversion if created
if n_channels > 1
    removeObject: sourceSound
endif

# === Final Info ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Valid grains: ", valid_grains, "/", total_grains
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound


# ===================================================================
# GRAIN PLACEMENT (one grain -> one output channel)
# ===================================================================
procedure placeGrain: .chan, .srcPos, .gStart, .pShift, .amp, .gDur
    selectObject: sourceSound
    Extract part: .srcPos, .srcPos + .gDur, "Hanning", 1, "no"
    .gx = selected("Sound")

    .pf = 2 ^ (.pShift / 12)
    if enable_pitch_shifting and abs(.pf - 1) > 0.02
        selectObject: .gx
        Override sampling frequency: sampling_rate * .pf
        Resample: sampling_rate, 50
        .gs = selected("Sound")
        removeObject: .gx
        .gx = .gs
    endif

    selectObject: .gx
    Formula: "self * " + string$(.amp)
    .actualDur = Get total duration
    .gEnd = .gStart + .actualDur
    if .gEnd > duration
        .gEnd = duration
    endif
    .gxID$ = string$(.gx)
    .gStart$ = fixed$(.gStart, 6)
    selectObject: outputSound
    Formula (part): .gStart, .gEnd, .chan, .chan, "self + object(" + .gxID$ + ", x - " + .gStart$ + ")"
    removeObject: .gx
endproc
