# ============================================================
# Praat AudioTools - Rhythmic Fractal Granulator 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fast multi-track overlap
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
# Extracts grains from source sound in fractal timing pattern
# with mirror symmetry and generation-based visualization
#
# ============================================================

# --- CHECK SELECTION ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object to use as the source!"
endif
source_id = selected("Sound")
source_dur = Get total duration
source_sr = Get sample rate
source_ch = Get number of channels
source_name$ = selected$("Sound")

# --- FORM ---
form Fractal Granulator Settings
    comment --- Presets ---
    optionmenu Preset 1
        option Custom
        option Dense Texture (short grains, many generations)
        option Sparse Rhythmic (long grains, few generations)
        option Glitchy (very short grains, high generations)
        option Ambient Cloud (medium grains, medium generations)
        option Percussive (short grains, low generations)
    
    comment --- Output Structure ---
    real Total_duration_(s) 4.0
    real Grain_duration_(s) 0.1
    integer Generations 5
    
    comment --- Grain Envelope ---
    choice Window_shape 2
        button Bell (Hanning)
        button Plateau (Trapezoid)
    
    comment --- Source Reading ---
    choice Read_mode 1
        button Random Offset
        button Sequential Scan
    
    comment --- Output ---
    boolean Stereo yes
    boolean Normalize yes
    boolean Draw_visualization yes
endform

# === APPLY PRESET ===
if preset = 2
    # Dense Texture
    total_duration = 6.0
    grain_duration = 0.05
    generations = 6
    window_shape = 1
    read_mode = 1
elsif preset = 3
    # Sparse Rhythmic
    total_duration = 8.0
    grain_duration = 0.2
    generations = 3
    window_shape = 2
    read_mode = 2
elsif preset = 4
    # Glitchy
    total_duration = 3.0
    grain_duration = 0.02
    generations = 7
    window_shape = 1
    read_mode = 1
elsif preset = 5
    # Ambient Cloud
    total_duration = 10.0
    grain_duration = 0.15
    generations = 4
    window_shape = 1
    read_mode = 1
elsif preset = 6
    # Percussive
    total_duration = 4.0
    grain_duration = 0.08
    generations = 3
    window_shape = 2
    read_mode = 2
endif
# If preset = 1 (Custom), use the form values as-is

# === INITIALIZATION ===
clearinfo
writeInfoLine: "Granulating '", source_name$, "' (", source_ch, " ch) into Fractal..."
uid$ = string$(randomInteger(10000, 99999))

# Derived Params
pivot_time = total_duration / 2
center_buffer = 0.05
jitter = 0.005
amp_decay = 0.15

# Arrays for Timing
max_events = 5000
event_times# = zero#(max_events)
event_gens# = zero#(max_events)

# --- STEP 1: GENERATE LEFT HALF (Fractal) ---
half_dur = pivot_time - center_buffer
num_events = 1
event_times#[1] = 0.1
event_gens#[1] = 0

for gen from 1 to generations
    shift = half_dur / (2 ^ gen)
    current_count = num_events
    for i from 1 to current_count
        parent_t = event_times#[i]
        new_t = parent_t + shift + randomUniform(-jitter, jitter)
        
        if new_t <= half_dur
            num_events = num_events + 1
            event_times#[num_events] = new_t
            event_gens#[num_events] = gen
        endif
    endfor
endfor

# --- STEP 2: MIRROR TO RIGHT ---
current_left = num_events
for i from 1 to current_left
    t_left = event_times#[i]
    gen = event_gens#[i]
    t_right = total_duration - t_left
    
    num_events = num_events + 1
    event_times#[num_events] = t_right
    event_gens#[num_events] = gen
endfor

# --- STEP 3: SORT TIMINGS ---
for i from 1 to num_events-1
    for j from i+1 to num_events
        if event_times#[j] < event_times#[i]
            temp_t = event_times#[i]
            event_times#[i] = event_times#[j]
            event_times#[j] = temp_t
            
            temp_g = event_gens#[i]
            event_gens#[i] = event_gens#[j]
            event_gens#[j] = temp_g
        endif
    endfor
