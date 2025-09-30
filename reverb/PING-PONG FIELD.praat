# PING-PONG FIELD — alternating tap families with tiny offsets & sign flips
Copy... "pingpong_field"
select Sound pingpong_field

n = 90
baseAmp = 0.25
minD = 0.02
maxD = 1.20

for k from 1 to n
    # base delay ramp
    t = minD + (maxD - minD) * k / n

    # small ping-pong offset (block if/else — no inline if)
    if k mod 2 = 0
        off = 0.003
    else
        off = -0.003
    endif

    delay = t + off + randomUniform(-0.004, 0.004)

    # sign flip to decorrelate LF buildup (block if/else)
    if k mod 4 < 2
        sgn = 1
    else
        sgn = -1
    endif

    a = baseAmp * (0.95 ^ k) * (0.9 + 0.2 * randomUniform(0,1)) * sgn

    # mild HF sparkle: add a 1-sample finite difference term
    Formula: "if x > delay then self + a * ( self(x - delay) + 0.3*(self(x - delay) - self(x - delay - 1/44100)) ) else self fi"

    if k mod 20 = 0
        Scale peak: 0.98
    endif
endfor

Scale peak: 0.98
Play
