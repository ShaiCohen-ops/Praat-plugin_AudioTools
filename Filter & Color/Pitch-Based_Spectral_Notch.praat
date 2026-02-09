# ============================================================
# Praat AudioTools - Pitch-Based_Spectral_Notch.praat
# Author: Shai Cohen (Enhanced by Praat AudioTools)
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2025) - Enhanced Edition
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based spectral notch filter. Analyzes the sound's mean
#   pitch, then applies a band-stop filter at the fundamental
#   or a selected harmonic. Creates a "hole" in the spectrum.
#
# Technical approach:
#   - Detects mean pitch via autocorrelation
#   - Calculates notch bounds in semitones around target frequency
#   - Applies Hann-windowed band-stop filter (smooth roll-off)
#   - True stereo processing preserves spatial image
#   - STATIC notch based on mean pitch (not time-varying)
#
# Improvements in v1.0:
#   - Fixed preset comparison bug (numeric not string)
#   - Fixed phonetic font errors
#   - Comprehensive 6-panel visualization
#   - Filter response curve display
#   - Before/after spectrum comparison
#   - Waveform visualization
# ============================================================

form Pitch-Based Spectral Notch v1.0
    comment === PRESETS ===
    optionmenu Preset 1
        option Custom
        option Remove Fundamental
        option Remove Second Harmonic
        option Remove Upper Harmonics (4th)
        option Wide Notch
        option Narrow Notch
    comment === Pitch Analysis ===
    positive Min_pitch 75
    positive Max_pitch 600
    comment === Notch Parameters ===
    real Harmonic_number 1
    positive Notch_width_semitones 6
    positive Smoothing_hz 50
    comment === Mix ===
    real Dry_wet_mix 1.0
    comment (1.0 = full wet, 0.0 = full dry)
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset = 2
    harmonic_number = 1
    notch_width_semitones = 4
    smoothing_hz = 40
    presetName$ = "RemoveFundamental"
elsif preset = 3
    harmonic_number = 2
    notch_width_semitones = 4
    smoothing_hz = 40
    presetName$ = "RemoveSecond"
elsif preset = 4
    harmonic_number = 4
    notch_width_semitones = 18
    smoothing_hz = 100
    presetName$ = "RemoveUpper"
elsif preset = 5
    harmonic_number = 1
    notch_width_semitones = 12
    smoothing_hz = 80
    presetName$ = "WideNotch"
elsif preset = 6
    harmonic_number = 1
    notch_width_semitones = 2
    smoothing_hz = 20
    presetName$ = "NarrowNotch"
else
    presetName$ = "Custom"
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

uniqueID$ = string$(randomInteger(10000, 99999))

# ============================================================
# Pitch analysis
# ============================================================
clearinfo
writeInfoLine: "=== Pitch-Based Spectral Notch v1.0 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: ""
appendInfoLine: "Step 1: Analyzing pitch..."

if numChannels > 1
    selectObject: sound
    soundMono = Convert to mono
else
    selectObject: sound
    soundMono = Copy: "mono_" + uniqueID$
endif

selectObject: soundMono
pitchObj = To Pitch: 0.01, min_pitch, max_pitch

selectObject: pitchObj
meanPitch = Get mean: 0, 0, "Hertz"

if meanPitch = undefined
    removeObject: pitchObj, soundMono
    exitScript: "No pitch detected. The sound may be unvoiced or too quiet."
endif

notchCenter = meanPitch * harmonic_number
widthRatio = 2 ^ (notch_width_semitones / 12)
notchLow = notchCenter / sqrt(widthRatio)
notchHigh = notchCenter * sqrt(widthRatio)

appendInfoLine: "  Mean pitch: ", fixed$(meanPitch, 1), " Hz"
appendInfoLine: "  Target harmonic: ", harmonic_number
appendInfoLine: "  Notch center: ", fixed$(notchCenter, 1), " Hz"
appendInfoLine: "  Notch range: ", fixed$(notchLow, 1), " - ", fixed$(notchHigh, 1), " Hz"
appendInfoLine: "  Notch width: ", notch_width_semitones, " semitones"
appendInfoLine: "  Hann smoothing: ", smoothing_hz, " Hz"

