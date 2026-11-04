# ============================================================
# Praat AudioTools - Generative_Exploration_Map.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Vector Chain - a listening-guided exploration instrument for the
#   parameter space of Markov Soundscape Weaver (v0.8).
#
#   Selected Sound -> a small diverse initial set of previews -> map ->
#   mark what interests you -> Around / Between / Other seeds -> new
#   previews are added to the SAME map -> ... -> render one point on the
#   whole Sound.
#
#   The Weaver renders every preview and the final result, unchanged,
#   through runScript; Python (generative_exploration_map.py) plans and
#   records the exploration, analyses the lossless previews and runs the
#   GUI. This script BLOCKS while the map is open (as CorpusMap.praat);
#   each exploration action closes the map, Praat renders only the new
#   points, and the map reopens with your marks and view restored.
#
#   The store is cumulative and content-addressed: a variation is its
#   effective (validated) parameter text plus seed, inside a store keyed by
#   the source samples, the Weaver file and the preview settings. A
#   configuration that has been rendered once is never rendered again;
#   reopening the same Sound later continues the same map. Every finished
#   preview is recorded on its own, so a stopped run resumes with only the
#   missing ones. Discard_cached_results starts that map from scratch.
#
#   Preview source: First segment (default) analyses Preview_duration_s
#   from Segment_start_s - fast, but the final render learns its model
#   from the whole Sound, so a preview is representative, not the opening
#   of the final render. Whole sound analyses the full Sound exactly as
#   the final render does (slower on long Sounds).
#
# Requirements:
#   Praat 6.4.02 or later (built-in MP3 writing).
#   pip install numpy librosa soundfile sounddevice scikit-learn pyqtgraph PySide6
#
# Store (v1.1; v1.0.1 sessions one level up are touched only by Clear All with
# the legacy box ticked):
#   Windows  %LOCALAPPDATA%\PraatAudioTools\GenerativeExplorationMap\v1.1\
#   macOS    ~/Library/Caches/PraatAudioTools/GenerativeExplorationMap/v1.1/
#   Linux    ~/.cache/PraatAudioTools/GenerativeExplorationMap/v1.1/
#
# Changelog v1.1.1 (2026):
#   - Manage Cache (button in the map): per-map usage, Open Folder, Clear
#     Current Exploration, Clear All Cache (legacy v1.0/v1.0.1 sessions only
#     when explicitly ticked). After a deletion the map closes, nothing is
#     rendered, and the original Sound stays selected. No change to the
#     Weaver, Progressive Exploration, synthesis or the v1.1 store format.
#
# Changelog v1.1 (2026):
#   - Progressive Exploration: Initial_points (default 24, cost-screened)
#     instead of 100 up front; Around / Between / Other seeds rounds add
#     to the same map.
#   - Rendered previews are never re-rendered; interrupted batches resume.
#   - Ownership-aware cleanup with per-run heartbeat locks (gem11_ prefix).
#   - Map layout aligned between rounds; GUI state persists.
#   - Rebuild_cache renamed Discard_cached_results; Number_of_previews
#     replaced by Initial_points. v1.0.1 remains available unchanged as
#     Generative_Exploration_Map_v1.0.1.praat.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
srcSound = selected("Sound")
srcName$ = selected$("Sound")

form Generative Exploration Map v1.1.1
    optionmenu Preview_source: 1
        option First segment (fast)
        option Whole sound (same model as final)
    real Segment_start_s 0
    positive Preview_duration_s 5
    natural Initial_points 24
    natural Base_seed 1
    real Final_duration_s 0
    boolean Discard_cached_results 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform
# Final_duration_s: 0 = the duration of the selected Sound.
# Initial_points: only used when this Sound has no map yet.

if praatVersion >= 7000
    trustGranted = askForTrust ()
    if trustGranted = 0
        exitScript: "Generative Exploration Map writes temporary files and runs Python; " +
        ... "it needs full trust to run."
    endif
endif
if praatVersion < 6402
    exitScript: "Generative Exploration Map needs Praat 6.4.02 or later (MP3 writing); this is Praat " +
    ... praatVersion$ + "."
endif

# ============================================================
# Validation
# ============================================================
selectObject: srcSound
srcDur = Get total duration
srcSR = Get sampling frequency
srcCh = Get number of channels
srcN = Get number of samples
if srcDur < 0.5
    exitScript: "The Sound is too short to explore (at least 0.5 s needed)."
endif
if initial_points < 6 or initial_points > 300
    exitScript: "Initial_points must be between 6 and 300."
endif
if preview_duration_s > 120
    exitScript: "Preview_duration_s above 120 s is not a preview."
