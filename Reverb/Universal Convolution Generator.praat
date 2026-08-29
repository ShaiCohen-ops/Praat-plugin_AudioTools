# ============================================================
# Praat AudioTools - Universal_Convolution_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.3 reviewed (2026)
# v0.4.3 (2026): Added persistent Apply/OK workflow; Apply processes then automatically reopens the same algorithm settings with values preserved.
# v0.4.2 (2026): Two-step wizard supports Back/Generate and preserves entered settings; DSP/analysis unchanged.
# v0.4.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Universal Convolution Generator - nine algorithmic impulse-
#   response generators in one interface: Accelerando, Bouncing
#   Ball, Bursts & Taps, Euclidean Rhythm, Fibonacci, Golden Angle,
#   Random Walk, Stereo Fibonacci, and Swing.
#
# Review changes v0.3:
#   - Corrected PointProcess: To Sound (pulse train) semantics:
#     sampling rate, adaptation factor, adaptation time, sinc depth.
#   - Removed repeated peak normalization from IR and wet signal.
#   - IRs are normalized by discrete energy before convolution so
#     algorithms with many taps do not become automatically louder.
#   - Stereo IR normalization uses one common gain, preserving L/R.
#   - Wet/dry uses documented time/channel object() reads.
#   - 0% wet is a true dry-only path with no output normalization.
#   - Final peak protection is down-only and applied once.
#   - Preserves stereo dry signal; mono + Stereo Fibonacci yields
#     a stereo wet field with the mono dry signal centred.
#   - Added optional reproducible random seed.
#   - Added guards for invalid algorithm parameter ranges.
#   - Visualization shows the ACTUAL tap pattern used by the DSP.
#   - Visualization updated to Praat AudioTools house style.
# ============================================================

# === Check Input First ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
inputSR = Get sampling frequency
inputDur = Get total duration
inputStart = Get start time
inputChannels = Get number of channels
inputEnd = inputStart + inputDur

if inputChannels <> 1 and inputChannels <> 2
    exitScript: "Universal Convolution Generator currently supports mono or stereo Sound objects only."
endif

# ---------------------------------------------------------------------------
# STEP 1 + STEP 2: reversible two-stage wizard
# ---------------------------------------------------------------------------

# Persistent UI state. These values are initialized once, then reused as
# defaults whenever the user returns with < Back. This keeps the pause
# windows compact without making the algorithm choice irreversible.
ui_algorithm = 1
ui_duration = 2.0
ui_wet_dry = 70
ui_random_seed = 0
ui_draw_visualization = 1
ui_play_after_processing = 1

# Algorithm-specific persistent defaults
accel_first = 0.10
accel_pulses = 24
accel_shrink = 0.85

ball_first = 0.10
ball_gravity = 9.81
ball_velocity = 3.0
ball_bounce = 0.60

burst_tap1 = 0.15
burst_tap2 = 1.20
burst_num = 3
burst_points = 10
burst_std = 0.035

euclid_steps = 16
euclid_pulses = 5

fib_num = 12
fib_scale = 100.0
fib_jitter = 0.01

golden_num = 24
golden_margin = 0.10

walk_gap = 0.18
walk_var = 0.015

sfib_num = 12
sfib_L1 = 1
sfib_L2 = 1
sfib_R1 = 2
sfib_R2 = 3

swing_tempo = 120
swing_delay = 0.06

sessionActive = 1
showStep1 = 1
usesRandom = 0
uiAction = 3

