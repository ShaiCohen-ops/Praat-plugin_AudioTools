# ============================================================
# Praat AudioTools - Hilbert Transform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Hilbert Time-Reversed Envelope
    comment This script extracts envelope and applies it backwards in time
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
    boolean show_info_report 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the selected sound name
sound$ = selected$("Sound")
select Sound 'sound$'
original_duration = Get total duration

# 1: Convert to spectrum
spectrum = To Spectrum: fast_fourier
Rename: "original_spectrum"

# 2: Create Hilbert transform (90-degree phase shift)
hilbert_spectrum = Copy: "hilbert_spectrum"
Formula: "if row=1 then Spectrum_original_spectrum[2,col] else -Spectrum_original_spectrum[1,col] fi"

# 3: Convert back to time domain
hilbert_sound = To Sound
Rename: "hilbert_sound"

# 4: Calculate envelope from analytic signal
select Sound 'sound$'
env_sound = Copy: "envelope_temp"
Formula: "sqrt(self^2 + Sound_hilbert_sound[]^2)"
Rename: "'sound$'_envelope"

# 5: Scale the envelope
Scale peak: scale_peak

# 6: Optional envelope sharpening
if apply_envelope_sharpening
    Formula: "self^'sharpening_exponent'"
endif

# 7: High-pass filter to reduce low-frequency dominance
Filter (pass Hann band): highpass_cutoff, 0, highpass_smoothing

# 8: Create time-reversed version of original sound
select Sound 'sound$'
reverse_sound = Copy: "'sound$'_reversed"
Formula: "self[(ncol-col+1)]"

# 9: Apply envelope backwards in time
select reverse_sound
reversed_with_env = Copy: "'sound$'_reversed_with_env"
Formula: "self * Sound_'sound$'_envelope[col]"

# 10: Reverse back to normal time
select reversed_with_env
final_sound = Copy: "'sound$'_time_reverse_env"
Formula: "self[(ncol-col+1)]"
Rename: "'sound$'_time_reverse_env"

# 11: Scale final output
Scale peak: scale_peak

# Show info report if requested
if show_info_report
    clearinfo
    appendInfoLine: "Time-reverse envelope processing complete!"
    appendInfoLine: "Original: ", sound$
    appendInfoLine: "Created: ", sound$, "_time_reverse_env"
    appendInfoLine: "Duration: ", fixed$(original_duration, 3), " seconds"
    appendInfoLine: "Envelope applied backwards in time"
endif

# Play if requested
if play_after_processing
    select final_sound
    Play
endif

# Cleanup intermediate objects unless requested to keep
if not keep_intermediate_objects
    selectObject: spectrum, hilbert_spectrum, hilbert_sound
    plusObject: reverse_sound, reversed_with_env, env_sound
    Remove
endif

# Select the final result
selectObject: final_sound