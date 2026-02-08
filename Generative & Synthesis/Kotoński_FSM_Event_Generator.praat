# ============================================================
# Praat AudioTools - Kotoński_FSM_Event_Generator.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - FIXED AND ENHANCED
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
# FSM Event Generator - Kotoński Edition
# Inspired by Włodzimierz Kotoński: Aela (1967)
# Fully deterministic finite-state machine with compositional presets
#
# FIXES in v1.0:
#   - Fixed formula mixing bug (line 619)
#   - Real noise generation (not pseudo-noise)
#   - Enhanced compositional info output
#   - Processing time tracking
#   - FIXED: Removed duplicate state transition logic
# ============================================================

form FSM Generator - Kotoński Edition
    comment === PRESET STRATEGIES ===
    optionmenu Preset 1
        option 1. Aela I: Sparse Pointillism (high register, silence)
        option 2. Aela II: Bass Punctuations (low interruptions)
        option 3. Aela III: Dense High Cluster (tight swarm)
        option 4. Aela IV: Filtered Noise Bands (spectral drift)
        option 5. Aela V: Mixed Texture (alternating characters)
        option 6. Custom (compositional control below)
    
    comment === GLOBAL PARAMETERS ===
    positive Duration_s 45.0
    positive Sample_rate 44100
    positive Num_events 120
    positive Global_amplitude 0.6
    positive Attack_ms 10
    positive Release_ms 15
    
    comment === CUSTOM MODE: COMPOSITIONAL CONTROLS ===
    comment (Only active when Custom preset selected)
    
    optionmenu State_progression 1
        option Linear cycle: 1→2→3→4
        option Palindrome: 1→2→3→4→3→2→1
        option Emphasize sparse: 1→3→1→3
        option Emphasize dense: 2→4→2→4
    
    optionmenu Transition_mode 1
        option Event-based (every N events)
        option Time-based (at duration %)
        option Hybrid (both)
    positive Transition_every_N 25
    
    positive Frequency_min_Hz 80
    positive Frequency_max_Hz 8000
    real Density_multiplier 1.0
    comment (< 1 = denser, > 1 = sparser)
    
    optionmenu State1_type 1
        option Tones
        option Noise
        option Mixed
    optionmenu State2_type 1
        option Tones
        option Noise
        option Mixed
    optionmenu State3_type 1
        option Tones
        option Noise
        option Mixed
    optionmenu State4_type 1
        option Tones
        option Noise
        option Mixed
    
    positive Noise_bandwidth_Hz 800
    
    comment === VISUALIZATION ===
    boolean Draw_score 1
    boolean Play_result 1
endform

startTime = stopwatch

# Apply preset overrides
if preset = 1
    duration_s = 50.0
    num_events = 80
    global_amplitude = 0.5
    attack_ms = 3
    release_ms = 5
    preset_name$ = "Aela I: Sparse Pointillism"
    custom_mode = 0
    
elsif preset = 2
    duration_s = 40.0
    num_events = 60
    global_amplitude = 0.7
    attack_ms = 2
    release_ms = 8
    preset_name$ = "Aela II: Bass Punctuations"
    custom_mode = 0
    
elsif preset = 3
    duration_s = 35.0
    num_events = 200
    global_amplitude = 0.4
    attack_ms = 2
    release_ms = 3
    preset_name$ = "Aela III: Dense High Cluster"
    custom_mode = 0
    
elsif preset = 4
    duration_s = 55.0
    num_events = 90
    global_amplitude = 0.55
    attack_ms = 20
    release_ms = 30
    preset_name$ = "Aela IV: Filtered Noise Bands"
    custom_mode = 0
    
elsif preset = 5
    duration_s = 60.0
    num_events = 150
    global_amplitude = 0.6
    attack_ms = 8
    release_ms = 12
    preset_name$ = "Aela V: Mixed Texture"
    custom_mode = 0
else
    preset_name$ = "Custom Configuration"
    custom_mode = 1
endif

# Constants
sr = sample_rate
total_dur = duration_s
n_events = num_events
global_amp = global_amplitude
attack_t = attack_ms / 1000
release_t = release_ms / 1000

# ============================================================
# INITIAL INFO OUTPUT
# ============================================================

clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  FSM GENERATOR - KOTOŃSKI EDITION"
writeInfoLine: "  Inspired by Włodzimierz Kotoński (1925-2014)"
writeInfoLine: "  Aela (1967) - Stochastic Synthesis"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "PRESET: ", preset_name$
appendInfoLine: ""
appendInfoLine: "=== COMPOSITIONAL PARAMETERS ==="
appendInfoLine: "Duration: ", fixed$(duration_s, 1), " seconds"
appendInfoLine: "Total events: ", num_events
appendInfoLine: "Average density: ", fixed$(num_events / duration_s, 2), " events/second"
appendInfoLine: "Attack: ", fixed$(attack_ms, 1), " ms | Release: ", fixed$(release_ms, 1), " ms"
appendInfoLine: "Global amplitude: ", fixed$(global_amplitude, 2)
appendInfoLine: ""

# Event data arrays
startTime# = zero# (n_events)
dur# = zero# (n_events)
gap# = zero# (n_events)
amp# = zero# (n_events)
type# = zero# (n_events)
f0_or_center# = zero# (n_events)
bandwidth# = zero# (n_events)
state# = zero# (n_events)

# Initialize
current_state = 1
current_time = 0

# Custom mode: state sequence setup
if custom_mode = 1
    sequence# = zero# (7)
    state_type_pref# = zero# (4)
    
    if state_progression = 1
        sequence_length = 4
        sequence#[1] = 1
        sequence#[2] = 2
        sequence#[3] = 3
        sequence#[4] = 4
    elsif state_progression = 2
        sequence_length = 7
        sequence#[1] = 1
        sequence#[2] = 2
        sequence#[3] = 3
        sequence#[4] = 4
        sequence#[5] = 3
        sequence#[6] = 2
        sequence#[7] = 1
    elsif state_progression = 3
        sequence_length = 4
        sequence#[1] = 1
        sequence#[2] = 3
        sequence#[3] = 1
        sequence#[4] = 3
    else
        sequence_length = 4
        sequence#[1] = 2
        sequence#[2] = 4
        sequence#[3] = 2
        sequence#[4] = 4
    endif
    sequence_index = 1
    
    state_type_pref#[1] = state1_type
    state_type_pref#[2] = state2_type
    state_type_pref#[3] = state3_type
    state_type_pref#[4] = state4_type
    
    appendInfoLine: "=== CUSTOM MODE ACTIVE ==="
    
    if state_progression = 1
        progType$ = "Linear cycle (1→2→3→4)"
    elsif state_progression = 2
        progType$ = "Palindrome (1→2→3→4→3→2→1)"
    elsif state_progression = 3
        progType$ = "Emphasize sparse (1↔3)"
    else
        progType$ = "Emphasize dense (2↔4)"
    endif
    appendInfoLine: "State progression: ", progType$
    
    if transition_mode = 1
        transType$ = "Event-based (every " + string$(transition_every_N) + " events)"
    elsif transition_mode = 2
        transType$ = "Time-based (proportional to duration)"
    else
        transType$ = "Hybrid (event + time)"
    endif
    appendInfoLine: "Transition mode: ", transType$
    
    appendInfoLine: "Frequency range: ", fixed$(frequency_min_Hz, 0), " - ", fixed$(frequency_max_Hz, 0), " Hz"
    appendInfoLine: "Density multiplier: ", fixed$(density_multiplier, 2)
    appendInfoLine: "Noise bandwidth: ", fixed$(noise_bandwidth_Hz, 0), " Hz"
    appendInfoLine: ""
    
    appendInfoLine: "State types:"
    for s to 4
        if state_type_pref#[s] = 1
            typeStr$ = "Tones"
        elsif state_type_pref#[s] = 2
            typeStr$ = "Noise"
        else
            typeStr$ = "Mixed"
        endif
        appendInfoLine: "  State ", s, ": ", typeStr$
    endfor
else
    appendInfoLine: "=== PRESET MODE ==="
    appendInfoLine: "Using deterministic state sequence"
    appendInfoLine: "4 states with equal event distribution"
endif

appendInfoLine: ""
appendInfoLine: "Generating event sequence..."

# Procedure to get event type
procedure getEventType: .state, .event_index, .preference
    if .preference = 1
        .result = 1
    elsif .preference = 2
        .result = 2
    else
        if (.event_index mod 2) = 0
            .result = 1
        else
            .result = 2
        endif
    endif
