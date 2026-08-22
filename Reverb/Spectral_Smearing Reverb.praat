# ============================================================
# Praat AudioTools - Spectral_Smearing_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.3 reviewed (2026)
# v0.3.3 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Smearing Reverb implemented as a true filter-bank
#   dispersion effect. The source is decomposed into consecutive
#   Hann frequency bands. Each band receives a frequency-dependent
#   delay (delay proportional to 1/sqrt(f)), a Lorentzian spectral
#   weighting, and a subtle slow cosine amplitude modulation.
#   Lower-frequency bands arrive later than higher-frequency bands.
#
# Review changes v0.3:
#   - Replaced nominal "bands" with actual Hann-filtered bands.
#   - Replaced exponentially unbounded centre frequencies with a
#     log-spaced filter bank bounded by Nyquist.
#   - Wet path is now truly wet (no direct source hidden inside it).
#   - Slow modulation no longer flips polarity or creates strong
#     audio-rate AM sidebands.
#   - Wet fade is applied before wet/dry mixing and never fades dry.
#   - Removed repeated/per-channel Scale peak normalization.
#   - Added common down-only peak protection after stereo combining.
#   - Uses time-based object() reads for sub-sample band delays.
#   - Visualization now shows the full output tail.
#
# Visual refinement v0.3.1:
#   - Reworked visualization to match the Praat AudioTools house style.
#   - Added normalized 0..1 axes to all text-only viewports.
#   - Added title/subtitle hierarchy, panel titles, and summary panel.
#   - Dry and output waveforms now share the same full-duration time axis.
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

if numChannels <> 1 and numChannels <> 2
    exitScript: "Spectral Smearing Reverb currently supports mono or stereo Sound objects only."
endif

if sr < 1000
    exitScript: "Sampling frequency is too low for this effect."
endif

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

# === Parameter guards ===
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

if frequency_bands < 2
    frequency_bands = 2
elsif frequency_bands > 64
    frequency_bands = 64
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

nyquist = sr / 2
baseFreq = 80
if baseFreq > nyquist / 4
    baseFreq = nyquist / 4
endif

maxCenter = nyquist * 0.90
effectivePeak = peak_frequency_Hz
if effectivePeak > nyquist * 0.95
    effectivePeak = nyquist * 0.95
endif

# Ensure enough output tail to contain the longest low-frequency delay.
effectiveTail = tail_duration_s
if time_stretch > effectiveTail
    effectiveTail = time_stretch
endif

fadeDuration = fadeout_duration_s
if fadeDuration > effectiveTail
    fadeDuration = effectiveTail
endif

totalDur = originalDur + effectiveTail
fadeStart = totalDur - fadeDuration

# === Build a logarithmic, Nyquist-bounded filter bank ===
# Band 1 is a low-pass band and the final band is a high-pass band.
# Interior boundaries are geometric means between neighbouring centres.
ratio = (maxCenter / baseFreq) ^ (1 / (frequency_bands - 1))

for band from 1 to frequency_bands
    bandFreq[band] = baseFreq * (ratio ^ (band - 1))
endfor

peak_R = effectivePeak * 1.08
if peak_R > nyquist * 0.95
    peak_R = nyquist * 0.95
endif
width_R = response_width_Hz * 0.94

for band from 1 to frequency_bands
    if band = 1
        bandLow[band] = 0
    else
        bandLow[band] = sqrt(bandFreq[band - 1] * bandFreq[band])
    endif

    if band = frequency_bands
        bandHigh[band] = 0
        bandWidth[band] = nyquist - bandLow[band]
    else
        bandHigh[band] = sqrt(bandFreq[band] * bandFreq[band + 1])
        bandWidth[band] = bandHigh[band] - bandLow[band]
    endif

    bandSmooth[band] = bandWidth[band] * 0.20
    if bandSmooth[band] < 5
        bandSmooth[band] = 5
    elsif bandSmooth[band] > 100
        bandSmooth[band] = 100
    endif

    # True frequency-dependent delays.
    bandDelayL[band] = time_stretch / sqrt(bandFreq[band] / baseFreq)
    bandDelayR[band] = (time_stretch * 0.92) / sqrt(bandFreq[band] / baseFreq)

    # Lorentzian band weights.
    bandResponseL[band] = 1 / (1 + ((bandFreq[band] - effectivePeak) / response_width_Hz) ^ 2)
    bandResponseR[band] = 1 / (1 + ((bandFreq[band] - peak_R) / width_R) ^ 2)

    # Precompute randomness once so DSP and reporting use the same values.
    bandAmpL[band] = base_amplitude * bandResponseL[band] * randomUniform(0.85, 1.15)
    bandAmpR[band] = base_amplitude * 0.96 * bandResponseR[band] * randomUniform(0.82, 1.18)

    # Slow AM only: avoids polarity reversal and strong audio-rate sidebands.
    bandModFreqL[band] = 0.12 + 0.88 * (band - 1) / (frequency_bands - 1)
    bandModFreqR[band] = 0.15 + 0.95 * (band - 1) / (frequency_bands - 1)
