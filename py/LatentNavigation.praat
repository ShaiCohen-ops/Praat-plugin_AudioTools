# ============================================================
# Praat AudioTools - LatentNavigation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Delete stale temp output/stats before Python call
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent Space Navigation (Audio → Audio)
#
#   Learns a latent space from event-level audio patches (on-the-fly
#   autoencoder), then navigates that space to generate a new timeline
#   by selecting/morphing events along a deterministic latent trajectory.
#   The result sounds like traveling through hidden acoustic identities.
#
#   Navigation modes:
#   - Trajectory: follows a path through latent space
#     (ThermoDrift / Attractor / Convection)
#   - Mixer: sweeps a 2D latent plane
#
#   Output modes:
#   - Selector: picks nearest event at each path step
#   - Morph: crossfades between nearest events
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
pythonScript$ = pluginDir$ + "py/latent_navigation.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/latent_navigation.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: latent_navigation.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_latnav_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_latnav_events.csv"
tempOutput$  = temporaryDirectory$ + "/temp_latnav_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_latnav_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_latnav_probe.ok"

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
form Latent Space Navigation v1.1
    optionmenu Preset: 1
        option Custom
        option Gentle drift
        option Deep attractors
        option Convection flow
        option Fast scatter
        option Slow morph
        option Dense mixer
    integer Learning_steps 100
    integer Latent_size 8
    integer Seed 42
    optionmenu Navigation_mode: 1
        option Trajectory
        option Mixer
    optionmenu Path_type: 1
        option ThermoDrift
        option Attractor
        option Convection
    real Travel_speed 0.5
    real Dwell_amount 0.3
    real Smoothing 0.4
    optionmenu Output_mode: 1
        option Selector
        option Morph
    optionmenu Target_duration: 1
        option Preserve
        option Expand
        option Compress
    real Density_(events_per_s) 3.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    learning_steps = 80
    latent_size = 6
    navigation_mode = 1
    path_type = 1
    travel_speed = 0.3
    dwell_amount = 0.5
    smoothing = 0.5
    output_mode = 1
    target_duration = 1
    density = 2.5
    presetName$ = "GentleDrift"
elsif preset = 3
    learning_steps = 150
    latent_size = 12
    navigation_mode = 1
    path_type = 2
    travel_speed = 0.4
    dwell_amount = 0.7
    smoothing = 0.3
    output_mode = 1
    target_duration = 1
    density = 3.0
    presetName$ = "DeepAttractors"
elsif preset = 4
    learning_steps = 120
    latent_size = 10
    navigation_mode = 1
    path_type = 3
    travel_speed = 0.6
    dwell_amount = 0.3
    smoothing = 0.4
    output_mode = 1
    target_duration = 1
    density = 3.5
    presetName$ = "ConvectionFlow"
elsif preset = 5
    learning_steps = 100
    latent_size = 8
    navigation_mode = 1
    path_type = 1
    travel_speed = 1.2
    dwell_amount = 0.1
    smoothing = 0.2
    output_mode = 1
    target_duration = 2
    density = 5.0
    presetName$ = "FastScatter"
elsif preset = 6
    learning_steps = 150
    latent_size = 10
    navigation_mode = 1
    path_type = 2
    travel_speed = 0.3
    dwell_amount = 0.6
    smoothing = 0.8
    output_mode = 2
    target_duration = 1
    density = 2.0
    presetName$ = "SlowMorph"
elsif preset = 7
    learning_steps = 100
    latent_size = 8
    navigation_mode = 2
    path_type = 1
    travel_speed = 0.5
    dwell_amount = 0.3
    smoothing = 0.5
    output_mode = 1
    target_duration = 1
    density = 4.0
    presetName$ = "DenseMixer"
else
    presetName$ = "Custom"
endif

# Clamp
if learning_steps < 10
    learning_steps = 10
endif
if learning_steps > 500
    learning_steps = 500
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif

# Map menu indices to Python integers (0-based)
navModeInt = navigation_mode - 1
pathTypeInt = path_type - 1
outModeInt = output_mode - 1
durModeInt = target_duration - 1

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Latent Space Navigation v1.1 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Learning steps: ", learning_steps
appendInfoLine: "Latent size:    ", latent_size
appendInfoLine: "Seed:           ", seed
appendInfoLine: ""
appendInfoLine: "Navigation:     ", navigation_mode$
appendInfoLine: "Path type:      ", path_type$
appendInfoLine: "Travel speed:   ", fixed$(travel_speed, 2)
appendInfoLine: "Dwell:          ", fixed$(dwell_amount, 2)
appendInfoLine: "Smoothing:      ", fixed$(smoothing, 2)
appendInfoLine: ""
appendInfoLine: "Output mode:    ", output_mode$
appendInfoLine: "Duration:       ", target_duration$
appendInfoLine: "Density:        ", fixed$(density, 1), " events/s"
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
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
appendInfoLine: "[3/5] Extracting per-event features..."

Create Table with column names: "eventFeatures", nEvents, "start_time end_time pitch_stability intensity_mean attack_slope hnr_mean"
eventTable = selected("Table")

