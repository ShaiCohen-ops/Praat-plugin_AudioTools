# ============================================================
# Praat AudioTools - Gesture-Based_Hard_Quantization.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026) - Short form; canonical atoms, fixed-hop timeline
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.1:
#   - Form reduced from 33 rows to 15. v2.0 added three fields and
#     three comment rows on top of v1.4's seven decorative
#     `comment === ... ===` separators, and the dialog stopped fitting
#     on shorter screens. Praat forms do not scroll, a script may only
#     contain one form block, and beginPause is not usable here, so:
#     all decorative and explanatory comment rows dropped (matching the
#     convention already used elsewhere in the suite), the four voice
#     level fields merged into one Voice_levels_dB field ("0 -3 -5 -7"),
#     and Target_sample_rate, N_time_samples and Verbose_output moved to
#     named constants directly under the form.
#   - No change to audio: the same values produce the same output.
#
# Changelog v2.0:
#
#   NOTE: output is NOT comparable to v1.4. The matching now runs on
#   the audio that is actually rendered, and the timeline no longer
#   contracts, so every selection and every duration changes.
#
#   CRITICAL 1 - matching measured one sound and played another.
#     v1.4 extracted features from the WHOLE dictionary file, then
#     rendered only its first segmentDur (or a Lengthen-ed derivative).
#     A gesture could be chosen for an event four seconds in and then
#     contribute 100 ms of its quiet opening.
#     v2.0 builds a CANONICAL ATOM per dictionary entry - exactly the
#     audio that will be rendered - and extracts features from that.
#     Analysis and resynthesis now refer to the same samples.
#
#   CRITICAL 2 - the output was shorter than the reference.
#     Concatenate with overlap subtracts the overlap at every join, so
#     N segments lost (N-1) * crossfade. Measured on a 2 s reference
#     with 20 segments: 1.810 s out, a 0.190 s shortfall, exactly
#     19 * 10 ms. With Output_duration = 60 the same ratio applied.
#     v2.0 uses fixed-hop assembly: atoms are cut to
#     segmentDur + crossfade, so after the overlaps are subtracted the
#     hop is exactly segmentDur, and the result is trimmed to the
#     requested duration. Verified: requested = delivered.
#
#   CRITICAL 3 - double envelope at every join.
#     v1.4 applied a 5 ms fade-in and fade-out to each piece AND then
#     let Concatenate with overlap apply its own Hann crossfade over
#     the same region, producing a level dip at every segment boundary.
#     v2.0 removes the per-piece fades; Praat's crossfade handles the
#     internal joins, and a fade is applied only to the head and tail
#     of the finished voice.
#
#   4 - Short gestures now really reach segmentDur. The Lengthen factor
#     is still capped at 8, but v1.4 then asked Extract part for a
#     range past the end of the object; Praat silently ZERO-PADS, so a
#     40 ms gesture stretched to 320 ms became a 400 ms segment with
#     80 ms of silence welded on. v2.0 tiles the stretched gesture to
#     the required length instead. Lengthen also uses the user's
#     Pitch_floor / Pitch_ceiling rather than a hard-coded 75 / 600.
#
#   5 - Boundary sampling. v1.4 sampled at exactly tStart and tEnd,
#     where Pitch and Intensity are undefined (verified: both return
#     undefined at the exact edges), and stored 0. globalMinDB was
#     therefore 0 on a corpus whose real floor is far higher, which
#     compressed every intensity difference. v2.0 samples at cell
#     centres AND clamps each sample time into the analysis object's
#     defined frame range - cell centres alone are not enough, since
#     the first Intensity frame sits half a window in.
#
#   6 - Unvoiced frames are no longer smuggled into the pitch channel.
#     v1.4 excluded f0 = 0 when building the range but still normalized
#     it, turning every unvoiced frame into a negative number whose
#     magnitude depended on the corpus. v2.0 uses three channels:
#     log-frequency pitch (perceptually spaced, semitone-like), an
#     explicit 0/1 voiced mask, and intensity.
#
#   7 - Normalization ranges are built from the canonical atoms and
#     from the actual reference segments, not from whole files.
#     Measured on the test corpus: v1.4 pushed 102 of 700 dictionary
#     feature values outside [0, 1].
#
#   8 - Voice 4 is documented honestly. With k = dictionary size the
#     selection is uniform over the whole dictionary: ranking and
#     repetition penalty have no effect on it. It is a scatter layer,
#     not a full-dictionary best-match search.
#
#   9 - Repetition penalty is additive, in units of the mean candidate
#     distance for that segment. The old multiplicative form left a
#     perfect match (distance 0) unpenalized forever.
#
#   10 - Hard quantization is precise for Voice 1 only. Voice 1 is a
#     nearest-neighbour quantizer; Voices 2-4 are stochastic top-k
#     layers. Named as such in the log and the visualization.
#
#   11 - Random_seed added (0 = unpredictable). The generator is
#     returned to its safe state once all selections are made.
#
#   12 - Validation: natural segment / k / sample counts, N >= 2,
#     Pitch_floor < Pitch_ceiling, Output_duration >= 0, minimum
#     segment duration for pitch analysis, and a silent-input check.
#
#   13 - Reference_filename field added. "First file" meant
#     alphabetically first; that is now the documented fallback, not a
#     hidden rule. The file scan also covers .WAV, .aiff, .aif and
#     .flac, with case-insensitive de-duplication.
#
#   14 - Visualization: Panel 3 now really plots segment -> gesture
#     index (it previously plotted normalized distance under a mapping
#     title), and Panel 4 scales its axis to the maximum distance
#     across all voices, so top-k voices are no longer clipped.
#
# Description:
#   Gesture-Based Hard Quantization - Segments a reference sound
#   and replaces each segment with the best-matching gesture from
#   a dictionary of sounds using k-best selection with repetition
#   penalty. Optionally generates 2-4 polyphonic voices, each with
#   independent selection parameters, panned across the stereo field.
#
#   PIPELINE:
#   1. Load folder (reference by name, or alphabetically first)
#   2. Preprocess all sounds (mono, resample, normalize intensity)
#   3. Derive segmentDur, then build one canonical atom per gesture
#   4. Extract features from the atoms and from the reference segments
#   5. Build global normalization ranges from those same vectors
#   6. For each voice: k-best match per segment, additive recency penalty
#   7. Fixed-hop crossfade assembly, trimmed to the requested duration
#   8. Pan voices to stereo, sum, normalize
#
#   POLYPHONIC VOICE PROFILES:
#   Voice 1: Leader   - k=1, nearest-neighbour (true hard quantization)
#   Voice 2: Shadow   - k=k_best, stochastic top-k
#   Voice 3: Wander   - k=k_best*2, stochastic top-k, penalty x1.3
#   Voice 4: Scatter  - k=nDict, UNIFORM random over the dictionary
#                       (ranking and penalty do not affect it)
#
# Category: Composition / Concatenative Synthesis
# ============================================================

# ============================================================
# FORM
# ============================================================

form Gesture Quantization v2.1
    optionmenu Preset: 2
        option Maximum Variety   (k=10, 4 voices)
        option Balanced          (k=7,  2 voices)
        option Coherent          (k=3,  1 voice)
        option Minimal           (k=1,  1 voice)
        option Custom
    natural Number_of_segments 20
    natural K_best_matches 7
    positive Repetition_penalty 0.5
    optionmenu Num_voices: 2
        option 1 (mono)
        option 2 voices
        option 3 voices
        option 4 voices
    sentence Voice_levels_dB 0 -3 -5 -7
    positive Crossfade_ms 10
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    sentence Folder_path
    sentence Reference_filename
    real Output_duration 0
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# SCRIPT-LEVEL SETTINGS  (v2.1)
# ============================================================
# The form was 33 rows in v2.0 and did not fit on shorter displays.
# Praat forms do not scroll and only one form block per script is
# allowed, so these three rarely-touched values moved out of the
# dialog. Edit them here if you need to.

