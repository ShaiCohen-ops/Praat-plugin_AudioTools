# ============================================================
# Praat AudioTools - Dramaturgical_Structure_Composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 5.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Section-level structural reshaping for fixed-media
#   electroacoustic composition. Detects sections in the input
#   via spectral novelty, classifies each section by a small
#   set of static features (RMS, spectral centroid,
#   harmonicity), then reshapes form through:
#
#     - Reordering by one of five archetypes (arch / contrast /
#       rondo / narrative / random)
#     - Optional structural operations: loop a section, insert
#       a silence, time-stretch a section, recall an earlier
#       section in transformed form
#     - Texture-pair-aware crossfade durations at joints
#     - A multiplicative macro tension-arc envelope over the
#       whole output (preserves intra-section dynamics)
#
#   This is an algorithmic-form tool. It produces arrangements
#   of the input's existing sections, not transformations of
#   them at the gestural / spectromorphological level. The only
#   actual content transformation is the optional "recall"
#   (low-pass + amplitude reduction + optional reverse).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v5.4.1:
#   Visualization alignment pass only; DSP and structural logic unchanged.
#   Reworked the Picture output to the current Praat AudioTools suite layout:
#   Source -> Dramaturgical form map -> Output -> Summary. The central map
#   aligns detected source sections with the actual output timeline, connects
#   each output item to its source section, encodes texture by fill color,
#   marks LOOP/SIL/STR/REC operations textually, and integrates the tension
#   arc below the timeline. Also fixes underscore/subscript display names and
#   removes the vertical text collisions present in the v5.4 Picture layout.
#
# Changelog v5.4:
#   Correctness + dramaturgical-semantics pass.
#   (1) CRITICAL: fixed iterative assembly order. Praat concatenates selected
#   Sounds in Object-list order, not selection order; the older accumulated
#   output could therefore come after the intended "next" timeline item.
#   v5.4 creates each join item after the accumulator before concatenation.
#   (2) Texture-aware crossfades are bounded by both adjacent item durations,
#   not by the duration of the whole accumulated output.
#   (3) Non-zero Sound time domains are handled explicitly. Structural times
#   remain zero-based; Spectrogram queries and source extracts use sourceStart.
#   (4) Harmonicity threshold default changed from 0.15 dB to 5 dB.
#   (5) Rondo refrain selection no longer uses abs(HNR), which rewarded large
#   negative/noise-dominated HNR; it now combines positive HNR and RMS salience.
#   (6) A final novelty boundary is removed if it would leave a section shorter
#   than Min_section_duration_s.
#   (7) Arc_exaggeration > 1 now increases arc contrast instead of flattening it.
#   (8) LOOP visualization flags are attached to actual generated loop copies.
#   (9) Spectral-novelty bins use only min(5 kHz, Nyquist).
#
# Changelog v5.3:
#   Capacity + edge-case pass. (1) max_timeline is now sized to hold
#   the worst-case Rondo form (2N-1) plus all operation insertions
#   (= 2*max_sections + 2*max_operations_bound), and the timeline build
#   WARNS if capacity is ever reached instead of silently dropping the
#   tail of the form. (2) Max-duration splitting now respects Min
#   section duration: it never creates a sub-Min fragment, keeping one
#   slightly-over-Max piece when Max and Min conflict, and reports both
#   that case and any hit of the max_sections cap. (3) max_operations
#   set to realistic values (only one op per type is planned, so the
#   ceiling is 4); over-cap trimming now drops a RANDOM operation rather
#   than always the last-planned one (which always removed recall).
#   (4) Novelty threshold clamped to its stated 0-1 range.
#
# Changelog v5.2:
#   Correctness pass. (1) Max section duration now SPLITS long spans
#   into forced boundaries instead of truncating them, so the whole
#   source is covered exactly once (v5.1 silently discarded material
#   past each cut, and a no-peak file kept only the first Max seconds).
#   (2) Structural operations are now applied in a SINGLE forward pass
#   keyed to stable form positions; v5.1 applied them to a mutating
#   timeline, so loop/silence insertions shifted the targets of later
#   stretch/recall ops -- a stretch could land on an inserted silence
#   and render secSound#[0] (a crash). (3) Detected-section count and
#   form length are now separate variables (numDetectedSections vs
#   formLength); Rondo (2N-1 items) no longer overflows sectionOrder#
#   (sized to max_timeline) or corrupts Panel A / cleanup. Also: novelty
#   is now gain-invariant (log-power flux, normalized so the threshold
#   is relative 0-1); "quiet" is classified by RMS relative to the
#   loudest section (not duration-dependent energy); texture distance
#   uses a categorical same/different term (not arbitrary code
#   arithmetic); parameter validation added (min<=max, arc bounds,
#   non-negative novelty); Random seed added; Harmonicity threshold
#   labelled in dB; Narrative "return" and arc-edge labels corrected.
#
# Changelog v5.1:
#   Output channel count now matches input. v5.0 always produced
#   mono output regardless of input channel count, because the
#   `Convert to mono` at the top of the script created `workSound`
#   and ALL downstream operations (section extraction, silence
#   creation, noise tail, time-stretch, recall, concatenation)
#   built on that mono buffer. The original stereo `inputSound`
#   was used only for spectrogram analysis and then ignored.
#
#   v5.1 keeps `workSound` mono (correctly -- it's still used for
#   analysis where mono is required) but rebuilds the assembly
#   path from the original `inputSound`. Specific changes:
#
#     1. Per-section extract (Step 2): the section stored in
#        secSound#[s] now comes from inputSound (preserves channel
#        count). A separate mono temporary is created from
#        workSound for the per-section analysis procedures
#        (computeSpectralCentroid uses To Spectrum, computeHarmonicity
#        uses To Harmonicity (cc) -- both mono-only in Praat).
#        For mono inputs the temp is skipped (sectionMono = sectionSound).
#     2. Noise tail template (silence_mode = 2): extracted from
#        inputSound instead of workSound.
#     3. Digital silence creation: number of channels parameter
#        now uses inputChannels (was hardcoded `1`). Required for
#        Concatenate with overlap to accept timeline items of
#        consistent channel count.
#     4. Time-stretch operation (itemType = 4): To Manipulation
#        is mono-only in Praat, so the stretch path now splits a
#        stereo section into channels, manipulates each
#        independently, and recombines via Combine to stereo.
#        Mono inputs skip the split and use the v5.0 code path.
#     5. Recall (itemType = 5): Filter (pass Hann band), Reverse,
#        and Multiply all already work on stereo, so the recall
#        path works unchanged for stereo input.
#
#   For mono input audio, output is bit-identical to v5.0. For
#   stereo input, output is now stereo and preserves the original
#   L/R image of each section.
#
# Changelog v5.0:
#   This is a substantial rewrite. v4.0 audio is NOT preserved.
#   Audio character is significantly different and (we believe)
#   correct in the direction that was broken before. Specific
#   audio-affecting changes:
#
#   - CORRECTNESS: section extract now uses rectangular window
#     instead of Hanning. v4.0's `Extract part: ..., "Hanning",
#     1, "no"` applied a full-section Hann window to every
#     section, so each section faded in from zero, peaked in
#     the middle, and faded back to zero. The crossfade-overlap
#     assembly stage already handles joints; v4.0 was
#     double-applying fades and destroying section content
#     edges. v5.0 outputs use the actual section audio.
#   - CORRECTNESS: time-stretch now operates on rectangular
#     section content (was operating on the windowed shape, so
#     the stretch was stretching the Hann envelope itself).
#   - REMOVED: dead silence detection. v4.0 ran detectSilence
#     and populated silStart/silEnd arrays that were never read
#     by section detection or operation planning. Removed the
#     procedure, the dead bookkeeping, the silence_threshold_dB
#     and min_silence_duration_s form fields, and the header
#     claim that the script does "actual silence detection".
#   - PERFORMANCE: spectrogram time step 0.002 -> 0.05 (line
#     354 in v4.0). The novelty analysis runs at 0.1 s step, so
#     49 of every 50 spectrogram frames were thrown away. ~5-15s
#     saved on typical 3-5 minute inputs.
#   - API: `computeSpectralCentroid` and `computeHarmonicity`
#     no longer accept time-range arguments (they were silently
#     ignored). Both now compute over the full passed Sound.
#   - DATA: pseudo-array syntax `var_'i'` replaced throughout
#     with modern vectors `var#[i]`. About 25 distinct
#     pseudo-arrays converted. Section, sort, operation, and
#     timeline data is now allocated in pre-sized vectors with
#     explicit bounds.
#   - SAFETY: timeline expansion now respects the array bound.
#     v4.0 could overflow `maxTimelineItems = 200` with many
#     loop/silence/recall operations.
#   - FORM: beginPause second-dialog removed. All settings
#     pulled into the main form. 5 decorative `=== Section ===`
#     comment dividers dropped. Form went from 13 main fields
#     + 9 dialog fields + 5 comments = 27 effective rows to 21
#     fields in one dialog.
#   - VIZ: rewritten to suite 8x8 standard AND extended to
#     finally show the structural transformation. v4.0's viz
#     showed input sections and output waveform but completely
#     hid the operation timeline. v5.0:
#       Title bar (suite standard)
#       Panel A (left, headline): input sections, colored by
#         texture, bar heights show RMS (preserved from v4.0)
#       Panel B (right, headline): OPERATION TIMELINE in
#         output time. Each timeline item is a horizontal
#         block at its actual position in the final output,
#         colored by the source section's texture (gray for
#         silences). Labels show source section number plus
#         operation marker (LOOP, STR, REC). This is the
#         "what did the dramaturgy actually do" view that v4.0
#         was missing.
#       Panel C: output waveform
#       Panel D: tension arc envelope curve
#       Panel E: light-grey summary stats bar (suite standard)
#   - OUTPUT NAMING: filename now includes strategy and reorder
#     mode. v4.0 always wrote to "DramaturgicalComposer_v4_out"
#     regardless of parameters, so different runs collided.
#     v5.0: <input>_dramat_<Strategy>_<Reorder>.
#
# Changelog v4.0:
#   - Macro-dynamics preserved (no per-block normalization)
#   - Optional tension arc envelope
#   - Texture-aware crossfade durations
#   - Form archetype reordering
#   - Transformed recalls
#   - Context-aware silence placement
# ============================================================

