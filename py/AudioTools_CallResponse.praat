# ============================================================
# Praat AudioTools Plugin
# Script:      AudioTools_CallResponse.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     0.1.2 (2026) - Native MDS visualization toggle
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Intelligent Musical Call & Response.  A performer plays a phrase;
#   audiotools_call_response.py records it, analyses its acoustic and
#   morphological features and chooses ONE of six existing AudioTools
#   transformations plus gesture-derived parameters; this script runs
#   that AudioTools script on the recorded phrase and plays the answer.
#
#     Paulstretch ............. stable harmonic material
#     Markov Soundscape Weaver  noisy / aperiodic material
#     MDS Space Navigator ..... discrete separable attacks
#     Spiral Pitch Dance ...... continuous glissando
#     Metamodulator ........... complex dynamic envelope
#     Percussive Groove Creator percussive events, changing density
#
# Execution model (strict turn-taking, fully synchronous):
#   per cycle:  runSubprocess python listen   (BLOCKS while listening)
#               -> phrase WAV + decision file
#               -> runScript <selected AudioTools script>
#               -> Play (blocks until the answer has finished)
#   The microphone is open ONLY inside the Python call, so the answer
#   can never be recorded as the next question.  Praat's GUI does not
#   respond while Python is listening or a transformation is rendering.
#   A session ends after Cycles turns, or when nobody plays for the
#   waiting timeout (30 s) - that is the safe way to stop it.
#
# Installation:
#   plugin_AudioTools/Vector Chain/AudioTools_CallResponse.praat
#   plugin_AudioTools/py/audiotools_call_response.py
#   pip install numpy scipy soundfile sounddevice
#   The six processing scripts are used unmodified from their usual
#   AudioTools folders; the plugin root is found from the preferences
#   folder, or as the parent of this script's folder.
#
# Testing without a microphone:
#   Select one or more Sounds, Source = "Selected Sound(s)".  Use
#   "Test all six" to push every selected Sound through all six scripts.
#   python audiotools_call_response.py --self-test   tests the classifier.
#
# Notes:
#   - Requires Praat 6.3+ (colon form syntax).  Praat 7: askForTrust()
#     is requested once, because the session writes and deletes temporary
#     files and launches Python.
#   - Only minimal performance state and chosen transformation are shown
#     in the Praat Info window.  Detailed child output is reset on return.
#   - MDS Space Navigator v0.4.1+ provides a native Draw_visualization flag.
#     All six transformations run with their visualization disabled.
#     Older MDS versions without this flag are rejected rather than drawing
#     in the Picture window.
#   - The live listener is synchronous; Praat does not update its display
#     during the blocking Python capture + analysis call.
# ============================================================

form: "AudioTools Call & Response 0.1"
    optionmenu: "Source", 1
        option: "Live microphone"
        option: "Selected Sound(s)"
        option: "List audio input devices"
    optionmenu: "Transformation", 1
        option: "Automatic (gesture classifier)"
        option: "Paulstretch"
        option: "Markov Soundscape Weaver"
        option: "MDS Space Navigator"
        option: "Spiral Pitch Dance"
        option: "Metamodulator"
        option: "Percussive Groove Creator"
        option: "Test all six (selected Sounds)"
    natural: "Cycles", "4"
    sentence: "Input_device", "default"
    positive: "Sample_rate", "44100"
    natural: "Channels", "1"
    positive: "Sensitivity_dB", "9"
    positive: "Min_phrase_s", "0.5"
    positive: "End_silence_s", "0.6"
    positive: "Max_phrase_s", "12"
    boolean: "Play_response", 1
endform

# ---- EDIT IF YOUR PYTHON IS NON-STANDARD (empty = auto-detect only) ----
pyCandidate1$ = "C:/Users/user/praat_ddsp_env/Scripts/python.exe"
# ------------------------------------------------------------------------
waitTimeout = 30
preroll = 0.25
version$ = "0.1.2-info-only"
diagnostics = 0

# ---- Praat 7 trust (file writing, deletion, subprocess) ----
if praatVersion >= 7000
    trustGranted = askForTrust ()
    if not trustGranted
        exitScript: "Call & Response needs FULL TRUST (it writes temporary audio and runs Python)."
    endif
endif
hasClock = praatVersion >= 6434

