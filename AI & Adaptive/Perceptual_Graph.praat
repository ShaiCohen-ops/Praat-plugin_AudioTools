# ============================================================
# Praat AudioTools - Perceptual_Graph_Explorer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Perceptual Graph Explorer - treats sound as a temporal graph
#   where time frames are projected into a 3D perceptual space
#   (Energy, Stability, Brightness). Clusters similar textures
#   and separates them into independent audio streams.
#
# Features v3.0:
#   - 3D Isometric scatter plot
#   - Convex hull visualization for clusters
#   - Cluster transition matrix
#   - Fixed audio scaling for all clusters
#   - Enhanced cluster colors
#
# Changelog v3.2 (2026):
#   - FIX (audible): montage fragments were full-length Hanning
#     windows placed with only Overlap_time_ms (5 ms) of overlap --
#     at every junction BOTH windows are near zero, stamping a deep
#     ~22 Hz amplitude dip across the whole montage (v3.0's
#     Concatenate path had the same double-taper flaw; v3.1 was
#     faithfully equivalent to it). v3.2 places fragments at 50%
#     Hann overlap-add: the window sum is exactly 1, junctions are
#     seamless, and -- since every preset's analysis step is half
#     the window -- contiguous same-cluster runs reconstruct the
#     source EXACTLY. Each cluster's montage duration now also
#     approximates the time that cluster occupies in the source.
#     Overlap_time_ms is deprecated (kept in the form for argument
#     compatibility; ignored, with an info note).
#   - FIX: the analysis grid started at t = step, skipping the
#     first frame of audio entirely; it now starts at t = 0.
#   - FIX: the info header erased itself (three consecutive
#     writeInfoLine calls -- each clears the Info window).
#   - FIX: the final "select all created sounds" ran BEFORE the
#     per-sound info loop, whose selectObject clobbered it -- the
#     script always ended with only the last cluster selected. The
#     multi-selection now happens last.
#   - VIZ: title strip uses an explicit inner viewport (the
#     outer-only form let font margins compress the mapping and
#     collide the two text lines).
#
# Changelog v3.1 (2026):
#   - PORTABILITY: The k-means convergence loop terminated early
#     by mutating its own iteration counter (iteration =
#     max_iterations) at line 361. v3.1 uses the standard "converged"
#     flag pattern that wraps the loop body — same behavior, no
#     loop-var mutation. Fragile across Praat versions.
#   - SPEED: Replaced Concatenate-in-loop cluster audio synthesis
#     with pre-allocated buffer + Formula (part) overlap-add.
#     v3.0's Concatenate-with-overlap inside the per-cluster loop
#     was O(N^2): each iteration rebuilt the entire growing buffer.
#     v3.1 pre-computes the total duration, allocates a zero-filled
#     Sound, then writes each Hanning-windowed fragment via a
#     Formula (part) at its calculated offset. Mathematically
#     equivalent (same Hanning OLA), much faster on long inputs.
#     For 200+ frames per cluster, runtime drops from O(N^2 * L)
#     to O(N * L) where L is window length.
#   - CLEANUP: Removed an unused whole-input Spectrum allocation
#     (was created and immediately removed without being read,
#     dead code from a previous version).
# ============================================================

form Perceptual Graph Explorer v3.2
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option 2 Clusters - Basic Split
        option 3 Clusters - Detailed
        option 4 Clusters - Fine Analysis
        option 5 Clusters - Very Fine
    
    comment === Analysis Parameters ===
    positive Window_length_ms 50
    positive Step_size_ms 25
    natural Number_of_clusters 3
    
    comment === Smoothing ===
    comment (Overlap_time is deprecated since v3.2: placement is 50% Hann OLA)
    positive Overlap_time_ms 5
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# Check Selection
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSoundID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalSoundID
duration = Get total duration
sr = Get sampling frequency

# ============================================================
# Apply Presets
# ============================================================
if preset = 2
    number_of_clusters = 2
    window_length_ms = 60
    step_size_ms = 30
    presetName$ = "Basic_2"
elsif preset = 3
    number_of_clusters = 3
    window_length_ms = 50
    step_size_ms = 25
    presetName$ = "Detailed_3"