form Dramaturgical Structure Composer v5.4.1
    positive Min_section_duration_s 8
    positive Max_section_duration_s 90
    comment Novelty threshold is relative (0-1 of peak); Harmonicity is HNR in dB
    real Novelty_threshold 0.25
    real Harmonicity_threshold_dB 5.0
    optionmenu Strategy: 2
        option Conservative (subtle)
        option Dramatic (major)
        option Radical (complete)
    optionmenu Reorder_mode: 3
        option None (original order)
        option Arch (build to peak)
        option Contrast (max adjacent diff)
        option Rondo (refrain + episodes)
        option Narrative (dark to bright + return)
        option Random swap
    optionmenu Crossfade_mode: 2
        option Fixed short (30 ms)
        option Texture-aware
    optionmenu Silence_mode: 2
        option Digital zero
        option Noise tail from source
    boolean Allow_looping 1
    boolean Allow_long_silences 1
    boolean Allow_time_stretching 1
    boolean Allow_material_recall 1
    boolean Recall_lowpass 1
    boolean Recall_reverse 1
    boolean Apply_tension_arc 1
    real Arc_peak_position 0.65
    real Arc_exaggeration 1.5
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ============================================================
# Constants (formerly in form / beginPause; pinned here)
# ============================================================
spectral_centroid_low_hz = 500
spectral_centroid_high_hz = 3000
recall_amplitude_factor = 0.7
recall_lowpass_hz = 2500

# Pre-allocated bounds
max_sections = 200
max_operations_bound = 50
# Worst case: Rondo form = 2*max_sections-1 items, plus up to 2 insertions per
# planned operation (loop copies, silence, recall). Sized so the timeline never
# has to silently drop the tail of the form.
max_timeline = 2 * max_sections + 2 * max_operations_bound

# ============================================================
# Helper Procedures
# ============================================================

procedure computeSpectralCentroid: .soundObj
    selectObject: .soundObj
    .spectrum = To Spectrum: "yes"
    .centroid = Get centre of gravity: 2
    if .centroid = undefined
        .centroid = 0
    endif
    removeObject: .spectrum
endproc

procedure computeHarmonicity: .soundObj
    selectObject: .soundObj
    .dur = Get total duration
    if .dur < 0.1
        .harmValue = 0
    else
        .harmObj = To Harmonicity (cc): 0.01, 75, 0.1, 1.0
        .harmValue = Get mean: 0, 0
        if .harmValue = undefined
            .harmValue = 0
        endif
        removeObject: .harmObj
    endif
endproc

procedure computeRMS: .soundObj
    selectObject: .soundObj
    .rms = Get root-mean-square: 0, 0
    if .rms = undefined
        .rms = 0
    endif
endproc

# ----------------------------------------------------------
# Texture-pair crossfade lookup
# Texture codes: 0=silence, 1=tonal, 2=quiet/sparse,
#                3=bright, 4=dark, 5=noise/fallback
# ----------------------------------------------------------
procedure getCrossfadeDuration: .fromTex, .toTex
    if crossfade_mode = 1
        .duration = 0.03
    else
        .duration = 0.3
        if .fromTex = 1 and .toTex = 1
            .duration = 1.5
        elsif .fromTex = 1
            .duration = 0.8
        elsif .toTex = 1
            .duration = 0.6
        endif
        if .fromTex = 2 or .toTex = 2
            .duration = 0.15
        endif
        if (.fromTex = 5 or .fromTex = 3) and (.toTex = 2)
            .duration = 0.01
        endif
        if .fromTex = 0
            .duration = 1.5
        endif
        if .toTex = 0
            .duration = 0.08
        endif
        if .fromTex = 5 and .toTex = 5
            .duration = 0.4
        endif
        if (.fromTex = 4 and .toTex = 3) or (.fromTex = 3 and .toTex = 4)
            .duration = 0.05
        endif
    endif
endproc

procedure textureDistance: .tex1, .tex2, .cent1, .cent2, .rms1, .rms2
    # Texture codes are CATEGORIES, so |code1-code2| is meaningless (it would
    # make tonal<->fallback "4x" more distant than bright<->dark). Use a binary
    # same/different term plus continuous centroid and RMS distances.
    if .tex1 = .tex2
        .texDiff = 0
    else
        .texDiff = 1
    endif
    .centDiff = abs(.cent1 - .cent2) / 5000
    .maxRms = max(.rms1, .rms2)
    if .maxRms > 0
        .rmsDiff = abs(.rms1 - .rms2) / .maxRms
    else
        .rmsDiff = 0
    endif
    .distance = .texDiff * 0.4 + .centDiff * 0.3 + .rmsDiff * 0.3
endproc

# ============================================================
# Strategy Settings
# ============================================================

if strategy = 1
    loop_probability = 0.2
    silence_insert_probability = 0.15
    stretch_probability = 0.2
    recall_probability = 0.25
    max_operations = 3
    silence_duration_range_s = 2
    stretch_factor_min = 0.7
    stretch_factor_max = 1.4
    strategyName$ = "Conservative"
elsif strategy = 2
    loop_probability = 0.4
    silence_insert_probability = 0.35
    stretch_probability = 0.4
    recall_probability = 0.4
    max_operations = 4
    silence_duration_range_s = 8
    stretch_factor_min = 0.4
    stretch_factor_max = 2.5
    strategyName$ = "Dramatic"
else
    loop_probability = 0.6
    silence_insert_probability = 0.5
    stretch_probability = 0.5
    recall_probability = 0.6
    max_operations = 4
    silence_duration_range_s = 20
    stretch_factor_min = 0.25
    stretch_factor_max = 4.0
    strategyName$ = "Radical"
endif

if reorder_mode = 1
    reorderName$ = "None"
elsif reorder_mode = 2
    reorderName$ = "Arch"
elsif reorder_mode = 3
    reorderName$ = "Contrast"
elsif reorder_mode = 4
    reorderName$ = "Rondo"
elsif reorder_mode = 5
    reorderName$ = "Narrative"
else
    reorderName$ = "Random"
endif

# ============================================================
# Input Validation
# ============================================================

nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

inputSound = selected("Sound")
selectObject: inputSound
inputName$ = selected$("Sound")
sourceStart = Get start time
sourceEnd = Get end time
inputDuration = Get total duration
inputChannels = Get number of channels
sampleRate = Get sampling frequency
nyquist = sampleRate / 2
analysisMaxHz = min(5000, nyquist)
effective_centroid_high_hz = min(spectral_centroid_high_hz, nyquist * 0.8)
effective_centroid_low_hz = min(spectral_centroid_low_hz, effective_centroid_high_hz * 0.5)

if inputDuration < 20
    exitScript: "Sound too short (< 20 s). Need longer material for structural analysis."
endif

# ============================================================
# Parameter validation (prevents out-of-range crashes downstream:
# arc div-by-zero, min>max detection/clip conflict, negative novelty)
# ============================================================
if min_section_duration_s > max_section_duration_s
    tmpDur = min_section_duration_s
    min_section_duration_s = max_section_duration_s
    max_section_duration_s = tmpDur
endif
if novelty_threshold < 0
    novelty_threshold = 0
endif
if novelty_threshold > 1
    novelty_threshold = 1
