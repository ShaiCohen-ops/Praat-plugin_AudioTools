# ============================================================
# Praat AudioTools - Wave_Terrain_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wave-terrain synthesis: a bounded 2-D trajectory scans a terrain z(x,y),
#   and the interpolated terrain height becomes the audio sample value.
#
# v0.4.2 runtime guard:
#   - Caps Terrain size at 512 before Matrix allocation to prevent accidental
#     excessive memory/CPU use in Custom settings. Audio/DSP behavior is unchanged.
# v0.4.1 hotfix:
#   - Fixed manual trajectory plotting at Sound endpoints: Get value at time 0
#     or exactly duration can be undefined because Sound sample centres lie
#     inside the nominal xmin..xmax interval. Plot queries are now clamped to
#     the first/last valid sample times. Audio synthesis is unchanged.
#
# v0.4 review changes:
#   - Reinterpreted X/Y amplitude as terrain span: 1.0 = full width/height.
#     This removes the severe boundary clipping present in v0.3 presets.
#   - Corrected trajectory modulation: modulation now perturbs trajectory phase
#     rather than scaling the already-offset coordinate and adding the offset twice.
#   - Replaced nearest-cell lookup with bilinear interpolation.
#   - Corrected the Chebyshev terrain to use actual T2/T3 polynomial terms.
#   - Renamed the deterministic "Fractal" terrain to Multi-scale harmonic.
#   - Removed ineffective Output_gain (it was cancelled by final peak scaling).
#   - Added DC removal, safe silence handling, output-peak control, random seed,
#     validation, and a compact Edit details panel.
#   - Rebuilt visualization around the PROCESS:
#       terrain + path -> x/y controls -> sampled height -> measured output.
#     Titles, data and QC strips use separate Picture viewports.
# ============================================================

form Wave Terrain Synthesis
    comment === Preset and duration ===
    optionmenu Preset 1
        option Custom
        option Classic Sine Terrain
        option Metallic Chebyshev
        option Chaotic Multiscale
        option Spiral Galaxy
        option FM Complex
        option Alien Landscape
        option Rhythmic Pulses
        option Smooth Ambient
    positive Duration_s 3.0

    comment === Custom core controls ===
    optionmenu Terrain_type 1
        option Sine product
        option Chebyshev product
        option Random smoothed
        option Multi-scale harmonic
        option Spiral
    optionmenu X_trajectory 1
        option Sine
        option Triangle
        option Saw
        option Square
    positive X_frequency_Hz 220
    optionmenu Y_trajectory 1
        option Sine
        option Triangle
        option Saw
        option Square
    positive Y_frequency_Hz 330

    comment === Output ===
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ------------------------------------------------------------------------------
# Defaults used by Custom mode and as the editable details for presets.
# ------------------------------------------------------------------------------
sample_rate_Hz = 44100
terrain_size = 128
terrain_scale = 1.0
x_span = 0.8
x_phase_deg = 0
x_offset = 0.5
x_phase_mod_rate_Hz = 0
x_phase_mod_index_rad = 0.5
y_span = 0.8
y_phase_deg = 90
y_offset = 0.5
y_phase_mod_rate_Hz = 0
output_peak = 0.95
random_seed = 0

preset_name$ = preset$

# Apply presets before Edit details, so the advanced page exposes preset values.
if preset$ = "Classic Sine Terrain"
    terrain_type = 1
    terrain_scale = 1.0
    x_frequency_Hz = 220
    y_frequency_Hz = 330
    x_trajectory = 1
    y_trajectory = 1
    x_span = 0.9
    y_span = 0.9
    x_phase_deg = 0
    y_phase_deg = 90
    x_offset = 0.5
    y_offset = 0.5
    x_phase_mod_rate_Hz = 0
    y_phase_mod_rate_Hz = 0
    terrain_size = 128
