# ============================================================
# Praat AudioTools - Additive_Particle_Field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Additive Particle Field Renderer - generates sine wave particles
#   that follow the pitch and intensity contour of the input audio.
#   Creates ethereal, bell-like textures from any source material.
#
# Changelog v0.3:
#   TIER 3 (performance, audio bit-identical):
#     - MAJOR speedup. v0.2 placed each grain into the full-length
#       mixL/mixR buffers with a whole-buffer `Formula`:
#         Formula: "if x >= tStart and x <= tEnd then self +
#                   object(grain, x) * gainL else self fi"
#       That iterated EVERY sample of the full-duration buffer for
#       EVERY particle (twice -- L and R), returning `else self`
#       for ~99.9% of samples. For Dense Cloud (300 particles) on
#       a 60 s input that is ~1.5 billion sample evaluations,
#       almost all wasted. v0.3 uses `Formula (part)` over only
#       the grain's time range:
#         Formula (part): grainStart, grainEnd, 1, 1,
#                         "self + object(grain, x) * gainL"
#       Same samples modified, same arithmetic -- bit-identical
#       output -- but each grain touches only ~grain_duration_s
#       worth of samples instead of the whole buffer. Speedup
#       scales with duration / grain_duration_s; typically
#       100-1000x on the synthesis loop, which dominates runtime.
#
#   TIER 2 (real bug, audio bit-identical):
#     - FIXED: legend text positioning. v0.2's legend panel
#       (outer viewport 0,8,5.1,5.4) set no Axes, so it inherited
#       `Axes: 0, duration, 0, 1` from the pan/amplitude panel.
#       The legend `Text: 1.5, "centre", 0.5, ...` was placed at
#       time=1.5 s / pan=0.5 in those inherited axes, so its
#       horizontal position depended on `duration` and fell off
#       the panel entirely for short inputs (duration < 1.5 s).
#       v0.3 sets explicit `Axes: 0, 1, 0, 1` (the legend is now
#       the suite-standard light-grey summary bar).
#
#   TIER 1 (polish, audio bit-identical):
#     - Dropped 7 form comment rows (1 instructional + 6
#       decorative `=== ... ===` dividers).
#     - Added colons to all 4 optionmenus (Preset:, Envelope_shape:,
#       Panning_mode:, Time_distribution:).
#     - Added presetName$ per preset; output filename now includes
#       it: <input>_particles_<preset> (was bare <input>_particles).
#     - Visualization rewritten to suite 8x8:
#         Title bar (suite light) + metadata subtitle
#         Original / Result waveform (side-by-side, headline)
#         Particle field time-vs-pitch (color = pan, signature)
#         Particle field time-vs-pan (color = amplitude)
#         Light-grey 3-line summary (suite standard)
#
#   Changelog v0.2:
#     - Fixed Formula interpolation syntax
#     - Optimized grain creation (short grains, not full-length)
#     - Added visualization
# ============================================================

form Additive Particle Field v0.3
    optionmenu Preset: 1
        option Custom
        option Dense Cloud
        option Sparse Field
        option Rhythmic Pulse
        option Shimmer
        option Long Resonance
    integer Number_of_particles 100
    real Grain_duration_s 0.050
    optionmenu Envelope_shape: 1
        option Hann
        option Gaussian
        option Rectangular
    optionmenu Panning_mode: 1
        option Pitch-derived
        option Random
        option Fixed
    real Fixed_pan 0.5
    boolean Apply_LFO 0
    real LFO_frequency 0.5
    optionmenu Time_distribution: 1
        option Linear
        option Exponential
        option Random
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
# v0.3: each preset defines presetName$ for the output filename + viz.
presetName$ = "Custom"
if preset = 2
    # Dense Cloud
    number_of_particles = 300
    grain_duration_s = 0.030
    envelope_shape = 2
    panning_mode = 2
    apply_LFO = 0
    time_distribution = 3
    presetName$ = "DenseCloud"
elsif preset = 3
    # Sparse Field
    number_of_particles = 30
    grain_duration_s = 0.150
    envelope_shape = 1
    panning_mode = 1
    apply_LFO = 0
    time_distribution = 1
    presetName$ = "SparseField"
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
    presetName$ = "RhythmicPulse"
elsif preset = 5
    # Shimmer
    number_of_particles = 150
    grain_duration_s = 0.060
    envelope_shape = 2
    panning_mode = 2
    apply_LFO = 1
    lFO_frequency = 0.25
    time_distribution = 2
    presetName$ = "Shimmer"
