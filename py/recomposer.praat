# ============================================================
# Praat AudioTools - recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CNN Event Recomposer — Morphological Compositional Engine
#
#   An event-based acoustic recomposition system for Praat.
#   The script automatically segments a selected Sound into
#   events, extracts feature trajectories, and sends them to
#   a self-supervised CNN engine in Python.
#
#   The CNN learns a latent morphology space of events,
#   clusters them, computes dramaturgical scores, and returns
#   a montage plan.
#
#   Praat then reassembles the original audio by cutting and
#   concatenating events in the new order (no pitch
#   manipulation or spectral processing).
#
#   The system functions as a structural AI engine for
#   event-based acoustic form.
#
# Citation:
#   Cohen, S. (2026). CNN Event Recomposer:
#   Event-Based Morphological Recomposition in Praat.
#   Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

form Recomposer — CNN Event Recomposition
    optionmenu Compositional_form: 1
        option sorted
        option braid
        option phase
        option walk
    real Silence_threshold_db -25
    real Min_event_dur_s 0.03
    real Pitch_floor_hz 60
    real Pitch_ceiling_hz 600
    real Fade_ms 5
    boolean Play_result 1
endform

# ============================================================
# CONFIGURATION — fixed defaults
# ============================================================

python_cmd$         = "python3"
frame_step_s        = 0.01
min_silence_dur_s   = 0.08
min_sound_dur_s     = 0.04

# Map form variables to internal names
silence_threshold_db  = silence_threshold_db
min_event_dur_s       = min_event_dur_s
pitch_floor_hz        = pitch_floor_hz
pitch_ceiling_hz      = pitch_ceiling_hz
fade_ms               = fade_ms

if compositional_form = 1
    compositional_form$ = "sorted"
elsif compositional_form = 2
    compositional_form$ = "braid"
elsif compositional_form = 3
    compositional_form$ = "phase"
else
    compositional_form$ = "walk"
endif

# ============================================================
# PATHS
# ============================================================

pluginDir$       = preferencesDirectory$ + "/plugin_AudioTools/"
inputEventsCsv$  = pluginDir$ + "recomposer_input_events.csv"
outputPlanCsv$   = pluginDir$ + "recomposer_output_plan.csv"
pythonScript$    = pluginDir$ + "py/recomposer.py"

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSound    = selected("Sound")
origName$    = selected$("Sound")
nChannels    = Get number of channels
isStereo     = (nChannels = 2)

clearinfo
writeInfoLine:  "=== Recomposer — CNN Event Recomposition ==="
appendInfoLine: "Sound:   ", origName$
appendInfoLine: "Stereo:  ", string$(isStereo)
appendInfoLine: ""

# ============================================================
# MONO MIX FOR ANALYSIS ONLY
# ============================================================

selectObject: origSound
if isStereo
    monoSound = Convert to mono
    appendInfoLine: "Created mono mix for analysis."
else
    monoSound = origSound
endif

selectObject: monoSound
dur = Get total duration
sr  = Get sampling frequency
appendInfoLine: "Duration: ", fixed$(dur, 3), " s  |  SR: ", sr, " Hz"
appendInfoLine: ""

# ============================================================
# STAGE 1: Intensity + silence-based TextGrid segmentation
# ============================================================

appendInfoLine: "--- Stage 1: Segmentation ---"

selectObject: monoSound
intensityObj = To Intensity: pitch_floor_hz, frame_step_s, "yes"
appendInfoLine: "Intensity computed."

selectObject: intensityObj
tgSilences = To TextGrid (silences): silence_threshold_db,
    ... min_silence_dur_s, min_sound_dur_s, "silent", "sounding"
appendInfoLine: "Silence TextGrid created."

# Rename the tier to "events" (Praat names it differently by default)
selectObject: tgSilences
Set tier name: 1, "events"

# Collect sounding intervals
nIntervals = Get number of intervals: 1
nEvents    = 0
event_start#  = zero# (200)
event_end#    = zero# (200)

