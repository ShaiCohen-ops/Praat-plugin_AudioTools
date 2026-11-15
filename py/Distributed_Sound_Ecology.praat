# ============================================================================
# Praat AudioTools - Distributed Sound Ecology.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1.7.1 (2026) - Persistent Sonic Processes + Final Fade
# v0.1.5.2 restored artist-tested Legacy and corrected the Off label; v0.1.5.3 retains both.
# v0.1.7.1: Persistent Processes now has a guaranteed final stereo fade-out.
# v0.1.7: Rendering adds Persistent Processes: agent decisions update one persistent
#         sound process per phrase (glide time Morph_s, articulation by phrases or attacks).
# v0.1.6.1: Rendering adds Continuous Voices (persistent voice per agent: new attacks vs.
#           voice evolution, no voice stealing); Sustain-Aware gains Preserve_tails.
# v0.1.6: Rendering = Fragmented (Legacy, unchanged audio) / Sustain-Aware (natural tails,
#         adaptive fades, release only where the source still sounds); figure shows tails.
# v0.1.5.6: figure only - time/value axes, external-drive row, full event raster, statistics panel.
# v0.1.5.5: conditional Custom dialog, quiet Cancel, study smoke test and silent-agent metric; synthesis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Front end for dce_engine.py EXACTLY version 0.1.7.1.
# Three conditions, one engine: Independent / Centralized / Decentralized.
# Selected Sound -> temporary float WAV -> Python corpus, agent simulation,
# renderer -> 1 or 3 stereo Sounds, plus optional Praat Picture comparison.
#
# Library conventions:
#   - One selected Sound object; Python in plugin_AudioTools/py/ or local py/.
#   - Praat orchestrates and visualizes; Python analyzes and synthesizes.
#   - Text interchange: TSV and key=value only; no JSON parser in Praat.
#   - Configurable musical presets do NOT overwrite numeric form values.
#   - Engine stdout/stderr captured in a log; failed runs preserve artifacts.
#   - Scratch removed on success unless Keep_intermediate_files is enabled.
#
# Requires: Praat with scripting support, Python 3 + numpy/scipy/librosa/soundfile.
# The optional figure uses the library's structural-grey and RGB palette.
# v0.1.4: short event-triggered coupling on condition 2, optional.
# v0.1.4.1: fix Couple_activity off in fast feedback; strict custom matrix/seed
# validation; explicit Picture viewport and reproducible result names.
# v0.1.5: optional condition-0 centered interaction feedback, selection gain,
# rate-normalized pulse deviations, in-picture pulse and global trajectory,
# per-agent diagnostics, automatic Play=1 for the selected or decentralized sound.
# Legacy feedback reference remains available for musical A/B comparisons.
# The form starts in Decentralized Hybrid, using the artist-tested
# coupling=4, memory=0.30 s, temperature=0.12 for an audible first test.
# Off disables FAST event feedback; only Legacy reference reproduces the old path.
# v0.1.5.3: added Central_reference (Legacy / Mean-centred G).
# v0.1.5.4: TimeLine Composer-style opt-in dialogs; main form fits on small screens.
# v0.1.5.5: Custom opens network dialog automatically; Cancel exits quietly.
# v0.2 Collective Regulation / Macro-Trajectory Replay are NOT implemented.
# ============================================================================

# ---- INPUT CHECK BEFORE FORM (library convention) ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object in the Objects window."
endif
sourceSound = selected("Sound")
sourceName$ = selected$("Sound")

# ---- OS-SPECIFIC PYTHON DISCOVERY (Praat AudioTools convention) ----
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

# ---- ENGINE DISCOVERY ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)
pythonScript$ = pluginDir$ + "py/dce_engine.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/py/dce_engine.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/dce_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find dce_engine.py. Install it in plugin_AudioTools/py/ or in a py/ folder beside the .praat file."
endif

# Guard against a silent .praat / .py version mismatch.
engineText$ = readFile$(pythonScript$)
if index(engineText$, "Version : 0.1.7.1 ") = 0 or index(engineText$, "final_fade_s") = 0
    exitScript: "Distributed Sound Ecology v0.1.7.1 requires the matching dce_engine.py v0.1.7.1 (with Final Fade)." + newline$ + "Engine file: " + pythonScript$ + newline$ + "Replace plugin_AudioTools/py/dce_engine.py with the engine supplied in this ZIP."
endif

# ---- COMPACT MAIN FORM ----
# Library convention: TimeLine Composer uses optional beginPause dialogs.  Keep
# the everyday listening controls here; reveal expert settings only on request.
form Distributed Sound Ecology v0.1.7.1
    comment === Music / comparison ===
    optionmenu Architecture: 4
        option All three (comparison)
        option Independent
        option Centralized
        option Decentralized
    positive Duration_s 15
    integer Seed 1
    optionmenu Network_preset: 1
        option Cyclic inhibition (default)
        option Cooperative network
        option Competitive network
        option Custom matrix (edit network options)
    real Coupling 4.0
    positive Memory_s 0.30
    positive Selection_temperature 0.12
    optionmenu Event_feedback: 2
        option Off (no fast feedback)
        option Hybrid (slow plus fast)
        option Fast response only (activity)
    optionmenu Rendering: 1
        option Fragmented (Legacy)
        option Sustain-Aware
        option Continuous Voices
        option Persistent Processes
    comment === Optional settings (open only when checked) ===
    boolean Edit_network_options 0
    boolean Edit_feedback_details 0
    boolean Edit_output_options 0
    boolean Play 1
endform

# Hidden default values are IDENTICAL to v0.1.5.3; this layout change should
# not change the musical output when optional dialogs are left unchecked.
custom_matrix$ = "0,0.3,-0.8;-0.8,0,0.3;0.3,-0.8,0"
couple_activity = 1
couple_grain_selection = 1
selection_gain = 1.0
subtick_onsets = 1
event_strength = 1.0
event_decay_s = 0.25
feedback_reference = 1
pulse_rate_normalize = 0
central_reference = 1
output_normalization = 1
draw_visualization = 1
show_statistics = 1
keep_intermediate_files = 0
debug = 0
# Sustain-Aware rendering (used only when Rendering = Sustain-Aware)
max_natural_tail_s = 4.0
release_ms = 120
crossfade_ms = 25
sustain_sensitivity = 0.5
final_boundary = 1
evolution_ms = 300
preserve_tails = 0
morph_s = 1.0
articulation = 1
final_fade_s = 1.0

if edit_network_options or network_preset = 4
    beginPause: "DCE - network and grain selection"
        comment: "Custom network opens this dialog automatically. Only Custom uses Custom_matrix."
        sentence: "Custom_matrix", custom_matrix$
        boolean: "Couple_activity", couple_activity
        boolean: "Couple_grain_selection", couple_grain_selection
        real: "Selection_gain", string$(selection_gain)
        boolean: "Subtick_onsets", subtick_onsets
    clicked = endPause: "Cancel", "Continue", 2, 1
    if clicked = 1
        exit
    endif
endif

if edit_feedback_details
    beginPause: "DCE - feedback calibration"
        comment: "Event controls affect only Decentralized; Legacy preserves the prior sound."
        real: "Event_strength", string$(event_strength)
        positive: "Event_decay_s", string$(event_decay_s)
        optionmenu: "Feedback_reference", feedback_reference
            option: "Legacy (original signal offsets)"
            option: "Independent baseline (centered feedback)"
        boolean: "Pulse_rate_normalize", pulse_rate_normalize
        comment: "Central_reference affects only Centralized. Not density matched."
        optionmenu: "Central_reference", central_reference
            option: "Legacy (G relative to 0.5)"
            option: "Mean-centred G (post-burn-in)"
    clicked = endPause: "Cancel", "Continue", 2, 1
    if clicked = 1
        exit
    endif
