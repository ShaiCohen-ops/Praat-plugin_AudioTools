# ============================================================
# Praat AudioTools - Intensity_Driven_Temporal_Walk.praat
# Title: Intensity-Driven Temporal Walk
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Category: CDP
# Version: 0.2 (2026)
# License: MIT License (script); bundled CDP programs retain their
#          respective licenses (LGPL-2.1-or-later).
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Intensity-Driven Temporal Walk transforms a single Sound into a
#   stereo pair of temporal recompositions using the Composers Desktop
#   Project's Drunken Walk process. The left channel uses a constant
#   segment clock, while the right channel uses a time-varying clock
#   derived automatically from Praat's Intensity analysis: loud passages
#   give short segments, quiet passages long ones. Both channels share
#   the same source navigation (locus), stochastic seed and processing
#   parameters, exposing the musical effects of analysis-driven temporal
#   control. Drunken Walk only reorders and splices source segments; it
#   has no transposition stage (pitch relations change only through the
#   reordering).
#
# Input:
#   One Sound, at least 2.5 s. A multichannel Sound is folded to mono for
#   analysis and processing (a temporary copy). The Intensity analysis
#   and IntensityTier are made internally. The original is not changed.
#
# Output:
#   One stereo Sound <name>_IntensityTemporalWalk_Stereo, starting at 0
#   (the output timeline): LEFT = constant clock, RIGHT = intensity-driven
#   clock. No panning, no mono mix, the original is not mixed in. One
#   common attenuation (only if the peak exceeds 0.95) keeps the two
#   channels' relative levels.
#
# Dependencies:
#   Praat 6.4 or newer; the CDP category of Praat AudioTools (this script
#   lives in plugin_AudioTools/CDP/: internal/cdp_engine.praat, the
#   registries, engine/windows). Process: drunk (extend drunk, mode 1).
#   No Python.
#
# Usage:
#   Select one Sound, run, choose a Preset or Custom. Both channels are
#   reproducible for a given Seed.
#
# Changelog v0.2 (2026):
#   - One Sound in: To Intensity + Down to IntensityTier made internally
#     (10 ms analysis step; clock breakpoints thinned to ~50 ms as in
#     the POC); values more than 60 dB below the loudest are floored (a
#     digitally silent stretch reads -300 dB and would flatten the
#     mapping).
#   - One stereo Sound out (left constant, right intensity-driven), one
#     common peak attenuation.
#   - Presets (Custom first; Balanced Walk = the POC configuration).
#   - Form sections, parameter validation, registry-template check,
#     optional 8-inch visualization.
#   - CDP passes unchanged from the POC: same engine calls, locus and
#     clock breakpoint files in OUTPUT time, only the clock differs.
#
# Changelog v0.1 (2026):
#   - Proof of concept: Sound + external IntensityTier, two mono outputs.
# ============================================================

include internal/cdp_engine.praat

if numberOfSelected () <> 1 or numberOfSelected ("Sound") <> 1
    exitScript: "Select exactly one Sound."
endif
sourceID = selected ("Sound")
srcName$ = selected$ ("Sound")

form Intensity-Driven Temporal Walk v0.2
    comment Composition
    optionmenu Preset: 1
        option Custom
        option Gentle Temporal Drift
        option Balanced Walk
        option Fragmented Gesture
        option Wide Temporal Excursions
        option Extended Temporal Landscape
    positive Output_duration_factor 1.5
    comment Intensity Analysis
    positive Intensity_pitch_floor_Hz 100
    positive Intensity_time_step_s 0.01
    positive Minimum_clock_s 0.07
    positive Maximum_clock_s 0.30
    comment CDP Drunken Walk
    positive Constant_clock_s 0.15
    positive Ambitus_s 0.30
    positive Step_s 0.08
    positive Splice_ms 12
    natural Seed 42
    comment Output
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Fixed (as in the POC; not user controls)
locusMargin = 0.65
clokRand = 0
overlapFrac = 0
thinStep = 0.05
dbFloorRange = 60
processID$ = "drunk"