for iInt from 1 to nIntervals
    label$ = Get label of interval: 1, iInt
    if label$ = "sounding"
        iStart = Get start time of interval: 1, iInt
        iEnd   = Get end time of interval:   1, iInt
        evDur  = iEnd - iStart
        if evDur >= min_event_dur_s
            nEvents = nEvents + 1
            event_start# [nEvents] = iStart
            event_end#   [nEvents] = iEnd
        endif
    endif
endfor

appendInfoLine: "Events found: ", nEvents

if nEvents = 0
    removeObject: intensityObj, tgSilences
    if isStereo
        removeObject: monoSound
    endif
    exitScript: "No sound events detected. Try lowering silence_threshold_db."
endif

# ============================================================
# STAGE 2: Feature extraction → input_events.csv
# ============================================================

appendInfoLine: ""
appendInfoLine: "--- Stage 2: Feature Extraction ---"

# Compute pitch and HNR once for the full file
selectObject: monoSound
pitchObj = To Pitch (ac): frame_step_s, pitch_floor_hz, 15, "no",
    ... 0.03, 0.45, 0.01, 0.35, 0.14, pitch_ceiling_hz

selectObject: monoSound
hnrObj = To Harmonicity (cc): 0.01, pitch_floor_hz, 0.1, 1.0

appendInfoLine: "Pitch and HNR objects computed."

# Write CSV header
deleteFile: inputEventsCsv$
header$ = "event_id,start_time_s,end_time_s,duration_s,"
    ... + "pitch_seq_hz,intensity_seq_db,hnr_seq_db,voiced_seq,"
    ... + "spectral_centroid_seq_hz,spectral_spread_seq_hz,zcr_seq"
fileappend 'inputEventsCsv$' 'header$''newline$'

for iEv from 1 to nEvents
    evStart = event_start# [iEv]
    evEnd   = event_end#   [iEv]
    evDur   = evEnd - evStart

    # Number of frames for this event
    nFrames = floor(evDur / frame_step_s)
    if nFrames < 2
        nFrames = 2
    endif

    # Build feature sequences
    pitch_seq$       = ""
    intensity_seq$   = ""
    hnr_seq$         = ""
    voiced_seq$      = ""
    centroid_seq$    = ""
    spread_seq$      = ""
    zcr_seq$         = ""

    for iFrame from 1 to nFrames
        t = evStart + (iFrame - 1) * frame_step_s

        # Clamp to event bounds
        if t > evEnd
            t = evEnd
        endif

        # Pitch
        selectObject: pitchObj
        p = Get value at time: t, "Hertz", "Linear"
        if p = undefined
            p = 0
        endif

        # Voiced flag
        v = 0
        if p > 0
            v = 1
        endif

        # Intensity
        selectObject: intensityObj
        inten = Get value at time: t, "Cubic"
        if inten = undefined
            inten = 0
        endif

        # HNR
        selectObject: hnrObj
        h = Get value at time: t, "Linear"
        if h = undefined
            h = 0
        endif

        # Spectral centroid (centre of gravity)
        tWin1 = t - frame_step_s / 2
        tWin2 = t + frame_step_s / 2
        if tWin1 < 0
            tWin1 = 0
        endif
        if tWin2 > dur
            tWin2 = dur
        endif
        centroid = 0
        sp_spread = 0
        if tWin2 > tWin1 + 0.001
            selectObject: monoSound
            snippetSound = Extract part: tWin1, tWin2, "Hanning", 1, "no"
            snippetSpec  = To Spectrum: "yes"
            centroid     = Get centre of gravity: 2
            sp_spread    = Get standard deviation: 2
            if centroid = undefined
                centroid = 0
            endif
            if sp_spread = undefined
                sp_spread = 0
            endif
            removeObject: snippetSound, snippetSpec
        endif

        # Zero crossing rate: count sign changes across snippet frames
        zcr_val = 0
        if tWin2 > tWin1 + 0.001
            nZcrFrames = 8
            prevSample = 0
            nCrossings = 0
            for iZ from 1 to nZcrFrames
                tZ = tWin1 + (iZ - 1) * (tWin2 - tWin1) / nZcrFrames
                selectObject: monoSound
                sZ = Get value at time: 1, tZ, "Sinc70"
                if sZ = undefined
                    sZ = 0
                endif
                if iZ > 1
                    if (prevSample > 0 and sZ < 0) or (prevSample < 0 and sZ > 0)
                        nCrossings = nCrossings + 1
                    endif
                endif
                prevSample = sZ
            endfor
            zcr_val = nCrossings / nZcrFrames
        endif

        # Append to sequences (semicolon-separated)
        if iFrame = 1
            pitch_seq$       = fixed$(p,         3)
            intensity_seq$   = fixed$(inten,     3)
            hnr_seq$         = fixed$(h,         3)
            voiced_seq$      = string$(v)
            centroid_seq$    = fixed$(centroid,  2)
            spread_seq$      = fixed$(sp_spread, 2)
            zcr_seq$         = fixed$(zcr_val,   4)
        else
            pitch_seq$       = pitch_seq$       + ";" + fixed$(p,         3)
            intensity_seq$   = intensity_seq$   + ";" + fixed$(inten,     3)
            hnr_seq$         = hnr_seq$         + ";" + fixed$(h,         3)
            voiced_seq$      = voiced_seq$      + ";" + string$(v)
            centroid_seq$    = centroid_seq$    + ";" + fixed$(centroid,  2)
            spread_seq$      = spread_seq$      + ";" + fixed$(sp_spread, 2)
            zcr_seq$         = zcr_seq$         + ";" + fixed$(zcr_val,   4)
        endif
    endfor

    # Write row (quote sequence fields to be safe)
    row$ = string$(iEv) + ","
        ... + fixed$(evStart, 6) + ","
        ... + fixed$(evEnd,   6) + ","
        ... + fixed$(evDur,   6) + ","
        ... + """" + pitch_seq$       + ""","
        ... + """" + intensity_seq$   + ""","
        ... + """" + hnr_seq$         + ""","
        ... + """" + voiced_seq$      + ""","
        ... + """" + centroid_seq$    + ""","
        ... + """" + spread_seq$      + ""","
        ... + """" + zcr_seq$         + """"
    fileappend 'inputEventsCsv$' 'row$''newline$'

    if iEv mod 10 = 0
        appendInfoLine: "  Extracted event ", iEv, " / ", nEvents
    endif
