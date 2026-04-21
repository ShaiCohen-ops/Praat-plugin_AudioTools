# ============================================================
# Praat AudioTools - RISSET'S MUTATIONS
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - With Presets
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Accelerating Polyrhythm Generator
#   Creates evolving polyrhythmic patterns with acceleration
#
# Usage:
#   RISSET'S MUTATIONS
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

form Risset Mutations Generator
    comment Select a Compositional Strategy:
    optionmenu preset 1
        option 1. Full Composition (3-Part Arc)
        option 2. Study in Odd Harmonics (Woody/Hollow)
        option 3. Study in High Order (Glassy/Chime)
        option 4. Study in Density (Brassy/Chaos)
    
    comment Global Parameters:
    positive master_duration 30.0
    boolean show_visuals 1
endform

clearinfo
Erase all
writeInfoLine: "Initializing Risset Generator (Mark VIII)..."

# 1. SETUP
# ------------------------------------------------------------------------------
run_id = randomInteger(1, 999999) 
writeInfoLine: "Run ID: ", run_id

sample_rate = 44100
base_freq = 110.0   

# Create Master
master_name$ = "Master_Mix_" + string$(run_id)
Create Sound from formula: master_name$, 1, 0, master_duration, sample_rate, "0"

# 2. SCHEDULER (PRESETS)
# ------------------------------------------------------------------------------
if preset = 1
    n_events = 14
    appendInfoLine: "Generating 3-Section Form..."
    for i from 1 to n_events
        # Section Logic
        if i <= 4
            section = 1
            t_min = 0.0
            t_max = master_duration * 0.3
        elsif i <= 10
            section = 2
            t_min = master_duration * 0.3
            t_max = master_duration * 0.7
        else
            section = 3
            t_min = master_duration * 0.6
            t_max = master_duration * 0.9
        endif
        
        start_t[i] = randomUniform(t_min, t_max)
        
        if section = 1
            dur[i] = randomUniform(8.0, 14.0)
            freq[i] = randomUniform(base_freq, base_freq * 3)
            mode[i] = 1
            pk[i] = randomUniform(0.3, 0.6)
        elsif section = 2
            dur[i] = randomUniform(4.0, 8.0)
            freq[i] = randomUniform(base_freq * 2, base_freq * 8)
            mode[i] = 2
            pk[i] = randomUniform(0.7, 1.0)
        else
            dur[i] = randomUniform(6.0, 10.0)
            freq[i] = randomUniform(base_freq, base_freq * 4)
            mode[i] = 3
            pk[i] = randomUniform(0.2, 0.5)
        endif
    endfor

elsif preset = 2
    n_events = 8
    appendInfoLine: "Generating Odd-Harmonic Drone..."
    for i from 1 to n_events
        start_t[i] = randomUniform(0, master_duration * 0.6)
        dur[i] = randomUniform(10.0, 15.0)
        freq[i] = randomUniform(55.0, 275.0)
        mode[i] = 1
        pk[i] = randomUniform(0.2, 0.7)
    endfor

elsif preset = 3
    n_events = 12
    appendInfoLine: "Generating Glassy Texture..."
    for i from 1 to n_events
        start_t[i] = randomUniform(0, master_duration * 0.8)
        dur[i] = randomUniform(4.0, 9.0)
        freq[i] = randomUniform(440.0, 1100.0)
        mode[i] = 3
        pk[i] = randomUniform(0.3, 0.8)
    endfor

elsif preset = 4
    n_events = 25
    appendInfoLine: "Generating Dense Chaos..."
    for i from 1 to n_events
        start_t[i] = randomUniform(0, master_duration * 0.85)
        dur[i] = randomUniform(1.5, 4.0)
        freq[i] = randomUniform(110.0, 1320.0)
        mode[i] = 2
        pk[i] = randomUniform(0.6, 1.0)
    endfor
endif

# Fix Durations
for i from 1 to n_events
    if start_t[i] + dur[i] > master_duration
        dur[i] = master_duration - start_t[i]
    endif
endfor

