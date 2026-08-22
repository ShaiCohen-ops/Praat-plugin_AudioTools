# ============================================================
# Praat AudioTools - Intelligent_EQ_Adaptive_Bandpass.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.2 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Description:
#   Pitch-tracked adaptive bandpass filter.
#   The pass-band centre follows detected F0 after an optional
#   multiplier and frequency offset. Harmonic-focus presets target
#   existing spectral energy near F0, 2*F0, 3*F0, or F0/2.
#
#   Important:
#   - This script FILTERS existing energy; it does not synthesize
#     missing harmonics or subharmonics.
#   - Processing is mono. Multichannel input is mixed to mono.
#   - Unvoiced "Bypass" preserves the original amplitude unless
#     optional peak normalization is enabled.
#
# DSP:
#   1. Convert working copy to mono and shift work time to 0.
#   2. Track and smooth F0.
#   3. Zero-pad by one analysis window on each side.
#   4. Process 50%-overlapped Hann-windowed frames.
#   5. Apply Praat's zero-phase Hann-band filter in voiced frames.
#   6. Overlap-add, crop away padding, restore original start time.
#
# Category: Filter & Spectral Shaping
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
duration = Get total duration
sourceStart = Get start time
sampleRate = Get sampling frequency
numChannels = Get number of channels
numSourceSamples = Get number of samples
nyquist = sampleRate / 2

if duration < 0.05
    exitScript: "Sound too short (min 0.05 s)."
endif

# === USER PARAMETERS ===
form Intelligent EQ: Adaptive Bandpass v1.2
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Fundamental Extraction
        option 2nd Harmonic Focus
        option 3rd Harmonic Focus
        option Octave-Below Band Focus (existing energy)
        option Wide F0 Region
        option Pitch-Band Noise Reduction

    comment === Pitch Tracking ===
    positive Minimum_pitch_(Hz) 75
    positive Maximum_pitch_(Hz) 500
    positive Pitch_smoothing_(Hz) 10

    comment === Target Frequency ===
    real F0_multiplier 1.0
    comment (1.0=F0, 2.0=2nd harmonic, 0.5=octave-below band)
    real F0_offset_(Hz) 0.0
    comment (Hz offset added after multiplier)

    comment === Filter Parameters ===
    positive Bandwidth_val 100
    optionmenu Bandwidth_mode 1
        option Fixed full bandwidth (Hz)
        option Relative full bandwidth / centre
    positive Transition_width_(Hz) 50
    comment (Praat Hann-band smoothing width between pass and stop)

    comment === Unvoiced Handling ===
    optionmenu Unvoiced_mode 2
        option Bypass (pass original)
        option Attenuate
        option Mute
    real Unvoiced_attenuation_(dB) -18

    comment === Tracking / Speed ===
    optionmenu Quality 2
        option Draft (60ms window)
        option Standard (40ms window)
        option High tracking (25ms window)

    comment === Output ===
    real Scale_peak 0
    comment (0 = preserve natural level; >0 = normalize peak)
    boolean Show_visualization 1
    boolean Play_result 1
endform

# === PARAMETER VALIDATION ===
if minimum_pitch >= maximum_pitch
    exitScript: "Minimum pitch must be lower than maximum pitch."
endif
if maximum_pitch >= nyquist
    exitScript: "Maximum pitch must be below Nyquist (" + fixed$(nyquist, 1) + " Hz)."
endif
if bandwidth_mode = 2 and bandwidth_val <= 0
    exitScript: "Relative bandwidth must be greater than zero."
endif
if transition_width <= 0
    exitScript: "Transition width must be greater than zero."
endif
if unvoiced_attenuation > 0
    unvoiced_attenuation = 0
endif
if scale_peak < 0
    scale_peak = 0
endif
if scale_peak > 1
    scale_peak = 1
endif

# === APPLY PRESETS ===
if preset = 2
    f0_multiplier = 1.0
    f0_offset = 0
    bandwidth_val = 0.4
    bandwidth_mode = 2
    unvoiced_mode = 3
    pitch_smoothing = 10
    presetName$ = "Fundamental Extraction"
