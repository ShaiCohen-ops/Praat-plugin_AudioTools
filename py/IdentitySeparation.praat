# ============================================================
# Praat AudioTools - IdentitySeparation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Continuity + Analysis Pass
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
#   C — Identity recomposition (grouped by identity, harmonic->noisy)
#   D — Identity morphing (confidence-weighted blend)
#   E — Hybridization (spectral envelope shaping)
#
#   NOTE: With "Multi-channel" output format the audio is a raw
#   per-identity separation (one identity per channel) and the
#   resynthesis Mode is NOT applied to the audio.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.4:
#   - Modes A/B: backend removes artificial boundary amplitude holes.
#     A uses a smooth equal-power pan trajectory over the raw classified
#     timeline; B reconstructs the one-identity-at-a-time timeline directly.
#   - C no longer pads crossfade-shortened recomposition with trailing silence;
#     D/E continuous streams no longer loop crossfade-padding silence.
#   - Final <1-hop source tail is assigned to the last identity event.
#   - Conservative multichannel analysis fallback: channel 1 remains the
#     analysis channel unless it is <10% of the strongest channel RMS.
#     Praat and Python now use the same selected analysis channel.
#   - Dependency probe uses importlib.find_spec instead of importing the
#     heavy packages in a throwaway Python process.
#   - Behavioral onset density is now peaks/second (label correctness only).
#   - Input/output waveforms now share explicit time/amplitude scales.
#   - Summary panel now exposes the real feature -> GMM -> event -> mode
#     process plus mean posterior confidence.
#
# Changelog v1.3:
#   Resynthesis correctness pass (most changes are in the Python
#   backend identity_separation.py — see its header for detail):
#     - Modes D and E redesigned so they actually blend / hybridize
#       across identities (v1.2 fed them time-disjoint event layers,
#       so D degenerated to a gated original and E produced near-
#       silence). Mode C now orders identity blocks by descending
#       HNR (harmonic -> noisy) instead of an accidental no-op sort.
#     - "Stereo mix" now yields a 2-channel file for every mode.
#     - Multi-channel output no longer silently ignores the Mode; the
#       summary now states the Mode is not applied for multi output.
#   Praat-side:
#     - Form option labels: U+2014 em-dash -> ASCII "-" (consistent
#       with the v1.2 non-ASCII purge in rendered text).
#     - Summary/info now annotate "(layers; mode N/A)" when the
#       Multi-channel format is selected, so the displayed Mode no
#       longer disagrees with the written audio.
#     - Guarded RMS ratio against divide-by-zero on silent input.
#
# Changelog v1.2:
#
#   TIER 1 (Praat polish, audio bit-identical):
#     - Dropped 4 decorative `comment === ... ===` form rows
#       (Preset / Identity Discovery / Resynthesis Mode / Output).
#       Form: 11 rows -> 7. All 3 optionmenus already had colons.
#     - Visualization rewritten with suite styling. New layout:
#         Title bar (suite light) + metadata subtitle
#         Input waveform / Output waveform   (side-by-side headline)
#         Original spectrogram / Output spec  (side-by-side)
#         Per-Identity Summary Bars  (full width, signature panel)
#         Identity Timeline          (full width, color-coded runs)
#         Light-grey 3-line summary  (suite standard)
#       Pairing waveforms and spectrograms side-by-side makes
#       before/after comparison direct, which is the main use case
#       for those panels here.
#     - Output filename: `<name>_identity` ->
#       `<name>_identity_<preset>` so multiple runs with different
#       presets don't silently overwrite.
#
#   TIER 2 (bug fixes, audio bit-identical):
#     - FIXED: subtitle text overflowing into the Input Waveform
#       panel. v1.1 line 478 had `Text: 0.5, "centre", -1.2, ...`
#       with viewport 0,8,0,0.5 and axes 0,1,0,1. The mapping
#       (axis y=0 -> outer 0.5, axis y=1 -> outer 0) sent axis
#       y=-1.2 to outer y = 0.5 + 1.2*0.5 = 1.1 inches, which is
#       INSIDE the Input Waveform panel (outer 0.6-1.4). So the
#       subtitle was drawn ON TOP of the input waveform. v1.2 uses
#       the suite-standard subtitle position (axis y=-0.22 in a
#       0-0.65 title viewport) which puts the subtitle in the
#       panel-header strip just above the first content panel's
#       inner box.
#     - FIXED: unicode `->` (right arrow) in the summary panel
#       (v1.1 line 705 used `string$(nChannels) + "ch" + ... `
#       with a U+2192 RIGHTWARDS ARROW glyph). Per the suite
#       gotcha library, non-ASCII glyphs in `Text()` render
#       unpredictably across platforms (mojibake on Windows,
#       missing-glyph boxes elsewhere). Replaced with `->`.
#
#   TIER 3 (Python backend):
#     - identity_separation.py Mode A: removed `or True` dead
#       code (was `if n_channels >= 2 or True:`). The condition
#       was always true, making the else branch unreachable.
#       Cosmetic-only change; output is bit-identical.
#
#   Audio output is bit-identical to v1.1 for any input and
#   preset.
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
    pythonScript$ = defaultDirectory$ + "/identity_separation.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: identity_separation.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
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
form Acoustic Identity Separation v1.4
    optionmenu Preset: 1
        option Custom
        option Gentle (3 identities, layered)
        option Detailed (5 identities, layered)
        option Alternating voices (4 identities)
        option Recomposition (4 identities, grouped)
        option Morphing blend (3 identities)
        option Hybrid filter (3 identities)
    integer Number_of_identities 4
    optionmenu Mode: 1
        option A - Layered reconstruction
        option B - Identity alternation
        option C - Identity recomposition
        option D - Identity morphing
        option E - Hybridization
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
    modeNote$ = ""