for iEv from 1 to nEvents
    t1 = evS_'iEv'
    t2 = evE_'iEv'
    tMid = (t1 + t2) / 2

    selectObject: eventTable
    Set numeric value: iEv, "start_time", t1
    Set numeric value: iEv, "end_time", t2

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
# Stage 4 — Call Python Engine
# ===========================================================================
appendInfoLine: "[4/5] Running Python engine..."
appendInfoLine: "  (Training AE + navigating latent space)"

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + string$(learning_steps)
    ... + " " + string$(latent_size)
    ... + " " + string$(seed)
    ... + " " + string$(navModeInt)
    ... + " " + string$(pathTypeInt)
    ... + " " + fixed$(travel_speed, 4)
    ... + " " + fixed$(dwell_amount, 4)
    ... + " " + fixed$(smoothing, 4)
    ... + " " + string$(outModeInt)
    ... + " " + string$(durModeInt)
    ... + " " + fixed$(density, 4)

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
    exitScript: "Python latent navigation engine failed." + newline$ + "Check terminal for error details."
endif

# ===========================================================================
# Stage 5 — Import Result
# ===========================================================================
appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_nav"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

# ===========================================================================
# Read Stats
# ===========================================================================
nEvStat$ = "?"
nOutputSteps$ = "?"
uniqueUsed$ = "?"
repRate$ = "?"
avgTravel$ = "?"
meanTempStat$ = "?"
outDurStat$ = "?"
navModeStat$ = "?"
pathTypeStat$ = "?"
outModeStat$ = "?"
finalLoss$ = "?"
initialLoss$ = "?"
meanEvDur$ = "?"
top0$ = "?"
top1$ = "?"
top2$ = "?"
warningStat$ = ""

