# ============================================================
# Praat AudioTools - Multi-Band Onset Detector.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-band onset detector for transient/sustain separation.
#   Analyzes energy increases across frequency bands to detect
#   onsets. Separates audio into transient (percussive) and
#   sustain (tonal) components for spectromorphological analysis.
#
#   Pipeline:
#     1. Logarithmic filterbank splits signal into N bands
#     2. Per-band rectification + smoothing -> band envelopes
#     3. Summed envelope -> onset function (positive derivative)
#     4. Sigmoid mask from onset function (soft gating)
#     5. Mask dilation via max-decay recursion (attack lookahead
#        + release decay, peak-preserving, zero latency)
#     6. Mask upsampled to original SR, applied at full quality
#     7. Sustain = original - transient (perfect reconstruction)
#
# Changelog v1.1:
#   - FIXED (critical): onset derivative was computed in place
#     (self[col-1] reads the value just written -> recursion
#     y[n] = max(0, x[n] - y[n-1]), a Nyquist-rate zigzag, not a
#     derivative). Now differences a frozen copy via object[].
#   - Derivative now taken over a 5 ms hop, so detector behaviour
#     no longer depends on Working_sample_rate_Hz.
#   - FIXED (critical): dilation replaced. Convolution was
#     unnormalized (values summed to >>1) and un-shifted (mask
#     opened attack_ms LATE, clipping the attacks). The re-sigmoid
#     also floored the mask at ~0.27 (27% sustain leak). New
#     dilation: forward max-decay pass (release) + reversed pass
#     (attack lookahead). Mask stays in [0,1], peaks preserved,
#     onsets pre-opened by the attack time as intended.
#   - FIXED (critical): inputs with >2 channels crashed with
#     undefined transId. Channel processing generalized to any
#     channel count.
#   - Frequency range now clamped to the ANALYSIS nyquist before
#     band edges are computed (was: original nyquist), preventing
#     silently collapsed / duplicated top bands.
#   - Mask application guarded against off-by-a-few-samples
#     length mismatch after resampling.
#   - Energy split reported before transient gain and relabelled
#     as RMS balance (RMS is not additive energy).
#
# Changelog v1.0:
#   - Fixed: mask now applied at full SR (upsample mask, not output)
#   - Fixed: convolution dilation cropped to correct duration
#   - Fixed: min() replaced with Praat-safe conditional
#   - Replaced hard threshold with sigmoid soft mask
#   - Sustain computed by subtraction (perfect reconstruction)
#   - Removed independent normalize (preserves energy ratio)
#   - Added per-band envelope visualization
#   - Library-style visualization with stats panel + legend
#   - Added energy ratio reporting
#   - Stereo support via per-channel processing
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Analysis & Feature Extraction
# ============================================================

# --- Input Validation ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

# ============================================================
# FORM
# ============================================================
form Multi-Band Onset Detector v1.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Drums/Percussion (sharp attacks)
        option Piano/Plucked (medium attacks)
        option Voice/Speech (consonants)
        option Full Mix (broadband)
        option Soft Transients (gentle onsets)
    comment === Detection ===
    real Threshold_dB 6.0
    positive Sigmoid_steepness 2.0
    positive Attack_ms 20
    positive Release_ms 50
    comment === Filterbank ===
    positive Low_frequency_Hz 100
    positive High_frequency_Hz 8000
    integer Number_of_bands 4
    comment === Analysis ===
    positive Envelope_smoothing_Hz 50
    positive Working_sample_rate_Hz 16000
    comment === Output ===
    real Transient_gain_dB 0.0
    boolean Show_visualization 1
endform

# ============================================================
# APPLY PRESETS
# ============================================================
if preset = 2
    # Drums/Percussion: sharp attacks, wide bandwidth
    presetName$ = "Drums/Percussion"
    threshold_dB = 4.0
    sigmoid_steepness = 3.0
    attack_ms = 10
    release_ms = 30
    low_frequency_Hz = 50
    high_frequency_Hz = 12000
    number_of_bands = 5
    envelope_smoothing_Hz = 80
