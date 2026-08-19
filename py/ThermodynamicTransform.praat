# ============================================================
# Praat AudioTools - ThermodynamicTransform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Thermodynamic event relocation with AI state discovery.
#   Analyzes acoustic structure -> discovers phase regimes via ML ->
#   segments complete time-domain events -> relocates/duplicates/evaporates
#   events according to Crystal/Fluid/Gas/Plasma rules.
#   Powered by Python (numpy, scipy, scikit-learn, soundfile).
#
#   Parameters:
#   - Macro intensity: overall transformation strength (0-1)
#   - Memory:          state machine inertia/hysteresis (0-1)
#   - AI mode:         A=clustering  B=predictive  C=learned-entropy
#   - AI strength:     AI influence on regime assignment (0-1)
#   - Seed:            for full deterministic reproducibility
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.3 (2026):
#   - CORRECTNESS: exact Praat/STFT time-grid alignment; silence no longer
#     reads as maximally flat/noisy spectral content.
#   - CONTROL: Thermo_intensity=0 is identity (unless Convection is used);
#     AI_strength=0 truly disables direct AI regime voting.
#   - RELOCATION: Gas moves globally; Plasma anchoring is continuous in intensity.
#   - MULTICHANNEL: strongest-RMS real channel is used for analysis.
#   - RECONSTRUCTION: crossfade only discontinuous joins; contiguous source
#     neighbours remain sample-contiguous. FLOAT output and true final audio tail.
#   - PORTABILITY: unique temp files and captured Python log.
#
# Changelog v2.2 (2026):
#   - FIX: Probe-failure detection. The OS-discovery block at the top
#     always assigned pythonCmd$ to something non-empty, making the
#     post-probe "if pythonCmd$ = """ exit unreachable. Total Python
#     failure was silently masked. Now pythonCmd$ is cleared before
#     the probe loop, and the early-discovery path (when present) is
#     prepended as the highest-priority candidate.
#   - PORTABILITY: Replaced the for-loop early-break that mutated the
#     loop variable (iCand = nCandidates + 1) with the standard
#     "found" flag pattern. Loop-var mutation works in current Praat
#     but is fragile across versions.
#   - SPEED (Python): ai_mode_b inference loop replaced with a single
#     batched model.predict() call. Per-frame predictions had ~3000
#     sklearn-call overheads on typical inputs.
#   - SPEED (Python): vectorized spectral-rolloff per-frame loop and
#     two pitch-derivative loops in compute_novelty_curve and
#     construct_fields. Pure numpy now, no per-frame Python iteration.
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
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

pythonScript$ = pluginDir$ + "py/thermodynamic_transform.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/thermodynamic_transform.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: thermodynamic_transform.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