endif
if final_duration_s < 0
    exitScript: "Final_duration_s cannot be negative (0 = source duration)."
endif
if preview_source = 1
    previewMode$ = "segment"
    if segment_start_s < 0 or segment_start_s > srcDur - 0.5
        exitScript: "Segment_start_s must lie between 0 and " + fixed$(srcDur - 0.5, 2) + " s."
    endif
    segStart = segment_start_s
    segDur = min(preview_duration_s, srcDur - segStart)
else
    previewMode$ = "whole"
    segStart = 0
    segDur = srcDur
endif
if final_duration_s > 0
    finalDur = final_duration_s
else
    finalDur = srcDur
endif

# ============================================================
# Python discovery (as CorpusMap.praat)
# ============================================================
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

pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/generative_exploration_map.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/generative_exploration_map.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/../py/generative_exploration_map.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find generative_exploration_map.py." + newline$ + "Expected at: " + pluginDir$ + "py/"
endif

# ============================================================
# Per-run files. The token makes every name unique to this run; the
# run lock is this run's heartbeat (touched on every preview), which is
# how a later run tells an active session from a crashed one.
# ============================================================
tmp$ = temporaryDirectory$
runTok$ = replace_regex$(date$(), "[^0-9]", "", 0) + "_" + string$(randomInteger(100000, 999999))
pre$ = tmp$ + "/gem11_" + runTok$
runLock$ = pre$ + ".lock"
manifest$ = pre$ + "_manifest.json"
sourceWav$ = pre$ + "_source.wav"
planTsv$ = pre$ + "_plan.tsv"
planInfo$ = pre$ + "_plan_info.tsv"
selectionTsv$ = pre$ + "_selection.tsv"
exploreStatus$ = pre$ + "_explore_status.tsv"
probeMarker$ = pre$ + "_probe.ok"
probeScript$ = pre$ + "_probe.py"
probeError$ = pre$ + "_probe_error.txt"

procedure delIf: .f$
    if fileReadable(.f$)
        deleteFile: .f$
    endif
endproc

procedure cleanUp
    @delIf: manifest$
    @delIf: sourceWav$
    @delIf: planTsv$
    @delIf: planInfo$
    @delIf: selectionTsv$
    @delIf: exploreStatus$
    @delIf: probeMarker$
    @delIf: probeScript$
    @delIf: probeError$
    @delIf: pre$ + "_owner.txt"
    # the heartbeat goes last
    @delIf: runLock$
endproc

procedure heartbeat
    writeFile: runLock$, "praat " + date$() + newline$
endproc

