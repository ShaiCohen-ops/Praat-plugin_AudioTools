# ============================================================
# Praat AudioTools - TemporalElasticity.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - acoustic reconstruction upgrade
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Temporal Elasticity — Latent Time Warping Engine
#
#   Segments a Sound into events, extracts acoustic features,
#   and calls a Python engine that learns a latent space and
#   builds a temporal field to warp event durations.  A second
#   Python engine renders those durations on the WHOLE Sound
#   through one continuous time map (silences preserved):
#     phase_vocoder  pitch-preserving, transient-protected,
#                    multichannel-coherent phase vocoder
#     varispeed      tape-speed reading; pitch follows speed
#     placement_only original samples placed in the new slots
#
# Dependencies (Python):
#   pip install numpy soundfile
#
# Python backends: latent_time_warp.py (durations, v1.3, unchanged)
#                  te_reconstruct.py   (audio rendering, v1.0)
# The separate stretch.py engine belongs to HPSS_Phase_Vocoder and is
# not called by Temporal Elasticity.
#
# v1.4 acoustic reconstruction upgrade:
#   - Per-event PSOLA / resampling / placement branches and their
#     Concatenate step are replaced by ONE call to te_reconstruct.py,
#     which processes the whole Sound in one pass.  Segmentation now only
#     decides the time map; it no longer cuts the audio.
#   - Silences, leading and trailing time are preserved sample-exactly
#     (v1.3 concatenated sounding events only and dropped every gap).
#   - Option 1 is now a phase vocoder (not PSOLA): no pitch tracking,
#     chords/noise/inharmonic material supported, attacks protected.
#   - Option 2 is explicitly labelled varispeed (pitch changes).
#   - Channel count, order and inter-channel phase are preserved.
#   - True identity path: when every event keeps its duration the
#     output is a Copy of the source (bit-identical, same time domain).
#   - Output keeps the source start time.  Rendered length is checked
#     against the planned length; a mismatch or a missing render is an
#     error, never a silently wrong Sound.
#   - Exchange files: source exported as 32-bit PCM WAV (exact for 16/24-
#     bit material; hot sources are attenuated by an exact power of two
#     and restored in Python), result returned as 64-bit float WAV.
#   - Praat 7 full-trust request; report parsing matches whole keys.
#
# v1.3.1 visualization pass:
#   - Dedicated vertical bands prevent panel titles and axis labels from colliding.
#   - Title/subtitle now remain inside their own header band.
#   - Existing visualization content and semantic colour mapping are preserved.
#
# v1.3 correctness pass:
#   - Sigma is relative to observed latent geometry in the Python backend.
#   - Effective z-dimension is capped by event count (N-1).
#   - Python dependency probing now requires a successful import probe.
#   - Fallback segmentation respects non-zero Sound start times.
#   - Varispeed reconstruction no longer clips requested warp rate at 192 kHz.
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

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
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/latent_time_warp.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/latent_time_warp.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: latent_time_warp.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif
reconScript$ = pluginDir$ + "py/te_reconstruct.py"
if not fileReadable(reconScript$)
    reconScript$ = defaultDirectory$ + "/te_reconstruct.py"
endif
if not fileReadable(reconScript$)
    exitScript: "Cannot find Python script: te_reconstruct.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

# Praat 7.0+ refuses file writes and system calls without full trust.
if praatVersion >= 7000
    if not askForTrust()
        exitScript: "Temporal Elasticity needs permission to write temporary files and run Python."
    endif
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)
runToken$ = string$(sound) + "_" + string$(randomInteger(100000, 999999))
tempBase$ = "temp_te_" + runToken$
patchPrefix$ = tempBase$ + "_patch_"

eventsCSV$    = tempDir$ + tempBase$ + "_events.csv"
durationsCSV$ = tempDir$ + tempBase$ + "_durations.csv"
statsTxt$     = tempDir$ + tempBase$ + "_stats.txt"
probePy$      = tempDir$ + tempBase$ + "_probe.py"
probeMarker$  = tempDir$ + tempBase$ + "_probe.ok"
logTxt$       = tempDir$ + tempBase$ + "_python.log"
sourceWav$    = tempDir$ + tempBase$ + "_source.wav"
renderWav$    = tempDir$ + tempBase$ + "_render.wav"
reconArgs$    = tempDir$ + tempBase$ + "_recon_args.txt"
reconRep$     = tempDir$ + tempBase$ + "_recon.txt"
reconLog$     = tempDir$ + tempBase$ + "_recon.log"

pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
eventsCSVJ$    = replace_regex$(eventsCSV$, "\\", "/", 0)
durationsCSVJ$ = replace_regex$(durationsCSV$, "\\", "/", 0)
statsTxtJ$     = replace_regex$(statsTxt$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)
logTxtJ$       = replace_regex$(logTxt$, "\\", "/", 0)
reconScriptJ$  = replace_regex$(reconScript$, "\\", "/", 0)
reconArgsJ$    = replace_regex$(reconArgs$, "\\", "/", 0)
reconLogJ$     = replace_regex$(reconLog$, "\\", "/", 0)
tempDirJ$      = replace_regex$(tempDir$, "\\", "/", 0)

nEvents = 0

procedure cleanUpTempFiles
    if fileReadable(eventsCSV$)
        deleteFile: eventsCSV$
    endif
    if fileReadable(durationsCSV$)
        deleteFile: durationsCSV$
    endif
    if fileReadable(statsTxt$)
        deleteFile: statsTxt$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(logTxt$)
        deleteFile: logTxt$
    endif
    if fileReadable(sourceWav$)
        deleteFile: sourceWav$
    endif
    if fileReadable(renderWav$)
        deleteFile: renderWav$
    endif
    if fileReadable(renderWav$ + ".part.wav")
        deleteFile: renderWav$ + ".part.wav"
    endif
    if fileReadable(reconArgs$)
        deleteFile: reconArgs$
    endif
    if fileReadable(reconRep$)
        deleteFile: reconRep$
    endif
    if fileReadable(reconLog$)
        deleteFile: reconLog$
    endif
    if nEvents > 0
        for .iPatch from 0 to nEvents - 1
            .patchPath$ = tempDir$ + patchPrefix$ + string$(.iPatch) + ".wav"
            if fileReadable(.patchPath$)
                deleteFile: .patchPath$
            endif
        endfor
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Temporal Elasticity v1.4
    comment ── Preset ───────────────────────────────────────────────────
    optionmenu Preset: 1
        option Custom
        option Gentle warp
        option Rhythmic stretch
        option Gravitational pull
        option Turbulent scatter
        option Time inversion
        option Spectral drift
        option Deep mutation
        option Relativistic

    comment ── Segmentation ──────────────────────────────────────────────
    positive Silence_threshold_(dB) 25.0
    positive Min_event_duration_(s) 0.05
    positive Min_silence_duration_(s) 0.03

    comment ── Latent space ──────────────────────────────────────────────
    integer Latent_dimensions 4
    integer Training_iterations 120
    optionmenu Latent_method: 1
        option ae
        option pca
    integer Random_seed 42

    comment ── Temporal field ────────────────────────────────────────────
    optionmenu Field_mode: 1
        option gravitational
        option inversion
        option turbulence
        option gradient
        option relativistic
    real Amplitude 0.8
    positive Sigma 1.0
    integer Clusters 3

    comment ── Duration rules ────────────────────────────────────────────
    optionmenu Extra_rules: 1
        option none
        option short_stretch
        option long_compress
        option harmonic_compress
        option noisy_dilate

    comment ── Reconstruction ────────────────────────────────────────────
    optionmenu Reconstruction_method: 1
        option phase_vocoder (pitch-preserving)
        option varispeed (pitch changes)
        option placement_only

    comment ── Output ────────────────────────────────────────────────────
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    silence_threshold    = 20.0
    min_event_duration   = 0.04
    min_silence_duration = 0.03
    latent_dimensions    = 4
    training_iterations  = 80
    latent_method        = 1
    random_seed          = 42
    field_mode           = 1
    amplitude            = 0.3
    sigma                = 1.5
    clusters             = 3
    extra_rules          = 1
    reconstruction_method = 1
    presetName$ = "GentleWarp"
elsif preset = 3
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    latent_dimensions    = 4
    training_iterations  = 100
    latent_method        = 2
    random_seed          = 7
    field_mode           = 4
    amplitude            = 0.6
    sigma                = 1.0
    clusters             = 4
    extra_rules          = 2
    reconstruction_method = 2
    presetName$ = "RhythmicStretch"
elsif preset = 4
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    latent_dimensions    = 6
    training_iterations  = 150
    latent_method        = 1
    random_seed          = 42
    field_mode           = 1
    amplitude            = 1.2
    sigma                = 0.8
    clusters             = 4
    extra_rules          = 1
    reconstruction_method = 1
    presetName$ = "GravitationalPull"
elsif preset = 5
    silence_threshold    = 20.0
    min_event_duration   = 0.03
    min_silence_duration = 0.02
    latent_dimensions    = 8
    training_iterations  = 120
    latent_method        = 1
    random_seed          = 99
    field_mode           = 3
    amplitude            = 1.0
    sigma                = 0.6
    clusters             = 5
    extra_rules          = 5
    reconstruction_method = 3
    presetName$ = "TurbulentScatter"
