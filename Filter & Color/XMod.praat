# ============================================================
# Praat AudioTools - XMod.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - ENHANCED VISUALIZATION
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cross-modulation effects with comprehensive visualization.
#   Ring Modulation, Amplitude Modulation, Rhythmic Gating.
# ============================================================

form XMod - Cross Modulation v1.0
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
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    mod_type = 1
    mod_source = 1
    mod_frequency = 440
    mod_depth = 1.0
    presetName$ = "RingMetallic"
elsif preset = 3
    mod_type = 1
    mod_source = 1
    mod_frequency = 80
    mod_depth = 1.0
    presetName$ = "RingDeep"
elsif preset = 4
    mod_type = 2
    mod_source = 1
    mod_frequency = 1000
    mod_depth = 0.8
    presetName$ = "AMRadio"
elsif preset = 5
    mod_type = 2
    mod_source = 1
    mod_frequency = 6
    mod_depth = 0.7
    presetName$ = "Tremolo"
elsif preset = 6
    mod_type = 3
    mod_source = 2
    mod_frequency = 10
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 2
    release = 2
    presetName$ = "FastStutter"
elsif preset = 7
    mod_type = 3
    mod_source = 2
    mod_frequency = 2
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 10
    release = 10
    presetName$ = "SlowPulse"
elsif preset = 8
    mod_type = 3
    mod_source = 2
    mod_frequency = 12.5
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 1
    release = 1
    presetName$ = "Helicopter"
elsif preset = 9
    mod_type = 3
    mod_source = 2
    mod_frequency = 2
    mod_depth = 0.9
    duty_cycle = 0.3
    attack = 5
    release = 80
    presetName$ = "Sidechain"
else
    presetName$ = "Custom"
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

startTime = stopwatch

writeInfoLine: "=== XMod - Cross Modulation v1.0 ==="
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
    # Ring Modulation
    selectObject: outputSound
    Formula: "self * (Sound_modulator[] * " + depthStr$ + " + (1 - " + depthStr$ + "))"
    
elsif mod_type = 2
    # Amplitude Modulation
    selectObject: outputSound
    Formula: "self * (1 + " + depthStr$ + " * Sound_modulator[]) / 2"
    
elsif mod_type = 3
    # Rhythmic Gate with envelope
    selectObject: modulatorMono
    gateEnv = Copy: "envelope"
    
    selectObject: gateEnv
    Formula: "(self + 1) / 2"
    
    smoothFreq = 1 / max(attackSec, releaseSec, 0.005)
    smoothFreq = min(smoothFreq, sampleRate / 4)
    smoothFreq = max(smoothFreq, 5)
    
    selectObject: gateEnv
    To Spectrum: "yes"
    envSpec = selected("Spectrum")
    
    smoothStr$ = fixed$(smoothFreq, 2)
    selectObject: envSpec
    Formula: "if x < " + smoothStr$ + " then self else self * exp(-((x-" + smoothStr$ + ")/" + smoothStr$ + ")^2) fi"
    
    smoothedEnv = To Sound
    
    selectObject: smoothedEnv
    envCropped = Extract part: 0, duration, "rectangular", 1, "no"
    
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
    
    selectObject: outputSound
    Formula: "self * Sound_gateenv[] * " + depthStr$ + " + self * (1 - " + depthStr$ + ")"
    
    # Keep envelope for visualization
    finalEnvelope = envCropped
    
    removeObject: gateEnv, envSpec, smoothedEnv
endif

# ============================================================
# FINALIZE
# ============================================================
selectObject: outputSound
Rename: originalName$ + "_xmod_" + presetName$
Scale peak: 0.95

processingTime = stopwatch - startTime

