# ============================================================
# Praat AudioTools - PhaseSpaceComposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Stable temperature mapping, correct weight metric,
#                        representative-channel analysis, weighted projection
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phase-Space Composition (Attractor-Driven Event Montage).
#   Segments the input into acoustic events, extracts perceptual
#   feature vectors, and drives event recomposition via a
#   deterministic dynamical system (attractor) in the feature space.
#   Powered by Python (numpy, soundfile, scipy).
#
#   Attractors:
#   Hopf        — stable limit cycle (periodic morphological loops)
#   Lorenz      — bounded strange attractor (chaotic recurrence)
#   Rossler     — single-scroll chaos (smooth divergence and return)
#   LogisticMap — 1-D chaos with delay embedding (regime shifts)
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

sound      = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-SPECIFIC PYTHON DISCOVERY ----
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

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/phase_space_compose.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/phase_space_compose.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: phase_space_compose.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_phsp_input.wav"
tempEvents$  = temporaryDirectory$ + "/temp_phsp_events.csv"
tempPlan$    = temporaryDirectory$ + "/temp_phsp_plan.csv"
tempStats$   = temporaryDirectory$ + "/temp_phsp_stats.txt"
probePy$     = temporaryDirectory$ + "/temp_phsp_probe.py"
probeMarker$ = temporaryDirectory$ + "/temp_phsp_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempEventsJ$   = replace_regex$(tempEvents$, "\\", "/", 0)
tempPlanJ$     = replace_regex$(tempPlan$, "\\", "/", 0)
tempStatsJ$    = replace_regex$(tempStats$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempEvents$)
        deleteFile: tempEvents$
    endif
    if fileReadable(tempPlan$)
        deleteFile: tempPlan$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Phase-Space Composer v1.4
    comment === Attractor ===
    optionmenu Attractor_type: 2
        option LimitCycle (Hopf)
        option Lorenz
        option Rossler
        option LogisticMap
    comment === State Space ===
    optionmenu State_dims: 2
        option 2D: centroid + flatness
        option 3D: centroid + flatness + flux
        option 4D: centroid + flatness + entropy + flux
        option 5D: centroid + flatness + entropy + flux + rms
    comment === Distance Weighting ===
    optionmenu Weight_preset: 1
        option Uniform
        option Brightness focus
        option Noisiness focus
        option Energy focus (5D only)
        option Transient focus
    comment === Composition ===
    integer Num_events_output 300
    comment Tabu_length: 0 = off; higher values prevent recent-event reuse
    integer Tabu_length 12
    real Temperature 0.15
    integer Seed 1234
    comment === Dynamics ===
    real Velocity_weight 0.0
    real Coupling 0.0
    comment === Audio ===
    real Crossfade_ms 10
    real Min_event_duration_ms 30
    comment === Segmentation ===
    real Silence_threshold_dB -25
    real Min_silent_interval 0.05
    real Min_sounding_interval 0.03
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
    boolean Debug 0
endform

# ---- MAP OPTION MENUS → STRINGS ----
if attractor_type = 1
    attractorStr$ = "Hopf"
elsif attractor_type = 2
    attractorStr$ = "Lorenz"
elsif attractor_type = 3
    attractorStr$ = "Rossler"
else
    attractorStr$ = "LogisticMap"
endif

if state_dims = 1
    stateDimInt = 2
    stateDimStr$ = "2D"
elsif state_dims = 2
    stateDimInt = 3
    stateDimStr$ = "3D"
elsif state_dims = 3
    stateDimInt = 4
    stateDimStr$ = "4D"
else
    stateDimInt = 5
    stateDimStr$ = "5D"
endif

# ---- MAP WEIGHT PRESET → dim_weights string ----
if weight_preset = 1
    dimWeights$ = "1.0,1.0,1.0,1.0,1.0"
    weightName$ = "Uniform"
elsif weight_preset = 2
    dimWeights$ = "2.0,0.8,0.8,0.8,0.6"
    weightName$ = "Brightness"
elsif weight_preset = 3
    dimWeights$ = "0.6,2.0,1.5,0.8,0.6"
    weightName$ = "Noisiness"
