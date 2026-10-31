# ============================================================
# Praat AudioTools - CDP_Chain_1.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0.1 (2026)
# License: MIT License (scripts). Bundled CDP programs: LGPL-2.1-or-later.
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CDP Chain 1 - one compositional gesture in four CDP stages:
#   1. Spectral Blur              - smooths short-time spectral change
#   2. Invert Formants            - peaks become troughs, troughs peaks
#   3. Waveset Reform: Exaggerate - waveform-level reshaping
#   4. Delay with Feedback        - a short resonant temporal extension
#   One selected Sound in, one new Sound out. Each stage runs on the
#   previous stage's result through the CDP Process Explorer engine
#   (internal/cdp_engine.praat); nothing is processed here directly.
#   After each stage the result is scaled to peak 0.9 (stagePeak) so the
#   next stage gets a full-level signal and the final Sound is not quiet.
#   The original Sound is never changed. Intermediate Sounds are removed;
#   only the final Sound remains, is selected, and plays once.
#   Requires Praat 6.4 or newer. Windows binaries only. No Python.
#
# Changelog v1.0.1 (2026):
#   - Level staging: each stage result is scaled to peak 0.9 (the v1.0.0
#     output could end some 25 dB down). A silent stage now stops the chain.
# ============================================================

include internal/cdp_engine.praat

# ---- The chain: process_id and every parameter as param_id=value ------
# Edit here to change the composition. The ids are those of
# CDP_Processes.tsv / CDP_Parameters.tsv; every parameter must be given.
nStages = 4
stagePid$ [1] = "spectral_blur"
stageValues$ [1] = "blurring=50"
stagePid$ [2] = "sp_fnu_3"
stageValues$ [2] = "vibrate=0 gain=1"
stagePid$ [3] = "reform_8"
stageValues$ [3] = "exag=2"
stagePid$ [4] = "echo"
stageValues$ [4] = "delay=250 mix=0.5 feedback=0.4 tail=2 prescale=0.7 invert=0"
chainSuffix$ = "_CDP_Chain_1"
# Level staging: every stage result (never the original) is scaled to this
# peak before the next stage, so CDP always gets a full-level signal and the
# final Sound is not near-silent. Set to 0 to keep CDP's levels unchanged.
stagePeak = 0.9

# ---- Source -------------------------------------------------------------
if numberOfSelected () <> 1 or numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object to start CDP Chain 1."
endif
sourceID = selected ("Sound")
sourceName$ = selected$ ("Sound")
sourceDur = Get total duration
sourceChannels = Get number of channels

@cdpx_init: defaultDirectory$
if cdpx_error$ <> ""
    selectObject: sourceID
    exitScript: "CDP Chain 1: " + cdpx_error$
endif

# Check the whole chain against the registry before anything runs.
for s to nStages
    @setStageValues: s
    if setStageValues.msg$ <> ""
        selectObject: sourceID
        exitScript: "CDP Chain 1, stage " + string$ (s) + " (" + stagePid$ [s] + "): " + setStageValues.msg$
    endif
endfor

# ---- Run the four stages ------------------------------------------------
# currentID is the input of the next stage; intermediate results are kept
# until the following stage has succeeded, then removed.
currentID = sourceID
report$ = ""
for s to nStages
    @setStageValues: s
    cdpx_sourceID = currentID
    cdpx_pid$ = stagePid$ [s]
    @cdpx_process
    if cdpx_error$ <> ""
        # stop: remove this chain's intermediate Sound, keep the original
        if currentID <> sourceID
            removeObject: currentID
        endif
        writeInfoLine: "=== CDP Chain 1 - stopped at stage ", s, " (", cdpx_displayName$, ") ===", newline$, cdpx_error$
        if cdpx_commandLine$ <> ""
            appendInfoLine: "Command line: ", cdpx_commandLine$
        endif
        selectObject: sourceID
        exitScript: "CDP Chain 1 stopped at stage " + string$ (s) + " (" + cdpx_displayName$ + "):" + newline$ + cdpx_error$
    endif
    report$ = report$ + string$ (s) + ". " + cdpx_displayName$ + "  [" + stagePid$ [s] + "]" + newline$ + cdpx_paramText$
    report$ = report$ + "   -> " + fixed$ (cdpx_outDur, 3) + " s, " + string$ (cdpx_outChannels) + " ch" + newline$
    if cdpx_channelAction$ <> "none"
        report$ = report$ + "   Channels: " + cdpx_channelAction$ + newline$
    endif
    if cdpx_warning$ <> ""
        report$ = report$ + "   Level: " + replace$ (cdpx_warning$, newline$, " ", 0) + newline$
    endif
    if currentID <> sourceID
        removeObject: currentID
    endif
    currentID = cdpx_resultID
    selectObject: currentID
    stageOutPeak = Get absolute extremum: 0, 0, "None"
    if stageOutPeak = 0 or stageOutPeak = undefined
        removeObject: currentID
        selectObject: sourceID
        exitScript: "CDP Chain 1 stopped at stage " + string$ (s) + " (" + cdpx_displayName$ + "):" + newline$ + "the stage produced silence."
    endif
    if stagePeak > 0
        Scale peak: stagePeak
        stageGainDb = round (200 * log10 (stagePeak / stageOutPeak)) / 10
        report$ = report$ + "   Level: " + fixed$ (stageGainDb, 1) + " dB (peak " + fixed$ (stageOutPeak, 3) + " -> " + fixed$ (stagePeak, 2) + ")" + newline$
    endif
