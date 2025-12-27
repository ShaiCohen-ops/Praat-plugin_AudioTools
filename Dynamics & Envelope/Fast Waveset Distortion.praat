# ============================================================
# Praat AudioTools - Fast Waveset Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fast waveset-inspired audio distortion with stereo processing.
#   Processes L/R differently for wide stereo image.
#   Applies windowing to eliminate clicks.
#
# Usage:
#   Select a Sound object and run this script.
# ============================================================

form Fast Waveset Distortion
    optionmenu mode 1
        option 1. Stutter (repeat chunks)
        option 2. Gaps (silence chunks)
        option 3. Reverse chunks
        option 4. Shuffle order
        option 5. Time stretch
        option 6. Time compress
        option 7. Pumping (alt. volume)
        option 8. Ring modulator
        option 9. Bitcrush
        option 10. Tremolo
    real amount 3.0
    positive chunk_ms 40
    real fade_ms 5
    real stereo_spread 0.2
    real mix 1.0
    boolean normalize_output 1
    boolean draw_result 1
endform

# === VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Select a Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")
sr = Get sampling frequency
dur = Get total duration
n_channels = Get number of channels

# Ensure fade doesn't exceed half chunk
fade_ms = min(fade_ms, chunk_ms / 2 - 1)
fade_sec = fade_ms / 1000

writeInfoLine: "Fast Waveset Distortion v1.5 (Stereo + Windowed)"
appendInfoLine: "================================================"
appendInfoLine: "Input: ", name$, " | ", fixed$(dur, 2), "s"
appendInfoLine: "Mode: ", mode$
appendInfoLine: "Amount: ", amount, " | Chunk: ", chunk_ms, "ms | Fade: ", fade_ms, "ms"
appendInfoLine: "Stereo spread: ", stereo_spread
appendInfoLine: ""

# === CONVERT TO MONO FOR PROCESSING ===
selectObject: original
mono = Convert to mono
Rename: "mono_source"

# === PROCESS LEFT CHANNEL ===
appendInfoLine: "Processing LEFT channel..."
selectObject: mono
left_source = Copy: "left_source"

amount_L = amount
chunk_ms_L = chunk_ms
tag$ = "L"

@processAudio: left_source, mode, amount_L, chunk_ms_L, fade_sec, tag$
left_result = selected("Sound")

# === PROCESS RIGHT CHANNEL ===
appendInfoLine: ""
appendInfoLine: "Processing RIGHT channel..."
selectObject: mono
right_source = Copy: "right_source"

amount_R = amount * (1 + stereo_spread * 0.5)
chunk_ms_R = chunk_ms * (1 + stereo_spread)
tag$ = "R"

@processAudio: right_source, mode, amount_R, chunk_ms_R, fade_sec, tag$
right_result = selected("Sound")

# === MATCH DURATIONS ===
selectObject: left_result
dur_L = Get total duration
selectObject: right_result
dur_R = Get total duration

min_dur = min(dur_L, dur_R)

if dur_L > min_dur
    selectObject: left_result
    left_trimmed = Extract part: 0, min_dur, "rectangular", 1, "no"
    removeObject: left_result
    left_result = left_trimmed
endif

if dur_R > min_dur
    selectObject: right_result
    right_trimmed = Extract part: 0, min_dur, "rectangular", 1, "no"
    removeObject: right_result
    right_result = right_trimmed
endif

# === COMBINE TO STEREO ===
selectObject: left_result
plusObject: right_result
stereo_result = Combine to stereo
Rename: name$ + "_WSD"

removeObject: left_result, right_result, mono

# === MIX WITH ORIGINAL ===
if mix < 1
    selectObject: stereo_result
    result_dur = Get total duration
    
    selectObject: original
    if n_channels = 1
        orig_stereo = Convert to stereo
    else
        orig_stereo = Copy: "orig_stereo"
    endif
    
    orig_dur = Get total duration
    use_dur = min(result_dur, orig_dur)
    
    if orig_dur > use_dur
        orig_part = Extract part: 0, use_dur, "rectangular", 1, "no"
        removeObject: orig_stereo
        orig_stereo = orig_part
    endif
    
    selectObject: stereo_result
    Formula: "self * mix + Sound_orig_stereo(x, y) * (1 - mix)"
    
    removeObject: orig_stereo
