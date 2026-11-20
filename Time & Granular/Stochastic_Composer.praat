# ============================================================
# Praat AudioTools - Stochastic_Composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Human-guided composition by chance. The script proposes recordings
#   at random from a corpus folder; the composer listens and ACCEPTS or
#   REJECTS each proposal, and FINISHES whenever the piece is complete.
#   The computer proposes. The composer listens, decides, and
#   determines the form.
#
#   Nothing is analysed, classified or scored. There is no similarity
#   measure, no feature extraction and no musical category: the only
#   selection mechanism is a uniform random draw over the corpus, and
#   the only musical intelligence is the composer's ear. The sequence,
#   the duration and the ending all come from the composer's decisions.
#
# Pipeline:
#   1. Scan the corpus folder. Every file with an audio extension is
#      test-read once; unreadable, empty and non-audio files are skipped
#      and listed in the Info window. Only references (path, duration,
#      channels, sample rate) are kept, not the audio.
#   2. Fix one internal format for the whole session: the HIGHEST sample
#      rate found (nothing is downsampled) and stereo if any file has
#      two or more channels (mono files are duplicated to both sides;
#      files with more than two channels are mixed to mono first).
#   3. Propose a recording (uniform random draw). Never the recording
#      just rejected, and never the last accepted one, while any other
#      choice exists. Small corpora: if those two are the only files
#      (or the only file), the last accepted one may be proposed again
#      first, then the rejected one; a proposal is always made, so
#      rejecting never loops or stalls. After UNDO, a pending candidate
#      that would repeat the new last recording is withdrawn (tracked,
#      not counted as a rejection) and a new one is drawn.
#   4. Audition in the Demo window: the candidate alone, LOCAL (last
#      accepted -> candidate), GLOBAL (whole composition -> candidate),
#      or the composition without the candidate. Playback is
#      asynchronous, so the window stays responsive and STOP works.
#   5. ACCEPT appends the candidate, REJECT discards this proposal only
#      (the file stays eligible for later positions), UNDO LAST removes
#      the most recent acceptance.
#   6. FINISH keeps the exact accepted sequence as a single Sound in
#      Praat Objects. It never exports a WAV or log automatically.
#
# Audio handling:
#   - Source files are only ever read, never written.
#   - Direct concatenation by default: no crossfade, no normalization,
#     no pitch or time change. Resampling (precision 50) happens only
#     when a file's rate differs from the session rate.
#   - Transition_gap_ms inserts exact digital silence between accepted
#     recordings (rounded to whole samples). Edge_fade_ms is OFF by
#     default; when set, each recording gets a raised-cosine fade in and
#     out of that length (capped at half the recording), applied
#     identically in every audition and in the final composition.
#   - The accepted sequence is stored as file references. One rendered
#     copy of the composition is cached for Global audition and finishing;
#     it is extended in place on ACCEPT and rebuilt from the files only
#     after UNDO.
#
# Safety of the accepted sequence:
#   - A temporary Table records the accepted sequence during the session.
#     FINISH leaves the completed Sound ready to play. CLOSE (or confirmed
#     QUIT) cleans the script's transient Praat objects and leaves only
#     Sound Stochastic_Composition.
#   - The source audio files are read-only, and the script does not write
#     any files to the disk. To save a result later, use Praat's normal
#     File > Save commands manually.
#   - CLOSING THE DEMO WINDOW with its operating-system close box can
#     stop Praat scripting before the cleanup handler runs. Use QUIT (Q)
#     or CLOSE in the Demo UI to ensure a clean Objects window. The
#     previously documented Praat 6.x restart caveat still applies.

# Interaction (Demo window):
#   Mouse: the buttons. Keys: A accept, R reject, U undo, F finish,
#   C candidate, L local, G global, P composition, S stop, Q quit.
#
# Requires:
#   Praat with its GUI (the Demo window does not exist in praat --run).
#   Verified on Praat 6.1.38, 6.4.06 and 7.0 (Linux builds). Pure Praat:
#   no Python, no external programs.
#
# Changelog v1.1 (2026):
#   - In-memory result only; removed disk export and log.
#   - Normal CLOSE/QUIT cleanup leaves one composition Sound.
# Changelog v1.0 (2026):
#   - Initial release.
# ============================================================

form Stochastic Composer v1.1
    comment Corpus folder (leave empty to choose it in a dialog)
    sentence Corpus_folder
    optionmenu Audition_mode: 1
        option Local (last accepted -> candidate)
        option Global (whole composition -> candidate)
    boolean Auto_audition 1
    comment Transition gap and edge fade in ms (0 = direct concatenation)
    real Transition_gap_ms 0
    real Edge_fade_ms 0
    integer Random_seed 0
    boolean Play_result 1
endform

####################################################################
# PARAMETERS AND VALIDATION
####################################################################

if transition_gap_ms < 0
    exitScript: "Transition_gap_ms cannot be negative (got ", transition_gap_ms, ")."
endif
if edge_fade_ms < 0
    exitScript: "Edge_fade_ms cannot be negative (got ", edge_fade_ms, ")."
endif
if random_seed < 0
    exitScript: "Random_seed must be 0 (unpredictable) or a positive integer."
endif

corpus$ = corpus_folder$
# strip surrounding quotes and spaces (pasted Windows paths often have them)
corpus$ = replace_regex$ (corpus$, "^[ \t""]+", "", 1)
corpus$ = replace_regex$ (corpus$, "[ \t""]+$", "", 1)
if corpus$ = ""
    corpus$ = chooseFolder$ ("Choose the corpus folder")
    if corpus$ = ""
        exitScript: "No corpus folder was chosen."
    endif
endif
# one trailing separator off, so corpus$ + "/" + name is always valid
corpus$ = replace_regex$ (corpus$, "[/\\]+$", "", 1)