endproc

# ============================================================
# EVENT GENERATION LOOP - FIXED STATE TRANSITIONS
# ============================================================

for i to n_events
    # === STATE TRANSITION LOGIC (AT BEGINNING OF LOOP) ===
    if custom_mode = 1
        if transition_mode = 1
            # Event-based
            if i > 1 and ((i - 1) mod transition_every_N) = 0
                sequence_index = sequence_index + 1
                if sequence_index > sequence_length
                    sequence_index = 1
                endif
                current_state = sequence#[sequence_index]
            endif
        elsif transition_mode = 2
            # Time-based
            progress = current_time / total_dur
            state_index = floor(progress * sequence_length) + 1
            if state_index > sequence_length
                state_index = sequence_length
            endif
            if state_index >= 1 and state_index <= sequence_length
                current_state = sequence#[state_index]
            endif
        else
            # Hybrid
            if i > 1 and ((i - 1) mod transition_every_N) = 0
                sequence_index = sequence_index + 1
                if sequence_index > sequence_length
                    sequence_index = 1
                endif
                current_state = sequence#[sequence_index]
            endif
        endif
    else
        # Preset mode: 4 equal states
        events_per_state = floor(n_events / 4)
        if i <= events_per_state
            current_state = 1
        elsif i <= events_per_state * 2
            current_state = 2
        elsif i <= events_per_state * 3
            current_state = 3
        else
            current_state = 4
        endif
    endif
    
    # NOW assign the state AFTER transition logic
    state#[i] = current_state
    
    # CUSTOM MODE
    if custom_mode = 1
        @getEventType: current_state, i, state_type_pref#[current_state]
        type#[i] = getEventType.result
        
        if current_state = 1
            dur_base = 0.08
            dur_var = 0.04
            gap_base = 0.06
            gap_var = 0.03
            freq_pos = 0.3
            freq_range = 0.3
        elsif current_state = 2
            dur_base = 0.20
            dur_var = 0.10
            gap_base = 0.08
            gap_var = 0.04
            freq_pos = 0.5
            freq_range = 0.4
        elsif current_state = 3
            dur_base = 0.04
            dur_var = 0.02
            gap_base = 0.20
            gap_var = 0.10
            freq_pos = 0.7
            freq_range = 0.25
        else
            dur_base = 0.15
            dur_var = 0.08
            gap_base = 0.01
            gap_var = 0.01
            freq_pos = 0.4
            freq_range = 0.5
        endif
        
        dur#[i] = dur_base + dur_var * sin(2 * pi * i / 17)
        gap#[i] = (gap_base + gap_var * cos(2 * pi * i / 11)) * density_multiplier
        amp#[i] = 0.6 + 0.2 * sin(2 * pi * i / 13)
        
        min_f = frequency_min_Hz
        max_f = frequency_max_Hz
        f0_or_center#[i] = min_f + (max_f - min_f) * (freq_pos + freq_range * sin(2 * pi * i / 19))
        bandwidth#[i] = noise_bandwidth_Hz * (0.7 + 0.6 * cos(2 * pi * i / 23))
                
    # PRESET MODE
    elsif preset = 1
        min_f = 800
        max_f = 6000
        if current_state = 1
            dur#[i] = 0.015 + 0.008 * sin(2 * pi * i / 23)
            gap#[i] = 0.4 + 0.25 * cos(2 * pi * i / 17)
            amp#[i] = 0.5 + 0.3 * sin(2 * pi * i / 19)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.7 + 0.25 * sin(2 * pi * i / 13))
            bandwidth#[i] = 30
        elsif current_state = 2
            dur#[i] = 0.020 + 0.010 * sin(2 * pi * i / 29)
            gap#[i] = 0.35 + 0.20 * cos(2 * pi * i / 23)
            amp#[i] = 0.6 + 0.25 * sin(2 * pi * i / 17)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.6 + 0.3 * sin(2 * pi * i / 19))
            bandwidth#[i] = 40
        elsif current_state = 3
            dur#[i] = 0.012 + 0.006 * sin(2 * pi * i / 31)
            gap#[i] = 0.5 + 0.3 * cos(2 * pi * i / 13)
            amp#[i] = 0.4 + 0.2 * sin(2 * pi * i / 23)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.8 + 0.15 * sin(2 * pi * i / 11))
            bandwidth#[i] = 25
        else
            dur#[i] = 0.018 + 0.009 * sin(2 * pi * i / 19)
            gap#[i] = 0.45 + 0.25 * cos(2 * pi * i / 29)
            amp#[i] = 0.55 + 0.3 * sin(2 * pi * i / 13)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.5 + 0.35 * sin(2 * pi * i / 17))
            bandwidth#[i] = 35
        endif
        
    elsif preset = 2
        min_f = 60
        max_f = 500
        if current_state = 1
            dur#[i] = 0.15 + 0.08 * sin(2 * pi * i / 17)
            gap#[i] = 0.08 + 0.04 * cos(2 * pi * i / 23)
            amp#[i] = 0.7 + 0.2 * sin(2 * pi * i / 19)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.2 + 0.3 * sin(2 * pi * i / 13))
            bandwidth#[i] = 80
        elsif current_state = 2
            dur#[i] = 0.25 + 0.12 * sin(2 * pi * i / 29)
            gap#[i] = 0.05 + 0.03 * cos(2 * pi * i / 17)
            amp#[i] = 0.8 + 0.15 * sin(2 * pi * i / 23)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.15 + 0.25 * sin(2 * pi * i / 11))
            bandwidth#[i] = 100
        elsif current_state = 3
            dur#[i] = 0.10 + 0.05 * sin(2 * pi * i / 19)
            gap#[i] = 0.12 + 0.06 * cos(2 * pi * i / 31)
            amp#[i] = 0.6 + 0.25 * sin(2 * pi * i / 17)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.3 + 0.35 * sin(2 * pi * i / 23))
            bandwidth#[i] = 60
        else
            dur#[i] = 0.20 + 0.10 * sin(2 * pi * i / 23)
            gap#[i] = 0.06 + 0.03 * cos(2 * pi * i / 19)
            amp#[i] = 0.75 + 0.2 * sin(2 * pi * i / 29)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.25 + 0.3 * sin(2 * pi * i / 13))
            bandwidth#[i] = 90
        endif
        
    elsif preset = 3
        min_f = 1500
        max_f = 7000
        if current_state = 1
            dur#[i] = 0.03 + 0.015 * sin(2 * pi * i / 17)
            gap#[i] = 0.02 + 0.01 * cos(2 * pi * i / 23)
            amp#[i] = 0.4 + 0.15 * sin(2 * pi * i / 19)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.3 + 0.4 * sin(2 * pi * i / 13))
            bandwidth#[i] = 50
        elsif current_state = 2
            dur#[i] = 0.025 + 0.012 * sin(2 * pi * i / 29)
            gap#[i] = 0.015 + 0.008 * cos(2 * pi * i / 17)
            amp#[i] = 0.35 + 0.2 * sin(2 * pi * i / 23)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.5 + 0.35 * sin(2 * pi * i / 11))
            bandwidth#[i] = 45
        elsif current_state = 3
            dur#[i] = 0.02 + 0.010 * sin(2 * pi * i / 19)
            gap#[i] = 0.01 + 0.005 * cos(2 * pi * i / 31)
            amp#[i] = 0.3 + 0.15 * sin(2 * pi * i / 17)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.7 + 0.25 * sin(2 * pi * i / 23))
            bandwidth#[i] = 40
        else
            dur#[i] = 0.035 + 0.018 * sin(2 * pi * i / 23)
            gap#[i] = 0.018 + 0.009 * cos(2 * pi * i / 19)
            amp#[i] = 0.45 + 0.2 * sin(2 * pi * i / 29)
            type#[i] = 1
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.4 + 0.45 * sin(2 * pi * i / 13))
            bandwidth#[i] = 55
        endif
        
    elsif preset = 4
        min_f = 200
        max_f = 5000
        if current_state = 1
            dur#[i] = 0.20 + 0.10 * sin(2 * pi * i / 17)
            gap#[i] = 0.08 + 0.04 * cos(2 * pi * i / 23)
            amp#[i] = 0.5 + 0.2 * sin(2 * pi * i / 19)
            type#[i] = 2
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.2 + 0.3 * sin(2 * pi * i / 13))
            bandwidth#[i] = 600 + 400 * cos(2 * pi * i / 11)
        elsif current_state = 2
            dur#[i] = 0.25 + 0.12 * sin(2 * pi * i / 29)
            gap#[i] = 0.06 + 0.03 * cos(2 * pi * i / 17)
            amp#[i] = 0.55 + 0.25 * sin(2 * pi * i / 23)
            type#[i] = 2
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.4 + 0.35 * sin(2 * pi * i / 19))
            bandwidth#[i] = 700 + 500 * cos(2 * pi * i / 13)
        elsif current_state = 3
            dur#[i] = 0.15 + 0.08 * sin(2 * pi * i / 19)
            gap#[i] = 0.10 + 0.05 * cos(2 * pi * i / 31)
            amp#[i] = 0.45 + 0.2 * sin(2 * pi * i / 17)
            type#[i] = 2
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.6 + 0.3 * sin(2 * pi * i / 23))
            bandwidth#[i] = 500 + 300 * cos(2 * pi * i / 29)
        else
            dur#[i] = 0.30 + 0.15 * sin(2 * pi * i / 23)
            gap#[i] = 0.05 + 0.025 * cos(2 * pi * i / 19)
            amp#[i] = 0.6 + 0.25 * sin(2 * pi * i / 29)
            type#[i] = 2
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.5 + 0.4 * sin(2 * pi * i / 11))
            bandwidth#[i] = 800 + 600 * cos(2 * pi * i / 17)
        endif
        
    elsif preset = 5
        min_f = 150
        max_f = 4000
        if current_state = 1
            dur#[i] = 0.10 + 0.05 * sin(2 * pi * i / 17)
            gap#[i] = 0.06 + 0.03 * cos(2 * pi * i / 23)
            amp#[i] = 0.55 + 0.25 * sin(2 * pi * i / 19)
            type#[i] = if (i mod 2) = 0 then 1 else 2 fi
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.3 + 0.4 * sin(2 * pi * i / 13))
            bandwidth#[i] = 400 + 300 * cos(2 * pi * i / 11)
        elsif current_state = 2
            dur#[i] = 0.15 + 0.08 * sin(2 * pi * i / 29)
            gap#[i] = 0.04 + 0.02 * cos(2 * pi * i / 17)
            amp#[i] = 0.6 + 0.2 * sin(2 * pi * i / 23)
            type#[i] = if (i mod 3) = 0 then 2 else 1 fi
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.5 + 0.35 * sin(2 * pi * i / 19))
            bandwidth#[i] = 500 + 400 * cos(2 * pi * i / 13)
        elsif current_state = 3
            dur#[i] = 0.08 + 0.04 * sin(2 * pi * i / 19)
            gap#[i] = 0.08 + 0.04 * cos(2 * pi * i / 31)
            amp#[i] = 0.5 + 0.3 * sin(2 * pi * i / 17)
            type#[i] = if (i mod 4) = 0 then 1 else 2 fi
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.7 + 0.25 * sin(2 * pi * i / 23))
            bandwidth#[i] = 300 + 200 * cos(2 * pi * i / 29)
        else
            dur#[i] = 0.12 + 0.06 * sin(2 * pi * i / 23)
            gap#[i] = 0.05 + 0.025 * cos(2 * pi * i / 19)
            amp#[i] = 0.65 + 0.25 * sin(2 * pi * i / 29)
            type#[i] = if (i mod 5) = 0 then 2 else 1 fi
            f0_or_center#[i] = min_f + (max_f - min_f) * (0.4 + 0.45 * sin(2 * pi * i / 11))
            bandwidth#[i] = 600 + 500 * cos(2 * pi * i / 17)
        endif
    endif
    
    # Assign timing
    startTime#[i] = current_time
    current_time = current_time + dur#[i] + gap#[i]
    
    # Progress reporting
    if (i mod (n_events / 10)) = 0 or i = n_events
        percentDone = floor(100 * i / n_events)
        appendInfoLine: "  ", percentDone, "% complete (", i, "/", n_events, " events)"
    endif