endif

if edit_output_options
    beginPause: "DCE - output, rendering and diagnostics"
        optionmenu: "Output_normalization", output_normalization
            option: "Fixed gain (for research comparison)"
            option: "RMS matched (for listening)"
            option: "Peak normalized"
        boolean: "Draw_visualization", draw_visualization
        boolean: "Show_statistics", show_statistics
        boolean: "Keep_intermediate_files", keep_intermediate_files
        boolean: "Debug", debug
        comment: "Sustain-Aware / Voices / Processes (Legacy ignores these):"
        real: "Max_natural_tail_s", string$(max_natural_tail_s)
        positive: "Release_ms", string$(release_ms)
        positive: "Crossfade_ms", string$(crossfade_ms)
        real: "Sustain_sensitivity", string$(sustain_sensitivity)
        optionmenu: "Final_boundary", final_boundary
            option: "Fixed duration (trim with release)"
            option: "Let tails finish"
        positive: "Evolution_ms", string$(evolution_ms)
        boolean: "Preserve_tails", preserve_tails
        positive: "Morph_s", string$(morph_s)
        comment: "Persistent Processes: end-of-file fade; 0 disables it."
        real: "Final_fade_s", string$(final_fade_s)
        optionmenu: "Articulation", articulation
            option: "Activity phrases"
            option: "Source attacks"
    clicked = endPause: "Cancel", "Continue", 2, 1
    if clicked = 1
        exit
    endif
endif

# ---- VALIDATION ----
if duration_s < 0.5 or duration_s > 180
    exitScript: "Duration_s must be between 0.5 and 180 seconds."
endif
if seed < 0
    exitScript: "Seed must be a non-negative integer."
endif
if coupling < 0 or coupling > 20
    exitScript: "Coupling must be between 0 and 20."
endif
if memory_s < 0.10 or memory_s > 120
    exitScript: "Memory_s must be between 0.10 and 120 seconds (simulation tick = 0.10 s)."
endif
if selection_temperature < 0.001 or selection_temperature > 10
    exitScript: "Selection_temperature must be between 0.001 and 10."
endif
if event_strength < 0 or event_strength > 20
    exitScript: "Event_strength must be between 0 and 20."
endif
if event_decay_s < 0.01 or event_decay_s > 30
    exitScript: "Event_decay_s must be between 0.01 and 30 seconds."
endif
if selection_gain < 0 or selection_gain > 10
    exitScript: "Selection_gain must be between 0 and 10."
endif
if max_natural_tail_s < 0 or max_natural_tail_s > 30
    exitScript: "Max_natural_tail_s must be between 0 and 30 seconds."
endif
if release_ms < 1 or release_ms > 2000
    exitScript: "Release_ms must be between 1 and 2000 ms."
endif
if crossfade_ms < 1 or crossfade_ms > 500
    exitScript: "Crossfade_ms must be between 1 and 500 ms."
endif
if sustain_sensitivity < 0 or sustain_sensitivity > 1
    exitScript: "Sustain_sensitivity must be between 0 and 1."
endif
if evolution_ms < 10 or evolution_ms > 3000
    exitScript: "Evolution_ms must be between 10 and 3000 ms."
endif
if morph_s < 0.05 or morph_s > 10
    exitScript: "Morph_s must be between 0.05 and 10 seconds."
endif
if final_fade_s < 0 or final_fade_s > 10
    exitScript: "Final_fade_s must be between 0 and 10 seconds."
endif
if articulation = 1
    articulationMode$ = "phrases"
else
    articulationMode$ = "attacks"
endif
if rendering = 2
    renderMode$ = "sustain"
elsif rendering = 3
    renderMode$ = "voices"
elsif rendering = 4
    renderMode$ = "process"
else
    renderMode$ = "legacy"
endif
if final_boundary = 1
    tailPolicy$ = "fixed"
else
    tailPolicy$ = "extend"
endif
if feedback_reference = 1
    referenceMode$ = "legacy"
else
    referenceMode$ = "independent"
endif
if central_reference = 1
    centralReferenceMode$ = "legacy"
else
    centralReferenceMode$ = "mean_g"
endif
if event_feedback = 1
    eventMode$ = "off"
elsif event_feedback = 2
    eventMode$ = "hybrid"
else
    eventMode$ = "fast_only"
endif

# The preset controls only K, never numeric knobs the user explicitly set.
if network_preset = 1
    matrix$ = "0,0.3,-0.8;-0.8,0,0.3;0.3,-0.8,0"
    networkLabel$ = "Cyclic inhibition"
elsif network_preset = 2
    matrix$ = "0,0.5,0.5;0.5,0,0.5;0.5,0.5,0"
    networkLabel$ = "Cooperative"
elsif network_preset = 3
    matrix$ = "0,-0.5,-0.5;-0.5,0,-0.5;-0.5,-0.5,0"
    networkLabel$ = "Competitive"
else
    matrix$ = custom_matrix$
    networkLabel$ = "Custom"
endif
# Strict allow-list blocks quotes, shell metacharacters, path expansions and
# whitespace BEFORE matrix$ can appear in the command line. The Python engine
# additionally validates finite 3x3 entries and a zero diagonal.
if replace_regex$(matrix$, "[^0-9eE+.,;-]", "", 0) <> matrix$
    exitScript: "Invalid matrix characters. Use only numeric values, commas, and semicolons (no spaces, quotes, or shell characters)."
endif
if length(matrix$) - length(replace_regex$(matrix$, ";", "", 0)) <> 2
    exitScript: "Custom_matrix must contain exactly 3 rows separated by 2 semicolons."
endif
if length(matrix$) - length(replace_regex$(matrix$, ",", "", 0)) <> 6
    exitScript: "Custom_matrix must contain exactly 3 numbers per row (6 commas total)."
endif

if output_normalization = 1
    norm$ = "fixed"
elsif output_normalization = 2
    norm$ = "rms"
else
    norm$ = "peak"
endif

if architecture = 1
    conditionsArg$ = "0 1 2"
    selectedLabel$ = "All three"
elsif architecture = 2
    conditionsArg$ = "0"
    selectedLabel$ = "Independent"
elsif architecture = 3
    conditionsArg$ = "1"
    selectedLabel$ = "Centralized"
else
    conditionsArg$ = "2"
    selectedLabel$ = "Decentralized"
endif

# ---- OUTPUT PATHS ----
# Scratch is unique per run. Keep_intermediate_files switches the run folder
# to the working directory, so events/states/CSVs can be examined later.
runTag$ = "DCE_" + string$(randomInteger(100000, 999999))
if keep_intermediate_files
    runFolder$ = defaultDirectory$ + "/" + runTag$
else
    runFolder$ = temporaryDirectory$ + "/temp_" + runTag$
endif
createFolder: runFolder$
inputWav$ = runFolder$ + "/temp_dce_input.wav"
corpusPath$ = runFolder$ + "/corpus.tsv"
logPath$ = runFolder$ + "/engine.log"
sustainPath$ = runFolder$ + "/corpus_sustain.tsv"
probePath$ = runFolder$ + "/temp_dce_probe.ok"
probeLogPath$ = runFolder$ + "/python_probe.log"

