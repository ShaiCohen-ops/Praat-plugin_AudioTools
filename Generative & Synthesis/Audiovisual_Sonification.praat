# ============================================================
# Praat AudioTools - Audiovisual_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 5.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified Audiovisual Engine — two modes in one script.
#
#   MODE 1 — AV PRESETS  (signal analysis → real-time visuals)
#     1. TRUE ANALYSIS: RMS -> Size         (amplitude-driven circle)
#     2. TRUE ANALYSIS: Pitch -> Y-Pos      (pitch-tracker dot)
#     3. Tone -> Sharpness                  (The Morphing Star)
#     4. Voices -> Swarm                    (The Particle System)
#     5. Phase -> Rotation                  (The Hypnotic Spiral)
#     6. FM Index -> Geometry               (The Trochoid Spirograph)
#     7. Stereo Waveform -> Path            (Lissajous + Phosphor Trails)
#
#   MODE 2 — POLY COMPOSITION  (multi-voice generative engine)
#     Shapes:     Circle, Triangle, Square, Pentagon, Hexagon,
#                 Star, Plane, Points, Lines
#     Colours:    Rainbow, Fire, Ice, Cyan, Magenta, Gold, White
#     Movement:   Orbit, Spiral, Bounce, Pendulum, Expand/Contract
#     Synthesis:  Pure Sine, FM, AM, Additive, Pulse
#     Voices:     1 – 8
#
# Implementation notes:
#   • "step" is a reserved Praat keyword — never use as variable name.
#   • "for x from a to b step n" does NOT exist in Praat;
#     use a while loop for non-unit steps.
#   • Dot-prefixed locals (.var) silently fail inside strings —
#     always copy to a plain variable before string interpolation.
#   • Build {r,g,b} colour strings via string$() concatenation,
#     never via '.var' interpolation.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: Unified Audiovisual Engine.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================================
# PERSISTENT DEFAULTS (used as initial values on first run)
# ============================================================
mode              = 1
preset            = 1
shape             = 1
color_palette     = 1
movement          = 1
synthesis_type    = 1
number_of_voices  = 3
total_duration    = 4
master_volume     = 0.85
show_trails       = 1
randomize_seed    = 1

# ============================================================
# FORM (persistent — re-opens after each run)
# ============================================================
repeat

beginPause: "AudioTools v5 — Select Mode & Configure"

    comment: "════  MODE  ════"
    optionmenu: "Mode", mode
        option: "AV Presets  (signal analysis → visuals)"
        option: "Poly Composition  (multi-voice generative)"

    comment: "────  AV PRESETS — ignored in Poly mode  ────"
    optionmenu: "Preset", preset
        option: "1. TRUE ANALYSIS: RMS -> Size"
        option: "2. TRUE ANALYSIS: Pitch -> Y-Position"
        option: "3. Tone -> Sharpness (The Morphing Star)"
        option: "4. Voices -> Swarm (The Particle System)"
        option: "5. Phase -> Rotation (The Hypnotic Spiral)"
        option: "6. FM Index -> Geometry (The Trochoid Spirograph)"
        option: "7. Stereo Waveform -> Path (Lissajous)"

    comment: "────  POLY COMPOSITION — ignored in AV Presets mode  ────"
    optionmenu: "Shape", shape
        option: "Circle"
        option: "Triangle  (3 sides)"
        option: "Square  (4 sides)"
        option: "Pentagon  (5 sides)"
        option: "Hexagon  (6 sides)"
        option: "Star  (5-pointed)"
        option: "Plane  (filled square)"
        option: "Points"
        option: "Lines  (from centre)"
    optionmenu: "Color palette", color_palette
        option: "Rainbow  (per voice)"
        option: "Fire  (red to orange)"
        option: "Ice  (blue to white)"
        option: "Cyan"
        option: "Magenta"
        option: "Gold"
        option: "White"
    optionmenu: "Movement", movement
        option: "Orbit  (circular)"
        option: "Spiral  (in and out)"
        option: "Bounce  (Lissajous paths)"
        option: "Pendulum  (coupled XY)"
        option: "Expand / Contract"
    optionmenu: "Synthesis type", synthesis_type
        option: "Pure Sine"
        option: "FM  (rich timbre)"
        option: "AM  (tremolo)"
        option: "Additive  (harmonics 1-4)"
        option: "Pulse  (bright, 6 partials)"
    natural: "Number of voices", number_of_voices

    comment: "════  SHARED PARAMETERS  ════"
    real: "Total duration", total_duration
    real: "Master volume", master_volume
    boolean: "Show trails", show_trails
    boolean: "Randomize seed", randomize_seed

