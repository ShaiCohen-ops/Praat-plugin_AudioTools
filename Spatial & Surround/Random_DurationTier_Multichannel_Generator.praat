# ============================================================
# Praat AudioTools - Random_DurationTier_Multichannel_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel time-stretching generator. Builds N random-walk
#   DurationTiers, applies each to a Manipulation copy of the
#   source via PSOLA resynthesis, and combines the N results
#   into one multichannel Sound. Each channel hears the source
#   with a different time-warping pattern.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - Fix (visualization): the duration-tier panel was empty by
#     default. v0.3 cleaned up the tiers BEFORE drawing, and the
#     drawing loop was guarded by `if keep_duration_tiers` — so
#     unless that toggle was on, the headline panel showed only
#     a unity line. Visualization now runs before cleanup, and
#     the `if keep_duration_tiers` guard inside the drawing
#     loop is removed.
#   - Visualization rewritten to suite 8x8 standard
#     (matching 22.2 Stem Renderer, 8-ch I Ching, 8-ch Movements,
#     4-ch Canon, 8-ch Spectral Shift, 8-ch Speed Deviations,
#     8-ch Speech-Driven Spatialization, etc.).
#     Panels:
#       A: All N duration-tier curves overlaid (headline).
#       B: Stretch-factor histogram across all tiers (shows
#          whether random walks are uniform across the range
#          or piling up at the boundaries).
#       C: Per-channel resulting-duration bar chart (lets you
#          see at a glance which channel ended up longest /
#          shortest after time-stretching).
#       D: Output multichannel waveform (Ch1 blue, Ch2 orange).
#       E: Summary stats bar with target variability vs achieved.
#   - NEW: Boundary_handling form parameter. Default is Clamp
#     (matches v0.3, all existing presets sound the same).
#     Reflect bounces the walk off boundaries; Reject re-rolls
#     the step until it stays in bounds. Reflect/Reject produce
#     more even distributions across the [min, max] range,
#     while Clamp tends to pile up at the boundaries on
#     aggressive settings.
#   - Modernized: tierId_'k' / resId_'k' dynamic-name pattern
#     replaced with proper indexed arrays tierId[k] / resId[k].
#     Pure style; matches the rest of the suite.
#   - Removed redundant Colour: setting before Paint rectangle
#     (Paint rectangle takes its own color argument).
# Changelog v0.3:
#   - Fixed critical bug: single channel output was deleted during cleanup
#   - Fixed multichannel combining for 3+ channels
#   - Added visualization option
#   - Added option to keep DurationTiers
# ============================================================

# ---- Require exactly one input Sound selected ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound before running this script."
endif
orig = selected("Sound")
origName$ = selected$("Sound")

# Domain for tiers
tmin = Get start time
tmax = Get end time
totalDur = tmax - tmin

form Random DurationTier Multichannel Generator v0.4
    comment ==== Presets ====
    optionmenu Preset: 1
        option Custom
        option Subtle Variations (4ch gentle)
        option Standard Multi-texture (8ch moderate)
        option Extreme Time-stretch (8ch wild)
        option Dense Polyrhythm (12ch complex)
        option Minimal Duo (2ch subtle)
        option Chaotic Cluster (16ch maximum)
    comment ==== Channel Settings ====
    integer Number_of_channels 8
    comment ==== Duration Variation ====
    integer Control_points 10
    positive Variability 0.40
    positive Min_factor 0.50
    positive Max_factor 2.00
    optionmenu Boundary_handling: 1
        option Clamp (matches v0.3 — piles up at edges)
        option Reflect (bounces off boundaries)
        option Reject (re-roll step if it would exceed bounds)
    comment ==== Pitch Analysis ====
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Time_step 0.01
    comment ==== Output Options ====
    word Name_prefix DurRand_
    word Output_stem dur8
    positive Scale_peak 0.99
    boolean Keep_duration_tiers 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply preset values if not Custom
if preset = 2
    number_of_channels = 4
    control_points = 8
    variability = 0.20
    min_factor = 0.80
    max_factor = 1.25
elsif preset = 3
    number_of_channels = 8
    control_points = 10
    variability = 0.40
    min_factor = 0.50
    max_factor = 2.00
elsif preset = 4
    number_of_channels = 8
    control_points = 15
    variability = 0.60
    min_factor = 0.25
    max_factor = 4.00
