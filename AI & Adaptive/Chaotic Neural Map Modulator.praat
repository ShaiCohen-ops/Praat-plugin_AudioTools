# ============================================================
# Praat AudioTools - Chaotic_Neural_Map_Modulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaotic Neural Map Modulator - Uses a trained neural network
#   and chaotic dynamics to generate organic audio modulation.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - Fixed array syntax for Praat compatibility
#   - Fixed != to <> operator
#   - Fixed preset comparison (number not string)
#   - Fixed Formula variable scope issues
#   - Added input validation
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

input_sound_original = selected("Sound")
input_name$ = selected$("Sound")

form Chaotic Neural Map Modulator v0.4
    comment === PRESETS ===
    optionmenu Preset: 2
        option Custom
        option Subtle Organic
        option Balanced Chaos
        option Wild Unstable
        option Tightly Controlled
        option Maximum Variation
        option Glitch Machine
    comment === Features & Network ===
    real Analysis_step_ms 60
    integer Hidden_neurons 10
    integer Training_iterations 200
    comment === Chaos Behavior ===
    real Autonomy 0.85
    real Chaos_volatility 2.5
    real Kick_interval_ms 200
    real Chaos_mutation 0.3
    comment === Modulation ===
    real Pitch_semitones 12
    real Amplitude_mod 0.8
    real Ring_mod 0.4
    boolean HQ_pitch 0
    comment === Output ===
    real Dry_wet 0.8
    real HF_boost_dB 3
    boolean Stereo_output 1
    boolean Play_output 1
    integer Random_seed 0
endform

#=============================================================================
# APPLY PRESET OVERRIDES
#=============================================================================

if preset = 2
    # Subtle Organic
    autonomy = 0.7
    chaos_volatility = 1.2
    kick_interval_ms = 100
    chaos_mutation = 0.15
    pitch_semitones = 6
    amplitude_mod = 0.5
    ring_mod = 0.2
    dry_wet = 0.5
    presetName$ = "SubtleOrganic"
elsif preset = 3
    # Balanced Chaos
    autonomy = 0.85
    chaos_volatility = 2.5
    kick_interval_ms = 200
    chaos_mutation = 0.3
    pitch_semitones = 12
    amplitude_mod = 0.8
    ring_mod = 0.4
    dry_wet = 0.8
    presetName$ = "BalancedChaos"
elsif preset = 4
    # Wild Unstable
    autonomy = 0.95
    chaos_volatility = 4.0
    kick_interval_ms = 500
    chaos_mutation = 0.7
    pitch_semitones = 18
    amplitude_mod = 0.9
    ring_mod = 0.6
    dry_wet = 1.0
    presetName$ = "WildUnstable"
elsif preset = 5
    # Tightly Controlled
    autonomy = 0.5
    chaos_volatility = 1.0
    kick_interval_ms = 50
    chaos_mutation = 0.1
    pitch_semitones = 8
    amplitude_mod = 0.6
    ring_mod = 0.3
    dry_wet = 0.6
    presetName$ = "TightlyControlled"
elsif preset = 6
    # Maximum Variation
    autonomy = 0.9
    chaos_volatility = 3.5
    kick_interval_ms = 300
    chaos_mutation = 0.9
    pitch_semitones = 15
    amplitude_mod = 0.85
    ring_mod = 0.5
    dry_wet = 0.9
    presetName$ = "MaxVariation"
elsif preset = 7
    # Glitch Machine
    autonomy = 0.98
    chaos_volatility = 5.0
    kick_interval_ms = 800
    chaos_mutation = 0.95
    pitch_semitones = 24
    amplitude_mod = 1.0
    ring_mod = 0.8
    dry_wet = 1.0
    presetName$ = "GlitchMachine"
else
    presetName$ = "Custom"
endif

#=============================================================================
# INITIALIZATION
#=============================================================================

selectObject: input_sound_original
duration = Get total duration
sr = Get sampling frequency
original_channels = Get number of channels

