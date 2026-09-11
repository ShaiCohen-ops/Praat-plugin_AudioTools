# ============================================================
# Praat AudioTools - DDSPNeuralDrawingSynthesizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Draw a musical gesture - a PITCH curve and a LOUDNESS curve on a shared
#   time axis - in Praat's Demo window, and let a pretrained Magenta DDSP
#   solo-instrument model (Violin, Flute, Flute2, Trumpet, Tenor Saxophone)
#   give it a sounding body. No input Sound is needed: the drawn curves are
#   fed to the model directly as its f0_hz / loudness_db conditioning.
#
#   DRAWING -> CONTROL REPRESENTATION -> TRANSFORMATION -> DDSP -> SOUND
#
#   Praat is the whole user interface. ddsp_neural_drawing_engine.py turns
#   the gesture into DDSP frames and renders it, reusing the model cache,
#   download and inference code of ddsp_neural_revoicing_engine.py (both
#   files must sit together in plugin_AudioTools/py/).
#
# How to draw:
#   Praat's Demo window reports mouse CLICKS only - it does not report mouse
#   motion while a button is held, so true freehand dragging is impossible
#   in any Praat window a script can control. Drawing is therefore
#   click-to-draw: each click adds a breakpoint and consecutive clicks in the
#   same panel form one stroke, joined by a straight line (linear in
#   semitones for pitch, in dB for loudness). A continuing stroke REPLACES
#   whatever was drawn between its clicks, so redrawing a passage is just
#   clicking over it. "Lift pen" (space bar) makes the next click start a
#   new stroke with a gap: a silence in the loudness panel, a leap in the
#   pitch panel. Pitch/Loudness smoothing then rounds the corners.
#
# Setup note:
#   The same Python as DDSP Neural Revoicing is used (TensorFlow + ddsp +
#   crepe; ddsp imports crepe itself even though CREPE is never run here).
#   candidate1$ below is tried first, then common per-OS locations. A Python
#   that has numpy but not DDSP is still accepted for Preview and drawing.
#   Model cache: preferencesDirectory$/ddsp_cache (shared with Revoicing).
#
# Honest limitations:
#   - Preview is a plain additive tone that follows the processed curves -
#     it auditions the GESTURE, not the instrument. Only Synthesize runs the
#     neural model, and that is not real time (model load + inference take
#     seconds).
#   - The models were trained on real solo recordings; curves drawn far
#     outside an instrument's range still render, with degraded timbre.
#   - The model synthesizes at 16 kHz; higher output rates add nothing
#     above ~8 kHz. The output is exactly as long as the canvas, so the
#     model's reverb tail is cut at the end - finish the loudness curve a
#     little before the right edge.
#
# Changelog v0.1:
#   - Initial release.
# ============================================================

form DDSP Neural Drawing Synthesizer
    optionmenu Start_from: 1
        option Blank canvas
        option Last gesture
        option Gesture file...
        option Example gesture
    positive Duration_s 5.0
    optionmenu Model: 1
        option Violin
        option Flute
        option Flute2
        option Trumpet
        option Tenor Saxophone
    optionmenu Drawing_mode: 1
        option Pitch + Loudness curves
        option Single gesture (experimental)
    positive Pitch_minimum_Hz 80
    positive Pitch_maximum_Hz 1200
    real Loudness_minimum_dB -80
    real Loudness_maximum_dB -15
    optionmenu Pitch_mode: 1
        option Continuous
        option Chromatic
        option Major
        option Minor
        option Pentatonic
    real Pitch_smoothing_percent 10
    real Loudness_smoothing_percent 10
    real Silence_threshold_dB -70
    optionmenu Output_level: 1
        option Match drawn loudness
        option Peak normalize (~0.95)
        option Raw (model level)
    boolean Play_result 1
    boolean Advanced_settings 0
endform

# ---- VALIDATION ----
if duration_s < 0.25 or duration_s > 120
    exitScript: "Duration must be between 0.25 and 120 s."
endif
if pitch_minimum_Hz < 20 or pitch_maximum_Hz > 5000 or pitch_minimum_Hz * 1.25 > pitch_maximum_Hz
    exitScript: "Pitch range must lie within 20-5000 Hz and span at least a major third."
endif
if loudness_minimum_dB < -120 or loudness_maximum_dB > 0 or loudness_minimum_dB + 6 > loudness_maximum_dB
    exitScript: "Loudness range must lie within -120..0 dB and span at least 6 dB."
endif
if pitch_smoothing_percent < 0 or pitch_smoothing_percent > 100 or loudness_smoothing_percent < 0 or loudness_smoothing_percent > 100
    exitScript: "Smoothing values are percentages (0-100)."
endif

# ---- ADVANCED SETTINGS (second dialog keeps the main form short) ----
# Initialised BEFORE the pause: on builds where a headless pause
# auto-continues, the fields would otherwise never be assigned.
scale_root$ = "C"
glide_ms = 30
edge_taper_ms = 15
tail_release_ms = 1200
motion_depth_dB = 25
transforms$ = ""
output_sample_rate = 44100
pitch_guides = 1
output_name$ = "DDSP_Drawing"
keep_temp_files = 0
if advanced_settings
    beginPause: "DDSP Drawing - advanced settings"
        comment: "Scale root for Major / Minor / Pentatonic (C, F#, Bb ...)"
        word: "Scale_root", scale_root$
        positive: "Glide_ms", string$(glide_ms)
        positive: "Edge_taper_ms", string$(edge_taper_ms)
        real: "Tail_release_ms", string$(tail_release_ms)
        positive: "Motion_depth_dB", string$(motion_depth_dB)
        comment: "Transforms, ; separated: transpose 12; invert; retrograde;"
        comment: "contour 0.5; vibrato 5.5 30; perturb 20 1   (blank = none)"
        sentence: "Transforms", transforms$
        positive: "Output_sample_rate", string$(output_sample_rate)
        choice: "Pitch_guides", pitch_guides
            option: "Note names"
            option: "MIDI numbers"
            option: "Hz"
        word: "Output_name", output_name$
        boolean: "Keep_temp_files", keep_temp_files
    endPause: "Continue", 1
endif

# Praat 7 refuses file writes, deletes and subprocesses without full trust.
if praatVersion >= 7000
    if not askForTrust ()
        exitScript: "This script needs permission to write temporary files and run Python."
    endif
endif

