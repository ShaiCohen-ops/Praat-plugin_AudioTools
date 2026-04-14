# ============================================================
# Praat AudioTools - SuperVP_Transform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SuperVP spectral transform bridge.
#   Exports selected Sound(s) to WAV, extracts F0 + Intensity BPFs
#   via Praat analysis, then sends all data to a Python backend
#   which builds parameter files and calls SuperVP.exe.
#   Praat reads the processed WAV back and optionally visualises.
#
#   Uses a repeat/Apply loop — the form stays open between runs
#   so parameters can be tweaked without re-entering from scratch.
#
#   Modes:
#     Age          - voice aging / rejuvenation  (-age)
#     Gender       - male <-> female morph        (-male / -female)
#     Flatten pitch- normalise F0 to median       (-transke + BPF)
#     Time stretch - F0-adaptive time dilation    (-D + -Mauto)
#     Tremolo      - intensity-envelope tremolo   (-trmdle)
#     Cross synth  - spectral cross-synthesis     (-Gcross)  [2 sounds]
#     Vibrato      - pitch vibrato modulation
#     Breathiness  - breathiness amount control
#     Formant shift- formant frequency shifting
#     Harmoniser   - pitch harmoniser / doubler
#     De-noise     - spectral noise reduction
#     Age + Gender - combined age and gender transform
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: SuperVP Transform.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
nSounds = numberOfSelected("Sound")
if nSounds < 1
    exitScript: "Please select at least 1 Sound object."
endif

for i from 1 to nSounds
    sound'i' = selected("Sound", i)
    soundName'i'$ = selected$("Sound", i)
endfor

# ---- PLATFORM ----
if windows
    sep$      = "\"
    platform$ = "Windows"
else
    sep$      = "/"
    platform$ = "macOS/Linux"
endif

# ---- PATHS ----
pluginDir$      = preferencesDirectory$ + sep$ + "plugin_AudioTools" + sep$
pythonScript$   = pluginDir$ + "py" + sep$ + "supervp_transform.py"
inputWav1$      = pluginDir$ + "svp_input_1.wav"
inputWav2$      = pluginDir$ + "svp_input_2.wav"
f0File$         = pluginDir$ + "svp_f0.bpf"
intensityFile$  = pluginDir$ + "svp_intensity.bpf"
resultWavFile$  = pluginDir$ + "svp_result.wav"
logFile$        = pluginDir$ + "svp_log.txt"
doneFile$       = pluginDir$ + "svp_done.txt"

createFolder: pluginDir$
createFolder: pluginDir$ + "py"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$
endif

# ---- DETECT PYTHON (3-candidate probe, runs once at startup) ----
probeMarker$ = pluginDir$ + "svp_probe.ok"

if windows
    nPyCandidates = 3
    pyCandidate1$ = "python"
    pyCandidate2$ = "py"
    pyCandidate3$ = "python3"
else
    nPyCandidates = 3
    pyCandidate1$ = "python3"
    pyCandidate2$ = "python"
    pyCandidate3$ = "py"
endif

pythonCmd$ = ""
for iCand from 1 to nPyCandidates
    if iCand = 1
        tryCmd$ = pyCandidate1$
    elsif iCand = 2
        tryCmd$ = pyCandidate2$
    else
        tryCmd$ = pyCandidate3$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    probeCode$ = "import sys,os,subprocess,struct,math,wave; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
    endif
    if pythonCmd$ <> ""
        iCand = nPyCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    exitScript: "Cannot find a working Python installation." + newline$
        ... + "Tried: " + pyCandidate1$ + ", " + pyCandidate2$ + ", " + pyCandidate3$ + newline$
        ... + "Please install Python 3 and ensure it is on your PATH."
endif