endfor

# === Info ===
writeInfoLine: "=== Spectral Smearing Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "True Hann filter-bank bands: ", frequency_bands
appendInfoLine: "Band centres: ", fixed$(bandFreq[1], 0), " - ", fixed$(bandFreq[frequency_bands], 0), " Hz"
appendInfoLine: "Filter-bank coverage: 0 - ", fixed$(nyquist, 0), " Hz"
appendInfoLine: "Longest L/R delay: ", fixed$(bandDelayL[1], 3), " / ", fixed$(bandDelayR[1], 3), " s"
appendInfoLine: "Shortest L/R delay: ", fixed$(bandDelayL[frequency_bands], 3), " / ", fixed$(bandDelayR[frequency_bands], 3), " s"
appendInfoLine: "Peak response: ", fixed$(effectivePeak, 0), " Hz"
if effectivePeak <> peak_frequency_Hz
    appendInfoLine: "  (requested peak was limited to 95% of Nyquist)"
endif
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: "Output duration: ", fixed$(totalDur, 2), " s"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing filter bank..."

# Fast path: 0% wet must be an unchanged dry signal followed by silence.
if wet_level = 0
    original_id_str$ = string$(original)
    Create Sound from formula: "smear_dry_only", numChannels, 0, totalDur, sr, "object(" + original_id_str$ + ", x, row)"
    result = selected("Sound")
    Rename: originalName$ + "_smear_" + presetName$
else
    if numChannels = 2
    # === STEREO SOURCE CHANNELS ===
    selectObject: original
    Extract one channel: 1
    leftChannel = selected("Sound")

    selectObject: original
    Extract one channel: 2
    rightChannel = selected("Sound")

    # Empty wet accumulators with room for the delayed tail.
    Create Sound from formula: "smear_wet_left", 1, 0, totalDur, sr, "0"
    wetLeft = selected("Sound")

    Create Sound from formula: "smear_wet_right", 1, 0, totalDur, sr, "0"
    wetRight = selected("Sound")

    # === LEFT FILTER BANK ===
    for band from 1 to frequency_bands
        low = bandLow[band]
        high = bandHigh[band]
        smoothing = bandSmooth[band]

        selectObject: leftChannel
        Filter (pass Hann band): low, high, smoothing
        bandSound = selected("Sound")

        band_id_str$ = string$(bandSound)
        delay_str$ = string$(bandDelayL[band])
        amp_str$ = string$(bandAmpL[band])
        mod_str$ = string$(bandModFreqL[band])

        selectObject: wetLeft
        Formula: "self + " + amp_str$ + " * object(" + band_id_str$ + ", x - " + delay_str$ + ", 1) * (1 + 0.12*cos(2*pi*x*" + mod_str$ + "))"

        removeObject: bandSound
    endfor

    # === RIGHT FILTER BANK ===
    for band from 1 to frequency_bands
        low = bandLow[band]
        high = bandHigh[band]
        smoothing = bandSmooth[band]

        selectObject: rightChannel
        Filter (pass Hann band): low, high, smoothing
        bandSound = selected("Sound")

        band_id_str$ = string$(bandSound)
        delay_str$ = string$(bandDelayR[band])
        amp_str$ = string$(bandAmpR[band])
        mod_str$ = string$(bandModFreqR[band])

        selectObject: wetRight
        Formula: "self + " + amp_str$ + " * object(" + band_id_str$ + ", x - " + delay_str$ + ", 1) * (1 + 0.12*cos(2*pi*x*" + mod_str$ + " + pi/2))"

        removeObject: bandSound
    endfor

    # Fade WET tail only. Formula expressions use nested/simple if syntax only.
    fade_start_str$ = string$(fadeStart)
    fade_str$ = string$(fadeDuration)

    selectObject: wetLeft
    Formula: "if x > " + fade_start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + fade_start_str$ + ")/" + fade_str$ + ")) else self fi"

    selectObject: wetRight
    Formula: "if x > " + fade_start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + fade_start_str$ + ")/" + fade_str$ + ")) else self fi"

    # True wet/dry mix. object() reads the immutable dry channel and
    # returns zero outside its original time domain.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    left_id_str$ = string$(leftChannel)
    right_id_str$ = string$(rightChannel)

    selectObject: wetLeft
    Formula: "self * " + wet_str$ + " + object(" + left_id_str$ + ", x, 1) * " + dry_str$

    selectObject: wetRight
    Formula: "self * " + wet_str$ + " + object(" + right_id_str$ + ", x, 1) * " + dry_str$

    # Combine first, then use one common down-only safety gain.
    selectObject: wetLeft, wetRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_smear_" + presetName$

    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "none"
    if resultPeak > 0.98
        Scale peak: 0.98
    endif

    removeObject: leftChannel, rightChannel, wetLeft, wetRight

