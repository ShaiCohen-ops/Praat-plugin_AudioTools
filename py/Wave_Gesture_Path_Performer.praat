# ========================================================================================
# Praat AudioTools - Wave_Gesture_Path_Performer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Perform a playback PATH through a folder of sounds using the Genki
#   Wave ring (Bluetooth MIDI). Sounds are ordered by MFCC timbral
#   similarity (as in Timbral_Similarity_Browser). The performer then
#   records a gesture take:
#       Tilt -> WHICH sound (position along the ordered path)
#       Pan  -> scrub offset (nudge forward/back for non-linear motion)
#       Roll -> velocity / volume
#   After each take the gestured sequence is concatenated into one WAV,
#   played, and a popup offers another take.
#
# ARCHITECTURE (Praat cannot read MIDI/Bluetooth):
#   Praat orders the corpus and writes a capture job, then runs the
#   Python helper 'wave_capture.py' which records the ring's CC stream
#   over BLE-MIDI for the take duration and writes a gesture CSV. Praat
#   reads the CSV and renders the take. Communication is via files in a
#   shared work folder + a done-sentinel (the established AudioTools
#   Praat<->Python pattern).
#
# REQUIREMENTS:
#   - Python 3 with:  pip install mido python-rtmidi
#   - Wave ring paired over BLE MIDI; Tilt/Pan/Roll assigned to CC
#     numbers (set them in Genki Softwave; defaults here are 16/17/18).
#
# Category: Performance / Hybrid (Praat + Python)
# ========================================================================================

form Wave Gesture Path Performer v1.3
    comment === Capture ===
    positive Record_seconds 8.0
    integer Countdown_seconds 3
    comment === Performance ===
    positive Grain_seconds 0.25
    comment (time between triggers; how often a new voice fires)
    positive Voice_seconds 1.5
    comment (how long each triggered voice rings before fading)
    integer Max_voices 8
    positive Pan_scrub_amount 4
    boolean Auto_play 1
endform

# --- Hardcoded Wave ring config (port + gesture->CC map) ---
chosenPort$ = "Wave 1"
cc_tilt = 1
cc_pan = 2
cc_roll = 3

# ========================================================================================
# DEFAULTS  (set-once values; edit here instead of in the dialog)
# ========================================================================================

# --- Corpus ordering (MFCC) ---
num_coefficients = 12
window_length = 0.015
time_step = 0.005

# --- Path mapping ---
min_volume = 0.15

# --- Python interpreter: OS-specific auto-discovery (as in
#     AI_Conductor_Mix.praat). Override only if it lives somewhere odd. ---
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        python_command$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        python_command$ = "/usr/local/bin/python3"
    else
        python_command$ = "python3"
    endif
elsif windows
    python_command$ = "python"
else
    python_command$ = "python3"
endif

# --- Where wave_capture.py lives (alongside the AudioTools Python
#     helpers); falls back to the sound folder if not installed there. ---
pluginPyDir$ = preferencesDirectory$ + "/plugin_AudioTools/py/"

# ========================================================================================
# SETUP: folders
# ========================================================================================

clearinfo
writeInfoLine: "=== Wave Gesture Path Performer v1.1 ==="
appendInfoLine: ""

# Sound folder (the corpus). Take WAVs are saved here; transient
# Praat<->Python handshake files live in temporaryDirectory$.
directory$ = chooseDirectory$: "Select folder containing .wav files"
if directory$ = ""
    exitScript: "No sound folder selected."