elsif preset = 6
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    latent_dimensions    = 4
    training_iterations  = 120
    latent_method        = 1
    random_seed          = 42
    field_mode           = 2
    amplitude            = 1.0
    sigma                = 1.0
    clusters             = 3
    extra_rules          = 3
    reconstruction_method = 1
    presetName$ = "TimeInversion"
elsif preset = 7
    silence_threshold    = 30.0
    min_event_duration   = 0.08
    min_silence_duration = 0.05
    latent_dimensions    = 6
    training_iterations  = 100
    latent_method        = 2
    random_seed          = 13
    field_mode           = 4
    amplitude            = 0.7
    sigma                = 1.2
    clusters             = 3
    extra_rules          = 4
    reconstruction_method = 2
    presetName$ = "SpectralDrift"
elsif preset = 8
    silence_threshold    = 15.0
    min_event_duration   = 0.03
    min_silence_duration = 0.02
    latent_dimensions    = 12
    training_iterations  = 200
    latent_method        = 1
    random_seed          = 42
    field_mode           = 1
    amplitude            = 1.8
    sigma                = 0.5
    clusters             = 6
    extra_rules          = 1
    reconstruction_method = 1
    presetName$ = "DeepMutation"
elsif preset = 9
    silence_threshold    = 20.0
    min_event_duration   = 0.04
    min_silence_duration = 0.02
    latent_dimensions    = 6
    training_iterations  = 150
    latent_method        = 1
    random_seed          = 42
    field_mode           = 5
    amplitude            = 1.2
    sigma                = 1.0
    clusters             = 4
    extra_rules          = 1
    reconstruction_method = 1
    presetName$ = "Relativistic"
else
    presetName$ = "Custom"
endif

# ---- VALIDATE USER CONTROLS ----
latent_dimensions = max(2, min(16, latent_dimensions))
training_iterations = max(20, min(400, training_iterations))
amplitude = max(0, min(3, amplitude))
sigma = max(0.1, min(5, sigma))
clusters = max(1, min(8, clusters))

# ---- MAP OPTION MENUS TO STRINGS ----
if field_mode = 1
    modeStr$ = "gravitational"
elsif field_mode = 2
    modeStr$ = "inversion"
elsif field_mode = 3
    modeStr$ = "turbulence"
elsif field_mode = 4
    modeStr$ = "gradient"
else
    modeStr$ = "relativistic"
endif

if latent_method = 1
    methodStr$ = "ae"
else
    methodStr$ = "pca"
endif

if extra_rules = 1
    rulesStr$ = "none"
elsif extra_rules = 2
    rulesStr$ = "short_stretch"
elsif extra_rules = 3
    rulesStr$ = "long_compress"
elsif extra_rules = 4
    rulesStr$ = "harmonic_compress"
else
    rulesStr$ = "noisy_dilate"
endif

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
soundStart = Get start time
soundEnd = Get end time
sr  = Get sampling frequency
nChannels = Get number of channels
nSourceSamples = Get number of samples
# Sample-boundary origin: Python counts samples from (x1 - dx/2).
firstSampleTime = Get time from sample number: 1
sampleOrigin = firstSampleTime - 0.5 / sr

if reconstruction_method = 1
    reconMethod$ = "pv"
    reconLabel$ = "phase vocoder"
elsif reconstruction_method = 2
    reconMethod$ = "varispeed"
    reconLabel$ = "varispeed (pitch changes)"
else
    reconMethod$ = "placement"
    reconLabel$ = "placement only"
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Temporal Elasticity v1.4 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Mode:    ", modeStr$, "  Method: ", methodStr$
appendInfoLine: "Rules:   ", rulesStr$
appendInfoLine: "Render:  ", reconLabel$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz"
appendInfoLine: ""

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================
appendInfoLine: "[0/5] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

# Probe the OS-preferred command first, then generic fallbacks.  Keep an
# explicit success flag: a non-empty command string is not proof that Python
# actually launched or that numpy/soundfile are installed.
preferredPython$ = pythonCmd$
if windows
    nCandidates = 5
    candidate1$ = preferredPython$
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = "py -3"
    candidate5$ = "python3"
else
    nCandidates = 4
    candidate1$ = preferredPython$
    candidate2$ = "python3"
    candidate3$ = "python"
    candidate4$ = "py"
    candidate5$ = ""
endif

pythonFound = 0
for iCand from 1 to nCandidates
    if pythonFound = 0
        if iCand = 1
            tryCmd$ = candidate1$
        elsif iCand = 2
            tryCmd$ = candidate2$
        elsif iCand = 3
            tryCmd$ = candidate3$
        elsif iCand = 4
            tryCmd$ = candidate4$
        else
            tryCmd$ = candidate5$
        endif

        if fileReadable(probeMarker$)
            deleteFile: probeMarker$
        endif

        runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

        if fileReadable(probeMarker$)
            pythonCmd$ = tryCmd$
            pythonFound = 1
            deleteFile: probeMarker$
        endif
    endif
