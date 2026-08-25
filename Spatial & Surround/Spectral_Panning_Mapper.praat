# ============================================================
# Praat AudioTools - Spectral_Panning_Mapper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1.4 (2026) - Spectral-flux / DBAP / multichannel-mix fixes
# v1.1.4 (2026): DSP / VALIDATION FIXES.
#   - Spectral flux is now true frame-to-frame change: each 80-8000 Hz
#     magnitude spectrum is L2-normalized, then compared with the previous
#     analysis frame. The resulting L2 distance is normalized to [0,1].
#   - Per-channel IntensityTier multiplication no longer rescales every
#     channel independently; DBAP gain ratios are preserved.
#   - Wet/dry mixing now builds an n-channel, power-normalized dry mono bed,
#     so 3-8 channel outputs never index nonexistent dry channels.
#   - Surround 5.1 keeps channel 4 as LFE but excludes it from full-range
#     DBAP and dry distribution; no crossover/LFE synthesis is invented.
#   - Custom channel count is clamped before speaker coordinates are built.
#   - Analysis_windows is an integer and must be at least 2.
#   - Gain heatmap / speaker map follow the same LFE exclusion as the audio.
# v1.1.3 (2026): RUNTIME VISUAL QA - relaxed panel spacing, shorter panel titles, compact Info reporting; DSP unchanged.
# v1.1.2 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral-driven dynamic spatial panning for 2-8 channels.
#   Analyzes two spectral features per time window:
#
#   SPECTRAL FLATNESS (Wiener entropy):
#     exp(mean(ln(power))) / mean(power)
#     0 = pure tone,  1 = white noise
#     → controls orbit RADIUS:  noise = wide spread, tone = center
#
#   SPECTRAL FLUX (frame-to-frame spectral change):
#     L2 distance between consecutive L2-normalized magnitude spectra
#     in the 80-8000 Hz analysis band, normalized to [0,1]
#     → controls orbit SPEED: changing spectrum = fast, stable = slow
#
#   SPATIAL MODEL:
#   The source is treated as a point moving in 2D speaker space.
#   Its position at each time step:
#     orbitRadius = flatness * flatness_influence + base_radius
#     orbitSpeed  = flux     * flux_influence     + base_speed
#     angle       += 2*pi * orbitSpeed * dt
#     srcX = orbitRadius * cos(angle)
#     srcY = orbitRadius * sin(angle)
#
#   Per-channel gain uses DBAP (Distance-Based Amplitude Panning):
#     gain_i = 1 / dist(src, speaker_i) ^ rolloff
#   Gains are power-normalized then converted to dB IntensityTiers.
#
#   MULTI-CHANNEL PRESETS (matching DBAP script vocabulary):
#   Stereo, Triangle, Quad, 5.1, Hexagon, Octagon, FrontArc, DiffuseField
#
# Changelog v1.1:
#   - Full multi-channel rewrite (2-8 channels)
#   - DBAP gain model replaces cos/sin stereo pan
#   - Orbit model: flatness->radius, flux->speed
#   - 14 presets (stereo + multi-channel)
#   - Fixed wet/dry formula (object[] syntax)
#   - Renamed "roughness" to "flux" for accuracy
#   - Improved visualization: speaker ring, orbit trace, gain heatmap
#
# Category: Spatial / Composition
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcSound  = selected("Sound")
srcName$  = selected$("Sound")
selectObject: srcSound
srcDur    = Get total duration
srcSr     = Get sampling frequency
srcCh     = Get number of channels

if srcDur < 0.3
    exitScript: "Sound must be at least 0.3 s."
endif

# ============================================================
# FORM
# ============================================================

form Spectral Panning Mapper v1.1.4
    comment === Preset ===
    optionmenu Preset: 3
        option Custom
        option Stereo Sweep      (2ch, classic LR oscillation)
        option Stereo Drift      (2ch, gentle flatness-driven)
        option Triangle Orbit    (3ch, equilateral, full orbit)
        option Quad Spiral       (4ch, square, spiral trajectory)
        option Quad Corners      (4ch, square, flatness->corners)
        option Hex Ring          (6ch, regular hexagon)
        option Surround 5.1      (6ch, ITU layout)
        option Octagon Orbit     (8ch, full 360 ring)
        option Octagon Front Arc (8ch, front hemisphere only)
        option Diffuse Field     (8ch, tone=center noise=diffuse)
        option Hyperactive       (4ch, fast response)
        option Slow Evolution    (6ch, long arcs)
        option Custom Multi      (use form values below)
    comment === Speaker Layout (Custom only) ===
    integer Num_channels 4
    comment === Analysis ===
    integer Analysis_windows 10
    positive Panning_update_rate_Hz 100
    comment === Orbit Parameters ===
    positive Base_orbit_radius 0.3
    positive Flatness_radius_influence 0.6
    positive Base_orbit_speed_Hz 0.4
    positive Flux_speed_influence 3.0
    comment === DBAP ===
    positive Rolloff_exponent 1.0
    comment === Mix ===
    real Mix_percent 100
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ALIASES
# ============================================================

