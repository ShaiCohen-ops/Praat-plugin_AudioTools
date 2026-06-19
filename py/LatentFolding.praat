# ============================================================
# Praat AudioTools - LatentFolding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Staleness fix; engine LRU window 4->8 (breaks Mirror-manifold event loop)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent Folding — Topological Manifold Navigation
#
#   Treats the learned latent audio space as a deformable manifold.
#   Three topologies: Mirror (reflection), Möbius (twist/inversion),
#   Torus (seamless wrap). As the observer traverses the space,
#   boundaries fold or invert acoustic identity — not time-reversal,
#   but identity-reversal. Creates "Recursive Spectralism."
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-Specific Python Discovery ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_folding.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/latent_folding.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: latent_folding.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_latfold_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_latfold_events.csv"
tempOutput$  = temporaryDirectory$ + "/temp_latfold_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_latfold_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_latfold_probe.ok"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Latent Folding v1.1 — Topological Manifold
    optionmenu Preset: 1
        option Custom
        option Gentle mirror
        option Sharp mirror
        option Möbius twist
        option Torus loop
        option Palindromic mirror
        option Palindromic Möbius
    integer Latent_size 8
    integer Learning_steps 100
    optionmenu Manifold_type: 1
        option Mirror (Reflection)
        option Möbius (Twist)
        option Torus (Infinite wrap)
    integer Fold_density 3
    real Curvature 0.5
    real Permutation_intensity 0.5
    real Symmetry_(0_off_1_palindrome) 0.0
    real Speed 0.5
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    latent_size = 8
    learning_steps = 100
    manifold_type = 1
    fold_density = 2
    curvature = 0.3
    permutation_intensity = 0.3
    symmetry = 0.0
    speed = 0.4
    presetName$ = "GentleMirror"
elsif preset = 3
    latent_size = 8
    learning_steps = 100
    manifold_type = 1
    fold_density = 5
    curvature = 0.9
    permutation_intensity = 0.7
    symmetry = 0.0
    speed = 0.6
    presetName$ = "SharpMirror"
elsif preset = 4
    latent_size = 10
    learning_steps = 120
    manifold_type = 2
    fold_density = 3
    curvature = 0.6
    permutation_intensity = 0.5
    symmetry = 0.0
    speed = 0.5
    presetName$ = "MöbiusTwist"
elsif preset = 5
    latent_size = 8
    learning_steps = 100
    manifold_type = 3
    fold_density = 2
    curvature = 0.4
    permutation_intensity = 0.4
    symmetry = 0.0
    speed = 0.5
    presetName$ = "TorusLoop"
elsif preset = 6
    latent_size = 10
    learning_steps = 120
    manifold_type = 1
    fold_density = 3
    curvature = 0.5
    permutation_intensity = 0.5
    symmetry = 1.0
    speed = 0.5
    presetName$ = "PalindromicMirror"
elsif preset = 7
    latent_size = 12
    learning_steps = 150
    manifold_type = 2
    fold_density = 4
    curvature = 0.7
    permutation_intensity = 0.6
    symmetry = 1.0
    speed = 0.6
    presetName$ = "PalindromicMöbius"
else
    presetName$ = "Custom"
endif

# Clamp
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif
if learning_steps < 10
    learning_steps = 10
endif
if learning_steps > 500
    learning_steps = 500
endif
if fold_density < 1
    fold_density = 1
endif
if fold_density > 12
    fold_density = 12
endif
if curvature < 0
    curvature = 0
endif
if curvature > 1
    curvature = 1
endif
if permutation_intensity < 0
    permutation_intensity = 0
endif
if permutation_intensity > 1
    permutation_intensity = 1
endif
if symmetry < 0
    symmetry = 0
endif
if symmetry > 1
    symmetry = 1
endif

# Map menu to 0-based
manifoldInt = manifold_type - 1

if manifold_type = 1
    manifoldName$ = "Mirror"
elsif manifold_type = 2
    manifoldName$ = "Möbius"
