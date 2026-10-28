# ============================================================
# Praat AudioTools - NMF_Granular_Spatial_Composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# Category: Hybrid Systems (Praat + Python)
#
# Description:
#   NMF Granular Spatial Composer - turns ONE selected Sound into newly
#   composed mono, stereo and quadraphonic sounds. The Python engine
#   decomposes the sound with NMF, derives an 8-source corpus from it,
#   re-assembles that corpus as a time-local granular cloud, imposes the
#   original amplitude envelope, and spatialises every grain individually.
#
# Pipeline:
#   Praat: selected Sound -> temporary WAV in an owned work folder
#   Python (nmf_granular_spatial_composer.py, same folder as this script):
#     STFT -> scikit-learn NMF (12 components, reference mode)
#     -> corpus: 3 strongest component solos, neutral Griffin-Lim,
#        H cross-route (original phase / Griffin-Lim), spectral sculpture,
#        spectral portrait
#     -> Poisson grains (local source position), Hann windows, overlap-add
#     -> original envelope -> Mono / Stereo Source Islands / Stereo Grain
#        Orbit / Quadraphonic Constellation (FL FR BL BR)
#   Praat: imports the requested results, draws the compositional score,
#   removes the work folder (or keeps it, protected, on request).
#
# Outputs (for a Sound named Source):
#   Source_NMF_Local_Granular   1 ch  local granular + original envelope
#   Source_NMF_Stereo_Islands   2 ch  each corpus source near its own place
#   Source_NMF_Stereo_Orbit     2 ch  grains scattered round a moving centre
#   Source_NMF_Quad             4 ch  channel order FL, FR, BL, BR
#   Source_NMF_Quad_Preview     2 ch  stereo DOWNMIX of the quad (not binaural)
#   All outputs are at the engine's 16 kHz reference analysis rate.
#
# Changelog v1.1 (2026):
#   - Compositional presets, separate from Spatial Rendering: Reference (the
#     approved experiment, unchanged and bit-identical), Suspended,
#     Fragmented, Diffuse Cloud (proposed starting points, not yet validated
#     by listening) and Custom (dialog with every granular parameter, the
#     random seed and the envelope strength).
#   - Compositional visualization on one 8-inch Praat Picture page:
#     A Temporal Gesture (source RMS, imposed envelope, measured output RMS),
#     B Granular Source Map (every grain on its corpus source lane, width =
#     grain duration), C Spatial Composition (Islands: positions around the
#     source anchors; Orbit: moving centre and the grains around it; Quad:
#     energy per speaker and a speaker sketch), and an information strip.
#     Positions are the ones RECORDED during the render, not recomputed.
#   - Retain work files: the kept folder is renamed NMF_GSC_kept_... and its
#     ownership marker removed, so the automatic 24 h cleanup never deletes
#     it (only marked NMF_GSC_work_ folders are temporary). The same applies
#     to a folder kept after an import problem.
#   - The three solo corpus slots are labelled with their real NMF component
#     numbers (report and figure).
#   - Play: choose which output is played; Auto prefers Stereo Source
#     Islands, then Orbit, the quad stereo preview, then mono.
#
# Changelog v1.0 (2026):
#   - First release. Consolidates three approved Python experiments
#     (nmf_python_lab.py, nmf_granular_envelope_poc.py,
#     nmf_granular_spatial_poc.py) into one engine; with the reference
#     settings its output is sample-identical to running those scripts in
#     sequence (see test_nmf_granular_spatial.py).
#   - Granular parameters live in an optional second dialog so the main form
#     stays short; their defaults are the approved reference values.
#   - Python is found automatically (no Python field): an optional one-line
#     file nmf_gsc_python.txt next to this script, then the Windows "py -3"
#     launcher, "python", "python3", and per-user Python installs. Each
#     candidate is probed with the engine's own dependency check.
#   - Temporary files live only in a uniquely named, marked work folder in
#     the system temp folder (never the plugin folder); Python deletes only
#     files it recorded there. Leftovers from crashes older than 24 h are
#     removed automatically, by the same marker rule.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Requires:
#   Praat 6.3 or later (7.0: asks once for permission to write files and
#   run Python). Python 3.10+ with numpy, scipy, librosa, scikit-learn,
#   soundfile (pip install -r requirements.txt).
# ============================================================

form NMF Granular Spatial Composer v1.1
    comment --- Compositional preset (how the grains are organised in time) ---
    optionmenu Preset: 1
        option Reference
        option Suspended
        option Fragmented
        option Diffuse Cloud
        option Custom
    comment --- Spatial rendering (where the material is placed) ---
    optionmenu Rendering: 5
        option Mono Local Granular
        option Stereo Source Islands
        option Stereo Grain Orbit
        option Quad Constellation
        option All Outputs
    boolean Original_envelope 1
    comment --- Options ---
    boolean Quad_stereo_preview 1
    boolean Draw_visualization 1
    boolean Show_processing_report 1
    boolean Retain_work_files 0
    optionmenu Play: 1
        option Auto (Stereo Islands first)
        option Mono Local Granular
        option Stereo Source Islands
        option Stereo Grain Orbit
        option Quad Preview (stereo downmix)
        option None
endform

# ------------------------------------------------------------
# 1. Validation that needs no files
# ------------------------------------------------------------
if numberOfSelected () <> 1 or numberOfSelected ("Sound") <> 1
    exitScript: "Select exactly one Sound object (and nothing else)."
endif
gsc_source = selected ("Sound")
gsc_name$ = selected$ ("Sound")
gsc_dur = Get total duration
gsc_peak = Get absolute extremum: 0, 0, "None"
if gsc_peak = undefined or gsc_peak <= 0
    exitScript: "The selected Sound is silent: there is nothing to decompose."
endif
if gsc_dur < 1
    exitScript: "The selected Sound is " + fixed$ (gsc_dur, 3) + " s long; at least 1 s is needed."
endif
if gsc_dur > 600
    exitScript: "The selected Sound is " + fixed$ (gsc_dur / 60, 1) + " min long; at most 10 minutes are accepted."
