# ============================================================
# Praat AudioTools - FM Texture Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 runtime fix (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ACCURATE DESCRIPTION
#   Six-operator FM/PM-style texture generator.
#
#   The digital operator engine is implemented as PHASE MODULATION:
#
#       y_c(t) = A_c(t) * sin(2*pi*f_c*t + y_m(t))
#
#   For a sinusoidal modulator with fixed amplitude this has the familiar
#   Chowning-FM sideband structure, with the modulator amplitude acting as
#   modulation index in radians. Dynamic operator envelopes make this an
#   operator-PM implementation rather than literal integration of frequency.
#
#   This is closer to classic digital "DX-style FM" architecture than the
#   previous description implied, but the presets below do NOT claim to
#   reproduce factory patches or specific instruments.
#
# ROUTING ALGORITHMS
#   1. Parallel additive bank:
#          op1 + op2 + op3 + op4 + op5 + op6(feedback)
#
#   2. Series stack:
#          op6(feedback) -> op5 -> op4 -> op3 -> op2 -> op1 -> OUT
#
#   3. Dual stack:
#          op6(feedback) -> op5 -> op4 --\
#                                         +--> OUT
#          op3           -> op2 -> op1 --/
#
# OPERATOR LEVEL SEMANTICS
#   - Carrier operator level = output amplitude.
#   - Modulator operator level = phase-modulation index (radians).
#   - Brightness scales modulator indices in Series/Dual algorithms.
#   - In Parallel mode Brightness tilts upper-partial operator gains.
#
# v0.4.1 runtime fix:
#   - Removed the silent 300-event truncation in Random Bursts.
#   - The Poisson burst field now runs for the complete requested duration.
#   - Added a high explicit 5000-event runaway guard that exits with a message
#     instead of silently dropping the remainder of the stochastic envelope.
#
# v0.4 reviewed:
#   - Reframed the engine accurately as six-operator PM/FM-style synthesis.
#   - Replaced the old analytic "feedback" approximation
#         sin(phi + fb*sin(phi))
#     with genuine one-sample recursive phase feedback in Op6:
#         y[n] = A[n] sin(phi[n] + fb*y[n-1])
#   - Rebuilt routing with explicit operator Sounds and object-ID modulation.
#     Disabled operators no longer silently bypass an upstream operator.
#   - Dual Stack now genuinely uses all six operators: 6->5->4 + 3->2->1.
#   - Master_Volume is no longer cancelled by note-level + final peak scaling.
#     One optional DOWN-ONLY peak-protection stage remains at the end.
#   - Melody demo is now transposed from Base_frequency and its durations scale
#     with Duration_s instead of ignoring both user controls.
#   - Random Bursts is now a seeded Poisson field of short Hann amplitude
#     windows rather than per-sample random gating.
#   - Added Random_seed and practical operator-frequency / aliasing QC.
#   - Global ADSR, Swell and edge timing are short-duration safe.
#   - Compact laptop-safe main form; advanced operator controls are split into
#     three small wizard pages.
#   - Presets renamed to mechanism-faithful timbral descriptions rather than
#     claiming exact DX7 factory patches or acoustic instruments.
#   - Visualization rebuilt:
#       A actual routing diagram with carrier/modulator roles
#       B actual effective operator-level envelopes for a representative note
#       C measured spectrogram + nominal carrier-frequency guides
#       D measured output spectrum
#       routing / bandwidth / level QC
# ============================================================

form FM PM Operator Texture v0.4.1
    boolean Melody_demo 0

    optionmenu Preset 1
        option Bright Dual-Stack Keys
        option Feedback Bass Stack
        option Metallic Dual Stack
        option Parallel Organ Spectrum
        option Detuned Parallel Pad
        option Simple Series Test

    positive Base_frequency_Hz 110.0
    positive Brightness 1.0
    positive Decay_scale 1.0

    optionmenu Global_envelope 1
        option No Envelope
        option Percussive
        option Slow Fade
        option Gate
        option Reverse
        option Tremolo
        option Swell
        option ADSR
        option Stutter
        option Random Bursts

    positive Duration_s 2.0
    positive Master_volume 0.8

    boolean Edit_operator_details 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

sampling_frequency = 44100
safeTop = 0.45*sampling_frequency
twoPi = 2*pi

# ---------------------------------------------------------------------------
# 0. BASE OPERATOR DEFAULTS
# ---------------------------------------------------------------------------
algorithm = 3

op1_freq = 1.0
op1_level = 0.80
op1_envelope$ = "decay"

op2_freq = 1.0
op2_level = 1.50
op2_envelope$ = "decay"

op3_freq = 14.0
op3_level = 2.80
op3_envelope$ = "snap"

op4_freq = 1.0
op4_level = 0.55
op4_envelope$ = "decay"

op5_freq = 1.0
op5_level = 1.00
op5_envelope$ = "decay"

op6_freq = 14.0
op6_level = 2.20
op6_feedback = 0.30
op6_envelope$ = "snap"

snap_decay_time = 0.10
tone_decay_time = 0.80
random_seed = 0

preset_name$ = "Bright Dual-Stack Keys"

# ---------------------------------------------------------------------------
# 1. PRESETS
# ---------------------------------------------------------------------------
if preset = 1
    algorithm = 3

    op1_freq = 1.0
    op1_level = 0.80
    op1_envelope$ = "decay"
    op2_freq = 1.0
    op2_level = 1.50
    op2_envelope$ = "decay"
    op3_freq = 14.0
    op3_level = 2.80
    op3_envelope$ = "snap"

    op4_freq = 1.0
    op4_level = 0.55
    op4_envelope$ = "decay"
    op5_freq = 1.0
    op5_level = 1.00
    op5_envelope$ = "decay"
    op6_freq = 14.0
    op6_level = 2.20
    op6_feedback = 0.30
    op6_envelope$ = "snap"

    snap_decay_time = 0.10
    tone_decay_time = 0.85
    preset_name$ = "Bright Dual-Stack Keys"

