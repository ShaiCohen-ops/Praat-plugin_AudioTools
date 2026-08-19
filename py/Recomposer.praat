# ============================================================
# Praat AudioTools - recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2.2 (2026) - adaptive segmentation + duration-corrected morphology
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CNN Event Recomposer — Morphological Compositional Engine
#
#   An event-based acoustic recomposition system for Praat.
#   The script adaptively segments a selected Sound into
#   events using a short-window Intensity threshold ladder, extracts
#   feature trajectories, and sends them to
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

form Recomposer — CNN Event Recomposition v1.2.3
    optionmenu Compositional_form: 1
        option sorted
        option braid
        option phase
        option walk
    real Silence_threshold_db -25
    real Min_event_dur_s 0.03
    real Min_silence_dur_s 0.03
    real Min_sound_dur_s 0.03
    real Pitch_floor_hz 60
    real Pitch_ceiling_hz 600
    real Fade_ms 5
    boolean Play_result 1
endform

# ============================================================
# CONFIGURATION — fixed defaults
# ============================================================

frame_step_s            = 0.01
intensity_min_pitch_hz = 250   ; ~13 ms Intensity window; independent of F0 floor

# Map form variables to internal names
silence_threshold_db  = silence_threshold_db
min_event_dur_s       = min_event_dur_s
min_silence_dur_s     = min_silence_dur_s
min_sound_dur_s       = min_sound_dur_s
pitch_floor_hz        = pitch_floor_hz
pitch_ceiling_hz      = pitch_ceiling_hz
fade_ms               = fade_ms

if min_event_dur_s <= 0
    exitScript: "Min_event_dur_s must be > 0."
endif
if min_silence_dur_s <= 0 or min_sound_dur_s <= 0
    exitScript: "Min_silence_dur_s and Min_sound_dur_s must be > 0."
endif

# Keep Min_event_dur meaningful: the silence segmenter must not discard
# sounding intervals before the explicit event-duration filter sees them.
effective_min_sound_dur_s = min_sound_dur_s
if effective_min_sound_dur_s > min_event_dur_s
    effective_min_sound_dur_s = min_event_dur_s
endif
if pitch_floor_hz <= 0 or pitch_ceiling_hz <= pitch_floor_hz
    exitScript: "Pitch ceiling must be greater than pitch floor, and both must be positive."
endif
if fade_ms < 0
    exitScript: "Fade_ms must be >= 0."
endif

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
# PATHS & UNIFIED CROSS-PLATFORM FIX
# ============================================================

pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/recomposer.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/recomposer.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: recomposer.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

inputEventsCsv$ = tempDir$ + "temp_recomposer_input_events.csv"
outputPlanCsv$  = tempDir$ + "temp_recomposer_output_plan.csv"
pythonLogFile$  = tempDir$ + "temp_recomposer_python.log"
probePy$        = tempDir$ + "temp_recomposer_probe.py"
probeMarker$    = tempDir$ + "temp_recomposer_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$   = replace_regex$(pythonScript$, "\\", "/", 0)
inputEventsCsvJ$ = replace_regex$(inputEventsCsv$, "\\", "/", 0)
outputPlanCsvJ$  = replace_regex$(outputPlanCsv$, "\\", "/", 0)
pythonLogFileJ$  = replace_regex$(pythonLogFile$, "\\", "/", 0)
probePyJ$        = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$    = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(inputEventsCsv$)
        deleteFile: inputEventsCsv$
    endif
    if fileReadable(outputPlanCsv$)
        deleteFile: outputPlanCsv$
    endif
    if fileReadable(pythonLogFile$)
        deleteFile: pythonLogFile$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSound    = selected("Sound")
origName$    = selected$("Sound")
nChannels    = Get number of channels
analysisSoundOwned = 0
analysisChannel = 1

clearinfo
writeInfoLine:  "=== Recomposer — CNN Event Recomposition v1.2 ==="
appendInfoLine: "Sound:    ", origName$
appendInfoLine: "Channels: ", nChannels
appendInfoLine: ""

