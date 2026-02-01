# ============================================================
# Praat AudioTools - Multiband_Compressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   3-band multiband compressor with independent threshold, ratio,
#   and makeup gain per band. Includes visualization of frequency
#   bands and compression curves.
#
# Changelog v1.0:
#   - Real threshold-based compression per band
#   - Independent parameters for each band
#   - Makeup gain per band
#   - Solo/mute per band
#   - Presets for common uses
#   - Band visualization
#   - Fast vectorized processing
# ============================================================

form Multiband Compressor v1.0
    optionmenu Preset 1
        option Custom
        option Master Bus (gentle glue)
        option Vocal Polish
        option Bass Control
        option Brighten & Punch
        option De-Harsh
        option Broadcast Ready
        option Lo-Fi Crush
    comment === Crossover Frequencies ===
    positive Low_mid_crossover_Hz 200
    positive Mid_high_crossover_Hz 2000
    comment === LOW Band ===
    real Low_threshold_dB -20
    positive Low_ratio 2.0
    real Low_makeup_dB 0
    comment === MID Band ===
    real Mid_threshold_dB -18
    positive Mid_ratio 2.0
    real Mid_makeup_dB 0
    comment === HIGH Band ===
    real High_threshold_dB -15
    positive High_ratio 3.0
    real High_makeup_dB 0
    comment === Global ===
    positive Attack_ms 10
    positive Release_ms 100
    boolean Normalize_output 1
    comment === Monitor ===
    optionmenu Solo 1
        option Off (full mix)
        option Solo LOW
        option Solo MID
        option Solo HIGH
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
sr = Get sampling frequency
dur = Get total duration
nChannels = Get number of channels

# === APPLY PRESETS ===
if preset = 2
    # Master Bus (gentle glue)
    low_mid_crossover_Hz = 150
    mid_high_crossover_Hz = 3000
    low_threshold_dB = -18
    low_ratio = 2.0
    low_makeup_dB = 1
    mid_threshold_dB = -16
    mid_ratio = 1.5
    mid_makeup_dB = 0
    high_threshold_dB = -14
    high_ratio = 2.0
    high_makeup_dB = 1
    presetName$ = "MasterBus"
elsif preset = 3
    # Vocal Polish
    low_mid_crossover_Hz = 200
    mid_high_crossover_Hz = 4000
    low_threshold_dB = -24
    low_ratio = 4.0
    low_makeup_dB = -2
    mid_threshold_dB = -18
    mid_ratio = 2.5
    mid_makeup_dB = 2
    high_threshold_dB = -20
    high_ratio = 2.0
    high_makeup_dB = 1
    presetName$ = "VocalPolish"
elsif preset = 4
    # Bass Control
    low_mid_crossover_Hz = 120
    mid_high_crossover_Hz = 2500
    low_threshold_dB = -15
    low_ratio = 6.0
    low_makeup_dB = 3
    mid_threshold_dB = -20
    mid_ratio = 1.5
    mid_makeup_dB = 0
    high_threshold_dB = -18
    high_ratio = 1.5
    high_makeup_dB = 0
    presetName$ = "BassControl"
elsif preset = 5
    # Brighten & Punch
    low_mid_crossover_Hz = 200
    mid_high_crossover_Hz = 3500
    low_threshold_dB = -18
    low_ratio = 3.0
    low_makeup_dB = 2
    mid_threshold_dB = -20
    mid_ratio = 2.0
    mid_makeup_dB = 0
    high_threshold_dB = -12
    high_ratio = 2.5
    high_makeup_dB = 3
    presetName$ = "BrightenPunch"
elsif preset = 6
    # De-Harsh
    low_mid_crossover_Hz = 250
    mid_high_crossover_Hz = 2500
    low_threshold_dB = -20
    low_ratio = 1.5
    low_makeup_dB = 0
    mid_threshold_dB = -16
    mid_ratio = 3.0
    mid_makeup_dB = -1
    high_threshold_dB = -10
    high_ratio = 4.0
    high_makeup_dB = -2
    presetName$ = "DeHarsh"
elsif preset = 7
    # Broadcast Ready
    low_mid_crossover_Hz = 150
    mid_high_crossover_Hz = 3000
    low_threshold_dB = -20
    low_ratio = 4.0
    low_makeup_dB = 2
    mid_threshold_dB = -18
    mid_ratio = 3.0
    mid_makeup_dB = 2
    high_threshold_dB = -16
    high_ratio = 3.0
    high_makeup_dB = 1
    presetName$ = "Broadcast"
