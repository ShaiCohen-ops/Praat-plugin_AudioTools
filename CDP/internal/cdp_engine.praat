# ============================================================
# Praat AudioTools - internal/cdp_engine.praat (CDP Process Explorer engine)
# Not a menu command: loaded by CDP_Process_Explorer.praat with include.
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6.0 (2026)
# License: MIT License
#
# Changelog v0.6.0 (2026):
#   - Optional CDP_Presets.tsv (process_id, preset, values, description),
#     validated at start-up against the parameter registry.
#
# Changelog v0.3.0 (2026):
#   - input_type 'spectral': the process runs on a PVOC analysis file.
#     The engine runs pvoc anal 1 (CDP defaults) -> process -> pvoc synth;
#     .ana files are temporary and removed. Spectral processes are mono.
#
# Changelog v0.2.1 (2026):
#   - Channels are handled automatically: a channel count the process
#     accepts is kept, anything else is mixed to mono (average) on a copy.
#   - A Sound that peaks above 1 is attenuated (copy only) before the
#     16-bit transfer instead of being clipped; the dB value is reported;
#     no re-amplification afterwards.
#   - No second diagnostic run: a failed CDP run gives one clear message;
#     temporary files are removed in every case.
#
# Changelog v0.2.0 (2026):
#   - Parameter types real / integer / boolean; boolean = CDP flag such
#     as -n (column 'switch'); numeric switches as -x{param} in templates.
#   - CDP is started with nocheck: a refused run returns to the caller.
#     Success = a readable output file. Otherwise the command is repeated
#     once through the system shell only to capture CDP's explanation
#     (CDP prints it on standard output, which Praat drops on failure).
#   - Column cdp_index: CDP's own parameter number, observed per process,
#     used to name the field in CDP's messages.
#   - Registry read into variables; no Table objects remain.
# ============================================================
# ------------------------------------------------------------------------
# Generic bridge between Praat Sound objects and bundled CDP executables.
# Included by CDP_Process_Explorer.praat and by tests/CDP_Run_Tests.praat.
#
# Nothing in this file names a specific CDP process. Every process is
# described in CDP_Processes.tsv + CDP_Parameters.tsv (the registry).
#
# Error convention: procedures never call exitScript. They set cdpx_error$
# and later steps are skipped. The caller decides how to report it.
# The single exception is a failing CDP program (nonzero exit status):
# Praat itself stops the script then. Diagnostics are written to the Info
# window BEFORE CDP runs, and temporary files are kept, so nothing is lost.
#
# Requires Praat 6.4 or newer (runSubprocess$, Windows argument quoting).
# ------------------------------------------------------------------------

cdpx_engineVersion$ = "0.6.0"
cdpx_maxArgs = 16

# ------------------------------------------------------------------------
# Initialisation: paths, platform, registry
# ------------------------------------------------------------------------

procedure cdpx_init: .baseDir$
    cdpx_error$ = ""
    cdpx_warning$ = ""
    cdpx_quiet = 0
    # registry handles (not Praat objects; see cdpx_cacheTable)
    cdpx_procTable = 1
    cdpx_parTable = 2
    cdpx_monoCopyID = 0
    cdpx_baseDir$ = .baseDir$
    if windows
        cdpx_sep$ = "\"
        cdpx_platform$ = "windows"
        cdpx_exeSuffix$ = ".exe"
    elsif macintosh
        cdpx_sep$ = "/"
        cdpx_platform$ = "macos"
        cdpx_exeSuffix$ = ""
    else
        cdpx_sep$ = "/"
        cdpx_platform$ = "linux"
        cdpx_exeSuffix$ = ""
    endif
    # Executables are ONLY looked up here. There is no PATH search and no
    # fallback to an installed CDP. Tests may override cdpx_engineDir$.
    cdpx_engineDir$ = cdpx_baseDir$ + cdpx_sep$ + "engine" + cdpx_sep$ + cdpx_platform$
    cdpx_workDir$ = temporaryDirectory$ + cdpx_sep$ + "AudioTools_CDP_work"
    if praatVersion < 6400
        cdpx_error$ = "CDP Process Explorer needs Praat 6.4 or newer (this is Praat " + praatVersion$ + ")." + newline$ + "Older Praat versions cannot run external programs reliably on Windows."
    endif
    if cdpx_error$ = ""
        @cdpx_loadRegistry
    endif
endproc

procedure cdpx_loadRegistry
    .procFile$ = cdpx_baseDir$ + cdpx_sep$ + "CDP_Processes.tsv"
    .parFile$ = cdpx_baseDir$ + cdpx_sep$ + "CDP_Parameters.tsv"
    if not fileReadable (.procFile$)
        cdpx_error$ = "Process registry not found:" + newline$ + .procFile$
    elsif not fileReadable (.parFile$)
        cdpx_error$ = "Parameter registry not found:" + newline$ + .parFile$
    else
        .tp = Read Table from tab-separated file: .procFile$
        .tq = Read Table from tab-separated file: .parFile$
        @cdpx_requireColumns: .tp, "CDP_Processes.tsv", "process_id category display_name executable subcommand mode input_type output_type input_channels channel_policy output_channels dll_dependencies argument_template name_tag"
        if cdpx_error$ = ""
            @cdpx_requireColumns: .tq, "CDP_Parameters.tsv", "process_id order param_id label type default min max decimals switch cdp_index help"
        endif
        # Copy both registries into script variables and remove the Tables at
        # once: no registry object ever appears in the Objects window.
        if cdpx_error$ = ""
            @cdpx_cacheTable: .tp, cdpx_procTable
            @cdpx_cacheTable: .tq, cdpx_parTable
        endif
        removeObject: .tp, .tq
        if cdpx_error$ = ""
            @cdpx_validateRegistry
        endif
        if cdpx_error$ = ""
            @cdpx_loadPresets
        endif
    endif
endproc

