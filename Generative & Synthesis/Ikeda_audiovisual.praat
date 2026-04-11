# ============================================================
# Praat AudioTools - Ikeda_audiovisual.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   IKEDA/SYN Tetralogy — Ryoji Ikeda-inspired audiovisual renderer.
#   Generates synchronized audio and visuals in real time within Praat's
#   demo window, modelling four Ikeda works at sample level:
#
#   Works:
#     1. test pattern   — Barcodes & Glitch
#     2. datamatics     — Grids & Scans
#     3. spectra        — Drones & Light
#     4. supercodex     — Genome Barcodes
#
#   Pipeline: (1) build full master audio, (2) pre-slice into
#   frame-length chunks, (3) play each chunk while drawing the
#   matching visual frame in the demo window.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: Ikeda Audiovisual.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

beginPause: "IKEDA/SYN — Parameters"
    comment: "Select a Ryoji Ikeda-inspired audiovisual model:"
    optionmenu: "Work", 1
        option: "1. test pattern (Barcodes & Glitch)"
        option: "2. datamatics (Grids & Scans)"
        option: "3. spectra (Drones & Light)"
        option: "4. supercodex (Genome Barcodes)"
    real: "Total duration", 16
    boolean: "Enable color", 1
    real: "Master volume", 0.9
endPause: "Run", 1

totalDur = total_duration
step = 0.125
sr = 44100
total_frames = floor(totalDur / step)

if work = 1
    title$ = "test pattern"
elsif work = 2
    title$ = "datamatics"
elsif work = 3
    title$ = "spectra"
elsif work = 4
    title$ = "supercodex"
endif

# ── AUDIO GENERATORS ─────────────────────────────────────────

procedure mixIn: .ev, .t
    selectObject: .ev
    Multiply: master_volume
    .startSample = max(1, round(.t * sr) + 1)
    .len = Get number of samples
    
    # Fast array math using Praat's Formula
    selectObject: masterSound
    Formula: "self + if col >= .startSample and col < (.startSample + .len) then object['.ev', 1, col - .startSample + 1] else 0 fi"
    removeObject: .ev
endproc

procedure makeKick: .t
    Create Sound from formula: "kick", 1, 0, 0.15, sr, "0.9 * sin(2*pi*50*x) * exp(-x / 0.05)"
    @mixIn: selected("Sound"), .t
endproc

procedure makeBeep: .t
    Create Sound from formula: "beep", 1, 0, 0.04, sr, "0.3 * sin(2*pi*10000*x) * exp(-x / 0.01)"
    @mixIn: selected("Sound"), .t
endproc

procedure makeClick: .t
    Create Sound from formula: "click", 1, 0, 0.015, sr, "0.4 * randomGauss(0,1) * exp(-x / 0.005)"
    @mixIn: selected("Sound"), .t
endproc

procedure makeSweep: .t
    Create Sound from formula: "sweep", 1, 0, 0.2, sr, "0.2 * sin(2*pi * (1000 + (5000-1000)/(2*0.2) * x) * x) * exp(-x / 0.1)"
    @mixIn: selected("Sound"), .t
endproc

procedure makeDrone: .dur
    Create Sound from formula: "drone", 1, 0, .dur, sr, "(0.3*sin(2*pi*50*x)) + (0.3*sin(2*pi*52*x)) + (0.15*sin(2*pi*100*x)) + (0.08*sin(2*pi*150*x))"
    @mixIn: selected("Sound"), 0
endproc

procedure makeChime: .t
    Create Sound from formula: "chime", 1, 0, 0.5, sr, "0.3 * sin(2*pi*4000*x) * exp(-x / 0.1)"
    @mixIn: selected("Sound"), .t
endproc

# ── VISUAL GENERATORS ────────────────────────────────────────

procedure drawTestPattern: .f
    demo Paint rectangle: "Black", 0, 100, 0, 100
    .isKick = (.f mod 8 = 0) or (.f mod 16 = 11)
    .isBeep = (.f mod 4 = 2)
    .isGlitch = (.f mod 32 >= 24)

    if .isKick
        demo Paint rectangle: "White", 10, 40, 0, 100
        demo Paint rectangle: "White", 65, 85, 0, 100
    endif
    if .isBeep
        demo Paint rectangle: "White", 5, 6, 0, 100
        demo Paint rectangle: "White", 50, 52, 0, 100
        demo Paint rectangle: "White", 92, 93, 0, 100
    endif
    if .isGlitch
        for .b from 1 to 15
            .seed = (.f * 17 + .b * 23) mod 100
            .width = (.seed mod 4) + 0.5
            demo Paint rectangle: "White", .seed, .seed + .width, 0, 100
        endfor
    endif
    demo Paint rectangle: "White", 0, 100, 49.5, 50.5
    demoShow()
endproc

