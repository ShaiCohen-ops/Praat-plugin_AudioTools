# ============================================================
# Praat AudioTools - Spectral_Smearing_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Smearing Reverb - frequency-dependent delays
#   simulating acoustic dispersion. Lower frequencies get
#   longer delays (bass "hangs"), higher frequencies shorter.
#   Uses inverse-sqrt dispersion model with Lorentzian
#   frequency response (peak ~600 Hz) and cosine modulation.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection and formula syntax
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Spectral Smearing Reverb
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Smear
        option Medium Smear
        option Heavy Smear
        option Extreme Smear
    
    comment === Smearing Parameters ===
    positive Tail_duration_s 1.5
    natural Frequency_bands 20
    positive Time_stretch 0.6
    positive Base_amplitude 0.35
    
    comment === Frequency Response ===
    positive Peak_frequency_Hz 600
    positive Response_width_Hz 800
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Fadeout_duration_s 1.2
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Smear
    tail_duration_s = 1.0
    frequency_bands = 12
    time_stretch = 0.4
    base_amplitude = 0.2
    peak_frequency_Hz = 600
    response_width_Hz = 800
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Smear
    tail_duration_s = 1.5
    frequency_bands = 20
    time_stretch = 0.6
    base_amplitude = 0.35
    peak_frequency_Hz = 600
    response_width_Hz = 800
    fadeout_duration_s = 1.2
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Smear
    tail_duration_s = 2.5
    frequency_bands = 30
    time_stretch = 0.85
    base_amplitude = 0.5
    peak_frequency_Hz = 600
    response_width_Hz = 800
    fadeout_duration_s = 1.8
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Smear
    tail_duration_s = 4.0
    frequency_bands = 45
    time_stretch = 1.2
    base_amplitude = 0.65
    peak_frequency_Hz = 600
    response_width_Hz = 800
    fadeout_duration_s = 2.5
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Base frequency for dispersion
baseFreq = 80

# Pre-calculate band parameters for visualization
for band from 1 to frequency_bands
    bandFreq[band] = baseFreq * (2 ^ (band / 2.5))
    bandDelay[band] = time_stretch * (1 / sqrt(bandFreq[band] / baseFreq))
    bandResponse[band] = 1 / (1 + ((bandFreq[band] - peak_frequency_Hz) / response_width_Hz) ^ 2)
    bandModFreq[band] = bandFreq[band] / 15
endfor

# === Info ===
writeInfoLine: "=== Spectral Smearing Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Frequency bands: ", frequency_bands
appendInfoLine: "Frequency range: ", fixed$(bandFreq[1], 0), " - ", fixed$(bandFreq[frequency_bands], 0), " Hz"
appendInfoLine: "Time stretch: ", time_stretch
appendInfoLine: "Peak response: ", peak_frequency_Hz, " Hz"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

totalDur = originalDur + tail_duration_s

# Create silent tail
if numChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sr, "0"
endif
silentTail = selected("Sound")

