# ============================================================
# Praat AudioTools - Kick_Detector_and_Bass_Adder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Fixed bass mixing
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Detects kicks in a drum loop using multi-band analysis,
#   then places a bass sample at each kick position.
#
# Usage:
#   Select TWO Sound objects: 1) Drum loop, 2) Bass sample
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sounds: 1) Drum loop, 2) Bass sample"
endif

drumID = selected("Sound", 1)
bassID = selected("Sound", 2)
drum$ = selected$("Sound", 1)
bass$ = selected$("Sound", 2)

form Kick Detector and Bass Adder v0.4
    comment === Sound Assignment ===
    comment First selected = Drum loop, Second = Bass sample
    comment === Detection Parameters ===
    real Score_threshold 0.80
    real Derivative_threshold 0.60
    real Refractory_period 0.09
    comment === Timing Adjustment ===
    real Time_offset 0.052
    comment === Score Weights ===
    real Weight_low 1.0
    real Weight_flux 0.5
    real Weight_lowmid_penalty 0.5
    comment === Mix ===
    real Bass_gain 1.0
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
writeInfoLine: "=== Kick Detector and Bass Adder v0.4 ==="
appendInfoLine: "Drum loop: ", drum$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Bass sample: ", bass$, " (", fixed$(bassDur, 3), " s)"
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
        # Formula: if x is within kick's bass region, add bass value at (x - kickTime + bassStart)
        Formula: "self + (if x >= " + kickT$ + " and x < " + kickEnd$ + " then Object_" + bassId$ + "(x - " + kickT$ + " + " + bassStart$ + ") else 0 endif)"
        
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
    endif
else
    appendInfoLine: "No kicks detected - copying original"
    selectObject: drumID
    resultID = Copy: drum$ + "_with_bass"
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
appendInfoLine: "Detected: ", numKicks, " kicks"
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