elsif preset$ = "Metallic Chebyshev"
    terrain_type = 2
    terrain_scale = 1.0
    x_frequency_Hz = 165
    y_frequency_Hz = 247
    x_trajectory = 1
    y_trajectory = 1
    x_span = 0.7
    y_span = 0.7
    x_phase_deg = 0
    y_phase_deg = 90
    x_offset = 0.5
    y_offset = 0.5
    x_phase_mod_rate_Hz = 0
    y_phase_mod_rate_Hz = 0
    terrain_size = 128
elsif preset$ = "Chaotic Multiscale"
    terrain_type = 4
    terrain_scale = 1.5
    x_frequency_Hz = 110
    y_frequency_Hz = 165
    x_trajectory = 2
    y_trajectory = 3
    x_span = 0.95
    y_span = 0.95
    x_phase_deg = 0
    y_phase_deg = 90
    x_offset = 0.5
    y_offset = 0.5
    x_phase_mod_rate_Hz = 2.3
    y_phase_mod_rate_Hz = 3.7
    x_phase_mod_index_rad = 0.3
    terrain_size = 96
elsif preset$ = "Spiral Galaxy"
    terrain_type = 5
    terrain_scale = 2.0
    x_frequency_Hz = 130
    y_frequency_Hz = 195
    x_trajectory = 1
    y_trajectory = 1
    x_span = 0.85
    y_span = 0.85
    x_phase_deg = 0
    y_phase_deg = 90
    x_offset = 0.5
    y_offset = 0.5
    x_phase_mod_rate_Hz = 0.5
    y_phase_mod_rate_Hz = 0.7
    x_phase_mod_index_rad = 0.4
    terrain_size = 128
elsif preset$ = "FM Complex"
    terrain_type = 1
    terrain_scale = 2.0
    x_frequency_Hz = 440
    y_frequency_Hz = 660
    x_trajectory = 1
    y_trajectory = 1
    x_span = 0.6
    y_span = 0.6
    x_phase_deg = 0
    y_phase_deg = 90
    x_offset = 0.5
    y_offset = 0.5
    x_phase_mod_rate_Hz = 6.5
    y_phase_mod_rate_Hz = 9.8
    x_phase_mod_index_rad = 0.7
    terrain_size = 96
elsif preset$ = "Alien Landscape"
    terrain_type = 3
    terrain_scale = 1.0
    x_frequency_Hz = 82.4
    y_frequency_Hz = 123.6
    x_trajectory = 4
    y_trajectory = 2
    x_span = 0.9
    y_span = 0.9
    x_phase_deg = 0
    y_phase_deg = 90
    x_offset = 0.5
    y_offset = 0.5
    x_phase_mod_rate_Hz = 0.2
    y_phase_mod_rate_Hz = 0.3
    x_phase_mod_index_rad = 0.6
    terrain_size = 128
elsif preset$ = "Rhythmic Pulses"
    terrain_type = 1
    terrain_scale = 3.0
    x_frequency_Hz = 8
    y_frequency_Hz = 440
    x_trajectory = 4
    y_trajectory = 1
    x_span = 0.8
    y_span = 0.5
    x_phase_deg = 0
    y_phase_deg = 90
    x_offset = 0.5
    y_offset = 0.5
    x_phase_mod_rate_Hz = 0
    y_phase_mod_rate_Hz = 0
    terrain_size = 128
elsif preset$ = "Smooth Ambient"
    terrain_type = 1
    terrain_scale = 0.5
    x_frequency_Hz = 55
    y_frequency_Hz = 82.5
    x_trajectory = 1
    y_trajectory = 1
    x_span = 0.95
    y_span = 0.95
    x_phase_deg = 0
    y_phase_deg = 90
    x_offset = 0.5
    y_offset = 0.5
    x_phase_mod_rate_Hz = 0.1
    y_phase_mod_rate_Hz = 0.15
    x_phase_mod_index_rad = 0.2
    terrain_size = 96
endif