elsif preset = 2
    algorithm = 2

    op1_freq = 1.0
    op1_level = 0.90
    op1_envelope$ = "decay"
    op2_freq = 1.0
    op2_level = 1.40
    op2_envelope$ = "decay"
    op3_freq = 2.0
    op3_level = 2.20
    op3_envelope$ = "snap"
    op4_freq = 1.0
    op4_level = 0.90
    op4_envelope$ = "decay"
    op5_freq = 0.5
    op5_level = 0.70
    op5_envelope$ = "sus"
    op6_freq = 1.0
    op6_level = 0.80
    op6_feedback = 2.20
    op6_envelope$ = "sus"

    snap_decay_time = 0.055
    tone_decay_time = 0.55
    preset_name$ = "Feedback Bass Stack"

elsif preset = 3
    algorithm = 3

    op1_freq = 1.0
    op1_level = 0.70
    op1_envelope$ = "decay"
    op2_freq = 3.5
    op2_level = 1.80
    op2_envelope$ = "decay"
    op3_freq = 10.0
    op3_level = 1.30
    op3_envelope$ = "snap"

    op4_freq = 1.01
    op4_level = 0.55
    op4_envelope$ = "decay"
    op5_freq = 2.75
    op5_level = 1.50
    op5_envelope$ = "decay"
    op6_freq = 13.0
    op6_level = 1.00
    op6_feedback = 0.45
    op6_envelope$ = "snap"

    snap_decay_time = 0.18
    tone_decay_time = 1.40
    preset_name$ = "Metallic Dual Stack"

elsif preset = 4
    algorithm = 1

    op1_freq = 0.5
    op1_level = 0.75
    op1_envelope$ = "sus"
    op2_freq = 1.0
    op2_level = 1.00
    op2_envelope$ = "sus"
    op3_freq = 2.0
    op3_level = 0.68
    op3_envelope$ = "sus"
    op4_freq = 3.0
    op4_level = 0.48
    op4_envelope$ = "sus"
    op5_freq = 4.0
    op5_level = 0.30
    op5_envelope$ = "sus"
    op6_freq = 8.0
    op6_level = 0.18
    op6_feedback = 0.0
    op6_envelope$ = "sus"

    tone_decay_time = 1.0
    preset_name$ = "Parallel Organ Spectrum"

elsif preset = 5
    algorithm = 1

    op1_freq = 1.000
    op1_level = 0.60
    op1_envelope$ = "slow"
    op2_freq = 1.008
    op2_level = 0.55
    op2_envelope$ = "slow"
    op3_freq = 2.000
    op3_level = 0.30
    op3_envelope$ = "slow"
    op4_freq = 2.013
    op4_level = 0.28
    op4_envelope$ = "slow"
    op5_freq = 3.000
    op5_level = 0.15
    op5_envelope$ = "slow"
    op6_freq = 0.500
    op6_level = 0.18
    op6_feedback = 0.0
    op6_envelope$ = "slow"

    tone_decay_time = 1.50
    preset_name$ = "Detuned Parallel Pad"

else
    algorithm = 2

    op1_freq = 1.0
    op1_level = 0.90
    op1_envelope$ = "sus"
    op2_freq = 1.0
    op2_level = 1.60
    op2_envelope$ = "decay"
    op3_freq = 2.0
    op3_level = 2.20
    op3_envelope$ = "decay"
    op4_freq = 1.0
    op4_level = 0.0
    op4_envelope$ = "decay"
    op5_freq = 1.0
    op5_level = 0.0
    op5_envelope$ = "decay"
    op6_freq = 1.0
    op6_level = 0.0
    op6_feedback = 0.0
    op6_envelope$ = "sus"

    snap_decay_time = 0.10
    tone_decay_time = 0.80
    preset_name$ = "Simple Series Test"
endif

# ---------------------------------------------------------------------------
# 2. OPTIONAL COMPACT ADVANCED WIZARD
# ---------------------------------------------------------------------------
# Convert envelope strings to menu indices so each page opens on the
# currently selected preset values.
op1_env_choice = 1
op2_env_choice = 1
op3_env_choice = 1
op4_env_choice = 1
op5_env_choice = 1
op6_env_choice = 1

if op1_envelope$ = "decay"
    op1_env_choice = 2
elsif op1_envelope$ = "sus"
    op1_env_choice = 3
elsif op1_envelope$ = "slow"
    op1_env_choice = 4
endif
if op2_envelope$ = "decay"
    op2_env_choice = 2
elsif op2_envelope$ = "sus"
    op2_env_choice = 3
elsif op2_envelope$ = "slow"
    op2_env_choice = 4
endif
if op3_envelope$ = "decay"
    op3_env_choice = 2
elsif op3_envelope$ = "sus"
    op3_env_choice = 3
elsif op3_envelope$ = "slow"
    op3_env_choice = 4
endif
if op4_envelope$ = "decay"
    op4_env_choice = 2
elsif op4_envelope$ = "sus"
    op4_env_choice = 3
elsif op4_envelope$ = "slow"
    op4_env_choice = 4
endif
if op5_envelope$ = "decay"
    op5_env_choice = 2
elsif op5_envelope$ = "sus"
    op5_env_choice = 3
elsif op5_envelope$ = "slow"
    op5_env_choice = 4
endif
if op6_envelope$ = "decay"
    op6_env_choice = 2
elsif op6_envelope$ = "sus"
    op6_env_choice = 3
elsif op6_envelope$ = "slow"
    op6_env_choice = 4
endif

