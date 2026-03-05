# ============================================================
# Praat AudioTools - SelfReflectiveFeedback.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2025)
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

# ---- PATHS ----
# pythonScript$, stageScript$, reflectDir$: all via preferencesDirectory$ —
# absolute, works on all platforms regardless of where this file is placed.
pythonScript$ = preferencesDirectory$ + "/plugin_AudioTools/py/reflect_analyze.py"
reflectDir$   = preferencesDirectory$ + "/plugin_AudioTools/_reflect_tmp/"
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find: " + pythonScript$
endif

# ---- FORM ----
form Self-Reflective Feedback v1.0
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
    stageScript$ = pluginDir$ + "Time & Granular/MDS Space Navigator.praat"
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

if not fileReadable(stageScript$)
    exitScript: "Stage script not found: " + stageScript$
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Self-Reflective Feedback v1.0 ==="
appendInfoLine: "Input:      ", inputName$
appendInfoLine: "Stage:      ", stageLabel$
appendInfoLine: "Max iter:   ", max_iter, "  |  Default iter: ", default_iter
appendInfoLine: "Tolerance:  ", fixed$(tolerance, 3)
appendInfoLine: ""

# ---- PYTHON AUTO-DETECTION ----
appendInfoLine: "Detecting Python..."
probeMarker$ = reflectDir$ + "reflect_pyprobe.ok"

