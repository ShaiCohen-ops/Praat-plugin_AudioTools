# ============================================================
# Praat AudioTools - Chaotic_Prosody_Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Creative prosody transformation using a chaotic/stochastic F0 target
#   and a deterministic Lorenz-derived amplitude envelope.
#   Logistic mode creates a deterministic chaotic F0 contour around the
#   measured mean F0. OU mode creates a stochastic mean-reverting contour.
#   The same F0 target and AM envelope are applied to every input channel,
#   while each channel is resynthesized independently to preserve channel count.
#
# Notes:
#   - This is creative PSOLA prosody resynthesis, not a physical voice model.
#   - The generated F0 target replaces the voiced F0 contour; it is not a
#     small perturbation of the original intonation.
#   - Lorenz_scale=0 disables Lorenz AM (unity multiplier).
#   - Random_seed affects OU pitch only; 0 uses an unpredictable seed.
#
# Changelog v0.5:
#   - Performance: Lorenz AM is now generated at control rate instead of
#     writing every audio sample with Set value at sample number.
#   - The control-rate envelope is applied by indexed lookup in one Sound Formula,
#     preserving the v0.4 piecewise-constant AM trajectory while avoiding O(N)
#     Praat command dispatch.
#   - Lorenz integration is skipped when AM scale=0 and visualization is off.
#   - DSP semantics, pitch target generation, multichannel PSOLA, Dry/Wet, and
#     safety behavior are unchanged.
#
# Changelog v0.4:
#   - Zero-based internal processing removes start-time dependence.
#   - Preserves arbitrary input channel count by per-channel PSOLA resynthesis.
#   - Added OU random seed and exact, stable OU discretization.
#   - Stabilized Lorenz integration with RK2 substeps independent of control rate.
#   - Lorenz AM is centred on unity; scale=0 now means no AM.
#   - Removed unconditional peak normalization; added attenuation-only Safety_peak.
#   - Added Dry_wet_percent with exact 0% bypass.
#   - Added multichannel-safe pitch-analysis fallback for anti-phase cancellation.
#   - Updated visualization to the AudioTools text/layout standard.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound_name$ = selected$("Sound")
selectObject: original
duration = Get total duration
sampling_rate = Get sampling frequency
num_channels = Get number of channels
xmin_original = Get start time
nyquist = sampling_rate / 2

form Chaotic Prosody Manipulation
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Chaos
        option Classic Lorenz
        option Wild Logistic
        option Stochastic Drift
        option Extreme Butterfly

    comment === Pitch Mode ===
    optionmenu Pitch_mode 1
        option Logistic chaos (deterministic)
        option Ornstein-Uhlenbeck (stochastic)
    positive Control_rate 100

    comment === Logistic Parameters ===
    real Logistic_r 3.9
    real Logistic_depth 0.35

    comment === OU Parameters ===
    real OU_theta 1.5
    real OU_sigma 20.0
    integer Random_seed 0

    comment === Lorenz AM Parameters ===
    real Lorenz_sigma 10.0
    real Lorenz_rho 28.0
    real Lorenz_beta 2.667
    real Lorenz_scale 0.6
    real AM_smoothing 0.85

    comment === Fade / Mix / Safety ===
    real Fadeout_duration 0.5
    real Dry_wet_percent 100
    real Safety_peak 0.99

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    pitch_mode = 1
    logistic_r = 3.7
    logistic_depth = 0.15
    lorenz_scale = 0.3
    aM_smoothing = 0.92
    presetName$ = "Gentle Chaos"
elsif preset = 3
    pitch_mode = 1
    logistic_r = 3.9
    logistic_depth = 0.25
    lorenz_sigma = 10.0
    lorenz_rho = 28.0
    lorenz_beta = 2.667
    lorenz_scale = 0.5
    aM_smoothing = 0.85
    presetName$ = "Classic Lorenz"
elsif preset = 4
    pitch_mode = 1
    logistic_r = 3.99
    logistic_depth = 0.5
    lorenz_scale = 0.7
    aM_smoothing = 0.75
    presetName$ = "Wild Logistic"
