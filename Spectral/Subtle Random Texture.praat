# ============================================================
# Praat AudioTools - Subtle Random Texture.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025)
# License: MIT License
#
# Description:
#   Adds random spectral variation to create subtle texture,
#   shimmer, or noise-like qualities. Each frequency bin gets
#   a random gain multiplier.
#
# Changelog v0.3:
#   - Added wet/dry mix control
#   - Added visualization
#   - Added stereo output option
#   - Added preset names to output filename
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Subtle Random Texture
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer
        option Strong Texture
        option Lo-Fi Grit
        option Spectral Dust
        option Vinyl Hiss
    comment === Variation Parameters ===
    positive frequency_cutoff 10000
    comment (frequencies below this get variation)
    positive variation_center 0.8
    positive variation_depth 0.2
    comment (gain = center ± depth × random)
    comment === Mix ===
    real wet_dry_percent 100
    comment (0 = dry, 100 = full wet)
    boolean stereo_output 1
    comment === Output ===
    positive scale_peak 0.90
    boolean draw_visualization 1
    boolean play_after_processing 1
endform

# Apply presets
presetName$ = "Custom"

if preset = 2
    # Subtle Shimmer
    variation_center = 0.9
    variation_depth = 0.1
    frequency_cutoff = 12000
    presetName$ = "SubtleShimmer"
elsif preset = 3
    # Strong Texture
    variation_center = 0.7
    variation_depth = 0.4
    frequency_cutoff = 10000
    presetName$ = "StrongTexture"
elsif preset = 4
    # Lo-Fi Grit
    variation_center = 0.6
    variation_depth = 0.5
    frequency_cutoff = 6000
    presetName$ = "LoFiGrit"
elsif preset = 5
    # Spectral Dust
    variation_center = 0.85
    variation_depth = 0.25
    frequency_cutoff = 16000
    presetName$ = "SpectralDust"
elsif preset = 6
    # Vinyl Hiss
    variation_center = 0.95
    variation_depth = 0.15
    frequency_cutoff = 8000
    presetName$ = "VinylHiss"
endif

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels

writeInfoLine: "=== Subtle Random Texture v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Cutoff: ", frequency_cutoff, " Hz"
appendInfoLine: "Variation: ", variation_center, " ± ", variation_depth
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if n_channels > 1
    workingID = Convert to mono
else
    workingID = Copy: "working"
endif

# Keep dry copy for mix
selectObject: originalID
if n_channels > 1
    dry_sound = Convert to mono
else
    dry_sound = Copy: "dry"
endif

# To spectrum
selectObject: workingID
origSpectrum = To Spectrum: "yes"
Rename: "original_spectrum"

# Copy for processing
selectObject: origSpectrum
spectrum = Copy: "processed_spectrum"

# Get bin width for Hz conversion
selectObject: spectrum
dx = Get bin width
cutoff_bin = round(frequency_cutoff / dx)

# Build formula
centerStr$ = fixed$(variation_center, 4)
depthStr$ = fixed$(variation_depth, 4)
cutoffStr$ = string$(cutoff_bin)

# Apply random variation
# Each bin gets: self * (center + depth * randomUniform(-1, 1))
selectObject: spectrum
Formula: "if col < " + cutoffStr$ + " then self * (" + centerStr$ + " + " + depthStr$ + " * randomUniform(-1, 1)) else self fi"

# Back to sound
selectObject: spectrum
resultID = To Sound

# Trim to original duration
selectObject: resultID
resultDur = Get total duration
if resultDur > duration
    trimmed = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: resultID
    resultID = trimmed
endif

# === WET/DRY MIX ===
if dry_level > 0
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: resultID
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
endif

# === STEREO OUTPUT ===
if stereo_output and n_channels > 1
    selectObject: resultID
    mono_result = resultID
    resultID = Convert to stereo
    removeObject: mono_result
elsif stereo_output and n_channels = 1
    # Create pseudo-stereo with slight delay
    selectObject: resultID
    mono_result = resultID
    delay_samples = round(0.012 * original_sr)
    delay_str$ = string$(delay_samples)
    mono_str$ = string$(mono_result)
    
    Create Sound from formula: "left", 1, 0, duration, original_sr, "object[" + mono_str$ + "]"
    left_ch = selected("Sound")
    
    Create Sound from formula: "right", 1, 0, duration, original_sr, 
        ... "if col > " + delay_str$ + " then object[" + mono_str$ + ", col - " + delay_str$ + "] else 0 fi"
    right_ch = selected("Sound")
    
    selectObject: left_ch
    plusObject: right_ch
    resultID = Combine to stereo
    
    removeObject: mono_result, left_ch, right_ch
endif

selectObject: resultID
Rename: originalName$ + "_" + presetName$
Scale peak: scale_peak

# === VISUALIZATION ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Subtle Random Texture: " + presetName$
    
    # --- Original waveform ---
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.4, 3.8, 0.7, 1.5
    selectObject: originalID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    
    # --- Original spectrum ---
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.4, 7.8, 0.7, 1.5
    selectObject: origSpectrum
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, frequency_cutoff * 1.2, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    
    # --- Result waveform ---
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
    
    # --- Result spectrum ---
    Select outer viewport: 4, 8, 1.8, 2.8
    Select inner viewport: 4.4, 7.8, 1.9, 2.7
    selectObject: spectrum
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, frequency_cutoff * 1.2, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Gain range diagram ---
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1
    
    max_display_freq = frequency_cutoff * 1.3
    min_gain = variation_center - variation_depth - 0.1
    max_gain = variation_center + variation_depth + 0.1
    if min_gain < 0
        min_gain = 0
    endif
    if max_gain < 1.2
        max_gain = 1.2
    endif
    
    Axes: 0, max_display_freq, min_gain, max_gain
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, max_display_freq, min_gain, max_gain
    
    # Unity gain line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 1, max_display_freq, 1
    
    # Random variation zone (shaded)
    Colour: "{0.85, 0.9, 0.95}"
    Paint rectangle: "{0.85, 0.9, 0.95}", 0, frequency_cutoff, variation_center - variation_depth, variation_center + variation_depth
    
    # Center line
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    Draw line: 0, variation_center, frequency_cutoff, variation_center
    
    # Upper and lower bounds
    Colour: "{0.5, 0.7, 0.9}"
    Line width: 1
    Dotted line
    Draw line: 0, variation_center + variation_depth, frequency_cutoff, variation_center + variation_depth
    Draw line: 0, variation_center - variation_depth, frequency_cutoff, variation_center - variation_depth
    Solid line
    
    # Cutoff line
    Colour: "{0.8, 0.4, 0.4}"
    Draw line: frequency_cutoff, min_gain, frequency_cutoff, max_gain
    
    # After cutoff (unity)
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: frequency_cutoff, 1, max_display_freq, 1
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", 
        ... "Center: " + fixed$(variation_center, 2) +
        ... " | Depth: ±" + fixed$(variation_depth, 2) +
        ... " | Range: " + fixed$(variation_center - variation_depth, 2) + " to " + fixed$(variation_center + variation_depth, 2) +
        ... " | Cutoff: " + string$(frequency_cutoff) + " Hz" +
        ... " | Wet: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# Cleanup
removeObject: workingID, origSpectrum, spectrum, dry_sound

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: resultID
if play_after_processing
    Play
endif