# ---- Presets (optional CDP_Presets.tsv) -----------------------------------
# One row per preset: process_id, preset, values ("param_id=value ..."),
# description. Parameters not listed keep their registry default. Without
# the file there are simply no presets.
procedure cdpx_loadPresets
    cdpx_presetTable = 3
    cdpx_nRows [cdpx_presetTable] = 0
    .file$ = cdpx_baseDir$ + cdpx_sep$ + "CDP_Presets.tsv"
    if fileReadable (.file$)
        .t = Read Table from tab-separated file: .file$
        @cdpx_requireColumns: .t, "CDP_Presets.tsv", "process_id preset values description"
        if cdpx_error$ = ""
            @cdpx_cacheTable: .t, cdpx_presetTable
        endif
        removeObject: .t
    endif
    .n = cdpx_nRows [cdpx_presetTable]
    for .r to .n
        if cdpx_error$ = ""
            .pid$ = cdpx_t3_process_id$ [.r]
            .name$ = cdpx_t3_preset$ [.r]
            .w$ = "CDP_Presets.tsv row " + string$ (.r + 1) + " (" + .pid$ + ", " + .name$ + "): "
            @cdpx_findProcess: .pid$
            if cdpx_findProcess.row = 0
                cdpx_error$ = .w$ + "unknown process_id."
            elsif .name$ = "" or .name$ = "-" or index (.name$, "Standard") = 1
                cdpx_error$ = .w$ + "preset name is empty or starts with 'Standard' (reserved)."
            endif
            for .i to .r - 1
                if cdpx_error$ = "" and cdpx_t3_process_id$ [.i] = .pid$ and cdpx_t3_preset$ [.i] = .name$
                    cdpx_error$ = .w$ + "duplicate preset name."
                endif
            endfor
            if cdpx_error$ = ""
                @cdpx_collectParams: .pid$
                @cdpx_applyPreset: .r
                if cdpx_applyPreset.msg$ <> ""
                    cdpx_error$ = .w$ + cdpx_applyPreset.msg$
                endif
            endif
        endif
    endfor
endproc

# Preset rows of one process -> cdpx_presetRow [1..n]
procedure cdpx_presetsFor: .pid$
    .n = 0
    for .r to cdpx_nRows [cdpx_presetTable]
        if cdpx_t3_process_id$ [.r] = .pid$
            .n += 1
            cdpx_presetRow [.n] = .r
        endif
    endfor
endproc

# Values of preset row .r for the params last collected (cdpx_collectParams)
# -> cdpx_presetValue [1..n]; .msg$ is "" when every value is valid.
procedure cdpx_applyPreset: .r
    .msg$ = ""
    for .k to cdpx_collectParams.n
        .row = cdpx_paramRow [.k]
        cdpx_presetValue [.k] = number (cdpx_t2_default$ [.row])
    endfor
    @cdpx_tokenize: cdpx_t3_values$ [.r]
    .nt = cdpx_tokenize.n
    for .i to .nt
        .tok$ [.i] = cdpx_tok$ [.i]
    endfor
    for .i to .nt
        if .msg$ = ""
            .eq = index (.tok$ [.i], "=")
            if .eq < 2
                .msg$ = "'" + .tok$ [.i] + "' is not of the form param_id=value."
            else
                .id$ = left$ (.tok$ [.i], .eq - 1)
                .x = number (mid$ (.tok$ [.i], .eq + 1, 1000))
                @cdpx_paramIndex: .id$
                if cdpx_paramIndex.k = 0
                    .msg$ = "unknown parameter '" + .id$ + "'."
                else
                    @cdpx_checkValue: cdpx_paramRow [cdpx_paramIndex.k], .x
                    if cdpx_checkValue.msg$ <> ""
                        .msg$ = .id$ + ": " + cdpx_checkValue.msg$
                    else
                        cdpx_presetValue [cdpx_paramIndex.k] = .x
                    endif
                endif
            endif
        endif
    endfor
endproc

# Table object -> variables cdpx_t<handle>_<column>$ [row], cdpx_nRows [handle]
procedure cdpx_cacheTable: .table, .handle
    selectObject: .table
    .nr = Get number of rows
    .nc = Get number of columns
    cdpx_nRows [.handle] = .nr
    for .c to .nc
        selectObject: .table
        .col$ = Get column label: .c
        if index_regex (.col$, "^[a-z][a-z0-9_]*$") = 1
            for .r to .nr
                selectObject: .table
                .v$ = Get value: .r, .col$
                cdpx_t'.handle'_'.col$'$ [.r] = .v$
            endfor
        endif
    endfor
endproc

procedure cdpx_requireColumns: .table, .fileName$, .columns$
    selectObject: .table
    .rest$ = .columns$ + " "
    while .rest$ <> "" and cdpx_error$ = ""
        .sp = index (.rest$, " ")
        .col$ = left$ (.rest$, .sp - 1)
        .rest$ = mid$ (.rest$, .sp + 1, 10000)
        if .col$ <> ""
            .ci = Get column index: .col$
            if .ci = 0
                cdpx_error$ = "Malformed registry " + .fileName$ + ": missing column '" + .col$ + "'."
            endif
        endif
    endwhile
endproc

# Read one cell as a string; "-", "?" and "" all mean "empty".
procedure cdpx_cell: .table, .row, .col$
    .v$ = cdpx_t'.table'_'.col$'$ [.row]
    if .v$ = "-" or .v$ = "?"
        .v$ = ""
    endif
endproc

