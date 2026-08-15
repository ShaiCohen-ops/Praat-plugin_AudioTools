# ============================================================
# Praat AudioTools - Logistic_Map_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 conceptual + DSP review (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# LOGISTIC MAP SYNTHESIS
#
# MATHEMATICAL MODEL
# ------------------
# Autonomous fixed-r mode:
#
#       x[n+1] = r*x[n]*(1-x[n]),      0 < x[n] < 1
#
# For the standard logistic family:
#   - r < 3:             stable fixed point after transients
#   - r = 3:             first period-doubling bifurcation
#   - r ~= 3.449489743:  second bifurcation (period 2 -> period 4)
#   - r ~= 3.544090359:  next bifurcation (period 4 -> period 8)
#   - r_infinity ~= 3.569945672:
#                        accumulation point of the period-doubling cascade
#
# Above r_infinity, chaotic parameter regions coexist with periodic windows;
# therefore "r > 3.57 = chaos" is NOT a complete classification.
#
# IMPORTANT AUDIO MODEL
# ---------------------
# v0.3 resampled x[n] with sinc interpolation and then used:
#
#       sin(2*pi*f(t)*t)
#
# with f(t) derived from x. That is not true instantaneous-frequency FM:
# the phase derivative contains an additional t*f'(t) term.
#
# v0.4 keeps the logistic sequence DISCRETE as zero-order hold at the map
# iteration rate, maps state to bounded instantaneous frequency,
#
#       f[n] = f_base * 2^(span_octaves*(x[n]-0.5))
#
# and integrates phase at the AUDIO sample rate:
#
#       phi[k] = phi[k-1] + 2*pi*f_inst[k]/Fs
#
# The oscillator is therefore phase-continuous even when the discrete map
# changes the instantaneous frequency abruptly.
#
# TRANSIENTS / DIAGNOSTICS
# ------------------------
# Burn_in_iterations are calculated before audio begins. For fixed-r mode,
# the script estimates:
#
#   lambda ~= mean( ln | r*(1-2*x[n]) | )
#
# after burn-in, and searches for an orbit period up to 64. lambda > 0 is a
# useful numerical signature of sensitive chaotic dynamics; lambda ~= 0 at a
# bifurcation/critical threshold requires careful interpretation.
#
# PARAMETER SWEEP MODE
# --------------------
# The "period-doubling parameter sweep" varies r linearly during the piece.
# This is a NON-AUTONOMOUS driven map, not one fixed logistic map and not a
# literal bifurcation diagram. It is labelled accordingly and no autonomous
# Lyapunov exponent / orbit period is claimed for it.
#
# PRESET CORRECTIONS
# ------------------
# v0.3 "Gentle Chaos r=3.5" was actually period 4.
# v0.3 "Bifurcation Cascade r=3.55" was a fixed-r period-8 orbit, not a cascade.
# v0.3 "Strange Attractor r=3.8" is renamed simply as a chaotic orbit; the
# present engine does not need the stronger and potentially misleading term.
#
# v0.4 changes
# ------------
#   - mathematically corrected regime/preset names
#   - added fixed point, period-2, period-4, period-8, Feigenbaum threshold,
#     chaotic, r=4 endpoint, period-3 window and parameter-sweep presets
#   - explicit burn-in before synthesis
#   - zero-order-held map state rather than sinc-interpolating x[n]
#   - true audio-rate phase integration of instantaneous frequency
#   - deterministic synthesis: no random process affects the sound
#   - Lyapunov and period diagnostics for fixed-r mode
#   - actual/log-symmetric frequency mapping around Base_frequency_Hz
#   - common Nyquist-headroom scaling
#   - equal-power Logistic State Pan / Slow Rotation stereo
#   - removed complementary left/right spectral filtering
#   - removed unconditional peak normalization; final protection is down-only
#   - mechanism-faithful visualization:
#       A map/cobweb + post-burn return points, or r-x trace in sweep mode
#       B actual post-burn x[n] sequence
#       C actual mapped instantaneous-frequency sequence
#       D measured spectrogram + actual frequency-range guides
#       mathematical / mapping / sampling / output QC
#
# Classical references:
#   Robert M. May, "Simple mathematical models with very complicated
#   dynamics", Nature 261 (1976), 459-467.
#   Mitchell J. Feigenbaum, "Quantitative universality for a class of
#   nonlinear transformations", Journal of Statistical Physics 19 (1978),
#   25-52.
# ============================================================

