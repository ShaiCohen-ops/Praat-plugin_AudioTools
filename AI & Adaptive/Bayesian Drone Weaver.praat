# ============================================================
# Praat AudioTools - Bayesian Drone Weaver
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generative Music Expert System
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# --- USER INTERACTION ---
folder$ = chooseDirectory$: "Select folder with audio clips"
if folder$ = ""
    exitScript: "No folder selected."
endif

# --- CONSTANTS ---
target_sr = 44100
min_clips = 3
max_clips = 50

# OPTIMIZATION: Increased time steps (lower resolution) for speed
# Drones do not need 10ms precision; 50ms is sufficient.
intensity_floor = 40
intensity_time_step = 0.05 
pitch_floor = 75
pitch_ceiling = 600
harmonicity_time_step = 0.05

# Bayesian constants
h_sustain = 1
h_swell = 2
h_tension = 3
h_air = 4
h_pulse = 5
n_hypotheses = 5

# --- SCAN FOLDER ---
if right$(folder$, 1) <> "/" and right$(folder$, 1) <> "\"
    folder$ = folder$ + "/"
endif

file_list = Create Strings as file list: "fileList", folder$ + "*.wav"
n_files = Get number of strings
file_list2 = Create Strings as file list: "fileList2", folder$ + "*.aiff"
n_files2 = Get number of strings
file_list3 = Create Strings as file list: "fileList3", folder$ + "*.flac"
n_files3 = Get number of strings

total_files = n_files + n_files2 + n_files3

if total_files < min_clips
    removeObject: file_list, file_list2, file_list3
    exitScript: "Error: Need at least " + string$(min_clips) + " files."
endif

# --- PROCESS CLIPS ---
n_valid = 0

# Process WAV
for i to n_files
    selectObject: file_list
    filename$ = Get string: i
    soundID = Read from file: folder$ + filename$
    @processClip: soundID, n_valid
    if processClip.success
        n_valid += 1
    endif
    if n_valid >= max_clips
        i = n_files
    endif
endfor

# Process AIFF
for i to n_files2
    selectObject: file_list2
    filename$ = Get string: i
    soundID = Read from file: folder$ + filename$
    @processClip: soundID, n_valid
    if processClip.success
        n_valid += 1
    endif
    if n_valid >= max_clips
        i = n_files2
    endif
endfor

# Process FLAC
for i to n_files3
    selectObject: file_list3
    filename$ = Get string: i
    soundID = Read from file: folder$ + filename$
    @processClip: soundID, n_valid
    if processClip.success
        n_valid += 1
    endif
    if n_valid >= max_clips
        i = n_files3
    endif
endfor

# Cleanup File Lists
removeObject: file_list, file_list2, file_list3

if n_valid < min_clips
    # Cleanup any loaded sounds if we fail
    for i to n_valid
        removeObject: clip_sound[i]
    endfor
    exitScript: "Error: Not enough valid clips loaded."
endif

# --- ANALYSIS & COMPOSITION ---
for i to n_valid
    @classifyGesture: i
    @computeMacros: i
endfor

@buildTimeline: n_valid
@assembleDrone

# --- FINALIZE ---
selectObject: final_sound
Scale peak: 0.95
Rename: "ComposedDrone"

# --- CLEANUP SOURCE CLIPS ---
for i to n_valid
    selectObject: clip_sound[i]
    Remove
endfor

selectObject: final_sound

# ============================================================================
# PROCEDURES
# ============================================================================