if edit_details
    beginPause: "Wave Terrain Synthesis - details"
        integer: "Terrain size", terrain_size
        positive: "Terrain spatial scale", terrain_scale
        real: "X span (0..1)", x_span
        real: "X phase (deg)", x_phase_deg
        real: "X offset (0..1)", x_offset
        real: "X phase-mod rate (Hz)", x_phase_mod_rate_Hz
        real: "Y span (0..1)", y_span
        real: "Y phase (deg)", y_phase_deg
        real: "Y offset (0..1)", y_offset
        real: "Y phase-mod rate (Hz)", y_phase_mod_rate_Hz
        real: "Phase-mod index (rad)", x_phase_mod_index_rad
        positive: "Sample rate (Hz)", sample_rate_Hz
        positive: "Output peak", output_peak
        integer: "Random seed (0=random)", random_seed
    endPause: "OK", 1
endif

y_phase_mod_index_rad = x_phase_mod_index_rad
phase_mod_index_rad = x_phase_mod_index_rad

# Option-menu string companions do not update when a preset assigns the numeric
# value programmatically, so derive explicit names from the final numeric state.
if terrain_type = 1
    terrain_name$ = "Sine product"
elsif terrain_type = 2
    terrain_name$ = "Chebyshev product"
elsif terrain_type = 3
    terrain_name$ = "Random smoothed"
elsif terrain_type = 4
    terrain_name$ = "Multi-scale harmonic"
else
    terrain_name$ = "Spiral"
endif
if x_trajectory = 1
    x_name$ = "Sine"
elsif x_trajectory = 2
    x_name$ = "Triangle"
elsif x_trajectory = 3
    x_name$ = "Saw"
else
    x_name$ = "Square"
endif
if y_trajectory = 1
    y_name$ = "Sine"
elsif y_trajectory = 2
    y_name$ = "Triangle"
elsif y_trajectory = 3
    y_name$ = "Saw"
else
    y_name$ = "Square"
endif

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------
tsize = round(terrain_size)
maxTerrainSize = 512
if tsize < 8
    exitScript: "Terrain size must be at least 8."
endif
if tsize > maxTerrainSize
    exitScript: "Terrain size " + string$(tsize) + " is too large. Maximum is " + string$(maxTerrainSize) + ". Reduce Terrain size."
endif
if terrain_scale <= 0
    exitScript: "Terrain spatial scale must be positive."
endif
if sample_rate_Hz < 4000
    exitScript: "Sample rate is too low for wave-terrain synthesis."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be in the interval (0, 1]."
endif
if x_span < 0 or x_span > 1 or y_span < 0 or y_span > 1
    exitScript: "X/Y span must be between 0 and 1. A span of 1 covers the full terrain dimension."
endif
if x_offset < 0 or x_offset > 1 or y_offset < 0 or y_offset > 1
    exitScript: "X/Y offsets must lie between 0 and 1."
endif
if x_span > 2 * min(x_offset, 1-x_offset) + 1e-12
    exitScript: "X span is too wide for the chosen X offset. Reduce span or move the offset toward 0.5."
endif
if y_span > 2 * min(y_offset, 1-y_offset) + 1e-12
    exitScript: "Y span is too wide for the chosen Y offset. Reduce span or move the offset toward 0.5."
endif
if x_phase_mod_rate_Hz < 0 or y_phase_mod_rate_Hz < 0 or phase_mod_index_rad < 0
    exitScript: "Phase-mod rates and modulation index must be zero or positive."
endif
x_inst_rate_max = x_frequency_Hz + phase_mod_index_rad * x_phase_mod_rate_Hz
y_inst_rate_max = y_frequency_Hz + phase_mod_index_rad * y_phase_mod_rate_Hz
if max(x_inst_rate_max, y_inst_rate_max) >= 0.45 * sample_rate_Hz
    exitScript: "Trajectory rate is too close to Nyquist. Increase sample rate or lower trajectory/modulation rates."
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