# ---- Six transformations: fixed whitelist, ids never taken from Python ----
nT = 6
tId$[1] = "paulstretch"
tId$[2] = "markov"
tId$[3] = "mds"
tId$[4] = "spiral"
tId$[5] = "metamod"
tId$[6] = "groove"
tDisplay$[1] = "Paulstretch"
tDisplay$[2] = "Markov Soundscape Weaver"
tDisplay$[3] = "MDS Space Navigator"
tDisplay$[4] = "Spiral Pitch Dance"
tDisplay$[5] = "Metamodulator"
tDisplay$[6] = "Percussive Groove Creator"
tRel$[1] = "Time & Granular/Paulstretch.praat"
tRel$[2] = "AI & Adaptive/Markov_Soundscape_Weaver.praat"
tRel$[3] = "Time & Granular/MDS_Space_Navigator.praat"
tRel$[4] = "Pitch/Spiral_Pitch_Dance.praat"
tRel$[5] = "Modulation/Metamodulator.praat"
tRel$[6] = "Time & Granular/Percussive Audio Groove Creator.praat"
# name stem each script appends to its input name (verified in source)
tStem$[1] = "_PS_"
tStem$[2] = "_MarkovWeave_"
tStem$[3] = "_reordered"
tStem$[4] = "_spiral_"
tStem$[5] = "_Metamod_"
tStem$[6] = "_groove_"

# ---- Validate source / mode combinations ----
sweep = transformation = 8
if source = 1 and sweep
    exitScript: "'Test all six' works on selected Sounds only - set Source to Selected Sound(s)."
endif
if source = 2
    nSel = numberOfSelected ("Sound")
    if nSel < 1
        exitScript: "Source is Selected Sound(s): select at least one Sound object."
    endif
    for i to nSel
        selSound[i] = selected ("Sound", i)
    endfor
endif

# ---- Plugin root ----
pluginRoot$ = ""
cand1$ = preferencesDirectory$ + "/plugin_AudioTools"
cand2$ = defaultDirectory$ + "/.."
cand3$ = defaultDirectory$
for i to 3
    c$ = cand'i'$
    if pluginRoot$ = "" and fileReadable (c$ + "/" + tRel$[1])
        pluginRoot$ = c$
    endif
endfor
pluginRoot$ = replace_regex$ (pluginRoot$, "[/\\][^/\\]+[/\\]\.\.$", "", 0)
if pluginRoot$ = ""
    exitScript: "Cannot find the AudioTools plugin root (looked for " + tRel$[1] + ") in:" + newline$
        ... + cand1$ + newline$ + cand2$ + newline$ + cand3$
endif
missing$ = ""
for i to nT
    tPath$[i] = pluginRoot$ + "/" + tRel$[i]
    if not fileReadable (tPath$[i])
        missing$ = missing$ + "  " + tPath$[i] + newline$
    endif
endfor

pyScript$ = pluginRoot$ + "/py/audiotools_call_response.py"
if not fileReadable (pyScript$)
    pyScript$ = defaultDirectory$ + "/audiotools_call_response.py"
endif
if not fileReadable (pyScript$)
    exitScript: "Cannot find audiotools_call_response.py in " + pluginRoot$ + "/py/ or next to this script."
endif

# ---- Session folder: RAM-backed where available, never the home folder ----
base$ = ""
if unix and folderExists ("/dev/shm")
    base$ = "/dev/shm"
endif
if base$ = "" and windows
    base$ = environment$ ("TEMP")
endif
if base$ = ""
    base$ = environment$ ("TMPDIR")
endif
if base$ = "" and not windows
    base$ = "/tmp"
endif
if base$ = "" or not folderExists (base$)
    base$ = temporaryDirectory$
endif
base$ = replace_regex$ (base$, "[/\\]+$", "", 0)
sessionId$ = replace_regex$ (date$ (), "[^0-9]", "", 0) + "_" + string$ (randomInteger (1000, 9999))
session$ = base$ + "/AudioTools_CR_" + sessionId$
createFolder: session$
if not folderExists (session$)
    exitScript: "Cannot create the session folder " + session$
endif

# ---- Native MDS visualization control: fail closed on older installations ----
# MDS Space Navigator v0.4.1 has a trailing Draw_visualization boolean.
# Do not invoke older MDS scripts: they always draw in the Picture window.
mdsSupportsHeadless = 0
if fileReadable (tPath$[3])
    mdsText$ = readFile$ (tPath$[3])
    if index (mdsText$, "boolean Draw_visualization 1") > 0
        mdsSupportsHeadless = 1
    endif
endif

# ---- Python discovery (no shell; file-based probe) ----
nPy = 0
if pyCandidate1$ <> ""
    nPy += 1
    pyC$[nPy] = pyCandidate1$
endif
if macintosh
    nPy += 1
    pyC$[nPy] = "/opt/homebrew/bin/python3"
    nPy += 1
    pyC$[nPy] = "/usr/local/bin/python3"
    nPy += 1
    pyC$[nPy] = "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"
    nPy += 1
    pyC$[nPy] = "python3"
