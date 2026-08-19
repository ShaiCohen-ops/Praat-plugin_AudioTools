# ============================================================
# Praat AudioTools - SSMComposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - SSM reliability + analysis-channel + visualization QA
#   v1.4: strongest-RMS analysis channel (no anti-phase fold cancellation);
#   Python feature/metric fixes; neutral transform parameters are exact identity;
#   teleports obey tabu; SSM panels use one fixed 0..1 display scale;
#   waveform panels use the same representative channel and Y range;
#   unused matplotlib PNG generation removed; SSM matrices exported only when
#   their panels are actually requested; summary/viewports repaired.
#
# Version: 1.3.1 (2026) - Short form for small screens (layout only)
#   v1.3.1: the single form showed ~20 fields at once and no longer fit a
#   laptop screen. The form now asks only Preset + the output toggles;
#   right after it, Custom runs get a short beginPause dialog (four small
#   screens) with everything else, and named presets skip it (they already
#   supply all values). No field was removed and no default changed - this
#   is the same layout pattern as Corpus_Concatenative_Codec v1.9.
# Version: 1.3 (2026)
#
# Changelog v1.2 (2026) -- external-review repairs:
#   - The visualization shows the ENGINE'S REAL matrices (exported
#     as matrix text): the old display rebuilt a different
#     MFCC-based SSM, always cosine, and labeled an unmodified
#     COPY "SSM after transform" -- no transformation was ever
#     shown.
#   - True overlapped crossfades (Concatenate with overlap,
#     clamped to the shortest chunk): the old fade+Concatenate
#     made faded butt joints, not crossfades.
#   - Original (identity) mode + Transformation_amount 0..1
#     (graded blend engine-side) -- proper A/B and ablations.
#   - Preserve_event_durations removed (never used anywhere).
#   - Unique per-run temp names (parallel runs no longer collide);
#     python stderr captured to a log and echoed on failure;
#     pythonCmd$ properly reset before the dependency probe.
#   - Sharpen relabeled "similarity contrast" (engine analysis:
#     with visit penalty off it is largely redundant with low
#     temperature).
#   - Summary shows the new engine metrics (Frobenius change,
#     path similarity on both matrices, coverage, teleport rate,
#     chronological jump/runs).
#   - Title strip on house geometry.
#
# Changelog v1.3 (2026) -- third-round review repairs:
#   - Transformation parameters exposed (Blur sigma, Sharpen
#     gamma, Diffusion alpha/steps, Motif boost, Warp amplitude)
#     and a separate Transformation_seed distinct from the
#     Navigation seed -- reshape the topology without moving the
#     path, or vice versa.
#   - Multichannel (not only stereo): analysis + patches use a
#     mono mixdown for any nChannels > 1; reconstruction still
#     cuts from the original sound, preserving channel count and
#     spatial image.
#   - The reported output duration is now MEASURED from the
#     crossfaded result (Get total duration), not the engine's
#     planned sum-of-events (which ignores the overlaps).
#   - Doc fixes: header no longer says Sharpen "reinforces
#     motifs"; the mislabeled "Similarity contrast" preset (which ran
#     Sharpen) renamed "Similarity contrast"; the mode list
#     description corrected.
#   - Cleanup removes the SSM PNGs too.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SSM Morph Composer — Structure-Driven Audio Recomposition
#
#   Segments a Sound into events and sends boundaries + patches
#   to a Python engine that builds a Self-Similarity Matrix (SSM),
#   transforms it, and navigates a new event path through the
#   modified structure.
#
#   Praat then reassembles the original audio by extracting and
#   concatenating events in the new order with crossfade.
#
#   SSM transformation modes:
#     Blur         — smooth structural boundaries (ambient)
#     Sharpen      — monotone similarity-contrast reshaping (repetitive)
#     Diffusion    — spread similarity across structure (evolving)
#     MotifAmplify — amplify diagonal bands (loop-like)
#     StructureWarp — warp SSM coordinates (folded time)
#
# Dependencies (Python):
#   pip install numpy scipy soundfile
#
# Citation:
#   Cohen, S. (2026). SSM Morph Composer:
#   Structure-Driven Audio Recomposition in Praat.
#   Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSound = selected("Sound")
origName$ = selected$("Sound")
nChannels = Get number of channels
isMultichannel = (nChannels > 1)

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

pythonScript$ = pluginDir$ + "py/ssm_morph_engine.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/ssm_morph_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: ssm_morph_engine.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