# ------------------------------------------------------------------------------
# Information
# ------------------------------------------------------------------------------
writeInfoLine: "=== Wave Terrain Synthesis v0.4.2 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Terrain: ", terrain_name$, " (", tsize, "x", tsize, ")"
appendInfoLine: "X: ", x_name$, " @ ", fixed$(x_frequency_Hz, 2), " Hz | span ", fixed$(x_span, 2)
appendInfoLine: "Y: ", y_name$, " @ ", fixed$(y_frequency_Hz, 2), " Hz | span ", fixed$(y_span, 2)
appendInfoLine: "Lookup: bilinear interpolation"
appendInfoLine: ""

# ==============================================================================
# 1. TERRAIN z(x,y)
# ==============================================================================
appendInfoLine: "Creating terrain..."
terrain_dx = 1 / (tsize - 1)
terrain = Create Matrix: "terrain", 0, 1, tsize, terrain_dx, 0, 0, 1, tsize, terrain_dx, 0, "0"

for i from 1 to tsize
    for j from 1 to tsize
        nx = (j - 1) / (tsize - 1)
        ny = (i - 1) / (tsize - 1)

        if terrain_type = 1
            val = sin(2*pi*nx*4*terrain_scale) * sin(2*pi*ny*4*terrain_scale)
        elsif terrain_type = 2
            # Exact T2/T3 construction at scale=1; scale stretches coordinates.
            u = (2*nx - 1) * terrain_scale
            v = (2*ny - 1) * terrain_scale
            t2u = 2*u^2 - 1
            t3u = 4*u^3 - 3*u
            t2v = 2*v^2 - 1
            t3v = 4*v^3 - 3*v
            val = t3u*t2v - t2u*t3v
        elsif terrain_type = 3
            val = randomGauss(0, 1)
        elsif terrain_type = 4
            val = sin(2*pi*nx*2*terrain_scale) * sin(2*pi*ny*2*terrain_scale) + 0.5 * sin(2*pi*nx*4*terrain_scale) * sin(2*pi*ny*4*terrain_scale) + 0.25 * sin(2*pi*nx*8*terrain_scale) * sin(2*pi*ny*8*terrain_scale)
        elsif terrain_type = 5
            dist = sqrt((nx-0.5)^2 + (ny-0.5)^2)
            angle = arctan2(ny-0.5, nx-0.5)
            val = sin(2*pi*dist*10*terrain_scale + angle)
        endif

        Set value: i, j, val
    endfor
endfor

# One periodic cross-neighbour smoothing pass for the random terrain.
if terrain_type = 3
    selectObject: terrain
    temp_terrain = Copy: "terrain_unsmoothed"
    for i from 1 to tsize
        im1 = i - 1
        if im1 < 1
            im1 = tsize
        endif
        ip1 = i + 1
        if ip1 > tsize
            ip1 = 1
        endif
        for j from 1 to tsize
            jm1 = j - 1
            if jm1 < 1
                jm1 = tsize
            endif
            jp1 = j + 1
            if jp1 > tsize
                jp1 = 1
            endif

            selectObject: temp_terrain
            v1 = Get value in cell: im1, j
            v2 = Get value in cell: ip1, j
            v3 = Get value in cell: i, jm1
            v4 = Get value in cell: i, jp1
            v5 = Get value in cell: i, j
            avg = (v1 + v2 + v3 + v4 + v5) / 5
            selectObject: terrain
            Set value: i, j, avg
        endfor
    endfor
    removeObject: temp_terrain
endif

# Zero-centre the terrain, then normalize by maximum absolute height.
terrain_mean = 0
selectObject: terrain
for i from 1 to tsize
    for j from 1 to tsize
        cell_value = Get value in cell: i, j
        terrain_mean = terrain_mean + cell_value
    endfor
endfor
terrain_mean = terrain_mean / (tsize * tsize)
Formula: "self - terrain_mean"
terrain_max = Get maximum
terrain_min = Get minimum
terrain_peak = max(abs(terrain_max), abs(terrain_min))
if terrain_peak > 0
    Formula: "self / terrain_peak"
