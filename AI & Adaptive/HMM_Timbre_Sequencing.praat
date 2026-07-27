# ============================================================
# Praat AudioTools - HMM_Timbre_Sequencing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.0 (2026) - Unified time base, OLA synthesis, real emissions
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.0:
#
#   NOTE: audio is NOT comparable to v1.3. The model now plays at the
#   rate it was trained at, which alone changes every output.
#
#   CRITICAL 1 - the HMM was trained at one rate and played at another.
#     Transitions were estimated from frames spaced frame_hop_s apart,
#     but synthesis advanced by (frame_size - crossfade). Measured at
#     the 80/40/5 ms defaults: training hop 0.040 s, synthesis advance
#     0.075 s, a slowdown of 1.875x. Every preset was affected
#     (roughly 1.80x to 1.94x), so a pattern learned as an event every
#     50 ms was rendered as an event every 92 ms - the Rhythmic preset
#     could not reproduce its own rhythm.
#     v2.0 makes frame_hop_s the state's time unit at BOTH ends:
#     output frame i starts at (i-1) * frame_hop_s, and the overlap is
#     frame_size - frame_hop by construction (40 ms at the defaults,
#     not 5). Crossfade_ms is gone from the form because it is no
#     longer a free parameter - it was silently redefining the model's
#     tempo.
#
#   CRITICAL 2 - double envelope at every join.
#     Each segment got a manual Fade in / Fade out over crossfade_s and
#     THEN Concatenate with overlap applied its own crossfade to the
#     same region. Measured on a steady 300 Hz tone: 1.26 dB
#     peak-to-trough ripple, 4.58% RMS variation, at the frame rate.
#     v2.0 uses fixed-hop Hann overlap-add with envelope normalization
#     (one window per frame, accumulated, divided out). On the same
#     tone the ripple is now flat to floating-point precision.
#
#   CRITICAL 3 - an empty state could emit a frame from ANY state.
#     If a state held no frames, generation fell back to
#     randomInteger(1, num_frames), i.e. a uniform draw from the whole
#     corpus, which breaks the meaning of the state entirely. Smoothing
#     also kept assigning positive transition mass to empty states, and
#     the first state was drawn uniformly rather than by occupancy.
#     Measured on a steady-tone corpus at K=24: 23 of 24 states ended
#     up empty, 91.85% of every transition row's probability mass
#     pointed at those empty states, and 3 of 54 generated frames were
#     drawn uniformly from the whole corpus. (On a varied corpus at
#     K=8 and K=24 no state emptied, so how often this bites depends
#     entirely on the material.) v2.0 removes it structurally: empty
#     states are pruned from the transition matrix, rows renormalized,
#     and the initial state drawn from occupancy. Re-measured on the
#     same steady-tone corpus: 0 frames from empty states.
#
#   4 - Emissions are now actually used to generate. v1.3 sampled a
#     state and then picked uniformly among that state's corpus frames,
#     so the Gaussians only ever served Viterbi - "sample observations"
#     was not happening. Frame_selection now offers Gaussian (draw an
#     observation from the state's Gaussian, take the nearest frame
#     within that state) or Uniform (the v1.3 behaviour, kept because
#     it is a legitimately different texture).
#
#   5 - Pitch and voicing are separate features. v1.3 wrote 0 Hz for
#     unvoiced frames and fed that into the same dimension as real F0,
#     producing a distribution with a spike at 0 and a continuum above
#     75 Hz - not remotely Gaussian, and the dimension meant two
#     different things at once. Observations are now 5D: intensity,
#     log2 pitch (voiced frames only), voiced fraction, spectral
#     centroid, spectral balance.
#
#   6 - The std floor no longer inflates stable states. v1.3 mapped any
#     std below 0.01 to 0.1 - an eleven-fold widening of the Gaussian
#     for the most consistent states. Observed once at K=24 on the test
#     corpus. Now std = sqrt(variance + eps^2), a continuous
#     regularization, with a genuine floor at 0.01.
#
#   7 - "Spectral slope" was never a slope: it was high/low band energy,
#     unbounded when the low band approached zero, so a single outlier
#     could crush every other frame toward 0 after min-max scaling. It
#     is now log((high + eps) / (low + eps)) and is called
#     spectral balance.
#
#   8 - Spectral analysis uses a Hann-windowed copy of each frame;
#     resynthesis still takes the raw segment. A rectangular cut leaks
#     energy across bins and biased both spectral features.
#
#   9 - Output length is one quantity. Match_input_duration built a few
#     frames too many and only the target-duration branch ever trimmed,
#     so Match Input overshot by up to one advance (measured: 6.004 s
#     for a 6.000 s input). Output_mode now selects the rule and the
#     result is trimmed or extended to the requested length exactly.
#
#   10 - A short fade follows the trim, which can otherwise land
#     mid-frame at a non-zero amplitude.
#
#   11 - Random_seed added (0 = unpredictable). K-means init, the
#     initial state, state sampling and frame choice were all random
#     with no way to reproduce a take. The generator is returned to its
#     safe state afterwards.
#
#   12 - Hard-EM runs to convergence. v1.3 did exactly one Viterbi
#     re-estimation and called it training. Max_HMM_iterations now
#     repeats decode + re-estimate until the path stops changing.
#
#   13 - Interface and reporting: natural fields for the integer
#     counts, the duplicated "Features extracted" line removed, the
#     transition heatmap's Y labels now match its reversed row order,
#     and Stereo_output is documented for what it is - synthetic
#     stereo from independent within-state sampling, not preserved
#     source stereo.
#
# Description:
#   HMM-trained timbre-state corpus resequencer.
#
#   Frames of the source are clustered into timbre states, an HMM is
#   trained over them by Viterbi hard-EM, and new sequences are
#   generated by sampling the transition matrix and drawing a source
#   frame for each visited state.
#
#   HMM Components:
#   - Hidden States: timbre classes (k-means initialization)
#   - Observations: 5D vectors (intensity, log2 pitch, voiced
#     fraction, spectral centroid, spectral balance)
#   - Emission Model: diagonal Gaussian per state
#   - Transition Model: learned state-to-state probabilities
#   - Decoding: log-space Viterbi
#   - Training: hard-EM, repeated to convergence
#   - Generation: sample states -> draw an observation from the
#     state Gaussian -> take the nearest frame in that state
#
#   TIME BASE: one HMM state = frame_hop_s, in training AND in
#   synthesis. Frames are overlap-added at that hop with a Hann
#   window and divided by the accumulated envelope.
#
#   STEREO: synthetic stereo from independent within-state frame
#   sampling. Source stereo is summed to mono first and is NOT
#   preserved.
#
####################################################################
# INPUT VALIDATION
####################################################################

numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound_original = selected("Sound")
sound_name$ = selected$("Sound")

####################################################################
# FORM
####################################################################

form HMM Timbre Sequencer v2.0
    optionmenu Preset 1
        option Custom
        option Fine Grain (subtle, 12 states)
        option Coarse Grain (bold, 5 states)
        option Textural (dense, 16 states)
        option Rhythmic (pulse, 8 states)
        option Experimental (glitchy, 24 states)
    positive Frame_size_ms 80
    positive Frame_hop_ms 40
    natural Number_of_states_K 8
    natural Max_kmeans_iterations 50
    natural Max_HMM_iterations 10
    optionmenu Frame_selection 1
        option Gaussian (draw observation, nearest frame in state)
        option Uniform (any frame in state, equally likely)
    optionmenu Output_mode 2
        option Match input duration
        option Target duration (seconds)
        option Fixed number of frames
    real Target_duration_s 8.0
    natural Output_length_frames 200
    integer Random_seed 0
    boolean Stereo_output 1
    boolean Draw_visualization 1
    boolean Show_info 1
    boolean Play_result 1
endform

####################################################################
# APPLY PRESETS
####################################################################

if preset = 2
    # Fine Grain
    frame_size_ms = 80
    frame_hop_ms = 40
    number_of_states_K = 12
    output_length_frames = 400
    presetName$ = "FineGrain"
elsif preset = 3
    # Coarse Grain
    frame_size_ms = 100
    frame_hop_ms = 50
    number_of_states_K = 5
    output_length_frames = 80
    presetName$ = "CoarseGrain"
elsif preset = 4
    # Textural
    frame_size_ms = 80
    frame_hop_ms = 40
    number_of_states_K = 16
    output_length_frames = 600
    presetName$ = "Textural"
elsif preset = 5
    # Rhythmic
    frame_size_ms = 100
    frame_hop_ms = 50
    number_of_states_K = 8
    output_length_frames = 200
    presetName$ = "Rhythmic"
elsif preset = 6
    # Experimental
    frame_size_ms = 64
    frame_hop_ms = 32
    number_of_states_K = 24
    output_length_frames = 1000
    presetName$ = "Experimental"
else
    presetName$ = "Custom"
endif

####################################################################
# PARAMETER VALIDATION
####################################################################

warnLines$ = ""

if frame_size_ms < 10
    exitScript: "Frame size must be >= 10 ms."
endif

frame_size_s = frame_size_ms / 1000
frame_hop_s = frame_hop_ms / 1000

# v2.0 CRITICAL 1: the hop IS the state's time unit, so it has to be
# usable at both ends. A hop larger than the frame would leave gaps in
# the overlap-add; a hop equal to the frame gives no overlap at all.
if frame_hop_s > frame_size_s
    frame_hop_s = frame_size_s / 2
    warnLines$ = warnLines$ + "  ! Hop exceeded frame size -> set to half the frame" + newline$
endif
if frame_hop_s > frame_size_s * 0.9
    frame_hop_s = frame_size_s * 0.9
    warnLines$ = warnLines$ + "  ! Hop raised above 90% of the frame -> capped" + newline$
endif
frame_hop_ms = frame_hop_s * 1000

# The overlap follows from the hop. v1.3 exposed Crossfade_ms as a free
# parameter and then used it to set the synthesis advance, which is
# what silently retuned the model's tempo.
overlap_s = frame_size_s - frame_hop_s

k = number_of_states_K

# v2.0 fix 11: reproducibility. v1.3 had no seed, so k-means
# initialization and generation both varied run to run with no way to
# recover a take.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

clearinfo
writeInfoLine: "=================================================="
appendInfoLine: "  HMM TIMBRE SEQUENCER v2.0"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "States (K): ", k
appendInfoLine: "Frame: ", fixed$(frame_size_ms, 1), " ms   hop: ",
    ... fixed$(frame_hop_ms, 1), " ms   overlap: ", fixed$(overlap_s * 1000, 1), " ms"
appendInfoLine: "Time base: 1 state = ", fixed$(frame_hop_ms, 1),
    ... " ms in training AND synthesis"
if frame_selection = 1
    appendInfoLine: "Frame choice: Gaussian observation -> nearest in state"
else
    appendInfoLine: "Frame choice: Uniform within state"
endif
appendInfoLine: "Seed: ", seedLabel$
appendInfoLine: ""

####################################################################
# PREPARE AUDIO
####################################################################

selectObject: sound_original
sound_mono = Convert to mono
Rename: sound_name$ + "_mono"

selectObject: sound_mono
duration_s = Get total duration
sampleRate = Get sampling frequency

appendInfoLine: "Audio: ", fixed$(duration_s, 2), " s @ ", sampleRate, " Hz"

####################################################################
# EXTRACT FEATURES
####################################################################

appendInfoLine: ""
appendInfoLine: "Extracting features..."

# Calculate number of frames
num_frames = floor((duration_s - frame_size_s) / frame_hop_s) + 1
appendInfoLine: "  Frames: ", num_frames

# v1.3: validation
if duration_s < 0.1
    removeObject: sound_mono
    exitScript: "Input too short: need at least 0.1 s of audio."
endif
if num_frames < 4
    removeObject: sound_mono
    exitScript: "Input too short for this frame size/hop: only "
        ... + string$(num_frames) + " frames."
endif
if num_frames < k
    removeObject: sound_mono
    exitScript: "Fewer frames (" + string$(num_frames) + ") than states (K="
        ... + string$(k) + "). Use a shorter frame/hop or fewer states."
endif

# Declare feature vectors (v2.0: 5D - pitch and voicing separated)
frame_start# = zero# (num_frames)
raw_int# = zero# (num_frames)
raw_pitch# = zero# (num_frames)
raw_voiced# = zero# (num_frames)
raw_cent# = zero# (num_frames)
raw_bal# = zero# (num_frames)

for i to num_frames
    frame_start#[i] = (i - 1) * frame_hop_s
endfor

# v1.3 computed intensity and pitch once globally and queried them in
# real time coordinates - that fix is kept.
selectObject: sound_mono
globalIntensity = To Intensity: 75, 0, "yes"
selectObject: sound_mono
globalPitch = To Pitch (ac): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600

selectObject: globalPitch
pitchFrames = Get number of frames

specEps = 1e-10

