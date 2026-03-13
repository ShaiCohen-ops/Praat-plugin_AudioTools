# ============================================================
# Praat AudioTools Plugin
# Script:      Envelope_Editor.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     2.0 (2025)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Opens a Python GUI with four independent breakpoint envelope lanes,
#   then applies all processing natively in Praat:
#
#     1. Pitch      — via To Manipulation + PitchTier (PSOLA resynthesis)
#     2. Intensity  — via IntensityTier multiply
#     3. Pan        — via AmplitudeTier on L/R channels
#     4. Filter     — segmented Hann-band pass filter
#
# Workflow:
#   1. Python GUI writes a breakpoints JSON file
#   2. Praat reads JSON (via Python one-liner), builds native tiers
#   3. Praat applies each effect in sequence
#   4. Result added to object list
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

# ---- Paths ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/envelope_editor.py"
bpFile$       = pluginDir$ + "temp_enved_breakpoints.json"
gainIntens$   = pluginDir$ + "temp_gain_intensity.wav"
gainPanL$     = pluginDir$ + "temp_gain_panL.wav"
gainPanR$     = pluginDir$ + "temp_gain_panR.wav"
pitchFile$    = pluginDir$ + "temp_bp_pitch.txt"
filterFile$   = pluginDir$ + "temp_bp_filter.txt"

# Clean stale files from any previous run
if fileReadable (bpFile$)
    deleteFile: bpFile$
endif
if fileReadable (gainIntens$)
    deleteFile: gainIntens$
endif
if fileReadable (gainPanL$)
    deleteFile: gainPanL$
endif
if fileReadable (gainPanR$)
    deleteFile: gainPanR$
endif
if fileReadable (pitchFile$)
    deleteFile: pitchFile$
endif
if fileReadable (filterFile$)
    deleteFile: filterFile$
endif

# ---- Robust Python detection (tkinter only needed now) ----
pythonCmd$   = ""
probeMarker$ = pluginDir$ + "temp_enved_probe.ok"

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

    if fileReadable (probeMarker$)
        deleteFile: probeMarker$
    endif

    probeCode$ = "import tkinter; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable (probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
    endif

    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    exitScript: "Cannot find Python with tkinter." + newline$
        ... + "tkinter ships with standard Python — reinstall Python."
endif

# ---- Launch GUI ----
clearinfo
appendInfoLine: "=== Envelope Editor 2.0 ==="
appendInfoLine: "Sound:    ", soundName$
appendInfoLine: "Duration: ", fixed$ (duration, 3), " s"
appendInfoLine: "Python:   ", pythonCmd$
appendInfoLine: ""
appendInfoLine: "Opening envelope editor..."

