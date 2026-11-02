# ============================================================
# Praat AudioTools - AI_Conductor_Mix.praat
# Title: AI Conductor Mix
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   AI Conductor Mix is an offline algorithmic ensemble conductor for
#   Praat AudioTools. It analyzes two or more recorded Sounds and
#   generates a continuous stereo mix through context-sensitive role
#   assignment, interpretive memory, and coordinated gain and spatial
#   decisions. Version 3.3 introduces Responsive and Complementary
#   conducting behaviors, phrase-aware interpretation, and optional
#   fixed chamber positioning while preserving the original v3.2
#   processing mode. ("AI" is the instrument's name; v3.3 contains no
#   trained or neural model - all decisions are deterministic.)
#
# Input:
#   Two or more selected Sound objects (mono, stereo or multichannel;
#   sample rates may differ).
#
# Output:
#   "ConductedMix" - stereo Sound (float, sources neither re-timed nor
#   re-pitched); optional Picture; optional mix plan CSV.
#
# Dependencies:
#   Python 3 with numpy + soundfile (librosa, scipy optional);
#   py/ai_conductor_mix.py v3.3 in the plugin folder (or next to this).
#
# Musical concept:
#   Roles: leader, shadow, resonance, noise fringe, pulse carrier,
#   interruption, sustain bed, contrast voice, memory trace, silence.
#   States: sparse, balanced, agitated, saturated, suspended, released.
#   Interpretive behaviour:
#     Original      - the v3.2 conductor, reproduced exactly
#     Responsive    - emphasizes significant gestures, in context
#     Complementary - makes room for a gesture by adjusting the others
#   Energy memory weight (v3.2) = how past ENERGY steers tension.
#   Interpretive memory (s)     = how long the conductor remembers its
#                                 OWN decisions (who was foregrounded).
#
# Usage:
#   Select the Sounds, run, choose a behaviour. Defaults reproduce v3.2.
#
# Changelog v3.3:
#   - Added Interpretive Memory
#   - Added Responsive Conductor and Complementary Conductor
#   - Added phrase-aware contextual decisions
#   - Added optional fixed chamber positioning
#   - Improved polyphony accounting in contextual modes
#   - Added neutral-intervention behaviour
#   - Extended visualization (rendered gain, exposure, phrase regions)
#   - Preserved Original Conductor v3.2 compatibility
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: AI Conductor Mix.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
nSounds = numberOfSelected("Sound")
if nSounds < 2
    exitScript: "Please select 2 or more Sound objects."
endif

# ---- COLLECT SELECTED SOUND IDs AND NAMES ----
for i from 1 to nSounds
    sound'i' = selected("Sound", i)
    soundName'i'$ = selected$("Sound", i)
endfor

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

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/ai_conductor_mix.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/ai_conductor_mix.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: ai_conductor_mix.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

manifestFile$   = temporaryDirectory$ + "/conductor_manifest.txt"
descriptorFile$ = temporaryDirectory$ + "/conductor_descriptors.txt"
mixPlanFile$    = temporaryDirectory$ + "/conductor_mix_plan.csv"
resultWavFile$  = temporaryDirectory$ + "/conductor_result.wav"
logFile$        = temporaryDirectory$ + "/conductor_log.txt"
doneFile$       = temporaryDirectory$ + "/conductor_done.txt"
vizFile$        = temporaryDirectory$ + "/conductor_viz.txt"

# ---- FORM ----
form AI Conductor Mix v3.3
    comment === Segmentation ===
    optionmenu Segment_mode: 2
        option Fixed frames
        option Onset-based
        option Hybrid (onset + fixed)
    positive Frame_size_ms 500
    positive Frame_hop_ms  250
    positive Min_onset_gap_ms 50

    comment === Conductor style (Neutral uses the four values below) ===
    optionmenu Conductor_style: 2
        option Neutral (balanced — uses custom params below)
        option Dramatic (high contrast)
        option Minimal (sparse, slow transitions)
        option Dense (layered, complex)
    positive Energy_memory_weight 0.4
    positive Tension_sensitivity 0.6
    boolean Allow_silence 1
    boolean Nonlinear_reactions 1

    comment === Interpretive behaviour ===
    optionmenu Interpretive_behaviour: 1
        option Original Conductor (v3.2)
        option Responsive Conductor
        option Complementary Conductor
    positive Interpretive_memory_s 4.0
    real Contextual_strength 0.5
    boolean Phrase_awareness 1
    optionmenu Spatial_mode: 1
        option Original role-based pan
        option Fixed chamber positions

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
    boolean Export_mix_plan 0
