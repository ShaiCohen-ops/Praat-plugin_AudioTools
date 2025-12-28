# ============================================================
# Praat AudioTools - Frequency-Dependent Phase Manipulation
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Manipulates spectral phase in frequency-dependent patterns,
#   creating comb filtering, phaser-like effects, or formant
#   resonances. Processes L/R with different phase amounts
#   to create wide stereo imaging.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Phase Manipulation Stereo
    optionmenu Preset: 1
        option Custom
        option Subtle Comb
        option Wide Phaser
        option Chaotic Texture
        option Spectral Blur
        option Formant Resonance
    comment === Phase Parameters ===
    positive Phase_amount 50.0
    comment (higher = more dramatic effect)
    positive Stereo_width 0.2
    comment (difference between L/R: 0.1-1.0)
    optionmenu Phase_mode: 1
        option Comb filter (periodic notches)
        option Chaotic texture (multiple periods)
        option Spectral blur (randomized)
        option Formant-like resonances
    comment === Output ===
    real Dry_wet 1.0
    comment (0 = dry, 1 = wet)
    positive Scale_peak 0.95
    boolean Play_output 1
endform

# --- APPLY PRESETS ---
if preset = 2
    phase_amount = 20
    stereo_width = 0.15
    phase_mode = 1
elsif preset = 3
    phase_amount = 60
    stereo_width = 0.4
    phase_mode = 1
elsif preset = 4
    phase_amount = 80
    stereo_width = 0.3
    phase_mode = 2
elsif preset = 5
    phase_amount = 50
    stereo_width = 0.25
    phase_mode = 3
elsif preset = 6
    phase_amount = 40
    stereo_width = 0.2
    phase_mode = 4
endif

# --- INPUT VALIDATION ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original_name$ = selected$("Sound")
original_id = selected("Sound")

selectObject: original_id
n_channels = Get number of channels
duration = Get total duration
sampleRate = Get sampling frequency

writeInfoLine: "=== Stereo Phase Manipulation ==="
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Phase amount: ", phase_amount
appendInfoLine: "Stereo width: ", stereo_width
appendInfoLine: ""

# Convert to mono if stereo
selectObject: original_id
if n_channels > 1
    mono_sound = Convert to mono
else
    mono_sound = Copy: "mono_temp"
endif

# Keep dry copy for mixing
selectObject: mono_sound
dry_copy = Copy: "dry"

# --- BUILD PHASE SHIFT FORMULAS ---
# Phase shift function varies by mode
amtL$ = fixed$(phase_amount, 4)
amtR$ = fixed$(phase_amount * (1 + stereo_width), 4)

if phase_mode = 1
    # Comb filter - single sine modulation
    shiftL$ = amtL$ + " * sin(2 * pi * x / 200)"
    shiftR$ = amtR$ + " * sin(2 * pi * x / 200)"
elsif phase_mode = 2
    # Chaotic - multiple inharmonic periods
    shiftL$ = amtL$ + " * (sin(2*pi*x/147) + 0.7*sin(2*pi*x/283) + 0.4*sin(2*pi*x/521))"
    shiftR$ = amtR$ + " * (sin(2*pi*x/147) + 0.7*sin(2*pi*x/283) + 0.4*sin(2*pi*x/521))"
elsif phase_mode = 3
    # Blur - product of sines creates pseudo-random pattern
    shiftL$ = amtL$ + " * sin(x/37) * sin(x/113)"
    shiftR$ = amtR$ + " * sin(x/37) * sin(x/113)"
elsif phase_mode = 4
    # Formant - Gaussian bumps at speech formant frequencies
    shiftL$ = amtL$ + " * (exp(-((x-800)/300)^2) + exp(-((x-1500)/400)^2) + exp(-((x-2500)/500)^2))"
    shiftR$ = amtR$ + " * (exp(-((x-800)/300)^2) + exp(-((x-1500)/400)^2) + exp(-((x-2500)/500)^2))"
endif

# --- PROCESS LEFT CHANNEL ---
appendInfoLine: "Processing left channel..."

selectObject: mono_sound
spectrum_L = To Spectrum: "yes"

selectObject: spectrum_L
matrix_L = To Matrix
Rename: "srcL"

selectObject: matrix_L
matrix_L_shifted = Copy: "shiftedL"

# Apply phase rotation: 
# new_real = mag * cos(phase + shift)
# new_imag = mag * sin(phase + shift)
selectObject: matrix_L_shifted
Formula: "if row = 1 then sqrt(Matrix_srcL[1,col]^2 + Matrix_srcL[2,col]^2) * cos(arctan2(Matrix_srcL[2,col], Matrix_srcL[1,col]) + " + shiftL$ + ") else sqrt(Matrix_srcL[1,col]^2 + Matrix_srcL[2,col]^2) * sin(arctan2(Matrix_srcL[2,col], Matrix_srcL[1,col]) + " + shiftL$ + ") fi"

selectObject: matrix_L_shifted
spectrum_L_mod = To Spectrum
Rename: "specL"

selectObject: spectrum_L_mod
sound_L = To Sound

appendInfoLine: "  Done"

# --- PROCESS RIGHT CHANNEL ---
appendInfoLine: "Processing right channel..."

selectObject: mono_sound
spectrum_R = To Spectrum: "yes"

selectObject: spectrum_R
matrix_R = To Matrix
Rename: "srcR"

selectObject: matrix_R
matrix_R_shifted = Copy: "shiftedR"

selectObject: matrix_R_shifted
Formula: "if row = 1 then sqrt(Matrix_srcR[1,col]^2 + Matrix_srcR[2,col]^2) * cos(arctan2(Matrix_srcR[2,col], Matrix_srcR[1,col]) + " + shiftR$ + ") else sqrt(Matrix_srcR[1,col]^2 + Matrix_srcR[2,col]^2) * sin(arctan2(Matrix_srcR[2,col], Matrix_srcR[1,col]) + " + shiftR$ + ") fi"

selectObject: matrix_R_shifted
spectrum_R_mod = To Spectrum
Rename: "specR"

selectObject: spectrum_R_mod
sound_R = To Sound

appendInfoLine: "  Done"

# --- TRIM TO ORIGINAL DURATION ---
selectObject: sound_L
durL = Get total duration
if durL > duration
    trimL = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: sound_L
    sound_L = trimL
endif

selectObject: sound_R
durR = Get total duration
if durR > duration
    trimR = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: sound_R
    sound_R = trimR
endif

# --- DRY/WET MIX ---
if dry_wet < 1
    appendInfoLine: "Mixing dry/wet..."
    
    wetStr$ = fixed$(dry_wet, 4)
    dryStr$ = fixed$(1 - dry_wet, 4)
    
    selectObject: sound_L
    Rename: "wetL"
    Formula: "self * " + wetStr$ + " + Sound_dry[] * " + dryStr$
    
    selectObject: sound_R
    Rename: "wetR"
    Formula: "self * " + wetStr$ + " + Sound_dry[] * " + dryStr$
endif

# --- COMBINE TO STEREO ---
selectObject: sound_L
plusObject: sound_R
stereo_sound = Combine to stereo

# Name based on mode
if phase_mode = 1
    mode_name$ = "Comb"
elsif phase_mode = 2
    mode_name$ = "Chaos"
elsif phase_mode = 3
    mode_name$ = "Blur"
else
    mode_name$ = "Formant"
endif

selectObject: stereo_sound
Rename: original_name$ + "_phase_" + mode_name$
Scale peak: scale_peak

# --- CLEANUP ---
removeObject: mono_sound, dry_copy
removeObject: spectrum_L, matrix_L, matrix_L_shifted, spectrum_L_mod, sound_L
removeObject: spectrum_R, matrix_R, matrix_R_shifted, spectrum_R_mod, sound_R

appendInfoLine: ""
appendInfoLine: "Complete!"
appendInfoLine: "Mode: ", mode_name$
appendInfoLine: "Stereo width: ", stereo_width

selectObject: stereo_sound
if play_output
    Play
endif