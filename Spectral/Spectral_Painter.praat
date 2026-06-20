# ============================================================
# Praat AudioTools - Spectral Painter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026) - Dramatic preset overhaul
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Comprehensive spectral gain modulation.
#   True stereo preserved: each channel is processed independently.
#   Mono input optionally widened with a short Haas delay (stereo_output).
#
# ============================================================

form Spectral Painter v0.6
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Broken Radio (destroyed transmission)
        option Demon Voice (sub harmonics)
        option Glass Shatter (extreme high diffusion)
        option Black Hole (spectral vacuum)
        option Bit Rot (digital decay)
        option Insect Swarm (dense buzzing)
        option Frozen Cathedral (icy reverb texture)
        option Dying Machine (mechanical failure)
        option Quantum Tunnel (phasing voids)
        option Vocal Destroyer (formant chaos)
        option Thunder Rumble (infrasonic boost)
        option Crystal Fracture (shattered harmonics)
        option Toxic Waste (corrosive texture)
        option Ghost Signal (barely there)
        option Nuclear Meltdown (total spectral chaos)
        option Cello: Harmonic Comb (strip every other partial)
        option Cello: Spectral Smear (chaotic overtone redistribution)
        option Cello: Body Resonance Warp (dramatic formant sculpt)
    comment === MODULATION TYPE ===
    optionmenu Modulation_type: 1
        option Sine Wave (Linear)
        option Sine Wave (Logarithmic/Musical)
        option Triangle Wave
        option Square Wave (Stepped)
        option Sawtooth
        option Exponential
        option Logarithmic
        option Random (Per-Bin Diffusion)
        option Dual Sine (Interference)
    comment === BASIC PARAMETERS ===
    positive cutoff_frequency 15000
    positive modulation_center 1.0
    real modulation_depth 0.8
    positive modulation_frequency_divisor 150
    comment === ADVANCED ===
    real phase_offset 0.01
    positive second_divisor 300
    positive randomness_amount 0.3
    comment === TIME MODIFICATIONS ===
    positive tail_duration_s 1.0
    positive fade_out_duration_s 0.5
    comment === MIX ===
    real wet_dry_percent 100
    boolean stereo_output 1
    comment === VISUALIZATION ===
    boolean show_visualization 1
    comment === OUTPUT ===
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# ===== PRESET APPLICATION =====
presetName$ = "Custom"

if preset = 2
    modulation_type = 4
    modulation_center = 0.15
    modulation_depth = 2.8
    modulation_frequency_divisor = 8
    cutoff_frequency = 6000
    randomness_amount = 0.5
    phase_offset = 0.0
    presetName$ = "BrokenRadio"
elsif preset = 3
    modulation_type = 6
    modulation_center = 0.0
    modulation_depth = 5.0
    modulation_frequency_divisor = 30
    cutoff_frequency = 1200
    phase_offset = 0.0
    presetName$ = "DemonVoice"
elsif preset = 4
    modulation_type = 8
    modulation_center = 0.0
    modulation_depth = 3.0
    modulation_frequency_divisor = 6
    cutoff_frequency = 20000
    randomness_amount = 1.0
    phase_offset = 0.0
    presetName$ = "GlassShatter"
elsif preset = 5
    modulation_type = 4
    modulation_center = 0.0
    modulation_depth = 1.0
    modulation_frequency_divisor = 60
    cutoff_frequency = 18000
    phase_offset = 1.57
    presetName$ = "BlackHole"
elsif preset = 6
    modulation_type = 4
    modulation_center = 0.5
    modulation_depth = -2.5
    modulation_frequency_divisor = 18
    cutoff_frequency = 14000
    phase_offset = 0.0
    presetName$ = "BitRot"
elsif preset = 7
    modulation_type = 9
    modulation_center = 0.2
    modulation_depth = 2.5
    modulation_frequency_divisor = 9
    second_divisor = 10
    cutoff_frequency = 18000
    phase_offset = 0.0
    presetName$ = "InsectSwarm"
elsif preset = 8
    modulation_type = 2
    modulation_center = 0.3
    modulation_depth = 2.2
    modulation_frequency_divisor = 30
    cutoff_frequency = 20000
    phase_offset = 1.57
    presetName$ = "FrozenCathedral"