runSystem_nocheck: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " " + fixed$ (duration, 6)
    ... + " """ + bpFile$ + """"

# ---- Check result ----
if not fileReadable (bpFile$)
    appendInfoLine: "Cancelled."
    exitScript: "Envelope Editor cancelled."
endif

appendInfoLine: "Breakpoints received. Applying DSP in Praat..."

# ---- Python: interpolate envelopes, write gain WAVs + breakpoint texts ----
# envelope_editor.py handles both the GUI and DSP modes.
# Gain WAVs are int16-normalised; a .peak sidecar holds the true scale factor.
# Praat applies them with Formula: "self * Sound_name(x)" — fully vectorized,
# no sample loops in Praat script at all (same pattern as DBAP).

selectObject: sound
nSampTotal = Get number of samples
srTotal    = Get sampling frequency
tStartS    = Get start time

runSystem: pythonCmd$ +
    ... " """ + pythonScript$         + """" +
    ... " envelopes"                          +
    ... " """ + bpFile$              + """" +
    ... " "   + string$ (nSampTotal) +
    ... " "   + string$ (srTotal)    +
    ... " "   + string$ (tStartS)    +
    ... " """ + gainIntens$          + """" +
    ... " """ + gainPanL$            + """" +
    ... " """ + gainPanR$            + """" +
    ... " """ + pitchFile$           + """" +
    ... " """ + filterFile$          + """"

# ============================================================
# STEP 1 — PITCH  (Manipulation / PSOLA resynthesis)
# ============================================================
appendInfoLine: "  [1/4] Pitch..."

selectObject: sound
To Manipulation: 0.01, 75, 600
manipulation = selected ("Manipulation")

selectObject: manipulation
Extract pitch tier
pitchTierOrig = selected ("PitchTier")
nOrigPts = Get number of points

# Read semitone-shift breakpoints
pitchMatrix = Read Matrix from raw text file: pitchFile$
nShiftPts   = Get number of rows

selectObject: pitchTierOrig
tStart = Get start time
tEnd   = Get end time

Create PitchTier: "shifted", tStart, tEnd
pitchTierNew = selected ("PitchTier")

# Shift each original pitch point by the interpolated semitone shift
for i from 1 to nOrigPts
    selectObject: pitchTierOrig
    t  = Get time from index: i
    hz = Get value at index: i

    # Interpolate shift_st from pitchMatrix at time t
    selectObject: pitchMatrix
    shift_st = 0
    for row from 1 to nShiftPts - 1
        t0 = Get value in cell: row,     1
        t1 = Get value in cell: row + 1, 1
        if t >= t0 and t <= t1
            v0 = Get value in cell: row,     2
            v1 = Get value in cell: row + 1, 2
            if t1 > t0
                shift_st = v0 + (t - t0) / (t1 - t0) * (v1 - v0)
            else
                shift_st = v0
            endif
        endif
    endfor

    newHz = hz * (2 ^ (shift_st / 12))
    newHz = max (newHz, 50)
    newHz = min (newHz, 800)

    selectObject: pitchTierNew
    Add point: t, newHz
endfor

# For unvoiced sounds: seed pitch tier from shift breakpoints at 100 Hz ref
if nOrigPts = 0
    for i from 1 to nShiftPts
        selectObject: pitchMatrix
        t        = Get value in cell: i, 1
        shift_st = Get value in cell: i, 2
        newHz    = 100 * (2 ^ (shift_st / 12))
        newHz    = max (newHz, 50)
        newHz    = min (newHz, 800)
        selectObject: pitchTierNew
        Add point: t, newHz
    endfor
endif

# Replace and resynthesize
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

# ============================================================
# STEP 2 — INTENSITY  (vectorized Formula, DBAP-style)
# ============================================================
appendInfoLine: "  [2/4] Intensity..."

gainIntensSound = Read from file: gainIntens$
Rename: "gainIntensity"
intensPeak = number (readFile$ (gainIntens$ + ".peak"))

# Sound_gainIntensity(x) interpolates the gain sound at time x.
# Multiply by intensPeak to undo the int16 normalisation Python applied.
selectObject: soundPitched
soundIntensity = Copy: "intensity"
nChI = Get number of channels
if nChI = 1
    Formula: "self * Sound_gainIntensity(x) * 'intensPeak'"
else
    Formula (part): 0, 0, 1, 1, "self * Sound_gainIntensity(x) * 'intensPeak'"
    Formula (part): 0, 0, 2, 2, "self * Sound_gainIntensity(x) * 'intensPeak'"
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

# Apply L and R gain envelopes — one Formula call each, fully vectorized
selectObject: soundStereo
Formula (part): 0, 0, 1, 1, "self * Sound_gainPanL(x) * 'panLPeak'"
Formula (part): 0, 0, 2, 2, "self * Sound_gainPanR(x) * 'panRPeak'"
soundPanned = soundStereo
Rename: "panned"

removeObject: gainPanLSound, gainPanRSound
appendInfoLine: "    done."

# ============================================================
# STEP 4 — FILTER  (segmented Hann-band pass)
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
    # Artifact-free time-varying filter via 3-way blend:
    #   dry signal  × wDry(t)
    # + lowpass 300Hz × wLP(t)
    # + highpass 3kHz × wHP(t)
    # where wDry + wLP + wHP = 1 at every sample → no amplitude loss.
    # Python writes the three weight WAVs; Praat blends in one Formula call.

    gainFiltLP$  = pluginDir$ + "temp_gain_filtLP.wav"
    gainFiltHP$  = pluginDir$ + "temp_gain_filtHP.wav"
    gainFiltDry$ = pluginDir$ + "temp_gain_filtDry.wav"

    selectObject: soundPanned
    nSampF  = Get number of samples
    srF     = Get sampling frequency
    tStartF = Get start time

    runSystem: pythonCmd$ +
        ... " """ + pythonScript$         + """" +
        ... " filter"                            +
        ... " """ + filterFile$          + """" +
        ... " "   + string$ (srF)        +
        ... " "   + string$ (nSampF)     +
        ... " "   + string$ (tStartF)    +
        ... " """ + gainFiltLP$          + """" +
        ... " """ + gainFiltHP$          + """" +
        ... " """ + gainFiltDry$         + """"

    # Filter the whole sound once at each fixed frequency
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

    # Blend all three — one vectorized Formula call, no segment cuts
    selectObject: soundPanned
    soundFiltered = Copy: "filtered"
    nChF = Get number of channels

    if nChF = 1
        Formula: "self * Sound_gainFiltDry(x) * 'peakDry' + Sound_filt_lp(x) * Sound_gainFiltLP(x) * 'peakLP' + Sound_filt_hp(x) * Sound_gainFiltHP(x) * 'peakHP'"
    else
        Formula (part): 0, 0, 1, 1, "self * Sound_gainFiltDry(x) * 'peakDry' + Sound_filt_lp(x) * Sound_gainFiltLP(x) * 'peakLP' + Sound_filt_hp(x) * Sound_gainFiltHP(x) * 'peakHP'"
        Formula (part): 0, 0, 2, 2, "self * Sound_gainFiltDry(x) * 'peakDry' + Sound_filt_lp(x) * Sound_gainFiltLP(x) * 'peakLP' + Sound_filt_hp(x) * Sound_gainFiltHP(x) * 'peakHP'"
    endif

    removeObject: gainLP, gainHP, gainDry
    removeObject: soundLP, soundHP
    removeObject: soundPanned

    deleteFile: gainFiltLP$
    deleteFile: gainFiltLP$ + ".peak"
    deleteFile: gainFiltHP$
    deleteFile: gainFiltHP$ + ".peak"
    deleteFile: gainFiltDry$
    deleteFile: gainFiltDry$ + ".peak"

    appendInfoLine: "    done."
endif

# ============================================================
# OUTPUT & CLEANUP
# ============================================================
selectObject: soundFiltered
Rename: soundName$ + "_enved"
result = selected ("Sound")

selectObject: result
rms_out = Get root-mean-square: 0, 0
nch_out = Get number of channels
dur_out = Get total duration

appendInfoLine: ""
appendInfoLine: "--- Output: ", soundName$ + "_enved ---"
appendInfoLine: "Duration: ", fixed$ (dur_out, 3), " s   Channels: ", nch_out
appendInfoLine: "RMS:      ", fixed$ (rms_out, 6)
if rms_out < 0.0001
    appendInfoLine: "WARNING: output is silent!"
else
    appendInfoLine: "OK"
endif

deleteFile: bpFile$
deleteFile: gainIntens$
deleteFile: gainIntens$ + ".peak"
deleteFile: gainPanL$
deleteFile: gainPanL$ + ".peak"
deleteFile: gainPanR$
deleteFile: gainPanR$ + ".peak"
deleteFile: pitchFile$
deleteFile: filterFile$

selectObject: result
Play

appendInfoLine: ""
appendInfoLine: "Done."
