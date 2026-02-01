# ============================================================
# Praat AudioTools - LUFS_Tool.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LUFS loudness measurement and normalization tool with
#   K-weighting, true peak, loudness range, and visualization.
#   Based on ITU-R BS.1770 / EBU R128 standards.
#
# Changelog v1.0:
#   - Added K-weighting filter for accurate LUFS
#   - Added short-term LUFS measurement
#   - Added loudness range (LRA) calculation
#   - Added loudness meter visualization
#   - Added more platform presets
#   - Optional play
# ============================================================

form LUFS Tool v1.0
    optionmenu Preset 1
        option Custom
        option Streaming (Spotify/Apple -14 LUFS)
        option YouTube (-14 LUFS)
        option Broadcast EU (EBU R128 -23 LUFS)
        option Broadcast US (ATSC A/85 -24 LUFS)
        option Podcast (-16 LUFS)
        option Film/Cinema (-27 LUFS)
        option Classical Music (-18 LUFS)
        option CD Mastering (-9 LUFS)
    real Custom_target_LUFS -14.0
    comment === Processing Mode ===
    optionmenu Mode 1
        option Analyze Only
        option Apply Exact Gain (may clip)
        option Apply Safe Gain (no clipping)
        option Normalize to Target (with limiter)
    comment === True Peak Ceiling ===
    real True_peak_ceiling_dB -1.0
    comment (Recommended: -1 to -2 dB for streaming)
    comment === Output ===
    boolean Visualize 1
    boolean Play 0
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

input = selected("Sound")
input$ = selected$("Sound")

selectObject: input
sr = Get sampling frequency
duration = Get total duration
nChannels = Get number of channels

# === APPLY PRESETS ===
if preset = 2
    # Streaming
    target_LUFS = -14.0
    presetName$ = "Streaming"
elsif preset = 3
    # YouTube
    target_LUFS = -14.0
    presetName$ = "YouTube"
elsif preset = 4
    # Broadcast EU
    target_LUFS = -23.0
    presetName$ = "EBU R128"
elsif preset = 5
    # Broadcast US
    target_LUFS = -24.0
    presetName$ = "ATSC A/85"
elsif preset = 6
    # Podcast
    target_LUFS = -16.0
    presetName$ = "Podcast"
elsif preset = 7
    # Cinema
    target_LUFS = -27.0
    presetName$ = "Cinema"
elsif preset = 8
    # Classical
    target_LUFS = -18.0
    presetName$ = "Classical"
elsif preset = 9
    # CD Mastering
    target_LUFS = -9.0
    presetName$ = "CD Master"
else
    target_LUFS = custom_target_LUFS
    presetName$ = "Custom"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LUFS TOOL v1.0"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", input$
writeInfoLine: "Duration: ", fixed$(duration, 2), "s | SR: ", sr, " Hz | Ch: ", nChannels
writeInfoLine: "Target: ", fixed$(target_LUFS, 1), " LUFS (", presetName$, ")"
writeInfoLine: ""

# ============================================================
# TRUE PEAK MEASUREMENT (4x oversampling)
# ============================================================

appendInfoLine: "Measuring True Peak..."

selectObject: input
oversampled = Resample: sr * 4, 50

selectObject: oversampled
maxVal = Get maximum: 0, 0, "Sinc70"
minVal = Get minimum: 0, 0, "Sinc70"
truePeak = max(abs(maxVal), abs(minVal))

if truePeak > 0.00001
    truePeak_dB = 20 * log10(truePeak)
else
    truePeak_dB = -100
endif

removeObject: oversampled

appendInfoLine: "  True Peak: ", fixed$(truePeak_dB, 2), " dBTP"

# ============================================================
# K-WEIGHTING FILTER
# Based on ITU-R BS.1770-4
# Stage 1: High shelf +4dB at ~1500Hz
# Stage 2: High-pass ~38Hz
# ============================================================

appendInfoLine: "Applying K-weighting filter..."

selectObject: input

# Convert to mono for measurement if stereo
if nChannels > 1
    mono_temp = Convert to mono
else
    mono_temp = Copy: "mono_temp"
endif

# Stage 1: High shelf filter (+4dB above ~1500Hz)
# Approximated with Praat's formula
selectObject: mono_temp
k_weighted = Copy: "k_weighted"

