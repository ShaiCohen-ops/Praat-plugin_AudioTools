# ============================================================
# Praat AudioTools - Spectral Freeze Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.5 (2026) - Guard too-short input; O(N^2) mix -> Formula (part)
# License: MIT License
#
# Description:
#   Spectral freeze effect - captures and holds frequency peaks,
#   creating sustained, evolving drones from any sound. Uses
#   additive synthesis to resynthesize frozen partials with
#   optional decay and pitch drift (glissando).
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
    positive max_frequency_hz 6000
    integer top_partials 10
    comment === Performance ===
    positive resample_to_hz 12000
    comment (Lower = Faster. 12000 is great for drones.)
    comment === Transformation ===
    positive decay_factor 0.2
    real glissando_oct_sec 0.0
    comment === Mix ===
    real wet_dry_percent 100
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
    decay_factor = 0.999
    glissando_oct_sec = 0
    top_partials = 10
    presetName$ = "Classic Freeze"
elsif preset = 3
    decay_factor = 0.5
    glissando_oct_sec = 0
    top_partials = 10
    presetName$ = "Gentle Decay"
elsif preset = 4
    decay_factor = 0.3
    glissando_oct_sec = 0.15
    top_partials = 12
    presetName$ = "Rising Shimmer"
elsif preset = 5
    decay_factor = 0.3
    glissando_oct_sec = -0.15
    top_partials = 12
    presetName$ = "Falling Shimmer"
elsif preset = 6
    decay_factor = 0.15
    glissando_oct_sec = 0.02
    top_partials = 20
    tail_duration_sec = 4
    presetName$ = "Ghostly Fade"
elsif preset = 7
    decay_factor = 0.95
    glissando_oct_sec = 0
    top_partials = 6
    max_frequency_hz = 3000
    presetName$ = "Metallic Drone"
elsif preset = 8
    decay_factor = 0.4
    glissando_oct_sec = 0.5
    top_partials = 15
    tail_duration_sec = 5
    presetName$ = "Cosmic Drift"
elsif preset = 9
    decay_factor = 0.8
    glissando_oct_sec = 0
    top_partials = 16
    stereo_delay_ms = 20
    max_frequency_hz = 4000
    presetName$ = "Frozen Choir"
elsif preset = 10
    decay_factor = 0.05
    glissando_oct_sec = -0.05
    top_partials = 25
    tail_duration_sec = 1
    presetName$ = "Disintegrating"
elsif preset = 11
    decay_factor = 0.6
    glissando_oct_sec = 0.8
    top_partials = 10
    tail_duration_sec = 4
    max_frequency_hz = 5000
    presetName$ = "Ascending to Heaven"
elsif preset = 12
    decay_factor = 0.7
    glissando_oct_sec = -0.6
    top_partials = 8
    tail_duration_sec = 4
    max_frequency_hz = 2500
    presetName$ = "Descending to Hell"
elsif preset = 13
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
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

writeInfoLine: "=== Spectral Freeze (V3 + Resample) ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Resampling to: ", resample_to_hz, " Hz"

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
selectObject: orig_id
orig_sr = Get sampling frequency
n_channels = Get number of channels
orig_dur = Get total duration

# === 1. RESAMPLE INPUT (The Speed Trick) ===
selectObject: orig_id
# Resample to lower rate for processing
input_id = Resample: resample_to_hz, 50
Rename: "work_copy"
work_sr = resample_to_hz

# Convert to mono for analysis
if n_channels > 1
    selectObject: input_id
    work_mono = Convert to mono
    removeObject: input_id
    input_id = work_mono
endif

# Keep dry copy (resampled)
selectObject: input_id
dry_sound = Copy: "dry_work"

# Add tail
selectObject: input_id
tail_id = Create Sound from formula: "tail", 1, 0, tail_duration_sec, work_sr, "0"
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

# Guard: too short to analyse even one frame. Praat's "for i from 0 to
# nframes-1" would run zero iterations silently and emit pure silence, so
# stop with a clear message (and clean up what we already created).
if nframes < 1
    nocheck removeObject: input_id
    nocheck removeObject: dry_sound
    exitScript: "Input too short for analysis. Need at least one " +
        ... "analysis window (" + fixed$(analysis_window_ms, 0) +
        ... " ms) plus a frame step within the sound + tail. Use a longer " +
        ... "sound, a shorter window, or a larger tail."
endif

# Validate Nyquist
if max_frequency_hz > work_sr / 2
    max_frequency_hz = work_sr / 2
    appendInfoLine: "Max Frequency capped to ", max_frequency_hz, " Hz (Nyquist)"
endif

appendInfoLine: "Processing ", nframes, " frames..."
appendInfoLine: ""

# Create output (at lower SR for speed)
out_chans = 1
if create_stereo_output
    out_chans = 2
endif
output_id = Create Sound from formula: "Freeze", out_chans, 0, tot_dur, work_sr, "0"

# Initialize accumulators
acc_freq# = zero#(top_partials)
acc_amp# = zero#(top_partials)

# Peak suppression width
bin_hz = 1 / win_dur
suppress_bins = round(50 / bin_hz)
if suppress_bins < 1
    suppress_bins = 1
endif