elsif weight_preset = 4
    dimWeights$ = "0.6,0.6,0.8,1.0,2.5"
    weightName$ = "Energy"
else
    dimWeights$ = "0.8,0.8,0.8,2.5,1.0"
    weightName$ = "Transient"
endif

# dimWeights$ is always given in canonical order (centroid, flatness,
# entropy, flux, rms) regardless of State_dims — the Python engine now
# resolves it onto the active feature columns BY NAME, so presets stay
# semantically correct at every dimensionality (fixes the old bug where
# e.g. Transient's flux weight silently landed on the wrong column in 3D).

# "Energy focus" targets the rms dimension, which only exists at 5D.
# Below 5D this isn't a harmless no-op: the remaining non-rms weights in
# the preset (e.g. flux=1.0 relative to centroid/flatness=0.6 in 3D)
# still apply after renormalization, so the preset silently turns into
# an unlabelled transient/entropy-leaning preset instead of doing
# nothing. That's worse than an error, so this stops the run instead of
# just warning.
if weight_preset = 4 and stateDimInt < 5
    exitScript: "Energy focus requires the 5D state space, because RMS is not present in 2D, 3D, or 4D." + newline$ + "Set State_dims to 5D, or choose a different Weight_preset."
endif

# ---- CLAMP PARAMETERS ----
if num_events_output < 10
    num_events_output = 10
endif
if num_events_output > 2000
    num_events_output = 2000
endif
if tabu_length < 0
    tabu_length = 0
endif
if tabu_length > 500
    tabu_length = 500
endif
if temperature < 0
    temperature = 0
endif
if temperature > 1
    temperature = 1
endif
if crossfade_ms < 0
    crossfade_ms = 0
endif
if crossfade_ms > 200
    crossfade_ms = 200
endif
if velocity_weight < 0
    velocity_weight = 0
endif
if velocity_weight > 1
    velocity_weight = 1
endif
if coupling < 0
    coupling = 0
endif
if coupling > 1
    coupling = 1
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Phase-Space Composer v1.4 ==="
appendInfoLine: "Input:     ", soundName$
appendInfoLine: "Attractor: ", attractorStr$, " | State: ", stateDimStr$, " | Weights: ", weightName$
appendInfoLine: "Output:    ", num_events_output, " events | Tabu: ", tabu_length, " | Temp: ", fixed$(temperature, 3), " | Seed: ", seed
appendInfoLine: "Dynamics:  Vel.weight=", fixed$(velocity_weight, 3), " | Coupling=", fixed$(coupling, 3)
appendInfoLine: "Crossfade: ", crossfade_ms, " ms | Min event: ", min_event_duration_ms, " ms"
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Ch: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

pyCode$ = "import sys" + newline$
pyCode$ = pyCode$ + "try:" + newline$
pyCode$ = pyCode$ + "    import numpy, soundfile, scipy" + newline$
pyCode$ = pyCode$ + "    with open('" + probeMarkerJ$ + "', 'w') as f:" + newline$
pyCode$ = pyCode$ + "        f.write('ok')" + newline$
pyCode$ = pyCode$ + "except Exception as e:" + newline$
pyCode$ = pyCode$ + "    print('Missing dependencies:', e)" + newline$
writeFile: probePy$, pyCode$