endfor

# ---- Final Sound ----------------------------------------------------------
@uniqueSoundName: sourceName$ + chainSuffix$
selectObject: currentID
Rename: uniqueSoundName.name$
finalName$ = selected$ ("Sound")
finalDur = Get total duration
finalChannels = Get number of channels

writeInfoLine: "=== CDP Chain 1 v1.0.1 ==="
appendInfoLine: "Original Sound : ", sourceName$, "  (", fixed$ (sourceDur, 3), " s, ", sourceChannels, " ch, unchanged)"
appendInfoLine: "Final Sound    : ", finalName$, "  (", fixed$ (finalDur, 3), " s, ", finalChannels, " ch)"
appendInfoLine: "Stages:"
appendInfo: report$

selectObject: currentID
Play

# ---- helpers ----------------------------------------------------------------
# Stage s -> cdpx_value [1..n] in registry order; .msg$ <> "" on any problem.
# Every parameter of the process must appear exactly once in stageValues$.
procedure setStageValues: .s
    .msg$ = ""
    @cdpx_findProcess: stagePid$ [.s]
    if cdpx_findProcess.row = 0
        .msg$ = "unknown process id."
    else
        @cdpx_collectParams: stagePid$ [.s]
        .n = cdpx_collectParams.n
        for .k to .n
            .set [.k] = 0
        endfor
        @cdpx_tokenize: stageValues$ [.s]
        for .i to cdpx_tokenize.n
            if .msg$ = ""
                .tok$ = cdpx_tok$ [.i]
                .eq = index (.tok$, "=")
                .id$ = left$ (.tok$, .eq - 1)
                @cdpx_paramIndex: .id$
                .k = cdpx_paramIndex.k
                if .eq < 2
                    .msg$ = "'" + .tok$ + "' is not of the form param_id=value."
                elsif .k = 0
                    .msg$ = "unknown parameter '" + .id$ + "'."
                elsif .set [.k]
                    .msg$ = "parameter '" + .id$ + "' is given twice."
                else
                    cdpx_value [.k] = number (mid$ (.tok$, .eq + 1, 1000))
                    .set [.k] = 1
                    @cdpx_checkValue: cdpx_paramRow [.k], cdpx_value [.k]
                    if cdpx_checkValue.msg$ <> ""
                        .msg$ = .id$ + ": " + cdpx_checkValue.msg$
                    endif
                endif
            endif
        endfor
        for .k to .n
            if .msg$ = "" and not .set [.k]
                .msg$ = "parameter '" + cdpx_t2_param_id$ [cdpx_paramRow [.k]] + "' is missing."
            endif
        endfor
    endif
endproc

# .name$ = base, or base_2, base_3 ... if a Sound of that name exists.
# Praat turns characters it does not allow in names into "_"; Rename does
# the same, so the comparison uses the name Praat would give.
procedure uniqueSoundName: .base$
    .base$ = replace_regex$ (.base$, "[^A-Za-z0-9_\-]", "_", 0)
    select all
    .nAll = numberOfSelected ("Sound")
    for .i to .nAll
        .existing$ [.i] = selected$ ("Sound", .i)
    endfor
    .name$ = .base$
    .try = 1
    .clash = 1
    while .clash
        .clash = 0
        for .i to .nAll
            if .existing$ [.i] = .name$
                .clash = 1
            endif
        endfor
        if .clash
            .try += 1
            .name$ = .base$ + "_" + string$ (.try)
        endif
    endwhile
endproc
