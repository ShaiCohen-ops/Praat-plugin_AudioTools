# Changelog v0.4 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
# ============================================================
# Praat AudioTools - OM_Rhythm_Tree_Slicer.praat
# OM Rhythm Tree Slicer
# OpenMusic rhythm-tree operations applied to a Sound
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# WHAT THIS DOES
#   Reads a FLAT OpenMusic-style proportion vector such as
#   "1 1 2 -1 1" and uses it as a metric grid over the selected
#   Sound. Positive values sound and negative values are rests.
#   This is an AudioTools audio-realisation layer, not a complete
#   parser for OpenMusic's recursive RT notation. The measure length
#   comes from the tempo and time signature,
#
#       measure_dur = (60 / BPM) * Numerator * (4 / Denominator)
#
#   and leaf i occupies d_i = measure_dur * |p_i| / SUM(|p|), so
#   a flat measure-level proportion list ( (num den) (p1 ... pn) )
#   is realised directly as audio. Positive leaves are extracted from the source;
#   negative leaves are built as silent Sounds of exactly the
#   right length. Before any slicing happens the proportion
#   vector is put through one of six OM-style transformations, and the
#   resulting slices - audio and silence alike - are reassembled
#   with "Concatenate" into a single new Sound; by default edge
#   fades are applied only where the source material is actually
#   discontinuous (or touches a rest / file boundary). The result is
#   named [Original_Name]_OM_RT. Real-valued proportions are
#   accepted as an AudioTools extension. NOTE: in OpenMusic RT
#   notation, floating-point leaf tokens denote ties; this slicer
#   treats them numerically and reports that semantic difference.
#
# TRANSFORMATIONS (AudioTools operations on the flat array BEFORE slicing)
#     None            - leaves in their original order.
#     reverse-tree    - temporal retrograde, p'[k] = p[n+1-k].
#       A leaf-level retrograde: the order of leaves reverses but
#       a leaf is not played backwards internally.
#     rotate-tree     - circular shift of whole leaves,
#       p'[k] = p[wrap(k+N)]. Magnitude and sign travel together,
#       so the onset grid itself moves. N = Rotation_steps and may
#       be negative; N = n is the identity.
#     rotate-props    - proportional rotation that leaves the GRID
#       BOUNDARIES untouched: |p'[k]| = |p[k]| while the sign
#       pattern (and the material identity) rotates by N. The
#       onset grid is therefore bit-identical to None; only which
#       slots sound, and what fills them, changes.
#     subst-rhythm    - leaf T (Subst_target_leaf) is replaced by
#       a nested tuplet array s[1..m] (Subst_proportions). Child j
#       receives |p[T]| * |s_j| / SUM(|s|) and the SIGN of s_j, so
#       SUM(|p|) - and hence every other leaf boundary - is
#       unchanged. This is the RT nesting ( ... (p_T (s1 s2 ...)) ).
#     invert-rhythm   - p'[k] = -p[k]; notes and rests swap while
#       the grid stays exactly as written.
#
# PROPORTION CONVENTION (read this before typing a tree)
#   The vector fills ONE measure, and Repetitions repeats that
#   measure. Only the RATIOS matter: "1 1 2" and "2 2 4" give the
#   same grid, because each leaf is normalised by SUM(|p|). A
#   leaf of 0 is rejected because this audio slicer has no zero-time
#   event model. OpenMusic itself uses 0 for grace notes. With
#   Progressive_rotation on, the
#   rotations accumulate across repetitions - repetition r is
#   rotated by N*r, so repetition 1 is already rotated by N. This
#   is the explicit AudioTools progressive-rotation convention.
#
# MATERIAL MAPPING (which audio lands in which leaf)
#     Sequential   - a playhead walks through the source and
#       advances only on SOUNDING leaves, so rests do not consume
#       material and the source is heard continuously.
#     Proportional - with Material_follows_transform OFF, a leaf at
#       output position t takes material from the same relative
#       position in the source (rests included). With it ON, the
#       source position belongs to the leaf's ORIGINAL pre-transform
#       identity; subst-rhythm children subdivide that parent window.
#     Fixed start  - every leaf reads from the source start; a
#       stutter.
#   Material_follows_transform decides whether material travels
#   WITH the leaf (so a retrograde really does play the source
#   backwards) or follows playback order (so the material runs
#   forwards through a rearranged rhythm). Under subst-rhythm the
#   children inherit their parent's material window and subdivide
#   it in order.
#
# METHOD NOTES / DELIBERATE ADDITIONS
#   - Fade_ms is a raised-cosine edge guard followed by a BUTT JOIN.
#     It is deliberately not an overlap crossfade: an overlap would
#     shorten the result and destroy the exact metric grid. With
#     Fade_only_discontinuities on (default), contiguous reads from
#     the same source are NOT faded, so continuous source material
#     stays continuous; fades are used only at discontinuities, rests,
#     zero-padding and the outer file edges. The fade is clamped to
#     half a slice so it cannot overrun.
#   - "Concatenate" joins whichever Sound objects are selected in
#     LIST order (creation order), not in the order they were
#     selected. Every slice is therefore created directly in its
#     final temporal position, and the script asserts that the
#     object IDs came out ascending before concatenating.
#   - Leaf lengths are computed in SAMPLES from cumulative rounded
#     boundaries. Each leaf therefore has an exact integer target and
#     each measure sums exactly to measureSamples; extraction shortfalls
#     are filled with exact-length silence. The report prints requested
#     vs achieved duration and the drift.
#   - Multichannel input is preserved. Praat Concatenate supports
#     multichannel Sounds when sample rate and channel count match;
#     silent rest/filler objects are therefore created with the same
#     number of channels as the source.
#   - A read that would run past the end of the source is pulled
#     back so the slice ends at the source end, rather than
#     splicing a wrap-around in mid-slice. A leaf longer than the
#     whole source uses the WHOLE source once from its beginning
#     and fills the remainder with silence. Both cases are counted in the report.
#   - Normalization defaults to an attenuate-only peak ceiling, so
#     the rhythm can be built without the level being rewritten;
#     "Normalize to peak" and "Off" are both available.
#   - Added form fields beyond the bare spec: Repetitions,
#     Progressive_rotation, Material_mapping,
#     Material_follows_transform, Fade_only_discontinuities,
#     Normalization / Peak_dB,
#     Draw_visualization and Play_result.
#
# KNOWN LIMITS
#   - One flat proportion vector per measure. Nested trees are
#     expressed through subst-rhythm rather than through a
#     parenthesised input syntax.
#   - The modern colon form syntax used below requires Praat 6.3
#     or newer; on 6.1.x / 6.2.x the form is not recognised and a
#     runScript call reports "Found N arguments but expected only
#     0". The body of the script itself runs identically from
#     6.1.38 through 7.0.
# ============================================================

