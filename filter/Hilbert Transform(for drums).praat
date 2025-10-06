# ============================================================
# Praat AudioTools - Hilbert Transform(for drums).praat
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

form Hilbert Transform Envelope Extraction
    comment This script extracts the amplitude envelope using Hilbert transform
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier no
    comment (use "no" for Hilbert transform)
    comment Envelope processing:
    boolean apply_envelope_sharpening 0
    positive sharpening_exponent 0.8
    comment (< 1 = sharper envelope, > 1 = smoother envelope)
    comment High-pass filter parameters:
    positive highpass_cutoff 50
    positive highpass_smoothing 10
    comment (reduces low-frequency dominance)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the selected sound name
sound$ = selected$("Sound")
originalSound = selected("Sound")

# 1: Convert to frequency domain
select originalSound
spectrum = To Spectrum: fast_fourier
Rename: "original_spectrum"

# 2: Create Hilbert transform (90-degree phase shift)
hilbert_spectrum = Copy: "hilbert_spectrum"
Formula: "if row=1 then Spectrum_original_spectrum[2,col] else -Spectrum_original_spectrum[1,col] fi"

# 3: Convert back to time domain
hilbert_sound = To Sound
Rename: "hilbert_sound"

# 4: Calculate envelope from analytic signal
# Envelope = sqrt(original^2 + hilbert^2)
select originalSound
Copy: "envelope_temp"
Formula: "sqrt(self^2 + Sound_hilbert_sound[]^2)"
Rename: "'sound$'_ENV"

# 5: Scale the envelope
Scale peak: scale_peak

# 6: Optional envelope sharpening
if apply_envelope_sharpening
    Formula: "self^'sharpening_exponent'"
endif

# 7: High-pass filter to reduce low-frequency dominance
Filter (pass Hann band): highpass_cutoff, 0, highpass_smoothing

# Play if requested
if play_after_processing
    Play
endif

# Cleanup intermediate objects unless requested to keep
if not keep_intermediate_objects
    select spectrum
    plus hilbert_spectrum
    plus hilbert_sound
    plus Sound envelope_temp
    Remove
endif