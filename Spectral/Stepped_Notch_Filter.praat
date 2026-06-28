# ============================================================
# Praat AudioTools - Stepped_Notch_Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2026)
# License: MIT License
#
# Description:
#   Stepped notch filter - multi-band spectral attenuation with
#   configurable frequency bands and gain controls. Useful for
#   notch filtering, de-essing, and spectral sculpting.
#
# Changelog v0.3:
#   - Renamed to Stepped Notch Filter
#   - Fixed wet/dry mix cross-object reference (needs col index)
#   - Standard header
#
# Changelog v0.2:
#   - Added wet/dry mix control
#   - Added visualization
#   - Added stereo output option
#   - Added preset names to output filename
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Stepped Notch Filter
    optionmenu Preset: 1
        option Custom
        option Vocal Notch (remove 2-4kHz presence)
        option De-Esser (reduce 5-8kHz)
        option Hollow Middle (scoop mids)
        option Telephone (bandpass effect)
    comment === Band 1 ===
    positive band1_low 2000
    positive band1_high 2200
    positive band1_gain 0.1
    comment === Band 2 ===
    positive band2_low 5500
    positive band2_high 5800
    positive band2_gain 0.2
    comment === Outside Bands ===
    positive outside_gain 1.0
    comment === Mix ===
    real wet_dry_percent 100
    comment (0 = dry, 100 = full wet)
    boolean stereo_output 1
    comment === Output ===
    positive scale_peak 0.90
    boolean draw_visualization 1
    boolean play_after_processing 1
endform

# Presets
presetName$ = "Custom"

if preset = 2
    band1_low = 2000
    band1_high = 4000
    band1_gain = 0.3
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
    presetName$ = "VocalNotch"
elsif preset = 3
    band1_low = 5000
    band1_high = 8000
    band1_gain = 0.4
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
    presetName$ = "DeEsser"
elsif preset = 4
    band1_low = 400
    band1_high = 2000
    band1_gain = 0.2
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
    presetName$ = "HollowMiddle"
elsif preset = 5
    band1_low = 0
    band1_high = 300
    band1_gain = 0.1
    band2_low = 3400
    band2_high = 20000
    band2_gain = 0.1
    outside_gain = 1.0
    presetName$ = "Telephone"
endif

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

writeInfoLine: "=== Stepped Notch Filter v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Band 1: ", band1_low, "-", band1_high, " Hz (gain: ", band1_gain, ")"
appendInfoLine: "Band 2: ", band2_low, "-", band2_high, " Hz (gain: ", band2_gain, ")"
appendInfoLine: "Outside: gain ", outside_gain
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

# Build formula using x (frequency in Hz)
b1l$ = fixed$(band1_low, 0)
b1h$ = fixed$(band1_high, 0)
b1g$ = fixed$(band1_gain, 4)
b2l$ = fixed$(band2_low, 0)
b2h$ = fixed$(band2_high, 0)
b2g$ = fixed$(band2_gain, 4)
outG$ = fixed$(outside_gain, 4)

# Apply multi-band attenuation
selectObject: spectrum
Formula: "if x >= " + b1l$ + " and x <= " + b1h$ + " then self * " + b1g$ + " else if x >= " + b2l$ + " and x <= " + b2h$ + " then self * " + b2g$ + " else self * " + outG$ + " fi fi"

# Back to sound
selectObject: spectrum
resultID = To Sound

# Trim
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
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", col] * " + dry_str$
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
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Stepped Notch Filter##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + presetName$
    
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
    Draw: 0, 10000, 0, 80, "no"
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
    Draw: 0, 10000, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Gain curve ---
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1
    
    # Find max frequency for display
    max_display_freq = 10000
    if band2_high > max_display_freq
        max_display_freq = band2_high * 1.2
    endif
    
    # Find gain range
    min_gain = min(min(band1_gain, band2_gain), outside_gain)
    max_gain = max(max(band1_gain, band2_gain), outside_gain)
    if min_gain > 0
        min_gain = 0
    endif
    if max_gain < 1.2
        max_gain = 1.2
    endif
    
    Axes: 0, max_display_freq, min_gain - 0.1, max_gain + 0.1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, max_display_freq, min_gain - 0.1, max_gain + 0.1
    
    # Unity gain line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 1, max_display_freq, 1
    
    # Draw gain curve
    Colour: "{0.2, 0.6, 0.8}"
    Line width: 2
    
    # Outside region before band1
    if band1_low > 0
        Draw line: 0, outside_gain, band1_low, outside_gain
    endif
    
    # Band 1
    if band1_high > band1_low
        # Transition to band1
        Draw line: band1_low, outside_gain, band1_low, band1_gain
        # Band1 region
        Draw line: band1_low, band1_gain, band1_high, band1_gain
        # Transition out
        Draw line: band1_high, band1_gain, band1_high, outside_gain
    endif
    
    # Between bands
    if band2_low > band1_high
        Draw line: band1_high, outside_gain, band2_low, outside_gain
    endif
    
    # Band 2
    if band2_high > band2_low and band2_low > 0
        # Transition to band2
        Draw line: band2_low, outside_gain, band2_low, band2_gain
        # Band2 region
        Draw line: band2_low, band2_gain, band2_high, band2_gain
        # Transition out
        Draw line: band2_high, band2_gain, band2_high, outside_gain
    endif
    
    # Outside region after band2
    end_freq = max(band1_high, band2_high)
    if end_freq < max_display_freq
        Draw line: end_freq, outside_gain, max_display_freq, outside_gain
    endif
    
    # Shade attenuated regions
    Colour: "{0.9, 0.8, 0.8}"
    if band1_high > band1_low
        Paint rectangle: "{0.9, 0.85, 0.85}", band1_low, band1_high, min_gain - 0.1, band1_gain
    endif
    if band2_high > band2_low and band2_low > 0
        Paint rectangle: "{0.9, 0.85, 0.85}", band2_low, band2_high, min_gain - 0.1, band2_gain
    endif
    
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
    
    band1_info$ = "Band1: " + string$(band1_low) + "-" + string$(band1_high) + " Hz @ " + fixed$(band1_gain, 2)
    band2_info$ = ""
    if band2_high > band2_low and band2_low > 0
        band2_info$ = " | Band2: " + string$(band2_low) + "-" + string$(band2_high) + " Hz @ " + fixed$(band2_gain, 2)
    endif
    
    Text: 0.5, "centre", 0.5, "half", 
        ... band1_info$ + band2_info$ +
        ... " | Outside: " + fixed$(outside_gain, 2) +
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