# ========================================================================================
# Praat AudioTools - Wave_Gesture_Path_Performer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.8 (2026) - corpus loading: all audio formats, report, n >= 2 check
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Perform a playback PATH through a folder of sounds using the Genki
#   Wave ring (Bluetooth MIDI). Sounds are ordered by MFCC timbral
#   similarity (as in Timbral_Similarity_Browser). The performer then
#   records a gesture take:
#       Tilt -> WHICH sound (position along the ordered path)
#       Pan  -> timbral-path scrub offset (nudge forward/back for non-linear motion)
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
#     numbers (set them in Genki Softwave; defaults here are 1/2/3).
#
# USAGE:
#   Type the corpus folder path into the form's Folder field, or leave it
#   blank to pick the folder with a dialog. Take WAVs are saved there.
#
# Changelog v1.8 (2026) - corpus loading (the "one sound" problem):
#   1. A take that "always plays the same sound" was a corpus of ONE sound:
#      only *.wav files directly in the folder are loaded, so a folder of
#      .aif / .flac / .mp3 files, or one whose sounds sit in subfolders,
#      gave n = 1 and every trigger played position 1. The capture and the
#      CC mapping were fine (the v2.4 MIDI report showed CC 1/2/3 fully
#      active, 0-127).
#   2. Loads .wav .aif .aiff .aifc .flac .mp3 (case-insensitive).
#   3. Reports how many audio files were found, loaded and skipped (with
#      names), and how many subfolders were NOT searched.
#   4. Stops BEFORE recording when fewer than 2 sounds loaded - a path
#      through one sound cannot be performed.
#   5. Fixed: a file that failed to load left the PREVIOUS Sound selected,
#      so it was counted again as a new sound. Each load is now checked
#      against the object it actually returned.
#
# Changelog v1.7 (2026) - Tilt mapping; ordering, capture, voices unchanged:
#   1. New form option Tilt_mapping (default Auto-fit). v1.6 mapped raw
#      Tilt 0..1 straight onto path positions 1..n, but a natural hand
#      movement covers only part of the ring's CC range (e.g. 0.43-0.57),
#      so a take only ever visited the middle of the corpus - and because
#      the path is MFCC nearest-neighbour ordered, those neighbours sound
#      alike ("the same sound with variations").
#        Auto-fit take to full corpus: after capture, the take's own Tilt
#          range is measured and stretched to positions 1..n. Robust
#          range: 2nd-98th percentile, so a twitch or a single outlier
#          does not set the scale. A range under 0.02 is treated as no
#          movement and falls back to Absolute (reported).
#        Absolute (0-1): the v1.6 mapping.
#      Note: with Auto-fit the same physical tilt can land on different
#      positions in different takes - each take is fitted to itself.
#   2. Pan scrub is unchanged and stays a LOCAL nudge (+/- positions); it
#      is not used to widen the range.
#   3. Figure: the Gesture panel shades the fitted Tilt range, the Path
#      panel shows the mapped positions, and the summary strip reports the
#      mapping, the fitted range and the share of the corpus visited.
#
# Changelog v1.6 (2026) - per user request; corpus ordering, capture and
#                         rendering unchanged:
#   1. Demo-window live meter REMOVED (v1.5 item 1), together with the
#      --live_file handshake. The Info window still shows the helper's log
#      live during capture (v1.5 items 2-3).
#   2. No WAV is written any more. Each take stays in the Objects list as
#      Wave_Take_N; the user decides what to do with it. Praat-side output
#      is therefore Sound objects + the figure only.
#
# Changelog v1.5 (2026) - live feedback + cleanup; corpus ordering and
#                         rendering unchanged:
#   1. LIVE METER in the Demo window during capture: countdown, recording
#      progress, Tilt / Pan / Roll bars, and the corpus strip with the
#      sound Tilt + Pan currently select (named), refreshed ~10x/s.
#      Needs wave_capture.py v2.2 (--live_file).
#   2. Python is now launched WITHOUT waiting (start /b on Windows, & on
#      macOS/Linux), so Praat keeps polling during capture. In v1.4 the
#      launch blocked, so the poll loop only ran after capture had ended
#      and Praat looked frozen. Set live_feedback = 0 in DEFAULTS to go
#      back to the blocking launch.
#   3. The Info window shows the helper's log live (countdown, RECORDING,
#      finished) instead of only at the end.
#   4. Temporary files are deleted: gesture_takeN.csv as soon as it is
#      read, wave_log / wave_done / wave_live after each take, and all of
#      them on every exit path. Leftovers from earlier versions in the old
#      location are removed at the end of the session.
#   5. Handshake files moved to the system temp folder (%TEMP% on
#      Windows); temporaryDirectory$ resolved to the user home folder.
#
# Changelog v1.4 (2026) - interface + visualization; no change to corpus
#                         ordering, capture or rendering:
#   1. Folder form field (mirrors Bayesian Drone Weaver / VoidMosaic): type
#      the corpus path, or leave it blank to fall back to a folder dialog.
#      Whitespace and trailing slashes are trimmed. v1.3 always opened a
#      dialog.
#   2. Figure rebuilt to the library standard: 8 in canvas, inner viewports
#      0.6-7.7, bold ##title## at font 12 with a font 7 subtitle, panel
#      ground {0.97, 0.97, 0.97}, labels at font 6-7, Draw inner box after
#      every panel, legend strip, grey {0.94, 0.94, 0.94} summary strip.
#      v1.3 mixed fonts 7/8/10/13 and used Praat's default margins.
#   3. The figure now shows the PERFORMANCE, not only the raw gesture:
#        Gesture        Tilt / Pan / Roll over the take
#        Path           the corpus position each trigger actually played
#                       (grey = Tilt alone, orange = after Pan scrub,
#                       dot size = Roll volume)
#        Rendered take  the output waveform with trigger onsets
#      All three share one time axis.
#   4. The figure is drawn AFTER the take is trimmed and saved, so the
#      waveform panel and the summary show the file that was written.
#   5. Ends by re-selecting the full canvas, so Save as PNG / Copy capture
#      the whole figure rather than the last panel.
#   6. Praat 7: asks for full trust once (the script runs Python and writes
#      WAV files, both trust-gated in 7.0). Guarded, inert on Praat 6.
#
# Category: Performance / Hybrid (Praat + Python)
# ========================================================================================