else
    outFmt$ = "multi"
    modeNote$ = "  (layers; mode N/A)"
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
writeInfoLine:  "=== Acoustic Identity Separation v1.4 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Identities:    ", number_of_identities
appendInfoLine: "Mode:          ", modeLetter$, modeNote$
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

probeCmd$ = pythonCmd$ + " -c ""import importlib.util; pkgs=['numpy','scipy','soundfile','sklearn']; assert all(importlib.util.find_spec(p) for p in pkgs); open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
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

# ---- Choose a representative analysis channel conservatively ----
# Keep historical channel 1 whenever it carries normal energy.  Only fall back
# to the strongest channel when channel 1 is nearly empty relative to the file,
# so stereo material with asymmetric recording levels is not analysed as silence.
analysisChannel = 1
analysisFallback = 0
if nChannels > 1
    selectObject: sound
    Extract one channel: 1
    tmpCh1 = selected("Sound")
    rmsCh1 = Get root-mean-square: 0, 0
    removeObject: tmpCh1

    strongestChannel = 1
    strongestRms = rmsCh1
    for chTest from 2 to nChannels
        selectObject: sound
        Extract one channel: chTest
        tmpChTest = selected("Sound")
        thisRms = Get root-mean-square: 0, 0
        if thisRms > strongestRms
            strongestRms = thisRms
            strongestChannel = chTest
        endif
        removeObject: tmpChTest
    endfor

    if strongestRms > 1e-9 and rmsCh1 < 0.10 * strongestRms
        analysisChannel = strongestChannel
        analysisFallback = 1
    endif
endif

selectObject: sound
if nChannels > 1
    Extract one channel: analysisChannel
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif

if analysisFallback
    appendInfoLine: "  Analysis channel fallback: ch", analysisChannel, " (ch1 nearly silent)"
else
    appendInfoLine: "  Analysis channel: ch", analysisChannel
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
    ... + " " + string$(analysisChannel)

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
# v1.2: output filename now includes preset suffix.
compositeName$ = soundName$ + "_identity_" + presetName$
Rename: compositeName$
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration
outChans = Get number of channels

# Guard the RMS ratio against divide-by-zero on silent input
if rms_orig > 0
    rmsRatio$ = fixed$(rms_out / rms_orig, 3) + "x"
else
    rmsRatio$ = "n/a"
endif

# ===========================================================================
# Read stats file
# ===========================================================================

nIdMode$ = "?"
nIdDisc$ = "?"
nEventsID$ = "?"
nTransitionsID$ = "?"
meanEventDurID$ = "?"
meanConfidenceID$ = "?"
nFeaturesID$ = "?"
analysisChannelStat$ = "?"

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
    @parseStatLine: statsText$, "mean_confidence="
    meanConfidenceID$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_features="
    nFeaturesID$ = parseStatLine.result$
    @parseStatLine: statsText$, "analysis_channel="
    analysisChannelStat$ = parseStatLine.result$

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

