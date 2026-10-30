# ============================================================
# Praat AudioTools - CDP_Process_Explorer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.0 (2026)
# License: MIT License (scripts). Bundled CDP programs: LGPL-2.1-or-later.
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   One entry point for the original Composers Desktop Project (CDP)
#   engines. Select ONE Sound, choose a process, set its parameters.
#   Apply runs CDP invisibly from the bundled engine folder, adds the
#   result as a new Sound, plays it, and keeps the dialog open for the
#   next try. OK runs and closes; Back returns to the process list;
#   Close stops. Every run starts from the original Sound, which is
#   never modified. Processes are defined in CDP_Processes.tsv and
#   CDP_Parameters.tsv; the engine is internal/cdp_engine.praat. No Python.
#   Requires Praat 6.4 or newer. Windows binaries only.
#
# Changelog v0.5.0 (2026):
#   - New category Spectral Formants: 17 formant-aware SPECFNU modes
#     (narrow, squeeze, invert, rotate, move formants; transpose, shift,
#     pitch invert/randomise while keeping the formants; Sine Speech).
#     204 processes in total. Final expansion for this release cycle.
#
# Changelog v0.4.0 (2026):
#   - 84 spectral (PVOC) processes in five categories: Blur & Noise,
#     Focus & Sustain, Filter & Trace, Pitch & Shift, Edit. 187 in total.
#
# Changelog v0.3.0 (2026):
#   - New category Spectral (PVOC) with Spectral Blur. Analysis and
#     resynthesis run automatically; the user still chooses Sound in,
#     Sound out. Multichannel Sounds are mixed to mono automatically.
#
# Changelog v0.2.4 (2026):
#   - Normalise uses CDP "force level" (loudness mode 4). Mode 3 refused
#     every Sound already above the target level.
#
# Changelog v0.2.3 (2026):
#   - The engine moved to internal/cdp_engine.praat (loaded by include),
#     so only this script belongs in the menu.
#
# Changelog v0.2.2 (2026):
#   - Standards button in the parameter dialog: restores the default
#     values of the current process (as in the other suite scripts).
#
# Changelog v0.2.1 (2026):
#   - No mono/stereo question: channels are kept when the process accepts
#     them, otherwise the Sound is mixed to mono (average) automatically.
#   - Sounds peaking above 1 are attenuated, not clipped, for the transfer.
#   - A failed CDP run gives one clear message in the dialog.
#
# Changelog v0.2.0 (2026):
#   - No registry Tables in the Objects window. The registry is read
#     into script variables and the Tables are removed immediately.
#   - Play result is ON by default and uses plain Play, as in the
#     rest of the suite.
#   - Suite-standard header, messages and indentation.
#
# Changelog v0.2.0 (2026):
#   - Apply / OK / Back / Close. Apply keeps the dialog open with the
#     last values; refused values are shown inside the dialog.
#
# Changelog v0.1.0 (2026):
#   - First version: generic engine, TSV registry, Speed Change,
#     Waveset Reform (square wave).
# ============================================================

include internal/cdp_engine.praat

# Above this many processes the choice is split into Category, then Process.
combinedMenuLimit = 15

if numberOfSelected () <> 1 or numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
sourceID = selected ("Sound")
sourceName$ = selected$ ("Sound")
sourceChannels = Get number of channels
sourceRate = Get sampling frequency

@cdpx_init: defaultDirectory$
if cdpx_error$ <> ""
    @abort: cdpx_error$
endif

# ---- Category / process menu (built once) -------------------------------
# Order: categories in order of first appearance, processes as listed.
nCat = 0
for r to cdpx_nProc
    @cdpx_cell: cdpx_procTable, r, "category"
    known = 0
    for c to nCat
        if category$ [c] = cdpx_cell.v$
            known = c
        endif
    endfor
    if known = 0
        nCat += 1
        category$ [nCat] = cdpx_cell.v$
    endif
endfor
nMenu = 0
for c to nCat
    for r to cdpx_nProc
        @cdpx_cell: cdpx_procTable, r, "category"
        if cdpx_cell.v$ = category$ [c]
            nMenu += 1
            menuRow [nMenu] = r
            menuCat [nMenu] = c
        endif
    endfor
