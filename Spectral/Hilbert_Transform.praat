# ============================================================
# Praat AudioTools - Hilbert_Transform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.6 (2026)
# License: MIT License
#
# Description:
#   Extracts the analytic-signal magnitude with a Hilbert transform, reduces it
#   to a SLOW dynamic contour E(t), and derives a bounded correction gain from
#   the reversed target contour E(T-t):
#
#       g(t) = clamp(E(T-t) / E(t)) ^ reverse_amount
#
#   The carrier order is unchanged, but its slow dynamics are driven toward the
#   time-reversed source dynamics. This is a defined reverse-dynamics mapping,
#   not raw envelope multiplication or audio-rate amplitude modulation.
#
#   The raw Hilbert magnitude is intentionally NOT applied directly. Broadband
#   and polyphonic material contains rapid beating in that magnitude; reversing
#   and multiplying those fluctuations creates sidebands/roughness. v0.6 smooths
#   analytic energy x^2+H{x}^2 forward/backward, then takes the square root to
#   obtain a stable slow contour before the reverse-dynamics mapping.
#
#   For multichannel input, the highest-RMS channel drives one common contour;
#   all original channels remain intact, so stereo phase relationships are kept.
#
# Changelog v0.6 (2026):
#   - MUSICAL REDESIGN: removed the v0.4/v0.5 bipolar envelope high-pass path.
#     It was a colour/ring-modulation mechanism rather than a clean reverse
#     envelope and was the main source of audible distortion.
#   - QUALITY: the raw Hilbert magnitude now passes through zero-delay-like
#     forward/backward exponential smoothing. Envelope_smoothing_ms controls the
#     time constant; this suppresses audio-rate beating without moving attacks.
#   - CORRECT MAPPING: v0.5 multiplied the carrier by E(T-t), yielding the
#     product E(t)E(T-t), not a reversed output envelope. v0.6 uses the ratio
#     E(T-t)/E(t), so the estimated output dynamics actually move toward the
#     reversed target.
#   - MUSICAL CONTROL: Max_correction_dB bounds boosts/cuts; Reverse_amount is a
#     log-domain depth (0 = unity gain, 1 = full bounded reverse mapping).
#   - PRESERVED: exact-length Hilbert transform, explicit DC/Nyquist handling,
#     strongest-channel analysis driver, original-rate multichannel carrier.
#   - VIZ: updated only because the mechanism changed. It shows raw Hilbert
#     magnitude, current/target slow contours, and reports the bounded gain range.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Hilbert Reverse Dynamics v0.6
    optionmenu Preset: 1
        option Custom
        option Subtle Reverse Swell
        option Strong Reverse Attack
        option Pad-like Bloom
        option Percussive Reverse
        option Gentle Fade-In
        option Dramatic Swell
    comment === Reverse Dynamic Contour ===
    positive Envelope_smoothing_ms 120
    comment (time constant; 60-300 ms is clean, very small values become rougher)
    positive Envelope_exponent 1.0
    comment (1 = unchanged; < 1 = gentler; > 1 = stronger dynamic contrast)
    positive Max_correction_dB 12
    comment (maximum boost/cut used to reach the reversed target)
    real Reverse_amount 0.75
    comment (0 = original dynamics, 1 = full bounded reverse-dynamics mapping)
    comment === Output ===
    real Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    envelope_smoothing_ms = 180
    envelope_exponent = 0.85
    max_correction_dB = 6
    reverse_amount = 0.40
    presetName$ = "SubtleSwell"
elsif preset = 3
    envelope_smoothing_ms = 90
    envelope_exponent = 1.35
    max_correction_dB = 12
    reverse_amount = 0.85
    presetName$ = "StrongReverse"
elsif preset = 4
    envelope_smoothing_ms = 260
    envelope_exponent = 1.15
    max_correction_dB = 10
    reverse_amount = 0.80
    presetName$ = "PadBloom"
elsif preset = 5
    envelope_smoothing_ms = 55
    envelope_exponent = 1.20
    max_correction_dB = 9
    reverse_amount = 0.70
    presetName$ = "PercussiveReverse"
elsif preset = 6
    envelope_smoothing_ms = 320
    envelope_exponent = 0.80
    max_correction_dB = 6
    reverse_amount = 0.55
    presetName$ = "GentleFadeIn"
elsif preset = 7
    envelope_smoothing_ms = 140
    envelope_exponent = 1.60
    max_correction_dB = 15
    reverse_amount = 1.00
    presetName$ = "DramaticSwell"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