endif
if arc_peak_position <= 0.01
    arc_peak_position = 0.01
endif
if arc_peak_position >= 0.99
    arc_peak_position = 0.99
endif
if arc_exaggeration <= 0.01
    arc_exaggeration = 0.01
endif

# Reproducible runs when a positive seed is given. This is a formula FUNCTION
# (parenthesis call); its predictable state persists in Praat until
# random_initializeSafelyAndUnpredictably() is called (done at the end). Placed
# after the early-exit checks above so a seeded run can't strand the RNG. In
# auto mode we reset to the safe state so results don't inherit a prior script's
# predictable state.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedNote$ = "seed " + string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedNote$ = "seed auto"
endif

writeInfoLine: "=============================================="
appendInfoLine: "  Dramaturgical Structure Composer v5.4.1"
appendInfoLine: "=============================================="
appendInfoLine: "Input: ", inputName$
appendInfoLine: "Duration: ", fixed$(inputDuration, 2), " s"
appendInfoLine: "Strategy: ", strategyName$
appendInfoLine: "Reorder: ", reorderName$
appendInfoLine: ""

# ============================================================
# Convert to Mono
# ============================================================

selectObject: inputSound
if inputChannels > 1
    workSound = Convert to mono
else
    workSound = Copy: "work_sound"
endif

# ============================================================
# STEP 1: SPECTRAL NOVELTY SECTION DETECTION
# (was Step 2 in v4.0; Step 1 detectSilence removed as dead code)
# ============================================================
appendInfoLine: "[1/6] Detecting sections via spectral novelty..."

selectObject: workSound
spectrogram = To Spectrogram: 0.01, analysisMaxHz, 0.05, 20, "Gaussian"

analysisStep = 0.1
numAnalysisFrames = floor(inputDuration / analysisStep)

spectralNovelty# = zero# (numAnalysisFrames)
prevSpectrum# = zero# (100)

