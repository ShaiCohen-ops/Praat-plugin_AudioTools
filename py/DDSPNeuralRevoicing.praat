# ============================================================
# Praat AudioTools - DDSPNeuralRevoicing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   DDSP Neural Revoicing - renders the selected Sound through a pretrained
#   Magenta DDSP timbre-transfer model (Violin, Flute, Flute2, Trumpet,
#   Tenor_Saxophone). It preserves the input's pitch contour and loudness
#   gesture and re-renders them with the chosen instrument model.
#
#   Praat is the front-end; the heavy DSP is offloaded to
#   ddsp_neural_revoicing_engine.py (hidden Python engine). The engine
#   downloads a model once, then caches it for offline use.
#
# Setup note:
#   `python_exe$` below is set to the venv that has TensorFlow + ddsp installed
#   (C:/Users/User/praat_ddsp_env). If your venv path differs, change that one
#   line. The model cache resolves to preferencesDirectory$\ddsp_cache.
#
# Honest limitations:
#   - This is NEURAL REVOICING / DDSP timbre transfer, NOT literal instrument
#     conversion and NOT guaranteed-natural timbre. Output is stylized.
#   - Works best on clean MONOPHONIC input. Polyphonic / noisy material is
#     unstable.
#   - The model synthesizes at 16 kHz; Match_input_sample_rate wraps the output
#     at the input rate for convenience but adds no content above ~8 kHz.
#   - Requires Python with TensorFlow + ddsp + crepe installed. If anything is
#     missing, a clear message is shown and written to the stats file.
#
# Changelog v0.4:
#   - New Note_gap_depth_dB control (default 0/off): deepens inter-note
#     loudness gaps so sustained models (Trumpet, Tenor_Saxophone) stop
#     slurring across short staccato gaps. Try 15-25 for staccato.
#
# Changelog v0.3:
#   - New Output_level control (default Match input loudness): DDSP renders
#     quiet, so output is scaled to the source RMS (peak-guarded). Options:
#     Match input / Peak (~0.95) / Raw.
#
# Changelog v0.2:
#   - Wired to the working venv (python_exe$) and existing model cache.
#   - New form controls: Confidence_gate_0to1 (silences low-confidence /
#     decaying-tail frames so pitch stops wandering), Match_input_sample_rate
#     (output at the input rate, honestly upsampled from 16 kHz), Play_result.
#
# Changelog v0.1:
#   - Initial release.
# ============================================================

form DDSP Neural Revoicing
    comment Select ONE Sound object first (monophonic works best).
    comment --- Target ---
    optionmenu Target_model: 1
        option Violin
        option Flute
        option Flute2
        option Trumpet
        option Tenor_Saxophone
    comment --- Conditioning (honest controls) ---
    real Note_detection_threshold_dB 30.0
    real Pitch_shift_octaves 0.0
    real Loudness_shift_dB 0.0
    real Autotune_amount_0to1 0.0
    real Quiet_attenuation_dB 0.0
    real Confidence_gate_0to1 0.15
    real Note_gap_depth_dB 0.0
    comment --- Output ---
    word Output_name DDSP_Revoiced
    boolean Match_input_sample_rate 1
    optionmenu Output_level: 1
        option Match input loudness
        option Peak normalize (~0.95)
        option Raw (model level)
    boolean Play_result 1
    boolean Keep_temp_files 0
    boolean Show_diagnostics 1
endform

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object first."
endif
sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- PYTHON INTERPRETER ----
# Point this at the venv that has TensorFlow + ddsp installed. Set from the
# working setup on this machine; if the venv ever moves, change THIS ONE LINE.
# (Forward slashes are safe in Praat paths on Windows.)
python_exe$ = "C:/Users/User/praat_ddsp_env/Scripts/python.exe"
if not fileReadable(python_exe$)
    # Fallbacks if the venv path above is not present.
    if macintosh
        python_exe$ = "/opt/homebrew/bin/python3"
    elsif windows
        python_exe$ = "python"
    else
        python_exe$ = "python3"
    endif
endif

# ---- PATHS (relative to plugin / script; never hard-coded) ----
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
backend_script$ = pluginDir$ + "py/ddsp_neural_revoicing_engine.py"
if not fileReadable(backend_script$)
    backend_script$ = defaultDirectory$ + "/ddsp_neural_revoicing_engine.py"