procedure cdpx_validateRegistry
    cdpx_nProc = cdpx_nRows [cdpx_procTable]
    if cdpx_nProc < 1
        cdpx_error$ = "Malformed registry: CDP_Processes.tsv contains no processes."
    endif
    .safe$ = "^[A-Za-z0-9._+-]+$"
    .ident$ = "^[a-z][a-z0-9_]*$"
    for .r to cdpx_nProc
        if cdpx_error$ = ""
            @cdpx_cell: cdpx_procTable, .r, "process_id"
            .pid$ = cdpx_cell.v$
            .where$ = "CDP_Processes.tsv row " + string$ (.r + 1) + " (" + .pid$ + "): "
            if index_regex (.pid$, .ident$) = 0
                cdpx_error$ = .where$ + "process_id must be lower-case letters, digits, underscores."
            endif
            # unique id
            for .r2 to .r - 1
                @cdpx_cell: cdpx_procTable, .r2, "process_id"
                if cdpx_cell.v$ = .pid$
                    cdpx_error$ = .where$ + "duplicate process_id."
                endif
            endfor
            @cdpx_cell: cdpx_procTable, .r, "executable"
            if cdpx_error$ = "" and index_regex (cdpx_cell.v$, "^[A-Za-z0-9_-]+$") = 0
                cdpx_error$ = .where$ + "executable must be a bare program name without extension or path (e.g. modify)."
            endif
            @cdpx_cell: cdpx_procTable, .r, "subcommand"
            if cdpx_error$ = "" and cdpx_cell.v$ <> "" and index_regex (cdpx_cell.v$, .safe$) = 0
                cdpx_error$ = .where$ + "subcommand contains unsafe characters."
            endif
            @cdpx_cell: cdpx_procTable, .r, "mode"
            if cdpx_error$ = "" and cdpx_cell.v$ <> "" and index_regex (cdpx_cell.v$, "^[0-9]+$") = 0
                cdpx_error$ = .where$ + "mode must be a whole number or '-'."
            endif
            @cdpx_cell: cdpx_procTable, .r, "input_channels"
            if cdpx_error$ = "" and index_regex (cdpx_cell.v$, "^[0-9]+-[0-9]+$") = 0
                cdpx_error$ = .where$ + "input_channels must look like 1-1 or 1-2."
            endif
            @cdpx_cell: cdpx_procTable, .r, "channel_policy"
            if cdpx_error$ = "" and index_regex (cdpx_cell.v$, "^(reject)(,downmix)?$") = 0
                cdpx_error$ = .where$ + "channel_policy must be 'reject' or 'reject,downmix' in v0.1.0."
            endif
            @cdpx_cell: cdpx_procTable, .r, "output_channels"
            if cdpx_error$ = "" and index_regex (cdpx_cell.v$, "^(same|[0-9]+)$") = 0
                cdpx_error$ = .where$ + "output_channels must be 'same' or a number."
            endif
            @cdpx_cell: cdpx_procTable, .r, "dll_dependencies"
            if cdpx_error$ = "" and cdpx_cell.v$ <> "" and index_regex (cdpx_cell.v$, "^[A-Za-z0-9._+-]+(,[A-Za-z0-9._+-]+)*$") = 0
                cdpx_error$ = .where$ + "dll_dependencies must be a comma-separated list of file names or '-'."
            endif
            @cdpx_cell: cdpx_procTable, .r, "input_type"
            if cdpx_error$ = "" and cdpx_cell.v$ <> "sound" and cdpx_cell.v$ <> "spectral"
                cdpx_error$ = .where$ + "input_type must be 'sound' or 'spectral'."
            elsif cdpx_error$ = "" and cdpx_cell.v$ = "spectral" and cdpx_t1_input_channels$ [.r] <> "1-1"
                cdpx_error$ = .where$ + "a spectral process works on mono analysis files: input_channels must be 1-1."
            endif
            @cdpx_cell: cdpx_procTable, .r, "output_type"
            if cdpx_error$ = "" and cdpx_cell.v$ <> "sound"
                cdpx_error$ = .where$ + "output_type '" + cdpx_cell.v$ + "' is not supported in v0.1.0 (only 'sound')."
            endif
            if cdpx_error$ = ""
                @cdpx_validateParameters: .pid$, .where$
            endif
            if cdpx_error$ = ""
                @cdpx_validateTemplate: .r, .pid$, .where$
            endif
        endif
    endfor
    # every parameter row must belong to a known process
    .np = cdpx_nRows [cdpx_parTable]
    for .i to .np
        if cdpx_error$ = ""
            @cdpx_cell: cdpx_parTable, .i, "process_id"
            @cdpx_findProcess: cdpx_cell.v$
            if cdpx_findProcess.row = 0
                cdpx_error$ = "CDP_Parameters.tsv row " + string$ (.i + 1) + ": unknown process_id '" + cdpx_cell.v$ + "'."
            endif
        endif
    endfor
endproc

procedure cdpx_validateParameters: .pid$, .where$
    @cdpx_collectParams: .pid$
    .reserved$ = " e pi undefined windows macintosh unix praatVersion newline tab multichannel_input play_result process category preset "
    for .k to cdpx_collectParams.n
        if cdpx_error$ = ""
            .row = cdpx_paramRow [.k]
            @cdpx_cell: cdpx_parTable, .row, "param_id"
            .id$ = cdpx_cell.v$
            .w$ = .where$ + "parameter '" + .id$ + "': "
            if index_regex (.id$, "^[a-z][a-z0-9_]*$") = 0
                cdpx_error$ = .w$ + "param_id must be lower-case letters, digits, underscores."
            endif
            for .k2 to .k - 1
                @cdpx_cell: cdpx_parTable, cdpx_paramRow [.k2], "param_id"
                if cdpx_cell.v$ = .id$
                    cdpx_error$ = .w$ + "duplicate param_id."
                endif
            endfor
            if index (" input output subcommand mode ", " " + .id$ + " ") > 0
                cdpx_error$ = .w$ + "param_id may not be input, output, subcommand or mode."
            endif
            @cdpx_cell: cdpx_parTable, .row, "label"
            .label$ = cdpx_cell.v$
            if cdpx_error$ = "" and index_regex (.label$, "^[A-Za-z]([A-Za-z0-9 ]*[A-Za-z0-9])?$") = 0 or index (.label$, "  ") > 0
                cdpx_error$ = .w$ + "label may contain only letters, digits and single spaces (it becomes a dialog field)."
            endif
            @cdpx_labelToVar: .label$
            if cdpx_error$ = "" and (index (.reserved$, " " + cdpx_labelToVar.var$ + " ") > 0 or left$ (cdpx_labelToVar.var$, 4) = "cdpx")
                cdpx_error$ = .w$ + "label '" + .label$ + "' collides with a reserved Praat variable name."
            endif
            @cdpx_cell: cdpx_parTable, .row, "type"
            .type$ = cdpx_cell.v$
            if cdpx_error$ = "" and .type$ <> "real" and .type$ <> "integer" and .type$ <> "boolean"
                cdpx_error$ = .w$ + "type must be 'real', 'integer' or 'boolean'."
            endif
            @cdpx_cell: cdpx_parTable, .row, "switch"
            .sw$ = cdpx_cell.v$
            if cdpx_error$ = "" and .type$ = "boolean" and index_regex (.sw$, "^-[A-Za-z0-9]+$") = 0
                cdpx_error$ = .w$ + "a boolean parameter needs a switch such as -n."
            elsif cdpx_error$ = "" and .type$ <> "boolean" and .sw$ <> ""
                cdpx_error$ = .w$ + "only boolean parameters have a switch; numeric switches are written in argument_template, e.g. -s{scatter}."
            endif
            @cdpx_cell: cdpx_parTable, .row, "default"
            .def$ = cdpx_cell.v$
            .def = number (.def$)
            if cdpx_error$ = "" and .def = undefined
                cdpx_error$ = .w$ + "default '" + .def$ + "' is not a number."
            endif
            if cdpx_error$ = ""
                @cdpx_checkValue: .row, .def
                if cdpx_checkValue.msg$ <> ""
                    cdpx_error$ = .w$ + "default value is invalid: " + cdpx_checkValue.msg$
                endif
            endif
            @cdpx_cell: cdpx_parTable, .row, "cdp_index"
            if cdpx_error$ = "" and cdpx_cell.v$ <> "" and index_regex (cdpx_cell.v$, "^[0-9]+$") = 0
                cdpx_error$ = .w$ + "cdp_index must be a whole number or '-'."
            endif
            @cdpx_cell: cdpx_parTable, .row, "decimals"
            if cdpx_error$ = "" and cdpx_cell.v$ <> "" and index_regex (cdpx_cell.v$, "^[0-9]$") = 0
                cdpx_error$ = .w$ + "decimals must be a single digit or '-'."
            endif
        endif
    endfor
