# ============================================================
# Praat AudioTools - Anomaly_Outlier_Extractor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026) - texture / memory modes (output length decoupled)
#
# Changelog v0.3:
#   - New assembly modes "texture" and "memory". The first three modes use
#     each slice EXACTLY ONCE, so output length is a consequence of how
#     much anomalous material was found - and high overlap makes it shorter
#     still (ten 100 ms slices at 0.70 overlap render 0.370 s, because the
#     hop is 30 ms). The new modes treat the slices as a CORPUS and take the
#     canvas length as a parameter, so a 70 ms anomaly can populate 30 s.
#       texture - weighted stochastic cloud, with an anti-repeat cooldown
#       memory  - each slice gets a recurrence budget from its score and its
#                 returns are spread across the whole canvas, so a sharp
#                 anomaly comes back as a motif rather than a cluster
#   - Anomaly_bias turns the anomaly score into a compositional control:
#     0 = every anomaly equally present, higher = the strongest recur most.
#   - Two presets added (Anomaly texture, Anomaly memory) and one form row
#     (Texture length). Detection, conditioning, scoring, thresholding and
#     segmentation are untouched - the extension is confined to assembly.
#
# Changelog v0.2:
#   - Form: reduced from ~32 rows to 10 so it fits on a laptop screen.
#     Six feature checkboxes became one Features text field (keywords, any
#     order, any case, "all" accepted); Window length + Time step became
#     one Window/step field; Pitch floor + ceiling became one Pitch range
#     field. Fade/segment/smoothing/seed/join/granular/peak moved behind a
#     "More options" checkbox that opens a second dialog PRE-FILLED with
#     whatever the chosen preset just set - so a preset stays inspectable
#     instead of becoming a black box.
#   - No change to analysis, detection, assembly or output. Same defaults,
#     same presets, same Python command line.
#
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Anomaly-Driven Outlier Extraction
#
#   Front-end for anomaly_engine.py. Praat measures a frame-level
#   feature table on one common time grid, hands it to the Python
#   backend together with the audio, and receives back a Sound
#   containing ONLY the acoustical outliers - the frames the
#   detector could not explain from the rest of the file.
#
#   Feature extraction (all sampled on the SAME grid, so the CSV is
#   a genuine frame matrix rather than four unrelated time axes):
#     - Pitch              (To Pitch, sampled at frame centres)
#     - Intensity          (To Intensity, sampled at frame centres)
#     - Spectral centroid  (per-frame Spectrum, centre of gravity)
#     - Spectral flux      (per-frame 8-band half-wave rectified
#                           log-energy difference)
#     - Formants F1/F2/F3  (To Formant (burg), sampled at frame centres)
#
#   Detection algorithms (Python side):
#     - IsolationForest  scikit-learn ensemble, path-length score
#     - Mahalanobis      shrinkage covariance, log-compressed distance
#     - Autoencoder      PyTorch if installed, numpy MLP fallback
#
#   Concatenation modes:
#     - chronological  original sequence order
#     - sorted         quietest anomaly to loudest anomaly
#     - granular       overlap-add cloud
#
#   NOTE ON THRESHOLD
#     Outlier_threshold is a FRACTION OF FRAMES, not a score cut.
#     0.05 keeps the top 5% most anomalous frames. Raw anomaly scores
#     are not comparable across algorithms or files, so an absolute
#     cut would behave differently for every input.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-Specific Python Discovery ----
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
pythonScript$ = pluginDir$ + "py/anomaly_engine.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/anomaly_engine.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: anomaly_engine.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_features.csv"
tempOutput$  = temporaryDirectory$ + "/temp_outliers_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_anomaly_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_anomaly_probe.ok"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
# Kept to 10 rows so it fits a laptop screen. Everything that used to be a
# separate row is either folded into a text field (features, grid, pitch
# range) or moved behind "More options", which opens a second dialog
# pre-filled with the values the chosen preset just set.
form Anomaly Outliers v0.3
    optionmenu Preset: 1
        option Custom
        option Transient hunt
        option Pitch instability
        option Broadband oddity
        option Granular cloud
        option Anomaly texture
        option Anomaly memory
    sentence Features pitch intensity centroid deltas
    sentence Window_step_s 0.025 0.010
    sentence Pitch_range_Hz 75 600
    optionmenu Algorithm: 1
        option IsolationForest
        option Mahalanobis
        option Autoencoder
    real Outlier_threshold_(top_fraction) 0.05
    optionmenu Concat_mode: 1
        option chronological
        option sorted
        option granular
        option texture
        option memory
    real Texture_length_s 20.0
    boolean More_options 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PARSE THE COMPACT TEXT FIELDS ----
# Features: any subset of the keywords below, in any order, any case.
# "all" turns everything on. Unknown words are ignored.
@parseTwo: window_step_s$, 0.025, 0.010
window_length = parseTwo.a
time_step     = parseTwo.b

@parseTwo: pitch_range_Hz$, 75, 600
pitch_floor   = parseTwo.a
pitch_ceiling = parseTwo.b

featLower$ = replace_regex$(features$, "([A-Z])", "\L\1", 0)
featAll = 0
if index(featLower$, "all") > 0
    featAll = 1
