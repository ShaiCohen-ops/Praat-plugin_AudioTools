# ============================================================
# Praat AudioTools - CDP_Composition_2.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0.1 (2026)
# License: MIT License (scripts). Bundled CDP programs: LGPL-2.1-or-later.
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CDP Composition 2 - three granular / time-domain CDP transformations in
#   PARALLEL, placed across the stereo field and entering one after the
#   other, like voices in a canon. Every branch starts from the original:
#            +- 1 Grain Timewarp x3  (sparse grains)   left    enters 0 s
#   Sound ---+- 2 Iterate            (a dense cloud)   centre  enters 1 s
#            +- 3 Scramble           (a cut-up)        right   enters 2 s
#   Each branch runs through the CDP Process Explorer engine
#   (internal/cdp_engine.praat), is made mono if needed and scaled to
#   peak 0.9, then panned (equal power) and placed at its entry time; the
#   mix is scaled to peak 0.9. One new STEREO Sound results; it is
#   selected and plays once. The original Sound is never changed; the
#   branch Sounds are removed.
#   Requires Praat 6.4 or newer. Windows binaries only. No Python.
#
# Changelog v1.0.1 (2026):
#   - Branch 2 uses Iterate (repetitions): 50 copies, so the cloud grows
#     with the input. Iterate (duration) refused Sounds longer than its
#     fixed 6 s output duration.
# ============================================================

include internal/cdp_engine.praat

# ---- The composition: one CDP process per branch -------------------------
# process_id, every parameter as param_id=value (ids of CDP_Processes.tsv /
# CDP_Parameters.tsv), the stereo position (-1 = left, 0 = centre,
# +1 = right) and the entry time in seconds.
nBranches = 3
stagePid$ [1] = "grain_timewarp"
stageValues$ [1] = "ratio=3 gate=0.3 minhole=0.032 nolast=0"
branchPan [1] = -0.8
branchStart [1] = 0
stagePid$ [2] = "iterate_2"
stageValues$ [2] = "reps=50 delay=0.08 rand=0.6 pshift=2 ampcut=0.4 fade=0 gain=0 seed=0"
branchPan [2] = 0
branchStart [2] = 1
stagePid$ [3] = "scramble_1"
stageValues$ [3] = "minlen=0.05 maxlen=0.2 outdur=6 splen=15 seed=0 keepstart=0 keepend=0"
branchPan [3] = 0.8
branchStart [3] = 2
compSuffix$ = "_CDP_Composition_2"
# Each branch, and the final mix, is scaled to this peak.
stagePeak = 0.9

# ---- Source -------------------------------------------------------------
if numberOfSelected () <> 1 or numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object to start CDP Composition 2."
endif
sourceID = selected ("Sound")
sourceName$ = selected$ ("Sound")
sourceDur = Get total duration
sourceChannels = Get number of channels

@cdpx_init: defaultDirectory$
if cdpx_error$ <> ""
    selectObject: sourceID
    exitScript: "CDP Composition 2: " + cdpx_error$
endif

# Check every branch against the registry before anything runs.
for s to nBranches
    @setStageValues: s
    if setStageValues.msg$ <> ""
        selectObject: sourceID
        exitScript: "CDP Composition 2, branch " + string$ (s) + " (" + stagePid$ [s] + "): " + setStageValues.msg$
    endif
endfor