elsif preset = 5
    pitch_mode = 2
    oU_theta = 1.0
    oU_sigma = 30.0
    lorenz_scale = 0.4
    aM_smoothing = 0.9
    presetName$ = "Stochastic Drift"
elsif preset = 6
    pitch_mode = 1
    logistic_r = 3.95
    logistic_depth = 0.45
    lorenz_sigma = 12.0
    lorenz_rho = 35.0
    lorenz_scale = 0.8
    aM_smoothing = 0.7
    presetName$ = "Extreme Butterfly"
else
    presetName$ = "Custom"
endif

# ============================================================
# VALIDATION
# ============================================================
if duration < 0.05
    exitScript: "Sound too short (minimum 0.05 s)."
endif
if logistic_r <= 0 or logistic_r > 4
    exitScript: "Logistic_r must be > 0 and <= 4."
endif
if logistic_depth < 0
    exitScript: "Logistic_depth must be >= 0."
endif
if oU_theta < 0 or oU_sigma < 0
    exitScript: "OU_theta and OU_sigma must be >= 0."
endif
if lorenz_sigma <= 0 or lorenz_rho <= 0 or lorenz_beta <= 0
    exitScript: "Lorenz sigma, rho, and beta must be > 0."
endif
if lorenz_scale < 0
    exitScript: "Lorenz_scale must be >= 0."
endif
if aM_smoothing < 0 or aM_smoothing > 1
    exitScript: "AM_smoothing must be between 0 and 1."
endif
if fadeout_duration < 0
    exitScript: "Fadeout_duration must be >= 0."
endif
if dry_wet_percent < 0 or dry_wet_percent > 100
    exitScript: "Dry_wet_percent must be between 0 and 100."
endif
if safety_peak < 0
    exitScript: "Safety_peak must be >= 0."
endif

fadeout_duration = min(fadeout_duration, duration)
wet_amount = dry_wet_percent / 100
dry_amount = 1 - wet_amount

# Avoid impractically dense control-rate loops while keeping a large margin
# below Nyquist. Report the effective value if a custom rate is excessive.
effective_control_rate = min(control_rate, 1000, sampling_rate / 4)
dt = 1 / effective_control_rate

if pitch_mode = 1
    pitchModeShort$ = "Logistic"
else
    pitchModeShort$ = "OU"
endif

writeInfoLine: "=== Chaotic Prosody Manipulation v0.4 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Pitch mode: ", pitchModeShort$
appendInfoLine: "Control rate: ", fixed$(effective_control_rate, 2), " Hz"
if effective_control_rate <> control_rate
    appendInfoLine: "Requested control rate clamped from ", fixed$(control_rate, 2), " Hz"
endif
if pitch_mode = 2
    if random_seed = 0
        appendInfoLine: "OU seed: unpredictable"
    else
        appendInfoLine: "OU seed: ", random_seed
    endif
endif
appendInfoLine: ""

# ============================================================
# ZERO-BASED WORKING COPY
# ============================================================
selectObject: original
workAll = Copy: "cpm_work"
if xmin_original <> 0
    Shift times by: -xmin_original
endif
n_samples = Get number of samples
source_peak = Get absolute extremum: 0, 0, "None"

# ============================================================
# PITCH ANALYSIS WITH MULTICHANNEL FALLBACK
# ============================================================
appendInfoLine: "Analyzing pitch..."
selectObject: workAll
if num_channels > 1
    analysisSound = Convert to mono
else
    analysisSound = Copy: "cpm_analysis"
endif
selectObject: analysisSound
analysisPitch = To Pitch: 0, 75, 600
f0_base = Get mean: 0, 0, "Hertz"
pitchAnalysisSource$ = "mono"

if f0_base = undefined and num_channels > 1
    removeObject: analysisPitch
    f0_base = undefined
    for ch from 1 to num_channels
        if f0_base = undefined
            selectObject: workAll
            fallbackCh = Extract one channel: ch
            fallbackPitch = To Pitch: 0, 75, 600
            candidateF0 = Get mean: 0, 0, "Hertz"
            if candidateF0 <> undefined
                f0_base = candidateF0
                pitchAnalysisSource$ = "channel " + string$(ch) + " fallback"
            endif
            removeObject: fallbackPitch, fallbackCh
        endif
    endfor
