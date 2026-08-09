# ============================================================
# Praat AudioTools - Additive_Particle_Field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Additive Particle Field Renderer - generates short additive spectral
#   particles that follow the pitch and intensity contour of the input audio.
#   Voiced frames produce harmonic or bell-inharmonic micro-spectra; unvoiced
#   frames produce noise particles, preserving brightness and transients.
#
#
# Changelog v0.5:
#   Spectral particle redesign:
#     - Each voiced particle is now an additive micro-spectrum rather than
#       a single sine oscillator. Custom controls expose partial count,
#       spectral brightness, and harmonic vs bell-inharmonic spectra.
#     - Partial amplitudes are power-law weighted and normalized so adding
#       more partials changes timbre without uncontrolled gain growth.
#     - Partials above 95% of Nyquist are omitted automatically.
#     - Randomized starting phases reduce phase-locked, organ-like buildup.
#     - Unvoiced analysis frames no longer fall back to a fixed 200 Hz sine.
#       They render short broadband noise particles, preserving fricative and
#       transient brightness instead of forcing everything into the low band.
#     - Shimmer and Long Resonance use stretched inharmonic partial ratios
#       for a more bell-like spectrum; other presets remain harmonic.
#     - Visualization and Info output now report spectral configuration and
#       distinguish voiced from unvoiced particles.
#
# Changelog v0.4:
#   DSP / correctness fixes:
#     - Intensity now controls particle amplitude in the correct domain.
#       Intensity values are dB SPL; v0.3 divided dB by 100 and also
#       mixed in one instantaneous waveform sample, making amplitude
#       phase-dependent and compressing the intended dynamic contour.
#       v0.4 converts dB differences to linear amplitude ratios:
#         amp = 10^((I(t) - Imax)/20)
#       and uses the smoothed Intensity contour directly.
#     - FIXED: Linear and Exponential distributions placed their final
#       particle exactly at the Sound end time, giving it zero duration.
#       All distributions now schedule starts over [0, duration-grainDur]
#       so particles can render at their requested full duration.
#     - FIXED: Pitch-derived pan used a cosine cycle, so pan was not
#       monotonic with pitch (low and high pitches could land on the same
#       side). It now maps minPitch..maxPitch directly to L..R.
#     - FIXED: non-zero Sound time domains. Analysis uses absolute source
#       time while synthesis/visualization use a zero-based output time.
#     - Gaussian envelope is now edge-normalized to reach zero at both
#       boundaries, reducing boundary clicks.
#     - Intensity analysis pitch floor now matches the pitch analysis
#       floor (minPitch) instead of using a separate hard-coded 100 Hz.
#     - Sub-millisecond grains are no longer silently discarded; the
#       minimum renderable grain is tied to the Sound sample period.
#     - Added particle-count validation and safe normalization for silent
#       results. Fixed-pan validation is applied only when Fixed mode is used.
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

form Additive Particle Field v0.5
    optionmenu Preset: 1
        option Custom
        option Dense Cloud
        option Sparse Field
        option Rhythmic Pulse
        option Shimmer
        option Long Resonance
    integer Number_of_particles 100
    real Grain_duration_s 0.050
    integer Number_of_partials 10
    real Spectral_brightness 0.78
    optionmenu Spectrum_type: 1
        option Harmonic
        option Bell-inharmonic
    real Inharmonicity 0.020
    real Unvoiced_noise_mix 0.35
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
# v0.5: presets also define spectral particle characteristics.
presetName$ = "Custom"
if preset = 2
    # Dense Cloud
    number_of_particles = 300
    grain_duration_s = 0.030
    number_of_partials = 9
    spectral_brightness = 0.82
    spectrum_type = 1
    unvoiced_noise_mix = 0.40
    inharmonicity = 0
    envelope_shape = 2
    panning_mode = 2
    apply_LFO = 0
    time_distribution = 3
    presetName$ = "DenseCloud"