# Convert to mono for analysis
if original_channels > 1
    input_sound = Convert to mono
    Rename: input_name$ + "_mono"
else
    input_sound = Copy: input_name$ + "_mono"
endif

clearinfo
writeInfoLine: "=== CHAOTIC NEURAL MAP MODULATOR v0.4 ==="
appendInfoLine: "Preset: ", presetName$
if stereo_output
    appendInfoLine: "Output: Stereo (independent L/R chaos)"
else
    appendInfoLine: "Output: Mono"
endif

#=============================================================================
# SEED RANDOM NUMBER GENERATOR
#=============================================================================

if random_seed = 0
    date$ = date$()
    time_val = extractNumber(date$, ":")
    seed = round(time_val * 10000 + randomUniform(0, 1000)) mod 100000
    for i to seed
        dummy = randomUniform(0, 1)
    endfor
    appendInfoLine: "Seed: ", seed, " (random)"
else
    for i to random_seed
        dummy = randomUniform(0, 1)
    endfor
    appendInfoLine: "Seed: ", random_seed, " (fixed)"
endif

appendInfoLine: ""
appendInfoLine: "Autonomy: ", round(autonomy * 100), "% | Volatility: ", chaos_volatility
appendInfoLine: "Kick: ", kick_interval_ms, "ms | Mutation: ", round(chaos_mutation * 100), "%"
appendInfoLine: ""

#=============================================================================
# EXTRACT FEATURES
#=============================================================================

appendInfoLine: "Extracting features..."

time_step = analysis_step_ms / 1000
num_frames = floor(duration / time_step)

# Pre-allocate arrays
time# = zero#(num_frames)
feat_amp# = zero#(num_frames)
feat_centroid# = zero#(num_frames)
feat_rolloff# = zero#(num_frames)

for i to num_frames
    time#[i] = (i - 1) * time_step
endfor

# Amplitude from Intensity
selectObject: input_sound
intensity = To Intensity: 75, time_step, "yes"
for i to num_frames
    selectObject: intensity
    val = Get value at time: time#[i], "Cubic"
    if val = undefined
        feat_amp#[i] = 70
    else
        feat_amp#[i] = val
    endif
endfor
removeObject: intensity

# Single spectrogram for centroid AND rolloff
selectObject: input_sound
spectrogram = To Spectrogram: 0.005, 5000, time_step, 20, "Gaussian"

for i to num_frames
    selectObject: spectrogram
    slice = To Spectrum (slice): time#[i]
    
    selectObject: slice
    
    # Centroid
    cog = Get centre of gravity: 2
    if cog <> undefined and cog > 0
        feat_centroid#[i] = cog
    else
        feat_centroid#[i] = 2000
    endif
    
    # Rolloff (85% energy threshold)
    n_bins = Get number of bins
    total_energy = 0
    
    for bin to n_bins
        freq = Get frequency from bin number: bin
        if freq > 100 and freq < 5000
            power = Get real value in bin: bin
            total_energy += power^2
        endif
    endfor
    
    target = total_energy * 0.85
    cumulative = 0
    rolloff_freq = 2500
    
    for bin to n_bins
        freq = Get frequency from bin number: bin
        if freq > 100 and freq < 5000
            power = Get real value in bin: bin
            cumulative += power^2
            if cumulative >= target
                rolloff_freq = freq
                bin = n_bins + 1
            endif
        endif
    endfor
    
    feat_rolloff#[i] = rolloff_freq
    removeObject: slice
endfor

removeObject: spectrogram

# Normalize features
# Amplitude
min_v = feat_amp#[1]
max_v = feat_amp#[1]
for i from 2 to num_frames
    if feat_amp#[i] < min_v
        min_v = feat_amp#[i]
    endif
    if feat_amp#[i] > max_v
        max_v = feat_amp#[i]
    endif
endfor
range = max_v - min_v + 0.001
for i to num_frames
    feat_amp#[i] = (feat_amp#[i] - min_v) / range
endfor