endproc

# Placeholders allowed in argument_template / name_tag:
#   {input} {output} {subcommand} {mode} and the process's own param_ids.
procedure cdpx_validateTemplate: .r, .pid$, .where$
    @cdpx_cell: cdpx_procTable, .r, "argument_template"
    .t$ = cdpx_cell.v$
    @cdpx_tokenize: .t$
    .nTok = cdpx_tokenize.n
    .nIn = 0
    .nOut = 0
    if .nTok < 2
        cdpx_error$ = .where$ + "argument_template is empty or too short."
    elsif .nTok > cdpx_maxArgs
        cdpx_error$ = .where$ + "argument_template has " + string$ (.nTok) + " arguments; the dispatcher supports at most " + string$ (cdpx_maxArgs) + "."
    endif
    @cdpx_collectParams: .pid$
    for .i to .nTok
        if cdpx_error$ = ""
            .tok$ = cdpx_tok$ [.i]
            if index (.tok$, "{") > 0
                if index_regex (.tok$, "^(-[A-Za-z]+)?\{[a-z][a-z0-9_]*\}$") = 0
                    cdpx_error$ = .where$ + "malformed placeholder " + .tok$ + " in argument_template."
                else
                    .brace = index (.tok$, "{")
                    .pre$ = left$ (.tok$, .brace - 1)
                    .name$ = mid$ (.tok$, .brace + 1, length (.tok$) - .brace - 1)
                    if .name$ = "input" or .name$ = "output" or .name$ = "subcommand" or .name$ = "mode"
                        if .pre$ <> ""
                            cdpx_error$ = .where$ + "{" + .name$ + "} cannot carry a switch prefix."
                        elsif .name$ = "input"
                            .nIn += 1
                        elsif .name$ = "output"
                            .nOut += 1
                        endif
                    else
                        @cdpx_paramIndex: .name$
                        if cdpx_paramIndex.k = 0
                            cdpx_error$ = .where$ + "placeholder " + .tok$ + " has no matching parameter in CDP_Parameters.tsv."
                        else
                            .prow = cdpx_paramRow [cdpx_paramIndex.k]
                            if cdpx_t2_type$ [.prow] = "boolean" and .pre$ <> ""
                                cdpx_error$ = .where$ + "boolean parameter " + .tok$ + " must appear as {" + .name$ + "} alone (its switch is in CDP_Parameters.tsv)."
                            endif
                        endif
                    endif
                endif
            elsif index_regex (.tok$, "^[A-Za-z0-9._+-]+$") = 0
                cdpx_error$ = .where$ + "literal argument '" + .tok$ + "' contains unsafe characters."
            endif
        endif
    endfor
    if cdpx_error$ = "" and (.nIn <> 1 or .nOut <> 1)
        cdpx_error$ = .where$ + "argument_template must contain {input} and {output} exactly once."
    endif
    # every declared parameter must be used in the command
    for .k to cdpx_collectParams.n
        if cdpx_error$ = ""
            @cdpx_cell: cdpx_parTable, cdpx_paramRow [.k], "param_id"
            if index (.t$, "{" + cdpx_cell.v$ + "}") = 0
                cdpx_error$ = .where$ + "parameter '" + cdpx_cell.v$ + "' is declared but not used in argument_template."
            endif
        endif
    endfor
    @cdpx_cell: cdpx_procTable, .r, "name_tag"
    if cdpx_error$ = "" and index_regex (cdpx_cell.v$, "^[A-Za-z0-9_{}.-]+$") = 0
        cdpx_error$ = .where$ + "name_tag may contain only letters, digits, _ - . and {placeholders}."
    endif
endproc

# ------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------

procedure cdpx_tokenize: .s$
    .n = 0
    .s$ = replace_regex$ (.s$, "\s+", " ", 0)
    .s$ = replace_regex$ (.s$, "^ | $", "", 0)
    .rest$ = .s$ + " "
    while .s$ <> "" and .rest$ <> ""
        .sp = index (.rest$, " ")
        .n += 1
        cdpx_tok$ [.n] = left$ (.rest$, .sp - 1)
        .rest$ = mid$ (.rest$, .sp + 1, 100000)
    endwhile
endproc

procedure cdpx_findProcess: .pid$
    .row = 0
    .nr = cdpx_nRows [cdpx_procTable]
    for .r to .nr
        .v$ = cdpx_t1_process_id$ [.r]
        if .v$ = .pid$
            .row = .r
        endif
    endfor
endproc

# Parameter rows of one process, sorted by 'order' -> cdpx_paramRow [1..n]
procedure cdpx_collectParams: .pid$
    .n = 0
    .nr = cdpx_nRows [cdpx_parTable]
    for .r to .nr
        .v$ = cdpx_t2_process_id$ [.r]
        if .v$ = .pid$
            .n += 1
            cdpx_paramRow [.n] = .r
            .ord [.n] = number (cdpx_t2_order$ [.r])
        endif
    endfor
    # insertion sort on order
    for .i from 2 to .n
        .j = .i
        while .j > 1 and .ord [.j - 1] > .ord [.j]
            .tmp = .ord [.j]
            .ord [.j] = .ord [.j - 1]
            .ord [.j - 1] = .tmp
            .tmp = cdpx_paramRow [.j]
            cdpx_paramRow [.j] = cdpx_paramRow [.j - 1]
            cdpx_paramRow [.j - 1] = .tmp
            .j -= 1
        endwhile
    endfor