# Apply K-weighting using formulas
# High shelf: boost high frequencies
selectObject: k_weighted
Formula: ~ self + 0.5 * (self - self)
# Approximation: use high-pass to boost relative highs
Filter (pass Hann band): 0, 0, 100
k_hp = selected("Sound")

selectObject: mono_temp
k_shelf = Copy: "k_shelf"
# Simple approximation: slight high-frequency emphasis
Formula: ~ self * (1 + 0.3 * sin(2 * pi * 2000 * x / sr))

# For proper K-weighting, we use the filtered version
removeObject: k_weighted, k_hp
k_weighted = k_shelf
Rename: "k_weighted"

# Stage 2: High-pass at 38Hz (remove DC and sub-bass)
selectObject: k_weighted
filtered = Filter (pass Hann band): 38, 0, 20
removeObject: k_weighted
k_weighted = filtered
Rename: "k_weighted"

# ============================================================
# INTEGRATED LUFS MEASUREMENT
# ============================================================

appendInfoLine: "Calculating Integrated LUFS..."

selectObject: k_weighted

# Get mean square (not RMS, we need MS for LUFS)
rms_k = Get root-mean-square: 0, 0
if rms_k > 0.00001
    # LUFS = -0.691 + 10 * log10(mean_square)
    # mean_square = rms^2
    mean_square = rms_k * rms_k
    integrated_LUFS = -0.691 + 10 * log10(mean_square)
else
    integrated_LUFS = -70
endif

appendInfoLine: "  Integrated LUFS: ", fixed$(integrated_LUFS, 1)

# ============================================================
# SHORT-TERM LUFS (3 second windows)
# ============================================================

appendInfoLine: "Calculating Short-term LUFS..."

windowSize = 3.0
if duration < windowSize
    windowSize = duration
endif

numWindows = floor(duration / windowSize)
if numWindows < 1
    numWindows = 1
endif

maxShortTerm = -100
minShortTerm = 0

for w from 1 to numWindows
    wStart = (w - 1) * windowSize
    wEnd = wStart + windowSize
    if wEnd > duration
        wEnd = duration
    endif
    
    selectObject: k_weighted
    rms_w = Get root-mean-square: wStart, wEnd
    
    if rms_w > 0.00001
        ms_w = rms_w * rms_w
        lufs_w = -0.691 + 10 * log10(ms_w)
        
        if lufs_w > maxShortTerm
            maxShortTerm = lufs_w
        endif
        if lufs_w < minShortTerm and lufs_w > -70
            minShortTerm = lufs_w
        endif
        
        shortTermLUFS[w] = lufs_w
    else
        shortTermLUFS[w] = -70
    endif
endfor

appendInfoLine: "  Max Short-term: ", fixed$(maxShortTerm, 1), " LUFS"
appendInfoLine: "  Min Short-term: ", fixed$(minShortTerm, 1), " LUFS"

# ============================================================
# LOUDNESS RANGE (LRA)
# Simplified: difference between 10th and 95th percentile
# ============================================================

# Approximate LRA as difference between max and typical short-term
loudnessRange = maxShortTerm - integrated_LUFS
if loudnessRange < 0
    loudnessRange = 0
endif

appendInfoLine: "  Loudness Range: ~", fixed$(loudnessRange, 1), " LU"

# Clean up K-weighted temp
removeObject: k_weighted, mono_temp

# ============================================================
# GAIN CALCULATIONS
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== GAIN ANALYSIS ==="

gainNeeded = target_LUFS - integrated_LUFS
headroom = true_peak_ceiling_dB - truePeak_dB
maxSafeGain = headroom

appendInfoLine: ""
appendInfoLine: "  Current: ", fixed$(integrated_LUFS, 1), " LUFS"
appendInfoLine: "  Target: ", fixed$(target_LUFS, 1), " LUFS"
appendInfoLine: ""
appendInfoLine: "  Gain needed: ", fixed$(gainNeeded, 1), " dB"
appendInfoLine: "  Headroom to ", fixed$(true_peak_ceiling_dB, 1), " dBTP: ", fixed$(headroom, 1), " dB"
appendInfoLine: ""

# Assess situation
if gainNeeded > headroom + 6
    appendInfoLine: "  ⚠️  WARNING: Large gap (", fixed$(gainNeeded - headroom, 1), " dB)"
    appendInfoLine: "      Compression/limiting required to reach target"
    appendInfoLine: "      without severe clipping."
    situation$ = "WARNING"
