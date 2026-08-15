# ============================================================
# Praat AudioTools - GENDYN_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.2.1 visual spacing (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# DYNAMIC STOCHASTIC SYNTHESIS - GENDYN FAMILY
#
#   A waveform cycle is a polygon defined by N breakpoints. Every breakpoint
#   has an amplitude and a relative time spacing. The polygon is sampled by
#   linear interpolation at the target audio sample rate.
#
#   v3.2 uses SECOND-ORDER stochastic motion for both breakpoint dimensions:
#
#       velocity[n+1] = reflect(velocity[n] + random_step)
#       position[n+1] = reflect(position[n] + velocity[n+1])
#
#   Thus the stochastic distribution perturbs a primary walk (velocity),
#   whose current position becomes the step of the secondary breakpoint walk.
#   This is closer to the mature GENDYN/Gendy3 family than the first-order
#   breakpoint walks used in v3.1.
#
# PITCH MODEL / HONESTY
#   This AudioTools variant retains the established controllable pitch walk:
#   breakpoint time spacings are normalized to one cycle and a separate
#   bounded frequency walk determines the cycle period. That is Gendy3-like
#   in its normalized-period construction, but it is NOT a literal historical
#   reconstruction of Xenakis's complete GENDYN program or Gendy3 score logic.
#
#   Frequency_range_factor is now ACTIVE. The pitch walk is confined to:
#
#       max(Min_frequency, Base_frequency / factor)
#           ...
#       min(Max_frequency, Base_frequency * factor)
#
#   A factor of 1 therefore gives fixed pitch.
#
# DISTRIBUTIONS
#   Uniform, Cauchy and Logistic are GENDYN-family choices. Gaussian is kept
#   as an AudioTools extension. All stochastic increments are bounded before
#   entering the second-order walks.
#
# v3.2.1 visual spacing:
#   - Picture-layout only: separated panel title/subtitle/legend strips.
#   - Moved Panel A legend out of the data frame.
#   - Added independent BP1 subheaders above the two Panel B plots.
#   - Increased C/D and D/summary gaps so axis text cannot collide.
#   - No stochastic, GENDYN, DSP, preset or level logic changed.
#
# v3.2 reviewed:
#   - Fixed previously unused Frequency_range parameter; it now controls the
#     active frequency range factor around Base_frequency.
#   - Replaced first-order amplitude/duration walks with second-order walks.
#   - Replaced one-bounce/snap barriers with true repeated reflecting barriers.
#   - Added reproducible Random_seed for initial shape and all evolution.
#   - Distribution labels are defined explicitly; no reliance on form strings.
#   - Retained full-audio-rate per-period Formula(part) rendering from v3.1.
#   - Duration evolution is expressed relative to mean breakpoint spacing,
#     kept positive by reflecting segment barriers, then normalized per cycle.
#   - Added practical resolution QC (samples per breakpoint at top pitch) and
#     a generation-workload guard.
#   - Fixed unsafe "stereoSound = Combine to stereo" command pattern.
#   - Rotating mode now spatializes the two independent voices with an
#     equal-power cross-rotation instead of unrelated cosine/sine gains.
#   - One combined output edge fade; one optional final/common normalization.
#   - Compact laptop-safe main form + optional stochastic/boundary detail page.
#   - Visualization rebuilt around the mechanism:
#       A actual start/mid/final breakpoint polygons
#       B actual selected-breakpoint amplitude and relative-duration walks
#       C actual pitch walk and effective barriers
#       D measured spectrogram + actual pitch trajectory
#       second-order-walk / resolution / level QC
# ============================================================

form GENDYN Family Dynamic Stochastic Synthesis v3.2.1
    optionmenu Preset 1
        option Custom (baseline values)
        option Gendy3-like 12-Point Motion
        option High Fast Breakpoint Motion
        option Deep Slow Mutation
        option Bright Wide Motion
        option Slow Narrow Evolution
        option Chaotic Wide Motion
        option Soft Logistic Motion
        option Medium Logistic Organism

    positive Duration_s 12.0
    integer Sample_rate_Hz 44100
    integer Number_of_breakpoints 12
    positive Base_frequency_Hz 180
    positive Frequency_range_factor 2.0

    real Amplitude_step 0.15
    real Duration_step 0.12

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Dual
        option Equal-Power Cross-Rotation

    boolean Edit_stochastic_boundaries 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