for i to num_frames
    t_start = frame_start#[i]
    t_end = t_start + frame_size_s

    if t_end > duration_s
        t_end = duration_s
    endif

    # --- Intensity ---
    selectObject: globalIntensity
    val = Get mean: t_start, t_end, "energy"
    if val = undefined
        val = 50
    endif
    raw_int#[i] = val

    # --- Pitch and voicing as SEPARATE features (v2.0 fix 5) ---
    # v1.3 stored 0 Hz for unvoiced frames in the same dimension as
    # real F0, so one axis carried both "how high" and "is it pitched",
    # with a mass spike at 0 and a continuum above 75 Hz. Voicing is
    # now its own dimension and pitch is measured only where it exists,
    # in log2 Hz so that an octave is an octave anywhere in the range.
    nVoiced = 0
    nLooked = 0
    sumLogF = 0
    for pf to pitchFrames
        selectObject: globalPitch
        tp = Get time from frame number: pf
        if tp >= t_start and tp <= t_end
            nLooked += 1
            selectObject: globalPitch
            f0 = Get value in frame: pf, "Hertz"
            if f0 <> undefined and f0 > 0
                nVoiced += 1
                sumLogF += log2(f0)
            endif
        endif
    endfor
    if nLooked > 0
        raw_voiced#[i] = nVoiced / nLooked
    else
        raw_voiced#[i] = 0
    endif
    if nVoiced > 0
        raw_pitch#[i] = sumLogF / nVoiced
    else
        # parked at a neutral value; the voiced dimension is what tells
        # the model not to read anything into it
        raw_pitch#[i] = undefined
    endif

    # --- Spectral features on a HANN-WINDOWED copy (v2.0 fix 8) ---
    # A rectangular cut has discontinuous edges and leaks energy across
    # bins, which biased both the centroid and the band ratio. The raw
    # segment is still what gets resynthesized.
    selectObject: sound_mono
    frame_sound = Extract part: t_start, t_end, "Hanning", 1.0, "no"
    selectObject: frame_sound
    To Spectrum: "yes"
    spectrum_obj = selected("Spectrum")

    selectObject: spectrum_obj
    cval = Get centre of gravity: 2
    if cval = undefined
        cval = 1000
    endif
    raw_cent#[i] = cval

    # v2.0 fix 7: this was called "spectral slope" but was
    # high_energy / low_energy, which is unbounded as the low band
    # approaches zero - one outlier could crush every other frame
    # toward 0 after min-max scaling. Log ratio, honestly named.
    selectObject: spectrum_obj
    low_energy = Get band energy: 0, 1000
    selectObject: spectrum_obj
    high_energy = Get band energy: 1000, 5000
    raw_bal#[i] = ln((high_energy + specEps) / (low_energy + specEps))

    removeObject: spectrum_obj, frame_sound
endfor

removeObject: globalIntensity, globalPitch

# Unvoiced frames get the mean of the voiced pitches, so the pitch
# dimension stays finite without inventing a value below the floor.
sumP = 0
cntP = 0
for i to num_frames
    if raw_pitch#[i] <> undefined
        sumP += raw_pitch#[i]
        cntP += 1
    endif
endfor
if cntP > 0
    meanLogF = sumP / cntP
else
    meanLogF = log2(200)
    warnLines$ = warnLines$ +
        ... "  ! No voiced frames found; pitch carries no information here" + newline$
endif
for i to num_frames
    if raw_pitch#[i] = undefined
        raw_pitch#[i] = meanLogF
    endif
endfor

appendInfoLine: "  Features extracted (5D: intensity, log2 pitch, voiced, centroid, balance)"

####################################################################
# NORMALIZE FEATURES  (5 dimensions)
####################################################################

appendInfoLine: "Normalizing features..."

nDims = 5
featName_1$ = "intensity"
featName_2$ = "pitch(log2)"
featName_3$ = "voiced"
featName_4$ = "centroid"
featName_5$ = "balance"

# Pack the raw features into one indexed store so every later stage
# (k-means, Gaussians, Viterbi, generation) loops over dimensions
# instead of repeating itself five times.
for i to num_frames
    raw_1_'i' = raw_int#[i]
    raw_2_'i' = raw_pitch#[i]
    raw_3_'i' = raw_voiced#[i]
    raw_4_'i' = raw_cent#[i]
    raw_5_'i' = raw_bal#[i]
endfor

for d to nDims
    mn = raw_'d'_1
    mx = raw_'d'_1
    for i from 2 to num_frames
        v = raw_'d'_'i'
        if v < mn
            mn = v
        endif
        if v > mx
            mx = v
        endif
    endfor
    rng = mx - mn
    if rng < 0.000001
        rng = 1
    endif
    fmin_'d' = mn
    fmax_'d' = mx
    frange_'d' = rng
endfor

for d to nDims
    for i to num_frames
        norm_'d'_'i' = (raw_'d'_'i' - fmin_'d') / frange_'d'
    endfor
endfor

# Legacy vector names kept for the visualization panels
norm_int# = zero# (num_frames)
norm_pitch# = zero# (num_frames)
norm_cent# = zero# (num_frames)
norm_slope# = zero# (num_frames)
for i to num_frames
    norm_int#[i] = norm_1_'i'
    norm_pitch#[i] = norm_2_'i'
    norm_cent#[i] = norm_4_'i'
    norm_slope#[i] = norm_5_'i'
endfor

####################################################################
# K-MEANS CLUSTERING (INITIALIZE STATES)
####################################################################

appendInfoLine: ""
appendInfoLine: "Running k-means clustering (K=", k, ")..."

# Initialize centroids from distinct frames where possible. v1.3 drew
# each centroid independently, so two could start on the same frame and
# collapse into an empty cluster.
for d to nDims
    for s to k
        cent_'d'_'s' = 0
    endfor
endfor
for s to k
    picked = 0
    tries = 0
    while picked = 0 and tries < 50
        tries += 1
        random_idx = randomInteger(1, num_frames)
        clash = 0
        for s2 from 1 to s - 1
            if seedFrame_'s2' = random_idx
                clash = 1
            endif
        endfor
        if clash = 0 or num_frames <= k
            picked = random_idx
        endif
    endwhile
    if picked = 0
        picked = randomInteger(1, num_frames)
    endif
    seedFrame_'s' = picked
    for d to nDims
        cent_'d'_'s' = norm_'d'_'picked'
    endfor
endfor

state# = zero# (num_frames)