endif
if right$(directory$, 1) <> "/" and right$(directory$, 1) <> "\"
    if index(directory$, "\") > 0
        directory$ = directory$ + "\"
    else
        directory$ = directory$ + "/"
    endif
endif

# Transient handshake files (cleared each take) go in Praat's temp dir.
tmpDir$ = temporaryDirectory$ + "/"

# Locate wave_capture.py: prefer the installed plugin py/ folder; fall
# back to the sound folder (handy when running the two files together).
capScript$ = pluginPyDir$ + "wave_capture.py"
if not fileReadable(capScript$)
    capScript$ = directory$ + "wave_capture.py"
endif
if not fileReadable(capScript$)
    exitScript: "Cannot find wave_capture.py. Put it in " + pluginPyDir$ +
        ... " or in the sound folder."
endif
appendInfoLine: "Capture helper: ", capScript$

# ========================================================================================
# STEP 1: LOAD + ORDER CORPUS (MFCC nearest-neighbor, as Timbral_Similarity)
# ========================================================================================

appendInfoLine: ""
appendInfoLine: "Loading and ordering corpus..."

files$# = fileNames_caseInsensitive$#(directory$ + "*.wav")
nFiles = size(files$#)
if nFiles = 0
    exitScript: "No .wav files found."
endif

loadCount = 0
targetSR = 0
for i from 1 to nFiles
    f$ = files$#[i]
    nocheck Read from file: directory$ + f$
    if numberOfSelected("Sound") = 1
        loadCount = loadCount + 1
        s_id = selected("Sound")
        nm$ = selected$("Sound")
        nCh = Get number of channels
        if nCh > 1
            Convert to mono
            mono = selected("Sound")
            removeObject: s_id
            Rename: nm$
            sound_'loadCount' = mono
        else
            sound_'loadCount' = s_id
        endif
        selectObject: sound_'loadCount'
        fsr = Get sampling frequency
        if targetSR = 0
            targetSR = fsr
        elsif fsr <> targetSR
            Resample: targetSR, 50
            rs = selected("Sound")
            removeObject: sound_'loadCount'
            Rename: nm$
            sound_'loadCount' = rs
        endif
        sound_dur_'loadCount' = Get total duration
        sound_name_'loadCount'$ = selected$("Sound")
    endif
endfor

if loadCount = 0
    exitScript: "No sounds loaded."
endif
n = loadCount
appendInfoLine: "  Loaded ", n, " sounds (SR ", targetSR, " Hz)"

# MFCC mean-vector features
Create TableOfReal: "feat", n, num_coefficients
featTable = selected("TableOfReal")
for i from 1 to n
    selectObject: sound_'i'
    dur = Get total duration
    if dur >= 0.02
        To MFCC: num_coefficients, window_length, time_step, 100, 100, 0.0
        mfccID = selected("MFCC")
        nfr = Get number of frames
        for c from 1 to num_coefficients
            sm = 0
            cnt = 0
            selectObject: mfccID
            for fr from 1 to nfr
                val = Get value in frame: fr, c
                if val <> undefined
                    sm = sm + val
                    cnt = cnt + 1
                endif
            endfor
            mv = 0
            if cnt > 0
                mv = sm / cnt
            endif
            selectObject: featTable
            Set value: i, c, mv
        endfor
        removeObject: mfccID
    endif
endfor

# Distance matrix + nearest-neighbor path
Create TableOfReal: "dist", n, n
distTable = selected("TableOfReal")
for i from 1 to n
    for j from i to n
        d = 0
        selectObject: featTable
        for c from 1 to num_coefficients
            vi = Get value: i, c
            vj = Get value: j, c
            d = d + (vi - vj) * (vi - vj)
        endfor
        d = sqrt(d)
        selectObject: distTable
        Set value: i, j, d
        Set value: j, i, d
    endfor
endfor

path# = zero#(n)
if n = 1
    path#[1] = 1
else
    visited# = zero#(n)
    path#[1] = 1
    visited#[1] = 1
    cur = 1
    for step from 2 to n
        best = 0
        bestD = 1e30
        selectObject: distTable
        for cand from 1 to n
            if visited#[cand] = 0
                dd = Get value: cur, cand
                if dd < bestD
                    bestD = dd
                    best = cand
                endif
            endif
        endfor
        if best > 0
            path#[step] = best
            visited#[best] = 1
            cur = best
        endif
    endfor
endif
removeObject: featTable, distTable
appendInfoLine: "  Ordered path built."

appendInfoLine: ""
appendInfoLine: "MIDI port: ", chosenPort$, "  (CC tilt/pan/roll = ",
    ... cc_tilt, "/", cc_pan, "/", cc_roll, ")"

# ========================================================================================
# TAKE LOOP
# ========================================================================================

take = 0
keepGoing = 1

while keepGoing = 1
    take = take + 1
    appendInfoLine: ""
    appendInfoLine: "=== TAKE ", take, " ==="

    # ---- shared file paths (mirrors ai_conductor_mix.py contract) ----
    gesture$ = tmpDir$ + "gesture_take" + string$(take) + ".csv"
    logFile$ = tmpDir$ + "wave_log.txt"
    doneFile$ = tmpDir$ + "wave_done.txt"
    nocheck deleteFile: doneFile$
    nocheck deleteFile: logFile$

    # ---- ready prompt (Praat is frozen during capture, so cue here) ----
    # After you click Start, Python beeps: short ticks during the
    # countdown, a high GO beep when recording begins, a low beep when it
    # ends. Move your hand only between the GO and the end beep.
    beginPause: "Take " + string$(take) + " - get ready"
        comment: "When you click Start, the " + string$(countdown_seconds) +
            ... "s countdown begins (you'll hear ticks)."
        comment: "Recording starts on the HIGH beep and lasts " +
            ... fixed$(record_seconds, 1) + "s; a LOW beep ends it."
        comment: "Tilt = sound | Pan = scrub | Roll = volume"
    clickedR = endPause: "Cancel", "Start", 2, 1
    if clickedR = 1
        @cleanupCorpus
        exitScript: "Cancelled before take " + string$(take) + "."
    endif

    # ---- launch Python capturer ----
    # Positional args: <gesture_csv> <log_file> <done_file>, then options,
    # exactly like the conductor's pyArgs$. We poll for the done file
    # (which contains "ok" or "error") with sleep:1, and echo the Python
    # log into the Info window - the same handshake as AI_Conductor_Mix.
    appendInfoLine: "  Capturing gesture via Wave ring..."
    appendInfoLine: "  (move your hand: Tilt=sound, Pan=scrub, Roll=volume)"
    pyArgs$ = " """ + capScript$ + """ """ + gesture$ + """ """
        ... + logFile$ + """ """ + doneFile$ + """"
        ... + " --seconds " + string$(record_seconds)
        ... + " --take " + string$(take)
        ... + " --port """ + chosenPort$ + """"
        ... + " --countdown " + string$(countdown_seconds)
        ... + " --cc_tilt " + string$(cc_tilt)
        ... + " --cc_pan " + string$(cc_pan)
        ... + " --cc_roll " + string$(cc_roll)
    runSystem_nocheck: python_command$ + pyArgs$

    # ---- poll for completion ----
    maxWait = record_seconds + countdown_seconds + 60
    waited = 0
    gotDone = 0
    repeat
        sleep: 1
        waited = waited + 1
        if fileReadable(doneFile$)
            gotDone = 1
        endif
    until gotDone = 1 or waited >= maxWait

    # ---- echo the Python log into the Info window ----
    if fileReadable(logFile$)
        log$ = readFile$(logFile$)
        appendInfoLine: log$
    endif

    if gotDone = 0
        @cleanupCorpus
        exitScript: "Capture timed out (no response from Python). Check " +
            ... "that Python + mido are installed and the ring is paired."
    endif

    status$ = readFile$(doneFile$)
    if index(status$, "error") > 0
        @cleanupCorpus
        exitScript: "Wave capture reported an error. See the log above " +
            ... "(MIDI port / mido install / ring pairing)."
    endif

    if not fileReadable(gesture$)
        @cleanupCorpus
        exitScript: "Gesture file not found: " + gesture$
    endif

    # ========================================================================================
    # RENDER THE GESTURED TAKE
    # ========================================================================================

    appendInfoLine: "  Rendering take ", take, " (", max_voices, "-voice)..."

    # Gesture CSV is TAB-delimited (time, tilt, pan, roll). Build trigger
    # steps at the grain rate: each step picks a sound via Tilt(+Pan scrub)
    # and a volume via Roll, sampling the gesture at the step's time. Each
    # trigger becomes a VOICE that rings for voice_seconds (Hanning-faded)
    # and is SUMMED into one output buffer at its onset (overlap-add), so
    # voices overlap instead of cutting each other off.
    Read Table from tab-separated file: gesture$
    gTable = selected("Table")
    nRows = Get number of rows

    nGrains = ceiling(record_seconds / grain_seconds)
    if nGrains < 1
        nGrains = 1
    endif

    # Output buffer: record window + a tail for the last voice to ring out.
    out_dur = record_seconds + voice_seconds + 0.05
    Create Sound from formula: "take_buf", 1, 0, out_dur, targetSR, "0"
    takeID = selected("Sound")

    # Voice pool bookkeeping (active onsets/ends for oldest-voice stealing).
    nActive = 0
    for v to max_voices
        voiceEnd_'v' = -1
        voiceOnset_'v' = -1
    endfor

    stealCount = 0

    for g from 1 to nGrains
        tOnset = (g - 1) * grain_seconds
        tCenter = tOnset + grain_seconds / 2

        # nearest gesture row to tCenter
        selectObject: gTable
        bestRow = 1
        bestDT = 1e30
        for r from 1 to nRows
            tr = Get value: r, "time"
            dt = abs(tr - tCenter)
            if dt < bestDT
                bestDT = dt
                bestRow = r
            endif
        endfor
        tilt = Get value: bestRow, "tilt"
        pan = Get value: bestRow, "pan"
        roll = Get value: bestRow, "roll"

        # Tilt -> base path index; Pan -> scrub offset
        baseIdx = floor(tilt * (n - 1) + 0.5) + 1
        scrub = round((pan - 0.5) * 2 * pan_scrub_amount)
        pathPos = baseIdx + scrub
        if pathPos < 1
            pathPos = 1
        endif
        if pathPos > n
            pathPos = n
        endif
        soundIdx = path#[pathPos]
        vol = min_volume + (1 - min_volume) * roll

        # --- voice allocation: free any voices that ended before now ---
        nActive = 0
        oldestV = 1
        oldestOnset = 1e30
        for v to max_voices
            if voiceEnd_'v' > tOnset
                nActive = nActive + 1
                if voiceOnset_'v' < oldestOnset
                    oldestOnset = voiceOnset_'v'
                    oldestV = v
                endif
            endif
        endfor

        # this voice's natural ring length (clamped to the source + buffer)
        thisLen = voice_seconds
        sdur = sound_dur_'soundIdx'
        if thisLen > sdur
            thisLen = sdur
        endif

        # If the pool is full, STEAL the oldest: cut its ring short so it
        # ends (with the Hanning tail) at this onset. We model the steal by
        # recording a shorter end; the already-summed tail is faded by the
        # voice's own Hanning window, and we additionally taper from here.
        if nActive >= max_voices
            stealCount = stealCount + 1
            # shorten the stolen voice's logical end to now
            voiceEnd_'oldestV' = tOnset
            # short linear fade in the buffer across the steal point so the
            # masked tail of the stolen voice doesn't click
            fadeLen = 0.03
            fadeStart = tOnset
            fadeEnd = tOnset + fadeLen
            if fadeEnd > out_dur
                fadeEnd = out_dur
            endif
            selectObject: takeID
            Formula (part): fadeStart, fadeEnd, 1, 1,
                ... "self * (1 - (x - " + string$(fadeStart) + ") / " + string$(fadeLen) + ")"
            useV = oldestV
        else
            # find a free slot
            useV = 1
            for v to max_voices
                if voiceEnd_'v' <= tOnset
                    useV = v
                endif
            endfor
        endif

        # record the new voice in the chosen slot
        voiceOnset_'useV' = tOnset
        voiceEnd_'useV' = tOnset + thisLen

        # --- extract the grain and SUM it into the buffer at tOnset ---
        selectObject: sound_'soundIdx'
        startMax = sdur - thisLen
        st = 0
        if startMax > 0
            st = (tCenter / record_seconds) * startMax
        endif
        Extract part: st, st + thisLen, "Hanning", 1, "no"
        grainID = selected("Sound")
        Scale peak: 0.99
        Formula: "self * " + string$(vol)

        gOnsetEnd = tOnset + thisLen
        if gOnsetEnd > out_dur
            gOnsetEnd = out_dur
        endif
        grainStr$ = string$(grainID)
        onsetStr$ = string$(tOnset)
        selectObject: takeID
        Formula (part): tOnset, gOnsetEnd, 1, 1,
            ... "self + Object_" + grainStr$ + "(x - " + onsetStr$ + ")"
        removeObject: grainID
    endfor

    appendInfoLine: "  Triggers: ", nGrains, "   voice steals: ", stealCount

    # ========================================================================================
    # VISUALIZE THE CAPTURED GESTURE (Tilt / Pan / Roll over the take)
    # ========================================================================================

    selectObject: gTable
    vizN = Get number of rows
    if vizN >= 2
        tLast = Get value: vizN, "time"
        if tLast <= 0
            tLast = record_seconds
        endif

        Erase all

        # --- title band (taller, rows well separated) ---
        Select outer viewport: 0, 8, 0, 0.75
        Axes: 0, 1, 0, 1
        Black
        Font size: 13
        Text: 0.5, "centre", 0.78, "half", "##Wave Gesture - Take " + string$(take) + "##"
        Font size: 8
        Colour: "{0.4, 0.4, 0.5}"
        Text: 0.5, "centre", 0.30, "half", "Tilt = sound path  |  Pan = scrub  |  Roll = volume"
        Black

        # --- curve panel ---
        Select outer viewport: 0, 8, 0.9, 3.7
        Select inner viewport: 0.7, 7.7, 1.2, 3.5
        Axes: 0, tLast, -0.05, 1.05
        Paint rectangle: "{0.97, 0.97, 0.98}", 0, tLast, -0.05, 1.05
        Marks bottom: 6, "yes", "yes", "no"
        Marks left: 5, "yes", "yes", "no"
        Text bottom: "yes", "time (s)"
        Text left: "yes", "normalised value (0..1)"

        # gridline at 0.5
        Line width: 0.5
        Colour: "{0.85, 0.85, 0.85}"
        Draw line: 0, 0.5, tLast, 0.5

        # Tilt (blue), Pan (green), Roll (red) - segment by segment
        Line width: 1.6
        prevT = Get value: 1, "time"
        prevTilt = Get value: 1, "tilt"
        prevPan = Get value: 1, "pan"
        prevRoll = Get value: 1, "roll"
        for r from 2 to vizN
            curT = Get value: r, "time"
            curTilt = Get value: r, "tilt"
            curPan = Get value: r, "pan"
            curRoll = Get value: r, "roll"
            Colour: "{0.15, 0.25, 0.70}"
            Draw line: prevT, prevTilt, curT, curTilt
            Colour: "{0.10, 0.55, 0.25}"
            Draw line: prevT, prevPan, curT, curPan
            Colour: "{0.75, 0.20, 0.20}"
            Draw line: prevT, prevRoll, curT, curRoll
            prevT = curT
            prevTilt = curTilt
            prevPan = curPan
            prevRoll = curRoll
        endfor
        Colour: "{0, 0, 0}"
        Font size: 10
        Draw inner box

        # --- legend band (taller; swatch row and stats row separated) ---
        Select outer viewport: 0, 8, 3.8, 4.6
        Axes: 0, 1, 0, 1
        Font size: 8
        Paint rectangle: "{0.15, 0.25, 0.70}", 0.03, 0.07, 0.62, 0.80
        Text: 0.09, "left", 0.71, "half", "Tilt (sound path)"
        Paint rectangle: "{0.10, 0.55, 0.25}", 0.32, 0.36, 0.62, 0.80
        Text: 0.38, "left", 0.71, "half", "Pan (scrub)"
        Paint rectangle: "{0.75, 0.20, 0.20}", 0.56, 0.60, 0.62, 0.80
        Text: 0.62, "left", 0.71, "half", "Roll (volume)"
        Colour: "{0.4, 0.4, 0.5}"
        Font size: 7
        Text: 0.03, "left", 0.22, "half", "samples: " + string$(vizN) +
            ... "   length: " + fixed$(tLast, 2) + " s   grains: " +
            ... string$(nGrains) + "   voices: " + string$(max_voices) +
            ... "   corpus: " + string$(n) + " sounds"
        Black
        Font size: 10
    endif

    removeObject: gTable

    # Trim trailing silence (the buffer has a voice_seconds ring-out tail).
    selectObject: takeID
    trimTo = out_dur
    probe = out_dur
    found = 0
    while found = 0 and probe > 0.2
        probe = probe - 0.02
        v = Get value at time: 1, probe, "Sinc70"
        if v = undefined
            v = 0
        endif
        if abs(v) > 0.0005
            trimTo = probe + 0.05
            found = 1
        endif
    endwhile
    if trimTo > out_dur
        trimTo = out_dur
    endif
    Extract part: 0, trimTo, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: takeID
    takeID = trimmed

    selectObject: takeID
    Scale peak: 0.99
    Rename: "Wave_Take_" + string$(take)
    takeDur = Get total duration

    # save the take WAV in the work folder
    takeWav$ = directory$ + "wave_take" + string$(take) + ".wav"
    nocheck Save as WAV file: takeWav$
    appendInfoLine: "  Take ", take, ": ", fixed$(takeDur, 2), " s -> ", takeWav$

    if auto_play
        selectObject: takeID
        Play
    endif

    # ---- another take? ----
    beginPause: "Take " + string$(take) + " complete"
        comment: "Saved: wave_take" + string$(take) + ".wav (" +
            ... fixed$(takeDur, 2) + " s)"
        comment: "Record another take?"
    clicked = endPause: "Stop", "Take " + string$(take + 1), 2
    if clicked = 1
        keepGoing = 0
    endif
endwhile

# ========================================================================================
# CLEANUP
# ========================================================================================

appendInfoLine: ""
appendInfoLine: "=== SESSION COMPLETE ==="
appendInfoLine: "Takes recorded: ", take

@cleanupCorpus

appendInfoLine: "Done. Take WAVs are in: ", directory$

procedure cleanupCorpus
    for i from 1 to n
        nocheck removeObject: sound_'i'
    endfor
endproc
