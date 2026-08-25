# ============================================================
# Praat AudioTools - PhaseSpaceComposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.7 (2026) - Rebuilt figure: 2:1 phase-space panel with clustered
#                        event cloud, arrowed attractor path, plan overlay,
#                        legend + callouts; plan-timeline panel replacing both
#                        spectrograms; layout + label-collision fixes
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
    # The attractor curve is the one element that genuinely needs
    # resolution: at 200 points a Lorenz spiral renders as a polygon.
    # 800 segments cost ~0.3 s in the Picture window.
    if nPTrajPts > 800
        nPTrajPts = 800
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
#
# Canvas: 8.0 x 10.50 in.  All panels share the 0.60 / 7.70 horizontal grid.
#
# Panel stack:
#   Original waveform + event boundaries      source time (what was segmented)
#   Output waveform                       \   output time
#   Plan timeline                         /   (what came out, and WHEN each
#                                              source event is used)
#   Phase-space mapping                       (WHERE in feature space it goes)
#   Summary
#
# The output/timeline pair shares one x axis: ticks on both panels, numbers
# only on the lower one.
#
# Both spectrograms were dropped (v1.6 / v1.7).  The output one gave ~7 px per
# event at 300 plan steps — texture, not structure — on a time axis 3-4x
# compressed relative to the panel above it.  The original one was legible but
# not load-bearing: the waveform above it already shows the segmentation and
# the phase-space scatter shows the spectral spread in the coordinates the
# algorithm actually uses.  The plan timeline replaces them and carries what
# the figure was missing: selection order, dwell and repetition.
###############################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    canvasH = 9.22

    Erase all
    Select outer viewport: 0, 8, 0, canvasH

    # =================================================================
    # Cluster the projected event cloud ONCE, up front, so the plan
    # timeline and the phase-space panel can share one colour code.
    #
    # Plain k-means over the same 2-D weighted projection that gets
    # plotted, with deterministic farthest-point seeding so a given run
    # always produces the same colouring.  It is a reading aid for the
    # scatter, not a claim about structure in the full state space.
    # =================================================================
    kClust = 1
    if nPEvPts >= 6
        kClust = 2
    endif
    if nPEvPts >= 15
        kClust = 3
    endif

    if nPEvPts > 0
        cmX = 0
        cmY = 0
        for iK from 0 to nPEvPts - 1
            cmX += pep_'iK'_x
            cmY += pep_'iK'_y
        endfor
        cmX /= nPEvPts
        cmY /= nPEvPts

        bestD = -1
        bestI = 0
        for iK from 0 to nPEvPts - 1
            ddK = (pep_'iK'_x - cmX)^2 + (pep_'iK'_y - cmY)^2
            if bestD < 0 or ddK < bestD
                bestD = ddK
                bestI = iK
            endif
        endfor
        cenX[1] = pep_'bestI'_x
        cenY[1] = pep_'bestI'_y

        for kSeed from 2 to kClust
            bestD = -1
            bestI = 0
            for iK from 0 to nPEvPts - 1
                nearD = -1
                for jK from 1 to kSeed - 1
                    ddK = (pep_'iK'_x - cenX[jK])^2 + (pep_'iK'_y - cenY[jK])^2
                    if nearD < 0 or ddK < nearD
                        nearD = ddK
                    endif
                endfor
                if nearD > bestD
                    bestD = nearD
                    bestI = iK
                endif
            endfor
            cenX[kSeed] = pep_'bestI'_x
            cenY[kSeed] = pep_'bestI'_y
        endfor

        for iterK from 1 to 20
            for kK from 1 to kClust
                sumKX[kK] = 0
                sumKY[kK] = 0
                cntK[kK]  = 0
            endfor
            for iK from 0 to nPEvPts - 1
                nearD = -1
                nearK = 1
                for kK from 1 to kClust
                    ddK = (pep_'iK'_x - cenX[kK])^2 + (pep_'iK'_y - cenY[kK])^2
                    if nearD < 0 or ddK < nearD
                        nearD = ddK
                        nearK = kK
                    endif
                endfor
                evClust[iK + 1] = nearK
                sumKX[nearK] += pep_'iK'_x
                sumKY[nearK] += pep_'iK'_y
                cntK[nearK]  += 1
            endfor
            for kK from 1 to kClust
                if cntK[kK] > 0
                    cenX[kK] = sumKX[kK] / cntK[kK]
                    cenY[kK] = sumKY[kK] / cntK[kK]
                endif
            endfor
        endfor
    endif

    # The output waveform and the plan timeline share one x axis.  Ticks are
    # drawn on both but NUMBERED only on the lower one — flush stacked panels
    # that each number a shared axis collide three ways (upper numbers, lower
    # caption, lower top-left tick label).
    @niceTick: dur
    tickIn = niceTick.t
    @niceTick: durOut
    tickOut = niceTick.t

    clusCol1$ = "{0.16, 0.44, 0.86}"
    clusCol2$ = "{0.09, 0.68, 0.57}"
    clusCol3$ = "{0.94, 0.53, 0.13}"
    trajCol$  = "{0.22, 0.26, 0.31}"
    planCol$  = "{0.46, 0.20, 0.86}"

    # === Title =======================================================
    # A title strip must use Select INNER viewport: Axes maps to the
    # inner viewport, so an outer-viewport strip is silently inset by the
    # standard margins and the two lines collapse onto each other.
    Font size: 12
    Select inner viewport: 0.6, 7.7, 0.04, 0.38
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.80, "half", "##Phase-Space Composition##"
    Font size: 8
    Select inner viewport: 0.6, 7.7, 0.04, 0.38
    Axes: 0, 1, 0, 1
    Colour: "{0.40, 0.40, 0.50}"
    Text: 0.5, "centre", 0.18, "half", soundName$ + " | " + attractorStr$ + " | " + stateDimStr$ + " | W=" + weightName$ + " | Vel=" + fixed$(velocity_weight, 2) + " | Cpl=" + fixed$(coupling, 2) + " | T=" + fixed$(temperature, 2) + " | Seed=" + string$(seed)

    # === Input Waveform + Event Boundaries ===========================
    Font size: 7
    Select outer viewport: 0, 8, 0.46, 1.26
    Select inner viewport: 0.6, 7.7, 0.56, 1.16
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

    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.56, 1.16
    Axes: 0, dur, -1, 1
    Colour: "{0.80, 0.25, 0.25}"
    Line width: 1
    for iEv from 1 to nEvents
        bS = evStart[iEv]
        if bS > 0
            Draw line: bS, -0.88, bS, 0.88
        endif
    endfor
    Colour: "Black"
    Draw inner box

    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.56, 1.16
    Axes: 0, dur, -1, 1
    Marks bottom every: 1, tickIn, "yes", "yes", "no"
    Text bottom: "yes", "Source time (s)"

    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.56, 1.16
    Axes: 0, 1, 0, 1
    Text top: "no", string$(nEvents) + " segmented events  |  " + fixed$(dur, 2) + " s"
    @railLabel: 0.6, 7.7, 0.56, 1.16, 7, "Original"

    # === Output Waveform =============================================
    Font size: 7
    Select outer viewport: 0, 8, 1.62, 2.34
    Select inner viewport: 0.6, 7.7, 1.68, 2.28
    selectObject: resultSound
    if outChans > 1
        visOutChannel = analysisChannel
        if visOutChannel > outChans
            visOutChannel = 1
        endif
        Extract one channel: visOutChannel
        tmpOutWav = selected("Sound")
        Colour: "{0.20, 0.50, 0.75}"
        Draw: 0, 0, -1, 1, "no", "Curve"
        removeObject: tmpOutWav
    else
        selectObject: resultSound
        Colour: "{0.20, 0.50, 0.75}"
        Draw: 0, 0, -1, 1, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box

    Font size: 7
    Select inner viewport: 0.6, 7.7, 1.68, 2.28
    Axes: 0, durOut, -1, 1
    Marks bottom every: 1, tickOut, "no", "yes", "no"
    @railLabel: 0.6, 7.7, 1.68, 2.28, 7, "Output"

    # =================================================================
    # === Plan Timeline ===============================================
    #
    # Source event index against OUTPUT time, one bar per plan step,
    # coloured with the same cluster code as the phase-space panel.
    # Horizontal runs = the attractor dwelling in one region of the
    # corpus; vertical scatter = it sweeping across the corpus; a row
    # that fires repeatedly is what Tabu_length and Temperature exist
    # to control, and Rep in the summary box is that made visible.
    # =================================================================
    tlX1 = 0.6
    tlX2 = 7.7
    tlY1 = 2.52
    tlY2 = 3.62

    Select outer viewport: 0, 8, 2.36, 3.64

    Font size: 6
    Select inner viewport: tlX1, tlX2, tlY1, tlY2
    Axes: 0, durOut, 0.5, nEvents + 0.5
    Paint rectangle: "{0.975, 0.977, 0.985}", 0, durOut, 0.5, nEvents + 0.5

    # Step onset times: each step advances by its own duration minus the
    # crossfade overlap, which is exactly what Concatenate with overlap does.
    barH = 0.40
    if nEvents > 120
        barH = 0.50
    endif

    tCur = 0
    for iStep from 1 to nPlanSteps
        stepEv = planEvIdx[iStep]
        stepDur = evDur[stepEv]
        @clusterOfEvent: stepEv
        if clusterOfEvent.k = 2
            barCol$ = clusCol2$
        elsif clusterOfEvent.k = 3
            barCol$ = clusCol3$
        else
            barCol$ = clusCol1$
        endif
        tEndBar = tCur + stepDur
        if tEndBar > durOut
            tEndBar = durOut
        endif
        Paint rectangle: barCol$, tCur, tEndBar, stepEv - barH, stepEv + barH
        tCur = tCur + stepDur - xfEff
        if tCur > durOut
            tCur = durOut
        endif
    endfor

    @niceTick: nEvents
    tickEv = niceTick.t
    if tickEv < 1
        tickEv = 1
    endif

    Font size: 6
    Select inner viewport: tlX1, tlX2, tlY1, tlY2
    Axes: 0, durOut, 0.5, nEvents + 0.5
    Colour: "Black"
    Line width: 1
    Draw inner box

    Font size: 6
    Select inner viewport: tlX1, tlX2, tlY1, tlY2
    Axes: 0, durOut, 0.5, nEvents + 0.5
    Marks bottom every: 1, tickOut, "yes", "yes", "no"
    Marks left every: 1, tickEv, "yes", "yes", "no"
    Text bottom: "yes", "Output time (s)"

    Font size: 6
    Select inner viewport: tlX1, tlX2, tlY1, tlY2
    Axes: 0, 1, 0, 1
    Text top: "no", "##Plan timeline##  —  which source event sounds when (colour = cluster, shared with the panel below)  |  " + string$(nPlanSteps) + " steps, " + uniqueUsedStat$ + " unique, Rep=" + repRateStat$
    @railLabel: tlX1, tlX2, tlY1, tlY2, 6, "Source event index"

    # =================================================================
    # === Phase-Space Panel: trajectory-to-event mapping ==============
    # =================================================================
    psX1 = 0.6
    psX2 = 7.7
    psY1 = 4.22
    psY2 = 7.52

    Select outer viewport: 0, 8, 4.10, 7.62

    if nPTrajPts > 1 or nPEvPts > 0

        # ---- data-derived bounds -------------------------------------
        # Draw line does NOT clip to the panel, so the axis range has to
        # contain every drawn point or the trajectory spills onto the
        # summary box below.
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
                axMinX = min(axMinX, bx)
                axMaxX = max(axMaxX, bx)
                axMinY = min(axMinY, by)
                axMaxY = max(axMaxY, by)
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
                axMinX = min(axMinX, bx)
                axMaxX = max(axMaxX, bx)
                axMinY = min(axMinY, by)
                axMaxY = max(axMaxY, by)
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
                axMinX = min(axMinX, bx)
                axMaxX = max(axMaxX, bx)
                axMinY = min(axMinY, by)
                axMaxY = max(axMaxY, by)
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
        axMinX -= rangeX * 0.06
        axMaxX += rangeX * 0.06
        axMinY -= rangeY * 0.06
        axMaxY += rangeY * 0.10
        rangeX = axMaxX - axMinX
        rangeY = axMaxY - axMinY

        @niceStep: rangeX
        stepX = niceStep.s
        @niceStep: rangeY
        stepY = niceStep.s

        # ---- background + grid ---------------------------------------
        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Paint rectangle: "{0.975, 0.977, 0.985}", axMinX, axMaxX, axMinY, axMaxY

        Colour: "{0.88, 0.89, 0.93}"
        Line width: 1
        gK = ceiling(axMinX / stepX)
        gV = gK * stepX
        while gV < axMaxX
            Draw line: gV, axMinY, gV, axMaxY
            gK += 1
            gV = gK * stepX
        endwhile
        gK = ceiling(axMinY / stepY)
        gV = gK * stepY
        while gV < axMaxY
            Draw line: axMinX, gV, axMaxX, gV
            gK += 1
            gV = gK * stepY
        endwhile

        # ---- dynamical trajectory ------------------------------------
        # Drawn UNDER the event cloud: with an erratic attractor
        # (LogisticMap in 4D) an on-top trajectory buries the corpus
        # completely.  On smooth attractors the two orders look the same.
        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Colour: trajCol$
        Line width: 1.5
        for iTP from 1 to nPTrajPts - 1
            iPrev = iTP - 1
            Draw line: ptp_'iPrev'_x, ptp_'iPrev'_y, ptp_'iTP'_x, ptp_'iTP'_y
        endfor

        if nPTrajPts > 12
            nArrows = 7
            Arrow size: 0.55
            for iA from 1 to nArrows
                aI = round(iA * (nPTrajPts - 2) / (nArrows + 1))
                if aI >= 1 and aI < nPTrajPts - 1
                    aJ = aI + 1
                    Draw arrow: ptp_'aI'_x, ptp_'aI'_y, ptp_'aJ'_x, ptp_'aJ'_y
                endif
            endfor
            Arrow size: 1
        endif
        Line width: 1

        # ---- analyzed source events (hollow, cluster-coloured) -------
        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Line width: 1.2
        for iEP from 0 to nPEvPts - 1
            kK = evClust[iEP + 1]
            if kK = 2
                Colour: clusCol2$
            elsif kK = 3
                Colour: clusCol3$
            else
                Colour: clusCol1$
            endif
            Draw circle (mm): pep_'iEP'_x, pep_'iEP'_y, 1.45
        endfor

        # ---- selected event plan -------------------------------------
        # Plan dot is deliberately SMALLER than the event ring, so a
        # selected event still shows the cluster colour underneath it.
        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: axMinX, axMaxX, axMinY, axMaxY
        for iSP from 0 to nPSelPts - 1
            Paint circle (mm): planCol$, psel_'iSP'_x, psel_'iSP'_y, 1.10
        endfor

        # Numbered badges on the first plan steps, so the reader can see
        # where the composition actually starts and in what order it moves.
        nBadge = 5
        if nPSelPts < nBadge
            nBadge = nPSelPts
        endif
        for iBd from 1 to nBadge
            bI = iBd - 1
            Font size: 6
            Select inner viewport: psX1, psX2, psY1, psY2
            Axes: axMinX, axMaxX, axMinY, axMaxY
            Paint circle (mm): planCol$, psel_'bI'_x, psel_'bI'_y, 1.90
            Font size: 5
            Select inner viewport: psX1, psX2, psY1, psY2
            Axes: axMinX, axMaxX, axMinY, axMaxY
            Colour: "White"
            Text: psel_'bI'_x, "centre", psel_'bI'_y, "half", "##" + string$(iBd) + "##"
        endfor

        # ---- legend --------------------------------------------------
        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: 0, 1, 0, 1

        lgX1 = 0.742
        lgX2 = 0.988
        lgY1 = 0.812
        lgY2 = 0.985
        Paint rectangle: "White", lgX1, lgX2, lgY1, lgY2
        Colour: "{0.70, 0.70, 0.75}"
        Draw rectangle: lgX1, lgX2, lgY1, lgY2

        lgSw = lgX1 + 0.026
        lgTx = lgX1 + 0.055
        lgR1 = lgY2 - 0.044
        lgR2 = lgY2 - 0.090
        lgR3 = lgY2 - 0.136

        Colour: clusCol1$
        Line width: 1.2
        Draw circle (mm): lgSw, lgR1, 1.45
        Colour: trajCol$
        Line width: 1.5
        Draw line: lgSw - 0.014, lgR2, lgSw + 0.014, lgR2
        Line width: 1
        Paint circle (mm): planCol$, lgSw, lgR3, 1.10

        Colour: "{0.20, 0.20, 0.24}"
        Text: lgTx, "left", lgR1, "half", "analyzed source events"
        Text: lgTx, "left", lgR2, "half", "dynamical trajectory"
        Text: lgTx, "left", lgR3, "half", "selected event plan"

        # ---- callouts ------------------------------------------------
        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.905, 0.935, 1.0}", 0.012, 0.212, 0.872, 0.982
        Colour: clusCol1$
        Draw rectangle: 0.012, 0.212, 0.872, 0.982
        Text: 0.024, "left", 0.955, "half", "clusters = segmented"
        Text: 0.024, "left", 0.900, "half", "source fragments"

        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.935, 0.912, 1.0}", 0.716, 0.988, 0.022, 0.132
        Colour: planCol$
        Draw rectangle: 0.716, 0.988, 0.022, 0.132
        Text: 0.728, "left", 0.105, "half", "selection: nearest event,"
        Text: 0.728, "left", 0.050, "half", "tabu memory + temperature"

        # ---- frame, marks, axis labels -------------------------------
        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Colour: "Black"
        Line width: 1
        Draw inner box

        Font size: 6
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Marks bottom every: 1, stepX, "yes", "yes", "no"
        Marks left every: 1, stepY, "yes", "yes", "no"

        projLab0$ = replace$(projAxis0$, "_", "-", 0)
        projLab1$ = replace$(projAxis1$, "_", "-", 0)

        Font size: 7
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: axMinX, axMaxX, axMinY, axMaxY
        Text bottom: "yes", "Normalized " + projLab0$
        Text top: "no", "##Trajectory-to-event mapping##  —  " + attractorStr$ + " (" + stateDimStr$ + "): a dynamical-system path is mapped onto analyzed source events"
        @railLabel: psX1, psX2, psY1, psY2, 7, "Normalized " + projLab1$

    else
        Font size: 7
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.975, 0.977, 0.985}", 0, 1, 0, 1
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.5, "centre", 0.5, "half", "(trajectory data not available)"
        Colour: "Black"
        Select inner viewport: psX1, psX2, psY1, psY2
        Axes: 0, 1, 0, 1
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Summary Panel ===============================================
    Font size: 7
    Select outer viewport: 0, 8, 8.04, 9.17
    Select inner viewport: 0.6, 7.7, 8.10, 9.14
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"

    Font size: 6
    Select inner viewport: 0.6, 7.7, 8.10, 9.14
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.68, "half", attractorStat$ + " " + stateDimsStat$ + "D | Events=" + nSourceEvStat$ + "->" + string$(nPlanSteps) + " | Uniq=" + uniqueUsedStat$ + " Rep=" + repRateStat$ + " | Speed=" + trajSpeedStat$
    Text: 0.02, "left", 0.50, "half", "Vel=" + velocityWeightStat$ + " Cpl=" + couplingStat$ + " W=" + weightPresetStat$ + " | Tabu=" + tabuStat$ + " T=" + tempStatVal$ + " | MapDist=" + meanMapDistStat$
    Text: 0.02, "left", 0.32, "half", "RMS: " + fixed$(rms_orig, 4) + "->" + fixed$(rms_out, 4) + " | " + fixed$(dur, 2) + "s->" + fixed$(durOut, 2) + "s | Ch=" + string$(analysisChannel) + " | Xfade=" + fixed$(xfEff * 1000, 1) + "ms | Seed=" + string$(seed)

    if attractor_type = 1
        attDesc$ = "Hopf: limit cycle — repeating morphological loops"
    elsif attractor_type = 2
        attDesc$ = "Lorenz: strange attractor — chaotic recurrence"
    elsif attractor_type = 3
        attDesc$ = "Rössler: single-scroll — spiral divergence + return"
    else
        attDesc$ = "Logistic: 1-D chaos — regime shifts + intermittency"
    endif
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.02, "left", 0.14, "half", attDesc$

    Font size: 6
    Select inner viewport: 0.6, 7.7, 8.10, 9.14
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Save as / Copy from the Picture window exports the CURRENT viewport
    # selection, so the script must end on the whole canvas or the export
    # comes out cropped to the last panel drawn.
    Colour: "Black"
    Line width: 1
    Font size: 10
    Select outer viewport: 0, 8, 0, canvasH

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

