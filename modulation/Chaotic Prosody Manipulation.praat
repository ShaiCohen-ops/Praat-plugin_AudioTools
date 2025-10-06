# ============================================================
# Praat AudioTools - Chaotic Prosody Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Modulation or vibrato-based processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ===================================================================
#  Chaotic Prosody Manipulation Script
#  - Pitch: Logistic chaos or mean-reverting Brownian (OU) in Hz
#  - Amplitude: Lorenz-driven AM with smooth fade-out
# ===================================================================

form Chaotic Prosody Parameters
    comment === PITCH MODULATION ===
    optionmenu pitch_mode: 1
        option Logistic chaos (multiplicative)
        option Mean-reverting Brownian (OU process)
    positive control_rate 100
    comment Logistic chaos parameters:
    real logistic_r 3.9
    real logistic_depth 0.35
    comment OU process parameters (Hz):
    real ou_theta 1.5
    real ou_sigma 20.0
    comment === AMPLITUDE MODULATION ===
    comment Lorenz system parameters:
    real lorenz_sigma 10.0
    real lorenz_rho 28.0
    real lorenz_beta 2.667
    real lorenz_scale 0.6
    real am_smoothing 0.85
    comment === FADE OUT ===
    real fadeout_duration 0.5
endform

# Get selected Sound
sound = selected("Sound")
sound_name$ = selected$("Sound")
duration = Get total duration
sampling_rate = Get sampling frequency
n_samples = Get number of samples

# ===================================================================
# PITCH EXTRACTION & MANIPULATION
# ===================================================================

selectObject: sound
To Pitch: 0, 75, 600

pitch = selected("Pitch")
f0_base = Get mean: 0, 0, "Hertz"

if f0_base = undefined
    f0_base = 150
endif

# Create Manipulation object
selectObject: sound
To Manipulation: 0.01, 75, 600
manipulation = selected("Manipulation")

# Extract original PitchTier and remove it
pitchtier_original = Extract pitch tier
Remove

# Create new PitchTier
selectObject: manipulation
Create PitchTier: sound_name$ + "_chaotic", 0, duration
pitchtier_new = selected("PitchTier")

# Generate chaotic/stochastic pitch contour
dt = 1 / control_rate
n_points = floor(duration * control_rate)

if pitch_mode = 1
    # Logistic chaos (multiplicative in log-space)
    x = 0.5
    for i from 1 to n_points
        t = (i - 1) * dt
        # Logistic map
        x = logistic_r * x * (1 - x)
        # Map to multiplicative factor
        factor = 1 + logistic_depth * (2 * x - 1)
        f0 = f0_base * factor
        
        selectObject: pitchtier_new
        Add point: t, f0
    endfor
else
    # Mean-reverting Brownian (OU process in Hz)
    f0 = f0_base
    for i from 1 to n_points
        t = (i - 1) * dt
        # OU process: df0 = theta*(f0_base - f0)*dt + sigma*sqrt(dt)*N(0,1)
        noise = randomGauss(0, 1)
        df0 = ou_theta * (f0_base - f0) * dt + ou_sigma * sqrt(dt) * noise
        f0 = f0 + df0
        
        # Clip to reasonable range
        if f0 < 50
            f0 = 50
        elsif f0 > 500
            f0 = 500
        endif
        
        selectObject: pitchtier_new
        Add point: t, f0
    endfor
endif

# Replace pitch tier in manipulation
selectObject: manipulation
plus pitchtier_new
Replace pitch tier
removeObject: pitchtier_new

# Resynthesize with modified pitch
selectObject: manipulation
sound_repitched = Get resynthesis (overlap-add)
Rename: sound_name$ + "_repitched"

# ===================================================================
# AMPLITUDE MODULATION (LORENZ)
# ===================================================================

# Initialize Lorenz system
x = 1.0
y = 1.0
z = 1.0

# Create amplitude envelope
Create Sound from formula: sound_name$ + "_am_env", 1, 0, duration, sampling_rate, "0"
am_envelope = selected("Sound")

# RK2 integration of Lorenz system
dt_lorenz = dt
smoothed_value = 0.5

for i from 1 to n_samples
    t = (i - 1) / sampling_rate
    
    # Update Lorenz system at control rate
    if i = 1 or (i - 1) mod floor(sampling_rate / control_rate) = 0
        # RK2 (midpoint method)
        # k1
        dx1 = lorenz_sigma * (y - x)
        dy1 = x * (lorenz_rho - z) - y
        dz1 = x * y - lorenz_beta * z
        
        # Midpoint
        x_mid = x + 0.5 * dt_lorenz * dx1
        y_mid = y + 0.5 * dt_lorenz * dy1
        z_mid = z + 0.5 * dt_lorenz * dz1
        
        # k2
        dx2 = lorenz_sigma * (y_mid - x_mid)
        dy2 = x_mid * (lorenz_rho - z_mid) - y_mid
        dz2 = x_mid * y_mid - lorenz_beta * z_mid
        
        # Update
        x = x + dt_lorenz * dx2
        y = y + dt_lorenz * dy2
        z = z + dt_lorenz * dz2
        
        # Normalize z to [0, 1] and smooth
        z_normalized = (z - 20) / 30
        if z_normalized < 0
            z_normalized = 0
        elsif z_normalized > 1
            z_normalized = 1
        endif
        
        # One-pole smoothing
        smoothed_value = am_smoothing * smoothed_value + (1 - am_smoothing) * z_normalized
    endif
    
    # Scale to AM envelope
    am_value = 0.5 + lorenz_scale * (smoothed_value - 0.5)
    
    # Apply fade-out
    if t > duration - fadeout_duration
        fade = (duration - t) / fadeout_duration
        am_value = am_value * fade
    endif
    
    selectObject: am_envelope
    Set value at sample number: 1, i, am_value
endfor

# Apply AM to repitched sound
selectObject: sound_repitched
Formula: "self * object[am_envelope, col]"
sound_final = selected("Sound")
Rename: sound_name$ + "_chaotic"
Play

# ===================================================================
# CLEANUP & SELECT OUTPUT
# ===================================================================

# Clean up intermediate objects
removeObject: pitch, manipulation, am_envelope

selectObject: sound_final

writeInfoLine: "✓ Chaotic prosody manipulation complete!"
appendInfoLine: "  Control rate: ", control_rate, " Hz"
appendInfoLine: "  Pitch mode: ", pitch_mode$
appendInfoLine: "  Base F0: ", fixed$(f0_base, 1), " Hz"
appendInfoLine: "  Duration: ", fixed$(duration, 3), " s"