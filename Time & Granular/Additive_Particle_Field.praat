# ============================================================
# Praat AudioTools - Particle_Field_Renderer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Additive Particle Field Renderer - generates sine wave particles
#   that follow the pitch and intensity contour of the input audio.
#   Creates ethereal, bell-like textures from any source material.
#
# Changelog v0.2:
#   - Fixed Formula interpolation syntax
#   - Optimized grain creation (short grains, not full-length)
#   - Added visualization
# ============================================================

form Additive Particle Field
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Dense Cloud
        option Sparse Field
        option Rhythmic Pulse
        option Shimmer
        option Long Resonance
    
    comment === Particles ===
    integer Number_of_particles 100
    real Grain_duration_s 0.050
    optionmenu Envelope_shape 1
        option Hann
        option Gaussian
        option Rectangular
    
    comment === Panning ===
    optionmenu Panning_mode 1
        option Pitch-derived
        option Random
        option Fixed
    real Fixed_pan 0.5
    
    comment === Modulation ===
    boolean Apply_LFO 0
    real LFO_frequency 0.5
    
    comment === Time Distribution ===
    optionmenu Time_distribution 1
        option Linear
        option Exponential
        option Random
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Dense Cloud
    number_of_particles = 300
    grain_duration_s = 0.030
    envelope_shape = 2
    panning_mode = 2
    apply_LFO = 0
    time_distribution = 3
elsif preset = 3
    # Sparse Field
    number_of_particles = 30
    grain_duration_s = 0.150
    envelope_shape = 1
    panning_mode = 1
    apply_LFO = 0
    time_distribution = 1
elsif preset = 4
    # Rhythmic Pulse
    number_of_particles = 80
    grain_duration_s = 0.040
    envelope_shape = 3
    panning_mode = 3
    fixed_pan = 0.5
    apply_LFO = 1
    lFO_frequency = 4.0
    time_distribution = 1
elsif preset = 5
    # Shimmer
    number_of_particles = 150
    grain_duration_s = 0.060
    envelope_shape = 2
    panning_mode = 2
    apply_LFO = 1
    lFO_frequency = 0.25
    time_distribution = 2
elsif preset = 6
    # Long Resonance
    number_of_particles = 15
    grain_duration_s = 0.800
    envelope_shape = 1
    panning_mode = 1
    apply_LFO = 1
    lFO_frequency = 0.15
    time_distribution = 2
endif

# === Fixed Parameters ===
defaultPitch = 200
minPitch = 75
maxPitch = 600

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
duration = Get total duration
sampleRate = Get sampling frequency

# === Info ===
writeInfoLine: "=== Additive Particle Field ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Particles: ", number_of_particles
appendInfoLine: "Grain duration: ", fixed$(grain_duration_s * 1000, 1), " ms"
appendInfoLine: ""

# === Analysis ===
appendInfoLine: "Analyzing pitch and intensity..."

selectObject: original
To Intensity: 100, 0, "yes"
intensityObj = selected("Intensity")

selectObject: original
To Pitch: 0, minPitch, maxPitch
pitchObj = selected("Pitch")

# === Create Stereo Mix Buffers ===
Create Sound from formula: "mixL", 1, 0, duration, sampleRate, "0"
mixL = selected("Sound")

Create Sound from formula: "mixR", 1, 0, duration, sampleRate, "0"
mixR = selected("Sound")

# === Store particle info for visualization ===
for i to number_of_particles
    particleTime[i] = 0
    particlePitch[i] = 0
    particlePan[i] = 0.5
    particleAmp[i] = 0
endfor

# === Particle Synthesis Loop ===
appendInfoLine: "Rendering particles..."
progressStep = max(1, floor(number_of_particles / 10))

