# ============================================================
# Praat AudioTools - Kick_Detector_and_Bass_Adder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Detects kick-like low-frequency onsets in a drum loop using
#   multi-band z-scored intensity features (low-band energy,
#   broadband level rise, low-mid penalty) plus a low-band onset
#   gate, then places a channel-matched bass sample at each trigger.
#   The detector is an acoustic heuristic, not a semantic drum classifier.
#
# Usage:
#   Select TWO Sound objects: 1) Drum loop, 2) Bass sample
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.6:
#   - FIX: refractory timing is measured between DETECTED onsets, not
#     between an unshifted analysis time and the previous shifted bass
#     trigger. In v0.5 a +52 ms trigger offset silently lengthened the
#     90 ms refractory to about 142 ms.
#   - DETECTION: corrected the Intensity time-resolution mapping. v0.5 used
#     0.8/window, producing an integration window about 4x broader than
#     intended and smearing kick attacks. v0.6 uses 3.2/window and applies
#     a half-window onset alignment. Candidates are local maxima of the
#     low-band onset derivative and must also pass the composite score.
#   - DEFAULT: Bass trigger offset is now 0 ms; the old +52 ms mainly
#     compensated for the over-smoothed detector. Offset remains available
#     as an explicit creative/alignment control.
#   - TRUTHFUL TERMINOLOGY: the broadband feature is a first difference
#     of broadband INTENSITY, not spectral flux.
#   - TEXTGRID: two point tiers: Kicks (measured onset times) and
#     BassTriggers (onset + user offset).
#   - FIX: kick/trigger vectors are allocated from the actual frame count
#     instead of a fixed 1000-event ceiling.
#   - MULTICHANNEL: bass is explicitly channel-matched before mixing.
#     Mono bass is duplicated; equal channel counts are preserved; a
#     multichannel bass feeding mono uses its strongest-RMS channel; extra
#     destination channels receive the strongest bass channel.
#   - SPEED: bass events are accumulated into one zero bass layer with
#     Formula (part), so each event touches only its own duration. The
#     final drum+bass mix is performed once instead of scanning the whole
#     drum file once per kick.
#   - SAFETY: optional legacy final normalization, conservative bass-only
#     reduction, or unrestricted output. Requested and applied bass gain
#     are both reported.
#   - OPTIONAL bass edge fade to prevent abrupt sample-edge clicks;
#     default 0 ms preserves the supplied sample exactly.
#   - VIZ: compact 2x2 mechanism-first layout: composite score, low-band
#     onset gate, actual added bass layer, and dry/result comparison.
#     Representative waveform channel is selected by RMS; no mono
#     fold-down is used for the display.
# Changelog v0.5:
#   - CRITICAL FIX: `endif` -> `fi` inside the bass-injection
#     Formula. v0.4 used the script-level `endif` keyword inside
#     a Formula's inline ternary. Praat's Formula parser is a
#     separate parser from the script parser and documents `fi`
#     as the closing keyword for inline `if/then/else/fi`. If
#     Praat strictly enforces this, v0.4's bass mixing silently
#     failed (kicks detected and TextGrid produced, but no bass
#     in output). v0.5 uses the documented `fi`.
#   - Modernized `Object_<id>(x)` -> `object(<id>, x)` in the
#     bass-injection Formula.
#   - Audio output: bit-identical to v0.4 IF Praat already
#     accepts `endif` inside Formula context (script was running
#     correctly); CORRECTED if Praat rejects it (v0.5 finally
#     adds the bass).
#   - Dropped 5 decorative `comment === ... ===` form section
#     dividers. Form went from 14 effective rows to 10.
#   - NEW: Draw_visualization boolean form toggle (default 1).
#     v0.4 had no visualization at all.
#   - NEW: Suite-standard 8x8 visualization:
#       Title bar + metadata subtitle (drum/bass names, kick
#         count, score/derivative thresholds, offset)
#       Panel A (left, headline): drum waveform with kick
#         markers — vertical orange stems + numbered labels
#         at each detected kick time. The detection diagnostic.
#       Panel B (right, headline): score curve over time with
#         red dashed score_threshold line and green dashed
#         derivative_threshold reference
#       Panel C: zoom on first 4 s (gray = drum, blue = result,
#         orange dotted = kick positions) — shows where bass
#         got injected
#       Panel D: full result waveform with kick injection
#         markers (orange dotted vertical lines)
#       Panel E: light-grey summary stats bar (suite standard)
# Changelog v0.4:
#   - Fixed bass mixing
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sounds: 1) Drum loop, 2) Bass sample"
endif

