# ============================================================
# Praat AudioTools - Scattering_Texture_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.1 (2026) - calibrated direct synthesis, parallel segments
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Hybrid Systems. Generates a NEW waveform whose wavelet scattering
#   statistics match a (optionally transformed) target taken from the
#   selected Sound. The result keeps selected multiscale texture - band
#   energy, envelope modulation, coarse dynamics - while exact waveform,
#   phase, pitch identity and fine timing are released.
#
#   Place in the wavelet line of the suite:
#     CWT Scalogram                 what multiscale components exist?
#     CWT Granular Resampler        use that structure to control another sound
#     Scattering Texture Generator  generate a new waveform that keeps
#                                   selected multiscale relationships
#
#   Scattering orders (Kymatio Morlet filters, averaging scale T = 2^J):
#     Order 0 = |x| * phi_J            coarse energy envelope
#     Order 1 = |x * psi1| * phi_J     wavelet-band energy (what the CWT shows)
#     Order 2 = ||x * psi1| * psi2| * phi_J, matched as S2/S1: modulation of
#               each band envelope - pulsation, tremolo, roughness,
#               articulation density. This is what scattering adds.
#
#   The deliverable is a Sound in the object list:
#       [name]_ScatteringTexture   (or [name]_<Preset>, e.g. _ModulationGhost)
#   Temporary files are deleted after the run.
#
#   Pipeline (single script, no chaining):
#     [Sound] -> Stage 1  mono 24-bit export                     (Praat)
#             -> Stage 2  scattering target + transformation     (engine)
#             -> Stage 3  calibrated direct synthesis per segment
#                         (+ L-BFGS refinement for Standard/High) (engine)
#             -> Stage 4  import, name, Info report              (Praat)
#             -> Stage 5  analysis figure                        (Praat Picture)
#             -> [name]_ScatteringTexture
#
#   Not a neural model: no training, no downloaded weights, CPU only.
#
# v0.3.1 (cleanup, safety, semantics; external review + user report):
#   - Temporary folders are now REMOVED after every run. Praat deleted the
#     files but cannot delete a folder on Windows, so every run left an empty
#     AudioTools_STG_* folder behind. The engine now removes it (--cleanup)
#     and also sweeps AudioTools_STG_* folders older than 10 minutes, both in
#     the temp folder and in the home folder where earlier versions put them.
#   - Work folder moved to the real system temp folder (%TEMP% on Windows);
#     temporaryDirectory$ resolved to the user home folder there.
#   - Worker processes use ONE FFT thread each. With several processes each
#     spawning all-core FFT threads the machine was oversubscribed - the
#     likely cause of Fine mode "still processing". If worker processes
#     cannot start, the engine falls back to one process and says so.
#   - Final peak check after restoring the export pre-scale: an input above
#     0.99 could previously undo the backend peak protection.
#   - Quality menu names its bandwidth: Preview (16 kHz internal), Standard
#     (22.05 kHz internal), High (full bandwidth).
#   - "Randomness" renamed Spectral randomization: it blends the carrier
#     spectrum from the source's exact spectrum to a smoothed, pitch-free
#     envelope; phases are random at every setting.
#   - Target operations are labelled [preset, always] or [x Transformation],
#     so a preset's own operations are visible at Transformation 0.
#   - Figure: order 2 is "not represented as a separate layer in a CWT
#     scalogram" (was "not visible in a CWT", which overstated it).
#   - Engine warns when Kymatio is not 0.3.x (it uses Kymatio's internal
#     filter_bank module).
#   - New validate_scattering.py: end-to-end checks on synthetic sounds
#     (15 checks, all passing).
#
# v0.3 (practicality; the v0.2 optimizer took ~4 min on a 17 s file):
#   - The waveform is BUILT from the target instead of optimized from noise.
#     Each first-order band = noise carrier with the source band spectrum x
#     an envelope that follows order 1, modulated by noise band-limited with
#     the analysis' own second-order filters. Five analysis-only rounds
#     calibrate band levels and modulation depths.
#   - Preview is direct synthesis only; Standard / High add 15 / 150 L-BFGS
#     refinement iterations.
#   - Segments run in parallel worker processes (one per core, up to 8) and
#     are joined with equal-power crossfades. Parallel and single-process
#     output verified bit-identical.
#   - Measured on a 17 s file, one core: Preview 55 s -> 17 s at similar loss;
#     Standard 55 s with lower loss than v0.2 Preview.
#   - First draft used an exponential (log-normal) envelope: crest factor
#     32-36 dB against 18 dB in the source, i.e. clicks. Replaced by bounded
#     linear modulation; now 14-15 dB, no limiting. Cost: very deep
#     modulation is reached only partly (7 Hz tremolo: -12.6 dB per band
#     against -1.2 dB in the source).
#   - Python is found automatically (house convention); the Python command
#     field is gone. The engine is looked up in plugin_AudioTools/py/.
#
# v0.2 (speed):
#   - Filters applied only on their non-negligible frequency bins; 1.7-2.3x
#     faster per loss + gradient evaluation, same results to ~1e-10.
#   - Progress log every 10 iterations with an estimate of time left.
#
# v0.1:
#   - First version: Kymatio filter bank re-implemented in NumPy with its
#     exact adjoint (forward matches Kymatio to 1e-16, gradient matches
#     finite differences to 1e-7), L-BFGS texture matching, six presets,
#     target transformations, house-style figure.
#   - Order 0 uses |x| * phi_J: Kymatio's x * phi_J is ~0 for audio.
#
# Known limit:
#   Time scattering does not constrain the PHASE of modulations across
#   bands. A tremolo keeps its rate and depth per band but loses its
#   cross-band synchrony (measured: 7 Hz envelope correlation between two
#   bands 0.96 in the source, 0.25 in the output).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Requires: Praat 6.1+ (tested 6.1.38, 6.4.06, 7.0; asks for full trust on
#           7.0), Python 3 with numpy + scipy + kymatio
#           (python -m pip install numpy scipy kymatio).
# ============================================================