# ============================================================
# STAGE 0: Detect Python Dependencies
# ============================================================
appendInfoLine: "--- Stage 0: Detecting Python Environment ---"

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "if sys.version_info[0] < 3: sys.exit(1)"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, sklearn"
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

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        detectedCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", detectedCmd$
        iCand = nCandidates + 1 ; Break early
    endif
endfor

deleteFile: probePy$

if detectedCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Install dependencies: pip install numpy scikit-learn"
endif

# ============================================================
# REPRESENTATIVE CHANNEL FOR ANALYSIS ONLY
# ============================================================
# Do not average channels: anti-phase multichannel material can cancel.
# Analyse the channel with the highest RMS and preserve all original channels
# for the final montage.
selectObject: origSound
if nChannels > 1
    bestRms = -1
    bestChannel = 1
    for iCh from 1 to nChannels
        selectObject: origSound
        chSound = Extract one channel: iCh
        chRms = Get root-mean-square: 0, 0
        if chRms > bestRms
            bestRms = chRms
            bestChannel = iCh
        endif
        removeObject: chSound
    endfor
    selectObject: origSound
    monoSound = Extract one channel: bestChannel
    analysisSoundOwned = 1
    analysisChannel = bestChannel
    appendInfoLine: "Analysis channel: ", bestChannel, " (highest RMS)"
else
    monoSound = origSound
    appendInfoLine: "Analysis channel: 1 (mono)"
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
intensityObj = To Intensity: intensity_min_pitch_hz, frame_step_s, "yes"
appendInfoLine: "Intensity computed (segmentation window floor: ", intensity_min_pitch_hz, " Hz)."
if effective_min_sound_dur_s <> min_sound_dur_s
    appendInfoLine: "  Min_sound_dur_s clamped to Min_event_dur_s: ", fixed$(effective_min_sound_dur_s, 3), " s"
endif

# A fixed dB-below-peak threshold is fragile on dense electroacoustic material.
# Build an adaptive candidate from the Intensity distribution, then try a short
# ladder.  We stop as soon as a candidate yields >= 6 usable events; otherwise
# we retain whichever candidate produced the largest event count.
selectObject: intensityObj
intMax = Get maximum: 0, 0, "Parabolic"
intQ25 = Get quantile: 0, 0, 0.25
adaptiveThresh = -(intMax - intQ25)
if adaptiveThresh < -30
    adaptiveThresh = -30
endif
if adaptiveThresh > -3
    adaptiveThresh = -3
endif

tryThresh# = zero# (5)
tryThresh# [1] = silence_threshold_db
tryThresh# [2] = adaptiveThresh
tryThresh# [3] = -6
tryThresh# [4] = -4
tryThresh# [5] = -3

bestEventCount = -1
usedThresh = silence_threshold_db
for iTry from 1 to 5
    thisThresh = tryThresh# [iTry]
    selectObject: intensityObj
    tgTry = To TextGrid (silences): thisThresh,
        ... min_silence_dur_s, effective_min_sound_dur_s, "silent", "sounding"
    selectObject: tgTry
    nTryIntervals = Get number of intervals: 1
    nTryEvents = 0
    for iInt from 1 to nTryIntervals
        label$ = Get label of interval: 1, iInt
        if label$ = "sounding"
            iStart = Get start time of interval: 1, iInt
            iEnd   = Get end time of interval: 1, iInt
            if iEnd - iStart >= min_event_dur_s
                nTryEvents = nTryEvents + 1
            endif
        endif
    endfor
    appendInfoLine: "  Segmentation try ", iTry, ": threshold ", fixed$(thisThresh, 1), " dB -> ", nTryEvents, " events"
    if nTryEvents > bestEventCount
        bestEventCount = nTryEvents
        usedThresh = thisThresh
    endif
    removeObject: tgTry
    if nTryEvents >= 6
        usedThresh = thisThresh
        bestEventCount = nTryEvents
        iTry = 5
    endif
endfor