else
    removeObject: analysisPitch
endif
removeObject: analysisSound

if f0_base = undefined
    f0_base = 150
    pitchAnalysisSource$ = "fallback 150 Hz (unpitched input)"
endif

appendInfoLine: "Base F0: ", fixed$(f0_base, 2), " Hz"
appendInfoLine: "Pitch analysis source: ", pitchAnalysisSource$

# Target F0 safety bounds. The analysis ceiling remains 600 Hz, while the
# generated target may move higher; keep it comfortably below Nyquist.
f0_min = 20
f0_max = min(1200, nyquist * 0.8)
if f0_max < f0_min
    f0_max = max(5, nyquist * 0.5)
endif

# ============================================================
# GENERATE GLOBAL CHAOTIC / STOCHASTIC PITCH TARGET
# ============================================================
n_points = max(2, ceiling(duration * effective_control_rate) + 1)
Create PitchTier: sound_name$ + "_chaotic_target", 0, duration
pitchtier_new = selected("PitchTier")

maxVizPoints = min(500, n_points)
vizTimes# = zero#(maxVizPoints)
vizPitch# = zero#(maxVizPoints)
vizChaosX# = zero#(maxVizPoints)
vizCount = 0
vizStoreEvery = max(1, ceiling(n_points / maxVizPoints))

if pitch_mode = 1
    x = 0.5
    for i from 1 to n_points
        t = min(duration, (i - 1) * dt)
        x = logistic_r * x * (1 - x)
        factor = 1 + logistic_depth * (2 * x - 1)
        f0 = f0_base * factor
        f0 = max(f0_min, min(f0_max, f0))

        selectObject: pitchtier_new
        Add point: t, f0

        if (i = 1 or i = n_points or ((i - 1) mod vizStoreEvery) = 0) and vizCount < maxVizPoints
            vizCount = vizCount + 1
            vizTimes#[vizCount] = t
            vizPitch#[vizCount] = f0
            vizChaosX#[vizCount] = x
        endif
    endfor
else
    if random_seed <> 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
    endif

    f0 = f0_base
    for i from 1 to n_points
        t = min(duration, (i - 1) * dt)
        if i > 1
            noise = randomGauss(0, 1)
            if oU_theta > 0
                decay = exp(-oU_theta * dt)
                varianceFactor = (1 - exp(-2 * oU_theta * dt)) / (2 * oU_theta)
                f0 = f0_base + (f0 - f0_base) * decay + oU_sigma * sqrt(max(0, varianceFactor)) * noise
            else
                f0 = f0 + oU_sigma * sqrt(dt) * noise
            endif
            f0 = max(f0_min, min(f0_max, f0))
        endif

        selectObject: pitchtier_new
        Add point: t, f0

        if (i = 1 or i = n_points or ((i - 1) mod vizStoreEvery) = 0) and vizCount < maxVizPoints
            vizCount = vizCount + 1
            vizTimes#[vizCount] = t
            vizPitch#[vizCount] = f0
            if oU_sigma > 0
                vizChaosX#[vizCount] = 0.5 + 0.25 * (f0 - f0_base) / max(oU_sigma, 1)
            else
                vizChaosX#[vizCount] = 0.5
            endif
        endif
    endfor

    if random_seed <> 0
        random_initializeSafelyAndUnpredictably ()
    endif
endif

# ============================================================
# APPLY THE SAME TARGET PITCH TO EACH CHANNEL INDEPENDENTLY
# ============================================================
appendInfoLine: "Resynthesizing ", num_channels, " channel(s)..."
repitchedAll = Create Sound from formula: "cpm_repitched", num_channels, 0, duration, sampling_rate, "0"