endif
if not fileReadable(backend_script$)
    exitScript: "Cannot find ddsp_neural_revoicing_engine.py." + newline$
        ... + "Expected at: " + pluginDir$ + "py/  or next to this script."
endif

# Stable model cache. preferencesDirectory$ is C:\Users\<you>\Praat on Windows,
# so this resolves to the same ...\Praat\ddsp_cache used already — the Violin /
# Trumpet models you downloaded stay cached and are not re-fetched.
cacheDir$ = preferencesDirectory$ + "/ddsp_cache/"
createDirectory: cacheDir$

# ---- TEMP PATHS (explicit prefix; only these are ever deleted) ----
tempDir$ = temporaryDirectory$ + "/"
createDirectory: tempDir$
tempPrefix$   = "temp_ddsp_revoice_"
tempInput$    = tempDir$ + tempPrefix$ + "input.wav"
tempOutput$   = tempDir$ + tempPrefix$ + "output.wav"
tempStats$    = tempDir$ + tempPrefix$ + "stats.txt"
tempLog$      = tempDir$ + tempPrefix$ + "pylog.txt"
tempAnalysis$ = tempDir$ + tempPrefix$ + "analysis.csv"

# Delete stale temps UP FRONT so a crashed run can't import old output.
@cleanUpTempFiles

procedure cleanUpTempFiles
    # Only ever touches files with this module's known temp prefix - never
    # user-owned files.
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(tempAnalysis$)
        deleteFile: tempAnalysis$
    endif
endproc

# Show the Python diagnostics (teed to --log) in the Info window on failure.
procedure showPyLog
    if fileReadable(tempLog$)
        Read Strings from raw text file: tempLog$
        .logId = selected("Strings")
        .n = Get number of strings
        if .n > 0
            appendInfoLine: ""
            appendInfoLine: "----- Python log -----"
            for .i to .n
                selectObject: .logId
                .line$ = Get string: .i
                appendInfoLine: "  ", .line$
            endfor
            appendInfoLine: "----------------------"
        endif
        removeObject: .logId
    endif
endproc

# ---- EXPORT SELECTED SOUND ----
selectObject: sound
inputDur = Get total duration
inputSr = Get sampling frequency
Save as WAV file: tempInput$
if not fileReadable(tempInput$)
    exitScript: "Could not export the selected Sound to a temp WAV."
endif

writeInfoLine: "=== DDSP Neural Revoicing v0.1 ==="
appendInfoLine: "Source:  ", soundName$
appendInfoLine: "Model:   ", target_model$
appendInfoLine: "Input:   ", fixed$(inputDur, 3), " s  @ ", fixed$(inputSr, 0), " Hz"
appendInfoLine: "Pitch shift: ", fixed$(pitch_shift_octaves, 3), " oct   Loudness: ",
    ... fixed$(loudness_shift_dB, 1), " dB   Autotune: ", fixed$(autotune_amount_0to1, 2),
    ... "   Quiet: ", fixed$(quiet_attenuation_dB, 1), " dB"

# ---- DIAGNOSTIC ANALYSIS (pitch + intensity -> CSV; NOT sent to Python) ----
# The engine does its own DDSP-style f0/loudness extraction; this CSV is only a
# diagnostic record of what Praat sees in the input.
selectObject: sound
Copy: "ddsp_ana_tmp"
anaId = selected("Sound")
anaCh = Get number of channels
if anaCh > 1
    Convert to mono
    .monoAna = selected("Sound")
    removeObject: anaId
    anaId = .monoAna
endif

selectObject: anaId
pitchId = To Pitch: 0, 75, 600
selectObject: anaId
intId = To Intensity: 75, 0, "yes"

writeFileLine: tempAnalysis$, "time,f0_hz,intensity_db"
anaStep = 0.01
anaN = floor(inputDur / anaStep)
if anaN > 6000
    anaStep = inputDur / 6000
    anaN = 6000
endif
meanF0sum = 0
voicedN = 0
for k from 0 to anaN
    t = k * anaStep
    selectObject: pitchId
    f0 = Get value at time: t, "Hertz", "linear"
    if f0 = undefined
        f0 = 0
    else
        meanF0sum = meanF0sum + f0
        voicedN = voicedN + 1
    endif
    selectObject: intId
    inten = Get value at time: t, "cubic"
    if inten = undefined
        inten = 0
    endif
    appendFileLine: tempAnalysis$, fixed$(t, 4), ",", fixed$(f0, 2), ",", fixed$(inten, 2)
