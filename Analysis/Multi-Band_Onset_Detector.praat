# ============================================================
# Praat AudioTools - Multi-Band Onset Detector.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
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
#     1. Logarithmic filterbank splits each channel into N bands
#     2. Per-band rectification + smoothing -> phase-safe RMS-across-channel envelopes
#     3. Positive 5-ms envelope change is computed PER BAND and summed
#        (multi-band positive flux; band rises cannot be cancelled by band falls)
#     4. Sigmoid mask from flux / adaptive local baseline
#     5. Mask dilation via max-decay recursion (attack lookahead
#        + release decay, peak-preserving, no output time shift)
#     6. Mask upsampled to original SR and applied identically to every channel
#     7. Sustain = original - transient (exact complementary split before
#        optional transient output gain)
#
# Changelog v1.2:
#   - TRUE MULTI-BAND NOVELTY: onset activity is now the SUM OF POSITIVE
#     PER-BAND envelope changes. v1.1 differentiated the SUMMED envelope,
#     so a rise in one band could be cancelled by a simultaneous fall in
#     another band. The detector now matches its multi-band claim.
#   - PHASE-SAFE MULTICHANNEL ANALYSIS: removed Convert to mono. Each band
#     is analyzed per channel and pooled as RMS across channel envelopes,
#     so antiphase stereo/multichannel transients cannot disappear.
#   - Visualization uses the strongest-RMS input channel as the waveform
#     representative instead of a potentially phase-cancelling fold-down.
#   - Presets now set an analysis sample rate high enough for their stated
#     frequency range. Full Mix can actually analyze to 16 kHz; Drums to
#     12 kHz when the source sample rate permits.
#   - Soft Transients preset corrected: its threshold is LOWER, not higher,
#     because a higher dB threshold makes the detector less sensitive.
#   - Custom Number_of_bands is constrained to 1..12 and envelope smoothing
#     is clamped to a valid range for the actual analysis sample rate.
#   - Clarified that the detector uses smoothed rectified-amplitude
#     envelopes (not additive physical energy), and that transient gain
#     intentionally breaks exact output-pair reconstruction after the split.
#   - Visualization title/subtitle separated; onset panel now describes the
#     measured per-band positive flux and mask panel includes attack/release.
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
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
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
form Multi-Band Onset Detector v1.2
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
    working_sample_rate_Hz = 32000
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
    working_sample_rate_Hz = 20000
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
    working_sample_rate_Hz = 16000
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
    working_sample_rate_Hz = 44100
elsif preset = 6
    # Soft Transients: increased sensitivity to gradual/weak envelope rises
    presetName$ = "Soft Transients"
    threshold_dB = 2.5
    sigmoid_steepness = 1.4
    attack_ms = 30
    release_ms = 100
    low_frequency_Hz = 100
    high_frequency_Hz = 8000
    number_of_bands = 4
    envelope_smoothing_Hz = 40
    working_sample_rate_Hz = 20000
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
if workingSR < 1000
    exitScript: "Working sample rate is too low (minimum 1000 Hz)."
endif
workNyquist = workingSR / 2

# Keep the custom form robust and the visualization readable.
if number_of_bands < 1
    number_of_bands = 1
elsif number_of_bands > 12
    number_of_bands = 12
endif

# The envelope smoother is a low-pass on rectified band amplitude.
# Keep it comfortably below the analysis Nyquist.
maxSmoothHz = workNyquist * 0.4
if envelope_smoothing_Hz > maxSmoothHz
    envelope_smoothing_Hz = maxSmoothHz
endif

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

writeInfoLine: "=== Multi-Band Onset Detector v1.2 ==="
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
# STEP 1: Create phase-safe per-channel working sources
# ============================================================
appendInfoLine: "[1/6] Preprocessing..."

representativeChannel = 1

if nChannels = 1
    selectObject: originalSound
    if workingSR < originalSR
        workCh_1 = Resample: workingSR, 50
        appendInfoLine: "  Downsampled to ", workingSR, " Hz for analysis"
    else
        workCh_1 = Copy: "work_ch1"
        workingSR = originalSR
    endif
else
    # Keep channels separate. A conventional mono fold-down can cancel
    # antiphase transients completely.
    selectObject: originalSound
    Extract all channels
    for c from 1 to nChannels
        fullCh_'c' = selected("Sound", c)
    endfor

    strongestRMS = -1
    for c from 1 to nChannels
        selectObject: fullCh_'c'
        thisRMS = Get root-mean-square: 0, 0
        if thisRMS > strongestRMS
            strongestRMS = thisRMS
            representativeChannel = c
        endif

        if workingSR < originalSR
            workCh_'c' = Resample: workingSR, 50
        else
            workCh_'c' = Copy: "work_ch" + string$(c)
        endif
    endfor

    for c from 1 to nChannels
        removeObject: fullCh_'c'
    endfor

    if workingSR < originalSR
        appendInfoLine: "  Downsampled ", nChannels, " channels to ", workingSR, " Hz for analysis"
    endif
    appendInfoLine: "  Phase-safe channel pooling: RMS of per-channel band envelopes"
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

