# ============================================================
# Praat AudioTools - Chaotic Function Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Two related classes of deterministic nonlinear generators:
#
#   A. Singular / highly oscillatory mathematical functions
#      These are sampled directly as waveforms. They are not claimed to be
#      chaotic dynamical systems. Built-ins use normalized time u=t/T.
#      They are rendered at up to 4x the requested sample rate and then
#      resampled down to reduce (not mathematically eliminate) aliasing near
#      singular regions.
#
#   B. Iterated dynamical maps
#      Logistic, tent and Henon trajectories are computed at a control rate,
#      band-limited to audio rate, mapped to a bounded instantaneous-frequency
#      trajectory, and integrated to phase before sine-wave synthesis.
#
# v0.4 reviewed:
#   - Removed the selectable menu "separator" that silently rendered sin(1/x).
#   - Renamed misleading "Lorenz-like" preset to "Henon Attractor".
#   - Chaos_parameter now actually drives the custom-r Logistic map/preset.
#   - Added burn-in before recording map trajectories.
#   - Tent map uses mu=1.9999 rather than exactly 2.0; the exact slope-2 map
#     collapses rapidly under finite binary arithmetic.
#   - Removed random resets from the standard Henon trajectory.
#   - Replaced incorrect sin(2*pi*f*t*(1+m(t))) map synthesis with:
#         f_inst[n] = f0 * (1 + depth * m[n])
#         phi[n]    = phi[n-1] + 2*pi*f_inst[n]/Fs
#         y[n]      = sin(phi[n])
#     so the requested deviation is genuinely bounded.
#   - Added Nyquist-aware carrier correction and FM-depth validation.
#   - Added reproducible Random_seed (0 = unpredictable).
#   - Singular built-ins are oversampled then anti-aliased by Resample.
#   - Corrected exp(-1/u^2)*sin(50u): 50 is now radians per normalized u,
#     rather than silently becoming 50 full cycles.
#   - Normalized the multi-sine coefficient sum and the asymmetric two-sine
#     expression to avoid hard clipping as part of their definition.
#   - Removed hard sample clipping; optional normalization is final/common.
#     A down-only safety scale is used only if normalization is disabled and
#     the direct singular/custom waveform exceeds the normal playback range.
#   - Stereo Wide is now short-delay decorrelation, not a spectral L/R split.
#   - Rotating mode is equal-power.
#   - One combined edge envelope avoids overlap/double-fade on short sounds.
#   - Visualization rebuilt around the actual mechanism:
#       * singular: sampled mathematical model -> measured output -> spectrum
#       * maps: actual return-map/Henon geometry -> instantaneous frequency
#               -> measured spectrogram with model trajectory overlay
#       * process equation + compact QC
# ============================================================

form Chaotic Function Generator v0.4
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Singularity
        option Dense Oscillation
        option Logistic Chaos
        option Henon Attractor
        option Tent Map Texture

    comment === Basic Settings ===
    positive Duration_s 1.0
    integer Sample_rate_Hz 44100

    comment === Function Type ===
    optionmenu Function_type 1
        option sin(1/u)
        option sin((1/u)*(1/(1-u)))
        option Multi-sine singular mixture
        option sin(3/u)*sin(5/(1-u))
        option sin(1/u) + 2*sin(1/(1-u))
        option tan(1/u)*cos(1/(1-u))
        option sin(1/u^2)*cos(1/(1-u)^2)
        option exp(-1/u^2)*sin(50u)
        option sin(1/u)*cos(1/u^2)
        option sin(1/(u(1-u)))
        option sin(ln(u))*cos(ln(1-u))
        option Logistic Map (r = Chaos_parameter)
        option Logistic Map (r = 3.7)
        option Tent Map (mu = 1.9999)
        option Henon Map (a=1.4, b=0.3)
        option Custom Formula

    comment === Iterated-map sonification ===
    positive Map_carrier_frequency_Hz 200
    positive Control_rate_Hz 1000
    real FM_depth_fraction 0.65
    real Chaos_parameter 3.9

    comment === Randomness / Output ===
    integer Random_seed 0
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1

    comment === Custom direct waveform ===
    comment Built-ins use u=t/T. For Custom, use x/duration_s if normalized time is desired.
    text Custom_formula sin(1/((x/duration_s)+eps))
