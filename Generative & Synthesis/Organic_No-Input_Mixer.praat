# ============================================================
# Praat AudioTools - Organic_No-Input_Mixer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 conceptual + DSP review (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ORGANIC NO-INPUT FEEDBACK NETWORK
#
# CONCEPTUAL SCOPE
# ----------------
# This is a DIGITAL FEEDBACK-NETWORK ABSTRACTION inspired by no-input mixing.
# It is not a circuit-level emulation of a specific analogue mixing desk.
#
# In a physical no-input setup an output is routed back to an input, so the
# mixer/effects/routing form an autonomous feedback instrument. Circuit noise,
# EQ, gain, nonlinearities, delays, impedance interactions and performer
# control can all affect the emergent behaviour.
#
# v0.3 did NOT implement temporal feedback. It repeatedly processed an entire
# duration-long Sound through a band-pass filter and waveshaper for N offline
# iterations. Its "analog instability" therefore changed between whole-file
# passes, not through musical time.
#
# v0.4 instead uses a genuine sample-by-sample nonlinear recurrence:
#
#   g_eff[n] =
#       growth_dB_per_s[n]
#       - compression_strength * C * y[n-1]^2
#
#   R_eff[n] = 10^(g_eff[n] / (20*internal_sample_rate))
#
#   y[n] =
#       2*R_eff[n]*cos(omega[n])*y[n-1]
#       - R_eff[n]^2*y[n-2]
#       + circuitNoise[n]
#
# The small-signal poles lie at approximately:
#
#       R[n] * exp(+/- j*omega[n])
#
# so:
#   R < 1  : subcritical / noise-sustained resonance
#   R = 1  : linearized edge of self-oscillation
#   R > 1  : growing oscillation, bounded by nonlinear loop compression
#
# Rather than expose an extremely sample-rate-sensitive pole radius directly,
# the UI specifies NET SMALL-SIGNAL LOOP GROWTH in dB per second:
#
#   R[n] = 10^( growth_dB_per_s[n] / (20*internal_sample_rate) )
#
# This keeps the stability meaning independent of sample rate and internal
# oversampling. Zero dB/s is the linearized threshold.
#
# "Organic instability" is not a static random perturbation. Two independent
# bounded OU-like random walks evolve in TIME:
#   - one perturbs resonance frequency logarithmically
#   - one perturbs loop growth around the threshold
#
# This makes intermittent threshold crossings and spectral wandering explicit.
#
# OVERSAMPLING
# ------------
# The nonlinear feedback core is rendered at up to 2x the requested output
# sampling rate (capped at 192 kHz), then sinc-resampled once. This reduces,
# but does not mathematically eliminate, aliasing from nonlinear saturation.
#
# SPATIALIZATION
# --------------
# Spatial processing occurs AFTER the feedback core. It therefore does not
# pretend that stereo post-processing changes the feedback topology itself.
#
#   Mono
#   Stereo Wide          direct left / short delayed right
#   Slow Rotation        equal-power pan trajectory
#   Micro-delay Headphone
#       simple ITD/ILD study only; NOT an HRTF/binaural simulation
#
# VISUALIZATION
# -------------
#   A actual loop-growth trajectory with the 0 dB/s threshold
#   B actual resonance-frequency trajectory
#   C measured output spectrogram + actual resonance guide
#   D measured short-time RMS vs time
#   process / threshold / sampling / output QC
#
# Conceptual references:
#   Mudd & Brown (2023), Musical pathways through the no-input mixer, NIME.
#   Toshimaru Nakamura interviews describing the no-input mixing board as a
#   mixer/effects feedback system without an external sound source.
# ============================================================

form Organic No-Input Feedback Network v0.4
    optionmenu Preset 1
        option Custom
        option Edge of Oscillation
        option Deep Throbbing Feedback
        option High Frequency Whistle
        option Crackling Near-Threshold Loop
        option Unstable Resonance

    positive Duration_s 10
    integer Output_sample_rate_Hz 44100

    real Loop_growth_dB_per_s 0.0
    positive Resonance_center_Hz 220
    positive Nonlinear_loop_compression 1.8
    positive Circuit_noise_RMS 0.00001

    real Organic_instability 0.08
    positive Organic_rate_Hz 0.15

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Slow Rotation
        option Micro-delay Headphone

    integer Random_seed 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED / MODEL CONSTANTS