elsif preset = 9
    modulation_type = 5
    modulation_center = 0.5
    modulation_depth = -2.0
    modulation_frequency_divisor = 25
    cutoff_frequency = 8000
    phase_offset = 0.0
    presetName$ = "DyingMachine"
elsif preset = 10
    modulation_type = 9
    modulation_center = 0.0
    modulation_depth = 2.0
    modulation_frequency_divisor = 100
    second_divisor = 101
    cutoff_frequency = 16000
    phase_offset = 0.0
    presetName$ = "QuantumTunnel"
elsif preset = 11
    modulation_type = 8
    modulation_center = 0.3
    modulation_depth = 3.5
    modulation_frequency_divisor = 30
    cutoff_frequency = 5000
    randomness_amount = 0.9
    phase_offset = 0.0
    presetName$ = "VocalDestroyer"
elsif preset = 12
    modulation_type = 6
    modulation_center = 0.0
    modulation_depth = 8.0
    modulation_frequency_divisor = 20
    cutoff_frequency = 400
    phase_offset = 0.0
    presetName$ = "ThunderRumble"
elsif preset = 13
    modulation_type = 4
    modulation_center = 0.15
    modulation_depth = 3.0
    modulation_frequency_divisor = 5
    cutoff_frequency = 18000
    phase_offset = 0.0
    presetName$ = "CrystalFracture"
elsif preset = 14
    modulation_type = 8
    modulation_center = 0.0
    modulation_depth = -3.0
    modulation_frequency_divisor = 12
    cutoff_frequency = 12000
    randomness_amount = 0.95
    phase_offset = 0.0
    presetName$ = "ToxicWaste"
elsif preset = 15
    modulation_type = 1
    modulation_center = 0.05
    modulation_depth = 0.12
    modulation_frequency_divisor = 500
    cutoff_frequency = 8000
    phase_offset = 0.0
    presetName$ = "GhostSignal"
elsif preset = 16
    modulation_type = 8
    modulation_center = 0.0
    modulation_depth = 5.0
    modulation_frequency_divisor = 4
    cutoff_frequency = 20000
    randomness_amount = 1.0
    phase_offset = 0.0
    presetName$ = "NuclearMeltdown"
elsif preset = 17
    modulation_type = 4
    modulation_center = 0.0
    modulation_depth = 1.0
    modulation_frequency_divisor = 65
    cutoff_frequency = 16000
    phase_offset = 1.57
    presetName$ = "CelloHarmonicComb"
elsif preset = 18
    modulation_type = 8
    modulation_center = 0.2
    modulation_depth = 4.0
    modulation_frequency_divisor = 55
    cutoff_frequency = 16000
    randomness_amount = 1.0
    phase_offset = 0.0
    presetName$ = "CelloSpectralSmear"
elsif preset = 19
    modulation_type = 2
    modulation_center = 0.5
    modulation_depth = 3.5
    modulation_frequency_divisor = 60
    cutoff_frequency = 16000
    phase_offset = 0.78
    presetName$ = "CelloBodyResonanceWarp"
endif

# Set target sample rate to Full Quality ALWAYS
targetSR = 0
speedStr$ = "Full Quality"

# ===== PROCESSING SETUP =====
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSelectionID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalSelectionID
original_sr = Get sampling frequency
n_channels = Get number of channels

# Create working copy to protect original object
Copy: "working_original"
originalID = selected("Sound")

# ===== APPLY TAIL =====
if tail_duration_s > 0
    Create Sound from formula: "silence", n_channels, 0, tail_duration_s, original_sr, "0"
    silenceID = selected("Sound")
    selectObject: originalID
    plusObject: silenceID
    Concatenate
    paddedID = selected("Sound")
    removeObject: originalID, silenceID
    originalID = paddedID
endif

selectObject: originalID
duration = Get total duration

wet_dry_percent = max(0, min(100, wet_dry_percent))
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

startTime = stopwatch