elsif preset = 6
    # Long Resonance
    number_of_particles = 15
    grain_duration_s = 0.800
    envelope_shape = 1
    panning_mode = 1
    apply_LFO = 1
    lFO_frequency = 0.15
    time_distribution = 2
    presetName$ = "LongResonance"
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
        
        # Add to mix buffers using Formula (part)
        # v0.3: Formula (part) over [grainStart, grainEnd] only.
        # v0.2 used a whole-buffer `Formula` with an `if x in range
        # then ... else self fi` test, iterating every sample of the
        # full-length buffer for every particle (twice). Formula
        # (part) touches only the grain's samples. Bit-identical
        # output, dramatically faster.
        grainStr$ = string$(grain)
        
        # Add to left channel
        selectObject: mixL
        Formula (part): grainStart, grainEnd, 1, 1, "self + object(" + grainStr$ + ", x) * gainL"
        
        # Add to right channel
        selectObject: mixR
        Formula (part): grainStart, grainEnd, 1, 1, "self + object(" + grainStr$ + ", x) * gainR"
        
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
Rename: original_name$ + "_particles_" + presetName$

# === Cleanup ===
removeObject: mixL, mixR, intensityObj, pitchObj

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Original waveform   (left half, headline)
# Panel B: Result waveform     (right half, headline)
# Panel C: Particle field time-vs-pitch (color = pan, signature)
# Panel D: Particle field time-vs-pan (color = amplitude)
# Panel E: Light-grey 3-line summary  (suite standard)
###############################################################################
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    if envelope_shape = 1
        envName$ = "Hann"
    elsif envelope_shape = 2
        envName$ = "Gaussian"
    else
        envName$ = "Rectangular"
    endif

    if panning_mode = 1
        panName$ = "Pitch-derived"
    elsif panning_mode = 2
        panName$ = "Random"
    else
        panName$ = "Fixed " + fixed$(fixed_pan, 2)
    endif

    if time_distribution = 1
        distName$ = "Linear"
    elsif time_distribution = 2
        distName$ = "Exponential"
    else
        distName$ = "Random"
    endif

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##ADDITIVE PARTICLE FIELD##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(number_of_particles) + " particles"
        ... + "  |  " + fixed$(grain_duration_s * 1000, 0) + " ms grains"
        ... + "  |  " + envName$ + " env"
        ... + "  |  " + distName$ + " dist"

    # ----------------------------------------------------------
    # PANEL A (left): ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18
    selectObject: original
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original  (" + fixed$(duration, 2) + " s)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL B (right): RESULT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18
    selectObject: result
    Colour: "{0.55, 0.30, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Particle field output  (stereo)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL C (left): PARTICLE FIELD  time vs pitch (color = pan)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 2.40, 4.40
    Select inner viewport: 0.55, 4.00, 2.60, 4.28
    Axes: 0, duration, minPitch, maxPitch
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minPitch, maxPitch

    for i to number_of_particles
        pan = particlePan[i]
        dotColor$ = "{" + fixed$(0.30 + pan * 0.60, 2) + ", " + fixed$(0.30, 2) + ", " + fixed$(0.90 - pan * 0.60, 2) + "}"
        Paint circle (mm): dotColor$, particleTime[i], particlePitch[i], 0.6
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Particles: pitch over time  (blue = L, red = R)"
    Font size: 6
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D (right): PARTICLE FIELD  time vs pan (color = amp)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.40, 4.40
    Select inner viewport: 4.55, 7.75, 2.60, 4.28
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1

    maxAmp = 0.001
    for i to number_of_particles
        if particleAmp[i] > maxAmp
            maxAmp = particleAmp[i]
        endif
    endfor

    # Center (pan = 0.5) reference
    Colour: "{0.70, 0.70, 0.74}"
    Dotted line
    Draw line: 0, 0.5, duration, 0.5
    Solid line

    for i to number_of_particles
        ampNorm = particleAmp[i] / maxAmp
        dotColor$ = "{" + fixed$(0.30 + ampNorm * 0.50, 2) + ", " + fixed$(0.50 + ampNorm * 0.30, 2) + ", " + fixed$(0.30, 2) + "}"
        Paint circle (mm): dotColor$, particleTime[i], particlePan[i], 0.6
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Particles: pan over time  (greener = louder)"
    Font size: 6
    Text left: "yes", "Pan (L=0, R=1)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # v0.3 fix: explicit Axes 0,1,0,1 before any Text(). v0.2's
    # legend inherited axes from the panel above, so text landed at
    # unpredictable positions (off-panel for short inputs).
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.50, 5.20
    Select inner viewport: 0.55, 7.75, 4.57, 5.14
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if apply_LFO
        lfoStr$ = "ON (" + fixed$(lFO_frequency, 2) + " Hz)"
    else
        lfoStr$ = "OFF"
    endif

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + original_name$
        ... + "  |  " + string$(number_of_particles) + " particles"
        ... + "  |  grain " + fixed$(grain_duration_s * 1000, 0) + " ms"
        ... + "  |  env " + envName$
        ... + "  |  pan " + panName$

    Text: 0.02, "left", 0.28, "half",
        ... "Time dist: " + distName$
        ... + "  |  LFO: " + lfoStr$
        ... + "  |  Pitch range: " + string$(minPitch) + "-" + string$(maxPitch) + " Hz"
        ... + "  |  In: " + fixed$(duration, 2) + " s"
        ... + "  |  Out: " + original_name$ + "_particles_" + presetName$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
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