# Recreate the winning segmentation and collect the final event boundaries.
selectObject: intensityObj
tgSilences = To TextGrid (silences): usedThresh,
    ... min_silence_dur_s, effective_min_sound_dur_s, "silent", "sounding"
selectObject: tgSilences
Set tier name: 1, "events"

nIntervals = Get number of intervals: 1
nEvents = 0
event_start# = zero# (nIntervals)
event_end#   = zero# (nIntervals)
for iInt from 1 to nIntervals
    label$ = Get label of interval: 1, iInt
    if label$ = "sounding"
        iStart = Get start time of interval: 1, iInt
        iEnd   = Get end time of interval: 1, iInt
        evDur  = iEnd - iStart
        if evDur >= min_event_dur_s
            nEvents = nEvents + 1
            event_start# [nEvents] = iStart
            event_end#   [nEvents] = iEnd
        endif
    endif
endfor

appendInfoLine: "Segmentation: threshold ", fixed$(usedThresh, 1), " dB -> ", nEvents, " events"

if nEvents < 2
    removeObject: intensityObj, tgSilences
    if analysisSoundOwned
        removeObject: monoSound
    endif
    @cleanUpTempFiles
    exitScript: "Only " + string$(nEvents) + " event detected — nothing to recompose." + newline$
        ... + "Raise Silence_threshold_db toward -6/-3, lower Min_silence_dur_s, or use material with clearer event boundaries."
endif
if nEvents < 6
    appendInfoLine: "WARNING: only ", nEvents, " events; form differences may be limited."
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
writeFileLine: inputEventsCsv$, "event_id,start_time_s,end_time_s,duration_s,"
    ... + "pitch_seq_hz,intensity_seq_db,hnr_seq_db,voiced_seq,"
    ... + "spectral_centroid_seq_hz,spectral_spread_seq_hz,zcr_seq"

for iEv from 1 to nEvents
    evStart = event_start# [iEv]
    evEnd   = event_end#   [iEv]
    evDur   = evEnd - evStart

    # Number of analysis frames. Sample at frame centres so the first
    # spectrum does not straddle the preceding silence/event boundary.
    nFrames = ceiling(evDur / frame_step_s)
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
        t = evStart + (iFrame - 0.5) * frame_step_s

        # Clamp to the interior of the event.
        if t > evEnd
            t = evEnd
        endif
        if t < evStart
            t = evStart
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
        if tWin1 < evStart
            tWin1 = evStart
        endif
        if tWin2 > evEnd
            tWin2 = evEnd
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
        endif

        # Exact zero-crossing rate from the already-extracted mono frame.
        # Count both rising and falling zeroes, then normalise by sample intervals.
        zcr_val = 0
        if tWin2 > tWin1 + 0.001
            selectObject: snippetSound
            nSnippetSamples = Get number of samples
            zeroPP = To PointProcess (zeroes): 1, "yes", "yes"
            nCrossings = Get number of points
            if nSnippetSamples > 1
                zcr_val = nCrossings / (nSnippetSamples - 1)
            endif
            removeObject: zeroPP, snippetSound, snippetSpec
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
    appendFileLine: inputEventsCsv$, row$

    if iEv mod 10 = 0
        appendInfoLine: "  Extracted event ", iEv, " / ", nEvents
    endif
endfor

appendInfoLine: "  Wrote intermediate events file."

# ============================================================
# STAGE 3: Call Python
# ============================================================

appendInfoLine: ""
appendInfoLine: "--- Stage 3: Running Python CNN engine ---"
appendInfoLine: "  Form: ", compositional_form$

