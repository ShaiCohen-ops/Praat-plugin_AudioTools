# ============================================================
# Praat AudioTools - Hilbert_Transform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025) - Fixed syntax, added visualization
# License: MIT License
#
# Description:
#   Extracts the amplitude envelope using Hilbert transform
#   (analytic signal), then applies it reversed in time.
#   Creates "backwards attack" or "reverse reverb" effects.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Hilbert Time-Reversed Envelope v0.3
    optionmenu Preset: 1
        option Custom
        option Subtle Reverse Swell
        option Strong Reverse Attack
        option Pad-like Bloom
        option Percussive Reverse
        option Gentle Fade-In
        option Dramatic Swell
    comment === Processing ===
    boolean Use_downsampling 1
    positive Processing_sample_rate 32000
    comment === Envelope Shaping ===
    boolean Apply_envelope_sharpening 0
    positive Sharpening_exponent 0.8
    comment (< 1 = sharper, > 1 = smoother)
    comment === High-Pass Filter ===
    positive Highpass_cutoff 50
    positive Highpass_smoothing 10
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    # Subtle Reverse Swell
    apply_envelope_sharpening = 0
    highpass_cutoff = 30
    highpass_smoothing = 10
    presetName$ = "SubtleSwell"
elsif preset = 3
    # Strong Reverse Attack
    apply_envelope_sharpening = 1
    sharpening_exponent = 0.6
    highpass_cutoff = 80
    highpass_smoothing = 20
    presetName$ = "StrongReverse"
elsif preset = 4
    # Pad-like Bloom
    apply_envelope_sharpening = 1
    sharpening_exponent = 1.5
    highpass_cutoff = 20
    highpass_smoothing = 5
    presetName$ = "PadBloom"
elsif preset = 5
    # Percussive Reverse
    apply_envelope_sharpening = 1
    sharpening_exponent = 0.4
    highpass_cutoff = 100
    highpass_smoothing = 30
    presetName$ = "PercussiveReverse"
elsif preset = 6
    # Gentle Fade-In
    apply_envelope_sharpening = 1
    sharpening_exponent = 2.0
    highpass_cutoff = 20
    highpass_smoothing = 5
    presetName$ = "GentleFadeIn"
elsif preset = 7
    # Dramatic Swell
    apply_envelope_sharpening = 1
    sharpening_exponent = 0.5
    highpass_cutoff = 60
    highpass_smoothing = 15
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

clearinfo
writeInfoLine: "=== Hilbert Time-Reversed Envelope v0.3 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " s"
appendInfoLine: "Sample rate: ", original_sr, " Hz"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
if apply_envelope_sharpening
    appendInfoLine: "Sharpening: ", sharpening_exponent
endif
appendInfoLine: "Highpass: ", highpass_cutoff, " Hz"
appendInfoLine: ""

# ============================================================
# STEP 1: PREPARE
# ============================================================

selectObject: originalID
if numChannels > 1
    workingID = Convert to mono
else
    workingID = Copy: "working"
endif

# Downsample if requested
selectObject: workingID
current_sr = Get sampling frequency

if use_downsampling and processing_sample_rate < current_sr
    downsampledID = Resample: processing_sample_rate, 50
    removeObject: workingID
    workingID = downsampledID
    appendInfoLine: "Downsampled to ", processing_sample_rate, " Hz"
else
    processing_sample_rate = current_sr
endif

# ============================================================
# STEP 2: HILBERT TRANSFORM
# ============================================================

appendInfo: "Computing Hilbert transform..."

selectObject: workingID
spectrumID = To Spectrum: "no"
Rename: "orig_spec"

# Create Hilbert transform (90° phase shift)
# Real -> Imag, Imag -> -Real
selectObject: spectrumID
hilbertSpecID = Copy: "hilbert_spec"

selectObject: hilbertSpecID
Formula: "if row = 1 then Spectrum_orig_spec[2, col] else -Spectrum_orig_spec[1, col] endif"

# Convert Hilbert spectrum to sound
selectObject: hilbertSpecID
hilbertSoundID = To Sound
Rename: "hilbert"

appendInfoLine: " done"

# ============================================================
# STEP 3: EXTRACT ENVELOPE
# ============================================================

