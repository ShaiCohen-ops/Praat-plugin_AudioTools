# ============================================================
# Praat AudioTools - Spectral_Hysteresis.praat
# Title: Spectral Hysteresis
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
#   Spectral Hysteresis transforms a single Sound into a stereo
#   composition of constant and adaptive spectral memories using the
#   Composers Desktop Project's Super Accumulate (tempered) process.
#   Praat analyzes melodic stability, pitch changes, voiced restarts and
#   silence to generate a time-varying Decay control. The left channel
#   combines the original sound with constant spectral accumulation, the
#   right combines the same original with analysis-driven accumulation.
#   The result explores the relationship between melodic change, harmonic
#   persistence and spectral forgetting. ("Hysteresis" names the
#   compositional dependence of the resonance on accumulated spectral
#   history; this is not a physical hysteresis model and not a harmonic
#   analysis engine. The tempered pitch organization belongs to CDP's
#   process; Praat's F0 only steers the Decay parameter.)
#
# Input:
#   One Sound, 1 to 25 s. Pitch, Intensity and IntensityTier are made
#   internally from a zero-based mono working copy (a multichannel Sound
#   is averaged to mono; its stereo image is not kept). The original
#   Sound is not changed.
#
# Output:
#   One stereo Sound <name>_SpectralHysteresis_Stereo, starting at 0:
#     LEFT  = Original level x mono source + Processed level x CONSTANT
#     RIGHT = Original level x mono source + Processed level x ADAPTIVE
#   Its length is the longest of the source and the two CDP results; the
#   CDP spectral tails are kept whole, shorter signals end in silence.
#   Identical gains on both channels; one common attenuation only if the
#   stereo peak exceeds 0.95 (never amplified, no per-channel normalizing).
#
# Dependencies:
#   Praat 6.4 or newer; the CDP category of Praat AudioTools (this script
#   lives in plugin_AudioTools/CDP/: internal/cdp_engine.praat, the
#   registries, engine/windows). Process: sp_superaccu_2 (Super
#   Accumulate, tempered). No Python.
#
# Usage:
#   Select one Sound, run, choose a Preset or Custom (Custom at its
#   default values = the approved POC configuration). Deterministic: the
#   same Sound and settings always give the same result.
#
# Changelog v0.2 (2026):
#   - Automatic analysis of one Sound, preserved from the POC (Pitch,
#     Intensity, IntensityTier; stable / change / restart / silence logic
#     with reset frames; one Decay breakpoint every analysis step).
#   - Constant and adaptive CDP Super Accumulate passes as in the POC,
#     differing only in Decay (number vs breakpoint file).
#   - One stereo dry/wet output (L constant, R adaptive), unequal CDP tail
#     durations preserved, one common attenuation-only peak guard.
#   - Presets (Custom, Balanced Memory, Deep Resonance, Melodic Erasure,
#     Fragile Memory, Suspended Silence, Slow Recollection).
#   - Optional 8-inch visualization of the measured analysis, the Decay
#     control sent to CDP, the controller states and the stereo result.
#   - Compact form, parameter validation, registry-template checks, full
#     cleanup. A breakpoint line whose time would not increase (the
#     analysis frame at the end can repeat the Sound's end time) is not
#     written; the analysis itself is unchanged.
#
# Changelog v0.1 (2026):
#   - Proof of concept: two separate Sounds (constant / adaptive Decay).
# ============================================================

include internal/cdp_engine.praat

if numberOfSelected () <> 1 or numberOfSelected ("Sound") <> 1
    exitScript: "Select exactly one Sound."
endif
sourceID = selected ("Sound")
sourceName$ = selected$ ("Sound")

form Spectral Hysteresis v0.2
    comment Composition
    optionmenu Preset: 1
        option Custom
        option Balanced Memory
        option Deep Resonance
        option Melodic Erasure
        option Fragile Memory
        option Suspended Silence
        option Slow Recollection
    comment Pitch & Stability Analysis
    positive Pitch_floor_Hz 140
    positive Pitch_ceiling_Hz 1500
    positive Analysis_step_s 0.05
    positive Stable_threshold_st 0.30
    positive Jump_threshold_st 1.5
    positive Silence_below_peak_dB 25
    natural Reset_frames 4
    comment Spectral Memory (CDP Decay)
    positive Constant_decay 0.40
    positive Stable_decay 0.65
    positive Change_decay 0.12
    positive Silence_decay 0.60
    comment Mix & Output
    real Original_level 0.70
    positive Processed_level 0.60
    boolean Draw_visualization 1
    boolean Play_result 1
endform