for i from 1 to numAnalysisFrames
    t = i * analysisStep
    analysisTime = sourceStart + t
    selectObject: spectrogram
    currentSpectrum# = zero# (100)

    for freqBin from 1 to 100
        freq = freqBin * analysisMaxHz / 100
        power = Get power at: analysisTime, freq
        if power = undefined
            power = 0
        endif
        currentSpectrum#[freqBin] = power
    endfor
    
    if i > 1
        difference = 0
        for freqBin from 1 to 100
            # Log-power spectral flux. A global gain g scales power by g^2, i.e.
            # adds a constant to log-power, which cancels in the frame-to-frame
            # difference -- so novelty no longer depends on the file's loudness.
            logCur = ln(currentSpectrum#[freqBin] + 1e-10)
            logPrev = ln(prevSpectrum#[freqBin] + 1e-10)
            diff = abs(logCur - logPrev)
            difference = difference + diff
        endfor
        spectralNovelty#[i] = difference / 100
    endif
    
    prevSpectrum# = currentSpectrum#
endfor

removeObject: spectrogram

# Normalize the novelty curve to its own peak so Novelty_threshold is a
# RELATIVE value (0-1 of peak), consistent across files of different loudness,
# rather than an absolute power number.
noveltyPeak = 0
for i from 1 to numAnalysisFrames
    if spectralNovelty#[i] > noveltyPeak
        noveltyPeak = spectralNovelty#[i]
    endif
endfor
if noveltyPeak > 0
    for i from 1 to numAnalysisFrames
        spectralNovelty#[i] = spectralNovelty#[i] / noveltyPeak
    endfor
endif

# Find section boundaries from novelty peaks
sectionBoundaries# = zero# (max_sections)
sectionBoundaries#[1] = 0
numSections = 1

for i from 2 to numAnalysisFrames - 1
    if spectralNovelty#[i] > novelty_threshold
        if spectralNovelty#[i] > spectralNovelty#[i-1] and spectralNovelty#[i] > spectralNovelty#[i+1]
            t = i * analysisStep
            if (t - sectionBoundaries#[numSections]) > min_section_duration_s
                if numSections < max_sections - 1
                    numSections = numSections + 1
                    sectionBoundaries#[numSections] = t
                endif
            endif
        endif
    endif
endfor

# Earlier accepted novelty boundaries are separated by Min duration, but a
# boundary near the end can leave a too-short final remainder. Merge it back.
if numSections > 1
    lastCandidate = sectionBoundaries#[numSections]
    if inputDuration - lastCandidate < min_section_duration_s
        numSections = numSections - 1
    endif
endif

numSections = numSections + 1
sectionBoundaries#[numSections] = inputDuration

# Enforce Max section duration by SPLITTING long spans, not by truncating them.
# The old code shortened an over-long section and silently dropped the material
# between the cut and the next boundary. Here we insert forced boundaries so the
# whole source is covered exactly once. We aim for pieces <= Max, but never
# create a piece shorter than Min: if Max and Min are incompatible for a span
# (span between Max and 2*Min), we keep one slightly-over-Max piece rather than
# sub-Min fragments (Min wins the conflict). Any such case is reported.
splitBoundaries# = zero# (max_sections)
nSplit = 0
overMaxPieces = 0
capHit = 0
for b from 1 to numSections - 1
    gapStart = sectionBoundaries#[b]
    gapEnd = sectionBoundaries#[b + 1]
    if nSplit < max_sections - 1
        nSplit = nSplit + 1
        splitBoundaries#[nSplit] = gapStart
    endif
    span = gapEnd - gapStart
    if span > max_section_duration_s
        # smallest #pieces with each <= Max, but not so many that a piece < Min
        piecesMax = ceiling(span / max_section_duration_s)
        piecesMin = max(1, floor(span / min_section_duration_s))
        pieces = min(piecesMax, piecesMin)
        pieceDur = span / pieces
        if pieceDur > max_section_duration_s + 0.001
            overMaxPieces = overMaxPieces + 1
        endif
        for k from 1 to pieces - 1
            if nSplit < max_sections - 1
                nSplit = nSplit + 1
                splitBoundaries#[nSplit] = gapStart + k * pieceDur
            else
                capHit = 1
            endif
        endfor
    endif
endfor
nSplit = nSplit + 1
splitBoundaries#[nSplit] = inputDuration
numSections = nSplit
for b from 1 to numSections
    sectionBoundaries#[b] = splitBoundaries#[b]
endfor

if overMaxPieces > 0
    appendInfoLine: "  Note: ", overMaxPieces, " span(s) kept above Max duration to avoid sub-Min fragments."
endif
if capHit = 1
    appendInfoLine: "  Note: hit the ", max_sections, "-section cap; some spans stayed longer than Max duration (whole source still covered)."
endif

# numDetectedSections is the count of analyzed source sections. It is fixed here
# and NEVER overwritten by the reordering (Rondo/Narrative change form length,
# not the number of real sections). Panel A, section analysis, and cleanup use
# this; reordering/operations/timeline use formLength (set in Step 3).
numDetectedSections = numSections - 1
appendInfoLine: "  Detected ", numDetectedSections, " section(s)"

# ============================================================
# STEP 2: ANALYZE EACH SECTION
# Rectangular extract (v5.0 fix) — v4.0 used Hanning which
# zeroed section content at start and end.
# ============================================================
appendInfoLine: "[2/6] Analyzing section characteristics..."

secStart# = zero# (max_sections)
secEnd# = zero# (max_sections)
secDur# = zero# (max_sections)
secCentroid# = zero# (max_sections)
secHarm# = zero# (max_sections)
secRms# = zero# (max_sections)
secEnergy# = zero# (max_sections)
secTexture# = zero# (max_sections)
secSound# = zero# (max_sections)

globalMaxRms = 0
globalMaxPositiveHarm = 0

for s from 1 to numDetectedSections
    secStart#[s] = sectionBoundaries#[s]
    secEnd#[s] = sectionBoundaries#[s + 1]
    secDur#[s] = secEnd#[s] - secStart#[s]
    
    # (Max section duration is now enforced by splitting boundaries in Step 1,
    # so no truncation here -- the whole source is already covered.)
    
    # v5.1: extract from inputSound (preserves channel count) for
    # the stored section that goes into the assembly pipeline.
    # v5.0 extracted from workSound which was always mono.
    selectObject: inputSound
    Extract part: sourceStart + secStart#[s], sourceStart + secEnd#[s], "rectangular", 1, "no"
    sectionSound = selected("Sound")
    
    # v5.1: separate mono temp for analysis. computeSpectralCentroid
    # calls `To Spectrum: "yes"` and computeHarmonicity calls
    # `To Harmonicity (cc)`, both of which expect mono input.
    # For mono inputs the temp is skipped (sectionMono = sectionSound).
    if inputChannels > 1
        selectObject: workSound
        Extract part: sourceStart + secStart#[s], sourceStart + secEnd#[s], "rectangular", 1, "no"
        sectionMono = selected("Sound")
    else
        sectionMono = sectionSound
    endif
    
    @computeSpectralCentroid: sectionMono
    secCentroid#[s] = computeSpectralCentroid.centroid
    
    @computeHarmonicity: sectionMono
    secHarm#[s] = computeHarmonicity.harmValue
    
    @computeRMS: sectionMono
    secRms#[s] = computeRMS.rms
    
    if secRms#[s] > globalMaxRms
        globalMaxRms = secRms#[s]
    endif
    if secHarm#[s] > globalMaxPositiveHarm
        globalMaxPositiveHarm = secHarm#[s]
    endif
    
    selectObject: sectionMono
    secEnergy#[s] = Get energy: 0, 0
    
    # v5.1: cleanup the mono temp if we created a separate one.
    # When inputChannels = 1, sectionMono IS sectionSound, so we
    # must NOT remove it (the stored sectionSound is still needed).
    if inputChannels > 1
        removeObject: sectionMono
    endif
    
    secSound#[s] = sectionSound
endfor

# ── Second pass: classify texture with RELATIVE loudness ──
# "quiet" is judged by RMS relative to the loudest section (duration-
# independent), instead of cumulative energy, which grew with section length
# and so mislabeled long-quiet vs short-loud sections. Runs after the loop so
# globalMaxRms is final.
quietRmsThreshold = globalMaxRms * 0.12
for s from 1 to numDetectedSections
    if secHarm#[s] > harmonicity_threshold_dB
        secTexture#[s] = 1
    elsif secRms#[s] < quietRmsThreshold
        secTexture#[s] = 2
    elsif secCentroid#[s] > effective_centroid_high_hz
        secTexture#[s] = 3
    elsif secCentroid#[s] < effective_centroid_low_hz
        secTexture#[s] = 4
    else
        secTexture#[s] = 5
    endif

    textureCode = secTexture#[s]
    if textureCode = 1
        textureName$ = "tonal"
    elsif textureCode = 2
        textureName$ = "quiet"
    elsif textureCode = 3
        textureName$ = "bright"
    elsif textureCode = 4
        textureName$ = "dark"
    else
        textureName$ = "mid"
    endif

    appendInfoLine: "  Section ", s, ": ", fixed$(secStart#[s], 1), "-", fixed$(secEnd#[s], 1),
        ... "s | ", textureName$,
        ... " | centroid=", fixed$(secCentroid#[s], 0), "Hz",
        ... " | RMS=", fixed$(secRms#[s], 4)
endfor

# ============================================================
# STEP 3: FORM ARCHETYPE REORDERING
# ============================================================
appendInfoLine: ""
appendInfoLine: "[3/6] Applying form archetype: ", reorderName$

# sectionOrder holds the FORM (may be longer than the detected sections, e.g.
# Rondo = 2N-1 items), so it is sized to max_timeline, not max_sections.
sectionOrder# = zero# (max_timeline)
formLength = numDetectedSections
for s from 1 to numDetectedSections
    sectionOrder#[s] = s
endfor

if reorder_mode = 1
    # None - keep original order
    appendInfoLine: "  Keeping original order."

elsif reorder_mode = 2
    # Arch: sort by RMS, place loudest near peak
    appendInfoLine: "  Arch: building to peak at ~", fixed$(arc_peak_position * 100, 0), "%"
    
    rmsSortIdx# = zero# (max_sections)
    for i from 1 to numDetectedSections
        rmsSortIdx#[i] = i
    endfor
    # Bubble sort ascending by RMS
    for i from 1 to numDetectedSections - 1
        for j from 1 to numDetectedSections - i
            jNext = j + 1
            idxJ = rmsSortIdx#[j]
            idxJNext = rmsSortIdx#[jNext]
            if secRms#[idxJ] > secRms#[idxJNext]
                rmsSortIdx#[j] = idxJNext
                rmsSortIdx#[jNext] = idxJ
            endif
        endfor
    endfor
    
    peakIdx = max(1, round(numDetectedSections * arc_peak_position))
    archPos# = zero# (max_sections)
    
    sortPos = numDetectedSections
    archPos#[peakIdx] = rmsSortIdx#[sortPos]
    sortPos = sortPos - 1
    leftSlot = peakIdx - 1
    rightSlot = peakIdx + 1
    toggle = 1
    
    while sortPos >= 1
        if toggle = 1 and leftSlot >= 1
            archPos#[leftSlot] = rmsSortIdx#[sortPos]
            leftSlot = leftSlot - 1
            sortPos = sortPos - 1
            toggle = 0
        elsif toggle = 0 and rightSlot <= numDetectedSections
            archPos#[rightSlot] = rmsSortIdx#[sortPos]
            rightSlot = rightSlot + 1
            sortPos = sortPos - 1
            toggle = 1
        elsif leftSlot >= 1
            archPos#[leftSlot] = rmsSortIdx#[sortPos]
            leftSlot = leftSlot - 1
            sortPos = sortPos - 1
        elsif rightSlot <= numDetectedSections
            archPos#[rightSlot] = rmsSortIdx#[sortPos]
            rightSlot = rightSlot + 1
            sortPos = sortPos - 1
        else
            sortPos = sortPos - 1
        endif
    endwhile
    
    for s from 1 to numDetectedSections
        sectionOrder#[s] = archPos#[s]
    endfor

elsif reorder_mode = 3
    # Contrast: greedy max-difference next
    appendInfoLine: "  Contrast: maximizing adjacent texture difference"
    
    contrastUsed# = zero# (max_sections)
    
    # Start with darkest (lowest centroid)
    bestStart = 1
    bestCent = secCentroid#[1]
    for s from 2 to numDetectedSections
        if secCentroid#[s] < bestCent
            bestCent = secCentroid#[s]
            bestStart = s
        endif
    endfor
    
    sectionOrder#[1] = bestStart
    contrastUsed#[bestStart] = 1
    
    for pos from 2 to numDetectedSections
        prevPos = pos - 1
        prevSec = sectionOrder#[prevPos]
        bestNext = 0
        bestDist = -1
        
        for candidate from 1 to numDetectedSections
            if contrastUsed#[candidate] = 0
                @textureDistance: secTexture#[prevSec], secTexture#[candidate],
                    ... secCentroid#[prevSec], secCentroid#[candidate],
                    ... secRms#[prevSec], secRms#[candidate]
                if textureDistance.distance > bestDist
                    bestDist = textureDistance.distance
                    bestNext = candidate
                endif
            endif
        endfor
        
        if bestNext > 0
            sectionOrder#[pos] = bestNext
            contrastUsed#[bestNext] = 1
        endif
    endfor

elsif reorder_mode = 4
    # Rondo: refrain + episodes
    appendInfoLine: "  Rondo: refrain + interleaved episodes"
    
    refrainIdx = 1
    bestScore = -1
    for s from 1 to numDetectedSections
        if globalMaxRms > 0
            rmsSalience = secRms#[s] / globalMaxRms
        else
            rmsSalience = 0
        endif
        if globalMaxPositiveHarm > 0
            harmSalience = max(0, secHarm#[s]) / globalMaxPositiveHarm
        else
            harmSalience = 0
        endif
        score = 0.55 * rmsSalience + 0.45 * harmSalience
        if score > bestScore
            bestScore = score
            refrainIdx = s
        endif
    endfor
    appendInfoLine: "    Refrain = section ", refrainIdx
    
    episodeList# = zero# (max_sections)
    numEpisodes = 0
    for s from 1 to numDetectedSections
        if s <> refrainIdx
            numEpisodes = numEpisodes + 1
            episodeList#[numEpisodes] = s
        endif
    endfor
    
    orderPos = 0
    for ep from 1 to numEpisodes
        if orderPos + 2 <= max_timeline
            orderPos = orderPos + 1
            sectionOrder#[orderPos] = refrainIdx
            orderPos = orderPos + 1
            sectionOrder#[orderPos] = episodeList#[ep]
        endif
    endfor
    if orderPos + 1 <= max_timeline
        orderPos = orderPos + 1
        sectionOrder#[orderPos] = refrainIdx
    endif
    formLength = orderPos

elsif reorder_mode = 5
    # Narrative: dark -> bright + appended recall of opening
    appendInfoLine: "  Narrative: dark -> bright, then return of the opening section (unprocessed)"
    
    centSortIdx# = zero# (max_sections)
    for i from 1 to numDetectedSections
        centSortIdx#[i] = i
    endfor
    for i from 1 to numDetectedSections - 1
        for j from 1 to numDetectedSections - i
            jNext = j + 1
            idxJ = centSortIdx#[j]
            idxJNext = centSortIdx#[jNext]
            if secCentroid#[idxJ] > secCentroid#[idxJNext]
                centSortIdx#[j] = idxJNext
                centSortIdx#[jNext] = idxJ
            endif
        endfor
    endfor
    
    for s from 1 to numDetectedSections
        sectionOrder#[s] = centSortIdx#[s]
    endfor
    
    # Append recall of opening (darkest)
    if formLength < max_timeline
        formLength = formLength + 1
        sectionOrder#[formLength] = centSortIdx#[1]
    endif

elsif reorder_mode = 6
    # Random swap (legacy)
    appendInfoLine: "  Random swap"
    if formLength >= 3
        numSwaps = randomInteger(1, max(1, floor(formLength / 2)))
        for sw from 1 to numSwaps
            s1 = randomInteger(1, formLength)
            s2 = randomInteger(1, formLength)
            if s1 <> s2
                temp = sectionOrder#[s1]
                sectionOrder#[s1] = sectionOrder#[s2]
                sectionOrder#[s2] = temp
                appendInfoLine: "    Swapped positions ", s1, " <-> ", s2
            endif
        endfor
    endif
endif

# Log final order
order$ = "  Final order: "
for s from 1 to formLength
    order$ = order$ + string$(sectionOrder#[s])
    if s < formLength
        order$ = order$ + " -> "
    endif
endfor
appendInfoLine: order$

# ============================================================
# STEP 4: PLAN ADDITIONAL OPERATIONS
# ============================================================
appendInfoLine: ""
appendInfoLine: "[4/6] Planning operations..."

opType# = zero# (max_operations_bound)
opTarget# = zero# (max_operations_bound)
opParam1# = zero# (max_operations_bound)

numOperations = 0

# LOOP
if allow_looping and randomUniform(0, 1) < loop_probability and formLength >= 2
    targetPos = randomInteger(1, formLength)
    targetSec = sectionOrder#[targetPos]
    
    if secDur#[targetSec] >= 15 and secDur#[targetSec] <= 60
        if numOperations < max_operations_bound
            numOperations = numOperations + 1
            opType#[numOperations] = 1
            opTarget#[numOperations] = targetPos
            opParam1#[numOperations] = randomInteger(2, 3)
            appendInfoLine: "  [LOOP] Position ", targetPos, " (sec ", targetSec, ") x ", opParam1#[numOperations]
        endif
    endif
endif

# SILENCE (after highest-RMS position — "post-peak breath")
if allow_long_silences and randomUniform(0, 1) < silence_insert_probability
    bestSilencePos = 1
    bestSilenceRms = 0
    for pos from 1 to formLength - 1
        posSection = sectionOrder#[pos]
        if secRms#[posSection] > bestSilenceRms
            bestSilenceRms = secRms#[posSection]
            bestSilencePos = pos
        endif
    endfor
    
    nextPos = bestSilencePos + 1
    if nextPos <= formLength
        nextSec = sectionOrder#[nextPos]
        peakSec = sectionOrder#[bestSilencePos]
        contrast = secRms#[peakSec] - secRms#[nextSec]
        if contrast < 0
            contrast = 0
        endif
        silDuration = 3 + contrast / max(globalMaxRms, 0.001) * silence_duration_range_s
    else
        silDuration = 3 + randomUniform(0, 1) * silence_duration_range_s * 0.5
    endif
    
    if numOperations < max_operations_bound
        numOperations = numOperations + 1
        opType#[numOperations] = 3
        opTarget#[numOperations] = bestSilencePos
        opParam1#[numOperations] = silDuration
        appendInfoLine: "  [SILENCE] Insert ", fixed$(silDuration, 1), "s after position ", bestSilencePos
    endif
endif

# STRETCH (prefer non-quiet sections)
if allow_time_stretching and randomUniform(0, 1) < stretch_probability and formLength >= 2
    bestStretchPos = 0
    for pos from 1 to formLength
        posSection = sectionOrder#[pos]
        if secTexture#[posSection] <> 2
            if bestStretchPos = 0 or randomUniform(0, 1) < 0.4
                bestStretchPos = pos
            endif
        endif
    endfor
    if bestStretchPos = 0
        bestStretchPos = randomInteger(1, formLength)
    endif
    
    if randomUniform(0, 1) < 0.5
        stretchFactor = 1.0 + randomUniform(0, 1) * (stretch_factor_max - 1.0)
        direction$ = "slower"
    else
        stretchFactor = stretch_factor_min + randomUniform(0, 1) * (1.0 - stretch_factor_min)
        direction$ = "faster"
    endif
    
    if numOperations < max_operations_bound
        numOperations = numOperations + 1
        opType#[numOperations] = 4
        opTarget#[numOperations] = bestStretchPos
        opParam1#[numOperations] = stretchFactor
        appendInfoLine: "  [STRETCH] Position ", bestStretchPos, " -> ", fixed$(stretchFactor, 2), "x (", direction$, ")"
    endif
endif

# RECALL
if allow_material_recall and randomUniform(0, 1) < recall_probability and formLength >= 3
    sourcePos = randomInteger(1, max(1, formLength - 2))
    targetPosition = randomInteger(min(sourcePos + 1, formLength), formLength)
    
    if numOperations < max_operations_bound
        numOperations = numOperations + 1
        opType#[numOperations] = 5
        opTarget#[numOperations] = sourcePos
        opParam1#[numOperations] = targetPosition
        appendInfoLine: "  [RECALL] Echo of position ", sourcePos, " after position ", targetPosition
    endif
endif

if numOperations > max_operations
    appendInfoLine: "  (limiting to ", max_operations, " operations)"
    # Remove RANDOM operations down to the cap. The old code truncated the
    # end of the list, which always dropped recall (planned last) -- e.g. every
    # capped Conservative run lost its recall. Random removal keeps the mix fair.
    while numOperations > max_operations
        dropIdx = randomInteger(1, numOperations)
        for k from dropIdx to numOperations - 1
            opType#[k] = opType#[k + 1]
            opTarget#[k] = opTarget#[k + 1]
            opParam1#[k] = opParam1#[k + 1]
        endfor
        numOperations = numOperations - 1
    endwhile
endif

appendInfoLine: "  Total: ", numOperations, " operation(s)"

# ============================================================
# STEP 5: BUILD TIMELINE
# Type codes: 0=section, 3=silence, 4=stretched section, 5=recall
# ============================================================
appendInfoLine: ""
appendInfoLine: "[5/6] Building timeline..."

timelineType# = zero# (max_timeline)
timelineSectionIdx# = zero# (max_timeline)
timelineParam# = zero# (max_timeline)
timelineTexture# = zero# (max_timeline)
timelineSound# = zero# (max_timeline)
timelineOutputStart# = zero# (max_timeline)
timelineOutputEnd# = zero# (max_timeline)
timelineLoopFlag# = zero# (max_timeline)
timelineReverseFlag# = zero# (max_timeline)

# Build per-position operation tables. Operations were planned against the
# STABLE reordered form positions (1..formLength). The old code applied them to
# a mutating timeline, so loop/silence insertions shifted the targets of later
# stretch/recall ops -- a stretch could land on an inserted silence and try to
# render secSound#[0] (a crash). Here we index every op by its intended position
# and construct the timeline in ONE forward pass, so each op hits its section.
stretchAtPos# = zero# (max_timeline)
loopAtPos#    = zero# (max_timeline)
silenceAfterPos# = zero# (max_timeline)
recallAfterActive# = zero# (max_timeline)
recallAfterSource# = zero# (max_timeline)

for op from 1 to numOperations
    thisOpType = opType#[op]
    thisOpTarget = opTarget#[op]
    thisOpParam = opParam1#[op]
    if thisOpType = 1
        if thisOpTarget >= 1 and thisOpTarget <= formLength
            loopAtPos#[thisOpTarget] = thisOpParam
        endif
    elsif thisOpType = 3
        if thisOpTarget >= 1 and thisOpTarget <= formLength
            silenceAfterPos#[thisOpTarget] = thisOpParam
        endif
    elsif thisOpType = 4
        if thisOpTarget >= 1 and thisOpTarget <= formLength
            stretchAtPos#[thisOpTarget] = thisOpParam
        endif
    elsif thisOpType = 5
        srcPos = thisOpTarget
        afterP = round(thisOpParam)
        if srcPos >= 1 and srcPos <= formLength and afterP >= 1 and afterP <= formLength
            recallAfterActive#[afterP] = 1
            # store a STABLE section id, resolved now against the fixed order
            recallAfterSource#[afterP] = sectionOrder#[srcPos]
        endif
    endif
endfor

# Single forward pass over the form.
numTimelineItems = 0
timelineFull = 0
for p from 1 to formLength
    secId = sectionOrder#[p]
    # (a) the section itself (stretched in place if flagged)
    if numTimelineItems < max_timeline
        numTimelineItems = numTimelineItems + 1
        if stretchAtPos#[p] > 0
            timelineType#[numTimelineItems] = 4
            timelineParam#[numTimelineItems] = stretchAtPos#[p]
        else
            timelineType#[numTimelineItems] = 0
            timelineParam#[numTimelineItems] = 0
        endif
        timelineSectionIdx#[numTimelineItems] = secId
    else
        timelineFull = 1
    endif
    # (b) loop copies (plain, unstretched)
    if loopAtPos#[p] > 1
        for rep from 2 to loopAtPos#[p]
            if numTimelineItems < max_timeline
                numTimelineItems = numTimelineItems + 1
                timelineType#[numTimelineItems] = 0
                timelineSectionIdx#[numTimelineItems] = secId
                timelineParam#[numTimelineItems] = 0
                timelineLoopFlag#[numTimelineItems] = 1
            endif
        endfor
    endif
    # (c) silence inserted after this position
    if silenceAfterPos#[p] > 0
        if numTimelineItems < max_timeline
            numTimelineItems = numTimelineItems + 1
            timelineType#[numTimelineItems] = 3
            timelineSectionIdx#[numTimelineItems] = 0
            timelineParam#[numTimelineItems] = silenceAfterPos#[p]
        endif
    endif
    # (d) recall inserted after this position (source section is stable)
    if recallAfterActive#[p] > 0
        if numTimelineItems < max_timeline
            numTimelineItems = numTimelineItems + 1
            timelineType#[numTimelineItems] = 5
            timelineSectionIdx#[numTimelineItems] = recallAfterSource#[p]
            timelineParam#[numTimelineItems] = 0
        endif
    endif
endfor

appendInfoLine: "  Timeline: ", numTimelineItems, " items"
if timelineFull = 1
    appendInfoLine: "  WARNING: timeline capacity (", max_timeline, ") reached; some form items were omitted."
endif

# Noise tail template (for organic silences)
if silence_mode = 2
    # v5.1: extract from inputSound (preserves channel count).
    # v5.0 used workSound which is always mono, producing mono
    # noise tails that broke Concatenate with overlap against
    # stereo timeline items.
    selectObject: inputSound
    tailOffset = max(0, inputDuration - 2.0)
    tailStart = sourceStart + tailOffset
    Extract part: tailStart, sourceEnd, "rectangular", 1, "no"
    noiseTailRaw = selected("Sound")
    
    selectObject: noiseTailRaw
    Filter (pass Hann band): 0, 400, 50
    noiseTailFiltered = selected("Sound")
    removeObject: noiseTailRaw
    
    selectObject: noiseTailFiltered
    Scale peak: 0.02
    noiseTailTemplate = noiseTailFiltered
endif

# Render each timeline item to a Sound
for t from 1 to numTimelineItems
    itemType = timelineType#[t]
    secIdx = timelineSectionIdx#[t]
    param = timelineParam#[t]
    
    if itemType = 0 or itemType = 4
        # Regular or stretched section
        selectObject: secSound#[secIdx]
        Copy: "timeline_item_" + string$(t)
        itemSound = selected("Sound")
        
        if itemType = 4
            selectObject: itemSound
            itemDur = Get total duration
            itemChannels = Get number of channels
            if itemDur > 0
                safePitchFloor = max(75, 3.0 / itemDur + 5)
                if itemChannels = 1
                    # Mono path (unchanged from v5.0)
                    To Manipulation: 0.01, safePitchFloor, 600
                    manipObj = selected("Manipulation")
                    Extract duration tier
                    durTier = selected("DurationTier")
                    Add point: 0, param
                    selectObject: manipObj
                    plusObject: durTier
                    Replace duration tier
                    selectObject: manipObj
                    Get resynthesis (overlap-add)
                    stretched = selected("Sound")
                    removeObject: manipObj, durTier, itemSound
                    itemSound = stretched
                else
                    # v5.1 multichannel path: To Manipulation is
                    # mono-only, so split into channels, stretch each
                    # with the SAME duration factor (preserves the
                    # spatial image), then recombine. Generalized to
                    # N channels (handles stereo, quad, octo, etc.).
                    selectObject: itemSound
                    Extract all channels
                    chanIn# = zero# (itemChannels)
                    for ch from 1 to itemChannels
                        chanIn#[ch] = selected("Sound", ch)
                    endfor
                    
                    chanOut# = zero# (itemChannels)
                    for ch from 1 to itemChannels
                        selectObject: chanIn#[ch]
                        To Manipulation: 0.01, safePitchFloor, 600
                        manipC = selected("Manipulation")
                        Extract duration tier
                        durTierC = selected("DurationTier")
                        Add point: 0, param
                        selectObject: manipC
                        plusObject: durTierC
                        Replace duration tier
                        selectObject: manipC
                        Get resynthesis (overlap-add)
                        chanOut#[ch] = selected("Sound")
                        removeObject: manipC, durTierC, chanIn#[ch]
                    endfor
                    
                    # Recombine all stretched channels
                    selectObject: chanOut#[1]
                    for ch from 2 to itemChannels
                        plusObject: chanOut#[ch]
                    endfor
                    Combine to stereo
                    stretched = selected("Sound")
                    for ch from 1 to itemChannels
                        removeObject: chanOut#[ch]
                    endfor
                    removeObject: itemSound
                    itemSound = stretched
                endif
            endif
        endif
        
        # Safety limiter only
        selectObject: itemSound
        peakAbs = Get absolute extremum: 0, 0, "None"
        if peakAbs > 1.0
            Scale peak: 0.99
        endif
        
        timelineSound#[t] = itemSound
        timelineTexture#[t] = secTexture#[secIdx]
    
    elsif itemType = 5
        # RECALL: transformed copy of a section
        selectObject: secSound#[secIdx]
        Copy: "recall_item_" + string$(t)
        itemSound = selected("Sound")
        
        recallReversed = 0
        if recall_reverse and randomUniform(0, 1) < 0.35
            selectObject: itemSound
            Reverse
            recallReversed = 1
        endif
        
        if recall_lowpass
            selectObject: itemSound
            Filter (pass Hann band): 0, recall_lowpass_hz, 200
            filteredRecall = selected("Sound")
            removeObject: itemSound
            itemSound = filteredRecall
        endif
        
        selectObject: itemSound
        Multiply: recall_amplitude_factor
        
        selectObject: itemSound
        peakAbs = Get absolute extremum: 0, 0, "None"
        if peakAbs > 1.0
            Scale peak: 0.99
        endif
        
        timelineSound#[t] = itemSound
        timelineTexture#[t] = secTexture#[secIdx]
        timelineReverseFlag#[t] = recallReversed
    
    elsif itemType = 3
        # SILENCE
        silDur = param
        if silence_mode = 2 and silDur > 0.1
            selectObject: noiseTailTemplate
            Copy: "organic_silence_" + string$(t)
            orgSil = selected("Sound")
            
            selectObject: orgSil
            currentSilDur = Get total duration
            while currentSilDur < silDur
                selectObject: orgSil, noiseTailTemplate
                Concatenate
                temp = selected("Sound")
                removeObject: orgSil
                orgSil = temp
                selectObject: orgSil
                currentSilDur = Get total duration
            endwhile
            
            selectObject: orgSil
            Extract part: 0, silDur, "rectangular", 1, "no"
            trimmedSil = selected("Sound")
            removeObject: orgSil
            
            selectObject: trimmedSil
            fadeDur = min(0.5, silDur * 0.2)
            Fade in: 0, 0, fadeDur, "yes"
            Fade out: 0, silDur, -fadeDur, "yes"
            
            timelineSound#[t] = trimmedSil
        else
            # v5.1: channel count matches input. v5.0 hardcoded `1`,
            # producing mono silence that broke Concatenate with
            # overlap against stereo timeline items (Praat requires
            # matching channel counts for concatenation).
            Create Sound from formula: "silence_" + string$(t), inputChannels, 0, silDur, sampleRate, "0"
            timelineSound#[t] = selected("Sound")
        endif
        timelineTexture#[t] = 0
    endif
endfor

# ============================================================
# STEP 6: ASSEMBLE WITH TEXTURE-AWARE CROSSFADES
# Track output start/end times for visualization
# ============================================================
appendInfoLine: ""
appendInfoLine: "[6/6] Assembling with texture-aware crossfades..."

selectObject: timelineSound#[1]
finalOutput = Copy: "assembling"
firstDur = Get total duration
timelineOutputStart#[1] = 0
timelineOutputEnd#[1] = firstDur

for t from 2 to numTimelineItems
    tPrev = t - 1
    fromTex = timelineTexture#[tPrev]
    toTex = timelineTexture#[t]

    @getCrossfadeDuration: fromTex, toTex
    targetCrossfade = getCrossfadeDuration.duration

    selectObject: finalOutput
    currentDur = Get total duration
    selectObject: timelineSound#[tPrev]
    prevDur = Get total duration
    selectObject: timelineSound#[t]
    nextDur = Get total duration

    # Keep each joint inside the two adjacent timeline items.
    safeCrossfade = min(targetCrossfade, min(prevDur, nextDur) * 0.4)

    # Praat concatenates by Object-list order. Copy the next item now, after
    # finalOutput, so the join order is guaranteed: finalOutput -> nextForJoin.
    selectObject: timelineSound#[t]
    nextForJoin = Copy: "join_item_" + string$(t)

    if safeCrossfade > 0.002 and prevDur > safeCrossfade * 2 and nextDur > safeCrossfade * 2
        timelineOutputStart#[t] = currentDur - safeCrossfade
        selectObject: finalOutput, nextForJoin
        Concatenate with overlap: safeCrossfade
        temp = selected("Sound")
    else
        timelineOutputStart#[t] = currentDur
        selectObject: finalOutput, nextForJoin
        Concatenate
        temp = selected("Sound")
    endif

    removeObject: finalOutput, nextForJoin
    finalOutput = temp

    selectObject: finalOutput
    timelineOutputEnd#[t] = Get total duration
endfor

# Cleanup timeline sounds
for t from 1 to numTimelineItems
    snd = timelineSound#[t]
    if snd > 0
        removeObject: snd
    endif
endfor

if silence_mode = 2
    removeObject: noiseTailTemplate
endif

# ============================================================
# Tension Arc
# ============================================================
selectObject: finalOutput
outputDuration = Get total duration

if apply_tension_arc
    Formula: ~ self * (0.3 + 0.7 * (if x/outputDuration <= arc_peak_position then x/outputDuration/arc_peak_position else 1-(x/outputDuration-arc_peak_position)/(1-arc_peak_position) fi) ^ arc_exaggeration)
    appendInfoLine: "  Tension arc applied (peak ", fixed$(arc_peak_position * 100, 0), "%, exag ", fixed$(arc_exaggeration, 1), ")"
endif

# Safety limiter (no normalize)
peakAbs = Get absolute extremum: 0, 0, "None"
if peakAbs > 1.0
    Scale peak: 0.99
endif

# Final output name with strategy + reorder suffix
selectObject: finalOutput
Rename: inputName$ + "_dramat_" + strategyName$ + "_" + reorderName$
finalOutput = selected("Sound")
outputDuration = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: ""
appendInfoLine: "  Output: ", fixed$(outputDuration, 2), " s (input was ", fixed$(inputDuration, 2), " s)"
appendInfoLine: "  Peak: ", fixed$(finalPeak, 3)

# ============================================================
# VISUALIZATION  (current Praat AudioTools suite styling)
# Source -> Dramaturgical form map -> Output -> Summary.
# Fill color in the structural map has one meaning: texture class.
# Operation type is encoded textually (LOOP / SIL / STR / REC), not by color.
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    displayName$ = replace$(inputName$, "_", " ", 0)

    # Zero-based mono display copies.
    selectObject: inputSound
    if inputChannels > 1
        vizInput = Convert to mono
    else
        vizInput = Copy: "viz_input"
    endif
    selectObject: vizInput
    vizInputStart = Get start time
    Shift times by: -vizInputStart

    selectObject: finalOutput
    outNumCh = Get number of channels
    if outNumCh > 1
        vizOutput = Convert to mono
    else
        vizOutput = Copy: "viz_output"
    endif
    selectObject: vizOutput
    vizOutputStart = Get start time
    Shift times by: -vizOutputStart

    # Shared source/output amplitude scale.
    selectObject: vizInput
    inputPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: vizOutput
    outputPeakViz = Get absolute extremum: 0, 0, "None"
    sharedPeakViz = max(inputPeakViz, outputPeakViz)
    if sharedPeakViz < 0.001
        sharedPeakViz = 0.001
    endif
    sharedAmpViz = 1.15 * sharedPeakViz

    # Count operation types for the summary.
    nLoop = 0
    nSil = 0
    nStr = 0
    nRec = 0
    for op from 1 to numOperations
        if opType#[op] = 1
            nLoop = nLoop + 1
        elsif opType#[op] = 3
            nSil = nSil + 1
        elsif opType#[op] = 4
            nStr = nStr + 1
        elsif opType#[op] = 5
            nRec = nRec + 1
        endif
    endfor

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Dramaturgical Structure Composer##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Dramaturgical Structure Composer.praat  |  " + displayName$ + "  |  " + strategyName$ + " / " + reorderName$ + "  |  " + string$(numDetectedSections) + " sections -> " + string$(numTimelineItems) + " timeline items"

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 2.00
    Select inner viewport: 0.55, 7.75, 0.82, 1.88
    Axes: 0, inputDuration, -sharedAmpViz, sharedAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, inputDuration, -sharedAmpViz, sharedAmpViz

    # Section tint: color means texture class throughout the structural view.
    for s from 1 to numDetectedSections
        sStart = secStart#[s]
        sEnd = secEnd#[s]
        tex = secTexture#[s]
        if tex = 1
            tintColor$ = "{0.90, 0.95, 1.00}"
        elsif tex = 2
            tintColor$ = "{0.94, 0.94, 0.94}"
        elsif tex = 3
            tintColor$ = "{1.00, 0.98, 0.86}"
        elsif tex = 4
            tintColor$ = "{0.94, 0.91, 0.99}"
        else
            tintColor$ = "{1.00, 0.94, 0.87}"
        endif
        Paint rectangle: tintColor$, sStart, sEnd, -sharedAmpViz, sharedAmpViz
    endfor

    selectObject: vizInput
    Colour: "{0.56, 0.56, 0.60}"
    Draw: 0, inputDuration, -sharedAmpViz, sharedAmpViz, "no", "Curve"

    Colour: "{0.58, 0.58, 0.60}"
    Line width: 1
    for s from 2 to numDetectedSections
        boundary = secStart#[s]
        Draw line: boundary, -sharedAmpViz, boundary, sharedAmpViz
    endfor

    Font size: 6
    Colour: "{0.25, 0.25, 0.30}"
    for s from 1 to numDetectedSections
        midT = (secStart#[s] + secEnd#[s]) / 2
        if secEnd#[s] - secStart#[s] > 0.025 * inputDuration
            Text: midT, "centre", 0.82 * sharedAmpViz, "half", string$(s)
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, inputDuration, -sharedAmpViz, sharedAmpViz
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * inputDuration, "left", -0.82 * sharedAmpViz, "half", string$(numDetectedSections) + " detected sections  |  section tint = texture class"

    # ----------------------------------------------------------
    # DRAMATURGICAL FORM MAP
    # Detected source sections and output timeline share normalized x.
    # Thin neutral connectors expose the actual source-to-output mapping.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.15, 4.80
    Select inner viewport: 0.55, 7.75, 2.32, 4.66
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Dramaturgical form map##"

    # Compact legend. Fill color has exactly one semantic role: texture class.
    legendY = 0.91
    legendBoxW = 0.018
    legendBoxH = 0.035
    Font size: 5
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", legendY, "half", "fill = texture:"

    Paint rectangle: "{0.70, 0.85, 1.00}", 0.16, 0.16 + legendBoxW, legendY - legendBoxH/2, legendY + legendBoxH/2
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.183, "left", legendY, "half", "tonal"
    Paint rectangle: "{0.88, 0.88, 0.88}", 0.255, 0.255 + legendBoxW, legendY - legendBoxH/2, legendY + legendBoxH/2
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.278, "left", legendY, "half", "quiet"
    Paint rectangle: "{1.00, 0.94, 0.62}", 0.35, 0.35 + legendBoxW, legendY - legendBoxH/2, legendY + legendBoxH/2
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.373, "left", legendY, "half", "bright"
    Paint rectangle: "{0.78, 0.70, 0.94}", 0.455, 0.455 + legendBoxW, legendY - legendBoxH/2, legendY + legendBoxH/2
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.478, "left", legendY, "half", "dark"
    Paint rectangle: "{0.96, 0.82, 0.62}", 0.545, 0.545 + legendBoxW, legendY - legendBoxH/2, legendY + legendBoxH/2
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.568, "left", legendY, "half", "mid"
    Text: 0.66, "left", legendY, "half", "labels = LOOP / SIL / STR / REC"

    # Row labels use one aligned left anchor.
    labelX = 0.02
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: labelX, "left", 0.77, "half", "Detected sections"
    Text: labelX, "left", 0.49, "half", "Output timeline"
    Text: labelX, "left", 0.17, "half", "Tension arc"

    rowX1 = 0.16
    rowX2 = 0.98
    rowW = rowX2 - rowX1
    sourceY1 = 0.67
    sourceY2 = 0.83
    outputY1 = 0.39
    outputY2 = 0.57

    # Source row.
    for s from 1 to numDetectedSections
        x1 = rowX1 + rowW * secStart#[s] / inputDuration
        x2 = rowX1 + rowW * secEnd#[s] / inputDuration
        tex = secTexture#[s]
        if tex = 1
            blockColor$ = "{0.70, 0.85, 1.00}"
        elsif tex = 2
            blockColor$ = "{0.88, 0.88, 0.88}"
        elsif tex = 3
            blockColor$ = "{1.00, 0.94, 0.62}"
        elsif tex = 4
            blockColor$ = "{0.78, 0.70, 0.94}"
        else
            blockColor$ = "{0.96, 0.82, 0.62}"
        endif
        Paint rectangle: blockColor$, x1, x2, sourceY1, sourceY2
        Colour: "{0.48, 0.48, 0.50}"
        Draw rectangle: x1, x2, sourceY1, sourceY2
        if x2 - x1 > 0.028
            Font size: 5
            Colour: "{0.20, 0.20, 0.24}"
            Text: (x1 + x2) / 2, "centre", (sourceY1 + sourceY2) / 2, "half", string$(s)
        endif
    endfor

    # Neutral source-to-output connectors, drawn before output blocks.
    Colour: "{0.82, 0.82, 0.84}"
    Line width: 0.8
    for t from 1 to numTimelineItems
        secIdxV = timelineSectionIdx#[t]
        itemType = timelineType#[t]
        if secIdxV >= 1 and secIdxV <= numDetectedSections and itemType <> 3
            srcMid = rowX1 + rowW * ((secStart#[secIdxV] + secEnd#[secIdxV]) / 2) / inputDuration
            outMid = rowX1 + rowW * ((timelineOutputStart#[t] + timelineOutputEnd#[t]) / 2) / outputDuration
            Draw line: srcMid, sourceY1, outMid, outputY2
        endif
    endfor
    Line width: 1

    # Output timeline row.
    for t from 1 to numTimelineItems
        x1 = rowX1 + rowW * timelineOutputStart#[t] / outputDuration
        x2 = rowX1 + rowW * timelineOutputEnd#[t] / outputDuration
        tex = timelineTexture#[t]
        itemType = timelineType#[t]

        if tex = 0
            blockColor$ = "{0.82, 0.82, 0.84}"
        elsif tex = 1
            blockColor$ = "{0.70, 0.85, 1.00}"
        elsif tex = 2
            blockColor$ = "{0.88, 0.88, 0.88}"
        elsif tex = 3
            blockColor$ = "{1.00, 0.94, 0.62}"
        elsif tex = 4
            blockColor$ = "{0.78, 0.70, 0.94}"
        else
            blockColor$ = "{0.96, 0.82, 0.62}"
        endif

        Paint rectangle: blockColor$, x1, x2, outputY1, outputY2
        Colour: "{0.42, 0.42, 0.45}"
        if itemType = 3
            Dashed line
        else
            Solid line
        endif
        Draw rectangle: x1, x2, outputY1, outputY2
        Solid line

        secIdxV = timelineSectionIdx#[t]
        if itemType = 3
            opLabel$ = "SIL"
        elsif itemType = 4
            opLabel$ = string$(secIdxV) + " STR"
        elsif itemType = 5
            if timelineReverseFlag#[t] = 1
                opLabel$ = string$(secIdxV) + " REC-R"
            else
                opLabel$ = string$(secIdxV) + " REC"
            endif
        elsif timelineLoopFlag#[t] = 1
            opLabel$ = string$(secIdxV) + " LOOP"
        else
            opLabel$ = string$(secIdxV)
        endif

        if x2 - x1 > 0.032
            Font size: 5
            Colour: "{0.20, 0.20, 0.24}"
            Text: (x1 + x2) / 2, "centre", (outputY1 + outputY2) / 2, "half", opLabel$
        endif
    endfor

    # Tension arc integrated into the structural map.
    arcX1 = rowX1
    arcX2 = rowX2
    arcYBase = 0.08
    arcYSpan = 0.18
    Colour: "{0.83, 0.83, 0.85}"
    Draw line: arcX1, arcYBase, arcX2, arcYBase

    if apply_tension_arc
        Colour: "{0.72, 0.30, 0.30}"
        Line width: 1.6
        numDrawPoints = 160
        for dp from 1 to numDrawPoints - 1
            p1 = (dp - 1) / numDrawPoints
            p2 = dp / numDrawPoints
            if p1 <= arc_peak_position
                shape1 = p1 / arc_peak_position
            else
                shape1 = 1.0 - (p1 - arc_peak_position) / (1.0 - arc_peak_position)
            endif
            if p2 <= arc_peak_position
                shape2 = p2 / arc_peak_position
            else
                shape2 = 1.0 - (p2 - arc_peak_position) / (1.0 - arc_peak_position)
            endif
            gain1 = 0.3 + 0.7 * shape1 ^ arc_exaggeration
            gain2 = 0.3 + 0.7 * shape2 ^ arc_exaggeration
            xx1 = arcX1 + (arcX2 - arcX1) * p1
            xx2 = arcX1 + (arcX2 - arcX1) * p2
            yy1 = arcYBase + arcYSpan * gain1
            yy2 = arcYBase + arcYSpan * gain2
            Draw line: xx1, yy1, xx2, yy2
        endfor
        Line width: 1
        peakX = arcX1 + (arcX2 - arcX1) * arc_peak_position
        Colour: "{0.55, 0.35, 0.35}"
        Dotted line
        Draw line: peakX, arcYBase, peakX, arcYBase + arcYSpan
        Solid line
        Font size: 5
        Text: peakX + 0.008, "left", arcYBase + arcYSpan, "half", "peak " + fixed$(arc_peak_position * 100, 0) + "%"
    else
        Colour: "{0.58, 0.58, 0.60}"
        Dashed line
        Draw line: arcX1, arcYBase + arcYSpan, arcX2, arcYBase + arcYSpan
        Solid line
        Font size: 5
        Text: (arcX1 + arcX2) / 2, "centre", arcYBase + 0.09, "half", "disabled"
    endif

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.95, 6.05
    Select inner viewport: 0.55, 7.75, 5.12, 5.93
    Axes: 0, outputDuration, -sharedAmpViz, sharedAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, -sharedAmpViz, sharedAmpViz

    Colour: "{0.85, 0.85, 0.88}"
    Dotted line
    for t from 2 to numTimelineItems
        boundary = timelineOutputStart#[t]
        Draw line: boundary, -sharedAmpViz, boundary, sharedAmpViz
    endfor
    Solid line

    selectObject: vizOutput
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, outputDuration, -sharedAmpViz, sharedAmpViz, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, outputDuration, -sharedAmpViz, sharedAmpViz
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * outputDuration, "left", 0.82 * sharedAmpViz, "half", string$(numTimelineItems) + " timeline items  |  dotted lines = item boundaries"

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    if apply_tension_arc
        arcStr$ = "ON (peak " + fixed$(arc_peak_position, 2) + ", exag " + fixed$(arc_exaggeration, 1) + ")"
    else
        arcStr$ = "OFF"
    endif
    if crossfade_mode = 1
        xfStr$ = "fixed 30 ms"
    else
        xfStr$ = "texture-aware"
    endif
    if silence_mode = 1
        silStr$ = "digital zero"
    else
        silStr$ = "noise tail"
    endif

    Select outer viewport: 0, 8, 6.20, 7.08
    Select inner viewport: 0.30, 7.80, 6.27, 7.01
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", strategyName$ + " / " + reorderName$ + "  |  " + string$(numDetectedSections) + " sections -> " + string$(numTimelineItems) + " items  |  Ops: LOOP " + string$(nLoop) + " / SIL " + string$(nSil) + " / STR " + string$(nStr) + " / REC " + string$(nRec)
    Text: 0.02, "left", 0.18, "half", "Crossfade " + xfStr$ + "  |  Silence " + silStr$ + "  |  Arc " + arcStr$ + "  |  " + fixed$(inputDuration, 1) + " s -> " + fixed$(outputDuration, 1) + " s  |  peak " + fixed$(finalPeak, 3)

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizInput, vizOutput
    selectObject: finalOutput
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: workSound
for s from 1 to numDetectedSections
    snd = secSound#[s]
    if snd > 0
        removeObject: snd
    endif
endfor

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: "Output: ", inputName$, "_dramat_", strategyName$, "_", reorderName$
appendInfoLine: "Random: ", seedNote$

if play_output
    Play
endif

# Undo the predictable-RNG state so it doesn't persist across later Praat work.
if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

selectObject: finalOutput
