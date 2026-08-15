# ============================================================
# Praat AudioTools - Audiovisual_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 5.1.1 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified Audiovisual Engine — two modes in one script.
#
#   MODE 1 — AV PRESETS  (generated signal/control → measured real-time visuals)
#     1. TRUE ANALYSIS: RMS -> Size         (amplitude-driven circle)
#     2. TRUE ANALYSIS: Pitch -> Y-Pos      (pitch-tracker dot)
#     3. FM Index -> Star Sharpness          (The Morphing Star)
#     4. Instantaneous Voice Freq -> Swarm   (The Particle System)
#     5. Phase Modulation -> Rotation        (The Hypnotic Spiral)
#     6. FM Index -> Geometry               (The Trochoid Spirograph)
#     7. Stereo Waveform -> Path             (measured L/R Lissajous)
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
#
# v5.1 reviewed:
#   - Replaced 80-ms chunk-by-chunk Play with one continuous `asynchronous Play`
#     per run; Demo animation is paced with sleep(). This removes hundreds of
#     temporary Sound objects and avoids device restart gaps/clicks.
#   - Uses ceiling() frame coverage so the final audio tail is not omitted.
#   - Added duration/master-volume guards and reproducible initial-phase seed.
#   - Preset 2 now uses click-safe local-note phase/envelopes before Pitch QC.
#   - Preset 4 uses mathematically correct integrated slow FM (bounded deviation).
#   - Presets 3/5/6 visualise the exact synthesis control that drives the sound.
#   - Preset 7 draws the actual stereo waveform relation sampled from the master
#     Sound, instead of an unrelated low-frequency 3:2 surrogate.
#   - RMS radius uses measured, run-specific normalization; Pitch Y mapping uses
#     the measured tracked range and holds the last valid value through dropouts.
#   - Poly mode is now stereo: visual X position drives equal-power stereo pan.
#   - Poly AM/additive/pulse oscillators now honour per-voice phase consistently.
#   - Global 10-ms edge fade prevents start/end clicks before peak scaling.
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
randomize_initial_phase = 1
random_seed        = 0

# ============================================================
# FORM (persistent — re-opens after each run)
# ============================================================
repeat

beginPause: "AudioTools v5.1 — Select Mode & Configure"

    comment: "════  MODE  ════"
    optionmenu: "Mode", mode
        option: "AV Presets  (generated signal/control → measured visuals)"
        option: "Poly Composition  (multi-voice generative)"

    comment: "────  AV PRESETS — ignored in Poly mode  ────"
    optionmenu: "Preset", preset
        option: "1. TRUE ANALYSIS: RMS -> Size"
        option: "2. TRUE ANALYSIS: Pitch -> Y-Position"
        option: "3. FM Index -> Star Sharpness (The Morphing Star)"
        option: "4. Voice Frequency -> Swarm (The Particle System)"
        option: "5. Phase Modulation -> Rotation (The Hypnotic Spiral)"
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
        option: "Plane  (filled tile + rotating outline)"
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
    boolean: "Show trails (Poly mode)", show_trails
    boolean: "Randomize initial phase", randomize_initial_phase
    integer: "Random seed (0 = unpredictable)", random_seed

clicked = endPause: "Quit", "Run", 2, 1

if clicked = 1
    exitScript: "Audiovisual session ended."
endif

# ============================================================
# SHARED SETUP
# ============================================================
totalDur   = total_duration
frame_step = 0.08        ; ~12.5 fps
sr         = 44100

if totalDur <= 0
    exitScript: "Total duration must be greater than zero."
endif
if totalDur > 300
    exitScript: "Total duration is limited to 300 seconds for a real-time Demo animation."
endif
if master_volume < 0
    master_volume = 0
endif
if master_volume > 0.98
    master_volume = 0.98
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (unpredictable) or a positive integer."
endif

total_frames = ceiling(totalDur / frame_step)
if total_frames < 1
    total_frames = 1
