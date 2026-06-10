# ============================================================
# Praat AudioTools - Spectral_Filtering_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Viz axis fixes, band-stop clamp, column-form mixing
#
# Changelog v1.1 (from v1.0):
#   - Audio bit-identical to v1.0 for the same parameters (mono).
#   - Viz: set world axes explicitly before the title and the
#     filter-type label. The label was inheriting the spectrum
#     panel's 0-5000 x 0-80 axes -> mis-placed bottom-left.
#   - Band-stop (type 4) now clamps band edges to [20, nyquist*0.95]
#     like band-pass (type 3); prevents negative / over-Nyquist edges
#     on extreme manual settings. No change for in-range settings.
#   - Shelf modes (5-8): mix via column-form object[id] instead of
#     time-interpolated Object_id(x). Bit-identical for mono;
#     unambiguous per-channel alignment for stereo.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral brightness/darkness filter with multiple presets.
#   Modifies timbral character by boosting or cutting frequency bands.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

form Spectral Filtering Effect v1.0
    optionmenu Preset: 1
        option Manual
        option Bright & Airy
        option Warm & Dark
        option Telephone
        option Radio Voice
        option Muffled
        option Presence Boost
        option Bass Boost
        option Treble Cut
        option Lo-Fi
    comment === Manual Parameters ===
    optionmenu Filter_type: 1
        option Low-pass (darken)
        option High-pass (thin)
        option Band-pass (focus)
        option Band-stop (notch)
        option Shelf boost high
        option Shelf cut high
        option Shelf boost low
        option Shelf cut low
    positive Cutoff_frequency 3000
    positive Bandwidth_or_slope 500
    real Gain_db 6
    comment === Output ===
    boolean Normalize_output 1
    real Peak_level 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    # Bright & Airy
    filter_type = 5
    cutoff_frequency = 4000
    bandwidth_or_slope = 1000
    gain_db = 8
    presetName$ = "BrightAiry"
elsif preset = 3
    # Warm & Dark
    filter_type = 1
    cutoff_frequency = 3500
    bandwidth_or_slope = 500
    gain_db = 0
    presetName$ = "WarmDark"
elsif preset = 4
    # Telephone
    filter_type = 3
    cutoff_frequency = 1500
    bandwidth_or_slope = 2000
    gain_db = 0
    presetName$ = "Telephone"
elsif preset = 5
    # Radio Voice
    filter_type = 3
    cutoff_frequency = 2000
    bandwidth_or_slope = 3000
    gain_db = 0
    presetName$ = "RadioVoice"
elsif preset = 6
    # Muffled
    filter_type = 1
    cutoff_frequency = 1000
    bandwidth_or_slope = 300
    gain_db = 0
    presetName$ = "Muffled"
elsif preset = 7
    # Presence Boost
    filter_type = 5
    cutoff_frequency = 2500
    bandwidth_or_slope = 800
    gain_db = 6
    presetName$ = "PresenceBoost"
elsif preset = 8
    # Bass Boost
    filter_type = 7
    cutoff_frequency = 200
    bandwidth_or_slope = 100
    gain_db = 8
    presetName$ = "BassBoost"
elsif preset = 9
    # Treble Cut
    filter_type = 6
    cutoff_frequency = 5000
    bandwidth_or_slope = 1000
    gain_db = -10
    presetName$ = "TrebleCut"
elsif preset = 10
    # Lo-Fi
    filter_type = 1
    cutoff_frequency = 4000
    bandwidth_or_slope = 500
    gain_db = 0
    presetName$ = "LoFi"
else
    presetName$ = "Manual"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: soundID
duration = Get total duration
sampleRate = Get sampling frequency
nyquist = sampleRate / 2
numChannels = Get number of channels

clearinfo
writeInfoLine: "=== Spectral Filtering Effect v1.0 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Sample rate: ", sampleRate, " Hz"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$

# Validate cutoff
if cutoff_frequency >= nyquist * 0.95
    cutoff_frequency = nyquist * 0.9
    appendInfoLine: "Note: Cutoff adjusted to ", fixed$(cutoff_frequency, 0), " Hz (near Nyquist)"
endif

# ============================================================
# APPLY FILTER
# ============================================================