nChan        = num_channels
nWindows     = analysis_windows
updateHz     = panning_update_rate_Hz
baseRadius   = base_orbit_radius
flatInfl     = flatness_radius_influence
baseSpeed    = base_orbit_speed_Hz
fluxInfl     = flux_speed_influence
rolloff      = rolloff_exponent
mixPct       = mix_percent

# Validate form values BEFORE any custom speaker coordinates are built.
if nChan < 2
    nChan = 2
elsif nChan > 8
    nChan = 8
endif
if nWindows < 2
    exitScript: "Analysis_windows must be at least 2."
endif
if mixPct < 0
    mixPct = 0
elsif mixPct > 100
    mixPct = 100
endif

# ============================================================
# PRESETS
# Sets: nChan, spkX[i], spkY[i], baseRadius, flatInfl,
#       baseSpeed, fluxInfl, rolloff, presetName$
# ============================================================

presetName$ = "Custom"
lfeChannel = 0

if preset = 2
    # Stereo Sweep
    nChan      = 2
    baseRadius = 0.5
    flatInfl   = 0.5
    baseSpeed  = 0.5
    fluxInfl   = 3.0
    rolloff    = 1.0
    presetName$ = "StereoSweep"
    spkX[1] = -1.0
    spkY[1] = 0.0
    spkX[2] = 1.0
    spkY[2] = 0.0

elsif preset = 3
    # Stereo Drift
    nChan      = 2
    baseRadius = 0.2
    flatInfl   = 0.3
    baseSpeed  = 0.15
    fluxInfl   = 1.0
    rolloff    = 1.0
    presetName$ = "StereoDrift"
    spkX[1] = -1.0
    spkY[1] = 0.0
    spkX[2] = 1.0
    spkY[2] = 0.0

elsif preset = 4
    # Triangle Orbit
    nChan      = 3
    baseRadius = 0.4
    flatInfl   = 0.5
    baseSpeed  = 0.3
    fluxInfl   = 2.0
    rolloff    = 1.0
    presetName$ = "TriOrbit"
    for ii from 1 to 3
        ang = (ii - 1) * 2 * pi / 3 - pi/2
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor

elsif preset = 5
    # Quad Spiral
    nChan      = 4
    baseRadius = 0.3
    flatInfl   = 0.6
    baseSpeed  = 0.4
    fluxInfl   = 3.0
    rolloff    = 1.0
    presetName$ = "QuadSpiral"
    for ii from 1 to 4
        ang = (ii - 1) * 2 * pi / 4 + pi/4
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor

elsif preset = 6
    # Quad Corners - flatness pushes to corners
    nChan      = 4
    baseRadius = 0.1
    flatInfl   = 0.85
    baseSpeed  = 0.2
    fluxInfl   = 1.5
    rolloff    = 1.2
    presetName$ = "QuadCorners"
    for ii from 1 to 4
        ang = (ii - 1) * 2 * pi / 4 + pi/4
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor

elsif preset = 7
    # Hex Ring
    nChan      = 6
    baseRadius = 0.3
    flatInfl   = 0.55
    baseSpeed  = 0.35
    fluxInfl   = 2.5
    rolloff    = 1.0
    presetName$ = "HexRing"
    for ii from 1 to 6
        ang = (ii - 1) * 2 * pi / 6
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor

elsif preset = 8
    # Surround 5.1 (ITU layout)
    nChan      = 6
    baseRadius = 0.0
    flatInfl   = 0.6
    baseSpeed  = 0.3
    fluxInfl   = 2.0
    rolloff    = 1.0
    presetName$ = "Surround51"
    lfeChannel = 4
    # L, R, C, LFE, Ls, Rs. Reference horizontal geometry follows
    # ITU-R BS.775: L/R at +/-30 deg, surrounds nominally +/-110 deg.
    # +Y is front and -X is left in this 2D map. Channel 4 is non-positional
    # LFE and is NOT fed full-range DBAP audio.
    spkX[1] = -0.500000
    spkY[1] = 0.866025
    spkX[2] = 0.500000
    spkY[2] = 0.866025
    spkX[3] = 0.0
    spkY[3] = 1.0
    spkX[4] = 0.0
    spkY[4] = 0.0
    spkX[5] = -0.939693
    spkY[5] = -0.342020
    spkX[6] = 0.939693
    spkY[6] = -0.342020

elsif preset = 9
    # Octagon Orbit
    nChan      = 8
    baseRadius = 0.35
    flatInfl   = 0.55
    baseSpeed  = 0.3
    fluxInfl   = 2.0
    rolloff    = 1.0
    presetName$ = "OctOrbit"
    for ii from 1 to 8
        ang = (ii - 1) * 2 * pi / 8
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor

elsif preset = 10
    # Octagon Front Arc
    nChan      = 8
    baseRadius = 0.4
    flatInfl   = 0.4
    baseSpeed  = 0.25
    fluxInfl   = 2.5
    rolloff    = 1.0
    presetName$ = "OctFrontArc"
    # All speakers in front semicircle
    for ii from 1 to 8
        ang = (ii - 1) * pi / 7
        spkX[ii] = cos(ang) * 0.9
        spkY[ii] = sin(ang) * 0.9
    endfor

elsif preset = 11
    # Diffuse Field: tonal=center, noise=diffuse to all channels
    nChan      = 8
    baseRadius = 0.05
    flatInfl   = 0.90
    baseSpeed  = 0.1
    fluxInfl   = 0.5
    rolloff    = 0.8
    presetName$ = "DiffuseField"
    for ii from 1 to 8
        ang = (ii - 1) * 2 * pi / 8
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor

elsif preset = 12
    # Hyperactive
    nChan      = 4
    baseRadius = 0.2
    flatInfl   = 0.7
    baseSpeed  = 1.2
    fluxInfl   = 8.0
    rolloff    = 1.0
    presetName$ = "Hyperactive"
    for ii from 1 to 4
        ang = (ii - 1) * 2 * pi / 4 + pi/4
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor

elsif preset = 13
    # Slow Evolution
    nChan      = 6
    baseRadius = 0.25
    flatInfl   = 0.4
    baseSpeed  = 0.08
    fluxInfl   = 0.4
    rolloff    = 1.0
    presetName$ = "SlowEvolution"
    for ii from 1 to 6
        ang = (ii - 1) * 2 * pi / 6
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor

else
    # Custom Multi (preset 14) or preset 1
    presetName$ = "Custom"
    for ii from 1 to nChan
        ang = (ii - 1) * 2 * pi / nChan
        spkX[ii] = cos(ang)
        spkY[ii] = sin(ang)
    endfor
endif

wetLevel = mixPct / 100
dryLevel = 1 - wetLevel

# Min speaker distance to avoid div/zero
minDist = 0.01

# ============================================================
# MONO SOURCE
# ============================================================

selectObject: srcSound
if srcCh > 1
    monoSrc = Convert to mono
else
    monoSrc = Copy: "spm_mono"
endif

# ============================================================
# SPECTRAL ANALYSIS
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  Spectral Panning Mapper v1.1.4"
writeInfoLine:  "=================================================="
appendInfoLine: "Source   : ", srcName$, " | ", fixed$(srcDur, 3), " s | ", srcCh, " ch @ ", fixed$(srcSr, 0), " Hz"
appendInfoLine: "Preset   : ", presetName$, " | output ", nChan, " ch | mix ", fixed$(mixPct, 0), "% wet"
appendInfoLine: "Analysis : ", nWindows, " windows | update ", fixed$(updateHz, 0), " Hz"
appendInfoLine: "Mapping  : radius ", fixed$(baseRadius, 2), " + flatness*", fixed$(flatInfl, 2),
    ... " | speed ", fixed$(baseSpeed, 2), " + flux*", fixed$(fluxInfl, 2), " Hz | rolloff ", fixed$(rolloff, 2)
if lfeChannel > 0
    appendInfoLine: "5.1 LFE  : channel ", lfeChannel, " kept silent (no crossover/LFE synthesis)."
endif
appendInfoLine: ""
appendInfoLine: "[1/4] Spectral analysis"

# Adaptive window half-size
winHalf = 0.1
if winHalf * 2 > srcDur / nWindows
    winHalf = srcDur / (nWindows * 2.5)
endif
if winHalf < 0.02
    winHalf = 0.02
endif

flatness# = zero#(nWindows)
flux#     = zero#(nWindows)
winTime#  = zero#(nWindows)

# Spectral flux state: previous L2-normalized magnitude spectrum.
# All analysis windows have the same duration, so the 80-8000 Hz bin count
# remains constant from frame to frame.
prevNorm# = zero#(1)
prevValidBins = 0