kmeansConverged = 0
iterationsUsed = 0
for iter to max_kmeans_iterations
    if kmeansConverged = 0
        nChanged = 0
        for i to num_frames
            min_dist = 1e30
            best_state = 1
            for s to k
                dist = 0
                for d to nDims
                    diff = norm_'d'_'i' - cent_'d'_'s'
                    dist += diff * diff
                endfor
                if dist < min_dist
                    min_dist = dist
                    best_state = s
                endif
            endfor
            if state#[i] <> best_state
                nChanged += 1
            endif
            state#[i] = best_state
        endfor

        for s to k
            cnt = 0
            for d to nDims
                sumD_'d' = 0
            endfor
            for i to num_frames
                if state#[i] = s
                    cnt += 1
                    for d to nDims
                        sumD_'d' = sumD_'d' + norm_'d'_'i'
                    endfor
                endif
            endfor
            if cnt > 0
                for d to nDims
                    cent_'d'_'s' = sumD_'d' / cnt
                endfor
            endif
        endfor

        iterationsUsed = iter
        if nChanged = 0
            kmeansConverged = 1
        endif
    endif
endfor

appendInfoLine: "K-means completed (", iterationsUsed, " iterations)"

####################################################################
# COMPUTE EMISSION PROBABILITIES (GAUSSIAN)
####################################################################

appendInfoLine: "Computing emission distributions..."

# Declare emission vectors (filled by estimateEmissions; the
# procedure preserves previous means for states that lose all
# members, so declare-once here)
emit_mean_int# = zero# (k)
emit_mean_pitch# = zero# (k)
emit_mean_cent# = zero# (k)
emit_mean_slope# = zero# (k)
emit_std_int# = zero# (k)
emit_std_pitch# = zero# (k)
emit_std_cent# = zero# (k)
emit_std_slope# = zero# (k)
state_count# = zero# (k)

# Declare every emission cell before the first estimate. A state that
# loses all its members keeps whatever it had; without this, a
# degenerate corpus (e.g. a constant tone, where k-means leaves states
# empty from the start) left cells undefined and the run aborted.
for d to nDims
    for s to k
        emitMean_'d'_'s' = 0.5
        emitStd_'d'_'s' = 0.1
    endfor
endfor

@estimateEmissions

####################################################################
# COMPUTE TRANSITION PROBABILITIES
####################################################################

appendInfoLine: "Learning transition probabilities..."

# Simulate 2D arrays with 1D indexing: index = (s1-1)*k + s2
max_trans_size = k * k
trans_count# = zero# (max_trans_size)
trans_prob# = zero# (max_trans_size)

@estimateTransitions

####################################################################
# VITERBI DECODE + ONE HARD-EM RE-ESTIMATION (v1.3)
#
# Decode the most likely hidden-state path under the learned
# Gaussian emissions and transition matrix (log-space Viterbi),
# then re-estimate emissions and transitions from the decoded
# path (one hard-EM iteration). The k-means labels serve as the
# initialization; the decoded path is what generation and the
# visualization use -- panel 2's "Viterbi Path" label is now true.
####################################################################

# v2.0 fix 12: hard-EM to convergence. v1.3 ran exactly one Viterbi
# re-estimation and described it as training.
appendInfoLine: "Viterbi decoding (hard-EM, up to ", max_HMM_iterations, " iterations)..."

hmmIter = 0
hmmConverged = 0
prevDelta# = zero# (k)
curDelta# = zero# (k)
psi# = zero# (num_frames * k)
viterbi_state# = zero# (num_frames)
emitLog# = zero# (num_frames * k)
lnTrans# = zero# (k * k)