elsif preset = 3
    # Sparse Field
    number_of_particles = 30
    grain_duration_s = 0.150
    number_of_partials = 10
    spectral_brightness = 0.68
    spectrum_type = 1
    unvoiced_noise_mix = 0.30
    inharmonicity = 0
    envelope_shape = 1
    panning_mode = 1
    apply_LFO = 0
    time_distribution = 1
    presetName$ = "SparseField"
elsif preset = 4
    # Rhythmic Pulse
    number_of_particles = 80
    grain_duration_s = 0.040
    number_of_partials = 8
    spectral_brightness = 0.90
    spectrum_type = 1
    unvoiced_noise_mix = 0.45
    inharmonicity = 0
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
    number_of_partials = 18
    spectral_brightness = 0.96
    spectrum_type = 2
    unvoiced_noise_mix = 0.25
    inharmonicity = 0.018
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
    number_of_partials = 14
    spectral_brightness = 0.80
    spectrum_type = 2
    unvoiced_noise_mix = 0.18
    inharmonicity = 0.030
    envelope_shape = 1
    panning_mode = 1
    apply_LFO = 1
    lFO_frequency = 0.15
    time_distribution = 2
    presetName$ = "LongResonance"
endif

# === Fixed Parameters ===
minPitch = 75
maxPitch = 600

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

# === Validate ===
if number_of_particles < 1
    exitScript: "Number of particles must be at least 1"
endif
if number_of_particles > 10000
    exitScript: "Number of particles must not exceed 10000"
endif
if grain_duration_s <= 0
    exitScript: "Grain duration must be > 0"
endif
if number_of_partials < 1 or number_of_partials > 32
    exitScript: "Number of partials must be between 1 and 32"
endif
if number_of_particles * number_of_partials > 50000
    exitScript: "Particle x partial count is too high (maximum complexity is 50000)"
endif
if spectral_brightness < 0 or spectral_brightness > 1
    exitScript: "Spectral brightness must be between 0 and 1"
endif
if inharmonicity < 0 or inharmonicity > 0.10
    exitScript: "Inharmonicity must be between 0 and 0.10"
endif
if unvoiced_noise_mix < 0 or unvoiced_noise_mix > 1
    exitScript: "Unvoiced noise mix must be between 0 and 1"
endif
if panning_mode = 3 and (fixed_pan < 0 or fixed_pan > 1)
    exitScript: "Fixed pan must be 0-1"
endif
if lFO_frequency <= 0 and apply_LFO
    exitScript: "LFO frequency must be > 0"
endif

# === Get Input ===
original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sourceStart = Get start time
duration = Get total duration
sampleRate = Get sampling frequency
nyquistLimit = 0.475 * sampleRate

# Brightness 0..1 maps to a steep..shallow partial roll-off.
# 0 -> 1/h^2.6 (dark), 1 -> 1/h^0.6 (bright).
partialDecay = 2.6 - 2.0 * spectral_brightness

minRenderableGrain = 2 / sampleRate
if grain_duration_s < minRenderableGrain
    exitScript: "Grain duration is too short for this sampling rate (minimum is " + fixed$(minRenderableGrain * 1000, 3) + " ms)"
endif

# Keep every particle fully inside the output whenever possible.
effectiveGrainDur = min(grain_duration_s, duration)
maxStart = max(0, duration - effectiveGrainDur)

# === Info ===
writeInfoLine: "=== Additive Particle Field ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Particles: ", number_of_particles
appendInfoLine: "Grain duration: ", fixed$(grain_duration_s * 1000, 1), " ms"
appendInfoLine: "Partials: ", number_of_partials, " | brightness: ", fixed$(spectral_brightness, 2)
if spectrum_type = 1
    appendInfoLine: "Spectrum: harmonic"
else
    appendInfoLine: "Spectrum: bell-inharmonic (stretch ", fixed$(inharmonicity, 3), ")"
endif
appendInfoLine: "Unvoiced noise mix: ", fixed$(unvoiced_noise_mix, 2)
appendInfoLine: ""

