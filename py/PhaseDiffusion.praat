# ============================================================
# Praat AudioTools - PhaseDiffusion.praat
# (filename preserved for distribution compatibility)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 6.3 (2026) — DSP correctness + transient/AE projection reliability
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent Spectral Diffusion — front-end for phase_diffusion_ai.py.
#   Trains a small NumpyAutoencoder on the input signal's own log-Mel
#   patches, then drives spectral processing via the learned latent
#   space. Three model heads:
#
#     AE-Weighted   — Random phase + per-bin magnitude attenuation
#                     guided by AE-learned per-band coherence. Bands
#                     the AE reconstructed well (interpreted as more
#                     structured/tonal) get more attenuation; bands
#                     it failed on (noisy/transient) are protected.
#                     CLI: --model pca (historical name; no SVD inside).
#
#     AR Smear      — AR(1) per-bin coefficient drives IIR magnitude
#                     decay, gated by AE coherence. Bins that are
#                     both sustained AND well-reconstructed by the
#                     AE get the heaviest smear. Random phase.
#                     CLI: --model ar.
#
#     Latent        — Each event's Z is walked toward its cluster
#                     centroid via temperature-annealed gradient
#                     descent, then decoded back to a mel patch whose
#                     energy profile shapes the magnitude envelope
#                     for that event's window. Result: each event
#                     sounds like a blend of acoustically similar
#                     events from the same recording.
#                     CLI: --model latent.
#
#   The filename PhaseDiffusion.praat is preserved for distribution
#   compatibility (existing users may have it wired into workflows);
#   internal naming throughout the form, info output, visualisation,
#   and summary uses the more accurate "Latent Spectral Diffusion".
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v6.3:
#   DSP correctness / reliability update (Python backend + front-end sync):
#     - Preserve_transients now uses true TEMPORAL frame-to-frame spectral
#       flux. v6.2 accidentally measured adjacent FFT-bin differences.
#     - Protected transient frames also retain more of their original phase,
#       not only more of their magnitude structure.
#     - AE mel-band error -> FFT-bin mapping is coverage-normalised; flat
#       profiles map to a neutral weight instead of filterbank geometry.
#     - Latent decoded mel envelope uses the same coverage-normalised mapping.
#     - AR(1) fit now uses true adjacent frame pairs when long files are
#       subsampled for efficiency.
#     - Silence / identical latent vectors and very short files no longer
#       crash K-means/event analysis.
#     - SciPy dependency removed; onset thresholding is NumPy-only.
#     - Spectral blur is edge-preserving and safely capped for extreme values.
#     - Multichannel analysis uses the strongest-RMS channel instead of always
#       channel 1; all channels are still processed independently.
#     - DC/Nyquist phase bins are preserved; latent exponentiation guarded
#       against overflow.
#   Praat:
#     - Custom odd Window_size is rounded up to even, matching the backend.
#     - Hop_size clamp now stays integer.
#     - Dependency message corrected to numpy + soundfile.
#     - Visualization mechanism text updated to describe the active model.
#
# Changelog v6.2:
#   Secondary knobs made live/consistent (audio change; see
#   phase_diffusion_ai.py header for detail):
#     - Temperature now audibly affects the Latent model (was near-inert);
#       still Latent-only. Form + info gate it as such.
#     - Mag_smear is now one consistent spectral blur across all three
#       models (was an exponent / weak multiplier / unused). Form labels it
#       as an all-model blur.
#     - diffusion_amount unchanged (already a clean master dial).
#
# Changelog v6.1:
#   Backend correctness refinement (audio change for AE-Weighted / AR
#   Smear via phase_diffusion_ai.py; see its header for detail):
#     - Stage 4 now measures per-mel-band reconstruction error in RAW
#       log-mel space, not z-scored space. v6.0 kept the per-band axis
#       but evaluated error after per-dimension normalization, which
#       equalized band variances and left the weights nearly flat (the
#       visible contrast came from min-max stretching). Raw-space error
#       makes the AE coherence weights genuinely frequency-discriminative.
#     - Latent model: fixed per-frame event lookup so trailing frames use
#       the last event's envelope instead of event 0.
#     - Removed dead Python parameters (no behaviour change).
#   Praat-side: version strings synced to v6.1; Panel D-right label
#   "(v6.0 honest)" -> "(v6.1 raw-space)". No Praat behaviour change.
#
# Changelog v6.0:
#   AUDIO CHANGE (via Python backend):
#     Stage 5a in phase_diffusion_ai.py now uses genuine per-event
#     per-mel-band reconstruction error to build the per-FFT-bin
#     coherence weights. v5.x broadcast a single scalar per-event
#     error uniformly across all mel bands before projecting to FFT
#     bins, so the frequency profile of the weights came entirely
#     from filterbank overlap geometry rather than from the AE's
#     per-band performance. v6.0 keeps the per-band axis intact, so
#     the AE-Weighted (pca) and AR Smear (ar) models now produce
#     outputs whose frequency-dependent character genuinely reflects
#     which bands of THIS recording the AE could compress well. The
#     Latent model is unaffected by this change (its envelopes come
#     from the decoded Z, not from ae_weights).
#
#   FRAMING (Praat-side):
#     - Form title, info header, viz title: "AI Phase Diffusion v5.1"
#       -> "Latent Spectral Diffusion v6.0". The historical name was
#       inaccurate ("PCA"/"AR" models also modify magnitudes, not
#       just phase; "AI" is correct since there's a real autoencoder
#       but "Phase" was a misnomer).
#     - Model option "Phase PCA" -> "AE-Weighted" (no SVD anywhere
#       in this model; the historical PCA name is retained ONLY as
#       the Python --model CLI argument for backward compatibility).
#     - Model option "Phase AR" -> "AR Smear" (the AR model fits real
#       AR(1) coefficients per bin; the "Phase" qualifier was wrong).
#     - Model option "Latent" — already accurate, unchanged.
#     - modelLabel$ values updated accordingly.
#     - Python CLI args unchanged: --model pca/ar/latent. Anyone
#       calling phase_diffusion_ai.py directly with the old names
#       continues to work.
#
#   FORM:
#     - Dropped 5 decorative `comment === ... ===` section dividers.
#       Form went from 20 effective rows (15 fields + 5 comments) to 15.
#
#   PRAAT-SIDE POLISH:
#     - Inline `if/then/else fi` strings in appendInfoLine and viz
#       Text() pre-computed into transStr$ / transStrViz$. Per gotcha
#       #17, inline ternary in script-level string concatenation is
#       unreliable across Praat versions (works in Formula context
#       but not always in appendInfoLine concatenation). Fixes lines
#       386 and 740 v5.1.
#     - Spectrogram time_step in viz: 0.002 -> 0.01 (5x faster, still
#       sharp at panel size). 0.002 produced ~25,000 time bins for a
#       5-second input; 0.01 gives ~500 bins, ~1 pixel per bin at
#       the panel scale.
#     - Title font size 13 -> 12 (suite standard).
#     - Output filename suffix: was "_phasediff" regardless of run
#       choice; now "_phasediff_<preset>_<modelName>" so multiple
#       runs with different presets/models don't collide.
#
#   VISUALISATION:
#     - Rewritten from 8x7.75 custom (6 sub-panels: title + 2
#       waveforms + 2 spectrograms + intensity + AE info + parameter
#       summary) to suite 8x8 standard. All diagnostic content
#       preserved, reorganised:
#         Title bar (suite light) + metadata subtitle
#         Panel A (left, headline): original spectrogram
#         Panel B (right, headline): diffused spectrogram (the
#           signature side-by-side comparison)
#         Panel C: original vs result waveforms overlaid on shared
#           y-axis (gray = original, model-coloured = result)
#         Panel D: intensity envelopes overlaid + AE info
#           (intensity left half, AE info text right half)
#         Panel E: light-grey summary bar with preset, all model
#           and AE parameters, signal stats (3 lines)
#
# Changelog v5.1:
#   - Unified cross-platform paths
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

