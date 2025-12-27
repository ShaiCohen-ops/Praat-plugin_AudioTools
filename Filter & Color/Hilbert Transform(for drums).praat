# ============================================================
# Praat AudioTools - Hilbert Transform Envelope.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Hilbert transform for envelope extraction and transient processing.
#   
# Output modes:
#   - Transient Enhanced: Original with punchier attacks
#   - Envelope Shaped: Original multiplied by its envelope
#   - Hilbert (90deg): Phase-shifted signal
#   - Raw Envelope: Low-frequency envelope signal (for analysis)
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Hilbert Transform Envelope
    optionmenu Preset: 1
        option Custom
        option Drum Punch (transient enhance)
        option Soft Attack (reduce transients)
        option Phase Shift (90 deg)
        option Gate Effect (envelope shape)
    optionmenu Output_mode: 1
        option Transient Enhanced
        option Envelope Shaped
        option Hilbert (90deg shift)
        option Raw Envelope (for analysis)
    real transient_amount 1.5
    comment (> 1 = punchier attacks, < 1 = softer attacks)
    real envelope_smoothing_ms 5
    real dry_wet_mix 1.0
    positive scale_peak 0.95
    boolean draw_visualization 1
    boolean play_after_processing 1
endform

# ============================================================
# Apply presets
# ============================================================
if preset$ = "Drum Punch (transient enhance)"
    output_mode = 1
    transient_amount = 2.0
    envelope_smoothing_ms = 2
elif preset$ = "Soft Attack (reduce transients)"
    output_mode = 1
    transient_amount = 0.5
    envelope_smoothing_ms = 10
elif preset$ = "Phase Shift (90 deg)"
    output_mode = 3
    transient_amount = 1.0
    envelope_smoothing_ms = 5
elif preset$ = "Gate Effect (envelope shape)"
    output_mode = 2
    transient_amount = 1.0
    envelope_smoothing_ms = 1
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
sampleRate = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels
nyquist = sampleRate / 2

if envelope_smoothing_ms < 0.1
    envelope_smoothing_ms = 0.1
endif
if transient_amount <= 0
    transient_amount = 0.1
endif
if dry_wet_mix < 0
    dry_wet_mix = 0
endif
if dry_wet_mix > 1
    dry_wet_mix = 1
endif

uniqueID$ = string$(randomInteger(10000, 99999))

if output_mode = 1
    modeName$ = "TransientEnhanced"
elif output_mode = 2
    modeName$ = "EnvelopeShaped"
elif output_mode = 3
    modeName$ = "Hilbert90"
else
    modeName$ = "RawEnvelope"
endif

# ============================================================
# Report
# ============================================================
writeInfoLine: "Hilbert Transform Envelope"
appendInfoLine: "=========================="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Output: ", modeName$
if output_mode = 1
    appendInfoLine: "Transient amount: ", transient_amount
endif
appendInfoLine: "Smoothing: ", envelope_smoothing_ms, " ms"
appendInfoLine: ""

# ============================================================
# Process
# ============================================================
appendInfoLine: "Computing Hilbert transform..."