# ============================================================
# ENHANCED VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "XMod: " + originalName$ + " [" + modTypeNames$[mod_type] + "]"
    
    # === ROW 1: WAVEFORMS ===
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.5
    Select inner viewport: 0.5, 3.7, 0.7, 1.4
    selectObject: carrierMono
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original (Carrier)"
    Text left: "yes", "Amp"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.5
    Select inner viewport: 4.5, 7.7, 0.7, 1.4
    selectObject: outputSound
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Processed"
    Text left: "yes", "Amp"
    
    # === ROW 2: MODULATOR ===
    Select outer viewport: 0, 8, 1.7, 2.8
    Select inner viewport: 0.6, 7.6, 1.8, 2.7
    
    # Display 3-5 cycles or max 0.5s
    displayDur = max(3 / mod_frequency, 0.15)
    displayDur = min(displayDur, 0.5, duration)
    
    Axes: 0, displayDur, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, displayDur, -1.2, 1.2
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, displayDur, 0
    
    # Draw modulator waveform
    if mod_source <> 5
        Colour: "{0.9, 0.5, 0.2}"
        Line width: 2
        
        step = displayDur / 500
        period = 1 / mod_frequency
        
        plotTime = 0
        phase = 0
        
        # Calculate initial value
        if mod_source = 1
            modVal = sin(2 * pi * phase)
        elsif mod_source = 2
            cyclePos = phase - floor(phase)
            modVal = if cyclePos < duty_cycle then 1 else -1 fi
        elsif mod_source = 3
            cyclePos = phase - floor(phase)
            modVal = if cyclePos < 0.5 then 4 * cyclePos - 1 else 3 - 4 * cyclePos fi
        elsif mod_source = 4
            cyclePos = phase - floor(phase)
            modVal = 2 * cyclePos - 1
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
                modVal = if cyclePos < duty_cycle then 1 else -1 fi
            elsif mod_source = 3
                cyclePos = phase - floor(phase)
                modVal = if cyclePos < 0.5 then 4 * cyclePos - 1 else 3 - 4 * cyclePos fi
            elsif mod_source = 4
                cyclePos = phase - floor(phase)
                modVal = 2 * cyclePos - 1
            endif
            
            Draw line: prevTime, prevVal, plotTime, modVal
            prevTime = plotTime
            prevVal = modVal
            plotTime = plotTime + step
        endwhile
    else
        # External modulator - draw actual sound
        selectObject: modulatorMono
        Colour: "{0.9, 0.5, 0.2}"
        Line width: 2
        Draw: 0, displayDur, 0, 0, "no", "Curve"
    endif
    
    # Gate envelope overlay
    if mod_type = 3
        selectObject: finalEnvelope
        Colour: "{0.3, 0.7, 0.4}"
        Line width: 1.5
        Dotted line
        Draw: 0, displayDur, 0, 1.2, "no", "Curve"
        Solid line
    endif
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Modulator: " + modSourceNames$[mod_source]
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # === ROW 3: SPECTROGRAMS ===
    # Original spectrogram
    Select outer viewport: 0, 4, 3.0, 4.4
    Select inner viewport: 0.5, 3.7, 3.1, 4.3
    selectObject: carrierMono
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original Spectrum"
    Text left: "yes", "Freq (Hz)"
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 3.0, 4.4
    Select inner viewport: 4.5, 7.7, 3.1, 4.3
    selectObject: outputSound
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    procSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: procSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Processed Spectrum"
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # === INFO PANEL ===
    Select outer viewport: 0, 8, 4.6, 5.3
    Select inner viewport: 0.5, 7.7, 4.65, 5.25
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    
    # Build info string
    if mod_source <> 5
        infoStr$ = "Frequency: " + fixed$(mod_frequency, 1) + " Hz | Depth: " + fixed$(mod_depth * 100, 0) + "%"
    else
        infoStr$ = "External Modulator | Depth: " + fixed$(mod_depth * 100, 0) + "%"
    endif
    
    if mod_type = 3
        infoStr$ = infoStr$ + " | Duty: " + fixed$(duty_cycle * 100, 0) + "% | A/R: " + fixed$(attack, 0) + "/" + fixed$(release, 0) + "ms"
    endif
    
    infoStr$ = infoStr$ + " | Time: " + fixed$(processingTime, 2) + "s"
    
    Text: 0.5, "centre", 0.5, "half", infoStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    
    # Cleanup envelope if exists
    if mod_type = 3
        removeObject: finalEnvelope
    endif
endif

# Cleanup
removeObject: carrierMono, modulatorMono

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Type: ", modTypeNames$[mod_type]
appendInfoLine: "Source: ", modSourceNames$[mod_source]
if mod_source <> 5
    appendInfoLine: "Frequency: ", mod_frequency, " Hz"
endif
appendInfoLine: "Depth: ", fixed$(mod_depth * 100, 0), "%"
appendInfoLine: "Output: ", originalName$, "_xmod_", presetName$

if play_result
    selectObject: outputSound
    Play
endif

selectObject: carrierID