processID$ = "sp_superaccu_2"
peakLimit = 0.95

# ---------------------------------------------------------------------
# 1. PRESET (Custom = the form values; presets set only the adaptive
#    memory logic: three Decays, jump threshold, reset frames)
# ---------------------------------------------------------------------
presetName$ = "Custom"
if preset = 2
    presetName$ = "Balanced Memory"
    @setPreset: 0.65, 0.12, 0.60, 1.5, 4
elsif preset = 3
    presetName$ = "Deep Resonance"
    @setPreset: 0.82, 0.18, 0.78, 1.5, 3
elsif preset = 4
    presetName$ = "Melodic Erasure"
    @setPreset: 0.75, 0.03, 0.68, 1.2, 6
elsif preset = 5
    presetName$ = "Fragile Memory"
    @setPreset: 0.43, 0.06, 0.38, 1.3, 5
elsif preset = 6
    presetName$ = "Suspended Silence"
    @setPreset: 0.72, 0.09, 0.87, 1.5, 4
elsif preset = 7
    presetName$ = "Slow Recollection"
    @setPreset: 0.80, 0.22, 0.70, 1.8, 2
endif

# Short internal names (as in the POC)
pitchFloor = pitch_floor_Hz
pitchCeiling = pitch_ceiling_Hz
analysisStep = analysis_step_s
jumpThreshold = jump_threshold_st
stableThreshold = stable_threshold_st
silenceBelowPeakDb = silence_below_peak_dB
constantDecay = constant_decay
forgetDecay = change_decay
stableDecay = stable_decay
silenceDecay = silence_decay
resetFrames = reset_frames
gDry = original_level
gWet = processed_level

# ---------------------------------------------------------------------
# 2. VALIDATION
# ---------------------------------------------------------------------
selectObject: sourceID
srcDur = Get total duration
srcChans = Get number of channels
srcRate = Get sampling frequency
if srcDur < 1 or srcDur > 25
    exitScript: "Please select a Sound between 1 and 25 seconds."
endif
if pitchCeiling <= pitchFloor
    exitScript: "Pitch ceiling must be greater than Pitch floor."
endif
if pitchFloor < 30
    exitScript: "Pitch floor must be at least 30 Hz."
endif
if analysisStep < 0.01 or analysisStep > 0.2
    exitScript: "Analysis step must be between 0.01 and 0.2 s."
endif
if stableThreshold >= jumpThreshold
    exitScript: "Stable threshold must be below the Jump threshold."
endif
if resetFrames < 1
    exitScript: "Reset frames must be at least 1."
endif
if silenceBelowPeakDb > 100
    exitScript: "Silence threshold must be at most 100 dB below the peak."
endif
@checkDecay: "Constant", constantDecay
@checkDecay: "Stable", stableDecay
@checkDecay: "Change", forgetDecay
@checkDecay: "Silence", silenceDecay
if gDry < 0 or gDry > 1 or gWet > 1
    exitScript: "Original and Processed levels must be between 0 and 1 (Processed above 0)."
endif

# ---------------------------------------------------------------------
# 3. ONE ZERO-BASED MONO ANALYSIS AND CDP SOURCE (as in the POC)
# ---------------------------------------------------------------------
selectObject: sourceID
if srcChans = 1
    monoID = Copy: sourceName$ + "_SH_work"
else
    monoID = Convert to mono
    Rename: sourceName$ + "_SH_work"
endif
Shift times to: "start time", 0
workRMS = Get root-mean-square: 0, 0
if workRMS = undefined or workRMS <= 0
    removeObject: monoID
    selectObject: sourceID
    exitScript: "The input is silent or invalid."
endif

selectObject: monoID
pitchID = To Pitch: 0.01, pitchFloor, pitchCeiling
selectObject: monoID
intensityID = To Intensity: pitchFloor, 0.01, "yes"
selectObject: intensityID
tierID = Down to IntensityTier
nIntensity = Get number of points
if nIntensity < 2
    removeObject: pitchID, intensityID, tierID, monoID
    selectObject: sourceID
    exitScript: "Intensity analysis returned too few points."
endif
peakDb = -1e9
for i from 1 to nIntensity
    selectObject: tierID
    v = Get value at index: i
    if v <> undefined
        peakDb = max (peakDb, v)
    endif
endfor
if peakDb < -500
    removeObject: pitchID, intensityID, tierID, monoID
    selectObject: sourceID
    exitScript: "Intensity analysis is invalid."
endif