# The renderer creates these paths as files, not Praat objects.
for c from 0 to 2
    resultWav$[c + 1] = runFolder$ + "/c" + string$(c) + "_s" + string$(seed) + ".wav"
    resultStates$[c + 1] = runFolder$ + "/c" + string$(c) + "_s" + string$(seed) + "_states.tsv"
    resultEvents$[c + 1] = runFolder$ + "/c" + string$(c) + "_s" + string$(seed) + "_events.tsv"
    resultRender$[c + 1] = runFolder$ + "/c" + string$(c) + "_s" + string$(seed) + "_render.tsv"
    resultRenderStats$[c + 1] = runFolder$ + "/c" + string$(c) + "_s" + string$(seed) + "_render_stats.txt"
endfor

# Normalize all file paths before using them in a shell command.
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
inputWavJ$ = replace_regex$(inputWav$, "\\", "/", 0)
runFolderJ$ = replace_regex$(runFolder$, "\\", "/", 0)
logPathJ$ = replace_regex$(logPath$, "\\", "/", 0)
probePathJ$ = replace_regex$(probePath$, "\\", "/", 0)
probeLogPathJ$ = replace_regex$(probeLogPath$, "\\", "/", 0)

# ---- PROCEDURES ----
procedure cleanUpScratch
    if fileReadable(probePath$)
        deleteFile: probePath$
    endif
    if fileReadable(probeLogPath$) and not keep_intermediate_files
        deleteFile: probeLogPath$
    endif
endproc

procedure cleanUpArtifacts
    if not keep_intermediate_files
        if fileReadable(inputWav$)
            deleteFile: inputWav$
        endif
        if fileReadable(corpusPath$)
            deleteFile: corpusPath$
        endif
        if fileReadable(sustainPath$)
            deleteFile: sustainPath$
        endif
        if fileReadable(logPath$)
            deleteFile: logPath$
        endif
        for .c from 1 to 3
            if fileReadable(resultWav$[.c])
                deleteFile: resultWav$[.c]
            endif
            if fileReadable(resultStates$[.c])
                deleteFile: resultStates$[.c]
            endif
            if fileReadable(resultEvents$[.c])
                deleteFile: resultEvents$[.c]
            endif
            if fileReadable(resultRender$[.c])
                deleteFile: resultRender$[.c]
            endif
            if fileReadable(resultRenderStats$[.c])
                deleteFile: resultRenderStats$[.c]
            endif
        endfor
    endif
endproc

# DCE summary figure (v0.1.5.6): one column per condition, four data rows
# (activity, external drive, event pulse, event map) and a statistics panel.
# Every row in every column shares one time axis; the drive row shares one
# symmetric scale across columns so the three architectures can be compared.
# Drawing order per panel follows the library frame rules:
#   Font size -> Select inner viewport -> Axes -> draw -> re-select -> box/marks.

procedure dceSanitize: .s$
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    dceSafe$ = .s$
endproc

# Smallest 1 / 2 / 5 x 10^k that is >= .x
procedure dceNice: .x
    if .x <= 0 or .x = undefined
        dceNiceValue = 1
    else
        .p = 10 ^ floor(log10(.x))
        .m = .x / .p
        if .m <= 1.000001
            .f = 1
        elsif .m <= 2.000001
            .f = 2
        elsif .m <= 5.000001
            .f = 5
        else
            .f = 10
        endif
        dceNiceValue = .f * .p
    endif
endproc

# fixed$ with a real zero ("0.00", not "0") and no runaway digits.
procedure dceFmt: .x, .d
    if .x = undefined
        dceF$ = "n/a"
    else
        .r = round(.x * 10 ^ .d) / 10 ^ .d
        if .r = 0
            dceF$ = "0"
            if .d > 0
                dceF$ = "0." + left$("0000000000", .d)
            endif
        else
            dceF$ = fixed$(.r, .d)
        endif
    endif
endproc

procedure dceSigned: .x, .d
    @dceFmt: .x, .d
    if .x <> undefined and dceF$ <> "n/a" and left$(dceF$, 1) <> "-"
        dceF$ = "+" + dceF$
    endif
endproc

procedure dceTimeMarks: .numbers$
    Colour: dceGrid$
    Marks bottom every: 1, dceTimeStep, .numbers$, "yes", "no"
endproc

