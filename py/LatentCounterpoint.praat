# ============================================================
# Praat AudioTools - LatentCounterpoint.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   The Latent Counterpoint
#
#   Trains an autoencoder on-the-fly to learn a latent space from
#   event-level audio patches, then deploys multiple agents that
#   navigate the latent space simultaneously with counterpoint forces
#   (attraction, repulsion, inertia, jitter) to produce polyphonic
#   recombination of the input material.
#
#   Agent profiles:
#   - Cantus:  heavy, slow, gravitates to center of gravity
#   - Florid:  light, fast, attracted to rare/peripheral sounds
#   - Shadow:  mirrors Cantus with temporal lag + inverted coordinates
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
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

# ---- PATHS ----
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_counterpoint.py"
tempInput$   = pluginDir$ + "temp_latcp_input.wav"
tempCSV$     = pluginDir$ + "temp_latcp_events.csv"
tempOutput$  = pluginDir$ + "temp_latcp_output.wav"
tempStats$   = pluginDir$ + "temp_latcp_stats.txt"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- FORM ----
form The Latent Counterpoint v1.0
    optionmenu Preset: 1
        option Custom
        option Duo (2 voices)
        option Trio (3 voices)
        option Quartet (4 voices)
        option Dense ensemble (5 voices)
        option Tight counterpoint
        option Free scatter
    integer Number_of_agents 3
    integer Latent_size 8
    real Counterpoint_rigidity 0.5
    real Speed 0.5
    real Duration_(0_=_original) 0
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    number_of_agents = 2
    latent_size = 6
    counterpoint_rigidity = 0.4
    speed = 0.4
    presetName$ = "Duo"
elsif preset = 3
    number_of_agents = 3
    latent_size = 8
    counterpoint_rigidity = 0.5
    speed = 0.5
    presetName$ = "Trio"
elsif preset = 4
    number_of_agents = 4
    latent_size = 10
    counterpoint_rigidity = 0.6
    speed = 0.5
    presetName$ = "Quartet"
elsif preset = 5
    number_of_agents = 5
    latent_size = 12
    counterpoint_rigidity = 0.7
    speed = 0.6
    presetName$ = "DenseEnsemble"
elsif preset = 6
    number_of_agents = 3
    latent_size = 8
    counterpoint_rigidity = 1.5
    speed = 0.3
    presetName$ = "TightCP"
elsif preset = 7
    number_of_agents = 3
    latent_size = 10
    counterpoint_rigidity = 0.1
    speed = 1.2
    presetName$ = "FreeScatter"
else
    presetName$ = "Custom"
endif

# Clamp
if number_of_agents < 2
    number_of_agents = 2
endif
if number_of_agents > 6
    number_of_agents = 6
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== The Latent Counterpoint v1.0 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Agents:     ", number_of_agents
appendInfoLine: "Latent:     ", latent_size
appendInfoLine: "Rigidity:   ", fixed$(counterpoint_rigidity, 2)
appendInfoLine: "Speed:      ", fixed$(speed, 2)
appendInfoLine: "Duration:   ", if duration > 0 then fixed$(duration, 1) else "original" fi
appendInfoLine: "Seed:       ", seed
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency
nChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0

if duration <= 0
    duration = dur
endif

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Event Segmentation
# ===========================================================================

appendInfoLine: "[1/5] Segmenting events..."

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
# Stage 2 — Extract Features + Export
# ===========================================================================

appendInfoLine: "[2/5] Extracting features..."

Create Table with column names: "eventFeatures", nEvents,
    ... "start_time end_time label pitch_stability intensity_mean attack_slope hnr_mean"
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

appendInfoLine: "[3/5] Exporting temp files..."
selectObject: sound
Save as WAV file: tempInput$
selectObject: eventTable
Save as comma-separated file: tempCSV$

removeObject: analysisMono, pitchObj, harmObj, intObj
removeObject: intMatrix, intSound, ppObj, eventTable