# ============================================================
# DEFAULT VALUES FOR THE LOOP
# ============================================================
v_supervpExe$          = "C:\Users\User\SuperVP\bin\supervp.exe"
v_mode                 = 1
v_age_years            = 20
v_gender_direction     = 1
v_gender_amount        = 3
v_target_f0_hz         = 0
v_stretch_factor       = 1.5
v_tremolo_freq_hz      = 5.0
v_tremolo_depth_cents  = 30
v_cross_mix            = 0.5
v_vibrato_freq_hz      = 5.5
v_vibrato_depth_cents  = 50
v_breathiness_amount   = 0.4
v_formant_shift_cents  = 200
v_harmoniser_interval  = 700
v_harmoniser_mix       = 0.3
v_denoise_threshold_db = 30
v_draw                 = 1
v_play                 = 1
prevResultID           = 0

# ============================================================
# MAIN LOOP
# ============================================================
repeat

    beginPause: "SuperVP Transform v2.2  (" + soundName1$ + ")"

        comment: "=== SUPERVP PATH ==="
        sentence: "SuperVP executable", v_supervpExe$

        comment: "=== MODE ==="
        optionMenu: "Mode", v_mode
            option: "Age"
            option: "Gender"
            option: "Flatten pitch"
            option: "Time stretch"
            option: "Tremolo"
            option: "Cross synth  (select 2 sounds)"
            option: "Vibrato"
            option: "Breathiness"
            option: "Formant shift"
            option: "Harmoniser"
            option: "De-noise"
            option: "Age + Gender"

        comment: "=== PARAMETERS ==="
        integer: "Age years", v_age_years
        optionMenu: "Gender direction", v_gender_direction
            option: "To female"
            option: "To male"
        integer: "Gender amount", v_gender_amount
        real: "Target f0 hz", v_target_f0_hz
        positive: "Stretch factor", v_stretch_factor
        positive: "Tremolo freq hz", v_tremolo_freq_hz
        positive: "Tremolo depth cents", v_tremolo_depth_cents
        real: "Cross mix", v_cross_mix
        positive: "Vibrato freq hz", v_vibrato_freq_hz
        positive: "Vibrato depth cents", v_vibrato_depth_cents
        real: "Breathiness amount", v_breathiness_amount
        integer: "Formant shift cents", v_formant_shift_cents
        real: "Harmoniser interval cents", v_harmoniser_interval
        real: "Harmoniser mix", v_harmoniser_mix
        positive: "Denoise threshold db", v_denoise_threshold_db

        comment: "=== OUTPUT ==="
        boolean: "Draw visualization", v_draw
        boolean: "Play result", v_play

    clicked = endPause: "Close", "Apply", 2, 1

    # ---- Save values for next iteration ----
    v_supervpExe$          = superVP_executable$
    v_mode                 = mode
    v_age_years            = age_years
    v_gender_direction     = gender_direction
    v_gender_amount        = gender_amount
    v_target_f0_hz         = target_f0_hz
    v_stretch_factor       = stretch_factor
    v_tremolo_freq_hz      = tremolo_freq_hz
    v_tremolo_depth_cents  = tremolo_depth_cents
    v_cross_mix            = cross_mix
    v_vibrato_freq_hz      = vibrato_freq_hz
    v_vibrato_depth_cents  = vibrato_depth_cents
    v_breathiness_amount   = breathiness_amount
    v_formant_shift_cents  = formant_shift_cents
    v_harmoniser_interval  = harmoniser_interval_cents
    v_harmoniser_mix       = harmoniser_mix
    v_denoise_threshold_db = denoise_threshold_db
    v_draw                 = draw_visualization
    v_play                 = play_result

    if clicked = 1
        appendInfoLine: "SuperVP Transform closed."
        exitScript: ""
    endif

    # ---- Verify SuperVP binary ----
    supervpExe$ = superVP_executable$
    if not fileReadable(supervpExe$)
        appendInfoLine: "ERROR: SuperVP executable not found: ", supervpExe$
        appendInfoLine: "Please correct the path and click Apply again."
        goto LOOP_END
    endif

    # ---- Map mode number to string ----
    if mode = 1
        mode$ = "age"
    elsif mode = 2
        mode$ = "gender"
    elsif mode = 3
        mode$ = "flatten_pitch"
    elsif mode = 4
        mode$ = "time_stretch"
    elsif mode = 5
        mode$ = "tremolo"
    elsif mode = 6
        mode$ = "cross"
    elsif mode = 7
        mode$ = "vibrato"
    elsif mode = 8
        mode$ = "breathiness"
    elsif mode = 9
        mode$ = "formant_shift"
    elsif mode = 10
        mode$ = "harmoniser"
    elsif mode = 11
        mode$ = "denoise"
    elsif mode = 12
        mode$ = "age_gender"
    endif

    # ---- Validation ----
    if mode$ = "cross" and nSounds < 2
        appendInfoLine: "ERROR: Cross synth requires 2 selected Sound objects."
        goto LOOP_END
    endif

    if cross_mix < 0
        cross_mix = 0
    endif
    if cross_mix > 1
        cross_mix = 1
    endif
    if breathiness_amount < 0
        breathiness_amount = 0
    endif
    if breathiness_amount > 1
        breathiness_amount = 1
    endif
    if harmoniser_mix < 0
        harmoniser_mix = 0
    endif
    if harmoniser_mix > 1
        harmoniser_mix = 1
    endif

    if gender_direction = 1
        genderDir$ = "female"
    else
        genderDir$ = "male"
    endif

    # ---- Remove previous result ----
    if prevResultID > 0
        removeObject: prevResultID
        prevResultID = 0
    endif

    # ---- Info header ----
    clearinfo
    writeInfoLine:  "=== SuperVP Transform v2.2 ==="
    appendInfoLine: "Platform:  ", platform$
    appendInfoLine: "Python:    ", pythonCmd$
    appendInfoLine: "SuperVP:   ", supervpExe$
    appendInfoLine: "Mode:      ", mode$
    appendInfoLine: "Source:    ", soundName1$
    appendInfoLine: ""

    # ---- Prep input files ----
    deleteFile: inputWav1$
    deleteFile: inputWav2$
    deleteFile: f0File$
    deleteFile: intensityFile$
    deleteFile: resultWavFile$
    deleteFile: doneFile$
    deleteFile: logFile$

    selectObject: sound1
    Save as WAV file: inputWav1$

    if nSounds >= 2
        selectObject: sound2
        Save as WAV file: inputWav2$
    endif

    # ---- F0 / Intensity analysis ----
    needF0 = 0
    needIntensity = 0
    if mode$ = "flatten_pitch" or mode$ = "time_stretch" or mode$ = "vibrato" or mode$ = "harmoniser"
        needF0 = 1
    endif
    if mode$ = "tremolo" or mode$ = "breathiness" or mode$ = "denoise"
        needIntensity = 1
    endif

    if needF0 or needIntensity
        analysisPitchFloor   = 75
        analysisPitchCeiling = 600
        exportStep           = 0.01

        selectObject: sound1
        tmin = Get start time
        tmax = Get end time

        appendInfoLine: "Preparing analysis tracks..."

        if needF0
            selectObject: sound1
            To Pitch: 0, analysisPitchFloor, analysisPitchCeiling
            pitchObj = selected("Pitch")
        endif

        if needIntensity
            selectObject: sound1
            To Intensity: analysisPitchFloor, 0, "no"
            intensityObj = selected("Intensity")
        endif

        time = tmin
        while time <= tmax + exportStep / 2
            if needF0
                selectObject: pitchObj
                f0 = Get value at time: time, "Hertz", "Linear"
                if f0 = undefined
                    f0 = 0
                endif
                appendFileLine: f0File$, fixed$(time, 6), " ", fixed$(f0, 6)
            endif
            if needIntensity
                selectObject: intensityObj
                dB = Get value at time: time, "Cubic"
                if dB = undefined
                    dB = 0
                endif
                appendFileLine: intensityFile$, fixed$(time, 6), " ", fixed$(dB, 6)
            endif
            time = time + exportStep
        endwhile

        if needF0 and needIntensity
            selectObject: pitchObj, intensityObj
            Remove
        elsif needF0
            selectObject: pitchObj
            Remove
        elsif needIntensity
            selectObject: intensityObj
            Remove
        endif

        appendInfoLine: "Analysis export done."
    else
        appendInfoLine: "No F0 / intensity analysis needed for this mode."
    endif

    appendInfoLine: ""
    appendInfoLine: "Running SuperVP..."

    # ---- Run Python ----
    if mode$ = "cross" and nSounds >= 2
        runSubprocess: pythonCmd$,
            ... pythonScript$,
            ... inputWav1$,
            ... f0File$,
            ... intensityFile$,
            ... doneFile$,
            ... "--supervp_exe",          supervpExe$,
            ... "--result_wav",           resultWavFile$,
            ... "--mode",                 mode$,
            ... "--cross_mix",            string$(cross_mix),
            ... "--input_wav2",           inputWav2$,
            ... "--age_val",              string$(age_years),
            ... "--gender_dir",           genderDir$,
            ... "--gender_amount",        string$(gender_amount),
            ... "--target_f0",            string$(target_f0_hz),
            ... "--stretch_factor",       string$(stretch_factor),
            ... "--tremolo_freq",         string$(tremolo_freq_hz),
            ... "--tremolo_depth",        string$(tremolo_depth_cents),
            ... "--vibrato_freq",         string$(vibrato_freq_hz),
            ... "--vibrato_depth",        string$(vibrato_depth_cents),
            ... "--breathiness_amount",   string$(breathiness_amount),
            ... "--formant_shift_cents",  string$(formant_shift_cents),
            ... "--harmoniser_interval",  string$(harmoniser_interval_cents),
            ... "--harmoniser_mix",       string$(harmoniser_mix),
            ... "--denoise_threshold_db", string$(denoise_threshold_db)
    else
        runSubprocess: pythonCmd$,
            ... pythonScript$,
            ... inputWav1$,
            ... f0File$,
            ... intensityFile$,
            ... doneFile$,
            ... "--supervp_exe",          supervpExe$,
            ... "--result_wav",           resultWavFile$,
            ... "--mode",                 mode$,
            ... "--age_val",              string$(age_years),
            ... "--gender_dir",           genderDir$,
            ... "--gender_amount",        string$(gender_amount),
            ... "--target_f0",            string$(target_f0_hz),
            ... "--stretch_factor",       string$(stretch_factor),
            ... "--tremolo_freq",         string$(tremolo_freq_hz),
            ... "--tremolo_depth",        string$(tremolo_depth_cents),
            ... "--cross_mix",            string$(cross_mix),
            ... "--vibrato_freq",         string$(vibrato_freq_hz),
            ... "--vibrato_depth",        string$(vibrato_depth_cents),
            ... "--breathiness_amount",   string$(breathiness_amount),
            ... "--formant_shift_cents",  string$(formant_shift_cents),
            ... "--harmoniser_interval",  string$(harmoniser_interval_cents),
            ... "--harmoniser_mix",       string$(harmoniser_mix),
            ... "--denoise_threshold_db", string$(denoise_threshold_db)
    endif

    # ---- Load result ----
    doneOk = 0
    if fileReadable(doneFile$)
        doneStatus$ = readFile$(doneFile$)
        doneStatus$ = replace$(doneStatus$, newline$, "", 0)
        if doneStatus$ = "ok"
            doneOk = 1
        endif
    endif

    if doneOk and fileReadable(resultWavFile$)
        resultName$ = soundName1$ + "_svp_" + mode$
        Read from file: resultWavFile$
        resultObj = selected("Sound")
        Rename: resultName$
        prevResultID = resultObj

        appendInfoLine: "Done! Result loaded: ", resultName$

        # ---- Visualization ----
        if draw_visualization
            appendInfoLine: "Drawing visualization..."

            selectObject: sound1
            dur1 = Get total duration

            selectObject: resultObj
            resultDur  = Get total duration
            resultSr   = Get sampling frequency
            resultMono = Convert to mono

            Erase all
            Select outer viewport: 0, 8, 0, 7

            # Title
            Select outer viewport: 0, 8, 0, 0.5
            Axes: 0, 1, 0, 1
            Font size: 12
            Colour: "Black"
            Text: 0.5, "centre", 0.65, "half", "##SuperVP Transform: " + mode$ + "##"
            Font size: 7
            Colour: "{0.4, 0.4, 0.5}"
            Text: 0.5, "centre", -0.8, "half", soundName1$ + "  ->  " + resultName$

            # Original waveform
            Select outer viewport: 0, 8, 0.5, 2.0
            Select inner viewport: 0.7, 7.7, 0.55, 1.95
            selectObject: sound1
            Colour: "{0.4, 0.5, 0.7}"
            Draw: 0, 0, 0, 0, "no", "Curve"
            Colour: "Black"
            Draw inner box
            Font size: 6
            Text left: "yes", "Original"

            # Result waveform
            Select outer viewport: 0, 8, 2.0, 3.5
            Select inner viewport: 0.7, 7.7, 2.05, 3.45
            selectObject: resultObj
            Colour: "{0.3, 0.6, 0.45}"
            Draw: 0, 0, 0, 0, "no", "Curve"
            Colour: "Black"
            Draw inner box
            Font size: 6
            Text left: "yes", "Transformed"

            # F0 contour
            if needF0
                selectObject: sound1
                To Pitch: 0, 75, 600
                pitchViz = selected("Pitch")

                Select outer viewport: 0, 8, 3.5, 4.8
                Select inner viewport: 0.7, 7.7, 3.55, 4.75
                Axes: 0, dur1, 50, 600
                Paint rectangle: "{0.95, 0.95, 0.97}", 0, dur1, 50, 600
                selectObject: pitchViz
                Colour: "{0.7, 0.3, 0.3}"
                Draw: 0, 0, 50, 600, "no"
                Colour: "Black"
                Draw inner box
                Font size: 6
                Text left: "yes", "F0 (Hz)"
                removeObject: pitchViz
            endif

            # Result spectrogram
            Select outer viewport: 0, 8, 4.8, 6.6
            Select inner viewport: 0.7, 7.7, 4.85, 6.55
            selectObject: resultMono
            specStep = max(0.002, resultDur / 2000)
            To Spectrogram: 0.01, 5000, specStep, 20, "Gaussian"
            specObj = selected("Spectrogram")
            Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
            Colour: "Black"
            Draw inner box
            Font size: 6
            Text left: "yes", "Freq (Hz)"
            Text bottom: "yes", "Time (s)"
            Text top: "no", "Result Spectrogram"
            removeObject: specObj

            # Stats bar
            Select outer viewport: 0, 8, 6.6, 7.0
            Axes: 0, 1, 0, 1
            Font size: 6
            Colour: "Black"
            Text: 0.02, "left", 0.6, "half",
                ... "Mode: " + mode$
                ... + "   In: " + fixed$(dur1, 2) + " s"
                ... + " -> Out: " + fixed$(resultDur, 2) + " s"
                ... + "   SR: " + string$(resultSr) + " Hz"

            removeObject: resultMono
        endif

        if play_result
            selectObject: resultObj
            Play
        endif

        # Cleanup temp files on success
        deleteFile: inputWav1$
        deleteFile: inputWav2$
        deleteFile: f0File$
        deleteFile: intensityFile$
        deleteFile: resultWavFile$
        deleteFile: doneFile$
        deleteFile: logFile$

    else
        appendInfoLine: "ERROR: Transform failed."
        if fileReadable(logFile$)
            appendInfoLine: ""
            appendInfoLine: "=== Python / SuperVP log ==="
            appendInfoLine: readFile$(logFile$)
        endif
        # Preserve log on failure
        deleteFile: inputWav1$
        deleteFile: inputWav2$
        deleteFile: f0File$
        deleteFile: intensityFile$
        deleteFile: resultWavFile$
        deleteFile: doneFile$
        appendInfoLine: "Log preserved at: ", logFile$
    endif

    appendInfoLine: ""
    appendInfoLine: "=== Apply complete — adjust parameters and click Apply again, or Close ==="
    appendInfoLine: ""

    label LOOP_END

until 0