# Ensure temp dir exists first (needed for probe marker)
if windows
    runSystem_nocheck: "mkdir """ + reflectDir$ + """ 2>NUL"
else
    runSystem_nocheck: "mkdir -p """ + reflectDir$ + """"
endif

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
    probeCode$ = "import numpy,scipy,soundfile; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"
    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
    endif
    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    exitScript: "Cannot find Python with required packages." + newline$
        ... + "  pip install numpy scipy soundfile"
endif
appendInfoLine: "  Python found: ", pythonCmd$
appendInfoLine: ""

# ---- FIXED TEMP FILE PATHS ----
paramsInFile$  = reflectDir$ + "params_in.json"
paramsOutJson$ = reflectDir$ + "params_out.json"
paramsOutTxt$  = reflectDir$ + "params_out.txt"
statusFile$    = reflectDir$ + "reflect_status.ok"
errorFile$     = reflectDir$ + "reflect_error.txt"
logFile$       = reflectDir$ + "reflect_log.txt"

# ---- INITIAL PARAMETERS (stage defaults) ----
if stage = 1
    # MDS Space Navigator — reflective params (adjusted by Python)
    # Silence_threshold_dB, Minimum_sounding_interval_s, Silence_between_words_s
    p_silence_threshold = 25.0
    p_min_sounding      = 0.10
    p_silence_between   = 0.10
    # Fixed constants (not adjusted by reflection)
    # Minimum_silent_interval_s, Similarity_metric, Max_formant_Hz,
    # Number_of_formants, Number_of_MFCC_Coefficients, Ordering, Play_result
    p_min_silent        = 0.10
    p_similarity_metric$ = "Formants (Vowel Quality)"
    p_max_formant       = 5500
    p_n_formants        = 5
    p_n_mfcc            = 12
    p_ordering$          = "Nearest neighbor chain (most similar next)"
    p_play_result       = 0
elsif stage = 2
    # Spectral Freeze & Glitch — reflective params (adjusted by Python)
    # Freeze_points, Freeze_repeat_divisor, Artifact_amplitude
    p_freeze_points   = 12
    p_freeze_rep_div  = 3.0
    p_artifact_amp    = 0.10
    # Fixed constants
    # Preset, Freeze_duration_divisor, Freeze_length_min_factor,
    # Freeze_length_max_factor, Scale_peak, Draw_visualization, Play_result
    p_preset$              = "Custom"
    p_freeze_dur_div       = 25.0
    p_freeze_len_min       = 0.5
    p_freeze_len_max       = 1.5
    p_scale_peak           = 0.91
    p_draw_visualization   = 0
    p_play_result_freeze   = 0
elsif stage = 3
    # Crystalline Cascade — reflective params (adjusted by Python)
    # Modulation_depth, Convolution_mix, Wet_dry_percent
    p_mod_depth        = 0.6
    p_conv_mix         = 0.35
    p_wet_dry          = 50.0
    # Fixed constants
    # Preset, Tail_duration_s, Poisson_density, Pulse_width, Pulse_period,
    # Exponential_base, Modulation_frequency, Layer2_amplitude,
    # Scale_peak, Draw_visualization, Play_result
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
    # 4-Channel Canon — reflective params (adjusted by Python)
    # Shift_percent_1..4, Delay_2..4 (Delay_1 always 0)
    p_shift1    = 0.0
    p_shift2    = 6.0
    p_shift3    = 12.0
    p_shift4    = -5.5
    p_delay1    = 0.0
    p_delay2    = 0.3
    p_delay3    = 0.6
    p_delay4    = 0.9
    # Fixed constants
    # Preset, Resample_frequency, Fade_time, Output_format, Draw_visualization, Play_result
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
        # Args: Silence_threshold_dB, Minimum_silent_interval_s,
        #       Minimum_sounding_interval_s, Similarity_metric,
        #       Max_formant_Hz, Number_of_formants,
        #       Number_of_MFCC_Coefficients, Ordering,
        #       Silence_between_words_s, Play_result
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
        # Args: Preset, Freeze_points, Freeze_duration_divisor,
        #       Freeze_length_min_factor, Freeze_length_max_factor,
        #       Freeze_repeat_divisor, Artifact_amplitude,
        #       Scale_peak, Draw_visualization, Play_result
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
        # Args: Preset, Tail_duration_s, Poisson_density, Pulse_width,
        #       Pulse_period, Exponential_base, Modulation_depth,
        #       Modulation_frequency, Convolution_mix, Layer2_amplitude,
        #       Wet_dry_percent, Scale_peak, Draw_visualization, Play_result
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
        # Args: Preset, Shift_percent_1..4, Delay_1..4,
        #       Resample_frequency, Fade_time,
        #       Output_format, Draw_visualization, Play_result
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

    # MDS appends "_reordered"; Freeze appends "_glitch";
    # Cascade appends "_cascade_Custom"; Canon appends "_canon4ch_Custom".
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
    previewWav$  = reflectDir$ + "preview_" + string$(iter) + ".wav"
    metricsFile$ = reflectDir$ + "metrics_" + string$(iter) + ".json"
    prevMetricsFile$ = ""
    if iter > 1
        prevMetricsFile$ = reflectDir$ + "metrics_" + string$(iter - 1) + ".json"
    endif

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
        json$ = json$ + """delay_2"": "          + fixed$(p_delay2, 6) + ","
        json$ = json$ + """delay_3"": "          + fixed$(p_delay3, 6) + ","
        json$ = json$ + """delay_4"": "          + fixed$(p_delay4, 6)
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

    pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
        ... + " """ + previewWav$    + """"
        ... + " "   + stageName$
        ... + " """ + paramsInFile$  + """"
        ... + " """ + paramsOutJson$ + """"
        ... + " """ + paramsOutTxt$  + """"
        ... + " --metrics-out """ + metricsFile$ + """"
        ... + " --status-file """ + statusFile$  + """"

    if prevMetricsFile$ <> ""
        if fileReadable(prevMetricsFile$)
            pythonCall$ = pythonCall$ + " --prev-metrics """ + prevMetricsFile$ + """"
        endif
    endif

    if debug
        pythonCall$ = pythonCall$ + " --debug"
        appendInfoLine: "      Cmd: ", pythonCall$
    endif

    # Capture both stdout (log) and stderr (errors)
    if windows
        pythonCall$ = pythonCall$ + " > """ + logFile$ + """ 2> """ + errorFile$ + """"
    else
        pythonCall$ = pythonCall$ + " > """ + logFile$ + """ 2> """ + errorFile$ + """"
    endif

    runSystem_nocheck: pythonCall$

    # Show Python log line in info window
    if fileReadable(logFile$)
        logText$ = readFile$(logFile$)
        if logText$ <> ""
            appendInfoLine: "      ", logText$
        endif
        deleteFile: logFile$
    endif

    # Check success
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

    # ── Play preview if requested ──────────────────────────────────────
    if play_after_each_iter
        selectObject: newSound
        Play
    endif

    # ── Remove previous iteration's intermediate Sound (not input) ────
    if hasPrevSound = 1
        removeObject: prevIterSound
    endif
    prevIterSound = newSound
    hasPrevSound  = 1

    # ── Interrupt dialog (after default_iter auto-iterations) ─────────
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
        # Options 1 and 2 both continue the while loop;
        # "Iterate once more" shows the dialog again next iteration too,
        # since iter will still be >= default_iter.
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
            # Last line with no trailing newline
            if .i = .n
                .result$ = .current$
            endif
        endif
    endfor
endproc
