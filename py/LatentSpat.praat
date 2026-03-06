# ============================================================
# Praat AudioTools - LatentSpat.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent Spat — Agent-Based Spatialization
#
#   Extends Latent Counterpoint with physical space: each agent's
#   latent position maps to spatial coordinates via VBAP panning.
#   Latent X → azimuth (position around listener)
#   Latent Y → distance (amplitude, filtering, reverb)
#
#   When agents repel in timbre, they move to opposite sides
#   of the room. The counterpoint becomes spatial.
#
#   Spatial formats: Stereo, Quad, 5.1, Octophonic
#   Distance models: Amplitude, +LowPass, +LowPass+Reverb
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
pythonScript$ = pluginDir$ + "py/latent_spat.py"
tempInput$   = pluginDir$ + "temp_latspat_input.wav"
tempCSV$     = pluginDir$ + "temp_latspat_events.csv"
tempOutput$  = pluginDir$ + "temp_latspat_output.wav"
tempStats$   = pluginDir$ + "temp_latspat_stats.txt"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- FORM ----
form Latent Spat v1.0 — Agent-Based Spatialization
    optionmenu Preset: 1
        option Custom
        option Stereo duo
        option Quad trio
        option Surround ensemble
        option Octophonic scatter
        option Immersive drift
        option Close-mic trio
    integer Number_of_agents 3
    integer Latent_size 8
    real Counterpoint_rigidity 0.5
    real Speed 0.5
    optionmenu Spatial_format: 1
        option Stereo (2ch)
        option Quad (4ch)
        option 5.1 (6ch)
        option Octophonic (8ch)
    optionmenu Distance_model: 3
        option Amplitude only
        option Amplitude + Low-pass
        option Amplitude + Low-pass + Reverb
    real Reverb_amount 0.4
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
    spatial_format = 1
    distance_model = 2
    reverb_amount = 0.2
    presetName$ = "StereoDuo"
elsif preset = 3
    number_of_agents = 3
    latent_size = 8
    counterpoint_rigidity = 0.5
    speed = 0.5
    spatial_format = 2
    distance_model = 3
    reverb_amount = 0.4
    presetName$ = "QuadTrio"
elsif preset = 4
    number_of_agents = 4
    latent_size = 10
    counterpoint_rigidity = 0.6
    speed = 0.5
    spatial_format = 3
    distance_model = 3
    reverb_amount = 0.5
    presetName$ = "SurroundEnsemble"
elsif preset = 5
    number_of_agents = 5
    latent_size = 12
    counterpoint_rigidity = 0.8
    speed = 0.8
    spatial_format = 4
    distance_model = 3
    reverb_amount = 0.5
    presetName$ = "OctoScatter"
elsif preset = 6
    number_of_agents = 3
    latent_size = 10
    counterpoint_rigidity = 0.3
    speed = 0.3
    spatial_format = 4
    distance_model = 3
    reverb_amount = 0.7
    presetName$ = "ImmersiveDrift"
elsif preset = 7
    number_of_agents = 3
    latent_size = 8
    counterpoint_rigidity = 0.6
    speed = 0.5
    spatial_format = 2
    distance_model = 1
    reverb_amount = 0.0
    presetName$ = "CloseMicTrio"
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
if reverb_amount < 0
    reverb_amount = 0
endif
if reverb_amount > 1
    reverb_amount = 1
endif

# Map menu indices to Python integers (0-based)
spatFormatInt = spatial_format - 1
distModelInt = distance_model - 1

# Format info
if spatial_format = 1
    spatName$ = "Stereo"
    nCh = 2
    chLabel$ = "L R"
elsif spatial_format = 2
    spatName$ = "Quad"
    nCh = 4
    chLabel$ = "FL FR RL RR"
elsif spatial_format = 3
    spatName$ = "5.1"
    nCh = 6
    chLabel$ = "L R C LFE LS RS"
else
    spatName$ = "Octophonic"
    nCh = 8
    chLabel$ = "F FR R RR B RL L FL"
endif

if distance_model = 1
    distName$ = "Amplitude"
elsif distance_model = 2
    distName$ = "Amp+LowPass"
