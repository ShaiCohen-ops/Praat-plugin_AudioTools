# ============================================================
# Praat AudioTools - Granular_Particle_Field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Particle Field Renderer - granular synthesis with spatial
#   and temporal control. Creates stereo particle clouds from
#   source audio with envelope shaping, pitch variation,
#   panning, and LFO modulation.
#
# Changelog v0.3:
#   - Fixed pitch shift: was Resample (preserves pitch -> no-op); now
#     Override sampling frequency (varispeed) which actually shifts pitch
#     and changes grain length. Mild aliasing possible on up-shifts.
#   - Header filename corrected to Granular_Particle_Field.praat.
#   - Viz legend drawn in normalized axes (was inheriting panel axes).
#   - Viz: particle dots enlarged (diameter was 0.5 mm ~ invisible); now
#     2-4 mm, scaled by grain amplitude.
#   - Perf note: mixing cost is O(grains x output-samples) - each grain
#     runs two whole-buffer Formula passes; the v0.2 "O(n)" note was
#     inaccurate. Correct but heavy for dense clouds / long outputs.
#
# Changelog v0.2:
#   - Fixed Formula interpolation
#   - Added visualization
# ============================================================

form Particle Field Renderer
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Dense Cloud
        option Sparse Field
        option Rhythmic Pulse
        option Shimmer
        option Long Resonance
    
    comment === Grains ===
    integer Number_of_grains 100
    real Grain_duration_s 0.050
    optionmenu Envelope_shape 1
        option Hann
        option Gaussian
        option Rectangular
    
    comment === Pitch ===
    boolean Apply_pitch_shift 0
    real Pitch_shift_semitones 0.0
    real Pitch_variation_semitones 0.0
    
    comment === Panning ===
    optionmenu Panning_mode 1
        option Position-derived
        option Random
        option Fixed
    real Fixed_pan 0.5
    
    comment === Modulation ===
    boolean Apply_LFO 0
    real LFO_frequency 0.5
    
    comment === Distribution ===
    optionmenu Time_distribution 1
        option Linear
        option Exponential
        option Random
    optionmenu Grain_source 1
        option Sequential
        option Random
    
    comment === Output ===
    real Output_duration_s 0.0
    comment (0 = use input duration)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Dense Cloud
    number_of_grains = 300
    grain_duration_s = 0.030
    envelope_shape = 2
    panning_mode = 2
    apply_LFO = 0
    time_distribution = 3
    grain_source = 2
    apply_pitch_shift = 0
elsif preset = 3
    # Sparse Field
    number_of_grains = 30
    grain_duration_s = 0.150
    envelope_shape = 1
    panning_mode = 1
    apply_LFO = 0
    time_distribution = 1
    grain_source = 1
    apply_pitch_shift = 0
elsif preset = 4
    # Rhythmic Pulse
    number_of_grains = 80
    grain_duration_s = 0.040
    envelope_shape = 3
    panning_mode = 3
    fixed_pan = 0.5
    apply_LFO = 1
    lFO_frequency = 4.0
    time_distribution = 1
    grain_source = 1
    apply_pitch_shift = 0
elsif preset = 5
    # Shimmer
    number_of_grains = 150
    grain_duration_s = 0.060
    envelope_shape = 2
    panning_mode = 2
    apply_LFO = 1
    lFO_frequency = 0.25
    time_distribution = 2
    grain_source = 2
    apply_pitch_shift = 1
    pitch_shift_semitones = 0
    pitch_variation_semitones = 7.0
elsif preset = 6
    # Long Resonance
    number_of_grains = 15
    grain_duration_s = 0.800
    envelope_shape = 1
    panning_mode = 1
    apply_LFO = 1
    lFO_frequency = 0.15
    time_distribution = 2
    grain_source = 2
    apply_pitch_shift = 1
    pitch_shift_semitones = 0
    pitch_variation_semitones = 3.0
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

# === Validate ===
if grain_duration_s <= 0
    exitScript: "Grain duration must be > 0"
endif
if fixed_pan < 0 or fixed_pan > 1
    exitScript: "Fixed pan must be 0-1"
endif
if lFO_frequency <= 0 and apply_LFO
    exitScript: "LFO frequency must be > 0"
endif

# === Get Input ===
original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
inputDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# Output duration
if output_duration_s > 0
    outDur = output_duration_s
else
    outDur = inputDuration
endif

# === Info ===
writeInfoLine: "=== Particle Field Renderer ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(inputDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Grains: ", number_of_grains
appendInfoLine: "Duration: ", fixed$(grain_duration_s * 1000, 1), " ms"
appendInfoLine: "Output: ", fixed$(outDur, 2), " s"
appendInfoLine: ""

# === Convert to Mono for Processing ===
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "source_mono"
    sourceSound = selected("Sound")
endif

# === Create Stereo Output Buffer ===
Create Sound from formula: "mixL", 1, 0, outDur, sampleRate, "0"
mixL = selected("Sound")

Create Sound from formula: "mixR", 1, 0, outDur, sampleRate, "0"
mixR = selected("Sound")

# === Store grain info for visualization ===
for i to number_of_grains
    grainTime[i] = 0
    grainPan[i] = 0.5
    grainAmp[i] = 1
endfor

# === Generate Grains ===
appendInfoLine: "Rendering grains..."
progressStep = max(1, floor(number_of_grains / 10))

