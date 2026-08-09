Erase all
# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 5 ---"

# --- Define Paths (Praat 7 compatible) ---
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

path1$ = pluginPath$ + "Distortion/Full-Wave_Rectifier_Abs.praat"
path2$ = pluginPath$ + "Time & Granular/Brownian_Motion_Texture_Generator.praat"
path3$ = pluginPath$ + "Spatial & Surround/8-Channel_Movements.praat"

# Praat 7 / script-relative fallback
if not fileReadable(path1$)
    path1$ = defaultDirectory$ + "/../Distortion/Full-Wave_Rectifier_Abs.praat"
endif
if not fileReadable(path2$)
    path2$ = defaultDirectory$ + "/../Time & Granular/Brownian_Motion_Texture_Generator.praat"
endif
if not fileReadable(path3$)
    path3$ = defaultDirectory$ + "/../Spatial & Surround/8-Channel_Movements.praat"
endif

path1$ = replace_regex$(path1$, "\\", "/", 0)
path2$ = replace_regex$(path2$, "\\", "/", 0)
path3$ = replace_regex$(path3$, "\\", "/", 0)

if not fileReadable(path1$)
    exitScript: "Cannot find Full-Wave_Rectifier_Abs.praat"
endif
if not fileReadable(path2$)
    exitScript: "Cannot find Brownian_Motion_Texture_Generator.praat"
endif
if not fileReadable(path3$)
    exitScript: "Cannot find 8-Channel_Movements.praat"
endif

# ==============================================================================
# STEP 1: Full-Wave Rectifier (Distortion)
# ==============================================================================
selectObject: initial_sound

# Full-Wave Rectifier v0.4b parameters (8 args):
# Preset, Dc_handling, Output_level, Scale_peak, Show_spectrum,
# Spectrum_reference, Draw_visualization, Play_result
runScript: path1$, "Standard level (0.95 peak)", "Raw rectification (v0.2/v0.3)", "Normalize to target", 0.95, 0, "Match levels (isolates harmonic change)", 0, 0

# Select Output
sound2 = selected("Sound")
appendInfoLine: "Step 1: Full-Wave Rectifier complete."

# ==============================================================================
# STEP 2: Brownian Motion Texture Generator
# ==============================================================================
selectObject: sound2

# Brownian Motion Texture v0.3 parameters (17 args)
runScript: path2$, "Dense Cloud", 0.05, 10.0, 20, 0.1, 0.0, 1, 0.15, 0.0, "Clamp (matches v0.2 — pins at edges)", 0.7, 1, 0.005, 2.0, 1, 0, 0

# Select Output
sound3 = selected("Sound")
appendInfoLine: "Step 2: Brownian Texture complete."

# ==============================================================================
# STEP 3: 8-Channel Spatial Movements
# ==============================================================================
selectObject: sound3

# 8-Channel Spatial Movements v0.5 parameters (16 args)
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