# === Analysis ===
appendInfoLine: "Analyzing pitch and intensity..."

selectObject: original
To Intensity: minPitch, 0, "yes"
intensityObj = selected("Intensity")
intensityPeak = Get maximum: 0, 0, "Parabolic"

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
    particleVoiced[i] = 0
endfor

# === Particle Synthesis Loop ===
appendInfoLine: "Rendering particles..."
progressStep = max(1, floor(number_of_particles / 10))
voicedParticles = 0
unvoicedParticles = 0

for i to number_of_particles
    # Time distribution. outTime is zero-based synthesis time;
    # sourceTime is the corresponding absolute time in the input Sound.
    if time_distribution = 1
        # Linear
        if number_of_particles = 1
            outTime = 0.5 * maxStart
        else
            outTime = (i - 1) / (number_of_particles - 1) * maxStart
        endif
    elsif time_distribution = 2
        # Exponential (higher event density toward the end)
        if number_of_particles = 1
            outTime = 0.5 * maxStart
        else
            t = (i - 1) / (number_of_particles - 1)
            outTime = maxStart * (1 - exp(-3 * t)) / (1 - exp(-3))
        endif
    else
        # Random
        if maxStart > 0
            outTime = randomUniform(0, maxStart)
        else
            outTime = 0
        endif
    endif
    sourceTime = sourceStart + outTime
    
    # Get intensity at this time. Intensity values are in dB; map
    # relative dB to a linear pressure/amplitude ratio.
    selectObject: intensityObj
    intensityValue = Get value at time: sourceTime, "Linear"
    if intensityValue = undefined or intensityPeak = undefined
        intensityAmp = 0
    else
        relativeDB = min(0, intensityValue - intensityPeak)
        intensityAmp = 10 ^ (relativeDB / 20)
    endif
    
    # Get pitch at this time. Undefined pitch means unvoiced: do not
    # invent a fixed 200 Hz tone; render a broadband noise particle below.
    selectObject: pitchObj
    pitchValue = Get value at time: sourceTime, "Hertz", "Linear"
    if pitchValue = undefined
        isVoiced = 0
        unvoicedParticles = unvoicedParticles + 1
        # A display/pan anchor only; it is not used as an oscillator pitch.
        pitchValue = randomUniform(minPitch, maxPitch)
    else
        isVoiced = 1
        voicedParticles = voicedParticles + 1
        pitchValue = min(maxPitch, max(minPitch, pitchValue))
    endif
    
    # Grain amplitude follows the smoothed intensity contour directly.
    grainAmp = 0.2 * intensityAmp
    
    # LFO modulation in zero-based output time.
    if apply_LFO
        lfoValue = 0.5 * (1 + sin(2 * pi * lFO_frequency * outTime))
        grainAmp = grainAmp * lfoValue
    endif
    
    # Panning
    if panning_mode = 1
        # Pitch-derived: monotonic low=L, high=R.
        pan = (pitchValue - minPitch) / (maxPitch - minPitch)
        pan = min(1, max(0, pan))
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
    particleTime[i] = outTime
    particlePitch[i] = pitchValue
    particlePan[i] = pan
    particleAmp[i] = grainAmp
    particleVoiced[i] = isVoiced
    
    # === Create Short Grain (OPTIMIZED) ===
    # Only create grain of actual duration, not full-length
    
    grainStart = outTime
    grainEnd = outTime + effectiveGrainDur
    if grainEnd > duration
        grainEnd = duration
    endif
    actualGrainDur = grainEnd - grainStart
    
    if actualGrainDur >= minRenderableGrain
        # Build carrier expression once per particle. Voiced particles use
        # a normalized additive spectrum; unvoiced particles use broadband
        # bounded white noise instead of an arbitrary low-frequency fallback.
        if isVoiced
            spectrumExpr$ = "0"
            partialWeightSum = 0
            partialsUsed = 0
            for h to number_of_partials
                if spectrum_type = 1
                    ratio = h
                else
                    # Stretched harmonic series: upper partials progressively
                    # depart from integer ratios, producing bell-like spectra.
                    ratio = h * (1 + inharmonicity * (h - 1))
                endif
                partialFreq = pitchValue * ratio
                if partialFreq < nyquistLimit
                    partialWeight = 1 / (h ^ partialDecay)
                    partialPhase = randomUniform(0, 2 * pi)
                    partialFreq$ = fixed$(partialFreq, 8)
                    partialPhase$ = fixed$(partialPhase, 8)
                    partialWeight$ = fixed$(partialWeight, 10)
                    spectrumExpr$ = spectrumExpr$ + " + " + partialWeight$ + "*sin(2*pi*" + partialFreq$ + "*x+" + partialPhase$ + ")"
                    partialWeightSum = partialWeightSum + partialWeight
                    partialsUsed = partialsUsed + 1
                endif
            endfor
            if partialWeightSum > 0
                carrierExpr$ = "(" + spectrumExpr$ + ")/" + fixed$(partialWeightSum, 10)
            else
                # Extremely low sampling rates can leave no safe sinusoidal
                # partial. Fall back to low-level broadband material.
                carrierExpr$ = fixed$(unvoiced_noise_mix, 8) + "*randomUniform(-1,1)"
            endif
        else
            carrierExpr$ = fixed$(unvoiced_noise_mix, 8) + "*randomUniform(-1,1)"
        endif

        # Create grain envelope formula around the carrier expression.
        if envelope_shape = 1
            # Hann
            grainFormula$ = "grainAmp * 0.5 * (1 - cos(2*pi*x/actualGrainDur)) * (" + carrierExpr$ + ")"
        elsif envelope_shape = 2
            # Edge-normalized Gaussian (sigma = duration/6).
            grainFormula$ = "grainAmp * (exp(-0.5 * ((x - actualGrainDur/2) / (actualGrainDur/6))^2) - exp(-4.5)) / (1 - exp(-4.5)) * (" + carrierExpr$ + ")"
        else
            # Rectangular
            grainFormula$ = "grainAmp * (" + carrierExpr$ + ")"
        endif
        Create Sound from formula: "grain", 1, 0, actualGrainDur, sampleRate, grainFormula$
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