pythonScript$ = pluginDir$ + "py/phase_diffusion_ai.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/phase_diffusion_ai.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: phase_diffusion_ai.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_phasediff_input.wav"
tempOutput$  = temporaryDirectory$ + "/temp_phasediff_output.wav"
statusFile$  = temporaryDirectory$ + "/temp_phasediff_status.ok"
probePy$     = temporaryDirectory$ + "/temp_phasediff_probe.py"
probeMarker$ = temporaryDirectory$ + "/temp_phasediff_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempOutputJ$   = replace_regex$(tempOutput$, "\\", "/", 0)
statusFileJ$   = replace_regex$(statusFile$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(statusFile$)
        deleteFile: statusFile$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Latent Spectral Diffusion v6.3
    optionmenu Preset: 1
        option Custom
        option Veil
        option Spectral Fog
        option Ambient Wash
        option Drone Cloud
        option Stutter Field
        option Formant Ghost
        option Phase Plasma
        option Void
        option Latent Drift
        option Latent Morph
        option Latent Deep
    real    Diffusion_amount 0.70
    integer Diffusion_steps  30
    integer Window_size      8192
    integer Hop_size         2048
    real    Mag_smear        1.0
    comment (Mag_smear: spectral blur — all models; strongest on AE-Weighted / AR Smear)
    optionmenu Model: 1
        option AE-Weighted
        option AR Smear
        option Latent
    integer Latent_size   8
    integer Train_steps   150
    integer N_clusters    4
    real    Temperature   1.0
    comment (Temperature: Latent model only — ignored by AE-Weighted / AR Smear)
    boolean Preserve_transients 1
    boolean Draw_visualization  1
    boolean Play_result         1
    boolean Debug               0
endform

# ---- PRESET APPLICATION ----
if preset = 2
    diffusion_amount    = 0.30
    diffusion_steps     = 20
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 0.4
    model               = 1
    latent_size         = 6
    train_steps         = 100
    n_clusters          = 3
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "Veil"
elsif preset = 3
    diffusion_amount    = 0.60
    diffusion_steps     = 30
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 1.0
    model               = 1
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "SpectralFog"
elsif preset = 4
    diffusion_amount    = 0.80
    diffusion_steps     = 30
    window_size         = 16384
    hop_size            = 4096
    mag_smear           = 1.2
    model               = 1
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "AmbientWash"
elsif preset = 5
    diffusion_amount    = 0.95
    diffusion_steps     = 30
    window_size         = 32768
    hop_size            = 8192
    mag_smear           = 1.8
    model               = 2
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 0
    presetName$         = "DroneCloud"
elsif preset = 6
    diffusion_amount    = 0.70
    diffusion_steps     = 20
    window_size         = 2048
    hop_size            = 512
    mag_smear           = 0.8
    model               = 1
    latent_size         = 6
    train_steps         = 100
    n_clusters          = 3
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "StutterField"
elsif preset = 7
    diffusion_amount    = 0.55
    diffusion_steps     = 30
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 2.0
    model               = 2
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "FormantGhost"
elsif preset = 8
    diffusion_amount    = 1.00
    diffusion_steps     = 30
    window_size         = 16384
    hop_size            = 4096
    mag_smear           = 1.5
    model               = 1
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 0
    presetName$         = "PhasePlasma"
elsif preset = 9
    diffusion_amount    = 1.00
    diffusion_steps     = 50
    window_size         = 32768
    hop_size            = 8192
    mag_smear           = 2.0
    model               = 2
    latent_size         = 12
    train_steps         = 200
    n_clusters          = 6
    temperature         = 2.0
    preserve_transients = 0
    presetName$         = "Void"
elsif preset = 10
    diffusion_amount    = 0.50
    diffusion_steps     = 20
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 1.0
    model               = 3
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 0.5
    preserve_transients = 1
    presetName$         = "LatentDrift"
elsif preset = 11
    diffusion_amount    = 0.75
    diffusion_steps     = 40
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 1.0
    model               = 3
    latent_size         = 8
    train_steps         = 200
    n_clusters          = 5
    temperature         = 1.5
    preserve_transients = 1
    presetName$         = "LatentMorph"
elsif preset = 12
    diffusion_amount    = 1.00
    diffusion_steps     = 60
    window_size         = 16384
    hop_size            = 4096
    mag_smear           = 1.2
    model               = 3
    latent_size         = 12
    train_steps         = 250
    n_clusters          = 6
    temperature         = 3.0
    preserve_transients = 0
    presetName$         = "LatentDeep"
else
    presetName$ = "Custom"
endif

# ---- CLAMP ----
if diffusion_amount < 0
    diffusion_amount = 0
endif
if diffusion_amount > 1
    diffusion_amount = 1
endif
if diffusion_steps < 1
    diffusion_steps = 1
endif
if diffusion_steps > 200
    diffusion_steps = 200
endif
if window_size < 256
    window_size = 256
endif
# Backend keeps an explicit Nyquist bin; round custom odd windows up to even.
if window_size <> 2 * floor(window_size / 2)
    window_size = window_size + 1
endif
if hop_size < 1
    hop_size = 1
endif
if hop_size > floor(window_size / 2)
    hop_size = floor(window_size / 2)
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif
if train_steps < 10
    train_steps = 10
endif
if train_steps > 500
    train_steps = 500
endif
if n_clusters < 2
    n_clusters = 2
endif
if n_clusters > 8
    n_clusters = 8
endif
if temperature < 0.05
    temperature = 0.05
endif

# ---- MODEL LABELS ----
# v6.0: model 1 ("AE-Weighted") and model 2 ("AR Smear") renamed from
# v5.1's "Phase PCA" / "Phase AR". The Python --model CLI args (modelName$)
# are unchanged ("pca", "ar", "latent") for backward compatibility with
# anyone calling phase_diffusion_ai.py directly.
if model = 1
    modelName$  = "pca"
    modelLabel$ = "AE-Weighted"
    modelCol$   = "{0.2, 0.5, 0.8}"
elsif model = 2
    modelName$  = "ar"
    modelLabel$ = "AR Smear"
    modelCol$   = "{0.7, 0.3, 0.5}"
elsif model = 3
    modelName$  = "latent"
    modelLabel$ = "Latent"
    modelCol$   = "{0.2, 0.65, 0.45}"
endif

# ---- STATS ----
selectObject: inputSound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0
winMs     = window_size / sr * 1000

# ---- PRE-COMPUTED INLINE STRINGS (gotcha #17) ----
# v6.0: inline `if/then/else fi` in script-level appendInfoLine and Text()
# concatenation is unreliable across Praat versions (works in Formula
# context but not always in info-line / Text concatenation). Pre-compute
# the string into a variable.
if preserve_transients
    transStr$    = "YES"
    transStrViz$ = "protected"
else
    transStr$    = "NO"
    transStrViz$ = "free"
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Latent Spectral Diffusion v6.3 ==="
appendInfoLine: "Input:    ", inputName$
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Model:    ", modelLabel$
appendInfoLine: "Duration: ", fixed$(dur, 2), " s  |  SR: ", sr, " Hz  |  Ch: ", nChannels
appendInfoLine: ""
appendInfoLine: "-- Diffusion -------------------------------------------"
appendInfoLine: "  diffusion_amount : ", fixed$(diffusion_amount, 3)
appendInfoLine: "  diffusion_steps  : ", diffusion_steps, "  (latent: gradient steps)"
appendInfoLine: "  window_size      : ", window_size, " smp (", fixed$(winMs, 1), " ms)"
appendInfoLine: "  hop_size         : ", hop_size, " smp"
appendInfoLine: "  mag_smear        : ", fixed$(mag_smear, 2), "  (spectral blur, all models)"
appendInfoLine: "  preserve_transients: ", transStr$, "  (temporal spectral-flux protection)"
appendInfoLine: "-- Autoencoder -----------------------------------------"
appendInfoLine: "  latent_size : ", latent_size
appendInfoLine: "  train_steps : ", train_steps
appendInfoLine: "  n_clusters  : ", n_clusters
if modelName$ = "latent"
    appendInfoLine: "  temperature : ", fixed$(temperature, 3), "  (active — Latent model)"
else
    appendInfoLine: "  temperature : ", fixed$(temperature, 3), "  (ignored — Latent model only)"
endif
appendInfoLine: "--------------------------------------------------------"
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/4] Detecting Python dependencies..."