endproc

# Index k (1..n) of param_id among the params last collected, 0 if absent
procedure cdpx_paramIndex: .id$
    .k = 0
    for .i to cdpx_collectParams.n
        .row = cdpx_paramRow [.i]
        .v$ = cdpx_t2_param_id$ [.row]
        if .v$ = .id$
            .k = .i
        endif
    endfor
endproc

# Praat pause-form rule: first letter lower-cased, spaces -> underscores
procedure cdpx_labelToVar: .label$
    .var$ = replace$ (.label$, " ", "_", 0)
    .c$ = left$ (.var$, 1)
    if index_regex (.c$, "[A-Z]") = 1
        .c$ = unicode$ (unicode (.c$) + 32)
    endif
    .var$ = .c$ + mid$ (.var$, 2, 10000)
endproc

# Check a numeric value against one parameter row -> .msg$ ("" if OK)
procedure cdpx_checkValue: .row, .x
    .msg$ = ""
    .type$ = cdpx_t2_type$ [.row]
    @cdpx_cell: cdpx_parTable, .row, "min"
    .min$ = cdpx_cell.v$
    @cdpx_cell: cdpx_parTable, .row, "max"
    .max$ = cdpx_cell.v$
    if .x = undefined
        .msg$ = "value is undefined."
    elsif .type$ = "boolean" and .x <> 0 and .x <> 1
        .msg$ = "value must be 0 (off) or 1 (on)."
    elsif .type$ = "boolean"
        .msg$ = ""
    elsif .type$ = "integer" and .x <> round (.x)
        .msg$ = "value " + string$ (.x) + " must be a whole number."
    elsif .min$ <> "" and .x < number (.min$)
        .msg$ = "value " + string$ (.x) + " is below the minimum " + .min$ + "."
    elsif .max$ <> "" and .x > number (.max$)
        .msg$ = "value " + string$ (.x) + " is above the maximum " + .max$ + "."
    endif
endproc

procedure cdpx_formatValue: .row, .x
    .type$ = cdpx_t2_type$ [.row]
    .text$ = ""
    if .type$ = "boolean"
        @cdpx_cell: cdpx_parTable, .row, "switch"
        if .x = 1
            .arg$ = cdpx_cell.v$
            .text$ = "on (" + cdpx_cell.v$ + ")"
        else
            .arg$ = ""
            .text$ = "off"
        endif
    elsif .type$ = "integer"
        .arg$ = string$ (round (.x))
    else
        .arg$ = string$ (.x)
    endif
    if .text$ = ""
        .text$ = .arg$
    endif
    @cdpx_cell: cdpx_parTable, .row, "decimals"
    if .type$ = "boolean"
        .tag$ = string$ (.x)
    elsif cdpx_cell.v$ = ""
        .tag$ = .arg$
    else
        .tag$ = fixed$ (.x, number (cdpx_cell.v$))
    endif
endproc

# Number of channels accepted: "1-2" -> .min 1, .max 2
procedure cdpx_channelRange: .row
    @cdpx_cell: cdpx_procTable, .row, "input_channels"
    .dash = index (cdpx_cell.v$, "-")
    .min = number (left$ (cdpx_cell.v$, .dash - 1))
    .max = number (mid$ (cdpx_cell.v$, .dash + 1, 100))
    @cdpx_cell: cdpx_procTable, .row, "channel_policy"
    .canDownmix = index (cdpx_cell.v$, "downmix") > 0 and .min = 1
endproc

# ------------------------------------------------------------------------
# Process execution
#   in : cdpx_sourceID, cdpx_pid$, cdpx_value [1..n] (numbers, in param
#        order of cdpx_collectParams)
#   out: cdpx_resultID (0 on failure), cdpx_error$, cdpx_report$
# ------------------------------------------------------------------------

procedure cdpx_process
    cdpx_error$ = ""
    cdpx_warning$ = ""
    cdpx_resultID = 0
    cdpx_report$ = ""
    @cdpx_prepare
    if cdpx_error$ = ""
        @cdpx_writeTemp
    endif
    if cdpx_error$ = ""
        @cdpx_queryVersion
    endif
    if cdpx_error$ = ""
        @cdpx_execute
    endif
    if cdpx_error$ = ""
        @cdpx_importResult
    endif
    if cdpx_error$ = ""
        @cdpx_cleanup
    else
        @cdpx_failureReport
    endif
    if cdpx_monoCopyID <> 0
        removeObject: cdpx_monoCopyID
        cdpx_monoCopyID = 0
    endif
endproc