endform

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
presetName$ = "Custom"

if preset = 2
    duration_s = 2.0
    function_type = 1
    spatial_mode = 1
    presetName$ = "Gentle Singularity"

elsif preset = 3
    duration_s = 1.5
    function_type = 3
    spatial_mode = 2
    presetName$ = "Dense Oscillation"

elsif preset = 4
    duration_s = 3.0
    function_type = 12
    map_carrier_frequency_Hz = 200
    control_rate_Hz = 500
    fM_depth_fraction = 0.65
    chaos_parameter = 3.95
    spatial_mode = 3
    presetName$ = "Logistic Chaos"

elsif preset = 5
    duration_s = 4.0
    function_type = 15
    map_carrier_frequency_Hz = 150
    control_rate_Hz = 800
    fM_depth_fraction = 0.65
    spatial_mode = 3
    presetName$ = "Henon Attractor"

elsif preset = 6
    duration_s = 2.0
    function_type = 14
    map_carrier_frequency_Hz = 300
    control_rate_Hz = 600
    fM_depth_fraction = 0.75
    spatial_mode = 2
    presetName$ = "Tent Map Texture"
endif

# ---------------------------------------------------------------------------
# 1. LABELS / VALIDATION
# ---------------------------------------------------------------------------
if function_type = 1
    functionLabel$ = "sin(1/u)"
elsif function_type = 2
    functionLabel$ = "sin((1/u)*(1/(1-u)))"
elsif function_type = 3
    functionLabel$ = "Multi-sine singular mixture"
elsif function_type = 4
    functionLabel$ = "sin(3/u)*sin(5/(1-u))"
elsif function_type = 5
    functionLabel$ = "sin(1/u) + 2*sin(1/(1-u))"
elsif function_type = 6
    functionLabel$ = "tan(1/u)*cos(1/(1-u))"
elsif function_type = 7
    functionLabel$ = "sin(1/u^2)*cos(1/(1-u)^2)"
elsif function_type = 8
    functionLabel$ = "exp(-1/u^2)*sin(50u)"
elsif function_type = 9
    functionLabel$ = "sin(1/u)*cos(1/u^2)"
elsif function_type = 10
    functionLabel$ = "sin(1/(u(1-u)))"
elsif function_type = 11
    functionLabel$ = "sin(ln(u))*cos(ln(1-u))"
elsif function_type = 12
    functionLabel$ = "Logistic Map (custom r)"
elsif function_type = 13
    functionLabel$ = "Logistic Map (r=3.7)"
elsif function_type = 14
    functionLabel$ = "Tent Map (mu=1.9999)"
elsif function_type = 15
    functionLabel$ = "Henon Map (a=1.4, b=0.3)"
else
    functionLabel$ = "Custom Formula"
endif

isIteratedMap = 0
if function_type >= 12 and function_type <= 15
    isIteratedMap = 1
endif

if duration_s <= 0
    exitScript: "Duration must be greater than zero."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

if isIteratedMap
    if control_rate_Hz < 20
        exitScript: "Control rate must be at least 20 Hz for iterated maps."
    endif
    if control_rate_Hz > min(5000, sample_rate_Hz / 4)
        control_rate_Hz = min(5000, sample_rate_Hz / 4)
    endif
    if map_carrier_frequency_Hz <= 0
        exitScript: "Map carrier frequency must be greater than zero."
    endif
    if fM_depth_fraction < 0 or fM_depth_fraction > 0.95
        exitScript: "FM depth fraction must be between 0 and 0.95."
    endif
    if function_type = 12
        if chaos_parameter <= 0 or chaos_parameter > 4
            exitScript: "For the Logistic map, Chaos_parameter must be > 0 and <= 4."
        endif
    endif
endif

# Praat form identifiers beginning with capitals are canonicalized.
fmDepth = fM_depth_fraction