# ---------------------------------------------------------------------------
controlRate = 80
frequencyDriftOctavesAtFull = 0.80
growthDriftDbAtFull = 30
masterAmplitude = 0.72
compressionDbPerAmpSquared = 80
edgeFade_s = 0.025
wideDelay_ms = 1.20
headphoneDelay_ms = 0.30
rotationRate_Hz = 0.08

preset_name$ = "Custom"

# ---------------------------------------------------------------------------
# PRESETS
# ---------------------------------------------------------------------------
if preset = 2
    loop_growth_dB_per_s = 0.0
    resonance_center_Hz = 440
    nonlinear_loop_compression = 1.45
    circuit_noise_RMS = 0.000006
    organic_instability = 0.08
    organic_rate_Hz = 0.12
    preset_name$ = "Edge of Oscillation"

elsif preset = 3
    loop_growth_dB_per_s = 7.0
    resonance_center_Hz = 62
    nonlinear_loop_compression = 2.10
    circuit_noise_RMS = 0.000004
    organic_instability = 0.13
    organic_rate_Hz = 0.07
    preset_name$ = "Deep Throbbing Feedback"

elsif preset = 4
    loop_growth_dB_per_s = 2.0
    resonance_center_Hz = 2600
    nonlinear_loop_compression = 1.55
    circuit_noise_RMS = 0.000003
    organic_instability = 0.025
    organic_rate_Hz = 0.20
    preset_name$ = "High Frequency Whistle"

elsif preset = 5
    loop_growth_dB_per_s = -2.0
    resonance_center_Hz = 820
    nonlinear_loop_compression = 2.80
    circuit_noise_RMS = 0.000045
    organic_instability = 0.24
    organic_rate_Hz = 0.65
    preset_name$ = "Crackling Near-Threshold Loop"

elsif preset = 6
    loop_growth_dB_per_s = 1.0
    resonance_center_Hz = 360
    nonlinear_loop_compression = 2.30
    circuit_noise_RMS = 0.000008
    organic_instability = 0.28
    organic_rate_Hz = 0.22
    preset_name$ = "Unstable Resonance"
endif

# ---------------------------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 180
    exitScript: "Duration must be > 0 and <= 180 seconds."
endif
if output_sample_rate_Hz < 8000 or output_sample_rate_Hz > 192000
    exitScript: "Output sample rate must be between 8000 and 192000 Hz."
endif
if loop_growth_dB_per_s < -120 or loop_growth_dB_per_s > 120
    exitScript: "Loop growth must be between -120 and +120 dB/s."
endif
if resonance_center_Hz < 20
    exitScript: "Resonance center must be at least 20 Hz."
endif
if nonlinear_loop_compression < 0.2 or nonlinear_loop_compression > 20
    exitScript: "Nonlinear loop compression must be between 0.2 and 20."
endif
if circuit_noise_RMS <= 0 or circuit_noise_RMS > 0.1
    exitScript: "Circuit noise RMS must be > 0 and <= 0.1."
endif
if organic_instability < 0 or organic_instability > 1
    exitScript: "Organic instability must be between 0 and 1."
endif
if organic_rate_Hz <= 0 or organic_rate_Hz > 10
    exitScript: "Organic rate must be > 0 and <= 10 Hz."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

outputSr = output_sample_rate_Hz
safeTop = 0.42*outputSr

if resonance_center_Hz > safeTop
    frequencyScale = safeTop/resonance_center_Hz
else
    frequencyScale = 1
endif

effectiveCenter = resonance_center_Hz*frequencyScale

# Nonlinear core is oversampled when feasible.
renderRate = min(192000,2*outputSr)
oversampleFactor = renderRate/outputSr

# ---------------------------------------------------------------------------
# RANDOMNESS
# ---------------------------------------------------------------------------
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

uid$ = string$(randomInteger(10000,99999))

# ---------------------------------------------------------------------------
# ORGANIC CONTROL RANDOM WALKS
# ---------------------------------------------------------------------------
# For an OU-like process with approximate correlation rate organic_rate_Hz:
# a = exp(-2*pi*rate/controlRate)
# innovation scale sqrt(1-a^2) gives roughly unit unconstrained variance.
ouA = exp(-2*pi*organic_rate_Hz/controlRate)
ouInnovation = sqrt(max(1e-12,1-ouA*ouA))