elsif preset = 3
    # Piano/Plucked: moderate attacks
    presetName$ = "Piano/Plucked"
    threshold_dB = 6.0
    sigmoid_steepness = 2.0
    attack_ms = 15
    release_ms = 80
    low_frequency_Hz = 80
    high_frequency_Hz = 8000
    number_of_bands = 4
    envelope_smoothing_Hz = 50
elsif preset = 4
    # Voice/Speech: consonant detection
    presetName$ = "Voice/Speech"
    threshold_dB = 5.0
    sigmoid_steepness = 2.5
    attack_ms = 25
    release_ms = 40
    low_frequency_Hz = 100
    high_frequency_Hz = 6000
    number_of_bands = 4
    envelope_smoothing_Hz = 60
elsif preset = 5
    # Full Mix: broadband, many bands
    presetName$ = "Full Mix"
    threshold_dB = 5.0
    sigmoid_steepness = 2.0
    attack_ms = 20
    release_ms = 60
    low_frequency_Hz = 50
    high_frequency_Hz = 16000
    number_of_bands = 6
    envelope_smoothing_Hz = 50
elsif preset = 6
    # Soft Transients: very gentle detection
    presetName$ = "Soft Transients"
    threshold_dB = 8.0
    sigmoid_steepness = 1.5
    attack_ms = 30
    release_ms = 100
    low_frequency_Hz = 100
    high_frequency_Hz = 8000
    number_of_bands = 4
    envelope_smoothing_Hz = 40
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================
epsilon = 1e-9

selectObject: originalSound
nChannels = Get number of channels
totalDur = Get total duration
originalSR = Get sampling frequency
nyquist = originalSR / 2

if totalDur < 0.05
    exitScript: "Sound is too short (minimum 0.05 s)."
endif

# Working SR: use for analysis only, output stays at original SR
workingSR = working_sample_rate_Hz
if workingSR > originalSR
    workingSR = originalSR
endif
workNyquist = workingSR / 2

# Clamp frequency range to the ANALYSIS nyquist (v1.1).
# Band edges are computed once from this range, so clamping here
# guarantees monotone, valid edges: the per-band rescue that could
# collapse a top band into a duplicate full-range band is gone.
if high_frequency_Hz > workNyquist - 100
    high_frequency_Hz = workNyquist - 100
endif
if low_frequency_Hz >= high_frequency_Hz
    low_frequency_Hz = 50
endif
if low_frequency_Hz >= high_frequency_Hz
    exitScript: "Frequency range collapsed: raise Working_sample_rate_Hz or lower Low_frequency_Hz."
endif

writeInfoLine: "=== Multi-Band Onset Detector v1.1 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "  ", fixed$(totalDur, 3), " s | ",
    ... originalSR, " Hz | ", nChannels, " ch"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Bands: ", number_of_bands,
    ... " (", fixed$(low_frequency_Hz, 0), "-",
    ... fixed$(high_frequency_Hz, 0), " Hz)"
appendInfoLine: "Threshold: ", fixed$(threshold_dB, 1),
    ... " dB | Steepness: ", fixed$(sigmoid_steepness, 1)
appendInfoLine: "Attack: ", fixed$(attack_ms, 0),
    ... " ms | Release: ", fixed$(release_ms, 0), " ms"
appendInfoLine: ""

# ============================================================
# STEP 1: Create working mono at analysis SR
# ============================================================
appendInfoLine: "[1/6] Preprocessing..."

selectObject: originalSound
if nChannels > 1
    monoFull = Convert to mono
else
    monoFull = Copy: "mono_full"
endif

if workingSR < originalSR
    selectObject: monoFull
    workSound = Resample: workingSR, 50
    appendInfoLine: "  Downsampled to ", workingSR, " Hz for analysis"
else
    selectObject: monoFull
    workSound = Copy: "work"
    workingSR = originalSR
endif

# ============================================================
# STEP 2: Multi-band filterbank + envelope extraction
# ============================================================
appendInfoLine: ""
appendInfoLine: "[2/6] Filterbank (", number_of_bands, " bands)..."

# Logarithmic band edges
for bi from 0 to number_of_bands
    bandEdge_'bi' = low_frequency_Hz * (high_frequency_Hz / low_frequency_Hz) ^ (bi / number_of_bands)
