# ============================================================
# Praat AudioTools - LatentBarycentric.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent Barycentric Mutation
#
#   Trains a VAE on-the-fly from event-level audio patches,
#   then navigates the latent space according to a navigation plan.
#   At each step K nearest-neighbor events are found and their
#   waveforms are mixed with barycentric (inverse-distance) weights.
#
#   The navigation plan can be:
#   (a) Loaded from an external CSV (e.g. the AI-generated latent_nav_plan.csv)
#   (b) Generated internally by Python from the form controls below
#
#   Navigation plan modes:
#   - drift:   coherent small steps, low temperature
#   - mutate:  large exploratory steps, high temperature
#   - return:  gravitational pull back to an anchor region
#   - settle:  cool-down, converge to stability (external CSV only)
#   - cycle:   auto preset that sequences drift → mutate → return
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
pythonScript$ = pluginDir$ + "py/latent_barycentric.py"
navPlanCSV$   = pluginDir$ + "py/latent_nav_plan.csv"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

tempPlanCSV$ = temporaryDirectory$ + "/temp_latbary_plan_placeholder.csv"
tempInput$   = temporaryDirectory$ + "/temp_latbary_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_latbary_events.csv"
tempOutput$  = temporaryDirectory$ + "/temp_latbary_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_latbary_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_latbary_probe.ok"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempPlanCSV$)
        deleteFile: tempPlanCSV$
    endif
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
form Latent Barycentric Mutation v1.2
    # ── Core settings ─────────────────────────────────────────────────────
    optionmenu Preset: 1
        option Custom
        option Gentle drift
        option Full mutation arc
        option Return focus
        option Slow settle
    integer Latent_size 8
    real Duration_(0_=_original) 0
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
    # ── Plan Generator ────────────────────────────────────────────────────
    comment ── Plan source ──────────────────────────────────────────────
    optionmenu Plan_source: 2
        option External CSV (latent_nav_plan.csv)
        option Auto-generate
    comment ── Generator controls (used when Auto-generate is selected) ──
    optionmenu Plan_mode_preset: 4
        option drift
        option mutate
        option return
        option cycle
    integer Plan_steps 60
    real Plan_step_size 0.35
    real Plan_temperature 0.40
    integer Plan_k_neighbors 4
    real Plan_return_strength 0.65
    optionmenu Plan_anchor_strategy: 1
        option center
        option step0
        option last
        option periodic
    integer Plan_anchor_period 15
    real Plan_dur_scale 1.0
    real Plan_dur_jitter 0.0
    real Plan_eng_scale 1.0
    real Plan_eng_jitter 0.0
    comment ── Output level ─────────────────────────────────────────────
    optionmenu Normalize_mode: 3
        option none
        option peak
        option rms
        option loudness
    comment ── Pitch preservation ──────────────────────────────────────
    optionmenu Pitch_mode: 2
        option off
        option preserve_f0
        option preserve_spectral_envelope
endform

# ---- PRESET APPLICATION (core settings) ----
if preset = 2
    latent_size = 6
    presetName$ = "GentleDrift"
elsif preset = 3
    latent_size = 10
    presetName$ = "FullMutationArc"
elsif preset = 4
    latent_size = 8
    presetName$ = "ReturnFocus"
elsif preset = 5
    latent_size = 6
    presetName$ = "SlowSettle"
else
    presetName$ = "Custom"
endif

if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif

# ---- MAP FORM OPTION-MENUS TO STRING VALUES ----
if plan_source = 1
    planSourceStr$ = "external_csv"
else
    planSourceStr$ = "auto_generate"
endif

if plan_mode_preset = 1
    planModeStr$ = "drift"
elsif plan_mode_preset = 2
    planModeStr$ = "mutate"
elsif plan_mode_preset = 3
    planModeStr$ = "return"
else
    planModeStr$ = "cycle"
endif

if plan_anchor_strategy = 1
    planAnchorStr$ = "center"
elsif plan_anchor_strategy = 2
    planAnchorStr$ = "step0"
