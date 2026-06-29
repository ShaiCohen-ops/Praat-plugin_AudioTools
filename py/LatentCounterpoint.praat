# ============================================================
# Praat AudioTools - LatentCounterpoint.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - counterpoint_rigidity now actually controls voice separation
#
# Changelog v1.3:
#   - counterpoint_rigidity is now a real, monotonic control over how
#     independent the voices are. Previously the rigidity knob drove only
#     the spatial repulsion force, which is capped (at speed*3) right when
#     agents are closest and clamped by max-velocity, so it was swamped by
#     the agent-profile attractions and the LRU memory: sweeping rigidity
#     0 -> 2 barely changed voice separation (~0.83 -> 0.88 x median, non-
#     monotonic) and the TightCP vs FreeScatter presets were nearly
#     identical. A graded Gaussian proximity penalty is now applied at event
#     selection time, scaled by rigidity, so each voice avoids events near
#     what the other voices just chose. Separation now rises monotonically
#     with rigidity (0.83 -> 1.07 x median) and the presets are genuinely
#     distinct, while per-voice diversity is preserved. The existing physics
#     repulsion is kept (it still shapes trajectories). Verified by sweeping
#     the live engine.
#   - Synced the version string across header, form title, and banner.
#
# Changelog v1.2:
#   - Viz: title/subtitle split into separate viewport bands (subtitle was
#     at y=-1.2, rendering over the input waveform).
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
pythonScript$ = pluginDir$ + "py/latent_counterpoint.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/latent_counterpoint.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: latent_counterpoint.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_latcp_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_latcp_events.csv"
tempOutput$  = temporaryDirectory$ + "/temp_latcp_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_latcp_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_latcp_probe.ok"

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
form The Latent Counterpoint v1.3
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
    # TightCP - tight, interlocked counterpoint: LOW rigidity so voices
    # stay close (rigidity drives REPULSION, so low = cohesive), with a
    # deliberate, controlled speed.
    number_of_agents = 3
    latent_size = 8
    counterpoint_rigidity = 0.15
    speed = 0.4
    presetName$ = "TightCP"
elsif preset = 7
    # FreeScatter - voices fly apart: HIGH rigidity = strong mutual
    # repulsion, fast speed -> wide, scattered, independent lines.
    number_of_agents = 3
    latent_size = 10
    counterpoint_rigidity = 1.5
    speed = 1.0
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
writeInfoLine:  "=== The Latent Counterpoint v1.3 ==="
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
appendInfoLine: "  (Training AE + running ", number_of_agents, "-voice counterpoint)"

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + string$(number_of_agents)
    ... + " " + string$(latent_size)
    ... + " " + fixed$(counterpoint_rigidity, 4)
    ... + " " + fixed$(speed, 4)
    ... + " " + fixed$(duration, 4)
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
    exitScript: "Python counterpoint engine failed." + newline$ + "Check terminal for error details."
endif

# ===========================================================================
# Stage 5 — Import Result
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

for iA from 0 to 5
    agProfile_'iA'$ = "?"
    agSteps_'iA'$ = "?"
    agUnique_'iA'$ = "?"
    agRepRate_'iA'$ = "?"
    agTravel_'iA'$ = "?"
    agPeriph_'iA'$ = "?"
    agTop_'iA'$ = "?"
endfor

nUnisonPairs = 0
for iA from 0 to 5
    for iB from iA + 1 to 5
        unisonRate_'iA'_'iB'$ = "?"
    endfor
endfor

