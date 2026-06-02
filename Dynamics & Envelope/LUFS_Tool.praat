# ============================================================
# Praat AudioTools - LUFS_Tool.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LUFS loudness measurement and normalization tool with
#   K-weighting, true peak, loudness range, and visualization.
#   Based on ITU-R BS.1770 / EBU R128 standards.
#
# Changelog v1.0:
#   - Added K-weighting filter, short-term LUFS, LRA, meter viz
#
# Changelog v2.0:
#   - Real ITU-R BS.1770-4 K-weighting: two cascaded biquads
#     (high-shelf + RLB high-pass), coefficients derived for the
#     actual sample rate. Replaces the v1.0 placeholder, which
#     ring-modulated at 2 kHz and discarded its own filter.
#   - Gated Integrated LUFS: 400 ms blocks, absolute -70 gate +
#     relative -10 LU gate (was ungated whole-file mean square).
#   - Channel-power summation for multichannel (no mono averaging).
#   - LRA from the gated short-term distribution (95th - 10th pct).
#   - ASCII status markers (dropped non-rendering emoji).
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
# K-WEIGHTING FILTER (ITU-R BS.1770-4)
# Two cascaded biquads, coefficients derived for this sample rate:
#   Stage 1: high-shelf (+~4 dB above ~1.68 kHz)
#   Stage 2: RLB high-pass (~38 Hz)
# Implemented recursively (see @biquad): x-history from an
# unmodified copy, y-history from self[col-k]. All channels filtered.
# ============================================================

appendInfoLine: "Applying K-weighting filter (BS.1770-4)..."

# Stage 1 - high shelf
hs_f0 = 1681.974450955533
hs_Q = 0.7071752369554196
hs_K = tan(pi * hs_f0 / sr)
hs_Vh = 10 ^ (3.999843853973347 / 20)
hs_Vb = hs_Vh ^ 0.4996667741545416
hs_a0 = 1 + hs_K / hs_Q + hs_K * hs_K
hs_b0 = (hs_Vh + hs_Vb * hs_K / hs_Q + hs_K * hs_K) / hs_a0
hs_b1 = 2 * (hs_K * hs_K - hs_Vh) / hs_a0
hs_b2 = (hs_Vh - hs_Vb * hs_K / hs_Q + hs_K * hs_K) / hs_a0
hs_a1 = 2 * (hs_K * hs_K - 1) / hs_a0
hs_a2 = (1 - hs_K / hs_Q + hs_K * hs_K) / hs_a0

# Stage 2 - high pass
hp_f0 = 38.13547087602444
hp_Q = 0.5003270373238773
hp_K = tan(pi * hp_f0 / sr)
hp_a0 = 1 + hp_K / hp_Q + hp_K * hp_K
hp_b0 = 1.0
hp_b1 = -2.0
hp_b2 = 1.0
hp_a1 = 2 * (hp_K * hp_K - 1) / hp_a0
hp_a2 = (1 - hp_K / hp_Q + hp_K * hp_K) / hp_a0

selectObject: input
k_weighted = Copy: "k_weighted"
@biquad: k_weighted, hs_b0, hs_b1, hs_b2, hs_a1, hs_a2
@biquad: k_weighted, hp_b0, hp_b1, hp_b2, hp_a1, hp_a2

# ============================================================
# INTEGRATED LUFS (gated, BS.1770)
# 400 ms blocks / 100 ms hop. Block loudness uses the sum of
# channel mean-squares (= nChannels * meanSquare for G=1 channels).
# Absolute gate -70 LUFS, then relative gate 10 LU below the mean.
# ============================================================

appendInfoLine: "Calculating gated Integrated LUFS..."

blockDur = 0.4
hop = 0.1
if duration >= blockDur
    nBlocks = floor((duration - blockDur) / hop) + 1
else
    nBlocks = 1
endif

sumMS_abs = 0
countAbs = 0
for bk from 1 to nBlocks
    t1 = (bk - 1) * hop
    t2 = t1 + blockDur
    if t2 > duration
        t2 = duration
    endif
    selectObject: k_weighted
    rms_b = Get root-mean-square: t1, t2
    ms_b = nChannels * rms_b * rms_b
    blockMS[bk] = ms_b
    if ms_b > 0
        blockL[bk] = -0.691 + 10 * log10(ms_b)
    else
        blockL[bk] = -100
    endif
    if blockL[bk] >= -70
        sumMS_abs = sumMS_abs + ms_b
        countAbs = countAbs + 1
    endif
endfor

if countAbs > 0
    relGate = -0.691 + 10 * log10(sumMS_abs / countAbs) - 10
else
    relGate = -70
endif

sumMS_rel = 0
countRel = 0
for bk from 1 to nBlocks
    if blockL[bk] >= -70 and blockL[bk] >= relGate
        sumMS_rel = sumMS_rel + blockMS[bk]
        countRel = countRel + 1
    endif
endfor

if countRel > 0
    integrated_LUFS = -0.691 + 10 * log10(sumMS_rel / countRel)