# ---- CONSTANTS ----
modelKey$ [1] = "Violin"
modelKey$ [2] = "Flute"
modelKey$ [3] = "Flute2"
modelKey$ [4] = "Trumpet"
modelKey$ [5] = "Tenor_Saxophone"
modelShow$ [1] = "Violin"
modelShow$ [2] = "Flute"
modelShow$ [3] = "Flute 2"
modelShow$ [4] = "Trumpet"
modelShow$ [5] = "Tenor Sax"
modeKey$ [1] = "continuous"
modeKey$ [2] = "chromatic"
modeKey$ [3] = "major"
modeKey$ [4] = "minor"
modeKey$ [5] = "pentatonic"
modeShow$ [1] = "Continuous"
modeShow$ [2] = "Chromatic"
modeShow$ [3] = "Major"
modeShow$ [4] = "Minor"
modeShow$ [5] = "Pentatonic"
levelKey$ [1] = "match"
levelKey$ [2] = "peak"
levelKey$ [3] = "raw"
@setScale: 3, "0 2 4 5 7 9 11"
@setScale: 4, "0 2 3 5 7 8 10"
@setScale: 5, "0 2 4 7 9"

# Canvas geometry (Demo window world coordinates, 0..100 both ways)
cx0 = 8.5
cx1 = 97.5
pY0 = 55
pY1 = 90
lY0 = 25
lY1 = 49
colPitch$ = "{0.15, 0.35, 0.75}"
colLoud$ = "{0.75, 0.25, 0.15}"
colProc$ = "{0.95, 0.60, 0.10}"
colGrid$ = "{0.86, 0.87, 0.90}"
colGridStrong$ = "{0.74, 0.76, 0.82}"
colText$ = "{0.35, 0.37, 0.42}"
colPanel$ = "{0.995, 0.995, 1.0}"
colBack$ = "{0.94, 0.94, 0.94}"

dur = duration_s
pMin = pitch_minimum_Hz
pMax = pitch_maximum_Hz
lMin = loudness_minimum_dB
lMax = loudness_maximum_dB
modelIdx = model
modeIdx = pitch_mode
drawMode = drawing_mode
cN [1] = 0
cN [2] = 0
penLifted = 0
strokePanel = 0
strokeLastT = 0
strokeStartBreak = 0
ovValid = 0
ovN = 0
uTop = 0
uCount = 0
lastResult = 0
status$ = "Click in PITCH to draw, then in LOUDNESS. Space = lift pen, Z = undo."

# ---- PATHS ----
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
engine$ = pluginDir$ + "py/ddsp_neural_drawing_engine.py"
if not fileReadable (engine$)
    engine$ = defaultDirectory$ + "/ddsp_neural_drawing_engine.py"
endif
if not fileReadable (engine$)
    exitScript: "Cannot find ddsp_neural_drawing_engine.py." + newline$
        ... + "Expected at: " + pluginDir$ + "py/  or next to this script."
endif
cacheDir$ = preferencesDirectory$ + "/ddsp_cache/"
createDirectory: cacheDir$
lastGesture$ = cacheDir$ + "last_gesture.txt"
# temporaryDirectory$ can be the user's home folder on Windows, so keep the
# temp files in their own subfolder.
workDir$ = temporaryDirectory$ + "/praat_ddsp_drawing/"
createDirectory: workDir$
tempPrefix$ = "temp_ddsp_draw_"
tmpGesture$ = workDir$ + tempPrefix$ + "gesture.txt"
tmpControls$ = workDir$ + tempPrefix$ + "controls.tsv"
tmpPreview$ = workDir$ + tempPrefix$ + "sketch.wav"
tmpOutput$ = workDir$ + tempPrefix$ + "output.wav"
tmpStats$ = workDir$ + tempPrefix$ + "stats.txt"
tmpLog$ = workDir$ + tempPrefix$ + "pylog.txt"
tmpProbe$ = workDir$ + tempPrefix$ + "probe.py"
tmpProbeMark$ = workDir$ + tempPrefix$ + "probe.ok"
@cleanUpTempFiles

# ---- PYTHON INTERPRETER (same cascade as DDSP Neural Revoicing) ----
# Each candidate is probed. "full" = numpy + tensorflow + ddsp + crepe are
# installed (checked with importlib.util.find_spec, which locates packages
# WITHOUT importing TensorFlow, so the probe takes well under a second).
# "basic" = numpy only: enough for drawing, saving and Preview.
probeMarkJ$ = replace_regex$ (tmpProbeMark$, "\\", "/", 0)
writeFileLine: tmpProbe$, "import sys, importlib.util as u"
appendFileLine: tmpProbe$, "try:"
appendFileLine: tmpProbe$, "    import numpy"
appendFileLine: tmpProbe$, "except Exception:"
appendFileLine: tmpProbe$, "    sys.exit(1)"
appendFileLine: tmpProbe$, "full = all(u.find_spec(m) is not None for m in ('tensorflow', 'ddsp', 'crepe'))"
appendFileLine: tmpProbe$, "open(r'" + probeMarkJ$ + "', 'w').write('full' if full else 'basic')"

nCand = 1
candidate$ [1] = "C:/Users/user/praat_ddsp_env/Scripts/python.exe"
if macintosh
    nCand += 1
    candidate$ [nCand] = "/opt/homebrew/bin/python3"
    nCand += 1
    candidate$ [nCand] = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    nCand += 1
    candidate$ [nCand] = "/usr/local/bin/python3"
    nCand += 1
    candidate$ [nCand] = "python3"
elsif windows
    nCand += 1
    candidate$ [nCand] = "python"
    nCand += 1
    candidate$ [nCand] = "py"
else
    nCand += 1
    candidate$ [nCand] = "python3"
    nCand += 1
    candidate$ [nCand] = "python"
endif

python$ = ""
pythonBasic$ = ""
triedList$ = ""
for zc to nCand
    thisCand$ = candidate$ [zc]
    if python$ = ""
        triedList$ = triedList$ + "  - " + thisCand$ + newline$
        isBare = (thisCand$ = "python3") or (thisCand$ = "python") or (thisCand$ = "py")
        if isBare or fileReadable (thisCand$)
            if fileReadable (tmpProbeMark$)
                deleteFile: tmpProbeMark$
            endif
            nocheck runSubprocess: thisCand$, tmpProbe$
            if fileReadable (tmpProbeMark$)
                probeRes$ = readFile$ (tmpProbeMark$)
                if probeRes$ = "full"
                    python$ = thisCand$
                elsif pythonBasic$ = ""
                    pythonBasic$ = thisCand$
                endif
            endif
        endif
    endif
endfor
canSynth = python$ <> ""
if python$ = ""
    python$ = pythonBasic$
endif
canPreview = python$ <> ""
if fileReadable (tmpProbeMark$)
    deleteFile: tmpProbeMark$
endif
if fileReadable (tmpProbe$)
    deleteFile: tmpProbe$
endif

writeInfoLine: "=== DDSP Neural Drawing Synthesizer v0.1 ==="
if canSynth
    appendInfoLine: "Python:  ", python$
elsif canPreview
    appendInfoLine: "Python:  ", python$, "  (numpy only - Preview works, Synthesize does not)"
    appendInfoLine: "         No Python with tensorflow + ddsp + crepe was found. Tried:"
    appendInfo: triedList$
