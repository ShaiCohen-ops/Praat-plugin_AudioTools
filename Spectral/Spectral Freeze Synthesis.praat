# ============================================================
# Praat AudioTools - Spectral Freeze Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025)
# License: MIT License
#
# Description:
#   Spectral freeze effect - captures and holds frequency peaks,
#   creating sustained, evolving drones from any sound. Uses
#   additive synthesis to resynthesize frozen partials with
#   optional decay and pitch drift (glissando).
#
# Changelog v0.3:
#   - Added wet/dry mix control
#   - Added visualization
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Spectral Freeze Synthesis
    optionmenu Preset: 1
        option Custom
        option Classic Freeze (infinite hold)
        option Gentle Decay (slow fade)
        option Rising Shimmer (upward drift)
        option Falling Shimmer (downward drift)
        option Ghostly Fade (fast decay, many partials)
        option Metallic Drone (tight peaks)
        option Cosmic Drift (extreme glissando)
        option Frozen Choir (wide stereo)
        option Disintegrating (very fast decay)
        option Ascending to Heaven (strong upward)
        option Descending to Hell (strong downward)
        option Spectral Dust (minimal, sparse)
    comment === Analysis ===
    positive frame_step_ms 20
    positive analysis_window_ms 35
    positive max_frequency_hz 8000
    integer top_partials 10
    comment === Transformation ===
    positive decay_factor 0.2
    comment (0.999 = infinite, 0.1 = fast decay)
    real glissando_oct_sec 0.0
    comment (octaves per second: + = up, - = down)
    comment === Mix ===
    real wet_dry_percent 100
    comment (0 = dry, 100 = full wet/freeze)
    comment === Output ===
    positive tail_duration_sec 2
    boolean create_stereo_output 1
    positive stereo_delay_ms 8
    real target_peak_db -1
    boolean draw_visualization 1
    boolean play_after 1
endform

# === APPLY PRESETS ===
presetName$ = "Custom"

if preset = 2
    # Classic Freeze
    decay_factor = 0.999
    glissando_oct_sec = 0
    top_partials = 10
    presetName$ = "Classic Freeze"
elsif preset = 3
    # Gentle Decay
    decay_factor = 0.5
    glissando_oct_sec = 0
    top_partials = 10
    presetName$ = "Gentle Decay"
elsif preset = 4
    # Rising Shimmer
    decay_factor = 0.3
    glissando_oct_sec = 0.15
    top_partials = 12
    presetName$ = "Rising Shimmer"
elsif preset = 5
    # Falling Shimmer
    decay_factor = 0.3
    glissando_oct_sec = -0.15
    top_partials = 12
    presetName$ = "Falling Shimmer"
elsif preset = 6
    # Ghostly Fade
    decay_factor = 0.15
    glissando_oct_sec = 0.02
    top_partials = 20
    tail_duration_sec = 4
    presetName$ = "Ghostly Fade"
elsif preset = 7
    # Metallic Drone
    decay_factor = 0.95
    glissando_oct_sec = 0
    top_partials = 6
    max_frequency_hz = 4000
    presetName$ = "Metallic Drone"
elsif preset = 8
    # Cosmic Drift
    decay_factor = 0.4
    glissando_oct_sec = 0.5
    top_partials = 15
    tail_duration_sec = 5
    presetName$ = "Cosmic Drift"
elsif preset = 9
    # Frozen Choir
    decay_factor = 0.8
    glissando_oct_sec = 0
    top_partials = 16
    stereo_delay_ms = 20
    max_frequency_hz = 5000
    presetName$ = "Frozen Choir"
elsif preset = 10
    # Disintegrating
    decay_factor = 0.05
    glissando_oct_sec = -0.05
    top_partials = 25
    tail_duration_sec = 1
    presetName$ = "Disintegrating"
elsif preset = 11
    # Ascending to Heaven
    decay_factor = 0.6
    glissando_oct_sec = 0.8
    top_partials = 10
    tail_duration_sec = 4
    max_frequency_hz = 12000
    presetName$ = "Ascending to Heaven"
elsif preset = 12
    # Descending to Hell
    decay_factor = 0.7
    glissando_oct_sec = -0.6
    top_partials = 8
    tail_duration_sec = 4
    max_frequency_hz = 3000
    presetName$ = "Descending to Hell"
elsif preset = 13
    # Spectral Dust
    decay_factor = 0.02
    glissando_oct_sec = 0.1
    top_partials = 3
    tail_duration_sec = 0.5
    presetName$ = "Spectral Dust"
endif

# === SETUP ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound."
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

writeInfoLine: "=== Spectral Freeze Synthesis ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Partials: ", top_partials, " | Decay: ", decay_factor
appendInfoLine: "Glissando: ", glissando_oct_sec, " oct/sec"
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
selectObject: orig_id
orig_sr = Get sampling frequency
n_channels = Get number of channels
orig_dur = Get total duration

# Prepare mono input
if n_channels > 1
    selectObject: orig_id
    input_id = Convert to mono
else
    selectObject: orig_id
    input_id = Copy: "input"
endif