form Logistic Map Synthesis v0.4
    optionmenu Preset 1
        option Custom
        option Stable Fixed Point (r=2.8)
        option Period-2 Orbit (r=3.2)
        option Period-4 Orbit (r=3.5)
        option Period-8 Orbit (r=3.55)
        option Feigenbaum Accumulation Threshold
        option Chaotic Orbit (r=3.9)
        option r=4 Chaotic Endpoint
        option Period-3 Window (r=3.83)
        option Period-Doubling Parameter Sweep

    positive Duration_s 10
    integer Audio_sample_rate_Hz 44100
    positive Base_frequency_Hz 180
    positive Map_iteration_rate_Hz 200

    optionmenu Parameter_mode 1
        option Fixed r
        option Linear r sweep

    real R_start 3.7
    real R_end 3.7
    real Initial_x 0.23

    boolean Edit_mapping_details 0

    optionmenu Spatial_mode 1
        option Mono
        option Logistic State Pan
        option Slow Rotation

    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
burn_in_iterations = 200
frequency_span_octaves = 1.5
second_harmonic_level = 0.16
master_amplitude = 0.52
rotation_rate_Hz = 0.10
edge_fade_s = 0.025
cobweb_iterations = 40

preset_name$ = "Custom"

# ---------------------------------------------------------------------------
# PRESETS
# ---------------------------------------------------------------------------
if preset = 2
    parameter_mode = 1
    r_start = 2.8
    r_end = 2.8
    initial_x = 0.23
    base_frequency_Hz = 170
    preset_name$ = "Stable Fixed Point"

elsif preset = 3
    parameter_mode = 1
    r_start = 3.2
    r_end = 3.2
    initial_x = 0.23
    base_frequency_Hz = 165
    preset_name$ = "Period-2 Orbit"

elsif preset = 4
    parameter_mode = 1
    r_start = 3.5
    r_end = 3.5
    initial_x = 0.23
    base_frequency_Hz = 170
    preset_name$ = "Period-4 Orbit"

elsif preset = 5
    parameter_mode = 1
    r_start = 3.55
    r_end = 3.55
    initial_x = 0.23
    base_frequency_Hz = 175
    preset_name$ = "Period-8 Orbit"

elsif preset = 6
    parameter_mode = 1
    r_start = 3.569945672
    r_end = r_start
    initial_x = 0.23
    base_frequency_Hz = 180
    burn_in_iterations = 800
    preset_name$ = "Feigenbaum Accumulation Threshold"

elsif preset = 7
    parameter_mode = 1
    r_start = 3.9
    r_end = 3.9
    initial_x = 0.23
    base_frequency_Hz = 190
    preset_name$ = "Chaotic Orbit"

elsif preset = 8
    parameter_mode = 1
    r_start = 4.0
    r_end = 4.0
    initial_x = 0.123456789
    base_frequency_Hz = 185
    preset_name$ = "r=4 Chaotic Endpoint"

elsif preset = 9
    parameter_mode = 1
    r_start = 3.83
    r_end = 3.83
    initial_x = 0.23
    base_frequency_Hz = 175
    burn_in_iterations = 500
    preset_name$ = "Period-3 Window"

elsif preset = 10
    parameter_mode = 2
    r_start = 3.0
    r_end = 3.57
    initial_x = 0.23
    base_frequency_Hz = 175
    burn_in_iterations = 200
    preset_name$ = "Period-Doubling Parameter Sweep"
endif

# ---------------------------------------------------------------------------
# ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_mapping_details
    beginPause: "Logistic Map Synthesis - Mapping Details"
        integer: "Burn-in iterations", burn_in_iterations
        real: "Frequency span (octaves)", frequency_span_octaves
        real: "Second harmonic level (0..1)", second_harmonic_level
        real: "Master amplitude", master_amplitude
        positive: "Rotation rate (Hz)", rotation_rate_Hz
        real: "Edge fade (s)", edge_fade_s
        integer: "Cobweb iterations", cobweb_iterations
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 180
    exitScript: "Duration must be > 0 and <= 180 seconds."