for i to number_of_grains
    # Output time distribution
    if time_distribution = 1
        # Linear
        if number_of_grains = 1
            outputTime = 0.5 * outDur
        else
            outputTime = (i - 1) / (number_of_grains - 1) * outDur
        endif
    elsif time_distribution = 2
        # Exponential
        if number_of_grains = 1
            outputTime = 0.5 * outDur
        else
            t = (i - 1) / (number_of_grains - 1)
            outputTime = outDur * (1 - exp(-3 * t)) / (1 - exp(-3))
        endif
    else
        # Random
        outputTime = randomUniform(0, outDur)
    endif
    
    # Source time
    if grain_source = 1
        # Sequential
        if number_of_grains = 1
            sourceTime = 0.5 * inputDuration
        else
            sourceTime = (i - 1) / (number_of_grains - 1) * inputDuration
        endif
    else
        # Random
        maxStart = inputDuration - grain_duration_s
        if maxStart < 0
            maxStart = 0
        endif
        sourceTime = randomUniform(0, maxStart)
    endif
    
    # Clamp source time
    if sourceTime < 0
        sourceTime = 0
    endif
    if sourceTime + grain_duration_s > inputDuration
        sourceTime = inputDuration - grain_duration_s
        if sourceTime < 0
            sourceTime = 0
        endif
    endif
    
    # Extract grain
    selectObject: sourceSound
    grainEnd = min(sourceTime + grain_duration_s, inputDuration)
    Extract part: sourceTime, grainEnd, "rectangular", 1, "no"
    grain = selected("Sound")
    
    # Get actual grain duration
    grainDur = Get total duration
    
    # Apply pitch shift (varispeed: reinterpret samples at a new rate ->
    # shifts pitch and changes grain length; mild aliasing on up-shifts)
    if apply_pitch_shift
        semitones = pitch_shift_semitones + randomUniform(-pitch_variation_semitones, pitch_variation_semitones)
        pitchFactor = 2^(semitones / 12)
        
        selectObject: grain
        Override sampling frequency: sampleRate * pitchFactor
        grainDur = Get total duration
    endif
    
    # Apply envelope
    selectObject: grain
    if envelope_shape = 1
        # Hann
        Formula: "self * 0.5 * (1 - cos(2*pi*x/grainDur))"
    elsif envelope_shape = 2
        # Gaussian
        Formula: "self * exp(-0.5 * ((x - grainDur/2) / (grainDur/4))^2)"
    endif
    # Rectangular = no envelope
    
    # LFO amplitude
    grainAmplitude = 1.0
    if apply_LFO
        lfoValue = 0.5 * (1 + sin(2 * pi * lFO_frequency * outputTime))
        grainAmplitude = lfoValue
    endif
    
    Formula: "self * grainAmplitude"
    
    # Panning
    if panning_mode = 1
        pan = sourceTime / inputDuration
    elsif panning_mode = 2
        pan = randomUniform(0, 1)
    else
        pan = fixed_pan
    endif
    
    gainL = sqrt(1 - pan)
    gainR = sqrt(pan)
    
    # Store for visualization
    grainTime[i] = outputTime
    grainPan[i] = pan
    grainAmp[i] = grainAmplitude
    
    # Add to mix buffers using Formula (FAST!)
    selectObject: grain
    Shift times to: "start time", outputTime
    
    grainStr$ = string$(grain)
    tStart$ = fixed$(outputTime, 6)
    tEnd$ = fixed$(outputTime + grainDur, 6)
    
    # Add to left channel
    selectObject: mixL
    Formula: "if x >= " + tStart$ + " and x <= " + tEnd$ + " then self + object(" + grainStr$ + ", x) * gainL else self fi"
    
    # Add to right channel
    selectObject: mixR
    Formula: "if x >= " + tStart$ + " and x <= " + tEnd$ + " then self + object(" + grainStr$ + ", x) * gainR else self fi"
    
    removeObject: grain
    
    if i mod progressStep = 0
        appendInfoLine: "  ", floor(i / number_of_grains * 100), "%"
    endif
endfor

# === Combine to Stereo ===
selectObject: mixL, mixR
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
Rename: original_name$ + "_particles"

removeObject: mixL, mixR, sourceSound

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Particle Field: " + original_name$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 0.5, 1.8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    selectObject: result
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Particles"
    Text bottom: "yes", "Time (s)"
    
    # Particle field (time vs pan)
    Select outer viewport: 0, 8, 3.3, 5.0
    Select inner viewport: 0.6, 7.6, 3.5, 4.9
    
    Axes: 0, outDur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, 0, 1
    
    # Draw grains as dots
    for i to number_of_grains
        # Color by amplitude
        ampColor = grainAmp[i]
        dotColor$ = "{" + fixed$(0.2 + ampColor * 0.5, 2) + ", " + fixed$(0.4 + ampColor * 0.3, 2) + ", " + fixed$(0.8 - ampColor * 0.3, 2) + "}"
        
        # Diameter (mm): visible floor + scale with amplitude
        dotDia = 2.0 + 2.0 * grainAmp[i]
        Paint circle (mm): dotColor$, grainTime[i], grainPan[i], dotDia
    endfor
    
    # Center line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0.5, outDur, 0.5
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan (L-R)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 5.1, 5.4
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Grains: " + string$(number_of_grains) + " | Duration: " + fixed$(grain_duration_s * 1000, 0) + "ms | Envelope: " + string$(envelope_shape)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result