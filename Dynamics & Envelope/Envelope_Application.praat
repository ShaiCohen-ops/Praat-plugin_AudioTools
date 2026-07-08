# ============================================================
# Praat AudioTools - Envelope_Application.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Advanced Envelope Application with multiple envelope types,
#   curve shapes, modifiers, and comprehensive visualization.
#
# Changelog v1.1:
#   - FIXED: info header was invisible -- eight consecutive
#     writeInfoLine calls each CLEAR the Info window, so only the
#     last (empty) line survived. Header now appends.
#   - FIXED: smoothing Formula read self[col +/- k] in place:
#     self[col - k] saw already-smoothed values while
#     self[col + k] saw raw ones (asymmetric recursive smear,
#     compounding per pass). Now averages a frozen copy via
#     object[]. (Recurring pattern: in-place Formula reads of
#     self[col - k] return the value just written.)
#   - CHANGED: envelope now applied by DIRECT multiplication
#     with a piecewise-linear envelope Sound. The IntensityTier
#     path had four defects: -80 dB floor (1e-4 residual on
#     every fade-out), dB-linear interpolation warping shapes
#     between points, Cubic re-reads of a staircase envelope
#     (overshoot at each step edge), and a hidden scale-to-0.9
#     inside bare Multiply -- a unity envelope on a 0.5-peak
#     signal amplified it 1.8x. AmplitudeTier hardcodes the
#     same rescale, so tiers are out entirely. Fades now reach
#     true zero; the drawn envelope IS the applied envelope.
#
# Changelog v1.0:
#   - Unified single-form interface (compact)
#   - Added presets
#   - Added envelope modifiers (invert, mirror, smooth)
#   - Added more envelope types
#   - Added normalization option
#   - Reduced code duplication with procedures
#   - Enhanced visualization with stage labels
# ============================================================

form Envelope Application v1.1
    optionmenu Preset 1
        option Custom
        option Fade In
        option Fade Out
        option Swell (triangle)
        option Percussive
        option ADSR Pad
        option Plucked
        option Tremolo
        option Gate
    optionmenu Envelope_type 1
        option Linear
        option Exponential
        option Sine (S-curve)
        option Triangle
        option Trapezoid
        option Gaussian
        option Step
        option ASR
        option Percussive
        option ADSR
        option Tremolo
    comment === Levels (0-1) ===
    real Start_level 0.0
    real End_level 1.0
    real Peak_level 1.0
    real Sustain_level 0.7
    comment === Times (seconds, 0=auto) ===
    real Attack 0.02
    real Decay 0.1
    real Sustain 0
    real Release 0.2
    comment === Shape & Modulation ===
    optionmenu Curve 1
        option Linear
        option Exponential
        option Sine
    real Curve_amount 4
    real Tremolo_rate_Hz 5
    real Tremolo_depth 0.5
    comment === Modifiers ===
    boolean Invert 0
    boolean Mirror 0
    integer Smoothing 0
    comment === Output ===
    boolean Normalize 1
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sr = Get sampling frequency

# === APPLY PRESETS ===
if preset = 2
    # Fade In
    envelope_type = 1
    start_level = 0
    end_level = 1
    presetName$ = "FadeIn"
elsif preset = 3
    # Fade Out
    envelope_type = 1
    start_level = 1
    end_level = 0
    presetName$ = "FadeOut"
elsif preset = 4
    # Swell
    envelope_type = 4
    peak_level = 1
    presetName$ = "Swell"
elsif preset = 5
    # Percussive
    envelope_type = 9
    attack = 0.005
    release = 0.3
    peak_level = 1
    curve = 2
    curve_amount = 4
    presetName$ = "Percussive"
elsif preset = 6
    # ADSR Pad
    envelope_type = 10
    attack = 0.3
    decay = 0.2
    sustain_level = 0.7
    sustain = 0
    release = 0.5
    peak_level = 1
    presetName$ = "Pad"
elsif preset = 7
    # Plucked
    envelope_type = 9
    attack = 0.001
    release = duration * 0.8
    peak_level = 1
    curve = 2
    curve_amount = 3
    presetName$ = "Plucked"
elsif preset = 8
    # Tremolo
    envelope_type = 11
    tremolo_rate_Hz = 6
    tremolo_depth = 0.4
    presetName$ = "Tremolo"