for emIter to max_HMM_iterations
    if hmmConverged = 0
        hmmIter = emIter

        for i to num_frames
            for s to k
                acc = 0
                nrm = 0
                for d to nDims
                    z = (norm_'d'_'i' - emitMean_'d'_'s') / emitStd_'d'_'s'
                    acc += z * z
                    nrm += ln(emitStd_'d'_'s')
                endfor
                emitLog#[(i - 1) * k + s] = -0.5 * acc - nrm
            endfor
        endfor

        for idx to k * k
            if trans_prob#[idx] > 0
                lnTrans#[idx] = ln(trans_prob#[idx])
            else
                lnTrans#[idx] = -1e30
            endif
        endfor

        # Initial probabilities from state occupancy (smoothed over
        # ACTIVE states only)
        activeTotal = 0
        for s to k
            if state_count#[s] > 0
                activeTotal += state_count#[s] + 0.5
            endif
        endfor
        if activeTotal <= 0
            activeTotal = 1
        endif
        for s to k
            if state_count#[s] > 0
                piS = (state_count#[s] + 0.5) / activeTotal
                prevDelta#[s] = ln(piS) + emitLog#[s]
            else
                prevDelta#[s] = -1e30
            endif
        endfor

        for i from 2 to num_frames
            for s to k
                best = -1e30
                bestPrev = 1
                for s1 to k
                    v = prevDelta#[s1] + lnTrans#[(s1 - 1) * k + s]
                    if v > best
                        best = v
                        bestPrev = s1
                    endif
                endfor
                curDelta#[s] = best + emitLog#[(i - 1) * k + s]
                psi#[(i - 1) * k + s] = bestPrev
            endfor
            prevDelta# = curDelta#
        endfor

        best = prevDelta#[1]
        bestS = 1
        for s from 2 to k
            if prevDelta#[s] > best
                best = prevDelta#[s]
                bestS = s
            endif
        endfor
        viterbi_state#[num_frames] = bestS

        for back to num_frames - 1
            i = num_frames - back
            viterbi_state#[i] = psi#[i * k + viterbi_state#[i + 1]]
        endfor

        nChangedV = 0
        for i to num_frames
            if viterbi_state#[i] <> state#[i]
                nChangedV += 1
            endif
        endfor
        state# = viterbi_state#

        @estimateEmissions
        @estimateTransitions

        appendInfoLine: "  iter ", emIter, ": ", nChangedV, "/", num_frames,
            ... " frame assignments changed"
        if nChangedV = 0
            hmmConverged = 1
        endif
    endif
endfor

if hmmConverged
    appendInfoLine: "  Converged after ", hmmIter, " iterations"
else
    appendInfoLine: "  Stopped at the iteration limit (path still moving)"
endif

# Active-state bookkeeping used by generation (v2.0 CRITICAL 3)
nActiveStates = 0
activeTotalCount = 0
for s to k
    if state_count#[s] > 0
        nActiveStates += 1
        activeTotalCount += state_count#[s]
    endif
endfor
appendInfoLine: "  Active states: ", nActiveStates, "/", k
if nActiveStates < k
    warnLines$ = warnLines$ + "  . " + string$(k - nActiveStates) +
        ... " state(s) ended up empty and were pruned from the chain" + newline$
endif

####################################################################
# GENERATE SEQUENCE (HMM SAMPLING)
####################################################################

appendInfoLine: ""
appendInfoLine: "Generating HMM sequence..."

# v2.0 CRITICAL 1 + fix 9: output length is expressed in the SAME time
# unit the model was trained on. v1.3 advanced by
# (frame_size - crossfade) at synthesis while estimating transitions at
# frame_hop_s - measured 0.075 s against 0.040 s at the defaults, a
# 1.875x slowdown. One state now equals one hop, everywhere.
advance_s = frame_hop_s

# One quantity decides the length, and it is always honoured exactly.
# v1.3 let Match_input build a few frames too many while only the
# target-duration branch ever trimmed (measured: 6.004 s out for a
# 6.000 s input).
if output_mode = 1
    desired_duration = duration_s
    useDuration = 1
elsif output_mode = 2
    desired_duration = target_duration_s
    useDuration = 1
    if desired_duration <= 0
        desired_duration = duration_s
        warnLines$ = warnLines$ +
            ... "  ! Target duration <= 0 -> matching input instead" + newline$
    endif
else
    useDuration = 0
endif

if useDuration
    base_output_length = ceiling(desired_duration / advance_s) + 1
    if base_output_length < 2
        base_output_length = 2
    endif
    appendInfoLine: "Output: ", fixed$(desired_duration, 3), " s (",
        ... base_output_length, " frames at ", fixed$(advance_s * 1000, 1), " ms hop)"
else
    base_output_length = output_length_frames
    desired_duration = base_output_length * advance_s + (frame_size_s - advance_s)
    appendInfoLine: "Output: ", output_length_frames, " frames -> ",
        ... fixed$(desired_duration, 3), " s"
endif

output_sequence_length = base_output_length
max_output_frames = output_sequence_length + 4
output_state# = zero# (max_output_frames)
output_frame# = zero# (max_output_frames)

# Initial state drawn by OCCUPANCY over active states. v1.3 used
# randomInteger(1, k), which could start the chain in an empty state.
rInit = randomUniform(0, activeTotalCount)
cum = 0
current_state = 0
for s to k
    if state_count#[s] > 0
        cum += state_count#[s]
        if current_state = 0 and rInit <= cum
            current_state = s
        endif
    endif
endfor
if current_state = 0
    for s to k
        if current_state = 0 and state_count#[s] > 0
            current_state = s
        endif
    endfor
endif
output_state#[1] = current_state

for i from 2 to output_sequence_length
    rand = randomUniform(0, 1)
    cumulative = 0
    next_state = 0
    for s to k
        if next_state = 0
            idx = (current_state - 1) * k + s
            cumulative += trans_prob#[idx]
            if rand <= cumulative
                next_state = s
            endif
        endif
    endfor
    if next_state = 0
        # rounding shortfall: fall back to the last active state, never
        # to an empty one
        for s to k
            if next_state = 0 and state_count#[s] > 0
                next_state = s
            endif
        endfor
    endif
    output_state#[i] = next_state
    current_state = next_state
endfor

# ============================================================
# FRAME SELECTION
# ============================================================
# v2.0 fix 4: v1.3 described "sample states -> sample observations",
# but observations were never sampled: it picked uniformly among the
# state's corpus frames, so the Gaussians only ever served Viterbi.
# Gaussian mode draws a 5D observation from the state's own
# distribution and takes the nearest frame WITHIN that state, which is
# what the description always claimed. Uniform mode is v1.3's
# behaviour, kept because it is a genuinely different texture.

appendInfoLine: "Selecting frames per state..."

# Membership lists per state
for s to k
    memberCount_'s' = 0
endfor
for f to num_frames
    s = state#[f]
    memberCount_'s' = memberCount_'s' + 1
    idxm = memberCount_'s'
    member_'s'_'idxm' = f
endfor

procedure pickFrame: .state
    .cnt = memberCount_'.state'
    if .cnt < 1
        # Structurally unreachable now: empty states are pruned from
        # the transition matrix and cannot be the initial state either.
        .cnt = 0
    endif
    if .cnt = 1
        pickFrame.result = member_'.state'_1
    elsif frame_selection = 2 or .cnt < 1
        .r = randomInteger(1, .cnt)
        pickFrame.result = member_'.state'_'.r'
    else
        # draw an observation from the state Gaussian
        for .d to nDims
            .obs_'.d' = emitMean_'.d'_'.state' +
                ... randomGauss(0, 1) * emitStd_'.d'_'.state'
        endfor
        .bestD = 1e30
        .bestF = member_'.state'_1
        for .m to .cnt
            .f = member_'.state'_'.m'
            .dd = 0
            for .d to nDims
                .df = norm_'.d'_'.f' - .obs_'.d'
                .dd += .df * .df
            endfor
            if .dd < .bestD
                .bestD = .dd
                .bestF = .f
            endif
        endfor
        pickFrame.result = .bestF
    endif
endproc

####################################################################
# SYNTHESIZE OUTPUT - FIXED-HOP HANN OVERLAP-ADD
#
# v2.0 CRITICAL 1 + 2. Frames are placed at (i-1) * frame_hop_s, which
# is the interval the transition matrix was estimated over, and each is
# windowed ONCE with a Hann and divided out by the accumulated
# envelope. v1.3 faded every segment manually over crossfade_s and then
# handed the set to Concatenate with overlap, which applies its own
# crossfade to the same samples: measured 1.26 dB peak-to-trough
# ripple at the frame rate on a steady tone, on top of the 1.875x
# slowdown from the advance mismatch.
####################################################################

appendInfoLine: ""
appendInfoLine: "Synthesizing audio (Hann OLA at ", fixed$(frame_hop_ms, 1), " ms hop)..."

procedure buildSequence: .n
    .bufDur = (.n - 1) * frame_hop_s + frame_size_s + 0.05
    Create Sound from formula: "hmm_out", 1, 0, .bufDur, sampleRate, "0"
    .outBuf = selected("Sound")
    Create Sound from formula: "hmm_env", 1, 0, .bufDur, sampleRate, "0"
    .envBuf = selected("Sound")

    for .i to .n
        .fi = buildFrames#[.i]
        .t1 = frame_start#[.fi]
        .t2 = .t1 + frame_size_s
        if .t2 > duration_s
            .t2 = duration_s
        endif

        selectObject: sound_mono
        .seg = Extract part: .t1, .t2, "rectangular", 1.0, "no"
        selectObject: .seg
        .segDur = Get total duration

        # exactly one window per frame
        if .segDur > 0.0005
            selectObject: .seg
            Formula: "self * (0.5 - 0.5 * cos(2 * pi * (x - xmin) / (xmax - xmin)))"
        endif

        .pos = (.i - 1) * frame_hop_s
        if .pos + .segDur > .bufDur
            .segDur = .bufDur - .pos
        endif
        if .segDur > 0.0005
            selectObject: .seg
            Shift times to: "start time", .pos
            .sid$ = string$(.seg)
            .p0$ = fixed$(.pos, 9)
            .gl$ = fixed$(.segDur, 9)

            selectObject: .outBuf
            Formula (part): .pos, .pos + .segDur, 1, 1,
                ... "self + object(" + .sid$ + ", x)"

            selectObject: .envBuf
            Formula (part): .pos, .pos + .segDur, 1, 1,
                ... "self + (0.5 - 0.5 * cos(2 * pi * (x - " + .p0$ + ") / " + .gl$ + "))"
        endif
        removeObject: .seg
    endfor

    # divide by the accumulated envelope, with the divisor floored so
    # the head and tail fade instead of being boosted
    selectObject: .envBuf
    .envPeak = Get absolute extremum: 0, 0, "None"
    if .envPeak < 1e-9
        .envPeak = 1e-9
    endif
    .ef$ = fixed$(.envPeak * 0.15, 9)
    .eid$ = string$(.envBuf)
    selectObject: .outBuf
    Formula: "self / max(object[" + .eid$ + ", col], " + .ef$ + ")"
    removeObject: .envBuf

    .cat = .outBuf

    # v2.0 fix 9: the requested length is delivered exactly, whichever
    # mode asked for it.
    selectObject: .cat
    .d = Get total duration
    if .d > desired_duration
        selectObject: .cat
        .tr = Extract part: 0, desired_duration, "rectangular", 1, "no"
        removeObject: .cat
        .cat = .tr
    elsif .d < desired_duration - 0.0005
        Create Sound from formula: "hmm_pad", 1, 0, desired_duration - .d, sampleRate, "0"
        .pad = selected("Sound")
        selectObject: .cat
        plusObject: .pad
        .joined = Concatenate
        removeObject: .cat, .pad
        .cat = .joined
    endif

    # v2.0 fix 10: the trim can land mid-frame at a non-zero amplitude.
    selectObject: .cat
    .rd = Get total duration
    .fade = 0.005
    if .fade > .rd * 0.1
        .fade = .rd * 0.1
    endif
    if .fade > 0.0002
        .fs$ = fixed$(.fade, 8)
        selectObject: .cat
        Formula: "if x - xmin < " + .fs$ + " then self * ((x - xmin) / " + .fs$ + ") else self fi"
        selectObject: .cat
        Formula: "if xmax - x < " + .fs$ + " then self * ((xmax - x) / " + .fs$ + ") else self fi"
    endif

    selectObject: .cat
    Scale peak: 0.95
    buildSequence.result = .cat
endproc

if stereo_output
    appendInfoLine: "Creating synthetic stereo (independent within-state sampling)..."

    output_frame_L# = zero# (output_sequence_length)
    output_frame_R# = zero# (output_sequence_length)

    for i to output_sequence_length
        s = output_state#[i]
        @pickFrame: s
        output_frame_L#[i] = pickFrame.result
        @pickFrame: s
        output_frame_R#[i] = pickFrame.result
    endfor

    buildFrames# = output_frame_L#
    @buildSequence: output_sequence_length
    left_channel = buildSequence.result

    buildFrames# = output_frame_R#
    @buildSequence: output_sequence_length
    right_channel = buildSequence.result

    selectObject: left_channel, right_channel
    output_sound = Combine to stereo
    Rename: sound_name$ + "_HMM_" + presetName$ + "_stereo"
    removeObject: left_channel, right_channel
else
    for i to output_sequence_length
        s = output_state#[i]
        @pickFrame: s
        output_frame#[i] = pickFrame.result
    endfor

    buildFrames# = zero# (output_sequence_length)
    for i to output_sequence_length
        buildFrames#[i] = output_frame#[i]
    endfor
    @buildSequence: output_sequence_length
    output_sound = buildSequence.result
    selectObject: output_sound
    Rename: sound_name$ + "_HMM_" + presetName$
endif

# v2.0 fix 11: all random draws are done.
random_initializeSafelyAndUnpredictably ()

appendInfoLine: "Generated ", output_sequence_length, " frames"

####################################################################
# VISUALIZATION
####################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Color palette for states (up to 24 states)
    state_colors$# = {
    ... "{0.2, 0.4, 0.8}", "{0.8, 0.2, 0.4}", "{0.2, 0.8, 0.4}", "{0.8, 0.6, 0.2}",
    ... "{0.6, 0.2, 0.8}", "{0.2, 0.8, 0.8}", "{0.8, 0.8, 0.2}", "{0.8, 0.4, 0.6}",
    ... "{0.4, 0.8, 0.6}", "{0.6, 0.4, 0.8}", "{0.3, 0.6, 0.3}", "{0.6, 0.3, 0.6}",
    ... "{0.5, 0.5, 0.2}", "{0.2, 0.5, 0.5}", "{0.5, 0.2, 0.5}", "{0.7, 0.5, 0.3}",
    ... "{0.3, 0.7, 0.5}", "{0.5, 0.3, 0.7}", "{0.4, 0.4, 0.4}", "{0.6, 0.6, 0.6}",
    ... "{0.3, 0.3, 0.8}", "{0.8, 0.3, 0.3}", "{0.3, 0.8, 0.3}", "{0.7, 0.7, 0.3}"
    ... }
    
    # v1.3: layout converted to the library-standard 8-wide canvas
    # (outer+inner viewports, 0.6/7.7 margins, ##Bold## title,
    # font 6-7 labels, summary strip at the bottom).

    # State-axis mark step (avoid clutter at high K)
    markStep = ceiling(k / 12)
    if markStep < 1
        markStep = 1
    endif

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", -1.7, "half",
        ... "##HMM Timbre Sequencer v2.0##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.20, "half",
        ... sound_name$ + " | " + presetName$
        ... + " | K=" + string$(k)
        ... + " | " + string$(num_frames) + " -> " + string$(output_sequence_length) + " frames"
        ... + " | frame " + string$(frame_size_ms) + " ms"

    # === PANEL: INPUT STATE SEQUENCE (VITERBI PATH) ===
    Select outer viewport: 0, 4, 0.50, 2.00
    Select inner viewport: 0.6, 3.85, 0.60, 1.95

    max_time_input = duration_s
    Axes: 0, max_time_input, 0.5, k + 0.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_input, 0.5, k + 0.5

    for i to num_frames
        s = state#[i]
        t_start = frame_start#[i]
        if i < num_frames
            t_end = frame_start#[i + 1]
        else
            t_end = max_time_input
        endif
        color_idx = ((s - 1) mod 24) + 1
        Paint rectangle: state_colors$#[color_idx], t_start, t_end, s - 0.4, s + 0.4
    endfor

    Colour: "Black"
    Draw inner box
    Marks left every: 1, markStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "State"
    Text top: "no", "Input states (Viterbi path)"
    Text bottom: "yes", "Time (s)"

    # === PANEL: OUTPUT STATE SEQUENCE ===
    Select outer viewport: 4, 8, 0.50, 2.00
    Select inner viewport: 4.2, 7.7, 0.60, 1.95

    # Output frames advance by (frame_size - crossfade)
    max_time_output = output_sequence_length * advance_s + (frame_size_s - advance_s)
    Axes: 0, max_time_output, 0.5, k + 0.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_output, 0.5, k + 0.5

    for i to output_sequence_length
        s = output_state#[i]
        t_start = (i - 1) * advance_s
        t_end = i * advance_s
        color_idx = ((s - 1) mod 24) + 1
        Paint rectangle: state_colors$#[color_idx], t_start, t_end, s - 0.4, s + 0.4
    endfor

    Colour: "Black"
    Draw inner box
    Marks left every: 1, markStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "State"
    Text top: "no", "Generated states (HMM sampling)"
    Text bottom: "yes", "Time (s)"

    # === PANEL: FEATURE TRAJECTORIES ===
    Select outer viewport: 0, 8, 2.05, 3.85
    Select inner viewport: 0.6, 7.7, 2.15, 3.80

    Axes: 0, max_time_input, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_input, 0, 1

    Colour: "{0.9, 0.9, 0.9}"
    level = 0.25
    while level <= 0.75
        Draw line: 0, level, max_time_input, level
        level = level + 0.25
    endwhile

    feature_colors$# = {"{0.2, 0.4, 0.8}", "{0.8, 0.2, 0.4}", "{0.2, 0.8, 0.4}", "{0.8, 0.6, 0.2}"}
    feature_names$# = {"Intensity", "Pitch", "Centroid", "Slope"}

    Colour: feature_colors$#[1]
    Line width: 1.5
    for i from 1 to num_frames - 1
        Draw line: frame_start#[i], norm_int#[i], frame_start#[i + 1], norm_int#[i + 1]
    endfor

    Colour: feature_colors$#[2]
    for i from 1 to num_frames - 1
        Draw line: frame_start#[i], norm_pitch#[i], frame_start#[i + 1], norm_pitch#[i + 1]
    endfor

    Colour: feature_colors$#[3]
    for i from 1 to num_frames - 1
        Draw line: frame_start#[i], norm_cent#[i], frame_start#[i + 1], norm_cent#[i + 1]
    endfor

    Colour: feature_colors$#[4]
    for i from 1 to num_frames - 1
        Draw line: frame_start#[i], norm_slope#[i], frame_start#[i + 1], norm_slope#[i + 1]
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Normalized"
    Text top: "no", "Feature trajectories (4D observations)"
    Text bottom: "yes", "Time (s)"

    Font size: 6
    x_legend = max_time_input * 0.02
    Colour: feature_colors$#[1]
    Text: x_legend, "left", 0.95, "half", feature_names$#[1]
    Colour: feature_colors$#[2]
    Text: x_legend, "left", 0.86, "half", feature_names$#[2]
    Colour: feature_colors$#[3]
    Text: x_legend, "left", 0.77, "half", feature_names$#[3]
    Colour: feature_colors$#[4]
    Text: x_legend, "left", 0.68, "half", feature_names$#[4]

    # === PANEL: TRANSITION MATRIX HEATMAP ===
    Select outer viewport: 0, 4, 3.90, 6.10
    Select inner viewport: 0.8, 3.7, 4.00, 6.00

    Axes: 0.5, k + 0.5, 0.5, k + 0.5

    for s1 to k
        for s2 to k
            idx = (s1 - 1) * k + s2
            prob = trans_prob#[idx]
            gray_level = 1 - prob
            if gray_level < 0
                gray_level = 0
            endif
            if gray_level > 1
                gray_level = 1
            endif
            color$ = "{" + string$(gray_level) + ", " + string$(gray_level) + ", " + string$(gray_level) + "}"
            Paint rectangle: color$, s2 - 0.5, s2 + 0.5, k - s1 + 0.5, k - s1 + 1.5
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, markStep, "yes", "yes", "no"
    # v2.0 fix 13: rows are painted in reverse (state 1 at the top), so
    # the default left marks labelled every row with the wrong state.
    # Drawn explicitly to match the paint order.
    Font size: 6
    for s1 to k
        if (s1 - 1) mod markStep = 0
            One mark left: k - s1 + 1, "no", "yes", "no", string$(s1)
        endif
    endfor
    Font size: 7
    Text bottom: "yes", "To state"
    Text left: "yes", "From state"
    Text top: "no", "Transitions (darker = higher p)"

    # === PANEL: EMISSION DISTRIBUTIONS ===
    Select outer viewport: 4, 8, 3.90, 6.10
    Select inner viewport: 4.35, 7.7, 4.00, 6.00

    Axes: 0.5, k + 0.5, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, k + 0.5, 0, 1

    bar_width = 0.15
    feature_offset# = {-0.3, -0.1, 0.1, 0.3}

    for s to k
        mean_val = emit_mean_int#[s]
        std_val = emit_std_int#[s]
        x_pos = s + feature_offset#[1]
        Colour: feature_colors$#[1]
        Paint rectangle: feature_colors$#[1], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)

        mean_val = emit_mean_pitch#[s]
        std_val = emit_std_pitch#[s]
        x_pos = s + feature_offset#[2]
        Colour: feature_colors$#[2]
        Paint rectangle: feature_colors$#[2], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)

        mean_val = emit_mean_cent#[s]
        std_val = emit_std_cent#[s]
        x_pos = s + feature_offset#[3]
        Colour: feature_colors$#[3]
        Paint rectangle: feature_colors$#[3], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)

        mean_val = emit_mean_slope#[s]
        std_val = emit_std_slope#[s]
        x_pos = s + feature_offset#[4]
        Colour: feature_colors$#[4]
        Paint rectangle: feature_colors$#[4], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, markStep, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "State"
    Text left: "yes", "Mean +- std"
    Text top: "no", "Emissions (Gaussian per state)"

    # === SUMMARY STRIP ===
    Select outer viewport: 0, 8, 6.20, 6.90
    Select inner viewport: 0.6, 7.7, 6.25, 6.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    selectObject: output_sound
    vizOutDur = Get total duration
    vizOutCh = Get number of channels

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half",
        ... "##Model##  K=" + string$(k)
        ... + "  frames " + string$(num_frames) + " -> " + string$(output_sequence_length)
        ... + "  k-means " + string$(iterationsUsed) + " iter"
        ... + "  Viterbi changed " + string$(nChangedV) + "/" + string$(num_frames)
    Text: 0.02, "left", 0.48, "half",
        ... "##Frames##  size=" + string$(frame_size_ms) + " ms"
        ... + "  hop=" + string$(frame_hop_ms) + " ms"
        ... + "  advance=" + fixed$(advance_s * 1000, 0) + " ms"
        ... + "  overlap=" + fixed$(overlap_s * 1000, 1) + " ms"
    Text: 0.02, "left", 0.18, "half",
        ... "##Output##  " + fixed$(vizOutDur, 2) + " s"
        ... + "  " + string$(vizOutCh) + " ch"
        ... + "  preset=" + presetName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete!"