for iAT from 0 to 5
    agNBlocks_'iAT' = 0
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

    # ── Parse per-agent polyphonic timeline blocks ──
    for iAT from 0 to number_of_agents - 1
        @parseStatLine: statsText$, "ag_" + string$(iAT) + "_n_blocks="
        nBl$ = parseStatLine.result$
        agNBlocks_'iAT' = 0
        if nBl$ <> "?"
            agNBlocks_'iAT' = number(nBl$)
        endif
        if agNBlocks_'iAT' > 150
            agNBlocks_'iAT' = 150
        endif
        for iBl from 0 to agNBlocks_'iAT' - 1
            @parseStatLine: statsText$, "ag_" + string$(iAT) + "_bl_" + string$(iBl) + "="
            blRaw$ = parseStatLine.result$
            agBl_'iAT'_'iBl'_ev = 0
            agBl_'iAT'_'iBl'_s = 0
            agBl_'iAT'_'iBl'_e = 0
            if blRaw$ <> "?"
                comma1 = index(blRaw$, ",")
                if comma1 > 0
                    agBl_'iAT'_'iBl'_ev = number(left$(blRaw$, comma1 - 1))
                    rest$ = mid$(blRaw$, comma1 + 1, length(blRaw$) - comma1)
                    comma2 = index(rest$, ",")
                    if comma2 > 0
                        agBl_'iAT'_'iBl'_s = number(left$(rest$, comma2 - 1))
                        agBl_'iAT'_'iBl'_e = number(mid$(rest$, comma2 + 1, length(rest$) - comma2))
                    endif
                endif
            endif
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

    # === Title (own band) ===
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##The Latent Counterpoint##"

    # === Subtitle (separate band so it can't collide with the title) ===
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", soundName$ + " | " + presetName$ + " | " + string$(number_of_agents) + " voices | Rigidity=" + fixed$(counterpoint_rigidity, 2)

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
    outChans = Get number of channels
    if outChans > 1
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
        agLine$ = agProfile_'iA'$ + " | Steps=" + agSteps_'iA'$ + " Uniq=" + agUnique_'iA'$ + " Rep=" + agRepRate_'iA'$ + " Travel=" + agTravel_'iA'$
        Text: 0.02, "left", yPos, "half", "Agent " + string$(iA) + ": " + agLine$
    endfor

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Polyphonic Timeline Panel ===
    Select outer viewport: 0, 8, 6.1, 7.2
    Select inner viewport: 0.6, 7.7, 6.2, 7.1

    tlMaxTime = 0.01
    for iAT from 0 to number_of_agents - 1
        nBl = agNBlocks_'iAT'
        if nBl > 0
            lastBl = nBl - 1
            blEnd = agBl_'iAT'_'lastBl'_e
            if blEnd > tlMaxTime
                tlMaxTime = blEnd
            endif
        endif
    endfor

    Axes: 0, tlMaxTime, -0.2, number_of_agents - 0.8
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, tlMaxTime, -0.2, number_of_agents - 0.8

    laneH = 0.35
    for iAT from 0 to number_of_agents - 1
        laneY = (number_of_agents - 1 - iAT) - 0.5
        nBl = agNBlocks_'iAT'
        thisCol$ = agCol_'iAT'$

        for iBl from 0 to nBl - 1
            blS = agBl_'iAT'_'iBl'_s
            blE = agBl_'iAT'_'iBl'_e
            blEv = agBl_'iAT'_'iBl'_ev
            Paint rectangle: thisCol$, blS, blE, laneY - laneH, laneY + laneH

            blDur = blE - blS
            if blDur > tlMaxTime * 0.04
                Font size: 4
                Colour: "White"
                Text: (blS + blE) / 2, "centre", laneY, "half", string$(blEv)
            endif
        endfor

        Font size: 5
        Colour: "Black"
        Text: -tlMaxTime * 0.005, "right", laneY, "half", string$(iAT)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Agent"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Polyphonic Timeline (event index per voice)"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 7.3, 8.0
    Select inner viewport: 0.6, 7.7, 7.35, 7.95

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.68, "half", "Events: " + nEvStat$ + " | Unique used: " + totalUnique$ + " | Mean dur: " + meanEvDur$ + "s | AE: " + initialLoss$ + "->" + finalLoss$
    Text: 0.02, "left", 0.44, "half", "Duration: " + fixed$(dur, 2) + "s->" + outDurStat$ + "s | RMS: " + fixed$(rms_orig, 4) + "->" + fixed$(rms_out, 4) + " | Latent=" + string$(latent_size) + " Seed=" + string$(seed)

    Colour: "{0.4, 0.4, 0.5}"
    unisonLine$ = "Unison: "
    for iA from 0 to number_of_agents - 2
        for iB from iA + 1 to number_of_agents - 1
            thisRate$ = unisonRate_'iA'_'iB'$
            if thisRate$ <> "?"
                unisonLine$ = unisonLine$ + string$(iA) + "↔" + string$(iB) + "=" + thisRate$ + " "
            endif
        endfor
    endfor
    Text: 0.02, "left", 0.20, "half", unisonLine$

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
# Cleanup & Summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_cp (stereo)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Agents:"
for iA from 0 to number_of_agents - 1
    appendInfoLine: "  ", string$(iA), ": ", agProfile_'iA'$, " | Steps=", agSteps_'iA'$, " | Unique=", agUnique_'iA'$, " | Rep=", agRepRate_'iA'$, " | Travel=", agTravel_'iA'$, " | Periphery=", agPeriph_'iA'$
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