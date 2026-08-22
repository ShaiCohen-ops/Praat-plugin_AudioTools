# ============================================================
# Praat AudioTools - Tournament_Grid_Recomposer.praat
# Metric-constrained concatenative recomposition by tabu-filtered
# tournament selection
# Author: Shai Cohen
# Version: 0.4 (2026)
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# WHAT THIS DOES
#   This is a segment re-ordering sequencer, not a spectral
#   process. One mono segment pool is cut from the source, each
#   segment is tagged with a measured feature vector
#
#       phi_i  metric phase in [0,1)  (position inside a measure)
#       F0_i   mean pitch (Hz, voiced segments only)
#       C_i    spectral centroid (Hz)
#       E_i    RMS level (dB)
#
#   and an output grid of N = measures x steps-per-measure slots
#   is filled one slot at a time. At each slot a tournament of k
#   candidates is drawn at random from the pool, minus whatever
#   is currently held in the tabu queue, and the candidate with
#   the lowest total cost wins the slot.
#
#       Cost_metric   = circular distance( phi_i , phi_target )
#       Cost_acoustic = wp*|dF0| + wc*|dC| + we*|dE|   (normalized)
#       Cost_total    = w_phi*Cost_metric
#                     + (1 - w_phi)*Cost_acoustic
#
#   The winner is appended to the tabu queue, the oldest entry
#   drops out, and the loop advances. Slots are then rendered
#   with optional PSOLA duration snapping and overlap-add
#   crossfades. The rendered duration is exactly N grid steps; the
#   final crossfade tail is clipped at the declared grid end. The
#   result is normalized to -1 dBFS.
#
#   IMPORTANT INTERPRETATION
#   The metric term is an alignment preference, not a beat
#   tracker. phi_i is measured against a grid the USER declares
#   (Target_BPM, time signature, downbeat offset). If the source
#   is not actually at that tempo, phi_i is still well defined
#   but it no longer means "where this material sat in a bar".
#   Grid segmentation makes the tagging tautological by
#   construction; onset and fixed-window segmentation do not.
#
# METHOD NOTES
#   - Analysis and synthesis share ONE mono pool. Multichannel
#     input is averaged; if that average nearly cancels against
#     the strongest channel, the strongest channel is used
#     instead and the substitution is reported. The mono output is
#     therefore deliberate, not an accidental stereo fold-down.
#   - All temporal geometry is quantized to the source sample
#     grid, so slot onsets land on exact output samples.
#   - Selection is stochastic. Random_seed makes a run
#     reproducible; seed 0 draws a clock-derived seed and
#     reports the value actually used.
#   - Every reported number is measured from the run, not
#     assumed from the settings: achieved stretch factors,
#     achieved metric-phase error, pool coverage, and the
#     number of times the tabu queue had to be relaxed.
#
# DELIBERATE DEPARTURES FROM THE WRITTEN SPECIFICATION
#   1. Metric distance is CIRCULAR. |phi_i - phi_target| makes
#      phase 0.98 maximally distant from a downbeat at 0.0,
#      when it is in fact 0.02 of a bar early. The script uses
#      d = |phi_i - phi_t|, d = min(d, 1-d), scaled x2 to keep
#      the term in [0,1].
#   2. The three acoustic weights are RENORMALIZED to sum to 1
#      before (1 - w_phi) is applied. The spec's four defaults
#      (0.4/0.3/0.2/0.1) already sum to 1, so multiplying the
#      acoustic block by (1 - w_phi) a second time silently
#      turns them into 0.4/0.18/0.12/0.06. Renormalizing makes
#      the printed effective weights match what was typed.
#      Weight_mode preserves the literal spec formula as an
#      option.
#   3. dF0 / dC / dE are measured against the PREVIOUSLY PLACED
#      segment, i.e. the acoustic term buys continuity across
#      the joint. The spec writes "delta" without naming a
#      reference; no external target exists in this design.
#      Slot 1 uses the chronologically first segment as its
#      virtual predecessor.
#   4. Added form fields the spec's own options require or that
#      the library ledger demands: Fixed_window_ms (the
#      spec offers "Fixed Window (ms)" with no length field),
#      Onset_threshold_dB, Source_downbeat_offset_ms,
#      Pitch_floor_Hz / Pitch_ceiling_Hz (never hardcode
#      75/600), Random_seed, Weight_mode, Draw_visualization,
#      Play_result.
#   5. Unvoiced segments remain in the pool but DO NOT receive a
#      fabricated pitch. If either side of a candidate transition
#      is unvoiced, the pitch term is omitted and the remaining
#      acoustic weights are rescaled locally so missing F0 does not
#      make that transition artificially cheap.
#
#      KNOWN ASYMMETRY, deliberately left in place: the rescaling is
#      per candidate, so two candidates in the SAME tournament can be
#      scored in different feature spaces - a voiced candidate on
#      phase + pitch + centroid + energy, an unvoiced one on
#      phase + centroid + energy renormalized to the same total
#      acoustic weight. The comparison inside a tournament is
#      therefore not strictly apples-to-apples. Changing it would
#      change which segments win and how the result sounds, so it is
#      documented here rather than silently altered.
#
# CHANGELOG v0.2
#   - COMPATIBILITY (not a modern-Praat bug): vector-element `+=`
#     replaced by an explicit assignment. `v#[i] += 1` is valid from
#     at least 6.3.09 (2023) through 6.4.63 (2026) - verified on
#     6.3.09 / 6.4.06 / 6.4.42 / 6.4.63. It fails only on Praat 6.1.x
#     with "Missing '=' after vector element", confirmed on 6.1.38,
#     the interpreter embedded in Parselmouth 0.4.7. Kept as legacy
#     compatibility, not as a critical fix.
#   - FIX: all segmentation boundaries are explicitly sample-grid
#     quantized before feature extraction and rendering.
#   - FIX: downbeat offset is treated as periodic metric phase, so
#     negative offsets and offsets outside the file remain valid.
#   - FIX: output duration is exactly measures x steps; no extra
#     crossfade tail is appended after the last slot.
#   - RENDER: preserves the v0.1 body-snapping law. A short
#     source-context tail is used only to supply the overlap region;
#     the declared output no longer includes a final extra tail.
#   - MODEL: missing F0 is handled as missing evidence, not replaced
#     by the voiced median.
#   - VIZ: compact AudioTools 2x2 layout with measured QC.
#
# CHANGELOG v0.3
#   - FIX (regression introduced in v0.2): PSOLA was gated on
#     voicing, which disabled grid snapping entirely on percussive
#     pools. Measured with Allow_time_stretching ON: 64/64 slots
#     truncated in fixed-window mode (~99 ms discarded per 220 ms
#     segment) and 24/24 in onset mode (~256 ms per 500 ms segment).
#     The gate is now on the DIRECTION of the ratio, which is what
#     the artifact actually depends on. Measured HNR of a decaying
#     noise burst through Praat PSOLA, -7.7 dB in:
#         ratio 0.30 -> -6.9    0.80 -> -8.0     (compression: clean)
#         ratio 1.30 -> -4.2    1.80 -> -1.5    2.30 -> -0.5
#     Compressing unvoiced material is transparent; expanding it
#     duplicates grains and injects periodicity into noise. Praat
#     reports 0 voiced frames at every one of those ratios, so a
#     voicing test cannot detect the artifact at all.
#     Unvoiced segments may now be PSOLA-COMPRESSED within
#     [0.2, Unvoiced_max_stretch_ratio] (default 1.1; the field is an
#     UPPER cap only, so its floor is 1.0 and unvoiced compression is
#     always permitted). Unvoiced
#     expansion beyond that is skipped: the natural material is kept
#     and the slot zero-padded, counted and warned as
#     "unvoiced expansion skipped". Voiced segments keep the full
#     [0.2, 5] range, unchanged from v0.1.
#   - FIX: the final slot now fades out over Crossfade_duration_ms
#     INSIDE the declared grid length, so the last sample reaches
#     zero without adding a tail. v0.1 and v0.2 both ended on a hard
#     cut (measured ~45% of full scale on the grid test) because the
#     tail taper was applied only when a following slot existed.
#     outDur remains exactly measures x measure duration.
#   - DOC: the per-candidate acoustic renormalization asymmetry is
#     now stated explicitly under departure 5 above. The selection
#     logic itself is unchanged.
#
# CHANGELOG v0.4
#   - VIZ ONLY: migrated the process figure to the current Praat
#     AudioTools visualization standard. Musical selection, feature
#     analysis, rendering, and output audio are unchanged.
#   - Standard 8-inch page grid, title/subtitle header, 0.60-inch
#     left plot margin, 0.60-inch two-column gutter, explicit inner
#     viewports, unified neutral panel grounds, and consistent
#     12/9/7/6-point typography.
#   - Display-only escaping of underscores in the Sound name and
#     safe percent-sign formatting in drawn text.
#   - Summary strip rewritten as measured run information rather
#     than a second oversized heading block.
#   - Restores the full-page outer viewport as the final drawing
#     action so Picture-window export and clipboard capture include
#     the complete visualization.
#
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form Tournament Grid Recomposer v0.4
    optionmenu Segmentation_method: 1
        option Grid / Quantized Beats
        option Onsets / Transients
        option Fixed Window (ms)
    positive Target_BPM 120.0
    natural Time_signature_numerator 4
    optionmenu Subdivision: 3
        option Quarter (1/4)
        option Eighth (1/8)
        option Sixteenth (1/16)
    real Source_downbeat_offset_ms 0.0
    positive Fixed_window_ms 150.0
    real Onset_threshold_dB 3.0
    natural Tournament_size_k 3
    boolean Enable_tabu_memory 1
    natural Tabu_history_length 5
    boolean Allow_time_stretching 1
    optionmenu Weight_mode: 1
        option Renormalized acoustic weights
        option Literal spec formula
    real Feature_weight_metric_phase 0.4
    real Feature_weight_pitch 0.3
    real Feature_weight_spectral_centroid 0.2
    real Feature_weight_energy 0.1
    real Crossfade_duration_ms 5.0
    natural Output_measures 8
    real Unvoiced_max_stretch_ratio 1.1
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# VALIDATION AND SETUP
# ============================================================
warnLines$ = ""