elsif preset = 3
    f0_multiplier = 2.0
    f0_offset = 0
    bandwidth_val = 0.3
    bandwidth_mode = 2
    unvoiced_mode = 2
    pitch_smoothing = 12
    presetName$ = "2nd Harmonic Focus"
elsif preset = 4
    f0_multiplier = 3.0
    f0_offset = 0
    bandwidth_val = 0.25
    bandwidth_mode = 2
    unvoiced_mode = 2
    pitch_smoothing = 12
    presetName$ = "3rd Harmonic Focus"
elsif preset = 5
    # Focuses existing energy around F0/2. Does not synthesize a subharmonic.
    f0_multiplier = 0.5
    f0_offset = 0
    bandwidth_val = 0.5
    bandwidth_mode = 2
    unvoiced_mode = 2
    pitch_smoothing = 15
    presetName$ = "Octave-Below Band Focus"
elsif preset = 6
    # Broad region centred on F0; not a harmonic filter bank.
    f0_multiplier = 1.0
    f0_offset = 0
    bandwidth_val = 2.0
    bandwidth_mode = 2
    unvoiced_mode = 1
    pitch_smoothing = 15
    presetName$ = "Wide F0 Region"
elsif preset = 7
    # Narrow F0-following band plus attenuation of unvoiced material.
    f0_multiplier = 1.0
    f0_offset = 0
    bandwidth_val = 150
    bandwidth_mode = 1
    unvoiced_mode = 2
    unvoiced_attenuation = -24
    pitch_smoothing = 10
    presetName$ = "Pitch-Band Noise Reduction"
else
    presetName$ = "Custom"
endif

# === ANALYSIS WINDOW ===
if quality = 1
    requestedWindowDur = 0.060
    qualityName$ = "Draft"
elsif quality = 2
    requestedWindowDur = 0.040
    qualityName$ = "Standard"
else
    requestedWindowDur = 0.025
    qualityName$ = "High tracking"
endif

# Use an even number of samples so the 50% hop is sample-aligned.
winSamples = round(requestedWindowDur * sampleRate)
if winSamples < 4
    winSamples = 4
endif
if winSamples mod 2 <> 0
    winSamples = winSamples + 1
endif
hopSamples = winSamples / 2
windowDur = winSamples / sampleRate
hopDur = hopSamples / sampleRate

# === SETUP / INFO ===
clearinfo
writeInfoLine: "=== Intelligent EQ: Adaptive Bandpass v1.2 ==="
appendInfoLine: "Input: ", originalName$, "  |  ", fixed$(duration, 2), " s  |  ", sampleRate, " Hz  |  ", numChannels, " ch"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Target: F0 x ", fixed$(f0_multiplier, 2), " + ", fixed$(f0_offset, 1), " Hz"
if bandwidth_mode = 2
    appendInfoLine: "Bandwidth: ", fixed$(bandwidth_val, 3), " x centre (full width)"
else
    appendInfoLine: "Bandwidth: ", fixed$(bandwidth_val, 1), " Hz (full width)"
endif
appendInfoLine: "Transition width: ", fixed$(transition_width, 1), " Hz"
appendInfoLine: "Window: ", fixed$(windowDur * 1000, 2), " ms  |  hop: ", fixed$(hopDur * 1000, 2), " ms"
if numChannels > 1
    appendInfoLine: "Processing: mixed to mono from ", numChannels, " channels"
endif
appendInfoLine: ""

# ============================================================
# STEP 1: PREPARE MONO WORKING SOURCE
# ============================================================
appendInfoLine: "[1/4] Preparing source..."

selectObject: originalID
if numChannels > 1
    monoSource = Convert to mono
else
    monoSource = Copy: "AT_IEQ_source"
endif

# Work internally from t=0 regardless of the source Sound time domain.
selectObject: monoSource
Shift times to: "start time", 0
Rename: "AT_IEQ_source"

# ============================================================
# STEP 2: PITCH ANALYSIS & SMOOTHING
# ============================================================
appendInfoLine: "[2/4] Tracking pitch..."