procedure drawDceCase
    .n = 0
    .ne = 0

    # Column header
    Font size: 9
    Select inner viewport: caseLeft, caseRight, dceHeadTop, dceHeadBottom
    Axes: 0, 1, 0, 1
    Colour: dceInk$
    Text: 0.5, "centre", 0.5, "half", "##" + caseLabel$ + "##"

    # ---- Load the state series (all rows; Picture drawing is cheap) ----
    Read Table from tab-separated file: caseStates$
    .st = selected("Table")
    .n = Get number of rows
    for .k from 1 to .n
        dceT[.k] = Get value: .k, "time"
        dceA[.k] = Get value: .k, "act_A"
        dceB[.k] = Get value: .k, "act_B"
        dceC[.k] = Get value: .k, "act_C"
        dceG[.k] = Get value: .k, "G"
        dcePA[.k] = Get value: .k, "pulse_A"
        dcePB[.k] = Get value: .k, "pulse_B"
        dcePC[.k] = Get value: .k, "pulse_C"
        dceDA[.k] = Get value: .k, "drive_A"
        dceDB[.k] = Get value: .k, "drive_B"
        dceDC[.k] = Get value: .k, "drive_C"
    endfor
    removeObject: .st

    # ---- Post-burn-in statistics, same window as the engine summary ----
    .k0 = floor(0.1 * .n) + 1
    .m = .n - .k0 + 1
    .sA = 0
    .sB = 0
    .sC = 0
    .qA = 0
    .qB = 0
    .qC = 0
    .xAB = 0
    .xAC = 0
    .xBC = 0
    .dA = 0
    .dB = 0
    .dC = 0
    .eA = 0
    .eB = 0
    .eC = 0
    for .k from .k0 to .n
        .sA += dceA[.k]
        .sB += dceB[.k]
        .sC += dceC[.k]
        .qA += dceA[.k] ^ 2
        .qB += dceB[.k] ^ 2
        .qC += dceC[.k] ^ 2
        .xAB += dceA[.k] * dceB[.k]
        .xAC += dceA[.k] * dceC[.k]
        .xBC += dceB[.k] * dceC[.k]
        .dA += dceDA[.k]
        .dB += dceDB[.k]
        .dC += dceDC[.k]
        .eA += dceDA[.k] ^ 2
        .eB += dceDB[.k] ^ 2
        .eC += dceDC[.k] ^ 2
    endfor
    .c = caseColumn
    if .m >= 2
        dceMeanA[.c] = .sA / .m
        dceMeanB[.c] = .sB / .m
        dceMeanC[.c] = .sC / .m
        .vA = max(0, .qA / .m - dceMeanA[.c] ^ 2)
        .vB = max(0, .qB / .m - dceMeanB[.c] ^ 2)
        .vC = max(0, .qC / .m - dceMeanC[.c] ^ 2)
        dceSdA[.c] = sqrt(.vA)
        dceSdB[.c] = sqrt(.vB)
        dceSdC[.c] = sqrt(.vC)
        .cAB = .xAB / .m - dceMeanA[.c] * dceMeanB[.c]
        .cAC = .xAC / .m - dceMeanA[.c] * dceMeanC[.c]
        .cBC = .xBC / .m - dceMeanB[.c] * dceMeanC[.c]
        dceRAB[.c] = undefined
        dceRAC[.c] = undefined
        dceRBC[.c] = undefined
        if .vA * .vB > 1e-12
            dceRAB[.c] = .cAB / sqrt(.vA * .vB)
        endif
        if .vA * .vC > 1e-12
            dceRAC[.c] = .cAC / sqrt(.vA * .vC)
        endif
        if .vB * .vC > 1e-12
            dceRBC[.c] = .cBC / sqrt(.vB * .vC)
        endif
        dceDsA[.c] = sqrt(max(0, .eA / .m - (.dA / .m) ^ 2))
        dceDsB[.c] = sqrt(max(0, .eB / .m - (.dB / .m) ^ 2))
        dceDsC[.c] = sqrt(max(0, .eC / .m - (.dC / .m) ^ 2))
    else
        dceMeanA[.c] = undefined
        dceMeanB[.c] = undefined
        dceMeanC[.c] = undefined
        dceSdA[.c] = undefined
        dceSdB[.c] = undefined
        dceSdC[.c] = undefined
        dceRAB[.c] = undefined
        dceRAC[.c] = undefined
        dceRBC[.c] = undefined
        dceDsA[.c] = undefined
        dceDsB[.c] = undefined
        dceDsC[.c] = undefined
    endif

    # ================= I  ACTIVITY =================
    Font size: 6
    Select inner viewport: caseLeft, caseRight, dceTop1, dceBot1
    Axes: 0, duration_s, 0, 1
    Paint rectangle: dcePlate$, 0, duration_s, 0, 1
    @dceTimeMarks: "no"
    Select inner viewport: caseLeft, caseRight, dceTop1, dceBot1
    Axes: 0, duration_s, 0, 1
    Line width: 1.1
    for .k from 2 to .n
        Colour: dceRed$
        Draw line: dceT[.k - 1], dceA[.k - 1], dceT[.k], dceA[.k]
        Colour: dceBlue$
        Draw line: dceT[.k - 1], dceB[.k - 1], dceT[.k], dceB[.k]
        Colour: dceGreen$
        Draw line: dceT[.k - 1], dceC[.k - 1], dceT[.k], dceC[.k]
    endfor
    if caseLabel$ = "Centralized"
        Colour: dceInk$
        # Dashes are drawn explicitly (about 0.3 s on / 0.3 s off): Praat's own
        # Dashed line restarts on every 0.1 s segment and looks solid.
        Line width: 1.6
        .dashTicks = max(1, round(0.3 / max(1e-6, dceT[2] - dceT[1])))
        for .k from 2 to .n
            if floor((.k - 2) / .dashTicks) mod 2 = 0
                Draw line: dceT[.k - 1], dceG[.k - 1], dceT[.k], dceG[.k]
            endif
        endfor
    endif
    Line width: 1
    Select inner viewport: caseLeft, caseRight, dceTop1, dceBot1
    Axes: 0, duration_s, 0, 1
    Colour: "Black"
    Draw inner box
    if caseIsFirst
        Select inner viewport: caseLeft, caseRight, dceTop1, dceBot1
        Axes: 0, duration_s, 0, 1
        Colour: dceLabel$
        One mark left: 0, "yes", "yes", "no", ""
        One mark left: 0.5, "yes", "yes", "no", ""
        One mark left: 1, "yes", "yes", "no", ""
    endif

    # ================= II  EXTERNAL DRIVE =================
    Font size: 6
    Select inner viewport: caseLeft, caseRight, dceTop2, dceBot2
    Axes: 0, duration_s, -dceDriveRange, dceDriveRange
    Paint rectangle: dcePlate$, 0, duration_s, -dceDriveRange, dceDriveRange
    @dceTimeMarks: "no"
    Select inner viewport: caseLeft, caseRight, dceTop2, dceBot2
    Axes: 0, duration_s, -dceDriveRange, dceDriveRange
    Colour: dceFaint$
    Dotted line
    Draw line: 0, 0, duration_s, 0
    Solid line
    Line width: 1.0
    for .k from 2 to .n
        Colour: dceRed$
        Draw line: dceT[.k - 1], dceDA[.k - 1], dceT[.k], dceDA[.k]
        Colour: dceBlue$
        Draw line: dceT[.k - 1], dceDB[.k - 1], dceT[.k], dceDB[.k]
        Colour: dceGreen$
        Draw line: dceT[.k - 1], dceDC[.k - 1], dceT[.k], dceDC[.k]
    endfor
    Line width: 1
    Select inner viewport: caseLeft, caseRight, dceTop2, dceBot2
    Axes: 0, duration_s, -dceDriveRange, dceDriveRange
    Colour: "Black"
    Draw inner box
    if caseIsFirst
        Select inner viewport: caseLeft, caseRight, dceTop2, dceBot2
        Axes: 0, duration_s, -dceDriveRange, dceDriveRange
        Colour: dceLabel$
        One mark left: -dceDriveRange, "yes", "yes", "no", ""
        One mark left: 0, "yes", "yes", "no", ""
        One mark left: dceDriveRange, "yes", "yes", "no", ""
    endif

    # ================= III  EVENT PULSE =================
    Font size: 6
    Select inner viewport: caseLeft, caseRight, dceTop3, dceBot3
    Axes: 0, duration_s, 0, 1
    Paint rectangle: dcePlate$, 0, duration_s, 0, 1
    @dceTimeMarks: "no"
    Select inner viewport: caseLeft, caseRight, dceTop3, dceBot3
    Axes: 0, duration_s, 0, 1
    Line width: 1.0
    for .k from 2 to .n
        Colour: dceRed$
        Draw line: dceT[.k - 1], dcePA[.k - 1], dceT[.k], dcePA[.k]
        Colour: dceBlue$
        Draw line: dceT[.k - 1], dcePB[.k - 1], dceT[.k], dcePB[.k]
        Colour: dceGreen$
        Draw line: dceT[.k - 1], dcePC[.k - 1], dceT[.k], dcePC[.k]
    endfor
    Line width: 1
    Select inner viewport: caseLeft, caseRight, dceTop3, dceBot3
    Axes: 0, duration_s, 0, 1
    Colour: "Black"
    Draw inner box
    if caseIsFirst
        Select inner viewport: caseLeft, caseRight, dceTop3, dceBot3
        Axes: 0, duration_s, 0, 1
        Colour: dceLabel$
        One mark left: 0, "yes", "yes", "no", ""
        One mark left: 1, "yes", "yes", "no", ""
    endif

    # ================= IV  EVENT MAP =================
    # Drawn from the rendered event log: every event, tick height = gain.
    Read Table from tab-separated file: caseEvents$
    .ev = selected("Table")
    .ne = Get number of rows
    .nA = 0
    .nB = 0
    .nC = 0
    .hA = 0
    .hB = 0
    .hC = 0
    Font size: 6
    Select inner viewport: caseLeft, caseRight, dceTop4, dceBot4
    Axes: 0, duration_s, 0.5, 3.5
    Paint rectangle: dcePlate$, 0, duration_s, 0.5, 3.5
    @dceTimeMarks: "no"
    Select inner viewport: caseLeft, caseRight, dceTop4, dceBot4
    Axes: 0, duration_s, 0.5, 3.5
    Colour: dceFaint$
    Dotted line
    for .lane from 1 to 3
        Draw line: 0, .lane, duration_s, .lane
    endfor
    Solid line
    # Sustain-Aware: pale bar = the rendered extent of each event (grain + natural
    # tail, after handoff / boundary trimming), read from the renderer's own log.
    if rendering >= 2 and fileReadable(caseRender$)
        Read Table from tab-separated file: caseRender$
        .rt = selected("Table")
        .nr = Get number of rows
        Select inner viewport: caseLeft, caseRight, dceTop4, dceBot4
        Axes: 0, duration_s, 0.5, 3.5
        Line width: 3.0
        for .k from 1 to .nr
            selectObject: .rt
            .who$ = Get value: .k, "agent"
            .t0 = Get value: .k, "time"
            .dd = Get value: .k, "dur_s"
            .t1 = min(duration_s, .t0 + .dd)
            if .t1 > .t0 and .t0 < duration_s
                if .who$ = "A"
                    Colour: dceRedPale$
                    .y = 3
                elsif .who$ = "B"
                    Colour: dceBluePale$
                    .y = 2
                else
                    Colour: dceGreenPale$
                    .y = 1
                endif
                Draw line: .t0, .y, .t1, .y
            endif
        endfor
        removeObject: .rt
    endif
    Line width: 1.2
    for .k from 1 to .ne
        selectObject: .ev
        .who$ = Get value: .k, "agent"
        .when = Get value: .k, "time"
        .gain = Get value: .k, "gain"
        .ent = Get value: .k, "sel_entropy"
        if .who$ = "A"
            .nA += 1
            .hA += .ent
            .y = 3
            Colour: dceRed$
        elsif .who$ = "B"
            .nB += 1
            .hB += .ent
            .y = 2
            Colour: dceBlue$
        else
            .nC += 1
            .hC += .ent
            .y = 1
            Colour: dceGreen$
        endif
        .half = 0.42 * min(1, max(0.1, .gain))
        Draw line: .when, .y - .half, .when, .y + .half
    endfor
    removeObject: .ev
    Line width: 1
    Select inner viewport: caseLeft, caseRight, dceTop4, dceBot4
    Axes: 0, duration_s, 0.5, 3.5
    Colour: "Black"
    Draw inner box
    Select inner viewport: caseLeft, caseRight, dceTop4, dceBot4
    Axes: 0, duration_s, 0.5, 3.5
    Colour: dceLabel$
    Marks bottom every: 1, dceTimeStep, "yes", "yes", "no"
    if caseIsFirst
        One mark left: 3, "no", "yes", "no", "A"
        One mark left: 2, "no", "yes", "no", "B"
        One mark left: 1, "no", "yes", "no", "C"
    endif

    # Time-axis caption under the bottom row (text strip, own viewport)
    Font size: 6
    Select inner viewport: caseLeft, caseRight, dceTimeTop, dceTimeBottom
    Axes: 0, 1, 0, 1
    Colour: dceLabel$
    Text: 0.5, "centre", 0.5, "half", "Time (s)"

    dceNev[.c] = .ne
    dceNA[.c] = .nA
    dceNB[.c] = .nB
    dceNC[.c] = .nC
    dceGA[.c] = undefined
    dceGB[.c] = undefined
    dceGC[.c] = undefined
    if .nA > 0
        dceGA[.c] = exp(.hA / .nA)
    endif
    if .nB > 0
        dceGB[.c] = exp(.hB / .nB)
    endif
    if .nC > 0
        dceGC[.c] = exp(.hC / .nC)
    endif
    dceColLabel$[.c] = caseLabel$
    dceStats$[.c] = ""
    if fileReadable(caseStats$)
        dceStats$[.c] = newline$ + readFile$(caseStats$)
    endif
    dceColCentre[.c] = (caseLeft + caseRight) / 2
