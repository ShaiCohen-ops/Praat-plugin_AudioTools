# ============================================================
# Praat AudioTools - Audiovisual_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Mapping Sound to Sight — Algorithmic Audiovisual Renderer.
#   Generates a stereo master signal and renders synchronized
#   real-time visuals in Praat's demo window via a 3-phase pipeline:
#   (1) synthesize stereo audio, (2) pre-compute signal analysis
#   and pre-slice audio chunks, (3) frame-locked draw + play loop.
#
#   Presets:
#     1. TRUE ANALYSIS: RMS -> Size        (amplitude-driven circle)
#     2. TRUE ANALYSIS: Pitch -> Y-Pos     (pitch-tracker dot)
#     3. Tone -> Sharpness                 (The Morphing Star)
#     4. Voices -> Swarm                   (The Particle System)
#     5. Phase -> Rotation                 (The Hypnotic Spiral)
#     6. FM Index -> Geometry              (The Trochoid Spirograph)
#     7. Stereo Waveform -> Path           (Lissajous + Phosphor Trails)
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: Audiovisual Sonification.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

beginPause: "AV Parameter Mapping — Select Preset"
    comment: "Choose an Audiovisual Concept to explore:"
    optionmenu: "Preset", 1
        option: "1. TRUE ANALYSIS: RMS -> Size"
        option: "2. TRUE ANALYSIS: Pitch -> Y-Position"
        option: "3. Tone -> Sharpness (The Morphing Star)"
        option: "4. Voices -> Swarm (The Particle System)"
        option: "5. Phase -> Rotation (The Hypnotic Spiral)"
        option: "6. FM Index -> Geometry (The Trochoid Spirograph)"
        option: "7. Stereo Waveform -> Path (Lissajous)"
    real: "Total duration", 3
    real: "Master volume", 0.9
    boolean: "Randomize seed", 1
endPause: "Run", 1

totalDur = total_duration
frame_step = 0.08   ; ~12fps — good balance of smoothness vs speed
sr = 44100
total_frames = floor(totalDur / frame_step)

# Seed randomization for organic variations
time_offset = 0
if randomize_seed
    time_offset = randomUniform(0, 100)
endif

if preset = 1
    title$ = "RMS Amplitude -> Radius"
elsif preset = 2
    title$ = "Fundamental Frequency -> Y-Pos"
elsif preset = 3
    title$ = "LFO -> Star Coordinate Space"
elsif preset = 4
    title$ = "Multi-Voice Particle Swarm"
elsif preset = 5
    title$ = "Phase Lock -> Polar Rotation"
elsif preset = 6
    title$ = "FM Index -> Trochoid Geometry"
elsif preset = 7
    title$ = "Stereo Phase -> Lissajous Path"
endif

# ============================================================
# PHASE 1: GENERATE MASTER AUDIO (2-CHANNEL STEREO)
# ============================================================
demo Erase all
demo Select inner viewport: 0, 100, 0, 100
demo Axes: 0, 100, 0, 100
demo Paint rectangle: "Black", 0, 100, 0, 100
demo Font size: 14
demo Colour: "White"
demo Text: 50, "centre", 50, "half", "Synthesizing and Routing Audio..."
demoShow()

# We now generate a STEREO sound to support Lissajous and panning
masterSound = Create Sound from formula: "master", 2, 0, totalDur, sr, "0"
selectObject: masterSound

if preset = 1
    Formula: "0.8 * sin(2*pi*150*(x+time_offset)) * (0.5 + 0.5 * sin(2*pi*1.5*(x+time_offset)))"

elsif preset = 2
    # The sequencer logic remains for audio generation, but NOT for drawing
    Formula: "0.6 * sin(2*pi * (200 + 600 * ((floor((x+time_offset)*8)*7) mod 5)/4) * x) * exp(-(((x+time_offset)*8) - floor((x+time_offset)*8)) / 0.1)"

elsif preset = 3
    Formula: "0.5 * sin(2*pi*300*x + (5 * (0.5 - 0.5*cos(2*pi*0.5*(x+time_offset)))) * sin(2*pi*600*x))"

elsif preset = 4
    for v from 1 to 5
        Formula: "self + 0.15 * sin(2*pi * (200 * v + 100 * sin(2*pi*(0.1*v)*(x+time_offset))) * x)"
    endfor

elsif preset = 5
    # Stereo Phase offset
    Formula: "0.5 * sin(2*pi*100*x) + 0.5 * sin(2*pi*100.5*x + (4*pi * sin(2*pi*0.2*(x+time_offset))))"

elsif preset = 6
    Formula: "0.6 * sin(2*pi*250*x + (6 * sin(2*pi*0.4*(x+time_offset))) * sin(2*pi*500*x))"