endfor

appendInfoLine: "Generated ", num_events, " fractal events (", current_left, " + ", current_left, " mirrored)"

# --- STEP 4: SYNTHESIS LOOP ---
appendInfoLine: "Processing grains from source..."

part_ids# = zero#(num_events * 2 + 5) 
part_count = 0
current_time = 0.0

if read_mode = 2
    scan_step = (source_dur - grain_duration) / num_events
    scan_cursor = 0
endif

for i from 1 to num_events
    target_start = event_times#[i]
    gen = event_gens#[i]
    
    # A. Calculate Amplitude
    amp_factor = 1.0 * (1 - amp_decay) ^ gen
    
    # B. Silence Gap (FIXED: Uses source_ch)
    gap = target_start - current_time
    if gap > 0.0001
        sil = Create Sound from formula: "sil", source_ch, 0, gap, source_sr, "0"
        part_count = part_count + 1
        part_ids#[part_count] = sil
        current_time = current_time + gap
    endif
    
    # C. EXTRACT GRAIN FROM SOURCE
    selectObject: source_id
    
    if read_mode = 1
        read_start = randomUniform(0, source_dur - grain_duration)
    else
        read_start = scan_cursor
        scan_cursor = scan_cursor + scan_step
    endif
    
    if read_start > source_dur - grain_duration
        read_start = source_dur - grain_duration
    endif
    if read_start < 0
        read_start = 0
    endif
    
    read_end = read_start + grain_duration
    
    grain = Extract part: read_start, read_end, "rectangular", 1, "no"
    Rename: "G_" + string$(i)
    
    # D. APPLY WINDOW & AMPLITUDE
    if window_shape = 1
        # BELL (Hanning)
        nx = Get number of samples
        Formula: "self * " + string$(amp_factor) + " * (sin(pi * (col-1) / (" + string$(nx) + " - 1)))^2"
    else
        # PLATEAU (Trapezoid)
        Formula: "self * " + string$(amp_factor)
        fade_dur = 0.2 * grain_duration
        Fade in: 0, 0, fade_dur, "yes"
        Fade out: 0, grain_duration - fade_dur, fade_dur, "yes"
    endif
    
    part_count = part_count + 1
    part_ids#[part_count] = grain
    
    dur = Get total duration
    current_time = current_time + dur
endfor

# E. Final Tail
tail_dur = total_duration - current_time
if tail_dur > 0.0001
    tail = Create Sound from formula: "tail", source_ch, 0, tail_dur, source_sr, "0"
    part_count = part_count + 1
    part_ids#[part_count] = tail
endif

# --- STEP 5: CONCATENATE ---
if part_count > 0
    selectObject: part_ids#[1]
    for i from 2 to part_count
        plusObject: part_ids#[i]
    endfor

    chain = Concatenate
    Rename: "Fractal_Granular_" + uid$
    final_id = selected("Sound")

    # Cleanup parts
    selectObject: part_ids#[1]
    for i from 2 to part_count
        plusObject: part_ids#[i]
    endfor
    Remove
    
    selectObject: final_id
    
    # Stereo conversion if needed
    if stereo and source_ch = 1
        Convert to stereo
        stereo_id = selected("Sound")
        removeObject: final_id
        selectObject: stereo_id
        final_id = stereo_id
    endif

    if normalize
        Scale peak: 0.95
    endif
    
    # --- VISUALIZATION ---
    if draw_visualization
        appendInfoLine: "Drawing visualization..."
        
        Erase all
        
        # === Title ===
        Select outer viewport: 0, 8, 0.1, 0.6
        Font size: 14
        Colour: "Black"
        Text: 0.5, "centre", 0.5, "half", "Fractal Granulator: " + source_name$
        
        # === Source Waveform ===
        Select outer viewport: 0, 8, 0.7, 1.8
        Select inner viewport: 0.6, 7.6, 0.8, 1.7
        selectObject: source_id
        Colour: "{0.7, 0.7, 0.7}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "Source"
        
        # === Fractal Timing Diagram ===
        Select outer viewport: 0, 8, 1.9, 3.5
        Select inner viewport: 0.6, 7.6, 2.0, 3.4
        
        Axes: 0, total_duration, 0, generations + 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, 0, generations + 1
        
        # Draw pivot line
        Colour: "{0.5, 0.5, 0.5}"
        Draw line: pivot_time, 0, pivot_time, generations + 1
        Font size: 6
        Text: pivot_time, "centre", generations + 1.3, "half", "PIVOT"
        
        # Draw events by generation (FIXED: Changed to string vector)
        gen_colors$# = {"{0.2, 0.4, 0.8}", "{0.3, 0.6, 0.9}", "{0.5, 0.7, 0.95}", 
            ... "{0.6, 0.8, 0.97}", "{0.7, 0.85, 0.98}", "{0.8, 0.9, 0.99}"}
        
        for i from 1 to num_events
            t = event_times#[i]
            g = event_gens#[i]
            
            if g <= 5
                Colour: gen_colors$#[g + 1]
            else
                Colour: "{0.8, 0.9, 0.99}"
            endif
            
            # Draw vertical bar for event
            if g <= 5
                Paint rectangle: gen_colors$#[g + 1], t, t + grain_duration, g + 0.1, g + 0.9
            else
                Paint rectangle: "{0.8, 0.9, 0.99}", t, t + grain_duration, g + 0.1, g + 0.9
            endif
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "Generation"
        Text bottom: "yes", "Time (s)"
        
        # Legend for generations
        Select outer viewport: 0, 8, 3.6, 3.9
        Font size: 7
        for g from 0 to min(generations, 5)
            if g <= 5
                Colour: gen_colors$#[g + 1]
            else
                Colour: "{0.8, 0.9, 0.99}"
            endif
            x_pos = 0.1 + g * 0.15
            Text: x_pos, "left", 0.5, "half", "Gen " + string$(g)
        endfor
        
        # === Output Waveform ===
        Select outer viewport: 0, 8, 4.0, 5.1
        Select inner viewport: 0.6, 7.6, 4.1, 5.0
        selectObject: final_id
        Colour: "{0.3, 0.6, 0.4}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "Output"
        Text bottom: "yes", "Time (s)"
        
        # === Fractal Structure Timeline ===
        Select outer viewport: 0, 8, 5.2, 6.2
        Select inner viewport: 0.6, 7.6, 5.3, 6.1
        
        Axes: 0, total_duration, 0, 1
        Paint rectangle: "White", 0, total_duration, 0, 1
        
        # Draw all events as impulses
        for i from 1 to num_events
            t = event_times#[i]
            g = event_gens#[i]
            
            if g <= 5
                Colour: gen_colors$#[g + 1]
            else
                Colour: "{0.8, 0.9, 0.99}"
            endif
            
            Draw line: t, 0, t, 1
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Events"
        Text bottom: "yes", "Time (s)"
        
        # === Statistics ===
        Select outer viewport: 0, 8, 6.3, 6.6
        Font size: 8
        Colour: "{0.4, 0.4, 0.4}"
        
        if window_shape = 1
            window_name$ = "Bell (Hanning)"
        else
            window_name$ = "Plateau"
        endif
        
        if read_mode = 1
            read_name$ = "Random"
        else
            read_name$ = "Sequential"
        endif
        
        Text: 0.5, "centre", 0.5, "half", 
            ... "Events: " + string$(num_events) + " | " 
            ... + "Grain: " + fixed$(grain_duration * 1000, 0) + "ms | "
            ... + "Window: " + window_name$ + " | "
            ... + "Read: " + read_name$
        
        Font size: 10
        Colour: "Black"
    endif
    
    appendInfoLine: ""
    appendInfoLine: "Done! Created Fractal Granular with ", num_events, " events."
    
    selectObject: final_id
else
    appendInfoLine: "Error: No events."
endif
Play