endproc

procedure dceRowCaption: .top, .bottom, .text$
    Font size: 7
    Select inner viewport: dceLeft, dceRight, .top, .bottom
    Axes: 0, 1, 0, 1
    Colour: dceLabel$
    Text: 0, "left", 0.5, "half", .text$
endproc

procedure drawDceFigure
    # ---- palette (library structural greys + RGB agent colours) ----
    dceInk$ = "{0.25, 0.25, 0.35}"
    dceLabel$ = "{0.35, 0.35, 0.50}"
    dceFaint$ = "{0.55, 0.55, 0.62}"
    dceGrid$ = "{0.82, 0.82, 0.86}"
    dcePlate$ = "{0.97, 0.97, 0.97}"
    dceSummary$ = "{0.94, 0.94, 0.94}"
    dceRed$ = "{0.85, 0.35, 0.35}"
    dceBlue$ = "{0.35, 0.55, 0.85}"
    dceGreen$ = "{0.35, 0.75, 0.45}"
    dceRedPale$ = "{0.96, 0.78, 0.78}"
    dceBluePale$ = "{0.78, 0.85, 0.96}"
    dceGreenPale$ = "{0.78, 0.92, 0.81}"

    # ---- layout (inches) ----
    dceLeft = 0.60
    dceRight = 7.70
    dceHeadTop = 0.66
    dceHeadBottom = 0.86
    dceCap1 = 0.92
    dceTop1 = 1.08
    dceBot1 = 2.08
    dceCap2 = 2.16
    dceTop2 = 2.32
    dceBot2 = 3.04
    dceCap3 = 3.12
    dceTop3 = 3.28
    dceBot3 = 3.80
    dceCap4 = 3.88
    dceTop4 = 4.04
    dceBot4 = 4.94
    dceTimeTop = 5.08
    dceTimeBottom = 5.20
    dceSumTop = 5.32
    dceSumBottom = 6.60
    dceCanvasH = 6.72

    .nCases = 0
    for .c from 0 to 2
        if architecture = 1 or architecture = .c + 2
            .nCases += 1
        endif
    endfor
    if .nCases = 1
        @dceNice: duration_s / 8
    else
        @dceNice: duration_s / 4
    endif
    dceTimeStep = dceNiceValue

    # ---- common symmetric drive scale across every drawn condition ----
    .dMax = 0
    for .c from 0 to 2
        if architecture = 1 or architecture = .c + 2
            Read Table from tab-separated file: resultStates$[.c + 1]
            .tb = selected("Table")
            .nr = Get number of rows
            if .nr > 0
                for .a from 1 to 3
                    .col$ = "drive_" + mid$("ABC", .a, 1)
                    .hi = Get maximum: .col$
                    .lo = Get minimum: .col$
                    .dMax = max(.dMax, abs(.hi), abs(.lo))
                endfor
            endif
            removeObject: .tb
        endif
    endfor
    if .dMax < 1e-9
        dceDriveRange = 1
    else
        # One decade-step above the data maximum: 6.5 -> 7, 0.32 -> 0.4, 13 -> 20
        .step = 10 ^ floor(log10(.dMax))
        dceDriveRange = ceiling(.dMax / .step * 0.999999) * .step
    endif

    Erase all
    Solid line
    Line width: 1

    # ---- title strip ----
    Font size: 13
    Select inner viewport: dceLeft, dceRight, 0.08, 0.40
    Axes: 0, 1, 0, 1
    Colour: dceInk$
    Text: 0.5, "centre", 0.5, "half", "##DISTRIBUTED CORPUS ECOLOGY##"
    @dceSanitize: sourceName$
    .src$ = dceSafe$
    if architecture = 1 or architecture = 3
        .central$ = "  |  Central ref " + centralReferenceMode$
        .central$ = replace$(.central$, "_", "\_ ", 0)
    else
        .central$ = ""
    endif
    if architecture = 1 or architecture = 4
        .fb$ = "  |  Events " + replace$(eventMode$, "_", "\_ ", 0) + ", ref " + referenceMode$
    else
        .fb$ = ""
    endif
    Font size: 7
    Select inner viewport: dceLeft, dceRight, 0.40, 0.58
    Axes: 0, 1, 0, 1
    Colour: dceFaint$
    Text: 0.5, "centre", 0.5, "half", .src$ + "  |  Seed " + string$(seed) + "  |  " + networkLabel$ + "  |  Coupling " + fixed$(coupling, 2) + "  |  Memory " + fixed$(memory_s, 2) + " s  |  T " + fixed$(selection_temperature, 3) + .fb$ + .central$ + "  |  Norm " + norm$

    # ---- row captions (full width, aligned on one left rail) ----
    @dceRowCaption: dceCap1, dceTop1, "##I##  ACTIVITY  (0-1;  dashed = global trajectory G, Centralized only)"
    Font size: 7
    Select inner viewport: dceLeft, dceRight, dceCap1, dceTop1
    Axes: 0, 1, 0, 1
    Colour: dceRed$
    Text: 0.755, "left", 0.5, "half", "##A## rhythmic"
    Colour: dceBlue$
    Text: 0.840, "left", 0.5, "half", "##B## spectral"
    Colour: dceGreen$
    Text: 0.925, "left", 0.5, "half", "##C## textural"
    @dceRowCaption: dceCap2, dceTop2, "##II##  EXTERNAL DRIVE  (input from outside the agent;  0 = none;  common scale for all columns)"
    @dceRowCaption: dceCap3, dceTop3, "##III##  EVENT PULSE  (decaying onset trace;  the fast feedback signal in Decentralized)"
    if rendering = 4
        @dceRowCaption: dceCap4, dceTop4, "##IV##  EVENT MAP  (decisions;  tick height = gain;  pale bar = the persistent voice each decision updates)"
    elsif rendering = 3
        @dceRowCaption: dceCap4, dceTop4, "##IV##  EVENT MAP  (decisions;  tick height = gain;  pale bar = voice segment until its next evolution or end)"
    elsif rendering = 2
        @dceRowCaption: dceCap4, dceTop4, "##IV##  EVENT MAP  (rendered events;  tick height = event gain;  pale bar = sounding extent incl. natural tail)"
    else
        @dceRowCaption: dceCap4, dceTop4, "##IV##  EVENT MAP  (rendered events;  tick height = event gain)"
    endif

    # ---- columns ----
    .gap = 0.30
    .w = (dceRight - dceLeft - (.nCases - 1) * .gap) / .nCases
    .col = 0
    for .c from 0 to 2
        if architecture = 1 or architecture = .c + 2
            .col += 1
            caseColumn = .col
            caseIsFirst = (.col = 1)
            caseLeft = dceLeft + (.col - 1) * (.w + .gap)
            caseRight = caseLeft + .w
            caseStates$ = resultStates$[.c + 1]
            caseEvents$ = resultEvents$[.c + 1]
            caseRender$ = resultRender$[.c + 1]
            caseStats$ = resultRenderStats$[.c + 1]
            if .c = 0
                caseLabel$ = "Independent"
            elsif .c = 1
                caseLabel$ = "Centralized"
            else
                caseLabel$ = "Decentralized"
            endif
            @drawDceCase
        endif
    endfor

    # ---- summary panel ----
    Font size: 6
    Select inner viewport: dceLeft, dceRight, dceSumTop, dceSumBottom
    Axes: dceLeft, dceRight, 0, 1
    Paint rectangle: dceSummary$, dceLeft, dceRight, 0, 1
    Select inner viewport: dceLeft, dceRight, dceSumTop, dceSumBottom
    Axes: dceLeft, dceRight, 0, 1
    for .col from 1 to .nCases
        .x = dceColCentre[.col]
        Colour: dceInk$
        .rate = dceNev[.col] / duration_s
        @dceFmt: .rate, 2
        Text: .x, "centre", 0.92, "half", "##" + dceColLabel$[.col] + "##   " + string$(dceNev[.col]) + " events  (" + dceF$ + " /s)"
        Colour: dceLabel$
        @dceFmt: dceNA[.col] / duration_s, 2
        .l$ = dceF$
        @dceFmt: dceNB[.col] / duration_s, 2
        .l$ = .l$ + " / " + dceF$
        @dceFmt: dceNC[.col] / duration_s, 2
        Text: .x, "centre", 0.81, "half", "Events/s   " + .l$ + " / " + dceF$
        @dceFmt: dceMeanA[.col], 2
        .l$ = dceF$
        @dceFmt: dceSdA[.col], 2
        .l$ = .l$ + " ± " + dceF$
        @dceFmt: dceMeanB[.col], 2
        .l$ = .l$ + "  /  " + dceF$
        @dceFmt: dceSdB[.col], 2
        .l$ = .l$ + " ± " + dceF$
        @dceFmt: dceMeanC[.col], 2
        .l$ = .l$ + "  /  " + dceF$
        @dceFmt: dceSdC[.col], 2
        Text: .x, "centre", 0.70, "half", "Activity   " + .l$ + " ± " + dceF$
        @dceSigned: dceRAB[.col], 2
        .l$ = "AB " + dceF$
        @dceSigned: dceRAC[.col], 2
        .l$ = .l$ + "   AC " + dceF$
        @dceSigned: dceRBC[.col], 2
        Text: .x, "centre", 0.59, "half", "Activity r   " + .l$ + "   BC " + dceF$
        @dceFmt: dceDsA[.col], 2
        .l$ = dceF$
        @dceFmt: dceDsB[.col], 2
        .l$ = .l$ + " / " + dceF$
        @dceFmt: dceDsC[.col], 2
        Text: .x, "centre", 0.48, "half", "Drive sd   " + .l$ + " / " + dceF$
        @dceFmt: dceGA[.col], 1
        .l$ = dceF$
        @dceFmt: dceGB[.col], 1
        .l$ = .l$ + " / " + dceF$
        @dceFmt: dceGC[.col], 1
        Text: .x, "centre", 0.37, "half", "Effective grains   " + .l$ + " / " + dceF$
        .st$ = dceStats$[.col]
        if .st$ <> ""
            .ovl = extractNumber(.st$, newline$ + "max_overlap=")
            @dceFmt: extractNumber(.st$, newline$ + "rms_dbfs="), 1
            .rmsTxt$ = dceF$
            if index(.st$, "mode=process") > 0
                .pv = extractNumber(.st$, newline$ + "voices=")
                @dceFmt: extractNumber(.st$, newline$ + "decisions_per_voice="), 1
                .dpv$ = dceF$
                @dceFmt: extractNumber(.st$, newline$ + "voice_mean_s="), 2
                Text: .x, "centre", 0.26, "half", "Process   voices " + string$(.pv) + "   decisions/voice " + .dpv$ + "   mean voice " + dceF$ + " s"
            elsif index(.st$, "mode=voices") > 0
                .vat = extractNumber(.st$, newline$ + "attacks=") + extractNumber(.st$, newline$ + "entries=")
                .vev = extractNumber(.st$, newline$ + "evolutions=")
                @dceFmt: extractNumber(.st$, newline$ + "voice_mean_s="), 2
                Text: .x, "centre", 0.26, "half", "Voices   attacks " + string$(.vat) + "   evolutions " + string$(.vev) + "   mean voice " + dceF$ + " s   overlap " + string$(.ovl)
            elsif index(.st$, "mode=sustain") > 0
                .nev = extractNumber(.st$, newline$ + "events=")
                .ext = extractNumber(.st$, newline$ + "extended=")
                .rel = extractNumber(.st$, newline$ + "release=") + extractNumber(.st$, newline$ + "boundary=")
                .hof = extractNumber(.st$, newline$ + "handoff=")
                Text: .x, "centre", 0.26, "half", "Sustain   tails " + string$(.ext) + "/" + string$(.nev) + "   release " + string$(.rel) + "   handoff " + string$(.hof) + "   overlap " + string$(.ovl)
            else
                Text: .x, "centre", 0.26, "half", "Legacy render   overlap " + string$(.ovl) + "   RMS " + .rmsTxt$ + " dBFS"
            endif
        endif
    endfor
    Colour: dceFaint$
    @dceFmt: dceDriveRange, 2 * (dceDriveRange < 1)
    Text: (dceLeft + dceRight) / 2, "centre", 0.08, "half", "Values are A / B / C.  Activity, r and drive: post-burn-in (first tenth of ticks discarded, as in the engine log).  Effective grains = exp(mean selection entropy).  Drive scale ±" + dceF$ + "."
    Select inner viewport: dceLeft, dceRight, dceSumTop, dceSumBottom
    Axes: dceLeft, dceRight, 0, 1
    Colour: "Black"
    Draw inner box

    # Leave the whole canvas selected so Save/Copy exports the full figure.
    Colour: "Black"
    Font size: 10
    Select outer viewport: 0, 8, 0, dceCanvasH