procedure drawDatamatics: .f
    demo Paint rectangle: "Black", 0, 100, 0, 100
    # Reduced to 10x10 grid using rectangles (not circles) — 10x faster
    for .x from 1 to 10
        for .y from 1 to 10
            .rx = .x * 10 - 5
            .ry = .y * 10 - 5
            .on = ((.x * .y * .f) mod 13) < 2
            if .on
                demo Paint rectangle: "White", .rx - 2, .rx + 2, .ry - 2, .ry + 2
            else
                demo Paint rectangle: "{0.2,0.2,0.2}", .rx - 1, .rx + 1, .ry - 1, .ry + 1
            endif
        endfor
    endfor
    
    .scanY = 100 - ((.f * 5) mod 100)
    if enable_color
        demo Paint rectangle: "{0.0, 0.8, 1.0}", 0, 100, .scanY, .scanY + 2
    else
        demo Paint rectangle: "White", 0, 100, .scanY, .scanY + 2
    endif
    
    if .f mod 16 = 8
        demo Paint rectangle: "White", 0, 100, 45, 55
    endif
    demoShow()
endproc

procedure drawSpectra: .f
    demo Paint rectangle: "Black", 0, 100, 0, 100
    .isStrobe = (.f mod 32 = 0) or (.f mod 32 = 1)
    
    if .isStrobe
        demo Paint rectangle: "White", 0, 100, 0, 100
    else
        .pulse = 10 + 5 * sin(.f * 0.2)
        if enable_color
            .r = 0.9 + 0.1 * sin(.f * 0.3)
            .b = 0.7 - 0.1 * sin(.f * 0.3)
            demo Paint rectangle: "{'.r', 0.95, '.b'}", 50 - .pulse, 50 + .pulse, 0, 100
        else
            demo Paint rectangle: "White", 50 - .pulse, 50 + .pulse, 0, 100
        endif
        demo Paint rectangle: "{0.3,0.3,0.3}", 20, 21, 0, 100
        demo Paint rectangle: "{0.3,0.3,0.3}", 79, 80, 0, 100
    endif
    demoShow()
endproc

procedure drawSupercodex: .f
    demo Paint rectangle: "Black", 0, 100, 0, 100
    for .i from 1 to 100
        .seed = (.i * 31 + .f * 7) mod 100
        .gray = .seed / 100
        demo Paint rectangle: "{'.gray', '.gray', '.gray'}", .i * 1.0 - 0.5, .i * 1.0 + 0.5, 0, 100
    endfor
    demoShow()
endproc

# ============================================================
# PHASE 1: GENERATE MASTER AUDIO
# ============================================================
demo Erase all
demo Select inner viewport: 0, 100, 0, 100
demo Axes: 0, 100, 0, 100

masterSound = Create Sound from formula: "master", 1, 0, totalDur, sr, "0"

for frame from 0 to total_frames - 1
    # HUD Feedback
    if frame mod 10 = 0
        demo Paint rectangle: "Black", 0, 100, 0, 100
        demo Font size: 14
        demo Colour: "White"
        demo Text: 50, "centre", 50, "half", "Building " + title$ + "... " + string$(round(frame / total_frames * 100)) + "%"
        demoShow()
    endif

    t = frame * step
    
    if work = 1
        if (frame mod 8 = 0) or (frame mod 16 = 11)
            @makeKick: t
        endif
        if frame mod 4 = 2
            @makeBeep: t
        endif
        if frame mod 32 >= 24
            @makeClick: t
        endif
    elsif work = 2
        if frame mod 4 = 0
            @makeClick: t
        endif
        if frame mod 16 = 8
            @makeSweep: t
        endif
        if (frame mod 8 = 4)
            @makeBeep: t
        endif
    elsif work = 3
        if frame = 0
            @makeDrone: totalDur
        endif
        if frame mod 32 = 0
            @makeChime: t
        endif
    elsif work = 4
        # Supercodex dense data rhythm
        if frame mod 2 = 0
            @makeClick: t
        endif
        if frame mod 8 = 0
            @makeKick: t
        endif
    endif
endfor

selectObject: masterSound
Scale peak: 0.99

# ============================================================
# PHASE 2: PRE-SLICE AUDIO CHUNKS
# ============================================================
demo Paint rectangle: "Black", 0, 100, 0, 100
demo Font size: 14
demo Colour: "White"
demo Text: 50, "centre", 50, "half", "Preparing playback..."
demoShow()

for frame from 0 to total_frames - 1
    t = frame * step
    t_end = t + step
    selectObject: masterSound
    chunk_id[frame] = Extract part: t, t_end, "rectangular", 1, "no"
endfor

# ============================================================
# PHASE 3: FRAME-BY-FRAME SYNC PLAYBACK
# ============================================================
for frame from 0 to total_frames - 1
    if work = 1
        @drawTestPattern: frame
    elsif work = 2
        @drawDatamatics: frame
    elsif work = 3
        @drawSpectra: frame
    elsif work = 4
        @drawSupercodex: frame
    endif
    
    selectObject: chunk_id[frame]
    Play
    removeObject: chunk_id[frame]
endfor

# ── FINAL FRAME ──────────────────────────────────────────────
demo Paint rectangle: "Black", 0, 100, 0, 100
demo Paint rectangle: "White", 0, 100, 49.8, 50.2
demo Font size: 14
demo Colour: "White"
demo Text: 50, "centre", 10, "half", title$ + " / praat"
demoShow()

appendInfoLine: "Playback complete."