elsif windows
    nPy += 1
    pyC$[nPy] = "python"
    nPy += 1
    pyC$[nPy] = "py"
    nPy += 1
    pyC$[nPy] = "python3"
else
    nPy += 1
    pyC$[nPy] = "python3"
    nPy += 1
    pyC$[nPy] = "python"
endif

probe$ = session$ + "/probe.txt"
python$ = ""
probeReport$ = ""
liveFlag$ = if source <> 2 then "--live" else "" fi
for i to nPy
    if python$ = ""
        p$ = pyC$[i]
        isBare = p$ = "python" or p$ = "python3" or p$ = "py"
        if isBare or fileReadable (p$)
            if fileReadable (probe$)
                deleteFile: probe$
            endif
            if liveFlag$ = ""
                nocheck runSubprocess: p$, pyScript$, "probe", "--out", probe$
            else
                nocheck runSubprocess: p$, pyScript$, "probe", "--out", probe$, liveFlag$
            endif
            if fileReadable (probe$)
                pr$ = newline$ + readFile$ (probe$)
                st$ = extractLine$ (pr$, newline$ + "status=")
                if st$ = "ok"
                    python$ = p$
                else
                    probeReport$ = probeReport$ + "  " + p$ + ": missing "
                        ... + extractLine$ (pr$, newline$ + "missing=") + newline$
                endif
            endif
        endif
    endif
endfor
if python$ = ""
    @cleanup
    exitScript: "No usable Python found." + newline$ + probeReport$
        ... + "Install: pip install numpy scipy soundfile sounddevice" + newline$
        ... + "or set pyCandidate1$ at the top of this script."
endif

# ---- Device list mode ----
if source = 3
    devFile$ = session$ + "/devices.txt"
    nocheck runSubprocess: python$, pyScript$, "devices", "--out", devFile$
    if fileReadable (devFile$)
        writeInfoLine: readFile$ (devFile$)
    else
        writeInfoLine: "Device query failed - is sounddevice / PortAudio installed?"
    endif
    @cleanup
    exitScript: ""
endif

nocheck runSubprocess: python$, pyScript$, "cleanup-stale", "--base", base$

# ============================================================
# PERFORMER DISPLAY: two lines maximum, always the current state.
# Child scripts may write verbose Info messages; restore this text after
# their runScript returns.  Detailed reports are never printed by default.
# ============================================================
log$ = ""
currentStatus$ = "AudioTools Call & Response"
procedure log: .line$
    log$ = log$ + .line$ + newline$
endproc
procedure status: .stage$, .detail$
    currentStatus$ = "AudioTools  |  " + string$ (cyc) + "/" + string$ (nTurns)
        ... + "  |  " + .stage$
    if .detail$ <> ""
        currentStatus$ = currentStatus$ + newline$ + .detail$
    endif
    writeInfoLine: currentStatus$
endproc
procedure restoreInfo
    writeInfoLine: currentStatus$
endproc

procedure cleanup
    if folderExists (session$)
        if python$ <> ""
            nocheck runSubprocess: python$, pyScript$, "cleanup", "--session", session$
        elsif fileReadable (probe$)
            deleteFile: probe$
        endif
    endif
endproc

procedure now
    if hasClock
        .t = clock ()
    else
        .t = undefined
    endif
endproc

procedure fmt: .v, .nd
    if .v = undefined
        .s$ = "n/a"
    else
        .s$ = fixed$ (.v, .nd)
    endif
endproc

# ---- metadata access: meta$ holds the decision file, newline-prefixed ----
procedure getStr: .key$
    .v$ = extractLine$ (meta$, newline$ + .key$ + "=")
endproc

# numeric parameter, validated and clamped against the child's own limits
procedure num: .key$, .default, .lo, .hi
    @getStr: .key$
    .v = number (getStr.v$)
    if .v = undefined
        .v = .default
        clampNotes$ = clampNotes$ + .key$ + " missing->" + string$ (.default) + "  "
    elsif .v < .lo or .v > .hi
        .old = .v
        .v = min (.hi, max (.lo, .v))
        clampNotes$ = clampNotes$ + .key$ + " " + string$ (.old) + "->" + string$ (.v) + "  "
    endif
endproc

procedure s: .v
    .s$ = fixed$ (.v, 6)
endproc

