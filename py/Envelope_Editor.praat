# ============================================================
# Praat AudioTools Plugin
# Script:      Envelope_Editor.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     2.5 (2026) - waveform display + zoom in the editor GUI
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.5:
#   - NEW: the editor shows the Sound's waveform (strip above the lanes plus
#     a faint copy behind each lane) and has a shared zoom across all lanes.
#     Praat writes a mono, peak-normalised 16-bit display copy once
#     (temp_enved_wave.wav) and passes it as an optional 4th "gui" argument;
#     it is reused across Audition/Tweak passes and removed at cleanup.
#     Display only - no DSP path changed. Requires envelope_editor.py v2.3.
#
# Changelog v2.4:
#   - Confirmed via Spectral_Eraser.praat that the configured venv, bare
#     "python", and "py" all genuinely lack tkinter on this machine (not a
#     quoting artifact - verified directly in cmd). Added "python3" as a
#     fourth candidate: on this system it resolves to the Microsoft Store
#     Python install, which does have tkinter (plus numpy/soundfile).
#
#
# Changelog v2.3:
#   - FIX: Python discovery was a single OS-based guess ("python" on
#     Windows), never verified until an inline "-c" probe run through a
#     real shell (runSystem_nocheck) with hand-escaped triple-quote
#     strings - the same class of quoting fragility already fixed in
#     CorpusMap.praat / Dereverberation.praat v2.2. On failure this gave
#     "Cannot find Python with tkinter" even when tkinter was fine and the
#     probe itself was the problem. Replaced with the library's verified
#     cascade (configured venv tried first, each candidate actually probed
#     via a no-shell, file-based check).
#   - All four Python calls (dependency probe, GUI launch, envelope DSP,
#     filter DSP) switched from runSystem/runSystem_nocheck string
#     concatenation to no-shell runSubprocess with separate arguments -
#     the house pattern used throughout the rest of the library.
#
# Description:
#   Opens a Python GUI with four independent breakpoint envelope lanes,
#   then applies all processing natively in Praat:
#
#     1. Pitch     — via To Manipulation + PitchTier (PSOLA resynthesis)
#     2. Intensity — via IntensityTier multiply
#     3. Pan       — via AmplitudeTier on L/R channels
#     4. Filter    — spectral morph: fixed LP <-> dry <-> fixed HP
#
# Workflow:
#   1. Python GUI writes a breakpoints JSON file
#   2. Praat reads JSON (via Python one-liner), builds native tiers
#   3. Praat applies each effect in sequence
#   4. Result is played, then: Play again / Tweak again / Keep
#   5. "Tweak again" reopens the editor pre-loaded with your curves
#      and re-renders — a full-fidelity audition loop
#
# JSON produced by envelope_editor.py:
#   { "pan":[[t,v],...], "pitch":[[t,v],...],
#     "intensity":[[t,v],...], "filter":[[t,v],...] }
#
# Usage:
#   Select a Sound object, then run this script.
# ============================================================

# ---- Verify selection ----
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected ("Sound")
soundName$ = selected$ ("Sound")
duration   = Get total duration

# ---- Python interpreter candidates (verified cascade) ----
# v2.3: previously this picked ONE name per OS (bare "python" on Windows)
# and never verified it had tkinter until a shell-based inline probe below
# - which is itself fragile (same class of quoting bug fixed in
# CorpusMap.praat / Dereverberation.praat v2.2). Now matches the rest of
# the library: #1 is your known-good venv (edit THAT ONE LINE if yours
# lives elsewhere), then an OS-appropriate fallback list. EACH candidate is
# actually probed below via a no-shell, file-based check before acceptance.
nPyCand = 1
pyCandidate1$ = "C:/Users/user/praat_ddsp_env/Scripts/python.exe"

if macintosh
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/opt/homebrew/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/usr/local/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python3"
elsif windows
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "py"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python3"
else
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python"
endif

# ---- Paths ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/envelope_editor.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/envelope_editor.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: envelope_editor.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

