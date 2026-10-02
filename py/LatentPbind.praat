# ============================================================
# Praat AudioTools - LatentPbind.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent Pbind (Hybrid Systems)
#
#   An algorithmic latent-space composition system in which independent
#   Pbind-style pattern streams generate a trajectory through a learned
#   acoustic space. A small beta-VAE is trained on the selected Sound; its
#   latent axes are rotated (z1 = direction of largest spread), oriented
#   (+z = brighter side) and robustly normalised (2nd..98th percentile ->
#   -1..+1), so patterns are composed in stable units without knowing the
#   raw latent scale. Each latent coordinate, the cluster anchor and a few
#   auxiliary process parameters are bound to their own pattern stream; a
#   key may also run on its own clock (dur_<key>), so latent dimensions can
#   behave as independent contrapuntal voices.
#
#   This is an OFFLINE compositional controller, not a performance
#   instrument: the trajectory is composed, then rendered.
#
# Pipeline:
#   Praat  : validate Sound -> mono 32-bit WAV + parameter file + Pbind file
#   Python : STFT -> 64 log bands -> overlapping 8-cell patches (silence-
#            gated) -> numpy beta-VAE -> PCA-rotated, oriented, robustly
#            scaled latent -> k-means++ identity clusters -> Pbind parse ->
#            per-key event streams -> step/linear/cubic/smooth curves ->
#            boundary (clamp/reflect/wrap/soft attract) + attraction ->
#            render (Decoder / Nearest event / Barycentric) in the STFT
#            domain -> ISTFT -> WAV + visualisation tables + stats
#   Praat  : read result, Info report, 6-panel Picture, cleanup, play
#
# Pbind keys:
#   dur (required, the global event clock) | z1..z8 (normalised latent
#   coordinates, -1..+1 covers the data) | cluster (identity anchor;
#   z keys become offsets from its centroid) | amp | temp (posterior
#   jitter per event) | attract (0..1 pull to the nearest source patch) |
#   rate (read speed, 0..4) | retrig (1 = restart the patch read pointer)
#   | interp (step/linear/cubic/smooth) | dur_<key> (own clock for <key>) |
#   interp_<key> (own interpolation). Keyword style key=value or
#   SuperCollider style \key, value are both accepted.
#
# Patterns (nestable):
#   Pseq Pser Prand Pxrand Pshuf Pwrand Pwhite Pexprand Pbrown Pwalk
#   Pseries Pgeom Pstutter Pn Plag Phold Pimpulse Plogistic
#
# Changelog v1.0.1:
#   - Temporary files carry a per-run session tag, so two Praat instances
#     (or two runs) can no longer overwrite each other's files.
#   - "Ended by" now names the stream that actually ended the output when
#     several finite patterns share the dur clock (Python fix).
#   - Barycentric panel shades by the amplitude coefficient actually
#     targeted (sqrt of the equal-power target), not the pre-power weight.
#   - Wording made precise: Decoder = latent spectral-envelope decoder
#     (hybrid resynthesis); Pure = decoded magnitude only, phase initialised
#     from the source and refined by Griffin-Lim; KL-active count refers to
#     raw VAE dimensions, not to the rotated z1..zd shown.
#
# Changelog v1.0:
#   - First release.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Requires:
#   Praat 6.3 or later (colon form syntax); Python 3 with numpy and scipy
#   (pip install numpy scipy). CPU only, no network, no pretrained model.
#   py/latent_pbind.py inside the plugin folder (or next to this script).
# ============================================================

version$ = "1.0.1"

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- FORM ----
form: "Latent Pbind v1.0.1"
    optionmenu: "Preset", 2
        option: "Custom (use the Pbind text below)"
        option: "Ordered drift"
        option: "Brownian latent walk"
        option: "Polymetric coordinates"
        option: "Sparse identity jumps"
        option: "Chaotic orbit"
        option: "Cluster pilgrimage"
        option: "Radical latent counterpoint"
    comment: "Pbind — keys: dur, z1..z8, cluster, amp, temp, attract, rate, retrig, interp"
    text: 4, "Pbind", "Pbind(dur=Pseq([0.25,0.5,0.25,1],inf), z1=Pwhite(-1,1,inf), z2=Pwalk([-1,-0.5,0,0.5,1],1), z3=Pseq([0,0.5,1,-0.5],inf), interp=cubic)"
    real: "Output_duration_(s)", "0"
    comment: "Output duration 0 = input duration (a finite pattern may end it earlier)"
    optionmenu: "Rendering_mode", 1
        option: "Decoder"
        option: "Nearest event"
        option: "Barycentric"
    optionmenu: "Interpolation", 4
        option: "Step"
        option: "Linear"
        option: "Cubic"
        option: "Smooth"
    optionmenu: "Boundary_mode", 2
        option: "Clamp"
        option: "Reflect"
        option: "Wrap"
        option: "Soft attract"
    real: "Excursion", "1.0"
    integer: "Random_seed", "1"
    boolean: "Advanced_settings", 0
    boolean: "Draw_visualisation", 1
    boolean: "Play_result", 1
endform

# ---- PRESETS (Pbind text) ----
if preset = 2
    presetName$ = "Ordered drift"
    pbind$ = "Pbind(dur=1, z1=Pseq([Pseries(-0.9,0.3,7), Pseries(0.9,-0.3,7)],inf), z2=Pseq([0.5,-0.5],inf), retrig=0, interp=smooth)"
elsif preset = 3
    presetName$ = "Brownian latent walk"
    pbind$ = "Pbind(dur=0.2, z1=Pbrown(-1,1,0.25,inf), z2=Pbrown(-1,1,0.25,inf), z3=Pbrown(-1,1,0.15,inf), z4=Pbrown(-1,1,0.1,inf), retrig=Pwrand([1,0],[0.3,0.7],inf), interp=linear)"