for ch from 1 to num_channels
    selectObject: workAll
    channelSound = Extract one channel: ch
    channelManip = To Manipulation: 0.01, 75, 600

    selectObject: channelManip
    plusObject: pitchtier_new
    Replace pitch tier

    selectObject: channelManip
    channelResult = Get resynthesis (overlap-add)

    selectObject: repitchedAll
    Formula (part): 0, duration, ch, ch, "object['channelResult:0', 1, col]"

    removeObject: channelSound, channelManip, channelResult
endfor
removeObject: pitchtier_new

# ============================================================
# LORENZ AM CONTROL (CONTROL-RATE STORAGE)
# ============================================================
appendInfoLine: "Generating Lorenz amplitude control..."

lx = 1.0
ly = 1.0
lz = 1.0
smoothed_value = 0.5

maxLorenzPoints = 500
lorenzX# = zero#(maxLorenzPoints)
lorenzY# = zero#(maxLorenzPoints)
lorenzZ# = zero#(maxLorenzPoints)
lorenzAM# = zero#(maxLorenzPoints)
lorenzTimes# = zero#(maxLorenzPoints)
lorenzIdx = 0

controlInterval = max(1, round(sampling_rate / effective_control_rate))
actualControlDt = controlInterval / sampling_rate
lorenzSubsteps = max(1, ceiling(actualControlDt / 0.005))
lorenzH = actualControlDt / lorenzSubsteps
totalControlUpdates = ceiling(n_samples / controlInterval)
lorenzStoreInterval = max(1, ceiling(totalControlUpdates / maxLorenzPoints))

# Store only one AM value per control update. v0.4 wrote the same value into
# every audio sample until the next update; indexed lookup below reproduces
# that step-held trajectory without hundreds of thousands of Praat commands.
am_control = Create Sound from formula: "cpm_am_control", 1, 0, totalControlUpdates, 1, "1"

if lorenz_scale > 0 or draw_visualization
    am_value = 1
    for u from 1 to totalControlUpdates
        t = (u - 1) * actualControlDt

        for ls from 1 to lorenzSubsteps
            dx1 = lorenz_sigma * (ly - lx)
            dy1 = lx * (lorenz_rho - lz) - ly
            dz1 = lx * ly - lorenz_beta * lz

            x_mid = lx + 0.5 * lorenzH * dx1
            y_mid = ly + 0.5 * lorenzH * dy1
            z_mid = lz + 0.5 * lorenzH * dz1

            dx2 = lorenz_sigma * (y_mid - x_mid)
            dy2 = x_mid * (lorenz_rho - z_mid) - y_mid
            dz2 = x_mid * y_mid - lorenz_beta * z_mid

            lx = lx + lorenzH * dx2
            ly = ly + lorenzH * dy2
            lz = lz + lorenzH * dz2
        endfor

        z_normalized = (lz - 20) / 30
        z_normalized = max(0, min(1, z_normalized))
        smoothed_value = aM_smoothing * smoothed_value + (1 - aM_smoothing) * z_normalized
        am_value = 1 + lorenz_scale * (smoothed_value - 0.5)
        am_value = max(0, am_value)

        selectObject: am_control
        Set value at sample number: 1, u, am_value

        if (u mod lorenzStoreInterval) = 0 and lorenzIdx < maxLorenzPoints
            lorenzIdx = lorenzIdx + 1
            lorenzX#[lorenzIdx] = lx
            lorenzY#[lorenzIdx] = ly
            lorenzZ#[lorenzIdx] = lz
            storeAmp = am_value
            if fadeout_duration > 0 and t > duration - fadeout_duration
                storeFade = max(0, min(1, (duration - t) / fadeout_duration))
                storeAmp = storeAmp * storeFade
            endif
            lorenzAM#[lorenzIdx] = storeAmp
            lorenzTimes#[lorenzIdx] = min(duration, t)
        endif
    endfor
else
    appendInfoLine: "Lorenz integration skipped (AM scale=0)."
endif

appendInfoLine: "Lorenz control updates: ", totalControlUpdates
appendInfoLine: "Lorenz control points stored: ", lorenzIdx

