Erase all
# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 2 ---"

# --- Define Paths (Relative) ---
# This assumes this script is saved in a subfolder like "plugin_AudioTools/Signal Chain/"
path1$ = "../Pitch/Spiral_Pitch_Dance.praat"
path2$ = "../AI & Adaptive/Neural Ambient Drone Designer.praat"
path3$ = "../Spatial & Surround/8-channel speed deviations.praat"

# ==============================================================================
# STEP 1: Spiral Pitch Dance
# ==============================================================================
selectObject: initial_sound
runScript: path1$, "Manual (configure below)", 2, 24, 1.5, 0.005, 50, 1200, 0, 0

# FIX: Force selection by name (Removed the "if not selected" check)
expected_name_1$ = initial_name$ + "_spiral_Manual"
selectObject: "Sound " + expected_name_1$
sound2 = selected("Sound")
appendInfoLine: "Step 1: Spiral Pitch Dance complete."

# ==============================================================================
# STEP 2: Neural Ambient Drone Designer
# ==============================================================================
selectObject: sound2
runScript: path2$, "Manual (Use Settings Below)", 20.0, 3, 20, 1, 0.15, "Octaves only", 100, 3, 10, 1, 0.7, 0

# FIX: Force selection by name
expected_name_2$ = expected_name_1$ + "_NeuralDrone_stereo"
selectObject: "Sound " + expected_name_2$
sound3 = selected("Sound")
appendInfoLine: "Step 2: Neural Drone complete."

# ==============================================================================
# STEP 3: 8-Channel Speed Deviations
# ==============================================================================
selectObject: sound3
runScript: path3$, "Custom (use mode below)", "Automatic (using factor)", 0.15, 0.85, 0.88, 0.91, 0.94, 1.06, 1.09, 1.12, 1.15, 0.80, 1.20, 42, 75, 600, 1, 44100, 0, 1

appendInfoLine: "Step 3: 8-Channel Deviations complete. Chain finished."
# ==============================================================================
# VISUALIZATION (Simple Text)
# ==============================================================================
Erase all
Select outer viewport: 0, 8, 0.1, 3.5
Axes: 0, 10, 0, 10
Font size: 16
Text: 5, "centre", 5, "half", "Spiral Pitch Dance -> Neural Ambient Drone -> 8-Channel Deviations"

# The final output in Chain 2 was 'sound3', so we select that
selectObject: sound3