clicked = endPause: "Quit", "Run", 2, 1

if clicked = 1
    exitScript: "Audiovisual session ended."
endif

# ============================================================
# SHARED SETUP
# ============================================================
totalDur     = total_duration
frame_step   = 0.08        ; ~12 fps
sr           = 44100
total_frames = floor(totalDur / frame_step)

time_offset = 0
if randomize_seed
    time_offset = randomUniform(0, 100)
endif

# ============================================================
# ════════════════════════════════════════════════════════════
#  MODE 1 — AV PRESETS
# ════════════════════════════════════════════════════════════
# ============================================================
if mode = 1

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

    # ----------------------------------------------------------
    # AV PHASE 1: GENERATE MASTER AUDIO (2-channel stereo)
    # ----------------------------------------------------------
    demo Erase all
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Font size: 14
    demo Colour: "White"
    demo Text: 50, "centre", 50, "half", "Synthesizing and Routing Audio..."
    demoShow()

    masterSound = Create Sound from formula: "master", 2, 0, totalDur, sr, "0"
    selectObject: masterSound

    if preset = 1
        Formula: "0.8 * sin(2*pi*150*(x+time_offset)) * (0.5 + 0.5 * sin(2*pi*1.5*(x+time_offset)))"

    elsif preset = 2
        Formula: "0.6 * sin(2*pi * (200 + 600 * ((floor((x+time_offset)*8)*7) mod 5)/4) * x) * exp(-(((x+time_offset)*8) - floor((x+time_offset)*8)) / 0.1)"

    elsif preset = 3
        Formula: "0.5 * sin(2*pi*300*x + (5 * (0.5 - 0.5*cos(2*pi*0.5*(x+time_offset)))) * sin(2*pi*600*x))"

    elsif preset = 4
        for v from 1 to 5
            Formula: "self + 0.15 * sin(2*pi * (200 * v + 100 * sin(2*pi*(0.1*v)*(x+time_offset))) * x)"
        endfor

    elsif preset = 5
        Formula: "0.5 * sin(2*pi*100*x) + 0.5 * sin(2*pi*100.5*x + (4*pi * sin(2*pi*0.2*(x+time_offset))))"

    elsif preset = 6
        Formula: "0.6 * sin(2*pi*250*x + (6 * sin(2*pi*0.4*(x+time_offset))) * sin(2*pi*500*x))"

    elsif preset = 7
        Formula: "if row = 1 then 0.5 * sin(2*pi*220*(x+time_offset)) else 0.5 * sin(2*pi*330*(x+time_offset) + pi/4) fi"

    endif

    selectObject: masterSound
    Scale peak: master_volume

    # Initialize Lissajous phosphor trail (preset 7)
    for h from 1 to 20
        hist_x[h] = 50
        hist_y[h] = 50
    endfor

    # ----------------------------------------------------------
    # AV PHASE 2: PRE-COMPUTE ANALYSIS DATA
    # ----------------------------------------------------------
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Colour: "White"
    demo Text: 50, "centre", 60, "half", "Pre-computing signal analysis..."
    demo Font size: 10
    demo Colour: "{0.5, 0.5, 0.5}"
    demo Text: 50, "centre", 40, "half", "(this makes playback smooth)"
    demoShow()

    samples_per_frame = round(frame_step * sr)
    if preset = 1 or preset = 2
        selectObject: masterSound
        for frame from 0 to total_frames - 1
            .start_sample = frame * samples_per_frame + 1
            .end_sample   = .start_sample + samples_per_frame - 1
            .sum_sq = 0
            .count  = 0
            .s = .start_sample
            while .s <= .end_sample
                .v = Get value at sample number: 1, .s
                .sum_sq = .sum_sq + .v * .v
                .count  = .count + 1
                .s = .s + 10
            endwhile
            rms_cache[frame] = sqrt(.sum_sq / .count)
        endfor
    else
        for frame from 0 to total_frames - 1
            rms_cache[frame] = 0
        endfor
    endif

    if preset = 2
        demo Paint rectangle: "Black", 0, 100, 0, 100
        demo Colour: "White"
        demo Text: 50, "centre", 60, "half", "Running pitch tracker..."
        demoShow()
        selectObject: masterSound
        fullPitch = To Pitch: 0, 75, 1000
        for frame from 0 to total_frames - 1
            t = frame * frame_step
            pv = Get value at time: t + (frame_step / 2), "Hertz", "Linear"
            if pv = undefined
                pitch_cache[frame] = 200
            else
                pitch_cache[frame] = pv
            endif
        endfor
        removeObject: fullPitch
    endif

    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Colour: "White"
    demo Text: 50, "centre", 60, "half", "Pre-slicing audio chunks..."
    demoShow()
    for frame from 0 to total_frames - 1
        t     = frame * frame_step
        t_end = t + frame_step
        selectObject: masterSound
        chunk_id[frame] = Extract part: t, t_end, "rectangular", 1, "no"
    endfor

    # ----------------------------------------------------------
    # AV PHASE 3: REAL-TIME PLAYBACK
    # ----------------------------------------------------------
    for frame from 0 to total_frames - 1
        t        = frame * frame_step
        t_end    = t + frame_step
        t_offset = t + time_offset

        rms_val = rms_cache[frame]
        if preset = 2
            pitch_val = pitch_cache[frame]
        else
            pitch_val = 200
        endif

        demo Paint rectangle: "Black", 0, 100, 0, 100

        if preset = 1
            .radius = 5 + (rms_val * 120)
            .color$ = "White"
            if rms_val > 0.35
                .color$ = "Red"
            endif
            demo Paint circle (mm): .color$, 50, 50, .radius

        elsif preset = 2
            .y_pos = 20 + ((pitch_val - 200) / 600) * 60
            demo Colour: "{0.2, 0.2, 0.2}"
            demo Draw line: 0, .y_pos, 100, .y_pos
            demo Paint circle (mm): "Cyan", 50, .y_pos, 5

        elsif preset = 3
            .mod   = 0.5 - 0.5 * cos(2*pi * 0.5 * t_offset)
            .outer = 40
            .inner = 15 + (25 * (1 - .mod))
            demo Line width: 3
            demo Colour: "Yellow"
            for .v from 0 to 9
                .a1 = .v * (2*pi / 10)
                .a2 = (.v + 1) * (2*pi / 10)
                .r1 = if .v mod 2 = 0 then .outer else .inner fi
                .r2 = if (.v + 1) mod 2 = 0 then .outer else .inner fi
                demo Draw line: 50 + .r1*cos(.a1), 50 + .r1*sin(.a1), 50 + .r2*cos(.a2), 50 + .r2*sin(.a2)
            endfor

        elsif preset = 4
            for .v from 1 to 5
                .x = 50 + 40 * cos(2*pi * (0.15 * .v) * t_offset + .v)
                .y = 50 + 40 * sin(2*pi * (0.1  * .v) * t_offset + .v)
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
            .lfo   = sin(2*pi * 0.2 * t_offset)
            .theta = (t_offset * 2) + (2 * pi * .lfo)
            for .j from 1 to 40
                .r        = .j * 1.0
                .angle    = .j * 0.15 + .theta
                .x        = 50 + .r * cos(.angle)
                .y        = 50 + .r * sin(.angle)
                .dot_size = 1.5 + 1.5 * sin(.angle * 3)
                if .dot_size < 0.05
                    .dot_size = 0.05
                endif
                demo Paint circle (mm): "{0.0, 1.0, 0.5}", .x, .y, .dot_size
            endfor

        elsif preset = 6
            .a     = 1.0
            .b     = 2.0 + 1.5 * sin(2*pi * 0.4 * t_offset)
            demo Line width: 2
            .c_val = abs(sin(2*pi * 0.4 * t_offset))
            c_val  = .c_val
            demo Colour: "{1.0, 'c_val', 0.5}"
            .last_x = 0
            .last_y = 0
            .p = -75
            while .p <= 75
                .phi = .p * 0.2
                .x   = 50 + 8 * (.a * .phi - .b * sin(.phi))
                .y   = 50 + 8 * (.a - .b * cos(.phi))
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
            ; Lissajous 3:2 (matches 220/330 Hz audio — perfect fifth)
            .phase_drift = pi/4 + 0.3 * sin(2*pi * 0.05 * t_offset)
            .new_x = 50 + 45 * sin(2*pi * 3.0 * t_offset)
            .new_y = 50 + 45 * sin(2*pi * 2.0 * t_offset + .phase_drift)
            for .h from 1 to 19
                .idx = 21 - .h
                hist_x[.idx] = hist_x[.idx - 1]
                hist_y[.idx] = hist_y[.idx - 1]
            endfor
            hist_x[1] = .new_x
            hist_y[1] = .new_y
            for .h from 1 to 20
                .fade    = 1.0 - (.h / 20)
                if .fade < 0.05
                    .fade = 0.05
                endif
                fade_val = .fade
                demo Paint circle (mm): "{0.2, 'fade_val', 0.8}", hist_x[.h], hist_y[.h], 3 * fade_val
            endfor
            demo Paint circle (mm): "White", .new_x, .new_y, 4

        endif

        ; HUD
        demo Font size: 10
        demo Colour: "{0.6, 0.6, 0.6}"
        demo Text: 2, "left", 98, "half", title$
        .hud$ = "t = " + fixed$(t, 2) + "s   |   RMS = " + fixed$(rms_val, 3)
        if preset = 2
            .hud$ = .hud$ + "   |   PITCH = " + fixed$(pitch_val, 1) + " Hz"
        elsif preset = 5
            .hud$ = .hud$ + "   |   LFO PHASE = " + fixed$(.lfo, 2)
        endif
        demo Text: 2, "left", 94, "half", .hud$
        demoShow()

        selectObject: chunk_id[frame]
        Play
        removeObject: chunk_id[frame]
    endfor

    removeObject: masterSound
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Font size: 14
    demo Colour: "White"
    demo Text: 50, "centre", 50, "half", "System Terminated."
    demoShow()