endif
terrain_max = Get maximum
terrain_min = Get minimum

# ==============================================================================
# 2. BOUNDED TRAJECTORY [x(t), y(t)]
#    Span=1 means a full 0..1 traversal around an offset of 0.5.
#    Modulation is PHASE modulation: phi(t)=2*pi*f*t + beta*sin(2*pi*fm*t).
# ==============================================================================
sound_dummy = Create Sound from formula: "terrain_timebase", 1, 0, duration_s, sample_rate_Hz, "0"

selectObject: sound_dummy
x_traj = Copy: "terrain_x"
if x_trajectory = 1
    Formula: "x_offset + 0.5*x_span*sin(2*pi*x_frequency_Hz*x + x_phase_deg*pi/180 + phase_mod_index_rad*sin(2*pi*x_phase_mod_rate_Hz*x))"
elsif x_trajectory = 2
    Formula: "x_offset + 0.5*x_span*(2*abs(2*((x*x_frequency_Hz + x_phase_deg/360 + phase_mod_index_rad/(2*pi)*sin(2*pi*x_phase_mod_rate_Hz*x)) mod 1)-1)-1)"
elsif x_trajectory = 3
    Formula: "x_offset + 0.5*x_span*(2*((x*x_frequency_Hz + x_phase_deg/360 + phase_mod_index_rad/(2*pi)*sin(2*pi*x_phase_mod_rate_Hz*x)) mod 1)-1)"
elsif x_trajectory = 4
    Formula: "x_offset + 0.5*x_span*(if ((x*x_frequency_Hz + x_phase_deg/360 + phase_mod_index_rad/(2*pi)*sin(2*pi*x_phase_mod_rate_Hz*x)) mod 1) < 0.5 then 1 else -1 fi)"
endif

selectObject: sound_dummy
y_traj = Copy: "terrain_y"
if y_trajectory = 1
    Formula: "y_offset + 0.5*y_span*sin(2*pi*y_frequency_Hz*x + y_phase_deg*pi/180 + phase_mod_index_rad*sin(2*pi*y_phase_mod_rate_Hz*x))"
elsif y_trajectory = 2
    Formula: "y_offset + 0.5*y_span*(2*abs(2*((x*y_frequency_Hz + y_phase_deg/360 + phase_mod_index_rad/(2*pi)*sin(2*pi*y_phase_mod_rate_Hz*x)) mod 1)-1)-1)"
elsif y_trajectory = 3
    Formula: "y_offset + 0.5*y_span*(2*((x*y_frequency_Hz + y_phase_deg/360 + phase_mod_index_rad/(2*pi)*sin(2*pi*y_phase_mod_rate_Hz*x)) mod 1)-1)"
elsif y_trajectory = 4
    Formula: "y_offset + 0.5*y_span*(if ((x*y_frequency_Hz + y_phase_deg/360 + phase_mod_index_rad/(2*pi)*sin(2*pi*y_phase_mod_rate_Hz*x)) mod 1) < 0.5 then 1 else -1 fi)"
endif

selectObject: x_traj
x_min = Get minimum: 0, 0, "None"
x_max = Get maximum: 0, 0, "None"
selectObject: y_traj
y_min = Get minimum: 0, 0, "None"
y_max = Get maximum: 0, 0, "None"

# Convert continuous normalized coordinates into continuous matrix indices.
selectObject: x_traj
x_index = Copy: "terrain_x_index"
Formula: "1 + self*(tsize-1)"
selectObject: y_traj
y_index = Copy: "terrain_y_index"
Formula: "1 + self*(tsize-1)"

# Matrices needed by the vectorized bilinear gather.
selectObject: x_index
x0_matrix = Down to Matrix
Formula: "floor(self)"
selectObject: x_index
xfrac_matrix = Down to Matrix
Formula: "self-floor(self)"
selectObject: y_index
y0_matrix = Down to Matrix
Formula: "floor(self)"
selectObject: y_index
yfrac_matrix = Down to Matrix
Formula: "self-floor(self)"