writeInfoLine:  "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║        SPECTRAL PAINTER v0.6 (With Tail & Fade)            ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Speed:    ", speedStr$
appendInfoLine: "Type:     ", modulation_type
appendInfoLine: "Center:   ", modulation_center, "  |  Depth: ", modulation_depth
appendInfoLine: "Channels: ", n_channels
appendInfoLine: "Tail:     ", tail_duration_s, "s | Fade Out: ", fade_out_duration_s, "s"
appendInfoLine: "Wet/Dry:  ", fixed$(wet_dry_percent, 0), "%"
if modulation_type = 1 or modulation_type = 2
    appendInfoLine: "Phase offset active (Sine modes): ", phase_offset
else
    appendInfoLine: "Phase offset: NOT used for this modulation type"
endif
appendInfoLine: ""

# ===================================================================
# Build modulation formula string
# ===================================================================
cenStr$ = string$(modulation_center)
depStr$ = string$(modulation_depth)
divStr$ = string$(modulation_frequency_divisor)
cutStr$ = string$(cutoff_frequency)
phaseStr$ = string$(phase_offset)
rndStr$ = string$(randomness_amount)
secStr$ = string$(second_divisor)

if modulation_type = 1
    modName$ = "Sine (Linear)"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * sin(x / " + divStr$ + " + " + phaseStr$ + ")) else self fi"
elsif modulation_type = 2
    modName$ = "Sine (Log)"
    density_str$ = string$(modulation_frequency_divisor / 10)
    modFormula$ = "if x < " + cutStr$ + " and x > 1 then self * (" + cenStr$ + " + " + depStr$ + " * sin(ln(x) * " + density_str$ + " + " + phaseStr$ + ")) else self fi"
elsif modulation_type = 3
    modName$ = "Triangle"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (2 * abs((x / " + divStr$ + ") - floor((x / " + divStr$ + ") + 0.5)) - 1)) else self fi"
elsif modulation_type = 4
    modName$ = "Square"
    modFormula$ = "if x < " + cutStr$ + " then self * if sin(x / " + divStr$ + ") > 0 then " + cenStr$ + " + " + depStr$ + " else " + cenStr$ + " - " + depStr$ + " fi else self fi"
elsif modulation_type = 5
    modName$ = "Sawtooth"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (2 * ((x / " + divStr$ + ") - floor((x / " + divStr$ + ") + 0.5)))) else self fi"
elsif modulation_type = 6
    modName$ = "Exponential"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * exp(-x / " + divStr$ + ")) else self fi"
elsif modulation_type = 7
    modName$ = "Logarithmic"
    modFormula$ = "if x < " + cutStr$ + " and x > 1 then self * (" + cenStr$ + " + " + depStr$ + " * ln(1 + x / " + divStr$ + ")) else self fi"
elsif modulation_type = 8
    modName$ = "Random Diffusion"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (sin(x / " + divStr$ + ") + " + rndStr$ + " * randomGauss(0, 1))) else self fi"
else
    modName$ = "Dual Sine"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (sin(x / " + divStr$ + ") + 0.5 * sin(x / " + secStr$ + ")) / 1.5) else self fi"
endif

appendInfoLine: "Modulation: ", modName$

if targetSR > 0 and original_sr > targetSR
    workingSR = targetSR
else
    workingSR = original_sr
endif

# ===================================================================
# MAIN PROCESSING
# ===================================================================
appendInfoLine: "[1/4] Extracting and optionally downsampling channels..."

proc_channels = n_channels
if proc_channels > 2
    proc_channels = 2
endif

origSpecID = 0
specID = 0