else
    integrated_LUFS = -70
endif

appendInfoLine: "  Integrated LUFS: ", fixed$(integrated_LUFS, 1), " (", countRel, " gated blocks)"

# ============================================================
# SHORT-TERM LUFS (3 s window / 1 s hop) and LRA
# LRA (EBU Tech 3342): relative-gated short-term distribution,
# 95th minus 10th percentile.
# ============================================================

appendInfoLine: "Calculating Short-term LUFS and LRA..."

stWin = 3.0
stHop = 1.0
if duration >= stWin
    numWindows = floor((duration - stWin) / stHop) + 1
else
    numWindows = 1
endif

maxShortTerm = -100
stSumMS = 0
stCount = 0
for w from 1 to numWindows
    t1 = (w - 1) * stHop
    t2 = t1 + stWin
    if t2 > duration
        t2 = duration
    endif
    selectObject: k_weighted
    rms_s = Get root-mean-square: t1, t2
    ms_s = nChannels * rms_s * rms_s
    if ms_s > 0
        lufs_s = -0.691 + 10 * log10(ms_s)
    else
        lufs_s = -100
    endif
    shortTermLUFS[w] = lufs_s
    shortTermT[w] = (t1 + t2) / 2
    if lufs_s > maxShortTerm
        maxShortTerm = lufs_s
    endif
    if lufs_s >= -70
        stSumMS = stSumMS + ms_s
        stCount = stCount + 1
    endif
endfor

appendInfoLine: "  Max Short-term: ", fixed$(maxShortTerm, 1), " LUFS"

if stCount > 0
    stRelGate = -0.691 + 10 * log10(stSumMS / stCount) - 20
else
    stRelGate = -70
endif

nLRA = 0
for w from 1 to numWindows
    if shortTermLUFS[w] >= -70 and shortTermLUFS[w] >= stRelGate
        nLRA = nLRA + 1
        lraVals[nLRA] = shortTermLUFS[w]
    endif
endfor

# insertion sort (ascending)
for i from 2 to nLRA
    key = lraVals[i]
    j = i - 1
    while j >= 1 and lraVals[j] > key
        lraVals[j + 1] = lraVals[j]
        j = j - 1
    endwhile
    lraVals[j + 1] = key
endfor

if nLRA >= 2
    loIdx = floor(0.10 * (nLRA - 1)) + 1
    hiIdx = floor(0.95 * (nLRA - 1)) + 1
    loudnessRange = lraVals[hiIdx] - lraVals[loIdx]
else
    loudnessRange = 0
endif
if loudnessRange < 0
    loudnessRange = 0
endif

appendInfoLine: "  Loudness Range: ", fixed$(loudnessRange, 1), " LU"

removeObject: k_weighted

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
    appendInfoLine: "  [WARNING] Large gap (", fixed$(gainNeeded - headroom, 1), " dB)"
    appendInfoLine: "      Compression/limiting required to reach target"
    appendInfoLine: "      without severe clipping."
    situation$ = "WARNING"
elsif gainNeeded > headroom
    appendInfoLine: "  [CAUTION] Limiting needed (", fixed$(gainNeeded - headroom, 1), " dB)"
    appendInfoLine: "      Some peak reduction will occur."
    situation$ = "CAUTION"
elsif gainNeeded < -1
    appendInfoLine: "  [i] Audio is LOUDER than target"
    appendInfoLine: "      Gain reduction will be applied."
    situation$ = "REDUCE"
else
    appendInfoLine: "  [OK] Target achievable with clean gain"
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
        appendInfoLine: "  [X] CLIPPING! Peak at ", fixed$(finalPeak_dB, 2), " dBFS"
        Rename: input$ + "_CLIPPED"
    else
        appendInfoLine: "  [OK] Applied ", fixed$(gainNeeded, 1), " dB"
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
        l1 = shortTermLUFS[w - 1]
        l2 = shortTermLUFS[w]
        
        if l1 > -60 and l2 > -60
            Draw line: shortTermT[w - 1], l1, shortTermT[w], l2
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

# ============================================================
# Biquad (Direct Form I), applied in place over all channels.
# y[n] = b0 x[n] + b1 x[n-1] + b2 x[n-2] - a1 y[n-1] - a2 y[n-2]
# x-history is read from an unmodified copy; y-history from self.
# ============================================================
procedure biquad: .sig, .b0, .b1, .b2, .a1, .a2
    selectObject: .sig
    .xcopy = Copy: "biquad_x"
    selectObject: .sig
    .x$ = string$(.xcopy)
    Formula: "if col > 2 then (" + string$(.b0) + ")*object[" + .x$ + ",row,col] + (" + string$(.b1) + ")*object[" + .x$ + ",row,col-1] + (" + string$(.b2) + ")*object[" + .x$ + ",row,col-2] - (" + string$(.a1) + ")*self[col-1] - (" + string$(.a2) + ")*self[col-2] else self fi"
    removeObject: .xcopy
endproc