endproc


# ---- INITIAL INFORMATION ----
clearinfo
writeInfoLine: "=== Distributed Corpus Ecology v0.1.7 - Persistent Sonic Processes ==="
appendInfoLine: "Source: ", sourceName$
appendInfoLine: "Architecture: ", selectedLabel$
appendInfoLine: "Network: ", networkLabel$
appendInfoLine: "Seed: ", seed, " | Duration: ", fixed$(duration_s, 2), " s"
appendInfoLine: "Coupling ", fixed$(coupling, 3), " | Memory ", fixed$(memory_s, 2), " s | Temperature ", fixed$(selection_temperature, 3)
appendInfoLine: "Couple activity (slow AND fast): ", couple_activity, " | Couple grain selection: ", couple_grain_selection, " | Subtick: ", subtick_onsets
appendInfoLine: "Event feedback: ", eventMode$, " | Strength: ", fixed$(event_strength, 2), " | Decay: ", fixed$(event_decay_s, 2), " s"
appendInfoLine: "Feedback reference: ", referenceMode$, " | Selection gain: ", fixed$(selection_gain, 2), " | Pulse rate normalization: ", pulse_rate_normalize
appendInfoLine: "Central reference: ", centralReferenceMode$
if architecture = 2 or architecture = 4
    appendInfoLine: "NOTE: Central_reference affects only Centralized; this selection does not use it."