# ===========================================================================
# Stage 3 — Call Python
# ===========================================================================

appendInfoLine: "[4/5] Running Python engine..."
appendInfoLine: "  (Training AE + running ", number_of_agents, "-voice counterpoint)"

# ---- Python detection ----
probeMarker$ = pluginDir$ + "temp_pyprobe.ok"

if windows
    nCandidates = 4
    candidate1$ = "python"
    candidate2$ = "py"
    candidate3$ = "py -3"
    candidate4$ = "python3"
else
    nCandidates = 3
    candidate1$ = "python3"
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = ""
endif

pythonCmd$ = ""
for iCand from 1 to nCandidates
    if iCand = 1
        tryCmd$ = candidate1$
    elsif iCand = 2
        tryCmd$ = candidate2$
    elsif iCand = 3
        tryCmd$ = candidate3$
    else
        tryCmd$ = candidate4$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    probeCode$ = "import numpy,soundfile,scipy; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", pythonCmd$
    endif
    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    deleteFile: tempInput$
    deleteFile: tempCSV$
    exitScript: "Cannot find a Python installation with the required packages." + newline$
        ... + "  pip install numpy soundfile scipy"
endif

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + string$(number_of_agents)
    ... + " " + string$(latent_size)
    ... + " " + fixed$(counterpoint_rigidity, 4)
    ... + " " + fixed$(speed, 4)
    ... + " " + fixed$(duration, 4)