drumID = selected("Sound", 1)
bassID = selected("Sound", 2)
drum$ = selected$("Sound", 1)
bass$ = selected$("Sound", 2)

form Kick Detector and Bass Adder v0.6
    comment === Detection ===
    real Score_threshold_z 0.80
    real Derivative_threshold_z 0.60
    real Refractory_ms 90
    real Bass_trigger_offset_ms 0
    real Weight_low 1.0
    real Weight_broadband_onset 0.5
    real Weight_lowmid_penalty 0.5
    comment === Bass Layer ===
    real Bass_gain 1.0
    real Bass_edge_fade_ms 0.0
    optionmenu Peak_safety: 1
        option Normalize final mix (legacy)
        option Reduce bass layer only
        option Allow over 0.99
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# User-facing units -> internal seconds / legacy variable names
score_threshold = score_threshold_z
derivative_threshold = derivative_threshold_z
refractory_period = max(0, refractory_ms / 1000)
time_offset = bass_trigger_offset_ms / 1000
weight_flux = weight_broadband_onset
bass_edge_fade = max(0, bass_edge_fade_ms / 1000)

# === Band Parameters ===
lowBandMin = 25
lowBandMax = 120
lowMidMin = 120
lowMidMax = 250
smoothHz = 100
hop_default = 0.01

# === Setup ===
selectObject: drumID
xmin = Get start time
xmax = Get end time
dur = xmax - xmin
drumRate = Get sampling frequency
drumChannels = Get number of channels

if dur <= 0.008
    exitScript: "Drum loop is too short (" + fixed$(dur, 3) + " s) for analysis."
endif

selectObject: bassID
bassDur = Get total duration
bassXmin = Get start time
bassXmax = Get end time
bassChannels = Get number of channels
bassRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Kick Detector and Bass Adder v0.6 ==="
appendInfoLine: "Drum loop:   ", drum$, " (", fixed$(dur, 2), " s, ", drumChannels, " ch)"
appendInfoLine: "Bass sample: ", bass$, " (", fixed$(bassDur, 3), " s, ", bassChannels, " ch)"
appendInfoLine: ""

# === Create Working Copy ===
selectObject: drumID
workID = Extract part: xmin, xmax, "rectangular", 1, "yes"
Rename: "KD_work"

# === Adaptive Window and Hop ===
safeWindow = min(0.5 * dur, 0.04)
safeWindow = max(safeWindow, 0.005)
# Praat Intensity uses an averaging window tied to the minimum pitch.
# 3.2/safeWindow makes the effective integration scale track the intended
# transient window; v0.5 used 0.8/safeWindow and smeared attacks heavily.
minPitchForIntensity = 3.2 / safeWindow
onsetAlignment = safeWindow / 2
hop = min(hop_default, safeWindow / 2)

# === Bandpass Filtering ===
appendInfoLine: "Filtering bands..."

selectObject: workID
lowID = Filter (pass Hann band): lowBandMin, lowBandMax, smoothHz
Rename: "KD_low"

selectObject: workID
lowmidID = Filter (pass Hann band): lowMidMin, lowMidMax, smoothHz
Rename: "KD_lowmid"

# === Intensity Analysis ===
appendInfoLine: "Computing intensity..."

selectObject: workID
intBroadID = To Intensity: minPitchForIntensity, hop, "yes"
Rename: "KD_I_broad"

selectObject: lowID
intLowID = To Intensity: minPitchForIntensity, hop, "yes"
Rename: "KD_I_low"

selectObject: lowmidID
intLowmidID = To Intensity: minPitchForIntensity, hop, "yes"
Rename: "KD_I_lowmid"

# === Read Intensities into Vectors ===
selectObject: intLowID
n = Get number of frames

if n < 3
    removeObject: workID, lowID, lowmidID, intBroadID, intLowID, intLowmidID
    exitScript: "Too few frames (" + string$(n) + ") for detection."
endif

appendInfoLine: "Analyzing ", n, " frames..."

time# = zero#(n)
low# = zero#(n)
lowmid# = zero#(n)
broad# = zero#(n)