# ============================================================
# APPLY AM, DRY/WET MIX, SAFETY
# ============================================================
selectObject: repitchedAll
wetSound = Copy: "cpm_wet"
intervalStr$ = string$(controlInterval)
controlUpdatesStr$ = string$(totalControlUpdates)
if lorenz_scale > 0
    Formula: "self * object['am_control:0', 1, min(" + controlUpdatesStr$ + ", floor((col-1)/" + intervalStr$ + ") + 1)]"
endif
if fadeout_duration > 0
    srStr$ = fixed$(sampling_rate, 12)
    durationStr$ = fixed$(duration, 12)
    fadeStr$ = fixed$(fadeout_duration, 12)
    Formula: "self * (if ((col-1)/" + srStr$ + ") > " + durationStr$ + " - " + fadeStr$ + " then max(0, min(1, (" + durationStr$ + " - ((col-1)/" + srStr$ + ")) / " + fadeStr$ + ")) else 1 fi)"
endif

if wet_amount <= 0
    selectObject: workAll
    result = Copy: "cpm_result"
else
    selectObject: wetSound
    result = Copy: "cpm_result"
    if wet_amount < 1
        Formula: "self * 'wet_amount:10' + object['workAll:0', row, col] * 'dry_amount:10'"
    endif

    if safety_peak > 0
        processedPeak = Get absolute extremum: 0, 0, "None"
        if processedPeak > safety_peak
            safetyGain = safety_peak / processedPeak
            Formula: "self * 'safetyGain:12'"
            appendInfoLine: "Safety attenuation: ", fixed$(20 * log10(safetyGain), 2), " dB"
        else
            appendInfoLine: "Safety attenuation: none"
        endif
    else
        appendInfoLine: "Safety attenuation: disabled"
    endif
endif

selectObject: result
if xmin_original <> 0
    Shift times by: xmin_original
endif
Rename: sound_name$ + "_chaotic_" + presetName$
finalName$ = selected$("Sound")