gapSec = transition_gap_ms / 1000
fadeSec = edge_fade_ms / 1000

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$ (random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

# Drawing target: "demo " sends every drawing command to the Demo window.
# (Test harnesses set it to "" to render the same layout in the Picture
# window; the script itself always uses the Demo window.)
dp$ = "demo "
vx1 = 0
vx2 = 100
vy1 = 0
vy2 = 100

clearinfo
writeInfoLine: "=================================================="
appendInfoLine: "  STOCHASTIC COMPOSER v1.0"
appendInfoLine: "  Human-Guided Composition by Chance"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Corpus folder: ", corpus$
appendInfoLine: "Transition gap: ", fixed$ (transition_gap_ms, 1), " ms | Edge fade: ",
    ... fixed$ (edge_fade_ms, 1), " ms | Seed: ", seedLabel$

####################################################################
# SEQUENCE RECORD (persistent Table; also the read-failure anchor)
####################################################################

seqTable = Create Table with column names: "StochasticComposer_sequence", 0,
    ... "position file original_duration_s start_s end_s"

####################################################################
# CORPUS SCAN
####################################################################

@scanCorpus

if nCorpus = 0
    removeObject: seqTable
    if scanFolderOk = 0
        exitScript: "The corpus folder could not be opened:" + newline$ + corpus$
    elsif scanCandidates = 0
        exitScript: "No audio files were found in:" + newline$ + corpus$
            ... + newline$ + "(checked extensions: " + audioExtList$ + ")"
    else
        exitScript: "None of the " + string$ (scanCandidates) + " audio file(s) in the folder could be read by Praat:"
            ... + newline$ + corpus$
    endif
endif

appendInfoLine: ""
appendInfoLine: "Corpus: ", nCorpus, " usable recording(s), ", nSkipped, " skipped"
for i to min (nSkipped, 20)
    appendInfoLine: "  skipped: ", skipName$[i], "  (", skipWhy$[i], ")"
endfor
if nSkipped > 20
    appendInfoLine: "  ... and ", nSkipped - 20, " more"
endif
appendInfoLine: "Session format: ", internalSr, " Hz, ", internalCh, " channel(s)"
if nResampled > 0
    appendInfoLine: "  ", nResampled, " recording(s) will be resampled to ", internalSr, " Hz"
endif
if nMultiCh > 0
    appendInfoLine: "  ", nMultiCh, " recording(s) with more than two channels will be mixed to mono"
endif

gapSamples = round (gapSec * internalSr)
gapSec = gapSamples / internalSr

####################################################################
# SESSION STATE
####################################################################

nUsable = nCorpus
nAcc = 0
nProposals = 0
nRejected = 0
nUndos = 0
nHist = 0
candIdx = 0
candSnd = 0
candSamples = 0
lastRejected = 0
compSnd = 0
playBuf = 0
lastPlayed$ = "nothing yet"
quitArmed = 0
state$ = "compose"
preserved = 0
if auto_audition
    autoMode = audition_mode
else
    autoMode = 0
endif
message$ = "Listen to the first proposal, then ACCEPT or REJECT it."
lastEventWasDecision = 0
titleSet = 0

@proposeCandidate
@autoAudition

####################################################################
# EVENT LOOP
####################################################################

running = 1
while running
    @drawUI
    @waitForAction
    action$ = waitForAction.action$
    if action$ <> ""
        @handleAction: action$
    endif
endwhile

@finalCleanup

####################################################################
# PROCEDURES — corpus
####################################################################

procedure scanCorpus
    audioExtList$ = "wav wave aif aiff aifc flac mp3 ogg opus au snd nist sph"
    .exts$ = " " + audioExtList$ + " "
    nCorpus = 0
    nSkipped = 0
    scanCandidates = 0
    nResampled = 0
    nMultiCh = 0
    internalSr = 0
    internalCh = 1

    scanFolderOk = 1
    selectObject: seqTable
    nocheck Create Strings as file list: "sc_filelist", corpus$ + "/*"
    if selected () = seqTable
        # the folder does not exist or cannot be opened
        scanFolderOk = 0
        .list = Create Strings as tokens: "", " "
    else
        .list = selected ()
    endif
    selectObject: .list
    .n = Get number of strings
    for .k to .n
        selectObject: .list
        .name$ = Get string: .k
        .dot = rindex (.name$, ".")
        .ext$ = ""
        if .dot > 0
            .ext$ = replace_regex$ (right$ (.name$, length (.name$) - .dot), "([A-Z])", "\L\1", 0)
        endif
        # hidden files (macOS "._name.wav" resource forks etc.) are not audio
        if left$ (.name$, 1) <> "." and .ext$ <> "" and index (.exts$, " " + .ext$ + " ") > 0
            scanCandidates += 1
            .path$ = corpus$ + "/" + .name$
            selectObject: seqTable
            nocheck Read from file: .path$
            .ok = 0
            if numberOfSelected () = 1
                if selected () <> seqTable
                    .obj = selected ()
                    if left$ (selected$ (), 6) = "Sound "
                        .ok = 1
                    else
                        removeObject: .obj
                    endif
                endif
            elsif numberOfSelected () > 1
                Remove
            endif
            if .ok = 1
                .ns = Get number of samples
                .dur = Get total duration
                .ch = Get number of channels
                .sr = Get sampling frequency
                removeObject: .obj
                if .ns < 1
                    nSkipped += 1
                    skipName$[nSkipped] = .name$
                    skipWhy$[nSkipped] = "no samples"
                else
                    nCorpus += 1
                    cPath$[nCorpus] = .path$
                    cName$[nCorpus] = .name$
                    cDur[nCorpus] = .dur
                    cCh[nCorpus] = .ch
                    cSr[nCorpus] = .sr
                    cOk[nCorpus] = 1
                    if .sr > internalSr
                        internalSr = .sr
                    endif
                    if .ch >= 2
                        internalCh = 2
                    endif
                    if .ch > 2
                        nMultiCh += 1
                    endif
                endif
            else
                nSkipped += 1
                skipName$[nSkipped] = .name$
                skipWhy$[nSkipped] = "Praat cannot read it"
            endif
        endif
    endfor
    removeObject: .list

    for .i to nCorpus
        if cSr[.i] <> internalSr
            nResampled += 1
        endif
    endfor
endproc

# Read one corpus file and bring it to the session format. Returns the
# new Sound's id, or 0 if the file can no longer be read.
procedure prepareClip: .i
    prepareClip.result = 0
    selectObject: seqTable
    nocheck Read from file: cPath$[.i]
    .s = 0
    if numberOfSelected () = 1
        if selected () <> seqTable
            .s = selected ()
            if left$ (selected$ (), 6) <> "Sound "
                removeObject: .s
                .s = 0
            endif
        endif
    elsif numberOfSelected () > 1
        Remove
    endif
    if .s > 0
        selectObject: .s
        .nch = Get number of channels
        if .nch > 2
            .t = Convert to mono
            removeObject: .s
            .s = .t
            .nch = 1
        endif
        if internalCh = 2 and .nch = 1
            selectObject: .s
            .t = Convert to stereo
            removeObject: .s
            .s = .t
        endif
        selectObject: .s
        .sr = Get sampling frequency
        if .sr <> internalSr
            .t = Resample: internalSr, 50
            removeObject: .s
            .s = .t
        endif
        if fadeSec > 0
            selectObject: .s
            .d = Get total duration
            .f = min (fadeSec, .d / 2)
            if .f > 0
                .f$ = fixed$ (.f, 9)
                Formula: "if x - xmin < " + .f$ + " then self * (0.5 - 0.5 * cos (pi * (x - xmin) / " + .f$
                    ... + ")) else if xmax - x < " + .f$ + " then self * (0.5 - 0.5 * cos (pi * (xmax - x) / "
                    ... + .f$ + ")) else self fi fi"
            endif
        endif
        selectObject: .s
        Rename: "SC_clip"
        prepareClip.result = .s
    endif
endproc

# Uniform random draw over usable recordings. Excludes the recording
# just rejected and the last accepted one while any other choice
# exists; if that leaves nothing, the last accepted one is allowed
# again; if that still leaves nothing, any usable recording.
procedure drawIndex
    drawIndex.result = 0
    .last = 0
    if nAcc > 0
        .last = accIdx[nAcc]
    endif
    for .pass to 3
        if drawIndex.result = 0
            .count = 0
            for .i to nCorpus
                @eligible: .i, .pass, .last
                .count += eligible.result
            endfor
            if .count > 0
                .r = randomInteger (1, .count)
                .c = 0
                for .i to nCorpus
                    if drawIndex.result = 0
                        @eligible: .i, .pass, .last
                        .c += eligible.result
                        if .c = .r and eligible.result = 1
                            drawIndex.result = .i
                        endif
                    endif
                endfor
            endif
        endif
    endfor
endproc

procedure eligible: .i, .pass, .last
    eligible.result = cOk[.i]
    if eligible.result = 1
        if .pass = 1 and (.i = lastRejected or .i = .last)
            eligible.result = 0
        elsif .pass = 2 and .i = lastRejected
            eligible.result = 0
        endif
    endif
endproc

procedure proposeCandidate
    if candSnd > 0
        removeObject: candSnd
    endif
    candSnd = 0
    candIdx = 0
    .done = 0
    while .done = 0
        @drawIndex
        .pick = drawIndex.result
        if .pick = 0
            .done = 1
        else
            @prepareClip: .pick
            if prepareClip.result = 0
                # The file was readable at the scan but is not now
                # (moved, deleted, locked): drop it from the pool.
                cOk[.pick] = 0
                nUsable -= 1
                message$ = "Could not read " + cName$[.pick] + " any more; it was removed from the pool."
                appendInfoLine: "  ! ", cName$[.pick], " could not be read any more; removed from the pool"
            else
                candIdx = .pick
                candSnd = prepareClip.result
                selectObject: candSnd
                candSamples = Get number of samples
                nProposals += 1
                .done = 1
            endif
        endif
    endwhile
    if candIdx = 0
        message$ = "No readable recording is left to propose."
        if nAcc > 0
            message$ = message$ + " You can still FINISH."
        endif
    endif
endproc

####################################################################
# PROCEDURES — composition
####################################################################

procedure compositionSamples
    compositionSamples.result = 0
    for .k to nAcc
        compositionSamples.result += accSamples[.k]
    endfor
    if nAcc > 1
        compositionSamples.result += (nAcc - 1) * gapSamples
    endif
endproc

procedure makeGap
    makeGap.result = Create Sound from formula: "SC_gap", internalCh, 0, gapSamples / internalSr, internalSr, "0"
endproc

# Render the accepted sequence from the files, once, into compSnd.
# Every part is created in sequence order, so the object-list order
# that Concatenate follows is the composition order.
procedure renderComposition
    renderComposition.ok = 1
    if compSnd = 0 and nAcc > 0
        .nParts = 0
        .failed = 0
        for .k to nAcc
            if .failed = 0
                @prepareClip: accIdx[.k]
                if prepareClip.result = 0
                    .failed = .k
                else
                    .nParts += 1
                    .part[.nParts] = prepareClip.result
                    if .k < nAcc and gapSamples > 0
                        @makeGap
                        .nParts += 1
                        .part[.nParts] = makeGap.result
                    endif
                endif
            endif
        endfor
        if .failed > 0
            for .p to .nParts
                removeObject: .part[.p]
            endfor
            renderComposition.ok = 0
            message$ = "Could not read " + cName$[accIdx[.failed]] + " (position " + string$ (.failed)
                ... + "). The sequence is kept; restore the file to render it."
        else
            if .nParts = 1
                compSnd = .part[1]
            else
                selectObject: .part[1]
                for .p from 2 to .nParts
                    plusObject: .part[.p]
                endfor
                compSnd = Concatenate
                for .p to .nParts
                    removeObject: .part[.p]
                endfor
            endif
            selectObject: compSnd
            Rename: "SC_composition"
        endif
    endif
endproc

####################################################################
# PROCEDURES — decisions
####################################################################

procedure addHistory: .file, .decision$, .pos
    nHist += 1
    histProposal[nHist] = nProposals
    histFile[nHist] = .file
    histDecision$[nHist] = .decision$
    histPos[nHist] = .pos
endproc

procedure doAccept
    if candIdx > 0
        @compositionSamples
        .startSamp = compositionSamples.result
        if nAcc > 0
            .startSamp += gapSamples
        endif
        nAcc += 1
        accIdx[nAcc] = candIdx
        accSamples[nAcc] = candSamples
        .start = .startSamp / internalSr
        .end = (.startSamp + candSamples) / internalSr

        selectObject: seqTable
        Append row
        Set numeric value: nAcc, "position", nAcc
        Set string value: nAcc, "file", cName$[candIdx]
        Set numeric value: nAcc, "original_duration_s", cDur[candIdx]
        Set numeric value: nAcc, "start_s", .start
        Set numeric value: nAcc, "end_s", .end

        # Extend the cached composition in place: cache (older), gap and
        # candidate copy (both created now) are in object-list order.
        if compSnd > 0
            if gapSamples > 0
                @makeGap
                .g = makeGap.result
            else
                .g = 0
            endif
            selectObject: candSnd
            .cc = Copy: "SC_clip"
            selectObject: compSnd
            if .g > 0
                plusObject: .g
            endif
            plusObject: .cc
            .new = Concatenate
            removeObject: compSnd, .cc
            if .g > 0
                removeObject: .g
            endif
            compSnd = .new
            selectObject: compSnd
            Rename: "SC_composition"
        elsif nAcc = 1
            selectObject: candSnd
            compSnd = Copy: "SC_composition"
        endif

        @addHistory: candIdx, "ACCEPT", nAcc
        @fmt: .start
        message$ = "Accepted " + cName$[candIdx] + " at position " + string$ (nAcc) + " (starts at " + fmt.result$ + ")."
        lastRejected = 0
        @proposeCandidate
        @autoAudition
    endif
endproc

procedure doReject
    if candIdx > 0
        @addHistory: candIdx, "REJECT", 0
        nRejected += 1
        lastRejected = candIdx
        message$ = "Rejected " + cName$[candIdx] + ". It stays available for later positions."
        @proposeCandidate
        @autoAudition
    endif
endproc

procedure doUndo
    if nAcc = 0
        message$ = "Nothing to undo: the composition is empty."
    else
        .f = accIdx[nAcc]
        @addHistory: .f, "UNDO", nAcc
        if nAcc > 1
            selectObject: seqTable
            Remove row: nAcc
        else
            # a Table cannot remove its only row: replace it by an empty one
            .t = Create Table with column names: "StochasticComposer_sequence", 0,
                ... "position file original_duration_s start_s end_s"
            removeObject: seqTable
            seqTable = .t
        endif
        nAcc -= 1
        nUndos += 1
        if compSnd > 0
            removeObject: compSnd
            compSnd = 0
        endif
        message$ = "Removed " + cName$[.f] + " from position " + string$ (nAcc + 1)
            ... + ". The pending candidate is unchanged."
        # The pending candidate was drawn against the OLD last recording.
        # If it is the NEW last recording, accepting it would repeat a
        # recording immediately, which the draw avoids whenever an
        # alternative exists: withdraw it (not a rejection) and draw again.
        if nAcc > 0 and candIdx > 0
            if candIdx = accIdx[nAcc]
                .alt = 0
                for .i to nCorpus
                    if cOk[.i] and .i <> candIdx
                        .alt = 1
                    endif
                endfor
                if .alt
                    @addHistory: candIdx, "WITHDRAWN_AFTER_UNDO", 0
                    @proposeCandidate
                    message$ = "Removed " + cName$[.f] + " from position " + string$ (nAcc + 1)
                        ... + ". The pending candidate was the new last recording, so a new one was drawn."
                endif
            endif
        endif
    endif
endproc

####################################################################
# PROCEDURES — playback
####################################################################

# Start asynchronous playback of .snd. Praat stops the sound that is
# playing before it starts a new one, so the previous buffer can be
# removed once the new one has started.
procedure startPlayback: .snd, .label$
    selectObject: .snd
    asynchronous Play
    if playBuf > 0 and playBuf <> .snd
        removeObject: playBuf
    endif
    playBuf = .snd
    lastPlayed$ = .label$
endproc

# STOP: replace whatever is playing by 1 ms of silence.
procedure stopPlayback
    if playBuf > 0
        .z = Create Sound from formula: "SC_silence", 1, 0, 0.001, max (internalSr, 8000), "0"
        @startPlayback: .z, "stopped"
    endif
endproc

procedure playCandidate
    if candIdx > 0
        selectObject: candSnd
        .b = Copy: "SC_play_candidate"
        @startPlayback: .b, "Candidate"
    endif
endproc

procedure playLocal
    if candIdx > 0
        if nAcc = 0
            selectObject: candSnd
            .b = Copy: "SC_play_local"
        else
            @prepareClip: accIdx[nAcc]
            .a = prepareClip.result
            if .a = 0
                message$ = "Could not read " + cName$[accIdx[nAcc]] + " for the local audition."
                .b = 0
            else
                .g = 0
                if gapSamples > 0
                    @makeGap
                    .g = makeGap.result
                endif
                selectObject: candSnd
                .cc = Copy: "SC_clip"
                selectObject: .a
                if .g > 0
                    plusObject: .g
                endif
                plusObject: .cc
                .b = Concatenate
                removeObject: .a, .cc
                if .g > 0
                    removeObject: .g
                endif
            endif
        endif
        if .b > 0
            selectObject: .b
            Rename: "SC_play_local"
            @startPlayback: .b, "Local"
        endif
    endif
endproc

procedure playGlobal
    if candIdx > 0
        if nAcc = 0
            selectObject: candSnd
            .b = Copy: "SC_play_global"
            @startPlayback: .b, "Global"
        else
            @renderComposition
            if renderComposition.ok
                .g = 0
                if gapSamples > 0
                    @makeGap
                    .g = makeGap.result
                endif
                selectObject: candSnd
                .cc = Copy: "SC_clip"
                selectObject: compSnd
                if .g > 0
                    plusObject: .g
                endif
                plusObject: .cc
                .b = Concatenate
                Rename: "SC_play_global"
                removeObject: .cc
                if .g > 0
                    removeObject: .g
                endif
                @startPlayback: .b, "Global"
            endif
        endif
    endif
endproc

procedure playComposition
    if nAcc > 0
        @renderComposition
        if renderComposition.ok
            selectObject: compSnd
            .b = Copy: "SC_play_composition"
            @startPlayback: .b, "Composition"
        endif
    endif
endproc

procedure autoAudition
    if state$ = "compose" and candIdx > 0
        if autoMode = 1
            @playLocal
        elsif autoMode = 2
            @playGlobal
        endif
    endif
endproc

####################################################################
# PROCEDURES — finish and quit (no disk output)
####################################################################

procedure doFinish
    if nAcc = 0
        message$ = "Accept at least one recording before FINISH."
    else
        @stopPlayback
        @renderComposition
        if renderComposition.ok
            state$ = "finished"
            if candSnd > 0
                removeObject: candSnd
                candSnd = 0
                candIdx = 0
            endif
            selectObject: compSnd
            Rename: "Stochastic_Composition"
            message$ = "Composition complete. The result is in Praat Objects; PLAY or CLOSE."
            @reportFinal
            if play_result
                @playComposition
            endif
        endif
    endif
endproc

procedure reportFinal
    @compositionSamples
    appendInfoLine: ""
    appendInfoLine: "=== Composition complete (Praat Objects only) ==="
    appendInfoLine: "Sound: Stochastic_Composition (no WAV or log written to disk)"
    appendInfoLine: "Accepted: ", nAcc, " | Proposals: ", nProposals, " | Rejected: ", nRejected,
        ... " | Undos: ", nUndos
    @fmt: compositionSamples.result / internalSr
    appendInfoLine: "Duration: ", fmt.result$, " (",
        ... fixed$ (compositionSamples.result / internalSr, 3), " s)"
    appendInfoLine: "Seed: ", seedLabel$
    appendInfoLine: "Use CLOSE in the Demo window to remove temporary Praat objects."
endproc

procedure doQuit: .confirmed
    if nAcc = 0 or .confirmed
        running = 0
        if nAcc > 0 and state$ = "compose"
            preserved = 1
        endif
    else
        quitArmed = 1
        message$ = "Quit the session? The composition Sound will remain in Praat Objects. Click QUIT again to confirm."
    endif
endproc

procedure finalCleanup
    # Stop playback before deleting the temporary buffer.
    if playBuf > 0
        .z = Create Sound from formula: "SC_silence", 1, 0, 0.001, max (internalSr, 8000), "0"
        selectObject: .z
        asynchronous Play
        removeObject: playBuf
        playBuf = .z
    endif
    if candSnd > 0
        removeObject: candSnd
        candSnd = 0
    endif
    if state$ = "finished"
        selectObject: compSnd
        Rename: "Stochastic_Composition"
    elsif preserved
        @renderComposition
        appendInfoLine: ""
        appendInfoLine: "=== Composition left in Praat Objects ==="
        if compSnd > 0
            selectObject: compSnd
            Rename: "Stochastic_Composition"
            appendInfoLine: "Sound Stochastic_Composition contains ", nAcc, " accepted recordings."
        else
            appendInfoLine: "The source audio for an accepted clip is unavailable; no result could be rendered."
        endif
    else
        if compSnd > 0
            removeObject: compSnd
            compSnd = 0
        endif
        appendInfoLine: ""
        appendInfoLine: "Cancelled before anything was accepted. No result kept."
    endif
    if seqTable > 0
        removeObject: seqTable
        seqTable = 0
    endif
    if playBuf > 0
        removeObject: playBuf
        playBuf = 0
    endif
    random_initializeSafelyAndUnpredictably ()
    if compSnd > 0 and (state$ = "finished" or preserved)
        selectObject: compSnd
    endif
endproc

####################################################################
# PROCEDURES — input
####################################################################

procedure waitForAction
    waitForAction.action$ = ""
    .alive = demoWaitForInput ()
    if .alive = 0
        waitForAction.action$ = "windowclosed"
    elsif demoClicked ()
        .x = demoX ()
        .y = demoY ()
        for .b to nButtons
            if btnOn[.b] and .x >= btnX1[.b] and .x <= btnX2[.b] and .y >= btnY1[.b] and .y <= btnY2[.b]
                waitForAction.action$ = btnId$[.b]
            endif
        endfor
    elsif demoKeyPressed ()
        .k$ = replace_regex$ (demoKey$ (), "([A-Z])", "\L\1", 0)
        if .k$ = "a"
            waitForAction.action$ = "accept"
        elsif .k$ = "r"
            waitForAction.action$ = "reject"
        elsif .k$ = "u"
            waitForAction.action$ = "undo"
        elsif .k$ = "f"
            waitForAction.action$ = "finish"
        elsif .k$ = "c"
            waitForAction.action$ = "candidate"
        elsif .k$ = "l"
            waitForAction.action$ = "local"
        elsif .k$ = "g"
            waitForAction.action$ = "global"
        elsif .k$ = "p"
            waitForAction.action$ = "composition"
        elsif .k$ = "s"
            waitForAction.action$ = "stop"
        elsif .k$ = "q"
            if state$ = "finished"
                waitForAction.action$ = "close"
            else
                waitForAction.action$ = "quit"
            endif
        endif
        # a key only counts when its button is currently enabled
        .allowed = 0
        for .b to nButtons
            if btnId$[.b] = waitForAction.action$ and btnOn[.b]
                .allowed = 1
            endif
        endfor
        if .allowed = 0
            waitForAction.action$ = ""
        endif
    endif
endproc

procedure handleAction: .a$
    # Debounce: a decision that follows another decision within 0.3 s is
    # a double click, not a second decision about the NEXT proposal.
    .dt = stopwatch
    .isDecision = (.a$ = "accept") or (.a$ = "reject") or (.a$ = "undo") or (.a$ = "finish")
    if .isDecision and lastEventWasDecision and .dt < 0.3
        .a$ = ""
    endif
    if .a$ <> ""
        lastEventWasDecision = .isDecision
    endif
    if .a$ <> "quit"
        quitArmed = 0
    endif

    if .a$ = "accept"
        @doAccept
    elsif .a$ = "reject"
        @doReject
    elsif .a$ = "undo"
        @doUndo
    elsif .a$ = "finish"
        @doFinish
    elsif .a$ = "candidate"
        @playCandidate
    elsif .a$ = "local"
        @playLocal
    elsif .a$ = "global"
        @playGlobal
    elsif .a$ = "composition"
        @playComposition
    elsif .a$ = "stop"
        @stopPlayback
    elsif .a$ = "mode0"
        autoMode = 0
        message$ = "Auto-audition off: new proposals are not played automatically."
    elsif .a$ = "mode1"
        autoMode = 1
        message$ = "Auto-audition: each new proposal plays LOCAL (last accepted -> candidate)."
    elsif .a$ = "mode2"
        autoMode = 2
        message$ = "Auto-audition: each new proposal plays GLOBAL (whole composition -> candidate)."
    elsif .a$ = "quit"
        @doQuit: quitArmed
    elsif .a$ = "close"
        running = 0
    elsif .a$ = "windowclosed"
        @doQuit: 1
    endif
endproc

####################################################################
# PROCEDURES — drawing (Demo window, AudioTools style)
####################################################################

# Every primitive re-selects the full inner viewport and axes first: a
# font change or a Text call can otherwise leave the drawing frame on
# the outer viewport and shift what follows.
procedure fr
    'dp$'Select inner viewport: vx1, vx2, vy1, vy2
    'dp$'Axes: 0, 100, 0, 100
endproc

procedure rect: .c$, .x1, .x2, .y1, .y2
    @fr
    'dp$'Paint rectangle: .c$, .x1, .x2, .y1, .y2
endproc

procedure frame: .c$, .x1, .x2, .y1, .y2, .lw
    @fr
    'dp$'Colour: .c$
    'dp$'Line width: .lw
    'dp$'Draw rectangle: .x1, .x2, .y1, .y2
    'dp$'Line width: 1
endproc

procedure hline: .c$, .x1, .x2, .y, .lw
    @fr
    'dp$'Colour: .c$
    'dp$'Line width: .lw
    'dp$'Draw line: .x1, .y, .x2, .y
    'dp$'Line width: 1
endproc

procedure vline: .c$, .x, .y1, .y2, .lw
    @fr
    'dp$'Colour: .c$
    'dp$'Line width: .lw
    'dp$'Draw line: .x, .y1, .x, .y2
    'dp$'Line width: 1
endproc

procedure txt: .x, .h$, .y, .size, .c$, .s$
    'dp$'Font size: .size
    @fr
    'dp$'Colour: .c$
    'dp$'Text: .x, .h$, .y, "half", .s$
endproc

# Picture-text escaping for file names (_ ^ % # \ are markup), with
# truncation BEFORE escaping so the visible length is what was asked.
procedure clean: .s$, .max
    if length (.s$) > .max
        .s$ = left$ (.s$, .max - 1) + "…"
    endif
    .s$ = replace$ (.s$, "\", "\bs", 0)
    .s$ = replace$ (.s$, "_", "\_ ", 0)
    .s$ = replace$ (.s$, "%", "\% ", 0)
    .s$ = replace$ (.s$, "#", "\# ", 0)
    .s$ = replace$ (.s$, "^", "\^ ", 0)
    clean.result$ = .s$
endproc

procedure fmt: .t
    @fmtDec: .t, 1
    fmt.result$ = fmtDec.result$
endproc

# m:ss.d with .dec decimals (h:mm:ss.d from one hour on)
procedure fmtDec: .t, .dec
    if .t < 0
        .t = 0
    endif
    .t = round (.t * 10 ^ .dec) / 10 ^ .dec
    .h = floor (.t / 3600)
    .m = floor ((.t - .h * 3600) / 60)
    .sec = round ((.t - .h * 3600 - .m * 60) * 10 ^ .dec) / 10 ^ .dec
    if .sec = 0
        # fixed$ prints a bare "0" for zero whatever the precision
        .s$ = "00"
        if .dec > 0
            .s$ = .s$ + "." + left$ ("000000", .dec)
        endif
    else
        .s$ = fixed$ (.sec, .dec)
        if .sec < 10
            .s$ = "0" + .s$
        endif
    endif
    if .h > 0
        .mm$ = string$ (.m)
        if .m < 10
            .mm$ = "0" + .mm$
        endif
        fmtDec.result$ = string$ (.h) + ":" + .mm$ + ":" + .s$
    else
        fmtDec.result$ = string$ (.m) + ":" + .s$
    endif
endproc

procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor (log10 (max (1e-9, .raw)))
    .n = .raw / .mag
    if .n < 1.5
        niceStep.result = .mag
    elsif .n < 3.5
        niceStep.result = 2 * .mag
    elsif .n < 7.5
        niceStep.result = 5 * .mag
    else
        niceStep.result = 10 * .mag
    endif
endproc

# style: 1 neutral, 2 accept, 3 reject, 4 selected toggle, 5 quiet
procedure button: .id$, .x1, .x2, .y1, .y2, .label$, .style, .enabled, .size
    nButtons += 1
    btnId$[nButtons] = .id$
    btnX1[nButtons] = .x1
    btnX2[nButtons] = .x2
    btnY1[nButtons] = .y1
    btnY2[nButtons] = .y2
    btnOn[nButtons] = .enabled
    if .enabled = 0
        .bg$ = "{0.94, 0.94, 0.95}"
        .fg$ = "{0.68, 0.68, 0.72}"
        .bd$ = "{0.84, 0.84, 0.86}"
    elsif .style = 2
        .bg$ = "{0.20, 0.55, 0.32}"
        .fg$ = "White"
        .bd$ = "{0.12, 0.40, 0.22}"
    elsif .style = 3
        .bg$ = "{0.72, 0.24, 0.22}"
        .fg$ = "White"
        .bd$ = "{0.52, 0.15, 0.14}"
    elsif .style = 4
        .bg$ = "{0.25, 0.45, 0.75}"
        .fg$ = "White"
        .bd$ = "{0.16, 0.30, 0.55}"
    elsif .style = 5
        .bg$ = "{0.97, 0.97, 0.97}"
        .fg$ = "{0.35, 0.35, 0.50}"
        .bd$ = "{0.70, 0.70, 0.75}"
    else
        .bg$ = "{0.88, 0.89, 0.92}"
        .fg$ = "{0.15, 0.15, 0.22}"
        .bd$ = "{0.62, 0.63, 0.70}"
    endif
    @rect: .bg$, .x1, .x2, .y1, .y2
    @frame: .bd$, .x1, .x2, .y1, .y2, 1
    @txt: (.x1 + .x2) / 2, "centre", (.y1 + .y2) / 2, .size, .fg$, .label$
endproc

procedure drawUI
    nButtons = 0
    if dp$ = "demo " and titleSet = 0
        demoWindowTitle: "Stochastic Composer"
        titleSet = 1
    endif
    'dp$'Erase all
    @rect: "White", 0, 100, 0, 100

    # ---------------- Title ----------------
    @txt: 50, "centre", 96.6, 22, "Black", "##Stochastic Composer##"
    @txt: 50, "centre", 92.4, 12, "{0.35, 0.35, 0.50}", "%%Human-Guided Composition by Chance%%"
    if state$ = "finished"
        @button: "close", 89, 98, 93, 97.6, "Close", 5, 1, 10
    else
        @button: "quit", 89, 98, 93, 97.6, "Quit", 5, 1, 10
    endif

    @compositionSamples
    compDur = compositionSamples.result / internalSr

    # ---------------- A  STATUS ----------------
    @rect: "{0.97, 0.97, 0.97}", 2, 33, 63, 89
    @frame: "{0.55, 0.55, 0.60}", 2, 33, 63, 89, 1
    @txt: 4, "left", 86, 12, "Black", "##A##  STATUS"
    @fmt: compDur
    .durStr$ = fmt.result$
    .labC$ = "{0.35, 0.35, 0.50}"
    .valC$ = "{0.10, 0.10, 0.18}"
    @txt: 4, "left", 80.5, 11, .labC$, "Accepted"
    @txt: 15.5, "left", 80.5, 11, .valC$, "##" + string$ (nAcc) + "##  recording" + (if nAcc = 1 then "" else "s" fi)
    @txt: 4, "left", 76, 11, .labC$, "Duration"
    @txt: 15.5, "left", 76, 11, .valC$, "##" + .durStr$ + "##"
    @txt: 4, "left", 71.5, 11, .labC$, "Rejected"
    @txt: 15.5, "left", 71.5, 11, .valC$, "##" + string$ (nRejected) + "##  of " + string$ (nProposals) + " proposals"
    @txt: 4, "left", 67, 11, .labC$, "Corpus"
    .corp$ = "##" + string$ (nUsable) + "##  recordings"
    if nSkipped > 0
        .corp$ = .corp$ + "  (" + string$ (nSkipped) + " skipped)"
    endif
    @txt: 15.5, "left", 67, 11, .valC$, .corp$

    # ---------------- B  CANDIDATE ----------------
    @rect: "{0.97, 0.97, 0.97}", 35, 98, 63, 89
    @frame: "{0.55, 0.55, 0.60}", 35, 98, 63, 89, 1
    if state$ = "finished"
        @rect: "{0.20, 0.55, 0.32}", 35, 36.2, 63, 89
        @txt: 38, "left", 86, 12, "Black", "##B##  COMPOSITION COMPLETE"
        @rect: "{0.20, 0.55, 0.32}", 84, 96, 84.3, 87.7
        @txt: 90, "centre", 86, 10, "White", "##READY##"
        @txt: 38, "left", 79.5, 16, "{0.10, 0.10, 0.18}", "##Stochastic_Composition##"
        @txt: 38, "left", 74.5, 10, .labC$, "Available as a Sound in Praat Objects; no file was saved."
        .d$ = string$ (nAcc) + (if nAcc = 1 then " recording" else " recordings" fi) + "   ·   " + .durStr$ + "   ·   " + string$ (internalSr) + " Hz, "
            ... + string$ (internalCh) + " ch"
        @txt: 38, "left", 70.5, 11, .valC$, .d$
        @txt: 38, "left", 66.5, 10, .labC$, "PLAY to audition; CLOSE to remove temporary Praat objects."
    elsif candIdx = 0
        @txt: 38, "left", 86, 12, "Black", "##B##  CURRENT CANDIDATE"
        @txt: 38, "left", 77, 13, .labC$, "No readable recording is left to propose."
    else
        @rect: "{0.85, 0.55, 0.20}", 35, 36.2, 63, 89
        @txt: 38, "left", 86, 12, "Black", "##B##  CURRENT CANDIDATE"
        @txt: 82.5, "right", 86, 10, .labC$, "proposal " + string$ (nProposals)
        @rect: "{0.85, 0.55, 0.20}", 84, 96, 84.3, 87.7
        @txt: 90, "centre", 86, 10, "White", "##PENDING##"
        @clean: cName$[candIdx], 46
        @txt: 38, "left", 79.5, 16, "{0.10, 0.10, 0.18}", "##" + clean.result$ + "##"
        @fmt: candSamples / internalSr
        .cd$ = fmt.result$
        .startS = compDur
        if nAcc > 0
            .startS += gapSec
        endif
        @fmt: .startS
        .st$ = fmt.result$
        .d$ = "duration  ##" + .cd$ + "##   ·   " + string$ (cCh[candIdx]) + " ch, " + string$ (cSr[candIdx])
            ... + " Hz   ·   would start at ##" + .st$ + "##"
        @txt: 38, "left", 73.5, 11, .valC$, .d$
        if nAcc = 0
            @txt: 38, "left", 67.5, 10, .labC$, "First sound: Local and Global audition play the candidate alone."
        else
            @clean: cName$[accIdx[nAcc]], 52
            @txt: 38, "left", 67.5, 10, .labC$, "follows  " + clean.result$
        endif
    endif

    # ---------------- C  AUDITION AND DECISION ----------------
    @rect: "{0.97, 0.97, 0.97}", 2, 98, 30, 61
    @frame: "{0.55, 0.55, 0.60}", 2, 98, 30, 61, 1
    @txt: 4, "left", 58, 12, "Black", "##C##  AUDITION AND DECISION"
    @vline: "{0.80, 0.80, 0.84}", 53.5, 32, 55, 1

    .hasC = candIdx > 0 and state$ = "compose"
    .hasA = nAcc > 0
    @txt: 4, "left", 53.5, 10, .labC$, "Playback   (last played: " + lastPlayed$ + ")"
    @button: "candidate", 4, 12.8, 43, 50.5, "Candidate", 1, .hasC, 11
    @button: "local", 13.6, 22.4, 43, 50.5, "Local", 1, .hasC, 11
    @button: "global", 23.2, 32, 43, 50.5, "Global", 1, .hasC, 11
    @button: "composition", 32.8, 43.6, 43, 50.5, "Composition", 1, .hasA, 11
    @button: "stop", 44.4, 51.6, 43, 50.5, "Stop", 1, 1, 11

    @txt: 4, "left", 36.5, 10, .labC$, "Auto-audition"
    .on = state$ = "compose"
    @button: "mode0", 17, 25, 33.5, 39.5, "Off", if autoMode = 0 then 4 else 1 fi, .on, 10
    @button: "mode1", 25.8, 35.4, 33.5, 39.5, "Local", if autoMode = 1 then 4 else 1 fi, .on, 10
    @button: "mode2", 36.2, 45.8, 33.5, 39.5, "Global", if autoMode = 2 then 4 else 1 fi, .on, 10

    @txt: 56, "left", 53.5, 10, .labC$, "Decision"
    @button: "accept", 56, 75.5, 41.5, 51, "##ACCEPT##", 2, .hasC, 18
    @button: "reject", 77, 96, 41.5, 51, "##REJECT##", 3, .hasC, 18
    @button: "undo", 56, 75.5, 32.5, 38.5, "Undo last", 1, .hasA and state$ = "compose", 11
    @button: "finish", 77, 96, 32.5, 38.5, "##FINISH##", 1, .hasA and state$ = "compose", 11

    # ---------------- D  TIMELINE ----------------
    @rect: "{0.97, 0.97, 0.97}", 2, 98, 9.5, 27.5
    @frame: "{0.55, 0.55, 0.60}", 2, 98, 9.5, 27.5, 1
    @txt: 4, "left", 25, 12, "Black", "##D##  TIMELINE"
    @drawTimeline

    # ---------------- Summary strip ----------------
    @rect: "{0.94, 0.94, 0.94}", 2, 98, 1, 7.5
    @frame: "{0.55, 0.55, 0.60}", 2, 98, 1, 7.5, 1
    .msg$ = message$
    @clean: .msg$, 140
    @txt: 4, "left", 5.5, 11, "{0.25, 0.25, 0.35}", clean.result$
    @txt: 4, "left", 2.8, 9, "{0.45, 0.45, 0.55}", "Keys:  A accept  ·  R reject  ·  U undo  ·  F finish  ·  C candidate  ·  L local  ·  G global  ·  P composition  ·  S stop  ·  Q quit"
    @txt: 96, "right", 2.8, 9, "{0.45, 0.45, 0.55}", "gap " + fixed$ (gapSec * 1000, 0) + " ms  ·  fade " + fixed$ (fadeSec * 1000, 0) + " ms  ·  seed " + seedLabel$

    'dp$'Colour: "Black"
    'dp$'Font size: 10
    @fr
    if dp$ = "demo "
        demoShow ()
    endif
endproc

procedure drawTimeline
    .x0 = 4
    .x1 = 96
    .y0 = 15
    .y1 = 21.5
    .showCand = candIdx > 0 and state$ = "compose"
    .candDur = 0
    .gapBefore = 0
    if .showCand
        .candDur = candSamples / internalSr
        if nAcc > 0
            .gapBefore = gapSec
        endif
    endif
    .total = compDur + .gapBefore + .candDur
    @rect: "{0.90, 0.90, 0.92}", .x0, .x1, .y0, .y1

    @fmt: compDur
    .info$ = "composition ##" + fmt.result$ + "##"
    if .showCand
        @fmt: .candDur
        .info$ = .info$ + "   +   candidate " + fmt.result$
    endif
    .info$ = .info$ + "     blue = accepted   ·   orange = pending"
    @txt: 96, "right", 25, 10, "{0.35, 0.35, 0.50}", .info$

    if .total <= 0
        @txt: 50, "centre", (.y0 + .y1) / 2, 10, "{0.45, 0.45, 0.55}", "The timeline grows as recordings are accepted."
    else
        .sc = (.x1 - .x0) / .total
        # label every m-th block so numbers never crowd
        .every = max (1, ceiling (nAcc / 40))
        .samp = 0
        for .k to nAcc
            if .k > 1
                .samp += gapSamples
            endif
            .ts = .samp / internalSr
            .samp += accSamples[.k]
            .te = .samp / internalSr
            .bx1 = .x0 + .ts * .sc
            .bx2 = .x0 + .te * .sc
            if .bx2 - .bx1 < 0.15
                .bx2 = .bx1 + 0.15
            endif
            if .k mod 2 = 1
                .col$ = "{0.25, 0.45, 0.75}"
            else
                .col$ = "{0.42, 0.60, 0.86}"
            endif
            @rect: .col$, .bx1, .bx2, .y0, .y1
            if .bx2 - .bx1 >= 2.2 and (.k mod .every = 0 or .k = 1)
                @txt: (.bx1 + .bx2) / 2, "centre", (.y0 + .y1) / 2, 9, "White", string$ (.k)
            endif
        endfor
        if .showCand
            .cx1 = .x0 + (compDur + .gapBefore) * .sc
            .cx2 = .x1
            if .cx2 - .cx1 < 0.4
                .cx1 = .cx2 - 0.4
            endif
            @rect: "{0.97, 0.80, 0.58}", .cx1, .cx2, .y0, .y1
            @frame: "{0.85, 0.55, 0.20}", .cx1, .cx2, .y0, .y1, 2
            if .cx2 - .cx1 >= 2.5
                @txt: (.cx1 + .cx2) / 2, "centre", (.y0 + .y1) / 2, 9, "{0.45, 0.25, 0.05}", "?"
            endif
        endif
        @frame: "{0.40, 0.40, 0.45}", .x0, .x1, .y0, .y1, 1

        # time ruler with round steps
        @niceStep: .total, 8
        .step = niceStep.result
        .t = 0
        while .t <= .total + 1e-9
            .tx = .x0 + .t * .sc
            @vline: "{0.40, 0.40, 0.45}", .tx, .y0 - 1, .y0, 1
            # as many decimals as the tick step needs, so labels never repeat
            .dec = max (0, ceiling (-log10 (.step) - 1e-9))
            @fmtDec: .t, .dec
            .lab$ = fmtDec.result$
            @txt: .tx, "centre", 12, 9, "{0.35, 0.35, 0.50}", .lab$
            .t += .step
        endwhile
    endif
endproc
