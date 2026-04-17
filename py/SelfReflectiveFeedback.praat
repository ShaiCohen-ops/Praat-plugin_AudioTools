# ============================================================
# Praat AudioTools - SelfReflectiveFeedback.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026) - Unified Cross-Platform Version
#
# Description:
#   Single-stage self-reflective feedback loop.
#   Praat runs a chosen transformation, exports a preview,
#   Python analyzes it and returns updated parameters,
#   and the process repeats until metrics stabilise or
#   max_iter is reached.
#
#   Supported stages:
#     1. MDS Space Navigator
#     2. Spectral Freeze & Glitch
#
#   Python parameters file format (params_out.txt):
#     MDS  (lines 1-6):  stop_flag, silence_threshold,
#                        min_sounding_interval, silence_between_words,
#                        n_dimensions, similarity_threshold
#     Freeze (lines 1-4): stop_flag, freeze_points,
#                         freeze_repeat_divisor, artifact_amplitude
#
# Dependencies:
#   pip install numpy scipy soundfile
# ============================================================

# ---- SELECTION CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputSound = selected("Sound")
inputName$ = selected$("Sound")

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

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/reflect_analyze.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/reflect_analyze.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: reflect_analyze.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

paramsInFile$  = tempDir$ + "temp_refl_params_in.json"
paramsOutJson$ = tempDir$ + "temp_refl_params_out.json"
paramsOutTxt$  = tempDir$ + "temp_refl_params_out.txt"
statusFile$    = tempDir$ + "temp_refl_status.ok"
errorFile$     = tempDir$ + "temp_refl_error.txt"
logFile$       = tempDir$ + "temp_refl_log.txt"
probePy$       = tempDir$ + "temp_refl_probe.py"
probeMarker$   = tempDir$ + "temp_refl_probe.ok"

pythonScriptJ$  = replace_regex$(pythonScript$, "\\", "/", 0)
paramsInFileJ$  = replace_regex$(paramsInFile$, "\\", "/", 0)
paramsOutJsonJ$ = replace_regex$(paramsOutJson$, "\\", "/", 0)
paramsOutTxtJ$  = replace_regex$(paramsOutTxt$, "\\", "/", 0)
statusFileJ$    = replace_regex$(statusFile$, "\\", "/", 0)
errorFileJ$     = replace_regex$(errorFile$, "\\", "/", 0)
logFileJ$       = replace_regex$(logFile$, "\\", "/", 0)
probePyJ$       = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$   = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(paramsInFile$)
        deleteFile: paramsInFile$
    endif
    if fileReadable(paramsOutJson$)
        deleteFile: paramsOutJson$
    endif
    if fileReadable(paramsOutTxt$)
        deleteFile: paramsOutTxt$
    endif
    if fileReadable(statusFile$)
        deleteFile: statusFile$
    endif
    if fileReadable(errorFile$)
        deleteFile: errorFile$
    endif
    if fileReadable(logFile$)
        deleteFile: logFile$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    for .i from 1 to 50
        .w$ = tempDir$ + "temp_refl_preview_" + string$(.i) + ".wav"
        .m$ = tempDir$ + "temp_refl_metrics_" + string$(.i) + ".json"
        if fileReadable(.w$)
            deleteFile: .w$
        endif
        if fileReadable(.m$)
            deleteFile: .m$
        endif
    endfor
endproc

@cleanUpTempFiles

# ---- FORM ----
form Self-Reflective Feedback v1.1
    comment ── Stage ──────────────────────────────────────────────────
    optionmenu Stage: 1
        option MDS Space Navigator
        option Spectral Freeze & Glitch
        option Crystalline Cascade
        option 4-Channel Canon
    comment ── Iteration control ──────────────────────────────────────
    integer Max_iter 3
    integer Default_iter 1
    comment ── Convergence tolerance (relative change, 0.01–0.10) ────
    real Tolerance 0.03
    comment ── Options ────────────────────────────────────────────────
    boolean Play_after_each_iter 0
    boolean Debug 0
endform

# ---- STAGE SETUP ----
if stage = 1
    stageScript$ = pluginDir$ + "Time & Granular/MDS_Space_Navigator.praat"
    stageName$   = "mds"
    stageLabel$  = "MDS Space Navigator"
elsif stage = 2
    stageScript$ = pluginDir$ + "Time & Granular/Spectral_Freeze_&_Glitch.praat"
    stageName$   = "freeze"
    stageLabel$  = "Spectral Freeze & Glitch"
