# ============================================================
# Praat AudioTools - AI_Conductor_Mix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Algorithmic Conductor Mix - descriptor-driven ensemble mixer.
#   Selects 2+ Sound objects, exports WAVs, sends them to a Python
#   backend which builds a role-based plan and renders a stereo mix
#   at sample level. Praat reads the result back and visualises.
#
#   Roles: leader, shadow, resonance, noise fringe,
#   pulse carrier, interruption, sustain bed, contrast voice,
#   memory trace, silence.
#
#   States: sparse, balanced, agitated, saturated, suspended, released.
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
pluginDir$      = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$   = pluginDir$ + "py/ai_conductor_mix.py"

manifestFile$   = temporaryDirectory$ + "/conductor_manifest.txt"
descriptorFile$ = temporaryDirectory$ + "/conductor_descriptors.txt"
mixPlanFile$    = temporaryDirectory$ + "/conductor_mix_plan.csv"
resultWavFile$  = temporaryDirectory$ + "/conductor_result.wav"
logFile$        = temporaryDirectory$ + "/conductor_log.txt"
doneFile$       = temporaryDirectory$ + "/conductor_done.txt"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

# ---- FORM ----
form AI Conductor Mix v3.1
    comment === Segmentation ===
    optionmenu Segment_mode: 2
        option Fixed frames
        option Onset-based
        option Hybrid (onset + fixed)
    positive Frame_size_ms 500
    positive Frame_hop_ms  250
    positive Min_onset_gap_ms 50

    comment === Conductor Behaviour ===
    comment Memory = how much past energy influences current decisions
    comment Tension = how reactive to energy contrasts
    optionmenu Conductor_style: 2
        option Neutral (balanced — uses custom params below)
        option Dramatic (high contrast)
        option Minimal (sparse, slow transitions)
        option Dense (layered, complex)
    positive Memory_weight 0.4
    boolean Allow_silence 1
    boolean Nonlinear_reactions 1
    positive Tension_sensitivity 0.6

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
    memWeight    = memory_weight
    tensionSens  = tension_sensitivity
    allowSilence = allow_silence
    nonlinear    = nonlinear_reactions
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
writeInfoLine:  "=== AI Conductor Mix v3.1 ==="
appendInfoLine: "Ensemble size: ", nSounds, " sounds"
for i from 1 to nSounds
    appendInfoLine: "  [", i, "] ", soundName'i'$
endfor
appendInfoLine: ""
appendInfoLine: "Style:        ", cStyle$
appendInfoLine: "Seg mode:     ", segMode$
appendInfoLine: "Frame:        ", frame_size_ms, " ms / hop ", frame_hop_ms, " ms"
appendInfoLine: "Memory:       ", memWeight
appendInfoLine: "Tension sens: ", tensionSens
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

# ---- STEP 2: PRAAT-SIDE DESCRIPTOR EXTRACTION ----
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

pyArgs$ = " """ + manifestFile$ + """ """ + descriptorFile$ + """ """ + mixPlanFile$ + """ """ + doneFile$ + """ --result_wav """ + resultWavFile$ + """ --style " + cStyle$ + " --seg_mode " + segMode$ + " --frame_ms " + string$(frame_size_ms) + " --hop_ms " + string$(frame_hop_ms) + " --onset_gap_ms " + string$(min_onset_gap_ms) + " --memory " + fixed$(memWeight, 3) + " --tension " + fixed$(tensionSens, 3) + " --allow_silence " + string$(allowSilence) + " --nonlinear " + string$(nonlinear)

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
endif

if waited >= maxWait and gotPlan = 0
    @cleanUpTempFiles
    exitScript: "Timed out waiting for conductor (10 min). Check Python environment."
endif

if not fileReadable(resultWavFile$)
    @cleanUpTempFiles
    exitScript: "Rendered WAV not produced. See log for errors."
endif

# ---- STEP 5: IMPORT RENDERED MIX ----
appendInfoLine: "[4/5] Importing rendered mix..."

mixObj = Read from file: resultWavFile$
Rename: "ConductedMix"

selectObject: mixObj
totalDur = Get total duration
nRendered = 0

appendInfoLine: "  Imported: ConductedMix (", fixed$(totalDur, 2), " s stereo)"

# ---- Parse CSV plan for role timeline data ----
if fileReadable(mixPlanFile$)
    planText$ = readFile$(mixPlanFile$)

    maxRoleSlots = 2000
    for ri from 1 to maxRoleSlots
        roleEntry'ri' = 0
        roleExit'ri'  = 0
        roleFile'ri'  = 0
        roleLabel'ri'$ = ""
    endfor

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
                roleStr$ = ""

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
                    endif
                until tabPos = 0 or colNum >= 16

                if fIdx >= 1 and fIdx <= nSounds and exitTimeP > entryTime
                    nRendered += 1
                    if nRendered <= maxRoleSlots
                        roleEntry'nRendered' = entryTime
                        roleExit'nRendered'  = exitTimeP
                        roleFile'nRendered'  = fIdx
                        roleLabel'nRendered'$ = roleStr$
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

    Erase all
    Select outer viewport: 0, 8, 0, 10

    # ---- Title panel ----
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##AI Conductor Mix##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.0, "half", "Style: " + cStyle$ + "  | Stereo | Files: " + string$(nSounds) + "  | Segs: " + string$(nRendered)

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
        Text left: "yes", soundName'i'$
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
        rX = roleExit'ri'
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

            yLo = rF - 0.35
            yHi = rF + 0.35
            Paint rectangle: roleCol$, rE, rX, yLo, yHi
        endif
    endfor

    Font size: 6
    Colour: "Black"
    for i from 1 to min(nSounds, 8)
        shortName$ = left$(soundName'i'$, 12)
        Text: -totalDur * 0.005, "right", i, "half", shortName$
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Roles"
    Text bottom: "yes", "Time (s)"
    Font size: 7
    Text top: "no", "Role Timeline"

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

    # ---- Mix spectrogram ----
    specH = 1.8
    yBot = yTop + specH
    Select outer viewport: 0, 8, yTop, yBot
    Select inner viewport: 0.7, 7.7, yTop + 0.05, yBot - 0.1

    selectObject: mixDraw
    specStep = max(0.002, totalDur / 2000)
    To Spectrogram: 0.01, 5000, specStep, 20, "Gaussian"
    specMix = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Freq (Hz)"
    Text top:  "no", "Mix Spectrogram"
    Text bottom: "yes", "Time (s)"
    removeObject: specMix

    removeObject: mixDraw

    # ---- Stats box ----
    yTop = yBot + 0.1
    Select outer viewport: 0, 8, yTop, yTop + 0.6
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "Black"
    Text: 0.02, "left", 0.7, "half", "Segments: " + string$(nRendered) + "   Duration: " + fixed$(totalDur, 2) + " s   Style: " + cStyle$ + "   Memory: " + fixed$(memWeight, 2) + "   Tension: " + fixed$(tensionSens, 2)
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