if edit_operator_details
    beginPause: "FM PM Operator Texture - Routing and Ops 1-2 (1/3)"
        optionmenu: "Algorithm", algorithm
            option: "Parallel additive bank"
            option: "Series 6->5->4->3->2->1"
            option: "Dual 6->5->4 + 3->2->1"

        positive: "Op1 frequency ratio", op1_freq
        real: "Op1 level", op1_level
        optionmenu: "Op1 envelope", op1_env_choice
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"

        positive: "Op2 frequency ratio", op2_freq
        real: "Op2 level", op2_level
        optionmenu: "Op2 envelope", op2_env_choice
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"
    endPause: "Next", 1

    beginPause: "FM PM Operator Texture - Ops 3-4 (2/3)"
        positive: "Op3 frequency ratio", op3_freq
        real: "Op3 level", op3_level
        optionmenu: "Op3 envelope", op3_env_choice
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"

        positive: "Op4 frequency ratio", op4_freq
        real: "Op4 level", op4_level
        optionmenu: "Op4 envelope", op4_env_choice
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"
    endPause: "Next", 1

    beginPause: "FM PM Operator Texture - Ops 5-6 and Timing (3/3)"
        positive: "Op5 frequency ratio", op5_freq
        real: "Op5 level", op5_level
        optionmenu: "Op5 envelope", op5_env_choice
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"

        positive: "Op6 frequency ratio", op6_freq
        real: "Op6 level", op6_level
        real: "Op6 feedback", op6_feedback
        optionmenu: "Op6 envelope", op6_env_choice
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"

        positive: "Snap decay time (s)", snap_decay_time
        positive: "Tone decay time (s)", tone_decay_time
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1

    if op1_env_choice = 1
        op1_envelope$ = "snap"
    elsif op1_env_choice = 2
        op1_envelope$ = "decay"
    elsif op1_env_choice = 3
        op1_envelope$ = "sus"
    else
        op1_envelope$ = "slow"
    endif

    if op2_env_choice = 1
        op2_envelope$ = "snap"
    elsif op2_env_choice = 2
        op2_envelope$ = "decay"
    elsif op2_env_choice = 3
        op2_envelope$ = "sus"
    else
        op2_envelope$ = "slow"
    endif

    if op3_env_choice = 1
        op3_envelope$ = "snap"
    elsif op3_env_choice = 2
        op3_envelope$ = "decay"
    elsif op3_env_choice = 3
        op3_envelope$ = "sus"
    else
        op3_envelope$ = "slow"
    endif

    if op4_env_choice = 1
        op4_envelope$ = "snap"
    elsif op4_env_choice = 2
        op4_envelope$ = "decay"
    elsif op4_env_choice = 3
        op4_envelope$ = "sus"
    else
        op4_envelope$ = "slow"
    endif

    if op5_env_choice = 1
        op5_envelope$ = "snap"
    elsif op5_env_choice = 2
        op5_envelope$ = "decay"
    elsif op5_env_choice = 3
        op5_envelope$ = "sus"
    else
        op5_envelope$ = "slow"
    endif

    if op6_env_choice = 1
        op6_envelope$ = "snap"
    elsif op6_env_choice = 2
        op6_envelope$ = "decay"
    elsif op6_env_choice = 3
        op6_envelope$ = "sus"
    else
        op6_envelope$ = "slow"
    endif
endif

# ---------------------------------------------------------------------------
# 3. VALIDATION / EFFECTIVE LEVELS
# ---------------------------------------------------------------------------
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if brightness <= 0 or brightness > 4
    exitScript: "Brightness must be > 0 and <= 4."
endif
if decay_scale <= 0 or decay_scale > 10
    exitScript: "Decay scale must be > 0 and <= 10."
endif
if duration_s <= 0 or duration_s > 60
    exitScript: "Duration must be > 0 and <= 60 seconds."
endif
if master_volume <= 0 or master_volume > 2
    exitScript: "Master volume must be > 0 and <= 2."
endif
if algorithm < 1 or algorithm > 3
    exitScript: "Algorithm must be 1, 2 or 3."
endif
if op6_feedback < 0 or op6_feedback > 4
    exitScript: "Op6 feedback must be between 0 and 4."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

if op1_level < 0 or op2_level < 0 or op3_level < 0 or
    ... op4_level < 0 or op5_level < 0 or op6_level < 0
    exitScript: "Operator levels cannot be negative."
endif
if op1_level > 10 or op2_level > 10 or op3_level > 10 or
    ... op4_level > 10 or op5_level > 10 or op6_level > 10
    exitScript: "Operator levels are limited to 10."
endif

maxRatio = max(op1_freq,op2_freq,op3_freq,op4_freq,op5_freq,op6_freq)

# Melody demo reaches 2x the selected root.
if melody_demo
    maxFundamental = 2*base_frequency_Hz
else
    maxFundamental = base_frequency_Hz
endif

if maxRatio*maxFundamental > safeTop
    exitScript: "Highest operator fundamental exceeds practical Nyquist headroom. Reduce Base frequency or operator ratios."
endif

# Effective levels used by both synthesis and visualization.
if algorithm = 1
    eff1 = op1_level
    eff2 = op2_level*sqrt(brightness)
    eff3 = op3_level*brightness
    eff4 = op4_level*brightness
    eff5 = op5_level*brightness
    eff6 = op6_level*brightness

elsif algorithm = 2
    eff1 = op1_level
    eff2 = op2_level*brightness
    eff3 = op3_level*brightness
    eff4 = op4_level*brightness
    eff5 = op5_level*brightness
    eff6 = op6_level*brightness

else
    # Carriers are 1 and 4; 2/3 and 5/6 are modulators.
    eff1 = op1_level
    eff2 = op2_level*brightness
    eff3 = op3_level*brightness
    eff4 = op4_level
    eff5 = op5_level*brightness
    eff6 = op6_level*brightness
endif

maxEffectiveIndex = max(eff2,eff3,eff5,eff6,eff6*op6_feedback)
practicalTopEstimate = maxFundamental*maxRatio*(1+maxEffectiveIndex)
aliasWarning = practicalTopEstimate > safeTop

if algorithm = 1
    algorithm$ = "Parallel additive bank"
elsif algorithm = 2
    algorithm$ = "Series 6->5->4->3->2->1"
else
    algorithm$ = "Dual 6->5->4 + 3->2->1"
endif

if global_envelope = 1
    globalEnvelope$ = "None"
elsif global_envelope = 2
    globalEnvelope$ = "Percussive"
elsif global_envelope = 3
    globalEnvelope$ = "Slow Fade"