endfor
removeObject: pitchId, intId, anaId

if voicedN > 0
    meanF0 = meanF0sum / voicedN
else
    meanF0 = 0
endif

# ---- CALL PYTHON ENGINE (runSubprocess: no shell, spaces in paths are safe) ----
# Map the Output_level menu (1/2/3) to the engine's mode string.
outputLevel$ = "match_input"
if output_level = 2
    outputLevel$ = "peak"
elsif output_level = 3
    outputLevel$ = "raw"
endif

appendInfoLine: ""
appendInfoLine: "Running DDSP engine (first run downloads the model, then caches it)..."

nocheck runSubprocess: python_exe$, backend_script$,
    ... "--input", tempInput$,
    ... "--output", tempOutput$,
    ... "--stats", tempStats$,
    ... "--model", target_model$,
    ... "--threshold", string$(note_detection_threshold_dB),
    ... "--pitch_shift", string$(pitch_shift_octaves),
    ... "--loudness_shift", string$(loudness_shift_dB),
    ... "--autotune", string$(autotune_amount_0to1),
    ... "--quiet", string$(quiet_attenuation_dB),
    ... "--confidence_gate", string$(confidence_gate_0to1),
    ... "--gap_depth", string$(note_gap_depth_dB),
    ... "--match_input_rate", string$(match_input_sample_rate),
    ... "--output_level", outputLevel$,
    ... "--cache_dir", cacheDir$,
    ... "--keep_temp", string$(keep_temp_files),
    ... "--log", tempLog$

# ---- HANDLE RESULT ----
if not fileReadable(tempOutput$)
    @showPyLog
    @reportStatsWarnings
    @cleanUpUnlessKept
    exitScript: "DDSP revoicing failed - no output produced." + newline$
        ... + "The Python log above shows why (commonly: TensorFlow/ddsp not" + newline$
        ... + "installed, or the pretrained model could not be downloaded)."
endif

Read from file: tempOutput$
result = selected("Sound")
resultName$ = output_name$ + "_" + target_model$
Rename: resultName$
appendInfoLine: ""
appendInfoLine: "Imported: ", resultName$

# ---- STATS SUMMARY ----
@showStatsSummary

# ---- CLEANUP ----
@cleanUpUnlessKept

if show_diagnostics
    appendInfoLine: ""
    appendInfoLine: "Diagnostics: input mean F0 = ", fixed$(meanF0, 1), " Hz over ",
        ... fixed$(inputDur, 2), " s"
    if keep_temp_files
        appendInfoLine: "Analysis CSV kept at: ", tempAnalysis$
    endif
endif

selectObject: result
if play_result
    Play
endif
goto END

# ============================================================
# Helper procedures
# ============================================================
procedure cleanUpUnlessKept
    if not keep_temp_files
        @cleanUpTempFiles
    endif
endproc

procedure reportStatsWarnings
    if fileReadable(tempStats$)
        Read Strings from raw text file: tempStats$
        .sId = selected("Strings")
        .n = Get number of strings
        for .i to .n
            selectObject: .sId
            .line$ = Get string: .i
            if startsWith(.line$, "warnings=") and length(.line$) > 9
                appendInfoLine: "Reason: ", replace$(.line$, "warnings=", "", 1)
            endif
        endfor
        removeObject: .sId
    endif
endproc

procedure showStatsSummary
    if not fileReadable(tempStats$)
        appendInfoLine: "(No stats file was written.)"
    else
        Read Strings from raw text file: tempStats$
        .sId = selected("Strings")
        .n = Get number of strings
        appendInfoLine: ""
        appendInfoLine: "----- Revoicing report -----"
        for .i to .n
            selectObject: .sId
            .line$ = Get string: .i
            .isKey = startsWith(.line$, "status=") or startsWith(.line$, "model=")
                ... or startsWith(.line$, "input_duration_s=")
                ... or startsWith(.line$, "output_duration_s=")
                ... or startsWith(.line$, "input_sample_rate=")
                ... or startsWith(.line$, "output_sample_rate=")
                ... or startsWith(.line$, "model_source=")
                ... or startsWith(.line$, "model_cache_path=")
                ... or startsWith(.line$, "warnings=")
            if .isKey
                appendInfoLine: "  ", .line$
            endif
        endfor
        appendInfoLine: "----------------------------"
        removeObject: .sId
    endif
endproc

label END