elsif plan_anchor_strategy = 3
    planAnchorStr$ = "last"
else
    planAnchorStr$ = "periodic"
endif

if normalize_mode = 1
    normModeStr$ = "none"
elsif normalize_mode = 2
    normModeStr$ = "peak"
elsif normalize_mode = 3
    normModeStr$ = "rms"
else
    normModeStr$ = "loudness"
endif

if pitch_mode = 1
    pitchModeStr$ = "off"
elsif pitch_mode = 2
    pitchModeStr$ = "preserve_f0"
else
    pitchModeStr$ = "preserve_spectral_envelope"
endif

# ---- EXTERNAL CSV CHECK ----
if plan_source = 1
    if not fileReadable(navPlanCSV$)
        exitScript: "Cannot find navigation plan: " + navPlanCSV$ + newline$ + "Expected: " + navPlanCSV$ + newline$ + "Tip: switch Plan source to Auto-generate to skip this file."
    endif
endif

# ---- CLAMP GENERATOR VALUES ----
if plan_steps < 4
    plan_steps = 4
endif
if plan_steps > 500
    plan_steps = 500
endif
if plan_step_size < 0
    plan_step_size = 0
endif
if plan_step_size > 1
    plan_step_size = 1
endif
if plan_temperature < 0
    plan_temperature = 0
endif
if plan_temperature > 1
    plan_temperature = 1
endif
if plan_k_neighbors < 2
    plan_k_neighbors = 2
endif
if plan_k_neighbors > 8
    plan_k_neighbors = 8
endif
if plan_return_strength < 0
    plan_return_strength = 0
endif
if plan_return_strength > 1
    plan_return_strength = 1
endif
if plan_anchor_period < 1
    plan_anchor_period = 1
endif
if plan_dur_scale < 0.25
    plan_dur_scale = 0.25
endif
if plan_dur_scale > 4.0
    plan_dur_scale = 4.0
endif
if plan_dur_jitter < 0
    plan_dur_jitter = 0
endif
if plan_eng_scale < 0.1
    plan_eng_scale = 0.1
endif
if plan_eng_scale > 3.0
    plan_eng_scale = 3.0
endif
if plan_eng_jitter < 0
    plan_eng_jitter = 0
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Latent Barycentric Mutation v1.2 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Latent size:  ", latent_size
appendInfoLine: "Duration:     ", if duration > 0 then fixed$(duration, 1) else "original" fi
appendInfoLine: "Seed:         ", seed
appendInfoLine: ""
appendInfoLine: "Plan source:  ", planSourceStr$
if plan_source = 2
    appendInfoLine: "Mode preset:  ", planModeStr$
    appendInfoLine: "Steps:        ", plan_steps
    appendInfoLine: "Step size:    ", fixed$(plan_step_size, 3)
    appendInfoLine: "Temperature:  ", fixed$(plan_temperature, 3)
    appendInfoLine: "K neighbors:  ", plan_k_neighbors
    appendInfoLine: "Ret strength: ", fixed$(plan_return_strength, 3)
    appendInfoLine: "Anchor strat: ", planAnchorStr$
    if plan_anchor_strategy = 4
        appendInfoLine: "Anchor period:", plan_anchor_period
    endif
    appendInfoLine: "Dur scale:    ", fixed$(plan_dur_scale, 3), "  jitter: ", fixed$(plan_dur_jitter, 3)
    appendInfoLine: "Eng scale:    ", fixed$(plan_eng_scale, 3), "  jitter: ", fixed$(plan_eng_jitter, 3)
endif
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

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
intSound  = To Sound (slice): 1
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
            tmpVal    = bound_'i'
            bound_'i' = bound_'j'
            bound_'j' = tmpVal
        endif
    endfor
endfor