elsif preset = 4
    number_of_clusters = 4
    window_length_ms = 40
    step_size_ms = 20
    presetName$ = "Fine_4"
elsif preset = 5
    number_of_clusters = 5
    window_length_ms = 35
    step_size_ms = 18
    presetName$ = "VeryFine_5"
else
    presetName$ = "Custom"
endif

# Convert to seconds
window_length = window_length_ms / 1000
step_size = step_size_ms / 1000
overlap_time = overlap_time_ms / 1000

# Define cluster colors (up to 8 clusters)
clusterColor$[1] = "{0.85, 0.35, 0.35}"
clusterColor$[2] = "{0.35, 0.55, 0.85}"
clusterColor$[3] = "{0.35, 0.75, 0.45}"
clusterColor$[4] = "{0.85, 0.65, 0.25}"
clusterColor$[5] = "{0.65, 0.35, 0.75}"
clusterColor$[6] = "{0.25, 0.75, 0.75}"
clusterColor$[7] = "{0.75, 0.55, 0.65}"
clusterColor$[8] = "{0.55, 0.65, 0.45}"

# Lighter versions for fills
clusterColorLight$[1] = "{0.95, 0.75, 0.75}"
clusterColorLight$[2] = "{0.75, 0.85, 0.95}"
clusterColorLight$[3] = "{0.75, 0.92, 0.8}"
clusterColorLight$[4] = "{0.95, 0.88, 0.7}"
clusterColorLight$[5] = "{0.88, 0.75, 0.92}"
clusterColorLight$[6] = "{0.7, 0.92, 0.92}"
clusterColorLight$[7] = "{0.92, 0.82, 0.88}"
clusterColorLight$[8] = "{0.82, 0.88, 0.78}"

clearinfo
writeInfoLine: "=============================================="
appendInfoLine: "  PERCEPTUAL GRAPH EXPLORER v3.2"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "STEP 1: Extracting Feature Nodes..."

# ============================================================
# STEP 1: MULTI-DIMENSIONAL FEATURE EXTRACTION
# ============================================================

# 1. Dimension A: ENERGY (Intensity)
selectObject: originalSoundID
To Intensity: 100, 0, "yes"
intensityID = selected("Intensity")

# 2. Dimension B: STABILITY (Harmonicity)
selectObject: originalSoundID
To Harmonicity (cc): 0.01, 75, 0.1, 1.0
harmonicityID = selected("Harmonicity")

# v3.1: removed unused whole-input Spectrum allocation.
# v3.0 created a Spectrum here but never read from it before
# removing — dead code from a previous version. Per-frame
# spectral centroid is computed below via per-frame Extract +
# To Spectrum + Get centre of gravity.

# Prepare Data Table
# v3.2: grid starts at t = 0 (the old i*step grid skipped the
# first frame of audio entirely)
numFrames = floor((duration - window_length) / step_size) + 1
if numFrames < number_of_clusters
    removeObject: intensityID, harmonicityID
    exitScript: "Audio too short for ", number_of_clusters, " clusters. Reduce clusters or use longer audio."
endif

Create Table with column names: "nodes", numFrames, "time energy stability brightness cluster"
tableID = selected("Table")

# 4. Populate Nodes
for i from 1 to numFrames
    t = (i - 1) * step_size
    t_center = t + window_length / 2
    
    # --- Get Energy ---
    selectObject: intensityID
    en = Get value at time: t_center, "cubic"
    if en = undefined
        en = 50
    endif
    
    # --- Get Stability ---
    selectObject: harmonicityID
    stab = Get value at time: t_center, "cubic"
    if stab = undefined
        stab = 0
    endif
    
    # --- Get Brightness (Spectral Centroid) ---
    selectObject: originalSoundID
    Extract part: t, t + window_length, "rectangular", 1, "no"
    tempSound = selected("Sound")
    To Spectrum: "yes"
    tempSpec = selected("Spectrum")
    bright = Get centre of gravity: 2
    removeObject: tempSound, tempSpec
    
    if bright = undefined
        bright = 1000
    endif
    
    # Save to Table
    selectObject: tableID
    Set numeric value: i, "time", t
    Set numeric value: i, "energy", en
    Set numeric value: i, "stability", stab
    Set numeric value: i, "brightness", bright
endfor