else
    appendInfoLine: "Python:  none found - you can draw and save gestures, but not"
    appendInfoLine: "         preview or synthesize. Tried:"
    appendInfo: triedList$
    appendInfoLine: "Fix: point candidate1$ at your DDSP venv (pip install tensorflow ddsp crepe)."
endif
appendInfoLine: "Engine:  ", engine$

# ---- INITIAL GESTURE ----
if start_from = 2
    if fileReadable (lastGesture$)
        @loadGesture: lastGesture$, 1
    else
        status$ = "No saved last gesture yet - starting blank."
    endif
elsif start_from = 3
    startFile$ = chooseReadFile$: "Open a DDSP drawing gesture"
    if startFile$ <> ""
        @loadGesture: startFile$, 1
    else
        status$ = "No file chosen - starting blank."
    endif
elsif start_from = 4
    @exampleGesture
endif

# ============================================================
# DRAWING LOOP
# ============================================================
demoWindowTitle: "DDSP Neural Drawing Synthesizer"
@redraw
while demoWaitForInput ()
    closing = 0
    if demoClicked ()
        mx = demoX ()
        my = demoY ()
        @handleClick: mx, my
    elsif demoKeyPressed ()
        @handleKey: demoKey$ ()
    endif
    if closing
        goto CLOSE
    endif
    @redraw
endwhile
label CLOSE

@autosaveGesture
if not keep_temp_files
    @cleanUpTempFiles
endif
status$ = "Closed. Rendered sounds are in the Objects window; the gesture is saved as Last gesture."
@redraw
if lastResult
    nocheck selectObject: lastResult
endif
appendInfoLine: ""
appendInfoLine: "Gesture autosaved to: ", lastGesture$
goto END

# ============================================================
# EVENTS
# ============================================================
procedure handleClick: .x, .y
    .hit = 0
    for .b to nButtons
        if .x >= bx0 [.b] and .x <= bx1 [.b] and .y >= 2.5 and .y <= 10.5
            .hit = .b
        endif
    endfor
    if .hit > 0
        @doButton: .hit
    elsif .x >= cx0 - 1.5 and .x <= cx1 + 1.5 and .y >= pY0 - 2 and .y <= pY1 + 2
        .t = max (0, min (dur, (.x - cx0) / (cx1 - cx0) * dur))
        .fr = max (0, min (1, (.y - pY0) / (pY1 - pY0)))
        .v = pMin * (pMax / pMin) ^ .fr
        @addPoint: 1, .t, .v
    elsif .x >= cx0 - 1.5 and .x <= cx1 + 1.5 and .y >= lY0 - 2 and .y <= lY1 + 2
        if drawMode = 2
            status$ = "Single-gesture mode: loudness is derived from the pitch line (G switches modes)."
        else
            .t = max (0, min (dur, (.x - cx0) / (cx1 - cx0) * dur))
            .fr = max (0, min (1, (.y - lY0) / (lY1 - lY0)))
            .v = lMin + .fr * (lMax - lMin)
            @addPoint: 2, .t, .v
        endif
    endif
endproc

procedure handleKey: .k$
    if .k$ = " "
        @doButton: 4
    elsif .k$ = "z" or .k$ = "Z"
        @doButton: 3
    elsif .k$ = "p" or .k$ = "P"
        @doButton: 8
    elsif .k$ = "s" or .k$ = "S"
        @doButton: 9
    elsif .k$ = "m" or .k$ = "M"
        @doButton: 1
    elsif .k$ = "k" or .k$ = "K"
        @doButton: 2
    elsif .k$ = "c" or .k$ = "C"
        @doButton: 5
    elsif .k$ = "q" or .k$ = "Q"
        @doButton: 10
    elsif .k$ = "g" or .k$ = "G"
        drawMode = 3 - drawMode
        ovValid = 0
        if drawMode = 2
            status$ = "Single-gesture mode: draw one pitch line; loudness follows its motion."
        else
            status$ = "Pitch + Loudness mode."
        endif
    endif
endproc

procedure doButton: .b
    if .b = 1
        modelIdx = modelIdx mod 5 + 1
        status$ = "Model: " + modelShow$ [modelIdx]
    elsif .b = 2
        modeIdx = modeIdx mod 5 + 1
        ovValid = 0
        status$ = "Pitch mode: " + modeShow$ [modeIdx]
    elsif .b = 3
        @popUndo
    elsif .b = 4
        penLifted = 1 - penLifted
        strokePanel = 0
        if penLifted
            status$ = "Pen lifted: the next click starts a new stroke (gap = silence / pitch leap)."
        else
            status$ = "Pen down."
        endif
    elsif .b = 5
        @pushUndo
        cN [1] = 0
        cN [2] = 0
        penLifted = 0
        strokePanel = 0
        ovValid = 0
        status$ = "Cleared (Z restores)."
    elsif .b = 6
        .f$ = chooseReadFile$: "Load a DDSP drawing gesture"
        if .f$ <> ""
            beginPause: "Load gesture"
                choice: "Load_what", 1
                    option: "Pitch and loudness (adopt its duration)"
                    option: "Pitch only (fitted to this canvas)"
                    option: "Loudness only (fitted to this canvas)"
            .clicked = endPause: "Cancel", "Load", 2
            if .clicked = 2
                @pushUndo
                @loadGesture: .f$, load_what
            endif
        endif
    elsif .b = 7
        .f$ = chooseWriteFile$: "Save the DDSP drawing gesture", "gesture.txt"
        if .f$ <> ""
            @writeGesture: .f$
            status$ = "Saved gesture: " + .f$
        endif
    elsif .b = 8
        @runPreview
    elsif .b = 9
        @runSynth
    elsif .b = 10
        closing = 1
    endif
endproc

# ============================================================
# EDITING (breakpoint arrays: cN [panel], cT/cV/cB [panel, i]; panel 1 =
# pitch in Hz, panel 2 = loudness in dB; cB = 1 means pen lifted before it)
# ============================================================
procedure addPoint: .p, .t, .v
    @pushUndo
    .snap = dur * 0.004
    if penLifted or strokePanel <> .p
        @deleteWhere: .p, .t - .snap, .t + .snap, -1
        .brk = penLifted
        @insertPoint: .p, .t, .v, .brk
        strokeStartBreak = .brk
        penLifted = 0
        strokeLastT = .t
    elsif abs (.t - strokeLastT) < .snap
        # Same spot as the previous click: move that point vertically.
        for .i to cN [.p]
            if abs (cT [.p, .i] - strokeLastT) < 1e-9
                cV [.p, .i] = .v
            endif
        endfor
    else
        # Also clear the snap zone just beyond the new click.
        .lo = min (strokeLastT, .t - .snap)
        .hi = max (strokeLastT, .t + .snap)
        @deleteWhere: .p, .lo, .hi, strokeLastT
        if .t > strokeLastT
            .brk = 0
        else
            # Drawing leftwards: this new point is the stroke's left end, so
            # it inherits the stroke's opening gap and the old left end joins.
            .brk = strokeStartBreak
            for .i to cN [.p]
                if abs (cT [.p, .i] - strokeLastT) < 1e-9
                    cB [.p, .i] = 0
                endif
            endfor
        endif
        @insertPoint: .p, .t, .v, .brk
        strokeLastT = .t
    endif
    strokePanel = .p
    ovValid = 0
    status$ = "Points: pitch " + string$ (cN [1]) + ", loudness " + string$ (cN [2])
        ... + ".  Preview (P) shows the processed curves."