elsif preset = 7
    # Left: 220Hz, Right: 330Hz (3:2 ratio perfect fifth) — rich audible stereo tone
    Formula: "if row = 1 then 0.5 * sin(2*pi*220*(x+time_offset)) else 0.5 * sin(2*pi*330*(x+time_offset) + pi/4) fi"

endif

selectObject: masterSound
Scale peak: master_volume

# Initialize Phosphor Trail Arrays
for h from 1 to 20
    hist_x[h] = 50
    hist_y[h] = 50
endfor

# ============================================================
# PHASE 2: PRE-COMPUTE ALL ANALYSIS DATA
# (Do all heavy lifting before playback starts)
# ============================================================
demo Paint rectangle: "Black", 0, 100, 0, 100
demo Colour: "White"
demo Text: 50, "centre", 60, "half", "Pre-computing signal analysis..."
demo Font size: 10
demo Colour: "{0.5,0.5,0.5}"
demo Text: 50, "centre", 40, "half", "(this makes playback smooth)"
demoShow()

# Pre-compute RMS — only needed for presets 1 and 2 (HUD)
# Uses direct sample access on masterSound — no Extract needed
samples_per_frame = round(frame_step * sr)
if preset = 1 or preset = 2
    selectObject: masterSound
    for frame from 0 to total_frames - 1
        .start_sample = frame * samples_per_frame + 1
        .end_sample = .start_sample + samples_per_frame - 1
        .sum_sq = 0
        .count = 0
        .s = .start_sample
        while .s <= .end_sample
            .v = Get value at sample number: 1, .s
            .sum_sq = .sum_sq + .v * .v
            .count = .count + 1
            .s = .s + 10
        endwhile
        rms_cache[frame] = sqrt(.sum_sq / .count)
    endfor
else
    # Fill with zeros — RMS not used by this preset
    for frame from 0 to total_frames - 1
        rms_cache[frame] = 0
    endfor
endif

# Pre-compute Pitch only if needed (preset 2)
if preset = 2
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Colour: "White"
    demo Text: 50, "centre", 60, "half", "Running pitch tracker..."
    demoShow()
    selectObject: masterSound
    fullPitch = To Pitch: 0, 75, 1000
    for frame from 0 to total_frames - 1
        t = frame * frame_step
        pv = Get value at time: t + (frame_step/2), "Hertz", "Linear"
        if pv = undefined
            pitch_cache[frame] = 200
        else
            pitch_cache[frame] = pv
        endif
    endfor
    removeObject: fullPitch
endif

# Pre-slice all audio chunks (done once, outside playback loop)
demo Paint rectangle: "Black", 0, 100, 0, 100
demo Colour: "White"
demo Text: 50, "centre", 60, "half", "Pre-slicing audio chunks..."
demoShow()
for frame from 0 to total_frames - 1
    t = frame * frame_step
    t_end = t + frame_step
    selectObject: masterSound
    chunk_id[frame] = Extract part: t, t_end, "rectangular", 1, "no"
endfor

