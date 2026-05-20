# ============================================================
# Praat AudioTools - Dramaturgical_Structure_Composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 5.1 (2026)
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

form Dramaturgical Structure Composer v5.1
    positive Min_section_duration_s 8
    positive Max_section_duration_s 90
    real Novelty_threshold 0.25
    real Harmonicity_threshold 0.15
    optionmenu Strategy: 2
        option Conservative (subtle)
        option Dramatic (major)
        option Radical (complete)
    optionmenu Reorder_mode: 3
        option None (original order)
        option Arch (build to peak)
        option Contrast (max adjacent diff)
        option Rondo (refrain + episodes)
        option Narrative (dark to bright + recall)
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
max_timeline = 400

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
    .texDiff = abs(.tex1 - .tex2)
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
    max_operations = 6
    silence_duration_range_s = 8
    stretch_factor_min = 0.4
    stretch_factor_max = 2.5
    strategyName$ = "Dramatic"
else
    loop_probability = 0.6
    silence_insert_probability = 0.5
    stretch_probability = 0.5
    recall_probability = 0.6
    max_operations = 10
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
inputDuration = Get total duration
inputChannels = Get number of channels
sampleRate = Get sampling frequency

if inputDuration < 20
    exitScript: "Sound too short (< 20 s). Need longer material for structural analysis."
endif

writeInfoLine: "=============================================="
appendInfoLine: "  Dramaturgical Structure Composer v5.1"
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
spectrogram = To Spectrogram: 0.01, 5000, 0.05, 20, "Gaussian"

analysisStep = 0.1
numAnalysisFrames = floor(inputDuration / analysisStep)

spectralNovelty# = zero# (numAnalysisFrames)
prevSpectrum# = zero# (100)

