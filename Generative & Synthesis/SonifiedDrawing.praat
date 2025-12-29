# ============================================================
# Praat AudioTools - SonifiedDrawing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SonifiedDrawing
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
form SonifiedDrawingMorph
    comment Shapes
    optionmenu shape1 1
        option Spiral
        option Circle
        option Square
        option Triangle
        option Lissajous
        option Rose
        option Figure8
    optionmenu shape2 1
        option Spiral
        option Circle
        option Square
        option Triangle
        option Lissajous
        option Rose
        option Figure8
    comment Scales
    optionmenu scale 1
        option Original (Unquantized)
        option PentatonicMinor
        option Major
        option NaturalMinor
        option Dorian
        option PentatonicMajor
    comment Tones
    optionmenu tone 1
        option OneSine_Fast
        option TwoSines_Richer
    comment Morphing
    real morphSpeed 0.01
    comment Drawing
    integer steps 200
    real dur 0.04
    real speed 0.25
    real radiusstep 0.22
    real centerx 50
    real centery 50
    real lissajousa 3
    real lissajousb 2
    real rosek 5
    real tonichz 110
    integer samplerate 22050
    integer playEvery 1
endform

Erase all
prevx = centerx
prevy = centery
prevsx = prevx / 100
prevsy = prevy / 100
morphProgress = 0