endif
if architecture <> 1 and architecture <> 4 and event_feedback <> 1
    appendInfoLine: "NOTE: Fast event response affects only Decentralized; this selection does not use it."
endif
appendInfoLine: "Normalization: ", norm$
if rendering = 4
    appendInfoLine: "Rendering: Persistent Processes | morph ", fixed$(morph_s, 2), " s | articulation ", articulationMode$, " | final fade ", fixed$(final_fade_s, 2), " s | release ", fixed$(release_ms, 0), " ms | boundary ", tailPolicy$
elsif rendering = 3
    appendInfoLine: "Rendering: Continuous Voices | evolution ", fixed$(evolution_ms, 0), " ms | max tail ", fixed$(max_natural_tail_s, 2), " s | release ", fixed$(release_ms, 0), " ms | entry fade ", fixed$(crossfade_ms, 0), " ms | sensitivity ", fixed$(sustain_sensitivity, 2), " | boundary ", tailPolicy$
elsif rendering = 2
    appendInfoLine: "Rendering: Sustain-Aware (preserve tails ", preserve_tails, ") | max tail ", fixed$(max_natural_tail_s, 2), " s | release ", fixed$(release_ms, 0), " ms | crossfade ", fixed$(crossfade_ms, 0), " ms | sensitivity ", fixed$(sustain_sensitivity, 2), " | boundary ", tailPolicy$
else
    appendInfoLine: "Rendering: Fragmented (Legacy) - identical audio to v0.1.5.5"
endif
appendInfoLine: "Engine: ", pythonScript$
appendInfoLine: "Python executable: ", pythonCmd$
appendInfoLine: ""

# ---- PYTHON INTERPRETER / DEPENDENCY PROBE ----
# Use the same shell command style as Anomaly_Outlier_Extractor.praat:
# a bare command name (python or py -3) followed by -c "...".
# Do NOT quote the bare command name as "python" on Windows.  On some
# Praat/Windows CMD combinations that changes command-line interpretation.
# A failed marker alone proves neither that Python nor a package is missing;
# capture the actual error and try the Windows Python launcher as fallback.
appendInfoLine: "[0/3] Checking Python interpreter and packages..."
pythonCandidate$[1] = pythonCmd$
nPythonCandidates = 1
if windows
    nPythonCandidates = 3
    pythonCandidate$[2] = "py -3"
    pythonCandidate$[3] = "python3"