removeObject: pitchObj, soundMono

# ============================================================
# Store original spectrum for visualization
# ============================================================
if draw_visualization
    selectObject: sound
    if numChannels > 1
        vizOrigMono = Convert to mono
    else
        vizOrigMono = Copy: "viz_orig_" + uniqueID$
    endif
    
    selectObject: vizOrigMono
    vizOrigSpectrum = To Spectrum: "yes"
    
    selectObject: vizOrigSpectrum
    To Matrix
    vizOrigMatrix = selected("Matrix")
    
    selectObject: vizOrigMatrix
    nFreqBins = Get number of columns
    nyquist = sampleRate / 2
    freqStep = nyquist / 500
    
    viz_freq# = zero#(500)
    viz_mag_orig# = zero#(500)
    
    for i from 1 to 500
        freq = (i - 1) * freqStep
        viz_freq#[i] = freq
        
        if freq > 0 and freq < nyquist
            bin = round(freq * nFreqBins / nyquist)
            if bin < 1
                bin = 1
            endif
            if bin > nFreqBins
                bin = nFreqBins
            endif
            
            realPart = Get value in cell: 1, bin
            imagPart = Get value in cell: 2, bin
            magnitude = sqrt(realPart^2 + imagPart^2)
            
            if magnitude > 1e-10
                viz_mag_orig#[i] = 20 * log10(magnitude)
            else
                viz_mag_orig#[i] = -100
            endif
        else
            viz_mag_orig#[i] = -100
        endif
    endfor
    
    removeObject: vizOrigMatrix
endif

# ============================================================
# Apply filter
# ============================================================
appendInfoLine: ""
appendInfoLine: "Step 2: Applying Hann band-stop filter..."

if numChannels = 1
    selectObject: sound
    filtered = Filter (stop Hann band): notchLow, notchHigh, smoothing_hz
    
    if dry_wet_mix < 1
        selectObject: sound
        dryCopy = Copy: "dry_" + uniqueID$
        selectObject: filtered
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dry_'uniqueID$'(x)"
        removeObject: dryCopy
    endif
    
    selectObject: filtered
    finalOutput = selected("Sound")
else
    selectObject: sound
    Extract one channel: 1
    left = selected("Sound")
    filteredL = Filter (stop Hann band): notchLow, notchHigh, smoothing_hz
    
    selectObject: sound
    Extract one channel: 2
    right = selected("Sound")
    filteredR = Filter (stop Hann band): notchLow, notchHigh, smoothing_hz
    
    if dry_wet_mix < 1
        selectObject: left
        Rename: "dryL_" + uniqueID$
        selectObject: filteredL
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dryL_'uniqueID$'(x)"
        removeObject: "Sound dryL_" + uniqueID$
        
        selectObject: right
        Rename: "dryR_" + uniqueID$
        selectObject: filteredR
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dryR_'uniqueID$'(x)"
        removeObject: "Sound dryR_" + uniqueID$
    else
        removeObject: left, right
    endif
    
    selectObject: filteredL, filteredR
    Combine to stereo
    finalOutput = selected("Sound")
    
    removeObject: filteredL, filteredR
endif

appendInfoLine: "  Filter applied successfully"