endif

use_pitch = 0
use_intensity = 0
use_spectral_centroid = 0
use_spectral_flux = 0
use_formants = 0
use_delta_features = 0

if featAll = 1 or index(featLower$, "pitch") > 0
    use_pitch = 1
endif
if featAll = 1 or index(featLower$, "intens") > 0
    use_intensity = 1
endif
if featAll = 1 or index(featLower$, "centroid") > 0 or index(featLower$, "cog") > 0
    use_spectral_centroid = 1
endif
if featAll = 1 or index(featLower$, "flux") > 0
    use_spectral_flux = 1
endif
if featAll = 1 or index(featLower$, "formant") > 0
    use_formants = 1
endif
if featAll = 1 or index(featLower$, "delta") > 0
    use_delta_features = 1
endif

# ---- ADVANCED DEFAULTS ----
# Set here so the presets below can overwrite them and the "More options"
# dialog can show the result. Every one of these was its own form row in
# v0.1.
join = 1
fade_ms = 7.0
min_segment_ms = 40.0
merge_gap_ms = 30.0
max_segment_ms = 2000.0
score_smoothing_frames = 3
seed = 42
granular_overlap = 0.5
granular_jitter = 0.0
anomaly_bias = 1.5
anti_repeat = 0.5
peak_dBFS = -1.0

# ---- PRESET APPLICATION ----
# Each preset configures the WHOLE analysis + detection cluster to match
# its name, not just one field. A preset that sets a single value gives
# two menu entries that behave identically.
if preset = 2
    # Transient hunt - short frames, delta-heavy, tight fast slices
    use_pitch = 0
    use_intensity = 1
    use_spectral_centroid = 1
    use_spectral_flux = 1
    use_formants = 0
    use_delta_features = 1
    window_length = 0.020
    time_step = 0.005
    algorithm = 1
    outlier_threshold = 0.03
    score_smoothing_frames = 3
    fade_ms = 5.0
    min_segment_ms = 30.0
    merge_gap_ms = 20.0
    concat_mode = 1
    presetName$ = "TransientHunt"
elsif preset = 3
    # Pitch instability - long frames, voice-source features, Mahalanobis
    use_pitch = 1
    use_intensity = 1
    use_spectral_centroid = 0
    use_spectral_flux = 0
    use_formants = 1
    use_delta_features = 1
    window_length = 0.040
    time_step = 0.010
    algorithm = 2
    outlier_threshold = 0.08
    score_smoothing_frames = 5
    fade_ms = 8.0
    min_segment_ms = 60.0
    merge_gap_ms = 40.0
    concat_mode = 1
    presetName$ = "PitchInstability"
elsif preset = 4
    # Broadband oddity - full spectral feature set, autoencoder, sorted
    use_pitch = 0
    use_intensity = 1
    use_spectral_centroid = 1
    use_spectral_flux = 1
    use_formants = 1
    use_delta_features = 1
    window_length = 0.030
    time_step = 0.010
    algorithm = 3
    outlier_threshold = 0.05
    score_smoothing_frames = 3
    fade_ms = 7.0
    min_segment_ms = 50.0
    merge_gap_ms = 30.0
    concat_mode = 2
    presetName$ = "BroadbandOddity"
elsif preset = 5
    # Granular cloud - permissive threshold, many short grains, OLA
    use_pitch = 1
    use_intensity = 1
    use_spectral_centroid = 1
    use_spectral_flux = 1
    use_formants = 0
    use_delta_features = 1
    window_length = 0.025
    time_step = 0.010
    algorithm = 1
    outlier_threshold = 0.15
    score_smoothing_frames = 3
    fade_ms = 5.0
    min_segment_ms = 25.0
    merge_gap_ms = 10.0
    max_segment_ms = 400.0
    concat_mode = 3
    granular_overlap = 0.70
    granular_jitter = 0.20
    presetName$ = "GranularCloud"
elsif preset = 6
    # Anomaly texture - stochastic cloud of a requested length
    use_pitch = 1
    use_intensity = 1
    use_spectral_centroid = 1
    use_spectral_flux = 1
    use_formants = 0
    use_delta_features = 1
    window_length = 0.025
    time_step = 0.010
    algorithm = 1
    outlier_threshold = 0.12
    score_smoothing_frames = 3
    fade_ms = 6.0
    min_segment_ms = 30.0
    merge_gap_ms = 15.0
    max_segment_ms = 500.0
    concat_mode = 4
    granular_overlap = 0.60
    granular_jitter = 0.15
    anomaly_bias = 1.5
    anti_repeat = 0.5
    presetName$ = "AnomalyTexture"
elsif preset = 7
    # Anomaly memory - each anomaly returns as a motif across the canvas
    use_pitch = 1
    use_intensity = 1
    use_spectral_centroid = 1
    use_spectral_flux = 1
    use_formants = 0
    use_delta_features = 1
    window_length = 0.025
    time_step = 0.010
    algorithm = 1
    outlier_threshold = 0.08
    score_smoothing_frames = 3
    fade_ms = 6.0
    min_segment_ms = 40.0
    merge_gap_ms = 20.0
    max_segment_ms = 600.0
    concat_mode = 5
    granular_overlap = 0.45
    granular_jitter = 0.20
    anomaly_bias = 2.5
    presetName$ = "AnomalyMemory"