# ============================================================
# RUN ONE TRANSFORMATION  (whitelisted index .k on Sound .src)
#   sets runT.result (0 = failed), runT.msg$, runT.sec
# ============================================================
procedure runT: .k, .src, .tag$
    .result = 0
    .msg$ = ""
    .sec = 0
    .bail = 0
    .haveWork = 0
    clampNotes$ = ""
    .id$ = tId$[.k]
    if not fileReadable (tPath$[.k])
        .msg$ = "script missing: " + tPath$[.k]
        .bail = 1
    elsif .id$ = "mds" and not mdsSupportsHeadless
        .msg$ = "MDS v0.4.1+ required (Draw_visualization toggle is missing)"
        .bail = 1
    endif

    # ---- work copy with a unique name (child output names derive from it) ----
    if .bail = 0
        selectObject: .src
        .srcDur = Get total duration
        .srcSR = Get sampling frequency
        .workName$ = "crin_" + .tag$ + "_" + .id$
        .work = Copy: .workName$
        .haveWork = 1
        @num: "seed", 1, 1, 2000000000
        .seed = round (num.v)
    endif

    # ---- per-script argument build (exact form order, verified in source) ----
    if .bail = 0 and .id$ = "paulstretch"
        @num: "p_paulstretch_crop_start", 0, 0, .srcDur
        .c0 = num.v
        @num: "p_paulstretch_crop_end", .srcDur, 0, .srcDur
        .c1 = num.v
        if .c1 - .c0 > 0.3 and (.c0 > 0.001 or .c1 < .srcDur - 0.001)
            selectObject: .work
            .tmp = Extract part: .c0, .c1, "rectangular", 1, "no"
            removeObject: .work
            .work = .tmp
            Rename: .workName$
            clampNotes$ = clampNotes$ + "input cropped to " + fixed$ (.c0, 2) + "-" + fixed$ (.c1, 2) + " s  "
        endif
        @num: "p_paulstretch_stretch", 4, 1.25, 6
        @s: num.v
        .a3$ = s.s$
        @num: "p_paulstretch_window", 0.25, 0.05, 1
        @s: num.v
        .a4$ = s.s$
        @num: "p_paulstretch_overlap", 75, 50, 90
        @s: num.v
        .a5$ = s.s$
        @num: "p_paulstretch_stereo", 1, 0, 1
        .a6$ = string$ (round (num.v))
        @num: "p_paulstretch_phase_offset", 0.3, 0, 1
        @s: num.v
        .a7$ = s.s$
        .args$ = "Custom | Balanced (downsample to 22 kHz) | " + .a3$ + " | " + .a4$
            ... + " | " + .a5$ + " | " + .a6$ + " | " + .a7$ + " | 0 | 0"
    elsif .bail = 0 and .id$ = "markov"
        @num: "p_markov_grain_ms", 80, 20, 200
        .g = num.v
        @num: "p_markov_states", 5, 2, 8
        .kk = round (num.v)
        # script rules: duration >= 4 grains, nGrains >= 2 x states
        if .srcDur < 4 * .g / 1000
            .g = 1000 * .srcDur / 4 * 0.95
            clampNotes$ = clampNotes$ + "grain shortened to " + fixed$ (.g, 1) + " ms  "
        endif
        .nG = floor ((.srcDur - .g / 1000) / (.g / 1000 * 0.5)) + 1
        while .kk > 2 and .nG < 2 * .kk
            .kk -= 1
        endwhile
        if .nG < 2 * .kk or .g < 20
            .msg$ = "phrase too short for Markov analysis (" + string$ (.nG) + " grains)"
            .bail = 1
        endif
        @num: "p_markov_randomness", 0.2, 0, 1
        @s: num.v
        .rnd$ = s.s$
        @num: "p_markov_out_dur", 8, 1, 20
        @s: num.v
        .od$ = s.s$
        @num: "p_markov_density_var", 0, 0, 1
        @s: num.v
        .dv$ = s.s$
        @num: "p_markov_decorrelation", 0.3, -1, 1
        @s: num.v
        .dc$ = s.s$
        @s: .g
        .gs$ = s.s$
        .args$ = "Manual | " + .gs$ + " | 0.5 | " + string$ (.kk) + " | First Order | "
            ... + .rnd$ + " | " + .od$ + " | 0.5 | 0 | 0.1 | " + .dv$ + " | " + .dc$
            ... + " | " + string$ (.seed) + " | 0 | 0"
    elsif .bail = 0 and .id$ = "mds"
        @num: "p_mds_silence_threshold_db", 25, 5, 60
        @s: num.v
        .th$ = s.s$
        @num: "p_mds_min_silent", 0.1, 0.02, 1
        @s: num.v
        .ms$ = s.s$
        @num: "p_mds_min_sounding", 0.1, 0.02, 1
        @s: num.v
        .mn$ = s.s$
        @num: "p_mds_between", 0.1, 0.01, 1
        @s: num.v
        .bw$ = s.s$
        .args$ = .th$ + " | " + .ms$ + " | " + .mn$ + " | MFCC (Timbre/Spectral Shape) | 5500 | 5 | 12"
            ... + " | Nearest neighbor chain (most similar next) | " + .bw$ + " | 0 | 0"
    elsif .bail = 0 and .id$ = "spiral"
        @num: "p_spiral_spirals", 2, 1, 3
        .sp$ = string$ (round (num.v))
        @num: "p_spiral_semitones", 6, 3, 12
        @s: num.v
        .st$ = s.s$
        @num: "p_spiral_acceleration", 1.5, 1, 2
        @s: num.v
        .ac$ = s.s$
        @num: "p_spiral_floor", 75, 50, 400
        .fl = num.v
        @num: "p_spiral_ceiling", 800, 100, 1200
        .ce = min (num.v, 0.449 * .srcSR)
        if .ce <= .fl * 1.5
            .ce = min (0.449 * .srcSR, .fl * 4)
        endif
        @s: .fl
        .fl$ = s.s$
        @s: .ce
        .ce$ = s.s$
        .args$ = "Manual (configure below) | " + .sp$ + " | " + .st$ + " | " + .ac$
            ... + " | 0.005 | " + .fl$ + " | " + .ce$ + " | 0 | 0"
    elsif .bail = 0 and .id$ = "metamod"
        @num: "p_metamod_carrier", 200, 20, 0.45 * .srcSR
        @s: num.v
        .ca$ = s.s$
        @num: "p_metamod_depth_hz", 100, 0, 2000
        @s: num.v
        .de$ = s.s$
        @num: "p_metamod_rate_hz", 2, 0.5, 8
        @s: num.v
        .ra$ = s.s$
        @num: "p_metamod_dry_wet", 40, 15, 60
        @s: num.v
        .dw$ = s.s$
        .args$ = "Custom (Use Manual Settings) | 5. Sinusoidal FM | " + .ca$ + " | 100 | 800 | "
            ... + .de$ + " | " + .ra$ + " | " + .dw$ + " | 0.99 | 0 | 0 | 0"
    elsif .bail = 0 and .id$ = "groove"
        @num: "p_groove_bars", 2, 1, 4
        .b = round (num.v)
        .bars$ = if .b = 1 then "1 bar" else if .b = 2 then "2 bars" else "4 bars" fi fi
        @getStr: "p_groove_pattern"
        .pat$ = getStr.v$
        if .pat$ <> "Standard 4/4" and .pat$ <> "Syncopated Funk" and .pat$ <> "Breakbeat"
            ... and .pat$ <> "Half-time Feel" and .pat$ <> "Double-time Feel" and .pat$ <> "Sparse Minimal"
            clampNotes$ = clampNotes$ + "pattern '" + .pat$ + "' not allowed -> Standard 4/4  "
            .pat$ = "Standard 4/4"
        endif
        @num: "p_groove_tempo", 100, 60, 180
        @s: num.v
        .te$ = s.s$
        @num: "p_groove_onset_thr_db", -20, -40, 0
        @s: num.v
        .ot$ = s.s$
        @num: "p_groove_min_silence", 0.05, 0.02, 0.2
        @s: num.v
        .si$ = s.s$
        @num: "p_groove_density", 0.6, 0, 1
        @s: num.v
        .dn$ = s.s$
        .args$ = .bars$ + " | " + .pat$ + " | " + .te$ + " | " + .ot$ + " | " + .si$
            ... + " | 0.15 | " + .dn$ + " | 0.12 | 0.002 | 0.05 | 1.2 | 1 | 0 | 0"
    endif

    if .bail = 0
        if diagnostics
            @log: "    " + .id$ + " args: " + .args$
        endif
        if clampNotes$ <> ""
            @log: "    validated: " + clampNotes$
        endif
        # watermark: every object the child creates has a higher id
        .mark = Create Sound from formula: "crmark", 1, 0, 0.001, 1000, "0"
        removeObject: .mark
        random_initializeWithSeedUnsafelyButPredictably (.seed)
        selectObject: .work
        @now
        .t0 = now.t
        if .id$ = "paulstretch"
            nocheck runScript: tPath$[.k], "Custom", "Balanced (downsample to 22 kHz)",
                ... .a3$, .a4$, .a5$, .a6$, .a7$, "0", "0"
        elsif .id$ = "markov"
            nocheck runScript: tPath$[.k], "Manual", .gs$, "0.5", string$ (.kk), "First Order",
                ... .rnd$, .od$, "0.5", "0", "0.1", .dv$, .dc$, string$ (.seed), "0", "0"
        elsif .id$ = "mds"
            # Play_result = 0; Draw_visualization = 0 (11th argument).
            nocheck runScript: tPath$[.k], .th$, .ms$, .mn$, "MFCC (Timbre/Spectral Shape)",
                ... "5500", "5", "12", "Nearest neighbor chain (most similar next)", .bw$, "0", "0"
        elsif .id$ = "spiral"
            nocheck runScript: tPath$[.k], "Manual (configure below)", .sp$, .st$, .ac$,
                ... "0.005", .fl$, .ce$, "0", "0"
        elsif .id$ = "metamod"
            nocheck runScript: tPath$[.k], "Custom (Use Manual Settings)", "5. Sinusoidal FM",
                ... .ca$, "100", "800", .de$, .ra$, .dw$, "0.99", "0", "0", "0"
        elsif .id$ = "groove"
            nocheck runScript: tPath$[.k], .bars$, .pat$, .te$, .ot$, .si$, "0.15", .dn$,
                ... "0.12", "0.002", "0.05", "1.2", "1", "0", "0"
        endif
        @now
        .sec = if hasClock then now.t - .t0 else undefined fi
        random_initializeSafelyAndUnpredictably ()
        @restoreInfo

        # ---- identify the output: newer than the watermark AND named by
        #      this child from this work copy; everything else it left is removed
        .prefix$ = "Sound " + .workName$ + tStem$[.k]
        .found = 0
        select all
        .nAll = numberOfSelected ()
        for .i to .nAll
            .ids[.i] = selected (.i)
        endfor
        for .i to .nAll
            if .ids[.i] > .mark
                selectObject: .ids[.i]
                .nm$ = selected$ ()
                if left$ (.nm$, length (.prefix$)) = .prefix$ and .ids[.i] > .found
                    .found = .ids[.i]
                endif
            endif
        endfor
        .leftovers = 0
        for .i to .nAll
            if .ids[.i] > .mark and .ids[.i] <> .found
                removeObject: .ids[.i]
                .leftovers += 1
            endif
        endfor
        if .leftovers > 0
            @log: "    removed " + string$ (.leftovers) + " object(s) left by the child script"
        endif
        removeObject: .work
        .haveWork = 0

        if .found = 0
            .msg$ = "no output Sound named " + .workName$ + tStem$[.k] + "... (the script stopped with an error)"
        else
            selectObject: .found
            .dur = Get total duration
            .rms = Get root-mean-square: 0, 0
            .pk = Get absolute extremum: 0, 0, "None"
            if .dur <= 0 or .rms = undefined or .pk = undefined
                .msg$ = "output is invalid"
                removeObject: .found
            elsif .rms < 1e-5
                .msg$ = "output is silent (rms " + fixed$ (.rms, 7) + ")"
                removeObject: .found
            else
                .result = .found
                .msg$ = "ok " + fixed$ (.dur, 2) + " s, rms " + fixed$ (20 * log10 (.rms), 1) + " dBFS"
            endif
        endif
    endif
    if .haveWork
        removeObject: .work
    endif