else
    manifoldName$ = "Torus"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Latent Folding v1.1 — Topological Manifold ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Manifold:      ", manifoldName$
appendInfoLine: "Fold density:  ", fold_density
appendInfoLine: "Curvature:     ", fixed$(curvature, 2)
appendInfoLine: "Permutation:   ", fixed$(permutation_intensity, 2)
appendInfoLine: "Symmetry:      ", fixed$(symmetry, 2)
appendInfoLine: "Speed:         ", fixed$(speed, 2)
appendInfoLine: "Latent:        ", latent_size
appendInfoLine: ""

# ---- ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency
nChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Event Segmentation
# ===========================================================================
appendInfoLine: "[2/5] Segmenting events..."

minEventDur = 0.200
maxEventDur = 3.000

selectObject: sound
if nChannels > 1
    Extract one channel: 1
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif

selectObject: analysisMono
pitchObj = To Pitch: 0.01, 75, 600

selectObject: analysisMono
harmObj = To Harmonicity (cc): 0.01, 75, 0.1, 1.0

selectObject: analysisMono
intObj = To Intensity: 100, 0.01, "yes"

selectObject: intObj
intMatrix = Down to Matrix
intSound = To Sound (slice): 1
selectObject: intSound
ppObj = To PointProcess (extrema): 1, "yes", "no", "Sinc70"

selectObject: ppObj
nPeaks = Get number of points

bound_1 = 0
bound_2 = dur
iBound = 3
for iPeak from 1 to nPeaks
    selectObject: ppObj
    peakT = Get time from index: iPeak
    bound_'iBound' = peakT
    iBound = iBound + 1
endfor
nBounds = iBound - 1

for i from 1 to nBounds
    for j from i + 1 to nBounds
        if bound_'j' < bound_'i'
            tmpVal = bound_'i'
            bound_'i' = bound_'j'
            bound_'j' = tmpVal
        endif
    endfor
endfor

nFinal = 0
prevT = -1
for i from 1 to nBounds
    thisT = bound_'i'
    if thisT - prevT >= minEventDur
        nFinal = nFinal + 1
        final_'nFinal' = thisT
        prevT = thisT
    endif
endfor

if nFinal > 0
    lastFinal = final_'nFinal'
    if dur - lastFinal > 0.050
        nFinal = nFinal + 1
        final_'nFinal' = dur
    else
        final_'nFinal' = dur
    endif
else
    nFinal = 2
    final_1 = 0
    final_2 = dur
endif

nEvents = 0
for i from 1 to nFinal - 1
    evStart = final_'i'
    iNext = i + 1
    evEnd = final_'iNext'
    evDur = evEnd - evStart

    if evDur > maxEventDur
        nChunks = ceiling(evDur / maxEventDur)
        chunkDur = evDur / nChunks
        for iChunk from 0 to nChunks - 1
            nEvents = nEvents + 1
            evS_'nEvents' = evStart + iChunk * chunkDur
            if iChunk = nChunks - 1
                evE_'nEvents' = evEnd
            else
                evE_'nEvents' = evStart + (iChunk + 1) * chunkDur
            endif
        endfor
    elsif evDur >= minEventDur
        nEvents = nEvents + 1
        evS_'nEvents' = evStart
        evE_'nEvents' = evEnd
    endif
endfor

if nEvents < 2
    nEvents = 1
    evS_1 = 0
    evE_1 = dur
endif

appendInfoLine: "  Found ", nEvents, " events"

# ===========================================================================
# Stage 3 — Extract Features + Export
# ===========================================================================
appendInfoLine: "[3/5] Extracting features..."

Create Table with column names: "eventFeatures", nEvents, "start_time end_time label pitch_stability intensity_mean attack_slope hnr_mean"
eventTable = selected("Table")

