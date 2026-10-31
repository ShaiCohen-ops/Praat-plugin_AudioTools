# ============================================================
# Praat AudioTools - CDP_Composition_3.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0.0 (2026)
# License: MIT License (scripts). Bundled CDP programs: LGPL-2.1-or-later.
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CDP Composition 3 - three resonant / pitch CDP transformations in
#   PARALLEL that MOVE through the stereo field while they sound; two of
#   them cross. Every branch starts from the original Sound:
#            +- 1 Filter Bank   (glass harmonics on A4)  left -> right
#   Sound ---+- 2 Stack         (a chord in fifths)      right -> left
#            +- 3 Shepard glissando (endless rise)       centre
#   Each branch runs through the CDP Process Explorer engine
#   (internal/cdp_engine.praat), is made mono if needed and scaled to
#   peak 0.9, its silent ending (below -60 dB) is cut so the movement ends
#   where the sound ends, then it is placed at its entry time and panned
#   (equal power) from its start position to its end position over its
#   own duration; the mix is scaled to peak 0.9. One new STEREO Sound
#   results; it is selected and plays once. The original Sound is never
#   changed; the branch Sounds are removed. All three processes work at
#   any input length.
#   Requires Praat 6.4 or newer. Windows binaries only. No Python.
# ============================================================

include internal/cdp_engine.praat

# ---- The composition: one CDP process per branch -------------------------
# process_id, every parameter as param_id=value (ids of CDP_Processes.tsv /
# CDP_Parameters.tsv), the stereo path (-1 = left, 0 = centre, +1 = right:
# the branch glides from panFrom to panTo over its duration) and the entry
# time in seconds.
nBranches = 3
stagePid$ [1] = "bank_1"
stageValues$ [1] = "q=200 gain=4 lof=440 hif=8000 tail=2 scat=0 double=0"
branchPanFrom [1] = -1
branchPanTo [1] = 1
branchStart [1] = 0
stagePid$ [2] = "stack"
stageValues$ [2] = "transp=7 count=3 lean=0.5 atk=0 gain=1 dur=1 norm=1"
branchPanFrom [2] = 1
branchPanTo [2] = -1
branchStart [2] = 0
stagePid$ [3] = "sp_glis_1"
stageValues$ [3] = "envpts=1 rate=1.5"
branchPanFrom [3] = 0
branchPanTo [3] = 0
branchStart [3] = 0.5
compSuffix$ = "_CDP_Composition_3"
# Each branch, and the final mix, is scaled to this peak.
stagePeak = 0.9

# ---- Source -------------------------------------------------------------
if numberOfSelected () <> 1 or numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object to start CDP Composition 3."
endif
sourceID = selected ("Sound")
sourceName$ = selected$ ("Sound")
sourceDur = Get total duration
sourceChannels = Get number of channels

@cdpx_init: defaultDirectory$
if cdpx_error$ <> ""
    selectObject: sourceID
    exitScript: "CDP Composition 3: " + cdpx_error$
endif

