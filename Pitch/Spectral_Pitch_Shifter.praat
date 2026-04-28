# ============================================================
# Praat AudioTools - Spectral_Pitch_Shifter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Pitch Shifter - analyzes spectral flatness and
#   roughness to drive pitch modulation. Noisy/harsh sections
#   get deeper, faster pitch modulation. Creates adaptive,
#   content-aware pitch effects.
#
# Changelog v0.3:
#   - Vectorized spectral analysis. The per-bin loop made
#     ~3*nBins Get-calls per analysis window (for an 0.2 s
#     window at 44.1 kHz: 8193 bins -> ~25k Get-calls per
#     window, ~200k total for 8 windows). Replaced with five
#     Matrix Formula + Get sum operations on a
#     Spectrum -> Matrix view. The roughness formula reads
#     col-1 and col+1, so it cross-references a renamed
#     source matrix (Matrix_spsrc) to avoid the in-place
#     overwrite that would otherwise zero things out.
#   - Split-phase pitch grid loop. originalPitchTier reads
#     and shiftedPitchTier writes are now two separate
#     passes, each needing one selectObject instead of
#     one per iteration. Modulation parameters are
#     precomputed as plain vectors.
#   - Output is bit-for-bit equivalent (modulo floating
#     point summation order); just much faster.
# Changelog v0.2:
#   - Added form with parameters
#   - Modern syntax
#   - Removed goto
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling = Get sampling frequency

# === Form ===
form Spectral Pitch Shifter
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Response
        option Moderate Response
        option Strong Response
        option Extreme Response
    
    comment === Analysis ===
    natural Num_analysis_points 8
    positive Min_frequency 80
    positive Max_frequency 5000
    
    comment === Pitch Modulation ===
    positive Base_shift_depth 2
    positive Flatness_multiplier 6
    positive Base_mod_speed 0.5
    positive Roughness_multiplier 3.0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    base_shift_depth = 1
    flatness_multiplier = 3
    base_mod_speed = 0.3
    roughness_multiplier = 1.5
    presetName$ = "Subtle"
elsif preset = 3
    base_shift_depth = 2
    flatness_multiplier = 6
    base_mod_speed = 0.5
    roughness_multiplier = 3.0
    presetName$ = "Moderate"
elsif preset = 4
    base_shift_depth = 4
    flatness_multiplier = 10
    base_mod_speed = 1.0
    roughness_multiplier = 5.0
    presetName$ = "Strong"
elsif preset = 5
    base_shift_depth = 6
    flatness_multiplier = 15
    base_mod_speed = 1.5
    roughness_multiplier = 8.0
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Spectral Pitch Shifter ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis points: ", num_analysis_points
appendInfoLine: "Frequency range: ", min_frequency, "-", max_frequency, " Hz"
appendInfoLine: "Shift depth: ", base_shift_depth, " + flatness×", flatness_multiplier
appendInfoLine: "Mod speed: ", base_mod_speed, " + roughness×", roughness_multiplier
appendInfoLine: ""

# ============================================================
# 1. ANALYZE SPECTRAL FEATURES  (vectorized)
# ============================================================
analysisTimes# = zero#(num_analysis_points)
flatness# = zero#(num_analysis_points)
roughness# = zero#(num_analysis_points)

appendInfoLine: "Analyzing ", num_analysis_points, " time windows (vectorized)..."
stopwatch

