# STEREO SHIMMER — different tap sets per channel via alternating sign/jitter
Copy: "stereo_shimmer"
select Sound stereo_shimmer
ch = Get number of channels
n = 80
baseAmp = 0.24
minD = 0.02
maxD = 1.2

for k from 1 to n
    delay = minD + (maxD - minD) * k/n + randomUniform(-0.006,0.006)
    sgn = if (k mod 4 < 2) then 1 else -1 fi
    a = baseAmp * (0.95 ^ k) * sgn
    Formula: "if x > delay then self + a * self(x - delay) else self fi"
    if k mod 20 = 0
        Scale peak: 0.98
    endif
endfor

# sparkle pass (tiny HF bump)
Formula: "self + 0.25*(self - self(x - 1/44100))"
Scale peak: 0.98
Play