original_sr = Get sampling frequency
original_duration = Get total duration
numChannels = Get number of channels

if envelope_smoothing_ms <= 0
    exitScript: "Envelope smoothing must be greater than 0 ms."
endif
if max_correction_dB <= 0 or max_correction_dB > 36
    exitScript: "Max correction must be greater than 0 and at most 36 dB."
endif
if reverse_amount < 0 or reverse_amount > 1
    exitScript: "Reverse amount must be between 0 and 1."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be greater than 0 and at most 1."
endif

clearinfo
writeInfoLine: "=== Hilbert Reverse Dynamics v0.6 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " s"
appendInfoLine: "Sample rate: ", original_sr, " Hz | channels: ", numChannels
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Envelope smoothing: ", fixed$(envelope_smoothing_ms, 1), " ms"
appendInfoLine: "Envelope exponent: ", fixed$(envelope_exponent, 2)
appendInfoLine: "Max correction: +/-", fixed$(max_correction_dB, 1), " dB | reverse amount: ", fixed$(reverse_amount, 2)
appendInfoLine: ""

# ============================================================
# STEP 1: PREPARE ENVELOPE ANALYSIS SOURCE
# ============================================================

# The envelope is common to all output channels. For multichannel input,
# choose the highest-RMS channel instead of summing to mono, so anti-phase
# material cannot cancel before Hilbert analysis.
if numChannels = 1
    selectObject: originalID
    workingID = Copy: "hilbert_analysis"
    analysisChannel = 1
else
    workingID = 0
    bestRms = -1
    analysisChannel = 1
    for ch from 1 to numChannels
        selectObject: originalID
        tempCh = Extract one channel: ch
        selectObject: tempCh
        tempRms = Get root-mean-square: 0, 0
        if tempRms > bestRms
            if workingID <> 0
                removeObject: workingID
            endif
            workingID = tempCh
            bestRms = tempRms
            analysisChannel = ch
        else
            removeObject: tempCh
        endif
    endfor
    selectObject: workingID
    Rename: "hilbert_analysis_ch" + string$(analysisChannel)
    appendInfoLine: "Envelope driver: channel ", analysisChannel,
        ... " (highest RMS ", fixed$(bestRms, 4), ")"
endif

# Full-quality analysis at the source sample rate. The former 32 kHz path
# was both bandwidth-reducing and slower in representative tests.
selectObject: workingID
analysis_sr = Get sampling frequency
appendInfoLine: "Envelope analysis SR: ", analysis_sr, " Hz (full quality)"


# ============================================================
# STEP 2: HILBERT TRANSFORM
# ============================================================

appendInfo: "Computing Hilbert transform..."

# Reflect-pad the ANALYSIS signal before the full-file Hilbert transform. A raw
# FFT Hilbert transform assumes periodic continuation; on a non-periodic file this
# creates edge ringing that becomes a false gain event after time reversal. Mirror
# padding keeps the carrier untouched while making the analysis boundary gentler.
tau = envelope_smoothing_ms / 1000
analysisPad = min(original_duration, max(0.10, min(0.50, 3*tau)))
paddedDur = original_duration + 2*analysisPad
padStr$ = fixed$(analysisPad, 12)
durStr$ = fixed$(original_duration, 12)
padPlusDurStr$ = fixed$(analysisPad + original_duration, 12)
workingIdStr$ = string$(workingID)
Create Sound from formula: "hilbert_analysis_padded", 1, 0, paddedDur, analysis_sr, "Object_" + workingIdStr$ + "(if x < " + padStr$ + " then " + padStr$ + " - x else if x <= " + padPlusDurStr$ + " then x - " + padStr$ + " else " + durStr$ + " - (x - " + padPlusDurStr$ + ") fi fi)"
paddedAnalysisID = selected("Sound")
analysisSamples = Get number of samples
analysisEven = (analysisSamples mod 2 = 0)
analysisEven$ = string$(analysisEven)

# Exact-length spectrum: no zero-padding is required for envelope extraction.
selectObject: paddedAnalysisID
spectrumID = To Spectrum: "no"
specID$ = string$(spectrumID)

# H{x}: multiply positive-frequency bins by -i.
# For X = a + ib, -iX = b - ia. DC is zero; for even N the Nyquist
# bin is real-only and its Hilbert component is also set to zero.
selectObject: spectrumID
hilbertSpecID = Copy: "hilbert_spec"

