# ============================================================
# Praat AudioTools - AI_Conductor_Mix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Added Stereo Panning
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   AI Conductor Mix - PyTorch-driven ensemble conductor.
#   Selects 2+ Sound objects, extracts per-segment descriptors,
#   sends them to Python/PyTorch which builds a dynamic role-based
#   mix plan (CSV), then Praat reconstructs the conducted mix.
#
#   Roles assigned by AI: leader, shadow, resonance, noise fringe,
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

# ---- PATHS ----
if windows
    sep$ = "\"
    pythonCmd$ = "py"
    platform$ = "Windows"
elsif macintosh
    sep$ = "/"
    pythonCmd$ = "python3"
    platform$ = "macOS"
else
    sep$ = "/"
    pythonCmd$ = "python3"
    platform$ = "Linux"
endif

pluginDir$    = preferencesDirectory$ + sep$ + "plugin_AudioTools" + sep$
pythonScript$ = pluginDir$ + "py" + sep$ + "ai_conductor_mix.py"
manifestFile$ = pluginDir$ + "conductor_manifest.txt"
descriptorFile$ = pluginDir$ + "conductor_descriptors.txt"
mixPlanFile$  = pluginDir$ + "conductor_mix_plan.csv"
logFile$      = pluginDir$ + "conductor_log.txt"
doneFile$     = pluginDir$ + "conductor_done.txt"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

# ---- FORM ----
form AI Conductor Mix v1.0
    comment === Segmentation ===
    optionmenu Segment_mode: 2
        option Fixed frames
        option Onset-based
        option Hybrid (onset + fixed)
    positive Frame_size_ms 500
    positive Frame_hop_ms  250
    positive Min_onset_gap_ms 50

    comment === Conductor Behaviour ===
    optionmenu Conductor_style: 2
        option Neutral (balanced)
        option Dramatic (high contrast)
        option Minimal (sparse, slow transitions)
        option Dense (layered, complex)
    positive Memory_weight 0.4
    boolean Allow_silence 1
    boolean Nonlinear_reactions 1
    positive Tension_sensitivity 0.6

    comment === Output ===
    boolean Stereo_panorama 1
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

# Override with form if style = 1 (neutral = user custom)
if conductor_style = 1
    memWeight    = memory_weight
    tensionSens  = tension_sensitivity
    allowSilence = allow_silence
    nonlinear    = nonlinear_reactions
endif

# Segment mode string
if segment_mode = 1
    segMode$ = "fixed"
elsif segment_mode = 2
    segMode$ = "onset"
else
    segMode$ = "hybrid"
endif

# ---- PRE-CALCULATE STEREO PANNING ----
for i from 1 to nSounds
    if nSounds > 1
        pan'i' = -1 + (2 * (i - 1) / (nSounds - 1))
    else
        pan'i' = 0
    endif
    leftGain'i' = sqrt((1 - pan'i') / 2)
    rightGain'i' = sqrt((1 + pan'i') / 2)
endfor

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== AI Conductor Mix v1.0 ==="
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
if stereo_panorama
    appendInfoLine: "Output:       Stereo Panorama"
endif
appendInfoLine: ""

# ---- STEP 1: EXPORT ALL SOUNDS + COLLECT DESCRIPTORS ----
appendInfoLine: "[1/5] Exporting ensemble WAVs and extracting descriptors..."

# Write manifest: one line per file (index TAB name TAB path)
deleteFile: manifestFile$

for i from 1 to nSounds
    wavPath$ = pluginDir$ + "conductor_input_" + string$(i) + ".wav"

    selectObject: sound'i'
    dur'i' = Get total duration
    sr'i'  = Get sampling frequency
    nCh'i' = Get number of channels
    rms'i' = Get root-mean-square: 0, 0

    Save as WAV file: wavPath$

    # Append to manifest
    appendFileLine: manifestFile$, string$(i) + tab$ + soundName'i'$ + tab$ + wavPath$ + tab$ + fixed$(dur'i', 4) + tab$ + string$(sr'i') + tab$ + string$(nCh'i') + tab$ + fixed$(rms'i', 6)
endfor

appendInfoLine: "  Manifest written: ", nSounds, " files"

# ---- STEP 2: PRAAT-SIDE DESCRIPTOR EXTRACTION ----
deleteFile: descriptorFile$
appendFileLine: descriptorFile$, "file_index" + tab$ + "file_name" + tab$ + "duration" + tab$ + "rms" + tab$ + "mean_pitch_hz" + tab$ + "pitch_range" + tab$ + "mean_intensity_db" + tab$ + "intensity_range_db" + tab$ + "spectral_centroid_est" + tab$ + "harmonicity_hnr"