# === MAIN LOOP (V3 Logic) ===
for i from 0 to nframes - 1
    if i mod 50 = 0
        perc = i / nframes * 100
        appendInfoLine: "Progress: ", fixed$(perc, 0), "%"
    endif

    # Time bounds
    tc = i * dt + win_dur/2
    t_start = tc - win_dur/2
    t_end = tc + win_dur/2
    
    # 1. ANALYZE FRAME (V3 Style)
    selectObject: input_id
    frame_id = Extract part: t_start, t_end, "hanning", 1, "yes"
    
    spec_id = To Spectrum: "yes"
    selectObject: spec_id
    mat_id = To Matrix
    
    # Calculate magnitude spectrum (row 1 = real, row 2 = imag)
    selectObject: mat_id
    Formula: "if row = 1 then sqrt(self^2 + self[2,col]^2) else 0 fi"
    
    # === OPTIMIZATION: THE SOUND HACK (V3) ===
    # Convert Matrix to Sound to use fast "Time of maximum" commands
    
    # Get parameters
    nc = Get number of columns
    dx = Get column distance
    
    # Convert entire matrix to a temporary Sound
    tmp_sound = To Sound
    
    # Extract just the Magnitude (Channel 1)
    mag_sound = Extract one channel: 1
    Rename: "spectrum_slice"
    
    # Clean up the temp stereo sound
    removeObject: tmp_sound
    
    # 2. UPDATE ACCUMULATORS
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
    
    # 3. FAST PEAK FINDING (V3 Fixes)
    for k from 1 to top_partials
        selectObject: mag_sound
        
        # Use "Parabolic" (Verified)
        cur_freq = Get time of maximum: 0, max_frequency_hz, "Parabolic"
        
        # Use "Linear" (Verified)
        cur_max = Get value at time: 1, cur_freq, "Linear"
        
        if cur_max > 0.000001
            # Freeze Logic
            if cur_max > acc_amp#[k]
                acc_amp#[k] = cur_max
                acc_freq#[k] = cur_freq
            endif
            
            # SUPPRESSION: "Set value at sample number" (Verified V3)
            cur_samp = round(cur_freq / dx) + 1
            
            s_low = cur_samp - suppress_bins
            s_high = cur_samp + suppress_bins
            if s_low < 1
               s_low = 1
            endif
            if s_high > nc
               s_high = nc
            endif
            
            for s from s_low to s_high
                Set value at sample number: 1, s, 0
            endfor
        endif
    endfor
    
    removeObject: mag_sound
    
    # 4. SYNTHESIZE GRAIN (Resampled SR)
    left_sum$ = ""
    right_sum$ = ""
    s_delay$ = fixed$(stereo_delay_sec, 6)
    
    found_partials = 0
    
    for k from 1 to top_partials
        freq = acc_freq#[k]
        amp = acc_amp#[k]
        
        if freq > 20 and amp > 0.000001
            # Note: We use 'work_sr' here
            amp_lin = amp / (win_dur * work_sr / 4)
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
        s_dur$ = fixed$(win_dur, 6)
        window_form$ = "0.5 * (1 - cos(2*pi * x / " + s_dur$ + "))"
        
        if out_chans = 1
            final_form$ = "(" + mid$(left_sum$, 4, length(left_sum$)) + ") * " + window_form$
            Create Sound from formula: "grain", 1, 0, win_dur, work_sr, final_form$
        else
            Create Sound from formula: "grain", 2, 0, win_dur, work_sr, "0"
            Formula: "if row = 1 then (" + mid$(left_sum$, 4, length(left_sum$)) + ") * " + window_form$ + " else (" + mid$(right_sum$, 4, length(right_sum$)) + ") * " + window_form$ + " fi"
        endif
        grain_id = selected("Sound")
        
        # Shift
        Shift times to: "start time", t_start
        
        # 5. MIX TO OUTPUT (overlap-add)
        # Formula (part) evaluates ONLY the grain's sample range instead
        # of scanning the whole output buffer every frame. This turns the
        # mix from O(nframes x totalSamples) into O(nframes x grainSamples)
        # - the single biggest speedup for long outputs/tails.
        selectObject: output_id
        s_gid$ = string$(grain_id)
        mix_start = t_start
        mix_end = t_end
        if mix_start < 0
            mix_start = 0
        endif
        if mix_end > tot_dur
            mix_end = tot_dur
        endif

        Formula (part): mix_start, mix_end, 1, out_chans,
            ... "self + object(" + s_gid$ + ", x)"

        removeObject: grain_id
    endif
    
    removeObject: frame_id, spec_id, mat_id
endfor

# Store final partials for visualization
final_freq# = acc_freq#
final_amp# = acc_amp#

# === WET/DRY MIX ===
if dry_level > 0
    selectObject: dry_sound
    dry_dur = Get total duration
    
    if tot_dur > dry_dur
        silence_dur = tot_dur - dry_dur
        Create Sound from formula: "silence", 1, 0, silence_dur, work_sr, "0"
        silence_id = selected("Sound")
        selectObject: dry_sound
        plusObject: silence_id
        extended_dry = Concatenate
        removeObject: dry_sound, silence_id
        dry_sound = extended_dry
    endif
    
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
    
    max_amp = 0.000001
    for k from 1 to top_partials
        if final_amp#[k] > max_amp
            max_amp = final_amp#[k]
        endif
    endfor
    
    for k from 1 to top_partials
        if final_freq#[k] > 20 and final_amp#[k] > 0.000001
            amp_norm = final_amp#[k] / max_amp
            if amp_norm > 1
                amp_norm = 1
            endif
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
    
    # Fixed Text V3 logic
    paramInfo$ = "Partials: " + string$(top_partials) + " | Decay: " + fixed$(decay_factor, 3) + " | Resample: " + string$(resample_to_hz) + " Hz"
    Text: 0.5, "centre", 0.5, "half", paramInfo$
    
    Font size: 10
    Colour: "Black"
    
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