selectObject: monoSource
pitchRaw = To Pitch: hopDur / 2, minimum_pitch, maximum_pitch

selectObject: pitchRaw
pitch = Smooth: pitch_smoothing
Rename: "AT_IEQ_pitch"
removeObject: pitchRaw

selectObject: pitch
meanPitch = Get mean: 0, 0, "Hertz"
minPitch = Get minimum: 0, 0, "Hertz", "Parabolic"
maxPitchDetected = Get maximum: 0, 0, "Hertz", "Parabolic"

numPitchFrames = Get number of frames
voicedCount = 0
for i from 1 to numPitchFrames
    selectObject: pitch
    pVal = Get value in frame: i, "Hertz"
    if pVal <> undefined
        voicedCount = voicedCount + 1
    endif
endfor
if numPitchFrames > 0
    voicedPercent = voicedCount / numPitchFrames * 100
else
    voicedPercent = 0
endif

if meanPitch = undefined
    displayMeanPitch = (minimum_pitch + maximum_pitch) / 2
    displayMinPitch = minimum_pitch
    displayMaxPitch = maximum_pitch
else
    displayMeanPitch = meanPitch
    displayMinPitch = minPitch
    displayMaxPitch = maxPitchDetected
endif

meanTarget = displayMeanPitch * f0_multiplier + f0_offset
minTarget = displayMinPitch * f0_multiplier + f0_offset
maxTarget = displayMaxPitch * f0_multiplier + f0_offset

appendInfoLine: "  Voiced: ", fixed$(voicedPercent, 1), "%"
if meanPitch <> undefined
    appendInfoLine: "  Mean F0: ", fixed$(meanPitch, 1), " Hz"
    appendInfoLine: "  Mean target: ", fixed$(meanTarget, 1), " Hz"
else
    appendInfoLine: "  No voiced F0 detected; unvoiced mode will determine output."
endif
appendInfoLine: ""

# ============================================================
# STEP 3: PAD + ADAPTIVE FILTER + OVERLAP-ADD
# ============================================================
appendInfoLine: "[3/4] Adaptive filtering..."

# One full window of zero padding on each side keeps the original
# signal away from the incomplete OLA boundary region.
padSamples = winSamples
padDur = padSamples / sampleRate
paddedSamples = numSourceSamples + 2 * padSamples
paddedDuration = paddedSamples / sampleRate

monoID$ = string$(monoSource)
Create Sound from formula: "AT_IEQ_padded", 1, 0, paddedDuration, sampleRate,
    ... "if col > " + string$(padSamples)
    ... + " and col <= " + string$(padSamples + numSourceSamples)
    ... + " then object[" + monoID$ + ", 1, col - " + string$(padSamples) + "] else 0 fi"
paddedSource = selected("Sound")

Create Sound from formula: "AT_IEQ_ola", 1, 0, paddedDuration, sampleRate, "0"
olaBuffer = selected("Sound")

attenFactor = 10 ^ (unvoiced_attenuation / 20)

numFrames = floor((paddedDuration - windowDur) / hopDur) + 1
processedVoiced = 0
processedUnvoiced = 0

