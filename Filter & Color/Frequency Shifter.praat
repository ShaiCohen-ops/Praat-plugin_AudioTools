# ============================================================
# Praat AudioTools - Frequency Shifter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bode-style frequency shifter using Single Sideband Modulation.
#   Shifts all frequencies by a constant Hz amount (not pitch scaling).
#   This creates inharmonic spectra - harmonic relationships are destroyed.
#
# Theory:
#   Frequency shifting multiplies the signal by a complex exponential:
#   y(t) = Re{x(t) · e^(j·2π·f_shift·t)}
#   Using Hilbert transform for the imaginary part:
#   y(t) = x(t)·cos(2π·f·t) - H{x(t)}·sin(2π·f·t)  [upper sideband]
#   y(t) = x(t)·cos(2π·f·t) + H{x(t)}·sin(2π·f·t)  [lower sideband]
#
# Musical effects:
#   - Small shifts (5-20 Hz): Chorus-like thickening
#   - Medium shifts (50-300 Hz): Metallic, bell-like, robotic
#   - Large shifts (>500 Hz): Alien, unintelligible speech
#   - Negative shifts: Darker, subharmonic content
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Frequency Shifter
    optionmenu Preset: 1
        option Custom
        option Subtle Detune (15 Hz)
        option Chorus Thick (8 Hz)
        option Metallic Ring (200 Hz)
        option Robot Voice (150 Hz)
        option Horror Alien (666 Hz)
        option Deep Sub (-100 Hz)
        option Bell Shimmer (1200 Hz)
    real shift_hz 100
    optionmenu Direction: 1
        option Up (positive shift)
        option Down (negative shift)
    real dry_wet_mix 1.0
    positive scale_peak 0.95
    boolean draw_visualization 1
    boolean play_after_processing 1
endform

# ============================================================
# Apply presets
# ============================================================
if preset$ = "Subtle Detune (15 Hz)"
    shift_hz = 15
    direction = 1
elif preset$ = "Chorus Thick (8 Hz)"
    shift_hz = 8
    direction = 1
elif preset$ = "Metallic Ring (200 Hz)"
    shift_hz = 200
    direction = 1
elif preset$ = "Robot Voice (150 Hz)"
    shift_hz = 150
    direction = 1
elif preset$ = "Horror Alien (666 Hz)"
    shift_hz = 666
    direction = 1
elif preset$ = "Deep Sub (-100 Hz)"
    shift_hz = 100
    direction = 2
elif preset$ = "Bell Shimmer (1200 Hz)"
    shift_hz = 1200
    direction = 1
endif

# Apply direction
if direction = 2
    shift_hz = -shift_hz
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
sampleRate = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels

# Clamp dry/wet
if dry_wet_mix < 0
    dry_wet_mix = 0
endif
if dry_wet_mix > 1
    dry_wet_mix = 1
endif

uniqueID$ = string$(randomInteger(10000, 99999))

# ============================================================
# Report
# ============================================================
writeInfoLine: "Frequency Shifter"
appendInfoLine: "================="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Shift: ", shift_hz, " Hz"
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Channels: ", numChannels
appendInfoLine: ""

# ============================================================
# Process using Hilbert transform + SSB modulation
# ============================================================
appendInfoLine: "Processing..."

# Angular frequency
omega = 2 * pi * shift_hz

if numChannels = 1
    # --- MONO PROCESSING ---
    
    # Create Hilbert transform (90° phase shift)
    selectObject: sound
    hilbert = Copy: "hilbert_" + uniqueID$
    
    # Convert to spectrum, shift phase by -90°, convert back
    selectObject: hilbert
    To Spectrum: "yes"
    specHilbert = selected("Spectrum")
    
    # Hilbert transform in frequency domain:
    # H(f) = -j·sign(f)·X(f)
    # For positive frequencies: multiply by -j (rotate -90°)
    # For negative frequencies: multiply by +j (rotate +90°)
    # In Praat Spectrum (which stores only positive frequencies):
    # Real part becomes Imaginary, Imaginary becomes -Real
    Formula: "if row = 1 then self[2, col] else -self[1, col] fi"
    
    To Sound
    hilbertSound = selected("Sound")
    removeObject: specHilbert
    
    selectObject: hilbert
    removeObject: hilbert
    hilbert = hilbertSound
    Rename: "hilbert_" + uniqueID$
    
    # Create output
    selectObject: sound
    result = Copy: "shifted_" + uniqueID$
    
    # SSB modulation:
    # Upper sideband (shift up): x·cos(ωt) - H{x}·sin(ωt)
    # Lower sideband (shift down): x·cos(ωt) + H{x}·sin(ωt)
    selectObject: result
    if shift_hz >= 0
        Formula: "Sound_'originalName$'(x) * cos('omega' * x) - Sound_hilbert_'uniqueID$'(x) * sin('omega' * x)"
    else
        Formula: "Sound_'originalName$'(x) * cos('omega' * x) + Sound_hilbert_'uniqueID$'(x) * sin('omega' * x)"
    endif
    
    removeObject: hilbert

else
    # --- STEREO PROCESSING ---
    
    selectObject: sound
    Extract one channel: 1
    left = selected("Sound")
    Rename: "left_" + uniqueID$
    
    selectObject: sound
    Extract one channel: 2
    right = selected("Sound")
    Rename: "right_" + uniqueID$
    
    # Process left channel
    selectObject: left
    To Spectrum: "yes"
    specL = selected("Spectrum")
    Formula: "if row = 1 then self[2, col] else -self[1, col] fi"
    To Sound
    hilbertL = selected("Sound")
    Rename: "hilbertL_" + uniqueID$
    removeObject: specL
    
    selectObject: left
    shiftedL = Copy: "shiftedL_" + uniqueID$
    if shift_hz >= 0
        Formula: "Sound_left_'uniqueID$'(x) * cos('omega' * x) - Sound_hilbertL_'uniqueID$'(x) * sin('omega' * x)"
    else
        Formula: "Sound_left_'uniqueID$'(x) * cos('omega' * x) + Sound_hilbertL_'uniqueID$'(x) * sin('omega' * x)"
    endif
    
    # Process right channel
    selectObject: right
    To Spectrum: "yes"
    specR = selected("Spectrum")
    Formula: "if row = 1 then self[2, col] else -self[1, col] fi"
    To Sound
    hilbertR = selected("Sound")
    Rename: "hilbertR_" + uniqueID$
    removeObject: specR
    
    selectObject: right
    shiftedR = Copy: "shiftedR_" + uniqueID$
    if shift_hz >= 0
        Formula: "Sound_right_'uniqueID$'(x) * cos('omega' * x) - Sound_hilbertR_'uniqueID$'(x) * sin('omega' * x)"
    else
        Formula: "Sound_right_'uniqueID$'(x) * cos('omega' * x) + Sound_hilbertR_'uniqueID$'(x) * sin('omega' * x)"
    endif
    
    # Combine to stereo
    selectObject: shiftedL, shiftedR
    Combine to stereo
    result = selected("Sound")
    
    removeObject: left, right, hilbertL, hilbertR, shiftedL, shiftedR
endif

# ============================================================
# Dry/wet mix
# ============================================================
if dry_wet_mix < 1
    selectObject: result
    Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_'originalName$'(x)"
endif

selectObject: result
Scale peak: scale_peak

if shift_hz >= 0
    Rename: originalName$ + "_shift+" + string$(abs(shift_hz)) + "Hz"
else
    Rename: originalName$ + "_shift" + string$(shift_hz) + "Hz"
endif

finalOutput = selected("Sound")

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    Erase all
    
    # Create spectrograms
    selectObject: sound
    if numChannels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "origMono_" + uniqueID$
    endif
    
    selectObject: origMono
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    
    selectObject: finalOutput
    if numChannels > 1
        resultMono = Convert to mono
    else
        resultMono = Copy: "resultMono_" + uniqueID$
    endif
    
    selectObject: resultMono
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    
    # Determine time ticks
    if duration > 10
        timeTick = 2
    elsif duration > 5
        timeTick = 1
    elsif duration > 2
        timeTick = 0.5
    else
        timeTick = 0.25
    endif
    
    # PANEL 1: Original spectrogram
    Select outer viewport: 0, 6, 0, 3
    Select inner viewport: 0.7, 5.8, 0.4, 2.7
    
    selectObject: origSpec
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Black
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "##Original##"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    # PANEL 2: Shifted spectrogram
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.7, 5.8, 3.4, 5.7
    
    selectObject: resultSpec
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Black
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    if shift_hz >= 0
        Text top: "no", "##Shifted +" + string$(abs(shift_hz)) + " Hz##"
    else
        Text top: "no", "##Shifted " + string$(shift_hz) + " Hz##"
    endif
    Marks bottom every: 1, timeTick, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: origMono, resultMono, origSpec, resultSpec
endif

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "================="
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    Play
endif