endfor

soundInfo$ = "Sound: " + sourceName$ + "  (" + string$ (sourceChannels) + " ch, " + string$ (sourceRate) + " Hz)"
menuChoice = 1
catChoice = 1
stage1Msg$ = ""
playResult = 1
lastResultID = 0
nResults = 0
finished = 0

while not finished
    # ---- Stage 1: choose a process --------------------------------------
    if nMenu <= combinedMenuLimit
        beginPause: "CDP Process Explorer"
            comment: soundInfo$
            if stage1Msg$ <> ""
                comment: stage1Msg$
            endif
            optionMenu: "Process", menuChoice
            for m to nMenu
                @cdpx_cell: cdpx_procTable, menuRow [m], "display_name"
                option: category$ [menuCat [m]] + "  >  " + cdpx_cell.v$
            endfor
        clicked = endPause: "Close", "Next", 2, 1
        if clicked = 1
            @finish
        endif
        menuChoice = process
        chosenRow = menuRow [process]
    else
        beginPause: "CDP Process Explorer"
            comment: soundInfo$
            if stage1Msg$ <> ""
                comment: stage1Msg$
            endif
            optionMenu: "Category", catChoice
            for c to nCat
                option: category$ [c]
            endfor
        clicked = endPause: "Close", "Next", 2, 1
        if clicked = 1
            @finish
        endif
        catChoice = category
        nSub = 0
        beginPause: "CDP Process Explorer"
            comment: soundInfo$
            comment: "Category: " + category$ [catChoice]
            optionMenu: "Process", 1
            for m to nMenu
                if menuCat [m] = catChoice
                    nSub += 1
                    subRow [nSub] = menuRow [m]
                    @cdpx_cell: cdpx_procTable, menuRow [m], "display_name"
                    option: cdpx_cell.v$
                endif
            endfor
        clicked = endPause: "Close", "Next", 2, 1
        if clicked = 1
            @finish
        endif
        chosenRow = subRow [process]
    endif
    stage1Msg$ = ""

    @cdpx_cell: cdpx_procTable, chosenRow, "process_id"
    pid$ = cdpx_cell.v$
    @cdpx_cell: cdpx_procTable, chosenRow, "display_name"
    displayName$ = cdpx_cell.v$
    @cdpx_cell: cdpx_procTable, chosenRow, "category"
    categoryName$ = cdpx_cell.v$
    @cdpx_cell: cdpx_procTable, chosenRow, "notes"
    notes$ = cdpx_cell.v$

    # Channels are handled automatically by the engine (kept, or mixed to mono).
    @cdpx_channelRange: chosenRow
    channelsOK = sourceChannels >= cdpx_channelRange.min and sourceChannels <= cdpx_channelRange.max
    @parameterDialog
endwhile

