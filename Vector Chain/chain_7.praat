# ============================================================
# Praat AudioTools - Custom Generative Chain
# Version: 1.4 - Stereo Mixer v0.6.2 compatibility
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
# This stable plugin path should contain the reviewed v1.5 implementation.
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
# STEP 2: Kotoński-Inspired State-Event Generator v1.5
# ==============================================================================
appendInfoLine: "Step 2: Generating Kotoński-inspired finite-state event field..."

# v1.5 has a new compact 12-argument main form. The older chain call passed
# state durations, transition mode, frequency bounds and material labels that
# no longer belong to the main runScript signature. Advanced state/sound
# parameters now live on an optional pause page, which must remain OFF inside
# an unattended chain.
#
# Chain mapping retained here:
#   old Custom preset         -> Custom Finite-State Field
#   duration                  -> 30 s
#   events                    -> 120
#   global amplitude          -> 0.60
#   palindrome state motion   -> Palindrome
#   event-based state change  -> State_hold_events = 10
#   downstream Stereo Mixer   -> Kotoński stage stays Mono
#   advanced page             -> off (non-interactive chain)
#   peak protection           -> on
#   visualization / playback  -> off
#
# v1.5 main-form signature:
#   Preset, Duration_s, Sample_rate_Hz, Num_events, Global_amplitude,
#   Transition_logic, State_hold_events, Spatial_mode,
#   Edit_state_sound_details, Peak_protection, Draw_visualization, Play_result
runScript: path2$, "Custom Finite-State Field", 30, 44100, 120, 0.60, "Palindrome", 10, "Mono", 0, 1, 0, 0

sound2 = selected("Sound")
appendInfoLine: "Step 2: Kotoński-inspired v1.5 field complete."

# ==============================================================================
# STEP 3: Risset's Mutations
# ==============================================================================
appendInfoLine: "Step 3: Generating Risset's Mutations..."

# FIX: Updated to Risset's Mutations v0.5.2's compact 5-argument form.
# The old 3-arg call ("1. Full Composition (3-Part Arc)", 30, 0) predates the
# v0.5 rewrite: the leading "1. " numbering no longer belongs to the
# optionmenu option text (the current form lists the option as plain
# "Full Composition (3-Part Arc)"), and the single trailing 0 doesn't align
# with any parameter in the current form.
#
# v0.5.2 main-form signature:
#   Preset, Duration_s, Edit_details, Draw_visualization, Play_result
#
# Chain mapping: preset and duration carried over unchanged; Edit_details
# stays off (non-interactive chain, matches the other steps' advanced pages);
# Draw_visualization and Play_result stay off since this is an intermediate
# stage feeding Step 5's mix, not the final output.
runScript: path3$, "Full Composition (3-Part Arc)", 30, 0, 0, 0

sound3 = selected("Sound")
appendInfoLine: "Step 3: Risset's Mutations complete."

# ==============================================================================
# STEP 4: Stockhausen Studie II Generator
# ==============================================================================
appendInfoLine: "Step 4: Generating Stockhausen Studie II..."

# FIX: Updated to Stockhausen_Studie_II_Generator's compact 5-argument form
# (introduced in v0.7, retained in v0.8). The old 12-arg call (base
# frequency, amplitude range, random groups, rotation offset, etc.) predates
# that rewrite - those engineering/model controls now live on the Edit
# details pause page, off by default and skipped in this unattended chain.
# The old preset text "Random (varied each time)" is also stale; the current
# optionmenu option reads "Random (creative, varied)".
#
# v0.8 main-form signature:
#   Generation_mode, Duration_s, Edit_details, Draw_score, Play_result
#
# Chain mapping: mode and duration carried over unchanged (Random, 30 s);
# Edit_details off (non-interactive chain); Draw_score and Play_result off
# since this is an intermediate stage feeding Step 5's mix.
runScript: path4$, "Random (creative, varied)", 30, 0, 0, 0

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

# FIX: Updated to Stereo_Mixer v0.6.2's form. Two things changed since the
# old call:
# - A new Edit_custom_gains_5_to_8 boolean was inserted right after the four
#   Custom-gain pairs (Sounds 5-8's gains moved to an optional second dialog
#   to keep the main form compact); the old 13-value call was missing this
#   field entirely, which would misalign every argument from
#   Normalize_output onward.
# - Normalize_output is a real boolean field (1/0), not the string "yes"
#   the old call passed.
# - The V Shape preset text was renamed/clarified: "V Shape (outside in)" ->
#   "V Shape (L to R to L)".
#
# v0.6.2 main-form signature:
#   Preset, Gain_1_L, Gain_1_R, Gain_2_L, Gain_2_R, Gain_3_L, Gain_3_R,
#   Gain_4_L, Gain_4_R, Edit_custom_gains_5_to_8, Normalize_output,
#   Target_peak, Draw_visualization, Play_result
#
# Chain mapping: preset is V Shape, so the four gain pairs are placeholders
# only (the preset branch overwrites them for all sounds); Edit_custom_gains
# stays off (non-interactive chain); Normalize_output on at Target_peak 0.95
# as before; Draw_visualization and Play_result stay off since this is an
# intermediate stage feeding Step 6.
runScript: path5$, "V Shape (L to R to L)", 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0.95, 0, 0

sound5 = selected("Sound")
appendInfoLine: "Step 5: Stereo Mix complete."

# ==============================================================================
# STEP 6: Golden Ratio Processor v3.0 (spectral-envelope engine)
# ==============================================================================
appendInfoLine: "Step 6: Applying Golden Ratio Processing v3.0..."
selectObject: sound5

runScript: path6$, "Subtle (gentle phi influence)", "no", "yes", "Spectral formant warp (keeps duration and pitch)", "yes", "yes", "no", 75, 600, 0.01, "Natural level", 0.95, 0, 0

sound6 = selected("Sound")
appendInfoLine: "Step 6: Golden Ratio Processing v3.0 complete."

# ==============================================================================
# PLAYBACK
# ==============================================================================
appendInfoLine: "Chain finished. Playing final mixdown."
selectObject: sound6
Play
