# ============================================================
# Praat AudioTools - XMod.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form XMod - Cross Modulation
    optionmenu Preset: 1
        option Custom
        option Ring Mod - Metallic
        option Ring Mod - Deep
        option AM - Radio Style
        option AM - Tremolo
        option Gate - Fast Stutter
        option Gate - Slow Pulse
        option Gate - Helicopter
        option Sidechain Style
    comment === Modulation Type ===
    optionmenu Mod_type: 1
        option Ring Modulation
        option Amplitude Modulation (AM)
        option Rhythmic Gate
    comment === Modulator Source ===
    optionmenu Mod_source: 1
        option Sine Oscillator
        option Square Oscillator
        option Triangle Oscillator
        option Sawtooth Oscillator
        option Second Sound (select 2 sounds)
    comment === Oscillator Parameters ===
    positive Mod_frequency_(Hz) 10
    real Mod_depth 1.0
    comment (0-1 for AM/Gate, any value for Ring)
    comment === Gate Envelope ===
    positive Attack_(ms) 5
    positive Release_(ms) 5
    positive Duty_cycle 0.5
    comment (0-1, ratio of ON time per cycle)
    comment === Output ===
    boolean Draw_modulator 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Ring Mod - Metallic
    mod_type = 1
    mod_source = 1
    mod_frequency = 440
    mod_depth = 1.0
elsif preset = 3
    # Ring Mod - Deep
    mod_type = 1
    mod_source = 1
    mod_frequency = 80
    mod_depth = 1.0
elsif preset = 4
    # AM - Radio Style
    mod_type = 2
    mod_source = 1
    mod_frequency = 1000
    mod_depth = 0.8
elsif preset = 5
    # AM - Tremolo
    mod_type = 2
    mod_source = 1
    mod_frequency = 6
    mod_depth = 0.7
elsif preset = 6
    # Gate - Fast Stutter
    mod_type = 3
    mod_source = 2
    mod_frequency = 10
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 2
    release = 2
elsif preset = 7
    # Gate - Slow Pulse
    mod_type = 3
    mod_source = 2
    mod_frequency = 2
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 10
    release = 10
elsif preset = 8
    # Gate - Helicopter
    mod_type = 3
    mod_source = 2
    mod_frequency = 12.5
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 1
    release = 1
elsif preset = 9
    # Sidechain Style
    mod_type = 3
    mod_source = 2
    mod_frequency = 2
    mod_depth = 0.9
    duty_cycle = 0.3
    attack = 5
    release = 80
endif

# ============================================================
# INPUT VALIDATION
# ============================================================
numSounds = numberOfSelected("Sound")

if mod_source = 5
    if numSounds <> 2
        exitScript: "Please select exactly 2 Sound objects for cross-modulation."
    endif
    carrierID = selected("Sound", 1)
    modulatorSoundID = selected("Sound", 2)
else
    if numSounds <> 1
        exitScript: "Please select exactly one Sound object."
    endif
    carrierID = selected("Sound")
endif

selectObject: carrierID
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

if duration < 0.01
    exitScript: "Sound too short."
endif

# Convert attack/release to seconds
attackSec = attack / 1000
releaseSec = release / 1000

writeInfoLine: "=== XMod - Cross Modulation ==="
appendInfoLine: "Carrier: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: ""

modTypeNames$[1] = "Ring Modulation"
modTypeNames$[2] = "Amplitude Modulation"
modTypeNames$[3] = "Rhythmic Gate"

modSourceNames$[1] = "Sine"
modSourceNames$[2] = "Square"
modSourceNames$[3] = "Triangle"
modSourceNames$[4] = "Sawtooth"
modSourceNames$[5] = "Second Sound"

