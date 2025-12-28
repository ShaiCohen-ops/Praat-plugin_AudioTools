# ============================================================
# Praat AudioTools - Hilbert Transform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Extracts the amplitude envelope using Hilbert transform
#   (analytic signal), then applies it reversed in time.
#   Creates "backwards attack" or "reverse reverb" effects
#   where sounds swell into their transients.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Hilbert Time-Reversed Envelope
    optionmenu Preset: 1
        option Custom
        option Subtle Reverse Swell
        option Strong Reverse Attack
        option Pad-like Bloom
        option Percussive Reverse
    comment === Processing ===
    boolean use_downsampling 1
    positive processing_sample_rate 32000
    comment === Envelope Shaping ===
    boolean apply_envelope_sharpening 0
    positive sharpening_exponent 0.8
    comment (< 1 = sharper, > 1 = smoother)
    comment === High-Pass Filter ===
    positive highpass_cutoff 50
    positive highpass_smoothing 10
    comment (reduces low-frequency pumping)
    comment === Output ===
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# Apply presets
if preset = 2
    apply_envelope_sharpening = 0
    highpass_cutoff = 30
    highpass_smoothing = 10
elsif preset = 3
    apply_envelope_sharpening = 1
    sharpening_exponent = 0.6
    highpass_cutoff = 80
    highpass_smoothing = 20
elsif preset = 4
    apply_envelope_sharpening = 1
    sharpening_exponent = 1.5
    highpass_cutoff = 20
    highpass_smoothing = 5
elsif preset = 5
    apply_envelope_sharpening = 1
    sharpening_exponent = 0.4
    highpass_cutoff = 100
    highpass_smoothing = 30
endif

# Check selection
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object first."
endif

originalID = selected("Sound")
sound$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
original_duration = Get total duration
num_channels = Get number of channels

writeInfoLine: "=== Hilbert Time-Reversed Envelope ==="
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " s"
appendInfoLine: "Sample rate: ", original_sr, " Hz"
appendInfoLine: ""

# STEP 1: Convert to mono
selectObject: originalID
if num_channels > 1
    workingID = Convert to mono
else
    workingID = Copy: "working"
endif

# STEP 2: Downsample if requested
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

# STEP 3: Create spectrum for Hilbert transform
appendInfoLine: "Computing Hilbert transform..."

selectObject: workingID
spectrum = To Spectrum: "no"
Rename: "orig_spec"

# STEP 4: Create Hilbert transform (90° phase shift)
selectObject: spectrum
hilbert_spectrum = Copy: "hilbert_spec"

selectObject: hilbert_spectrum
Formula: "if row = 1 then Spectrum_orig_spec[2, col] else -Spectrum_orig_spec[1, col] fi"

# STEP 5: Convert Hilbert spectrum to sound
selectObject: hilbert_spectrum
hilbert_sound = To Sound
Rename: "hilbert"

# STEP 6: Calculate envelope from analytic signal
appendInfoLine: "Extracting envelope..."

selectObject: workingID
env_sound = Copy: "env"

selectObject: env_sound
Formula: "sqrt(self^2 + Sound_hilbert[]^2)"

# STEP 7: Scale envelope
selectObject: env_sound
Scale peak: 0.99

# STEP 8: Optional envelope sharpening
if apply_envelope_sharpening
    selectObject: env_sound
    expStr$ = fixed$(sharpening_exponent, 4)
    Formula: "self ^ " + expStr$
    appendInfoLine: "Envelope sharpened (exp: ", sharpening_exponent, ")"
endif

# STEP 9: High-pass filter
selectObject: env_sound
filtered_env = Filter (pass Hann band): highpass_cutoff, 0, highpass_smoothing
Rename: "env_filt"
removeObject: env_sound

# STEP 10: Create time-reversed original
appendInfoLine: "Applying reversed envelope..."

selectObject: workingID
reverse_sound = Copy: "reversed"

selectObject: reverse_sound
Formula: "self[ncol - col + 1]"

# STEP 11: Apply envelope
selectObject: reverse_sound
Rename: "rev_env"
Formula: "self * Sound_env_filt[]"

# STEP 12: Reverse back to normal time
selectObject: reverse_sound
final_sound = Copy: "final"

selectObject: final_sound
Formula: "self[ncol - col + 1]"

# STEP 13: Resample back if needed
if use_downsampling and processing_sample_rate < original_sr
    appendInfoLine: "Resampling to ", original_sr, " Hz..."
    selectObject: final_sound
    resampledID = Resample: original_sr, 50
    removeObject: final_sound
    final_sound = resampledID
endif

# STEP 14: Finalize
selectObject: final_sound
Rename: sound$ + "_reverse_env"
Scale peak: scale_peak

# Cleanup
removeObject: spectrum, hilbert_spectrum, hilbert_sound, filtered_env, reverse_sound, workingID

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: final_sound
if play_after_processing
    Play
endif