endif
if audio_sample_rate_Hz < 8000 or audio_sample_rate_Hz > 192000
    exitScript: "Audio sample rate must be between 8000 and 192000 Hz."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if map_iteration_rate_Hz < 5 or map_iteration_rate_Hz > 4000
    exitScript: "Map iteration rate must be between 5 and 4000 Hz."
endif
if r_start < 2.5 or r_start > 4
    exitScript: "R start must be between 2.5 and 4.0."
endif
if r_end < 2.5 or r_end > 4
    exitScript: "R end must be between 2.5 and 4.0."
endif
if initial_x <= 0 or initial_x >= 1
    exitScript: "Initial x must satisfy 0 < x < 1."
endif
if burn_in_iterations < 0 or burn_in_iterations > 100000
    exitScript: "Burn-in iterations must be between 0 and 100000."
endif
if frequency_span_octaves < 0 or frequency_span_octaves > 6
    exitScript: "Frequency span must be between 0 and 6 octaves."
endif
if second_harmonic_level < 0 or second_harmonic_level > 1
    exitScript: "Second harmonic level must be between 0 and 1."
endif
if master_amplitude <= 0 or master_amplitude > 2
    exitScript: "Master amplitude must be > 0 and <= 2."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif
if cobweb_iterations < 1 or cobweb_iterations > 500
    exitScript: "Cobweb iterations must be between 1 and 500."
endif

if parameter_mode = 1
    r_end = r_start
    parameter_name$ = "fixed r"
else
    parameter_name$ = "linear r sweep"
endif

if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "Logistic State Pan"
else
    spatial_name$ = "Slow Rotation"
endif

sr = audio_sample_rate_Hz
mapRate = map_iteration_rate_Hz
safeTop = 0.45*sr
twoPi = 2*pi

# ---------------------------------------------------------------------------
# SPECIAL DEGENERACY NOTE
# ---------------------------------------------------------------------------
degeneracyNote$ = "none"

if r_start = 4 and abs(initial_x-0.5) < 1e-15
    degeneracyNote$ = "r=4 with x0=0.5 maps exactly 0.5 -> 1 -> 0 -> 0"
endif

# ---------------------------------------------------------------------------
# BURN-IN
# ---------------------------------------------------------------------------
xBurn = initial_x

if burn_in_iterations > 0
    for b from 1 to burn_in_iterations
        xBurn = r_start*xBurn*(1-xBurn)
    endfor
endif

# The first stored control sample is the first iterate AFTER burn-in.
xFirst = r_start*xBurn*(1-xBurn)

# ---------------------------------------------------------------------------
# DISCRETE LOGISTIC CONTROL SOUND
# ---------------------------------------------------------------------------
ctrlSound = Create Sound from formula:
    ... "logistic_control_" + string$(randomInteger(10000,99999)),
    ... 1,0,duration_s,mapRate,"0"

totalCtrlSamples = Get number of samples

if parameter_mode = 1
    selectObject: ctrlSound
    Formula: "if col=1 then xFirst else r_start*self[col-1]*(1-self[col-1]) fi"

else
    # r is sampled at the same discrete map instants as x.
    # This is a driven/non-autonomous recurrence.
    sweepDenominator = max(1,totalCtrlSamples-1)
    rStart$ = fixed$(r_start,12)
    rDelta$ = fixed$(r_end-r_start,12)

    selectObject: ctrlSound
    Formula:
        ... "if col=1 then xFirst else ("
        ... + rStart$ + "+" + rDelta$
        ... + "*(col-1)/" + string$(sweepDenominator) + ")"
        ... + "*self[col-1]*(1-self[col-1]) fi"
endif

ctrlId$ = string$(ctrlSound)

selectObject: ctrlSound
xMin = Get minimum: 0,0,"None"
xMax = Get maximum: 0,0,"None"
xMean = Get mean: 0,0

# ---------------------------------------------------------------------------
# FIXED-r DYNAMICAL DIAGNOSTICS
# ---------------------------------------------------------------------------
lyapunov = undefined
detectedPeriod = 0

