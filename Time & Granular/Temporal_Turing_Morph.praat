# ============================================================
# Praat AudioTools - Temporal_Turing_Morph.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026)
# License: MIT License
#
# Description:
#   Applies a 1D activator-inhibitor reaction-diffusion process to
#   a sequence of audio segments, using the resulting spatial
#   pattern to creatively reorder them in time.
#
#   Unlike granular synthesis (ms-scale grains), this operates
#   at the EVENT scale (5ms-2000ms). A spatial pattern forms
#   across the segment sequence; that pattern becomes the
#   reordering logic.
#
#   MATHEMATICAL MODEL (1D activator-inhibitor reaction-diffusion):
#     dA/dt = Da*Lap1D(A) + r*A*(1 - A/K) - s*A*I
#     dI/dt = Di*Lap1D(I) + r*A - s*I
#   Lap1D = discrete 1D Laplacian over the segment-index axis.
#
#   NOTE ON DYNAMICS: these kinetics are stable at their non-zero
#   equilibrium and do NOT undergo a true Turing bifurcation (both
#   reaction self-derivatives are negative, so Da*g_I + Di*f_A < 0
#   for any Da,Di). The visible structure is driven by the seed
#   perturbation plus a small per-iteration stochastic term, shaped
#   -- not created -- by diffusion. This is a musically useful
#   reaction-diffusion morph, not a Turing pattern generator. For a
#   genuine Turing system, swap the kinetics for Gierer-Meinhardt or
#   Gray-Scott (where Di >> Da really is the instability condition).
#
#   REORDER MODES:
#   Sort      - output segments ranked by ascending activator
#               value -> clusters of similar activator level.
#   Displace  - each segment shifts forward/back by an amount
#               proportional to (A[i] - mean(A)); high spots pull
#               forward, low spots push back -> local smearing.
#   StripeRev - within each contiguous band (segments on the same
#               side of mean(A)), the internal order is reversed
#               -> palindromic pockets inside forward motion.
#
#   SEED MODES:
#   Flat + noise   - pattern emerges from the random seed
#   Energy-seeded  - RMS envelope seeds the activator so the
#                    pattern grows out of the audio's own dynamics
#
#   MORPH BLEND (0..1):
#   0.0 = original order unchanged
#   1.0 = full reordered permutation
#   Between: a proportional prefix of the adjacent transpositions
#   that turn identity into the target order is applied, so the
#   deviation from the original grows monotonically with morph.
#
#   ARC / DRIFT / RUPTURE: these shape the R-D evolution ACROSS
#   ITERATIONS, which changes the single final pattern used for
#   reordering. They do NOT animate the audio along its own
#   timeline -- e.g. "Expand-Collapse" bends the simulation
#   trajectory that yields one permutation, it does not make the
#   output literally expand then collapse in time.
#
#   COMPUTATIONAL PIPELINE:
#   1. Sound -> N segments (last may be shorter; whole file covered)
#   2. Optional: extract RMS envelope for energy seeding
#   3. Initialize 1D activator A[1..N], inhibitor I[1..N]
#   4. Iterate 1D R-D (explicit Euler, reflective boundaries)
#   5. Compute permutation from final A[] state
#   6. Apply monotonic morph blend
#   7. Apply cosine edge taper (fade in/out) to each segment
#   8. Concatenate in reordered order -> output Sound
#   9. Visualization: activator pattern, permutation map,
#      waveforms, energy evolution, parameter summary
#
# Category: Temporal / Experimental / Composition
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcID    = selected("Sound")
srcName$ = selected$("Sound")
selectObject: srcID
srcDur = Get total duration
srcFs  = Get sampling frequency
srcCh  = Get number of channels

if srcDur < 0.05
    exitScript: "Sound must be at least 50 ms."
endif

# ============================================================
# FORM  (no comment lines — keeps form height minimal)
# ============================================================

form Temporal Turing Morph v1.1
    optionmenu Preset: 1
        option Custom
        option Temporal Stutter  (short chunks, frozen stripes)
        option Phrase Scrambler  (medium chunks, volatile)
        option Memory Erosion    (long chunks, displacement)
        option Rhythmic Crystal  (micro-bands, sorted clusters)
        option Narrative Arc     (expand then collapse)
        option Tectonic Rupture  (drift plus burst events)
    positive Chunk_duration_ms 80.0
    positive Diffusion_rate 1.0
    positive Reaction_rate 0.20
    positive Inhibition_strength 0.30
    integer  Iterations 25
    real     Initial_perturbation 0.05
    optionmenu Reorder_mode: 1
        option Sort  (R-D rank)
        option Displace  (R-D shift)
        option StripeRev  (palindrome within stripes)
    integer  Max_displacement_segments 10
    real     Morph_amount 1.0
    optionmenu Seed_mode: 1
        option Flat + noise
        option Energy-seeded
    real     Edge_taper_ms 5.0
    optionmenu Arc_mode: 1
        option Off  (constant)
        option Expand-Collapse  (peak then rupture)
        option Collapse-Regrow  (decay then recovery)
        option Pulse  (cyclic tension)
    real     Arc_strength 0.8
    real     Drift_strength 0.0
    real     Rupture_prob 0.0
    integer  Random_seed 0
    boolean  Normalize_output 1
    boolean  Draw_visualization 1
    boolean  Play_result 1
