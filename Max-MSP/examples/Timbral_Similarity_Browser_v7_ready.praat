#@tool mode=browser output=host_save_selected_sound title="Timbral Similarity Browser v1.4"
#@param Folder type=folder
#@preset "Standard (12 MFCC)" preset=1 num_coefficients=12 window_length=0.015 time_step=0.005
#@preset "Detailed (24 MFCC)" preset=2 num_coefficients=24 window_length=0.020 time_step=0.005
#@preset "Fast (6 MFCC)" preset=3 num_coefficients=6 window_length=0.015 time_step=0.010
#@preset "Custom (use Analysis Parameters below)" preset=4

# ============================================================
# Praat AudioTools - Timbral_Similarity_Browser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Concatenation now follows the computed path
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Timbral Similarity Browser - Orders sounds from a folder by
#   MFCC-based timbral similarity using a nearest-neighbor path.
#
#   Similarity model: each sound is reduced to the TIME-AVERAGED MFCC
#   vector and compared by Euclidean distance. This is a global average
#   timbre model, not a model of timbral evolution - two files with the
#   same mean MFCC but completely different trajectories come out
#   near-identical. The Standardized metric equalizes the weight of each
#   coefficient; neither variant uses variance, deltas, covariance or
#   DTW. Mean + SD, frame-distribution distance and trajectory DTW are
#   the obvious extensions if evolution matters for a given collection.
#
# Changelog v1.4:
#
#     - FIXED (the audio never followed the path): `Concatenate` and
#       `Concatenate with overlap` join sounds in the order they appear
#       in the OBJECT LIST, not the order they were selected. Selecting
#       the path's first sound and adding the rest with plusObject had
#       no bearing on the result - the output came out in load order.
#       This was true in v1.2 and v1.3 alike, and it made the tool
#       internally inconsistent in a way none of the reports revealed:
#       the info window, the path statistics, the Path Sequence panel
#       and the distance matrix all showed the computed similarity
#       path, while the rendered waveform, its boundary markers and the
#       appended un-analyzable tail were in a different order entirely.
#       Resampling made it worse, since replaced objects move to the
#       bottom of the list. Fresh copies are now created in path order
#       - created sequentially, so their object-list order IS the path
#       - and those copies are concatenated and then removed. Short
#       fades are applied to the copies, leaving the loaded originals
#       untouched.
#     - Renamed the default Start_mode to "First analyzable file",
#       which is what it has always done when sound 1 cannot be
#       analyzed.
#     - The STEP 2 MFCC tally is now labelled provisional, since the
#       coefficient-validity check in STEP 3 can still demote a sound
#       counted there; STEP 3 prints the final counts alongside the
#       usable-vector total.
#
# Changelog v1.3:
#
#   CORRECTNESS FIXES:
#     - FIXED (loading): success was tested with
#       `numberOfSelected("Sound") = 0` after a `nocheck Read from
#       file`, which asks whether ANY Sound is selected, not whether
#       the read produced one. A Sound left selected by the previous
#       iteration - or by the user before the script ran - passed the
#       test, so a failed read incremented loadCount and stored the
#       PREVIOUS object id again: the earlier file was analysed and
#       concatenated in place of the failed one, and cleanup then
#       called removeObject twice on the same id. Each read is now
#       verified against a disposable probe Sound.
#     - FIXED (dead controls): Num_coefficients, Window_length and
#       Time_step were overwritten by every one of the three presets,
#       and the `else` branch that would have preserved them was
#       unreachable from the form. Preset 4 "Custom" now exists;
#       presets 1-3 keep their indices and values.
#     - FIXED (path): un-analyzable sounds were folded into the same
#       path via an artificial `penalty = maxDist + 1.0`, and the path
#       always began at sound 1 - so an un-analyzable sound 1 opened
#       the path instead of being deferred to the end as the info line
#       claimed, and with all its distances equal the second step fell
#       back to index order. The path is now built over analyzable
#       sounds only; the rest are appended afterwards in load order and
#       excluded from path statistics. The penalty is gone entirely.
#     - FIXED (validity): `analyzed_i = 1` was set as soon as an MFCC
#       object existed, with no check that it had frames. A frameless
#       MFCC yielded an all-zero mean vector sitting at the origin of
#       the feature space looking like a real timbre - the same problem
#       v1.1 set out to solve, re-entering by another door. nFrames is
#       now checked, a sound whose coefficients have no defined values
#       is demoted, and the length threshold is derived from
#       Window_length instead of a hardcoded 0.02 s that ignored the
#       analysis settings.
#     - FIXED (heatmap scale): maxDist was computed over the whole
#       matrix including rows for phantom zero vectors, then penalty
#       cells were normalized by it, giving intensity > 1 and colour
#       components outside 0-1 - and with maxDist = 0 a penalty cell
#       was painted as MAXIMUM similarity. maxDist is now taken over
#       valid pairs only, intensity is clamped, and cells involving an
#       un-analyzable sound are drawn in neutral grey.
#     - FIXED (visualization): the subtitle used axis y = -1 in a
#       0-0.5 inch title viewport, mapping to outer y = 1.0 - inside
#       the Output Waveform panel, so it was drawn over the waveform.
#       It was also at x = 0.2 with "centre" alignment. Same fix as
#       Self_Attention_Recomposer v1.1. The summary bar gained the
#       `Draw inner box` the suite layout calls for.
#     - HARDENED (resampling): the resampled object is now explicitly
#       reselected before Rename, rather than relying on the selection
#       surviving the removeObject of the original.
#
#   NEW CONTROLS (defaults reproduce v1.2 behaviour):
#     - Target_sample_rate: v1.2 adopted the rate of whichever file
#       loaded first and resampled the rest to it, so an 8 kHz file at
#       the top of the alphabet dragged the whole collection down and
#       renaming a file could change the result. Resampling is now
#       deferred until all files are loaded. Default = first loaded
#       file; also highest in collection, 44100, 48000.
#     - Start_mode: the path always started at sound 1, so a rename or
#       a change in listing order could rewrite it with no change to
#       the audio. Default = first file; also medoid, most isolated,
#       and try-every-start-keep-shortest.
#     - Distance_metric: raw mean MFCC (default) weights coefficients
#       by their numeric range, so low-order coefficients dominate.
#       Standardized applies a per-coefficient z-score first.
#     - Join_mode + Join_fade_s: v1.2 hard-concatenated with no fade,
#       DC match or zero-crossing alignment, so adjacent files could
#       click. Default keeps hard concatenation; short fades and
#       crossfade are options, and boundary markers in the
#       visualization account for the shortening overlap causes.
#     - Output_level: `Scale peak: 0.99` is normalization, not a
#       limiter - a quiet collection was always pushed up to 0.99.
#       Default still normalizes; preserve and conditional limiter
#       are available.
#
# Changelog v1.2:
#   - Added a "Folder" form field (mirrors VoidMosaic): type a path, or
#     leave it blank to fall back to a folder-selection dialog. The path
#     is whitespace- and trailing-slash-trimmed; cancelling the dialog
#     exits cleanly. Synced the version string across header/form/banner.
#
# Changelog v1.1:
#   - Guard against a single-sound batch (n = 1): no path/stats
#     division-by-zero; the one sound is output directly.
#   - Sounds too short to analyze (no MFCC) no longer pollute the
#     ordering with an all-zero feature vector. Their distance to
#     everything is set just above the max, so the nearest-neighbor
#     path visits them LAST instead of treating silence-like zero
#     vectors as mutually similar. (Changes ordering only for
#     batches that contain an un-analyzable file.)
#
# Changelog v1.0:
#   - Added path sequence display
#   - Added sound boundaries on waveform
#   - Added total path length metric
#   - Improved visualization layout
# ============================================================

