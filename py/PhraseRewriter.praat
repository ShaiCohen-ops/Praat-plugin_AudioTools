# ============================================================
# Praat AudioTools - PhraseRewriter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Wired inert per-mode knobs; per-mode control hints
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phrase Rewriter — Compositional Archetype Engine
#
#   An event-based acoustic recomposition system for Praat.
#   The script automatically segments a selected Sound into
#   phrase events, extracts acoustic feature trajectories
#   (pitch, intensity, HNR, formants), and generates a
#   rewrite plan driven by one of eight compositional
#   archetypes (Constellation, Cloud, Resonance, Center,
#   Becoming, Distance, Mass, Multiplication).
#
#   Each archetype applies a distinct structural logic to
#   select, order, scale, and layer source events. Python
#   handles all planning and rendering; Praat remains the
#   front-end and user environment.
#
#   The system functions as a structural AI engine for
#   phrase-level acoustic form transformation.
#
# Citation:
#   Cohen, S. (2026). Phrase Rewriter:
#   Compositional Archetype Engine for Praat.
#   Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- PATHS & NORMALIZATION ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)
pythonScript$ = pluginDir$ + "py/phrase_rewriter.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/phrase_rewriter.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: phrase_rewriter.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempInput$   = tempDir$ + "temp_phraserw_input.wav"
tempCSV$     = tempDir$ + "temp_phraserw_features.csv"
tempOutput$  = tempDir$ + "temp_phraserw_output.wav"
tempStats$   = tempDir$ + "temp_phraserw_stats.txt"
probeScript$ = tempDir$ + "temp_phraserw_probe.py"
probeMarker$ = tempDir$ + "temp_phraserw_probe.ok"

# ---- INITIAL CLEANUP ----
@cleanUpTempFiles

# ---- EARLY PYTHON DEPENDENCY PROBE ----
writeFileLine: probeScript$, "import sys"
appendFileLine: probeScript$, "try:"
appendFileLine: probeScript$, "    import numpy, soundfile, scipy"
appendFileLine: probeScript$, "    with open(r'" + probeMarker$ + "', 'w') as f: f.write('ok')"
appendFileLine: probeScript$, "except ImportError:"
appendFileLine: probeScript$, "    sys.exit(1)"

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

    runSystem_nocheck: tryCmd$ + " """ + probeScript$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1 ; Break early
    endif
endfor

deleteFile: probeScript$

if pythonCmd$ = ""
    exitScript: "Cannot find a Python installation with the required packages." + newline$
        ... + "Please install them via: pip install numpy scipy soundfile"
endif

