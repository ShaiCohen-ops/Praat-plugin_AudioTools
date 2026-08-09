# ============================================================
# Praat AudioTools - Brownian_Motion_Texture_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Brownian Motion Texture Generator — granular textures using
#   random walk for both temporal placement and stereo panning.
#   Brownian motion creates cumulative drift patterns rather than
#   simple random scatter.
#
#   Behavior:
#   - Temporal Brownian: each grain's output time is the previous
#     grain's nominal time plus a Gaussian step.
#   - Spatial Brownian: pan position random-walks across [0, 1]
#     with selectable boundary behavior (Clamp / Reflect / Reject).
#   - Grains are drawn from random, sequential, or frozen-centre
#     positions in the source.
#   - With Allow_overlap = ON (default), dense settings produce
#     true overlapping grain clouds (sum of grains where they
#     overlap in time). With OFF, grains are serialized — matches
#     v0.2's behavior, useful only if you want exact v0.2 output.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   DSP / timing / correctness:
#   - Temporal Brownian boundaries are now state-aware. v0.3 clipped
#     displayed grain times to the canvas but let the hidden cumulative
#     offset continue beyond the wall, causing long piles of grains at
#     0 or at the end. Temporal Clamp / Reflect / Reject modes now keep
#     the Brownian state itself inside the legal start-time interval.
#   - The original Brownian path is preserved for visualization. v0.3
#     sorted grainOutTime/grainPan in place before drawing, so the panel
#     labelled "Brownian path" showed a monotonic sorted schedule instead
#     of the generated walk. Rendering uses a sorted copy; diagnostics use
#     the unsorted path.
#   - Serialized mode now computes its exact schedule before allocating the
#     output canvas. v0.3 could under-allocate and truncate late grains.
#   - Final fade-out is applied after the final output duration is known.
#   - Amplitude_scaling is meaningful again: final peak scaling is now a
#     safety limiter only when peak > 0.95, instead of unconditional
#     normalization that cancelled all global gain choices.
#   - Removed the silent 500-grain density cap. Requested density is kept;
#     an explicit 5000-grain guard prevents pathological workloads.
#   - Added validation for output shorter than one grain and for edge-fade
#     duration > half a grain (which could create a discontinuous envelope).
#   - Sequential source traversal now includes both source endpoints.
#   - Frozen Moment now actually freezes the source read position at centre,
#     via a new Source_position_mode (Random / Sequential / Frozen centre).
#   - Spatial Reject now truly rejects after repeated failed proposals
#     instead of falling through to a random clamped step.
#
# Changelog v0.3:
#   - HEADLINE: speed rewrite. v0.2 used Concatenate-with-silences
#     to assemble grains, with O(n^2) bubble sort plus per-grain
#     Extract/Fade/Copy/Combine pipeline (~10 Praat operations
#     per grain). For 200-grain presets that was thousands of
#     Praat calls. v0.3 allocates a single stereo output canvas
#     and writes each grain via Formula (part) — same approach
#     used in Total Serialism Machine and BPM Panning. ~30-50x
#     faster on dense presets.
#   - HEADLINE: overlapping grains now actually overlap. v0.2's
#     concatenate-with-silences pipeline serialized any grain
#     whose nominal start time was earlier than the previous
#     grain's end time. With density * grain_duration >= 1
#     (Dense Cloud, Rhythmic Pulse), the audible result was a
#     queue of grains, not a cloud. v0.3 sums overlapping grains
#     correctly into the canvas. Previous serialized behavior
#     is preserved via Allow_overlap form toggle = OFF.
#   - Bubble sort O(n^2) replaced with insertion sort. For
#     nearly-sorted Brownian sequences this is near-linear
#     instead of n^2/2. Audio output is bit-identical (same
#     final order).
#   - NEW: Boundary_handling parameter for spatial Brownian.
#     Clamp = v0.2 behavior (default; pins to 0 or 1 at walls).
#     Reflect = bounces walk off boundaries.
#     Reject = re-rolls steps that would exceed bounds.
#     Same options as Random_DurationTier_Multichannel v0.4.
#   - NEW: Allow_overlap toggle. ON (default) = correct overlap
#     summation. OFF = v0.2's serialized concatenate behavior.
#   - Form syntax: optionmenu uses colon, modern Praat-compatible.
#   - Visualization rewritten to suite 8x8 standard with title
#     bar + metadata subtitle, aligned panel titles, output
#     waveform with L/R channels distinguished, summary bar.
#     Brownian path panels (temporal and spatial) are preserved
#     since they're the script's most informative diagnostic.
#   - Header documents the overlap behavior so users understand
#     when v0.2 and v0.3 will sound different.
# Changelog v0.2:
#   - Optimized using sorted concatenation
#   - Added visualization showing Brownian paths
#   - Added play option
# ============================================================