elsif stage = 3
    stageScript$ = pluginDir$ + "Reverb/Crystalline_Cascade.praat"
    stageName$   = "cascade"
    stageLabel$  = "Crystalline Cascade"
elsif stage = 4
    stageScript$ = pluginDir$ + "Spatial & Surround/4-Channel Canon.praat"
    stageName$   = "canon"
    stageLabel$  = "4-Channel Canon"
endif

stageScript$ = replace_regex$(stageScript$, "\\", "/", 0)

if not fileReadable(stageScript$)
    exitScript: "Stage script not found: " + stageScript$
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Self-Reflective Feedback v1.1 ==="
appendInfoLine: "Input:      ", inputName$
appendInfoLine: "Stage:      ", stageLabel$
appendInfoLine: "Max iter:   ", max_iter, "  |  Default iter: ", default_iter
appendInfoLine: "Tolerance:  ", fixed$(tolerance, 3)
appendInfoLine: ""

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================
appendInfoLine: "[0/...] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

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

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1 ; Break early
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install numpy scipy soundfile"
endif

appendInfoLine: "  Python found: ", pythonCmd$
appendInfoLine: ""

# ---- INITIAL PARAMETERS (stage defaults) ----
if stage = 1
    p_silence_threshold = 25.0
    p_min_sounding      = 0.10
    p_silence_between   = 0.10
    p_min_silent        = 0.10
    p_similarity_metric$ = "Formants (Vowel Quality)"
    p_max_formant       = 5500
    p_n_formants        = 5
    p_n_mfcc            = 12
    p_ordering$          = "Nearest neighbor chain (most similar next)"
    p_play_result       = 0
elsif stage = 2
    p_freeze_points   = 12
    p_freeze_rep_div  = 3.0
    p_artifact_amp    = 0.10
    p_preset$              = "Custom"
    p_freeze_dur_div       = 25.0
    p_freeze_len_min       = 0.5
    p_freeze_len_max       = 1.5
    p_scale_peak           = 0.91
    p_draw_visualization   = 0
    p_play_result_freeze   = 0
elsif stage = 3
    p_mod_depth        = 0.6
    p_conv_mix         = 0.35
    p_wet_dry          = 50.0
    p_cascade_preset$  = "Custom (use settings below)"
    p_tail_dur         = 2.0
    p_poisson          = 800
    p_pulse_width      = 0.08
    p_pulse_period     = 1200
    p_exp_base         = 120
    p_mod_freq         = 60
    p_layer2_amp       = 0.7
    p_cascade_peak     = 0.88
    p_cascade_viz      = 0
    p_cascade_play     = 0
elsif stage = 4
    p_shift1    = 0.0
    p_shift2    = 6.0
    p_shift3    = 12.0
    p_shift4    = -5.5
    p_delay1    = 0.0
    p_delay2    = 0.3
    p_delay3    = 0.6
    p_delay4    = 0.9
    p_canon_preset$    = "Custom (use values below)"
    p_resample         = 44100
    p_fade_time        = 0.01
    p_output_format$   = "4 channels (quadraphonic)"
    p_canon_viz        = 0
    p_canon_play       = 0
endif

# ---- MAIN REFLECTIVE LOOP ----
stopFlag       = 0
iter           = 0
hasPrevSound   = 0
prevIterSound  = 0

