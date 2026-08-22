# ============================================================
# Praat AudioTools - Spectral_Pitch_Shifter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Pitch Shifter - analyzes spectral flatness and
#   roughness to drive pitch modulation. Noisy/harsh sections
#   get deeper, faster pitch modulation. Creates adaptive,
#   content-aware pitch effects.
#
# Changelog v0.5.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.5: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.5:
#   - Spectral flatness now uses FFT power (real^2 + imag^2), so it is
#     phase-independent.
#   - Roughness now uses normalized local magnitude curvature, reducing
#     dependence on FFT phase and source amplitude.
#   - Full xmin/xmax-safe analysis and PitchTier processing.
#   - Analysis windows adapt safely to short sounds.
#   - Exact endpoint pitch grid with continuous phase integration through
#     voiced and unvoiced regions.
#   - Added validation for analysis points, frequency range, and modulation
#     parameters; modulation contributions may now be set to 0.
#   - True identity path when shift depth and flatness contribution are 0.
#   - Stops cleanly on no-pitch input when pitch processing is required.
#   - Spectral and pitch analysis use a mono reference; processing preserves
#     the exact original channel count.
#   - Pitch targets use synthesis safety limits independent of analysis range.
#   - Peak protection is attenuation-only.
#   - Visualization layout/style preserved; title/legend/sentinel robustness fixed.
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
xmin = Get start time
xmax = Get end time
duration = xmax - xmin
sampling = Get sampling frequency
n_channels = Get number of channels

# === Form ===
form Spectral Pitch Shifter v0.5.1
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
    real Base_shift_depth 2
    real Flatness_multiplier 6
    real Base_mod_speed 0.5
    real Roughness_multiplier 3.0
    
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

# === Validation ===
if duration <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if num_analysis_points < 2 or num_analysis_points > 128
    exitScript: "Num_analysis_points must be between 2 and 128."
endif
if min_frequency <= 0 or max_frequency <= min_frequency
    exitScript: "Min_frequency / Max_frequency are invalid."
endif
if max_frequency >= 0.49 * sampling
    exitScript: "Max_frequency must be below 49% of the source sampling frequency."
endif
if base_shift_depth < 0
    exitScript: "Base_shift_depth must be zero or greater."
endif
if flatness_multiplier < 0
    exitScript: "Flatness_multiplier must be zero or greater."
endif
if base_mod_speed < 0
    exitScript: "Base_mod_speed must be zero or greater."
endif
if roughness_multiplier < 0
    exitScript: "Roughness_multiplier must be zero or greater."
endif

identity_mode = 0
if base_shift_depth = 0 and flatness_multiplier = 0
    identity_mode = 1
endif

# === Info ===
writeInfoLine: "=== Spectral Pitch Shifter v0.5.1 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis points: ", num_analysis_points
appendInfoLine: "Frequency range: ", min_frequency, "-", max_frequency, " Hz"
appendInfoLine: "Shift depth: ", base_shift_depth, " + flatness x ", flatness_multiplier
appendInfoLine: "Mod speed: ", base_mod_speed, " + roughness x ", roughness_multiplier
appendInfoLine: ""

# ============================================================
# 1. MONO ANALYSIS REFERENCE
# ============================================================
selectObject: original
if n_channels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: "SPS_analysis"
endif

# ============================================================
# 2. ANALYZE SPECTRAL FEATURES
# ============================================================
analysisTimes# = zero#(num_analysis_points)
flatness# = zero#(num_analysis_points)
roughness# = zero#(num_analysis_points)

appendInfoLine: "Analyzing ", num_analysis_points, " time windows..."
stopwatch

# Nominal 200 ms windows; shrink automatically for short sounds.
analysisHalf = min(0.1, duration / 2)
if analysisHalf <= 0
    removeObject: analysisMono
    exitScript: "The selected Sound is too short for spectral analysis."
endif