for i from 1 to numFrames
    frameStart = (i - 1) * hopDur
    frameEnd = frameStart + windowDur
    frameMidPadded = (frameStart + frameEnd) / 2
    frameMidOriginal = frameMidPadded - padDur

    # Query pitch only inside the original signal range.
    currentPitch = undefined
    if frameMidOriginal >= 0 and frameMidOriginal <= duration
        selectObject: pitch
        currentPitch = Get value at time: frameMidOriginal, "Hertz", "linear"
    endif
    isVoiced = (currentPitch <> undefined and currentPitch > 0)

    selectObject: paddedSource
    frameSound = Extract part: frameStart, frameEnd, "Hanning", 1, "no"

    if isVoiced
        processedVoiced = processedVoiced + 1

        targetFreq = currentPitch * f0_multiplier + f0_offset
        targetFreq = max(20, min(nyquist - 50, targetFreq))

        if bandwidth_mode = 2
            effectiveBW = targetFreq * bandwidth_val
        else
            effectiveBW = bandwidth_val
        endif
        effectiveBW = max(1, effectiveBW)

        lowBound = max(0, targetFreq - effectiveBW / 2)
        highBound = min(nyquist, targetFreq + effectiveBW / 2)

        # Keep a non-empty pass band.
        if highBound <= lowBound
            lowBound = max(0, targetFreq - 0.5)
            highBound = min(nyquist, targetFreq + 0.5)
        endif

        selectObject: frameSound
        filtered = Filter (pass Hann band): lowBound, highBound, transition_width
    else
        processedUnvoiced = processedUnvoiced + 1
        selectObject: frameSound
        filtered = Copy: "AT_IEQ_unvoiced"
        if unvoiced_mode = 2
            Formula: "self * " + string$(attenFactor)
        elsif unvoiced_mode = 3
            Formula: "0"
        endif
    endif

    # Add using sample-aligned offset. The extracted frame is shifted
    # to t=0 so object indexing is independent of absolute frame time.
    selectObject: filtered
    Shift times to: "start time", 0
    frameID$ = string$(filtered)
    startSample = 1 + (i - 1) * hopSamples
    endSample = startSample + winSamples - 1
    if endSample > paddedSamples
        endSample = paddedSamples
    endif
    startTime = (startSample - 1) / sampleRate
    endTime = endSample / sampleRate

    selectObject: olaBuffer
    Formula (part): startTime, endTime, 1, 1,
        ... "self + object[" + frameID$ + ", 1, col - " + string$(startSample - 1) + "]"

    removeObject: frameSound, filtered
endfor

# Crop away OLA boundary padding.
selectObject: olaBuffer
cropped = Extract part: padDur, padDur + duration, "rectangular", 1, "no"
Rename: originalName$ + "_adaptive_EQ"
outputSound = selected("Sound")

# Restore original time domain.
Shift times to: "start time", sourceStart

# Optional peak normalization. Default 0 preserves natural level.
if scale_peak > 0
    Scale peak: scale_peak
endif

appendInfoLine: "  Frames: ", numFrames, "  |  voiced: ", processedVoiced, "  |  unvoiced/pad: ", processedUnvoiced
appendInfoLine: ""