# ============================================================
# DRAW MODULATOR
# ============================================================
if draw_modulator
    Erase all
    Select outer viewport: 0, 6, 0, 3.5
    
    displayDur = max(3 / mod_frequency, 0.3)
    displayDur = min(displayDur, duration)
    
    Axes: 0, displayDur, -1.2, 1.2
    
    Colour: "Black"
    Draw inner box
    
    Colour: "{0.8,0.8,0.8}"
    Draw line: 0, 0, displayDur, 0
    
    Colour: "Blue"
    Line width: 2
    
    step = displayDur / 300
    plotTime = 0
    period = 1 / mod_frequency
    
    phase = 0
    if mod_source = 1
        modVal = sin(2 * pi * phase)
    elsif mod_source = 2
        cyclePos = phase - floor(phase)
        if cyclePos < duty_cycle
            modVal = 1
        else
            modVal = -1
        endif
    elsif mod_source = 3
        cyclePos = phase - floor(phase)
        if cyclePos < 0.5
            modVal = 4 * cyclePos - 1
        else
            modVal = 3 - 4 * cyclePos
        endif
    elsif mod_source = 4
        cyclePos = phase - floor(phase)
        modVal = 2 * cyclePos - 1
    else
        modVal = 0
    endif
    
    prevTime = 0
    prevVal = modVal
    
    plotTime = step
    while plotTime <= displayDur
        phase = plotTime * mod_frequency
        
        if mod_source = 1
            modVal = sin(2 * pi * phase)
        elsif mod_source = 2
            cyclePos = phase - floor(phase)
            if cyclePos < duty_cycle
                modVal = 1
            else
                modVal = -1
            endif
        elsif mod_source = 3
            cyclePos = phase - floor(phase)
            if cyclePos < 0.5
                modVal = 4 * cyclePos - 1
            else
                modVal = 3 - 4 * cyclePos
            endif
        elsif mod_source = 4
            cyclePos = phase - floor(phase)
            modVal = 2 * cyclePos - 1
        endif
        
        Draw line: prevTime, prevVal, plotTime, modVal
        prevTime = plotTime
        prevVal = modVal
        plotTime = plotTime + step
    endwhile
    
    Colour: "Black"
    Font size: 12
    Text: displayDur / 2, "Centre", 1.15, "Half", modTypeNames$[mod_type] + " - " + modSourceNames$[mod_source]
    
    Font size: 10
    Text: displayDur / 2, "Centre", -1.1, "Half", "Time (s)"
    
    Colour: "{0.4,0.4,0.4}"
    Font size: 9
    Text: displayDur * 0.15, "Centre", 1.05, "Half", "Freq: " + fixed$(mod_frequency, 1) + " Hz"
    Text: displayDur * 0.15, "Centre", 0.9, "Half", "Depth: " + fixed$(mod_depth * 100, 0) + "%"
    
    if mod_type = 3
        Text: displayDur * 0.85, "Centre", 1.05, "Half", "Duty: " + fixed$(duty_cycle * 100, 0) + "%"
        Text: displayDur * 0.85, "Centre", 0.9, "Half", "A/R: " + fixed$(attack, 0) + "/" + fixed$(release, 0) + " ms"
    endif
    
    Colour: "Black"
    Marks bottom every: 1, 0.1, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    
    Line width: 1
endif

# ============================================================
# PREPARE CARRIER
# ============================================================
selectObject: carrierID
if numChannels > 1
    carrierMono = Convert to mono
else
    carrierMono = Copy: "carrier"
endif

# ============================================================
# CREATE OR PREPARE MODULATOR
# ============================================================
if mod_source = 5
    selectObject: modulatorSoundID
    modulatorDur = Get total duration
    
    if modulatorDur < duration
        selectObject: modulatorSoundID
        modulatorMono = Copy: "modulator"
    else
        selectObject: modulatorSoundID
        modulatorMono = Extract part: 0, duration, "rectangular", 1, "no"
    endif
    
    selectObject: modulatorMono
    if Get number of channels > 1
        tmpMod = Convert to mono
        removeObject: modulatorMono
        modulatorMono = tmpMod
    endif
    
    selectObject: modulatorMono
    Scale peak: 1.0
    Rename: "modulator"
    
    appendInfoLine: "Modulator: Second sound"