endproc

procedure deleteWhere: .p, .lo, .hi, .keepT
    # Removes points with lo <= t <= hi, except one at exactly keepT.
    .n = 0
    for .i to cN [.p]
        .tt = cT [.p, .i]
        .del = .tt >= .lo - 1e-9 and .tt <= .hi + 1e-9 and abs (.tt - .keepT) > 1e-9
        if not .del
            .n += 1
            cT [.p, .n] = .tt
            cV [.p, .n] = cV [.p, .i]
            cB [.p, .n] = cB [.p, .i]
        endif
    endfor
    cN [.p] = .n
endproc

procedure insertPoint: .p, .t, .v, .brk
    .pos = cN [.p] + 1
    for .i to cN [.p]
        if .pos > cN [.p] and cT [.p, .i] > .t
            .pos = .i
        endif
    endfor
    for .j to cN [.p] - .pos + 1
        .src = cN [.p] - .j + 1
        cT [.p, .src + 1] = cT [.p, .src]
        cV [.p, .src + 1] = cV [.p, .src]
        cB [.p, .src + 1] = cB [.p, .src]
    endfor
    cT [.p, .pos] = .t
    cV [.p, .pos] = .v
    cB [.p, .pos] = .brk
    cN [.p] += 1
endproc

procedure pushUndo
    uTop = uTop mod 20 + 1
    uCount = min (uCount + 1, 20)
    uDur [uTop] = dur
    for .p to 2
        uN [uTop, .p] = cN [.p]
        for .i to cN [.p]
            uT [uTop, .p, .i] = cT [.p, .i]
            uV [uTop, .p, .i] = cV [.p, .i]
            uB [uTop, .p, .i] = cB [.p, .i]
        endfor
    endfor
endproc

procedure popUndo
    if uCount = 0
        status$ = "Nothing to undo."
    else
        dur = uDur [uTop]
        for .p to 2
            cN [.p] = uN [uTop, .p]
            for .i to cN [.p]
                cT [.p, .i] = uT [uTop, .p, .i]
                cV [.p, .i] = uV [uTop, .p, .i]
                cB [.p, .i] = uB [uTop, .p, .i]
            endfor
        endfor
        uTop = (uTop + 18) mod 20 + 1
        uCount -= 1
        strokePanel = 0
        penLifted = 0
        ovValid = 0
        status$ = "Undone (" + string$ (uCount) + " more available)."
    endif
endproc

procedure exampleGesture
    # A two-phrase line: a rising, swelling first phrase, a silence, and a
    # falling answer with a short detached note in between.
    cN [1] = 0
    cN [2] = 0
    @exPt: 1, 0.00, 262, 0
    @exPt: 1, 0.14, 262, 0
    @exPt: 1, 0.30, 330, 0
    @exPt: 1, 0.42, 392, 0
    @exPt: 1, 0.52, 523, 1
    @exPt: 1, 0.62, 494, 0
    @exPt: 1, 0.70, 440, 0
    @exPt: 1, 0.80, 392, 0
    @exPt: 1, 0.98, 330, 0
    @exPt: 2, 0.02, -60, 0
    @exPt: 2, 0.10, -32, 0
    @exPt: 2, 0.36, -22, 0
    @exPt: 2, 0.44, -45, 0
    @exPt: 2, 0.52, -30, 1
    @exPt: 2, 0.56, -28, 0
    @exPt: 2, 0.58, -78, 0
    @exPt: 2, 0.62, -30, 1
    @exPt: 2, 0.90, -27, 0
    @exPt: 2, 0.97, -78, 0
    status$ = "Example gesture loaded. Press Preview or Synthesize - or redraw over it."
endproc

procedure exPt: .p, .frac, .v, .brk
    cN [.p] += 1
    cT [.p, cN [.p]] = .frac * dur
    cV [.p, cN [.p]] = .v
    cB [.p, cN [.p]] = .brk
endproc

# ============================================================
# GESTURE FILES
# ============================================================
procedure writeGesture: .path$
    .s$ = "# DDSP Neural Drawing Synthesizer - gesture file" + newline$
        ... + "# rows: time_s value break   (break=1: pen lifted before point)" + newline$
        ... + "format ddsp_drawing_gesture 1" + newline$
        ... + "duration " + fixed$ (dur, 6) + newline$
        ... + "pitch_range " + fixed$ (pMin, 3) + " " + fixed$ (pMax, 3) + newline$
        ... + "loudness_range " + fixed$ (lMin, 3) + " " + fixed$ (lMax, 3) + newline$
        ... + "[PITCH]" + newline$
    for .i to cN [1]
        .s$ = .s$ + fixed$ (cT [1, .i], 6) + " " + fixed$ (cV [1, .i], 4) + " " + string$ (cB [1, .i]) + newline$
    endfor
    .s$ = .s$ + "[LOUDNESS]" + newline$
    for .i to cN [2]
        .s$ = .s$ + fixed$ (cT [2, .i], 6) + " " + fixed$ (cV [2, .i], 3) + " " + string$ (cB [2, .i]) + newline$
    endfor
    writeFile: .path$, .s$
endproc

procedure autosaveGesture
    if cN [1] + cN [2] > 0
        @writeGesture: lastGesture$
    endif
endproc