form Wave Gesture Path Performer v1.8
    comment === Corpus Folder ===
    comment (Leave blank to pick a folder with a dialog)
    sentence Folder 
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
    optionmenu Tilt_mapping: 1
        option Auto-fit take to full corpus
        option Absolute (0-1)
    boolean Auto_play 1
endform

# --- Wave ring config (gesture->CC map) ---
# Leave chosenPort$ empty for Python-side auto-detection. The helper prefers
# ports whose names contain Wave, Genki, Bluetooth, or BLE; otherwise it uses
# the first available MIDI input. Set an exact/partial port name here only
# when you need to override auto-detection.
chosenPort$ = ""
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

# --- Live feedback: 1 = launch the capture helper without waiting and show
#     its log live in the Info window (countdown, RECORDING, finished);
#     0 = blocking launch (Praat waits silently until capture ends). ---
live_feedback = 1

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
writeInfoLine: "=== Wave Gesture Path Performer v1.8 ==="
appendInfoLine: ""

# Sound folder (the corpus). Take WAVs are saved here; transient
# Praat<->Python handshake files live in temporaryDirectory$.
# Folder field (mirrors Bayesian Drone Weaver): use the typed path, or
# fall back to a dialog when the field is left blank.
folder$ = replace_regex$(folder$, "^[ \t]*|[ \t]*$", "", 0)
folder$ = replace_regex$(folder$, "[\\/]+$", "", 0)
if folder$ = ""
    folder$ = chooseFolder$: "Select folder containing .wav files"
    folder$ = replace_regex$(folder$, "[\\/]+$", "", 0)
endif
if folder$ = ""
    exitScript: "Operation cancelled. Please supply a valid corpus folder path."
