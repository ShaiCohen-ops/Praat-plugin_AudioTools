# ============================================================
# Praat AudioTools - Spectral_Noise_Shaping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral noise shaping generator. Analyses a folder of
#   audio files, learns their spectral profile and temporal
#   envelope, then generates new audio by shaping white noise
#   to match. No neural networks — finishes in seconds.
#
# Dependencies:
#   Python 3 with numpy, scipy, soundfile
# ============================================================

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
pythonScript$  = pluginDir$ + "py" + sep$ + "praat_spectral_gen.py"
resultWav$     = pluginDir$ + "specgen_output.wav"
statsTxt$      = pluginDir$ + "specgen_stats.txt"

createFolder: pluginDir$
createFolder: pluginDir$ + "py" + sep$

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$
endif

# ---- FORM ----
form Spectral Noise Shaping v1.1
    comment === INPUT ===
    sentence Input_folder D:\sounds\corpus
    comment (folder containing audio files to analyse)

    comment === OUTPUT ===
    positive Duration 3.0
    integer Seed 0
    comment (0 = random seed)

    comment === SPECTRAL SETTINGS ===
    integer N_fft 2048
    integer Hop_length 512
    optionmenu Chunk_preset: 3
        option 1024  —  ~23 ms  (grainy / fluttery)
        option 2048  —  ~46 ms  (default / balanced)
        option 4096  —  ~93 ms  (smooth / sustained)
        option 8192  —  ~186 ms (slow / washy)
        option Same as N_fft
    real Variation 0.5
    comment (0 = pure mean spectrum / 1 = max variation)

    comment === AUDIO ===
    integer Sample_rate 44100

    comment === OUTPUT OPTIONS ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- VALIDATE ----
if not folderExists(input_folder$)
    exitScript: "Input folder not found: " + input_folder$
endif

# ---- RESOLVE CHUNK PRESET ----
if chunk_preset = 1
    effective_chunk = 1024
elsif chunk_preset = 2
    effective_chunk = 2048
elsif chunk_preset = 3
    effective_chunk = 4096
elsif chunk_preset = 4
    effective_chunk = 8192
else
    effective_chunk = n_fft
endif

if effective_chunk < 2 * hop_length
    exitScript: "Chunk size (" + string$(effective_chunk) + ") is smaller " +
        ... "than 2 x Hop length (" + string$(2 * hop_length) + "). " +
        ... "Please increase Hop length or choose a larger preset."
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Noise Shaping v1.1 ==="
appendInfoLine: "Folder:     ", input_folder$
appendInfoLine: "Duration:   ", fixed$(duration, 2), " s"
appendInfoLine: "Variation:  ", fixed$(variation, 2)
appendInfoLine: "Chunk size: ", string$(effective_chunk), " samples"
appendInfoLine: ""

# ---- CLEANUP ----
deleteFile: resultWav$
deleteFile: statsTxt$

# ---- BUILD COMMAND ----
dq$ = """"
cmd$ = pythonCmd$ + " "
cmd$ = cmd$ + dq$ + pythonScript$ + dq$ + " "
cmd$ = cmd$ + dq$ + input_folder$ + dq$ + " "
cmd$ = cmd$ + dq$ + resultWav$    + dq$ + " "
cmd$ = cmd$ + dq$ + statsTxt$     + dq$ + " "
cmd$ = cmd$ + "--duration "   + string$(duration) + " "
cmd$ = cmd$ + "--sr "         + string$(sample_rate) + " "
cmd$ = cmd$ + "--n_fft "      + string$(n_fft) + " "
cmd$ = cmd$ + "--hop_length " + string$(hop_length) + " "
cmd$ = cmd$ + "--variation "  + string$(variation)

if effective_chunk <> n_fft
    cmd$ = cmd$ + " --chunk_size " + string$(effective_chunk)
endif

if seed > 0
    cmd$ = cmd$ + " --seed " + string$(seed)
endif

appendInfoLine: "Running spectral noise shaping..."

# ---- RUN ----
runSystem: cmd$

# ---- IMPORT RESULT ----
if fileReadable(resultWav$)
    Read from file: resultWav$
    resultObj = selected("Sound")
    Rename: "spectral_noise_shaped"

    appendInfoLine: ""
    appendInfoLine: "Result loaded."

    if fileReadable(statsTxt$)
        appendInfoLine: ""
        appendInfoLine: readFile$(statsTxt$)
    endif

    # ---- VISUALIZATION ----
    if draw_visualization
        selectObject: resultObj
        dur_out = Get total duration
        sr_out  = Get sampling frequency

        Erase all
        Select outer viewport: 0, 8, 0, 8

        # Title
        Select outer viewport: 0, 8, 0, 0.65
        Axes: 0, 1, 0, 1
        Font size: 12
        Colour: "Black"
        Text: 0.5, "centre", 0.65, "half", "##Spectral Noise Shaping##"
        Font size: 7
        Colour: "{0.35, 0.35, 0.52}"
        Text: 0.5, "centre", -0.25, "half",
            ... "variation=" + fixed$(variation, 2)
            ... + "  |  fft=" + string$(n_fft)
            ... + "  |  chunk=" + string$(effective_chunk)
            ... + "  |  dur=" + fixed$(dur_out, 2) + "s"
            ... + "  |  seed=" + string$(seed)

        # Waveform
        Select outer viewport: 0, 8, 0.70, 2.30
        Select inner viewport: 0.55, 7.65, 0.78, 2.22
        selectObject: resultObj
        Colour: "{0.15, 0.50, 0.35}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Amp"
        Text top: "no", "Generated waveform"

        # Spectrogram
        Select outer viewport: 0, 8, 2.40, 4.60
        Select inner viewport: 0.55, 7.65, 2.50, 4.50
        selectObject: resultObj
        To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
        specObj = selected("Spectrogram")
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        removeObject: specObj
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Hz"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Spectrogram"

        # Summary
        Select outer viewport: 0, 8, 4.70, 5.30
        Select inner viewport: 0.55, 7.65, 4.76, 5.24
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.02, "left", 0.72, "half", "##spectral_noise_shaped##"
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.02, "left", 0.28, "half",
            ... "Duration: " + fixed$(dur_out, 2) + "s"
            ... + "  SR: " + string$(sr_out) + " Hz"
            ... + "  FFT: " + string$(n_fft)
            ... + "  Chunk: " + string$(effective_chunk)
            ... + "  Hop: " + string$(hop_length)
            ... + "  Var: " + fixed$(variation, 2)
            ... + "  Seed: " + string$(seed)
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1

        Font size: 10
        Colour: "Black"
        Line width: 1
    endif

    if play_result
        selectObject: resultObj
        Play
    endif

else
    appendInfoLine: "ERROR: Generation failed."
    if fileReadable(statsTxt$)
        appendInfoLine: ""
        appendInfoLine: readFile$(statsTxt$)
    endif
endif

# ---- CLEANUP ----
deleteFile: resultWav$
deleteFile: statsTxt$

appendInfoLine: ""
appendInfoLine: "=== Done ==="