elsif preset = 5
    number_of_channels = 12
    control_points = 20
    variability = 0.50
    min_factor = 0.40
    max_factor = 2.50
elsif preset = 6
    number_of_channels = 2
    control_points = 6
    variability = 0.25
    min_factor = 0.70
    max_factor = 1.50
elsif preset = 7
    number_of_channels = 16
    control_points = 25
    variability = 0.70
    min_factor = 0.20
    max_factor = 5.00
endif

# Resolve preset name and boundary handling name for display
if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "SubtleVariations"
elsif preset = 3
    presetName$ = "StandardMultitexture"
elsif preset = 4
    presetName$ = "ExtremeTimeStretch"
elsif preset = 5
    presetName$ = "DensePolyrhythm"
elsif preset = 6
    presetName$ = "MinimalDuo"
else
    presetName$ = "ChaoticCluster"
endif

if boundary_handling = 1
    boundaryName$ = "Clamp"
elsif boundary_handling = 2
    boundaryName$ = "Reflect"
else
    boundaryName$ = "Reject"
endif

# Shorthand variables
nTiers = number_of_channels
nPts = control_points

writeInfoLine: "=== Random DurationTier Multichannel Generator v0.4 ==="
appendInfoLine: "Processing: ", origName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(totalDur, 3), " s"
appendInfoLine: "Number of channels: ", nTiers
appendInfoLine: "Control points per channel: ", nPts
appendInfoLine: "Variability: ", fixed$(variability, 2)
appendInfoLine: "Range: ", fixed$(min_factor, 2), " to ", fixed$(max_factor, 2)
appendInfoLine: "Boundary handling: ", boundaryName$
appendInfoLine: ""

# Random-walk step sigma
# For a walk of N steps with step variance σ², total variance is N×σ².
# Setting σ = variability/sqrt(N) gives total variance = variability².
stepSigma = variability / sqrt(nPts)

# ============================================================
# CREATE DURATION TIERS  (one per channel)
# ============================================================

appendInfoLine: "Creating ", nTiers, " duration tiers..."

# Indexed arrays for tier IDs and per-tier statistics
# (statistics used for visualization Panel B histogram)
tierId# = zero# (nTiers)
allFactors# = zero# (nTiers * (nPts + 2))
nFactorsTotal = 0

for k from 1 to nTiers
    tierName$ = name_prefix$ + string$(k)
    Create DurationTier: tierName$, tmin, tmax
    
    # Start at unity
    Add point: tmin, 1.0
    nFactorsTotal = nFactorsTotal + 1
    allFactors#[nFactorsTotal] = 1.0
    
    # Random walk for interior points
    state = 1.0
    for j from 1 to nPts
        time = tmin + j * (tmax - tmin) / (nPts + 1)
        
        # Generate next state per chosen boundary handling
        if boundary_handling = 1
            # Clamp: take step, then clamp to bounds (v0.3 behavior)
            step = randomGauss(0, stepSigma)
            state = state + step
            if state < min_factor
                state = min_factor
            endif
            if state > max_factor
                state = max_factor
            endif
        elsif boundary_handling = 2
            # Reflect: take step, bounce off bounds (may need multiple
            # bounces if step is huge relative to range)
            step = randomGauss(0, stepSigma)
            newState = state + step
            # Iterative reflection in case the step overshoots both walls
            iter = 0
            while (newState < min_factor or newState > max_factor) and iter < 10
                if newState < min_factor
                    newState = 2 * min_factor - newState
                endif
                if newState > max_factor
                    newState = 2 * max_factor - newState
                endif
                iter = iter + 1
            endwhile
            # If still out of bounds after 10 bounces (extreme step), clamp
            if newState < min_factor
                newState = min_factor
            endif
            if newState > max_factor
                newState = max_factor
            endif
            state = newState
        else
            # Reject: re-roll step if it would exceed bounds
            tries = 0
            accepted = 0
            while accepted = 0 and tries < 20
                step = randomGauss(0, stepSigma)
                trialState = state + step
                if trialState >= min_factor and trialState <= max_factor
                    state = trialState
                    accepted = 1
                endif
                tries = tries + 1
            endwhile
            # If 20 rejections, fall through to clamp (very rare)
            if accepted = 0
                state = state + randomGauss(0, stepSigma)
                if state < min_factor
                    state = min_factor
                endif
                if state > max_factor
                    state = max_factor
                endif
            endif
        endif
        
        Add point: time, state
        nFactorsTotal = nFactorsTotal + 1
        allFactors#[nFactorsTotal] = state
    endfor
    
    # End at unity
    Add point: tmax, 1.0
    nFactorsTotal = nFactorsTotal + 1
    allFactors#[nFactorsTotal] = 1.0
    
    tierId#[k] = selected("DurationTier")