for ch from 1 to proc_channels
    appendInfoLine: "  Channel ", ch, " of ", proc_channels, ":"

    selectObject: originalID
    if n_channels > 1
        Extract one channel: ch
        chSoundID = selected("Sound")
    else
        Copy: "ch_work"
        chSoundID = selected("Sound")
    endif

    if targetSR > 0 and original_sr > targetSR
        appendInfoLine: "    Downsampling to ", targetSR, " Hz..."
        selectObject: chSoundID
        Resample: targetSR, 50
        resampledID = selected("Sound")
        removeObject: chSoundID
        chSoundID = resampledID
    endif

    appendInfoLine: "    [2/4] Spectrum..."
    selectObject: chSoundID
    To Spectrum: "yes"
    chOrigSpecID = selected("Spectrum")

    Copy: "modulated_ch" + string$(ch)
    chSpecID = selected("Spectrum")

    if ch = 1
        origSpecID = chOrigSpecID
    else
        removeObject: chOrigSpecID
    endif

    appendInfoLine: "    [3/4] Modulation..."
    selectObject: chSpecID
    Formula: modFormula$

    if ch = 1
        specID = chSpecID
    endif

    appendInfoLine: "    [4/4] Reconstruct..."
    selectObject: chSpecID
    To Sound
    chResultID = selected("Sound")

    if ch > 1
        removeObject: chSpecID
    endif

    selectObject: chResultID
    resultDur = Get total duration
    if resultDur > duration
        Extract part: 0, duration, "rectangular", 1, "no"
        trimmedID = selected("Sound")
        removeObject: chResultID
        chResultID = trimmedID
    endif

    if targetSR > 0 and original_sr > targetSR
        appendInfoLine: "    Upsampling back to ", original_sr, " Hz..."
        selectObject: chResultID
        Resample: original_sr, 50
        upsampledID = selected("Sound")
        removeObject: chResultID
        chResultID = upsampledID
    endif

    resultCh'ch' = chResultID
    removeObject: chSoundID
endfor

# ===================================================================
# WET/DRY MIX
# ===================================================================
if dry_level > 0
    appendInfoLine: "  Mixing wet/dry..."

    for ch from 1 to proc_channels
        # Extract dry channel reference
        selectObject: originalID
        if n_channels > 1
            Extract one channel: ch
            dryChID = selected("Sound")
        else
            Copy: "dry_ch"
            dryChID = selected("Sound")
        endif

        # Single Formula: wet * result + dry * original
        selectObject: resultCh'ch'
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + string$(dryChID) + ", col] * " + string$(dry_level)

        removeObject: dryChID
    endfor
endif

# ===================================================================
# ASSEMBLE FINAL OUTPUT
# ===================================================================
if proc_channels = 2
    appendInfoLine: "  Combining stereo channels..."
    selectObject: resultCh1
    plusObject: resultCh2
    Combine to stereo
    resultID = selected("Sound")
    removeObject: resultCh1, resultCh2

elsif proc_channels = 1
    resultID = resultCh1

    if stereo_output
        appendInfoLine: "  Creating Haas-delay stereo from mono..."
        delay_samples = round(0.012 * original_sr)

        selectObject: resultID
        Copy: "left"
        leftID = selected("Sound")

        monoIdStr$ = string$(resultID)
        Create Sound from formula: "right", 1, 0, duration, original_sr,
            ... "if col > " + string$(delay_samples) + " then object[" + monoIdStr$ + ", 1, col - " + string$(delay_samples) + "] else 0 fi"
        rightID = selected("Sound")

        selectObject: leftID
        plusObject: rightID
        Combine to stereo
        stereoID = selected("Sound")

        removeObject: resultID, leftID, rightID
        resultID = stereoID
    endif
endif

# ===================================================================
# FADE OUT
# ===================================================================
if fade_out_duration_s > 0
    appendInfoLine: "  Applying fade out..."
    selectObject: resultID
    fadeStart = duration - fade_out_duration_s
    if fadeStart < 0
        fadeStart = 0
        fade_out_duration_s = duration
    endif
    Formula: "if x > " + string$(fadeStart) + " then self * (" + string$(duration) + " - x) / " + string$(fade_out_duration_s) + " else self fi"
endif

# ===================================================================
# SCALE & RENAME
# ===================================================================
selectObject: resultID
Rename: originalName$ + "_" + presetName$
Scale peak: scale_peak