for i from 1 to n
    selectObject: intLowID
    time#[i] = Get time from frame: i
    lv = Get value in frame: i
    if lv = undefined
        lv = 0
    endif
    low#[i] = lv

    selectObject: intLowmidID
    lmv = Get value in frame: i
    if lmv = undefined
        lmv = 0
    endif
    lowmid#[i] = lmv

    selectObject: intBroadID
    bv = Get value in frame: i
    if bv = undefined
        bv = 0
    endif
    broad#[i] = bv
endfor

# === First Differences ===
dlow# = zero#(n)
dbroad# = zero#(n)

for i from 2 to n
    dlow#[i] = low#[i] - low#[i-1]
    dbroad#[i] = broad#[i] - broad#[i-1]
endfor

# === Z-Score Normalization ===
appendInfoLine: "Standardizing detector features..."

muLow = 0
muLowMid = 0
muDLow = 0
muDBroad = 0
for i from 1 to n
    muLow = muLow + low#[i]
    muLowMid = muLowMid + lowmid#[i]
    muDLow = muDLow + dlow#[i]
    muDBroad = muDBroad + dbroad#[i]
endfor
muLow = muLow / n
muLowMid = muLowMid / n
muDLow = muDLow / n
muDBroad = muDBroad / n

varLow = 0
varLowMid = 0
varDLow = 0
varDBroad = 0
for i from 1 to n
    d = low#[i] - muLow
    varLow = varLow + d * d
    d = lowmid#[i] - muLowMid
    varLowMid = varLowMid + d * d
    d = dlow#[i] - muDLow
    varDLow = varDLow + d * d
    d = dbroad#[i] - muDBroad
    varDBroad = varDBroad + d * d
endfor
varLow = varLow / n
varLowMid = varLowMid / n
varDLow = varDLow / n
varDBroad = varDBroad / n

if varLow <= 1e-12
    varLow = 1e-12
endif
if varLowMid <= 1e-12
    varLowMid = 1e-12
endif
if varDLow <= 1e-12
    varDLow = 1e-12
endif
if varDBroad <= 1e-12
    varDBroad = 1e-12
endif

sdLow = sqrt(varLow)
sdLowMid = sqrt(varLowMid)
sdDLow = sqrt(varDLow)
sdDBroad = sqrt(varDBroad)

zLow# = zero#(n)
zLowMid# = zero#(n)
zDLow# = zero#(n)
zDBroadPos# = zero#(n)
score# = zero#(n)