endfor

appendInfoLine: "  Wrote: ", inputEventsCsv$

# ============================================================
# STAGE 3: Call Python
# ============================================================

appendInfoLine: ""
appendInfoLine: "--- Stage 3: Running Python CNN engine ---"
appendInfoLine: "  Form: ", compositional_form$

# Auto-detect Python executable
probeMarker$ = pluginDir$ + "temp_recomposer_probe.ok"

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

detectedCmd$ = ""
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
    probeCode$ = "import sys; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"
    if fileReadable(probeMarker$)
        detectedCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", detectedCmd$
    endif
    if detectedCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if detectedCmd$ = ""
    exitScript: "Cannot find Python 3. Tried: python3, python, py. Please add Python to PATH."
endif

deleteFile: outputPlanCsv$
pythonLogFile$ = pluginDir$ + "temp_recomposer_python.log"
deleteFile: pythonLogFile$

if windows
    runSystem: detectedCmd$ + " """ + pythonScript$ + """"
        ... + " """ + inputEventsCsv$ + """"
        ... + " """ + outputPlanCsv$ + """"
        ... + " --form " + compositional_form$
        ... + " 2> """ + pythonLogFile$ + """"
else
    runSystem: detectedCmd$ + " """ + pythonScript$ + """"
        ... + " """ + inputEventsCsv$ + """"
        ... + " """ + outputPlanCsv$ + """"
        ... + " --form " + compositional_form$
        ... + " 2> """ + pythonLogFile$ + """"
endif

if not fileReadable(outputPlanCsv$)
    exitScript: "Python engine failed — output_plan.csv not found." + newline$
        ... + "Expected: " + outputPlanCsv$ + newline$
        ... + "Run manually to see error:" + newline$
        ... + "  " + detectedCmd$ + " " + pythonScript$
        ... + " """ + inputEventsCsv$ + """"
        ... + " """ + outputPlanCsv$ + """"
endif

appendInfoLine: "  Python engine completed."

# Print Python log (contains walk traversal + CNN progress) to Info
if fileReadable(pythonLogFile$)
    Read Strings from raw text file: pythonLogFile$
    pyLogStrings = selected("Strings")
    nLogLines = Get number of strings
    for iLog from 1 to nLogLines
        selectObject: pyLogStrings
        logLine$ = Get string: iLog
        appendInfoLine: "  ", logLine$
    endfor
    removeObject: pyLogStrings
    deleteFile: pythonLogFile$
endif

# ============================================================
# STAGE 4: Read output_plan.csv
# ============================================================

appendInfoLine: ""
appendInfoLine: "--- Stage 4: Reading montage plan ---"

Read Strings from raw text file: outputPlanCsv$
planStrings = selected("Strings")
nPlanLines  = Get number of strings

# Store plan rows
nPlan = 0
plan_newIdx#    = zero# (500)
plan_evId#      = zero# (500)
plan_start#     = zero# (500)
plan_end#       = zero# (500)
plan_cluster#   = zero# (500)
plan_morph#     = zero# (500)
plan_embNorm#   = zero# (500)

for iLine from 2 to nPlanLines
    selectObject: planStrings
    rowStr$ = Get string: iLine
    rowStr$ = replace$(rowStr$, " ", "", 0)
    if rowStr$ <> ""
        # Parse CSV: new_index,orig_event_id,orig_start,orig_end,
        #            cluster_id,morph_score,emb_norm
        # Extract fields by successive comma finds
        remain$ = rowStr$

        # field 1: new_index
        cp = index(remain$, ",")
        f1$ = left$(remain$, cp - 1)
        remain$ = mid$(remain$, cp + 1, length(remain$))

        # field 2: orig_event_id
        cp = index(remain$, ",")
        f2$ = left$(remain$, cp - 1)
        remain$ = mid$(remain$, cp + 1, length(remain$))

        # field 3: orig_start_time_s
        cp = index(remain$, ",")
        f3$ = left$(remain$, cp - 1)
        remain$ = mid$(remain$, cp + 1, length(remain$))

        # field 4: orig_end_time_s
        cp = index(remain$, ",")
        f4$ = left$(remain$, cp - 1)
        remain$ = mid$(remain$, cp + 1, length(remain$))

        # field 5: cluster_id
        cp = index(remain$, ",")
        f5$ = left$(remain$, cp - 1)
        remain$ = mid$(remain$, cp + 1, length(remain$))

        # field 6: morph_score
        cp = index(remain$, ",")
        f6$ = left$(remain$, cp - 1)
        f7$ = mid$(remain$, cp + 1, length(remain$))

        nPlan = nPlan + 1
        plan_newIdx#  [nPlan] = number(f1$)
        plan_evId#    [nPlan] = number(f2$)
        plan_start#   [nPlan] = number(f3$)
        plan_end#     [nPlan] = number(f4$)
        plan_cluster# [nPlan] = number(f5$)
        plan_morph#   [nPlan] = number(f6$)
        plan_embNorm# [nPlan] = number(f7$)
    endif
endfor
removeObject: planStrings

appendInfoLine: "  Montage plan: ", nPlan, " events"

# ============================================================
# STAGE 5: Assemble recomposed sound
# ============================================================

appendInfoLine: ""
appendInfoLine: "--- Stage 5: Assembling recomposed sound ---"

fade_s = fade_ms / 1000

# Extract and store all chunks; preserve stereo
chunkIds# = zero# (nPlan)

for iRow from 1 to nPlan
    chunkStart = plan_start# [iRow]
    chunkEnd   = plan_end#   [iRow]

    # Safety clamp
    if chunkStart < 0
        chunkStart = 0
    endif
    if chunkEnd > dur
        chunkEnd = dur
    endif
    if chunkEnd <= chunkStart
        chunkEnd = chunkStart + 0.001
    endif

    # Extract from original sound (stereo-safe)
    selectObject: origSound
    chunk = Extract part: chunkStart, chunkEnd, "rectangular", 1, "no"
    chunkDur = Get total duration

    # Fade in / out
    if chunkDur > fade_s * 2.5
        Fade in:  0, 0,                  fade_s, "yes"
        Fade out: 0, chunkDur - fade_s,  fade_s, "yes"
    endif

    chunkIds# [iRow] = chunk
endfor

# Concatenate all chunks
selectObject: chunkIds# [1]
for iRow from 2 to nPlan
    plusObject: chunkIds# [iRow]
endfor
Concatenate

recomposedSound = selected("Sound")
Rename: origName$ + "_recomposed_CNN"

# Remove chunk objects
for iRow from 1 to nPlan
    removeObject: chunkIds# [iRow]
endfor

appendInfoLine: "  Recomposed sound: ", origName$, "_recomposed_CNN"

# ============================================================
# STAGE 6: Visualization
# ============================================================

appendInfoLine: ""
appendInfoLine: "--- Stage 6: Visualization ---"

# ── A. Build cluster-labelled TextGrid for the recomposed sound ──────────────

selectObject: recomposedSound
recompDur = Get total duration

Create TextGrid: 0, recompDur, "clusters", ""
recompTG = selected("TextGrid")

# Fill cluster tier with boundaries
cursorTime = 0
for iRow from 1 to nPlan
    chunkStart  = plan_start#   [iRow]
    chunkEnd    = plan_end#     [iRow]
    chunkDur    = chunkEnd - chunkStart
    clustId     = round(plan_cluster# [iRow])
    morphScore  = plan_morph# [iRow]

    endTime = cursorTime + chunkDur
    if endTime > recompDur
        endTime = recompDur
    endif

    selectObject: recompTG
    if iRow < nPlan
        Insert boundary: 1, endTime
    endif

    # Label interval with cluster ID
    selectObject: recompTG
    nBounds = Get number of intervals: 1
    for iBound from 1 to nBounds
        bStart = Get start time of interval: 1, iBound
        bEnd   = Get end time of interval:   1, iBound
        bMid   = (bStart + bEnd) / 2
        if bMid >= cursorTime and bMid < endTime
            Set interval text: 1, iBound, "C" + string$(clustId)
        endif
    endfor

    cursorTime = endTime
endfor

appendInfoLine: "  Cluster TextGrid created."

# ── B. Summary Table ──────────────────────────────────────────────────────────

Create Table with column names: "recomposer_summary", nPlan,
    ... "new_index orig_event_id cluster_id morphology_score embedding_norm"
summaryTable = selected("Table")

for iRow from 1 to nPlan
    Set numeric value: iRow, "new_index",         plan_newIdx#  [iRow]
    Set numeric value: iRow, "orig_event_id",      plan_evId#    [iRow]
    Set numeric value: iRow, "cluster_id",         plan_cluster# [iRow]
    Set numeric value: iRow, "morphology_score",   plan_morph#   [iRow]
    Set numeric value: iRow, "embedding_norm",     plan_embNorm# [iRow]
endfor

appendInfoLine: "  Summary Table created."

# ── C. Picture window: waveform + cluster timeline ───────────────────────────

Erase all
Select outer viewport: 0, 8, 0, 7

# Title
Select outer viewport: 0, 8, 0, 0.45
Axes: 0, 1, 0, 1
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.6, "half", "##Recomposer — CNN Event Recomposition##"
Font size: 8
Colour: "{0.35, 0.35, 0.45}"
Text: 0.5, "centre", -1.2, "half", origName$ + "  |  events: " + string$(nEvents)
    ... + "  |  clusters: " + string$(round(plan_cluster# [nPlan]) + 1)

# Original waveform with event boundaries
Select outer viewport: 0, 8, 0.55, 1.55
Select inner viewport: 0.6, 7.7, 0.60, 1.50
selectObject: origSound
Colour: "{0.50, 0.50, 0.55}"
Draw: 0, 0, 0, 0, "no", "Curve"
Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Original"
Text top:  "no", "Original sound  +  event boundaries"
Axes: 0, dur, -1, 1
Colour: "{0.75, 0.35, 0.35}"
Line width: 1
for iEv from 1 to nEvents
    evT = event_start# [iEv]
    if evT > 0 and evT < dur
        Draw line: evT, -0.85, evT, 0.85
    endif
endfor
Line width: 1

# Recomposed waveform
Select outer viewport: 0, 8, 1.60, 2.60
Select inner viewport: 0.6, 7.7, 1.65, 2.55
selectObject: recomposedSound
Colour: "{0.20, 0.45, 0.75}"
Draw: 0, 0, 0, 0, "no", "Curve"
Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Recomp."
Text bottom: "yes", "Time (s)"

# Cluster timeline: coloured bars over recomposed duration
Select outer viewport: 0, 8, 2.70, 3.55
Select inner viewport: 0.6, 7.7, 2.75, 3.50
Axes: 0, recompDur, 0, 1
Paint rectangle: "{0.96, 0.96, 0.98}", 0, recompDur, 0, 1

# Determine number of distinct clusters
maxClust = 0
for iRow from 1 to nPlan
    c = round(plan_cluster# [iRow])
    if c > maxClust
        maxClust = c
    endif
endfor
nClusters = maxClust + 1

# Cluster colours (up to 6)
# Store as triplets: r_1, g_1, b_1, r_2, ...
clustR# = { 0.85, 0.25, 0.15, 0.55, 0.75, 0.45 }
clustG# = { 0.35, 0.65, 0.70, 0.20, 0.65, 0.45 }
clustB# = { 0.20, 0.30, 0.80, 0.75, 0.25, 0.80 }

cursorTime = 0
for iRow from 1 to nPlan
    chunkStart = plan_start#   [iRow]
    chunkEnd   = plan_end#     [iRow]
    chunkDur   = chunkEnd - chunkStart
    cid        = round(plan_cluster# [iRow]) + 1
    if cid < 1
        cid = 1
    endif
    if cid > 6
        cid = 6
    endif
    endTime = cursorTime + chunkDur
    colStr$ = "{" + string$(clustR# [cid]) + "," + string$(clustG# [cid]) + "," + string$(clustB# [cid]) + "}"
    Paint rectangle: colStr$, cursorTime, endTime, 0.05, 0.95
    cursorTime = endTime
endfor

# Cluster labels in the bar
Font size: 7
cursorTime = 0
for iRow from 1 to nPlan
    chunkStart = plan_start#   [iRow]
    chunkEnd   = plan_end#     [iRow]
    chunkDur   = chunkEnd - chunkStart
    cid        = round(plan_cluster# [iRow])
    endTime    = cursorTime + chunkDur
    midTime    = (cursorTime + endTime) / 2
    if chunkDur > recompDur * 0.04
        Colour: "White"
        Text: midTime, "centre", 0.5, "half", "C" + string$(cid)
    endif
    cursorTime = endTime
endfor
Colour: "Black"
Draw inner box
Font size: 7
Text left:   "yes", "Cluster"
Text bottom: "yes", "Recomposed time (s)"
Text top:    "no",  "Cluster timeline  (sorted by morphology score)"

# Morphology score bar chart (one bar per cluster)
Select outer viewport: 0, 8, 3.65, 4.90
Select inner viewport: 0.6, 7.7, 3.75, 4.80
Axes: -0.5, nClusters - 0.5, 0, 1.15

Paint rectangle: "{0.96, 0.96, 0.98}", -0.5, nClusters - 0.5, 0, 1.15

for cid from 0 to nClusters - 1
    # Find morphology score for this cluster
    morphVal = 0
    for iRow from 1 to nPlan
        if round(plan_cluster# [iRow]) = cid
            morphVal = plan_morph# [iRow]
            iRow     = nPlan + 1
        endif
    endfor
    cidArr = cid + 1
    if cidArr < 1
        cidArr = 1
    endif
    if cidArr > 6
        cidArr = 6
    endif
    colStr$ = "{" + string$(clustR# [cidArr]) + "," + string$(clustG# [cidArr]) + "," + string$(clustB# [cidArr]) + "}"
    Paint rectangle: colStr$, cid - 0.35, cid + 0.35, 0, morphVal
    Colour: "Black"
    Font size: 7
    Text: cid, "centre", morphVal + 0.06, "half", fixed$(morphVal, 2)
    Text: cid, "centre", -0.08, "half", "C" + string$(cid)
endfor

Colour: "Black"
Line width: 1
Draw inner box
Font size: 7
Text left:   "yes", "Score"
Text top:    "no",  "Cluster morphology scores  (CNN-derived)"
Text bottom: "yes", "Cluster"

# Embedding norm scatter (event index vs norm, coloured by cluster)
Select outer viewport: 0, 8, 5.00, 6.15
Select inner viewport: 0.6, 7.7, 5.10, 6.05

# Find norm range
normMin = plan_embNorm# [1]
normMax = plan_embNorm# [1]
for iRow from 1 to nPlan
    if plan_embNorm# [iRow] < normMin
        normMin = plan_embNorm# [iRow]
    endif
    if plan_embNorm# [iRow] > normMax
        normMax = plan_embNorm# [iRow]
    endif
endfor
normRange = normMax - normMin
if normRange < 0.01
    normRange = 1
endif

Axes: 0, nPlan + 1, normMin - normRange * 0.1, normMax + normRange * 0.15
Paint rectangle: "{0.96, 0.96, 0.98}", 0, nPlan + 1, normMin - normRange * 0.1, normMax + normRange * 0.15

for iRow from 1 to nPlan
    cid    = round(plan_cluster# [iRow]) + 1
    if cid < 1
        cid = 1
    endif
    if cid > 6
        cid = 6
    endif
    normV  = plan_embNorm# [iRow]
    colStr$ = "{" + string$(clustR# [cid]) + "," + string$(clustG# [cid]) + "," + string$(clustB# [cid]) + "}"
    Paint circle: colStr$, iRow, normV, 0.12
endfor

Colour: "Black"
Draw inner box
Font size: 7
Text left:   "yes", "‖emb‖"
Text bottom: "yes", "Montage position"
Text top:    "no",  "Embedding norm per event  (montage order, coloured by cluster)"

# Summary panel
Select outer viewport: 0, 8, 6.25, 7.0
Select inner viewport: 0.6, 7.7, 6.30, 6.95
Axes: 0, 1, 0, 1
Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
Font size: 7
Colour: "Black"
Text: 0.02, "left", 0.88, "half", "Summary:"
Font size: 6
Colour: "{0.25, 0.25, 0.35}"
Text: 0.02, "left", 0.65, "half",
    ... "Source: " + origName$ + "  |  Duration: " + fixed$(dur, 2) + " s"
    ... + "  |  Events: " + string$(nEvents) + "  |  Clusters: " + string$(nClusters)
Text: 0.02, "left", 0.42, "half",
    ... "Frame step: " + fixed$(frame_step_s * 1000, 0) + " ms"
    ... + "  |  Pitch: " + string$(pitch_floor_hz) + "-" + string$(pitch_ceiling_hz) + " Hz"
    ... + "  |  Fade: " + string$(fade_ms) + " ms"
Text: 0.02, "left", 0.20, "half",
    ... "CNN: multi-scale conv (k=9,21)  T=128  D=32"
    ... + "  |  Contrastive training  |  K-means k=" + string$(nClusters)
Colour: "Black"
Draw rectangle: 0, 1, 0, 1
Font size: 10
Colour: "Black"

appendInfoLine: "  Visualization complete."

# ============================================================
# ============================================================
# CLEANUP
# ============================================================

removeObject: intensityObj, pitchObj, hnrObj, tgSilences
removeObject: recompTG, summaryTable
if isStereo
    removeObject: monoSound
endif

deleteFile: inputEventsCsv$
deleteFile: outputPlanCsv$

# ============================================================
# PLAY & FINAL SELECTION
# ============================================================

selectObject: recomposedSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", origName$, "_recomposed_CNN"
appendInfoLine: "Events:   ", nEvents
appendInfoLine: "Clusters: ", nClusters
appendInfoLine: "Montage:  ", nPlan, " events"

if play_result
    Play
endif
