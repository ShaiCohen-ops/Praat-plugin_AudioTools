# ============================================================
# Praat AudioTools - Rhythmatist.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   RHYTHMATIST - Rhythmic Strata System with Spectral Identity.
#   Cuts a sound at the points of a mathematical rhythmic series, puts the
#   segments in a new temporal order and plays each one at its own speed
#   (tape-style varispeed: speed changes duration and pitch together).
#   The composition is built from three independent stages:
#     1. Segmentation   - which durations (Su, Sc, Sy, Sd, SRC)
#     2. Organization   - in which order
#     3. Speed          - at which playback speed (trajectory over the
#                         OUTPUT positions, optionally linked to duration)
#
# Series types (unchanged from v2.x):
#   Su  - Uniform Regular: n equal durations
#   Sc  - Regular Compound: union of two uniform grids Su_a u Su_b
#   Sy  - Irregular Cumulative: n random cumulative split times
#   Sd  - Irregular Individual: n random durations, normalised
#   SRC - Combined: all four merged and deduplicated
#   Param mapping: Su/Sy/Sd n = a; Sc a, b; SRC su = a, sca = b, scb = c,
#   sy = d, sd = e.
#
# Organization (output order of the segments):
#   Original order | Random shuffle (Fisher-Yates, as v2.x) | Reverse |
#   Rotation (by about a third of the segments) | Long-short alternation
#   (longest, shortest, 2nd longest, ...) | Short to long | Long to short |
#   Grouped shuffle (groups of ~sqrt(n) neighbours shuffled inside, group
#   order kept)
#
# Speed:
#   Trajectory over the output position u = 0..1, interpolated on a log
#   scale between Speed_min and Speed_max:
#     Constant (geometric centre of the range) | Acceleration |
#     Deceleration | Arch (climax at the centre) | Alternating (slow/fast) |
#     Wave (two cycles) | Random controlled (bounded random walk)
#   Duration_link g (-1..1): log r += g * log(D / Dref), Dref = geometric
#     mean of the segment durations. 0 = independent, > 0 = longer
#     segments faster, < 0 = longer segments slower. g = 1 makes every
#     processed duration equal (D / r = const); the Info window warns
#     from |g| >= 0.8. Speeds never leave Speed_min..Speed_max.
#   Playback:
#     Natural varispeed (default): a segment of duration D at speed r
#       lasts D / r; the timeline is built from the real durations.
#     Fixed-slot varispeed (v2.x behaviour): each segment keeps a slot of
#       its original duration; a faster segment leaves silence in the slot
#       (shown in the figure), a slower one is cut at the slot end.
#   Target_duration (s, 0 = free): the speed curve is moved as a whole
#     (global scale) to reach the target. If the curve would then leave
#     the speed range, its depth is reduced just enough (shape kept) and
#     this is reported; if even a flat curve cannot reach the target, the
#     free result is kept and the reachable interval is reported.
#
# Articulation:
#   Gap: none | fixed (ms) | proportional (% of the processed event).
#   Edge_fade (ms): raised-cosine fade at both ends of every event, inside
#     the event (no change of duration); 0 = sharp edges.
#   Safe_cuts: each mathematical boundary may move to the quietest point
#     within +/-15 ms (+/-5 ms on a BPM grid), then to the nearest zero
#     crossing. Off by default.
#
# Stereo: Off keeps the source channel count (stereo stays stereo).
#   Panning follows either the source identity of a segment or its output
#   position. A stereo source is balanced (both channels kept), a mono
#   source is panned with equal power.
#
# Random_seed: > 0 makes segmentation, order, speeds and panning
#   repeatable (Praat's generator is seeded and reset afterwards);
#   0 = a new seed each run, printed so the run can be repeated.
#
# Presets set segmentation, organization, speed behaviour and gaps only.
#   They never change BPM, stereo, seed, target duration, fades, safe
#   cuts, playback mode, drawing or playing.
#
# v3.0 changelog (2026):
#   * Speed composition replaces the pitch levels of v2.x: natural
#     varispeed by default (v2.x padded/trimmed every transposed segment
#     back to its slot: a 2x segment became 1 s sound + 1 s silence).
#   * Organization, speed trajectory, duration link, target duration,
#     gaps, edge fades, safe cuts, stereo by source or output position,
#     working Random_seed, new presets (8 + Custom).
#   * No mono collapse of a stereo source; output placed sample-exactly.
#   * Figure: source, segment map (original vs output timeline, inserted
#     silence in grey), speed per event, result, summary.
#   * The v2.x form and its pitch-level parameters are gone.
#
# v2.4 / v2.3 / v2.2 / v2.1: see the v2.4 file (visualization pass;
#   zero-based segments, Sy fix, BPM boundary hardening; compact form;
#   BPM grid, tape transposition, panning).
# ============================================================

