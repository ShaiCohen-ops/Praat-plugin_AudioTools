# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 5 ---"

# --- Define Paths (Relative) ---
path1$ = "../Distortion/Full-Wave Rectifier Abs.praat"
path2$ = "../Time & Granular/Brownian Motion Texture Generator.praat"
path3$ = "../Spatial & Surround/8-Channel movements.praat"

# ==============================================================================
# STEP 1: Full-Wave Rectifier (Distortion)
# ==============================================================================
selectObject: initial_sound
# Args (4): Preset, Scale_peak, Viz, Play
runScript: path1$, "Default (0.95 peak)", 0.95, 0, 0

# Select Output
sound2 = selected("Sound")
appendInfoLine: "Step 1: Full-Wave Rectifier complete."

# ==============================================================================
# STEP 2: Brownian Motion Texture Generator
# ==============================================================================
selectObject: sound2
# Args (15): Preset, GrainDur, OutDur, Dens, TimeStep, TimeDrift, SpatEnable, 
# SpatStep, SpatDrift, AmpScale, RandPos, FadeDur, FadeOut, Viz, Play
runScript: path2$, "Dense Cloud", 0.05, 10.0, 20, 0.1, 0.0, 1, 0.15, 0.0, 0.7, 1, 0.005, 2.0, 0, 0

# Select Output
sound3 = selected("Sound")
appendInfoLine: "Step 2: Brownian Texture complete."

# ==============================================================================
# STEP 3: 8-Channel Spatial Movements
# ==============================================================================
selectObject: sound3

# FIXED: Now providing all 14 arguments required by the new script
# 1. Pattern ("8. Circular rotation")
# 2. Motion_speed (0.2)
# 3. Frequency_hz (2.0 - default)
# 4. Fadein_time (1.0 - default)
# 5. Min_volume (60 - from your settings)
# 6. Max_volume (85 - from your settings)
# 7. Amplitude (50.0 - default)
# 8. Exponent (1.0 - default)
# 9. Custom_x (0.5 - default)
# 10. Custom_y (0.5 - default)
# 11. Number_of_points (100 - default)
# 12. Random_seed (1 - default)
# 13. Draw_visualization (0 - from your settings)
# 14. Play_result (1 - from your settings)

runScript: path3$, "8. Circular rotation", 0.2, 2.0, 1.0, 60, 85, 50.0, 1.0, 0.5, 0.5, 100, 1, 0, 1

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