procedure cdpx_prepare
    cdpx_monoCopyID = 0
    cdpx_inPath$ = ""
    cdpx_outPath$ = ""
    cdpx_anaIn$ = ""
    cdpx_anaOut$ = ""
    cdpx_version$ = "(not queried)"
    cdpx_commandLine$ = ""
    cdpx_paramText$ = ""
    cdpx_inChannels = 0
    cdpx_inRate = 0
    @cdpx_findProcess: cdpx_pid$
    cdpx_row = cdpx_findProcess.row
    if cdpx_row = 0
        cdpx_error$ = "Unknown process '" + cdpx_pid$ + "'."
    endif
    if cdpx_error$ = ""
        selectObject: cdpx_sourceID
        cdpx_sourceName$ = selected$ ("Sound")
        cdpx_inChannels = Get number of channels
        cdpx_inRate = Get sampling frequency
        cdpx_inDur = Get total duration
        cdpx_inSamples = Get number of samples
        @cdpx_cell: cdpx_procTable, cdpx_row, "display_name"
        cdpx_displayName$ = cdpx_cell.v$
        @cdpx_cell: cdpx_procTable, cdpx_row, "category"
        cdpx_category$ = cdpx_cell.v$
        @cdpx_cell: cdpx_procTable, cdpx_row, "executable"
        cdpx_exeName$ = cdpx_cell.v$ + cdpx_exeSuffix$
        cdpx_exePath$ = cdpx_engineDir$ + cdpx_sep$ + cdpx_exeName$
        # 'spectral' processes work on PVOC analysis files: the engine wraps
        # them in pvoc anal (before) and pvoc synth (after), with CDP's
        # default analysis settings. The user still sees Sound in, Sound out.
        cdpx_spectral = cdpx_t1_input_type$ [cdpx_row] = "spectral"
        cdpx_pvocPath$ = cdpx_engineDir$ + cdpx_sep$ + "pvoc" + cdpx_exeSuffix$
        @cdpx_cell: cdpx_procTable, cdpx_row, "subcommand"
        cdpx_subcommand$ = cdpx_cell.v$
        @cdpx_cell: cdpx_procTable, cdpx_row, "mode"
        cdpx_mode$ = cdpx_cell.v$
        @cdpx_cell: cdpx_procTable, cdpx_row, "output_channels"
        cdpx_outChannelsSpec$ = cdpx_cell.v$
        if not fileReadable (cdpx_exePath$)
            cdpx_error$ = "CDP executable not found in the bundled engine folder:" + newline$ + cdpx_exePath$ + newline$ + "The Explorer never uses a CDP installation elsewhere on this computer." + newline$ + "Reinstall the CDP folder of Praat AudioTools."
        elsif cdpx_spectral and not fileReadable (cdpx_pvocPath$)
            cdpx_error$ = "CDP executable not found in the bundled engine folder:" + newline$ + cdpx_pvocPath$ + newline$ + "Reinstall the CDP folder of Praat AudioTools."
        endif
    endif
    # DLLs declared in the registry must sit next to the executable
    if cdpx_error$ = ""
        @cdpx_cell: cdpx_procTable, cdpx_row, "dll_dependencies"
        .dlls$ = replace$ (cdpx_cell.v$, ",", " ", 0)
        if .dlls$ <> "" and windows
            @cdpx_tokenize: .dlls$
            for .i to cdpx_tokenize.n
                if not fileReadable (cdpx_engineDir$ + cdpx_sep$ + cdpx_tok$ [.i])
                    cdpx_error$ = "Missing runtime library for " + cdpx_exeName$ + ": " + cdpx_tok$ [.i] + newline$ + "Expected in: " + cdpx_engineDir$
                endif
            endfor
        endif
    endif
    # channel compatibility, before anything is written or run
    if cdpx_error$ = ""
        @cdpx_channelRange: cdpx_row
        cdpx_channelAction$ = "none"
        cdpx_procChannels = cdpx_inChannels
        # Automatic: a channel count the process accepts is kept; anything
        # else becomes an equal-weight mono mix of a copy (never the source).
        if cdpx_inChannels < cdpx_channelRange.min or cdpx_inChannels > cdpx_channelRange.max
            if cdpx_channelRange.min = 1
                selectObject: cdpx_sourceID
                cdpx_monoCopyID = Convert to mono
                Rename: "cdpx_mono_transfer"
                cdpx_channelAction$ = "mixed " + string$ (cdpx_inChannels) + " channels to mono (average); this process accepts " + cdpx_t1_input_channels$ [cdpx_row] + " channel(s)"
                cdpx_procChannels = 1
            else
                cdpx_error$ = "This CDP process needs at least " + string$ (cdpx_channelRange.min) + " channels; the selected Sound has " + string$ (cdpx_inChannels) + "."
            endif
        endif
    endif
    # parameter validation, build arguments and the object-name tag
    if cdpx_error$ = ""
        @cdpx_collectParams: cdpx_pid$
        cdpx_nParams = cdpx_collectParams.n
        cdpx_paramText$ = ""
        for .k to cdpx_nParams
            if cdpx_error$ = ""
                .row = cdpx_paramRow [.k]
                .label$ = cdpx_t2_label$ [.row]
                @cdpx_checkValue: .row, cdpx_value [.k]
                if cdpx_checkValue.msg$ <> ""
                    cdpx_error$ = "Invalid parameter '" + .label$ + "': " + cdpx_checkValue.msg$
                else
                    @cdpx_formatValue: .row, cdpx_value [.k]
                    cdpx_paramArg$ [.k] = cdpx_formatValue.arg$
                    cdpx_paramTag$ [.k] = cdpx_formatValue.tag$
                    cdpx_paramText$ = cdpx_paramText$ + "   " + .label$ + " = " + cdpx_formatValue.text$ + newline$
                endif
            endif
        endfor
        if cdpx_paramText$ = ""
            cdpx_paramText$ = "   (none)" + newline$
        endif
    endif
endproc