# ---- Run the branches, each on the ORIGINAL Sound ------------------------
report$ = ""
maxDur = 0
for s to nBranches
    @setStageValues: s
    cdpx_sourceID = sourceID
    cdpx_pid$ = stagePid$ [s]
    @cdpx_process
    if cdpx_error$ <> ""
        @removeBranches: s - 1
        writeInfoLine: "=== CDP Composition 2 - stopped at branch ", s, " (", cdpx_displayName$, ") ===", newline$, cdpx_error$
        if cdpx_commandLine$ <> ""
            appendInfoLine: "Command line: ", cdpx_commandLine$
        endif
        selectObject: sourceID
        exitScript: "CDP Composition 2 stopped at branch " + string$ (s) + " (" + cdpx_displayName$ + "):" + newline$ + cdpx_error$
    endif
    branchID [s] = cdpx_resultID
    report$ = report$ + string$ (s) + ". " + cdpx_displayName$ + "  [" + stagePid$ [s] + "]   position " + fixed$ (branchPan [s], 2) + ", enters at " + fixed$ (branchStart [s], 2) + " s" + newline$ + cdpx_paramText$
    report$ = report$ + "   -> " + fixed$ (cdpx_outDur, 3) + " s, " + string$ (cdpx_outChannels) + " ch" + newline$
    if cdpx_channelAction$ <> "none"
        report$ = report$ + "   Channels: " + cdpx_channelAction$ + newline$
    endif
    if cdpx_warning$ <> ""
        report$ = report$ + "   Level: " + replace$ (cdpx_warning$, newline$, " ", 0) + newline$
    endif
    # one channel per branch: a stereo result is mixed to mono for panning
    selectObject: branchID [s]
    if cdpx_outChannels > 1
        branchMono = Convert to mono
        removeObject: branchID [s]
        branchID [s] = branchMono
        report$ = report$ + "   Mixed to mono for panning" + newline$
    endif
    selectObject: branchID [s]
    stageOutPeak = Get absolute extremum: 0, 0, "None"
    if stageOutPeak = 0 or stageOutPeak = undefined
        @removeBranches: s
        selectObject: sourceID
        exitScript: "CDP Composition 2 stopped at branch " + string$ (s) + " (" + cdpx_displayName$ + "):" + newline$ + "the branch produced silence."
    endif
    Scale peak: stagePeak
    stageGainDb = round (200 * log10 (stagePeak / stageOutPeak)) / 10
    report$ = report$ + "   Level: " + fixed$ (stageGainDb, 1) + " dB (peak " + fixed$ (stageOutPeak, 3) + " -> " + fixed$ (stagePeak, 2) + ")" + newline$
    branchDur = Get total duration
    if branchStart [s] + branchDur > maxDur
        maxDur = branchStart [s] + branchDur
    endif
endfor

# ---- Stereo mix: equal-power panning, each branch at its entry time -----
selectObject: sourceID
mixRate = Get sampling frequency
@uniqueSoundName: sourceName$ + compSuffix$
mixID = Create Sound from formula: uniqueSoundName.name$, 2, 0, maxDur, mixRate, "0"
for s to nBranches
    panAngle = (branchPan [s] + 1) * pi / 4
    gainL = cos (panAngle)
    gainR = sin (panAngle)
    b = branchID [s]
    entry = branchStart [s]
    selectObject: mixID
    Formula: "self + (if row = 1 then gainL else gainR fi) * object (b, x - entry)"
endfor
@removeBranches: nBranches
selectObject: mixID
mixPeak = Get absolute extremum: 0, 0, "None"
Scale peak: stagePeak
finalName$ = selected$ ("Sound")

writeInfoLine: "=== CDP Composition 2 v1.0.1 ==="
appendInfoLine: "Original Sound : ", sourceName$, "  (", fixed$ (sourceDur, 3), " s, ", sourceChannels, " ch, unchanged)"
appendInfoLine: "Final Sound    : ", finalName$, "  (", fixed$ (maxDur, 3), " s, 2 ch, peak ", fixed$ (stagePeak, 2), ")"
appendInfoLine: "Branches (each from the original; position -1 left ... +1 right):"
appendInfo: report$
appendInfoLine: "Mix: peak ", fixed$ (mixPeak, 3), " -> ", fixed$ (stagePeak, 2)

selectObject: mixID
Play

# ---- helpers ----------------------------------------------------------------
# Remove the branch Sounds 1..n made so far (never the original).
procedure removeBranches: .n
    for .i to .n
        removeObject: branchID [.i]
    endfor
endproc

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