for i from 1 to numAnalysisFrames
    t = i * analysisStep
    selectObject: spectrogram
    currentSpectrum# = zero# (100)
    
    for freqBin from 1 to 100
        freq = freqBin * 50
        power = Get power at: t, freq
        if power = undefined
            power = 0
        endif
        currentSpectrum#[freqBin] = power
    endfor
    
    if i > 1
        difference = 0
        for freqBin from 1 to 100
            diff = abs(currentSpectrum#[freqBin] - prevSpectrum#[freqBin])
            difference = difference + diff
        endfor
        spectralNovelty#[i] = difference / 100
    endif
    
    prevSpectrum# = currentSpectrum#
endfor

removeObject: spectrogram

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

numSections = numSections + 1
sectionBoundaries#[numSections] = inputDuration

actualNumSections = numSections - 1
appendInfoLine: "  Detected ", actualNumSections, " section(s)"

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

for s from 1 to actualNumSections
    secStart#[s] = sectionBoundaries#[s]
    secEnd#[s] = sectionBoundaries#[s + 1]
    secDur#[s] = secEnd#[s] - secStart#[s]
    
    if secDur#[s] > max_section_duration_s
        secEnd#[s] = secStart#[s] + max_section_duration_s
        secDur#[s] = max_section_duration_s
    endif
    
    # v5.1: extract from inputSound (preserves channel count) for
    # the stored section that goes into the assembly pipeline.
    # v5.0 extracted from workSound which was always mono.
    selectObject: inputSound
    Extract part: secStart#[s], secEnd#[s], "rectangular", 1, "no"
    sectionSound = selected("Sound")
    
    # v5.1: separate mono temp for analysis. computeSpectralCentroid
    # calls `To Spectrum: "yes"` and computeHarmonicity calls
    # `To Harmonicity (cc)`, both of which expect mono input.
    # For mono inputs the temp is skipped (sectionMono = sectionSound).
    if inputChannels > 1
        selectObject: workSound
        Extract part: secStart#[s], secEnd#[s], "rectangular", 1, "no"
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
    
    selectObject: sectionMono
    secEnergy#[s] = Get energy: 0, 0
    
    # v5.1: cleanup the mono temp if we created a separate one.
    # When inputChannels = 1, sectionMono IS sectionSound, so we
    # must NOT remove it (the stored sectionSound is still needed).
    if inputChannels > 1
        removeObject: sectionMono
    endif
    
    # Classify texture: 1=tonal, 2=quiet, 3=bright, 4=dark, 5=fallback
    if secHarm#[s] > harmonicity_threshold
        secTexture#[s] = 1
    elsif secEnergy#[s] < 0.001
        secTexture#[s] = 2
    elsif secCentroid#[s] > spectral_centroid_high_hz
        secTexture#[s] = 3
    elsif secCentroid#[s] < spectral_centroid_low_hz
        secTexture#[s] = 4
    else
        secTexture#[s] = 5
    endif
    
    secSound#[s] = sectionSound
    
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

sectionOrder# = zero# (max_sections)
for s from 1 to actualNumSections
    sectionOrder#[s] = s
endfor

if reorder_mode = 1
    # None - keep original order
    appendInfoLine: "  Keeping original order."

elsif reorder_mode = 2
    # Arch: sort by RMS, place loudest near peak
    appendInfoLine: "  Arch: building to peak at ~", fixed$(arc_peak_position * 100, 0), "%"
    
    rmsSortIdx# = zero# (max_sections)
    for i from 1 to actualNumSections
        rmsSortIdx#[i] = i
    endfor
    # Bubble sort ascending by RMS
    for i from 1 to actualNumSections - 1
        for j from 1 to actualNumSections - i
            jNext = j + 1
            idxJ = rmsSortIdx#[j]
            idxJNext = rmsSortIdx#[jNext]
            if secRms#[idxJ] > secRms#[idxJNext]
                rmsSortIdx#[j] = idxJNext
                rmsSortIdx#[jNext] = idxJ
            endif
        endfor
    endfor
    
    peakIdx = max(1, round(actualNumSections * arc_peak_position))
    archPos# = zero# (max_sections)
    
    sortPos = actualNumSections
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
        elsif toggle = 0 and rightSlot <= actualNumSections
            archPos#[rightSlot] = rmsSortIdx#[sortPos]
            rightSlot = rightSlot + 1
            sortPos = sortPos - 1
            toggle = 1
        elsif leftSlot >= 1
            archPos#[leftSlot] = rmsSortIdx#[sortPos]
            leftSlot = leftSlot - 1
            sortPos = sortPos - 1
        elsif rightSlot <= actualNumSections
            archPos#[rightSlot] = rmsSortIdx#[sortPos]
            rightSlot = rightSlot + 1
            sortPos = sortPos - 1
        else
            sortPos = sortPos - 1
        endif
    endwhile
    
    for s from 1 to actualNumSections
        sectionOrder#[s] = archPos#[s]
    endfor

elsif reorder_mode = 3
    # Contrast: greedy max-difference next
    appendInfoLine: "  Contrast: maximizing adjacent texture difference"
    
    contrastUsed# = zero# (max_sections)
    
    # Start with darkest (lowest centroid)
    bestStart = 1
    bestCent = secCentroid#[1]
    for s from 2 to actualNumSections
        if secCentroid#[s] < bestCent
            bestCent = secCentroid#[s]
            bestStart = s
        endif
    endfor
    
    sectionOrder#[1] = bestStart
    contrastUsed#[bestStart] = 1
    
    for pos from 2 to actualNumSections
        prevPos = pos - 1
        prevSec = sectionOrder#[prevPos]
        bestNext = 0
        bestDist = -1
        
        for candidate from 1 to actualNumSections
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
    bestScore = 0
    for s from 1 to actualNumSections
        score = abs(secHarm#[s]) + abs(secCentroid#[s] - 1500) / 1500
        if score > bestScore
            bestScore = score
            refrainIdx = s
        endif
    endfor
    appendInfoLine: "    Refrain = section ", refrainIdx
    
    episodeList# = zero# (max_sections)
    numEpisodes = 0
    for s from 1 to actualNumSections
        if s <> refrainIdx
            numEpisodes = numEpisodes + 1
            episodeList#[numEpisodes] = s
        endif
    endfor
    
    orderPos = 0
    for ep from 1 to numEpisodes
        orderPos = orderPos + 1
        sectionOrder#[orderPos] = refrainIdx
        orderPos = orderPos + 1
        sectionOrder#[orderPos] = episodeList#[ep]
    endfor
    orderPos = orderPos + 1
    sectionOrder#[orderPos] = refrainIdx
    actualNumSections = orderPos

elsif reorder_mode = 5
    # Narrative: dark -> bright + appended recall of opening
    appendInfoLine: "  Narrative: dark -> build -> bright -> recall -> fade"
    
    centSortIdx# = zero# (max_sections)
    for i from 1 to actualNumSections
        centSortIdx#[i] = i
    endfor
    for i from 1 to actualNumSections - 1
        for j from 1 to actualNumSections - i
            jNext = j + 1
            idxJ = centSortIdx#[j]
            idxJNext = centSortIdx#[jNext]
            if secCentroid#[idxJ] > secCentroid#[idxJNext]
                centSortIdx#[j] = idxJNext
                centSortIdx#[jNext] = idxJ
            endif
        endfor
    endfor
    
    for s from 1 to actualNumSections
        sectionOrder#[s] = centSortIdx#[s]
    endfor
    
    # Append recall of opening (darkest)
    if actualNumSections < max_sections
        actualNumSections = actualNumSections + 1
        sectionOrder#[actualNumSections] = centSortIdx#[1]
    endif

elsif reorder_mode = 6
    # Random swap (legacy)
    appendInfoLine: "  Random swap"
    if actualNumSections >= 3
        numSwaps = randomInteger(1, max(1, floor(actualNumSections / 2)))
        for sw from 1 to numSwaps
            s1 = randomInteger(1, actualNumSections)
            s2 = randomInteger(1, actualNumSections)
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
for s from 1 to actualNumSections
    order$ = order$ + string$(sectionOrder#[s])
    if s < actualNumSections
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
if allow_looping and randomUniform(0, 1) < loop_probability and actualNumSections >= 2
    targetPos = randomInteger(1, actualNumSections)
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
    for pos from 1 to actualNumSections - 1
        posSection = sectionOrder#[pos]
        if secRms#[posSection] > bestSilenceRms
            bestSilenceRms = secRms#[posSection]
            bestSilencePos = pos
        endif
    endfor
    
    nextPos = bestSilencePos + 1
    if nextPos <= actualNumSections
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
if allow_time_stretching and randomUniform(0, 1) < stretch_probability and actualNumSections >= 2
    bestStretchPos = 0
    for pos from 1 to actualNumSections
        posSection = sectionOrder#[pos]
        if secTexture#[posSection] <> 2
            if bestStretchPos = 0 or randomUniform(0, 1) < 0.4
                bestStretchPos = pos
            endif
        endif
    endfor
    if bestStretchPos = 0
        bestStretchPos = randomInteger(1, actualNumSections)
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
if allow_material_recall and randomUniform(0, 1) < recall_probability and actualNumSections >= 3
    sourcePos = randomInteger(1, max(1, actualNumSections - 2))
    targetPosition = randomInteger(min(sourcePos + 1, actualNumSections), actualNumSections)
    
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
    numOperations = max_operations
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

# Initial: one entry per reordered section
numTimelineItems = 0
for s from 1 to actualNumSections
    if numTimelineItems < max_timeline
        numTimelineItems = numTimelineItems + 1
        timelineType#[numTimelineItems] = 0
        timelineSectionIdx#[numTimelineItems] = sectionOrder#[s]
        timelineParam#[numTimelineItems] = 0
    endif
endfor

# Apply operations
for op from 1 to numOperations
    thisOpType = opType#[op]
    thisOpTarget = opTarget#[op]
    thisOpParam = opParam1#[op]
    
    if thisOpType = 1
        # LOOP: insert (loopCount-1) extra copies after target position
        loopCount = thisOpParam
        insertPos = min(thisOpTarget, numTimelineItems)
        if insertPos > 0 and numTimelineItems + loopCount - 1 <= max_timeline
            targetSecIdx = timelineSectionIdx#[insertPos]
            shiftBy = loopCount - 1
            # Shift items insertPos+1..end forward by shiftBy (reverse iteration)
            for offset from 0 to numTimelineItems - insertPos - 1
                srcT = numTimelineItems - offset
                dstT = srcT + shiftBy
                timelineType#[dstT] = timelineType#[srcT]
                timelineSectionIdx#[dstT] = timelineSectionIdx#[srcT]
                timelineParam#[dstT] = timelineParam#[srcT]
            endfor
            # Fill the loop copies
            for rep from 1 to loopCount - 1
                repPos = insertPos + rep
                timelineType#[repPos] = 0
                timelineSectionIdx#[repPos] = targetSecIdx
                timelineParam#[repPos] = 0
            endfor
            numTimelineItems = numTimelineItems + shiftBy
        endif
    
    elsif thisOpType = 3
        # SILENCE: insert after target position
        insertPos = min(thisOpTarget, numTimelineItems)
        if insertPos > 0 and numTimelineItems + 1 <= max_timeline
            for offset from 0 to numTimelineItems - insertPos - 1
                srcT = numTimelineItems - offset
                dstT = srcT + 1
                timelineType#[dstT] = timelineType#[srcT]
                timelineSectionIdx#[dstT] = timelineSectionIdx#[srcT]
                timelineParam#[dstT] = timelineParam#[srcT]
            endfor
            silPos = insertPos + 1
            timelineType#[silPos] = 3
            timelineSectionIdx#[silPos] = 0
            timelineParam#[silPos] = thisOpParam
            numTimelineItems = numTimelineItems + 1
        endif
    
    elsif thisOpType = 4
        # STRETCH: mark existing item (no insert)
        stretchPos = min(thisOpTarget, numTimelineItems)
        if stretchPos > 0
            timelineType#[stretchPos] = 4
            timelineParam#[stretchPos] = thisOpParam
        endif
    
    elsif thisOpType = 5
        # RECALL: insert transformed copy
        sourceTimelinePos = min(thisOpTarget, numTimelineItems)
        afterPos = min(thisOpParam, numTimelineItems)
        if sourceTimelinePos > 0 and afterPos > 0 and numTimelineItems + 1 <= max_timeline
            sourceSec = timelineSectionIdx#[sourceTimelinePos]
            for offset from 0 to numTimelineItems - afterPos - 1
                srcT = numTimelineItems - offset
                dstT = srcT + 1
                timelineType#[dstT] = timelineType#[srcT]
                timelineSectionIdx#[dstT] = timelineSectionIdx#[srcT]
                timelineParam#[dstT] = timelineParam#[srcT]
            endfor
            recallPos = afterPos + 1
            timelineType#[recallPos] = 5
            timelineSectionIdx#[recallPos] = sourceSec
            timelineParam#[recallPos] = 0
            numTimelineItems = numTimelineItems + 1
        endif
    endif
endfor

appendInfoLine: "  Timeline: ", numTimelineItems, " items"

# Noise tail template (for organic silences)
if silence_mode = 2
    # v5.1: extract from inputSound (preserves channel count).
    # v5.0 used workSound which is always mono, producing mono
    # noise tails that broke Concatenate with overlap against
    # stereo timeline items.
    selectObject: inputSound
    tailStart = max(0, inputDuration - 2.0)
    Extract part: tailStart, inputDuration, "rectangular", 1, "no"
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

# Mark consecutive same-section items as loop copies (for viz)
for t from 2 to numTimelineItems
    if timelineType#[t] = 0 and timelineType#[t-1] = 0 and timelineSectionIdx#[t] = timelineSectionIdx#[t-1]
        timelineLoopFlag#[t] = 1
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
    selectObject: timelineSound#[t]
    nextDur = Get total duration
    
    minDur = min(currentDur, nextDur)
    safeCrossfade = min(targetCrossfade, minDur * 0.4)
    
    if safeCrossfade > 0.002 and currentDur > safeCrossfade * 2 and nextDur > safeCrossfade * 2
        timelineOutputStart#[t] = currentDur - safeCrossfade
        selectObject: finalOutput, timelineSound#[t]
        Concatenate with overlap: safeCrossfade
        temp = selected("Sound")
        removeObject: finalOutput
        finalOutput = temp
    else
        timelineOutputStart#[t] = currentDur
        selectObject: finalOutput, timelineSound#[t]
        Concatenate
        temp = selected("Sound")
        removeObject: finalOutput
        finalOutput = temp
    endif
    
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
    Formula: ~ self * (0.3 + 0.7 * (if x/outputDuration <= arc_peak_position then x/outputDuration/arc_peak_position else 1-(x/outputDuration-arc_peak_position)/(1-arc_peak_position) fi) ^ (1/arc_exaggeration))
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
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Panel A: input sections (color = texture, height = RMS)
# Panel B: OPERATION TIMELINE in output time (the actual
#          dramaturgical transformation)
# Panel C: output waveform
# Panel D: tension arc curve
# Panel E: light-grey summary
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    Black
    Plain line
    
    # Texture color palette
    # 0=silence (mid gray), 1=tonal (blue), 2=quiet (pale gray),
    # 3=bright (yellow), 4=dark (purple), 5=mid (sand)
    
    # Mono copy of output for waveform panel
    selectObject: finalOutput
    outNumCh = Get number of channels
    if outNumCh > 1
        vizOutput = Convert to mono
    else
        vizOutput = Copy: "viz_output"
    endif
    selectObject: vizOutput
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    outAmp = outPeak * 1.15
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##DRAMATURGICAL STRUCTURE COMPOSER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... inputName$
        ... + "  |  " + strategyName$
        ... + "  |  reorder " + reorderName$
        ... + "  |  " + string$(actualNumSections) + " sections"
        ... + "  |  " + string$(numTimelineItems) + " timeline items"
        ... + "  |  " + string$(numOperations) + " ops"
        ... + "  |  in " + fixed$(inputDuration, 1) + " s -> out " + fixed$(outputDuration, 1) + " s"
    
    # ----------------------------------------------------------
    # PANEL A: INPUT SECTIONS  (left, headline)
    # Color = texture, vertical bar height = RMS
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, inputDuration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, inputDuration, 0, 1
    
    for s from 1 to actualNumSections
        # Skip narrative-appended recall (it's at index actualNumSections
        # if reorder_mode = 5 — it's not a "real" input section)
        if not (reorder_mode = 5 and s = actualNumSections)
            sStart = secStart#[s]
            sEnd = secEnd#[s]
            tex = secTexture#[s]
            
            if tex = 1
                bgColor$ = "{0.70, 0.85, 1.00}"
            elsif tex = 2
                bgColor$ = "{0.90, 0.90, 0.90}"
            elsif tex = 3
                bgColor$ = "{1.00, 1.00, 0.78}"
            elsif tex = 4
                bgColor$ = "{0.80, 0.75, 0.95}"
            else
                bgColor$ = "{1.00, 0.88, 0.72}"
            endif
            
            Paint rectangle: bgColor$, sStart, sEnd, 0, 1
            
            # RMS bar (dark blue at bottom)
            if globalMaxRms > 0
                rmsHeight = secRms#[s] / globalMaxRms
            else
                rmsHeight = 0.5
            endif
            if sEnd - sStart > 1
                Paint rectangle: "{0.25, 0.30, 0.55}", sStart + 0.3, sEnd - 0.3, 0, rmsHeight * 0.35
            endif
            
            # Boundary line
            Colour: "Black"
            Line width: 1
            Draw line: sStart, 0, sStart, 1
            
            # Section number
            Font size: 6
            Colour: "{0.20, 0.20, 0.30}"
            midT = (sStart + sEnd) / 2
            Text: midT, "centre", 0.88, "half", string$(s)
        endif
    endfor
    
    # Final boundary
    Colour: "Black"
    Line width: 1
    Draw line: inputDuration, 0, inputDuration, 1
    
    Draw inner box
    Font size: 6
    Text left: "yes", "Input sections"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: OPERATION TIMELINE  (right, headline)
    # The structural transformation, in output time.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, outputDuration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, outputDuration, 0, 1
    
    for t from 1 to numTimelineItems
        oStart = timelineOutputStart#[t]
        oEnd = timelineOutputEnd#[t]
        tex = timelineTexture#[t]
        itemType = timelineType#[t]
        
        # Color from texture (silences distinct)
        if tex = 0
            blockColor$ = "{0.78, 0.78, 0.82}"
        elsif tex = 1
            blockColor$ = "{0.70, 0.85, 1.00}"
        elsif tex = 2
            blockColor$ = "{0.90, 0.90, 0.90}"
        elsif tex = 3
            blockColor$ = "{1.00, 1.00, 0.78}"
        elsif tex = 4
            blockColor$ = "{0.80, 0.75, 0.95}"
        else
            blockColor$ = "{1.00, 0.88, 0.72}"
        endif
        
        Paint rectangle: blockColor$, oStart, oEnd, 0.05, 0.95
        
        # Special outline for recalls (orange) and stretches (dark border)
        if itemType = 5
            Colour: "{0.95, 0.55, 0.20}"
            Line width: 2
            Draw rectangle: oStart, oEnd, 0.05, 0.95
        elsif itemType = 4
            Colour: "{0.50, 0.20, 0.70}"
            Line width: 1.5
            Draw rectangle: oStart, oEnd, 0.05, 0.95
        elsif itemType = 3
            Colour: "{0.55, 0.55, 0.55}"
            Line width: 1.2
            Dashed line
            Draw rectangle: oStart, oEnd, 0.05, 0.95
            Solid line
        else
            Colour: "{0.40, 0.40, 0.45}"
            Line width: 1
            Draw rectangle: oStart, oEnd, 0.05, 0.95
        endif
        
        # Label (only if block is wide enough)
        if oEnd - oStart > outputDuration * 0.025
            secIdxV = timelineSectionIdx#[t]
            if itemType = 3
                blockLabel$ = "SIL " + fixed$(timelineParam#[t], 1) + "s"
            elsif itemType = 4
                blockLabel$ = string$(secIdxV) + " STR " + fixed$(timelineParam#[t], 1) + "x"
            elsif itemType = 5
                if timelineReverseFlag#[t] = 1
                    blockLabel$ = string$(secIdxV) + " REC R"
                else
                    blockLabel$ = string$(secIdxV) + " REC"
                endif
            elsif timelineLoopFlag#[t] = 1
                blockLabel$ = string$(secIdxV) + " LOOP"
            else
                blockLabel$ = string$(secIdxV)
            endif
            
            Font size: 5
            Colour: "{0.20, 0.20, 0.30}"
            midOut = (oStart + oEnd) / 2
            Text: midOut, "centre", 0.50, "half", blockLabel$
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Output timeline"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Detected sections (color = texture, bar = RMS)"
    Text: 6.10, "centre", 7.30, "half", "Operation timeline (orange = RECALL, purple = STRETCH, gray dashed = SILENCE)"
    
    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    Axes: 0, outputDuration, -outAmp, outAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, -outAmp, outAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outputDuration, 0
    
    # Mark timeline boundaries faintly
    Colour: "{0.85, 0.85, 0.90}"
    Line width: 1
    Dotted line
    for t from 2 to numTimelineItems
        boundary = timelineOutputStart#[t]
        Draw line: boundary, -outAmp, boundary, outAmp
    endfor
    Solid line
    
    selectObject: vizOutput
    Colour: "{0.25, 0.40, 0.65}"
    Line width: 1
    Draw: 0, outputDuration, -outAmp, outAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform  (dotted lines = timeline-item boundaries)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: TENSION ARC CURVE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    Axes: 0, 1, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1.1
    
    # Reference grid
    Colour: "{0.85, 0.85, 0.90}"
    Line width: 1
    Dotted line
    Draw line: 0, 0.3, 1, 0.3
    Draw line: 0, 0.65, 1, 0.65
    Draw line: 0, 1.0, 1, 1.0
    Solid line
    
    if apply_tension_arc
        Colour: "{0.80, 0.30, 0.30}"
        Line width: 2
        numDrawPoints = 200
        for dp from 1 to numDrawPoints - 1
            x1 = (dp - 1) / numDrawPoints
            x2 = dp / numDrawPoints
            
            if x1 <= arc_peak_position
                shape1 = x1 / arc_peak_position
            else
                shape1 = 1.0 - (x1 - arc_peak_position) / (1.0 - arc_peak_position)
            endif
            y1 = 0.3 + 0.7 * shape1 ^ (1.0 / arc_exaggeration)
            
            if x2 <= arc_peak_position
                shape2 = x2 / arc_peak_position
            else
                shape2 = 1.0 - (x2 - arc_peak_position) / (1.0 - arc_peak_position)
            endif
            y2 = 0.3 + 0.7 * shape2 ^ (1.0 / arc_exaggeration)
            
            Draw line: x1, y1, x2, y2
        endfor
        
        # Mark peak position
        Colour: "{0.50, 0.20, 0.20}"
        Line width: 1.5
        Dashed line
        Draw line: arc_peak_position, 0, arc_peak_position, 1.1
        Solid line
        
        Font size: 5
        Colour: "{0.55, 0.20, 0.20}"
        Text: arc_peak_position + 0.01, "left", 1.05, "half", "peak " + fixed$(arc_peak_position * 100, 0) + "%"
    else
        # Flat line at 1.0 with "disabled" note
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Dashed line
        Draw line: 0, 1.0, 1, 1.0
        Solid line
        Font size: 7
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.5, "centre", 0.55, "half", "Tension arc disabled"
    endif
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Tension arc envelope (multiplicative, 0 = silence edges, 1 = peak)"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Normalized output position"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    # Count operations by type
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
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + strategyName$ + " / " + reorderName$ + "##"
        ... + "  " + inputName$
        ... + "  |  " + string$(actualNumSections) + " sections detected"
        ... + "  |  Timeline: " + string$(numTimelineItems) + " items"
        ... + "  |  Ops: LOOP " + string$(nLoop)
        ... + " / SIL " + string$(nSil)
        ... + " / STR " + string$(nStr)
        ... + " / REC " + string$(nRec)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Crossfade: " + xfStr$
        ... + "  |  Silence: " + silStr$
        ... + "  |  Arc: " + arcStr$
        ... + "  |  In: " + fixed$(inputDuration, 1) + " s -> Out: " + fixed$(outputDuration, 1) + " s"
        ... + "  |  Peak: " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    removeObject: vizOutput
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: workSound
for s from 1 to actualNumSections
    # Skip narrative-appended recall (sectionOrder entry, not a real section)
    if not (reorder_mode = 5 and s = actualNumSections)
        snd = secSound#[s]
        if snd > 0
            removeObject: snd
        endif
    endif
endfor

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: "Output: ", inputName$, "_dramat_", strategyName$, "_", reorderName$

if play_output
    Play
endif

selectObject: finalOutput