endform

# Hardcoded dramaturgy (edit in script for fine-tuning)
noise_per_iter   = 0.02
satCeiling       = 5.0
rupture_strength = 2.5

# ============================================================
# PRESET OVERRIDES
# ============================================================

if preset = 2
    # Temporal Stutter: frozen stripe pattern over short chunks
    chunk_duration_ms         = 20.0
    diffusion_rate            = 2.5
    reaction_rate             = 0.35
    inhibition_strength       = 0.30
    iterations                = 50
    initial_perturbation           = 0.05
    reorder_mode              = 1
    max_displacement_segments = 15
    morph_amount              = 1.0
    seed_mode                 = 1
    edge_taper_ms              = 2.0
    arc_mode                  = 1
    arc_strength              = 0.0
    drift_strength            = 0.0
    rupture_prob              = 0.0
elsif preset = 3
    # Phrase Scrambler: volatile mid-point, medium chunks sorted
    chunk_duration_ms         = 250.0
    diffusion_rate            = 1.5
    reaction_rate             = 0.60
    inhibition_strength       = 0.30
    iterations                = 7
    initial_perturbation           = 0.08
    reorder_mode              = 1
    max_displacement_segments = 20
    morph_amount              = 1.0
    seed_mode                 = 2
    edge_taper_ms              = 12.0
    arc_mode                  = 1
    arc_strength              = 0.0
    drift_strength            = 0.0
    rupture_prob              = 0.0
elsif preset = 4
    # Memory Erosion: displacement mode, energy-seeded, long chunks
    chunk_duration_ms         = 400.0
    diffusion_rate            = 1.2
    reaction_rate             = 0.25
    inhibition_strength       = 0.40
    iterations                = 20
    initial_perturbation           = 0.05
    reorder_mode              = 2
    max_displacement_segments = 8
    morph_amount              = 0.75
    seed_mode                 = 2
    edge_taper_ms              = 20.0
    arc_mode                  = 1
    arc_strength              = 0.0
    drift_strength            = 0.0
    rupture_prob              = 0.0
elsif preset = 5
    # Rhythmic Crystal: high inhibition → tight stripes, sorted
    chunk_duration_ms         = 50.0
    diffusion_rate            = 0.05
    reaction_rate             = 0.15
    inhibition_strength       = 0.85
    iterations                = 80
    initial_perturbation           = 0.05
    reorder_mode              = 1
    max_displacement_segments = 30
    morph_amount              = 1.0
    seed_mode                 = 1
    edge_taper_ms              = 3.0
    arc_mode                  = 1
    arc_strength              = 0.0
    drift_strength            = 0.0
    rupture_prob              = 0.0
elsif preset = 6
    # Narrative Arc: energy-seeded, expansion then sharp collapse
    chunk_duration_ms         = 120.0
    diffusion_rate            = 1.2
    reaction_rate             = 0.30
    inhibition_strength       = 0.25
    iterations                = 40
    initial_perturbation           = 0.05
    reorder_mode              = 1
    max_displacement_segments = 15
    morph_amount              = 1.0
    seed_mode                 = 2
    edge_taper_ms              = 8.0
    arc_mode                  = 2
    arc_strength              = 0.9
    drift_strength            = 0.0
    rupture_prob              = 0.0
elsif preset = 7
    # Tectonic Rupture: drifting diffusion hotspot + burst events
    chunk_duration_ms         = 80.0
    diffusion_rate            = 1.5
    reaction_rate             = 0.25
    inhibition_strength       = 0.30
    iterations                = 35
    initial_perturbation           = 0.05
    reorder_mode              = 2
    max_displacement_segments = 12
    morph_amount              = 1.0
    seed_mode                 = 2
    edge_taper_ms              = 6.0
    arc_mode                  = 1
    arc_strength              = 0.0
    drift_strength            = 1.2
    rupture_prob              = 0.12
endif

# ============================================================
# CLAMPS
# ============================================================

if chunk_duration_ms < 5.0
    chunk_duration_ms = 5.0
endif
if chunk_duration_ms > 2000.0
    chunk_duration_ms = 2000.0
endif
if diffusion_rate < 0.001
    diffusion_rate = 0.001
endif
if diffusion_rate > 5.0
    diffusion_rate = 5.0
endif
if reaction_rate < 0.001
    reaction_rate = 0.001
endif
if reaction_rate > 1.0
    reaction_rate = 1.0
endif
if inhibition_strength < 0.01
    inhibition_strength = 0.01
endif
if inhibition_strength > 2.0
    inhibition_strength = 2.0
endif
if iterations < 1
    iterations = 1
endif
if iterations > 200
    iterations = 200
endif
if initial_perturbation < 0.001
    initial_perturbation = 0.001
endif
if initial_perturbation > 0.5
    initial_perturbation = 0.5
endif
if morph_amount < 0.0
    morph_amount = 0.0
endif
if morph_amount > 1.0
    morph_amount = 1.0
endif
if edge_taper_ms < 0.0
    edge_taper_ms = 0.0
endif
if max_displacement_segments < 1
    max_displacement_segments = 1
endif
if max_displacement_segments > 100
    max_displacement_segments = 100
endif
if arc_strength < 0.0
    arc_strength = 0.0
endif
if arc_strength > 1.0
    arc_strength = 1.0
endif
if drift_strength < 0.0
    drift_strength = 0.0
endif
if drift_strength > 3.0
    drift_strength = 3.0
endif
if rupture_prob < 0.0
    rupture_prob = 0.0
endif
if rupture_prob > 0.5
    rupture_prob = 0.5
endif

# ============================================================
# DERIVED PARAMETERS
# ============================================================

chunkDur     = chunk_duration_ms / 1000.0
edgeTaperDur = edge_taper_ms / 1000.0

diffA  = diffusion_rate * 0.08
diffI  = diffusion_rate * 4.0
# Fixed, stable time step. Previously dt = 0.85/(4*diffI) cancelled the
# diffusion coefficient (dt*diffI was constant, so Diffusion_rate did nothing
# to the diffusion) and blew up at low diffusion. Size dt for the WORST case:
# the largest diffI (Diffusion_rate<=5 -> diffI<=20) AND the largest drift bias
# (local_bias up to 1+Drift_strength), so the explicit-Euler CFL holds even
# when a strong drift hotspot multiplies the local diffusion. Diffusion_rate
# still genuinely scales the per-iteration diffusion (dt*diffI grows with it).
diffI_ceiling = 5.0 * 4.0
maxBias = 1.0 + drift_strength
dtSafe = 0.85 / (4.0 * diffI_ceiling * maxBias)

# Segment count. Use ceiling so the WHOLE file is covered; the final segment
# may be shorter than a chunk (the extractor clamps it to the file end). If we
# would exceed the segment cap, grow the chunk so the whole file still fits.
nSeg = ceiling(srcDur / chunkDur)
if nSeg < 2
    exitScript: "Chunk too long - fewer than 2 segments. Use a shorter Chunk_duration_ms."
endif
maxSeg = 500
segNote$ = ""
if nSeg > maxSeg
    chunkDur = srcDur / maxSeg
    chunk_duration_ms = chunkDur * 1000.0
    nSeg = maxSeg
    segNote$ = "Note: chunk enlarged to " + fixed$(chunk_duration_ms, 1) +
        ... " ms so all " + fixed$(srcDur, 2) + " s fit within " + string$(maxSeg) + " segments."
endif

# Seed the RNG AFTER the early-exit checks above, so a seeded run can't leave
# Praat in the predictable state by exiting before the restore at the end.
# random_initializeWithSeedUnsafelyButPredictably is a formula FUNCTION
# (parenthesis call, not a colon command); its predictable state persists in
# Praat until random_initializeSafelyAndUnpredictably() is called. In auto mode
# we reset to the safe state explicitly, so results don't depend on RNG state
# left behind by a previous script.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedNote$ = "seed=" + string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedNote$ = "seed=auto (not reproducible)"
endif

# Reorder mode label
if reorder_mode = 1
    modeStr$ = "Sort (R-D rank)"
elsif reorder_mode = 2
    modeStr$ = "Displace (R-D shift)"
else
    modeStr$ = "StripeRev (band palindrome)"
endif

# ============================================================
# INFO HEADER
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  Temporal Turing Morph v1.1"
writeInfoLine:  "=================================================="
appendInfoLine: ""
appendInfoLine: "Source   : ", srcName$, "  (", fixed$(srcDur, 3), " s  ", srcCh, " ch)"
appendInfoLine: "Chunk    : ", fixed$(chunk_duration_ms, 1), " ms  ->  ", nSeg, " segments"
if segNote$ <> ""
    appendInfoLine: "  ", segNote$
endif
appendInfoLine: ""
appendInfoLine: "1D activator-inhibitor R-D (not a true Turing bifurcation):"
appendInfoLine: "  Da=", fixed$(diffA, 4), "  Di=", fixed$(diffI, 4),
    ... "  (Di/Da=", fixed$(diffI / diffA, 0), "x)"
appendInfoLine: "  r=", fixed$(reaction_rate, 4), "  s=", fixed$(inhibition_strength, 4),
    ... "  dt=", fixed$(dtSafe, 6)
appendInfoLine: "  iterations=", iterations, "  perturb=", fixed$(initial_perturbation, 4),
    ... "  ", seedNote$
appendInfoLine: ""
appendInfoLine: "Reorder  : ", modeStr$, "  morph=", fixed$(morph_amount, 2)
appendInfoLine: "Edge taper: ", fixed$(edge_taper_ms, 1), " ms"
appendInfoLine: ""