endif

# === NORMALIZE ===
selectObject: stereo_result
if normalize_output
    Scale peak: 0.95
endif

output = stereo_result
final_dur = Get total duration

# === DRAW ===
if draw_result
    Erase all
    
    Select outer viewport: 0, 7, 0, 1.5
    selectObject: original
    Draw: 0, 0, 0, 0, "no", "Curve"
    Text top: "yes", "Original: " + name$
    
    Select outer viewport: 0, 7, 1.5, 3
    selectObject: output
    Extract one channel: 1
    left_draw = selected("Sound")
    Draw: 0, 0, 0, 0, "no", "Curve"
    Text top: "yes", "Left: amt=" + fixed$(amount_L, 1) + ", chunk=" + string$(round(chunk_ms_L)) + "ms"
    removeObject: left_draw
    
    Select outer viewport: 0, 7, 3, 4.5
    selectObject: output
    Extract one channel: 2
    right_draw = selected("Sound")
    Draw: 0, 0, 0, 0, "no", "Curve"
    Text top: "yes", "Right: amt=" + fixed$(amount_R, 1) + ", chunk=" + string$(round(chunk_ms_R)) + "ms"
    Text bottom: "yes", "Time (s)"
    removeObject: right_draw
    
    Select outer viewport: 0, 7, 0, 4.5
endif

selectObject: output

appendInfoLine: ""
appendInfoLine: "Original: ", fixed$(dur, 2), "s (", n_channels, " ch)"
appendInfoLine: "Output: ", fixed$(final_dur, 2), "s (stereo)"
appendInfoLine: ""
appendInfoLine: "Done! -> ", name$, "_WSD"

Play

# ============================================================
# APPLY HANN WINDOW FADES TO CHUNK
# ============================================================
procedure applyWindow: .snd, .fade_sec
    selectObject: .snd
    .chunk_dur = Get total duration
    
    if .fade_sec > 0 and .fade_sec < .chunk_dur / 2
        # Fade in: Hann window rise (0 to 1)
        Formula (part): 0, .fade_sec, 1, 1, "self * (0.5 - 0.5 * cos(pi * x / .fade_sec))"
        
        # Fade out: Hann window fall (1 to 0)
        .fade_start = .chunk_dur - .fade_sec
        Formula (part): .fade_start, .chunk_dur, 1, 1, "self * (0.5 + 0.5 * cos(pi * (x - .fade_start) / .fade_sec))"
    endif
endproc

