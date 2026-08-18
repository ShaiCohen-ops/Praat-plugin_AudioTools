# ============================================================
# Praat AudioTools - InternalPolyphony.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.6 (2026) - Unified Cross-Platform Version
# License: MIT License
# v2.4 frontend: short-source rescue retained; Python v2.4 prevents correlated
# self-overlap when sparse Support/Halo pools contain too few unique fragments.
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Internal Polyphony
#
#   Discovers hidden simultaneous internal voices (support, body,
#   accent, halo, residue, shimmer) latent inside one sound using
#   NMF-based functional role decomposition and source-derived
#   waveform recomposition.
#
#   This is not a denoiser, not a latent-space gimmick, and not a
#   generic spectral effect. It reveals hidden chamber music already
#   present inside the source.
#
# Python engine: internal_polyphony.py
#
# Dependencies (Python):
#   pip install numpy scipy soundfile
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-Specific Python Discovery ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/internal_polyphony.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/internal_polyphony.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: internal_polyphony.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_intpoly_input.wav"
tempOutput$  = temporaryDirectory$ + "/temp_intpoly_output.wav"
tempReport$  = temporaryDirectory$ + "/temp_intpoly_report.json"
tempCSV$     = temporaryDirectory$ + "/temp_intpoly_roles.csv"
tempTrace$   = temporaryDirectory$ + "/temp_intpoly_trace.txt"
probeMarker$ = temporaryDirectory$ + "/temp_intpoly_probe.ok"

# Replace backslashes for the Python inline probe (Windows safety)
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempReport$)
        deleteFile: tempReport$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    if fileReadable(tempTrace$)
        deleteFile: tempTrace$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Internal Polyphony v2.6
    optionmenu Preset: 1
        option Custom
        option Reveal (subtle)
        option Counterpoint
        option Canon
        option PedalHalo
        option FracturedChoir
    comment __ Decomposition ________________________________________________
    integer Num_components 10
    integer Fft_window 2048
    integer Hop_size 512
    optionmenu Analysis_mode: 1
        option full
        option hpss
        option transient
    comment __ Output / Staging _____________________________________________
    optionmenu Polyphony_mode: 3
        option reveal
        option counterpoint
        option canon
        option pedalhalo
        option fracturedchoir
    real Voice_density 0.65
    real Min_fragment_sec 0.15
    real Expansion_factor 1.0
    comment __ Mix / Character _______________________________________________
    real Dry_wet 0.85
    real Accent_prominence 0.7
    real Halo_amount 0.6
    real Stereo_width 1.2
    comment __ Options _______________________________________________________
    integer Random_seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- APPLY PRESETS ----
if preset = 2
    polyphony_mode = 1
    voice_density  = 0.45
    dry_wet        = 0.65
    accent_prominence = 0.4
    halo_amount    = 0.5
    stereo_width   = 0.9
    presetName$    = "Reveal"
elsif preset = 3
    polyphony_mode = 2
    voice_density  = 0.7
    dry_wet        = 0.9
    accent_prominence = 0.8
    halo_amount    = 0.55
    stereo_width   = 1.3
    presetName$    = "Counterpoint"
elsif preset = 4
    polyphony_mode = 3
    voice_density  = 0.6
    dry_wet        = 0.85
    accent_prominence = 0.6
    halo_amount    = 0.65
    stereo_width   = 1.4
    presetName$    = "Canon"
elsif preset = 5
    polyphony_mode = 4
    voice_density  = 0.55
    dry_wet        = 0.80
    accent_prominence = 0.3
    halo_amount    = 0.9
    stereo_width   = 1.5
    presetName$    = "PedalHalo"
elsif preset = 6
    polyphony_mode = 5
    voice_density  = 0.9
    dry_wet        = 0.95
    accent_prominence = 0.75
    halo_amount    = 0.5
    stereo_width   = 1.6
    presetName$    = "FracturedChoir"
else
    presetName$ = "Custom"
endif

# ---- MAP OPTION MENUS TO STRINGS ----
if analysis_mode = 1
    analysisModeStr$ = "full"
elsif analysis_mode = 2
    analysisModeStr$ = "hpss"
else
    analysisModeStr$ = "transient"
endif

if polyphony_mode = 1
    polyModeStr$ = "reveal"
