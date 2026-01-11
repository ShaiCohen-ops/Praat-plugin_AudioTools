# ============================================================
# Praat AudioTools - Universal_Convolution_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Universal Convolution Generator - 9 impulse response
#   algorithms in one interface: Accelerando, Bouncing Ball,
#   Bursts & Taps, Euclidean Rhythm, Fibonacci, Golden Angle,
#   Random Walk, Stereo Fibonacci, and Swing. Each algorithm
#   generates a unique impulse pattern for convolution.
#
# Changelog v0.2:
#   - Fixed name-based references (all ID-based)
#   - Added wet/dry mix control
#   - Added visualization
#   - Uses input sample rate by default
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

# --- STEP 1: Main Selection Window ---
beginPause: "Universal Convolver - Step 1"
    comment: "Select your generation algorithm:"
    optionmenu: "Algorithm", 1
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
    positive: "Duration", 2.0
    real: "Wet_dry_percent", 70
    
    comment: "Output:"
    boolean: "Draw_visualization", 1
    boolean: "Play_after_processing", 1
endPause: "Next >>", 1

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# --- STEP 2: Context-Aware Parameter Window ---

if algorithm$ = "Accelerando"
    beginPause: "Settings: Accelerando"
        comment: "Pulses that accelerate (gaps shrink)"
        positive: "First_hit_time", 0.10
        natural: "Number_of_pulses", 24
        positive: "Gap_shrink_ratio", 0.85
    endPause: "Run", 1
    
    accel_first = first_hit_time
    accel_pulses = number_of_pulses
    accel_shrink = gap_shrink_ratio

elsif algorithm$ = "Bouncing Ball"
    beginPause: "Settings: Bouncing Ball"
        comment: "Physics-based bouncing pattern"
        positive: "First_bounce_time", 0.10
        positive: "Gravity", 9.81
        positive: "Initial_velocity", 3.0
        positive: "Bounce_coefficient", 0.60
    endPause: "Run", 1

    ball_first = first_bounce_time
    ball_gravity = gravity
    ball_velocity = initial_velocity
    ball_bounce = bounce_coefficient

elsif algorithm$ = "Bursts and Taps"
    beginPause: "Settings: Bursts & Taps"
        comment: "Random bursts with tap accents"
        positive: "Tap_1_time", 0.15
        positive: "Tap_2_time", 1.20
        natural: "Number_of_bursts", 3
        natural: "Points_per_burst", 10
        positive: "Burst_stddev", 0.035
    endPause: "Run", 1

    burst_tap1 = tap_1_time
    burst_tap2 = tap_2_time
    burst_num = number_of_bursts
    burst_points = points_per_burst
    burst_std = burst_stddev

elsif algorithm$ = "Euclidean Rhythm"
    beginPause: "Settings: Euclidean"
        comment: "Bjorklund algorithm: K pulses in N steps"
        natural: "Total_steps", 16
        natural: "Active_pulses", 5
    endPause: "Run", 1

    euclid_steps = total_steps
    euclid_pulses = active_pulses

elsif algorithm$ = "Fibonacci (Mono)"
    beginPause: "Settings: Fibonacci"
        comment: "Impulses at Fibonacci sequence times"
        natural: "Number_of_impulses", 12
        positive: "Scale_divisor", 100.0
        positive: "Jitter_stddev", 0.01
    endPause: "Run", 1

    fib_num = number_of_impulses
    fib_scale = scale_divisor
    fib_jitter = jitter_stddev

elsif algorithm$ = "Golden Angle Drift"
    beginPause: "Settings: Golden Angle"
        comment: "Golden ratio distribution"
        natural: "Number_of_impulses", 24
        positive: "Margin_s", 0.10
    endPause: "Run", 1

    golden_num = number_of_impulses
    golden_margin = margin_s

elsif algorithm$ = "Random Walk"
    beginPause: "Settings: Random Walk"
        comment: "Gap varies by random walk"
        positive: "Initial_gap", 0.18
        positive: "Gap_variation", 0.015
    endPause: "Run", 1

    walk_gap = initial_gap
    walk_var = gap_variation

elsif algorithm$ = "Stereo Fibonacci"
    beginPause: "Settings: Stereo Fibonacci"
        comment: "Different Fibonacci seeds per channel"
        natural: "Number_of_impulses", 12
        comment: "Left Channel Seeds:"
        natural: "Left_seed_1", 1
        natural: "Left_seed_2", 1
        comment: "Right Channel Seeds:"
        natural: "Right_seed_1", 2
        natural: "Right_seed_2", 3
    endPause: "Run", 1

    sfib_num = number_of_impulses
    sfib_L1 = left_seed_1
    sfib_L2 = left_seed_2
    sfib_R1 = right_seed_1
    sfib_R2 = right_seed_2

elsif algorithm$ = "Swing"
    beginPause: "Settings: Swing"
        comment: "Jazz swing timing"
        positive: "Tempo_BPM", 120
        positive: "Swing_delay_s", 0.06
    endPause: "Run", 1

    swing_tempo = tempo_BPM
    swing_delay = swing_delay_s
endif

# === Setup ===
sr = inputSR
duration_seconds = duration
pulse_amplitude = 1
pulse_width = 0.02
pulse_period = 2000

# === Info ===
writeInfoLine: "=== Universal Convolution Generator ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Algorithm: ", algorithm$
appendInfoLine: "IR Duration: ", duration_seconds, " s"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# === Prepare Source ===
selectObject: originalID
Copy: "source_copy"
sourceCopy = selected("Sound")

# Flag for stereo processing
isStereo = 0

# === Generate Impulse Response ===
appendInfoLine: "Generating impulse pattern..."

if algorithm$ = "Accelerando"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")
    
    remain = duration_seconds - accel_first
    den = 1 - accel_shrink ^ accel_pulses
    g0 = remain * (1 - accel_shrink) / den
    t = accel_first
    i = 1
    while i <= accel_pulses and t < duration_seconds
        selectObject: ppGen
        Add point: t
        gap = g0 * accel_shrink ^ (i - 1)
        t = t + gap
        i = i + 1
    endwhile

elsif algorithm$ = "Bouncing Ball"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")
    
    t = ball_first
    v = ball_velocity
    if t > 0 and t < duration_seconds
        Add point: t
    endif
    dt = 2 * v / ball_gravity
    count = 0
    while (t + dt < duration_seconds) and (dt >= 0.001) and (count < 50)
        t = t + dt
        Add point: t
        v = ball_bounce * v
        dt = 2 * v / ball_gravity
        count = count + 1
    endwhile

elsif algorithm$ = "Bursts and Taps"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")
    
    if burst_tap1 < duration_seconds
        Add point: burst_tap1
    endif
    if burst_tap2 < duration_seconds
        Add point: burst_tap2
    endif
    
    for b from 1 to burst_num
        center = randomUniform(0.05, duration_seconds - 0.05)
        for i from 1 to burst_points
            u = center + randomGauss(0, burst_std)
            if u > 0 and u < duration_seconds
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
            selectObject: ppGen
            Add point: i * step
        endif
    endfor

elsif algorithm$ = "Fibonacci (Mono)"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")
    
    f1 = 1
    f2 = 1
    for i from 1 to fib_num
        t_base = (f1 / fib_scale) * duration_seconds
        t = t_base + randomGauss(0, fib_jitter)
        if t > 0 and t < duration_seconds
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
            selectObject: ppGen
            Add point: t
        endif
    endfor

elsif algorithm$ = "Random Walk"
    Create empty PointProcess: "pp_gen", 0, duration_seconds
    ppGen = selected("PointProcess")
    
    t = 0.10
    gap = walk_gap
    count = 0
    while (t < duration_seconds) and (count < 400)
        Add point: t
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
            Add point: t + swing_delay
        else
            Add point: t
        endif
        t = t + beat
        i = i + 1
    endwhile

elsif algorithm$ = "Stereo Fibonacci"
    isStereo = 1
    
    # Left channel
    Create empty PointProcess: "pp_left", 0, duration_seconds
    ppLeft = selected("PointProcess")
    f1 = sfib_L1
    f2 = sfib_L2
    for i from 1 to sfib_num
        t = (f1 / 100.0) * duration_seconds + randomGauss(0, 0.01)
        if t > 0 and t < duration_seconds
            selectObject: ppLeft
            Add point: t
        endif
        ft = f1 + f2
        f1 = f2
        f2 = ft
    endfor
    
    # Right channel
    Create empty PointProcess: "pp_right", 0, duration_seconds
    ppRight = selected("PointProcess")
    f1 = sfib_R1
    f2 = sfib_R2
    for i from 1 to sfib_num
        t = (f1 / 120.0) * duration_seconds + randomGauss(0, 0.02)
        if t > 0 and t < duration_seconds
            selectObject: ppRight
            Add point: t
        endif
        ft = f1 + f2
        f1 = f2
        f2 = ft
    endfor
endif

# === Convert to Pulse Trains ===
if isStereo = 0
    selectObject: ppGen
    To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulse_period
    irSound = selected("Sound")
    Scale peak: 0.99
    removeObject: ppGen
else
    selectObject: ppLeft
    To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulse_period
    irLeft = selected("Sound")
    Scale peak: 0.99
    
    selectObject: ppRight
    To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulse_period
    irRight = selected("Sound")
    Scale peak: 0.99
    
    selectObject: irLeft, irRight
    Combine to stereo
    irSound = selected("Sound")
    
    removeObject: ppLeft, ppRight, irLeft, irRight
endif

# === Convolve ===
appendInfoLine: "Convolving..."

selectObject: sourceCopy, irSound
Convolve: "sum", "zero"
wetSound = selected("Sound")
Scale peak: 0.95

# === Apply Wet/Dry ===
if dry_level > 0
    selectObject: wetSound
    wetDur = Get total duration
    
    selectObject: sourceCopy
    dryDur = Get total duration
    dryChannels = Get number of channels
    
    if dryDur < wetDur
        # Extend dry - MATCH CHANNEL COUNT
        Create Sound from formula: "sil_pad", dryChannels, 0, wetDur - dryDur, sr, "0"
        silPad = selected("Sound")
        selectObject: sourceCopy, silPad
        Concatenate
        dryExt = selected("Sound")
        removeObject: silPad
    else
        selectObject: sourceCopy
        Copy: "dry_ext"
        dryExt = selected("Sound")
    endif
    
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dryExt)
    
    selectObject: wetSound
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
    
    removeObject: dryExt