endform

# ---- PRESET CONDUCTOR STYLES ----
if conductor_style = 1
    cStyle$ = "neutral"
    memWeight = 0.4
    tensionSens = 0.5
    allowSilence = 1
    nonlinear = 0
elsif conductor_style = 2
    cStyle$ = "dramatic"
    memWeight = 0.55
    tensionSens = 0.8
    allowSilence = 1
    nonlinear = 1
elsif conductor_style = 3
    cStyle$ = "minimal"
    memWeight = 0.3
    tensionSens = 0.3
    allowSilence = 1
    nonlinear = 0
elsif conductor_style = 4
    cStyle$ = "dense"
    memWeight = 0.5
    tensionSens = 0.6
    allowSilence = 0
    nonlinear = 1
else
    cStyle$ = "neutral"
endif

if conductor_style = 1
    memWeight    = energy_memory_weight
    tensionSens  = tension_sensitivity
    allowSilence = allow_silence
    nonlinear    = nonlinear_reactions
endif

# Safety bounds for the backend control laws
memWeight = min(1, max(0, memWeight))
tensionSens = min(2, max(0, tensionSens))

# ---- INTERPRETIVE BEHAVIOUR (v3.3) ----
if interpretive_behaviour = 2
    behav$ = "responsive"
    behavLabel$ = "Responsive"
elsif interpretive_behaviour = 3
    behav$ = "complementary"
    behavLabel$ = "Complementary"
else
    behav$ = "original"
    behavLabel$ = "Original (v3.2)"
endif
ctxStrength = min(1, max(0, contextual_strength))
imemTau = min(30, max(0.25, interpretive_memory_s))
if spatial_mode = 2
    spatial$ = "chamber"
else
    spatial$ = "role"
endif

if segment_mode = 1
    segMode$ = "fixed"
elsif segment_mode = 2
    segMode$ = "onset"
else
    segMode$ = "hybrid"
endif

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(manifestFile$)
        deleteFile: manifestFile$
    endif
    if fileReadable(descriptorFile$)
        deleteFile: descriptorFile$
    endif
    if fileReadable(resultWavFile$)
        deleteFile: resultWavFile$
    endif
    if fileReadable(logFile$)
        deleteFile: logFile$
    endif
    if fileReadable(doneFile$)
        deleteFile: doneFile$
    endif
    if fileReadable(vizFile$)
        deleteFile: vizFile$
    endif
    for c_i from 1 to nSounds
        tmpWav$ = temporaryDirectory$ + "/conductor_input_" + string$(c_i) + ".wav"
        if fileReadable(tmpWav$)
            deleteFile: tmpWav$
        endif
    endfor
    if not export_mix_plan
        if fileReadable(mixPlanFile$)
            deleteFile: mixPlanFile$
        endif
    endif
endproc

# Run cleanup at the beginning
@cleanUpTempFiles

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== AI Conductor Mix v3.3 ==="
appendInfoLine: "Ensemble size: ", nSounds, " sounds"
for i from 1 to nSounds
    appendInfoLine: "  [", i, "] ", soundName'i'$
endfor
appendInfoLine: ""
appendInfoLine: "Style:        ", cStyle$
appendInfoLine: "Seg mode:     ", segMode$
appendInfoLine: "Frame:        ", frame_size_ms, " ms / hop ", frame_hop_ms, " ms"
appendInfoLine: "Energy mem.:  ", memWeight
appendInfoLine: "Tension sens: ", tensionSens
appendInfoLine: "Behaviour:    ", behavLabel$
if behav$ <> "original"
    appendInfoLine: "Interp. mem.: ", fixed$(imemTau, 2), " s   strength ", fixed$(ctxStrength, 2), "   phrase ", phrase_awareness
endif
appendInfoLine: "Spatial:      ", spatial$
appendInfoLine: "Output:       Stereo (Python sample-level rendering)"
appendInfoLine: ""

# ---- STEP 1: EXPORT ALL SOUNDS + COLLECT DESCRIPTORS ----
appendInfoLine: "[1/5] Exporting ensemble WAVs and extracting descriptors..."

for i from 1 to nSounds
    wavPath$ = temporaryDirectory$ + "/conductor_input_" + string$(i) + ".wav"

    selectObject: sound'i'
    dur'i' = Get total duration
    sr'i'  = Get sampling frequency
    nCh'i' = Get number of channels
    rms'i' = Get root-mean-square: 0, 0

    Save as WAV file: wavPath$

    appendFileLine: manifestFile$, string$(i) + tab$ + soundName'i'$ + tab$ + wavPath$ + tab$ + fixed$(dur'i', 4) + tab$ + string$(sr'i') + tab$ + string$(nCh'i') + tab$ + fixed$(rms'i', 6)
