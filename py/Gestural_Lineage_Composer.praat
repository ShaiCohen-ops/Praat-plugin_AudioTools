# ============================================================
# Praat AudioTools - Gestural_Lineage_Composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1.2 (2026)
#   v2.1.2 (sixth review): phrase durations are measured over the sounding
#   range only - leading or trailing silence no longer forces a cut.
#   v2.1.1 (fifth review): pause threshold never below the silence floor;
#   equal pauses are not mistaken for articulation; identical phrases
#   (distance 0) link; a one-phrase result is not reported as a path;
#   STUMPY required only for strict chains; Surrogates = 0 reported as
#   not tested; a fallback to gesture windows is marked in the name.
#   v2.1: phrase-aware analysis. Analysis unit = Gesture windows (v2.0,
#   unchanged), Phrases (automatic) or Phrases (TextGrid). Automatic phrases
#   adapt Sonic Syntax's pause evidence and add acoustic-change boundaries
#   (texture novelty incl. spectral flux) for continuous material; phrases
#   are compared on contours resampled to a shared grid, with duration and
#   pauses kept; the same evolution-path search composes them; the order is
#   tested against permutations of the same phrases.
#   v2.0 (fourth review - redesign of the selection and composition stage):
#   strict time series chains rarely form in real recordings, and one
#   feature does not carry a gesture's identity. The default engine now
#   builds the best EVOLUTION PATH through the relations found in the
#   recording: windows matched on all three features (or one), linked to
#   their mutual k nearest neighbours in time order (k = 1 is a chain
#   link), and the path is chosen exactly for continuity and steady change
#   toward a direction (Evolve toward). A path is always built; its order
#   is tested against time-shuffled versions. The v1 strict chains remain
#   (Advanced settings: Engine).
#   v1.0.2 (third review): structural evolution (contour) and acoustic
#   evolution (sound) are named separately; a sound change is named by its
#   strength and labelled confirmed or tentative by its chance test; Gradual
#   Evolution with Strict off may choose a lineage for its sound change even
#   when the lineage itself is not beyond chance (reported as Exploratory).
#   v1.0.1 (after external review): the chance test can now say "insufficient
#   data" when a Sound has too few block orders to reach p <= 0.05 (it used
#   to report "weak"); results are significant / exploratory / insufficient;
#   engine errors stop the script instead of returning the source unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Gestural Lineage Composer - composing with the evolutionary relations
#   inside one recording.
#
#   v2.0 default (Evolution path): see the Version note above and the HTML
#   guide. Strict chains (Advanced settings: Engine), as in v1:
#   A feature trajectory of the selected Sound (spectral centroid,
#   loudness or spectral flatness) is cut into every overlapping window of
#   a fixed duration. The Python engine (STUMPY) finds each window's
#   nearest neighbour among EARLIER windows and among LATER ones. A time
#   series chain is a run of windows in which every consecutive pair is
#   mutually linked - B is A's closest later window AND A is B's closest
#   earlier window. Such a chain is a lineage: a gesture that returns, each
#   time most like the time before, so that its first and last appearances
#   can differ a great deal while every step is small.
#
#   Every lineage is tested against the same material with its time order
#   shuffled; only lineages beyond chance are composed with (unless Allow
#   weak lineages is ticked). If there is none, the script says so and
#   makes no Sound.
#
#   Modes (all cut the ORIGINAL audio, all channels, no processing):
#     Lineage reconstruction  the lineage's gestures in chain order
#     Evolutionary montage    several lineages interleaved generation by
#                             generation
#     Branching lineages      lineages whose first gestures resemble one
#                             another, one after the other
#     Guided exploration      the lineage through a chosen moment
#                             (Anchor_time_s, or the first labelled
#                             interval of a TextGrid selected with the Sound)
#
#   Difference from SSM Composer: SSM Composer compares silence-separated
#   EVENTS by their mean features (a symmetric similarity) and walks
#   stochastically through them. This tool compares the SHAPES of feature
#   trajectories in fixed windows on a continuous time grid, uses the
#   DIRECTION of time (left and right neighbours), and its result is a
#   deterministic, chronologically ordered lineage, with a chance test.
#
# Dependencies (Python):
#   pip install numpy scipy soundfile stumpy
#   (the first run compiles STUMPY's kernels, about 10-20 s; later runs
#   reuse a cache in the user's local cache folder)
#
# Citation:
#   Cohen, S. (2026). Gestural Lineage Composer: Composing with Time
#   Series Chains in Praat. Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#   Chains: Zhu, Imamura, Nikovski, Keogh (2017). Matrix Profile VII:
#   Time Series Chains. IEEE ICDM.
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object (optionally together with one TextGrid)."
endif
origSound = selected("Sound")
origName$ = selected$("Sound")
anchorTg = 0
if numberOfSelected("TextGrid") = 1
    anchorTg = selected("TextGrid")
endif
selectObject: origSound
nChannels = Get number of channels
dur = Get total duration
sr = Get sampling frequency
srcStart = Get start time
srcEnd = Get end time

if praatVersion >= 7000
    trustGranted = askForTrust ()
    if trustGranted = 0
        exitScript: "Gestural Lineage Composer writes temporary files and runs Python; it needs full trust."
    endif
endif

# ---- PATHS ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)
pythonScript$ = pluginDir$ + "py/gestural_lineage_engine.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/gestural_lineage_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: gestural_lineage_engine.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif
tempDir$ = replace_regex$(temporaryDirectory$ + "/", "\\", "/", 0)
uid$ = string$(randomInteger(100000, 999999))
pre$ = tempDir$ + "temp_glc_" + uid$
srcWav$ = pre$ + "_source.wav"
planTsv$ = pre$ + "_plan.tsv"
trajTsv$ = pre$ + "_traj.tsv"
mpTsv$ = pre$ + "_mp.tsv"
linTsv$ = pre$ + "_lineages.tsv"
memTsv$ = pre$ + "_members.tsv"
phrTsv$ = pre$ + "_phrases.tsv"
plinkTsv$ = pre$ + "_phrase_links.tsv"
tgInTsv$ = pre$ + "_tg_in.tsv"
statsTxt$ = pre$ + "_stats.txt"
runLog$ = pre$ + "_runlog.txt"
probePy$ = pre$ + "_probe.py"
probeMarker$ = pre$ + "_probe.ok"
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)

procedure cleanUpTempFiles
    for .k to 13
        if .k = 11
            .f$ = phrTsv$
        elsif .k = 12
            .f$ = plinkTsv$
        elsif .k = 13
            .f$ = tgInTsv$
        elsif .k = 1
            .f$ = srcWav$
        elsif .k = 2
            .f$ = planTsv$
        elsif .k = 3
            .f$ = trajTsv$
        elsif .k = 4
            .f$ = mpTsv$
        elsif .k = 5
            .f$ = linTsv$
        elsif .k = 6
            .f$ = memTsv$
        elsif .k = 7
            .f$ = statsTxt$
        elsif .k = 8
            .f$ = runLog$
        elsif .k = 9
            .f$ = probePy$
        else
            .f$ = probeMarker$
        endif
        if fileReadable(.f$)
            deleteFile: .f$
        endif
    endfor
endproc

# ---- FORM ----
form Gestural Lineage Composer v2.1.2
    comment Preset (Custom uses the settings below)
    optionmenu Preset: 1
        option Custom
        option Hidden Recurrences
        option Gradual Evolution
        option Distant Relatives
        option Branching Memory
        option Sparse Lineage
    optionmenu Analysis_unit: 1
        option Gesture windows
        option Phrases (automatic)
        option Phrases (TextGrid)
    optionmenu Match_on: 1
        option All three features
        option Spectral centroid
        option Loudness
        option Spectral flatness
    optionmenu Evolve_toward: 1
        option Auto (strongest steady change)
        option Brighter
        option Darker
        option Louder
        option Softer
        option Noisier
        option More tonal
        option Continuity only
    comment Window (gesture windows only)
    positive Window_s 1.0
    optionmenu Mode: 1
        option Lineage reconstruction
        option Evolutionary montage
        option Branching lineages
        option Guided exploration
    comment Guided exploration: anchor time (or select a TextGrid with the Sound)
    real Anchor_time_s 0
    boolean Advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- DEFAULTS (Custom) ----
# featureIdx 0 = all three features (evolution-path engine only)
featureIdx = match_on - 1
evolveIdx = evolve_toward
engine = 1
unitIdx = analysis_unit
# 0 = automatic: 3 for gesture windows, 5 for phrases
links_per_unit = 0
link_tolerance = 2.0
min_phrase_s = 0
max_phrase_s = 0
phrase_boundaries = 1
phrase_detail = 50
textgrid_tier = 1
phrase_textgrid = 1
windowSec = window_s
modeIdx = mode
lineage_choice = 1
order = 1
similarity = 1
silence_between = 1
silence_scale = 0.25
lineages_used = 3
branch_root_ratio = 3.0
crossfade_ms = 10
max_output_s = 0
surrogates = 99
seed = 1
strict = 0