endproc

# ============================================================
# ONE TURN: load phrase, run the chosen transformation(s), play
# (uses the session globals; called once per question)
# ============================================================
procedure turn
    # ---- load phrase (the musician's audio is kept, never modified) ----
    if source = 1
        phrase = Read from file: qwav$
        Rename: "crq_" + tag$
    else
        selectObject: selSound[cyc]
        phrase = Copy: "crq_" + tag$
    endif
    selectObject: phrase
    qDur = Get total duration
    @log: "Phrase " + fixed$ (qDur, 2) + " s   " + extractLine$ (meta$, newline$ + "morphology=")
    if source = 1
        @log: "  ended by " + extractLine$ (meta$, newline$ + "ended_by=") + ", noise floor "
            ... + extractLine$ (meta$, newline$ + "noise_floor_dbfs=") + " dBFS, false triggers "
            ... + extractLine$ (meta$, newline$ + "false_triggers=")
    endif
    # Detailed report remains a Python-side artifact; do not flood the performer UI.

    # ---- which transformations to run ----
    sel$ = extractLine$ (meta$, newline$ + "selected=")
    ranking$ = extractLine$ (meta$, newline$ + "ranking=")
    nRun = 0
    if sweep
        for k to nT
            nRun += 1
            runK[nRun] = k
        endfor
    else
        selK = 0
        for k to nT
            if sel$ = tId$[k]
                selK = k
            endif
        endfor
        if selK > 0
            nRun = 1
            runK[1] = selK
        endif
    endif
    ambiguous$ = extractLine$ (meta$, newline$ + "ambiguous=")
    if ambiguous$ <> "" and not diagnostics
        @log: "  ambiguous decision: " + ambiguous$
    endif
    warning$ = extractLine$ (meta$, newline$ + "warning=")
    if warning$ <> ""
        @log: "  " + warning$
    endif

    # ---- answer(s) ----
    for r to max (nRun, 1)
        answer = 0
        usedId$ = "passthrough"
        praatSec = 0
        if nRun = 0
            @log: "No transformation reached its confidence threshold - answering with the phrase itself."
        else
            k = runK[r]
            @getStr: "score_" + tId$[k]
            @log: "TRANSFORMING with " + tId$[k] + " (score " + getStr.v$ + ")"
            @status: "PROCESSING", tDisplay$[k]
            @runT: k, phrase, tag$
            praatSec = runT.sec
            @log: "  " + tId$[k] + ": " + runT.msg$
            if runT.result
                answer = runT.result
                usedId$ = tId$[k]
            elsif transformation = 1
                # automatic mode: next eligible candidate above threshold, logged
                rest$ = ranking$ + ","
                tried = 0
                while answer = 0 and rest$ <> ""
                    c = index (rest$, ",")
                    cand$ = left$ (rest$, c - 1)
                    rest$ = mid$ (rest$, c + 1, length (rest$) - c)
                    kk = 0
                    for k2 to nT
                        if cand$ = tId$[k2] and cand$ <> tId$[k]
                            kk = k2
                        endif
                    endfor
                    if kk > 0 and tried = 0
                        tried = 1
                        @log: "FALLBACK: " + tId$[k] + " failed, trying runner-up " + tId$[kk]
                        @status: "PROCESSING", tDisplay$[kk]
                        @runT: kk, phrase, tag$ + "b"
                        praatSec = praatSec + runT.sec
                        @log: "  " + tId$[kk] + ": " + runT.msg$
                        if runT.result
                            answer = runT.result
                            usedId$ = tId$[kk]
                        endif
                    endif
                endwhile
            endif
            if answer = 0 and not sweep
                @log: "No valid output - answering with the untransformed phrase (logged fallback)."
            endif
        endif
        if answer = 0 and sweep
            # test sweep: a failed pairing is reported, not answered
            @log: "  (no answer object for " + tId$[k] + ")"
            summary$ = summary$ + "  " + tag$ + "  " + tId$[k] + "   FAILED: " + runT.msg$ + newline$
        else
            if answer = 0
                selectObject: phrase
                answer = Copy: "cra_" + tag$ + "_passthrough"
            else
                selectObject: answer
                Rename: "cra_" + tag$ + "_" + usedId$
            endif
            selectObject: answer
            aDur = Get total duration

            # ---- timing ----
            @now
            tPlay = now.t
            tEnd = number (extractLine$ (meta$, newline$ + "t_phrase_end_epoch="))
            tWritten = number (extractLine$ (meta$, newline$ + "t_written_epoch="))
            detect = number (extractLine$ (meta$, newline$ + "t_detect_delay="))
            pyFeat = number (extractLine$ (meta$, newline$ + "t_features="))
            pySel = number (extractLine$ (meta$, newline$ + "t_select="))
            total = undefined
            handoff = undefined
            if hasClock and tEnd <> undefined
                if abs (tPlay - tEnd) < 3600
                    total = tPlay - tEnd
                endif
            endif
            if hasClock and tWritten <> undefined
                if abs (tBack - tWritten) < 3600
                    handoff = tBack - tWritten
                endif
            endif
            @fmt: detect, 3
            d$ = fmt.s$
            @fmt: pyFeat + pySel, 3
            p$ = fmt.s$
            @fmt: praatSec, 2
            q$ = fmt.s$
            @fmt: handoff, 3
            h$ = fmt.s$
            @fmt: total, 2
            tt$ = fmt.s$
            @log: "Timing: end detection " + d$ + " s | python analysis " + p$ + " s | python exit "
                ... + h$ + " s | Praat render " + q$ + " s | phrase end -> answer " + tt$ + " s"
            nDone += 1
            summary$ = summary$ + "  " + tag$ + "  " + usedId$ + "   in " + fixed$ (qDur, 2) + " s -> out "
                ... + fixed$ (aDur, 2) + " s   delay " + tt$ + " s" + newline$

            if play_response
                # The final chosen process can differ from the first candidate.
                .chosenName$ = "Original phrase"
                for .p to nT
                    if usedId$ = tId$[.p]
                        .chosenName$ = tDisplay$[.p]
                    endif
                endfor
                @status: "PLAYING", .chosenName$ + "  (" + fixed$ (aDur, 1) + " s)"
                selectObject: answer
                Play
            endif
        endif
    endfor