for i from 1 to nSounds
    selectObject: sound'i'

    # Mono copy for analysis
    if nCh'i' > 1
        Extract one channel: 1
        monoSnd = selected("Sound")
    else
        Copy: "tmpMono_" + string$(i)
        monoSnd = selected("Sound")
    endif

    # Pitch
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

    # Intensity
    selectObject: monoSnd
    To Intensity: 100, 0, "yes"
    intObj = selected("Intensity")
    meanInt   = Get mean: 0, 0, "dB"
    minInt    = Get minimum: 0, 0, "Parabolic"
    maxInt    = Get maximum: 0, 0, "Parabolic"
    intRange  = maxInt - minInt
    removeObject: intObj

    # Harmonicity (HNR)
    selectObject: monoSnd
    To Harmonicity (cc): 0.01, 75, 0.1, 1.0
    hnrObj = selected("Harmonicity")
    hnr    = Get mean: 0, 0
    if hnr = undefined
        hnr = 0
    endif
    removeObject: hnrObj

    # Spectral centroid estimate via LPC
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

    # Write descriptor row
    appendFileLine: descriptorFile$, string$(i) + tab$ + soundName'i'$ + tab$ + fixed$(dur'i', 4) + tab$ + fixed$(rms'i', 6) + tab$ + fixed$(meanPitch, 2) + tab$ + fixed$(pitchRange, 2) + tab$ + fixed$(meanInt, 2) + tab$ + fixed$(intRange, 2) + tab$ + fixed$(centroid_est, 1) + tab$ + fixed$(hnr, 2)
endfor

appendInfoLine: "  Descriptors written for ", nSounds, " sounds"

# ---- STEP 3: LAUNCH PYTHON CONDUCTOR ----
appendInfoLine: "[2/5] Launching PyTorch conductor (async)..."

if fileReadable(doneFile$)
    deleteFile: doneFile$
endif
if fileReadable(mixPlanFile$)
    deleteFile: mixPlanFile$
endif
if fileReadable(logFile$)
    deleteFile: logFile$
endif