form Timbral Similarity Browser v1.4
    comment === Audio Folder ===
    comment (Leave blank to pick a folder with a dialog)
    sentence Folder 
    comment === Preset ===
    optionmenu Preset: 1
        option Standard (12 MFCC)
        option Detailed (24 MFCC)
        option Fast (6 MFCC)
        option Custom (use Analysis Parameters below)
    comment === Loading Options ===
    integer Max_files_to_load 0 (= all)
    optionmenu Target_sample_rate: 1
        option First loaded file
        option Highest in collection
        option 44100 Hz
        option 48000 Hz
    comment === Analysis Parameters (Custom preset only) ===
    integer Num_coefficients 12
    positive Window_length 0.015
    positive Time_step 0.005
    optionmenu Distance_metric: 1
        option Raw mean MFCC
        option Standardized mean MFCC
    comment === Path ===
    optionmenu Start_mode: 1
        option First analyzable file
        option Most central (medoid)
        option Most isolated
        option Shortest greedy path (try all starts)
    comment === Output ===
    optionmenu Join_mode: 1
        option Hard concatenate
        option Short fades
        option Crossfade
    positive Join_fade_s 0.010
    optionmenu Output_level: 3
        option Preserve
        option Conditional limiter
        option Normalize to 0.99
    boolean Draw_visualization 1
    boolean Auto_play 1
endform

# ===== PRESET LOGIC =====
# v1.3 (item 1): v1.2 offered only three presets, every one of which
# overwrote Num_coefficients / Window_length / Time_step, and the `else`
# branch that would have preserved them was unreachable from the form.
# The three manual fields were therefore dead controls. Preset 4 is now a
# real Custom option; presets 1-3 keep their previous indices and values.
if preset = 1
    num_coefficients = 12
    window_length = 0.015
    time_step = 0.005
    presetName$ = "Standard"
elsif preset = 2
    num_coefficients = 24
    window_length = 0.020
    time_step = 0.005
    presetName$ = "Detailed"
elsif preset = 3
    num_coefficients = 6
    window_length = 0.015
    time_step = 0.010
    presetName$ = "Fast"
else
    presetName$ = "Custom"
endif

if num_coefficients < 1
    exitScript: "Num_coefficients must be at least 1."
endif

# v1.3 (item 4): the "too short to analyze" threshold was a hardcoded
# 0.02 s that ignored the analysis settings entirely - with the Detailed
# preset's 0.020 s window a 0.021 s file passed the test and yielded a
# single frame. It is now derived from the window actually in use.
minAnalysisDur = window_length * 3
if minAnalysisDur < 0.02
    minAnalysisDur = 0.02
endif

clearinfo
writeInfoLine: "=== Timbral Similarity Browser v1.4 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "MFCC coefficients: ", num_coefficients
appendInfoLine: "Window: ", fixed$(window_length * 1000, 1), " ms | step: ", fixed$(time_step * 1000, 1), " ms"
appendInfoLine: "Min analyzable duration: ", fixed$(minAnalysisDur * 1000, 1), " ms"
appendInfoLine: ""