else
    presetName$ = "Custom"
endif

# ---- OPTIONAL SECOND DIALOG ----
# Only opened on request, so the default path is one small form.
if more_options
    beginPause: "Anomaly Outliers - more options"
        comment: "Segmentation (milliseconds)"
        real: "Fade_ms", fade_ms
        real: "Min_segment_ms", min_segment_ms
        real: "Merge_gap_ms", merge_gap_ms
        real: "Max_segment_ms", max_segment_ms
        comment: "Detection"
        integer: "Score_smoothing_frames", score_smoothing_frames
        integer: "Seed", seed
        comment: "Assembly and output"
        optionmenu: "Join", join
            option: "xfade (overlap the tapers)"
            option: "butt (no overlap)"
        real: "Granular_overlap", granular_overlap
        real: "Granular_jitter", granular_jitter
        comment: "Texture / memory modes"
        real: "Anomaly_bias", anomaly_bias
        real: "Anti_repeat", anti_repeat
        comment: "Output"
        real: "Peak_dBFS", peak_dBFS
    advClicked = endPause: "Cancel", "Continue", 2
    if advClicked = 1
        exitScript: "Cancelled."
    endif
endif

# ---- VALIDATE / CLAMP ----
nFeatSelected = use_pitch + use_intensity + use_spectral_centroid
    ... + use_spectral_flux + use_formants
if nFeatSelected = 0
    exitScript: "No features recognised in """ + features$ + """." + newline$
        ... + "Use any of: pitch intensity centroid flux formants deltas all"
endif

if window_length <= 0
    window_length = 0.025
endif
if time_step <= 0
    time_step = 0.010
endif
if pitch_floor <= 0
    pitch_floor = 75
endif
if outlier_threshold < 0.001
    outlier_threshold = 0.001
endif
if outlier_threshold > 0.99
    outlier_threshold = 0.99
endif
if time_step > window_length
    time_step = window_length
endif
if pitch_ceiling <= pitch_floor
    pitch_ceiling = pitch_floor * 4
endif
if fade_ms < 0.5
    fade_ms = 0.5
endif
if min_segment_ms < 2 * fade_ms + 1
    min_segment_ms = 2 * fade_ms + 1
endif
if merge_gap_ms < 0
    merge_gap_ms = 0
endif
if score_smoothing_frames < 0
    score_smoothing_frames = 0
endif
if granular_overlap < 0
    granular_overlap = 0
endif
if granular_overlap > 0.95
    granular_overlap = 0.95
endif
if granular_jitter < 0
    granular_jitter = 0
endif
if anomaly_bias < 0
    anomaly_bias = 0
endif
if anomaly_bias > 12
    anomaly_bias = 12
endif
if anti_repeat < 0
    anti_repeat = 0
endif
if anti_repeat > 0.9
    anti_repeat = 0.9
endif
if texture_length_s < 0.5
    texture_length_s = 0.5
endif
if texture_length_s > 300
    texture_length_s = 300
endif
if peak_dBFS > 0
    peak_dBFS = 0
endif

# ---- MAP OPTION-MENUS TO STRING VALUES ----
if algorithm = 1
    algorithmStr$ = "IsolationForest"
elsif algorithm = 2
    algorithmStr$ = "Mahalanobis"
else
    algorithmStr$ = "Autoencoder"
endif

if concat_mode = 1
    modeStr$ = "chronological"
elsif concat_mode = 2
    modeStr$ = "sorted"
elsif concat_mode = 3
    modeStr$ = "granular"
elsif concat_mode = 4
    modeStr$ = "texture"
else
    modeStr$ = "memory"
endif

# texture and memory decouple output length from how much anomalous
# material was found: the canvas length is asked for directly.
if concat_mode >= 4
    isTexture = 1
else
    isTexture = 0
endif

if join = 1
    joinStr$ = "xfade"
else
    joinStr$ = "butt"
endif

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
tStart    = Get start time
rms_orig  = Get root-mean-square: 0, 0
nyquist   = sr / 2

# Intensity needs at least 6.4 / minPitch seconds of signal.
if use_intensity = 1 and dur < 6.4 / pitch_floor
    exitScript: "Sound is too short for intensity analysis at pitch floor "
        ... + string$(pitch_floor) + " Hz." + newline$
        ... + "Needs at least " + fixed$(6.4 / pitch_floor, 3) + " s, has "
        ... + fixed$(dur, 3) + " s. Raise Pitch floor or use a longer Sound."
endif

if dur < 4 * window_length
    exitScript: "Sound is shorter than 4 analysis windows."
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Anomaly-Driven Outlier Extraction v0.3 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""
appendInfoLine: "Features:  pitch=", use_pitch, " intensity=", use_intensity,
    ... " centroid=", use_spectral_centroid, " flux=", use_spectral_flux,
    ... " formants=", use_formants, " deltas=", use_delta_features
appendInfoLine: "Grid:      window ", fixed$(window_length, 4), " s | step ", fixed$(time_step, 4), " s"
appendInfoLine: "Algorithm: ", algorithmStr$
appendInfoLine: "Threshold: ", fixed$(outlier_threshold, 4), "  (top ", fixed$(outlier_threshold * 100, 1), "% of frames)"
appendInfoLine: "Mode:      ", modeStr$, " | join ", joinStr$
if isTexture = 1
    appendInfoLine: "Texture:   ", fixed$(texture_length_s, 1), " s canvas | bias ",
        ... fixed$(anomaly_bias, 2), " | overlap ", fixed$(granular_overlap, 2),
        ... " | jitter ", fixed$(granular_jitter, 2)
endif
appendInfoLine: ""

# ===========================================================================
# Stage 1 - Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

if algorithm = 1
    probeImports$ = "import numpy, scipy, pandas, soundfile, sklearn"
else
    probeImports$ = "import numpy, scipy, pandas, soundfile"
endif

probeCmd$ = pythonCmd$ + " -c """ + probeImports$
    ... + "; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$
        ... + "Please install: pip install numpy scipy pandas soundfile scikit-learn"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 - Build the analysis grid + analysis objects