selectObject: soundID

if filter_type = 1
    # Low-pass (darken)
    appendInfoLine: "Filter: Low-pass at ", cutoff_frequency, " Hz"
    resultID = Filter (pass Hann band): 0, cutoff_frequency, bandwidth_or_slope
    
elsif filter_type = 2
    # High-pass (thin)
    appendInfoLine: "Filter: High-pass at ", cutoff_frequency, " Hz"
    resultID = Filter (pass Hann band): cutoff_frequency, nyquist * 0.95, bandwidth_or_slope
    
elsif filter_type = 3
    # Band-pass (focus)
    lowFreq = cutoff_frequency - bandwidth_or_slope / 2
    highFreq = cutoff_frequency + bandwidth_or_slope / 2
    if lowFreq < 20
        lowFreq = 20
    endif
    if highFreq > nyquist * 0.95
        highFreq = nyquist * 0.95
    endif
    appendInfoLine: "Filter: Band-pass ", fixed$(lowFreq, 0), "-", fixed$(highFreq, 0), " Hz"
    resultID = Filter (pass Hann band): lowFreq, highFreq, bandwidth_or_slope / 4
    
elsif filter_type = 4
    # Band-stop (notch)
    lowFreq = cutoff_frequency - bandwidth_or_slope / 2
    highFreq = cutoff_frequency + bandwidth_or_slope / 2
    if lowFreq < 20
        lowFreq = 20
    endif
    if highFreq > nyquist * 0.95
        highFreq = nyquist * 0.95
    endif
    appendInfoLine: "Filter: Band-stop ", fixed$(lowFreq, 0), "-", fixed$(highFreq, 0), " Hz"
    resultID = Filter (stop Hann band): lowFreq, highFreq, bandwidth_or_slope / 4
    
elsif filter_type = 5
    # Shelf boost high (add filtered highs to original)
    appendInfoLine: "Filter: High shelf boost at ", cutoff_frequency, " Hz (+", gain_db, " dB)"
    
    # Extract high frequencies
    highID = Filter (pass Hann band): cutoff_frequency, nyquist * 0.95, bandwidth_or_slope
    
    # Calculate gain multiplier
    gainLin = 10 ^ (gain_db / 20) - 1
    gainLin$ = string$(gainLin)
    
    # Apply gain to highs
    selectObject: highID
    Formula: "self * " + gainLin$
    
    # Mix with original
    selectObject: soundID
    resultID = Copy: "temp_result"
    highId$ = string$(highID)
    Formula: "self + object [" + highId$ + "]"
    
    removeObject: highID
    
elsif filter_type = 6
    # Shelf cut high (subtract filtered highs from original)
    appendInfoLine: "Filter: High shelf cut at ", cutoff_frequency, " Hz (", gain_db, " dB)"
    
    # Extract high frequencies
    highID = Filter (pass Hann band): cutoff_frequency, nyquist * 0.95, bandwidth_or_slope
    
    # Calculate attenuation (gain_db should be negative)
    if gain_db > 0
        gain_db = -gain_db
    endif
    cutAmount = 1 - 10 ^ (gain_db / 20)
    cutAmount$ = string$(cutAmount)
    
    # Apply cut to highs
    selectObject: highID
    Formula: "self * " + cutAmount$
    
    # Subtract from original
    selectObject: soundID
    resultID = Copy: "temp_result"
    highId$ = string$(highID)
    Formula: "self - object [" + highId$ + "]"
    
    removeObject: highID
    
elsif filter_type = 7
    # Shelf boost low (add filtered lows to original)
    appendInfoLine: "Filter: Low shelf boost at ", cutoff_frequency, " Hz (+", gain_db, " dB)"
    
    # Extract low frequencies
    lowID = Filter (pass Hann band): 20, cutoff_frequency, bandwidth_or_slope
    
    # Calculate gain
    gainLin = 10 ^ (gain_db / 20) - 1
    gainLin$ = string$(gainLin)
    
    # Apply gain
    selectObject: lowID
    Formula: "self * " + gainLin$
    
    # Mix with original
    selectObject: soundID
    resultID = Copy: "temp_result"
    lowId$ = string$(lowID)
    Formula: "self + object [" + lowId$ + "]"
    
    removeObject: lowID
    