while iter < max_iter and stopFlag = 0
    iter = iter + 1
    appendInfoLine: "─── Iteration ", iter, "/", max_iter, " ───────────────────────────────"

    # ── Run transformation on original input ──────────────────────────
    appendInfoLine: "  [1] Running: ", stageLabel$
    selectObject: inputSound

    if stage = 1
        runScript: stageScript$,
            ... p_silence_threshold,
            ... p_min_silent,
            ... p_min_sounding,
            ... p_similarity_metric$,
            ... p_max_formant,
            ... p_n_formants,
            ... p_n_mfcc,
            ... p_ordering$,
            ... p_silence_between,
            ... p_play_result
    elsif stage = 2
        runScript: stageScript$,
            ... p_preset$,
            ... p_freeze_points,
            ... p_freeze_dur_div,
            ... p_freeze_len_min,
            ... p_freeze_len_max,
            ... p_freeze_rep_div,
            ... p_artifact_amp,
            ... p_scale_peak,
            ... p_draw_visualization,
            ... p_play_result_freeze
    elsif stage = 3
        runScript: stageScript$,
            ... p_cascade_preset$,
            ... p_tail_dur,
            ... p_poisson,
            ... p_pulse_width,
            ... p_pulse_period,
            ... p_exp_base,
            ... p_mod_depth,
            ... p_mod_freq,
            ... p_conv_mix,
            ... p_layer2_amp,
            ... p_wet_dry,
            ... p_cascade_peak,
            ... p_cascade_viz,
            ... p_cascade_play
    elsif stage = 4
        runScript: stageScript$,
            ... p_canon_preset$,
            ... p_shift1,
            ... p_shift2,
            ... p_shift3,
            ... p_shift4,
            ... p_delay1,
            ... p_delay2,
            ... p_delay3,
            ... p_delay4,
            ... p_resample,
            ... p_fade_time,
            ... p_output_format$,
            ... p_canon_viz,
            ... p_canon_play
    endif

    if stage = 1
        expectedName$ = inputName$ + "_reordered"
    elsif stage = 2
        expectedName$ = inputName$ + "_glitch"
    elsif stage = 3
        expectedName$ = inputName$ + "_cascade_Custom"
    elsif stage = 4
        expectedName$ = inputName$ + "_canon4ch_Custom"
    endif
    selectObject: "Sound " + expectedName$
    newSound = selected("Sound")
    appendInfoLine: "      Output: ", selected$("Sound")

    # ── Export preview WAV ─────────────────────────────────────────────
    previewWav$  = tempDir$ + "temp_refl_preview_" + string$(iter) + ".wav"
    metricsFile$ = tempDir$ + "temp_refl_metrics_" + string$(iter) + ".json"
    prevMetricsFile$ = ""
    if iter > 1
        prevMetricsFile$ = tempDir$ + "temp_refl_metrics_" + string$(iter - 1) + ".json"
    endif

    previewWavJ$  = replace_regex$(previewWav$, "\\", "/", 0)
    metricsFileJ$ = replace_regex$(metricsFile$, "\\", "/", 0)
    prevMetricsFileJ$ = replace_regex$(prevMetricsFile$, "\\", "/", 0)

    selectObject: newSound
    Save as WAV file: previewWav$
    appendInfoLine: "      Preview: ", previewWav$

    # ── Write params_in.json ───────────────────────────────────────────
    tolStr$ = fixed$(tolerance, 6)
    if stage = 1
        json$ = "{"
        json$ = json$ + """stage"": ""mds"","
        json$ = json$ + """iteration"": " + string$(iter) + ","
        json$ = json$ + """tolerance"": {"
        json$ = json$ + """centroid_mean"": " + tolStr$ + ","
        json$ = json$ + """centroid_var"": " + tolStr$ + ","
        json$ = json$ + """spectral_flatness"": " + tolStr$ + ","
        json$ = json$ + """rms_energy_var"": " + tolStr$ + ","
        json$ = json$ + """spectral_flux"": " + tolStr$
        json$ = json$ + "},"
        json$ = json$ + """params"": {"
        json$ = json$ + """silence_threshold_db"": "      + fixed$(p_silence_threshold, 6) + ","
        json$ = json$ + """min_sounding_interval_s"": "   + fixed$(p_min_sounding, 6) + ","
        json$ = json$ + """silence_between_words_s"": "   + fixed$(p_silence_between, 6)
        json$ = json$ + "}}"
    elsif stage = 2
        json$ = "{"
        json$ = json$ + """stage"": ""freeze"","
        json$ = json$ + """iteration"": " + string$(iter) + ","
        json$ = json$ + """tolerance"": {"
        json$ = json$ + """centroid_mean"": " + tolStr$ + ","
        json$ = json$ + """centroid_var"": " + tolStr$ + ","
        json$ = json$ + """spectral_flatness"": " + tolStr$ + ","
        json$ = json$ + """rms_energy_var"": " + tolStr$ + ","
        json$ = json$ + """spectral_flux"": " + tolStr$
        json$ = json$ + "},"
        json$ = json$ + """params"": {"
        json$ = json$ + """freeze_points"": "          + string$(p_freeze_points) + ","
        json$ = json$ + """freeze_repeat_divisor"": "  + fixed$(p_freeze_rep_div, 6) + ","
        json$ = json$ + """artifact_amplitude"": "     + fixed$(p_artifact_amp, 6)
        json$ = json$ + "}}"
    elsif stage = 3
        json$ = "{"
        json$ = json$ + """stage"": ""cascade"","
        json$ = json$ + """iteration"": " + string$(iter) + ","
        json$ = json$ + """tolerance"": {"
        json$ = json$ + """centroid_mean"": " + tolStr$ + ","
        json$ = json$ + """centroid_var"": " + tolStr$ + ","
        json$ = json$ + """spectral_flatness"": " + tolStr$ + ","
        json$ = json$ + """rms_energy_var"": " + tolStr$ + ","
        json$ = json$ + """spectral_flux"": " + tolStr$
        json$ = json$ + "},"
        json$ = json$ + """params"": {"
        json$ = json$ + """modulation_depth"": "  + fixed$(p_mod_depth, 6) + ","
        json$ = json$ + """convolution_mix"": "   + fixed$(p_conv_mix, 6) + ","
        json$ = json$ + """wet_dry_percent"": "   + fixed$(p_wet_dry, 6)
        json$ = json$ + "}}"
    elsif stage = 4
        json$ = "{"
        json$ = json$ + """stage"": ""canon"","
        json$ = json$ + """iteration"": " + string$(iter) + ","
        json$ = json$ + """tolerance"": {"
        json$ = json$ + """centroid_mean"": " + tolStr$ + ","
        json$ = json$ + """centroid_var"": " + tolStr$ + ","
        json$ = json$ + """spectral_flatness"": " + tolStr$ + ","
        json$ = json$ + """rms_energy_var"": " + tolStr$ + ","
        json$ = json$ + """spectral_flux"": " + tolStr$
        json$ = json$ + "},"
        json$ = json$ + """params"": {"
        json$ = json$ + """shift_percent_1"": " + fixed$(p_shift1, 6) + ","
        json$ = json$ + """shift_percent_2"": " + fixed$(p_shift2, 6) + ","
        json$ = json$ + """shift_percent_3"": " + fixed$(p_shift3, 6) + ","
        json$ = json$ + """shift_percent_4"": " + fixed$(p_shift4, 6) + ","
        json$ = json$ + """delay_2"": "         + fixed$(p_delay2, 6) + ","
        json$ = json$ + """delay_3"": "         + fixed$(p_delay3, 6) + ","
        json$ = json$ + """delay_4"": "         + fixed$(p_delay4, 6)
        json$ = json$ + "}}"
    endif
    writeFile: paramsInFile$, json$

    # ── Call Python analysis ───────────────────────────────────────────
    appendInfoLine: "  [2] Analyzing..."
    if fileReadable(statusFile$)
        deleteFile: statusFile$
    endif
    if fileReadable(errorFile$)
        deleteFile: errorFile$
    endif

    pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
        ... + " """ + previewWavJ$     + """"
        ... + " "   + stageName$
        ... + " """ + paramsInFileJ$   + """"
        ... + " """ + paramsOutJsonJ$  + """"
        ... + " """ + paramsOutTxtJ$   + """"
        ... + " --metrics-out """ + metricsFileJ$ + """"
        ... + " --status-file """ + statusFileJ$  + """"

    if prevMetricsFileJ$ <> ""
        if fileReadable(prevMetricsFile$)
            pythonCall$ = pythonCall$ + " --prev-metrics """ + prevMetricsFileJ$ + """"
        endif
    endif

    if debug
        pythonCall$ = pythonCall$ + " --debug"
        appendInfoLine: "      Cmd: ", pythonCall$
    endif

    pythonCall$ = pythonCall$ + " > """ + logFileJ$ + """ 2> """ + errorFileJ$ + """"

    runSystem_nocheck: pythonCall$

    if fileReadable(logFile$)
        logText$ = readFile$(logFile$)
        if logText$ <> ""
            appendInfoLine: "      ", logText$
        endif
        deleteFile: logFile$
    endif

    if not fileReadable(statusFile$)
        errMsg$ = "(no error captured)"
        if fileReadable(errorFile$)
            errMsg$ = readFile$(errorFile$)
            deleteFile: errorFile$
        endif
        appendInfoLine: "  WARNING: Python analysis failed: ", errMsg$
        appendInfoLine: "  Continuing with unchanged parameters."
    else
        deleteFile: statusFile$

        # ── Read params_out.txt ────────────────────────────────────────
        if fileReadable(paramsOutTxt$)
            paramsText$ = readFile$(paramsOutTxt$)

            @getLine: paramsText$, 1
            stopFlag = number(getLine.result$)

            if stage = 1
                @getLine: paramsText$, 2
                p_silence_threshold = number(getLine.result$)
                @getLine: paramsText$, 3
                p_min_sounding = number(getLine.result$)
                @getLine: paramsText$, 4
                p_silence_between = number(getLine.result$)
                appendInfoLine: "      thresh_dB=", fixed$(p_silence_threshold, 2),
                    ... "  minSnd=", fixed$(p_min_sounding, 3),
                    ... "  silBtw=", fixed$(p_silence_between, 3)
            elsif stage = 2
                @getLine: paramsText$, 2
                p_freeze_points = number(getLine.result$)
                @getLine: paramsText$, 3
                p_freeze_rep_div = number(getLine.result$)
                @getLine: paramsText$, 4
                p_artifact_amp = number(getLine.result$)
                appendInfoLine: "      freeze_pts=", p_freeze_points,
                    ... "  rep_div=", fixed$(p_freeze_rep_div, 2),
                    ... "  art_amp=", fixed$(p_artifact_amp, 3)
            elsif stage = 3
                @getLine: paramsText$, 2
                p_mod_depth = number(getLine.result$)
                @getLine: paramsText$, 3
                p_conv_mix = number(getLine.result$)
                @getLine: paramsText$, 4
                p_wet_dry = number(getLine.result$)
                appendInfoLine: "      mod_depth=", fixed$(p_mod_depth, 3),
                    ... "  conv_mix=", fixed$(p_conv_mix, 3),
                    ... "  wet_dry=",  fixed$(p_wet_dry, 1)
            elsif stage = 4
                @getLine: paramsText$, 2
                p_shift1 = number(getLine.result$)
                @getLine: paramsText$, 3
                p_shift2 = number(getLine.result$)
                @getLine: paramsText$, 4
                p_shift3 = number(getLine.result$)
                @getLine: paramsText$, 5
                p_shift4 = number(getLine.result$)
                @getLine: paramsText$, 6
                p_delay2 = number(getLine.result$)
                @getLine: paramsText$, 7
                p_delay3 = number(getLine.result$)
                @getLine: paramsText$, 8
                p_delay4 = number(getLine.result$)
                appendInfoLine: "      shifts=", fixed$(p_shift1,1), "/",
                    ... fixed$(p_shift2,1), "/", fixed$(p_shift3,1), "/", fixed$(p_shift4,1),
                    ... "  delays=0/", fixed$(p_delay2,2), "/",
                    ... fixed$(p_delay3,2), "/", fixed$(p_delay4,2)
            endif
            appendInfoLine: "      stop_flag=", stopFlag
        endif
    endif

    if play_after_each_iter
        selectObject: newSound
        Play
    endif

    if hasPrevSound = 1
        removeObject: prevIterSound
    endif
    prevIterSound = newSound
    hasPrevSound  = 1

    if iter >= default_iter and stopFlag = 0 and iter < max_iter
        beginPause: "Iteration " + string$(iter) + "/" + string$(max_iter) + " complete"
            comment: "Parameters updated. Choose next action:"
            comment: "(press Enter / OK to continue automatically)"
            choice: "Next_action", 1
                option: "Continue automatically"
                option: "Iterate once more"
                option: "Stop — keep current result"
        endPause: "OK", 1

        if next_action = 3
            stopFlag = 1
            appendInfoLine: "  User stopped at iteration ", iter, "."
        endif
    endif

endwhile

# ---- FINAL OUTPUT ----
selectObject: newSound
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:     ", selected$("Sound")
appendInfoLine: "Iterations: ", iter

if stopFlag = 1 and iter < max_iter
    stopReason$ = "metrics_stabilised (auto)"
elsif stopFlag = 1 and iter >= max_iter
    stopReason$ = "user_stop"
else
    stopReason$ = "max_iter_reached"
endif
appendInfoLine: "Stop reason: ", stopReason$

# ---- CLEANUP TEMP DIRECTORY ----
@cleanUpTempFiles

# ============================================================
# Procedure: extract line N (1-indexed) from a newline-delimited string
# Call:  @getLine: text$, N
# Read:  getLine.result$
# ============================================================
procedure getLine: .text$, .n
    .result$ = ""
    .current$ = .text$
    for .i to .n
        .nl = index(.current$, newline$)
        if .nl > 0
            if .i = .n
                .result$ = left$(.current$, .nl - 1)
            else
                .current$ = mid$(.current$, .nl + 1, length(.current$))
            endif
        else
            if .i = .n
                .result$ = .current$
            endif
        endif
    endfor
endproc