for ww from 1 to nWindows
    winTime#[ww] = winHalf + (ww - 1) * (srcDur - 2 * winHalf) / (nWindows - 1)

    tStart = winTime#[ww] - winHalf
    tEnd   = winTime#[ww] + winHalf
    if tStart < 0
        tStart = 0
    endif
    if tEnd > srcDur
        tEnd = srcDur
    endif

    selectObject: monoSrc
    winSnd = Extract part: tStart, tEnd, "Hamming", 1, "no"
    selectObject: winSnd
    To Spectrum: "yes"
    spec = selected("Spectrum")

    selectObject: spec
    nBins    = Get number of bins
    binWidth = Get bin width

    lnSum     = 0
    linSum    = 0
    magEnergy = 0
    validBins = 0
    minFreq   = 80
    maxFreq   = 8000
    currAmp#  = zero#(nBins)

    for bin from 1 to nBins
        freq = (bin - 1) * binWidth
        if freq >= minFreq and freq <= maxFreq
            re = Get real value in bin: bin
            im = Get imaginary value in bin: bin
            amp = sqrt(re * re + im * im)
            validBins = validBins + 1
            currAmp#[validBins] = amp
            magEnergy = magEnergy + amp * amp

            pw = amp * amp
            if pw < 1e-12
                pw = 1e-12
            endif
            lnSum  = lnSum  + ln(pw)
            linSum = linSum + pw
        endif
    endfor

    # Wiener entropy / spectral flatness.
    if validBins > 0 and linSum > 0
        geoMean   = exp(lnSum / validBins)
        arithMean = linSum / validBins
        flatness#[ww] = geoMean / arithMean
        if flatness#[ww] < 0
            flatness#[ww] = 0
        elsif flatness#[ww] > 1
            flatness#[ww] = 1
        endif
    else
        flatness#[ww] = 0
    endif

    # True frame-to-frame spectral flux. Normalize each frame's magnitude
    # vector to unit L2 norm, then measure its L2 distance from the previous
    # normalized frame. Unit non-negative vectors have distance <= sqrt(2),
    # so dividing the squared distance by 2 yields a natural [0,1] measure.
    if ww = 1 or validBins <= 0 or prevValidBins <> validBins
        flux#[ww] = 0
    else
        if magEnergy > 1e-24
            normDen = sqrt(magEnergy)
        else
            normDen = 0
        endif
        fluxSq = 0
        for vb from 1 to validBins
            if normDen > 0
                currNorm = currAmp#[vb] / normDen
            else
                currNorm = 0
            endif
            diff = currNorm - prevNorm#[vb]
            fluxSq = fluxSq + diff * diff
        endfor
        fluxVal = sqrt(fluxSq / 2)
        if fluxVal < 0
            fluxVal = 0
        elsif fluxVal > 1
            fluxVal = 1
        endif
        flux#[ww] = fluxVal
    endif

    # Save this frame as the reference for the next one. Silence becomes a
    # zero vector; otherwise save the L2-normalized magnitudes.
    if validBins > 0
        prevNorm# = zero#(validBins)
        if magEnergy > 1e-24
            normDen = sqrt(magEnergy)
            for vb from 1 to validBins
                prevNorm#[vb] = currAmp#[vb] / normDen
            endfor
        endif
    else
        prevNorm# = zero#(1)
    endif
    prevValidBins = validBins

    removeObject: winSnd, spec
endfor

flatMin = flatness#[1]
flatMax = flatness#[1]
flatSum = 0
fluxMin = flux#[1]
fluxMax = flux#[1]
fluxSumInfo = 0
for ww from 1 to nWindows
    fv = flatness#[ww]
    xv = flux#[ww]
    flatSum = flatSum + fv
    fluxSumInfo = fluxSumInfo + xv
    if fv < flatMin
        flatMin = fv
    endif
    if fv > flatMax
        flatMax = fv
    endif
    if xv < fluxMin
        fluxMin = xv
    endif
    if xv > fluxMax
        fluxMax = xv
    endif
endfor
flatMean = flatSum / nWindows
fluxMeanInfo = fluxSumInfo / nWindows
appendInfoLine: "  Flatness mean ", fixed$(flatMean, 5), " | range ", fixed$(flatMin, 5), " .. ", fixed$(flatMax, 5)
appendInfoLine: "  Flux     mean ", fixed$(fluxMeanInfo, 5), " | range ", fixed$(fluxMin, 5), " .. ", fixed$(fluxMax, 5)
appendInfoLine: ""
appendInfoLine: "[2/4] Spatial envelopes"

# ============================================================
# CREATE PER-CHANNEL INTENSITY TIERS
# ============================================================

for ch from 1 to nChan
    chanTier_'ch' = Create IntensityTier: "spm_ch" + string$(ch), 0, srcDur
endfor

timeStep   = 1 / updateHz
nGrid      = round(srcDur / timeStep) + 1
orbitAngle = 0
prevT      = 0

# Arrays for visualization
orbitX# = zero#(nGrid)
orbitY# = zero#(nGrid)
gridT#  = zero#(nGrid)