endif
# Compositional presets. Reference = the approved experiment (unchanged);
# the other three are proposed starting points, not yet validated by listening.
#                  Reference Suspended Fragmented Diffuse_Cloud
gsc_pDensity#   = {93,       75,       125,       150}
gsc_pGmin#      = {65,       140,      40,        90}
gsc_pGmax#      = {140,      260,      85,        210}
gsc_pLocality#  = {0.26,     0.35,     0.12,      0.55}
gsc_pSmin#      = {0.92,     0.92,     0.85,      0.78}
gsc_pSmax#      = {1.08,     1.08,     1.15,      1.22}
gsc_pEnv#       = {1.0,      0.8,      1.0,       0.65}
gsc_presetNames$# = {"Reference", "Suspended", "Fragmented", "Diffuse Cloud", "Custom"}
gsc_preset$ = gsc_presetNames$# [preset]
random_seed = 20261029
if preset <= 4
    density = gsc_pDensity# [preset]
    grain_min_ms = gsc_pGmin# [preset]
    grain_max_ms = gsc_pGmax# [preset]
    locality_s = gsc_pLocality# [preset]
    speed_min = gsc_pSmin# [preset]
    speed_max = gsc_pSmax# [preset]
    envelope_strength = gsc_pEnv# [preset]
else
    beginPause: "NMF Granular Spatial Composer - Custom preset"
        comment: "Defaults are the Reference values (the approved experiment)."
        positive: "Density", "93"
        positive: "Grain_min_ms", "65"
        positive: "Grain_max_ms", "140"
        real: "Locality_s", "0.26"
        positive: "Speed_min", "0.92"
        positive: "Speed_max", "1.08"
        real: "Envelope_strength", "1.0"
        integer: "Random_seed", "20261029"
    gsc_clicked = endPause: "Cancel", "Continue", 2, 1
    if gsc_clicked = 1
        exitScript ()
    endif
endif
if envelope_strength < 0 or envelope_strength > 1
    exitScript: "Envelope_strength must be between 0 and 1 (1 = the reference envelope)."
endif
if not original_envelope
    envelope_strength = 0
endif
gsc_err$ = ""
if density < 1 or density > 500
    gsc_err$ = "Density must be 1-500 grains per second."
elsif grain_min_ms < 5 or grain_max_ms > 1000
    gsc_err$ = "Grain durations must be 5-1000 ms."
elsif grain_min_ms > grain_max_ms
    gsc_err$ = "Grain_min_ms is above Grain_max_ms."
elsif locality_s < 0 or locality_s > 5
    gsc_err$ = "Locality_s must be 0-5 s."
elsif speed_min < 0.25 or speed_max > 4
    gsc_err$ = "Playback speeds must be 0.25-4."
elsif speed_min > speed_max
    gsc_err$ = "Speed_min is above Speed_max."
elsif random_seed < 0
    gsc_err$ = "Random_seed must be >= 0."
endif
if gsc_err$ <> ""
    exitScript: gsc_err$
endif

gsc_modes$# = {"mono", "islands", "orbit", "quad", "all"}
gsc_mode$ = gsc_modes$# [rendering]
gsc_renderNames$# = {"Mono Local Granular", "Stereo Source Islands", "Stereo Grain Orbit", "Quad Constellation", "All Outputs"}
gsc_viz$ = "no"
if draw_visualization
    gsc_viz$ = "yes"
endif
gsc_preview$ = "no"
if quad_stereo_preview
    gsc_preview$ = "yes"
endif

# ------------------------------------------------------------
# 2. Permission (Praat 7), engine location
# ------------------------------------------------------------
if praatVersion >= 7000
    gsc_trust = askForTrust ()
    if not gsc_trust
        exitScript: "NMF Granular Spatial Composer needs permission to write a temporary WAV and to run Python."
    endif
endif
gsc_dir$ = defaultDirectory$
gsc_engine$ = gsc_dir$ + "/nmf_granular_spatial_composer.py"
if not fileReadable (gsc_engine$)
    exitScript: "The Python engine was not found next to this script:" + newline$ + gsc_engine$ + newline$ + "Keep NMF_Granular_Spatial_Composer.praat and nmf_granular_spatial_composer.py in the same folder."
endif

# ------------------------------------------------------------
# 3. System temp folder (the work folder is created after Python is found)
# ------------------------------------------------------------
gsc_root$ = environment$ ("TEMP")
if gsc_root$ = ""
    gsc_root$ = environment$ ("TMP")
endif
if gsc_root$ = ""
    gsc_root$ = environment$ ("TMPDIR")
endif
if gsc_root$ = "" and unix
    gsc_root$ = "/tmp"
endif
if gsc_root$ = ""
    gsc_root$ = temporaryDirectory$
endif
gsc_stamp$ = replace_regex$ (date$ (), "[^A-Za-z0-9]", "", 0) + "_" + string$ (randomInteger (100000, 999999))
gsc_probe$ = gsc_root$ + "/NMF_GSC_probe_" + gsc_stamp$ + ".json"
# The temp folder must be writable before anything else depends on it.
nocheck writeFileLine: gsc_probe$, "{}"
if not fileReadable (gsc_probe$)
    exitScript: "The temporary folder is missing or not writable:" + newline$ + gsc_root$ + newline$ + "Check the TEMP (Windows) or TMPDIR environment variable."
endif
nocheck deleteFile: gsc_probe$
gsc_clean = 0
gsc_work$ = ""

# ------------------------------------------------------------
# 4. Find Python: probe each candidate with the engine itself
# ------------------------------------------------------------
gsc_nc = 0
gsc_config$ = gsc_dir$ + "/nmf_gsc_python.txt"
gsc_configured = 0
if fileReadable (gsc_config$)
    gsc_cfg$ = readFile$ (gsc_config$)
    gsc_cfg$ = replace_regex$ (gsc_cfg$, "^[ \t\r\n""]+|[ \t\r\n""]+$", "", 0)
    gsc_cfg$ = replace_regex$ (gsc_cfg$, "[\r\n].*", "", 0)
    if gsc_cfg$ <> ""
        gsc_configured = 1
        gsc_nc = gsc_nc + 1
        gsc_exe$[gsc_nc] = gsc_cfg$
        gsc_arg$[gsc_nc] = ""
    endif