for t from 1 to steps
    morphProgress = morphProgress + morphSpeed
    if morphProgress > 1
        morphProgress = 0
    endif

    angle = t * speed

    # --- Shape 1 ---
    px1 = centerx
    py1 = centery
    if shape1 = 1
        radius = t * radiusstep
        px1 = centerx + radius * cos(angle)
        py1 = centery + radius * sin(angle)
    elsif shape1 = 2
        r0 = 30
        px1 = centerx + r0 * cos(angle)
        py1 = centery + r0 * sin(angle)
    elsif shape1 = 3
        s = 60
        half = s / 2
        p = t / steps
        p4 = p * 4
        if p4 < 1
            px1 = centerx - half + p4 * s
            py1 = centery - half
        elsif p4 < 2
            px1 = centerx + half
            py1 = centery - half + (p4 - 1) * s
        elsif p4 < 3
            px1 = centerx + half - (p4 - 2) * s
            py1 = centery + half
        else
            px1 = centerx - half
            py1 = centery + half - (p4 - 3) * s
        endif
    elsif shape1 = 4
        s = 60
        h = s * sqrt(3) / 2
        ax = centerx
        ay = centery - h / 2
        bx = centerx + s / 2
        by = centery + h / 2
        cxv = centerx - s / 2
        cyv = centery + h / 2
        p = t / steps
        p3 = p * 3
        if p3 < 1
            px1 = ax + (bx - ax) * p3
            py1 = ay + (by - ay) * p3
        elsif p3 < 2
            u = p3 - 1
            px1 = bx + (cxv - bx) * u
            py1 = by + (cyv - by) * u
        else
            u = p3 - 2
            px1 = cxv + (ax - cxv) * u
            py1 = cyv + (ay - cyv) * u
        endif
    elsif shape1 = 5
        aamp = 30
        bamp = 30
        a = lissajousa
        b = lissajousb
        px1 = centerx + aamp * sin(a * angle)
        py1 = centery + bamp * sin(b * angle + pi/2)
    elsif shape1 = 6
        rmax = 35
        k = rosek
        r = rmax * cos(k * angle)
        px1 = centerx + r * cos(angle)
        py1 = centery + r * sin(angle)
    else
        a8 = 35
        denom = 1 + sin(angle) * sin(angle)
        px1 = centerx + a8 * cos(angle) / denom
        py1 = centery + a8 * sin(angle) * cos(angle) / denom
    endif

    # --- Shape 2 ---
    px2 = centerx
    py2 = centery
    if shape2 = 1
        radius = t * radiusstep
        px2 = centerx + radius * cos(angle)
        py2 = centery + radius * sin(angle)
    elsif shape2 = 2
        r0 = 30
        px2 = centerx + r0 * cos(angle)
        py2 = centery + r0 * sin(angle)
    elsif shape2 = 3
        s = 60
        half = s / 2
        p = t / steps
        p4 = p * 4
        if p4 < 1
            px2 = centerx - half + p4 * s
            py2 = centery - half
        elsif p4 < 2
            px2 = centerx + half
            py2 = centery - half + (p4 - 1) * s
        elsif p4 < 3
            px2 = centerx + half - (p4 - 2) * s
            py2 = centery + half
        else
            px2 = centerx - half
            py2 = centery + half - (p4 - 3) * s
        endif
    elsif shape2 = 4
        s = 60
        h = s * sqrt(3) / 2
        ax = centerx
        ay = centery - h / 2
        bx = centerx + s / 2
        by = centery + h / 2
        cxv = centerx - s / 2
        cyv = centery + h / 2
        p = t / steps
        p3 = p * 3
        if p3 < 1
            px2 = ax + (bx - ax) * p3
            py2 = ay + (by - ay) * p3
        elsif p3 < 2
            u = p3 - 1
            px2 = bx + (cxv - bx) * u
            py2 = by + (cyv - by) * u
        else
            u = p3 - 2
            px2 = cxv + (ax - cxv) * u
            py2 = cyv + (ay - cyv) * u
        endif
    elsif shape2 = 5
        aamp = 30
        bamp = 30
        a = lissajousa
        b = lissajousb
        px2 = centerx + aamp * sin(a * angle)
        py2 = centery + bamp * sin(b * angle + pi/2)
    elsif shape2 = 6
        rmax = 35
        k = rosek
        r = rmax * cos(k * angle)
        px2 = centerx + r * cos(angle)
        py2 = centery + r * sin(angle)
    else
        a8 = 35
        denom = 1 + sin(angle) * sin(angle)
        px2 = centerx + a8 * cos(angle) / denom
        py2 = centery + a8 * sin(angle) * cos(angle) / denom
    endif

    # --- Morph between shapes ---
    px = px1 * (1 - morphProgress) + px2 * morphProgress
    py = py1 * (1 - morphProgress) + py2 * morphProgress

    # --- Draw the line ---
    sx = px / 100
    sy = py / 100
    Draw line: prevsx, prevsy, sx, sy

    # --- Calculate distance from center ---
    dist = sqrt((px - centerx)^2 + (py - centery)^2)

    # --- Calculate frequency based on scale ---
    if scale = 1
        base_freq = 140 + 3 * dist
    else
        if scale = 2
            n = 5
            d = floor(dist) mod n
            if d = 0
                semi = 0
            elsif d = 1
                semi = 3
            elsif d = 2
                semi = 5
            elsif d = 3
                semi = 7
            else
                semi = 10
            endif
        elsif scale = 3
            n = 7
            d = floor(dist) mod n
            if d = 0
                semi = 0
            elsif d = 1
                semi = 2
            elsif d = 2
                semi = 4
            elsif d = 3
                semi = 5
            elsif d = 4
                semi = 7
            elsif d = 5
                semi = 9
            else
                semi = 11
            endif
        elsif scale = 4
            n = 7
            d = floor(dist) mod n
            if d = 0
                semi = 0
            elsif d = 1
                semi = 2
            elsif d = 2
                semi = 3
            elsif d = 3
                semi = 5
            elsif d = 4
                semi = 7
            elsif d = 5
                semi = 8
            else
                semi = 10
            endif
        elsif scale = 5
            n = 7
            d = floor(dist) mod n
            if d = 0
                semi = 0
            elsif d = 1
                semi = 2
            elsif d = 2
                semi = 3
            elsif d = 3
                semi = 5
            elsif d = 4
                semi = 7
            elsif d = 5
                semi = 9
            else
                semi = 10
            endif
        else
            n = 5
            d = floor(dist) mod n
            if d = 0
                semi = 0
            elsif d = 1
                semi = 2
            elsif d = 2
                semi = 4
            elsif d = 3
                semi = 7
            else
                semi = 9
            endif
        endif
        oct = floor(dist / 8) * 12
        semitotal = semi + oct
        base_freq = tonichz * exp(ln(2) * (semitotal / 12))
    endif

    # --- Panning and amplitude ---
    pan = (px - centerx) / 50
    if pan > 1
        pan = 1
    endif
    if pan < -1
        pan = -1
    endif
    amp = 0.4 + (py / 100) * 0.5
    if amp < 0
        amp = 0
    endif
    if amp > 1
        amp = 1
    endif
    panangle = (pan + 1) * (pi / 4)
    leftgain = cos(panangle)
    rightgain = sin(panangle)

    # --- Envelope ---
    env$ = "(sin(pi*x/'dur')*sin(pi*x/'dur'))"

    # --- Tone ---
    if tone = 1
        tone$ = "sin(2*pi*'base_freq'*x)"
    else
        tone$ = "sin(2*pi*'base_freq'*x)+0.3*sin(2*pi*'base_freq'*2*x)"
    endif

    # --- Create sound ---
    leftFormula$  = "('leftgain'*'amp')*("  + env$ + ")*(" + tone$ + ")"
    rightFormula$ = "('rightgain'*'amp')*(" + env$ + ")*(" + tone$ + ")"
    Create Sound from formula: "L" + string$(t), 1, 0, dur, samplerate, leftFormula$
    Create Sound from formula: "R" + string$(t), 1, 0, dur, samplerate, rightFormula$
    select Sound L't'
    plus Sound R't'
    Combine to stereo
    Rename: "N" + string$(t)

    # --- Play sound ---
    if ((t - 1) mod playEvery) = 0
        select Sound N't'
        Play
    endif

    # --- Clean up ---
    select all
    Remove

    # --- Update previous coordinates ---
    prevx = px
    prevy = py
    prevsx = sx
    prevsy = sy
endfor