# ---- UI FORM ----
form Phrase Rewriter
    optionmenu Mode: 1
        option Constellation
        option Cloud
        option Resonance
        option Center
        option Becoming
        option Distance
        option Mass
        option Multiplication
    real Preserve_source 0.60
    real Rewrite_intensity 0.55
    optionmenu Duration_policy: 1
        option keep near original
        option allow shorter
        option allow longer
    real Variation_amount 0.20
    comment (Preserve / Intensity / Variation act differently per mode — Info window lists this mode's primary controls)
    integer Seed 42
    boolean Run_variation 0
    boolean Draw_visualization 1
    boolean Draw_transformation_map 1
    boolean Play_result 1
    comment ── Constellation controls (ignored by other modes) ──────────────
    real Pitch_shift_semitones 0.0
    real Fragment_length_scale 1.0
endform

if preserve_source < 0
    preserve_source = 0
endif
if preserve_source > 1
    preserve_source = 1
endif
if rewrite_intensity < 0
    rewrite_intensity = 0
endif
if rewrite_intensity > 1
    rewrite_intensity = 1
endif
if variation_amount < 0
    variation_amount = 0
endif
if variation_amount > 1
    variation_amount = 1
endif
if pitch_shift_semitones < -24
    pitch_shift_semitones = -24
endif
if pitch_shift_semitones > 24
    pitch_shift_semitones = 24
endif
if fragment_length_scale < 0.10
    fragment_length_scale = 0.10
endif
if fragment_length_scale > 4.0
    fragment_length_scale = 4.0
endif

modeName$ = "Constellation"
modeKnobs$ = "preserve (seed density), intensity (fragmentation); variation subtle"
if mode = 2
    modeName$ = "Cloud"
    modeKnobs$ = "intensity (density/overlap), variation (scatter), preserve (length/gain)"
elsif mode = 3
    modeName$ = "Resonance"
    modeKnobs$ = "intensity (sustain/resonance), preserve (event count/gain)"
elsif mode = 4
    modeName$ = "Center"
    modeKnobs$ = "intensity (repeat count), preserve (satellites/length)"
elsif mode = 5
    modeName$ = "Becoming"
    modeKnobs$ = "intensity (final transform), preserve (gentleness of the ramp)"
elsif mode = 6
    modeName$ = "Distance"
    modeKnobs$ = "intensity (gap size/rhythm), preserve (selection/gain), variation (echoes)"
elsif mode = 7
    modeName$ = "Mass"
    modeKnobs$ = "intensity (density), variation (scatter/looseness), preserve (grain length)"
elsif mode = 8
    modeName$ = "Multiplication"
    modeKnobs$ = "intensity (copies), variation (looseness), preserve (spacing/length)"
endif

if duration_policy = 1
    durPolicy$ = "keep"
elsif duration_policy = 2
    durPolicy$ = "shorter"
else
    durPolicy$ = "longer"
endif

seedToUse = seed
if run_variation
    seedToUse = seed + randomInteger(1, 1000000)
endif

effective_pitch_shift = pitch_shift_semitones

clearinfo
writeInfoLine: "=== Phrase Rewriter ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "  Primary controls: ", modeKnobs$
appendInfoLine: "Preserve source: ", fixed$(preserve_source, 2)
appendInfoLine: "Rewrite intensity: ", fixed$(rewrite_intensity, 2)
appendInfoLine: "Duration policy: ", durPolicy$
appendInfoLine: "Variation: ", fixed$(variation_amount, 2)
appendInfoLine: "Seed: ", seedToUse
if mode = 1
    appendInfoLine: "Pitch shift: ", fixed$(pitch_shift_semitones, 2), " semitones"
    appendInfoLine: "Fragment length: ", fixed$(fragment_length_scale, 2), "x"
endif
appendInfoLine: ""

selectObject: sound
dur = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

hopSec = 0.01
nFrames = floor(dur / hopSec)
if nFrames < 10
    exitScript: "Sound is too short for analysis (need > 0.1 s)."
endif

appendInfoLine: "[1/3] Extracting phrase features..."

selectObject: sound
if nChannels > 1
    Extract one channel: 1
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif

selectObject: analysisMono
pitchObj = To Pitch: 0.01, 75, 1200
selectObject: analysisMono
harmObj = To Harmonicity (cc): 0.01, 75, 0.1, 1.0
selectObject: analysisMono
intObj = To Intensity: 100, 0.01, "yes"
selectObject: analysisMono
formantObj = To Formant (burg): 0.01, 5, 5500, 0.025, 50

Create Table with column names: "features", nFrames,
    ... "time pitch voiced hnr intensity f1 f2 f3"
featureTable = selected("Table")

for i from 1 to nFrames
    t = (i - 0.5) * hopSec
    if t > dur
        t = dur
    endif

    selectObject: featureTable
    Set numeric value: i, "time", t

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

    selectObject: harmObj
    h = Get value at time: t, "Cubic"
    if h = undefined
        h = 0
    endif
    selectObject: featureTable
    Set numeric value: i, "hnr", h

    selectObject: intObj
    iv = Get value at time: t, "Cubic"
    if iv = undefined
        iv = 0
    endif
    selectObject: featureTable
    Set numeric value: i, "intensity", iv

    for fNum from 1 to 3
        selectObject: formantObj
        fVal = Get value at time: fNum, t, "hertz", "Linear"
        if fVal = undefined
            fVal = 0
        endif
        selectObject: featureTable
        Set numeric value: i, "f" + string$(fNum), fVal
    endfor
endfor

appendInfoLine: "[2/3] Exporting temp WAV + CSV..."
selectObject: sound
Save as WAV file: tempInput$
selectObject: featureTable
Save as comma-separated file: tempCSV$
removeObject: analysisMono, pitchObj, harmObj, intObj, formantObj, featureTable

appendInfoLine: "[3/3] Running Python engine..."

constellationFlags$ = ""
if mode = 1
    constellationFlags$ = " --pitch_shift " + fixed$(effective_pitch_shift, 4) + " --fragment_length " + fixed$(fragment_length_scale, 4)
endif

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + modeName$
    ... + " " + fixed$(preserve_source, 4)
    ... + " " + fixed$(rewrite_intensity, 4)
    ... + " " + durPolicy$
    ... + " " + fixed$(variation_amount, 4)
    ... + " " + string$(seedToUse)
    ... + " " + fixed$(hopSec, 4)
    ... + " --cleanup"
    ... + constellationFlags$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Phrase Rewriter Python engine failed." + newline$
        ... + "Python command used: " + pythonCmd$
endif

appendInfoLine: "Importing result..."
Read from file: tempOutput$
Rename: soundName$ + "_rewritten_" + modeName$
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration
rms_in_active  = 0
rms_out_active = 0

selectObject: sound
rms_in = Get root-mean-square: 0, 0

# ============================================================
# Read stats
# ============================================================

modeStat$      = "?"
preserveStat$  = "?"
intensStat$    = "?"
durPolStat$    = "?"
varStat$       = "?"
nEvStat$       = "?"
nPlanStat$     = "?"
inDurStat$     = "?"
outDurStat$    = "?"
warningStat$   = ""

nEvParsed  = 0
nPlParsed  = 0

for ei from 0 to 127
    ev_start_'ei' = 0
    ev_end_'ei'   = 0
    ev_str_'ei'   = 0
    ev_act_'ei'   = -1
    ev_ten_'ei'   = -1
endfor

for pli from 0 to 255
    pl_src_'pli'   = 0
    pl_start_'pli' = 0
    pl_dur_'pli'   = 1
    pl_gain_'pli'  = 0.5
    pl_eff_'pli'   = 0
    pl_role_'pli'$ = ""
endfor

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "mode="
    modeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "preserve_source="
    preserveStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rewrite_intensity="
    intensStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "duration_policy="
    durPolStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "variation="
    varStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_plan_steps="
    nPlanStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "input_duration="
    inDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "rms_in="
    if parseStatLine.result$ <> "?"
        rms_in_active = number(parseStatLine.result$)
    else
        rms_in_active = rms_in
    endif
    @parseStatLine: statsText$, "rms_out="
    if parseStatLine.result$ <> "?"
        rms_out_active = number(parseStatLine.result$)
    else
        rms_out_active = rms_out
    endif

    if nEvStat$ <> "?"
        nEvParsed = number(nEvStat$)
        if nEvParsed > 128
            nEvParsed = 128
        endif
    endif
    # ev_i = start,end,strength[,activity,tension]
    # Three fields is the pre-v1.1 layout; activity/tension then stay -1 and
    # the feature panel falls back to strength, exactly as before.
    for ei from 0 to nEvParsed - 1
        @parseStatLine: statsText$, "ev_" + string$(ei) + "="
        raw$ = parseStatLine.result$
        if raw$ <> "?"
            @splitFields: raw$
            if splitFields.n >= 3
                ev_start_'ei' = number(splitFields.f1$)
                ev_end_'ei'   = number(splitFields.f2$)
                ev_str_'ei'   = number(splitFields.f3$)
            endif
            if splitFields.n >= 5
                ev_act_'ei' = number(splitFields.f4$)
                ev_ten_'ei' = number(splitFields.f5$)
            endif
        endif
    endfor

    if nPlanStat$ <> "?"
        nPlParsed = number(nPlanStat$)
        if nPlParsed > 256
            nPlParsed = 256
        endif
    endif
    # pl_i = src,start,dur_scale,gain[,effective_duration[,role]]
    # The effective duration is the renderer's own target length. Without it
    # (older stats file) the map falls back to source duration x dur_scale.
    for pli from 0 to nPlParsed - 1
        @parseStatLine: statsText$, "pl_" + string$(pli) + "="
        raw$ = parseStatLine.result$
        if raw$ <> "?"
            @splitFields: raw$
            if splitFields.n >= 4
                pl_src_'pli'   = number(splitFields.f1$)
                pl_start_'pli' = number(splitFields.f2$)
                pl_dur_'pli'   = number(splitFields.f3$)
                pl_gain_'pli'  = number(splitFields.f4$)
            endif
            if splitFields.n >= 5
                pl_eff_'pli' = number(splitFields.f5$)
            endif
            if splitFields.n >= 6
                pl_role_'pli'$ = splitFields.f6$
            endif
        endif
    endfor
    for pli from 0 to nPlParsed - 1
        if pl_eff_'pli' <= 0
            .si = pl_src_'pli'
            pl_eff_'pli' = (ev_end_'.si' - ev_start_'.si') * pl_dur_'pli'
        endif
    endfor

    appendInfoLine: ""
    appendInfoLine: "--- Stats ---"
    appendInfoLine: statsText$
    if mode = 7
        appendInfoLine: ""
        appendInfoLine: "Duration policy: archetype-controlled."
        appendInfoLine: "Mass uses its intrinsic compact-cluster duration; the global"
        appendInfoLine: "duration policy (keep / shorter / longer) is deliberately not applied."
    endif
endif

# display maxima for the map's activity/tension ticks (display only)
actMapMax = 0.001
tenMapMax = 0.001
for ei from 0 to nEvParsed - 1
    if ev_act_'ei' > actMapMax
        actMapMax = ev_act_'ei'
    endif
    if ev_ten_'ei' > tenMapMax
        tenMapMax = ev_ten_'ei'
    endif
endfor

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # =========================================================
    # Title panel
    # =========================================================
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Phrase Rewriter##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.50}"
    constellationSub$ = ""
    if mode = 1
        constellationSub$ = " | Pitch=" + fixed$(pitch_shift_semitones, 2) + "st  FragLen=" + fixed$(fragment_length_scale, 2) + "x"
    endif
    Text: 0.5, "centre", -1.0, "half",
        ... soundName$ + " | Mode: " + modeName$
        ... + " | Preserve=" + fixed$(preserve_source, 2)
        ... + " | Intensity=" + fixed$(rewrite_intensity, 2)
        ... + " | Seed=" + string$(seedToUse)
        ... + constellationSub$

    # =========================================================
    # Input waveform  (with event boundary markers)
    # =========================================================
    Select outer viewport: 0, 8, 0.55, 1.45
    Select inner viewport: 0.6, 7.7, 0.60, 1.40
    selectObject: sound
    Colour: "{0.50, 0.50, 0.50}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    Colour: "{0.85, 0.30, 0.20}"
    Line width: 1
    Axes: 0, dur, -1, 1
    for ei from 0 to nEvParsed - 1
        bnd = ev_start_'ei'
        if bnd > 0 and bnd < dur
            Draw line: bnd, -0.88, bnd, 0.88
        endif
    endfor
    Line width: 1
    Font size: 7
    Colour: "Black"
    Text top: "no", string$(nEvParsed) + " events | " + fixed$(dur, 2) + " s"

    # =========================================================
    # Output waveform
    # =========================================================
    Select outer viewport: 0, 8, 1.45, 2.35
    Select inner viewport: 0.6, 7.7, 1.50, 2.30
    selectObject: resultSound
    Colour: "{0.20, 0.50, 0.78}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Rewritten"
    Text bottom: "yes", "Time (s)"

    # =========================================================
    # Input spectrogram
    # =========================================================
    Select outer viewport: 0, 8, 2.45, 3.55
    Select inner viewport: 0.6, 7.7, 2.50, 3.50
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

    # =========================================================
    # Output spectrogram
    # =========================================================
    Select outer viewport: 0, 8, 3.55, 4.65
    Select inner viewport: 0.6, 7.7, 3.60, 4.60
    selectObject: resultSound
    if nChannels > 1
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
    Text top: "no", "Rewritten spectrogram"
    removeObject: specOut, tmpOut

    # =========================================================
    # Phrase feature curves panel
    # =========================================================
    Select outer viewport: 0, 8, 4.75, 5.60
    Select inner viewport: 0.6, 7.7, 4.80, 5.55

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, 1, 0, 1

    # Activity and Tension are now the values the backend actually computed
    # (ev_act_ / ev_ten_). Only the display is normalised; the exported
    # numbers are untouched. An old stats file without them (-1) falls back
    # to strength for both, which is the previous behaviour.
    if nEvParsed > 1
        actMax = 0.001
        tenMax = 0.001
        strMax = 0.001
        haveAT = 1
        for ei from 0 to nEvParsed - 1
            if ev_str_'ei' > strMax
                strMax = ev_str_'ei'
            endif
            if ev_act_'ei' < 0 or ev_ten_'ei' < 0
                haveAT = 0
            endif
            if ev_act_'ei' > actMax
                actMax = ev_act_'ei'
            endif
            if ev_ten_'ei' > tenMax
                tenMax = ev_ten_'ei'
            endif
        endfor

        totalDur = dur
        if totalDur < 0.001
            totalDur = 0.001
        endif

        for ei from 0 to nEvParsed - 1
            eS = ev_start_'ei'
            eE = ev_end_'ei'

            xL = eS / totalDur
            xR = eE / totalDur

            if haveAT
                normAct = ev_act_'ei' / actMax
                normTen = ev_ten_'ei' / tenMax
            else
                normAct = ev_str_'ei' / strMax
                normTen = normAct
            endif

            actH = 0.08 + 0.40 * normAct
            Paint rectangle: "{0.22, 0.48, 0.80}", xL + 0.002, xR - 0.002, 0.08, actH

            tenH = 0.55 + 0.38 * normTen
            Paint rectangle: "{0.78, 0.28, 0.22}", xL + 0.002, xR - 0.002, 0.55, tenH
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Colour: "{0.22, 0.48, 0.80}"
    Text: 0.01, "left", 0.28, "half", "Activity"
    Colour: "{0.78, 0.28, 0.22}"
    Text: 0.01, "left", 0.72, "half", "Tension"
    Colour: "Black"
    Font size: 5
    Text bottom: "yes", "Event time axis (original)"
    if haveAT
        Text top: "no", "Phrase shape per event  (bar height = measured activity / tension)"
    else
        Text top: "no", "Phrase shape per event  (bar height = strength; older stats file has no activity/tension)"
    endif

    # =========================================================
    # Rewrite plan panel
    # =========================================================
    Select outer viewport: 0, 8, 5.70, 6.70
    Select inner viewport: 0.6, 7.7, 5.75, 6.65

    plMaxX = 0.001
    plMaxY = 0
    for pli from 0 to nPlParsed - 1
        if pl_start_'pli' > plMaxX
            plMaxX = pl_start_'pli'
        endif
        if pl_src_'pli' > plMaxY
            plMaxY = pl_src_'pli'
        endif
    endfor
    plMaxX = plMaxX * 1.05
    if plMaxY < 1
        plMaxY = 1
    endif
    plMaxY = plMaxY + 1

    Axes: 0, plMaxX, 0, plMaxY
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, plMaxX, 0, plMaxY

    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    for ei from 0 to nEvParsed - 1
        Draw line: 0, ei + 0.5, plMaxX, ei + 0.5
    endfor

    for pli from 0 to nPlParsed - 1
        px = pl_start_'pli'
        py = pl_src_'pli' + 0.5
        pg = pl_gain_'pli'
        if pg < 0
            pg = 0
        endif
        if pg > 1
            pg = 1
        endif

        if pg < 0.20
            Paint circle (mm): "{0.55, 0.55, 0.58}", px, py, 1.3
        elsif pg < 0.40
            Paint circle (mm): "{0.40, 0.42, 0.52}", px, py, 1.3
        elsif pg < 0.60
            Paint circle (mm): "{0.22, 0.46, 0.78}", px, py, 1.3
        elsif pg < 0.80
            Paint circle (mm): "{0.15, 0.58, 0.55}", px, py, 1.3
        else
            Paint circle (mm): "{0.88, 0.50, 0.12}", px, py, 1.3
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Src ev"
    Text bottom: "yes", "Output time (s)"
    Text top: "no", "Rewrite plan  (" + nPlanStat$ + " steps) — dot colour: grey=quiet, blue=mid, orange=loud"

    # =========================================================
    # Mode colour-coded label strip
    # =========================================================
    Select outer viewport: 0, 8, 6.80, 7.10
    Select inner viewport: 0.6, 7.7, 6.83, 7.07

    Axes: 0, 1, 0, 1

    if mode = 1
        Paint rectangle: "{0.22, 0.48, 0.80}", 0, 1, 0, 1
    elsif mode = 2
        Paint rectangle: "{0.30, 0.60, 0.88}", 0, 1, 0, 1
    elsif mode = 3
        Paint rectangle: "{0.65, 0.28, 0.70}", 0, 1, 0, 1
    elsif mode = 4
        Paint rectangle: "{0.88, 0.55, 0.10}", 0, 1, 0, 1
    elsif mode = 5
        Paint rectangle: "{0.25, 0.70, 0.45}", 0, 1, 0, 1
    elsif mode = 6
        Paint rectangle: "{0.80, 0.30, 0.25}", 0, 1, 0, 1
    elsif mode = 7
        Paint rectangle: "{0.45, 0.35, 0.65}", 0, 1, 0, 1
    else
        Paint rectangle: "{0.70, 0.55, 0.20}", 0, 1, 0, 1
    endif
    Font size: 9
    Colour: "White"
    Text: 0.5, "centre", 0.5, "half", "##" + modeName$ + "##"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # =========================================================
    # Summary panel
    # =========================================================
    Select outer viewport: 0, 8, 7.15, 8.0
    Select inner viewport: 0.6, 7.7, 7.20, 7.95

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "Summary:"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    if mode = 7
        durPolShow$ = "archetype-controlled"
    else
        durPolShow$ = durPolStat$
    endif
    Text: 0.02, "left", 0.70, "half",
        ... "Events=" + nEvStat$
        ... + " | Plan steps=" + nPlanStat$
        ... + " | Dur policy=" + durPolShow$
        ... + " | Variation=" + varStat$
    Text: 0.02, "left", 0.50, "half",
        ... "Duration: " + inDurStat$ + " s -> " + outDurStat$ + " s"
        ... + " | RMS: " + fixed$(rms_in_active, 4) + " -> " + fixed$(rms_out_active, 4)
    constellationSum$ = ""
    if mode = 1
        constellationSum$ = " | Pitch=" + fixed$(pitch_shift_semitones, 2) + "st | FragLen=" + fixed$(fragment_length_scale, 2) + "x"
    endif
    Text: 0.02, "left", 0.30, "half",
        ... "Preserve=" + preserveStat$
        ... + " | Intensity=" + intensStat$
        ... + " | Seed=" + string$(seedToUse)
        ... + constellationSum$

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.80, 0.20, 0.20}"
        Text: 0.02, "left", 0.10, "half", "Warning: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"