# ===========================================================================
appendInfoLine: "[2/5] Building analysis objects..."

# Analysis is always mono: To Spectrum and several other commands fail on
# multi-channel Sounds. The EXPORTED audio stays at its original channel
# count, so the extracted slices keep the source stereo image.
selectObject: sound
if nChannels > 1
    Extract one channel: 1
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif

# Frame centres: first centre one half-window in, last one half-window
# before the end, so every window lies entirely inside the signal.
gridStart = tStart + window_length / 2
gridEnd   = tStart + dur - window_length / 2
nFrames   = floor((gridEnd - gridStart) / time_step) + 1

if nFrames < 8
    removeObject: analysisMono
    exitScript: "Only " + string$(nFrames) + " analysis frames fit in this Sound."
        ... + newline$ + "Reduce Time step or Window length."
endif
if nFrames > 20000
    removeObject: analysisMono
    exitScript: "Analysis grid has " + string$(nFrames) + " frames (limit 20000)."
        ... + newline$ + "Increase Time step or shorten the Sound."
endif

pitchObj   = 0
intObj     = 0
formantObj = 0

if use_pitch = 1
    selectObject: analysisMono
    pitchObj = To Pitch: time_step, pitch_floor, pitch_ceiling
endif

if use_intensity = 1
    selectObject: analysisMono
    intObj = To Intensity: pitch_floor, time_step, "yes"
endif

if use_formants = 1
    maxFormantHz = 5500
    if maxFormantHz > nyquist - 50
        maxFormantHz = nyquist - 50
    endif
    selectObject: analysisMono
    formantObj = To Formant (burg): time_step, 5, maxFormantHz, window_length, 50
endif

# Eight log-spaced bands for spectral flux, from 50 Hz to just under Nyquist
nBands = 8
bandLo = 50
bandHi = nyquist * 0.95
if bandHi <= bandLo * 2
    bandHi = bandLo * 2
endif
bandRatio = (bandHi / bandLo) ^ (1 / nBands)
for b from 0 to nBands
    bandEdge_'b' = bandLo * bandRatio ^ b
endfor

appendInfoLine: "  Grid: ", nFrames, " frames from ", fixed$(gridStart, 3),
    ... " s to ", fixed$(gridStart + (nFrames - 1) * time_step, 3), " s"

# ===========================================================================
# Stage 3 - Sample every feature on the shared grid + export
# ===========================================================================
appendInfoLine: "[3/5] Extracting features..."

if use_spectral_centroid = 1 or use_spectral_flux = 1
    appendInfoLine: "  (per-frame spectra: this is the slow stage)"
endif

colNames$ = "time"
if use_pitch = 1
    colNames$ = colNames$ + " pitch"
endif
if use_intensity = 1
    colNames$ = colNames$ + " intensity"
endif
if use_spectral_centroid = 1
    colNames$ = colNames$ + " centroid"
endif
if use_spectral_flux = 1
    colNames$ = colNames$ + " flux"
endif
if use_formants = 1
    colNames$ = colNames$ + " f1 f2 f3"
endif

Create Table with column names: "featureTable", nFrames, colNames$
featureTable = selected("Table")

havePrevBands = 0
nUndefined = 0