endfor

# Combined envelope (sum of all band envelopes)
selectObject: workSound
combinedEnv = Copy: "combined_env"
Formula: "0"

# Per-band processing
for bi from 1 to number_of_bands
    biM1 = bi - 1
    loEdge = bandEdge_'biM1'
    hiEdge = bandEdge_'bi'
    
    # Edges are guaranteed monotone and < workNyquist - 100
    # by the up-front clamp in SETUP (v1.1).
    
    appendInfoLine: "  Band ", bi, ": ",
        ... fixed$(loEdge, 0), "-", fixed$(hiEdge, 0), " Hz"
    
    # Filter to band
    selectObject: workSound
    filtered = Filter (pass Hann band): loEdge, hiEdge, 100
    
    # Rectify (abs)
    Formula: "abs(self)"
    
    # Smooth to get envelope
    bandEnv = Filter (pass Hann band): 0, envelope_smoothing_Hz, 20
    
    # Store for visualization
    if show_visualization
        selectObject: bandEnv
        vizBandEnv_'bi' = Copy: "viz_band_" + string$(bi)
    endif
    
    # Add to combined
    bandEnvId = bandEnv
    selectObject: combinedEnv
    Formula: "self + object[bandEnvId]"
    
    removeObject: filtered, bandEnv
endfor

# ============================================================
# STEP 3: Onset function (positive derivative)
# ============================================================
appendInfoLine: ""
appendInfoLine: "[3/6] Onset function..."

selectObject: combinedEnv
onsetFunc = Copy: "onset_func"

# Positive half-wave rectified derivative: captures energy increases.
# v1.1: MUST difference the frozen source via object[] -- inside
# Formula, self[col-1] reads the value just written (in-place,
# left-to-right evaluation), which turned this into the recursion
# y[n] = max(0, x[n] - y[n-1]): a Nyquist-rate zigzag, not a
# derivative. Differencing over a 5 ms hop also decouples the
# onset function's scale from the working sample rate.
combinedEnvSrc = combinedEnv
onsetLag = round(workingSR * 0.005)
if onsetLag < 1
    onsetLag = 1
endif
Formula: "if col > onsetLag then max(0, object[combinedEnvSrc, col] - object[combinedEnvSrc, col - onsetLag]) else 0 endif"

selectObject: onsetFunc
onsetMax = Get maximum: 0, 0, "None"
if onsetMax < epsilon
    onsetMax = epsilon
endif

appendInfoLine: "  Peak onset energy: ", fixed$(onsetMax, 6)

# ============================================================
# STEP 4: Sigmoid mask (soft gating)
# ============================================================
appendInfoLine: ""
appendInfoLine: "[4/6] Sigmoid mask..."

# Compute slow floor from onset function (running baseline)
selectObject: onsetFunc
onsetFloor = Filter (pass Hann band): 0, 5, 10
Rename: "onset_floor"

# Sigmoid on dB ratio of onset vs floor
# mask = 1 / (1 + exp(-steepness * (dB_ratio - threshold)))
onsetFloorId = onsetFloor

selectObject: onsetFunc
mask = Copy: "mask"

steepStr$ = fixed$(sigmoid_steepness, 8)
threshStr$ = fixed$(threshold_dB, 8)
epsStr$ = fixed$(epsilon, 12)

Formula: "1 / (1 + exp(-" + steepStr$
    ... + " * ((20 * log10((self + " + epsStr$
    ... + ") / (object[" + string$(onsetFloorId)
    ... + "] + " + epsStr$ + "))) - " + threshStr$ + ")))"

removeObject: onsetFloor

appendInfoLine: "  Sigmoid: steepness=", fixed$(sigmoid_steepness, 1),
    ... " threshold=", fixed$(threshold_dB, 1), " dB"

# ============================================================
# STEP 5: Mask dilation (attack/release shaping)
# ============================================================
appendInfoLine: ""
appendInfoLine: "[5/6] Mask dilation..."

attackSec = attack_ms / 1000
releaseSec = release_ms / 1000