freqDrift = Create Sound from formula:
    ... "nim_freq_drift_" + uid$,
    ... 1,0,duration_s,controlRate,
    ... "if col=1 then 0 else max(-1,min(1,"
    ... + fixed$(ouA,12) + "*self[col-1]+"
    ... + fixed$(ouInnovation,12) + "*randomGauss(0,1))) fi"

gainDrift = Create Sound from formula:
    ... "nim_gain_drift_" + uid$,
    ... 1,0,duration_s,controlRate,
    ... "if col=1 then 0 else max(-1,min(1,"
    ... + fixed$(ouA,12) + "*self[col-1]+"
    ... + fixed$(ouInnovation,12) + "*randomGauss(0,1))) fi"

freqDriftId$ = string$(freqDrift)
gainDriftId$ = string$(gainDrift)

# ---------------------------------------------------------------------------
# ACTUAL CONTROL TRAJECTORIES AT CONTROL RATE
# ---------------------------------------------------------------------------
freqTrace = Create Sound from formula:
    ... "nim_frequency_trace_" + uid$,
    ... 1,0,duration_s,controlRate,
    ... fixed$(effectiveCenter,12)
    ... + "*2^(" + fixed$(organic_instability*frequencyDriftOctavesAtFull,12)
    ... + "*object[" + freqDriftId$ + ",1,col])"

growthTrace = Create Sound from formula:
    ... "nim_growth_trace_" + uid$,
    ... 1,0,duration_s,controlRate,
    ... fixed$(loop_growth_dB_per_s,12)
    ... + "+" + fixed$(organic_instability*growthDriftDbAtFull,12)
    ... + "*object[" + gainDriftId$ + ",1,col]"

freqTraceId$ = string$(freqTrace)
growthTraceId$ = string$(growthTrace)

# Clamp frequency trajectory to a conservative output-band headroom.
selectObject: freqTrace
Formula: "max(20,min(" + fixed$(safeTop,9) + ",self))"

# ---------------------------------------------------------------------------
# CONTROL QC
# ---------------------------------------------------------------------------
selectObject: freqTrace
minFreq = Get minimum: 0,0,"None"
maxFreq = Get maximum: 0,0,"None"
meanFreq = Get mean: 0,0

selectObject: growthTrace
minGrowth = Get minimum: 0,0,"None"
maxGrowth = Get maximum: 0,0,"None"
meanGrowth = Get mean: 0,0
growthSamples = Get number of samples

aboveThreshold = 0
for c from 1 to growthSamples
    g = Get value at sample number: 1,c
    if g > 0
        aboveThreshold = aboveThreshold+1
    endif
endfor
fractionAboveThreshold = aboveThreshold/growthSamples

# ---------------------------------------------------------------------------
# EXACT INTERNAL-RATE CONTROL SOUNDS
# ---------------------------------------------------------------------------
# Growth is converted to pole radius at the INTERNAL render rate:
#   R = 10^(growth_dB_per_s / (20*renderRate)).
frequencyAudio = Create Sound from formula:
    ... "nim_frequency_audio_" + uid$,
    ... 1,0,duration_s,renderRate,
    ... "object(" + freqTraceId$ + ",x,1)"

radiusAudio = Create Sound from formula:
    ... "nim_radius_audio_" + uid$,
    ... 1,0,duration_s,renderRate,
    ... "10^(object(" + growthTraceId$ + ",x,1)/(20*"
    ... + string$(renderRate) + "))"

frequencyAudioId$ = string$(frequencyAudio)
radiusAudioId$ = string$(radiusAudio)

# ---------------------------------------------------------------------------
# NONLINEAR SAMPLE-BY-SAMPLE FEEDBACK CORE
# ---------------------------------------------------------------------------
# The stored radiusAudio is the SMALL-SIGNAL radius implied by growthTrace.
# During oscillation, amplitude-dependent loop loss reduces the instantaneous
# growth rate while preserving the resonator angle/frequency. This avoids the
# large pitch shift produced by clipping the feedback waveform itself.
coreSound = Create Sound from formula:
    ... "nim_feedback_core_" + uid$,
    ... 1,0,duration_s,renderRate,
    ... fixed$(circuit_noise_RMS,12) + "*randomGauss(0,1)"