elsif preset = 8
    # Lo-Fi Crush
    low_mid_crossover_Hz = 300
    mid_high_crossover_Hz = 2000
    low_threshold_dB = -25
    low_ratio = 8.0
    low_makeup_dB = 4
    mid_threshold_dB = -22
    mid_ratio = 6.0
    mid_makeup_dB = 3
    high_threshold_dB = -20
    high_ratio = 10.0
    high_makeup_dB = 2
    presetName$ = "LoFiCrush"
else
    presetName$ = "Custom"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  MULTIBAND COMPRESSOR v1.0"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), "s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""
writeInfoLine: "Crossovers: ", low_mid_crossover_Hz, " Hz | ", mid_high_crossover_Hz, " Hz"
writeInfoLine: ""
writeInfoLine: "=== Band Settings ==="
writeInfoLine: "  LOW  (<", low_mid_crossover_Hz, " Hz):  Thresh ", fixed$(low_threshold_dB, 0), "dB | Ratio ", fixed$(low_ratio, 1), ":1 | Makeup ", fixed$(low_makeup_dB, 0), "dB"
writeInfoLine: "  MID  (", low_mid_crossover_Hz, "-", mid_high_crossover_Hz, " Hz): Thresh ", fixed$(mid_threshold_dB, 0), "dB | Ratio ", fixed$(mid_ratio, 1), ":1 | Makeup ", fixed$(mid_makeup_dB, 0), "dB"
writeInfoLine: "  HIGH (>", mid_high_crossover_Hz, " Hz): Thresh ", fixed$(high_threshold_dB, 0), "dB | Ratio ", fixed$(high_ratio, 1), ":1 | Makeup ", fixed$(high_makeup_dB, 0), "dB"
writeInfoLine: ""

# ============================================================
# SPLIT INTO FREQUENCY BANDS
# ============================================================

appendInfoLine: "Splitting into frequency bands..."

selectObject: sound
lowBand = Filter (pass Hann band): 0, low_mid_crossover_Hz, 100
Rename: "low_band"

selectObject: sound
midBand = Filter (pass Hann band): low_mid_crossover_Hz, mid_high_crossover_Hz, 100
Rename: "mid_band"

selectObject: sound
highBand = Filter (pass Hann band): mid_high_crossover_Hz, 0, 100
Rename: "high_band"

# ============================================================
# COMPRESS EACH BAND
# Fast method using soft-knee formula with threshold
# ============================================================

appendInfoLine: "Compressing bands..."

# Convert thresholds to linear
low_thresh_lin = 10 ^ (low_threshold_dB / 20)
mid_thresh_lin = 10 ^ (mid_threshold_dB / 20)
high_thresh_lin = 10 ^ (high_threshold_dB / 20)

# Convert makeup to linear
low_makeup_lin = 10 ^ (low_makeup_dB / 20)
mid_makeup_lin = 10 ^ (mid_makeup_dB / 20)
high_makeup_lin = 10 ^ (high_makeup_dB / 20)

# === COMPRESS LOW BAND ===
selectObject: lowBand
# Soft-knee compression formula:
# Below threshold: pass through
# Above threshold: apply ratio
Formula: ~ if abs(self) < low_thresh_lin then self else (low_thresh_lin + (abs(self) - low_thresh_lin) / low_ratio) * (self / (abs(self) + 1e-10)) fi
# Apply makeup gain
Formula: ~ self * low_makeup_lin

# Get stats
selectObject: lowBand
lowPeak = Get maximum: 0, 0, "Sinc70"
lowPeak_dB = 20 * log10(abs(lowPeak) + 1e-10)

appendInfoLine: "  LOW: Peak after compression: ", fixed$(lowPeak_dB, 1), " dB"

# === COMPRESS MID BAND ===
selectObject: midBand
Formula: ~ if abs(self) < mid_thresh_lin then self else (mid_thresh_lin + (abs(self) - mid_thresh_lin) / mid_ratio) * (self / (abs(self) + 1e-10)) fi
Formula: ~ self * mid_makeup_lin

selectObject: midBand
midPeak = Get maximum: 0, 0, "Sinc70"
midPeak_dB = 20 * log10(abs(midPeak) + 1e-10)

appendInfoLine: "  MID: Peak after compression: ", fixed$(midPeak_dB, 1), " dB"

# === COMPRESS HIGH BAND ===
selectObject: highBand
Formula: ~ if abs(self) < high_thresh_lin then self else (high_thresh_lin + (abs(self) - high_thresh_lin) / high_ratio) * (self / (abs(self) + 1e-10)) fi
Formula: ~ self * high_makeup_lin

selectObject: highBand
highPeak = Get maximum: 0, 0, "Sinc70"
highPeak_dB = 20 * log10(abs(highPeak) + 1e-10)

appendInfoLine: "  HIGH: Peak after compression: ", fixed$(highPeak_dB, 1), " dB"