# ============================================================
# Store result spectrum for visualization
# ============================================================
if draw_visualization
    selectObject: finalOutput
    if numChannels > 1
        vizResultMono = Convert to mono
    else
        vizResultMono = Copy: "viz_result_" + uniqueID$
    endif
    
    selectObject: vizResultMono
    vizResultSpectrum = To Spectrum: "yes"
    
    selectObject: vizResultSpectrum
    To Matrix
    vizResultMatrix = selected("Matrix")
    
    selectObject: vizResultMatrix
    viz_mag_result# = zero#(500)
    
    for i from 1 to 500
        freq = viz_freq#[i]
        
        if freq > 0 and freq < nyquist
            bin = round(freq * nFreqBins / nyquist)
            if bin < 1
                bin = 1
            endif
            if bin > nFreqBins
                bin = nFreqBins
            endif
            
            realPart = Get value in cell: 1, bin
            imagPart = Get value in cell: 2, bin
            magnitude = sqrt(realPart^2 + imagPart^2)
            
            if magnitude > 1e-10
                viz_mag_result#[i] = 20 * log10(magnitude)
            else
                viz_mag_result#[i] = -100
            endif
        else
            viz_mag_result#[i] = -100
        endif
    endfor
    
    removeObject: vizResultMatrix
    
    viz_filter_response# = zero#(500)
    for i from 1 to 500
        freq = viz_freq#[i]
        
        if freq < notchLow - smoothing_hz
            viz_filter_response#[i] = 0
        elsif freq > notchHigh + smoothing_hz
            viz_filter_response#[i] = 0
        elsif freq >= notchLow + smoothing_hz and freq <= notchHigh - smoothing_hz
            viz_filter_response#[i] = -60
        else
            if freq < notchCenter
                dist = abs(freq - notchLow)
                if dist < smoothing_hz
                    rolloff = (1 - cos(pi * dist / smoothing_hz)) / 2
                    viz_filter_response#[i] = -60 * rolloff
                else
                    viz_filter_response#[i] = -60
                endif
            else
                dist = abs(freq - notchHigh)
                if dist < smoothing_hz
                    rolloff = (1 - cos(pi * dist / smoothing_hz)) / 2
                    viz_filter_response#[i] = -60 * rolloff
                else
                    viz_filter_response#[i] = -60
                endif
            endif
        endif
    endfor
endif

# ============================================================
# Finalize
# ============================================================
appendInfoLine: "Step 3: Finalizing..."