endproc

# ============================================================
# SESSION
# ============================================================
clearinfo
@log: "=== AudioTools Call & Response " + version$ + " ==="
if transformation = 1
    modeName$ = "automatic"
elsif sweep
    modeName$ = "test all six"
else
    modeName$ = "manual: " + tId$[transformation - 1]
endif
srcName$ = if source = 1 then "live microphone" else "selected Sound(s)" fi
@log: "Source: " + srcName$ + "   Mode: " + modeName$ + "   Python: " + python$
@log: "Plugin: " + pluginRoot$
@log: "Session: " + session$
if missing$ <> ""
    @log: "WARNING - missing processing scripts:" + newline$ + missing$
endif
if source = 1
    @log: "Listening: " + fixed$ (sample_rate, 0) + " Hz, " + string$ (channels) + " ch, device '"
        ... + input_device$ + "', sensitivity " + fixed$ (sensitivity_dB, 1) + " dB, end silence "
        ... + fixed$ (end_silence_s, 2) + " s, phrase " + fixed$ (min_phrase_s, 2) + "-"
        ... + fixed$ (max_phrase_s, 1) + " s, timeout " + string$ (waitTimeout) + " s"
    nTurns = cycles
else
    nTurns = nSel
endif
if not hasClock
    @log: "(Praat < 6.4.34: no clock(), so Praat-side timings are not reported)"