if not fileReadable(tempOutput$)
    deleteFile: tempInput$
    deleteFile: tempCSV$
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    exitScript: "Python counterpoint engine failed." + newline$
        ... + "Run in terminal to see error:" + newline$
        ... + "  " + pythonCmd$ + " """ + pythonScript$ + """"
endif

# ===========================================================================
# Import Result
# ===========================================================================

appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_cp"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

# ===========================================================================
# Read Stats
# ===========================================================================

nEvStat$ = "?"
nAgentsStat$ = "?"
outDurStat$ = "?"
finalLoss$ = "?"
initialLoss$ = "?"
meanEvDur$ = "?"
totalUnique$ = "?"
warningStat$ = ""

# Per-agent stats arrays (up to 6 agents)
for iA from 0 to 5
    agProfile_'iA'$ = "?"
    agSteps_'iA'$ = "?"
    agUnique_'iA'$ = "?"
    agRepRate_'iA'$ = "?"
    agTravel_'iA'$ = "?"
    agPeriph_'iA'$ = "?"
    agTop_'iA'$ = "?"
endfor

# Unison rates (up to 15 pairs for 6 agents)
nUnisonPairs = 0
for iA from 0 to 5
    for iB from iA + 1 to 5
        unisonRate_'iA'_'iB'$ = "?"
    endfor
endfor

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_agents="
    nAgentsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEvDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "total_unique_events="
    totalUnique$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$

    for iA from 0 to number_of_agents - 1
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_profile="
        agProfile_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_steps="
        agSteps_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_unique="
        agUnique_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_rep_rate="
        agRepRate_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_avg_travel="
        agTravel_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_mean_periphery="
        agPeriph_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_top_event="
        agTop_'iA'$ = parseStatLine.result$
    endfor

    for iA from 0 to number_of_agents - 2
        for iB from iA + 1 to number_of_agents - 1
            @parseStatLine: statsText$, "unison_rate_" + string$(iA) + "_" + string$(iB) + "="
            unisonRate_'iA'_'iB'$ = parseStatLine.result$
        endfor
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
    Text: 0.5, "centre", 0.6, "half", "##The Latent Counterpoint##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | " + string$(number_of_agents) + " voices | Rigidity=" + fixed$(counterpoint_rigidity, 2)

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

    # === Output Waveform (stereo → L channel) ===
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: resultSound
    Colour: "{0.4, 0.2, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Counterpoint"
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
    Extract one channel: 1
    tmpOut = selected("Sound")
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Counterpoint spectrogram (L channel)"
    removeObject: specOut, tmpOut

    # === Agent Profiles Panel ===
    Select outer viewport: 0, 8, 5.0, 6.0
    Select inner viewport: 0.6, 7.7, 5.1, 5.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.96}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Agent Profiles:"

    # Agent colors
    agCol_0$ = "{0.2, 0.4, 0.7}"
    agCol_1$ = "{0.7, 0.3, 0.2}"
    agCol_2$ = "{0.3, 0.6, 0.3}"
    agCol_3$ = "{0.6, 0.4, 0.6}"
    agCol_4$ = "{0.7, 0.6, 0.2}"
    agCol_5$ = "{0.4, 0.6, 0.7}"

    yStep = 0.75 / max(1, number_of_agents)
    for iA from 0 to number_of_agents - 1
        yPos = 0.78 - iA * yStep
        thisCol$ = agCol_'iA'$
        Colour: thisCol$
        Font size: 6
        agLine$ = agProfile_'iA'$ + " | Steps=" + agSteps_'iA'$
            ... + " Uniq=" + agUnique_'iA'$
            ... + " Rep=" + agRepRate_'iA'$
            ... + " Travel=" + agTravel_'iA'$
        Text: 0.02, "left", yPos, "half", "Agent " + string$(iA) + ": " + agLine$
    endfor

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Unison / Counterpoint Panel ===
    Select outer viewport: 0, 8, 6.1, 6.7
    Select inner viewport: 0.6, 7.7, 6.2, 6.6

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.93, 0.93}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "Counterpoint (unison rates — lower = more independent):"

    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    unisonLine$ = ""
    for iA from 0 to number_of_agents - 2
        for iB from iA + 1 to number_of_agents - 1
            thisRate$ = unisonRate_'iA'_'iB'$
            if thisRate$ <> "?"
                unisonLine$ = unisonLine$ + string$(iA) + "↔" + string$(iB) + "=" + thisRate$ + "  "
            endif
        endfor
    endfor
    Text: 0.02, "left", 0.30, "half", unisonLine$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.9, 8.0
    Select inner viewport: 0.6, 7.7, 7.0, 7.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.68, "half", "Events: " + nEvStat$ + " | Total unique used: " + totalUnique$ + " | Mean dur: " + meanEvDur$ + " s"
    Text: 0.02, "left", 0.48, "half", "AE loss: " + initialLoss$ + " -> " + finalLoss$ + " | Latent=" + string$(latent_size) + " | Seed=" + string$(seed)
    Text: 0.02, "left", 0.28, "half", "Duration: " + fixed$(dur, 2) + "s -> " + outDurStat$ + "s | RMS: " + fixed$(rms_orig, 4) + " -> " + fixed$(rms_out, 4)

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", 0.08, "half", "Warning: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ===========================================================================
# Cleanup
# ===========================================================================

deleteFile: tempInput$
deleteFile: tempCSV$
deleteFile: tempOutput$
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif
if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

# ===========================================================================
# Summary
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_cp (stereo)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Agents:"
for iA from 0 to number_of_agents - 1
    appendInfoLine: "  ", string$(iA), ": ", agProfile_'iA'$,
        ... " | Steps=", agSteps_'iA'$,
        ... " | Unique=", agUnique_'iA'$,
        ... " | Rep=", agRepRate_'iA'$,
        ... " | Travel=", agTravel_'iA'$,
        ... " | Periphery=", agPeriph_'iA'$
endfor

appendInfoLine: ""
appendInfoLine: "Counterpoint (unison rates):"
for iA from 0 to number_of_agents - 2
    for iB from iA + 1 to number_of_agents - 1
        appendInfoLine: "  ", string$(iA), " ↔ ", string$(iB), ": ", unisonRate_'iA'_'iB'$
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s -> ", outDurStat$, " s"
appendInfoLine: "RMS: ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4)

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