endif
if not gsc_configured
    if windows
        gsc_nc = gsc_nc + 1
        gsc_exe$[gsc_nc] = "py"
        gsc_arg$[gsc_nc] = "-3"
        gsc_nc = gsc_nc + 1
        gsc_exe$[gsc_nc] = "python"
        gsc_arg$[gsc_nc] = ""
        gsc_nc = gsc_nc + 1
        gsc_exe$[gsc_nc] = "python3"
        gsc_arg$[gsc_nc] = ""
        gsc_lad$ = environment$ ("LOCALAPPDATA")
        if gsc_lad$ <> ""
            gsc_pyroot$ = gsc_lad$ + "/Programs/Python"
            gsc_list = Create Strings as folder list: "pyfolders", gsc_pyroot$ + "/Python3*"
            gsc_np = Get number of strings
            if gsc_np > 0
                Sort
            endif
            for gsc_i from 1 to gsc_np
                selectObject: gsc_list
                gsc_f$ = Get string: gsc_np + 1 - gsc_i
                gsc_nc = gsc_nc + 1
                gsc_exe$[gsc_nc] = gsc_pyroot$ + "/" + gsc_f$ + "/python.exe"
                gsc_arg$[gsc_nc] = ""
            endfor
            removeObject: gsc_list
        endif
    else
        gsc_nc = gsc_nc + 1
        gsc_exe$[gsc_nc] = "python3"
        gsc_arg$[gsc_nc] = ""
        gsc_nc = gsc_nc + 1
        gsc_exe$[gsc_nc] = "python"
        gsc_arg$[gsc_nc] = ""
    endif
endif