distribution_type = 2
amplitude_barrier = 0.95
min_frequency_Hz = 20
max_frequency_Hz = 2000
random_seed = 0
edge_fade_s = 0.02

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    duration_s = 12.0
    number_of_breakpoints = 12
    base_frequency_Hz = 180
    frequency_range_factor = 2.5
    amplitude_step = 0.18
    duration_step = 0.15
    distribution_type = 2
    amplitude_barrier = 0.92
    min_frequency_Hz = 30
    max_frequency_Hz = 1500
    spatial_mode = 2
    preset_name$ = "Gendy3-like 12-Point Motion"

elsif preset = 3
    duration_s = 8.0
    number_of_breakpoints = 8
    base_frequency_Hz = 400
    frequency_range_factor = 1.5
    amplitude_step = 0.25
    duration_step = 0.20
    distribution_type = 2
    amplitude_barrier = 0.95
    min_frequency_Hz = 100
    max_frequency_Hz = 3000
    spatial_mode = 3
    preset_name$ = "High Fast Breakpoint Motion"

elsif preset = 4
    duration_s = 20.0
    number_of_breakpoints = 16
    base_frequency_Hz = 60
    frequency_range_factor = 1.8
    amplitude_step = 0.10
    duration_step = 0.08
    distribution_type = 3
    amplitude_barrier = 0.95
    min_frequency_Hz = 20
    max_frequency_Hz = 400
    spatial_mode = 2
    preset_name$ = "Deep Slow Mutation"

elsif preset = 5
    duration_s = 10.0
    number_of_breakpoints = 10
    base_frequency_Hz = 800
    frequency_range_factor = 2.0
    amplitude_step = 0.20
    duration_step = 0.18
    distribution_type = 2
    amplitude_barrier = 0.95
    min_frequency_Hz = 200
    max_frequency_Hz = 4000
    spatial_mode = 3
    preset_name$ = "Bright Wide Motion"

elsif preset = 6
    duration_s = 30.0
    number_of_breakpoints = 20
    base_frequency_Hz = 100
    frequency_range_factor = 1.2
    amplitude_step = 0.05
    duration_step = 0.04
    distribution_type = 3
    amplitude_barrier = 0.95
    min_frequency_Hz = 30
    max_frequency_Hz = 500
    spatial_mode = 2
    preset_name$ = "Slow Narrow Evolution"

elsif preset = 7
    duration_s = 8.0
    number_of_breakpoints = 8
    base_frequency_Hz = 200
    frequency_range_factor = 4.0
    amplitude_step = 0.35
    duration_step = 0.30
    distribution_type = 2
    amplitude_barrier = 0.95
    min_frequency_Hz = 40
    max_frequency_Hz = 2500
    spatial_mode = 3
    preset_name$ = "Chaotic Wide Motion"

elsif preset = 8
    duration_s = 15.0
    number_of_breakpoints = 14
    base_frequency_Hz = 150
    frequency_range_factor = 1.5
    amplitude_step = 0.08
    duration_step = 0.06
    distribution_type = 4
    amplitude_barrier = 0.60
    min_frequency_Hz = 50
    max_frequency_Hz = 800
    spatial_mode = 2
    preset_name$ = "Soft Logistic Motion"

elsif preset = 9
    duration_s = 12.0
    number_of_breakpoints = 12
    base_frequency_Hz = 120
    frequency_range_factor = 2.2
    amplitude_step = 0.12
    duration_step = 0.10
    distribution_type = 4
    amplitude_barrier = 0.90
    min_frequency_Hz = 40
    max_frequency_Hz = 1000
    spatial_mode = 3
    preset_name$ = "Medium Logistic Organism"
endif

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_stochastic_boundaries
    beginPause: "GENDYN v3.2.1 - Stochastic / Boundary Details"
        optionmenu: "Step distribution", distribution_type
            option: "Uniform"
            option: "Cauchy"
            option: "Gaussian (extension)"
            option: "Logistic"
        real: "Amplitude barrier", amplitude_barrier
        real: "Minimum frequency (Hz)", min_frequency_Hz
        real: "Maximum frequency (Hz)", max_frequency_Hz
        integer: "Random seed (0 = unpredictable)", random_seed
        real: "Edge fade (s)", edge_fade_s
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# 1. VALIDATION / EFFECTIVE PITCH BOUNDS
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if number_of_breakpoints < 3 or number_of_breakpoints > 40
    exitScript: "Number of breakpoints must be between 3 and 40."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if frequency_range_factor < 1 or frequency_range_factor > 16
    exitScript: "Frequency range factor must be between 1 and 16."
endif
if amplitude_step < 0 or amplitude_step > 1
    exitScript: "Amplitude step must be between 0 and 1."
endif
if duration_step < 0 or duration_step > 1
    exitScript: "Duration step must be between 0 and 1."