removeObject: intensityID, harmonicityID

appendInfoLine: "  Extracted ", numFrames, " feature nodes"

# ============================================================
# STEP 2: NORMALIZATION
# ============================================================
appendInfoLine: ""
appendInfoLine: "STEP 2: Constructing Graph Space..."

selectObject: tableID

# Store original ranges for display
min_en_orig = Get minimum: "energy"
max_en_orig = Get maximum: "energy"
min_st_orig = Get minimum: "stability"
max_st_orig = Get maximum: "stability"
min_br_orig = Get minimum: "brightness"
max_br_orig = Get maximum: "brightness"

# Normalize Energy
min_en = min_en_orig
max_en = max_en_orig
if max_en > min_en
    Formula: "energy", "(self - min_en) / (max_en - min_en)"
else
    Formula: "energy", "0.5"
endif

# Normalize Stability
min_st = min_st_orig
max_st = max_st_orig
if max_st > min_st
    Formula: "stability", "(self - min_st) / (max_st - min_st)"
else
    Formula: "stability", "0.5"
endif

# Normalize Brightness
min_br = min_br_orig
max_br = max_br_orig
if max_br > min_br
    Formula: "brightness", "(self - min_br) / (max_br - min_br)"
else
    Formula: "brightness", "0.5"
endif

appendInfoLine: "  Energy range: ", fixed$(min_en_orig, 1), " - ", fixed$(max_en_orig, 1), " dB"
appendInfoLine: "  Stability range: ", fixed$(min_st_orig, 1), " - ", fixed$(max_st_orig, 1)
appendInfoLine: "  Brightness range: ", fixed$(min_br_orig, 0), " - ", fixed$(max_br_orig, 0), " Hz"

# ============================================================
# STEP 3: IMPROVED K-MEANS CLUSTERING
# ============================================================
appendInfoLine: ""
appendInfoLine: "STEP 3: Detecting Communities (k-means)..."

# Initialize centroids using k-means++ style
selectObject: tableID

# First centroid: random
rand_idx = randomInteger(1, numFrames)
cent_en[1] = Get value: rand_idx, "energy"
cent_st[1] = Get value: rand_idx, "stability"
cent_br[1] = Get value: rand_idx, "brightness"

# Remaining centroids: choose far from existing
for k from 2 to number_of_clusters
    maxMinDist = 0
    bestIdx = 1
    
    for i from 1 to numFrames
        selectObject: tableID
        val_e = Get value: i, "energy"
        val_s = Get value: i, "stability"
        val_b = Get value: i, "brightness"
        
        # Find distance to nearest existing centroid
        minDist = 1000
        for j from 1 to k - 1
            de = val_e - cent_en[j]
            ds = val_s - cent_st[j]
            db = val_b - cent_br[j]
            dist = sqrt(de*de + ds*ds + db*db)
            if dist < minDist
                minDist = dist
            endif
        endfor
        
        if minDist > maxMinDist
            maxMinDist = minDist
            bestIdx = i
        endif
    endfor
    
    selectObject: tableID
    cent_en[k] = Get value: bestIdx, "energy"
    cent_st[k] = Get value: bestIdx, "stability"
    cent_br[k] = Get value: bestIdx, "brightness"
endfor

# Converge with threshold
max_iterations = 30
threshold = 0.001
converged = 0