bpFile$       = temporaryDirectory$ + "/temp_enved_breakpoints.json"
gainIntens$   = temporaryDirectory$ + "/temp_gain_intensity.wav"
gainPanL$     = temporaryDirectory$ + "/temp_gain_panL.wav"
gainPanR$     = temporaryDirectory$ + "/temp_gain_panR.wav"
pitchFile$    = temporaryDirectory$ + "/temp_bp_pitch.txt"
filterFile$   = temporaryDirectory$ + "/temp_bp_filter.txt"
gainFiltLP$   = temporaryDirectory$ + "/temp_gain_filtLP.wav"
gainFiltHP$   = temporaryDirectory$ + "/temp_gain_filtHP.wav"
gainFiltDry$  = temporaryDirectory$ + "/temp_gain_filtDry.wav"
probeMarker$  = temporaryDirectory$ + "/temp_enved_probe.ok"
probeScript$  = temporaryDirectory$ + "/temp_enved_probe.py"
waveFile$     = temporaryDirectory$ + "/temp_enved_wave.wav"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- Cleanup Procedure ----
procedure cleanUpTempFiles
    if fileReadable (bpFile$)
        deleteFile: bpFile$
    endif
    if fileReadable (gainIntens$)
        deleteFile: gainIntens$
    endif
    if fileReadable (gainIntens$ + ".peak")
        deleteFile: gainIntens$ + ".peak"
    endif
    if fileReadable (gainPanL$)
        deleteFile: gainPanL$
    endif
    if fileReadable (gainPanL$ + ".peak")
        deleteFile: gainPanL$ + ".peak"
    endif
    if fileReadable (gainPanR$)
        deleteFile: gainPanR$
    endif
    if fileReadable (gainPanR$ + ".peak")
        deleteFile: gainPanR$ + ".peak"
    endif
    if fileReadable (pitchFile$)
        deleteFile: pitchFile$
    endif
    if fileReadable (filterFile$)
        deleteFile: filterFile$
    endif
    if fileReadable (gainFiltLP$)
        deleteFile: gainFiltLP$
    endif
    if fileReadable (gainFiltLP$ + ".peak")
        deleteFile: gainFiltLP$ + ".peak"
    endif
    if fileReadable (gainFiltHP$)
        deleteFile: gainFiltHP$
    endif
    if fileReadable (gainFiltHP$ + ".peak")
        deleteFile: gainFiltHP$ + ".peak"
    endif
    if fileReadable (gainFiltDry$)
        deleteFile: gainFiltDry$
    endif
    if fileReadable (gainFiltDry$ + ".peak")
        deleteFile: gainFiltDry$ + ".peak"
    endif
    if fileReadable (probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable (probeScript$)
        deleteFile: probeScript$
    endif
    if fileReadable (bpFile$ + ".applied")
        deleteFile: bpFile$ + ".applied"
    endif
    if fileReadable (bpFile$ + ".audition")
        deleteFile: bpFile$ + ".audition"
    endif
    if fileReadable (waveFile$)
        deleteFile: waveFile$
    endif
endproc

@cleanUpTempFiles

# ---- Robust Python detection & dependency probe (no-shell, cascade) ----
if fileReadable(probeScript$)
    deleteFile: probeScript$
endif
writeFileLine: probeScript$, "import sys"
appendFileLine: probeScript$, "try:"
appendFileLine: probeScript$, "    import tkinter"
appendFileLine: probeScript$, "except Exception:"
appendFileLine: probeScript$, "    sys.exit(1)"
appendFileLine: probeScript$, "open(r'" + probeMarkerJ$ + "', 'w').write('ok')"

pythonCmd$ = ""
pySource$  = ""
pyTried$   = ""

for iPyCand to nPyCand
    thisPyCand$ = pyCandidate'iPyCand'$
    pyTried$ = pyTried$ + "  - " + thisPyCand$ + newline$
    if pythonCmd$ = ""
        isBarePyCmd = (thisPyCand$ = "python3") or (thisPyCand$ = "python") or (thisPyCand$ = "py")
        if isBarePyCmd or fileReadable(thisPyCand$)
            if fileReadable(probeMarker$)
                deleteFile: probeMarker$
            endif
            nocheck runSubprocess: thisPyCand$, probeScript$
            if fileReadable(probeMarker$)
                pythonCmd$ = thisPyCand$
                if iPyCand = 1
                    pySource$ = "configured venv"
                else
                    pySource$ = "auto-detected"
                endif
            endif
        endif
    endif
endfor

if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif
if fileReadable(probeScript$)
    deleteFile: probeScript$
endif

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python with tkinter." + newline$ + newline$
        ... + "Tried:" + newline$ + pyTried$ + newline$
        ... + "tkinter ships with standard Python - if none of the above" + newline$
        ... + "have it, reinstall Python with tcl/tk included, or point" + newline$
        ... + "pyCandidate1$ at a venv that has it."
endif

# ---- Banner ----
clearinfo
appendInfoLine: "=== Envelope Editor 2.5 ==="
appendInfoLine: "Sound:    ", soundName$
appendInfoLine: "Duration: ", fixed$ (duration, 3), " s"
appendInfoLine: "Python:   ", pythonCmd$, " (", pySource$, ")"
appendInfoLine: ""

# ---- Waveform display copy for the editor (v2.5; display only) ----
# Mono + peak-normalised so the 16-bit WAV never clips and quiet files
# are still readable. Written once, reused by every editor pass.
selectObject: sound
nChWave = Get number of channels
if nChWave > 1
    waveTmp = Convert to mono
else
    waveTmp = Copy: "enved_wave_tmp"
endif
wavePeak = Get absolute extremum: 0, 0, "None"
if wavePeak > 0
    Scale peak: 0.99
endif
Save as WAV file: waveFile$
removeObject: waveTmp

# ---- Render constants (from the original; unchanged across passes) ----
selectObject: sound
nSampTotal = Get number of samples
srTotal    = Get sampling frequency
tStartS    = Get start time

# The GUI writes this marker on Apply. Because the breakpoints file now
# persists between passes (so the GUI can pre-load the last curves), the
# marker is what tells Apply apart from Cancel.
appliedMarker$ = bpFile$ + ".applied"
auditionMarker$ = bpFile$ + ".audition"

result      = 0
iteration   = 0
auditioning = 1

# ============================================================
# AUDITION LOOP  —  edit -> full render -> listen -> reopen/keep
# ============================================================
while auditioning
    iteration = iteration + 1

    # Clear stale action markers. The GUI writes exactly one of them.
    if fileReadable (appliedMarker$)
        deleteFile: appliedMarker$
    endif
    if fileReadable (auditionMarker$)
        deleteFile: auditionMarker$
    endif

    if iteration = 1
        appendInfoLine: "Opening envelope editor..."
    else
        appendInfoLine: ""
        appendInfoLine: "Reopening editor (pass ", iteration, ") -- previous curves pre-loaded..."
    endif

    # ---- Launch GUI (pre-loads bpFile$ if it exists from a prior pass) ----
    nocheck runSubprocess: pythonCmd$, pythonScript$, "gui", fixed$(duration, 6), bpFile$, waveFile$

    action$ = ""
    if fileReadable (auditionMarker$)
        action$ = "audition"
        deleteFile: auditionMarker$
    elsif fileReadable (appliedMarker$)
        action$ = "apply"
        deleteFile: appliedMarker$
    endif

    if action$ = ""
        if result = 0
            appendInfoLine: "Cancelled."
            @cleanUpTempFiles
            exitScript: "Envelope Editor cancelled."
        endif
        appendInfoLine: "Editor closed without Audition/Apply -- keeping the last render."
        auditioning = 0
    else
        appendInfoLine: "Breakpoints received (", action$, "). Applying DSP in Praat..."

        # Drop the previous render before building a new one
        if result <> 0
            removeObject: result
            result = 0
        endif

        # ---- Python: interpolate envelopes, write gain WAVs + breakpoint texts ----
        runSubprocess: pythonCmd$, pythonScript$, "envelopes", bpFile$,
            ... string$(nSampTotal), string$(srTotal), string$(tStartS),
            ... gainIntens$, gainPanL$, gainPanR$, pitchFile$, filterFile$

# ============================================================
# STEP 1 — PITCH  (Manipulation / PSOLA resynthesis)
# ============================================================
appendInfoLine: "  [1/4] Pitch..."

pitchMatrix = Read Matrix from raw text file: pitchFile$
nShiftPts   = Get number of rows
pitchActive = 0
for row from 1 to nShiftPts
    selectObject: pitchMatrix
    vCheck = Get value in cell: row, 2
    if abs (vCheck) > 0.000001
        pitchActive = 1
    endif
endfor

if pitchActive = 0
    # True bypass for a neutral pitch lane: no unnecessary PSOLA resynthesis.
    selectObject: sound
    soundPitched = Copy: "pitched"
    removeObject: pitchMatrix
    appendInfoLine: "    skipped (neutral)."
else
    selectObject: sound
    To Manipulation: 0.01, 75, 600
    manipulation = selected ("Manipulation")

    selectObject: manipulation
    Extract pitch tier
    pitchTierOrig = selected ("PitchTier")
    nOrigPts = Get number of points

    selectObject: pitchTierOrig
    tStart = Get start time
    tEnd   = Get end time

    Create PitchTier: "shifted", tStart, tEnd
    pitchTierNew = selected ("PitchTier")

    # GUI breakpoint times are relative (0..duration); PitchTier times are
    # absolute Sound times.  Convert each PitchTier time to relative time.
    for i from 1 to nOrigPts
        selectObject: pitchTierOrig
        t  = Get time from index: i
        hz = Get value at index: i
        tRel = t - tStart

        selectObject: pitchMatrix
        shift_st = 0
        for row from 1 to nShiftPts - 1
            t0 = Get value in cell: row,     1
            t1 = Get value in cell: row + 1, 1
            if tRel >= t0 and tRel <= t1
                v0 = Get value in cell: row,     2
                v1 = Get value in cell: row + 1, 2
                if t1 > t0
                    shift_st = v0 + (tRel - t0) / (t1 - t0) * (v1 - v0)
                else
                    shift_st = v0
                endif
                row = nShiftPts
            endif
        endfor

        newHz = hz * (2 ^ (shift_st / 12))
        newHz = max (newHz, 50)
        newHz = min (newHz, 800)

        selectObject: pitchTierNew
        Add point: t, newHz
    endfor

    if nOrigPts = 0
        for i from 1 to nShiftPts
            selectObject: pitchMatrix
            tRel     = Get value in cell: i, 1
            shift_st = Get value in cell: i, 2
            newHz    = 100 * (2 ^ (shift_st / 12))
            newHz    = max (newHz, 50)
            newHz    = min (newHz, 800)
            tAbs     = min (tEnd, max (tStart, tStart + tRel))
            selectObject: pitchTierNew
            Add point: tAbs, newHz
        endfor
    endif

    selectObject: manipulation
    plusObject: pitchTierNew
    Replace pitch tier
    selectObject: manipulation
    soundPitched = Get resynthesis (overlap-add)
    Rename: "pitched"

    removeObject: pitchTierOrig
    removeObject: pitchTierNew
    removeObject: pitchMatrix
    removeObject: manipulation
    appendInfoLine: "    done."
endif

# ============================================================
# STEP 2 — INTENSITY  (vectorized Formula, DBAP-style)
# ============================================================
appendInfoLine: "  [2/4] Intensity..."

gainIntensSound = Read from file: gainIntens$
Rename: "gainIntensity"
intensPeak = number (readFile$ (gainIntens$ + ".peak"))

selectObject: soundPitched
soundIntensity = Copy: "intensity"
nChI = Get number of channels
if nChI = 1
    Formula: "self * Sound_gainIntensity(x - 'tStartS') * 'intensPeak'"
else
    Formula (part): 0, 0, 1, 1, "self * Sound_gainIntensity(x - 'tStartS') * 'intensPeak'"
    Formula (part): 0, 0, 2, 2, "self * Sound_gainIntensity(x - 'tStartS') * 'intensPeak'"
endif

removeObject: gainIntensSound, soundPitched
appendInfoLine: "    done."

# ============================================================
# STEP 3 — PAN  (vectorized Formula, equal-power)
# ============================================================
appendInfoLine: "  [3/4] Pan..."

gainPanLSound = Read from file: gainPanL$
Rename: "gainPanL"
gainPanRSound = Read from file: gainPanR$
Rename: "gainPanR"
panLPeak = number (readFile$ (gainPanL$ + ".peak"))
panRPeak = number (readFile$ (gainPanR$ + ".peak"))

# Ensure stereo
selectObject: soundIntensity
nCh = Get number of channels
if nCh = 1
    soundStereo = Convert to stereo
    removeObject: soundIntensity
else
    soundStereo = Copy: "stereo"
    removeObject: soundIntensity
endif

# Apply L and R gain envelopes
selectObject: soundStereo
Formula (part): 0, 0, 1, 1, "self * Sound_gainPanL(x - 'tStartS') * 'panLPeak'"
Formula (part): 0, 0, 2, 2, "self * Sound_gainPanR(x - 'tStartS') * 'panRPeak'"
soundPanned = soundStereo
Rename: "panned"

removeObject: gainPanLSound, gainPanRSound
appendInfoLine: "    done."

# ============================================================
# STEP 4 — FILTER  (spectral morph: fixed LP <-> dry <-> fixed HP)
# ============================================================
appendInfoLine: "  [4/4] Filter..."

filtMatrix = Read Matrix from raw text file: filterFile$
nFiltPts   = Get number of rows

# Check if filter is all-neutral (all values within 50 Hz of 1000)
filterActive = 0
for i from 1 to nFiltPts
    selectObject: filtMatrix
    fcCheck = Get value in cell: i, 2
    if abs (fcCheck - 1000) > 50
        filterActive = 1
    endif
endfor
removeObject: filtMatrix

if filterActive = 0
    soundFiltered = soundPanned
    appendInfoLine: "    skipped (all neutral)."
else
    selectObject: soundPanned
    nSampF  = Get number of samples
    srF     = Get sampling frequency
    tStartF = Get start time

    runSubprocess: pythonCmd$, pythonScript$, "filter", filterFile$,
        ... string$(srF), string$(nSampF), string$(tStartF),
        ... gainFiltLP$, gainFiltHP$, gainFiltDry$

    # Filter the whole sound once at each fixed endpoint.
    # The control is a spectral morph coordinate: <=300 reaches LP,
    # 1000 is dry, and >=3000 reaches HP; it is not a literal moving cutoff.
    selectObject: soundPanned
    soundLP = Filter (pass Hann band): 0, 300, 100
    Rename: "filt_lp"

    selectObject: soundPanned
    soundHP = Filter (pass Hann band): 3000, 0, 100
    Rename: "filt_hp"

    # Load blend weight sounds
    gainLP  = Read from file: gainFiltLP$
    Rename: "gainFiltLP"
    peakLP  = number (readFile$ (gainFiltLP$ + ".peak"))

    gainHP  = Read from file: gainFiltHP$
    Rename: "gainFiltHP"
    peakHP  = number (readFile$ (gainFiltHP$ + ".peak"))

    gainDry = Read from file: gainFiltDry$
    Rename: "gainFiltDry"
    peakDry = number (readFile$ (gainFiltDry$ + ".peak"))

    # Blend all three
    selectObject: soundPanned
    soundFiltered = Copy: "filtered"
    nChF = Get number of channels

    if nChF = 1
        Formula: "self * Sound_gainFiltDry(x - 'tStartF') * 'peakDry' + Sound_filt_lp(x) * Sound_gainFiltLP(x - 'tStartF') * 'peakLP' + Sound_filt_hp(x) * Sound_gainFiltHP(x - 'tStartF') * 'peakHP'"
    else
        Formula (part): 0, 0, 1, 1, "self * Sound_gainFiltDry(x - 'tStartF') * 'peakDry' + Sound_filt_lp(x) * Sound_gainFiltLP(x - 'tStartF') * 'peakLP' + Sound_filt_hp(x) * Sound_gainFiltHP(x - 'tStartF') * 'peakHP'"
        Formula (part): 0, 0, 2, 2, "self * Sound_gainFiltDry(x - 'tStartF') * 'peakDry' + Sound_filt_lp(x) * Sound_gainFiltLP(x - 'tStartF') * 'peakLP' + Sound_filt_hp(x) * Sound_gainFiltHP(x - 'tStartF') * 'peakHP'"
    endif

    removeObject: gainLP, gainHP, gainDry
    removeObject: soundLP, soundHP
    removeObject: soundPanned

    appendInfoLine: "    done."
endif

    # ============================================================
    # OUTPUT (this pass)
    # ============================================================
    selectObject: soundFiltered
    Rename: soundName$ + "_enved"
    result = selected ("Sound")

    selectObject: result
    rms_out = Get root-mean-square: 0, 0
    nch_out = Get number of channels
    dur_out = Get total duration

    appendInfoLine: ""
    appendInfoLine: "--- Pass ", iteration, ": ", soundName$ + "_enved ---"
    appendInfoLine: "Duration: ", fixed$ (dur_out, 3), " s   Channels: ", nch_out
    appendInfoLine: "RMS:      ", fixed$ (rms_out, 6)
    if rms_out < 0.0001
        appendInfoLine: "WARNING: output is silent!"
    else
        appendInfoLine: "OK"
    endif

    # ---- Explicit GUI Audition versus Apply ----
    if action$ = "audition"
        selectObject: result
        Play
        appendInfoLine: "Audition played -- reopening editor automatically."
        # auditioning remains 1, so the current curves reopen immediately.
    else
        choosing = 1
        while choosing
            selectObject: result
            Play
            beginPause: "Envelope Editor -- Applied render (pass " + string$(iteration) + ")"
                comment: "Result: " + soundName$ + "_enved"
                comment: ""
                comment: "Play again  -- replay this render"
                comment: "Tweak again -- reopen the editor with your current curves"
                comment: "Keep        -- finish, leaving this render in the object list"
            clickedAud = endPause: "Play again", "Tweak again", "Keep", 3
            if clickedAud = 1
                # replay -- loop
            elsif clickedAud = 2
                choosing = 0
                # auditioning stays 1 -> reopen the editor for another pass
            else
                choosing = 0
                auditioning = 0
            endif
        endwhile
    endif
    endif
endwhile

# ============================================================
# FINAL CLEANUP
# ============================================================
@cleanUpTempFiles

selectObject: result
appendInfoLine: ""
appendInfoLine: "Kept: ", soundName$, "_enved  (", iteration, " pass(es))"
appendInfoLine: "Done."