else
    appendInfoLine: "Modulator: ", modSourceNames$[mod_source], " @ ", mod_frequency, " Hz"
    
    freqStr$ = fixed$(mod_frequency, 6)
    dutyStr$ = fixed$(duty_cycle, 6)
    
    if mod_source = 1
        modulatorMono = Create Sound from formula: "modulator", 1, 0, duration, sampleRate,
        ... "sin(2*pi*" + freqStr$ + "*x)"
    elsif mod_source = 2
        modulatorMono = Create Sound from formula: "modulator", 1, 0, duration, sampleRate,
        ... "if ((" + freqStr$ + "*x) mod 1) < " + dutyStr$ + " then 1 else -1 fi"
    elsif mod_source = 3
        modulatorMono = Create Sound from formula: "modulator", 1, 0, duration, sampleRate,
        ... "if ((" + freqStr$ + "*x) mod 1) < 0.5 then 4*((" + freqStr$ + "*x) mod 1)-1 else 3-4*((" + freqStr$ + "*x) mod 1) fi"
    elsif mod_source = 4
        modulatorMono = Create Sound from formula: "modulator", 1, 0, duration, sampleRate,
        ... "2*((" + freqStr$ + "*x) mod 1)-1"
    endif
endif

# ============================================================
# APPLY MODULATION
# ============================================================
appendInfoLine: ""
appendInfoLine: "Applying modulation..."

selectObject: carrierMono
Rename: "carrier"

selectObject: carrierMono
outputSound = Copy: "output"

depthStr$ = fixed$(mod_depth, 6)

if mod_type = 1
    # Ring Modulation: carrier * modulator
    selectObject: outputSound
    Formula: "self * (Sound_modulator[] * " + depthStr$ + " + (1 - " + depthStr$ + "))"
    
elsif mod_type = 2
    # Amplitude Modulation: carrier * (1 + depth * modulator) / 2
    selectObject: outputSound
    Formula: "self * (1 + " + depthStr$ + " * Sound_modulator[]) / 2"
    
elsif mod_type = 3
    # Rhythmic Gate with attack/release envelope
    
    # Create gate envelope from modulator
    # First convert bipolar to unipolar
    selectObject: modulatorMono
    gateEnv = Copy: "envelope"
    
    selectObject: gateEnv
    Formula: "(self + 1) / 2"
    
    # Apply smoothing for attack/release using convolution with exponential
    # Simpler approach: use a gentle low-pass to smooth transitions
    
    smoothFreq = 1 / max(attackSec, releaseSec, 0.005)
    smoothFreq = min(smoothFreq, sampleRate / 4)
    smoothFreq = max(smoothFreq, 5)
    
    selectObject: gateEnv
    To Spectrum: "yes"
    envSpec = selected("Spectrum")
    
    # Apply smoothing filter (lowpass)
    smoothStr$ = fixed$(smoothFreq, 2)
    selectObject: envSpec
    Formula: "if x < " + smoothStr$ + " then self else self * exp(-((x-" + smoothStr$ + ")/" + smoothStr$ + ")^2) fi"
    
    smoothedEnv = To Sound
    
    # Crop to original duration (FFT padding)
    selectObject: smoothedEnv
    envCropped = Extract part: 0, duration, "rectangular", 1, "no"
    
    # Normalize envelope to 0-1
    selectObject: envCropped
    minEnv = Get minimum: 0, 0, "None"
    maxEnv = Get maximum: 0, 0, "None"
    
    envRange = maxEnv - minEnv
    if envRange < 0.001
        envRange = 1
    endif
    
    minStr$ = fixed$(minEnv, 8)
    rangeStr$ = fixed$(envRange, 8)
    
    selectObject: envCropped
    Formula: "(self - " + minStr$ + ") / " + rangeStr$
    Rename: "gateenv"
    
    # Apply gate envelope to output
    selectObject: outputSound
    Formula: "self * Sound_gateenv[] * " + depthStr$ + " + self * (1 - " + depthStr$ + ")"
    
    # Cleanup envelope objects
    removeObject: gateEnv, envSpec, smoothedEnv, envCropped
endif

# ============================================================
# FINALIZE
# ============================================================
selectObject: outputSound
Rename: originalName$ + "_xmod"

Scale peak: 0.95

# Cleanup
removeObject: carrierMono, modulatorMono

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "Complete!"
appendInfoLine: "Type: ", modTypeNames$[mod_type]
appendInfoLine: "Source: ", modSourceNames$[mod_source]
if mod_source <> 5
    appendInfoLine: "Frequency: ", mod_frequency, " Hz"
endif
appendInfoLine: "Depth: ", fixed$(mod_depth * 100, 0), "%"

if play_result
    selectObject: outputSound
    Play
endif