# ==============================================================================
# 3. BILINEAR TERRAIN LOOKUP
# ==============================================================================
selectObject: sound_dummy
output = Copy: "waveTerrain_work"
appendInfoLine: "Sampling terrain with bilinear interpolation..."

selectObject: output
Formula: "(1-object[xfrac_matrix,1,col])*(1-object[yfrac_matrix,1,col])*object[terrain, object[y0_matrix,1,col], object[x0_matrix,1,col]] + object[xfrac_matrix,1,col]*(1-object[yfrac_matrix,1,col])*object[terrain, object[y0_matrix,1,col], min(tsize,object[x0_matrix,1,col]+1)] + (1-object[xfrac_matrix,1,col])*object[yfrac_matrix,1,col]*object[terrain, min(tsize,object[y0_matrix,1,col]+1), object[x0_matrix,1,col]] + object[xfrac_matrix,1,col]*object[yfrac_matrix,1,col]*object[terrain, min(tsize,object[y0_matrix,1,col]+1), min(tsize,object[x0_matrix,1,col]+1)]"

# Keep the raw terrain-height signal for the process visualization.
selectObject: output
raw_output = Copy: "terrain_sampled_height"
raw_rms = Get root-mean-square: 0, 0

# ==============================================================================
# 4. OUTPUT CONDITIONING
# ==============================================================================
selectObject: output
Subtract mean
pre_scale_max = Get maximum: 0, 0, "None"
pre_scale_min = Get minimum: 0, 0, "None"
pre_scale_peak = max(abs(pre_scale_max), abs(pre_scale_min))
if pre_scale_peak > 0
    Scale peak: output_peak
endif
Rename: "waveTerrain_" + terrain_name$
outputSound = selected("Sound")

output_max = Get maximum: 0, 0, "None"
output_min = Get minimum: 0, 0, "None"
output_peak_measured = max(abs(output_max), abs(output_min))
output_rms = Get root-mean-square: 0, 0

if draw_visualization
    @drawVisualization
endif

# Cleanup auxiliaries, preserve final Sound only.
removeObject: sound_dummy, x_index, y_index, x0_matrix, xfrac_matrix, y0_matrix, yfrac_matrix, raw_output, x_traj, y_traj, terrain

appendInfoLine: ""
appendInfoLine: "=== QC ==="
appendInfoLine: "Terrain range after centering/normalization: ", fixed$(terrain_min, 3), " .. ", fixed$(terrain_max, 3)
appendInfoLine: "X range: ", fixed$(x_min, 3), " .. ", fixed$(x_max, 3), " | Y range: ", fixed$(y_min, 3), " .. ", fixed$(y_max, 3)
appendInfoLine: "Raw terrain-height RMS: ", fixed$(raw_rms, 4)
appendInfoLine: "Output peak: ", fixed$(output_peak_measured, 4), " | RMS: ", fixed$(output_rms, 4)
appendInfoLine: "Note: nonlinear terrain scanning is not strictly band-limited; bright/discontinuous paths benefit from higher sample rates."
appendInfoLine: ""
appendInfoLine: "=== Done ==="
selectObject: outputSound
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    selectObject: outputSound
    Play
endif