# ---------------------------------------------------------------------
# 4. CDP ENGINE, REGISTRY CHECKS, PARAMETERS
# ---------------------------------------------------------------------
@cdpx_init: defaultDirectory$
if cdpx_error$ <> ""
    err$ = cdpx_error$
    removeObject: pitchID, intensityID, tierID, monoID
    selectObject: sourceID
    exitScript: "CDP initialization failed: " + err$ + newline$ + "Place this script inside plugin_AudioTools/CDP/."
endif
@cdpx_findProcess: processID$
templateOK = 0
if cdpx_findProcess.row > 0
    pRowP = cdpx_findProcess.row
    @cdpx_tokenize: cdpx_t1_argument_template$ [pRowP]
    if cdpx_tokenize.n = 7
        if cdpx_t1_subcommand$ [pRowP] = "superaccu" and cdpx_t1_mode$ [pRowP] = "2"
            if cdpx_tok$ [5] = "-d{decay}" and cdpx_tok$ [6] = "-g{glis}" and cdpx_tok$ [7] = "{reassign}"
                templateOK = 1
            endif
        endif
    endif
endif
if not templateOK
    removeObject: pitchID, intensityID, tierID, monoID
    selectObject: sourceID
    exitScript: "The Super Accumulate (tempered) entry in CDP_Processes.tsv is missing or its argument template has changed; stopped safely."
endif

cdpx_pid$ = processID$
cdpx_sourceID = monoID
@cdpx_collectParams: cdpx_pid$
if cdpx_collectParams.n <> 3
    removeObject: pitchID, intensityID, tierID, monoID
    selectObject: sourceID
    exitScript: "Unexpected Super Accumulate parameter registry."
endif
for k from 1 to cdpx_collectParams.n
    pRow = cdpx_paramRow [k]
    id$ = cdpx_t2_param_id$ [pRow]
    if id$ = "decay"
        cdpx_value [k] = constantDecay
    elsif id$ = "glis"
        cdpx_value [k] = 0
    elsif id$ = "reassign"
        cdpx_value [k] = 0
    else
        removeObject: pitchID, intensityID, tierID, monoID
        selectObject: sourceID
        exitScript: "Unknown Super Accumulate parameter: " + id$
    endif
    @cdpx_checkValue: pRow, cdpx_value [k]
    if cdpx_checkValue.msg$ <> ""
        removeObject: pitchID, intensityID, tierID, monoID
        selectObject: sourceID
        exitScript: "Super Accumulate " + id$ + ": " + cdpx_checkValue.msg$
    endif
endfor

createFolder: cdpx_workDir$
unique$ = string$ (randomInteger (100000000, 999999999))
brkPath$ = cdpx_workDir$ + cdpx_sep$ + "AT_spectral_hysteresis_" + unique$ + ".brk"

# ---------------------------------------------------------------------
# 5. ADAPTIVE DECAY BREAKPOINTS (the POC algorithm, unchanged)
# ---------------------------------------------------------------------
# Every breakpoint time is relative to the audio start (0 s); one control
# point per analysis step. The frame values are kept in arrays for the
# report and the visualization (state codes: 0 silence/unvoiced,
# 1 voiced restart, 2 melodic change - both for all their reset frames -,
# 3 transitional, 4 stable).
prevPitch = 0
resetLeft = 0
countReset = 0
countValid = 0
nRestart = 0
nChange = 0
resetKind = 0
nSteps = ceiling (srcDur / analysisStep)
nFr = 0
nBrk = 0
lastBrkT$ = ""
for i from 0 to nSteps
    t = min (srcDur, i * analysisStep)
    selectObject: pitchID
    f = Get value at time: t, "Hertz", "linear"
    selectObject: tierID
    db = Get value at time: t

    voiced = 1
    if f = undefined
        voiced = 0
    elsif f < pitchFloor or f > pitchCeiling
        voiced = 0
    endif
    if db = undefined
        voiced = 0
    elsif db < peakDb - silenceBelowPeakDb
        voiced = 0
    endif

    onset = 0
    if voiced = 0
        # Silence has no meaningful F0: keep the prior resonances rather
        # than reading unvoiced frames as jumps.
        d = silenceDecay
        prevPitch = 0
        resetLeft = 0
        state = 0
    else
        countValid += 1
        if prevPitch = 0
            resetLeft = resetFrames
            countReset += 1
            nRestart += 1
            resetKind = 1
            onset = 1
        else
            jump = abs (12 * ln (f / prevPitch) / ln (2))
            if jump >= jumpThreshold
                resetLeft = resetFrames
                countReset += 1
                nChange += 1
                resetKind = 2
                onset = 2
            endif
        endif

        if resetLeft > 0
            d = forgetDecay
            resetLeft -= 1
            state = resetKind
        else
            jump = abs (12 * ln (f / prevPitch) / ln (2))
            # stable threshold or less -> stable memory;
            # jump threshold or more -> quick forgetting.
            stability = 1 - (jump - stableThreshold) / (jumpThreshold - stableThreshold)
            stability = max (0, min (1, stability))
            d = forgetDecay + (stableDecay - forgetDecay) * stability
            state = if stability >= 1 then 4 else 3 fi
        endif
        prevPitch = f
    endif
    d = max (0.00001, min (0.9, d))

    nFr += 1
    frT [nFr] = t
    frF [nFr] = if voiced then f else undefined fi
    frD [nFr] = d
    frState [nFr] = state
    frOnset [nFr] = onset

    # one breakpoint line per frame; a time that does not increase is
    # skipped (only possible for the final frame at the Sound's end)
    tLine$ = fixed$ (t, 6)
    if i = 0
        writeFileLine: brkPath$, "0.000000 " + fixed$ (d, 6)
        nBrk += 1
        brkT [nBrk] = 0
        brkD [nBrk] = d
        lastBrkT$ = "0.000000"
    elsif number (tLine$) > number (lastBrkT$)
        appendFileLine: brkPath$, tLine$ + " " + fixed$ (d, 6)
        nBrk += 1
        brkT [nBrk] = number (tLine$)
        brkD [nBrk] = number (fixed$ (d, 6))
        lastBrkT$ = tLine$
    endif
