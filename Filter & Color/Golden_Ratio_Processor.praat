# ============================================================
# Praat AudioTools - Golden_Ratio_Processor.praat
# Author: Shai Cohen 
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2025) - GOLDEN PANNING INTEGRATION
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   An audio processing pipeline based entirely on the Golden Ratio (φ ≈ 1.618).
#   This script transforms pitch, intensity, timbre, and spatialization (panning)
#   to align with the "Golden Time Structure".
#
#   NEW IN V2.3: "The Golden Bloom" (Panning Architecture)
#     - Stereo Width: Starts at 0 (Mono), expands to 100% (Full Stereo) exactly at
#       the Golden Climax (T₁ = T/φ ≈ 0.618 * Duration), then resolves.
#     - Motion Speed: The panning oscillation is not constant; it accelerates 
#       by a factor of φ as it approaches the climax, creating structural tension.
#
#   Golden Ratio Principles Used:
#     1. Time Structure:  T₁ (Development) = T/φ; T₂ (Resolution) = T - T₁
#     2. Panning:         Width "blooms" at T₁; Speed accelerates by φ
#     3. Pitch:           Scaled deviation from original contour using φ
#     4. Intensity:       Envelope peaks at 0.618T
#     5. Spectral:        Global warp (scale) and gentle filtering by φ
#
# Usage:
#   Select a Sound object and run. Choose "Apply_golden_panning" to hear the stereo bloom.
# ============================================================

form Golden Ratio Processor v2.3
    comment === Processing Intensity ===
    optionmenu Preset 1
        option Subtle (gentle φ influence)
        option Standard (moderate φ scaling)
        option Pronounced (strong φ transformation)
    
    comment === Golden Ratio Components ===
    boolean Apply_pitch_architecture 1
    boolean Apply_intensity_structure 1
    boolean Apply_spectral_scaling 1
    comment (Global spectral warp by φ factor)
    boolean Apply_spectral_filtering 1
    comment (φ-scaled bandwidth, gentle)
    boolean Apply_golden_panning 1
    comment (Stereo width blooms at φ-Climax)
    boolean Apply_micro_modulation 0
    comment (φ-derived vibrato cascade)
    
    comment === Analysis Parameters ===
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    positive Time_step_s 0.01
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

phi = 1.618033988749895
phi_inv = 1 / phi

if preset = 1
    scaling_strength = 0.3
    presetName$ = "Subtle"
elsif preset = 2
    scaling_strength = 0.6
    presetName$ = "Standard"
elsif preset = 3
    scaling_strength = 1.0
    presetName$ = "Pronounced"
endif

orig_id = selected("Sound")
orig_name$ = selected$("Sound")

clearinfo
writeInfoLine: "=== Golden Ratio Processor v2.3 ==="
writeInfoLine: "φ = ", fixed$(phi, 6)
writeInfoLine: "Input: ", orig_name$
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""

selectObject: orig_id
sample_rate = Get sampling frequency
n_channels = Get number of channels
total_duration = Get total duration

appendInfoLine: "PHASE 1: Global Analysis"
appendInfoLine: "Duration: ", fixed$(total_duration, 3), " s"

# Always convert to mono first to build the "Golden Core"
if n_channels > 1
    selectObject: orig_id
    Convert to mono
    mono_id = selected("Sound")
else
    selectObject: orig_id
    Copy: "mono"
    mono_id = selected("Sound")
endif

selectObject: mono_id
To Pitch: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
pitch_obj = selected("Pitch")
mean_f0 = Get mean: 0, 0, "Hertz"
if mean_f0 = undefined
    mean_f0 = 200
endif
f0_min = Get minimum: 0, 0, "Hertz", "Parabolic"
f0_max = Get maximum: 0, 0, "Hertz", "Parabolic"
if f0_min = undefined
    f0_min = mean_f0 * 0.8
endif
if f0_max = undefined
    f0_max = mean_f0 * 1.2
endif

selectObject: mono_id
To Intensity: pitch_floor_Hz, time_step_s, "yes"
intensity_obj = selected("Intensity")
mean_intensity = Get mean: 0, 0, "energy"
intensity_stddev = Get standard deviation: 0, 0

# For Spectral Scaling calculation
if apply_spectral_scaling
    selectObject: mono_id
    To Formant (burg): time_step_s, 5, 5500, 0.025, 50
    formant_obj = selected("Formant")
    mean_f2 = Get mean: 2, 0, 0, "Hertz"
    if mean_f2 = undefined
        mean_f2 = 1500
    endif
    target_f2 = mean_f2 * phi
    removeObject: formant_obj