# ============================================================
# ════════════════════════════════════════════════════════════
#  MODE 2 — POLY COMPOSITION
# ════════════════════════════════════════════════════════════
# ============================================================
elsif mode = 2

    # Clamp voices to safe range 1–8
    n_voices = number_of_voices
    if n_voices < 1
        n_voices = 1
    endif
    if n_voices > 8
        n_voices = 8
    endif

    # Pentatonic frequency table — root A2 = 110 Hz
    # Ratios: 1  9/8  5/4  3/2  5/3  2  9/4  5/2
    penta_ratio[1] = 1.000
    penta_ratio[2] = 1.125
    penta_ratio[3] = 1.250
    penta_ratio[4] = 1.500
    penta_ratio[5] = 1.667
    penta_ratio[6] = 2.000
    penta_ratio[7] = 2.250
    penta_ratio[8] = 2.500
    root_freq = 110

    for v from 1 to n_voices
        .idx = ((v - 1) mod 8) + 1
        voice_freq[v]  = root_freq * penta_ratio[.idx]
        voice_phase[v] = (v - 1) * 2 * pi / n_voices
    endfor

    # ----------------------------------------------------------
    # POLY PHASE 1: SYNTHESISE AUDIO
    # ----------------------------------------------------------
    demo Erase all
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Font size: 14
    demo Colour: "White"
    demo Text: 50, "centre", 55, "half", "Synthesising voices..."
    demoShow()

    masterSound = Create Sound from formula: "poly", 1, 0, totalDur, sr, "0"
    selectObject: masterSound

    for v from 1 to n_voices
        vf  = voice_freq[v]
        vp  = voice_phase[v]
        amp = 0.8 / n_voices

        if synthesis_type = 1
            Formula: "self + 'amp' * sin(2*pi * 'vf' * (x + 'time_offset') + 'vp')"

        elsif synthesis_type = 2
            Formula: "self + 'amp' * sin(2*pi * 'vf' * (x + 'time_offset') + 3 * sin(2*pi * 'vf' * 2 * (x + 'time_offset')) + 'vp')"

        elsif synthesis_type = 3
            Formula: "self + 'amp' * (0.5 + 0.5 * sin(2*pi * 4 * (x + 'time_offset') + 'vp')) * sin(2*pi * 'vf' * (x + 'time_offset'))"

        elsif synthesis_type = 4
            Formula: "self + 'amp' * (0.55 * sin(2*pi * 'vf' * (x + 'time_offset')) + 0.25 * sin(2*pi * 'vf' * 2 * (x + 'time_offset')) + 0.13 * sin(2*pi * 'vf' * 3 * (x + 'time_offset')) + 0.07 * sin(2*pi * 'vf' * 4 * (x + 'time_offset')) + 'vp' * 0)"

        elsif synthesis_type = 5
            Formula: "self + 'amp' * (sin(2*pi * 'vf' * (x + 'time_offset')) + 0.5 * sin(2*pi * 'vf' * 2 * (x + 'time_offset')) + 0.33 * sin(2*pi * 'vf' * 3 * (x + 'time_offset')) + 0.25 * sin(2*pi * 'vf' * 4 * (x + 'time_offset')) + 0.2 * sin(2*pi * 'vf' * 5 * (x + 'time_offset')) + 0.17 * sin(2*pi * 'vf' * 6 * (x + 'time_offset')))"

        endif
    endfor

    selectObject: masterSound
    Scale peak: master_volume

    # ----------------------------------------------------------
    # POLY PHASE 2: PRE-SLICE AUDIO CHUNKS
    # ----------------------------------------------------------
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Colour: "White"
    demo Text: 50, "centre", 60, "half", "Pre-slicing audio..."
    demo Font size: 10
    demo Colour: "{0.5, 0.5, 0.5}"
    demo Text: 50, "centre", 40, "half", "(ensures smooth playback)"
    demoShow()

    for frame from 0 to total_frames - 1
        t_s = frame * frame_step
        t_e = t_s + frame_step
        selectObject: masterSound
        chunk_id[frame] = Extract part: t_s, t_e, "rectangular", 1, "no"
    endfor

    # Init per-voice trail arrays
    # trail_x'v'[h]: h=1 newest, h=trail_len oldest
    trail_len = 14
    for v from 1 to n_voices
        for h from 1 to trail_len
            trail_x'v'[h] = 50
            trail_y'v'[h] = 50
        endfor
    endfor

    # ----------------------------------------------------------
    # POLY PHASE 3: REAL-TIME PLAYBACK
    # ----------------------------------------------------------
    for frame from 0 to total_frames - 1
        t     = frame * frame_step
        t_off = t + time_offset

        demo Paint rectangle: "Black", 0, 100, 0, 100

        for v from 1 to n_voices
            vphase = voice_phase[v]

            ; ---- POSITION ----
            if movement = 1
                cx = 50 + 35 * cos(2 * pi * 0.4 * t_off + vphase)
                cy = 50 + 35 * sin(2 * pi * 0.4 * t_off + vphase)

            elsif movement = 2
                sp_r = 12 + 28 * abs(sin(2 * pi * 0.25 * t_off + vphase * 0.4))
                cx = 50 + sp_r * cos(2 * pi * 0.5 * t_off + vphase)
                cy = 50 + sp_r * sin(2 * pi * 0.5 * t_off + vphase)

            elsif movement = 3
                cx = 50 + 38 * sin(2 * pi * (0.30 + 0.04 * v) * t_off + vphase)
                cy = 50 + 38 * sin(2 * pi * (0.19 + 0.03 * v) * t_off + vphase * 0.7)

            elsif movement = 4
                cx = 50 + 38 * sin(2 * pi * 0.35 * t_off + vphase)
                cy = 50 + 38 * sin(2 * pi * 0.55 * t_off + vphase + pi / 3)

            elsif movement = 5
                exp_r = 8 + 35 * (0.5 + 0.5 * sin(2 * pi * 0.28 * t_off + vphase))
                cx = 50 + exp_r * cos(vphase)
                cy = 50 + exp_r * sin(vphase)

            endif

            ; ---- COLOUR ----
            bright = 0.65 + 0.35 * sin(2 * pi * 0.5 * t_off + vphase)

            if color_palette = 1
                hue   = (v - 1) / n_voices
                r_col = 0.5 + 0.5 * sin(hue * 2 * pi)
                g_col = 0.5 + 0.5 * sin(hue * 2 * pi + 2 * pi / 3)
                b_col = 0.5 + 0.5 * sin(hue * 2 * pi + 4 * pi / 3)
            elsif color_palette = 2
                t_col = (v - 1) / (max(n_voices - 1, 1))
                r_col = 1.0
                g_col = t_col * 0.65
                b_col = 0.0
            elsif color_palette = 3
                t_col = (v - 1) / (max(n_voices - 1, 1))
                r_col = t_col * 0.6
                g_col = t_col * 0.85
                b_col = 1.0
            elsif color_palette = 4
                r_col = 0.0
                g_col = 1.0
                b_col = 1.0
            elsif color_palette = 5
                r_col = 1.0
                g_col = 0.0
                b_col = 1.0
            elsif color_palette = 6
                r_col = 1.0
                g_col = 0.80
                b_col = 0.0
            elsif color_palette = 7
                r_col = 1.0
                g_col = 1.0
                b_col = 1.0
            endif

            ; Apply brightness and clamp
            r_col = r_col * bright
            g_col = g_col * bright
            b_col = b_col * bright
            if r_col > 1.0
                r_col = 1.0
            endif
            if g_col > 1.0
                g_col = 1.0
            endif
            if b_col > 1.0
                b_col = 1.0
            endif
            if r_col < 0.0
                r_col = 0.0
            endif
            if g_col < 0.0
                g_col = 0.0
            endif
            if b_col < 0.0
                b_col = 0.0
            endif

            ; Build colour string safely via concatenation
            col_str$ = "{" + string$(r_col) + ", " + string$(g_col) + ", " + string$(b_col) + "}"

            ; ---- TRAILS ----
            if show_trails = 1
                ; Shift trail (index 1 = newest)
                .h = trail_len
                while .h >= 2
                    trail_x'v'[.h] = trail_x'v'[.h - 1]
                    trail_y'v'[.h] = trail_y'v'[.h - 1]
                    .h = .h - 1
                endwhile
                trail_x'v'[1] = cx
                trail_y'v'[1] = cy

                ; Draw oldest-to-newest so brightest dot is on top
                .h = trail_len
                while .h >= 2
                    .fade = 1.0 - (.h / trail_len)
                    if .fade < 0.04
                        .fade = 0.04
                    endif
                    tr_r   = r_col * .fade
                    tr_g   = g_col * .fade
                    tr_b   = b_col * .fade
                    tr_col$ = "{" + string$(tr_r) + ", " + string$(tr_g) + ", " + string$(tr_b) + "}"
                    tr_sz  = 3.0 * .fade
                    if tr_sz < 0.15
                        tr_sz = 0.15
                    endif
                    demo Paint circle (mm): tr_col$, trail_x'v'[.h], trail_y'v'[.h], tr_sz
                    .h = .h - 1
                endwhile
            endif

            ; ---- SHAPE ----
            shape_r   = 7 + 3 * sin(2 * pi * 0.5 * t_off + vphase)
            shape_rot = t_off * (0.3 + 0.04 * v)

            demo Line width: 2
            demo Colour: col_str$

            if shape = 1
                demo Paint circle (mm): col_str$, cx, cy, shape_r

            elsif shape = 2
                for .s from 0 to 2
                    .a1 = .s * 2 * pi / 3 + shape_rot
                    .a2 = (.s + 1) * 2 * pi / 3 + shape_rot
                    demo Draw line: cx + shape_r*cos(.a1), cy + shape_r*sin(.a1), cx + shape_r*cos(.a2), cy + shape_r*sin(.a2)
                endfor

            elsif shape = 3
                for .s from 0 to 3
                    .a1 = .s * 2 * pi / 4 + shape_rot
                    .a2 = (.s + 1) * 2 * pi / 4 + shape_rot
                    demo Draw line: cx + shape_r*cos(.a1), cy + shape_r*sin(.a1), cx + shape_r*cos(.a2), cy + shape_r*sin(.a2)
                endfor

            elsif shape = 4
                for .s from 0 to 4
                    .a1 = .s * 2 * pi / 5 + shape_rot
                    .a2 = (.s + 1) * 2 * pi / 5 + shape_rot
                    demo Draw line: cx + shape_r*cos(.a1), cy + shape_r*sin(.a1), cx + shape_r*cos(.a2), cy + shape_r*sin(.a2)
                endfor

            elsif shape = 5
                for .s from 0 to 5
                    .a1 = .s * 2 * pi / 6 + shape_rot
                    .a2 = (.s + 1) * 2 * pi / 6 + shape_rot
                    demo Draw line: cx + shape_r*cos(.a1), cy + shape_r*sin(.a1), cx + shape_r*cos(.a2), cy + shape_r*sin(.a2)
                endfor

            elsif shape = 6
                .outer_r = shape_r
                .inner_r = shape_r * 0.4
                for .s from 0 to 9
                    .a1 = .s * pi / 5 + shape_rot
                    .a2 = (.s + 1) * pi / 5 + shape_rot
                    .r1 = if .s mod 2 = 0 then .outer_r else .inner_r fi
                    .r2 = if (.s + 1) mod 2 = 0 then .outer_r else .inner_r fi
                    demo Draw line: cx + .r1*cos(.a1), cy + .r1*sin(.a1), cx + .r2*cos(.a2), cy + .r2*sin(.a2)
                endfor

            elsif shape = 7
                ; Plane: filled square with rotating outline
                for .s from 0 to 3
                    .a1 = .s * 2 * pi / 4 + shape_rot
                    .a2 = (.s + 1) * 2 * pi / 4 + shape_rot
                    demo Draw line: cx + shape_r*cos(.a1), cy + shape_r*sin(.a1), cx + shape_r*cos(.a2), cy + shape_r*sin(.a2)
                endfor
                demo Paint rectangle: col_str$, cx - shape_r*0.7, cx + shape_r*0.7, cy - shape_r*0.7, cy + shape_r*0.7

            elsif shape = 8
                demo Paint circle (mm): col_str$, cx, cy, 2.5

            elsif shape = 9
                demo Line width: 2
                demo Draw line: 50, 50, cx, cy

            endif

        endfor   ; end voice loop

        ; HUD
        demo Font size: 9
        demo Colour: "{0.45, 0.45, 0.45}"
        demo Text: 2, "left", 98, "half", "Poly Composition  |  voices: " + string$(n_voices)
        demo Text: 2, "left", 94, "half", "t = " + fixed$(t, 2) + " s"
        demoShow()

        selectObject: chunk_id[frame]
        Play
        removeObject: chunk_id[frame]

    endfor   ; end playback loop

    removeObject: masterSound
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Font size: 14
    demo Colour: "White"
    demo Text: 50, "centre", 50, "half", "Composition complete."
    demoShow()

endif   ; end mode branch

until 0