# ---- PRESETS: each one a different analytical or compositional choice ----
if preset = 2
    presetName$ = "Hidden Recurrences"
    featureIdx = 0
    evolveIdx = 8
    link_tolerance = 1.5
    windowSec = 0.5
    modeIdx = 1
    lineage_choice = 2
    crossfade_ms = 8
elsif preset = 3
    presetName$ = "Gradual Evolution"
    featureIdx = 0
    evolveIdx = 1
    windowSec = 1.0
    modeIdx = 1
    lineage_choice = 3
    crossfade_ms = 15
elsif preset = 4
    presetName$ = "Distant Relatives"
    # the widest-span lineage: a strict-chain choice (v1 engine)
    engine = 2
    featureIdx = 1
    windowSec = 1.0
    modeIdx = 1
    lineage_choice = 4
    crossfade_ms = 15
elsif preset = 5
    presetName$ = "Branching Memory"
    featureIdx = 0
    evolveIdx = 1
    windowSec = 1.0
    modeIdx = 3
    lineage_choice = 1
    lineages_used = 3
    crossfade_ms = 15
elsif preset = 6
    presetName$ = "Sparse Lineage"
    featureIdx = 0
    evolveIdx = 1
    windowSec = 1.0
    modeIdx = 1
    lineage_choice = 1
    silence_between = 2
    silence_scale = 0.25
    crossfade_ms = 20
else
    presetName$ = "Custom"
endif

# ---- ADVANCED (pre-filled with the preset's values, so presets stay inspectable) ----
if advanced_settings
    beginPause: "Gestural Lineage Composer: advanced settings"
        choice: "Engine", engine
            option: "Evolution path (v2: mutual k-nearest links, best path)"
            option: "Strict chains (v1: reciprocal nearest neighbours only)"
        integer: "Links per unit", string$(links_per_unit)
        positive: "Link tolerance", string$(link_tolerance)
        if unitIdx = 2
            comment: "Phrases (automatic): 0 = adaptive duration; Phrase detail 50 = neutral, higher = more phrases"
            real: "Min phrase s", string$(min_phrase_s)
            real: "Max phrase s", string$(max_phrase_s)
            choice: "Phrase boundaries", phrase_boundaries
                option: "Pauses + acoustic change"
                option: "Pauses only"
                option: "Acoustic change only"
            real: "Phrase detail", string$(phrase_detail)
        elsif unitIdx = 3
            comment: "Phrases (TextGrid): labelled intervals of this interval tier are the phrases"
            natural: "TextGrid tier", string$(textgrid_tier)
        endif
        if unitIdx > 1
            boolean: "Phrase TextGrid", phrase_textgrid
        endif
        comment: "Strict chains only: which lineage, and the branch tolerance"
        choice: "Lineage choice", lineage_choice
            option: "Strongest (most beyond chance)"
            option: "Tightest (closest links)"
            option: "Most drift (sound changes most)"
            option: "Widest span (furthest apart in time)"
        choice: "Order", order
            option: "Forward (ancestor to descendant)"
            option: "Backward (descendant to ancestor)"
        choice: "Similarity", similarity
            option: "Shape (transposition and size ignored)"
            option: "Absolute (register and range count)"
        choice: "Silence between", silence_between
            option: "None (gestures crossfaded)"
            option: "Proportional (original distance x scale)"
        positive: "Silence scale", string$(silence_scale)
        natural: "Lineages used", string$(lineages_used)
        positive: "Branch root ratio", string$(branch_root_ratio)
        real: "Crossfade ms", string$(crossfade_ms)
        real: "Max output s", string$(max_output_s)
        comment: "Order test (0 surrogates = no test; nothing then counts as beyond chance):"
        integer: "Surrogates", string$(surrogates)
        integer: "Seed", string$(seed)
        comment: "Strict = make a Sound only if the order is beyond chance (off: always a result)"
        boolean: "Strict", strict
    endPause: "Continue", 1
endif

if featureIdx = 0 and engine = 2
    # strict chains match on one feature
    featureIdx = 1
endif
if featureIdx = 0
    featStr$ = "centroid"
    featLabel$ = "Spectral centroid"
    matchStr$ = "all"
    matchLabel$ = "all three features"
elsif featureIdx = 1
    featStr$ = "centroid"
    featLabel$ = "Spectral centroid"
elsif featureIdx = 2
    featStr$ = "loudness"
    featLabel$ = "Loudness"
else
    featStr$ = "flatness"
    featLabel$ = "Spectral flatness"
endif
if featureIdx > 0
    matchStr$ = "feature"
    matchLabel$ = featLabel$
endif
if evolveIdx = 1
    dirStr$ = "auto"
elsif evolveIdx = 2
    dirStr$ = "brighter"
elsif evolveIdx = 3
    dirStr$ = "darker"
elsif evolveIdx = 4
    dirStr$ = "louder"
elsif evolveIdx = 5
    dirStr$ = "softer"
elsif evolveIdx = 6
    dirStr$ = "noisier"
elsif evolveIdx = 7
    dirStr$ = "more_tonal"
else
    dirStr$ = "continuity"
endif
if unitIdx = 1
    unitStr$ = "gesture"
    unitLabel$ = "gesture windows"
elsif unitIdx = 2
    unitStr$ = "phrase_auto"
    unitLabel$ = "phrases (automatic)"
else
    unitStr$ = "phrase_textgrid"
    unitLabel$ = "phrases (TextGrid)"
endif
engineNote$ = ""
if unitIdx > 1 and engine = 2
    # phrase analysis composes evolution paths; strict chains are a gesture-window method
    engine = 1
    engineNote$ = "phrase analysis uses the evolution-path engine (strict chains are gesture-level)"
endif
engineStr$ = if engine = 2 then "chain" else "path" fi
if links_per_unit < 0
    links_per_unit = 0
endif
if phrase_boundaries = 2
    boundStr$ = "silence"
elsif phrase_boundaries = 3
    boundStr$ = "change"
else
    boundStr$ = "both"
endif
if modeIdx = 1
    modeStr$ = "lineage"
    modeLabel$ = "Lineage reconstruction"
elsif modeIdx = 2
    modeStr$ = "montage"
    modeLabel$ = "Evolutionary montage"
elsif modeIdx = 3
    modeStr$ = "branching"
    modeLabel$ = "Branching lineages"
else
    modeStr$ = "guided"
    modeLabel$ = "Guided exploration"
endif
if lineage_choice = 1
    selStr$ = "strongest"
elsif lineage_choice = 2
    selStr$ = "tightest"
elsif lineage_choice = 3
    selStr$ = "drift"
else
    selStr$ = "span"
endif
orderStr$ = if order = 2 then "backward" else "forward" fi
simStr$ = if similarity = 2 then "absolute" else "shape" fi
gapStr$ = if silence_between = 2 then "proportional" else "none" fi
if crossfade_ms < 0
    crossfade_ms = 0
endif
if surrogates < 0
    surrogates = 0
endif