endif
if amplitude_barrier <= 0 or amplitude_barrier > 1
    exitScript: "Amplitude barrier must be > 0 and <= 1."
endif
if min_frequency_Hz <= 0 or max_frequency_Hz <= 0 or min_frequency_Hz > max_frequency_Hz
    exitScript: "Frequency boundaries must be positive and Min <= Max."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

if distribution_type = 1
    distribution$ = "Uniform"
elsif distribution_type = 2
    distribution$ = "Cauchy"
elsif distribution_type = 3
    distribution$ = "Gaussian extension"
else
    distribution$ = "Logistic"
endif

if spatial_mode = 1
    spatial$ = "Mono"
elsif spatial_mode = 2
    spatial$ = "Stereo Dual"
else
    spatial$ = "Equal-Power Cross-Rotation"
endif

rangeLow = base_frequency_Hz/frequency_range_factor
rangeHigh = base_frequency_Hz*frequency_range_factor
effectiveMinFreq = max(min_frequency_Hz,rangeLow)
effectiveMaxFreq = min(max_frequency_Hz,rangeHigh)

# Keep the fundamental itself below practical Nyquist. Polygon corners can
# produce higher harmonics; that is inherent in piecewise-linear DSS.
effectiveMaxFreq = min(effectiveMaxFreq,0.45*sample_rate_Hz)

if effectiveMinFreq > effectiveMaxFreq
    exitScript: "Frequency-range factor and Min/Max boundaries have no overlap."
endif

if base_frequency_Hz < effectiveMinFreq
    initialFrequency = effectiveMinFreq
elsif base_frequency_Hz > effectiveMaxFreq
    initialFrequency = effectiveMaxFreq
else
    initialFrequency = base_frequency_Hz
endif

avgSamplesPerBreakpointAtTop =
    ... sample_rate_Hz/(max(1e-9,effectiveMaxFreq)*number_of_breakpoints)
resolutionWarning = avgSamplesPerBreakpointAtTop < 2

maxGenerationEstimate = duration_s*effectiveMaxFreq
if maxGenerationEstimate > 150000
    exitScript: "Worst-case generation count exceeds 150,000. Reduce duration or maximum pitch range."
endif

uid$ = string$(randomInteger(10000,99999))
twoPi = 2*pi
startTime = stopwatch

seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

# ---------------------------------------------------------------------------
# 2. INITIALIZE BREAKPOINT POSITIONS + PRIMARY WALKS
# ---------------------------------------------------------------------------
meanSeg = 1/number_of_breakpoints
minSeg = 0.08*meanSeg
maxSeg = 4.0*meanSeg

for bp from 1 to number_of_breakpoints
    # Mild random initial shape; the stochastic evolution rapidly dominates.
    amp[bp] = randomUniform(-0.25*amplitude_barrier,0.25*amplitude_barrier)
    dur[bp] = meanSeg
    ampVelocity[bp] = 0
    durVelocity[bp] = 0

    ampStart[bp] = amp[bp]
    durStart[bp] = dur[bp]
endfor

currentFreq = initialFrequency

if spatial_mode >= 2
    for bp from 1 to number_of_breakpoints
        amp2[bp] = randomUniform(-0.25*amplitude_barrier,0.25*amplitude_barrier)
        dur2[bp] = meanSeg
        ampVelocity2[bp] = 0
        durVelocity2[bp] = 0
    endfor

    currentFreq2 = initialFrequency*randomUniform(0.985,1.015)
    currentFreq2 = max(effectiveMinFreq,min(effectiveMaxFreq,currentFreq2))
endif

# ---------------------------------------------------------------------------
# 3. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  GENDYN FAMILY DSS v3.2.1"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Breakpoints: ", number_of_breakpoints
appendInfoLine: "Distribution: ", distribution$
appendInfoLine: "Second-order amplitude/duration walks: yes"
appendInfoLine: "Base frequency: ", fixed$(base_frequency_Hz,2), " Hz"
appendInfoLine: "Active frequency range: ",
    ... fixed$(effectiveMinFreq,2), "-", fixed$(effectiveMaxFreq,2), " Hz"
appendInfoLine: "Frequency factor: x", fixed$(frequency_range_factor,2)
appendInfoLine: "Samples / breakpoint at top pitch (mean): ",
    ... fixed$(avgSamplesPerBreakpointAtTop,2)
if resolutionWarning
    appendInfoLine: "QC WARNING: fewer than 2 samples per breakpoint on average at top pitch."