form: "OM Rhythm Tree Slicer v0.4"
    comment: "Presets override the SCORE fields below (time signature, proportions,"
    comment: "transformation, rotation, substitution, repetitions, material mapping)."
    optionmenu: "Preset", 1
        option: "Manual (use fields below)"
        option: "4/4 quarters - None"
        option: "5/4 additive - reverse-tree"
        option: "7/8 additive - rotate-tree (progressive)"
        option: "4/4 mask - rotate-props"
        option: "4/4 nested quintuplet - subst-rhythm"
        option: "4/4 mask - invert-rhythm"
    comment: "--- Metre --------------------------------------------------------"
    comment: "Tempo BPM is quarter-note BPM (the denominator scales the measure)."
    positive: "Tempo_BPM", "120"
    natural: "Numerator", "4"
    natural: "Denominator", "4"
    natural: "Repetitions", "2"
    comment: "--- Rhythm tree (space separated; negative = rest) ----------------"
    sentence: "Proportions", "1 1 2 -1 1"
    comment: "--- Transformation -----------------------------------------------"
    optionmenu: "Transformation", 1
        option: "None"
        option: "reverse-tree"
        option: "rotate-tree"
        option: "rotate-props"
        option: "subst-rhythm"
        option: "invert-rhythm"
    integer: "Rotation_steps", "1"
    boolean: "Progressive_rotation", 0
    natural: "Subst_target_leaf", "3"
    sentence: "Subst_proportions", "1 1 1"
    comment: "--- Source material ----------------------------------------------"
    optionmenu: "Material_mapping", 1
        option: "Sequential (advance playhead)"
        option: "Proportional (map to position)"
        option: "Fixed start (stutter)"
    boolean: "Material_follows_transform", 1
    comment: "--- Output -------------------------------------------------------"
    positive: "Fade_ms", "8"
    boolean: "Fade_only_discontinuities", 1
    optionmenu: "Normalization", 1
        option: "Peak ceiling (attenuate only)"
        option: "Normalize to peak"
        option: "Off (keep source level)"
    real: "Peak_dB", "-1.0"
    boolean: "Draw_visualization", 1
    boolean: "Play_result", 1
endform

# ----------------------------------------------------------------------------
# STEP 0 -- presets
# Every preset writes EVERY score field it can influence.  A preset that sets
# only some of them would behave differently from run to run depending on what
# was left in the form (a bug pattern this library has been bitten by before).
# Tempo, Fade, Fade_only_discontinuities, Normalization, Peak,
# Material_follows_transform and Draw_visualization are deliberately
# NOT touched by presets.
# ----------------------------------------------------------------------------
presetApplied$ = "none"

if preset$ <> "Manual (use fields below)"
    presetApplied$ = preset$
    if preset$ = "4/4 quarters - None"
        numerator = 4
        denominator = 4
        proportions$ = "1 1 1 1"
        transformation$ = "None"
        rotation_steps = 1
        progressive_rotation = 0
        subst_target_leaf = 1
        subst_proportions$ = "1 1"
        repetitions = 2
        material_mapping$ = "Sequential (advance playhead)"
    elsif preset$ = "5/4 additive - reverse-tree"
        numerator = 5
        denominator = 4
        proportions$ = "2 1 1 -1 2 1"
        transformation$ = "reverse-tree"
        rotation_steps = 1
        progressive_rotation = 0
        subst_target_leaf = 1
        subst_proportions$ = "1 1"
        repetitions = 2
        material_mapping$ = "Sequential (advance playhead)"
    elsif preset$ = "7/8 additive - rotate-tree (progressive)"
        numerator = 7
        denominator = 8
        proportions$ = "2 -1 2 1 1"
        transformation$ = "rotate-tree"
        rotation_steps = 2
        progressive_rotation = 1
        subst_target_leaf = 1
        subst_proportions$ = "1 1"
        repetitions = 4
        material_mapping$ = "Sequential (advance playhead)"
    elsif preset$ = "4/4 mask - rotate-props"
        numerator = 4
        denominator = 4
        proportions$ = "1 1 -1 1 1 -1 1 1"
        transformation$ = "rotate-props"
        rotation_steps = 3
        progressive_rotation = 1
        subst_target_leaf = 1
        subst_proportions$ = "1 1"
        repetitions = 4
        material_mapping$ = "Proportional (map to position)"
    elsif preset$ = "4/4 nested quintuplet - subst-rhythm"
        numerator = 4
        denominator = 4
        proportions$ = "1 1 -1 1"
        transformation$ = "subst-rhythm"
        rotation_steps = 1
        progressive_rotation = 0
        subst_target_leaf = 2
        subst_proportions$ = "1 1 1 1 1"
        repetitions = 2
        material_mapping$ = "Sequential (advance playhead)"
    elsif preset$ = "4/4 mask - invert-rhythm"
        numerator = 4
        denominator = 4
        proportions$ = "1 -1 1 1 -1 1 -1 1"
        transformation$ = "invert-rhythm"
        rotation_steps = 1
        progressive_rotation = 0
        subst_target_leaf = 1
        subst_proportions$ = "1 1"
        repetitions = 2
        material_mapping$ = "Sequential (advance playhead)"
    endif
endif

# ----------------------------------------------------------------------------
# STEP 1 -- validate the selection and read the source
# ----------------------------------------------------------------------------
if numberOfSelected ("Sound") <> 1
    exitScript: "Select exactly ONE Sound object before running OM Rhythm Tree Slicer."
endif

srcId = selected ("Sound")
srcName$ = selected$ ("Sound")

selectObject: srcId
srcChannels = Get number of channels
srcRate = Get sampling frequency
srcXmin = Get start time
srcXmax = Get end time
srcSamples = Get number of samples
srcDur = srcXmax - srcXmin
dt = 1 / srcRate

if srcDur <= 0 or srcSamples < 2
    exitScript: "The selected Sound is empty."
endif

# ----------------------------------------------------------------------------
# STEP 2 -- string parsing
# Uses the THREE-argument mid$ throughout: the two-argument form returns exactly
# one character, which silently truncates a tokenizer to its first token.
# number("xyz") returns undefined rather than erroring, so it is a safe test.
# ----------------------------------------------------------------------------
procedure padLeft: .s$, .w
    # right$() TRUNCATES, it does not pad, so column alignment needs this
    .out$ = .s$
    while length (.out$) < .w
        .out$ = " " + .out$
    endwhile
    padded$ = .out$
endproc

procedure makeSilence: .n, .name$
    # a silent Sound of EXACTLY .n samples (used for rests and for filler)
    .dur = .n / srcRate
    Create Sound from formula: .name$, srcChannels, 0, .dur, srcRate, "0"
    silenceId = selected ("Sound")
    silenceN = Get number of samples
    if silenceN <> .n
        removeObject: silenceId
        .dur = (.n + 0.25) / srcRate
        Create Sound from formula: .name$, srcChannels, 0, .dur, srcRate, "0"
        silenceId = selected ("Sound")
        silenceN = Get number of samples
    endif
    if silenceN <> .n
        removeObject: silenceId
        exitScript: "Internal error: could not create an exact " + string$ (.n) + "-sample silence object."
    endif