selectObject: hilbertSpecID
Formula: "if col=1 or (" + analysisEven$ + " and col=ncol) then 0 else if row=1 then object[" + specID$ + ",2,col] else -object[" + specID$ + ",1,col] fi fi"

selectObject: hilbertSpecID
hilbertSoundID = To Sound
Override sampling frequency: analysis_sr
Rename: "hilbert_padded"

appendInfoLine: " done"

# ============================================================
# STEP 3: EXTRACT / SMOOTH / SHAPE REVERSE DYNAMIC CONTOUR
# ============================================================

appendInfo: "Extracting and smoothing Hilbert envelope..."

# Analytic magnitude A(t) = sqrt(x(t)^2 + H{x}(t)^2).
selectObject: workingID
rawEnvID = Copy: "hilbert_env_raw"
hilbertIdStr$ = string$(hilbertSoundID)
selectObject: rawEnvID
Formula: "sqrt(self^2 + Object_" + hilbertIdStr$ + "(x + " + padStr$ + ")^2)"

# Smooth analytic ENERGY rather than amplitude. Averaging x^2+H{x}^2 first and
# taking the square root afterwards is substantially more stable on steady tones
# while retaining the slow dynamic contour.
selectObject: rawEnvID
energyEnvID = Copy: "hilbert_env_energy"
selectObject: energyEnvID
Formula: "self^2"

# Forward/backward one-pole smoothing. The forward pass deliberately uses the
# already-written previous sample as recursive state. Reversing through a frozen
# source and repeating the pass gives a zero-delay-like two-sided contour.
smoothA = exp(-1 / (tau * analysis_sr))
smoothB = 1 - smoothA
smoothA$ = fixed$(smoothA, 15)
smoothB$ = fixed$(smoothB, 15)

selectObject: energyEnvID
smoothFwdID = Copy: "hilbert_env_smooth_fwd"
selectObject: smoothFwdID
Formula: "if col=1 then self else " + smoothB$ + "*self + " + smoothA$ + "*self[row,col-1] fi"

# Reverse to run the same causal smoother from the opposite edge.
selectObject: smoothFwdID
smoothRevID = Copy: "hilbert_env_smooth_rev"
smoothFwdStr$ = string$(smoothFwdID)
selectObject: smoothRevID
Formula: "object[" + smoothFwdStr$ + ",row,ncol-col+1]"
selectObject: smoothRevID
Formula: "if col=1 then self else " + smoothB$ + "*self + " + smoothA$ + "*self[row,col-1] fi"

# Reverse back: this is the slow positive dynamic contour.
selectObject: smoothRevID
smoothEnvID = Copy: "hilbert_env_smooth"
smoothRevStr$ = string$(smoothRevID)
selectObject: smoothEnvID
Formula: "sqrt(max(0,object[" + smoothRevStr$ + ",row,ncol-col+1]))"

# Normalize only AFTER smoothing, so rapid Hilbert beating cannot dominate the
# dynamic mapping. Shape the estimated source contour E(t) on 0..1.
selectObject: smoothEnvID
smoothPeak = Get absolute extremum: 0, 0, "None"
if smoothPeak > 1e-15
    Scale peak: 1
endif
expStr$ = fixed$(envelope_exponent, 8)
Formula: "max(1e-8,self)^" + expStr$

# Freeze E(t) and create the target E(T-t).
selectObject: smoothEnvID
contourVizID = Copy: "hilbert_contour_current"
contourStr$ = string$(contourVizID)
selectObject: contourVizID
reversedContourID = Copy: "hilbert_contour_target_reversed"
selectObject: reversedContourID
Formula: "object[" + contourStr$ + ",row,ncol-col+1]"

# Correction ratio target/current, symmetrically bounded in dB. Reverse_amount
# is a log-domain depth: ratio^0 = 1, ratio^1 = full bounded correction.
maxRatio = 10^(max_correction_dB/20)
minRatio = 1/maxRatio
maxRatioStr$ = fixed$(maxRatio, 12)
minRatioStr$ = fixed$(minRatio, 12)
amountStr$ = fixed$(reverse_amount, 8)
selectObject: reversedContourID
appliedModID = Copy: "hilbert_reverse_gain"
selectObject: appliedModID
Formula: "min(" + maxRatioStr$ + ",max(" + minRatioStr$ + ",self/max(1e-8,object[" + contourStr$ + ",row,col])))^" + amountStr$

gainMin = Get minimum: 0, 0, "None"
gainMax = Get maximum: 0, 0, "None"