endfor

appendInfoLine: "  Manifest written: ", nSounds, " files"

# ---- STEP 2: PRAAT-SIDE MACRO DESCRIPTORS (BLENDED WITH PYTHON SEGMENT FEATURES) ----
appendFileLine: descriptorFile$, "file_index" + tab$ + "file_name" + tab$ + "duration" + tab$ + "rms" + tab$ + "mean_pitch_hz" + tab$ + "pitch_range" + tab$ + "mean_intensity_db" + tab$ + "intensity_range_db" + tab$ + "spectral_centroid_est" + tab$ + "harmonicity_hnr"

for i from 1 to nSounds
    selectObject: sound'i'

    if nCh'i' > 1
        Extract one channel: 1
        monoSnd = selected("Sound")
    else
        Copy: "tmpMono_" + string$(i)
        monoSnd = selected("Sound")
    endif

    selectObject: monoSnd
    To Pitch: 0, 75, 600
    pitchObj = selected("Pitch")
    meanPitch = Get mean: 0, 0, "Hertz"
    minPitch  = Get minimum: 0, 0, "Hertz", "Parabolic"
    maxPitch  = Get maximum: 0, 0, "Hertz", "Parabolic"
    pitchRange = maxPitch - minPitch
    if meanPitch = undefined
        meanPitch  = 0
        pitchRange = 0
    endif
    removeObject: pitchObj

    selectObject: monoSnd
    To Intensity: 100, 0, "yes"
    intObj = selected("Intensity")
    meanInt  = Get mean: 0, 0, "dB"
    minInt   = Get minimum: 0, 0, "Parabolic"
    maxInt   = Get maximum: 0, 0, "Parabolic"
    intRange = maxInt - minInt
    removeObject: intObj

    selectObject: monoSnd
    To Harmonicity (cc): 0.01, 75, 0.1, 1.0
    hnrObj = selected("Harmonicity")
    hnr    = Get mean: 0, 0
    if hnr = undefined
        hnr = 0
    endif
    removeObject: hnrObj

    selectObject: monoSnd
    sndDur = Get total duration
    centroid_est = 0
    if sndDur > 0.1
        To Spectrum: "yes"
        specObj = selected("Spectrum")
        centroid_est = Get centre of gravity: 2
        removeObject: specObj
    endif

    removeObject: monoSnd

    appendFileLine: descriptorFile$, string$(i) + tab$ + soundName'i'$ + tab$ + fixed$(dur'i', 4) + tab$ + fixed$(rms'i', 6) + tab$ + fixed$(meanPitch, 2) + tab$ + fixed$(pitchRange, 2) + tab$ + fixed$(meanInt, 2) + tab$ + fixed$(intRange, 2) + tab$ + fixed$(centroid_est, 1) + tab$ + fixed$(hnr, 2)
endfor

appendInfoLine: "  Descriptors written for ", nSounds, " sounds"

# ---- STEP 3: LAUNCH PYTHON CONDUCTOR ----
appendInfoLine: "[2/5] Launching conductor engine..."