pythonCall$ = detectedCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + inputEventsCsvJ$ + """"
    ... + " """ + outputPlanCsvJ$ + """"
    ... + " --form " + compositional_form$
    ... + " 2> """ + pythonLogFileJ$ + """"

runSystem_nocheck: pythonCall$

if not fileReadable(outputPlanCsv$)
    appendInfoLine: ""
    appendInfoLine: "--- Python error log ---"
    if fileReadable(pythonLogFile$)
        Read Strings from raw text file: pythonLogFile$
        errStrings = selected("Strings")
        nErr = Get number of strings
        for iErr from 1 to nErr
            selectObject: errStrings
            errLine$ = Get string: iErr
            appendInfoLine: "  ", errLine$
        endfor
        removeObject: errStrings
    else
        appendInfoLine: "(no Python log was written)"
    endif
    @cleanUpTempFiles
    exitScript: "Python engine failed. See the Info window for details."
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
endif

# ============================================================
# STAGE 4: Read output_plan.csv
# ============================================================

appendInfoLine: ""
appendInfoLine: "--- Stage 4: Reading montage plan ---"

Read Strings from raw text file: outputPlanCsv$
planStrings = selected("Strings")
nPlanLines  = Get number of strings

# Store plan rows. Capacity follows the CSV, not an arbitrary 500-row cap.
nPlan = 0
planCapacity = nPlanLines - 1
if planCapacity < 1
    planCapacity = 1
endif
plan_newIdx#    = zero# (planCapacity)
plan_evId#      = zero# (planCapacity)
plan_start#     = zero# (planCapacity)
plan_end#       = zero# (planCapacity)
plan_cluster#   = zero# (planCapacity)
plan_morph#     = zero# (planCapacity)
plan_clustDist# = zero# (planCapacity)

for iLine from 2 to nPlanLines
    selectObject: planStrings
    rowStr$ = Get string: iLine
    rowStr$ = replace$(rowStr$, " ", "", 0)
    if rowStr$ <> ""
        # Parse CSV: new_index,orig_event_id,orig_start,orig_end,
        #            cluster_id,morph_score,cluster_distance
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
        plan_clustDist# [nPlan] = number(f7$)
    endif
endfor
removeObject: planStrings

appendInfoLine: "  Montage plan: ", nPlan, " events"
if nPlan < 2
    @cleanUpTempFiles
    exitScript: "Montage plan contains fewer than 2 events — refusing passthrough masquerading as recomposition."
endif

# ============================================================
# STAGE 5: Assemble recomposed sound
# ============================================================

appendInfoLine: ""
appendInfoLine: "--- Stage 5: Assembling recomposed sound ---"

fade_s = max(0, fade_ms / 1000)

# Choose a safe global crossfade. Praat's Concatenate with overlap performs
# complementary raised-cosine fades, avoiding the zero-level dip produced by
# fading each chunk separately and then concatenating.
minChunkDur = plan_end# [1] - plan_start# [1]
for iRow from 2 to nPlan
    thisDur = plan_end# [iRow] - plan_start# [iRow]
    if thisDur < minChunkDur
        minChunkDur = thisDur
    endif
endfor
overlap_s = fade_s
if overlap_s > minChunkDur * 0.45
    overlap_s = minChunkDur * 0.45
endif
# Extract and store all chunks; preserve every original channel.
chunkIds# = zero# (nPlan)
for iRow from 1 to nPlan
    chunkStart = max(0, plan_start# [iRow])
    chunkEnd   = min(dur, plan_end# [iRow])
    if chunkEnd <= chunkStart
        chunkEnd = min(dur, chunkStart + 0.001)
    endif
    selectObject: origSound
    chunk = Extract part: chunkStart, chunkEnd, "rectangular", 1, "no"
    chunkIds# [iRow] = chunk
endfor

selectObject: chunkIds# [1]
for iRow from 2 to nPlan
    plusObject: chunkIds# [iRow]
endfor
if overlap_s > 0
    Concatenate with overlap: overlap_s
else
    Concatenate
endif

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

# Fill cluster tier. During each crossfade the label handover occurs at
# the midpoint of the overlap, so the TextGrid remains a valid non-overlapping tier.
audioStart = 0
for iRow from 1 to nPlan
    chunkDur = plan_end# [iRow] - plan_start# [iRow]
    clustId  = round(plan_cluster# [iRow])
    selectObject: recompTG
    if iRow < nPlan
        nextAudioStart = audioStart + chunkDur - overlap_s
        boundaryTime = nextAudioStart + overlap_s / 2
        if boundaryTime > 0 and boundaryTime < recompDur
            Insert boundary: 1, boundaryTime
        endif
        audioStart = nextAudioStart
    endif
endfor
selectObject: recompTG
for iRow from 1 to nPlan
    Set interval text: 1, iRow, "C" + string$(round(plan_cluster# [iRow]))
endfor

appendInfoLine: "  Cluster TextGrid created."

# ── B. Summary Table ──────────────────────────────────────────────────────────

Create Table with column names: "recomposer_summary", nPlan,
    ... "new_index orig_event_id cluster_id morphology_score cluster_distance"
summaryTable = selected("Table")

for iRow from 1 to nPlan
    Set numeric value: iRow, "new_index",         plan_newIdx#  [iRow]
    Set numeric value: iRow, "orig_event_id",      plan_evId#    [iRow]
    Set numeric value: iRow, "cluster_id",         plan_cluster# [iRow]
    Set numeric value: iRow, "morphology_score",   plan_morph#   [iRow]
    Set numeric value: iRow, "cluster_distance",  plan_clustDist# [iRow]
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
Text: 0.5, "centre", -1.18, "half", origName$ + "  |  form: " + compositional_form$ + "  |  events: " + string$(nEvents)

# Shared symmetric waveform scale for a meaningful before/after comparison
selectObject: origSound
origPeak = Get absolute extremum: 0, 0, "Sinc70"
selectObject: recomposedSound
recompPeak = Get absolute extremum: 0, 0, "Sinc70"
wavePeak = max(origPeak, recompPeak)
if wavePeak < 0.001
    wavePeak = 1
endif

# Original waveform with event boundaries
Select outer viewport: 0, 8, 0.55, 1.55
Select inner viewport: 0.6, 7.7, 0.60, 1.50
selectObject: origSound
Colour: "{0.50, 0.50, 0.55}"
Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Original"
Text top:  "no", "Original sound  +  event boundaries"
Select inner viewport: 0.6, 7.7, 0.60, 1.50
Axes: 0, dur, -wavePeak, wavePeak
Colour: "{0.75, 0.35, 0.35}"
Line width: 1
for iEv from 1 to nEvents
    evT = event_start# [iEv]
    if evT > 0 and evT < dur
        Draw line: evT, -wavePeak * 0.85, evT, wavePeak * 0.85
    endif
endfor
Line width: 1

# Recomposed waveform
Select outer viewport: 0, 8, 1.60, 2.60
Select inner viewport: 0.6, 7.7, 1.65, 2.55
selectObject: recomposedSound
Colour: "{0.20, 0.45, 0.75}"
Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
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

segmentStart = 0
audioStart = 0
for iRow from 1 to nPlan
    chunkDur = plan_end# [iRow] - plan_start# [iRow]
    cid = round(plan_cluster# [iRow]) + 1
    if cid < 1
        cid = 1
    endif
    if cid > 6
        cid = 6
    endif
    if iRow < nPlan
        nextAudioStart = audioStart + chunkDur - overlap_s
        segmentEnd = nextAudioStart + overlap_s / 2
    else
        segmentEnd = recompDur
    endif
    colStr$ = "{" + string$(clustR# [cid]) + "," + string$(clustG# [cid]) + "," + string$(clustB# [cid]) + "}"
    Paint rectangle: colStr$, segmentStart, segmentEnd, 0.05, 0.95
    segmentStart = segmentEnd
    if iRow < nPlan
        audioStart = nextAudioStart
    endif
endfor

# Cluster labels in the bar
Font size: 7
segmentStart = 0
audioStart = 0
for iRow from 1 to nPlan
    chunkDur = plan_end# [iRow] - plan_start# [iRow]
    cid = round(plan_cluster# [iRow])
    if iRow < nPlan
        nextAudioStart = audioStart + chunkDur - overlap_s
        segmentEnd = nextAudioStart + overlap_s / 2
    else
        segmentEnd = recompDur
    endif
    midTime = (segmentStart + segmentEnd) / 2
    if segmentEnd - segmentStart > recompDur * 0.04
        Colour: "White"
        Text: midTime, "centre", 0.5, "half", "C" + string$(cid)
    endif
    segmentStart = segmentEnd
    if iRow < nPlan
        audioStart = nextAudioStart
    endif
endfor
Colour: "Black"
Draw inner box
Font size: 7
Text left:   "yes", "Cluster"
Text bottom: "yes", "Recomposed time (s)"
Text top:    "no",  "Cluster timeline — " + compositional_form$ + " form"

# Morphology score bar chart (one bar per cluster)
Select outer viewport: 0, 8, 3.65, 4.90
Select inner viewport: 0.6, 7.7, 3.75, 4.80
Axes: -0.5, nClusters - 0.5, 0, 1.15

Paint rectangle: "{0.96, 0.96, 0.98}", -0.5, nClusters - 0.5, 0, 1.15

for cid from 0 to nClusters - 1
    Select inner viewport: 0.6, 7.7, 3.75, 4.80
    Axes: -0.5, nClusters - 0.5, 0, 1.15
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

Select inner viewport: 0.6, 7.7, 3.75, 4.80
Axes: -0.5, nClusters - 0.5, 0, 1.15
Colour: "Black"
Line width: 1
Draw inner box
Font size: 7
Text left:   "yes", "Score"
Text top:    "no",  "Corpus cluster morphology  (form-independent)"
Text bottom: "yes", "Cluster"

# Cluster-distance scatter (event distance to its learned centroid)
Select outer viewport: 0, 8, 5.00, 6.15
Select inner viewport: 0.6, 7.7, 5.10, 6.05

# Find norm range
normMin = plan_clustDist# [1]
normMax = plan_clustDist# [1]
for iRow from 1 to nPlan
    if plan_clustDist# [iRow] < normMin
        normMin = plan_clustDist# [iRow]
    endif
    if plan_clustDist# [iRow] > normMax
        normMax = plan_clustDist# [iRow]
    endif
endfor
normRange = normMax - normMin
if normRange < 0.01
    normRange = 1
endif

Axes: 0, nPlan + 1, normMin - normRange * 0.1, normMax + normRange * 0.15
Paint rectangle: "{0.96, 0.96, 0.98}", 0, nPlan + 1, normMin - normRange * 0.1, normMax + normRange * 0.15

for iRow from 1 to nPlan
    Select inner viewport: 0.6, 7.7, 5.10, 6.05
    Axes: 0, nPlan + 1, normMin - normRange * 0.1, normMax + normRange * 0.15
    cid    = round(plan_cluster# [iRow]) + 1
    if cid < 1
        cid = 1
    endif
    if cid > 6
        cid = 6
    endif
    normV  = plan_clustDist# [iRow]
    colStr$ = "{" + string$(clustR# [cid]) + "," + string$(clustG# [cid]) + "," + string$(clustB# [cid]) + "}"
    Paint circle: colStr$, iRow, normV, 0.12
endfor

Select inner viewport: 0.6, 7.7, 5.10, 6.05
Axes: 0, nPlan + 1, normMin - normRange * 0.1, normMax + normRange * 0.15
Colour: "Black"
Draw inner box
Font size: 7
Text left:   "yes", "d(cluster)"
Text bottom: "yes", "Montage position"
Text top:    "no",  "Distance to learned cluster centroid  (lower = more central)"

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
    ... + "  |  Crossfade: " + fixed$(overlap_s * 1000, 1) + " ms"
Text: 0.02, "left", 0.20, "half",
    ... "CNN: multi-scale conv (k=9,21)  T=128  F=8  D=32"
    ... + "  |  unit embeddings  |  K-means k=" + string$(nClusters)
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
if analysisSoundOwned
    removeObject: monoSound
endif

@cleanUpTempFiles

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