for point from 1 to num_analysis_points
    # Relative time for interpolation/visualization.
    analysisTimes#[point] = (point - 1) * duration / (num_analysis_points - 1)
    centreAbs = xmin + analysisTimes#[point]

    beginTime = centreAbs - analysisHalf
    endTime = centreAbs + analysisHalf
    if beginTime < xmin
        beginTime = xmin
    endif
    if endTime > xmax
        endTime = xmax
    endif

    if endTime <= beginTime
        flatness#[point] = 0
        roughness#[point] = 0
    else
        selectObject: analysisMono
        windowSound = Extract part: beginTime, endTime, "Hamming", 1, "no"

        selectObject: windowSound
        spectrum = To Spectrum: "yes"

        selectObject: spectrum
        binWidth = Get bin width

        # Spectrum -> Matrix: row 1 real, row 2 imaginary.
        To Matrix
        spSrcID = selected("Matrix")
        Rename: "spsrc"

        Copy: "spwork"
        spWorkID = selected("Matrix")

        # Count in-band bins (one contribution per FFT bin).
        selectObject: spWorkID
        Formula: "if row = 1 and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then 1 else 0 fi"
        validBins = Get sum

        # Spectral flatness from POWER, independent of FFT phase.
        Formula: "if row = 1 and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then max(Matrix_spsrc[1,col]^2 + Matrix_spsrc[2,col]^2, 1e-20) else 0 fi"
        linearSum = Get sum

        Formula: "if row = 1 and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then ln(max(Matrix_spsrc[1,col]^2 + Matrix_spsrc[2,col]^2, 1e-20)) else 0 fi"
        lnSum = Get sum

        # Normalized local magnitude curvature:
        # |m[k] - (m[k-1]+m[k+1])/2| / local mean magnitude.
        Formula: "if row = 1 and col > 1 and col < ncol and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then abs(sqrt(Matrix_spsrc[1,col]^2+Matrix_spsrc[2,col]^2) - (sqrt(Matrix_spsrc[1,col-1]^2+Matrix_spsrc[2,col-1]^2)+sqrt(Matrix_spsrc[1,col+1]^2+Matrix_spsrc[2,col+1]^2))/2) / max((sqrt(Matrix_spsrc[1,col-1]^2+Matrix_spsrc[2,col-1]^2)+sqrt(Matrix_spsrc[1,col]^2+Matrix_spsrc[2,col]^2)+sqrt(Matrix_spsrc[1,col+1]^2+Matrix_spsrc[2,col+1]^2))/3, 1e-10) else 0 fi"
        roughnessSum = Get sum

        Formula: "if row = 1 and col > 1 and col < ncol and (col-1)*'binWidth' >= 'min_frequency' and (col-1)*'binWidth' <= 'max_frequency' then 1 else 0 fi"
        roughnessBins = Get sum

        if validBins > 0
            flatness#[point] = exp(lnSum / validBins) / (linearSum / validBins)
            if flatness#[point] < 0
                flatness#[point] = 0
            elsif flatness#[point] > 1
                flatness#[point] = 1
            endif
        else
            flatness#[point] = 0
        endif

        if roughnessBins > 0
            roughness#[point] = roughnessSum / roughnessBins
            if roughness#[point] < 0
                roughness#[point] = 0
            elsif roughness#[point] > 4
                roughness#[point] = 4
            endif
        else
            roughness#[point] = 0
        endif

        appendInfoLine: "  Window ", point, " (", fixed$(analysisTimes#[point], 2), " s): ",
            ... "flat=", fixed$(flatness#[point], 3), " rough=", fixed$(roughness#[point], 3)

        removeObject: windowSound, spectrum, spSrcID, spWorkID
    endif
endfor

analysisElapsed = stopwatch
appendInfoLine: "  (analysis: ", fixed$(analysisElapsed, 2), " s)"

# ============================================================
# 3. PRECOMPUTE MODULATION GRID
# ============================================================
timeStep = 0.01
numGridPoints = ceiling(duration / timeStep) + 1
if numGridPoints < 2
    numGridPoints = 2
endif
grid_dt = duration / (numGridPoints - 1)

maxVizPoints = min(numGridPoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizDepths# = zero#(maxVizPoints)
vizSpeeds# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)
vizStep = numGridPoints / maxVizPoints

timesRel# = zero#(numGridPoints)
timesAbs# = zero#(numGridPoints)
shiftDepths# = zero#(numGridPoints)
modSpeeds# = zero#(numGridPoints)

for i from 1 to numGridPoints
    tRel = (i - 1) * grid_dt
    tAbs = xmin + tRel
    timesRel#[i] = tRel
    timesAbs#[i] = tAbs

    # Locate the enclosing spectral-analysis segment.
    segment = num_analysis_points - 1
    for p from 1 to num_analysis_points - 1
        if tRel >= analysisTimes#[p] and tRel <= analysisTimes#[p + 1]
            segment = p
            p = num_analysis_points
        endif
    endfor

    segmentStart = analysisTimes#[segment]
    segmentEnd = analysisTimes#[segment + 1]
    if segmentEnd > segmentStart
        progress = (tRel - segmentStart) / (segmentEnd - segmentStart)
    else
        progress = 0
    endif
    if progress < 0
        progress = 0
    elsif progress > 1
        progress = 1
    endif

    currentFlatness = flatness#[segment] +
        ... progress * (flatness#[segment + 1] - flatness#[segment])
    currentRoughness = roughness#[segment] +
        ... progress * (roughness#[segment + 1] - roughness#[segment])

    shiftDepths#[i] = base_shift_depth + currentFlatness * flatness_multiplier
    modSpeeds#[i] = base_mod_speed + currentRoughness * roughness_multiplier
endfor

# ============================================================
# 4. TRUE IDENTITY PATH
# ============================================================
safetyApplied = 0
limited_points = 0

if identity_mode
    selectObject: original
    result = Copy: originalName$ + "_spectral_" + presetName$
    appendInfoLine: ""
    appendInfoLine: "Zero shift depth: exact audio copy (PSOLA bypassed)."

    # Keep visualization meaningful: show a flat 0-st shift curve.
    for i from 1 to numGridPoints
        vizIdx = floor((i - 1) / vizStep) + 1
        if vizIdx < 1
            vizIdx = 1
        elsif vizIdx > maxVizPoints
            vizIdx = maxVizPoints
        endif
        if vizFilled#[vizIdx] = 0
            vizTimes#[vizIdx] = timesRel#[i]
            vizShifts#[vizIdx] = 0
            vizDepths#[vizIdx] = shiftDepths#[i]
            vizSpeeds#[vizIdx] = modSpeeds#[i]
            vizFilled#[vizIdx] = 1
        endif
    endfor

else
    appendInfoLine: ""
    appendInfoLine: "Creating pitch modulation..."
    stopwatch

    # Shared pitch analysis from the mono reference.
    pitchFloor = 50
    pitchCeil = min(1000, 0.45 * sampling)
    if pitchCeil <= pitchFloor
        removeObject: analysisMono
        exitScript: "The source sampling frequency is too low for safe pitch analysis."
    endif

    selectObject: analysisMono
    analysisManip = To Manipulation: 0.01, pitchFloor, pitchCeil

    selectObject: analysisManip
    originalPitchTier = Extract pitch tier

    selectObject: originalPitchTier
    nPitchPoints = Get number of points
    if nPitchPoints < 1
        removeObject: analysisManip, originalPitchTier, analysisMono
        exitScript: "No usable voiced pitch was detected."
    endif

    Create PitchTier: "spectral_shifted_pitch", xmin, xmax
    shiftedPitchTier = selected("PitchTier")

    # Read source pitch values at exact absolute grid times.
    selectObject: originalPitchTier
    origFreqs# = zero#(numGridPoints)
    for i from 1 to numGridPoints
        origFreqs#[i] = Get value at time: timesAbs#[i]
    endfor

    # Continuous phase integration across ALL grid points.
    newFreqs# = zero#(numGridPoints)
    shiftSemis# = zero#(numGridPoints)
    currentPhase = 0
    synth_floor = 20
    synth_ceil = 0.45 * sampling

    for i from 1 to numGridPoints
        if i > 1
            meanSpeed = 0.5 * (modSpeeds#[i - 1] + modSpeeds#[i])
            currentPhase += 2 * pi * meanSpeed * grid_dt
        endif

        semitoneShift = shiftDepths#[i] * sin(currentPhase)
        shiftSemis#[i] = semitoneShift

        if origFreqs#[i] <> undefined and origFreqs#[i] > 0
            newFreq = origFreqs#[i] * 2 ^ (semitoneShift / 12)
            if newFreq < synth_floor
                newFreq = synth_floor
                limited_points += 1
            elsif newFreq > synth_ceil
                newFreq = synth_ceil
                limited_points += 1
            endif
            newFreqs#[i] = newFreq
        endif

        vizIdx = floor((i - 1) / vizStep) + 1
        if vizIdx < 1
            vizIdx = 1
        elsif vizIdx > maxVizPoints
            vizIdx = maxVizPoints
        endif
        if vizFilled#[vizIdx] = 0
            vizTimes#[vizIdx] = timesRel#[i]
            vizShifts#[vizIdx] = semitoneShift
            vizDepths#[vizIdx] = shiftDepths#[i]
            vizSpeeds#[vizIdx] = modSpeeds#[i]
            vizFilled#[vizIdx] = 1
        endif
    endfor

    selectObject: shiftedPitchTier
    for i from 1 to numGridPoints
        if newFreqs#[i] > 0
            Add point: timesAbs#[i], newFreqs#[i]
        endif
    endfor

    if limited_points > 0
        appendInfoLine: "Sampling-safe pitch limits applied: ", limited_points, " point(s)"
    endif

    pitchElapsed = stopwatch
    appendInfoLine: "  (pitch grid: ", fixed$(pitchElapsed, 2), " s)"

    # Resynthesize every original channel with the same processed PitchTier.
    appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."
    channelResults# = zero#(n_channels)

    for ch from 1 to n_channels
        selectObject: original
        if n_channels = 1
            channelWork = Copy: "SPS_ch1"
        else
            channelWork = Extract one channel: ch
            Rename: "SPS_ch" + string$(ch)
        endif

        selectObject: channelWork
        manipulation = To Manipulation: 0.01, pitchFloor, pitchCeil

        selectObject: manipulation
        plusObject: shiftedPitchTier
        Replace pitch tier

        selectObject: manipulation
        channelResult = Get resynthesis (overlap-add)
        Rename: "SPS_result_ch" + string$(ch)
        channelResults#[ch] = channelResult

        removeObject: manipulation, channelWork
    endfor

    Create Sound from formula: "SPS_result_build", n_channels,
        ... xmin, xmax, sampling, "0"
    result = selected("Sound")

    for ch from 1 to n_channels
        selectObject: result
        Formula (part): xmin, xmax, ch, ch,
            ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
        removeObject: channelResults#[ch]
    endfor

    selectObject: result
    Rename: originalName$ + "_spectral_" + presetName$

    removeObject: analysisManip, originalPitchTier, shiftedPitchTier
endif

# Final attenuation-only peak safety.
selectObject: result
result_peak = Get absolute extremum: 0, 0, "None"
if result_peak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
endif

# ============================================================
# 4. VISUALIZATION  (unchanged from v0.2)
# ============================================================
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Pitch Shifter v0.5.1: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
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
    
    firstViz = 0
    for vp from 1 to maxVizPoints
        if vizFilled#[vp] = 1
            if firstViz = 0
                minS = vizShifts#[vp]
                maxS = vizShifts#[vp]
                firstViz = 1
            else
                if vizShifts#[vp] < minS
                    minS = vizShifts#[vp]
                endif
                if vizShifts#[vp] > maxS
                    maxS = vizShifts#[vp]
                endif
            endif
        endif
    endfor
    if firstViz = 0
        minS = 0
        maxS = 0
    endif
    
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
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
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
    
    if maxFlat < 0.01
        maxFlat = 0.01
    endif
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
    
    if maxRough < 0.01
        maxRough = 0.01
    endif
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
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.5, "centre", 0.5, "half", "Flatness -> Shift Depth | Roughness -> Modulation Speed"
    
    Font size: 10
    Colour: "Black"

    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.42, 5.98
    Select inner viewport: 0.60, 7.70, 5.42 + 0.04, 5.98 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.45, "half", "Spectral shift law • pitch displacement • reconstructed output"
    Text: 0.02, "left", 0.20, "half", "Spectral Pitch Shifter • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 6.08
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Cleanup ===
removeObject: analysisMono

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Peak safety applied: ", safetyApplied

if play_result
    selectObject: result
    Play
endif

selectObject: result