# v3.1: Replaced "iteration = max_iterations" loop-var mutation with
# the standard "converged" flag pattern. Once converged, the rest
# of the loop iterations are guarded no-ops.
for iteration from 1 to max_iterations
    if converged = 0
        # Assign points to nearest centroid
        selectObject: tableID
        for i from 1 to numFrames
            val_e = Get value: i, "energy"
            val_s = Get value: i, "stability"
            val_b = Get value: i, "brightness"
            
            min_dist = 1000
            best_k = 1
            
            for k from 1 to number_of_clusters
                de = val_e - cent_en[k]
                ds = val_s - cent_st[k]
                db = val_b - cent_br[k]
                dist = sqrt(de*de + ds*ds + db*db)
                
                if dist < min_dist
                    min_dist = dist
                    best_k = k
                endif
            endfor
            
            selectObject: tableID
            Set numeric value: i, "cluster", best_k
        endfor
        
        # Store old centroids
        for k from 1 to number_of_clusters
            old_en[k] = cent_en[k]
            old_st[k] = cent_st[k]
            old_br[k] = cent_br[k]
        endfor
        
        # Update centroids
        for k from 1 to number_of_clusters
            selectObject: tableID
            Extract rows where column (number): "cluster", "equal to", k
            tempID = selected("Table")
            nRows = Get number of rows
            
            if nRows > 0
                cent_en[k] = Get mean: "energy"
                cent_st[k] = Get mean: "stability"
                cent_br[k] = Get mean: "brightness"
            endif
            removeObject: tempID
        endfor
        
        # Check convergence
        max_shift = 0
        for k from 1 to number_of_clusters
            shift = sqrt((cent_en[k] - old_en[k])^2 + (cent_st[k] - old_st[k])^2 + (cent_br[k] - old_br[k])^2)
            if shift > max_shift
                max_shift = shift
            endif
        endfor
        
        if max_shift < threshold
            converged = 1
            appendInfoLine: "  Converged after ", iteration, " iterations"
        endif
    endif
endfor

if converged = 0
    appendInfoLine: "  Reached max iterations (", max_iterations, ")"
endif

# ============================================================
# STEP 4: CLUSTER CHARACTERIZATION & HULL COMPUTATION
# ============================================================
appendInfoLine: ""
appendInfoLine: "STEP 4: Characterizing Clusters..."

for k from 1 to number_of_clusters
    selectObject: tableID
    Extract rows where column (number): "cluster", "equal to", k
    clusterTable = selected("Table")
    nPoints = Get number of rows
    
    if nPoints > 0
        avg_e = Get mean: "energy"
        avg_s = Get mean: "stability"
        avg_b = Get mean: "brightness"
        
        # Get bounding box for hull approximation
        hull_min_e[k] = Get minimum: "energy"
        hull_max_e[k] = Get maximum: "energy"
        hull_min_s[k] = Get minimum: "stability"
        hull_max_s[k] = Get maximum: "stability"
        hull_min_b[k] = Get minimum: "brightness"
        hull_max_b[k] = Get maximum: "brightness"
        
        # Characterize cluster
        label$ = "C" + string$(k)
        
        if avg_e > 0.66
            label$ = label$ + "_Loud"
        elsif avg_e < 0.33
            label$ = label$ + "_Quiet"
        else
            label$ = label$ + "_Mid"
        endif
        
        if avg_s > 0.66
            label$ = label$ + "_Tonal"
        elsif avg_s < 0.33
            label$ = label$ + "_Noisy"
        endif
        
        if avg_b > 0.66
            label$ = label$ + "_Bright"
        elsif avg_b < 0.33
            label$ = label$ + "_Dark"
        endif
        
        clusterLabel$[k] = label$
        clusterSize[k] = nPoints
        clusterEnergy[k] = avg_e
        clusterStability[k] = avg_s
        clusterBrightness[k] = avg_b
        
        appendInfoLine: "  ", label$, ": ", nPoints, " frames (", fixed$(nPoints / numFrames * 100, 1), "%)"
        appendInfoLine: "    E=", fixed$(avg_e, 2), " S=", fixed$(avg_s, 2), " B=", fixed$(avg_b, 2)
    else
        clusterLabel$[k] = "C" + string$(k) + "_Empty"
        clusterSize[k] = 0
        hull_min_e[k] = 0.5
        hull_max_e[k] = 0.5
        hull_min_s[k] = 0.5
        hull_max_s[k] = 0.5
        hull_min_b[k] = 0.5
        hull_max_b[k] = 0.5
    endif
    
    removeObject: clusterTable
endfor

# ============================================================
# STEP 5: CLUSTER TRANSITION MATRIX
# ============================================================
appendInfoLine: ""
appendInfoLine: "STEP 5: Computing Transition Matrix..."

# Initialize transition matrix
for i from 1 to number_of_clusters
    for j from 1 to number_of_clusters
        transitionCount[i, j] = 0
    endfor
endfor

# Count transitions
selectObject: tableID
prevCluster = Get value: 1, "cluster"

for i from 2 to numFrames
    selectObject: tableID
    currCluster = Get value: i, "cluster"
    
    transitionCount[prevCluster, currCluster] += 1
    prevCluster = currCluster