endif

###############################################################################
# DRAW TRANSFORMATION MAP
#   Complementary to the analytical panels above: those show phrase
#   behaviour, this shows compositional rewriting. When both are requested
#   the panels are drawn first and the map replaces them after a prompt, so
#   the existing workflow is unchanged for anyone who ignores the new box.
###############################################################################
if draw_transformation_map and nEvParsed > 0
    mapClicked = 2
    if draw_visualization
        beginPause: "Phrase Rewriter"
            comment: "The analytical panels are in the Picture window."
            comment: "Draw the Transformation Map now? It replaces the current picture."
        mapClicked = endPause: "Keep panels", "Draw map", 2, 1
    endif
    if mapClicked <> 1
        appendInfoLine: ""
        appendInfoLine: "Drawing Transformation Map..."
        @drawTransformationMap
    endif
endif

# ============================================================
# FINAL CLEANUP
# ============================================================
@cleanUpTempFiles

# ============================================================
# Summary to Info window
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_rewritten_", modeName$
appendInfoLine: "Mode:   ", modeName$
appendInfoLine: ""
appendInfoLine: "Events:     ", nEvStat$
appendInfoLine: "Plan steps: ", nPlanStat$
appendInfoLine: "Input dur:  ", inDurStat$, " s"
appendInfoLine: "Output dur: ", outDurStat$, " s"
appendInfoLine: "RMS:        ", fixed$(rms_in_active, 4), " -> ", fixed$(rms_out_active, 4)

