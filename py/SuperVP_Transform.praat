# ============================================================
# Praat AudioTools - SuperVP_Transform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
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
#   Modes:
#     Age          - voice aging / rejuvenation  (-age)
#     Gender       - male <-> female morph        (-male / -female)
#     Flatten pitch- normalise F0 to median       (-transke + BPF)
#     Time stretch - F0-adaptive time dilation    (-D + -Mauto)
#     Tremolo      - intensity-envelope tremolo   (-trmdle)
#     Cross synth  - spectral cross-synthesis     (-Gcross)  [2 sounds]
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

# ---- PATHS ----
if windows
    sep$ = "\"
    pythonCmd$ = "py"
    platform$ = "Windows"
else
    sep$ = "/"
    pythonCmd$ = "python3"
    platform$ = "macOS/Linux"
endif

pluginDir$      = preferencesDirectory$ + sep$ + "plugin_AudioTools" + sep$
pythonScript$   = pluginDir$ + "py" + sep$ + "supervp_transform.py"
inputWav1$      = pluginDir$ + "svp_input_1.wav"
inputWav2$      = pluginDir$ + "svp_input_2.wav"
f0File$         = pluginDir$ + "svp_f0.bpf"
intensityFile$  = pluginDir$ + "svp_intensity.bpf"
resultWavFile$  = pluginDir$ + "svp_result.wav"
logFile$        = pluginDir$ + "svp_log.txt"
doneFile$       = pluginDir$ + "svp_done.txt"

supervpExe$ = "C:\Users\User\SuperVP\bin\supervp.exe"

createFolder: pluginDir$
createFolder: pluginDir$ + "py"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$
endif

# ---- PERSISTENT DEFAULTS ----
age_years = 20
gender_direction = 1
gender_amount = 3
target_f0_hz = 0
stretch_factor = 1.5
tremolo_freq_hz = 5.0
tremolo_depth_cents = 30
cross_mix = 0.5
vibrato_freq_hz = 5.5
vibrato_depth_cents = 50
breathiness_amount = 0.4
formant_shift_cents = 200
harmoniser_interval_cents = 700
harmoniser_mix = 0.3
denoise_threshold_db = 30

draw_visualization = 1
play_result = 1
mode = 1