procedure niceStep: .range
    if .range <= 0.30
        .s = 0.05
    elsif .range <= 0.60
        .s = 0.1
    elsif .range <= 1.50
        .s = 0.2
    elsif .range <= 3.50
        .s = 0.5
    else
        .s = 1
    endif
endproc

# Text left: / Text right: position a rotated panel label against whatever
# drawing frame is current, which puts each panel's name at a different x.
# Placing them by hand against one shared offset keeps the rail straight.
# Vertical alignment must be "bottom", not "half": "half" anchors the glyph
# bounding box, so a descender shifts that one label off the rail.
procedure railLabel: .x1, .x2, .y1, .y2, .size, .label$
    Font size: .size
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.035, "centre", 0.5, "bottom", "Helvetica", .size, "90", .label$
endproc

# Python samples the event cloud with linspace(0, nEvents-1, min(nEvents,200)),
# so a source event's cluster is found by inverting that sampling.  When the
# corpus is 200 events or fewer the mapping is the identity.
procedure clusterOfEvent: .srcIdx
    .k = 0
    if nPEvPts > 0
        if nPEvPts >= nEvents
            .s = .srcIdx
        else
            .s = round((.srcIdx - 1) * (nPEvPts - 1) / max(nEvents - 1, 1)) + 1
        endif
        if .s < 1
            .s = 1
        endif
        if .s > nPEvPts
            .s = nPEvPts
        endif
        .k = evClust[.s]
    endif
endproc

# Axis tick spacing: the largest 1/2/5 x 10^k step that still gives roughly
# eight divisions across the span.
procedure niceTick: .span
    if .span <= 0
        .t = 1
    else
        .raw  = .span / 8
        .expo = floor(log10(.raw))
        .base = .raw / 10 ^ .expo
        if .base < 1.5
            .m = 1
        elsif .base < 3.5
            .m = 2
        elsif .base < 7.5
            .m = 5
        else
            .m = 10
        endif
        .t = .m * 10 ^ .expo
    endif
endproc