# ===================================================================
# VISUALIZATION
# ===================================================================
if show_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all

    # Title
    Select outer viewport: 1, 8, 0.2, 0.7
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Painter: " + presetName$ + " (" + speedStr$ + ")"

    # Input waveform 
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.4, 3.8, 0.7, 1.5
    selectObject: originalSelectionID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Original spectrum
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.4, 7.8, 0.7, 1.5
    selectObject: origSpecID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, cutoff_frequency, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"

    # Result waveform
    Select outer viewport: 0, 4, 1.8, 2.8
    Select inner viewport: 0.4, 3.8, 1.9, 2.7
    selectObject: resultID
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Modulated spectrum
    Select outer viewport: 4, 8, 1.8, 2.8
    Select inner viewport: 4.4, 7.8, 1.9, 2.7
    selectObject: specID
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, cutoff_frequency, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mod.spectrum (ch1, pre-mix)"
    Text bottom: "yes", "Frequency (Hz)"
    
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1

    minGain = modulation_center - abs(modulation_depth) - 0.2
    maxGain = modulation_center + abs(modulation_depth) + 0.2
    if minGain > -0.3
        minGain = -0.3
    endif
    if maxGain < 1.5
        maxGain = 1.5
    endif

    Axes: 0, cutoff_frequency, minGain, maxGain
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, cutoff_frequency, minGain, maxGain

    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 1, cutoff_frequency, 1

    if minGain < 0
        Colour: "{1, 0.8, 0.8}"
        Draw line: 0, 0, cutoff_frequency, 0
    endif

    Colour: "{0.2, 0.5, 0.8}"
    Line width: 1.5

    numPoints = 200
    freqStep = cutoff_frequency / numPoints

    for i from 1 to numPoints
        freq = (i - 1) * freqStep + 1

        if modulation_type = 1
            gain = modulation_center + modulation_depth * sin(freq / modulation_frequency_divisor + phase_offset)
        elsif modulation_type = 2
            if freq > 1
                density = modulation_frequency_divisor / 10
                gain = modulation_center + modulation_depth * sin(ln(freq) * density + phase_offset)
            else
                 gain = modulation_center
            endif
        elsif modulation_type = 3
            gain = modulation_center + modulation_depth * (2 * abs((freq / modulation_frequency_divisor) - floor((freq / modulation_frequency_divisor) + 0.5)) - 1)
        elsif modulation_type = 4
            if sin(freq / modulation_frequency_divisor) > 0
                gain = modulation_center + modulation_depth
            else
                gain = modulation_center - modulation_depth
            endif
        elsif modulation_type = 5
            gain = modulation_center + modulation_depth * (2 * ((freq / modulation_frequency_divisor) - floor((freq / modulation_frequency_divisor) + 0.5)))
        elsif modulation_type = 6
            gain = modulation_center + modulation_depth * exp(-freq / modulation_frequency_divisor)
        elsif modulation_type = 7
            if freq > 1
                gain = modulation_center + modulation_depth * ln(1 + freq / modulation_frequency_divisor)
            else
                gain = modulation_center
            endif
        elsif modulation_type = 8
            gain = modulation_center + modulation_depth * sin(freq / modulation_frequency_divisor)
        else
            gain = modulation_center + modulation_depth * (sin(freq / modulation_frequency_divisor) + 0.5 * sin(freq / second_divisor)) / 1.5
        endif

        if i = 1
            prevFreq = freq
            prevGain = gain
        else
            Draw line: prevFreq, prevGain, freq, gain
            prevFreq = freq
             prevGain = gain
        endif
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7

    if modulation_type = 8
        Text left: "yes", "Gain (~approx, random noise not shown)"
    else
        Text left: "yes", "Gain"
    endif
    Text bottom: "yes", "Frequency (Hz)"

    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"

    processingTime = stopwatch - startTime

    param_text$ = "Center: " + fixed$(modulation_center, 2) +
        ... " | Depth: " + fixed$(modulation_depth, 2) +
        ... " | Divisor: " + string$(modulation_frequency_divisor) +
        ... " | Tail: " + fixed$(tail_duration_s, 2) + "s" +
        ... " | Fade: " + fixed$(fade_out_duration_s, 2) + "s" +
        ... " | Time: " + fixed$(processingTime, 2) + "s"

    Text: 0.5, "centre", 0.5, "half", param_text$

    Font size: 10
    Colour: "Black"
endif

# ===================================================================
# CLEANUP
# ===================================================================
# We clean up originalID (which is the padded working copy), 
# leaving the user's actual sound untouched in the Objects list.
removeObject: origSpecID, specID, originalID

processingTime = stopwatch - startTime

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    Play
endif

selectObject: resultID
# ============================================================
# END OF SCRIPT
# ============================================================