# Centroid
min_v = feat_centroid#[1]
max_v = feat_centroid#[1]
for i from 2 to num_frames
    if feat_centroid#[i] < min_v
        min_v = feat_centroid#[i]
    endif
    if feat_centroid#[i] > max_v
        max_v = feat_centroid#[i]
    endif
endfor
range = max_v - min_v + 0.001
for i to num_frames
    feat_centroid#[i] = (feat_centroid#[i] - min_v) / range
endfor

# Rolloff
min_v = feat_rolloff#[1]
max_v = feat_rolloff#[1]
for i from 2 to num_frames
    if feat_rolloff#[i] < min_v
        min_v = feat_rolloff#[i]
    endif
    if feat_rolloff#[i] > max_v
        max_v = feat_rolloff#[i]
    endif
endfor
range = max_v - min_v + 0.001
for i to num_frames
    feat_rolloff#[i] = (feat_rolloff#[i] - min_v) / range
endfor

appendInfoLine: "  ", num_frames, " frames extracted"

#=============================================================================
# TRAIN NETWORK
#=============================================================================

appendInfoLine: "Training neural network..."

# Initialize weights (using indexed variables for 2D arrays)
for h to hidden_neurons
    w_in_'h'_1 = randomUniform(-0.5, 0.5)
    w_in_'h'_2 = randomUniform(-0.5, 0.5)
    w_in_'h'_3 = randomUniform(-0.5, 0.5)
    b_h_'h' = randomUniform(-0.5, 0.5)
endfor

for d to 3
    for h to hidden_neurons
        w_out_'d'_'h' = randomUniform(-0.5, 0.5)
    endfor
    b_o_'d' = randomUniform(-0.5, 0.5)
endfor

# Training loop
learning_rate = 0.12

for iter to training_iterations
    for frame from 2 to num_frames - 1
        inp_1 = feat_amp#[frame]
        inp_2 = feat_centroid#[frame]
        inp_3 = feat_rolloff#[frame]
        
        targ_1 = feat_amp#[frame + 1]
        targ_2 = feat_centroid#[frame + 1]
        targ_3 = feat_rolloff#[frame + 1]
        
        # Forward pass - hidden layer
        for h to hidden_neurons
            sum = b_h_'h'
            sum += inp_1 * w_in_'h'_1
            sum += inp_2 * w_in_'h'_2
            sum += inp_3 * w_in_'h'_3
            
            # Tanh activation
            if sum > 20
                hid_'h' = 1
            elsif sum < -20
                hid_'h' = -1
            else
                hid_'h' = (exp(sum) - exp(-sum)) / (exp(sum) + exp(-sum))
            endif
        endfor
        
        # Forward pass - output layer
        for d to 3
            sum = b_o_'d'
            for h to hidden_neurons
                hidVal = hid_'h'
                wVal = w_out_'d'_'h'
                sum += hidVal * wVal
            endfor
            if sum > 20
                out_'d' = 1
            elsif sum < -20
                out_'d' = -1
            else
                out_'d' = (exp(sum) - exp(-sum)) / (exp(sum) + exp(-sum))
            endif
        endfor
        
        # Backprop - output layer
        for d to 3
            if d = 1
                targVal = targ_1
            elsif d = 2
                targVal = targ_2
            else
                targVal = targ_3
            endif
            outVal = out_'d'
            err = targVal - outVal
            delta_o_'d' = err * (1 - outVal^2)
            deltaVal = delta_o_'d'
            for h to hidden_neurons
                hidVal = hid_'h'
                w_out_'d'_'h' += learning_rate * deltaVal * hidVal
            endfor
            b_o_'d' += learning_rate * deltaVal
        endfor
        
        # Backprop - hidden layer
        for h to hidden_neurons
            delta_h = 0
            for d to 3
                deltaO = delta_o_'d'
                wOut = w_out_'d'_'h'
                delta_h += deltaO * wOut
            endfor
            hidVal = hid_'h'
            delta_h *= (1 - hidVal^2)
            w_in_'h'_1 += learning_rate * delta_h * inp_1
            w_in_'h'_2 += learning_rate * delta_h * inp_2
            w_in_'h'_3 += learning_rate * delta_h * inp_3
            b_h_'h' += learning_rate * delta_h
        endfor
    endfor