for i to number_of_particles
    # Time distribution
    if time_distribution = 1
        # Linear
        if number_of_particles = 1
            pTime = 0.5 * duration
        else
            pTime = (i - 1) / (number_of_particles - 1) * duration
        endif
    elsif time_distribution = 2
        # Exponential
        if number_of_particles = 1
            pTime = 0.5 * duration
        else
            t = (i - 1) / (number_of_particles - 1)
            pTime = duration * (1 - exp(-3 * t)) / (1 - exp(-3))
        endif
    else
        # Random
        pTime = randomUniform(0, duration)
    endif
    
    # Get intensity at this time
    selectObject: intensityObj
    intensityValue = Get value at time: pTime, "Linear"
    if intensityValue = undefined
        intensityValue = 0
    endif
    
    # Get pitch at this time
    selectObject: pitchObj
    pitchValue = Get value at time: pTime, "Hertz", "Linear"
    if pitchValue = undefined
        pitchValue = defaultPitch
    endif
    pitchValue = min(maxPitch, max(minPitch, pitchValue))
    
    # Get amplitude from waveform
    selectObject: original
    amp = Get value at time: 1, pTime, "Linear"
    if amp = undefined
        amp = 0
    endif
    absAmp = abs(amp)
    
    # Grain amplitude
    grainAmp = 0.2 * (absAmp + intensityValue / 100.0)
    
    # LFO modulation
    if apply_LFO
        lfoValue = 0.5 * (1 + sin(2 * pi * lFO_frequency * pTime))
        grainAmp = grainAmp * lfoValue
    endif
    
    # Panning
    if panning_mode = 1
        # Pitch-derived
        angle = (pitchValue / maxPitch) * 2 * pi
        dirX = cos(angle)
        pan = (dirX + 1) / 2
    elsif panning_mode = 2
        # Random
        pan = randomUniform(0, 1)
    else
        # Fixed
        pan = fixed_pan
    endif
    
    gainL = sqrt(1 - pan)
    gainR = sqrt(pan)
    
    # Store for visualization
    particleTime[i] = pTime
    particlePitch[i] = pitchValue
    particlePan[i] = pan
    particleAmp[i] = grainAmp
    
    # === Create Short Grain (OPTIMIZED) ===
    # Only create grain of actual duration, not full-length
    
    grainStart = pTime
    grainEnd = pTime + grain_duration_s
    if grainEnd > duration
        grainEnd = duration
    endif
    actualGrainDur = grainEnd - grainStart
    
    if actualGrainDur > 0.001
        # Create grain envelope formula
        if envelope_shape = 1
            # Hann
            Create Sound from formula: "grain", 1, 0, actualGrainDur, sampleRate, 
                ... "grainAmp * 0.5 * (1 - cos(2*pi*x/actualGrainDur)) * sin(2*pi*pitchValue*x)"
        elsif envelope_shape = 2
            # Gaussian
            Create Sound from formula: "grain", 1, 0, actualGrainDur, sampleRate,
                ... "grainAmp * exp(-0.5 * ((x - actualGrainDur/2) / (actualGrainDur/4))^2) * sin(2*pi*pitchValue*x)"
        else
            # Rectangular
            Create Sound from formula: "grain", 1, 0, actualGrainDur, sampleRate,
                ... "grainAmp * sin(2*pi*pitchValue*x)"
        endif
        grain = selected("Sound")
        
        # Shift grain to correct position
        Shift times to: "start time", grainStart
        
        # Add to mix buffers using Formula
        grainStr$ = string$(grain)
        tStart$ = fixed$(grainStart, 6)
        tEnd$ = fixed$(grainEnd, 6)
        
        # Add to left channel
        selectObject: mixL
        Formula: "if x >= " + tStart$ + " and x <= " + tEnd$ + " then self + object(" + grainStr$ + ", x) * gainL else self fi"
        
        # Add to right channel
        selectObject: mixR
        Formula: "if x >= " + tStart$ + " and x <= " + tEnd$ + " then self + object(" + grainStr$ + ", x) * gainR else self fi"
        
        removeObject: grain
    endif
    
    if i mod progressStep = 0
        appendInfoLine: "  ", floor(i / number_of_particles * 100), "%"
    endif
endfor

# === Combine to Stereo ===
selectObject: mixL, mixR
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
Rename: original_name$ + "_particles"

# === Cleanup ===
removeObject: mixL, mixR, intensityObj, pitchObj

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Additive Particle Field: " + original_name$
    
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
    Colour: "{0.6, 0.3, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Particles"
    Text bottom: "yes", "Time (s)"
    
    # Particle field (time vs pitch, color by pan)
    Select outer viewport: 0, 4, 3.3, 5.0
    Select inner viewport: 0.6, 3.8, 3.5, 4.9
    
    Axes: 0, duration, minPitch, maxPitch
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minPitch, maxPitch
    
    # Draw particles as dots (color by pan: blue=left, red=right)
    for i to number_of_particles
        pan = particlePan[i]
        dotColor$ = "{" + fixed$(0.3 + pan * 0.6, 2) + ", " + fixed$(0.3, 2) + ", " + fixed$(0.9 - pan * 0.6, 2) + "}"
        
        Paint circle (mm): dotColor$, particleTime[i], particlePitch[i], 0.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Particle field (time vs pan, color by amplitude)
    Select outer viewport: 4, 8, 3.3, 5.0
    Select inner viewport: 4.4, 7.6, 3.5, 4.9
    
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1
    
    # Find max amplitude for normalization
    maxAmp = 0.001
    for i to number_of_particles
        if particleAmp[i] > maxAmp
            maxAmp = particleAmp[i]
        endif
    endfor
    
    # Draw particles (color by amplitude)
    for i to number_of_particles
        ampNorm = particleAmp[i] / maxAmp
        dotColor$ = "{" + fixed$(0.3 + ampNorm * 0.5, 2) + ", " + fixed$(0.5 + ampNorm * 0.3, 2) + ", " + fixed$(0.3, 2) + "}"
        
        Paint circle (mm): dotColor$, particleTime[i], particlePan[i], 0.5
    endfor
    
    # Center line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0.5, duration, 0.5
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan (L-R)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 5.1, 5.4
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.5, "centre", 0.5, "half", "Particles: " + string$(number_of_particles) + " | Duration: " + fixed$(grain_duration_s * 1000, 0) + "ms | Pitch range: " + string$(minPitch) + "-" + string$(maxPitch) + " Hz"
    
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