appendInfoLine: "Voiced particles: ", voicedParticles, " | unvoiced/noise particles: ", unvoicedParticles

# === Combine to Stereo ===
selectObject: mixL, mixR
Combine to stereo
result = selected("Sound")

# Avoid asking Scale peak to normalize an all-zero result.
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: 0.95
endif
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

    if spectrum_type = 1
        spectrumName$ = "Harmonic"
    else
        spectrumName$ = "Bell-inharmonic"
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
        ... + "  |  " + string$(number_of_partials) + " partials"
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
        if particleVoiced[i]
            dotColor$ = "{" + fixed$(0.30 + pan * 0.60, 2) + ", " + fixed$(0.30, 2) + ", " + fixed$(0.90 - pan * 0.60, 2) + "}"
        else
            dotColor$ = "{0.55, 0.55, 0.55}"
        endif
        Paint circle (mm): dotColor$, particleTime[i], particlePitch[i], 0.6
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Particles: pitch anchors  (grey = unvoiced/noise carrier)"
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
        ... + "  |  " + spectrumName$
        ... + "  |  pan " + panName$

    Text: 0.02, "left", 0.28, "half",
        ... "Time dist: " + distName$
        ... + "  |  LFO: " + lfoStr$
        ... + "  |  partials: " + string$(number_of_partials)
        ... + "  |  bright: " + fixed$(spectral_brightness, 2)
        ... + "  |  V/U: " + string$(voicedParticles) + "/" + string$(unvoicedParticles)
        ... + "  |  Pitch: " + string$(minPitch) + "-" + string$(maxPitch) + " Hz"
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