q$ = """"

pyArgs$ = " " + q$ + manifestFile$ + q$ + " " + q$ + descriptorFile$ + q$ + " " + q$ + mixPlanFile$ + q$ + " " + q$ + doneFile$ + q$ + " --style " + cStyle$ + " --seg_mode " + segMode$ + " --frame_ms " + string$(frame_size_ms) + " --hop_ms " + string$(frame_hop_ms) + " --onset_gap_ms " + string$(min_onset_gap_ms) + " --memory " + fixed$(memWeight, 3) + " --tension " + fixed$(tensionSens, 3) + " --allow_silence " + string$(allowSilence) + " --nonlinear " + string$(nonlinear)

if windows
    cmd$ = "start /b " + pythonCmd$ + " " + q$ + pythonScript$ + q$ + pyArgs$ + " > " + q$ + logFile$ + q$ + " 2>&1"
else
    cmd$ = pythonCmd$ + " " + q$ + pythonScript$ + q$ + pyArgs$ + " > " + q$ + logFile$ + q$ + " 2>&1 &"
endif

runSystem_nocheck: cmd$

# ---- STEP 4: POLL FOR COMPLETION ----
appendInfoLine: "[3/5] Waiting for conductor plan..."

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

# Read log
if fileReadable(logFile$)
    log$ = readFile$(logFile$)
    appendInfoLine: log$
    deleteFile: logFile$
endif

deleteFile: doneFile$
deleteFile: manifestFile$
deleteFile: descriptorFile$

# Delete exported WAVs
for i from 1 to nSounds
    deleteFile: pluginDir$ + "conductor_input_" + string$(i) + ".wav"
endfor

if waited >= maxWait and gotPlan = 0
    exitScript: "Timed out waiting for AI conductor (10 min). Check Python environment."
endif

if not fileReadable(mixPlanFile$)
    exitScript: "Conductor plan not produced. See log for errors."
endif

appendInfoLine: "  Plan received."

# ---- STEP 5: READ MIX PLAN AND RENDER ----
appendInfoLine: "[4/5] Rendering conducted mix..."

planText$ = readFile$(mixPlanFile$)

if length(planText$) < 10
    exitScript: "Mix plan is empty or malformed."
endif

# ---- Extract max_dur from sentinel line ----
sentinel$ = mid$(planText$, 1, index(planText$, newline$) - 1)
eqPos     = index(sentinel$, "=")
totalDur  = 0
if eqPos > 0
    totalDur = number(mid$(sentinel$, eqPos + 1, length(sentinel$)))
endif

# Safety fallback loop
if totalDur < 0.1
    lineStart = index(planText$, newline$) + 1
    lineStart = lineStart + index(mid$(planText$, lineStart, length(planText$)), newline$)
    repeat
        lineEnd = index(mid$(planText$, lineStart, length(planText$)), newline$)
        if lineEnd > 0
            line$ = mid$(planText$, lineStart, lineEnd - 1)
        else
            line$ = mid$(planText$, lineStart, length(planText$))
        endif
        if length(line$) > 2
            colNum = 0
            fieldStart = 1
            exitTimeVal = 0
            repeat
                tabPos = index(mid$(line$, fieldStart, length(line$)), tab$)
                if tabPos > 0
                    field$ = mid$(line$, fieldStart, tabPos - 1)
                    fieldStart = fieldStart + tabPos
                else
                    field$ = mid$(line$, fieldStart, length(line$))
                    tabPos = 0
                endif
                colNum += 1
                if colNum = 11
                    exitTimeVal = number(field$)
                endif
            until tabPos = 0 or colNum >= 15
            if exitTimeVal > totalDur
                totalDur = exitTimeVal
            endif
        endif
        lineStart = lineStart + lineEnd
    until lineEnd = 0 or lineStart > length(planText$)
endif

if totalDur < 0.1
    totalDur = 10
endif

appendInfoLine: "  Canvas duration: ", fixed$(totalDur, 2), " s (longest source file)"

# Create silent output canvas
sr_out = sr1
if stereo_panorama
    Create Sound from formula: "conductedMix", 2, 0, totalDur, sr_out, "0"
else
    Create Sound from formula: "conductedMix", 1, 0, totalDur, sr_out, "0"
endif
mixObj = selected("Sound")

# Parse plan again and composite segments
lineStart = index(planText$, newline$) + 1
lineStart = lineStart + index(mid$(planText$, lineStart, length(planText$)), newline$)

nRendered = 0
repeat
    lineEnd = index(mid$(planText$, lineStart, length(planText$)), newline$)
    if lineEnd > 0
        line$ = mid$(planText$, lineStart, lineEnd - 1)
    else
        line$ = mid$(planText$, lineStart, length(planText$))
    endif

    if length(line$) > 2
        colNum = 0
        fieldStart = 1
        fIdx       = 0
        srcStart   = 0
        srcDur     = 0
        gainVal    = 1
        entryTime  = 0
        exitTimeP  = 0
        transformP = 0

        repeat
            tabPos = index(mid$(line$, fieldStart, length(line$)), tab$)
            if tabPos > 0
                field$ = mid$(line$, fieldStart, tabPos - 1)
                fieldStart = fieldStart + tabPos
            else
                field$ = mid$(line$, fieldStart, length(line$))
                tabPos = 0
            endif
            colNum += 1
            if colNum = 2
                fIdx      = number(field$)
            elsif colNum = 5
                srcStart  = number(field$)
            elsif colNum = 6
                srcDur    = number(field$)
            elsif colNum = 7
                gainVal   = number(field$)
            elsif colNum = 10
                entryTime = number(field$)
            elsif colNum = 11
                exitTimeP = number(field$)
            elsif colNum = 12
                transformP = number(field$)
            endif
        until tabPos = 0 or colNum >= 15

        if fIdx >= 1 and fIdx <= nSounds and srcDur > 0.001 and gainVal > 0.0001
            selectObject: sound'fIdx'

            srcEnd = srcStart + srcDur
            srcTotalDur = dur'fIdx'
            if srcStart < 0
                srcStart = 0
            endif
            if srcEnd > srcTotalDur
                srcEnd = srcTotalDur
            endif
            if srcEnd - srcStart > 0.001
                Extract part: srcStart, srcEnd, "rectangular", 1, "no"
                segSnd = selected("Sound")

                selectObject: segSnd
                nSegCh = Get number of channels
                if nSegCh > 1
                    Convert to mono
                    monoSeg = selected("Sound")
                    removeObject: segSnd
                    segSnd = monoSeg
                endif

                Multiply: gainVal

                if transformP > 0.05
                    fadeLen = min(0.02, (srcEnd - srcStart) * 0.15)
                    Fade in:  0, 0, fadeLen, "no"
                    Fade out: 0, srcEnd - srcStart, -fadeLen, "no"
                endif

                if sr'fIdx' <> sr_out
                    Resample: sr_out, 50
                    tmpResampled = selected("Sound")
                    removeObject: segSnd
                    segSnd = tmpResampled
                endif

                # ---- Place segment into canvas ----
                nRendered += 1
                segSndStr$  = string$(segSnd)
                tStart$     = fixed$(entryTime, 6)
                segEnd      = entryTime + srcDur
                if segEnd > totalDur
                    segEnd = totalDur
                endif
                tEnd$       = fixed$(segEnd, 6)

                selectObject: mixObj
                if stereo_panorama
                    lGain$ = string$(leftGain'fIdx')
                    rGain$ = string$(rightGain'fIdx')
                    # Apply constant power stereo routing based on the 'row' parameter (channel index)
                    Formula: "if x >= " + tStart$ + " and x <= " + tEnd$ + " then self + object(" + segSndStr$ + ", x - " + tStart$ + ") * (if row = 1 then " + lGain$ + " else " + rGain$ + " fi) else self fi"
                else
                    Formula: "if x >= " + tStart$ + " and x <= " + tEnd$ + " then self + object(" + segSndStr$ + ", x - " + tStart$ + ") else self fi"
                endif

                removeObject: segSnd
            endif
        endif
    endif

    lineStart = lineStart + lineEnd
until lineEnd = 0 or lineStart > length(planText$)

selectObject: mixObj
Rename: "ConductedMix"
Scale peak: 0.95

appendInfoLine: "  Rendered: ", nRendered, " segments into mix (", fixed$(totalDur, 2), " s)"

if not export_mix_plan
    deleteFile: mixPlanFile$
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Drawing visualization..."

    # Safety wrapper for UI drawing: force mono for Spectrogram logic
    selectObject: mixObj
    if stereo_panorama
        mixDraw = Convert to mono
    else
        mixDraw = mixObj
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 10

    # --- Title panel ---
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##AI Conductor Mix##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    if stereo_panorama
        Text: 0.5, "centre", -1.0, "half", "Style: " + cStyle$ + "  | Output: Stereo | Files: " + string$(nSounds) + "  | Segs: " + string$(nRendered)
    else
        Text: 0.5, "centre", -1.0, "half", "Style: " + cStyle$ + "  | Output: Mono | Files: " + string$(nSounds) + "  | Segs: " + string$(nRendered)
    endif

    # --- Individual input waveforms ---
    panelH = 1.1
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
        Font size: 7
        Text left: "yes", soundName'i'$
        yTop = yBot
    endfor

    # --- Conducted mix waveform ---
    yBot = yTop + 1.3
    Select outer viewport: 0, 8, yTop, yBot
    Select inner viewport: 0.7, 7.7, yTop + 0.05, yBot - 0.1
    selectObject: mixDraw
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Conducted"
    Text bottom: "yes", "Time (s)"
    yTop = yBot

    # --- Mix spectrogram ---
    yBot = yTop + 2.0
    Select outer viewport: 0, 8, yTop, yBot
    Select inner viewport: 0.7, 7.7, yTop + 0.05, yBot - 0.1

    selectObject: mixDraw
    To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    specMix = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top:  "no", "Mix Spectrogram"
    Text bottom: "yes", "Time (s)"
    removeObject: specMix

    # Clean up mono draw object if we created one
    if stereo_panorama
        removeObject: mixDraw
    endif

    # --- Stats box ---
    yTop = yBot + 0.1
    Select outer viewport: 0, 8, yTop, yTop + 0.9
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.75, "half", "Segments: " + string$(nRendered) + "   Duration: " + fixed$(totalDur, 2) + " s" + "   Style: " + cStyle$ + "   Memory: " + fixed$(memWeight, 2) + "   Tension: " + fixed$(tensionSens, 2)
endif

# ---- PLAY ----
if play_result
    selectObject: mixObj
    Play
endif

# ---- DONE ----
appendInfoLine: ""
appendInfoLine: "=== Conducted mix complete ==="
appendInfoLine: "Output: ConductedMix (" + fixed$(totalDur, 2) + " s)"
if export_mix_plan
    appendInfoLine: "Mix plan saved: " + mixPlanFile$
endif