selectObject: coreSound

compressionCoeff =
    ... nonlinear_loop_compression*compressionDbPerAmpSquared

# Convert the amplitude-dependent dB/s loss to a per-internal-sample radius
# multiplier:
#   R_loss = 10^(-compressionCoeff*y[n-1]^2/(20*renderRate))
radiusLossFactor$ =
    ... "10^(-" + fixed$(compressionCoeff,9)
    ... + "*self[col-1]^2/(20*" + string$(renderRate) + "))"

effectiveRadius$ =
    ... "(object[" + radiusAudioId$ + ",1,col]*"
    ... + radiusLossFactor$ + ")"

feedbackExpr$ =
    ... "2*" + effectiveRadius$
    ... + "*cos(2*pi*object[" + frequencyAudioId$ + ",1,col]/"
    ... + string$(renderRate) + ")*self[col-1]"
    ... + "-" + effectiveRadius$ + "^2*self[col-2]"
    ... + "+" + fixed$(circuit_noise_RMS,12)
    ... + "*randomGauss(0,1)"

Formula:
    ... "if col<=2 then self else " + feedbackExpr$ + " fi"

Formula: "self*" + fixed$(masterAmplitude,9)

# ---------------------------------------------------------------------------
# BAND-LIMIT BACK TO REQUESTED OUTPUT RATE
# ---------------------------------------------------------------------------
if renderRate <> outputSr
    selectObject: coreSound
    Resample: outputSr,50
    resampledCore = selected("Sound")
    removeObject: coreSound
    coreSound = resampledCore
endif

Rename: "nim_core_" + uid$

# ---------------------------------------------------------------------------
# SPATIALIZATION
# ---------------------------------------------------------------------------
if spatial_mode = 1
    selectObject: coreSound
    Rename: "Organic_NoInput_" + replace$(preset_name$," ","_",0)
    outputSound = selected("Sound")
    spatialName$ = "Mono"

elsif spatial_mode = 2
    selectObject: coreSound
    Copy: "nim_left_" + uid$
    leftSound = selected("Sound")

    selectObject: coreSound
    Copy: "nim_right_" + uid$
    rightSound = selected("Sound")

    wideDelaySamples = max(1,round(wideDelay_ms*outputSr/1000))
    coreId$ = string$(coreSound)

    selectObject: rightSound
    Formula:
        ... "if col>" + string$(wideDelaySamples)
        ... + " then object[" + coreId$ + ",1,col-"
        ... + string$(wideDelaySamples) + "] else 0 fi"

    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "Organic_NoInput_" + replace$(preset_name$," ","_",0)
    removeObject: coreSound,leftSound,rightSound
    spatialName$ = "Stereo Wide"

elsif spatial_mode = 3
    selectObject: coreSound
    Copy: "nim_left_" + uid$
    leftSound = selected("Sound")
    Formula:
        ... "self*sqrt(1-(0.5+0.46*sin(2*pi*"
        ... + fixed$(rotationRate_Hz,9) + "*x)))"

    selectObject: coreSound
    Copy: "nim_right_" + uid$
    rightSound = selected("Sound")
    Formula:
        ... "self*sqrt(0.5+0.46*sin(2*pi*"
        ... + fixed$(rotationRate_Hz,9) + "*x))"

    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "Organic_NoInput_" + replace$(preset_name$," ","_",0)
    removeObject: coreSound,leftSound,rightSound
    spatialName$ = "Slow Rotation"

else
    selectObject: coreSound
    Copy: "nim_left_" + uid$
    leftSound = selected("Sound")

    selectObject: coreSound
    Copy: "nim_right_" + uid$
    rightSound = selected("Sound")

    headphoneDelaySamples =
        ... max(1,round(headphoneDelay_ms*outputSr/1000))
    coreId$ = string$(coreSound)

    selectObject: rightSound
    Formula:
        ... "if col>" + string$(headphoneDelaySamples)
        ... + " then 0.92*object[" + coreId$ + ",1,col-"
        ... + string$(headphoneDelaySamples) + "] else 0 fi"

    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "Organic_NoInput_" + replace$(preset_name$," ","_",0)
    removeObject: coreSound,leftSound,rightSound
    spatialName$ = "Micro-delay Headphone (ITD/ILD study, not HRTF)"
