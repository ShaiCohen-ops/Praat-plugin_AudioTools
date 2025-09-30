# RIBBON SHIMMER — log-spaced delays produce a silky, non-mushy tail
Copy: "ribbon_shimmer"
select Sound ribbon_shimmer

n = 95
baseAmp = 0.24
minD = 0.015
maxD = 1.35

for k from 1 to n
    # log spacing from minD→maxD to avoid dense LF clumps
    u = k/n
    delay = minD * ( (maxD/minD) ^ u )
    a = baseAmp * (0.955 ^ k) * (if (k mod 3) = 0 then -1 else 1 fi)

    # tiny HF lift + jitter to keep it lively
    j = randomUniform(-0.003, 0.003)
    Formula: "if x > delay + j then self + a * ( self(x - (delay + j)) + 0.25*(self(x - (delay + j)) - self(x - (delay + j) - 1/44100)) ) else self fi"

    if k mod 20 = 0
        Scale peak: 0.98
    endif
endfor

Scale peak: 0.98
Play