for iF from 1 to nFrames
    tC = gridStart + (iF - 1) * time_step
    t1 = tC - window_length / 2
    t2 = tC + window_length / 2

    selectObject: featureTable
    Set numeric value: iF, "time", tC

    # ---- Pitch ----
    if use_pitch = 1
        selectObject: pitchObj
        pv = Get value at time: tC, "Hertz", "linear"
        selectObject: featureTable
        Set numeric value: iF, "pitch", pv
        if pv = undefined
            nUndefined = nUndefined + 1
        endif
    endif

    # ---- Intensity ----
    if use_intensity = 1
        selectObject: intObj
        iv = Get value at time: tC, "cubic"
        selectObject: featureTable
        Set numeric value: iF, "intensity", iv
        if iv = undefined
            nUndefined = nUndefined + 1
        endif
    endif

    # ---- Spectral centroid and/or flux (share one Spectrum) ----
    if use_spectral_centroid = 1 or use_spectral_flux = 1
        selectObject: analysisMono
        Extract part: t1, t2, "Hanning", 1, "no"
        frameSound = selected("Sound")
        To Spectrum: "yes"
        frameSpec = selected("Spectrum")

        if use_spectral_centroid = 1
            cog = Get centre of gravity: 2
            selectObject: featureTable
            Set numeric value: iF, "centroid", cog
            if cog = undefined
                nUndefined = nUndefined + 1
            endif
            selectObject: frameSpec
        endif

        if use_spectral_flux = 1
            # Half-wave rectified log-energy difference over 8 bands.
            # Rising energy only: this measures onsets, not decays.
            fluxSum = 0
            for b from 1 to nBands
                bPrev = b - 1
                eLo = bandEdge_'bPrev'
                eHi = bandEdge_'b'
                selectObject: frameSpec
                be = Get band energy: eLo, eHi
                if be = undefined
                    be = 0
                endif
                logBe = log10(be + 1e-12)
                if havePrevBands = 1
                    dBand = logBe - prevBand_'b'
                    if dBand > 0
                        fluxSum = fluxSum + dBand
                    endif
                endif
                prevBand_'b' = logBe
            endfor
            if havePrevBands = 0
                # First frame has no predecessor; leave it undefined rather
                # than writing a 0 that would read as "maximally stable".
                fluxVal = undefined
                nUndefined = nUndefined + 1
            else
                fluxVal = fluxSum
            endif
            havePrevBands = 1
            selectObject: featureTable
            Set numeric value: iF, "flux", fluxVal
        endif

        removeObject: frameSpec, frameSound
    endif

    # ---- Formants ----
    if use_formants = 1
        selectObject: formantObj
        fv1 = Get value at time: 1, tC, "hertz", "linear"
        fv2 = Get value at time: 2, tC, "hertz", "linear"
        fv3 = Get value at time: 3, tC, "hertz", "linear"
        selectObject: featureTable
        Set numeric value: iF, "f1", fv1
        Set numeric value: iF, "f2", fv2
        Set numeric value: iF, "f3", fv3
        if fv1 = undefined
            nUndefined = nUndefined + 1
        endif
    endif
endfor

appendInfoLine: "  ", nFrames, " frames measured | undefined cells: ", nUndefined

appendInfoLine: "  Exporting temp files..."
selectObject: sound
Save as WAV file: tempInput$
selectObject: featureTable
Save as comma-separated file: tempCSV$

removeObject: analysisMono, featureTable
if pitchObj <> 0
    removeObject: pitchObj
endif
if intObj <> 0
    removeObject: intObj
endif
if formantObj <> 0
    removeObject: formantObj
endif