elsif preset = 4
    presetName$ = "Polymetric coordinates"
    pbind$ = "Pbind(dur=0.25, z1=Pseq([-1,-0.5,0,0.5,1],inf), z2=Pseq([1,0.6,0.2,-0.2,-0.6,-1,0],inf), z3=Pseq([0,0.8,-0.8,0.4,-0.4,0.9,-0.9,0.2,-0.2,0.6,-0.6],inf), interp=cubic)"
elsif preset = 5
    presetName$ = "Sparse identity jumps"
    pbind$ = "Pbind(dur=0.25, cluster=Phold(Pxrand([0,1,2,3,4,5],inf),0.08), z1=Pwhite(-0.12,0.12,inf), z2=Pwhite(-0.12,0.12,inf), retrig=Pwrand([1,0],[0.15,0.85],inf), interp=step)"
elsif preset = 6
    presetName$ = "Chaotic orbit"
    pbind$ = "Pbind(dur=0.125, z1=Plag(Plogistic(3.91,0.31,-1,1),0.7), z2=Plag(Plogistic(3.83,0.62,-1,1),0.8), z3=Plag(Pwhite(-1,1,inf),0.9), temp=0.5, interp=smooth)"
elsif preset = 7
    presetName$ = "Cluster pilgrimage"
    pbind$ = "Pbind(dur=2, cluster=Pseq([0,1,2,3,4,5],inf), z1=Plag(Pwhite(-0.3,0.3,inf),0.5), dur_z1=0.25, z2=Plag(Pwhite(-0.3,0.3,inf),0.5), dur_z2=0.25, attract=0.3, retrig=0, interp=smooth)"
elsif preset = 8
    presetName$ = "Radical latent counterpoint"
    pbind$ = "Pbind(dur=1, z1=Pbrown(-1,1,0.2,inf), dur_z1=0.5, interp_z1=smooth, z2=Pseq([-0.8,0.3,0.9,-0.2,0.5],inf), dur_z2=Pseq([0.75,0.25,0.5],inf), interp_z2=step, z3=Pimpulse(0.2,-1,1), dur_z3=0.125, interp_z3=step, z4=Pgeom(1,0.9,inf), dur_z4=0.4, interp_z4=linear, rate=Pseq([1,1,0.5,2],inf))"
else
    presetName$ = "Custom"
endif

# ---- ADVANCED SETTINGS (second dialog keeps the main form short) ----
# Initialised first: on Praat builds where a pause auto-continues headless,
# the fields would otherwise never be assigned.
latent_dimensions = 4
patch_length_ms = 120
analysis_hop_ms = 20
training_epochs = 150
beta = 0.5
clusters = 6
neighbours_K = 4
crossfade_ms = 40
phase_iterations = 12
decoder_detail = 1
normalise_output = 1
if preset = 8 or preset = 3
    # these presets address z4
    latent_dimensions = 4
endif
if advanced_settings
    beginPause: "Latent Pbind — advanced settings"
        comment: "Latent model"
        natural: "Latent_dimensions", string$(latent_dimensions)
        positive: "Patch_length_ms", string$(patch_length_ms)
        positive: "Analysis_hop_ms", string$(analysis_hop_ms)
        natural: "Training_epochs", string$(training_epochs)
        real: "Beta", string$(beta)
        natural: "Clusters", string$(clusters)
        comment: "Rendering"
        natural: "Neighbours_K", string$(neighbours_K)
        real: "Crossfade_ms", string$(crossfade_ms)
        integer: "Phase_iterations", string$(phase_iterations)
        optionmenu: "Decoder_detail", decoder_detail
            option: "Source fine structure"
            option: "Pure decoder"
        boolean: "Normalise_output", normalise_output
    endPause: "Continue", 1
endif

# ---- VALIDATION ----
if latent_dimensions < 2 or latent_dimensions > 8
    exitScript: "Latent dimensions must be 2..8 (got " + string$(latent_dimensions) + ")."
endif
if patch_length_ms < 30 or patch_length_ms > 1000
    exitScript: "Patch length must be 30..1000 ms."
endif
if analysis_hop_ms < 5 or analysis_hop_ms > 1000
    exitScript: "Analysis hop must be 5..1000 ms."
endif
if training_epochs < 10 or training_epochs > 2000
    exitScript: "Training epochs must be 10..2000."
endif
if beta < 0
    exitScript: "Beta must be >= 0."
endif
if clusters < 2 or clusters > 32
    exitScript: "Clusters must be 2..32."
endif
if neighbours_K < 2 or neighbours_K > 16
    exitScript: "Neighbours K must be 2..16."
endif
if crossfade_ms < 0
    exitScript: "Crossfade must be >= 0 ms."
endif
if phase_iterations < 0 or phase_iterations > 200
    exitScript: "Phase iterations must be 0..200."
endif
if excursion < 0 or excursion > 10
    exitScript: "Excursion must be 0..10."
endif
if output_duration < 0 or output_duration > 3600
    exitScript: "Output duration must be 0..3600 s."
endif
pbindFlat$ = replace_regex$(pbind$, "[\r\n\t]+", " ", 0)
pbindFlat$ = replace_regex$(pbindFlat$, " +", " ", 0)
if index_regex(pbindFlat$, "[^ ]") = 0
    exitScript: "The Pbind expression is empty."
endif

selectObject: sound
dur = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels
if dur < 3 * patch_length_ms / 1000
    exitScript: "Input too short: " + fixed$(dur, 3) + " s; needs at least 3 x patch length (" + fixed$(3 * patch_length_ms / 1000, 2) + " s)."
endif
rmsIn = Get root-mean-square: 0, 0
if rmsIn = undefined or rmsIn < 1e-5
    exitScript: "The selected Sound is silent."
endif

# Option text -> engine tokens
renderTok$ = "decoder"
if rendering_mode = 2
    renderTok$ = "nearest"
elsif rendering_mode = 3
    renderTok$ = "barycentric"
endif
interpTok$ = replace_regex$(interpolation$, "([A-Z])", "\L\1", 0)
boundTok$ = "clamp"
if boundary_mode = 2
    boundTok$ = "reflect"