# ============================================================
# ---- START CONTINUOUS UI LOOP ----
# ============================================================
repeat

    # ---- STEP 1: GLOBAL SETUP ----
    beginPause: "SuperVP Transform v2.5 - Setup"
        comment: "=== Transform Mode ==="
        choice: "mode", mode
            option: "Age"
            option: "Gender"
            option: "Flatten pitch"
            option: "Time stretch"
            option: "Tremolo"
            option: "Cross synth (select 2 sounds)"
            option: "Vibrato"
            option: "Breathiness"
            option: "Formant shift"
            option: "Harmoniser"
            option: "De-noise"
            option: "Age + Gender"

        comment: "=== Output ==="
        boolean: "draw_visualization", draw_visualization
        boolean: "play_result", play_result
    clicked1 = endPause: "Quit", "Next >", 2, 1

    if clicked1 == 1
        exitScript: "SuperVP session ended."
    endif

    if mode == 1
        mode$ = "age"
    elsif mode == 2
        mode$ = "gender"
    elsif mode == 3
        mode$ = "flatten_pitch"
    elsif mode == 4
        mode$ = "time_stretch"
    elsif mode == 5
        mode$ = "tremolo"
    elsif mode == 6
        mode$ = "cross"
    elsif mode == 7
        mode$ = "vibrato"
    elsif mode == 8
        mode$ = "breathiness"
    elsif mode == 9
        mode$ = "formant_shift"
    elsif mode == 10
        mode$ = "harmoniser"
    elsif mode == 11
        mode$ = "denoise"
    elsif mode == 12
        mode$ = "age_gender"
    endif

    # ---- STEP 2: SETTINGS ----
    if mode == 1
        beginPause: "Settings: Age"
            integer: "age_years", age_years
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 2
        beginPause: "Settings: Gender"
            choice: "gender_direction", gender_direction
                option: "To female"
                option: "To male"
            integer: "gender_amount", gender_amount
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 3
        beginPause: "Settings: Flatten Pitch"
            real: "target_f0_hz", target_f0_hz
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 4
        beginPause: "Settings: Time Stretch"
            positive: "stretch_factor", stretch_factor
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 5
        beginPause: "Settings: Tremolo"
            positive: "tremolo_freq_hz", tremolo_freq_hz
            positive: "tremolo_depth_cents", tremolo_depth_cents
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 6
        beginPause: "Settings: Cross Synth"
            real: "cross_mix", cross_mix
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 7
        beginPause: "Settings: Vibrato"
            positive: "vibrato_freq_hz", vibrato_freq_hz
            positive: "vibrato_depth_cents", vibrato_depth_cents
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 8
        beginPause: "Settings: Breathiness"
            real: "breathiness_amount", breathiness_amount
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 9
        beginPause: "Settings: Formant Shift"
            integer: "formant_shift_cents", formant_shift_cents
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 10
        beginPause: "Settings: Harmoniser"
            real: "harmoniser_interval_cents", harmoniser_interval_cents
            real: "harmoniser_mix", harmoniser_mix
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 11
        beginPause: "Settings: De-noise"
            positive: "denoise_threshold_db", denoise_threshold_db
        clicked2 = endPause: "< Back", "Run", 2, 1
    elsif mode == 12
        beginPause: "Settings: Age + Gender"
            integer: "age_years", age_years
            choice: "gender_direction", gender_direction
                option: "To female"
                option: "To male"
            integer: "gender_amount", gender_amount
        clicked2 = endPause: "< Back", "Run", 2, 1
    endif

    if clicked2 == 2

        # ---- STEP 3: VALIDATION ----
        if mode$ = "cross" and nSounds < 2
            clearinfo
            writeInfoLine: "ERROR: Cross synth requires 2 selected Sound objects."
            pauseScript: "Select 2 sounds, then run again."
        else

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

            if gender_direction == 1
                genderDir$ = "female"
            else
                genderDir$ = "male"
            endif

            # ---- STEP 4: PREP INPUT FILES ----
            clearinfo
            writeInfoLine:  "=== SuperVP Transform v2.5 ==="
            appendInfoLine: "Mode:     ", mode$
            appendInfoLine: "Platform: ", platform$

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

            # Create analysis contours only for modes that actually use them.
            # This avoids unnecessary work (and apparent freezing) for modes like
            # age, gender, formant_shift, cross, and age_gender.
            needF0 = 0
            needIntensity = 0
            if mode$ = "flatten_pitch" or mode$ = "time_stretch" or mode$ = "vibrato" or mode$ = "harmoniser"
                needF0 = 1
            endif
            if mode$ = "tremolo" or mode$ = "breathiness" or mode$ = "denoise"
                needIntensity = 1
            endif

            if needF0 or needIntensity
                analysisPitchFloor = 75
                analysisPitchCeiling = 600
                exportStep = 0.01

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
                        appendFileLine: f0File$, fixed$ (time, 6), " ", fixed$ (f0, 6)
                    endif

                    if needIntensity
                        selectObject: intensityObj
                        dB = Get value at time: time, "Cubic"
                        if dB = undefined
                            dB = 0
                        endif
                        appendFileLine: intensityFile$, fixed$ (time, 6), " ", fixed$ (dB, 6)
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

            # ---- STEP 5: BUILD PYTHON COMMAND ----
            dq$ = """"
            cmd$ = pythonCmd$ + " "
            cmd$ = cmd$ + dq$ + pythonScript$     + dq$ + " "
            cmd$ = cmd$ + dq$ + inputWav1$        + dq$ + " "
            cmd$ = cmd$ + dq$ + f0File$           + dq$ + " "
            cmd$ = cmd$ + dq$ + intensityFile$    + dq$ + " "
            cmd$ = cmd$ + dq$ + doneFile$         + dq$ + " "
            cmd$ = cmd$ + "--supervp_exe " + dq$ + supervpExe$    + dq$ + " "
            cmd$ = cmd$ + "--result_wav "  + dq$ + resultWavFile$ + dq$ + " "
            cmd$ = cmd$ + "--mode "                + mode$                        + " "
            cmd$ = cmd$ + "--age_val "             + string$ (age_years)          + " "
            cmd$ = cmd$ + "--gender_dir "          + genderDir$                   + " "
            cmd$ = cmd$ + "--gender_amount "       + string$ (gender_amount)      + " "
            cmd$ = cmd$ + "--target_f0 "           + string$ (target_f0_hz)       + " "
            cmd$ = cmd$ + "--stretch_factor "      + string$ (stretch_factor)     + " "
            cmd$ = cmd$ + "--tremolo_freq "        + string$ (tremolo_freq_hz)    + " "
            cmd$ = cmd$ + "--tremolo_depth "       + string$ (tremolo_depth_cents) + " "
            cmd$ = cmd$ + "--cross_mix "           + string$ (cross_mix)          + " "
            cmd$ = cmd$ + "--vibrato_freq "        + string$ (vibrato_freq_hz)    + " "
            cmd$ = cmd$ + "--vibrato_depth "       + string$ (vibrato_depth_cents) + " "
            cmd$ = cmd$ + "--breathiness_amount "  + string$ (breathiness_amount) + " "
            cmd$ = cmd$ + "--formant_shift_cents " + string$ (formant_shift_cents) + " "
            cmd$ = cmd$ + "--harmoniser_interval " + string$ (harmoniser_interval_cents) + " "
            cmd$ = cmd$ + "--harmoniser_mix "      + string$ (harmoniser_mix)     + " "
            cmd$ = cmd$ + "--denoise_threshold_db " + string$ (denoise_threshold_db)

            if mode$ = "cross" and nSounds >= 2
                cmd$ = cmd$ + " --input_wav2 " + dq$ + inputWav2$ + dq$
            endif

            appendInfoLine: ""
            appendInfoLine: "DEBUG - Python command being sent:"
            appendInfoLine: cmd$
            appendInfoLine: ""
            appendInfoLine: "Running SuperVP..."

            # ---- STEP 6: RUN PYTHON ----
            # Note: runSystem is synchronous; Praat waits here until Python / SuperVP return.
            runSystem: cmd$

            # ---- STEP 7: LOAD RESULT ----
            if fileReadable(resultWavFile$)
                resultName$ = soundName1$ + "_svp_" + mode$
                Read from file: resultWavFile$
                resultObj = selected("Sound")
                Rename: resultName$

                appendInfoLine: "Done! Result loaded: ", resultName$

                # ---- VISUALIZATION ----
                if draw_visualization
                    appendInfoLine: "Drawing visualization..."

                    selectObject: sound1
                    dur1 = Get total duration

                    selectObject: resultObj
                    resultDur = Get total duration
                    resultSr = Get sampling frequency
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

                    # F0 contour when this mode uses F0 analysis
                    if needF0
                        selectObject: sound1
                        To Pitch: 0, 75, 600
                        pitchViz = selected("Pitch")

                        Select outer viewport: 0, 8, 3.5, 4.8
                        Select inner viewport: 0.7, 7.7, 3.55, 4.75
                        Axes: 0, dur1, 50, 600
                        Colour: "{0.85, 0.85, 0.88}"
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

                    # Stats
                    Select outer viewport: 0, 8, 6.6, 7.0
                    Axes: 0, 1, 0, 1
                    Font size: 6
                    Colour: "Black"
                    Text: 0.02, "left", 0.6, "half", "Mode: " + mode$ + "   In: " + fixed$ (dur1, 2) + " s -> Out: " + fixed$ (resultDur, 2) + " s   SR: " + string$ (resultSr) + " Hz"

                    removeObject: resultMono
                endif

                if play_result
                    selectObject: resultObj
                    Play
                endif
            else
                appendInfoLine: "ERROR: Transform failed. Result file not found."
                if fileReadable(logFile$)
                    appendInfoLine: ""
                    appendInfoLine: "=== Python / SuperVP log ==="
                    appendInfoLine: readFile$ (logFile$)
                endif
            endif

            # ---- STEP 8: CLEAN UP ----
            deleteFile: inputWav1$
            deleteFile: inputWav2$
            deleteFile: f0File$
            deleteFile: intensityFile$
            deleteFile: resultWavFile$
            deleteFile: doneFile$

        endif
    endif

until 0