procedure loadGesture: .path$, .what
    # .what: 1 = both (adopt file duration), 2 = pitch only, 3 = loudness only
    Read Strings from raw text file: .path$
    .sid = selected ("Strings")
    .nl = Get number of strings
    .fDur = 0
    .sec = 0
    fN [1] = 0
    fN [2] = 0
    .bad = 0
    for .i to .nl
        selectObject: .sid
        .line$ = Get string: .i
        .h = index (.line$, "#")
        if .h > 0
            .line$ = left$ (.line$, .h - 1)
        endif
        .line$ = replace_regex$ (.line$, "[\t,]", " ", 0)
        .line$ = replace_regex$ (.line$, " +", " ", 0)
        .line$ = replace_regex$ (.line$, "^ | $", "", 0)
        if .line$ = ""
            # blank
        elsif .line$ = "[PITCH]" or .line$ = "[pitch]" or .line$ = "[Pitch]"
            .sec = 1
        elsif .line$ = "[LOUDNESS]" or .line$ = "[loudness]" or .line$ = "[Loudness]"
            .sec = 2
        elsif .sec = 0
            if startsWith (.line$, "duration ")
                .fDur = number (mid$ (.line$, 10, length (.line$) - 9))
            endif
        else
            .sp = index (.line$, " ")
            if .sp = 0
                .bad += 1
            else
                .a = number (left$ (.line$, .sp - 1))
                .rest$ = mid$ (.line$, .sp + 1, length (.line$) - .sp)
                .sp2 = index (.rest$, " ")
                if .sp2 = 0
                    .bv = number (.rest$)
                    .cv = 0
                else
                    .bv = number (left$ (.rest$, .sp2 - 1))
                    .cv = number (mid$ (.rest$, .sp2 + 1, length (.rest$) - .sp2))
                endif
                if .a = undefined or .bv = undefined or (.sec = 1 and .bv <= 0)
                    .bad += 1
                else
                    if .cv = undefined
                        .cv = 0
                    endif
                    fN [.sec] += 1
                    fT [.sec, fN [.sec]] = .a
                    fV [.sec, fN [.sec]] = .bv
                    fB [.sec, fN [.sec]] = (.cv <> 0)
                endif
            endif
        endif
    endfor
    removeObject: .sid
    if .fDur <= 0
        for .p to 2
            for .i to fN [.p]
                .fDur = max (.fDur, fT [.p, .i])
            endfor
        endfor
    endif
    if .fDur <= 0 or fN [1] + fN [2] = 0
        status$ = "Could not read a gesture from that file."
    else
        if .what = 1
            dur = .fDur
            .scale = 1
        else
            .scale = dur / .fDur
        endif
        for .p to 2
            if .what = 1 or .what = .p + 1
                cN [.p] = 0
                for .i to fN [.p]
                    .tt = fT [.p, .i] * .scale
                    if .tt >= -1e-9 and .tt <= dur + 1e-9
                        @insertPoint: .p, max (0, min (dur, .tt)), fV [.p, .i], fB [.p, .i]
                    endif
                endfor
            endif
        endfor
        # Widen the display ranges if the file goes outside them.
        for .i to cN [1]
            pMin = min (pMin, cV [1, .i] / 1.06)
            pMax = max (pMax, cV [1, .i] * 1.06)
        endfor
        for .i to cN [2]
            lMin = min (lMin, cV [2, .i] - 2)
            lMax = min (0, max (lMax, cV [2, .i] + 2))
        endfor
        strokePanel = 0
        penLifted = 0
        ovValid = 0
        status$ = "Loaded " + string$ (cN [1]) + " pitch / " + string$ (cN [2])
            ... + " loudness points (" + fixed$ (dur, 2) + " s)"
        if .bad > 0
            status$ = status$ + " - " + string$ (.bad) + " unreadable lines skipped"
        endif
    endif
endproc

# ============================================================
# ENGINE CALLS
# ============================================================
procedure engineArgs
    engDrawMode$ = if drawMode = 2 then "gesture" else "curves" fi
    engTransforms$ = if transforms$ = "" then "none" else transforms$ fi
    engRoot$ = if scale_root$ = "" then "C" else scale_root$ fi
endproc

procedure runPreview
    if not canPreview
        status$ = "Preview needs a Python with numpy - see the Info window."
    elsif cN [1] < 1
        status$ = "Draw a pitch line first."
    else
        @cleanUpTempFiles
        @writeGesture: tmpGesture$
        @engineArgs
        status$ = "Computing controls + sketch..."
        @redraw
        demoShow ()
        nocheck runSubprocess: python$, engine$, "--mode", "controls",
            ... "--gesture", tmpGesture$,
            ... "--draw_mode", engDrawMode$, "--pitch_mode", modeKey$ [modeIdx],
            ... "--scale_root", engRoot$,
            ... "--pitch_smoothing", string$ (pitch_smoothing_percent),
            ... "--loudness_smoothing", string$ (loudness_smoothing_percent),
            ... "--silence_threshold", string$ (silence_threshold_dB),
            ... "--loudness_max", string$ (loudness_maximum_dB),
            ... "--motion_depth", string$ (motion_depth_dB),
            ... "--glide_ms", string$ (glide_ms), "--edge_ms", string$ (edge_taper_ms),
            ... "--release_ms", string$ (tail_release_ms),
            ... "--transforms", engTransforms$,
            ... "--controls_out", tmpControls$, "--preview_wav", tmpPreview$,
            ... "--stats", tmpStats$, "--log", tmpLog$
        @readStat: "status"
        if readStat.value$ = "SUCCESS" and fileReadable (tmpControls$)
            @readOverlay
            @readStat: "warnings"
            .w$ = readStat.value$
            @readStat: "n_notes"
            status$ = "Sketch (plain additive tone, not the neural model): "
                ... + readStat.value$ + " note(s)"
            if .w$ <> ""
                status$ = status$ + "  [" + .w$ + "]"
            endif
            @redraw
            demoShow ()
            if fileReadable (tmpPreview$)
                .keep$ = status$
                status$ = status$ + "   - playing (clicks wait until it ends)"
                @redraw
                demoShow ()
                status$ = .keep$
                Read from file: tmpPreview$
                .snd = selected ("Sound")
                Play
                removeObject: .snd
            endif
        else
            @readStat: "warnings"
            status$ = "Preview failed: " + readStat.value$
            @showPyLog
        endif
    endif
endproc

