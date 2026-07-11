# ============================================================
# Praat AudioTools - Wave Interference Pattern.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.4 (2026)
# License: MIT License
#
# Description:
#   Creates complex spectral interference patterns by combining
#   sine and cosine modulation at different frequencies. The
#   interaction between two wave patterns creates beating,
#   phasing, and otherworldly textures.
#
# Changelog v0.4 (2026):
#   - AUDIO UNCHANGED (bit-identical to v0.3): all fixes are
#     visualization and documentation.
#   - VIZ FIX: the "output spectrum" panel drew spec_out, which is
#     computed BEFORE the wet/dry mix and before the FFT-pad trim
#     -- at wet/dry < 100% it showed the full-wet spectrum,
#     mislabeled. Now recomputed from the actual output sound.
#   - VIZ FIX: the combined interference curve now includes the
#     brightness-compensation ramp, i.e. the gain actually applied
#     (the pattern panel previously omitted it).
#   - DOC: the divisors are in FFT BIN units, so the pattern's Hz
#     spacing depends on the FFT size and therefore on the INPUT
#     DURATION: the same preset is twice as dense (in Hz) on a
#     file twice as long. This is the original, deliberate design
#     (the viz axis has always said "Frequency bin") -- documented
#     here so it is not mistaken for a bug.
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

form Wave Interference Pattern v0.4
    optionmenu Preset: 1
        option Custom
        option Strong Interference
        option Subtle Interference
        option Alien Radio
        option Phaser (slow beating)
        option Metallic Ring
        option Underwater Transmission
    comment === Interference Parameters ===
    comment (divisors are in FFT bins: pattern spacing in Hz scales with input duration)
    positive Frequency_cutoff_hz 11000
    positive Sine_divisor 800
    positive Cosine_divisor 1200
    positive Cosine_weight 0.5
    comment === Tone ===
    positive Brightness_compensation 1.2
    comment (boosts highs to prevent dark sound)
    comment === Mix ===
    real Wet_dry_percent 100
    comment (0 = dry, 100 = full wet)
    boolean Stereo_output 1
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# Apply presets
presetName$ = "Custom"

if preset = 2
    sine_divisor = 400
    cosine_divisor = 600
    cosine_weight = 0.8
    brightness_compensation = 1.5
    presetName$ = "StrongInterference"
elsif preset = 3
    sine_divisor = 1200
    cosine_divisor = 2000
    cosine_weight = 0.2
    brightness_compensation = 1.1
    presetName$ = "SubtleInterference"
elsif preset = 4
    # Alien Radio - tight interference
    sine_divisor = 150
    cosine_divisor = 160
    cosine_weight = 0.9
    brightness_compensation = 2.0
    presetName$ = "AlienRadio"
elsif preset = 5
    # Phaser - very close = slow beating
    sine_divisor = 2000
    cosine_divisor = 2005
    cosine_weight = 1.0
    brightness_compensation = 1.0
    presetName$ = "Phaser"
elsif preset = 6
    # Metallic Ring
    sine_divisor = 300
    cosine_divisor = 450
    cosine_weight = 0.7
    brightness_compensation = 1.8
    presetName$ = "MetallicRing"
elsif preset = 7
    # Underwater Transmission
    sine_divisor = 500
    cosine_divisor = 700
    cosine_weight = 0.6
    brightness_compensation = 0.8
    frequency_cutoff_hz = 6000
    presetName$ = "UnderwaterTransmission"
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
original_dur = Get total duration
n_channels = Get number of channels

writeInfoLine: "=== Wave Interference Pattern v0.4 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(original_dur, 2), " s"
appendInfoLine: "Sine div: ", sine_divisor, " | Cosine div: ", cosine_divisor
appendInfoLine: "Cosine weight: ", cosine_weight
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# Convert to mono if needed
selectObject: originalID
if n_channels > 1
    monoID = Convert to mono
else
    monoID = Copy: "working"
endif

# Keep dry copy for mix
selectObject: originalID
if n_channels > 1
    dry_sound = Convert to mono
else
    dry_sound = Copy: "dry"
endif

# Analyze
selectObject: monoID
origSpectrum = To Spectrum: "yes"
Rename: "original_spectrum"