# v1.1: peak-preserving max-decay dilation instead of convolution.
# The old convolution was unnormalized (window summed to >>1, so
# the re-sigmoid saturated the mask almost everywhere -- and its
# value at self=0 floored the mask at ~0.27, a 27% sustain leak)
# and un-shifted (mask opened attack_ms LATE, clipping attacks).
#
# New scheme, per pass: y[n] = max(x[n], y[n-1] * coef).
# This deliberately exploits Praat's in-place Formula semantics
# (self[col-1] is the value just computed) -- the same property
# that was a bug in Step 3 is the correct tool here.
#   Forward pass  = release: mask decays exponentially after an
#                   onset region (time constant release_ms).
#   Reversed pass = attack LOOKAHEAD: mask pre-opens before each
#                   onset (time constant attack_ms), so the very
#                   first samples of the attack are kept.
# Mask stays in [0, 1]; peaks are preserved exactly; zero latency.
relCoef = exp(-1 / (releaseSec * workingSR))
attCoef = exp(-1 / (attackSec * workingSR))

selectObject: mask
Formula: "if col > 1 then max(self, self[col-1] * relCoef) else self endif"
Reverse
Formula: "if col > 1 then max(self, self[col-1] * attCoef) else self endif"
Reverse
Rename: "mask_final"

appendInfoLine: "  Attack lookahead: ", fixed$(attack_ms, 0),
    ... " ms | Release decay: ", fixed$(release_ms, 0), " ms (1/e)"

# Store visualization copies
if show_visualization
    selectObject: combinedEnv
    vizCombinedEnv = Copy: "viz_combined"
    
    selectObject: onsetFunc
    vizOnsetFunc = Copy: "viz_onset"
    
    selectObject: mask
    vizMask = Copy: "viz_mask"
endif

# Cleanup analysis objects
removeObject: combinedEnv, onsetFunc

# ============================================================
# STEP 6: Apply mask at original SR
# ============================================================
appendInfoLine: ""
appendInfoLine: "[6/6] Applying mask..."

# Upsample mask to original SR (mask stays smooth)
if workingSR < originalSR
    selectObject: mask
    maskFullSR = Resample: originalSR, 50
    removeObject: mask
    mask = maskFullSR
    Rename: "mask_fullsr"
endif

# Ensure mask duration matches original
selectObject: mask
maskDur = Get total duration
if maskDur < totalDur - 0.001
    # Pad with zeros
    padNeeded = totalDur - maskDur
    Create Sound from formula: "pad", 1, 0, padNeeded, originalSR, "0"
    padSnd = selected("Sound")
    selectObject: mask, padSnd
    Concatenate
    extMask = selected("Sound")
    removeObject: mask, padSnd
    mask = extMask
    Rename: "mask_fullsr"
elsif maskDur > totalDur + 0.001
    selectObject: mask
    # preserve times "no" already rebases the result to 0
    Extract part: 0, totalDur, "rectangular", 1, "no"
    trimMask = selected("Sound")
    removeObject: mask
    mask = trimMask
    Rename: "mask_fullsr"
endif

# Apply to each channel
maskId = mask
# v1.1: resampling can leave the mask a few samples short/long
# within the 1 ms tolerance above; guard the object[] read so an
# out-of-range column can never be touched.
selectObject: mask
maskNx = Get number of samples

if nChannels = 1
    # Mono: mask * original = transients
    selectObject: originalSound
    transId = Copy: originalName$ + "_transients"
    Formula: "if col <= maskNx then self * object[maskId, col] else 0 endif"
    
    # Sustain = original - transients (perfect reconstruction)
    transIdNum = transId
    selectObject: originalSound
    sustId = Copy: originalName$ + "_sustain"
    Formula: "self - object[transIdNum]"