selectObject: finalOutput
Scale peak: scale_peak
Rename: originalName$ + "_notched_" + presetName$

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    appendInfoLine: "Step 4: Drawing visualization..."
    
    Erase all
    
    if duration > 10
        timeTickInterval = 2
    elsif duration > 5
        timeTickInterval = 1
    elsif duration > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif
    
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "Pitch-Based Spectral Notch"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.1, "half", originalName$ + " | " + presetName$ + " | Notch: " + fixed$(notchCenter, 0) + " Hz"
    
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.7, 1.45
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(duration, 2) + " s"
    
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.6, 2.35
    selectObject: finalOutput
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Notched"
    Text bottom: "yes", "Time (s)"
    
    Select outer viewport: 0, 4, 2.5, 4.5
    Select inner viewport: 0.6, 3.7, 2.6, 4.4
    
    selectObject: vizOrigMono
    To Spectrogram: 0.005, 4000, 0.002, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    
    Axes: 0, duration, 0, 4000
    if notchHigh < 4000
        Colour: "{1, 0.85, 0.85}"
        Paint rectangle: "{1, 0.85, 0.85}", 0, duration, notchLow, notchHigh
        
        Colour: "{0.8, 0, 0}"
        Line width: 2
        Draw line: 0, notchCenter, duration, notchCenter
        Line width: 1
        Dotted line
        Draw line: 0, notchLow, duration, notchLow
        Draw line: 0, notchHigh, duration, notchHigh
        Solid line
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original Spectrogram"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: origSpec
    
    Select outer viewport: 4, 8, 2.5, 4.5
    Select inner viewport: 4.4, 7.7, 2.6, 4.4
    
    selectObject: vizResultMono
    To Spectrogram: 0.005, 4000, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Result Spectrogram"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: resultSpec
    
    Select outer viewport: 0, 4, 4.6, 6.8
    Select inner viewport: 0.6, 3.7, 4.7, 6.7
    
    max_freq_plot = min(4000, nyquist)
    
    Axes: 0, max_freq_plot, -70, 5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_freq_plot, -70, 5
    
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 2
    for i from 1 to 499
        f1 = viz_freq#[i]
        f2 = viz_freq#[i + 1]
        if f1 <= max_freq_plot and f2 <= max_freq_plot
            r1 = viz_filter_response#[i]
            r2 = viz_filter_response#[i + 1]
            Draw line: f1, r1, f2, r2
        endif
    endfor
    Line width: 1
    
    Colour: "{0.8, 0, 0}"
    Dotted line
    Draw line: notchCenter, -70, notchCenter, 5
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Magnitude (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Filter Response (Hann Band-Stop)"
    
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, max_freq_plot, 0
    Draw line: 0, -20, max_freq_plot, -20
    Draw line: 0, -40, max_freq_plot, -40
    Draw line: 0, -60, max_freq_plot, -60
    Solid line
    
    Select outer viewport: 4, 8, 4.6, 6.8
    Select inner viewport: 4.4, 7.7, 4.7, 6.7
    
    min_mag = -80
    max_mag = -20
    
    Axes: 0, max_freq_plot, min_mag, max_mag
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_freq_plot, min_mag, max_mag
    
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 1.5
    for i from 1 to 499
        f1 = viz_freq#[i]
        f2 = viz_freq#[i + 1]
        if f1 <= max_freq_plot and f2 <= max_freq_plot
            m1 = viz_mag_orig#[i]
            m2 = viz_mag_orig#[i + 1]
            if m1 > min_mag and m2 > min_mag
                Draw line: f1, m1, f2, m2
            endif
        endif
    endfor
    
    Colour: "{0.3, 0.7, 0.3}"
    Line width: 2
    for i from 1 to 499
        f1 = viz_freq#[i]
        f2 = viz_freq#[i + 1]
        if f1 <= max_freq_plot and f2 <= max_freq_plot
            m1 = viz_mag_result#[i]
            m2 = viz_mag_result#[i + 1]
            if m1 > min_mag and m2 > min_mag
                Draw line: f1, m1, f2, m2
            endif
        endif
    endfor
    Line width: 1
    
    Colour: "{1, 0.85, 0.85}"
    Paint rectangle: "{1, 0.85, 0.85}", notchLow, notchHigh, min_mag, max_mag
    
    Colour: "{0.8, 0, 0}"
    Dotted line
    Draw line: notchCenter, min_mag, notchCenter, max_mag
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Magnitude (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Magnitude Spectrum Comparison"
    
    Select outer viewport: 0, 8, 6.9, 7.5
    Select inner viewport: 0, 8, 6.9, 7.5
    Axes: 0, 1, 0, 1
    Font size: 7
    
    Colour: "Black"
    Text: 0.02, "left", 0.7, "half", "Notch parameters:"
    Text: 0.25, "left", 0.7, "half", "Center = " + fixed$(notchCenter, 1) + " Hz (H" + string$(harmonic_number) + ")"
    Text: 0.5, "left", 0.7, "half", "Width = " + string$(notch_width_semitones) + " ST"
    Text: 0.65, "left", 0.7, "half", "Smoothing = " + string$(smoothing_hz) + " Hz"
    
    x_pos = 0.02
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 2
    Draw line: x_pos, 0.3, x_pos + 0.03, 0.3
    Colour: "Black"
    Line width: 1
    Text: x_pos + 0.04, "left", 0.3, "half", "Original"
    
    x_pos = 0.15
    Colour: "{0.3, 0.7, 0.3}"
    Line width: 2
    Draw line: x_pos, 0.3, x_pos + 0.03, 0.3
    Colour: "Black"
    Line width: 1
    Text: x_pos + 0.04, "left", 0.3, "half", "Notched"
    
    x_pos = 0.28
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 2
    Draw line: x_pos, 0.3, x_pos + 0.03, 0.3
    Colour: "Black"
    Line width: 1
    Text: x_pos + 0.04, "left", 0.3, "half", "Filter Response"
    
    Font size: 6
    Text: 0.02, "left", 0.05, "half", "Static notch based on mean pitch (" + fixed$(meanPitch, 1) + " Hz) - not time-varying"
    
    Font size: 10
    
    removeObject: vizOrigMono, vizOrigSpectrum, vizResultMono, vizResultSpectrum
endif

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", originalName$, "_notched_", presetName$
appendInfoLine: "Channels: ", numChannels
appendInfoLine: "Mean pitch: ", fixed$(meanPitch, 1), " Hz"
appendInfoLine: "Notch center: ", fixed$(notchCenter, 1), " Hz"
appendInfoLine: "Notch range: ", fixed$(notchLow, 0), " - ", fixed$(notchHigh, 0), " Hz"
appendInfoLine: "Dry/wet mix: ", fixed$(dry_wet_mix * 100, 0), "% wet"
if draw_visualization
    appendInfoLine: "Visualization complete"
endif

if play_after_processing
    Play
endif