# ============================================================
# STEP 4: VISUALIZATION - Praat AudioTools house style
# ============================================================
if show_visualization
    appendInfoLine: "[4/4] Creating AudioTools visualization..."

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    vizDuration = min(duration, 12)
    vizMaxHz = min(8000, nyquist)
    if meanPitch <> undefined
        vizTrackMax = min(nyquist, max(500, max(maxPitchDetected, maxTarget) * 1.35))
        vizTrackMin = max(0, min(minPitch, minTarget) * 0.7)
    else
        vizTrackMin = 0
        vizTrackMax = min(nyquist, maximum_pitch * 1.5)
    endif
    if vizTrackMax <= vizTrackMin
        vizTrackMax = vizTrackMin + 500
    endif

    # Input display uses the mono working source already shifted to 0.
    selectObject: monoSource
    vizInput = Copy: "AT_IEQ_viz_input"

    # Output display copy shifted to 0 for direct visual alignment.
    selectObject: outputSound
    vizOutput = Copy: "AT_IEQ_viz_output"
    Shift times to: "start time", 0

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Intelligent EQ: Adaptive Bandpass v1.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: vizInput
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: vizOutput
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Paired spectrograms
    # ----------------------------------------------------------
    if vizMaxHz > 100
        Select outer viewport: 0, 4.1, 2.24, 3.64
        Select inner viewport: 0.55, 3.85, 2.34, 3.54
        selectObject: vizInput
        To Spectrogram: 0.02, vizMaxHz, 0.005, 20, "Gaussian"
        vizSpecIn = selected("Spectrogram")
        Paint: 0, vizDuration, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
        removeObject: vizSpecIn
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Hz"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Input spectrogram"

        Select outer viewport: 4.1, 8, 2.24, 3.64
        Select inner viewport: 4.40, 7.65, 2.34, 3.54
        selectObject: vizOutput
        To Spectrogram: 0.02, vizMaxHz, 0.005, 20, "Gaussian"
        vizSpecOut = selected("Spectrogram")
        Paint: 0, vizDuration, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
        removeObject: vizSpecOut
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Hz"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Processed output"
    endif

    # ----------------------------------------------------------
    # Adaptive tracking diagnostic
    # gray = detected F0; blue = target centre; dotted = pass edges
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.72, 4.92
    Select inner viewport: 0.55, 7.65, 3.80, 4.84
    Axes: 0, vizDuration, vizTrackMin, vizTrackMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDuration, vizTrackMin, vizTrackMax

    selectObject: pitch
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1.5
    Draw: 0, vizDuration, vizTrackMin, vizTrackMax, "no"

    # Draw target centre and pass-band edges from sampled pitch values.
    trackStep = max(hopDur, vizDuration / 250)
    prevT = undefined
    prevCenter = undefined
    prevLow = undefined
    prevHigh = undefined
    t = 0
    while t <= vizDuration
        selectObject: pitch
        pv = Get value at time: t, "Hertz", "linear"
        if pv <> undefined
            centerV = max(20, min(nyquist - 50, pv * f0_multiplier + f0_offset))
            if bandwidth_mode = 2
                bwV = max(1, centerV * bandwidth_val)
            else
                bwV = max(1, bandwidth_val)
            endif
            lowV = max(0, centerV - bwV / 2)
            highV = min(nyquist, centerV + bwV / 2)

            if prevCenter <> undefined
                Select inner viewport: 0.55, 7.65, 3.80, 4.84
                Axes: 0, vizDuration, vizTrackMin, vizTrackMax
                Colour: "{0.25, 0.50, 0.82}"
                Line width: 2
                Solid line
                Draw line: prevT, prevCenter, t, centerV
                Colour: "{0.55, 0.68, 0.84}"
                Line width: 1
                Dotted line
                Draw line: prevT, prevLow, t, lowV
                Draw line: prevT, prevHigh, t, highV
            endif
            prevT = t
            prevCenter = centerV
            prevLow = lowV
            prevHigh = highV
        else
            prevT = undefined
            prevCenter = undefined
            prevLow = undefined
            prevHigh = undefined
        endif
        t = t + trackStep
    endwhile

    Solid line
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Tracking  |  gray=F0  blue=target  dotted=pass-band edges"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.02, 5.82
    Select inner viewport: 0.55, 7.65, 5.08, 5.76
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    if bandwidth_mode = 2
        bwText$ = fixed$(bandwidth_val, 3) + " x centre"
    else
        bwText$ = fixed$(bandwidth_val, 1) + " Hz"
    endif
    if scale_peak > 0
        peakText$ = fixed$(scale_peak, 2)
    else
        peakText$ = "off"
    endif
    if unvoiced_mode = 1
        unvoicedText$ = "bypass"
    elsif unvoiced_mode = 2
        unvoicedText$ = "attenuate " + fixed$(unvoiced_attenuation, 0) + " dB"
    else
        unvoicedText$ = "mute"
    endif

    Text: 0.02, "left", 0.52, "half",
        ... "Target: F0 x " + fixed$(f0_multiplier, 2) + " + " + fixed$(f0_offset, 1) + " Hz"
        ... + "  |  BW: " + bwText$
        ... + "  |  transition: " + fixed$(transition_width, 1) + " Hz"
    Text: 0.02, "left", 0.25, "half",
        ... "Voiced: " + fixed$(voicedPercent, 1) + "%"
        ... + "  |  unvoiced: " + unvoicedText$
        ... + "  |  input: " + string$(numChannels) + " ch -> mono"
        ... + "  |  peak norm: " + peakText$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizInput, vizOutput
else
    appendInfoLine: "[4/4] Visualization disabled."
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# CLEANUP / OUTPUT
# ============================================================
removeObject: monoSource, pitch, paddedSource, olaBuffer

selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "Complete."
appendInfoLine: "Output: ", originalName$, "_adaptive_EQ"
appendInfoLine: "Natural level preserved: ", if scale_peak = 0 then "yes" else "no (peak normalized)" fi

if play_result
    Play
endif