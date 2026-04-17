# ============================================================
# Praat AudioTools - IdentitySeparation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Acoustic Identity Separation & Resynthesis.
#   Discovers latent acoustic identities inside a recording via AI
#   clustering, then reorganizes material by identity.
#   Powered by Python (numpy, scipy, scikit-learn, soundfile).
#
#   Modes:
#   A — Layered reconstruction (spatial separation)
#   B — Identity alternation (one at a time)
#   C — Identity recomposition (grouped by identity)
#   D — Identity morphing (confidence-weighted blend)
#   E — Hybridization (spectral envelope shaping)
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
pythonScript$ = pluginDir$ + "py/identity_separation.py"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

tempInput$   = temporaryDirectory$ + "/temp_idsep_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_idsep_features.csv"
tempOutput$  = temporaryDirectory$ + "/temp_idsep_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_idsep_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_idsep_probe.ok"

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
form Acoustic Identity Separation v1.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Gentle (3 identities, layered)
        option Detailed (5 identities, layered)
        option Alternating voices (4 identities)
        option Recomposition (4 identities, grouped)
        option Morphing blend (3 identities)
        option Hybrid filter (3 identities)
    comment === Identity Discovery ===
    integer Number_of_identities 4
    comment === Resynthesis Mode ===
    optionmenu Mode: 1
        option A — Layered reconstruction
        option B — Identity alternation
        option C — Identity recomposition
        option D — Identity morphing
        option E — Hybridization
    comment === Output ===
    optionmenu Output_format: 1
        option Stereo mix
        option Multi-channel (1 identity per channel)
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    number_of_identities = 3
    mode = 1
    output_format = 1
    presetName$ = "Gentle3"
elsif preset = 3
    number_of_identities = 5
    mode = 1
    output_format = 1
    presetName$ = "Detailed5"
elsif preset = 4
    number_of_identities = 4
    mode = 2
    output_format = 1
    presetName$ = "Alternating"
elsif preset = 5
    number_of_identities = 4
    mode = 3
    output_format = 1
    presetName$ = "Recomposed"
elsif preset = 6
    number_of_identities = 3
    mode = 4
    output_format = 1
    presetName$ = "Morphing"
elsif preset = 7
    number_of_identities = 3
    mode = 5
    output_format = 1
    presetName$ = "Hybrid"
else
    presetName$ = "Custom"
endif

# Resolve mode letter
modeLetter$ = mid$("ABCDE", mode, 1)

# Resolve output format string
if output_format = 1
    outFmt$ = "stereo"
else
    outFmt$ = "multi"
endif

# Clamp identities
if number_of_identities < 2
    number_of_identities = 2
endif
if number_of_identities > 8
    number_of_identities = 8
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Acoustic Identity Separation v1.1 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Identities:    ", number_of_identities
appendInfoLine: "Mode:          ", modeLetter$
appendInfoLine: "Output format: ", outFmt$
appendInfoLine: "Seed:          ", seed
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

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile, sklearn; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile scikit-learn"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Feature Extraction
# ===========================================================================

appendInfoLine: "[2/5] Extracting acoustic features..."

hopSec = 0.01
nFrames = floor(dur / hopSec)
if nFrames < 10
    @cleanUpTempFiles
    exitScript: "Sound is too short for analysis (need > 0.1 s)."
endif

# ---- Create analysis objects ----
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

selectObject: analysisMono
formantObj = To Formant (burg): 0.01, 5, 5500, 0.025, 50

# ---- Build feature table ----
Create Table with column names: "features", nFrames, "time pitch voiced hnr intensity f1 f2 f3 f4 b1 b2 b3 b4"
featureTable = selected("Table")

for i from 1 to nFrames
    t = (i - 0.5) * hopSec
    if t > dur
        t = dur
    endif

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
selectObject: sound
Save as WAV file: tempInput$

selectObject: featureTable
Save as comma-separated file: tempCSV$

# ---- Cleanup analysis objects ----
removeObject: analysisMono, pitchObj, harmObj, intObj, formantObj, featureTable

# ===========================================================================
# Stage 3 — Call Python
# ===========================================================================

appendInfoLine: "[3/5] Running Python engine (this may take a while)..."

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + modeLetter$
    ... + " " + string$(number_of_identities)
    ... + " " + outFmt$
    ... + " " + string$(seed)
    ... + " " + fixed$(hopSec, 4)

runSystem_nocheck: pyCmd$

# ---- Verify output ----
if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python identity separation engine failed." + newline$ + "Check terminal/console for details."
endif

# ===========================================================================
# Stage 4 — Import Result
# ===========================================================================

appendInfoLine: "[4/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_identity"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration
outChans = Get number of channels

# ===========================================================================
# Read stats file
# ===========================================================================

nIdMode$ = "?"
nIdDisc$ = "?"
nEventsID$ = "?"
nTransitionsID$ = "?"
meanEventDurID$ = "?"