if parameter_mode = 1
    diagnosticStep = max(1,floor(totalCtrlSamples/5000))
    lyapSum = 0
    lyapCount = 0

    for i from 1 to totalCtrlSamples
        if ((i-1) mod diagnosticStep)=0
            selectObject: ctrlSound
            xv = Get value at sample number: 1,i
            derivAbs = abs(r_start*(1-2*xv))
            lyapSum = lyapSum+ln(max(1e-15,derivAbs))
            lyapCount = lyapCount+1
        endif
    endfor

    if lyapCount > 0
        lyapunov = lyapSum/lyapCount
    endif

    # Search period 1..64 on the tail. Require repeated agreement over several
    # cycles; this is a finite-precision diagnostic, not a proof.
    maxPeriod = min(64,floor((totalCtrlSamples-1)/4))
    periodTolerance = 1e-7

    if maxPeriod >= 1
        for p from 1 to maxPeriod
            if detectedPeriod = 0
                comparisons = min(4*p,totalCtrlSamples-p)
                periodOkay = 1

                for k from 0 to comparisons-1
                    idx1 = totalCtrlSamples-k
                    idx2 = idx1-p

                    selectObject: ctrlSound
                    v1 = Get value at sample number: 1,idx1
                    v2 = Get value at sample number: 1,idx2

                    if abs(v1-v2) > periodTolerance
                        periodOkay = 0
                    endif
                endfor

                if periodOkay
                    detectedPeriod = p
                endif
            endif
        endfor
    endif

    if detectedPeriod > 0
        regime$ = "period-" + string$(detectedPeriod) + " orbit"
    elsif abs(lyapunov) < 0.01
        regime$ = "near-critical / unresolved finite-time orbit"
    elsif lyapunov > 0
        regime$ = "positive-Lyapunov chaotic orbit"
    else
        regime$ = "negative-Lyapunov orbit; period >64 or unresolved"
    endif
else
    regime$ = "non-autonomous r sweep; autonomous regime label not applicable"
endif

# ---------------------------------------------------------------------------
# AUDIO MAPPING / FREQUENCY HEADROOM
# ---------------------------------------------------------------------------
requestedFundTop =
    ... base_frequency_Hz*
    ... 2^(frequency_span_octaves*(xMax-0.5))

requestedFundBottom =
    ... base_frequency_Hz*
    ... 2^(frequency_span_octaves*(xMin-0.5))

if second_harmonic_level > 0
    harmonicFactor = 2
else
    harmonicFactor = 1
endif

frequencyScale =
    ... min(1,safeTop/(harmonicFactor*requestedFundTop))

effectiveBase = base_frequency_Hz*frequencyScale
actualFundBottom = requestedFundBottom*frequencyScale
actualFundTop = requestedFundTop*frequencyScale

if actualFundBottom < 20
    exitScript: "Frequency headroom scaling would move the mapped fundamental below 20 Hz. Reduce Base frequency/span or second harmonic."
endif

# ---------------------------------------------------------------------------
# ZERO-ORDER-HOLD AUDIO-RATE CONTROL
# ---------------------------------------------------------------------------
audioControl = Create Sound from formula:
    ... "logistic_hold_control",
    ... 1,0,duration_s,sr,
    ... "object[" + ctrlId$ + ",1,"
    ... + "min(" + string$(totalCtrlSamples)
    ... + ",max(1,floor(x*" + fixed$(mapRate,9) + ")+1))]"

audioCtrlId$ = string$(audioControl)

# ---------------------------------------------------------------------------
# AUDIO-RATE INSTANTANEOUS FREQUENCY
# ---------------------------------------------------------------------------
frequencySound = Create Sound from formula:
    ... "logistic_instantaneous_frequency",
    ... 1,0,duration_s,sr,
    ... fixed$(effectiveBase,12)
    ... + "*2^(" + fixed$(frequency_span_octaves,12)
    ... + "*(object[" + audioCtrlId$ + ",1,col]-0.5))"

frequencyId$ = string$(frequencySound)

# ---------------------------------------------------------------------------
# AUDIO-RATE PHASE INTEGRATION
# ---------------------------------------------------------------------------
phaseSound = Create Sound from formula:
    ... "logistic_phase",1,0,duration_s,sr,"0"

selectObject: phaseSound
Formula:
    ... "if col=1 then "
    ... + fixed$(twoPi/sr,15)
    ... + "*object[" + frequencyId$ + ",1,col]"
    ... + " else self[col-1]+"
    ... + fixed$(twoPi/sr,15)
    ... + "*object[" + frequencyId$ + ",1,col] fi"

# Convert phase accumulator to a bounded oscillator.
sourceNorm = sqrt(2)/sqrt(1+second_harmonic_level^2)