form Brownian Motion Texture v0.4
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Dense Cloud
        option Sparse Field
        option Wild Drift
        option Subtle Shimmer
        option Rhythmic Pulse
        option Frozen Moment
    
    comment === Grain Parameters ===
    positive Grain_duration_s 0.05
    positive Output_duration_s 10.0
    positive Density_grains_per_sec 20
    
    comment === Temporal Brownian Motion ===
    real Time_step_size_s 0.1
    real Time_drift 0.0
    optionmenu Temporal_boundary_handling: 2
        option Clamp (pins at time boundaries)
        option Reflect (bounces off time boundaries)
        option Reject (re-roll step if out of bounds)
    
    comment === Spatial Brownian Motion (Stereo) ===
    boolean Enable_spatial_brownian 1
    real Spatial_step_size 0.15
    real Spatial_drift 0.0
    optionmenu Boundary_handling: 1
        option Clamp (matches v0.2 — pins at edges)
        option Reflect (bounces off boundaries)
        option Reject (re-roll step if would exceed bounds)
    
    comment === Options ===
    positive Amplitude_scaling 0.7
    optionmenu Source_position_mode: 1
        option Random
        option Sequential
        option Frozen centre
    real Fade_duration_s 0.005
    real Fade_out_s 2.0
    boolean Allow_overlap 1
    comment (ON: dense grain clouds overlap correctly. OFF: v0.2 serial behavior)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    grain_duration_s = 0.03
    output_duration_s = 8.0
    density_grains_per_sec = 40
    time_step_size_s = 0.08
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.2
    spatial_drift = 0.0
    amplitude_scaling = 0.5
    source_position_mode = 1
    fade_duration_s = 0.003
    fade_out_s = 2.0
    presetName$ = "DenseCloud"
elsif preset = 3
    grain_duration_s = 0.15
    output_duration_s = 15.0
    density_grains_per_sec = 8
    time_step_size_s = 0.2
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.1
    spatial_drift = 0.0
    amplitude_scaling = 0.8
    source_position_mode = 1
    fade_duration_s = 0.01
    fade_out_s = 3.0
    presetName$ = "SparseField"
elsif preset = 4
    grain_duration_s = 0.06
    output_duration_s = 12.0
    density_grains_per_sec = 25
    time_step_size_s = 0.25
    time_drift = 0.02
    enable_spatial_brownian = 1
    spatial_step_size = 0.3
    spatial_drift = 0.01
    amplitude_scaling = 0.6
    source_position_mode = 1
    fade_duration_s = 0.005
    fade_out_s = 2.5
    presetName$ = "WildDrift"
elsif preset = 5
    grain_duration_s = 0.04
    output_duration_s = 10.0
    density_grains_per_sec = 30
    time_step_size_s = 0.05
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.08
    spatial_drift = 0.0
    amplitude_scaling = 0.6
    source_position_mode = 1
    fade_duration_s = 0.004
    fade_out_s = 2.0
    presetName$ = "SubtleShimmer"
elsif preset = 6
    grain_duration_s = 0.08
    output_duration_s = 10.0
    density_grains_per_sec = 15
    time_step_size_s = 0.02
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.25
    spatial_drift = 0.0
    amplitude_scaling = 0.75
    source_position_mode = 2
    fade_duration_s = 0.006
    fade_out_s = 1.5
    presetName$ = "RhythmicPulse"
elsif preset = 7
    grain_duration_s = 0.4
    output_duration_s = 20.0
    density_grains_per_sec = 6
    time_step_size_s = 0.15
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.12
    spatial_drift = 0.0
    amplitude_scaling = 0.85
    source_position_mode = 3
    fade_duration_s = 0.015
    fade_out_s = 4.0
    presetName$ = "FrozenMoment"