# ---------------------------------------------------------------------
# 1. PRESET (Custom = the form values)
# ---------------------------------------------------------------------
# Presets set only the walk's temporal parameters; the seed, splice and
# analysis settings always come from the form, and both channels always
# share everything except the clock.
presetName$ = "Custom"
if preset = 2
    presetName$ = "Gentle Temporal Drift"
    output_duration_factor = 1.25
    constant_clock_s = 0.22
    minimum_clock_s = 0.15
    maximum_clock_s = 0.35
    ambitus_s = 0.15
    step_s = 0.04
elsif preset = 3
    presetName$ = "Balanced Walk"
    output_duration_factor = 1.5
    constant_clock_s = 0.15
    minimum_clock_s = 0.07
    maximum_clock_s = 0.30
    ambitus_s = 0.30
    step_s = 0.08
elsif preset = 4
    presetName$ = "Fragmented Gesture"
    output_duration_factor = 1.5
    constant_clock_s = 0.10
    minimum_clock_s = 0.04
    maximum_clock_s = 0.18
    ambitus_s = 0.40
    step_s = 0.12
elsif preset = 5
    presetName$ = "Wide Temporal Excursions"
    output_duration_factor = 1.75
    constant_clock_s = 0.18
    minimum_clock_s = 0.06
    maximum_clock_s = 0.40
    ambitus_s = 0.75
    step_s = 0.20
elsif preset = 6
    presetName$ = "Extended Temporal Landscape"
    output_duration_factor = 2.5
    constant_clock_s = 0.25
    minimum_clock_s = 0.10
    maximum_clock_s = 0.50
    ambitus_s = 0.35
    step_s = 0.06
endif

# ---------------------------------------------------------------------
# 2. VALIDATION AND MONO WORKING COPY
# ---------------------------------------------------------------------
selectObject: sourceID
srcStart = Get start time
srcDur = Get total duration
srcChannels = Get number of channels
srcRate = Get sampling frequency
if srcDur < 2.5
    exitScript: "Please select a Sound of at least 2.5 seconds."
endif
if output_duration_factor < 1 or output_duration_factor > 4
    exitScript: "Output duration factor must be between 1 and 4."
endif
outDur = output_duration_factor * srcDur
if outDur > 180
    exitScript: "The output would last " + fixed$ (outDur, 1) + " s (limit 180 s): use a shorter Sound or a smaller factor."
endif
if splice_ms < 1 or splice_ms > 50
    exitScript: "Splice must be between 1 and 50 ms."
endif
# CDP: clock > 2 x splice, and at least 0.03 s; at most the source length.
clockFloor = max (0.03, 2 * splice_ms / 1000 + 0.001)
if minimum_clock_s < clockFloor or constant_clock_s < clockFloor
    exitScript: "Clock values must be at least " + fixed$ (clockFloor, 3) + " s (CDP: more than twice the splice of " + fixed$ (splice_ms, 0) + " ms, and at least 0.03 s)."
endif
if maximum_clock_s <= minimum_clock_s
    exitScript: "Maximum clock must be greater than Minimum clock."
endif
if maximum_clock_s > srcDur or constant_clock_s > srcDur
    exitScript: "Clock values must not exceed the Sound's duration (" + fixed$ (srcDur, 2) + " s)."
endif
if step_s <= 0.002
    exitScript: "Step must be greater than 0.002 s."
endif
if seed < 1
    exitScript: "Seed must be 1 or more: both channels need the same reproducible random sequence."
endif
if intensity_time_step_s > 0.05
    exitScript: "Intensity time step must be at most 0.05 s (the clock breakpoints are ~50 ms apart)."
endif
locusStart = locusMargin
locusEnd = srcDur - locusMargin
ambitusUsed = ambitus_s
ambitusNote$ = ""
if ambitusUsed > srcDur / 2
    ambitusUsed = srcDur / 2
    ambitusNote$ = " (clamped from " + fixed$ (ambitus_s, 2) + " s to half the Sound)"
endif

# Zero-based mono working copy: analysis and both CDP passes use it.
selectObject: sourceID
if srcChannels = 1
    monoID = Copy: srcName$ + "_ITW_mono"
else
    monoID = Convert to mono
    Rename: srcName$ + "_ITW_mono"
endif
Shift times to: "start time", 0
monoRMS = Get root-mean-square: 0, 0
if monoRMS = undefined or monoRMS <= 0
    removeObject: monoID
    exitScript: "The selected Sound is silent."
endif