# Read per-identity stats (up to 8 identities)
for idxStat from 0 to 7
    id_'idxStat'_pct$ = ""
    id_'idxStat'_behavior$ = ""
    id_'idxStat'_hnr$ = ""
    id_'idxStat'_flatness$ = ""
    id_'idxStat'_mean_dur$ = ""
endfor

nTimelineRuns = 0

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

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "mode="
    nIdMode$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_identities="
    nIdDisc$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_events="
    nEventsID$ = parseStatLine.result$
    @parseStatLine: statsText$, "transitions="
    nTransitionsID$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEventDurID$ = parseStatLine.result$

    for idxStat from 0 to number_of_identities - 1
        prefix$ = "id_" + string$(idxStat) + "_"

        @parseStatLine: statsText$, prefix$ + "pct="
        id_'idxStat'_pct$ = parseStatLine.result$
        @parseStatLine: statsText$, prefix$ + "behavior="
        id_'idxStat'_behavior$ = parseStatLine.result$
        @parseStatLine: statsText$, prefix$ + "hnr="
        id_'idxStat'_hnr$ = parseStatLine.result$
        @parseStatLine: statsText$, prefix$ + "flatness="
        id_'idxStat'_flatness$ = parseStatLine.result$
        @parseStatLine: statsText$, prefix$ + "mean_dur="
        id_'idxStat'_mean_dur$ = parseStatLine.result$
    endfor

    # Parse identity timeline runs
    @parseStatLine: statsText$, "n_timeline_runs="
    nTimelineRuns$ = parseStatLine.result$
    nTimelineRuns = 0
    if nTimelineRuns$ <> "?"
        nTimelineRuns = number(nTimelineRuns$)
    endif
    if nTimelineRuns > 2000
        nTimelineRuns = 2000
    endif

    for tlIdx from 0 to nTimelineRuns - 1
        @parseStatLine: statsText$, "tl_" + string$(tlIdx) + "="
        tlRaw$ = parseStatLine.result$
        # Format: "identity,start_sec,end_sec"
        tl_'tlIdx'_id = 0
        tl_'tlIdx'_start = 0
        tl_'tlIdx'_end = 0
        if tlRaw$ <> "?"
            comma1 = index(tlRaw$, ",")
            if comma1 > 0
                tl_'tlIdx'_id = number(left$(tlRaw$, comma1 - 1))
                rest$ = mid$(tlRaw$, comma1 + 1, length(tlRaw$) - comma1)
                comma2 = index(rest$, ",")
                if comma2 > 0
                    tl_'tlIdx'_start = number(left$(rest$, comma2 - 1))
                    tl_'tlIdx'_end = number(mid$(rest$, comma2 + 1, length(rest$) - comma2))
                endif
            endif
        endif
    endfor
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
    Text: 0.5, "centre", 0.6, "half", "##Acoustic Identity Separation##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | Mode: " + modeLetter$ + " | IDs: " + string$(number_of_identities) + " | Seed: " + string$(seed)

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

    # For multi-channel output, draw ch1
    if outChans > 1
        selectObject: resultSound
        Extract one channel: 1
        tmpOutWav = selected("Sound")
        Colour: "{0.2, 0.5, 0.7}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: tmpOutWav
    else
        selectObject: resultSound
        Colour: "{0.2, 0.5, 0.7}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
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
    Select outer viewport: 0, 8, 3.5, 4.7
    Select inner viewport: 0.6, 7.7, 3.6, 4.6

    selectObject: resultSound
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
    Text top: "no", "Output spectrogram (mode " + modeLetter$ + ")"
    removeObject: specOut, tmpOut

    # === Per-Identity Summary Bars ===
    Select outer viewport: 0, 8, 4.8, 5.9
    Select inner viewport: 0.6, 7.7, 4.9, 5.8

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "##Identity Profiles##"

    # Define identity colours (up to 8)
    idCol_0$ = "{0.2, 0.5, 0.8}"
    idCol_1$ = "{0.8, 0.3, 0.3}"
    idCol_2$ = "{0.3, 0.7, 0.4}"
    idCol_3$ = "{0.8, 0.6, 0.2}"
    idCol_4$ = "{0.6, 0.3, 0.7}"
    idCol_5$ = "{0.2, 0.7, 0.7}"
    idCol_6$ = "{0.7, 0.5, 0.3}"
    idCol_7$ = "{0.5, 0.5, 0.5}"

    nIdShow = number_of_identities
    if nIdShow > 8
        nIdShow = 8
    endif

    rowHeight = 0.8 / nIdShow

    for idDraw from 0 to nIdShow - 1
        yTop = 0.85 - idDraw * rowHeight
        yBot = yTop - rowHeight * 0.85

        # Get percentage for bar width
        thisPct$ = id_'idDraw'_pct$
        thisBehav$ = id_'idDraw'_behavior$
        thisHnr$ = id_'idDraw'_hnr$
        thisFlat$ = id_'idDraw'_flatness$
        thisDur$ = id_'idDraw'_mean_dur$

        barWidth = 0
        if thisPct$ <> "" and thisPct$ <> "?"
            barWidth = number(thisPct$) / 100
        endif
        if barWidth > 1
            barWidth = 1
        endif

        # Draw bar
        Colour: idCol_'idDraw'$
        Paint rectangle: idCol_'idDraw'$, 0.02, 0.02 + barWidth * 0.35, yBot, yTop

        # Label
        Font size: 6
        Colour: "Black"
        label$ = "ID " + string$(idDraw) + ": " + thisPct$ + "% "
        if thisBehav$ <> "" and thisBehav$ <> "?"
            label$ = label$ + "(" + thisBehav$ + ")"
        endif
        Text: 0.40, "left", (yTop + yBot) / 2, "half", label$

        # Stats on right
        Colour: "{0.4, 0.4, 0.4}"
        stats$ = ""
        if thisHnr$ <> "" and thisHnr$ <> "?"
            stats$ = "HNR:" + thisHnr$
        endif
        if thisFlat$ <> "" and thisFlat$ <> "?"
            stats$ = stats$ + "  flat:" + thisFlat$
        endif
        if thisDur$ <> "" and thisDur$ <> "?"
            stats$ = stats$ + "  dur:" + thisDur$ + "s"
        endif
        Text: 0.72, "left", (yTop + yBot) / 2, "half", stats$
    endfor

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Identity Timeline ===
    Select outer viewport: 0, 8, 6.0, 6.8
    Select inner viewport: 0.6, 7.7, 6.1, 6.7

    Axes: 0, dur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, dur, 0, 1

    # Draw color-coded runs from the parsed timeline
    if nTimelineRuns > 0
        for tlDraw from 0 to nTimelineRuns - 1
            thisId = tl_'tlDraw'_id
            thisStart = tl_'tlDraw'_start
            thisEnd = tl_'tlDraw'_end
            if thisId >= 0 and thisId <= 7
                Paint rectangle: idCol_'thisId'$, thisStart, thisEnd, 0.05, 0.95
            endif
        endfor
    else
        # Fallback if no timeline data
        Font size: 6
        Colour: "{0.5, 0.5, 0.5}"
        Text: dur / 2, "centre", 0.5, "half", "(timeline data not available)"
    endif

    # Draw thin identity-number labels for long runs
    Font size: 5
    Colour: "White"
    if nTimelineRuns > 0
        for tlLabel from 0 to nTimelineRuns - 1
            runDur = tl_'tlLabel'_end - tl_'tlLabel'_start
            if runDur > dur * 0.03
                midT = (tl_'tlLabel'_start + tl_'tlLabel'_end) / 2
                Text: midT, "centre", 0.5, "half", string$(tl_'tlLabel'_id)
            endif
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "ID"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Identity Timeline (colour = identity)"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 7.0, 8.0
    Select inner viewport: 0.6, 7.7, 7.1, 7.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.8, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.55, "half", "Events: " + nEventsID$ + " | Transitions: " + nTransitionsID$ + " | Mean dur: " + meanEventDurID$ + " s"
    Text: 0.02, "left", 0.3, "half", "RMS orig: " + fixed$(rms_orig, 4) + " | RMS out: " + fixed$(rms_out, 4) + " | Ratio: " + fixed$(rms_out / rms_orig, 3) + "x"

    Font size: 7
    Colour: "Black"
    Text: 0.62, "left", 0.8, "half", "Settings:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.62, "left", 0.55, "half", "Mode: " + modeLetter$ + " | IDs: " + string$(number_of_identities) + " | Format: " + outFmt$
    Text: 0.62, "left", 0.3, "half", "Seed: " + string$(seed) + " | " + string$(nChannels) + "ch→" + string$(outChans) + "ch | " + string$(sr) + "Hz"

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
@cleanUpTempFiles

# ===========================================================================
# Summary
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_identity"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Identity separation:"
appendInfoLine: "  Identities: ", nIdDisc$
appendInfoLine: "  Events: ", nEventsID$, " (mean dur: ", meanEventDurID$, " s)"
appendInfoLine: "  Transitions: ", nTransitionsID$
appendInfoLine: ""

for idxInfo from 0 to number_of_identities - 1
    pctStr$ = id_'idxInfo'_pct$
    behavStr$ = id_'idxInfo'_behavior$
    hnrStr$ = id_'idxInfo'_hnr$
    flatStr$ = id_'idxInfo'_flatness$
    durStr$ = id_'idxInfo'_mean_dur$
    appendInfoLine: "  ID ", idxInfo, ": ", pctStr$, "% | ", behavStr$, " | HNR=", hnrStr$, " flat=", flatStr$
endfor

appendInfoLine: ""
appendInfoLine: "RMS original:    ", fixed$(rms_orig, 6)
appendInfoLine: "RMS output:      ", fixed$(rms_out, 6)
appendInfoLine: "RMS ratio:       ", fixed$(rms_out / rms_orig, 3), "x"

selectObject: resultSound

if play_result
    Play
endif