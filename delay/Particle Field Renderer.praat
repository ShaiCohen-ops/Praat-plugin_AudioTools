# ============================================================
# Praat AudioTools - Particle Field Renderer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Particle Field Renderer
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# ============= Particle Field Renderer (Stereo) =============
# Select exactly one Sound before running.

form Particle Field Render
    comment Particle Synthesis Parameters
    integer numberOfParticles 100
    real    grainDur 0.050
    choice  envelopeShape 1
        button Hann
        button Gaussian
        button Rectangular
    comment Pitch Parameters
    real    defaultPitch 200
    real    minPitch 75
    real    maxPitch 600
    comment Panning Parameters
    choice  panningMode 1
        button Pitch-derived
        button Random
        button Fixed
    real    fixedPan 0.5 
    comment Amplitude Modulation
    boolean applyLFO 0
    real    lfoFrequency 0.5 
    comment Time Distribution
    choice  timeDistribution 1
        button Linear
        button Exponential
        button Random
    comment Output Settings
    real    scale_peak 0.99
    boolean play_after_processing 1
endform

# ---------- Safety ----------
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# ---------- Input Validation ----------
if grainDur <= 0
    exitScript: "Grain duration must be greater than 0."
endif
if minPitch <= 0 or maxPitch <= minPitch
    exitScript: "Invalid pitch range: minPitch must be > 0 and less than maxPitch."
endif
if fixedPan < 0 or fixedPan > 1
    exitScript: "Fixed pan must be between 0 and 1."
endif
if lfoFrequency <= 0 and applyLFO
    exitScript: "LFO frequency must be greater than 0 when applyLFO is enabled."
endif

# ---------- Selected sound & props ----------
sound$ = selected$("Sound")
sound  = selected("Sound")

selectObject: sound
duration          = Get total duration
samplingFrequency = Get sampling frequency

# Safe aliases
dur = duration
sr  = samplingFrequency

writeInfoLine: "Rendering ", numberOfParticles, " particles from: ", sound$, newline$

# ---------- Analysis ----------
selectObject: sound
To Intensity: 100, 0, "yes"
intensity = selected("Intensity")

selectObject: sound
To Pitch: 0, minPitch, maxPitch
pitch = selected("Pitch")

# ---------- Create empty L/R mix buffers ----------
Create Sound from formula: "MixL", 1, 0, dur, sr, "0"
mixL = selected("Sound")
Create Sound from formula: "MixR", 1, 0, dur, sr, "0"
mixR = selected("Sound")

# ---------- Optional: print a small header ----------
appendInfoLine: "ID", tab$, "t(s)", tab$, "freq(Hz)", tab$, "amp", tab$, "pan"

# ---------- Particle synthesis loop ----------
for i from 1 to numberOfParticles
    # Time distribution
    if timeDistribution = 1 ; Linear
        if numberOfParticles = 1
            particleTime = 0.5 * duration
        else
            particleTime = (i - 1) / (numberOfParticles - 1) * duration
        endif
    elsif timeDistribution = 2 ; Exponential
        if numberOfParticles = 1
            particleTime = 0.5 * duration
        else
            t = (i - 1) / (numberOfParticles - 1)
            particleTime = duration * (1 - exp(-3 * t)) / (1 - exp(-3))
        endif
    else ; Random
        particleTime = randomUniform(0, duration)
    endif

    # Features
    selectObject: intensity
    intensityValue = Get value at time: particleTime, "Linear"
    if intensityValue = undefined
        intensityValue = 0
    endif

    selectObject: pitch
    pitchValue = Get value at time: particleTime, "Hertz", "Linear"
    if pitchValue = undefined
        pitchValue = defaultPitch
    endif
    pitchValue = min(maxPitch, max(minPitch, pitchValue))

    selectObject: sound
    amp = Get value at time: 1, particleTime, "Linear"
    if amp = undefined
        amp = 0
    endif

    # Manual abs
    if amp < 0
        absAmp = -amp
    else
        absAmp = amp
    endif

    # Grain amplitude with optional LFO
    grainAmp = 0.2 * (absAmp + intensityValue / 100.0)
    if applyLFO
        lfoValue = 0.5 * (1 + sin(2 * 3.14 * lfoFrequency * particleTime))
        grainAmp = grainAmp * lfoValue
    endif

    # Panning
    if panningMode = 1 ; Pitch-derived
        angle = (pitchValue / maxPitch) * 2 * 3.14
        dirX = cos(angle)
        pan = (dirX + 1) / 2
    elsif panningMode = 2 ; Random
        pan = randomUniform(0, 1)
    else ; Fixed
        pan = fixedPan
    endif
    gl = sqrt(1 - pan)
    gr = sqrt(pan)

    # Grain envelope formula based on choice
    if envelopeShape = 1 ; Hann
        envelope$ = "0.5 * (1 - cos(2*3.14*(x - 'particleTime')/'grainDur'))"
    elsif envelopeShape = 2 ; Gaussian
        envelope$ = "exp(-0.5 * ((x - 'particleTime' - 'grainDur'/2) / ('grainDur'/4))^2)"
    else ; Rectangular
        envelope$ = "1"
    endif

    # Create grain
    formula$ = "if x >= 'particleTime' and x < 'particleTime' + 'grainDur' then 'grainAmp' * ('envelope$') * sin(2*3.14*'pitchValue'*(x - 'particleTime')) else 0 fi"
    Create Sound from formula: "Grain", 1, 0, dur, sr, formula$
    grain = selected("Sound")
    
    # Split to L/R and scale with gains
    selectObject: grain
    Copy: "GrainL"
    grainL = selected("Sound")
    selectObject: grain
    Copy: "GrainR"
    grainR = selected("Sound")

    selectObject: grainL
    Multiply: gl
    selectObject: grainR
    Multiply: gr

    # Accumulate into L/R mixes using Formula
    selectObject: mixL
    if numberOfSelected("Sound") = 1
        selectObject: grainL
        if numberOfSelected("Sound") = 1
            selectObject: mixL
            Formula: "self + Sound_GrainL(x)"
        else
            appendInfoLine: "Error: GrainL not found for particle ", i
        endif
    else
        appendInfoLine: "Error: MixL not found for particle ", i
    endif

    selectObject: mixR
    if numberOfSelected("Sound") = 1
        selectObject: grainR
        if numberOfSelected("Sound") = 1
            selectObject: mixR
            Formula: "self + Sound_GrainR(x)"
        else
            appendInfoLine: "Error: GrainR not found for particle ", i
        endif
    else
        appendInfoLine: "Error: MixR not found for particle ", i
    endif

    # Cleanup grain objects
    selectObject: grain
    plusObject: grainL
    plusObject: grainR
    Remove

    # Log progress
    appendInfoLine: fixed$(i,0), tab$, fixed$(particleTime,3), tab$, fixed$(pitchValue,1), tab$, fixed$(grainAmp,3), tab$, fixed$(pan,3)
endfor

# ---------- Finalize stereo ----------
selectObject: mixL
plusObject: mixR
Combine to stereo
Rename: "Particles_mix"

# Final level
selectObject: "Sound Particles_mix"
Scale peak: scale_peak

# ---------- Cleanup analysis ----------
selectObject: intensity
Remove
selectObject: pitch
Remove
selectObject: mixL
Remove
selectObject: mixR
Remove

# ---------- Optionally play ----------
if play_after_processing
    selectObject: "Sound Particles_mix"
    Play
endif

appendInfoLine: newline$, "Done. Created stereo Sound: 'Particles_mix'"