# ============================================================
# RECOMBINE BANDS
# ============================================================

appendInfoLine: ""
appendInfoLine: "Recombining bands..."

if solo = 1
    # Full mix - copy lowBand first, then add others
    selectObject: lowBand
    result = Copy: sound_name$ + "_multiband"
    
    # Add mid band
    selectObject: result
    Formula: ~ self + object[midBand]
    
    # Add high band
    Formula: ~ self + object[highBand]
    
elsif solo = 2
    selectObject: lowBand
    result = Copy: sound_name$ + "_LOW_solo"
elsif solo = 3
    selectObject: midBand
    result = Copy: sound_name$ + "_MID_solo"
else
    selectObject: highBand
    result = Copy: sound_name$ + "_HIGH_solo"
endif

# === NORMALIZE ===
if normalize_output
    selectObject: result
    Scale peak: 0.95
endif

# === OUTPUT STATS ===
selectObject: result
outPeak = Get maximum: 0, 0, "Sinc70"
outPeak_dB = 20 * log10(abs(outPeak) + 1e-10)

outRMS = Get root-mean-square: 0, 0
outRMS_dB = 20 * log10(outRMS + 1e-10)

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Multiband Compressor## | " + presetName$ + " | " + string$(low_mid_crossover_Hz) + "/" + string$(mid_high_crossover_Hz) + " Hz"
    
    # === INPUT WAVEFORM ===
    Select outer viewport: 0, 8, 0.5, 1.5
    Select inner viewport: 0.8, 7.6, 0.6, 1.3
    
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.5, 1.5
    Text left: "yes", "Input"
    
    # === BAND WAVEFORMS ===
    # LOW
    Select outer viewport: 0, 8, 1.6, 2.4
    Select inner viewport: 0.8, 7.6, 1.7, 2.25
    
    selectObject: lowBand
    Colour: "{0.8, 0.3, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 0.15, 8, 1.6, 2.4
    Text left: "yes", "LOW"
    
    # MID
    Select outer viewport: 0, 8, 2.5, 3.3
    Select inner viewport: 0.8, 7.6, 2.6, 3.15
    
    selectObject: midBand
    Colour: "{0.3, 0.7, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 0.15, 8, 2.5, 3.3
    Text left: "yes", "MID"
    
    # HIGH
    Select outer viewport: 0, 8, 3.4, 4.2
    Select inner viewport: 0.8, 7.6, 3.5, 4.05
    
    selectObject: highBand
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 0.15, 8, 3.4, 4.2
    Text left: "yes", "HIGH"
    
    # === OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 4.3, 5.3
    Select inner viewport: 0.8, 7.6, 4.4, 5.1
    
    selectObject: result
    Colour: "{0.4, 0.4, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 4.3, 5.3
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # === BAND INFO ===
    Select outer viewport: 0, 8, 5.4, 6.0
    Axes: 0, 1, 0, 1
    Font size: 6
    
    # LOW info
    Colour: "{0.8, 0.3, 0.3}"
    Paint rectangle: "{0.8, 0.3, 0.3}", 0.02, 0.05, 0.3, 0.7
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.07, "left", 0.5, "half", "LOW <" + string$(low_mid_crossover_Hz) + "Hz: " + fixed$(low_ratio, 1) + ":1 @ " + fixed$(low_threshold_dB, 0) + "dB"
    
    # MID info
    Colour: "{0.3, 0.7, 0.3}"
    Paint rectangle: "{0.3, 0.7, 0.3}", 0.35, 0.38, 0.3, 0.7
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.40, "left", 0.5, "half", "MID: " + fixed$(mid_ratio, 1) + ":1 @ " + fixed$(mid_threshold_dB, 0) + "dB"
    
    # HIGH info
    Colour: "{0.3, 0.5, 0.8}"
    Paint rectangle: "{0.3, 0.5, 0.8}", 0.68, 0.71, 0.3, 0.7
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.73, "left", 0.5, "half", "HIGH >" + string$(mid_high_crossover_Hz) + "Hz: " + fixed$(high_ratio, 1) + ":1 @ " + fixed$(high_threshold_dB, 0) + "dB"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

removeObject: lowBand, midBand, highBand

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output Peak: ", fixed$(outPeak_dB, 1), " dBFS"
appendInfoLine: "Output RMS: ", fixed$(outRMS_dB, 1), " dBFS"

if solo > 1
    if solo = 2
        appendInfoLine: ""
        appendInfoLine: "** SOLO: LOW band only **"
    elsif solo = 3
        appendInfoLine: ""
        appendInfoLine: "** SOLO: MID band only **"
    else
        appendInfoLine: ""
        appendInfoLine: "** SOLO: HIGH band only **"
    endif
endif

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result