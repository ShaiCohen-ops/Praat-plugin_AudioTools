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

# FIX: Updated to the correct 15-argument signature for HMM_Timbre_Sequencing v2.0.
# v2.0 dropped Crossfade_ms (no longer a free parameter - fixed-hop OLA replaced
# it) and Match_input_duration (folded into Output_mode), and added
# Max_HMM_iterations, Frame_selection and Random_seed. The old 12/13-arg call
# below misaligned from Max_HMM_iterations onward.
# Parameters: Preset, Frame_size_ms, Frame_hop_ms, Number_of_states_K,
#             Max_kmeans_iterations, Max_HMM_iterations, Frame_selection,
#             Output_mode, Target_duration_s, Output_length_frames,
#             Random_seed, Stereo_output, Draw_visualization, Show_info,
#             Play_result
#
# Old call passed target_duration_s=7 with match_input_duration=0 (false),
# i.e. "use the target duration, not the input length" -> Output_mode =
# "Target duration (seconds)". The old crossfade_ms=5 has no v2.0 equivalent
# and is dropped. Frame_selection is new in v2.0; "Uniform" is chosen here
# because it matches what v1.3 actually did (it sampled a state, then picked
# uniformly among that state's frames) - v2.0's new "Gaussian" option is a
# different texture, so switch to it if you want the new default behaviour.
# Max_HMM_iterations and Random_seed are new in v2.0 and have no old value to
# carry over; left at the form's own defaults (10 and 0/unpredictable).
#
# NOTE:
# - "Three Region Evolution" is not a valid preset name in this script.
# - Frame size must be >= 64 ms.
runScript: path1$, "Custom", 80, 25, 10, 25, 10, "Uniform (any frame in state, equally likely)", "Target duration (seconds)", 7, 200, 0, 1, 1, 1, 0

sound1 = selected("Sound")
appendInfoLine: "Step 1: HMM Timbre Sequencing complete."

# ==============================================================================
# STEP 2: Kotoński FSM Event Generator
# ==============================================================================
appendInfoLine: "Step 2: Generating Kotoński FSM Events..."
runScript: path2$, "6. Custom (compositional control below)", 30, 44100, 120, 0.6, 10, 15, "Palindrome: 1->2->3->4->3->2->1", "Event-based (every N events)", 25, 80, 8000, 1, "Noise", "Noise", "Mixed", "Tones", 800, 0, 0

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