while sessionActive = 1
    wizardDone = 0

    while wizardDone = 0
        # -------------------------------------------------------------------
        # STEP 1: Algorithm + shared settings
        # -------------------------------------------------------------------
        if showStep1 = 1
    beginPause: "Universal Convolver - Step 1"
        comment: "Select your generation algorithm:"
        optionmenu: "Algorithm", ui_algorithm
            option: "Accelerando"
            option: "Bouncing Ball"
            option: "Bursts and Taps"
            option: "Euclidean Rhythm"
            option: "Fibonacci (Mono)"
            option: "Golden Angle Drift"
            option: "Random Walk"
            option: "Stereo Fibonacci"
            option: "Swing"

        comment: "General Settings:"
        positive: "Duration", ui_duration
        real: "Wet_dry_percent", ui_wet_dry
        integer: "Random_seed", ui_random_seed
        comment: "Random seed: 0 = different stochastic pattern each run"

        comment: "Output:"
        boolean: "Draw_visualization", ui_draw_visualization
        boolean: "Play_after_processing", ui_play_after_processing
    endPause: "Next >", 1

    # Save Step 1 state so it survives a return from Step 2.
    ui_algorithm = algorithm
    ui_duration = duration
    ui_wet_dry = wet_dry_percent
    ui_random_seed = random_seed
    ui_draw_visualization = draw_visualization
    ui_play_after_processing = play_after_processing

    # Clamp shared settings exactly as before.
    if ui_wet_dry < 0
        ui_wet_dry = 0
    elsif ui_wet_dry > 100
        ui_wet_dry = 100
    endif

    if ui_random_seed < 0
        ui_random_seed = 0
    endif

    wet_dry_percent = ui_wet_dry
    random_seed = ui_random_seed
    draw_visualization = ui_draw_visualization
    play_after_processing = ui_play_after_processing
    wet_level = wet_dry_percent / 100
    dry_level = 1 - wet_level
    duration_seconds = ui_duration
    sr = inputSR

    # PointProcess pulse rendering settings. With adaptation factor = 1,
    # adaptation time does not attenuate pulses; sinc depth controls
    # band-limited sub-sample interpolation.
    adaptationFactor = 1
    adaptationTime = 0.05
    sincDepth = 2000

        endif

        # -------------------------------------------------------------------
        # STEP 2: Algorithm-specific settings
        # -------------------------------------------------------------------
    # Reset each time through the wizard. The final selected algorithm sets
    # this value before Generate exits the loop.
    usesRandom = 0
    clicked = 0

    if algorithm$ = "Accelerando"
        beginPause: "Settings: Accelerando"
            comment: "Pulses accelerate as successive gaps shrink"
            positive: "First_hit_time", accel_first
            natural: "Number_of_pulses", accel_pulses
            positive: "Gap_shrink_ratio", accel_shrink
        clicked = endPause: "< Back", "Apply", "OK", 2

        accel_first = first_hit_time
        accel_pulses = number_of_pulses
        accel_shrink = gap_shrink_ratio

        if clicked = 2 or clicked = 3
            if accel_first >= duration_seconds
                exitScript: "Accelerando: First hit time must be shorter than IR duration."
            endif
            if accel_shrink >= 1
                exitScript: "Accelerando: Gap shrink ratio must be greater than 0 and smaller than 1."
            endif
            if accel_pulses > 5000
                exitScript: "Accelerando: Number of pulses is limited to 5000."
            endif

            algoParams$ = "First " + fixed$(accel_first, 3) + " s | Pulses " + string$(accel_pulses) + " | Gap ratio " + fixed$(accel_shrink, 3)
            wizardDone = 1
        endif

    elsif algorithm$ = "Bouncing Ball"
        beginPause: "Settings: Bouncing Ball"
            comment: "Restitution-controlled shrinking bounce intervals"
            positive: "First_bounce_time", ball_first
            positive: "Gravity", ball_gravity
            positive: "Initial_velocity", ball_velocity
            positive: "Bounce_coefficient", ball_bounce
        clicked = endPause: "< Back", "Apply", "OK", 2

        ball_first = first_bounce_time
        ball_gravity = gravity
        ball_velocity = initial_velocity
        ball_bounce = bounce_coefficient

        if clicked = 2 or clicked = 3
            if ball_first >= duration_seconds
                exitScript: "Bouncing Ball: First bounce must be shorter than IR duration."
            endif
            if ball_bounce >= 1
                exitScript: "Bouncing Ball: Bounce coefficient must be greater than 0 and smaller than 1."
            endif

            algoParams$ = "First " + fixed$(ball_first, 3) + " s | g " + fixed$(ball_gravity, 2) + " | v0 " + fixed$(ball_velocity, 2) + " | restitution " + fixed$(ball_bounce, 2)
            wizardDone = 1
        endif

    elsif algorithm$ = "Bursts and Taps"
        usesRandom = 1

        beginPause: "Settings: Bursts & Taps"
            comment: "Random Gaussian bursts around independently chosen centres"
            positive: "Tap_1_time", burst_tap1
            positive: "Tap_2_time", burst_tap2
            natural: "Number_of_bursts", burst_num
            natural: "Points_per_burst", burst_points
            positive: "Burst_stddev", burst_std
        clicked = endPause: "< Back", "Apply", "OK", 2

        burst_tap1 = tap_1_time
        burst_tap2 = tap_2_time
        burst_num = number_of_bursts
        burst_points = points_per_burst
        burst_std = burst_stddev

        if clicked = 2 or clicked = 3
            if burst_num * burst_points > 5000
                exitScript: "Bursts & Taps: total burst points are limited to 5000."
            endif

            algoParams$ = "Taps " + fixed$(burst_tap1, 2) + "/" + fixed$(burst_tap2, 2) + " s | Bursts " + string$(burst_num) + " x " + string$(burst_points) + " | sigma " + fixed$(burst_std, 3) + " s"
            wizardDone = 1
        endif

    elsif algorithm$ = "Euclidean Rhythm"
        beginPause: "Settings: Euclidean"
            comment: "Evenly distributed K-pulse Euclidean rhythm in N steps"
            natural: "Total_steps", euclid_steps
            natural: "Active_pulses", euclid_pulses
        clicked = endPause: "< Back", "Apply", "OK", 2

        euclid_steps = total_steps
        euclid_pulses = active_pulses

        if clicked = 2 or clicked = 3
            if euclid_pulses > euclid_steps
                exitScript: "Euclidean Rhythm: Active pulses cannot exceed total steps."
            endif
            if euclid_steps > 10000
                exitScript: "Euclidean Rhythm: Total steps are limited to 10000."
            endif

            algoParams$ = "Euclidean E(" + string$(euclid_pulses) + "," + string$(euclid_steps) + ")"
            wizardDone = 1
        endif

    elsif algorithm$ = "Fibonacci (Mono)"
        usesRandom = 1

        beginPause: "Settings: Fibonacci"
            comment: "Fibonacci-positioned impulses with optional timing jitter"
            natural: "Fibonacci_terms", fib_num
            positive: "Scale_divisor", fib_scale
            positive: "Jitter_stddev", fib_jitter
        clicked = endPause: "< Back", "Apply", "OK", 2

        fib_num = fibonacci_terms
        fib_scale = scale_divisor
        fib_jitter = jitter_stddev

        if clicked = 2 or clicked = 3
            if fib_num > 80
                exitScript: "Fibonacci: Number of impulses is limited to 80."
            endif

            algoParams$ = "Requested " + string$(fib_num) + " | Scale " + fixed$(fib_scale, 1) + " | Jitter sigma " + fixed$(fib_jitter, 3) + " s"
            wizardDone = 1
        endif

    elsif algorithm$ = "Golden Angle Drift"
        beginPause: "Settings: Golden Angle"
            comment: "Low-discrepancy golden-ratio distribution"
            natural: "Number_of_impulses", golden_num
            positive: "Margin_s", golden_margin
        clicked = endPause: "< Back", "Apply", "OK", 2

        golden_num = number_of_impulses
        golden_margin = margin_s

        if clicked = 2 or clicked = 3
            if 2 * golden_margin >= duration_seconds
                exitScript: "Golden Angle: Margin must be smaller than half the IR duration."
            endif
            if golden_num > 5000
                exitScript: "Golden Angle: Number of impulses is limited to 5000."
            endif

            algoParams$ = "Impulses " + string$(golden_num) + " | Margin " + fixed$(golden_margin, 3) + " s"
            wizardDone = 1
        endif

    elsif algorithm$ = "Random Walk"
        usesRandom = 1

        beginPause: "Settings: Random Walk"
            comment: "Successive gaps follow a bounded random walk"
            positive: "Initial_gap", walk_gap
            positive: "Gap_variation", walk_var
        clicked = endPause: "< Back", "Apply", "OK", 2

        walk_gap = initial_gap
        walk_var = gap_variation

        if clicked = 2 or clicked = 3
            algoParams$ = "Initial gap " + fixed$(walk_gap, 3) + " s | Step sigma " + fixed$(walk_var, 3) + " s"
            wizardDone = 1
        endif

    elsif algorithm$ = "Stereo Fibonacci"
        usesRandom = 1

        beginPause: "Settings: Stereo Fibonacci"
            comment: "Different Fibonacci seeds and jitter per channel"
            natural: "Fibonacci_terms_per_channel", sfib_num
            comment: "Left Channel Seeds:"
            natural: "Left_seed_1", sfib_L1
            natural: "Left_seed_2", sfib_L2
            comment: "Right Channel Seeds:"
            natural: "Right_seed_1", sfib_R1
            natural: "Right_seed_2", sfib_R2
        clicked = endPause: "< Back", "Apply", "OK", 2

        sfib_num = fibonacci_terms_per_channel
        sfib_L1 = left_seed_1
        sfib_L2 = left_seed_2
        sfib_R1 = right_seed_1
        sfib_R2 = right_seed_2

        if clicked = 2 or clicked = 3
            if sfib_num > 80
                exitScript: "Stereo Fibonacci: Number of impulses is limited to 80."
            endif

            algoParams$ = "Requested " + string$(sfib_num) + "/ch | L seeds " + string$(sfib_L1) + "," + string$(sfib_L2) + " | R seeds " + string$(sfib_R1) + "," + string$(sfib_R2)
            wizardDone = 1
        endif

    elsif algorithm$ = "Swing"
        beginPause: "Settings: Swing"
            comment: "Alternating delayed timing around a tempo grid"
            positive: "Tempo_BPM", swing_tempo
            positive: "Swing_delay_s", swing_delay
        clicked = endPause: "< Back", "Apply", "OK", 2

        swing_tempo = tempo_BPM
        swing_delay = swing_delay_s

        if clicked = 2 or clicked = 3
            swingBeat = 60 / swing_tempo
            if swing_delay >= swingBeat
                exitScript: "Swing: Swing delay must be shorter than one beat."
            endif

            algoParams$ = "Tempo " + fixed$(swing_tempo, 1) + " BPM | Alternate delay " + fixed$(swing_delay * 1000, 1) + " ms"
            wizardDone = 1
        endif
    endif

        # Navigation state shared by all algorithm pages.
        if clicked = 1
            showStep1 = 1
        elsif wizardDone = 1
            uiAction = clicked
            showStep1 = 0
        endif
    endwhile