# ============================================================
# STEP 1: PREPARE MONO WORKING COPY
# ============================================================

selectObject: srcID
if srcCh > 1
    # True mono mixdown (average of all channels), not just channel 1 --
    # otherwise a file with content only on channel 2 would come out silent.
    monoSrc = Convert to mono
    Rename: "tTM_mono"
else
    monoSrc = Copy: "tTM_mono"
endif

# ============================================================
# STEP 2: EXTRACT SEGMENTS
# ============================================================

appendInfoLine: "[1/5] Extracting ", nSeg, " segments..."

segID#  = zero#(nSeg)
segRMS# = zero#(nSeg)

for i from 1 to nSeg
    t1 = (i - 1) * chunkDur
    t2 = t1 + chunkDur
    if t2 > srcDur
        t2 = srcDur
    endif
    selectObject: monoSrc
    tmpSeg = Extract part: t1, t2, "rectangular", 1, "no"
    Rename: "tTM_seg_" + string$(i)
    segID#[i] = selected("Sound")
    selectObject: segID#[i]
    segRMS#[i] = Get root-mean-square: 0, 0
    if segRMS#[i] < 1e-10
        segRMS#[i] = 1e-10
    endif
endfor

# ============================================================
# STEP 3: INITIALIZE 1D R-D VECTORS  A[1..nSeg], I[1..nSeg]
# ============================================================

appendInfoLine: "[2/5] Initializing 1D R-D (", nSeg, " cells)..."

act# = zero#(nSeg)
inh# = zero#(nSeg)