# ============================================================
# VISUALIZATION - AUDIOTOOLS TEXT/LAYOUT STANDARD
# ============================================================
if draw_visualization
    # Zero-based mono display copies so waveform time matches control plots.
    selectObject: original
    if num_channels > 1
        origDisplay = Convert to mono
    else
        origDisplay = Copy: "cpm_origDisplay"
    endif
    if xmin_original <> 0
        Shift times by: -xmin_original
    endif

    selectObject: result
    if num_channels > 1
        resultDisplay = Convert to mono
    else
        resultDisplay = Copy: "cpm_resultDisplay"
    endif
    if xmin_original <> 0
        Shift times by: -xmin_original
    endif

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Chaotic Prosody Manipulation##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half",
    ... sound_name$ + "  |  " + presetName$ + "  |  " + pitchModeShort$

    # Input waveform.
    Select outer viewport: 0, 8, 0.72, 1.38
    Select inner viewport: 0.65, 7.65, 0.80, 1.31
    selectObject: origDisplay
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, duration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform.
    Select outer viewport: 0, 8, 1.46, 2.14
    Select inner viewport: 0.65, 7.65, 1.54, 2.05
    selectObject: resultDisplay
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, duration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Chaotic pitch target.
    minP = f0_base
    maxP = f0_base
    for vp from 1 to vizCount
        if vizPitch#[vp] < minP
            minP = vizPitch#[vp]
        endif
        if vizPitch#[vp] > maxP
            maxP = vizPitch#[vp]
        endif
    endfor
    pMargin = max(10, (maxP - minP) * 0.1)

    Select outer viewport: 0, 8, 2.30, 3.32
    Select inner viewport: 0.65, 7.65, 2.40, 3.22
    Axes: 0, duration, minP - pMargin, maxP + pMargin
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minP - pMargin, maxP + pMargin
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, f0_base, duration, f0_base
    Solid line
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.5
    for vp from 2 to vizCount
        Draw line: vizTimes#[vp - 1], vizPitch#[vp - 1], vizTimes#[vp], vizPitch#[vp]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Target F0 (Hz)"
    Text bottom: "yes", "Time (s)"

    # Lorenz XY projection.
    Select outer viewport: 0, 4, 3.50, 4.75
    Select inner viewport: 0.65, 3.75, 3.60, 4.65
    if lorenzIdx > 1
        minLX = lorenzX#[1]
        maxLX = lorenzX#[1]
        minLY = lorenzY#[1]
        maxLY = lorenzY#[1]
        for lp from 2 to lorenzIdx
            minLX = min(minLX, lorenzX#[lp])
            maxLX = max(maxLX, lorenzX#[lp])
            minLY = min(minLY, lorenzY#[lp])
            maxLY = max(maxLY, lorenzY#[lp])
        endfor
        lMargin = max(1, max(maxLX - minLX, maxLY - minLY) * 0.1)
        Axes: minLX - lMargin, maxLX + lMargin, minLY - lMargin, maxLY + lMargin
        Paint rectangle: "{0.97, 0.97, 0.97}", minLX - lMargin, maxLX + lMargin, minLY - lMargin, maxLY + lMargin
        Colour: "{0.50, 0.35, 0.72}"
        for lp from 2 to lorenzIdx
            Draw line: lorenzX#[lp - 1], lorenzY#[lp - 1], lorenzX#[lp], lorenzY#[lp]
        endfor
    else
        Axes: -20, 20, -30, 30
        Paint rectangle: "{0.97, 0.97, 0.97}", -20, 20, -30, 30
    endif
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Lorenz Y"
    Text bottom: "yes", "Lorenz X"

    # Actual AM multiplier trajectory.
    Select outer viewport: 4, 8, 3.50, 4.75
    Select inner viewport: 4.45, 7.65, 3.60, 4.65
    amMin = 1
    amMax = 1
    for lp from 1 to lorenzIdx
        amMin = min(amMin, lorenzAM#[lp])
        amMax = max(amMax, lorenzAM#[lp])
    endfor
    amMargin = max(0.05, (amMax - amMin) * 0.15)
    Axes: 0, duration, max(0, amMin - amMargin), amMax + amMargin
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, max(0, amMin - amMargin), amMax + amMargin
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 1, duration, 1
    Solid line
    if lorenzIdx > 1
        Colour: "{0.22, 0.46, 0.82}"
        for lp from 2 to lorenzIdx
            Draw line: lorenzTimes#[lp - 1], lorenzAM#[lp - 1], lorenzTimes#[lp], lorenzAM#[lp]
        endfor
    endif
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "AM multiplier"
    Text bottom: "yes", "Time (s)"

    # Summary panel: heading + two short left-aligned lines.
    Select outer viewport: 0, 8, 4.90, 5.62
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    if pitch_mode = 1
        summaryPitch$ = "Pitch: Logistic r=" + fixed$(logistic_r, 2) + " | depth=" + fixed$(logistic_depth, 2) + " | base F0=" + fixed$(f0_base, 1) + " Hz"
    else
        summaryPitch$ = "Pitch: OU theta=" + fixed$(oU_theta, 2) + " | sigma=" + fixed$(oU_sigma, 1) + " | base F0=" + fixed$(f0_base, 1) + " Hz"
    endif
    Text: 0.02, "left", 0.50, "half", summaryPitch$
    summaryAM$ = "Lorenz: sigma=" + fixed$(lorenz_sigma, 1) + " | rho=" + fixed$(lorenz_rho, 1) + " | beta=" + fixed$(lorenz_beta, 3) + " | AM scale=" + fixed$(lorenz_scale, 2) + " | Wet=" + fixed$(dry_wet_percent, 0) + "%"
    Text: 0.02, "left", 0.18, "half", summaryAM$

    Font size: 10
    Colour: "Black"
    Line width: 1
    removeObject: origDisplay, resultDisplay
endif

# ============================================================
# CLEANUP / REPORT / OUTPUT
# ============================================================
removeObject: workAll, repitchedAll, wetSound, am_control

selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Created: ", finalName$
appendInfoLine: "Channels: ", num_channels
appendInfoLine: "Start time: ", fixed$(xmin_original, 6), " s"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"

if play_result
    Play
endif
selectObject: result