form Rhythmatist v3.0
    optionmenu Preset 1
        option Custom
        option Original Pulse
        option Accelerando
        option Ritardando
        option Rhythmic Arch
        option Long-Short Dialogue
        option Fractured Time
        option Controlled Chaos
        option Dense Strata
    optionmenu Series_type 1
        option Su  - Uniform Regular
        option Sc  - Regular Compound (a + b)
        option Sy  - Irregular Cumulative
        option Sd  - Irregular Individual
        option SRC - Combined (Su+Sc+Sy+Sd)
    sentence Params_a_b_c_d_e 8 4 5 4 3
    optionmenu Organization 2
        option Original order
        option Random shuffle
        option Reverse
        option Rotation
        option Long-short alternation
        option Short to long
        option Long to short
        option Grouped shuffle
    optionmenu Speed_trajectory 2
        option Constant
        option Acceleration
        option Deceleration
        option Arch
        option Alternating
        option Wave
        option Random controlled
    positive Speed_min 0.5
    positive Speed_max 2.0
    real Duration_link_(-1..1) 0
    optionmenu Playback 1
        option Natural varispeed
        option Fixed-slot varispeed (v2.x)
    real Target_duration_(s,_0_=_free) 0
    optionmenu Gap 1
        option None
        option Fixed (ms)
        option Proportional (% of event)
    real Gap_value 50
    real Edge_fade_(ms,_0_=_sharp) 2
    boolean Safe_cuts 0
    real Bpm_value_(0_=_off) 0
    optionmenu Grid_division 4
        option Quarter notes
        option Eighth notes
        option Triplet eighths
        option Sixteenth notes
        option Triplet sixteenths
    optionmenu Stereo_placement 1
        option Off (keep source channels)
        option Alternate L-R by source segment
        option Alternate L-R by output position
        option Sweep L to R by source segment
        option Sweep L to R by output position
        option Cycle 4 positions by output position
        option Random positions
    real Stereo_width 0.8
    integer Random_seed_(0_=_new) 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PARAMETERS
# ============================================================

@parseParams: params_a_b_c_d_e$
param_a = parseParams.v[1]
param_b = parseParams.v[2]
param_c = parseParams.v[3]
param_d = parseParams.v[4]
param_e = parseParams.v[5]
durLink = duration_link
targetDur = target_duration
fadeMs = edge_fade
bpm_value = bpm_value
gapMode = gap
gapValue = gap_value

# ============================================================
# PRESETS: segmentation, organization, speed behaviour and gaps only
# ============================================================

presetName$ = "Custom"
if preset = 2
    presetName$ = "Original Pulse"
    series_type = 1
    param_a = 8
    organization = 1
    speed_trajectory = 1
    speed_min = 1
    speed_max = 1
    durLink = 0
    gapMode = 1
elsif preset = 3
    presetName$ = "Accelerando"
    series_type = 1
    param_a = 16
    organization = 1
    speed_trajectory = 2
    speed_min = 0.6
    speed_max = 2.2
    durLink = 0
    gapMode = 1
elsif preset = 4
    presetName$ = "Ritardando"
    series_type = 1
    param_a = 12
    organization = 1
    speed_trajectory = 3
    speed_min = 0.45
    speed_max = 1.6
    durLink = 0
    gapMode = 3
    gapValue = 15
elsif preset = 5
    presetName$ = "Rhythmic Arch"
    series_type = 2
    param_a = 3
    param_b = 5
    organization = 1
    speed_trajectory = 4
    speed_min = 0.6
    speed_max = 2.4
    durLink = 0
    gapMode = 1
elsif preset = 6
    presetName$ = "Long-Short Dialogue"
    series_type = 4
    param_a = 10
    organization = 5
    speed_trajectory = 5
    speed_min = 0.6
    speed_max = 1.8
    durLink = -0.4
    gapMode = 2
    gapValue = 40
elsif preset = 7
    presetName$ = "Fractured Time"
    series_type = 3
    param_a = 14
    organization = 2
    speed_trajectory = 7
    speed_min = 0.4
    speed_max = 2.5
    durLink = -0.6
    gapMode = 1
elsif preset = 8
    presetName$ = "Controlled Chaos"
    series_type = 5
    param_a = 4
    param_b = 3
    param_c = 5
    param_d = 6
    param_e = 5
    organization = 8
    speed_trajectory = 6
    speed_min = 0.5
    speed_max = 2.0
    durLink = 0.3
    gapMode = 3
    gapValue = 10
elsif preset = 9
    presetName$ = "Dense Strata"
    series_type = 5
    param_a = 6
    param_b = 4
    param_c = 7
    param_d = 8
    param_e = 6
    organization = 2
    speed_trajectory = 1
    speed_min = 1.4
    speed_max = 2.4
    durLink = 0.4
    gapMode = 1
endif

trajName$[1] = "Constant"
trajName$[2] = "Acceleration"
trajName$[3] = "Deceleration"
trajName$[4] = "Arch"
trajName$[5] = "Alternating"
trajName$[6] = "Wave"
trajName$[7] = "Random controlled"
orgName$[1] = "Original order"
orgName$[2] = "Random shuffle"
orgName$[3] = "Reverse"
orgName$[4] = "Rotation"
orgName$[5] = "Long-short alternation"
orgName$[6] = "Short to long"
orgName$[7] = "Long to short"
orgName$[8] = "Grouped shuffle"

bpm_quantize = (bpm_value > 0)
apply_stereo = (stereo_placement > 1)

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif
sound      = selected("Sound")
soundName$ = selected$("Sound")
displayName$ = replace$(soundName$, "_", "\_ ", 0)

selectObject: sound
nCh        = Get number of channels
sampleRate = Get sampling frequency
sourceStart = Get start time
t_total    = Get total duration
samplePeriod = 1 / sampleRate

if speed_min > speed_max
    exitScript: "Speed_min must not be larger than Speed_max."
endif
if speed_min < 0.1 or speed_max > 8
    exitScript: "Speeds must lie between 0.1x and 8x."
endif
if durLink < -1 or durLink > 1
    exitScript: "Duration_link must lie between -1 and 1."
endif
if targetDur < 0
    exitScript: "Target_duration must be 0 (free) or positive."
endif
if gapValue < 0
    exitScript: "Gap_value must not be negative."
endif
if fadeMs < 0 or fadeMs > 50
    exitScript: "Edge_fade must lie between 0 and 50 ms."
endif
if stereo_width < 0
    stereo_width = 0
elsif stereo_width > 1
    stereo_width = 1
endif
if random_seed < 0
    exitScript: "Random_seed must be 0 (new) or positive."
endif
if param_a < 1 or param_b < 1 or param_c < 1 or param_d < 1 or param_e < 1
    exitScript: "Params must be five positive integers, e.g. 8 4 5 4 3."
endif

# Random seed: every random decision below follows it.
if random_seed > 0
    seedUsed = random_seed
else
    seedUsed = randomInteger(1, 999999)
endif
random_initializeWithSeedUnsafelyButPredictably (seedUsed)

# ============================================================
# BPM / GRID SETUP
# ============================================================

if grid_division = 1
    units_per_beat = 1
    grid_label$    = "quarter"
elsif grid_division = 2
    units_per_beat = 2
    grid_label$    = "8th"
elsif grid_division = 3
    units_per_beat = 3
    grid_label$    = "triplet 8th"
elsif grid_division = 4
    units_per_beat = 4
    grid_label$    = "16th"
else
    units_per_beat = 6
    grid_label$    = "triplet 16th"
endif
if bpm_quantize
    beat_s          = 60 / bpm_value
    grid_interval_s = beat_s / units_per_beat
else
    beat_s          = 0
    grid_interval_s = 0
endif

createdTrim = 0
if bpm_quantize
    n_grid_units = floor(t_total / grid_interval_s)
    target_grid  = n_grid_units * grid_interval_s
    if target_grid > 0 and target_grid < t_total - 1e-6
        t_total = target_grid
        createdTrim = 1
    endif
else
    n_grid_units = 0
endif

# Private zero-based processing copy (all channels kept).
selectObject: sound
processingSound = Extract part: sourceStart, sourceStart + t_total, "rectangular", 1, "no"
Rename: soundName$ + "_rhythmatist_work"

# ============================================================
# SERIES (v2.4 definitions)
# ============================================================

if series_type = 1
    su_n = param_a
    seriesLabel$ = "Su " + string$(su_n)
elsif series_type = 2
    sc_a = param_a
    sc_b = param_b
    seriesLabel$ = "Sc (" + string$(sc_a) + "+" + string$(sc_b) + ")"
elsif series_type = 3
    sy_n = param_a
    seriesLabel$ = "Sy " + string$(sy_n)
elsif series_type = 4
    sd_n = param_a
    seriesLabel$ = "Sd " + string$(sd_n)
else
    src_su  = param_a
    src_sca = param_b
    src_scb = param_c
    src_sy  = param_d
    src_sd  = param_e
    seriesLabel$ = "SRC (" + string$(src_su) + "," + string$(src_sca) + "," + string$(src_scb) + "," + string$(src_sy) + "," + string$(src_sd) + ")"
endif

if series_type = 1
    expectedPts = su_n - 1
elsif series_type = 2
    expectedPts = sc_a + sc_b - 2
elsif series_type = 3
    expectedPts = sy_n - 1
elsif series_type = 4
    expectedPts = sd_n - 1
else
    expectedPts = (src_su - 1) + (src_sca - 1) + (src_scb - 1) + (src_sy - 1) + (src_sd - 1)
endif
if expectedPts > 2000
    removeObject: processingSound
    exitScript: "Too many requested split points (maximum 2000 before de-duplication)"
endif

nPts = 0
if series_type = 1
    for k from 1 to su_n - 1
        nPts += 1
        tk[nPts] = k / su_n
    endfor
elsif series_type = 2
    for k from 1 to sc_a - 1
        @insertSorted: k / sc_a
    endfor
    for k from 1 to sc_b - 1
        @insertSorted: k / sc_b
    endfor
    @deduplicate
elsif series_type = 3
    if sy_n > 1
        for k from 1 to sy_n - 1
            @insertSorted: randomUniform(0, 1)
        endfor
    endif
elsif series_type = 4
    t_d = 0
    for k from 1 to sd_n
        dd[k] = randomUniform(0, 1)
        t_d += dd[k]
    endfor
    cumT = 0
    for k from 1 to sd_n - 1
        cumT += dd[k] / t_d
        nPts += 1
        tk[nPts] = cumT
    endfor
else
    for k from 1 to src_su - 1
        @insertSorted: k / src_su
    endfor
    for k from 1 to src_sca - 1
        @insertSorted: k / src_sca
    endfor
    for k from 1 to src_scb - 1
        @insertSorted: k / src_scb
    endfor
    if src_sy > 1
        for k from 1 to src_sy - 1
            @insertSorted: randomUniform(0, 1)
        endfor
    endif
    t_d = 0
    for k from 1 to src_sd
        dd[k] = randomUniform(0, 1)
        t_d += dd[k]
    endfor
    cumT = 0
    for k from 1 to src_sd - 1
        cumT += dd[k] / t_d
        @insertSorted: cumT
    endfor
    @deduplicate
    newN = 0
    for i from 1 to nPts
        if tk[i] > 1e-9 and tk[i] < 1.0 - 1e-9
            newN += 1
            tk2[newN] = tk[i]
        endif
    endfor
    nPts = newN
    for i from 1 to nPts
        tk[i] = tk2[i]
    endfor
endif

for i from 1 to nPts
    boundary[i] = tk[i] * t_total
endfor

# Grid snapping (v2.4)
if bpm_quantize
    if n_grid_units < 2
        nPts = 0
    else
        newN = 0
        prev_b = -1
        for i from 1 to nPts
            snapped = round(boundary[i] / grid_interval_s) * grid_interval_s
            if snapped > samplePeriod * 0.5 and snapped < t_total - samplePeriod * 0.5
                if newN = 0 or abs(snapped - prev_b) > samplePeriod * 0.5
                    newN += 1
                    boundary_tmp[newN] = snapped
                    prev_b = snapped
                endif
            endif
        endfor
        nPts = newN
        for i from 1 to nPts
            boundary[i] = boundary_tmp[i]
        endfor
    endif
endif

# Optional safe cuts: quietest point nearby, then nearest zero crossing.
safeMoved = 0
safeMaxShift = 0
if safe_cuts and nPts > 0
    selectObject: processingSound
    for i from 1 to nPts
        bPrev = if i = 1 then 0 else boundary[i - 1] fi
        bNext = if i = nPts then t_total else boundary[i + 1] fi
        win = min(0.015, 0.25 * min(boundary[i] - bPrev, bNext - boundary[i]))
        if bpm_quantize
            win = min(win, 0.005)
        endif
        best = boundary[i]
        if win > 0.002
            bestE = 1e30
            tq = boundary[i] - win
            while tq <= boundary[i] + win
                eq = Get root-mean-square: max(0, tq - 0.001), min(t_total, tq + 0.001)
                if eq <> undefined
                    if eq < bestE
                        bestE = eq
                        best = tq
                    endif
                endif
                tq += 0.0005
            endwhile
        endif
        zc = Get nearest zero crossing: 1, best
        if zc <> undefined
            if abs(zc - best) < 0.002
                best = zc
            endif
        endif
        if best > bPrev + 0.002 and best < bNext - 0.002
            if abs(best - boundary[i]) > samplePeriod
                safeMoved += 1
                safeMaxShift = max(safeMaxShift, abs(best - boundary[i]))
            endif
            boundary[i] = best
        endif
    endfor
endif

# One-sample sanitation for all series (v2.4)
newN = 0
prev_b = 0
for i from 1 to nPts
    b = boundary[i]
    if b - prev_b >= samplePeriod and t_total - b >= samplePeriod
        newN += 1
        boundary_tmp[newN] = b
        prev_b = b
    endif
endfor
nPts = newN
for i from 1 to nPts
    boundary[i] = boundary_tmp[i]
endfor
nSeg = nPts + 1

# Segment table: boundaries on whole samples, so the segments tile the
# source exactly (sample n of segment s = sample segS0[s] + n of the source)
selectObject: processingSound
nSrc = Get number of samples
for s from 1 to nSeg
    segS0[s] = if s = 1 then 0 else round(boundary[s - 1] * sampleRate) fi
    segS1[s] = if s = nSeg then nSrc else round(boundary[s] * sampleRate) fi
    segT0[s] = segS0[s] / sampleRate
    segT1[s] = segS1[s] / sampleRate
    segDur[s] = segT1[s] - segT0[s]
endfor

# ============================================================
# STAGE 2: ORGANIZATION (output position -> source segment)
# ============================================================

for p from 1 to nSeg
    order[p] = p
endfor
rotBy = 0
groupSize = 0
if organization = 2
    @shuffleRange: 1, nSeg
elsif organization = 3
    for p from 1 to nSeg
        order[p] = nSeg + 1 - p
    endfor
elsif organization = 4
    rotBy = max(1, round(nSeg / 3))
    if nSeg < 2
        rotBy = 0
    endif
    for p from 1 to nSeg
        order[p] = ((p - 1 + rotBy) mod nSeg) + 1
    endfor
elsif organization >= 5 and organization <= 7
    # stable sort by duration, ascending
    for p from 1 to nSeg
        srt[p] = p
    endfor
    for p from 2 to nSeg
        v = srt[p]
        q = p - 1
        while q >= 1
            if segDur[srt[q]] > segDur[v]
                srt[q + 1] = srt[q]
                q -= 1
            else
                srt[q + 1] = v
                q = -1
            endif
        endwhile
        if q = 0
            srt[1] = v
        endif
    endfor
    if organization = 6
        for p from 1 to nSeg
            order[p] = srt[p]
        endfor
    elsif organization = 7
        for p from 1 to nSeg
            order[p] = srt[nSeg + 1 - p]
        endfor
    else
        lo = 1
        hi = nSeg
        p = 0
        while lo <= hi
            p += 1
            order[p] = srt[hi]
            hi -= 1
            if lo <= hi
                p += 1
                order[p] = srt[lo]
                lo += 1
            endif
        endwhile
    endif
elsif organization = 8
    groupSize = max(2, round(sqrt(nSeg)))
    g0 = 1
    while g0 <= nSeg
        g1 = min(nSeg, g0 + groupSize - 1)
        @shuffleRange: g0, g1
        g0 = g1 + 1
    endwhile
endif

# ============================================================
# STAGE 3: SPEED (trajectory over output positions + duration link)
# ============================================================

lnMin = ln(speed_min)
lnMax = ln(speed_max)
lnSpan = lnMax - lnMin
lnCentre = (lnMin + lnMax) / 2
lnDref = 0
for s from 1 to nSeg
    lnDref += ln(segDur[s])
endfor
lnDref = lnDref / nSeg

sWalk = randomUniform(0.25, 0.75)
for p from 1 to nSeg
    u = if nSeg > 1 then (p - 1) / (nSeg - 1) else 0.5 fi
    if speed_trajectory = 1
        sv = 0.5
    elsif speed_trajectory = 2
        sv = u
    elsif speed_trajectory = 3
        sv = 1 - u
    elsif speed_trajectory = 4
        sv = sin(pi * u)
    elsif speed_trajectory = 5
        sv = if (p mod 2) = 1 then 0 else 1 fi
    elsif speed_trajectory = 6
        sv = 0.5 - 0.5 * cos(4 * pi * u)
    else
        # bounded random walk: neighbours stay related, whole range used
        if p > 1
            sWalk = sWalk + randomUniform(-0.35, 0.35)
            sWalk = max(0, min(1, sWalk))
        endif
        sv = sWalk
    endif
    traj[p] = sv
    # q = offset from the centre of the range (log units)
    qv[p] = (sv - 0.5) * lnSpan + durLink * (ln(segDur[order[p]]) - lnDref)
endfor

# processed duration factor of a gap
gapFixed = 0
gapProp = 0
if gapMode = 2
    gapFixed = gapValue / 1000
elsif gapMode = 3
    gapProp = gapValue / 100
endif

# Free curve
cUse = lnCentre
wUse = 1
targetNote$ = "free"
targetHit = 0
if targetDur > 0 and playback = 2
    targetNote$ = "ignored in fixed-slot playback (slots keep the source duration)"
elsif targetDur > 0
    # largest depth w in [0, 1] for which the target is reachable inside the range
    @reach: 1
    if targetDur >= reach.tLo and targetDur <= reach.tHi
        wUse = 1
    else
        @reach: 0
        if targetDur >= reach.tLo and targetDur <= reach.tHi
            wLo = 0
            wHi = 1
            for it from 1 to 40
                wm = (wLo + wHi) / 2
                @reach: wm
                if targetDur >= reach.tLo and targetDur <= reach.tHi
                    wLo = wm
                else
                    wHi = wm
                endif
            endfor
            wUse = wLo
        else
            wUse = -1
            tReachLo = reach.tLo
            tReachHi = reach.tHi
        endif
    endif
    if wUse >= 0
        @reach: wUse
        cLo = reach.cLo
        cHi = reach.cHi
        for it from 1 to 60
            cm = (cLo + cHi) / 2
            @totalFor: cm, wUse
            if totalFor.t > targetDur
                cLo = cm
            else
                cHi = cm
            endif
        endfor
        cUse = (cLo + cHi) / 2
        targetHit = 1
        if wUse < 0.999
            targetNote$ = "reached; speed-curve depth reduced to " + fixed$(100 * wUse, 0) + " % to stay inside the range"
        else
            targetNote$ = "reached by a global speed scale of x" + fixed$(exp(cUse - lnCentre), 3)
        endif
    else
        wUse = 1
        cUse = lnCentre
        targetNote$ = "NOT reachable inside " + fixed$(speed_min, 2) + "-" + fixed$(speed_max, 2) + "x (reachable " + fixed$(tReachLo, 2) + "-" + fixed$(tReachHi, 2) + " s); free result kept"
    endif
endif

nClamped = 0
for p from 1 to nSeg
    lr = cUse + wUse * qv[p]
    if lr < lnMin - 1e-9
        lr = lnMin
        nClamped += 1
    elsif lr > lnMax + 1e-9
        lr = lnMax
        nClamped += 1
    endif
    speed[p] = exp(lr)
endfor

# ============================================================
# BUILD EVENTS (varispeed, fades, panning) AND THE TIMELINE
# ============================================================

outCh = if apply_stereo then 2 else nCh fi
fadeSec = fadeMs / 1000
cursor = 0
nPadded = 0
nCut = 0
silenceTotal = 0
for p from 1 to nSeg
    sIdx = order[p]
    part = Create Sound from formula: "seg", nCh, 0, (segS1[sIdx] - segS0[sIdx]) / sampleRate, sampleRate,
    ... "object[" + string$(processingSound) + ", row, col + " + string$(segS0[sIdx]) + "]"
    r = speed[p]
    if abs(r - 1) > 1e-9
        # tape varispeed: reinterpret the rate, then resample (sinc, 50)
        Override sampling frequency: sampleRate * r
        ev = Resample: sampleRate, 50
        removeObject: part
    else
        ev = part
    endif
    selectObject: ev
    nEv = Get number of samples
    # fixed-slot: the slot is the source duration of the segment
    slotN = round(segDur[sIdx] * sampleRate)
    padN = 0
    if playback = 2
        if nEv > slotN
            cutPart = Extract part: 0, slotN / sampleRate, "rectangular", 1, "no"
            removeObject: ev
            ev = cutPart
            selectObject: ev
            nEv = Get number of samples
            nCut += 1
            evNote$[p] = "cut to slot"
        else
            padN = slotN - nEv
            if padN > 0
                nPadded += 1
            endif
            evNote$[p] = if padN > 0 then "slot silence " + fixed$(1000 * padN / sampleRate, 0) + " ms" else "" fi
        endif
    else
        evNote$[p] = ""
    endif
    evDur = nEv / sampleRate
    # edge fades inside the event
    if fadeSec > 0
        fz = min(fadeSec, evDur / 4)
        fzs$ = fixed$(fz, 6)
        eds$ = fixed$(evDur, 6)
        Formula: "self * (if x < " + fzs$ + " then 0.5 - 0.5 * cos(pi * x / " + fzs$ + ") else 1 fi) * (if x > " + eds$ + " - " + fzs$ + " then 0.5 - 0.5 * cos(pi * (" + eds$ + " - x) / " + fzs$ + ") else 1 fi)"
    endif
    # panning
    panVal = 0
    if apply_stereo
        if stereo_placement = 2
            panVal = if (sIdx mod 2) = 1 then -stereo_width else stereo_width fi
        elsif stereo_placement = 3
            panVal = if (p mod 2) = 1 then -stereo_width else stereo_width fi
        elsif stereo_placement = 4
            panVal = if nSeg > 1 then ((sIdx - 1) / (nSeg - 1) * 2 - 1) * stereo_width else 0 fi
        elsif stereo_placement = 5
            panVal = if nSeg > 1 then ((p - 1) / (nSeg - 1) * 2 - 1) * stereo_width else 0 fi
        elsif stereo_placement = 6
            pos4 = (p - 1) mod 4
            panVal = (-1 + pos4 * 2 / 3) * stereo_width
        else
            panVal = randomUniform(-1, 1) * stereo_width
        endif
        theta = (panVal + 1) / 2 * pi / 2
        if nCh = 1
            # equal power
            gL = cos(theta)
            gR = sin(theta)
            st = Convert to stereo
            removeObject: ev
            ev = st
        else
            # balance: both channels kept, unity at the centre
            gL = min(1, sqrt(2) * cos(theta))
            gR = min(1, sqrt(2) * sin(theta))
        endif
        selectObject: ev
        Formula: "self * (if row = 1 then " + fixed$(gL, 6) + " else " + fixed$(gR, 6) + " fi)"
    endif
    evId[p] = ev
    evN[p] = nEv
    evPan[p] = panVal
    evStart[p] = cursor
    cursor += nEv + padN
    evSlotEnd[p] = cursor
    silenceTotal += padN
    # gap after every event except the last
    gapN = 0
    if p < nSeg
        if gapMode = 2
            gapN = round(gapFixed * sampleRate)
        elsif gapMode = 3
            gapN = round(gapProp * nEv)
        endif
    endif
    evGap[p] = gapN
    cursor += gapN
    silenceTotal += gapN
endfor
totalN = cursor
resultDur = totalN / sampleRate

result = Create Sound from formula: soundName$ + "_rhythmatist", outCh, 0, resultDur, sampleRate, "0"
for p from 1 to nSeg
    off$ = string$(evStart[p])
    n$ = string$(evN[p])
    selectObject: result
    Formula (part): evStart[p] / sampleRate, (evStart[p] + evN[p]) / sampleRate, 1, outCh,
    ... "if col - " + off$ + " >= 1 and col - " + off$ + " <= " + n$ + " then object[" + string$(evId[p]) + ", row, col - " + off$ + "] else self fi"
    removeObject: evId[p]
endfor

selectObject: result
peakOut = Get absolute extremum: 0, 0, "None"
safetyScaled = 0
if peakOut > 0.99
    Scale peak: 0.99
    safetyScaled = 1
endif

# ============================================================
# REPORT
# ============================================================

writeInfoLine: "=== RHYTHMATIST v3.0 ==="
appendInfoLine: "Source:       ", soundName$, "  (", fixed$(t_total, 3), " s, ", nCh, " ch, ", sampleRate, " Hz)"
appendInfoLine: "Preset:       ", presetName$
appendInfoLine: "Segmentation: ", seriesLabel$, "  -> ", nSeg, " segments"
appendInfoLine: "Organization: ", orgName$[organization], (if organization = 4 then " by " + string$(rotBy) else "" fi), (if organization = 8 then " (groups of " + string$(groupSize) + ")" else "" fi)
appendInfoLine: "Speed:        ", trajName$[speed_trajectory], "  ", fixed$(speed_min, 2), "-", fixed$(speed_max, 2), "x, duration link ", fixed$(durLink, 2), "  (", if playback = 1 then "natural varispeed" else "fixed-slot varispeed" fi, ")"
if abs(durLink) >= 0.8
    appendInfoLine: "              NOTE: |Duration_link| >= 0.8 makes processed durations nearly equal (1 = equal)."
endif
if nClamped > 0
    appendInfoLine: "              ", nClamped, " event speed(s) limited to the range."
endif
appendInfoLine: "Target:       ", if targetDur > 0 then fixed$(targetDur, 3) + " s - " + targetNote$ else "free duration" fi
if bpm_quantize
    appendInfoLine: "BPM:          ", fixed$(bpm_value, 1), "  grid ", grid_label$, if createdTrim then "  (source trimmed to the grid)" else "" fi
endif
if safe_cuts
    appendInfoLine: "Safe cuts:    ", safeMoved, " boundary(ies) moved, max ", fixed$(1000 * safeMaxShift, 1), " ms"
endif
gapTxt$ = "none"
if gapMode = 2
    gapTxt$ = fixed$(gapValue, 0) + " ms"
elsif gapMode = 3
    gapTxt$ = fixed$(gapValue, 0) + " % of each event"
endif
appendInfoLine: "Gaps:         ", gapTxt$, "   Edge fade: ", if fadeMs > 0 then fixed$(fadeMs, 1) + " ms" else "off (sharp)" fi
appendInfoLine: "Stereo:       ", if apply_stereo then stereo_placement$ + ", width " + fixed$(stereo_width, 2) else "off (" + string$(nCh) + " ch kept)" fi
appendInfoLine: "Random seed:  ", seedUsed, if random_seed = 0 then "  (new; enter it to repeat this run)" else "" fi
appendInfoLine: ""
appendInfoLine: "  pos  seg   D src s   speed    D out s   start s    pan    gap ms   note"
for p from 1 to nSeg
    @padL: string$(p), 5
    c1$ = padL$
    @padL: string$(order[p]), 5
    c2$ = padL$
    @padL: fixed$(segDur[order[p]], 3), 10
    c3$ = padL$
    @padL: fixed$(speed[p], 3), 9
    c4$ = padL$
    @padL: fixed$(evN[p] / sampleRate, 3), 10
    c5$ = padL$
    @padL: fixed$(evStart[p] / sampleRate, 3), 10
    c6$ = padL$
    @padL: fixed$(evPan[p], 2), 7
    c7$ = padL$
    @padL: fixed$(1000 * evGap[p] / sampleRate, 0), 9
    c8$ = padL$
    appendInfoLine: c1$, c2$, c3$, c4$, c5$, c6$, c7$, c8$, "   ", evNote$[p]
endfor
appendInfoLine: ""
appendInfoLine: "Result:       ", fixed$(resultDur, 3), " s (source ", fixed$(t_total, 3), " s); inserted silence ", fixed$(silenceTotal / sampleRate, 3), " s"
if playback = 2
    appendInfoLine: "              fixed-slot: ", nPadded, " slot(s) with silence, ", nCut, " event(s) cut at the slot end"
endif
appendInfoLine: "Peak:         ", fixed$(peakOut, 3), if safetyScaled then "  (scaled to 0.99)" else "" fi

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    blueA$ = "{0.55, 0.75, 0.90}"
    blueB$ = "{0.25, 0.55, 0.75}"
    orangeA$ = "{0.85, 0.60, 0.25}"
    orangeB$ = "{0.78, 0.45, 0.16}"
    tMax = max(t_total, resultDur)
    Erase all
    Line width: 1
    Solid line

    Font size: 13
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.45, "half", "##Rhythmatist v3.0##"
    Font size: 8
    Select outer viewport: 0, 8, 0.4, 0.8
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.5, "centre", 0.5, "half", displayName$ + "  |  " + presetName$ + "  |  " + seriesLabel$ + "  |  " + orgName$[organization] + "  |  " + trajName$[speed_trajectory]

    Font size: 7
    # A: source with boundaries (and BPM grid)
    Select outer viewport: 0, 8, 0.75, 2.25
    Select inner viewport: 0.6, 7.7, 0.95, 2.05
    selectObject: processingSound
    Axes: 0, tMax, -1, 1
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Axes: 0, tMax, -1, 1
    if bpm_quantize
        Colour: "{0.85, 0.85, 0.65}"
        Dotted line
        gt = grid_interval_s
        while gt < t_total - 1e-6
            Draw line: gt, -1, gt, 1
            gt += grid_interval_s
        endwhile
        Solid line
    endif
    Colour: "{1.00, 0.30, 0.30}"
    Line width: if nPts > 40 then 1 else 1.5 fi
    for i from 1 to nPts
        Draw line: boundary[i], -1, boundary[i], 1
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Text left: "no", "Source"
    Text top: "no", "##Source## and segment boundaries (" + string$(nSeg) + " segments, " + fixed$(t_total, 2) + " s)"

    Font size: 7
    # B: segment map - original timeline (blue) vs output timeline (orange)
    Select outer viewport: 0, 8, 2.25, 3.65
    Select inner viewport: 0.6, 7.7, 2.45, 3.45
    Axes: 0, tMax, 0, 2
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, tMax, 0, 2
    for s from 1 to nSeg
        Paint rectangle: if (s mod 2) = 1 then blueA$ else blueB$ fi, segT0[s], segT1[s], 1.08, 1.92
        if segDur[s] >= 0.03 * tMax
            Colour: "White"
            Text: (segT0[s] + segT1[s]) / 2, "centre", 1.5, "half", string$(s)
        endif
    endfor
    for p from 1 to nSeg
        sIdx = order[p]
        a0 = evStart[p] / sampleRate
        a1 = (evStart[p] + evN[p]) / sampleRate
        Paint rectangle: if (sIdx mod 2) = 1 then orangeA$ else orangeB$ fi, a0, a1, 0.08, 0.92
        if evSlotEnd[p] > evStart[p] + evN[p]
            Paint rectangle: "{0.80, 0.80, 0.80}", a1, evSlotEnd[p] / sampleRate, 0.30, 0.70
        endif
        if evGap[p] > 0
            Paint rectangle: "{0.88, 0.88, 0.88}", evSlotEnd[p] / sampleRate, (evSlotEnd[p] + evGap[p]) / sampleRate, 0.40, 0.60
        endif
        if a1 - a0 >= 0.03 * tMax
            Colour: "White"
            Text: (a0 + a1) / 2, "centre", 0.5, "half", string$(sIdx)
        endif
    endfor
    Colour: "{0.70, 0.70, 0.70}"
    Draw line: 0, 1, tMax, 1
    Colour: "Black"
    Draw inner box
    Colour: blueB$
    One mark left: 1.5, "no", "no", "no", "source"
    Colour: orangeB$
    One mark left: 0.5, "no", "no", "no", "output"
    Colour: "Black"
    Text top: "no", "##Segment map##: source timeline (blue) and output timeline (orange, numbers = source segment; grey = inserted silence)"

    Font size: 7
    # C: speed per event on the output timeline (log scale)
    Select outer viewport: 0, 8, 3.65, 5.0
    Select inner viewport: 0.6, 7.7, 3.85, 4.8
    yLo = ln(speed_min) - 0.1 * max(lnSpan, 0.4)
    yHi = ln(speed_max) + 0.1 * max(lnSpan, 0.4)
    yLo = min(yLo, ln(0.95))
    yHi = max(yHi, ln(1.05))
    Axes: 0, tMax, yLo, yHi
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, tMax, yLo, yHi
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, ln(speed_min), tMax, ln(speed_min)
    Draw line: 0, ln(speed_max), tMax, ln(speed_max)
    Solid line
    Colour: "{0.55, 0.55, 0.55}"
    Draw line: 0, 0, tMax, 0
    Colour: orangeB$
    Line width: 2
    for p from 1 to nSeg
        a0 = evStart[p] / sampleRate
        a1 = (evStart[p] + evN[p]) / sampleRate
        Draw line: a0, ln(speed[p]), a1, ln(speed[p])
        if p < nSeg
            Line width: 1
            Draw line: a1, ln(speed[p]), evStart[p + 1] / sampleRate, ln(speed[p + 1])
            Line width: 2
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    One mark left: ln(speed_min), "no", "yes", "no", fixed$(speed_min, 2) + "x"
    One mark left: ln(speed_max), "no", "yes", "no", fixed$(speed_max, 2) + "x"
    if speed_min < 0.97 and speed_max > 1.03
        One mark left: 0, "no", "yes", "no", "1x"
    endif
    Text top: "no", "##Playback speed## per event (log scale; output timeline)"

    Font size: 7
    # D: result
    Select outer viewport: 0, 8, 5.0, 6.45
    Select inner viewport: 0.6, 7.7, 5.2, 6.1
    selectObject: result
    Axes: 0, tMax, -1, 1
    if outCh > 1
        vL = Extract one channel: 1
        selectObject: result
        vR = Extract one channel: 2
        selectObject: vL
        Colour: "{0.20, 0.50, 0.70}"
        Draw: 0, 0, -1, 1, "no", "Curve"
        selectObject: vR
        Colour: "{0.75, 0.25, 0.15}"
        Draw: 0, 0, -1, 1, "no", "Curve"
        removeObject: vL, vR
    else
        Colour: "{0.20, 0.50, 0.70}"
        Draw: 0, 0, -1, 1, "no", "Curve"
    endif
    Axes: 0, tMax, -1, 1
    Colour: "Black"
    Draw inner box
    tStep = 10 ^ floor(log10(tMax / 2))
    if tMax / tStep > 10
        tStep = tStep * 5
    elsif tMax / tStep > 5
        tStep = tStep * 2
    endif
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "##Result## (" + fixed$(resultDur, 2) + " s" + if outCh > 1 then ", L blue / R red" else "" fi + ")"

    Font size: 7
    # Summary
    Select outer viewport: 0, 8, 6.75, 7.75
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Draw inner box
    Colour: "{0.20, 0.20, 0.20}"
    Text: 0.02, "left", 0.80, "half", "##" + presetName$ + "##   " + seriesLabel$ + "  |  " + orgName$[organization] + "  |  " + trajName$[speed_trajectory] + " " + fixed$(speed_min, 2) + "-" + fixed$(speed_max, 2) + "x  |  link " + fixed$(durLink, 2) + "  |  " + if playback = 1 then "natural varispeed" else "fixed-slot" fi
    Text: 0.02, "left", 0.50, "half", "Source " + fixed$(t_total, 2) + " s  ->  result " + fixed$(resultDur, 2) + " s  |  silence " + fixed$(silenceTotal / sampleRate, 2) + " s  |  gaps " + gapTxt$ + "  |  fade " + fixed$(fadeMs, 1) + " ms" + if safe_cuts then "  |  safe cuts " + string$(safeMoved) else "" fi
    Text: 0.02, "left", 0.20, "half", "Target: " + if targetDur > 0 then fixed$(targetDur, 2) + " s, " + targetNote$ else "free" fi + "  |  stereo " + if apply_stereo then "on" else "off" fi + "  |  seed " + string$(seedUsed) + "  |  peak " + fixed$(peakOut, 2)
    Colour: "Black"
    # whole figure selected, so Save/Copy takes all panels
    Select outer viewport: 0, 8, 0, 7.85