else
    # v1.1: generalized to ANY channel count (was: stereo only,
    # so >2-channel input crashed with undefined transId).
    # The mono-derived mask is applied identically to every channel.
    selectObject: originalSound
    Extract all channels
    for c from 1 to nChannels
        chan_'c' = selected("Sound", c)
    endfor
    
    # Transient channels
    for c from 1 to nChannels
        selectObject: chan_'c'
        trans_'c' = Copy: "trans_ch" + string$(c)
        Formula: "if col <= maskNx then self * object[maskId, col] else 0 endif"
    endfor
    
    selectObject: trans_1
    for c from 2 to nChannels
        plusObject: trans_'c'
    endfor
    Combine to stereo
    transId = selected("Sound")
    Rename: originalName$ + "_transients"
    
    # Sustain channels (perfect reconstruction per channel)
    for c from 1 to nChannels
        srcTrans = trans_'c'
        selectObject: chan_'c'
        sust_'c' = Copy: "sust_ch" + string$(c)
        Formula: "self - object[srcTrans]"
    endfor
    
    selectObject: sust_1
    for c from 2 to nChannels
        plusObject: sust_'c'
    endfor
    Combine to stereo
    sustId = selected("Sound")
    Rename: originalName$ + "_sustain"
    
    for c from 1 to nChannels
        removeObject: chan_'c', trans_'c', sust_'c'
    endfor
endif

# RMS balance (v1.1: reported BEFORE gain so it reflects the
# detection itself; note RMS is not additive energy -- this is a
# relative balance indicator, not an energy-conservation figure)
selectObject: transId
transRMS = Get root-mean-square: 0, 0
selectObject: sustId
sustRMS = Get root-mean-square: 0, 0
totalRMS = transRMS + sustRMS + epsilon
transPct = transRMS / totalRMS * 100
sustPct = sustRMS / totalRMS * 100

appendInfoLine: ""
appendInfoLine: "RMS balance:"
appendInfoLine: "  Transient: ", fixed$(transPct, 1), "%"
appendInfoLine: "  Sustain:   ", fixed$(sustPct, 1), "%"

# Transient gain (applied after reporting)
if transient_gain_dB <> 0
    selectObject: transId
    gainLinear = 10 ^ (transient_gain_dB / 20)
    gainStr$ = fixed$(gainLinear, 8)
    Formula: "self * " + gainStr$
    appendInfoLine: "  Transient gain: ", fixed$(transient_gain_dB, 1), " dB"
endif

removeObject: mask, workSound, monoFull