# ==============================================================================
# Procedure: drawVisualization
# PROCESS view: terrain+path -> x/y controls -> sampled terrain height -> output.
# ==============================================================================
procedure drawVisualization
    Erase all

    .slow_rate = min(x_frequency_Hz, y_frequency_Hz)
    .path_window = min(duration_s, max(0.03, min(0.5, 2/.slow_rate)))
    .path_points = 240

    # ----- Title strip -----
    Select outer viewport: 0, 8, 0.08, 0.48
    Select inner viewport: 0, 8, 0.08, 0.48
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "Wave Terrain Synthesis: " + terrain_name$

    # ----- Process strip -----
    Select outer viewport: 0, 8, 0.50, 0.88
    Select inner viewport: 0, 8, 0.50, 0.88
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.28,0.28,0.34}"
    Text: 0.5, "centre", 0.55, "half", "terrain z(x,y)  ->  bounded x(t), y(t)  ->  bilinear sample z[x(t),y(t)]  ->  DC removal / peak scale  ->  output"

    # ==========================================================================
    # A. Terrain + actual trajectory excerpt
    # ==========================================================================
    Select outer viewport: 0, 4.7, 1.02, 3.72
    Select inner viewport: 0.55, 4.45, 1.25, 3.45
    Axes: 0, 1, 0, 1
    selectObject: terrain
    Paint image: 0, 1, 0, 1, -1, 1

    # Draw the actual trajectory excerpt on the same terrain coordinates.
    # Sound sample centres run from the first sample time to the last sample
    # time, not from xmin=0 to xmax=duration exactly.  Clamp all manual
    # Get-value queries to that valid sample-centre interval; otherwise Praat
    # may return undefined at t=0 or exactly t=duration.
    selectObject: x_traj
    .nx = Get number of samples
    .first_t = Get time from sample number: 1
    .last_t = Get time from sample number: .nx
    .prevx = Get value at time: .first_t, "Linear"
    selectObject: y_traj
    .prevy = Get value at time: .first_t, "Linear"
    Colour: "White"
    Line width: 2
    for .k from 1 to .path_points
        .tt = .path_window * .k / .path_points
        if .tt < .first_t
            .query_t = .first_t
        elsif .tt > .last_t
            .query_t = .last_t
        else
            .query_t = .tt
        endif
        selectObject: x_traj
        .xv = Get value at time: .query_t, "Linear"
        selectObject: y_traj
        .yv = Get value at time: .query_t, "Linear"
        Draw line: .prevx, .prevy, .xv, .yv
        .prevx = .xv
        .prevy = .yv
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks bottom: 2, "yes", "yes", "no"
    Marks left: 2, "yes", "yes", "no"

    Select outer viewport: 0, 4.7, 0.94, 1.18
    Select inner viewport: 0, 4.7, 0.94, 1.18
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "A  Terrain surface + actual trajectory excerpt"

    # ==========================================================================
    # B. X/Y trajectory controls over the SAME excerpt
    # ==========================================================================
    Select outer viewport: 4.75, 8, 1.02, 3.72
    Select inner viewport: 5.20, 7.75, 1.25, 3.45
    Axes: 0, .path_window, 0, 1
    Colour: "{0.20,0.45,0.68}"
    selectObject: x_traj
    Draw: 0, .path_window, 0, 1, "no", "Curve"
    Colour: "{0.72,0.34,0.22}"
    selectObject: y_traj
    Draw: 0, .path_window, 0, 1, "no", "Curve"
    Select inner viewport: 5.20, 7.75, 1.25, 3.45
    Axes: 0, .path_window, 0, 1
    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    Marks left: 2, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Normalized position"

    Select outer viewport: 4.75, 8, 0.94, 1.18
    Select inner viewport: 4.75, 8, 0.94, 1.18
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "B  Trajectory controls: x(t) and y(t)"

    # Legend strip for B
    Select outer viewport: 5.0, 7.9, 3.50, 3.72
    Select inner viewport: 5.0, 7.9, 3.50, 3.72
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.20,0.45,0.68}"
    Text: 0.34, "centre", 0.5, "half", "x(t)"
    Colour: "{0.72,0.34,0.22}"
    Text: 0.66, "centre", 0.5, "half", "y(t)"

    # ----- Bilinear equation strip -----
    Select outer viewport: 0, 8, 3.80, 4.16
    Select inner viewport: 0, 8, 3.80, 4.16
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.30,0.30,0.34}"
    Text: 0.5, "centre", 0.55, "half", "bilinear lookup: z = (1-a)(1-b)z00 + a(1-b)z10 + (1-a)b z01 + ab z11"

    # ==========================================================================
    # C. Sampled terrain height vs final conditioned output (same excerpt)
    # ==========================================================================
    Select outer viewport: 0, 8, 4.25, 5.32
    Select inner viewport: 0.70, 7.65, 4.45, 5.12
    Axes: 0, .path_window, -1, 1
    Colour: "{0.60,0.60,0.60}"
    selectObject: raw_output
    Draw: 0, .path_window, -1, 1, "no", "Curve"
    Colour: "{0.18,0.42,0.65}"
    selectObject: outputSound
    Draw: 0, .path_window, -1, 1, "no", "Curve"
    Select inner viewport: 0.70, 7.65, 4.45, 5.12
    Axes: 0, .path_window, -1, 1
    Colour: "Black"
    Draw inner box
    Marks left: 2, "yes", "yes", "no"
    Marks bottom: 3, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 4.17, 4.40
    Select inner viewport: 0, 8, 4.17, 4.40
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "C  Terrain height sampled along the path -> conditioned audio"

    # ==========================================================================
    # D. Full measured output
    # ==========================================================================
    Select outer viewport: 0, 8, 5.45, 6.22
    Select inner viewport: 0.70, 7.65, 5.62, 6.08
    selectObject: outputSound
    Colour: "{0.18,0.42,0.65}"
    Draw: 0, duration_s, -1, 1, "no", "Curve"
    Select inner viewport: 0.70, 7.65, 5.62, 6.08
    Axes: 0, duration_s, -1, 1
    Colour: "Black"
    Draw inner box
    Marks bottom: 4, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 5.35, 5.58
    Select inner viewport: 0, 8, 5.35, 5.58
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "D  Measured output"

    # ==========================================================================
    # QC: two rows x three independent text cells
    # ==========================================================================
    .qc1$ = terrain_name$ + " | " + string$(tsize) + "x" + string$(tsize) + " | bilinear"
    .qc2$ = "X " + x_name$ + " " + fixed$(x_frequency_Hz,1) + " Hz | span " + fixed$(x_span,2)
    .qc3$ = "Y " + y_name$ + " " + fixed$(y_frequency_Hz,1) + " Hz | span " + fixed$(y_span,2)
    .qc4$ = "phase mod beta=" + fixed$(phase_mod_index_rad,2) + " rad | " + fixed$(x_phase_mod_rate_Hz,2) + "/" + fixed$(y_phase_mod_rate_Hz,2) + " Hz"
    .qc5$ = "raw RMS " + fixed$(raw_rms,3) + " | fs " + fixed$(sample_rate_Hz,0) + " Hz"
    .qc6$ = "output peak " + fixed$(output_peak_measured,3) + " | RMS " + fixed$(output_rms,3)

    .cellW = 8/3
    for .r from 0 to 1
        for .c from 0 to 2
            .idx = .r*3 + .c + 1
            .x1 = .c*.cellW
            .x2 = (.c+1)*.cellW
            .y1 = 6.35 + .r*0.34
            .y2 = .y1 + 0.30
            Select outer viewport: .x1, .x2, .y1, .y2
            Select inner viewport: .x1, .x2, .y1, .y2
            Axes: 0, 1, 0, 1
            Paint rectangle: "{0.95,0.95,0.95}", 0, 1, 0, 1
            Colour: "{0.30,0.30,0.30}"
            Font size: 7
            if .idx = 1
                Text: 0.5, "centre", 0.5, "half", .qc1$
            elsif .idx = 2
                Text: 0.5, "centre", 0.5, "half", .qc2$
            elsif .idx = 3
                Text: 0.5, "centre", 0.5, "half", .qc3$
            elsif .idx = 4
                Text: 0.5, "centre", 0.5, "half", .qc4$
            elsif .idx = 5
                Text: 0.5, "centre", 0.5, "half", .qc5$
            else
                Text: 0.5, "centre", 0.5, "half", .qc6$
            endif
        endfor
    endfor

    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
