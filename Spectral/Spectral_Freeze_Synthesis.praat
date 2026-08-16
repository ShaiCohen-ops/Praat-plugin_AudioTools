# ============================================================
# Praat AudioTools - Spectral Freeze Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.7 (2026) - Mechanism-first measured visualization; held-bank trajectory QC
# License: MIT License
#
# Description:
#   Evolving spectral peak-hold freeze: analyzes successive frames,
#   holds/decays dominant spectral peaks, and resynthesizes them
#   additively with optional pitch drift (glissando). The legacy
#   grain-local phase reset is intentionally preserved for character.
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
    positive peak_separation_hz 50
    comment === Performance ===
    positive resample_to_hz 12000
    comment (Lower = Faster. 12000 is great for drones.)
    boolean restore_original_sample_rate 1
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
    decay_factor = 1.0
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

# Defensive parameter guards. Preserve creative behaviour where possible,
# but prevent invalid arrays, runaway growth, and non-sensical mix values.
if top_partials < 1
    top_partials = 1
endif
if decay_factor > 1
    decay_factor = 1
endif
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

writeInfoLine: "=== Spectral Freeze v0.7 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Analysis rate: ", resample_to_hz, " Hz"

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
selectObject: orig_id
orig_sr = Get sampling frequency
n_channels = Get number of channels
orig_dur = Get total duration

# === 1. RESAMPLE FOR ANALYSIS ===
# Keep a multichannel work copy separate from the mono analysis path.
# This fixes the old behaviour where the dry signal was copied only after
# conversion to mono and therefore lost the original stereo image.
selectObject: orig_id
work_source = Resample: resample_to_hz, 50
Rename: "freeze_work_multichannel"
selectObject: work_source
work_sr = Get sampling frequency

# Analysis remains mono by design: peak tracking is global, while the dry
# path retains its channel structure independently.
selectObject: work_source
if n_channels > 1
    input_id = Convert to mono
else
    input_id = Copy: "freeze_analysis_mono"
endif
Rename: "freeze_analysis_mono"

# Add analysis/synthesis tail only to the mono analysis signal.
selectObject: input_id
tail_id = Create Sound from formula: "freeze_tail", 1, 0, tail_duration_sec, work_sr, "0"
selectObject: input_id
plusObject: tail_id
temp_id = Concatenate
removeObject: input_id, tail_id
input_id = temp_id
Rename: "freeze_analysis_with_tail"

selectObject: input_id
tot_dur = Get total duration

# Calculate constants. decay_factor is interpreted as a per-second retention
# ratio, so d_frame converts it to the actual frame interval.
dt = frame_step_ms / 1000
win_dur = analysis_window_ms / 1000
d_frame = decay_factor ^ dt
gliss_ratio = 2 ^ (glissando_oct_sec * dt)
stereo_delay_sec = stereo_delay_ms / 1000
nframes = floor((tot_dur - win_dur) / dt) + 1

# Guard: at least one complete analysis window must fit.
if nframes < 1
    nocheck removeObject: input_id
    nocheck removeObject: work_source
    exitScript: "Input too short for analysis. Need at least one complete " +
        ... "analysis window (" + fixed$(analysis_window_ms, 0) + " ms)."
endif

# Validate Nyquist at the work rate.
if max_frequency_hz > work_sr / 2
    max_frequency_hz = work_sr / 2
    appendInfoLine: "Max frequency capped to ", max_frequency_hz, " Hz (Nyquist)."
endif

appendInfoLine: "Processing ", nframes, " frames..."
appendInfoLine: "Peak separation: ", peak_separation_hz, " Hz"
appendInfoLine: ""

# Create wet output at the work rate for speed.
out_chans = 1
if create_stereo_output
    out_chans = 2
endif
output_id = Create Sound from formula: "Freeze_wet", out_chans, 0, tot_dur, work_sr, "0"

# Initialize accumulators
acc_freq# = zero#(top_partials)
acc_amp# = zero#(top_partials)

# Visualization/QC history. These vectors record the ACTUAL held bank after
# every analysis frame, so the later picture is a measurement of the state
# that drove synthesis rather than an illustrative model. They are allocated
# only when visualization is requested.
hold_updates = 0
active_sum = 0
hist_max_amp = 1e-12
if draw_visualization
    hist_freq# = zero#(nframes * top_partials)
    hist_amp# = zero#(nframes * top_partials)
endif

# Peak suppression width: user-facing spectral separation between selected peaks.
bin_hz = 1 / win_dur
suppress_bins = round(peak_separation_hz / bin_hz)
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
                hold_updates = hold_updates + 1
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

    # Record the actual held-bank state used for this grain.
    frame_active = 0
    for k from 1 to top_partials
        if acc_freq#[k] > 20 and acc_amp#[k] > 0.000001
            frame_active = frame_active + 1
        endif
        if draw_visualization
            hidx = i * top_partials + k
            hist_freq#[hidx] = acc_freq#[k]
            hist_amp#[hidx] = acc_amp#[k]
            if acc_amp#[k] > hist_max_amp
                hist_max_amp = acc_amp#[k]
            endif
        endif
    endfor
    active_sum = active_sum + frame_active
    
    # 4. SYNTHESIZE GRAIN (Resampled SR)
    left_sum$ = ""
    right_sum$ = ""
    s_delay$ = fixed$(stereo_delay_sec, 6)
    
    found_partials = 0
    
    for k from 1 to top_partials
        freq = acc_freq#[k]
        amp = acc_amp#[k]
        
        if freq > 20 and amp > 0.000001
            # Spectrum magnitude is in Pa*s (Pa/Hz): for a bin-centred sine
            # under a Hanning window, |X(f)| ~= A * win_dur / 4. Therefore
            # the sinusoid peak amplitude is A ~= 4*|X|/win_dur. The old
            # v0.5 formula divided by work_sr as well, making the wet signal
            # smaller by roughly the sampling rate and breaking wet/dry balance.
            amp_lin = 4 * amp / win_dur
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

        # Explicit y preserves the grain channel. Without it, a multichannel
        # Sound can be averaged, which collapses the intended stereo phase width.
        Formula (part): mix_start, mix_end, 1, out_chans,
            ... "self + object(" + s_gid$ + ", x, y)"

        removeObject: grain_id
    endif
    
    removeObject: frame_id, spec_id, mat_id
endfor

# Store final partials for visualization
final_freq# = acc_freq#
final_amp# = acc_amp#

# === OUTPUT RATE + WET/DRY MIX ===
# Optional restoration changes only the sample grid; it cannot recreate
# frequencies removed by the low work-rate analysis. Crucially, the dry path
# is taken from the original Sound when the final rate is the original rate.
final_sr = work_sr
if restore_original_sample_rate and abs(orig_sr - work_sr) > 0.01
    selectObject: output_id
    restored_wet = Resample: orig_sr, 50
    removeObject: output_id
    output_id = restored_wet
    final_sr = orig_sr
endif

# Preserve a pure-wet measurement object for visualization BEFORE dry/wet
# mixing and final peak scaling. This makes the spectral comparison explain
# the synthesis itself rather than the user's mix choice.
wet_viz_id = 0
if draw_visualization and wet_level > 0
    selectObject: output_id
    wet_viz_id = Copy: "freeze_pure_wet_viz"
endif

# Wet = 0 is a true bypass: copy the untouched source, with no resampling,
# pseudo-stereo, tail, or peak normalization.
if wet_level = 0
    selectObject: orig_id
    bypass_id = Copy: orig_name$ + "_freeze"
    removeObject: output_id
    output_id = bypass_id
    result = output_id
    final_sr = orig_sr
    out_chans = n_channels
    tot_dur = orig_dur
else
    # Prepare a dry object with the same channel count as the wet output.
    # At original output rate, use the untouched original as the dry source.
    # At work rate, use Praat's sinc-resampled multichannel work copy.
    if abs(final_sr - orig_sr) < 0.01
        dry_base = orig_id
    else
        dry_base = work_source
    endif

    if dry_level > 0
        selectObject: dry_base
        dry_base_chans = Get number of channels
        dry_dur = Get total duration

        if out_chans = 1
            if dry_base_chans > 1
                dry_match = Convert to mono
            else
                dry_match = Copy: "freeze_dry_match"
            endif
        else
            if dry_base_chans = 1
                s_dry$ = string$(dry_base)
                dry_match = Create Sound from formula: "freeze_dry_match", 2, 0, dry_dur, final_sr,
                    ... "object(" + s_dry$ + ", x, 1)"
            elsif dry_base_chans = 2
                dry_match = Copy: "freeze_dry_match"
            else
                # Stereo output from a >2-channel source preserves channels 1 and 2.
                s_dry$ = string$(dry_base)
                dry_match = Create Sound from formula: "freeze_dry_match", 2, 0, dry_dur, final_sr,
                    ... "if row = 1 then object(" + s_dry$ + ", x, 1) else object(" + s_dry$ + ", x, 2) fi"
            endif
        endif

        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        dry_id_str$ = string$(dry_match)

        selectObject: output_id
        # object(..., x, y) performs time-domain interpolation and returns zero
        # outside the dry Sound, so the synthesis tail naturally remains wet-only.
        Formula: "self * " + wet_str$ + " + object(" + dry_id_str$ + ", x, y) * " + dry_str$
        removeObject: dry_match
    endif

    # Peak normalization is applied only when an effect is present; bypass stays bit-faithful.
    # Guard all-zero output so Scale peak never has to normalize silence.
    selectObject: output_id
    Rename: orig_name$ + "_freeze"
    output_rms_pre_scale = Get root-mean-square: 0, 0
    if output_rms_pre_scale > 0
        Scale peak: 10^(target_peak_db / 20)
    endif
    result = output_id
endif

# Analysis/work objects are temporary.
removeObject: input_id, work_source

# === VISUALIZATION ===
if draw_visualization
    # ------------------------------------------------------------------
    # Measured objects
    # ------------------------------------------------------------------
    # Representative source channel: strongest of channels 1/2. Do not
    # fold stereo to mono because phase cancellation would distort the claim.
    selectObject: orig_id
    orig_vis_ch = 1
    if n_channels > 1
        srcL = Extract one channel: 1
        srcLrms = Get root-mean-square: 0, 0
        selectObject: orig_id
        srcR = Extract one channel: 2
        srcRrms = Get root-mean-square: 0, 0
        if srcRrms > srcLrms
            orig_vis_ch = 2
            orig_vis = srcR
            removeObject: srcL
        else
            orig_vis = srcL
            removeObject: srcR
        endif
    else
        orig_vis = Copy: "freeze_viz_source"
    endif

    # Pure wet channel measured before dry/wet mixing and peak scaling.
    # For bypass there is no synthesized wet object; compare against source.
    if wet_viz_id <> 0
        selectObject: wet_viz_id
        wet_chans = Get number of channels
        wet_vis_ch = 1
        if wet_chans > 1
            wetL = Extract one channel: 1
            wetLrms = Get root-mean-square: 0, 0
            selectObject: wet_viz_id
            wetR = Extract one channel: 2
            wetRrms = Get root-mean-square: 0, 0
            if wetRrms > wetLrms
                wet_vis_ch = 2
                wet_vis = wetR
                removeObject: wetL
            else
                wet_vis = wetL
                removeObject: wetR
            endif
        else
            wet_vis = Copy: "freeze_viz_wet"
        endif
    else
        selectObject: orig_vis
        wet_vis = Copy: "freeze_viz_wet_bypass"
        wet_vis_ch = orig_vis_ch
    endif

    # Compare spectra over the same source-duration interval. The freeze tail
    # is valid output, but including it only on the wet side would bias LTAS
    # level comparisons because the integration durations would differ.
    selectObject: wet_vis
    wet_viz_dur = Get total duration
    if wet_viz_dur > orig_dur + 1e-9
        wet_trim = Extract part: 0, orig_dur, "rectangular", 1, "no"
        removeObject: wet_vis
        wet_vis = wet_trim
    endif

    # Final output channels for the measured waveform panel.
    selectObject: result
    result_chans = Get number of channels
    resultL = Extract one channel: 1
    selectObject: resultL
    outPeakL = Get absolute extremum: 0, 0, "None"
    outRmsL = Get root-mean-square: 0, 0
    if result_chans > 1
        selectObject: result
        resultR = Extract one channel: 2
        selectObject: resultR
        outPeakR = Get absolute extremum: 0, 0, "None"
        outRmsR = Get root-mean-square: 0, 0
    else
        resultR = 0
        outPeakR = 0
        outRmsR = 0
    endif
    vizPeak = max(outPeakL, outPeakR)
    if vizPeak < 1e-8
        vizPeak = 1
    else
        vizPeak = 1.05 * vizPeak
    endif

    # Input QC on the actually displayed source channel.
    selectObject: orig_vis
    input_peak = Get absolute extremum: 0, 0, "None"
    input_rms = Get root-mean-square: 0, 0
    if result_chans > 1
        output_rms = sqrt((outRmsL^2 + outRmsR^2) / 2)
    else
        output_rms = outRmsL
    endif
    if input_rms > 0 and output_rms > 0
        rms_ratio_db = 20 * log10(output_rms / input_rms)
        rms_ratio_text$ = fixed$(rms_ratio_db, 1) + " dB"
    else
        rms_ratio_db = undefined
        rms_ratio_text$ = "undefined"
    endif
    mean_active = active_sum / nframes

    # Smoothed LTAS comparison: source vs PURE wet. Use local frequency
    # averaging and draw manually on a logarithmic frequency axis.
    selectObject: orig_vis
    src_spec = To Spectrum: "yes"
    To Ltas (1-to-1)
    src_ltas = selected("Ltas")

    selectObject: wet_vis
    wet_spec = To Spectrum: "yes"
    To Ltas (1-to-1)
    wet_ltas = selected("Ltas")

    spec_fmin = 50
    spec_fmax = min(max_frequency_hz, 0.45 * final_sr)
    if spec_fmax > 16000
        spec_fmax = 16000
    endif
    if spec_fmax <= spec_fmin * 1.2
        spec_fmin = max(1, spec_fmax / 5)
    endif
    log_fmin = log10(spec_fmin)
    log_fmax = log10(spec_fmax)
    n_spec_points = 90
    spec_min = 1e9
    spec_max = -1e9
    src_peak_db = -1e9
    wet_peak_db = -1e9
    src_peak_freq = spec_fmin
    wet_peak_freq = spec_fmin

    for q from 1 to n_spec_points
        frac = (q - 1) / (n_spec_points - 1)
        freq = spec_fmin * (spec_fmax / spec_fmin)^frac
        selectObject: src_ltas
        b1 = Get bin number from frequency: 0.94 * freq
        b1 = round(b1)
        b2 = Get bin number from frequency: 0.97 * freq
        b2 = round(b2)
        b3 = Get bin number from frequency: freq
        b3 = round(b3)
        b4 = Get bin number from frequency: 1.03 * freq
        b4 = round(b4)
        b5 = Get bin number from frequency: 1.06 * freq
        b5 = round(b5)
        sv1 = Get value in bin: b1
        sv2 = Get value in bin: b2
        sv3 = Get value in bin: b3
        sv4 = Get value in bin: b4
        sv5 = Get value in bin: b5
        sdb = (sv1 + sv2 + sv3 + sv4 + sv5) / 5
        selectObject: wet_ltas
        b1 = Get bin number from frequency: 0.94 * freq
        b1 = round(b1)
        b2 = Get bin number from frequency: 0.97 * freq
        b2 = round(b2)
        b3 = Get bin number from frequency: freq
        b3 = round(b3)
        b4 = Get bin number from frequency: 1.03 * freq
        b4 = round(b4)
        b5 = Get bin number from frequency: 1.06 * freq
        b5 = round(b5)
        wv1 = Get value in bin: b1
        wv2 = Get value in bin: b2
        wv3 = Get value in bin: b3
        wv4 = Get value in bin: b4
        wv5 = Get value in bin: b5
        wdb = (wv1 + wv2 + wv3 + wv4 + wv5) / 5
        if sdb < spec_min
            spec_min = sdb
        endif
        if wdb < spec_min
            spec_min = wdb
        endif
        if sdb > spec_max
            spec_max = sdb
        endif
        if wdb > spec_max
            spec_max = wdb
        endif
        if sdb > src_peak_db
            src_peak_db = sdb
            src_peak_freq = freq
        endif
        if wdb > wet_peak_db
            wet_peak_db = wdb
            wet_peak_freq = freq
        endif
    endfor
    spec_lo = 10 * floor((spec_min - 5) / 10)
    spec_hi = 10 * ceiling((spec_max + 5) / 10)
    if spec_hi <= spec_lo + 20
        spec_hi = spec_lo + 20
    endif

    # Shared round tick helper.
    procedure freezeVizStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = 1 * .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    Erase all

    # ------------------------------------------------------------------
    # Header
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 0.00, 0.40
    Select inner viewport: 0, 8, 0.00, 0.40
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "Spectral Freeze v0.7 — " + presetName$

    Select outer viewport: 0, 8, 0.42, 0.73
    Select inner viewport: 0, 8, 0.42, 0.73
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5, "centre", 0.66, "half", "mono analysis -> ranked spectral peaks -> decaying held bank -> glissando -> additive Hann grains -> overlap-add -> dry/wet"
    Text: 0.5, "centre", 0.22, "half", "hold law: amplitude=max(decayed hold, ranked peak) | frequency drifts each hop until a stronger peak replaces the slot"

    # ------------------------------------------------------------------
    # A  Grain geometry
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 0.79, 0.99
    Select inner viewport: 0, 8, 0.79, 0.99
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  Synthesis geometry: Hann grains and the actual overlap sum"

    Select outer viewport: 0, 8, 1.01, 2.05
    Select inner viewport: 0.62, 7.72, 1.08, 1.93
    nWinDraw = 6
    aXmax = (nWinDraw - 1) * dt + win_dur
    # Measure the overlap-sum peak first so the panel gets an explicit,
    # data-derived vertical range instead of a loose theoretical ceiling.
    overlapPeak = 0
    for q from 0 to 280
        tq = aXmax * q / 280
        sumq = 0
        for kk from 0 to nWinDraw - 1
            ws = kk * dt
            if tq >= ws and tq <= ws + win_dur
                uq = (tq - ws) / win_dur
                sumq = sumq + 0.5 * (1 - cos(2*pi*uq))
            endif
        endfor
        if sumq > overlapPeak
            overlapPeak = sumq
        endif
    endfor
    aYmax = 1.12 * max(1, overlapPeak)
    Axes: 0, aXmax, 0, aYmax
    Paint rectangle: "{0.975,0.975,0.978}", 0, aXmax, 0, aYmax

    nDraw = 110
    for kk from 0 to nWinDraw - 1
        ws = kk * dt
        Colour: "{0.43,0.55,0.74}"
        Line width: 1
        for q from 1 to nDraw
            t0 = ws + win_dur * (q - 1) / nDraw
            t1 = ws + win_dur * q / nDraw
            w0 = 0.5 * (1 - cos(2*pi*(q - 1)/nDraw))
            w1 = 0.5 * (1 - cos(2*pi*q/nDraw))
            Draw line: t0, w0, t1, w1
        endfor
    endfor

    Colour: "{0.78,0.34,0.25}"
    Line width: 2
    for q from 1 to 280
        t0 = aXmax * (q - 1) / 280
        t1 = aXmax * q / 280
        sum0 = 0
        sum1 = 0
        for kk from 0 to nWinDraw - 1
            ws = kk * dt
            if t0 >= ws and t0 <= ws + win_dur
                u0 = (t0 - ws) / win_dur
                sum0 = sum0 + 0.5 * (1 - cos(2*pi*u0))
            endif
            if t1 >= ws and t1 <= ws + win_dur
                u1 = (t1 - ws) / win_dur
                sum1 = sum1 + 0.5 * (1 - cos(2*pi*u1))
            endif
        endfor
        Draw line: t0, sum0, t1, sum1
    endfor
    Line width: 1

    Select inner viewport: 0.62, 7.72, 1.08, 1.93
    Axes: 0, aXmax, 0, aYmax
    Font size: 5
    Colour: "{0.34,0.34,0.40}"
    Text: 0.02*aXmax, "left", 0.92*aYmax, "half", "blue = individual Hann grains | orange = their overlap sum"
    Colour: "Black"
    Draw inner box
    @freezeVizStep: aYmax, 4
    Marks left every: 1, freezeVizStep.step, "yes", "yes", "no"
    @freezeVizStep: aXmax, 6
    Marks bottom every: 1, freezeVizStep.step, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "window / sum"

    Select outer viewport: 0, 8, 2.05, 2.23
    Select inner viewport: 0, 8, 2.05, 2.23
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5, "centre", 0.5, "half", "window " + fixed$(win_dur*1000,1) + " ms | hop " + fixed$(dt*1000,1) + " ms | orange overlap breathing is retained as grain character"

    # ------------------------------------------------------------------
    # B  Actual held-bank trajectories
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 2.29, 2.49
    Select inner viewport: 0, 8, 2.29, 2.49
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "B  Actual held partial bank through time (log-frequency)"

    Select outer viewport: 0, 8, 2.51, 3.73
    Select inner viewport: 0.72, 7.72, 2.59, 3.57
    track_fmin = 20
    track_fmax = max(max_frequency_hz, 40)
    track_ymin = log10(track_fmin)
    track_ymax = log10(track_fmax)
    Axes: 0, tot_dur, track_ymin, track_ymax
    Paint rectangle: "{0.975,0.975,0.978}", 0, tot_dur, track_ymin, track_ymax

    hist_stride = max(1, floor(nframes / 300))
    for k from 1 to top_partials
        ii = hist_stride
        while ii <= nframes - 1
            idx0 = (ii - hist_stride) * top_partials + k
            idx1 = ii * top_partials + k
            f0 = hist_freq#[idx0]
            f1 = hist_freq#[idx1]
            a0 = hist_amp#[idx0]
            a1 = hist_amp#[idx1]
            if f0 >= track_fmin and f1 >= track_fmin and a0 > 0.000001 and a1 > 0.000001
                relA = min(1, max(a0,a1) / hist_max_amp)
                if relA > 0.45
                    Colour: "{0.22,0.45,0.76}"
                    Line width: 1.5
                elsif relA > 0.15
                    Colour: "{0.42,0.57,0.76}"
                    Line width: 1
                else
                    Colour: "{0.72,0.75,0.80}"
                    Line width: 1
                endif
                tt0 = (ii - hist_stride) * dt + win_dur/2
                tt1 = ii * dt + win_dur/2
                Draw line: tt0, log10(f0), tt1, log10(f1)
            endif
            ii = ii + hist_stride
        endwhile
    endfor
    Line width: 1

    Select inner viewport: 0.72, 7.72, 2.59, 3.57
    Axes: 0, tot_dur, track_ymin, track_ymax
    Colour: "Black"
    Draw inner box
    Font size: 5
    @freezeVizStep: tot_dur, 6
    Marks bottom every: 1, freezeVizStep.step, "yes", "yes", "no"
    # Manual log-frequency marks keep labels readable and avoid scientific notation.
    for fq from 1 to 8
        if fq = 1
            fm = 50
            fl$ = "50"
        elsif fq = 2
            fm = 100
            fl$ = "100"
        elsif fq = 3
            fm = 200
            fl$ = "200"
        elsif fq = 4
            fm = 500
            fl$ = "500"
        elsif fq = 5
            fm = 1000
            fl$ = "1k"
        elsif fq = 6
            fm = 2000
            fl$ = "2k"
        elsif fq = 7
            fm = 5000
            fl$ = "5k"
        else
            fm = 10000
            fl$ = "10k"
        endif
        if fm >= track_fmin and fm <= track_fmax
            One mark left: log10(fm), "no", "yes", "no", fl$
        endif
    endfor
    Font size: 6
    Text left: "yes", "held frequency"
    Text bottom: "yes", "time (s)"

    Select outer viewport: 0, 8, 3.73, 3.93
    Select inner viewport: 0, 8, 3.73, 3.93
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5, "centre", 0.66, "half", "every line is recorded from the state that synthesized a grain; upward/downward slopes are glissando, abrupt jumps are stronger-peak replacements"
    Text: 0.5, "centre", 0.22, "half", "active " + fixed$(mean_active,1) + "/" + string$(top_partials) + " partials | updates " + string$(hold_updates) + " | separation " + fixed$(peak_separation_hz,0) + " Hz"

    # ------------------------------------------------------------------
    # C  Measured spectral comparison
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 3.99, 4.19
    Select inner viewport: 0, 8, 3.99, 4.19
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "C  Measured spectrum: source vs pure synthesized freeze"

    Select outer viewport: 0, 8, 4.21, 5.36
    Select inner viewport: 0.72, 7.72, 4.29, 5.20
    Axes: log_fmin, log_fmax, spec_lo, spec_hi
    Paint rectangle: "{0.975,0.975,0.978}", log_fmin, log_fmax, spec_lo, spec_hi
    have_prev = 0
    for q from 1 to n_spec_points
        frac = (q - 1) / (n_spec_points - 1)
        freq = spec_fmin * (spec_fmax / spec_fmin)^frac
        logf = log10(freq)
        selectObject: src_ltas
        b1 = Get bin number from frequency: 0.94 * freq
        b1 = round(b1)
        b2 = Get bin number from frequency: 0.97 * freq
        b2 = round(b2)
        b3 = Get bin number from frequency: freq
        b3 = round(b3)
        b4 = Get bin number from frequency: 1.03 * freq
        b4 = round(b4)
        b5 = Get bin number from frequency: 1.06 * freq
        b5 = round(b5)
        sv1 = Get value in bin: b1
        sv2 = Get value in bin: b2
        sv3 = Get value in bin: b3
        sv4 = Get value in bin: b4
        sv5 = Get value in bin: b5
        sdb = (sv1 + sv2 + sv3 + sv4 + sv5) / 5
        selectObject: wet_ltas
        b1 = Get bin number from frequency: 0.94 * freq
        b1 = round(b1)
        b2 = Get bin number from frequency: 0.97 * freq
        b2 = round(b2)
        b3 = Get bin number from frequency: freq
        b3 = round(b3)
        b4 = Get bin number from frequency: 1.03 * freq
        b4 = round(b4)
        b5 = Get bin number from frequency: 1.06 * freq
        b5 = round(b5)
        wv1 = Get value in bin: b1
        wv2 = Get value in bin: b2
        wv3 = Get value in bin: b3
        wv4 = Get value in bin: b4
        wv5 = Get value in bin: b5
        wdb = (wv1 + wv2 + wv3 + wv4 + wv5) / 5
        if have_prev
            Colour: "{0.56,0.56,0.58}"
            Line width: 1
            Draw line: prev_logf, prev_sdb, logf, sdb
            Colour: "{0.25,0.50,0.80}"
            Line width: 1.5
            Draw line: prev_logf, prev_wdb, logf, wdb
        endif
        prev_logf = logf
        prev_sdb = sdb
        prev_wdb = wdb
        have_prev = 1
    endfor
    Line width: 1

    # Measured dominant-frequency markers, derived from the same smoothed
    # curves rather than from the held-bank model.
    Dashed line
    Colour: "{0.56,0.56,0.58}"
    Draw line: log10(src_peak_freq), spec_lo, log10(src_peak_freq), spec_hi
    Colour: "{0.25,0.50,0.80}"
    Draw line: log10(wet_peak_freq), spec_lo, log10(wet_peak_freq), spec_hi
    Solid line

    Select inner viewport: 0.72, 7.72, 4.29, 5.20
    Axes: log_fmin, log_fmax, spec_lo, spec_hi
    Colour: "Black"
    Draw inner box
    Font size: 5
    @freezeVizStep: spec_hi - spec_lo, 5
    Marks left every: 1, freezeVizStep.step, "yes", "yes", "no"
    for fq from 1 to 8
        if fq = 1
            fm = 50
            fl$ = "50"
        elsif fq = 2
            fm = 100
            fl$ = "100"
        elsif fq = 3
            fm = 200
            fl$ = "200"
        elsif fq = 4
            fm = 500
            fl$ = "500"
        elsif fq = 5
            fm = 1000
            fl$ = "1k"
        elsif fq = 6
            fm = 2000
            fl$ = "2k"
        elsif fq = 7
            fm = 5000
            fl$ = "5k"
        else
            fm = 10000
            fl$ = "10k"
        endif
        if fm >= spec_fmin and fm <= spec_fmax
            One mark bottom: log10(fm), "no", "yes", "no", fl$
        endif
    endfor
    Font size: 6
    Text left: "yes", "dB/Hz"
    Font size: 5
    Colour: "{0.56,0.56,0.58}"
    Text: log_fmin + 0.02*(log_fmax-log_fmin), "left", spec_hi-0.08*(spec_hi-spec_lo), "half", "gray source"
    Colour: "{0.25,0.50,0.80}"
    Text: log_fmin + 0.25*(log_fmax-log_fmin), "left", spec_hi-0.08*(spec_hi-spec_lo), "half", "blue pure wet"

    Select outer viewport: 0, 8, 5.36, 5.56
    Select inner viewport: 0, 8, 5.36, 5.56
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    if wet_level > 0
        Text: 0.5, "centre", 0.5, "half", "same duration/axes | five-point LTAS smoothing | measured strongest: source " + fixed$(src_peak_freq,0) + " Hz -> wet " + fixed$(wet_peak_freq,0) + " Hz"
    else
        Text: 0.5, "centre", 0.5, "half", "bypass: wet is zero, so the comparison intentionally collapses to the source"
    endif

    # ------------------------------------------------------------------
    # D  Final measured output
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 5.82
    Select inner viewport: 0, 8, 5.62, 5.82
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "D  Measured final output (shared amplitude scale)"

    selectObject: resultL
    result_dur = Get total duration
    if result_chans > 1
        Select outer viewport: 0, 8, 5.84, 6.27
        Select inner viewport: 0.66, 7.72, 5.88, 6.23
        Colour: "{0.25,0.50,0.80}"
        Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
        Select inner viewport: 0.66, 7.72, 5.88, 6.23
        Axes: 0, result_dur, -vizPeak, vizPeak
        Colour: "Black"
        Draw inner box
        Font size: 5
        @freezeVizStep: vizPeak, 2
        Marks left every: 1, freezeVizStep.step, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "L"

        Select outer viewport: 0, 8, 6.27, 6.70
        Select inner viewport: 0.66, 7.72, 6.31, 6.66
        selectObject: resultR
        Colour: "{0.80,0.42,0.24}"
        Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
        Select inner viewport: 0.66, 7.72, 6.31, 6.66
        Axes: 0, result_dur, -vizPeak, vizPeak
        Colour: "Black"
        Draw inner box
        Font size: 5
        @freezeVizStep: vizPeak, 2
        Marks left every: 1, freezeVizStep.step, "yes", "yes", "no"
        @freezeVizStep: result_dur, 6
        Marks bottom every: 1, freezeVizStep.step, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "R"
        Text bottom: "yes", "time (s)"
    else
        Select outer viewport: 0, 8, 5.84, 6.70
        Select inner viewport: 0.66, 7.72, 5.91, 6.64
        selectObject: resultL
        Colour: "{0.25,0.50,0.80}"
        Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
        Select inner viewport: 0.66, 7.72, 5.91, 6.64
        Axes: 0, result_dur, -vizPeak, vizPeak
        Colour: "Black"
        Draw inner box
        Font size: 5
        @freezeVizStep: vizPeak, 2
        Marks left every: 1, freezeVizStep.step, "yes", "yes", "no"
        @freezeVizStep: result_dur, 6
        Marks bottom every: 1, freezeVizStep.step, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "mono"
        Text bottom: "yes", "time (s)"
    endif

    # ------------------------------------------------------------------
    # QC grid
    # ------------------------------------------------------------------
    Select outer viewport: 0, 8, 6.76, 7.42
    Select inner viewport: 0.15, 7.85, 6.79, 7.39
    Axes: 0, 3, 0, 2
    Paint rectangle: "{0.965,0.965,0.97}", 0, 3, 0, 2
    Colour: "{0.82,0.82,0.84}"
    Draw line: 1, 0, 1, 2
    Draw line: 2, 0, 2, 2
    Draw line: 0, 1, 3, 1
    Colour: "Black"
    Draw rectangle: 0, 3, 0, 2
    Font size: 5.3
    Text: 0.05, "left", 1.55, "half", "analysis: win " + fixed$(analysis_window_ms,1) + " ms | hop " + fixed$(frame_step_ms,1) + " ms | work SR " + fixed$(work_sr,0)
    Text: 1.05, "left", 1.55, "half", "hold: decay " + fixed$(decay_factor,3) + " | gliss " + fixed$(glissando_oct_sec,3) + " oct/s | updates " + string$(hold_updates)
    Text: 2.05, "left", 1.55, "half", "bank: mean active " + fixed$(mean_active,1) + "/" + string$(top_partials) + " | separation " + fixed$(peak_separation_hz,0) + " Hz"
    Text: 0.05, "left", 0.55, "half", "mix: wet " + fixed$(wet_dry_percent,0) + " percent | final SR " + fixed$(final_sr,0) + " Hz | tail " + fixed$(tail_duration_sec,2) + " s"
    if result_chans > 1
        Text: 1.05, "left", 0.55, "half", "stereo: delay " + fixed$(stereo_delay_ms,2) + " ms | peak L/R " + fixed$(outPeakL,3) + "/" + fixed$(outPeakR,3)
        Text: 2.05, "left", 0.55, "half", "RMS L/R " + fixed$(outRmsL,3) + "/" + fixed$(outRmsR,3) + " | out/in " + rms_ratio_text$
    else
        Text: 1.05, "left", 0.55, "half", "mono output | peak " + fixed$(outPeakL,3) + " | RMS " + fixed$(outRmsL,3)
        Text: 2.05, "left", 0.55, "half", "source ch " + string$(orig_vis_ch) + " peak " + fixed$(input_peak,3) + " | out/in " + rms_ratio_text$
    endif

    # Visualization-only cleanup.
    removeObject: orig_vis, wet_vis, src_spec, src_ltas, wet_spec, wet_ltas, resultL
    if resultR <> 0
        removeObject: resultR
    endif
    if wet_viz_id <> 0
        removeObject: wet_viz_id
    endif
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
appendInfoLine: "Output sample rate: ", final_sr, " Hz"
appendInfoLine: "Wet/dry: ", wet_dry_percent, "% wet"
appendInfoLine: "Complete!"

selectObject: result
if play_after
    Play
endif