form Scattering Texture Generator v0.3.1
    comment Presets set the three Preserve weights; Custom uses the values below
    optionmenu Preset: 1
        option Custom
        option Spectral Skeleton
        option Temporal Texture
        option Modulation Ghost
        option Structure Without Identity
        option Second-Order Reconstruction
        option Radical Texture
    optionmenu Texture_scale: 2
        option Fine (T ~ 46 ms)
        option Medium (T ~ 186 ms)
        option Broad (T ~ 743 ms)
    optionmenu Frequency_detail: 2
        option Low (Q = 4)
        option Medium (Q = 8)
        option High (Q = 12)
    real Preserve_global_envelope_(%) 40
    real Preserve_spectral_structure_(%) 60
    real Preserve_temporal_modulation_(%) 100
    real Texture_transformation_(%) 30
    real Spectral_randomization_(%) 50
    optionmenu Reconstruction_quality: 1
        option Preview (16 kHz internal)
        option Standard (22.05 kHz internal)
        option High (full bandwidth)
    integer Random_seed_(0_=_new_variation) 1
    boolean Draw_visualization 1
    boolean Play 1
endform

# ------------------------------------------------------------
# INPUT
# ------------------------------------------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound."
endif
source = selected("Sound")
sourceName$ = selected$("Sound")
selectObject: source
srcStart = Get start time
srcDur = Get total duration
srcSr = Get sampling frequency
srcCh = Get number of channels
if srcDur < 0.02
    exitScript: "The Sound is shorter than 20 ms - too short for a scattering analysis."
endif

scaleName$[1] = "Fine"
scaleName$[2] = "Medium"
scaleName$[3] = "Broad"
detailName$[1] = "Low"
detailName$[2] = "Medium"
detailName$[3] = "High"
qualityName$[1] = "Preview"
qualityName$[2] = "Standard"
qualityName$[3] = "High"
presetTag$[1] = "ScatteringTexture"
presetTag$[2] = "SpectralSkeleton"
presetTag$[3] = "TemporalTexture"
presetTag$[4] = "ModulationGhost"
presetTag$[5] = "StructureWithoutIdentity"
presetTag$[6] = "SecondOrderReconstruction"
presetTag$[7] = "RadicalTexture"

preserve_global_envelope = min(100, max(0, preserve_global_envelope))
preserve_spectral_structure = min(100, max(0, preserve_spectral_structure))
preserve_temporal_modulation = min(100, max(0, preserve_temporal_modulation))
texture_transformation = min(100, max(0, texture_transformation))
randomness = min(100, max(0, spectral_randomization))
if random_seed < 0
    random_seed = 0
endif

# ------------------------------------------------------------
# BACKEND LOCATION + PERMISSIONS
# ------------------------------------------------------------
# ---- OS-SPECIFIC PYTHON DISCOVERY (house convention) ----
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

# ---- ENGINE PATH: plugin_AudioTools/py/, else next to this script ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)
enginePath$ = pluginDir$ + "py/scattering_texture_engine.py"
if not fileReadable(enginePath$)
    enginePath$ = defaultDirectory$ + "/scattering_texture_engine.py"
endif
if not fileReadable(enginePath$)
    exitScript: "Cannot find Python script: scattering_texture_engine.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif
if praatVersion >= 7000
    trustOk = askForTrust ()
    if trustOk = 0
        exitScript: "This tool writes temporary files and runs Python; Praat 7 needs FULL TRUST for that."
    endif
endif