endfor
voicedPct = 100 * countValid / nFr

# Breakpoint sanity: strictly increasing times, Decay within CDP's range.
brkOK = 1
for b from 1 to nBrk
    if brkD [b] = undefined or brkD [b] < 0.00001 or brkD [b] > 0.9
        brkOK = 0
    endif
    if b > 1
        if brkT [b] <= brkT [b - 1]
            brkOK = 0
        endif
    endif
endfor
if not brkOK
    deleteFile: brkPath$
    removeObject: pitchID, intensityID, tierID, monoID
    selectObject: sourceID
    exitScript: "Internal error: the Decay breakpoints are not valid."
endif

# The Pitch contour is kept for the picture only; the rest goes now.
removeObject: intensityID, tierID

# ---------------------------------------------------------------------
# 6. A. CONSTANT REFERENCE - ordinary CDP engine call (POC)
# ---------------------------------------------------------------------
@cdpx_process
if cdpx_error$ <> ""
    err$ = cdpx_error$
    deleteFile: brkPath$
    removeObject: pitchID, monoID
    selectObject: sourceID
    exitScript: "Constant Super Accumulate failed: " + err$
endif
constantID = cdpx_resultID
commandConstant$ = cdpx_commandLine$

# ---------------------------------------------------------------------
# 7. B. ADAPTIVE - only the -d argument becomes the breakpoint file (POC)
# ---------------------------------------------------------------------
# Expected command (Reassign gliss off -> no -r):
#   superaccu 2 {input.ana} {output.ana} -d{decay} -g{glis}
cdpx_error$ = ""
cdpx_warning$ = ""
cdpx_resultID = 0
@cdpx_prepare
if cdpx_error$ = ""
    @cdpx_writeTemp
endif
if cdpx_error$ = ""
    if cdpx_nArgs <> 6 or cdpx_arg$ [1] <> "superaccu" or cdpx_arg$ [2] <> "2" or cdpx_arg$ [5] <> "-d" + string$ (constantDecay) or cdpx_arg$ [6] <> "-g0"
        cdpx_error$ = "CDP Super Accumulate command differs from the expected form; the breakpoint file was not substituted."
    else
        cdpx_arg$ [5] = "-d" + brkPath$
        @cdpx_execute
        if cdpx_error$ = ""
            @cdpx_importResult
        endif
    endif
endif
if cdpx_error$ <> ""
    err$ = cdpx_error$
    @cdpx_failureReport
    if cdpx_monoCopyID <> 0
        removeObject: cdpx_monoCopyID
        cdpx_monoCopyID = 0
    endif
    removeObject: pitchID, monoID, constantID
    selectObject: sourceID
    exitScript: "Adaptive Super Accumulate failed: " + err$ + newline$
        ... + "No output was made (the adaptive channel is never replaced by a constant one)." + newline$
        ... + "Breakpoint file kept for diagnosis: " + brkPath$
endif
adaptiveID = cdpx_resultID
commandAdaptive$ = cdpx_commandLine$
@cdpx_cleanup
if cdpx_monoCopyID <> 0
    removeObject: cdpx_monoCopyID
    cdpx_monoCopyID = 0