endfor

appendInfoLine: "  ", training_iterations, " iterations complete"

#=============================================================================
# GENERATE CHAOS
#=============================================================================

appendInfoLine: "Generating chaos trajectories..."

if stereo_output
    n_passes = 2
else
    n_passes = 1
endif

kick_interval = kick_interval_ms / 1000
injection_rate = 1 - autonomy

# Pre-allocate chaos arrays
for frame to num_frames
    chaos_L_'frame'_1 = 0
    chaos_L_'frame'_2 = 0
    chaos_L_'frame'_3 = 0
    chaos_R_'frame'_1 = 0
    chaos_R_'frame'_2 = 0
    chaos_R_'frame'_3 = 0
endfor

for pass from 1 to n_passes
    # Initialize state
    state_1 = randomUniform(0.2, 0.8)
    state_2 = randomUniform(0.2, 0.8)
    state_3 = randomUniform(0.2, 0.8)
    
    last_kick = 0
    phase_offset = randomUniform(0, 1)
    
    for frame to num_frames
        inject = 0
        if time#[frame] - last_kick >= kick_interval
            inject = 1
            last_kick = time#[frame]
        endif
        
        if randomUniform(0, 1) < chaos_mutation * 0.5
            inject = 1 - inject
        endif
        
        if inject = 1
            inp_1 = feat_amp#[frame] * injection_rate + state_1 * (1 - injection_rate)
            inp_2 = feat_centroid#[frame] * injection_rate + state_2 * (1 - injection_rate)
            inp_3 = feat_rolloff#[frame] * injection_rate + state_3 * (1 - injection_rate)
        else
            inp_1 = state_1
            inp_2 = state_2
            inp_3 = state_3
        endif
        
        # Add mutation
        if chaos_mutation > 0
            inp_1 += randomUniform(-1, 1) * chaos_mutation * 0.2
            inp_2 += randomUniform(-1, 1) * chaos_mutation * 0.2
            inp_3 += randomUniform(-1, 1) * chaos_mutation * 0.2
            inp_1 = max(0, min(1, inp_1))
            inp_2 = max(0, min(1, inp_2))
            inp_3 = max(0, min(1, inp_3))
        endif
        
        # Forward through network
        for h to hidden_neurons
            sum = b_h_'h'
            sum += inp_1 * w_in_'h'_1
            sum += inp_2 * w_in_'h'_2
            sum += inp_3 * w_in_'h'_3
            if sum > 20
                hid_'h' = 1
            elsif sum < -20
                hid_'h' = -1
            else
                hid_'h' = (exp(sum) - exp(-sum)) / (exp(sum) + exp(-sum))
            endif
        endfor
        
        for d to 3
            sum = b_o_'d'
            for h to hidden_neurons
                hidVal = hid_'h'
                wVal = w_out_'d'_'h'
                sum += hidVal * wVal
            endfor
            if sum > 20
                new_state = 1
            elsif sum < -20
                new_state = -1
            else
                new_state = (exp(sum) - exp(-sum)) / (exp(sum) + exp(-sum))
            endif
            
            volatility_factor = chaos_volatility * randomUniform(0.8, 1.2)
            new_state = (new_state - 0.5) * volatility_factor + 0.5
            
            if chaos_mutation > 0 and randomUniform(0, 1) < chaos_mutation * 0.1
                new_state += randomUniform(-0.3, 0.3) * chaos_mutation
            endif
            
            new_state = max(0, min(1, new_state))
            
            phase_mod = sin(2 * pi * (frame / num_frames + phase_offset))
            chaos_val = (new_state * 2 - 1) * (1 + phase_mod * chaos_mutation * 0.3)
            chaos_val = max(-1, min(1, chaos_val))
            
            # Store in pass-specific arrays
            if pass = 1
                chaos_L_'frame'_'d' = chaos_val
                if d = 1
                    state_1 = new_state
                elsif d = 2
                    state_2 = new_state
                else
                    state_3 = new_state
                endif
            else
                chaos_R_'frame'_'d' = chaos_val
                if d = 1
                    state_1 = new_state
                elsif d = 2
                    state_2 = new_state
                else
                    state_3 = new_state
                endif
            endif
        endfor
    endfor