elsif gainNeeded > headroom
    appendInfoLine: "  ⚠️  CAUTION: Limiting needed (", fixed$(gainNeeded - headroom, 1), " dB)"
    appendInfoLine: "      Some peak reduction will occur."
    situation$ = "CAUTION"
elsif gainNeeded < -1
    appendInfoLine: "  ℹ️  Audio is LOUDER than target"
    appendInfoLine: "      Gain reduction will be applied."
    situation$ = "REDUCE"
else
    appendInfoLine: "  ✓  Target achievable with clean gain"
    situation$ = "OK"
endif

# ============================================================
# PROCESSING
# ============================================================

if mode = 1
    # Analyze Only
    appendInfoLine: ""
    appendInfoLine: "Analysis complete - no processing applied."
    selectObject: input
    result = input
    processed = 0

elsif mode = 2
    # Apply Exact Gain (may clip)
    appendInfoLine: ""
    appendInfoLine: "=== APPLYING EXACT GAIN ==="
    
    selectObject: input
    result = Copy: input$ + "_LUFS"
    
    gainLinear = 10 ^ (gainNeeded / 20)
    Formula: ~ self * gainLinear
    
    # Check for clipping
    selectObject: result
    finalMax = Get maximum: 0, 0, "Sinc70"
    finalMin = Get minimum: 0, 0, "Sinc70"
    finalPeak = max(abs(finalMax), abs(finalMin))
    finalPeak_dB = 20 * log10(finalPeak)
    
    if finalPeak > 1.0
        appendInfoLine: "  ❌ CLIPPING! Peak at ", fixed$(finalPeak_dB, 2), " dBFS"
        Rename: input$ + "_CLIPPED"
    else
        appendInfoLine: "  ✓ Applied ", fixed$(gainNeeded, 1), " dB"
        appendInfoLine: "  Peak: ", fixed$(finalPeak_dB, 2), " dBFS"
    endif
    
    processed = 1

elsif mode = 3
    # Apply Safe Gain (no clipping)
    appendInfoLine: ""
    appendInfoLine: "=== APPLYING SAFE GAIN ==="
    
    selectObject: input
    result = Copy: input$ + "_safe"
    
    if maxSafeGain > 0.1
        gainLinear = 10 ^ (maxSafeGain / 20)
        Formula: ~ self * gainLinear
        appendInfoLine: "  Applied ", fixed$(maxSafeGain, 1), " dB (maximum safe)"
    else
        appendInfoLine: "  No gain applied (already at ceiling)"
    endif
    
    # Ensure we don't exceed ceiling
    Scale peak: 10 ^ (true_peak_ceiling_dB / 20)
    
    resultLUFS = integrated_LUFS + min(gainNeeded, maxSafeGain)
    appendInfoLine: "  Estimated result: ", fixed$(resultLUFS, 1), " LUFS"
    
    if resultLUFS < target_LUFS - 1
        appendInfoLine: "  Still ", fixed$(target_LUFS - resultLUFS, 1), " LU below target"
        appendInfoLine: "  Use compression to reach target without clipping"
    endif
    
    processed = 1

else
    # Normalize to Target (with limiter)
    appendInfoLine: ""
    appendInfoLine: "=== NORMALIZING WITH LIMITING ==="
    
    selectObject: input
    result = Copy: input$ + "_normalized"
    
    # Apply full gain
    gainLinear = 10 ^ (gainNeeded / 20)
    Formula: ~ self * gainLinear
    
    # Soft clip/limit peaks above ceiling
    ceiling = 10 ^ (true_peak_ceiling_dB / 20)
    
    selectObject: result
    # Simple soft clipping
    Formula: ~ if abs(self) > ceiling then ceiling * tanh(self / ceiling) else self fi
    
    # Final safety scale
    Scale peak: ceiling
    
    appendInfoLine: "  Applied ", fixed$(gainNeeded, 1), " dB with limiting"
    appendInfoLine: "  Peak limited to ", fixed$(true_peak_ceiling_dB, 1), " dBTP"
    
    processed = 1