elsif preset = 9
    # Gate
    envelope_type = 5
    peak_level = 1
    attack = 0.05
    release = 0.05
    presetName$ = "Gate"
else
    presetName$ = "Custom"
endif

# === GET ENVELOPE TYPE NAME ===
if envelope_type = 1
    envName$ = "Linear"
elsif envelope_type = 2
    envName$ = "Exponential"
elsif envelope_type = 3
    envName$ = "Sine"
elsif envelope_type = 4
    envName$ = "Triangle"
elsif envelope_type = 5
    envName$ = "Trapezoid"
elsif envelope_type = 6
    envName$ = "Gaussian"
elsif envelope_type = 7
    envName$ = "Step"
elsif envelope_type = 8
    envName$ = "ASR"
elsif envelope_type = 9
    envName$ = "Percussive"
elsif envelope_type = 10
    envName$ = "ADSR"
else
    envName$ = "Tremolo"
endif

# === INFO HEADER ===
# v1.1: writeInfoLine clears the Info window on EVERY call --
# the old header (eight writeInfoLine calls) erased itself.
writeInfoLine: "=============================================="
appendInfoLine: "  ENVELOPE APPLICATION v1.1"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", sound_name$, " (", fixed$(duration, 3), "s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Envelope: ", envName$
appendInfoLine: ""

# ============================================================
# PROCEDURE: Apply curve shape to linear phase (0-1)
# ============================================================

procedure applyCurve: .phase
    if curve = 1
        # Linear
        applyCurve.result = .phase
    elsif curve = 2
        # Exponential
        if curve_amount > 0
            applyCurve.result = 1 - exp(-curve_amount * .phase)
            .maxVal = 1 - exp(-curve_amount)
            if .maxVal > 0.001
                applyCurve.result = applyCurve.result / .maxVal
            endif
        else
            applyCurve.result = .phase
        endif
    else
        # Sine
        applyCurve.result = (1 - cos(.phase * pi)) / 2
    endif
endproc

# ============================================================
# PROCEDURE: Calculate envelope amplitude at time t
# ============================================================

procedure getEnvelopeValue: .t, .dur
    .progress = .t / .dur
    
    if envelope_type = 1
        # Linear
        .amp = start_level + (end_level - start_level) * .progress
        
    elsif envelope_type = 2
        # Exponential
        if start_level > 0.001 and end_level > 0.001
            .amp = start_level * (end_level / start_level) ^ .progress
        else
            .amp = start_level + (end_level - start_level) * .progress
        endif
        
    elsif envelope_type = 3
        # Sine (S-curve)
        .amp = start_level + (end_level - start_level) * (1 - cos(.progress * pi)) / 2
        
    elsif envelope_type = 4
        # Triangle (peak in middle)
        if .progress < 0.5
            .amp = peak_level * (.progress / 0.5)
        else
            .amp = peak_level * (1 - (.progress - 0.5) / 0.5)
        endif
        
    elsif envelope_type = 5
        # Trapezoid
        .flatDur = .dur - attack - release
        if .flatDur < 0
            .flatDur = 0
        endif
        
        if .t < attack
            .phase = .t / attack
            @applyCurve: .phase
            .amp = peak_level * applyCurve.result
        elsif .t < attack + .flatDur
            .amp = peak_level
        elsif .t < attack + .flatDur + release
            .phase = (.t - attack - .flatDur) / release
            @applyCurve: .phase
            .amp = peak_level * (1 - applyCurve.result)
        else
            .amp = 0
        endif
        
    elsif envelope_type = 6
        # Gaussian
        .center = .dur / 2
        .sigma = .dur / 4
        .amp = peak_level * exp(-0.5 * ((.t - .center) / .sigma) ^ 2)
        
    elsif envelope_type = 7
        # Step
        .stepTime = .dur / 2
        if .t < .stepTime
            .amp = start_level
        else
            .amp = end_level
        endif
        
    elsif envelope_type = 8
        # ASR
        .sus = sustain
        if .sus = 0
            .sus = .dur - attack - release
            if .sus < 0
                .sus = 0
            endif
        endif
        
        if .t < attack
            .phase = .t / attack
            @applyCurve: .phase
            .amp = peak_level * applyCurve.result
        elsif .t < attack + .sus
            .amp = peak_level
        elsif .t < attack + .sus + release
            .phase = (.t - attack - .sus) / release
            @applyCurve: .phase
            .amp = peak_level * (1 - applyCurve.result)
        else
            .amp = 0
        endif
        
    elsif envelope_type = 9
        # Percussive
        .total = attack + release
        
        if .t < attack
            .phase = .t / attack
            @applyCurve: .phase
            .amp = peak_level * applyCurve.result
        elsif .t < .total
            .phase = (.t - attack) / release
            .amp = peak_level * (1 - .phase) ^ (abs(curve_amount) / 2)
        else
            .amp = 0
        endif
        
    elsif envelope_type = 10
        # ADSR
        .sus = sustain
        if .sus = 0
            .sus = .dur - attack - decay - release
            if .sus < 0
                .sus = 0
            endif
        endif
        .susAmp = sustain_level * peak_level
        
        if .t < attack
            .phase = .t / attack
            @applyCurve: .phase
            .amp = peak_level * applyCurve.result
        elsif .t < attack + decay
            .phase = (.t - attack) / decay
            @applyCurve: .phase
            .amp = peak_level - (peak_level - .susAmp) * applyCurve.result
        elsif .t < attack + decay + .sus
            .amp = .susAmp
        elsif .t < attack + decay + .sus + release
            .phase = (.t - attack - decay - .sus) / release
            @applyCurve: .phase
            .amp = .susAmp * (1 - applyCurve.result)
        else
            .amp = 0
        endif
        
    else
        # Tremolo
        .base = (start_level + end_level) / 2
        if .base < 0.1
            .base = 0.5
        endif
        .mod = tremolo_depth * .base
        .amp = .base + .mod * sin(2 * pi * tremolo_rate_Hz * .t)
        if .amp < 0
            .amp = 0
        endif
    endif
    
    # Apply modifiers
    if invert
        .amp = peak_level - .amp
        if .amp < 0
            .amp = 0
        endif
    endif
    
    getEnvelopeValue.result = .amp
endproc

# ============================================================
# CREATE ENVELOPE
# ============================================================

appendInfoLine: "Creating envelope..."

# Create envelope sound
numPoints = min(10000, max(200, round(duration * 500)))
timeStep = duration / numPoints

Create Sound from formula: "envelope_temp", 1, 0, duration, sr, "0"
envelope_sound = selected("Sound")

# Fill with envelope values
for i from 0 to numPoints
    t = i * timeStep
    if t > duration
        t = duration
    endif
    
    # Handle mirror
    if mirror
        t_lookup = duration - t
    else
        t_lookup = t
    endif
    
    @getEnvelopeValue: t_lookup, duration
    envAmp[i] = getEnvelopeValue.result
    envTime[i] = i * timeStep
endfor

# Apply to envelope sound: paint piecewise-LINEAR segments
# between grid points (v1.1; was a half-step staircase, which
# only worked because the tier re-interpolated it downstream)
selectObject: envelope_sound
for i from 0 to numPoints - 1
    t1 = envTime[i]
    t2 = envTime[i + 1]
    a1 = envAmp[i]
    a2 = envAmp[i + 1]
    Formula (part): t1, t2, 1, 1, ~ a1 + (a2 - a1) * (x - t1) / (t2 - t1)
endfor

# Apply smoothing
if smoothing > 0
    appendInfoLine: "  Smoothing (", smoothing, " passes)..."
    smoothSamples = max(2, round(sr * 0.005))
    
    # v1.1: each pass averages a FROZEN copy. The old in-place
    # version read self[col - k] AFTER it had been overwritten
    # (already-smoothed) while self[col + k] was still raw:
    # an asymmetric recursive smear, not a 3-tap average.
    for pass to smoothing
        selectObject: envelope_sound
        smoothSrc = Copy: "smooth_src"
        selectObject: envelope_sound
        Formula: ~ if col > smoothSamples and col < ncol - smoothSamples then (object[smoothSrc, col - smoothSamples] + object[smoothSrc, col] + object[smoothSrc, col + smoothSamples]) / 3 else self fi
        removeObject: smoothSrc
    endfor
endif

# ============================================================
# APPLY ENVELOPE BY DIRECT MULTIPLICATION
# ============================================================
# v1.1: the envelope Sound (piecewise-linear, optionally
# smoothed) is multiplied in directly. The old IntensityTier
# path had four problems: a -80 dB floor (1e-4 residual on
# every fade-out), dB-linear interpolation that warped every
# shape between points, Cubic re-reads of a STAIRCASE envelope
# (overshoot at each step edge), and a hidden scale-to-0.9-peak
# baked into bare Multiply -- a unity envelope on a 0.5-peak
# signal amplified it 1.8x. (AmplitudeTier: Multiply hardcodes
# the same rescale with no way to disable it, so no tier at
# all.) Direct multiplication is exact, reaches true zero, and
# the drawn envelope is now literally the applied envelope.

appendInfoLine: "Applying envelope..."

# Clamp to [0, 1], preserving the v1.0 behaviour where the
# 0 dB cap limited gain to unity
selectObject: envelope_sound
Formula: ~ min(1, max(0, self))
envId = envelope_sound
envNx = Get number of samples

selectObject: sound
result = Copy: sound_name$ + "_" + envName$
Formula: ~ self * object[envId, min(col, envNx)]

if normalize
    selectObject: result
    Scale peak: 0.95
endif

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Envelope Application## | " + envName$ + " | " + presetName$
    
    # Original
    Select outer viewport: 0, 8, 0.5, 1.8
    Select inner viewport: 0.6, 7.6, 0.6, 1.6
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.2, 8, 0.5, 1.8
    Text left: "yes", "Input"
    
    # Envelope with ADSR stage colors
    Select outer viewport: 0, 8, 1.9, 3.2
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    
    Axes: 0, duration, 0, 1.1
    
    if envelope_type = 10
        # ADSR stage markers
        .sus = sustain
        if .sus = 0
            .sus = duration - attack - decay - release
            if .sus < 0
                .sus = 0
            endif
        endif
        
        Paint rectangle: "{0.85, 0.95, 0.85}", 0, attack, 0, 1.1
        Paint rectangle: "{0.95, 0.95, 0.85}", attack, attack + decay, 0, 1.1
        Paint rectangle: "{0.85, 0.85, 0.95}", attack + decay, attack + decay + .sus, 0, 1.1
        Paint rectangle: "{0.95, 0.85, 0.85}", attack + decay + .sus, duration, 0, 1.1
        
        Font size: 6
        Colour: "{0.3, 0.6, 0.3}"
        Text: attack / 2, "centre", 1.05, "half", "A"
        Colour: "{0.6, 0.6, 0.3}"
        Text: attack + decay / 2, "centre", 1.05, "half", "D"
        Colour: "{0.3, 0.3, 0.6}"
        Text: attack + decay + .sus / 2, "centre", 1.05, "half", "S"
        Colour: "{0.6, 0.3, 0.3}"
        Text: attack + decay + .sus + release / 2, "centre", 1.05, "half", "R"
    else
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, 1.1
    endif
    
    selectObject: envelope_sound
    Colour: "{0.8, 0.3, 0.2}"
    Line width: 2
    Draw: 0, 0, 0, 1.1, "no", "Curve"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Envelope"
    
    # Result
    Select outer viewport: 0, 8, 3.3, 4.6
    Select inner viewport: 0.6, 7.6, 3.4, 4.4
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Parameters
    Select outer viewport: 0, 8, 4.7, 5.1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    if envelope_type = 10
        Text: 0.5, "centre", 0.5, "half", "A:" + fixed$(attack*1000, 0) + "ms D:" + fixed$(decay*1000, 0) + "ms S:" + fixed$(sustain_level*100, 0) + "% R:" + fixed$(release*1000, 0) + "ms"
    elsif envelope_type = 9 or envelope_type = 8
        Text: 0.5, "centre", 0.5, "half", "Attack:" + fixed$(attack*1000, 0) + "ms Release:" + fixed$(release*1000, 0) + "ms Curve:" + fixed$(curve_amount, 1)
    elsif envelope_type = 11
        Text: 0.5, "centre", 0.5, "half", "Rate:" + fixed$(tremolo_rate_Hz, 1) + "Hz Depth:" + fixed$(tremolo_depth*100, 0) + "%"
    else
        Text: 0.5, "centre", 0.5, "half", "Start:" + fixed$(start_level, 2) + " End:" + fixed$(end_level, 2) + " Peak:" + fixed$(peak_level, 2)
    endif
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

removeObject: envelope_sound
selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="

if play
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result