endfor

# Calculate transition probabilities and find max for display
maxTransition = 0
totalTransitions = numFrames - 1

for i from 1 to number_of_clusters
    rowSum = 0
    for j from 1 to number_of_clusters
        rowSum += transitionCount[i, j]
    endfor
    
    for j from 1 to number_of_clusters
        if rowSum > 0
            transitionProb[i, j] = transitionCount[i, j] / rowSum
        else
            transitionProb[i, j] = 0
        endif
        
        if transitionCount[i, j] > maxTransition
            maxTransition = transitionCount[i, j]
        endif
    endfor
endfor

# Display transition matrix
appendInfoLine: ""
appendInfoLine: "  Transition Matrix (probabilities):"
appendInfoLine: ""

# Header
header$ = "       "
for j from 1 to number_of_clusters
    header$ = header$ + "  C" + string$(j) + "   "
endfor
appendInfoLine: header$

for i from 1 to number_of_clusters
    row$ = "  C" + string$(i) + " "
    for j from 1 to number_of_clusters
        row$ = row$ + " " + fixed$(transitionProb[i, j], 2) + " "
    endfor
    appendInfoLine: row$
endfor

# ============================================================
# STEP 6: SMOOTH AUDIO GENERATION (FIXED SCALING)
# ============================================================
appendInfoLine: ""
appendInfoLine: "STEP 6: Generating Audio Layers..."

soundsCreated = 0
for k from 1 to number_of_clusters
    if clusterSize[k] > 0
        selectObject: tableID
        Extract rows where column (number): "cluster", "equal to", k
        clusterTableID = selected("Table")
        nRows = Get number of rows
        
        # v3.1: pre-allocated buffer + Formula (part) OLA instead of
        # Concatenate-in-loop. v3.0's "Concatenate with overlap"
        # called inside the per-fragment loop rebuilt the entire
        # growing buffer each iteration (O(N^2)). v3.1 computes the
        # total destination length, allocates a zero-filled Sound,
        # and writes each Hanning-windowed fragment via
        # Formula (part) at its calculated offset. Mathematically
        # equivalent (same Hanning OLA) at O(N) cost.
        
        # v3.2: fragments are placed at 50% Hann overlap-add. Hann
        # windows at half-window hops sum to exactly 1, so junctions
        # are seamless (the old Overlap_time_ms placement left both
        # windows near zero at every junction: a deep ~22 Hz dip
        # stamped across the montage). Since every preset's analysis
        # step is half the window, contiguous same-cluster runs
        # reconstruct the source EXACTLY, and the montage duration
        # approximates the time the cluster occupies in the source.
        # Overlap_time_ms is deprecated and ignored.
        frag_samples = round(window_length * sr)
        step_samples = round(frag_samples / 2)
        if step_samples < 1
            step_samples = 1
        endif
        total_samples = frag_samples + (nRows - 1) * step_samples
        total_dur = total_samples / sr
        
        if nRows = 1
            # Single fragment: no concatenation needed.
            selectObject: clusterTableID
            t1 = Get value: 1, "time"
            selectObject: originalSoundID
            Extract part: t1, t1 + window_length, "Hanning", 1, "no"
            Rename: clusterLabel$[k]
            finalSound = selected("Sound")
        else
            # Pre-allocate destination at sr (matches originalSound's sr).
            finalSound = Create Sound from formula: clusterLabel$[k],
                ... 1, 0, total_dur, sr, "0"
            
            # Place each Hanning-windowed fragment via Formula (part).
            # Fragment r writes into samples [(r-1)*step+1 .. (r-1)*step+L].
            for r from 1 to nRows
                selectObject: clusterTableID
                t = Get value: r, "time"
                
                selectObject: originalSoundID
                Extract part: t, t + window_length, "Hanning", 1, "no"
                frag = selected("Sound")
                
                offset_samples = (r - 1) * step_samples
                offset_sec = offset_samples / sr
                # Formula reads frag at col-offset_samples
                fragStr$ = string$(frag)
                offsetStr$ = string$(offset_samples)
                
                selectObject: finalSound
                Formula (part): offset_sec, offset_sec + window_length, 1, 1,
                    ... "self + object[" + fragStr$ + ", 1, col - " + offsetStr$ + "]"
                
                removeObject: frag
            endfor
            
            selectObject: finalSound
            Rename: clusterLabel$[k]
        endif
        
        # === FIX: Scale each cluster sound to target peak ===
        selectObject: finalSound
        Scale peak: scale_peak
        
        soundsCreated += 1
        createdSounds[soundsCreated] = finalSound
        createdLabels$[soundsCreated] = clusterLabel$[k]
        createdCluster[soundsCreated] = k
        
        # Get duration for info
        selectObject: finalSound
        finalDur = Get total duration
        appendInfoLine: "  ", clusterLabel$[k], ": ", fixed$(finalDur, 2), " s"
        
        removeObject: clusterTableID
    endif