endif

####################################################################
# CLEANUP
####################################################################

removeObject: sound_mono

selectObject: output_sound

if show_info
    selectObject: output_sound
    dur = Get total duration
    n_ch = Get number of channels
    appendInfoLine: ""
    appendInfoLine: "=== Complete ==="
    appendInfoLine: "Output: ", selected$("Sound")
    appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
    appendInfoLine: "Channels: ", n_ch
    appendInfoLine: ""
    appendInfoLine: "HMM Model:"
    appendInfoLine: "  States: ", k, " hidden timbre classes"
    appendInfoLine: "  Observations: 5D (intensity, log2 pitch, voiced, centroid, balance)"
    appendInfoLine: "  Emissions: Gaussian (mean + std per feature)"
if frame_selection = 1
    appendInfoLine: "  Generation: observation sampled from state Gaussian"
else
    appendInfoLine: "  Generation: uniform within state"
endif
appendInfoLine: "  Time base: 1 state = " + fixed$(frame_hop_ms, 1) + " ms (train = synth)"
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Notes:"
    appendInfo: warnLines$
endif
    appendInfoLine: "  Transitions: Learned from data"
endif

if play_result
    Play
endif
####################################################################
# PROCEDURES (v1.3)
####################################################################

# Estimate Gaussian emissions and state occupancy from the current
# global state# assignment. States with no members keep their
# previous means (generation falls back to a random frame for them
# anyway); stds get the standard floors.
procedure estimateEmissions
    state_count# = zero# (k)
    for .d to nDims
        for .s to k
            .sum_'.d'_'.s' = 0
        endfor
    endfor

    for .i to num_frames
        .s = state#[.i]
        state_count#[.s] += 1
        for .d to nDims
            .sum_'.d'_'.s' = .sum_'.d'_'.s' + norm_'.d'_'.i'
        endfor
    endfor

    for .s to k
        if state_count#[.s] > 0
            for .d to nDims
                emitMean_'.d'_'.s' = .sum_'.d'_'.s' / state_count#[.s]
            endfor
        endif
    endfor

    for .d to nDims
        for .s to k
            .var_'.d'_'.s' = 0
        endfor
    endfor
    for .i to num_frames
        .s = state#[.i]
        for .d to nDims
            .dv = norm_'.d'_'.i' - emitMean_'.d'_'.s'
            .var_'.d'_'.s' = .var_'.d'_'.s' + .dv * .dv
        endfor
    endfor

    # v2.0 fix 6: continuous variance regularization. v1.3 tested
    # "if std < 0.01 then std = 0.1", which is not a floor at 0.01 - a
    # state measuring 0.009 was widened elevenfold, and the most
    # consistent states were punished hardest. Observed once at K=24 on
    # the test corpus.
    .eps = 0.02
    .hardFloor = 0.01
    for .s to k
        for .d to nDims
            if state_count#[.s] > 1
                .v = .var_'.d'_'.s' / state_count#[.s]
            else
                # a single member carries no spread; the epsilon below
                # is what gives it a usable width
                .v = 0
            endif
            .sd = sqrt(.v + .eps * .eps)
            if .sd < .hardFloor
                .sd = .hardFloor
            endif
            emitStd_'.d'_'.s' = .sd
        endfor
    endfor

    # Legacy names for the visualization panels
    for .s to k
        emit_mean_int#[.s] = emitMean_1_'.s'
        emit_mean_pitch#[.s] = emitMean_2_'.s'
        emit_mean_cent#[.s] = emitMean_4_'.s'
        emit_mean_slope#[.s] = emitMean_5_'.s'
        emit_std_int#[.s] = emitStd_1_'.s'
        emit_std_pitch#[.s] = emitStd_2_'.s'
        emit_std_cent#[.s] = emitStd_4_'.s'
        emit_std_slope#[.s] = emitStd_5_'.s'
    endfor