# Copy for processing
selectObject: origSpectrum
spectrum = Copy: "processed_spectrum"

# Get resolution for Hz to bin conversion
selectObject: spectrum
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
resultID = selected("Sound")

removeObject: sound_tmp

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
    
    Create Sound from formula: "left", 1, 0, original_dur, original_sr, "object[" + mono_str$ + "]"
    left_ch = selected("Sound")
    
    Create Sound from formula: "right", 1, 0, original_dur, original_sr, 
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
    Text: 0.5, "centre", 0.5, "half", "Wave Interference: " + presetName$
    
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
    Draw: 0, frequency_cutoff_hz * 1.1, 0, 80, "no"
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
    # v0.4: computed from the ACTUAL output (post-mix, post-trim);
    # spec_out is the pre-mix padded spectrum and misrepresented
    # the result at wet/dry < 100%.
    Select outer viewport: 4, 8, 1.8, 2.8
    Select inner viewport: 4.4, 7.8, 1.9, 2.7
    selectObject: resultID
    nchViz = Get number of channels
    if nchViz > 1
        vizOutMono = Convert to mono
    else
        vizOutMono = Copy: "viz_out_mono"
    endif
    vizOutSpec = To Spectrum: "yes"
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, frequency_cutoff_hz * 1.1, 0, 80, "no"
    removeObject: vizOutMono, vizOutSpec
    selectObject: resultID
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Interference pattern ---
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1
    
    # Calculate pattern range
    max_pattern = 1 + cosine_weight + 0.2
    
    Axes: 0, cutoff_bin, 0, max_pattern
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, cutoff_bin, 0, max_pattern
    
    # Unity line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 1, cutoff_bin, 1
    
    # Draw sine component
    Colour: "{0.7, 0.7, 0.9}"
    Line width: 1
    numPoints = 400
    for i from 1 to numPoints
        bin = (i - 1) / (numPoints - 1) * cutoff_bin
        val = abs(sin(bin / sine_divisor))
        if i > 1
            Draw line: prev_bin, prev_val, bin, val
        endif
        prev_bin = bin
        prev_val = val
    endfor
    
    # Draw cosine component
    Colour: "{0.9, 0.8, 0.7}"
    for i from 1 to numPoints
        bin = (i - 1) / (numPoints - 1) * cutoff_bin
        val = abs(cosine_weight * cos(bin / cosine_divisor))
        if i > 1
            Draw line: prev_bin, prev_val, bin, val
        endif
        prev_bin = bin
        prev_val = val
    endfor
    
    # Draw combined interference pattern
    # v0.4: includes the brightness-compensation ramp -- this is
    # the gain actually applied to the bins.
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 1.5
    for i from 1 to numPoints
        bin = (i - 1) / (numPoints - 1) * cutoff_bin
        val = abs(sin(bin / sine_divisor) + cosine_weight * cos(bin / cosine_divisor))
        val = val * (1 + (bin / nx) * (brightness_compensation - 1))
        if i > 1
            Draw line: prev_bin, prev_val, bin, val
        endif
        prev_bin = bin
        prev_val = val
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency bin"
    
    # Legend
    Font size: 5
    Colour: "{0.7, 0.7, 0.9}"
    Text: cutoff_bin * 0.75, "left", max_pattern * 0.95, "half", "sin"
    Colour: "{0.9, 0.8, 0.7}"
    Text: cutoff_bin * 0.82, "left", max_pattern * 0.95, "half", "cos"
    Colour: "{0.2, 0.5, 0.8}"
    Text: cutoff_bin * 0.89, "left", max_pattern * 0.95, "half", "combined"
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", 
        ... "Sin div: " + string$(sine_divisor) +
        ... " | Cos div: " + string$(cosine_divisor) +
        ... " | Cos weight: " + fixed$(cosine_weight, 2) +
        ... " | Brightness: " + fixed$(brightness_compensation, 2) +
        ... " | Cutoff: " + string$(frequency_cutoff_hz) + " Hz" +
        ... " | Wet: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# Cleanup
removeObject: origSpectrum, spectrum, mat_src, spec_out, monoID, dry_sound

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: resultID
if play_after_processing
    Play
endif