# Concatenate
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left channel
    selectObject: leftChannel
    Copy: "smear_left"
    smearLeft = selected("Sound")
    
    for band from 1 to frequency_bands
        center_freq = baseFreq * (2 ^ (band / 2.5))
        delay_time = time_stretch * (1 / sqrt(center_freq / baseFreq))
        freq_response = 1 / (1 + ((center_freq - peak_frequency_Hz) / response_width_Hz) ^ 2)
        amplitude = base_amplitude * freq_response * randomUniform(0.7, 1.3)
        mod_freq = center_freq / 15
        
        delay_str$ = string$(delay_time)
        amp_str$ = string$(amplitude)
        mod_str$ = string$(mod_freq)
        
        selectObject: smearLeft
        Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (0.3 + 0.7*cos(2*pi*x*" + mod_str$ + "))"
        
        if band mod 10 = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    
    # Process right channel (slightly different parameters)
    selectObject: rightChannel
    Copy: "smear_right"
    smearRight = selected("Sound")
    
    baseFreq_R = 85
    stretch_R = time_stretch * 0.92
    peak_R = peak_frequency_Hz + 50
    width_R = response_width_Hz - 50
    
    for band from 1 to frequency_bands
        center_freq = baseFreq_R * (2 ^ (band / 2.3))
        delay_time = stretch_R * (1 / sqrt(center_freq / baseFreq_R))
        freq_response = 1 / (1 + ((center_freq - peak_R) / width_R) ^ 2)
        amplitude = base_amplitude * 0.94 * freq_response * randomUniform(0.65, 1.35)
        mod_freq = center_freq / 18
        
        delay_str$ = string$(delay_time)
        amp_str$ = string$(amplitude)
        mod_str$ = string$(mod_freq)
        
        selectObject: smearRight
        Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (0.25 + 0.75*cos(2*pi*x*" + mod_str$ + "))"
        
        if band mod 10 = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    
    # Apply wet/dry mix
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: smearLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: smearRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: smearLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    selectObject: smearRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    # Combine
    selectObject: smearLeft, smearRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_smear_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, smearLeft, smearRight, extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "smear_mono"
    smearMono = selected("Sound")
    
    for band from 1 to frequency_bands
        center_freq = baseFreq * (2 ^ (band / 2.5))
        delay_time = time_stretch * (1 / sqrt(center_freq / baseFreq))
        freq_response = 1 / (1 + ((center_freq - peak_frequency_Hz) / response_width_Hz) ^ 2)
        amplitude = base_amplitude * freq_response * randomUniform(0.7, 1.3)
        mod_freq = center_freq / 15
        
        delay_str$ = string$(delay_time)
        amp_str$ = string$(amplitude)
        mod_str$ = string$(mod_freq)
        
        selectObject: smearMono
        Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (0.3 + 0.7*cos(2*pi*x*" + mod_str$ + "))"
        
        if band mod 10 = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    
    # Apply wet/dry mix
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: smearMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: smearMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    Rename: originalName$ + "_smear_" + presetName$
    result = smearMono
    
    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Smearing Reverb: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Smear " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Dispersion curve (delay vs frequency)
    Select outer viewport: 0, 4, 2.5, 4.0
    Select inner viewport: 0.5, 3.7, 2.7, 3.85
    
    maxFreq = bandFreq[frequency_bands] * 1.1
    maxDelay = time_stretch * 1.2
    
    Axes: 0, maxFreq / 1000, 0, maxDelay * 1000
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxFreq / 1000, 0, maxDelay * 1000
    
    # Draw dispersion curve
    Colour: "{0.5, 0.6, 0.8}"
    Line width: 2
    
    prevX = baseFreq / 1000
    prevY = time_stretch * 1000
    for f from 1 to 50
        freq = baseFreq + (maxFreq - baseFreq) * f / 50
        delay = time_stretch * (1 / sqrt(freq / baseFreq)) * 1000
        Draw line: prevX, prevY, freq / 1000, delay
        prevX = freq / 1000
        prevY = delay
    endfor
    
    # Mark actual bands
    for band from 1 to frequency_bands
        freq = bandFreq[band] / 1000
        delay = bandDelay[band] * 1000
        Paint circle (mm): "{0.4, 0.5, 0.7}", freq, delay, 1.2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Delay (ms)"
    Text bottom: "yes", "Frequency (kHz)"
    
    # Title
    Font size: 8
    Select outer viewport: 0, 4, 2.35, 2.55
    Text: 0.5, "centre", 0.5, "half", "DISPERSION (delay = 1/√f)"
    
    # Lorentzian frequency response
    Select outer viewport: 4, 8, 2.5, 4.0
    Select inner viewport: 4.5, 7.7, 2.7, 3.85
    
    Axes: 0, maxFreq / 1000, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxFreq / 1000, 0, 1.2
    
    # Draw response curve
    Colour: "{0.7, 0.5, 0.6}"
    Line width: 2
    
    prevX = 0
    prevY = 1 / (1 + ((baseFreq - peak_frequency_Hz) / response_width_Hz) ^ 2)
    for f from 1 to 50
        freq = baseFreq + (maxFreq - baseFreq) * f / 50
        response = 1 / (1 + ((freq - peak_frequency_Hz) / response_width_Hz) ^ 2)
        Draw line: prevX, prevY, freq / 1000, response
        prevX = freq / 1000
        prevY = response
    endfor
    
    # Mark peak
    Colour: "{0.8, 0.4, 0.4}"
    Dashed line
    Draw line: peak_frequency_Hz / 1000, 0, peak_frequency_Hz / 1000, 1
    Solid line
    
    # Mark actual bands
    for band from 1 to frequency_bands
        freq = bandFreq[band] / 1000
        response = bandResponse[band]
        Paint circle (mm): "{0.6, 0.4, 0.5}", freq, response, 1.2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (kHz)"
    
    # Title
    Font size: 8
    Select outer viewport: 4, 8, 2.35, 2.55
    Text: 0.5, "centre", 0.5, "half", "LORENTZIAN RESPONSE (peak " + string$(peak_frequency_Hz) + "Hz)"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Bands: " + string$(frequency_bands) + " | Range: " + fixed$(bandFreq[1], 0) + "-" + fixed$(bandFreq[frequency_bands], 0) + "Hz | Stretch: " + fixed$(time_stretch, 2) + " | Peak: " + string$(peak_frequency_Hz) + "Hz"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