# Phrases (TextGrid): the selected TextGrid's intervals are the phrases
tgNote$ = ""
if unitStr$ = "phrase_textgrid"
    if anchorTg = 0
        exitScript: "Analysis unit 'Phrases (TextGrid)' needs a TextGrid selected together with the Sound."
    endif
    selectObject: anchorTg
    nTiers = Get number of tiers
    if textgrid_tier < 1 or textgrid_tier > nTiers
        exitScript: "The TextGrid has " + string$(nTiers) + " tier(s); tier " + string$(textgrid_tier) + " does not exist (Advanced settings: TextGrid tier)."
    endif
    isInt = Is interval tier: textgrid_tier
    if not isInt
        exitScript: "TextGrid tier " + string$(textgrid_tier) + " is a point tier; phrases need an interval tier."
    endif
    tgName$ = Get tier name: textgrid_tier
    nI = Get number of intervals: textgrid_tier
    tgNote$ = "tier " + string$(textgrid_tier) + " """ + tgName$ + """, " + string$(nI) + " intervals"
endif

# Guided anchor: a TextGrid selected with the Sound wins over the number
# (except when the TextGrid's intervals are the phrases)
anchorT = anchor_time_s
anchorSrc$ = "Anchor_time_s"
if modeStr$ = "guided" and anchorTg > 0 and unitStr$ <> "phrase_textgrid"
    selectObject: anchorTg
    nTiers = Get number of tiers
    found = 0
    for iTier to nTiers
        isInt = Is interval tier: iTier
        if isInt and found = 0
            nI = Get number of intervals: iTier
            for iI to nI
                if found = 0
                    lab$ = Get label of interval: iTier, iI
                    if lab$ <> ""
                        anchorT = Get start time of interval: iTier, iI
                        anchorSrc$ = "TextGrid tier " + string$(iTier) + " interval """ + lab$ + """"
                        found = 1
                    endif
                endif
            endfor
        endif
    endfor
    if found = 0
        anchorSrc$ = "Anchor_time_s (the TextGrid has no labelled interval)"
    endif
endif
if modeStr$ = "guided" and (anchorT < srcStart or anchorT > srcEnd)
    exitScript: "Anchor time " + fixed$(anchorT, 3) + " s is outside the Sound (" + fixed$(srcStart, 3) + " - " + fixed$(srcEnd, 3) + " s)."
endif

clearinfo
writeInfoLine: "=== Gestural Lineage Composer v2.1.2 ==="
appendInfoLine: "Input:    ", origName$, " (", fixed$(dur, 2), " s, ", sr, " Hz, ", nChannels, " ch)"
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Unit:     ", unitLabel$, if tgNote$ <> "" then " (" + tgNote$ + ")" else "" fi
if engineNote$ <> ""
    appendInfoLine: "          ", engineNote$
endif
if engineStr$ = "path"
    appendInfoLine: "Engine:   evolution path | links per unit ", if links_per_unit = 0 then "auto" else string$(links_per_unit) fi, " | link tolerance ", fixed$(link_tolerance, 2)
    appendInfoLine: "Match on: ", matchLabel$, if unitIdx = 1 then " | window " + fixed$(windowSec, 3) + " s" else "" fi, " | similarity ", simStr$
    appendInfoLine: "Mode:     ", modeLabel$, " | evolve toward ", replace$(dirStr$, "_", " ", 0), " | order ", orderStr$
else
    appendInfoLine: "Engine:   strict chains (v1)"
    appendInfoLine: "Feature:  ", featLabel$, " | window ", fixed$(windowSec, 3), " s | similarity ", simStr$
    appendInfoLine: "Mode:     ", modeLabel$, " | lineage choice ", selStr$, " | order ", orderStr$
endif
if modeStr$ = "guided"
    appendInfoLine: "Anchor:   ", fixed$(anchorT, 3), " s from ", anchorSrc$
endif
appendInfoLine: ""

# ===========================================================================
# Python with numpy, scipy, soundfile and stumpy
# ===========================================================================
appendInfoLine: "[1/4] Detecting Python..."
@cleanUpTempFiles
writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
# STUMPY is needed only by the strict-chain engine
appendFileLine: probePy$, "    import numpy, scipy, soundfile" + if engineStr$ = "chain" then ", stumpy" else "" fi
appendFileLine: probePy$, "    with open(r'" + replace_regex$(probeMarker$, "\\", "/", 0) + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"
if windows
    nCandidates = 4
    candidate1$ = "python"
    candidate2$ = "py"
    candidate3$ = "py -3"
    candidate4$ = "python3"
elsif macintosh
    nCandidates = 4
    candidate1$ = "/opt/homebrew/bin/python3"
    candidate2$ = "/usr/local/bin/python3"
    candidate3$ = "python3"
    candidate4$ = "python"
else
    nCandidates = 3
    candidate1$ = "python3"
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = ""
endif
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
    runSystem_nocheck: tryCmd$ + " """ + replace_regex$(probePy$, "\\", "/", 0) + """"
    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1
    endif
endfor
if fileReadable(probePy$)
    deleteFile: probePy$
endif
if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 with the required packages." + newline$ + "Please install: pip install numpy scipy soundfile" + if engineStr$ = "chain" then " stumpy" else "" fi + newline$ + "(stumpy is needed only for Strict chains)"
endif
appendInfoLine: "  Python: ", pythonCmd$

# ===========================================================================
# Analysis (Python)
# ===========================================================================
appendInfoLine: "[2/4] Analysing trajectories, relations, " + if engineStr$ = "path" then "evolution path" else "chains" fi + " and order test..."
# the TextGrid tier's intervals for the engine (written after the temp-file
# clean-up of the Python detection)
if unitStr$ = "phrase_textgrid"
    selectObject: anchorTg
    writeFileLine: tgInTsv$, "start" + tab$ + "end" + tab$ + "label"
    for iI to nI
        t0 = Get start time of interval: textgrid_tier, iI
        t1 = Get end time of interval: textgrid_tier, iI
        lab$ = Get label of interval: textgrid_tier, iI
        lab$ = replace$(replace$(lab$, tab$, " ", 0), newline$, " ", 0)
        appendFileLine: tgInTsv$, fixed$(t0, 9) + tab$ + fixed$(t1, 9) + tab$ + lab$
    endfor
endif
selectObject: origSound
Save as 32-bit WAV file: srcWav$
pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " --wav """ + replace_regex$(srcWav$, "\\", "/", 0) + """"
    ... + " --out_prefix """ + replace_regex$(pre$, "\\", "/", 0) + """"
    ... + " --xmin " + fixed$(srcStart, 9)
    ... + " --feature " + featStr$
    ... + " --window_s " + fixed$(windowSec, 6)
    ... + " --similarity " + simStr$
    ... + " --mode " + modeStr$
    ... + " --select " + selStr$
    ... + " --order " + orderStr$
    ... + " --gap_mode " + gapStr$
    ... + " --gap_scale " + fixed$(silence_scale, 6)
    ... + " --n_lineages " + string$(lineages_used)
    ... + " --branch_ratio " + fixed$(branch_root_ratio, 6)
    ... + " --anchor_time " + fixed$(anchorT, 9)
    ... + " --max_output " + fixed$(max_output_s, 6)
    ... + " --surrogates " + string$(surrogates)
    ... + " --seed " + string$(seed)
    ... + " --allow_weak " + string$(1 - strict)
    ... + " --engine " + engineStr$
    ... + " --match " + matchStr$
    ... + " --direction " + dirStr$
    ... + " --k_links " + string$(links_per_unit)
    ... + " --unit " + unitStr$
    ... + " --phrases_tsv """ + replace_regex$(tgInTsv$, "\\", "/", 0) + """"
    ... + " --min_phrase " + fixed$(min_phrase_s, 6)
    ... + " --max_phrase " + fixed$(max_phrase_s, 6)
    ... + " --boundaries " + boundStr$
    ... + " --phrase_detail " + fixed$(phrase_detail, 6)
    ... + " --tolerance " + fixed$(link_tolerance, 6)
stopwatch
runSystem_nocheck: pythonCall$ + " > """ + replace_regex$(runLog$, "\\", "/", 0) + """ 2>&1"
engineSec = stopwatch
if not fileReadable(statsTxt$)
    errTail$ = ""
    if fileReadable(runLog$)
        errTail$ = readFile$(runLog$)
        if length(errTail$) > 1500
            errTail$ = "..." + right$(errTail$, 1500)
        endif
    endif
    @cleanUpTempFiles
    if index(errTail$, "unrecognized arguments") > 0
        # an older engine does not know the v2.0 options
        exitScript: "Engine version mismatch: the engine at" + newline$ + pythonScript$ + newline$ + "is older than this script (v2.1.2) and does not accept its options." + newline$ + "Replace it with gestural_lineage_engine.py v2.1.2 (plugin_AudioTools/py is searched before this script's folder)."
    endif
    exitScript: "Python engine failed (no statistics written)." + newline$ + newline$ + "Engine output:" + newline$ + errTail$
endif
statsText$ = newline$ + readFile$(statsTxt$)

procedure stat: .key$
    .result$ = "?"
    .pos = index(statsText$, newline$ + .key$ + "=")
    if .pos > 0
        .start = .pos + length(.key$) + 2
        .rest$ = mid$(statsText$, .start, length(statsText$) - .start + 1)
        .nl = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

procedure sf: .key$, .nd
    @stat: .key$
    .x = number(stat.result$)
    if .x = undefined
        .r$ = stat.result$
    else
        .r$ = fixed$(.x, .nd)
    endif
endproc

procedure statNum: .key$
    @stat: .key$
    .result = number(stat.result$)
endproc

@stat: "status"
status$ = stat.result$
@stat: "reason"
reason$ = stat.result$
@statNum: "analysis_channel"
anaCh = statNum.result
if anaCh = undefined or anaCh < 1 or anaCh > nChannels
    anaCh = 1
endif
@statNum: "window_s"
winEff = statNum.result
@stat: "adapted"
adapted$ = stat.result$
# the engine may have adapted the feature (pauses / constant feature)
@stat: "feature_used"
if stat.result$ = "centroid"
    featStr$ = "centroid"
    featLabel$ = "Spectral centroid"
elsif stat.result$ = "loudness"
    featStr$ = "loudness"
    featLabel$ = "Loudness"
elsif stat.result$ = "flatness"
    featStr$ = "flatness"
    featLabel$ = "Spectral flatness"
endif
# analysis unit actually used (automatic phrases fall back to gesture
# windows when fewer than two phrases are found - always reported)
@stat: "unit_used"
unitUsed$ = stat.result$
isPhrase = (unitUsed$ = "phrase")
@stat: "phrase_fallback"
fallback$ = if stat.result$ = "?" then "" else stat.result$ fi
@statNum: "n_phrases"
nPhrases = statNum.result
@stat: "segmentation"
segMethod$ = stat.result$
@statNum: "k_links"
kLinks = statNum.result
if isPhrase
    winEffLabel$ = "phrases, median " + fixed$(winEff, 2) + " s"
else
    winEffLabel$ = fixed$(winEff, 2) + " s windows"
endif
isWeak = (status$ = "exploratory" or status$ = "insufficient")
if status$ = "insufficient" and surrogates <= 0
    weakTag$ = "not_tested"
    weakLabel$ = "Not tested"
    weakTitle$ = "NOT TESTED - Surrogates = 0: the order test was not run"
elsif status$ = "insufficient"
    weakTag$ = "insufficient"
    weakLabel$ = "Insufficient data"
    weakTitle$ = if surrogates <= 0 then "NOT TESTED - Surrogates = 0: the order test was not run" else "INSUFFICIENT DATA - the " + if isPhrase then "order test cannot decide: too few phrases" else "chance test cannot decide for this Sound and window" fi fi
else
    weakTag$ = "exploratory"
    weakLabel$ = "Exploratory"
    weakTitle$ = "EXPLORATORY - not beyond chance: no stronger than " + if isPhrase then "random orders of the same phrases" else "the same material in random order" fi
endif
# v1.0.2: the engine is loaded from plugin_AudioTools/py FIRST; a stale copy
# there would silently run an older engine
@stat: "engine_version"
if stat.result$ <> "2.1.2"
    @cleanUpTempFiles
    exitScript: "Engine version mismatch: this script is v2.1.2 but the engine it ran reports '" + stat.result$ + "'." + newline$ + "Engine used: " + pythonScript$ + newline$ + "Replace that file with gestural_lineage_engine.py v2.1.2 (note: plugin_AudioTools/py is searched before this script's folder)."
endif
if status$ = "error"
    errTail$ = ""
    if fileReadable(runLog$)
        errTail$ = readFile$(runLog$)
        if length(errTail$) > 1500
            errTail$ = "..." + right$(errTail$, 1500)
        endif
    endif
    @cleanUpTempFiles
    exitScript: "Engine error: " + reason$ + newline$ + newline$ + errTail$
endif
appendInfoLine: "  Engine: ", fixed$(engineSec, 1), " s | status ", status$
if reason$ <> "" and reason$ <> "?"
    appendInfoLine: "  ", reason$
endif

# ===========================================================================
# Reconstruction from the original Sound (all channels, no processing)
# ===========================================================================
resultSound = 0
nRows = 0
xfadeEff = 0
actualOutputDur = 0
peakOut = 0
peakScaled = 0
nOverlapPairs = 0
if (status$ = "ok" or isWeak) and fileReadable(planTsv$)
    appendInfoLine: "[3/4] Reconstructing from the source..."
    planT = Read Table from tab-separated file: planTsv$
    nRows = Get number of rows
    rowStart# = zero# (nRows)
    rowEnd# = zero# (nRows)
    rowSil# = zero# (nRows)
    rowLin# = zero# (nRows)
    rowGen# = zero# (nRows)
    rowCorr# = zero# (nRows)
    pieceId# = zero# (2 * nRows)
    pieceRow# = zero# (2 * nRows)
    pieceOut0# = zero# (2 * nRows)
    pieceOut1# = zero# (2 * nRows)
    crossfade_s = crossfade_ms / 1000
    minChunk = 1e9
    for iRow to nRows
        selectObject: planT
        r1 = Get value: iRow, "src_start"
        r2 = Get value: iRow, "src_end"
        rowStart#[iRow] = max(srcStart, r1)
        rowEnd#[iRow] = min(srcEnd, r2)
        rowSil#[iRow] = Get value: iRow, "silence_before"
        rowLin#[iRow] = Get value: iRow, "lineage"
        rowGen#[iRow] = Get value: iRow, "generation"
        rowCorr#[iRow] = Get value: iRow, "link_corr"
        minChunk = min(minChunk, rowEnd#[iRow] - rowStart#[iRow])
    endfor
    removeObject: planT
    # overlapping source regions inside the output (possible across lineages)
    for iRow to nRows
        for jRow from iRow + 1 to nRows
            if rowStart#[jRow] < rowEnd#[iRow] and rowStart#[iRow] < rowEnd#[jRow]
                nOverlapPairs = nOverlapPairs + 1
            endif
        endfor
    endfor
    xfadeEff = min(crossfade_s, 0.45 * minChunk)
    nPieces = 0
    for iRow to nRows
        if rowSil#[iRow] > 0.0005
            nPieces = nPieces + 1
            # Concatenate with overlap eats one crossfade at each side
            pieceId#[nPieces] = Create Sound from formula: "glc_sil", nChannels, 0, rowSil#[iRow] + 2 * xfadeEff, sr, "0"
            pieceRow#[nPieces] = 0
        endif
        selectObject: origSound
        nPieces = nPieces + 1
        pieceId#[nPieces] = Extract part: rowStart#[iRow], rowEnd#[iRow], "rectangular", 1, "no"
        pieceRow#[nPieces] = iRow
    endfor
    # output position of every piece (Concatenate with overlap shortens each join by one crossfade)
    tOut = 0
    for iP to nPieces
        selectObject: pieceId#[iP]
        dP = Get total duration
        pieceOut0#[iP] = tOut
        pieceOut1#[iP] = tOut + dP
        tOut = tOut + dP - xfadeEff
    endfor
    selectObject: pieceId#[1]
    for iP from 2 to nPieces
        plusObject: pieceId#[iP]
    endfor
    if nPieces > 1 and xfadeEff > 0.0005
        Concatenate with overlap: xfadeEff
    else
        Concatenate
    endif
    resultSound = selected("Sound")
    for iP to nPieces
        removeObject: pieceId#[iP]
    endfor
    selectObject: resultSound
    Rename: origName$ + "_GLC_" + modeStr$ + if isPhrase then "_phrases" else "" fi + if fallback$ <> "" then "_windows_fallback" else "" fi + if isWeak then "_" + weakTag$ else "" fi
    resultName$ = selected$("Sound")
    actualOutputDur = Get total duration
    # the first and last cuts are not crossfaded: short raised-cosine fades
    edge = min(0.005, actualOutputDur / 4)
    if edge > 0
        Formula (part): 0, edge, 1, nChannels, "self * (0.5 - 0.5 * cos(pi * x / " + fixed$(edge, 9) + "))"
        Formula (part): actualOutputDur - edge, actualOutputDur, 1, nChannels, "self * (0.5 - 0.5 * cos(pi * (" + fixed$(actualOutputDur, 9) + " - x) / " + fixed$(edge, 9) + "))"
    endif
    peakOut = Get absolute extremum: 0, 0, "none"
    if peakOut > 0.999
        Scale peak: 0.99
        peakScaled = 1
    endif
    appendInfoLine: "  ", nRows, " gestures | output ", fixed$(actualOutputDur, 3), " s | crossfade ", fixed$(xfadeEff * 1000, 1), " ms | peak ", fixed$(peakOut, 4), if peakScaled then " (scaled to 0.99)" else "" fi
elsif status$ = "unchanged"
    # nothing in the recording can be related: the result is the source itself
    appendInfoLine: "[3/4] Nothing to relate: the result is the source, unchanged."
    selectObject: origSound
    resultSound = Copy: origName$ + "_GLC_unchanged"
    resultName$ = selected$("Sound")
    actualOutputDur = Get total duration
    peakOut = Get absolute extremum: 0, 0, "none"
elsif status$ = "no_relation"
    appendInfoLine: "[3/4] No two phrases are related within the link settings: no path, no Sound made."
elsif status$ = "no_lineage"
    appendInfoLine: "[3/4] Strict is on and the order is not beyond chance: no Sound made."
elsif status$ = "insufficient"
    appendInfoLine: "[3/4] Strict is on and the chance test cannot decide for this Sound and window: no Sound made."
else
    appendInfoLine: "[3/4] No Sound made (engine status: " + status$ + ")."
endif

# ===========================================================================
# Visualization: every number drawn comes from the engine's files or the
# reconstructed Sound
# ===========================================================================
# a tick step of 1, 2 or 5 x 10^k giving about .n ticks over .span
procedure niceStep: .span, .n
    .raw = .span / .n
    .p = 10 ^ floor(log10(.raw))
    .f = .raw / .p
    if .f < 1.5
        .result = .p
    elsif .f < 3.5
        .result = 2 * .p
    elsif .f < 7.5
        .result = 5 * .p
    else
        .result = 10 * .p
    endif
endproc

procedure linColour: .k
    .m = ((.k - 1) mod 5) + 1
    if .m = 1
        .c$ = "{0.20, 0.40, 0.80}"
        .light$ = "{0.80, 0.86, 0.97}"
    elsif .m = 2
        .c$ = "{0.85, 0.40, 0.15}"
        .light$ = "{0.98, 0.86, 0.78}"
    elsif .m = 3
        .c$ = "{0.20, 0.58, 0.35}"
        .light$ = "{0.80, 0.93, 0.84}"
    elsif .m = 4
        .c$ = "{0.58, 0.30, 0.65}"
        .light$ = "{0.90, 0.83, 0.93}"
    else
        .c$ = "{0.72, 0.58, 0.10}"
        .light$ = "{0.96, 0.92, 0.78}"
    endif
endproc

if draw_visualization
    appendInfoLine: "[4/4] Drawing..."
    # ---- read display data ----
    nTr = 0
    if fileReadable(trajTsv$)
        trT = Read Table from tab-separated file: trajTsv$
        nTr = Get number of rows
        trX# = zero# (nTr)
        trY# = zero# (nTr)
        for i to nTr
            trX#[i] = Get value: i, "time"
            trY#[i] = Get value: i, "value"
        endfor
        removeObject: trT
    endif
    nMp = 0
    if fileReadable(mpTsv$)
        mpT = Read Table from tab-separated file: mpTsv$
        nMp = Get number of rows
        mpX# = zero# (nMp)
        mpY# = zero# (nMp)
        for i to nMp
            mpX#[i] = Get value: i, "time"
            mpY#[i] = Get value: i, "P"
        endfor
        removeObject: mpT
    endif
    nMem = 0
    if fileReadable(memTsv$)
        memT = Read Table from tab-separated file: memTsv$
        nMem = Get number of rows
        memL# = zero# (nMem)
        memG# = zero# (nMem)
        memS# = zero# (nMem)
        memE# = zero# (nMem)
        memP# = zero# (nMem)
        for i to nMem
            memL#[i] = Get value: i, "lineage"
            memG#[i] = Get value: i, "generation"
            memS#[i] = Get value: i, "start"
            memE#[i] = Get value: i, "end"
            memP#[i] = Get value: i, "P"
        endfor
        removeObject: memT
    endif
    # phrases and their relation graph (phrase units only)
    nPhD = 0
    if isPhrase and fileReadable(phrTsv$)
        pT = Read Table from tab-separated file: phrTsv$
        nPhD = Get number of rows
        pdS# = zero# (nPhD)
        pdE# = zero# (nPhD)
        for i to nPhD
            pdS#[i] = Get value: i, "start"
            pdE#[i] = Get value: i, "end"
            pdKind$[i] = Get value: i, "boundary_after"
        endfor
        removeObject: pT
    endif
    nLk = 0
    if isPhrase and fileReadable(plinkTsv$)
        lT = Read Table from tab-separated file: plinkTsv$
        nLk = Get number of rows
        lkA# = zero# (nLk)
        lkB# = zero# (nLk)
        lkR# = zero# (nLk)
        lkP# = zero# (nLk)
        for i to nLk
            lkA#[i] = Get value: i, "t_i"
            lkB#[i] = Get value: i, "t_j"
            lkR#[i] = Get value: i, "ratio"
            lkP#[i] = Get value: i, "path"
        endfor
        removeObject: lT
    endif
    # lineage ids in the plan -> display slot
    nUsed = 0
    maxGen = 1
    usedId# = zero# (max(1, nMem))
    for i to nMem
        isNew = 1
        for k to nUsed
            if usedId#[k] = memL#[i]
                isNew = 0
            endif
        endfor
        if isNew
            nUsed = nUsed + 1
            usedId#[nUsed] = memL#[i]
        endif
        maxGen = max(maxGen, memG#[i])
    endfor

    @statNum: "mp_median"
    mpMed = statNum.result
    @stat: "sel_kind"
    selKind$ = stat.result$
    @statNum: "sel_p"
    selP = statNum.result
    @statNum: "sel_drift_ratio"
    selDrift = statNum.result
    @statNum: "sel_mean_link_corr"
    selCorr = statNum.result
    @statNum: "sel_end_corr"
    selEndCorr = statNum.result
    @statNum: "sel_length"
    selLen = statNum.result
    @statNum: "n_lineages"
    nLin = statNum.result
    @statNum: "n_significant"
    nSig = statNum.result
    @statNum: "shuffle_versions"
    nSurr = statNum.result
    @statNum: "shuffle_exact"
    shuffleExact = statNum.result
    @stat: "sel_acoustic_trend"
    selTrend$ = stat.result$
    @stat: "sel_acoustic_detail"
    selTrendDetail$ = stat.result$
    @stat: "sel_acoustic_confidence"
    selConf$ = stat.result$
    # structural (contour) and acoustic (sound) evolution are reported separately
    if selTrend$ = "stable"
        soundLabel$ = "acoustic: stable"
    elsif selTrend$ = "n/a" or selTrend$ = ""
        soundLabel$ = "acoustic: not measured"
    else
        soundLabel$ = "acoustic evolution: " + replace$(selTrend$, "_", " ", 0) + " (" + selConf$ + ")"
    endif
    @statNum: "sel_mean_link_dist"
    selDist = statNum.result
    @statNum: "null_longest_median"
    nullMed = statNum.result
    @statNum: "null_longest_max"
    nullMax = statNum.result
    @statNum: "n_gesture_windows"
    nGestW = statNum.result
    @statNum: "n_windows"
    nWinAll = statNum.result
    @statNum: "n_flat_windows"
    nFlatW = statNum.result
    @statNum: "silent_cells"
    nSilent = statNum.result
    @statNum: "grid_cells"
    nCells = statNum.result
    @statNum: "best_p_fwer"
    bestP = statNum.result

    panelC$ = if engineStr$ = "path" then "C. Evolution path" else "C. Gestural lineage" fi
    pLab$ = if engineStr$ = "path" then "order p" else "chance p" fi
    @statNum: "typical_link_distance"
    typLink = statNum.result
    @niceStep: dur, 8
    tStep = niceStep.result
    @niceStep: max(actualOutputDur, 0.01), 8
    tStepOut = niceStep.result
    Erase all
    Line width: 1
    Solid line
    # ---- header ----
    Font size: 12
    Select inner viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Gestural Lineage Composer v2.1.2##"
    Font size: 7
    Select inner viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Colour: "{0.40, 0.40, 0.50}"
    if engineStr$ = "path"
        subLine$ = replace$(origName$, "_", "-", 0) + " | " + presetName$ + " | " + modeLabel$ + " | evolution path, evolve toward " + replace$(dirStr$, "_", " ", 0) + " | " + if isPhrase then unitLabel$ + ": " + string$(nPhrases) + " " else "" fi + winEffLabel$ + ", matched on " + matchLabel$ + ", " + simStr$
    else
        subLine$ = replace$(origName$, "_", "-", 0) + " | " + presetName$ + " | " + modeLabel$ + " | strict chains | " + featLabel$ + ", " + fixed$(winEff, 2) + " s windows, " + simStr$ + " similarity"
    endif
    Text: 0.5, "centre", 0.22, "half", subLine$

    # ---- A. Acoustic trajectory ----
    yLo = 1e30
    yHi = -1e30
    for i to nTr
        if trY#[i] <> undefined
            yLo = min(yLo, trY#[i])
            yHi = max(yHi, trY#[i])
        endif
    endfor
    if yLo > yHi
        yLo = 0
        yHi = 1
    endif
    if yHi - yLo < 1e-6
        yHi = yLo + 1
    endif
    yPad = 0.08 * (yHi - yLo)
    aLo = yLo - yPad
    aHi = yHi + 2.2 * yPad
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.95, 2.05
    Axes: srcStart, srcEnd, aLo, aHi
    Paint rectangle: "{0.98, 0.98, 0.99}", srcStart, srcEnd, aLo, aHi
    for i to nMem
        @linColour: memL#[i]
        Paint rectangle: linColour.light$, memS#[i], memE#[i], aLo, aHi
    endfor
    # every analysed phrase: a strip along the bottom (alternating greys),
    # boundaries as thin lines (orange: acoustic-change boundary)
    for i to nPhD
        Paint rectangle: if i mod 2 = 1 then "{0.62, 0.64, 0.70}" else "{0.80, 0.82, 0.86}" fi, pdS#[i], pdE#[i], aLo, aLo + 0.045 * (aHi - aLo)
    endfor
    for i to nPhD
        Colour: "{0.70, 0.71, 0.76}"
        Draw line: pdS#[i], aLo, pdS#[i], aHi
        if i < nPhD
            if pdKind$[i] = "change"
                Colour: "{0.88, 0.55, 0.20}"
                Draw line: pdE#[i], aLo, pdE#[i], aHi
            endif
        endif
    endfor
    Select inner viewport: 0.6, 7.7, 0.95, 2.05
    Axes: srcStart, srcEnd, aLo, aHi
    Colour: "{0.25, 0.25, 0.30}"
    for i from 2 to nTr
        if trY#[i] <> undefined and trY#[i - 1] <> undefined
            Draw line: trX#[i - 1], trY#[i - 1], trX#[i], trY#[i]
        endif
    endfor
    Font size: 6
    Select inner viewport: 0.6, 7.7, 0.95, 2.05
    Axes: srcStart, srcEnd, aLo, aHi
    for i to nMem
        @linColour: memL#[i]
        Colour: linColour.c$
        Text: (memS#[i] + memE#[i]) / 2, "centre", aHi - 0.4 * yPad, "half", string$(memG#[i])
    endfor
    Colour: "Black"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.95, 2.05
    Axes: srcStart, srcEnd, aLo, aHi
    Draw inner box
    if featStr$ = "centroid"
        for k from 5 to 14
            hz = 2 ^ k
            if k >= yLo - 0.01 and k <= yHi + 0.01
                lab$ = if hz >= 1000 then fixed$(hz / 1000, 0) + "k" else fixed$(hz, 0) fi
                One mark left: k, "no", "yes", "no", lab$
            endif
        endfor
        unit$ = "centroid (Hz, log)"
    else
        @niceStep: yHi - yLo, 5
        Marks left every: 1, niceStep.result, "yes", "yes", "no"
        unit$ = if featStr$ = "loudness" then "loudness (dB)" else "flatness (log10)" fi
    endif
    Text left: "yes", unit$
    if isPhrase
        Text top: "no", "##A. Source and phrases##  measured " + featLabel$ + "  |  grey strip: the " + string$(nPhrases) + " analysed phrases (orange line: acoustic-change boundary)  |  shaded: phrases of the path(s), by generation"
    else
        Text top: "no", "##A. Acoustic trajectory##  measured " + featLabel$ + "  |  shaded: gestures of the " + if engineStr$ = "path" then "path(s)" else "lineage(s)" fi + " used, numbered by generation"
    endif
    Marks bottom every: 1, tStep, "no", "yes", "no"

    # ---- B. Phrase relationships (phrase units) / Relations / Matrix profile ----
    if isPhrase
    Font size: 7
    Select inner viewport: 0.6, 7.7, 2.6, 3.55
    Axes: srcStart, srcEnd, 0, 1.08
    Paint rectangle: "{0.98, 0.98, 0.99}", srcStart, srcEnd, 0, 1.08
    spanMax = 0
    for i to nLk
        spanMax = max(spanMax, lkB#[i] - lkA#[i])
    endfor
    if spanMax <= 0
        spanMax = 1
    endif
    # relation arcs: height = time between the two phrases, darker = closer
    for pass to 2
        for i to nLk
            if (pass = 1 and lkP#[i] = 0) or (pass = 2 and lkP#[i] > 0)
                hArc = 0.06 + 0.94 * (lkB#[i] - lkA#[i]) / spanMax
                if lkP#[i] > 0
                    @linColour: lkP#[i]
                    Colour: linColour.c$
                    Line width: 2.2
                else
                    g = 0.40 + 0.45 * min(1, lkR#[i] / link_tolerance)
                    Colour: "{" + fixed$(g, 2) + ", " + fixed$(g, 2) + ", " + fixed$(min(1, g + 0.04), 2) + "}"
                    Line width: 0.8
                endif
                xa = lkA#[i]
                ya = 0
                for kSeg to 16
                    th = pi * kSeg / 16
                    xb = lkA#[i] + (lkB#[i] - lkA#[i]) * (1 - cos(th)) / 2
                    yb = hArc * sin(th)
                    Draw line: xa, ya, xb, yb
                    xa = xb
                    ya = yb
                endfor
            endif
        endfor
    endfor
    Line width: 1
    for i to nPhD
        Paint circle (mm): "{0.35, 0.36, 0.42}", (pdS#[i] + pdE#[i]) / 2, 0, 0.5
    endfor
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 2.6, 3.55
    Axes: srcStart, srcEnd, 0, 1.08
    Draw inner box
    Text left: "yes", "time apart"
    Text top: "no", "##B. Phrase relationships##  arcs join each phrase to its mutual " + string$(kLinks) + " nearest later relatives (within " + fixed$(link_tolerance, 1) + " x typical)  |  darker = closer  |  coloured: path links"
    Marks bottom every: 1, tStep, "no", "yes", "no"
    else
    pHi = 0
    for i to nMp
        if mpY#[i] <> undefined
            pHi = max(pHi, mpY#[i])
        endif
    endfor
    if pHi <= 0
        pHi = 1
    endif
    pHi = 1.08 * pHi
    Font size: 7
    Select inner viewport: 0.6, 7.7, 2.6, 3.55
    Axes: srcStart, srcEnd, 0, pHi
    Paint rectangle: "{0.98, 0.98, 0.99}", srcStart, srcEnd, 0, pHi
    Select inner viewport: 0.6, 7.7, 2.6, 3.55
    Axes: srcStart, srcEnd, 0, pHi
    Colour: "{0.45, 0.45, 0.55}"
    for i from 2 to nMp
        if mpY#[i] <> undefined and mpY#[i - 1] <> undefined
            Draw line: mpX#[i - 1], mpY#[i - 1], mpX#[i], mpY#[i]
        endif
    endfor
    if mpMed <> undefined
        Colour: "{0.75, 0.35, 0.35}"
        Dashed line
        Draw line: srcStart, mpMed, srcEnd, mpMed
        Solid line
    endif
    for i to nMem
        if memP#[i] <> undefined
            @linColour: memL#[i]
            Paint circle (mm): linColour.c$, (memS#[i] + memE#[i]) / 2, memP#[i], 0.7
        endif
    endfor
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 2.6, 3.55
    Axes: srcStart, srcEnd, 0, pHi
    Draw inner box
    @niceStep: pHi, 4
    Marks left every: 1, niceStep.result, "yes", "yes", "no"
    Text left: "yes", "distance"
    if engineStr$ = "path"
        Text top: "no", "##B. Relations##  each candidate window's distance to its nearest other gesture (" + matchLabel$ + ")  |  dashed: typical (median)  |  dots: path members"
    else
        Text top: "no", "##B. Matrix profile##  each window's distance to its nearest neighbour  |  dashed: median  |  dots: lineage members"
    endif
    if nMem > 0
        Marks bottom every: 1, tStep, "no", "yes", "no"
    else
        Marks bottom every: 1, tStep, "yes", "yes", "no"
        Text bottom: "yes", "Source time (s)"
    endif
    endif

    # ---- C. Gestural lineage ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 4.15, 5.45
    Axes: srcStart, srcEnd, 0.4, maxGen + 0.6
    Paint rectangle: "{0.98, 0.98, 0.99}", srcStart, srcEnd, 0.4, maxGen + 0.6
    if nMem > 0
        for k to nUsed
            @linColour: usedId#[k]
            yOff = 0
            if nUsed > 1
                yOff = 0.5 * ((k - 1) / (nUsed - 1) - 0.5)
            endif
            for i to nMem
                if memL#[i] = usedId#[k]
                    Paint rectangle: linColour.c$, memS#[i], memE#[i], memG#[i] + yOff - 0.07, memG#[i] + yOff + 0.07
                endif
            endfor
            Select inner viewport: 0.6, 7.7, 4.15, 5.45
            Axes: srcStart, srcEnd, 0.4, maxGen + 0.6
            Colour: linColour.c$
            prevX = undefined
            for i to nMem
                if memL#[i] = usedId#[k]
                    cx = (memS#[i] + memE#[i]) / 2
                    if prevX <> undefined
                        Draw line: prevX, prevY, cx, memG#[i] + yOff
                    endif
                    prevX = cx
                    prevY = memG#[i] + yOff
                endif
            endfor
        endfor
        # link shape correlations, from the plan (lineage, generation, link_corr)
        Font size: 5
        Select inner viewport: 0.6, 7.7, 4.15, 5.45
        Axes: srcStart, srcEnd, 0.4, maxGen + 0.6
        if nRows <= 40
            for iRow to nRows
                if rowCorr#[iRow] <> undefined and rowGen#[iRow] > 1
                    for i to nMem
                        if memL#[i] = rowLin#[iRow] and memG#[i] = rowGen#[iRow]
                            for j to nMem
                                if memL#[j] = rowLin#[iRow] and memG#[j] = rowGen#[iRow] - 1
                                    Colour: "{0.30, 0.30, 0.30}"
                                    Text: ((memS#[i] + memE#[i]) / 2 + (memS#[j] + memE#[j]) / 2) / 2, "centre", memG#[i] - 0.5, "half", "r " + fixed$(rowCorr#[iRow], 2)
                                endif
                            endfor
                        endif
                    endfor
                endif
            endfor
        endif
        Font size: 7
    else
        Select inner viewport: 0.6, 7.7, 4.15, 5.45
        Axes: 0, 1, 0, 1
        Colour: "{0.55, 0.20, 0.20}"
        Text: 0.5, "centre", 0.55, "half", "No lineage used"
        Font size: 6
        Select inner viewport: 0.6, 7.7, 4.15, 5.45
        Axes: 0, 1, 0, 1
        Colour: "{0.35, 0.35, 0.35}"
        Text: 0.5, "centre", 0.35, "half", replace$(left$(reason$, 150), "_", "-", 0)
        Font size: 7
    endif
    if isWeak and nMem > 0
        # Text top ignores Colour: the warning goes inside the panel, in world coordinates
        Font size: 7
        Select inner viewport: 0.6, 7.7, 4.15, 5.45
        Axes: 0, 1, 0, 1
        Colour: "{0.75, 0.10, 0.10}"
        Text: 0.01, "left", 0.92, "half", "##" + weakTitle$ + if status$ = "exploratory" then " (p = " + fixed$(selP, 3) + ")" else "" fi + "##"
    endif
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 4.15, 5.45
    Axes: srcStart, srcEnd, 0.4, maxGen + 0.6
    Draw inner box
    if nMem > 0
        Marks left every: 1, if maxGen > 12 then 2 else 1 fi, "yes", "yes", "no"
        Text left: "yes", "generation"
        Marks bottom every: 1, tStep, "yes", "yes", "no"
        Text bottom: "yes", "Source time (s)"
        if isWeak and selP <> undefined
            Text top: "no", "##" + panelC$ + " (" + weakTag$ + ")##  " + soundLabel$ + ", " + selKind$ + ", " + fixed$(selLen, 0) + " generations, " + pLab$ + " = " + fixed$(selP, 3) + if simStr$ = "shape" then "  |  r = shape correlation of each link" else "" fi
        elsif status$ = "ok" and selP <> undefined
            Text top: "no", "##" + panelC$ + "##  " + soundLabel$ + ", " + selKind$ + ", " + fixed$(selLen, 0) + " generations, " + pLab$ + " = " + fixed$(selP, 3) + ", drift ratio " + fixed$(selDrift, 2) + if simStr$ = "shape" then "  |  r = shape correlation of each link" else "" fi
        else
            Text top: "no", "##" + panelC$ + "##"
        endif
    else
        Text top: "no", "##" + panelC$ + "##"
    endif

    # ---- D. Compositional reconstruction ----
    Font size: 7
    if resultSound > 0 and nRows > 0
        selectObject: resultSound
        if nChannels > 1
            vizOut = Extract one channel: anaCh
        else
            vizOut = Copy: "glc_viz"
        endif
        selectObject: vizOut
        wPk = Get absolute extremum: 0, 0, "none"
        if wPk < 1e-6
            wPk = 1
        endif
        wPk = 1.15 * wPk
        Select inner viewport: 0.6, 7.7, 6.1, 7.05
        Axes: 0, actualOutputDur, -wPk, wPk
        Paint rectangle: "{0.98, 0.98, 0.99}", 0, actualOutputDur, -wPk, wPk
        for iP to nPieces
            if pieceRow#[iP] > 0
                @linColour: rowLin#[pieceRow#[iP]]
                Paint rectangle: linColour.light$, pieceOut0#[iP], pieceOut1#[iP], -wPk, wPk
            endif
        endfor
        Select inner viewport: 0.6, 7.7, 6.1, 7.05
        selectObject: vizOut
        Colour: "{0.20, 0.20, 0.25}"
        Draw: 0, 0, -wPk, wPk, "no", "Curve"
        # joins (centre of each crossfade), drawn over the audio
        Select inner viewport: 0.6, 7.7, 6.1, 7.05
        Axes: 0, actualOutputDur, -wPk, wPk
        Colour: "{0.55, 0.55, 0.62}"
        Dotted line
        for iP from 2 to nPieces
            xj = pieceOut0#[iP] + xfadeEff / 2
            Draw line: xj, -wPk, xj, wPk
        endfor
        Solid line
        Select inner viewport: 0.6, 7.7, 6.1, 7.05
        Axes: 0, actualOutputDur, -wPk, wPk
        Font size: 5
        Select inner viewport: 0.6, 7.7, 6.1, 7.05
        Axes: 0, actualOutputDur, -wPk, wPk
        for iP to nPieces
            if pieceRow#[iP] > 0
                iRow = pieceRow#[iP]
                @linColour: rowLin#[iRow]
                Colour: linColour.c$
                Text: (pieceOut0#[iP] + pieceOut1#[iP]) / 2, "centre", 0.86 * wPk, "half", string$(rowGen#[iRow])
                if nRows <= 24
                    Colour: "{0.35, 0.35, 0.35}"
                    Text: (pieceOut0#[iP] + pieceOut1#[iP]) / 2, "centre", -0.86 * wPk, "half", fixed$(rowStart#[iRow], 1) + " s"
                endif
            endif
        endfor
        removeObject: vizOut
        Font size: 7
        Colour: "Black"
        Select inner viewport: 0.6, 7.7, 6.1, 7.05
        Axes: 0, actualOutputDur, -wPk, wPk
        Draw inner box
        Marks bottom every: 1, tStepOut, "yes", "yes", "no"
        Text bottom: "yes", "Output time (s)"
        Text top: "no", "##D. Compositional reconstruction##  " + fixed$(actualOutputDur, 2) + " s from " + string$(nRows) + if isPhrase then " source phrases (original durations)" else " source gestures" fi + "  |  top: generation, bottom: source time"
    else
        Select inner viewport: 0.6, 7.7, 6.1, 7.05
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.98, 0.98, 0.99}", 0, 1, 0, 1
        Colour: "{0.55, 0.20, 0.20}"
        Text: 0.5, "centre", 0.5, "half", if resultSound > 0 then "Result = the source, unchanged (nothing in it can be related)" else "No Sound was made (Strict is on and no lineage is beyond chance)" fi
        Colour: "Black"
        Select inner viewport: 0.6, 7.7, 6.1, 7.05
        Axes: 0, 1, 0, 1
        Draw inner box
        Text top: "no", "##D. Compositional reconstruction##"
    endif

    # ---- summary ----
    Font size: 6
    Select inner viewport: 0.6, 7.7, 7.6, 8.45
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 7.6, 8.45
    Axes: 0, 1, 0, 1
    Text: 0.015, "left", 0.84, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, 7.6, 8.45
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.25}"
    if isPhrase
        @statNum: "phrase_dur_min"
        dmin = statNum.result
        @statNum: "phrase_dur_max"
        dmax = statNum.result
        Text: 0.015, "left", 0.62, "half", "Analysis: " + string$(nPhrases) + " phrases, " + segMethod$ + ", " + fixed$(dmin, 2) + " to " + fixed$(dmax, 2) + " s | links: mutual " + string$(kLinks) + " nearest, within " + fixed$(link_tolerance, 1) + " x typical (" + fixed$(typLink, 2) + ") | " + fixed$(nLin, 0) + " path(s) used"
        Text: 0.015, "left", 0.42, "half", "Order test: " + fixed$(nSurr, 0) + if shuffleExact = 1 then " (all possible)" else "" fi + " other orders of the same phrases searched the same way, their best path median " + fixed$(nullMed, 0) + " / max " + fixed$(nullMax, 0) + " phrases | p " + if bestP = undefined then "-" else fixed$(bestP, 3) fi
    elsif engineStr$ = "path"
        Text: 0.015, "left", 0.62, "half", "Analysis: " + fixed$(nGestW, 0) + " of " + fixed$(nWinAll, 0) + " windows are candidates (80 percent sounding; silent cells " + fixed$(nSilent, 0) + "/" + fixed$(nCells, 0) + ") | links: mutual " + string$(kLinks) + " nearest, within " + fixed$(link_tolerance, 1) + " x typical (" + fixed$(typLink, 2) + ") | " + fixed$(nLin, 0) + " path(s) used"
        Text: 0.015, "left", 0.42, "half", "Order test: " + fixed$(nSurr, 0) + if shuffleExact = 1 then " (all possible)" else "" fi + " time-shuffled versions searched the same way, their best path median " + fixed$(nullMed, 0) + " / max " + fixed$(nullMax, 0) + " gestures | p " + if bestP = undefined then "-" else fixed$(bestP, 3) fi
    else
    Text: 0.015, "left", 0.62, "half", "Analysis: " + fixed$(nGestW, 0) + " of " + fixed$(nWinAll, 0) + " windows carry a gesture (" + fixed$(nFlatW, 0) + " flat, silent cells " + fixed$(nSilent, 0) + "/" + fixed$(nCells, 0) + ") | " + fixed$(nLin, 0) + " distinct lineages, " + fixed$(nSig, 0) + " beyond chance"
    Text: 0.015, "left", 0.42, "half", "Chance test: " + fixed$(nSurr, 0) + if shuffleExact = 1 then " (all possible)" else "" fi + " time-shuffled versions run, their longest chain median " + fixed$(nullMed, 0) + " / max " + fixed$(nullMax, 0) + " | best p " + if bestP = undefined then "-" else fixed$(bestP, 3) fi
    endif
    if fallback$ <> ""
        Colour: "{0.70, 0.15, 0.15}"
        Text: 0.015, "left", 0.05, "half", "FALLBACK: " + replace$(left$(fallback$, 150), "_", "-", 0)
        Colour: "{0.25, 0.25, 0.25}"
    elsif adapted$ <> "" and adapted$ <> "?"
        Colour: "{0.70, 0.15, 0.15}"
        Text: 0.015, "left", 0.05, "half", "Adapted: " + replace$(left$(adapted$, 150), "_", "-", 0)
        Colour: "{0.25, 0.25, 0.25}"
    endif
    if status$ = "ok" or isWeak
        Text: 0.015, "left", 0.22, "half", if isWeak then weakLabel$ + " - " else "Significant - " fi + if simStr$ = "shape" then if engineStr$ = "path" then "Path: mean link shape r " else "Lineage: mean link shape r " fi + fixed$(selCorr, 3) + ", first vs last r " + fixed$(selEndCorr, 3) else "Lineage: mean link distance " + fixed$(selDist, 3) fi + " | " + soundLabel$ + " | output " + fixed$(actualOutputDur, 2) + " s, peak " + fixed$(peakOut, 3) + if peakScaled then " (scaled)" else "" fi + ", crossfade " + fixed$(xfadeEff * 1000, 1) + " ms" + if nOverlapPairs > 0 then ", " + string$(nOverlapPairs) + " overlapping source pairs" else "" fi
    else
        Text: 0.015, "left", 0.22, "half", "Status: " + replace$(status$, "_", " ", 0) + " - " + replace$(left$(reason$, 140), "_", "-", 0)
    endif
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 7.6, 8.45
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Select outer viewport: 0, 8, 0, 8.7
endif

# ---- report ----
appendInfoLine: ""
appendInfoLine: "=== RESULT ==="
if fileReadable(statsTxt$)
    appendInfoLine: "Status:        ", status$, if reason$ <> "" and reason$ <> "?" then " - " + reason$ else "" fi
    if adapted$ <> "" and adapted$ <> "?"
        appendInfoLine: "Adapted:       ", adapted$
    endif
    @sf: "window_s", 3
    if fallback$ <> ""
        appendInfoLine: "FALLBACK:      ", fallback$
    endif
    if isPhrase
        @sf: "phrase_dur_min", 2
        a$ = sf.r$
        @sf: "phrase_dur_median", 2
        b$ = sf.r$
        @sf: "phrase_dur_max", 2
        c$ = sf.r$
        appendInfoLine: "Phrases:       ", nPhrases, " from ", segMethod$, " | durations ", a$, " / ", b$, " / ", c$, " s (min / median / max)"
        if unitStr$ = "phrase_auto"
            @sf: "min_phrase_s", 2
            a$ = sf.r$
            @sf: "max_phrase_s", 1
            b$ = sf.r$
            @sf: "pause_threshold_db", 1
            appendInfoLine: "Segmentation:  phrase length ", a$, " - ", b$, " s | pause threshold ", sf.r$, " dB | phrase detail ", fixed$(phrase_detail, 0)
        endif
        appendInfoLine: "Analysed:      matched on ", matchLabel$, " (contours on a shared grid; duration and pauses kept) | links: mutual ", kLinks, " nearest"
    elsif engineStr$ = "path"
        appendInfoLine: "Analysed:      matched on ", matchLabel$, ", ", sf.r$, " s windows (panel A shows ", featLabel$, ")"
    else
        appendInfoLine: "Analysed:      ", featLabel$, ", ", sf.r$, " s windows"
    endif
    @sf: "n_gesture_windows", 0
    a$ = sf.r$
    @sf: "n_windows", 0
    b$ = sf.r$
    @sf: "n_flat_windows", 0
    c$ = sf.r$
    @sf: "n_undefined_windows", 0
    d$ = sf.r$
    if isPhrase
        @sf: "typical_link_distance", 3
        appendInfoLine: "Relations:     typical nearest phrase distance ", sf.r$
    elsif engineStr$ = "path"
        @sf: "typical_link_distance", 3
        appendInfoLine: "Windows:       ", a$, " of ", b$, " are candidates (at least 80% sounding) | typical nearest distance ", sf.r$
    else
        appendInfoLine: "Windows:       ", a$, " of ", b$, " carry a gesture (", c$, " flat, ", d$, " touch silence)"
    endif
    @sf: "n_lineages", 0
    a$ = sf.r$
    @sf: "n_significant", 0
    b$ = sf.r$
    @sf: "n_raw_chains_ge3", 0
    c$ = sf.r$
    if engineStr$ = "path"
        appendInfoLine: "Paths used:    ", a$
    else
        appendInfoLine: "Lineages:      ", a$, " distinct (from ", c$, " raw chains of 3+), ", b$, " beyond chance"
    endif
    @sf: "shuffle_versions", 0
    a$ = sf.r$
    @stat: "shuffle_exact"
    if stat.result$ = "1"
        a$ = a$ + " (every possible order)"
    endif
    @sf: "null_longest_median", 1
    b$ = sf.r$
    @sf: "null_longest_max", 0
    c$ = sf.r$
    if isPhrase
        appendInfoLine: "Order test:    ", a$, " other orders of the same phrases searched the same way; their best path: median ", b$, ", max ", c$, " phrases"
    elsif engineStr$ = "path"
        appendInfoLine: "Order test:    ", a$, " time-shuffled versions searched the same way; their best path: median ", b$, ", max ", c$, " gestures"
    else
        appendInfoLine: "Chance test:   ", a$, " time-shuffled versions; their longest chain: median ", b$, ", max ", c$
    endif
    @stat: "sel_length"
    if stat.result$ <> "?"
        @sf: "sel_length", 0
        a$ = sf.r$
        @stat: "sel_kind"
        b$ = stat.result$
        @sf: "sel_p", 3
        c$ = sf.r$
        if engineStr$ = "path"
            @stat: "sel_direction"
            appendInfoLine: "Path used:     ", a$, " generations, ", b$, ", evolve toward ", replace$(stat.result$, "_", " ", 0), ", order p = ", c$
            if isPhrase
                @stat: "sel_phrases"
                a$ = stat.result$
                @sf: "sel_duration_ratio", 2
                appendInfoLine: "Phrases used:  ", a$, " (numbers as in the phrase TextGrid) | longest / shortest duration ", sf.r$, "x"
            endif
        else
            appendInfoLine: "Lineage used:  ", a$, " generations, ", b$, ", chance p = ", c$
        endif
        @sf: "sel_mean_link_corr", 3
        a$ = sf.r$
        @sf: "sel_min_link_corr", 3
        b$ = sf.r$
        @sf: "sel_end_corr", 3
        c$ = sf.r$
        if simStr$ = "shape"
            appendInfoLine: "Shape r:       links mean ", a$, " (weakest ", b$, ") | first vs last ", c$, if engineStr$ = "path" and matchStr$ = "all" then " (mean over the three features)" else "" fi
        else
            @sf: "sel_mean_link_dist", 3
            appendInfoLine: "Link distance: mean ", sf.r$, " (absolute feature units x sqrt(window cells))"
        endif
        @stat: "sel_acoustic_trend"
        a$ = stat.result$
        @stat: "sel_acoustic_confidence"
        if stat.result$ <> "-" and stat.result$ <> ""
            a$ = a$ + " (" + stat.result$ + ")"
        endif
        @stat: "sel_acoustic_detail"
        appendInfoLine: "Sound change:  ", a$, " - ", stat.result$
        @sf: "sel_drift_ratio", 2
        a$ = sf.r$
        @sf: "sel_monotonicity", 2
        b$ = sf.r$
        @sf: "sel_span_s", 2
        c$ = sf.r$
        @sf: "sel_first_start", 3
        d$ = sf.r$
        @sf: "sel_last_start", 3
        e$ = sf.r$
        appendInfoLine: "Drift:         ratio ", a$, " | steadiness ", b$, " | span ", c$, " s (", d$, " s -> ", e$, " s)"
        if modeStr$ = "guided"
            @sf: "anchor_window_start", 3
            a$ = sf.r$
            @sf: "anchor_position", 0
            b$ = sf.r$
            appendInfoLine: "Anchor window: starts ", a$, " s, generation ", b$, " of this lineage"
        endif
        if modeStr$ = "branching" or modeStr$ = "montage"
            @sf: "used_lineages", 0
            appendInfoLine: "Lineages used: ", sf.r$
        endif
        if modeStr$ = "branching"
            @stat: "branch_root_ratios"
            appendInfoLine: "Branch roots:  first-gesture distance to the root lineage's (x typical): ", stat.result$
        endif
    endif
endif
if resultSound > 0
    appendInfoLine: "Output:        ", resultName$, " | ", fixed$(actualOutputDur, 3), " s | ", nRows, if isPhrase then " phrases" else " gestures" fi, " | peak ", fixed$(peakOut, 4)
endif
# ---- optional TextGrid of the analysed phrases (path members marked) ----
phraseTg = 0
if isPhrase and unitIdx > 1 and phrase_textgrid and fileReadable(phrTsv$)
    phT = Read Table from tab-separated file: phrTsv$
    nPh = Get number of rows
    phS# = zero# (nPh)
    phE# = zero# (nPh)
    for i to nPh
        phS#[i] = Get value: i, "start"
        phE#[i] = Get value: i, "end"
    endfor
    for i to nPh
        phLab$[i] = Get value: i, "label"
        phTag$[i] = ""
    endfor
    removeObject: phT
    if fileReadable(memTsv$)
        mT = Read Table from tab-separated file: memTsv$
        nM = Get number of rows
        for k to nM
            ms = Get value: k, "start"
            ml = Get value: k, "lineage"
            mg = Get value: k, "generation"
            for i to nPh
                if abs(phS#[i] - ms) < 1e-6
                    phTag$[i] = phTag$[i] + " | path " + string$(ml) + " gen " + string$(mg)
                endif
            endfor
        endfor
        removeObject: mT
    endif
    phraseTg = Create TextGrid: srcStart, srcEnd, "phrases", ""
    Rename: origName$ + "_GLC_phrases"
    lastB = srcStart
    for i to nPh
        if phS#[i] > lastB + 1e-6 and phS#[i] < srcEnd - 1e-6
            nocheck Insert boundary: 1, phS#[i]
            lastB = phS#[i]
        endif
        if phE#[i] > lastB + 1e-6 and phE#[i] < srcEnd - 1e-6
            nocheck Insert boundary: 1, phE#[i]
            lastB = phE#[i]
        endif
        iv = Get interval at time: 1, (phS#[i] + phE#[i]) / 2
        Set interval text: 1, iv, phLab$[i] + phTag$[i]
    endfor
    appendInfoLine: "Phrase TextGrid: ", origName$, "_GLC_phrases (", nPh, " phrases; path members marked)"
endif
@cleanUpTempFiles

if resultSound > 0
    selectObject: resultSound
    if play_result
        Play
    endif
else
    selectObject: origSound
endif