endif

# ---------------------------------------------------------------------------
# SHORT COMMON EDGE FADE
# ---------------------------------------------------------------------------
actualFade = min(edgeFade_s,0.20*duration_s)
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

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  ORGANIC NO-INPUT FEEDBACK NETWORK v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Scope: digital feedback-network abstraction; NOT mixer circuit emulation"
appendInfoLine: "Duration: ", fixed$(duration_s,3), " s"
appendInfoLine: "Output / internal sample rate: ",
    ... outputSr, " / ", renderRate, " Hz"
appendInfoLine: "Internal oversampling factor: ",
    ... fixed$(oversampleFactor,2)
appendInfoLine: "Requested / effective center: ",
    ... fixed$(resonance_center_Hz,1), " / ",
    ... fixed$(effectiveCenter,1), " Hz"
appendInfoLine: "Actual resonance trajectory: ",
    ... fixed$(minFreq,1), " - ", fixed$(maxFreq,1),
    ... " Hz (mean ", fixed$(meanFreq,1), ")"
appendInfoLine: "Loop growth trajectory: ",
    ... fixed$(minGrowth,2), " - ", fixed$(maxGrowth,2),
    ... " dB/s (mean ", fixed$(meanGrowth,2), ")"
appendInfoLine: "Time above linearized self-oscillation threshold: ",
    ... fixed$(100*fractionAboveThreshold,1), "%"
appendInfoLine: "Nonlinear loop compression: ", fixed$(nonlinear_loop_compression,3)
appendInfoLine: "Circuit noise RMS: ", fixed$(circuit_noise_RMS,7)
appendInfoLine: "Organic instability/rate: ",
    ... fixed$(organic_instability,3), " / ",
    ... fixed$(organic_rate_Hz,3), " Hz"
appendInfoLine: "Spatial mode: ", spatialName$
appendInfoLine: "Randomness: ", seedLabel$
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

# Remove internal controls after visualization.
removeObject:
    ... freqDrift,gainDrift,freqTrace,growthTrace,
    ... frequencyAudio,radiusAudio