endif
probeImports$ = "import sys, numpy, scipy, librosa, soundfile; open('" + probePathJ$ + "', 'w').write(sys.executable)"
pythonFound = 0
for .i from 1 to nPythonCandidates
    if not pythonFound
        pythonCmd$ = pythonCandidate$[.i]
        if fileReadable(probePath$)
            deleteFile: probePath$
        endif
        if fileReadable(probeLogPath$)
            deleteFile: probeLogPath$
        endif
        probeCmd$ = pythonCmd$ + " -c """ + probeImports$ + """ > """ + probeLogPathJ$ + """ 2>&1"
        if debug
            appendInfoLine: "Probe command: ", probeCmd$
        endif
        runSystem_nocheck: probeCmd$
        if fileReadable(probePath$)
            pythonFound = 1
            pythonExecutable$ = readFile$(probePath$)
            appendInfoLine: "  Python command: ", pythonCmd$
            appendInfoLine: "  Interpreter: ", pythonExecutable$
        else
            appendInfoLine: "  Probe failed for: ", pythonCmd$
            if fileReadable(probeLogPath$)
                appendInfoLine: readFile$(probeLogPath$)
            else
                appendInfoLine: "  No diagnostic output was written. Check shell access and temporary folder permissions."
            endif
        endif
    endif
endfor
if not pythonFound
    exitScript: "No compatible Python interpreter passed the dependency probe." + newline$ + "Inspect the Info window for the precise errors and Python commands tested." + newline$ + "Install missing packages with the SAME Python that Praat uses, e.g. python -m pip install numpy scipy librosa soundfile."
endif
@cleanUpScratch

# ---- EXPORT SOURCE (NO CHANNEL LOSS ON THE PRAAT SIDE) ----
appendInfoLine: "[1/3] Exporting selected Sound as 32-bit float WAV..."
selectObject: sourceSound
Save as 32-bit WAV file: inputWav$
if not fileReadable(inputWav$)
    exitScript: "Could not export the selected Sound: " + inputWav$
endif

# ---- ONE ENGINE INVOCATION FOR EVERY ARCHITECTURE ----
# Quoting follows other Praat AudioTools shell wrappers. Double-quote every
# path, and pass --set values individually; no JSON or shell configuration.
appendInfoLine: "[2/3] Analyzing corpus, simulating agents, rendering..."
pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """ run """ + inputWavJ$ + """"
pythonCall$ = pythonCall$ + " --conditions " + conditionsArg$ + " --seeds " + string$(seed)
pythonCall$ = pythonCall$ + " --norm " + norm$
pythonCall$ = pythonCall$ + " --set ""duration=" + fixed$(duration_s, 6) + """"
pythonCall$ = pythonCall$ + " --set ""coupling=" + fixed$(coupling, 6) + """"
pythonCall$ = pythonCall$ + " --set ""memory_tau=" + fixed$(memory_s, 6) + """"
pythonCall$ = pythonCall$ + " --set ""temperature=" + fixed$(selection_temperature, 6) + """"
pythonCall$ = pythonCall$ + " --set ""coupling_activity=" + string$(couple_activity) + """"
pythonCall$ = pythonCall$ + " --set ""coupling_selection=" + string$(couple_grain_selection) + """"
pythonCall$ = pythonCall$ + " --set ""selection_gain=" + fixed$(selection_gain, 6) + """"
pythonCall$ = pythonCall$ + " --set ""feedback_reference=" + referenceMode$ + """"
pythonCall$ = pythonCall$ + " --set ""central_reference=" + centralReferenceMode$ + """"
pythonCall$ = pythonCall$ + " --set ""pulse_rate_normalize=" + string$(pulse_rate_normalize) + """"
pythonCall$ = pythonCall$ + " --set ""subtick=" + string$(subtick_onsets) + """"
pythonCall$ = pythonCall$ + " --set ""event_mode=" + eventMode$ + """"
pythonCall$ = pythonCall$ + " --set ""event_strength=" + fixed$(event_strength, 6) + """"
pythonCall$ = pythonCall$ + " --set ""event_decay_s=" + fixed$(event_decay_s, 6) + """"
pythonCall$ = pythonCall$ + " --set ""K=" + matrix$ + """"
# Rendering options are not simulation settings: the event log is identical in both modes.
pythonCall$ = pythonCall$ + " --render-mode " + renderMode$ + " --tail-policy " + tailPolicy$
pythonCall$ = pythonCall$ + " --max-tail " + fixed$(max_natural_tail_s, 6) + " --release-ms " + fixed$(release_ms, 6)
pythonCall$ = pythonCall$ + " --crossfade-ms " + fixed$(crossfade_ms, 6) + " --sustain-sensitivity " + fixed$(sustain_sensitivity, 6)
pythonCall$ = pythonCall$ + " --evolution-ms " + fixed$(evolution_ms, 6) + " --preserve-tails " + string$(preserve_tails)
pythonCall$ = pythonCall$ + " --morph-s " + fixed$(morph_s, 6) + " --articulation " + articulationMode$
pythonCall$ = pythonCall$ + " --final-fade-s " + fixed$(final_fade_s, 6)
pythonCall$ = pythonCall$ + " -o """ + runFolderJ$ + """ > """ + logPathJ$ + """ 2>&1"
if debug
    appendInfoLine: "Command: ", pythonCall$
endif
runSystem_nocheck: pythonCall$

# Validate every requested output; log persists if a run failed.
if not fileReadable(corpusPath$)
    if fileReadable(logPath$)
        appendInfoLine: readFile$(logPath$)
    endif
    exitScript: "DCE Python engine failed before creating corpus.tsv." + newline$ + "Debug files preserved at: " + runFolder$
endif
for c from 0 to 2
    if architecture = 1 or architecture = c + 2
        if not fileReadable(resultWav$[c + 1]) or not fileReadable(resultStates$[c + 1]) or not fileReadable(resultEvents$[c + 1])
            if fileReadable(logPath$)
                appendInfoLine: readFile$(logPath$)
            endif
            exitScript: "DCE Python engine did not produce the expected output for condition " + string$(c) + "." + newline$ + "Debug files preserved at: " + runFolder$
        endif
    endif
endfor

if (debug or show_statistics) and fileReadable(logPath$)
    appendInfoLine: "--- Python engine diagnostics ---"
    appendInfoLine: readFile$(logPath$)
endif

# ---- IMPORT GENERATED SOUNDS ----
appendInfoLine: "[3/3] Importing outputs into Praat Objects..."
nResults = 0
for c from 0 to 2
    if architecture = 1 or architecture = c + 2
        Read from file: resultWav$[c + 1]
        resultSound[c + 1] = selected("Sound")
        if c = 0
            Rename: sourceName$ + "_DCE_Independent_s" + string$(seed)
        elsif c = 1
            if centralReferenceMode$ = "mean_g"
                Rename: sourceName$ + "_DCE_Centralized_MeanG_s" + string$(seed)
            else
                Rename: sourceName$ + "_DCE_Centralized_Legacy_s" + string$(seed)
            endif
        else
            if referenceMode$ = "independent"
                referenceSuffix$ = "Baseline"
            else
                referenceSuffix$ = "Legacy"
            endif
            if event_feedback = 1
                Rename: sourceName$ + "_DCE_Decentralized_Off_" + referenceSuffix$ + "_s" + string$(seed)
            elsif event_feedback = 2
                Rename: sourceName$ + "_DCE_Decentralized_Hybrid_" + referenceSuffix$ + "_s" + string$(seed)
            else
                Rename: sourceName$ + "_DCE_Decentralized_FastOnly_" + referenceSuffix$ + "_s" + string$(seed)
            endif
        endif
        if rendering >= 2
            selectObject: resultSound[c + 1]
            .resultName$ = selected$("Sound")
            if rendering = 4
                Rename: .resultName$ + "_Process"
            elsif rendering = 3
                Rename: .resultName$ + "_Voices"
            elsif preserve_tails
                Rename: .resultName$ + "_SustainKeep"
            else
                Rename: .resultName$ + "_Sustain"
            endif
        endif
        # Sampled peak in the imported Sound (no sinc overshoot) for Play safety.
        selectObject: resultSound[c + 1]
        .outputPeak = Get absolute extremum: 0, 0, "None"
        appendInfoLine: "Output ", c, " (Seed ", seed, ") peak: ", fixed$(.outputPeak, 4)
        if .outputPeak > 1.0
            appendInfoLine: "WARNING: Output exceeds |1.0|; Praat Play or the audio device may clip. Use RMS/Peak normalization for audition."
        endif
        nResults += 1
    endif
endfor

# ---- OPTIONAL PRAAT PICTURE FIGURE ----
if draw_visualization
    appendInfoLine: "Drawing agent activity and event maps..."
    @drawDceFigure
endif

# Restore the generated Sounds as the selection, not the temporary Tables.
firstResult = 1
for c from 0 to 2
    if architecture = 1 or architecture = c + 2
        if firstResult
            selectObject: resultSound[c + 1]
            firstResult = 0
        else
            plusObject: resultSound[c + 1]
        endif
    endif
endfor

appendInfoLine: "Created ", nResults, " stereo Sound object(s)."
if keep_intermediate_files
    appendInfoLine: "Analysis corpus, state/event TSV, WAV and log retained: ", runFolder$
else
    appendInfoLine: "Scratch WAV/TSV files are removed on success."
endif
if architecture = 1 or architecture = 4
    appendInfoLine: "Fast event feedback affects Decentralized only, with one-tick latency."
    appendInfoLine: "A/B check: Off disables fast feedback only. For historical Legacy comparison also select Feedback_reference = Legacy."
    appendInfoLine: "Feedback_reference = Legacy reproduces the previous musical behavior; Independent baseline is the calibrated experiment."
endif
if architecture = 1 or architecture = 3
    appendInfoLine: "Central_reference = Mean-centred G removes the mean central drive; it does NOT match event density or drive variance."
endif
appendInfoLine: "Play=1 plays the selected condition (Decentralized when all three are generated); the output Sounds remain selected."
appendInfoLine: "Note: Regulator and Replay are planned for DCE v0.2, not part of v0.1.7."
appendInfoLine: "Done."

@cleanUpArtifacts

# Play=1: for a single condition, play that result; when comparing all three,
# audition Decentralized and leave all generated Sounds selected afterward.
if play
    if architecture = 1
        playSound = resultSound[3]
    else
        playSound = resultSound[architecture - 1]
    endif
    selectObject: playSound
    Play
    firstResult = 1
    for c from 0 to 2
        if architecture = 1 or architecture = c + 2
            if firstResult
                selectObject: resultSound[c + 1]
                firstResult = 0
            else
                plusObject: resultSound[c + 1]
            endif
        endif
    endfor
endif