for point from 1 to num_analysis_points
    analysisTimes#[point] = (point - 1) * duration / (num_analysis_points - 1)
    if analysisTimes#[point] < 0.1
        analysisTimes#[point] = 0.1
    endif
    if analysisTimes#[point] > duration - 0.2
        analysisTimes#[point] = duration - 0.2
    endif
    
    beginTime = analysisTimes#[point] - 0.1
    endTime = analysisTimes#[point] + 0.1
    if beginTime < 0
        beginTime = 0
    endif
    if endTime > duration
        endTime = duration
    endif
    
    # --- Extract window and compute spectrum ---
    selectObject: original
    windowSound = Extract part: beginTime, endTime, "Hamming", 1, "no"
    
    selectObject: windowSound
    To Spectrum: "yes"
    spectrum = selected("Spectrum")
    
    selectObject: spectrum
    nBins = Get number of bins
    binWidth = Get bin width
    
    # --- Spectrum -> Matrix (row 1 = real part, row 2 = imag part) ---
    # Source matrix is renamed so cross-Matrix references can find it.
    # Working matrix is where each Formula writes; we Get sum per pass.
    To Matrix
    spSrcID = selected("Matrix")
    Rename: "spsrc"
    
    Copy: "spwork"
    spWorkID = selected("Matrix")
    
    # Aggregate 1: validBins (count of in-band bins, row 1 only)
    selectObject: spWorkID
    Formula: "if row = 1 and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then 1 else 0 fi"
    validBins = Get sum
    
    # Aggregate 2: linearSum = sum_in_band( max(re^2, 1e-12) )
    Formula: "if row = 1 and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then max(Matrix_spsrc[1, col] ^ 2, 1e-12) else 0 fi"
    linearSum = Get sum
    
    # Aggregate 3: lnSum = sum_in_band( ln(max(re^2, 1e-12)) )
    Formula: "if row = 1 and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then ln(max(Matrix_spsrc[1, col] ^ 2, 1e-12)) else 0 fi"
    lnSum = Get sum
    
    # Aggregate 4: roughnessSum = sum_in_band_excl_edges( |x_k - (x_{k-1}+x_{k+1})/2| )
    # Uses Matrix_spsrc to read col-1, col, col+1 from the unmodified source
    # (in-place modification of self would corrupt neighbour reads).
    Formula: "if row = 1 and col > 1 and col < ncol and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then abs(Matrix_spsrc[1, col] - (Matrix_spsrc[1, col-1] + Matrix_spsrc[1, col+1]) / 2) else 0 fi"
    roughnessSum = Get sum
    
    # Aggregate 5: roughnessBins (count of bins contributing to roughnessSum)
    Formula: "if row = 1 and col > 1 and col < ncol and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then 1 else 0 fi"
    roughnessBins = Get sum
    
    # --- Reduce to flatness / roughness scalars ---
    if validBins > 0 and roughnessBins > 0
        flatness#[point] = exp(lnSum / validBins) / (linearSum / validBins)
        roughness#[point] = roughnessSum / roughnessBins
    else
        flatness#[point] = 0.2
        roughness#[point] = 0.02
    endif
    
    appendInfoLine: "  Window ", point, " (", fixed$(analysisTimes#[point], 2), "s): ",
        ... "flat=", fixed$(flatness#[point], 3), " rough=", fixed$(roughness#[point], 3)
    
    removeObject: windowSound, spectrum, spSrcID, spWorkID
endfor

analysisElapsed = stopwatch
appendInfoLine: "  (analysis: ", fixed$(analysisElapsed, 2), " s)"

# ============================================================
# 2. CREATE PITCH MODULATION  (vectorized + split-phase)
# ============================================================
appendInfoLine: ""
appendInfoLine: "Creating pitch modulation..."
stopwatch

selectObject: original
workingSound = Copy: "working_" + originalName$

selectObject: workingSound
manipulation = To Manipulation: 0.01, 75, 600

selectObject: manipulation
originalPitchTier = Extract pitch tier

shiftedPitchTier = Create PitchTier: "spectral_shifted_pitch", 0, duration

timeStep = 0.01
numGridPoints = round(duration / timeStep) + 1

# --- Visualization storage ---
maxVizPoints = min(numGridPoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizDepths# = zero#(maxVizPoints)
vizSpeeds# = zero#(maxVizPoints)
vizStep = numGridPoints / maxVizPoints

# --- Precompute per-grid-point parameters (pure script math, no object queries) ---
times# = zero#(numGridPoints)
shiftDepths# = zero#(numGridPoints)
modSpeeds# = zero#(numGridPoints)

for i from 1 to numGridPoints
    t = (i - 1) * timeStep
    times#[i] = t
    
    # Locate segment in analysisTimes#
    segment = num_analysis_points - 1
    for p from 1 to num_analysis_points - 1
        if t >= analysisTimes#[p] and t <= analysisTimes#[p + 1]
            segment = p
            p = num_analysis_points
        endif
    endfor
    if t < analysisTimes#[1]
        segment = 1
    endif
    
    segmentStart = analysisTimes#[segment]
    segmentEnd = analysisTimes#[segment + 1]
    if segmentEnd > segmentStart
        progress = (t - segmentStart) / (segmentEnd - segmentStart)
    else
        progress = 0
    endif
    
    currentFlatness  = flatness#[segment]  + progress * (flatness#[segment + 1]  - flatness#[segment])
    currentRoughness = roughness#[segment] + progress * (roughness#[segment + 1] - roughness#[segment])
    
    shiftDepths#[i] = base_shift_depth + currentFlatness  * flatness_multiplier
    modSpeeds#[i]   = base_mod_speed   + currentRoughness * roughness_multiplier
endfor

# --- Phase A: read all original pitch values in one pass ---
selectObject: originalPitchTier
origFreqs# = zero#(numGridPoints)
for i from 1 to numGridPoints
    origFreqs#[i] = Get value at time: times#[i]
endfor

# --- Compute new frequencies (phase has serial dependency, so a loop) ---
# Phase advance is preserved exactly as in v0.2: phase only updates on
# voiced points, currentPhase is reset to 0 at i=1, and previousTime
# tracks the last voiced grid time.
newFreqs# = zero#(numGridPoints)
shiftSemis# = zero#(numGridPoints)
currentPhase = 0
previousTime = 0

for i from 1 to numGridPoints
    if origFreqs#[i] > 0
        if i > 1
            timeDelta = times#[i] - previousTime
            currentPhase = currentPhase + 2 * pi * modSpeeds#[i] * timeDelta
        else
            currentPhase = 0
        endif
        
        semitoneShift = shiftDepths#[i] * sin(currentPhase)
        newFreqs#[i] = origFreqs#[i] * 2 ^ (semitoneShift / 12)
        shiftSemis#[i] = semitoneShift
        previousTime = times#[i]
        
        # Sparse viz capture (first hit per viz bucket wins, matches v0.2)
        vizIdx = floor(i / vizStep) + 1
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            if vizTimes#[vizIdx] = 0
                vizTimes#[vizIdx]  = times#[i]
                vizShifts#[vizIdx] = semitoneShift
                vizDepths#[vizIdx] = shiftDepths#[i]
                vizSpeeds#[vizIdx] = modSpeeds#[i]
            endif
        endif
    endif
endfor

# --- Phase B: write all points to shiftedPitchTier in one pass ---
selectObject: shiftedPitchTier
for i from 1 to numGridPoints
    if origFreqs#[i] > 0
        Add point: times#[i], newFreqs#[i]
    endif
endfor

pitchElapsed = stopwatch
appendInfoLine: "  (pitch grid: ", fixed$(pitchElapsed, 2), " s)"

# ============================================================
# 3. RESYNTHESIZE
# ============================================================
appendInfoLine: ""
appendInfoLine: "Resynthesizing..."

selectObject: manipulation, shiftedPitchTier
Replace pitch tier

selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_spectral_" + presetName$

selectObject: result
Scale peak: 0.95

# ============================================================
# 4. VISUALIZATION  (unchanged from v0.2)
# ============================================================
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Pitch Shifter: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Spectral"
    Text bottom: "yes", "Time (s)"
    
    # Pitch shift curve
    Select outer viewport: 0, 8, 2.5, 3.5
    Select inner viewport: 0.6, 7.6, 2.6, 3.4
    
    minS = vizShifts#[1]
    maxS = vizShifts#[1]
    for vp from 2 to maxVizPoints
        if vizShifts#[vp] < minS
            minS = vizShifts#[vp]
        endif
        if vizShifts#[vp] > maxS
            maxS = vizShifts#[vp]
        endif
    endfor
    
    sMargin = max((maxS - minS) * 0.1, 2)
    
    Axes: 0, duration, minS - sMargin, maxS + sMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, minS - sMargin, maxS + sMargin
    
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line
    
    Colour: "{0.4, 0.5, 0.7}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Shift (st)"
    
    # Flatness panel
    Select outer viewport: 0, 4, 3.7, 4.7
    Select inner viewport: 0.6, 3.8, 3.8, 4.6
    
    maxFlat = flatness#[1]
    for p from 2 to num_analysis_points
        if flatness#[p] > maxFlat
            maxFlat = flatness#[p]
        endif
    endfor
    
    Axes: 0, duration, 0, maxFlat * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, maxFlat * 1.2
    
    Colour: "{0.7, 0.5, 0.5}"
    for p from 2 to num_analysis_points
        Draw line: analysisTimes#[p - 1], flatness#[p - 1], analysisTimes#[p], flatness#[p]
    endfor
    for p from 1 to num_analysis_points
        Paint circle (mm): "{0.7, 0.5, 0.5}", analysisTimes#[p], flatness#[p], 1.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Flatness"
    Text bottom: "yes", "Time (s)"
    
    # Roughness panel
    Select outer viewport: 4, 8, 3.7, 4.7
    Select inner viewport: 4.4, 7.6, 3.8, 4.6
    
    maxRough = roughness#[1]
    for p from 2 to num_analysis_points
        if roughness#[p] > maxRough
            maxRough = roughness#[p]
        endif
    endfor
    
    Axes: 0, duration, 0, maxRough * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, maxRough * 1.2
    
    Colour: "{0.5, 0.7, 0.5}"
    for p from 2 to num_analysis_points
        Draw line: analysisTimes#[p - 1], roughness#[p - 1], analysisTimes#[p], roughness#[p]
    endfor
    for p from 1 to num_analysis_points
        Paint circle (mm): "{0.5, 0.7, 0.5}", analysisTimes#[p], roughness#[p], 1.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Roughness"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 4.9, 5.3
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.5, "centre", 0.5, "half", "Flatness → Shift Depth | Roughness → Modulation Speed"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: workingSound, manipulation, originalPitchTier, shiftedPitchTier

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    selectObject: result
    Play
endif

selectObject: result