# ============================================================
# PHASE 3: LEAN REAL-TIME PLAYBACK (draw + play only)
# ============================================================
for frame from 0 to total_frames - 1
    t = frame * frame_step
    t_end = t + frame_step
    t_offset = t + time_offset

    # Pull pre-computed values from cache
    rms_val = rms_cache[frame]
    if preset = 2
        pitch_val = pitch_cache[frame]
    else
        pitch_val = 200
    endif

    # --- VISUAL DRAWING ---
    demo Paint rectangle: "Black", 0, 100, 0, 100
    
    if preset = 1
        # Visual is physically coupled to the waveform's RMS energy!
        .radius = 5 + (rms_val * 120)
        .color$ = "White"
        if rms_val > 0.35
            .color$ = "Red"
        endif
        demo Paint circle (mm): .color$, 50, 50, .radius

    elsif preset = 2
        # Visual is physically coupled to Praat's Pitch Tracker!
        # Map 200Hz-800Hz to 20%-80% Y-axis
        .y_pos = 20 + ((pitch_val - 200) / 600) * 60
        demo Colour: "{0.2, 0.2, 0.2}"
        demo Draw line: 0, .y_pos, 100, .y_pos
        demo Paint circle (mm): "Cyan", 50, .y_pos, 5

    elsif preset = 3
        .mod = 0.5 - 0.5*cos(2*pi * 0.5 * t_offset)
        .outer = 40
        # FIXED: Inner scales from 15 (sharp star) to 40 (pure decagon) based on mod
        .inner = 15 + (25 * (1 - .mod)) 
        
        demo Line width: 3
        demo Colour: "Yellow"
        for .v from 0 to 9
            .a1 = .v * (2*pi/10)
            .a2 = (.v+1) * (2*pi/10)
            .r1 = if .v mod 2 = 0 then .outer else .inner fi
            .r2 = if (.v+1) mod 2 = 0 then .outer else .inner fi
            demo Draw line: 50 + .r1*cos(.a1), 50 + .r1*sin(.a1), 50 + .r2*cos(.a2), 50 + .r2*sin(.a2)
        endfor

    elsif preset = 4
        # Precompute all positions, draw lines first then circles (fewer colour switches)
        for .v from 1 to 5
            .x = 50 + 40 * cos(2*pi * (0.15*.v) * t_offset + .v)
            .y = 50 + 40 * sin(2*pi * (0.1*.v) * t_offset + .v)
            pos_x[.v] = .x
            pos_y[.v] = .y
        endfor
        demo Line width: 1
        demo Colour: "White"
        for .v from 1 to 5
            demo Draw line: 50, 50, pos_x[.v], pos_y[.v]
        endfor
        for .v from 1 to 5
            demo Paint circle (mm): "Cyan", pos_x[.v], pos_y[.v], 3
        endfor

    elsif preset = 5
        # Phase rotation locked to LFO — reduced to 40 dots for speed
        .lfo = sin(2*pi * 0.2 * t_offset)
        .theta = (t_offset * 2) + (2 * pi * .lfo)
        demo Colour: "{0.0, 1.0, 0.5}"
        for .j from 1 to 40
            .r = .j * 1.0
            .angle = .j * 0.15 + .theta
            .x = 50 + .r * cos(.angle)
            .y = 50 + .r * sin(.angle)
            .dot_size = 1.5 + 1.5 * sin(.angle * 3)
            if .dot_size < 0.05
                .dot_size = 0.05
            endif
            demo Paint circle (mm): "{0.0, 1.0, 0.5}", .x, .y, .dot_size
        endfor

    elsif preset = 6
        .a = 1.0
        .b = 2.0 + 1.5 * sin(2*pi * 0.4 * t_offset) 
        demo Line width: 2
        .c_val = abs(sin(2*pi * 0.4 * t_offset))
        c_val = .c_val
        demo Colour: "{1.0, 'c_val', 0.5}"
        
        .last_x = 0
        .last_y = 0
        .p = -75
        while .p <= 75
            .phi = .p * 0.2
            .x = 50 + 8 * (.a * .phi - .b * sin(.phi))
            .y = 50 + 8 * (.a - .b * cos(.phi))
            if .p > -75
                if .x > -20 and .x < 120
                    demo Draw line: .last_x, .last_y, .x, .y
                endif
            endif
            .last_x = .x
            .last_y = .y
            .p = .p + 2
        endwhile

    elsif preset = 7
        # STEREO LISSAJOUS WITH PHOSPHOR TRAILS
        # Ratio 3:2 matches the audio (220Hz left, 330Hz right = perfect fifth)
        # Slow precession keeps figure alive without unbounded drift
        .phase_drift = pi/4 + 0.3 * sin(2*pi * 0.05 * t_offset)
        .new_x = 50 + 45 * sin(2*pi * 3.0 * t_offset)
        .new_y = 50 + 45 * sin(2*pi * 2.0 * t_offset + .phase_drift)
        
        # Shift the history array
        for .h from 1 to 19
            .idx = 21 - .h
            hist_x[.idx] = hist_x[.idx - 1]
            hist_y[.idx] = hist_y[.idx - 1]
        endfor
        hist_x[1] = .new_x
        hist_y[1] = .new_y
        
        # Draw phosphor trail
        for .h from 1 to 20
            .fade = 1.0 - (.h / 20)
            if .fade < 0.05
                .fade = 0.05
            endif
            fade_val = .fade
            demo Paint circle (mm): "{0.2, 'fade_val', 0.8}", hist_x[.h], hist_y[.h], 3 * fade_val
        endfor
        
        # Draw main bright point
        demo Paint circle (mm): "White", .new_x, .new_y, 4

    endif
    
    # --- HUD OVERLAY ---
    demo Font size: 10
    demo Colour: "{0.6, 0.6, 0.6}"
    demo Text: 2, "left", 98, "half", title$
    
    # Live Parameter Readout!
    .hud$ = "t = " + fixed$(t, 2) + "s   |   RMS = " + fixed$(rms_val, 3)
    if preset = 2
        .hud$ = .hud$ + "   |   PITCH = " + fixed$(pitch_val, 1) + " Hz"
    elsif preset = 5
        .hud$ = .hud$ + "   |   LFO PHASE = " + fixed$(.lfo, 2)
    endif
    
    demo Text: 2, "left", 94, "half", .hud$
    demoShow()
    
    # --- AUDIO PLAYBACK ---
    selectObject: chunk_id[frame]
    Play
    removeObject: chunk_id[frame]
endfor  ; end Phase 3 playback loop

demo Paint rectangle: "Black", 0, 100, 0, 100
demo Font size: 14
demo Colour: "White"
demo Text: 50, "centre", 50, "half", "System Terminated."
demoShow()