else
    presetName$ = "Custom"
endif

# Boundary-mode display names
if temporal_boundary_handling = 1
    temporalBoundaryName$ = "Clamp"
elsif temporal_boundary_handling = 2
    temporalBoundaryName$ = "Reflect"
else
    temporalBoundaryName$ = "Reject"
endif

if boundary_handling = 1
    spatialBoundaryName$ = "Clamp"
elsif boundary_handling = 2
    spatialBoundaryName$ = "Reflect"
else
    spatialBoundaryName$ = "Reject"
endif

if source_position_mode = 1
    sourceModeName$ = "Random"
elsif source_position_mode = 2
    sourceModeName$ = "Sequential"
else
    sourceModeName$ = "Frozen centre"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
input_name$ = selected$("Sound")

# === Convert to Mono ===
selectObject: original
Convert to mono
source = selected("Sound")

selectObject: source
input_duration = Get total duration
sampleRate = Get sampling frequency

# === Validate ===
if input_duration < grain_duration_s
    removeObject: source
    exitScript: "Input sound shorter than grain duration"
endif
if output_duration_s < grain_duration_s
    removeObject: source
    exitScript: "Output duration must be at least one grain duration"
endif
if time_step_size_s < 0
    removeObject: source
    exitScript: "Time step size must be >= 0"
endif
if spatial_step_size < 0
    removeObject: source
    exitScript: "Spatial step size must be >= 0"
endif
if fade_duration_s < 0
    removeObject: source
    exitScript: "Grain fade duration must be >= 0"
endif
if fade_duration_s > grain_duration_s / 2
    removeObject: source
    exitScript: "Grain fade duration must not exceed half the grain duration"
endif
if fade_out_s < 0
    removeObject: source
    exitScript: "Final fade-out must be >= 0"
endif

# === Calculate Grain Count ===
# Preserve the requested density; do not silently cap it.
totalGrains = max(1, round(density_grains_per_sec * output_duration_s))
if totalGrains > 5000
    removeObject: source
    exitScript: "This setting requests more than 5000 grains. Reduce density or output duration."
endif
maxOutTime = output_duration_s - grain_duration_s

# === Overlap Diagnostic ===
overlap_factor = density_grains_per_sec * grain_duration_s