# ---------------------------------------------------------------------
# 3. INTENSITY ANALYSIS -> INTENSITYTIER (internal)
# ---------------------------------------------------------------------
selectObject: monoID
intensityID = To Intensity: intensity_pitch_floor_Hz, intensity_time_step_s, "yes"
tierID = Down to IntensityTier
n = Get number of points
if n < 2
    removeObject: monoID, intensityID, tierID
    exitScript: "The Intensity analysis gave fewer than two points: the Sound is too short for this pitch floor."
endif
# tier times are zero-based (source-relative): tau = t
tStart = 0
tEnd = srcDur
hiRaw = -1e9
for i from 1 to n
    v = Get value at index: i
    if v <> undefined
        hiRaw = max (hiRaw, v)
    endif
endfor
if hiRaw = -1e9
    removeObject: monoID, intensityID, tierID
    exitScript: "The Intensity analysis returned no valid values."
endif
# Floor: digitally silent frames read -300 dB; any value more than
# dbFloorRange below the loudest point is treated as that floor.
dbFloor = hiRaw - dbFloorRange
nFloored = 0
for i from 1 to n
    v = Get value at index: i
    if v = undefined or v < dbFloor
        nFloored += 1
    endif
endfor

# Normalization range, as in the POC: the values at both ends plus every
# tier point inside the Sound (floored values count as the floor).
vStart = Get value at time: tStart
vEnd = Get value at time: tEnd
@floorDb: vStart
vStart = floorDb.v
@floorDb: vEnd
vEnd = floorDb.v
lo = min (vStart, vEnd)
hi = max (vStart, vEnd)
for i from 1 to n
    t = Get time from index: i
    if t >= tStart and t <= tEnd
        v = Get value at index: i
        @floorDb: v
        lo = min (lo, floorDb.v)
        hi = max (hi, floorDb.v)
    endif
endfor
flatRange = hi - lo < 0.01

# ---------------------------------------------------------------------
# 4. CDP ENGINE, PARAMETERS (registry) AND BREAKPOINT FILES
# ---------------------------------------------------------------------
@cdpx_init: defaultDirectory$
if cdpx_error$ <> ""
    removeObject: monoID, intensityID, tierID
    exitScript: "CDP initialization failed: " + cdpx_error$ + newline$ + "Place this script inside plugin_AudioTools/CDP/."
endif
@cdpx_findProcess: processID$
if cdpx_findProcess.row = 0
    removeObject: monoID, intensityID, tierID
    exitScript: "The CDP registry does not contain process '" + processID$ + "' (Drunken Walk)."
endif
# The breakpoint files replace arguments 6 (locus) and 9 (clock): check
# that the registry template still has them there.
@cdpx_tokenize: cdpx_t1_argument_template$ [cdpx_findProcess.row]
if cdpx_tokenize.n < 9
    templateOK = 0
else
    templateOK = cdpx_tok$ [6] = "{locus}" and cdpx_tok$ [9] = "{clock}"
endif
if not templateOK
    removeObject: monoID, intensityID, tierID
    exitScript: "The Drunken Walk argument template in CDP_Processes.tsv has changed (locus/clock positions); stopped safely."
endif

cdpx_pid$ = processID$
cdpx_sourceID = monoID
@cdpx_collectParams: cdpx_pid$
for k from 1 to cdpx_collectParams.n
    pRow = cdpx_paramRow [k]
    id$ = cdpx_t2_param_id$ [pRow]
    if id$ = "outdur"
        cdpx_value [k] = outDur
    elsif id$ = "locus"
        cdpx_value [k] = locusStart
    elsif id$ = "ambitus"
        cdpx_value [k] = ambitusUsed
    elsif id$ = "step"
        cdpx_value [k] = step_s
    elsif id$ = "clock"
        cdpx_value [k] = constant_clock_s
    elsif id$ = "splice"
        cdpx_value [k] = splice_ms
    elsif id$ = "clokrand"
        cdpx_value [k] = clokRand
    elsif id$ = "overlap"
        cdpx_value [k] = overlapFrac
    elsif id$ = "seed"
        cdpx_value [k] = seed
    else
        removeObject: monoID, intensityID, tierID
        exitScript: "Unexpected CDP Drunken Walk parameter: " + id$
    endif
    @cdpx_checkValue: pRow, cdpx_value [k]
    if cdpx_checkValue.msg$ <> ""
        removeObject: monoID, intensityID, tierID
        exitScript: "Drunken Walk parameter " + id$ + ": " + cdpx_checkValue.msg$
    endif