endfor

# ============================================================
# STEP 7: VISUALIZATION
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "STEP 7: Creating Visualization..."
    
    Erase all
    
    # === TITLE ===
    # v3.2: explicit inner viewport == outer strip (outer-only form
    # lets font-size margins compress the mapping; the two text
    # lines collided)
    Select outer viewport: 0, 8, 0, 0.6
    Select inner viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Perceptual Graph Explorer v3.2## | " + originalName$
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.28, "half", presetName$ + " | " + string$(number_of_clusters) + " clusters | " + string$(numFrames) + " frames"
    
    # === 3D ISOMETRIC SCATTER PLOT ===
    Select outer viewport: 0, 4.5, 0.7, 3.7
    Select inner viewport: 0.4, 4.3, 0.8, 3.6
    
    # Isometric projection parameters
    # X-axis: Energy (horizontal right)
    # Y-axis: Stability (horizontal left)
    # Z-axis: Brightness (vertical)
    
    isoAngle = 30 * pi / 180
    cosA = cos(isoAngle)
    sinA = sin(isoAngle)
    
    # Projection functions (inline calculations)
    # proj_x = x * cos(30) - y * cos(30) = (x - y) * cos(30)
    # proj_y = x * sin(30) + y * sin(30) + z = (x + y) * sin(30) + z
    
    # Calculate plot bounds
    plotMinX = -1.2
    plotMaxX = 1.2
    plotMinY = -0.3
    plotMaxY = 1.8
    
    Axes: plotMinX, plotMaxX, plotMinY, plotMaxY
    
    # Background
    Paint rectangle: "{0.96, 0.96, 0.97}", plotMinX, plotMaxX, plotMinY, plotMaxY
    
    # Draw 3D axes
    Colour: "{0.6, 0.6, 0.65}"
    Line width: 1
    
    # Origin at (0,0,0) -> projected
    ox = 0
    oy = 0
    
    # X-axis (Energy): from origin to (1,0,0)
    ax_x = 1 * cosA
    ax_y = 1 * sinA
    Draw arrow: ox, oy, ax_x, ax_y
    
    # Y-axis (Stability): from origin to (0,1,0)
    ay_x = -1 * cosA
    ay_y = 1 * sinA
    Draw arrow: ox, oy, ay_x, ay_y
    
    # Z-axis (Brightness): from origin to (0,0,1)
    az_x = 0
    az_y = 1
    Draw arrow: ox, oy, az_x, az_y
    
    # Axis labels
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: ax_x + 0.1, "left", ax_y, "half", "Energy"
    Text: ay_x - 0.1, "right", ay_y, "half", "Stability"
    Text: az_x, "centre", az_y + 0.1, "bottom", "Brightness"
    
    # Draw grid on floor (z=0 plane)
    Colour: "{0.88, 0.88, 0.9}"
    Line width: 0.5
    for g from 0 to 4
        gVal = g / 4
        # Lines parallel to X-axis
        x1 = gVal * cosA - 0 * cosA
        y1 = gVal * sinA + 0 * sinA
        x2 = gVal * cosA - 1 * cosA
        y2 = gVal * sinA + 1 * sinA
        Draw line: x1, y1, x2, y2
        
        # Lines parallel to Y-axis
        x1 = 0 * cosA - gVal * cosA
        y1 = 0 * sinA + gVal * sinA
        x2 = 1 * cosA - gVal * cosA
        y2 = 1 * sinA + gVal * sinA
        Draw line: x1, y1, x2, y2
    endfor
    
    # Draw convex hull approximations (bounding boxes projected)
    Line width: 1.5
    for k from 1 to number_of_clusters
        if clusterSize[k] > 0
            Colour: clusterColorLight$[k]
            
            # Get hull bounds
            e1 = hull_min_e[k]
            e2 = hull_max_e[k]
            s1 = hull_min_s[k]
            s2 = hull_max_s[k]
            b1 = hull_min_b[k]
            b2 = hull_max_b[k]
            
            # Draw bottom face (at b1)
            p1x = e1 * cosA - s1 * cosA
            p1y = e1 * sinA + s1 * sinA + b1
            p2x = e2 * cosA - s1 * cosA
            p2y = e2 * sinA + s1 * sinA + b1
            p3x = e2 * cosA - s2 * cosA
            p3y = e2 * sinA + s2 * sinA + b1
            p4x = e1 * cosA - s2 * cosA
            p4y = e1 * sinA + s2 * sinA + b1
            
            Dotted line
            Draw line: p1x, p1y, p2x, p2y
            Draw line: p2x, p2y, p3x, p3y
            Draw line: p3x, p3y, p4x, p4y
            Draw line: p4x, p4y, p1x, p1y
            
            # Draw top face (at b2)
            q1x = e1 * cosA - s1 * cosA
            q1y = e1 * sinA + s1 * sinA + b2
            q2x = e2 * cosA - s1 * cosA
            q2y = e2 * sinA + s1 * sinA + b2
            q3x = e2 * cosA - s2 * cosA
            q3y = e2 * sinA + s2 * sinA + b2
            q4x = e1 * cosA - s2 * cosA
            q4y = e1 * sinA + s2 * sinA + b2
            
            Draw line: q1x, q1y, q2x, q2y
            Draw line: q2x, q2y, q3x, q3y
            Draw line: q3x, q3y, q4x, q4y
            Draw line: q4x, q4y, q1x, q1y
            
            # Draw vertical edges
            Draw line: p1x, p1y, q1x, q1y
            Draw line: p2x, p2y, q2x, q2y
            Draw line: p3x, p3y, q3x, q3y
            Draw line: p4x, p4y, q4x, q4y
            Solid line
        endif
    endfor
    
    # Draw points
    selectObject: tableID
    for i from 1 to numFrames
        en = Get value: i, "energy"
        st = Get value: i, "stability"
        br = Get value: i, "brightness"
        cl = Get value: i, "cluster"
        
        # Project to 2D isometric
        px = en * cosA - st * cosA
        py = en * sinA + st * sinA + br
        
        # Draw point
        Colour: clusterColor$[cl]
        dotSize = 0.015
        Paint circle: clusterColor$[cl], px, py, dotSize
    endfor
    
    # Draw centroids
    Line width: 2
    for k from 1 to number_of_clusters
        if clusterSize[k] > 0
            cx = clusterEnergy[k] * cosA - clusterStability[k] * cosA
            cy = clusterEnergy[k] * sinA + clusterStability[k] * sinA + clusterBrightness[k]
            
            Colour: "Black"
            Paint circle: "White", cx, cy, 0.04
            Colour: clusterColor$[k]
            Draw circle: cx, cy, 0.04
            
            Font size: 8
            Text: cx, "centre", cy + 0.08, "bottom", "C" + string$(k)
        endif
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Font size: 8
    Text top: "no", "3D Perceptual Space (Isometric)"
    
    # === TRANSITION MATRIX HEATMAP ===
    Select outer viewport: 4.5, 8, 0.7, 3.7
    Select inner viewport: 5.0, 7.6, 1.0, 3.4
    
    Axes: 0, number_of_clusters, 0, number_of_clusters
    
    # Draw cells
    for i from 1 to number_of_clusters
        for j from 1 to number_of_clusters
            # Color intensity based on probability
            prob = transitionProb[i, j]
            
            # Interpolate color from white to cluster color
            if prob > 0
                intensity = prob
                r = 0.95 - intensity * 0.5
                g = 0.95 - intensity * 0.5
                b = 0.95 - intensity * 0.3
                cellColor$ = "{" + fixed$(r, 2) + "," + fixed$(g, 2) + "," + fixed$(b, 2) + "}"
            else
                cellColor$ = "{0.97, 0.97, 0.97}"
            endif
            
            Paint rectangle: cellColor$, j - 1, j, number_of_clusters - i, number_of_clusters - i + 1
            
            # Draw probability text
            if prob >= 0.1
                Colour: "Black"
            else
                Colour: "{0.6, 0.6, 0.6}"
            endif
            Font size: 7
            Text: j - 0.5, "centre", number_of_clusters - i + 0.5, "half", fixed$(prob, 2)
        endfor
    endfor
    
    # Grid lines
    Colour: "{0.8, 0.8, 0.8}"
    Line width: 0.5
    for i from 0 to number_of_clusters
        Draw line: i, 0, i, number_of_clusters
        Draw line: 0, i, number_of_clusters, i
    endfor
    
    # Labels
    Font size: 7
    Colour: "Black"
    for k from 1 to number_of_clusters
        # Column labels (To)
        Text: k - 0.5, "centre", number_of_clusters + 0.15, "bottom", "C" + string$(k)
        # Row labels (From)
        Text: -0.15, "right", number_of_clusters - k + 0.5, "half", "C" + string$(k)
    endfor
    
    Font size: 6
    Text: number_of_clusters / 2, "centre", number_of_clusters + 0.4, "bottom", "To"
    Text special: -0.4, "centre", number_of_clusters / 2, "half", "Helvetica", 6, "90", "From"
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 8
    Text top: "no", "Transition Matrix"
    
    # === CLUSTER WAVEFORMS ===
    vPos = 3.9
    vHeight = 0.55
    
    for s from 1 to soundsCreated
        Select outer viewport: 0, 8, vPos, vPos + vHeight
        Select inner viewport: 0.6, 7.7, vPos + 0.05, vPos + vHeight - 0.05
        
        selectObject: createdSounds[s]
        k = createdCluster[s]
        
        Colour: clusterColor$[k]
        Draw: 0, 0, 0, 0, "no", "Curve"
        
        Colour: "Black"
        Line width: 0.5
        Draw inner box
        
        Font size: 6
        Colour: clusterColor$[k]
        Text: -0.02, "right", 0, "half", createdLabels$[s]
        
        vPos = vPos + vHeight
    endfor
    
    # Time axis label
    Font size: 7
    Colour: "Black"
    Text bottom: "yes", "Time (s)"
    
    # === CLUSTER LEGEND ===
    Select outer viewport: 0, 8, vPos + 0.1, vPos + 0.5
    Axes: 0, 1, 0, 1
    
    Font size: 6
    xPos = 0.02
    for k from 1 to number_of_clusters
        if clusterSize[k] > 0
            Paint rectangle: clusterColor$[k], xPos, xPos + 0.02, 0.4, 0.7
            Colour: "Black"
            Text: xPos + 0.03, "left", 0.55, "half", clusterLabel$[k] + " (" + string$(clusterSize[k]) + ")"
            xPos = xPos + 0.18
        endif
    endfor
    
    # Parameters
    Colour: "{0.5, 0.5, 0.5}"
    Font size: 5
    Text: 0.98, "right", 0.55, "half", "Win:" + string$(window_length_ms) + "ms Step:" + string$(step_size_ms) + "ms"
    
    Font size: 10
    Colour: "Black"
    
    appendInfoLine: "  Visualization complete"
endif

# ============================================================
# CLEANUP AND FINAL SELECTION
# ============================================================
removeObject: tableID

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Created ", soundsCreated, " cluster sounds:"
for s from 1 to soundsCreated
    selectObject: createdSounds[s]
    dur = Get total duration
    appendInfoLine: "  ", createdLabels$[s], " (", fixed$(dur, 2), " s)"
endfor

# === Play ===
if play_result and soundsCreated > 0
    selectObject: createdSounds[1]
    Play
endif

# v3.2: final multi-selection LAST. It used to run before the info
# loop, whose per-sound selectObject clobbered it -- the script
# always ended with only the last cluster selected.
if soundsCreated > 0
    selectObject: createdSounds[1]
    for k from 2 to soundsCreated
        plusObject: createdSounds[k]
    endfor
endif