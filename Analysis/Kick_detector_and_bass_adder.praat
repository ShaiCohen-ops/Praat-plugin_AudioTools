# ============================================================
# Praat AudioTools - Kick_Detector_and_Bass_Adder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Detects kicks in a drum loop using multi-band z-scored
#   intensity features (low band intensity, broadband flux,
#   low-mid penalty), then places a bass sample at each kick
#   position via Formula-based time-shifted addition.
#
# Usage:
#   Select TWO Sound objects: 1) Drum loop, 2) Bass sample
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
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

form Kick Detector and Bass Adder v0.5
    real Score_threshold 0.80
    real Derivative_threshold 0.60
    real Refractory_period 0.09
    real Time_offset 0.052
    real Weight_low 1.0
    real Weight_flux 0.5
    real Weight_lowmid_penalty 0.5
    real Bass_gain 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

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
writeInfoLine: "=== Kick Detector and Bass Adder v0.5 ==="
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
minPitchForIntensity = 0.8 / safeWindow
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
appendInfoLine: "Normalizing..."

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
appendInfoLine: "Detecting kicks..."

tgID = Create TextGrid: xmin, xmax, "Kicks", "Kicks"
Rename: "KD_Kicks"

lastHitTime = xmin - refractory_period
numKicks = 0

# Store kick times in array
kickTimes# = zero#(1000)

for i from 2 to n - 1
    t = time#[i]
    if score#[i] > score_threshold and zDLow#[i] > derivative_threshold and t - lastHitTime >= refractory_period
        imax = i
        smax = score#[i]
        if score#[i-1] > smax
            imax = i - 1
            smax = score#[i-1]
        endif
        if score#[i+1] > smax
            imax = i + 1
        endif
        
        thit = time#[imax] + time_offset
        
        if thit >= xmin and thit <= xmax
            selectObject: tgID
            Insert point: 1, thit, "kick"
            lastHitTime = thit
            numKicks = numKicks + 1
            kickTimes#[numKicks] = thit
        endif
    endif
endfor

appendInfoLine: "Detected ", numKicks, " kicks"

# === Mix Bass Sample at Kick Positions ===
wasNormalized = 0
if numKicks > 0
    appendInfoLine: "Mixing bass at kick positions..."
    
    # Prepare bass sample (resample and channel-match)
    if bassRate <> drumRate
        selectObject: bassID
        bassResamp = Resample: drumRate, 50
    else
        selectObject: bassID
        bassResamp = Copy: "bass_temp"
    endif
    
    selectObject: bassResamp
    bassChNow = Get number of channels
    if bassChNow = 1 and drumChannels = 2
        bassReady = Convert to stereo
        removeObject: bassResamp
        bassResamp = bassReady
    elsif bassChNow = 2 and drumChannels = 1
        bassReady = Convert to mono
        removeObject: bassResamp
        bassResamp = bassReady
    endif
    
    # Apply gain
    if bass_gain <> 1
        selectObject: bassResamp
        gain$ = string$(bass_gain)
        Formula: "self * " + gain$
    endif
    
    # Get bass timing info
    selectObject: bassResamp
    bassStart = Get start time
    bassEnd = Get end time
    bassDurNow = bassEnd - bassStart
    
    # Create output
    selectObject: drumID
    resultID = Copy: drum$ + "_with_bass"
    
    # Mix bass at each kick using time-shifted Formula
    # v0.5 FIX: `fi` (not `endif`) closes Formula inline ternary,
    # and `object(id, x)` modernization replaces `Object_<id>(x)`.
    bassId$ = string$(bassResamp)
    bassStart$ = string$(bassStart)
    bassDur$ = string$(bassDurNow)
    
    for k from 1 to numKicks
        kickTime = kickTimes#[k]
        kickT$ = string$(kickTime)
        kickEnd = kickTime + bassDurNow
        kickEnd$ = string$(kickEnd)
        
        selectObject: resultID
        # Add bass sample shifted to kick position
        Formula: "self + (if x >= " + kickT$ + " and x < " + kickEnd$ + " then object(" + bassId$ + ", x - " + kickT$ + " + " + bassStart$ + ") else 0 fi)"
        
        appendInfoLine: "  Kick ", k, " at ", fixed$(kickTime, 3), " s"
    endfor
    
    removeObject: bassResamp
    
    # Normalize if clipping
    selectObject: resultID
    maxAmp = Get maximum: 0, 0, "Sinc70"
    minAmp = Get minimum: 0, 0, "Sinc70"
    peak = max(abs(maxAmp), abs(minAmp))
    if peak > 0.99
        appendInfoLine: "Normalizing output (peak was ", fixed$(peak, 2), ")"
        Scale peak: 0.99
        wasNormalized = 1
    endif