nFinal = 0
prevT  = -1
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
    iNext   = i + 1
    evEnd   = final_'iNext'
    evDur   = evEnd - evStart

    if evDur > maxEventDur
        nChunks  = ceiling(evDur / maxEventDur)
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
    t1   = evS_'iEv'
    t2   = evE_'iEv'
    tMid = (t1 + t2) / 2

    selectObject: eventTable
    Set numeric value: iEv, "start_time", t1
    Set numeric value: iEv, "end_time",   t2
    Set string value:  iEv, "label",      "ev" + string$(iEv)

    selectObject: pitchObj
    pMean = Get mean:               t1, t2, "Hertz"
    pStd  = Get standard deviation: t1, t2, "Hertz"
    if pMean = undefined or pMean = 0
        pitchStab = 0
    else
        if pStd = undefined
            pStd = 0
        endif
        pitchCV   = pStd / (pMean + 0.001)
        pitchStab = 1 - min(1, pitchCV)
        if pitchStab < 0
            pitchStab = 0
        endif
    endif
    selectObject: eventTable
    Set numeric value: iEv, "pitch_stability", pitchStab

    selectObject: intObj
    iMean  = Get mean:             t1, t2, "energy"
    if iMean = undefined
        iMean = 0
    endif
    iStart = Get value at time: t1, "Cubic"
    if iStart = undefined
        iStart = 0
    endif
    iPeak  = Get maximum:         t1, t2, "Parabolic"
    if iPeak = undefined
        iPeak = iStart
    endif
    tPeak  = Get time of maximum: t1, t2, "Parabolic"
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
    Set numeric value: iEv, "attack_slope",   attackSlope

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

if plan_source = 2
    appendInfoLine: "[4/5] Running Python engine..."
    appendInfoLine: "  (VAE + auto-generated plan: ", planModeStr$, ", ", plan_steps, " steps, latent=", latent_size, ")"
else
    appendInfoLine: "[4/5] Running Python engine..."
    appendInfoLine: "  (VAE + external nav plan, latent=", latent_size, ")"
endif

if plan_source = 2
    navPlanArg$ = tempPlanCSV$
else
    navPlanArg$ = navPlanCSV$
endif

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + navPlanArg$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " --latent_size " + string$(latent_size)
    ... + " --seed "        + string$(seed)
    ... + " --duration "    + fixed$(duration, 4)
    ... + " --cleanup"
    ... + " --plan_source " + planSourceStr$
    ... + " --normalize_mode " + normModeStr$
    ... + " --pitch_mode " + pitchModeStr$

if plan_source = 2
    pythonCall$ = pythonCall$
        ... + " --plan_steps "               + string$(plan_steps)
        ... + " --plan_mode_preset "         + planModeStr$
        ... + " --plan_step_size "           + fixed$(plan_step_size, 4)
        ... + " --plan_temperature "         + fixed$(plan_temperature, 4)
        ... + " --plan_k "                   + string$(plan_k_neighbors)
        ... + " --plan_return_strength "     + fixed$(plan_return_strength, 4)
        ... + " --plan_return_anchor_strategy " + planAnchorStr$
        ... + " --plan_anchor_period "       + string$(plan_anchor_period)
        ... + " --plan_dur_scale "           + fixed$(plan_dur_scale, 4)
        ... + " --plan_dur_jitter "          + fixed$(plan_dur_jitter, 4)
        ... + " --plan_eng_scale "           + fixed$(plan_eng_scale, 4)
        ... + " --plan_eng_jitter "          + fixed$(plan_eng_jitter, 4)
        ... + " --plan_cleanup_policy python_cleanup"
endif

runSystem_nocheck: pythonCall$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python barycentric engine failed." + newline$ + "Check terminal for error details."
endif

# ===========================================================================
# Stage 5 — Import Result
# ===========================================================================
appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_bary"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration

# ===========================================================================
# Read Stats
# ===========================================================================
nEvStat$        = "?"
nPlanSteps$     = "?"
nExecSteps$     = "?"
planSourceStat$ = "?"
outDurStat$     = "?"
normModeStat$   = "?"
pitchModeStat$  = "?"
rmsInputStat$   = "?"
rmsOutputStat$  = "?"
finalLoss$      = "?"
initialLoss$    = "?"
meanEvDur$      = "?"
modeDrift$      = "0"
modeMutate$     = "0"
modeReturn$     = "0"
modeSettle$     = "0"
warningStat$    = ""