endfor

# ============================================================
# GENERATE TIME-STRETCHED VARIANTS
# ============================================================

appendInfoLine: "Generating ", nTiers, " time-stretched variants..."

resId# = zero# (nTiers)
resDur# = zero# (nTiers)

for k from 1 to nTiers
    selectObject: orig
    To Manipulation: time_step, pitch_floor, pitch_ceiling
    man = selected("Manipulation")
    
    selectObject: man
    plusObject: tierId#[k]
    Replace duration tier
    
    selectObject: man
    Get resynthesis (overlap-add)
    Rename: output_stem$ + "_var" + string$(k)
    resId#[k] = selected("Sound")
    
    # Capture resulting duration for Panel C
    resDur#[k] = Get total duration
    
    selectObject: man
    Remove
    
    if k mod 4 = 0 or k = nTiers
        appendInfoLine: "  Processed ", k, " / ", nTiers, " channels..."
    endif
endfor

# ============================================================
# COMBINE TO MULTICHANNEL
# ============================================================

appendInfoLine: ""
appendInfoLine: "Combining channels..."

if nTiers = 1
    selectObject: resId#[1]
    Copy: output_stem$ + "_1ch"
    multiChannelSound = selected("Sound")
elsif nTiers = 2
    selectObject: resId#[1]
    plusObject: resId#[2]
    Combine to stereo
    Rename: output_stem$ + "_2ch"
    multiChannelSound = selected("Sound")
else
    # 3+ channels - iterative combining
    selectObject: resId#[1]
    plusObject: resId#[2]
    Combine to stereo
    combined = selected("Sound")
    
    for k from 3 to nTiers
        selectObject: combined
        plusObject: resId#[k]
        Combine to stereo
        newCombined = selected("Sound")
        selectObject: combined
        Remove
        combined = newCombined
    endfor
    
    selectObject: combined
    Rename: output_stem$ + "_" + string$(nTiers) + "ch"
    multiChannelSound = selected("Sound")
endif

selectObject: multiChannelSound
Scale peak: scale_peak
finalName$ = selected$("Sound")
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# COMPUTE ACHIEVED STATISTICS  (for summary bar)
# ============================================================

# Achieved variance over all factor samples (excluding tmin/tmax anchors
# which are always exactly 1.0). The "interior" stats are what the user
# actually asked for via variability.
sumF = 0
sumF2 = 0
nInterior = 0
for k from 1 to nTiers
    # Each tier contributes (nPts + 2) factors; first and last are 1.0 anchors
    baseIdx = (k - 1) * (nPts + 2)
    for p from 2 to nPts + 1
        f = allFactors#[baseIdx + p]
        sumF = sumF + f
        sumF2 = sumF2 + f * f
        nInterior = nInterior + 1
    endfor
endfor

if nInterior > 0
    meanF = sumF / nInterior
    varF = (sumF2 / nInterior) - meanF * meanF
    if varF < 0
        varF = 0
    endif
    achievedSD = sqrt(varF)