else
    appendInfoLine: "No kicks detected - copying original"
    selectObject: drumID
    resultID = Copy: drum$ + "_with_bass"
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
# VISUALIZATION  (8 x 8 canvas — suite standard)
# v0.4 had no visualization. v0.5 adds the suite layout.
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # Mono copies of drum and result for waveform panels
    selectObject: drumID
    if drumChannels > 1
        vizDrum = Convert to mono
    else
        vizDrum = Copy: "viz_drum"
    endif
    
    selectObject: resultID
    resNumCh = Get number of channels
    if resNumCh > 1
        vizResult = Convert to mono
    else
        vizResult = Copy: "viz_result"
    endif
    
    # SHARED y-axis from BOTH drum and result
    selectObject: vizDrum
    dPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    rPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = dPeak
    if rPeak > sharedPeak
        sharedPeak = rPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.15
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##KICK DETECTOR + BASS ADDER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... drum$ + " <- " + bass$
        ... + "  |  " + string$(numKicks) + " kicks (" + fixed$(kicksPerSec, 2) + "/s)"
        ... + "  |  score >" + fixed$(score_threshold, 2)
        ... + "  |  dz_low >" + fixed$(derivative_threshold, 2)
        ... + "  |  offset " + fixed$(time_offset * 1000, 1) + " ms"
        ... + "  |  gain " + fixed$(bass_gain, 2)

    # ----------------------------------------------------------
    # PANEL A: DRUM WAVEFORM + KICK MARKERS  (left, headline)
    # The detection diagnostic — kicks shown as orange vertical
    # stems with numbered labels on the drum waveform.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, dur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, dur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, dur, 0
    
    # Drum waveform behind (gray)
    selectObject: vizDrum
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, dur, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Kick markers on top (orange stems)
    Colour: "{0.95, 0.55, 0.20}"
    Line width: 1.5
    for k from 1 to numKicks
        kt = kickTimes#[k]
        # Vertical stem
        Draw line: kt, -sharedAmp * 0.95, kt, sharedAmp * 0.95
        # Top dot
        Paint circle (mm): "{0.95, 0.55, 0.20}", kt, sharedAmp * 0.95, 0.8
    endfor
    Line width: 1
    
    # Kick number labels (only if not too crowded — show first 16
    # or every Nth if more)
    if numKicks <= 16
        labelStride = 1
    else
        labelStride = ceiling(numKicks / 16)
    endif
    
    Font size: 5
    Colour: "{0.55, 0.30, 0.15}"
    for k from 1 to numKicks
        if k mod labelStride = 0 or k = 1 or k = numKicks
            kt = kickTimes#[k]
            Text: kt, "centre", -sharedAmp * 0.9, "half", string$(k)
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: SCORE CURVE WITH THRESHOLDS  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, dur, scoreYMin, scoreYMax
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, dur, scoreYMin, scoreYMax
    
    # Zero line
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: 0, 0, dur, 0
    
    # Reference gridlines
    Colour: "{0.88, 0.88, 0.92}"
    Dotted line
    if scoreYMax >= 1
        Draw line: 0, 1, dur, 1
    endif
    if scoreYMax >= 2
        Draw line: 0, 2, dur, 2
    endif
    if scoreYMax >= 3
        Draw line: 0, 3, dur, 3
    endif
    Solid line
    
    # Score threshold line (red dashed)
    Colour: "{0.85, 0.25, 0.25}"
    Line width: 1.5
    Dashed line
    Draw line: 0, score_threshold, dur, score_threshold
    Solid line
    
    # Score curve (purple)
    Colour: "{0.55, 0.30, 0.70}"
    Line width: 1.5
    for i from 2 to n
        Draw line: time#[i-1], score#[i-1], time#[i], score#[i]
    endfor
    Line width: 1
    
    # Mark kick positions on the score curve (small orange dots)
    Colour: "{0.95, 0.55, 0.20}"
    for k from 1 to numKicks
        kt = kickTimes#[k]
        # Find the score at this time (subtract time_offset to undo the shift)
        ktUnshifted = kt - time_offset
        # Approximate frame index
        if ktUnshifted >= time#[1] and ktUnshifted <= time#[n]
            fIdx = round((ktUnshifted - time#[1]) / (time#[n] - time#[1]) * (n - 1)) + 1
            if fIdx >= 1 and fIdx <= n
                Paint circle (mm): "{0.95, 0.55, 0.20}", ktUnshifted, score#[fIdx], 0.8
            endif
        endif
    endfor
    
    # Inline legend
    Font size: 5
    Colour: "{0.55, 0.30, 0.70}"
    Text: dur * 0.02, "left", scoreYMax - 0.15 * (scoreYMax - scoreYMin), "half", "score"
    Colour: "{0.85, 0.25, 0.25}"
    Text: dur * 0.10, "left", score_threshold + 0.04 * (scoreYMax - scoreYMin), "half", "threshold " + fixed$(score_threshold, 2)
    Colour: "{0.95, 0.55, 0.20}"
    Text: dur * 0.32, "left", scoreYMax - 0.15 * (scoreYMax - scoreYMin), "half", "kicks"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Score (z-units)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Drum waveform + kick markers (orange)"
    Text: 6.10, "centre", 7.30, "half", "Score curve (purple) + threshold (red dashed)"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM  (first 4 s)
    # Gray = drum, blue = result, orange = kick positions.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 4
    if zoomDur > dur
        zoomDur = dur
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif
    
    selectObject: vizDrum
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: vizResult
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Kick markers behind (so waveforms draw on top)
    Colour: "{0.95, 0.75, 0.50}"
    Line width: 1
    Dotted line
    for k from 1 to numKicks
        kt = kickTimes#[k]
        if kt < zoomDur
            Draw line: kt, -z_amp, kt, z_amp
        endif
    endfor
    Solid line
    
    # Drum behind (gray)
    selectObject: vizDrum
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Result on top (blue)
    selectObject: vizResult
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur, 1) + " s  (gray = drum, blue = result, orange = kicks)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: FULL RESULT WAVEFORM + ALL KICK MARKERS
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    Axes: 0, finalDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    # Kick markers (orange dotted)
    Colour: "{0.95, 0.75, 0.50}"
    Line width: 1
    Dotted line
    for k from 1 to numKicks
        kt = kickTimes#[k]
        Draw line: kt, -sharedAmp, kt, sharedAmp
    endfor
    Solid line
    
    # Result waveform (blue)
    selectObject: vizResult
    Colour: "{0.20, 0.50, 0.80}"
    Line width: 1
    Draw: 0, finalDur, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform with kick markers (dotted = injection points)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if wasNormalized
        normStr$ = "normalized (was > 0.99)"
    else
        normStr$ = "no normalization needed"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + drum$ + "##"
        ... + "  + " + bass$
        ... + "  |  Kicks: " + string$(numKicks) + " (" + fixed$(kicksPerSec, 2) + "/s)"
        ... + "  |  Score range: " + fixed$(scoreMin, 2) + "-" + fixed$(scoreMax, 2)
        ... + "  |  Score thresh: " + fixed$(score_threshold, 2)
        ... + "  |  dz_low thresh: " + fixed$(derivative_threshold, 2)
        ... + "  |  Refractory: " + fixed$(refractory_period * 1000, 0) + " ms"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Weights: low=" + fixed$(weight_low, 2) + " flux=" + fixed$(weight_flux, 2) + " lowmid_pen=" + fixed$(weight_lowmid_penalty, 2)
        ... + "  |  Time offset: " + fixed$(time_offset * 1000, 1) + " ms"
        ... + "  |  Bass gain: " + fixed$(bass_gain, 2)
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  " + normStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: vizDrum, vizResult
endif

# === Cleanup ===
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
appendInfoLine: "Detected: ", numKicks, " kicks (", fixed$(kicksPerSec, 2), "/s)"
appendInfoLine: ""
appendInfoLine: "Created:"
appendInfoLine: "  - TextGrid: KD_Kicks (kick markers)"
appendInfoLine: "  - Sound: ", drum$, "_with_bass"

if play_result
    selectObject: resultID
    Play
endif

selectObject: resultID
plusObject: tgID
