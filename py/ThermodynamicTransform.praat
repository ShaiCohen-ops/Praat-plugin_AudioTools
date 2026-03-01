# ============================================================
# Praat AudioTools - ThermodynamicTransform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Thermodynamic audio transformation with AI state discovery.
#   Analyzes acoustic structure → discovers phase regimes via ML →
#   applies regime-dependent spectral transforms (Crystal/Fluid/Gas/Plasma).
#   Powered by Python (numpy, scipy, scikit-learn, soundfile).
#
#   Parameters:
#   - Macro intensity: overall transformation strength (0-1)
#   - Memory:          state machine inertia/hysteresis (0-1)
#   - Diffusion:       spectral smearing in Fluid regime (0-1)
#   - Crystallization:  bias toward stable/Crystal regimes (0-1)
#   - AI mode:         A=clustering  B=predictive  C=learned-entropy
#   - AI strength:     AI influence on regime assignment (0-1)
#   - Seed:            for full deterministic reproducibility
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

# ---- PATHS (plugin-relative for distribution) ----
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/thermodynamic_transform.py"
tempInput$   = pluginDir$ + "temp_thermo_input.wav"
tempCSV$     = pluginDir$ + "temp_thermo_features.csv"
tempOutput$  = pluginDir$ + "temp_thermo_output.wav"
tempRegimes$ = pluginDir$ + "temp_thermo_regimes.txt"
tempStats$   = pluginDir$ + "temp_thermo_stats.txt"

# Verify Python script exists
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- FORM ----
form Thermodynamic Transform v1.0
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
writeInfoLine:  "=== Thermodynamic Transform v2.0 (Event Relocation) ==="
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
# Stage 1 — Feature Extraction
# ===========================================================================

appendInfoLine: "[1/5] Extracting acoustic features..."

hopSec = 0.01
nFrames = floor(dur / hopSec)
if nFrames < 10
    exitScript: "Sound is too short for analysis (need > 0.1 s)."
endif

# ---- Create analysis objects ----
selectObject: sound

# Work on channel 1 for analysis
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
Save as WAV file: tempInput$

selectObject: featureTable
Save as comma-separated file: tempCSV$

# ---- Cleanup analysis objects ----
removeObject: analysisMono, pitchObj, harmObj, intObj, formantObj, featureTable

# ===========================================================================
# Stage 2–5 — Call Python
# ===========================================================================

appendInfoLine: "[3/5] Running Python engine (this may take a while)..."

# ---- Robust Python detection ----
# On Windows, "py" and "python" can resolve to different installations.
# We probe each candidate by asking it to import sklearn and write a marker.
probeMarker$ = pluginDir$ + "temp_pyprobe.ok"

# Candidate list (order matters — first success wins)
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

    # Delete marker if leftover
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    # Probe: import all required packages; write marker on success
    probeCode$ = "import numpy,soundfile,scipy,sklearn; open(r'" + probeMarker$ + "','w').write('ok')"
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
    # Cleanup before exit
    deleteFile: tempInput$
    deleteFile: tempCSV$
    exitScript: "Cannot find a Python installation with the required packages." + newline$
        ... + "" + newline$
        ... + "Tried: python, py, py -3, python3" + newline$
        ... + "" + newline$
        ... + "Please install the packages into your Python and ensure it is in PATH:" + newline$
        ... + "  pip install numpy soundfile scipy scikit-learn" + newline$
        ... + "" + newline$
        ... + "To check which Python pip uses:   pip --version" + newline$
        ... + "Then call that same Python, e.g.:  python --version"
endif

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempRegimes$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + fixed$(thermo_intensity, 4)
    ... + " " + fixed$(memory, 4)
    ... + " " + fixed$(convection, 4)
    ... + " " + string$(preserve_duration)
    ... + " " + aiModeLetter$
    ... + " " + fixed$(aI_strength, 4)
    ... + " " + string$(seed)
    ... + " " + fixed$(hopSec, 4)