appendInfo: "Extracting envelope..."

# Envelope = sqrt(signal^2 + hilbert^2)
selectObject: workingID
envSoundID = Copy: "env"

hilbertIdStr$ = string$(hilbertSoundID)

selectObject: envSoundID
Formula: "sqrt(self^2 + Object_" + hilbertIdStr$ + "(x)^2)"

# Scale envelope
selectObject: envSoundID
Scale peak: 0.99

# Optional envelope sharpening
if apply_envelope_sharpening
    selectObject: envSoundID
    expStr$ = fixed$(sharpening_exponent, 4)
    Formula: "self ^ " + expStr$
endif

# High-pass filter to reduce low-frequency pumping
selectObject: envSoundID
filteredEnvID = Filter (pass Hann band): highpass_cutoff, 0, highpass_smoothing
Rename: "env_filt"

# Keep a copy for visualization before removing
selectObject: filteredEnvID
envForVizID = Copy: "env_viz"

removeObject: envSoundID

appendInfoLine: " done"

# ============================================================
# STEP 4: APPLY REVERSED ENVELOPE
# ============================================================

appendInfo: "Applying reversed envelope..."

# Create time-reversed original
selectObject: workingID
reverseSoundID = Copy: "reversed"

selectObject: reverseSoundID
Formula: "self[ncol - col + 1]"

# Apply envelope to reversed sound
filteredEnvIdStr$ = string$(filteredEnvID)

selectObject: reverseSoundID
Rename: "rev_env"
Formula: "self * Object_" + filteredEnvIdStr$ + "(x)"

# Reverse back to normal time
selectObject: reverseSoundID
finalSoundID = Copy: "final"

selectObject: finalSoundID
Formula: "self[ncol - col + 1]"

appendInfoLine: " done"

# ============================================================
# STEP 5: RESAMPLE AND FINALIZE
# ============================================================

if use_downsampling and processing_sample_rate < original_sr
    appendInfo: "Resampling to ", original_sr, " Hz..."
    selectObject: finalSoundID
    resampledID = Resample: original_sr, 50
    removeObject: finalSoundID
    finalSoundID = resampledID
    appendInfoLine: " done"
endif

selectObject: finalSoundID
Rename: originalName$ + "_reverseEnv_" + presetName$
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Hilbert Reverse Envelope: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.5, 3.7, 0.75, 1.85
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
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
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Reverse Envelope Applied"
    Text left: "yes", "Amp"
    
    # Extracted envelope
    Select outer viewport: 0, 8, 2.2, 3.8
    Select inner viewport: 0.6, 7.6, 2.4, 3.6
    
    selectObject: envForVizID
    Colour: "{0.9, 0.5, 0.2}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Also draw reversed envelope
    selectObject: envForVizID
    envDur = Get total duration
    envSamples = Get number of samples
    
    Colour: "{0.2, 0.7, 0.4}"
    # Draw manually reversed
    Axes: 0, envDur, -1, 1
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Hilbert Envelope (orange = original, applied reversed)"
    Text left: "yes", "Env"
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
    Text top: "no", "Hilbert Transform (90° phase shift)"
    Text left: "yes", "Amp"
    
    # Info panel
    Select outer viewport: 4, 8, 4.0, 5.4
    Select inner viewport: 4.4, 7.8, 4.15, 5.25
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.8, "half", "Preset: " + presetName$
    if apply_envelope_sharpening
        Text: 0.05, "left", 0.55, "half", "Sharpening: " + fixed$(sharpening_exponent, 2)
    else
        Text: 0.05, "left", 0.55, "half", "Sharpening: OFF"
    endif
    Text: 0.05, "left", 0.3, "half", "Highpass: " + string$(highpass_cutoff) + " Hz"
    Text: 0.55, "left", 0.8, "half", "Sample rate: " + string$(processing_sample_rate)
    Text: 0.55, "left", 0.55, "half", "Smoothing: " + string$(highpass_smoothing)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    
    removeObject: envForVizID
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: spectrumID, hilbertSpecID, hilbertSoundID, filteredEnvID, reverseSoundID, workingID
if draw_visualization = 0
    removeObject: envForVizID
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_reverseEnv_", presetName$

if play_result
    selectObject: finalSoundID
    Play
endif