pyCode$ = "import sys" + newline$
pyCode$ = pyCode$ + "try:" + newline$
pyCode$ = pyCode$ + "    import numpy, soundfile" + newline$
pyCode$ = pyCode$ + "    with open('" + probeMarkerJ$ + "', 'w') as f:" + newline$
pyCode$ = pyCode$ + "        f.write('ok')" + newline$
pyCode$ = pyCode$ + "except Exception as e:" + newline$
pyCode$ = pyCode$ + "    print('Missing dependencies:', e)" + newline$
writeFile: probePy$, pyCode$

probeCmd$ = pythonCmd$ + " """ + probePyJ$ + """"
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy soundfile"
endif

deleteFile: probeMarker$
deleteFile: probePy$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Export Source Audio
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "[2/4] Exporting input WAV..."
selectObject: inputSound
Save as WAV file: tempInput$

# ===========================================================================
# Stage 3 — Call Python Engine
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "[3/4] Running Latent Spectral Diffusion v6.3..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempInputJ$  + """"
    ... + " """ + tempOutputJ$ + """"
    ... + " --model "              + modelName$
    ... + " --diffusion-amount "   + fixed$(diffusion_amount, 6)
    ... + " --diffusion-steps "    + string$(diffusion_steps)
    ... + " --window-size "        + string$(window_size)
    ... + " --hop-size "           + string$(hop_size)
    ... + " --mag-smear "          + fixed$(mag_smear, 6)
    ... + " --latent-size "        + string$(latent_size)
    ... + " --train-steps "        + string$(train_steps)
    ... + " --n-clusters "         + string$(n_clusters)
    ... + " --temperature "        + fixed$(temperature, 6)
    ... + " --seed 42"
    ... + " --status-file """ + statusFileJ$ + """"

if preserve_transients
    pythonCall$ = pythonCall$ + " --preserve-transients"
endif
if debug
    pythonCall$ = pythonCall$ + " --debug"
endif

appendInfoLine: "-- Python command --------------------------------------"
appendInfoLine: "  ", pythonCall$
appendInfoLine: "--------------------------------------------------------"

runSystem_nocheck: pythonCall$

# ---- CHECK SUCCESS ----
if not fileReadable(statusFile$)
    @cleanUpTempFiles
    exitScript: "Python Latent Spectral Diffusion engine failed." + newline$ + "Check terminal for error details."
endif

appendInfoLine: ""
appendInfoLine: "**** PYTHON OK ****"

# ===========================================================================
# Stage 4 — Import Result
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "[4/4] Importing result..."
if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Output WAV not found: " + tempOutput$
endif

Read from file: tempOutput$
resultSound = selected("Sound")
# v6.0: output filename now includes preset and model name suffix
# so multiple runs don't collide. modelName$ is the Python CLI value
# ("pca"/"ar"/"latent") — compact and unambiguous.
resultName$ = inputName$ + "_phasediff_" + presetName$ + "_" + modelName$
Rename: resultName$
appendInfoLine: "  Result: ", resultName$

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration

###############################################################################
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Panel A: original spectrogram (left, headline)
# Panel B: diffused spectrogram (right, headline)
# Panel C: waveform comparison (gray = orig, model-coloured = result)
# Panel D: intensity envelopes + AE/latent info text
# Panel E: light-grey summary stats bar
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##LATENT SPECTRAL DIFFUSION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... inputName$
        ... + "  |  " + presetName$
        ... + "  |  " + modelLabel$
        ... + "  |  amount " + fixed$(diffusion_amount, 2)
        ... + "  |  win " + string$(window_size) + " (" + fixed$(winMs, 0) + " ms)"
        ... + "  |  hop " + string$(hop_size)
        ... + "  |  latent " + string$(latent_size)
        ... + "  |  clusters " + string$(n_clusters)

    # ----------------------------------------------------------
    # PANEL A: ORIGINAL SPECTROGRAM  (left, headline)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    selectObject: inputSound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    # v6.0: spectrogram time_step 0.002 -> 0.01 (5x faster, still
    # sharp at panel size).
    To Spectrogram: 0.005, 5000, 0.01, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specOrig, tmpOrig

    # ----------------------------------------------------------
    # PANEL B: DIFFUSED SPECTROGRAM  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpDiff = selected("Sound")
    else
        Copy: "tmpDiff"
        tmpDiff = selected("Sound")
    endif
    To Spectrogram: 0.005, 5000, 0.01, 20, "Gaussian"
    specDiff = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specDiff, tmpDiff

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Original spectrogram"
    Text: 6.10, "centre", 7.30, "half", "Diffused spectrogram  (" + modelLabel$ + ")"

    # ----------------------------------------------------------
    # PANEL C: WAVEFORM COMPARISON
    # Gray = original, model-coloured = result. Shared y-axis from
    # the max absolute peak of either signal.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    selectObject: inputSound
    if nChannels > 1
        Extract one channel: 1
        vizOrig = selected("Sound")
    else
        Copy: "viz_orig"
        vizOrig = selected("Sound")
    endif
    selectObject: vizOrig
    oPeak = Get absolute extremum: 0, 0, "None"

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        vizRes = selected("Sound")
    else
        Copy: "viz_res"
        vizRes = selected("Sound")
    endif
    selectObject: vizRes
    rPeak = Get absolute extremum: 0, 0, "None"

    sharedPeak = oPeak
    if rPeak > sharedPeak
        sharedPeak = rPeak
    endif
    if sharedPeak < 0.01
        sharedPeak = 0.01
    endif
    sharedAmp = sharedPeak * 1.15

    Axes: 0, dur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, dur, 0

    # Original (gray) behind
    selectObject: vizOrig
    Colour: "{0.62, 0.62, 0.62}"
    Line width: 1
    Draw: 0, dur, -sharedAmp, sharedAmp, "no", "Curve"

    # Result (model colour) on top
    selectObject: vizRes
    Colour: modelCol$
    Line width: 1
    Draw: 0, dur, -sharedAmp, sharedAmp, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Waveform comparison  (gray = original, colour = diffused)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    removeObject: vizOrig, vizRes

    # ----------------------------------------------------------
    # PANEL D: INTENSITY ENVELOPES + AE INFO TEXT (split halves)
    # Left half: intensity envelope overlay (gray = orig, colour = result)
    # Right half: autoencoder / latent information text
    # ----------------------------------------------------------

    # ===== Panel D-left: intensity envelopes =====
    Select outer viewport: 0, 4.2, 5.62, 6.55
    Select inner viewport: 0.55, 4.00, 5.69, 6.48

    Axes: 0, dur, 30, 90
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, dur, 30, 90

    selectObject: inputSound
    if nChannels > 1
        Extract one channel: 1
        tmpOrigI = selected("Sound")
    else
        Copy: "tmpOrigI"
        tmpOrigI = selected("Sound")
    endif
    To Intensity: 100, 0, "yes"
    intOrig = selected("Intensity")
    selectObject: intOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intOrig, tmpOrigI

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpDiffI = selected("Sound")
    else
        Copy: "tmpDiffI"
        tmpDiffI = selected("Sound")
    endif
    To Intensity: 100, 0, "yes"
    intDiff = selected("Intensity")
    selectObject: intDiff
    Colour: modelCol$
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intDiff, tmpDiffI

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"

    # ===== Panel D-right: AE / latent info text =====
    Select outer viewport: 4.2, 8, 5.62, 6.55
    Select inner viewport: 4.55, 7.75, 5.69, 6.48

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.95, 0.98}", 0, 1, 0, 1

    Font size: 8
    Colour: "Black"
    Text: 0.05, "left", 0.92, "half", "##Autoencoder / Latent##"

    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.78, "half",
        ... "Arch: log-Mel (40) -> hidden -> latent(" + string$(latent_size) + ") -> hidden -> reconstruct"
    Text: 0.05, "left", 0.66, "half",
        ... "Train: " + string$(train_steps) + " steps  |  Adam + denoising + L2  |  leaky ReLU"

    if model = 3
        Colour: "{0.15, 0.55, 0.35}"
        Text: 0.05, "left", 0.50, "half",
            ... "##Latent model active##"
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.38, "half",
            ... "Z -> T-weighted cluster walk -> decode"
        Text: 0.05, "left", 0.26, "half",
            ... "Clusters: " + string$(n_clusters) + "  |  T=" + fixed$(temperature, 2)
            ... + "  |  steps=" + string$(diffusion_steps)
        Text: 0.05, "left", 0.10, "half",
            ... "Decoded mel energy -> coverage-normalised spectral envelope"
    elsif model = 2
        Colour: "{0.55, 0.25, 0.45}"
        Text: 0.05, "left", 0.50, "half",
            ... "##AR Smear + AE coherence##"
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.38, "half",
            ... "a(f)=sum M[t]M[t+1] / sum M[t]^2"
        Text: 0.05, "left", 0.26, "half",
            ... "decay = a(f) * AE-coherence * amount"
        Text: 0.05, "left", 0.10, "half",
            ... "True adjacent frame pairs; temporal-flux transient protection"
    else
        Colour: "{0.30, 0.40, 0.55}"
        Text: 0.05, "left", 0.50, "half",
            ... "##AE-Weighted coherence (v6.3)##"
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.38, "half",
            ... "Raw per-mel-band MSE -> coverage-normalised FFT weights"
        Text: 0.05, "left", 0.26, "half",
            ... "Low MSE -> coherent/tonal -> stronger wet attenuation"
        Text: 0.05, "left", 0.10, "half",
            ... "High MSE -> less attenuation; transients protected in time"
    endif

    Colour: "Black"
    Line width: 1
    Draw rectangle: 0, 1, 0, 1

    # Aligned subtitles above Panel D halves
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.95, "half", "Intensity  (gray = original  |  colour = diffused)"
    Text: 6.10, "centre", 7.95, "half", "AE / latent info"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey, 3 lines)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    rmsRatio = rms_out / (rms_orig + 0.000001)

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + inputName$
        ... + "  |  Model: " + modelLabel$
        ... + "  |  Amount: " + fixed$(diffusion_amount, 2)
        ... + "  |  Steps: " + string$(diffusion_steps)
        ... + "  |  Smear: " + fixed$(mag_smear, 2)
        ... + "  |  Trans: " + transStrViz$

    Text: 0.02, "left", 0.50, "half",
        ... "AE: latent=" + string$(latent_size)
        ... + "  |  train=" + string$(train_steps)
        ... + "  |  clusters=" + string$(n_clusters)
        ... + "  |  T=" + fixed$(temperature, 2)
        ... + "  |  Window: " + string$(window_size) + " (" + fixed$(winMs, 1) + " ms)"
        ... + "  |  Hop: " + string$(hop_size)

    Text: 0.02, "left", 0.18, "half",
        ... "RMS: " + fixed$(rms_orig, 4) + " -> " + fixed$(rms_out, 4)
        ... + "  (" + fixed$(rmsRatio, 2) + "x)"
        ... + "  |  Duration: " + fixed$(dur, 2) + " s"
        ... + "  |  SR: " + string$(sr) + " Hz"
        ... + "  |  Channels: " + string$(nChannels)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
    appendInfoLine: "  Visualization drawn."

else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ---- PLAY ----
if play_result
    selectObject: resultSound
    Play
endif

# ---- CLEANUP ----
@cleanUpTempFiles

# ---- SUMMARY ----
rmsRatio = rms_out / (rms_orig + 0.000001)
appendInfoLine: ""
appendInfoLine: "========================================================"
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "  Output       : ", resultName$
appendInfoLine: "  Preset       : ", presetName$
appendInfoLine: "  Model        : ", modelLabel$, " (--model ", modelName$, ")"
appendInfoLine: "  Amount       : ", fixed$(diffusion_amount, 3)
appendInfoLine: "  Window       : ", window_size, " smp (", fixed$(winMs, 1), " ms)"
appendInfoLine: "  Hop          : ", hop_size
appendInfoLine: "  Steps        : ", diffusion_steps
appendInfoLine: "  Smear        : ", fixed$(mag_smear, 2)
appendInfoLine: "  Transients   : ", transStrViz$
appendInfoLine: "-- Autoencoder -----------------------------------------"
appendInfoLine: "  Latent size  : ", latent_size
appendInfoLine: "  Train steps  : ", train_steps
appendInfoLine: "  Clusters     : ", n_clusters
appendInfoLine: "  Temperature  : ", fixed$(temperature, 3)
appendInfoLine: "-- Signal ----------------------------------------------"
appendInfoLine: "  RMS          : ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4),
    ... "  (", fixed$(rmsRatio, 2), "x)"
appendInfoLine: "========================================================"

selectObject: resultSound