else
    meanF = 1.0
    achievedSD = 0
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Drawn BEFORE cleanup so tiers are still alive.
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##RANDOM DURATION-TIER MULTICHANNEL GENERATOR##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... origName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Channels: " + string$(nTiers)
        ... + "  |  Pts: " + string$(nPts)
        ... + "  |  Var: " + fixed$(variability, 2)
        ... + "  |  Range: " + fixed$(min_factor, 2) + "-" + fixed$(max_factor, 2)
        ... + "  |  " + boundaryName$
    
    # ----------------------------------------------------------
    # PANEL A: ALL DURATION-TIER CURVES OVERLAID  (left, headline)
    # Each tier in its own color, color-graded by channel index.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.45
    
    yMin = min_factor * 0.92
    yMax = max_factor * 1.08
    
    Axes: tmin, tmax, yMin, yMax
    Paint rectangle: "{0.96, 0.96, 0.96}", tmin, tmax, yMin, yMax
    
    # Light horizontal grid at every 0.5 factor
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    gv = ceiling(yMin * 2) / 2
    while gv <= yMax
        Draw line: tmin, gv, tmax, gv
        gv = gv + 0.5
    endwhile
    
    # Unity line (factor = 1.0, no stretch)
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Line width: 1.5
    Draw line: tmin, 1.0, tmax, 1.0
    Solid line
    Line width: 1
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: tmax * 0.99, "right", 1.0, "bottom", "1.0 (no stretch)"
    
    # Min and max factor reference lines
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: tmin, min_factor, tmax, min_factor
    Draw line: tmin, max_factor, tmax, max_factor
    Solid line
    Font size: 5
    Colour: "{0.55, 0.30, 0.55}"
    Text: tmin * 0.01 + tmax * 0.99, "right", min_factor, "bottom", "min " + fixed$(min_factor, 2)
    Text: tmin * 0.01 + tmax * 0.99, "right", max_factor, "top", "max " + fixed$(max_factor, 2)
    
    # Tier curves — use proper rainbow with HSV-style mapping
    Line width: 1.3
    for k from 1 to nTiers
        # Color from a perceptual gradient: warm at low k, cool at high k
        progress = (k - 1) / max(1, nTiers - 1)
        # Cool-warm diverging through green-yellow-red:
        if progress < 0.5
            t = progress * 2
            cR = 0.20 + t * 0.55
            cG = 0.45 + t * 0.30
            cB = 0.80 - t * 0.45
        else
            t = (progress - 0.5) * 2
            cR = 0.75 + t * 0.15
            if cR > 1
                cR = 1
            endif
            cG = 0.75 - t * 0.45
            cB = 0.35 - t * 0.20
            if cB < 0
                cB = 0
            endif
        endif
        rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
        Colour: rgb$
        
        selectObject: tierId#[k]
        nPoints = Get number of points
        for p from 2 to nPoints
            t1 = Get time from index: p - 1
            v1 = Get value at index: p - 1
            t2 = Get time from index: p
            v2 = Get value at index: p
            Draw line: t1, v1, t2, v2
        endfor
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Time-stretch factor"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: STRETCH-FACTOR HISTOGRAM  (right, upper)
    # Shows distribution of all factor values across all tiers.
    # If Clamp is active, you'll see piles at min_factor and max_factor.
    # If Reflect/Reject is active, distribution is more even.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
    nBins = 24
    bins# = zero# (nBins)
    binW = (max_factor - min_factor) / nBins
    if binW < 0.0001
        binW = 0.0001
    endif
    
    # Use only interior points (anchors are always 1.0 and would dominate)
    for k from 1 to nTiers
        baseIdx = (k - 1) * (nPts + 2)
        for p from 2 to nPts + 1
            f = allFactors#[baseIdx + p]
            bIdx = floor((f - min_factor) / binW) + 1
            if bIdx < 1
                bIdx = 1
            endif
            if bIdx > nBins
                bIdx = nBins
            endif
            bins#[bIdx] = bins#[bIdx] + 1
        endfor
    endfor
    
    binMax = 1
    for b from 1 to nBins
        if bins#[b] > binMax
            binMax = bins#[b]
        endif
    endfor
    
    Axes: min_factor, max_factor, 0, binMax * 1.1
    Paint rectangle: "{0.96, 0.96, 0.96}", min_factor, max_factor, 0, binMax * 1.1
    
    # Unity reference (where 1.0 sits in the range)
    if 1.0 >= min_factor and 1.0 <= max_factor
        Colour: "{0.55, 0.55, 0.55}"
        Dotted line
        Draw line: 1.0, 0, 1.0, binMax * 1.1
        Solid line
    endif
    
    # Histogram bars
    Colour: "{0.45, 0.55, 0.78}"
    for b from 1 to nBins
        if bins#[b] > 0
            xL = min_factor + (b - 1) * binW
            xR = xL + binW * 0.92
            Paint rectangle: "{0.45, 0.55, 0.78}", xL, xR, 0, bins#[b]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Count"
    Text bottom: "yes", "Stretch factor"
    
    # ----------------------------------------------------------
    # PANEL C: PER-CHANNEL RESULTING DURATIONS  (right, lower)
    # Shows the actual stretched duration of each output channel.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.18, 4.50
    
    # Find duration extremes
    dMin = resDur#[1]
    dMax = resDur#[1]
    for k from 2 to nTiers
        if resDur#[k] < dMin
            dMin = resDur#[k]
        endif
        if resDur#[k] > dMax
            dMax = resDur#[k]
        endif
    endfor
    dPad = (dMax - dMin) * 0.10
    if dPad < 0.05
        dPad = 0.05
    endif
    yLo = 0
    yHi = dMax + dPad
    
    Axes: 0.5, nTiers + 0.5, yLo, yHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.5, nTiers + 0.5, yLo, yHi
    
    # Original-duration reference line
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Line width: 1.5
    Draw line: 0.5, totalDur, nTiers + 0.5, totalDur
    Solid line
    Line width: 1
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: nTiers + 0.45, "right", totalDur, "bottom", "orig " + fixed$(totalDur, 2) + "s"
    
    # Per-channel bars, colored to match Panel A
    for k from 1 to nTiers
        progress = (k - 1) / max(1, nTiers - 1)
        if progress < 0.5
            t = progress * 2
            cR = 0.20 + t * 0.55
            cG = 0.45 + t * 0.30
            cB = 0.80 - t * 0.45
        else
            t = (progress - 0.5) * 2
            cR = 0.75 + t * 0.15
            if cR > 1
                cR = 1
            endif
            cG = 0.75 - t * 0.45
            cB = 0.35 - t * 0.20
            if cB < 0
                cB = 0
            endif
        endif
        rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
        
        Paint rectangle: rgb$, k - 0.38, k + 0.38, 0, resDur#[k]
        
        # Channel index label
        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        if nTiers <= 12
            Text: k, "centre", -yHi * 0.04, "half", string$(k)
        elsif k mod 2 = 1
            Text: k, "centre", -yHi * 0.04, "half", string$(k)
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Duration (s)"
    Text bottom: "yes", "Channel"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.20, "centre", 7.30, "half", "Random-walk duration tiers (one curve per channel)"
    Text: 6.10, "centre", 7.30, "half", "Factor distribution (upper) & per-channel duration (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: multiChannelSound
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    if nResultCh = 1
        selectObject: multiChannelSound
        Colour: "{0.20, 0.55, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        selectObject: multiChannelSound
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if nResultCh >= 2
            selectObject: multiChannelSound
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        Text top: "no", "Output  (blue=Ch1  orange=Ch2 of " + string$(nResultCh) + ")"
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + origName$
        ... + "  |  " + string$(nTiers) + " channels"
        ... + "  |  " + string$(nPts) + " control points each"
        ... + "  |  Boundary: " + boundaryName$
        ... + "  |  Pitch: " + fixed$(pitch_floor, 0) + "-" + fixed$(pitch_ceiling, 0) + " Hz"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Variability target: " + fixed$(variability, 2)
        ... + "  |  Achieved std-dev: " + fixed$(achievedSD, 3)
        ... + "  |  Mean factor: " + fixed$(meanF, 3)
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s"
        ... + "  |  Peak: " + fixed$(finalPeak, 3)
        ... + "  |  Tiers stored: " + string$(nFactorsTotal)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP  (now after visualization)
# ============================================================

# Remove variant sounds (they've been combined)
for k from 1 to nTiers
    selectObject: resId#[k]
    Remove
endfor

# Remove or keep duration tiers
if keep_duration_tiers
    appendInfoLine: "Duration tiers kept in Objects list"
else
    for k from 1 to nTiers
        selectObject: tierId#[k]
        Remove
    endfor
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: multiChannelSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Original: ", origName$
appendInfoLine: "Result: ", finalName$
appendInfoLine: "Channels: ", nTiers
appendInfoLine: "Boundary handling: ", boundaryName$
appendInfoLine: "Variability target: ", fixed$(variability, 3),
    ... "    Achieved std-dev: ", fixed$(achievedSD, 3)
appendInfoLine: "Peak: ", fixed$(scale_peak, 2)
if keep_duration_tiers
    appendInfoLine: "Duration tiers: kept (", nTiers, " tiers)"
endif
appendInfoLine: ""

if play_result
    selectObject: multiChannelSound
    Play
endif