endproc

procedure tokenize: .raw$
    .s$ = replace_regex$ (.raw$, "[,;\t]+", " ", 0)
    .s$ = replace_regex$ (.s$, "^ +", "", 0)
    .s$ = replace_regex$ (.s$, " +$", "", 0)
    .s$ = replace_regex$ (.s$, " +", " ", 0)
    nTok = 0
    .rest$ = .s$
    while length (.rest$) > 0
        .sp = index (.rest$, " ")
        if .sp = 0
            .piece$ = .rest$
            .rest$ = ""
        else
            .piece$ = mid$ (.rest$, 1, .sp - 1)
            .rest$ = mid$ (.rest$, .sp + 1, length (.rest$) - .sp)
        endif
        if length (.piece$) > 0
            .val = number (.piece$)
            if .val = undefined
                exitScript: "Cannot read '" + .piece$ + "' as a number in: " + .raw$
            endif
            nTok = nTok + 1
            tok [nTok] = .val
            tokText$ [nTok] = .piece$
        endif
    endwhile
endproc

@tokenize: proportions$
if nTok < 1
    exitScript: "The Proportions field is empty.  Give at least one value, e.g. 1 1 2 -1 1"
endif
nProp = nTok
sumAbs = 0
omFloatTokenCount = 0
for i to nProp
    prop [i] = tok [i]
    propToken$ [i] = tokText$ [i]
    if prop [i] = 0
        exitScript: "Proportion number " + string$ (i) + " is 0.  OpenMusic uses 0 for a grace note; this audio slicer does not implement zero-time grace events."
    endif
    if index (propToken$ [i], ".") > 0 or index (propToken$ [i], "e") > 0 or index (propToken$ [i], "E") > 0
        omFloatTokenCount = omFloatTokenCount + 1
    endif
    sumAbs = sumAbs + abs (prop [i])
endfor

origCum = 0
for i to nProp
    origStartFrac [i] = origCum / sumAbs
    origDurFrac [i] = abs (prop [i]) / sumAbs
    origCum = origCum + abs (prop [i])
endfor

nSub = 0
if transformation$ = "subst-rhythm"
    @tokenize: subst_proportions$
    if nTok < 1
        exitScript: "subst-rhythm needs at least one value in Subst proportions."
    endif
    nSub = nTok
    subSumAbs = 0
    for i to nSub
        sub [i] = tok [i]
        if sub [i] = 0
            exitScript: "Substitution value " + string$ (i) + " is 0.  Zero-time grace subdivisions are not implemented in this audio slicer."
        endif
        subSumAbs = subSumAbs + abs (sub [i])
    endfor
endif

substTarget = subst_target_leaf
substClamped = 0
if transformation$ = "subst-rhythm" and substTarget > nProp
    substTarget = nProp
    substClamped = 1
endif

# ----------------------------------------------------------------------------
# STEP 3 -- metric grid
# ----------------------------------------------------------------------------
if peak_dB > 0
    exitScript: "Peak_dB must be 0 dBFS or lower; positive values can exceed Praat's normal audio range."
endif

measureDur = (60 / tempo_BPM) * numerator * (4 / denominator)
beatDur = (60 / tempo_BPM) * (4 / denominator)
measureSamples = round (measureDur * srcRate)
totalSamples = repetitions * measureSamples
totalOutDur = totalSamples / srcRate

if measureSamples < nProp * 2
    exitScript: "The measure is only " + string$ (measureSamples) + " samples long at this tempo and sample rate, which cannot hold " + string$ (nProp) + " leaves.  Lower the tempo or use fewer proportions."
endif

denomWarn = 0
dpow = denominator
while dpow > 1 and dpow / 2 = floor (dpow / 2)
    dpow = dpow / 2
endwhile
if dpow <> 1
    denomWarn = 1
endif

# ----------------------------------------------------------------------------
# STEP 4 -- the transformation itself
# Fills nT, tProp[] (signed magnitude), tSrc[] (identity = index of the ORIGINAL
# leaf this one came from) and tF0[]/tF1[] (position inside that original leaf's
# material window, used by subst-rhythm children).
# ----------------------------------------------------------------------------
procedure wrapIndex: .i, .n
    # 0-based wrap that is correct for negative .i as well
    wrapped = .i - .n * floor (.i / .n)
endproc

procedure applyTransform: .steps
    if transformation$ = "None"
        nT = nProp
        for .k to nT
            tProp [.k] = prop [.k]
            tSrc [.k] = .k
            tF0 [.k] = 0
            tF1 [.k] = 1
        endfor

    elsif transformation$ = "reverse-tree"
        nT = nProp
        for .k to nT
            .idx = nProp + 1 - .k
            tProp [.k] = prop [.idx]
            tSrc [.k] = .idx
            tF0 [.k] = 0
            tF1 [.k] = 1
        endfor

    elsif transformation$ = "rotate-tree"
        nT = nProp
        for .k to nT
            @wrapIndex: .k - 1 + .steps, nProp
            .idx = wrapped + 1
            tProp [.k] = prop [.idx]
            tSrc [.k] = .idx
            tF0 [.k] = 0
            tF1 [.k] = 1
        endfor

    elsif transformation$ = "rotate-props"
        # magnitudes stay in place -> grid boundaries identical to "None";
        # only the sign pattern and the material identity rotate
        nT = nProp
        for .k to nT
            @wrapIndex: .k - 1 + .steps, nProp
            .idx = wrapped + 1
            if prop [.idx] > 0
                tProp [.k] = abs (prop [.k])
            else
                tProp [.k] = -abs (prop [.k])
            endif
            tSrc [.k] = .idx
            tF0 [.k] = 0
            tF1 [.k] = 1
        endfor

    elsif transformation$ = "subst-rhythm"
        nT = 0
        for .i to nProp
            if .i <> substTarget
                nT = nT + 1
                tProp [nT] = prop [.i]
                tSrc [nT] = .i
                tF0 [nT] = 0
                tF1 [nT] = 1
            else
                .acc = 0
                for .j to nSub
                    .frac = abs (sub [.j]) / subSumAbs
                    nT = nT + 1
                    .mag = abs (prop [.i]) * .frac
                    if sub [.j] > 0
                        tProp [nT] = .mag
                    else
                        tProp [nT] = -.mag
                    endif
                    tSrc [nT] = .i
                    tF0 [nT] = .acc
                    tF1 [nT] = .acc + .frac
                    .acc = .acc + .frac
                endfor
            endif
        endfor

    elsif transformation$ = "invert-rhythm"
        nT = nProp
        for .k to nT
            tProp [.k] = -prop [.k]
            tSrc [.k] = .k
            tF0 [.k] = 0
            tF1 [.k] = 1
        endfor
    endif
endproc