for i from 1 to n
    zLow#[i] = (low#[i] - muLow) / sdLow
    zLowMid#[i] = (lowmid#[i] - muLowMid) / sdLowMid
    zDLow#[i] = (dlow#[i] - muDLow) / sdDLow
    zDBroad = (dbroad#[i] - muDBroad) / sdDBroad
    if zDBroad > 0
        zDBroadPos#[i] = zDBroad
    else
        zDBroadPos#[i] = 0
    endif
endfor

# === Scoring ===
appendInfoLine: "Scoring frames..."

for i from 1 to n
    score#[i] = weight_low * zLow#[i] + weight_flux * zDBroadPos#[i] - weight_lowmid_penalty * zLowMid#[i]
endfor

# === Peak Detection ===
appendInfoLine: "Detecting kick-like low-frequency onsets..."

# Two point tiers keep acoustic detection separate from bass placement.
tgID = Create TextGrid: xmin, xmax, "Kicks BassTriggers", "Kicks BassTriggers"
Rename: "KD_Kicks"

lastDetectTime = xmin - refractory_period
numKicks = 0
numTriggers = 0
skippedTriggers = 0

# At most one event can originate per analysis frame.
rawKickTimes# = zero#(n)
kickTimes# = zero#(n)
triggerTimes# = zero#(n)
kickFrame# = zero#(n)

for i from 2 to n - 1
    # A kick candidate is a local maximum of the low-band onset derivative.
    isDerivativePeak = 0
    if zDLow#[i] >= zDLow#[i-1] and zDLow#[i] > zDLow#[i+1]
        isDerivativePeak = 1
    endif

    # The composite score may peak one frame away from the derivative.
    localScore = score#[i]
    if score#[i-1] > localScore
        localScore = score#[i-1]
    endif
    if score#[i+1] > localScore
        localScore = score#[i+1]
    endif

    rawDetectTime = time#[i]
    detectTime = rawDetectTime + onsetAlignment
    if isDerivativePeak and localScore > score_threshold and zDLow#[i] > derivative_threshold and detectTime - lastDetectTime >= refractory_period
        if detectTime >= xmin and detectTime <= xmax
            numKicks = numKicks + 1
            rawKickTimes#[numKicks] = rawDetectTime
            kickTimes#[numKicks] = detectTime
            kickFrame#[numKicks] = i
            selectObject: tgID
            Insert point: 1, detectTime, "kick"
            lastDetectTime = detectTime

            triggerTime = detectTime + time_offset
            if triggerTime >= xmin and triggerTime <= xmax
                numTriggers = numTriggers + 1
                triggerTimes#[numTriggers] = triggerTime
                selectObject: tgID
                Insert point: 2, triggerTime, "bass"
            else
                skippedTriggers = skippedTriggers + 1
            endif
        endif
    endif
endfor

appendInfoLine: "Detected ", numKicks, " kick-like onsets; ", numTriggers, " bass triggers"
if skippedTriggers > 0
    appendInfoLine: "Skipped ", skippedTriggers, " trigger(s) shifted outside the drum time domain"
endif

# === Mix Bass Sample at Trigger Positions ===
wasNormalized = 0
finalMixScale = 1
bassLayerReduced = 0
appliedBassGain = bass_gain
bassReady = 0

# Always create an exact-grid zero bass layer. This keeps the dry signal
# untouched until the single final mix operation.
selectObject: drumID
bassLayer = Copy: "KD_bass_layer"
Formula: "0"

if numTriggers > 0
    appendInfoLine: "Preparing channel-matched bass layer..."

    # Resample first so Formula (part) can address the bass on the drum grid.
    if bassRate <> drumRate
        selectObject: bassID
        bassResamp = Resample: drumRate, 50
    else
        selectObject: bassID
        bassResamp = Copy: "KD_bass_resampled"
    endif

    selectObject: bassResamp
    bassChNow = Get number of channels
    bassStart = Get start time
    bassEnd = Get end time
    bassDurNow = bassEnd - bassStart
    bassSamples = Get number of samples

    # Strongest bass channel is used only when a channel mismatch requires
    # one representative source channel.
    strongestBassCh = 1
    strongestBassRms = -1
    if bassChNow > 1
        for ch from 1 to bassChNow
            selectObject: bassResamp
            Extract one channel: ch
            tmpBassCh = selected("Sound")
            tmpRms = Get root-mean-square: 0, 0
            if tmpRms > strongestBassRms
                strongestBassRms = tmpRms
                strongestBassCh = ch
            endif
            removeObject: tmpBassCh
        endfor
    endif

    # Explicit channel matching avoids the undefined/implicit behaviour of
    # addressing a stereo bass from a 3+ channel destination Formula.
    if bassChNow = drumChannels
        selectObject: bassResamp
        bassReady = Copy: "KD_bass_ready"
    else
        bassIDstr$ = string$(bassResamp)
        strongestStr$ = string$(strongestBassCh)
        selectObject: bassResamp
        if drumChannels = 1
            Create Sound from formula: "KD_bass_ready", 1, bassStart, bassEnd, drumRate,
                ... "object[" + bassIDstr$ + ", " + strongestStr$ + ", col]"
            bassReady = selected("Sound")
        elsif bassChNow = 1
            Create Sound from formula: "KD_bass_ready", drumChannels, bassStart, bassEnd, drumRate,
                ... "object[" + bassIDstr$ + ", 1, col]"
            bassReady = selected("Sound")
        else
            bassChNowStr$ = string$(bassChNow)
            Create Sound from formula: "KD_bass_ready", drumChannels, bassStart, bassEnd, drumRate,
                ... "if row <= " + bassChNowStr$ + " then object[" + bassIDstr$ + ", row, col] else object[" + bassIDstr$ + ", " + strongestStr$ + ", col] fi"
            bassReady = selected("Sound")
        endif
    endif

    removeObject: bassResamp

    # Optional sample-edge fade. Default 0 ms preserves the original bass.
    if bass_edge_fade > 0
        fadeSamples = round(bass_edge_fade * drumRate)
        maxFadeSamples = floor((bassSamples - 1) / 2)
        if fadeSamples > maxFadeSamples
            fadeSamples = maxFadeSamples
        endif
        if fadeSamples > 0
            fadeN$ = string$(fadeSamples)
            bassN$ = string$(bassSamples)
            selectObject: bassReady
            Formula: "self * min(1, (col - 1) / " + fadeN$ + ", (" + bassN$ + " - col) / " + fadeN$ + ")"
        endif
    endif

    # Requested gain is applied to the bass layer only.
    if bass_gain <> 1
        selectObject: bassReady
        gain$ = string$(bass_gain)
        Formula: "self * " + gain$
    endif

    # Accumulate each bass event only over the affected time region.
    selectObject: bassReady
    bassStart = Get start time
    bassEnd = Get end time
    bassDurNow = bassEnd - bassStart
    bassId$ = string$(bassReady)
    bassStart$ = string$(bassStart)

    for k from 1 to numTriggers
        triggerTime = triggerTimes#[k]
        triggerEnd = min(xmax, triggerTime + bassDurNow)
        if triggerEnd > triggerTime
            triggerT$ = string$(triggerTime)
            selectObject: bassLayer
            Formula (part): triggerTime, triggerEnd, 1, drumChannels,
                ... "self + object(" + bassId$ + ", x - " + triggerT$ + " + " + bassStart$ + ")"
            appendInfoLine: "  Bass trigger ", k, " at ", fixed$(triggerTime, 3), " s"
        endif
    endfor

    removeObject: bassReady

    # Optional conservative safety mode: preserve drum samples exactly and
    # reduce only the complete bass layer using the triangle-inequality bound.
    if peak_safety = 2
        selectObject: drumID
        dryPeak = Get absolute extremum: 0, 0, "None"
        selectObject: bassLayer
        layerPeak = Get absolute extremum: 0, 0, "None"
        layerScale = 1
        if dryPeak + layerPeak > 0.99 and layerPeak > 0
            if dryPeak < 0.99
                layerScale = (0.99 - dryPeak) / layerPeak
                layerScale = max(0, min(1, layerScale))
            else
                layerScale = 0
            endif
            if layerScale < 1
                selectObject: bassLayer
                Formula: "self * " + string$(layerScale)
                appliedBassGain = bass_gain * layerScale
                bassLayerReduced = 1
                appendInfoLine: "Bass-only safety reduced gain to ", fixed$(appliedBassGain, 4), " (conservative bound)"
            endif
        endif
    endif
endif

# One final mix pass. With zero triggers the bass layer is identically zero,
# so the output is a sample-exact copy of the drum loop.
selectObject: drumID
resultID = Copy: drum$ + "_with_bass"
layerID$ = string$(bassLayer)
Formula: "self + object(" + layerID$ + ", x)"

# Legacy-compatible safety option normalizes the complete mix only if needed.
if peak_safety = 1
    selectObject: resultID
    mixPeak = Get absolute extremum: 0, 0, "None"
    if mixPeak > 0.99
        finalMixScale = 0.99 / mixPeak
        appendInfoLine: "Normalizing final mix (peak was ", fixed$(mixPeak, 3), ", scale ", fixed$(finalMixScale, 4), ")"
        Scale peak: 0.99
        wasNormalized = 1
    endif
elsif peak_safety = 3
    appendInfoLine: "Peak safety: unrestricted output"
endif

# Capture stats for visualization
selectObject: resultID
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# Score range for Panel B y-axis
scoreMin = score#[1]
scoreMax = score#[1]
for i from 1 to n
    if score#[i] < scoreMin
        scoreMin = score#[i]
    endif
    if score#[i] > scoreMax
        scoreMax = score#[i]
    endif
endfor
# Buffer the y-axis for readability
scoreYMin = scoreMin - 0.5
scoreYMax = scoreMax + 0.5

# Kicks per second (density)
if dur > 0
    kicksPerSec = numKicks / dur
else
    kicksPerSec = 0
endif

# ============================================================
# VISUALIZATION  (AudioTools 2 x 2, width 8)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    Erase all

    # Representative waveform channel: strongest RMS channel, never mono fold-down.
    vizChannel = 1
    if drumChannels > 1
        bestVizRms = -1
        for ch from 1 to drumChannels
            selectObject: drumID
            Extract one channel: ch
            tmpViz = selected("Sound")
            tmpVizRms = Get root-mean-square: 0, 0
            if tmpVizRms > bestVizRms
                bestVizRms = tmpVizRms
                vizChannel = ch
            endif
            removeObject: tmpViz
        endfor
    endif

    selectObject: drumID
    if drumChannels > 1
        Extract one channel: vizChannel
        vizDrum = selected("Sound")
    else
        vizDrum = Copy: "KD_viz_drum"
    endif

    selectObject: resultID
    if drumChannels > 1
        Extract one channel: vizChannel
        vizResult = selected("Sound")
    else
        vizResult = Copy: "KD_viz_result"
    endif

    selectObject: bassLayer
    if drumChannels > 1
        Extract one channel: vizChannel
        vizBass = selected("Sound")
    else
        vizBass = Copy: "KD_viz_bass"
    endif

    selectObject: vizDrum
    dPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    rPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(dPeak, rPeak)
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.10

    # Score and derivative ranges.
    scoreMin = score#[1]
    scoreMax = score#[1]
    dMin = zDLow#[1]
    dMax = zDLow#[1]
    for i from 2 to n
        scoreMin = min(scoreMin, score#[i])
        scoreMax = max(scoreMax, score#[i])
        dMin = min(dMin, zDLow#[i])
        dMax = max(dMax, zDLow#[i])
    endfor
    scoreYMin = min(scoreMin - 0.3, score_threshold - 0.5)
    scoreYMax = max(scoreMax + 0.3, score_threshold + 0.5)
    dYMin = min(dMin - 0.3, derivative_threshold - 0.5)
    dYMax = max(dMax + 0.3, derivative_threshold + 0.5)

    # --- Title strip ---
    Select outer viewport: 0.4, 7.8, 0.04, 0.25
    Select inner viewport: 0.4, 7.8, 0.04, 0.25
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Kick Detector + Bass Adder v0.6"

    # --- Process strip ---
    Select outer viewport: 0.4, 7.8, 0.28, 0.46
    Select inner viewport: 0.4, 7.8, 0.28, 0.46
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30, 0.30, 0.34}"
    Text: 0.5, "centre", 0.5, "half", "25-120 Hz energy + broadband level rise - 120-250 Hz penalty -> low-band onset peak -> trigger + offset -> channel-matched bass layer"

    # --- Panel A title ---
    Select outer viewport: 0.3, 3.95, 0.58, 0.78
    Select inner viewport: 0.3, 3.95, 0.58, 0.78
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "A  COMPOSITE DETECTION SCORE"

    # --- Panel A data ---
    Select outer viewport: 0.3, 3.95, 0.80, 2.55
    Select inner viewport: 0.62, 3.82, 0.90, 2.43
    Axes: xmin, xmax, scoreYMin, scoreYMax
    Paint rectangle: "{0.98, 0.98, 0.98}", xmin, xmax, scoreYMin, scoreYMax
    Colour: "{0.52, 0.32, 0.68}"
    Line width: 1.5
    for i from 2 to n
        Draw line: time#[i-1], score#[i-1], time#[i], score#[i]
    endfor
    Colour: "{0.82, 0.25, 0.25}"
    Dashed line
    Draw line: xmin, score_threshold, xmax, score_threshold
    Solid line
    Colour: "{0.95, 0.55, 0.20}"
    Line width: 1
    for k from 1 to numKicks
        Draw line: rawKickTimes#[k], scoreYMin, rawKickTimes#[k], scoreYMax
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "z score"

    # --- Panel B title ---
    Select outer viewport: 4.05, 7.75, 0.58, 0.78
    Select inner viewport: 4.05, 7.75, 0.58, 0.78
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "B  LOW-BAND ONSET GATE"

    # --- Panel B data ---
    Select outer viewport: 4.05, 7.75, 0.80, 2.55
    Select inner viewport: 4.40, 7.62, 0.90, 2.43
    Axes: xmin, xmax, dYMin, dYMax
    Paint rectangle: "{0.98, 0.98, 0.98}", xmin, xmax, dYMin, dYMax
    Colour: "{0.20, 0.55, 0.72}"
    Line width: 1.5
    for i from 2 to n
        Draw line: time#[i-1], zDLow#[i-1], time#[i], zDLow#[i]
    endfor
    Colour: "{0.82, 0.25, 0.25}"
    Dashed line
    Draw line: xmin, derivative_threshold, xmax, derivative_threshold
    Solid line
    Colour: "{0.95, 0.55, 0.20}"
    for k from 1 to numKicks
        Draw line: rawKickTimes#[k], dYMin, rawKickTimes#[k], dYMax
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "d low (z)"

    # --- Panel C title ---
    Select outer viewport: 0.3, 3.95, 2.72, 2.92
    Select inner viewport: 0.3, 3.95, 2.72, 2.92
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "C  ACTUAL ADDED BASS LAYER"

    # --- Panel C data ---
    Select outer viewport: 0.3, 3.95, 2.94, 4.72
    Select inner viewport: 0.62, 3.82, 3.04, 4.58
    selectObject: vizBass
    bPeak = Get absolute extremum: 0, 0, "None"
    if bPeak < 0.001
        bPeak = 0.001
    endif
    bAmp = bPeak * 1.10
    Axes: xmin, xmax, -bAmp, bAmp
    Paint rectangle: "{0.98, 0.98, 0.98}", xmin, xmax, -bAmp, bAmp
    Colour: "{0.92, 0.63, 0.22}"
    Line width: 1
    selectObject: vizBass
    Draw: xmin, xmax, -bAmp, bAmp, "no", "Curve"
    Colour: "{0.60, 0.35, 0.15}"
    Dotted line
    for k from 1 to numTriggers
        Draw line: triggerTimes#[k], -bAmp, triggerTimes#[k], bAmp
    endfor
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # --- Panel D title ---
    Select outer viewport: 4.05, 7.75, 2.72, 2.92
    Select inner viewport: 4.05, 7.75, 2.72, 2.92
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "D  DRUM / RESULT - SAME SCALE"

    # --- Panel D data ---
    Select outer viewport: 4.05, 7.75, 2.94, 4.72
    Select inner viewport: 4.40, 7.62, 3.04, 4.58
    Axes: xmin, xmax, -sharedAmp, sharedAmp
    Paint rectangle: "{0.98, 0.98, 0.98}", xmin, xmax, -sharedAmp, sharedAmp
    selectObject: vizDrum
    Colour: "{0.58, 0.58, 0.58}"
    Line width: 1
    Draw: xmin, xmax, -sharedAmp, sharedAmp, "no", "Curve"
    selectObject: vizResult
    Colour: "{0.20, 0.48, 0.80}"
    Draw: xmin, xmax, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # --- Summary bar ---
    if peak_safety = 1
        safety$ = "normalize final"
    elsif peak_safety = 2
        safety$ = "reduce bass only"
    else
        safety$ = "unrestricted"
    endif
    Select outer viewport: 0.4, 7.7, 4.92, 5.24
    Select inner viewport: 0.4, 7.7, 4.92, 5.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7.5
    Colour: "{0.25, 0.25, 0.28}"
    Text: 0.5, "centre", 0.66, "half", "kicks " + string$(numKicks) + " | triggers " + string$(numTriggers) + " | onset align +" + fixed$(onsetAlignment * 1000, 1) + " ms | trigger offset " + fixed$(time_offset * 1000, 1) + " ms | analysis ch " + string$(vizChannel)
    Text: 0.5, "centre", 0.26, "half", "bass gain requested " + fixed$(bass_gain, 3) + " / layer " + fixed$(appliedBassGain, 3) + " | mix scale " + fixed$(finalMixScale, 3) + " | safety " + safety$ + " | final peak " + fixed$(finalPeak, 3)

    Select outer viewport: 0, 8, 0, 5.3
    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizDrum, vizResult, vizBass
endif

# === Cleanup ===
removeObject: bassLayer
appendInfoLine: ""
appendInfoLine: "Cleaning up..."

removeObject: workID
removeObject: lowID
removeObject: lowmidID
removeObject: intBroadID
removeObject: intLowID
removeObject: intLowmidID

# === Output ===
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Detected: ", numKicks, " kick-like onsets; injected: ", numTriggers, " bass trigger(s)"
appendInfoLine: ""
appendInfoLine: "Created:"
appendInfoLine: "  - TextGrid: KD_Kicks (tiers: Kicks, BassTriggers)"
appendInfoLine: "  - Sound: ", drum$, "_with_bass"

if play_result
    selectObject: resultID
    Play
endif

selectObject: resultID
plusObject: tgID