# ---------------------------------------------------------------------------
# Random-state handling
# ---------------------------------------------------------------------------

if usesRandom = 1
    if random_seed = 0
        random_initializeSafelyAndUnpredictably ()
        seedLabel$ = "random each run"
    else
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
        seedLabel$ = "seed " + string$(random_seed)
    endif
else
    seedLabel$ = "deterministic"
endif

# ---------------------------------------------------------------------------
# Generate ACTUAL tap pattern and keep tap times for visualization
# ---------------------------------------------------------------------------

writeInfoLine: "=== Universal Convolution Generator ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Algorithm: ", algorithm$
appendInfoLine: "IR duration: ", fixed$(duration_seconds, 3), " s"
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 1), "%"
appendInfoLine: "Pattern: ", seedLabel$
appendInfoLine: ""
appendInfoLine: "Generating impulse pattern..."

isStereo = 0
nTaps = 0
nLeft = 0
nRight = 0

if algorithm$ = "Accelerando"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")

    nTaps = 1
    tapTime[nTaps] = accel_first
    selectObject: ppGen
    Add point: accel_first

    if accel_pulses > 1
        endTarget = duration_seconds - 0.5 / sr
        if accel_first >= endTarget
            removeObject: ppGen
            exitScript: "Accelerando: First hit leaves no room for the requested number of pulses."
        endif

        span = endTarget - accel_first
        if accel_shrink > 0.999999
            firstGap = span / (accel_pulses - 1)
        else
            firstGap = span * (1 - accel_shrink) / (1 - accel_shrink ^ (accel_pulses - 1))
        endif

        t = accel_first
        for i from 1 to accel_pulses - 1
            gap = firstGap * accel_shrink ^ (i - 1)
            t = t + gap
            if t > 0 and t < duration_seconds
                nTaps = nTaps + 1
                tapTime[nTaps] = t
                selectObject: ppGen
                Add point: t
            endif
        endfor
    endif

elsif algorithm$ = "Bouncing Ball"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")

    t = ball_first
    v = ball_velocity

    if t > 0 and t < duration_seconds
        nTaps = nTaps + 1
        tapTime[nTaps] = t
        selectObject: ppGen
        Add point: t
    endif

    dt = 2 * v / ball_gravity
    count = 0

    while (t + dt < duration_seconds) and (dt >= 0.001) and (count < 500)
        t = t + dt
        nTaps = nTaps + 1
        tapTime[nTaps] = t
        selectObject: ppGen
        Add point: t

        v = ball_bounce * v
        dt = 2 * v / ball_gravity
        count = count + 1
    endwhile

elsif algorithm$ = "Bursts and Taps"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")

    if burst_tap1 > 0 and burst_tap1 < duration_seconds
        nTaps = nTaps + 1
        tapTime[nTaps] = burst_tap1
        selectObject: ppGen
        Add point: burst_tap1
    endif

    if burst_tap2 > 0 and burst_tap2 < duration_seconds
        nTaps = nTaps + 1
        tapTime[nTaps] = burst_tap2
        selectObject: ppGen
        Add point: burst_tap2
    endif

    burstMargin = min(0.05, 0.20 * duration_seconds)
    centerLow = burstMargin
    centerHigh = duration_seconds - burstMargin

    for b from 1 to burst_num
        if centerHigh > centerLow
            center = randomUniform(centerLow, centerHigh)
        else
            center = 0.5 * duration_seconds
        endif

        for i from 1 to burst_points
            u = center + randomGauss(0, burst_std)
            if u > 0 and u < duration_seconds
                nTaps = nTaps + 1
                tapTime[nTaps] = u
                selectObject: ppGen
                Add point: u
            endif
        endfor
    endfor

elsif algorithm$ = "Euclidean Rhythm"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")

    step = duration_seconds / euclid_steps

    for i from 0 to euclid_steps - 1
        if ((i * euclid_pulses) mod euclid_steps) < euclid_pulses
            t = i * step
            nTaps = nTaps + 1
            tapTime[nTaps] = t
            selectObject: ppGen
            Add point: t
        endif
    endfor

elsif algorithm$ = "Fibonacci (Mono)"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")

    f1 = 1
    f2 = 1

    for i from 1 to fib_num
        tBase = (f1 / fib_scale) * duration_seconds
        t = tBase + randomGauss(0, fib_jitter)

        if t > 0 and t < duration_seconds
            nTaps = nTaps + 1
            tapTime[nTaps] = t
            selectObject: ppGen
            Add point: t
        endif

        ft = f1 + f2
        f1 = f2
        f2 = ft
    endfor

elsif algorithm$ = "Golden Angle Drift"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")

    phi = (sqrt(5) - 1) / 2

    for i from 1 to golden_num
        u = (i * phi) - floor(i * phi)
        t = golden_margin + u * (duration_seconds - 2 * golden_margin)

        if t > 0 and t < duration_seconds
            nTaps = nTaps + 1
            tapTime[nTaps] = t
            selectObject: ppGen
            Add point: t
        endif
    endfor

elsif algorithm$ = "Random Walk"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")

    t = min(0.10, 0.10 * duration_seconds)
    gap = walk_gap
    count = 0

    while (t < duration_seconds) and (count < 5000)
        if t > 0
            nTaps = nTaps + 1
            tapTime[nTaps] = t
            selectObject: ppGen
            Add point: t
        endif

        gap = gap + randomGauss(0, walk_var)

        if gap < 0.01
            gap = 0.01
        elsif gap > 0.65
            gap = 0.65
        endif

        t = t + gap
        count = count + 1
    endwhile

elsif algorithm$ = "Swing"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")

    beat = 60 / swing_tempo
    t = beat
    i = 1

    while t < duration_seconds
        if (i mod 2) = 0
            tDraw = t + swing_delay
        else
            tDraw = t
        endif

        if tDraw > 0 and tDraw < duration_seconds
            nTaps = nTaps + 1
            tapTime[nTaps] = tDraw
            selectObject: ppGen
            Add point: tDraw
        endif

        t = t + beat
        i = i + 1
    endwhile

elsif algorithm$ = "Stereo Fibonacci"
    isStereo = 1

    # Left
    Create empty PointProcess: "pp_left", 0, duration_seconds
    ppLeft = selected("PointProcess")

    f1 = sfib_L1
    f2 = sfib_L2

    for i from 1 to sfib_num
        t = (f1 / 100.0) * duration_seconds + randomGauss(0, 0.01)

        if t > 0 and t < duration_seconds
            nLeft = nLeft + 1
            leftTime[nLeft] = t
            selectObject: ppLeft
            Add point: t
        endif

        ft = f1 + f2
        f1 = f2
        f2 = ft
    endfor

    # Right
    Create empty PointProcess: "pp_right", 0, duration_seconds
    ppRight = selected("PointProcess")

    f1 = sfib_R1
    f2 = sfib_R2

    for i from 1 to sfib_num
        t = (f1 / 120.0) * duration_seconds + randomGauss(0, 0.02)

        if t > 0 and t < duration_seconds
            nRight = nRight + 1
            rightTime[nRight] = t
            selectObject: ppRight
            Add point: t
        endif

        ft = f1 + f2
        f1 = f2
        f2 = ft
    endfor
endif

# Do not leave Praat's global RNG in a predictable state.
if usesRandom = 1 and random_seed <> 0
    random_initializeSafelyAndUnpredictably ()
endif

if isStereo = 0
    if nTaps < 1
        removeObject: ppGen
        exitScript: "These settings generated no valid impulse times inside the IR duration."
    endif
    appendInfoLine: "Actual taps: ", nTaps
else
    if nLeft < 1 or nRight < 1
        removeObject: ppLeft, ppRight
        exitScript: "Stereo Fibonacci requires at least one valid tap in both channels. Adjust seeds, count, or duration."
    endif
    appendInfoLine: "Actual taps: L=", nLeft, " | R=", nRight
endif

# ---------------------------------------------------------------------------
# DSP
# ---------------------------------------------------------------------------

if wet_level = 0
    appendInfoLine: "Wet = 0%: bypassing IR rendering and convolution."

    if isStereo = 0
        removeObject: ppGen
    else
        removeObject: ppLeft, ppRight
    endif

    selectObject: originalID
    Copy: originalName$ + "_conv_" + algorithm$
    result = selected("Sound")

else
    appendInfoLine: "Rendering band-limited impulse response..."

    if isStereo = 0
        selectObject: ppGen
        To Sound (pulse train): sr, adaptationFactor, adaptationTime, sincDepth
        irSound = selected("Sound")
        removeObject: ppGen

        # Unit discrete energy: sum(h^2) = 1.
        selectObject: irSound
        irEnergy = Get energy: 0, 0

        if irEnergy <= 0
            removeObject: irSound
            exitScript: "Generated impulse response has zero energy."
        endif

        irGain = 1 / sqrt(irEnergy * sr)
        irGainStr$ = string$(irGain)
        Formula: "self * " + irGainStr$

    else
        selectObject: ppLeft
        To Sound (pulse train): sr, adaptationFactor, adaptationTime, sincDepth
        irLeft = selected("Sound")

        selectObject: ppRight
        To Sound (pulse train): sr, adaptationFactor, adaptationTime, sincDepth
        irRight = selected("Sound")

        removeObject: ppLeft, ppRight

        # One common energy gain preserves the relative L/R pattern.
        selectObject: irLeft
        energyLeft = Get energy: 0, 0

        selectObject: irRight
        energyRight = Get energy: 0, 0

        maxIrEnergy = max(energyLeft, energyRight)

        if maxIrEnergy <= 0
            removeObject: irLeft, irRight
            exitScript: "Generated stereo impulse response has zero energy."
        endif

        irGain = 1 / sqrt(maxIrEnergy * sr)
        irGainStr$ = string$(irGain)

        selectObject: irLeft
        Formula: "self * " + irGainStr$

        selectObject: irRight
        Formula: "self * " + irGainStr$

        selectObject: irLeft, irRight
        Combine to stereo
        irSound = selected("Sound")

        removeObject: irLeft, irRight
    endif

    appendInfoLine: "Convolving..."

    # Praat permits mono/multichannel convolution; if one Sound is mono,
    # its impulse response is applied to every channel of the other Sound.
    selectObject: originalID, irSound
    Convolve: "sum", "zero"
    wetSound = selected("Sound")

    removeObject: irSound

    # True wet/dry mix. object() returns zero outside the dry Sound domain,
    # so no explicit dry padding is needed.
    if dry_level > 0
        wetStr$ = string$(wet_level)
        dryStr$ = string$(dry_level)
        originalIdStr$ = string$(originalID)

        selectObject: wetSound

        if inputChannels = 1
            Formula: "self * " + wetStr$ + " + object(" + originalIdStr$ + ", x, 1) * " + dryStr$
        else
            Formula: "self * " + wetStr$ + " + object(" + originalIdStr$ + ", x, row) * " + dryStr$
        endif
    endif

    Rename: originalName$ + "_conv_" + algorithm$
    result = selected("Sound")

    # One down-only safety gain. Never amplify quiet material.
    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "none"

    if resultPeak > 0.98
        Scale peak: 0.98
    endif
endif

# ---------------------------------------------------------------------------
# Result metadata
# ---------------------------------------------------------------------------

selectObject: result
resultDur = Get total duration
resultStart = Get start time
resultChannels = Get number of channels
resultEnd = resultStart + resultDur
resultPeak = Get absolute extremum: 0, 0, "none"

timelineStart = min(inputStart, resultStart)
timelineEnd = max(inputEnd, resultEnd)

if isStereo = 0
    tapSummary$ = string$(nTaps) + " taps"
else
    tapSummary$ = "L " + string$(nLeft) + " / R " + string$(nRight) + " taps"
endif