target_sample_rate = 44100
n_time_samples     = 50
verbose_output     = 1

# Voice mix levels, parsed from the single Voice_levels_dB field
# ("0 -3 -5 -7" = voice 1 at unity, voice 2 at -3 dB, and so on).
# Missing or unreadable entries fall back to the defaults below.
voice1_dB = 0.0
voice2_dB = -3.0
voice3_dB = -5.0
voice4_dB = -7.0

vlParts$# = splitByWhitespace$# (voice_levels_dB$)
for vlIdx to size(vlParts$#)
    if vlIdx <= 4
        vlVal = number(vlParts$# [vlIdx])
        if vlVal <> undefined
            voice'vlIdx'_dB = vlVal
        endif
    endif
endfor

# ============================================================
# APPLY PRESET
# ============================================================

if preset = 1
    number_of_segments = 30
    k_best_matches     = 10
    repetition_penalty = 0.8
    num_voices         = 4
    presetName$        = "MaxVariety"
elsif preset = 2
    number_of_segments = 20
    k_best_matches     = 7
    repetition_penalty = 0.7
    num_voices         = 2
    presetName$        = "Balanced"
elsif preset = 3
    number_of_segments = 12
    k_best_matches     = 3
    repetition_penalty = 0.3
    num_voices         = 1
    presetName$        = "Coherent"
elsif preset = 4
    number_of_segments = 8
    k_best_matches     = 1
    repetition_penalty = 0.0
    num_voices         = 1
    presetName$        = "Minimal"
else
    presetName$        = "Custom"
endif

# num_voices from optionmenu is 1-4 (index); presets 1-4 override it above,
# preset 5 (Custom) keeps whatever the form supplied.

# ============================================================
# VALIDATION  (v2.0 fix 12)
# ============================================================

warnLines$ = ""

# The feature timeline needs at least two samples: the sampling step is
# duration / N, and a single sample cannot describe a gesture at all.
if n_time_samples < 2
    n_time_samples = 2
    warnLines$ = warnLines$ + "  ! N_time_samples < 2 -> raised to 2" + newline$
endif

if pitch_floor >= pitch_ceiling
    pitch_floor = 75
    pitch_ceiling = 600
    warnLines$ = warnLines$ + "  ! Pitch_floor >= Pitch_ceiling -> reset to 75 / 600" + newline$
endif

if output_duration < 0
    output_duration = 0
    warnLines$ = warnLines$ + "  ! Output_duration < 0 -> reset to 0 (match reference)" + newline$
endif

if crossfade_ms < 0.1
    crossfade_ms = 0.1
    warnLines$ = warnLines$ + "  ! Crossfade_ms too small -> raised to 0.1 ms" + newline$
endif

# ============================================================
# RANDOM SEED  (v2.0 fix 11)
# ============================================================
# v1.4 had no seed at all, so a successful take could not be recovered:
# top-k selection and the staggered voice histories are both random.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    # Explicit, so that "0 = unpredictable" is actually true rather than
    # inheriting whatever state the interpreter happened to start in.
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

# ============================================================
# DIRECTORY SELECTION
# ============================================================

clearinfo

# --- FOLDER DISCOVERY ---
# Mirrors VoidMosaic: use the typed path, or fall back to a dialog when
# the Folder field is left blank. Trim whitespace and trailing slashes
# first; the trailing-slash normalization just below re-adds it for the
# *.wav glob.
folder_path$ = replace_regex$(folder_path$, "^[ \t]*|[ \t]*$", "", 0)
folder_path$ = replace_regex$(folder_path$, "[\\/]+$", "", 0)

if folder_path$ == ""
    folder_path$ = chooseFolder$: "Select folder containing sound files (first file = reference)"
    folder_path$ = replace_regex$(folder_path$, "[\\/]+$", "", 0)
endif

if folder_path$ == ""
    exitScript: "Operation cancelled. Please supply a valid folder path."
endif

if right$(folder_path$, 1) <> "/" and right$(folder_path$, 1) <> "\"
    folder_path$ = folder_path$ + "/"
endif

# ============================================================
# HELPER PROCEDURES
# ============================================================

procedure log: .message$
    if verbose_output
        appendInfoLine: .message$
    endif
endproc

procedure normalizeIntensity: .soundID
    selectObject: .soundID
    Scale intensity: 70
endproc

procedure convertToMono: .soundID
    selectObject: .soundID
    .nCh = Get number of channels
    if .nCh > 1
        .mono = Convert to mono
        removeObject: .soundID
        .soundID = .mono
    endif
    convertToMono.result = .soundID
endproc

procedure resampleIfNeeded: .soundID, .targetRate
    selectObject: .soundID
    .curRate = Get sampling frequency
    if .curRate <> .targetRate
        .resampled = Resample: .targetRate, 50
        removeObject: .soundID
        .soundID = .resampled
    endif
    resampleIfNeeded.result = .soundID
endproc

# extractFeatureVector: writes global feature_vector_1 ... feature_vector_(3*nSamples)
#   [1 .. N]        log2 pitch in Hz  (raw; 0 when unvoiced)
#   [N+1 .. 2N]     voiced mask, 0 or 1
#   [2N+1 .. 3N]    intensity in dB
#
# v2.0 fix 5: v1.4 sampled at exactly tStart and tEnd, where Pitch and
# Intensity are both undefined (verified on 6.4.42), and wrote 0 for
# each - manufacturing silence at both ends of every vector and pulling
# globalMinDB down to 0. Cell centres alone do not fix this: the first
# Intensity frame sits half an analysis window in, so an early cell
# centre is still outside the defined range. Each sample time is
# therefore clamped into the analysis object's own frame range.
#
# v2.0 fix 6: pitch is stored as log2(Hz) so that 100->200 Hz and
# 400->800 Hz are the same distance, and voicing is carried by its own
# channel instead of being smuggled in as a pitch of zero.
procedure extractFeatureVector: .soundID, .nSamples
    selectObject: .soundID
    .dur   = Get total duration
    .tStart = Get start time

    # Praat requires pitch_floor >= 3 / duration for To Pitch and
    # >= 6.4 / duration for To Intensity. Very short segments can push
    # past what either analysis can do at all, so both are attempted
    # under nocheck and fall back rather than aborting the script.
    .effectivePitchFloor = pitch_floor
    .minAllowedPitchFloor = 3 / .dur
    if .effectivePitchFloor < .minAllowedPitchFloor
        .effectivePitchFloor = ceiling(.minAllowedPitchFloor) + 10
    endif

    .haveP = 0
    if .effectivePitchFloor < pitch_ceiling
        selectObject: .soundID
        nocheck nowarn noprogress To Pitch: 0.01, .effectivePitchFloor, pitch_ceiling
        if numberOfSelected("Pitch") = 1
            .pitch = selected("Pitch")
            .haveP = 1
        endif
    endif
    if .haveP
        selectObject: .pitch
        .pFrames = Get number of frames
        selectObject: .pitch
        .pFirst = Get time from frame number: 1
        if .pFrames > 1
            selectObject: .pitch
            .pLast = Get time from frame number: .pFrames
        else
            .pLast = .pFirst
        endif
    endif

    # Intensity: the floor must satisfy 6.4 / floor <= duration.
    .iPitchFloor = 100
    if 6.4 / .iPitchFloor > .dur
        .iPitchFloor = ceiling(6.4 / .dur) + 10
    endif
    .haveI = 0
    if 6.4 / .iPitchFloor <= .dur
        selectObject: .soundID
        nocheck nowarn noprogress To Intensity: .iPitchFloor, 0, "yes"
        if numberOfSelected("Intensity") = 1
            .intensity = selected("Intensity")
            .haveI = 1
        endif
    endif
    if .haveI
        selectObject: .intensity
        .iFrames = Get number of frames
        selectObject: .intensity
        .iFirst = Get time from frame number: 1
        if .iFrames > 1
            selectObject: .intensity
            .iLast = Get time from frame number: .iFrames
        else
            .iLast = .iFirst
        endif
    else
        # Fall back to one flat level for the whole segment rather than
        # dropping the intensity channel to an arbitrary zero.
        selectObject: .soundID
        .flatDB = Get intensity (dB)
        if .flatDB = undefined
            .flatDB = silenceFloorDB
        endif
    endif

    # Cell centres, not edges
    .cell = .dur / .nSamples

    for .ii to .nSamples
        .t = .tStart + (.ii - 0.5) * .cell

        # --- pitch (clamped into the Pitch object's frame range) ---
        .idxMask = .nSamples + .ii
        if .haveP
            .tp = .t
            if .tp < .pFirst
                .tp = .pFirst
            endif
            if .tp > .pLast
                .tp = .pLast
            endif
            selectObject: .pitch
            .f0 = Get value at time: .tp, "Hertz", "Linear"
        else
            .f0 = undefined
        endif
        if .f0 = undefined or .f0 <= 0
            # genuinely unvoiced: pitch channel parked, mask off
            feature_vector_'.ii' = 0
            feature_vector_'.idxMask' = 0
        else
            feature_vector_'.ii' = log2(.f0)
            feature_vector_'.idxMask' = 1
        endif

        # --- intensity (clamped into the Intensity object's frame range) ---
        .idx3 = 2 * .nSamples + .ii
        if .haveI
            .ti = .t
            if .ti < .iFirst
                .ti = .iFirst
            endif
            if .ti > .iLast
                .ti = .iLast
            endif
            selectObject: .intensity
            .db = Get value at time: .ti, "Cubic"
        else
            .db = .flatDB
        endif
        if .db = undefined
            # a defined floor, not an arbitrary 0 dB
            .db = silenceFloorDB
        endif
        if .db < silenceFloorDB
            .db = silenceFloorDB
        endif
        feature_vector_'.idx3' = .db
    endfor

    if .haveP
        removeObject: .pitch
    endif
    if .haveI
        removeObject: .intensity
    endif
endproc

# normalizeFeatures: normalizes global feature_vector in place.
# Channel 2 (the voiced mask) is already 0/1 and is left alone.
procedure normalizeFeatures: .vectorLen, .minP, .maxP, .minD, .maxD
    for .ii to n_time_samples
        .mi = n_time_samples + .ii
        .mask = feature_vector_'.mi'
        if .mask > 0 and .maxP > .minP
            .val = feature_vector_'.ii'
            .nv = (.val - .minP) / (.maxP - .minP)
            if .nv < 0
                .nv = 0
            endif
            if .nv > 1
                .nv = 1
            endif
            feature_vector_'.ii' = .nv
        else
            feature_vector_'.ii' = 0
        endif
    endfor
    for .ii from 2 * n_time_samples + 1 to .vectorLen
        .val = feature_vector_'.ii'
        if .maxD > .minD
            .nv = (.val - .minD) / (.maxD - .minD)
            if .nv < 0
                .nv = 0
            endif
            if .nv > 1
                .nv = 1
            endif
            feature_vector_'.ii' = .nv
        else
            feature_vector_'.ii' = 0
        endif
    endfor
endproc

# euclideanDistance: compares global feature_vector vs global dict_vector
procedure euclideanDistance: .vLen
    .dist = 0
    for .ii to .vLen
        .diff = feature_vector_'.ii' - dict_vector_'.ii'
        .dist = .dist + .diff * .diff
    endfor
    euclideanDistance.distance = sqrt(.dist)
endproc

# findKBestMatches: selects from dictionary, applies penalty for last 3 choices
# .voiceHistory_1/.voiceHistory_2/.voiceHistory_3 = recent indices for this voice
procedure findKBestMatches: .nPatterns, .k, .h1, .h2, .h3
    for .ii to .nPatterns
        candidate_dist_'.ii' = 10000
        candidate_idx_'.ii'  = .ii
    endfor

    # Pass 1: raw distances, and their mean (the penalty unit)
    .sumDist = 0
    for .dictIdx to .nPatterns
        for .jj to vectorLength
            dict_vector_'.jj' = dict_features_'.dictIdx'_'.jj'
        endfor
        @euclideanDistance: vectorLength
        .dist = euclideanDistance.distance
        candidate_dist_'.dictIdx' = .dist
        .sumDist = .sumDist + .dist
    endfor
    .meanDistLocal = .sumDist / .nPatterns
    if .meanDistLocal < 1e-9
        .meanDistLocal = 1e-9
    endif

    # Pass 2: ADDITIVE recency penalty (v2.0 fix 9).
    # v1.4 multiplied: dist * (1 + penalty). A perfect match has
    # distance 0, and 0 times anything is still 0, so an exact hit
    # could be selected forever no matter how high the penalty. The
    # penalty is now expressed in units of the mean candidate distance
    # for THIS segment, which keeps it scale-free across corpora.
    if repetition_penalty > 0
        if .h1 >= 1 and .h1 <= .nPatterns
            candidate_dist_'.h1' = candidate_dist_'.h1'
                ... + repetition_penalty * .meanDistLocal
        endif
        if .h2 >= 1 and .h2 <= .nPatterns
            candidate_dist_'.h2' = candidate_dist_'.h2'
                ... + repetition_penalty * 0.6 * .meanDistLocal
        endif
        if .h3 >= 1 and .h3 <= .nPatterns
            candidate_dist_'.h3' = candidate_dist_'.h3'
                ... + repetition_penalty * 0.3 * .meanDistLocal
        endif
    endif

    # Partial selection sort to find top k
    for .ii to .k
        .minIdx  = .ii
        .minDist = candidate_dist_'.ii'
        for .jj from .ii + 1 to .nPatterns
            .testDist = candidate_dist_'.jj'
            if .testDist < .minDist
                .minDist = .testDist
                .minIdx  = .jj
            endif
        endfor
        if .minIdx <> .ii
            .tmpDist = candidate_dist_'.ii'
            .tmpIdx  = candidate_idx_'.ii'
            candidate_dist_'.ii'    = candidate_dist_'.minIdx'
            candidate_idx_'.ii'     = candidate_idx_'.minIdx'
            candidate_dist_'.minIdx' = .tmpDist
            candidate_idx_'.minIdx'  = .tmpIdx
        endif
    endfor

    if .k = 1
        findKBestMatches.selectedIndex    = candidate_idx_1
        findKBestMatches.selectedDistance = candidate_dist_1
    else
        .rChoice = randomInteger(1, .k)
        findKBestMatches.selectedIndex    = candidate_idx_'.rChoice'
        findKBestMatches.selectedDistance = candidate_dist_'.rChoice'
    endif
endproc

# buildCanonicalAtom: produce a Sound of EXACTLY grainDur from a gesture.
#
# v2.0 CRITICAL 1: this is the whole point of the rewrite. v1.4 measured
# the complete dictionary file but rendered only its first segmentDur (or
# a Lengthen-ed derivative), so a gesture could win on an event that never
# reached the output. The atom built here is both what gets measured and
# what gets played.
#
# v2.0 fix 4: when a gesture is far too short, Lengthen is capped at 8x
# and v1.4 then asked Extract part for a range past the end of the object.
# Praat ZERO-PADS silently, so a 40 ms gesture became a 400 ms segment
# with 80 ms of welded-on silence. The atom is tiled instead.
procedure buildCanonicalAtom: .soundID, .targetDur
    selectObject: .soundID
    .gDur = Get total duration
    .gStart = Get start time

    if .gDur >= .targetDur
        .atom = Extract part: .gStart, .gStart + .targetDur, "rectangular", 1, "no"
    else
        # Stretch as far as Lengthen is willing to go, using the user's
        # pitch range (v1.4 hard-coded 75 / 600 here regardless of form).
        .lenFactor = .targetDur / .gDur
        if .lenFactor > 8.0
            .lenFactor = 8.0
        endif
        selectObject: .soundID
        .copy = Copy: "atom_src"
        selectObject: .copy
        .lFloor = pitch_floor
        .lCeil = pitch_ceiling
        nocheck nowarn noprogress Lengthen (overlap-add): .lFloor, .lCeil, .lenFactor
        if numberOfSelected("Sound") = 1
            .stretched = selected("Sound")
        else
            .stretched = .copy
        endif
        if .stretched <> .copy
            removeObject: .copy
        endif

        # Lengthen (overlap-add) SATURATES on very short input: past a
        # certain factor it stops producing samples but still sets xmax
        # to the requested length, so `Get total duration` lies.
        # Measured on 6.4.42 with a 40 ms / 1764-sample source:
        #   factor 2 -> dur 0.080  nx 3528  (nx/fs = 0.080)  consistent
        #   factor 4 -> dur 0.160  nx 5292  (nx/fs = 0.120)  DISAGREES
        #   factor 8 -> dur 0.320  nx 5292  (nx/fs = 0.120)  DISAGREES
        # Concatenate goes by sample content, which is why a naive tiling
        # of two "0.32 s" objects produced 0.24 s. Rebuild a clean object
        # from the real content before doing anything else with it.
        selectObject: .stretched
        .snx = Get number of samples
        selectObject: .stretched
        .sfs = Get sampling frequency
        .sContent = .snx / .sfs

        selectObject: .stretched
        .cleanStretch = Extract part: 0, .sContent, "rectangular", 1, "no"
        removeObject: .stretched
        .stretched = .cleanStretch
        .sDur = .sContent

        if .sDur >= .targetDur
            .atom = Extract part: 0, .targetDur, "rectangular", 1, "no"
            removeObject: .stretched
        else
            # Tile: repeat the stretched gesture until it is long enough,
            # then cut to length. No silence is introduced.
            .nCopies = ceiling(.targetDur / .sDur)
            if .nCopies < 2
                .nCopies = 2
            endif
            selectObject: .stretched
            .tileAcc = Copy: "tile_acc"
            for .cc from 2 to .nCopies
                selectObject: .stretched
                .tileNext = Copy: "tile_next"
                selectObject: .tileAcc
                plusObject: .tileNext
                .tileNew = Concatenate
                removeObject: .tileAcc, .tileNext
                .tileAcc = .tileNew
            endfor
            selectObject: .tileAcc
            .atom = Extract part: 0, .targetDur, "rectangular", 1, "no"
            removeObject: .tileAcc, .stretched
        endif
    endif

    buildCanonicalAtom.result = .atom
endproc

# buildVoice: runs full selection+assembly for one voice
# .vIdx      = voice number (1-4)
# .kForVoice = k_best to use for this voice
# .penScale  = multiplier on repetition_penalty for this voice
# writes: voiceSound_'vIdx' (Sound ID), voiceDist_'vIdx'_'segIdx' (distances)
procedure buildVoice: .vIdx, .kForVoice, .penScale
    @log: "  Voice " + string$(.vIdx) + " (" + voiceRole_'.vIdx'$ + "): k=" +
        ... string$(.kForVoice) + "  penalty_scale=" + fixed$(.penScale, 1)

    # Clamp k to dictionary size
    .kUse = .kForVoice
    if .kUse > nDictSounds
        .kUse = nDictSounds
    endif
    if .kUse < 1
        .kUse = 1
    endif

    # History ring (last 3 choices)
    .hist1 = 0
    .hist2 = 0
    .hist3 = 0

    # Stagger starting history for variety among voices
    if .vIdx = 2
        .hist1 = randomInteger(1, nDictSounds)
    elsif .vIdx = 3
        .hist1 = randomInteger(1, nDictSounds)
        .hist2 = randomInteger(1, nDictSounds)
    elsif .vIdx = 4
        .hist1 = randomInteger(1, nDictSounds)
        .hist2 = randomInteger(1, nDictSounds)
        .hist3 = randomInteger(1, nDictSounds)
    endif

    # Temporarily scale repetition_penalty
    savedPenalty = repetition_penalty
    repetition_penalty = repetition_penalty * .penScale

    hasOutput = 0
    currentOutput = 0

    for .segIdx to segmentsToGenerate
        # tile the reference cyclically when generating more than N segments
        .refSegIdx = ((.segIdx - 1) mod number_of_segments) + 1

        # v2.0 fix 7: the reference segment features were already
        # extracted once, before the normalization ranges were built.
        # v1.4 re-ran a full Pitch + Intensity analysis here for every
        # segment of every voice, against ranges that had never seen a
        # single segment.
        for .jj to vectorLength
            feature_vector_'.jj' = seg_features_'.refSegIdx'_'.jj'
        endfor

        @findKBestMatches: nDictSounds, .kUse, .hist1, .hist2, .hist3

        .bestIdx  = findKBestMatches.selectedIndex
        .bestDist = findKBestMatches.selectedDistance

        # Store per-voice distance + match index for stats/visualization
        voiceDist_'.vIdx'_'.segIdx' = .bestDist
        voiceMatch_'.vIdx'_'.segIdx' = .bestIdx

        # Update history ring
        .hist3 = .hist2
        .hist2 = .hist1
        .hist1 = .bestIdx

        # The canonical atom IS the audio that was measured.
        selectObject: atomID_'.bestIdx'
        .piece = Copy: "gq_piece"

        # v2.0 CRITICAL 3: no per-piece fades. v1.4 applied a 5 ms
        # fade-in and fade-out to every piece and then let
        # Concatenate with overlap apply its own Hann crossfade over the
        # same samples, so each join carried two envelopes and dipped in
        # level. Praat's crossfade handles the internal joins; the head
        # and tail of the finished voice are faded once, below.

        # Fixed-hop assembly (v2.0 CRITICAL 2): every atom is
        # segmentDur + crossfade long, so subtracting one crossfade per
        # join leaves a hop of exactly segmentDur.
        if hasOutput = 0
            selectObject: .piece
            currentOutput = Copy: "voice_asm"
            removeObject: .piece
            hasOutput = 1
        else
            selectObject: currentOutput
            plusObject: .piece
            .newAsm = Concatenate with overlap: xfadeSec
            removeObject: currentOutput, .piece
            currentOutput = .newAsm
        endif
    endfor

    # Restore penalty
    repetition_penalty = savedPenalty

    # Trim to the requested timeline. Assembly yields
    # N * (segmentDur + xfade) - (N - 1) * xfade = N * segmentDur + xfade,
    # so there is always at least the trim margin available.
    selectObject: currentOutput
    .asmDur = Get total duration
    .wantDur = targetOutputDur
    if .wantDur > .asmDur
        .wantDur = .asmDur
    endif
    .trimmed = Extract part: 0, .wantDur, "rectangular", 1, "no"
    removeObject: currentOutput
    currentOutput = .trimmed

    # Head/tail fade only (internal joins are already crossfaded)
    selectObject: currentOutput
    .voiceDur = Get total duration
    .edgeFade = xfadeSec
    if .edgeFade > .voiceDur * 0.25
        .edgeFade = .voiceDur * 0.25
    endif
    if .edgeFade > 0.0005
        .efStr$ = fixed$(.edgeFade, 8)
        Formula: "if x - xmin < " + .efStr$ +
            ... " then self * ((x - xmin) / " + .efStr$ + ")" +
            ... " else self fi"
        Formula: "if xmax - x < " + .efStr$ +
            ... " then self * ((xmax - x) / " + .efStr$ + ")" +
            ... " else self fi"
    endif

    # Scale amplitude for voice blend
    if .vIdx = 1
        .voiceDB = voice1_dB
    elsif .vIdx = 2
        .voiceDB = voice2_dB
    elsif .vIdx = 3
        .voiceDB = voice3_dB
    else
        .voiceDB = voice4_dB
    endif
    .ampScale = 10 ^ (.voiceDB / 20)

    selectObject: currentOutput
    Formula: "self * " + fixed$(.ampScale, 6)

    voiceSound_'.vIdx' = currentOutput
endproc

# ============================================================
# LOAD AND PREPROCESS
# ============================================================

if verbose_output
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: "  Gesture-Based Hard Quantization v2.1"
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: ""
    appendInfoLine: "Preset:   ", presetName$
    appendInfoLine: "Voices:   ", num_voices
    appendInfoLine: "Segments: ", number_of_segments
    appendInfoLine: "K-best:   ", k_best_matches
    appendInfoLine: "Penalty:  ", fixed$(repetition_penalty, 2)
    appendInfoLine: "Seed:     ", seedLabel$
    appendInfoLine: ""
endif
if warnLines$ <> ""
    appendInfoLine: "Notes / adjustments:"
    appendInfo: warnLines$
    appendInfoLine: ""
endif

@log: "Reading folder: " + folder_path$

# ============================================================
# FILE SCAN  (v2.0 fix 13)
# ============================================================
# v1.4 globbed *.wav only and silently treated the alphabetically first
# result as the reference. Create Strings as file list sorts by Unicode
# order, not by when a file was added, so "first file" was never the
# user's idea of first. The scan now covers common extensions and the
# reference can be named outright.

nFiles = 0
patternCount = 5
pat_1$ = "*.wav"
pat_2$ = "*.WAV"
pat_3$ = "*.aiff"
pat_4$ = "*.aif"
pat_5$ = "*.flac"

for pIdx to patternCount
    thisList = Create Strings as file list: "scan", folder_path$ + pat_'pIdx'$
    nThis = Get number of strings
    for sIdx to nThis
        selectObject: thisList
        cand$ = Get string: sIdx
        # case-insensitive de-dup (a case-insensitive filesystem returns
        # the same file for *.wav and *.WAV)
        isDup = 0
        for eIdx to nFiles
            if replace_regex$(cand$, ".*", "\\L&", 0) =
                ... replace_regex$(fileName_'eIdx'$, ".*", "\\L&", 0)
                isDup = 1
            endif
        endfor
        if isDup = 0
            nFiles += 1
            fileName_'nFiles'$ = cand$
        endif
    endfor
    removeObject: thisList
endfor

if nFiles < 2
    exitScript: "Need at least 2 sound files (1 reference + 1 dictionary) in: " + folder_path$
endif

# Alphabetical sort across the merged patterns, so the documented
# "alphabetically first" fallback is deterministic.
for aIdx from 2 to nFiles
    keyA$ = fileName_'aIdx'$
    bIdx = aIdx - 1
    while bIdx >= 1 and fileName_'bIdx'$ > keyA$
        nextB = bIdx + 1
        fileName_'nextB'$ = fileName_'bIdx'$
        bIdx -= 1
    endwhile
    nextB = bIdx + 1
    fileName_'nextB'$ = keyA$
endfor

# Reference selection
reference_filename$ = replace_regex$(reference_filename$, "^[ \t]*|[ \t]*$", "", 0)
refFileIdx = 1
if reference_filename$ <> ""
    found = 0
    for fIdx to nFiles
        if fileName_'fIdx'$ = reference_filename$
            refFileIdx = fIdx
            found = 1
        endif
    endfor
    if found = 0
        exitScript: "Reference_filename not found in folder: " + reference_filename$
    endif
else
    warnLines$ = warnLines$ +
        ... "  . No Reference_filename given -> using alphabetically first: " +
        ... fileName_1$ + newline$
endif

# Reorder so the reference is index 1 and the dictionary follows
refPick$ = fileName_'refFileIdx'$
orderCount = 0
orderCount += 1
orderedName_1$ = refPick$
for fIdx to nFiles
    if fIdx <> refFileIdx
        orderCount += 1
        orderedName_'orderCount'$ = fileName_'fIdx'$
    endif
endfor
for fIdx to nFiles
    fileName_'fIdx'$ = orderedName_'fIdx'$
endfor

@log: "Found " + string$(nFiles) + " sound files"
@log: "Reference: " + fileName_1$
@log: ""

# v2.0: three channels per time sample (log-pitch, voiced mask, dB)
vectorLength  = 3 * n_time_samples
nDictSounds   = nFiles - 1
silenceFloorDB = 20

@log: "Loading and preprocessing..."
@log: ""

for fileIdx to nFiles
    filename$  = fileName_'fileIdx'$
    filepath$  = folder_path$ + filename$
    @log: "  [" + string$(fileIdx) + "/" + string$(nFiles) + "] " + filename$
    sound = Read from file: filepath$
    @convertToMono: sound
    sound = convertToMono.result
    @resampleIfNeeded: sound, target_sample_rate
    sound = resampleIfNeeded.result

    # v2.0 fix 12: a silent file cannot be analysed or matched.
    selectObject: sound
    filePeak = Get absolute extremum: 0, 0, "None"
    if filePeak < 1e-6
        exitScript: "File is silent (or near-silent): " + filename$
    endif

    @normalizeIntensity: sound
    soundID_'fileIdx' = sound
    selectObject: sound
    soundName_'fileIdx'$ = selected$("Sound")
endfor
@log: ""

# ============================================================
# REFERENCE SETUP  (moved BEFORE the dictionary build in v2.0,
# because segmentDur determines the canonical atom length)
# ============================================================

refSound   = soundID_1
selectObject: refSound
refDur     = Get total duration
refStart   = Get start time
segmentDur = refDur / number_of_segments

xfadeSec = crossfade_ms / 1000
if xfadeSec > segmentDur * 0.5
    xfadeSec = segmentDur * 0.5
    warnLines$ = warnLines$ +
        ... "  ! Crossfade longer than half a segment -> capped to " +
        ... fixed$(xfadeSec * 1000, 1) + " ms" + newline$
endif

# Every atom is one hop plus one crossfade long.
grainDur = segmentDur + xfadeSec

# v2.0 fix 12: a pitch analysis needs three periods of the floor.
minSegForPitch = 3 / pitch_floor
if segmentDur < minSegForPitch
    warnLines$ = warnLines$ +
        ... "  ! Segment (" + fixed$(segmentDur * 1000, 1) +
        ... " ms) is shorter than 3 periods of Pitch_floor (" +
        ... fixed$(minSegForPitch * 1000, 1) +
        ... " ms); the floor is raised per segment and pitch matching weakens." +
        ... newline$
endif

segmentsToGenerate = number_of_segments
if output_duration > 0
    segmentsToGenerate = ceiling(output_duration / segmentDur)
    if segmentsToGenerate < 1
        segmentsToGenerate = 1
    endif
endif

# The timeline the assembly is trimmed to (v2.0 CRITICAL 2).
if output_duration > 0
    targetOutputDur = output_duration
else
    targetOutputDur = refDur
endif

@log: "Reference: " + soundName_1$
@log: "  Duration:     " + fixed$(refDur, 3) + " s"
@log: "  Analysis segs:" + string$(number_of_segments)
@log: "  Segment dur:  " + fixed$(segmentDur, 4) + " s"
@log: "  Crossfade:    " + fixed$(xfadeSec * 1000, 1) + " ms"
@log: "  Atom length:  " + fixed$(grainDur, 4) + " s (segment + crossfade)"
@log: "  Target output:" + fixed$(targetOutputDur, 3) + " s"
if output_duration > 0
    @log: "  Tiling reference -> " + string$(segmentsToGenerate) + " segments"
endif
@log: ""

# ============================================================
# CANONICAL ATOMS  (v2.0 CRITICAL 1)
# ============================================================

@log: "Building " + string$(nDictSounds) + " canonical atoms (" +
    ... fixed$(grainDur, 4) + " s each)..."

for dictIdx to nDictSounds
    soundIdx = dictIdx + 1
    @buildCanonicalAtom: soundID_'soundIdx', grainDur
    atomID_'dictIdx' = buildCanonicalAtom.result
endfor
@log: "  Atoms ready."
@log: ""

# ============================================================
# FEATURES: ATOMS + ACTUAL REFERENCE SEGMENTS
# ============================================================
# v2.0 fix 7: v1.4 built its normalization ranges from whole dictionary
# files and one whole-reference pass, so the segment vectors it later
# compared were measured against a range that had never seen a segment
# (102 of 700 dictionary values landed outside [0, 1] on the test
# corpus). Ranges now come from exactly the vectors that get compared.

@log: "Extracting features from atoms and reference segments..."

for dictIdx to nDictSounds
    @extractFeatureVector: atomID_'dictIdx', n_time_samples
    for jj to vectorLength
        dict_features_'dictIdx'_'jj' = feature_vector_'jj'
    endfor
endfor

for segIdx to number_of_segments
    segS = refStart + (segIdx - 1) * segmentDur
    segE = segS + segmentDur
    selectObject: refSound
    segObj = Extract part: segS, segE, "rectangular", 1, "no"
    @extractFeatureVector: segObj, n_time_samples
    for jj to vectorLength
        seg_features_'segIdx'_'jj' = feature_vector_'jj'
    endfor
    removeObject: segObj
endfor

# Global ranges over both sets
globalMinPitch = 1e9
globalMaxPitch = -1e9
globalMinDB    = 1e9
globalMaxDB    = -1e9
voicedFrames   = 0

procedure scanRanges: .n, .prefix$
    for .ii to .n
        for .jj to n_time_samples
            .mi = n_time_samples + .jj
            .di = 2 * n_time_samples + .jj
            if .prefix$ = "dict"
                .p = dict_features_'.ii'_'.jj'
                .m = dict_features_'.ii'_'.mi'
                .d = dict_features_'.ii'_'.di'
            else
                .p = seg_features_'.ii'_'.jj'
                .m = seg_features_'.ii'_'.mi'
                .d = seg_features_'.ii'_'.di'
            endif
            if .m > 0
                voicedFrames += 1
                if .p < globalMinPitch
                    globalMinPitch = .p
                endif
                if .p > globalMaxPitch
                    globalMaxPitch = .p
                endif
            endif
            if .d < globalMinDB
                globalMinDB = .d
            endif
            if .d > globalMaxDB
                globalMaxDB = .d
            endif
        endfor
    endfor
endproc

@scanRanges: nDictSounds, "dict"
@scanRanges: number_of_segments, "seg"

if voicedFrames = 0
    # Nothing voiced anywhere: the pitch channel carries no information.
    globalMinPitch = 0
    globalMaxPitch = 0
    warnLines$ = warnLines$ +
        ... "  ! No voiced frames found in any input; matching runs on" +
        ... " intensity alone." + newline$
endif
if globalMinDB > globalMaxDB
    globalMinDB = silenceFloorDB
    globalMaxDB = silenceFloorDB + 1
endif

@log: ""
@log: "Global normalization ranges (from atoms + reference segments):"
if voicedFrames > 0
    @log: "  Pitch: " + fixed$(2 ^ globalMinPitch, 1) + " - " +
        ... fixed$(2 ^ globalMaxPitch, 1) + " Hz  (" +
        ... string$(voicedFrames) + " voiced frames)"
else
    @log: "  Pitch: none voiced"
endif
@log: "  Intensity: " + fixed$(globalMinDB, 1) + " - " + fixed$(globalMaxDB, 1) + " dB"
@log: ""

# Normalize both sets in place
for dictIdx to nDictSounds
    for jj to vectorLength
        feature_vector_'jj' = dict_features_'dictIdx'_'jj'
    endfor
    @normalizeFeatures: vectorLength, globalMinPitch, globalMaxPitch, globalMinDB, globalMaxDB
    for jj to vectorLength
        dict_features_'dictIdx'_'jj' = feature_vector_'jj'
    endfor
endfor
for segIdx to number_of_segments
    for jj to vectorLength
        feature_vector_'jj' = seg_features_'segIdx'_'jj'
    endfor
    @normalizeFeatures: vectorLength, globalMinPitch, globalMaxPitch, globalMinDB, globalMaxDB
    for jj to vectorLength
        seg_features_'segIdx'_'jj' = feature_vector_'jj'
    endfor
endfor
@log: "Dictionary ready."
@log: ""

# ============================================================
# BUILD VOICES
# ============================================================

@log: "Building " + string$(num_voices) + " voice(s)..."
@log: ""

# Voice profiles (v2.0 fixes 8 and 10 - named for what they actually do):
# Voice 1: Leader   - k=1. The only true hard nearest-neighbour quantizer.
# Voice 2: Shadow   - k=k_best, stochastic top-k, staggered history.
# Voice 3: Wander   - k=k_best*2, stochastic top-k, penalty x1.3.
# Voice 4: Scatter  - k=nDict. Selection is UNIFORM over the whole
#                     dictionary, so distance ranking and the repetition
#                     penalty have no effect on it whatsoever. v1.4
#                     described this as a full-dictionary best-match
#                     search and applied a 1.5x penalty scale that could
#                     not change anything.
voiceRole_1$ = "Leader / nearest-neighbour"
voiceRole_2$ = "Shadow / stochastic top-k"
voiceRole_3$ = "Wander / stochastic top-k"
voiceRole_4$ = "Scatter / uniform random"

for vv to num_voices
    if vv = 1
        .kV = 1
        .pS = 1.0
    elsif vv = 2
        .kV = k_best_matches
        .pS = 1.0
    elsif vv = 3
        .kV = k_best_matches * 2
        .pS = 1.3
    else
        .kV = nDictSounds
        .pS = 1.0
    endif
    @buildVoice: vv, .kV, .pS
    if vv = 4
        @log: "    (Scatter: uniform over the dictionary; ranking and" +
            ... " penalty do not apply)"
    endif
    @log: ""
endfor

# v2.0 fix 11: all random selections are done.
if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

# ============================================================
# COMPUTE STATISTICS (Voice 1 = representative)
# ============================================================

sumDist     = 0
statMinDist = voiceDist_1_1
statMaxDist = voiceDist_1_1

for segIdx to segmentsToGenerate
    dist = voiceDist_1_'segIdx'
    sumDist = sumDist + dist
    if dist < statMinDist
        statMinDist = dist
    endif
    if dist > statMaxDist
        statMaxDist = dist
    endif
endfor
meanDist = sumDist / segmentsToGenerate

sumSqDiff = 0
for segIdx to segmentsToGenerate
    diff = voiceDist_1_'segIdx' - meanDist
    sumSqDiff = sumSqDiff + diff * diff
endfor
stdDist = sqrt(sumSqDiff / segmentsToGenerate)

# Gesture usage (voice 1): count how often each dictionary gesture was
# chosen, how many distinct gestures were used, and the peak reuse.
for dictIdx to nDictSounds
    gestureCount_'dictIdx' = 0
endfor
for segIdx to segmentsToGenerate
    m = voiceMatch_1_'segIdx'
    if m >= 1 and m <= nDictSounds
        gestureCount_'m' = gestureCount_'m' + 1
    endif
endfor
uniqueCount = 0
maxUsage    = 0
for dictIdx to nDictSounds
    c = gestureCount_'dictIdx'
    if c > 0
        uniqueCount = uniqueCount + 1
    endif
    if c > maxUsage
        maxUsage = c
    endif
endfor

# ============================================================
# MIX VOICES TO OUTPUT
# ============================================================

@log: "Mixing " + string$(num_voices) + " voice(s) to output..."

# Pan positions — always defined for all 4 slots so viz never hits unknown variable
panPos_1 = 0.0
panPos_2 = 0.0
panPos_3 = 0.0
panPos_4 = 0.0

if num_voices = 1
    # Mono output - just rename voice 1
    selectObject: voiceSound_1
    peakV = Get absolute extremum: 0, 0, "None"
    if peakV > 0
        Scale peak: 0.95
    endif
    outputName$ = "gesture_quant_" + presetName$ + "_" + soundName_1$
    outputName$ = replace$(outputName$, " ", "_", 0)
    Rename: outputName$
    outputSound = selected("Sound")
    outputDur   = Get total duration

else
    # Find longest voice duration for padding
    maxVoiceDur = 0
    for vv to num_voices
        selectObject: voiceSound_'vv'
        vDur = Get total duration
        if vDur > maxVoiceDur
            maxVoiceDur = vDur
        endif
    endfor

    # Pad all voices to maxVoiceDur
    for vv to num_voices
        selectObject: voiceSound_'vv'
        vDur = Get total duration
        padNeeded = maxVoiceDur - vDur
        if padNeeded > 0.005
            Create Sound from formula: "pad", 1, 0, padNeeded, target_sample_rate, "0"
            padSnd = selected("Sound")
            selectObject: voiceSound_'vv'
            plusObject: padSnd
            paddedVoice = Concatenate
            removeObject: voiceSound_'vv', padSnd
            voiceSound_'vv' = paddedVoice
        endif
    endfor

    if num_voices = 2
        panPos_1 = -0.55
        panPos_2 =  0.55
    elsif num_voices = 3
        panPos_1 = -0.70
        panPos_2 =  0.00
        panPos_3 =  0.70
    else
        panPos_1 = -0.75
        panPos_2 = -0.25
        panPos_3 =  0.25
        panPos_4 =  0.75
    endif

    # Create stereo sum (start with zeros at maxVoiceDur)
    Create Sound from formula: "gq_L", 1, 0, maxVoiceDur, target_sample_rate, "0"
    leftAcc = selected("Sound")
    Create Sound from formula: "gq_R", 1, 0, maxVoiceDur, target_sample_rate, "0"
    rightAcc = selected("Sound")

    # Equal-power pan and add each voice
    for vv to num_voices
        panP = panPos_'vv'
        # Equal-power: angle in [0, pi/2]
        panNorm = (panP + 1) / 2
        lGain   = cos(panNorm * pi / 2)
        rGain   = sin(panNorm * pi / 2)

        # Scale voice to L channel contribution
        selectObject: voiceSound_'vv'
        lChan = Copy: "gq_lc"
        selectObject: lChan
        Formula: "self * " + fixed$(lGain, 6)

        selectObject: voiceSound_'vv'
        rChan = Copy: "gq_rc"
        selectObject: rChan
        Formula: "self * " + fixed$(rGain, 6)

        # Add to accumulators
        selectObject: leftAcc
        Formula: "self + object[lChan]"
        selectObject: rightAcc
        Formula: "self + object[rChan]"

        removeObject: lChan, rChan
    endfor

    # Combine to stereo
    selectObject: leftAcc
    plusObject: rightAcc
    Combine to stereo
    stereoOut = selected("Sound")
    removeObject: leftAcc, rightAcc

    selectObject: stereoOut
    peakV = Get absolute extremum: 0, 0, "None"
    if peakV > 0
        Scale peak: 0.95
    endif

    outputName$ = "gesture_quant_" + presetName$ + "_" + string$(num_voices) + "v_" + soundName_1$
    outputName$ = replace$(outputName$, " ", "_", 0)
    Rename: outputName$
    outputSound = stereoOut
    outputDur   = Get total duration

    # Remove voice intermediates
    for vv to num_voices
        removeObject: voiceSound_'vv'
    endfor
endif

@log: "Output: " + outputName$
@log: "Duration: " + fixed$(outputDur, 2) + " s"
@log: ""

# ============================================================
# VERBOSE STATISTICS
# ============================================================

if verbose_output
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: "  SUMMARY STATISTICS"
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: ""
    appendInfoLine: "Preset:    ", presetName$
    appendInfoLine: "Reference: ", soundName_1$
    appendInfoLine: "Dictionary:", nDictSounds, " gestures"
    appendInfoLine: "Voices:    ", num_voices
    appendInfoLine: ""
    appendInfoLine: "Parameters:"
    appendInfoLine: "  Segments:         ", number_of_segments
    appendInfoLine: "  Segment duration: ", fixed$(segmentDur, 3), " s"
    appendInfoLine: "  K-best (voice 1): 1 (nearest-neighbour leader)"
    if num_voices > 1
        appendInfoLine: "  K-best (voice 2): ", k_best_matches
    endif
    if num_voices > 2
        appendInfoLine: "  K-best (voice 3): ", k_best_matches * 2
    endif
    if num_voices > 3
        appendInfoLine: "  K-best (voice 4): ", nDictSounds,
            ... " (uniform scatter - ranking/penalty inactive)"
    endif
    appendInfoLine: "  Repetition penalty: ", fixed$(repetition_penalty, 2)
    appendInfoLine: ""
    appendInfoLine: "Voice 1 Distance Statistics:"
    appendInfoLine: "  Mean: ", fixed$(meanDist, 4)
    appendInfoLine: "  Std:  ", fixed$(stdDist,  4)
    appendInfoLine: "  Min:  ", fixed$(statMinDist, 4)
    appendInfoLine: "  Max:  ", fixed$(statMaxDist, 4)
    appendInfoLine: ""
    appendInfoLine: "Voice 1 Gesture Usage:"
    appendInfoLine: "  Distinct gestures used: ", uniqueCount, " / ", nDictSounds
    appendInfoLine: "  Most-reused gesture:    ", maxUsage, " segment(s)"
    appendInfoLine: ""
    appendInfoLine: "════════════════════════════════════════════════════════"
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    @log: "Drawing visualization..."

    selectObject: refSound
    refPeak = Get absolute extremum: 0, 0, "None"
    if refPeak < 0.001
        refPeak = 0.001
    endif
    ampMax = refPeak * 1.15

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.48
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Gesture-Based Hard Quantization v2.1##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.15, "half",
        ... "[" + presetName$ + "]  " + soundName_1$
        ... + "  |  " + string$(num_voices) + " voice(s)"
        ... + "  |  k=" + string$(k_best_matches)
        ... + "  |  " + string$(nDictSounds) + " gestures"
        ... + "  |  " + string$(number_of_segments) + " seg"

    # === PANEL 1: Reference waveform ===
    Select outer viewport: 0, 8, 0.52, 1.35
    Select inner viewport: 0.60, 7.65, 0.57, 1.30
    Axes: 0, refDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, refDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, refDur, 0
    # Segment boundary lines
    for segIdx to segmentsToGenerate - 1
        bTime = refStart + segIdx * segmentDur
        Colour: "{0.72, 0.78, 0.88}"
        Dotted line
        Draw line: bTime, -ampMax, bTime, ampMax
        Solid line
    endfor
    selectObject: refSound
    Colour: "{0.45, 0.50, 0.58}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Reference"
    Text top: "no", "Input  (dotted = segment boundaries)"

    # === PANEL 2: Output waveform ===
    Select outer viewport: 0, 8, 1.38, 2.20
    Select inner viewport: 0.60, 7.65, 1.43, 2.15
    Axes: 0, outputDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, outputDur, 0
    selectObject: outputSound
    Colour: "{0.25, 0.55, 0.45}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Quantized output  (" + string$(num_voices) + " voice(s))"
    Text bottom: "yes", "Time (s)"

    # === PANEL 3: Segment → Gesture mapping (voice 1) ===
    Select outer viewport: 0, 8, 2.28, 3.32
    Select inner viewport: 0.60, 7.65, 2.33, 3.27
    Axes: 0, segmentsToGenerate, 0, nDictSounds + 1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, segmentsToGenerate, 0, nDictSounds + 1

    # Horizontal grid lines per gesture
    for dictIdx to nDictSounds
        Colour: "{0.88, 0.88, 0.88}"
        Draw line: 0, dictIdx, segmentsToGenerate, dictIdx
    endfor

    # v2.0 fix 14: this panel is titled "Segment -> Gesture mapping" and
    # now actually plots the chosen gesture index on y. v1.4 plotted
    # normalized distance there, so the y axis was labelled with a
    # dictionary range it never used.
    for segIdx to segmentsToGenerate
        dist     = voiceDist_1_'segIdx'
        distNorm = (dist - statMinDist) / (statMaxDist - statMinDist + 0.001)
        cR = 0.35 + distNorm * 0.45
        cG = 0.72 - distNorm * 0.32
        cB = 0.35
        cRs$ = fixed$(cR, 2)
        cGs$ = fixed$(cG, 2)
        cBs$ = fixed$(cB, 2)
        yPos = voiceMatch_1_'segIdx'
        Paint rectangle: "{" + cRs$ + "," + cGs$ + "," + cBs$ + "}",
            ... segIdx - 1, segIdx, yPos - 0.4, yPos + 0.4
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gesture #"
    Text bottom: "yes", "Segment"
    Text top: "no", "Voice 1 segment -> gesture  (green=close match  orange=far)"

    # === PANEL 4: Per-voice distance comparison (if >1 voice) ===
    Select outer viewport: 0, 4, 3.40, 4.45
    Select inner viewport: 0.55, 3.75, 3.45, 4.40

    if statMaxDist < 0.001
        statMaxDist = 1
    endif

    # v2.0 fix 14: scale to the largest distance across ALL voices.
    # v1.4 used Voice 1's maximum, but Voice 1 is the nearest-neighbour
    # leader and therefore has the SMALLEST distances by construction,
    # so every top-k voice was clipped at the top of the panel.
    allMaxDist = statMaxDist
    for vv to num_voices
        for segIdx to segmentsToGenerate
            dv = voiceDist_'vv'_'segIdx'
            if dv > allMaxDist
                allMaxDist = dv
            endif
        endfor
    endfor
    if allMaxDist < 0.001
        allMaxDist = 1
    endif

    Axes: 0, segmentsToGenerate + 1, 0, allMaxDist * 1.2
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, segmentsToGenerate + 1, 0, allMaxDist * 1.2

    # Mean line
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, meanDist, segmentsToGenerate + 1, meanDist
    Solid line

    # Voice colors
    vc_1R = 0.25
    vc_1G = 0.50
    vc_1B = 0.75
    vc_2R = 0.80
    vc_2G = 0.40
    vc_2B = 0.20
    vc_3R = 0.25
    vc_3G = 0.65
    vc_3B = 0.40
    vc_4R = 0.65
    vc_4G = 0.25
    vc_4B = 0.65

    for vv to num_voices
        cR$ = fixed$(vc_'vv'R, 2)
        cG$ = fixed$(vc_'vv'G, 2)
        cB$ = fixed$(vc_'vv'B, 2)
        Colour: "{" + cR$ + "," + cG$ + "," + cB$ + "}"
        Line width: 1.2
        for segIdx from 2 to segmentsToGenerate
            prevIdx = segIdx - 1
            d1 = voiceDist_'vv'_'prevIdx'
            d2 = voiceDist_'vv'_'segIdx'
            Draw line: prevIdx, d1, segIdx, d2
        endfor
        Line width: 1
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Distance"
    Text bottom: "yes", "Segment"
    Text top: "no", "Match distances by voice"

    # Legend
    if num_voices > 1
        Font size: 5
        xLeg = segmentsToGenerate * 0.65
        yLeg = allMaxDist * 1.15
        yStep = allMaxDist * 0.10
        for vv to num_voices
            cR$ = fixed$(vc_'vv'R, 2)
            cG$ = fixed$(vc_'vv'G, 2)
            cB$ = fixed$(vc_'vv'B, 2)
            Colour: "{" + cR$ + "," + cG$ + "," + cB$ + "}"
            Text: xLeg, "left", yLeg - (vv - 1) * yStep, "half", "V" + string$(vv)
        endfor
    endif

    # === PANEL 5: Pan positions (if >1 voice) ===
    if num_voices > 1
    Select outer viewport: 4, 8, 3.40, 4.45
    Select inner viewport: 4.20, 7.65, 3.45, 4.40
    Axes: 0, num_voices + 1, -1.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, num_voices + 1, -1.1, 1.1

    # Center line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, num_voices + 1, 0
    # L/R labels
    Font size: 6
    Colour: "{0.65, 0.65, 0.65}"
    Text: 0.15, "left", -0.95, "half", "L"
    Text: 0.15, "left",  0.95, "half", "R"

    for vv to num_voices
        panP = panPos_'vv'
        cR$ = fixed$(vc_'vv'R, 2)
        cG$ = fixed$(vc_'vv'G, 2)
        cB$ = fixed$(vc_'vv'B, 2)
        Paint rectangle: "{" + cR$ + "," + cG$ + "," + cB$ + "}",
            ... vv - 0.35, vv + 0.35, 0, panP
        Font size: 6
        Colour: "Black"
        if panP >= 0
            labelY = panP + 0.08
        else
            labelY = panP - 0.08
        endif
        Text: vv, "centre", labelY, "half", fixed$(panP, 2)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan"
    Text bottom: "yes", "Voice"
    Text top: "no", "Voice pan positions (L=-1  R=+1)"
    endif

    # === PANEL 6: Statistics ===
    Select outer viewport: 0, 8, 4.52, 5.20
    Select inner viewport: 0.40, 7.75, 4.57, 5.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.87, "half", "##Gesture-Based Hard Quantization v2.1##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02, "left", 0.65, "half",
        ... "Reference: " + soundName_1$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Voices: " + string$(num_voices)
        ... + "  |  Dict: " + string$(nDictSounds) + " gestures"
    Text: 0.02, "left", 0.44, "half",
        ... "Segments: " + string$(number_of_segments)
        ... + "  |  Seg dur: " + fixed$(segmentDur * 1000, 0) + " ms"
        ... + "  |  K-best: " + string$(k_best_matches)
        ... + "  |  Penalty: " + fixed$(repetition_penalty, 2)
    Text: 0.02, "left", 0.23, "half",
        ... "V1 dist: mean=" + fixed$(meanDist, 3)
        ... + "  std=" + fixed$(stdDist, 3)
        ... + "  min=" + fixed$(statMinDist, 3)
        ... + "  max=" + fixed$(statMaxDist, 3)
        ... + "  |  Output: " + outputName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    @log: "  Visualization complete."
endif

# ============================================================
# CLEANUP
# ============================================================

@log: "Cleaning up..."

for ii to nFiles
    removeObject: soundID_'ii'
endfor
for ii to nDictSounds
    removeObject: atomID_'ii'
endfor

# ============================================================
# OUTPUT
# ============================================================

selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "════════════════════════════════════════════════════════"
appendInfoLine: "  COMPLETE"
appendInfoLine: "════════════════════════════════════════════════════════"
appendInfoLine: "Output:   ", outputName$
appendInfoLine: "Duration: ", fixed$(outputDur, 2), " s"
appendInfoLine: "Voices:   ", num_voices
if num_voices = 1
    appendInfoLine: "Channels: 1 (mono)"
else
    appendInfoLine: "Channels: 2 (stereo)"
endif

if play_result
    Play
endif