endfor

createFolder: cdpx_workDir$
# Remove breakpoint files left by an earlier run that Praat aborted
# (a runtime error cannot be caught by a script, so its cleanup never ran).
staleID = Create Strings as file list: "staleBrk", cdpx_workDir$ + cdpx_sep$ + "AT_walk_*.brk"
nStale = Get number of strings
for i to nStale
    selectObject: staleID
    stale$ = Get string: i
    deleteFile: cdpx_workDir$ + cdpx_sep$ + stale$
endfor
removeObject: staleID
tag$ =string$ (randomInteger (100000000, 999999999))
locusPath$ = cdpx_workDir$ + cdpx_sep$ + "AT_walk_locus_" + tag$ + ".brk"
clockPath$ = cdpx_workDir$ + cdpx_sep$ + "AT_walk_clock_" + tag$ + ".brk"

# Locus breakpoint time = OUTPUT seconds; value = INPUT (source) seconds.
writeFileLine: locusPath$, "0.000000 " + fixed$ (locusStart, 6)
appendFileLine: locusPath$, fixed$ (outDur, 6) + " " + fixed$ (locusEnd, 6)

# Clock breakpoint time ALSO = OUTPUT seconds: source-relative tau maps
# to tau x factor. About one point every 50 ms of source time (POC).
nBrk = 0
selectObject: tierID
@clockFor: vStart
@addBrk: 0, clockFor.c
writeFileLine: clockPath$, "0.000000 " + fixed$ (clockFor.c, 6)
lastWritten = tStart
for i from 1 to n
    selectObject: tierID
    t = Get time from index: i
    if t > tStart and t < tEnd and t - lastWritten >= thinStep
        v = Get value at index: i
        @clockFor: v
        appendFileLine: clockPath$, fixed$ ((t - tStart) * output_duration_factor, 6) + " " + fixed$ (clockFor.c, 6)
        @addBrk: (t - tStart) * output_duration_factor, clockFor.c
        lastWritten = t
    endif
endfor
@clockFor: vEnd
appendFileLine: clockPath$, fixed$ (outDur, 6) + " " + fixed$ (clockFor.c, 6)
@addBrk: outDur, clockFor.c

# Breakpoint sanity: strictly increasing times, finite clocks in range.
brkOK = 1
for b from 1 to nBrk
    if brkC [b] = undefined or brkC [b] < minimum_clock_s - 1e-9 or brkC [b] > maximum_clock_s + 1e-9
        brkOK = 0
    endif
    if b > 1
        if brkT [b] <= brkT [b - 1]
            brkOK = 0
        endif
    endif
endfor
if not brkOK
    deleteFile: locusPath$
    deleteFile: clockPath$
    removeObject: monoID, intensityID, tierID
    exitScript: "Internal error: the clock breakpoints are not valid (times must increase, clocks within range)."
endif

# ---------------------------------------------------------------------
# 5. THE TWO DRUNKEN WALKS (identical except the clock)
# ---------------------------------------------------------------------
constantID = 0
drivenID = 0
for pass from 1 to 2
    cdpx_error$ = ""
    cdpx_warning$ = ""
    cdpx_resultID = 0
    @cdpx_prepare
    if cdpx_error$ = ""
        @cdpx_writeTemp
    endif
    if cdpx_error$ = ""
        if cdpx_nArgs <> 13 or cdpx_arg$ [6] <> string$ (locusStart) or cdpx_arg$ [9] <> string$ (constant_clock_s)
            cdpx_error$ = "CDP Drunken Walk arguments are not in the expected form; stopped safely."
        else
            cdpx_arg$ [6] = locusPath$
            if pass = 2
                cdpx_arg$ [9] = clockPath$
            endif
            @cdpx_execute
            if cdpx_error$ = ""
                @cdpx_importResult
            endif
        endif
    endif
    if cdpx_error$ <> ""
        failure$ = cdpx_error$
        @cdpx_failureReport
        if cdpx_monoCopyID <> 0
            removeObject: cdpx_monoCopyID
            cdpx_monoCopyID = 0
        endif
        deleteFile: locusPath$
        deleteFile: clockPath$
        if constantID <> 0
            removeObject: constantID
        endif
        removeObject: monoID, intensityID, tierID
        selectObject: sourceID
        exitScript: "CDP Drunken Walk failed (" + if pass = 1 then "constant" else "intensity-driven" fi + " clock): " + failure$
    endif
    thisID = cdpx_resultID
    if pass = 1
        commandConstant$ = cdpx_commandLine$
    else
        commandDriven$ = cdpx_commandLine$
    endif
    @cdpx_cleanup
    if cdpx_monoCopyID <> 0
        removeObject: cdpx_monoCopyID
        cdpx_monoCopyID = 0
    endif
    if pass = 1
        constantID = thisID
    else
        drivenID = thisID
    endif
