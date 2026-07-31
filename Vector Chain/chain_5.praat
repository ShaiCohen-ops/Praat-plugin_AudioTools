Erase all
# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 5 ---"

# --- Define Paths (Absolute via preferencesDirectory$) ---
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

path1$ = pluginPath$ + "Distortion/Full-Wave_Rectifier_Abs.praat"
path2$ = pluginPath$ + "Time & Granular/Brownian_Motion_Texture_Generator.praat"
path3$ = pluginPath$ + "Spatial & Surround/8-Channel_Movements.praat"

# ==============================================================================
# STEP 1: Full-Wave Rectifier (Distortion)
# ==============================================================================
selectObject: initial_sound
# Args (8): Preset, Dc_handling, Output_level, Scale_peak, Show_spectrum,
#           Spectrum_reference, Viz, Play
# FIX: v0.4/v0.4b added Dc_handling, Output_level and Spectrum_reference
# (optionmenus, so exact label strings are required) and renamed the
# Preset options. Old call had 5 args; v0.4b requires 8.
# Dc_handling = "Raw rectification (v0.2/v0.3)" and Output_level =
# "Normalize to target" reproduce the old, always-scale-to-peak behavior.
runScript: path1$, "Standard level (0.95 peak)", "Raw rectification (v0.2/v0.3)", "Normalize to target", 0.95, 0, "Match levels (isolates harmonic change)", 0, 0

# Select Output
sound2 = selected("Sound")
appendInfoLine: "Step 1: Full-Wave Rectifier complete."

# ==============================================================================
# STEP 2: Brownian Motion Texture Generator
# ==============================================================================
selectObject: sound2
# Args (17): Preset, GrainDur, OutDur, Dens, TimeStep, TimeDrift, SpatEnable,
# SpatStep, SpatDrift, ClampMode, AmpScale, RandPos, FadeDur, FadeOut, Normalize, Viz, Play
runScript: path2$, "Dense Cloud", 0.05, 10.0, 20, 0.1, 0.0, 1, 0.15, 0.0, "Clamp (matches v0.2 — pins at edges)", 0.7, 1, 0.005, 2.0, 1, 0, 0

# Select Output
sound3 = selected("Sound")
appendInfoLine: "Step 2: Brownian Texture complete."

# ==============================================================================
# STEP 3: 8-Channel Spatial Movements
# ==============================================================================
selectObject: sound3

# Args (16):
# 1. Pattern ("8. [SPATIAL] Circular rotation")
# 2. Motion_speed (0.2)
# 3. Frequency_hz (2.0)
# 4. Fadein_time (1.0)
# 5. Exponent (1.0)
# 6. Path_radius (0.7)
# 7. Source_focus (2.0)
# 8. Custom_x (0.0)
# 9. Custom_y (0.0)
# 10. Floor_db (-60.0)
# 11. Scale_peak (0.95)
# 12. Number_of_points (100)
# 13. Random_seed (1)
# 14. Output_format ("8 channels - octophonic (Ch1-Ch8)")
# 15. Draw_visualization (0)
# 16. Play_result (1)
#
# FIX: v0.4/v0.5 dropped Min_volume, Max_volume and Amplitude (old
# absolute-dB fields) in favor of Floor_db (relative dB) and Scale_peak
# (peak target), inserted Path_radius and Source_focus after Exponent,
# and added an Output_format optionmenu. Old call had 14 args; v0.5
# requires 16. Pattern's label also changed to include the [SPATIAL]
# tag. Output_format = octophonic is required since the code below
# branches on nch > 2 to extract channels 1 & 2.
runScript: path3$, "8. [SPATIAL] Circular rotation", 0.2, 2.0, 1.0, 1.0, 0.7, 2.0, 0.0, 0.0, -60.0, 0.95, 100, 1, "8 channels - octophonic (Ch1-Ch8)", 0, 1

# Select Output
sound4 = selected("Sound")

# ==============================================================================
# VISUALIZATION (Simple Text)
# ==============================================================================
Erase all
Select outer viewport: 0, 8, 0.1, 3.5
Axes: 0, 10, 0, 10
Font size: 16
Text: 5, "centre", 5, "half", "Full-Wave Rectifier -> Brownian Motion -> 8-Channel Movements"

selectObject: sound4