endif

# Optional randomized initial phase/time offset, with reproducibility.
time_offset = 0
seedWasFixed = 0
if randomize_initial_phase
    if random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
        seedWasFixed = 1
    endif
    time_offset = randomUniform(0, 100)
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
endif

edgeFade = min(0.010, totalDur / 4)

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
        title$ = "FM Index -> Star Sharpness"
    elsif preset = 4
        title$ = "Instantaneous Voice Frequency -> Swarm"
    elsif preset = 5
        title$ = "Phase Modulation -> Polar Rotation"
    elsif preset = 6
        title$ = "FM Index -> Trochoid Geometry"
    elsif preset = 7
        title$ = "Measured Stereo Waveform -> Lissajous"
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
        # 8 notes/s. Local note phase plus a sine envelope makes every note
        # start and end at zero, so pitch changes do not create discontinuities.
        Formula: "0.65 * sin(pi * (((x+time_offset)*8) - floor((x+time_offset)*8))) * sin(2*pi * (200 + 600 * ((floor((x+time_offset)*8)*7) mod 5)/4) * ((((x+time_offset)*8) - floor((x+time_offset)*8)) / 8))"

    elsif preset = 3
        Formula: "0.5 * sin(2*pi*300*x + (5 * (0.5 - 0.5*cos(2*pi*0.5*(x+time_offset)))) * sin(2*pi*600*x))"

    elsif preset = 4
        # Exact integral of f(t)=200*v + 100*sin(2*pi*0.1*v*t).
        # Unlike f(t)*t, this keeps the intended +/-100-Hz deviation bounded.
        for v from 1 to 5
            Formula: "self + 0.15 * sin(2*pi*(200*v)*x - (100/(0.1*v))*cos(2*pi*(0.1*v)*(x+time_offset)))"
        endfor

    elsif preset = 5
        Formula: "0.5 * sin(2*pi*100*x) + 0.5 * sin(2*pi*100.5*x + (4*pi * sin(2*pi*0.2*(x+time_offset))))"

    elsif preset = 6
        Formula: "0.6 * sin(2*pi*250*x + (6 * sin(2*pi*0.4*(x+time_offset))) * sin(2*pi*500*x))"

    elsif preset = 7
        Formula: "if row = 1 then 0.5 * sin(2*pi*220*(x+time_offset)) else 0.5 * sin(2*pi*330*(x+time_offset) + pi/4) fi"

    endif

    selectObject: masterSound
    if edgeFade > 0
        fadeOutStart = totalDur - edgeFade
        Formula: "if x < edgeFade then self * (x/edgeFade) else if x > fadeOutStart then self * ((totalDur-x)/edgeFade) else self fi fi"
    endif
    if master_volume > 0
        Scale peak: master_volume
    else
        Formula: "0"
    endif

    total_samples = Get number of samples

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
    rmsMax = 0
    if preset = 1 or preset = 2
        selectObject: masterSound
        for frame from 0 to total_frames - 1
            .start_sample = frame * samples_per_frame + 1
            .end_sample   = min(total_samples, .start_sample + samples_per_frame - 1)
            .sum_sq = 0
            .count  = 0
            .s = .start_sample
            while .s <= .end_sample
                .v = Get value at sample number: 1, .s
                .sum_sq = .sum_sq + .v * .v
                .count  = .count + 1
                .s = .s + 10
            endwhile
            if .count > 0
                rms_cache[frame] = sqrt(.sum_sq / .count)
            else
                rms_cache[frame] = 0
            endif
            if rms_cache[frame] > rmsMax
                rmsMax = rms_cache[frame]
            endif
        endfor
    else
        for frame from 0 to total_frames - 1
            rms_cache[frame] = 0
        endfor
    endif
    if rmsMax <= 0
        rmsMax = 1
    endif

    pitchMin = 1e30
    pitchMax = 0
    if preset = 2
        demo Paint rectangle: "Black", 0, 100, 0, 100
        demo Colour: "White"
        demo Text: 50, "centre", 60, "half", "Running pitch tracker..."
        demoShow()
        selectObject: masterSound
        fullPitch = To Pitch: 0.005, 75, 1000
        lastPitch = 200
        for frame from 0 to total_frames - 1
            t = min(totalDur, frame * frame_step + frame_step / 2)
            pv = Get value at time: t, "Hertz", "Linear"
            if pv = undefined or pv <= 0
                pv = lastPitch
            else
                lastPitch = pv
            endif
            pitch_cache[frame] = pv
            pitchMin = min(pitchMin, pv)
            pitchMax = max(pitchMax, pv)
        endfor
        removeObject: fullPitch
        if pitchMax <= pitchMin
            pitchMin = 200
            pitchMax = 800
        endif
    endif

    # Preset 7: precompute a short *measured* L/R waveform path per frame.
    # The plotted Lissajous therefore comes from the exact master Sound.
    liss_points = 32
    liss_window = 0.020
    if preset = 7
        selectObject: masterSound
        lissScale = 45 / max(master_volume, 0.01)
        for frame from 0 to total_frames - 1
            .centreT = min(totalDur, frame * frame_step + frame_step / 2)
            .startT = max(0, min(totalDur - liss_window, .centreT - liss_window / 2))
            if .startT < 0
                .startT = 0
            endif
            for .j from 1 to liss_points
                .sampleT = .startT + (.j - 1) * liss_window / (liss_points - 1)
                .sampleNo = round(.sampleT * sr) + 1
                .sampleNo = max(1, min(total_samples, .sampleNo))
                .idx = frame * liss_points + .j
                .leftSample = Get value at sample number: 1, .sampleNo
                .rightSample = Get value at sample number: 2, .sampleNo
                liss_x[.idx] = 50 + lissScale * .leftSample
                liss_y[.idx] = 50 + lissScale * .rightSample
            endfor
        endfor
    endif

    # Continuous audio playback: the whole Sound is started once. Praat's
    # asynchronous directive lets the Demo animation continue while it plays.
    # ----------------------------------------------------------
    # AV PHASE 3: CONTINUOUS AUDIO + REAL-TIME ANIMATION
    # ----------------------------------------------------------
    selectObject: masterSound
    asynchronous Play
    lateFrames = 0

    for frame from 0 to total_frames - 1
        stopwatch
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
            .rmsNorm = min(1, rms_val / rmsMax)
            .radius = 6 + 30 * .rmsNorm
            .color$ = "White"
            if .rmsNorm > 0.70
                .color$ = "Red"
            endif
            demo Paint circle (mm): .color$, 50, 50, .radius

        elsif preset = 2
            .pitchNorm = (pitch_val - pitchMin) / (pitchMax - pitchMin)
            .pitchNorm = max(0, min(1, .pitchNorm))
            .y_pos = 15 + 70 * .pitchNorm
            demo Colour: "{0.2, 0.2, 0.2}"
            demo Draw line: 0, .y_pos, 100, .y_pos
            demo Paint circle (mm): "Cyan", 50, .y_pos, 5

        elsif preset = 3
            .mod = 0.5 - 0.5 * cos(2*pi * 0.5 * t_offset)
            .fmIndex = 5 * .mod
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
            # Each particle's vertical position is the instantaneous frequency
            # of the corresponding audio voice; X remains a slow identity orbit.
            for .v from 1 to 5
                .instF = 200 * .v + 100 * sin(2*pi * (0.1*.v) * t_offset)
                .x = 50 + 38 * cos(2*pi * (0.08*.v) * t_offset + .v)
                .y = 10 + 80 * ((.instF - 100) / 1000)
                .y = max(8, min(92, .y))
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
            .lfo = sin(2*pi * 0.2 * t_offset)
            .pmPhase = 4 * pi * .lfo
            .theta = (t_offset * 2) + .pmPhase
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
            .fmIndex = 6 * sin(2*pi * 0.4 * t_offset)
            .a = 1.0
            .b = 2.0 + 0.25 * .fmIndex
            demo Line width: 2
            .c_val = abs(.fmIndex) / 6
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
            # Measured L/R waveform relation over a 20-ms window.
            demo Line width: 2
            demo Colour: "{0.2, 0.85, 0.95}"
            for .j from 2 to liss_points
                .idx1 = frame * liss_points + .j - 1
                .idx2 = frame * liss_points + .j
                demo Draw line: liss_x[.idx1], liss_y[.idx1], liss_x[.idx2], liss_y[.idx2]
            endfor
            .midIdx = frame * liss_points + round(liss_points / 2)
            demo Paint circle (mm): "White", liss_x[.midIdx], liss_y[.midIdx], 3.5

        endif

        ; HUD: report the actual control / measurement shown.
        demo Font size: 10
        demo Colour: "{0.6, 0.6, 0.6}"
        demo Text: 2, "left", 98, "half", title$
        .hud$ = "t = " + fixed$(t, 2) + " s"
        if preset = 1
            .hud$ = .hud$ + "   |   measured RMS = " + fixed$(rms_val, 3)
        elsif preset = 2
            .hud$ = .hud$ + "   |   measured F0 = " + fixed$(pitch_val, 1) + " Hz"
        elsif preset = 3
            .hud$ = .hud$ + "   |   FM index = " + fixed$(.fmIndex, 2)
        elsif preset = 4
            .hud$ = .hud$ + "   |   Y = instantaneous voice frequency"
        elsif preset = 5
            .hud$ = .hud$ + "   |   PM phase = " + fixed$(.pmPhase, 2) + " rad"
        elsif preset = 6
            .hud$ = .hud$ + "   |   FM index = " + fixed$(.fmIndex, 2)
        elsif preset = 7
            .hud$ = .hud$ + "   |   path = measured L/R samples"
        endif
        demo Text: 2, "left", 94, "half", .hud$
        demoShow()

        .renderTime = stopwatch
        .frameBudget = min(frame_step, totalDur - t)
        .sleepTime = .frameBudget - .renderTime
        if .sleepTime > 0
            sleep(.sleepTime)
        else
            lateFrames = lateFrames + 1
        endif
    endfor

    removeObject: masterSound
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Font size: 14
    demo Colour: "White"
    demo Text: 50, "centre", 54, "half", "AV run complete."
    demo Font size: 8
    demo Colour: "{0.55, 0.55, 0.55}"
    demo Text: 50, "centre", 45, "half", "late visual frames: " + string$(lateFrames)
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

    # Stereo master. The same X trajectory used by the visual movement controls
    # equal-power pan, giving Poly mode a real audiovisual correspondence.
    masterSound = Create Sound from formula: "poly", 2, 0, totalDur, sr, "0"

    for v from 1 to n_voices
        vf = voice_freq[v]
        vp = voice_phase[v]
        voiceAmp = 0.8 / sqrt(n_voices)

        if synthesis_type = 1
            voiceFormula$ = "sin(2*pi*vf*(x+time_offset) + vp)"
        elsif synthesis_type = 2
            voiceFormula$ = "sin(2*pi*vf*(x+time_offset) + 3*sin(2*pi*(2*vf)*(x+time_offset) + 2*vp) + vp)"
        elsif synthesis_type = 3
            voiceFormula$ = "(0.5 + 0.5*sin(2*pi*4*(x+time_offset) + vp)) * sin(2*pi*vf*(x+time_offset) + vp)"
        elsif synthesis_type = 4
            voiceFormula$ = "0.55*sin(2*pi*vf*(x+time_offset)+vp) + 0.25*sin(2*pi*(2*vf)*(x+time_offset)+2*vp) + 0.13*sin(2*pi*(3*vf)*(x+time_offset)+3*vp) + 0.07*sin(2*pi*(4*vf)*(x+time_offset)+4*vp)"
        else
            voiceFormula$ = "sin(2*pi*vf*(x+time_offset)+vp) + 0.5*sin(2*pi*(2*vf)*(x+time_offset)+2*vp) + 0.33*sin(2*pi*(3*vf)*(x+time_offset)+3*vp) + 0.25*sin(2*pi*(4*vf)*(x+time_offset)+4*vp) + 0.2*sin(2*pi*(5*vf)*(x+time_offset)+5*vp) + 0.17*sin(2*pi*(6*vf)*(x+time_offset)+6*vp)"
        endif

        voiceSound = Create Sound from formula: "av_voice", 1, 0, totalDur, sr, voiceFormula$
        selectObject: voiceSound
        Formula: "self * voiceAmp"

        # Pan trajectory = visual X coordinate / 100, with safe margins.
        if movement = 1
            panExpr$ = "0.5 + 0.35*cos(2*pi*0.4*(x+time_offset) + vp)"
        elsif movement = 2
            panExpr$ = "0.5 + 0.01*(12 + 28*abs(sin(2*pi*0.25*(x+time_offset) + vp*0.4)))*cos(2*pi*0.5*(x+time_offset) + vp)"
        elsif movement = 3
            panExpr$ = "0.5 + 0.38*sin(2*pi*(0.30 + 0.04*v)*(x+time_offset) + vp)"
        elsif movement = 4
            panExpr$ = "0.5 + 0.38*sin(2*pi*0.35*(x+time_offset) + vp)"
        else
            panExpr$ = "0.5 + 0.01*(8 + 35*(0.5 + 0.5*sin(2*pi*0.28*(x+time_offset) + vp)))*cos(vp)"
        endif

        sourceVoiceID = voiceSound
        selectObject: masterSound
        Formula: "self + object[sourceVoiceID, 1, col] * (if row = 1 then sqrt(1 - (" + panExpr$ + ")) else sqrt(" + panExpr$ + ") fi)"
        removeObject: voiceSound
    endfor

    selectObject: masterSound
    if edgeFade > 0
        fadeOutStart = totalDur - edgeFade
        Formula: "if x < edgeFade then self * (x/edgeFade) else if x > fadeOutStart then self * ((totalDur-x)/edgeFade) else self fi fi"
    endif
    if master_volume > 0
        Scale peak: master_volume
    else
        Formula: "0"
    endif

    # ----------------------------------------------------------
    # POLY PHASE 2: VISUAL STATE
    # ----------------------------------------------------------

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
    # POLY PHASE 3: CONTINUOUS AUDIO + REAL-TIME ANIMATION
    # ----------------------------------------------------------
    selectObject: masterSound
    asynchronous Play
    lateFrames = 0

    for frame from 0 to total_frames - 1
        stopwatch
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
        demo Text: 2, "left", 98, "half", "Poly Composition  |  voices: " + string$(n_voices) + "  |  visual X -> stereo pan"
        demo Text: 2, "left", 94, "half", "t = " + fixed$(t, 2) + " s"
        demoShow()

        .renderTime = stopwatch
        .frameBudget = min(frame_step, totalDur - t)
        .sleepTime = .frameBudget - .renderTime
        if .sleepTime > 0
            sleep(.sleepTime)
        else
            lateFrames = lateFrames + 1
        endif

    endfor   ; end animation loop

    removeObject: masterSound
    demo Paint rectangle: "Black", 0, 100, 0, 100
    demo Font size: 14
    demo Colour: "White"
    demo Text: 50, "centre", 54, "half", "Composition complete."
    demo Font size: 8
    demo Colour: "{0.55, 0.55, 0.55}"
    demo Text: 50, "centre", 45, "half", "late visual frames: " + string$(lateFrames)
    demoShow()

endif   ; end mode branch

until 0