# Keep dry copy for mix
selectObject: orig_id
if n_channels > 1
    dry_sound = Convert to mono
else
    dry_sound = Copy: "dry"
endif

# Add tail for freeze to decay
selectObject: input_id
tail_id = Create Sound from formula: "tail", 1, 0, tail_duration_sec, orig_sr, "0"
selectObject: input_id
plusObject: tail_id
temp_id = Concatenate
removeObject: input_id, tail_id
input_id = temp_id

selectObject: input_id
tot_dur = Get total duration

# Calculate constants
dt = frame_step_ms / 1000
win_dur = analysis_window_ms / 1000
d_frame = decay_factor ^ dt
gliss_ratio = 2 ^ (glissando_oct_sec * dt)
stereo_delay_sec = stereo_delay_ms / 1000
nframes = floor((tot_dur - win_dur) / dt)

appendInfoLine: "Processing ", nframes, " frames..."
appendInfoLine: ""

# Create output
out_chans = 1
if create_stereo_output
    out_chans = 2
endif
output_id = Create Sound from formula: "Freeze", out_chans, 0, tot_dur, orig_sr, "0"

# Initialize accumulators
acc_freq# = zero#(top_partials)
acc_amp# = zero#(top_partials)

# Peak suppression width
bin_hz = 1 / win_dur
suppress_bins = round(50 / bin_hz)
if suppress_bins < 1
    suppress_bins = 1
endif

# === MAIN LOOP ===
for i from 0 to nframes - 1
    if i mod 50 = 0
        perc = i / nframes * 100
        appendInfoLine: "Progress: ", fixed$(perc, 0), "%"
    endif

    # Time bounds
    tc = i * dt + win_dur/2
    t_start = tc - win_dur/2
    t_end = tc + win_dur/2
    
    # 1. ANALYZE FRAME
    selectObject: input_id
    frame_id = Extract part: t_start, t_end, "hanning", 1, "yes"
    
    spec_id = To Spectrum: "yes"
    selectObject: spec_id
    mat_id = To Matrix
    
    # Calculate magnitude spectrum (row 1 = real, row 2 = imag)
    selectObject: mat_id
    Formula: "if row = 1 then sqrt(self^2 + self[2,col]^2) else 0 fi"
    
    nc = Get number of columns
    freq_step = (orig_sr/2) / (nc - 1)
    max_col = round(max_frequency_hz / freq_step) + 1
    if max_col > nc
        max_col = nc
    endif
    
    # Limit frequency range
    Formula: "if col > " + string$(max_col) + " then 0 else self fi"
    
    # 2. UPDATE ACCUMULATORS (decay + glissando)
    for k from 1 to top_partials
        acc_amp#[k] = acc_amp#[k] * d_frame
        if acc_freq#[k] > 0
            acc_freq#[k] = acc_freq#[k] * gliss_ratio
            if acc_freq#[k] > max_frequency_hz
                acc_freq#[k] = max_frequency_hz
            elsif acc_freq#[k] < 20
                acc_freq#[k] = 20
            endif
        endif
    endfor
    
    # 3. FIND PEAKS
    for k from 1 to top_partials
        selectObject: mat_id
        
        cur_max = -1
        cur_col = -1
        
        for c from 1 to max_col
            val = Get value in cell: 1, c
            if val > cur_max
                cur_max = val
                cur_col = c
            endif
        endfor
        
        if cur_max > 0.000001
            cur_freq = (cur_col - 1) * freq_step
            
            # Freeze: only update if new peak is louder
            if cur_max > acc_amp#[k]
                acc_amp#[k] = cur_max
                acc_freq#[k] = cur_freq
            endif
            
            # Suppress this peak region
            sup_c1 = cur_col - suppress_bins
            sup_c2 = cur_col + suppress_bins
            Formula: "if col >= " + string$(sup_c1) + " and col <= " + string$(sup_c2) + " then 0 else self fi"
        endif
    endfor
    
    # 4. SYNTHESIZE GRAIN
    Create Sound from formula: "grain", out_chans, 0, win_dur, orig_sr, "0"
    grain_id = selected("Sound")
    Shift times to: "start time", t_start
    
    # Build synthesis formula
    left_sum$ = ""
    right_sum$ = ""
    s_delay$ = fixed$(stereo_delay_sec, 6)
    
    found_partials = 0
    
    for k from 1 to top_partials
        freq = acc_freq#[k]
        amp = acc_amp#[k]
        
        if freq > 20 and amp > 0.000001
            amp_lin = amp / (win_dur * orig_sr / 4)
            s_freq$ = fixed$(freq, 2)
            s_amp$ = fixed$(amp_lin, 8)
            
            term_L$ = " + " + s_amp$ + " * sin(2*pi*" + s_freq$ + "*x)"
            left_sum$ = left_sum$ + term_L$
            
            if out_chans = 2
                term_R$ = " + " + s_amp$ + " * sin(2*pi*" + s_freq$ + "*(x - " + s_delay$ + "))"
                right_sum$ = right_sum$ + term_R$
            endif
            
            found_partials = 1
        endif
    endfor
    
    if found_partials
        if out_chans = 1
            Formula: "self" + left_sum$
        else
            Formula: "if row = 1 then self" + left_sum$ + " else self" + right_sum$ + " fi"
        endif
        
        # Hanning window
        s_dur$ = fixed$(win_dur, 6)
        s_start$ = fixed$(t_start, 6)
        Formula: "self * 0.5 * (1 - cos(2*pi * (x - " + s_start$ + ") / " + s_dur$ + "))"
    endif
    
    # 5. MIX TO OUTPUT
    selectObject: output_id
    s_gid$ = string$(grain_id)
    s_end$ = fixed$(t_end, 6)
    Formula: "if x >= " + s_start$ + " and x <= " + s_end$ + " then self + object(" + s_gid$ + ", x) else self fi"
    
    removeObject: frame_id, spec_id, mat_id, grain_id
endfor

# Store final partials for visualization
final_freq# = acc_freq#
final_amp# = acc_amp#

# === WET/DRY MIX ===
if dry_level > 0
    # Extend dry sound to match output length
    selectObject: dry_sound
    dry_dur = Get total duration
    
    if tot_dur > dry_dur
        silence_dur = tot_dur - dry_dur
        Create Sound from formula: "silence", 1, 0, silence_dur, orig_sr, "0"
        silence_id = selected("Sound")
        selectObject: dry_sound
        plusObject: silence_id
        extended_dry = Concatenate
        removeObject: dry_sound, silence_id
        dry_sound = extended_dry
    endif
    
    # Mix
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: output_id
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
endif

# === FINALIZE ===
selectObject: output_id
Rename: orig_name$ + "_freeze"
Scale peak: 10^(target_peak_db / 20)

result = output_id

removeObject: input_id, dry_sound

# === VISUALIZATION ===
if draw_visualization
    # Create spectra for display
    selectObject: orig_id
    if n_channels > 1
        orig_mono = Convert to mono
    else
        orig_mono = Copy: "orig_mono"
    endif
    selectObject: orig_mono
    orig_spectrum = To Spectrum: "yes"
    
    selectObject: result
    if out_chans > 1
        result_mono = Convert to mono
    else
        result_mono = Copy: "result_mono"
    endif
    selectObject: result_mono
    result_spectrum = To Spectrum: "yes"
    
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Freeze: " + presetName$
    
    # --- Original waveform ---
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.4, 3.8, 0.7, 1.5
    selectObject: orig_id
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    
    # --- Original spectrum ---
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.4, 7.8, 0.7, 1.5
    selectObject: orig_spectrum
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, max_frequency_hz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    
    # --- Result waveform ---
    Select outer viewport: 0, 4, 1.8, 2.8
    Select inner viewport: 0.4, 3.8, 1.9, 2.7
    selectObject: result
    Colour: "{0.2, 0.6, 0.9}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freeze"
    Text bottom: "yes", "Time (s)"
    
    # --- Result spectrum ---
    Select outer viewport: 4, 8, 1.8, 2.8
    Select inner viewport: 4.4, 7.8, 1.9, 2.7
    selectObject: result_spectrum
    Colour: "{0.9, 0.5, 0.2}"
    Draw: 0, max_frequency_hz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freeze"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Frozen partials ---
    Select outer viewport: 0, 8, 3.0, 4.0
    Select inner viewport: 0.4, 7.6, 3.1, 3.9
    
    Axes: 0, max_frequency_hz, 0, 1.2
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, max_frequency_hz, 0, 1.2
    
    # Find max amplitude for scaling
    max_amp = 0.000001
    for k from 1 to top_partials
        if final_amp#[k] > max_amp
            max_amp = final_amp#[k]
        endif
    endfor
    
    # Draw partials
    for k from 1 to top_partials
        if final_freq#[k] > 20 and final_amp#[k] > 0.000001
            amp_norm = final_amp#[k] / max_amp
            if amp_norm > 1
                amp_norm = 1
            endif
            
            # Color by glissando direction
            if glissando_oct_sec > 0
                col$ = "{0.2, 0.7, 0.4}"
            elsif glissando_oct_sec < 0
                col$ = "{0.8, 0.3, 0.3}"
            else
                col$ = "{0.3, 0.5, 0.8}"
            endif
            
            Colour: col$
            Draw line: final_freq#[k], 0, final_freq#[k], amp_norm
            Paint circle (mm): col$, final_freq#[k], amp_norm, 1.2
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Partials"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", 
        ... "Partials: " + string$(top_partials) +
        ... " | Decay: " + fixed$(decay_factor, 3) +
        ... " | Gliss: " + fixed$(glissando_oct_sec, 2) + " oct/s" +
        ... " | Tail: " + fixed$(tail_duration_sec, 1) + "s" +
        ... " | Wet: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
    
    # Cleanup
    removeObject: orig_mono, orig_spectrum, result_mono, result_spectrum
endif

# === FINAL INFO ===
appendInfoLine: ""
appendInfoLine: "=== Frozen Partials ==="
for k from 1 to top_partials
    if final_freq#[k] > 20
        appendInfoLine: "  ", k, ": ", fixed$(final_freq#[k], 1), " Hz"
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: result
if play_after
    Play
endif