# ============================================================
# MAIN PROCESSING PROCEDURE
# ============================================================
procedure processAudio: .source, .mode, .amount, .chunk_ms, .fade_sec, .tag$
    selectObject: .source
    .sr = Get sampling frequency
    .dur = Get total duration
    
    .chunk_sec = .chunk_ms / 1000
    .n_chunks = ceiling(.dur / .chunk_sec)
    
    # Extract chunks into GLOBAL array
    for c from 1 to .n_chunks
        .t1 = (c - 1) * .chunk_sec
        .t2 = min(c * .chunk_sec, .dur)
        
        if .t2 > .t1
            selectObject: .source
            chunk[c] = Extract part: .t1, .t2, "rectangular", 1, "no"
            Rename: "chunk_" + .tag$ + "_" + string$(c)
        else
            chunk[c] = 0
        endif
    endfor
    
    n_chunks = .n_chunks
    
    # Process by mode
    if .mode = 1
        # STUTTER
        .reps = max(2, min(8, round(.amount)))
        
        selectObject: chunk[1]
        @applyWindow: chunk[1], .fade_sec
        result = Copy: "result_" + .tag$
        
        for .r from 2 to .reps
            selectObject: chunk[1]
            .temp = Copy: "temp"
            .decay = 0.85 ^ (.r - 1)
            Formula: "self * .decay"
            @applyWindow: .temp, .fade_sec
            selectObject: result
            plusObject: .temp
            .new_result = Concatenate
            removeObject: result, .temp
            result = .new_result
        endfor
        
        for c from 2 to n_chunks
            if chunk[c] <> 0
                @applyWindow: chunk[c], .fade_sec
                for .r from 1 to .reps
                    selectObject: chunk[c]
                    .temp = Copy: "temp"
                    if .r > 1
                        .decay = 0.85 ^ (.r - 1)
                        Formula: "self * .decay"
                    endif
                    selectObject: result
                    plusObject: .temp
                    .new_result = Concatenate
                    removeObject: result, .temp
                    result = .new_result
                endfor
            endif
        endfor
        
    elsif .mode = 2
        # GAPS
        .skip_n = max(2, round(.amount))
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                if c mod .skip_n = 0
                    selectObject: chunk[c]
                    Formula: "0"
                else
                    @applyWindow: chunk[c], .fade_sec
                endif
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 3
        # REVERSE
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Reverse
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 4
        # SHUFFLE
        for c from 1 to n_chunks
            order[c] = c
        endfor
        for c from n_chunks to 2
            .j = randomInteger(1, c)
            .tmp = order[c]
            order[c] = order[.j]
            order[.j] = .tmp
        endfor
        
        # Apply windows to all chunks
        for c from 1 to n_chunks
            if chunk[c] <> 0
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        .first_idx = order[1]
        if chunk[.first_idx] <> 0
            selectObject: chunk[.first_idx]
            result = Copy: "result_" + .tag$
        endif
        
        for c from 2 to n_chunks
            .idx = order[c]
            if chunk[.idx] <> 0
                selectObject: result
                plusObject: chunk[.idx]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 5
        # STRETCH
        .factor = max(1.1, .amount / 2)
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                .chunk_sr = Get sampling frequency
                .new_sr = .chunk_sr / .factor
                if .new_sr >= 100
                    Resample: .new_sr, 50
                    .new_chunk = selected("Sound")
                    removeObject: chunk[c]
                    selectObject: .new_chunk
                    Override sampling frequency: .chunk_sr
                    chunk[c] = .new_chunk
                    Rename: "chunk_" + .tag$ + "_" + string$(c)
                endif
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 6
        # COMPRESS
        .factor = max(1.1, .amount / 2)
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                .chunk_sr = Get sampling frequency
                .new_sr = .chunk_sr * .factor
                if .new_sr <= 96000
                    Resample: .new_sr, 50
                    .new_chunk = selected("Sound")
                    removeObject: chunk[c]
                    selectObject: .new_chunk
                    Override sampling frequency: .chunk_sr
                    chunk[c] = .new_chunk
                    Rename: "chunk_" + .tag$ + "_" + string$(c)
                endif
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 7
        # PUMPING
        .gain_hi = 1 + (.amount - 1) * 0.5
        .gain_lo = 1 / .gain_hi
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                if c mod 2 = 1
                    Formula: "self * .gain_hi"
                else
                    Formula: "self * .gain_lo"
                endif
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 8
        # RING MOD
        .ring_freq = 50 + .amount * 80
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "self * sin(2 * pi * .ring_freq * x)"
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 9
        # BITCRUSH
        .levels = max(2, round(16 / .amount))
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "round(self * .levels) / .levels"
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 10
        # TREMOLO
        .trem_freq = 2 + .amount * 3
        .trem_depth = min(0.9, .amount * 0.15)
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "self * (1 - .trem_depth * (0.5 + 0.5 * sin(2 * pi * .trem_freq * x)))"
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
    endif
    
    # Cleanup chunks
    for c from 1 to n_chunks
        if chunk[c] <> 0
            removeObject: chunk[c]
        endif
    endfor
    
    removeObject: .source
    
    selectObject: result
endproc