elsif global_envelope = 4
    globalEnvelope$ = "Gate"
elsif global_envelope = 5
    globalEnvelope$ = "Reverse"
elsif global_envelope = 6
    globalEnvelope$ = "Tremolo"
elsif global_envelope = 7
    globalEnvelope$ = "Swell"
elsif global_envelope = 8
    globalEnvelope$ = "ADSR"
elsif global_envelope = 9
    globalEnvelope$ = "Stutter"
else
    globalEnvelope$ = "Random Bursts"
endif

# Count active operators.
activeOps = 0
if eff1 > 0
    activeOps = activeOps+1
endif
if eff2 > 0
    activeOps = activeOps+1
endif
if eff3 > 0
    activeOps = activeOps+1
endif
if eff4 > 0
    activeOps = activeOps+1
endif
if eff5 > 0
    activeOps = activeOps+1
endif
if eff6 > 0
    activeOps = activeOps+1
endif

# ---------------------------------------------------------------------------
# 4. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  FM / PM OPERATOR TEXTURE v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Algorithm: ", algorithm$
appendInfoLine: "Base frequency: ", fixed$(base_frequency_Hz,2), " Hz"
appendInfoLine: "Brightness: ", fixed$(brightness,2)
appendInfoLine: "Decay scale: ", fixed$(decay_scale,2)
appendInfoLine: "Global envelope: ", globalEnvelope$
appendInfoLine: "Active operators: ", activeOps, "/6"
appendInfoLine: "Practical spectral-top estimate: ",
    ... fixed$(practicalTopEstimate,0), " Hz"
if aliasWarning
    appendInfoLine: "QC WARNING: upper PM sidebands may exceed practical Nyquist headroom."
endif
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 5. NOTE / MELODY GENERATION
# ---------------------------------------------------------------------------
if melody_demo
    appendInfoLine: "Generating transposable 1-3-5-8-5-3-1-low5 demo..."

    demoScale = duration_s/2.0
    demoRatio# = {1, 1.25992105, 1.49830708, 2, 1.49830708, 1.25992105, 1, 0.74915354}
    demoDurBase# = {0.4,0.4,0.4,0.6,0.4,0.4,0.4,0.8}
    demoHz# = zero#(8)
    demoDur# = zero#(8)
    demoOnset# = zero#(8)

    for i from 1 to 8
        demoHz#[i] = base_frequency_Hz*demoRatio#[i]
        demoDur#[i] = demoDurBase#[i]*demoScale
    endfor

    demoOnset#[1] = 0
    for i from 2 to 8
        demoOnset#[i] = demoOnset#[i-1]+demoDur#[i-1]
    endfor

    for i from 1 to 8
        @makeFMNote: demoHz#[i],demoDur#[i]
        noteID[i] = selected("Sound")
    endfor

    selectObject: noteID[1]
    for i from 2 to 8
        plusObject: noteID[i]
    endfor
    Concatenate
    sound = selected("Sound")

    for i from 1 to 8
        removeObject: noteID[i]
    endfor

    selectObject: sound
    Rename: "fm_pm_" + replace$(preset_name$," ","_",0) + "_demo"

    representativeFreq = demoHz#[1]
    representativeDur = demoDur#[1]

else
    @makeFMNote: base_frequency_Hz,duration_s
    sound = selected("Sound")
    Rename: "fm_pm_" + replace$(preset_name$," ","_",0)

    representativeFreq = base_frequency_Hz
    representativeDur = duration_s
endif

# ---------------------------------------------------------------------------
# 6. MASTER LEVEL + GLOBAL AMPLITUDE SHAPE
# ---------------------------------------------------------------------------
selectObject: sound
Formula: "self*master_volume"
totalDur = Get total duration

if global_envelope = 2
    # Percussive.
    envRate = 5/decay_scale
    Formula: "self*exp(-x*envRate)"

elsif global_envelope = 3
    # Slow fade.
    envRate = 0.30/decay_scale
    Formula: "self*exp(-x*envRate)"

elsif global_envelope = 4
    # Periodic gate. Kept deliberately hard-edged as a rhythmic gate.
    gatePeriod = max(0.04,0.10/brightness)
    Formula: "self*if sin(twoPi*x/gatePeriod)>0 then 1 else 0 fi"

elsif global_envelope = 5
    # Reverse / crescendo.
    Formula: "self*(x/totalDur)"

elsif global_envelope = 6
    tremRate = 5+5*brightness
    tremDepth = min(0.95,max(0.05,0.30+0.15*(brightness-1)))
    Formula: "self*((1-tremDepth)+tremDepth*(0.5+0.5*sin(twoPi*tremRate*x)))"

elsif global_envelope = 7
    attackTime = min(totalDur,max(0.01,0.30*decay_scale))
    Formula: "self*min(1,x/attackTime)"

elsif global_envelope = 8
    attack = min(0.02,0.10*totalDur)
    decay = min(0.20*decay_scale,0.20*totalDur)
    sustain = min(0.90,max(0.25,0.50+0.10*brightness))
    releaseDur = min(0.30*decay_scale,0.25*totalDur)
    releaseStart = max(attack+decay,totalDur-releaseDur)
    actualRelease = max(1e-6,totalDur-releaseStart)

    adsr$ = "self*if x<attack then x/attack else if x<attack+decay then 1-(1-sustain)*((x-attack)/decay) else if x<releaseStart then sustain else sustain*max(0,(totalDur-x)/actualRelease) fi fi fi"
    Formula: adsr$

elsif global_envelope = 9
    # Intentional hard stutter.
    stutterRate = 10+10*brightness
    Formula: "self*if floor(x*stutterRate) mod 2=0 then 1 else 0 fi"