gsc_py$ = ""
gsc_pyarg$ = ""
gsc_missing$ = ""
gsc_tried$ = ""
gsc_i = 0
while gsc_py$ = "" and gsc_i < gsc_nc
    gsc_i = gsc_i + 1
    gsc_tried$ = gsc_tried$ + newline$ + "  " + gsc_exe$[gsc_i] + " " + gsc_arg$[gsc_i]
    if gsc_arg$[gsc_i] = ""
        nocheck runSubprocess: gsc_exe$[gsc_i], gsc_engine$, "--probe", gsc_probe$
    else
        nocheck runSubprocess: gsc_exe$[gsc_i], gsc_arg$[gsc_i], gsc_engine$, "--probe", gsc_probe$
    endif
    if fileReadable (gsc_probe$)
        gsc_pj$ = readFile$ (gsc_probe$)
        nocheck deleteFile: gsc_probe$
        if index (gsc_pj$, """ok"": true")
            gsc_py$ = gsc_exe$[gsc_i]
            gsc_pyarg$ = gsc_arg$[gsc_i]
        elsif gsc_missing$ = ""
            gsc_m1 = index (gsc_pj$, """missing"": [")
            gsc_m$ = mid$ (gsc_pj$, gsc_m1 + 12, length (gsc_pj$) - gsc_m1 - 11)
            gsc_m$ = left$ (gsc_m$, index (gsc_m$, "]") - 1)
            gsc_m$ = replace$ (gsc_m$, """", "", 0)
            gsc_m$ = replace$ (gsc_m$, newline$, " ", 0)
            gsc_m$ = replace$ (gsc_m$, tab$, " ", 0)
            gsc_m$ = replace_regex$ (gsc_m$, " +", " ", 0)
            gsc_m$ = replace_regex$ (gsc_m$, "^ | $", "", 0)
            gsc_mexe$ = gsc_exe$[gsc_i]
            gsc_marg$ = gsc_arg$[gsc_i]
            gsc_missing$ = "Python was found (" + gsc_mexe$ + ") but these packages are missing: " + gsc_m$ + "."
        endif
    endif
endwhile
if gsc_py$ = ""
    if gsc_missing$ <> ""
        gsc_launch$ = """" + gsc_mexe$ + """"
        if gsc_marg$ <> ""
            gsc_launch$ = gsc_launch$ + " " + gsc_marg$
        endif
        exitScript: gsc_missing$ + newline$ + "Install them (once) from a command prompt with:" + newline$ + "  " + gsc_launch$ + " -m pip install -r """ + gsc_dir$ + "/requirements.txt"""
    elsif gsc_configured
        exitScript: "The Python configured in nmf_gsc_python.txt could not run the engine:" + newline$ + "  " + gsc_cfg$ + newline$ + "Correct the path in that file (one line: the full path to python.exe), or delete the file to use automatic discovery."
    else
        exitScript: "No usable Python 3 was found. Tried:" + gsc_tried$ + newline$ + "Install Python 3.10+ from python.org (tick 'Add python.exe to PATH'), then run:  python -m pip install -r requirements.txt" + newline$ + "Or write the full path to python.exe into nmf_gsc_python.txt next to this script."
    endif
endif

# ------------------------------------------------------------
# 5. Owned work folder (unique name + marker; Python records every file it
#    writes in a ledger there, and cleanup deletes only marker + ledger files)
# ------------------------------------------------------------
gsc_work$ = gsc_root$ + "/NMF_GSC_work_" + gsc_stamp$
gsc_marker$ = gsc_work$ + "/NMF_GSC_WORKDIR.txt"
gsc_input$ = gsc_work$ + "/input.wav"
createDirectory: gsc_work$
nocheck writeFileLine: gsc_marker$, "NMF_GSC_WORKDIR v1", newline$, "input=input.wav", newline$, "created_by=NMF_Granular_Spatial_Composer.praat"
if not fileReadable (gsc_marker$)
    exitScript: "Could not create a work folder in the temporary folder:" + newline$ + gsc_root$ + newline$ + "Check that the TEMP folder exists and is writable."
endif
gsc_clean = 1

# ------------------------------------------------------------
# 6. Export the Sound and run the engine
# ------------------------------------------------------------
selectObject: gsc_source
Save as 32-bit WAV file: gsc_input$
writeInfoLine: "NMF Granular Spatial Composer v1.1: ", gsc_preset$, " / ", gsc_mode$, " from ", gsc_name$, " (", fixed$ (gsc_dur, 2), " s) ..."
if gsc_pyarg$ = ""
    nocheck runSubprocess: gsc_py$, gsc_engine$, "--input", gsc_input$, "--output-dir", gsc_work$, "--mode", gsc_mode$, "--seed", string$ (random_seed), "--density", string$ (density), "--grain-min-ms", string$ (grain_min_ms), "--grain-max-ms", string$ (grain_max_ms), "--locality", string$ (locality_s), "--speed-min", string$ (speed_min), "--speed-max", string$ (speed_max), "--envelope-strength", string$ (envelope_strength), "--quad-preview", gsc_preview$, "--stems", "yes", "--viz", gsc_viz$, "--preset-label", gsc_preset$, "--quiet"
else
    nocheck runSubprocess: gsc_py$, gsc_pyarg$, gsc_engine$, "--input", gsc_input$, "--output-dir", gsc_work$, "--mode", gsc_mode$, "--seed", string$ (random_seed), "--density", string$ (density), "--grain-min-ms", string$ (grain_min_ms), "--grain-max-ms", string$ (grain_max_ms), "--locality", string$ (locality_s), "--speed-min", string$ (speed_min), "--speed-max", string$ (speed_max), "--envelope-strength", string$ (envelope_strength), "--quad-preview", gsc_preview$, "--stems", "yes", "--viz", gsc_viz$, "--preset-label", gsc_preset$, "--quiet"
endif

# ------------------------------------------------------------
# 7. Read the manifest
# ------------------------------------------------------------
gsc_manifest$ = gsc_work$ + "/praat_manifest.txt"
if not fileReadable (gsc_manifest$)
    @gscCleanup
    exitScript: "The Python engine stopped without writing its result manifest (it may have crashed or been interrupted)." + newline$ + "Run it by hand to see the full error:" + newline$ + "  " + gsc_py$ + " " + gsc_pyarg$ + " """ + gsc_engine$ + """ --input <file.wav> --output-dir <folder>"
endif
gsc_lines = Read Strings from raw text file: gsc_manifest$
gsc_nl = Get number of strings
gsc_status$ = ""
gsc_message$ = ""
gsc_nout = 0
gsc_info$ = ""
gsc_nslot = 0
gsc_grains = 0
for gsc_i from 1 to gsc_nl
    selectObject: gsc_lines
    gsc_l$ = Get string: gsc_i
    @gscSplit: gsc_l$
    if gscF$[1] = "STATUS"
        gsc_status$ = gscF$[2]
    elsif gscF$[1] = "MESSAGE"
        gsc_message$ = gscF$[2]
    elsif gscF$[1] = "OUTPUT" and gscN >= 6
        gsc_nout = gsc_nout + 1
        gsc_kind$[gsc_nout] = gscF$[2]
        gsc_file$[gsc_nout] = gscF$[3]
        gsc_ch[gsc_nout] = number (gscF$[4])
        gsc_frames[gsc_nout] = number (gscF$[5])
        gsc_osr[gsc_nout] = number (gscF$[6])
    elsif gscF$[1] = "INFO"
        gsc_info$ = gsc_info$ + "  " + gscF$[2] + newline$
    elsif gscF$[1] = "SLOT" and gscN >= 4
        gsc_nslot = gsc_nslot + 1
        gsc_slotLabel$[gsc_nslot] = gscF$[3]
        gsc_slotGrains[gsc_nslot] = number (gscF$[4])
    elsif gscF$[1] = "GRAINCOUNT"
        gsc_grains = number (gscF$[2])
    endif
endfor
removeObject: gsc_lines
if gsc_status$ <> "ok"
    @gscCleanup
    exitScript: "The Python engine reported an error:" + newline$ + gsc_message$
endif

# ------------------------------------------------------------
# 8. Import the requested results
# ------------------------------------------------------------
gsc_imported = 0
gsc_failed$ = ""
for gsc_i from 1 to gsc_nout
    gsc_path$ = gsc_work$ + "/" + gsc_file$[gsc_i]
    selectObject: gsc_source
    nocheck Read from file: gsc_path$
    gsc_ok = 0
    if numberOfSelected ("Sound") = 1
        gsc_new = selected ("Sound")
        if gsc_new <> gsc_source
            gsc_c = Get number of channels
            gsc_n = Get number of samples
            if gsc_c = gsc_ch[gsc_i] and gsc_n = gsc_frames[gsc_i]
                gsc_ok = 1
                @gscSuffix: gsc_kind$[gsc_i]
                Rename: gsc_name$ + gscSuffix$
                gsc_imported = gsc_imported + 1
                gsc_out[gsc_imported] = gsc_new
                gsc_outkind$[gsc_imported] = gsc_kind$[gsc_i]
            else
                removeObject: gsc_new
                gsc_failed$ = gsc_failed$ + newline$ + "  " + gsc_file$[gsc_i] + ": expected " + string$ (gsc_ch[gsc_i]) + " ch x " + string$ (gsc_frames[gsc_i]) + " samples, read " + string$ (gsc_c) + " x " + string$ (gsc_n)
            endif
        endif
    endif
    if not gsc_ok and index (gsc_failed$, gsc_file$[gsc_i]) = 0
        gsc_failed$ = gsc_failed$ + newline$ + "  " + gsc_file$[gsc_i] + ": could not be read"
    endif
endfor

# ------------------------------------------------------------
# 9. Drawing data (read before the work folder goes), cleanup, report
# ------------------------------------------------------------
gsc_vizOk = 0
if draw_visualization and gsc_imported > 0
    gsc_vg$ = gsc_work$ + "/viz_grains.tsv"
    gsc_vc$ = gsc_work$ + "/viz_curves.tsv"
    if fileReadable (gsc_vg$) and fileReadable (gsc_vc$)
        gsc_vg = Read Table from tab-separated file: gsc_vg$
        gsc_vc = Read Table from tab-separated file: gsc_vc$
        gsc_vizOk = 1
    endif
endif

gsc_kept$ = ""
if gsc_failed$ <> ""
    # Keep the folder: the results on disk may still be recoverable.
    gsc_clean = 0
    @gscRelease
    appendInfoLine: "IMPORT PROBLEM -- the work folder was KEPT so nothing is lost:", gsc_failed$
    appendInfoLine: "  folder: ", gsc_kept$
elsif retain_work_files
    gsc_clean = 0
    @gscRelease
    appendInfoLine: "Work files retained (manifest.json, drawing data, quad file with channel mask, stems):"
    appendInfoLine: "  ", gsc_kept$
    appendInfoLine: "  This folder is yours: the automatic cleanup never touches NMF_GSC_kept_ folders."
endif
if gsc_clean
    @gscCleanup
endif
# Leftover TEMPORARY folders of earlier crashed runs (NMF_GSC_work_ with
# marker, older than 24 h). Kept folders have no marker and are skipped.
if gsc_pyarg$ = ""
    nocheck runSubprocess: gsc_py$, gsc_engine$, "--cleanup-stale", gsc_root$, "--older-than-hours", "24", "--quiet"
else
    nocheck runSubprocess: gsc_py$, gsc_pyarg$, gsc_engine$, "--cleanup-stale", gsc_root$, "--older-than-hours", "24", "--quiet"
endif

if show_processing_report
    appendInfoLine: "Source: ", gsc_name$, " | preset: ", gsc_preset$, " | rendering: ", gsc_renderNames$# [rendering]
    appendInfoLine: "Granular: seed ", random_seed, " | density ", density, " | grains ", grain_min_ms, "-", grain_max_ms, " ms | speed ", speed_min, "-", speed_max, " | locality +-", locality_s, " s | envelope ", envelope_strength
    if preset > 1 and preset < 5
        appendInfoLine: "  (", gsc_preset$, " is a proposed starting point, not yet validated by listening; Reference = the approved experiment.)"
    endif
    appendInfo: gsc_info$
    if gsc_nslot > 0
        gsc_s$ = "  Corpus slots (grains): "
        for gsc_i from 1 to gsc_nslot
            gsc_s$ = gsc_s$ + string$ (gsc_i) + " " + gsc_slotLabel$[gsc_i] + " (" + string$ (gsc_slotGrains[gsc_i]) + ")"
            if gsc_i < gsc_nslot
                gsc_s$ = gsc_s$ + ", "
            endif
        endfor
        appendInfoLine: gsc_s$
    endif
    appendInfoLine: "Imported:"
    for gsc_i from 1 to gsc_imported
        selectObject: gsc_out[gsc_i]
        gsc_c = Get number of channels
        gsc_d = Get total duration
        gsc_sr = Get sampling frequency
        appendInfoLine: "  ", selected$ ("Sound"), ": ", gsc_c, " ch, ", fixed$ (gsc_d, 3), " s, ", gsc_sr, " Hz"
    endfor
    appendInfoLine: "Quad channel order: 1 FL, 2 FR, 3 BL, 4 BR. The Quad_Preview is a stereo downmix, not a binaural rendering."
endif

if gsc_imported = 0
    if gsc_vizOk
        removeObject: gsc_vg, gsc_vc
    endif
    selectObject: gsc_source
    exitScript: "No output could be imported." + gsc_failed$
endif

# ------------------------------------------------------------
# 10. Compositional visualization (Python supplied the data; Praat draws)
# ------------------------------------------------------------
if gsc_vizOk
    @gscDrawPage
    removeObject: gsc_vg, gsc_vc
elsif draw_visualization
    appendInfoLine: "Note: the drawing data was not found, so no figure was drawn."
endif

# ------------------------------------------------------------
# 11. Selection and playback
# ------------------------------------------------------------
gsc_playWant$# = {"auto", "mono", "islands", "orbit", "quad_preview", "none"}
gsc_want$ = gsc_playWant$# [play]
gsc_play = 0
if gsc_want$ <> "auto" and gsc_want$ <> "none"
    @gscFindOut: gsc_want$
    gsc_play = gscFindOut
    if gsc_play = 0
        appendInfoLine: "Play: ", gsc_want$, " was not rendered; playing the first available output instead (Islands, Orbit, Quad preview, Mono)."
    endif
endif
if gsc_want$ <> "none" and gsc_play = 0
    gsc_auto$# = {"islands", "orbit", "quad_preview", "mono"}
    for gsc_i from 1 to 4
        if gsc_play = 0
            @gscFindOut: gsc_auto$# [gsc_i]
            gsc_play = gscFindOut
        endif
    endfor
endif
if gsc_play > 0
    selectObject: gsc_play
    appendInfoLine: "Playing: ", selected$ ("Sound")
    # A missing or busy audio device must not cost the results.
    nocheck Play
endif
selectObject: gsc_out[1]
for gsc_i from 2 to gsc_imported
    plusObject: gsc_out[gsc_i]
endfor

# ------------------------------------------------------------
procedure gscSuffix: .kind$
    gscSuffix$ = "_NMF_" + .kind$
    if .kind$ = "mono"
        gscSuffix$ = "_NMF_Local_Granular"
    elsif .kind$ = "islands"
        gscSuffix$ = "_NMF_Stereo_Islands"
    elsif .kind$ = "orbit"
        gscSuffix$ = "_NMF_Stereo_Orbit"
    elsif .kind$ = "quad"
        gscSuffix$ = "_NMF_Quad"
    elsif .kind$ = "quad_preview"
        gscSuffix$ = "_NMF_Quad_Preview"
    endif
endproc

procedure gscSplit: .s$
    gscN = 0
    .rest$ = .s$
    while index (.rest$, tab$) > 0
        .p = index (.rest$, tab$)
        gscN = gscN + 1
        gscF$[gscN] = left$ (.rest$, .p - 1)
        .rest$ = mid$ (.rest$, .p + 1, length (.rest$) - .p)
    endwhile
    gscN = gscN + 1
    gscF$[gscN] = .rest$
    for .j from gscN + 1 to 7
        gscF$[.j] = ""
    endfor
endproc

# Removes only what this run created: Python deletes the marker and the
# files listed in the work folder's ledger, then the folder if nothing else
# is left in it. Called only after Python has been found.
procedure gscCleanup
    if gsc_clean
        if gsc_pyarg$ = ""
            nocheck runSubprocess: gsc_py$, gsc_engine$, "--cleanup", gsc_work$, "--quiet"
        else
            nocheck runSubprocess: gsc_py$, gsc_pyarg$, gsc_engine$, "--cleanup", gsc_work$, "--quiet"
        endif
        gsc_clean = 0
        if fileReadable (gsc_marker$)
            appendInfoLine: "Note: the work folder could not be removed: ", gsc_work$
        endif
    endif
endproc

# A folder the user keeps (Retain work files, or after an import problem)
# becomes NMF_GSC_kept_<stamp>: Python removes the input copy and the
# ownership marker and renames the folder, so no cleanup (this run's, or the
# 24 h stale cleanup of a later run) can ever delete it.
procedure gscRelease
    if gsc_pyarg$ = ""
        nocheck runSubprocess: gsc_py$, gsc_engine$, "--release", gsc_work$, "--quiet"
    else
        nocheck runSubprocess: gsc_py$, gsc_pyarg$, gsc_engine$, "--release", gsc_work$, "--quiet"
    endif
    gsc_kept$ = gsc_root$ + "/NMF_GSC_kept_" + gsc_stamp$
    if not fileReadable (gsc_kept$ + "/praat_manifest.txt")
        gsc_kept$ = gsc_work$
        appendInfoLine: "Note: the work folder could not be marked as kept; copy its files elsewhere, since the 24 h cleanup may remove it."
    endif
endproc

procedure gscFindOut: .kind$
    gscFindOut = 0
    for .i from 1 to gsc_imported
        if gscFindOut = 0 and gsc_outkind$[.i] = .kind$
            gscFindOut = gsc_out[.i]
        endif
    endfor
endproc

# ============================================================
# Compositional visualization: one 8-inch page in the Picture window.
#   A Temporal Gesture   B Granular Source Map   C Spatial Composition
#   + information strip. Data: viz_grains.tsv (one row per grain, with the
#   spatial positions recorded during the render) and viz_curves.tsv
#   (10 ms RMS curves measured by the engine).
# ============================================================
procedure gscDrawPage
    # Which output the page describes.
    .shown$ = gsc_mode$
    if gsc_mode$ = "all"
        .shown$ = "islands"
    endif
    .tmax = gsc_frames[1] / gsc_osr[1]
    .x1 = 1.25
    .x2 = 7.75
    # Slot colours (Okabe-Ito based) and quad speaker colours
    .col$[1] = "{0.90, 0.62, 0.00}"
    .col$[2] = "{0.34, 0.71, 0.91}"
    .col$[3] = "{0.00, 0.62, 0.45}"
    .col$[4] = "{0.55, 0.55, 0.55}"
    .col$[5] = "{0.00, 0.45, 0.70}"
    .col$[6] = "{0.80, 0.47, 0.65}"
    .col$[7] = "{0.84, 0.37, 0.00}"
    .col$[8] = "{0.12, 0.12, 0.12}"
    .spk$[1] = "FL"
    .spk$[2] = "FR"
    .spk$[3] = "BL"
    .spk$[4] = "BR"
    .spkDeg[1] = 315
    .spkDeg[2] = 45
    .spkDeg[3] = 225
    .spkDeg[4] = 135
    .islandAnchor# = {-0.95, 0.95, -0.58, 0.58, -0.33, 0.33, -0.79, 0.79}
    .quadAnchor# = {315, 45, 225, 135, 0, 90, 270, 180}
    for .k from 1 to 8
        .lab$[.k] = "Slot " + string$ (.k)
        .cnt[.k] = 0
    endfor
    for .k from 1 to gsc_nslot
        .lab$[.k] = gsc_slotLabel$[.k]
        .cnt[.k] = gsc_slotGrains[.k]
    endfor
    .step = 1
    if .tmax > 20
        .step = 5
    endif
    if .tmax > 60
        .step = 10
    endif
    if .tmax > 150
        .step = 30
    endif
    if .tmax > 400
        .step = 60
    endif

    # Page layout (inches from the top)
    .yA1 = 1.3
    .yA2 = 2.5
    .yB1 = 3.1
    .yB2 = 5.5
    .yC1 = 6.2
    .yC2 = 7.6
    .yQ1 = .yC1
    .hasC = 1
    .hasQ = 0
    if .shown$ = "mono"
        .hasC = 0
        .yInfo = .yB2 + 0.65
    elsif .shown$ = "quad"
        .hasC = 0
        .hasQ = 1
        .yQ1 = .yC1
        .yQ2 = .yQ1 + 1.6
        .yInfo = .yQ2 + 0.65
    else
        .yInfo = .yC2 + 0.65
        if gsc_mode$ = "all"
            .hasQ = 1
            .yQ1 = .yC2 + 0.75
            .yQ2 = .yQ1 + 1.6
            .yInfo = .yQ2 + 0.65
        endif
    endif
    .pageH = .yInfo + 0.75

    Erase all
    Black
    Solid line
    Line width: 1
    Font size: 10
    Select outer viewport: 0, 8, 0, .pageH
    Select inner viewport: 0, 8, 0, .pageH
    Axes: 0, 8, .pageH, 0
    # --- title
    @gscEsc: gsc_name$
    Font size: 14
    Text: 0.25, "left", 0.26, "half", "##NMF Granular Spatial Composer#   " + gscEsc$
    Font size: 9
    Grey
    Text: 0.25, "left", 0.66, "half", "Preset " + gsc_preset$ + "  ·  " + string$ (density) + " grains/s  ·  grains " + string$ (grain_min_ms) + "–" + string$ (grain_max_ms) + " ms  ·  locality ±" + string$ (locality_s) + " s  ·  speed " + fixed$ (speed_min, 2) + "–" + fixed$ (speed_max, 2) + "  ·  envelope " + string$ (round (envelope_strength * 100)) + "\% "
    Black

    # ======================== A. Temporal Gesture
    @gscHeader: "A", "Temporal Gesture", "original dynamics and the composed result (each curve normalised to its own peak)", .yA1 - 0.2, .pageH
    # legend
    Line width: 2.5
    Colour: "{0.75, 0.75, 0.75}"
    Draw line: 4.35, .yA1 - 0.32, 4.6, .yA1 - 0.32
    Colour: "{0.00, 0.45, 0.70}"
    Line width: 1.5
    Draw line: 5.65, .yA1 - 0.32, 5.9, .yA1 - 0.32
    Black
    Line width: 1.2
    Dashed line
    Draw line: 6.75, .yA1 - 0.32, 7.0, .yA1 - 0.32
    Solid line
    Line width: 1
    Font size: 8
    Text: 4.65, "left", .yA1 - 0.32, "half", "Original RMS"
    Text: 5.95, "left", .yA1 - 0.32, "half", "Output RMS"
    Text: 7.05, "left", .yA1 - 0.32, "half", "Imposed env."
    Font size: 8
    Select inner viewport: .x1, .x2, .yA1, .yA2
    @gscCurve: "src_rms", 0
    Line width: 2.5
    Colour: "{0.75, 0.75, 0.75}"
    Draw: 0, .tmax, 0, 1.08, "no", "Curve"
    Remove
    @gscCurve: "out_" + .shown$, 0
    Line width: 1.5
    Colour: "{0.00, 0.45, 0.70}"
    Draw: 0, .tmax, 0, 1.08, "no", "Curve"
    Remove
    if envelope_strength > 0
        @gscCurve: "envelope", 0
        Line width: 1.2
        Black
        Dashed line
        Draw: 0, .tmax, 0, 1.08, "no", "Curve"
        Remove
        Solid line
    endif
    Line width: 1
    Black
    Axes: 0, .tmax, 0, 1.08
    Draw inner box
    Marks bottom every: 1, .step, "yes", "yes", "no"

    # ======================== B. Granular Source Map
    @gscHeader: "B", "Granular Source Map", "one mark per grain on its corpus source; width = grain duration, height in lane = read offset", .yB1 - 0.2, .pageH
    Font size: 8
    Select inner viewport: .x1, .x2, .yB1, .yB2
    Axes: 0, .tmax, 0, 8
    Colour: "{0.93, 0.93, 0.93}"
    for .k from 1 to 7
        Draw line: 0, .k, .tmax, .k
    endfor
    selectObject: gsc_vg
    .ng = Get number of rows
    .maxOff = 0.001
    for .r from 1 to .ng
        .on = Get value: .r, "onset"
        .rd = Get value: .r, "read"
        .maxOff = max (.maxOff, abs (.rd - .on))
    endfor
    .stride = max (1, ceiling (.ng / 6000))
    Line width: 2
    for .r from 1 to .ng
        if (.r - 1) mod .stride = 0
            .k = Get value: .r, "slot"
            .on = Get value: .r, "onset"
            .du = Get value: .r, "dur"
            .rd = Get value: .r, "read"
            .y = 8.5 - .k + 0.36 * (.rd - .on) / .maxOff
            Colour: .col$[.k]
            Draw line: .on, .y, .on + .du, .y
        endif
    endfor
    Line width: 1
    Black
    Draw inner box
    Marks bottom every: 1, .step, "yes", "yes", "no"
    for .k from 1 to 8
        Colour: .col$[.k]
        Text: -0.012 * .tmax, "right", 8.5 - .k, "half", .lab$[.k] + "  " + string$ (.cnt[.k])
    endfor
    Black
    if .stride > 1
        Text: .tmax, "right", -0.35, "half", "(1 of every " + string$ (.stride) + " grains drawn)"
    endif
    if .hasC = 0 and .hasQ = 0
        Text bottom: "yes", "Time (s)"
    endif

    # ======================== C. Spatial Composition (stereo)
    if .hasC
        if .shown$ = "islands"
            @gscHeader: "C", "Spatial Composition –  Stereo Source Islands", "recorded position of every grain around the anchor of its source", .yC1 - 0.2, .pageH
            .pcol$ = "pan_islands"
        else
            @gscHeader: "C", "Spatial Composition –  Stereo Grain Orbit", "the moving centre of the cloud (black) and the recorded position of every grain", .yC1 - 0.2, .pageH
            .pcol$ = "pan_orbit"
        endif
        Font size: 8
        Select inner viewport: .x1, .x2, .yC1, .yC2
        Axes: 0, .tmax, -1.08, 1.08
        Colour: "{0.85, 0.85, 0.85}"
        Draw line: 0, 0, .tmax, 0
        if .shown$ = "islands"
            Dotted line
            for .k from 1 to 8
                Colour: .col$[.k]
                Draw line: 0, .islandAnchor# [.k], .tmax, .islandAnchor# [.k]
            endfor
            Solid line
        endif
        for .k from 1 to 8
            selectObject: gsc_vg
            .sub = Extract rows where column (number): "slot", "equal to", .k
            .nsub = Get number of rows
            if .nsub > 0
                Colour: .col$[.k]
                Scatter plot (mark): "onset", 0, .tmax, .pcol$, -1.08, 1.08, 0.9, "no", "o"
            endif
            removeObject: .sub
        endfor
        if .shown$ = "orbit"
            @gscCurve: "orbit_centre", 1
            Black
            Line width: 2.5
            Draw: 0, .tmax, -1.08, 1.08, "no", "Curve"
            Remove
            Line width: 1
        endif
        Black
        Axes: 0, .tmax, -1.08, 1.08
        Draw inner box
        Marks bottom every: 1, .step, "yes", "yes", "no"
        One mark left: 1, "no", "yes", "no", "R"
        One mark left: 0, "no", "yes", "no", "C"
        One mark left: -1, "no", "yes", "no", "L"
        if .hasQ = 0
            Text bottom: "yes", "Time (s)"
        endif
    endif

    # ======================== C. Spatial Composition (quad)
    if .hasQ
        .qx2 = 6.35
        .qLetter$ = "C"
        if .hasC
            .qLetter$ = "C2"
        endif
        @gscHeader: .qLetter$, "Spatial Composition –  Quad Constellation", "energy per speaker over time (one scale for all four)", .yQ1 - 0.2, .pageH
        Font size: 8
        Select inner viewport: .x1, .qx2, .yQ1, .yQ2
        .qmax = 1e-9
        selectObject: gsc_vc
        for .c from 1 to 4
            .ci = Get column index: "quad_" + .spk$[.c]
            if .ci > 0
                .m = Get maximum: "quad_" + .spk$[.c]
                .qmax = max (.qmax, .m)
            endif
        endfor
        .qcol$[1] = "{0.00, 0.45, 0.70}"
        .qcol$[2] = "{0.84, 0.37, 0.00}"
        .qcol$[3] = "{0.00, 0.62, 0.45}"
        .qcol$[4] = "{0.80, 0.47, 0.65}"
        Axes: 0, .tmax, 0, 4
        Colour: "{0.88, 0.88, 0.88}"
        for .c from 1 to 3
            Draw line: 0, .c, .tmax, .c
        endfor
        Line width: 1.2
        for .c from 1 to 4
            @gscCurveScaled: "quad_" + .spk$[.c], 0.9 / .qmax, 4 - .c
            Colour: .qcol$[.c]
            Draw: 0, .tmax, 0, 4, "no", "Curve"
            Remove
        endfor
        Line width: 1
        Black
        Axes: 0, .tmax, 0, 4
        Draw inner box
        Marks bottom every: 1, .step, "yes", "yes", "no"
        for .c from 1 to 4
            Colour: .qcol$[.c]
            Text: -0.012 * .tmax, "right", 4.5 - .c, "half", .spk$[.c]
        endfor
        Black
        Text bottom: "yes", "Time (s)"
        # Speaker sketch: listener in the centre, front at the top
        Select inner viewport: 6.6, 7.85, .yQ1 + 0.1, .yQ1 + 1.35
        Axes: -1.35, 1.35, -1.35, 1.35
        Colour: "{0.8, 0.8, 0.8}"
        Draw circle: 0, 0, 1
        for .k from 1 to 8
            .a = .quadAnchor# [.k] * pi / 180
            Colour: .col$[.k]
            Paint circle: .col$[.k], 0.84 * sin (.a), 0.84 * cos (.a), 0.09
        endfor
        for .c from 1 to 4
            .a = .spkDeg[.c] * pi / 180
            .sx = 1.12 * sin (.a)
            .sy = 1.12 * cos (.a)
            Paint rectangle: .qcol$[.c], .sx - 0.13, .sx + 0.13, .sy - 0.13, .sy + 0.13
            Black
            Text: .sx, "centre", .sy + 0.3 * (.sy / abs (.sy)), "half", .spk$[.c]
        endfor
        Black
        Text: 0, "centre", 0, "half", "+"
        Font size: 7
        Grey
        Text: 0, "centre", 0.32, "half", "front"
        Black
    endif

    # ======================== Information strip
    Font size: 8
    Select inner viewport: 0, 8, 0, .pageH
    Axes: 0, 8, .pageH, 0
    Paint rectangle: "{0.94, 0.94, 0.94}", 0.25, 7.85, .yInfo, .yInfo + 0.58
    @gscThousands: gsc_grains
    .envTxt$ = "Off"
    if envelope_strength > 0
        .envTxt$ = "Original, " + string$ (round (envelope_strength * 100)) + "\% "
    endif
    .outTxt$ = gsc_renderNames$# [rendering]
    if gsc_mode$ = "all"
        .outTxt$ = "All Outputs"
    endif
    @gscCell: 0.4, .yInfo + 0.16, "Corpus", "8 sources / 12 NMF components"
    @gscCell: 3.0, .yInfo + 0.16, "Grain Events", gscThousands$
    @gscCell: 5.7, .yInfo + 0.16, "Preset", gsc_preset$
    @gscCell: 0.4, .yInfo + 0.42, "Envelope", .envTxt$
    @gscCell: 3.0, .yInfo + 0.42, "Output", .outTxt$
    @gscCell: 5.7, .yInfo + 0.42, "Random Seed", string$ (random_seed)
    Black
    Font size: 10
    Select outer viewport: 0, 8, 0, .pageH
endproc

procedure gscHeader: .letter$, .title$, .sub$, .y, .pageH
    Font size: 10
    Select inner viewport: 0, 8, 0, .pageH
    Axes: 0, 8, .pageH, 0
    Black
    Text: 0.25, "left", .y - 0.12, "half", "##" + .letter$ + "   " + .title$ + "#"
    Font size: 8
    Grey
    Text: 0.25, "left", .y + 0.06, "half", .sub$
    Black
endproc

procedure gscCell: .x, .y, .label$, .value$
    Grey
    Text: .x, "left", .y, "half", .label$
    Black
    Text: .x + 0.95, "left", .y, "half", .value$
endproc

# A curve column of viz_curves.tsv as a Sound at 100 Hz (selected), divided
# by its peak unless .raw is 1.
procedure gscCurve: .col$, .raw
    selectObject: gsc_vc
    .scale = 1
    .ci = Get column index: .col$
    if .ci > 0 and .raw = 0
        .m = Get maximum: .col$
        if .m > 0
            .scale = 1 / .m
        endif
    endif
    @gscCurveScaled: .col$, .scale, 0
endproc

procedure gscCurveScaled: .col$, .scale, .offset
    selectObject: gsc_vc
    .n = Get number of rows
    .ci = Get column index: .col$
    if .ci > 0
        Create Sound from formula: "gsc_curve", 1, 0, .n * 0.01, 100, string$ (.offset) + " + " + string$ (.scale) + " * object[" + string$ (gsc_vc) + ", min (" + string$ (.n) + ", max (1, round (x * 100 + 0.5))), " + string$ (.ci) + "]"
    else
        Create Sound from formula: "gsc_curve", 1, 0, .n * 0.01, 100, string$ (.offset)
    endif
endproc

# Text for the Picture window: neutralise Praat's style characters.
procedure gscEsc: .s$
    gscEsc$ = replace$ (.s$, "\", "\bs", 0)
    gscEsc$ = replace$ (gscEsc$, "_", "\_ ", 0)
    gscEsc$ = replace$ (gscEsc$, "%", "\% ", 0)
    gscEsc$ = replace$ (gscEsc$, "^", "\^ ", 0)
    gscEsc$ = replace$ (gscEsc$, "#", "\# ", 0)
endproc

procedure gscThousands: .n
    .s$ = string$ (round (.n))
    gscThousands$ = ""
    while length (.s$) > 3
        gscThousands$ = "," + right$ (.s$, 3) + gscThousands$
        .s$ = left$ (.s$, length (.s$) - 3)
    endwhile
    gscThousands$ = .s$ + gscThousands$
endproc