# v1.2: unique per-run names -- parallel Praat instances no
# longer overwrite each other's temp files
uid$ = string$(randomInteger(100000, 999999))
eventsCSV$   = tempDir$ + "temp_ssm_" + uid$ + "_events.csv"
planCSV$     = tempDir$ + "temp_ssm_" + uid$ + "_plan.csv"
statsTxt$    = tempDir$ + "temp_ssm_" + uid$ + "_stats.txt"
patchDir$    = tempDir$
patchPrefix$ = "patch_" + uid$ + "_"
ssmOrigPng$  = tempDir$ + "temp_ssm_" + uid$ + "_original.png"
ssmModPng$   = tempDir$ + "temp_ssm_" + uid$ + "_modified.png"
ssmOrigTxt$  = tempDir$ + "temp_ssm_" + uid$ + "_orig.txt"
ssmModTxt$   = tempDir$ + "temp_ssm_" + uid$ + "_mod.txt"
runLog$      = tempDir$ + "temp_ssm_" + uid$ + "_runlog.txt"
probePy$     = tempDir$ + "temp_ssm_" + uid$ + "_probe.py"
probeMarker$ = tempDir$ + "temp_ssm_" + uid$ + "_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
eventsCSVJ$    = replace_regex$(eventsCSV$, "\\", "/", 0)
planCSVJ$      = replace_regex$(planCSV$, "\\", "/", 0)
statsTxtJ$     = replace_regex$(statsTxt$, "\\", "/", 0)
patchDirJ$     = replace_regex$(patchDir$, "\\", "/", 0)
ssmOrigPngJ$   = replace_regex$(ssmOrigPng$, "\\", "/", 0)
ssmModPngJ$    = replace_regex$(ssmModPng$, "\\", "/", 0)
ssmOrigTxtJ$   = replace_regex$(ssmOrigTxt$, "\\", "/", 0)
ssmModTxtJ$    = replace_regex$(ssmModTxt$, "\\", "/", 0)
runLogJ$       = replace_regex$(runLog$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(eventsCSV$)
        deleteFile: eventsCSV$
    endif
    if fileReadable(planCSV$)
        deleteFile: planCSV$
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
    if fileReadable(ssmOrigPng$)
        deleteFile: ssmOrigPng$
    endif
    if fileReadable(ssmModPng$)
        deleteFile: ssmModPng$
    endif
    if fileReadable(ssmOrigTxt$)
        deleteFile: ssmOrigTxt$
    endif
    if fileReadable(ssmModTxt$)
        deleteFile: ssmModTxt$
    endif
    if fileReadable(runLog$)
        deleteFile: runLog$
    endif
    for .iEv from 0 to 9999
        .patchPath$ = patchDir$ + patchPrefix$ + string$(.iEv) + ".wav"
        if fileReadable(.patchPath$)
            deleteFile: .patchPath$
        else
            .iEv = 9999
        endif
    endfor
endproc

@cleanUpTempFiles

# ---- FORM (v1.3.1) ----
# Short form: only Preset + the output toggles every run needs. Everything
# else is defaulted in code below, then - for Custom only - a beginPause
# dialog shows the parameters grouped by section. Choosing a named preset
# skips the dialog entirely (the preset supplies all values), so the whole
# thing fits a laptop screen. No field was removed and no default changed;
# this is a layout change only (the Corpus_Concatenative_Codec v1.9 pattern).
form SSM Morph Composer v1.4
    comment ── Preset (choose Custom to edit all parameters) ──
    optionmenu Preset: 1
        option Custom
        option Ambient blur
        option Similarity contrast
        option Diffuse field
        option Loop engine
        option Folded time
        option Frozen texture
        option Spectral labyrinth
    comment ── Output ──
    boolean Draw_SSM 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

clearinfo

# ---- PARAMETER DEFAULTS (match the old v1.3 form defaults exactly) ----
# A named preset overwrites the relevant ones in the preset block below;
# for Custom, the beginPause dialog (also below) overwrites them from the
# user's input. Everything starts here so no code path sees an unset value.
sSM_mode             = 1
transform_amount     = 1.0
blur_sigma           = 2.5
sharpen_gamma        = 3.0
diffusion_alpha      = 0.85
diffusion_steps      = 4
motif_boost          = 2.0
warp_amplitude       = 0.15
transformation_seed  = -1
output_events        = 300
similarity_metric    = 1
temperature          = 0.3
tabu_length          = 10
teleport_probability = 0.02
visit_penalty        = 0.3
seed                 = 1234
silence_threshold_dB   = -25
min_silent_interval_s  = 0.08
min_sounding_interval_s = 0.03
crossfade_ms         = 10

# ---- PRESETS ----
if preset = 2
    sSM_mode                = 1
    output_events           = 400
    similarity_metric       = 1
    temperature             = 0.8
    tabu_length             = 5
    seed                    = 1234
    teleport_probability    = 0.03
    visit_penalty           = 0.4
    silence_threshold_dB    = -25
    min_silent_interval_s   = 0.08
    min_sounding_interval_s = 0.03
    crossfade_ms            = 30
    transform_amount        = 1.0
    blur_sigma = 3.5
    diffusion_alpha = 0.85
    diffusion_steps = 4
    motif_boost = 2.0
    warp_amplitude = 0.15
    sharpen_gamma = 3.0
    transformation_seed = -1
    presetName$             = "AmbientBlur"
elsif preset = 3
    sSM_mode                = 2
    output_events           = 200
    similarity_metric       = 1
    temperature             = 0.1
    tabu_length             = 3
    seed                    = 42
    teleport_probability    = 0.01
    visit_penalty           = 0.1
    silence_threshold_dB    = -20
    min_silent_interval_s   = 0.05
    min_sounding_interval_s = 0.03
    crossfade_ms            = 5
    transform_amount        = 1.0
    blur_sigma = 2.5
    diffusion_alpha = 0.85
    diffusion_steps = 4
    motif_boost = 2.0
    warp_amplitude = 0.15
    sharpen_gamma = 3.0
    transformation_seed = -1
    presetName$             = "SimilarityContrast"
elsif preset = 4
    sSM_mode                = 3
    output_events           = 300
    similarity_metric       = 1
    temperature             = 0.5
    tabu_length             = 8
    seed                    = 1234
    teleport_probability    = 0.02
    visit_penalty           = 0.3
    silence_threshold_dB    = -25
    min_silent_interval_s   = 0.08
    min_sounding_interval_s = 0.03
    crossfade_ms            = 15
    transform_amount        = 1.0
    blur_sigma = 2.5
    diffusion_alpha = 0.9
    diffusion_steps = 6
    motif_boost = 2.0
    warp_amplitude = 0.15
    sharpen_gamma = 3.0
    transformation_seed = -1
    presetName$             = "DiffuseField"
elsif preset = 5
    sSM_mode                = 4
    output_events           = 300
    similarity_metric       = 1
    temperature             = 0.05
    tabu_length             = 20
    seed                    = 7
    teleport_probability    = 0.005
    visit_penalty           = 0.5
    silence_threshold_dB    = -20
    min_silent_interval_s   = 0.05
    min_sounding_interval_s = 0.02
    crossfade_ms            = 8
    transform_amount        = 1.0
    blur_sigma = 2.5
    diffusion_alpha = 0.85
    diffusion_steps = 4
    motif_boost = 2.5
    warp_amplitude = 0.15
    sharpen_gamma = 3.0
    transformation_seed = -1
    presetName$             = "LoopEngine"
elsif preset = 6
    sSM_mode                = 5
    output_events           = 250
    similarity_metric       = 2
    temperature             = 0.4
    tabu_length             = 12
    seed                    = 999
    teleport_probability    = 0.02
    visit_penalty           = 0.3
    silence_threshold_dB    = -25
    min_silent_interval_s   = 0.08
    min_sounding_interval_s = 0.03
    crossfade_ms            = 20
    transform_amount        = 1.0
    blur_sigma = 2.5
    diffusion_alpha = 0.85
    diffusion_steps = 4
    motif_boost = 2.0
    warp_amplitude = 0.25
    sharpen_gamma = 3.0
    transformation_seed = -1
    presetName$             = "FoldedTime"
elsif preset = 7
    sSM_mode                = 1
    output_events           = 500
    similarity_metric       = 1
    temperature             = 0.02
    tabu_length             = 2
    seed                    = 1234
    teleport_probability    = 0.005
    visit_penalty           = 0.2
    silence_threshold_dB    = -30
    min_silent_interval_s   = 0.1
    min_sounding_interval_s = 0.05
    crossfade_ms            = 50
    transform_amount        = 1.0
    blur_sigma = 4.0
    diffusion_alpha = 0.85
    diffusion_steps = 4
    motif_boost = 2.0
    warp_amplitude = 0.15
    sharpen_gamma = 3.0
    transformation_seed = -1
    presetName$             = "FrozenTexture"
elsif preset = 8
    sSM_mode                = 3
    output_events           = 400
    similarity_metric       = 2
    temperature             = 0.9
    tabu_length             = 15
    seed                    = 314
    teleport_probability    = 0.05
    visit_penalty           = 0.6
    silence_threshold_dB    = -15
    min_silent_interval_s   = 0.05
    min_sounding_interval_s = 0.02
    crossfade_ms            = 10
    transform_amount        = 1.0
    blur_sigma = 2.5
    diffusion_alpha = 0.88
    diffusion_steps = 5
    motif_boost = 2.0
    warp_amplitude = 0.3
    sharpen_gamma = 3.0
    transformation_seed = -1
    presetName$             = "SpectralLabyrinth"
else
    presetName$ = "Custom"
endif

# ---- CUSTOM PARAMETERS (v1.3.1) ----
# For Custom only: show the parameters the slim form no longer carries,
# grouped into short screens that each fit a laptop display. A named preset
# supplied every value already, so it skips this entirely. beginPause field
# names mangle to variables exactly like form fields (e.g. "Blur sigma" ->
# blur_sigma), so these overwrite the defaults set above.
if preset = 1
    beginPause: "SSM Morph (1/4): transformation"
        comment: "Which structural transformation to apply to the similarity matrix:"
        optionMenu: "SSM mode", 1
            option: "Blur"
            option: "Sharpen (similarity contrast)"
            option: "Diffusion"
            option: "MotifAmplify"
            option: "StructureWarp"
            option: "Original (identity baseline)"
        comment: "Transform amount: 0 = original matrix, 1 = fully transformed:"
        real: "Transform amount", transform_amount
    endPause: "Continue", 1

    beginPause: "SSM Morph (2/4): transform parameters"
        comment: "Only the parameter for the SSM mode chosen above has any effect:"
        positive: "Blur sigma", blur_sigma
        positive: "Sharpen gamma", sharpen_gamma
        real: "Diffusion alpha", diffusion_alpha
        natural: "Diffusion steps", diffusion_steps
        real: "Motif boost", motif_boost
        real: "Warp amplitude", warp_amplitude
        comment: "Transformation seed shapes the StructureWarp field only"
        comment: "(-1 = reuse the navigation Seed on screen 3):"
        integer: "Transformation seed", transformation_seed
    endPause: "Continue", 1

    beginPause: "SSM Morph (3/4): navigation"
        comment: "How the walk traverses the (possibly transformed) matrix:"
        integer: "Output events", output_events
        optionMenu: "Similarity metric", 1
            option: "cosine"
            option: "euclidean"
        real: "Temperature", temperature
        integer: "Tabu length", tabu_length
        real: "Teleport probability", teleport_probability
        real: "Visit penalty", visit_penalty
        integer: "Seed", seed
    endPause: "Continue", 1

    beginPause: "SSM Morph (4/4): segmentation + reconstruction"
        comment: "How the source is cut into events:"
        real: "Silence threshold dB", silence_threshold_dB
        real: "Min silent interval s", min_silent_interval_s
        real: "Min sounding interval s", min_sounding_interval_s
        comment: "Overlap between reassembled events:"
        real: "Crossfade ms", crossfade_ms
    endPause: "Continue", 1
endif

# ---- MAP OPTION MENUS TO STRINGS ----
if sSM_mode = 1
    modeStr$ = "Blur"
elsif sSM_mode = 2
    modeStr$ = "Sharpen"
elsif sSM_mode = 3
    modeStr$ = "Diffusion"
elsif sSM_mode = 4
    modeStr$ = "MotifAmplify"
elsif sSM_mode = 5
    modeStr$ = "StructureWarp"
else
    modeStr$ = "Original"
endif
if transform_amount < 0
    transform_amount = 0
elsif transform_amount > 1
    transform_amount = 1
endif
if blur_sigma < 0
    blur_sigma = 0
endif
if sharpen_gamma <= 0
    sharpen_gamma = 0.000001
endif
if diffusion_alpha < 0
    diffusion_alpha = 0
elsif diffusion_alpha > 1
    diffusion_alpha = 1
endif
if diffusion_steps < 0
    diffusion_steps = 0
elsif diffusion_steps > 100
    diffusion_steps = 100
endif
if motif_boost < 0
    motif_boost = 0
endif
if warp_amplitude < 0
    warp_amplitude = 0
endif
if crossfade_ms < 0
    crossfade_ms = 0
endif

if similarity_metric = 1
    metricStr$ = "cosine"
else
    metricStr$ = "euclidean"
endif

# ---- ORIGINAL STATS ----
selectObject: origSound
dur = Get total duration
sr  = Get sampling frequency

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== SSM Morph Composer v1.4 ==="
appendInfoLine: "Input:   ", origName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Mode:    ", modeStr$
appendInfoLine: "Metric:  ", metricStr$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================
appendInfoLine: "[0/5] Detecting Python dependencies..."

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

# v1.3: transformation seed -- -1 means "same as navigation seed"
if transformation_seed < 0
    effTransformSeed = seed
else
    effTransformSeed = transformation_seed
endif

# v1.2: reset before probing -- the OS-discovery guess must not
# survive if every candidate fails the dependency probe
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

# ===========================================================================
# Stage 1 — Segment into events
# ===========================================================================
appendInfoLine: "[1/5] Segmenting events..."

# v1.4: choose one real representative channel for analysis. A mono average can
# cancel anti-phase stereo and can make both segmentation and SSM features see
# silence where the multichannel source is actually strong.
analysisChannel = 1
analysisChannelRms = 0
if isMultichannel
    bestRms = -1
    for iCh from 1 to nChannels
        selectObject: origSound
        chProbe = Extract one channel: iCh
        chRms = Get root-mean-square: 0, 0
        if chRms > bestRms
            bestRms = chRms
            analysisChannel = iCh
            analysisChannelRms = chRms
        endif
        removeObject: chProbe
    endfor
    selectObject: origSound
    analysisSound = Extract one channel: analysisChannel
else
    selectObject: origSound
    Copy: "ssm_analysis"
    analysisSound = selected("Sound")
    analysisChannelRms = Get root-mean-square: 0, 0
endif
appendInfoLine: "  Analysis channel: ", analysisChannel, " (RMS ", fixed$(analysisChannelRms, 5), ")"

selectObject: analysisSound
tg = To TextGrid (silences): 100, 0, silence_threshold_dB,
    ... min_silent_interval_s, min_sounding_interval_s, "silent", "sounding"

nInt    = Get number of intervals: 1
nEvents = 0

for iInt from 1 to nInt
    selectObject: tg
    lab$ = Get label of interval: 1, iInt
    if lab$ = "sounding"
        evS = Get start time of interval: 1, iInt
        evE = Get end time of interval:   1, iInt
        if evE - evS >= min_sounding_interval_s
            nEvents = nEvents + 1
            evStart_'nEvents' = evS
            evEnd_'nEvents'   = evE
        endif
    endif
endfor

removeObject: tg
appendInfoLine: "  Events: ", nEvents

if nEvents < 4
    # v1.3: guarantee exactly four proportional events -- the old
    # 0.25 s grid returned 0 events for inputs under 0.25 s and
    # still fewer than four for inputs under 1 s, defeating the
    # fallback's own purpose. A four-part split makes every
    # positive-duration sound navigable.
    appendInfoLine: "  Warning: fewer than 4 events — four-part fallback grid"
    nEvents = 4
    for iEv from 1 to 4
        evStart_'iEv' = (iEv - 1) * dur / 4
        evEnd_'iEv'   = iEv * dur / 4
    endfor
    appendInfoLine: "  Grid events: ", nEvents
endif

# ===========================================================================
# Stage 2 — Export events CSV + audio patches
# ===========================================================================
appendInfoLine: "[2/5] Exporting events and patches..."

writeFileLine: eventsCSV$, "event_index,start_time,end_time,duration"

for iEv from 1 to nEvents
    t1 = evStart_'iEv'
    t2 = evEnd_'iEv'
    appendFileLine: eventsCSV$,
        ... string$(iEv - 1) + "," +
        ... fixed$(t1, 6) + "," +
        ... fixed$(t2, 6) + "," +
        ... fixed$(t2 - t1, 6)
endfor

for iEv from 1 to nEvents
    t1 = evStart_'iEv'
    t2 = evEnd_'iEv'
    selectObject: analysisSound
    patch = Extract part: t1, t2, "rectangular", 1, "no"
    selectObject: patch
    Save as WAV file: patchDir$ + patchPrefix$ + string$(iEv - 1) + ".wav"
    removeObject: patch
endfor
removeObject: analysisSound

appendInfoLine: "  Wrote: ", nEvents, " events + patches from channel ", analysisChannel

# ===========================================================================
# Stage 3 — Run Python engine
# ===========================================================================
appendInfoLine: "[3/5] Running Python SSM engine..."

needSsmPanels = draw_SSM and draw_visualization
ssmTextArgs$ = ""
if needSsmPanels
    ssmTextArgs$ = " --ssm_orig_txt """ + ssmOrigTxtJ$ + """" +
        ... " --ssm_mod_txt """ + ssmModTxtJ$ + """"
endif

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + eventsCSVJ$ + """"
    ... + " """ + planCSVJ$ + """"
    ... + " """ + statsTxtJ$ + """"
    ... + " --patch_dir """    + patchDirJ$ + """"
    ... + " --mode "           + modeStr$
    ... + " --metric "         + metricStr$
    ... + " --output_events "  + string$(output_events)
    ... + " --temperature "    + fixed$(temperature, 4)
    ... + " --tabu_length "    + string$(tabu_length)
    ... + " --seed "           + string$(seed)
    ... + " --teleport_prob "  + fixed$(teleport_probability, 4)
    ... + " --visit_lambda "   + fixed$(visit_penalty, 4)
    ... + " --transform_amount " + fixed$(transform_amount, 4)
    ... + " --blur_sigma "     + fixed$(blur_sigma, 4)
    ... + " --sharpen_gamma "  + fixed$(sharpen_gamma, 4)
    ... + " --diffusion_alpha " + fixed$(diffusion_alpha, 4)
    ... + " --diffusion_steps " + string$(diffusion_steps)
    ... + " --motif_boost "    + fixed$(motif_boost, 4)
    ... + " --warp_amplitude " + fixed$(warp_amplitude, 4)
    ... + " --transform_seed " + string$(effTransformSeed)
    ... + " --patch_prefix "   + patchPrefix$ + ssmTextArgs$

# v1.2: capture stdout+stderr -- on failure the tail is shown
runSystem_nocheck: pythonCall$ + " > """ + runLogJ$ + """ 2>&1"

if not fileReadable(planCSV$)
    errTail$ = ""
    if fileReadable(runLog$)
        errTail$ = readFile$(runLog$)
        if length(errTail$) > 1200
            errTail$ = "..." + right$(errTail$, 1200)
        endif
    endif
    @cleanUpTempFiles
    exitScript: "Python engine failed — plan CSV not found." + newline$ + newline$ + "Engine output:" + newline$ + errTail$
endif

appendInfoLine: "  Engine complete."

# ===========================================================================
# Stage 4 — Read plan + reconstruct audio
# ===========================================================================
appendInfoLine: "[4/5] Reconstructing..."

Read Strings from raw text file: planCSV$
planStrings = selected("Strings")
nPlanLines  = Get number of strings

nPlan = 0
for iLine from 2 to nPlanLines
    selectObject: planStrings
    rowStr$ = Get string: iLine
    rowStr$ = replace$(rowStr$, " ", "", 0)
    if rowStr$ <> ""
        cp    = index(rowStr$, ",")
        evIdx = number(mid$(rowStr$, cp + 1, length(rowStr$)))
        nPlan = nPlan + 1
        planArr[nPlan] = evIdx + 1
    endif
endfor
removeObject: planStrings

appendInfoLine: "  Plan: ", nPlan, " steps"

crossfade_s  = crossfade_ms / 1000
output_name$ = origName$ + "_SSMComposer"
chunkIds#    = zero#(nPlan)
minChunkDur  = 1e9

for iRow from 1 to nPlan
    evIdx = planArr[iRow]
    if evIdx < 1
        evIdx = 1
    endif
    if evIdx > nEvents
        evIdx = nEvents
    endif
    t1 = evStart_'evIdx'
    t2 = evEnd_'evIdx'
    selectObject: origSound
    chunk    = Extract part: t1, t2, "rectangular", 1, "no"
    chunkDur = Get total duration
    if chunkDur < minChunkDur
        minChunkDur = chunkDur
    endif
    chunkIds#[iRow] = chunk
endfor

# v1.2: TRUE overlapped crossfades. The old per-chunk fade +
# plain Concatenate produced faded butt joints -- the events
# never actually overlapped. Overlap is clamped to 45% of the
# shortest chunk so no event is consumed entirely by its fades.
xfadeEff = min(crossfade_s, 0.45 * minChunkDur)
selectObject: chunkIds#[1]
for iRow from 2 to nPlan
    plusObject: chunkIds#[iRow]
endfor
if nPlan > 1 and xfadeEff > 0.0005
    Concatenate with overlap: xfadeEff
else
    Concatenate
endif
resultSound = selected("Sound")
Rename: output_name$
# v1.3: the engine's planned_event_duration ignores the overlaps;
# report the real length of the crossfaded audio
selectObject: resultSound
actualOutputDur = Get total duration

for iRow from 1 to nPlan
    removeObject: chunkIds#[iRow]
endfor

# ---- Read stats ----
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

nEvStat$    = "?"
modeStat$   = "?"
metricStat$ = "?"
tempStat$   = "?"
tabuStat$   = "?"
nPlanStat$  = "?"
plannedDurStat$ = "?"
entrStat$   = "?"
diagStat$   = "?"
uniqueStat$ = "?"
repStat$    = "?"
froStat$    = "?"
psOrigStat$ = "?"
psModStat$  = "?"
covStat$    = "?"
telStat$    = "?"
chronoStat$ = "?"
runStat$    = "?"
normEntrStat$ = "?"
featDimsStat$ = "?"
motifOrigStat$ = "?"
motifModStat$ = "?"
motifContrastOrigStat$ = "?"
motifContrastModStat$ = "?"

if fileReadable(statsTxt$)
    statsText$ = readFile$(statsTxt$)
    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode="
    modeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "metric="
    metricStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "temperature="
    tempStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "tabu_length="
    tabuStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "plan_length="
    nPlanStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "planned_event_duration="
    plannedDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "path_entropy="
    entrStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "diag_energy="
    diagStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "unique_events="
    uniqueStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "repetition_rate="
    repStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "frobenius_change="
    froStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "path_sim_orig="
    psOrigStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "path_sim_mod="
    psModStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "coverage="
    covStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "teleport_rate="
    telStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_chrono_jump="
    chronoStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_run_length="
    runStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "normalized_path_entropy="
    normEntrStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "effective_feature_dims="
    featDimsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "motif_band_peak_orig="
    motifOrigStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "motif_band_peak_mod="
    motifModStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "motif_band_contrast_orig="
    motifContrastOrigStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "motif_band_contrast_mod="
    motifContrastModStat$ = parseStatLine.result$
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Drawing visualization..."

    Erase all
    if needSsmPanels
        Select outer viewport: 0, 8, 0, 9.1
    else
        Select outer viewport: 0, 8, 0, 8
    endif

    # === Title (v1.2: house geometry) ===
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##SSM Morph Composer v1.4##"
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.24, "half",
        ... origName$ + " | " + presetName$ + " | " + modeStr$ + " | " + metricStr$
        ... + " | events=" + nEvStat$ + " | plan=" + nPlanStat$

    # === SSM matrices — the ENGINE'S REAL matrices (v1.2) ===
    # The old display rebuilt a different MFCC-based SSM (always
    # cosine) and painted an unmodified COPY as "after transform".
    # Both panels now read the matrices the engine actually used.
    if needSsmPanels and fileReadable(ssmOrigTxt$) and fileReadable(ssmModTxt$)

        Read Matrix from raw text file: ssmOrigTxt$
        ssmMatOrig = selected("Matrix")
        Read Matrix from raw text file: ssmModTxt$
        ssmMatMod = selected("Matrix")

        # v1.4: one fixed display mapping for before/after. Independent min-max
        # stretches made a small transform look as strong as a large one.
        Select outer viewport: 0, 4, 0.6, 2.5
        selectObject: ssmMatOrig
        Paint cells: 0, 0, 0, 0, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "SSM original (" + metricStr$ + ") [0..1 engine scale]"
        Text bottom: "yes", "Event"
        Text left: "yes", "Event"

        Select outer viewport: 4, 8, 0.6, 2.5
        selectObject: ssmMatMod
        Paint cells: 0, 0, 0, 0, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "SSM after " + modeStr$ + " (amount " + fixed$(transform_amount, 2) + ") [same 0..1 scale]"
        Text bottom: "yes", "Event"

        removeObject: ssmMatOrig, ssmMatMod

        ssmShift = 2.0
    else
        ssmShift = 0.0
    endif

    # Representative real channel for comparable waveform/spectrogram panels.
    selectObject: origSound
    if nChannels > 1
        vizOrig = Extract one channel: analysisChannel
    else
        Copy: "ssm_viz_orig"
        vizOrig = selected("Sound")
    endif
    selectObject: resultSound
    if nChannels > 1
        vizOut = Extract one channel: analysisChannel
    else
        Copy: "ssm_viz_out"
        vizOut = selected("Sound")
    endif
    selectObject: vizOrig
    peakOrig = Get absolute extremum: 0, 0, "none"
    selectObject: vizOut
    peakOut = Get absolute extremum: 0, 0, "none"
    wavePeak = 1.05 * max(peakOrig, peakOut)
    if wavePeak < 0.000001
        wavePeak = 1
    endif
    specCeil = min(8000, sr / 2)

    # === Original waveform + event boundaries ===
    Select outer viewport: 0, 8, 0.6 + ssmShift, 1.45 + ssmShift
    Select inner viewport: 0.6, 7.7, 0.65 + ssmShift, 1.40 + ssmShift
    selectObject: vizOrig
    Colour: "{0.5, 0.5, 0.55}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Axes: 0, dur, -wavePeak, wavePeak
    Colour: "{0.75, 0.35, 0.35}"
    Line width: 1
    for iEv from 1 to nEvents
        evT = evStart_'iEv'
        if evT > 0 and evT < dur
            Draw line: evT, -0.9 * wavePeak, evT, 0.9 * wavePeak
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original ch" + string$(analysisChannel)
    Text top: "no", fixed$(dur, 2) + " s  |  " + string$(nEvents) + " events"

    # === Output waveform ===
    Select outer viewport: 0, 8, 1.45 + ssmShift, 2.3 + ssmShift
    Select inner viewport: 0.6, 7.7, 1.50 + ssmShift, 2.25 + ssmShift
    selectObject: vizOut
    Colour: "{0.2, 0.5, 0.75}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output ch" + string$(analysisChannel)
    Text bottom: "yes", "Time (s)"
    Text top: "no", fixed$(actualOutputDur, 2) + " s (audio)  |  " + nPlanStat$ + " events  (" + modeStr$ + ")"

    # === Original spectrogram ===
    Select outer viewport: 0, 8, 2.4 + ssmShift, 3.6 + ssmShift
    Select inner viewport: 0.6, 7.7, 2.50 + ssmShift, 3.50 + ssmShift
    selectObject: vizOrig
    To Spectrogram: 0.005, specCeil, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, specCeil, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original spectrogram ch" + string$(analysisChannel) + " (auto-levelled)"
    removeObject: specOrig

    # === Output spectrogram ===
    Select outer viewport: 0, 8, 3.6 + ssmShift, 4.8 + ssmShift
    Select inner viewport: 0.6, 7.7, 3.70 + ssmShift, 4.70 + ssmShift
    selectObject: vizOut
    To Spectrogram: 0.005, specCeil, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, specCeil, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram ch" + string$(analysisChannel) + " (auto-levelled)"
    removeObject: specOut

    # === Event path line ===
    Select outer viewport: 0, 8, 4.9 + ssmShift, 5.9 + ssmShift
    Select inner viewport: 0.6, 7.7, 5.00 + ssmShift, 5.80 + ssmShift
    Axes: 0, nPlan, 0, nEvents
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, nPlan, 0, nEvents
    Colour: "{0.2, 0.5, 0.75}"
    Line width: 1
    for iRow from 2 to nPlan
        Draw line: iRow - 2, planArr[iRow - 1] - 1, iRow - 1, planArr[iRow] - 1
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Event"
    Text bottom: "yes", "Step"
    Text top: "no", "Event path  (entropy=" + entrStat$ + ", norm=" + normEntrStat$ + " | motif contrast " + motifContrastOrigStat$ + "->" + motifContrastModStat$ + ")"

    # === Summary panel ===
    Select outer viewport: 0, 8, 6.0 + ssmShift, 7.0 + ssmShift
    Select inner viewport: 0.6, 7.7, 6.10 + ssmShift, 6.90 + ssmShift
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.86, "half", "##Run statistics##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.64, "half",
        ... "Events: " + nEvStat$ + " | Features: " + featDimsStat$ + "/5 | Analysis ch: " + string$(analysisChannel) +
        ... " | Mode: " + modeStat$ + " | Metric: " + metricStat$ + " | Temp: " + tempStat$
    Text: 0.02, "left", 0.43, "half",
        ... "Plan: " + nPlanStat$ + " | Output: " + fixed$(actualOutputDur, 2) + " s (planned " + plannedDurStat$ + ")" +
        ... " | Unique: " + uniqueStat$ + " | Coverage: " + covStat$
    Text: 0.02, "left", 0.22, "half",
        ... "Entropy: " + entrStat$ + " (norm " + normEntrStat$ + ") | Frobenius: " + froStat$ +
        ... " | Path sim orig/mod: " + psOrigStat$ + "/" + psModStat$
    Text: 0.02, "left", 0.04, "half",
        ... "Motif contrast: " + motifContrastOrigStat$ + "->" + motifContrastModStat$ + " | Teleports: " + telStat$ +
        ... " | Chrono jump: " + chronoStat$ + " | Runs: " + runStat$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: vizOrig, vizOut

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "Visualization skipped."
endif

# ---- FINAL CLEANUP ----
@cleanUpTempFiles

# ---- Final summary ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:       ", output_name$
appendInfoLine: "Preset:       ", presetName$
appendInfoLine: "Mode:         ", modeStat$
appendInfoLine: "Events:       ", nEvStat$, " | Analysis ch: ", analysisChannel, " | Features: ", featDimsStat$, "/5"
appendInfoLine: "Plan:         ", nPlanStat$, " steps"
appendInfoLine: "Output dur:   ", fixed$(actualOutputDur, 2), " s (audio; planned ", plannedDurStat$, " s)"
appendInfoLine: "Path entropy: ", entrStat$, " (normalized ", normEntrStat$, ")"
appendInfoLine: "Local diag:   ", diagStat$ + " | Motif contrast: " + motifContrastOrigStat$ + " -> " + motifContrastModStat$
appendInfoLine: "Unique evts:  ", uniqueStat$
appendInfoLine: "Repetition:   ", repStat$
appendInfoLine: "Frobenius Δ:  ", froStat$
appendInfoLine: "Path sim:     ", psOrigStat$, " (orig) / ", psModStat$, " (mod)"
appendInfoLine: "Coverage:     ", covStat$, " | Teleports: ", telStat$
appendInfoLine: "Chrono jump:  ", chronoStat$, " | Mean run: ", runStat$

selectObject: resultSound

if play_result
    Play
endif
