# ============================================================
# Praat AudioTools - Chaotic_Prosody_Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaotic Prosody Manipulation - applies chaos theory to
#   prosody. Pitch uses either the logistic map (deterministic
#   chaos) or Ornstein-Uhlenbeck process (stochastic). Amplitude
#   uses the Lorenz attractor for chaotic modulation.
#
# Changelog v0.2:
#   - Added input check
#   - Modern syntax
#   - Added presets
#   - Added visualization
#   - Fixed array bounds issues
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling_rate = Get sampling frequency
n_samples = Get number of samples

# === Form ===
form Chaotic Prosody Manipulation
    comment Select a Sound object first
    
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
    
    comment === Lorenz AM Parameters ===
    real Lorenz_sigma 10.0
    real Lorenz_rho 28.0
    real Lorenz_beta 2.667
    real Lorenz_scale 0.6
    real AM_smoothing 0.85
    
    comment === Fade Out ===
    real Fadeout_duration 0.5
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Chaos
    pitch_mode = 1
    logistic_r = 3.7
    logistic_depth = 0.15
    lorenz_scale = 0.3
    aM_smoothing = 0.92
    presetName$ = "Gentle"
elsif preset = 3
    # Classic Lorenz
    pitch_mode = 1
    logistic_r = 3.9
    logistic_depth = 0.25
    lorenz_sigma = 10.0
    lorenz_rho = 28.0
    lorenz_beta = 2.667
    lorenz_scale = 0.5
    aM_smoothing = 0.85
    presetName$ = "Classic"
elsif preset = 4
    # Wild Logistic
    pitch_mode = 1
    logistic_r = 3.99
    logistic_depth = 0.5
    lorenz_scale = 0.7
    aM_smoothing = 0.75
    presetName$ = "Wild"
elsif preset = 5
    # Stochastic Drift
    pitch_mode = 2
    oU_theta = 1.0
    oU_sigma = 30.0
    lorenz_scale = 0.4
    aM_smoothing = 0.9
    presetName$ = "Stochastic"
elsif preset = 6
    # Extreme Butterfly
    pitch_mode = 1
    logistic_r = 3.95
    logistic_depth = 0.45
    lorenz_sigma = 12.0
    lorenz_rho = 35.0
    lorenz_scale = 0.8
    aM_smoothing = 0.7
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Chaotic Prosody Manipulation ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
if pitch_mode = 1
    appendInfoLine: "Pitch: Logistic map (r=", logistic_r, ", depth=", logistic_depth, ")"
else
    appendInfoLine: "Pitch: OU process (θ=", oU_theta, ", σ=", oU_sigma, ")"
endif
appendInfoLine: "AM: Lorenz (σ=", lorenz_sigma, ", ρ=", lorenz_rho, ", β=", lorenz_beta, ")"
appendInfoLine: ""

# === Extract Base Pitch ===
appendInfoLine: "Analyzing pitch..."
selectObject: original
To Pitch: 0, 75, 600
pitch = selected("Pitch")
f0_base = Get mean: 0, 0, "Hertz"

if f0_base = undefined
    f0_base = 150
endif

appendInfoLine: "Base F0: ", fixed$(f0_base, 1), " Hz"

# === Create Manipulation ===
selectObject: original
manipulation = To Manipulation: 0.01, 75, 600

selectObject: manipulation
Extract pitch tier
origPitchTier = selected("PitchTier")
removeObject: origPitchTier

# Create new PitchTier
Create PitchTier: sound_name$ + "_chaotic", 0, duration
pitchtier_new = selected("PitchTier")

# === Generate Chaotic Pitch Contour ===
appendInfoLine: ""
appendInfoLine: "Generating chaotic pitch..."

dt = 1 / control_rate
n_points = floor(duration * control_rate)

# Store for visualization
maxVizPoints = min(n_points, 500)
vizTimes# = zero#(maxVizPoints)
vizPitch# = zero#(maxVizPoints)
vizChaosX# = zero#(maxVizPoints)

if pitch_mode = 1
    # Logistic map chaos
    x = 0.5
    for i from 1 to n_points
        t = (i - 1) * dt
        
        # Logistic map iteration
        x = logistic_r * x * (1 - x)
        
        # Map to pitch factor
        factor = 1 + logistic_depth * (2 * x - 1)
        f0 = f0_base * factor
        
        # Store for visualization (evenly spaced)
        vizIdx = floor((i - 1) / n_points * maxVizPoints) + 1
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            vizTimes#[vizIdx] = t
            vizPitch#[vizIdx] = f0
            vizChaosX#[vizIdx] = x
        endif
        
        selectObject: pitchtier_new
        Add point: t, f0
    endfor