# ========== STEP 1: LOAD SOUNDS ==========
appendInfoLine: "STEP 1: Loading sounds from folder"
appendInfoLine: "------------------------------------"

# --- FOLDER DISCOVERY ---
# Mirrors VoidMosaic: use the typed path, or fall back to a dialog when
# the Folder field is left blank. Trim whitespace and trailing slashes
# first; the trailing-slash normalization just below re-adds it for the
# *.wav glob.
directory$ = replace_regex$(folder$, "^[ \t]*|[ \t]*$", "", 0)
directory$ = replace_regex$(directory$, "[\\/]+$", "", 0)

if directory$ == ""
    directory$ = chooseFolder$: "Select folder containing .wav files"
    directory$ = replace_regex$(directory$, "[\\/]+$", "", 0)
endif

if directory$ == ""
    exitScript: "Operation cancelled. Please supply a valid folder path."
endif

if right$(directory$, 1) <> "/" and right$(directory$, 1) <> "\"
    if index(directory$, "\") > 0
        directory$ = directory$ + "\"
    else
        directory$ = directory$ + "/"
    endif
endif

appendInfoLine: "Loading from: ", directory$

files$# = fileNames_caseInsensitive$#(directory$ + "*.wav")
nFiles = size(files$#)

if nFiles = 0
    exitScript: "No .wav files found in folder."
endif

appendInfoLine: "Found ", nFiles, " file(s)"

if max_files_to_load > 0 and max_files_to_load < nFiles
    nFiles = max_files_to_load
    appendInfoLine: "Loading first ", nFiles, " file(s)"
endif

appendInfoLine: ""

loadCount = 0

# v1.3 (item 2): v1.2 tested `numberOfSelected("Sound") = 0` after a
# `nocheck Read from file`. That does not ask "did the read create
# something" - it asks "is any Sound selected right now". A Sound left
# selected by the previous iteration, or one the user had selected before
# running the script, satisfies it. A failed read then incremented
# loadCount and stored the OLD object id under sound_'loadCount', so the
# previous file's audio was analysed and concatenated in place of the one
# that failed - and cleanup would call removeObject on that same id twice.
# A disposable probe Sound is created before each read: if the read
# succeeded the probe is no longer the selected Sound, and if it failed
# the probe is exactly what is still selected.
for i from 1 to nFiles
    f$ = files$#[i]
    appendInfoLine: "[", i, "/", nFiles, "] ", f$
    
    Create Sound from formula: "tsb_probe", 1, 0, 0.01, 1000, "0"
    probe_id = selected("Sound")
    
    nocheck Read from file: directory$ + f$
    
    readOK = 1
    if numberOfSelected("Sound") <> 1
        readOK = 0
    else
        if selected("Sound") = probe_id
            readOK = 0
        endif
    endif
    
    if readOK = 0
        appendInfoLine: "    FAILED to load"
        removeObject: probe_id
    else
        s_id = selected("Sound")
        removeObject: probe_id
        selectObject: s_id
        
        loadCount = loadCount + 1
        name$ = selected$("Sound")
        nCh = Get number of channels
        
        if nCh > 1
            appendInfoLine: "    OK (stereo -> mono)"
            Convert to mono
            mono_id = selected("Sound")
            removeObject: s_id
            selectObject: mono_id
            Rename: name$
            sound_'loadCount' = mono_id
        else
            appendInfoLine: "    OK (mono)"
            sound_'loadCount' = s_id
        endif
        
        selectObject: sound_'loadCount'
        sr_'loadCount' = Get sampling frequency
        appendInfoLine: "    SR: ", sr_'loadCount', " Hz"
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Loaded: ", loadCount, " sounds"

if loadCount = 0
    exitScript: "No sounds were loaded successfully."
endif

number_of_sounds = loadCount

# ---------- Target sample rate ----------
# v1.3 (item 10): v1.2 adopted the sampling rate of whatever file loaded
# FIRST and resampled everything else to it, so an 8 kHz file at the top
# of the alphabet dragged the whole collection down - and merely renaming
# a file could change the result. Resampling is now deferred until every
# file is loaded, so the target can be chosen deliberately.
if target_sample_rate = 2
    targetSR = 0
    for i from 1 to number_of_sounds
        if sr_'i' > targetSR
            targetSR = sr_'i'
        endif
    endfor
    srDesc$ = "highest in collection"
elsif target_sample_rate = 3
    targetSR = 44100
    srDesc$ = "fixed"
elsif target_sample_rate = 4
    targetSR = 48000
    srDesc$ = "fixed"
else
    targetSR = sr_1
    srDesc$ = "first loaded file"
endif

appendInfoLine: "Target SR: ", targetSR, " Hz (", srDesc$, ")"

nResampled = 0
for i from 1 to number_of_sounds
    if sr_'i' <> targetSR
        selectObject: sound_'i'
        name$ = selected$("Sound")
        Resample: targetSR, 50
        resampled_id = selected("Sound")
        removeObject: sound_'i'
        selectObject: resampled_id
        Rename: name$
        sound_'i' = resampled_id
        nResampled = nResampled + 1
    endif
endfor
if nResampled > 0
    appendInfoLine: "Resampled: ", nResampled, " sound(s)"
endif

for i from 1 to number_of_sounds
    selectObject: sound_'i'
    sound_dur_'i' = Get total duration
endfor

# ========== STEP 2: MFCC ANALYSIS ==========
appendInfoLine: ""
appendInfoLine: "STEP 2: MFCC Analysis"
appendInfoLine: "---------------------"

analyzed = 0
failed_mfcc = 0

for i from 1 to number_of_sounds
    selectObject: sound_'i'
    name$ = selected$("Sound")
    
    dur = Get total duration
    
    if dur < minAnalysisDur
        appendInfoLine: "[", i, "] ", name$, " - SKIPPED (too short: ", fixed$(dur * 1000, 1), " ms)"
        failed_mfcc = failed_mfcc + 1
        mfcc_'i' = 0
        analyzed_'i' = 0
    else
        To MFCC: num_coefficients, window_length, time_step, 100, 100, 0.0
        mfcc_'i' = selected("MFCC")
        
        selectObject: mfcc_'i'
        nFrames = Get number of frames
        
        # v1.3 (item 4): v1.2 set analyzed_'i' = 1 as soon as an MFCC
        # object existed, without checking that it contained any frames.
        # A frameless MFCC produced an all-zero mean vector that then sat
        # at the origin of the feature space looking like a real timbre -
        # reintroducing exactly the problem v1.1's changelog set out to
        # solve. The coefficient-level validity check runs in STEP 3,
        # once the means are known.
        if nFrames < 1
            appendInfoLine: "[", i, "] ", name$, " - SKIPPED (MFCC has no frames)"
            failed_mfcc = failed_mfcc + 1
            removeObject: mfcc_'i'
            mfcc_'i' = 0
            analyzed_'i' = 0
        else
            appendInfoLine: "[", i, "] ", name$, " - ", nFrames, " frames"
            analyzed = analyzed + 1
            analyzed_'i' = 1
        endif
    endif
endfor

appendInfoLine: ""
# v1.4: this tally is provisional - the coefficient-level validity check
# in STEP 3 can still demote a sound counted here, which made the two
# numbers look contradictory against the later "Usable feature vectors"
# line. Labelled as provisional, with the final counts printed in STEP 3.
appendInfoLine: "MFCC objects created: ", analyzed, " | skipped: ", failed_mfcc, "  (provisional)"

if analyzed = 0
    exitScript: "No sounds were successfully analyzed."
endif

n = number_of_sounds

# ========== STEP 3: COMPUTE SIMILARITY ==========
appendInfoLine: ""
appendInfoLine: "STEP 3: Computing Similarity"
appendInfoLine: "----------------------------"

appendInfoLine: "Computing mean MFCC vectors..."

Create TableOfReal: "MFCC_Features", n, num_coefficients
featureTable = selected("TableOfReal")

for i from 1 to n
    selectObject: sound_'i'
    name$ = selected$("Sound")
    sound_name_'i'$ = name$
    
    if mfcc_'i' <> 0
        selectObject: mfcc_'i'
        nFrames = Get number of frames
        
        nDefinedCoefs = 0
        for coef from 1 to num_coefficients
            sum = 0
            count = 0
            
            selectObject: mfcc_'i'
            for frame from 1 to nFrames
                value = Get value in frame: frame, coef
                if value <> undefined
                    sum = sum + value
                    count = count + 1
                endif
            endfor
            
            if count > 0
                mean_value = sum / count
                nDefinedCoefs = nDefinedCoefs + 1
            else
                mean_value = 0
            endif
            
            selectObject: featureTable
            Set value: i, coef, mean_value
        endfor
        
        # v1.3 (item 4): a coefficient with no defined frame contributes a
        # fabricated 0 to the feature vector. If ANY coefficient is in
        # that state the vector is part-fabricated, so the sound is
        # demoted rather than compared against real timbres.
        if nDefinedCoefs < num_coefficients
            appendInfoLine: "  [", i, "] ", name$, " - DEMOTED (", num_coefficients - nDefinedCoefs, " coefficient(s) had no defined values)"
            analyzed_'i' = 0
            analyzed = analyzed - 1
            failed_mfcc = failed_mfcc + 1
            for coef from 1 to num_coefficients
                selectObject: featureTable
                Set value: i, coef, 0
            endfor
        endif
    endif
    
    selectObject: featureTable
    Set row label (index): i, name$
endfor

if analyzed = 0
    exitScript: "No sounds produced a usable MFCC feature vector."
endif

# ---------- Build the list of valid sounds ----------
nValid = 0
for i from 1 to n
    if analyzed_'i' = 1
        nValid = nValid + 1
        validIdx_'nValid' = i
    endif
endfor
appendInfoLine: "Usable feature vectors: ", nValid, " of ", n, "  (final: analyzed ", analyzed, ", skipped/demoted ", failed_mfcc, ")"

# ---------- Optional standardization (item 7) ----------
# v1.3: the raw mean-MFCC Euclidean distance weights each coefficient by
# its numeric range, so the low-order coefficients (which carry the
# largest values) dominate the metric. Standardizing per coefficient
# across the collection gives every dimension equal say. Raw remains the
# default so existing orderings are reproducible. Either way this is a
# GLOBAL AVERAGE timbre model: two files with the same mean MFCC but
# completely different timbral trajectories still come out near-identical.
if distance_metric = 2
    selectObject: featureTable
    for coef from 1 to num_coefficients
        cMean = 0
        for v from 1 to nValid
            vi = validIdx_'v'
            cv = Get value: vi, coef
            cMean = cMean + cv
        endfor
        cMean = cMean / nValid
        
        cVar = 0
        for v from 1 to nValid
            vi = validIdx_'v'
            cv = Get value: vi, coef
            cVar = cVar + (cv - cMean) * (cv - cMean)
        endfor
        cVar = cVar / nValid
        cStd = sqrt(cVar)
        if cStd < 1e-10
            cStd = 1e-10
        endif
        
        for v from 1 to nValid
            vi = validIdx_'v'
            cv = Get value: vi, coef
            Set value: vi, coef, (cv - cMean) / cStd
        endfor
    endfor
    metricDesc$ = "standardized mean MFCC"
    appendInfoLine: "Metric: standardized mean MFCC (per-coefficient z-score)"
else
    metricDesc$ = "raw mean MFCC"
    appendInfoLine: "Metric: raw mean MFCC"
endif

appendInfoLine: "Computing pairwise distances..."

Create TableOfReal: "Distance_Matrix", n, n
distMatrix = selected("TableOfReal")

for i from 1 to n
    selectObject: sound_'i'
    name$ = selected$("Sound")
    
    selectObject: distMatrix
    Set row label (index): i, name$
    Set column label (index): i, name$
endfor

maxDist = 0
for i from 1 to n
    for j from i to n
        dist = 0
        
        selectObject: featureTable
        for coef from 1 to num_coefficients
            val_i = Get value: i, coef
            val_j = Get value: j, coef
            diff = val_i - val_j
            dist = dist + diff * diff
        endfor
        
        dist = sqrt(dist)
        
        # v1.3 (item 5): maxDist used to be taken over the WHOLE matrix,
        # including rows for un-analyzable sounds whose feature vector is
        # an all-zero phantom - so the "real maximum" was often a distance
        # to a fabricated point. It is now taken over valid pairs only.
        if analyzed_'i' = 1 and analyzed_'j' = 1
            if dist > maxDist
                maxDist = dist
            endif
        endif
        
        selectObject: distMatrix
        Set value: i, j, dist
        Set value: j, i, dist
    endfor
endfor

appendInfoLine: "Max distance (valid pairs): ", fixed$(maxDist, 2)

# v1.3 (item 3 + 5): v1.2 overwrote every distance involving an
# un-analyzable sound with `penalty = maxDist + 1.0` and then built ONE
# nearest-neighbor path over valid and invalid sounds together. Two
# things went wrong. The path always began at sound 1, so if sound 1 was
# the un-analyzable one it appeared at the START of the path, not the end
# as the info line promised - and since all its distances were the same
# penalty, the second step fell back to index order rather than timbre.
# And the heatmap kept normalizing by the OLD maxDist, so a penalty cell
# gave intensity > 1 and colour components outside 0-1 (with maxDist = 0
# it gave intensity 0, painting the penalty cell as maximum similarity).
# There is no longer any penalty: the path is built over valid sounds
# only and the invalid ones are appended afterwards, in load order.
if nValid < n
    appendInfoLine: "  (", n - nValid, " un-analyzable sound(s) appended after the path, excluded from path statistics)"
endif

appendInfoLine: "Creating nearest-neighbor path..."

# ---------- Choose the start (item 6) ----------
# v1.3: v1.2 always started at sound 1, so renaming a file - or any
# change in the order the folder listing came back - could rewrite the
# whole path even though no audio had changed. The start is now a
# deliberate choice; "First file" reproduces v1.2.
if nValid = 1
    startValid = 1
    startDesc$ = "single valid sound"
elsif start_mode = 2
    bestSum = 1e30
    startValid = 1
    selectObject: distMatrix
    for v from 1 to nValid
        vi = validIdx_'v'
        sumD = 0
        for w from 1 to nValid
            wi = validIdx_'w'
            dvw = Get value: vi, wi
            sumD = sumD + dvw
        endfor
        if sumD < bestSum
            bestSum = sumD
            startValid = v
        endif
    endfor
    startDesc$ = "most central (medoid)"
elsif start_mode = 3
    bestSum = -1
    startValid = 1
    selectObject: distMatrix
    for v from 1 to nValid
        vi = validIdx_'v'
        sumD = 0
        for w from 1 to nValid
            wi = validIdx_'w'
            dvw = Get value: vi, wi
            sumD = sumD + dvw
        endfor
        if sumD > bestSum
            bestSum = sumD
            startValid = v
        endif
    endfor
    startDesc$ = "most isolated"
elsif start_mode = 4
    # Run the greedy walk from every valid start and keep the shortest.
    # Still not a globally optimal tour, but it removes the dependence on
    # which file happens to be listed first.
    bestTotal = 1e30
    startValid = 1
    for v0 from 1 to nValid
        for w from 1 to nValid
            tvisited_'w' = 0
        endfor
        tcur = v0
        tvisited_'v0' = 1
        tTotal = 0
        for tstep from 2 to nValid
            tBest = 1e30
            tNext = 0
            selectObject: distMatrix
            for w from 1 to nValid
                if tvisited_'w' = 0
                    wd = Get value: validIdx_'tcur', validIdx_'w'
                    if wd < tBest
                        tBest = wd
                        tNext = w
                    endif
                endif
            endfor
            if tNext > 0
                tTotal = tTotal + tBest
                tvisited_'tNext' = 1
                tcur = tNext
            endif
        endfor
        if tTotal < bestTotal
            bestTotal = tTotal
            startValid = v0
        endif
    endfor
    startDesc$ = "shortest greedy path (" + string$(nValid) + " starts tried)"
else
    startValid = 1
    startDesc$ = "first analyzable file"
endif

startIdx = validIdx_'startValid'
appendInfoLine: "Start: ", sound_name_'startIdx'$, "  [", startDesc$, "]"

# ---------- Greedy walk over valid sounds only ----------
path# = zero#(n)
pathValidLen = nValid

if nValid = 1
    path#[1] = validIdx_1
else
    for v from 1 to nValid
        vvisited_'v' = 0
    endfor
    current = startValid
    path#[1] = validIdx_'startValid'
    vvisited_'startValid' = 1

    for step from 2 to nValid
        min_dist = 1e30
        next_valid = 0
        
        selectObject: distMatrix
        for cand from 1 to nValid
            if vvisited_'cand' = 0
                dist = Get value: validIdx_'current', validIdx_'cand'
                if dist < min_dist
                    min_dist = dist
                    next_valid = cand
                endif
            endif
        endfor
        
        if next_valid > 0
            path#[step] = validIdx_'next_valid'
            vvisited_'next_valid' = 1
            current = next_valid
        endif
    endfor
endif

# ---------- Append un-analyzable sounds, in load order ----------
tailPos = nValid
for i from 1 to n
    if analyzed_'i' = 0
        tailPos = tailPos + 1
        path#[tailPos] = i
    endif
endfor

appendInfoLine: ""
appendInfoLine: "SIMILARITY PATH:"
appendInfoLine: ""

for i from 1 to n
    idx = path#[i]
    selectObject: sound_'idx'
    name$ = selected$("Sound")
    appendInfoLine: "  ", i, ". ", name$
endfor

# ========== STEP 4: CONCATENATE ==========
appendInfoLine: ""
appendInfoLine: "STEP 4: Concatenating"
appendInfoLine: "---------------------"

# Store cumulative positions for boundary visualization
cumulative_pos# = zero#(n + 1)
cumulative_pos#[1] = 0

# v1.3 (item 8): v1.2 used a bare `Concatenate`, so even timbrally
# adjacent files could click at the join from an instantaneous jump in
# phase or amplitude. Hard concatenation is kept as the default (it is a
# legitimate montage aesthetic), with fades and crossfade as options.
joinOverlap = 0

# v1.4 CRITICAL: Praat's `Concatenate` and `Concatenate with overlap`
# join the sounds in the order they appear in the OBJECT LIST, not the
# order they were selected. Selecting sound_'path#[1]' and then adding
# the rest with plusObject therefore had no effect on the result: the
# output came out in load order, so the computed similarity path never
# reached the audio at all. (This was true in v1.2 as well - the path
# was correct in the info window, the statistics and the visualization,
# while the waveform, its boundary markers and the un-analyzable tail
# were all in a different order.) Fresh copies are made here in path
# order; because they are created one after another they occupy the
# object list in exactly that order, and concatenating THEM is faithful.
# Fades are applied to the copies so the loaded originals stay pristine.
appendInfoLine: "Building sequence copies in path order..."
for i from 1 to n
    idx = path#[i]
    selectObject: sound_'idx'
    seqCopy_'i' = Copy: "seq_" + string$(i)
endfor

if join_mode = 2
    for i from 1 to n
        selectObject: seqCopy_'i'
        cStart = Get start time
        cEnd = Get end time
        cDur = cEnd - cStart
        fd = join_fade_s
        if fd > cDur / 2
            fd = cDur / 2
        endif
        if fd > 0
            nChOut = Get number of channels
            Formula (part): cStart, cStart + fd, 1, nChOut, "self * ((x - cStart) / fd)"
            Formula (part): cEnd - fd, cEnd, 1, nChOut, "self * ((cEnd - x) / fd)"
        endif
    endfor
    joinDesc$ = "short fades"
elsif join_mode = 3
    minDurAll = 1e30
    for i from 1 to n
        idx = path#[i]
        if sound_dur_'idx' < minDurAll
            minDurAll = sound_dur_'idx'
        endif
    endfor
    joinOverlap = join_fade_s
    if joinOverlap > minDurAll * 0.45
        joinOverlap = minDurAll * 0.45
    endif
    joinDesc$ = "crossfade (" + fixed$(joinOverlap * 1000, 1) + " ms overlap)"
else
    joinDesc$ = "hard concatenate"
endif

first_idx = path#[1]
selectObject: seqCopy_1

for i from 2 to n
    plusObject: seqCopy_'i'
endfor

if join_mode = 3 and n >= 2
    Concatenate with overlap: joinOverlap
else
    Concatenate
endif
outputSound = selected("Sound")
Rename: "Timbral_Similarity_" + presetName$

for i from 1 to n
    removeObject: seqCopy_'i'
endfor
selectObject: outputSound

# Boundary positions must account for the shortening that overlap causes.
cumulative_pos#[2] = sound_dur_'first_idx'
if join_mode = 3
    cumulative_pos#[2] = sound_dur_'first_idx' - joinOverlap
endif
for i from 2 to n
    idx = path#[i]
    cumulative_pos#[i + 1] = cumulative_pos#[i] + sound_dur_'idx'
    if join_mode = 3 and i < n
        cumulative_pos#[i + 1] = cumulative_pos#[i + 1] - joinOverlap
    endif
endfor

# v1.3 (item 9): `Scale peak: 0.99` is full normalization, not a limiter -
# a deliberately quiet collection was always pushed up to 0.99. Relative
# levels BETWEEN files are preserved either way, but the overall level of
# the output was never the composer's to decide. Normalize stays the
# default so v1.2 renders are reproducible.
if output_level = 1
    levelDesc$ = "preserved"
elsif output_level = 2
    peakMax = Get maximum: 0, 0, "None"
    peakMin = Get minimum: 0, 0, "None"
    peakAbs = peakMax
    if -peakMin > peakAbs
        peakAbs = -peakMin
    endif
    if peakAbs > 0.99
        Scale peak: 0.99
        levelDesc$ = "limited (peak was " + fixed$(peakAbs, 3) + ")"
    else
        levelDesc$ = "unchanged (peak " + fixed$(peakAbs, 3) + ")"
    endif
else
    Scale peak: 0.99
    levelDesc$ = "normalized to 0.99"
endif

totalDur = Get total duration
appendInfoLine: "Output duration: ", fixed$(totalDur, 2), " s  (join: ", joinDesc$, ", level: ", levelDesc$, ")"

# Compute path distances and total path length
# v1.3 (item 3): statistics cover the VALID segment only. The appended
# un-analyzable sounds have no meaningful distance to anything, so
# including them would have been averaging in a sentinel.
totalPathLength = 0
maxPathDist = 0
meanPathDist = 0
nPathSteps = 0

if nValid > 1
    nPathSteps = nValid - 1
    pathDist# = zero#(nPathSteps)
    for i from 1 to nPathSteps
        idx1 = path#[i]
        idx2 = path#[i + 1]
        selectObject: distMatrix
        d = Get value: idx1, idx2
        pathDist#[i] = d
        totalPathLength = totalPathLength + d
        if d > maxPathDist
            maxPathDist = d
        endif
    endfor
    meanPathDist = totalPathLength / nPathSteps
    appendInfoLine: "Total path length: ", fixed$(totalPathLength, 2), "  (over ", nValid, " analyzable sounds)"
    appendInfoLine: "Mean step distance: ", fixed$(meanPathDist, 3)
else
    appendInfoLine: "Fewer than 2 analyzable sounds: no path distances."
endif

# ========== VISUALIZATION ==========
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    
    # === Title ===
    # v1.3: the subtitle used axis y = -1 inside a 0-0.5 inch title
    # viewport, which mapped to outer y = 1.0 inches - inside the Output
    # Waveform panel (outer 0.6-1.9), so it was drawn over the waveform.
    # It was also placed at x = 0.2 with "centre" alignment, off-centre
    # against the title above it. Same fix as Self_Attention_Recomposer
    # v1.1: taller title viewport, subtitle just above the first panel.
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Timbral Similarity Browser##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.22, "half", presetName$ + " | " + string$(n) + " sounds (" + string$(nValid) + " analyzable) | " + string$(num_coefficients) + " MFCCs | " + metricDesc$
    
    # === Output Waveform with Boundaries ===
    Select outer viewport: 0, 8, 0.6, 1.9
    Select inner viewport: 0.6, 7.7, 0.75, 1.8
    
    selectObject: outputSound
    Colour: "{0.4, 0.55, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Draw sound boundaries
    Colour: "{0.8, 0.5, 0.4}"
    Dashed line
    for i from 2 to n
        boundaryTime = cumulative_pos#[i]
        Draw line: boundaryTime, -0.95, boundaryTime, 0.95
    endfor
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Concatenated (" + fixed$(totalDur, 2) + " s) - dashed lines = boundaries"
    
    # === Distance Matrix Heatmap ===
    if n <= 20
        Select outer viewport: 0, 4, 2.0, 4.3
        Select inner viewport: 0.6, 3.7, 2.2, 4.1
        
        Axes: 0, n, 0, n
        
        for i from 1 to n
            for j from 1 to n
                selectObject: distMatrix
                dist = Get value: i, j
                
                # v1.3 (item 5): cells involving an un-analyzable sound
                # are not distances in the timbral space at all - their
                # feature row is a fabricated zero vector. They are drawn
                # in neutral grey instead of being coloured on the
                # similarity scale, and real distances are clamped to
                # 0-1 so the colour formulas stay in range.
                if analyzed_'i' = 0 or analyzed_'j' = 0
                    rVal = 0.85
                    gVal = 0.85
                    bVal = 0.85
                else
                    if maxDist > 0
                        intensity = dist / maxDist
                    else
                        intensity = 0
                    endif
                    if intensity < 0
                        intensity = 0
                    endif
                    if intensity > 1
                        intensity = 1
                    endif
                    
                    # Blue (similar) to Orange (different)
                    rVal = 0.3 + intensity * 0.5
                    gVal = 0.5 - intensity * 0.2
                    bVal = 0.7 - intensity * 0.4
                endif
                
                rVal$ = fixed$(rVal, 2)
                gVal$ = fixed$(gVal, 2)
                bVal$ = fixed$(bVal, 2)
                
                Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", i - 1, i, n - j, n - j + 1
            endfor
        endfor
        
        # Highlight path on matrix (valid segment only)
        Colour: "{0.9, 0.3, 0.3}"
        Line width: 2
        for i from 1 to nValid - 1
            idx1 = path#[i]
            idx2 = path#[i + 1]
            x1 = idx1 - 0.5
            y1 = n - idx1 + 0.5
            x2 = idx2 - 0.5
            y2 = n - idx2 + 0.5
            Draw line: x1, y1, x2, y2
        endfor
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Sound #"
        Text bottom: "no", "Sound #"
        Text top: "no", "Distance Matrix (red = path, grey = un-analyzable)"
    else
        # Too many sounds - show message
        Select outer viewport: 0, 4, 2.0, 4.3
        Select inner viewport: 0.6, 3.7, 2.2, 4.1
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
        Font size: 9
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "Distance matrix too large to display"
        Text: 0.5, "centre", 0.3, "half", "(" + string$(n) + " × " + string$(n) + " = " + string$(n*n) + " cells)"
        Colour: "Black"
        Draw inner box
    endif
    
    # === Path Distances ===
    Select outer viewport: 4, 8, 2.0, 4.3
    Select inner viewport: 4.4, 7.7, 2.2, 4.1
    
    if maxPathDist < 0.1
        maxPathDist = 1
    endif
    
    Axes: 0, n, 0, maxPathDist * 1.15
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, n, 0, maxPathDist * 1.15
    
    # Mean line
    Colour: "{0.8, 0.8, 0.8}"
    Dashed line
    Draw line: 0, meanPathDist, n, meanPathDist
    Solid line
    
    # Draw path distances as bars (valid segment only)
    for i from 1 to nPathSteps
        intensity = pathDist#[i] / maxPathDist
        rVal = 0.4 + intensity * 0.4
        gVal = 0.65 - intensity * 0.25
        bVal = 0.5 - intensity * 0.2
        rVal$ = fixed$(rVal, 2)
        gVal$ = fixed$(gVal, 2)
        bVal$ = fixed$(bVal, 2)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", i - 0.35, i + 0.35, 0, pathDist#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Distance"
    Text bottom: "no", "Step"
    Text top: "no", "Path Distances (mean=" + fixed$(meanPathDist, 2) + ")"
    
    # === Path Sequence ===
    Select outer viewport: 0, 8, 4.4, 5.8
    Select inner viewport: 0.6, 7.7, 4.55, 5.7
    
    Axes: 0, n + 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, n + 1, 0, 1
    
    Font size: 5
    Colour: "{0.3, 0.3, 0.4}"
    
    # Show path sequence (truncate names if needed)
    maxNameLen = 12
    for i from 1 to n
        idx = path#[i]
        name$ = sound_name_'idx'$
        if length(name$) > maxNameLen
            name$ = left$(name$, maxNameLen - 2) + ".."
        endif
        
        # Alternate colors for readability; appended un-analyzable
        # sounds are shown in grey so the path proper is legible.
        if i > nValid
            Paint rectangle: "{0.88, 0.88, 0.88}", i - 0.45, i + 0.45, 0.15, 0.85
        elsif i mod 2 = 0
            Paint rectangle: "{0.92, 0.94, 0.96}", i - 0.45, i + 0.45, 0.15, 0.85
        else
            Paint rectangle: "{0.96, 0.94, 0.92}", i - 0.45, i + 0.45, 0.15, 0.85
        endif
        
        Colour: "{0.2, 0.2, 0.3}"
        Text: i, "centre", 0.5, "half", string$(i) + ":" + name$
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Similarity Path: Start → Most Similar → ... → End   (grey = un-analyzable, appended)"
    
    # === Summary Stats ===
    Select outer viewport: 0, 8, 5.9, 6.5
    Axes: 0, 1, 0, 1
    
    Paint rectangle: "{0.95, 0.97, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.3, 0.3, 0.4}"
    
    Text: 0.10, "centre", 0.72, "half", "Sounds: " + string$(n) + " (" + string$(nValid) + " ok)"
    Text: 0.30, "centre", 0.72, "half", "MFCCs: " + string$(num_coefficients)
    Text: 0.50, "centre", 0.72, "half", "Max dist: " + fixed$(maxDist, 2)
    Text: 0.70, "centre", 0.72, "half", "Path length: " + fixed$(totalPathLength, 2)
    Text: 0.89, "centre", 0.72, "half", "Duration: " + fixed$(totalDur, 1) + "s"
    
    Text: 0.10, "centre", 0.28, "half", "SR: " + string$(targetSR) + " Hz"
    Text: 0.30, "centre", 0.28, "half", "Start: " + startDesc$
    Text: 0.58, "centre", 0.28, "half", "Join: " + joinDesc$
    Text: 0.85, "centre", 0.28, "half", "Level: " + levelDesc$
    
    Colour: "Black"
    Draw inner box
    Font size: 10
endif

# ========== CLEANUP ==========
appendInfoLine: ""
appendInfoLine: "STEP 5: Cleanup"
appendInfoLine: "---------------"

for i from 1 to n
    removeObject: sound_'i'
    if mfcc_'i' <> 0
        removeObject: mfcc_'i'
    endif
endfor

removeObject: featureTable, distMatrix

appendInfoLine: "Cleanup complete!"

# ========== OUTPUT ==========
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(totalDur, 2), " s"
appendInfoLine: "Total path length: ", fixed$(totalPathLength, 2)

if auto_play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    selectObject: outputSound
    Play
endif

selectObject: outputSound