endfor

deleteFile: probePy$

if pythonFound = 0
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried the preferred interpreter plus python3/python/py fallbacks." + newline$ + "Please install: pip install numpy soundfile"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 1 — Segment into events
# ===========================================================================
appendInfoLine: "[1/5] Segmenting events..."

# Use the strongest REAL channel for segmentation. Arithmetic fold-down can
# cancel anti-phase stereo and create false silence boundaries.
analysisChannel = 1
bestChannelRms = -1
if nChannels > 1
    for iCh from 1 to nChannels
        selectObject: sound
        chTmp = Extract one channel: iCh
        selectObject: chTmp
        chRms = Get root-mean-square: 0, 0
        if chRms > bestChannelRms
            bestChannelRms = chRms
            analysisChannel = iCh
        endif
        removeObject: chTmp
    endfor
    selectObject: sound
    Extract one channel: analysisChannel
    analysisSound = selected("Sound")
else
    selectObject: sound
    Copy: "te_analysis"
    analysisSound = selected("Sound")
endif
appendInfoLine: "  Analysis channel: ", analysisChannel

selectObject: analysisSound
tg = To TextGrid (silences): 100, 0, -silence_threshold, min_silence_duration,
    ... min_event_duration, "silent", "sounding"

nInt    = Get number of intervals: 1
nEvents = 0

for iInt from 1 to nInt
    selectObject: tg
    lab$ = Get label of interval: 1, iInt
    if lab$ = "sounding"
        evS = Get start time of interval: 1, iInt
        evE = Get end time of interval:   1, iInt
        if evE - evS >= min_event_duration
            nEvents = nEvents + 1
            evStart_'nEvents' = evS
            evEnd_'nEvents'   = evE
        endif
    endif
endfor

removeObject: tg
appendInfoLine: "  Events: ", nEvents

if nEvents < 2
    appendInfoLine: "  Warning: fewer than 2 events — using 0.25 s fallback grid"
    nEvents = 0
    t = soundStart
    while t < soundEnd - 0.001
        tEnd = min(t + 0.25, soundEnd)
        if tEnd - t >= 0.02
            nEvents = nEvents + 1
            evStart_'nEvents' = t
            evEnd_'nEvents'   = tEnd
        endif
        t = t + 0.25
    endwhile
endif
if nEvents < 1
    removeObject: analysisSound
    @cleanUpTempFiles
    exitScript: "No usable events were found in the selected Sound."
endif

# ===========================================================================
# Stage 2 — Feature extraction → events CSV
# ===========================================================================
appendInfoLine: "[2/5] Extracting features..."

writeFileLine: eventsCSV$,
    ... "event_index,start_time,end_time,duration,rms,spectral_centroid,spectral_flatness,zero_crossing_rate,patch_file"

for iEv from 1 to nEvents
    t1 = evStart_'iEv'
    t2 = evEnd_'iEv'
    patchFile$ = patchPrefix$ + string$(iEv - 1) + ".wav"
    patchPath$ = tempDir$ + patchFile$

    # Export the ORIGINAL multichannel event. Python chooses the strongest
    # event channel for its 24-D analysis, preserving anti-phase material.
    selectObject: sound
    patchPart = Extract part: t1, t2, "rectangular", 1, "no"
    selectObject: patchPart
    Save as WAV file: patchPath$
    removeObject: patchPart
    if not fileReadable(patchPath$)
        removeObject: analysisSound
        @cleanUpTempFiles
        exitScript: "Could not export analysis patch: " + patchPath$
    endif

    # Lightweight CSV fallback descriptors come from the same representative
    # channel used for segmentation. Full features are extracted from patches.
    selectObject: analysisSound
    part = Extract part: t1, t2, "rectangular", 1, "no"
    selectObject: part
    rmsVal = Get root-mean-square: 0, 0
    spec = To Spectrum: "yes"
    centroid = Get centre of gravity: 2
    if centroid = undefined
        centroid = 0
    endif
    removeObject: spec, part

    appendFileLine: eventsCSV$,
        ... string$(iEv - 1) + "," +
        ... fixed$(t1, 6) + "," +
        ... fixed$(t2, 6) + "," +
        ... fixed$(t2 - t1, 6) + "," +
        ... fixed$(rmsVal, 6) + "," +
        ... fixed$(centroid / (sr / 2 + 1), 6) + ",0.5,0," + patchFile$
endfor
removeObject: analysisSound