procedure jsonSafe: .s$
    .s$ = replace$(.s$, "\", "/", 0)
    .s$ = replace$(.s$, """", "_", 0)
    jsonSafe.out$ = .s$
endproc

procedure kvRead: .path$, .key$
    kvRead.out$ = ""
    if fileReadable(.path$)
        .t = Read Table from tab-separated file: .path$
        .row = Search column: "key", .key$
        if .row > 0
            kvRead.out$ = Get value: .row, "value"
        endif
        removeObject: .t
    endif
endproc

@heartbeat

clearinfo
writeInfoLine: "=== Generative Exploration Map v1.1.1 ==="
appendInfoLine: "Source: ", srcName$, " (", fixed$(srcDur, 3), " s, ", srcCh, " ch, ", srcSR, " Hz)"
appendInfoLine: "Detecting Python and dependencies..."

writeFile: probeScript$,
    ... "import sys" + newline$ +
    ... "marker_path = sys.argv[1]" + newline$ +
    ... "error_path  = sys.argv[2]" + newline$ +
    ... "pkgs = ['numpy','librosa','soundfile','sounddevice','sklearn','pyqtgraph','PySide6']" + newline$ +
    ... "missing = []" + newline$ +
    ... "for pkg in pkgs:" + newline$ +
    ... "    try:" + newline$ +
    ... "        __import__(pkg)" + newline$ +
    ... "    except ImportError:" + newline$ +
    ... "        missing.append(pkg)" + newline$ +
    ... "    except Exception as e:" + newline$ +
    ... "        missing.append(pkg + ' (error: ' + str(e) + ')')" + newline$ +
    ... "if not missing:" + newline$ +
    ... "    open(marker_path, 'w').write('ok')" + newline$ +
    ... "else:" + newline$ +
    ... "    open(error_path, 'w').write('Missing: ' + ', '.join(missing))" + newline$
probeArgs$ = " """ + probeScript$ + """ """ + probeMarker$ + """ """ + probeError$ + """"
runSystem_nocheck: pythonCmd$ + probeArgs$
if not fileReadable(probeMarker$) and windows
    runSystem_nocheck: "py" + probeArgs$
    if fileReadable(probeMarker$)
        pythonCmd$ = "py"
    endif
endif
if not fileReadable(probeMarker$)
    diagMsg$ = "pip install numpy librosa soundfile sounddevice scikit-learn pyqtgraph PySide6"
    if fileReadable(probeError$)
        diagMsg$ = readFile$(probeError$) + newline$ + newline$ + "Run:  " + diagMsg$
    elsif windows
        diagMsg$ = "Python not found on PATH (tried 'python' and 'py')." + newline$ +
            ... "Install Python from https://python.org and tick 'Add to PATH'." + newline$ + newline$ +
            ... "Then run:  " + diagMsg$
    endif
    @cleanUp
    exitScript: diagMsg$
endif
@delIf: probeMarker$
@delIf: probeScript$
@delIf: probeError$

# ============================================================
# Manifest (rewritten before every Python call)
# ============================================================
@jsonSafe: srcName$
nameJ$ = jsonSafe.out$
@jsonSafe: tmp$
tmpJ$ = jsonSafe.out$
@jsonSafe: pluginDir$
pluginJ$ = jsonSafe.out$
@jsonSafe: defaultDirectory$
scriptDirJ$ = jsonSafe.out$
@jsonSafe: sourceWav$
sourceWavJ$ = jsonSafe.out$
@jsonSafe: planTsv$
planTsvJ$ = jsonSafe.out$
@jsonSafe: planInfo$
planInfoJ$ = jsonSafe.out$
@jsonSafe: selectionTsv$
selectionJ$ = jsonSafe.out$
@jsonSafe: exploreStatus$
exploreStatusJ$ = jsonSafe.out$
if discard_cached_results
    discardJ$ = "true"
else
    discardJ$ = "false"
endif

manifestCore$ = "{" + newline$ +
    ... "  ""token"": """ + runTok$ + """," + newline$ +
    ... "  ""source_name"": """ + nameJ$ + """," + newline$ +
    ... "  ""source_duration"": " + string$(srcDur) + "," + newline$ +
    ... "  ""source_sr"": " + string$(srcSR) + "," + newline$ +
    ... "  ""source_channels"": " + string$(srcCh) + "," + newline$ +
    ... "  ""source_samples"": " + string$(srcN) + "," + newline$ +
    ... "  ""source_wav"": """ + sourceWavJ$ + """," + newline$ +
    ... "  ""preview_source"": """ + previewMode$ + """," + newline$ +
    ... "  ""segment_start"": " + string$(segStart) + "," + newline$ +
    ... "  ""preview_duration"": " + string$(preview_duration_s) + "," + newline$ +
    ... "  ""n_initial"": " + string$(initial_points) + "," + newline$ +
    ... "  ""base_seed"": " + string$(base_seed) + "," + newline$ +
    ... "  ""discard"": " + discardJ$ + "," + newline$ +
    ... "  ""temp_dir"": """ + tmpJ$ + """," + newline$ +
    ... "  ""plugin_dir"": """ + pluginJ$ + """," + newline$ +
    ... "  ""script_dir"": """ + scriptDirJ$ + """," + newline$ +
    ... "  ""plan_tsv"": """ + planTsvJ$ + """," + newline$ +
    ... "  ""plan_info"": """ + planInfoJ$ + """," + newline$ +
    ... "  ""selection_tsv"": """ + selectionJ$ + """," + newline$ +
    ... "  ""explore_status"": """ + exploreStatusJ$ + """"

procedure writeManifest
    if storeDir$ = ""
        writeFile: manifest$, manifestCore$ + newline$ + "}" + newline$
    else
        @jsonSafe: storeDir$
        .sJ$ = jsonSafe.out$
        @jsonSafe: enginePath$
        .eJ$ = jsonSafe.out$
        writeFile: manifest$, manifestCore$ + "," + newline$ +
            ... "  ""store_dir"": """ + .sJ$ + """," + newline$ +
            ... "  ""engine_path"": """ + .eJ$ + """" + newline$ + "}" + newline$
    endif
endproc

# ============================================================
# Fingerprint source once (Python hashes and deletes it)
# ============================================================
appendInfoLine: "Fingerprinting the source and opening its map..."
selectObject: srcSound
Save as 32-bit WAV file: sourceWav$

storeDir$ = ""
enginePath$ = ""
previewSrc = 0
roundsDone = 0
totalRendered = 0
exStatus$ = ""

repeat
    # ---------------- plan: what still has to be rendered ----------------
    @heartbeat
    @writeManifest
    @delIf: planInfo$
    runSystem_nocheck: pythonCmd$ + " """ + pythonScript$ + """ plan """ + manifest$ + """"
    @kvRead: planInfo$, "status"
    planStatus$ = kvRead.out$
    if planStatus$ = "error" or planStatus$ = "busy"
        @kvRead: planInfo$, "message"
        errMsg$ = kvRead.out$
        if previewSrc <> 0
            removeObject: previewSrc
        endif
        @cleanUp
        exitScript: if planStatus$ = "busy" then "" else "Planning failed:" + newline$ fi + errMsg$
    elsif planStatus$ <> "render" and planStatus$ <> "ready"
        if previewSrc <> 0
            removeObject: previewSrc
        endif
        @cleanUp
        exitScript: "The Python planning step did not report back. " +
        ... "Run the .py once from a terminal to see its error."
    endif
    @kvRead: planInfo$, "engine"
    enginePath$ = kvRead.out$
    @kvRead: planInfo$, "store_dir"
    storeDir$ = kvRead.out$
    @kvRead: planInfo$, "complete"
    nComplete = number(kvRead.out$)

    # ---------------- render the missing previews (Weaver) ----------------
    if planStatus$ = "render"
        if previewSrc = 0
            if previewMode$ = "segment"
                selectObject: srcSound
                previewSrc = Extract part: segStart, segStart + segDur, "rectangular", 1, "no"
                Rename: srcName$ + "_gemseg"
            else
                previewSrc = srcSound
            endif
        endif
        planT = Read Table from tab-separated file: planTsv$
        nPlan = Get number of rows
        durP$ = string$(preview_duration_s)
        tSum = 0
        nFailed = 0
        for i to nPlan
            selectObject: planT
            id$ = Get value: i, "id"
            label$ = Get value: i, "label"
            seed$ = Get value: i, "seed"
            g$ = Get value: i, "grain_size_ms"
            aov$ = Get value: i, "analysis_overlap"
            k$ = Get value: i, "number_of_states"
            ord$ = Get value: i, "markov_order"
            rnd$ = Get value: i, "randomness"
            sov$ = Get value: i, "synthesis_overlap"
            vs$ = Get value: i, "varispeed_scatter_semitones"
            pj$ = Get value: i, "position_jitter"
            dv$ = Get value: i, "density_variation"
            sd$ = Get value: i, "stereo_decorrelation"
            wav$ = Get value: i, "wav"
            mp3$ = Get value: i, "mp3"
            done$ = Get value: i, "done"

            selectObject: previewSrc
            stopwatch
            nocheck runScript: enginePath$, "Manual", g$, aov$, k$, ord$, rnd$, durP$, sov$, vs$, pj$,
                ... dv$, sd$, seed$, "no", "no"
            ok = 0
            if numberOfSelected("Sound") = 1
                res = selected("Sound")
                if res <> previewSrc and res <> srcSound
                    ok = 1
                endif
            endif
            if ok
                selectObject: res
                Save as 32-bit WAV file: wav$
                selectObject: res
                nocheck Save as highest quality MP3 file: mp3$
                removeObject: res
                if not fileReadable(mp3$)
                    ok = 0
                endif
            endif
            tOne = stopwatch
            tSum = tSum + tOne
            # the .done marker is written LAST: it is what makes this
            # preview count as finished if the run stops right after
            if ok
                writeFile: done$, "ok" + tab$ + fixed$(tOne, 3) + newline$
            else
                nFailed = nFailed + 1
                writeFile: done$, "failed" + tab$ + fixed$(tOne, 3) + newline$
            endif
            @heartbeat
            totalRendered = totalRendered + 1

            clearinfo
            writeInfoLine: "=== Generative Exploration Map v1.1.1 ==="
            appendInfoLine: "Source: ", srcName$, " | ", nComplete, " points already in this map"
            appendInfoLine: "Rendering new previews with the Weaver: ", i, " / ", nPlan, "  (", label$, ", ",
                ... fixed$(tOne, 2), " s; ", fixed$(tSum, 1), " s so far",
                ... if i < nPlan then ", about " + fixed$(tSum / i * (nPlan - i), 0) + " s left" else "" fi, ")"
            if nFailed > 0
                appendInfoLine: "  failed so far: ", nFailed, " (recorded, not retried)"
            endif
        endfor
        removeObject: planT
    endif

    # ---------------- map (Python GUI, BLOCKING) ----------------
    @heartbeat
    @writeManifest
    @delIf: exploreStatus$
    @delIf: selectionTsv$
    appendInfoLine: ""
    appendInfoLine: "=== MAP OPEN ==="
    appendInfoLine: "Click to audition | Mark (M) | Around / Between / Other seeds add points | RENDER CURRENT | Manage Cache"
    runSystem_nocheck: pythonCmd$ + " """ + pythonScript$ + """ explore """ + manifest$ + """"
    @kvRead: exploreStatus$, "status"
    exStatus$ = kvRead.out$
    roundsDone = roundsDone + 1
    if exStatus$ = "error"
        @kvRead: exploreStatus$, "message"
        errMsg$ = kvRead.out$
        if previewSrc <> 0 and previewSrc <> srcSound
            removeObject: previewSrc
        endif
        @cleanUp
        exitScript: "Exploration failed:" + newline$ + errMsg$
    endif
    if exStatus$ = "refine"
        clearinfo
        writeInfoLine: "=== Generative Exploration Map v1.1.1 ==="
        appendInfoLine: "New points requested - rendering them..."
    endif
until exStatus$ <> "refine"

if previewSrc <> 0 and previewSrc <> srcSound
    removeObject: previewSrc
endif

# ============================================================
# Final render of the chosen point on the whole Sound
# ============================================================
if exStatus$ = "selected" and fileReadable(selectionTsv$)
    selT = Read Table from tab-separated file: selectionTsv$
    id$ = Get value: 1, "id"
    label$ = Get value: 1, "label"
    seed$ = Get value: 1, "seed"
    g$ = Get value: 1, "grain_size_ms"
    aov$ = Get value: 1, "analysis_overlap"
    k$ = Get value: 1, "number_of_states"
    ord$ = Get value: 1, "markov_order"
    rnd$ = Get value: 1, "randomness"
    sov$ = Get value: 1, "synthesis_overlap"
    vs$ = Get value: 1, "varispeed_scatter_semitones"
    pj$ = Get value: 1, "position_jitter"
    dv$ = Get value: 1, "density_variation"
    sd$ = Get value: 1, "stereo_decorrelation"
    removeObject: selT
    @cleanUp

    drawArg$ = if draw_visualization then "yes" else "no" fi
    playArg$ = if play_result then "yes" else "no" fi
    selectObject: srcSound
    runScript: enginePath$, "Manual", g$, aov$, k$, ord$, rnd$, string$(finalDur), sov$, vs$, pj$,
        ... dv$, sd$, seed$, drawArg$, playArg$
    finalSound = selected("Sound")
    Rename: srcName$ + "_GEM_" + label$
    finalName$ = selected$("Sound")

    appendInfoLine: ""
    appendInfoLine: "=== Generative Exploration Map v1.1.1: RENDERED ==="
    appendInfoLine: "Variation: ", label$, "  (id ", id$, ")  seed ", seed$
    appendInfoLine: "  Grain_size_ms ", g$, " | Analysis_overlap ", aov$, " | Number_of_states ", k$, " | ", ord$
    appendInfoLine: "  Randomness ", rnd$, " | Synthesis_overlap ", sov$, " | Varispeed ", vs$, " st"
    appendInfoLine: "  Position_jitter ", pj$, " | Density_variation ", dv$, " | Stereo_decorrelation ", sd$,
        ... if number(sd$) < 0 then " (mono)" else "" fi
    appendInfoLine: "  Output duration ", fixed$(finalDur, 3), " s, from the whole source"
    appendInfoLine: "  This session: ", totalRendered, " preview(s) rendered, ", roundsDone, " map round(s)"
    appendInfoLine: "Output: ", finalName$
    selectObject: finalSound
elsif exStatus$ = "deleted"
    @kvRead: exploreStatus$, "message"
    delMsg$ = kvRead.out$
    @kvRead: exploreStatus$, "scope"
    delScope$ = kvRead.out$
    @cleanUp
    appendInfoLine: ""
    appendInfoLine: "=== CACHE: ", if delScope$ = "all" then "CLEAR ALL" else "CLEAR CURRENT EXPLORATION" fi,
        ... " - nothing rendered ==="
    appendInfoLine: delMsg$
    appendInfoLine: "The original Sound is unchanged."
    selectObject: srcSound
else
    @cleanUp
    appendInfoLine: ""
    appendInfoLine: "=== DONE - nothing rendered ==="
    appendInfoLine: "This session: ", totalRendered, " preview(s) rendered, ", roundsDone, " map round(s)."
    appendInfoLine: "The map is kept and continues next time: ", storeDir$
    selectObject: srcSound
endif
