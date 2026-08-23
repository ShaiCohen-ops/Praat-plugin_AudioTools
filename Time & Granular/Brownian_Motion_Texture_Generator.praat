# ============================================================
# Praat AudioTools - Brownian_Motion_Texture_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
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
# Changelog v0.4.3:
#   - Visualization-only alignment to the current Praat AudioTools suite.
#   - Reframed as Source -> Brownian state map -> Output -> Summary.
#   - v0.4.3 aligns the left edges and left-side axis labels of all display boxes.
#   - Unified temporal and spatial Brownian paths on aligned Grain-number tracks.
#   - Sanitized underscores in display names and clarified colour semantics.
#   - No DSP or scheduling changes.
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

form Brownian Motion Texture v0.4.3
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
writeInfoLine: "=== Brownian Motion Texture Generator v0.4.3 ==="
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
# VISUALIZATION  (current Praat AudioTools suite styling)
# Source -> Brownian state map -> Output -> Summary.
# The central map directly shows the two cumulative random walks:
#   upper track = output-time state against the no-drift reference,
#   lower track = stereo-pan state around the centre reference.
# Colour is reserved for state identity; boundaries and guides are neutral.
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    vizGrainMax = max(2, totalGrains)
    Erase all
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    displayName$ = replace$(input_name$, "_", " ", 0)

    if allow_overlap
        modeStr$ = "Overlap"
    else
        modeStr$ = "Serial"
    endif

    # Mono, zero-based source display copy.
    selectObject: original
    vizOrig = Convert to mono
    selectObject: vizOrig
    vizOrigStart = Get start time
    Shift times by: -vizOrigStart

    # Shared source/output amplitude scale.
    selectObject: vizOrig
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: output
    outPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(origPeak, outPeak)
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = 1.15 * sharedPeak

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Brownian Motion Texture Generator##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Brownian Motion Texture Generator.praat  |  " + displayName$ + "  |  cumulative temporal and spatial random walks"

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, input_duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, input_duration, -sharedAmp, sharedAmp
    selectObject: vizOrig
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, input_duration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, input_duration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * input_duration, "left", 0.82 * sharedAmp, "half", sourceModeName$ + " source positions  |  grain " + fixed$(grain_duration_s * 1000, 1) + " ms  |  " + string$(totalGrains) + " grains"

    # ----------------------------------------------------------
    # BROWNIAN STATE MAP - unified process view
    # ----------------------------------------------------------
    # Outer panel provides one title/frame for both aligned state tracks.
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.22, 4.40
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text top: "no", "##Brownian state map##"

    # Upper track: cumulative temporal state.
    Select outer viewport: 0, 8, 2.28, 3.38
    Select inner viewport: 0.55, 7.75, 2.39, 3.28
    Axes: 1, vizGrainMax, 0, output_duration_s
    Paint rectangle: "{0.985, 0.985, 0.985}", 1, vizGrainMax, 0, output_duration_s

    referenceEnd = min(maxOutTime, (totalGrains - 1) / density_grains_per_sec)
    Colour: "{0.72, 0.72, 0.75}"
    Dotted line
    Draw line: 1, 0, totalGrains, referenceEnd
    Solid line

    Colour: "{0.82, 0.34, 0.24}"
    Line width: 1.3
    for i from 2 to totalGrains
        Draw line: i - 1, pathOutTime[i - 1], i, pathOutTime[i]
    endfor
    for i to totalGrains
        Paint circle (mm): "{0.82, 0.34, 0.24}", i, pathOutTime[i], 0.45
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output time (s)"
    Axes: 1, vizGrainMax, 0, output_duration_s
    Colour: "{0.34, 0.34, 0.34}"
    Text: 1 + 0.01 * (vizGrainMax - 1), "left", 0.90 * output_duration_s, "half", "temporal walk"
    Colour: "{0.58, 0.58, 0.58}"
    Text: totalGrains - 0.5, "right", min(output_duration_s * 0.82, referenceEnd + output_duration_s * 0.06), "half", "no-drift reference"

    # Lower track: cumulative spatial state.
    Select outer viewport: 0, 8, 3.43, 4.43
    Select inner viewport: 0.55, 7.75, 3.52, 4.31
    Axes: 1, vizGrainMax, 0, 1
    Paint rectangle: "{0.985, 0.985, 0.985}", 1, vizGrainMax, 0, 1

    Colour: "{0.72, 0.72, 0.75}"
    Dotted line
    Draw line: 1, 0.5, totalGrains, 0.5
    Solid line

    if enable_spatial_brownian
        Colour: "{0.48, 0.33, 0.72}"
        Line width: 1.3
        for i from 2 to totalGrains
            Draw line: i - 1, pathPan[i - 1], i, pathPan[i]
        endfor
        for i to totalGrains
            Paint circle (mm): "{0.48, 0.33, 0.72}", i, pathPan[i], 0.42
        endfor
        Line width: 1
    else
        Colour: "{0.55, 0.55, 0.55}"
        Font size: 7
        Text: totalGrains / 2, "centre", 0.5, "half", "spatial Brownian disabled"
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pan"
    Text bottom: "yes", "Grain #"
    Axes: 1, vizGrainMax, 0, 1
    Colour: "{0.34, 0.34, 0.34}"
    Text: 1 + 0.01 * (vizGrainMax - 1), "left", 0.90, "half", "R"
    Text: 1 + 0.01 * (vizGrainMax - 1), "left", 0.10, "half", "L"
    Colour: "{0.58, 0.58, 0.58}"
    Text: totalGrains - 0.5, "right", 0.57, "half", "centre reference"

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83
    Axes: 0, finalDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0

    selectObject: output
    Extract one channel: 1
    vizCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, finalDur, -sharedAmp, sharedAmp, "no", "Curve"
    removeObject: vizCh1

    selectObject: output
    Extract one channel: 2
    vizCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, finalDur, -sharedAmp, sharedAmp, "no", "Curve"
    removeObject: vizCh2

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, finalDur, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * finalDur, "left", 0.82 * sharedAmp, "half", "blue = L  |  orange = R  |  " + modeStr$ + "  |  density factor " + fixed$(overlap_factor, 2)

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", presetName$ + "  |  " + string$(totalGrains) + " grains @ " + fixed$(density_grains_per_sec, 1) + "/s  |  grain " + fixed$(grain_duration_s * 1000, 1) + " ms  |  temporal step " + fixed$(time_step_size_s, 3) + " s  |  spatial step " + fixed$(spatial_step_size, 3)
    Text: 0.02, "left", 0.18, "half", "Boundaries T/S " + temporalBoundaryName$ + "/" + spatialBoundaryName$ + "  |  source " + sourceModeName$ + "  |  " + modeStr$ + "  |  fade out " + fixed$(fade_out_s, 2) + " s  |  output " + fixed$(finalDur, 2) + " s  |  peak " + fixed$(finalPeak, 3)

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizOrig
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