elsif global_envelope = 10
    # Seeded Poisson field of short Hann windows.
    if random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
        seededBursts = 1
    else
        seededBursts = 0
    endif

    burstDensity = 2+3*brightness
    burstGate = Create Sound from formula: "pm_burst_gate",1,0,totalDur,sampling_frequency,"0"

    burstTime = 0
    burstCount = 0
    maxBurstEvents = 5000
    while burstTime < totalDur
        u = max(1e-12,randomUniform(0,1))
        burstTime = burstTime-ln(u)/burstDensity

        if burstTime < totalDur
            burstCount = burstCount+1
            if burstCount > maxBurstEvents
                if seededBursts
                    random_initializeSafelyAndUnpredictably ()
                endif
                removeObject: burstGate
                exitScript: "Random Bursts exceeded 5000 events. Reduce Brightness or Duration."
            endif

            burstDur = randomUniform(0.035,0.11)
            burstEnd = min(totalDur,burstTime+burstDur)

            bt$ = fixed$(burstTime,9)
            bd$ = fixed$(max(1e-6,burstEnd-burstTime),9)

            selectObject: burstGate
            Formula (part): burstTime,burstEnd,1,1,
                ... "max(self,0.5*(1-cos(twoPi*(x-" + bt$ + ")/" + bd$ + ")))"
        endif
    endwhile

    if seededBursts
        random_initializeSafelyAndUnpredictably ()
    endif

    selectObject: sound
    gateID$ = string$(burstGate)
    Formula: "self*object[" + gateID$ + ",1,col]"
    removeObject: burstGate
endif

# Short edge protection independent of musical envelope.
edgeFade = min(0.006,0.08*totalDur)
if edgeFade > 0
    fadeOutStart = totalDur-edgeFade
    selectObject: sound
    Formula: "if x<edgeFade then self*(x/edgeFade) else if x>fadeOutStart then self*((totalDur-x)/edgeFade) else self fi fi"
endif

# ---------------------------------------------------------------------------
# 7. FINAL DOWN-ONLY PEAK PROTECTION / METRICS
# ---------------------------------------------------------------------------
selectObject: sound
preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.95
    Scale peak: 0.95
    protectionApplied = 1
endif

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalDuration = Get total duration

# ---------------------------------------------------------------------------
# 8. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# 9. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: sound
appendInfoLine: ""
appendInfoLine: "Pre-protection peak/RMS: ",
    ... fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Master volume: ", fixed$(master_volume,3)
appendInfoLine: "Peak protection applied: ", protectionApplied
appendInfoLine: "Duration: ", fixed$(finalDuration,3), " s"
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: sound


# ===========================================================================
# PROCEDURE: makeOperator
# Creates one operator Sound. Modulator output is used directly as radians
# in the phase of the downstream operator.
# ===========================================================================
procedure makeOperator: .ratio,.level,.env$,.fund,.dur,.modID,.feedback,.tag$

    .fs = 44100
    .fHz = .ratio*.fund

    # Short-note-safe operator envelopes.
    .snapDecay = max(0.001,snap_decay_time*decay_scale)
    .toneDecay = max(0.001,tone_decay_time*decay_scale)
    .attackFast = min(0.010,0.12*.dur)
    .attackSnap = min(0.002,0.06*.dur)
    .slowAttack = min(0.50*decay_scale,0.60*.dur)
    .slowAttack = max(0.001,.slowAttack)

    if .env$ = "snap"
        .a$ = fixed$(.attackSnap,9)
        .d$ = fixed$(.snapDecay,9)
        .envExpr$ = "(if x<" + .a$ + " then x/" + .a$
            ... + " else exp(-(x-" + .a$ + ")/" + .d$ + ") fi)"

    elsif .env$ = "decay"
        .a$ = fixed$(.attackFast,9)
        .d$ = fixed$(.toneDecay,9)
        .envExpr$ = "(if x<" + .a$ + " then x/" + .a$
            ... + " else exp(-(x-" + .a$ + ")/" + .d$ + ") fi)"

    elsif .env$ = "slow"
        .a$ = fixed$(.slowAttack,9)
        .envExpr$ = "(if x<" + .a$ + " then x/" + .a$ + " else 1 fi)"

    else
        .a$ = fixed$(.attackFast,9)
        .envExpr$ = "(if x<" + .a$
            ... + " then x/" + .a$
            ... + " else 0.1*exp(-(x-" + .a$ + ")/0.5)+0.9 fi)"
    endif

    Create Sound from formula: "pm_" + .tag$,1,0,.dur,.fs,"0"
    .id = selected("Sound")

    .f$ = fixed$(.fHz,9)
    .l$ = fixed$(.level,9)

    if .level <= 0
        Formula: "0"

    elsif .feedback > 0 and .modID = 0
        # True one-sample recursive phase feedback.
        .fb$ = fixed$(.feedback,9)
        .formula$ = "if col=1 then " + .l$ + "*" + .envExpr$
            ... + "*sin(2*pi*" + .f$ + "*x)"
            ... + " else " + .l$ + "*" + .envExpr$
            ... + "*sin(2*pi*" + .f$ + "*x+" + .fb$ + "*self[col-1]) fi"
        Formula: .formula$

    elsif .modID > 0
        .mid$ = string$(.modID)
        .formula$ = .l$ + "*" + .envExpr$ + "*sin(2*pi*" + .f$ +
            ... "*x+object[" + .mid$ + ",1,col])"
        Formula: .formula$

    else
        .formula$ = .l$ + "*" + .envExpr$ + "*sin(2*pi*" + .f$ + "*x)"
        Formula: .formula$
    endif

    .result = .id
endproc


# ===========================================================================
# PROCEDURE: makeFMNote
# ===========================================================================
procedure makeFMNote: .freq,.dur

    if algorithm = 1
        @makeOperator: op1_freq,eff1,op1_envelope$,.freq,.dur,0,0,"op1"
        .o1 = makeOperator.result
        @makeOperator: op2_freq,eff2,op2_envelope$,.freq,.dur,0,0,"op2"
        .o2 = makeOperator.result
        @makeOperator: op3_freq,eff3,op3_envelope$,.freq,.dur,0,0,"op3"
        .o3 = makeOperator.result
        @makeOperator: op4_freq,eff4,op4_envelope$,.freq,.dur,0,0,"op4"
        .o4 = makeOperator.result
        @makeOperator: op5_freq,eff5,op5_envelope$,.freq,.dur,0,0,"op5"
        .o5 = makeOperator.result
        @makeOperator: op6_freq,eff6,op6_envelope$,.freq,.dur,0,op6_feedback,"op6"
        .o6 = makeOperator.result

        .parallelNorm = sqrt(max(1,activeOps))
        .norm$ = fixed$(.parallelNorm,9)

        .mix = Create Sound from formula: "pm_note",1,0,.dur,44100,
            ... "(object[" + string$(.o1) + ",1,col]+object[" + string$(.o2)
            ... + ",1,col]+object[" + string$(.o3) + ",1,col]+object[" + string$(.o4)
            ... + ",1,col]+object[" + string$(.o5) + ",1,col]+object[" + string$(.o6)
            ... + ",1,col])/" + .norm$

        removeObject: .o1,.o2,.o3,.o4,.o5,.o6

    elsif algorithm = 2
        @makeOperator: op6_freq,eff6,op6_envelope$,.freq,.dur,0,op6_feedback,"op6"
        .o6 = makeOperator.result
        @makeOperator: op5_freq,eff5,op5_envelope$,.freq,.dur,.o6,0,"op5"
        .o5 = makeOperator.result
        @makeOperator: op4_freq,eff4,op4_envelope$,.freq,.dur,.o5,0,"op4"
        .o4 = makeOperator.result
        @makeOperator: op3_freq,eff3,op3_envelope$,.freq,.dur,.o4,0,"op3"
        .o3 = makeOperator.result
        @makeOperator: op2_freq,eff2,op2_envelope$,.freq,.dur,.o3,0,"op2"
        .o2 = makeOperator.result
        @makeOperator: op1_freq,eff1,op1_envelope$,.freq,.dur,.o2,0,"op1"
        .o1 = makeOperator.result

        selectObject: .o1
        Copy: "pm_note"
        .mix = selected("Sound")

        removeObject: .o1,.o2,.o3,.o4,.o5,.o6

    else
        # Upper stack: 6 -> 5 -> 4
        @makeOperator: op6_freq,eff6,op6_envelope$,.freq,.dur,0,op6_feedback,"op6"
        .o6 = makeOperator.result
        @makeOperator: op5_freq,eff5,op5_envelope$,.freq,.dur,.o6,0,"op5"
        .o5 = makeOperator.result
        @makeOperator: op4_freq,eff4,op4_envelope$,.freq,.dur,.o5,0,"op4"
        .o4 = makeOperator.result

        # Lower stack: 3 -> 2 -> 1
        @makeOperator: op3_freq,eff3,op3_envelope$,.freq,.dur,0,0,"op3"
        .o3 = makeOperator.result
        @makeOperator: op2_freq,eff2,op2_envelope$,.freq,.dur,.o3,0,"op2"
        .o2 = makeOperator.result
        @makeOperator: op1_freq,eff1,op1_envelope$,.freq,.dur,.o2,0,"op1"
        .o1 = makeOperator.result

        .dualCount = 0
        if eff1 > 0
            .dualCount = .dualCount+1
        endif
        if eff4 > 0
            .dualCount = .dualCount+1
        endif
        .dualNorm = sqrt(max(1,.dualCount))
        .norm$ = fixed$(.dualNorm,9)

        .mix = Create Sound from formula: "pm_note",1,0,.dur,44100,
            ... "(object[" + string$(.o1) + ",1,col]+object[" + string$(.o4)
            ... + ",1,col])/" + .norm$

        removeObject: .o1,.o2,.o3,.o4,.o5,.o6
    endif

    # Short note-local edge fade only; no note peak normalization.
    selectObject: .mix
    .edge = min(0.005,0.08*.dur)
    if .edge > 0
        .fadeOut = .dur-.edge
        Formula: "if x<" + fixed$(.edge,9)
            ... + " then self*(x/" + fixed$(.edge,9)
            ... + ") else if x>" + fixed$(.fadeOut,9)
            ... + " then self*((" + fixed$(.dur,9)
            ... + "-x)/" + fixed$(.edge,9) + ") else self fi fi"
    endif

    selectObject: .mix
endproc


# ===========================================================================
# PROCEDURE: makeLevelEnvelope
# Creates the same effective operator level trajectory used by synthesis.
# ===========================================================================
procedure makeLevelEnvelope: .level,.env$,.dur,.tag$

    .snapDecay = max(0.001,snap_decay_time*decay_scale)
    .toneDecay = max(0.001,tone_decay_time*decay_scale)
    .attackFast = min(0.010,0.12*.dur)
    .attackSnap = min(0.002,0.06*.dur)
    .slowAttack = max(0.001,min(0.50*decay_scale,0.60*.dur))

    if .env$ = "snap"
        .a$ = fixed$(.attackSnap,9)
        .d$ = fixed$(.snapDecay,9)
        .expr$ = fixed$(.level,9) + "*(if x<" + .a$
            ... + " then x/" + .a$
            ... + " else exp(-(x-" + .a$ + ")/" + .d$ + ") fi)"

    elsif .env$ = "decay"
        .a$ = fixed$(.attackFast,9)
        .d$ = fixed$(.toneDecay,9)
        .expr$ = fixed$(.level,9) + "*(if x<" + .a$
            ... + " then x/" + .a$
            ... + " else exp(-(x-" + .a$ + ")/" + .d$ + ") fi)"

    elsif .env$ = "slow"
        .a$ = fixed$(.slowAttack,9)
        .expr$ = fixed$(.level,9) + "*(if x<" + .a$
            ... + " then x/" + .a$ + " else 1 fi)"

    else
        .a$ = fixed$(.attackFast,9)
        .expr$ = fixed$(.level,9) + "*(if x<" + .a$
            ... + " then x/" + .a$
            ... + " else 0.1*exp(-(x-" + .a$ + ")/0.5)+0.9 fi)"
    endif

    Create Sound from formula: "env_" + .tag$,1,0,.dur,400,.expr$
    .result = selected("Sound")