endproc

# Count transitions in the current global state# assignment and
# convert to row-normalized probabilities with add-constant
# smoothing.
procedure estimateTransitions
    trans_count# = zero# (max_trans_size)

    for .i from 1 to num_frames - 1
        .idx = (state#[.i] - 1) * k + state#[.i + 1]
        trans_count#[.idx] += 1
    endfor

    # v2.0 CRITICAL 3: an empty state must not be reachable. v1.3
    # smoothed every cell equally, so states holding no frames kept a
    # slice of probability in every row; generation could then walk
    # into one and fall back to a uniform draw over the WHOLE corpus,
    # which is the one thing a state model must never do.
    .smoothing = 0.01
    for .s1 to k
        .rowSum = 0
        for .s2 to k
            .idx = (.s1 - 1) * k + .s2
            if state_count#[.s2] > 0
                .rowSum += trans_count#[.idx] + .smoothing
            endif
        endfor

        for .s2 to k
            .idx = (.s1 - 1) * k + .s2
            if state_count#[.s2] = 0
                trans_prob#[.idx] = 0
            elsif .rowSum > 0
                trans_prob#[.idx] = (trans_count#[.idx] + .smoothing) / .rowSum
            else
                trans_prob#[.idx] = 0
            endif
        endfor

        # A row that reaches nothing (no active target at all) spreads
        # evenly over the active states instead of being left at zero.
        if .rowSum <= 0
            .nAct = 0
            for .s2 to k
                if state_count#[.s2] > 0
                    .nAct += 1
                endif
            endfor
            if .nAct > 0
                for .s2 to k
                    .idx = (.s1 - 1) * k + .s2
                    if state_count#[.s2] > 0
                        trans_prob#[.idx] = 1 / .nAct
                    endif
                endfor
            endif
        endif
    endfor
endproc

# Build one audio sequence from buildFrames#[1..n]: extract and
# fade all segments, join them in a single Concatenate-with-overlap,
# then loop and/or trim to the target duration if one is set.