endif
deleteFile: brkPath$

# ---------------------------------------------------------------------
# 8. STEREO DRY/WET: L = gDry X + gWet C, R = gDry X + gWet A
# ---------------------------------------------------------------------
# All three start at 0 and are copied sample by sample (no resampling);
# the result lasts as long as the longest, the others end in silence.
selectObject: monoID
nX = Get number of samples
selectObject: constantID
nC = Get number of samples
rC = Get sampling frequency
chC = Get number of channels
lenC = Get total duration
selectObject: adaptiveID
nA = Get number of samples
rA = Get sampling frequency
chA = Get number of channels
lenA = Get total duration
if rC <> srcRate or rA <> srcRate or chC <> 1 or chA <> 1
    removeObject: pitchID, monoID, constantID, adaptiveID
    selectObject: sourceID
    exitScript: "The CDP results are not mono at the source's sampling frequency; stopped."
endif
nOut = max (nX, max (nC, nA))
dryTerm$ = "(if col <= " + string$ (nX) + " then object [" + string$ (monoID) + ", col] else 0 fi)"
stereoID = Create Sound from formula: sourceName$ + "_SpectralHysteresis_Stereo", 2, 0, nOut / srcRate, srcRate,
    ... string$ (gDry) + " * " + dryTerm$ + " + " + string$ (gWet) + " * (if row = 1 then"
    ... + " (if col <= " + string$ (nC) + " then object [" + string$ (constantID) + ", col] else 0 fi)"
    ... + " else (if col <= " + string$ (nA) + " then object [" + string$ (adaptiveID) + ", col] else 0 fi) fi)"
removeObject: constantID, adaptiveID
selectObject: stereoID
mixPeak = Get absolute extremum: 0, 0, "None"
attenDb = 0
if mixPeak > peakLimit
    Multiply: peakLimit / mixPeak
    attenDb = 20 * log10 (peakLimit / mixPeak)
endif
finalName$ = selected$ ("Sound")
finalLen = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ---------------------------------------------------------------------
# 9. REPORT
# ---------------------------------------------------------------------
writeInfoLine: "=== Spectral Hysteresis v0.2 ===  (preset: ", presetName$, ")"
appendInfoLine: "Input: ", sourceName$, "  (", fixed$ (srcDur, 3), " s, ", srcChans, " ch, ", srcRate, " Hz",
    ... if srcChans > 1 then ", averaged to mono; stereo image not kept" else "" fi, ")"
appendInfoLine: "Analysis: pitch ", pitchFloor, "-", pitchCeiling, " Hz, step ", fixed$ (analysisStep, 3), " s, stable <= ",
    ... fixed$ (stableThreshold, 2), " st, jump >= ", fixed$ (jumpThreshold, 2), " st, silence < peak - ", silenceBelowPeakDb, " dB, reset ", resetFrames, " frames"
appendInfoLine: "   ", nFr, " frames, ", countValid, " voiced (", fixed$ (voicedPct, 1), " %); ", nChange, " melodic change(s), ", nRestart, " voiced restart(s)"
if countValid = 0
    appendInfoLine: "   No voiced frames: the adaptive Decay is the Silence Decay throughout."
endif
appendInfoLine: "CDP Super Accumulate (tempered), glissando 0, reassign off"
appendInfoLine: "   LEFT  constant Decay ", fixed$ (constantDecay, 3), "  -> ", fixed$ (lenC, 3), " s"
appendInfoLine: "   RIGHT adaptive Decay (stable ", fixed$ (stableDecay, 2), ", change ", fixed$ (forgetDecay, 2), ", silence ",
    ... fixed$ (silenceDecay, 2), "), ", nBrk, " breakpoints  -> ", fixed$ (lenA, 3), " s"
appendInfoLine: "Mix: original ", fixed$ (gDry, 2), " + processed ", fixed$ (gWet, 2), " on both channels"
appendInfoLine: "Output: ", finalName$, "  (2 ch, ", fixed$ (finalLen, 3), " s, peak ", fixed$ (finalPeak, 3), ")"
if attenDb < 0
    appendInfoLine: "   Common attenuation ", fixed$ (attenDb, 2), " dB on both channels (mix peak ", fixed$ (mixPeak, 3), ")."
endif

# ---------------------------------------------------------------------
# 10. VISUALIZATION (optional; reads stored data and the final Sound)
# ---------------------------------------------------------------------
if draw_visualization
    @drawHysteresis
endif