procedure cdpx_writeTemp
    createFolder: cdpx_workDir$
    .found = 0
    .try = 0
    while .found = 0 and .try < 50
        .try += 1
        cdpx_runID$ = "cdpx_" + string$ (randomInteger (100000000, 999999999))
        cdpx_inPath$ = cdpx_workDir$ + cdpx_sep$ + cdpx_runID$ + "_in.wav"
        cdpx_outPath$ = cdpx_workDir$ + cdpx_sep$ + cdpx_runID$ + "_out.wav"
        cdpx_anaIn$ = cdpx_workDir$ + cdpx_sep$ + cdpx_runID$ + "_in.ana"
        cdpx_anaOut$ = cdpx_workDir$ + cdpx_sep$ + cdpx_runID$ + "_out.ana"
        if not fileReadable (cdpx_inPath$) and not fileReadable (cdpx_outPath$)
            .found = 1
        endif
    endwhile
    if .found = 0
        cdpx_error$ = "Could not find a free temporary file name in " + cdpx_workDir$
    else
        if cdpx_monoCopyID <> 0
            selectObject: cdpx_monoCopyID
        else
            selectObject: cdpx_sourceID
        endif
        # The transfer file is 16-bit WAV (range -1..+1). A Sound that peaks
        # above 1 would be clipped irreversibly, so its COPY is attenuated
        # instead. The level is not restored afterwards: that is only valid
        # for linear processes; the exact attenuation is reported.
        .peak = Get absolute extremum: 0, 0, "None"
        cdpx_attenDb = 0
        if .peak = undefined
            cdpx_error$ = "The Sound contains undefined samples and cannot be written to a WAV file."
        elsif .peak > 1
            .g = 0.99 / .peak
            if cdpx_monoCopyID = 0
                cdpx_monoCopyID = Copy: "cdpx_transfer"
            endif
            selectObject: cdpx_monoCopyID
            Multiply: .g
            cdpx_attenDb = 20 * log10 (.g)
            cdpx_warning$ = cdpx_warning$ + "Input peaks at " + fixed$ (.peak, 3) + ", above the WAV range: the transfer copy was attenuated by " + fixed$ (-cdpx_attenDb, 2) + " dB (no clipping). The result is not re-amplified." + newline$
        endif
    endif
    if cdpx_error$ = ""
        Save as WAV file: cdpx_inPath$
        if not fileReadable (cdpx_inPath$)
            cdpx_error$ = "Could not write the temporary input file:" + newline$ + cdpx_inPath$
        endif
    endif
    # build the argument vector from the template
    if cdpx_error$ = ""
        @cdpx_cell: cdpx_procTable, cdpx_row, "argument_template"
        @cdpx_tokenize: cdpx_cell.v$
        cdpx_nArgs = 0
        cdpx_commandLine$ = """" + cdpx_exePath$ + """"
        for .i to cdpx_tokenize.n
            .tok$ = cdpx_tok$ [.i]
            .use = 1
            if .tok$ = "{input}" and cdpx_spectral
                .a$ = cdpx_anaIn$
            elsif .tok$ = "{output}" and cdpx_spectral
                .a$ = cdpx_anaOut$
            elsif .tok$ = "{input}"
                .a$ = cdpx_inPath$
            elsif .tok$ = "{output}"
                .a$ = cdpx_outPath$
            elsif .tok$ = "{subcommand}"
                .a$ = cdpx_subcommand$
            elsif .tok$ = "{mode}"
                .a$ = cdpx_mode$
            elsif index (.tok$, "{") > 0
                .brace = index (.tok$, "{")
                .pre$ = left$ (.tok$, .brace - 1)
                @cdpx_paramIndex: mid$ (.tok$, .brace + 1, length (.tok$) - .brace - 1)
                .a$ = .pre$ + cdpx_paramArg$ [cdpx_paramIndex.k]
                # an 'off' boolean switch is simply left out
                if .a$ = ""
                    .use = 0
                endif
            else
                .a$ = .tok$
            endif
            if .use
                cdpx_nArgs += 1
                cdpx_arg$ [cdpx_nArgs] = .a$
                if index (.a$, " ") > 0
                    cdpx_commandLine$ = cdpx_commandLine$ + " """ + .a$ + """"
                else
                    cdpx_commandLine$ = cdpx_commandLine$ + " " + .a$
                endif
            endif
        endfor
        if cdpx_spectral
            cdpx_commandLine$ = """" + cdpx_pvocPath$ + """ anal 1 <in.wav> <in.ana>  |  " + cdpx_commandLine$ + "  |  """ + cdpx_pvocPath$ + """ synth <out.ana> <out.wav>"
        endif
        # object name from name_tag
        @cdpx_cell: cdpx_procTable, cdpx_row, "name_tag"
        .tag$ = cdpx_cell.v$
        for .k to cdpx_nParams
            .row = cdpx_paramRow [.k]
            .id$ = cdpx_t2_param_id$ [.row]
            .tag$ = replace$ (.tag$, "{" + .id$ + "}", cdpx_paramTag$ [.k], 0)
        endfor
        .tag$ = replace$ (.tag$, "{mode}", cdpx_mode$, 0)
        .tag$ = replace$ (.tag$, "{subcommand}", cdpx_subcommand$, 0)
        cdpx_resultName$ = cdpx_sourceName$ + "_CDP_" + .tag$
    endif
endproc

procedure cdpx_queryVersion
    .v$ = runSubprocess$ (cdpx_exePath$, "--version")
    .v$ = replace_regex$ (.v$, "[\r\n]+", " ", 0)
    .v$ = replace_regex$ (.v$, "^ +| +$", "", 0)
    if .v$ = ""
        .v$ = "(no answer to --version)"
    endif
    cdpx_version$ = .v$ + " (self-reported by " + cdpx_exeName$ + ")"
endproc

procedure cdpx_execute
    # A refused run must not stop the script: with nocheck, Praat continues
    # when CDP exits with an error status. Success is judged by each step's
    # output file; when one is missing, one clear message is given.
    cdpx_cdpRefused = 0
    if cdpx_spectral
        # keep the process's own arguments, run the analysis first
        .nKeep = cdpx_nArgs
        for .i to .nKeep
            .keep$ [.i] = cdpx_arg$ [.i]
        endfor
        cdpx_arg$ [1] = "anal"
        cdpx_arg$ [2] = "1"
        cdpx_arg$ [3] = cdpx_inPath$
        cdpx_arg$ [4] = cdpx_anaIn$
        cdpx_nArgs = 4
        @cdpx_dispatch: cdpx_pvocPath$
        if cdpx_error$ = "" and not fileReadable (cdpx_anaIn$)
            cdpx_error$ = "CDP's spectral analysis (pvoc anal) failed for this Sound."
        endif
        cdpx_nArgs = .nKeep
        for .i to .nKeep
            cdpx_arg$ [.i] = .keep$ [.i]
        endfor
        if cdpx_error$ = ""
            @cdpx_dispatch: cdpx_exePath$
            if cdpx_error$ = "" and not fileReadable (cdpx_anaOut$)
                @cdpx_failMessage
            endif
        endif
        if cdpx_error$ = ""
            cdpx_arg$ [1] = "synth"
            cdpx_arg$ [2] = cdpx_anaOut$
            cdpx_arg$ [3] = cdpx_outPath$
            cdpx_nArgs = 3
            @cdpx_dispatch: cdpx_pvocPath$
            if cdpx_error$ = "" and not fileReadable (cdpx_outPath$)
                cdpx_error$ = "CDP's spectral resynthesis (pvoc synth) failed."
            endif
        endif
    else
        @cdpx_dispatch: cdpx_exePath$
        if cdpx_error$ = "" and not fileReadable (cdpx_outPath$)
            @cdpx_failMessage
        endif
    endif
    if cdpx_error$ <> ""
        cdpx_cdpRefused = 1
    endif
endproc