removeObject: smoothFwdID, smoothRevID, smoothEnvID
appendInfoLine: " done"

# ============================================================
# STEP 4: APPLY REVERSED DYNAMIC CONTOUR TO ORIGINAL CARRIER
# ============================================================

appendInfo: "Applying reversed dynamic contour to original-rate carrier..."

appliedModIdStr$ = string$(appliedModID)

# One positive, slowly varying correction gain is applied equally to every
# original channel. It preserves native stereo/multichannel phase and cannot
# invert polarity. The slow estimated output envelope moves toward E(T-t).
selectObject: originalID
finalSoundID = Copy: "final"
selectObject: finalSoundID
Formula: "self * Object_" + appliedModIdStr$ + "(x)"

appendInfoLine: " done"

# ============================================================
# STEP 5: FINALIZE
# ============================================================

selectObject: finalSoundID
Rename: originalName$ + "_reverseDynamics_" + presetName$
resultPeakBefore = Get absolute extremum: 0, 0, "None"
if resultPeakBefore > 1e-15
    Scale peak: scale_peak
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Hilbert Reverse Dynamics: " + originalName$ + " [" + presetName$ + "]"
    
    # Original and processed waveform use ONE amplitude scale.
    selectObject: originalID
    srcPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: finalSoundID
    outPeakViz = Get absolute extremum: 0, 0, "None"
    wavePeakViz = 1.05 * max(srcPeakViz, outPeakViz)
    if wavePeakViz < 1e-9
        wavePeakViz = 1
    endif

    # Original waveform
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.5, 3.7, 0.75, 1.85
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, -wavePeakViz, wavePeakViz, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Original"
    Text left: "yes", "Amp"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.5, 7.7, 0.75, 1.85
    selectObject: finalSoundID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, -wavePeakViz, wavePeakViz, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Reverse Dynamics Applied"
    Text left: "yes", "Amp"
    
    # Raw Hilbert magnitude, current slow contour E(t), and reversed target E(T-t).
    Select outer viewport: 0, 8, 2.2, 3.8
    Select inner viewport: 0.6, 7.6, 2.4, 3.6

    selectObject: rawEnvID
    rawEnvPeakViz = Get absolute extremum: 0, 0, "None"
    envTop = 1.05 * max(1, rawEnvPeakViz)

    selectObject: rawEnvID
    Colour: "{0.68, 0.68, 0.70}"
    Line width: 1
    Draw: 0, original_duration, 0, envTop, "no", "Curve"

    selectObject: contourVizID
    Colour: "{0.90, 0.50, 0.20}"
    Line width: 2
    Draw: 0, original_duration, 0, envTop, "no", "Curve"

    selectObject: reversedContourID
    Colour: "{0.20, 0.65, 0.42}"
    Line width: 1.5
    Draw: 0, original_duration, 0, envTop, "no", "Curve"

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Hilbert magnitude -> E(t) current contour -> E(T-t) target contour"
    Text left: "yes", "Norm. envelope"
    Text bottom: "yes", "Time (s)"

    # Hilbert signal (quadrature component)
    Select outer viewport: 0, 4, 4.0, 5.4
    Select inner viewport: 0.5, 3.7, 4.15, 5.25
    selectObject: hilbertSoundID
    Colour: "{0.6, 0.3, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Hilbert quadrature of envelope-driver channel " + string$(analysisChannel)
    Text left: "yes", "Amp"
    
    # Info panel
    Select outer viewport: 4, 8, 4.0, 5.4
    Select inner viewport: 4.4, 7.8, 4.15, 5.25
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.8, "half", "Preset: " + presetName$
    Text: 0.05, "left", 0.55, "half", "Smoothing: " + fixed$(envelope_smoothing_ms, 0) + " ms"
    Text: 0.05, "left", 0.3, "half", "Exponent: " + fixed$(envelope_exponent, 2)
    Text: 0.55, "left", 0.8, "half", "Reverse amount: " + fixed$(reverse_amount, 2)
    Text: 0.55, "left", 0.55, "half", "Gain range: " + fixed$(gainMin, 2) + ".." + fixed$(gainMax, 2) + "x"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: paddedAnalysisID, spectrumID, hilbertSpecID, hilbertSoundID, rawEnvID, energyEnvID, contourVizID, reversedContourID, appliedModID, workingID

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_reverseDynamics_", presetName$

selectObject: finalSoundID
if play_result
    Play
endif
selectObject: finalSoundID