endfor

# ============================================================
# EVENT GENERATION STATISTICS
# ============================================================

eventGenTime = stopwatch - startTime

appendInfoLine: ""
appendInfoLine: "=== EVENT GENERATION COMPLETE ==="
appendInfoLine: "Generation time: ", fixed$(eventGenTime, 2), " seconds"
appendInfoLine: ""

# Count events per state
state1_count = 0
state2_count = 0
state3_count = 0
state4_count = 0
tone_count = 0
noise_count = 0

for i to n_events
    if state#[i] = 1
        state1_count = state1_count + 1
    elsif state#[i] = 2
        state2_count = state2_count + 1
    elsif state#[i] = 3
        state3_count = state3_count + 1
    else
        state4_count = state4_count + 1
    endif
    
    if type#[i] = 1
        tone_count = tone_count + 1
    else
        noise_count = noise_count + 1
    endif
endfor

appendInfoLine: "=== COMPOSITIONAL STATISTICS ==="
appendInfoLine: "State distribution:"
appendInfoLine: "  State 1: ", state1_count, " events (", fixed$(100 * state1_count / n_events, 1), "%)"
appendInfoLine: "  State 2: ", state2_count, " events (", fixed$(100 * state2_count / n_events, 1), "%)"
appendInfoLine: "  State 3: ", state3_count, " events (", fixed$(100 * state3_count / n_events, 1), "%)"
appendInfoLine: "  State 4: ", state4_count, " events (", fixed$(100 * state4_count / n_events, 1), "%)"
appendInfoLine: ""
appendInfoLine: "Material distribution:"
appendInfoLine: "  Tones: ", tone_count, " events (", fixed$(100 * tone_count / n_events, 1), "%)"
appendInfoLine: "  Noise: ", noise_count, " events (", fixed$(100 * noise_count / n_events, 1), "%)"
appendInfoLine: ""