procedure runSynth
    if not canSynth
        status$ = "Synthesize needs a Python with tensorflow + ddsp + crepe - see the Info window."
    elsif cN [1] < 1
        status$ = "Draw a pitch line first."
    else
        @cleanUpTempFiles
        @writeGesture: tmpGesture$
        @autosaveGesture
        @engineArgs
        status$ = "Rendering with " + modelShow$ [modelIdx] + " (first use downloads the model; this takes a while)..."
        @redraw
        demoShow ()
        nocheck runSubprocess: python$, engine$, "--mode", "synth",
            ... "--gesture", tmpGesture$, "--model", modelKey$ [modelIdx],
            ... "--draw_mode", engDrawMode$, "--pitch_mode", modeKey$ [modeIdx],
            ... "--scale_root", engRoot$,
            ... "--pitch_smoothing", string$ (pitch_smoothing_percent),
            ... "--loudness_smoothing", string$ (loudness_smoothing_percent),
            ... "--silence_threshold", string$ (silence_threshold_dB),
            ... "--loudness_max", string$ (loudness_maximum_dB),
            ... "--motion_depth", string$ (motion_depth_dB),
            ... "--glide_ms", string$ (glide_ms), "--edge_ms", string$ (edge_taper_ms),
            ... "--release_ms", string$ (tail_release_ms),
            ... "--transforms", engTransforms$,
            ... "--output_level", levelKey$ [output_level],
            ... "--output_rate", string$ (output_sample_rate),
            ... "--controls_out", tmpControls$, "--output", tmpOutput$,
            ... "--cache_dir", cacheDir$, "--stats", tmpStats$, "--log", tmpLog$
        @readStat: "status"
        if readStat.value$ = "SUCCESS" and fileReadable (tmpOutput$)
            Read from file: tmpOutput$
            lastResult = selected ("Sound")
            .name$ = output_name$ + "_" + modelKey$ [modelIdx]
            Rename: .name$
            @readOverlay
            @reportSynth: .name$
            @readStat: "warnings"
            status$ = "Rendered " + .name$ + ".  Draw more, change model (M), or Close."
            if readStat.value$ <> ""
                status$ = status$ + "  [" + readStat.value$ + "]"
            endif
            @redraw
            demoShow ()
            if play_result
                .keep$ = status$
                status$ = "Playing " + .name$ + " (clicks wait until it ends)..."
                @redraw
                demoShow ()
                status$ = .keep$
                selectObject: lastResult
                Play
            endif
        else
            @readStat: "warnings"
            status$ = "Synthesis failed - see the Info window.  " + readStat.value$
            appendInfoLine: ""
            appendInfoLine: "Synthesis FAILED (", modelKey$ [modelIdx], "): ", readStat.value$
            @showPyLog
        endif
    endif
endproc

procedure readStat: .key$
    # Reads one key=value line from the engine's stats file ("" if absent).
    .value$ = ""
    if fileReadable (tmpStats$)
        .all$ = newline$ + replace$ (readFile$ (tmpStats$), unicode$ (13), "", 0)
        .k = index (.all$, newline$ + .key$ + "=")
        if .k > 0
            .rest$ = mid$ (.all$, .k + length (.key$) + 2, length (.all$))
            .e = index (.rest$, newline$)
            if .e > 0
                .rest$ = left$ (.rest$, .e - 1)
            endif
            .value$ = .rest$
        endif
    endif
endproc

procedure readOverlay
    Read Table from tab-separated file: tmpControls$
    .tid = selected ("Table")
    ovN = Get number of rows
    for .i to ovN
        ovT [.i] = Get value: .i, "time"
        ovF [.i] = Get value: .i, "f0_hz"
        ovL [.i] = Get value: .i, "loudness_db"
        ovV [.i] = Get value: .i, "voiced"
    endfor
    removeObject: .tid
    ovValid = ovN > 1
endproc

procedure reportSynth: .name$
    appendInfoLine: ""
    appendInfoLine: "----- ", .name$, " -----"
    appendInfoLine: "  mode ", engDrawMode$, " | pitch ", modeKey$ [modeIdx], " (root ", engRoot$,
        ... ") | smoothing ", fixed$ (pitch_smoothing_percent, 0), "/", fixed$ (loudness_smoothing_percent, 0),
        ... " | threshold ", fixed$ (silence_threshold_dB, 1), " dB | transforms: ", engTransforms$
    .keys$ = "duration_s output_sample_rate synthesis_rate frame_rate time_steps n_notes "
        ... + "voiced_fraction f0_median_hz model_mean_pitch_hz output_level_mode level_gain_db "
        ... + "output_peak model_source timing_inference_s timing_total_s warnings "
    .rest$ = .keys$
    while index (.rest$, " ") > 0
        .sp = index (.rest$, " ")
        .k$ = left$ (.rest$, .sp - 1)
        .rest$ = mid$ (.rest$, .sp + 1, length (.rest$) - .sp)
        @readStat: .k$
        if readStat.value$ <> ""
            appendInfoLine: "  ", .k$, " = ", readStat.value$
        endif
    endwhile
endproc

procedure showPyLog
    if fileReadable (tmpLog$)
        appendInfoLine: ""
        appendInfoLine: "----- Python log -----"
        appendInfo: readFile$ (tmpLog$)
        appendInfoLine: "----------------------"
    endif
endproc

procedure cleanUpTempFiles
    # Only files with this module's own prefix are ever deleted.
    for .k to 7
        .f$ = if .k = 1 then tmpGesture$ else if .k = 2 then tmpControls$ else
            ... if .k = 3 then tmpPreview$ else if .k = 4 then tmpOutput$ else
            ... if .k = 5 then tmpStats$ else if .k = 6 then tmpLog$ else tmpProbeMark$ fi fi fi fi fi fi
        if fileReadable (.f$)
            deleteFile: .f$
        endif
    endfor
endproc

procedure setScale: .m, .list$
    .rest$ = .list$ + " "
    .n = 0
    while index (.rest$, " ") > 0
        .sp = index (.rest$, " ")
        .n += 1
        scaleStep [.m, .n] = number (left$ (.rest$, .sp - 1))
        .rest$ = mid$ (.rest$, .sp + 1, length (.rest$) - .sp)
    endwhile
    scaleStep [.m, 0] = .n
endproc

# ============================================================
# DRAWING THE CANVAS
# ============================================================
procedure frame
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
endproc

procedure txt: .x, .h$, .y, .v$, .size, .col$, .t$
    demo Colour: .col$
    demo Text special: .x, .h$, .y, .v$, "Helvetica", .size, "0", .t$
    @frame
endproc