procedure processClip: .soundID, .index
    .success = 0
    .sound = .soundID
    
    selectObject: .sound
    .nchannels = Get number of channels
    if .nchannels > 1
        .mono = Convert to mono
        removeObject: .sound
        .sound = .mono
    endif
    
    selectObject: .sound
    .sr = Get sampling frequency
    if .sr != target_sr
        .resampled = Resample: target_sr, 50
        removeObject: .sound
        .sound = .resampled
    endif
    
    selectObject: .sound
    .duration = Get total duration
    if .duration < 0.1 or .duration > 30
        removeObject: .sound
        .success = 0
        goto DONE_CLIP
    endif
    
    .idx = .index + 1
    clip_sound[.idx] = .sound
    clip_duration[.idx] = .duration
    
    # --- OPTIMIZED FEATURE EXTRACTION ---
    
    # Intensity
    selectObject: .sound
    .intensity = To Intensity: intensity_floor, intensity_time_step, "yes"
    .mean_intensity = Get mean: 0, 0, "energy"
    .std_intensity = Get standard deviation: 0, 0
    
    .dur_quarter = .duration / 4
    .mean_early = Get mean: 0, .dur_quarter, "energy"
    .mean_late = Get mean: .duration - .dur_quarter, .duration, "energy"
    .intensity_motion = (.mean_late - .mean_early) / .duration
    removeObject: .intensity
    
    # Spectrum
    selectObject: .sound
    .spectrum = To Spectrum: "yes"
    .brightness = Get centre of gravity: 2
    removeObject: .spectrum
    
    # Harmonicity
    selectObject: .sound
    .harmonicity = To Harmonicity (cc): harmonicity_time_step, pitch_floor, 0.1, 1.0
    .harmonicity_mean = Get mean: 0, 0
    removeObject: .harmonicity
    
    # Pitch / Voicing (OPTIMIZED: Replaced Loop with Native Command)
    selectObject: .sound
    # Using larger time step (0.02) for speed
    .pitch = To Pitch: 0.02, pitch_floor, pitch_ceiling
    .n_frames = Get number of frames
    
    # SPEED FIX: Use built-in command instead of looping 1000 times
    .voiced_count = Count voiced frames
    
    if .n_frames > 0
        .voiced_fraction = .voiced_count / .n_frames
    else
        .voiced_fraction = 0
    endif
    removeObject: .pitch
    
    clip_intensity[.idx] = .mean_intensity
    clip_intensity_std[.idx] = .std_intensity
    clip_intensity_motion[.idx] = .intensity_motion
    clip_brightness[.idx] = .brightness
    clip_harmonicity[.idx] = .harmonicity_mean
    clip_voiced[.idx] = .voiced_fraction
    
    .success = 1
    label DONE_CLIP
endproc

procedure classifyGesture: .idx
    .intensity = clip_intensity[.idx]
    .std_int = clip_intensity_std[.idx]
    .motion = clip_intensity_motion[.idx]
    .bright = clip_brightness[.idx]
    .harm = clip_harmonicity[.idx]
    .voiced = clip_voiced[.idx]
    .bright_khz = .bright / 1000
    
    # Simplified Logic for speed
    .ll_sustain = -(.std_int - 2)^2 / 10 - .motion^2 / 0.1 - (.bright_khz - 1.5)^2 / 3 + .harm / 5 + .voiced
    
    .ll_swell = 0
    if .motion > 0
        .ll_swell += .motion * 10
    else
        .ll_swell += .motion * 3
    endif
    .ll_swell += -(.bright_khz - 2)^2 / 4 + .std_int / 5 + .harm / 10
    
    .ll_tension = (.bright_khz - 1) * 2 - .harm + .intensity / 10 + .std_int / 3
    .ll_air = -((.intensity - 50)^2) / 200 + (.bright_khz - 3) / 2 - .harm * 2 - .voiced
    
    .ll_pulse = .std_int - .harm / 2
    if .motion < -2
        .ll_pulse += 2
    endif
    
    .prior = ln(0.2)
    .post[h_sustain] = .ll_sustain + .prior
    .post[h_swell] = .ll_swell + .prior
    .post[h_tension] = .ll_tension + .prior
    .post[h_air] = .ll_air + .prior
    .post[h_pulse] = .ll_pulse + .prior
    
    .max_post = .post[1]
    for .h to n_hypotheses
        if .post[.h] > .max_post
            .max_post = .post[.h]
        endif
    endfor
    
    .sum = 0
    for .h to n_hypotheses
        .post[.h] = exp(.post[.h] - .max_post)
        .sum += .post[.h]
    endfor
    
    for .h to n_hypotheses
        .post[.h] /= .sum
        clip_posterior[.idx, .h] = .post[.h]
    endfor
endproc

procedure computeMacros: .idx
    .p_sustain = clip_posterior[.idx, h_sustain]
    .p_swell = clip_posterior[.idx, h_swell]
    .p_tension = clip_posterior[.idx, h_tension]
    .p_air = clip_posterior[.idx, h_air]
    .p_pulse = clip_posterior[.idx, h_pulse]
    
    clip_flow[.idx] = 0.5 + 0.3 * .p_sustain + 0.4 * .p_air + 0.2 * .p_swell
    if clip_flow[.idx] > 1
        clip_flow[.idx] = 1
    endif
    
    clip_growth[.idx] = 0.3 + 0.6 * .p_swell + 0.1 * .p_tension
    
    clip_edge[.idx] = 0.2 + 0.6 * .p_tension + 0.2 * .p_swell
    if clip_edge[.idx] > 0.85
        clip_edge[.idx] = 0.85
    endif
    
    clip_space[.idx] = 0.4 + 0.4 * .p_air + 0.3 * .p_sustain + 0.1 * .p_swell
    if clip_space[.idx] > 1
        clip_space[.idx] = 1
    endif
    
    clip_soften[.idx] = .p_pulse
endproc

procedure buildTimeline: .n_clips
    timeline.n_segments = .n_clips
    if timeline.n_segments > 30
        timeline.n_segments = 30
    endif
    
    for .i to .n_clips
        clip_used[.i] = 0
    endfor
    
    for .seg to timeline.n_segments
        .phase = (.seg - 1) / (timeline.n_segments - 1)
        
        if .phase < 0.25
            .target_flow = 0.85
            .target_growth = 0.2
            .target_edge = 0.15
            .target_space = 0.8
        elsif .phase < 0.60
            .target_flow = 0.75
            .target_growth = 0.7
            .target_edge = 0.4
            .target_space = 0.5
        elsif .phase < 0.80
            .target_flow = 0.5
            .target_growth = 0.4
            .target_edge = 0.75
            .target_space = 0.3
        else
            .target_flow = 0.95
            .target_growth = 0.1
            .target_edge = 0.2
            .target_space = 0.9
        endif
        
        .best_idx = 0
        .best_score = -1000
        
        for .i to .n_clips
            if clip_used[.i] = 0
                .dist = 0
                .dist += (clip_flow[.i] - .target_flow)^2
                .dist += (clip_growth[.i] - .target_growth)^2
                .dist += (clip_edge[.i] - .target_edge)^2
                .dist += (clip_space[.i] - .target_space)^2
                .score = -sqrt(.dist)
                
                if .seg > 1
                    .prev_idx = timeline.clip[.seg - 1]
                    .cont = abs(clip_flow[.i] - clip_flow[.prev_idx]) + abs(clip_edge[.i] - clip_edge[.prev_idx])
                    .score += -(0.3 * .cont)
                endif
                
                if .score > .best_score
                    .best_score = .score
                    .best_idx = .i
                endif
            endif
        endfor
        
        timeline.clip[.seg] = .best_idx
        clip_used[.best_idx] = 1
    endfor
    
    timeline.start[1] = 0
    .total_dur = clip_duration[timeline.clip[1]]
    
    for .seg from 2 to timeline.n_segments
        .prev_idx = timeline.clip[.seg - 1]
        .curr_idx = timeline.clip[.seg]
        
        .flow_avg = (clip_flow[.prev_idx] + clip_flow[.curr_idx]) / 2
        .space_avg = (clip_space[.prev_idx] + clip_space[.curr_idx]) / 2
        
        if .seg / timeline.n_segments > 0.8
            .overlap = 0.6 + .flow_avg * 1.2 + .space_avg * 0.5
        else
            .overlap = 0.4 + .flow_avg * 0.8 + .space_avg * 0.3
        endif
        
        if .overlap > 2
            .overlap = 2
        endif
        
        .prev_start = timeline.start[.seg - 1]
        .prev_dur = clip_duration[.prev_idx]
        timeline.start[.seg] = .prev_start + .prev_dur - .overlap
        
        .curr_dur = clip_duration[.curr_idx]
        .end_time = timeline.start[.seg] + .curr_dur
        if .end_time > .total_dur
            .total_dur = .end_time
        endif
    endfor
    
    timeline.total_duration = .total_dur
endproc

procedure assembleDrone
    final_sound = Create Sound from formula: "base", 1, 0, timeline.total_duration, target_sr, "0"
    
    for .seg to timeline.n_segments
        .clip_idx = timeline.clip[.seg]
        .start_time = timeline.start[.seg]
        .duration = clip_duration[.clip_idx]
        
        selectObject: clip_sound[.clip_idx]
        .part = Copy: "part"
        
        .flow = clip_flow[.clip_idx]
        .space = clip_space[.clip_idx]
        .soften = clip_soften[.clip_idx]
        
        .fade_in = 0.05 + .flow * 0.4 + .soften * 0.5
        .fade_out = 0.1 + .flow * 0.5 + .space * 0.4 + .soften * 0.6
        
        if .fade_in > .duration / 2
            .fade_in = .duration / 2
        endif
        if .fade_out > .duration / 2
            .fade_out = .duration / 2
        endif
        
        selectObject: .part
        Fade in: 0, 0, .fade_in, "yes"
        Fade out: 0, .duration, -.fade_out, "yes"
        
        if .soften > 0.5
            .scale = 1 - (.soften - 0.5)
            Scale intensity: .scale * 70
        endif
        
        .start_sample = round(.start_time * target_sr)
        .end_sample = round((.start_time + .duration) * target_sr)
        
        selectObject: final_sound
        Formula: "self + if col >= " + string$(.start_sample) + " and col <= " + string$(.end_sample) + " then object[.part, col - " + string$(.start_sample) + "] else 0 endif"
        
        removeObject: .part
    endfor
endproc
Play