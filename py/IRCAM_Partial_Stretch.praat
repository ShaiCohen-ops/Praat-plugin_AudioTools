# ============================================================
# Praat AudioTools - Partial_Stretch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SPEAR-style partial manipulation for electroacoustic
#   composition. Analyses a selected Sound with PM2, then
#   applies frequency-dependent time operations to individual
#   partial tracks and resynthesizes via additive synthesis.
#
#   Modes:
#     Spectral Stretch — upper partials stretched, lower intact
#     Band Stretch     — 3-band independent time stretch
#     Freeze           — sustain spectral snapshot as a drone
#     Partial Thin     — spectral sieve above a threshold
#     Spectral Blur    — smoothed spectral evolution
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")

# ---- PLATFORM ----
if windows
    sep$       = "\"
    pythonCmd$ = "py"
else
    sep$       = "/"
    pythonCmd$ = "python3"
endif

# ---- PATHS ----
pluginDir$     = preferencesDirectory$ + sep$ + "plugin_AudioTools" + sep$
pythonScript$  = pluginDir$ + "py" + sep$ + "partial_stretch.py"
inputWav$      = pluginDir$ + "ps_input.wav"
resultWav$     = pluginDir$ + "ps_result.wav"
doneFile$      = pluginDir$ + "ps_done.txt"
logFile$       = pluginDir$ + "ps_log.txt"

pm2Dir$ = "C:\Users\User\Pm2\bin"

createFolder: pluginDir$
createFolder: pluginDir$ + "py" + sep$

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$
endif

# ---- FORM ----
form Partial Stretch v1.1
    comment === MODE ===
    optionmenu Mode: 1
        option Spectral Stretch
        option Band Stretch
        option Freeze
        option Partial Thin
        option Spectral Blur

    comment === SPECTRAL STRETCH ===
    positive Split_frequency_Hz 1000
    positive Upper_stretch_factor 3.0

    comment === BAND STRETCH ===
    positive Band_low_Hz 500
    positive Band_mid_Hz 2000
    positive Band_low_stretch 1.0
    positive Band_mid_stretch 2.0
    positive Band_high_stretch 4.0

    comment === FREEZE ===
    real Freeze_time 0.5
    comment (normalised 0..1 — position in the sound)
    positive Freeze_duration 5.0

    comment === PARTIAL THIN ===
    positive Thin_above_Hz 1000
    integer Thin_every_N 2

    comment === SPECTRAL BLUR ===
    positive Blur_window_ms 100

    comment === ANALYSIS ===
    integer Max_partials 200
    real Analysis_window_ms 46.44
    real Hop_ms 5.0

    comment === OUTPUT ===
    real Output_gain 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- MAP MODE ----
if mode = 1
    mode$ = "spectral_stretch"
elsif mode = 2
    mode$ = "band_stretch"
elsif mode = 3
    mode$ = "freeze"
elsif mode = 4
    mode$ = "partial_thin"
elsif mode = 5
    mode$ = "spectral_blur"
endif

resultName$ = soundName$ + "_ps_" + mode$

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Partial Stretch v1.1 ==="
appendInfoLine: "Mode:     ", mode$
appendInfoLine: "Source:   ", soundName$
appendInfoLine: ""

# ---- PREP INPUT ----
deleteFile: inputWav$
deleteFile: resultWav$
deleteFile: doneFile$
deleteFile: logFile$

selectObject: sound
Save as WAV file: inputWav$