# ------------------------------------------------------------
# EXPORT (mono, 24-bit; pre-scale only if the Sound would clip)
# ------------------------------------------------------------
# Work folder in the real system temp folder (on Windows temporaryDirectory$
# can resolve to the user home folder, where earlier versions left folders)
tmpBase$ = temporaryDirectory$
if windows
    envTemp$ = environment$("TEMP")
    if envTemp$ <> ""
        tmpBase$ = replace$(envTemp$, "\", "/", 0)
    endif
endif
tmpDir$ = tmpBase$ + "/AudioTools_STG_" + string$(randomInteger(100000, 999999))
createDirectory: tmpDir$
inWav$ = tmpDir$ + "/stg_in.wav"
outWav$ = tmpDir$ + "/stg_out.wav"
reportPath$ = tmpDir$ + "/report.txt"

selectObject: source
if srcCh > 1
    monoIn = Convert to mono
else
    monoIn = Copy: "stg_mono"
endif
inPeak = Get absolute extremum: 0, 0, "None"
preScale = 1
if inPeak > 0.99
    preScale = 0.99 / inPeak
    Multiply: preScale
endif
Save as 24-bit WAV file: inWav$
if preScale <> 1
    Multiply: 1 / preScale
endif
Rename: "stg_analysis_copy"

# ------------------------------------------------------------
# RUN BACKEND
# ------------------------------------------------------------
writeInfoLine: "Scattering Texture Generator - running Python backend"
appendInfoLine: "  analyzing multiscale structure -> extracting second-order modulation"
appendInfoLine: "  -> building texture target -> optimizing new waveform"
appendInfoLine: "  (", qualityName$[reconstruction_quality], " quality; Praat looks frozen until the backend finishes)"
appendInfoLine: "  Progress (updated every 10 iterations, with time left): " + tmpDir$ + "/engine_log.txt"

nocheck runSubprocess: pythonCmd$, enginePath$,
... "--in", inWav$, "--out", outWav$, "--workdir", tmpDir$,
... "--preset", preset$, "--scale", scaleName$[texture_scale], "--detail", detailName$[frequency_detail],
... "--w0", fixed$(preserve_global_envelope, 3), "--w1", fixed$(preserve_spectral_structure, 3),
... "--w2", fixed$(preserve_temporal_modulation, 3), "--transform", fixed$(texture_transformation, 3),
... "--randomness", fixed$(randomness, 3), "--quality", qualityName$[reconstruction_quality],
... "--seed", string$(random_seed)

if not fileReadable(reportPath$)
    @cleanup
    removeObject: monoIn
    exitScript: "The Python backend did not run (Python command: " + pythonCmd$ + ")." + newline$ + "Check that Python 3 is installed and on the PATH, and that numpy, scipy and kymatio" + newline$ + "are installed for it:  " + pythonCmd$ + " -m pip install numpy scipy kymatio"
endif

# ------------------------------------------------------------
# READ REPORT (key=value lines)
# ------------------------------------------------------------
repStrings = Read Strings from raw text file: reportPath$
nRep = Get number of strings
for i to nRep
    line$ = Get string: i
    eq = index(line$, "=")
    if eq > 0
        repKey$[i] = left$(line$, eq - 1)
        repVal$[i] = mid$(line$, eq + 1, length(line$) - eq)
    else
        repKey$[i] = ""
        repVal$[i] = ""
    endif
endfor
removeObject: repStrings

@rep: "status"
if rep$ <> "OK" or not fileReadable(outWav$)
    @rep: "message"
    errMsg$ = rep$
    @cleanup
    removeObject: monoIn
    exitScript: "Scattering backend failed: " + errMsg$
endif

# ------------------------------------------------------------
# IMPORT RESULT
# ------------------------------------------------------------
res = Read from file: outWav$
if preScale <> 1
    Multiply: 1 / preScale
endif
# final safety: restoring the export pre-scale must not undo the backend
# peak protection (attenuate only, never boost)
finalLimitDb = 0
chkPeak = Get absolute extremum: 0, 0, "None"
if chkPeak > 0.98
    finalLimitDb = 20 * log10(0.98 / chkPeak)
    Multiply: 0.98 / chkPeak
endif
resDur = Get total duration
resSr = Get sampling frequency
if abs(resDur - srcDur) > 0.5 / srcSr or resSr <> srcSr
    removeObject: res, monoIn
    @cleanup
    exitScript: "Backend returned a Sound of the wrong length or rate - nothing imported."
endif
Shift times to: "start time", srcStart
outName$ = replace_regex$(sourceName$ + "_" + presetTag$[preset], "[^A-Za-z0-9_]", "_", 0)
Rename: outName$
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0

# ------------------------------------------------------------
# INFO
# ------------------------------------------------------------
@rep: "silent_input"
silentIn = rep$ = "1"
writeInfoLine: "=== Scattering Texture Generator v0.3.1 ==="
appendInfoLine: "Source: ", sourceName$, " (", srcCh, " ch -> mono analysis, ", fixed$(srcDur, 3), " s, ", srcSr, " Hz)"
appendInfoLine: "Output: ", outName$, " (", fixed$(resDur, 3), " s, peak ", fixed$(outPeak, 3), ", RMS matched to source)"
if silentIn
    appendInfoLine: "Silent input: output is silence of the same duration."
else
    @rep: "preset"
    p$ = rep$
    @rep: "w0"
    w0$ = rep$
    @rep: "w1"
    w1$ = rep$
    @rep: "w2"
    w2$ = rep$
    appendInfoLine: "Preset: ", p$, " | weights order0/order1/order2 = ", w0$, " / ", w1$, " / ", w2$
    @rep: "transform"
    t$ = rep$
    @rep: "randomness"
    r$ = rep$
    @rep: "seed"
    seedUsed$ = rep$
    appendInfoLine: "Texture transformation ", t$, " % | spectral randomization ", r$, " % | seed ", seedUsed$, " (reuse it to reproduce this realization)"
    @rep: "J"
    j$ = rep$
    @rep: "T_ms"
    tms$ = rep$
    @rep: "Q1"
    q1$ = rep$
    @rep: "Q2"
    q2$ = rep$
    @rep: "n_order1"
    n1$ = rep$
    @rep: "n_order2"
    n2$ = rep$
    appendInfoLine: "Scattering: J = ", j$, " (T = ", fixed$(number(tms$), 0), " ms), Q = (", q1$, ", ", q2$, "), ", n1$, " first-order + ", n2$, " second-order paths"
    @rep: "mod_rate_min_hz"
    mr1 = number(rep$)
    @rep: "mod_rate_max_hz"
    mr2 = number(rep$)
    appendInfoLine: "Order-2 modulation rates covered: ", fixed$(mr1, 1), " - ", fixed$(mr2, 0), " Hz; slower changes live in the order-1 trajectory"
    @rep: "working_sr"
    wsr$ = rep$
    @rep: "band_limit_hz"
    bl$ = rep$
    @rep: "segments"
    sg$ = rep$
    @rep: "iterations_per_segment"
    it$ = rep$
    @rep: "calibration_rounds"
    cr$ = rep$
    @rep: "workers"
    wk$ = rep$
    appendInfoLine: "Working rate ", wsr$, " Hz (output band-limited to ", bl$, " Hz) | ", sg$, " segment(s) on ", wk$, " process(es)"
    appendInfoLine: "Synthesis: direct, ", cr$, " calibration rounds; refinement: up to ", it$, " L-BFGS iterations per segment"
    @rep: "loss_reduction_pct"
    appendInfoLine: "Texture-matching loss reduced by ", fixed$(number(rep$), 1), " %"
    @rep: "n_ops"
    nOps = number(rep$)
    if nOps > 0
        for k to nOps
            @rep: "op_" + string$(k)
            appendInfoLine: "  target op: ", rep$
        endfor
    else
        appendInfoLine: "  target: source scattering, untransformed"
    endif
    @rep: "warning"
    if rep$ <> "none"
        appendInfoLine: "WARNING: ", rep$
    endif
    if finalLimitDb < 0
        appendInfoLine: "Output attenuated by ", fixed$(-finalLimitDb, 1), " dB after restoring the input scale (peak protection)"
    endif
    appendInfoLine: "Target ops marked [preset, always] belong to the preset and apply even at Transformation 0."
    appendInfoLine: "Note: order 0 uses |x| * phi_J (Kymatio x * phi_J is ~0 for audio); order 2 is matched as S2/S1."
    appendInfoLine: "      Time scattering does not constrain the PHASE of modulations across bands:"
    appendInfoLine: "      a tremolo keeps its rate and depth per band but loses its cross-band synchrony."
endif

# ------------------------------------------------------------
# VISUALIZATION
# ------------------------------------------------------------
if draw_visualization and not silentIn
    @drawFigure
endif

@cleanup
removeObject: monoIn
selectObject: res
if play
    Play
endif

# ============================================================
# PROCEDURES
# ============================================================
procedure rep: .k$
    rep$ = ""
    for .i to nRep
        if repKey$[.i] = .k$
            rep$ = repVal$[.i]
        endif
    endfor
endproc

procedure sanitize: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    san$ = .s$
endproc

procedure cleanup
    # Praat can delete files but not folders on Windows, so the engine removes
    # the folder (and sweeps AudioTools_STG_* folders older than 10 minutes,
    # both in the temp folder and in the old home-folder location)
    .files = Create Strings as file list: "stgfiles", tmpDir$ + "/*"
    .n = Get number of strings
    for .i to .n
        .f$ = Get string: .i
        nocheck deleteFile: tmpDir$ + "/" + .f$
    endfor
    removeObject: .files
    nocheck deleteFile: tmpDir$
    nocheck runSubprocess: pythonCmd$, enginePath$, "--cleanup", tmpDir$, temporaryDirectory$
endproc

procedure niceLeft: .lo, .hi
    # labelled marks on round 1-2-5 steps (never at the data-derived extremes)
    .raw = (.hi - .lo) / 4
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
    Marks left every: 1, .step, "yes", "yes", "no"
endproc

procedure niceBottom: .lo, .hi
    .raw = (.hi - .lo) / 4
    .p = 10 ^ floor(log10(max(.raw, 1e-9)))
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
    Marks bottom every: 1, .step, "yes", "yes", "no"
endproc

procedure heatColour: .v
    # 0 -> pale grey-blue, 0.5 -> mid blue, 1 -> deep orange-red
    .v = min(1, max(0, .v))
    if .v < 0.5
        .a = .v / 0.5
        .r = 0.95 + (0.25 - 0.95) * .a
        .g = 0.95 + (0.45 - 0.95) * .a
        .b = 0.97 + (0.80 - 0.97) * .a
    else
        .a = (.v - 0.5) / 0.5
        .r = 0.25 + (0.85 - 0.25) * .a
        .g = 0.45 + (0.30 - 0.45) * .a
        .b = 0.80 + (0.10 - 0.80) * .a
    endif
    heat$ = "{" + fixed$(.r, 2) + ", " + fixed$(.g, 2) + ", " + fixed$(.b, 2) + "}"
endproc

procedure sectionHeader: .y, .text$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y - 0.09, .y + 0.09
    Axes: 0, 1, 0, 1
    Colour: {0.15, 0.15, 0.15}
    Text: 0, "left", 0.5, "half", .text$
endproc

procedure matrixRange: .m, .col1, .col2
    selectObject: .m
    .nr = Get number of rows
    mrLo = 1e30
    mrHi = -1e30
    for .r to .nr
        for .c from .col1 to .col2
            .v = Get value in cell: .r, .c
            if .v > -998
                mrLo = min(mrLo, .v)
                mrHi = max(mrHi, .v)
            endif
        endfor
    endfor
endproc

procedure logTicks: .lo, .hi, .axis$
    # labelled 1-2-5 ticks on a log10 axis between frequencies .lo and .hi (Hz)
    for .e from -1 to 5
        for .m to 3
            if .m = 1
                .f = 10 ^ .e
            elsif .m = 2
                .f = 2 * 10 ^ .e
            else
                .f = 5 * 10 ^ .e
            endif
            if .f >= .lo and .f <= .hi
                if .f >= 1000
                    .lab$ = fixed$(.f / 1000, 0) + "k"
                elsif .f >= 1
                    .lab$ = fixed$(.f, 0)
                else
                    .lab$ = fixed$(.f, 1)
                endif
                if .axis$ = "bottom"
                    One mark bottom: log10(.f), "no", "yes", "no", .lab$
                else
                    One mark left: log10(.f), "no", "yes", "no", .lab$
                endif
            endif
        endfor
    endfor
endproc

procedure drawFigure
    Erase all
    canvasW = 8
    canvasH = 10.1
    grey$ = "{0.55, 0.55, 0.55}"
    tgtC$ = "{0.20, 0.40, 0.80}"
    outC$ = "{0.80, 0.25, 0.20}"
    o0C$ = "{0.45, 0.45, 0.45}"
    o1C$ = "{0.20, 0.40, 0.80}"
    o2C$ = "{0.85, 0.45, 0.10}"

    # ---- data -----------------------------------------------------------
    m0 = Read Matrix from raw text file: tmpDir$ + "/order0_series.txt"
    m1 = Read Matrix from raw text file: tmpDir$ + "/order1_profile.txt"
    m2r = Read Matrix from raw text file: tmpDir$ + "/order2_rate_profile.txt"
    gS = Read Matrix from raw text file: tmpDir$ + "/mod_src.txt"
    gT = Read Matrix from raw text file: tmpDir$ + "/mod_tgt.txt"
    gO = Read Matrix from raw text file: tmpDir$ + "/mod_out.txt"
    gA = Read Matrix from raw text file: tmpDir$ + "/mod_axes.txt"
    mh = Read Matrix from raw text file: tmpDir$ + "/loss_history.txt"

    # ---- title ------------------------------------------------------------
    Font size: 13
    Select inner viewport: 0.6, 7.7, 0.10, 0.42
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Scattering Texture Generator##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.42, 0.62
    Axes: 0, 1, 0, 1
    Colour: {0.30, 0.30, 0.30}
    @sanitize: sourceName$
    Text: 0.5, "centre", 0.5, "half", "Source: " + san$ + "   |   wavelet scattering + structural transformation + calibrated waveform synthesis (no neural model)"

    # ---- 1. SOURCE --------------------------------------------------------
    if srcCh > 1
        @sectionHeader: 0.80, "##1  SOURCE##   mono analysis copy of the " + string$(srcCh) + "-channel input"
    else
        @sectionHeader: 0.80, "##1  SOURCE##"
    endif
    selectObject: monoIn
    sPk = Get absolute extremum: 0, 0, "None"
    selectObject: res
    rPk = Get absolute extremum: 0, 0, "None"
    wRange = max(sPk, rPk)
    if wRange <= 0
        wRange = 1
    endif
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.92, 1.52
    Axes: srcStart, srcStart + srcDur, -wRange, wRange
    Colour: grey$
    selectObject: monoIn
    Draw: srcStart, srcStart + srcDur, -wRange, wRange, "no", "Curve"
    Select inner viewport: 0.6, 7.7, 0.92, 1.52
    Axes: srcStart, srcStart + srcDur, -wRange, wRange
    Colour: "Black"
    Draw inner box
    Marks left every: 1, wRange, "no", "yes", "no"

    # ---- 2. MULTISCALE ANALYSIS -------------------------------------------
    @sectionHeader: 1.76, "##2  MULTISCALE ANALYSIS##   grey = source   blue = target (after transformation)   red = new realization"
    # order 0 -----------------------------------------------------------
    selectObject: m0
    n0 = Get number of rows
    @matrixRange: m0, 2, 4
    y0lo = mrLo - 3
    y0hi = mrHi + 3
    Font size: 7
    Select inner viewport: 0.6, 2.7, 2.0, 3.1
    Axes: 0, srcDur, y0lo, y0hi
    Colour: "Black"
    Text top: "no", "##Order 0##  envelope |x| * phi (dB)"
    for col from 2 to 4
        if col = 2
            Colour: grey$
            Line width: 3
        elsif col = 3
            Colour: tgtC$
            Line width: 1
        else
            Colour: outC$
            Line width: 1
        endif
        Select inner viewport: 0.6, 2.7, 2.0, 3.1
        Axes: 0, srcDur, y0lo, y0hi
        selectObject: m0
        for r from 2 to n0
            ta = Get value in cell: r - 1, 1
            va = Get value in cell: r - 1, col
            tb = Get value in cell: r, 1
            vb = Get value in cell: r, col
            Draw line: min(ta, srcDur), va, min(tb, srcDur), vb
        endfor
    endfor
    Line width: 1
    Select inner viewport: 0.6, 2.7, 2.0, 3.1
    Axes: 0, srcDur, y0lo, y0hi
    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    @niceLeft: y0lo, y0hi
    Text bottom: "yes", "Time (s)"

    # order 1 -----------------------------------------------------------
    selectObject: m1
    n1r = Get number of rows
    fLo = 40
    fHi = Get value in cell: 1, 1
    @matrixRange: m1, 2, 4
    y1hi = mrHi + 3
    y1lo = max(mrLo, mrHi - 70) - 3
    Font size: 7
    Select inner viewport: 3.2, 5.3, 2.0, 3.1
    Axes: log10(fLo), log10(fHi), y1lo, y1hi
    Colour: "Black"
    Text top: "no", "##Order 1##  band energy (dB) = CWT-like"
    for col from 2 to 4
        if col = 2
            Colour: grey$
            Line width: 3
        elsif col = 3
            Colour: tgtC$
            Line width: 1
        else
            Colour: outC$
            Line width: 1
        endif
        Select inner viewport: 3.2, 5.3, 2.0, 3.1
        Axes: log10(fLo), log10(fHi), y1lo, y1hi
        selectObject: m1
        for r from 2 to n1r
            fa = Get value in cell: r - 1, 1
            fb = Get value in cell: r, 1
            if fa >= fLo and fb >= fLo
                va = Get value in cell: r - 1, col
                vb = Get value in cell: r, col
                Draw line: log10(fa), min(y1hi, max(y1lo, va)), log10(fb), min(y1hi, max(y1lo, vb))
            endif
        endfor
    endfor
    Line width: 1
    Select inner viewport: 3.2, 5.3, 2.0, 3.1
    Axes: log10(fLo), log10(fHi), y1lo, y1hi
    Colour: "Black"
    Draw inner box
    @logTicks: fLo, fHi, "bottom"
    @niceLeft: y1lo, y1hi
    Text bottom: "yes", "Band centre (Hz)"

    # order 2 (compact: modulation spectrum averaged over carriers) -------
    selectObject: m2r
    n2r = Get number of rows
    rLo = Get value in cell: 1, 1
    rHi = Get value in cell: n2r, 1
    @matrixRange: m2r, 2, 4
    y2lo = mrLo - 3
    y2hi = mrHi + 3
    Font size: 7
    Select inner viewport: 5.8, 7.7, 2.0, 3.1
    Axes: log10(rLo), log10(rHi), y2lo, y2hi
    Colour: "Black"
    Text top: "no", "##Order 2##  modulation depth S2/S1 (dB)"
    for col from 2 to 4
        if col = 2
            Colour: grey$
            Line width: 3
        elsif col = 3
            Colour: tgtC$
            Line width: 1
        else
            Colour: outC$
            Line width: 1
        endif
        Select inner viewport: 5.8, 7.7, 2.0, 3.1
        Axes: log10(rLo), log10(rHi), y2lo, y2hi
        selectObject: m2r
        for r from 2 to n2r
            fa = Get value in cell: r - 1, 1
            fb = Get value in cell: r, 1
            va = Get value in cell: r - 1, col
            vb = Get value in cell: r, col
            Draw line: log10(fa), va, log10(fb), vb
        endfor
    endfor
    Line width: 1
    Select inner viewport: 5.8, 7.7, 2.0, 3.1
    Axes: log10(rLo), log10(rHi), y2lo, y2hi
    Colour: "Black"
    Draw inner box
    @logTicks: rLo, rHi, "bottom"
    @niceLeft: y2lo, y2hi
    Text bottom: "yes", "Modulation rate (Hz)"

    # ---- 3. WHAT SCATTERING ADDS ------------------------------------------
    @sectionHeader: 3.66, "##3  WHAT SCATTERING ADDS##   order-2 modulation per carrier band and rate - not represented as a separate layer in a CWT scalogram"
    selectObject: gA
    cLo = Get value in cell: 1, 1
    cHi = Get value in cell: 1, 2
    aLo = Get value in cell: 1, 3
    aHi = Get value in cell: 1, 4
    @matrixRange: gS, 1, 7
    hLo = mrLo
    hHi = mrHi
    @matrixRange: gT, 1, 7
    hLo = min(hLo, mrLo)
    hHi = max(hHi, mrHi)
    @matrixRange: gO, 1, 7
    hLo = min(hLo, mrLo)
    hHi = max(hHi, mrHi)
    if hHi <= hLo
        hHi = hLo + 1
    endif
    selectObject: gS
    nGr = Get number of rows
    nGc = Get number of columns
    for panel to 3
        if panel = 1
            gm = gS
            x1 = 0.6
            x2 = 2.7
            cap$ = "Source"
        elsif panel = 2
            gm = gT
            x1 = 3.2
            x2 = 5.3
            cap$ = "Target (after transformation)"
        else
            gm = gO
            x1 = 5.8
            x2 = 7.7
            cap$ = "New realization (achieved)"
        endif
        Font size: 7
        Select inner viewport: x1, x2, 3.85, 4.95
        Axes: log10(aLo), log10(aHi), log10(cLo), log10(cHi)
        Colour: "Black"
        Text top: "no", "##" + cap$ + "##"
        Select inner viewport: x1, x2, 3.85, 4.95
        Axes: 0, nGc, 0, nGr
        selectObject: gm
        for r to nGr
            for c to nGc
                v = Get value in cell: r, c
                if v > -998
                    @heatColour: (v - hLo) / (hHi - hLo)
                else
                    heat$ = "{1.00, 1.00, 1.00}"
                endif
                Paint rectangle: heat$, c - 1, c, r - 1, r
            endfor
        endfor
        Select inner viewport: x1, x2, 3.85, 4.95
        Axes: log10(aLo), log10(aHi), log10(cLo), log10(cHi)
        Colour: "Black"
        Draw inner box
        @logTicks: aLo, aHi, "bottom"
        if panel = 1
            @logTicks: cLo, cHi, "left"
            Text left: "yes", "Carrier (Hz)"
        endif
        Text bottom: "yes", "Modulation rate (Hz)"
    endfor
    Font size: 6
    Select inner viewport: 0.6, 7.7, 5.40, 5.50
    Axes: 0, 1, 0, 1
    Colour: {0.30, 0.30, 0.30}
    Text: 1, "right", 0.5, "half", "colour: " + fixed$(hLo, 0) + " dB (pale) ... " + fixed$(hHi, 0) + " dB (red), normalized S2/S1   |   white = rate above that band bandwidth (no path)"

    # ---- 4. TEXTURE CONSTRAINTS + ITERATIVE MATCHING ----------------------
    @sectionHeader: 5.58, "##4  TEXTURE CONSTRAINTS  +  ITERATIVE MATCHING##"
    @rep: "w0"
    bw0 = number(rep$)
    @rep: "w1"
    bw1 = number(rep$)
    @rep: "w2"
    bw2 = number(rep$)
    @rep: "transform"
    btr = number(rep$)
    @rep: "randomness"
    brn = number(rep$)
    Font size: 7
    Select inner viewport: 0.6, 3.6, 5.92, 6.82
    Axes: -75, 118, 0, 5
    Colour: "Black"
    Text top: "no", "##Weights and amounts## (0-100)"
    for b to 5
        if b = 1
            bv = bw0
            bl$ = "Order 0  envelope"
            bc$ = o0C$
        elsif b = 2
            bv = bw1
            bl$ = "Order 1  spectrum"
            bc$ = o1C$
        elsif b = 3
            bv = bw2
            bl$ = "Order 2  modulation"
            bc$ = o2C$
        elsif b = 4
            bv = btr
            bl$ = "Transformation"
            bc$ = "{0.35, 0.60, 0.35}"
        else
            bv = brn
            bl$ = "Spectral random."
            bc$ = "{0.60, 0.50, 0.70}"
        endif
        yb = 5 - b + 0.5
        Select inner viewport: 0.6, 3.6, 5.92, 6.82
        Axes: -75, 118, 0, 5
        Paint rectangle: bc$, 0, max(bv, 0.3), yb - 0.3, yb + 0.3
        Colour: "Black"
        Text: -73, "left", yb, "half", bl$
        Text: bv + 2, "left", yb, "half", fixed$(bv, 0)
    endfor
    Select inner viewport: 0.6, 3.6, 5.92, 6.82
    Axes: -75, 118, 0, 5
    Colour: "Black"
    Draw line: 0, 0, 0, 5
    Draw inner box

    # loss history (log10), segments concatenated
    selectObject: mh
    nh = Get number of rows
    lMin = 1e30
    lMax = -1e30
    for r to nh
        for c from 3 to 5
            v = Get value in cell: r, c
            if v > 0
                lMin = min(lMin, log10(v))
                lMax = max(lMax, log10(v))
            endif
        endfor
    endfor
    if lMax <= lMin
        lMax = lMin + 1
    endif
    lMin = lMin - 0.1
    lMax = lMax + 0.1
    Font size: 7
    Select inner viewport: 4.3, 7.7, 5.92, 6.82
    Axes: 0, nh, lMin, lMax
    Colour: "Black"
    Text top: "no", "##Loss per order## (log10, weighted)   gray 0   blue 1   orange 2"
    for c from 3 to 5
        if c = 3
            Colour: o0C$
        elsif c = 4
            Colour: o1C$
        else
            Colour: o2C$
        endif
        Select inner viewport: 4.3, 7.7, 5.92, 6.82
        Axes: 0, nh, lMin, lMax
        selectObject: mh
        for r from 2 to nh
            sa = Get value in cell: r - 1, 1
            sb = Get value in cell: r, 1
            va = Get value in cell: r - 1, c
            vb = Get value in cell: r, c
            if sa = sb and va > 0 and vb > 0
                Draw line: r - 1, log10(va), r, log10(vb)
            endif
        endfor
    endfor
    Select inner viewport: 4.3, 7.7, 5.92, 6.82
    Axes: 0, nh, lMin, lMax
    Colour: {0.60, 0.60, 0.60}
    selectObject: mh
    for r from 2 to nh
        sa = Get value in cell: r - 1, 1
        sb = Get value in cell: r, 1
        if sa <> sb
            Dotted line
            Draw line: r - 0.5, lMin, r - 0.5, lMax
            Solid line
        endif
    endfor
    Colour: "Black"
    Draw inner box
    @niceLeft: lMin, lMax
    @niceBottom: 0, nh
    Text bottom: "yes", "Calibration rounds, then refinement steps (dotted = next segment)"

    # ---- 5. NEW REALIZATION -----------------------------------------------
    @sectionHeader: 7.22, "##5  NEW REALIZATION##   same scale as the source panel"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 7.34, 7.94
    Axes: srcStart, srcStart + srcDur, -wRange, wRange
    Colour: outC$
    selectObject: res
    Draw: srcStart, srcStart + srcDur, -wRange, wRange, "no", "Curve"
    Select inner viewport: 0.6, 7.7, 7.34, 7.94
    Axes: srcStart, srcStart + srcDur, -wRange, wRange
    Colour: "Black"
    Draw inner box
    Marks left every: 1, wRange, "no", "yes", "no"
    Marks bottom: 6, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # ---- summary ------------------------------------------------------------
    Select inner viewport: 0.6, 7.7, 8.45, 9.95
    Axes: 0, 1, 0, 1
    Paint rectangle: {0.94, 0.94, 0.94}, 0, 1, 0, 1
    @rep: "preset"
    sPreset$ = rep$
    @rep: "seed"
    sSeed$ = rep$
    @rep: "J"
    sJ$ = rep$
    @rep: "T_ms"
    sT = number(rep$)
    @rep: "Q1"
    sQ1$ = rep$
    @rep: "Q2"
    sQ2$ = rep$
    @rep: "n_order1"
    sN1$ = rep$
    @rep: "n_order2"
    sN2$ = rep$
    @rep: "working_sr"
    sWsr = number(rep$)
    @rep: "band_limit_hz"
    sBl = number(rep$)
    @rep: "segments"
    sSeg$ = rep$
    @rep: "overlap_ms"
    sOv = number(rep$)
    @rep: "iterations_per_segment"
    sIt$ = rep$
    @rep: "loss_reduction_pct"
    sRed = number(rep$)
    @rep: "mod_rate_min_hz"
    sMr1 = number(rep$)
    @rep: "mod_rate_max_hz"
    sMr2 = number(rep$)
    @rep: "n_ops"
    sNops = number(rep$)
    ops$ = ""
    for k to sNops
        @rep: "op_" + string$(k)
        if k > 1
            ops$ = ops$ + "; "
        endif
        ops$ = ops$ + rep$
    endfor
    if ops$ = ""
        ops$ = "none (target = source scattering)"
    endif
    @rep: "warning"
    sWarn$ = rep$

    line1$ = "Preset " + sPreset$ + "  |  weights 0/1/2 = " + fixed$(bw0, 0) + " / " + fixed$(bw1, 0) + " / " + fixed$(bw2, 0) + "  |  transformation " + fixed$(btr, 0) + " %  |  randomness " + fixed$(brn, 0) + " %  |  seed " + sSeed$
    line2$ = "Kymatio Morlet filters: J = " + sJ$ + " (T = " + fixed$(sT, 0) + " ms), Q = (" + sQ1$ + ", " + sQ2$ + "), " + sN1$ + " first-order + " + sN2$ + " second-order paths; order-2 rates " + fixed$(sMr1, 1) + "-" + fixed$(sMr2, 0) + " Hz"
    @rep: "calibration_rounds"
    sCr$ = rep$
    if sIt$ = "0"
        refine$ = ", no refinement"
    else
        refine$ = " + up to " + sIt$ + " refinement steps"
    endif
    line3$ = "Working rate " + fixed$(sWsr, 0) + " Hz (band limit " + fixed$(sBl, 0) + " Hz)  |  " + sSeg$ + " segment(s), overlap " + fixed$(sOv, 0) + " ms  |  direct synthesis, " + sCr$ + " calibration rounds" + refine$ + "  |  loss reduced " + fixed$(sRed, 0) + " %"
    line4$ = "Target operations: " + ops$
    line5$ = "Order 0 = |x| * phi_J (envelope form). Order 2 matched as S2/S1. Cross-band modulation phase is not constrained by time scattering."
    line6$ = "Warning: " + sWarn$
    Font size: 6
    Colour: {0.15, 0.15, 0.15}
    for k to 6
        Select inner viewport: 0.6, 7.7, 8.45, 9.95
        Axes: 0, 1, 0, 1
        @sanitize: line'k'$
        if k = 1
            Text: 0.01, "left", 1 - k / 7, "half", "##" + san$ + "##"
        else
            Text: 0.01, "left", 1 - k / 7, "half", san$
        endif
    endfor
    Select inner viewport: 0.6, 7.7, 8.45, 9.95
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    removeObject: m0, m1, m2r, gS, gT, gO, gA, mh
    Select outer viewport: 0, canvasW, 0, canvasH
endproc