nNEvPts = 0
nNTrajPts = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_output_steps="
    nOutputSteps$ = parseStatLine.result$
    @parseStatLine: statsText$, "unique_events_used="
    uniqueUsed$ = parseStatLine.result$
    @parseStatLine: statsText$, "repetition_rate="
    repRate$ = parseStatLine.result$
    @parseStatLine: statsText$, "avg_latent_travel="
    avgTravel$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_temperature="
    meanTempStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "nav_mode="
    navModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "path_type="
    pathTypeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_mode="
    outModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEvDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "top_event_0="
    top0$ = parseStatLine.result$
    @parseStatLine: statsText$, "top_event_1="
    top1$ = parseStatLine.result$
    @parseStatLine: statsText$, "top_event_2="
    top2$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$

    # ── Parse trajectory data ──
    @parseStatLine: statsText$, "n_ev_pts="
    nNEvPts$ = parseStatLine.result$
    if nNEvPts$ <> "?"
        nNEvPts = number(nNEvPts$)
    endif
    if nNEvPts > 200
        nNEvPts = 200
    endif
    for iEP from 0 to nNEvPts - 1
        @parseStatLine: statsText$, "nev_" + string$(iEP) + "="
        epRaw$ = parseStatLine.result$
        nep_'iEP'_x = 0
        nep_'iEP'_y = 0
        if epRaw$ <> "?"
            comma = index(epRaw$, ",")
            if comma > 0
                nep_'iEP'_x = number(left$(epRaw$, comma - 1))
                nep_'iEP'_y = number(mid$(epRaw$, comma + 1, length(epRaw$) - comma))
            endif
        endif
    endfor

    @parseStatLine: statsText$, "n_traj_pts="
    nNTrajPts$ = parseStatLine.result$
    if nNTrajPts$ <> "?"
        nNTrajPts = number(nNTrajPts$)
    endif
    if nNTrajPts > 200
        nNTrajPts = 200
    endif
    for iTP from 0 to nNTrajPts - 1
        @parseStatLine: statsText$, "ntr_" + string$(iTP) + "="
        tpRaw$ = parseStatLine.result$
        ntp_'iTP'_x = 0
        ntp_'iTP'_y = 0
        if tpRaw$ <> "?"
            comma = index(tpRaw$, ",")
            if comma > 0
                ntp_'iTP'_x = number(left$(tpRaw$, comma - 1))
                ntp_'iTP'_y = number(mid$(tpRaw$, comma + 1, length(tpRaw$) - comma))
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
    Text: 0.5, "centre", 0.6, "half", "##Latent Space Navigation##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | " + navModeStat$ + "/" + pathTypeStat$ + "/" + outModeStat$

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.65, 1.45
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    Colour: "{0.8, 0.3, 0.3}"
    Line width: 1
    Axes: 0, dur, -1, 1
    for iEv from 1 to nEvents
        evBound = evS_'iEv'
        if evBound > 0 and evBound < dur
            Draw line: evBound, -0.9, evBound, 0.9
        endif
    endfor
    Text top: "no", string$(nEvents) + " events | " + fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: resultSound
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Navigated"
    Text bottom: "yes", "Time (s)"

    # === Original Spectrogram ===
    Select outer viewport: 0, 8, 2.5, 3.7
    Select inner viewport: 0.6, 7.7, 2.6, 3.6

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
    Select outer viewport: 0, 8, 3.7, 4.9
    Select inner viewport: 0.6, 7.7, 3.8, 4.8

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpOut = selected("Sound")
    else
        Copy: "tmpOut"
        tmpOut = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Navigated spectrogram"
    removeObject: specOut, tmpOut

    # === Navigation Stats Panel ===
    Select outer viewport: 0, 8, 5.0, 5.8
    Select inner viewport: 0.6, 7.7, 5.1, 5.7

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.95, 0.97}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "Navigation:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.55, "half", "Steps=" + nOutputSteps$ + " | Unique=" + uniqueUsed$ + "/" + nEvStat$ + " | Rep.rate=" + repRate$ + " | Avg travel=" + avgTravel$
    Text: 0.02, "left", 0.20, "half", "Most used: [" + top0$ + "] [" + top1$ + "] [" + top2$ + "]"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Latent Navigation Trajectory ===
    Select outer viewport: 0, 8, 5.9, 7.1
    Select inner viewport: 0.6, 7.7, 6.0, 7.0

    if nNTrajPts > 1 or nNEvPts > 0
        axMinX = 0
        axMaxX = 1
        axMinY = 0
        axMaxY = 1
        gotBounds = 0
        for iB from 0 to nNEvPts - 1
            bx = nep_'iB'_x
            by = nep_'iB'_y
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
        for iB from 0 to nNTrajPts - 1
            bx = ntp_'iB'_x
            by = ntp_'iB'_y
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

        for iEP from 0 to nNEvPts - 1
            Paint circle (mm): "{0.75, 0.75, 0.75}", nep_'iEP'_x, nep_'iEP'_y, 1.2
        endfor

        Colour: "{0.2, 0.5, 0.7}"
        Line width: 2
        for iTP from 1 to nNTrajPts - 1
            iPrev = iTP - 1
            Draw line: ntp_'iPrev'_x, ntp_'iPrev'_y, ntp_'iTP'_x, ntp_'iTP'_y
        endfor
        Line width: 1

        if nNTrajPts > 0
            Paint circle (mm): "{0.2, 0.7, 0.3}", ntp_0_x, ntp_0_y, 2.0
            iLast = nNTrajPts - 1
            Paint circle (mm): "{0.8, 0.2, 0.2}", ntp_'iLast'_x, ntp_'iLast'_y, 2.0
        endif

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "PC2"
        Text bottom: "yes", "PC1"
        Text top: "no", "Latent trajectory (" + navModeStat$ + "/" + pathTypeStat$ + ") — ##S##=start ##E##=end"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(trajectory data not available)"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Summary Panel ===
    Select outer viewport: 0, 8, 7.2, 8.0
    Select inner viewport: 0.6, 7.7, 7.25, 7.95

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.68, "half", navModeStat$ + "/" + pathTypeStat$ + "/" + outModeStat$ + " | Steps=" + nOutputSteps$ + " Uniq=" + uniqueUsed$ + "/" + nEvStat$ + " Rep=" + repRate$ + " Trav=" + avgTravel$
    Text: 0.02, "left", 0.44, "half", "AE: " + initialLoss$ + "->" + finalLoss$ + " Lat=" + string$(latent_size) + " | Dur: " + fixed$(dur, 2) + "s->" + outDurStat$ + "s | RMS: " + fixed$(rms_orig, 4) + "->" + fixed$(rms_out, 4)
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.20, "half", "Top: [" + top0$ + "] [" + top1$ + "] [" + top2$ + "] | Temp=" + meanTempStat$ + " Dens=" + fixed$(density, 1) + "/s Seed=" + string$(seed)

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.60, "left", 0.20, "half", "Warn: " + warningStat$
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
appendInfoLine: "Output: ", soundName$, "_nav"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Navigation:"
appendInfoLine: "  Mode: ", navModeStat$, " | Path: ", pathTypeStat$, " | Output: ", outModeStat$
appendInfoLine: "  Steps: ", nOutputSteps$, " | Unique events: ", uniqueUsed$, "/", nEvStat$
appendInfoLine: "  Repetition rate: ", repRate$
appendInfoLine: "  Avg latent travel: ", avgTravel$
appendInfoLine: ""
appendInfoLine: "Autoencoder:"
appendInfoLine: "  Loss: ", initialLoss$, " -> ", finalLoss$
appendInfoLine: "  Mean temperature: ", meanTempStat$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s -> ", outDurStat$, " s"
appendInfoLine: "RMS: ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4)
if rms_orig > 0
    appendInfoLine: "RMS ratio: ", fixed$(rms_out / rms_orig, 3), "x"
endif

if warningStat$ <> "?" and warningStat$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", warningStat$
endif

appendInfoLine: ""
appendInfoLine: "Most used events:"
appendInfoLine: "  #1: ", top0$
appendInfoLine: "  #2: ", top1$
appendInfoLine: "  #3: ", top2$

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