# ----------------------------------------------------------------------------
# STEP 5 -- build the full leaf list (all repetitions) in SAMPLES
# Boundaries come from cumulative rounding of the measure length, so every
# repetition is exactly measureSamples long and the repetitions stay in phase.
# ----------------------------------------------------------------------------
nLeaf = 0
for r to repetitions
    steps = rotation_steps
    if progressive_rotation = 1
        steps = rotation_steps * r
    endif
    @applyTransform: steps

    tSumAbs = 0
    for k to nT
        tSumAbs = tSumAbs + abs (tProp [k])
    endfor

    prevBound = 0
    cum = 0
    for k to nT
        cum = cum + abs (tProp [k])
        bound = round ((cum / tSumAbs) * measureSamples)
        if k = nT
            bound = measureSamples
        endif
        nLeaf = nLeaf + 1
        leafRep [nLeaf] = r
        leafSlot [nLeaf] = k
        leafProp [nLeaf] = tProp [k]
        leafSrc [nLeaf] = tSrc [k]
        leafF0 [nLeaf] = tF0 [k]
        leafF1 [nLeaf] = tF1 [k]
        leafStart [nLeaf] = (r - 1) * measureSamples + prevBound
        leafN [nLeaf] = bound - prevBound
        if leafN [nLeaf] < 1
            exitScript: "Leaf " + string$ (k) + " of measure " + string$ (r) + " rounds to zero samples.  Lower the tempo, raise the sample rate, or use fewer / larger proportions."
        endif
        prevBound = bound
    endfor
    if r = 1
        nTfirst = nT
        for k to nT
            firstProp [k] = tProp [k]
            firstSrc [k] = tSrc [k]
        endfor
    endif
endfor

# ----------------------------------------------------------------------------
# STEP 6 -- material offsets
# Sequential mapping can either attach source-consumption order to original leaf
# identity (material follows transform) or to output order. Proportional mapping
# is explicit: follows-transform maps by ORIGINAL leaf position (and subst child
# fraction); otherwise it maps by OUTPUT timeline position. Fixed-start ignores
# the transform flag by definition.
# ----------------------------------------------------------------------------
for q to nLeaf
    ordIdx [q] = q
endfor

if material_mapping$ = "Sequential (advance playhead)" and material_follows_transform = 1
    keyScale = nProp + 2
    for a from 2 to nLeaf
        moving = ordIdx [a]
        keyMove = leafRep [moving] * keyScale + leafSrc [moving] + leafF0 [moving]
        b = a - 1
        stop = 0
        while b >= 1 and stop = 0
            other = ordIdx [b]
            keyOther = leafRep [other] * keyScale + leafSrc [other] + leafF0 [other]
            if keyOther > keyMove
                ordIdx [b + 1] = ordIdx [b]
                b = b - 1
            else
                stop = 1
            endif
        endwhile
        ordIdx [b + 1] = moving
    endfor
endif

playhead = 0
for q to nLeaf
    k = ordIdx [q]
    leafDur = leafN [k] / srcRate
    if material_mapping$ = "Sequential (advance playhead)"
        leafOff [k] = playhead
        if leafProp [k] > 0
            playhead = playhead + leafDur
        endif
    elsif material_mapping$ = "Proportional (map to position)"
        if material_follows_transform = 1
            srcLeaf = leafSrc [k]
            withinMeasure = origStartFrac [srcLeaf] + leafF0 [k] * origDurFrac [srcLeaf]
            globalFrac = ((leafRep [k] - 1) + withinMeasure) / repetitions
            leafOff [k] = globalFrac * srcDur
        else
            leafOff [k] = (leafStart [k] / totalSamples) * srcDur
        endif
    else
        leafOff [k] = 0
    endif
endfor

# ----------------------------------------------------------------------------
# STEP 6b -- plan exact reads and boundary fades before creating objects
# This makes the render deterministic and lets us distinguish a truly contiguous
# source join from a discontinuity. A long leaf (> whole source) deliberately
# uses the whole source once from sample 0, then pads with silence.
# ----------------------------------------------------------------------------
nPulledBack = 0
nLongWholeSource = 0
for k to nLeaf
    planOffSamp [k] = 0
    planTake [k] = 0
    planPad [k] = 0
    if leafProp [k] > 0
        target = leafN [k]
        if target > srcSamples
            planOffSamp [k] = 0
            planTake [k] = srcSamples
            planPad [k] = target - srcSamples
            nLongWholeSource = nLongWholeSource + 1
        else
            off = leafOff [k]
            off = off - srcDur * floor (off / srcDur)
            offSamp = round (off * srcRate)
            if offSamp > srcSamples - 1
                offSamp = srcSamples - 1
            endif
            avail = srcSamples - offSamp
            if avail < target
                offSamp = srcSamples - target
                nPulledBack = nPulledBack + 1
            endif
            planOffSamp [k] = offSamp
            planTake [k] = target
            planPad [k] = 0
        endif
    endif
endfor

for k to nLeaf
    needFadeIn [k] = 0
    needFadeOut [k] = 0
    if leafProp [k] > 0
        if fade_only_discontinuities = 0
            needFadeIn [k] = 1
            needFadeOut [k] = 1
        else
            if k = 1
                needFadeIn [k] = 1
            else
                if leafProp [k - 1] < 0 or planPad [k - 1] > 0
                    needFadeIn [k] = 1
                elsif planOffSamp [k] <> planOffSamp [k - 1] + planTake [k - 1]
                    needFadeIn [k] = 1
                endif
            endif
            if k = nLeaf or planPad [k] > 0
                needFadeOut [k] = 1
            else
                if leafProp [k + 1] < 0
                    needFadeOut [k] = 1
                elsif planOffSamp [k + 1] <> planOffSamp [k] + planTake [k]
                    needFadeOut [k] = 1
                endif
            endif
        endif
    endif
endfor

# ----------------------------------------------------------------------------
# STEP 7 -- slice, fade and collect
# Objects are created strictly in temporal order.  This matters: Praat's
# Concatenate joins by OBJECT-LIST ORDER, not by selection order, and the only
# safe way to control it is to create the pieces in the order you want them.
# ----------------------------------------------------------------------------
# Preserve the source channel topology. Praat Concatenate supports multichannel
# Sounds as long as all pieces share sample rate and channel count.
workId = srcId

fadeSecNominal = fade_ms / 1000
nObj = 0
achieved = 0
nSounding = 0
nRests = 0
nZeroPadded = 0
nFadeClamped = 0
padSamplesTotal = 0
lastId = 0
orderOk = 1