# ---- Visualization comparison references ----
vizOutChannel = 1
if outChans > 1
    strongestOutRms = -1
    for chViz from 1 to outChans
        selectObject: resultSound
        Extract one channel: chViz
        tmpVizCh = selected("Sound")
        thisOutRms = Get root-mean-square: 0, 0
        if thisOutRms > strongestOutRms
            strongestOutRms = thisOutRms
            vizOutChannel = chViz
        endif
        removeObject: tmpVizCh
    endfor
endif

selectObject: sound
if nChannels > 1
    Extract one channel: analysisChannel
    tmpVizIn = selected("Sound")
else
    Copy: "tmpVizIn_idsep"
    tmpVizIn = selected("Sound")
endif
peakVizIn = Get absolute extremum: 0, 0, "None"

selectObject: resultSound
if outChans > 1
    Extract one channel: vizOutChannel
    tmpVizOut = selected("Sound")
else
    Copy: "tmpVizOut_idsep"
    tmpVizOut = selected("Sound")
endif
peakVizOut = Get absolute extremum: 0, 0, "None"
peakViz = max(peakVizIn, peakVizOut)
if peakViz < 0.001
    peakViz = 0.001
endif
maxDurViz = max(dur, durOut)
removeObject: tmpVizIn, tmpVizOut

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling, custom layout for 6 panels)
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    # v1.2: subtitle position fixed. v1.1 had axis y=-1.2 with
    # viewport 0,8,0,0.5 -> outer y=1.1 (inside Input Waveform).
    # v1.2 uses suite-standard axis y=-0.22 with viewport 0-0.65.
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##ACOUSTIC IDENTITY SEPARATION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  " + presetName$
        ... + "  |  Mode " + modeLetter$ + modeNote$
        ... + "  |  " + string$(number_of_identities) + " IDs"
        ... + "  |  Seed " + string$(seed)

    # ----------------------------------------------------------
    # PANEL A (left): INPUT WAVEFORM  (headline)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 1.85
    Select inner viewport: 0.55, 4.00, 0.95, 1.75

    selectObject: sound
    if nChannels > 1
        Extract one channel: analysisChannel
        tmpInWave = selected("Sound")
    else
        Copy: "tmpInWave_idsep"
        tmpInWave = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, maxDurViz, -peakViz, peakViz, "no", "Curve"
    removeObject: tmpInWave
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Input waveform  (" + fixed$(dur, 2) + " s)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL B (right): OUTPUT WAVEFORM  (headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 1.85
    Select inner viewport: 4.55, 7.75, 0.95, 1.75

    # Draw the strongest output channel on the SAME time/amplitude scale.
    selectObject: resultSound
    if outChans > 1
        Extract one channel: vizOutChannel
        tmpOutWav = selected("Sound")
    else
        Copy: "tmpOutWav_idsep"
        tmpOutWav = selected("Sound")
    endif
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, maxDurViz, -peakViz, peakViz, "no", "Curve"
    removeObject: tmpOutWav
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform  (mode " + modeLetter$ + ",  " + string$(outChans) + " ch)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL C (left): ORIGINAL SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 1.95, 4.10
    Select inner viewport: 0.55, 4.00, 2.10, 3.95

    selectObject: sound
    if nChannels > 1
        Extract one channel: analysisChannel
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif

    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original spectrogram"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specOrig, tmpOrig

    # ----------------------------------------------------------
    # PANEL D (right): OUTPUT SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 1.95, 4.10
    Select inner viewport: 4.55, 7.75, 2.10, 3.95

    selectObject: resultSound
    if outChans > 1
        Extract one channel: vizOutChannel
        tmpOut = selected("Sound")
    else
        Copy: "tmpOut"
        tmpOut = selected("Sound")
    endif

    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output spectrogram  (mode " + modeLetter$ + ")"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specOut, tmpOut

    # ----------------------------------------------------------
    # PANEL E: PER-IDENTITY SUMMARY BARS  (full width, signature)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.20, 5.40
    Select inner viewport: 0.55, 7.72, 4.35, 5.30

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    # Define identity colours (up to 8)
    idCol_0$ = "{0.20, 0.50, 0.80}"
    idCol_1$ = "{0.80, 0.30, 0.30}"
    idCol_2$ = "{0.30, 0.70, 0.40}"
    idCol_3$ = "{0.80, 0.60, 0.20}"
    idCol_4$ = "{0.60, 0.30, 0.70}"
    idCol_5$ = "{0.20, 0.70, 0.70}"
    idCol_6$ = "{0.70, 0.50, 0.30}"
    idCol_7$ = "{0.50, 0.50, 0.50}"

    nIdShow = number_of_identities
    if nIdShow > 8
        nIdShow = 8
    endif

    rowHeight = 0.85 / nIdShow

    for idDraw from 0 to nIdShow - 1
        yTop = 0.92 - idDraw * rowHeight
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
        Paint rectangle: idCol_'idDraw'$, 0.02, 0.02 + barWidth * 0.30, yBot, yTop

        # Label (left of bar end)
        Font size: 6
        Colour: "Black"
        label$ = "ID " + string$(idDraw) + ": " + thisPct$ + "%"
        if thisBehav$ <> "" and thisBehav$ <> "?"
            label$ = label$ + "  (" + thisBehav$ + ")"
        endif
        Text: 0.36, "left", (yTop + yBot) / 2, "half", label$

        # Stats on right
        Colour: "{0.40, 0.40, 0.45}"
        stats$ = ""
        if thisHnr$ <> "" and thisHnr$ <> "?"
            stats$ = "HNR:" + thisHnr$
        endif
        if thisFlat$ <> "" and thisFlat$ <> "?"
            stats$ = stats$ + "  flat:" + thisFlat$
        endif
        if thisDur$ <> "" and thisDur$ <> "?"
            stats$ = stats$ + "  mean dur:" + thisDur$ + "s"
        endif
        Text: 0.72, "left", (yTop + yBot) / 2, "half", stats$
    endfor

    Colour: "Black"
    Line width: 1
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text top: "no", "Per-identity profiles  (bar width = % of total frames)"

    # ----------------------------------------------------------
    # PANEL F: IDENTITY TIMELINE  (full width, color-coded runs)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.50, 6.30
    Select inner viewport: 0.55, 7.72, 5.65, 6.20

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
        Colour: "{0.55, 0.55, 0.60}"
        Text: dur / 2, "centre", 0.5, "half", "(timeline data not available)"
    endif

    # Identity-number labels for long runs
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
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Identity timeline  (color = identity, label = ID number)"
    Font size: 6
    Text left: "yes", "ID"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL G: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.40, 7.10
    Select inner viewport: 0.55, 7.72, 6.47, 7.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.82, "half",
        ... "##PROCESS##  Praat voice/formant features + Python spectral descriptors"
        ... + "  ->  RobustScaler  ->  GMM (" + string$(number_of_identities) + " IDs)"
        ... + "  ->  identity runs  ->  Mode " + modeLetter$ + modeNote$

    Text: 0.02, "left", 0.50, "half",
        ... "Features: " + nFeaturesID$
        ... + "  |  Mean posterior confidence: " + meanConfidenceID$
        ... + "  |  Events: " + nEventsID$
        ... + "  |  Transitions: " + nTransitionsID$
        ... + "  |  Analysis ch: " + analysisChannelStat$

    Text: 0.02, "left", 0.18, "half",
        ... "QC  Input " + string$(nChannels) + "ch -> Output " + string$(outChans) + "ch"
        ... + "  |  RMS " + fixed$(rms_orig, 4) + " -> " + fixed$(rms_out, 4)
        ... + " (" + rmsRatio$ + ")"
        ... + "  |  Mean event: " + meanEventDurID$ + " s"
        ... + "  |  Seed: " + string$(seed)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
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
appendInfoLine: "Output: ", compositeName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Identity separation:"
appendInfoLine: "  Identities: ", nIdDisc$
appendInfoLine: "  Events: ", nEventsID$, " (mean dur: ", meanEventDurID$, " s)"
appendInfoLine: "  Transitions: ", nTransitionsID$
appendInfoLine: "  Mean posterior confidence: ", meanConfidenceID$
appendInfoLine: "  Analysis channel: ", analysisChannelStat$
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
appendInfoLine: "RMS ratio:       ", rmsRatio$

selectObject: resultSound

if play_result
    Play
endif