runToken$    = string$(sound)
tempInput$   = tempDir$ + "temp_thermo_" + runToken$ + "_input.wav"
tempCSV$     = tempDir$ + "temp_thermo_" + runToken$ + "_features.csv"
tempOutput$  = tempDir$ + "temp_thermo_" + runToken$ + "_output.wav"
tempRegimes$ = tempDir$ + "temp_thermo_" + runToken$ + "_regimes.txt"
tempStats$   = tempDir$ + "temp_thermo_" + runToken$ + "_stats.txt"
tempLog$     = tempDir$ + "temp_thermo_" + runToken$ + "_python.log"
probePy$     = tempDir$ + "temp_thermo_" + runToken$ + "_probe.py"
probeMarker$ = tempDir$ + "temp_thermo_" + runToken$ + "_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempCSVJ$      = replace_regex$(tempCSV$, "\\", "/", 0)
tempOutputJ$   = replace_regex$(tempOutput$, "\\", "/", 0)
tempRegimesJ$  = replace_regex$(tempRegimes$, "\\", "/", 0)
tempStatsJ$    = replace_regex$(tempStats$, "\\", "/", 0)
tempLogJ$      = replace_regex$(tempLog$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

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
    if fileReadable(tempRegimes$)
        deleteFile: tempRegimes$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
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
form Thermodynamic Transform v2.3
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Gentle crystallization
        option Balanced flow
        option Volatile atmosphere
        option Deep plasma
        option AI explorer
        option Convection flow
    comment === Thermodynamic Controls ===
    real Thermo_intensity 0.6
    real Memory 0.5
    real Convection 0.0
    boolean Preserve_duration 1
    comment === AI Layer ===
    optionmenu AI_mode: 1
        option A — Unsupervised clustering
        option B — Predictive instability
        option C — Learned entropy (PCA)
    real AI_strength 0.5
    comment === Reproducibility ===
    integer Seed 42
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    thermo_intensity = 0.3
    memory           = 0.7
    convection       = 0.0
    aI_strength      = 0.4
    presetName$ = "GentleCrystal"
elsif preset = 3
    thermo_intensity = 0.5
    memory           = 0.5
    convection       = 0.0
    aI_strength      = 0.5
    presetName$ = "BalancedFlow"
elsif preset = 4
    thermo_intensity = 0.7
    memory           = 0.3
    convection       = 0.0
    aI_strength      = 0.6
    presetName$ = "VolatileAtmo"
elsif preset = 5
    thermo_intensity = 0.85
    memory           = 0.2
    convection       = 0.0
    aI_strength      = 0.7
    presetName$ = "DeepPlasma"
elsif preset = 6
    thermo_intensity = 0.6
    memory           = 0.4
    convection       = 0.0
    aI_strength      = 0.9
    presetName$ = "AIExplorer"
elsif preset = 7
    thermo_intensity = 0.6
    memory           = 0.3
    convection       = 0.7
    aI_strength      = 0.5
    presetName$ = "Convection"
else
    presetName$ = "Custom"
endif

# Keep displayed/reported controls identical to the clamped Python values.
thermo_intensity = max(0, min(1, thermo_intensity))
memory = max(0, min(1, memory))
convection = max(0, min(1, convection))
aI_strength = max(0, min(1, aI_strength))

# Resolve AI mode letter
if aI_mode = 1
    aiModeLetter$ = "A"
elsif aI_mode = 2
    aiModeLetter$ = "B"
else
    aiModeLetter$ = "C"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Thermodynamic Transform v2.3 (Event Relocation) ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Thermo intensity: ", fixed$(thermo_intensity, 2)
appendInfoLine: "Memory:           ", fixed$(memory, 2)
appendInfoLine: "Convection:       ", fixed$(convection, 2)
appendInfoLine: "Preserve duration:", preserve_duration
appendInfoLine: "AI mode:          ", aiModeLetter$
appendInfoLine: "AI strength:      ", fixed$(aI_strength, 2)
appendInfoLine: "Seed:             ", seed
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
# Stage 0 — Early Python Dependency Probe
# ===========================================================================
appendInfoLine: "[0/5] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile, sklearn"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

# v2.2: Save the OS-discovery value as candidate0 (highest priority),
# then clear pythonCmd$ so the post-probe check can detect total failure.
# The OS-discovery block above set pythonCmd$ to a path like
# /opt/homebrew/bin/python3 if available — if that path passes the
# probe, it's preferred over the generic "python3" name (which may
# resolve to a different Python on Mac).
earlyDiscovered$ = pythonCmd$
pythonCmd$ = ""

if windows
    nCandidates = 5
    candidate1$ = earlyDiscovered$
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = "py -3"
    candidate5$ = "python3"
else
    nCandidates = 4
    candidate1$ = earlyDiscovered$
    candidate2$ = "python3"
    candidate3$ = "python"
    candidate4$ = "py"
    candidate5$ = ""
endif

# v2.2: replaced "iCand = nCandidates + 1" loop-var mutation with
# the standard "found" flag pattern. Loop-var mutation works in
# current Praat but is fragile across versions.
found = 0
for iCand from 1 to nCandidates
    if found = 0
        if iCand = 1
            tryCmd$ = candidate1$
        elsif iCand = 2
            tryCmd$ = candidate2$
        elsif iCand = 3
            tryCmd$ = candidate3$
        elsif iCand = 4
            tryCmd$ = candidate4$
        else
            tryCmd$ = candidate5$
        endif

        # Skip empty candidate slot (Linux candidate5)
        if tryCmd$ <> ""
            if fileReadable(probeMarker$)
                deleteFile: probeMarker$
            endif

            runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

            if fileReadable(probeMarker$)
                pythonCmd$ = tryCmd$
                deleteFile: probeMarker$
                found = 1
            endif
        endif
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: " + earlyDiscovered$ + ", python3, python, py" + newline$ + "Please install: pip install numpy scipy soundfile scikit-learn"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 1 — Feature Extraction
# ===========================================================================

appendInfoLine: "[1/5] Extracting acoustic features..."

hopSec = 0.01
nFrames = floor(dur / hopSec)
if nFrames < 10
    @cleanUpTempFiles
    exitScript: "Sound is too short for analysis (need > 0.1 s)."
endif

# ---- Create analysis objects ----
selectObject: sound

# Use the strongest real channel for analysis (avoid silent channel 1 / phase fold-down).
analysisChannel = 1
if nChannels > 1
    bestChannelRMS = -1
    for ch from 1 to nChannels
        selectObject: sound
        Extract one channel: ch
        probeChannel = selected("Sound")
        channelRMS = Get root-mean-square: 0, 0
        if channelRMS > bestChannelRMS
            bestChannelRMS = channelRMS
            analysisChannel = ch
        endif
        removeObject: probeChannel
    endfor
    selectObject: sound
    Extract one channel: analysisChannel
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif
appendInfoLine: "  Analysis channel: ", analysisChannel

selectObject: analysisMono
pitchObj = To Pitch: 0.01, 75, 600

selectObject: analysisMono
harmObj = To Harmonicity (cc): 0.01, 75, 0.1, 1.0

selectObject: analysisMono
intObj = To Intensity: 100, 0.01, "yes"

selectObject: analysisMono
formantObj = To Formant (burg): 0.01, 5, 5500, 0.025, 50

# ---- Build feature table ----
Create Table with column names: "features", nFrames,
    ... "time pitch voiced hnr intensity f1 f2 f3 f4 b1 b2 b3 b4"
featureTable = selected("Table")

for i from 1 to nFrames
    t = (i - 0.5) * hopSec
    if t > dur
        t = dur
    endif

    # Time
    selectObject: featureTable
    Set numeric value: i, "time", t

    # Pitch
    selectObject: pitchObj
    p = Get value at time: t, "Hertz", "Linear"
    if p = undefined
        selectObject: featureTable
        Set numeric value: i, "pitch", 0
        Set numeric value: i, "voiced", 0
    else
        selectObject: featureTable
        Set numeric value: i, "pitch", p
        Set numeric value: i, "voiced", 1
    endif

    # HNR
    selectObject: harmObj
    h = Get value at time: t, "Cubic"
    if h = undefined
        h = 0
    endif
    selectObject: featureTable
    Set numeric value: i, "hnr", h

    # Intensity
    selectObject: intObj
    intVal = Get value at time: t, "Cubic"
    if intVal = undefined
        intVal = 0
    endif
    selectObject: featureTable
    Set numeric value: i, "intensity", intVal

    # Formants + bandwidths
    for fNum from 1 to 4
        selectObject: formantObj
        fVal = Get value at time: fNum, t, "hertz", "Linear"
        bVal = Get bandwidth at time: fNum, t, "hertz", "Linear"
        if fVal = undefined
            fVal = 0
        endif
        if bVal = undefined
            bVal = 0
        endif
        selectObject: featureTable
        Set numeric value: i, "f" + string$(fNum), fVal
        Set numeric value: i, "b" + string$(fNum), bVal
    endfor
endfor

appendInfoLine: "  Extracted ", nFrames, " frames at ", fixed$(hopSec * 1000, 0), " ms hop"

# ---- Export WAV + CSV ----
appendInfoLine: "[2/5] Exporting temp files..."

selectObject: sound
Save as 32-bit WAV file: tempInput$

selectObject: featureTable
Save as comma-separated file: tempCSV$

# ---- Cleanup analysis objects ----
removeObject: analysisMono, pitchObj, harmObj, intObj, formantObj, featureTable

# ===========================================================================
# Stage 3 — Call Python
# ===========================================================================

appendInfoLine: "[3/5] Running Python engine (this may take a while)..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempInputJ$ + """"
    ... + " """ + tempCSVJ$ + """"
    ... + " """ + tempOutputJ$ + """"
    ... + " """ + tempRegimesJ$ + """"
    ... + " """ + tempStatsJ$ + """"
    ... + " " + fixed$(thermo_intensity, 4)
    ... + " " + fixed$(memory, 4)
    ... + " " + fixed$(convection, 4)
    ... + " " + string$(preserve_duration)
    ... + " " + aiModeLetter$
    ... + " " + fixed$(aI_strength, 4)
    ... + " " + string$(seed)
    ... + " " + fixed$(hopSec, 4)

runSystem_nocheck: pythonCall$ + " > """ + tempLogJ$ + """ 2>&1"

# ---- Verify output ----
if not fileReadable(tempOutput$)
    pythonError$ = "Python thermodynamic engine failed."
    if fileReadable(tempLog$)
        pythonError$ = pythonError$ + newline$ + newline$ + readFile$(tempLog$)
    endif
    @cleanUpTempFiles
    exitScript: pythonError$
endif

# ===========================================================================
# Stage 4 - Import Result
# ===========================================================================

appendInfoLine: "[4/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_thermo"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

# ===========================================================================
# Read stats & regimes for visualization
# ===========================================================================

# Parse stats
crystalPct$   = "?"
fluidPct$     = "?"
gasPct$       = "?"
plasmaPct$    = "?"
nTransitions$ = "?"
meanEntropy$  = "?"
peakEntropy$  = "?"
meanTemp$     = "?"
nClusters$    = "?"
nEvents$      = "?"
nRelocated$   = "?"
nEvaporated$  = "?"
nDuplicated$  = "?"
meanEventDur$ = "?"
analysisChannelStat$ = "?"
nCrossfades$ = "?"
nContiguous$ = "?"
outputDurationStat$ = "?"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "crystal_pct="
    crystalPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "fluid_pct="
    fluidPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "gas_pct="
    gasPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "plasma_pct="
    plasmaPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "transitions="
    nTransitions$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_entropy="
    meanEntropy$ = parseStatLine.result$
    @parseStatLine: statsText$, "peak_entropy="
    peakEntropy$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_temp="
    meanTemp$ = parseStatLine.result$
    @parseStatLine: statsText$, "clusters="
    nClusters$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_events="
    nEvents$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_relocated="
    nRelocated$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_evaporated="
    nEvaporated$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_duplicated="
    nDuplicated$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEventDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "analysis_channel="
    analysisChannelStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "crossfades="
    nCrossfades$ = parseStatLine.result$
    @parseStatLine: statsText$, "contiguous_joins="
    nContiguous$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outputDurationStat$ = parseStatLine.result$
endif

nRegimeFrames = 0
regimeHop = hopSec

if fileReadable(tempRegimes$)
    regimeText$ = readFile$(tempRegimes$)
    nRegimeFrames = 0
    @countLines: regimeText$
    nRegimeFrames = countLines.n - 1
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Creating visualization..."

    # Representative channels for honest before/after comparison.
    selectObject: sound
    if nChannels > 1
        Extract one channel: analysisChannel
        vizOrig = selected("Sound")
    else
        Copy: "vizOrig"
        vizOrig = selected("Sound")
    endif
    selectObject: resultSound
    outChannels = Get number of channels
    outVizChannel = min(analysisChannel, outChannels)
    if outChannels > 1
        Extract one channel: outVizChannel
        vizOut = selected("Sound")
    else
        Copy: "vizOut"
        vizOut = selected("Sound")
    endif
    selectObject: vizOrig
    peakOrigViz = Get absolute extremum: 0, 0, "none"
    selectObject: vizOut
    peakOutViz = Get absolute extremum: 0, 0, "none"
    vizPeak = max(peakOrigViz, peakOutViz) * 1.05
    if vizPeak < 0.01
        vizPeak = 0.01
    endif
    freqCeil = min(8000, sr / 2)

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Thermodynamic Event Relocation v2.3##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.18, "half", soundName$ + " | " + presetName$ + " | AI: " + aiModeLetter$ + " | Seed: " + string$(seed)

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.65, 1.35
    selectObject: vizOrig
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.4, 2.2
    Select inner viewport: 0.6, 7.7, 1.45, 2.15
    selectObject: vizOut
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Transformed"
    Text bottom: "yes", "Time (s)"

    # === Original Spectrogram ===
    Select outer viewport: 0, 8, 2.3, 3.5
    Select inner viewport: 0.6, 7.7, 2.4, 3.4

    selectObject: vizOrig
    To Spectrogram: 0.005, freqCeil, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, freqCeil, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original Spectrogram"

    removeObject: specOrig

    # === Transformed Spectrogram ===
    Select outer viewport: 0, 8, 3.5, 4.7
    Select inner viewport: 0.6, 7.7, 3.6, 4.6

    selectObject: vizOut
    To Spectrogram: 0.005, freqCeil, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, freqCeil, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Transformed Spectrogram"

    removeObject: specOut

    # === Regime Timeline ===
    Select outer viewport: 0, 8, 4.8, 5.8
    Select inner viewport: 0.6, 7.7, 4.9, 5.7

    Axes: 0, dur, -0.5, 3.5
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, dur, -0.5, 3.5

    if fileReadable(tempRegimes$) and nRegimeFrames > 0
        regimeLines$ = readFile$(tempRegimes$)
        lineStart = 1
        regIdx = 0
        for iLine from 1 to nRegimeFrames + 1
            lineEnd = index(mid$(regimeLines$, lineStart, length(regimeLines$)), newline$)
            if lineEnd = 0
                lineEnd = length(regimeLines$) - lineStart + 2
            endif
            currentLine$ = mid$(regimeLines$, lineStart, lineEnd - 1)
            lineStart = lineStart + lineEnd

            if iLine = 1
                # Skip header
            else
                regIdx = regIdx + 1
                rVal = number(currentLine$)
                tStart = (regIdx - 1) * regimeHop
                tEnd = regIdx * regimeHop
                if tEnd > dur
                    tEnd = dur
                endif

                if rVal = 0
                    Paint rectangle: "{0.3, 0.5, 0.9}", tStart, tEnd, rVal - 0.35, rVal + 0.35
                elsif rVal = 1
                    Paint rectangle: "{0.3, 0.75, 0.6}", tStart, tEnd, rVal - 0.35, rVal + 0.35
                elsif rVal = 2
                    Paint rectangle: "{0.9, 0.65, 0.2}", tStart, tEnd, rVal - 0.35, rVal + 0.35
                else
                    Paint rectangle: "{0.85, 0.25, 0.25}", tStart, tEnd, rVal - 0.35, rVal + 0.35
                endif
            endif
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Regime"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "State Timeline: Blue=Crystal | Green=Fluid | Orange=Gas | Red=Plasma"

    # === Intensity Comparison ===
    Select outer viewport: 0, 8, 5.9, 6.8
    Select inner viewport: 0.6, 7.7, 6.0, 6.7

    Axes: 0, dur, 30, 90
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, dur, 30, 90

    selectObject: vizOrig
    To Intensity: 100, 0, "yes"
    intOrig = selected("Intensity")
    selectObject: intOrig
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intOrig

    selectObject: vizOut
    To Intensity: 100, 0, "yes"
    intOut = selected("Intensity")
    selectObject: intOut
    Colour: "{0.3, 0.6, 0.5}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intOut

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Intensity: Grey = original | Green = transformed"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 7.0, 8.0
    Select inner viewport: 0.6, 7.7, 7.1, 7.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.8, "half", "Regime Distribution:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.55, "half", "Crystal: " + crystalPct$ + "% | Fluid: " + fluidPct$ + "% | Gas: " + gasPct$ + "% | Plasma: " + plasmaPct$ + "%"
    Text: 0.02, "left", 0.3, "half", "Transitions: " + nTransitions$ + " | Crossfades: " + nCrossfades$ + " | Contiguous joins: " + nContiguous$

    Font size: 7
    Colour: "Black"
    Text: 0.62, "left", 0.8, "half", "Parameters:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.62, "left", 0.55, "half", "Intensity: " + fixed$(thermo_intensity, 2) + " | Memory: " + fixed$(memory, 2) + " | Convect: " + fixed$(convection, 2)
    Text: 0.62, "left", 0.3, "half", "AI: " + aiModeLetter$ + " (str=" + fixed$(aI_strength, 2) + ") | Seed: " + string$(seed) + " | " + string$(nChannels) + "ch " + string$(sr) + "Hz"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: vizOrig, vizOut
    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "[5/5] Visualization skipped."
endif

# ===========================================================================
# Final Cleanup
# ===========================================================================
@cleanUpTempFiles

# ===========================================================================
# Summary
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_thermo"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Event relocation:"
appendInfoLine: "  Events: ", nEvents$, " (mean dur: ", meanEventDur$, " s)"
appendInfoLine: "  Relocated: ", nRelocated$, " | Evaporated: ", nEvaporated$, " | Duplicated: ", nDuplicated$
appendInfoLine: "  Crossfades: ", nCrossfades$, " | Contiguous joins: ", nContiguous$
appendInfoLine: "  Analysis channel: ", analysisChannelStat$, " | Output duration: ", outputDurationStat$, " s"
appendInfoLine: ""
appendInfoLine: "Regime distribution:"
appendInfoLine: "  Crystal: ", crystalPct$, "% | Fluid: ", fluidPct$, "% | Gas: ", gasPct$, "% | Plasma: ", plasmaPct$, "%"
appendInfoLine: "  Transitions: ", nTransitions$
appendInfoLine: "  Mean entropy: ", meanEntropy$, " | Peak: ", peakEntropy$
appendInfoLine: ""
appendInfoLine: "RMS original:    ", fixed$(rms_orig, 6)
appendInfoLine: "RMS transformed: ", fixed$(rms_out, 6)
if rms_orig > 1e-12
    appendInfoLine: "RMS ratio:       ", fixed$(rms_out / rms_orig, 3), "x"
else
    appendInfoLine: "RMS ratio:       n/a (silent input)"
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

procedure countLines: .text$
    .n = 0
    .remaining$ = .text$
    while length(.remaining$) > 0
        .nlPos = index(.remaining$, newline$)
        if .nlPos > 0
            .n = .n + 1
            .remaining$ = mid$(.remaining$, .nlPos + 1, length(.remaining$) - .nlPos)
        else
            if length(.remaining$) > 0
                .n = .n + 1
            endif
            .remaining$ = ""
        endif
    endwhile
endproc