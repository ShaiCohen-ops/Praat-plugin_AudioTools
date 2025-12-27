# ============================================================
# Praat AudioTools - Spectral Hole Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
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
#   - Applies Hann-windowed band-stop filter (smooth edges)
#   - True stereo processing preserves spatial image
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit
#   for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Spectral Hole Filter
    comment Pitch-based spectral notch filter.
    optionmenu Preset: 1
        option Custom
        option Remove Fundamental
        option Remove Second Harmonic
        option Remove Upper Harmonics
        option Wide Notch
        option Narrow Notch
    positive min_pitch 75
    positive max_pitch 600
    real harmonic_number 1
    positive notch_width_semitones 6
    positive smoothing_hz 50
    real dry_wet_mix 1.0
    positive scale_peak 0.95
    boolean play_after_processing 1
    boolean draw_visualization 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Remove Fundamental"
    harmonic_number = 1
    notch_width_semitones = 4
    smoothing_hz = 40
elif preset$ = "Remove Second Harmonic"
    harmonic_number = 2
    notch_width_semitones = 4
    smoothing_hz = 40
elif preset$ = "Remove Upper Harmonics"
    harmonic_number = 4
    notch_width_semitones = 18
    smoothing_hz = 100
elif preset$ = "Wide Notch"
    harmonic_number = 1
    notch_width_semitones = 12
    smoothing_hz = 80
elif preset$ = "Narrow Notch"
    harmonic_number = 1
    notch_width_semitones = 2
    smoothing_hz = 20
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
writeInfoLine: "Spectral Hole Filter"
appendInfoLine: "===================="
appendInfoLine: "Input: ", originalName$
appendInfoLine: ""
appendInfoLine: "[1/3] Analyzing pitch..."

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

# Calculate notch bounds
notchCenter = meanPitch * harmonic_number
widthRatio = 2 ^ (notch_width_semitones / 12)
notchLow = notchCenter / sqrt(widthRatio)
notchHigh = notchCenter * sqrt(widthRatio)

appendInfoLine: "  Mean pitch: ", fixed$(meanPitch, 1), " Hz"
appendInfoLine: "  Notch center: ", fixed$(notchCenter, 1), " Hz (harmonic ", harmonic_number, ")"
appendInfoLine: "  Notch range: ", fixed$(notchLow, 1), " - ", fixed$(notchHigh, 1), " Hz"

# Cleanup pitch objects
removeObject: pitchObj, soundMono

# ============================================================
# Apply filter
# ============================================================
appendInfoLine: ""
appendInfoLine: "[2/3] Applying notch filter..."

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

# ============================================================
# Finalize
# ============================================================
appendInfoLine: "[3/3] Finalizing..."

selectObject: finalOutput
Scale peak: scale_peak
Rename: originalName$ + "_notched"

# ============================================================
# Visualization
# ============================================================
if draw_visualization
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
    
    # PANEL 1: Original
    Select outer viewport: 0, 6, 0, 3
    Select inner viewport: 0.6, 5.8, 0.4, 2.7
    
    selectObject: sound
    if numChannels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "orig_viz_" + uniqueID$
    endif
    
    selectObject: origMono
    To Spectrogram: 0.005, 4000, 0.002, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    
    # Draw notch region
    Axes: 0, duration, 0, 4000
    if notchHigh < 4000
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
    
    Line width: 1
    Black
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "##Original## (shaded = notch at " + fixed$(notchCenter, 0) + " Hz)"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: origSpec, origMono
    
    # PANEL 2: Result
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.6, 5.8, 3.4, 5.7
    
    selectObject: finalOutput
    if numChannels > 1
        resultMono = Convert to mono
    else
        resultMono = Copy: "result_viz_" + uniqueID$
    endif
    
    selectObject: resultMono
    To Spectrogram: 0.005, 4000, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    
    Black
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "##Result## - spectral hole applied"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: resultSpec, resultMono
endif

selectObject: finalOutput

if play_after_processing
    Play
endif

appendInfoLine: ""
appendInfoLine: "===================="
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", originalName$, "_notched"
appendInfoLine: "Channels: ", numChannels
appendInfoLine: "Notch: ", fixed$(notchLow, 0), " - ", fixed$(notchHigh, 0), " Hz"
appendInfoLine: "Dry/wet: ", fixed$(dry_wet_mix * 100, 0), "%"
if draw_visualization
    appendInfoLine: "Visualization in Picture window."
endif