# Calculate average duration and gap
total_event_dur = 0
total_gap_dur = 0
for i to n_events
    total_event_dur = total_event_dur + dur#[i]
    total_gap_dur = total_gap_dur + gap#[i]
endfor
avg_dur = total_event_dur / n_events
avg_gap = total_gap_dur / n_events

appendInfoLine: "Timing statistics:"
appendInfoLine: "  Average event duration: ", fixed$(avg_dur * 1000, 1), " ms"
appendInfoLine: "  Average gap: ", fixed$(avg_gap * 1000, 1), " ms"
appendInfoLine: "  Sound/silence ratio: ", fixed$(total_event_dur / total_gap_dur, 2), ":1"
appendInfoLine: ""

renderStartTime = stopwatch
appendInfoLine: "Rendering audio..."

# ============================================================
# AUDIO RENDERING
# ============================================================

uid$ = string$(randomInteger(1000, 9999))
master_name$ = "master_" + uid$

master = Create Sound from formula: master_name$, 1, 0, total_dur, sr, "0"

# Get frequency range for visualization
min_freq_viz = 999999
max_freq_viz = 0
for i to n_events
    if f0_or_center#[i] < min_freq_viz
        min_freq_viz = f0_or_center#[i]
    endif
    if f0_or_center#[i] > max_freq_viz
        max_freq_viz = f0_or_center#[i]
    endif
    if type#[i] = 2
        test_low = f0_or_center#[i] - bandwidth#[i] / 2
        test_high = f0_or_center#[i] + bandwidth#[i] / 2
        if test_low < min_freq_viz
            min_freq_viz = test_low
        endif
        if test_high > max_freq_viz
            max_freq_viz = test_high
        endif
    endif