for iEv from 1 to nEvents
    t1 = evS_'iEv'
    t2 = evE_'iEv'
    tMid = (t1 + t2) / 2

    selectObject: eventTable
    Set numeric value: iEv, "start_time", t1
    Set numeric value: iEv, "end_time", t2
    Set string value: iEv, "label", "ev" + string$(iEv)

    selectObject: pitchObj
    pMean = Get mean: t1, t2, "Hertz"
    pStd = Get standard deviation: t1, t2, "Hertz"
    if pMean = undefined or pMean = 0
        pitchStab = 0
    else
        if pStd = undefined
            pStd = 0
        endif
        pitchCV = pStd / (pMean + 0.001)
        pitchStab = 1 - min(1, pitchCV)
        if pitchStab < 0
            pitchStab = 0
        endif
    endif
    selectObject: eventTable
    Set numeric value: iEv, "pitch_stability", pitchStab

    selectObject: intObj
    iMean = Get mean: t1, t2, "energy"
    if iMean = undefined
        iMean = 0
    endif
    iStart = Get value at time: t1, "Cubic"
    if iStart = undefined
        iStart = 0
    endif
    iPeak = Get maximum: t1, t2, "Parabolic"
    if iPeak = undefined
        iPeak = iStart
    endif
    tPeak = Get time of maximum: t1, t2, "Parabolic"
    if tPeak = undefined
        tPeak = tMid
    endif
    attackTime = tPeak - t1
    if attackTime > 0.001
        attackSlope = (iPeak - iStart) / attackTime
    else
        attackSlope = 0
    endif
    selectObject: eventTable
    Set numeric value: iEv, "intensity_mean", iMean
    Set numeric value: iEv, "attack_slope", attackSlope

    selectObject: harmObj
    hMean = Get mean: t1, t2
    if hMean = undefined
        hMean = 0
    endif
    selectObject: eventTable
    Set numeric value: iEv, "hnr_mean", hMean
endfor

appendInfoLine: "  Exporting temp files..."
selectObject: sound
Save as WAV file: tempInput$
selectObject: eventTable
Save as comma-separated file: tempCSV$

removeObject: analysisMono, pitchObj, harmObj, intObj
removeObject: intMatrix, intSound, ppObj, eventTable

# ===========================================================================
# Stage 4 — Call Python
# ===========================================================================
appendInfoLine: "[4/5] Running Python engine..."
appendInfoLine: "  (Training AE + ", manifoldName$, " folding, density=", fold_density, ")"

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + string$(latent_size)
    ... + " " + string$(learning_steps)
    ... + " " + string$(manifoldInt)
    ... + " " + string$(fold_density)
    ... + " " + fixed$(curvature, 4)
    ... + " " + fixed$(permutation_intensity, 4)
    ... + " " + fixed$(symmetry, 4)
    ... + " " + fixed$(speed, 4)
    ... + " " + string$(seed)

# Remove any stale output/stats from a PREVIOUS run before calling Python.
# The temp filenames are fixed, so without this a crashed run would leave
# the old files in place and the fileReadable() check below would pass on
# stale data - silently importing a previous result as if it were new.
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif

runSystem_nocheck: pythonCall$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python folding engine failed." + newline$ + "Check terminal for error details."
endif

# ===========================================================================
# Stage 5 — Import Result
# ===========================================================================
appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_fold"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

# ===========================================================================
# Read Stats
# ===========================================================================
nEvStat$ = "?"
nStepsStat$ = "?"
uniqueStat$ = "?"
repRateStat$ = "?"
avgTravelStat$ = "?"
outDurStat$ = "?"
manifoldStat$ = "?"
foldDensStat$ = "?"
curvatureStat$ = "?"
permStat$ = "?"
symStat$ = "?"
nFoldEvents$ = "?"
nMirrorsStat$ = "?"
nTwistsStat$ = "?"
nWrapsStat$ = "?"
hasSymStat$ = "?"
palindromicStat$ = "?"
finalLoss$ = "?"
initialLoss$ = "?"
meanEvDur$ = "?"
warningStat$ = ""
topEv_0$ = "?"
topEv_1$ = "?"
topEv_2$ = "?"