# Combined envelope is retained for visualization/context only.
selectObject: workCh_1
combinedEnv = Copy: "combined_env"
Formula: "0"

# Multi-band onset function is accumulated directly from POSITIVE
# per-band changes, so simultaneous energy redistribution across
# frequency bands cannot cancel a new onset.
selectObject: workCh_1
onsetFunc = Copy: "onset_func"
Formula: "0"

onsetLag = round(workingSR * 0.005)
if onsetLag < 1
    onsetLag = 1
endif

# Per-band processing
for bi from 1 to number_of_bands
    biM1 = bi - 1
    loEdge = bandEdge_'biM1'
    hiEdge = bandEdge_'bi'

    appendInfoLine: "  Band ", bi, ": ",
        ... fixed$(loEdge, 0), "-", fixed$(hiEdge, 0), " Hz"

    # Phase-safe band envelope: filter/rectify/smooth each channel
    # separately, then pool the channel envelopes by RMS.
    selectObject: workCh_1
    bandEnv = Copy: "band_env_" + string$(bi)
    Formula: "0"

    for c from 1 to nChannels
        selectObject: workCh_'c'
        filtered = Filter (pass Hann band): loEdge, hiEdge, 100

        # Rectified amplitude, then low-pass smoothing.
        Formula: "abs(self)"
        chanEnv = Filter (pass Hann band): 0, envelope_smoothing_Hz, 20
        chanEnvId = chanEnv

        selectObject: bandEnv
        Formula: "self + object[chanEnvId]^2"

        removeObject: filtered, chanEnv
    endfor

    selectObject: bandEnv
    Formula: "sqrt(self / nChannels)"

    # Store the measured aggregate envelope for visualization.
    if show_visualization
        vizBandEnv_'bi' = Copy: "viz_band_" + string$(bi)
    endif

    bandEnvId = bandEnv
    selectObject: combinedEnv
    Formula: "self + object[bandEnvId]"

    # Positive 5-ms novelty PER BAND.
    bandSrc = bandEnv
    selectObject: onsetFunc
    Formula: "self + if col > onsetLag then max(0, object[bandSrc, col] - object[bandSrc, col - onsetLag]) else 0 endif"

    removeObject: bandEnv
endfor

# ============================================================
# STEP 3: Multi-band positive-flux onset function
# ============================================================
appendInfoLine: ""
appendInfoLine: "[3/6] Multi-band positive flux..."

selectObject: onsetFunc
onsetMax = Get maximum: 0, 0, "None"
if onsetMax < epsilon
    onsetMax = epsilon
endif

appendInfoLine: "  Peak multi-band flux: ", fixed$(onsetMax, 6)

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
# Mask stays in [0, 1]; peaks are preserved exactly. The attack pass is
# offline/noncausal lookahead, but it does not shift the output timeline.
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
    # The phase-safe aggregate mask is applied identically to every channel.
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
    appendInfoLine: "  Note: exact transient+sustain reconstruction applies before this output gain."
endif

removeObject: mask
for c from 1 to nChannels
    removeObject: workCh_'c'
endfor

# ============================================================
# STEP 7: Visualization
# ============================================================
if show_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    # Prepare phase-safe representative views for drawing.
    # For multichannel material use the strongest-RMS input channel
    # determined during preprocessing; do not fold channels to mono.
    if nChannels > 1
        selectObject: transId
        vizTrans = Extract one channel: representativeChannel
        selectObject: sustId
        vizSust = Extract one channel: representativeChannel
        selectObject: originalSound
        vizOrig = Extract one channel: representativeChannel
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
    Select outer viewport: 0, 8, 0, 0.28
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half",
        ... "##Multi-Band Onset Detector v1.2##"

    # Separate subtitle strip: never draw outside the title viewport.
    Select outer viewport: 0, 8, 0.28, 0.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half",
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
    Text top: "no", if nChannels > 1 then "Original representative ch " + string$(representativeChannel) else "Original" fi
    
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
    Text left: "yes", "Env"
    Text top: "no", "Band envelopes (coloured) + summed context (black)"
    
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
    Text left: "yes", "Flux"
    Text top: "no", "Onset function: summed positive per-band envelope flux"
    
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
    Text top: "no", "Transient mask after sigmoid + attack/release shaping"
    
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
        ... + if nChannels > 1 then " | phase-safe RMS channel pooling" else "" fi
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