for k to nLeaf
    target = leafN [k]

    if leafProp [k] > 0
        # --- sounding leaf: extract from the source -------------------------
        offSamp = planOffSamp [k]
        take = planTake [k]
        pad = planPad [k]

        t1 = srcXmin + offSamp * dt
        t2 = srcXmin + (offSamp + take) * dt
        selectObject: workId
        Extract part: t1, t2, "rectangular", 1, "no"
        sliceId = selected ("Sound")
        got = Get number of samples

        # Extract part can land one sample either side of the requested window.
        # Trim if long; a short read is absorbed by the silent filler below.
        if got > target
            selectObject: sliceId
            Extract part: 0, target * dt, "rectangular", 1, "no"
            trimId = selected ("Sound")
            removeObject: sliceId
            sliceId = trimId
            selectObject: sliceId
            got = Get number of samples
        endif
        pad = target - got
        if pad < 0
            pad = 0
        endif

        # Raised-cosine edge guard. With discontinuity-only mode, contiguous
        # source reads are left untouched; only real edit boundaries are faded.
        sliceDur = got * dt
        fadeSec = fadeSecNominal
        if (needFadeIn [k] = 1 or needFadeOut [k] = 1) and fadeSec > sliceDur / 2
            fadeSec = sliceDur / 2
            nFadeClamped = nFadeClamped + 1
        endif
        if fadeSec > 0 and (needFadeIn [k] = 1 or needFadeOut [k] = 1)
            selectObject: sliceId
            if needFadeIn [k] = 1 and needFadeOut [k] = 1
                fadeFormula$ = "if x < " + string$ (fadeSec)
                ... + " then self * 0.5 * (1 - cos (pi * x / " + string$ (fadeSec) + "))"
                ... + " else if x > " + string$ (sliceDur - fadeSec)
                ... + " then self * 0.5 * (1 - cos (pi * (" + string$ (sliceDur) + " - x) / " + string$ (fadeSec) + "))"
                ... + " else self fi fi"
            elsif needFadeIn [k] = 1
                fadeFormula$ = "if x < " + string$ (fadeSec)
                ... + " then self * 0.5 * (1 - cos (pi * x / " + string$ (fadeSec) + ")) else self fi"
            else
                fadeFormula$ = "if x > " + string$ (sliceDur - fadeSec)
                ... + " then self * 0.5 * (1 - cos (pi * (" + string$ (sliceDur) + " - x) / " + string$ (fadeSec) + ")) else self fi"
            endif
            Formula: fadeFormula$
        endif

        nObj = nObj + 1
        objId [nObj] = sliceId
        if sliceId < lastId
            orderOk = 0
        endif
        lastId = sliceId
        achieved = achieved + got
        nSounding = nSounding + 1
        leafTook [k] = got
        leafOffUsed [k] = offSamp * dt

        if pad > 0
            @makeSilence: pad, "OMRT_pad"
            nObj = nObj + 1
            objId [nObj] = silenceId
            if silenceId < lastId
                orderOk = 0
            endif
            lastId = silenceId
            achieved = achieved + silenceN
            nZeroPadded = nZeroPadded + 1
            padSamplesTotal = padSamplesTotal + silenceN
        endif
    else
        # --- rest: a silent Sound of exactly the right length ---------------
        @makeSilence: target, "OMRT_rest"
        nObj = nObj + 1
        objId [nObj] = silenceId
        if silenceId < lastId
            orderOk = 0
        endif
        lastId = silenceId
        achieved = achieved + silenceN
        nRests = nRests + 1
        leafTook [k] = silenceN
        leafOffUsed [k] = undefined
    endif
endfor

if orderOk = 0
    for j to nObj
        removeObject: objId [j]
    endfor
    exitScript: "Internal error: temporary slices are not in ascending object order, so Concatenate would join them in the wrong sequence.  Nothing was written."
endif

# ----------------------------------------------------------------------------
# STEP 8 -- concatenate, level, rename
# ----------------------------------------------------------------------------
selectObject: objId [1]
for j from 2 to nObj
    plusObject: objId [j]
endfor
Concatenate
outId = selected ("Sound")

selectObject: outId
outSamples = Get number of samples
outDur = Get total duration
driftSamples = outSamples - totalSamples

rawPeak = Get absolute extremum: 0, 0, "None"

targetPeak = 10 ^ (peak_dB / 20)
gainApplied = 1
if normalization$ = "Peak ceiling (attenuate only)"
    if rawPeak > targetPeak and rawPeak > 0
        gainApplied = targetPeak / rawPeak
        Formula: "self * " + string$ (gainApplied)
    endif
elsif normalization$ = "Normalize to peak"
    if rawPeak > 0
        gainApplied = targetPeak / rawPeak
        Formula: "self * " + string$ (gainApplied)
    endif
endif

selectObject: outId
finalPeak = Get absolute extremum: 0, 0, "None"

outName$ = srcName$ + "_OM_RT"
selectObject: outId
Rename: outName$

# ----------------------------------------------------------------------------
# STEP 9 -- clean up every temporary object
# ----------------------------------------------------------------------------
for j to nObj
    removeObject: objId [j]
endfor

# ----------------------------------------------------------------------------
# STEP 10 -- report
# One writeInfoLine, then appendInfoLine only: a second writeInfoLine erases
# everything above it.
# ----------------------------------------------------------------------------
writeInfoLine: "=== OM Rhythm Tree Slicer  v0.4 ==================================="
appendInfoLine: ""
appendInfoLine: "SOURCE"
appendInfoLine: "  Object            : ", srcName$
appendInfoLine: "  Duration          : ", fixed$ (srcDur, 4), " s   (", srcSamples, " samples @ ", fixed$ (srcRate, 0), " Hz)"
appendInfoLine: "  Channels          : ", srcChannels, "   (preserved in output)"
appendInfoLine: "  Start time        : ", fixed$ (srcXmin, 4), " s"
appendInfoLine: ""
appendInfoLine: "SCORE"
if presetApplied$ <> "none"
    appendInfoLine: "  Preset            : ", presetApplied$
    appendInfoLine: "                      (overrode metre, proportions, transformation,"
    appendInfoLine: "                       rotation, substitution, repetitions, mapping)"
endif
appendInfoLine: "  Tempo             : ", fixed$ (tempo_BPM, 3), " BPM"
appendInfoLine: "  Time signature    : ", numerator, "/", denominator
if denomWarn = 1
    appendInfoLine: "  WARNING           : denominator ", denominator, " is not a power of 2."
    appendInfoLine: "                      The measure length formula still applies, but this is"
    appendInfoLine: "                      not a conventional notated metre."
endif
appendInfoLine: "  Beat duration     : ", fixed$ (beatDur, 6), " s"
appendInfoLine: "  Measure duration  : ", fixed$ (measureDur, 6), " s   (", measureSamples, " samples)"
appendInfoLine: "  Repetitions       : ", repetitions
appendInfoLine: "  Input proportions : ", proportions$, "   (", nProp, " leaves, sum |p| = ", fixed$ (sumAbs, 4), ")"
if omFloatTokenCount > 0
    appendInfoLine: "  OM syntax note    : ", omFloatTokenCount, " decimal token(s) treated as numeric ratios here."
    appendInfoLine: "                      In OpenMusic RT notation, floating-point leaves denote ties."
endif
appendInfoLine: "  Transformation    : ", transformation$
if transformation$ = "rotate-tree" or transformation$ = "rotate-props"
    appendInfoLine: "  Rotation steps    : ", rotation_steps, if progressive_rotation = 1 then "   (progressive: N*r on repetition r)" else "" fi