endfor
min_freq_viz = max(20, min_freq_viz * 0.9)
max_freq_viz = min(sr / 2, max_freq_viz * 1.1)

# Render each event
for i to n_events
    t_start = startTime#[i]
    t_dur = dur#[i]
    t_end = t_start + t_dur
    amplitude = amp#[i] * global_amp
    event_type = type#[i]
    freq = f0_or_center#[i]
    bw = bandwidth#[i]
    
    if t_start >= total_dur
        goto SKIP_EVENT
    endif
    
    if t_end > total_dur
        t_end = total_dur
        t_dur = t_end - t_start
    endif
    
    if t_dur > 0
        event_name$ = "evt_" + string$(i) + "_" + uid$
        
        if event_type = 1
            # TONE
            event = Create Sound from formula: event_name$, 1, 0, t_end, sr, "if x < t_start then 0 else amplitude * sin(2 * pi * freq * (x - t_start)) * (if (x - t_start) < attack_t then (1 - cos(pi * (x - t_start) / attack_t)) / 2 else (if (x - t_start) > (t_dur - release_t) then (1 - cos(pi * (t_end - x) / release_t)) / 2 else 1 endif) endif) fi"
        else
            # REAL NOISE (FIXED!)
            event = Create Sound from formula: event_name$, 1, 0, t_end, sr, "if x < t_start then 0 else amplitude * randomGauss(0, 1) * (if (x - t_start) < attack_t then (1 - cos(pi * (x - t_start) / attack_t)) / 2 else (if (x - t_start) > (t_dur - release_t) then (1 - cos(pi * (t_end - x) / release_t)) / 2 else 1 endif) endif) fi"
        endif
        
        selectObject: event
        
        if event_type = 2
            low_cut = freq - bw / 2
            high_cut = freq + bw / 2
            if low_cut < 10
                low_cut = 10
            endif
            if high_cut > sr / 2 - 100
                high_cut = sr / 2 - 100
            endif
            Filter (pass Hann band): low_cut, high_cut, 100
            filtered = selected("Sound")
            removeObject: event
            event = filtered
            Rename: event_name$
        endif
        
        # FIXED MIXING
        selectObject: master
        plusObject: event
        Formula: "self + object[event]"
        
        selectObject: master
        removeObject: event
    endif
    
    label SKIP_EVENT
    
    if (i mod (n_events / 5)) = 0 or i = n_events
        percentDone = floor(100 * i / n_events)
        appendInfoLine: "  Rendering: ", percentDone, "%"
    endif