appendInfoLine: "  Wrote: ", eventsCSV$
appendInfoLine: "  Audio patches: ", nEvents

# ===========================================================================
# Stage 3 — Call Python engine
# ===========================================================================
appendInfoLine: "[3/5] Running Python engine..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + eventsCSVJ$ + """"
    ... + " """ + durationsCSVJ$ + """"
    ... + " """ + statsTxtJ$ + """"
    ... + " --z_dim "         + string$(latent_dimensions)
    ... + " --n_iter "        + string$(training_iterations)
    ... + " --latent_method " + methodStr$
    ... + " --seed "          + string$(random_seed)
    ... + " --mode "          + modeStr$
    ... + " --amplitude "     + string$(amplitude)
    ... + " --sigma "         + string$(sigma)
    ... + " --n_clusters "    + string$(clusters)
    ... + " --extra_rules "   + rulesStr$
    ... + " --patch_dir """ + tempDirJ$ + """"

runSystem_nocheck: pythonCall$ + " > """ + logTxtJ$ + """ 2>&1"

if not fileReadable(durationsCSV$)
    errMsg$ = "Python engine failed — durations CSV not found."
    if fileReadable(logTxt$)
        errMsg$ = errMsg$ + newline$ + newline$ + readFile$(logTxt$)
    endif
    @cleanUpTempFiles
    exitScript: errMsg$
endif

# ===========================================================================
# Stage 4 — Read durations + reconstruct
# ===========================================================================
appendInfoLine: "[4/5] Reconstructing (", reconLabel$, ")..."

Read Table from comma-separated file: durationsCSV$
durTable = selected("Table")
nRows    = Get number of rows

maxDurChange = 0
for i from 1 to nRows
    startArr[i]   = Get value: i, "start_time"
    origDurArr[i] = Get value: i, "original_duration"
    scaleArr[i]   = Get value: i, "time_scale"
    newDurArr[i]  = Get value: i, "new_duration"
    z0Arr[i]      = Get value: i, "latent_z0"
    z1Arr[i]      = Get value: i, "latent_z1"
    maxDurChange = max(maxDurChange, abs(newDurArr[i] - origDurArr[i]))
endfor
removeObject: durTable

output_name$ = soundName$ + "_te"

# Planned output length: source length plus every event's duration change.
# Silences and untouched time keep their exact length.
plannedChange = 0
for i from 1 to nRows
    plannedChange = plannedChange + newDurArr[i] - origDurArr[i]
endfor
plannedSamples = round(nSourceSamples + plannedChange * sr)

reconExact$ = "?"
reconOnsets$ = "?"
reconUnprot$ = "0"
reconPeak$ = "?"

if maxDurChange * sr < 0.5
    # ---- Identity path: no event changes length -> exact copy, no resynthesis.
    selectObject: sound
    outputSound = Copy: output_name$
    reconLabel$ = "identity (exact copy)"
    reconExact$ = "1"
    reconOnsets$ = "0"
    reconPeak$ = "unchanged"
    plannedSamples = nSourceSamples
    appendInfoLine: "  All effective scales are 1.0 -> identity copy (no resynthesis)"
else
    # ---- Export the whole source once.  32-bit PCM is exact for 16/24-bit
    # material; values at or above full scale would clip, so a hot source is
    # first attenuated by an exact power of two that Python undoes.
    selectObject: sound
    srcPeak = Get absolute extremum: 0, 0, "None"
    gainExp = 0
    if srcPeak >= 0.999
        gainExp = floor(log2(srcPeak / 0.999)) + 1
    endif
    exportCopy = Copy: "te_export"
    if gainExp > 0
        Formula: "self * " + string$(2 ^ (-gainExp))
    endif
    Save as 32-bit WAV file: sourceWav$
    removeObject: exportCopy
    if not fileReadable(sourceWav$)
        @cleanUpTempFiles
        exitScript: "Could not export the source Sound for reconstruction: " + sourceWav$
    endif

    # Arguments go through a file (one per line): long paths cannot be cut
    # by the ~1 kB command-line limit of Praat's runSystem on Windows.
    writeFileLine: reconArgs$, replace_regex$(sourceWav$, "\\", "/", 0)
    appendFileLine: reconArgs$, durationsCSVJ$
    appendFileLine: reconArgs$, replace_regex$(renderWav$, "\\", "/", 0)
    appendFileLine: reconArgs$, replace_regex$(reconRep$, "\\", "/", 0)
    appendFileLine: reconArgs$, "--method=" + reconMethod$
    appendFileLine: reconArgs$, "--time_offset=" + fixed$(sampleOrigin, 12)
    appendFileLine: reconArgs$, "--input_gain=" + string$(2 ^ gainExp)

    reconCall$ = pythonCmd$ + " """ + reconScriptJ$ + """ ""@" + reconArgsJ$ + """"
    runSystem_nocheck: reconCall$ + " > """ + reconLogJ$ + """ 2>&1"

    if not fileReadable(renderWav$)
        errMsg$ = "Reconstruction engine failed - no rendered audio was produced."
        if fileReadable(reconLog$)
            errMsg$ = errMsg$ + newline$ + newline$ + readFile$(reconLog$)
        endif
        @cleanUpTempFiles
        exitScript: errMsg$
    endif

    # The engine rounds every event boundary to a sample, so its exact plan
    # may differ from the float estimate above by up to one sample per event.
    enginePlan = undefined
    if fileReadable(reconRep$)
        reconText$ = newline$ + readFile$(reconRep$)
        @parseKey: reconText$, "planned_out_samples"
        enginePlan = number(parseKey.result$)
    endif
    if enginePlan = undefined or abs(enginePlan - plannedSamples) > nRows + 1
        @cleanUpTempFiles
        exitScript: "Reconstruction report missing or inconsistent with the event plan" + newline$ +
            ... "(engine plan " + string$(enginePlan) + " samples, script plan " + string$(plannedSamples) + ")."
    endif
    plannedSamples = enginePlan

    outputSound = Read from file: renderWav$
    Rename: output_name$
    outCh = Get number of channels
    outN = Get number of samples
    outSr = Get sampling frequency
    if outCh <> nChannels or outSr <> sr or outN <> plannedSamples
        removeObject: outputSound
        @cleanUpTempFiles
        exitScript: "Reconstruction returned an inconsistent Sound:" + newline$ +
            ... "channels " + string$(outCh) + " (expected " + string$(nChannels) + "), " +
            ... "rate " + string$(outSr) + " Hz, samples " + string$(outN) +
            ... " (planned " + string$(plannedSamples) + ")."
    endif
    Shift times to: "start time", soundStart

    if fileReadable(reconRep$)
        @parseKey: reconText$, "exact_fraction"
        reconExact$ = parseKey.result$
        @parseKey: reconText$, "onsets_protected"
        reconOnsets$ = parseKey.result$
        @parseKey: reconText$, "onsets_unprotected"
        reconUnprot$ = parseKey.result$
        @parseKey: reconText$, "peak_out"
        reconPeak$ = parseKey.result$
    endif
endif

selectObject: outputSound
measuredOutputDur = Get total duration
appendInfoLine: "  Rendered: ", fixed$(measuredOutputDur, 4), " s (planned ", fixed$(plannedSamples / sr, 4), " s), ",
    ... nChannels, " ch"
appendInfoLine: "  Exact (unresynthesised) fraction: ", reconExact$, " | attacks protected: ", reconOnsets$
outPeakCheck = Get absolute extremum: 0, 0, "None"
if outPeakCheck > 1
    appendInfoLine: "  Note: rendered peak ", fixed$(outPeakCheck, 3), " exceeds full scale (not normalized;",
        ... " phase changes can raise the crest of noisy material). Scale before saving to integer formats."
endif

# ---- Read stats ----
# Keys are matched as whole lines (newline + key + "="), so e.g. "scale_mean"
# can no longer match inside "field_scale_mean".
procedure parseKey: .text$, .key$
    @parseStatLine: .text$, newline$ + .key$ + "="
    .result$ = parseStatLine.result$
endproc

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl    = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

nEvStat$       = "?"
zDimStat$      = "?"
methodStat$    = "?"
modeStat$      = "?"
rulesStat$     = "?"
lossInitStat$  = "?"
lossFinalStat$ = "?"
comprStat$     = "?"
origDurStat$   = "?"
newDurStat$    = "?"
scaleMinStat$  = "?"
scaleMaxStat$  = "?"
scaleMeanStat$ = "?"
entrStat$      = "?"

if fileReadable(statsTxt$)
    statsText$ = newline$ + readFile$(statsTxt$)
    @parseKey: statsText$, "n_events"
    nEvStat$ = parseKey.result$
    @parseKey: statsText$, "z_dim"
    zDimStat$ = parseKey.result$
    @parseKey: statsText$, "latent_method"
    methodStat$ = parseKey.result$
    @parseKey: statsText$, "field_mode"
    modeStat$ = parseKey.result$
    @parseKey: statsText$, "extra_rules"
    rulesStat$ = parseKey.result$
    @parseKey: statsText$, "latent_loss_initial"
    lossInitStat$ = parseKey.result$
    @parseKey: statsText$, "latent_loss_final"
    lossFinalStat$ = parseKey.result$
    @parseKey: statsText$, "compression_ratio"
    comprStat$ = parseKey.result$
    @parseKey: statsText$, "orig_total_dur"
    origDurStat$ = parseKey.result$
    @parseKey: statsText$, "new_total_dur"
    newDurStat$ = parseKey.result$
    @parseKey: statsText$, "scale_min"
    scaleMinStat$ = parseKey.result$
    @parseKey: statsText$, "scale_max"
    scaleMaxStat$ = parseKey.result$
    @parseKey: statsText$, "scale_mean"
    scaleMeanStat$ = parseKey.result$
    @parseKey: statsText$, "scale_entropy"
    entrStat$ = parseKey.result$
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Drawing visualization..."

    # Representative real channels for fair before/after comparison.
    selectObject: sound
    if nChannels > 1
        Extract one channel: analysisChannel
        vizOrig = selected("Sound")
    else
        Copy: "te_viz_orig"
        vizOrig = selected("Sound")
    endif

    selectObject: outputSound
    nOutChannels = Get number of channels
    outAnalysisChannel = 1
    if nOutChannels > 1
        outBestRms = -1
        for iCh from 1 to nOutChannels
            selectObject: outputSound
            outChTmp = Extract one channel: iCh
            selectObject: outChTmp
            outChRms = Get root-mean-square: 0, 0
            if outChRms > outBestRms
                outBestRms = outChRms
                outAnalysisChannel = iCh
            endif
            removeObject: outChTmp
        endfor
        selectObject: outputSound
        Extract one channel: outAnalysisChannel
        vizOut = selected("Sound")
    else
        selectObject: outputSound
        Copy: "te_viz_out"
        vizOut = selected("Sound")
    endif

    selectObject: vizOrig
    origVizPeak = Get absolute extremum: 0, 0, "Sinc70"
    selectObject: vizOut
    outVizPeak = Get absolute extremum: 0, 0, "Sinc70"
    sharedVizPeak = max(origVizPeak, outVizPeak) * 1.05 + 1e-6

    # The visualization uses dedicated header / title / axis bands.  Do not
    # tighten these viewports without checking a rendered Picture: the spacing
    # is intentional and prevents adjacent panel annotations from colliding.
    Erase all
    Select outer viewport: 0, 8, 0, 9.2

    # === Header band ===
    Select outer viewport: 0, 8, 0, 0.58
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Temporal Elasticity — Latent Time Warping##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.20, "half", soundName$ + " | " + presetName$ + " | " + modeStr$ + " | " + methodStat$ + " | z=" + zDimStat$

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.72, 1.70
    Select inner viewport: 0.6, 7.7, 0.88, 1.60
    selectObject: vizOrig
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, -sharedVizPeak, sharedVizPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"

    # === Output waveform ===
    Select outer viewport: 0, 8, 1.82, 2.84
    Select inner viewport: 0.6, 7.7, 1.98, 2.64
    selectObject: vizOut
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, -sharedVizPeak, sharedVizPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Warped"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Rendered " + fixed$(measuredOutputDur, 2) + " s | planned " + fixed$(plannedSamples / sr, 2) + " s | " + reconLabel$

    # === Latent map (actual mechanism) ===
    Select outer viewport: 0, 8, 3.04, 4.50
    Select inner viewport: 0.6, 7.7, 3.22, 4.26
    z0min = z0Arr[1]
    z0max = z0Arr[1]
    z1min = z1Arr[1]
    z1max = z1Arr[1]
    for i from 2 to nRows
        z0min = min(z0min, z0Arr[i])
        z0max = max(z0max, z0Arr[i])
        z1min = min(z1min, z1Arr[i])
        z1max = max(z1max, z1Arr[i])
    endfor
    z0range = z0max - z0min
    z1range = z1max - z1min
    if z0range < 1e-6
        z0range = 1
    endif
    if z1range < 1e-6
        z1range = 1
    endif
    z0lo = z0min - 0.10 * z0range
    z0hi = z0max + 0.10 * z0range
    z1lo = z1min - 0.12 * z1range
    z1hi = z1max + 0.12 * z1range
    Axes: z0lo, z0hi, z1lo, z1hi
    Paint rectangle: "{0.96, 0.96, 0.98}", z0lo, z0hi, z1lo, z1hi
    Colour: "{0.70, 0.70, 0.76}"
    for i from 1 to nRows - 1
        Draw line: z0Arr[i], z1Arr[i], z0Arr[i + 1], z1Arr[i + 1]
    endfor
    for i from 1 to nRows
        Select inner viewport: 0.6, 7.7, 3.22, 4.26
        Axes: z0lo, z0hi, z1lo, z1hi
        if scaleArr[i] < 0.98
            pointCol$ = "{0.20,0.42,0.88}"
        elsif scaleArr[i] > 1.02
            pointCol$ = "{0.88,0.30,0.22}"
        else
            pointCol$ = "{0.45,0.45,0.50}"
        endif
        Paint circle: pointCol$, z0Arr[i], z1Arr[i], 0.11
    endfor
    Select inner viewport: 0.6, 7.7, 3.22, 4.26
    Axes: z0lo, z0hi, z1lo, z1hi
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "latent z1"
    Text bottom: "yes", "latent z0"
    Text top: "no", "Latent trajectory — effective scale: blue compress · red stretch"

    # === Output spectrogram ===
    Select outer viewport: 0, 8, 4.74, 6.20
    Select inner viewport: 0.6, 7.7, 4.92, 5.96
    vizFmax = min(8000, sr / 2 - 1)
    selectObject: vizOut
    To Spectrogram: 0.005, vizFmax, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, vizFmax, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Warped spectrogram (auto-levelled; representative output channel)"
    removeObject: specOut

    # === Scale per event bar chart ===
    Select outer viewport: 0, 8, 6.44, 7.80
    Select inner viewport: 0.6, 7.7, 6.62, 7.56

    smin = scaleArr[1]
    smax = scaleArr[1]
    for i from 2 to nRows
        if scaleArr[i] < smin
            smin = scaleArr[i]
        endif
        if scaleArr[i] > smax
            smax = scaleArr[i]
        endif
    endfor

    scaleTop = max(1.10, smax * 1.15 + 0.05)
    Axes: 0, nRows + 1, 0, scaleTop
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, nRows + 1, 0, scaleTop
    for i from 1 to nRows
        if scaleArr[i] < 0.98
            barCol$ = "{0.20,0.42,0.88}"
        elsif scaleArr[i] > 1.02
            barCol$ = "{0.88,0.30,0.22}"
        else
            barCol$ = "{0.45,0.45,0.50}"
        endif
        Paint rectangle: barCol$, i - 0.4, i + 0.4, 0, scaleArr[i]
    endfor
    Line width: 2
    Colour: "{0.8, 0.2, 0.2}"
    Draw line: 0, 1.0, nRows + 1, 1.0
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Time scale"
    Text bottom: "yes", "Event index"
    Text top: "no", "Scale per event  (blue=compress · red=stretch · line=1.0)"

    # === Summary panel ===
    Select outer viewport: 0, 8, 8.04, 9.10
    Select inner viewport: 0.6, 7.7, 8.14, 9.00
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.86, "half", "##Run statistics##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.66, "half",
        ... "Events: " + nEvStat$ +
        ... " | Latent: " + methodStat$ + " z=" + zDimStat$ +
        ... " | Fit metric: " + lossInitStat$ + " → " + lossFinalStat$
    Text: 0.02, "left", 0.48, "half",
        ... "Field: " + modeStat$ +
        ... " | Rules: " + rulesStat$ +
        ... " | Scale: [" + scaleMinStat$ + ", " + scaleMaxStat$ + "]  mean=" + scaleMeanStat$
    Text: 0.02, "left", 0.30, "half",
        ... "Event-sum: " + origDurStat$ + " s → " + newDurStat$ + " s | Rendered (with silences): " + fixed$(measuredOutputDur, 2) + " s" +
        ... " | Ratio: " + comprStat$ +
        ... " | Entropy: " + entrStat$
    Text: 0.02, "left", 0.12, "half",
        ... "Render: " + reconLabel$ + " | " + string$(nChannels) + " ch" +
        ... " | exact fraction " + reconExact$ +
        ... " | attacks protected " + reconOnsets$ + " (unprotected " + reconUnprot$ + ")"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    removeObject: vizOrig, vizOut
else
    appendInfoLine: "[5/5] Visualization skipped."
endif

# ---- FINAL CLEANUP ----
@cleanUpTempFiles

# ---- Summary ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:    ", output_name$
appendInfoLine: "Preset:    ", presetName$
appendInfoLine: "Events:    ", nEvStat$, " | Latent: ", methodStat$, " z=", zDimStat$
appendInfoLine: "Field:     ", modeStat$, " | Rules: ", rulesStat$
appendInfoLine: "Fit metric:", lossInitStat$, " → ", lossFinalStat$
appendInfoLine: "Duration:  event sum ", origDurStat$, " s → ", newDurStat$, " s; rendered ", fixed$(measuredOutputDur, 3), " s (silences kept)"
appendInfoLine: "Render:    ", reconLabel$, " | ", nChannels, " ch | exact fraction ", reconExact$,
    ... " | attacks protected ", reconOnsets$, " | peak ", reconPeak$
appendInfoLine: "Scale:     [", scaleMinStat$, ", ", scaleMaxStat$, "]  mean=", scaleMeanStat$

selectObject: outputSound

if play_result
    Play
endif
