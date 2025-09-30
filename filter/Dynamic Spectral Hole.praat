partial_octave = 2
a = selected("Sound")
c = To Pitch: 0, 75, 600
lo = Get mean: 0, 0, "Hertz"
hi = lo * partial_octave
select a

d = To Spectrum... n
Formula... if x>=lo and x<=hi then self*0.1 else self fi
b = To Sound
Scale peak: 0.99
select b
Play
removeObject: c, d