endfor

#=============================================================================
# APPLY MODULATION
#=============================================================================

appendInfoLine: "Applying modulation..."

# Get median pitch
selectObject: input_sound
pitch_obj = To Pitch: time_step, 75, 600
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"
if median_f0 = undefined or median_f0 < 75
    median_f0 = 200
endif
removeObject: pitch_obj

for pass from 1 to n_passes
    if stereo_output
        if pass = 1
            appendInfoLine: "  Processing LEFT..."
        else
            appendInfoLine: "  Processing RIGHT..."
        endif
    endif
    
    selectObject: input_sound
    work = Copy: input_name$ + "_work"
    
    # Build pitch tier
    pitch_tier = Create PitchTier: "chaos", 0, duration
    
    for i to num_frames
        if pass = 1
            chaos_pitch = chaos_L_'i'_1
        else
            chaos_pitch = chaos_R_'i'_1
        endif
        
        selectObject: pitch_tier
        semitones = chaos_pitch * pitch_semitones
        freq = median_f0 * 2 ^ (semitones / 12)
        freq = max(50, min(1000, freq))
        Add point: time#[i], freq
    endfor
    
    # Apply pitch modification
    selectObject: work
    manip = To Manipulation: 0.01, 75, 600
    selectObject: manip
    plusObject: pitch_tier
    Replace pitch tier
    selectObject: manip
    work_pitched = Get resynthesis (overlap-add)
    removeObject: manip, pitch_tier, work
    
    # Build amplitude tier
    amp_tier = Create IntensityTier: "chaos_amp", 0, duration
    for i to num_frames
        if pass = 1
            chaos_amp = chaos_L_'i'_2
        else
            chaos_amp = chaos_R_'i'_2
        endif
        
        selectObject: amp_tier
        db_mod = chaos_amp * 15 * amplitude_mod
        Add point: time#[i], 70 + db_mod
    endfor
    
    selectObject: work_pitched
    plusObject: amp_tier
    work_amp = Multiply: "yes"
    removeObject: amp_tier, work_pitched
    
    # Ring modulation
    if ring_mod > 0
        selectObject: work_amp
        ring_sound = Create Sound from formula: "ring_mod", 1, 0, duration, sr, "0"
        
        for i to num_frames
            if pass = 1
                chaos_ring = chaos_L_'i'_3
            else
                chaos_ring = chaos_R_'i'_3
            endif
            
            t_start = time#[i]
            if i < num_frames
                t_end = time#[i + 1]
            else
                t_end = duration
            endif
            
            ring_freq = 300 + chaos_ring * 600
            ringFreqStr$ = string$(ring_freq)
            ringModStr$ = string$(ring_mod)
            
            selectObject: ring_sound
            Formula (part): t_start, t_end, 1, 1,
                ... "(1 - " + ringModStr$ + ") + " + ringModStr$ + " * sin(2 * pi * " + ringFreqStr$ + " * x)"
        endfor
        
        # Apply ring mod
        ringIdStr$ = string$(ring_sound)
        selectObject: work_amp
        Formula: "self * Object_" + ringIdStr$ + "[col]"
        removeObject: ring_sound
    endif
    
    # HF boost
    if hF_boost_dB > 0
        selectObject: work_amp
        work_boosted = Filter (de-emphasis): 50
        selectObject: work_boosted
        boost_factor = 10 ^ (hF_boost_dB / 20)
        boostStr$ = string$(boost_factor)
        Formula: "self * " + boostStr$
        removeObject: work_amp
        work_amp = work_boosted
    endif
    
    # Store channel
    if pass = 1
        channel_left = work_amp
        selectObject: channel_left
        Rename: "Channel_Left"
    else
        channel_right = work_amp
        selectObject: channel_right
        Rename: "Channel_Right"
    endif