else
    distName$ = "Amp+LP+Reverb"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Latent Spat v1.0 — Agent-Based Spatialization ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Agents:     ", number_of_agents
appendInfoLine: "Latent:     ", latent_size
appendInfoLine: "Rigidity:   ", fixed$(counterpoint_rigidity, 2)
appendInfoLine: "Speed:      ", fixed$(speed, 2)
appendInfoLine: ""
appendInfoLine: "Spatial:    ", spatName$, " (", nCh, " ch)"
appendInfoLine: "Distance:   ", distName$
appendInfoLine: "Reverb:     ", fixed$(reverb_amount, 2)
appendInfoLine: "Channels:   ", chLabel$
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
appendInfoLine: "  (Training AE + ", number_of_agents, "-voice counterpoint → ", spatName$, " spatialization)"

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
    ... + " " + string$(spatFormatInt)
    ... + " " + string$(distModelInt)
    ... + " " + fixed$(reverb_amount, 4)
    ... + " " + string$(seed)

if not fileReadable(tempOutput$)
    deleteFile: tempInput$
    deleteFile: tempCSV$
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    exitScript: "Python spatialization engine failed." + newline$
        ... + "Run in terminal to see error:" + newline$
        ... + "  " + pythonCmd$ + " """ + pythonScript$ + """"
endif

# ===========================================================================
# Import Result
# ===========================================================================

appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_spat"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration
nChOut = Get number of channels

# ===========================================================================
# Read Stats
# ===========================================================================

nEvStat$ = "?"
nAgentsStat$ = "?"
nChannelsStat$ = "?"
spatFormatStat$ = "?"
distModelStat$ = "?"
reverbStat$ = "?"
outDurStat$ = "?"
finalLoss$ = "?"
initialLoss$ = "?"
meanEvDur$ = "?"
totalUnique$ = "?"
speakerLabels$ = "?"
warningStat$ = ""

for iA from 0 to 5
    agProfile_'iA'$ = "?"
    agSteps_'iA'$ = "?"
    agUnique_'iA'$ = "?"
    agRepRate_'iA'$ = "?"
    agAzRange_'iA'$ = "?"
    agAzTravel_'iA'$ = "?"
    agMeanDist_'iA'$ = "?"
    agMeanAz_'iA'$ = "?"
endfor

for iA from 0 to 5
    for iB from iA + 1 to 5
        unisonRate_'iA'_'iB'$ = "?"
        spatSep_'iA'_'iB'$ = "?"
    endfor
endfor

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_agents="
    nAgentsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_channels="
    nChannelsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "spatial_format="
    spatFormatStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "distance_model="
    distModelStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "reverb_amount="
    reverbStat$ = parseStatLine.result$
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
    @parseStatLine: statsText$, "speaker_labels="
    speakerLabels$ = parseStatLine.result$
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
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_az_range="
        agAzRange_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_az_travel="
        agAzTravel_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_mean_dist="
        agMeanDist_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_mean_az="
        agMeanAz_'iA'$ = parseStatLine.result$
    endfor

    for iA from 0 to number_of_agents - 2
        for iB from iA + 1 to number_of_agents - 1
            @parseStatLine: statsText$, "unison_rate_" + string$(iA) + "_" + string$(iB) + "="
            unisonRate_'iA'_'iB'$ = parseStatLine.result$
            @parseStatLine: statsText$, "spatial_sep_" + string$(iA) + "_" + string$(iB) + "="
            spatSep_'iA'_'iB'$ = parseStatLine.result$
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
    Text: 0.5, "centre", 0.6, "half", "##Latent Spat — Agent-Based Spatialization##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | " + spatFormatStat$ + " " + nChannelsStat$ + "ch | " + distModelStat$

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
    Axes: 0, dur, -1, 1
    for iEv from 1 to nEvents
        evBound = evS_'iEv'
        if evBound > 0 and evBound < dur
            Draw line: evBound, -0.9, evBound, 0.9
        endif
    endfor
    Text top: "no", string$(nEvents) + " events | " + fixed$(dur, 2) + " s"

    # === Output Waveform (ch 1) ===
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: resultSound
    Extract one channel: 1
    tmpCh1 = selected("Sound")
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Ch 1"
    Text bottom: "yes", "Time (s)"
    removeObject: tmpCh1

    # === Spatial Field Display (top-down circle) ===
    Select outer viewport: 0, 4, 2.5, 5.1
    Select inner viewport: 0.4, 3.8, 2.7, 4.9

    Axes: -1.5, 1.5, -1.5, 1.5

    # Draw listener circle
    Paint rectangle: "{0.97, 0.97, 0.98}", -1.5, 1.5, -1.5, 1.5
    Colour: "{0.85, 0.85, 0.90}"
    Draw circle: 0, 0, 1.0
    Colour: "{0.9, 0.9, 0.92}"
    Draw circle: 0, 0, 0.5

    # Draw listener at center
    Colour: "Black"
    Font size: 7
    Text: 0, "centre", 0, "half", "+"

    # Draw speakers
    if spatial_format = 1
        nSpk = 2
        spkAz_1 = 330
        spkAz_2 = 30
    elsif spatial_format = 2
        nSpk = 4
        spkAz_1 = 315
        spkAz_2 = 45
        spkAz_3 = 225
        spkAz_4 = 135
    elsif spatial_format = 3
        nSpk = 6
        spkAz_1 = 330
        spkAz_2 = 30
        spkAz_3 = 0
        spkAz_4 = 0
        spkAz_5 = 240
        spkAz_6 = 120
    else
        nSpk = 8
        spkAz_1 = 0
        spkAz_2 = 45
        spkAz_3 = 90
        spkAz_4 = 135
        spkAz_5 = 180
        spkAz_6 = 225
        spkAz_7 = 270
        spkAz_8 = 315
    endif

    Colour: "{0.6, 0.6, 0.6}"
    Font size: 6
    for iSpk from 1 to nSpk
        thisAz = spkAz_'iSpk'
        # Convert azimuth to x,y (0=front=up, clockwise)
        azRad = (90 - thisAz) * pi / 180
        sx = 1.2 * cos(azRad)
        sy = 1.2 * sin(azRad)
        Draw rectangle: sx - 0.06, sx + 0.06, sy - 0.06, sy + 0.06
    endfor

    # Draw agent positions (use mean azimuth and distance)
    agCol_0$ = "{0.2, 0.4, 0.7}"
    agCol_1$ = "{0.7, 0.3, 0.2}"
    agCol_2$ = "{0.3, 0.6, 0.3}"
    agCol_3$ = "{0.6, 0.4, 0.6}"
    agCol_4$ = "{0.7, 0.6, 0.2}"
    agCol_5$ = "{0.4, 0.6, 0.7}"

    agSymb_0$ = "C"
    agSymb_1$ = "F"
    agSymb_2$ = "S"
    agSymb_3$ = "C"
    agSymb_4$ = "F"
    agSymb_5$ = "S"

    Font size: 8
    for iA from 0 to number_of_agents - 1
        thisCol$ = agCol_'iA'$
        thisSymb$ = agSymb_'iA'$

        # Parse azimuth range to get midpoint
        azRangeStr$ = agAzRange_'iA'$
        azTravelStr$ = agAzTravel_'iA'$
        distStr$ = agMeanDist_'iA'$

        if distStr$ <> "?"
            agDist = number(distStr$)
        else
            agDist = 0.5
        endif

        # Use actual mean azimuth from Python spatial trajectories
        azStr$ = agMeanAz_'iA'$
        if azStr$ <> "?"
            estAz = number(azStr$)
        else
            # Fallback to profile-based estimate
            if iA mod 3 = 0
                estAz = 150
            elsif iA mod 3 = 1
                estAz = 300
            else
                estAz = 30
            endif
        endif

        azRad = (90 - estAz) * pi / 180
        r = agDist * 1.0
        ax = r * cos(azRad)
        ay = r * sin(azRad)

        Colour: thisCol$
        Draw circle: ax, ay, 0.12
        Colour: "White"
        Text: ax, "centre", ay, "half", thisSymb$
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Spatial field (top-down)"
    Text bottom: "yes", "C=Cantus  F=Florid  S=Shadow"

    # === Agent Spatial Stats ===
    Select outer viewport: 4, 8, 2.5, 5.1
    Select inner viewport: 4.2, 7.7, 2.7, 4.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.96}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.95, "half", "Agent Spatial Profiles:"

    yStep = 0.85 / max(1, number_of_agents)
    for iA from 0 to number_of_agents - 1
        yPos = 0.85 - iA * yStep
        thisCol$ = agCol_'iA'$
        Colour: thisCol$
        Font size: 6

        line1$ = agProfile_'iA'$ + " | Az range=" + agAzRange_'iA'$ + "°"
            ... + " | Travel=" + agAzTravel_'iA'$ + "°"
        line2$ = "  Dist=" + agMeanDist_'iA'$
            ... + " | Steps=" + agSteps_'iA'$
            ... + " | Uniq=" + agUnique_'iA'$

        Text: 0.02, "left", yPos, "half", "Agent " + string$(iA) + ": " + line1$
        Text: 0.02, "left", yPos - yStep * 0.4, "half", line2$
    endfor

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Spatial Separation + Unison Panel ===
    Select outer viewport: 0, 8, 5.2, 6.2
    Select inner viewport: 0.6, 7.7, 5.3, 6.1

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.93, 0.93}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "Counterpoint & Spatial Separation:"

    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"

    sepLine$ = ""
    uniLine$ = ""
    for iA from 0 to number_of_agents - 2
        for iB from iA + 1 to number_of_agents - 1
            thisSep$ = spatSep_'iA'_'iB'$
            thisUni$ = unisonRate_'iA'_'iB'$
            if thisSep$ <> "?"
                sepLine$ = sepLine$ + string$(iA) + "↔" + string$(iB) + "=" + thisSep$ + "°  "
            endif
            if thisUni$ <> "?"
                uniLine$ = uniLine$ + string$(iA) + "↔" + string$(iB) + "=" + thisUni$ + "  "
            endif
        endfor
    endfor
    Text: 0.02, "left", 0.58, "half", "Spatial: " + sepLine$
    Text: 0.02, "left", 0.22, "half", "Unison: " + uniLine$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.4, 7.9
    Select inner viewport: 0.6, 7.7, 6.5, 7.8

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.75, "half", "Format: " + spatFormatStat$ + " (" + nChannelsStat$ + "ch) | Distance: " + distModelStat$ + " | Reverb=" + reverbStat$
    Text: 0.02, "left", 0.55, "half", "Events: " + nEvStat$ + " | Unique used: " + totalUnique$ + " | Mean dur: " + meanEvDur$ + " s"
    Text: 0.02, "left", 0.35, "half", "AE loss: " + initialLoss$ + " -> " + finalLoss$ + " | Latent=" + string$(latent_size) + " | Seed=" + string$(seed)
    Text: 0.02, "left", 0.15, "half", "Duration: " + fixed$(dur, 2) + "s -> " + outDurStat$ + "s | Output channels: " + string$(nChOut)

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", -0.02, "half", "Warning: " + warningStat$
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
appendInfoLine: "Output: ", soundName$, "_spat (", nChOut, " channels)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Format: ", spatFormatStat$, " | Distance: ", distModelStat$
appendInfoLine: ""

appendInfoLine: "Agent Spatial Profiles:"
for iA from 0 to number_of_agents - 1
    appendInfoLine: "  Agent ", string$(iA), ": ", agProfile_'iA'$,
        ... " | Az range=", agAzRange_'iA'$, "°",
        ... " | Travel=", agAzTravel_'iA'$, "°",
        ... " | Dist=", agMeanDist_'iA'$,
        ... " | Steps=", agSteps_'iA'$,
        ... " | Unique=", agUnique_'iA'$
endfor

appendInfoLine: ""
appendInfoLine: "Spatial Separation (degrees):"
for iA from 0 to number_of_agents - 2
    for iB from iA + 1 to number_of_agents - 1
        appendInfoLine: "  ", string$(iA), " ↔ ", string$(iB),
            ... ": ", spatSep_'iA'_'iB'$, "°",
            ... " (unison=", unisonRate_'iA'_'iB'$, ")"
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s -> ", outDurStat$, " s"
appendInfoLine: "Channels: ", nChOut
appendInfoLine: "Speaker layout: ", speakerLabels$

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