# Check every branch against the registry before anything runs.
for s to nBranches
    @setStageValues: s
    if setStageValues.msg$ <> ""
        selectObject: sourceID
        exitScript: "CDP Composition 3, branch " + string$ (s) + " (" + stagePid$ [s] + "): " + setStageValues.msg$
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
        writeInfoLine: "=== CDP Composition 3 - stopped at branch ", s, " (", cdpx_displayName$, ") ===", newline$, cdpx_error$
        if cdpx_commandLine$ <> ""
            appendInfoLine: "Command line: ", cdpx_commandLine$
        endif
        selectObject: sourceID
        exitScript: "CDP Composition 3 stopped at branch " + string$ (s) + " (" + cdpx_displayName$ + "):" + newline$ + cdpx_error$
    endif
    branchID [s] = cdpx_resultID
    report$ = report$ + string$ (s) + ". " + cdpx_displayName$ + "  [" + stagePid$ [s] + "]   moves " + fixed$ (branchPanFrom [s], 2) + " -> " + fixed$ (branchPanTo [s], 2) + ", enters at " + fixed$ (branchStart [s], 2) + " s" + newline$ + cdpx_paramText$
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
        exitScript: "CDP Composition 3 stopped at branch " + string$ (s) + " (" + cdpx_displayName$ + "):" + newline$ + "the branch produced silence."
    endif
    Scale peak: stagePeak
    stageGainDb = round (200 * log10 (stagePeak / stageOutPeak)) / 10
    report$ = report$ + "   Level: " + fixed$ (stageGainDb, 1) + " dB (peak " + fixed$ (stageOutPeak, 3) + " -> " + fixed$ (stagePeak, 2) + ")" + newline$
    # cut a silent ending, so the glide ends where the sound ends
    @trimSilentEnd: branchID [s]
    branchID [s] = trimSilentEnd.id
    if trimSilentEnd.cut > 0
        report$ = report$ + "   Silent ending removed: " + fixed$ (trimSilentEnd.cut, 2) + " s" + newline$
    endif
    selectObject: branchID [s]
    branchDur = Get total duration
    branchLen [s] = branchDur
    if branchStart [s] + branchDur > maxDur
        maxDur = branchStart [s] + branchDur
    endif
endfor

# ---- Stereo mix: each branch at its entry time, gliding across the field --
# Equal-power panning with a position that moves linearly from panFrom to
# panTo over the branch's own duration.
selectObject: sourceID
mixRate = Get sampling frequency
@uniqueSoundName: sourceName$ + compSuffix$
mixID = Create Sound from formula: uniqueSoundName.name$, 2, 0, maxDur, mixRate, "0"
for s to nBranches
    b = branchID [s]
    entry = branchStart [s]
    len = branchLen [s]
    pFrom = branchPanFrom [s]
    pTo = branchPanTo [s]
    selectObject: mixID
    Formula: "self + (if row = 1 then cos ((pFrom + (pTo - pFrom) * min (max ((x - entry) / len, 0), 1) + 1) * pi / 4) else sin ((pFrom + (pTo - pFrom) * min (max ((x - entry) / len, 0), 1) + 1) * pi / 4) fi) * object (b, x - entry)"
endfor
@removeBranches: nBranches
selectObject: mixID
mixPeak = Get absolute extremum: 0, 0, "None"
Scale peak: stagePeak
finalName$ = selected$ ("Sound")

writeInfoLine: "=== CDP Composition 3 v1.0.0 ==="
appendInfoLine: "Original Sound : ", sourceName$, "  (", fixed$ (sourceDur, 3), " s, ", sourceChannels, " ch, unchanged)"
appendInfoLine: "Final Sound    : ", finalName$, "  (", fixed$ (maxDur, 3), " s, 2 ch, peak ", fixed$ (stagePeak, 2), ")"
appendInfoLine: "Branches (each from the original; -1 left ... +1 right):"
appendInfo: report$
appendInfoLine: "Mix: peak ", fixed$ (mixPeak, 3), " -> ", fixed$ (stagePeak, 2)

selectObject: mixID
Play

# ---- helpers ----------------------------------------------------------------
# Cut the ending of Sound .id that lies more than 60 dB below its loudest
# part (e.g. silent filter tails). .id is the (possibly new) Sound, .cut the
# seconds removed. Only the chain's own branch Sound is replaced.
procedure trimSilentEnd: .id
    .cut = 0
    selectObject: .id
    .dur = Get total duration
    if .dur > 0.2
        .int = To Intensity: 75, 0.01, "no"
        .max = Get maximum: 0, 0, "Parabolic"
        .n = Get number of frames
        .last = .n
        .found = 0
        while .last > 1 and not .found
            .v = Get value in frame: .last
            if .v <> undefined and .v > .max - 60
                .found = 1
            else
                .last -= 1
            endif
        endwhile
        .t = Get time from frame number: .last
        removeObject: .int
        .end = min (.dur, .t + 0.05)
        if .end < .dur - 0.1
            selectObject: .id
            .new = Extract part: 0, .end, "rectangular", 1, "no"
            removeObject: .id
            .id = .new
            .cut = .dur - .end
        endif
    endif
endproc

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
