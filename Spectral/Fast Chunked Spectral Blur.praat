# ============================================================
# Praat AudioTools - Fast Chunked Spectral Blur.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Spectral blur effect - smooths the frequency spectrum over time,
#   creating dreamy, smeared textures. Uses Spectrogram domain
#   processing with configurable window sizes for different timbres.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Spectral Blur Texture
    comment Select a Vibe:
    optionmenu Preset: 1
        option 1. Standard Blur (Clean)
        option 2. Ethereal Pad (Drone-like)
        option 3. Underwater (Muffled)
        option 4. Robotic / Metallic (Gritty)
        option 5. Rhythmic Glitch (Stutter)
    comment Advanced Overrides (ignored if using presets):
    boolean Override_settings 0
    positive Blur_radius 3.0
    positive Window_size_sec 0.025
    positive Chunk_size_sec 2.0
    comment === Output ===
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Preset names for display
presetName$[1] = "Standard Blur"
presetName$[2] = "Ethereal Pad"
presetName$[3] = "Underwater"
presetName$[4] = "Robotic/Metallic"
presetName$[5] = "Rhythmic Glitch"

# --- PRESET LOGIC ---
if override_settings = 0
    if preset = 1
        blur_radius = 3.0
        window_size = 0.025
        chunk_size = 2.0
    elsif preset = 2
        blur_radius = 10.0
        window_size = 0.08
        chunk_size = 5.0
    elsif preset = 3
        blur_radius = 20.0
        window_size = 0.03
        chunk_size = 3.0
    elsif preset = 4
        blur_radius = 2.0
        window_size = 0.008
        chunk_size = 1.0
    elsif preset = 5
        blur_radius = 5.0
        window_size = 0.02
        chunk_size = 0.25
    endif
else
    window_size = window_size_sec
    chunk_size = chunk_size_sec
endif

# --- INPUT VALIDATION ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound_id = selected("Sound")
sound_name$ = selected$("Sound")
selectObject: sound_id
fs = Get sampling frequency
total_duration = Get total duration
total_samples = Get number of samples
num_channels = Get number of channels

# Convert to mono if stereo
if num_channels > 1
    monoID = Convert to mono
    sound_id = monoID
endif

# Chunk parameters
chunk_samples = round(chunk_size * fs)
num_chunks = ceiling(total_samples / chunk_samples)

writeInfoLine: "=== Spectral Blur: ", presetName$[preset], " ==="
appendInfoLine: "Duration: ", fixed$(total_duration, 2), " s"
appendInfoLine: "Window: ", fixed$(window_size * 1000, 1), " ms"
appendInfoLine: "Blur radius: ", blur_radius
appendInfoLine: "Chunks: ", num_chunks, " x ", fixed$(chunk_size, 2), " s"
appendInfoLine: ""

chunk_ids# = zero#(num_chunks)

for i from 1 to num_chunks
    selectObject: sound_id
    
    start_sample = (i - 1) * chunk_samples + 1
    end_sample = min(start_sample + chunk_samples - 1, total_samples)
    
    start_time = (start_sample - 1) / fs
    end_time = (end_sample - 1) / fs
    
    if end_time > start_time
        chunk = Extract part: start_time, end_time, "rectangular", 1.0, "no"
        
        # To Spectrogram with dynamic window
        time_step = window_size / 8
        To Spectrogram: window_size, 5000, time_step, 20, "Gaussian"
        spec = selected("Spectrogram")
        
        # Blur: smooth across frequency bins
        if blur_radius >= 1
            loop_count = round(blur_radius)
            for k from 1 to loop_count
                Formula: "if row > 1 and row < nrow then (self[row-1,col] + 2*self + self[row+1,col])/4 else self fi"
            endfor
        endif
        
        # Back to Sound
        To Sound: fs
        processed_chunk = selected("Sound")
        chunk_ids#[i] = processed_chunk
        
        removeObject: chunk, spec
        
        if i mod 5 = 0
            appendInfoLine: "  Chunk ", i, "/", num_chunks
        endif
    endif
endfor

# Concatenate all chunks
selectObject: chunk_ids#[1]
for i from 2 to num_chunks
    if chunk_ids#[i] > 0
        plusObject: chunk_ids#[i]
    endif
endfor

Concatenate
result_id = selected("Sound")
Rename: sound_name$ + "_blur"
Scale peak: scale_peak

# Cleanup chunks
for i from 1 to num_chunks
    if chunk_ids#[i] > 0
        removeObject: chunk_ids#[i]
    endif
endfor

# Cleanup mono conversion if done
if num_channels > 1
    removeObject: monoID
endif

appendInfoLine: ""
appendInfoLine: "Complete!"

if play_after_processing
    selectObject: result_id
    Play
endif

selectObject: result_id