endfor

# Final processing
selectObject: master
Scale peak: 0.9

fade_dur = 0.01
Formula: "self * (if x < fade_dur then x / fade_dur else (if x > (total_dur - fade_dur) then (total_dur - x) / fade_dur else 1 endif) endif)"

Rename: "FSM_" + preset_name$

renderTime = stopwatch - renderStartTime

# ============================================================
# RENDERING COMPLETE INFO
# ============================================================

selectObject: master
finalDuration = Get total duration
finalMax = Get maximum: 0, 0, "None"

appendInfoLine: ""
appendInfoLine: "=== RENDERING COMPLETE ==="
appendInfoLine: "Render time: ", fixed$(renderTime, 2), " seconds"
appendInfoLine: ""
appendInfoLine: "=== FINAL OUTPUT ==="
appendInfoLine: "Sound object: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " seconds"
appendInfoLine: "Peak amplitude: ", fixed$(finalMax, 3)
appendInfoLine: "Frequency range: ", fixed$(min_freq_viz, 0), " - ", fixed$(max_freq_viz, 0), " Hz"
appendInfoLine: ""

# ============================================================
# VISUALIZATION
# ============================================================

if draw_score
    vizStartTime = stopwatch
    appendInfoLine: "Drawing score visualization..."
    
    Erase all
    
    # === Title Section ===
    Select outer viewport: 0, 12, 0, 1.2
    Font size: 16
    Colour: "Black"
    Text top: "no", "FSM Generator - Kotoński Edition"
    Font size: 12
    Text: 6, "centre", 0.7, "half", preset_name$
    
    # === Main Score ===
    Select outer viewport: 0, 12, 1.5, 8
    Select inner viewport: 0.8, 11.5, 1.8, 7.7
    
    # Black background
    Axes: 0, total_dur, 0, max_freq_viz
    Paint rectangle: "Black", 0, total_dur, 0, max_freq_viz
    
    # Frequency grid
    Colour: "{0.2, 0.2, 0.25}"
    Line width: 0.5
    freq_grid = 500
    while freq_grid < max_freq_viz
        Draw line: 0, freq_grid, total_dur, freq_grid
        freq_grid = freq_grid + 500
    endwhile
    
    # Time grid
    time_grid = 5
    if total_dur > 60
        time_grid = 10
    endif
    t_mark = time_grid
    while t_mark < total_dur
        Draw line: t_mark, 0, t_mark, max_freq_viz
        t_mark = t_mark + time_grid
    endwhile
    
    # === Draw Events ===
    Line width: 2
    
    for i to n_events
        t = startTime#[i]
        d = dur#[i]
        f = f0_or_center#[i]
        a = amp#[i]
        typ = type#[i]
        st = state#[i]
        
        # Color based on state
        if st = 1
            r = 0.2
            g = 0.8
            b = 1.0
        elsif st = 2
            r = 0.3
            g = 1.0
            b = 0.4
        elsif st = 3
            r = 1.0
            g = 0.9
            b = 0.2
        else
            r = 1.0
            g = 0.5
            b = 0.1
        endif
        
        brightness = 0.5 + a * 0.5
        r = r * brightness
        g = g * brightness
        b = b * brightness
        
        Colour: "{" + fixed$(r, 3) + ", " + fixed$(g, 3) + ", " + fixed$(b, 3) + "}"
        
        if typ = 1
            # TONE
            Draw line: t, f - 50, t, f + 50
            Draw line: t, f, t + d, f
            Draw line: t + d, f - 30, t + d, f + 30
        else
            # NOISE
            bw_val = bandwidth#[i]
            f_low = f - bw_val / 2
            f_high = f + bw_val / 2
            
            steps = 5
            for step to steps
                y_pos = f_low + (f_high - f_low) * step / steps
                Draw line: t, y_pos, t + d, y_pos
            endfor
            
            Line width: 1.5
            Draw line: t, f_low, t + d, f_low
            Draw line: t, f_high, t + d, f_high
            Line width: 2
        endif
    endfor
    
    # === Axes ===
    Line width: 1.5
    Colour: "{0.8, 0.8, 0.8}"
    Draw inner box
    
    # === Labels ===
    Colour: "White"
    Font size: 10
    Marks bottom every: 1, time_grid, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    Font size: 11
    Text bottom: "yes", "Time (seconds)"
    Text left: "yes", "Frequency (Hz)"
    
    # === Legend ===
    Select outer viewport: 0, 12, 8.2, 9
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 9
    Colour: "Black"

    # Build legend string to avoid pipe parsing issues
    legend$ = "Tone = line - Noise = band - Colors: State 1 (cyan) to State 2 (green) to State 3 (yellow) to State 4 (orange) - Brightness = amplitude"

    Text: 0.5, "centre", 0.5, "half", legend$

    Colour: "Black"
    Line width: 1
    Draw rectangle: 0, 1, 0, 1
    
    # === Info Panel ===
    Select outer viewport: 0, 12, 9.2, 10
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.1, 0.1, 0.1}", 0, 1, 0, 1

    Font size: 8
    Colour: "White"

    # Build info string piece by piece to avoid parsing issues
    info$ = "Events: " + string$(n_events)
    info$ = info$ + " - Duration: " + fixed$(total_dur, 1) + "s"
    info$ = info$ + " - Range: " + fixed$(min_freq_viz, 0) + "-" + fixed$(max_freq_viz, 0) + "Hz"
    info$ = info$ + " - Attack: " + fixed$(attack_ms, 1) + "ms"
    info$ = info$ + " - Release: " + fixed$(release_ms, 1) + "ms"

    Text: 0.5, "centre", 0.5, "half", info$

    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    vizTime = stopwatch - vizStartTime
    appendInfoLine: "Visualization complete (", fixed$(vizTime, 2), " s)"
    appendInfoLine: ""
endif

# ============================================================
# FINAL SUMMARY
# ============================================================

totalTime = stopwatch - startTime

selectObject: master

appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "TOTAL PROCESSING TIME: ", fixed$(totalTime, 2), " seconds"
appendInfoLine: ""
appendInfoLine: "Event generation: ", fixed$(eventGenTime, 2), " s"
appendInfoLine: "Audio rendering: ", fixed$(renderTime, 2), " s"
if draw_score
    appendInfoLine: "Visualization: ", fixed$(vizTime, 2), " s"
endif
appendInfoLine: ""
appendInfoLine: "Compositional approach:"
if custom_mode = 1
    appendInfoLine: "  Custom state sequencer with user-defined progression"
else
    appendInfoLine: "  Preset '", preset_name$, "'"
    appendInfoLine: "  Based on Kotoński's stochastic composition techniques"
endif
appendInfoLine: ""
appendInfoLine: "Output character:"
appendInfoLine: "  ", tone_count, " tonal events + ", noise_count, " noise bands"
appendInfoLine: "  Distributed across 4 compositional states"
appendInfoLine: "  Average density: ", fixed$(n_events / duration_s, 2), " events/second"
appendInfoLine: ""
appendInfoLine: "I compose with sound as a painter"
appendInfoLine: "composes with color."
appendInfoLine: "                   - Wlodzimierz Kotoski"

# Play
if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: master