# === Info Header ===
writeInfoLine: "=== Brownian Motion Texture Generator v0.4 ==="
appendInfoLine: "Source: ", input_name$, " (", fixed$(input_duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Output: ", output_duration_s, " s"
appendInfoLine: "Grains: ", totalGrains, " (density * grain_dur = ", fixed$(overlap_factor, 2), ")"
if overlap_factor > 0.95
    if allow_overlap
        appendInfoLine: "Note: dense settings — grains will overlap and sum"
    else
        appendInfoLine: "Note: dense settings, but Allow_overlap=OFF — grains will be serialized (v0.2 behavior)"
    endif
endif
appendInfoLine: "Temporal step SD: ", time_step_size_s, " s | drift/grain: ", time_drift, " s (", temporalBoundaryName$, ")"
appendInfoLine: "Spatial step SD: ", spatial_step_size, " | drift/grain: ", spatial_drift, " (", spatialBoundaryName$, ")"
appendInfoLine: "Source positions: ", sourceModeName$
appendInfoLine: ""

# === Calculate Brownian Paths ===
appendInfoLine: "Calculating Brownian paths..."

time_offset = 0
pan_position = 0.5

for i to totalGrains
    # Temporal Brownian: regular density grid + cumulative random-walk offset.
    # Boundary handling updates the Brownian STATE, not only the displayed
    # grain time, avoiding long artificial piles at 0 / maxOutTime.
    base_time = (i - 1) / density_grains_per_sec
    if base_time > maxOutTime
        base_time = maxOutTime
    endif

    if maxOutTime <= 0
        grain_time = 0
        time_offset = -base_time
    elsif temporal_boundary_handling = 1
        # Clamp
        time_step = randomGauss(time_drift, time_step_size_s)
        candidate_time = base_time + time_offset + time_step
        grain_time = min(maxOutTime, max(0, candidate_time))
        time_offset = grain_time - base_time
    elsif temporal_boundary_handling = 2
        # Reflect. Mapping through a 2*range period handles arbitrarily
        # large Gaussian overshoots without repeated while loops.
        time_step = randomGauss(time_drift, time_step_size_s)
        candidate_time = base_time + time_offset + time_step
        period = 2 * maxOutTime
        reflected_time = candidate_time - floor(candidate_time / period) * period
        if reflected_time > maxOutTime
            reflected_time = period - reflected_time
        endif
        grain_time = reflected_time
        time_offset = grain_time - base_time
    else
        # Reject / re-roll. If the moving base has already pushed the
        # no-step state outside the legal range, clamp state first.
        base_candidate = base_time + time_offset
        if base_candidate < 0 or base_candidate > maxOutTime
            base_candidate = min(maxOutTime, max(0, base_candidate))
            time_offset = base_candidate - base_time
        endif
        tries = 0
        accepted = 0
        while accepted = 0 and tries < 30
            time_step = randomGauss(time_drift, time_step_size_s)
            candidate_time = base_time + time_offset + time_step
            if candidate_time >= 0 and candidate_time <= maxOutTime
                grain_time = candidate_time
                time_offset = grain_time - base_time
                accepted = 1
            endif
            tries = tries + 1
        endwhile
        if accepted = 0
            grain_time = min(maxOutTime, max(0, base_time + time_offset))
            time_offset = grain_time - base_time
        endif
    endif
    pathOutTime[i] = grain_time

    # Spatial Brownian — three boundary modes
    if enable_spatial_brownian
        if boundary_handling = 1
            # Clamp
            spatial_step = randomGauss(spatial_drift, spatial_step_size)
            pan_position = min(1, max(0, pan_position + spatial_step))
        elsif boundary_handling = 2
            # Reflect through a period of 2 pan units.
            spatial_step = randomGauss(spatial_drift, spatial_step_size)
            candidate_pan = pan_position + spatial_step
            reflected_pan = candidate_pan - floor(candidate_pan / 2) * 2
            if reflected_pan > 1
                reflected_pan = 2 - reflected_pan
            endif
            pan_position = reflected_pan
        else
            # Reject — re-roll step if it would exceed bounds.
            tries = 0
            accepted = 0
            while accepted = 0 and tries < 30
                spatial_step = randomGauss(spatial_drift, spatial_step_size)
                trial_pan = pan_position + spatial_step
                if trial_pan >= 0 and trial_pan <= 1
                    pan_position = trial_pan
                    accepted = 1
                endif
                tries = tries + 1
            endwhile
            # If all proposals fail, keep the previous position: true reject.
        endif
    else
        pan_position = 0.5
    endif
    pathPan[i] = pan_position

    # Source position
    sourceSpan = input_duration - grain_duration_s
    if source_position_mode = 1
        pathSrcTime[i] = randomUniform(0, sourceSpan)
    elsif source_position_mode = 2
        if totalGrains = 1
            pathSrcTime[i] = 0.5 * sourceSpan
        else
            pathSrcTime[i] = (i - 1) / (totalGrains - 1) * sourceSpan
        endif
    else
        pathSrcTime[i] = 0.5 * sourceSpan
    endif
endfor

# Copy the generated path into render arrays. These copies may be sorted;
# pathOutTime/pathPan/pathSrcTime remain untouched for visualization.
for i to totalGrains
    grainOutTime[i] = pathOutTime[i]
    grainPan[i] = pathPan[i]
    grainSrcTime[i] = pathSrcTime[i]
endfor

# === Sort Grains by Output Time (insertion sort) ===
# Replaces v0.2's bubble sort. For nearly-sorted Brownian sequences
# (which is the typical case), insertion sort is near-linear.
# Rendering order is chronological; the unsorted path is retained separately.
appendInfoLine: "Sorting grains..."

for i from 2 to totalGrains
    keyT = grainOutTime[i]
    keyP = grainPan[i]
    keyS = grainSrcTime[i]
    j = i - 1
    while j >= 1 and grainOutTime[j] > keyT
        grainOutTime[j + 1] = grainOutTime[j]
        grainPan[j + 1] = grainPan[j]
        grainSrcTime[j + 1] = grainSrcTime[j]
        j = j - 1
    endwhile
    grainOutTime[j + 1] = keyT
    grainPan[j + 1] = keyP
    grainSrcTime[j + 1] = keyS
endfor

# === Build exact render schedule and output canvas ===
appendInfoLine: "Preparing render schedule..."

# In overlap mode, sorted start times are written directly. In serialized
# mode, compute the exact pushed-forward start time for every grain FIRST,
# then allocate a canvas long enough to hold the schedule without truncation.
if allow_overlap
    canvasDur = output_duration_s
else
    currentTime = 0
    for i to totalGrains
        if grainOutTime[i] > currentTime
            serialStart[i] = grainOutTime[i]
        else
            serialStart[i] = currentTime
        endif
        currentTime = serialStart[i] + grain_duration_s
    endfor
    canvasDur = max(output_duration_s, currentTime)
    if canvasDur > output_duration_s + 1 / sampleRate
        appendInfoLine: "Serial mode extends output to ", fixed$(canvasDur, 3), " s"
    endif
endif

estimatedStereoSamples = round(canvasDur * sampleRate) * 2
if estimatedStereoSamples > 50000000
    removeObject: source
    exitScript: "Requested output would exceed 50 million stereo samples. Reduce duration, density, or use overlap mode."
endif

output = Create Sound from formula: input_name$ + "_brownian_" + presetName$,
    ... 2, 0, canvasDur, sampleRate, "0"

sourceID$ = string$(source)

# === Generate Grains ===
appendInfoLine: "Writing grains..."

gainStr$ = fixed$(amplitude_scaling, 8)


for i to totalGrains
    # Determine where to write this grain
    if allow_overlap
        writeStart = grainOutTime[i]
    else
        writeStart = serialStart[i]
    endif
    
    writeEnd = writeStart + grain_duration_s
    if writeEnd > canvasDur
        writeEnd = canvasDur
    endif
    
    if writeStart < canvasDur and writeEnd > writeStart
        # Compute pan gains
        pan = grainPan[i]
        gainL = sqrt(1 - pan)
        gainR = sqrt(pan)
        gainLStr$ = fixed$(gainL, 8)
        gainRStr$ = fixed$(gainR, 8)
        
        # Source extraction parameters
        srcOffset = grainSrcTime[i]
        srcStartSamp = round(srcOffset * sampleRate)
        canvasStartSamp = round(writeStart * sampleRate)
        offsetStr$ = string$(srcStartSamp - canvasStartSamp)
        
        # Cosine fade-in/out for Hanning-window-equivalent envelope
        # Praat's Fade in/out at "yes" = cosine (raised-cosine ramp).
        # We replicate it in the formula: gain at relative time
        # tRel = (col - canvasStart) / sr (in seconds within the grain),
        # tRel = 0 at start, tRel = grain_duration_s at end.
        # Hanning window is 0.5 - 0.5*cos(2*pi*tRel/grainDur), but for
        # short fades (fade_duration_s) we want a cosine ramp only at
        # the edges, full gain in the middle.
        durStr$ = fixed$(grain_duration_s, 8)
        fadeStr$ = fixed$(fade_duration_s, 8)
        startStr$ = fixed$(writeStart, 8)
        
        # Build the fade envelope as part of the grain reference
        # tRel = x - writeStart  (time within the grain, in seconds)
        # win(tRel):
        #   if tRel < fade then 0.5 * (1 - cos(pi * tRel / fade))
        #   elif tRel > grainDur - fade then 0.5 * (1 - cos(pi * (grainDur - tRel) / fade))
        #   else 1
        if fade_duration_s > 0
            win$ = "(if (x - " + startStr$ + ") < " + fadeStr$
                ... + " then 0.5 * (1 - cos(pi * (x - " + startStr$ + ") / " + fadeStr$ + "))"
                ... + " else if (x - " + startStr$ + ") > (" + durStr$ + " - " + fadeStr$ + ")"
                ... + " then 0.5 * (1 - cos(pi * (" + durStr$ + " - (x - " + startStr$ + ")) / " + fadeStr$ + "))"
                ... + " else 1 fi fi)"
        else
            win$ = "1"
        endif
        
        # Source reference. For output column col, source column is
        # col + offset. If col + offset is out of source range,
        # object[] returns 0 (Praat default). So out-of-range writes
        # are silent — safe.
        srcRef$ = "object[" + sourceID$ + ", col + " + offsetStr$ + "]"
        
        selectObject: output
        # Left channel
        Formula (part): writeStart, writeEnd, 1, 1,
            ... "self + " + gainStr$ + " * " + gainLStr$ + " * " + win$ + " * " + srcRef$
        # Right channel
        Formula (part): writeStart, writeEnd, 2, 2,
            ... "self + " + gainStr$ + " * " + gainRStr$ + " * " + win$ + " * " + srcRef$
    endif
    
    if i mod 50 = 0
        appendInfoLine: "  ", i, "/", totalGrains
    endif
endfor

# === Apply final fade-out ===
selectObject: output
outDur = Get total duration
effectiveFadeOut = min(fade_out_s, outDur)
if effectiveFadeOut > 0
    fadeStartTime = outDur - effectiveFadeOut
    fadeStartStr$ = fixed$(fadeStartTime, 8)
    fadeDurStr$ = fixed$(effectiveFadeOut, 8)
    # Cosine fade-out across both channels, including the case where the
    # requested fade spans the entire output.
    Formula: "self * if x < " + fadeStartStr$ + " then 1 else 0.5 * (1 + cos(pi * (x - " + fadeStartStr$ + ") / " + fadeDurStr$ + ")) fi"
endif

# === Safety peak limiter ===
# Do not normalize every result: that would cancel Amplitude_scaling.
selectObject: output
preLimitPeak = Get absolute extremum: 0, 0, "None"
if preLimitPeak > 0.95
    Scale peak: 0.95
endif

# === Cleanup source ===
removeObject: source

# === Final stats ===
selectObject: output
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    vizGrainMax = max(2, totalGrains)
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##BROWNIAN MOTION TEXTURE GENERATOR##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if allow_overlap
        modeStr$ = "Overlap"
    else
        modeStr$ = "Serial"
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... input_name$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(totalGrains) + " grains"
        ... + "  |  T:" + temporalBoundaryName$ + "/S:" + spatialBoundaryName$
        ... + "  |  " + modeStr$
        ... + "  |  Density factor: " + fixed$(overlap_factor, 2)
    
    # ----------------------------------------------------------
    # PANEL A: TEMPORAL BROWNIAN PATH  (left, headline)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 1, vizGrainMax, 0, output_duration_s
    Paint rectangle: "{0.96, 0.96, 0.96}", 1, totalGrains, 0, output_duration_s
    
    # Reference: the "ideal" linear progression (no Brownian drift)
    Colour: "{0.65, 0.65, 0.70}"
    Dotted line
    Line width: 1.2
    referenceEnd = min(maxOutTime, (totalGrains - 1) / density_grains_per_sec)
    Draw line: 1, 0, totalGrains, referenceEnd
    Solid line
    Line width: 1
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: totalGrains * 0.99, "right", min(output_duration_s * 0.95, referenceEnd + output_duration_s * 0.03), "half", "no-drift reference"
    
    # Brownian path
    Colour: "{0.85, 0.30, 0.30}"
    Line width: 1.3
    for i from 2 to totalGrains
        Draw line: i - 1, pathOutTime[i - 1], i, pathOutTime[i]
    endfor
    Line width: 1
    
    # Per-grain dots, color by source position
    for i to totalGrains
        srcRel = pathSrcTime[i] / max(input_duration, 0.001)
        cR = 0.30 + srcRel * 0.55
        cG = 0.40
        cB = 0.78 - srcRel * 0.55
        if cB < 0
            cB = 0
        endif
        rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
        Paint circle (mm): rgb$, i, pathOutTime[i], 0.6
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output time (s)"
    Text bottom: "yes", "Grain #  (color = source position)"
    
    # ----------------------------------------------------------
    # PANEL B: SPATIAL BROWNIAN PATH  (right, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
    Axes: 1, vizGrainMax, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 1, totalGrains, 0, 1
    
    # Center reference
    Colour: "{0.65, 0.65, 0.70}"
    Dotted line
    Draw line: 1, 0.5, totalGrains, 0.5
    Solid line
    
    # L/R reference lines
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: 1, 0, totalGrains, 0
    Draw line: 1, 1, totalGrains, 1
    
    # Spatial path
    if enable_spatial_brownian
        Colour: "{0.30, 0.65, 0.30}"
        Line width: 1.3
        for i from 2 to totalGrains
            Draw line: i - 1, pathPan[i - 1], i, pathPan[i]
        endfor
        Line width: 1
        
        # Per-grain dots colored by pan
        for i to totalGrains
            cR = 0.30 + pathPan[i] * 0.55
            cG = 0.55
            cB = 0.78 - pathPan[i] * 0.55
            if cB < 0
                cB = 0
            endif
            rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
            Paint circle (mm): rgb$, i, pathPan[i], 0.5
        endfor
    else
        Colour: "{0.55, 0.55, 0.55}"
        Font size: 8
        Text: totalGrains / 2, "centre", 0.5, "half", "Spatial Brownian disabled"
    endif
    
    # L/R labels
    Font size: 5
    Colour: "{0.30, 0.30, 0.30}"
    Text: 1.5, "left", 0.04, "half", "L"
    Text: 1.5, "left", 0.96, "half", "R"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pan (0=L, 1=R)"
    Text bottom: "yes", "Grain #"
    
    # ----------------------------------------------------------
    # PANEL C: GRAIN DENSITY HISTOGRAM  (right, lower)
    # Time on x, count of grains landing in each time bin on y
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.20, 4.50
    
    nDensBins = 30
    densBins# = zero# (nDensBins)
    binDur = output_duration_s / nDensBins
    
    for i to totalGrains
        b = floor(pathOutTime[i] / binDur) + 1
        if b < 1
            b = 1
        endif
        if b > nDensBins
            b = nDensBins
        endif
        densBins#[b] = densBins#[b] + 1
    endfor
    
    densMax = 1
    for b to nDensBins
        if densBins#[b] > densMax
            densMax = densBins#[b]
        endif
    endfor
    
    Axes: 0, output_duration_s, 0, densMax * 1.15
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, output_duration_s, 0, densMax * 1.15
    
    # Expected uniform density reference line
    expectedPerBin = totalGrains / nDensBins
    Colour: "{0.78, 0.78, 0.85}"
    Dotted line
    Draw line: 0, expectedPerBin, output_duration_s, expectedPerBin
    Solid line
    Font size: 5
    Colour: "{0.55, 0.55, 0.55}"
    Text: output_duration_s * 0.99, "right", expectedPerBin * 1.1, "half",
        ... "uniform = " + fixed$(expectedPerBin, 1)
    
    # Bars
    for b to nDensBins
        if densBins#[b] > 0
            xL = (b - 1) * binDur
            xR = xL + binDur * 0.92
            Paint rectangle: "{0.55, 0.40, 0.78}", xL, xR, 0, densBins#[b]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Grain count"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Temporal Brownian path"
    Text: 6.10, "centre", 7.30, "half", "Spatial Brownian (upper) & temporal density (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: output
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: output
    Extract one channel: 1
    vCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh1
    
    selectObject: output
    Extract one channel: 2
    vCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh2
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output  (blue=L  orange=R)"
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
        ... + "  " + input_name$
        ... + "  |  " + string$(totalGrains) + " grains @ " + fixed$(density_grains_per_sec, 1) + "/s"
        ... + "  |  Grain dur: " + fixed$(grain_duration_s * 1000, 1) + " ms"
        ... + "  |  Time step: " + fixed$(time_step_size_s, 3) + "s"
        ... + "  |  Spatial step: " + fixed$(spatial_step_size, 3)
        ... + "  |  Source: " + sourceModeName$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Boundaries T/S: " + temporalBoundaryName$ + "/" + spatialBoundaryName$
        ... + "  |  Mode: " + modeStr$
        ... + "  |  Fade in/out: " + fixed$(fade_duration_s * 1000, 1) + " ms / " + fixed$(fade_out_s, 2) + " s"
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final ===
selectObject: output
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: output
    Play
endif

selectObject: output