else
    # Ornstein-Uhlenbeck process
    f0 = f0_base
    for i from 1 to n_points
        t = (i - 1) * dt
        
        # OU process
        noise = randomGauss(0, 1)
        df0 = oU_theta * (f0_base - f0) * dt + oU_sigma * sqrt(dt) * noise
        f0 = f0 + df0
        
        # Clamp to range
        if f0 < 50
            f0 = 50
        elsif f0 > 500
            f0 = 500
        endif
        
        # Store for visualization
        vizIdx = floor((i - 1) / n_points * maxVizPoints) + 1
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            vizTimes#[vizIdx] = t
            vizPitch#[vizIdx] = f0
            vizChaosX#[vizIdx] = (f0 - f0_base) / 100 + 0.5
        endif
        
        selectObject: pitchtier_new
        Add point: t, f0
    endfor
endif

# === Replace Pitch Tier ===
selectObject: manipulation, pitchtier_new
Replace pitch tier
removeObject: pitchtier_new

# === Resynthesize Pitch ===
appendInfoLine: "Resynthesizing pitch..."
selectObject: manipulation
sound_repitched = Get resynthesis (overlap-add)
Rename: sound_name$ + "_repitched"

# === Generate Lorenz AM Envelope ===
appendInfoLine: "Generating Lorenz amplitude envelope..."

Create Sound from formula: sound_name$ + "_am_env", 1, 0, duration, sampling_rate, "0"
am_envelope = selected("Sound")

# Initialize Lorenz system
lx = 1.0
ly = 1.0
lz = 1.0

# Store Lorenz trajectory for visualization
maxLorenzPoints = 500
lorenzX# = zero#(maxLorenzPoints)
lorenzY# = zero#(maxLorenzPoints)
lorenzZ# = zero#(maxLorenzPoints)
lorenzAM# = zero#(maxLorenzPoints)
lorenzTimes# = zero#(maxLorenzPoints)

dt_lorenz = dt
smoothed_value = 0.5
lorenzIdx = 0

# RK2 integration
controlInterval = floor(sampling_rate / control_rate)
if controlInterval < 1
    controlInterval = 1
endif

# Calculate how often to store for visualization
totalControlUpdates = floor(n_samples / controlInterval)
lorenzStoreInterval = ceiling(totalControlUpdates / maxLorenzPoints)
if lorenzStoreInterval < 1
    lorenzStoreInterval = 1
endif
lorenzUpdateCount = 0

for i from 1 to n_samples
    t = (i - 1) / sampling_rate
    
    # Update Lorenz at control rate
    if i = 1 or ((i - 1) mod controlInterval) = 0
        lorenzUpdateCount = lorenzUpdateCount + 1
        
        # RK2 midpoint method
        dx1 = lorenz_sigma * (ly - lx)
        dy1 = lx * (lorenz_rho - lz) - ly
        dz1 = lx * ly - lorenz_beta * lz
        
        x_mid = lx + 0.5 * dt_lorenz * dx1
        y_mid = ly + 0.5 * dt_lorenz * dy1
        z_mid = lz + 0.5 * dt_lorenz * dz1
        
        dx2 = lorenz_sigma * (y_mid - x_mid)
        dy2 = x_mid * (lorenz_rho - z_mid) - y_mid
        dz2 = x_mid * y_mid - lorenz_beta * z_mid
        
        lx = lx + dt_lorenz * dx2
        ly = ly + dt_lorenz * dy2
        lz = lz + dt_lorenz * dz2
        
        # Normalize z to [0, 1]
        z_normalized = (lz - 20) / 30
        if z_normalized < 0
            z_normalized = 0
        elsif z_normalized > 1
            z_normalized = 1
        endif
        
        # Smooth
        smoothed_value = aM_smoothing * smoothed_value + (1 - aM_smoothing) * z_normalized
        
        # Store for visualization at regular intervals
        if (lorenzUpdateCount mod lorenzStoreInterval) = 0 and lorenzIdx < maxLorenzPoints
            lorenzIdx = lorenzIdx + 1
            lorenzX#[lorenzIdx] = lx
            lorenzY#[lorenzIdx] = ly
            lorenzZ#[lorenzIdx] = lz
            lorenzAM#[lorenzIdx] = smoothed_value
            lorenzTimes#[lorenzIdx] = t
        endif
    endif
    
    # Calculate AM value
    am_value = 0.5 + lorenz_scale * (smoothed_value - 0.5)
    
    # Fade out
    if t > duration - fadeout_duration
        fade = (duration - t) / fadeout_duration
        am_value = am_value * fade
    endif
    
    selectObject: am_envelope
    Set value at sample number: 1, i, am_value
endfor

appendInfoLine: "Lorenz points stored: ", lorenzIdx

# === Apply AM ===
appendInfoLine: "Applying amplitude modulation..."
selectObject: sound_repitched
Formula: ~ self * object[am_envelope, col]
result = selected("Sound")
Rename: sound_name$ + "_chaotic_" + presetName$
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Chaotic Prosody: " + sound_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.3
    Select inner viewport: 0.6, 7.6, 0.7, 1.2
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.4, 2.1
    Select inner viewport: 0.6, 7.6, 1.5, 2.0
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Chaotic"
    Text bottom: "yes", "Time (s)"
    
    # Pitch contour
    Select outer viewport: 0, 8, 2.3, 3.3
    Select inner viewport: 0.6, 7.6, 2.4, 3.2
    
    # Find pitch range
    minP = vizPitch#[1]
    maxP = vizPitch#[1]
    for vp from 2 to maxVizPoints
        if vizPitch#[vp] > 0
            if vizPitch#[vp] < minP
                minP = vizPitch#[vp]
            endif
            if vizPitch#[vp] > maxP
                maxP = vizPitch#[vp]
            endif
        endif
    endfor
    
    pMargin = (maxP - minP) * 0.1
    if pMargin < 10
        pMargin = 10
    endif
    
    Axes: 0, duration, minP - pMargin, maxP + pMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, minP - pMargin, maxP + pMargin
    
    # Base F0 line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, f0_base, duration, f0_base
    Solid line
    
    # Draw pitch curve
    Colour: "{0.5, 0.5, 0.8}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizPitch#[vp - 1], vizTimes#[vp], vizPitch#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (Hz)"
    
    # Lorenz XY projection (attractor view)
    Select outer viewport: 0, 4, 3.5, 5.0
    Select inner viewport: 0.6, 3.8, 3.6, 4.9
    
    if lorenzIdx > 1
        # Find range
        minLX = lorenzX#[1]
        maxLX = lorenzX#[1]
        minLY = lorenzY#[1]
        maxLY = lorenzY#[1]
        for lp from 2 to lorenzIdx
            if lorenzX#[lp] < minLX
                minLX = lorenzX#[lp]
            endif
            if lorenzX#[lp] > maxLX
                maxLX = lorenzX#[lp]
            endif
            if lorenzY#[lp] < minLY
                minLY = lorenzY#[lp]
            endif
            if lorenzY#[lp] > maxLY
                maxLY = lorenzY#[lp]
            endif
        endfor
        
        lMargin = max((maxLX - minLX), (maxLY - minLY)) * 0.1
        if lMargin < 1
            lMargin = 1
        endif
        
        Axes: minLX - lMargin, maxLX + lMargin, minLY - lMargin, maxLY + lMargin
        Paint rectangle: "{0.95, 0.95, 0.95}", minLX - lMargin, maxLX + lMargin, minLY - lMargin, maxLY + lMargin
        
        # Draw attractor
        Colour: "{0.7, 0.4, 0.5}"
        for lp from 2 to lorenzIdx
            Draw line: lorenzX#[lp - 1], lorenzY#[lp - 1], lorenzX#[lp], lorenzY#[lp]
        endfor
    else
        Axes: -20, 20, -30, 30
        Paint rectangle: "{0.95, 0.95, 0.95}", -20, 20, -30, 30
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Lorenz Y"
    Text bottom: "yes", "Lorenz X"
    
    # AM envelope
    Select outer viewport: 4, 8, 3.5, 5.0
    Select inner viewport: 4.4, 7.6, 3.6, 4.9
    
    Axes: 0, duration, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, 1.1
    
    # Draw AM
    if lorenzIdx > 1
        Colour: "{0.5, 0.7, 0.5}"
        for lp from 2 to lorenzIdx
            Draw line: lorenzTimes#[lp - 1], lorenzAM#[lp - 1], lorenzTimes#[lp], lorenzAM#[lp]
        endfor
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "AM Env"
    Text bottom: "yes", "Time (s)"
    
    # Stats
    Select outer viewport: 0, 8, 5.1, 5.4
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    if pitch_mode = 1
        pitchText$ = "Logistic r=" + fixed$(logistic_r, 2)
    else
        pitchText$ = "OU θ=" + fixed$(oU_theta, 1) + " σ=" + fixed$(oU_sigma, 0)
    endif
    Text: 0.5, "centre", 0.5, "half", pitchText$ + " | Lorenz σ=" + fixed$(lorenz_sigma, 0) + " ρ=" + fixed$(lorenz_rho, 0) + " β=" + fixed$(lorenz_beta, 2) + " | Base F0=" + fixed$(f0_base, 0) + " Hz"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: pitch, manipulation, am_envelope

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result