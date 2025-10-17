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
#   Particle Field Renderer audio
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
clearinfo
form Granular Sampler
    comment Preset Selection
    optionmenu Preset 1
        option Custom
        option Dense Cloud
        option Sparse Field
        option Rhythmic Pulse
        option Shimmer
        option Long Resonance
    comment Grain Synthesis Parameters
    integer numberOfGrains 100
    real    grainDur 0.050
    choice  envelopeShape 1
        button Hann
        button Gaussian
        button Rectangular
    comment Pitch Shift
    boolean applyPitchShift 0
    real    pitchShiftSemitones 0.0
    real    pitchVariation 0.0
    comment Panning Parameters
    choice  panningMode 1
        button Position-derived
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
    comment Grain Source
    choice  grainSource 1
        button Sequential
        button Random
    comment Output Duration
    real    outputDuration 0.0
    comment (0 = use input duration)
endform

# ---------- Apply Preset ----------
if preset = 2 ; Dense Cloud
    numberOfGrains = 300
    grainDur = 0.030
    envelopeShape = 2
    panningMode = 2
    applyLFO = 0
    timeDistribution = 3
    grainSource = 2
    applyPitchShift = 0
elsif preset = 3 ; Sparse Field
    numberOfGrains = 30
    grainDur = 0.150
    envelopeShape = 1
    panningMode = 1
    applyLFO = 0
    timeDistribution = 1
    grainSource = 1
    applyPitchShift = 0
elsif preset = 4 ; Rhythmic Pulse
    numberOfGrains = 80
    grainDur = 0.040
    envelopeShape = 3
    panningMode = 3
    fixedPan = 0.5
    applyLFO = 1
    lfoFrequency = 4.0
    timeDistribution = 1
    grainSource = 1
    applyPitchShift = 0
elsif preset = 5 ; Shimmer
    numberOfGrains = 150
    grainDur = 0.060
    envelopeShape = 2
    panningMode = 2
    applyLFO = 1
    lfoFrequency = 0.25
    timeDistribution = 2
    grainSource = 2
    applyPitchShift = 1
    pitchShiftSemitones = 0
    pitchVariation = 7.0
elsif preset = 6 ; Long Resonance
    numberOfGrains = 15
    grainDur = 0.800
    envelopeShape = 1
    panningMode = 1
    applyLFO = 1
    lfoFrequency = 0.15
    timeDistribution = 2
    grainSource = 2
    applyPitchShift = 1
    pitchShiftSemitones = 0
    pitchVariation = 3.0
endif

# ---------- Fixed internal parameters ----------
scale_peak = 0.99
play_after_processing = 1

# ---------- Safety ----------
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# ---------- Input Validation ----------
if grainDur <= 0
    exitScript: "Grain duration must be greater than 0."
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
numberOfChannels  = Get number of channels

# Safe aliases
dur = duration
sr  = samplingFrequency

# Use custom output duration if specified
if outputDuration > 0
    dur = outputDuration
endif

writeInfoLine: "Rendering ", numberOfGrains, " grains from: ", sound$, newline$
appendInfoLine: "Input duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Output duration: ", fixed$(dur, 3), " s"
appendInfoLine: newline$, "ID", tab$, "t_out(s)", tab$, "t_src(s)", tab$, "amp", tab$, "pan", tab$, "pitch"

# ---------- Create empty stereo mix ----------
Create Sound from formula: "Granular_mix", 2, 0, dur, sr, "0"
mixedSound = selected("Sound")