# ---- BUILD PYTHON COMMAND ----
dq$ = """"
cmd$ = pythonCmd$ + " "
cmd$ = cmd$ + dq$ + pythonScript$ + dq$ + " "
cmd$ = cmd$ + dq$ + inputWav$     + dq$ + " "
cmd$ = cmd$ + dq$ + doneFile$     + dq$ + " "
cmd$ = cmd$ + "--pm2_dir "               + dq$ + pm2Dir$ + dq$ + " "
cmd$ = cmd$ + "--result_wav "            + dq$ + resultWav$ + dq$ + " "
cmd$ = cmd$ + "--log_path "              + dq$ + logFile$ + dq$ + " "
cmd$ = cmd$ + "--mode "                  + mode$ + " "
cmd$ = cmd$ + "--max_partials "          + string$(max_partials) + " "
cmd$ = cmd$ + "--analysis_window_ms "    + string$(analysis_window_ms) + " "
cmd$ = cmd$ + "--hop_ms "                + string$(hop_ms) + " "
cmd$ = cmd$ + "--output_gain "           + string$(output_gain) + " "
cmd$ = cmd$ + "--split_freq_hz "         + string$(split_frequency_Hz) + " "
cmd$ = cmd$ + "--upper_stretch_factor "  + string$(upper_stretch_factor) + " "
cmd$ = cmd$ + "--band_lo_hz "            + string$(band_low_Hz) + " "
cmd$ = cmd$ + "--band_mid_hz "           + string$(band_mid_Hz) + " "
cmd$ = cmd$ + "--band_lo_stretch "       + string$(band_low_stretch) + " "
cmd$ = cmd$ + "--band_mid_stretch "      + string$(band_mid_stretch) + " "
cmd$ = cmd$ + "--band_hi_stretch "       + string$(band_high_stretch) + " "
cmd$ = cmd$ + "--freeze_time "           + string$(freeze_time) + " "
cmd$ = cmd$ + "--freeze_duration "       + string$(freeze_duration) + " "
cmd$ = cmd$ + "--thin_above_hz "         + string$(thin_above_Hz) + " "
cmd$ = cmd$ + "--thin_every_n "          + string$(thin_every_N) + " "
cmd$ = cmd$ + "--blur_window_ms "        + string$(blur_window_ms)

appendInfoLine: "Running Partial Stretch..."

# ---- RUN PYTHON ----
runSystem: cmd$

# ---- IMPORT RESULT ----
if fileReadable(doneFile$)
    doneStatus$ = readFile$(doneFile$)
    doneStatus$ = replace$(doneStatus$, newline$, "", 0)

    if doneStatus$ = "ok" and fileReadable(resultWav$)
        Read from file: resultWav$
        resultObj = selected("Sound")
        Rename: resultName$

        appendInfoLine: "Result loaded: ", resultName$

        # ---- VISUALIZATION ----
        if draw_visualization
            appendInfoLine: "Drawing visualization..."

            selectObject: sound
            dur_in = Get total duration
            sr_in  = Get sampling frequency
            nCh_in = Get number of channels

            selectObject: resultObj
            dur_out = Get total duration
            sr_out  = Get sampling frequency
            resultMono = Convert to mono

            Erase all
            Select outer viewport: 0, 8, 0, 8

            # Title
            Select outer viewport: 0, 8, 0, 0.65
            Axes: 0, 1, 0, 1
            Font size: 12
            Colour: "Black"
            Text: 0.5, "centre", 0.65, "half", "##Partial Stretch: " + mode$ + "##"
            Font size: 7
            Colour: "{0.35, 0.35, 0.52}"
            if mode$ = "spectral_stretch"
                Text: 0.5, "centre", -0.25, "half",
                    ... soundName$
                    ... + "  |  split=" + fixed$(split_frequency_Hz, 0) + " Hz"
                    ... + "  |  upper " + fixed$(upper_stretch_factor, 1) + "×"
            elsif mode$ = "band_stretch"
                Text: 0.5, "centre", -0.25, "half",
                    ... soundName$
                    ... + "  |  lo=" + fixed$(band_low_stretch, 1) + "×"
                    ... + "  mid=" + fixed$(band_mid_stretch, 1) + "×"
                    ... + "  hi=" + fixed$(band_high_stretch, 1) + "×"
            elsif mode$ = "freeze"
                Text: 0.5, "centre", -0.25, "half",
                    ... soundName$
                    ... + "  |  t=" + fixed$(freeze_time, 2)
                    ... + "  |  dur=" + fixed$(freeze_duration, 1) + "s"
            elsif mode$ = "partial_thin"
                Text: 0.5, "centre", -0.25, "half",
                    ... soundName$
                    ... + "  |  above " + fixed$(thin_above_Hz, 0) + " Hz"
                    ... + "  |  keep 1/" + string$(thin_every_N)
            else
                Text: 0.5, "centre", -0.25, "half",
                    ... soundName$
                    ... + "  |  blur=" + fixed$(blur_window_ms, 0) + " ms"
            endif

            # Input waveform
            Select outer viewport: 0, 8, 0.70, 1.65
            Select inner viewport: 0.55, 7.65, 0.75, 1.60
            selectObject: sound
            if nCh_in > 1
                Extract one channel: 1
                vizIn = selected("Sound")
            else
                Copy: "vizIn"
                vizIn = selected("Sound")
            endif
            Colour: "{0.55, 0.55, 0.55}"
            Draw: 0, 0, 0, 0, "no", "Curve"
            removeObject: vizIn
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text left: "yes", "Input"

            # Output waveform
            Select outer viewport: 0, 8, 1.70, 2.65
            Select inner viewport: 0.55, 7.65, 1.75, 2.60
            selectObject: resultObj
            Colour: "{0.15, 0.50, 0.35}"
            Draw: 0, 0, 0, 0, "no", "Curve"
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text left: "yes", "Output"
            Text bottom: "yes", "Time (s)"

            # Input spectrogram
            Select outer viewport: 0, 4.1, 2.75, 4.45
            Select inner viewport: 0.55, 3.85, 2.85, 4.35
            selectObject: sound
            if nCh_in > 1
                Extract one channel: 1
                vizSpecIn = selected("Sound")
            else
                Copy: "vizSpecIn"
                vizSpecIn = selected("Sound")
            endif
            To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
            specIn = selected("Spectrogram")
            Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
            removeObject: specIn, vizSpecIn
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text left: "yes", "Hz"
            Text bottom: "yes", "Time (s)"
            Text top: "no", "Input spectrogram"

            # Output spectrogram
            Select outer viewport: 4.1, 8, 2.75, 4.45
            Select inner viewport: 4.40, 7.65, 2.85, 4.35
            selectObject: resultMono
            specStep = max(0.002, dur_out / 2000)
            To Spectrogram: 0.02, 5000, specStep, 20, "Gaussian"
            specOut = selected("Spectrogram")
            Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
            removeObject: specOut
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text left: "yes", "Hz"
            Text bottom: "yes", "Time (s)"
            Text top: "no", "Output spectrogram"

            # Summary bar
            Select outer viewport: 0, 8, 4.55, 5.15
            Select inner viewport: 0.55, 7.65, 4.60, 5.08
            Axes: 0, 1, 0, 1
            Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
            Font size: 7
            Colour: "Black"
            Text: 0.02, "left", 0.72, "half", "##" + resultName$ + "##"
            Font size: 6
            Colour: "{0.30, 0.30, 0.30}"
            Text: 0.02, "left", 0.28, "half",
                ... "In: " + fixed$(dur_in, 2) + "s"
                ... + "  Out: " + fixed$(dur_out, 2) + "s"
                ... + "  SR: " + string$(sr_out) + " Hz"
                ... + "  Partials: " + string$(max_partials)
                ... + "  Mode: " + mode$
            Colour: "Black"
            Draw rectangle: 0, 1, 0, 1

            Font size: 10
            Colour: "Black"
            Line width: 1

            removeObject: resultMono
        endif

        if play_result
            selectObject: resultObj
            Play
        endif

    else
        appendInfoLine: "ERROR: result missing or backend failed."
        if fileReadable(logFile$)
            appendInfoLine: ""
            appendInfoLine: "=== Backend log ==="
            appendInfoLine: readFile$(logFile$)
        endif
    endif
else
    appendInfoLine: "ERROR: done_file was not written."
    if fileReadable(logFile$)
        appendInfoLine: readFile$(logFile$)
    endif
endif

# ---- CLEANUP ----
deleteFile: doneFile$
deleteFile: inputWav$
deleteFile: resultWav$

appendInfoLine: ""
appendInfoLine: "=== Partial Stretch complete ==="