twoPi = 2 * pi
sqrtTwo = sqrt(2)
eps = 1e-4
safeTop = 0.45 * sample_rate_Hz
uid$ = string$(randomInteger(10000, 99999))

carrierCorrected = 0
if isIteratedMap
    maxCarrier = safeTop / (1 + fmDepth)
    if map_carrier_frequency_Hz > maxCarrier
        map_carrier_frequency_Hz = maxCarrier
        carrierCorrected = 1
    endif
endif

# Reproducible initial state / custom random formula if requested.
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  CHAOTIC FUNCTION GENERATOR v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Function: ", functionLabel$
appendInfoLine: "Duration: ", fixed$(duration_s, 3), " s"
appendInfoLine: "Sample rate: ", sample_rate_Hz, " Hz"

if isIteratedMap
    appendInfoLine: "Map carrier: ", fixed$(map_carrier_frequency_Hz, 2), " Hz"
    appendInfoLine: "FM depth: +/-", fixed$(100 * fmDepth, 1), "%"
    appendInfoLine: "Control rate: ", fixed$(control_rate_Hz, 1), " Hz"
else
    appendInfoLine: "Mode: direct sampled mathematical waveform"
endif
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

# Objects retained for visualization when relevant.
modelSound = 0
controlSound = 0
henonYSound = 0
instFreqSound = 0
mapBurnIn = 0
mapR = 0
tentMu = 0
controlMin = 0
controlMax = 0
safetyScaled = 0

# ---------------------------------------------------------------------------
# 2A. SINGULAR / DIRECT MATHEMATICAL FUNCTIONS
# ---------------------------------------------------------------------------
if isIteratedMap = 0
    appendInfoLine: "Rendering direct mathematical waveform..."

    # Oversample up to 4x, capped at 192 kHz, then anti-alias down to target Fs.
    internalRate = min(192000, 4 * sample_rate_Hz)

    if function_type = 1
        formula$ = "sin(1/((x/duration_s)+eps))"

    elsif function_type = 2
        formula$ = "sin((1/((x/duration_s)+eps))*(1/((1-(x/duration_s))+eps)))"

    elsif function_type = 3
        # Coefficient sum = 10, so divide by 10 instead of hard clipping.
        formula$ = "((2*sin(3/((x/duration_s)+eps)))+(3*cos(5/((x/duration_s)+eps)))+(4*sin(6/((x/duration_s)+eps)))+(cos(3/((x/duration_s)+eps))))/10"

    elsif function_type = 4
        formula$ = "sin(3/((x/duration_s)+eps))*sin(5/((1-(x/duration_s))+eps))"

    elsif function_type = 5
        # Theoretical peak <= 3.
        formula$ = "(sin(1/((x/duration_s)+eps))+(2*sin(1/((1-(x/duration_s))+eps))))/3"

    elsif function_type = 6
        formula$ = "max(-1,min(1,tan(1/((x/duration_s)+eps))))*cos(1/((1-(x/duration_s))+eps))"

    elsif function_type = 7
        formula$ = "sin(1/(((x/duration_s)+eps)^2))*cos(1/(((1-(x/duration_s))+eps)^2))"

    elsif function_type = 8
        # Literal normalized-time formula: exp(-1/u^2) * sin(50u)
        formula$ = "exp(-1/(((x/duration_s)+eps)^2))*sin(50*(x/duration_s))"

    elsif function_type = 9
        formula$ = "sin(1/((x/duration_s)+eps))*cos(1/(((x/duration_s)+eps)^2))"

    elsif function_type = 10
        formula$ = "sin(1/(((x/duration_s)+eps)*((1-(x/duration_s))+eps)))"

    elsif function_type = 11
        formula$ = "sin(ln((x/duration_s)+0.01))*cos(ln((1-(x/duration_s))+0.01))"

    else
        formula$ = custom_formula$
    endif

    highRateSound = Create Sound from formula: "chaos_hi_" + uid$, 1, 0, duration_s, internalRate, formula$

    if internalRate <> sample_rate_Hz
        selectObject: highRateSound
        outputSound = Resample: sample_rate_Hz, 50
        removeObject: highRateSound
    else
        outputSound = highRateSound
    endif

    # Keep the sampled mathematical trajectory before edge/spatial processing.
    if draw_visualization
        selectObject: outputSound
        Copy: "chaos_model_" + uid$
        modelSound = selected("Sound")
    endif

    # Avoid hidden hard clipping. If normalization is off, only scale DOWN when
    # the direct/custom formula exceeds Praat's normal playback amplitude range.
    selectObject: outputSound
    directPeak = Get absolute extremum: 0, 0, "None"
    if normalize_output = 0 and directPeak > 0.98
        Scale peak: 0.98
        safetyScaled = 1
    endif

    appendInfoLine: "Internal singular render rate: ", fixed$(internalRate, 0), " Hz"
    if internalRate > sample_rate_Hz
        appendInfoLine: "Anti-alias step: downsampled with sinc resampling"
    endif