endif
appendInfoLine: "Spatial: ", spatial$
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 4. OUTPUT BUFFERS + BREAKPOINT MATRICES
# ---------------------------------------------------------------------------
outputSound = Create Sound from formula:
    ... "gendyn_" + uid$,1,0,duration_s,sample_rate_Hz,"0"

if spatial_mode >= 2
    outputSound2 = Create Sound from formula:
        ... "gendyn2_" + uid$,1,0,duration_s,sample_rate_Hz,"0"
endif

nBp1 = number_of_breakpoints+1
amMat = Create simple Matrix: "am1_" + uid$,1,nBp1,"0"
cmMat = Create simple Matrix: "cm1_" + uid$,1,nBp1,"0"

if spatial_mode >= 2
    amMat2 = Create simple Matrix: "am2_" + uid$,1,nBp1,"0"
    cmMat2 = Create simple Matrix: "cm2_" + uid$,1,nBp1,"0"
endif

# ---------------------------------------------------------------------------
# 5. SYNTHESIZE VOICE 1
# ---------------------------------------------------------------------------
@buildGendynFormula: amMat,cmMat,"genT","genP"
gendynF1$ = buildGendynFormula.result$

if spatial_mode >= 2
    @buildGendynFormula: amMat2,cmMat2,"genT2","genP2"
    gendynF2$ = buildGendynFormula.result$
endif

appendInfoLine: "Synthesizing dynamic stochastic voice 1..."

genT = 0
generation = 0
traceCount = 0
midCaptured = 0
lastReportPercent = 0
traceDurRelMax = 1
pitchMinRealized = currentFreq
pitchMaxRealized = currentFreq

# The distribution perturbs the primary velocity walks. Their barriers are
# the user step-size controls. Acceleration increments are a fraction of those
# maxima so velocity retains correlation from cycle to cycle.
ampAccelStep = 0.30*amplitude_step
durAccelStep = 0.30*duration_step
pitchStep = min(0.08,0.50*duration_step)

while genT < duration_s
    generation = generation+1
    genP = 1/currentFreq

    # Trace ACTUAL state used for this rendered generation.
    traceCount = traceCount+1
    traceTime[traceCount] = genT
    traceFreq[traceCount] = currentFreq
    traceAmp[traceCount] = amp[1]
    traceDurRel[traceCount] = dur[1]/meanSeg
    traceDurRelMax = max(traceDurRelMax,traceDurRel[traceCount])

    if midCaptured = 0 and genT >= 0.5*duration_s
        for bp from 1 to number_of_breakpoints
            ampMid[bp] = amp[bp]
            durMid[bp] = dur[bp]
        endfor
        midCaptured = 1
    endif

    # Always keep the last actually-rendered polygon.
    for bp from 1 to number_of_breakpoints
        ampFinal[bp] = amp[bp]
        durFinal[bp] = dur[bp]
    endfor

    pitchMinRealized = min(pitchMinRealized,currentFreq)
    pitchMaxRealized = max(pitchMaxRealized,currentFreq)

    @refreshMats: amMat,cmMat,1
    selectObject: outputSound
    Formula (part): genT,min(genT+genP,duration_s),1,1,gendynF1$

    # ---- SECOND-ORDER AMPLITUDE WALKS -------------------------------
    for bp from 1 to number_of_breakpoints
        @getRandomStep: ampAccelStep
        newVel = ampVelocity[bp]+getRandomStep.result
        @reflectBarrier: newVel,-amplitude_step,amplitude_step
        ampVelocity[bp] = reflectBarrier.result

        newAmp = amp[bp]+ampVelocity[bp]
        @reflectBarrier: newAmp,-amplitude_barrier,amplitude_barrier
        amp[bp] = reflectBarrier.result
    endfor

    # ---- SECOND-ORDER DURATION-SPACING WALKS ------------------------
    totalDur = 0
    for bp from 1 to number_of_breakpoints
        @getRandomStep: durAccelStep
        newDurVel = durVelocity[bp]+getRandomStep.result
        @reflectBarrier: newDurVel,-duration_step,duration_step
        durVelocity[bp] = reflectBarrier.result

        # Velocity is in units of one mean segment per generation.
        newDur = dur[bp]+meanSeg*durVelocity[bp]
        @reflectBarrier: newDur,minSeg,maxSeg
        dur[bp] = reflectBarrier.result
        totalDur = totalDur+dur[bp]
    endfor

    for bp from 1 to number_of_breakpoints
        dur[bp] = dur[bp]/totalDur
    endfor

    # ---- CONTROLLABLE BOUNDED PITCH WALK ----------------------------
    if effectiveMaxFreq > effectiveMinFreq and pitchStep > 0
        @getRandomStep: pitchStep
        currentFreq = currentFreq*(1+getRandomStep.result)
        @reflectBarrier: currentFreq,effectiveMinFreq,effectiveMaxFreq
        currentFreq = reflectBarrier.result
    else
        currentFreq = effectiveMinFreq
    endif

    genT = genT+genP

    percentDone = round(100*genT/duration_s)
    if percentDone >= lastReportPercent+20
        appendInfoLine: "  ", min(percentDone,100), "% | Gen: ", generation,
            ... " | Freq: ", fixed$(currentFreq,0), " Hz"
        lastReportPercent = percentDone
    endif
