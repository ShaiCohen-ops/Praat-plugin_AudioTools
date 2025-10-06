# ============================================================
# Praat AudioTools - tremolo_2.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Modulation or vibrato-based processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Strong Tremolo Effect
    comment This script applies pronounced tremolo using absolute sine LFO
    comment Modulation parameters:
    positive modulation_rate_hz 7
    comment (tremolo frequency: higher = faster pulses)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
    boolean show_info_report 1
    boolean keep_modulator 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get sound properties
sound$ = selected$("Sound")
select Sound 'sound$'
duration = Get total duration
samplePeriod = Get sample period
fs = 1 / samplePeriod

# Create absolute-sine modulator (swings from 0 to 1)
modulator = Create Sound from formula: "'sound$'_tremoloLFO", 1, 0, duration, fs, "abs(sin(2 * pi * 'modulation_rate_hz' * x))"

# Apply modulator to original sound
select Sound 'sound$'
tremolo_sound = Copy: "'sound$'_strong_tremolo"
Formula: "self * Sound_'sound$'_tremoloLFO[col]"
Rename: "'sound$'_strong_tremolo"

# Scale to peak
Scale peak: scale_peak

# Show info report if requested
if show_info_report
    clearinfo
    appendInfoLine: "Strong tremolo processing complete!"
    appendInfoLine: "Original: ", sound$
    appendInfoLine: "Created: ", sound$, "_strong_tremolo"
    appendInfoLine: "Modulation frequency: ", string$(modulation_rate_hz), " Hz"
endif

# Play if requested
if play_after_processing
    selectObject: tremolo_sound
    Play
endif

# Clean up modulator unless requested to keep
if not keep_modulator
    selectObject: modulator
    Remove
endif

# Select result
selectObject: tremolo_sound