# ---- Verify output ----
if not fileReadable(tempOutput$)
    # Cleanup on failure
    deleteFile: tempInput$
    deleteFile: tempCSV$
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    exitScript: "Python thermodynamic engine failed." + newline$
        ... + "" + newline$
        ... + "Python command used: " + pythonCmd$ + newline$
        ... + "" + newline$
        ... + "Possible causes:" + newline$
        ... + "  - A package version is incompatible with Python 3.7" + newline$
        ... + "  - Input audio is corrupt or empty" + newline$
        ... + "  - Out of memory for very long files" + newline$
        ... + "" + newline$
        ... + "Run this in your terminal to see the exact error:" + newline$
        ... + "  " + pythonCmd$ + " """ + pythonScript$ + """ --help"
endif

# ===========================================================================
# Import Result
# ===========================================================================

appendInfoLine: "[4/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_thermo"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

# ===========================================================================
# Read stats file for visualization
# ===========================================================================

# Parse stats
crystalPct$ = "?"
fluidPct$ = "?"
gasPct$ = "?"
plasmaPct$ = "?"
nTransitions$ = "?"
meanEntropy$ = "?"
peakEntropy$ = "?"
meanTemp$ = "?"
nClusters$ = "?"
nEvents$ = "?"
nRelocated$ = "?"
nEvaporated$ = "?"
nDuplicated$ = "?"
meanEventDur$ = "?"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    # Parse key=value lines
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
endif

# ===========================================================================
# Read regime file for timeline visualization
# ===========================================================================

# Count regime frames
nRegimeFrames = 0
regimeHop = hopSec

if fileReadable(tempRegimes$)
    regimeText$ = readFile$(tempRegimes$)
    # First line is hop_sec=..., rest are regime indices
    nRegimeFrames = 0
    @countLines: regimeText$
    nRegimeFrames = countLines.n - 1
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Thermodynamic Event Relocation##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | AI: " + aiModeLetter$ + " | Seed: " + string$(seed)

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.65, 1.35
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.4, 2.2
    Select inner viewport: 0.6, 7.7, 1.45, 2.15
    selectObject: resultSound
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Transformed"
    Text bottom: "yes", "Time (s)"

    # === Original Spectrogram ===
    Select outer viewport: 0, 8, 2.3, 3.5
    Select inner viewport: 0.6, 7.7, 2.4, 3.4

    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original Spectrogram"

    removeObject: specOrig, tmpOrig

    # === Transformed Spectrogram ===
    Select outer viewport: 0, 8, 3.5, 4.7
    Select inner viewport: 0.6, 7.7, 3.6, 4.6

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpOut = selected("Sound")
    else
        Copy: "tmpOut"
        tmpOut = selected("Sound")
    endif

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Transformed Spectrogram"

    removeObject: specOut, tmpOut

    # === Regime Timeline ===
    Select outer viewport: 0, 8, 4.8, 5.8
    Select inner viewport: 0.6, 7.7, 4.9, 5.7

    Axes: 0, dur, -0.5, 3.5
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, dur, -0.5, 3.5

    # Draw regime bands from file (if available)
    if fileReadable(tempRegimes$) and nRegimeFrames > 0
        # Read regime data line by line
        regimeLines$ = readFile$(tempRegimes$)
        lineStart = 1
        regIdx = 0
        for iLine from 1 to nRegimeFrames + 1
            # Find end of current line
            lineEnd = index(mid$(regimeLines$, lineStart, length(regimeLines$)), newline$)
            if lineEnd = 0
                lineEnd = length(regimeLines$) - lineStart + 2
            endif
            currentLine$ = mid$(regimeLines$, lineStart, lineEnd - 1)
            lineStart = lineStart + lineEnd

            # Skip header line (hop_sec=...)
            if iLine = 1
                # This is the header; skip
            else
                regIdx = regIdx + 1
                rVal = number(currentLine$)
                tStart = (regIdx - 1) * regimeHop
                tEnd = regIdx * regimeHop
                if tEnd > dur
                    tEnd = dur
                endif

                # Paint by regime colour
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

    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrigI = selected("Sound")
    else
        Copy: "tmpOrigI"
        tmpOrigI = selected("Sound")
    endif

    To Intensity: 100, 0, "yes"
    intOrig = selected("Intensity")
    selectObject: intOrig
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intOrig, tmpOrigI

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpOutI = selected("Sound")
    else
        Copy: "tmpOutI"
        tmpOutI = selected("Sound")
    endif

    To Intensity: 100, 0, "yes"
    intOut = selected("Intensity")
    selectObject: intOut
    Colour: "{0.3, 0.6, 0.5}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intOut, tmpOutI

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
    Text: 0.02, "left", 0.3, "half", "Transitions: " + nTransitions$ + " | Mean S: " + meanEntropy$ + " | Peak S: " + peakEntropy$ + " | Mean T: " + meanTemp$

    Font size: 7
    Colour: "Black"
    Text: 0.62, "left", 0.8, "half", "Parameters:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.62, "left", 0.55, "half", "Intensity: " + fixed$(thermo_intensity, 2) + " | Memory: " + fixed$(memory, 2) + " | Convect: " + fixed$(convection, 2)
    Text: 0.62, "left", 0.3, "half", "AI: " + aiModeLetter$ + " (str=" + fixed$(aI_strength, 2) + ") | Seed: " + string$(seed) + " | " + string$(nChannels) + "ch " + string$(sr) + "Hz"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "[5/5] Visualization skipped."
endif

# ===========================================================================
# Cleanup — always delete temp files
# ===========================================================================

deleteFile: tempInput$
deleteFile: tempCSV$
deleteFile: tempOutput$
if fileReadable(tempRegimes$)
    deleteFile: tempRegimes$
endif
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
appendInfoLine: "Output: ", soundName$, "_thermo"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Event relocation:"
appendInfoLine: "  Events: ", nEvents$, " (mean dur: ", meanEventDur$, " s)"
appendInfoLine: "  Relocated: ", nRelocated$, " | Evaporated: ", nEvaporated$, " | Duplicated: ", nDuplicated$
appendInfoLine: ""
appendInfoLine: "Regime distribution:"
appendInfoLine: "  Crystal: ", crystalPct$, "% | Fluid: ", fluidPct$, "% | Gas: ", gasPct$, "% | Plasma: ", plasmaPct$, "%"
appendInfoLine: "  Transitions: ", nTransitions$
appendInfoLine: "  Mean entropy: ", meanEntropy$, " | Peak: ", peakEntropy$
appendInfoLine: ""
appendInfoLine: "RMS original:    ", fixed$(rms_orig, 6)
appendInfoLine: "RMS transformed: ", fixed$(rms_out, 6)
appendInfoLine: "RMS ratio:       ", fixed$(rms_out / rms_orig, 3), "x"

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