elsif polyphony_mode = 2
    polyModeStr$ = "counterpoint"
elsif polyphony_mode = 3
    polyModeStr$ = "canon"
elsif polyphony_mode = 4
    polyModeStr$ = "pedalhalo"
else
    polyModeStr$ = "fracturedchoir"
endif

# ---- CLAMP VALUES ----
if num_components < 3
    num_components = 3
endif
if num_components > 24
    num_components = 24
endif
if fft_window < 256
    fft_window = 256
endif
if hop_size < 64
    hop_size = 64
endif
if hop_size > fft_window
    hop_size = fft_window / 2
endif
if voice_density < 0.05
    voice_density = 0.05
endif
if voice_density > 1
    voice_density = 1
endif
if min_fragment_sec < 0.05
    min_fragment_sec = 0.05
endif
if expansion_factor < 0.5
    expansion_factor = 0.5
endif
if expansion_factor > 4
    expansion_factor = 4
endif
if dry_wet < 0
    dry_wet = 0
endif
if dry_wet > 1
    dry_wet = 1
endif
if accent_prominence < 0
    accent_prominence = 0
endif
if accent_prominence > 2
    accent_prominence = 2
endif
if halo_amount < 0
    halo_amount = 0
endif
if halo_amount > 2
    halo_amount = 2
endif
if stereo_width < 0
    stereo_width = 0
endif
if stereo_width > 3
    stereo_width = 3
endif

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
srcMax    = Get maximum: 0, 0, "None"
srcMin    = Get minimum: 0, 0, "None"
srcPeak   = max(abs(srcMax), abs(srcMin))
if srcPeak <= 0
    srcPeak = 1
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Internal Polyphony v2.6 ==="
appendInfoLine: "Input:    ", soundName$
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: ""
appendInfoLine: "Components:  ", num_components
appendInfoLine: "FFT window:  ", fft_window, "  hop: ", hop_size
appendInfoLine: "Analysis:    ", analysisModeStr$
appendInfoLine: "Mode:        ", polyModeStr$
appendInfoLine: "Density:     ", fixed$(voice_density, 2)
appendInfoLine: "Dry/wet:     ", fixed$(dry_wet, 2)
appendInfoLine: "Expansion:   ", fixed$(expansion_factor, 2)
appendInfoLine: "Seed:        ", random_seed
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Ch: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/4] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Export Source Audio
# ===========================================================================
appendInfoLine: "[2/4] Exporting source audio..."

selectObject: sound
Save as WAV file: tempInput$