endwhile

if midCaptured = 0
    for bp from 1 to number_of_breakpoints
        ampMid[bp] = ampFinal[bp]
        durMid[bp] = durFinal[bp]
    endfor
endif

# ---------------------------------------------------------------------------
# 6. SYNTHESIZE INDEPENDENT VOICE 2
# ---------------------------------------------------------------------------
if spatial_mode >= 2
    appendInfoLine: "Synthesizing dynamic stochastic voice 2..."

    genT2 = 0
    generation2 = 0

    while genT2 < duration_s
        generation2 = generation2+1
        genP2 = 1/currentFreq2

        @refreshMats: amMat2,cmMat2,2
        selectObject: outputSound2
        Formula (part): genT2,min(genT2+genP2,duration_s),1,1,gendynF2$

        for bp from 1 to number_of_breakpoints
            @getRandomStep: ampAccelStep
            newVel2 = ampVelocity2[bp]+getRandomStep.result
            @reflectBarrier: newVel2,-amplitude_step,amplitude_step
            ampVelocity2[bp] = reflectBarrier.result

            newAmp2 = amp2[bp]+ampVelocity2[bp]
            @reflectBarrier: newAmp2,-amplitude_barrier,amplitude_barrier
            amp2[bp] = reflectBarrier.result
        endfor

        totalDur2 = 0
        for bp from 1 to number_of_breakpoints
            @getRandomStep: durAccelStep
            newDurVel2 = durVelocity2[bp]+getRandomStep.result
            @reflectBarrier: newDurVel2,-duration_step,duration_step
            durVelocity2[bp] = reflectBarrier.result

            newDur2 = dur2[bp]+meanSeg*durVelocity2[bp]
            @reflectBarrier: newDur2,minSeg,maxSeg
            dur2[bp] = reflectBarrier.result
            totalDur2 = totalDur2+dur2[bp]
        endfor

        for bp from 1 to number_of_breakpoints
            dur2[bp] = dur2[bp]/totalDur2
        endfor

        if effectiveMaxFreq > effectiveMinFreq and pitchStep > 0
            @getRandomStep: pitchStep
            currentFreq2 = currentFreq2*(1+getRandomStep.result)
            @reflectBarrier: currentFreq2,effectiveMinFreq,effectiveMaxFreq
            currentFreq2 = reflectBarrier.result
        else
            currentFreq2 = effectiveMinFreq
        endif

        genT2 = genT2+genP2
    endwhile
endif

appendInfoLine: ""
appendInfoLine: "Voice-1 generations: ", generation
if spatial_mode >= 2
    appendInfoLine: "Voice-2 generations: ", generation2
endif

removeObject: amMat,cmMat
if spatial_mode >= 2
    removeObject: amMat2,cmMat2
endif

# ---------------------------------------------------------------------------
# 7. SPATIAL OUTPUT
# ---------------------------------------------------------------------------
if spatial_mode = 1
    selectObject: outputSound
    Rename: "gendyn_" + replace$(preset_name$," ","_",0)

elsif spatial_mode = 2
    selectObject: outputSound
    plusObject: outputSound2
    Combine to stereo
    stereoSound = selected("Sound")
    Rename: "gendyn_" + replace$(preset_name$," ","_",0)

    removeObject: outputSound,outputSound2
    outputSound = stereoSound

else
    # Two independent voices rotate in opposite directions. For uncorrelated
    # voices, the equal-power gains preserve approximately constant total power.
    v1$ = string$(outputSound)
    v2$ = string$(outputSound2)
    pan$ = "(0.5+0.46*sin(2*pi*0.08*x))"

    leftRot = Create Sound from formula:
        ... "gendyn_rotL_" + uid$,1,0,duration_s,sample_rate_Hz,
        ... "(sqrt(1-" + pan$ + ")*object[" + v1$ + ",1,col]"
        ... + "+sqrt(" + pan$ + ")*object[" + v2$ + ",1,col])/sqrt(2)"

    rightRot = Create Sound from formula:
        ... "gendyn_rotR_" + uid$,1,0,duration_s,sample_rate_Hz,
        ... "(sqrt(" + pan$ + ")*object[" + v1$ + ",1,col]"
        ... + "+sqrt(1-" + pan$ + ")*object[" + v2$ + ",1,col])/sqrt(2)"

    selectObject: leftRot
    plusObject: rightRot
    Combine to stereo
    stereoSound = selected("Sound")
    Rename: "gendyn_" + replace$(preset_name$," ","_",0)

    removeObject: outputSound,outputSound2,leftRot,rightRot
    outputSound = stereoSound
endif

# ---------------------------------------------------------------------------
# 8. EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.20*duration_s)
if actualFade > 0
    fadeOutStart = duration_s-actualFade
    selectObject: outputSound
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

selectObject: outputSound
preNormPeak = Get absolute extremum: 0,0,"None"
preNormRMS = Get root-mean-square: 0,0

if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels
processingTime = stopwatch-startTime

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 9. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# 10. PLAY / FINAL INFO
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Realized voice-1 pitch: ",
    ... fixed$(pitchMinRealized,1), "-", fixed$(pitchMaxRealized,1), " Hz"