endif
if transformation$ = "subst-rhythm"
    appendInfoLine: "  Substitution      : leaf ", substTarget, " -> ", subst_proportions$, "   (", nSub, " children)"
    if substClamped = 1
        appendInfoLine: "  NOTE              : target leaf clamped to ", substTarget, " (only ", nProp, " leaves exist)"
    endif
endif
appendInfoLine: ""
appendInfoLine: "TRANSFORMED TREE (measure 1)"
line$ = "  "
for k to nTfirst
    line$ = line$ + fixed$ (firstProp [k], 3) + " "
endfor
appendInfoLine: line$
appendInfoLine: "  ", nTfirst, " leaves after transformation"
appendInfoLine: ""
appendInfoLine: "MATERIAL"
appendInfoLine: "  Mapping           : ", material_mapping$
appendInfoLine: "  Follows transform : ", if material_follows_transform = 1 then "yes (material travels with the leaf)" else "no (material follows playback order)" fi
appendInfoLine: "  Pulled-back reads : ", nPulledBack, "   (slice would have run past the source end)"
appendInfoLine: "  Zero-padded slices: ", nZeroPadded, "   (", padSamplesTotal, " samples of filler)"
appendInfoLine: "  Long > source     : ", nLongWholeSource, "   (used whole source once, then silence)"
appendInfoLine: ""
appendInfoLine: "SLICING"
appendInfoLine: "  Leaves total      : ", nLeaf, "   (", nSounding, " sounding, ", nRests, " rests)"
if nSounding = 0
    appendInfoLine: "  WARNING           : every leaf is a rest -- the output is pure silence."
endif
appendInfoLine: "  Temp objects      : ", nObj, "   (all removed)"
appendInfoLine: "  Edge fade         : ", fixed$ (fade_ms, 2), " ms raised cosine, butt-joined"
appendInfoLine: "  Fade policy       : ", if fade_only_discontinuities = 1 then "discontinuities/rests/outer edges only" else "every sounding slice edge" fi
appendInfoLine: "                      (NOT an overlap crossfade; exact metric length is preserved)"
if nFadeClamped > 0
    appendInfoLine: "  Fade clamped on   : ", nFadeClamped, " slice(s) shorter than 2 x fade"
endif
appendInfoLine: ""
appendInfoLine: "OUTPUT"
appendInfoLine: "  Object            : ", outName$, "   (id ", outId, ")"
appendInfoLine: "  Requested length  : ", fixed$ (totalOutDur, 6), " s   (", totalSamples, " samples)"
appendInfoLine: "  Achieved length   : ", fixed$ (outDur, 6), " s   (", outSamples, " samples)"
appendInfoLine: "  Drift             : ", driftSamples, " samples   (", fixed$ (driftSamples * dt * 1000, 4), " ms)"
appendInfoLine: "  Normalization     : ", normalization$
appendInfoLine: "  Peak before / after: ", fixed$ (rawPeak, 5), " / ", fixed$ (finalPeak, 5), "   (gain x ", fixed$ (gainApplied, 5), ")"
appendInfoLine: ""
appendInfoLine: "LEAF TABLE   (start / duration are output-timeline values)"
hdr$ = ""
@padLeft: "#", 4
hdr$ = hdr$ + padded$
@padLeft: "rep", 5
hdr$ = hdr$ + padded$
@padLeft: "slot", 5
hdr$ = hdr$ + padded$
@padLeft: "prop", 9
hdr$ = hdr$ + padded$
@padLeft: "start(s)", 12
hdr$ = hdr$ + padded$
@padLeft: "dur(ms)", 10
hdr$ = hdr$ + padded$
@padLeft: "samples", 9
hdr$ = hdr$ + padded$
@padLeft: "type", 7
hdr$ = hdr$ + padded$
@padLeft: "src(s)", 9
hdr$ = hdr$ + padded$
appendInfoLine: hdr$
maxRows = 96
shown = min (nLeaf, maxRows)
for k to shown
    typ$ = "note"
    if leafProp [k] < 0
        typ$ = "rest"
    endif
    srcTxt$ = "-"
    if leafOffUsed [k] <> undefined
        srcTxt$ = fixed$ (leafOffUsed [k], 4)
    endif
    row$ = ""
    @padLeft: string$ (k), 4
    row$ = row$ + padded$
    @padLeft: string$ (leafRep [k]), 5
    row$ = row$ + padded$
    @padLeft: string$ (leafSlot [k]), 5
    row$ = row$ + padded$
    @padLeft: fixed$ (leafProp [k], 3), 9
    row$ = row$ + padded$
    @padLeft: fixed$ (leafStart [k] * dt, 4), 12
    row$ = row$ + padded$
    @padLeft: fixed$ (leafTook [k] * dt * 1000, 2), 10
    row$ = row$ + padded$
    @padLeft: string$ (leafTook [k]), 9
    row$ = row$ + padded$
    @padLeft: typ$, 7
    row$ = row$ + padded$
    @padLeft: srcTxt$, 9
    row$ = row$ + padded$
    appendInfoLine: row$
endfor
if nLeaf > maxRows
    appendInfoLine: "  ... ", nLeaf - maxRows, " further leaves not listed"