probeCmd$ = pythonCmd$ + " """ + probePyJ$ + """"
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
deleteFile: probePy$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Event Segmentation
# ===========================================================================
appendInfoLine: "[2/5] Segmenting sound into events..."

# Representative-channel policy: never average stereo/multichannel channels
# for analysis, because anti-phase material can cancel and create a fictitious
# "silent" analysis signal.  Choose the whole-file strongest-RMS real channel
# and pass that exact 1-based channel number to Python, so segmentation and
# feature extraction operate on the same physical channel.
analysisChannel = 1
if nChannels > 1
    bestChannelRms = -1
    for ch from 1 to nChannels
        selectObject: sound
        Extract one channel: ch
        probeCh = selected("Sound")
        chRms = Get root-mean-square: 0, 0
        if chRms > bestChannelRms
            bestChannelRms = chRms
            analysisChannel = ch
        endif
        removeObject: probeCh
    endfor
    selectObject: sound
    Extract one channel: analysisChannel
    analysisMono = selected("Sound")
else
    Copy: "phsp_analysisMono"
    analysisMono = selected("Sound")
endif

appendInfoLine: "  Analysis channel: ", analysisChannel, " (strongest RMS real channel)"

selectObject: analysisMono
To Intensity: 100, 0.01, "yes"
intObj = selected("Intensity")

selectObject: intObj
To TextGrid (silences): silence_threshold_dB, min_silent_interval, min_sounding_interval, "silent", "sounding"
tgObj = selected("TextGrid")

nEvents = 0
selectObject: tgObj
nIntervals = Get number of intervals: 1

for i from 1 to nIntervals
    selectObject: tgObj
    lab$ = Get label of interval: 1, i
    if lab$ = "sounding"
        tS = Get start time of interval: 1, i
        tE = Get end time of interval: 1, i
        evDurSec = tE - tS
        if evDurSec * 1000 >= min_event_duration_ms
            nEvents += 1
            evStart[nEvents] = tS
            evEnd[nEvents]   = tE
            evDur[nEvents]   = evDurSec
        endif
    endif
endfor

appendInfoLine: "  Detected ", nEvents, " valid events"

if nEvents < 3
    removeObject: analysisMono, intObj, tgObj
    @cleanUpTempFiles
    exitScript: "Too few events detected (" + string$(nEvents) + ")." + newline$ + "Try: lower Silence_threshold_dB, reduce Min_event_duration_ms, or reduce Min_sounding_interval."
endif

removeObject: analysisMono, intObj, tgObj

# ===========================================================================
# Stage 3 — Export WAV + Events CSV
# ===========================================================================
appendInfoLine: "[3/5] Exporting temp files..."

selectObject: sound
Save as WAV file: tempInput$

writeFileLine: tempEvents$, "index,start_s,end_s,duration_s"
for i from 1 to nEvents
    appendFileLine: tempEvents$, string$(i) + "," + fixed$(evStart[i], 6) + "," + fixed$(evEnd[i], 6) + "," + fixed$(evDur[i], 6)
endfor

appendInfoLine: "  WAV + ", nEvents, "-row events CSV written"

# ===========================================================================
# Stage 4 — Python Engine
# ===========================================================================
appendInfoLine: "[4/5] Running Python phase-space engine..."

debugFlag$ = ""
if debug
    debugFlag$ = " --debug"
endif

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " --wav """    + tempInputJ$  + """"
    ... + " --events """ + tempEventsJ$ + """"
    ... + " --out_plan """  + tempPlanJ$  + """"
    ... + " --out_stats """ + tempStatsJ$ + """"
    ... + " --attractor "   + attractorStr$
    ... + " --state_dims "  + string$(stateDimInt)
    ... + " --n_output "    + string$(num_events_output)
    ... + " --tabu "        + string$(tabu_length)
    ... + " --temperature " + fixed$(temperature, 4)
    ... + " --seed "        + string$(seed)
    ... + " --min_event_dur_ms " + fixed$(min_event_duration_ms, 1)
    ... + " --analysis_channel " + string$(analysisChannel)
    ... + " --dim_weights """ + dimWeights$ + """"
    ... + " --weight_preset_name """ + weightName$ + """"
    ... + " --velocity_weight " + fixed$(velocity_weight, 4)
    ... + " --coupling "        + fixed$(coupling, 4)
    ... + debugFlag$

runSystem_nocheck: pythonCall$

if not fileReadable(tempPlan$)
    @cleanUpTempFiles
    exitScript: "Python phase-space engine failed — plan.csv not written." + newline$ + "Check terminal for error details."
endif

# ===========================================================================
# Stage 5 — Reconstruct Composition from Plan
# ===========================================================================
appendInfoLine: "[5/5] Reconstructing composition..."

planText$ = readFile$(tempPlan$)
nlPos = index(planText$, newline$)
remaining$ = mid$(planText$, nlPos + 1, length(planText$))

nPlanSteps = 0
maxPlanSteps = num_events_output + 20

while length(remaining$) > 1 and nPlanSteps < maxPlanSteps
    nlPos = index(remaining$, newline$)
    if nlPos > 0
        line$ = left$(remaining$, nlPos - 1)
        remaining$ = mid$(remaining$, nlPos + 1, length(remaining$))
    else
        line$ = remaining$
        remaining$ = ""
    endif

    line$ = replace$(line$, " ", "", 0)

    if length(line$) > 2
        c1 = index(line$, ",")
        if c1 > 0
            rest$ = mid$(line$, c1 + 1, length(line$))
            c2 = index(rest$, ",")
            if c2 > 0
                evIdxStr$ = left$(rest$, c2 - 1)
                gainStr$  = mid$(rest$, c2 + 1, length(rest$))
            else
                evIdxStr$ = rest$
                gainStr$  = "1.0"
            endif
            rawIdx = number(evIdxStr$)
            if rawIdx >= 0 and rawIdx < nEvents
                nPlanSteps += 1
                planEvIdx[nPlanSteps] = rawIdx + 1
                planGain[nPlanSteps]  = number(gainStr$)
            endif
        endif
    endif
endwhile

appendInfoLine: "  Plan loaded: ", nPlanSteps, " steps"

if nPlanSteps < 1
    @cleanUpTempFiles
    exitScript: "Plan CSV was empty or unparseable."
endif

minSegDur = evDur[planEvIdx[1]]

for step from 1 to nPlanSteps
    evIdx   = planEvIdx[step]
    tS      = evStart[evIdx]
    tE      = evEnd[evIdx]
    segDur  = evDur[evIdx]
    if segDur < minSegDur
        minSegDur = segDur
    endif

    selectObject: sound
    Extract part: tS, tE, "rectangular", 1.0, "no"
    Rename: "phsp_step_" + string$(step)
    curSnd  = selected("Sound")

    gVal = planGain[step]
    if gVal <> 1.0 and gVal > 0.0
        selectObject: curSnd
        Formula: "self * " + fixed$(gVal, 5)
    endif
endfor

# ---- TRUE CROSSFADE ----
# Previously this applied a fade-in/fade-out to each segment's own edges
# and then used plain Concatenate, which abuts segments with no overlap
# at all — that's an edge fade, not a crossfade. "Concatenate with
# overlap" actually overlaps and blends adjacent segments by xfEff
# seconds, which is what "Crossfade_ms" has always claimed to do.
# The overlap is clamped so it can never exceed a fraction of the
# shortest segment in the plan (a segment can't crossfade with itself).
xfEff = crossfade_ms / 1000.0
maxOverlap = minSegDur * 0.45
if xfEff > maxOverlap
    xfEff = maxOverlap
endif
if xfEff < 0.001
    xfEff = 0
endif

selectObject: "Sound phsp_step_1"
for step from 2 to nPlanSteps
    plusObject: "Sound phsp_step_" + string$(step)
endfor
if xfEff > 0
    Concatenate with overlap: xfEff
else
    Concatenate
endif
Rename: soundName$ + "_phaseSpace_" + attractorStr$
resultSound = selected("Sound")

for step from 1 to nPlanSteps
    removeObject: "Sound phsp_step_" + string$(step)
endfor

selectObject: resultSound
rms_out   = Get root-mean-square: 0, 0
durOut    = Get total duration
outChans  = Get number of channels

appendInfoLine: "  Output: ", fixed$(durOut, 2), " s | ", outChans, " ch | RMS=", fixed$(rms_out, 4)

# ===========================================================================
# Read Stats File
# ===========================================================================

attractorStat$      = "?"
stateDimsStat$      = "?"
nSourceEvStat$      = "?"
nOutputEvStat$      = "?"
uniqueUsedStat$     = "?"
repRateStat$        = "?"
trajSpeedStat$      = "?"
tabuStat$           = "?"
tempStatVal$        = "?"
weightPresetStat$   = "?"
velocityWeightStat$ = "?"
couplingStat$       = "?"
meanMapDistStat$    = "?"
meanVelAlignStat$   = "?"

nPEvPts = 0
nPTrajPts = 0
nPSelPts = 0
projAxis0$ = "dim0"
projAxis1$ = "dim1"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "attractor="
    attractorStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "state_dims="
    stateDimsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_source_events="
    nSourceEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_output_events="
    nOutputEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "unique_events_used="
    uniqueUsedStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "repetition_rate="
    repRateStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_trajectory_speed="
    trajSpeedStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "tabu_length="
    tabuStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "temperature="
    tempStatVal$ = parseStatLine.result$
    @parseStatLine: statsText$, "weight_preset="
    weightPresetStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "velocity_weight="
    velocityWeightStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "coupling="
    couplingStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_mapping_distance="
    meanMapDistStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_velocity_alignment="
    meanVelAlignStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "proj_axis0="
    projAxis0$ = parseStatLine.result$
    @parseStatLine: statsText$, "proj_axis1="
    projAxis1$ = parseStatLine.result$

    @parseStatLine: statsText$, "n_ev_pts="
    nPEP$ = parseStatLine.result$
    if nPEP$ <> "?"
        nPEvPts = number(nPEP$)
    endif
    if nPEvPts > 200
        nPEvPts = 200
    endif
    for iEP from 0 to nPEvPts - 1
        @parseStatLine: statsText$, "pev_" + string$(iEP) + "="
        epRaw$ = parseStatLine.result$
        pep_'iEP'_x = 0
        pep_'iEP'_y = 0
        if epRaw$ <> "?"
            comma = index(epRaw$, ",")
            if comma > 0
                pep_'iEP'_x = number(left$(epRaw$, comma - 1))
                pep_'iEP'_y = number(mid$(epRaw$, comma + 1, length(epRaw$) - comma))
            endif
        endif
    endfor

    @parseStatLine: statsText$, "n_traj_pts="
    nPTP$ = parseStatLine.result$
    if nPTP$ <> "?"
        nPTrajPts = number(nPTP$)
    endif
    if nPTrajPts > 200
        nPTrajPts = 200
    endif
    for iTP from 0 to nPTrajPts - 1
        @parseStatLine: statsText$, "ptr_" + string$(iTP) + "="
        tpRaw$ = parseStatLine.result$
        ptp_'iTP'_x = 0
        ptp_'iTP'_y = 0
        if tpRaw$ <> "?"
            comma = index(tpRaw$, ",")
            if comma > 0
                ptp_'iTP'_x = number(left$(tpRaw$, comma - 1))
                ptp_'iTP'_y = number(mid$(tpRaw$, comma + 1, length(tpRaw$) - comma))
            endif
        endif
    endfor

    # Selected-event path: the actual sequence "trajectory point ->
    # selected event -> next selected event", in plan order (not sorted
    # by feature value). This is what makes the controller visible.
    @parseStatLine: statsText$, "n_sel_pts="
    nSP$ = parseStatLine.result$
    if nSP$ <> "?"
        nPSelPts = number(nSP$)
    endif
    if nPSelPts > 200
        nPSelPts = 200
    endif
    for iSP from 0 to nPSelPts - 1
        @parseStatLine: statsText$, "psel_" + string$(iSP) + "="
        spRaw$ = parseStatLine.result$
        psel_'iSP'_x = 0
        psel_'iSP'_y = 0
        if spRaw$ <> "?"
            comma = index(spRaw$, ",")
            if comma > 0
                psel_'iSP'_x = number(left$(spRaw$, comma - 1))
                psel_'iSP'_y = number(mid$(spRaw$, comma + 1, length(spRaw$) - comma))
            endif
        endif
    endfor
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Phase-Space Composition##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.18, "half", soundName$ + " | " + attractorStr$ + " | " + stateDimStr$ + " | W=" + weightName$ + " | Vel=" + fixed$(velocity_weight, 2) + " | Cpl=" + fixed$(coupling, 2) + " | T=" + fixed$(temperature, 2) + " | Seed=" + string$(seed)

    # === Input Waveform + Event Boundaries ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.65, 1.45
    selectObject: sound
    if nChannels > 1
        Extract one channel: analysisChannel
        tmpOrigWav = selected("Sound")
    else
        Copy: "tmpOrigWav"
        tmpOrigWav = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -1, 1, "no", "Curve"
    removeObject: tmpOrigWav

    Colour: "{0.8, 0.25, 0.25}"
    Line width: 1
    Axes: 0, dur, -1, 1
    for iEv from 1 to nEvents
        bS = evStart[iEv]
        if bS > 0
            Draw line: bS, -0.88, bS, 0.88
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.6, 7.7, 0.65, 1.45
    Axes: 0, dur, -1, 1
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", string$(nEvents) + " events  | " + fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: resultSound
    if outChans > 1
        visOutChannel = analysisChannel
        if visOutChannel > outChans
            visOutChannel = 1
        endif
        Extract one channel: visOutChannel
        tmpOutWav = selected("Sound")
        Colour: "{0.2, 0.5, 0.75}"
        Draw: 0, 0, -1, 1, "no", "Curve"
        removeObject: tmpOutWav
    else
        selectObject: resultSound
        Colour: "{0.2, 0.5, 0.75}"
        Draw: 0, 0, -1, 1, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    Axes: 0, durOut, -1, 1
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # === Input Spectrogram ===
    Select outer viewport: 0, 8, 2.5, 3.65
    Select inner viewport: 0.6, 7.7, 2.55, 3.60
    selectObject: sound
    if nChannels > 1
        Extract one channel: analysisChannel
        tmpOrigSpec = selected("Sound")
    else
        Copy: "tmpOrigSpec"
        tmpOrigSpec = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.6, 7.7, 2.55, 3.60
    Axes: 0, dur, 0, 5000
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrigSpec

    # === Output Spectrogram ===
    Select outer viewport: 0, 8, 3.65, 4.8
    Select inner viewport: 0.6, 7.7, 3.70, 4.75
    selectObject: resultSound
    if outChans > 1
        visOutChannel = analysisChannel
        if visOutChannel > outChans
            visOutChannel = 1
        endif
        Extract one channel: visOutChannel
        tmpOutSpec = selected("Sound")
    else
        Copy: "tmpOutSpec"
        tmpOutSpec = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.6, 7.7, 3.70, 4.75
    Axes: 0, durOut, 0, 5000
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram (" + attractorStr$ + ")"
    removeObject: specOut, tmpOutSpec

    # === Phase-Space Attractor Trajectory ===
    Select outer viewport: 0, 8, 4.85, 6.25
    Select inner viewport: 0.6, 7.7, 4.90, 6.20

    if nPTrajPts > 1 or nPEvPts > 0
        axMinX = 0
        axMaxX = 1
        axMinY = 0
        axMaxY = 1
        gotBounds = 0
        for iB from 0 to nPEvPts - 1
            bx = pep_'iB'_x
            by = pep_'iB'_y
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
        for iB from 0 to nPTrajPts - 1
            bx = ptp_'iB'_x
            by = ptp_'iB'_y
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
        for iB from 0 to nPSelPts - 1
            bx = psel_'iB'_x
            by = psel_'iB'_y
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
        axMinX = axMinX - rangeX * 0.08
        axMaxX = axMaxX + rangeX * 0.08
        axMinY = axMinY - rangeY * 0.08
        axMaxY = axMaxY + rangeY * 0.08

        Axes: axMinX, axMaxX, axMinY, axMaxY
        Paint rectangle: "{0.97, 0.97, 0.99}", axMinX, axMaxX, axMinY, axMaxY

        for iEP from 0 to nPEvPts - 1
            Paint circle (mm): "{0.75, 0.75, 0.75}", pep_'iEP'_x, pep_'iEP'_y, 1.2
        endfor

        Select inner viewport: 0.6, 7.7, 4.90, 6.20
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Colour: "{0.25, 0.45, 0.75}"
        Line width: 1.5
        for iTP from 1 to nPTrajPts - 1
            iPrev = iTP - 1
            Draw line: ptp_'iPrev'_x, ptp_'iPrev'_y, ptp_'iTP'_x, ptp_'iTP'_y
        endfor
        Line width: 1

        if nPTrajPts > 0
            Paint circle (mm): "{0.2, 0.7, 0.3}", ptp_0_x, ptp_0_y, 2.0
            iLast = nPTrajPts - 1
            Paint circle (mm): "{0.8, 0.2, 0.2}", ptp_'iLast'_x, ptp_'iLast'_y, 2.0
        endif

        Select inner viewport: 0.6, 7.7, 4.90, 6.20
        Axes: axMinX, axMaxX, axMinY, axMaxY

        # === Composed path: trajectory point -> selected event -> next selected event ===
        # This is the sequence actually heard, in plan order — distinct from the
        # attractor curve above (which is where the dynamics WANT to go) and the
        # grey dots (which are just the available corpus). Drawing it is what makes
        # the "compositional controller" claim visible rather than asserted.
        if nPSelPts > 1
            Colour: "{0.95, 0.55, 0.05}"
            Line width: 1.3
            for iSPL from 1 to nPSelPts - 1
                iSPrev = iSPL - 1
                Draw line: psel_'iSPrev'_x, psel_'iSPrev'_y, psel_'iSPL'_x, psel_'iSPL'_y
            endfor
            Line width: 1
            Paint circle (mm): "{0.95, 0.75, 0.15}", psel_0_x, psel_0_y, 1.5
            iSPLast = nPSelPts - 1
            Paint circle (mm): "{0.6, 0.25, 0.6}", psel_'iSPLast'_x, psel_'iSPLast'_y, 1.5
        endif

        Select inner viewport: 0.6, 7.7, 4.90, 6.20
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.6, 7.7, 4.90, 6.20
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Font size: 6
        Text left: "yes", projAxis1$
        Text bottom: "yes", projAxis0$
        Text top: "no", attractorStr$ + " (" + stateDimStr$ + ") — weighted projection: " + projAxis0$ + " / " + projAxis1$ + " | grey=corpus blue=attractor ##orange=composed path##"
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
    Select outer viewport: 0, 8, 6.35, 7.85
    Select inner viewport: 0.6, 7.7, 6.40, 7.80

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "Summary:"

    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.73, "half", attractorStat$ + " " + stateDimsStat$ + "D | Events=" + nSourceEvStat$ + "->" + string$(nPlanSteps) + " | Uniq=" + uniqueUsedStat$ + " Rep=" + repRateStat$ + " | Speed=" + trajSpeedStat$
    Text: 0.02, "left", 0.53, "half", "Vel=" + velocityWeightStat$ + " Cpl=" + couplingStat$ + " W=" + weightPresetStat$ + " | Tabu=" + tabuStat$ + " T=" + tempStatVal$ + " | MapDist=" + meanMapDistStat$
    Text: 0.02, "left", 0.33, "half", "RMS: " + fixed$(rms_orig, 4) + "->" + fixed$(rms_out, 4) + " | " + fixed$(dur, 2) + "s->" + fixed$(durOut, 2) + "s | Ch=" + string$(analysisChannel) + " | Xfade=" + fixed$(xfEff * 1000, 1) + "ms | Seed=" + string$(seed)

    Colour: "{0.35, 0.35, 0.35}"
    if attractor_type = 1
        attDesc$ = "Hopf: limit cycle — repeating morphological loops"
    elsif attractor_type = 2
        attDesc$ = "Lorenz: strange attractor — chaotic recurrence"
    elsif attractor_type = 3
        attDesc$ = "Rössler: single-scroll — spiral divergence + return"
    else
        attDesc$ = "Logistic: 1-D chaos — regime shifts + intermittency"
    endif
    Text: 0.02, "left", 0.13, "half", attDesc$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"

else
    appendInfoLine: "Visualization skipped."
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
appendInfoLine: "Output:  ", soundName$, "_phaseSpace_", attractorStr$
appendInfoLine: ""
appendInfoLine: "Attractor:        ", attractorStat$
appendInfoLine: "Analysis channel: ", analysisChannel
appendInfoLine: "State dims:       ", stateDimsStat$, "D"
appendInfoLine: "Source events:    ", nSourceEvStat$
appendInfoLine: "Output events:    ", nOutputEvStat$
appendInfoLine: "Unique used:      ", uniqueUsedStat$, " / ", nSourceEvStat$
appendInfoLine: "Repetition rate:  ", repRateStat$
appendInfoLine: "Traj. speed:      ", trajSpeedStat$
appendInfoLine: ""
appendInfoLine: "RMS original:  ", fixed$(rms_orig, 6)
appendInfoLine: "RMS output:    ", fixed$(rms_out,  6)
appendInfoLine: "Duration:      ", fixed$(dur, 2), " s  →  ", fixed$(durOut, 2), " s"

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