endfor

#=============================================================================
# MIX AND COMBINE
#=============================================================================

appendInfoLine: "Mixing..."

dryWetStr$ = string$(dry_wet)
dryAmtStr$ = string$(1 - dry_wet)

if stereo_output
    # Apply dry/wet to both channels
    selectObject: channel_left
    Formula: "self * " + dryWetStr$
    
    selectObject: channel_right
    Formula: "self * " + dryWetStr$
    
    # Create dry stereo
    selectObject: input_sound_original
    if original_channels > 1
        dry_sound = Copy: "dry"
    else
        dry_left = Copy: "dry_L"
        dry_right = Copy: "dry_R"
        selectObject: dry_left
        plusObject: dry_right
        dry_sound = Combine to stereo
        removeObject: dry_left, dry_right
    endif
    
    selectObject: dry_sound
    Formula: "self * " + dryAmtStr$
    
    # Combine wet channels
    selectObject: channel_left
    plusObject: channel_right
    wet_stereo = Combine to stereo
    Rename: "wet_stereo"
    removeObject: channel_left, channel_right
    
    # Match durations
    selectObject: wet_stereo
    wet_dur = Get total duration
    selectObject: dry_sound
    dry_dur = Get total duration
    
    if wet_dur < dry_dur
        selectObject: dry_sound
        dry_trimmed = Extract part: 0, wet_dur, "rectangular", 1.0, "no"
        removeObject: dry_sound
        dry_sound = dry_trimmed
    elsif dry_dur < wet_dur
        selectObject: wet_stereo
        wet_trimmed = Extract part: 0, dry_dur, "rectangular", 1.0, "no"
        removeObject: wet_stereo
        wet_stereo = wet_trimmed
    endif
    
    # Final mix
    wetIdStr$ = string$(wet_stereo)
    selectObject: dry_sound
    Formula: "self + Object_" + wetIdStr$ + "[row, col]"
    
    output_sound = dry_sound
    selectObject: output_sound
    Rename: input_name$ + "_chaotic_" + presetName$
    
    removeObject: wet_stereo
else
    # Mono output
    selectObject: channel_left
    Formula: "self * " + dryWetStr$
    
    selectObject: input_sound
    dry_mono = Copy: "dry_mono"
    Formula: "self * " + dryAmtStr$
    
    # Match durations
    selectObject: channel_left
    wet_dur = Get total duration
    selectObject: dry_mono
    dry_dur = Get total duration
    
    if wet_dur < dry_dur
        selectObject: dry_mono
        dry_trimmed = Extract part: 0, wet_dur, "rectangular", 1.0, "no"
        removeObject: dry_mono
        dry_mono = dry_trimmed
    elsif dry_dur < wet_dur
        selectObject: channel_left
        wet_trimmed = Extract part: 0, dry_dur, "rectangular", 1.0, "no"
        removeObject: channel_left
        channel_left = wet_trimmed
    endif
    
    wetIdStr$ = string$(channel_left)
    selectObject: dry_mono
    Formula: "self + Object_" + wetIdStr$ + "[col]"
    
    output_sound = dry_mono
    selectObject: output_sound
    Rename: input_name$ + "_chaotic_" + presetName$
    
    removeObject: channel_left
endif

#=============================================================================
# CLEANUP
#=============================================================================

removeObject: input_sound

selectObject: output_sound
Scale peak: 0.99

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")
selectObject: output_sound
n_ch = Get number of channels
dur = Get total duration
appendInfoLine: "Duration: ", fixed$(dur, 3), " s | Channels: ", n_ch

if play_output
    appendInfoLine: "Playing..."
    Play
endif

selectObject: output_sound