endif
appendInfoLine: ""
appendInfoLine: "==================================================================="
# ----------------------------------------------------------------------------
# STEP 11 -- visualization
# Drawing-frame rule: Text: and Draw inner box both leave the frame on the OUTER
# viewport, and a following Axes: does NOT restore the inner one.  Every group
# therefore re-issues Select inner viewport + Axes before drawing.
# Panel captions use Text top: so they sit above the box instead of over the
# data; no intermediate panel draws bottom numbers, so nothing collides.
# ----------------------------------------------------------------------------
if draw_visualization = 1

    dispName$ = replace$ (srcName$, "_", "\_ ", 0)
    dispOut$ = replace$ (outName$, "_", "\_ ", 0)
    dispProps$ = replace$ (proportions$, "_", "\_ ", 0)
    dispSub$ = replace$ (subst_proportions$, "_", "\_ ", 0)
    dispTrans$ = transformation$

    # panel geometry (8 in wide canvas, 0.6 / 7.7 inner margins)
    panelAy1 = 1.05
    panelAy2 = 2.00
    panelBy1 = 2.60
    panelBy2 = 3.55
    panelCy1 = 4.25
    panelCy2 = 5.60
    panelDy1 = 6.30
    panelDy2 = 8.40

    Erase all
    Line width: 1
    Colour: {0.00, 0.00, 0.00}

    # A full-canvas background must use Select INNER viewport: with the outer
    # viewport Praat's standard margins are left unpainted.
    Select inner viewport: 0, 8, 0, 8.6
    Axes: 0, 1, 0, 1
    Paint rectangle: {1.00, 1.00, 1.00}, 0, 1, 0, 1

    # ---- suite header ------------------------------------------------------
    Select inner viewport: 0.60, 7.70, 0.15, 0.62
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##OM Rhythm Tree Slicer v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.20, "half", dispTrans$ + " | " + dispName$ + " | " + string$ (numerator) + "/" + string$ (denominator)
    ... + " @ " + fixed$ (tempo_BPM, 1) + " BPM | measure " + fixed$ (measureDur, 3) + " s | x"
    ... + string$ (repetitions) + " | output " + fixed$ (outDur, 3) + " s"

    # ---- panel A : input tree, one measure, proportional units -------------
    Select inner viewport: 0.6, 7.7, panelAy1, panelAy2
    Axes: 0, 1, 0, 1
    Paint rectangle: {0.99, 0.99, 0.99}, 0, 1, 0, 1

    cumA = 0
    for k to nProp
        xa0 = cumA / sumAbs
        cumA = cumA + abs (prop [k])
        xa1 = cumA / sumAbs
        Select inner viewport: 0.6, 7.7, panelAy1, panelAy2
        Axes: 0, 1, 0, 1
        if prop [k] > 0
            Paint rectangle: {0.20, 0.40, 0.80}, xa0, xa1, 0.48, 0.86
        else
            Paint rectangle: {0.84, 0.84, 0.84}, xa0, xa1, 0.48, 0.86
        endif
        Colour: {1.00, 1.00, 1.00}
        Line width: 1
        Draw rectangle: xa0, xa1, 0.48, 0.86
    endfor

    # beat ruler under the blocks
    Select inner viewport: 0.6, 7.7, panelAy1, panelAy2
    Axes: 0, 1, 0, 1
    Colour: {0.45, 0.45, 0.45}
    Draw line: 0, 0.24, 1, 0.24
    for bnum from 0 to numerator
        xb = bnum / numerator
        Draw line: xb, 0.14, xb, 0.24
    endfor

    Select inner viewport: 0.6, 7.7, panelAy1, panelAy2
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: {0.45, 0.45, 0.45}
    for bnum to numerator
        xb = (bnum - 0.5) / numerator
        Text: xb, "centre", 0.08, "half", "beat " + string$ (bnum)
    endfor

    Select inner viewport: 0.6, 7.7, panelAy1, panelAy2
    Axes: 0, 1, 0, 1
    Font size: 6
    cumA = 0
    for k to nProp
        xa0 = cumA / sumAbs
        cumA = cumA + abs (prop [k])
        xa1 = cumA / sumAbs
        Select inner viewport: 0.6, 7.7, panelAy1, panelAy2
        Axes: 0, 1, 0, 1
        if prop [k] > 0
            Colour: {1.00, 1.00, 1.00}
        else
            Colour: {0.45, 0.45, 0.45}
        endif
        Text: (xa0 + xa1) / 2, "centre", 0.62, "half", fixed$ (prop [k], 2)
    endfor

    Select inner viewport: 0.6, 7.7, panelAy1, panelAy2
    Axes: 0, 1, 0, 1
    Colour: {0.00, 0.00, 0.00}
    Draw inner box
    Select inner viewport: 0.6, 7.7, panelAy1, panelAy2
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: {0.20, 0.20, 0.20}
    Text top: "no", "##INPUT TREE##   one measure in proportional units      blue = sounding pulse      grey = rest"

    # ---- panel B : transformed tree over the whole output ------------------
    Select inner viewport: 0.6, 7.7, panelBy1, panelBy2
    Axes: 0, totalOutDur, 0, 1
    Paint rectangle: {0.99, 0.99, 0.99}, 0, totalOutDur, 0, 1

    for k to nLeaf
        xb0 = leafStart [k] * dt
        xb1 = xb0 + leafTook [k] * dt
        if xb1 > totalOutDur
            xb1 = totalOutDur
        endif
        Select inner viewport: 0.6, 7.7, panelBy1, panelBy2
        Axes: 0, totalOutDur, 0, 1
        if leafProp [k] > 0
            Paint rectangle: {0.20, 0.40, 0.80}, xb0, xb1, 0.46, 0.86
        else
            Paint rectangle: {0.84, 0.84, 0.84}, xb0, xb1, 0.46, 0.86
        endif
        Colour: {1.00, 1.00, 1.00}
        Draw rectangle: xb0, xb1, 0.46, 0.86
    endfor

    Select inner viewport: 0.6, 7.7, panelBy1, panelBy2
    Axes: 0, totalOutDur, 0, 1
    Colour: {0.75, 0.20, 0.20}
    Line width: 2
    for r to repetitions - 1
        xm = r * measureSamples * dt
        Draw line: xm, 0.28, xm, 0.94
    endfor
    Line width: 1

    Select inner viewport: 0.6, 7.7, panelBy1, panelBy2
    Axes: 0, totalOutDur, 0, 1
    Font size: 6
    Colour: {0.55, 0.15, 0.15}
    for r to repetitions
        xm = (r - 0.5) * measureSamples * dt
        Text: xm, "centre", 0.18, "half", "measure " + string$ (r)
    endfor

    Select inner viewport: 0.6, 7.7, panelBy1, panelBy2
    Axes: 0, totalOutDur, 0, 1
    Colour: {0.00, 0.00, 0.00}
    Draw inner box
    Select inner viewport: 0.6, 7.7, panelBy1, panelBy2
    Axes: 0, totalOutDur, 0, 1
    Font size: 7
    Colour: {0.20, 0.20, 0.20}
    Text top: "no", "##TRANSFORMED TREE##   output timeline, " + string$ (nLeaf) + " leaves, red = barline"

    # ---- panel C : output waveform -----------------------------------------
    # A round axis range so Marks left every gives readable numbers, and an
    # explicit range passed to Draw: so the overlay lines land where they should
    # (Draw: 0,0,0,0 would autoscale and break plot-audio agreement).
    drawRange = finalPeak * 1.05
    if drawRange <= 0
        drawRange = 1
    endif
    # Marks left every: places marks AT the axis extremes if the step comes from
    # the range itself, which prints values like 0.6284.  Pick a ROUND step of
    # roughly a third of the range instead and let the marks fall where they may.
    markTarget = drawRange / 3
    markDecade = 10 ^ floor (log10 (markTarget))
    markRatio = markTarget / markDecade
    if markRatio < 1.5
        markStep = markDecade
    elsif markRatio < 3.5
        markStep = 2 * markDecade
    elsif markRatio < 7.5
        markStep = 5 * markDecade
    else
        markStep = 10 * markDecade
    endif

    Select inner viewport: 0.6, 7.7, panelCy1, panelCy2
    selectObject: outId
    Colour: {0.15, 0.45, 0.60}
    Line width: 1
    Draw: 0, 0, -drawRange, drawRange, "no", "Curve"

    Select inner viewport: 0.6, 7.7, panelCy1, panelCy2
    Axes: 0, outDur, -drawRange, drawRange
    Colour: {0.60, 0.60, 0.60}
    for k to nLeaf
        xc = leafStart [k] * dt
        if xc > 0 and xc < outDur
            Draw line: xc, -drawRange * 0.55, xc, drawRange * 0.55
        endif
    endfor

    Select inner viewport: 0.6, 7.7, panelCy1, panelCy2
    Axes: 0, outDur, -drawRange, drawRange
    Colour: {0.75, 0.20, 0.20}
    Line width: 2
    for r to repetitions - 1
        xm = r * measureSamples * dt
        if xm < outDur
            Draw line: xm, -drawRange, xm, drawRange
        endif
    endfor
    Line width: 1

    Select inner viewport: 0.6, 7.7, panelCy1, panelCy2
    Axes: 0, outDur, -drawRange, drawRange
    Colour: {0.00, 0.00, 0.00}
    Draw inner box
    Select inner viewport: 0.6, 7.7, panelCy1, panelCy2
    Axes: 0, outDur, -drawRange, drawRange
    Font size: 6
    tickStep = 0.25
    if outDur > 60
        tickStep = 10
    elsif outDur > 24
        tickStep = 5
    elsif outDur > 12
        tickStep = 2
    elsif outDur > 6
        tickStep = 1
    elsif outDur > 3
        tickStep = 0.5
    endif
    Marks bottom every: 1, tickStep, "yes", "yes", "no"
    Marks left every: 1, markStep, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "time (s)"
    Select inner viewport: 0.6, 7.7, panelCy1, panelCy2
    Axes: 0, outDur, -drawRange, drawRange
    Colour: {0.20, 0.20, 0.20}
    Text top: "no", "##OUTPUT WAVEFORM##   grey = leaf boundary, red = barline"

    # ---- panel D : summary --------------------------------------------------
    Select inner viewport: 0.6, 7.7, panelDy1, panelDy2
    Axes: 0, 1, 0, 1
    Paint rectangle: {0.94, 0.94, 0.94}, 0, 1, 0, 1

    Select inner viewport: 0.6, 7.7, panelDy1, panelDy2
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: {0.15, 0.15, 0.15}

    # Count the rows FIRST and derive the step, otherwise the optional rows
    # (substitution, all-rests warning, preset) push the footer through the
    # bottom border of the panel.
    sumRows = 10
    if transformation$ = "subst-rhythm"
        sumRows = sumRows + 1
    endif
    if nSounding = 0
        sumRows = sumRows + 1
    endif
    if presetApplied$ <> "none"
        sumRows = sumRows + 1
    endif
    rowStep = 0.90 / sumRows
    sumRow = 0.95 - rowStep / 2

    Text: 0.02, "left", sumRow, "half", "##SUMMARY##"
    sumRow = sumRow - rowStep
    Text: 0.02, "left", sumRow, "half", "Transformation: " + dispTrans$
    ... + "      rotation steps: " + string$ (rotation_steps)
    ... + "      progressive: " + if progressive_rotation = 1 then "yes" else "no" fi
    sumRow = sumRow - rowStep
    Text: 0.02, "left", sumRow, "half", "Input tree: " + dispProps$
    ... + "      leaves in: " + string$ (nProp) + "      leaves out per measure: " + string$ (nTfirst)
    sumRow = sumRow - rowStep
    if transformation$ = "subst-rhythm"
        Text: 0.02, "left", sumRow, "half", "Substitution: leaf " + string$ (substTarget) + " -> " + dispSub$
        ... + "      children: " + string$ (nSub)
        sumRow = sumRow - rowStep
    endif
    Text: 0.02, "left", sumRow, "half", "Metre: " + string$ (numerator) + "/" + string$ (denominator)
    ... + " at " + fixed$ (tempo_BPM, 1) + " BPM      measure = " + fixed$ (measureDur, 4) + " s ("
    ... + string$ (measureSamples) + " samples)      repetitions: " + string$ (repetitions)
    sumRow = sumRow - rowStep
    Text: 0.02, "left", sumRow, "half", "Leaves: " + string$ (nLeaf) + " total, "
    ... + string$ (nSounding) + " sounding, " + string$ (nRests) + " rests"
    ... + "      temporary objects created and removed: " + string$ (nObj)
    sumRow = sumRow - rowStep
    Text: 0.02, "left", sumRow, "half", "Material: " + material_mapping$
    ... + "      follows transform: " + if material_follows_transform = 1 then "yes" else "no" fi
    ... + "      pulled-back reads: " + string$ (nPulledBack)
    ... + "      zero-padded: " + string$ (nZeroPadded)
    sumRow = sumRow - rowStep
    Text: 0.02, "left", sumRow, "half", "Edge fade: " + fixed$ (fade_ms, 2)
    ... + " ms raised cosine, butt-joined; policy: "
    ... + if fade_only_discontinuities = 1 then "discontinuities only" else "every slice" fi
    ... + "      clamped on " + string$ (nFadeClamped) + " slice(s)"
    sumRow = sumRow - rowStep
    Text: 0.02, "left", sumRow, "half", "Length: requested " + fixed$ (totalOutDur, 5)
    ... + " s / achieved " + fixed$ (outDur, 5) + " s      drift " + string$ (driftSamples)
    ... + " samples (" + fixed$ (driftSamples * dt * 1000, 3) + " ms)"
    sumRow = sumRow - rowStep
    Text: 0.02, "left", sumRow, "half", "Level: " + normalization$
    ... + "      peak " + fixed$ (rawPeak, 4) + " -> " + fixed$ (finalPeak, 4)
    ... + " (gain x " + fixed$ (gainApplied, 4) + ")"
    ... + "      channels preserved: " + string$ (srcChannels)
    sumRow = sumRow - rowStep
    if nSounding = 0
        Colour: {0.65, 0.15, 0.15}
        Text: 0.02, "left", sumRow, "half", "WARNING: every leaf is a rest -- the output is pure silence."
        Colour: {0.15, 0.15, 0.15}
        sumRow = sumRow - rowStep
    endif
    if presetApplied$ <> "none"
        Text: 0.02, "left", sumRow, "half", "Preset: " + presetApplied$
        ... + "   (metre, proportions, transformation, rotation, substitution, repetitions, mapping)"
        sumRow = sumRow - rowStep
    endif
    Colour: {0.40, 0.40, 0.40}
    Font size: 6
    Text: 0.02, "left", sumRow, "half", "Praat AudioTools -- OM Rhythm Tree Slicer v0.4      output object: " + dispOut$

    Select inner viewport: 0.6, 7.7, panelDy1, panelDy2
    Axes: 0, 1, 0, 1
    Colour: {0.00, 0.00, 0.00}
    Draw inner box

    # leave the whole figure selected, so Save as... / Copy from the Picture
    # window exports the complete canvas rather than the last panel drawn
    Select outer viewport: 0, 8, 0, 8.6
    Colour: {0.00, 0.00, 0.00}
    Font size: 10
    Line width: 1
    # Restore complete page for Picture export / clipboard.
    pageHeight = 8.75
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

selectObject: outId

if play_result
    appendInfoLine: "Playing..."
    Play
endif