if numChannels = 1
    # --- MONO PROCESSING ---
    selectObject: sound
    inputCopy = Copy: "input_" + uniqueID$
    
    # Create Hilbert transform via spectral phase shift
    selectObject: inputCopy
    To Spectrum: "yes"
    origSpec = selected("Spectrum")
    Rename: "origSpec_" + uniqueID$
    
    hilbertSpec = Copy: "hilbertSpec_" + uniqueID$
    Formula: "if row = 1 then Spectrum_origSpec_'uniqueID$'[2, col] else -Spectrum_origSpec_'uniqueID$'[1, col] fi"
    
    To Sound
    hilbert = selected("Sound")
    Rename: "hilbert_" + uniqueID$
    
    removeObject: origSpec, hilbertSpec
    
    # Compute envelope: sqrt(x^2 + H{x}^2)
    selectObject: inputCopy
    envelope = Copy: "envelope_" + uniqueID$
    Formula: "sqrt(self^2 + Sound_hilbert_'uniqueID$'(x)^2)"
    
    # Smooth envelope
    if envelope_smoothing_ms > 0
        smoothHz = 1000 / envelope_smoothing_ms
        if smoothHz < nyquist
            selectObject: envelope
            Filter (pass Hann band): 0, smoothHz, smoothHz * 0.2
            smoothed = selected("Sound")
            removeObject: envelope
            envelope = smoothed
            Rename: "envelope_" + uniqueID$
        endif
    endif
    
    # Normalize envelope to max = 1, with floor to avoid divide-by-zero
    selectObject: envelope
    envMax = Get maximum: 0, 0, "Sinc70"
    if envMax > 0.0001
        # Add small epsilon (0.001) to avoid zero values when raising to negative powers
        Formula: "max(0.001, self / 'envMax')"
    else
        Formula: "0.001"
    endif
    
    # Create output based on mode
    selectObject: inputCopy
    output = Copy: "output_" + uniqueID$
    
    if output_mode = 1
        # TRANSIENT ENHANCED: original * envelope^(amount-1)
        exponent = transient_amount - 1
        Formula: "self * Sound_envelope_'uniqueID$'(x)^'exponent'"
        
    elif output_mode = 2
        # ENVELOPE SHAPED: original * envelope
        Formula: "self * Sound_envelope_'uniqueID$'(x)"
        
    elif output_mode = 3
        # HILBERT (90 degree phase shift)
        Formula: "Sound_hilbert_'uniqueID$'(x)"
        
    else
        # RAW ENVELOPE
        Formula: "Sound_envelope_'uniqueID$'(x)"
    endif
    
    removeObject: inputCopy, hilbert, envelope
    result = output