# ---------- Generate and mix grains ----------
for i from 1 to numberOfGrains
    # Output time distribution
    if timeDistribution = 1 ; Linear
        if numberOfGrains = 1
            outputTime = 0.5 * duration
        else
            outputTime = (i - 1) / (numberOfGrains - 1) * duration
        endif
    elsif timeDistribution = 2 ; Exponential
        if numberOfGrains = 1
            outputTime = 0.5 * duration
        else
            t = (i - 1) / (numberOfGrains - 1)
            outputTime = duration * (1 - exp(-3 * t)) / (1 - exp(-3))
        endif
    else ; Random
        outputTime = randomUniform(0, duration)
    endif

    # Source time selection
    if grainSource = 1 ; Sequential
        if numberOfGrains = 1
            sourceTime = 0.5 * duration
        else
            sourceTime = (i - 1) / (numberOfGrains - 1) * duration
        endif
    else ; Random
        maxSourceStart = duration - grainDur
        if maxSourceStart < 0
            maxSourceStart = 0
        endif
        sourceTime = randomUniform(0, maxSourceStart)
    endif

    # Ensure source time is valid
    if sourceTime < 0
        sourceTime = 0
    endif
    if sourceTime + grainDur > duration
        sourceTime = duration - grainDur
        if sourceTime < 0
            sourceTime = 0
        endif
    endif

    # Extract grain from source
    selectObject: sound
    Extract part: sourceTime, sourceTime + grainDur, "rectangular", 1, "no"
    extractedGrain = selected("Sound")

    # Apply pitch shift if enabled
    pitchShift = 1.0
    if applyPitchShift
        semitones = pitchShiftSemitones + randomUniform(-pitchVariation, pitchVariation)
        pitchShift = 2^(semitones / 12)
        
        selectObject: extractedGrain
        Resample: sr * pitchShift, 50
        resampledGrain = selected("Sound")
        selectObject: extractedGrain
        Remove
        selectObject: resampledGrain
        extractedGrain = selected("Sound")
    endif

    # Get current grain duration
    selectObject: extractedGrain
    currentGrainDur = Get total duration

    # Apply envelope
    selectObject: extractedGrain
    if envelopeShape = 1 ; Hann
        Formula: "self * 0.5 * (1 - cos(2*pi*x/'currentGrainDur'))"
    elsif envelopeShape = 2 ; Gaussian
        Formula: "self * exp(-0.5 * ((x - 'currentGrainDur'/2) / ('currentGrainDur'/4))^2)"
    endif

    # Amplitude with optional LFO
    grainAmp = 1.0
    if applyLFO
        lfoValue = 0.5 * (1 + sin(2 * 3.14 * lfoFrequency * outputTime))
        grainAmp = grainAmp * lfoValue
    endif

    selectObject: extractedGrain
    Formula: "self * 'grainAmp'"

    # Panning
    if panningMode = 1 ; Position-derived
        pan = sourceTime / duration
    elsif panningMode = 2 ; Random
        pan = randomUniform(0, 1)
    else ; Fixed
        pan = fixedPan
    endif
    gl = sqrt(1 - pan)
    gr = sqrt(pan)

    # Convert to stereo
    selectObject: extractedGrain
    nChannels = Get number of channels
    
    if nChannels = 1
        Convert to stereo: gl, gr
        stereoGrain = selected("Sound")
    else
        Extract one channel: 1
        chanL = selected("Sound")
        selectObject: extractedGrain
        Extract one channel: 2
        chanR = selected("Sound")
        
        selectObject: chanL
        Formula: "self * 'gl'"
        selectObject: chanR
        Formula: "self * 'gr'"
        
        selectObject: chanL
        plusObject: chanR
        Combine to stereo
        stereoGrain = selected("Sound")
        selectObject: chanL
        Remove
        selectObject: chanR
        Remove
        selectObject: extractedGrain
        Remove
    endif
    
    # Rename for formula reference
    selectObject: stereoGrain
    Rename: "Grain_'i'"
    grainName$ = "Grain_'i'"
    
    # Get grain properties
    grainDuration = Get total duration
    grainEnd = outputTime + grainDuration
    
    # Make sure grain fits within duration
    if grainEnd > dur
        grainEnd = dur
        grainDuration = grainEnd - outputTime
    endif
    
    # Only process if grain is valid
    if grainDuration > 0 and outputTime >= 0
        # Extract the portion of mix where grain will be added
        selectObject: mixedSound
        Extract part: outputTime, grainEnd, "rectangular", 1, "no"
        mixPart = selected("Sound")
        
        # Extract matching portion from grain (should be same length)
        selectObject: stereoGrain
        Extract part: 0, grainDuration, "rectangular", 1, "no"
        grainPart = selected("Sound")
        
        # Add them together channel by channel
        selectObject: mixPart
        Extract one channel: 1
        Rename: "MixL"
        chanMixL = selected("Sound")
        
        selectObject: mixPart
        Extract one channel: 2
        Rename: "MixR"
        chanMixR = selected("Sound")
        
        selectObject: grainPart
        Extract one channel: 1
        Rename: "GrainL"
        chanGrainL = selected("Sound")
        
        selectObject: grainPart
        Extract one channel: 2
        Rename: "GrainR"
        chanGrainR = selected("Sound")
        
        # Add L channel using Formula
        selectObject: chanMixL
        Formula: "self + Sound_GrainL[]"
        
        # Add R channel using Formula
        selectObject: chanMixR
        Formula: "self + Sound_GrainR[]"
        
        # Combine summed channels back to stereo
        selectObject: chanMixL
        plusObject: chanMixR
        Combine to stereo
        summedPart = selected("Sound")
        
        # Put the summed part back into the mix
        # We'll do this by creating three parts: before, summed, after
        if outputTime > 0
            selectObject: mixedSound
            Extract part: 0, outputTime, "rectangular", 1, "no"
            beforePart = selected("Sound")
        endif
        
        if grainEnd < dur
            selectObject: mixedSound
            Extract part: grainEnd, dur, "rectangular", 1, "no"
            afterPart = selected("Sound")
        endif
        
        # Concatenate: before + summed + after
        if outputTime > 0
            selectObject: beforePart
            plusObject: summedPart
            if grainEnd < dur
                plusObject: afterPart
            endif
            Concatenate
        elsif grainEnd < dur
            selectObject: summedPart
            plusObject: afterPart
            Concatenate
        else
            selectObject: summedPart
            Copy: "NewMix"
        endif
        newMix = selected("Sound")
        Rename: "Granular_mix"
        
        # Remove old mix and update reference
        selectObject: mixedSound
        Remove
        mixedSound = newMix
        
        # Cleanup temporary objects
        selectObject: mixPart
        Remove
        selectObject: grainPart
        Remove
        selectObject: chanMixL
        Remove
        selectObject: chanMixR
        Remove
        selectObject: chanGrainL
        Remove
        selectObject: chanGrainR
        Remove
        selectObject: summedPart
        Remove
        if outputTime > 0
            selectObject: beforePart
            Remove
        endif
        if grainEnd < dur
            selectObject: afterPart
            Remove
        endif
        
        # Log progress
        appendInfoLine: fixed$(i,0), tab$, fixed$(outputTime,3), tab$, fixed$(sourceTime,3), tab$, 
            ... fixed$(grainAmp,3), tab$, fixed$(pan,3), tab$, fixed$(pitchShift,3)
    else
        appendInfoLine: "Grain ", i, " skipped (out of bounds)"
    endif
    
    # Cleanup grain
    selectObject: stereoGrain
    Remove
        
    if i mod 20 = 0
        appendInfoLine: "  Processed ", i, " of ", numberOfGrains, " grains..."
    endif
endfor

# Final level
selectObject: mixedSound
Scale peak: scale_peak

# ---------- Optionally play ----------
if play_after_processing
    selectObject: mixedSound
    Play
endif

appendInfoLine: newline$, "Done. Created stereo Sound: 'Granular_mix'"