endif
summary$ = ""
nDone = 0

cyc = 0
stopSession = 0
while cyc < nTurns and not stopSession
    cyc += 1
    tag$ = right$ ("00" + string$ (cyc), 3)
    decision$ = session$ + "/decision_" + tag$ + ".txt"
    report$ = session$ + "/report_" + tag$ + ".txt"
    qwav$ = session$ + "/q_" + tag$ + ".wav"
    force$ = "auto"
    if transformation >= 2 and transformation <= 7
        force$ = tId$[transformation - 1]
    endif
    @log: ""
    @log: "--- Turn " + string$ (cyc) + " / " + string$ (nTurns) + " ---"

    # ---- question ----
    if source = 1
        @status: "LISTENING", "Play a phrase"
        @log: "LISTENING... play a phrase (the Praat window is frozen until it ends)"
        nocheck runSubprocess: python$, pyScript$, "listen", "--session", session$,
            ... "--cycle", string$ (cyc), "--force", force$, "--device", input_device$,
            ... "--sr", fixed$ (sample_rate, 0), "--channels", string$ (channels),
            ... "--sensitivity", fixed$ (sensitivity_dB, 3), "--min-phrase", fixed$ (min_phrase_s, 3),
            ... "--end-silence", fixed$ (end_silence_s, 3), "--max-phrase", fixed$ (max_phrase_s, 3),
            ... "--preroll", fixed$ (preroll, 3), "--timeout", string$ (waitTimeout)
    else
        selectObject: selSound[cyc]
        qName$ = selected$ ("Sound")
        Save as 32-bit WAV file: qwav$
        @status: "ANALYZING", qName$
        @log: "Analysing selected Sound '" + qName$ + "'"
        nocheck runSubprocess: python$, pyScript$, "analyze", "--session", session$,
            ... "--cycle", string$ (cyc), "--force", force$, "--input", qwav$
    endif
    @now
    tBack = now.t

    # ---- decision ----
    status$ = "missing"
    if fileReadable (decision$)
        meta$ = newline$ + readFile$ (decision$)
        if extractLine$ (meta$, newline$ + "end=") = "1"
            status$ = extractLine$ (meta$, newline$ + "status=")
        else
            status$ = "incomplete"
        endif
    endif
    turnOk = 1
    if status$ = "missing" or status$ = "incomplete"
        @log: "Python terminated unexpectedly (decision file " + status$ + ")."
        @status: "ERROR", "Python did not return a valid decision"
        turnOk = 0
        stopSession = 1
    elsif status$ <> "ok"
        @log: "Python: " + status$ + " - " + extractLine$ (meta$, newline$ + "message=")
        @status: "STOPPED", status$
        turnOk = 0
        # live: timeout / silent input / device error end the session safely;
        # selected Sounds: skip this one and continue with the next
        if source = 1
            stopSession = 1
        endif
    endif
    if turnOk
        @status: "SELECTING", "Choosing transformation"
        @turn
        if nRun = 0
            @status: "READY", "Original phrase (no matching transformation)"
        else
            readyName$ = "Original phrase"
            for readyIx to nT
                if usedId$ = tId$[readyIx]
                    readyName$ = tDisplay$[readyIx]
                endif
            endfor
            @status: "READY", readyName$
        endif
    endif
endwhile

@log: ""
@log: "=== Session summary: " + string$ (nDone) + " answer(s) ==="
@log: "Objects: crq_NNN = recorded questions, cra_NNN_<transformation> = answers."
@cleanup
if nDone > 0 and not stopSession
    @status: "DONE", string$ (nDone) + " response(s) completed"
elsif nDone = 0 and not stopSession
    @status: "DONE", "No response generated"
endif