# ---------------------------------------------------------------------------
# 2B. ITERATED MAPS -> BOUNDED INSTANTANEOUS FREQUENCY
# ---------------------------------------------------------------------------
else
    appendInfoLine: "Computing iterated map..."

    controlSound = Create Sound from formula: "chaos_control_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
    selectObject: controlSound
    nControlPoints = Get number of samples

    if nControlPoints < 4
        exitScript: "The duration/control-rate combination produces too few map points."
    endif

    # Initialize and burn in before recording the audible trajectory.
    if function_type = 12 or function_type = 13
        mapX = randomUniform(0.11, 0.89)
        if function_type = 12
            mapR = chaos_parameter
        else
            mapR = 3.7
        endif
        mapBurnIn = 200

        for burn to mapBurnIn
            mapX = mapR * mapX * (1 - mapX)
        endfor

    elsif function_type = 14
        # Exactly mu=2 is mathematically standard, but finite binary arithmetic
        # eventually collapses to a short/zero orbit. 1.9999 remains chaotic
        # over practical AudioTools durations without silently degenerating.
        tentMu = 1.9999
        mapX = randomUniform(0.11, 0.89)
        mapBurnIn = 100

        for burn to mapBurnIn
            if mapX < 0.5
                mapX = tentMu * mapX
            else
                mapX = tentMu * (1 - mapX)
            endif
        endfor

    else
        # Standard Henon attractor; deterministic starting state and no
        # stochastic "escape reset" that would destroy the dynamical system.
        mapX = 0.1
        mapY = 0.1
        henonA = 1.4
        henonB = 0.3
        mapBurnIn = 500

        for burn to mapBurnIn
            newX = 1 - henonA * mapX * mapX + mapY
            newY = henonB * mapX
            mapX = newX
            mapY = newY
        endfor

        henonYSound = Create Sound from formula: "chaos_henon_y_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
    endif

    # Record the actual trajectory used by the sonification.
    for cp to nControlPoints
        if function_type = 12 or function_type = 13
            mapX = mapR * mapX * (1 - mapX)
            modValue = 2 * mapX - 1

        elsif function_type = 14
            if mapX < 0.5
                mapX = tentMu * mapX
            else
                mapX = tentMu * (1 - mapX)
            endif
            modValue = 2 * mapX - 1

        else
            newX = 1 - henonA * mapX * mapX + mapY
            newY = henonB * mapX
            mapX = newX
            mapY = newY

            if abs(mapX) > 5 or abs(mapY) > 5
                exitScript: "Henon trajectory escaped unexpectedly; synthesis stopped rather than injecting a random reset."
            endif

            modValue = mapX / 1.5

            selectObject: henonYSound
            Set value at sample number: 1, cp, mapY
        endif

        # Protect the sonification mapping, without altering the stored state law.
        modValue = max(-1, min(1, modValue))
        selectObject: controlSound
        Set value at sample number: 1, cp, modValue
    endfor

    selectObject: controlSound
    controlMin = Get minimum: 0, 0, "None"
    controlMax = Get maximum: 0, 0, "None"

    # Band-limit/interpolate the discrete control trajectory to audio rate.
    controlAudio = Resample: sample_rate_Hz, 50

    # Actual bounded instantaneous-frequency trajectory.
    instFreqSound = Create Sound from formula: "chaos_frequency_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "map_carrier_frequency_Hz * (1 + fmDepth * object[controlAudio,1,col])"

    selectObject: instFreqSound
    instFreqMin = Get minimum: 0, 0, "None"
    instFreqMax = Get maximum: 0, 0, "None"

    # Integrate frequency -> phase. Praat Formula runs left-to-right, so
    # self[col-1] is the already updated previous phase sample.
    phaseSound = Create Sound from formula: "chaos_phase_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    selectObject: phaseSound
    Formula: "if col = 1 then twoPi * object[instFreqSound,1,col] / sample_rate_Hz else self[col-1] + twoPi * object[instFreqSound,1,col] / sample_rate_Hz fi"

    outputSound = Create Sound from formula: "chaos_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "sin(object[phaseSound,1,col])"

    removeObject: phaseSound, controlAudio

    appendInfoLine: "Burn-in: ", mapBurnIn, " iterations"
    appendInfoLine: "Control range: ", fixed$(controlMin, 3), " to ", fixed$(controlMax, 3)
    appendInfoLine: "Realized frequency: ", fixed$(instFreqMin, 1), " to ", fixed$(instFreqMax, 1), " Hz"
    if carrierCorrected
        appendInfoLine: "Carrier reduced automatically for Nyquist safety."
    endif