# ---------------------------------------------------------------------
# 11. CLEANUP, SELECTION, PLAYBACK
# ---------------------------------------------------------------------
removeObject: pitchID, monoID
selectObject: stereoID
if play_result
    Play
endif
selectObject: stereoID

# =====================================================================
# PROCEDURES
# =====================================================================

procedure setPreset: .stable, .change, .silence, .jump, .reset
    stable_decay = .stable
    change_decay = .change
    silence_decay = .silence
    jump_threshold_st = .jump
    reset_frames = .reset
endproc

procedure checkDecay: .label$, .value
    if .value < 0.00001 or .value > 0.9
        exitScript: .label$ + " Decay must lie between 0.00001 and 0.9 (CDP Super Accumulate)."
    endif
endproc

procedure drawHysteresis
    .bgCol$ = "{0.97, 0.97, 0.99}"
    .gridCol$ = "{0.74, 0.74, 0.80}"
    .axisCol$ = "{0.20, 0.20, 0.28}"
    .dimCol$ = "{0.45, 0.45, 0.55}"
    .srcCol$ = "{0.62, 0.62, 0.66}"
    .f0Col$ = "{0.15, 0.15, 0.25}"
    .lCol$ = "{0.20, 0.40, 0.80}"
    .rCol$ = "{0.80, 0.35, 0.20}"
    .silCol$ = "{0.88, 0.88, 0.90}"
    .panelBg$ = "{0.94, 0.94, 0.94}"
    # state colours: silence, restart, change, transitional, stable
    .stCol$ [0] = "{0.86, 0.86, 0.88}"
    .stCol$ [1] = "{0.55, 0.35, 0.70}"
    .stCol$ [2] = "{0.85, 0.45, 0.20}"
    .stCol$ [3] = "{0.70, 0.82, 0.70}"
    .stCol$ [4] = "{0.25, 0.60, 0.40}"
    .vL = 0.60
    .vR = 7.70
    .railX = -0.065
    .pageHeight = 8.00

    @vizSafe: sourceName$
    .name$ = vizSafe$
    @niceStep: srcDur, 10
    .stepS = niceStep
    @niceStep: finalLen, 10
    .stepO = niceStep
    selectObject: monoID
    .srcPeak = Get absolute extremum: 0, 0, "None"
    if .srcPeak < 1e-6
        .srcPeak = 1e-6
    endif
    # half-step frame edges: frame k covers [t_k - step/2, t_k + step/2]
    .hs = analysisStep / 2

    Erase all
    Line width: 1
    Colour: "Black"
    Solid line

    # ---- Title -----------------------------------------------------------
    Font size: 12
    Select inner viewport: .vL, .vR, 0.12, 0.32
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Spectral Hysteresis v0.2##"
    Font size: 7
    Select inner viewport: .vL, .vR, 0.34, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.5, "half", .name$ + "  |  " + presetName$ + "  |  CDP Super Accumulate (tempered)  |  LEFT constant Decay "
        ... + fixed$ (constantDecay, 2) + ", RIGHT Decay from melodic analysis"

    # ---- Panel A: waveform + F0 (two aligned strips) ---------------------
    .aT = 0.80
    .aM = 1.45
    .aB = 2.30
    Font size: 6
    # silence / unvoiced frames shaded across both strips
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, srcDur, 0, 1
    Paint rectangle: .bgCol$, 0, srcDur, 0, 1
    for .k to nFr
        if frState [.k] = 0
            Paint rectangle: .silCol$, max (0, frT [.k] - .hs), min (srcDur, frT [.k] + .hs), 0, 1
        endif
    endfor
    # waveform strip
    Select inner viewport: .vL, .vR, .aT, .aM
    Axes: 0, srcDur, -.srcPeak * 1.1, .srcPeak * 1.1
    selectObject: monoID
    Colour: .srcCol$
    Draw: 0, srcDur, -.srcPeak * 1.1, .srcPeak * 1.1, "no", "Curve"
    # F0 strip (10 ms Pitch frames, log-frequency axis)
    .fLo = pitchCeiling
    .fHi = pitchFloor
    for .k to nFr
        if frF [.k] <> undefined
            .fLo = min (.fLo, frF [.k])
            .fHi = max (.fHi, frF [.k])
        endif
    endfor
    if countValid = 0
        .fLo = pitchFloor
        .fHi = pitchCeiling
    endif
    .yLo = log2 (.fLo) - 0.25
    .yHi = log2 (.fHi) + 0.25
    if .yHi - .yLo < 1
        .yMid = (.yHi + .yLo) / 2
        .yLo = .yMid - 0.5
        .yHi = .yMid + 0.5
    endif
    Select inner viewport: .vL, .vR, .aM, .aB
    Axes: 0, srcDur, .yLo, .yHi
    Colour: .gridCol$
    Draw line: 0, .yHi, srcDur, .yHi
    selectObject: pitchID
    .nPf = Get number of frames
    .pPrevT = undefined
    .pPrevY = undefined
    Colour: .f0Col$
    Line width: 1.5
    for .j to .nPf
        selectObject: pitchID
        .pt = Get time from frame number: .j
        .pf = Get value in frame: .j, "Hertz"
        if .pf <> undefined
            .py = log2 (.pf)
            if .pPrevT <> undefined
                if .pt - .pPrevT < 0.015 and .py >= .yLo and .py <= .yHi and .pPrevY >= .yLo and .pPrevY <= .yHi
                    Draw line: .pPrevT, .pPrevY, .pt, .py
                endif
            endif
            .pPrevT = .pt
            .pPrevY = .py
        else
            .pPrevT = undefined
        endif
    endfor
    Line width: 1
    # events: melodic changes (orange) and voiced restarts (purple)
    for .k to nFr
        if frOnset [.k] > 0
            Colour: .stCol$ [frOnset [.k]]
            Line width: 1.5
            Draw line: frT [.k], .yLo, frT [.k], .yHi
            Line width: 1
            if frF [.k] <> undefined
                Paint circle (mm): .stCol$ [frOnset [.k]], frT [.k], log2 (frF [.k]), 1.0
            endif
        endif
    endfor
    Colour: .axisCol$
    @f0Mark: 0.5
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, srcDur, 0, 1
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepS, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Source / F0 (Hz)"
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Source and melodic analysis## (s) - waveform (mono); F0, log scale; purple: voiced restart ("
        ... + string$ (nRestart) + "), orange: melodic change (" + string$ (nChange) + "); grey: silence / unvoiced"

    # ---- Panel B: Decay control (central) --------------------------------
    .bT = 2.65
    .bB = 4.05
    .dTop = 1.0
    .dBot = 0
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, srcDur, .dBot, .dTop
    Paint rectangle: .bgCol$, 0, srcDur, .dBot, .dTop
    Colour: .gridCol$
    Dotted line
    for .q to 4
        Draw line: 0, .q * 0.2, srcDur, .q * 0.2
    endfor
    Draw line: 0, 0.9, srcDur, 0.9
    Solid line
    Colour: .lCol$
    Line width: 2
    Draw line: 0, constantDecay, srcDur, constantDecay
    Colour: .rCol$
    Line width: 1.5
    for .b from 2 to nBrk
        Draw line: brkT [.b - 1], brkD [.b - 1], brkT [.b], brkD [.b]
    endfor
    Line width: 1
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, srcDur, .dBot, .dTop
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.2, "yes", "yes", "no"
    Colour: .dimCol$
    Text: srcDur, "right", 0.9, "bottom", "CDP maximum 0.9 "
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Decay"
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Spectral memory control## (s) - blue: LEFT constant Decay " + fixed$ (constantDecay, 2)
        ... + "; orange: RIGHT, the " + string$ (nBrk) + " breakpoints sent to CDP (a control parameter, not accumulated energy)"

    # ---- Panel C: controller states (aligned under B) --------------------
    .cT = 4.10
    .cB = 4.42
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, srcDur, 0, 1
    for .k to nFr
        Paint rectangle: .stCol$ [frState [.k]], max (0, frT [.k] - .hs), min (srcDur, frT [.k] + .hs), 0, 1
    endfor
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepS, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "State"
    # legend under the axis numbers
    Select inner viewport: .vL, .vR, .cB + 0.20, .cB + 0.34
    Axes: 0, 1, 0, 1
    .lx = 0
    @legendItem: .stCol$ [4], "stable (Decay " + fixed$ (stableDecay, 2) + ")", 0.00
    @legendItem: .stCol$ [3], "transitional (interpolated)", 0.19
    @legendItem: .stCol$ [2], "melodic change (" + fixed$ (forgetDecay, 2) + ", " + string$ (resetFrames) + " frames)", 0.39
    @legendItem: .stCol$ [1], "voiced restart (" + fixed$ (forgetDecay, 2) + ")", 0.63
    @legendItem: .stCol$ [0], "silence / unvoiced (" + fixed$ (silenceDecay, 2) + ")", 0.81

    # ---- Panel D: stereo output -------------------------------------------
    .dT = 5.05
    .dB = 7.10
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
        Colour: if .c = 1 then .lCol$ else .rCol$ fi
        Draw: 0, finalLen, -.amp, .amp * 1.45, "no", "Curve"
        removeObject: .ex
        Text: finalLen * 0.005, "left", .amp * 1.22, "half", if .c = 1 then "##LEFT - ORIGINAL + CONSTANT MEMORY##" else "##RIGHT - ORIGINAL + ADAPTIVE MEMORY##" fi
        # where this channel's CDP result ends
        .cEnd = if .c = 1 then lenC else lenA fi
        Colour: .axisCol$
        Draw line: .cEnd, -.amp, .cEnd, .amp * 1.05
        @boxText: .cEnd, if .cEnd < 0.7 * finalLen then "left" else "right" fi, -.amp * 0.9, " CDP result ends " + fixed$ (.cEnd, 2) + " s "
        if .c = 2
            Colour: .gridCol$
            Draw line: 0, .amp * 1.45, finalLen, .amp * 1.45
        endif
    endfor
    # end of the original phrase
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, finalLen, 0, 1
    Colour: .axisCol$
    Dashed line
    Draw line: srcDur, 0, srcDur, 1
    Solid line
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
    Text top: "no", "##Stereo output## (s) - with the CDP tails, one amplitude scale (+/-" + fixed$ (.amp, 2) + "); dashed: the original ends (" + fixed$ (srcDur, 2) + " s); ticks: each CDP result ends"

    # ---- Summary strip ----------------------------------------------------
    .sT = 7.40
    .sB = 7.92
    Font size: 6
    Select inner viewport: .vL, .vR, .sT, .sB
    Axes: 0, 1, 0, 1
    Paint rectangle: .panelBg$, 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.015, "left", 0.78, "half", "##Input##  " + .name$ + "  |  " + fixed$ (srcDur, 3) + " s, " + string$ (srcChans)
        ... + " ch  |  " + string$ (countValid) + " of " + string$ (nFr) + " frames voiced  |  " + string$ (nChange) + " melodic changes, "
        ... + string$ (nRestart) + " voiced restarts  |  pitch " + string$ (pitchFloor) + "-" + string$ (pitchCeiling) + " Hz"
    Text: 0.015, "left", 0.50, "half", "##Memory##  " + presetName$ + "  |  constant " + fixed$ (constantDecay, 2)
        ... + "  |  stable " + fixed$ (stableDecay, 2) + ", change " + fixed$ (forgetDecay, 2) + ", silence " + fixed$ (silenceDecay, 2)
        ... + "  |  jump " + fixed$ (jumpThreshold, 2) + " st, reset " + string$ (resetFrames) + "  |  " + string$ (nBrk) + " breakpoints"
    Text: 0.015, "left", 0.22, "half", "##Output##  original " + fixed$ (gDry, 2) + " + processed " + fixed$ (gWet, 2)
        ... + "  |  " + fixed$ (finalLen, 2) + " s (CDP L " + fixed$ (lenC, 2) + " s, R " + fixed$ (lenA, 2) + " s)  |  final peak "
        ... + fixed$ (finalPeak, 3) + if attenDb < 0 then " (common " + fixed$ (attenDb, 1) + " dB)" else "" fi
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, .pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endproc

