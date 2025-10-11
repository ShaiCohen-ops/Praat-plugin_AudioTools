form SonifiedDrawingFast
    optionmenu shape 1
        option Spiral
        option Circle
        option Square
        option Triangle
        option Lissajous
        option Rose
        option Figure8
    optionmenu scale 1
        option Original (Unquantized)
        option PentatonicMinor
        option Major
        option NaturalMinor
        option Dorian
        option PentatonicMajor
    optionmenu tone 1
        option OneSine_Fast
        option TwoSines_Richer
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

for t from 1 to steps
    angle = t * speed
    px = centerx
    py = centery

    if shape = 1
        radius = t * radiusstep
        px = centerx + radius * cos(angle)
        py = centery + radius * sin(angle)
    elsif shape = 2
        r0 = 30
        px = centerx + r0 * cos(angle)
        py = centery + r0 * sin(angle)
    elsif shape = 3
        s = 60
        half = s / 2
        p = t / steps
        p4 = p * 4
        if p4 < 1
            px = centerx - half + p4 * s
            py = centery - half
        elsif p4 < 2
            px = centerx + half
            py = centery - half + (p4 - 1) * s
        elsif p4 < 3
            px = centerx + half - (p4 - 2) * s
            py = centery + half
        else
            px = centerx - half
            py = centery + half - (p4 - 3) * s
        endif
    elsif shape = 4
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
            px = ax + (bx - ax) * p3
            py = ay + (by - ay) * p3
        elsif p3 < 2
            u = p3 - 1
            px = bx + (cxv - bx) * u
            py = by + (cyv - by) * u
        else
            u = p3 - 2
            px = cxv + (ax - cxv) * u
            py = cyv + (ay - cyv) * u
        endif
    elsif shape = 5
        aamp = 30
        bamp = 30
        a = lissajousa
        b = lissajousb
        px = centerx + aamp * sin(a * angle)
        py = centery + bamp * sin(b * angle + pi/2)
    elsif shape = 6
        rmax = 35
        k = rosek
        r = rmax * cos(k * angle)
        px = centerx + r * cos(angle)
        py = centery + r * sin(angle)
    else
        a8 = 35
        denom = 1 + sin(angle) * sin(angle)
        px = centerx + a8 * cos(angle) / denom
        py = centery + a8 * sin(angle) * cos(angle) / denom
    endif

    sx = px / 100
    sy = py / 100
    Draw line: prevsx, prevsy, sx, sy

    dist = sqrt((px - centerx)^2 + (py - centery)^2)

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

    env$ = "(sin(pi*x/'dur')*sin(pi*x/'dur'))"
    if tone = 1
        tone$ = "sin(2*pi*'base_freq'*x)"
    else
        tone$ = "sin(2*pi*'base_freq'*x)+0.3*sin(2*pi*'base_freq'*2*x)"
    endif
    leftFormula$  = "('leftgain'*'amp')*("  + env$ + ")*(" + tone$ + ")"
    rightFormula$ = "('rightgain'*'amp')*(" + env$ + ")*(" + tone$ + ")"

    Create Sound from formula: "L" + string$(t), 1, 0, dur, samplerate, leftFormula$
    Create Sound from formula: "R" + string$(t), 1, 0, dur, samplerate, rightFormula$
    select Sound L't'
    plus Sound R't'
    Combine to stereo
    Rename: "N" + string$(t)

    if ((t - 1) mod playEvery) = 0
        select Sound N't'
        Play
    endif

    select all
    Remove

    prevx = px
    prevy = py
    prevsx = sx
    prevsy = sy
endfor