endif
directory$ = folder$
if right$(directory$, 1) <> "/" and right$(directory$, 1) <> "\"
    if index(directory$, "\") > 0
        directory$ = directory$ + "\"
    else
        directory$ = directory$ + "/"
    endif
endif

# Praat 7 gates system commands and file writes behind full trust.
if praatVersion >= 7000
    trustOk = askForTrust ()
    if trustOk = 0
        exitScript: "This script runs Python and deletes its temporary files; Praat 7 needs FULL TRUST for that."
    endif
endif

# Transient handshake files (cleared each take) go in Praat's temp dir.
# On Windows temporaryDirectory$ can be the user home folder; use %TEMP%.
tmpBase$ = temporaryDirectory$
if windows
    envTemp$ = environment$("TEMP")
    if envTemp$ <> ""
        tmpBase$ = replace$(envTemp$, "\", "/", 0)
    endif
endif
tmpDir$ = tmpBase$ + "/"

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

# every audio format Praat reads, case-insensitive, top level of the folder
nFiles = 0
for ext to 6
    if ext = 1
        ext$ = "wav"
    elsif ext = 2
        ext$ = "aif"
    elsif ext = 3
        ext$ = "aiff"
    elsif ext = 4
        ext$ = "aifc"
    elsif ext = 5
        ext$ = "flac"
    else
        ext$ = "mp3"
    endif
    found$# = fileNames_caseInsensitive$#(directory$ + "*." + ext$)
    for k to size(found$#)
        nFiles = nFiles + 1
        file_'nFiles'$ = found$#[k]
    endfor
endfor
subs$# = folderNames$#(directory$ + "*")
nSubs = size(subs$#)
appendInfoLine: "  Folder: ", directory$
appendInfoLine: "  Audio files found: ", nFiles, " (wav/aif/aiff/aifc/flac/mp3)"
if nSubs > 0
    appendInfoLine: "  Subfolders NOT searched: ", nSubs
endif
if nFiles = 0
    exitScript: "No audio files (wav, aif, aiff, aifc, flac, mp3) found in: " + directory$
endif

loadCount = 0
targetSR = 0
skipped = 0
skipped$ = ""
lastId = 0
for i from 1 to nFiles
    f$ = file_'i'$
    nocheck Read from file: directory$ + f$
    gotNew = 0
    if numberOfSelected("Sound") = 1
        if selected("Sound") <> lastId
            gotNew = 1
        endif
    endif
    if gotNew = 0
        skipped = skipped + 1
        if skipped <= 5
            skipped$ = skipped$ + "    " + f$ + newline$
        endif
    else
        lastId = selected("Sound")
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
        lastId = selected("Sound")
    endif
endfor

if skipped > 0
    appendInfoLine: "  Could not load ", skipped, " file(s):"
    appendInfo: skipped$
    if skipped > 5
        appendInfoLine: "    ..."
    endif
endif
if loadCount = 0
    exitScript: "No sounds loaded."
endif
if loadCount < 2
    n = loadCount
    @cleanupCorpus
    exitScript: "Only " + string$(loadCount) + " sound loaded from " + directory$ + newline$
        ... + "The gesture moves along a path THROUGH the corpus, so it needs at least 2 sounds" + newline$
        ... + "(more is better). Sounds in subfolders are not searched (" + string$(nSubs) + " subfolder(s) here)."
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
if chosenPort$ = ""
    appendInfoLine: "MIDI port: auto-detect  (CC tilt/pan/roll = ",
        ... cc_tilt, "/", cc_pan, "/", cc_roll, ")"
else
    appendInfoLine: "MIDI port override: ", chosenPort$, "  (CC tilt/pan/roll = ",
        ... cc_tilt, "/", cc_pan, "/", cc_roll, ")"
endif

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
    @cleanupTake

    # ---- ready prompt (Praat is frozen during capture, so cue here) ----
    # After you click Start, Python beeps: short ticks during the
    # countdown, a high GO beep when recording begins, a low beep when it
    # ends. Move your hand only between the GO and the end beep.
    beginPause: "Take " + string$(take) + " - get ready"
        comment: "When you click Start, the " + string$(countdown_seconds) +
            ... "s countdown begins (you'll hear ticks)."
        comment: "Recording starts on the HIGH beep and lasts " +
            ... fixed$(record_seconds, 1) + "s; a LOW beep ends it."
        comment: "Tilt = sound path | Pan gesture = timbral-path scrub | Roll = volume"
    clickedR = endPause: "Cancel", "Start", 2, 1
    if clickedR = 1
        @cleanupCorpus
        @cleanupTemp
        exitScript: "Cancelled before take " + string$(take) + "."
    endif

    # ---- launch Python capturer ----
    # Positional args: <gesture_csv> <log_file> <done_file>, then options,
    # exactly like the conductor's pyArgs$. We poll for the done file
    # (which contains "ok" or "error") with sleep:1, and echo the Python
    # log into the Info window - the same handshake as AI_Conductor_Mix.
    appendInfoLine: "  Capturing gesture via Wave ring..."
    appendInfoLine: "  (move your hand: Tilt=sound path, Pan gesture=timbral-path scrub, Roll=volume)"
    pyArgs$ = " """ + capScript$ + """ """ + gesture$ + """ """
        ... + logFile$ + """ """ + doneFile$ + """"
        ... + " --seconds " + string$(record_seconds)
        ... + " --take " + string$(take)
        ... + " --port """ + chosenPort$ + """"
        ... + " --countdown " + string$(countdown_seconds)
        ... + " --cc_tilt " + string$(cc_tilt)
        ... + " --cc_pan " + string$(cc_pan)
        ... + " --cc_roll " + string$(cc_roll)
    infoHead$ = info$ ()

    if live_feedback
        # launch WITHOUT waiting, so this script can poll and draw meanwhile
        if windows
            runSystem_nocheck: "start """" /b " + python_command$ + pyArgs$
        else
            runSystem_nocheck: python_command$ + pyArgs$ + " &"
        endif
    else
        runSystem_nocheck: python_command$ + pyArgs$
    endif

    # ---- poll for completion (live log while waiting) ----
    # The helper's own watchdog ends it after countdown + take + 20 s, so
    # maxWait is only a last resort.
    maxWait = record_seconds + countdown_seconds + 60
    waited = 0
    gotDone = 0
    lastLog$ = ""
    tick = 0
    repeat
        sleep: 0.1
        waited = waited + 0.1
        tick = tick + 1
        if fileReadable(doneFile$)
            gotDone = 1
        endif
        if live_feedback and tick mod 5 = 0 and fileReadable(logFile$)
            log$ = readFile$(logFile$)
            if log$ <> lastLog$
                writeInfoLine: infoHead$ + log$
                lastLog$ = log$
            endif
        endif
    until gotDone = 1 or waited >= maxWait

    # ---- final log into the Info window ----
    if fileReadable(logFile$)
        log$ = readFile$(logFile$)
        if live_feedback
            writeInfoLine: infoHead$ + log$
        else
            appendInfoLine: log$
        endif
    endif

    if gotDone = 0
        @cleanupCorpus
        @cleanupTemp
        exitScript: "Capture timed out (no response from Python). Check " +
            ... "that Python + mido are installed and the ring is paired."
    endif

    status$ = readFile$(doneFile$)
    if index(status$, "error") > 0
        @cleanupCorpus
        @cleanupTemp
        exitScript: "Wave capture reported an error. See the log above " +
            ... "(MIDI port / mido install / ring pairing)."
    endif

    if not fileReadable(gesture$)
        @cleanupCorpus
        @cleanupTemp
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

    # ---- Tilt mapping: fit this take's own Tilt range to the corpus ----
    tiltLo = 0
    tiltHi = 1
    tiltFitNote$ = "absolute 0-1"
    if tilt_mapping = 1
        tiltQ02 = Get quantile: "tilt", 0.02
        tiltQ98 = Get quantile: "tilt", 0.98
        if tiltQ98 - tiltQ02 >= 0.02
            tiltLo = tiltQ02
            tiltHi = tiltQ98
            tiltFitNote$ = "auto-fit " + fixed$(tiltLo, 2) + "-" + fixed$(tiltHi, 2) + " (P2-P98)"
        else
            tiltFitNote$ = "auto-fit skipped: Tilt range " + fixed$(tiltQ98 - tiltQ02, 3) + " < 0.02, absolute used"
        endif
    endif
    appendInfoLine: "  Tilt mapping: ", tiltFitNote$
    @cleanupTake
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
    # per-trigger record for the figure
    gT# = zero#(nGrains)
    gBase# = zero#(nGrains)
    gPos# = zero#(nGrains)
    gVol# = zero#(nGrains)

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
        tiltRaw = tilt
        tilt = min(1, max(0, (tilt - tiltLo) / (tiltHi - tiltLo)))
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
        gT#[g] = tOnset
        gBase#[g] = min(n, max(1, baseIdx))
        gPos#[g] = pathPos
        gVol#[g] = vol

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
    seen# = zero#(n)
    for g to nGrains
        seen#[gPos#[g]] = 1
    endfor
    nVisited = sum(seen#)
    appendInfoLine: "  Path positions visited: ", nVisited, " of ", n,
        ... " (range ", min(gPos#), "-", max(gPos#), ")"

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

    # the take stays in the Objects list; nothing is written to disk
    appendInfoLine: "  Take ", take, ": ", fixed$(takeDur, 2), " s -> Objects list: Wave_Take_", take

    # ---- figure: gesture, path through the corpus, rendered take ----
    @drawTake
    removeObject: gTable

    if auto_play
        selectObject: takeID
        Play
    endif

    # ---- another take? ----
    beginPause: "Take " + string$(take) + " complete"
        comment: "Take " + string$(take) + " is in the Objects list as Wave_Take_" + string$(take) + " (" +
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
@cleanupTemp

appendInfoLine: "Done. The takes are in the Objects list (Wave_Take_1 ...); nothing was saved to disk."

procedure cleanupTake
    # this take's handshake files (the gesture CSV is already in a Table)
    nocheck deleteFile: gesture$
    nocheck deleteFile: doneFile$
    nocheck deleteFile: logFile$
endproc

procedure cleanupTemp
    # every handshake file of this session, plus leftovers from earlier
    # versions in the old location (temporaryDirectory$)
    for .k to 2
        if .k = 1
            .d$ = tmpDir$
        else
            .d$ = temporaryDirectory$ + "/"
        endif
        .lst = Create Strings as file list: "stg", .d$ + "gesture_take*.csv"
        .nf = Get number of strings
        for .i to .nf
            .f$ = Get string: .i
            nocheck deleteFile: .d$ + .f$
        endfor
        removeObject: .lst
        nocheck deleteFile: .d$ + "wave_done.txt"
        nocheck deleteFile: .d$ + "wave_log.txt"
    endfor
endproc

procedure cleanupCorpus
    for i from 1 to n
        nocheck removeObject: sound_'i'
    endfor
endproc

procedure sanitize: .s$
    # Picture-window markup: _ subscript, % italic, # bold, ^ superscript
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    san$ = .s$
endproc

procedure niceStep: .span, .nTicks
    # round 1-2-5 tick spacing for an axis of the given span
    .raw = .span / .nTicks
    .p = 10 ^ floor(log10(max(.raw, 1e-9)))
    .m = .raw / .p
    if .m < 1.5
        niceStep = .p
    elsif .m < 3.5
        niceStep = 2 * .p
    elsif .m < 7.5
        niceStep = 5 * .p
    else
        niceStep = 10 * .p
    endif
endproc

procedure drawTake
    # Library-standard figure. Drawing-frame rules used throughout: Font size
    # BEFORE Select inner viewport; re-select the inner viewport before
    # curves and before Draw inner box (Text and Draw inner box leave the
    # frame on the outer viewport).
    .colTilt$ = "{0.15, 0.25, 0.70}"
    .colPan$ = "{0.10, 0.55, 0.25}"
    .colRoll$ = "{0.75, 0.20, 0.20}"
    .colPath$ = "{0.90, 0.50, 0.10}"
    .colBase$ = "{0.60, 0.60, 0.60}"
    .colWave$ = "{0.35, 0.35, 0.45}"
    .canvasH = 7.1

    selectObject: gTable
    .nRows = Get number of rows
    .tLast = Get value: .nRows, "time"
    .xMax = max(takeDur, record_seconds)
    @niceStep: .xMax, 6
    .tStep = niceStep
    @sanitize: replace_regex$(folder$, ".*[\\/]", "", 0)
    .folderLabel$ = san$

    Erase all

    # === TITLE ==========================================================
    Font size: 12
    Select inner viewport: 0.6, 7.7, 0.02, 0.36
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Wave Gesture Path Performer v1.8 - Take " + string$(take) + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.36, 0.54
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.5, "half", "Corpus: " + .folderLabel$ + "  |  " + string$(n) + " sounds (MFCC-ordered path)"
        ... + "  |  gesture " + fixed$(.tLast, 2) + " s  |  take " + fixed$(takeDur, 2) + " s"

    # === PANEL 1: GESTURE ===============================================
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.80, 2.05
    Axes: 0, .xMax, -0.05, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .xMax, -0.05, 1.05
    Colour: "Black"
    Text top: "no", "##Gesture##  Tilt, Pan and Roll from the ring (normalised 0..1); shaded band = Tilt range fitted to the corpus"
    Select inner viewport: 0.6, 7.7, 0.80, 2.05
    Axes: 0, .xMax, -0.05, 1.05
    Paint rectangle: "{0.88, 0.91, 0.98}", 0, .xMax, tiltLo, tiltHi
    Colour: "{0.80, 0.80, 0.80}"
    Line width: 1
    Dotted line
    Draw line: 0, 0.5, .xMax, 0.5
    Solid line
    Line width: 1.5
    selectObject: gTable
    .pT = Get value: 1, "time"
    .pA = Get value: 1, "tilt"
    .pB = Get value: 1, "pan"
    .pC = Get value: 1, "roll"
    for .r from 2 to .nRows
        .cT = Get value: .r, "time"
        .cA = Get value: .r, "tilt"
        .cB = Get value: .r, "pan"
        .cC = Get value: .r, "roll"
        Colour: .colTilt$
        Draw line: .pT, .pA, .cT, .cA
        Colour: .colPan$
        Draw line: .pT, .pB, .cT, .cB
        Colour: .colRoll$
        Draw line: .pT, .pC, .cT, .cC
        .pT = .cT
        .pA = .cA
        .pB = .cB
        .pC = .cC
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, 0.80, 2.05
    Axes: 0, .xMax, -0.05, 1.05
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Marks bottom every: 1, .tStep, "yes", "yes", "no"
    Text left: "yes", "Value"

    # === PANEL 2: PATH THROUGH THE CORPUS ================================
    .yLo = 0.5
    .yHi = n + 0.5
    @niceStep: n, 5
    .pStep = max(1, round(niceStep))
    Font size: 7
    Select inner viewport: 0.6, 7.7, 2.60, 3.90
    Axes: 0, .xMax, .yLo, .yHi
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .xMax, .yLo, .yHi
    Colour: "Black"
    Text top: "no", "##Path##  corpus position per trigger:  grey = mapped Tilt,  orange = after Pan scrub,  dot size = Roll volume"
    Select inner viewport: 0.6, 7.7, 2.60, 3.90
    Axes: 0, .xMax, .yLo, .yHi
    Colour: .colBase$
    Line width: 2
    for .g to nGrains
        .t2 = min(gT#[.g] + grain_seconds, .xMax)
        Draw line: gT#[.g], gBase#[.g], .t2, gBase#[.g]
    endfor
    Line width: 1
    Colour: .colPath$
    for .g from 2 to nGrains
        Draw line: gT#[.g - 1], gPos#[.g - 1], gT#[.g], gPos#[.g]
    endfor
    for .g to nGrains
        Paint circle (mm): .colPath$, gT#[.g], gPos#[.g], 0.35 + 0.9 * gVol#[.g]
    endfor
    Select inner viewport: 0.6, 7.7, 2.60, 3.90
    Axes: 0, .xMax, .yLo, .yHi
    Colour: "Black"
    Draw inner box
    Marks left every: 1, .pStep, "yes", "yes", "no"
    Marks bottom every: 1, .tStep, "yes", "yes", "no"
    Text left: "yes", "Path position"

    # === PANEL 3: RENDERED TAKE ==========================================
    selectObject: takeID
    .pk = Get absolute extremum: 0, 0, "None"
    if .pk <= 0
        .pk = 1
    endif
    Font size: 7
    Select inner viewport: 0.6, 7.7, 4.45, 5.30
    Axes: 0, .xMax, -.pk, .pk
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .xMax, -.pk, .pk
    Colour: "Black"
    Text top: "no", "##Rendered take##  " + string$(nGrains) + " triggers, " + string$(stealCount)
        ... + " voice steals; ticks = trigger onsets"
    Select inner viewport: 0.6, 7.7, 4.45, 5.30
    Axes: 0, .xMax, -.pk, .pk
    Colour: .colWave$
    selectObject: takeID
    Draw: 0, .xMax, -.pk, .pk, "no", "Curve"
    Select inner viewport: 0.6, 7.7, 4.45, 5.30
    Axes: 0, .xMax, -.pk, .pk
    Colour: .colPath$
    Line width: 1
    for .g to nGrains
        Draw line: gT#[.g], 0.82 * .pk, gT#[.g], .pk
    endfor
    Select inner viewport: 0.6, 7.7, 4.45, 5.30
    Axes: 0, .xMax, -.pk, .pk
    Colour: "Black"
    Draw inner box
    Marks left every: 1, .pk, "no", "yes", "no"
    Marks bottom every: 1, .tStep, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # === LEGEND =========================================================
    Font size: 6
    Select inner viewport: 0.6, 7.7, 5.72, 5.94
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Paint rectangle: .colTilt$, 0.00, 0.03, 0.25, 0.75
    Text: 0.035, "left", 0.5, "half", "Tilt (which sound)"
    Paint rectangle: .colPan$, 0.19, 0.22, 0.25, 0.75
    Text: 0.225, "left", 0.5, "half", "Pan (path scrub)"
    Paint rectangle: .colRoll$, 0.37, 0.40, 0.25, 0.75
    Text: 0.405, "left", 0.5, "half", "Roll (volume)"
    Paint rectangle: .colBase$, 0.54, 0.57, 0.25, 0.75
    Text: 0.575, "left", 0.5, "half", "Path from mapped Tilt"
    Paint rectangle: .colPath$, 0.75, 0.78, 0.25, 0.75
    Text: 0.785, "left", 0.5, "half", "Path played (after scrub)"

    # === SUMMARY STRIP ==================================================
    if chosenPort$ = ""
        .port$ = "auto-detect"
    else
        @sanitize: chosenPort$
        .port$ = san$
    endif
    @sanitize: "Wave_Take_" + string$(take)
    .file$ = san$
    Font size: 6
    Select inner viewport: 0.6, 7.7, 6.02, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.01, "left", 0.86, "half", "##Corpus##  folder " + .folderLabel$
        ... + "   sounds " + string$(n) + "   SR " + string$(targetSR) + " Hz"
        ... + "   order: MFCC (" + string$(num_coefficients) + " coeff.) nearest-neighbour path"
    Text: 0.01, "left", 0.62, "half", "##Performance##  record " + fixed$(record_seconds, 1) + " s"
        ... + "   grain " + fixed$(grain_seconds, 2) + " s   voice " + fixed$(voice_seconds, 2) + " s"
        ... + "   max voices " + string$(max_voices) + "   Pan scrub +/-" + fixed$(pan_scrub_amount, 0)
        ... + " positions   min volume " + fixed$(min_volume, 2)
    Text: 0.01, "left", 0.38, "half", "##Tilt mapping##  " + tiltFitNote$
        ... + "   ->  positions visited " + string$(nVisited) + " of " + string$(n)
        ... + " (" + fixed$(100 * nVisited / n, 0) + "\% )   range " + string$(min(gPos#)) + "-" + string$(max(gPos#))
    Text: 0.01, "left", 0.14, "half", "##Capture##  port " + .port$
        ... + "   CC tilt/pan/roll " + string$(cc_tilt) + "/" + string$(cc_pan) + "/" + string$(cc_roll)
        ... + "   " + string$(.nRows) + " samples   take " + fixed$(takeDur, 2) + " s  ->  object " + .file$
    Select inner viewport: 0.6, 7.7, 6.02, 6.98
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    # full canvas last, so Save as PNG / Copy capture the whole figure
    Select outer viewport: 0, 8, 0, .canvasH
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