# ===========================================================================
# Stage 3 — Call Python Engine
# ===========================================================================
appendInfoLine: "[3/4] Running Python engine (this may take a while)..."
appendInfoLine: "  Components: ", num_components, " | Mode: ", polyModeStr$
appendInfoLine: "  Analysis: ", analysisModeStr$, " | Density: ", fixed$(voice_density, 2)

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " --input """    + tempInput$  + """"
    ... + " --output """   + tempOutput$ + """"
    ... + " --report """   + tempReport$ + """"
    ... + " --csv """      + tempCSV$    + """"
    ... + " --trace """    + tempTrace$  + """"
    ... + " --components " + string$(num_components)
    ... + " --fft "        + string$(fft_window)
    ... + " --hop "        + string$(hop_size)
    ... + " --analysis "   + analysisModeStr$
    ... + " --mode "       + polyModeStr$
    ... + " --density "    + fixed$(voice_density, 4)
    ... + " --minfrag "    + fixed$(min_fragment_sec, 4)
    ... + " --expand "     + fixed$(expansion_factor, 4)
    ... + " --drywet "     + fixed$(dry_wet, 4)
    ... + " --accent "     + fixed$(accent_prominence, 4)
    ... + " --halo "       + fixed$(halo_amount, 4)
    ... + " --width "      + fixed$(stereo_width, 4)
    ... + " --seed "       + string$(random_seed)

runSystem_nocheck: pythonCall$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python engine failed — output file not found." + newline$ + "Run in terminal to see error: " + pythonCall$
endif

# ===========================================================================
# Stage 4 — Import Result + Parse Report
# ===========================================================================
appendInfoLine: "[4/4] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_polyphony"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration
outMax  = Get maximum: 0, 0, "None"
outMin  = Get minimum: 0, 0, "None"
outPeak = max(abs(outMax), abs(outMin))
if outPeak <= 0
    outPeak = 1
endif
selectObject: sound
rms_in  = Get root-mean-square: 0, 0

# ---- Parse JSON report ----
nComponents$    = "?"
effectiveComp$  = "?"
decompError$    = "?"
outputRMS$      = "?"
outputPeak$     = "?"
noveltyRatio$   = "?"
overlapDensity$ = "?"
stereoSpread$   = "?"
voiceIndep$     = "?"
rolesPresent$   = "?"
nRolesPresent$  = "?"
modeReport$     = "?"
warningReport$  = ""
shortRescue$    = "0"
effectiveMinfrag$ = "?"

nRoles = 6
roleName_1$ = "support"
roleName_2$ = "body"
roleName_3$ = "accent"
roleName_4$ = "halo"
roleName_5$ = "residue"
roleName_6$ = "shimmer"

for iR from 1 to nRoles
    role_dur_'iR'$    = "?"
    role_frags_'iR'$  = "?"
    role_avgdur_'iR'$ = "?"
    role_rms_'iR'$    = "?"
    roleAct_'iR'      = 0
endfor

if fileReadable(tempReport$)
    reportText$ = readFile$(tempReport$)

    @parseJsonField: reportText$, "n_components"
    nComponents$ = parseJsonField.result$
    @parseJsonField: reportText$, "effective_components"
    effectiveComp$ = parseJsonField.result$
    @parseJsonField: reportText$, "decomp_error"
    decompError$ = parseJsonField.result$
    @parseJsonField: reportText$, "output_rms"
    outputRMS$ = parseJsonField.result$
    @parseJsonField: reportText$, "output_peak"
    outputPeak$ = parseJsonField.result$
    @parseJsonField: reportText$, "novelty_ratio"
    noveltyRatio$ = parseJsonField.result$
    @parseJsonField: reportText$, "overlap_density"
    overlapDensity$ = parseJsonField.result$
    @parseJsonField: reportText$, "stereo_spread"
    stereoSpread$ = parseJsonField.result$
    @parseJsonField: reportText$, "voice_independence"
    voiceIndep$ = parseJsonField.result$
    @parseJsonField: reportText$, "roles_present"
    rolesPresent$ = parseJsonField.result$
    @parseJsonField: reportText$, "n_roles_present"
    nRolesPresent$ = parseJsonField.result$
    @parseJsonField: reportText$, "mode"
    modeReport$ = parseJsonField.result$
    @parseJsonField: reportText$, "warning"
    warningReport$ = parseJsonField.result$
    @parseJsonField: reportText$, "short_source_rescue"
    shortRescue$ = parseJsonField.result$
    @parseJsonField: reportText$, "effective_minfrag"
    effectiveMinfrag$ = parseJsonField.result$

    if warningReport$ = "?"
        warningReport$ = ""
    endif

    for iR from 1 to nRoles
        rn$ = roleName_'iR'$
        @parseJsonField: reportText$, rn$ + "_duration"
        role_dur_'iR'$ = parseJsonField.result$
        @parseJsonField: reportText$, rn$ + "_fragments"
        role_frags_'iR'$ = parseJsonField.result$
        @parseJsonField: reportText$, rn$ + "_avg_frag_dur"
        role_avgdur_'iR'$ = parseJsonField.result$
        @parseJsonField: reportText$, rn$ + "_rms"
        role_rms_'iR'$ = parseJsonField.result$
        @parseJsonField: reportText$, rn$ + "_activity"
        actStr$ = parseJsonField.result$
        if actStr$ <> "?" and actStr$ <> ""
            roleAct_'iR' = number(actStr$)
        endif
    endfor
endif

###############################################################################
# VISUALIZATION  (v2.6 - process idiom, simple)
#
#   SOURCE     what we started from        [source time]
#   HARVEST    where each role was found   [source time]
#   SCORE      where it was placed         [output time]
#   OUTPUT     what came out               [output time]
#
# The two lane panels are drawn from the engine's process trace.
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    gutL = 0.30
    gutR = 1.50
    datR = 7.74

    ySrcT = 0.60
    ySrcB = 1.28
    yHarT = 1.50
    yHarB = 3.90
    yScoT = 4.42
    yScoB = 6.82
    yOutT = 7.04
    yOutB = 7.72

    rColR_1 = 0.25
    rColG_1 = 0.45
    rColB_1 = 0.75
    rColR_2 = 0.30
    rColG_2 = 0.65
    rColB_2 = 0.40
    rColR_3 = 0.80
    rColG_3 = 0.35
    rColB_3 = 0.25
    rColR_4 = 0.65
    rColG_4 = 0.35
    rColB_4 = 0.75
    rColR_5 = 0.45
    rColG_5 = 0.45
    rColB_5 = 0.45
    rColR_6 = 0.80
    rColG_6 = 0.65
    rColB_6 = 0.15

    # ---- read the process trace ----
    traceOK   = 0
    nFragRow  = 0
    nPlaceRow = 0
    srcDurT   = dur
    tgtDurT   = durOut

    for iR from 1 to nRoles
        stageOff_'iR'   = 0
        stageGain_'iR'  = 1
        stageLaw_'iR'$  = ""
        fragCount_'iR'  = 0
        placeCount_'iR' = 0
    endfor

    if fileReadable(tempTrace$)
        traceTable = Read Table from tab-separated file: tempTrace$
        nTraceRow  = Get number of rows
        if nTraceRow > 0
            traceOK = 1
        endif

        for iRow from 1 to nTraceRow
            selectObject: traceTable
            kind$ = Get value: iRow, "kind"
            rn$   = Get value: iRow, "role"

            rIdx = 0
            for iR from 1 to nRoles
                cmp$ = roleName_'iR'$
                if rn$ = cmp$
                    rIdx = iR
                endif
            endfor

            if kind$ = "meta"
                mv = Get value: iRow, "t1"
                if rn$ = "source"
                    srcDurT = mv
                elsif rn$ = "target"
                    tgtDurT = mv
                endif

            elsif kind$ = "frag" and rIdx > 0
                nFragRow += 1
                fragRole[nFragRow] = rIdx
                fragIdx [nFragRow] = Get value: iRow, "idx"
                fragT0  [nFragRow] = Get value: iRow, "t0"
                fragT1  [nFragRow] = Get value: iRow, "t1"
                fragQ   [nFragRow] = Get value: iRow, "v1"
                fragCount_'rIdx' += 1

            elsif kind$ = "place" and rIdx > 0
                nPlaceRow += 1
                placeRole[nPlaceRow] = rIdx
                placeIdx [nPlaceRow] = Get value: iRow, "idx"
                placeT0  [nPlaceRow] = Get value: iRow, "t0"
                placeT1  [nPlaceRow] = Get value: iRow, "t1"
                placeG   [nPlaceRow] = Get value: iRow, "v1"
                placeCount_'rIdx' += 1

            elsif kind$ = "stage" and rIdx > 0
                law$ = Get value: iRow, "law"
                sOff = Get value: iRow, "t0"
                sGn  = Get value: iRow, "v1"
                if law$ = "entry-shift" or law$ = "canonic-delay"
                        ... or law$ = "emergence-ramp"
                    stageOff_'rIdx'  = sOff
                    stageLaw_'rIdx'$ = law$
                else
                    stageGain_'rIdx' = stageGain_'rIdx' * sGn
                endif
            endif
        endfor
        removeObject: traceTable
    endif

    if srcDurT <= 0
        srcDurT = dur
    endif
    if tgtDurT <= 0
        tgtDurT = durOut
    endif

    # only a true delay relocates a block; a ramp only changes its level
    for iR from 1 to nRoles
        shiftOff_'iR' = 0
        lw$ = stageLaw_'iR'$
        if lw$ = "entry-shift" or lw$ = "canonic-delay"
            shiftOff_'iR' = stageOff_'iR'
        endif
    endfor

    @tickStep: srcDurT
    srcTick = tickStep.result
    @tickStep: tgtDurT
    tgtTick = tickStep.result

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Line width: 1

    # =====================================================================
    # Title
    # =====================================================================
    Select inner viewport: gutL, datR, 0.06, 0.48
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Internal Polyphony##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", 0.22, "half",
        ... replace$(soundName$, "_", "\_ ", 0) + "   |   " + polyModeStr$
        ... + "   |   " + string$(nFragRow) + " fragments -> "
        ... + string$(nPlaceRow) + " placements   |   seed " + string$(random_seed)

    # =====================================================================
    # SOURCE
    # =====================================================================
    Select inner viewport: gutL, gutR, ySrcT, ySrcB
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.90, "right", 0.50, "half", "##SOURCE##"

    Select inner viewport: gutR, datR, ySrcT, ySrcB
    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, srcDurT, -srcPeak, srcPeak, "no", "Curve"
    Select inner viewport: gutR, datR, ySrcT, ySrcB
    Axes: 0, srcDurT, -srcPeak, srcPeak
    Colour: "Black"
    Draw inner box

    # =====================================================================
    # HARVEST  [source time]
    # =====================================================================
    Select inner viewport: gutR, datR, yHarT, yHarB
    Axes: 0, srcDurT, 0, nRoles
    Paint rectangle: "{0.965, 0.965, 0.975}", 0, srcDurT, 0, nRoles
    for iR from 1 to nRoles
        if fragCount_'iR' = 0
            Paint rectangle: "{0.925, 0.925, 0.935}", 0, srcDurT,
                ... nRoles - iR + 0.05, nRoles - iR + 0.95
        endif
    endfor

    for iF from 1 to nFragRow
        rI = fragRole[iF]
        x0 = fragT0[iF]
        x1 = fragT1[iF]
        wMin = srcDurT * 0.004
        if x1 - x0 < wMin
            x1 = x0 + wMin
        endif
        shade = 0.55 + 0.45 * (1 - fragIdx[iF] / (fragCount_'rI' + 1))
        cR = 1 - shade * (1 - rColR_'rI')
        cG = 1 - shade * (1 - rColG_'rI')
        cB = 1 - shade * (1 - rColB_'rI')
        Select inner viewport: gutR, datR, yHarT, yHarB
        Axes: 0, srcDurT, 0, nRoles
        Paint rectangle: "{'cR', 'cG', 'cB'}", x0, x1,
            ... nRoles - rI + 0.18, nRoles - rI + 0.82
    endfor

    Select inner viewport: gutR, datR, yHarT, yHarB
    Axes: 0, srcDurT, 0, nRoles
    Colour: "{0.78, 0.78, 0.82}"
    for iR from 1 to nRoles - 1
        Draw line: 0, iR, srcDurT, iR
    endfor
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, srcTick, "yes", "yes", "no"
    Select inner viewport: gutR, datR, yHarT, yHarB
    Axes: 0, srcDurT, 0, nRoles
    Font size: 6
    Text bottom: "yes", "source time (s)"

    Select inner viewport: gutL, gutR, yHarT, yHarB
    Axes: 0, 1, 0, nRoles
    Font size: 7
    Colour: "Black"
    Text: 0.90, "right", nRoles + 0.30, "half", "##HARVEST##"
    for iR from 1 to nRoles
        rn$ = roleName_'iR'$
        yMid = nRoles - iR + 0.5
        Font size: 6
        if fragCount_'iR' > 0
            Colour: "Black"
            Text: 0.90, "right", yMid, "half",
                ... rn$ + "   " + string$(fragCount_'iR')
        else
            Colour: "{0.62, 0.62, 0.62}"
            Text: 0.90, "right", yMid, "half", rn$
        endif
    endfor

    # =====================================================================
    # SCORE  [output time]
    # =====================================================================
    Select inner viewport: gutR, datR, yScoT, yScoB
    Axes: 0, tgtDurT, 0, nRoles
    Paint rectangle: "{0.965, 0.965, 0.975}", 0, tgtDurT, 0, nRoles
    for iR from 1 to nRoles
        if placeCount_'iR' = 0
            Paint rectangle: "{0.925, 0.925, 0.935}", 0, tgtDurT,
                ... nRoles - iR + 0.05, nRoles - iR + 0.95
        endif
    endfor

    for iP from 1 to nPlaceRow
        rI = placeRole[iP]
        gn = placeG[iP] * stageGain_'rI'
        if stageLaw_'rI'$ = "emergence-ramp"
            tMid  = (placeT0[iP] + placeT1[iP]) / 2
            rSpan = tgtDurT - stageOff_'rI'
            if rSpan <= 0
                rFac = 1
            else
                rFac = (tMid - stageOff_'rI') / rSpan
            endif
            if rFac < 0
                rFac = 0
            endif
            if rFac > 1
                rFac = 1
            endif
            gn = gn * rFac ^ 1.5
        endif
        if gn > 1
            gn = 1
        endif
        if gn < 0.06
            gn = 0.06
        endif
        x0 = placeT0[iP] + shiftOff_'rI'
        x1 = placeT1[iP] + shiftOff_'rI'
        if x0 < tgtDurT
            if x1 > tgtDurT
                x1 = tgtDurT
            endif
            wMin = tgtDurT * 0.004
            if x1 - x0 < wMin
                x1 = x0 + wMin
            endif
            yB = nRoles - rI + 0.10
            shade = 0.55 + 0.45 * (1 - placeIdx[iP] / (fragCount_'rI' + 1))
            cR = 1 - shade * (1 - rColR_'rI')
            cG = 1 - shade * (1 - rColG_'rI')
            cB = 1 - shade * (1 - rColB_'rI')
            Select inner viewport: gutR, datR, yScoT, yScoB
            Axes: 0, tgtDurT, 0, nRoles
            Paint rectangle: "{'cR', 'cG', 'cB'}", x0, x1, yB, yB + 0.78 * gn
            Colour: "{0.30, 0.30, 0.35}"
            Draw line: x0, yB, x0, yB + 0.78 * gn
        endif
    endfor

    for iR from 1 to nRoles
        if placeCount_'iR' > 0 and stageOff_'iR' > 0
            cR = rColR_'iR'
            cG = rColG_'iR'
            cB = rColB_'iR'
            Select inner viewport: gutR, datR, yScoT, yScoB
            Axes: 0, tgtDurT, 0, nRoles
            Colour: "{'cR', 'cG', 'cB'}"
            Line width: 2
            Draw line: stageOff_'iR', nRoles - iR + 0.02,
                ... stageOff_'iR', nRoles - iR + 0.98
            Line width: 1
        endif
    endfor

    Select inner viewport: gutR, datR, yScoT, yScoB
    Axes: 0, tgtDurT, 0, nRoles
    Colour: "{0.78, 0.78, 0.82}"
    for iR from 1 to nRoles - 1
        Draw line: 0, iR, tgtDurT, iR
    endfor
    Colour: "Black"
    Draw inner box

    Select inner viewport: gutL, gutR, yScoT, yScoB
    Axes: 0, 1, 0, nRoles
    Font size: 7
    Colour: "Black"
    Text: 0.90, "right", nRoles + 0.30, "half", "##SCORE##"
    for iR from 1 to nRoles
        rn$ = roleName_'iR'$
        yMid = nRoles - iR + 0.5
        Font size: 6
        if placeCount_'iR' > 0
            Colour: "Black"
            Text: 0.90, "right", yMid, "half",
                ... rn$ + "   " + string$(placeCount_'iR')
        else
            Colour: "{0.62, 0.62, 0.62}"
            Text: 0.90, "right", yMid, "half", rn$
        endif
    endfor

    # =====================================================================
    # OUTPUT
    # =====================================================================
    Select inner viewport: gutR, datR, yOutT, yOutB
    selectObject: resultSound
    Colour: "{0.25, 0.50, 0.78}"
    Draw: 0, tgtDurT, -outPeak, outPeak, "no", "Curve"
    Select inner viewport: gutR, datR, yOutT, yOutB
    Axes: 0, tgtDurT, -outPeak, outPeak
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, tgtTick, "yes", "yes", "no"
    Select inner viewport: gutR, datR, yOutT, yOutB
    Axes: 0, tgtDurT, -outPeak, outPeak
    Font size: 6
    Text bottom: "yes", "output time (s)"

    Select inner viewport: gutL, gutR, yOutT, yOutB
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.90, "right", 0.50, "half", "##OUTPUT##"

    if traceOK = 0
        Select inner viewport: gutR, datR, yHarT, yHarB
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "{0.75, 0.35, 0.15}"
        Text: 0.5, "centre", 0.5, "half",
            ... "process trace unavailable"
    endif

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ===========================================================================
# Cleanup & Summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_polyphony (stereo)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Components:       ", nComponents$, " (effective: ", effectiveComp$, ")"
appendInfoLine: "Decomp error:     ", decompError$
appendInfoLine: "Mode:             ", modeReport$
appendInfoLine: "Duration:         ", fixed$(dur, 2), " s -> ", fixed$(durOut, 2), " s"
appendInfoLine: "RMS:              ", fixed$(rms_in, 4), " -> ", fixed$(rms_out, 4)
appendInfoLine: "Output peak:      ", outputPeak$
appendInfoLine: "Novelty ratio:    ", noveltyRatio$
appendInfoLine: "Overlap density:  ", overlapDensity$
appendInfoLine: "Stereo spread:    ", stereoSpread$
if shortRescue$ = "1"
    appendInfoLine: "Short-source rescue: YES (effective minfrag ", effectiveMinfrag$, " s)"
endif
appendInfoLine: "Voice independence:", voiceIndep$
appendInfoLine: "Roles present:     ", nRolesPresent$, "/6  ", rolesPresent$
appendInfoLine: ""
appendInfoLine: "Role breakdown:"

for iR from 1 to nRoles
    rn$ = roleName_'iR'$
    rdur$ = role_dur_'iR'$
    rfrags$ = role_frags_'iR'$
    ravgd$ = role_avgdur_'iR'$
    rrms$ = role_rms_'iR'$
    if rdur$ = "?"
        rdur$ = "--"
    endif
    if rfrags$ = "?"
        rfrags$ = "--"
    endif
    if ravgd$ = "?"
        ravgd$ = "--"
    endif
    if rrms$ = "?"
        rrms$ = "--"
    endif
    appendInfoLine: "  ", rn$, ":"
    appendInfoLine: "    duration=", rdur$, "s  fragments=", rfrags$, "  avgfrag=", ravgd$, "s  rms=", rrms$
endfor

if warningReport$ <> "?" and warningReport$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", warningReport$
endif

selectObject: resultSound
if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================
procedure tickStep2: .span
    # Integer-count axis: aim for 4-8 numbered marks.
    .result = 1
    if .span > 30
        .result = 10
    elsif .span > 12
        .result = 5
    elsif .span > 6
        .result = 2
    endif
endproc

procedure tickStep: .span
    # Round tick interval giving roughly 6-12 numbered marks on the axis.
    .result = 1
    if .span <= 0
        .result = 1
    elsif .span <= 0.6
        .result = 0.05
    elsif .span <= 1.5
        .result = 0.1
    elsif .span <= 3
        .result = 0.25
    elsif .span <= 8
        .result = 0.5
    elsif .span <= 20
        .result = 1
    elsif .span <= 45
        .result = 5
    elsif .span <= 120
        .result = 10
    else
        .result = 30
    endif
endproc

procedure parseJsonField: .text$, .key$
    .result$ = "?"
    .searchKey$ = """" + .key$ + """"
    .pos = index(.text$, .searchKey$)
    if .pos > 0
        .afterKey = .pos + length(.searchKey$)
        .rest$ = mid$(.text$, .afterKey, length(.text$) - .afterKey + 1)
        .colPos = index(.rest$, ":")
        if .colPos > 0
            .valStart = .colPos + 1
            .valRest$ = mid$(.rest$, .valStart, length(.rest$) - .valStart + 1)
            while left$(.valRest$, 1) = " "
                .valRest$ = mid$(.valRest$, 2, length(.valRest$) - 1)
            endwhile
            if left$(.valRest$, 1) = """"
                .inner$ = mid$(.valRest$, 2, length(.valRest$) - 1)
                .endQ = index(.inner$, """")
                if .endQ > 0
                    .result$ = left$(.inner$, .endQ - 1)
                endif
            else
                .endNum = length(.valRest$)
                .nlPos = index(.valRest$, newline$)
                if .nlPos > 0
                    if .nlPos - 1 < .endNum
                        .endNum = .nlPos - 1
                    endif
                endif
                .commaPos = index(.valRest$, ",")
                if .commaPos > 0
                    if .commaPos - 1 < .endNum
                        .endNum = .commaPos - 1
                    endif
                endif
                .bracePos = index(.valRest$, "}")
                if .bracePos > 0
                    if .bracePos - 1 < .endNum
                        .endNum = .bracePos - 1
                    endif
                endif
                if .endNum < 0
                    .endNum = 0
                endif
                .result$ = left$(.valRest$, .endNum)
                while right$(.result$, 1) = " "
                    .result$ = left$(.result$, length(.result$) - 1)
                endwhile
            endif
        endif
    endif
endproc