nEvPts = 0
nTrajPts = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_plan_steps="
    nPlanSteps$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_executed_steps="
    nExecSteps$ = parseStatLine.result$
    @parseStatLine: statsText$, "plan_source="
    planSourceStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "normalize_mode="
    normModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "pitch_mode="
    pitchModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_input="
    rmsInputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_output="
    rmsOutputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEvDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_drift_steps="
    modeDrift$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_mutate_steps="
    modeMutate$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_return_steps="
    modeReturn$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_settle_steps="
    modeSettle$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$

    # ── Parse event positions (PCA-projected) ──
    @parseStatLine: statsText$, "n_ev_pts="
    nEvPts$ = parseStatLine.result$
    if nEvPts$ <> "?"
        nEvPts = number(nEvPts$)
    endif
    if nEvPts > 200
        nEvPts = 200
    endif
    for iEP from 0 to nEvPts - 1
        @parseStatLine: statsText$, "ev_" + string$(iEP) + "="
        epRaw$ = parseStatLine.result$
        ep_'iEP'_x = 0
        ep_'iEP'_y = 0
        if epRaw$ <> "?"
            comma = index(epRaw$, ",")
            if comma > 0
                ep_'iEP'_x = number(left$(epRaw$, comma - 1))
                ep_'iEP'_y = number(mid$(epRaw$, comma + 1, length(epRaw$) - comma))
            endif
        endif
    endfor

    # ── Parse trajectory points (PCA-projected + mode) ──
    @parseStatLine: statsText$, "n_traj_pts="
    nTrajPts$ = parseStatLine.result$
    if nTrajPts$ <> "?"
        nTrajPts = number(nTrajPts$)
    endif
    if nTrajPts > 200
        nTrajPts = 200
    endif
    for iTP from 0 to nTrajPts - 1
        @parseStatLine: statsText$, "tr_" + string$(iTP) + "="
        tpRaw$ = parseStatLine.result$
        tp_'iTP'_x = 0
        tp_'iTP'_y = 0
        tp_'iTP'_mode$ = "drift"
        if tpRaw$ <> "?"
            comma1 = index(tpRaw$, ",")
            if comma1 > 0
                tp_'iTP'_x = number(left$(tpRaw$, comma1 - 1))
                rest$ = mid$(tpRaw$, comma1 + 1, length(tpRaw$) - comma1)
                comma2 = index(rest$, ",")
                if comma2 > 0
                    tp_'iTP'_y = number(left$(rest$, comma2 - 1))
                    tp_'iTP'_mode$ = mid$(rest$, comma2 + 1, length(rest$) - comma2)
                else
                    tp_'iTP'_y = number(rest$)
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
    Text: 0.5, "centre", 0.6, "half", "##Latent Barycentric Mutation##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    if plan_source = 2
        subtitleStr$ = soundName$ + " | " + presetName$ + " | auto:" + planModeStr$ + "/" + string$(plan_steps) + "steps | Latent=" + string$(latent_size)
    else
        subtitleStr$ = soundName$ + " | " + presetName$ + " | ext.plan | Latent=" + string$(latent_size) + " | Seed=" + string$(seed)
    endif
    Text: 0.5, "centre", -1.2, "half", subtitleStr$

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
    Text left: "yes", "Barycentric"
    Text bottom: "yes", "Time (s)"

    # === Input Spectrogram ===
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
    Text top: "no", "Barycentric output spectrogram (L channel)"
    removeObject: specOut, tmpOut

    # === Latent Trajectory Panel ===
    Select outer viewport: 0, 8, 5.0, 6.5
    Select inner viewport: 0.6, 7.7, 5.1, 6.4

    if nEvPts > 0 or nTrajPts > 0
        axMinX = 0
        axMaxX = 1
        axMinY = 0
        axMaxY = 1
        gotBounds = 0
        for iB from 0 to nEvPts - 1
            bx = ep_'iB'_x
            by = ep_'iB'_y
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
        for iB from 0 to nTrajPts - 1
            bx = tp_'iB'_x
            by = tp_'iB'_y
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

        dotR = rangeX * 0.015
        for iEP from 0 to nEvPts - 1
            Paint circle (mm): "{0.7, 0.7, 0.7}", ep_'iEP'_x, ep_'iEP'_y, 1.2
        endfor

        Line width: 2
        for iTP from 1 to nTrajPts - 1
            iPrev = iTP - 1
            thisMode$ = tp_'iTP'_mode$
            if thisMode$ = "mutate"
                Colour: "{0.8, 0.3, 0.2}"
            elsif thisMode$ = "return"
                Colour: "{0.3, 0.7, 0.4}"
            elsif thisMode$ = "settle"
                Colour: "{0.6, 0.5, 0.2}"
            else
                Colour: "{0.3, 0.5, 0.8}"
            endif
            Draw line: tp_'iPrev'_x, tp_'iPrev'_y, tp_'iTP'_x, tp_'iTP'_y
        endfor
        Line width: 1

        if nTrajPts > 0
            Paint circle (mm): "{0.2, 0.7, 0.3}", tp_0_x, tp_0_y, 1.8
            iLast = nTrajPts - 1
            Paint circle (mm): "{0.8, 0.2, 0.2}", tp_'iLast'_x, tp_'iLast'_y, 1.8
        endif

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "PC2"
        Text bottom: "yes", "PC1"
        Text top: "no", "Latent trajectory (events = grey | ##S## = start | ##E## = end)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(latent trajectory data not available)"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.6, 8.0
    Select inner viewport: 0.6, 7.7, 6.7, 7.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.91, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.75, "half", "Events: " + nEvStat$ + " | Plan: " + nPlanSteps$ + " steps | Used: " + nExecSteps$ + " / " + nPlanSteps$ + " | Mean event dur: " + meanEvDur$ + " s"
    Text: 0.02, "left", 0.57, "half", "VAE loss: " + initialLoss$ + " -> " + finalLoss$ + " | Latent=" + string$(latent_size) + " | Seed=" + string$(seed)
    Text: 0.02, "left", 0.39, "half", "Duration: " + fixed$(dur, 2) + "s -> " + outDurStat$ + "s | Normalize: " + normModeStat$ + " | RMS: " + rmsInputStat$ + " -> " + rmsOutputStat$
    Text: 0.02, "left", 0.21, "half", "Pitch: " + pitchModeStat$ + " | Plan source: " + planSourceStat$
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.05, "half", "Phases: drift=" + modeDrift$ + " mutate=" + modeMutate$ + " return=" + modeReturn$ + " settle=" + modeSettle$

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.65, "left", 0.05, "half", "Warn: " + warningStat$
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
appendInfoLine: "Output: ", soundName$, "_bary (stereo)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Plan:   ", planSourceStat$
appendInfoLine: ""
appendInfoLine: "Navigation plan phases:"
appendInfoLine: "  drift:  ", modeDrift$,  " steps"
appendInfoLine: "  mutate: ", modeMutate$, " steps"
appendInfoLine: "  return: ", modeReturn$, " steps"
appendInfoLine: "  settle: ", modeSettle$, " steps"
appendInfoLine: ""
appendInfoLine: "Plan steps: ", nPlanSteps$, " | Used: ", nExecSteps$, " / ", nPlanSteps$
appendInfoLine: "Events:     ", nEvStat$,    " | Mean dur: ", meanEvDur$, " s"
appendInfoLine: "VAE loss:   ", initialLoss$, " -> ", finalLoss$
appendInfoLine: "Duration:   ", fixed$(dur, 2), " s -> ", outDurStat$, " s"
appendInfoLine: "Normalize:  ", normModeStat$
appendInfoLine: "Pitch mode: ", pitchModeStat$
appendInfoLine: "RMS input:  ", rmsInputStat$
appendInfoLine: "RMS output: ", rmsOutputStat$

if warningStat$ <> "?" and warningStat$ <> ""
    appendInfoLine: "WARNING:    ", warningStat$
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