elsif filter_type = 8
    # Shelf cut low
    appendInfoLine: "Filter: Low shelf cut at ", cutoff_frequency, " Hz (", gain_db, " dB)"
    
    # Extract low frequencies
    lowID = Filter (pass Hann band): 20, cutoff_frequency, bandwidth_or_slope
    
    # Calculate attenuation
    if gain_db > 0
        gain_db = -gain_db
    endif
    cutAmount = 1 - 10 ^ (gain_db / 20)
    cutAmount$ = string$(cutAmount)
    
    # Apply cut
    selectObject: lowID
    Formula: "self * " + cutAmount$
    
    # Subtract from original
    selectObject: soundID
    resultID = Copy: "temp_result"
    lowId$ = string$(lowID)
    Formula: "self - object [" + lowId$ + "]"
    
    removeObject: lowID
endif

# Rename result
selectObject: resultID
Rename: soundName$ + "_" + presetName$

# ============================================================
# NORMALIZE
# ============================================================

if normalize_output
    selectObject: resultID
    Scale peak: peak_level
    appendInfoLine: "Normalized to ", peak_level
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    # Create spectrograms for comparison
    selectObject: soundID
    origSpecID = To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    
    selectObject: resultID
    resSpecID = To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    
    # Calculate spectral averages for comparison
    selectObject: soundID
    origSpectrumID = To Spectrum: "yes"
    
    selectObject: resultID
    resSpectrumID = To Spectrum: "yes"
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Filtering: " + soundName$ + " [" + presetName$ + "]"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 0.6, 2.8
    selectObject: origSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Font size: 9
    Text top: "no", "Original"
    
    # Filtered spectrogram
    Select outer viewport: 4, 8, 0.6, 2.8
    selectObject: resSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Filtered (" + presetName$ + ")"
    
    # Spectrum comparison
    Select outer viewport: 0, 8, 3.0, 5.2
    Select inner viewport: 0.6, 7.6, 3.2, 5.0
    
    selectObject: origSpectrumID
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 1
    Draw: 0, 5000, 0, 80, "no"
    
    selectObject: resSpectrumID
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    Draw: 0, 5000, 0, 80, "no"
    
    # Mark cutoff frequency
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 1
    Axes: 0, 5000, 0, 80
    Dotted line
    Draw line: cutoff_frequency, 0, cutoff_frequency, 80
    Solid line
    
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Level (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Legend
    Font size: 8
    Colour: "{0.6, 0.6, 0.6}"
    Text: 4500, "right", 75, "half", "Original"
    Colour: "{0.2, 0.5, 0.8}"
    Text: 4500, "right", 70, "half", "Filtered"
    Colour: "{0.9, 0.3, 0.3}"
    Text: 4500, "right", 65, "half", "Cutoff: " + fixed$(cutoff_frequency, 0) + " Hz"
    
    # Filter type label
    Select outer viewport: 0, 8, 5.2, 5.6
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    
    if filter_type = 1
        filterDesc$ = "Low-pass filter (removes highs)"
    elsif filter_type = 2
        filterDesc$ = "High-pass filter (removes lows)"
    elsif filter_type = 3
        filterDesc$ = "Band-pass filter (isolates band)"
    elsif filter_type = 4
        filterDesc$ = "Band-stop filter (notch)"
    elsif filter_type = 5
        filterDesc$ = "High shelf boost (+" + fixed$(gain_db, 0) + " dB)"
    elsif filter_type = 6
        filterDesc$ = "High shelf cut (" + fixed$(gain_db, 0) + " dB)"
    elsif filter_type = 7
        filterDesc$ = "Low shelf boost (+" + fixed$(gain_db, 0) + " dB)"
    elsif filter_type = 8
        filterDesc$ = "Low shelf cut (" + fixed$(gain_db, 0) + " dB)"
    endif
    
    Text: 0.5, "centre", 0.5, "half", filterDesc$
    
    # Cleanup visualization objects
    removeObject: origSpecID, resSpecID, origSpectrumID, resSpectrumID
    
    Font size: 10
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", soundName$, "_", presetName$

if play_result
    selectObject: resultID
    Play
endif

selectObject: soundID
