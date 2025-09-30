# Very low-bit quantization
lo = 200
hi = 3000
steps = 2
To Spectrum... n
Formula... if x>=lo and x<=hi then self * (round(2 * (x-lo)/(hi-lo)) / 2) else self*0.5 fi
To Sound
Scale peak: 0.99
Play