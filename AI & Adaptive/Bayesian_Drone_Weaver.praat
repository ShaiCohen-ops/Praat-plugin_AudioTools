# ============================================================
# Praat AudioTools - Bayesian_Drone_Weaver.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026) - Fixed assembly Formula
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bayesian Drone Weaver - Generative composition system that
#   analyzes audio clips, classifies them using Bayesian inference,
#   and assembles them into evolving drone textures.
#
# Usage:
#   Run this script and select a folder containing audio clips.
#
# Changelog v0.3 (2026):
#   - FIX: assembleDrone's mix Formula used "Object_<id>[...]" which
#     resolves by name, not numeric ID, and would fail at runtime.
#     Replaced with the correct "object[<id>, col - offset]" idiom.
#   - FIX: The same Formula had an off-by-one: when start_sample = 0,
#     it read part sample 2 at buffer col 1. Corrected so part col 1
#     aligns with buffer col (offset + 1).
#   - FIX: Terminator "endif" inside Formula string replaced with
#     "fi" which is the correct token in Praat's Formula language.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Bayesian Drone Weaver v0.3
    comment === Composition Style ===
    optionmenu Preset: 1
        option Custom
        option Ambient (slow evolution)
        option Cinematic (dramatic arc)
        option Meditative (sustained)
        option Textural (varied)
    comment === Parameters ===
    positive Max_clips 30
    positive Overlap_factor 1.0
    boolean Draw_visualization 1
endform

# Apply presets
if preset = 2
    # Ambient
    max_clips = 20
    overlap_factor = 1.2
    presetName$ = "Ambient"
elsif preset = 3
    # Cinematic
    max_clips = 30
    overlap_factor = 0.8
    presetName$ = "Cinematic"
elsif preset = 4
    # Meditative
    max_clips = 15
    overlap_factor = 1.5
    presetName$ = "Meditative"
elsif preset = 5
    # Textural
    max_clips = 40
    overlap_factor = 0.6
    presetName$ = "Textural"
else
    presetName$ = "Custom"
endif

# --- USER INTERACTION ---
folder$ = chooseDirectory$: "Select folder with audio clips"
if folder$ = ""
    exitScript: "No folder selected."
endif

# --- CONSTANTS ---
target_sr = 44100
min_clips = 3

intensity_floor = 40
intensity_time_step = 0.05 
pitch_floor = 75
pitch_ceiling = 600
harmonicity_time_step = 0.05

# Bayesian hypothesis indices
h_sustain = 1
h_swell = 2
h_tension = 3
h_air = 4
h_pulse = 5
n_hypotheses = 5

clearinfo
writeInfoLine: "=== Bayesian Drone Weaver v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

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

appendInfoLine: "Found ", total_files, " audio files"

if total_files < min_clips
    removeObject: file_list, file_list2, file_list3
    exitScript: "Error: Need at least " + string$(min_clips) + " files."
endif

# --- PROCESS CLIPS ---
n_valid = 0

appendInfoLine: "Loading and analyzing clips..."

# Process WAV
for i to n_files
    if n_valid < max_clips
        selectObject: file_list
        filename$ = Get string: i
        soundID = Read from file: folder$ + filename$
        @processClip: soundID, n_valid
        if processClip.success
            n_valid += 1
            appendInfo: "."
        endif
    endif
endfor

# Process AIFF
for i to n_files2
    if n_valid < max_clips
        selectObject: file_list2
        filename$ = Get string: i
        soundID = Read from file: folder$ + filename$
        @processClip: soundID, n_valid
        if processClip.success
            n_valid += 1
            appendInfo: "."
        endif
    endif
endfor

# Process FLAC
for i to n_files3
    if n_valid < max_clips
        selectObject: file_list3
        filename$ = Get string: i
        soundID = Read from file: folder$ + filename$
        @processClip: soundID, n_valid
        if processClip.success
            n_valid += 1
            appendInfo: "."
        endif
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Loaded ", n_valid, " valid clips"

# Cleanup File Lists
removeObject: file_list, file_list2, file_list3

if n_valid < min_clips
    for i to n_valid
        removeObject: clip_sound_'i'
    endfor
    exitScript: "Error: Not enough valid clips loaded."
endif

# --- ANALYSIS & COMPOSITION ---
appendInfoLine: "Classifying gestures..."
for i to n_valid
    @classifyGesture: i
    @computeMacros: i
endfor

appendInfoLine: "Building timeline..."
@buildTimeline: n_valid

appendInfoLine: "Assembling drone..."
@assembleDrone

# --- FINALIZE ---
selectObject: final_sound
Scale peak: 0.95
Rename: "BayesianDrone_" + presetName$

# --- VISUALIZATION ---
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawVisualization: n_valid
endif

# --- CLEANUP SOURCE CLIPS ---
for i to n_valid
    removeObject: clip_sound_'i'
endfor

selectObject: final_sound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: BayesianDrone_", presetName$
appendInfoLine: "Duration: ", fixed$(timeline_total_duration, 2), " s"
appendInfoLine: "Segments: ", timeline_n_segments

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
    if .sr <> target_sr
        .resampled = Resample: target_sr, 50
        removeObject: .sound
        .sound = .resampled
    endif
    
    selectObject: .sound
    .duration = Get total duration
    
    # Validate duration
    if .duration < 0.1 or .duration > 30
        removeObject: .sound
        .success = 0
    else
        .idx = .index + 1
        clip_sound_'.idx' = .sound
        clip_duration_'.idx' = .duration
        
        # --- FEATURE EXTRACTION ---
        
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
        
        # Pitch / Voicing
        selectObject: .sound
        .pitch = To Pitch: 0.02, pitch_floor, pitch_ceiling
        .n_frames = Get number of frames
        .voiced_count = Count voiced frames
        
        if .n_frames > 0
            .voiced_fraction = .voiced_count / .n_frames
        else
            .voiced_fraction = 0
        endif
        removeObject: .pitch
        
        clip_intensity_'.idx' = .mean_intensity
        clip_intensity_std_'.idx' = .std_intensity
        clip_intensity_motion_'.idx' = .intensity_motion
        clip_brightness_'.idx' = .brightness
        clip_harmonicity_'.idx' = .harmonicity_mean
        clip_voiced_'.idx' = .voiced_fraction
        
        .success = 1
    endif
endproc

procedure classifyGesture: .idx
    .intensity = clip_intensity_'.idx'
    .std_int = clip_intensity_std_'.idx'
    .motion = clip_intensity_motion_'.idx'
    .bright = clip_brightness_'.idx'
    .harm = clip_harmonicity_'.idx'
    .voiced = clip_voiced_'.idx'
    .bright_khz = .bright / 1000
    
    # Log-likelihood calculations
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
    
    # Compute posteriors
    .prior = ln(0.2)
    .post_1 = .ll_sustain + .prior
    .post_2 = .ll_swell + .prior
    .post_3 = .ll_tension + .prior
    .post_4 = .ll_air + .prior
    .post_5 = .ll_pulse + .prior
    
    # Find max for numerical stability
    .max_post = .post_1
    if .post_2 > .max_post
        .max_post = .post_2
    endif
    if .post_3 > .max_post
        .max_post = .post_3
    endif
    if .post_4 > .max_post
        .max_post = .post_4
    endif
    if .post_5 > .max_post
        .max_post = .post_5
    endif
    
    # Normalize
    .post_1 = exp(.post_1 - .max_post)
    .post_2 = exp(.post_2 - .max_post)
    .post_3 = exp(.post_3 - .max_post)
    .post_4 = exp(.post_4 - .max_post)
    .post_5 = exp(.post_5 - .max_post)
    
    .sum = .post_1 + .post_2 + .post_3 + .post_4 + .post_5
    
    clip_post_'.idx'_1 = .post_1 / .sum
    clip_post_'.idx'_2 = .post_2 / .sum
    clip_post_'.idx'_3 = .post_3 / .sum
    clip_post_'.idx'_4 = .post_4 / .sum
    clip_post_'.idx'_5 = .post_5 / .sum
    
    # Store dominant class
    .max_p = clip_post_'.idx'_1
    clip_class_'.idx' = 1
    if clip_post_'.idx'_2 > .max_p
        .max_p = clip_post_'.idx'_2
        clip_class_'.idx' = 2
    endif
    if clip_post_'.idx'_3 > .max_p
        .max_p = clip_post_'.idx'_3
        clip_class_'.idx' = 3
    endif
    if clip_post_'.idx'_4 > .max_p
        .max_p = clip_post_'.idx'_4
        clip_class_'.idx' = 4
    endif
    if clip_post_'.idx'_5 > .max_p
        clip_class_'.idx' = 5
    endif
endproc

procedure computeMacros: .idx
    .p_sustain = clip_post_'.idx'_1
    .p_swell = clip_post_'.idx'_2
    .p_tension = clip_post_'.idx'_3
    .p_air = clip_post_'.idx'_4
    .p_pulse = clip_post_'.idx'_5
    
    clip_flow_'.idx' = 0.5 + 0.3 * .p_sustain + 0.4 * .p_air + 0.2 * .p_swell
    if clip_flow_'.idx' > 1
        clip_flow_'.idx' = 1
    endif
    
    clip_growth_'.idx' = 0.3 + 0.6 * .p_swell + 0.1 * .p_tension
    
    clip_edge_'.idx' = 0.2 + 0.6 * .p_tension + 0.2 * .p_swell
    if clip_edge_'.idx' > 0.85
        clip_edge_'.idx' = 0.85
    endif
    
    clip_space_'.idx' = 0.4 + 0.4 * .p_air + 0.3 * .p_sustain + 0.1 * .p_swell
    if clip_space_'.idx' > 1
        clip_space_'.idx' = 1
    endif
    
    clip_soften_'.idx' = .p_pulse
endproc

procedure buildTimeline: .n_clips
    timeline_n_segments = .n_clips
    if timeline_n_segments > 30
        timeline_n_segments = 30
    endif
    
    for .i to .n_clips
        clip_used_'.i' = 0
    endfor
    
    for .seg to timeline_n_segments
        .phase = (.seg - 1) / (timeline_n_segments - 1)
        
        # Phase-based targets (intro→development→climax→resolution)
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
        
        .best_idx = 1
        .best_score = -1000
        
        for .i to .n_clips
            if clip_used_'.i' = 0
                .flow = clip_flow_'.i'
                .growth = clip_growth_'.i'
                .edge = clip_edge_'.i'
                .space = clip_space_'.i'
                
                .dist = 0
                .dist += (.flow - .target_flow)^2
                .dist += (.growth - .target_growth)^2
                .dist += (.edge - .target_edge)^2
                .dist += (.space - .target_space)^2
                .score = -sqrt(.dist)
                
                # Continuity bonus
                if .seg > 1
                    .prev_idx = timeline_clip_'.seg_minus_1'
                    .prev_flow = clip_flow_'.prev_idx'
                    .prev_edge = clip_edge_'.prev_idx'
                    .cont = abs(.flow - .prev_flow) + abs(.edge - .prev_edge)
                    .score += -(0.3 * .cont)
                endif
                
                if .score > .best_score
                    .best_score = .score
                    .best_idx = .i
                endif
            endif
        endfor
        
        timeline_clip_'.seg' = .best_idx
        clip_used_'.best_idx' = 1
        
        # Store for next iteration
        .seg_minus_1 = .seg
    endfor
    
    # Calculate start times
    .first_clip = timeline_clip_1
    timeline_start_1 = 0
    .total_dur = clip_duration_'.first_clip'
    
    for .seg from 2 to timeline_n_segments
        .seg_prev = .seg - 1
        .prev_idx = timeline_clip_'.seg_prev'
        .curr_idx = timeline_clip_'.seg'
        
        .flow_prev = clip_flow_'.prev_idx'
        .flow_curr = clip_flow_'.curr_idx'
        .space_prev = clip_space_'.prev_idx'
        .space_curr = clip_space_'.curr_idx'
        
        .flow_avg = (.flow_prev + .flow_curr) / 2
        .space_avg = (.space_prev + .space_curr) / 2
        
        if .seg / timeline_n_segments > 0.8
            .overlap = 0.6 + .flow_avg * 1.2 + .space_avg * 0.5
        else
            .overlap = 0.4 + .flow_avg * 0.8 + .space_avg * 0.3
        endif
        
        .overlap = .overlap * overlap_factor
        
        if .overlap > 2
            .overlap = 2
        endif
        
        .prev_start = timeline_start_'.seg_prev'
        .prev_dur = clip_duration_'.prev_idx'
        timeline_start_'.seg' = .prev_start + .prev_dur - .overlap
        
        .curr_dur = clip_duration_'.curr_idx'
        .end_time = timeline_start_'.seg' + .curr_dur
        if .end_time > .total_dur
            .total_dur = .end_time
        endif
    endfor
    
    timeline_total_duration = .total_dur
endproc

procedure assembleDrone
    final_sound = Create Sound from formula: "base", 1, 0, timeline_total_duration, target_sr, "0"
    
    for .seg to timeline_n_segments
        .clip_idx = timeline_clip_'.seg'
        .start_time = timeline_start_'.seg'
        .duration = clip_duration_'.clip_idx'
        
        selectObject: clip_sound_'.clip_idx'
        .part = Copy: "part"
        
        .flow = clip_flow_'.clip_idx'
        .space = clip_space_'.clip_idx'
        .soften = clip_soften_'.clip_idx'
        
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
        
        # Mix into final sound.
        # v0.3 FIX: v0.2 used "Object_<id>[expr]" which resolves by
        # NAME (not numeric ID) and was off-by-one. Correct idiom is
        # object[<id>, <col_expr>] with col_expr = col - offset where
        # offset = round(start_time * sr). Terminator inside a Formula
        # string is `fi`, not `endif`.
        .off = round(.start_time * target_sr)
        selectObject: .part
        .partNSamples = Get number of samples

        .firstCol = .off + 1
        .lastCol  = .off + .partNSamples
        .partIdStr$ = fixed$(.part, 0)
        .offStr$ = fixed$(.off, 0)
        .firstStr$ = fixed$(.firstCol, 0)
        .lastStr$ = fixed$(.lastCol, 0)

        selectObject: final_sound
        Formula: "self + if col >= " + .firstStr$
            ... + " and col <= " + .lastStr$
            ... + " then object[" + .partIdStr$ + ", col - " + .offStr$ + "]"
            ... + " else 0 fi"

        removeObject: .part
    endfor
endproc

procedure drawVisualization: .n_clips
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Bayesian Drone Weaver: " + presetName$
    
    # Timeline visualization
    Select outer viewport: 0, 8, 0.8, 3.5
    Select inner viewport: 0.6, 7.6, 1.0, 3.3
    
    Axes: 0, timeline_total_duration, 0, timeline_n_segments + 1
    
    # Background
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, timeline_total_duration, 0, timeline_n_segments + 1
    
    # Draw segments
    for .seg to timeline_n_segments
        .clip_idx = timeline_clip_'.seg'
        .start = timeline_start_'.seg'
        .dur = clip_duration_'.clip_idx'
        .end = .start + .dur
        
        .class = clip_class_'.clip_idx'
        
        # Color by class
        if .class = 1
            .col$ = "{0.3, 0.6, 0.9}"
        elsif .class = 2
            .col$ = "{0.4, 0.8, 0.4}"
        elsif .class = 3
            .col$ = "{0.9, 0.4, 0.3}"
        elsif .class = 4
            .col$ = "{0.7, 0.7, 0.9}"
        else
            .col$ = "{0.9, 0.7, 0.3}"
        endif
        
        .y1 = .seg - 0.4
        .y2 = .seg + 0.4
        
        Paint rectangle: .col$, .start, .end, .y1, .y2
        
        # Label
        Colour: "Black"
        Font size: 7
        Text: (.start + .end) / 2, "centre", .seg, "half", string$(.clip_idx)
    endfor
    
    Colour: "Black"
    Font size: 10
    Draw inner box
    Text left: "yes", "Segment"
    Text bottom: "yes", "Time (s)"
    Marks bottom every: 1, 5, "yes", "yes", "no"
    
    # Legend
    Select outer viewport: 0, 8, 3.7, 4.3
    Axes: 0, 1, 0, 1
    Font size: 8
    
    Paint rectangle: "{0.3, 0.6, 0.9}", 0.02, 0.06, 0.4, 0.6
    Text: 0.08, "left", 0.5, "half", "Sustain"
    
    Paint rectangle: "{0.4, 0.8, 0.4}", 0.22, 0.26, 0.4, 0.6
    Text: 0.28, "left", 0.5, "half", "Swell"
    
    Paint rectangle: "{0.9, 0.4, 0.3}", 0.42, 0.46, 0.4, 0.6
    Text: 0.48, "left", 0.5, "half", "Tension"
    
    Paint rectangle: "{0.7, 0.7, 0.9}", 0.62, 0.66, 0.4, 0.6
    Text: 0.68, "left", 0.5, "half", "Air"
    
    Paint rectangle: "{0.9, 0.7, 0.3}", 0.82, 0.86, 0.4, 0.6
    Text: 0.88, "left", 0.5, "half", "Pulse"
    
    Font size: 10
endproc
Play