endif

selectObject: wetSound
Scale peak: 0.98
Rename: originalName$ + "_conv_" + algorithm$
result = selected("Sound")

# === Cleanup ===
removeObject: sourceCopy, irSound

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Universal Convolver: " + algorithm$ + " → " + originalName$
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.5, 3.7, 0.75, 1.45
    selectObject: originalID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.5, 7.7, 0.75, 1.45
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, inputDur * 1.5, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Convolved " + fixed$(wet_dry_percent, 0) + "%"
    
    # Algorithm diagram
    Select outer viewport: 0, 8, 1.8, 3.3
    Select inner viewport: 0.6, 7.6, 2.0, 3.15
    
    Axes: 0, duration_seconds, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration_seconds, 0, 1.2
    
    # Draw algorithm name
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: duration_seconds * 0.5, "centre", 1.1, "half", algorithm$
    
    # Show pattern schematic
    Colour: "{0.5, 0.6, 0.8}"
    Line width: 2
    
    if algorithm$ = "Accelerando"
        # Show accelerating pattern
        gap = 0.3
        t = 0.1
        for i from 1 to 12
            Draw line: t, 0.1, t, 0.8
            Paint circle (mm): "{0.5, 0.6, 0.8}", t, 0.8, 1.5
            gap = gap * 0.82
            t = t + gap
        endfor
        Font size: 5
        Text: duration_seconds * 0.8, "centre", 0.5, "half", "gaps shrink"
        
    elsif algorithm$ = "Bouncing Ball"
        # Show bouncing pattern
        t = 0.1
        dt = 0.35
        for i from 1 to 10
            Draw line: t, 0.1, t, 0.8
            Paint circle (mm): "{0.5, 0.6, 0.8}", t, 0.8, 1.5
            t = t + dt
            dt = dt * 0.65
        endfor
        Font size: 5
        Text: duration_seconds * 0.8, "centre", 0.5, "half", "physics bounce"
        
    elsif algorithm$ = "Euclidean Rhythm"
        # Show euclidean pattern
        step = duration_seconds / 16
        for i from 0 to 15
            t = i * step
            if ((i * 5) mod 16) < 5
                Draw line: t, 0.1, t, 0.8
                Paint circle (mm): "{0.5, 0.6, 0.8}", t, 0.8, 1.5
            else
                Colour: "{0.85, 0.85, 0.85}"
                Draw line: t, 0.2, t, 0.4
                Colour: "{0.5, 0.6, 0.8}"
            endif
        endfor
        Font size: 5
        Text: duration_seconds * 0.8, "centre", 0.5, "half", "5 in 16"
        
    elsif algorithm$ = "Fibonacci (Mono)"
        f1 = 1
        f2 = 1
        for i from 1 to 10
            t = (f1 / 100) * duration_seconds
            if t < duration_seconds
                Draw line: t, 0.1, t, 0.8
                Paint circle (mm): "{0.5, 0.6, 0.8}", t, 0.8, 1.5
            endif
            ft = f1 + f2
            f1 = f2
            f2 = ft
        endfor
        Font size: 5
        Text: duration_seconds * 0.8, "centre", 0.5, "half", "1,1,2,3,5,8..."
        
    elsif algorithm$ = "Golden Angle Drift"
        phi = (sqrt(5) - 1) / 2
        for i from 1 to 15
            u = (i * phi) - floor(i * phi)
            t = 0.1 + u * (duration_seconds - 0.2)
            Draw line: t, 0.1, t, 0.8
            Paint circle (mm): "{0.5, 0.6, 0.8}", t, 0.8, 1.5
        endfor
        Font size: 5
        Text: duration_seconds * 0.8, "centre", 0.5, "half", "φ distribution"
        
    elsif algorithm$ = "Swing"
        beat = duration_seconds / 8
        t = beat
        for i from 1 to 7
            if (i mod 2) = 0
                tDraw = t + beat * 0.15
            else
                tDraw = t
            endif
            Draw line: tDraw, 0.1, tDraw, 0.8
            Paint circle (mm): "{0.5, 0.6, 0.8}", tDraw, 0.8, 1.5
            t = t + beat
        endfor
        Font size: 5
        Text: duration_seconds * 0.8, "centre", 0.5, "half", "swing feel"
        
    else
        # Generic pattern
        for i from 1 to 10
            t = randomUniform(0.05, duration_seconds - 0.05)
            Draw line: t, 0.1, t, 0.8
            Paint circle (mm): "{0.5, 0.6, 0.8}", t, 0.8, 1.5
        endfor
    endif
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Time (s)"
    
    # Parameters
    Select outer viewport: 0, 8, 3.4, 3.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "IR Duration: " + fixed$(duration_seconds, 1) + "s | Wet/Dry: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_after_processing
    selectObject: result
    Play
endif

selectObject: result