else
    mean_f2 = 1500
    target_f2 = mean_f2 * phi
endif

selectObject: mono_id
To Spectrum: "yes"
spectrum_obj = selected("Spectrum")
cog = Get centre of gravity: 2

appendInfoLine: "  Mean F0: ", fixed$(mean_f0, 1), " Hz"
appendInfoLine: "  Mean intensity: ", fixed$(mean_intensity, 1), " dB"
if apply_spectral_scaling
    appendInfoLine: "  Spectral Target: Global warp ×", fixed$(phi, 3)
endif
appendInfoLine: ""

t1 = total_duration * phi_inv
t2 = total_duration - t1
climax_time = t1

appendInfoLine: "PHASE 2: Golden Time Structure"
appendInfoLine: "  T₁ (developmental): ", fixed$(t1, 3), " s"
appendInfoLine: "  Climax at: ", fixed$(climax_time, 3), " s (0.618T)"
appendInfoLine: ""

upper_pitch_factor = 1 + scaling_strength * (phi - 1)
lower_pitch_factor = 1 - scaling_strength * (1 - phi_inv)

delta_intensity = intensity_stddev * 2
peak_intensity = mean_intensity + delta_intensity * (phi - 1)
soft_intensity = mean_intensity - delta_intensity * phi_inv

# Spectral Filters
low_anchor = max(100, mean_f0 * 0.5)
high_anchor = min(sample_rate / 2 * 0.9, 5000)
filter_range = high_anchor - low_anchor
gentle_lower = max(50, low_anchor - filter_range * 0.3)
gentle_upper = min(sample_rate / 2 * 0.95, high_anchor + filter_range * 0.3)

# Vibrato Rates
base_vibrato_rate = mean_f0 / (phi * 40)
rate_1 = base_vibrato_rate
rate_2 = base_vibrato_rate * phi_inv

# Panning Parameters
pan_speed_base = 0.5 / phi
pan_speed_climax = 0.5 * phi

appendInfoLine: "PHASE 3: φ-Derived Targets"
if apply_golden_panning
    appendInfoLine: "  Golden Panning (Stereo):"
    appendInfoLine: "    Width: Bloom to 100% at ", fixed$(climax_time, 2), "s"
    appendInfoLine: "    Speed: Accelerates ×", fixed$(phi, 2), " towards climax"
endif
if apply_pitch_architecture
    appendInfoLine: "  Pitch: T₁=×", fixed$(upper_pitch_factor, 2), " | T₂=×", fixed$(lower_pitch_factor, 2)
endif
appendInfoLine: ""

appendInfoLine: "PHASE 4: Applying φ-Transformations..."

selectObject: mono_id
Copy: "working"
working_sound = selected("Sound")

component_count = 0
if apply_pitch_architecture
    component_count = component_count + 1
endif
if apply_intensity_structure
    component_count = component_count + 1
endif
if apply_spectral_scaling
    component_count = component_count + 1
endif
if apply_spectral_filtering
    component_count = component_count + 1
endif
if apply_micro_modulation
    component_count = component_count + 1
endif
if apply_golden_panning
    component_count = component_count + 1
endif

current_component = 0

# --- 1. PITCH ---
if apply_pitch_architecture
    current_component = current_component + 1
    appendInfoLine: "  [", current_component, "/", component_count, "] Pitch: Scaled deviation..."
    
    selectObject: working_sound
    To Manipulation: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
    manip_obj = selected("Manipulation")
    Extract pitch tier
    pitch_tier = selected("PitchTier")
    
    n_points = Get number of points
    for i to n_points
        t = Get time from index: i
        f0 = Get value at index: i
        if t <= t1
            progress = t / t1
            scale_factor = 1 + progress * (upper_pitch_factor - 1)
        else
            progress = (t - t1) / t2
            scale_factor = upper_pitch_factor - progress * (upper_pitch_factor - lower_pitch_factor)
        endif
        new_f0 = f0 * scale_factor
        new_f0 = max(pitch_floor_Hz, min(pitch_ceiling_Hz, new_f0))
        Remove point: i
        Add point: t, new_f0
    endfor
    
    selectObject: manip_obj
    plusObject: pitch_tier
    Replace pitch tier
    selectObject: manip_obj
    Get resynthesis (overlap-add)
    pitch_processed = selected("Sound")
    removeObject: manip_obj, pitch_tier, working_sound
    working_sound = pitch_processed
endif

# --- 2. INTENSITY ---
if apply_intensity_structure
    current_component = current_component + 1
    appendInfoLine: "  [", current_component, "/", component_count, "] Intensity: Peak at 0.618T..."
    selectObject: working_sound
    Formula: "if x <= climax_time then self * 10^(((soft_intensity + (peak_intensity - soft_intensity) * (x / climax_time)) - mean_intensity) / 20) else self * 10^(((peak_intensity - (peak_intensity - soft_intensity) * ((x - climax_time) / t2)) - mean_intensity) / 20) fi"
    Scale peak: 0.95
endif

# --- 3. SPECTRAL SCALING ---
if apply_spectral_scaling
    current_component = current_component + 1
    appendInfoLine: "  [", current_component, "/", component_count, "] Spectral: Global φ-warp..."
    spectral_ratio = phi
    adjusted_ratio = 1 + (spectral_ratio - 1) * scaling_strength
    selectObject: working_sound
    current_rate = Get sampling frequency
    Override sampling frequency: current_rate * adjusted_ratio
    Resample: current_rate, 50
    spectral_processed = selected("Sound")
    removeObject: working_sound
    working_sound = spectral_processed
endif

# --- 4. SPECTRAL FILTERING ---
if apply_spectral_filtering
    current_component = current_component + 1
    appendInfoLine: "  [", current_component, "/", component_count, "] Filter: Gentle φ-bandwidth..."
    selectObject: working_sound
    smoothing = 20 + (1 - scaling_strength) * 30
    Filter (pass Hann band): gentle_lower, gentle_upper, smoothing
    filtered_sound = selected("Sound")
    selectObject: working_sound
    Formula: "self * (1 - scaling_strength * 0.5) + Object_" + string$(filtered_sound) + "[col] * (scaling_strength * 0.5)"
    removeObject: filtered_sound
endif

# --- 5. VIBRATO ---
if apply_micro_modulation
    current_component = current_component + 1
    appendInfoLine: "  [", current_component, "/", component_count, "] Vibrato: φ-cascade..."
    selectObject: working_sound
    To Manipulation: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
    manip_obj = selected("Manipulation")
    Extract pitch tier
    pitch_tier = selected("PitchTier")
    depth_cents = 20 * scaling_strength
    n_points = Get number of points
    for i to n_points
        t = Get time from index: i
        f0 = Get value at index: i
        mod_1 = sin(2 * pi * rate_1 * t)
        mod_2 = sin(2 * pi * rate_2 * t)
        combined_mod = (mod_1 + 0.5 * mod_2) / 1.5
        cents_offset = depth_cents * combined_mod
        new_f0 = f0 * 2 ^ (cents_offset / 1200)
        Remove point: i
        Add point: t, new_f0
    endfor
    selectObject: manip_obj
    plusObject: pitch_tier
    Replace pitch tier
    selectObject: manip_obj
    Get resynthesis (overlap-add)
    vibrato_processed = selected("Sound")
    removeObject: manip_obj, pitch_tier, working_sound
    working_sound = vibrato_processed
endif

# --- 6. GOLDEN PANNING (STEREO INTEGRATION) ---
if apply_golden_panning
    current_component = current_component + 1
    appendInfoLine: "  [", current_component, "/", component_count, "] Panning: Golden Bloom..."
    
    leftTier = Create IntensityTier: "left_pan", 0, total_duration
    rightTier = Create IntensityTier: "right_pan", 0, total_duration
    
    pan_steps = 200
    phase_accum = 0
    
    for i from 0 to pan_steps
        t = i * total_duration / pan_steps
        if t <= t1
            width = t / t1
            current_speed = pan_speed_base + (pan_speed_climax - pan_speed_base) * (t / t1)
        else
            width = 1 - (t - t1) / t2
            current_speed = pan_speed_climax - (pan_speed_climax - pan_speed_base) * ((t - t1) / t2)
        endif
        width = width * scaling_strength
        phase_accum = phase_accum + current_speed * (total_duration / pan_steps)
        osc = sin(2 * pi * phase_accum)
        pan = 0.5 + (osc * 0.5 * width)
        angle = pan * pi / 2
        gainL = cos(angle)
        gainR = sin(angle)
        valL = 70 + 20 * log10(gainL + 0.0001)
        valR = 70 + 20 * log10(gainR + 0.0001)
        selectObject: leftTier
        Add point: t, valL
        selectObject: rightTier
        Add point: t, valR
    endfor
    
    selectObject: working_sound
    leftCh = Copy: "L"
    selectObject: working_sound
    rightCh = Copy: "R"
    selectObject: leftCh
    plusObject: leftTier
    leftRes = Multiply: "yes"
    selectObject: rightCh
    plusObject: rightTier
    rightRes = Multiply: "yes"
    selectObject: leftRes
    plusObject: rightRes
    stereo_sound = Combine to stereo
    removeObject: leftTier, rightTier, leftCh, rightCh, leftRes, rightRes, working_sound
    working_sound = stereo_sound
endif

selectObject: working_sound
Rename: orig_name$ + "_GoldenRatio_" + presetName$
Scale peak: 0.95
processed_sound = selected("Sound")

removeObject: pitch_obj, intensity_obj, spectrum_obj, mono_id

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "Golden Ratio Processor v2.3"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.25, "half", "φ = 1.618 | " + orig_name$ + " | " + presetName$
    
    # --- 1. Original (Mono) ---
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.6, 3.7, 0.7, 1.95
    selectObject: orig_id
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "{0.8, 0.3, 0.3}"
    Dotted line
    Draw line: climax_time, -1, climax_time, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input (Mono)"
    
    # --- 2. Golden Panning Architecture (The "Bloom") ---
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.4, 7.7, 0.7, 1.95
    
    Axes: 0, total_duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, 0, 1
    
    # Re-calculate points for visualization
    if apply_golden_panning
        n_viz = 200
        phase_accum = 0
        
        # Draw Left (Gold) and Right (Blue) envelopes
        for i from 1 to n_viz
            t_prev = (i - 1) * total_duration / n_viz
            t_curr = i * total_duration / n_viz
            
            # Helper: Get Pan at time t
            for k from 0 to 1
                if k=0
                    t_eval = t_prev
                else
                    t_eval = t_curr
                endif
                
                if t_eval <= t1
                    width_v = t_eval / t1
                    speed_v = pan_speed_base + (pan_speed_climax - pan_speed_base) * (t_eval / t1)
                else
                    width_v = 1 - (t_eval - t1) / t2
                    speed_v = pan_speed_climax - (pan_speed_climax - pan_speed_base) * ((t_eval - t1) / t2)
                endif
                width_v = width_v * scaling_strength
                
                # Approximate phase (not perfect integration for viz, but close enough for graph)
                # We use the accumulated phase from the main loop logic concept
                # For viz, we just show the ENVELOPE (Width), because drawing the osc is messy
                if k=0 
                    w_prev = width_v
                else 
                    w_curr = width_v
                endif
            endfor
            
            # Draw Width Envelope (The Bloom)
            Colour: "{0.9, 0.7, 0.3}"
            Line width: 2
            # Plot the "Bloom" envelope (Center +/- Width/2)
            Draw line: t_prev, 0.5 + w_prev*0.5, t_curr, 0.5 + w_curr*0.5
            Draw line: t_prev, 0.5 - w_prev*0.5, t_curr, 0.5 - w_curr*0.5
            Line width: 1
        endfor
        
        # Fill center
        Colour: "{0.9, 0.9, 0.9}"
        Draw line: 0, 0.5, total_duration, 0.5
    else
        Text: total_duration/2, "centre", 0.5, "half", "(Panning Off)"
    endif
    
    Colour: "{0.8, 0.3, 0.3}"
    Dotted line
    Draw line: climax_time, 0, climax_time, 1
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Stereo Width"
    Text: climax_time, "centre", 0.9, "half", "BLOOM"
    
    # --- 3. Output (Stereo) ---
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.7, 2.2, 3.4
    selectObject: processed_sound
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # --- 4. Info ---
    Select outer viewport: 0, 8, 3.6, 4.0
    Select inner viewport: 0.6, 7.7, 3.6, 4.0
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "Parameters: φ=" + fixed$(phi, 4) + " | Climax=" + fixed$(climax_time, 2) + "s | Panning: " + if apply_golden_panning then "Golden Bloom" else "Off" fi
    
endif

selectObject: processed_sound
appendInfoLine: "=== Complete ==="
if play_result
    Play
endif