# ===========================================================================
# Stage 4 - Call Python
# ===========================================================================
appendInfoLine: "[4/5] Running Python anomaly engine..."
appendInfoLine: "  (", algorithmStr$, ", top ", fixed$(outlier_threshold * 100, 1),
    ... "% of ", nFrames, " frames, mode ", modeStr$, ")"

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " --audio_in """  + tempInput$  + """"
    ... + " --csv_in """    + tempCSV$    + """"
    ... + " --audio_out """ + tempOutput$ + """"
    ... + " --stats_out """ + tempStats$  + """"
    ... + " --algorithm "     + algorithmStr$
    ... + " --threshold "     + fixed$(outlier_threshold, 4)
    ... + " --mode "          + modeStr$
    ... + " --join "          + joinStr$
    ... + " --fade_ms "       + fixed$(fade_ms, 2)
    ... + " --min_seg_ms "    + fixed$(min_segment_ms, 2)
    ... + " --merge_gap_ms "  + fixed$(merge_gap_ms, 2)
    ... + " --max_seg_ms "    + fixed$(max_segment_ms, 2)
    ... + " --smooth_frames " + string$(score_smoothing_frames)
    ... + " --granular_overlap " + fixed$(granular_overlap, 3)
    ... + " --granular_jitter "  + fixed$(granular_jitter, 3)
    ... + " --peak_dbfs "     + fixed$(peak_dBFS, 2)
    ... + " --seed "          + string$(seed)

if isTexture = 1
    pythonCall$ = pythonCall$
        ... + " --texture_duration " + fixed$(texture_length_s, 3)
        ... + " --anomaly_bias "     + fixed$(anomaly_bias, 3)
        ... + " --anti_repeat "      + fixed$(anti_repeat, 3)
endif

if use_delta_features = 1
    pythonCall$ = pythonCall$ + " --deltas"
endif

# Remove any stale output/stats from a PREVIOUS run before calling Python.
# The temp filenames are fixed, so without this a crashed run would leave
# the old files in place and the fileReadable() check below would pass on
# stale data - silently importing a previous result as if it were new.
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif

runSystem_nocheck: pythonCall$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python anomaly engine failed." + newline$
        ... + "Check the terminal / Praat console for the traceback." + newline$
        ... + "Common causes: no frame survived Min segment ms, or a missing package."
endif

# ===========================================================================
# Stage 5 - Import Result
# ===========================================================================
appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: "anomaly_outliers"
resultSound = selected("Sound")

selectObject: resultSound
durOut  = Get total duration
rms_out = Get root-mean-square: 0, 0
outChannels = Get number of channels

# ===========================================================================
# Read Stats
# ===========================================================================
algoStat$      = "?"
scoreKindStat$ = "?"
modeStat$      = "?"
nFramesStat$   = "?"
nFeatStat$     = "?"
featNames$     = "?"
scoreCutStat$  = "?"
nFlaggedStat$  = "?"
nSegStat$      = "?"
outlierDur$    = "?"
coverageStat$  = "?"
meanSegStat$   = "?"
scoreMeanStat$ = "?"
peakBefore$    = "?"
peakGain$      = "?"
nEventsStat$   = "?"
distinctStat$  = "?"
maxRepeatStat$ = "?"
warningStat$   = ""

scoreCut = 0
nScorePts = 0
nSegPts = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "algorithm="
    algoStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "score_kind="
    scoreKindStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode="
    modeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_frames="
    nFramesStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_features="
    nFeatStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "feature_names="
    featNames$ = parseStatLine.result$
    @parseStatLine: statsText$, "score_cut="
    scoreCutStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_flagged_frames="
    nFlaggedStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_segments="
    nSegStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "outlier_duration="
    outlierDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "coverage_percent="
    coverageStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_seg_dur="
    meanSegStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "score_mean="
    scoreMeanStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "peak_before="
    peakBefore$ = parseStatLine.result$
    @parseStatLine: statsText$, "peak_gain_db="
    peakGain$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_events="
    nEventsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "distinct_slices="
    distinctStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "max_repeats="
    maxRepeatStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$

    if scoreCutStat$ <> "?"
        scoreCut = number(scoreCutStat$)
    endif

    # -- Score curve points --
    @parseStatLine: statsText$, "n_score_pts="
    nScorePts$ = parseStatLine.result$
    if nScorePts$ <> "?"
        nScorePts = number(nScorePts$)
    endif
    if nScorePts > 400
        nScorePts = 400
    endif
    for iS from 0 to nScorePts - 1
        @parseStatLine: statsText$, "sc_" + string$(iS) + "="
        scRaw$ = parseStatLine.result$
        sc_'iS'_t = 0
        sc_'iS'_v = 0
        if scRaw$ <> "?"
            comma = index(scRaw$, ",")
            if comma > 0
                sc_'iS'_t = number(left$(scRaw$, comma - 1))
                sc_'iS'_v = number(mid$(scRaw$, comma + 1, length(scRaw$) - comma))
            endif
        endif
    endfor

    # -- Segment rows --
    @parseStatLine: statsText$, "n_seg_pts="
    nSegPts$ = parseStatLine.result$
    if nSegPts$ <> "?"
        nSegPts = number(nSegPts$)
    endif
    if nSegPts > 200
        nSegPts = 200
    endif
    for iG from 0 to nSegPts - 1
        @parseStatLine: statsText$, "sg_" + string$(iG) + "="
        sgRaw$ = parseStatLine.result$
        sg_'iG'_a = 0
        sg_'iG'_b = 0
        sg_'iG'_s = 0
        if sgRaw$ <> "?"
            c1 = index(sgRaw$, ",")
            if c1 > 0
                sg_'iG'_a = number(left$(sgRaw$, c1 - 1))
                rest$ = mid$(sgRaw$, c1 + 1, length(sgRaw$) - c1)
                c2 = index(rest$, ",")
                if c2 > 0
                    sg_'iG'_b = number(left$(rest$, c2 - 1))
                    sg_'iG'_s = number(mid$(rest$, c2 + 1, length(rest$) - c2))
                else
                    sg_'iG'_b = number(rest$)
                endif
            endif
        endif
    endfor
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    # In Picture-window text "_" is SUBSCRIPT markup (and "^" superscript,
    # "%" italic, "#" bold), so a feature called d_pitch would draw as "d"
    # with a subscript. Sanitize anything that reaches a Text command.
    featNamesDraw$ = replace$(featNames$, "_", "-", 0)
    soundNameDraw$ = replace$(soundName$, "_", "-", 0)
    scoreKindDraw$ = replace$(scoreKindStat$, "_", "-", 0)

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title (own band) ===
    Select inner viewport: 0.6, 7.7, 0, 0.34
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Anomaly-Driven Outlier Extraction##"

    # === Subtitle (separate band so it cannot collide with the title) ===
    Select inner viewport: 0.6, 7.7, 0.34, 0.52
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.40, 0.40, 0.50}"
    Text: 0.5, "centre", 0.5, "half", soundNameDraw$ + " | " + presetName$
        ... + " | " + algoStat$ + " | top " + fixed$(outlier_threshold * 100, 1)
        ... + "% | " + modeStat$

    # === Input waveform with outlier regions marked ===
    Select outer viewport: 0, 8, 0.60, 1.55
    Select inner viewport: 0.6, 7.7, 0.73, 1.52
    selectObject: sound
    ampMax = Get maximum: 0, 0, "Sinc70"
    ampMin = Get minimum: 0, 0, "Sinc70"
    ampRange = max(abs(ampMax), abs(ampMin))
    if ampRange <= 0
        ampRange = 1
    endif
    Colour: "{0.50, 0.50, 0.50}"
    Draw: 0, 0, -ampRange, ampRange, "no", "Curve"
    Axes: tStart, tStart + dur, -ampRange, ampRange
    for iG from 0 to nSegPts - 1
        segA = sg_'iG'_a
        segB = sg_'iG'_b
        Paint rectangle: "{0.90, 0.60, 0.55}", segA, segB, -ampRange, -0.86 * ampRange
        Colour: "{0.80, 0.25, 0.20}"
        Line width: 1
        Draw line: segA, -0.95 * ampRange, segA, 0.95 * ampRange
        Draw line: segB, -0.95 * ampRange, segB, 0.95 * ampRange
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Input | " + nSegStat$ + " outlier regions | "
        ... + coverageStat$ + "% of " + fixed$(dur, 2) + " s"

    # === Input spectrogram ===
    Select outer viewport: 0, 8, 1.60, 2.62
    Select inner viewport: 0.6, 7.7, 1.74, 2.60
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Input spectrogram"
    removeObject: specOrig, tmpOrig

    # === Anomaly score curve A(t) ===
    Select outer viewport: 0, 8, 2.68, 3.78
    Select inner viewport: 0.6, 7.7, 2.82, 3.76
    Axes: tStart, tStart + dur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", tStart, tStart + dur, 0, 1

    if nScorePts > 1
        # Region above the cut shaded first, so the curve draws over it
        Colour: "{0.95, 0.85, 0.82}"
        Paint rectangle: "{0.95, 0.85, 0.82}", tStart, tStart + dur, scoreCut, 1
        Colour: "{0.20, 0.40, 0.80}"
        Line width: 1
        for iS from 1 to nScorePts - 1
            iPrevS = iS - 1
            Draw line: sc_'iPrevS'_t, sc_'iPrevS'_v, sc_'iS'_t, sc_'iS'_v
        endfor
        Line width: 2
        Colour: "{0.80, 0.20, 0.20}"
        Draw line: tStart, scoreCut, tStart + dur, scoreCut
        Line width: 1
        Font size: 6
        if scoreCut > 0.85
            cutLabelY = scoreCut - 0.06
        else
            cutLabelY = scoreCut + 0.06
        endif
        Text: tStart + dur * 0.99, "right", cutLabelY, "half",
            ... "cut = " + fixed$(scoreCut, 3)
    else
        Font size: 7
        Colour: "{0.50, 0.50, 0.50}"
        Text: tStart + dur / 2, "centre", 0.5, "half", "(no score data available)"
    endif

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "A(t)"
    Text top: "no", "Anomaly score | " + scoreKindDraw$ + " | flagged "
        ... + nFlaggedStat$ + " / " + nFramesStat$ + " frames"

    # === Segment map (where each slice came from, coloured by score) ===
    Select outer viewport: 0, 8, 3.84, 4.42
    Select inner viewport: 0.6, 7.7, 3.98, 4.40
    Axes: tStart, tStart + dur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", tStart, tStart + dur, 0, 1
    for iG from 0 to nSegPts - 1
        segA = sg_'iG'_a
        segB = sg_'iG'_b
        segS = sg_'iG'_s
        segR = 0.25 + 0.65 * segS
        segG = 0.55 - 0.35 * segS
        segB2 = 0.80 - 0.60 * segS
        Paint rectangle: "{" + fixed$(segR, 2) + ", " + fixed$(segG, 2)
            ... + ", " + fixed$(segB2, 2) + "}", segA, segB, 0.15, 0.85
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Segments"
    Text bottom: "no", "Time in ORIGINAL (s)"
    if isTexture = 1
        Text top: "no", "Corpus regions - resampled to fill the canvas (blue = weaker anomaly | red = stronger)"
    else
        Text top: "no", "Extracted regions (blue = weaker anomaly | red = stronger)"
    endif

    # === Output waveform ===
    Select outer viewport: 0, 8, 4.52, 5.44
    Select inner viewport: 0.6, 7.7, 4.66, 5.42
    selectObject: resultSound
    outMax = Get maximum: 0, 0, "Sinc70"
    outMin = Get minimum: 0, 0, "Sinc70"
    outRange = max(abs(outMax), abs(outMin))
    if outRange <= 0
        outRange = 1
    endif
    Colour: "{0.20, 0.50, 0.70}"
    Draw: 0, 0, -outRange, outRange, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Outliers"
    Text top: "no", "Output | " + modeStat$ + " | " + fixed$(durOut, 2) + " s"

    # === Output spectrogram ===
    Select outer viewport: 0, 8, 5.52, 6.64
    Select inner viewport: 0.6, 7.7, 5.66, 6.60
    selectObject: resultSound
    if outChannels > 1
        Extract one channel: 1
        tmpOut = selected("Sound")
    else
        Copy: "tmpOut"
        tmpOut = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "no", "Time in OUTPUT (s)"
    Text top: "no", "Output spectrogram (channel 1)"
    removeObject: specOut, tmpOut

    # === Summary panel ===
    Select outer viewport: 0, 8, 6.72, 8.0
    Select inner viewport: 0.6, 7.7, 6.76, 7.96
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.77, "half", "Frames: " + nFramesStat$ + " | Features: "
        ... + nFeatStat$ + " (" + featNamesDraw$ + ")"
    Text: 0.02, "left", 0.62, "half", "Algorithm: " + algoStat$ + " | cut = "
        ... + scoreCutStat$ + " | flagged " + nFlaggedStat$ + " frames -> "
        ... + nSegStat$ + " segments | mean seg " + meanSegStat$ + " s"
    if isTexture = 1
        Text: 0.02, "left", 0.47, "half", "Duration: " + fixed$(dur, 2) + " s -> "
            ... + fixed$(durOut, 2) + " s canvas | Mode: " + modeStat$
            ... + " | " + nEventsStat$ + " events from " + distinctStat$
            ... + " slices | max repeats " + maxRepeatStat$ + " | bias "
            ... + fixed$(anomaly_bias, 2)
    else
        Text: 0.02, "left", 0.47, "half", "Duration: " + fixed$(dur, 2) + " s -> "
            ... + fixed$(durOut, 2) + " s (" + coverageStat$ + "% retained) | Mode: "
            ... + modeStat$ + " / " + joinStr$ + " | Fade: " + fixed$(fade_ms, 1) + " ms"
    endif
    Text: 0.02, "left", 0.32, "half", "Peak: " + peakBefore$ + " -> "
        ... + fixed$(peak_dBFS, 1) + " dBFS (" + peakGain$ + " dB) | RMS: "
        ... + fixed$(rms_orig, 4) + " -> " + fixed$(rms_out, 4)
    Colour: "{0.40, 0.40, 0.50}"
    Text: 0.02, "left", 0.17, "half", "Grid: window " + fixed$(window_length, 3)
        ... + " s / step " + fixed$(time_step, 3) + " s | Deltas: "
        ... + string$(use_delta_features) + " | Smoothing: "
        ... + string$(score_smoothing_frames) + " frames | Seed: " + string$(seed)

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.80, 0.20, 0.20}"
        Text: 0.02, "left", 0.04, "half", "Warn: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ===========================================================================
# Cleanup & Summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output object: Sound anomaly_outliers"
appendInfoLine: "Preset:        ", presetName$
appendInfoLine: ""
appendInfoLine: "Algorithm:     ", algoStat$, "  (", scoreKindStat$, ")"
appendInfoLine: "Features:      ", nFeatStat$, "  (", featNames$, ")"
appendInfoLine: "Frames:        ", nFramesStat$
appendInfoLine: "Score cut:     ", scoreCutStat$, "  (mean A(t) = ", scoreMeanStat$, ")"
appendInfoLine: "Flagged:       ", nFlaggedStat$, " frames"
appendInfoLine: "Segments:      ", nSegStat$, "  | mean duration ", meanSegStat$, " s"
appendInfoLine: "Outlier time:  ", outlierDur$, " s  (", coverageStat$, "% of input)"
appendInfoLine: ""
appendInfoLine: "Duration:      ", fixed$(dur, 2), " s -> ", fixed$(durOut, 2), " s"
appendInfoLine: "Mode:          ", modeStat$, " / ", joinStr$
if isTexture = 1
    appendInfoLine: "Texture:       ", nEventsStat$, " events from ", distinctStat$,
        ... " / ", nSegStat$, " slices | max repeats ", maxRepeatStat$
    appendInfoLine: "               canvas ", fixed$(texture_length_s, 1),
        ... " s | bias ", fixed$(anomaly_bias, 2)
endif
appendInfoLine: "Peak:          ", peakBefore$, " -> ", fixed$(peak_dBFS, 1), " dBFS (", peakGain$, " dB)"
appendInfoLine: "RMS:           ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4)

if warningStat$ <> "?" and warningStat$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING:       ", warningStat$
endif

selectObject: resultSound
if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================
procedure parseTwo: .text$, .defA, .defB
    # Read two numbers out of one text field ("0.025 0.010", "75, 600",
    # "0.03/0.01"). Falls back to the defaults on anything unreadable, so a
    # typo degrades to the default rather than to undefined.
    .a = .defA
    .b = .defB
    .s$ = replace_regex$(.text$, "[,;/]", " ", 0)
    .s$ = replace_regex$(.s$, "^[ \t]+", "", 0)
    .s$ = replace_regex$(.s$, "[ \t]+$", "", 0)
    .sp = index_regex(.s$, "[ \t]")
    if .sp > 0
        .a = number(left$(.s$, .sp - 1))
        .rest$ = replace_regex$(mid$(.s$, .sp + 1, length(.s$) - .sp), "^[ \t]+", "", 0)
        .b = number(.rest$)
    elsif length(.s$) > 0
        .a = number(.s$)
    endif
    if .a = undefined
        .a = .defA
    endif
    if .b = undefined
        .b = .defB
    endif
endproc

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc
