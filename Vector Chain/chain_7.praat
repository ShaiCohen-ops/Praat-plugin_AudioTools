# ============================================================
# Praat AudioTools - Custom Generative Chain
# ============================================================

Erase all

# ==============================================================================
# INPUT CHECK
# ==============================================================================
numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds <> 1
    exitScript: "Please select exactly one Sound object before running the chain."
endif

inputSound = selected("Sound")

appendInfoLine: "--- Starting Custom Generative Chain ---"

# --- Define Paths (Relative) ---
# Assumes this script is in "plugin_AudioTools/_Chains/"
path1$ = "../AI & Adaptive/HMM_Timbre_Sequencing.praat"
path2$ = "../Generative & Synthesis/Kotoński_FSM_Event_Generator.praat"
path3$ = "../Generative & Synthesis/Risset's_Mutations.praat"
path4$ = "../Generative & Synthesis/Stockhausen_Studie_II_Generator.praat"
path5$ = "../Spatial & Surround/Stereo_Mixer.praat"
path6$ = "../Filter & Color/Golden_Ratio_Processor.praat"

# ==============================================================================
# STEP 1: HMM Timbre Sequencing
# ==============================================================================
appendInfoLine: "Step 1: Running HMM Timbre Sequencing on selected input..."
selectObject: inputSound

# HMM_Timbre_Sequencing.praat expects exactly 12 arguments:
# preset, frame_size_ms, frame_hop_ms, number_of_states_K, max_kmeans_iterations,
# target_duration_s, match_input_duration, output_length_frames, crossfade_ms,
# stereo_output, draw_visualization, show_info
#
# NOTE:
# - "Three Region Evolution" is not a valid preset name in this script.
# - Frame size must be >= 64 ms.
runScript: path1$, "Custom", 80, 25, 10, 25, 7, 0, 200, 5, 1, 1, 1, 0

sound1 = selected("Sound")
appendInfoLine: "Step 1: HMM Timbre Sequencing complete."

# ==============================================================================
# STEP 2: Kotoński FSM Event Generator
# ==============================================================================
appendInfoLine: "Step 2: Generating Kotoński FSM Events..."
runScript: path2$, "6. Custom (compositional control below)", 30, 44100, 120, 0.6, 10, 15, "Palindrome: 1→2→3→4→3→2→1", "Event-based (every N events)", 25, 80, 8000, 1, "Noise", "Noise", "Mixed", "Tones", 800, 0, 0

sound2 = selected("Sound")
appendInfoLine: "Step 2: Kotoński Generator complete."

# ==============================================================================
# STEP 3: Risset's Mutations
# ==============================================================================
appendInfoLine: "Step 3: Generating Risset's Mutations..."
runScript: path3$, "1. Full Composition (3-Part Arc)", 30, 0

sound3 = selected("Sound")
appendInfoLine: "Step 3: Risset's Mutations complete."

# ==============================================================================
# STEP 4: Stockhausen Studie II Generator
# ==============================================================================
appendInfoLine: "Step 4: Generating Stockhausen Studie II..."
runScript: path4$, "Random (varied each time)", 30, 7, 44100, 100, 0.1, 0.3, 0, 0, 0, 0

sound4 = selected("Sound")
appendInfoLine: "Step 4: Stockhausen Studie II complete."

# ==============================================================================
# STEP 5: Stereo Mixer
# ==============================================================================
appendInfoLine: "Step 5: Mixing generators (Stereo Mixer)..."
selectObject: sound1
plusObject: sound2
plusObject: sound3
plusObject: sound4

runScript: path5$, "V Shape (outside in)", 1, 1, 1, 1, 1, 1, 1, 1, "yes", 0.95, 0, 0

sound5 = selected("Sound")
appendInfoLine: "Step 5: Stereo Mix complete."

# ==============================================================================
# STEP 6: Golden Ratio Processor
# ==============================================================================
appendInfoLine: "Step 6: Applying Golden Ratio Processing..."
selectObject: sound5

runScript: path6$, "Subtle (gentle φ influence)", "no", "yes", "yes", "yes", "yes", "no", 75, 600, 0.01, 0, 0

sound6 = selected("Sound")
appendInfoLine: "Step 6: Golden Ratio Processing complete."

# ==============================================================================
# PLAYBACK
# ==============================================================================
appendInfoLine: "Chain finished. Playing final mixdown."
selectObject: sound6
Play