# ---- Stage 2: parameters, with Apply (stay) and OK (close) -------------
procedure parameterDialog
    @cdpx_collectParams: pid$
    nPar = cdpx_collectParams.n
    for .k to nPar
        parRow [.k] = cdpx_paramRow [.k]
        .row = parRow [.k]
        curValue [.k] = number (cdpx_t2_default$ [.row])
    endfor
    stage2Msg$ = ""
    .back = 0
    while not .back and not finished
        beginPause: "CDP Process Explorer"
            comment: categoryName$ + "  >  " + displayName$
            if notes$ <> ""
                comment: notes$
            endif
            for .k to nPar
                .row = parRow [.k]
                .label$ = cdpx_t2_label$ [.row]
                .type$ = cdpx_t2_type$ [.row]
                @cdpx_cell: cdpx_parTable, parRow [.k], "min"
                .min$ = cdpx_cell.v$
                @cdpx_cell: cdpx_parTable, parRow [.k], "max"
                .max$ = cdpx_cell.v$
                @cdpx_cell: cdpx_parTable, parRow [.k], "help"
                .help$ = cdpx_cell.v$
                if curValue [.k] = undefined
                    .cur$ = "undefined"
                else
                    .cur$ = string$ (curValue [.k])
                endif
                if .type$ = "boolean"
                    .min$ = ""
                    .max$ = ""
                endif
                # Range and short help go in brackets after the label: Praat
                # ignores bracketed text when it names the dialog variable.
                # Kept short so labels are not cut off; "min 0" is omitted.
                .range$ = ""
                if .min$ <> "" and .max$ <> ""
                    .range$ = .min$ + " to " + .max$
                elsif .min$ <> "" and .min$ <> "0"
                    .range$ = "min " + .min$
                elsif .max$ <> ""
                    .range$ = "max " + .max$
                endif
                if .help$ = .range$
                    .help$ = ""
                endif
                .suffix$ = .range$
                .longHelp$ = ""
                if .help$ <> "" and length (.help$) <= 14
                    if .suffix$ <> ""
                        .suffix$ = .help$ + ", " + .suffix$
                    else
                        .suffix$ = .help$
                    endif
                elsif .help$ <> "" and nPar <= 4
                    .longHelp$ = .help$
                endif
                .shown$ = .label$
                if .suffix$ <> ""
                    .shown$ = .label$ + " (" + .suffix$ + ")"
                endif
                if .type$ = "boolean"
                    boolean: .shown$, curValue [.k]
                elsif .type$ = "integer"
                    integer: .shown$, .cur$
                else
                    real: .shown$, .cur$
                endif
                if .longHelp$ <> ""
                    comment: "      " + .longHelp$
                endif
            endfor
            .info$ = ""
            if nPar = 0
                .info$ = "No numeric parameters.  "
            endif
            if cdpx_channelRange.max = 1
                .info$ = .info$ + "Requires mono input.  "
            endif
            if not channelsOK
                .info$ = .info$ + "This " + string$ (sourceChannels) + "-channel Sound will be mixed to mono."
            endif
            if .info$ <> ""
                comment: .info$
            endif
            boolean: "Play result", playResult
            if stage2Msg$ <> ""
                comment: stage2Msg$
            endif
        # Buttons: Standards | Close | Back | Apply | OK  (default Apply)
        clicked = endPause: "Standards", "Close", "Back", "Apply", "OK", 4, 2
        if clicked = 1
            # Standards: back to the registry defaults (and Play result on)
            for .k to nPar
                .row = parRow [.k]
                curValue [.k] = number (cdpx_t2_default$ [.row])
            endfor
            playResult = 1
            stage2Msg$ = "Standard settings restored."
        elsif clicked = 2
            @finish
        elsif clicked = 3
            .back = 1
        else
            # Read the dialog values back by their derived variable names.
            for .k to nPar
                .row = parRow [.k]
                .label$ = cdpx_t2_label$ [.row]
                @cdpx_labelToVar: .label$
                .var$ = cdpx_labelToVar.var$
                curValue [.k] = '.var$'
                cdpx_value [.k] = curValue [.k]
            endfor
            playResult = play_result
            @runOnce
            if cdpx_error$ = ""
                stage2Msg$ = "Last result: " + cdpx_resultName$ + "  (" + fixed$ (cdpx_outDur, 3) + " s)   -   " + string$ (nResults) + " new Sound(s) so far"
                if clicked = 5
                    @finish
                endif
            else
                stage2Msg$ = "NOT processed: " + replace$ (cdpx_error$, newline$, "  ", 0)
            endif
        endif
    endwhile
endproc

# One CDP run on the ORIGINAL Sound. Errors found before CDP starts are
# returned (the dialog stays open); a failing CDP program stops the script.
procedure runOnce
    cdpx_sourceID = sourceID
    cdpx_pid$ = pid$
    @cdpx_process
    if cdpx_error$ = ""
        writeInfo: cdpx_report$
        lastResultID = cdpx_resultID
        nResults += 1
        if playResult
            selectObject: cdpx_resultID
            Play
        endif
    elsif cdpx_inPath$ <> ""
        writeInfoLine: cdpx_report$
    endif
endproc

# ---- helpers ------------------------------------------------------------
procedure abort: .msg$
    @cdpx_release
    selectObject: sourceID
    exitScript: .msg$
endproc

# Close the Explorer. Every Sound made with Apply/OK stays in the list;
# the last one is selected (or the original if nothing was made).
procedure finish
    @cdpx_release
    if lastResultID <> 0
        selectObject: lastResultID
    else
        selectObject: sourceID
    endif
    exitScript ()
endproc