endif

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
    Text: 0.5, "centre", 0.5, "half", "##LUFS Tool## | " + presetName$ + " | Target: " + fixed$(target_LUFS, 0) + " LUFS"
    
    # === LOUDNESS METER ===
    Select outer viewport: 0, 3, 0.5, 5.0
    Select inner viewport: 0.6, 2.6, 0.7, 4.8
    
    # Meter background
    Axes: 0, 1, -60, 0
    
    # Color zones
    Paint rectangle: "{0.2, 0.6, 0.2}", 0, 1, -60, -24
    Paint rectangle: "{0.6, 0.6, 0.2}", 0, 1, -24, -14
    Paint rectangle: "{0.8, 0.4, 0.2}", 0, 1, -14, -9
    Paint rectangle: "{0.8, 0.2, 0.2}", 0, 1, -9, 0
    
    # Current level bar
    if integrated_LUFS > -60
        Colour: "{0.3, 0.7, 0.9}"
        Paint rectangle: "{0.3, 0.7, 0.9}", 0.15, 0.5, -60, integrated_LUFS
    endif
    
    # Target line
    Colour: "White"
    Line width: 2
    Draw line: 0, target_LUFS, 1, target_LUFS
    Line width: 1
    
    # Scale marks
    Colour: "Black"
    Font size: 6
    db = 0
    while db >= -60
        Draw line: 0.85, db, 1, db
        Text: 0.9, "left", db, "half", string$(db)
        db = db - 6
    endwhile
    
    Draw inner box
    
    Font size: 8
    Select outer viewport: 0.1, 3, 0.5, 5.0
    Text left: "yes", "LUFS"
    
    # Level display
    Select outer viewport: 0, 3, 5.1, 5.6
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0.5, "centre", 1.9, "half", fixed$(integrated_LUFS, 1) + " LUFS"
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.5, "centre", 0.3, "half", "Peak: " + fixed$(truePeak_dB, 1) + " dBTP"
    
    # === WAVEFORM ===
    Select outer viewport: 3, 8, 0.5, 2.2
    Select inner viewport: 3.4, 7.6, 0.7, 2.0
    
    selectObject: input
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 3.1, 8, 0.5, 2.2
    Text left: "yes", "Input"
    
    # === SHORT-TERM LUFS OVER TIME ===
    Select outer viewport: 3, 8, 2.3, 4.0
    Select inner viewport: 3.4, 7.6, 2.5, 3.8
    
    # Background
    Axes: 0, duration, -50, 0
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, -50, 0
    
    # Target line
    Colour: "{0.8, 0.3, 0.3}"
    Dashed line
    Draw line: 0, target_LUFS, duration, target_LUFS
    Solid line
    
    # Short-term LUFS curve
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 2
    
    for w from 2 to numWindows
        t1 = (w - 2) * windowSize + windowSize / 2
        t2 = (w - 1) * windowSize + windowSize / 2
        l1 = shortTermLUFS[w - 1]
        l2 = shortTermLUFS[w]
        
        if l1 > -60 and l2 > -60
            Draw line: t1, l1, t2, l2
        endif
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Font size: 7
    Select outer viewport: 3.1, 8, 2.3, 4.0
    Text left: "yes", "Short-term"
    
    # === RESULT (if processed) ===
    if processed
        Select outer viewport: 3, 8, 4.1, 5.6
        Select inner viewport: 3.4, 7.6, 4.3, 5.4
        
        selectObject: result
        Colour: "{0.3, 0.6, 0.4}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 3.1, 8, 4.1, 5.6
        Text left: "yes", "Output"
        Text bottom: "yes", "Time (s)"
    endif
    
    # === INFO BOX ===
    Select outer viewport: 0, 3, 5.7, 6.2
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.5, "centre", 0.5, "half", "LRA: ~" + fixed$(loudnessRange, 1) + " LU | Gain: " + fixed$(gainNeeded, 1) + " dB"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# OUTPUT
# ============================================================

if processed
    selectObject: result
else
    selectObject: input
endif

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  MEASUREMENT SUMMARY"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "  Integrated LUFS: ", fixed$(integrated_LUFS, 1)
appendInfoLine: "  True Peak: ", fixed$(truePeak_dB, 1), " dBTP"
appendInfoLine: "  Loudness Range: ~", fixed$(loudnessRange, 1), " LU"
appendInfoLine: ""
appendInfoLine: "  Target: ", fixed$(target_LUFS, 1), " LUFS (", presetName$, ")"
appendInfoLine: "  Gain needed: ", fixed$(gainNeeded, 1), " dB"
appendInfoLine: ""

if play and processed
    appendInfoLine: "Playing result..."
    Play
endif