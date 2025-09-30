sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if col < 10000 then self[1,col]*exp(-col/5000) else self[1,col] fi"
To Sound
Scale peak: 0.90
Play