endproc


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    selectObject: sound
    .totalDur = Get total duration

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.76,0.38,0.18}"
    .green$ = "{0.25,0.58,0.38}"
    .purple$ = "{0.52,0.30,0.62}"
    .dark$ = "{0.18,0.18,0.20}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "FM / PM OPERATOR TEXTURE | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... algorithm$ + " | base " + fixed$(base_frequency_Hz,1)
        ... + " Hz | brightness " + fixed$(brightness,2)
        ... + " | " + globalEnvelope$
    Text: 0.5,"centre",0.20,"half",
        ... "operator envelope -> sinusoidal PM index -> routing network -> global amplitude stage -> measured output"

    # -----------------------------------------------------------------------
    # PANEL A: ROUTING DIAGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.76,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  OPERATOR ROUTING | C = carrier/output operator; M = phase modulator"

    Select inner viewport: .left,.right,1.05,2.12
    Axes: 0,1,0,1
    Paint rectangle: .bg$,0,1,0,1

    Font size: 6
    Colour: "{0.55,0.55,0.58}"

    if algorithm = 1
        # Six parallel carriers into output bus.
        for .i from 1 to 6
            .x = 0.08+(.i-1)*0.135
            Paint rectangle: "{0.91,0.94,0.98}",.x,.x+0.09,0.48,0.72
            Colour: .blue$
            Text: .x+0.045,"centre",0.63,"half","OP"+string$(.i)
            Colour: .dark$
            Text: .x+0.045,"centre",0.53,"half","C"
            Colour: "{0.55,0.55,0.58}"
            Draw rectangle: .x,.x+0.09,0.48,0.72
            Draw line: .x+0.045,0.48,.x+0.045,0.30
        endfor
        Draw line: 0.12,0.30,0.80,0.30
        Draw line: 0.80,0.30,0.90,0.30
        Colour: "Black"
        Text: 0.92,"centre",0.30,"half","OUT"

    elsif algorithm = 2
        # Series left-to-right: 6 -> 5 -> 4 -> 3 -> 2 -> 1.
        for .j from 1 to 6
            .op = 7-.j
            .x = 0.05+(.j-1)*0.145
            if .op = 1
                .fill$ = "{0.91,0.94,0.98}"
                .role$ = "C"
            else
                .fill$ = "{0.96,0.93,0.88}"
                .role$ = "M"
            endif
            Paint rectangle: .fill$,.x,.x+0.09,0.42,0.68
            Colour: .dark$
            Text: .x+0.045,"centre",0.59,"half","OP"+string$(.op)
            Text: .x+0.045,"centre",0.49,"half",.role$
            Colour: "{0.55,0.55,0.58}"
            Draw rectangle: .x,.x+0.09,0.42,0.68
            if .j < 6
                Draw line: .x+0.09,0.55,.x+0.145,0.55
            endif
        endfor
        Draw line: 0.05+5*0.145+0.09,0.55,0.94,0.55
        Colour: "Black"
        Text: 0.96,"centre",0.55,"half","OUT"

    else
        # Upper 6->5->4, lower 3->2->1.
        .opsTop# = {6,5,4}
        .opsBot# = {3,2,1}

        for .j from 1 to 3
            .x = 0.12+(.j-1)*0.18

            .op = .opsTop#[.j]
            if .op = 4
                .fill$ = "{0.91,0.94,0.98}"
                .role$ = "C"
            else
                .fill$ = "{0.96,0.93,0.88}"
                .role$ = "M"
            endif
            Paint rectangle: .fill$,.x,.x+0.10,0.62,0.84
            Colour: .dark$
            Text: .x+0.05,"centre",0.77,"half","OP"+string$(.op)
            Text: .x+0.05,"centre",0.68,"half",.role$
            Colour: "{0.55,0.55,0.58}"
            Draw rectangle: .x,.x+0.10,0.62,0.84
            if .j < 3
                Draw line: .x+0.10,0.73,.x+0.18,0.73
            endif

            .op = .opsBot#[.j]
            if .op = 1
                .fill$ = "{0.91,0.94,0.98}"
                .role$ = "C"
            else
                .fill$ = "{0.96,0.93,0.88}"
                .role$ = "M"
            endif
            Paint rectangle: .fill$,.x,.x+0.10,0.22,0.44
            Colour: .dark$
            Text: .x+0.05,"centre",0.37,"half","OP"+string$(.op)
            Text: .x+0.05,"centre",0.28,"half",.role$
            Colour: "{0.55,0.55,0.58}"
            Draw rectangle: .x,.x+0.10,0.22,0.44
            if .j < 3
                Draw line: .x+0.10,0.33,.x+0.18,0.33
            endif
        endfor

        Draw line: 0.58,0.73,0.74,0.73
        Draw line: 0.58,0.33,0.74,0.33
        Draw line: 0.74,0.33,0.74,0.73
        Draw line: 0.74,0.53,0.88,0.53

        Colour: "Black"
        Text: 0.91,"centre",0.53,"half","OUT"
    endif

    # Feedback annotation.
    if op6_feedback > 0
        Colour: .purple$
        Text: 0.08,"left",0.08,"half",
            ... "Op6 feedback = " + fixed$(op6_feedback,2)
            ... + " (one-sample recursive phase feedback)"
    endif

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL OPERATOR LEVEL ENVELOPES
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.28,2.50
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  EFFECTIVE OPERATOR LEVELS | representative note; modulators = PM index in radians"

    @makeLevelEnvelope: eff1,op1_envelope$,representativeDur,"1"
    .e1 = makeLevelEnvelope.result
    @makeLevelEnvelope: eff2,op2_envelope$,representativeDur,"2"
    .e2 = makeLevelEnvelope.result
    @makeLevelEnvelope: eff3,op3_envelope$,representativeDur,"3"
    .e3 = makeLevelEnvelope.result
    @makeLevelEnvelope: eff4,op4_envelope$,representativeDur,"4"
    .e4 = makeLevelEnvelope.result
    @makeLevelEnvelope: eff5,op5_envelope$,representativeDur,"5"
    .e5 = makeLevelEnvelope.result
    @makeLevelEnvelope: eff6,op6_envelope$,representativeDur,"6"
    .e6 = makeLevelEnvelope.result

    .levelY = 1.08*max(0.1,eff1,eff2,eff3,eff4,eff5,eff6)

    Select inner viewport: .left,.right,2.57,3.55
    Axes: 0,representativeDur,0,.levelY
    Paint rectangle: .bg$,0,representativeDur,0,.levelY

    selectObject: .e1
    Colour: .blue$
    Draw: 0,0,0,.levelY,"no","Curve"
    selectObject: .e2
    Colour: .orange$
    Draw: 0,0,0,.levelY,"no","Curve"
    selectObject: .e3
    Colour: .green$
    Draw: 0,0,0,.levelY,"no","Curve"
    selectObject: .e4
    Colour: .purple$
    Draw: 0,0,0,.levelY,"no","Curve"
    selectObject: .e5
    Colour: "{0.55,0.35,0.20}"
    Draw: 0,0,0,.levelY,"no","Curve"
    selectObject: .e6
    Colour: .dark$
    Draw: 0,0,0,.levelY,"no","Curve"

    removeObject: .e1,.e2,.e3,.e4,.e5,.e6

    Axes: 0,representativeDur,0,.levelY
    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Operator level"

    # Compact legend.
    Text: 0.02*representativeDur,"left",0.94*.levelY,"half",
        ... "1 blue | 2 orange | 3 green | 4 purple | 5 brown | 6 black"

    # -----------------------------------------------------------------------
    # PANEL C: MEASURED SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.71,3.93
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + nominal carrier guides"

    .specMax = min(safeTop,max(5000,2.0*maxRatio*maxFundamental))
    .specStep = max(0.002,.totalDur/1200)

    selectObject: sound
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,4.00,5.12
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,.totalDur,0,.specMax
    Colour: .blue$
    Line width: 1

    if melody_demo
        for .i from 1 to 8
            .x0 = demoOnset#[.i]
            .x1 = min(.totalDur,.x0+demoDur#[.i])

            if algorithm = 1
                if op1_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op1_freq*demoHz#[.i],.x1,op1_freq*demoHz#[.i]
                endif
                if op2_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op2_freq*demoHz#[.i],.x1,op2_freq*demoHz#[.i]
                endif
                if op3_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op3_freq*demoHz#[.i],.x1,op3_freq*demoHz#[.i]
                endif
                if op4_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op4_freq*demoHz#[.i],.x1,op4_freq*demoHz#[.i]
                endif
                if op5_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op5_freq*demoHz#[.i],.x1,op5_freq*demoHz#[.i]
                endif
                if op6_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op6_freq*demoHz#[.i],.x1,op6_freq*demoHz#[.i]
                endif

            elsif algorithm = 2
                if op1_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op1_freq*demoHz#[.i],.x1,op1_freq*demoHz#[.i]
                endif

            else
                if op1_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op1_freq*demoHz#[.i],.x1,op1_freq*demoHz#[.i]
                endif
                if op4_freq*demoHz#[.i] <= .specMax
                    Draw line: .x0,op4_freq*demoHz#[.i],.x1,op4_freq*demoHz#[.i]
                endif
            endif
        endfor

    else
        if algorithm = 1
            .carrierRatio# = {op1_freq,op2_freq,op3_freq,op4_freq,op5_freq,op6_freq}
            for .i to 6
                .cf = .carrierRatio#[.i]*base_frequency_Hz
                if .cf <= .specMax
                    Draw line: 0,.cf,.totalDur,.cf
                endif
            endfor

        elsif algorithm = 2
            .cf = op1_freq*base_frequency_Hz
            if .cf <= .specMax
                Draw line: 0,.cf,.totalDur,.cf
            endif

        else
            .cf = op1_freq*base_frequency_Hz
            if .cf <= .specMax
                Draw line: 0,.cf,.totalDur,.cf
            endif
            .cf = op4_freq*base_frequency_Hz
            if .cf <= .specMax
                Draw line: 0,.cf,.totalDur,.cf
            endif
        endif
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"
    Text bottom: "yes","Time (s)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SPECTRUM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.28,5.50
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MEASURED OUTPUT SPECTRUM | PM sidebands are measured, not inferred"

    selectObject: sound
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")

    Select inner viewport: .left,.right,5.57,6.35
    selectObject: .spectrum
    Colour: .purple$
    Draw: 0,.specMax,0,0,"no"
    removeObject: .spectrum

    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Power (dB)"
    Text bottom: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.58,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.80,"half",
        ... "ROUTING  |  " + algorithm$ + "  |  active operators "
        ... + string$(activeOps) + "/6  |  Op6 feedback " + fixed$(op6_feedback,2)

    Text: 0.02,"left",0.58,"half",
        ... "RATIOS  |  " + fixed$(op1_freq,2) + ", " + fixed$(op2_freq,2)
        ... + ", " + fixed$(op3_freq,2) + ", " + fixed$(op4_freq,2)
        ... + ", " + fixed$(op5_freq,2) + ", " + fixed$(op6_freq,2)

    if aliasWarning
        .alias$ = "upper-sideband warning"
    else
        .alias$ = "headroom OK"
    endif

    Text: 0.02,"left",0.37,"half",
        ... "BANDWIDTH QC  |  operator max " + fixed$(maxRatio*maxFundamental,0)
        ... + " Hz  |  practical PM top ~" + fixed$(practicalTopEstimate,0)
        ... + " Hz  |  " + .alias$

    if protectionApplied
        .protect$ = "peak protection applied"
    else
        .protect$ = "level preserved"
    endif

    Text: 0.02,"left",0.16,"half",
        ... "OUTPUT  |  master " + fixed$(master_volume,2)
        ... + "  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  RMS " + fixed$(finalRMS,4)
        ... + "  |  " + .protect$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