endfor
deleteFile: locusPath$
deleteFile: clockPath$

# ---------------------------------------------------------------------
# 6. STEREO: LEFT = constant, RIGHT = intensity-driven
# ---------------------------------------------------------------------
# Both start at 0 (output timeline). Neither branch is trimmed: the
# shorter one is padded with silence to the longer one's length, so the
# real temporal difference is kept. Samples are copied, not resampled.
selectObject: constantID
nC = Get number of samples
rC = Get sampling frequency
chC = Get number of channels
lenC = Get total duration
selectObject: drivenID
nD = Get number of samples
rD = Get sampling frequency
chD = Get number of channels
lenD = Get total duration
if rC <> rD or chC <> 1 or chD <> 1
    removeObject: constantID, drivenID, monoID, intensityID, tierID
    exitScript: "The two CDP results differ in sampling frequency or are not mono; stopped."
endif
nMax = max (nC, nD)
stereoID = Create Sound from formula: srcName$ + "_IntensityTemporalWalk_Stereo", 2, 0, nMax / rC, rC,
    ... "if row = 1 then (if col <= " + string$ (nC) + " then object [" + string$ (constantID) + ", col] else 0 fi)"
    ... + " else (if col <= " + string$ (nD) + " then object [" + string$ (drivenID) + ", col] else 0 fi) fi"
removeObject: constantID, drivenID
constantID = 0
drivenID = 0
selectObject: stereoID
outPeak = Get absolute extremum: 0, 0, "None"
attenDb = 0
if outPeak > 0.95
    Scale peak: 0.95
    attenDb = 20 * log10 (0.95 / outPeak)
endif
finalName$ = selected$ ("Sound")
finalLen = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ---------------------------------------------------------------------
# 7. REPORT
# ---------------------------------------------------------------------
writeInfoLine: "=== Intensity-Driven Temporal Walk v0.2 ===  (preset: ", presetName$, ")"
appendInfoLine: "Input: ", srcName$, "  (", fixed$ (srcDur, 3), " s, ", srcChannels, " ch, ", srcRate, " Hz", if srcChannels > 1 then ", folded to mono" else "" fi, ")"
appendInfoLine: "Intensity: To Intensity (", fixed$ (intensity_pitch_floor_Hz, 0), " Hz, ", fixed$ (intensity_time_step_s * 1000, 0), " ms) -> IntensityTier, ",
    ... n, " points; range ", fixed$ (lo, 2), " to ", fixed$ (hi, 2), " dB"
if nFloored > 0
    appendInfoLine: "   ", nFloored, " point(s) more than ", dbFloorRange, " dB below the loudest (", fixed$ (hiRaw, 1), " dB) were floored at ", fixed$ (dbFloor, 1), " dB."
endif
if flatRange
    appendInfoLine: "   The intensity is effectively flat: the driven clock uses the constant clock value."
endif
appendInfoLine: "Clock: LEFT constant ", fixed$ (constant_clock_s, 3), " s | RIGHT ", fixed$ (maximum_clock_s, 3), " s (quiet) to ",
    ... fixed$ (minimum_clock_s, 3), " s (loud), ", nBrk, " breakpoints"
appendInfoLine: "Drunken Walk (both): output ", fixed$ (outDur, 3), " s (x", fixed$ (output_duration_factor, 2), "), locus ", fixed$ (locusStart, 2),
    ... " -> ", fixed$ (locusEnd, 2), " s, ambitus ", fixed$ (ambitusUsed, 3), " s", ambitusNote$, ", step ", fixed$ (step_s, 3),
    ... " s, splice ", fixed$ (splice_ms, 0), " ms, seed ", seed