selectObject: resultSound
if play_result
    Play
endif

# ============================================================
# Procedures
# ============================================================

# Splits a comma-separated stats value into up to 6 fields. Missing fields
# stay empty and .n reports how many were present, so older stats files with
# fewer fields parse without error.
procedure splitFields: .raw$
    .n = 0
    .f1$ = ""
    .f2$ = ""
    .f3$ = ""
    .f4$ = ""
    .f5$ = ""
    .f6$ = ""
    .rest$ = .raw$
    .more = 1
    while .more and .n < 6
        .c = index(.rest$, ",")
        if .c > 0
            .piece$ = left$(.rest$, .c - 1)
            .rest$ = mid$(.rest$, .c + 1, length(.rest$) - .c)
        else
            .piece$ = .rest$
            .rest$ = ""
            .more = 0
        endif
        .n += 1
        if .n = 1
            .f1$ = .piece$
        elsif .n = 2
            .f2$ = .piece$
        elsif .n = 3
            .f3$ = .piece$
        elsif .n = 4
            .f4$ = .piece$
        elsif .n = 5
            .f5$ = .piece$
        else
            .f6$ = .piece$
        endif
    endwhile
endproc

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
    if fileReadable(probeScript$)
        deleteFile: probeScript$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

###############################################################################
# TRANSFORMATION MAP
#   Source segmentation -> compositional rewrite -> rendered phrase.
#   One grammar for all eight modes: colour = source event identity, so the
#   same colour appearing several times below is the same material reused.
#   Mode-specific accents stay small (Constellation role line styles, Center
#   focus band) rather than eight separate visualisers.
###############################################################################
procedure drawTransformationMap
    Erase all
    Select outer viewport: 0, 8, 0, 5.9
    Black
    Line width: 1
    Solid line

    .srcDur = dur
    if .srcDur < 0.001
        .srcDur = 0.001
    endif
    .outDur = number(outDurStat$)
    if .outDur = undefined or .outDur < 0.001
        .outDur = .srcDur
    endif

    # --- title ---
    Font size: 12
    Select inner viewport: 0.6, 7.7, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Phrase Rewriter \--  Transformation Map##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", 0.22, "half", "Source segmentation \-> compositional rewrite \-> rendered phrase"

    # --- map body: one coordinate system, manual bands ---
    Select inner viewport: 0.6, 7.7, 0.95, 4.75
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975, 0.975, 0.985}", 0, 1, 0, 1

    .srcTop = 0.965
    .srcBot = 0.800
    .outTop = 0.215
    .outBot = 0.050

    # strength range for source block weight
    .sMax = 0.001
    for .ei from 0 to nEvParsed - 1
        if ev_str_'.ei' > .sMax
            .sMax = ev_str_'.ei'
        endif
    endfor

    # which source event is used most (Center focus, and general interest)
    .topSrc = -1
    .topUse = 0
    for .ei from 0 to nEvParsed - 1
        .uses = 0
        for .pi from 0 to nPlParsed - 1
            if pl_src_'.pi' = .ei
                .uses += 1
            endif
        endfor
        use_'.ei' = .uses
        if .uses > .topUse
            .topUse = .uses
            .topSrc = .ei
        endif
    endfor

    # Center: mark the organising focus behind its source block
    if modeStat$ = "Center" and .topSrc >= 0
        .fx1 = ev_start_'.topSrc' / .srcDur
        .fx2 = ev_end_'.topSrc' / .srcDur
        Paint rectangle: "{0.93, 0.90, 0.80}", .fx1 - 0.004, .fx2 + 0.004, .srcBot - 0.030, .srcTop + 0.030
    endif

    # ================= A. SOURCE PHRASE =================
    for .ei from 0 to nEvParsed - 1
        .x1 = ev_start_'.ei' / .srcDur
        .x2 = ev_end_'.ei' / .srcDur
        if .x2 - .x1 < 0.002
            .x2 = .x1 + 0.002
        endif
        @eventColour: .ei
        .norm = ev_str_'.ei' / .sMax
        # unused source events are drawn hollow: they disappeared in the rewrite
        if use_'.ei' = 0
            Colour: "{0.72, 0.72, 0.76}"
            Draw rectangle: .x1, .x2, .srcBot, .srcTop
        else
            .h = .srcBot + (.srcTop - .srcBot) * (0.45 + 0.55 * .norm)
            Paint rectangle: eventColour.col$, .x1, .x2, .srcBot, .h
            Colour: "{0.55, 0.55, 0.60}"
            Draw rectangle: .x1, .x2, .srcBot, .srcTop
        endif
        # activity (left tick) and tension (right tick) inside the block
        if ev_act_'.ei' >= 0
            Line width: 1
            Colour: "{0.22, 0.48, 0.80}"
            .ay = .srcBot + (.srcTop - .srcBot) * min(1, ev_act_'.ei' / max(0.001, actMapMax))
            Draw line: .x1 + 0.0015, .srcBot, .x1 + 0.0015, .ay
            Colour: "{0.78, 0.28, 0.22}"
            .ty = .srcBot + (.srcTop - .srcBot) * min(1, ev_ten_'.ei' / max(0.001, tenMapMax))
            Draw line: .x2 - 0.0015, .srcBot, .x2 - 0.0015, .ty
        endif
    endfor
    Font size: 5
    Colour: "{0.30, 0.30, 0.38}"
    for .ei from 0 to nEvParsed - 1
        .x1 = ev_start_'.ei' / .srcDur
        .x2 = ev_end_'.ei' / .srcDur
        if .x2 - .x1 > 0.022
            Text: (.x1 + .x2) / 2, "centre", .srcTop + 0.012, "bottom", string$(.ei)
        endif
    endfor

    # Lane assignment for the output band: each rendered block goes in the
    # lowest lane whose previous block has already ended, so simultaneous
    # copies stack instead of painting over each other. Cloud and Mass are
    # unreadable on a single baseline - their density IS the result.
    .maxLanes = 6
    for .k from 1 to .maxLanes
        laneEnd_'.k' = -1
    endfor
    .lanesUsed = 1
    for .pi from 0 to nPlParsed - 1
        .bs = pl_start_'.pi'
        .be = pl_start_'.pi' + pl_eff_'.pi'
        .placed = 0
        for .k from 1 to .maxLanes
            if .placed = 0 and laneEnd_'.k' <= .bs + 0.0005
                lane_'.pi' = .k
                laneEnd_'.k' = .be
                .placed = 1
                if .k > .lanesUsed
                    .lanesUsed = .k
                endif
            endif
        endfor
        if .placed = 0
            # more than maxLanes at once: reuse the lane that frees first
            .best = 1
            for .k from 2 to .maxLanes
                if laneEnd_'.k' < laneEnd_'.best'
                    .best = .k
                endif
            endfor
            lane_'.pi' = .best
            laneEnd_'.best' = .be
            .lanesUsed = .maxLanes
        endif
    endfor
    .laneH = (.outTop - .outBot) / .lanesUsed

    # ================= B. REWRITE MAP =================
    for .pi from 0 to nPlParsed - 1
        .si = pl_src_'.pi'
        @eventColour: .si
        .sx = (ev_start_'.si' + ev_end_'.si') / 2 / .srcDur
        .ox = (pl_start_'.pi' + pl_eff_'.pi' / 2) / .outDur
        .g = pl_gain_'.pi'
        if .g < 0
            .g = 0
        endif
        if .g > 1
            .g = 1
        endif
        Line width: 0.4 + 2.2 * .g
        Solid line
        .role$ = pl_role_'.pi'$
        if .role$ = "echo"
            Dotted line
        elsif .role$ = "shadow"
            Dashed line
        elsif .role$ = "star"
            Line width: 1.2 + 2.2 * .g
        endif
        Colour: eventColour.col$
        .ly = .outBot + lane_'.pi' * .laneH
        Draw line: .sx, .srcBot - 0.012, .ox, .ly + 0.004
        Solid line
    endfor
    Line width: 1

    # ================= C. REWRITTEN PHRASE =================
    for .pi from 0 to nPlParsed - 1
        .si = pl_src_'.pi'
        @eventColour: .si
        .x1 = pl_start_'.pi' / .outDur
        .x2 = (pl_start_'.pi' + pl_eff_'.pi') / .outDur
        if .x2 - .x1 < 0.0025
            .x2 = .x1 + 0.0025
        endif
        .g = pl_gain_'.pi'
        if .g < 0
            .g = 0
        endif
        if .g > 1
            .g = 1
        endif
        .role$ = pl_role_'.pi'$
        .hfrac = 0.40 + 0.60 * .g
        if .role$ = "echo" or .role$ = "shadow"
            .hfrac = .hfrac * 0.55
        endif
        .y0 = .outBot + (lane_'.pi' - 1) * .laneH
        .h = .y0 + .laneH * 0.86 * .hfrac
        Paint rectangle: eventColour.col$, .x1, .x2, .y0 + .laneH * 0.06, .h
    endfor
    # faint lane rules, so stacking reads as simultaneity
    Colour: "{0.88, 0.88, 0.91}"
    Line width: 1
    for .k from 1 to .lanesUsed - 1
        Draw line: 0, .outBot + .k * .laneH, 1, .outBot + .k * .laneH
    endfor
    Colour: "{0.55, 0.55, 0.60}"
    Draw line: 0, .outBot, 1, .outBot
    Draw line: 0, .srcTop, 1, .srcTop

    # band labels + time rulers
    Font size: 6
    Colour: "{0.30, 0.30, 0.38}"
    Text: 0.002, "left", .srcTop + 0.038, "bottom", "##SOURCE PHRASE##   " + fixed$(.srcDur, 2) + " s, " + string$(nEvParsed) + " events"
    Text: 0.002, "left", .outTop + 0.050, "bottom", "##REWRITTEN PHRASE##   " + fixed$(.outDur, 2) + " s, " + string$(nPlParsed) + " events"
    Font size: 5
    Colour: "{0.45, 0.45, 0.52}"
    Text: 0.998, "right", .srcTop + 0.038, "bottom", "hollow block = event not used"
    if .lanesUsed > 1
        Text: 0.998, "right", .outTop + 0.050, "bottom", "width = rendered duration, height = gain, stacked = simultaneous (" + string$(.lanesUsed) + " lanes)"
    else
        Text: 0.998, "right", .outTop + 0.050, "bottom", "width = rendered duration, height = gain"
    endif

    Colour: "Black"
    Draw inner box

    # ================= metadata strip =================
    Font size: 6
    Select inner viewport: 0.6, 7.7, 4.95, 5.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    if modeStat$ = "Mass"
        .policy$ = "archetype-controlled (Mass keeps its intrinsic compact-cluster duration; the global duration policy is not applied)"
    else
        .policy$ = durPolStat$
    endif
    Text: 0.01, "left", 0.80, "half", "##Mode:## " + modeStat$ + "    ##Preserve:## " + preserveStat$ +
        ... "    ##Rewrite intensity:## " + intensStat$ + "    ##Variation:## " + varStat$ + "    ##Seed:## " + string$(seedToUse)
    Text: 0.01, "left", 0.50, "half", "##Duration policy:## " + .policy$
    @modeHint: modeStat$
    Text: 0.01, "left", 0.20, "half", "##Reading it:## colour = source event identity; a colour reappearing below is the same material reused.    " + modeHint.text$
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, 5.9
    Font size: 10
    Line width: 1