if random_seed = 0
    now# = date_utc#()
    usedSeed = round(now#[3] * 86400 + now#[4] * 3600 + now#[5] * 60 + now#[6]) + 1
    if usedSeed < 1
        usedSeed = 1
    endif
else
    usedSeed = abs(random_seed)
endif
random_initializeWithSeedUnsafelyButPredictably (usedSeed)

segMethodName$ = "grid / quantized beats"
if segmentation_method = 2
    segMethodName$ = "onsets / transients"
elsif segmentation_method = 3
    segMethodName$ = "fixed window"
endif

subdivFactor = 1
subdivName$ = "quarter (1/4)"
if subdivision = 2
    subdivFactor = 2
    subdivName$ = "eighth (1/8)"
elsif subdivision = 3
    subdivFactor = 4
    subdivName$ = "sixteenth (1/16)"
endif

if pitch_ceiling_Hz <= pitch_floor_Hz * 1.5
    pitch_ceiling_Hz = pitch_floor_Hz * 1.5
    warnLines$ = warnLines$ + "  ! Pitch ceiling too close to floor -> raised to " + fixed$(pitch_ceiling_Hz,0) + " Hz" + newline$
endif

# Weights: clamp to the documented 0..1 range.
if feature_weight_metric_phase < 0
    feature_weight_metric_phase = 0
    warnLines$ = warnLines$ + "  ! Metric-phase weight < 0 -> 0" + newline$
endif
if feature_weight_metric_phase > 1
    feature_weight_metric_phase = 1
    warnLines$ = warnLines$ + "  ! Metric-phase weight > 1 -> 1" + newline$
endif
if feature_weight_pitch < 0
    feature_weight_pitch = 0
    warnLines$ = warnLines$ + "  ! Pitch weight < 0 -> 0" + newline$
endif
if feature_weight_pitch > 1
    feature_weight_pitch = 1
    warnLines$ = warnLines$ + "  ! Pitch weight > 1 -> 1" + newline$
endif
if feature_weight_spectral_centroid < 0
    feature_weight_spectral_centroid = 0
    warnLines$ = warnLines$ + "  ! Centroid weight < 0 -> 0" + newline$
endif
if feature_weight_spectral_centroid > 1
    feature_weight_spectral_centroid = 1
    warnLines$ = warnLines$ + "  ! Centroid weight > 1 -> 1" + newline$
endif
if feature_weight_energy < 0
    feature_weight_energy = 0
    warnLines$ = warnLines$ + "  ! Energy weight < 0 -> 0" + newline$
endif
if feature_weight_energy > 1
    feature_weight_energy = 1
    warnLines$ = warnLines$ + "  ! Energy weight > 1 -> 1" + newline$
endif

wPhi = feature_weight_metric_phase
acousticSum = feature_weight_pitch + feature_weight_spectral_centroid + feature_weight_energy

if weight_mode = 1
    weightModeName$ = "renormalized"
    if acousticSum > 1e-9
        wPit = feature_weight_pitch / acousticSum
        wCen = feature_weight_spectral_centroid / acousticSum
        wEne = feature_weight_energy / acousticSum
    else
        wPit = 0
        wCen = 0
        wEne = 0
        if wPhi > 0
            warnLines$ = warnLines$ + "  ! All three acoustic weights are 0 -> metric phase only" + newline$
        endif
    endif
else
    weightModeName$ = "literal spec"
    wPit = feature_weight_pitch
    wCen = feature_weight_spectral_centroid
    wEne = feature_weight_energy
endif

# Effective weights as they actually enter Cost_total.
effPhi = wPhi
effPit = (1 - wPhi) * wPit
effCen = (1 - wPhi) * wCen
effEne = (1 - wPhi) * wEne

# Every weight zero means no preference at all: the cost surface is
# flat and the tournament degenerates to a uniform random draw.
# Say so rather than quietly substituting a different objective.
allWeightsZero = 0
if effPhi + effPit + effCen + effEne <= 1e-12
    allWeightsZero = 1
    warnLines$ = warnLines$ + "  ! Every weight is 0 -> flat cost, selection is a uniform random draw" + newline$
endif

if crossfade_duration_ms < 0
    crossfade_duration_ms = 0
    warnLines$ = warnLines$ + "  ! Crossfade < 0 ms -> 0 ms" + newline$
endif
if onset_threshold_dB < 0
    onset_threshold_dB = 0
    warnLines$ = warnLines$ + "  ! Onset threshold < 0 dB -> 0 dB" + newline$
endif

# Upper PSOLA limit for UNVOICED material only, and an UPPER limit
# only: compression is transparent, so the floor of this field is
# 1.0. The general [0.2, 5] safety range still applies on top of it.
# 1.0 forbids any unvoiced expansion, 5 restores v0.1 behaviour.
if unvoiced_max_stretch_ratio < 1
    unvoiced_max_stretch_ratio = 1
    warnLines$ = warnLines$ + "  ! Unvoiced max stretch ratio < 1 -> 1 (this field caps expansion only; unvoiced compression is always allowed)" + newline$
endif
if unvoiced_max_stretch_ratio > 5
    unvoiced_max_stretch_ratio = 5
    warnLines$ = warnLines$ + "  ! Unvoiced max stretch ratio > 5 -> 5" + newline$
endif

selectObject: snd
dur = Get total duration
fs = Get sampling frequency
nChannels = Get number of channels

# --- Metric geometry, quantized to the source sample grid ---
stepsPerMeasure = time_signature_numerator * subdivFactor
stepMsRequested = (60000 / target_BPM) / subdivFactor
stepSamples = round((stepMsRequested / 1000) * fs)
if stepSamples < 8
    stepSamples = 8
    warnLines$ = warnLines$ + "  ! Step shorter than 8 samples -> floored" + newline$
endif
stepSec = stepSamples / fs
stepMs = 1000 * stepSec
measureSec = stepsPerMeasure * stepSec
nSteps = output_measures * stepsPerMeasure

fadeSamples = round((crossfade_duration_ms / 1000) * fs)
if fadeSamples > floor(stepSamples / 2)
    fadeSamples = floor(stepSamples / 2)
    warnLines$ = warnLines$ + "  ! Crossfade exceeds half a step -> capped to half-step" + newline$
endif
if fadeSamples < 0
    fadeSamples = 0
endif
fadeSec = fadeSamples / fs
fadeMs = 1000 * fadeSec

# A slot renders stepSec of body plus a fadeSec tail that bleeds
# into the next slot. Slot ONSETS therefore stay exactly on grid.
renderSamples = stepSamples + fadeSamples
renderSec = renderSamples / fs

# A downbeat offset is a periodic grid phase, not a one-shot time
# that must lie inside the file. Wrap it into one measure so negative
# offsets (downbeat before file start) remain meaningful.
offsetRequestedSec = source_downbeat_offset_ms / 1000
offsetSec = offsetRequestedSec - measureSec * floor(offsetRequestedSec / measureSec)
offsetSec = round(offsetSec * fs) / fs
if offsetSec >= measureSec
    offsetSec = 0
endif

if dur < 4 * stepSec
    exitScript: "Sound too short: needs at least four grid steps (", fixed$(4000*stepSec,0), " ms) at this tempo and subdivision."
endif

# ============================================================
# MONO POOL
# ============================================================
strongestCh = 1
strongestRms = -1
for ch from 1 to nChannels
    selectObject: snd
    tmpCh = Extract one channel: ch
    tmpRms = Get root-mean-square: 0, 0
    if tmpRms > strongestRms
        strongestRms = tmpRms
        strongestCh = ch
    endif
    removeObject: tmpCh
endfor

selectObject: snd
workSnd = Convert to mono
Rename: "tg_mono"
monoMethod$ = "channel average"
selectObject: workSnd
monoRms = Get root-mean-square: 0, 0

if nChannels > 1 and strongestRms > 0 and monoRms < 0.1 * strongestRms
    removeObject: workSnd
    selectObject: snd
    workSnd = Extract one channel: strongestCh
    Rename: "tg_mono"
    selectObject: workSnd
    monoRms = Get root-mean-square: 0, 0
    monoMethod$ = "strongest channel fallback"
    warnLines$ = warnLines$ + "  ! Channel average nearly cancelled -> mono pool uses channel " + string$(strongestCh) + newline$
endif

# Normalize the time domain so every absolute-time query below is
# measured from 0 regardless of where the source Sound sits.
selectObject: workSnd
Shift times to: "start time", 0
srcMonoPeak = Get absolute extremum: 0, 0, "None"

clearinfo
writeInfoLine: "=== Tournament Grid Recomposer v0.4 ==="
appendInfoLine: "Sound: ", sndName$, "  (", fixed$(dur, 2), " s, ", nChannels, " ch, ", fixed$(fs,0), " Hz)"
appendInfoLine: "Mono pool: ", monoMethod$, " | RMS ", fixed$(monoRms, 4)
appendInfoLine: "Grid: ", fixed$(target_BPM,1), " BPM, ", time_signature_numerator, "/4 measures, ", subdivName$
appendInfoLine: "Step: ", fixed$(stepMs, 3), " ms effective (", fixed$(stepMsRequested,3), " ms requested) | ", stepsPerMeasure, " steps/measure"
appendInfoLine: "Output: ", output_measures, " measures = ", nSteps, " steps"
appendInfoLine: "Segmentation: ", segMethodName$
if enable_tabu_memory
    tabuDesc$ = "on, requested length " + string$(tabu_history_length)
else
    tabuDesc$ = "off"
endif
if random_seed = 0
    seedDesc$ = " (clock-derived)"
else
    seedDesc$ = " (user)"
endif
appendInfoLine: "Tournament k = ", tournament_size_k, " | tabu ", tabuDesc$
if tournament_size_k = 1
    appendInfoLine: "  Note: k = 1 is a uniform random draw. Nothing is compared, so no cost is minimized."
endif
appendInfoLine: "Weights (as applied): phase ", fixed$(effPhi,3), " | pitch ", fixed$(effPit,3), " | centroid ", fixed$(effCen,3), " | energy ", fixed$(effEne,3), "  [", weightModeName$, "]"
appendInfoLine: "Unvoiced PSOLA limit: ratio <= ", fixed$(unvoiced_max_stretch_ratio,2), " (compression clean, expansion adds periodicity)"
appendInfoLine: "Random seed: ", usedSeed, seedDesc$
appendInfoLine: ""

# ============================================================
# PHASE 1: SEGMENTATION AND METRIC TAGGING
# ============================================================
appendInfoLine: "Phase 1: segmenting and tagging metric phase..."

maxSegs = 4000
segStart# = zero#(maxSegs)
segEnd# = zero#(maxSegs)
nSegs = 0

if segmentation_method = 1
    # Grid: the subdivision lattice extends in both directions from
    # the declared downbeat. Find its first boundary in [0, stepSec),
    # so a negative/downstream downbeat phase does not discard most
    # of the source before segmentation begins.
    cursor = offsetSec
    while cursor - stepSec >= 0
        cursor -= stepSec
    endwhile
    cursor = round(cursor * fs) / fs
    while cursor + stepSec <= dur and nSegs < maxSegs
        nSegs += 1
        segStart#[nSegs] = cursor
        segEnd#[nSegs] = cursor + stepSec
        cursor += stepSec
    endwhile

elsif segmentation_method = 2
    # Onsets: local maxima of a short-lookback intensity rise.
    selectObject: workSnd
    onsInt = To Intensity: pitch_floor_Hz, 0, "yes"
    nIntFrames = Get number of frames
    intStep = Get time step
    lookFrames = max(1, round(0.024 / intStep))
    minIOI = max(0.030, 0.5 * stepSec)

    intVal# = zero#(nIntFrames)
    for f from 1 to nIntFrames
        v = Get value in frame: f
        if v = undefined
            v = -300
        endif
        intVal#[f] = v
    endfor

    rise# = zero#(nIntFrames)
    for f from 1 to nIntFrames
        fp = f - lookFrames
        if fp < 1
            fp = 1
        endif
        rise#[f] = intVal#[f] - intVal#[fp]
    endfor

    onsTime# = zero#(maxSegs)
    nOnsets = 1
    onsTime#[1] = 0
    lastOnset = -1e9
    for f from 2 to nIntFrames - 1
        if nOnsets < maxSegs
            selectObject: onsInt
            tf = Get time from frame number: f
            if rise#[f] >= onset_threshold_dB and rise#[f] >= rise#[f - 1] and rise#[f] > rise#[f + 1]
                if tf - lastOnset >= minIOI and tf >= minIOI and tf <= dur - minIOI
                    nOnsets += 1
                    onsTime#[nOnsets] = tf
                    lastOnset = tf
                endif
            endif
        endif
    endfor
    removeObject: onsInt

    if nOnsets < 4
        warnLines$ = warnLines$ + "  ! Only " + string$(nOnsets) + " onsets found -> fell back to fixed-window segmentation" + newline$
        cursor = 0
        winSec = fixed_window_ms / 1000
        while cursor + winSec <= dur and nSegs < maxSegs
            nSegs += 1
            segStart#[nSegs] = cursor
            segEnd#[nSegs] = cursor + winSec
            cursor += winSec
        endwhile
        segMethodName$ = "fixed window (onset fallback)"
    else
        for o from 1 to nOnsets
            if o < nOnsets
                segTo = onsTime#[o + 1]
            else
                segTo = dur
            endif
            if segTo - onsTime#[o] > 0.005
                nSegs += 1
                segStart#[nSegs] = onsTime#[o]
                segEnd#[nSegs] = segTo
            endif
        endfor
        appendInfoLine: "  ", nOnsets, " onsets detected (threshold ", fixed$(onset_threshold_dB,1), " dB rise over ", fixed$(1000*lookFrames*intStep,0), " ms, min IOI ", fixed$(1000*minIOI,0), " ms)"
    endif

else
    # Fixed window.
    cursor = 0
    winSec = fixed_window_ms / 1000
    if winSec > dur / 4
        winSec = dur / 4
        warnLines$ = warnLines$ + "  ! Fixed window longer than a quarter of the source -> " + fixed$(1000*winSec,1) + " ms" + newline$
    endif
    while cursor + winSec <= dur and nSegs < maxSegs
        nSegs += 1
        segStart#[nSegs] = cursor
        segEnd#[nSegs] = cursor + winSec
        cursor += winSec
    endwhile
endif

# Snap every segment boundary to the source sample grid. Rebuild the
# arrays so sub-two-sample fragments disappear rather than being
# carried into feature analysis.
durSamples = round(dur * fs)
qCount = 0
maxBoundaryShiftSamples = 0
for i from 1 to nSegs
    oldS = segStart#[i]
    oldE = segEnd#[i]
    sSamp = round(oldS * fs)
    eSamp = round(oldE * fs)
    sSamp = max(0, min(durSamples, sSamp))
    eSamp = max(0, min(durSamples, eSamp))
    if eSamp - sSamp >= 2
        qCount += 1
        segStart#[qCount] = sSamp / fs
        segEnd#[qCount] = eSamp / fs
        sh1 = abs(segStart#[qCount] - oldS) * fs
        sh2 = abs(segEnd#[qCount] - oldE) * fs
        if sh1 > maxBoundaryShiftSamples
            maxBoundaryShiftSamples = sh1
        endif
        if sh2 > maxBoundaryShiftSamples
            maxBoundaryShiftSamples = sh2
        endif
    endif
endfor
nSegs = qCount

if nSegs < 4
    removeObject: workSnd
    exitScript: "Segmentation produced only ", nSegs, " valid sample-quantized segments. Use a shorter window, a lower onset threshold, or a longer source."
endif

# Metric phase of each segment start, relative to the declared grid.
segPhase# = zero#(nSegs)
segDur# = zero#(nSegs)
for i from 1 to nSegs
    u = segStart#[i] - offsetSec
    u = u - measureSec * floor(u / measureSec)
    segPhase#[i] = u / measureSec
    segDur#[i] = segEnd#[i] - segStart#[i]
endfor

meanSegMs = 0
minSegMs = 1e9
maxSegMs = 0
for i from 1 to nSegs
    d = 1000 * segDur#[i]
    meanSegMs += d
    if d < minSegMs
        minSegMs = d
    endif
    if d > maxSegMs
        maxSegMs = d
    endif
endfor
meanSegMs = meanSegMs / nSegs

appendInfoLine: "  ", nSegs, " segments | duration mean ", fixed$(meanSegMs,1), " ms (", fixed$(minSegMs,1), "-", fixed$(maxSegMs,1), " ms)"

if tournament_size_k > nSegs
    tournament_size_k = nSegs
    warnLines$ = warnLines$ + "  ! Tournament k larger than the pool -> k = " + string$(nSegs) + newline$
endif

tabuLen = tabu_history_length
if enable_tabu_memory = 0
    tabuLen = 0
endif
if tabuLen > nSegs - 1
    tabuLen = nSegs - 1
    warnLines$ = warnLines$ + "  ! Tabu length >= pool size -> reduced to " + string$(tabuLen) + newline$
endif

# ============================================================
# PHASE 2: FEATURE EXTRACTION AND NORMALIZATION
# ============================================================
appendInfoLine: "Phase 2: extracting pitch, centroid and RMS per segment..."

rawF0# = zero#(nSegs)
rawCen# = zero#(nSegs)
rawEne# = zero#(nSegs)
voiced# = zero#(nSegs)
nUnvoiced = 0

minPitchDur = 3 / pitch_floor_Hz

for i from 1 to nSegs
    t1 = max(0, segStart#[i])
    t2 = min(dur, segEnd#[i])
    selectObject: workSnd
    seg = Extract part: t1, t2, "rectangular", 1, "no"
    Rename: "tg_feat"

    selectObject: seg
    r = Get root-mean-square: 0, 0
    if r = undefined or r <= 1e-9
        rawEne#[i] = -180
    else
        rawEne#[i] = 20 * log10(r)
    endif

    # Centroid on a windowed copy: a rectangular cut adds edge
    # energy that biases brightness upward.
    selectObject: workSnd
    segW = Extract part: t1, t2, "Hanning", 1, "no"
    spec = To Spectrum: "yes"
    cg = Get centre of gravity: 2
    if cg = undefined or cg <= 0
        cg = 0
    endif
    rawCen#[i] = cg
    removeObject: segW, spec

    f0 = undefined
    if t2 - t1 >= minPitchDur
        selectObject: seg
        pit = To Pitch: 0, pitch_floor_Hz, pitch_ceiling_Hz
        f0 = Get mean: 0, 0, "Hertz"
        removeObject: pit
    endif
    if f0 = undefined or f0 <= 0
        voiced#[i] = 0
        nUnvoiced += 1
        rawF0#[i] = 0
    else
        voiced#[i] = 1
        rawF0#[i] = f0
    endif

    removeObject: seg
endfor

nVoiced = nSegs - nUnvoiced

# Min-max normalization to [0,1]; a flat feature collapses to 0.5
# so it contributes a constant (i.e. no) preference.
normF0# = zero#(nSegs)
normCen# = zero#(nSegs)
normEne# = zero#(nSegs)

if nVoiced > 0
    loF0 = 1e300
    hiF0 = -1e300
    for i from 1 to nSegs
        if voiced#[i] = 1
            if rawF0#[i] < loF0
                loF0 = rawF0#[i]
            endif
            if rawF0#[i] > hiF0
                hiF0 = rawF0#[i]
            endif
        endif
    endfor
else
    loF0 = 0
    hiF0 = 0
endif
loCen = rawCen#[1]
hiCen = rawCen#[1]
loEne = rawEne#[1]
hiEne = rawEne#[1]
for i from 2 to nSegs
    if rawCen#[i] < loCen
        loCen = rawCen#[i]
    endif
    if rawCen#[i] > hiCen
        hiCen = rawCen#[i]
    endif
    if rawEne#[i] < loEne
        loEne = rawEne#[i]
    endif
    if rawEne#[i] > hiEne
        hiEne = rawEne#[i]
    endif
endfor

flatFeatures$ = ""
for i from 1 to nSegs
    if voiced#[i] = 1 and hiF0 - loF0 > 1e-9
        normF0#[i] = (rawF0#[i] - loF0) / (hiF0 - loF0)
    else
        # Display placeholder only; this value is never charged as a
        # pitch distance when the segment is unvoiced.
        normF0#[i] = 0.5
    endif
    if hiCen - loCen > 1e-9
        normCen#[i] = (rawCen#[i] - loCen) / (hiCen - loCen)
    else
        normCen#[i] = 0.5
    endif
    if hiEne - loEne > 1e-9
        normEne#[i] = (rawEne#[i] - loEne) / (hiEne - loEne)
    else
        normEne#[i] = 0.5
    endif
endfor
if nVoiced = 0 or hiF0 - loF0 <= 1e-9
    flatFeatures$ = flatFeatures$ + " pitch"
endif
if hiCen - loCen <= 1e-9
    flatFeatures$ = flatFeatures$ + " centroid"
endif
if hiEne - loEne <= 1e-9
    flatFeatures$ = flatFeatures$ + " energy"
endif
if flatFeatures$ <> ""
    warnLines$ = warnLines$ + "  ! Constant/unavailable across the pool ->" + flatFeatures$ + " contributes no preference" + newline$
endif

appendInfoLine: "  pitch ", fixed$(loF0,1), "-", fixed$(hiF0,1), " Hz | centroid ", fixed$(loCen,0), "-", fixed$(hiCen,0), " Hz | RMS ", fixed$(loEne,1), " to ", fixed$(hiEne,1), " dB"
if nUnvoiced > 0
    appendInfoLine: "  ", nUnvoiced, " of ", nSegs, " segments unvoiced -> pitch cost omitted whenever either side of a joint is unvoiced"
endif
appendInfoLine: "  segment boundaries quantized to samples | max requested->effective shift ", fixed$(maxBoundaryShiftSamples,3), " samples"

# ============================================================
# PHASE 3: TABU-CONSTRAINED TOURNAMENT SELECTION
# ============================================================
appendInfoLine: "Phase 3: running ", nSteps, " tournaments (k = ", tournament_size_k, ")..."

chosen# = zero#(nSteps)
winCost# = zero#(nSteps)
poolMin# = zero#(nSteps)
poolMax# = zero#(nSteps)
targetPhase# = zero#(nSteps)
phaseErr# = zero#(nSteps)
kActual# = zero#(nSteps)

inTabu# = zero#(nSegs)
tabuQ# = zero#(max(1, tabuLen))
tabuCount = 0
tabuHead = 0
tabuRelaxations = 0
shrunkTournaments = 0

elig# = zero#(nSegs)
useCount# = zero#(nSegs)

# Virtual predecessor for slot 1: the chronologically first segment.
prevIdx = 1
prevF0 = normF0#[1]
prevCen = normCen#[1]
prevEne = normEne#[1]
prevVoiced = voiced#[1]
baseAcousticWeight = wPit + wCen + wEne
pitchOmittedWins = 0

for n from 1 to nSteps
    phiT = ((n - 1) mod stepsPerMeasure) / stepsPerMeasure
    targetPhase#[n] = phiT

    # --- eligible pool = everything not currently tabu ---
    nElig = 0
    for i from 1 to nSegs
        if inTabu#[i] = 0
            nElig += 1
            elig#[nElig] = i
        endif
    endfor
    if nElig = 0
        # Cannot happen with tabuLen <= nSegs-1, but never let the
        # loop die on an empty pool.
        tabuRelaxations += 1
        for i from 1 to nSegs
            elig#[i] = i
        endfor
        nElig = nSegs
    endif

    kThis = tournament_size_k
    if kThis > nElig
        kThis = nElig
        shrunkTournaments += 1
    endif
    kActual#[n] = kThis

    # --- draw k distinct candidates (ascending partial shuffle) ---
    for j from 1 to kThis
        r = randomInteger(j, nElig)
        tmp = elig#[j]
        elig#[j] = elig#[r]
        elig#[r] = tmp
    endfor

    # --- cost function ---
    bestCost = 1e300
    worstCost = -1e300
    bestIdx = elig#[1]
    for j from 1 to kThis
        cand = elig#[j]

        dPhase = abs(segPhase#[cand] - phiT)
        if dPhase > 0.5
            dPhase = 1 - dPhase
        endif
        costMetric = 2 * dPhase

        # Missing F0 is missing evidence, not a fabricated median.
        pitchAvailable = voiced#[cand] = 1 and prevVoiced = 1
        activeWeight = wCen + wEne
        costRaw = wCen * abs(normCen#[cand] - prevCen)
            ... + wEne * abs(normEne#[cand] - prevEne)
        if pitchAvailable
            activeWeight += wPit
            costRaw += wPit * abs(normF0#[cand] - prevF0)
        endif
        if activeWeight > 1e-12 and baseAcousticWeight > 1e-12
            costAcoustic = costRaw * baseAcousticWeight / activeWeight
        else
            costAcoustic = 0
        endif

        costTotal = wPhi * costMetric + (1 - wPhi) * costAcoustic

        if costTotal < bestCost
            bestCost = costTotal
            bestIdx = cand
        endif
        if costTotal > worstCost
            worstCost = costTotal
        endif
    endfor

    chosen#[n] = bestIdx
    winCost#[n] = bestCost
    poolMin#[n] = bestCost
    poolMax#[n] = worstCost
    useCount#[bestIdx] = useCount#[bestIdx] + 1

    dp = abs(segPhase#[bestIdx] - phiT)
    if dp > 0.5
        dp = 1 - dp
    endif
    phaseErr#[n] = dp

    if voiced#[bestIdx] = 0 or prevVoiced = 0
        pitchOmittedWins += 1
    endif
    prevF0 = normF0#[bestIdx]
    prevCen = normCen#[bestIdx]
    prevEne = normEne#[bestIdx]
    prevVoiced = voiced#[bestIdx]
    prevIdx = bestIdx

    # --- tabu queue update (circular) ---
    if tabuLen > 0
        if tabuCount < tabuLen
            tabuCount += 1
            tabuHead = tabuCount
            tabuQ#[tabuHead] = bestIdx
            inTabu#[bestIdx] = 1
        else
            tabuHead = tabuHead mod tabuLen + 1
            oldest = tabuQ#[tabuHead]
            inTabu#[oldest] = 0
            tabuQ#[tabuHead] = bestIdx
            inTabu#[bestIdx] = 1
        endif
    endif
endfor

# --- measured selection statistics ---
uniqueUsed = 0
maxUse = 0
for i from 1 to nSegs
    if useCount#[i] > 0
        uniqueUsed += 1
    endif
    if useCount#[i] > maxUse
        maxUse = useCount#[i]
    endif
endfor
coveragePct = 100 * uniqueUsed / nSegs

meanWinCost = 0
meanSpread = 0
meanPhaseErr = 0
maxPhaseErr = 0
immediateRepeats = 0
for n from 1 to nSteps
    meanWinCost += winCost#[n]
    meanSpread += poolMax#[n] - poolMin#[n]
    meanPhaseErr += phaseErr#[n]
    if phaseErr#[n] > maxPhaseErr
        maxPhaseErr = phaseErr#[n]
    endif
    if n > 1
        if chosen#[n] = chosen#[n - 1]
            immediateRepeats += 1
        endif
    endif
endfor
meanWinCost /= nSteps
meanSpread /= nSteps
meanPhaseErr /= nSteps

appendInfoLine: "  pool coverage ", fixed$(coveragePct,1), "% (", uniqueUsed, " of ", nSegs, " segments, most-used ", maxUse, "x)"
appendInfoLine: "  mean winning cost ", fixed$(meanWinCost,4), " | mean tournament spread ", fixed$(meanSpread,4)
# Baseline: the phase error a uniform random draw would have given,
# averaged over the same target phases. This is what the tournament
# is measured against - without it, "0.15" means nothing.
baselinePhaseErr = 0
for n from 1 to nSteps
    acc = 0
    for i from 1 to nSegs
        db = abs(segPhase#[i] - targetPhase#[n])
        if db > 0.5
            db = 1 - db
        endif
        acc += db
    endfor
    baselinePhaseErr += acc / nSegs
endfor
baselinePhaseErr /= nSteps
if baselinePhaseErr > 1e-9
    phaseImprovePct = 100 * (1 - meanPhaseErr / baselinePhaseErr)
else
    phaseImprovePct = 0
endif

appendInfoLine: "  mean metric-phase error ", fixed$(meanPhaseErr,4), " of a measure (max ", fixed$(maxPhaseErr,4), ")"
appendInfoLine: "  random-draw baseline ", fixed$(baselinePhaseErr,4), " -> tournament is ", fixed$(phaseImprovePct,1), "% closer to the grid"
if shrunkTournaments > 0
    appendInfoLine: "  ", shrunkTournaments, " tournaments ran with fewer than k candidates (tabu pressure)"
endif

# ============================================================
# PHASE 4: RESYNTHESIS AND TIME ALIGNMENT
# ============================================================
appendInfoLine: "Phase 4: rendering ", nSteps, " slots..."

# Exact declared grid length. Crossfade tails exist only between slots;
# the last slot has no tail beyond the requested number of measures.
outDur = nSteps * stepSec
outBuf = Create Sound from formula: "tg_out", 1, 0, outDur, fs, "0"

stretchRatio# = zero#(nSteps)
nStretched = 0
nPsolaSkipped = 0
nPsolaSkippedUnvoiced = 0
nStretchedUnvoiced = 0
nUnvoicedExpansionSkipped = 0
nTruncated = 0
nPadded = 0
minRatio = 1e300
maxRatio = 0
achievedErrSamples = 0

for n from 1 to nSteps
    idx = chosen#[n]
    outStart = (n - 1) * stepSec
    if n < nSteps
        thisTail = fadeSec
    else
        thisTail = 0
    endif
    thisRenderSec = stepSec + thisTail

    # Preserve v0.1's musical law: the SEGMENT BODY maps to exactly
    # one grid step. A short source-context tail is extracted only to
    # supply the overlap region; the last slot has no extra tail.
    if allow_time_stretching
        bodyRatio = stepSec / max(segDur#[idx], 1/fs)
        srcWant = segDur#[idx] * thisRenderSec / stepSec
    else
        bodyRatio = 1
        # Without stretching, never read a whole following event just
        # to fill a short segment: use at most the chosen segment plus
        # the explicit crossfade tail, then zero-pad if needed.
        srcWant = min(thisRenderSec, segDur#[idx] + thisTail)
    endif

    srcFrom = segStart#[idx]
    srcTo = min(dur, srcFrom + srcWant)
    selectObject: workSnd
    rawSeg = Extract part: srcFrom, srcTo, "rectangular", 1, "no"
    Rename: "tg_raw"
    selectObject: rawSeg
    Shift times to: "start time", 0
    rawDur = Get total duration

    ratio = bodyRatio
    stretchRatio#[n] = ratio

    usedSeg = rawSeg
    madeSeg = 0
    # v0.3 gate: the artifact depends on the DIRECTION of the ratio,
    # not on voicing. Compressing unvoiced material is transparent;
    # expanding it duplicates grains and adds periodicity to noise.
    canPsola = 0
    unvExpansion = 0
    if allow_time_stretching and abs(ratio - 1) > 0.001
        if rawDur >= minPitchDur and ratio >= 0.2 and ratio <= 5
            if voiced#[idx] = 1
                canPsola = 1
            elsif ratio <= unvoiced_max_stretch_ratio
                canPsola = 1
                nStretchedUnvoiced = nStretchedUnvoiced + 1
            else
                unvExpansion = 1
            endif
        endif
    endif
    if canPsola
        selectObject: rawSeg
        man = To Manipulation: 0.01, pitch_floor_Hz, pitch_ceiling_Hz
        dtier = Extract duration tier
        Add point: rawDur / 2, ratio
        selectObject: man, dtier
        Replace duration tier
        selectObject: man
        psola = Get resynthesis (overlap-add)
        Rename: "tg_psola"
        removeObject: man, dtier
        usedSeg = psola
        madeSeg = 1
        nStretched += 1
    elsif allow_time_stretching and abs(ratio - 1) > 0.001
        nPsolaSkipped += 1
        if voiced#[idx] = 0
            nPsolaSkippedUnvoiced += 1
        endif
        if unvExpansion
            nUnvoicedExpansionSkipped = nUnvoicedExpansionSkipped + 1
        endif
        stretchRatio#[n] = 1
    else
        stretchRatio#[n] = 1
    endif

    selectObject: usedSeg
    Shift times to: "start time", 0
    haveDur = Get total duration
    achievedErrSamples += abs(haveDur - thisRenderSec) * fs
    if haveDur > thisRenderSec + 0.5 / fs
        nTruncated += 1
    elsif haveDur < thisRenderSec - 0.5 / fs
        nPadded += 1
    endif

    # Copy only the available part into an exact-length slot; the rest
    # remains digital zero. ID-based lookup avoids name collisions.
    slot = Create Sound from formula: "tg_slot", 1, 0, thisRenderSec, fs, "0"
    copyDur = min(haveDur, thisRenderSec)
    if copyDur > 0
        usedId$ = string$(usedSeg)
        selectObject: slot
        Formula (part): 0, copyDur, 1, 1, "object(" + usedId$ + ", x)"
    endif

    if madeSeg = 1
        removeObject: usedSeg
    endif
    removeObject: rawSeg

    # Complementary raised-cosine overlap only between neighbouring
    # slots. Head + previous tail = 1 through the overlap.
    selectObject: slot
    if fadeSec > 0
        if n > 1
            Formula (part): 0, min(fadeSec, thisRenderSec), 1, 1, "self * (0.5 - 0.5*cos(pi*x/'fadeSec'))"
        endif
        # v0.3: the tail taper is applied to EVERY slot, including the
        # last. For n < nSteps it is the complementary half of the
        # next slot's head fade; on the last slot there is no next
        # head, so it simply brings the output to zero inside the
        # declared grid length instead of ending on a hard cut.
        Formula (part): thisRenderSec - fadeSec, thisRenderSec, 1, 1, "self * (0.5 - 0.5*cos(pi*(xmax-x)/'fadeSec'))"
    endif

    selectObject: slot
    Shift times to: "start time", outStart
    slotId$ = string$(slot)
    selectObject: outBuf
    Formula (part): outStart, min(outDur, outStart + thisRenderSec), 1, 1,
        ... "self + object(" + slotId$ + ", x)"
    removeObject: slot

    if stretchRatio#[n] < minRatio
        minRatio = stretchRatio#[n]
    endif
    if stretchRatio#[n] > maxRatio
        maxRatio = stretchRatio#[n]
    endif
endfor

meanSlotErrSamples = achievedErrSamples / nSteps

selectObject: outBuf
prePeak = Get absolute extremum: 0, 0, "None"
if prePeak > 1e-9
    Scale peak: 0.891251
else
    warnLines$ = warnLines$ + "  ! Rendered output is silent -> peak normalization skipped" + newline$
endif
Rename: sndName$ + "_tourn_grid"

selectObject: outBuf
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0
if outRms > 1e-12
    outRmsDb = 20 * log10(outRms)
else
    outRmsDb = -180
endif

appendInfoLine: "  ", nStretched, " of ", nSteps, " slots PSOLA-stretched (", nStretchedUnvoiced, " of them unvoiced compressions) | ratio range ", fixed$(minRatio,3), "-", fixed$(maxRatio,3)
if nPsolaSkipped > 0
    appendInfoLine: "  ", nPsolaSkipped, " slots not PSOLA-stretched (", nUnvoicedExpansionSkipped, " unvoiced expansion skipped; remainder too short or too extreme)"
endif
if nUnvoicedExpansionSkipped > 0
    warnLines$ = warnLines$ + "  ! " + string$(nUnvoicedExpansionSkipped) + " unvoiced slots needed expansion above ratio " + fixed$(unvoiced_max_stretch_ratio,2) + " -> PSOLA skipped, natural material kept and slot zero-padded" + newline$
endif
appendInfoLine: "  slot fit error before truncate/pad: mean ", fixed$(meanSlotErrSamples,2), " samples | ", nTruncated, " truncated, ", nPadded, " zero-padded"
appendInfoLine: "  exact grid duration ", fixed$(outDur,3), " s = ", output_measures, " measures | pre-normalization peak ", fixed$(prePeak,4), " -> -1 dBFS"

# ============================================================
# VISUALIZATION
# AudioTools-standard 2x2 mechanism-first layout. Every panel is
# measured from the run: no idealized curves, no settings echoed
# as if measured. v0.4 changes visualization only.
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing process visualization..."

    # Praat reads "_" in drawn text as a subscript marker. Escape it
    # for display only; the actual Sound object name is untouched.
    vizSoundName$ = replace$(sndName$, "_", "\_ ", 0)

    selectObject: workSnd
    srcYr = Get absolute extremum: 0, 0, "None"
    if srcYr < 1e-6
        srcYr = 1
    endif
    srcYr = 1.08 * srcYr

    selectObject: outBuf
    outYr = Get absolute extremum: 0, 0, "None"
    if outYr < 1e-6
        outYr = 1
    endif
    outYr = 1.08 * outYr

    procedure tgStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = 1 * .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    if tabuLen > 0
        tabuLabel$ = string$(tabuLen)
    else
        tabuLabel$ = "off"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 6.19

    # ---------------- Header ----------------
    Select outer viewport: 0, 8, 0, 0.50
    Select inner viewport: 0.60, 7.70, 0.02, 0.48
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Tournament Grid Recomposer v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizSoundName$ + " | " + segMethodName$
        ... + " | " + fixed$(target_BPM, 1) + " BPM"
        ... + " | " + string$(output_measures) + " measures"
        ... + " | " + subdivName$

    # ========================================================
    # A  POOL
    # ========================================================
    Select outer viewport: 0, 4, 0.64, 0.90
    Select inner viewport: 0.18, 3.85, 0.64, 0.90
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "A  POOL - source and measured segment boundaries"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.01, "left", 0.18, "half",
        ... string$(nSegs) + " segments | mean " + fixed$(meanSegMs, 1)
        ... + " ms | grey = measure reference | red = segment cut"

    Select outer viewport: 0, 4, 0.90, 3.03
    Select inner viewport: 0.60, 3.85, 1.01, 2.86
    Axes: 0, dur, -srcYr, srcYr
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, -srcYr, srcYr

    selectObject: workSnd
    Colour: "{0.30, 0.30, 0.34}"
    Draw: 0, dur, -srcYr, srcYr, "no", "Curve"

    # Grid and cuts go on top of the waveform so the visual claim is
    # preserved even for dense source material.
    Select inner viewport: 0.60, 3.85, 1.01, 2.86
    Axes: 0, dur, -srcYr, srcYr
    Colour: "{0.80, 0.80, 0.80}"
    Line width: 1.3
    mStride = ceiling((dur / measureSec) / 60)
    if mStride < 1
        mStride = 1
    endif
    mLine = offsetSec
    while mLine <= dur
        Draw line: mLine, -srcYr, mLine, srcYr
        mLine += mStride * measureSec
    endwhile
    Line width: 1

    segStride = ceiling(nSegs / 70)
    if segStride < 1
        segStride = 1
    endif
    Colour: "{0.78, 0.28, 0.22}"
    for i from 1 to nSegs
        if (i - 1) mod segStride = 0
            Draw line: segStart#[i], -1.00 * srcYr, segStart#[i], -0.86 * srcYr
            Draw line: segStart#[i], 0.86 * srcYr, segStart#[i], 1.00 * srcYr
        endif
    endfor

    Select inner viewport: 0.60, 3.85, 1.01, 2.86
    Axes: 0, dur, -srcYr, srcYr
    Colour: "Black"
    Draw inner box
    Font size: 6
    @tgStep: dur, 5
    Marks bottom every: 1, tgStep.step, "yes", "yes", "no"
    @tgStep: 2 * srcYr, 4
    Marks left every: 1, tgStep.step, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "source time (s)"
    Text left: "yes", "amplitude"

    # ========================================================
    # B  SELECTION
    # ========================================================
    Select outer viewport: 4, 8, 0.64, 0.90
    Select inner viewport: 4.18, 7.70, 0.64, 0.90
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "B  SELECTION - winning source segment for each slot"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.01, "left", 0.18, "half",
        ... "coverage " + fixed$(coveragePct, 1) + "\%  | most-used "
        ... + string$(maxUse) + "x | immediate repeats " + string$(immediateRepeats)

    Select outer viewport: 4, 8, 0.90, 3.03
    Select inner viewport: 4.45, 7.70, 1.01, 2.86
    Axes: 0, nSteps + 1, 0, nSegs + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nSteps + 1, 0, nSegs + 1

    # Quiet measure boundaries in the output grid.
    Colour: "{0.80, 0.80, 0.80}"
    Line width: 1
    for m from 0 to output_measures
        xm = m * stepsPerMeasure + 0.5
        if xm <= nSteps + 1
            Draw line: xm, 0, xm, nSegs + 1
        endif
    endfor

    # The connecting line and points encode one measured read-head path.
    Colour: "{0.26, 0.48, 0.78}"
    Line width: 1
    for n from 2 to nSteps
        Draw line: n - 1, chosen#[n - 1], n, chosen#[n]
    endfor

    dotR = 0.55
    if nSteps > 200
        dotR = 0.32
    endif
    if dotR < 0.20
        dotR = 0.20
    endif
    for n from 1 to nSteps
        Paint circle (mm): "{0.26, 0.48, 0.78}", n, chosen#[n], dotR
    endfor

    Select inner viewport: 4.45, 7.70, 1.01, 2.86
    Axes: 0, nSteps + 1, 0, nSegs + 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    @tgStep: nSteps, 5
    Marks bottom every: 1, tgStep.step, "yes", "yes", "no"
    @tgStep: nSegs, 5
    Marks left every: 1, tgStep.step, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "output slot"
    Text left: "yes", "source segment"

    # ========================================================
    # C  COST
    # ========================================================
    Select outer viewport: 0, 4, 3.13, 3.39
    Select inner viewport: 0.18, 3.85, 3.13, 3.39
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "C  COST - winner against the tournament it beat"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.01, "left", 0.18, "half",
        ... "blue = winning cost | grey = candidate range | mean "
        ... + fixed$(meanWinCost, 4) + " | spread " + fixed$(meanSpread, 4)

    costMax = 0
    for n from 1 to nSteps
        if poolMax#[n] > costMax
            costMax = poolMax#[n]
        endif
    endfor
    if costMax < 0.05
        costMax = 0.05
    endif
    costMax = 1.12 * costMax

    Select outer viewport: 0, 4, 3.39, 5.52
    Select inner viewport: 0.60, 3.85, 3.50, 5.35
    Axes: 0, nSteps + 1, 0, costMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nSteps + 1, 0, costMax

    # Grey band = min..max cost actually seen in each tournament.
    for n from 1 to nSteps
        yLo = poolMin#[n]
        yHi = poolMax#[n]
        if yHi - yLo < costMax / 400
            yHi = yLo + costMax / 400
        endif
        Paint rectangle: "{0.86, 0.86, 0.86}", n - 0.45, n + 0.45, yLo, yHi
    endfor

    Select inner viewport: 0.60, 3.85, 3.50, 5.35
    Axes: 0, nSteps + 1, 0, costMax
    Colour: "{0.26, 0.48, 0.78}"
    Line width: 1.5
    for n from 2 to nSteps
        Draw line: n - 1, winCost#[n - 1], n, winCost#[n]
    endfor
    Line width: 1

    Colour: "{0.78, 0.28, 0.22}"
    Draw line: 0, meanWinCost, nSteps + 1, meanWinCost

    Select inner viewport: 0.60, 3.85, 3.50, 5.35
    Axes: 0, nSteps + 1, 0, costMax
    Colour: "Black"
    Draw inner box
    Font size: 6
    @tgStep: nSteps, 5
    Marks bottom every: 1, tgStep.step, "yes", "yes", "no"
    @tgStep: costMax, 4
    Marks left every: 1, tgStep.step, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "output slot"
    Text left: "yes", "total cost"

    # ========================================================
    # D  GRID CHECK
    # ========================================================
    Select outer viewport: 4, 8, 3.13, 3.39
    Select inner viewport: 4.18, 7.70, 3.13, 3.39
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "D  GRID CHECK - rendered output against the declared grid"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.01, "left", 0.18, "half",
        ... "grey = measure reference | " + fixed$(stepMs, 1)
        ... + " ms steps | mean phase error " + fixed$(meanPhaseErr, 3)

    Select outer viewport: 4, 8, 3.39, 5.52
    Select inner viewport: 4.45, 7.70, 3.50, 5.35
    Axes: 0, outDur, -outYr, outYr
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, -outYr, outYr

    selectObject: outBuf
    Colour: "{0.30, 0.30, 0.34}"
    Draw: 0, outDur, -outYr, outYr, "no", "Curve"

    Select inner viewport: 4.45, 7.70, 3.50, 5.35
    Axes: 0, outDur, -outYr, outYr
    Colour: "{0.80, 0.80, 0.80}"
    Line width: 1
    dStride = ceiling(output_measures / 40)
    if dStride < 1
        dStride = 1
    endif
    for m from 0 to output_measures
        if m mod dStride = 0
            xm = m * measureSec
            if xm <= outDur
                Draw line: xm, -outYr, xm, outYr
            endif
        endif
    endfor

    Select inner viewport: 4.45, 7.70, 3.50, 5.35
    Axes: 0, outDur, -outYr, outYr
    Colour: "Black"
    Draw inner box
    Font size: 6
    @tgStep: outDur, 5
    Marks bottom every: 1, tgStep.step, "yes", "yes", "no"
    @tgStep: 2 * outYr, 4
    Marks left every: 1, tgStep.step, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "output time (s)"
    Text left: "yes", "amplitude"

    # ---------------- Summary strip ----------------
    Select outer viewport: 0, 8, 5.62, 6.19
    Select inner viewport: 0.60, 7.70, 5.67, 6.14
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.80, "half",
        ... "##Grid##  " + fixed$(target_BPM, 1) + " BPM "
        ... + string$(time_signature_numerator) + "/4 " + subdivName$
        ... + "   ##Slots##  " + string$(nSteps)
        ... + "   ##Pool##  " + string$(nSegs)
        ... + "   ##k##  " + string$(tournament_size_k)
        ... + "   ##Tabu##  " + tabuLabel$
    Text: 0.02, "left", 0.50, "half",
        ... "##Weights##  phase " + fixed$(effPhi, 2)
        ... + " / pitch " + fixed$(effPit, 2)
        ... + " / centroid " + fixed$(effCen, 2)
        ... + " / energy " + fixed$(effEne, 2)
        ... + "   ##Coverage##  " + fixed$(coveragePct, 1) + "\%  "
        ... + "   ##Phase error##  " + fixed$(meanPhaseErr, 3)
    Text: 0.02, "left", 0.20, "half",
        ... "##Render##  PSOLA " + string$(nStretched) + "/" + string$(nSteps)
        ... + " | unvoiced expansion skipped " + string$(nUnvoicedExpansionSkipped)
        ... + " | pitch omitted " + string$(pitchOmittedWins) + " joints"
        ... + "   ##Seed##  " + string$(usedSeed)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the full page as the last drawing action. Praat exports
    # the last selected outer viewport; without this, Save as PNG or
    # Copy to clipboard can capture only the summary strip.
    Select outer viewport: 0, 8, 0, 6.19
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Segments: ", nSegs, " (", segMethodName$, ") | coverage ", fixed$(coveragePct,1), "%, most-used ", maxUse, "x"
appendInfoLine: "Mean winning cost: ", fixed$(meanWinCost,4), " | mean tournament spread: ", fixed$(meanSpread,4)
appendInfoLine: "Mean metric-phase error: ", fixed$(meanPhaseErr,4), " of a measure = ", fixed$(1000 * meanPhaseErr * measureSec, 1), " ms"
appendInfoLine: "  vs random-draw baseline ", fixed$(baselinePhaseErr,4), " (", fixed$(phaseImprovePct,1), "% closer). Raise k to tighten this."
appendInfoLine: "Immediate segment repeats: ", immediateRepeats, " of ", nSteps - 1, " joints"
if shrunkTournaments > 0
    appendInfoLine: "Tabu pressure: ", shrunkTournaments, " of ", nSteps, " tournaments had fewer than k eligible candidates"
endif
if tabuRelaxations > 0
    appendInfoLine: "Tabu relaxations (pool emptied): ", tabuRelaxations
endif
appendInfoLine: "PSOLA-stretched slots: ", nStretched, " of ", nSteps, " (", nStretchedUnvoiced, " unvoiced compressions, ", nUnvoicedExpansionSkipped, " unvoiced expansions skipped)"
appendInfoLine: "Pitch term omitted at ", pitchOmittedWins, " winning joints | mean slot-fit error ", fixed$(meanSlotErrSamples,2), " samples"
appendInfoLine: "Crossfade: ", fixed$(fadeMs, 2), " ms effective (", fixed$(crossfade_duration_ms,2), " ms requested)"
appendInfoLine: "Output duration: ", fixed$(outDur, 3), " s  (source ", fixed$(dur, 3), " s)"
appendInfoLine: "Output peak: ", fixed$(outPeak, 4), " (-1 dBFS) | RMS: ", fixed$(outRms, 4), " (", fixed$(outRmsDb,1), " dB)"
appendInfoLine: "Random seed used: ", usedSeed
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments made during processing:"
    appendInfo: warnLines$
endif

removeObject: workSnd
selectObject: outBuf

if play_result
    appendInfoLine: "Playing..."
    Play
endif