# ============================================================
# STEP 7: Visualization
# ============================================================
if show_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    # Prepare mono views of outputs for drawing
    if nChannels > 1
        selectObject: transId
        vizTrans = Extract one channel: 1
        selectObject: sustId
        vizSust = Extract one channel: 1
        selectObject: originalSound
        vizOrig = Convert to mono
    else
        selectObject: transId
        vizTrans = Copy: "viz_trans"
        selectObject: sustId
        vizSust = Copy: "viz_sust"
        selectObject: originalSound
        vizOrig = Copy: "viz_orig"
    endif
    
    # Get amplitude bounds
    selectObject: vizOrig
    origAbsMax = Get maximum: 0, 0, "Sinc70"
    origAbsMin = Get minimum: 0, 0, "Sinc70"
    if origAbsMax < 0
        origAbsMax = -origAbsMax
    endif
    if origAbsMin < 0
        origAbsMin = -origAbsMin
    endif
    if origAbsMax >= origAbsMin
        ampMax = origAbsMax * 1.1
    else
        ampMax = origAbsMin * 1.1
    endif
    if ampMax < 0.001
        ampMax = 0.001
    endif
    
    # Get envelope bounds
    selectObject: vizCombinedEnv
    envMax = Get maximum: 0, 0, "None"
    if envMax < epsilon
        envMax = 0.001
    endif
    envMax = envMax * 1.2
    
    # Get onset bounds
    selectObject: vizOnsetFunc
    onsetVizMax = Get maximum: 0, 0, "None"
    if onsetVizMax < epsilon
        onsetVizMax = 0.001
    endif
    onsetVizMax = onsetVizMax * 1.15
    
    # Band colours
    bandCol1$ = "{0.2, 0.5, 0.8}"
    bandCol2$ = "{0.8, 0.4, 0.2}"
    bandCol3$ = "{0.3, 0.7, 0.4}"
    bandCol4$ = "{0.7, 0.3, 0.6}"
    bandCol5$ = "{0.5, 0.7, 0.2}"
    bandCol6$ = "{0.2, 0.6, 0.7}"
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half",
        ... "##Multi-Band Onset Detector v1.1##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half",
        ... originalName$ + " | " + presetName$
        ... + " | " + string$(number_of_bands) + " bands"
        ... + " | Thresh: " + fixed$(threshold_dB, 1) + " dB"
    
    # === ROW 1: Original waveform ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.8, 7.5, 0.65, 1.35
    
    Axes: 0, totalDur, -ampMax, ampMax
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, -ampMax, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, totalDur, 0
    
    selectObject: vizOrig
    Colour: "{0.4, 0.4, 0.4}"
    Line width: 1
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Original"
    
    # === ROW 2: Band envelopes + combined ===
    Select outer viewport: 0, 8, 1.5, 2.5
    Select inner viewport: 0.8, 7.5, 1.55, 2.45
    
    Axes: 0, totalDur, 0, envMax
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, 0, envMax
    
    # Draw individual band envelopes
    for bi from 1 to number_of_bands
        if bi = 1
            Colour: bandCol1$
        elsif bi = 2
            Colour: bandCol2$
        elsif bi = 3
            Colour: bandCol3$
        elsif bi = 4
            Colour: bandCol4$
        elsif bi = 5
            Colour: bandCol5$
        else
            Colour: bandCol6$
        endif
        Line width: 1
        selectObject: vizBandEnv_'bi'
        Draw: 0, 0, 0, envMax, "no", "Curve"
    endfor
    
    # Combined envelope on top
    selectObject: vizCombinedEnv
    Colour: "Black"
    Line width: 2
    Draw: 0, 0, 0, envMax, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Energy"
    Text top: "no", "Band Envelopes (coloured) + Combined (black)"
    
    # === ROW 3: Onset function ===
    Select outer viewport: 0, 8, 2.6, 3.5
    Select inner viewport: 0.8, 7.5, 2.65, 3.45
    
    Axes: 0, totalDur, 0, onsetVizMax
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, 0, onsetVizMax
    
    selectObject: vizOnsetFunc
    Colour: "{0.2, 0.6, 0.8}"
    Line width: 1
    Draw: 0, 0, 0, onsetVizMax, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dE/dt"
    Text top: "no", "Onset Function (positive energy derivative)"
    
    # === ROW 4: Sigmoid mask ===
    Select outer viewport: 0, 8, 3.6, 4.3
    Select inner viewport: 0.8, 7.5, 3.65, 4.25
    
    Axes: 0, totalDur, -0.05, 1.1
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, -0.05, 1.1
    
    # 0.5 reference
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0.5, totalDur, 0.5
    Solid line
    
    selectObject: vizMask
    Colour: "{0.6, 0.2, 0.8}"
    Line width: 2
    Draw: 0, 0, -0.05, 1.1, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mask"
    Text top: "no", "Transient Mask (sigmoid)"
    
    # === ROW 5: Transient waveform ===
    Select outer viewport: 0, 4, 4.4, 5.3
    Select inner viewport: 0.8, 3.7, 4.45, 5.25
    
    Axes: 0, totalDur, -ampMax, ampMax
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, -ampMax, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, totalDur, 0
    
    selectObject: vizTrans
    Colour: "{0.8, 0.2, 0.2}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Transients (" + fixed$(transPct, 1) + "%)"
    
    # === ROW 5: Sustain waveform ===
    Select outer viewport: 4, 8, 4.4, 5.3
    Select inner viewport: 4.4, 7.5, 4.45, 5.25
    
    Axes: 0, totalDur, -ampMax, ampMax
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, -ampMax, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, totalDur, 0
    
    selectObject: vizSust
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Sustain (" + fixed$(sustPct, 1) + "%)"
    Text bottom: "yes", "Time (s)"
    
    # === STATS PANEL ===
    Select outer viewport: 0, 8, 5.4, 6.15
    Select inner viewport: 0.6, 7.7, 5.45, 6.1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##Detection Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    
    Text: 0.02, "left", 0.62, "half",
        ... "Input: " + originalName$ + " | "
        ... + fixed$(totalDur, 2) + " s | "
        ... + string$(originalSR) + " Hz | "
        ... + string$(nChannels) + " ch"
        ... + " | Analysis SR: " + string$(workingSR) + " Hz"
    Text: 0.02, "left", 0.38, "half",
        ... "Bands: " + string$(number_of_bands)
        ... + " (" + fixed$(low_frequency_Hz, 0)
        ... + "-" + fixed$(high_frequency_Hz, 0) + " Hz)"
        ... + " | Threshold: " + fixed$(threshold_dB, 1) + " dB"
        ... + " | Steepness: " + fixed$(sigmoid_steepness, 1)
        ... + " | Smoothing: " + fixed$(envelope_smoothing_Hz, 0) + " Hz"
    Text: 0.02, "left", 0.14, "half",
        ... "Attack: " + fixed$(attack_ms, 0) + " ms"
        ... + " | Release: " + fixed$(release_ms, 0) + " ms"
        ... + " | Transient gain: " + fixed$(transient_gain_dB, 1) + " dB"
        ... + " | RMS: " + fixed$(transPct, 1)
        ... + "% trans / " + fixed$(sustPct, 1) + "% sust"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 6.2, 6.5
    Axes: 0, 1, 0, 1
    Font size: 6
    
    Colour: "{0.4, 0.4, 0.4}"
    Draw line: 0.02, 0.5, 0.06, 0.5
    Colour: "Black"
    Text: 0.07, "left", 0.5, "half", "Original"
    
    Colour: "{0.8, 0.2, 0.2}"
    Draw line: 0.16, 0.5, 0.20, 0.5
    Colour: "Black"
    Text: 0.21, "left", 0.5, "half", "Transients"
    
    Colour: "{0.2, 0.5, 0.8}"
    Draw line: 0.32, 0.5, 0.36, 0.5
    Colour: "Black"
    Text: 0.37, "left", 0.5, "half", "Sustain"
    
    Colour: "{0.6, 0.2, 0.8}"
    Line width: 2
    Draw line: 0.47, 0.5, 0.51, 0.5
    Line width: 1
    Colour: "Black"
    Text: 0.52, "left", 0.5, "half", "Mask"
    
    Colour: "{0.2, 0.6, 0.8}"
    Draw line: 0.59, 0.5, 0.63, 0.5
    Colour: "Black"
    Text: 0.64, "left", 0.5, "half", "Onset"
    
    # Band legend
    nLegendBands = number_of_bands
    if nLegendBands > 6
        nLegendBands = 6
    endif
    
    legendStart = 0.73
    legendStep = 0.045
    for bi from 1 to nLegendBands
        lx = legendStart + (bi - 1) * legendStep
        if bi = 1
            Colour: bandCol1$
        elsif bi = 2
            Colour: bandCol2$
        elsif bi = 3
            Colour: bandCol3$
        elsif bi = 4
            Colour: bandCol4$
        elsif bi = 5
            Colour: bandCol5$
        else
            Colour: bandCol6$
        endif
        Draw line: lx, 0.5, lx + 0.02, 0.5
    endfor
    Colour: "Black"
    lxEnd = legendStart + nLegendBands * legendStep
    Text: lxEnd, "left", 0.5, "half", "Bands"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup visualization objects
    removeObject: vizOrig, vizTrans, vizSust
    removeObject: vizCombinedEnv, vizOnsetFunc, vizMask
    for bi from 1 to number_of_bands
        removeObject: vizBandEnv_'bi'
    endfor

endif

# ============================================================
# FINAL
# ============================================================
selectObject: originalSound
plusObject: transId
plusObject: sustId

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", originalName$, "_transients"
appendInfoLine: "Created: ", originalName$, "_sustain"
appendInfoLine: ""
appendInfoLine: "Compositional applications:"
appendInfoLine: "  - Gesture vs. texture separation (spectromorphology)"
appendInfoLine: "  - Isolate attacks for rhythmic recomposition"
appendInfoLine: "  - Cross-synthesis: transients from A + sustain from B"
appendInfoLine: "  - Onset-driven effects gating"