# F0 axis marks at musically readable frequencies inside the strip
procedure f0Mark: .dummy
    .cand# = {50, 100, 150, 200, 300, 400, 500, 600, 800, 1000, 1200, 1500, 2000}
    .last = -100
    for .q to size (.cand#)
        .yy = log2 (.cand# [.q])
        if .yy > drawHysteresis.yLo + 0.05 and .yy < drawHysteresis.yHi - 0.05 and .yy - .last > 0.30
            One mark left: .yy, "no", "yes", "no", string$ (.cand# [.q])
            .last = .yy
        endif
    endfor
endproc

procedure legendItem: .col$, .label$, .x0
    Paint rectangle: .col$, .x0, .x0 + 0.012, 0.15, 0.85
    Colour: "{0.30, 0.30, 0.38}"
    Text: .x0 + 0.016, "left", 0.5, "half", .label$
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

# Text on a small background box (readable over waveforms and grid lines)
procedure boxText: .x, .align$, .y, .s$
    .w = Text width (world coordinates): .s$

    .x0 = if .align$ = "right" then .x - .w else .x fi
    .ext = Horizontal mm to world coordinates: 0.6
    .vh = Vertical mm to world coordinates: 1.4
    Paint rectangle: "{0.97, 0.97, 0.99}", .x0 - .ext, .x0 + .w + .ext, .y - .vh, .y + .vh
    Text: .x, .align$, .y, "half", .s$
endproc