endproc

# eight-colour identity palette, cycled by source-event index
procedure eventColour: .idx
    .k = .idx mod 8
    if .k = 0
        .col$ = "{0.20, 0.44, 0.74}"
    elsif .k = 1
        .col$ = "{0.85, 0.42, 0.16}"
    elsif .k = 2
        .col$ = "{0.25, 0.58, 0.45}"
    elsif .k = 3
        .col$ = "{0.60, 0.35, 0.68}"
    elsif .k = 4
        .col$ = "{0.80, 0.62, 0.15}"
    elsif .k = 5
        .col$ = "{0.35, 0.60, 0.78}"
    elsif .k = 6
        .col$ = "{0.72, 0.28, 0.35}"
    else
        .col$ = "{0.42, 0.45, 0.52}"
    endif
endproc

# one short sentence per mode: what the map should show if the mode worked
procedure modeHint: .mode$
    if .mode$ = "Constellation"
        .text$ = "##Constellation:## many short fragments; solid = star/satellite, dotted = echo, dashed = shadow."
    elsif .mode$ = "Cloud"
        .text$ = "##Cloud:## overlapping copies \--  look for blocks stacked in the same time region."
    elsif .mode$ = "Resonance"
        .text$ = "##Resonance:## selected events plus trailing echo extensions of the same colour."
    elsif .mode$ = "Center"
        .text$ = "##Center:## one highlighted source event returns repeatedly as the organising focus."
    elsif .mode$ = "Becoming"
        .text$ = "##Becoming:## a left-to-right gradient \— early output keeps the source, later output departs from it."
    elsif .mode$ = "Distance"
        .text$ = "##Distance:## growing separation and silence between blocks."
    elsif .mode$ = "Mass"
        .text$ = "##Mass:## accumulation into one dense compact cluster."
    elsif .mode$ = "Multiplication"
        .text$ = "##Multiplication:## one-to-many fans \--  a single source colour repeated across the output."
    else
        .text$ = ""
    endif
endproc