# ---------------------------------------------------------------------------
# PLAY / FINAL SELECTION
# ---------------------------------------------------------------------------
selectObject: outputSound
if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.82
    .right = 7.55
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.82,0.82,0.84}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.88,0.42,0.15}"
    .red$ = "{0.78,0.20,0.18}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER / PROCESS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "ORGANIC NO-INPUT FEEDBACK NETWORK | " + preset_name$

    Select inner viewport: 0.30,7.70,0.37,0.72
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.36}"
    Text: 0.5,"centre",0.69,"half",
        ... "circuit noise -> resonant recurrence -> amplitude-dependent loop loss -> feedback state -> output"
    Text: 0.5,"centre",0.20,"half",
        ... "small-signal R(t)=10^(growth_dB/s / (20*Fs_internal));  0 dB/s is the threshold"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL GROWTH / THRESHOLD
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.83,1.04
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "A  ACTUAL LOOP GROWTH | stochastic threshold crossings happen in musical time"

    .gPad = max(1,0.10*(maxGrowth-minGrowth))
    .gLo = min(-1,minGrowth-.gPad)
    .gHi = max(1,maxGrowth+.gPad)

    Select inner viewport: .left,.right,1.11,2.08
    Axes: 0,duration_s,.gLo,.gHi
    Paint rectangle: .bg$,0,duration_s,.gLo,.gHi

    Colour: .grid$
    Dotted line
    Draw line: 0,0,duration_s,0
    Plain line

    selectObject: growthTrace
    .nControl = Get number of samples
    .controlStep = max(1,ceiling(.nControl/1200))

    .havePrev = 0
    for .i from 1 to .nControl
        if ((.i-1) mod .controlStep)=0
            .t = (.i-1)/controlRate
            .g = Get value at sample number: 1,.i

            if .g > 0
                Colour: .red$
            else
                Colour: .blue$
            endif

            if .havePrev
                Draw line: .prevT,.prevG,.t,.g
            endif

            .prevT = .t
            .prevG = .g
            .havePrev = 1
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Growth (dB/s)"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL FREQUENCY DRIFT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.23,2.44
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "B  ACTUAL RESONANCE TRAJECTORY | bounded correlated drift"

    .fPad = max(10,0.08*(maxFreq-minFreq))
    .fLo = max(20,minFreq-.fPad)
    .fHi = max(.fLo+20,maxFreq+.fPad)

    Select inner viewport: .left,.right,2.51,3.45
    Axes: 0,duration_s,.fLo,.fHi
    Paint rectangle: .bg$,0,duration_s,.fLo,.fHi

    Colour: .grid$
    Dotted line
    Draw line: 0,effectiveCenter,duration_s,effectiveCenter
    Plain line

    Colour: .orange$
    selectObject: freqTrace
    .havePrev = 0

    for .i from 1 to .nControl
        if ((.i-1) mod .controlStep)=0
            .t = (.i-1)/controlRate
            .f = Get value at sample number: 1,.i

            if .havePrev
                Draw line: .prevT,.prevF,.t,.f
            endif

            .prevT = .t
            .prevF = .f
            .havePrev = 1
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "nim_display_" + uid$
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
    # PANEL C: MEASURED SPECTROGRAM + MODEL GUIDE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.60,3.81
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + actual resonance guide"

    .specMax = min(0.45*outputSr,max(2000,4*maxFreq))
    .specStep = max(0.002,duration_s/1200)

    selectObject: .disp
    To Spectrogram: 0.030,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,3.88,5.00
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: "{0.10,0.72,0.90}"
    Line width: 0.8

    selectObject: freqTrace
    .havePrev = 0
    for .i from 1 to .nControl
        if ((.i-1) mod .controlStep)=0
            .t = (.i-1)/controlRate
            .f = Get value at sample number: 1,.i

            if .havePrev
                Draw line: .prevT,.prevF,.t,.f
            endif

            .prevT = .t
            .prevF = .f
            .havePrev = 1
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SHORT-TIME RMS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.15,5.36
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "D  MEASURED OUTPUT ENERGY | short-time RMS reveals growth, saturation and quenching"

    .bins = min(140,max(40,round(duration_s*8)))
    .rmsDb# = zero#(.bins)
    .minDb = 0

    selectObject: .disp
    for .b from 1 to .bins
        .t0 = duration_s*(.b-1)/.bins
        .t1 = duration_s*.b/.bins
        .r = Get root-mean-square: .t0,.t1
        .db = 20*log10(max(1e-8,.r))
        .rmsDb#[.b] = .db

        if .b = 1 or .db < .minDb
            .minDb = .db
        endif
    endfor

    .yLo = max(-100,min(-40,floor(.minDb/10)*10-10))

    Select inner viewport: .left,.right,5.43,6.38
    Axes: 0,duration_s,.yLo,0
    Paint rectangle: .bg$,0,duration_s,.yLo,0

    Colour: .grid$
    Dotted line
    Draw line: 0,-20,duration_s,-20
    Draw line: 0,-40,duration_s,-40
    Plain line

    Colour: .blue$
    Line width: 1.2
    for .b from 2 to .bins
        .ta = duration_s*(.b-1.5)/.bins
        .tb = duration_s*(.b-0.5)/.bins
        Draw line:
            ... .ta,.rmsDb#[.b-1],
            ... .tb,.rmsDb#[.b]
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","RMS (dB)"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.60,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.81,"half",
        ... "MODEL  |  digital nonlinear feedback abstraction; no external source; continuous circuit-noise excitation"

    Text: 0.02,"left",0.60,"half",
        ... "THRESHOLD  |  growth " + fixed$(minGrowth,1)
        ... + " to " + fixed$(maxGrowth,1) + " dB/s"
        ... + "  |  above 0 dB/s for "
        ... + fixed$(100*fractionAboveThreshold,1) + "% of control samples"

    Text: 0.02,"left",0.39,"half",
        ... "SPECTRUM  |  resonance " + fixed$(minFreq,0)
        ... + "-" + fixed$(maxFreq,0) + " Hz"
        ... + "  |  output/internal Fs " + string$(outputSr)
        ... + "/" + string$(renderRate)
        ... + "  |  scale " + fixed$(frequencyScale,4)

    if protectionApplied
        .level$ = "down-only protection applied"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.18,"half",
        ... "OUTPUT  |  " + spatialName$
        ... + "  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  RMS " + fixed$(preProtectRMS,4)
        ... + "  |  " + .level$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