selectObject: phaseSound
Formula:
    ... fixed$(master_amplitude*sourceNorm,12)
    ... + "*(sin(self)+"
    ... + fixed$(second_harmonic_level,12)
    ... + "*sin(2*self))"

Rename: "LogisticMap_" + replace$(preset_name$," ","_",0)
outputSound = selected("Sound")

# ---------------------------------------------------------------------------
# COMMON EDGE FADE
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.20*duration_s)

if actualFade > 0
    fadeOutStart = duration_s-actualFade

    selectObject: outputSound
    Formula:
        ... "if x<actualFade then self*(x/actualFade)"
        ... + " else if x>fadeOutStart then "
        ... + "self*((duration_s-x)/actualFade)"
        ... + " else self fi fi"
endif

# ---------------------------------------------------------------------------
# SPATIALIZATION
# ---------------------------------------------------------------------------
if spatial_mode = 2
    selectObject: outputSound
    Copy: "logistic_left"
    leftSound = selected("Sound")
    Formula:
        ... "self*sqrt(1-(0.05+0.90*object["
        ... + audioCtrlId$ + ",1,col]))"

    selectObject: outputSound
    Copy: "logistic_right"
    rightSound = selected("Sound")
    Formula:
        ... "self*sqrt(0.05+0.90*object["
        ... + audioCtrlId$ + ",1,col])"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "LogisticMap_" + replace$(preset_name$," ","_",0)

    removeObject: outputSound,leftSound,rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    selectObject: outputSound
    Copy: "logistic_left"
    leftSound = selected("Sound")
    Formula:
        ... "self*sqrt(1-(0.5+0.46*sin(2*pi*"
        ... + fixed$(rotation_rate_Hz,9) + "*x)))"

    selectObject: outputSound
    Copy: "logistic_right"
    rightSound = selected("Sound")
    Formula:
        ... "self*sqrt(0.5+0.46*sin(2*pi*"
        ... + fixed$(rotation_rate_Hz,9) + "*x))"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "LogisticMap_" + replace$(preset_name$," ","_",0)

    removeObject: outputSound,leftSound,rightSound
    outputSound = stereoSound
endif

# ---------------------------------------------------------------------------
# FINAL LEVEL / QC
# ---------------------------------------------------------------------------
selectObject: outputSound
preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.92
    Scale peak: 0.92
    protectionApplied = 1
endif

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels

# ---------------------------------------------------------------------------
# INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LOGISTIC MAP SYNTHESIS v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Parameter mode: ", parameter_name$
appendInfoLine: "r start / end: ",
    ... fixed$(r_start,9), " / ", fixed$(r_end,9)
appendInfoLine: "Initial x: ", fixed$(initial_x,9)
appendInfoLine: "Burn-in iterations: ", burn_in_iterations
appendInfoLine: "Map iteration rate: ",
    ... fixed$(mapRate,2), " iter/s"
appendInfoLine: "Post-burn x range / mean: ",
    ... fixed$(xMin,6), " - ", fixed$(xMax,6),
    ... " / ", fixed$(xMean,6)
appendInfoLine: "Regime diagnostic: ", regime$

if parameter_mode = 1
    appendInfoLine: "Finite-time Lyapunov estimate: ",
        ... fixed$(lyapunov,6)
    appendInfoLine: "Detected period (<=64): ", detectedPeriod
else
    appendInfoLine: "Lyapunov/period: not reported for driven r sweep"
endif

appendInfoLine: "Base frequency requested/effective: ",
    ... fixed$(base_frequency_Hz,2), " / ",
    ... fixed$(effectiveBase,2), " Hz"
appendInfoLine: "Actual mapped fundamental range: ",
    ... fixed$(actualFundBottom,2), " - ",
    ... fixed$(actualFundTop,2), " Hz"
appendInfoLine: "Frequency span: ",
    ... fixed$(frequency_span_octaves,3), " octaves"
appendInfoLine: "Common frequency scale: ",
    ... fixed$(frequencyScale,6)
appendInfoLine: "Spatial mode: ", spatial_name$
appendInfoLine: "Degeneracy note: ", degeneracyNote$
appendInfoLine: "Pre-protection peak/RMS: ",
    ... fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied

# ---------------------------------------------------------------------------
# VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# Controls no longer needed after visualization.
removeObject: ctrlSound,audioControl,frequencySound

# ---------------------------------------------------------------------------
# PLAY / FINAL SELECTION
# ---------------------------------------------------------------------------
selectObject: outputSound
if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# VISUALIZATION PROCEDURE
# ===========================================================================
procedure drawVisualization

    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.82,0.82,0.84}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.90,0.44,0.12}"
    .red$ = "{0.80,0.20,0.20}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "LOGISTIC MAP SYNTHESIS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.38,0.70
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.66,"half",
        ... "x[n+1] = r*x[n]*(1-x[n]) | "
        ... + parameter_name$ + " | "
        ... + fixed$(mapRate,0) + " iterations/s"
    Text: 0.5,"centre",0.18,"half",
        ... "discrete map -> zero-order hold -> instantaneous frequency -> audio-rate phase integration"

    # -----------------------------------------------------------------------
    # PANEL A TITLE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,3.90,0.82,1.02
    Axes: 0,1,0,1
    Font size: 7
    Colour: "Black"

    if parameter_mode = 1
        Text: 0.5,"centre",0.5,"half",
            ... "A  MAP / COBWEB + POST-BURN RETURN POINTS"
    else
        Text: 0.5,"centre",0.5,"half",
            ... "A  DRIVEN PARAMETER TRACE | actual r[n] vs x[n]"
    endif

    # -----------------------------------------------------------------------
    # PANEL A DATA
    # -----------------------------------------------------------------------
    Select inner viewport: 0.58,3.72,1.08,3.35

    if parameter_mode = 1
        Axes: 0,1,0,1
        Paint rectangle: .bg$,0,1,0,1

        Colour: .grid$
        Dotted line
        Draw line: 0,0,1,1
        Plain line

        Colour: .blue$
        Line width: 1.5
        for .j from 0 to 199
            .xa = .j/200
            .xb = (.j+1)/200
            .ya = r_start*.xa*(1-.xa)
            .yb = r_start*.xb*(1-.xb)
            Draw line: .xa,.ya,.xb,.yb
        endfor

        # Cobweb starts from the actual user x0, before burn-in.
        .cx = initial_x
        Colour: .red$
        Line width: 0.8

        for .j from 1 to cobweb_iterations
            .cy = r_start*.cx*(1-.cx)
            Draw line: .cx,.cx,.cx,.cy
            Draw line: .cx,.cy,.cy,.cy
            .cx = .cy
        endfor

        # Actual post-burn return-map points.
        .returnStep = max(1,ceiling(totalCtrlSamples/180))
        Colour: .orange$

        for .i from 1 to totalCtrlSamples-1
            if ((.i-1) mod .returnStep)=0
                selectObject: ctrlSound
                .vx = Get value at sample number: 1,.i
                .vy = Get value at sample number: 1,.i+1
                Paint circle (mm): .orange$,.vx,.vy,0.55
            endif
        endfor

        Colour: "Black"
        Line width: 1
        Draw inner box
        Marks bottom every: 1,0.2,"yes","yes","no"
        Marks left every: 1,0.2,"yes","yes","no"
        Font size: 5
        Text bottom: "yes","x[n]"
        Text left: "yes","x[n+1]"

    else
        .rLo = min(r_start,r_end)
        .rHi = max(r_start,r_end)

        if .rHi <= .rLo
            .rHi = .rLo+0.01
        endif

        Axes: .rLo,.rHi,0,1
        Paint rectangle: .bg$,.rLo,.rHi,0,1
        Colour: .orange$

        .traceStep = max(1,ceiling(totalCtrlSamples/400))

        for .i from 1 to totalCtrlSamples
            if ((.i-1) mod .traceStep)=0
                .rr =
                    ... r_start+(r_end-r_start)*
                    ... (.i-1)/max(1,totalCtrlSamples-1)

                selectObject: ctrlSound
                .vx = Get value at sample number: 1,.i
                Paint circle (mm): .orange$,.rr,.vx,0.48
            endif
        endfor

        Colour: "Black"
        Draw inner box
        Marks bottom: 4,"yes","yes","no"
        Marks left every: 1,0.2,"yes","yes","no"
        Font size: 5
        Text bottom: "yes","r[n]"
        Text left: "yes","x[n]"
    endif

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL POST-BURN SEQUENCE
    # -----------------------------------------------------------------------
    Select inner viewport: 4.10,7.65,0.82,1.02
    Axes: 0,1,0,1
    Font size: 7
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "B  ACTUAL POST-BURN SEQUENCE | first discrete control states"

    .showN = min(80,totalCtrlSamples)

    Select inner viewport: 4.30,7.48,1.08,3.35
    Axes: 1,max(2,.showN),0,1
    Paint rectangle: .bg$,1,max(2,.showN),0,1

    Colour: .grid$
    Dotted line
    Draw line: 1,0.5,max(2,.showN),0.5
    Plain line

    for .i from 1 to .showN
        selectObject: ctrlSound
        .vx = Get value at sample number: 1,.i

        if .i > 1
            Draw line: .i-1,.previousX,.i,.vx
        endif

        Colour: .blue$
        Paint circle (mm): .blue$,.i,.vx,0.62
        .previousX = .vx
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Marks left every: 1,0.2,"yes","yes","no"
    Font size: 5
    Text bottom: "yes","Iteration n"
    Text left: "yes","x[n]"

    # -----------------------------------------------------------------------
    # PANEL C: ACTUAL INSTANTANEOUS-FREQUENCY MAPPING
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.52,3.73
    Axes: 0,1,0,1
    Font size: 7
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "C  STATE -> FREQUENCY | same first control states after log-frequency mapping"

    .fLo = max(20,0.92*actualFundBottom)
    .fHi = 1.08*actualFundTop

    if .fHi <= .fLo
        .fHi = .fLo+10
    endif

    Select inner viewport: 0.82,7.52,3.80,4.80
    Axes: 1,max(2,.showN),.fLo,.fHi
    Paint rectangle: .bg$,1,max(2,.showN),.fLo,.fHi

    for .i from 1 to .showN
        selectObject: ctrlSound
        .vx = Get value at sample number: 1,.i
        .ff =
            ... effectiveBase*
            ... 2^(frequency_span_octaves*(.vx-0.5))

        if .i > 1
            Colour: .orange$
            Draw line: .i-1,.previousF,.i,.ff
        endif

        Paint circle (mm): .orange$,.i,.ff,0.58
        .previousF = .ff
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Marks left: 4,"yes","yes","no"
    Font size: 5
    Text left: "yes","Instantaneous frequency (Hz)"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "logistic_display"
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0,0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0,0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,4.96,5.17
    Axes: 0,1,0,1
    Font size: 7
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "D  MODEL -> MEASUREMENT | measured output spectrum over time"

    .specMax =
        ... min(safeTop,
        ... max(1200,2.15*actualFundTop))

    .specStep = max(0.002,duration_s/1200)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: 0.82,7.52,5.24,6.43
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: "{0.18,0.54,0.82}"
    Line width: 0.7
    Draw line: 0,actualFundBottom,duration_s,actualFundBottom
    Draw line: 0,actualFundTop,duration_s,actualFundTop

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Frequency (Hz)"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # SUMMARY / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.66,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    if parameter_mode = 1
        .dyn$ =
            ... regime$ + " | lambda " + fixed$(lyapunov,5)
            ... + " | detected P " + string$(detectedPeriod)
    else
        .dyn$ =
            ... "driven r sweep " + fixed$(r_start,4)
            ... + " -> " + fixed$(r_end,4)
            ... + " | no autonomous lambda/P claim"
    endif

    Text: 0.02,"left",0.80,"half",
        ... "DYNAMICS  |  " + .dyn$

    Text: 0.02,"left",0.58,"half",
        ... "CONTROL  |  x " + fixed$(xMin,4)
        ... + "-" + fixed$(xMax,4)
        ... + "  |  map rate " + fixed$(mapRate,1)
        ... + "/s  |  burn-in " + string$(burn_in_iterations)

    Text: 0.02,"left",0.36,"half",
        ... "MAPPING  |  fundamental "
        ... + fixed$(actualFundBottom,1) + "-"
        ... + fixed$(actualFundTop,1) + " Hz"
        ... + "  |  span " + fixed$(frequency_span_octaves,2)
        ... + " oct  |  scale " + fixed$(frequencyScale,4)

    if protectionApplied
        .level$ = "down-only protection applied"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.14,"half",
        ... "OUTPUT  |  " + spatial_name$
        ... + "  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  RMS " + fixed$(preProtectRMS,4)
        ... + "  |  " + .level$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