else
    # --- STEREO PROCESSING ---
    selectObject: sound
    Extract one channel: 1
    leftIn = selected("Sound")
    Rename: "leftIn_" + uniqueID$
    
    selectObject: sound
    Extract one channel: 2
    rightIn = selected("Sound")
    Rename: "rightIn_" + uniqueID$
    
    # === Process LEFT ===
    selectObject: leftIn
    To Spectrum: "yes"
    specL = selected("Spectrum")
    Rename: "specL_" + uniqueID$
    
    hilbertSpecL = Copy: "hilbertSpecL_" + uniqueID$
    Formula: "if row = 1 then Spectrum_specL_'uniqueID$'[2, col] else -Spectrum_specL_'uniqueID$'[1, col] fi"
    
    To Sound
    hilbertL = selected("Sound")
    Rename: "hilbertL_" + uniqueID$
    
    removeObject: specL, hilbertSpecL
    
    # Envelope L
    selectObject: leftIn
    envelopeL = Copy: "envelopeL_" + uniqueID$
    Formula: "sqrt(self^2 + Sound_hilbertL_'uniqueID$'(x)^2)"
    
    if envelope_smoothing_ms > 0
        smoothHz = 1000 / envelope_smoothing_ms
        if smoothHz < nyquist
            selectObject: envelopeL
            Filter (pass Hann band): 0, smoothHz, smoothHz * 0.2
            smoothedL = selected("Sound")
            removeObject: envelopeL
            envelopeL = smoothedL
            Rename: "envelopeL_" + uniqueID$
        endif
    endif
    
    selectObject: envelopeL
    envMaxL = Get maximum: 0, 0, "Sinc70"
    if envMaxL > 0.0001
        Formula: "max(0.001, self / 'envMaxL')"
    else
        Formula: "0.001"
    endif
    
    # Output L
    selectObject: leftIn
    outputL = Copy: "outputL_" + uniqueID$
    
    if output_mode = 1
        exponent = transient_amount - 1
        Formula: "self * Sound_envelopeL_'uniqueID$'(x)^'exponent'"
    elif output_mode = 2
        Formula: "self * Sound_envelopeL_'uniqueID$'(x)"
    elif output_mode = 3
        Formula: "Sound_hilbertL_'uniqueID$'(x)"
    else
        Formula: "Sound_envelopeL_'uniqueID$'(x)"
    endif
    
    # === Process RIGHT ===
    selectObject: rightIn
    To Spectrum: "yes"
    specR = selected("Spectrum")
    Rename: "specR_" + uniqueID$
    
    hilbertSpecR = Copy: "hilbertSpecR_" + uniqueID$
    Formula: "if row = 1 then Spectrum_specR_'uniqueID$'[2, col] else -Spectrum_specR_'uniqueID$'[1, col] fi"
    
    To Sound
    hilbertR = selected("Sound")
    Rename: "hilbertR_" + uniqueID$
    
    removeObject: specR, hilbertSpecR
    
    # Envelope R
    selectObject: rightIn
    envelopeR = Copy: "envelopeR_" + uniqueID$
    Formula: "sqrt(self^2 + Sound_hilbertR_'uniqueID$'(x)^2)"
    
    if envelope_smoothing_ms > 0
        smoothHz = 1000 / envelope_smoothing_ms
        if smoothHz < nyquist
            selectObject: envelopeR
            Filter (pass Hann band): 0, smoothHz, smoothHz * 0.2
            smoothedR = selected("Sound")
            removeObject: envelopeR
            envelopeR = smoothedR
            Rename: "envelopeR_" + uniqueID$
        endif
    endif
    
    selectObject: envelopeR
    envMaxR = Get maximum: 0, 0, "Sinc70"
    if envMaxR > 0.0001
        Formula: "max(0.001, self / 'envMaxR')"
    else
        Formula: "0.001"
    endif
    
    # Output R
    selectObject: rightIn
    outputR = Copy: "outputR_" + uniqueID$
    
    if output_mode = 1
        exponent = transient_amount - 1
        Formula: "self * Sound_envelopeR_'uniqueID$'(x)^'exponent'"
    elif output_mode = 2
        Formula: "self * Sound_envelopeR_'uniqueID$'(x)"
    elif output_mode = 3
        Formula: "Sound_hilbertR_'uniqueID$'(x)"
    else
        Formula: "Sound_envelopeR_'uniqueID$'(x)"
    endif
    
    # Combine to stereo
    selectObject: outputL, outputR
    Combine to stereo
    result = selected("Sound")
    
    removeObject: leftIn, rightIn, hilbertL, hilbertR, envelopeL, envelopeR, outputL, outputR
endif

# ============================================================
# Dry/wet mix
# ============================================================
if dry_wet_mix < 1
    selectObject: result
    Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_'originalName$'(x)"
endif

selectObject: result
Scale peak: scale_peak
Rename: originalName$ + "_" + modeName$

finalOutput = selected("Sound")

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    Erase all
    
    selectObject: sound
    if numChannels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "origMono_" + uniqueID$
    endif
    
    selectObject: finalOutput
    if numChannels > 1
        resultMono = Convert to mono
    else
        resultMono = Copy: "resultMono_" + uniqueID$
    endif
    
    if duration > 10
        timeTick = 2
    elsif duration > 5
        timeTick = 1
    elsif duration > 2
        timeTick = 0.5
    else
        timeTick = 0.1
    endif
    
    # PANEL 1: Original waveform
    Select outer viewport: 0, 6, 0, 3
    Select inner viewport: 0.7, 5.8, 0.4, 2.7
    
    selectObject: origMono
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Black
    Draw inner box
    Text left: "yes", "Amplitude"
    Text top: "no", "##Original##"
    Marks bottom every: 1, timeTick, "yes", "yes", "no"
    
    # PANEL 2: Result
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.7, 5.8, 3.4, 5.7
    
    selectObject: resultMono
    Colour: "{0.2, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Black
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"
    Text top: "no", "##" + modeName$ + "##"
    Marks bottom every: 1, timeTick, "yes", "yes", "no"
    
    removeObject: origMono, resultMono
endif

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=========================="
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    Play
endif