if seed_mode = 2
    # Energy-seeded: normalize RMS → [0,1], then add small noise
    rmsMax = max(segRMS#)
    if rmsMax < 1e-10
        rmsMax = 1e-10
    endif
    for i from 1 to nSeg
        act#[i] = segRMS#[i] / rmsMax + initial_perturbation * randomGauss(0.0, 1.0)
        if act#[i] < 0
            act#[i] = 0
        endif
    endfor
else
    # Flat + noise: pure mathematical emergence
    for i from 1 to nSeg
        act#[i] = 0.5 + initial_perturbation * randomGauss(0.0, 1.0)
        if act#[i] < 0
            act#[i] = 0
        endif
    endfor
endif

# Inhibitor starts matched to activator
for i from 1 to nSeg
    inh#[i] = act#[i]
endfor

# ============================================================
# STEP 4: RUN 1D REACTION-DIFFUSION
# ============================================================

appendInfoLine: "[3/5] Running ", iterations, " R-D iterations..."

iterMean# = zero#(iterations)

# --- Pre-compute arc reaction rate profile over all iterations ---
# arc_r#[iter] is the effective reaction rate at that iteration.
# Arc mode shapes the instability arc: expansion, collapse, recovery.
arc_r# = zero#(iterations)
for iter from 1 to iterations
    if iterations > 1
        t_arc = (iter - 1) / (iterations - 1)
    else
        t_arc = 0.0
    endif
    if arc_mode = 1
        arc_factor = 1.0
    elsif arc_mode = 2
        # Expand then collapse: rises to peak at 65%, sharp drop after
        if t_arc < 0.65
            arc_factor = t_arc / 0.65
        else
            arc_factor = 1.0 - (t_arc - 0.65) / 0.35 * 3.0
            if arc_factor < 0.05
                arc_factor = 0.05
            endif
        endif
    elsif arc_mode = 3
        # Collapse then regrow: U-shaped minimum at midpoint
        arc_factor = 1.0 - 4.0 * t_arc * (1.0 - t_arc)
        if arc_factor < 0.05
            arc_factor = 0.05
        endif
    else
        # Pulse: two sinusoidal cycles of tension/release
        arc_factor = 0.5 + 0.5 * cos(4.0 * pi * t_arc)
    endif
    arc_r#[iter] = reaction_rate * (1.0 - arc_strength + arc_strength * arc_factor)
    if arc_r#[iter] < 0.001
        arc_r#[iter] = 0.001
    endif
endfor

# --- Pre-allocate work vectors ---
act_pad#   = zero#(nSeg + 2)
inh_pad#   = zero#(nSeg + 2)
lap_act#   = zero#(nSeg)
lap_inh#   = zero#(nSeg)
d_act#     = zero#(nSeg)
d_inh#     = zero#(nSeg)
local_bias# = zero#(nSeg)
drift_spread = max(nSeg / 4.0, 2.0)

for iter from 1 to iterations

    # --- Arc: effective reaction rate this iteration ---
    r_iter = arc_r#[iter]

    # --- Drift: Gaussian hotspot sweeping across segment positions ---
    if drift_strength > 0.0
        if iterations > 1
            t_drift = (iter - 1) / (iterations - 1)
        else
            t_drift = 0.0
        endif
        bias_center = 1.0 + t_drift * (nSeg - 1)
        for i from 1 to nSeg
            dist_sq = (i - bias_center) * (i - bias_center)
            local_bias#[i] = 1.0 + drift_strength * exp(-dist_sq / (drift_spread * drift_spread))
        endfor
    else
        for i from 1 to nSeg
            local_bias#[i] = 1.0
        endfor
    endif

    # --- Reflective boundary padding ---
    act_pad#[1] = act#[2]
    inh_pad#[1] = inh#[2]
    for i from 1 to nSeg
        act_pad#[i + 1] = act#[i]
        inh_pad#[i + 1] = inh#[i]
    endfor
    if nSeg > 1
        act_pad#[nSeg + 2] = act#[nSeg - 1]
        inh_pad#[nSeg + 2] = inh#[nSeg - 1]
    else
        act_pad#[nSeg + 2] = act#[nSeg]
        inh_pad#[nSeg + 2] = inh#[nSeg]
    endif

    # --- 1D discrete Laplacian: L[i] = A[i-1] - 2*A[i] + A[i+1] ---
    for i from 1 to nSeg
        lap_act#[i] = act_pad#[i] - 2.0 * act_pad#[i + 1] + act_pad#[i + 2]
        lap_inh#[i] = inh_pad#[i] - 2.0 * inh_pad#[i + 1] + inh_pad#[i + 2]
    endfor

    # --- Activator-inhibitor R-D update (arc rate + drift bias per cell) ---
    for i from 1 to nSeg
        aV = act#[i]
        iV = inh#[i]
        d_act#[i] = local_bias#[i] * diffA * lap_act#[i] + r_iter * aV * (1.0 - aV / satCeiling) - inhibition_strength * aV * iV
        d_inh#[i] = local_bias#[i] * diffI * lap_inh#[i] + r_iter * aV - inhibition_strength * iV
    endfor

    # --- Explicit Euler step + symmetry-breaking noise ---
    for i from 1 to nSeg
        act#[i] = act#[i] + dtSafe * d_act#[i] + noise_per_iter * randomGauss(0.0, 1.0)
        inh#[i] = inh#[i] + dtSafe * d_inh#[i]
        if act#[i] < 0
            act#[i] = 0
        endif
        if act#[i] > satCeiling
            act#[i] = satCeiling
        endif
        if inh#[i] < 0
            inh#[i] = 0
        endif
        if inh#[i] > satCeiling
            inh#[i] = satCeiling
        endif
    endfor

    # --- Rupture events: stochastic burst injection ---
    # Fires with probability rupture_prob each iteration.
    # Injects a Gaussian energy spike at a random position,
    # temporarily exceeding satCeiling — the inhibitor suppresses
    # it over the following iterations, creating collapse dynamics.
    if rupture_prob > 0.0
        if randomUniform(0.0, 1.0) < rupture_prob
            r_center = round(randomUniform(1.0, nSeg * 1.0))
            if r_center < 1
                r_center = 1
            endif
            if r_center > nSeg
                r_center = nSeg
            endif
            for i from 1 to nSeg
                r_dist = abs(i - r_center)
                if r_dist <= 4
                    burst = rupture_strength * exp(-r_dist * r_dist * 0.5)
                    act#[i] = act#[i] + burst
                endif
            endfor
        endif
    endif

    iterMean#[iter] = mean(act#)

endfor

appendInfoLine: "  A_mean final: ", fixed$(iterMean#[iterations], 4)

# ============================================================
# STEP 5: COMPUTE PERMUTATION FROM R-D PATTERN
# ============================================================

appendInfoLine: "[4/5] Computing reorder permutation (", modeStr$, ")..."

# Range of act# (used by Displace for mean-centered shift scaling)
aMin   = min(act#)
aMax   = max(act#)
aRange = aMax - aMin
if aRange < 1e-10
    aRange = 1e-10
endif

turingOrder# = zero#(nSeg)

if reorder_mode = 1
    # SORT: output slot j ← segment with j-th smallest activator value
    # Manual argsort (selection sort) — Praat has no sort_index#
    turingOrder# = zero#(nSeg)
    sortUsed#    = zero#(nSeg)   ; 1 = already placed
    for j from 1 to nSeg
        bestIdx = 0
        bestVal = 1e38
        for k from 1 to nSeg
            if sortUsed#[k] = 0 and act#[k] < bestVal
                bestVal = act#[k]
                bestIdx = k
            endif
        endfor
        turingOrder#[j] = bestIdx
        sortUsed#[bestIdx] = 1
    endfor

elsif reorder_mode = 2
    # DISPLACE: segment i targets position i + shift(A[i])
    # Segments with A > mean shift forward; A < mean shift back.
    # Sort segments by target position → defines output order.
    aMeanVal = mean(act#)
    # Normalize by the largest deviation from the mean so |shift| never exceeds
    # max_displacement_segments (dividing by range*2 could overshoot the user's
    # stated maximum for skewed activator distributions).
    maxDev = max(abs(aMax - aMeanVal), abs(aMin - aMeanVal))
    if maxDev < 1e-10
        maxDev = 1e-10
    endif
    targetPos# = zero#(nSeg)
    for i from 1 to nSeg
        # Shift proportional to (A[i] - mean(A)): above-mean segments move
        # forward, below-mean move back, bounded by max_displacement_segments.
        shift = round((act#[i] - aMeanVal) / maxDev * max_displacement_segments)
        targetPos#[i] = i + shift
    endfor
    # Sort segments by target position — manual argsort on targetPos#
    sortUsed2#   = zero#(nSeg)
    for j from 1 to nSeg
        bestIdx2 = 0
        bestVal2 = 1e38
        for k from 1 to nSeg
            if sortUsed2#[k] = 0 and targetPos#[k] < bestVal2
                bestVal2 = targetPos#[k]
                bestIdx2 = k
            endif
        endfor
        turingOrder#[j] = bestIdx2
        sortUsed2#[bestIdx2] = 1
    endfor

else
    # STRIPEREV: reverse segment order within each activator band.
    # A stripe = contiguous run of segments on same side of mean(A).
    # Start with identity, then reverse each run in-place.
    for i from 1 to nSeg
        turingOrder#[i] = i
    endfor
    aMeanVal = mean(act#)
    runStart = 1
    # Detect run boundaries (i = nSeg+1 is the sentinel)
    for i from 2 to nSeg + 1
        # Is this the end of the current run?
        endOfRun = 0
        if i > nSeg
            endOfRun = 1
        elsif (act#[i] > aMeanVal) <> (act#[runStart] > aMeanVal)
            endOfRun = 1
        endif
        if endOfRun = 1
            runEnd = i - 1
            runLen = runEnd - runStart + 1
            # Reverse within [runStart .. runEnd]
            halfLen = floor((runLen - 1) / 2)
            for k from 0 to halfLen
                tmp = turingOrder#[runStart + k]
                turingOrder#[runStart + k] = turingOrder#[runEnd - k]
                turingOrder#[runEnd - k] = tmp
            endfor
            runStart = i
        endif
    endfor

endif

# --- Monotonic morph blend: identity ↔ reordered permutation ---
# The old scheme interpolated index numbers, rounded, and patched duplicates,
# which is non-monotonic (raising morph could move the output CLOSER to the
# original). Instead: take the sequence of adjacent transpositions that turns
# identity into turingOrder, and apply a morph-fraction PREFIX of them. The
# result is always a valid permutation and its deviation from the original
# grows monotonically with morph.

finalOrder# = zero#(nSeg)
for i from 1 to nSeg
    finalOrder#[i] = i
endfor

if morph_amount >= 0.999
    # Full permutation
    for i from 1 to nSeg
        finalOrder#[i] = turingOrder#[i]
    endfor
elsif morph_amount > 0.001
    # Record adjacent swaps that bubble-sort a copy of turingOrder back to
    # identity; reversed, these build turingOrder from identity.
    maxSwaps = floor(nSeg * (nSeg - 1) / 2) + 1
    swapPos# = zero#(maxSwaps)
    work#    = zero#(nSeg)
    for i from 1 to nSeg
        work#[i] = turingOrder#[i]
    endfor
    nSwaps = 0
    for a from 1 to nSeg
        for p from 1 to nSeg - 1
            if work#[p] > work#[p + 1]
                tmpw          = work#[p]
                work#[p]      = work#[p + 1]
                work#[p + 1]  = tmpw
                nSwaps        = nSwaps + 1
                swapPos#[nSwaps] = p
            endif
        endfor
    endfor
    # Apply the first round(morph * nSwaps) swaps of the reversed sequence.
    kApply = round(morph_amount * nSwaps)
    for q from 1 to kApply
        p = swapPos#[nSwaps - q + 1]
        tmpf              = finalOrder#[p]
        finalOrder#[p]    = finalOrder#[p + 1]
        finalOrder#[p + 1] = tmpf
    endfor
endif

# ============================================================
# STEP 6: APPLY COSINE EDGE TAPER (fade in/out) TO EACH SEGMENT
# ============================================================

if edgeTaperDur > 0.0005
    for i from 1 to nSeg
        selectObject: segID#[i]
        segLen = Get total duration
        fadeT  = edgeTaperDur
        if fadeT > segLen * 0.40
            fadeT = segLen * 0.40
        endif
        # Cosine taper via Formula — both fade-in and fade-out in one pass
        fadeTStr$ = fixed$(fadeT, 8)
        segLenStr$ = fixed$(segLen, 8)
        Formula: "if x < " + fadeTStr$ + " then self * 0.5 * (1 - cos(pi * x / " + fadeTStr$ + ")) " +
            ... "else if x > " + segLenStr$ + " - " + fadeTStr$ + " then self * 0.5 * (1 + cos(pi * (x - (" + segLenStr$ + " - " + fadeTStr$ + ")) / " + fadeTStr$ + ")) " +
            ... "else self fi fi"
    endfor
endif

# ============================================================
# STEP 7: CONCATENATE IN REORDERED ORDER
# ============================================================

appendInfoLine: "[5/5] Reassembling ", nSeg, " segments..."

# Copy each segment in final order into temporary objects
# (copying avoids any Praat duplicate-selection issues)
tmpID# = zero#(nSeg)
for j from 1 to nSeg
    selectObject: segID#[round(finalOrder#[j])]
    tmpID#[j] = Copy: "tTM_out_" + string$(j)
endfor

# Multi-select and concatenate
selectObject: tmpID#[1]
for j from 2 to nSeg
    plusObject: tmpID#[j]
endfor
Concatenate
rawSynth = selected("Sound")

if normalize_output = 1
    selectObject: rawSynth
    Scale peak: 0.99
endif

# ============================================================
# CLEANUP TEMPORARIES
# ============================================================

for j from 1 to nSeg
    removeObject: tmpID#[j]
endfor
for i from 1 to nSeg
    removeObject: segID#[i]
endfor
removeObject: monoSrc

# ============================================================
# NAME OUTPUT
# ============================================================

outputName$ = srcName$ + "_TemporalTuring"
selectObject: rawSynth
Rename: outputName$
resultID  = selected("Sound")
resultDur = Get total duration

appendInfoLine: ""
appendInfoLine: "Output: ", outputName$, "  (", fixed$(resultDur, 3), " s)"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1

    appendInfoLine: "[Viz] Drawing..."

    Erase all

    # --- Title bar ---
    Select outer viewport: 0, 8, 0, 0.46
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.73, "half", "##Temporal Turing Morph v1.1##"
    Font size: 7.5
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", -0.08, "half",
        ... srcName$
        ... + "  |  " + string$(nSeg) + " segs × " + fixed$(chunk_duration_ms, 0) + "ms"
        ... + "  iter=" + string$(iterations)
        ... + "  " + modeStr$
        ... + "  morph=" + fixed$(morph_amount, 1)

    # --- Panel 1: activator pattern (the permutation driver) ---
    Select outer viewport: 0, 8, 0.50, 1.42
    Select inner viewport: 0.58, 7.65, 0.55, 1.37
    aMinViz = min(act#)
    aMaxViz = max(act#)
    aRangeViz = aMaxViz - aMinViz
    if aRangeViz < 0.0001
        aRangeViz = 0.0001
    endif
    yBotA = aMinViz - aRangeViz * 0.10
    yTopA = aMaxViz + aRangeViz * 0.22
    Axes: 0, nSeg + 1, yBotA, yTopA
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nSeg + 1, yBotA, yTopA
    # Mean reference line
    Colour: "{0.85, 0.65, 0.22}"
    Dotted line
    Draw line: 0, mean(act#), nSeg + 1, mean(act#)
    Solid line
    # Activator as vertical bars, blue→orange gradient
    Line width: 1
    for i from 1 to nSeg
        frac = (i - 1) / max(nSeg - 1, 1)
        cR = 0.22 + frac * 0.60
        cG = 0.48 - frac * 0.20
        cB = 0.72 - frac * 0.55
        Colour: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
        Draw line: i, aMinViz, i, act#[i]
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "A(i)"
    Text top: "no", "1D activator pattern  (spatial structure -> reordering)"

    # --- Panel 2: Permutation map  original index → output slot ---
    Select outer viewport: 0, 8, 1.46, 2.38
    Select inner viewport: 0.58, 7.65, 1.51, 2.33
    Axes: 0, nSeg + 1, 0, nSeg + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nSeg + 1, 0, nSeg + 1
    # Identity diagonal
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, 0, nSeg + 1, nSeg + 1
    Solid line
    # Permutation as vertical line segments (output slot j ← original finalOrder[j])
    Line width: 1
    for j from 1 to nSeg
        frac = (j - 1) / max(nSeg - 1, 1)
        cR = 0.22 + frac * 0.60
        cG = 0.48 - frac * 0.20
        cB = 0.72 - frac * 0.55
        Colour: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
        # Draw tick at (finalOrder[j], j)
        Draw line: finalOrder#[j] - 0.3, j, finalOrder#[j] + 0.3, j
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out pos"
    Text bottom: "yes", "Orig. segment"
    Text top: "no", "Permutation map  (diagonal = identity, deviation = R-D reorder)"

    # --- Panel 3 & 4: Input / Output waveforms ---
    selectObject: srcID
    srcPeak = Get absolute extremum: 0, 0, "None"
    if srcPeak < 0.001
        srcPeak = 0.001
    endif
    ampMax = srcPeak * 1.15
    # The output is peak-normalized independently, so scale its panel to its
    # OWN peak; otherwise a quiet source would push the output waveform out of
    # the frame.
    selectObject: resultID
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampMaxOut = outPeak * 1.15

    Select outer viewport: 0, 8, 2.42, 3.14
    Select inner viewport: 0.58, 7.65, 2.47, 3.09
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, srcDur, 0
    selectObject: srcID
    Colour: "{0.42, 0.48, 0.58}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Original: " + srcName$

    Select outer viewport: 0, 8, 3.17, 3.89
    Select inner viewport: 0.58, 7.65, 3.22, 3.84
    Axes: 0, resultDur, -ampMaxOut, ampMaxOut
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, resultDur, -ampMaxOut, ampMaxOut
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, resultDur, 0
    selectObject: resultID
    Colour: "{0.20, 0.72, 0.48}"
    Draw: 0, 0, -ampMaxOut, ampMaxOut, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", outputName$
    Text bottom: "yes", "Time (s)"

    # --- Panel 5: Activator energy evolution + arc profile overlay ---
    Select outer viewport: 0, 5.5, 3.93, 4.85
    Select inner viewport: 0.55, 5.20, 3.98, 4.80

    minE = iterMean#[1]
    maxE = iterMean#[1]
    for ii from 2 to iterations
        if iterMean#[ii] < minE
            minE = iterMean#[ii]
        endif
        if iterMean#[ii] > maxE
            maxE = iterMean#[ii]
        endif
    endfor
    eRange = maxE - minE
    if eRange < 0.0001
        eRange = 0.0001
    endif
    yBotE = minE - eRange * 0.12
    yTopE = maxE + eRange * 0.28

    Axes: 0, iterations + 1, yBotE, yTopE
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, iterations + 1, yBotE, yTopE

    # Arc profile as faint filled band (scaled to energy range)
    if arc_mode > 1
        Colour: "{0.90, 0.80, 0.60}"
        for ii from 2 to iterations
            arcScaled_prev = yBotE + (arc_r#[ii - 1] / reaction_rate) * eRange * 0.35
            arcScaled_now  = yBotE + (arc_r#[ii]     / reaction_rate) * eRange * 0.35
            Draw line: ii - 1, arcScaled_prev, ii, arcScaled_now
        endfor
        Font size: 5
        Text: iterations * 0.72, "left", yBotE + eRange * 0.35 + eRange * 0.08, "half", "arc"
    endif

    # Reference line: mean A after iteration 1 (not the raw seed)
    Colour: "{0.85, 0.65, 0.22}"
    Dotted line
    Draw line: 0, iterMean#[1], iterations + 1, iterMean#[1]
    Solid line

    # Energy curve — color transitions blue (early) to orange (late)
    Line width: 2
    for ii from 2 to iterations
        eFrac = (ii - 1) / iterations
        cR = 0.22 + eFrac * 0.60
        cG = 0.48 - eFrac * 0.20
        cB = 0.72 - eFrac * 0.55
        Colour: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
        Draw line: ii - 1, iterMean#[ii - 1], ii, iterMean#[ii]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "A mean"
    Text bottom: "yes", "Iteration"
    Text top: "no", "Activator mean A per iteration  (gold = arc profile, colour = progress)"

    # --- Panel 6: R-D parameter summary ---
    Select outer viewport: 5.5, 8, 3.93, 4.85
    Select inner viewport: 5.68, 7.65, 3.98, 4.80
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.06, "left", 0.93, "half", "##Activator-Inhibitor R-D##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.40}"
    Text: 0.06, "left", 0.81, "half",
        ... "Da=" + fixed$(diffA, 3) + "  Di=" + fixed$(diffI, 3)
        ... + "  (Di/Da=" + fixed$(diffI / diffA, 0) + "x)"
    Text: 0.06, "left", 0.69, "half",
        ... "r=" + fixed$(reaction_rate, 3) + "  s=" + fixed$(inhibition_strength, 3)
        ... + "  dt=" + fixed$(dtSafe, 5)
    Text: 0.06, "left", 0.57, "half",
        ... "iter=" + string$(iterations) + "  segs=" + string$(nSeg)
        ... + "  perturb=" + fixed$(initial_perturbation, 3)
    Text: 0.06, "left", 0.45, "half",
        ... "chunk=" + fixed$(chunk_duration_ms, 0) + "ms"
        ... + "  morph=" + fixed$(morph_amount, 2)
    Text: 0.06, "left", 0.33, "half",
        ... "arc=" + string$(arc_mode) + "  str=" + fixed$(arc_strength, 2)
        ... + "  drift=" + fixed$(drift_strength, 2)
    Text: 0.06, "left", 0.21, "half",
        ... "rupture p=" + fixed$(rupture_prob, 3)
        ... + "  str=" + fixed$(rupture_strength, 1)
    Text: 0.06, "left", 0.09, "half",
        ... "mode: " + modeStr$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# ============================================================
# SUMMARY
# ============================================================

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=================================================="
appendInfoLine: "Output   : ", outputName$
appendInfoLine: "Duration : ", fixed$(resultDur, 3), " s"
appendInfoLine: "Segments : ", nSeg, "  (nominal chunk ", fixed$(chunk_duration_ms, 1), " ms; final may be shorter)"
appendInfoLine: "Reorder  : ", modeStr$, "  morph=", fixed$(morph_amount, 2)
appendInfoLine: "A_mean final: ", fixed$(iterMean#[iterations], 5)

selectObject: resultID

if play_result = 1
    Play
endif

# Undo the predictable-RNG state so it doesn't persist across later Praat work.
if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif
