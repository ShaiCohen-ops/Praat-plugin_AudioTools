# ============================================================
# Praat AudioTools - Microphone_Simulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# v0.4.1 (2026): VISUALIZATION LAYOUT FIX - output/Summary spacing and versioned title; DSP unchanged.
# v0.4 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Physically-modelled microphone simulation. Renders a mono source as
#   it would be picked up by various studio mic pairs (Mid-Side, XY,
#   Blumlein, AB, ORTF, Decca Tree) with directional polar patterns
#   (omni, fig-8, cardioid, hypercardioid).
#
# Modeled phenomena:
#   - Polar pattern attenuation (azimuth-dependent gain)
#   - Inter-mic delays for spaced configurations (yields comb filter
#     on summed playback, the "AB sound")
#   - Distance attenuation (1/r pressure law, optional)
#   - Proximity effect (low-shelf boost on directional mics at <30cm,
#     optional, NEW in v0.4)
#
# NOT modeled:
#   - Room acoustics / reflections
#   - Specific mic models / capsule color
#   - Phase response of the directional pattern (only magnitude)
#   - Self-noise / handling noise
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - NEW: optional proximity-effect simulation. When enabled and
#     pattern is directional and distance < 30cm, applies a low-shelf
#     boost via Praat's Filter (de-emphasis from) — magnitude scales
#     with proximity (max ~+6 dB at closest, tapering to 0 at 30 cm).
#     This is the single most-audible signature of close-miking and
#     was missing from v0.2.
#   - NEW: frequency-response panel in visualization. Drives an impulse
#     through the same processing chain and plots the magnitude
#     spectrum of the result. For spaced configurations (AB, ORTF,
#     Decca) this shows the comb-filter pattern that defines their
#     sonic character. For coincident configurations (XY, Blumlein,
#     M/S) it shows the flat response that explains why those don't
#     have the "spaced sound."
#   - Visualization: canvas now uses the full suite-standard 8x8
#     layout with title bar + metadata subtitle + aligned panel
#     titles + summary bar. v0.2 used only ~5.5 of the 8 vertical
#     units, leaving the bottom ~2.5 blank.
#   - NEW: ITD readout on configuration diagram for spaced mics.
#     For AB, ORTF, Decca: shows the inter-channel delay in
#     milliseconds and which channel leads. Lets the user see at
#     a glance how strong the timing cue is.
#   - Modernized formula syntax: Object_<id>[col] -> object[<id>,col]
#     throughout, matching the rest of the suite.
#   - Style: Get sample period followed by 1/x replaced with
#     direct Get sampling frequency.
# Changelog v0.2:
#   - Fixed critical delay calculation bug (was dividing by period, not rate)
#   - Modern selectObject: syntax throughout
#   - Preset comparison by index (more robust)
#   - Simplified sound selection (uses selected sound directly)
#   - Added visualization of polar patterns and mic configuration
#   - Added draw_visualization toggle
# ============================================================

clearinfo

# ============================================================
# FORM
# ============================================================

form Microphone Simulation v0.4.1
    comment ─────────────────────────────────────────
    comment Preset (overrides custom settings)
    optionmenu Preset: 1
        option Custom
        option Studio Vocal (Cardioid Mono, 30cm)
        option Blumlein Pair (Fig-8, 1m)
        option ORTF Standard (Cardioid, 1m)
        option Spaced Omnis AB (50cm spacing, 2m)
        option Mid-Side (Cardioid M + Fig-8 S, 1m)
        option Decca Tree (Omni, 3m)
        option Close XY (Cardioid, 50cm)
        option Hypercardioid Spot (Mono, 1.5m)
        option AB Wide (100cm spacing, 2m)
        option Close Vocal Bass-boost (Cardioid Mono, 10cm)
    comment ─────────────────────────────────────────
    comment Microphone Pattern
    optionmenu Pattern: 3
        option Omnidirectional
        option Figure-of-eight
        option Cardioid
        option Hypercardioid
    comment ─────────────────────────────────────────
    comment Stereo Configuration
    optionmenu Stereo_config: 1
        option Mono
        option Mid-Side
        option XY Pair
        option Blumlein Pair
        option AB Pair (omnis)
        option ORTF Pair
        option Decca Tree
    comment ─────────────────────────────────────────
    comment Source Position
    real Azimuth_degrees 0
    comment (0°=front, +90°=right, -90°=left, ±180°=back)
    real Distance_cm 100
    real Mic_spacing_cm 17
    comment ─────────────────────────────────────────
    boolean Apply_distance_attenuation 0
    boolean Apply_proximity_effect 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET SYSTEM
# ============================================================

if preset = 2
    pattern = 3
    stereo_config = 1
    azimuth_degrees = 0
    distance_cm = 30
    presetName$ = "StudioVocal"
elsif preset = 3
    pattern = 2
    stereo_config = 4
    azimuth_degrees = 0
    distance_cm = 100
    presetName$ = "Blumlein"
elsif preset = 4
    pattern = 3
    stereo_config = 6
    azimuth_degrees = 0
    distance_cm = 100
    mic_spacing_cm = 17
    presetName$ = "ORTF"
elsif preset = 5
    pattern = 1
    stereo_config = 5
    azimuth_degrees = 0
    distance_cm = 200
    mic_spacing_cm = 50
    presetName$ = "AB50"
elsif preset = 6
    pattern = 3
    stereo_config = 2
    azimuth_degrees = 0
    distance_cm = 100
    presetName$ = "MidSide"
elsif preset = 7
    pattern = 1
    stereo_config = 7
    azimuth_degrees = 0
    distance_cm = 300
    presetName$ = "DeccaTree"
elsif preset = 8
    pattern = 3
    stereo_config = 3
    azimuth_degrees = 0
    distance_cm = 50
    presetName$ = "XY"
elsif preset = 9
    pattern = 4
    stereo_config = 1
    azimuth_degrees = 0
    distance_cm = 150
    presetName$ = "HyperSpot"
elsif preset = 10
    pattern = 1
    stereo_config = 5
    azimuth_degrees = 0
    distance_cm = 200
    mic_spacing_cm = 100
    presetName$ = "ABwide"
elsif preset = 11
    pattern = 3
    stereo_config = 1
    azimuth_degrees = 0
    distance_cm = 10
    apply_proximity_effect = 1
    presetName$ = "CloseVocalBassBoost"
else
    presetName$ = "Custom"
endif

# Pattern names
if pattern = 1
    pattern$ = "Omnidirectional"
elsif pattern = 2
    pattern$ = "Figure-of-eight"
elsif pattern = 3
    pattern$ = "Cardioid"
else
    pattern$ = "Hypercardioid"
endif

# Config names
if stereo_config = 1
    config$ = "Mono"
elsif stereo_config = 2
    config$ = "Mid-Side"
elsif stereo_config = 3
    config$ = "XY"
elsif stereo_config = 4
    config$ = "Blumlein"
elsif stereo_config = 5
    config$ = "AB"
elsif stereo_config = 6
    config$ = "ORTF"
else
    config$ = "Decca"
endif

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

if stereo_config = 3 and pattern = 1
    exitScript: "XY pair requires directional microphones." + newline$
        ... + "Please select Cardioid, Figure-of-eight, or Hypercardioid." + newline$
        ... + "For omnidirectional spacing, use AB Pair instead."
endif

if stereo_config = 5 and pattern <> 1
    appendInfoLine: "Note: AB pair typically uses omnidirectional mics. Proceeding with selected pattern."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
nChannelsOrig = Get number of channels
duration = Get total duration
sr = Get sampling frequency

# Convert to mono
if nChannelsOrig > 1
    selectObject: original
    monoSound = Convert to mono
else
    selectObject: original
    monoSound = Copy: "mono_work"
endif

# ============================================================
# CONSTANTS
# ============================================================

speedOfSound = 343
azimuthRad = azimuth_degrees * pi / 180
distance_m = distance_cm / 100

# Distance attenuation (1/r, normalized to 1m)
if apply_distance_attenuation
    distanceAmp = 1.0 / max(distance_m, 0.01)
else
    distanceAmp = 1.0
endif

# Proximity-effect parameters
# Active when: distance < 30 cm AND pattern is directional (not omni)
# Boost magnitude scales linearly from +6 dB at 0 cm to 0 dB at 30 cm.
# Below ~150 Hz where the boost is concentrated.
proxActive = 0
proxBoostDb = 0
if apply_proximity_effect and distance_cm < 30 and pattern <> 1
    proxActive = 1
    proxScale = 1.0 - (distance_cm / 30.0)
    if proxScale < 0
        proxScale = 0
    endif
    proxBoostDb = 6.0 * proxScale
endif

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
appendInfoLine: "Microphone Simulation v0.4.1"
appendInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
if preset > 1
    appendInfoLine: "Preset: ", presetName$
endif
appendInfoLine: "Pattern: ", pattern$
appendInfoLine: "Configuration: ", config$
appendInfoLine: "Azimuth: ", azimuth_degrees, "°"
appendInfoLine: "Distance: ", distance_cm, " cm"
if stereo_config >= 5
    appendInfoLine: "Mic spacing: ", mic_spacing_cm, " cm"
endif
if apply_distance_attenuation
    appendInfoLine: "Distance attenuation: ON (1/r)"
else
    appendInfoLine: "Distance attenuation: OFF"
endif
if proxActive
    appendInfoLine: "Proximity effect: ON (+", fixed$(proxBoostDb, 1), " dB low-shelf)"
elsif apply_proximity_effect
    appendInfoLine: "Proximity effect: enabled but inactive (distance >= 30cm or omni)"
else
    appendInfoLine: "Proximity effect: OFF"
endif
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# PROCEDURES
# ============================================================

procedure applyPattern: .sound, .azimuth, .patternType
    selectObject: .sound
    if .patternType = 1
        # Omnidirectional: gain = 1, no formula needed
    elsif .patternType = 2
        Formula: "self * cos(" + string$(.azimuth) + ")"
    elsif .patternType = 3
        Formula: "self * (0.5 + 0.5 * cos(" + string$(.azimuth) + "))"
    elsif .patternType = 4
        Formula: "self * (0.25 + 0.75 * cos(" + string$(.azimuth) + "))"
    endif
endproc

procedure applyDelay: .sound, .delaySec
    selectObject: .sound
    .result = .sound
    if abs(.delaySec) > 0.00001
        Shift times by: .delaySec
        .dur = Get total duration
        .newSound = Extract part: 0, .dur, "rectangular", 1, "no"
        removeObject: .sound
        .result = .newSound
    endif
endproc

# Proximity-effect low-shelf approximation.
# Praat's "Filter (de-emphasis from)" applies y[n] = x[n] + alpha*y[n-1]
# which gives a low-frequency boost. We use it on a copy at the chosen
# corner frequency, mix with the unfiltered signal scaled to produce
# the desired shelf gain in dB.
#
# Recipe: shelf at corner Fc with boost B dB
#   filtered = unity-gain low-pass-ish via de-emphasis
#   output   = signal + filtered * (10^(B/20) - 1)
# This sums the original (flat) with a low-passed copy at gain
# (linear_boost - 1), giving total LF gain ~ linear_boost and HF gain
# ~ 1 (because the low-passed copy is near-zero at HF). Simple and
# stable.
procedure applyProximity: .sound, .boostDb, .cornerHz
    if .boostDb > 0.01
        selectObject: .sound
        .filtered = Filter (de-emphasis): .cornerHz
        .linBoost = 10 ^ (.boostDb / 20)
        .extra = .linBoost - 1
        # Add scaled filtered copy to the signal in place
        selectObject: .sound
        Formula: "self + " + fixed$(.extra, 8)
            ... + " * object[" + string$(.filtered) + ", col]"
        removeObject: .filtered
    endif
endproc

# ============================================================
# PROCESS: MONO
# ============================================================

if stereo_config = 1
    selectObject: monoSound
    finalSound = Copy: originalName$ + "_" + pattern$ + "_mono"
    @applyPattern: finalSound, azimuthRad, pattern
    if proxActive
        @applyProximity: finalSound, proxBoostDb, 150
    endif

# ============================================================
# PROCESS: MID-SIDE
# ============================================================

elsif stereo_config = 2
    selectObject: monoSound
    mid = Copy: "mid"
    @applyPattern: mid, azimuthRad, pattern
    if proxActive
        @applyProximity: mid, proxBoostDb, 150
    endif
    
    selectObject: monoSound
    side = Copy: "side"
    sideAngle = azimuthRad + pi/2
    selectObject: side
    Formula: "self * cos(" + string$(sideAngle) + ")"
    
    midId$ = string$(mid)
    sideId$ = string$(side)
    
    selectObject: mid
    left = Copy: "left"
    selectObject: left
    Formula: "(object[" + midId$ + ", col] + object[" + sideId$ + ", col]) / sqrt(2)"
    
    selectObject: mid
    right = Copy: "right"
    selectObject: right
    Formula: "(object[" + midId$ + ", col] - object[" + sideId$ + ", col]) / sqrt(2)"
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_MS_" + pattern$
    
    removeObject: mid, side, left, right

# ============================================================
# PROCESS: XY PAIR
# ============================================================

elsif stereo_config = 3
    selectObject: monoSound
    left = Copy: "xy_L"
    @applyPattern: left, azimuthRad + pi/4, pattern
    if proxActive
        @applyProximity: left, proxBoostDb, 150
    endif
    
    selectObject: monoSound
    right = Copy: "xy_R"
    @applyPattern: right, azimuthRad - pi/4, pattern
    if proxActive
        @applyProximity: right, proxBoostDb, 150
    endif
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_XY_" + pattern$
    
    removeObject: left, right

# ============================================================
# PROCESS: BLUMLEIN PAIR
# ============================================================

elsif stereo_config = 4
    selectObject: monoSound
    left = Copy: "blum_L"
    leftAngle = azimuthRad + pi/4
    selectObject: left
    Formula: "self * cos(" + string$(leftAngle) + ")"
    if proxActive
        @applyProximity: left, proxBoostDb, 150
    endif
    
    selectObject: monoSound
    right = Copy: "blum_R"
    rightAngle = azimuthRad - pi/4
    selectObject: right
    Formula: "self * cos(" + string$(rightAngle) + ")"
    if proxActive
        @applyProximity: right, proxBoostDb, 150
    endif
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_Blumlein"
    
    removeObject: left, right

# ============================================================
# PROCESS: AB PAIR
# ============================================================

elsif stereo_config = 5
    spacing_m = mic_spacing_cm / 100
    
    sourceX = distance_m * sin(azimuthRad)
    sourceY = distance_m * cos(azimuthRad)
    
    distL = sqrt((sourceX + spacing_m/2)^2 + sourceY^2)
    distR = sqrt((sourceX - spacing_m/2)^2 + sourceY^2)
    minDist = min(distL, distR)
    
    delayL = (distL - minDist) / speedOfSound
    delayR = (distR - minDist) / speedOfSound
    
    appendInfoLine: "AB delays: L=", fixed$(delayL * 1000, 3), "ms, R=", fixed$(delayR * 1000, 3), "ms"
    
    selectObject: monoSound
    left = Copy: "ab_L"
    @applyDelay: left, delayL
    left = applyDelay.result
    
    selectObject: monoSound
    right = Copy: "ab_R"
    @applyDelay: right, delayR
    right = applyDelay.result
    
    selectObject: left
    Formula: "self * " + string$(minDist / distL)
    
    selectObject: right
    Formula: "self * " + string$(minDist / distR)
    
    # Proximity-effect doesn't really apply to AB omnis (omnis don't have
    # proximity), but if user set a directional pattern on AB anyway,
    # apply it.
    if proxActive
        @applyProximity: left, proxBoostDb, 150
        @applyProximity: right, proxBoostDb, 150
    endif
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_AB_" + string$(mic_spacing_cm) + "cm"
    
    removeObject: left, right

# ============================================================
# PROCESS: ORTF PAIR
# ============================================================

elsif stereo_config = 6
    spacing_m = 0.17
    
    deltaT = (spacing_m / speedOfSound) * sin(azimuthRad)
    delayL = -deltaT / 2
    delayR = deltaT / 2
    
    if delayL < 0
        delayR = delayR - delayL
        delayL = 0
    endif
    if delayR < 0
        delayL = delayL - delayR
        delayR = 0
    endif
    
    appendInfoLine: "ORTF delays: L=", fixed$(delayL * 1000, 3), "ms, R=", fixed$(delayR * 1000, 3), "ms"
    
    selectObject: monoSound
    left = Copy: "ortf_L"
    @applyPattern: left, azimuthRad + 55*pi/180, 3
    @applyDelay: left, delayL
    left = applyDelay.result
    if proxActive
        @applyProximity: left, proxBoostDb, 150
    endif
    
    selectObject: monoSound
    right = Copy: "ortf_R"
    @applyPattern: right, azimuthRad - 55*pi/180, 3
    @applyDelay: right, delayR
    right = applyDelay.result
    if proxActive
        @applyProximity: right, proxBoostDb, 150
    endif
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_ORTF"
    
    removeObject: left, right

# ============================================================
# PROCESS: DECCA TREE
# ============================================================

elsif stereo_config = 7
    deccaSpacing = 2.0
    centerForward = 1.5
    
    sourceX = distance_m * sin(azimuthRad)
    sourceY = distance_m * cos(azimuthRad)
    
    distL = sqrt((sourceX + deccaSpacing/2)^2 + sourceY^2)
    distC = sqrt(sourceX^2 + (sourceY - centerForward)^2)
    distR = sqrt((sourceX - deccaSpacing/2)^2 + sourceY^2)
    
    minDist = min(distL, min(distC, distR))
    
    delayL = (distL - minDist) / speedOfSound
    delayC = (distC - minDist) / speedOfSound
    delayR = (distR - minDist) / speedOfSound
    
    appendInfoLine: "Decca delays: L=", fixed$(delayL * 1000, 2),
        ... "ms, C=", fixed$(delayC * 1000, 2),
        ... "ms, R=", fixed$(delayR * 1000, 2), "ms"
    
    selectObject: monoSound
    left = Copy: "decca_L"
    @applyDelay: left, delayL
    left = applyDelay.result
    
    selectObject: monoSound
    center = Copy: "decca_C"
    @applyDelay: center, delayC
    center = applyDelay.result
    
    selectObject: monoSound
    right = Copy: "decca_R"
    @applyDelay: right, delayR
    right = applyDelay.result
    
    selectObject: left
    Formula: "self * " + string$(minDist / distL)
    
    selectObject: center
    Formula: "self * " + string$(minDist / distC)
    
    selectObject: right
    Formula: "self * " + string$(minDist / distR)
    
    centerId$ = string$(center)
    
    selectObject: left
    leftMix = Copy: "left_mix"
    selectObject: leftMix
    Formula: "self + 0.7 * object[" + centerId$ + ", col]"
    
    selectObject: right
    rightMix = Copy: "right_mix"
    selectObject: rightMix
    Formula: "self + 0.7 * object[" + centerId$ + ", col]"
    
    selectObject: leftMix
    plusObject: rightMix
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_DeccaTree"
    
    removeObject: left, center, right, leftMix, rightMix
endif

# ============================================================
# DISTANCE ATTENUATION (post-process)
# ============================================================

if distanceAmp <> 1.0
    selectObject: finalSound
    Formula: "self * " + string$(distanceAmp)
endif

selectObject: finalSound
Scale peak: 0.99

# ============================================================
# CLEANUP
# ============================================================

removeObject: monoSound

# ============================================================
# FREQUENCY-RESPONSE PROBE
# Drive an impulse through the same processing chain to capture
# the system's actual transfer function. Used by the visualization
# panel to show the comb-filter pattern for spaced configurations.
# ============================================================

procRunFreqResponse = 0
if draw_visualization
    procRunFreqResponse = 1
endif

if procRunFreqResponse
    # Generate a 0.05s impulse at the same SR
    impDur = 0.05
    impulseSrc = Create Sound from formula: "imp_src", 1, 0, impDur, sr,
        ... "if col = 1 then 1 else 0 fi"
    
    # Run the full pipeline on the impulse, mirroring the processing above
    # (slight code duplication, but cleaner than refactoring the pipeline
    # into a single procedure that handles both real and impulse inputs)
    
    if stereo_config = 1
        selectObject: impulseSrc
        impOut = Copy: "imp_mono"
        @applyPattern: impOut, azimuthRad, pattern
        if proxActive
            @applyProximity: impOut, proxBoostDb, 150
        endif
    elsif stereo_config = 2
        selectObject: impulseSrc
        iMid = Copy: "imp_mid"
        @applyPattern: iMid, azimuthRad, pattern
        if proxActive
            @applyProximity: iMid, proxBoostDb, 150
        endif
        selectObject: impulseSrc
        iSide = Copy: "imp_side"
        selectObject: iSide
        Formula: "self * cos(" + string$(azimuthRad + pi/2) + ")"
        iMidStr$ = string$(iMid)
        iSideStr$ = string$(iSide)
        selectObject: iMid
        iL = Copy: "imp_L"
        Formula: "(object[" + iMidStr$ + ", col] + object[" + iSideStr$ + ", col]) / sqrt(2)"
        selectObject: iMid
        iR = Copy: "imp_R"
        Formula: "(object[" + iMidStr$ + ", col] - object[" + iSideStr$ + ", col]) / sqrt(2)"
        selectObject: iL
        plusObject: iR
        impOut = Combine to stereo
        removeObject: iMid, iSide, iL, iR
    elsif stereo_config = 3
        selectObject: impulseSrc
        iL = Copy: "imp_L"
        @applyPattern: iL, azimuthRad + pi/4, pattern
        if proxActive
            @applyProximity: iL, proxBoostDb, 150
        endif
        selectObject: impulseSrc
        iR = Copy: "imp_R"
        @applyPattern: iR, azimuthRad - pi/4, pattern
        if proxActive
            @applyProximity: iR, proxBoostDb, 150
        endif
        selectObject: iL
        plusObject: iR
        impOut = Combine to stereo
        removeObject: iL, iR
    elsif stereo_config = 4
        selectObject: impulseSrc
        iL = Copy: "imp_L"
        Formula: "self * cos(" + string$(azimuthRad + pi/4) + ")"
        if proxActive
            @applyProximity: iL, proxBoostDb, 150
        endif
        selectObject: impulseSrc
        iR = Copy: "imp_R"
        Formula: "self * cos(" + string$(azimuthRad - pi/4) + ")"
        if proxActive
            @applyProximity: iR, proxBoostDb, 150
        endif
        selectObject: iL
        plusObject: iR
        impOut = Combine to stereo
        removeObject: iL, iR
    elsif stereo_config = 5
        # AB
        spacing_m = mic_spacing_cm / 100
        sourceX = distance_m * sin(azimuthRad)
        sourceY = distance_m * cos(azimuthRad)
        distL = sqrt((sourceX + spacing_m/2)^2 + sourceY^2)
        distR = sqrt((sourceX - spacing_m/2)^2 + sourceY^2)
        minDist = min(distL, distR)
        delayL = (distL - minDist) / speedOfSound
        delayR = (distR - minDist) / speedOfSound
        selectObject: impulseSrc
        iL = Copy: "imp_L"
        @applyDelay: iL, delayL
        iL = applyDelay.result
        selectObject: impulseSrc
        iR = Copy: "imp_R"
        @applyDelay: iR, delayR
        iR = applyDelay.result
        selectObject: iL
        Formula: "self * " + string$(minDist / distL)
        selectObject: iR
        Formula: "self * " + string$(minDist / distR)
        selectObject: iL
        plusObject: iR
        impOut = Combine to stereo
        removeObject: iL, iR
    elsif stereo_config = 6
        # ORTF
        spacing_m = 0.17
        deltaT = (spacing_m / speedOfSound) * sin(azimuthRad)
        delayL = -deltaT / 2
        delayR = deltaT / 2
        if delayL < 0
            delayR = delayR - delayL
            delayL = 0
        endif
        if delayR < 0
            delayL = delayL - delayR
            delayR = 0
        endif
        selectObject: impulseSrc
        iL = Copy: "imp_L"
        @applyPattern: iL, azimuthRad + 55*pi/180, 3
        @applyDelay: iL, delayL
        iL = applyDelay.result
        selectObject: impulseSrc
        iR = Copy: "imp_R"
        @applyPattern: iR, azimuthRad - 55*pi/180, 3
        @applyDelay: iR, delayR
        iR = applyDelay.result
        selectObject: iL
        plusObject: iR
        impOut = Combine to stereo
        removeObject: iL, iR
    else
        # Decca
        deccaSpacing = 2.0
        centerForward = 1.5
        sourceX = distance_m * sin(azimuthRad)
        sourceY = distance_m * cos(azimuthRad)
        distL = sqrt((sourceX + deccaSpacing/2)^2 + sourceY^2)
        distC = sqrt(sourceX^2 + (sourceY - centerForward)^2)
        distR = sqrt((sourceX - deccaSpacing/2)^2 + sourceY^2)
        minDist = min(distL, min(distC, distR))
        delayL = (distL - minDist) / speedOfSound
        delayC = (distC - minDist) / speedOfSound
        delayR = (distR - minDist) / speedOfSound
        selectObject: impulseSrc
        iL = Copy: "imp_L"
        @applyDelay: iL, delayL
        iL = applyDelay.result
        selectObject: impulseSrc
        iC = Copy: "imp_C"
        @applyDelay: iC, delayC
        iC = applyDelay.result
        selectObject: impulseSrc
        iR = Copy: "imp_R"
        @applyDelay: iR, delayR
        iR = applyDelay.result
        selectObject: iL
        Formula: "self * " + string$(minDist / distL)
        selectObject: iC
        Formula: "self * " + string$(minDist / distC)
        selectObject: iR
        Formula: "self * " + string$(minDist / distR)
        iCStr$ = string$(iC)
        selectObject: iL
        iLM = Copy: "imp_LM"
        Formula: "self + 0.7 * object[" + iCStr$ + ", col]"
        selectObject: iR
        iRM = Copy: "imp_RM"
        Formula: "self + 0.7 * object[" + iCStr$ + ", col]"
        selectObject: iLM
        plusObject: iRM
        impOut = Combine to stereo
        removeObject: iL, iC, iR, iLM, iRM
    endif
    
    removeObject: impulseSrc
    
    # Compute spectrum of the impulse response
    selectObject: impOut
    impCh = Get number of channels
    if impCh > 1
        # Use channel 1 as representative for the FR plot;
        # AB / ORTF / Decca produce nearly identical L and R magnitude
        # for a centered source.
        irMono = Convert to mono
        removeObject: impOut
        impOut = irMono
    endif
    
    selectObject: impOut
    irSpectrum = To Spectrum: "yes"
    irLtas = To Ltas (1-to-1)
    Rename: "fr_ltas"
    irLtasID = selected("Ltas")
    
    removeObject: impOut, irSpectrum
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    
    # Pre-build summary strings
    attenStr$ = "OFF"
    if apply_distance_attenuation
        attenStr$ = "1/r"
    endif
    
    proxStr$ = "OFF"
    if proxActive
        proxStr$ = "+" + fixed$(proxBoostDb, 1) + " dB"
    elsif apply_proximity_effect
        proxStr$ = "ENABLED (inactive)"
    endif
    
    # Compute ITD readout (for spaced configurations only)
    itdMs = 0
    itdSide$ = ""
    if stereo_config = 5
        # AB
        spacing_m = mic_spacing_cm / 100
        sourceX = distance_m * sin(azimuthRad)
        sourceY = distance_m * cos(azimuthRad)
        dL = sqrt((sourceX + spacing_m/2)^2 + sourceY^2)
        dR = sqrt((sourceX - spacing_m/2)^2 + sourceY^2)
        itdMs = (dL - dR) * 1000 / speedOfSound
    elsif stereo_config = 6
        # ORTF
        spacing_m = 0.17
        itdMs = (spacing_m / speedOfSound) * sin(azimuthRad) * 1000
    elsif stereo_config = 7
        # Decca: report L–R only
        deccaSpacing = 2.0
        sourceX = distance_m * sin(azimuthRad)
        sourceY = distance_m * cos(azimuthRad)
        dL = sqrt((sourceX + deccaSpacing/2)^2 + sourceY^2)
        dR = sqrt((sourceX - deccaSpacing/2)^2 + sourceY^2)
        itdMs = (dL - dR) * 1000 / speedOfSound
    endif
    
    if itdMs > 0.001
        itdSide$ = "right leads"
    elsif itdMs < -0.001
        itdSide$ = "left leads"
    else
        itdSide$ = "centered"
    endif
    
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##MICROPHONE SIMULATION v0.4.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  " + config$ + "  " + pattern$
        ... + "  |  Az: " + string$(azimuth_degrees) + "°"
        ... + "  |  Dist: " + string$(distance_cm) + " cm"
        ... + "  |  Prox: " + proxStr$
    
    # ----------------------------------------------------------
    # PANEL A: POLAR PATTERN  (left, headline)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.40
    Select inner viewport: 0.45, 3.95, 0.95, 4.20
    
    Axes: -1.4, 1.4, -1.4, 1.4
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.4, 1.4, -1.4, 1.4
    
    # Concentric guides at 0.25, 0.5, 0.75, 1.0
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    rGuide# = { 0.25, 0.50, 0.75, 1.00 }
    for k from 1 to 4
        rg = rGuide#[k]
        prevX = rg
        prevY = 0
        for h from 1 to 64
            a = 2 * pi * h / 64
            cx = rg * cos(a)
            cy = rg * sin(a)
            Draw line: prevX, prevY, cx, cy
            prevX = cx
            prevY = cy
        endfor
    endfor
    
    # Crosshair
    Colour: "{0.78, 0.78, 0.82}"
    Dotted line
    Draw line: -1.3, 0, 1.3, 0
    Draw line: 0, -1.3, 0, 1.3
    Solid line
    
    # Polar pattern lobe (mic forward = +y)
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 2
    prevX = 0
    prevY = 0
    for i from 0 to 360
        angle = i * pi / 180
        if pattern = 1
            pGain = 1
        elsif pattern = 2
            pGain = abs(cos(angle))
        elsif pattern = 3
            pGain = 0.5 + 0.5 * cos(angle)
        else
            pGain = 0.25 + 0.75 * cos(angle)
        endif
        if pGain < 0
            pGain = 0
        endif
        # Polar to Cartesian: +y is the mic axis (forward)
        px = pGain * sin(angle)
        py = pGain * cos(angle)
        if i > 0
            Draw line: prevX, prevY, px, py
        endif
        prevX = px
        prevY = py
    endfor
    Line width: 1
    
    # Source position
    srcDist = min(distance_m / 3, 1.20)
    srcPx = srcDist * sin(azimuthRad)
    srcPy = srcDist * cos(azimuthRad)
    
    Colour: "{0.82, 0.28, 0.28}"
    Line width: 2
    Draw arrow: 0, 0, srcPx, srcPy
    Paint circle (mm): "{0.90, 0.30, 0.30}", srcPx, srcPy, 2.5
    Line width: 1
    
    Font size: 6
    Colour: "{0.60, 0.25, 0.25}"
    if srcPy > 0
        Text: srcPx, "centre", srcPy + 0.13, "half", "Src " + string$(azimuth_degrees) + "°"
    else
        Text: srcPx, "centre", srcPy - 0.13, "half", "Src " + string$(azimuth_degrees) + "°"
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    
    # ----------------------------------------------------------
    # PANEL B: CONFIGURATION DIAGRAM  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.55
    Select inner viewport: 4.50, 7.75, 0.95, 2.42
    
    Axes: -1.6, 1.6, -0.4, 2.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -0.4, 2.2
    
    Colour: "{0.25, 0.50, 0.72}"
    Line width: 2
    
    if stereo_config = 1
        Paint circle (mm): "{0.25, 0.50, 0.72}", 0, 0.6, 3.5
        Font size: 7
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0, "centre", 0.30, "half", "Mono"
    elsif stereo_config = 2
        Paint circle (mm): "{0.25, 0.50, 0.72}", 0, 0.6, 3.5
        Paint circle (mm): "{0.82, 0.35, 0.35}", 0.22, 0.6, 2.8
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0, "centre", 0.30, "half", "M"
        Text: 0.22, "centre", 0.30, "half", "S"
        Draw line: 0, 0.6, 0, 1.0
        Colour: "{0.82, 0.35, 0.35}"
        Draw line: 0.22, 0.6, 0.55, 0.6
    elsif stereo_config = 3 or stereo_config = 4
        Paint circle (mm): "{0.25, 0.50, 0.72}", -0.12, 0.6, 2.8
        Paint circle (mm): "{0.82, 0.35, 0.35}", 0.12, 0.6, 2.8
        Colour: "{0.25, 0.50, 0.72}"
        Draw line: -0.12, 0.6, -0.12 + 0.35 * sin(-pi/4), 0.6 + 0.35 * cos(-pi/4)
        Colour: "{0.82, 0.35, 0.35}"
        Draw line: 0.12, 0.6, 0.12 + 0.35 * sin(pi/4), 0.6 + 0.35 * cos(pi/4)
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        if stereo_config = 3
            Text: 0, "centre", 0.28, "half", "XY ±45°"
        else
            Text: 0, "centre", 0.28, "half", "Blumlein ±45°"
        endif
    elsif stereo_config = 5
        spacing_vis = min(mic_spacing_cm / 100, 1.2)
        Paint circle (mm): "{0.25, 0.50, 0.72}", -spacing_vis/2, 0.6, 2.8
        Paint circle (mm): "{0.82, 0.35, 0.35}", spacing_vis/2, 0.6, 2.8
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw line: -spacing_vis/2, 0.42, spacing_vis/2, 0.42
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0, "centre", 0.26, "half", "AB " + string$(mic_spacing_cm) + " cm"
    elsif stereo_config = 6
        Paint circle (mm): "{0.25, 0.50, 0.72}", -0.12, 0.6, 2.8
        Paint circle (mm): "{0.82, 0.35, 0.35}", 0.12, 0.6, 2.8
        Colour: "{0.25, 0.50, 0.72}"
        Draw line: -0.12, 0.6, -0.12 + 0.30 * sin(-55*pi/180), 0.6 + 0.30 * cos(-55*pi/180)
        Colour: "{0.82, 0.35, 0.35}"
        Draw line: 0.12, 0.6, 0.12 + 0.30 * sin(55*pi/180), 0.6 + 0.30 * cos(55*pi/180)
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0, "centre", 0.26, "half", "ORTF 17 cm 110°"
    elsif stereo_config = 7
        Paint circle (mm): "{0.25, 0.50, 0.72}", -0.55, 0.4, 2.8
        Paint circle (mm): "{0.55, 0.55, 0.55}", 0, 0.95, 2.8
        Paint circle (mm): "{0.82, 0.35, 0.35}", 0.55, 0.4, 2.8
        Colour: "{0.78, 0.78, 0.78}"
        Line width: 1
        Dotted line
        Draw line: -0.55, 0.4, 0, 0.95
        Draw line: 0, 0.95, 0.55, 0.4
        Draw line: -0.55, 0.4, 0.55, 0.4
        Solid line
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        Text: -0.55, "centre", 0.18, "half", "L"
        Text: 0, "centre", 1.12, "half", "C"
        Text: 0.55, "centre", 0.18, "half", "R"
    endif
    
    # Source indicator
    cfgSrcY = 1.85
    cfgSrcX = cfgSrcY * sin(azimuthRad)
    if abs(cfgSrcX) > 1.40
        cfgSrcX = 1.40 * (cfgSrcX / abs(cfgSrcX))
    endif
    Colour: "{0.82, 0.28, 0.28}"
    Paint circle (mm): "{0.90, 0.30, 0.30}", cfgSrcX, cfgSrcY, 2
    Colour: "{0.82, 0.65, 0.65}"
    Dotted line
    Draw line: 0, 0.6, cfgSrcX, cfgSrcY
    Solid line
    Font size: 6
    Colour: "{0.60, 0.25, 0.25}"
    Text: cfgSrcX, "centre", cfgSrcY - 0.14, "half",
        ... string$(azimuth_degrees) + "°  " + string$(distance_cm) + "cm"
    
    # ITD readout for spaced configs
    if stereo_config >= 5
        Font size: 6
        Colour: "{0.30, 0.30, 0.40}"
        Text: -1.55, "left", -0.30, "half",
            ... "ITD: " + fixed$(abs(itdMs), 3) + " ms (" + itdSide$ + ")"
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    
    # ----------------------------------------------------------
    # PANEL C: FREQUENCY RESPONSE  (right column, lower)
    # The whole point of this script — shows what the chosen mic
    # configuration actually does to the frequency content.
    # Comb filter on AB / ORTF / Decca, flat on coincident pairs.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.65, 4.40
    Select inner viewport: 4.50, 7.75, 2.85, 4.25
    
    selectObject: irLtasID
    ltasMin = Get minimum: 0, 0, "None"
    ltasMax = Get maximum: 0, 0, "None"
    ltasN = Get number of bins
    binSize = Get bin width
    nyq = ltasN * binSize
    
    # Use log-frequency from 100 Hz to Nyquist
    freqLo = 100
    freqHi = nyq
    if freqHi < freqLo * 2
        freqHi = freqLo * 2
    endif
    logLo = log10(freqLo)
    logHi = log10(freqHi)
    
    # Y range: relative to peak, floor at -24 dB
    yLo = ltasMax - 24
    yHi = ltasMax + 3
    
    Axes: logLo, logHi, yLo, yHi
    Paint rectangle: "{0.96, 0.96, 0.96}", logLo, logHi, yLo, yHi
    
    # Decade gridlines + labels
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    decadeLabels$# = { "100", "1k", "10k" }
    decadeFreqs# = { 100, 1000, 10000 }
    for k from 1 to 3
        if decadeFreqs#[k] >= freqLo and decadeFreqs#[k] <= freqHi
            lf = log10(decadeFreqs#[k])
            Draw line: lf, yLo, lf, yHi
            Font size: 6
            Colour: "{0.45, 0.45, 0.50}"
            Text: lf, "centre", yLo + (yHi - yLo) * 0.04, "half", decadeLabels$#[k]
            Colour: "{0.88, 0.88, 0.92}"
        endif
    endfor
    
    # 0 dB reference line
    Colour: "{0.65, 0.65, 0.65}"
    Dotted line
    Draw line: logLo, ltasMax, logHi, ltasMax
    Solid line
    
    # FR curve
    Colour: "{0.25, 0.50, 0.78}"
    Line width: 1.5
    prevLogF = logLo
    prevDb = yLo
    bin = 1
    while bin <= ltasN
        f = bin * binSize
        if f >= freqLo
            db = Get value in bin: bin
            if db = undefined
                db = yLo
            endif
            if db < yLo
                db = yLo
            endif
            lf = log10(f)
            if lf > logHi
                lf = logHi
            endif
            if prevLogF >= logLo
                Draw line: prevLogF, prevDb, lf, db
            endif
            prevLogF = lf
            prevDb = db
        endif
        bin = bin + 1
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 2.65, 4.4
    Select inner viewport: 4.02, 4.4, 2.67, 4.38
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Mag (dB rel)"
    Select outer viewport: 4.2, 8, 2.65, 4.4
    Select inner viewport: 4.5, 7.75, 2.85, 4.25
    Axes: logLo, logHi, yLo, yHi
    Text bottom: "yes", "Freq (Hz, log)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.20, "centre", 7.30, "half", "Polar pattern: " + pattern$
    Text: 6.10, "centre", 7.30, "half", "Configuration (upper) & frequency response (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.60, 5.75
    Select inner viewport: 0.55, 7.72, 4.70, 5.65
    
    selectObject: finalSound
    nChOut = Get number of channels
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampMax = outPeak * 1.15
    
    Axes: 0, duration, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, duration, 0
    
    if nChOut > 1
        selectObject: finalSound
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
        removeObject: vizL
        
        selectObject: finalSound
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
        removeObject: vizR
    else
        selectObject: finalSound
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nChOut > 1
        Text top: "no", "Output  (blue=L  orange=R)"
    else
        Text top: "no", "Mono output"
    endif
    Select outer viewport: 0.08, 0.52, 4.60, 5.75
    Select inner viewport: 0.08, 0.52, 4.62, 5.73
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 4.60, 5.75
    Select inner viewport: 0.55, 7.72, 4.70, 5.65
    Axes: 0, duration, -ampMax, ampMax
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.95, 6.75
    Select inner viewport: 0.55, 7.72, 6.02, 6.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.64, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Config: " + config$ + "  Pattern: " + pattern$
        ... + "  |  Az: " + string$(azimuth_degrees) + "°"
        ... + "  |  Dist: " + string$(distance_cm) + " cm"
        ... + "  |  Spacing: " + string$(mic_spacing_cm) + " cm"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Dist atten: " + attenStr$
        ... + "  |  Proximity: " + proxStr$
        ... + "  |  Out channels: " + string$(nChOut)
        ... + "  |  Out duration: " + fixed$(duration, 2) + " s"
        ... + "  |  Peak: " + fixed$(outPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Select outer viewport: 0, 8, 0, 6.85
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz-only objects
    removeObject: irLtasID
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: finalSound

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "PROCESSING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: ""
appendInfoLine: "Configuration: ", config$
appendInfoLine: "Pattern: ", pattern$
appendInfoLine: "Source: ", azimuth_degrees, "° at ", distance_cm, " cm"

if play_result
    selectObject: finalSound
    Play
endif

selectObject: finalSound