# ---------------------------------------------------------------------------
# VISUALIZATION - PRAAT AUDIOTOOLS HOUSE STYLE
# ---------------------------------------------------------------------------

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7


    # Title.
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "Universal Convolution Generator | " + algorithm$ + " | v0.4.3"

    # Metadata.
    Select outer viewport: 0, 8, 0.36, 0.58
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | IR " + fixed$(duration_seconds, 2) + " s | " + tapSummary$ + " | Wet " + fixed$(wet_dry_percent, 0) + "%"

    # Dry waveform on the complete result timeline.
    Select outer viewport: 0, 8, 0.65, 1.35
    Select inner viewport: 0.60, 7.70, 0.72, 1.28
    selectObject: originalID
    Colour: "{0.65, 0.65, 0.65}"
    Draw: timelineStart, timelineEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 0.72, 1.28
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.72, 1.28
    Axes: 0, 1, 0, 1

    # Output waveform.
    Select outer viewport: 0, 8, 1.42, 2.12
    Select inner viewport: 0.60, 7.70, 1.49, 2.05
    selectObject: result
    Colour: "{0.48, 0.60, 0.76}"
    Draw: timelineStart, timelineEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 1.49, 2.05
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Output"
    Select inner viewport: 0.60, 7.70, 1.49, 2.05
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"

    # Actual tap-pattern title.
    Select outer viewport: 0, 8, 2.24, 2.48
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Actual impulse pattern used by the DSP"

    # Actual tap pattern.
    Select outer viewport: 0, 8, 2.45, 3.82
    Select inner viewport: 0.60, 7.70, 2.60, 3.68

    if isStereo = 0
        Axes: 0, duration_seconds, 0, 1.08
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_seconds, 0, 1.08

        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0.10, duration_seconds, 0.10

        Colour: "{0.42, 0.58, 0.76}"
        for i from 1 to nTaps
            t = tapTime[i]
            Draw line: t, 0.10, t, 0.80
            Paint circle (mm): "{0.42, 0.58, 0.76}", t, 0.80, 1.2
        endfor

        Colour: "Black"
        Draw inner box
        Font size: 6
        Select inner viewport: 0.20, 0.48, 2.60, 3.68
        Axes: 0, 1, 0, 1
        Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Impulse"
        Select inner viewport: 0.60, 7.70, 2.60, 3.68
        Axes: 0, duration_seconds, 0, 1.08
        Text bottom: "yes", "IR time (s)"

    else
        Axes: 0, duration_seconds, -1.10, 1.10
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_seconds, -1.10, 1.10

        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0, duration_seconds, 0

        Colour: "{0.42, 0.58, 0.76}"
        for i from 1 to nLeft
            t = leftTime[i]
            Draw line: t, 0.05, t, 0.78
            Paint circle (mm): "{0.42, 0.58, 0.76}", t, 0.78, 1.2
        endfor

        Colour: "{0.78, 0.48, 0.42}"
        for i from 1 to nRight
            t = rightTime[i]
            Draw line: t, -0.05, t, -0.78
            Paint circle (mm): "{0.78, 0.48, 0.42}", t, -0.78, 1.2
        endfor

        Colour: "Black"
        Draw inner box
        Font size: 6
        Select inner viewport: 0.20, 0.48, 2.60, 3.68
        Axes: 0, 1, 0, 1
        Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "L / R"
        Select inner viewport: 0.60, 7.70, 2.60, 3.68
        Axes: 0, duration_seconds, -1.10, 1.10
        Text bottom: "yes", "IR time (s)"

        Font size: 6
        Colour: "{0.42, 0.58, 0.76}"
        Text: duration_seconds * 0.98, "right", 0.95, "half", "LEFT " + string$(nLeft)
        Colour: "{0.78, 0.48, 0.42}"
        Text: duration_seconds * 0.98, "right", -0.95, "half", "RIGHT " + string$(nRight)
    endif

    # Summary panel.
    Select outer viewport: 0, 8, 3.97, 4.97
    Select inner viewport: 0.60, 7.70, 4.04, 4.90
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Colour: "{0.35, 0.35, 0.35}"
    Font size: 6
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", algoParams$
    Font size: 6
    Text: 0.02, "left", 0.24, "half", tapSummary$ + " | " + seedLabel$ + " | IR energy-normalized | Output " + fixed$(resultDur, 2) + " s / " + string$(resultChannels) + " ch"

    Select inner viewport: 0.60, 7.70, 4.04, 4.90
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 5.07
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ---------------------------------------------------------------------------
# FINAL INFO / PLAY
# ---------------------------------------------------------------------------

selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output duration: ", fixed$(resultDur, 3), " s"
appendInfoLine: "Output channels: ", resultChannels
appendInfoLine: "Output peak: ", fixed$(resultPeak, 4)

if play_after_processing
    selectObject: result
    Play
endif

selectObject: result

    # Apply keeps the session alive and returns directly to the same
    # algorithm-specific page. OK applies once and closes the session.
    if uiAction = 2
        selectObject: originalID
    else
        sessionActive = 0
    endif
endwhile

selectObject: result
