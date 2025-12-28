# ============================================================
# Praat AudioTools - Wave Interference Pattern.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Creates complex spectral interference patterns by combining
#   sine and cosine modulation at different frequencies. The
#   interaction between two wave patterns creates beating,
#   phasing, and otherworldly textures.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Wave Interference Pattern
    optionmenu Preset: 1
        option Custom
        option Strong Interference
        option Subtle Interference
        option Alien Radio
        option Phaser (slow beating)
        option Metallic Ring
        option Underwater Transmission
    comment === Interference Parameters ===
    positive Frequency_cutoff_hz 11000
    positive Sine_divisor 800
    positive Cosine_divisor 1200
    positive Cosine_weight 0.5
    comment === Tone ===
    positive Brightness_compensation 1.2
    comment (boosts highs to prevent dark sound)
    comment === Output ===
    positive Scale_peak 0.95
    boolean Play_after_processing 1
endform

# Apply presets
if preset = 2
    sine_divisor = 400
    cosine_divisor = 600
    cosine_weight = 0.8
    brightness_compensation = 1.5
elsif preset = 3
    sine_divisor = 1200
    cosine_divisor = 2000
    cosine_weight = 0.2
    brightness_compensation = 1.1
elsif preset = 4
    # Alien Radio - tight interference
    sine_divisor = 150
    cosine_divisor = 160
    cosine_weight = 0.9
    brightness_compensation = 2.0
elsif preset = 5
    # Phaser - very close = slow beating
    sine_divisor = 2000
    cosine_divisor = 2005
    cosine_weight = 1.0
    brightness_compensation = 1.0
elsif preset = 6
    # Metallic Ring
    sine_divisor = 300
    cosine_divisor = 450
    cosine_weight = 0.7
    brightness_compensation = 1.8
elsif preset = 7
    # Underwater Transmission
    sine_divisor = 500
    cosine_divisor = 700
    cosine_weight = 0.6
    brightness_compensation = 0.8
    frequency_cutoff_hz = 6000
endif

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")
selectObject: sound
original_sr = Get sampling frequency
original_dur = Get total duration
n_channels = Get number of channels

writeInfoLine: "=== Wave Interference Pattern ==="
appendInfoLine: "Duration: ", fixed$(original_dur, 2), " s"
appendInfoLine: "Sine div: ", sine_divisor, " | Cosine div: ", cosine_divisor
appendInfoLine: "Cosine weight: ", cosine_weight
appendInfoLine: ""

# Convert to mono if needed
if n_channels > 1
    monoID = Convert to mono
    sound = monoID
else
    selectObject: sound
    monoID = Copy: "working"
    sound = monoID
endif

# Analyze
selectObject: sound
spectrum = To Spectrum: "yes"

# Get resolution for Hz to bin conversion
dx = Get bin width
nx = Get number of bins

# Convert Hz cutoff to bins
cutoff_bin = round(frequency_cutoff_hz / dx)

appendInfoLine: "Cutoff: ", frequency_cutoff_hz, " Hz (bin ", cutoff_bin, ")"

# Convert to Matrix for processing
selectObject: spectrum
mat_src = To Matrix
Rename: "src"

# Build formula strings
s_div$ = fixed$(sine_divisor, 2)
c_div$ = fixed$(cosine_divisor, 2)
c_wgt$ = fixed$(cosine_weight, 4)
bright$ = fixed$(brightness_compensation, 4)
c_bin$ = fixed$(cutoff_bin, 0)
n_bins$ = string$(nx)

# Apply interference pattern
# abs(sin + weight*cos) creates complex beating
# Brightness compensation boosts higher frequencies
selectObject: mat_src
Formula: "if col < " + c_bin$ + " then self * abs(sin(col / " + s_div$ + ") + " + c_wgt$ + " * cos(col / " + c_div$ + ")) * (1 + (col/" + n_bins$ + ") * (" + bright$ + " - 1)) else self fi"

# Reconstruct
selectObject: mat_src
spec_out = To Spectrum
sound_tmp = To Sound

# Fix sample rate
selectObject: sound_tmp
Override sampling frequency: original_sr

# Trim to original duration
Extract part: 0, original_dur, "rectangular", 1, "no"
finalID = selected("Sound")

Rename: originalName$ + "_interference"
Scale peak: scale_peak

# Cleanup
removeObject: spectrum, mat_src, spec_out, sound_tmp, monoID

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: finalID
if play_after_processing
    Play
endif