endif

# Restore the global RNG after all stochastic initialization/custom rendering.
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 3. EDGE ENVELOPE
# ---------------------------------------------------------------------------
fadeDur = min(0.010, 0.20 * duration_s)
fadeOutStart = duration_s - fadeDur

selectObject: outputSound
if fadeDur > 0
    Formula: "if x < fadeDur then self * (x/fadeDur) else if x > fadeOutStart then self * ((duration_s-x)/fadeDur) else self fi fi"
endif

# ---------------------------------------------------------------------------
# 4. SPATIAL RENDER
# ---------------------------------------------------------------------------
if spatial_mode = 2
    appendInfoLine: "Spatial: Stereo Wide (short decorrelation delay)"
    sourceID = outputSound
    wideDelay = min(0.009, 0.02 * duration_s)

    selectObject: sourceID
    Copy: "chaos_left_" + uid$
    leftSound = selected("Sound")
    Formula: "self / sqrtTwo"

    selectObject: sourceID
    Copy: "chaos_right_" + uid$
    rightSound = selected("Sound")
    Formula: "object(sourceID, x-wideDelay, 1) / sqrtTwo"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    removeObject: sourceID, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Spatial: Rotating (equal power)"
    sourceID = outputSound

    selectObject: sourceID
    Copy: "chaos_left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * cos(0.25*pi*(1+sin(twoPi*0.2*x)))"

    selectObject: sourceID
    Copy: "chaos_right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sin(0.25*pi*(1+sin(twoPi*0.2*x)))"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    removeObject: sourceID, leftSound, rightSound
    outputSound = stereoSound
endif

selectObject: outputSound
Rename: "chaos_" + replace$(presetName$, " ", "_", 0)

# ---------------------------------------------------------------------------
# 5. FINAL NORMALIZATION / METRICS
# ---------------------------------------------------------------------------
selectObject: outputSound
if normalize_output
    outputPrePeak = Get absolute extremum: 0, 0, "None"
    if outputPrePeak > 0
        Scale peak: 0.90
    endif
endif

selectObject: outputSound
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
outputChannels = Get number of channels

if spatial_mode = 1
    spatialLabel$ = "Mono"
elsif spatial_mode = 2
    spatialLabel$ = "Stereo Wide"
else
    spatialLabel$ = "Rotating"
endif

# ---------------------------------------------------------------------------
# 6. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# Control/model helper objects are no longer needed after drawing.
if modelSound > 0
    removeObject: modelSound