nFEvPts = 0
nFTrajPts = 0
nFoldMarkers = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_output_steps="
    nStepsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "unique_events="
    uniqueStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "repetition_rate="
    repRateStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "avg_latent_travel="
    avgTravelStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "manifold="
    manifoldStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "fold_density="
    foldDensStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "curvature="
    curvatureStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "permutation="
    permStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "symmetry="
    symStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_fold_events="
    nFoldEvents$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_mirrors="
    nMirrorsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_twists="
    nTwistsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_wraps="
    nWrapsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "has_symmetry="
    hasSymStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "palindromic_score="
    palindromicStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEvDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "top_event_0="
    topEv_0$ = parseStatLine.result$
    @parseStatLine: statsText$, "top_event_1="
    topEv_1$ = parseStatLine.result$
    @parseStatLine: statsText$, "top_event_2="
    topEv_2$ = parseStatLine.result$

    # ── Parse folding path trajectory ──
    @parseStatLine: statsText$, "n_ev_pts="
    nFEvPts$ = parseStatLine.result$
    nFEvPts = 0
    if nFEvPts$ <> "?"
        nFEvPts = number(nFEvPts$)
    endif
    if nFEvPts > 200
        nFEvPts = 200
    endif
    for iEP from 0 to nFEvPts - 1
        @parseStatLine: statsText$, "fev_" + string$(iEP) + "="
        epRaw$ = parseStatLine.result$
        fep_'iEP'_x = 0
        fep_'iEP'_y = 0
        if epRaw$ <> "?"
            comma = index(epRaw$, ",")
            if comma > 0
                fep_'iEP'_x = number(left$(epRaw$, comma - 1))
                fep_'iEP'_y = number(mid$(epRaw$, comma + 1, length(epRaw$) - comma))
            endif
        endif
    endfor

    @parseStatLine: statsText$, "n_traj_pts="
    nFTrajPts$ = parseStatLine.result$
    nFTrajPts = 0
    if nFTrajPts$ <> "?"
        nFTrajPts = number(nFTrajPts$)
    endif
    if nFTrajPts > 200
        nFTrajPts = 200
    endif
    for iTP from 0 to nFTrajPts - 1
        @parseStatLine: statsText$, "ftr_" + string$(iTP) + "="
        tpRaw$ = parseStatLine.result$
        ftp_'iTP'_x = 0
        ftp_'iTP'_y = 0
        if tpRaw$ <> "?"
            comma = index(tpRaw$, ",")
            if comma > 0
                ftp_'iTP'_x = number(left$(tpRaw$, comma - 1))
                ftp_'iTP'_y = number(mid$(tpRaw$, comma + 1, length(tpRaw$) - comma))
            endif
        endif
    endfor

    @parseStatLine: statsText$, "n_fold_markers="
    nFoldMarkers$ = parseStatLine.result$
    nFoldMarkers = 0
    if nFoldMarkers$ <> "?"
        nFoldMarkers = number(nFoldMarkers$)
    endif
    if nFoldMarkers > 100
        nFoldMarkers = 100
    endif
    for iFM from 0 to nFoldMarkers - 1
        @parseStatLine: statsText$, "fm_" + string$(iFM) + "="
        fmRaw$ = parseStatLine.result$
        fm_'iFM'_x = 0
        fm_'iFM'_y = 0
        fm_'iFM'_type$ = "mirror"
        if fmRaw$ <> "?"
            comma1 = index(fmRaw$, ",")
            if comma1 > 0
                fm_'iFM'_x = number(left$(fmRaw$, comma1 - 1))
                rest$ = mid$(fmRaw$, comma1 + 1, length(fmRaw$) - comma1)
                comma2 = index(rest$, ",")
                if comma2 > 0
                    fm_'iFM'_y = number(left$(rest$, comma2 - 1))
                    fm_'iFM'_type$ = mid$(rest$, comma2 + 1, length(rest$) - comma2)
                else
                    fm_'iFM'_y = number(rest$)
                endif
            endif
        endif
    endfor
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Latent Folding — Topological Manifold##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | " + manifoldStat$ + " | Folds=" + nFoldEvents$

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.7
    Select inner viewport: 0.6, 7.7, 0.65, 1.65
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Colour: "{0.8, 0.3, 0.3}"
    Axes: 0, dur, -1, 1
    for iEv from 1 to nEvents
        evBound = evS_'iEv'
        if evBound > 0 and evBound < dur
            Draw line: evBound, -0.9, evBound, 0.9
        endif
    endfor
    Text top: "no", string$(nEvents) + " events | " + fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.7, 2.8
    Select inner viewport: 0.6, 7.7, 1.75, 2.75
    selectObject: resultSound
    Colour: "{0.5, 0.2, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Folded"
    Text bottom: "yes", "Time (s)"

    # === Original Spectrogram ===
    Select outer viewport: 0, 8, 2.9, 4.1
    Select inner viewport: 0.6, 7.7, 3.0, 4.0
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrig

    # === Output Spectrogram ===
    Select outer viewport: 0, 8, 4.1, 5.3
    Select inner viewport: 0.6, 7.7, 4.2, 5.2
    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpFold = selected("Sound")
    else
        selectObject: resultSound
        Copy: "tmpFold"
        tmpFold = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specFold = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Folded spectrogram"
    removeObject: specFold, tmpFold

    # === Folding Path Trajectory ===
    Select outer viewport: 0, 8, 5.4, 6.7
    Select inner viewport: 0.6, 7.7, 5.5, 6.6

    if nFTrajPts > 1 or nFEvPts > 0
        axMinX = 0
        axMaxX = 1
        axMinY = 0
        axMaxY = 1
        gotBounds = 0
        for iB from 0 to nFEvPts - 1
            bx = fep_'iB'_x
            by = fep_'iB'_y
            if gotBounds = 0
                axMinX = bx
                axMaxX = bx
                axMinY = by
                axMaxY = by
                gotBounds = 1
            else
                if bx < axMinX
                    axMinX = bx
                endif
                if bx > axMaxX
                    axMaxX = bx
                endif
                if by < axMinY
                    axMinY = by
                endif
                if by > axMaxY
                    axMaxY = by
                endif
            endif
        endfor
        for iB from 0 to nFTrajPts - 1
            bx = ftp_'iB'_x
            by = ftp_'iB'_y
            if gotBounds = 0
                axMinX = bx
                axMaxX = bx
                axMinY = by
                axMaxY = by
                gotBounds = 1
            else
                if bx < axMinX
                    axMinX = bx
                endif
                if bx > axMaxX
                    axMaxX = bx
                endif
                if by < axMinY
                    axMinY = by
                endif
                if by > axMaxY
                    axMaxY = by
                endif
            endif
        endfor

        rangeX = axMaxX - axMinX
        rangeY = axMaxY - axMinY
        if rangeX < 0.01
            rangeX = 1
        endif
        if rangeY < 0.01
            rangeY = 1
        endif
        axMinX = axMinX - rangeX * 0.1
        axMaxX = axMaxX + rangeX * 0.1
        axMinY = axMinY - rangeY * 0.1
        axMaxY = axMaxY + rangeY * 0.1

        Axes: axMinX, axMaxX, axMinY, axMaxY
        Paint rectangle: "{0.97, 0.97, 0.99}", axMinX, axMaxX, axMinY, axMaxY

        for iEP from 0 to nFEvPts - 1
            Paint circle (mm): "{0.75, 0.75, 0.75}", fep_'iEP'_x, fep_'iEP'_y, 1.2
        endfor

        Colour: "{0.5, 0.2, 0.5}"
        Line width: 2
        for iTP from 1 to nFTrajPts - 1
            iPrev = iTP - 1
            Draw line: ftp_'iPrev'_x, ftp_'iPrev'_y, ftp_'iTP'_x, ftp_'iTP'_y
        endfor
        Line width: 1

        for iFM from 0 to nFoldMarkers - 1
            fmType$ = fm_'iFM'_type$
            if fmType$ = "twist"
                Paint circle (mm): "{0.8, 0.3, 0.2}", fm_'iFM'_x, fm_'iFM'_y, 2.0
            elsif fmType$ = "wrap"
                Paint circle (mm): "{0.2, 0.6, 0.8}", fm_'iFM'_x, fm_'iFM'_y, 2.0
            else
                Paint circle (mm): "{0.3, 0.7, 0.4}", fm_'iFM'_x, fm_'iFM'_y, 2.0
            endif
        endfor

        if nFTrajPts > 0
            Paint circle (mm): "{0.2, 0.7, 0.3}", ftp_0_x, ftp_0_y, 2.0
            iLast = nFTrajPts - 1
            Paint circle (mm): "{0.8, 0.2, 0.2}", ftp_'iLast'_x, ftp_'iLast'_y, 2.0
        endif

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "PC2"
        Text bottom: "yes", "PC1"
        Text top: "no", "Folding path (" + manifoldStat$ + ") — green=mirror | red=twist | blue=wrap"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(folding path data not available)"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.8, 8.0
    Select inner viewport: 0.6, 7.7, 6.85, 7.95

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.76, "half", "Steps=" + nStepsStat$ + " | Unique=" + uniqueStat$ + "/" + nEvStat$ + " | Rep=" + repRateStat$ + " | Travel=" + avgTravelStat$
    Text: 0.02, "left", 0.58, "half", manifoldStat$ + " dens=" + foldDensStat$ + " curv=" + curvatureStat$ + " | Folds=" + nFoldEvents$ + " (m=" + nMirrorsStat$ + " t=" + nTwistsStat$ + " w=" + nWrapsStat$ + ")"
    Text: 0.02, "left", 0.40, "half", "AE: " + initialLoss$ + "->" + finalLoss$ + " | Latent=" + string$(latent_size) + " | Dur: " + fixed$(dur, 2) + "s->" + outDurStat$ + "s | RMS: " + fixed$(rms_orig, 4) + "->" + fixed$(rms_out, 4)

    Colour: "{0.4, 0.4, 0.5}"
    symLine$ = ""
    if hasSymStat$ = "1"
        symLine$ = "Palindrome=" + palindromicStat$ + " | "
    endif
    symLine$ = symLine$ + "Top: " + topEv_0$ + " | " + topEv_1$ + " | " + topEv_2$
    Text: 0.02, "left", 0.22, "half", symLine$

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", 0.06, "half", "Warn: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ===========================================================================
# Cleanup
# ===========================================================================
@cleanUpTempFiles

# ===========================================================================
# Summary
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_fold"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Manifold:  ", manifoldStat$
appendInfoLine: "Density:   ", foldDensStat$
appendInfoLine: "Curvature: ", curvatureStat$
appendInfoLine: "Permutation: ", permStat$
appendInfoLine: "Symmetry:  ", symStat$
appendInfoLine: ""
appendInfoLine: "Steps:     ", nStepsStat$
appendInfoLine: "Unique:    ", uniqueStat$, "/", nEvStat$
appendInfoLine: "Folds:     ", nFoldEvents$, " (mirrors=", nMirrorsStat$, " twists=", nTwistsStat$, " wraps=", nWrapsStat$, ")"

if hasSymStat$ = "1"
    appendInfoLine: "Palindromic score: ", palindromicStat$
endif

appendInfoLine: ""
appendInfoLine: "Duration:  ", fixed$(dur, 2), " s -> ", outDurStat$, " s"
appendInfoLine: "RMS:       ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4)
appendInfoLine: "AE loss:   ", initialLoss$, " -> ", finalLoss$
appendInfoLine: "Top events: ", topEv_0$, " | ", topEv_1$, " | ", topEv_2$

if warningStat$ <> "?" and warningStat$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", warningStat$
endif

selectObject: resultSound

if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc