# ============================================================
# Gesture_Convolution_Transform.praat
# ------------------------------------------------------------
# Part of the Praat AudioTools plugin
#
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email:       shai.cohen@biu.ac.il
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# License:     MIT License
# Category:    Pitch  /  Time & Granular
# Version:     1.4 (2026)
# ------------------------------------------------------------
# A gesture-based pitch / time / intensity transformation.
#
# Builds a 2-D prosodic feature map (time frames x control
# parameters), applies an anisotropic 2-D convolution that
# SMEARS and COUPLES prosodic dimensions (accent expansion,
# pitch-glissando shaping, intensity->time coupling, local
# time dilation around accents), then rebuilds the PitchTier
# and DurationTier inside a Manipulation object, resynthesises,
# and shapes the output intensity with a continuous IntensityTier.
#
# This is a Praat-native phase-vocoder-free transformation: Praat has no full phase vocoder, so the effect
# is realised through Manipulation resynthesis + PitchTier /
# DurationTier replacement + post-resynthesis intensity shaping.
#
# All transformed controls are smoothed into continuous breakpoint
# functions before they touch audio (avoids overlap-add clicks).
#
# USAGE: select exactly ONE Sound object, then Run.
#        Output is left in the Objects window; nothing is saved.
#
# Changelog:
#   1.4 - Fixed orphaned *_int object + un-applied gain: Sound+IntensityTier
#         Multiply creates a NEW Sound, now captured as the output.
#   1.3 - Renamed to Gesture Convolution Transform; experimental
#         presets; viz legibility fixes (axis + summary fonts).
#   1.2 - Added preset menu, header, feature-map visualization.
#   1.1 - Click fixes: IntensityTier gain (was an impulse train),
#         smoothed pitch/duration tiers, voiced-aware derivatives,
#         safer defaults.
#   1.0 - Initial prosodic-convolution prototype.
# ============================================================

form Gesture Convolution Transform
    comment === Preset ===
    optionmenu Preset: 2
        option Subtle
        option Smear
        option Accent-Expand
        option Glissando
        option Warp
        option Rupture
        option Custom
    comment === Global (used when Preset = Custom) ===
    real Effect_amount 0.3
    comment (0 = dry, 1 = full wet)
    real Output_gain 1.0
    comment === Dimension influences ===
    real Pitch_influence 1.0
    real Time_smear_amount 0.25
    real Intensity_influence 0.3
    real Accent_sensitivity 1.0
    comment === Safety / range ===
    positive Max_pitch_shift_semitones 3.0
    real Max_pitch_jump_semitones 2.0
    real Min_duration_factor 0.75
    real Max_duration_factor 1.35
    comment === Smoothing (ms) ===
    positive Pitch_smooth_ms 20
    positive Duration_smooth_ms 60
    positive Gain_smooth_ms 20
    comment === Analysis grid ===
    positive Time_step 0.01
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET VOICINGS
# ------------------------------------------------------------
# Each preset overrides the effect cluster (Custom leaves the
# form values untouched).
# ============================================================
if preset = 1
    # Subtle - gentle polish, barely-there shaping (safe anchor)
    presetName$ = "Subtle"
    effect_amount = 0.25
    pitch_influence = 0.6
    time_smear_amount = 0.2
    intensity_influence = 0.25
    accent_sensitivity = 0.7
    max_pitch_shift_semitones = 2.0
    max_pitch_jump_semitones = 1.5
    min_duration_factor = 0.85
    max_duration_factor = 1.2
elsif preset = 2
    # Smear - heavy prosodic blur / forward temporal overshoot
    presetName$ = "Smear"
    effect_amount = 0.7
    pitch_influence = 1.0
    time_smear_amount = 0.85
    intensity_influence = 0.55
    accent_sensitivity = 1.0
    max_pitch_shift_semitones = 4.0
    max_pitch_jump_semitones = 2.5
    min_duration_factor = 0.55
    max_duration_factor = 1.8
elsif preset = 3
    # Accent-Expand - violently dwell on and inflate accents
    presetName$ = "Accent-Expand"
    effect_amount = 0.75
    pitch_influence = 0.9
    time_smear_amount = 0.55
    intensity_influence = 0.9
    accent_sensitivity = 2.6
    max_pitch_shift_semitones = 5.0
    max_pitch_jump_semitones = 3.0
    min_duration_factor = 0.5
    max_duration_factor = 2.5
elsif preset = 4
    # Glissando - exaggerated sliding contours, curvature feedback
    presetName$ = "Glissando"
    effect_amount = 0.8
    pitch_influence = 2.2
    time_smear_amount = 0.5
    intensity_influence = 0.35
    accent_sensitivity = 1.1
    max_pitch_shift_semitones = 9.0
    max_pitch_jump_semitones = 5.0
    min_duration_factor = 0.7
    max_duration_factor = 1.6
elsif preset = 5
    # Warp - intensity drives time hard; rhythmic dislocation
    presetName$ = "Warp"
    effect_amount = 0.85
    pitch_influence = 0.7
    time_smear_amount = 1.0
    intensity_influence = 1.0
    accent_sensitivity = 2.0
    max_pitch_shift_semitones = 4.0
    max_pitch_jump_semitones = 3.0
    min_duration_factor = 0.4
    max_duration_factor = 3.0
elsif preset = 6
    # Rupture - maximum everything; far-out, audibly broken-beautiful
    presetName$ = "Rupture"
    effect_amount = 1.0
    pitch_influence = 2.5
    time_smear_amount = 1.0
    intensity_influence = 1.0
    accent_sensitivity = 3.0
    max_pitch_shift_semitones = 12.0
    max_pitch_jump_semitones = 7.0
    min_duration_factor = 0.35
    max_duration_factor = 3.5
else
    presetName$ = "Custom"
endif

# ============================================================
# SECTION 1 — INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object first."
endif

origID    = selected("Sound")
origName$ = selected$("Sound")

selectObject: origID
nChan = Get number of channels

# Manipulation / pitch analysis require mono. Keep the original for the
# final intensity reference; build a mono working copy for everything else.
if nChan > 1
    workID = Convert to mono
    Rename: "gct_work_mono"
else
    workID = Copy: "gct_work_mono"
endif

selectObject: workID
totalDur = Get total duration
workSR   = Get sampling frequency

clearinfo
appendInfoLine: "=== Gesture Convolution Transform v1.4 ==="
appendInfoLine: "Input: ", origName$, "  (", fixed$(totalDur, 3), " s)"
appendInfoLine: ""

# ============================================================
# SECTION 2 — ANALYSIS
# ============================================================
appendInfoLine: "[1/7] Analysing prosody..."

# Manipulation object (drives pitch + duration resynthesis)
selectObject: workID
manipID = To Manipulation: time_step, pitch_floor, pitch_ceiling

# Pitch (for the feature map) — read from a PitchTier sampled on the grid
selectObject: workID
pitchObj = To Pitch: time_step, pitch_floor, pitch_ceiling

# Intensity (dB), sampled on the same grid
selectObject: workID
intObj = To Intensity: pitch_floor, time_step, "yes"

# Number of frames on the common grid
nFrames = floor(totalDur / time_step)
if nFrames < 8
    selectObject: pitchObj, intObj, manipID, workID
    Remove
    exitScript: "Sound too short for this effect (need at least ~8 analysis frames)."
endif

# Feature columns (fixed layout):
#   1 = semitone pitch       2 = pitch slope       3 = pitch curvature
#   4 = local duration factor 5 = intensity dB     6 = intensity slope
#   7 = accent strength      8 = voicing mask
nCols = 8

# Raw feature matrix (time x parameter)
featRaw = Create simple Matrix: "featRaw", nFrames, nCols, "0"

# Reference semitone base for pitch (median of voiced frames)
selectObject: pitchObj
medianF0 = Get quantile: 0, 0, 0.5, "Hertz"
if medianF0 = undefined or medianF0 < pitch_floor
    medianF0 = pitch_floor
endif
stRef = medianF0

appendInfoLine: "  Frames: ", nFrames, "   Median F0: ", fixed$(medianF0, 1), " Hz"

# ============================================================
# SECTION 3 — FEATURE-MAP CONSTRUCTION
# ============================================================
appendInfoLine: "[2/7] Building feature map..."

# Pass A: fill pitch (semitones), intensity (dB), voicing mask
for i to nFrames
    t = (i - 0.5) * time_step

    selectObject: pitchObj
    f0 = Get value at time: t, "Hertz", "linear"

    voiced = 0
    st = -999
    if f0 <> undefined and f0 > 0
        voiced = 1
        st = 12 * ln(f0 / stRef) / ln(2)
    endif

    selectObject: intObj
    db = Get value at time: t, "Cubic"
    if db = undefined
        db = 0
    endif

    selectObject: featRaw
    Set value: i, 1, st
    Set value: i, 5, db
    Set value: i, 8, voiced
endfor

# Pass A2: fill unvoiced pitch by interpolating between the nearest voiced
# frames (so the feature map is CONTINUOUS - storing 0 st in unvoiced frames
# would create phantom melodic dips at every consonant). The voicing mask in
# column 8 still records the truth, so resynthesis can preserve unvoiced.
# First find the first/last voiced frame for edge extrapolation.
firstVoiced = 0
lastVoiced = 0
for i to nFrames
    selectObject: featRaw
    vm = Get value in cell: i, 8
    if vm >= 0.5
        if firstVoiced = 0
            firstVoiced = i
        endif
        lastVoiced = i
    endif
endfor

if firstVoiced = 0
    # no voiced frames at all - flat reference everywhere
    for i to nFrames
        selectObject: featRaw
        Set value: i, 1, 0
    endfor
else
    # leading/trailing unvoiced -> hold nearest voiced value
    selectObject: featRaw
    firstVal = Get value in cell: firstVoiced, 1
    lastVal  = Get value in cell: lastVoiced, 1
    for i to nFrames
        selectObject: featRaw
        vm = Get value in cell: i, 8
        if vm < 0.5
            if i < firstVoiced
                Set value: i, 1, firstVal
            elsif i > lastVoiced
                Set value: i, 1, lastVal
            else
                # interior gap: linear interp between bounding voiced frames
                gl = i
                while gl >= 1 and vm < 0.5
                    gl -= 1
                    if gl >= 1
                        vmg = Get value in cell: gl, 8
                        if vmg >= 0.5
                            vm = 1
                        endif
                    endif
                endwhile
                vm2 = 0
                gr = i
                while gr <= nFrames and vm2 < 0.5
                    gr += 1
                    if gr <= nFrames
                        vmg = Get value in cell: gr, 8
                        if vmg >= 0.5
                            vm2 = 1
                        endif
                    endif
                endwhile
                if gl >= 1 and gr <= nFrames
                    vL = Get value in cell: gl, 1
                    vR = Get value in cell: gr, 1
                    frac = (i - gl) / (gr - gl)
                    Set value: i, 1, vL + frac * (vR - vL)
                endif
            endif
        endif
    endfor
endif

# Pass B: derivatives (slope, curvature). Pitch slope/curvature are MASKED to
# 0 when the current frame or either neighbour is unvoiced - otherwise the
# voiced/unvoiced boundary would inject a false melodic gesture (and a false
# accent) at every consonant.
for i to nFrames
    selectObject: featRaw
    p0 = Get value in cell: i, 1
    iPrev = i - 1
    iNext = i + 1
    if iPrev < 1
        iPrev = 1
    endif
    if iNext > nFrames
        iNext = nFrames
    endif
    pPrev = Get value in cell: iPrev, 1
    pNext = Get value in cell: iNext, 1
    dPrev = Get value in cell: iPrev, 5
    dNext = Get value in cell: iNext, 5

    vHere = Get value in cell: i, 8
    vP = Get value in cell: iPrev, 8
    vN = Get value in cell: iNext, 8

    intSlope   = (dNext - dPrev) / 2
    if vHere >= 0.5 and vP >= 0.5 and vN >= 0.5
        pitchSlope = (pNext - pPrev) / 2
        pitchCurv  = pNext - 2 * p0 + pPrev
    else
        pitchSlope = 0
        pitchCurv  = 0
    endif

    Set value: i, 2, pitchSlope
    Set value: i, 3, pitchCurv
    Set value: i, 6, intSlope
endfor

# Pass C: accent strength = normalised product of |intensity above local
# baseline| and pitch movement, smoothed. Local duration factor starts at 1.
selectObject: intObj
meanDB = Get mean: 0, 0, "dB"
if meanDB = undefined
    meanDB = 0
endif

for i to nFrames
    selectObject: featRaw
    db   = Get value in cell: i, 5
    psl  = Get value in cell: i, 2
    accent = (db - meanDB) * (1 + abs(psl))
    if accent < 0
        accent = 0
    endif
    Set value: i, 7, accent
    Set value: i, 4, 1.0
endfor

# ============================================================
# SECTION 4 — NORMALISE each dimension (store mean+sd to invert later)
# ============================================================
appendInfoLine: "[3/7] Normalising dimensions..."

for c to nCols
    sum = 0
    for i to nFrames
        selectObject: featRaw
        v = Get value in cell: i, c
        sum += v
    endfor
    mean'c' = sum / nFrames

    sumsq = 0
    for i to nFrames
        selectObject: featRaw
        v = Get value in cell: i, c
        sumsq += (v - mean'c')^2
    endfor
    sd'c' = sqrt(sumsq / nFrames)
    if sd'c' < 1e-9
        sd'c' = 1
    endif
endfor

# Normalised matrix (z-scores)
featNorm = Create simple Matrix: "featNorm", nFrames, nCols, "0"
for i to nFrames
    for c to nCols
        selectObject: featRaw
        v = Get value in cell: i, c
        z = (v - mean'c') / sd'c'
        selectObject: featNorm
        Set value: i, c, z
    endfor
endfor

# ============================================================
# SECTION 5 — 2-D ANISOTROPIC CONVOLUTION  (the gesture core)
# ------------------------------------------------------------
# Result is written into a SEPARATE matrix (featConv) so we never read a
# cell we have already overwritten. The kernel is asymmetric in time
# (trailing smear) and COUPLES dimensions:
#   - time smear     : low-pass along time on pitch dims, weighted by
#                      time_smear_amount, with a causal/trailing bias.
#   - accent expand  : accent (col 7) widens its own temporal footprint.
#   - intensity->time: intensity slope (col 6) pushes local duration (col 4).
#   - glissando shape : pitch curvature (col 3) feeds back into pitch (col 1).
# ============================================================
appendInfoLine: "[4/7] Convolving feature map (time x parameter)..."

# temporal half-window grows with time-smear
halfWin = 2 + floor(time_smear_amount * 6)

featConv = Create simple Matrix: "featConv", nFrames, nCols, "0"

for i to nFrames
    # --- accumulate a trailing-biased temporal average of the pitch row ---
    accPitch = 0
    accCurv  = 0
    accAccent = 0
    wsum = 0
    for k from -halfWin to halfWin
        j = i + k
        if j >= 1 and j <= nFrames
            # asymmetric weight: trailing samples (k>0) weighted more ->
            # smears prosody FORWARD in time (gesture "overshoot")
            if k >= 0
                w = exp(-k / (halfWin + 1))
            else
                w = 0.4 * exp(k / (halfWin + 1))
            endif
            selectObject: featNorm
            gv1 = Get value in cell: j, 1
            gv3 = Get value in cell: j, 3
            gv7 = Get value in cell: j, 7
            accPitch  += w * gv1
            accCurv   += w * gv3
            accAccent += w * gv7
            wsum += w
        endif
    endfor
    if wsum < 1e-9
        wsum = 1
    endif
    smPitch  = accPitch  / wsum
    smCurv   = accCurv   / wsum
    smAccent = accAccent / wsum

    selectObject: featNorm
    p1 = Get value in cell: i, 1
    p2 = Get value in cell: i, 2
    p3 = Get value in cell: i, 3
    p4 = Get value in cell: i, 4
    p5 = Get value in cell: i, 5
    p6 = Get value in cell: i, 6
    p7 = Get value in cell: i, 7
    p8 = Get value in cell: i, 8

    # local accent gain (accent_sensitivity scales how strongly accents act)
    aGain = 1 + accent_sensitivity * smAccent

    # --- couplings ---
    # pitch: smeared pitch + curvature feedback (glissando shaping)
    cP1 = smPitch + 0.5 * pitch_influence * smCurv * aGain
    # pitch slope: exaggerated by accent
    cP2 = p2 * aGain
    # pitch curvature: smeared
    cP3 = smCurv
    # local duration: pushed by intensity slope (intensity->time coupling)
    #                 and dilated around accents (local time dilation)
    cP4 = p4 + time_smear_amount * (0.6 * p6 + 0.8 * smAccent * accent_sensitivity)
    # intensity: lifted by accent (accent expansion in loudness)
    cP5 = p5 + 0.4 * intensity_influence * smAccent
    # intensity slope: smoothed toward 0 (less spiky) — smear
    cP6 = p6 * (1 - 0.5 * time_smear_amount)
    # accent: temporally expanded
    cP7 = smAccent
    # voicing mask: preserved exactly (no convolution — protects unvoiced)
    cP8 = p8

    selectObject: featConv
    Set value: i, 1, cP1
    Set value: i, 2, cP2
    Set value: i, 3, cP3
    Set value: i, 4, cP4
    Set value: i, 5, cP5
    Set value: i, 6, cP6
    Set value: i, 7, cP7
    Set value: i, 8, cP8
endfor

# ============================================================
# SECTION 6 — WET/DRY MIX + DENORMALISE + CONSTRAINTS
# ============================================================
appendInfoLine: "[5/7] Mixing, denormalising, applying constraints..."

# Final (denormalised) feature matrix
featOut = Create simple Matrix: "featOut", nFrames, nCols, "0"
for i to nFrames
    for c to nCols
        selectObject: featNorm
        zdry = Get value in cell: i, c
        selectObject: featConv
        zwet = Get value in cell: i, c
        # voicing mask is never wet-mixed (constraint: preserve voicing)
        if c = 8
            zmix = zdry
        else
            zmix = (1 - effect_amount) * zdry + effect_amount * zwet
        endif
        # denormalise
        v = zmix * sd'c' + mean'c'
        selectObject: featOut
        Set value: i, c, v
    endfor
endfor

# ---- smooth the control curves before they touch audio ----
# All transformed controls must be smooth breakpoint functions or overlap-add
# resynthesis clicks. Pitch is smoothed lightly; duration much more heavily
# (it is a slower control). Box-average over a window derived from the ms
# settings. Smoothing reads from featOut and writes to a SEPARATE column copy
# to avoid reading cells already overwritten.
pitchWin = floor((pitch_smooth_ms / 1000) / time_step / 2)
durWin   = floor((duration_smooth_ms / 1000) / time_step / 2)
if pitchWin < 1
    pitchWin = 1
endif
if durWin < 1
    durWin = 1
endif

# smooth column 1 (pitch, semitones) - only average over VOICED neighbours
smoothCol1 = Create simple Matrix: "smoothCol1", nFrames, 1, "0"
smoothCol4 = Create simple Matrix: "smoothCol4", nFrames, 1, "0"
for i to nFrames
    # pitch (voiced-aware box average)
    psum = 0
    pn = 0
    for k from -pitchWin to pitchWin
        j = i + k
        if j >= 1 and j <= nFrames
            selectObject: featOut
            vmj = Get value in cell: j, 8
            if vmj >= 0.5
                pv = Get value in cell: j, 1
                psum += pv
                pn += 1
            endif
        endif
    endfor
    if pn = 0
        selectObject: featOut
        pAvg = Get value in cell: i, 1
    else
        pAvg = psum / pn
    endif
    selectObject: smoothCol1
    Set value: i, 1, pAvg

    # duration (heavy box average)
    dsum = 0
    dn = 0
    for k from -durWin to durWin
        j = i + k
        if j >= 1 and j <= nFrames
            selectObject: featOut
            dv = Get value in cell: j, 4
            dsum += dv
            dn += 1
        endif
    endfor
    selectObject: smoothCol4
    Set value: i, 1, dsum / dn
endfor

# write smoothed values back into featOut
for i to nFrames
    selectObject: smoothCol1
    pv = Get value in cell: i, 1
    selectObject: smoothCol4
    dv = Get value in cell: i, 1
    selectObject: featOut
    Set value: i, 1, pv
    Set value: i, 4, dv
endfor

# ---- build PitchTier + DurationTier from featOut, with safety ----
# Replace tiers inside a copy of the Manipulation object.
selectObject: manipID
pitchTier = Extract pitch tier
durTier   = Create DurationTier: "gct_dur", 0, totalDur

# Remove existing pitch points, we will write our own
selectObject: pitchTier
Remove points between: 0, totalDur

maxShiftST = max_pitch_shift_semitones
jumpRatio  = 2 ^ (max_pitch_jump_semitones / 12)
prevF0 = medianF0

for i to nFrames
    t = (i - 0.5) * time_step

    selectObject: featOut
    stVal   = Get value in cell: i, 1
    durFac  = Get value in cell: i, 4
    voiced  = Get value in cell: i, 8

    # ---- pitch safety ----
    # clamp semitone shift relative to reference
    if stVal > maxShiftST
        stVal = maxShiftST
    elsif stVal < -maxShiftST
        stVal = -maxShiftST
    endif
    newF0 = stRef * 2^(stVal / 12)

    # preserve unvoiced regions: only write pitch points where voiced
    if voiced >= 0.5 and newF0 > 0
        # limit frame-to-frame jump to max_pitch_jump_semitones
        ratio = newF0 / prevF0
        if ratio > jumpRatio
            newF0 = prevF0 * jumpRatio
        elsif ratio < 1 / jumpRatio
            newF0 = prevF0 / jumpRatio
        endif
        if newF0 >= pitch_floor and newF0 <= pitch_ceiling
            selectObject: pitchTier
            Add point: t, newF0
            prevF0 = newF0
        endif
    endif

    # ---- duration safety ----  clamp local factor
    if durFac < min_duration_factor
        durFac = min_duration_factor
    elsif durFac > max_duration_factor
        durFac = max_duration_factor
    endif
    selectObject: durTier
    Add point: t, durFac
endfor

# ============================================================
# SECTION 7 — TIER RECONSTRUCTION + RESYNTHESIS
# ============================================================
appendInfoLine: "[6/7] Rebuilding tiers and resynthesising..."

selectObject: manipID, pitchTier
Replace pitch tier

selectObject: manipID, durTier
Replace duration tier

selectObject: manipID
resynthID = Get resynthesis (overlap-add)
Rename: "gct_resynth"

# ---- post-resynthesis intensity shaping (CONTINUOUS envelope) ----
# The transformed intensity (col 5) becomes a smooth gain applied via an
# IntensityTier. An IntensityTier interpolates LINEARLY between breakpoints,
# so multiplying it onto the sound is click-free - unlike writing gain at
# isolated samples and leaving the rest at 1 (which is an impulse train).
# We additionally box-smooth the per-frame gain over gain_smooth_ms before
# laying down points, so even the breakpoints are gentle.
selectObject: resynthID
resynDur = Get total duration

gainWin = floor((gain_smooth_ms / 1000) / time_step / 2)
if gainWin < 1
    gainWin = 1
endif

# Pre-compute smoothed linear gain per frame into a 1-col matrix.
gainCol = Create simple Matrix: "gct_gaincol", nFrames, 1, "0"
for i to nFrames
    gsum = 0
    gn = 0
    for k from -gainWin to gainWin
        j = i + k
        if j >= 1 and j <= nFrames
            selectObject: featOut
            dbV = Get value in cell: j, 5
            gdb = dbV - meanDB
            if gdb > 12
                gdb = 12
            elsif gdb < -12
                gdb = -12
            endif
            gl = 10^(gdb / 20)
            gl = (1 - intensity_influence) + intensity_influence * gl
            gsum += gl
            gn += 1
        endif
    endfor
    selectObject: gainCol
    Set value: i, 1, gsum / gn
endfor

# Build an IntensityTier of the gain in dB (IntensityTier is a dB curve;
# value 0 dB = unity gain). Convert linear gain -> dB for the tier points.
gainTier = Create IntensityTier: "gct_gaintier", 0, resynDur
for i to nFrames
    t = (i - 0.5) * time_step
    if t >= 0 and t <= resynDur
        selectObject: gainCol
        gl = Get value in cell: i, 1
        if gl < 0.001
            gl = 0.001
        endif
        gdbTier = 20 * log10(gl)
        selectObject: gainTier
        Add point: t, gdbTier
    endif
endfor

# Apply the gain envelope to the resynthesised sound (click-free multiply).
# NOTE: Sound + IntensityTier "Multiply" creates a NEW Sound (named
# <name>_int); it does NOT modify in place. Capture that result as the
# real output and discard the pre-multiply copy, otherwise the gain would
# never reach the output and a stray *_int object would be orphaned.
selectObject: resynthID
preGainID = Copy: "gct_pre_gain"
plusObject: gainTier
finalID = Multiply: "yes"
removeObject: preGainID

# ---- anti-clipping: scale peak just under 1 if needed ----
selectObject: finalID
peak = Get absolute extremum: 0, 0, "None"
if peak > 0.99
    Scale peak: 0.99
endif
# output gain (bounded so it can't push back into clipping)
if output_gain <> 1.0
    Formula: "self * output_gain"
    peak2 = Get absolute extremum: 0, 0, "None"
    if peak2 > 0.99
        Scale peak: 0.99
    endif
