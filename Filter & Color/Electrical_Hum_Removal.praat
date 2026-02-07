# ============================================================
# Praat AudioTools - Electrical_Hum_Removal.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - Complete rewrite with visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Removes electrical/power line hum (50Hz or 60Hz) and harmonics
#   using cascaded band-stop (notch) filters. Can auto-detect actual
#   hum frequency or use fixed values. Includes before/after spectrum
#   visualization with notch locations marked.
#
# Features:
#   - Auto-detection of hum frequency (finds strongest peak near 50/60Hz)
#   - Fixed frequency mode (50Hz or 60Hz)
#   - Adaptive bandwidth (scales with harmonic number)
#   - Dry/wet mix for subtle removal
#   - Comprehensive visualization: spectra, notch positions, waveforms
#   - Presets for common scenarios
#
# Categories: Audio Restoration, Spectral Processing, Noise Reduction
#
# Usage:
#   Select a Sound with electrical hum and run. Use auto-detect for
#   variable-frequency hum or fixed mode for stable AC power hum.
#   Start with 50% dry/wet for subtle removal, increase for stronger effect.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis 
#   Toolkit for Experimental Composition.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Electrical Hum Removal v2.0
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Auto-detect (mild)
        option 50 Hz European (strong)
        option 60 Hz American (strong)
        option Studio Recording (subtle)
        option Field Recording (aggressive)
    
    comment === Detection Mode ===
    optionmenu Detection_mode: 1
        option Auto-detect hum frequency
        option Fixed 50 Hz
        option Fixed 60 Hz
    
    comment === Filter Settings ===
    integer Max_harmonic 8
    positive Base_bandwidth_(Hz) 1.5
    real Bandwidth_scaling 1.3
    comment (Higher harmonics get wider notches: BW × scaling^n)
    
    comment === Processing ===
    real Dry_wet_mix 1.0
    comment (0 = original, 1 = full removal, 0.5 = blend)
    
    comment === Output ===
    boolean Normalize_output 1
    real Peak_level 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Auto-detect mild
    detection_mode = 1
    max_harmonic = 6
    base_bandwidth = 1.0
    bandwidth_scaling = 1.2
    dry_wet_mix = 0.7
    presetName$ = "AutoMild"
elsif preset = 3
    # 50 Hz strong
    detection_mode = 2
    max_harmonic = 10
    base_bandwidth = 2.0
    bandwidth_scaling = 1.4
    dry_wet_mix = 1.0
    presetName$ = "50Hz_Strong"
elsif preset = 4
    # 60 Hz strong
    detection_mode = 3
    max_harmonic = 10
    base_bandwidth = 2.0
    bandwidth_scaling = 1.4
    dry_wet_mix = 1.0
    presetName$ = "60Hz_Strong"
elsif preset = 5
    # Studio (subtle)
    detection_mode = 1
    max_harmonic = 5
    base_bandwidth = 0.8
    bandwidth_scaling = 1.1
    dry_wet_mix = 0.5
    presetName$ = "Studio"
elsif preset = 6
    # Field (aggressive)
    detection_mode = 1
    max_harmonic = 12
    base_bandwidth = 2.5
    bandwidth_scaling = 1.5
    dry_wet_mix = 1.0
    presetName$ = "Field"
else
    presetName$ = "Custom"
endif

startTime = stopwatch

clearinfo
writeInfoLine: "=== Electrical Hum Removal v2.0 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

selectObject: originalID
samplingFreq = Get sampling frequency
duration = Get total duration
nyquist = samplingFreq / 2

appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Sample rate: ", samplingFreq, " Hz"
appendInfoLine: "Nyquist: ", fixed$(nyquist, 1), " Hz"
appendInfoLine: ""

# ============================================================
# STAGE 1: DETECT OR SET HUM FREQUENCY
# ============================================================
appendInfo: "Stage 1: Hum frequency detection... "