pyArgs$ = " """ + manifestFile$ + """ """ + descriptorFile$ + """ """ + mixPlanFile$ + """ """ + doneFile$ + """ --result_wav """ + resultWavFile$ + """ --style " + cStyle$ + " --seg_mode " + segMode$ + " --frame_ms " + string$(frame_size_ms) + " --hop_ms " + string$(frame_hop_ms) + " --onset_gap_ms " + string$(min_onset_gap_ms) + " --memory " + fixed$(memWeight, 3) + " --tension " + fixed$(tensionSens, 3) + " --allow_silence " + string$(allowSilence) + " --nonlinear " + string$(nonlinear) + " --behavior " + behav$ + " --imem_tau " + fixed$(imemTau, 3) + " --ctx_strength " + fixed$(ctxStrength, 3) + " --phrase " + string$(phrase_awareness) + " --spatial " + spatial$
if draw_visualization
    pyArgs$ = pyArgs$ + " --viz_file """ + vizFile$ + """"
endif

if windows
    cmd$ = "start /b " + pythonCmd$ + " """ + pythonScript$ + """" + pyArgs$ + " > """ + logFile$ + """ 2>&1"
else
    cmd$ = pythonCmd$ + " """ + pythonScript$ + """" + pyArgs$ + " > """ + logFile$ + """ 2>&1 &"
endif

runSystem_nocheck: cmd$

# ---- STEP 4: POLL FOR COMPLETION ----
appendInfoLine: "[3/5] Waiting for conductor plan + rendered WAV..."

maxWait = 600
waited  = 0
gotPlan = 0

repeat
    sleep: 1
    waited += 1
    if fileReadable(doneFile$)
        gotPlan = 1
    endif
until gotPlan = 1 or waited >= maxWait

if fileReadable(logFile$)
    log$ = readFile$(logFile$)
    appendInfoLine: log$
else
    log$ = ""
endif

if gotPlan = 1
    doneStatus$ = readFile$(doneFile$)
    if index(doneStatus$, "error") = 1
        errText$ = "Python conductor failed." + newline$ + log$
        @cleanUpTempFiles
        exitScript: errText$
    endif
endif

if waited >= maxWait and gotPlan = 0
    @cleanUpTempFiles
    exitScript: "Timed out waiting for conductor (10 min). Check Python environment."
endif

if not fileReadable(resultWavFile$)
    errText$ = "Rendered WAV not produced." + newline$ + log$
    @cleanUpTempFiles
    exitScript: errText$
endif

# ---- STEP 5: IMPORT RENDERED MIX ----
appendInfoLine: "[4/5] Importing rendered mix..."

mixObj = Read from file: resultWavFile$
Rename: "ConductedMix"

selectObject: mixObj
totalDur = Get total duration
mixSr = Get sampling frequency
nRendered = 0

appendInfoLine: "  Imported: ConductedMix (", fixed$(totalDur, 2), " s stereo)"

# ---- Parse CSV plan for role timeline data ----
if fileReadable(mixPlanFile$)
    planText$ = readFile$(mixPlanFile$)

    maxRoleSlots = 4000
    for ri from 1 to maxRoleSlots
        roleEntry'ri' = 0
        roleExit'ri'  = 0
        roleFile'ri'  = 0
        rolePriority'ri' = 0
        roleTension'ri' = 0
        roleLabel'ri'$ = ""
        roleFg'ri' = 0
        roleLf'ri' = 0
    endfor
    # contextual modes append diagnostics:
    # column 25 = gain_emphasized, column 26 = level_foreground
    lastCol = 18
    if behav$ <> "original"
        lastCol = 26
    endif

    firstNL = index(planText$, newline$)
    if firstNL > 0
        dataStart = firstNL + 1
        secondNL  = index(mid$(planText$, dataStart, length(planText$) - dataStart + 1), newline$)
        if secondNL > 0
            dataStart = dataStart + secondNL
        endif

        scanPos = dataStart
        repeat
            lineEnd = index(mid$(planText$, scanPos, length(planText$) - scanPos + 1), newline$)
            if lineEnd > 0
                line$ = mid$(planText$, scanPos, lineEnd - 1)
            else
                line$ = mid$(planText$, scanPos, length(planText$) - scanPos + 1)
            endif

            if length(line$) > 2
                colNum = 0
                fieldStart = 1
                fIdx = 0
                entryTime = 0
                exitTimeP = 0
                priorityP = 0
                tensionP = 0
                roleStr$ = ""
                fgP = 0
                lfP = 0

                repeat
                    tabPos = index(mid$(line$, fieldStart, length(line$) - fieldStart + 1), tab$)
                    if tabPos > 0
                        field$ = mid$(line$, fieldStart, tabPos - 1)
                        fieldStart = fieldStart + tabPos
                    else
                        field$ = mid$(line$, fieldStart, length(line$) - fieldStart + 1)
                        tabPos = 0
                    endif
                    colNum += 1
                    if colNum = 2 and field$ <> ""
                        fIdx = number(field$)
                    elsif colNum = 8
                        roleStr$ = field$
                    elsif colNum = 10 and field$ <> ""
                        entryTime = number(field$)
                    elsif colNum = 11 and field$ <> ""
                        exitTimeP = number(field$)
                    elsif colNum = 15 and field$ <> ""
                        priorityP = number(field$)
                    elsif colNum = 17 and field$ <> ""
                        tensionP = number(field$)
                    elsif colNum = 25 and field$ <> ""
                        fgP = number(field$)
                    elsif colNum = 26 and field$ <> ""
                        lfP = number(field$)
                    endif
                until tabPos = 0 or colNum >= lastCol

                if fIdx >= 1 and fIdx <= nSounds and exitTimeP > entryTime
                    nRendered += 1
                    if nRendered <= maxRoleSlots
                        roleEntry'nRendered' = entryTime
                        roleExit'nRendered'  = exitTimeP
                        roleFile'nRendered'  = fIdx
                        rolePriority'nRendered' = priorityP
                        roleTension'nRendered' = tensionP
                        roleLabel'nRendered'$ = roleStr$
                        roleFg'nRendered' = fgP
                        roleLf'nRendered' = lfP
                    endif
                endif
            endif

            if lineEnd > 0
                scanPos = scanPos + lineEnd
            endif
        until lineEnd = 0 or scanPos > length(planText$)
    endif
endif

appendInfoLine: "  Segments in plan: ", nRendered

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Drawing visualization..."

    selectObject: mixObj
    mixDraw = Convert to mono

    # v3.3 data from the same run: rendered gain envelopes (the renderer's
    # own smoothed curves), phrase context and interpretive memory
    hasViz = 0
    nVizRows = 0
    if fileReadable(vizFile$)
        vizTab = Read Table from tab-separated file: vizFile$
        nVizRows = Get number of rows
        if nVizRows > 1
            hasViz = 1
        endif
    endif
    isCtx = 0
    if behav$ <> "original" and hasViz
        isCtx = 1
    endif

    canvasH = 10.6
    if hasViz
        canvasH = canvasH + 1.75
    endif
    if isCtx
        canvasH = canvasH + 1.45
    endif

    Erase all
    Select outer viewport: 0, 8, 0, canvasH

    # ---- Title panel ----
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##AI Conductor Mix v3.3##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.18, "half", "Behaviour: " + behavLabel$ + "  | Style: " + cStyle$ + "  | Pan: " + spatial$ + "  | Files: " + string$(nSounds) + "  | Segs: " + string$(nRendered)

    # ---- Individual input waveforms ----
    panelH = 0.9
    yTop = 0.7

    for i from 1 to min(nSounds, 4)
        yBot = yTop + panelH
        Select outer viewport: 0, 8, yTop, yBot
        Select inner viewport: 0.7, 7.7, yTop + 0.05, yBot - 0.05
        selectObject: sound'i'
        grey = 0.3 + (i - 1) * 0.15
        Colour: "{" + fixed$(grey, 2) + ", " + fixed$(grey + 0.1, 2) + ", " + fixed$(grey + 0.2, 2) + "}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", replace$(soundName'i'$, "_", "\_ ", 0)
        yTop = yBot
    endfor

    # ---- Conducted mix waveform ----
    yBot = yTop + 1.1
    Select outer viewport: 0, 8, yTop, yBot
    Select inner viewport: 0.7, 7.7, yTop + 0.05, yBot - 0.1
    selectObject: mixDraw
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Conducted"
    Text bottom: "yes", "Time (s)"
    yTop = yBot

    # ---- Role timeline panel ----
    roleTimeH = 1.6
    yBot = yTop + roleTimeH
    Select outer viewport: 0, 8, yTop, yBot
    Select inner viewport: 0.7, 7.7, yTop + 0.05, yBot - 0.1
    Axes: 0, totalDur, 0, nSounds + 1
    Paint rectangle: "{0.95, 0.95, 0.97}", 0, totalDur, 0, nSounds + 1

    for i from 1 to nSounds
        Colour: "{0.85, 0.85, 0.88}"
        Draw line: 0, i, totalDur, i
    endfor

    for ri from 1 to min(nRendered, maxRoleSlots)
        rE = roleEntry'ri'
        rX = min(totalDur, roleExit'ri')
        rF = roleFile'ri'
        rL$ = roleLabel'ri'$

        if rF >= 1 and rF <= nSounds and rX > rE
            if rL$ = "leader"
                 roleCol$ = "{0.85, 0.15, 0.15}"
            elsif rL$ = "shadow"
                roleCol$ = "{0.55, 0.55, 0.55}"
            elsif rL$ = "resonance"
                roleCol$ = "{0.2, 0.45, 0.8}"
            elsif rL$ = "noise_fringe"
                roleCol$ = "{0.6, 0.4, 0.2}"
            elsif rL$ = "pulse_carrier"
                roleCol$ = "{0.9, 0.55, 0.1}"
            elsif rL$ = "interruption"
                roleCol$ = "{0.8, 0.15, 0.6}"
            elsif rL$ = "sustain_bed"
                roleCol$ = "{0.2, 0.6, 0.55}"
            elsif rL$ = "contrast_voice"
                roleCol$ = "{0.85, 0.75, 0.1}"
            elsif rL$ = "memory_trace"
                roleCol$ = "{0.6, 0.5, 0.8}"
            else
                roleCol$ = "{0.7, 0.7, 0.7}"
            endif

            rP = rolePriority'ri'
            roleHalfH = 0.18 + 0.20 * min(1, max(0, rP))
            yLo = rF - roleHalfH
            yHi = rF + roleHalfH
            Paint rectangle: roleCol$, rE, rX, yLo, yHi
            # indicators separate from the analytic role:
            # grey = gain-emphasized (commands), black = level foreground
            # (source level + applied gain, >= 3 dB ahead; an estimate)
            if roleFg'ri' = 1
                Paint rectangle: "{0.62, 0.62, 0.62}", rE, rX, rF + 0.39, rF + 0.43
            endif
            if roleLf'ri' = 1
                Paint rectangle: "{0.10, 0.10, 0.10}", rE, rX, rF + 0.44, rF + 0.48
            endif
        endif
    endfor

    Font size: 6
    Colour: "Black"
    for i from 1 to min(nSounds, 8)
        shortName$ = replace$(left$(soundName'i'$, 12), "_", "\_ ", 0)
        Text: -totalDur * 0.005, "right", i, "half", shortName$
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Roles"
    Text bottom: "yes", "Time (s)"
    Font size: 7
    if behav$ <> "original"
        Text top: "no", "Role Timeline: colour = analytic role, height = priority; above: grey = gain-emphasized, black = level foreground (est.)"
    else
        Text top: "no", "Role Timeline (bar height = priority)"
    endif

    # ---- Role legend ----
    legendY = yBot + 0.02
    Select outer viewport: 0, 8, legendY, legendY + 0.4
    Axes: 0, 1, 0, 1
    Font size: 5

    Paint rectangle: "{0.85, 0.15, 0.15}", 0.02, 0.05, 0.55, 0.9
    Colour: "Black"
    Text: 0.055, "left", 0.72, "half", "leader"

    Paint rectangle: "{0.55, 0.55, 0.55}", 0.13, 0.16, 0.55, 0.9
    Text: 0.165, "left", 0.72, "half", "shadow"

    Paint rectangle: "{0.2, 0.45, 0.8}", 0.24, 0.27, 0.55, 0.9
    Text: 0.275, "left", 0.72, "half", "reson."

    Paint rectangle: "{0.6, 0.4, 0.2}", 0.35, 0.38, 0.55, 0.9
    Text: 0.385, "left", 0.72, "half", "noise"

    Paint rectangle: "{0.9, 0.55, 0.1}", 0.45, 0.48, 0.55, 0.9
    Text: 0.485, "left", 0.72, "half", "pulse"

    Paint rectangle: "{0.8, 0.15, 0.6}", 0.56, 0.59, 0.55, 0.9
    Text: 0.595, "left", 0.72, "half", "interr."

    Paint rectangle: "{0.2, 0.6, 0.55}", 0.67, 0.70, 0.55, 0.9
    Text: 0.705, "left", 0.72, "half", "sustain"

    Paint rectangle: "{0.85, 0.75, 0.1}", 0.78, 0.81, 0.55, 0.9
    Text: 0.815, "left", 0.72, "half", "contrast"

    Paint rectangle: "{0.6, 0.5, 0.8}", 0.89, 0.92, 0.55, 0.9
    Text: 0.925, "left", 0.72, "half", "memory"

    yTop = legendY + 0.4

    # ---- v3.3: rendered gain envelopes + phrase regions ----
    nVoiceCol = 8
    voiceCol1$ = "{0.20, 0.40, 0.80}"
    voiceCol2$ = "{0.85, 0.35, 0.10}"
    voiceCol3$ = "{0.15, 0.60, 0.35}"
    voiceCol4$ = "{0.60, 0.25, 0.70}"
    voiceCol5$ = "{0.75, 0.60, 0.05}"
    voiceCol6$ = "{0.10, 0.60, 0.70}"
    voiceCol7$ = "{0.55, 0.35, 0.20}"
    voiceCol8$ = "{0.45, 0.45, 0.45}"
    nBound = 0
    nPreserve = 0
    nEmph = 0
    nWithdraw = 0
    if hasViz
        selectObject: vizTab
        vStep = max(1, ceiling(nVizRows / 1500))
        for vr from 1 to nVizRows
            if isCtx
                bflag = Get value: vr, "boundary"
                if bflag = 1
                    nBound += 1
                    boundT'nBound' = Get value: vr, "time"
                endif
                dcode = Get value: vr, "decision"
                if dcode = 0
                    nPreserve += 1
                elsif dcode = 1
                    nEmph += 1
                elsif dcode = 2
                    nWithdraw += 1
                endif
            endif
        endfor

        gainH = 1.4
        yBot = yTop + gainH
        Font size: 6
        Select outer viewport: 0, 8, yTop, yBot
        Select inner viewport: 0.7, 7.7, yTop + 0.25, yBot - 0.1
        Axes: 0, totalDur, 0, 1.15
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, totalDur, 0, 1.0

        # phrase-context strip (contextual modes): one rectangle per run
        if isCtx
            runStart = 0
            runCode = Get value: 1, "phrase"
            for vr from 2 to nVizRows + 1
                if vr <= nVizRows
                    curCode = Get value: vr, "phrase"
                else
                    curCode = -99
                endif
                if curCode <> runCode
                    runEnd = Get value: vr - 1, "time"
                    if runCode = 1
                        phCol$ = "{0.98, 0.82, 0.62}"
                    elsif runCode = 2
                        phCol$ = "{0.93, 0.68, 0.82}"
                    elsif runCode = 3
                        phCol$ = "{0.70, 0.85, 0.95}"
                    else
                        phCol$ = "{0.88, 0.88, 0.88}"
                    endif
                    Paint rectangle: phCol$, runStart, min(totalDur, runEnd + 0.02), 1.04, 1.13
                    runStart = runEnd + 0.02
                    runCode = curCode
                endif
            endfor
        endif

        # curves: actual renderer envelopes (after 300 ms Hann smoothing)
        Line width: 1.2
        for vi from 1 to nSounds
            vc = ((vi - 1) mod nVoiceCol) + 1
            Colour: voiceCol'vc'$
            prevT = Get value: 1, "time"
            prevG = Get value: 1, "g" + string$(vi)
            for vr from 1 + vStep to nVizRows
                if (vr - 1) mod vStep = 0 or vr = nVizRows
                    curT = Get value: vr, "time"
                    curG = Get value: vr, "g" + string$(vi)
                    if curT <= totalDur
                        Draw line: prevT, min(1, prevG), curT, min(1, curG)
                    endif
                    prevT = curT
                    prevG = curG
                endif
            endfor
        endfor
        Line width: 1
        if nBound > 0
            Colour: "{0.30, 0.30, 0.30}"
            Dashed line
            for bi from 1 to nBound
                Draw line: boundT'bi', 0, boundT'bi', 1.0
            endfor
            Solid line
        endif
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.7, 7.7, yTop + 0.25, yBot - 0.1
        Axes: 0, totalDur, 0, 1.15
        Marks left every: 1, 0.5, "yes", "yes", "no"
        Text left: "yes", "Gain"
        if isCtx
            Text top: "no", "Rendered gain per voice (smoothed renderer envelope) — top strip: phrase context, dashed: estimated boundaries"
        else
            Text top: "no", "Rendered gain per voice (smoothed renderer envelope)"
        endif

        # voice + phrase key
        yTop = yBot
        Select inner viewport: 0.7, 7.7, yTop, yTop + 0.3
        Axes: 0, 1, 0, 1
        Font size: 6
        keyX = 0
        for vi from 1 to min(nSounds, 8)
            vc = ((vi - 1) mod nVoiceCol) + 1
            Paint rectangle: voiceCol'vc'$, keyX, keyX + 0.025, 0.35, 0.75
            keyName$ = replace$(left$(soundName'vi'$, 12), "_", "\_ ", 0)
            Colour: "Black"
            Text: keyX + 0.03, "left", 0.55, "half", keyName$
            keyX = keyX + 0.115
        endfor
        if isCtx
            Paint rectangle: "{0.88, 0.88, 0.88}", 0.93, 0.95, 0.80, 1.0
            Paint rectangle: "{0.98, 0.82, 0.62}", 0.93, 0.95, 0.55, 0.75
            Paint rectangle: "{0.93, 0.68, 0.82}", 0.93, 0.95, 0.30, 0.55
            Paint rectangle: "{0.70, 0.85, 0.95}", 0.93, 0.95, 0.05, 0.30
            Font size: 5
            Text: 0.955, "left", 0.90, "half", "continuing"
            Text: 0.955, "left", 0.65, "half", "building"
            Text: 0.955, "left", 0.42, "half", "contrasting"
            Text: 0.955, "left", 0.17, "half", "releasing"
        endif
        yTop = yTop + 0.35

        # ---- interpretive memory: foreground exposure per voice ----
        if isCtx
            expH = 1.4
            yBot = yTop + expH
            Font size: 6
            Select outer viewport: 0, 8, yTop, yBot
            Select inner viewport: 0.7, 7.7, yTop + 0.2, yBot - 0.15
            Axes: 0, totalDur, 0, 1
            Paint rectangle: "{0.98, 0.98, 0.98}", 0, totalDur, 0, 1
            selectObject: vizTab
            Line width: 1.2
            for vi from 1 to nSounds
                vc = ((vi - 1) mod nVoiceCol) + 1
                Colour: voiceCol'vc'$
                prevT = Get value: 1, "time"
                prevE = Get value: 1, "e" + string$(vi)
                for vr from 1 + vStep to nVizRows
                    if (vr - 1) mod vStep = 0 or vr = nVizRows
                        curT = Get value: vr, "time"
                        curE = Get value: vr, "e" + string$(vi)
                        if curT <= totalDur and prevE >= 0 and curE >= 0
                            Draw line: prevT, prevE, curT, prevE
                            Draw line: curT, prevE, curT, curE
                        endif
                        prevT = curT
                        prevE = curE
                    endif
                endfor
            endfor
            Line width: 1
            if nBound > 0
                Colour: "{0.30, 0.30, 0.30}"
                Dashed line
                for bi from 1 to nBound
                    Draw line: boundT'bi', 0, boundT'bi', 1
                endfor
                Solid line
            endif
            Colour: "Black"
            Draw inner box
            Select inner viewport: 0.7, 7.7, yTop + 0.2, yBot - 0.15
            Axes: 0, totalDur, 0, 1
            Marks left every: 1, 0.5, "yes", "yes", "no"
            Text left: "yes", "Exposure"
            Text top: "no", "Interpretive memory: recent foreground exposure per voice (from committed gains, tau " + fixed$(imemTau, 1) + " s)"
            yTop = yBot + 0.05
        endif
        removeObject: vizTab
    endif

    # ---- Mix spectrogram ----
    specH = 1.8
    yBot = yTop + specH
    Select outer viewport: 0, 8, yTop, yBot
    Select inner viewport: 0.7, 7.7, yTop + 0.05, yBot - 0.1

    selectObject: mixDraw
    specStep = max(0.002, totalDur / 2000)
    specMax = min(5000, mixSr * 0.49)
    To Spectrogram: 0.01, specMax, specStep, 20, "Gaussian"
    specMix = selected("Spectrogram")
    Paint: 0, 0, 0, specMax, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Freq (Hz)"
    Text top:  "no", "Mix Spectrogram"
    Text bottom: "yes", "Time (s)"
    removeObject: specMix

    removeObject: mixDraw

    # ---- Stats box ----
    yTop = yBot + 0.45
    Font size: 6
    Select inner viewport: 0.7, 7.7, yTop, yTop + 0.5
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##   Plan rows: " + string$(nRendered) + "   Duration: " + fixed$(totalDur, 2) + " s   Style: " + cStyle$ + "   Energy memory: " + fixed$(memWeight, 2) + "   Tension sensitivity: " + fixed$(tensionSens, 2)
    if isCtx
        nDec = max(1, nPreserve + nEmph + nWithdraw)
        Text: 0.02, "left", 0.28, "half", "Behaviour: " + behavLabel$ + "   Interp. memory: " + fixed$(imemTau, 1) + " s   Strength: " + fixed$(ctxStrength, 2) + "   Phrase: " + string$(phrase_awareness) + " (" + string$(nBound) + " boundaries)   Time preserved / emphasized / withdrawn: " + fixed$(100 * nPreserve / nDec, 0) + " / " + fixed$(100 * nEmph / nDec, 0) + " / " + fixed$(100 * nWithdraw / nDec, 0) + " \%  "
    else
        Text: 0.02, "left", 0.28, "half", "Behaviour: " + behavLabel$ + "   Pan: " + spatial$
    endif
    Select inner viewport: 0.7, 7.7, yTop, yTop + 0.5
    Axes: 0, 1, 0, 1
    Draw inner box
    canvasH = yTop + 0.6
    Select outer viewport: 0, 8, 0, canvasH
endif

# ---- PLAY ----
if play_result
    selectObject: mixObj
    Play
endif

# ---- CLEANUP AND DONE ----
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== Conducted mix complete ==="
appendInfoLine: "Output: ConductedMix (" + fixed$(totalDur, 2) + " s, stereo)"
if export_mix_plan
    appendInfoLine: "Mix plan saved: " + mixPlanFile$
endif