elsif boundary_mode = 3
    boundTok$ = "wrap"
elsif boundary_mode = 4
    boundTok$ = "attract"
endif
detailTok$ = "source"
if decoder_detail = 2
    detailTok$ = "pure"
endif

# ---- PRAAT 7 TRUST (writes temp files and runs Python) ----
if praatVersion >= 7000
    trustOK = askForTrust()
    if not trustOK
        exitScript: "Latent Pbind needs permission to write temporary files and run Python."
    endif
endif

# ---- PATHS ----
pluginDir$ = replace$(preferencesDirectory$, "\", "/", 0) + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_pbind.py"
if not fileReadable(pythonScript$)
    pythonScript$ = replace$(defaultDirectory$, "\", "/", 0) + "/latent_pbind.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find latent_pbind.py." + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

# Per-run session tag: concurrent runs / Praat instances never share files.
sessionTag$ = replace_regex$(date$(), "[^0-9]", "", 0) + "_" + string$(randomInteger(100000, 999999))
tmp$ = replace$(temporaryDirectory$, "\", "/", 0) + "/temp_latpbind_" + sessionTag$ + "_"
fIn$ = tmp$ + "input.wav"
fOut$ = tmp$ + "output.wav"
fPar$ = tmp$ + "params.txt"
fPb$ = tmp$ + "pbind.txt"
fStatus$ = tmp$ + "status.txt"
fStats$ = tmp$ + "stats.txt"
fLog$ = tmp$ + "log.txt"
fEv$ = tmp$ + "events.csv"
fTr$ = tmp$ + "traj.csv"
fCl$ = tmp$ + "cloud.csv"
fCe$ = tmp$ + "centres.csv"
fOn$ = tmp$ + "onsets.csv"
fProbe$ = tmp$ + "probe.py"
fProbeOK$ = tmp$ + "probe.ok"

procedure cleanUp
    for .k from 1 to 14
        if .k = 1
            .f$ = fIn$
        elsif .k = 2
            .f$ = fOut$
        elsif .k = 3
            .f$ = fPar$
        elsif .k = 4
            .f$ = fPb$
        elsif .k = 5
            .f$ = fStatus$
        elsif .k = 6
            .f$ = fStats$
        elsif .k = 7
            .f$ = fLog$
        elsif .k = 8
            .f$ = fEv$
        elsif .k = 9
            .f$ = fTr$
        elsif .k = 10
            .f$ = fCl$
        elsif .k = 11
            .f$ = fCe$
        elsif .k = 12
            .f$ = fOn$
        elsif .k = 13
            .f$ = fProbe$
        else
            .f$ = fProbeOK$
        endif
        if fileReadable(.f$)
            deleteFile: .f$
        endif
    endfor
endproc
@cleanUp

# ---- INFO HEADER ----
writeInfoLine: "=== Latent Pbind v", version$, " ==="
appendInfoLine: "Input:    ", soundName$, "  (", fixed$(dur, 2), " s, ", sr, " Hz, ", nChannels, " ch)"
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Pbind:    ", pbindFlat$
appendInfoLine: ""

# ---- [1] PYTHON DISCOVERY ----
appendInfoLine: "[1/4] Looking for Python 3 with numpy + scipy..."
writeFileLine: fProbe$, "import numpy, scipy.io.wavfile"
appendFileLine: fProbe$, "open(r'" + fProbeOK$ + "', 'w').write('ok')"
if windows
    nCand = 4
    cand1$ = "python"
    cand2$ = "py -3"
    cand3$ = "py"
    cand4$ = "python3"
elsif macintosh
    nCand = 4
    cand1$ = "/opt/homebrew/bin/python3"
    cand2$ = "/usr/local/bin/python3"
    cand3$ = "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"
    cand4$ = "python3"
else
    nCand = 2
    cand1$ = "python3"
    cand2$ = "python"
endif
pythonCmd$ = ""
iCand = 1
while iCand <= nCand and pythonCmd$ = ""
    tryCmd$ = cand'iCand'$
    runSystem_nocheck: tryCmd$ + " """ + fProbe$ + """"
    if fileReadable(fProbeOK$)
        pythonCmd$ = tryCmd$
        deleteFile: fProbeOK$
    endif
    iCand = iCand + 1
endwhile
if pythonCmd$ = ""
    @cleanUp
    exitScript: "No Python 3 with numpy + scipy was found." + newline$ + "Install with:  pip install numpy scipy"
endif
appendInfoLine: "      using: ", pythonCmd$

# ---- [2] TEMP FILES ----
appendInfoLine: "[2/4] Writing temporary files..."
selectObject: sound
if nChannels > 1
    tmpMono = Convert to mono
else
    tmpMono = Copy: "latpbind_tmp"
endif
Save as 32-bit WAV file: fIn$
removeObject: tmpMono

writeFileLine: fPb$, pbind$
writeFileLine: fPar$, "input_wav=" + fIn$
appendFileLine: fPar$, "pbind_file=" + fPb$
appendFileLine: fPar$, "output_wav=" + fOut$
appendFileLine: fPar$, "status_file=" + fStatus$
appendFileLine: fPar$, "stats_file=" + fStats$
appendFileLine: fPar$, "events_csv=" + fEv$
appendFileLine: fPar$, "traj_csv=" + fTr$
appendFileLine: fPar$, "cloud_csv=" + fCl$
appendFileLine: fPar$, "centres_csv=" + fCe$
appendFileLine: fPar$, "onsets_csv=" + fOn$
appendFileLine: fPar$, "output_duration=" + string$(output_duration)
appendFileLine: fPar$, "seed=" + string$(random_seed)
appendFileLine: fPar$, "render_mode=" + renderTok$
appendFileLine: fPar$, "interp=" + interpTok$
appendFileLine: fPar$, "boundary=" + boundTok$
appendFileLine: fPar$, "excursion=" + string$(excursion)
appendFileLine: fPar$, "latent_dims=" + string$(latent_dimensions)
appendFileLine: fPar$, "patch_ms=" + string$(patch_length_ms)
appendFileLine: fPar$, "analysis_hop_ms=" + string$(analysis_hop_ms)
appendFileLine: fPar$, "epochs=" + string$(training_epochs)
appendFileLine: fPar$, "beta=" + string$(beta)
appendFileLine: fPar$, "clusters=" + string$(clusters)
appendFileLine: fPar$, "neighbours=" + string$(neighbours_K)
appendFileLine: fPar$, "crossfade_ms=" + string$(crossfade_ms)
appendFileLine: fPar$, "gl_iterations=" + string$(phase_iterations)
appendFileLine: fPar$, "decoder_detail=" + detailTok$
appendFileLine: fPar$, "normalise=" + string$(normalise_output)

# ---- [3] ENGINE ----
appendInfoLine: "[3/4] Training the latent model and rendering (CPU; usually 5-30 s)..."
runSystem_nocheck: pythonCmd$ + " """ + pythonScript$ + """ """ + fPar$ + """ > """ + fLog$ + """ 2>&1"
if not fileReadable(fStatus$)
    logTail$ = ""
    if fileReadable(fLog$)
        logTail$ = readFile$(fLog$)
        if length(logTail$) > 1500
            logTail$ = right$(logTail$, 1500)
        endif
    endif
    @cleanUp
    appendInfoLine: logTail$
    exitScript: "The Python engine did not run to completion (no status file)." + newline$ + "Command: " + pythonCmd$ + " " + pythonScript$
endif
status$ = readFile$(fStatus$)
status$ = replace_regex$(status$, "[\r\n]+$", "", 0)
if left$(status$, 2) <> "OK"
    if fileReadable(fLog$)
        logTxt$ = readFile$(fLog$)
        if index(status$, "ERROR internal") > 0
            if length(logTxt$) > 1500
                logTxt$ = right$(logTxt$, 1500)
            endif
            appendInfoLine: logTxt$
        endif
    endif
    @cleanUp
    exitScript: "Latent Pbind stopped:" + newline$ + status$
endif
if not fileReadable(fOut$) or not fileReadable(fStats$)
    @cleanUp
    exitScript: "The engine reported OK but its output files are missing (temporary-file error)."
endif

# ---- [4] RESULT ----
appendInfoLine: "[4/4] Reading result..."
result = Read from file: fOut$
Rename: soundName$ + "_LatentPbind"
outDur = Get total duration
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0

stats$ = newline$ + readFile$(fStats$)
procedure statNum: .key$
    .v = extractNumber(stats$, newline$ + .key$ + "=")
endproc
procedure statStr: .key$
    .s$ = extractLine$(stats$, newline$ + .key$ + "=")
endproc

@statNum: "seed"
seedUsed = statNum.v
@statStr: "ended"
ended$ = statStr.s$
@statNum: "patches"
nPatches = statNum.v
@statNum: "patch_ms_eff"
patchMsEff = statNum.v
@statNum: "hop_ms"
hopMs = statNum.v
@statNum: "active_dims"
activeDims = statNum.v
@statNum: "rec_db"
recDb = statNum.v
@statNum: "level_cal"
levelCal = statNum.v
@statNum: "kl"
klVal = statNum.v
@statNum: "clusters"
nClusters = statNum.v
@statNum: "r_ref"
rRef = statNum.v
@statStr: "var_share"
varShare$ = statStr.s$
@statStr: "corr_centroid"
corrC$ = statStr.s$
@statStr: "corr_level"
corrL$ = statStr.s$
@statStr: "interp"
interpUsed$ = statStr.s$
@statNum: "global_events"
nGlobal = statNum.v
@statStr: "lanes"
lanes$ = statStr.s$
@statNum: "n_lanes"
nLanes = statNum.v
@statStr: "plot_dims"
plotDims$ = statStr.s$
@statNum: "outside_pct"
outsidePct = statNum.v
@statNum: "far_pct"
farPct = statNum.v
@statNum: "dist_mean"
distMean = statNum.v
@statNum: "dist_max"
distMax = statNum.v
@statNum: "limited_pct"
limitedPct = statNum.v
@statNum: "distinct_donors"
nDonors = statNum.v
@statNum: "voice_starts"
nVoiceStarts = statNum.v
@statNum: "retriggers"
nRetrig = statNum.v
@statNum: "neighbours"
nNeigh = statNum.v
@statNum: "gl"
glUsed = statNum.v
@statStr: "detail"
detailUsed$ = statStr.s$
@statNum: "peak_raw"
peakRaw = statNum.v
@statNum: "gain"
gainApplied = statNum.v

if detailUsed$ = "source"
    detailLabel$ = "decoded envelope + source fine structure"
elsif detailUsed$ = "pure"
    detailLabel$ = "decoded magnitude only; phase from source, refined by Griffin-Lim"
else
    detailLabel$ = "n/a"
endif
if random_seed = 0
    seedLabel$ = string$(seedUsed) + " (auto; enter it to reproduce)"
else
    seedLabel$ = string$(seedUsed)
endif

# ---- INFO REPORT ----
appendInfoLine: ""
appendInfoLine: "--- Latent model ---"
appendInfoLine: "  numpy beta-VAE on STFT log-band patches (64 bands x 8 cells)"
appendInfoLine: "  Patches:        ", nPatches, " x ", fixed$(patchMsEff, 0), " ms  (STFT hop ", fixed$(hopMs, 1), " ms)"
appendInfoLine: "  Latent dims:    ", latent_dimensions, "   (", activeDims, "/", latent_dimensions, " raw VAE dims active by KL, before rotation)   beta ", beta, ", ", training_epochs, " epochs"
appendInfoLine: "  Reconstruction: ", fixed$(recDb, 2), " dB RMS per cell; decoder level calibration ", fixed$(levelCal, 2), " dB; KL ", fixed$(klVal, 2)
appendInfoLine: "  Axis variance:  ", varShare$, "   (z1 first)"
appendInfoLine: "  r(z, centroid): ", corrC$, "   (sign set so r >= 0; orientation is meaningful only where r is clearly > 0)"
appendInfoLine: "  r(z, level):    ", corrL$
appendInfoLine: "  Clusters:       ", nClusters, "  (ordered along z1; cluster 0 = lowest z1)"
appendInfoLine: ""
appendInfoLine: "--- Pattern ---"
appendInfoLine: "  Lanes:          ", replace$(lanes$, ";", ", ", 0)
appendInfoLine: "  Global events:  ", nGlobal, "   retriggers ", nRetrig
appendInfoLine: "  Interpolation:  ", interpUsed$, " (default; interp_<key> overrides per key)"
appendInfoLine: "  Seed:           ", seedLabel$
appendInfoLine: "  Output:         ", fixed$(outDur, 3), " s  (ended by: ", ended$, ")"
appendInfoLine: ""
appendInfoLine: "--- Navigation ---"
appendInfoLine: "  Boundary:       ", boundary_mode$, "   excursion ", fixed$(excursion, 2)
appendInfoLine: "  Raw trajectory outside the data box: ", fixed$(outsidePct, 1), "% of frames"
appendInfoLine: "  Distance to nearest patch: mean ", fixed$(distMean, 2), ", max ", fixed$(distMax, 2), " x r90 (", fixed$(rRef, 3), ");  ", fixed$(farPct, 1), "% of frames beyond r90"
appendInfoLine: ""
appendInfoLine: "--- Rendering ---"
if rendering_mode = 1
    appendInfoLine: "  Mode:           Decoder (latent spectral-envelope decoder, hybrid resynthesis)"
else
    appendInfoLine: "  Mode:           ", rendering_mode$
endif
if rendering_mode = 1
    appendInfoLine: "  Detail:         ", detailLabel$, "; Griffin-Lim ", glUsed, " iterations"
    appendInfoLine: "  Level-limited frames (extrapolated latents): ", fixed$(limitedPct, 1), "%"
elsif rendering_mode = 3
    appendInfoLine: "  Neighbours:     ", nNeigh, " (inverse-distance weights, equal-power mix)"
endif
appendInfoLine: "  Distinct source patches used: ", nDonors, ";  voice changes ", nVoiceStarts, "  (crossfade ", crossfade_ms, " ms)"
if normalise_output
    appendInfoLine: "  Normalised to -1 dBFS (raw peak ", fixed$(peakRaw, 3), ", gain ", fixed$(gainApplied, 3), ")"
elsif gainApplied < 1
    appendInfoLine: "  Peak guard: raw peak ", fixed$(peakRaw, 3), " attenuated by ", fixed$(gainApplied, 3)
else
    appendInfoLine: "  No normalisation (raw peak ", fixed$(peakRaw, 3), ")"
endif
appendInfoLine: "  Output peak ", fixed$(outPeak, 3), ", RMS ", fixed$(outRms, 4), "  (input RMS ", fixed$(rmsIn, 4), ")"

# ===========================================================================
# VISUALISATION
# ===========================================================================
if draw_visualisation
    @drawFigure
endif

@cleanUp
appendInfoLine: ""
appendInfoLine: "Output: ", soundName$, "_LatentPbind  (the original Sound is unchanged)"
selectObject: result
if play_result
    Play
endif

# ===========================================================================
# PROCEDURES
# ===========================================================================

procedure sanitize: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    .out$ = .s$
endproc

procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        .step = .p
    elsif .m < 3.5
        .step = 2 * .p
    elsif .m < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure keyColour: .key$
    .rgb$ = "{0.50, 0.50, 0.50}"
    if .key$ = "z1"
        .rgb$ = "{0.20, 0.40, 0.80}"
    elsif .key$ = "z2"
        .rgb$ = "{0.85, 0.35, 0.15}"
    elsif .key$ = "z3"
        .rgb$ = "{0.15, 0.60, 0.35}"
    elsif .key$ = "z4"
        .rgb$ = "{0.60, 0.25, 0.70}"
    elsif .key$ = "z5"
        .rgb$ = "{0.85, 0.65, 0.10}"
    elsif .key$ = "z6"
        .rgb$ = "{0.10, 0.65, 0.75}"
    elsif .key$ = "z7"
        .rgb$ = "{0.75, 0.20, 0.45}"
    elsif .key$ = "z8"
        .rgb$ = "{0.40, 0.40, 0.40}"
    elsif .key$ = "dur"
        .rgb$ = "{0.10, 0.10, 0.10}"
    elsif .key$ = "cluster"
        .rgb$ = "{0.45, 0.28, 0.12}"
    endif
endproc

procedure timeMarks: .withNumbers
    @niceStep: outDur, 8
    if .withNumbers
        Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    else
        Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure drawFigure
    Erase all
    Line width: 1
    Solid line

    # ---- geometry (inches) ----
    t0 = 0.10
    t1 = 0.60
    p1a = 0.95
    p1b = 2.15
    p2a = 2.45
    p2b = 3.70
    p3a = 4.20
    p3b = 6.55
    p4a = 7.10
    p4b = 8.05
    p5a = 8.30
    p5b = 9.20
    s0 = 9.70
    s1 = 10.70
    canvasH = 10.80
    xL = 0.60
    xR = 7.70

    # ---- title ----
    Font size: 13
    Select inner viewport: xL, xR, t0, t1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Latent Pbind — algorithmic motion through a learned acoustic space##"
    Font size: 7
    Select inner viewport: xL, xR, t0, t1
    Axes: 0, 1, 0, 1
    @sanitize: soundName$
    sub$ = sanitize.out$ + "   |   " + presetName$ + "   |   " + rendering_mode$ + "   |   " + boundary_mode$ + "   |   seed " + string$(seedUsed)
    Colour: "{0.35, 0.35, 0.42}"
    Text: 0.5, "centre", 0.18, "half", sub$

    # ================= Panel 1: pattern events =================
    evTab = Read Table from comma-separated file: fEv$
    nEv = Get number of rows
    Font size: 7
    Select inner viewport: xL, xR, p1a, p1b
    Axes: 0, outDur, 0, nLanes
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, outDur, 0, nLanes
    Colour: "{0.85, 0.85, 0.88}"
    for iL from 1 to nLanes - 1
        Draw line: 0, iL, outDur, iL
    endfor
    prevLane = -1
    prevT = 0
    prevY = 0
    for iR from 1 to nEv
        selectObject: evTab
        lane = Get value: iR, "lane"
        key$ = Get value: iR, "key"
        tt = Get value: iR, "time"
        vn = Get value: iR, "vnorm"
        laneBase = nLanes - lane
        yy = laneBase + 0.15 + 0.70 * vn
        @keyColour: key$
        Colour: keyColour.rgb$
        if lane = prevLane
            Line width: 1
            Draw line: prevT, prevY, tt, prevY
            Colour: "{0.75, 0.75, 0.78}"
            Draw line: tt, prevY, tt, yy
            Colour: keyColour.rgb$
        endif
        Line width: 1
        Draw line: tt, laneBase, tt, laneBase + 0.12
        Paint circle (mm): keyColour.rgb$, tt, yy, 0.45
        if iR = nEv
            Draw line: tt, yy, outDur, yy
        else
            nextLane = Get value: iR + 1, "lane"
            if nextLane <> lane
                Draw line: tt, yy, outDur, yy
            endif
        endif
        prevLane = lane
        prevT = tt
        prevY = yy
    endfor
    removeObject: evTab
    # lane names (left margin)
    Font size: 6
    Select inner viewport: xL, xR, p1a, p1b
    Axes: 0, 1, 0, nLanes
    rem$ = lanes$ + ";"
    for iL from 1 to nLanes
        sp = index(rem$, ";")
        name$ = left$(rem$, sp - 1)
        rem$ = mid$(rem$, sp + 1, length(rem$) - sp)
        @keyColour: name$
        Colour: keyColour.rgb$
        @sanitize: name$
        Text: -0.006, "right", nLanes - iL + 0.5, "half", sanitize.out$
    endfor
    Font size: 7
    Select inner viewport: xL, xR, p1a, p1b
    Axes: 0, outDur, 0, nLanes
    Colour: "Black"
    Text top: "no", "##Pattern events## — one lane per stream; dot height = value (lane-normalised), tick = onset; dur lane shows the duration"
    Select inner viewport: xL, xR, p1a, p1b
    Axes: 0, outDur, 0, nLanes
    Draw inner box
    @timeMarks: 0
    @railLabel: p1a, p1b, "Events"

    # ================= Panel 2: latent trajectories =================
    trTab = Read Table from comma-separated file: fTr$
    nTr = Get number of rows
    yMax = 1.25
    nPD = 0
    remD$ = plotDims$ + " "
    while index(remD$, " ") > 0 and length(remD$) > 1
        sp = index(remD$, " ")
        tok$ = left$(remD$, sp - 1)
        remD$ = mid$(remD$, sp + 1, length(remD$) - sp)
        if tok$ <> ""
            nPD = nPD + 1
            pd_'nPD' = number(tok$)
        endif
    endwhile
    for iD from 1 to nPD
        col$ = "z" + string$(pd_'iD')
        selectObject: trTab
        cMax = Get maximum: col$
        cMin = Get minimum: col$
        yMax = max(yMax, abs(cMax) * 1.05, abs(cMin) * 1.05)
    endfor
    Font size: 7
    Select inner viewport: xL, xR, p2a, p2b
    Axes: 0, outDur, -yMax, yMax
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, outDur, -yMax, yMax
    Paint rectangle: "{0.93, 0.95, 0.98}", 0, outDur, -1, 1
    Colour: "{0.65, 0.65, 0.70}"
    Dotted line
    Draw line: 0, 1, outDur, 1
    Draw line: 0, -1, outDur, -1
    Solid line
    Colour: "{0.80, 0.80, 0.84}"
    Draw line: 0, 0, outDur, 0
    Line width: 1.5
    for iD from 1 to nPD
        col$ = "z" + string$(pd_'iD')
        @keyColour: col$
        Colour: keyColour.rgb$
        selectObject: trTab
        xa = Get value: 1, "time"
        ya = Get value: 1, col$
        for iR from 2 to nTr
            xb = Get value: iR, "time"
            yb = Get value: iR, col$
            Draw line: xa, ya, xb, yb
            xa = xb
            ya = yb
        endfor
    endfor
    Line width: 1
    # legend
    Font size: 6
    Select inner viewport: xL, xR, p2a, p2b
    Axes: 0, 1, 0, 1
    for iD from 1 to nPD
        col$ = "z" + string$(pd_'iD')
        @keyColour: col$
        Colour: keyColour.rgb$
        Text: 0.995 - (nPD - iD) * 0.035, "right", 0.93, "half", "##" + col$ + "##"
    endfor
    Font size: 7
    Select inner viewport: xL, xR, p2a, p2b
    Axes: 0, outDur, -yMax, yMax
    Colour: "Black"
    Text top: "no", "##Latent trajectories## — final normalised coordinates (after boundary + attraction); shaded band = data box -1…+1"
    Select inner viewport: xL, xR, p2a, p2b
    Axes: 0, outDur, -yMax, yMax
    Draw inner box
    @timeMarks: 1
    @niceStep: 2 * yMax, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @railLabel: p2a, p2b, "Latent (norm.)"

    # ================= Panel 3: latent maps =================
    clTab = Read Table from comma-separated file: fCl$
    nCl = Get number of rows
    ceTab = Read Table from comma-separated file: fCe$
    nCe = Get number of rows
    onTab = Read Table from comma-separated file: fOn$
    nOn = Get number of rows
    nMaps = 2
    if latent_dimensions >= 4
        mxA$ = "z1"
        myA$ = "z2"
        mxB$ = "z3"
        myB$ = "z4"
    elsif latent_dimensions = 3
        mxA$ = "z1"
        myA$ = "z2"
        mxB$ = "z1"
        myB$ = "z3"
    else
        mxA$ = "z1"
        myA$ = "z2"
        nMaps = 1
    endif
    for iMap from 1 to nMaps
        if iMap = 1
            mx$ = mxA$
            my$ = myA$
            vx0 = xL
            vx1 = 3.85
        else
            mx$ = mxB$
            my$ = myB$
            vx0 = 4.45
            vx1 = xR
        endif
        selectObject: clTab
        ax0 = Get minimum: mx$
        ax1 = Get maximum: mx$
        ay0 = Get minimum: my$
        ay1 = Get maximum: my$
        selectObject: trTab
        tx0 = Get minimum: mx$
        tx1 = Get maximum: mx$
        ty0 = Get minimum: my$
        ty1 = Get maximum: my$
        ax0 = min(ax0, tx0, -1)
        ax1 = max(ax1, tx1, 1)
        ay0 = min(ay0, ty0, -1)
        ay1 = max(ay1, ty1, 1)
        padX = 0.08 * (ax1 - ax0)
        padY = 0.08 * (ay1 - ay0)
        ax0 = ax0 - padX
        ax1 = ax1 + padX
        ay0 = ay0 - padY
        ay1 = ay1 + padY
        Font size: 7
        Select inner viewport: vx0, vx1, p3a, p3b
        Axes: ax0, ax1, ay0, ay1
        Paint rectangle: "{0.98, 0.98, 0.99}", ax0, ax1, ay0, ay1
        Paint rectangle: "{0.93, 0.95, 0.98}", -1, 1, -1, 1
        # source patches
        for iR from 1 to nCl
            selectObject: clTab
            px = Get value: iR, mx$
            py = Get value: iR, my$
            Paint circle (mm): "{0.66, 0.66, 0.68}", px, py, 0.35
        endfor
        # trajectory, colour = time (blue -> orange)
        Line width: 1.6
        selectObject: trTab
        xa = Get value: 1, mx$
        ya = Get value: 1, my$
        for iR from 2 to nTr
            xb = Get value: iR, mx$
            yb = Get value: iR, my$
            u = (iR - 1) / max(nTr - 1, 1)
            rr = 0.20 + 0.70 * u
            gg = 0.40 + 0.00 * u
            bb = 0.80 - 0.70 * u
            Colour: "{" + fixed$(rr, 3) + ", " + fixed$(gg, 3) + ", " + fixed$(bb, 3) + "}"
            Draw line: xa, ya, xb, yb
            xa = xb
            ya = yb
        endfor
        Line width: 1
        # event onsets
        Colour: "{0.10, 0.10, 0.10}"
        for iR from 1 to nOn
            selectObject: onTab
            px = Get value: iR, mx$
            py = Get value: iR, my$
            Draw circle (mm): px, py, 0.7
        endfor
        # cluster centres
        for iR from 1 to nCe
            selectObject: ceTab
            px = Get value: iR, mx$
            py = Get value: iR, my$
            cIdx = Get value: iR, "idx"
            Paint circle (mm): "{0.30, 0.30, 0.32}", px, py, 2.6
            Font size: 6
            Select inner viewport: vx0, vx1, p3a, p3b
            Axes: ax0, ax1, ay0, ay1
            Colour: "White"
            Text: px, "centre", py, "half", "##" + string$(cIdx) + "##"
            Font size: 7
            Select inner viewport: vx0, vx1, p3a, p3b
            Axes: ax0, ax1, ay0, ay1
        endfor
        Colour: "Black"
        if iMap = 1
            Text top: "no", "##Latent map " + mx$ + " × " + my$ + "## — grey: source patches, line: trajectory (blue→orange = time)"
        else
            Text top: "no", "##Latent map " + mx$ + " × " + my$ + "## — ○ event onsets, numbered discs: identity clusters"
        endif
        Select inner viewport: vx0, vx1, p3a, p3b
        Axes: ax0, ax1, ay0, ay1
        Draw inner box
        @niceStep: ax1 - ax0, 5
        Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
        @niceStep: ay1 - ay0, 5
        Marks left every: 1, niceStep.step, "yes", "yes", "no"
        Text bottom: "yes", mx$ + " (normalised)"
        Text left: "yes", my$
    endfor
    if nMaps = 1
        Font size: 7
        Select inner viewport: 4.45, xR, p3a, p3b
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Colour: "{0.35, 0.35, 0.35}"
        Text: 0.5, "centre", 0.5, "half", "Two-dimensional model: z1 × z2 is the whole latent space"
        Select inner viewport: 4.45, xR, p3a, p3b
        Axes: 0, 1, 0, 1
        Colour: "Black"
        Draw inner box
    endif
    removeObject: clTab, ceTab, onTab

    # ================= Panel 4: rendering diagnostic =================
    Font size: 7
    if rendering_mode = 1
        selectObject: trTab
        dMax = Get maximum: "dist"
        yTop = max(2, dMax * 1.1)
        Select inner viewport: xL, xR, p4a, p4b
        Axes: 0, outDur, 0, yTop
        Paint rectangle: "{0.98, 0.98, 0.99}", 0, outDur, 0, yTop
        Paint rectangle: "{0.99, 0.93, 0.90}", 0, outDur, 1, yTop
        Colour: "{0.70, 0.45, 0.40}"
        Dotted line
        Draw line: 0, 1, outDur, 1
        Solid line
        Colour: "{0.20, 0.40, 0.80}"
        Line width: 1.5
        xa = Get value: 1, "time"
        ya = Get value: 1, "dist"
        for iR from 2 to nTr
            xb = Get value: iR, "time"
            yb = Get value: iR, "dist"
            Draw line: xa, ya, xb, yb
            xa = xb
            ya = yb
        endfor
        Line width: 1
        Colour: "Black"
        Text top: "no", "##Decoder distance from the training cloud## — nearest-patch distance in multiples of r90; shaded = extrapolation"
        p4name$ = "Dist. / r90"
        Select inner viewport: xL, xR, p4a, p4b
        Axes: 0, outDur, 0, yTop
    else
        Select inner viewport: xL, xR, p4a, p4b
        Axes: 0, outDur, 0, dur
        Paint rectangle: "{0.98, 0.98, 0.99}", 0, outDur, 0, dur
        selectObject: trTab
        if rendering_mode = 2
            for iR from 1 to nTr
                xb = Get value: iR, "time"
                yb = Get value: iR, "donor"
                Paint circle (mm): "{0.20, 0.40, 0.80}", xb, min(yb, dur), 0.35
            endfor
            Colour: "Black"
            Text top: "no", "##Nearest event## — source position read at each output time (vertical jumps = identity changes)"
        else
            for iR from 1 to nTr
                xb = Get value: iR, "time"
                for k from 1 to nNeigh
                    yb = Get value: iR, "n" + string$(k)
                    wk = Get value: iR, "w" + string$(k)
                    gl = 0.85 - 0.80 * min(1, wk * 1.6)
                    Paint circle (mm): "{" + fixed$(gl, 3) + ", " + fixed$(gl, 3) + ", " + fixed$(min(1, gl + 0.12), 3) + "}", xb, min(yb, dur), 0.30
                endfor
            endfor
            Colour: "Black"
            Text top: "no", "##Barycentric neighbours## — source positions of the K nearest patches; darker = larger amplitude coefficient"
        endif
        p4name$ = "Source (s)"
        Select inner viewport: xL, xR, p4a, p4b
        Axes: 0, outDur, 0, dur
        yTop = dur
    endif
    Draw inner box
    @timeMarks: 0
    @niceStep: yTop, 3
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: p4a, p4b, p4name$
    removeObject: trTab

    # ================= Panel 5: output waveform =================
    selectObject: result
    wMax = Get maximum: 0, 0, "None"
    wMin = Get minimum: 0, 0, "None"
    wR = max(abs(wMax), abs(wMin), 1e-6) * 1.05
    Font size: 7
    Select inner viewport: xL, xR, p5a, p5b
    Axes: 0, outDur, -wR, wR
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, outDur, -wR, wR
    Select inner viewport: xL, xR, p5a, p5b
    Colour: "{0.20, 0.40, 0.80}"
    Draw: 0, 0, -wR, wR, "no", "Curve"
    Select inner viewport: xL, xR, p5a, p5b
    Axes: 0, outDur, -wR, wR
    Colour: "Black"
    Text top: "no", "##Output## — " + fixed$(outDur, 2) + " s, peak " + fixed$(outPeak, 3) + ", RMS " + fixed$(outRms, 4)
    Select inner viewport: xL, xR, p5a, p5b
    Axes: 0, outDur, -wR, wR
    Draw inner box
    @timeMarks: 1
    Text bottom: "yes", "Time (s)"
    @railLabel: p5a, p5b, "Output"

    # ================= Summary strip =================
    Font size: 7
    Select inner viewport: xL, xR, s0, s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.86, "half", "##Summary##"
    Font size: 6
    Select inner viewport: xL, xR, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    line1$ = "Model: numpy beta-VAE on STFT log-band patches  |  d = " + string$(latent_dimensions) + " (" + string$(activeDims) + "/" + string$(latent_dimensions) + " VAE dims active by KL)  |  " + string$(nPatches) + " patches × " + fixed$(patchMsEff, 0) + " ms  |  rec. error " + fixed$(recDb, 1) + " dB  |  " + string$(nClusters) + " clusters"
    line2$ = "Pattern: " + presetName$ + "  |  " + string$(nGlobal) + " global events  |  output " + fixed$(outDur, 2) + " s (" + ended$ + ")  |  seed " + string$(seedUsed) + "  |  interpolation " + interpUsed$
    line3$ = "Navigation: boundary " + boundary_mode$ + ", excursion " + fixed$(excursion, 2) + "  |  raw outside box " + fixed$(outsidePct, 1) + "\%  |  beyond r90 " + fixed$(farPct, 1) + "\%  |  render " + rendering_mode$
    if rendering_mode = 1
        line3$ = line3$ + " — spectral-envelope decoder (" + detailLabel$ + ")"
    endif
    @sanitize: line1$
    Text: 0.012, "left", 0.66, "half", sanitize.out$
    Text: 0.012, "left", 0.49, "half", replace$(line2$, "_", "\_ ", 0)
    Text: 0.012, "left", 0.32, "half", line3$
    # Pbind text, wrapped over two lines
    @sanitize: pbindFlat$
    pbS$ = sanitize.out$
    Colour: "{0.35, 0.35, 0.50}"
    Font size: 5
    Select inner viewport: xL, xR, s0, s1
    Axes: 0, 1, 0, 1
    if length(pbindFlat$) > 190
        @wrapPoint: pbindFlat$, 190
        @sanitize: left$(pbindFlat$, wrapPoint.at)
        Text: 0.012, "left", 0.17, "half", sanitize.out$
        restP$ = mid$(pbindFlat$, wrapPoint.at + 1, length(pbindFlat$) - wrapPoint.at)
        if length(restP$) > 200
            restP$ = left$(restP$, 197) + "..."
        endif
        @sanitize: restP$
        Text: 0.012, "left", 0.06, "half", sanitize.out$
    else
        Text: 0.012, "left", 0.12, "half", pbS$
    endif
    Select inner viewport: xL, xR, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Select outer viewport: 0, 8, 0, canvasH
endproc

procedure wrapPoint: .s$, .max
    # last ", " or space at or before .max characters
    .at = .max
    .found = 0
    .i = .max
    while .i > .max / 2 and .found = 0
        if mid$(.s$, .i, 1) = " " or mid$(.s$, .i, 1) = ","
            .at = .i
            .found = 1
        endif
        .i = .i - 1
    endwhile
endproc