endif
if controlSound > 0
    removeObject: controlSound
endif
if henonYSound > 0
    removeObject: henonYSound
endif
if instFreqSound > 0
    removeObject: instFreqSound
endif

# ---------------------------------------------------------------------------
# 7. INFO / PLAY / FINAL SELECTION
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)
appendInfoLine: "RMS: ", fixed$(finalRMS, 4)
appendInfoLine: "Channels: ", outputChannels
if safetyScaled
    appendInfoLine: "Direct waveform received down-only playback-range safety scaling."
endif
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.80
    .right = 7.55
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .model$ = "{0.18,0.43,0.72}"
    .measure$ = "{0.72,0.34,0.22}"

    Erase all

    # ---- Header ------------------------------------------------------------
    Select inner viewport: 0.25, 7.75, 0.06, 0.34
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "CHAOTIC FUNCTION GENERATOR | " + presetName$

    Select inner viewport: 0.35, 7.65, 0.38, 0.70
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    if isIteratedMap
        Text: 0.5, "centre", 0.67, "half",
            ... functionLabel$ + " | control " + fixed$(control_rate_Hz,0) + " Hz | carrier "
            ... + fixed$(map_carrier_frequency_Hz,1) + " Hz | depth +/-" + fixed$(100*fmDepth,0) + "%"
        Text: 0.5, "centre", 0.20, "half",
            ... "map state -> band-limited control -> bounded instantaneous frequency -> phase integral -> audio"
    else
        Text: 0.5, "centre", 0.67, "half", functionLabel$ + " | direct sampled mathematical waveform"
        Text: 0.5, "centre", 0.20, "half",
            ... "normalized time u=t/T -> f(u) -> oversampled discrete waveform -> anti-aliased resample -> audio"
    endif

    # ---- Representative output channel ------------------------------------
    if outputChannels = 1
        selectObject: outputSound
        Copy: "chaos_display_" + uid$
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0, 0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0, 0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # =======================================================================
    # PANEL A
    # =======================================================================
    Select inner viewport: 0.35, 7.65, 0.79, 1.02
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"

    if isIteratedMap
        if function_type = 15
            Text: 0.5, "centre", 0.52, "half", "A  ACTUAL MAP GEOMETRY | Henon attractor after burn-in"
        else
            Text: 0.5, "centre", 0.52, "half", "A  ACTUAL MAP GEOMETRY | return map x(n) -> x(n+1)"
        endif
    else
        Text: 0.5, "centre", 0.52, "half", "A  MATHEMATICAL MODEL | sampled function before edge/spatial rendering"
    endif

    if isIteratedMap
        Select inner viewport: .left, .right, 1.08, 2.46

        if function_type = 15
            Axes: -1.5, 1.5, -0.5, 0.5
            Paint rectangle: .bg$, -1.5, 1.5, -0.5, 0.5
            Colour: .grid$
            Dotted line
            Draw line: -1.5, 0, 1.5, 0
            Draw line: 0, -0.5, 0, 0.5
            Plain line

            .step = max(1, floor(nControlPoints / 700))
            Font size: 4
            Colour: .model$
            for .cp from 1 to nControlPoints
                if ((.cp - 1) mod .step) = 0
                    selectObject: controlSound
                    .mx = Get value at sample number: 1, .cp
                    .mx = 1.5 * .mx
                    selectObject: henonYSound
                    .my = Get value at sample number: 1, .cp
                    Text: .mx, "centre", .my, "half", "."
                endif
            endfor

            Colour: "Black"
            Draw inner box
            Marks left: 3, "yes", "yes", "no"
            Marks bottom: 5, "yes", "yes", "no"
            Font size: 6
            Text left: "yes", "y(n)"
            Text bottom: "yes", "x(n)"

        else
            Axes: 0, 1, 0, 1
            Paint rectangle: .bg$, 0, 1, 0, 1
            Colour: .grid$
            Dotted line
            Draw line: 0, 0, 1, 1
            Plain line

            .step = max(1, floor((nControlPoints - 1) / 650))
            Font size: 4
            Colour: .model$
            for .cp from 1 to nControlPoints - 1
                if ((.cp - 1) mod .step) = 0
                    selectObject: controlSound
                    .m1 = Get value at sample number: 1, .cp
                    .m2 = Get value at sample number: 1, .cp + 1
                    .x1 = 0.5 * (.m1 + 1)
                    .x2 = 0.5 * (.m2 + 1)
                    Text: .x1, "centre", .x2, "half", "."
                endif
            endfor

            Colour: "Black"
            Draw inner box
            Marks left: 5, "yes", "yes", "no"
            Marks bottom: 5, "yes", "yes", "no"
            Font size: 6
            Text left: "yes", "x(n+1)"
            Text bottom: "yes", "x(n)"
        endif

    else
        Select inner viewport: .left, .right, 1.08, 2.46
        selectObject: modelSound
        .modelPeak = Get absolute extremum: 0, 0, "None"
        if .modelPeak < 0.01
            .modelPeak = 0.01
        endif
        .modelY = 1.05 * .modelPeak
        Axes: 0, duration_s, -.modelY, .modelY
        Paint rectangle: .bg$, 0, duration_s, -.modelY, .modelY
        Colour: .model$
        Draw: 0, 0, -.modelY, .modelY, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Marks left: 3, "yes", "yes", "no"
        Marks bottom: 5, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "f(u)"
        Text bottom: "yes", "Time (s)"
    endif

    # =======================================================================
    # PANEL B
    # =======================================================================
    Select inner viewport: 0.35, 7.65, 2.59, 2.82
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"

    if isIteratedMap
        Text: 0.5, "centre", 0.52, "half", "B  SONIFICATION MODEL | actual bounded instantaneous-frequency trajectory"
    else
        Text: 0.5, "centre", 0.52, "half", "B  MEASURED OUTPUT | representative channel after edge/spatial processing"
    endif

    Select inner viewport: .left, .right, 2.88, 4.08

    if isIteratedMap
        .fPad = max(10, 0.08 * (instFreqMax - instFreqMin))
        .fLo = max(0, instFreqMin - .fPad)
        .fHi = min(safeTop, instFreqMax + .fPad)
        Axes: 0, duration_s, .fLo, .fHi
        Paint rectangle: .bg$, 0, duration_s, .fLo, .fHi
        selectObject: instFreqSound
        Colour: .model$
        Draw: 0, 0, .fLo, .fHi, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Marks left: 4, "yes", "yes", "no"
        Marks bottom: 5, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "Frequency (Hz)"
        Text bottom: "yes", "Time (s)"

    else
        selectObject: .disp
        .wavePeak = Get absolute extremum: 0, 0, "None"
        if .wavePeak < 0.01
            .wavePeak = 0.01
        endif
        .waveY = 1.05 * .wavePeak
        Axes: 0, duration_s, -.waveY, .waveY
        Paint rectangle: .bg$, 0, duration_s, -.waveY, .waveY
        Colour: .measure$
        Draw: 0, 0, -.waveY, .waveY, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Marks left: 3, "yes", "yes", "no"
        Marks bottom: 5, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "Amplitude"
        Text bottom: "yes", "Time (s)"
    endif

    # =======================================================================
    # PANEL C: MEASUREMENT
    # =======================================================================
    Select inner viewport: 0.35, 7.65, 4.21, 4.44
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    if isIteratedMap
        Text: 0.5, "centre", 0.52, "half", "C  MODEL -> MEASUREMENT | spectrogram with instantaneous-frequency guide"
    else
        Text: 0.5, "centre", 0.52, "half", "C  MEASUREMENT | output spectrogram"
    endif

    if isIteratedMap
        .specMax = min(safeTop, max(1000, 1.50 * instFreqMax))
    else
        .specMax = min(10000, safeTop)
    endif
    .specStep = max(0.002, duration_s / 1000)

    selectObject: .disp
    .spec = To Spectrogram: 0.025, .specMax, .specStep, 20, "Gaussian"

    Select inner viewport: .left, .right, 4.50, 5.72
    selectObject: .spec
    Paint: 0, 0, 0, .specMax, 100, 1, 50, 6, 0, 0
    removeObject: .spec

    Axes: 0, duration_s, 0, .specMax
    if isIteratedMap
        selectObject: instFreqSound
        Colour: .model$
        Line width: 1.3
        Draw: 0, 0, 0, .specMax, "no", "Curve"
        Line width: 1
    endif

    Colour: "Black"
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    removeObject: .disp

    # =======================================================================
    # MECHANISM STRIP
    # =======================================================================
    Select inner viewport: 0.55, 7.45, 5.87, 6.57
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.955,0.955,0.960}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    if isIteratedMap
        Text: 0.5, "centre", 0.72, "half",
            ... "MAP x(n) -> control m(t) -> f(t)=f0[1+d*m(t)] -> phase integral -> sin(phase)"
        Font size: 6
        Colour: "{0.28,0.28,0.28}"
        if function_type = 12 or function_type = 13
            Text: 0.5, "centre", 0.30, "half", "Logistic: x(n+1)=r*x(n)*[1-x(n)]"
        elsif function_type = 14
            Text: 0.5, "centre", 0.30, "half", "Tent: x(n+1)=mu*x(n) for x<0.5; mu*[1-x(n)] otherwise"
        else
            Text: 0.5, "centre", 0.30, "half", "Henon: x(n+1)=1-a*x(n)^2+y(n); y(n+1)=b*x(n)"
        endif
    else
        Text: 0.5, "centre", 0.72, "half", "u=t/T -> mathematical f(u) -> oversample -> anti-alias resample -> edge/spatial render"
        Font size: 6
        Colour: "{0.28,0.28,0.28}"
        Text: 0.5, "centre", 0.30, "half", "Singular functions are highly oscillatory sampled functions, not chaotic dynamical systems."
    endif

    Colour: "{0.55,0.55,0.58}"
    Draw rectangle: 0, 1, 0, 1

    # =======================================================================
    # QC SUMMARY
    # =======================================================================
    Select inner viewport: 0.55, 7.45, 6.72, 7.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    if isIteratedMap
        if function_type = 12 or function_type = 13
            .law$ = "r " + fixed$(mapR,4)
        elsif function_type = 14
            .law$ = "mu " + fixed$(tentMu,4)
        else
            .law$ = "a 1.4 | b 0.3"
        endif

        Text: 0.02, "left", 0.76, "half",
            ... "DYNAMICS  |  " + .law$ + "  |  burn-in " + string$(mapBurnIn)
            ... + "  |  control " + fixed$(controlMin,3) + " to " + fixed$(controlMax,3)

        Text: 0.02, "left", 0.50, "half",
            ... "SONIFICATION  |  f0 " + fixed$(map_carrier_frequency_Hz,1) + " Hz"
            ... + "  |  depth +/-" + fixed$(100*fmDepth,1) + "%"
            ... + "  |  realized " + fixed$(instFreqMin,1) + "-" + fixed$(instFreqMax,1) + " Hz"

    else
        if internalRate > sample_rate_Hz
            .aa$ = "oversample " + fixed$(internalRate/sample_rate_Hz,1) + "x + sinc resample"
        else
            .aa$ = "native sample rate"
        endif

        Text: 0.02, "left", 0.76, "half",
            ... "MODEL  |  " + functionLabel$ + "  |  " + .aa$

        if safetyScaled
            .safe$ = "down-only safety scale"
        else
            .safe$ = "no safety scale"
        endif

        Text: 0.02, "left", 0.50, "half",
            ... "SAMPLING  |  Fs " + string$(sample_rate_Hz) + " Hz"
            ... + "  |  " + .safe$
    endif

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "not normalized"
    endif

    Text: 0.02, "left", 0.24, "half",
        ... "OUTPUT  |  peak " + fixed$(finalPeak,3) + "  |  RMS " + fixed$(finalRMS,4)
        ... + "  |  " + spatialLabel$ + "  |  " + .norm$ + "  |  " + seedLabel$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