appendInfoLine: "Processing time: ", fixed$(processingTime,2), " s"
appendInfoLine: "Pre-normalization peak/RMS: ",
    ... fixed$(preNormPeak,4), " / ", fixed$(preNormRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# PROCEDURE: random step distribution
# ===========================================================================
procedure getRandomStep: .maxStep
    if .maxStep <= 0
        .result = 0

    elsif distribution_type = 1
        .result = randomUniform(-.maxStep,.maxStep)

    elsif distribution_type = 2
        # Truncated Cauchy increment.
        .u = randomUniform(0.01,0.99)
        .raw = tan(pi*(.u-0.5))/5
        .raw = max(-2,min(2,.raw))
        .result = .maxStep*.raw

    elsif distribution_type = 3
        # AudioTools extension.
        .result = randomGauss(0,.maxStep*0.5)
        .result = max(-2*.maxStep,min(2*.maxStep,.result))

    else
        # Truncated logistic increment.
        .u = randomUniform(0.01,0.99)
        .raw = ln(.u/(1-.u))/5
        .raw = max(-2,min(2,.raw))
        .result = .maxStep*.raw
    endif
endproc


# ===========================================================================
# PROCEDURE: repeated reflecting barrier
# ===========================================================================
procedure reflectBarrier: .value,.min,.max
    if .max <= .min
        .result = .min
    else
        .result = .value
        .guard = 0

        while (.result < .min or .result > .max) and .guard < 20
            if .result < .min
                .result = 2*.min-.result
            elsif .result > .max
                .result = 2*.max-.result
            endif
            .guard = .guard+1
        endwhile

        # Extreme custom values should never reach this after validation, but
        # retain a final safe clamp in case a distribution produces bad input.
        .result = max(.min,min(.max,.result))
    endif
endproc


# ===========================================================================
# PROCEDURE: refresh breakpoint matrices
# ===========================================================================
procedure refreshMats: .amId,.cmId,.which
    .cum = 0

    selectObject: .cmId
    Set value: 1,1,0

    for .bp from 1 to number_of_breakpoints
        if .which = 1
            .a = amp[.bp]
            .d = dur[.bp]
        else
            .a = amp2[.bp]
            .d = dur2[.bp]
        endif

        selectObject: .amId
        Set value: 1,.bp,.a

        .cum = .cum+.d
        selectObject: .cmId

        if .bp < number_of_breakpoints
            Set value: 1,.bp+1,.cum
        else
            # Pin wrap boundary to exactly 1 to avoid a floating-point gap.
            Set value: 1,.bp+1,1
        endif
    endfor

    selectObject: .amId
    if .which = 1
        Set value: 1,number_of_breakpoints+1,amp[1]
    else
        Set value: 1,number_of_breakpoints+1,amp2[1]
    endif
endproc


# ===========================================================================
# PROCEDURE: build one period interpolation formula
# ===========================================================================
procedure buildGendynFormula: .amId,.cmId,.tVar$,.pVar$
    .ph$ = "min((x-" + .tVar$ + ")/" + .pVar$ + ",0.9999995)"
    .am$ = string$(.amId)
    .cm$ = string$(.cmId)
    .f$ = ""

    for .bp from 1 to number_of_breakpoints
        .b$ = string$(.bp)
        .b1$ = string$(.bp+1)

        .lerp$ = "object[" + .am$ + ",1," + .b$ + "]"
            ... + "+(object[" + .am$ + ",1," + .b1$ + "]-object["
            ... + .am$ + ",1," + .b$ + "])*(" + .ph$ + "-object["
            ... + .cm$ + ",1," + .b$ + "])/(object[" + .cm$ + ",1,"
            ... + .b1$ + "]-object[" + .cm$ + ",1," + .b$ + "]+1e-12)"

        if .bp < number_of_breakpoints
            .f$ = .f$ + "if " + .ph$ + "<object[" + .cm$ + ",1,"
                ... + .b1$ + "] then " + .lerp$ + " else "
        else
            .f$ = .f$+.lerp$
        endif
    endfor

    for .bp from 1 to number_of_breakpoints-1
        .f$ = .f$+" fi"
    endfor

    buildGendynFormula.result$ = .f$
endproc


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.76,0.38,0.18}"
    .green$ = "{0.25,0.58,0.38}"
    .purple$ = "{0.52,0.30,0.62}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "GENDYN FAMILY DYNAMIC STOCHASTIC SYNTHESIS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... string$(number_of_breakpoints) + " breakpoints | " + distribution$
        ... + " | second-order walks | pitch "
        ... + fixed$(effectiveMinFreq,0) + "-" + fixed$(effectiveMaxFreq,0) + " Hz"
    Text: 0.5,"centre",0.20,"half",
        ... "random acceleration -> walk velocity -> breakpoint amplitude/time -> polygon period -> audio"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL POLYGON EVOLUTION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.75,0.94
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  BREAKPOINT POLYGON | actual start, midpoint and final rendered cycle shapes"

    # Dedicated legend strip keeps annotation clear of both title and data.
    Select inner viewport: .left,.right,0.96,1.07
    Axes: 0,1,0,1
    Font size: 5
    Colour: "{0.30,0.30,0.32}"
    Text: 0.01,"left",0.50,"half","start blue | midpoint green | final orange"

    .ampY = 1.08*amplitude_barrier
    Select inner viewport: .left,.right,1.10,1.96
    Axes: 0,1,-.ampY,.ampY
    Paint rectangle: .bg$,0,1,-.ampY,.ampY

    Colour: .grid$
    Dotted line
    Draw line: 0,0,1,0
    Plain line

    # Start polygon.
    .cum0 = 0
    Colour: .blue$
    Line width: 1.0
    for .bp from 1 to number_of_breakpoints
        .x0 = .cum0
        .cum0 = .cum0+durStart[.bp]
        if .bp < number_of_breakpoints
            .a1 = ampStart[.bp+1]
        else
            .a1 = ampStart[1]
        endif
        Draw line: .x0,ampStart[.bp],.cum0,.a1
    endfor

    # Mid polygon.
    .cum0 = 0
    Colour: .green$
    Line width: 1.2
    for .bp from 1 to number_of_breakpoints
        .x0 = .cum0
        .cum0 = .cum0+durMid[.bp]
        if .bp < number_of_breakpoints
            .a1 = ampMid[.bp+1]
        else
            .a1 = ampMid[1]
        endif
        Draw line: .x0,ampMid[.bp],.cum0,.a1
    endfor

    # Final polygon.
    .cum0 = 0
    Colour: .orange$
    Line width: 1.5
    for .bp from 1 to number_of_breakpoints
        .x0 = .cum0
        .cum0 = .cum0+durFinal[.bp]
        if .bp < number_of_breakpoints
            .a1 = ampFinal[.bp+1]
        else
            .a1 = ampFinal[1]
        endif
        Draw line: .x0,ampFinal[.bp],.cum0,.a1
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Amplitude"
    Text bottom: "yes","Normalized cycle phase"

    # -----------------------------------------------------------------------
    # PANEL B: SELECTED BREAKPOINT WALKS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.13,2.32
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  SELECTED BREAKPOINT WALK | second-order motion of breakpoint 1"

    .midX = 4.06

    # Independent subplot headers prevent collision with the shared B title.
    Select inner viewport: .left,3.92,2.36,2.49
    Axes: 0,1,0,1
    Font size: 5
    Colour: "{0.30,0.30,0.32}"
    Text: 0.5,"centre",0.48,"half","BP1 amplitude"

    Select inner viewport: 4.20,.right,2.36,2.49
    Axes: 0,1,0,1
    Font size: 5
    Colour: "{0.30,0.30,0.32}"
    Text: 0.5,"centre",0.48,"half","BP1 relative segment duration"

    # B-left amplitude walk.
    Select inner viewport: .left,3.92,2.53,3.30
    Axes: 0,duration_s,-.ampY,.ampY
    Paint rectangle: .bg$,0,duration_s,-.ampY,.ampY

    .traceStep = max(1,ceiling(traceCount/1000))
    Colour: .blue$
    Line width: 1.1
    .havePrev = 0
    for .k from 1 to traceCount
        if ((.k-1) mod .traceStep)=0
            if .havePrev
                Draw line: .px,.py,traceTime[.k],traceAmp[.k]
            endif
            .px = traceTime[.k]
            .py = traceAmp[.k]
            .havePrev = 1
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 4,"yes","yes","no"
    Font size: 5
    Text left: "yes","BP1 amp"

    # B-right relative duration walk.
    .durY = max(1.25,1.08*traceDurRelMax)
    Select inner viewport: 4.20,.right,2.53,3.30
    Axes: 0,duration_s,0,.durY
    Paint rectangle: .bg$,0,duration_s,0,.durY

    Colour: .orange$
    Line width: 1.1
    .havePrev = 0
    for .k from 1 to traceCount
        if ((.k-1) mod .traceStep)=0
            if .havePrev
                Draw line: .px,.py,traceTime[.k],traceDurRel[.k]
            endif
            .px = traceTime[.k]
            .py = traceDurRel[.k]
            .havePrev = 1
        endif
    endfor
    Colour: .grid$
    Dotted line
    Draw line: 0,1,duration_s,1
    Plain line
    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 4,"yes","yes","no"
    Font size: 5
    Text left: "yes","BP1 dur / mean"

    # -----------------------------------------------------------------------
    # PANEL C: ACTUAL PITCH WALK
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.50,3.70
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  CONTROLLED PITCH WALK | actual cycle frequency vs active reflecting barriers"

    .pitchLo = max(1,0.92*effectiveMinFreq)
    .pitchHi = 1.08*effectiveMaxFreq

    Select inner viewport: .left,.right,3.78,4.61
    Axes: 0,duration_s,.pitchLo,.pitchHi
    Paint rectangle: .bg$,0,duration_s,.pitchLo,.pitchHi

    Colour: .grid$
    Dotted line
    Draw line: 0,effectiveMinFreq,duration_s,effectiveMinFreq
    Draw line: 0,effectiveMaxFreq,duration_s,effectiveMaxFreq
    Plain line

    Colour: .purple$
    Line width: 1.2
    .havePrev = 0
    for .k from 1 to traceCount
        if ((.k-1) mod .traceStep)=0
            if .havePrev
                Draw line: .px,.py,traceTime[.k],traceFreq[.k]
            endif
            .px = traceTime[.k]
            .py = traceFreq[.k]
            .havePrev = 1
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Cycle frequency (Hz)"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "gendyn_display_" + uid$
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
    # PANEL D: MODEL -> MEASURED AUDIO
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,4.79,4.99
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MODEL -> MEASUREMENT | measured spectrogram + actual voice-1 cycle frequency"

    .specMax = min(0.45*sample_rate_Hz,max(5000,4*effectiveMaxFreq))
    .specStep = max(0.002,duration_s/1200)

    selectObject: .disp
    To Spectrogram: 0.020,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,5.07,6.11
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: .purple$
    Line width: 0.9
    .havePrev = 0
    for .k from 1 to traceCount
        if ((.k-1) mod .traceStep)=0 and traceFreq[.k] <= .specMax
            if .havePrev
                Draw line: .px,.py,traceTime[.k],traceFreq[.k]
            endif
            .px = traceTime[.k]
            .py = traceFreq[.k]
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
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.64,7.88
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.80,"half",
        ... "DSS  |  second-order amp/time walks -> reflecting barriers -> normalized polygon -> period rendering"

    Text: 0.02,"left",0.58,"half",
        ... "MOTION  |  amp step " + fixed$(amplitude_step,2)
        ... + "  |  dur step " + fixed$(duration_step,2)
        ... + "  |  generations " + string$(generation)
        ... + "  |  " + seedLabel$

    if resolutionWarning
        .res$ = "resolution warning"
    else
        .res$ = "resolution OK"
    endif

    Text: 0.02,"left",0.36,"half",
        ... "PITCH QC  |  active " + fixed$(effectiveMinFreq,0) + "-"
        ... + fixed$(effectiveMaxFreq,0) + " Hz"
        ... + "  |  samples/BP at top " + fixed$(avgSamplesPerBreakpointAtTop,2)
        ... + "  |  " + .res$

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02,"left",0.14,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preNormPeak,3)
        ... + "  |  pre-RMS " + fixed$(preNormRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