endif

Rename: "Gesture_Convolution_Transform"

# ============================================================
# SECTION 7B — VISUALIZATION (house style: 8-wide canvas)
# ------------------------------------------------------------
# Three data panels telling the story of the transformation:
#   1) pitch contour  - original (grey) vs transformed (red)
#   2) local duration factor (time dilation)
#   3) intensity (blue) + accent strength (orange)
# Reads from featRaw (original) and featOut (transformed), both
# still alive at this point.
# ============================================================
if draw_visualization
    # precompute axis ranges from the data
    stMin = 1e9
    stMax = -1e9
    dbMin = 1e9
    dbMax = -1e9
    accMax = 1e-9
    durMin = 1e9
    durMax = -1e9
    for i to nFrames
        selectObject: featRaw
        so = Get value in cell: i, 1
        selectObject: featOut
        st = Get value in cell: i, 1
        dr = Get value in cell: i, 4
        db = Get value in cell: i, 5
        selectObject: featRaw
        ac = Get value in cell: i, 7
        if so < stMin
            stMin = so
        endif
        if so > stMax
            stMax = so
        endif
        if st < stMin
            stMin = st
        endif
        if st > stMax
            stMax = st
        endif
        if db < dbMin
            dbMin = db
        endif
        if db > dbMax
            dbMax = db
        endif
        if ac > accMax
            accMax = ac
        endif
        if dr < durMin
            durMin = dr
        endif
        if dr > durMax
            durMax = dr
        endif
    endfor
    if stMax - stMin < 1
        stMin = stMin - 1
        stMax = stMax + 1
    endif
    if dbMax - dbMin < 1
        dbMin = dbMin - 1
        dbMax = dbMax + 1
    endif
    if durMax - durMin < 0.05
        durMin = durMin - 0.05
        durMax = durMax + 0.05
    endif

    Erase all
    Font size: 10
    Line width: 1
    Black

    # ---- TITLE BAND  (0,8,0,0.6 ; single centred line) ----
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 13
    Text: 0.5, "centre", 0.5, "half",
        ... "##Gesture Convolution Transform##  -  " + presetName$ +
        ... ",  wet " + fixed$(effect_amount, 2)

    # ---- PANEL 1: pitch contour (orig grey vs transformed red) ----
    Select outer viewport: 0, 8, 0.7, 2.0
    Select inner viewport: 0.6, 7.7, 0.85, 1.9
    Axes: 0, totalDur, stMin, stMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, totalDur, stMin, stMax
    # original (grey)
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 1
    for i from 2 to nFrames
        selectObject: featRaw
        y0 = Get value in cell: i - 1, 1
        y1 = Get value in cell: i, 1
        t0 = (i - 1.5) * time_step
        t1 = (i - 0.5) * time_step
        Draw line: t0, y0, t1, y1
    endfor
    # transformed (red)
    Colour: "{0.75, 0.20, 0.20}"
    Line width: 2
    for i from 2 to nFrames
        selectObject: featOut
        y0 = Get value in cell: i - 1, 1
        y1 = Get value in cell: i, 1
        t0 = (i - 1.5) * time_step
        t1 = (i - 0.5) * time_step
        Draw line: t0, y0, t1, y1
    endfor
    Black
    Line width: 1
    Font size: 8
    Marks left: 4, "yes", "yes", "no"
    Text left: "yes", "semitones"
    Draw inner box
    Font size: 9
    Text top: "no", "##Pitch contour##   (grey = original, red = transformed)"

    # ---- PANEL 2: local duration factor ----
    Select outer viewport: 0, 8, 2.1, 3.0
    Select inner viewport: 0.6, 7.7, 2.2, 2.9
    Axes: 0, totalDur, durMin, durMax
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, totalDur, durMin, durMax
    # unity reference line at 1.0
    Colour: "{0.7, 0.7, 0.7}"
    Draw line: 0, 1, totalDur, 1
    Colour: "{0.20, 0.45, 0.75}"
    Line width: 2
    for i from 2 to nFrames
        selectObject: featOut
        y0 = Get value in cell: i - 1, 4
        y1 = Get value in cell: i, 4
        t0 = (i - 1.5) * time_step
        t1 = (i - 0.5) * time_step
        Draw line: t0, y0, t1, y1
    endfor
    Black
    Line width: 1
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "dur factor"
    Draw inner box
    Font size: 9
    Text top: "no", "##Local duration factor##   (>1 = stretch, <1 = compress)"

    # ---- PANEL 3: intensity + accent ----
    Select outer viewport: 0, 8, 3.1, 4.0
    Select inner viewport: 0.6, 7.7, 3.2, 3.9
    Axes: 0, totalDur, dbMin, dbMax
    Paint rectangle: "{0.98, 0.97, 0.97}", 0, totalDur, dbMin, dbMax
    # intensity (transformed) in blue
    Colour: "{0.20, 0.45, 0.75}"
    Line width: 2
    for i from 2 to nFrames
        selectObject: featOut
        y0 = Get value in cell: i - 1, 5
        y1 = Get value in cell: i, 5
        t0 = (i - 1.5) * time_step
        t1 = (i - 0.5) * time_step
        Draw line: t0, y0, t1, y1
    endfor
    # accent (original) scaled into this panel, orange
    Colour: "{0.90, 0.50, 0.15}"
    Line width: 1
    for i from 2 to nFrames
        selectObject: featRaw
        a0 = Get value in cell: i - 1, 7
        a1 = Get value in cell: i, 7
        y0 = dbMin + (a0 / accMax) * (dbMax - dbMin)
        y1 = dbMin + (a1 / accMax) * (dbMax - dbMin)
        t0 = (i - 1.5) * time_step
        t1 = (i - 0.5) * time_step
        Draw line: t0, y0, t1, y1
    endfor
    Black
    Line width: 1
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "dB"
    Text bottom: "yes", "time (s)"
    Draw inner box
    Font size: 9
    Text top: "no", "##Intensity## (blue) ##+ accent## (orange, scaled)"

    # ---- LEGEND BAND (single row of swatches + labels) ----
    Select outer viewport: 0, 8, 4.1, 4.6
    Axes: 0, 1, 0, 1
    Font size: 8
    Paint rectangle: "{0.6, 0.6, 0.6}", 0.02, 0.05, 0.40, 0.62
    Text: 0.07, "left", 0.5, "half", "original pitch"
    Paint rectangle: "{0.75, 0.20, 0.20}", 0.24, 0.27, 0.40, 0.62
    Text: 0.29, "left", 0.5, "half", "transformed pitch"
    Paint rectangle: "{0.20, 0.45, 0.75}", 0.50, 0.53, 0.40, 0.62
    Text: 0.55, "left", 0.5, "half", "duration / intensity"
    Paint rectangle: "{0.90, 0.50, 0.15}", 0.78, 0.81, 0.40, 0.62
    Text: 0.83, "left", 0.5, "half", "accent"
    Black

    # ---- SUMMARY PANEL (grey background) ----
    Select outer viewport: 0, 8, 4.7, 5.9
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Draw inner box
    Font size: 7
    Black
    Text: 0.02, "left", 0.82, "half",
        ... "preset: " + presetName$ + "    frames: " + string$(nFrames) +
        ... "    grid: " + fixed$(time_step * 1000, 0) + " ms"
    Text: 0.02, "left", 0.50, "half",
        ... "pitch infl " + fixed$(pitch_influence, 2) +
        ... "    smear " + fixed$(time_smear_amount, 2) +
        ... "    int infl " + fixed$(intensity_influence, 2) +
        ... "    accent " + fixed$(accent_sensitivity, 2)
    Text: 0.02, "left", 0.18, "half",
        ... "max shift " + fixed$(max_pitch_shift_semitones, 1) + " st" +
        ... "    max jump " + fixed$(max_pitch_jump_semitones, 1) + " st" +
        ... "    dur " + fixed$(min_duration_factor, 2) + "-" +
        ... fixed$(max_duration_factor, 2)
    Font size: 10
endif

# ============================================================
# SECTION 8 — FINAL CLEANUP
# ============================================================
appendInfoLine: "[7/7] Cleaning up..."

removeObject: workID, manipID, pitchObj, intObj
removeObject: featRaw, featNorm, featConv, featOut
removeObject: pitchTier, durTier, resynthID
removeObject: smoothCol1, smoothCol4, gainCol, gainTier

selectObject: finalID
if play_result
    Play
endif

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: Gesture_Convolution_Transform"
appendInfoLine: "(original left untouched in the Objects window)"