appendInfoLine: "Rendered lengths: constant ", fixed$ (lenC, 3), " s, intensity-driven ", fixed$ (lenD, 3), " s"
appendInfoLine: "Output: ", finalName$, "  (2 ch, ", fixed$ (finalLen, 3), " s, peak ", fixed$ (finalPeak, 3), ")"
if attenDb < 0
    appendInfoLine: "   Common attenuation ", fixed$ (attenDb, 2), " dB on both channels (mix peak ", fixed$ (outPeak, 3), ")."
endif

# ---------------------------------------------------------------------
# 8. VISUALIZATION (optional; reads the finished Sound only)
# ---------------------------------------------------------------------
if draw_visualization
    @drawWalk
endif

# ---------------------------------------------------------------------
# 9. CLEANUP, SELECTION, PLAYBACK
# ---------------------------------------------------------------------
removeObject: monoID, intensityID, tierID
selectObject: stereoID
if play_result
    Play
endif
selectObject: stereoID

# =====================================================================
# PROCEDURES
# =====================================================================

# dB value with the silence floor applied
procedure floorDb: .v
    if .v = undefined or .v < dbFloor
        .v = dbFloor
    endif
endproc

# Intensity (dB) -> clock (s): loud = short, quiet = long (the POC mapping)
procedure clockFor: .v
    @floorDb: .v
    if not flatRange
        .c = maximum_clock_s - (maximum_clock_s - minimum_clock_s) * (floorDb.v - lo) / (hi - lo)
    else
        .c = constant_clock_s
    endif
    .c = max (minimum_clock_s, min (maximum_clock_s, .c))
endproc

procedure addBrk: .t, .c
    nBrk += 1
    brkT [nBrk] = .t
    brkC [nBrk] = .c
endproc

