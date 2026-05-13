# ============================================================
# Praat AudioTools - Chain 1
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   This script executes a sequential processing chain using four 
#   AudioTools modules:
#   1. MDS Space Navigator - Auto-segments and reorders audio based on similarity.
#   2. Spectral Freeze & Glitch - Applies spectral freezing and glitch effects.
#   3. Crystalline Cascade - Adds a subtle flutter reverberation cascade.
#   4. 4-Channel Canon - Distributes the result into a quadraphonic canon.
#
#   The script concludes by generating a visual text summary of the 
#   pipeline in the Praat Picture window.
# ============================================================

Erase all
# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 1 (Relative Paths) ---"

# --- Define Paths (Relative) ---
# Assumes this script is in "plugin_AudioTools/_Chains/"
path1$ = "../Time & Granular/MDS_Space_Navigator.praat"
path2$ = "../Time & Granular/Spectral_Freeze_&_Glitch.praat"
path3$ = "../Reverb/Crystalline_Cascade.praat"
path4$ = "../Spatial & Surround/4-Channel_Canon.praat"

# ==============================================================================
# STEP 1: MDS Space Navigator
# ==============================================================================
selectObject: initial_sound
# Note: Using "Nearest neighbor..." text string for safety. 10 arguments matching form.
runScript: path1$, 25, 0.1, 0.1, "Formants (Vowel Quality)", 5500, 5, 12, "Nearest neighbor chain (most similar next)", 0.05, 0

# FIX: Force selection by name (MDS always appends "_reordered")
expected_name_1$ = initial_name$ + "_reordered"
selectObject: "Sound " + expected_name_1$
sound2 = selected("Sound")
appendInfoLine: "Step 1: MDS Space Navigator complete."

# ==============================================================================
# STEP 2: Spectral Freeze & Glitch
# ==============================================================================
selectObject: sound2
# Visualization (Arg 9) is set to 0, so the sound usually stays selected.
# However, for safety, we track the name logic: Input + "_glitch"
runScript: path2$, "Default (balanced)", 12, 25, 0.5, 1.5, 3, 0.1, 0.9, 0, 0

expected_name_2$ = expected_name_1$ + "_glitch"
# We check if it exists;
# if not, we assume the previous sound is still the active one (some presets might vary)
if selected$("Sound") <> expected_name_2$
    selectObject: "Sound " + expected_name_2$
endif
sound3 = selected("Sound")
appendInfoLine: "Step 2: Spectral Freeze complete."

# ==============================================================================
# STEP 3: Crystalline Cascade
# ==============================================================================
selectObject: sound3
# Visualization (Arg 13) is set to 0
runScript: path3$, "Subtle Flutter", 2.0, 800, 0.08, 1200, 120, 0.6, 60, 0.35, 0.7, 50, 0.88, 0, 0

# Crystalline typically appends "_Crystalline" or similar, 
# but since Viz is OFF, the object should remain selected automatically.
sound4 = selected("Sound")
appendInfoLine: "Step 3: Crystalline Cascade complete."

# ==============================================================================
# STEP 4: 4-Channel Canon
# ==============================================================================
selectObject: sound4
# Visualization (Arg 13) is set to 0
runScript: path4$, "Classic Canon (unison, staggered)", 0, 0, 0, 0, 0.0, 0.5, 1.0, 1.5, 44100, 0.01, "4 channels (quadraphonic)", 0, 1

appendInfoLine: "Step 4: 4-Channel Canon complete. Chain finished."

# ==============================================================================
# VISUALIZATION (Simple Text)
# ==============================================================================
Erase all
Select outer viewport: 0, 8, 0.1, 3.5
Axes: 0, 10, 0, 10
Font size: 16
Text: 5, "centre", 5, "half", "MDS Space Navigator -> Spectral Freeze -> Crystalline Cascade -> 4-Channel Canon"

selectObject: sound4