else
    # === MONO PROCESSING ===
    Create Sound from formula: "smear_wet_mono", 1, 0, totalDur, sr, "0"
    wetMono = selected("Sound")

    for band from 1 to frequency_bands
        low = bandLow[band]
        high = bandHigh[band]
        smoothing = bandSmooth[band]

        selectObject: original
        Filter (pass Hann band): low, high, smoothing
        bandSound = selected("Sound")

        band_id_str$ = string$(bandSound)
        delay_str$ = string$(bandDelayL[band])
        amp_str$ = string$(bandAmpL[band])
        mod_str$ = string$(bandModFreqL[band])

        selectObject: wetMono
        Formula: "self + " + amp_str$ + " * object(" + band_id_str$ + ", x - " + delay_str$ + ", 1) * (1 + 0.12*cos(2*pi*x*" + mod_str$ + "))"

        removeObject: bandSound
    endfor

    # Fade wet only.
    fade_start_str$ = string$(fadeStart)
    fade_str$ = string$(fadeDuration)

    selectObject: wetMono
    Formula: "if x > " + fade_start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + fade_start_str$ + ")/" + fade_str$ + ")) else self fi"

    # True wet/dry mix.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    original_id_str$ = string$(original)

    selectObject: wetMono
    Formula: "self * " + wet_str$ + " + object(" + original_id_str$ + ", x, 1) * " + dry_str$

    Rename: originalName$ + "_smear_" + presetName$
    result = wetMono

    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "none"
    if resultPeak > 0.98
        Scale peak: 0.98
    endif
    endif
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Select outer viewport: 0, 8, 0, 8

    selectObject: result
    resultDur = Get total duration

    # === TITLE ===
    Select outer viewport: 0, 8, 0.0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.66, "half", "##Spectral Smearing Reverb##  |  " + presetName$ + " | v0.3.3"
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.12, "half", originalName$ + "   |   " + string$(frequency_bands) + " bands   |   wet/dry " + fixed$(wet_dry_percent, 0) + "%"

    # === DRY WAVEFORM ===
    Select outer viewport: 0, 8, 0.7, 2.3
    Select inner viewport: 0.60, 7.70, 0.8, 2.2
    Axes: 0, resultDur, -1, 1
    selectObject: original
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, originalDur, -1, 1, "no", "Curve"
    Colour: "{0.75, 0.75, 0.80}"
    Dotted line
    Draw line: originalDur, -1, originalDur, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Select inner viewport: 0.20, 0.48, 0.8, 2.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.8, 2.2
    Axes: 0, resultDur, -1, 1
    Font size: 7
    Text top: "no", "##Original (dry)##"

    # === SMEARED OUTPUT (full length including tail) ===
    Select outer viewport: 0, 8, 2.4, 4.0
    Select inner viewport: 0.60, 7.70, 2.5, 3.9
    Axes: 0, resultDur, -1, 1
    selectObject: result
    Colour: "{0.58, 0.48, 0.70}"
    Draw: 0, resultDur, -1, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Select inner viewport: 0.20, 0.48, 2.5, 3.9
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Smear " + fixed$(wet_dry_percent, 0) + "\%  "
    Select inner viewport: 0.60, 7.70, 2.5, 3.9
    Axes: 0, resultDur, -1, 1
    Text bottom: "yes", "Time (s)"
    Font size: 7
    Text top: "no", "##Smearing Output (full length with tail)##"

    # === FILTER-BANK DISPERSION ===
    Select outer viewport: 0, 4, 4.25, 6.8
    Select inner viewport: 0.60, 3.85, 4.50, 6.55

    maxDelay = time_stretch * 1.1
    Axes: 0, nyquist / 1000, 0, maxDelay * 1000
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, nyquist / 1000, 0, maxDelay * 1000

    Colour: "{0.48, 0.58, 0.78}"
    Line width: 2
    prevX = baseFreq / 1000
    prevY = time_stretch * 1000
    for f from 1 to 80
        freq = baseFreq + (maxCenter - baseFreq) * f / 80
        delay = time_stretch / sqrt(freq / baseFreq) * 1000
        Draw line: prevX, prevY, freq / 1000, delay
        prevX = freq / 1000
        prevY = delay
    endfor

    for band from 1 to frequency_bands
        Paint circle (mm): "{0.38, 0.48, 0.68}", bandFreq[band] / 1000, bandDelayL[band] * 1000, 1.2
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 4.50, 6.55
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Delay (ms)"
    Select inner viewport: 0.60, 3.85, 4.50, 6.55
    Axes: 0, nyquist / 1000, 0, maxDelay * 1000
    Text bottom: "yes", "Frequency (kHz)"
    Font size: 7
    Text top: "no", "##Filter-bank dispersion##"

    # === LORENTZIAN WEIGHTING ===
    Select outer viewport: 4, 8, 4.25, 6.8
    Select inner viewport: 4.45, 7.70, 4.50, 6.55

    Axes: 0, nyquist / 1000, 0, 1.2
    Paint rectangle: "{0.98, 0.96, 0.97}", 0, nyquist / 1000, 0, 1.2

    Colour: "{0.68, 0.48, 0.60}"
    Line width: 2
    prevX = 0
    prevY = 1 / (1 + ((0 - effectivePeak) / response_width_Hz) ^ 2)
    for f from 1 to 80
        freq = nyquist * f / 80
        response = 1 / (1 + ((freq - effectivePeak) / response_width_Hz) ^ 2)
        Draw line: prevX, prevY, freq / 1000, response
        prevX = freq / 1000
        prevY = response
    endfor

    Colour: "{0.78, 0.38, 0.42}"
    Dashed line
    Draw line: effectivePeak / 1000, 0, effectivePeak / 1000, 1
    Solid line

    for band from 1 to frequency_bands
        Paint circle (mm): "{0.58, 0.38, 0.50}", bandFreq[band] / 1000, bandResponseL[band], 1.2
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 4.05, 4.33, 4.50, 6.55
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Gain"
    Select inner viewport: 4.45, 7.70, 4.50, 6.55
    Axes: 0, nyquist / 1000, 0, 1.2
    Text bottom: "yes", "Frequency (kHz)"
    Font size: 7
    Text top: "no", "##Lorentzian weighting##  |  peak " + fixed$(effectivePeak, 0) + " Hz"

    # === SUMMARY PANEL ===
    Select outer viewport: 0, 8, 7.00, 8.00
    Select inner viewport: 0.60, 7.70, 7.07, 7.93
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 7
    Colour: "{0.25, 0.25, 0.25}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "Bands: " + string$(frequency_bands) + "    Range: " + fixed$(baseFreq, 0) + "-" + fixed$(maxCenter, 0) + " Hz    Stretch: " + fixed$(time_stretch, 2) + " s    Peak: " + fixed$(effectivePeak, 0) + " Hz"
    Colour: "{0.4, 0.4, 0.5}"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Output: " + fixed$(resultDur, 2) + " s  (original " + fixed$(originalDur, 2) + " s + " + fixed$(tail_duration_s, 2) + " s tail)    Response width: " + fixed$(response_width_Hz, 0) + " Hz"
    Colour: "Black"

    Select inner viewport: 0.60, 7.70, 7.07, 7.93
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 8.10
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
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