# Generic argument dispatcher. runSubprocess has a variadic argument list;
# Praat cannot expand an array into it, so one branch per argument count.
procedure cdpx_dispatch: .e$
    .n = cdpx_nArgs
    if .n = 1
        nocheck runSubprocess: .e$, cdpx_arg$ [1]
    elsif .n = 2
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2]
    elsif .n = 3
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3]
    elsif .n = 4
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4]
    elsif .n = 5
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5]
    elsif .n = 6
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6]
    elsif .n = 7
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7]
    elsif .n = 8
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8]
    elsif .n = 9
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8], cdpx_arg$ [9]
    elsif .n = 10
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8], cdpx_arg$ [9], cdpx_arg$ [10]
    elsif .n = 11
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8], cdpx_arg$ [9], cdpx_arg$ [10], cdpx_arg$ [11]
    elsif .n = 12
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8], cdpx_arg$ [9], cdpx_arg$ [10], cdpx_arg$ [11], cdpx_arg$ [12]
    elsif .n = 13
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8], cdpx_arg$ [9], cdpx_arg$ [10], cdpx_arg$ [11], cdpx_arg$ [12], cdpx_arg$ [13]
    elsif .n = 14
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8], cdpx_arg$ [9], cdpx_arg$ [10], cdpx_arg$ [11], cdpx_arg$ [12], cdpx_arg$ [13], cdpx_arg$ [14]
    elsif .n = 15
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8], cdpx_arg$ [9], cdpx_arg$ [10], cdpx_arg$ [11], cdpx_arg$ [12], cdpx_arg$ [13], cdpx_arg$ [14], cdpx_arg$ [15]
    elsif .n = 16
        nocheck runSubprocess: .e$, cdpx_arg$ [1], cdpx_arg$ [2], cdpx_arg$ [3], cdpx_arg$ [4], cdpx_arg$ [5], cdpx_arg$ [6], cdpx_arg$ [7], cdpx_arg$ [8], cdpx_arg$ [9], cdpx_arg$ [10], cdpx_arg$ [11], cdpx_arg$ [12], cdpx_arg$ [13], cdpx_arg$ [14], cdpx_arg$ [15], cdpx_arg$ [16]
    else
        cdpx_error$ = "Internal error: unsupported argument count " + string$ (.n) + "."
    endif
endproc

procedure cdpx_failMessage
    cdpx_error$ = "CDP could not process this Sound with these settings (" + cdpx_displayName$ + ")." + newline$ + "Check the values: some limits depend on the Sound, e.g. times must lie inside it."
endproc

procedure cdpx_importResult
    # Remember the current selection: a failed read leaves it unchanged.
    selectObject: cdpx_sourceID
    nocheck Read from file: cdpx_outPath$
    .ok = 0
    if numberOfSelected () = 1
        if numberOfSelected ("Sound") = 1
            .id = selected ("Sound")
            if .id <> cdpx_sourceID
                .ok = 1
            endif
        endif
    endif
    if .ok = 0
        @cdpx_failMessage
    else
        cdpx_resultID = .id
        cdpx_outChannels = Get number of channels
        cdpx_outRate = Get sampling frequency
        cdpx_outDur = Get total duration
        cdpx_outSamples = Get number of samples
        if cdpx_outChannelsSpec$ = "same"
            .expectCh = cdpx_procChannels
        else
            .expectCh = number (cdpx_outChannelsSpec$)
        endif
        .bad = Get absolute extremum: 0, 0, "None"
        if cdpx_outSamples < 1 or .bad = undefined
            @cdpx_failMessage
        elsif cdpx_outChannels <> .expectCh
            cdpx_error$ = "CDP output has " + string$ (cdpx_outChannels) + " channel(s); the registry expects " + string$ (.expectCh) + "."
        elsif cdpx_outRate <> cdpx_inRate
            cdpx_error$ = "CDP output sample rate " + string$ (cdpx_outRate) + " Hz differs from the input (" + string$ (cdpx_inRate) + " Hz)."
        endif
        if cdpx_error$ <> ""
            removeObject: cdpx_resultID
            cdpx_resultID = 0
        else
            selectObject: cdpx_resultID
            Rename: cdpx_resultName$
            cdpx_resultName$ = selected$ ("Sound")
        endif
    endif
endproc

procedure cdpx_cleanup
    deleteFile: cdpx_inPath$
    deleteFile: cdpx_outPath$
    deleteFile: cdpx_anaIn$
    deleteFile: cdpx_anaOut$
    cdpx_report$ = "=== CDP Process Explorer v" + cdpx_engineVersion$ + " ===" + newline$
    cdpx_report$ = cdpx_report$ + "New Sound      : " + cdpx_resultName$ + "  (" + string$ (cdpx_outChannels) + " ch, " + string$ (cdpx_outRate) + " Hz, " + fixed$ (cdpx_outDur, 3) + " s)" + newline$
    cdpx_report$ = cdpx_report$ + "Source Sound   : " + cdpx_sourceName$ + "  (" + string$ (cdpx_inChannels) + " ch, " + fixed$ (cdpx_inDur, 3) + " s, unchanged)" + newline$
    cdpx_report$ = cdpx_report$ + "Process        : " + cdpx_category$ + " > " + cdpx_displayName$ + "  [" + cdpx_pid$ + "]" + newline$
    cdpx_report$ = cdpx_report$ + "CDP program    : " + cdpx_exeName$ + " " + cdpx_subcommand$ + ", mode " + cdpx_mode$ + newline$
    cdpx_report$ = cdpx_report$ + "CDP version    : " + cdpx_version$ + newline$
    cdpx_report$ = cdpx_report$ + "Engine folder  : " + cdpx_engineDir$ + newline$
    cdpx_report$ = cdpx_report$ + "Channel action : " + cdpx_channelAction$ + newline$
    cdpx_report$ = cdpx_report$ + "Parameters     :" + newline$ + cdpx_paramText$
    cdpx_report$ = cdpx_report$ + "Command line   : " + cdpx_commandLine$ + newline$
    if cdpx_warning$ <> ""
        cdpx_report$ = cdpx_report$ + "Warnings       :" + newline$ + cdpx_warning$
    endif
endproc

procedure cdpx_failureReport
    if cdpx_inPath$ <> ""
        deleteFile: cdpx_inPath$
        deleteFile: cdpx_outPath$
        deleteFile: cdpx_anaIn$
        deleteFile: cdpx_anaOut$
    endif
    cdpx_report$ = "=== CDP Process Explorer v" + cdpx_engineVersion$ + " - NOT COMPLETED ===" + newline$ + cdpx_error$ + newline$
endproc

# Kept for compatibility: the registry holds no Praat objects any more.
procedure cdpx_release
endproc