for gi from 1 to nGrid
    curT = (gi - 1) * timeStep
    if curT > srcDur
        curT = srcDur
    endif
    gridT#[gi] = curT

    # Interpolate spectral features at curT
    seg = 1
    for pp from 1 to nWindows - 1
        if curT >= winTime#[pp] and curT < winTime#[pp + 1]
            seg = pp
        endif
    endfor
    if curT < winTime#[1]
        seg = 1
    endif
    if curT >= winTime#[nWindows]
        seg = nWindows - 1
    endif
    if seg >= nWindows
        seg = nWindows - 1
    endif

    segLen = winTime#[seg + 1] - winTime#[seg]
    if segLen > 0
        prog = (curT - winTime#[seg]) / segLen
        if prog < 0
            prog = 0
        endif
        if prog > 1
            prog = 1
        endif
    else
        prog = 0
    endif

    curFlat = flatness#[seg] + prog * (flatness#[seg + 1] - flatness#[seg])
    curFlux = flux#[seg]     + prog * (flux#[seg + 1]     - flux#[seg])

    # Orbit parameters driven by spectral features
    orbitR = baseRadius + curFlat * flatInfl
    if orbitR > 0.95
        orbitR = 0.95
    endif
    orbitSpd = baseSpeed + curFlux * fluxInfl

    # Advance orbit angle
    if gi > 1
        dt = curT - prevT
        orbitAngle = orbitAngle + 2 * pi * orbitSpd * dt
    endif

    # Source position in speaker space
    srcX = orbitR * cos(orbitAngle)
    srcY = orbitR * sin(orbitAngle)
    orbitX#[gi] = srcX
    orbitY#[gi] = srcY

    # DBAP gains. In the Surround 5.1 preset, channel 4 is LFE and is
    # deliberately excluded from the full-range panning normalization.
    totalPower = 0
    for ch from 1 to nChan
        if ch = lfeChannel
            chGain_'ch' = 0
        else
            dx   = srcX - spkX[ch]
            dy   = srcY - spkY[ch]
            dist = sqrt(dx * dx + dy * dy)
            if dist < minDist
                dist = minDist
            endif
            chGain_'ch' = 1 / (dist ^ rolloff)
            totalPower  = totalPower + chGain_'ch' * chGain_'ch'
        endif
    endfor

    # Power normalization over active full-range channels only.
    if totalPower > 0
        normFactor = sqrt(totalPower)
        for ch from 1 to nChan
            if ch <> lfeChannel
                chGain_'ch' = chGain_'ch' / normFactor
            endif
        endfor
    endif

    # Write to IntensityTiers. -120 dB is only a numerical floor for the
    # tier; the LFE channel is forced to exact zero after multiplication.
    for ch from 1 to nChan
        g = chGain_'ch'
        if g < 0.000001
            g = 0.000001
        endif
        gDb = 20 * log10(g)
        selectObject: chanTier_'ch'
        Add point: curT, gDb
    endfor

    prevT = curT
endfor

appendInfoLine: "  ", nChan, " channels | ", nGrid, " grid points per channel"

# ============================================================
# APPLY ENVELOPES
# ============================================================

appendInfoLine: ""
appendInfoLine: "[3/4] Rendering spatial output"

for ch from 1 to nChan
    selectObject: monoSrc
    chanCopy_'ch' = Copy: "spm_ch" + string$(ch)
    selectObject: chanCopy_'ch'
    plusObject: chanTier_'ch'
    # Do NOT rescale each rendered channel independently: that would undo
    # the DBAP ratios. Preserve the gain envelope exactly.
    Multiply: "no"
    chanOut_'ch' = selected("Sound")
    if ch = lfeChannel
        selectObject: chanOut_'ch'
        Formula: "0"
    endif
    removeObject: chanCopy_'ch', chanTier_'ch'
endfor

# Combine all channels
selectObject: chanOut_1
for ch from 2 to nChan
    plusObject: chanOut_'ch'
endfor
Combine to stereo
wetSound = selected("Sound")

# Cleanup channel copies
for ch from 1 to nChan
    removeObject: chanOut_'ch'
endfor

# Wet/dry mix. The wet path is always derived from the mono analysis source,
# so the dry reference is an unpanned mono bed distributed with equal power
# across the active full-range output channels. This gives drySnd exactly the
# same channel count as wetSound and avoids undefined row access for 3-8 ch.
if dryLevel > 0
    activeDryChannels = nChan
    if lfeChannel > 0
        activeDryChannels = nChan - 1
    endif
    drySpreadGain = 1 / sqrt(activeDryChannels)
    dryGainStr$ = fixed$(drySpreadGain, 12)

    for ch from 1 to nChan
        selectObject: monoSrc
        dryCh_'ch' = Copy: "spm_dry_ch" + string$(ch)
        selectObject: dryCh_'ch'
        if ch = lfeChannel
            Formula: "0"
        else
            Formula: "self * " + dryGainStr$
        endif
    endfor

    selectObject: dryCh_1
    for ch from 2 to nChan
        plusObject: dryCh_'ch'
    endfor
    Combine to stereo
    drySnd = selected("Sound")

    for ch from 1 to nChan
        removeObject: dryCh_'ch'
    endfor

    wStr$ = string$(wetLevel)
    dStr$ = string$(dryLevel)
    selectObject: wetSound
    Formula: "self * " + wStr$ + " + object[drySnd][row, col] * " + dStr$
    removeObject: drySnd
endif

selectObject: wetSound
peakVal = Get absolute extremum: 0, 0, "None"
if peakVal > 0
    Scale peak: 0.95
endif
Rename: srcName$ + "_SPM_" + presetName$
result = selected("Sound")
resultDur = Get total duration

removeObject: monoSrc

appendInfoLine: "  Output: ", srcName$, "_SPM_", presetName$,
    ... "  (", fixed$(resultDur, 2), " s  ", nChan, " ch)"

# ============================================================
# VISUALIZATION
# ============================================================

appendInfoLine: ""
appendInfoLine: "[4/4] Drawing visualization"

if draw_visualization = 1

    selectObject: srcSound
    origPeak = Get absolute extremum: 0, 0, "None"
    if origPeak < 0.001
        origPeak = 0.001
    endif
    ampMax = origPeak * 1.15

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.28
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Spectral Panning Mapper v1.1.4##"
    Select outer viewport: 0, 8, 0.28, 0.50
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half",
        ... "[" + presetName$ + "]  " + srcName$
        ... + "  |  " + string$(nChan) + " ch"
        ... + "  |  " + string$(nWindows) + " windows"
        ... + "  |  " + fixed$(updateHz, 0) + " Hz update"
        ... + "  |  mix " + fixed$(mixPct, 0) + "%"

    # === PANEL 1: Original waveform ===
    Select outer viewport: 0, 8, 0.62, 1.52
    Select inner viewport: 0.60, 7.70, 0.67, 1.47
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, srcDur, 0
    selectObject: srcSound
    Colour: "{0.45, 0.50, 0.58}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 0.62, 1.52
    Select inner viewport: 0.08, 0.52, 0.64, 1.50
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Input"
    Select outer viewport: 0, 8, 0.62, 1.52
    Select inner viewport: 0.6, 7.65, 0.57, 1.33
    Axes: 0, srcDur, -ampMax, ampMax
    Text top: "no", "Source waveform"

    # === PANEL 2: Spectral features ===
    Select outer viewport: 0, 8, 1.72, 2.62
    Select inner viewport: 0.60, 7.70, 1.47, 2.17
    Axes: 0, srcDur, -0.05, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -0.05, 1.15
    Colour: "{0.87, 0.87, 0.87}"
    Draw line: 0, 0, srcDur, 0
    Draw line: 0, 1, srcDur, 1

    # Flatness (orange)
    Colour: "{0.82, 0.42, 0.15}"
    Line width: 2
    for ww from 2 to nWindows
        Draw line: winTime#[ww-1], flatness#[ww-1], winTime#[ww], flatness#[ww]
    endfor

    # Flux (teal)
    Colour: "{0.18, 0.58, 0.52}"
    for ww from 2 to nWindows
        Draw line: winTime#[ww-1], flux#[ww-1], winTime#[ww], flux#[ww]
    endfor
    Line width: 1

    # Analysis point markers
    for ww from 1 to nWindows
        Colour: "{0.75, 0.75, 0.75}"
        Dotted line
        Draw line: winTime#[ww], -0.05, winTime#[ww], 1.15
        Solid line
    endfor

    Font size: 6
    Colour: "{0.82, 0.42, 0.15}"
    Text: srcDur * 0.78, "left", 1.07, "half", "Flatness (->radius)"
    Colour: "{0.18, 0.58, 0.52}"
    Text: srcDur * 0.78, "left", 0.94, "half", "Flux frame change (->speed)"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 1.72, 2.62
    Select inner viewport: 0.08, 0.52, 1.74, 2.60
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Feature"
    Select outer viewport: 0, 8, 1.72, 2.62
    Select inner viewport: 0.60, 7.70, 1.77, 2.57
    Axes: 0, srcDur, -0.05, 1.15
    Text top: "no", "Spectral features"

    # === PANEL 3: Speaker layout + orbit trace ===
    Select outer viewport: 0, 4, 2.90, 5.15
    Select inner viewport: 0.60, 3.85, 2.95, 5.10
    Axes: -1.35, 1.35, -1.35, 1.35
    Paint rectangle: "{0.96, 0.96, 0.97}", -1.35, 1.35, -1.35, 1.35

    # Unit circle reference
    Colour: "{0.88, 0.88, 0.88}"
    nCircPts = 60
    for cp from 1 to nCircPts - 1
        a1 = (cp - 1) * 2 * pi / nCircPts
        a2 = cp * 2 * pi / nCircPts
        Draw line: cos(a1), sin(a1), cos(a2), sin(a2)
    endfor

    # Orbit trace (subsample)
    traceStep = round(nGrid / 400)
    if traceStep < 1
        traceStep = 1
    endif
    Colour: "{0.70, 0.78, 0.88}"
    Line width: 1
    gi2 = 1 + traceStep
    while gi2 <= nGrid
        gi1 = gi2 - traceStep
        if gi1 < 1
            gi1 = 1
        endif
        Draw line: orbitX#[gi1], orbitY#[gi1], orbitX#[gi2], orbitY#[gi2]
        gi2 = gi2 + traceStep
    endwhile
    Line width: 1

    # Speaker dots (sized by average gain - compute from first grid point)
    srcX0 = orbitX#[1]
    srcY0 = orbitY#[1]
    for ch from 1 to nChan
        if ch <> lfeChannel
            dx0   = srcX0 - spkX[ch]
            dy0   = srcY0 - spkY[ch]
            dist0 = sqrt(dx0*dx0 + dy0*dy0)
            if dist0 < minDist
                dist0 = minDist
            endif
            g0 = 1 / (dist0 ^ rolloff)
            spkSz = 2.5 + g0 * 3.5
            if spkSz > 8
                spkSz = 8
            endif
            Paint circle (mm): "{0.25, 0.48, 0.72}", spkX[ch], spkY[ch], spkSz
            Colour: "White"
            Font size: 6
            Text: spkX[ch], "centre", spkY[ch], "half", string$(ch)
        endif
    endfor
    if lfeChannel > 0
        Colour: "{0.45, 0.45, 0.48}"
        Font size: 5
        Text: -1.28, "left", -1.23, "half", "Ch4 LFE reserved (silent)"
    endif

    # Listener position (green dot)
    Paint circle (mm): "{0.25, 0.65, 0.35}", 0, 0, 2.5

    # Source start position (red)
    Paint circle (mm): "{0.82, 0.25, 0.18}", orbitX#[1], orbitY#[1], 3.0
    Font size: 6
    Colour: "{0.60, 0.15, 0.10}"
    Text: orbitX#[1] + 0.08, "left", orbitY#[1] + 0.08, "half", "start"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Speaker layout + orbit"
    Text bottom: "yes", "X"
    Select outer viewport: 0.08, 0.52, 2.90, 5.15
    Select inner viewport: 0.08, 0.52, 2.92, 5.13
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Y"
    Select outer viewport: 0, 4, 2.90, 5.15
    Select inner viewport: 0.5, 3.75, 2.33, 4.15
    Axes: -1.35, 1.35, -1.35, 1.35

    # === PANEL 4: Orbit coordinates over time ===
    Select outer viewport: 4, 8, 2.90, 3.85
    Select inner viewport: 4.45, 7.70, 2.95, 3.80
    Axes: 0, srcDur, -1.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -1.1, 1.1
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, srcDur, 0

    # X trajectory (orange)
    Colour: "{0.82, 0.42, 0.15}"
    Line width: 1.2
    gi2 = 1 + traceStep
    while gi2 <= nGrid
        gi1 = gi2 - traceStep
        if gi1 < 1
            gi1 = 1
        endif
        Draw line: gridT#[gi1], orbitX#[gi1], gridT#[gi2], orbitX#[gi2]
        gi2 = gi2 + traceStep
    endwhile

    # Y trajectory (teal)
    Colour: "{0.18, 0.58, 0.52}"
    gi2 = 1 + traceStep
    while gi2 <= nGrid
        gi1 = gi2 - traceStep
        if gi1 < 1
            gi1 = 1
        endif
        Draw line: gridT#[gi1], orbitY#[gi1], gridT#[gi2], orbitY#[gi2]
        gi2 = gi2 + traceStep
    endwhile
    Line width: 1

    Font size: 6
    Colour: "{0.82, 0.42, 0.15}"
    Text: srcDur * 0.78, "left",  1.02, "half", "X"
    Colour: "{0.18, 0.58, 0.52}"
    Text: srcDur * 0.78, "left",  0.88, "half", "Y"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 4.04, 4.38, 2.90, 3.85
    Select inner viewport: 4.04, 4.38, 2.92, 3.83
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Position"
    Select outer viewport: 4, 8, 2.90, 3.85
    Select inner viewport: 4.45, 7.70, 2.95, 3.80
    Axes: 0, srcDur, -1.1, 1.1
    Text top: "no", "Orbit X/Y over time"

    # === PANEL 5: Per-channel gain heatmap over time ===
    Select outer viewport: 4, 8, 4.15, 5.15
    Select inner viewport: 4.45, 7.70, 4.20, 5.10

    # Sample gains at 50 time points for heatmap
    nHeat = 50
    Axes: 0, nHeat, 0, nChan
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nHeat, 0, nChan

    for hh from 1 to nHeat
        hT = (hh - 1) / (nHeat - 1) * srcDur
        # Find nearest grid point
        nearGi = round(hT / timeStep) + 1
        if nearGi < 1
            nearGi = 1
        endif
        if nearGi > nGrid
            nearGi = nGrid
        endif
        hSrcX = orbitX#[nearGi]
        hSrcY = orbitY#[nearGi]

        # Recompute gains at this point using the same active-channel rule
        # as the audio renderer (5.1 LFE excluded).
        hTotalPow = 0
        for ch from 1 to nChan
            if ch = lfeChannel
                hg_'ch' = 0
            else
                hdx = hSrcX - spkX[ch]
                hdy = hSrcY - spkY[ch]
                hd  = sqrt(hdx*hdx + hdy*hdy)
                if hd < minDist
                    hd = minDist
                endif
                hg_'ch' = 1 / (hd ^ rolloff)
                hTotalPow = hTotalPow + hg_'ch' * hg_'ch'
            endif
        endfor
        if hTotalPow > 0
            hNorm = sqrt(hTotalPow)
            for ch from 1 to nChan
                if ch <> lfeChannel
                    hg_'ch' = hg_'ch' / hNorm
                endif
            endfor
        endif

        for ch from 1 to nChan
            hgVal = hg_'ch'
            # Color: low gain = dark blue, high gain = bright orange
            cR = 0.10 + hgVal * 0.75
            cG = 0.25 + hgVal * 0.35
            cB = 0.65 - hgVal * 0.50
            cRs$ = fixed$(cR, 2)
            cGs$ = fixed$(cG, 2)
            cBs$ = fixed$(cB, 2)
            Paint rectangle: "{" + cRs$ + "," + cGs$ + "," + cBs$ + "}",
                ... hh - 1, hh, ch - 1, ch
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 4.04, 4.38, 4.15, 5.15
    Select inner viewport: 4.04, 4.38, 4.17, 5.13
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Channel"
    Select outer viewport: 4, 8, 4.15, 5.15
    Select inner viewport: 4.45, 7.70, 4.20, 5.10
    Axes: 0, nHeat, 0, nChan
    Text bottom: "yes", "Time ->"
    Text top: "no", "Gain per channel over time"

    # === PANEL 6: Output waveform ===
    Select outer viewport: 0, 8, 5.50, 6.45
    Select inner viewport: 0.60, 7.70, 5.55, 6.40
    Axes: 0, resultDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, resultDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, resultDur, 0
    selectObject: result
    Colour: "{0.22, 0.48, 0.72}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 5.50, 6.45
    Select inner viewport: 0.08, 0.52, 5.52, 6.43
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Output"
    Select outer viewport: 0, 8, 5.50, 6.45
    Select inner viewport: 0.60, 7.70, 5.55, 6.40
    Axes: 0, resultDur, -ampMax, ampMax
    Text top: "no", "Output waveform  (" + string$(nChan) + " ch combined)"

    # === SUMMARY ===
    Select outer viewport: 0, 8, 6.70, 7.70
    Select inner viewport: 0.60, 7.70, 6.77, 7.63
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.84, "half", "##Spectral Panning Mapper v1.1.4##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02, "left", 0.60, "half",
        ... "Source: " + srcName$ + "  (" + fixed$(srcDur,2) + " s)"
        ... + "  |  Preset: " + presetName$
        ... + "  |  Channels: " + string$(nChan)
        ... + "  |  Windows: " + string$(nWindows)
    Text: 0.02, "left", 0.37, "half",
        ... "Base radius: " + fixed$(baseRadius, 2)
        ... + "  Flatness->radius: " + fixed$(flatInfl, 2)
        ... + "  Base speed: " + fixed$(baseSpeed, 2) + " Hz"
        ... + "  Flux->speed: " + fixed$(fluxInfl, 2)
        ... + "  Rolloff: " + fixed$(rolloff, 2)
    Text: 0.02, "left", 0.13, "half",
        ... "Update: " + fixed$(updateHz, 0) + " Hz"
        ... + "  |  Mix: " + fixed$(mixPct, 0) + "% wet"
        ... + "  |  Grid points: " + string$(nGrid)
        ... + "  |  Output: " + srcName$ + "_SPM_" + presetName$
    Select inner viewport: 0.60, 7.70, 6.77, 7.63
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Select outer viewport: 0, 8, 0, 7.80
    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Picture complete"
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=================================================="
appendInfoLine: "Output   : ", srcName$, "_SPM_", presetName$
appendInfoLine: "Render   : ", fixed$(resultDur, 2), " s | ", nChan, " ch | ", fixed$(mixPct, 0), "% wet"
appendInfoLine: "Speakers :"
for ch from 1 to nChan
    infoX = spkX[ch]
    infoY = spkY[ch]
    if abs(infoX) < 0.0005
        infoX = 0
    endif
    if abs(infoY) < 0.0005
        infoY = 0
    endif
    if ch = lfeChannel
        appendInfoLine: "  Ch", ch, " LFE: reserved / silent (no crossover generated)"
    else
        appendInfoLine: "  Ch", ch, ": (", fixed$(infoX, 3), ", ", fixed$(infoY, 3), ")"
    endif
endfor

if play_result = 1
    Play
endif