procedure san: .s$
    # Picture-text markup: _ subscript, % italic, # bold, ^ superscript.
    .out$ = replace$ (.s$, "\", "/", 0)
    .out$ = replace$ (.out$, "_", "\_ ", 0)
    .out$ = replace$ (.out$, "%", "\% ", 0)
    .out$ = replace$ (.out$, "#", "\# ", 0)
    .out$ = replace$ (.out$, "^", "\^ ", 0)
endproc

procedure redraw
    demo Erase all
    demo Font size: 10
    @frame
    demo Paint rectangle: colBack$, 0, 100, 0, 100
    demo Colour: "Black"
    demo Solid line
    demo Line width: 1

    @txt: cx0, "left", 95.5, "half", 15, "{0.10, 0.12, 0.18}", "##DDSP Neural Drawing Synthesizer##"
    .hdr$ = modelShow$ [modelIdx] + "   ·   " + modeShow$ [modeIdx]
    if modeIdx > 2
        .hdr$ = .hdr$ + " (" + scale_root$ + ")"
    endif
    .hdr$ = .hdr$ + "   ·   " + fixed$ (dur, 2) + " s   ·   "
        ... + (if drawMode = 2 then "single gesture" else "pitch + loudness" fi)
    @san: .hdr$
    @txt: cx1, "right", 95.5, "half", 11, colText$, san.out$

    @pitchPanel
    @loudnessPanel
    @timeAxis
    if ovValid
        @drawOverlay
    endif
    @drawCurve: 1
    if drawMode = 1
        @drawCurve: 2
    endif
    @drawButtons

    @san: status$
    @txt: cx0, "left", 15.5, "half", 10.5, "{0.10, 0.12, 0.18}", san.out$
    if drawMode = 2
        .help$ = "Click = add point   Space = lift pen (gap)   Z = undo   P = preview   S = synthesize   G = two-curve mode"
    else
        .help$ = "Click = add point   Space = lift pen (gap)   Z = undo   P = preview   S = synthesize   G = single-gesture mode"
    endif
    @txt: cx0, "left", 12.3, "half", 8.5, colText$, .help$
endproc

procedure pitchPanel
    demo Paint rectangle: colPanel$, cx0, cx1, pY0, pY1
    @shadeUnvoiced: pY0, pY1
    .lnMin = ln (pMin)
    .span = ln (pMax / pMin)
    .m0 = ceiling (69 + 12 * log2 (pMin / 440))
    .m1 = floor (69 + 12 * log2 (pMax / 440))
    # Faint scale-degree lines when quantizing to a scale over a modest range
    if modeIdx > 2 and .m1 - .m0 <= 36
        @rootPc
        demo Colour: "{0.93, 0.94, 0.97}"
        for .m from .m0 to .m1
            .pc = (.m - rootPc.pc + 1200) mod 12
            .inScale = 0
            for .k to scaleStep [modeIdx, 0]
                if scaleStep [modeIdx, .k] = .pc
                    .inScale = 1
                endif
            endfor
            if .inScale
                .y = pY0 + (ln (440 * 2 ^ ((.m - 69) / 12)) - .lnMin) / .span * (pY1 - pY0)
                demo Draw line: cx0, .y, cx1, .y
            endif
        endfor
    elsif modeIdx = 2 and .m1 - .m0 <= 30
        demo Colour: "{0.93, 0.94, 0.97}"
        for .m from .m0 to .m1
            .y = pY0 + (ln (440 * 2 ^ ((.m - 69) / 12)) - .lnMin) / .span * (pY1 - pY0)
            demo Draw line: cx0, .y, cx1, .y
        endfor
    endif
    if pitch_guides = 3
        for .dec from 1 to 4
            for .q to 3
                .hz = (if .q = 1 then 1 else if .q = 2 then 2 else 5 fi fi) * 10 ^ .dec
                if .hz >= pMin and .hz <= pMax
                    .y = pY0 + (ln (.hz) - .lnMin) / .span * (pY1 - pY0)
                    demo Colour: colGridStrong$
                    demo Draw line: cx0, .y, cx1, .y
                    @txt: cx0 - 0.6, "right", .y, "half", 8.5, colText$, string$ (.hz)
                endif
            endfor
        endfor
    else
        for .m from .m0 to .m1
            .pc = .m mod 12
            if .pc = 9 or (.pc = 0 and .m1 - .m0 <= 60)
                .y = pY0 + (ln (440 * 2 ^ ((.m - 69) / 12)) - .lnMin) / .span * (pY1 - pY0)
                .oct = floor (.m / 12) - 1
                if pitch_guides = 2
                    .lab$ = string$ (.m)
                else
                    .lab$ = (if .pc = 9 then "A" else "C" fi) + string$ (.oct)
                endif
                if .pc = 9
                    demo Colour: colGridStrong$
                    demo Draw line: cx0, .y, cx1, .y
                    @txt: cx0 - 0.6, "right", .y, "half", 9, colText$, "##" + .lab$ + "##"
                else
                    demo Colour: colGrid$
                    demo Draw line: cx0, .y, cx1, .y
                    @txt: cx0 - 0.6, "right", .y, "half", 7.5, colText$, .lab$
                endif
            endif
        endfor
    endif
    demo Colour: "{0.55, 0.57, 0.62}"
    demo Draw rectangle: cx0, cx1, pY0, pY1
    demo Colour: "{0.20, 0.22, 0.30}"
    demo Text special: 2.2, "centre", (pY0 + pY1) / 2, "half", "Helvetica", 11, "90", "##PITCH##"
    @frame
endproc

procedure loudnessPanel
    demo Paint rectangle: colPanel$, cx0, cx1, lY0, lY1
    @shadeUnvoiced: lY0, lY1
    .first = 20 * ceiling (lMin / 20)
    for .k from 0 to 6
        .db = .first + 20 * .k
        if .db <= lMax and .db >= lMin
            .y = lY0 + (.db - lMin) / (lMax - lMin) * (lY1 - lY0)
            demo Colour: colGridStrong$
            demo Draw line: cx0, .y, cx1, .y
            @txt: cx0 - 0.6, "right", .y, "half", 8.5, colText$, string$ (.db)
        endif
    endfor
    if silence_threshold_dB > lMin and silence_threshold_dB < lMax
        .y = lY0 + (silence_threshold_dB - lMin) / (lMax - lMin) * (lY1 - lY0)
        demo Colour: "{0.85, 0.45, 0.45}"
        demo Dashed line
        demo Draw line: cx0, .y, cx1, .y
        demo Solid line
        @txt: cx0 + 0.4, "left", .y - 0.3, "top", 8, "{0.80, 0.35, 0.35}", "silence"
    endif
    if drawMode = 2 and not ovValid
        @txt: (cx0 + cx1) / 2, "centre", (lY0 + lY1) / 2, "half", 10, "{0.60, 0.62, 0.68}",
            ... "loudness follows the motion of the pitch line (Preview shows it)"
    endif
    demo Colour: "{0.55, 0.57, 0.62}"
    demo Draw rectangle: cx0, cx1, lY0, lY1
    demo Colour: "{0.20, 0.22, 0.30}"
    demo Text special: 2.2, "centre", (lY0 + lY1) / 2, "half", "Helvetica", 11, "90", "##LOUDNESS##"
    @frame
    @txt: cx0 - 0.6, "right", lY1 + 1.6, "bottom", 8, colText$, "dB"
endproc

procedure timeAxis
    .raw = dur / 8
    .mag = 10 ^ floor (log10 (.raw))
    .step = if .raw <= .mag then .mag else if .raw <= 2 * .mag then 2 * .mag else
        ... if .raw <= 5 * .mag then 5 * .mag else 10 * .mag fi fi fi
    .dec = max (0, - floor (log10 (.step) + 1e-9))
    .n = floor (dur / .step + 1e-9)
    for .k from 0 to .n
        .t = .k * .step
        .x = cx0 + .t / dur * (cx1 - cx0)
        demo Colour: colGrid$
        demo Draw line: .x, pY0, .x, pY1
        demo Draw line: .x, lY0, .x, lY1
        .lab$ = if .k = 0 then "0" else fixed$ (.t, .dec) fi
        @txt: .x, "centre", lY0 - 1.2, "top", 8.5, colText$, .lab$
    endfor
    @txt: cx1, "right", lY0 - 4.6, "top", 8.5, colText$, "time (s)"
endproc

procedure shadeUnvoiced: .y0, .y1
    # Silent (unvoiced) stretches of the last processed controls.
    if ovValid
        for .i from 2 to ovN
            if ovV [.i] = 0
                .xa = cx0 + ovT [.i - 1] / dur * (cx1 - cx0)
                .xb = cx0 + ovT [.i] / dur * (cx1 - cx0)
                demo Paint rectangle: "{0.93, 0.93, 0.94}", max (cx0, .xa), min (cx1, .xb), .y0, .y1
            endif
        endfor
    endif
endproc

procedure drawOverlay
    # Processed controls from the engine: orange = what DDSP actually receives.
    demo Colour: colProc$
    demo Line width: 2
    .lnMin = ln (pMin)
    .span = ln (pMax / pMin)
    for .i from 2 to ovN
        if ovV [.i] and ovV [.i - 1]
            .xa = cx0 + ovT [.i - 1] / dur * (cx1 - cx0)
            .xb = cx0 + ovT [.i] / dur * (cx1 - cx0)
            .ya = pY0 + max (0, min (1, (ln (ovF [.i - 1]) - .lnMin) / .span)) * (pY1 - pY0)
            .yb = pY0 + max (0, min (1, (ln (ovF [.i]) - .lnMin) / .span)) * (pY1 - pY0)
            demo Draw line: .xa, .ya, .xb, .yb
            .ya = lY0 + max (0, min (1, (ovL [.i - 1] - lMin) / (lMax - lMin))) * (lY1 - lY0)
            .yb = lY0 + max (0, min (1, (ovL [.i] - lMin) / (lMax - lMin))) * (lY1 - lY0)
            demo Draw line: .xa, .ya, .xb, .yb
        endif
    endfor
    demo Line width: 1
    demo Colour: colProc$
    demo Draw line: cx1 - 16, lY0 - 4.1, cx1 - 14, lY0 - 4.1
    @txt: cx1 - 13.5, "left", lY0 - 4.1, "half", 8, colText$, "processed"
endproc

procedure drawCurve: .p
    if .p = 1
        .col$ = colPitch$
        .y0 = pY0
        .y1 = pY1
    else
        .col$ = colLoud$
        .y0 = lY0
        .y1 = lY1
    endif
    .n = cN [.p]
    for .i to .n
        if .p = 1
            .fy [.i] = .y0 + max (0, min (1, ln (cV [1, .i] / pMin) / ln (pMax / pMin))) * (.y1 - .y0)
        else
            .fy [.i] = .y0 + max (0, min (1, (cV [2, .i] - lMin) / (lMax - lMin))) * (.y1 - .y0)
        endif
        .fx [.i] = cx0 + cT [.p, .i] / dur * (cx1 - cx0)
    endfor
    if .n > 0 and .p = 1
        # pitch is held outside and between strokes: show it dotted
        demo Colour: "{0.55, 0.62, 0.80}"
        demo Dotted line
        demo Draw line: cx0, .fy [1], .fx [1], .fy [1]
        demo Draw line: .fx [.n], .fy [.n], cx1, .fy [.n]
        for .i from 2 to .n
            if cB [1, .i]
                demo Draw line: .fx [.i - 1], .fy [.i - 1], .fx [.i], .fy [.i - 1]
            endif
        endfor
        demo Solid line
    endif
    demo Colour: .col$
    demo Line width: 3
    for .i from 2 to .n
        if cB [.p, .i] = 0
            demo Draw line: .fx [.i - 1], .fy [.i - 1], .fx [.i], .fy [.i]
        endif
    endfor
    demo Line width: 1
    for .i to .n
        demo Paint circle (mm): .col$, .fx [.i], .fy [.i], 1.6
    endfor
    if strokePanel = .p and not penLifted
        for .i to .n
            if abs (cT [.p, .i] - strokeLastT) < 1e-9
                demo Colour: .col$
                demo Draw circle (mm): .fx [.i], .fy [.i], 3.2
            endif
        endfor
    endif
endproc

procedure drawButtons
    nButtons = 10
    bl$ [1] = modelShow$ [modelIdx]
    bl$ [2] = modeShow$ [modeIdx]
    bl$ [3] = "Undo"
    bl$ [4] = "Lift pen"
    bl$ [5] = "Clear"
    bl$ [6] = "Load"
    bl$ [7] = "Save"
    bl$ [8] = "Preview"
    bl$ [9] = "Synthesize"
    bl$ [10] = "Close"
    .gap = 0.8
    .wide = 11
    .w = (96 - 2 * .wide - 9 * .gap) / 8
    .x = 2
    for .b to nButtons
        bx0 [.b] = .x
        .bw = if .b <= 2 then .wide else .w fi
        bx1 [.b] = .x + .bw
        .x = bx1 [.b] + .gap
        .fill$ = "{0.99, 0.99, 1.0}"
        .tcol$ = "{0.10, 0.12, 0.18}"
        if .b = 9
            .fill$ = if canSynth then "{0.20, 0.40, 0.80}" else "{0.80, 0.82, 0.86}" fi
            .tcol$ = "{1.0, 1.0, 1.0}"
        elsif .b = 8 and not canPreview
            .tcol$ = "{0.65, 0.66, 0.70}"
        elsif .b = 4 and penLifted
            .fill$ = "{1.0, 0.90, 0.60}"
        endif
        demo Paint rectangle: .fill$, bx0 [.b], bx1 [.b], 3, 10
        demo Colour: "{0.60, 0.62, 0.68}"
        demo Draw rectangle: bx0 [.b], bx1 [.b], 3, 10
        if .b <= 2
            .cap$ = if .b = 1 then "MODEL  (M)" else "PITCH MODE  (K)" fi
            @txt: (bx0 [.b] + bx1 [.b]) / 2, "centre", 8.4, "half", 7, colText$, .cap$
            @txt: (bx0 [.b] + bx1 [.b]) / 2, "centre", 5.2, "half", 10.5, .tcol$, "##" + bl$ [.b] + "##"
        else
            @txt: (bx0 [.b] + bx1 [.b]) / 2, "centre", 6.5, "half", 10.5, .tcol$, bl$ [.b]
        endif
    endfor
endproc

procedure rootPc
    .s$ = scale_root$ + "  "
    .l$ = left$ (.s$, 1)
    .base = -1
    if .l$ <> " "
        .base = index ("C D EF G A B", .l$) - 1
        if .base < 0
            .base = index ("c d ef g a b", .l$) - 1
        endif
    endif
    if .base < 0
        .base = 0
    endif
    .acc$ = mid$ (.s$, 2, 1)
    .pc = .base + (.acc$ = "#") - (.acc$ = "b")
endproc

label END