procedure drawWalk
    .bgCol$ = "{0.97, 0.97, 0.99}"
    .gridCol$ = "{0.74, 0.74, 0.80}"
    .axisCol$ = "{0.20, 0.20, 0.28}"
    .dimCol$ = "{0.45, 0.45, 0.55}"
    .srcCol$ = "{0.62, 0.62, 0.66}"
    .intCol$ = "{0.80, 0.35, 0.20}"
    .lCol$ = "{0.20, 0.40, 0.80}"
    .rCol$ = "{0.80, 0.35, 0.20}"
    .bandCol$ = "{0.86, 0.89, 0.95}"
    .panelBg$ = "{0.94, 0.94, 0.94}"
    .vL = 0.60
    .vR = 7.70
    .railX = -0.065
    .pageHeight = 8.00

    @vizSafe: srcName$
    .name$ = vizSafe$
    @niceStep: srcDur, 8
    .stepS = niceStep
    @niceStep: finalLen, 10
    .stepO = niceStep
    selectObject: monoID
    .srcPeak = Get absolute extremum: 0, 0, "None"
    if .srcPeak < 0.001
        .srcPeak = 0.001
    endif

    Erase all
    Line width: 1
    Colour: "Black"
    Solid line

    # ---- Title -----------------------------------------------------------
    Font size: 12
    Select inner viewport: .vL, .vR, 0.12, 0.32
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Intensity-Driven Temporal Walk v0.2##"
    Font size: 7
    Select inner viewport: .vL, .vR, 0.34, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.5, "half", .name$ + "  |  " + presetName$ + "  |  CDP Drunken Walk  |  LEFT constant "
        ... + fixed$ (constant_clock_s * 1000, 0) + " ms, RIGHT " + fixed$ (minimum_clock_s * 1000, 0) + "-"
        ... + fixed$ (maximum_clock_s * 1000, 0) + " ms from Intensity"

    # ---- Panel A: source waveform and its Intensity (dB) ------------
    .aT = 0.80
    .aB = 1.95
    .dbTop = hi + 3
    .dbBot = lo - 3
    Font size: 6
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, srcDur, -.srcPeak * 1.1, .srcPeak * 1.1
    Paint rectangle: .bgCol$, 0, srcDur, -.srcPeak * 1.1, .srcPeak * 1.1
    selectObject: monoID
    Colour: .srcCol$
    Draw: 0, srcDur, -.srcPeak * 1.1, .srcPeak * 1.1, "no", "Curve"
    # the IntensityTier on its own dB axis (floored values drawn at the floor)
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, srcDur, .dbBot, .dbTop
    Colour: .intCol$
    Line width: 1.5
    selectObject: tierID
    .tPrev = undefined
    for .i from 1 to n
        .t = Get time from index: .i
        .v = Get value at index: .i
        @floorDb: .v
        if .tPrev <> undefined
            Draw line: .tPrev, .vPrev, .t, floorDb.v
        endif
        .tPrev = .t
        .vPrev = floorDb.v
    endfor
    Line width: 1
    Colour: .axisCol$
    Marks right every: 1, 10, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, srcDur, .dbBot, .dbTop
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepS, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Source"
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Source and Intensity## (source s) - grey: waveform (mono); orange: Intensity in dB (right axis), "
        ... + fixed$ (lo, 1) + " to " + fixed$ (hi, 1) + " dB, " + string$ (n) + " IntensityTier points"

    # ---- Panel B: the two clocks submitted to CDP (output time) ---------
    .bT = 2.30
    .bB = 3.55
    .cTop = max (maximum_clock_s, constant_clock_s) * 1000 * 1.12
    .cBot = min (minimum_clock_s, constant_clock_s) * 1000 * 0.80
    Font size: 6
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, outDur, .cBot, .cTop
    Paint rectangle: .bgCol$, 0, outDur, .cBot, .cTop
    Colour: .gridCol$
    Dotted line
    Draw line: 0, minimum_clock_s * 1000, outDur, minimum_clock_s * 1000
    Draw line: 0, maximum_clock_s * 1000, outDur, maximum_clock_s * 1000
    Solid line
    Colour: .lCol$
    Line width: 2
    Draw line: 0, constant_clock_s * 1000, outDur, constant_clock_s * 1000
    Colour: .rCol$
    Line width: 1.5
    for .b from 2 to nBrk
        Draw line: brkT [.b - 1], brkC [.b - 1] * 1000, brkT [.b], brkC [.b] * 1000
    endfor
    Line width: 1
    Colour: .lCol$
    Text: outDur, "right", constant_clock_s * 1000, "bottom", "LEFT constant " + fixed$ (constant_clock_s * 1000, 0) + " ms "
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, outDur, .cBot, .cTop
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepO, "yes", "yes", "no"
    One mark left: minimum_clock_s * 1000, "yes", "yes", "no", ""
    One mark left: maximum_clock_s * 1000, "yes", "yes", "no", ""
    if abs (constant_clock_s - minimum_clock_s) > 0.15 * (maximum_clock_s - minimum_clock_s) and abs (constant_clock_s - maximum_clock_s) > 0.15 * (maximum_clock_s - minimum_clock_s)
        One mark left: constant_clock_s * 1000, "yes", "yes", "no", ""
    endif
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Clock (ms)"
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Segment clock## (output s, ms) - blue: LEFT constant; orange: RIGHT, the " + string$ (nBrk)
        ... + " breakpoints sent to CDP (loud = short, quiet = long); dotted: min/max"

    # ---- Panel C: source navigation (shared locus) -----------------------
    .cT = 3.90
    .cB = 4.85
    Font size: 6
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, outDur, 0, srcDur
    Paint rectangle: .bgCol$, 0, outDur, 0, srcDur
    # ambitus band around the locus line (clipped to the source)
    .steps = 60
    for .q from 1 to .steps
        .ta = outDur * (.q - 1) / .steps
        .tb = outDur * .q / .steps
        .lm = locusStart + (locusEnd - locusStart) * (.ta + .tb) / 2 / outDur
        Paint rectangle: .bandCol$, .ta, .tb, max (0, .lm - ambitusUsed), min (srcDur, .lm + ambitusUsed)
    endfor
    Colour: .axisCol$
    Line width: 2
    Draw line: 0, locusStart, outDur, locusEnd
    Line width: 1
    Colour: .gridCol$
    Dotted line
    Draw line: 0, 0, srcDur, srcDur * 1
    Solid line
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, outDur, 0, srcDur
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepO, "yes", "yes", "no"
    Marks left every: 1, .stepS, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Source (s)"
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Source navigation## (output s vs source s) - line: locus " + fixed$ (locusStart, 2) + " -> " + fixed$ (locusEnd, 2)
        ... + " s, shared by BOTH channels; band: +/- ambitus " + fixed$ (ambitusUsed, 2) + " s; dotted: real time"

    # ---- Panel D: the stereo result ---------------------------------------
    .dT = 5.20
    .dB = 7.15
    .amp = finalPeak * 1.05
    if .amp <= 0
        .amp = 1
    endif
    .laneH = (.dB - .dT) / 2
    Font size: 6
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, finalLen, 0, 1
    Paint rectangle: .bgCol$, 0, finalLen, 0, 1
    for .c to 2
        .lt = .dT + (.c - 1) * .laneH
        Select inner viewport: .vL, .vR, .lt, .lt + .laneH
        Axes: 0, finalLen, -.amp, .amp * 1.45
        selectObject: stereoID
        .ex = Extract one channel: .c
        if .c = 1
            Colour: .lCol$
        else
            Colour: .rCol$
        endif
        Draw: 0, finalLen, -.amp, .amp * 1.45, "no", "Curve"
        removeObject: .ex
        Text: finalLen * 0.005, "left", .amp * 1.22, "half", if .c = 1 then "##LEFT - CONSTANT WALK##" else "##RIGHT - INTENSITY-DRIVEN WALK##" fi
        if .c = 2
            Colour: .gridCol$
            Draw line: 0, .amp * 1.45, finalLen, .amp * 1.45
        endif
    endfor
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, finalLen, 0, 1
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepO, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Output"
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Stereo output## (s) - the rendered Sound, both channels on one amplitude scale (+/-" + fixed$ (.amp, 2) + ")"

    # ---- Summary strip ----------------------------------------------------
    .sT = 7.40
    .sB = 7.92
    Font size: 6
    Select inner viewport: .vL, .vR, .sT, .sB
    Axes: 0, 1, 0, 1
    Paint rectangle: .panelBg$, 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.015, "left", 0.78, "half", "##Input##  " + .name$ + "  |  " + fixed$ (srcDur, 3) + " s, " + string$ (srcChannels)
        ... + " ch  |  Intensity " + fixed$ (lo, 1) + " to " + fixed$ (hi, 1) + " dB (" + fixed$ (intensity_pitch_floor_Hz, 0) + " Hz, "
        ... + fixed$ (intensity_time_step_s * 1000, 0) + " ms)  |  " + string$ (nBrk) + " clock breakpoints"
    Text: 0.015, "left", 0.50, "half", "##Walk##  " + presetName$ + "  |  CDP extend drunk (mode 1)  |  constant "
        ... + fixed$ (constant_clock_s * 1000, 0) + " ms vs " + fixed$ (minimum_clock_s * 1000, 0) + "-" + fixed$ (maximum_clock_s * 1000, 0)
        ... + " ms  |  ambitus " + fixed$ (ambitusUsed, 2) + " s, step " + fixed$ (step_s, 2) + " s, splice " + fixed$ (splice_ms, 0)
        ... + " ms, seed " + string$ (seed)
    Text: 0.015, "left", 0.22, "half", "##Output##  stereo (L constant, R intensity-driven)  |  requested " + fixed$ (outDur, 2)
        ... + " s, rendered " + fixed$ (finalLen, 2) + " s  |  final peak " + fixed$ (finalPeak, 3)
        ... + if attenDb < 0 then " (common " + fixed$ (attenDb, 1) + " dB)" else "" fi
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, .pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endproc

# Snap an axis step to 1 / 2 / 5 x 10^k.
procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .pw = 10 ^ floor (log10 (.raw))
    .nm = .raw / .pw
    if .nm < 1.5
        niceStep = 1 * .pw
    elsif .nm < 3.5
        niceStep = 2 * .pw
    elsif .nm < 7.5
        niceStep = 5 * .pw
    else
        niceStep = 10 * .pw
    endif
endproc

# Escape Picture-window markup in names (underscore pass last).
procedure vizSafe: .s$
    vizSafe$ = replace$ (.s$, "#", "\# ", 0)
    vizSafe$ = replace$ (vizSafe$, "%", "\% ", 0)
    vizSafe$ = replace$ (vizSafe$, "^", "\^ ", 0)
    vizSafe$ = replace$ (vizSafe$, "_", "\_ ", 0)
endproc