# 3. VISUALIZATION
# ------------------------------------------------------------------------------
if show_visuals
    Erase all
    
    # Temporarily clear info to prevent text overlay on drawing
    clearinfo
    
    # === Title Section ===
    Select outer viewport: 0, 10, 0, 3.8
    Font size: 14
    Colour: "Black"
    if preset = 1
        Text top: "no", "RISSET'S MUTATIONS: Full Composition (3-Part Arc)"
    elsif preset = 2
        Text top: "no", "RISSET'S MUTATIONS: Study in Odd Harmonics (Woody/Hollow)"
    elsif preset = 3
        Text top: "no", "RISSET'S MUTATIONS: Study in High Order (Glassy/Chime)"
    elsif preset = 4
        Text top: "no", "RISSET'S MUTATIONS: Study in Density (Brassy/Chaos)"
    endif
    
    # === Main Score Area ===
    Select outer viewport: 0, 10, 1, 7
    Select inner viewport: 0.8, 9.5, 1.2, 6.7
    
    # Set up axes
    max_freq = 0
    for i from 1 to n_events
        test_freq = freq[i] + pk[i] * 200
        if test_freq > max_freq
            max_freq = test_freq
        endif
    endfor
    max_freq = max_freq * 1.1
    
    Axes: 0, master_duration, 0, max_freq
    
    # Paint black background
    Paint rectangle: "Black", 0, master_duration, 0, max_freq
    
    # Draw frequency grid (subtle)
    Colour: "{0.2, 0.2, 0.25}"
    Line width: 0.5
    grid_step = 110
    grid_freq = grid_step
    while grid_freq < max_freq
        Draw line: 0, grid_freq, master_duration, grid_freq
        grid_freq = grid_freq + grid_step
    endwhile
    
    # Draw time grid
    time_step = 5
    if master_duration < 15
        time_step = 2
    elsif master_duration > 60
        time_step = 10
    endif
    
    grid_time = time_step
    while grid_time < master_duration
        Draw line: grid_time, 0, grid_time, max_freq
        grid_time = grid_time + time_step
    endwhile
    
    # === Draw Events with Time-based Color Gradient ===
    Line width: 2
    
    for i from 1 to n_events
        t1 = start_t[i]
        d = dur[i]
        f = freq[i]
        m = mode[i]
        p = pk[i]
        
        # Time-based color progression (blue → cyan → green → yellow → red)
        time_ratio = t1 / master_duration
        
        if time_ratio < 0.25
            phase = time_ratio / 0.25
            r = 0.3
            g = 0.5 + phase * 0.3
            b = 1.0
        elsif time_ratio < 0.5
            phase = (time_ratio - 0.25) / 0.25
            r = 0.3
            g = 0.8 + phase * 0.2
            b = 1.0 - phase * 0.4
        elsif time_ratio < 0.75
            phase = (time_ratio - 0.5) / 0.25
            r = 0.3 + phase * 0.5
            g = 1.0
            b = 0.6 - phase * 0.6
        else
            phase = (time_ratio - 0.75) / 0.25
            r = 0.8 + phase * 0.2
            g = 1.0 - phase * 0.3
            b = 0.0
        endif
        
        # Mode-based brightness variation
        if m = 1
            brightness = 1.0
        elsif m = 2
            brightness = 0.85
        else
            brightness = 0.95
        endif
        
        r = r * brightness
        g = g * brightness
        b = b * brightness
        
        Colour: "{" + fixed$(r, 3) + ", " + fixed$(g, 3) + ", " + fixed$(b, 3) + "}"
        
        # Draw frequency modulation curve
        x_prev = t1
        y_prev = f
        steps = 30
        
        for s from 1 to steps
            nt = s / steps
            t_curr = t1 + (nt * d)
            env_val = (abs(sin(pi * nt)))^1.5
            y_curr = f + (env_val * p * 200)
            Draw line: x_prev, y_prev, t_curr, y_curr
            x_prev = t_curr
            y_prev = y_curr
        endfor
        
        # Draw base frequency line (thinner, dimmer)
        Line width: 1
        dim_r = r * 0.6
        dim_g = g * 0.6
        dim_b = b * 0.6
        Colour: "{" + fixed$(dim_r, 3) + ", " + fixed$(dim_g, 3) + ", " + fixed$(dim_b, 3) + "}"
        Draw line: t1, f, t1 + d, f
        Line width: 2
    endfor
    
    # === Draw Axes ===
    Line width: 1.5
    Colour: "{0.7, 0.7, 0.7}"
    Draw inner box
    
    # === Labels ===
    Colour: "White"
    Font size: 10
    Marks bottom every: 1, time_step, "yes", "yes", "no"
    Marks left every: 1, grid_step, "yes", "yes", "no"
    
    Font size: 11
    Text bottom: "yes", "Time (seconds)"
    Text left: "yes", "Frequency (Hz)"
    
    
    
    # Info text (centered, second row)
    Text: 0.5, "centre", 0.55, "half", "Events: " + string$(n_events) + "  |  Duration: " + fixed$(master_duration, 1) + "s  |  Base: " + fixed$(base_freq, 0) + "Hz  |  Color: blue → red (time)"
    
    # Reset
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# 4. SYNTHESIS PIPELINE
# ------------------------------------------------------------------------------
appendInfoLine: "Synthesizing events..."

for i from 1 to n_events
    suffix$ = "_" + string$(i) + "_" + string$(run_id)
    
    t_start = start_t[i]
    dur_evt = dur[i]
    t_end = t_start + dur_evt
    frq = freq[i]
    m_pk = pk[i]
    md = mode[i]
    
    appendInfoLine: "Event ", i, ": T=", fixed$(t_start, 2), "s"
    
    voice_name$ = "Voice" + suffix$
    
    # A. Source
    # SAFE CREATE: We create the sound starting at 0 to avoid alignment errors.
    # The 'if x < t_start' ensures silence before the event.
    Create Sound from formula: voice_name$, 1, 0, t_end, sample_rate,
        ... "if x < 't_start' then 0 else sin(2*pi*'frq'*(x-'t_start')) fi"

    # B. Envelopes
    # We create temporary envelopes that match the full duration (0 to t_end)
    # but represent the shape only during the event window.
    
    env_morph$ = "Env_Morph" + suffix$
    Create Sound from formula: env_morph$, 1, 0, t_end, sample_rate,
        ... "if x < 't_start' then 0 else 'm_pk' * (abs(sin(pi*(x-'t_start')/'dur_evt')))^1.5 fi"

    env_amp$ = "Env_Amp" + suffix$
    Create Sound from formula: env_amp$, 1, 0, t_end, sample_rate,
        ... "if x < 't_start' then 0 else (sin(pi*(x-'t_start')/'dur_evt'))^2 fi"

    # C. SHAPING
    selectObject: "Sound " + voice_name$
    if md = 1
        Formula: "(1 - Sound_'env_morph$'[]) * self + Sound_'env_morph$'[] * (-0.3 * self + 2.0 * self^3 - 0.7 * self^5)"
    elsif md = 2
        Formula: "(1 - Sound_'env_morph$'[]) * self + Sound_'env_morph$'[] * (0.5 * self + 0.5 * (2 * self^2 - 1))"
    else
        Formula: "(1 - Sound_'env_morph$'[]) * self + Sound_'env_morph$'[] * (64 * self^7 - 112 * self^5 + 56 * self^3 - 7 * self)"
    endif
    
    # Apply amplitude
    Formula: "self * Sound_'env_amp$'[]"

    # D. ACCUMULATE
    # Now both Master and Voice start at 0.0s, so simple addition is 100% safe.
    selectObject: "Sound " + master_name$
    Formula: "self + Sound_'voice_name$'[]"
    
    # F. CLEANUP
    selectObject: "Sound " + voice_name$
    plusObject: "Sound " + env_morph$
    plusObject: "Sound " + env_amp$
    Remove

endfor

# 5. FINALIZE
# ------------------------------------------------------------------------------
selectObject: "Sound " + master_name$
Scale peak: 0.95
if show_visuals
    Play
endif

appendInfoLine: "Done."