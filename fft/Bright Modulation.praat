sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if col < 10000 then self[1,col]*0.5*(1+sin(col/1000)) else self[1,col] fi"
To Sound
Scale peak: 0.95
Play