endif

removeObject: processingSound
random_initializeSafelyAndUnpredictably ()

if play_result
    selectObject: result
    Play
endif
selectObject: result

# ============================================================
# PROCEDURES
# ============================================================

procedure parseParams: .s$
    .s$ = replace$(replace$(.s$, ",", " ", 0), tab$, " ", 0) + " "
    .n = 0
    for .k from 1 to 5
        .v[.k] = 0
    endfor
    while index(.s$, " ") > 0 and .n < 5
        .w$ = left$(.s$, index(.s$, " ") - 1)
        .s$ = mid$(.s$, index(.s$, " ") + 1, 10000)
        if .w$ <> ""
            .n += 1
            .x = number(.w$)
            .v[.n] = if .x = undefined then 0 else round(.x) fi
        endif
    endwhile
    for .k from .n + 1 to 5
        .v[.k] = 1
    endfor
endproc

procedure insertSorted: .v
    .pos = nPts + 1
    .i = 1
    while .i <= nPts
        if tk[.i] >= .v
            .pos = .i
            .i = nPts + 1
        else
            .i += 1
        endif
    endwhile
    .j = nPts
    while .j >= .pos
        tk[.j + 1] = tk[.j]
        .j -= 1
    endwhile
    tk[.pos] = .v
    nPts += 1
endproc

procedure deduplicate
    .prev = -1
    .newN = 0
    for .i from 1 to nPts
        if abs(tk[.i] - .prev) > 1e-9
            .newN += 1
            tk2[.newN] = tk[.i]
            .prev = tk[.i]
        endif
    endfor
    nPts = .newN
    for .i from 1 to nPts
        tk[.i] = tk2[.i]
    endfor
endproc

# Fisher-Yates on order[.a .. .b]
procedure shuffleRange: .a, .b
    .i = .b
    while .i > .a
        .j = randomInteger(.a, .i)
        .t = order[.i]
        order[.i] = order[.j]
        order[.j] = .t
        .i -= 1
    endwhile
endproc

# Total output duration for log-centre .c and depth .w (natural playback)
procedure totalFor: .c, .w
    .t = 0
    for .p from 1 to nSeg
        .d = segDur[order[.p]] / exp(.c + .w * qv[.p])
        .t += .d
        if .p < nSeg
            .t += gapFixed + gapProp * .d
        endif
    endfor
    totalFor.t = .t
endproc

# Reachable durations for depth .w with every speed inside the range
procedure reach: .w
    .qMin = 1e9
    .qMax = -1e9
    for .p from 1 to nSeg
        .qMin = min(.qMin, .w * qv[.p])
        .qMax = max(.qMax, .w * qv[.p])
    endfor
    reach.cLo = lnMin - .qMin
    reach.cHi = lnMax - .qMax
    if reach.cLo > reach.cHi + 1e-12
        reach.tLo = 1e9
        reach.tHi = -1e9
    else
        @totalFor: reach.cHi, .w
        reach.tLo = totalFor.t
        @totalFor: reach.cLo, .w
        reach.tHi = totalFor.t
    endif
endproc

procedure padL: .s$, .w
    padL$ = .s$
    while length(padL$) < .w
        padL$ = " " + padL$
    endwhile
endproc