if detection_mode = 1
    # Auto-detect using Ltas
    selectObject: originalID
    
    # Extract beginning for analysis (first 2 seconds)
    analysisLen = min(2.0, duration)
    Extract part: 0, analysisLen, "rectangular", 1, "no"
    partID = selected("Sound")
    
    # Create long-term average spectrum
    To Ltas: 100
    ltasID = selected("Ltas")
    
    # Search for peak near 50Hz
    peak50 = 50
    max50 = -999
    for testFreq from 45 to 55
        val = Get value at frequency: testFreq, "Cubic"
        if val <> undefined and val > max50
            max50 = val
            peak50 = testFreq
        endif
    endfor
    
    # Search for peak near 60Hz
    peak60 = 60
    max60 = -999
    for testFreq from 55 to 65
        val = Get value at frequency: testFreq, "Cubic"
        if val <> undefined and val > max60
            max60 = val
            peak60 = testFreq
        endif
    endfor
    
    # Choose stronger peak
    if max50 > max60
        baseFreq = peak50
        detectedType$ = "~50Hz"
    else
        baseFreq = peak60
        detectedType$ = "~60Hz"
    endif
    
    removeObject: partID, ltasID
    
    appendInfoLine: fixed$(baseFreq, 1), " Hz (", detectedType$, ")"
    
elsif detection_mode = 2
    baseFreq = 50
    appendInfoLine: "50 Hz (fixed)"
else
    baseFreq = 60
    appendInfoLine: "60 Hz (fixed)"
endif

# ============================================================
# STAGE 2: APPLY CASCADED NOTCH FILTERS
# ============================================================
appendInfo: "Stage 2: Applying notch filters... "

selectObject: originalID
processedID = Copy: "filtered_temp"

validHarmonics = 0
notchFreqs# = zero#(max_harmonic)
notchBandwidths# = zero#(max_harmonic)

for harmonic from 1 to max_harmonic
    freq = baseFreq * harmonic
    
    # Scale bandwidth with harmonic number
    currentBW = base_bandwidth * (bandwidth_scaling ^ (harmonic - 1))
    
    # Only filter if below Nyquist (with margin)
    if freq < nyquist * 0.85
        validHarmonics += 1
        
        lowCut = max(1, freq - currentBW)
        highCut = freq + currentBW
        
        selectObject: processedID
        Filter (stop Hann band): lowCut, highCut, currentBW * 2
        filteredID = selected("Sound")
        
        # Store for visualization
        notchFreqs#[validHarmonics] = freq
        notchBandwidths#[validHarmonics] = currentBW
        
        removeObject: processedID
        processedID = filteredID
        
        if harmonic mod 3 = 0
            appendInfo: "."
        endif
    endif
endfor

appendInfoLine: " ", validHarmonics, " harmonics"

# ============================================================
# STAGE 3: DRY/WET MIX
# ============================================================
appendInfo: "Stage 3: Mixing... "

if dry_wet_mix < 0.99
    selectObject: originalID
    origName$ = selected$("Sound")
    
    selectObject: processedID
    procName$ = selected$("Sound")
    
    wetStr$ = fixed$(dry_wet_mix, 4)
    dryStr$ = fixed$(1 - dry_wet_mix, 4)
    
    selectObject: processedID
    Formula: "self * " + wetStr$ + " + Sound_" + origName$ + "[] * " + dryStr$
    
    appendInfoLine: "done (", fixed$(dry_wet_mix * 100, 0), "% wet)"
else
    appendInfoLine: "100% wet"
endif

# ============================================================
# STAGE 4: NORMALIZE
# ============================================================
if normalize_output
    selectObject: processedID
    Scale peak: peak_level
    appendInfoLine: "Normalized to ", peak_level
endif

selectObject: processedID
Rename: originalName$ + "_hum_removed_" + presetName$
outputID = selected("Sound")

processingTime = stopwatch - startTime

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Base frequency: ", fixed$(baseFreq, 2), " Hz"
appendInfoLine: "Harmonics removed: ", validHarmonics

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Electrical Hum Removal: " + originalName$ + " [" + presetName$ + "]"
    
    # === ORIGINAL SPECTRUM ===
    Select outer viewport: 0, 5, 0.6, 3.0
    Select inner viewport: 0.5, 4.7, 0.8, 2.8
    
    selectObject: originalID
    To Ltas: 100
    origLtasID = selected("Ltas")
    
    maxFreqDisplay = min(1000, nyquist)
    
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, maxFreqDisplay, 20, 80, "no", "Curve"
    
    # Mark notch positions
    for h to validHarmonics
        freq = notchFreqs#[h]
        bw = notchBandwidths#[h]
        
        if freq < maxFreqDisplay
            Colour: "{0.9, 0.3, 0.3}"
            Line width: 2
            Draw line: freq, 20, freq, 80
            
            # Show notch width
            Colour: "{1.0, 0.7, 0.7}"
            Line width: 1
            Paint rectangle: "{1.0, 0.9, 0.9}", freq - bw, freq + bw, 20, 25
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    
    Font size: 8
    Text top: "no", "Original Spectrum + Notch Positions"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # === PROCESSED SPECTRUM ===
    Select outer viewport: 5, 10, 0.6, 3.0
    Select inner viewport: 5.5, 9.7, 0.8, 2.8
    
    selectObject: outputID
    To Ltas: 100
    procLtasID = selected("Ltas")
    
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, maxFreqDisplay, 20, 80, "no", "Curve"
    
    # Mark removed frequencies
    for h to validHarmonics
        freq = notchFreqs#[h]
        if freq < maxFreqDisplay
            Colour: "{0.5, 0.8, 0.5}"
            Line width: 1
            Dashed line
            Draw line: freq, 20, freq, 80
            Solid line
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    
    Font size: 8
    Text top: "no", "Processed Spectrum"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # === WAVEFORMS ===
    # Original
    Select outer viewport: 0, 5, 3.2, 4.2
    Select inner viewport: 0.5, 4.7, 3.3, 4.1
    
    selectObject: originalID
    displayDur = min(0.5, duration)
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, displayDur, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original (0-" + fixed$(displayDur, 2) + "s)"
    Text left: "yes", "Amp"
    
    # Processed
    Select outer viewport: 5, 10, 3.2, 4.2
    Select inner viewport: 5.5, 9.7, 3.3, 4.1
    
    selectObject: outputID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, displayDur, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Processed"
    Text left: "yes", "Amp"
    
    # === NOTCH DETAILS TABLE ===
    Select outer viewport: 0, 10, 4.4, 5.5
    Select inner viewport: 0.5, 9.7, 4.5, 5.4
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.3, 0.3, 0.3}"
    
    # Header
    Text: 0.05, "left", 0.9, "half", "##Notch Filters Applied##"
    
    # List harmonics
    maxDisplay = min(validHarmonics, 8)
    for h to maxDisplay
        yPos = 0.75 - (h - 1) * 0.08
        freq = notchFreqs#[h]
        bw = notchBandwidths#[h]
        
        text$ = "H" + string$(h) + ": " + fixed$(freq, 1) + " Hz  (±" + fixed$(bw, 1) + " Hz)"
        Text: 0.08, "left", yPos, "half", text$
    endfor
    
    if validHarmonics > 8
        Text: 0.08, "left", 0.05, "half", "... and " + string$(validHarmonics - 8) + " more"
    endif
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === INFO PANEL ===
    Select outer viewport: 0, 10, 5.6, 6.1
    Select inner viewport: 0.5, 9.7, 5.65, 6.05
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.5, "half", "Base: " + fixed$(baseFreq, 2) + " Hz | Harmonics: " + string$(validHarmonics) + " | Mix: " + fixed$(dry_wet_mix * 100, 0) + "% | Time: " + fixed$(processingTime, 2) + "s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    
    # Cleanup spectra
    removeObject: origLtasID, procLtasID
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: outputID

appendInfoLine: ""
appendInfoLine: "Output: ", selected$("Sound")

if play_result
    appendInfoLine: "Playing processed sound..."
    Play
endif

selectObject: originalID
